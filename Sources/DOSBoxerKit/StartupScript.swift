/// The DOS commands that set up a session: mount drives quietly, show DOS
/// Boxer's own welcome header instead of the emulator's banner, and
/// optionally start a program.
public enum StartupScript {
    /// dosbox arguments for a quick session with `folderPath` (if any) as C.
    public static func arguments(folderPath: String?, folderName: String?) -> [String] {
        guard let folderPath else {
            return arguments(mounts: [], title: "DOS Boxer",
                             detail: "No game folder yet. Choose one with the folder button in the toolbar.",
                             program: nil)
        }
        return arguments(mounts: ["@MOUNT C \"\(folderPath)\" >NUL", "@C:"],
                         title: "DOS Boxer",
                         detail: "Drive C is \(dosSafe(folderName ?? "your folder")). Type DIR to see what's there.",
                         program: nil)
    }

    /// dosbox arguments that run `mounts` (DOS commands), show a header, and
    /// start `program` (a DOS path like `C:\CC1\CC1.EXE`) if given. With
    /// `exitsAfterwards`, DOS shuts down when the program ends, so the game
    /// window can close.
    public static func arguments(mounts: [String], title: String, detail: String,
                                 program: String?, exitsAfterwards: Bool = false) -> [String] {
        var commands = ["@ECHO OFF"] + mounts
        // A game that starts straight away (and closes when done) needs no
        // header; it would only flash past
        if !(program != nil && exitsAfterwards) {
            commands += header(title: title, detail: detail)
        }
        if let program {
            commands += programCommands(program)
            if exitsAfterwards {
                commands.append("@EXIT")
            }
        }
        return ["--set", "dosbox startup_verbosity=quiet"]
            + commands.flatMap { ["-c", $0] }
    }

    /// Switches to the program's drive and folder, then runs it. Batch files
    /// are CALLed: running one from another batch file never returns, so
    /// anything after it (like EXIT) would never happen.
    private static func programCommands(_ dosPath: String) -> [String] {
        let parts = dosPath.split(separator: "\\", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2, parts[0].hasSuffix(":"), let program = parts.last else {
            return ["@\(dosPath)"]
        }
        let folder = parts.dropFirst().dropLast().joined(separator: "\\")
        let run = program.lowercased().hasSuffix(".bat") ? "@CALL \(program)" : "@\(program)"
        return ["@\(parts[0])", "@CD \\\(folder)", run]
    }

    /// A blue band across the top of the screen, drawn with ANSI colours.
    /// Each row is filled to the edge with "erase to end of line".
    private static func header(title: String, detail: String) -> [String] {
        let esc = "\u{1B}"
        let band = "\(esc)[44m", bold = "\(esc)[1;37;44m", body = "\(esc)[0;37;44m"
        let fill = "\(esc)[K", reset = "\(esc)[0m"
        return [
            "@ECHO \(band)\(fill)",
            "@ECHO \(bold)  \(dosSafe(title))\(fill)",
            "@ECHO \(body)  \(dosSafe(detail, limit: 76))\(fill)",
            "@ECHO \(band)\(fill)\(reset)",
            "@ECHO.",
        ]
    }

    /// Keeps text to plain characters DOS can print and ECHO won't misread.
    static func dosSafe(_ text: String, limit: Int = 60) -> String {
        let printable = text.unicodeScalars.map {
            $0.isASCII && $0.value >= 32 && !"<>|%".unicodeScalars.contains($0) ? Character($0) : "?"
        }
        return String(String(printable).prefix(limit))
    }
}
