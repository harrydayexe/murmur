import SwiftUI

/// Editor for a front matter template: highlighting, autocomplete after `{{`, an Insert menu,
/// presets and a live preview (SPEC §5.3.6).
struct FrontMatterEditor: View {
    @Binding var template: String
    /// Renders the template for the preview, so a project in `append` mode previews the merged result.
    var render: (TemplateContext) -> FrontMatterResult
    var defaultStyle: NoteStyleKind
    var showsPresets = true

    @State private var attributed = AttributedString()
    @State private var selection = AttributedTextSelection()
    @State private var pendingPreset: FrontMatterPreset?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                insertMenu
                if showsPresets { presetsMenu }
                Spacer()
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            TextEditor(text: $attributed, selection: $selection)
                .font(.body.monospaced())
                .frame(minHeight: 110)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))

            suggestions

            TemplatePreview(render: render, defaultStyle: defaultStyle, unknown: TemplateEditing.unknownPlaceholders(in: template))
        }
        .onAppear { attributed = Self.styled(template) }
        .onChange(of: attributed) { syncFromEditor() }
        .onChange(of: template) {
            // Changed from outside, e.g. another project was selected.
            if String(attributed.characters) != template {
                attributed = Self.styled(template)
                selection = AttributedTextSelection()
            }
        }
        .confirmationDialog(
            "Replace the template with the \(pendingPreset?.displayName ?? "") preset?",
            isPresented: Binding(get: { pendingPreset != nil }, set: { if !$0 { pendingPreset = nil } }),
            presenting: pendingPreset
        ) { preset in
            Button("Replace") { setText(preset.template, cursor: preset.template.count) }
        } message: { _ in
            Text("Your current template will be replaced.")
        }
    }

    // MARK: Menus

    private var insertMenu: some View {
        Menu("Insert") {
            Section("Placeholders") {
                ForEach(PlaceholderCatalog.placeholders) { entry in menuItem(entry) }
            }
            Section("Filters") {
                ForEach(PlaceholderCatalog.filters) { entry in menuItem(entry) }
            }
        }
    }

    private func menuItem(_ entry: PlaceholderCatalog.Entry) -> some View {
        Button {
            let result = TemplateEditing.insert(entry, into: template, cursor: cursor ?? template.count)
            setText(result.text, cursor: result.cursor)
        } label: {
            Text(entry.insertText)
            Text(entry.isAI ? "\(entry.summary) (AI)" : entry.summary)
        }
    }

    private var presetsMenu: some View {
        Menu("Presets") {
            ForEach(FrontMatterPreset.allCases, id: \.self) { preset in
                Button(preset.displayName) {
                    let current = template.trimmingCharacters(in: .whitespacesAndNewlines)
                    if current.isEmpty || current == preset.template {
                        setText(preset.template, cursor: preset.template.count)
                    } else {
                        pendingPreset = preset
                    }
                }
            }
        }
    }

    // MARK: Autocomplete

    @ViewBuilder
    private var suggestions: some View {
        if let cursor, let query = TemplateEditing.completionQuery(text: template, cursor: cursor) {
            let matches = TemplateEditing.completions(for: query)
            if !matches.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(matches) { entry in
                            Button(entry.name) {
                                let result = TemplateEditing.complete(entry, query: query, in: template)
                                setText(result.text, cursor: result.cursor)
                            }
                            .help(entry.summary)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .controlSize(.small)
                .font(.body.monospaced())
            }
        }
    }

    // MARK: Text

    /// The cursor as a character offset: the insertion point, or the end of the selection.
    private var cursor: Int? {
        let characters = attributed.characters
        switch selection.indices(in: attributed) {
        case .insertionPoint(let index):
            return characters.distance(from: characters.startIndex, to: index)
        case .ranges(let ranges):
            return ranges.ranges.last.map { characters.distance(from: characters.startIndex, to: $0.upperBound) }
        }
    }

    private func syncFromEditor() {
        let plain = String(attributed.characters)
        if plain != template { template = plain }
        // Re-apply highlighting in place, so the selection stays where it is. A no-op edit
        // leaves `attributed` unchanged, which ends the onChange loop.
        var restyled = attributed
        var restyledSelection = selection
        restyled.transform(updating: &restyledSelection) { Self.applyStyle(to: &$0) }
        if restyled != attributed {
            attributed = restyled
            selection = restyledSelection
        }
    }

    private func setText(_ text: String, cursor: Int) {
        let styled = Self.styled(text)
        attributed = styled
        template = text
        let characters = styled.characters
        let offset = min(max(cursor, 0), characters.count)
        selection = AttributedTextSelection(insertionPoint: characters.index(characters.startIndex, offsetBy: offset))
    }

    private static func styled(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        applyStyle(to: &attributed)
        return attributed
    }

    /// Clears any formatting (e.g. from pasted rich text) and highlights placeholders.
    private static func applyStyle(to attributed: inout AttributedString) {
        let plain = String(attributed.characters)
        attributed.setAttributes(AttributeContainer())
        let characters = attributed.characters
        for highlight in TemplateEditing.highlights(in: plain) {
            let lower = characters.index(characters.startIndex, offsetBy: highlight.range.lowerBound)
            let upper = characters.index(characters.startIndex, offsetBy: highlight.range.upperBound)
            if highlight.isKnown {
                attributed[lower..<upper].swiftUI.foregroundColor = .accentColor
            } else {
                attributed[lower..<upper].swiftUI.foregroundColor = .red
                attributed[lower..<upper].swiftUI.underlineStyle = .single
            }
        }
    }
}

/// The rendered front matter for a sample note, with YAML status (SPEC §5.3.6).
private struct TemplatePreview: View {
    var render: (TemplateContext) -> FrontMatterResult
    var defaultStyle: NoteStyleKind
    var unknown: [String]

    @State private var withAI = true
    @State private var style: NoteStyleKind?

    var body: some View {
        let result = render(.sample(withAI: withAI, style: style ?? defaultStyle, appVersion: AppState.appVersion))
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Sample", selection: $withAI) {
                    Text("With AI values").tag(true)
                    Text("AI unavailable").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                Picker("Style", selection: Binding(get: { style ?? defaultStyle }, set: { style = $0 })) {
                    Text("Standard").tag(NoteStyleKind.standard)
                    Text("Obsidian").tag(NoteStyleKind.obsidian)
                }
                .labelsHidden()
                .fixedSize()
            }

            Text(previewText(result))
                .font(.callout.monospaced())
                .foregroundStyle(result == .none ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))

            status(result)

            if !unknown.isEmpty {
                Label("Unknown placeholders are left as they are: \(unknown.joined(separator: ", "))", systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func previewText(_ result: FrontMatterResult) -> String {
        switch result {
        case .none: "No front matter"
        case .valid(let yaml), .invalid(let yaml, _): "---\n\(yaml)\n---"
        }
    }

    @ViewBuilder
    private func status(_ result: FrontMatterResult) -> some View {
        switch result {
        case .none:
            EmptyView()
        case .valid:
            Label("Valid YAML", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .invalid(_, let error):
            Label("Invalid YAML, \(error). Notes would be saved without front matter.", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
