import Foundation

/// Where 2dle keeps its own files: `~/Library/Application Support/2dle`.
/// (Until 2026-10-14 some of them were kept in a folder with the app's first name on it. The first time the app
/// itself starts after that, whatever is found there is brought over and the old folder goes.)
enum AppFolder {
    static let url: URL = {
        // (The screen saver's host has a home of its own: the account's home is looked up, so that both read the same files.)
        let home =
            getpwuid(getuid()).map { URL(fileURLWithPath: String(cString: $0.pointee.pw_dir), isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser
        let support = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let folder = support.appendingPathComponent("2dle", isDirectory: true)
        let old = support.appendingPathComponent("Spindle", isDirectory: true)
        let files = FileManager.default
        try? files.createDirectory(at: folder, withIntermediateDirectories: true)
        // (Only the app does the moving: a test render or the screen saver leaves the old folder for it.)
        if Bundle.main.bundleURL.pathExtension == "app", let kept = try? files.contentsOfDirectory(atPath: old.path) {
            for name in kept {
                let from = old.appendingPathComponent(name)
                let to = folder.appendingPathComponent(name)
                try? files.removeItem(at: to)
                try? files.moveItem(at: from, to: to)
            }
            if (try? files.contentsOfDirectory(atPath: old.path))?.isEmpty == true { try? files.removeItem(at: old) }
        }
        return folder
    }()
}
