import AppKit
import Foundation
import Observation

enum FolderStatus: Equatable {
    case notChosen
    case ready(URL)
    case unavailable(String)
}

/// App-wide UI state (SPEC §7): idle → recording → finalizing → tidying(i, n) → writing → done | error.
@MainActor
@Observable
final class AppState {
    enum Phase: Equatable {
        case idle
        case preparing(String)
        case recording
        case finalizing
        case writingDraft
        case tidying(Int, Int)
        case generating
        case writing
        case done(PipelineResult)
        case error(String)

        var isProcessing: Bool {
            switch self {
            case .finalizing, .writingDraft, .tidying, .generating, .writing: true
            default: false
            }
        }
    }

    let settingsStore: SettingsStore
    private(set) var phase = Phase.idle
    private(set) var live = LiveTranscript()
    private(set) var level: Float = 0
    private(set) var elapsed: TimeInterval = 0
    private(set) var folderStatus: [UUID: FolderStatus] = [:]
    /// The latest non-fatal problem, shown in the footer.
    private(set) var warning: String?
    var noteType = NoteTypeSelection.auto

    @ObservationIgnored private let folderAccess: any FolderAccessing
    @ObservationIgnored private let transcriber: any Transcribing
    @ObservationIgnored private let pipeline: NotePipeline
    @ObservationIgnored private var snapshot: RecordingSnapshot?
    @ObservationIgnored private var recordingProjectID: UUID?
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored private var processingTask: Task<Void, Never>?

    static let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"

    init(settingsStore: SettingsStore, folderAccess: any FolderAccessing, transcriber: any Transcribing, pipeline: NotePipeline) {
        self.settingsStore = settingsStore
        self.folderAccess = folderAccess
        self.transcriber = transcriber
        self.pipeline = pipeline
        warning = settingsStore.loadWarning
        resolveAllFolders()
    }

    static func live() -> AppState {
        let store = SettingsStore(directory: UserDirectories.appSupport, homeDirectory: UserDirectories.home)
        let access = SecurityScopedFolderAccess()
        let pipeline = NotePipeline(
            polisher: Polisher(),
            metadata: MetadataGenerator(),
            unsavedRoot: UserDirectories.appSupport.appending(path: "Unsaved", directoryHint: .isDirectory),
            isWritable: { access.isWritableDirectory($0) }
        )
        return AppState(settingsStore: store, folderAccess: access, transcriber: Transcriber(), pipeline: pipeline)
    }

    // MARK: Derived state

    var settings: AppSettings { settingsStore.settings }
    var activeProject: Project? { settings.activeProject }
    var isRecording: Bool { phase == .recording }

    /// The project being recorded into, or the active one.
    var currentProject: Project? {
        if let recordingProjectID, let project = settings.projects.first(where: { $0.id == recordingProjectID }) {
            return project
        }
        return activeProject
    }

    var menuBarSymbol: String {
        switch phase {
        case .recording: "record.circle.fill"
        case .preparing, .finalizing, .writingDraft, .tidying, .generating, .writing: "ellipsis.circle"
        case .error: "exclamationmark.triangle"
        case .idle, .done: warning == nil ? "waveform" : "exclamationmark.triangle"
        }
    }

    var statusText: String? {
        switch phase {
        case .preparing(let text): text
        case .finalizing: "Finishing transcription…"
        case .writingDraft: "Saving draft…"
        case .tidying(let chunk, let total): "Tidying (\(chunk)/\(total))…"
        case .generating: "Writing title and summary…"
        case .writing: "Writing note…"
        default: nil
        }
    }

    // MARK: Projects and folders

    func selectProject(_ id: UUID) {
        guard !isRecording, !phase.isProcessing else { return }
        settingsStore.update { $0.activeProjectID = id }
    }

    @discardableResult
    func addProject() -> UUID {
        let project = Project(name: "New project")
        settingsStore.update { settings in
            settings.projects.append(project)
        }
        folderStatus[project.id] = .notChosen
        return project.id
    }

