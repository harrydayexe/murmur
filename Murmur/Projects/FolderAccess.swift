import Foundation
import Synchronization

/// Access to project folders through security-scoped bookmarks.
protocol FolderAccessing: Sendable {
    /// Resolves a bookmark and starts security-scoped access, which stays open for the app's lifetime.
    /// Returns a fresh bookmark if the old one was stale.
    func open(bookmark: Data) throws -> (url: URL, refreshedBookmark: Data?)
    func makeBookmark(for url: URL) throws -> Data
    func isWritableDirectory(_ url: URL) -> Bool
}

final class SecurityScopedFolderAccess: FolderAccessing {
    private let accessing = Mutex<Set<String>>([])

    func open(bookmark: Data) throws -> (url: URL, refreshedBookmark: Data?) {
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
        let path = url.standardizedFileURL.path(percentEncoded: false)
        let needsStart = accessing.withLock { $0.insert(path).inserted }
        if needsStart, !url.startAccessingSecurityScopedResource() {
            accessing.withLock { _ = $0.remove(path) }
            Log.app.error("Couldn't start access to \(path, privacy: .public)")
        }
        let refreshed = stale ? try? makeBookmark(for: url) : nil
        return (url, refreshed)
    }

    func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    func isWritableDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let path = url.path(percentEncoded: false)
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && FileManager.default.isWritableFile(atPath: path)
    }
}

/// Finds the Obsidian vault a folder is in by walking up to a `.obsidian/` directory (SPEC §5.4).
enum VaultDetector {
    static func vaultRoot(for folder: URL, directoryExists: (URL) -> Bool) -> URL? {
        // Walk path components rather than `deletingLastPathComponent()`, which turns `/` into `/..` forever.
        var components = folder.standardizedFileURL.pathComponents
        while !components.isEmpty {
            let directory = URL(filePath: NSString.path(withComponents: components), directoryHint: .isDirectory)
            if directoryExists(directory.appending(path: ".obsidian", directoryHint: .isDirectory)) { return directory }
            components.removeLast()
        }
        return nil
    }

    static func vaultRoot(for folder: URL) -> URL? {
        vaultRoot(for: folder) { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }
}

/// The real home directory. Inside the sandbox, `NSHomeDirectory()` is the container.
enum UserDirectories {
    static var home: URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(filePath: String(cString: dir), directoryHint: .isDirectory)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static var documents: URL { home.appending(path: "Documents", directoryHint: .isDirectory) }

    /// `Application Support/Murmur` inside the app's container.
    static var appSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "Murmur", directoryHint: .isDirectory)
    }
}
