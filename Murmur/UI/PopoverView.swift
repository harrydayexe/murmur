import AppKit
import SwiftUI

struct PopoverView: View {
    @Environment(AppState.self) private var app
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch app.phase {
            case .recording:
                RecordingView()
            case .finalizing, .writingDraft, .tidying, .generating, .writing:
                ProcessingView()
            default:
                IdleView(openSettings: showSettings)
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 360)
        .onAppear { app.popoverOpened() }
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline) {
            if let warning = app.warning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
                    .onTapGesture { app.clearWarning() }
                    .help("Click to dismiss")
            } else {
                Text(app.statusText ?? "Ready")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Settings…", action: showSettings)
                .keyboardShortcut(",")
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .font(.caption)
    }

    private func showSettings() {
        NSApp.activate()
        openSettings()
    }
}

private struct IdleView: View {
    @Environment(AppState.self) private var app
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            projectMenu
            if !app.settings.noteTypes.isEmpty { noteTypePicker }

            Button {
                app.startRecording()
            } label: {
                Label("Record", systemImage: "record.circle")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(isPreparing)

            switch app.phase {
            case .preparing(let text):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(text).font(.callout).foregroundStyle(.secondary)
                }
            case .done(let result):
                DoneView(result: result)
            case .error(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            default:
                EmptyView()
            }
        }
    }

    private var isPreparing: Bool {
        if case .preparing = app.phase { true } else { false }
    }

    private var projectMenu: some View {
        let projects = app.settings.projects.filter { !$0.archived }
        return Menu {
            ForEach(projects) { project in
                Button {
                    app.selectProject(project.id)
                } label: {
                    if project.id == app.activeProject?.id {
                        Label(menuTitle(project), systemImage: "checkmark")
                    } else {
                        Text(menuTitle(project))
                    }
                }
            }
            Divider()
            Button("New project…") {
                app.selectProject(app.addProject())
                openSettings()
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.activeProject?.name ?? "No project")
                        .font(.headline)
                    Text(app.activeProject?.folderPathHint.abbreviatingHome ?? "Add a project in Settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if app.activeProject?.style == .obsidian { ObsidianBadge() }
            }
        }
        .menuStyle(.borderlessButton)
    }

    private func menuTitle(_ project: Project) -> String {
        project.style == .obsidian ? "\(project.name) (Obsidian)" : project.name
    }

    private var noteTypePicker: some View {
        @Bindable var app = app
        return Picker("Type", selection: $app.noteType) {
            Text("Auto").tag(NoteTypeSelection.auto)
            ForEach(app.settings.noteTypes, id: \.self) { type in
                Text(type.capitalized).tag(NoteTypeSelection.fixed(type))
            }
        }
    }
}

private struct DoneView: View {
    @Environment(AppState.self) private var app
    let result: PipelineResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Saved to \(Text(result.projectName).italic()): \(Text(result.title).italic())")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if result.processing != .tidied {
                Text(result.processing == .raw ? "Saved without AI tidying." : "Some parts were kept as spoken.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Open") { NSWorkspace.shared.open(result.noteURL) }
                Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([result.noteURL]) }
                Spacer()
                Button("Dismiss") { app.dismissResult() }
                    .buttonStyle(.borderless)
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ObsidianBadge: View {
    var body: some View {
        Text("Obsidian")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.purple.opacity(0.2), in: Capsule())
            .foregroundStyle(.purple)
    }
}

extension String {
    /// `/Users/name/Documents` → `~/Documents`.
    var abbreviatingHome: String {
        let home = UserDirectories.home.path(percentEncoded: false)
        let trimmedHome = home.hasSuffix("/") ? String(home.dropLast()) : home
        return hasPrefix(trimmedHome) ? "~" + dropFirst(trimmedHome.count) : self
    }
}
