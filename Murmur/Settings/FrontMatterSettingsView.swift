import SwiftUI

/// Settings → Front matter: the global template, omit-empty, list merging, the placeholder
/// reference and the Used AI values panel (SPEC §4.3, §5.3, §6.5).
struct FrontMatterSettingsView: View {
    @Environment(AppState.self) private var app
    @State private var mergeListsDraft = ""

    var body: some View {
        Form {
            Section {
                FrontMatterEditor(
                    template: settingBinding(\.frontMatter.template),
                    render: { builder(project: nil).build(context: $0) },
                    defaultStyle: app.activeProject?.style ?? .standard
                )
            } header: {
                Text("Global template")
            } footer: {
                Text("Every key in a note's front matter comes from this template, or a project's own. Murmur adds nothing else.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Options") {
                Toggle("Leave out keys whose value is empty", isOn: settingBinding(\.frontMatter.omitEmpty))
                TextField("Merge as lists", text: $mergeListsDraft, prompt: Text("tags, aliases"))
                    .onChange(of: mergeListsDraft) {
                        let keys = mergeListsDraft.split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        if keys != app.settings.frontMatter.mergeLists {
                            app.settingsStore.update { $0.frontMatter.mergeLists = keys }
                        }
                    }
                Text("When a project appends to the global template and both set one of these keys, their values are combined into one list.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let project = app.activeProject {
                Section("Used AI values") {
                    Text(requirements(for: project).summaryText)
                    Text(usedAIFootnote(for: project))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                DisclosureGroup("Placeholder reference") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                        ForEach(PlaceholderCatalog.all) { entry in
                            GridRow {
                                Text(entry.insertText)
                                    .font(.callout.monospaced())
                                    .textSelection(.enabled)
                                Text(entry.isAI ? "\(entry.summary) (AI)" : entry.summary)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 4)
                    Text("Filters go inside a placeholder and can be chained: {{title|lower|slug}}. Dates take Obsidian-style formats: {{date:dddd D MMMM YYYY}}.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { mergeListsDraft = app.settings.frontMatter.mergeLists.joined(separator: ", ") }
    }

    private func builder(project: Project?) -> FrontMatterBuilder {
        let settings = app.settings.frontMatter
        return FrontMatterBuilder(
            globalTemplate: settings.template,
            projectTemplate: project?.frontMatter.template ?? "",
            mode: project?.frontMatter.mode ?? .inherit,
            omitEmpty: settings.omitEmpty,
            mergeLists: settings.mergeLists
        )
    }

    private func requirements(for project: Project) -> MetadataRequirements {
        MetadataRequirements(
            ai: app.settings.ai,
            noteType: .auto,
            projectDefaultType: project.defaultNoteType,
            noteTypes: app.settings.noteTypes,
            effectiveTemplate: builder(project: project).effectiveTemplate,
            filenamePattern: app.settings.output.filenamePattern,
            timelineEnabled: NotePipeline.timelineEnabled
        )
    }

    private func usedAIFootnote(for project: Project) -> String {
        let source = switch project.frontMatter.mode {
        case .inherit: "this template"
        case .override: "\(project.name)'s own template"
        case .append: "this template plus \(project.name)'s"
        }
        return "For \(project.name), the active project, using \(source), the AI settings and the filename pattern, with the note type set to Auto. Values that aren't used are never generated."
    }

    private func settingBinding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { app.settings[keyPath: keyPath] },
            set: { value in app.settingsStore.update { $0[keyPath: keyPath] = value } }
        )
    }
}
