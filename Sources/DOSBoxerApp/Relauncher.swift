import AppKit

/// Starts DOS again by relaunching the app.
///
/// The emulator core can only run once per process, so for now "Restart" and
/// choosing a different folder relaunch DOS Boxer and hand the folder to the
/// new instance as a security-scoped bookmark. This goes away once each game
/// runs in its own helper process.
enum Relauncher {
    private static let folderKey = "PendingGameFolderBookmark"
    private static let autoStartKey = "PendingAutoStart"

    /// Relaunches the app, which then starts DOS with `folder` as drive C.
    @MainActor
    static func relaunch(withFolder folder: URL?) {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: autoStartKey)
        if let folder,
           let bookmark = try? folder.bookmarkData(options: .withSecurityScope) {
            defaults.set(bookmark, forKey: folderKey)
        } else {
            defaults.removeObject(forKey: folderKey)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    /// If the previous instance asked us to start right away, returns
    /// (and forgets) the folder it handed over. The outer optional is nil
    /// when no relaunch is pending.
    static func consumePendingStart() -> URL?? {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: autoStartKey) else { return nil }
        defaults.removeObject(forKey: autoStartKey)
        defer { defaults.removeObject(forKey: folderKey) }

        guard let bookmark = defaults.data(forKey: folderKey) else { return .some(nil) }
        var isStale = false
        let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope,
                           bookmarkDataIsStale: &isStale)
        return .some(url)
    }
}
