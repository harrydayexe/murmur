import Foundation

/// Atomic writes: write a temp file in the same directory, then rename it over the target.
enum AtomicFile {
    static func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        let temp = directory.appending(path: ".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: temp)
        do {
            guard rename(temp.path(percentEncoded: false), url.path(percentEncoded: false)) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }

    static func write(_ text: String, to url: URL) throws {
        try write(Data(text.utf8), to: url)
    }
}
