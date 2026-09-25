import AVFoundation
import Speech

/// Captures microphone audio (SPEC §6.1). Each tap buffer is copied, written to the audio file,
/// converted to the analyzer's format and queued for transcription.
final class AudioRecorder: @unchecked Sendable {
    enum RecorderError: LocalizedError {
        case noInput
        case couldNotStart(Error)

        var errorDescription: String? {
            switch self {
            case .noInput: "No microphone input is available."
            case .couldNotStart(let error): "The microphone couldn't start: \(error.localizedDescription)"
            }
        }
    }

    private let engine = AVAudioEngine()
    /// Serialises all buffer work off the realtime audio thread.
    private let queue = DispatchQueue(label: "dev.harryday.murmur.audio", qos: .userInitiated)
    private var configurationObserver: NSObjectProtocol?

    // Only touched on `queue` while recording.
    private var file: AVAudioFile?
    private var fileConverter: AVAudioConverter?
    private var analyzerConverter: AVAudioConverter?
    private var analyzerFormat: AVAudioFormat?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var levelHandler: (@Sendable (Float) -> Void)?

    /// 16-bit PCM, mono, for the temporary capture file.
    static func pcmSettings(sampleRate: Double) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
        ]
    }

    var inputFormat: AVAudioFormat { engine.inputNode.outputFormat(forBus: 0) }

    func start(
        fileURL: URL,
        fileSettings: [String: Any],
        analyzerFormat: AVAudioFormat,
        continuation: AsyncStream<AnalyzerInput>.Continuation,
        level: @escaping @Sendable (Float) -> Void
    ) throws {
        let file = try AVAudioFile(forWriting: fileURL, settings: fileSettings, commonFormat: .pcmFormatFloat32, interleaved: false)
        queue.sync {
            self.file = file
            self.analyzerFormat = analyzerFormat
            self.continuation = continuation
            self.levelHandler = level
        }
        try installTapAndStart()

        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            Log.recording.notice("Audio configuration changed; restarting the tap")
            self?.restartTap()
        }
    }

    /// Stops capture and drains queued buffers. The audio file is closed when this returns.
    func stop() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        queue.sync {
            file = nil
            fileConverter = nil
            analyzerConverter = nil
            continuation = nil
            levelHandler = nil
        }
    }

    private func installTapAndStart() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw RecorderError.noInput }

        queue.sync {
            if let file {
                fileConverter = Self.converter(from: format, to: file.processingFormat)
            }
            if let analyzerFormat {
                analyzerConverter = Self.converter(from: format, to: analyzerFormat)
            }
        }

        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self, let copy = buffer.deepCopy() else { return }
            let box = BufferBox(buffer: copy)
            self.queue.async { self.process(box.buffer) }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw RecorderError.couldNotStart(error)
        }
    }

    private func restartTap() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        do {
            try installTapAndStart()
        } catch {
            Log.recording.error("Couldn't restart after a configuration change: \(String(describing: error), privacy: .public)")
        }
    }

    /// Runs on `queue`.
    private func process(_ buffer: AVAudioPCMBuffer) {
        if let file, let fileConverter, let converted = Self.convert(buffer, with: fileConverter) {
            do {
                try file.write(from: converted)
            } catch {
                Log.recording.error("Audio write failed: \(String(describing: error), privacy: .public)")
            }
        }
        if let analyzerConverter, let converted = Self.convert(buffer, with: analyzerConverter) {
            continuation?.yield(AnalyzerInput(buffer: converted))
        }
        levelHandler?(Self.level(of: buffer))
    }

    private static func converter(from input: AVAudioFormat, to output: AVAudioFormat) -> AVAudioConverter? {
        let converter = AVAudioConverter(from: input, to: output)
        converter?.primeMethod = .none
        converter?.downmix = true
        return converter
    }

    private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else { return nil }

        var error: NSError?
        nonisolated(unsafe) var supplied = false
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil, output.frameLength > 0 else { return nil }
        return output
    }

    /// RMS of the first channel, mapped from -50…0 dBFS to 0…1.
    static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) {
            sum += samples[index] * samples[index]
        }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        return min(max((decibels + 50) / 50, 0), 1)
    }
}

/// Moves a copied buffer to the audio queue. The copy is never touched again on the tap thread.
private struct BufferBox: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}

extension AVAudioPCMBuffer {
    /// Tap buffers are reused by the engine, so they must be copied before queueing.
    func deepCopy() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else { return nil }
        copy.frameLength = frameLength
        let source = UnsafeMutableAudioBufferListPointer(mutableAudioBufferList)
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (from, to) in zip(source, destination) {
            guard let fromData = from.mData, let toData = to.mData else { continue }
            memcpy(toData, fromData, Int(min(from.mDataByteSize, to.mDataByteSize)))
        }
        return copy
    }
}
