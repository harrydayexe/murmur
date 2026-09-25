import AppKit

@MainActor
enum FolderPicker {
    /// Shows an open panel for a folder. Returns nil if cancelled.
    static func chooseFolder(startingAt directory: URL, message: String, prompt: String) -> URL? {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = directory
        panel.message = message
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.url : nil
    }
}
