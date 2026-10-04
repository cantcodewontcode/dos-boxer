import Foundation

/// Reads the version menus eXoDOS puts in a game's start script, e.g.
///
///     echo Press 1 for ABC Boxing w/ SoundBlaster
///     echo Press 2 for ABC Boxing w/ MT-32
///     echo Press 3 to Quit
///     choice /C:123 /N Please Choose:
///     if errorlevel = 2 goto MT32
///     if errorlevel = 1 goto SB16
///     :SB16
///     CONFIG -set "mididevice=default"
///     @vbox
///     goto quit
///
/// and turns each option into a named launcher that runs just that option's
/// commands. (Running the whole menu would come back to the menu when the
/// game ends, so the game window could never close by itself.)
enum BatchMenuReader {
    struct Option: Equatable {
        var title: String
        /// DOS commands, run from the batch file's folder.
        var commands: [String]
    }

    /// The menu's options, or none if `script` isn't a menu like this.
    /// `isBatchFile` says whether a program name (relative to the folder the
    /// script has changed into) is a batch file, so it can be CALLed.
    static func options(in script: String, isBatchFile: (_ folder: [String], _ name: String) -> Bool = { _, _ in false })
        -> [Option] {
        let lines = script.replacingOccurrences(of: "\r", with: "").split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        // "Press 1 for Title" → key "1": "Title" (skipping quit/exit)
        var titles: [(key: Character, title: String)] = []
        let pressPattern = /(?i)^@?echo\s+press\s+(\S)\s+(?:for|to)\s+(.+)$/
        for line in lines {
            guard let match = line.firstMatch(of: pressPattern) else { continue }
            let title = String(match.2).trimmingCharacters(in: CharacterSet(charactersIn: " .*"))
            guard let key = match.1.first, !["quit", "exit"].contains(title.lowercased()) else { continue }
            titles.append((Character(key.uppercased()), title))
        }
        guard titles.count >= 2 else { return [] }

        // "choice /C:123" gives each key's errorlevel (its position, from 1)
        let choicePattern = /(?i)^@?choice\b.*\/c:?([^\s\/]+)/
        guard let choice = lines.lazy.compactMap({ $0.firstMatch(of: choicePattern) }).first else { return [] }
        let keys = Array(String(choice.1).uppercased())

        // "if errorlevel = 2 goto MT32" (also "if errorlevel 2 goto …")
        var labelForLevel: [Int: String] = [:]
        let gotoPattern = /(?i)^@?if\s+errorlevel\s*=?=?\s*(\d+)\s+goto\s+:?(\S+)$/
        for line in lines {
            if let match = line.firstMatch(of: gotoPattern), let level = Int(match.1) {
                labelForLevel[level] = String(match.2).lowercased()
            }
        }

        return titles.compactMap { key, title in
            guard let index = keys.firstIndex(of: key), let label = labelForLevel[index + 1] else { return nil }
            let commands = section(labelled: label, in: lines, isBatchFile: isBatchFile)
            return commands.isEmpty ? nil : Option(title: title, commands: commands)
        }
    }

    /// The commands under `:label`, up to its `goto` or the next label.
    private static func section(labelled label: String, in lines: [String],
                                isBatchFile: ([String], String) -> Bool) -> [String] {
        guard let start = lines.firstIndex(where: { $0.lowercased() == ":\(label)" }) else { return [] }
        var commands: [String] = []
        var folder: [String] = []
        for line in lines[(start + 1)...] {
            let command = line.hasPrefix("@") ? String(line.dropFirst()) : line
            let lower = command.lowercased()
            if lower.hasPrefix(":") || lower.hasPrefix("goto ") || lower == "exit" { break }
            if command.isEmpty || lower == "cls" || lower.hasPrefix("echo") || lower.hasPrefix("rem ")
                || lower == "pause" || lower.hasPrefix("choice") { continue }

            if lower.hasPrefix("cd ") || lower.hasPrefix("cd\\") {
                let target = command.dropFirst(2).trimmingCharacters(in: .whitespaces)
                for part in target.split(separator: "\\") {
                    if part == ".." { _ = folder.popLast() } else if part != "." { folder.append(String(part)) }
                }
                commands.append(command)
                continue
            }
            // A bare program name that's a batch file must be CALLed to return
            let name = command.split(separator: " ").first.map(String.init) ?? command
            let isBuiltin = ["config", "copy", "del", "set", "mount", "imgmount", "cd", "md", "mkdir", "loadfix",
                             "keyb", "mixer", "call", "if", "lh", "loadhigh"].contains(name.lowercased())
            if !isBuiltin, isBatchFile(folder, name) {
                commands.append("CALL \(command)")
            } else {
                commands.append(command)
            }
        }
        return commands
    }
}
