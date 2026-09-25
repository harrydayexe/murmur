import Foundation

/// Everything the pipeline needs, captured when recording starts (SPEC §6).
struct RecordingSnapshot: Sendable {
    var project: Project
    var settings: AppSettings
    var noteType: NoteTypeSelection
    var startDate: Date
    var timeZone: TimeZone = .current
    var appVersion: String
    /// The project folder with security-scoped access already started, or nil if there's none.
    var folder: URL?
}

/// The output of a finished recording.
struct CapturedRecording: Sendable {
    var segments: [TranscriptSegment]
    var duration: TimeInterval
    /// Audio to keep, in a temporary location. Nil if audio isn't kept.
    var audioFile: URL?
}

enum PipelineStep: Equatable, Sendable {
    case writingDraft
    case tidying(Int, Int)
    case generatingMetadata
    case writingNote
}

struct PipelineResult: Equatable, Sendable {
    var noteURL: URL
    var title: String
    var projectName: String
    var processing: ProcessingStatus
    /// True if the project folder was unreachable and the note went to `Unsaved/`.
    var savedToFallback: Bool
    var warnings: [String]
}

/// Raw draft → tidy → metadata → final write (SPEC §6.3–§6.6).
struct NotePipeline: Sendable {
    var polisher: any TextPolishing
    var metadata: any MetadataGenerating
    var unsavedRoot: URL
    var isWritable: @Sendable (URL) -> Bool
    /// Timeline isn't written yet, so it doesn't count as a use of the summary or type.
    /// Static so the Used AI values panel sees the same value.
    static let timelineEnabled = false

