import Foundation

/// Where a note gets saved: the project folder, or `Application Support/Murmur/Unsaved/<project>/`
/// if the folder is missing or unwritable (SPEC §4.2).
enum SaveLocation {
    static func resolve(
        projectFolder: URL?,
        projectName: String,
        unsavedRoot: URL,
        isWritable: (URL) -> Bool
    ) -> (folder: URL, isFallback: Bool) {
        if let projectFolder, isWritable(projectFolder) {
            return (projectFolder, false)
        }
        let safeName = Filename.clean(projectName)
        return (unsavedRoot.appending(path: safeName, directoryHint: .isDirectory), true)
    }
}