    func removeProject(_ id: UUID) {
        settingsStore.update { settings in
            settings.projects.removeAll { $0.id == id }
            if settings.activeProjectID == id { settings.activeProjectID = settings.projects.first?.id }
        }
        folderStatus[id] = nil
    }

    func updateProject(_ id: UUID, _ change: (inout Project) -> Void) {
        settingsStore.update { settings in
            guard let index = settings.projects.firstIndex(where: { $0.id == id }) else { return }
            change(&settings.projects[index])
        }
    }

    func resolveAllFolders() {
        for project in settings.projects { resolveFolder(for: project.id) }
    }

    @discardableResult
    func resolveFolder(for id: UUID) -> URL? {
        guard let project = settings.projects.first(where: { $0.id == id }) else { return nil }
        guard let bookmark = project.folderBookmark else {
            folderStatus[id] = .notChosen
            return nil
        }
        do {
            let (url, refreshed) = try folderAccess.open(bookmark: bookmark)
            if let refreshed { updateProject(id) { $0.folderBookmark = refreshed } }
            guard folderAccess.isWritableDirectory(url) else {
                folderStatus[id] = .unavailable("The folder is missing or can't be written to.")
                return nil
            }
            folderStatus[id] = .ready(url)
            return url
        } catch {
            Log.app.error("Couldn't resolve folder for \(project.name, privacy: .public): \(String(describing: error), privacy: .public)")
            folderStatus[id] = .unavailable("Murmur lost access to this folder. Choose it again.")
            return nil
        }
    }

