import CryptoKit
import Foundation

/// Recognizes games by their programs, whatever their folder is called:
/// checksums of programs unique to one game, gathered by the compatibility
/// lab (`Fingerprints.json`), give the name collections know it by.
enum GameFingerprints {
    private struct File: Decodable { let programs: [String: String] }

    static let programs: [String: String] = {
        guard let url = Bundle(for: GameLibrary.self).url(forResource: "Fingerprints", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return [:] }
        return file.programs
    }()

    /// The collection name ("Duke Nukem - Episode 1 - Shrapnel City (1991)")
    /// of the game in `folder`, if one of its programs is known.
    static func collectionName(forFilesIn folder: URL) -> String? {
        guard !programs.isEmpty,
              let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey])
        else { return nil }
        for case let file as URL in files where ["exe", "com", "bat"].contains(file.pathExtension.lowercased()) {
            guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0, size < 50_000_000,
                  let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { continue }
            let hash = SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
            if let name = programs[hash] { return name }
        }
        return nil
    }
}
