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
        /// The disc image file the option puts in the CD drive first, e.g.
        /// "Command & Conquer CD-2.iso" (Nod's missions are on disc 2).
        var disc: String? = nil
    }

    /// One "Press 1 for…" menu in a script.
    private struct Menu {
        /// The label the menu starts at (":menu2"), if any.
        var label: String?
        var titles: [(key: Character, title: String)]
        var keys: [Character]
        var labelForLevel: [Int: String]

        /// Each option's title and the label it goes to.
        var choices: [(title: String, label: String)] {
            titles.compactMap { key, title in
                guard let index = keys.firstIndex(of: key), let label = labelForLevel[index + 1] else { return nil }
                return (title, label)
            }
        }
    }

    /// The menu's options, or none if `script` isn't a menu like this. When
    /// an option goes on to another menu (Blood: pick the sound card, then
    /// which Blood), it runs that menu's first option too, and the other
    /// menu's options are listed after.
    /// `isBatchFile` says whether a program name (relative to the folder the
    /// script has changed into) is a batch file, so it can be CALLed.
    static func options(in script: String, isBatchFile: (_ folder: [String], _ name: String) -> Bool = { _, _ in false })
        -> [Option] {
        let lines = script.replacingOccurrences(of: "\r", with: "").split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let menus = Self.menus(in: lines)
        guard let first = menus.first else { return [] }

        // The commands an option runs, following "goto" into other menus,
        // but not back to a menu already passed (the game ending and
        // "goto menu" showing the menu again)
        func run(_ label: String, from origin: String?, depth: Int = 0) -> (commands: [String], disc: String?) {
            let (commands, next, disc) = section(labelled: label, in: lines, isBatchFile: isBatchFile)
            guard depth < 3, let next, next != origin, let menu = menus.first(where: { $0.label == next }),
                  let firstChoice = menu.choices.first else { return (commands, disc) }
            let rest = run(firstChoice.label, from: origin, depth: depth + 1)
            return (commands + rest.commands, disc ?? rest.disc)
        }

        var options: [Option] = first.choices.compactMap { title, label in
            let (commands, disc) = run(label, from: first.label)
            return commands.isEmpty ? nil : Option(title: title, commands: commands, disc: disc)
        }
        // Menus reached from the first one: their options, standalone
        for menu in menus.dropFirst() where menu.label != nil {
            for (title, label) in menu.choices where !options.contains(where: { $0.title == title }) {
                let (commands, disc) = run(label, from: menu.label)
                if !commands.isEmpty { options.append(Option(title: title, commands: commands, disc: disc)) }
            }
        }
        return options
    }

    /// Every menu in the script, in order.
    private static func menus(in lines: [String]) -> [Menu] {
        let pressPattern = /(?i)^@?echo\s+press\s+(\S)\s+(?:for|to)\s+(.+)$/
        let choicePattern = /(?i)^@?choice\b.*\/c:?([^\s\/]+)/
        let gotoPattern = /(?i)^@?if\s+errorlevel\s*=?=?\s*(\d+)\s+goto\s+:?(\S+)$/
        var menus: [Menu] = []
        var label: String?
        var titles: [(key: Character, title: String)] = []
        for line in lines {
            if line.hasPrefix(":") {
                label = String(line.dropFirst()).lowercased()
                titles = []
            } else if let match = line.firstMatch(of: pressPattern) {
                // "Press 1 for Title" → key "1": "Title" (skipping quit/exit)
                var title = String(match.2).trimmingCharacters(in: CharacterSet(charactersIn: " .*"))
                // "Press 5 to play Network Multiplayer" → "Play Network Multiplayer"
                title = title.prefix(1).uppercased() + title.dropFirst()
                if let key = match.1.first, !["quit", "exit"].contains(title.lowercased()) {
                    titles.append((Character(key.uppercased()), title))
                }
            } else if let match = line.firstMatch(of: choicePattern), titles.count >= 2 {
                // "choice /C:123" gives each key's errorlevel (its position, from 1)
                menus.append(Menu(label: label, titles: titles, keys: Array(String(match.1).uppercased()),
                                  labelForLevel: [:]))
                titles = []
            } else if let match = line.firstMatch(of: gotoPattern), let level = Int(match.1), !menus.isEmpty {
                // "if errorlevel = 2 goto MT32", for the menu just read
                if menus[menus.count - 1].labelForLevel[level] == nil {
                    menus[menus.count - 1].labelForLevel[level] = String(match.2).lowercased()
                }
            }
        }
        return menus.filter { !$0.choices.isEmpty }
    }

    /// The commands under `:label`, up to its `goto` (returned, if it goes
    /// to another label) or the next label, and the disc its CD mount puts
    /// in first.
    private static func section(labelled label: String, in lines: [String], isBatchFile: ([String], String) -> Bool)
        -> (commands: [String], next: String?, disc: String?) {
        guard let start = lines.firstIndex(where: { $0.lowercased() == ":\(label)" }) else { return ([], nil, nil) }
        var commands: [String] = []
        var disc: String?
        var folder: [String] = []
        for line in lines[(start + 1)...] {
            let command = line.hasPrefix("@") ? String(line.dropFirst()) : line
            let lower = command.lowercased()
            if lower.hasPrefix("goto ") {
                let target = String(command.dropFirst(5)).trimmingCharacters(in: CharacterSet(charactersIn: " :"))
                return (commands, target.lowercased() == "quit" ? nil : target.lowercased(), disc)
            }
            if lower.hasPrefix(":") || lower == "exit" { break }
            if command.isEmpty || lower == "cls" || lower.hasPrefix("echo") || lower.hasPrefix("rem ")
                || lower == "pause" || lower.hasPrefix("choice") { continue }
            // A menu inside this section: its choices are read as a menu
            if lower.hasPrefix("if errorlevel") { continue }
            // DOS Boxer mounts the game's drives itself (the script's paths
            // are its collection's); which disc goes in first is kept
            if lower.hasPrefix("imgmount "), disc == nil,
               let match = command.firstMatch(of: /(?i)^imgmount\s+[a-z]:?\s+(?:"([^"]+)"|(\S+))/) {
                let path = String(match.1 ?? match.2 ?? "")
                disc = path.split(whereSeparator: { $0 == "\\" || $0 == "/" }).last.map(String.init)
            }
            if lower.hasPrefix("mount ") || lower.hasPrefix("imgmount ") { continue }

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
                             "keyb", "mixer", "call", "if", "lh", "loadhigh", "type"].contains(name.lowercased())
            if !isBuiltin, isBatchFile(folder, name) {
                commands.append("CALL \(command)")
            } else {
                commands.append(command)
            }
        }
        return (commands, nil, disc)
    }
}
