import Foundation
import Observation

/// Loads and saves `settings.json` (SPEC §4.1). Saves are debounced and atomic, and keep unknown keys.
@MainActor
@Observable
final class SettingsStore {
    private(set) var settings: AppSettings
    /// Set when the settings file was corrupt and defaults were loaded.
    private(set) var loadWarning: String?

    let fileURL: URL

    @ObservationIgnored private var rawJSON: [String: Any] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let debounce: Duration

    init(directory: URL, homeDirectory: URL, debounce: Duration = .milliseconds(500)) {
        self.fileURL = directory.appending(path: "settings.json")
        self.debounce = debounce

        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        guard let data = try? Data(contentsOf: fileURL) else {
            settings = .initial(homeDirectory: homeDirectory)
            scheduleSave(immediately: true)
            return
        }

        do {
            let (decoded, raw) = try SettingsCodec.decode(data)
            settings = decoded
            rawJSON = raw
        } catch {
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = directory.appending(path: "settings.corrupt-\(stamp).json")
            try? fileManager.moveItem(at: fileURL, to: backup)
            Log.app.error("Settings file was corrupt (\(String(describing: error), privacy: .public)); backed up to \(backup.lastPathComponent, privacy: .public)")
            settings = .initial(homeDirectory: homeDirectory)
            loadWarning = "Settings were unreadable and have been reset. The old file was saved as \(backup.lastPathComponent)."
            scheduleSave(immediately: true)
        }
    }

    func update(_ mutate: (inout AppSettings) -> Void) {
        var copy = settings
        mutate(&copy)
        guard copy != settings else { return }
        settings = copy
        scheduleSave(immediately: false)
    }

    /// Writes any pending change now.
    func flush() async {
        saveTask?.cancel()
        await write()
    }

    private func scheduleSave(immediately: Bool) {
        saveTask?.cancel()
        let delay = immediately ? .zero : debounce
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.write()
        }
    }

    private func write() async {
        let data: Data
        do {
            (data, rawJSON) = try SettingsCodec.encode(settings, preserving: rawJSON)
        } catch {
            Log.app.error("Couldn't encode settings: \(String(describing: error), privacy: .public)")
            return
        }
        let url = fileURL
        await Task.detached(priority: .utility) {
            do {
                try AtomicFile.write(data, to: url)
            } catch {
                Log.app.error("Couldn't save settings: \(String(describing: error), privacy: .public)")
            }
        }.value
    }
}

/// JSON encoding for settings that keeps keys this version doesn't know about.
enum SettingsCodec {
    /// Optional keys that are left out of the JSON when nil, so they must be removed rather than kept from the old file.
    static let nullableKeys: Set<String> = ["activeProjectID", "folderBookmark", "vaultRootPathHint", "defaultNoteType", "inputDeviceUID"]

    static func decode(_ data: Data) throws -> (AppSettings, [String: Any]) {
        guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        // Fill in any keys the file leaves out from the defaults, then decode.
        let defaults = try dictionary(from: AppSettings())
        let merged = merge(old: defaults, new: raw, removeMissingNullables: false)
        let settings = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: merged))
        return (settings, raw)
    }

    static func encode(_ settings: AppSettings, preserving raw: [String: Any]) throws -> (Data, [String: Any]) {
        let merged = merge(old: raw, new: try dictionary(from: settings), removeMissingNullables: true)
        let data = try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return (data, merged)
    }

    private static func dictionary(from settings: AppSettings) throws -> [String: Any] {
        let data = try JSONEncoder().encode(settings)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    /// Deep-merges `new` over `old`. Arrays of objects with an `id` are merged element by element.
    static func merge(old: [String: Any], new: [String: Any], removeMissingNullables: Bool) -> [String: Any] {
        var result = old
        if removeMissingNullables {
            for key in nullableKeys where new[key] == nil { result.removeValue(forKey: key) }
        }
        for (key, newValue) in new {
            switch (old[key], newValue) {
            case let (oldDict as [String: Any], newDict as [String: Any]):
                result[key] = merge(old: oldDict, new: newDict, removeMissingNullables: removeMissingNullables)
            case let (oldArray as [[String: Any]], newArray as [[String: Any]]):
                result[key] = newArray.map { element -> [String: Any] in
                    guard let id = element["id"] as? String,
                          let previous = oldArray.first(where: { $0["id"] as? String == id }) else { return element }
                    return merge(old: previous, new: element, removeMissingNullables: removeMissingNullables)
                }
            default:
                result[key] = newValue
            }
        }
        return result
    }
}
