import Foundation
import Speech

enum SpeechAssets {
    /// Downloads and installs speech assets for the modules if needed. The only network activity,
    /// done by macOS itself.
    static func ensureInstalled(
        for modules: [any SpeechModule],
        progress: @escaping @MainActor (Double) -> Void
    ) async throws {
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: modules) else { return }
        Log.recording.info("Installing speech assets")

        let watcher = Task { @MainActor in
            while !Task.isCancelled {
                progress(request.progress.fractionCompleted)
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        defer { watcher.cancel() }
        try await request.downloadAndInstall()
    }
}
