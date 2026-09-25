import SwiftUI

struct RecordingView: View {
    @Environment(AppState.self) private var app
    @State private var confirmingDiscard = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "record.circle.fill").foregroundStyle(.red)
                Text(app.currentProject?.name ?? "Recording")
                    .font(.headline)
                Spacer()
                Text(Duration.seconds(app.elapsed).formatted(.time(pattern: .minuteSecond)))
                    .font(.system(.body, design: .monospaced))
            }

            LevelMeter(level: app.level)

            ScrollViewReader { proxy in
                ScrollView {
                    Text(transcript)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .id("bottom")
                }
                .frame(height: 140)
                .onChange(of: app.live) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .padding(8)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

            if confirmingDiscard {
                HStack {
                    Text("Discard this recording?").font(.callout)
                    Spacer()
                    Button("Keep Recording") { confirmingDiscard = false }
                        .keyboardShortcut(.cancelAction)
                    Button("Discard", role: .destructive) { app.discard() }
                }
            } else {
                HStack {
                    Button("Discard", role: .destructive) {
                        if app.elapsed > 10 { confirmingDiscard = true } else { app.discard() }
                    }
                    .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button {
                        app.stopAndSave()
                    } label: {
                        Label("Stop & Save", systemImage: "stop.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private var transcript: AttributedString {
        let live = app.live
        if live.finalized.isEmpty && live.volatile.isEmpty {
            var placeholder = AttributedString("Listening…")
            placeholder.foregroundColor = .secondary
            return placeholder
        }
        var text = AttributedString(live.finalized)
        if !live.volatile.isEmpty {
            var tail = AttributedString((live.finalized.isEmpty ? "" : " ") + live.volatile)
            tail.foregroundColor = .secondary
            text += tail
        }
        return text
    }
}

struct LevelMeter: View {
    var level: Float

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(.green.gradient)
                    .frame(width: max(4, geometry.size.width * CGFloat(level)))
                    .animation(.linear(duration: 0.05), value: level)
            }
        }
        .frame(height: 6)
        .accessibilityLabel("Input level")
        .accessibilityValue("\(Int(level * 100)) percent")
    }
}

struct ProcessingView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(app.statusText ?? "Working…")
            }
            Text("You can close this window; Murmur keeps going.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