    /// Asks the user for a folder and stores a bookmark. With `useDefaultSubfolder`, choosing
    /// `~/Documents` itself saves into `~/Documents/Murmur`.
    @discardableResult
    func chooseFolder(for id: UUID, useDefaultSubfolder: Bool) -> URL? {
        let message = useDefaultSubfolder
            ? "Murmur saves notes to ~/Documents/Murmur. Click Grant Access, or choose another folder."
            : "Choose the folder where this project's notes are saved."
        guard let picked = FolderPicker.chooseFolder(
            startingAt: UserDirectories.documents,
            message: message,
            prompt: useDefaultSubfolder ? "Grant Access" : "Choose"
        ) else { return nil }

        var folder = picked
        do {
            if useDefaultSubfolder, picked.standardizedFileURL.path(percentEncoded: false) == UserDirectories.documents.standardizedFileURL.path(percentEncoded: false) {
                folder = picked.appending(path: "Murmur", directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            let bookmark = try folderAccess.makeBookmark(for: folder)
            let vaultRoot = VaultDetector.vaultRoot(for: folder)
            updateProject(id) { project in
                project.folderBookmark = bookmark
                project.folderPathHint = folder.path(percentEncoded: false)
                project.style = vaultRoot == nil ? .standard : .obsidian
                project.vaultRootPathHint = vaultRoot?.path(percentEncoded: false)
            }
            if settings.projects.filter({ $0.folderPathHint == folder.path(percentEncoded: false) }).count > 1 {
                warning = "Another project already saves to this folder."
            }
        } catch {
            warning = "Couldn't use that folder: \(error.localizedDescription)"
            return nil
        }
        return resolveFolder(for: id)
    }

    // MARK: Recording

    /// Readies the speech analyzer when the popover opens, so recording starts quickly.
    func popoverOpened() {
        guard phase == .idle || isFinished, Permissions.microphoneAuthorized else { return }
        let locale = Locale(identifier: settings.recording.locale)
        Task { try? await transcriber.prepare(locale: locale, assetProgress: { _ in }) }
    }

    private var isFinished: Bool {
        switch phase {
        case .done, .error: true
        default: false
        }
    }

    func toggleRecording() {
        if isRecording { stopAndSave() } else { startRecording() }
    }

    func startRecording() {
        guard phase == .idle || isFinished else { return }
        guard let project = activeProject else {
            phase = .error("Add a project in Settings first.")
            return
        }

        // Before recording: the folder must be writable (SPEC §4.2).
        var folder = resolveFolder(for: project.id)
        if folder == nil {
            folder = chooseFolder(for: project.id, useDefaultSubfolder: project.folderBookmark == nil)
            guard folder != nil else {
                phase = .error("Choose a folder for \(project.name) to start recording.")
                return
            }
        }
        guard let project = activeProject else { return }

        let settings = self.settings
        phase = .preparing("Checking permissions…")
        Task {
            guard await Permissions.requestMicrophone() else {
                phase = .error("Microphone access is off. Turn it on in System Settings → Privacy & Security → Microphone.")
                return
            }
            guard await Permissions.requestSpeechRecognition() else {
                phase = .error("Speech recognition is off. Turn it on in System Settings → Privacy & Security → Speech Recognition.")
                return
            }

            let locale = Locale(identifier: settings.recording.locale)
            do {
                phase = .preparing("Preparing speech recognition…")
                try await transcriber.prepare(locale: locale) { fraction in
                    self.phase = .preparing("Downloading speech model (\(Int(fraction * 100))%)…")
                }
                live = LiveTranscript()
                level = 0
                snapshot = RecordingSnapshot(
                    project: project,
                    settings: settings,
                    noteType: noteType,
                    startDate: Date(),
                    appVersion: Self.appVersion,
                    folder: folder
                )
                recordingProjectID = project.id
                try await transcriber.start(
                    locale: locale,
                    onUpdate: { self.live = $0 },
                    onLevel: { self.level = $0 }
                )
                phase = .recording
                startClock(maxMinutes: settings.recording.maxMinutes)
            } catch {
                snapshot = nil
                recordingProjectID = nil
                Log.recording.error("Couldn't start recording: \(String(describing: error), privacy: .public)")
                phase = .error(error.localizedDescription)
            }
        }
    }

    func stopAndSave() {
        guard phase == .recording, let snapshot else { return }
        stopClock()
        phase = .finalizing
        self.snapshot = nil

        processingTask = Task {
            let capture = await transcriber.stop()
            level = 0
            do {
                let result = try await pipeline.run(capture, snapshot: snapshot) { step in
                    await self.apply(step)
                }
                finish(with: result)
            } catch {
                Log.output.error("Saving failed: \(String(describing: error), privacy: .public); retrying in Unsaved")
                // Never lose a recording: try again in the Unsaved folder.
                var fallback = snapshot
                fallback.folder = nil
                do {
                    let result = try await pipeline.run(capture, snapshot: fallback)
                    finish(with: result)
                } catch {
                    if let audio = capture.audioFile {
                        Log.output.error("Recording left at \(audio.path(percentEncoded: false), privacy: .public)")
                    }
                    phase = .error("Couldn't save the note: \(error.localizedDescription)")
                }
            }
            recordingProjectID = nil
        }
    }

    func discard() {
        guard phase == .recording else { return }
        stopClock()
        snapshot = nil
        Task {
            await transcriber.discard()
            live = LiveTranscript()
            level = 0
            recordingProjectID = nil
            phase = .idle
        }
    }

    func dismissResult() {
        if isFinished { phase = .idle }
    }

    func clearWarning() { warning = nil }

    private func finish(with result: PipelineResult) {
        phase = .done(result)
        warning = result.warnings.first
    }

    private func apply(_ step: PipelineStep) {
        switch step {
        case .writingDraft: phase = .writingDraft
        case .tidying(let chunk, let total): phase = .tidying(chunk, total)
        case .generatingMetadata: phase = .generating
        case .writingNote: phase = .writing
        }
    }

    private func startClock(maxMinutes: Int) {
        let start = Date()
        elapsed = 0
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, self.phase == .recording else { return }
                self.elapsed = Date().timeIntervalSince(start)
                if maxMinutes > 0, self.elapsed >= Double(maxMinutes * 60) {
                    Log.recording.notice("Maximum length reached; stopping")
                    self.stopAndSave()
                    return
                }
            }
        }
    }

    private func stopClock() {
        clockTask?.cancel()
        clockTask = nil
    }
}
