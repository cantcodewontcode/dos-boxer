/// The DOS commands that set up a session: mount the game folder quietly and
/// show DOS Boxer's own welcome header instead of the emulator's banner.
public enum StartupScript {
    /// dosbox arguments for a session, with `folderPath` (if any) as drive C.
    public static func arguments(folderPath: String?, folderName: String?) -> [String] {
        var commands = ["@ECHO OFF"]
        if let folderPath {
            commands += ["@MOUNT C \"\(folderPath)\" >NUL", "@C:"]
        }
        commands += header(folderName: folderPath == nil ? nil : folderName)

        return ["--set", "dosbox startup_verbosity=quiet"]
            + commands.flatMap { ["-c", $0] }
    }

    /// A blue band across the top of the screen, drawn with ANSI colours.
    /// Each row is filled to the edge with "erase to end of line".
    private static func header(folderName: String?) -> [String] {
        let esc = "\u{1B}"
        let band = "\(esc)[44m", title = "\(esc)[1;37;44m", body = "\(esc)[0;37;44m"
        let fill = "\(esc)[K", reset = "\(esc)[0m"

        let detail = if let folderName {
            "Drive C is \(dosSafe(folderName)). Type DIR to see what's there."
        } else {
            "No game folder yet. Choose one with the folder button in the toolbar."
        }
        return [
            "@ECHO \(band)\(fill)",
            "@ECHO \(title)  DOS Boxer\(fill)",
            "@ECHO \(body)  \(detail)\(fill)",
            "@ECHO \(band)\(fill)\(reset)",
            "@ECHO.",
        ]
    }

    /// Keeps a name to plain characters DOS can print, and short enough for
    /// one line of the header.
    private static func dosSafe(_ name: String) -> String {
        let printable = name.unicodeScalars.map { $0.isASCII && $0.value >= 32 && !"<>|%".unicodeScalars.contains($0) ? Character($0) : "?" }
        return String(String(printable).prefix(40))
    }
}
