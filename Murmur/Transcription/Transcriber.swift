import AVFoundation
import Foundation
import Speech

/// The live transcript while recording: finalized text plus a replaceable volatile tail.
struct LiveTranscript: Equatable, Sendable {
    var finalized = ""
    var volatile = ""
}

/// Records and transcribes live. Implemented with SpeechAnalyzer; faked in tests.
@MainActor
protocol Transcribing: AnyObject {
    /// Gets a fresh analyzer ready for `locale`, installing speech assets if needed.
    func prepare(locale: Locale, assetProgress: @escaping @MainActor (Double) -> Void) async throws
    func start(
        locale: Locale,
        onUpdate: @escaping @MainActor (LiveTranscript) -> Void,
        onLevel: @escaping @MainActor (Float) -> Void
    ) async throws
    /// Stops in the order SPEC §6.2 requires and returns everything finalized.
    func stop() async -> CapturedRecording
    /// Stops and throws the recording away.
    func discard() async
}

enum TranscriberError: LocalizedError {
    case unsupportedLocale(String)
    case noAudioFormat

    var errorDescription: String? {
        switch self {
        case .unsupportedLocale(let locale): "Speech recognition doesn't support \(locale) on this Mac."
        case .noAudioFormat: "The speech analyzer didn't offer an audio format."
        }
    }
}

@MainActor
final class Transcriber: Transcribing {
    private struct Prepared {
        let locale: Locale
        let analyzer: SpeechAnalyzer
        let module: any SpeechModule
        let format: AVAudioFormat
    }

    private var prepared: Prepared?
    private var preparing: Task<Void, Error>?
    private var active: Prepared?
    private let recorder = AudioRecorder()
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzerTask: Task<Void, Error>?
    private var consumerTask: Task<Void, Never>?

    private var segments: [TranscriptSegment] = []
    private var volatile = ""
    private var onUpdate: (@MainActor (LiveTranscript) -> Void)?
    private var startedAt: Date?
    private var audioURL: URL?

    func prepare(locale: Locale, assetProgress: @escaping @MainActor (Double) -> Void) async throws {
        if let prepared, prepared.locale == locale { return }
        // The popover and the Record button can both ask; share one preparation.
        if let preparing {
            try await preparing.value
            if let prepared, prepared.locale == locale { return }
        }
        let task = Task { try await self.makePrepared(locale: locale, assetProgress: assetProgress) }
        preparing = task
        defer { preparing = nil }
        try await task.value
    }

    private func makePrepared(locale: Locale, assetProgress: @escaping @MainActor (Double) -> Void) async throws {
        let module = try await Self.makeModule(locale: locale)
        try await SpeechAssets.ensureInstalled(for: [module], progress: assetProgress)

        let analyzer = SpeechAnalyzer(modules: [module], options: .init(priority: .userInitiated, modelRetention: .lingering))
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw TranscriberError.noAudioFormat
        }
        try await analyzer.prepareToAnalyze(in: format)
        prepared = Prepared(locale: locale, analyzer: analyzer, module: module, format: format)
    }

    func start(
        locale: Locale,
        onUpdate: @escaping @MainActor (LiveTranscript) -> Void,
        onLevel: @escaping @MainActor (Float) -> Void
    ) async throws {
        try await prepare(locale: locale, assetProgress: { _ in })
        guard let session = prepared else { return }
        prepared = nil  // An analyzer is used for one recording only.
        active = session

        segments = []
        volatile = ""
        self.onUpdate = onUpdate
        startedAt = Date()

        // Temporary capture only; the pipeline deletes it once the raw note is written.
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).caf")
        audioURL = url
        let settings = AudioRecorder.pcmSettings(sampleRate: recorder.inputFormat.sampleRate)

        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        inputContinuation = continuation

        consumerTask = consume(session.module)
        let analyzer = session.analyzer
        analyzerTask = Task { try await analyzer.start(inputSequence: stream) }

        do {
            try recorder.start(fileURL: url, fileSettings: settings, analyzerFormat: session.format, continuation: continuation) { level in
                Task { @MainActor in onLevel(level) }
            }
        } catch {
            continuation.finish()
            await analyzer.cancelAndFinishNow()
            await consumerTask?.value
            active = nil
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    func stop() async -> CapturedRecording {
        // 1. Stop the engine and remove the tap (drains queued buffers).
        recorder.stop()
        // 2. End the input stream.
        inputContinuation?.finish()
        inputContinuation = nil
        // 3. Finalize everything that was said.
        if let analyzer = active?.analyzer {
            do {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            } catch {
                Log.recording.error("Finalizing transcription failed: \(String(describing: error), privacy: .public)")
            }
        }
        // 4. Let the consumer finish. Never cancel it.
        await consumerTask?.value
        _ = try? await analyzerTask?.value
        consumerTask = nil
        analyzerTask = nil
        active = nil

        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        let audio = audioURL
        audioURL = nil
        onUpdate = nil
        return CapturedRecording(segments: segments, duration: duration, audioFile: audio)
    }

    func discard() async {
        recorder.stop()
        inputContinuation?.finish()
        inputContinuation = nil
        await active?.analyzer.cancelAndFinishNow()
        await consumerTask?.value
        consumerTask = nil
        analyzerTask = nil
        active = nil
        if let audioURL { try? FileManager.default.removeItem(at: audioURL) }
        audioURL = nil
        onUpdate = nil
        segments = []
        volatile = ""
    }

    // MARK: Results

    private func consume(_ module: any SpeechModule) -> Task<Void, Never> {
        if let transcriber = module as? SpeechTranscriber {
            return Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        self?.handle(text: result.text, range: result.range, isFinal: result.isFinal)
                    }
                } catch {
                    Log.recording.error("Transcription results ended with an error: \(String(describing: error), privacy: .public)")
                }
            }
        }
        if let transcriber = module as? DictationTranscriber {
            return Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        self?.handle(text: result.text, range: result.range, isFinal: result.isFinal)
                    }
                } catch {
                    Log.recording.error("Dictation results ended with an error: \(String(describing: error), privacy: .public)")
                }
            }
        }
        return Task {}
    }

    private func handle(text: AttributedString, range: CMTimeRange, isFinal: Bool) {
        let string = String(text.characters)
        if isFinal {
            let start = range.start.isNumeric ? range.start.seconds : 0
            let end = range.end.isNumeric ? range.end.seconds : start
            segments.append(TranscriptSegment(text: string, start: start, end: end))
            volatile = ""
        } else {
            // Volatile results replace earlier volatile text.
            volatile = string
        }
        onUpdate?(LiveTranscript(finalized: TranscriptAssembler.text(from: segments), volatile: volatile))
    }

    private static func makeModule(locale: Locale) async throws -> any SpeechModule {
        if SpeechTranscriber.isAvailable, let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            return SpeechTranscriber(
                locale: supported,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults],
                attributeOptions: [.audioTimeRange]
            )
        }
        if let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            Log.recording.notice("SpeechTranscriber unavailable; using DictationTranscriber")
            return DictationTranscriber(
                locale: supported,
                contentHints: [],
                transcriptionOptions: [.punctuation],
                reportingOptions: [.volatileResults],
                attributeOptions: [.audioTimeRange]
            )
        }
        throw TranscriberError.unsupportedLocale(locale.identifier)
    }
}
