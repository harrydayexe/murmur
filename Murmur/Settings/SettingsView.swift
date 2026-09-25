import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Projects", systemImage: "folder") {
                ProjectsSettingsView()
            }
        }
        .frame(width: 640, height: 400)
    }
}

private struct ProjectsSettingsView: View {
    @Environment(AppState.self) private var app
    @State private var selection: UUID?
    @State private var confirmingRemoval: Project?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(app.settings.projects) { project in
                        HStack {
                            Text(project.name)
                            Spacer()
                            if project.id == app.activeProject?.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .help("Active project")
                            }
                        }
                        .tag(project.id)
                    }
                }
                Divider()
                HStack(spacing: 0) {
                    Button {
                        selection = app.addProject()
                    } label: {
                        Image(systemName: "plus").frame(width: 24, height: 20)
                    }
                    Button {
                        confirmingRemoval = selectedProject
                    } label: {
                        Image(systemName: "minus").frame(width: 24, height: 20)
                    }
                    .disabled(selectedProject == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(4)
            }
            .frame(width: 200)

            Divider()

            Group {
                if let project = selectedProject {
                    ProjectDetailView(project: project)
                } else {
                    Text("Select a project").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { selection = selection ?? app.activeProject?.id }
        .confirmationDialog(
            "Remove \(confirmingRemoval?.name ?? "project")?",
            isPresented: Binding(get: { confirmingRemoval != nil }, set: { if !$0 { confirmingRemoval = nil } }),
            presenting: confirmingRemoval
        ) { project in
            Button("Remove", role: .destructive) {
                app.removeProject(project.id)
                selection = app.settings.projects.first?.id
            }
        } message: { _ in
            Text("Notes and audio already saved in its folder are not deleted.")
        }
    }

    private var selectedProject: Project? {
        app.settings.projects.first { $0.id == selection }
    }
}

private struct ProjectDetailView: View {
    @Environment(AppState.self) private var app
    let project: Project

    var body: some View {
        Form {
            TextField("Name", text: binding(\.name))

            LabeledContent("Folder") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.folderPathHint.isEmpty ? "Not chosen" : project.folderPathHint.abbreviatingHome)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    folderStatus
                    Button(project.folderBookmark == nil ? "Choose Folder…" : "Re-choose Folder…") {
                        app.chooseFolder(for: project.id, useDefaultSubfolder: project.folderBookmark == nil)
                    }
                }
            }

            Picker("Note style", selection: binding(\.style)) {
                Text("Standard Markdown").tag(NoteStyleKind.standard)
                Text("Obsidian").tag(NoteStyleKind.obsidian)
            }
            if let vault = project.vaultRootPathHint {
                LabeledContent("Obsidian vault", value: vault.abbreviatingHome)
            }

            LabeledContent("Active") {
                if project.id == app.activeProject?.id {
                    Text("Recording goes to this project").foregroundStyle(.secondary)
                } else {
                    Button("Make Active") { app.selectProject(project.id) }
                }
            }

            Section {
                Button("Reveal Settings File") {
                    NSWorkspace.shared.activateFileViewerSelecting([app.settingsStore.fileURL])
                }
            } footer: {
                Text("Templates, AI and recording options can be edited in the settings file for now. Restart Murmur after editing it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var folderStatus: some View {
        switch app.folderStatus[project.id] ?? .notChosen {
        case .ready:
            Label("Writable", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
        case .notChosen:
            Label("Murmur will ask for access when you first record", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary).font(.caption)
        case .unavailable(let reason):
            Label(reason, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<Project, Value>) -> Binding<Value> {
        Binding(
            get: { project[keyPath: keyPath] },
            set: { value in app.updateProject(project.id) { $0[keyPath: keyPath] = value } }
        )
    }
}
