import SwiftUI

@main
struct MurmurApp: App {
    @State private var app = AppState.live()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(app)
        } label: {
            MenuBarLabel(app: app)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(app)
        }
    }
}

private struct MenuBarLabel: View {
    let app: AppState

    var body: some View {
        if app.isRecording {
            HStack(spacing: 4) {
                Image(systemName: "record.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.red)
                Text(Duration.seconds(app.elapsed).formatted(.time(pattern: .minuteSecond)))
                    .monospacedDigit()
            }
        } else {
            Image(systemName: app.menuBarSymbol)
        }
    }
}