    func run(
        _ capture: CapturedRecording,
        snapshot: RecordingSnapshot,
        progress: @escaping @Sendable (PipelineStep) async -> Void = { _ in }
    ) async throws -> PipelineResult {
        let settings = snapshot.settings
        let project = snapshot.project
        let fileManager = FileManager.default
        var warnings: [String] = []

        // MARK: Raw draft (always, before any AI step)
        await progress(.writingDraft)
        let glossary = Glossary(entries: settings.ai.glossary + project.glossary)
        let rawTranscript = TranscriptAssembler.text(from: capture.segments)
        let draftTranscript = glossary.apply(to: rawTranscript)

        let (folder, isFallback) = SaveLocation.resolve(
            projectFolder: snapshot.folder, projectName: project.name, unsavedRoot: unsavedRoot, isWritable: isWritable
        )
        if isFallback {
            Log.output.error("Project folder unavailable; saving to \(folder.path(percentEncoded: false), privacy: .public)")
            warnings.append("The folder for \(project.name) wasn't reachable, so the note was saved in Murmur's Unsaved folder.")
        }
        let audioFolder = folder.appending(path: NoteStyle.audioFolder, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        let requirements = MetadataRequirements(
            ai: settings.ai,
            noteType: snapshot.noteType,
            projectDefaultType: project.defaultNoteType,
            noteTypes: settings.noteTypes,
            effectiveTemplate: frontMatterBuilder(snapshot).effectiveTemplate,
            filenamePattern: settings.output.filenamePattern,
            timelineEnabled: Self.timelineEnabled
        )

        let fallbackTitle = "Voice note " + DateTokenFormatter(timeZone: snapshot.timeZone, locale: Locale(identifier: settings.recording.locale))
            .string(from: snapshot.startDate, format: DateTokenFormatter.timeFormat)
        var context = TemplateContext(
            title: fallbackTitle,
            project: project.name,
            type: requirements.fixedType ?? "",
            date: snapshot.startDate,
            timeZone: snapshot.timeZone,
            style: project.style,
            durationSeconds: Int(capture.duration.rounded()),
            locale: settings.recording.locale,
            processing: .raw,
            appVersion: snapshot.appVersion
        )

        let draftName = Filename.unique(Filename.render(pattern: settings.output.filenamePattern, context: context)) {
            Self.isTaken($0, in: folder, audioFolder: audioFolder)
        }
        context.filename = draftName
        if let audio = capture.audioFile {
            try fileManager.createDirectory(at: audioFolder, withIntermediateDirectories: true)
            let audioName = "\(draftName).\(audio.pathExtension)"
            try fileManager.moveItem(at: audio, to: audioFolder.appending(path: audioName))
            context.audioFilename = audioName
        }

        var noteURL = folder.appending(path: "\(draftName).md")
        try write(context: context, snapshot: snapshot, transcript: draftTranscript, raw: rawTranscript, metadata: nil, to: noteURL, warnings: &warnings)
        Log.output.info("Raw note written: \(noteURL.lastPathComponent, privacy: .public)")
        // From here on the note exists on disk.

        // MARK: Tidy
        var transcript = draftTranscript
        var processing = ProcessingStatus.raw
        if settings.ai.tidyLevel == .light, !draftTranscript.isEmpty {
            do {
                let result = try await polisher.polish(draftTranscript, glossary: glossary.preferred) { chunk, total in
                    await progress(.tidying(chunk, total))
                }
                transcript = result.text
                processing = result.fellBack ? .tidiedPartial : .tidied
            } catch {
                Log.ai.notice("Tidying skipped: \(String(describing: error), privacy: .public)")
            }
        }

        // MARK: Metadata (only what's used)
        var generated = GeneratedMetadata()
        let fields = requirements.fields
        if !fields.isEmpty, !transcript.isEmpty {
            await progress(.generatingMetadata)
            do {
                generated = try await metadata.generate(MetadataRequest(
                    transcript: transcript, fields: fields, noteTypes: settings.noteTypes, tags: settings.ai.tags
                ))
            } catch {
                Log.ai.notice("Metadata skipped: \(String(describing: error), privacy: .public)")
            }
        }

        // MARK: Final write
        await progress(.writingNote)
        let title = generated.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if fields.contains(.title), !title.isEmpty { context.title = title }
        if requirements.fixedType == nil { context.type = generated.type }
        context.aiSummary = generated.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        context.aiKeyPoints = generated.keyPoints
        context.aiTags = TagNormalizer(settings: settings.ai.tags).normalize(generated.tags)
        context.processing = processing

        var finalName = Filename.render(pattern: settings.output.filenamePattern, context: context)
        if finalName != draftName {
            finalName = Filename.unique(finalName) { Self.isTaken($0, in: folder, audioFolder: audioFolder) }
            if !context.audioFilename.isEmpty {
                let ext = (context.audioFilename as NSString).pathExtension
                let newAudio = "\(finalName).\(ext)"
                do {
                    try fileManager.moveItem(at: audioFolder.appending(path: context.audioFilename), to: audioFolder.appending(path: newAudio))
                    context.audioFilename = newAudio
                } catch {
                    Log.output.error("Couldn't rename audio: \(String(describing: error), privacy: .public)")
                    finalName = draftName
                }
            }
        }
        context.filename = finalName

        let finalURL = folder.appending(path: "\(finalName).md")
        var finalWarnings: [String] = []
        try write(context: context, snapshot: snapshot, transcript: transcript, raw: rawTranscript, metadata: generated, to: finalURL, warnings: &finalWarnings)
        if finalURL != noteURL {
            try? fileManager.removeItem(at: noteURL)
            noteURL = finalURL
        }
        warnings += finalWarnings

        return PipelineResult(
            noteURL: noteURL,
            title: context.title,
            projectName: project.name,
            processing: processing,
            savedToFallback: isFallback,
            warnings: warnings
        )
    }

    private func frontMatterBuilder(_ snapshot: RecordingSnapshot) -> FrontMatterBuilder {
        FrontMatterBuilder(
            globalTemplate: snapshot.settings.frontMatter.template,
            projectTemplate: snapshot.project.frontMatter.template,
            mode: snapshot.project.frontMatter.mode,
            omitEmpty: snapshot.settings.frontMatter.omitEmpty,
            mergeLists: snapshot.settings.frontMatter.mergeLists
        )
    }

    private func write(
        context: TemplateContext,
        snapshot: RecordingSnapshot,
        transcript: String,
        raw: String,
        metadata: GeneratedMetadata?,
        to url: URL,
        warnings: inout [String]
    ) throws {
        let frontMatter = frontMatterBuilder(snapshot).build(context: context)
        if case .invalid(_, let error) = frontMatter {
            warnings.append("The front matter template isn't valid YAML (\(error)). The note was saved without it, and the rendered block is in a comment at the top.")
        }
        let body = snapshot.settings.ai.body
        let document = NoteDocument(
            frontMatter: frontMatter,
            title: context.title,
            summary: body.summary ? metadata?.summary ?? "" : "",
            keyPoints: body.keyPoints ? metadata?.keyPoints ?? [] : [],
            audioFilename: context.audioFilename,
            transcript: transcript,
            rawTranscript: raw
        )
        try AtomicFile.write(NoteStyle(kind: snapshot.project.style).render(document), to: url)
    }

    private static func isTaken(_ name: String, in folder: URL, audioFolder: URL) -> Bool {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: folder.appending(path: "\(name).md").path(percentEncoded: false)) { return true }
        let audioFiles = (try? fileManager.contentsOfDirectory(atPath: audioFolder.path(percentEncoded: false))) ?? []
        return audioFiles.contains { ($0 as NSString).deletingPathExtension == name }
    }
}
