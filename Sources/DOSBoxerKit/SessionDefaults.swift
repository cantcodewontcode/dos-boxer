import Carbon.HIToolbox
import Foundation

/// dosbox settings every DOS Boxer session starts with, before any
/// game-specific ones.
enum SessionDefaults {
    /// Ignore the person's own DOSBox Staging config files (from using
    /// DOSBox Staging directly), so games behave the same for everyone; and
    /// use the keyboard layout they're typing with.
    static func arguments() -> [String] {
        ["--noprimaryconf", "--nolocalconf",
         "--set", "dos keyboard_layout=\(dosKeyboardLayout(forInputSource: currentInputSourceID()))",
         // General MIDI music plays through macOS's built-in synthesizer.
         // DOSBox's usual choice is an external MIDI device; with none
         // plugged in, music is switched off and games that wait for a MIDI
         // device to answer (Blackthorne) hang
         "--set", "midi mididevice=coreaudio",
         // Sound handed over in blocks of 1,024 rather than DOSBox Staging's
         // 512, as eXoDOS and Boxer both run games: with the small ones many
         // games' sound crackles. 20 ms kept ready, so sound stays prompt;
         // games that still crackle get more (ShippedGameSettings,
         // Gamebox.talkieSettings)
         "--set", "mixer blocksize=1024",
         "--set", "mixer prebuffer=20",
         // DOS Boxer captures the mouse itself (clicking the game); DOSBox's
         // own click-to-capture would swallow the next click and ignore
         // movement until then
         "--set", "mouse mouse_capture=onstart"]
            + MT32Setup.sessionArguments()
            // Sound Canvas music plays through the installed SoundFont
            + (SoundFontSetup.installedFont.map {
                ["--set", "fluidsynth soundfont=\($0.path(percentEncoded: false))"]
            } ?? [])
    }

    /// Whether a General MIDI SoundFont is installed for Sound Canvas music
    /// (Settings › Music).
    static var hasSoundFont: Bool { SoundFontSetup.isReady }

    /// The Mac keyboard layout in use right now, e.g. "com.apple.keylayout.US".
    static func currentInputSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(property).takeUnretainedValue() as String
    }

    /// The DOS keyboard layout matching a Mac input source, or "us".
    ///
    /// DOSBox Staging can detect this itself, but it looks at every enabled
    /// input source and prefers non-US ones, so a Mac with Hebrew enabled
    /// (but typing in English) got a Hebrew DOS keyboard.
    static func dosKeyboardLayout(forInputSource id: String?) -> String {
        guard let id, let name = id.split(separator: ".").last.map(String.init) else { return "us" }
        let layouts: [String: String] = [
            "US": "us", "ABC": "us", "USExtended": "us", "USInternational-PC": "ux",
            "Dvorak": "dv", "Dvorak-Left": "lh", "Dvorak-Right": "rh", "Colemak": "co",
            "British": "uk", "British-PC": "uk", "Irish": "uk",
            "Australian": "us", "Canadian": "us", "Canadian-CSA": "cf", "CanadianFrench-PC": "cf",
            "German": "de", "Austrian": "de", "SwissGerman": "sg", "SwissFrench": "sf",
            "French": "fr", "French-PC": "fr", "French-numerical": "fr", "Belgian": "be",
            "Spanish": "es", "Spanish-ISO": "es", "LatinAmerican": "la",
            "Italian": "it", "Italian-Pro": "it",
            "Portuguese": "po", "Brazilian": "br", "Brazilian-ABNT2": "br", "Brazilian-Pro": "br274",
            "Dutch": "nl", "Swedish": "sv", "Swedish-Pro": "sv", "Norwegian": "no", "Danish": "dk",
            "Finnish": "fi", "Icelandic": "is", "Estonian": "ee", "Latvian": "lv", "Lithuanian": "lt",
            "Polish": "pl", "PolishPro": "pl", "Czech": "cz", "Czech-QWERTY": "cz489", "Slovak": "sk",
            "Hungarian": "hu", "Romanian": "ro", "Croatian": "hr", "Slovenian": "si", "Serbian-Latin": "yu",
            "Russian": "ru", "RussianWin": "ru", "Ukrainian": "ur", "Bulgarian": "bg", "Greek": "gk",
            "Turkish": "tr", "Turkish-QWERTY": "tr", "Turkish-QWERTY-PC": "tr",
            "Hebrew": "il", "Hebrew-QWERTY": "il",
        ]
        return layouts[name] ?? "us"
    }
}
