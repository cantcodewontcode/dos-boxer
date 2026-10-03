import Foundation

/// Makes sure every file in a gamebox is on this Mac before DOS starts.
///
/// Libraries in iCloud Drive, Dropbox or OneDrive can hold placeholder files
/// that only download when opened. If DOS hit one mid-game, the game would
/// freeze until it arrived, so we fetch everything up front instead.
public enum GameboxDownloads {
    /// Files still to download, with their total size in bytes.
    public static func missingFiles(in gamebox: URL) -> (files: [URL], bytes: Int64) {
        let keys: [URLResourceKey] = [.ubiquitousItemDownloadingStatusKey, .isDirectoryKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: gamebox, includingPropertiesForKeys: keys) else {
            return ([], 0)
        }
        var files: [URL] = []
        var bytes: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isDirectory != true,
                  let status = values.ubiquitousItemDownloadingStatus, status != .current else { continue }
            files.append(url)
            bytes += Int64(values.fileSize ?? 0)
        }
        return (files, bytes)
    }

    /// Downloads any cloud-only files and waits for them. Reports progress as
    /// a fraction of files done. Returns immediately for local libraries.
    public static func downloadAll(in gamebox: URL,
                                   progress: @Sendable (Double) -> Void = { _ in }) async throws {
        let (files, _) = missingFiles(in: gamebox)
        guard !files.isEmpty else { return }

        for file in files {
            try FileManager.default.startDownloadingUbiquitousItem(at: file)
        }
        var remaining = Set(files)
        while !remaining.isEmpty {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(250))
            remaining = remaining.filter { file in
                var url = file
                url.removeAllCachedResourceValues()
                let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                    .ubiquitousItemDownloadingStatus
                return status != nil && status != .current
            }
            progress(Double(files.count - remaining.count) / Double(files.count))
        }
    }
}
