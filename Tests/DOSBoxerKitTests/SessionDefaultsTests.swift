import Testing
@testable import DOSBoxerKit

struct SessionDefaultsTests {
    @Test func mapsMacKeyboardsToDOSLayouts() {
        #expect(SessionDefaults.dosKeyboardLayout(forInputSource: "com.apple.keylayout.US") == "us")
        #expect(SessionDefaults.dosKeyboardLayout(forInputSource: "com.apple.keylayout.German") == "de")
        #expect(SessionDefaults.dosKeyboardLayout(forInputSource: "com.apple.keylayout.British-PC") == "uk")
        #expect(SessionDefaults.dosKeyboardLayout(forInputSource: "com.apple.keylayout.Hebrew-QWERTY") == "il")
        // Unknown or missing: plain US
        #expect(SessionDefaults.dosKeyboardLayout(forInputSource: "com.example.Klingon") == "us")
        #expect(SessionDefaults.dosKeyboardLayout(forInputSource: nil) == "us")
    }

    @Test func ignoresThePersonsOwnDOSBoxConfig() {
        let arguments = SessionDefaults.arguments()
        #expect(arguments.contains("--noprimaryconf"))
        #expect(arguments.contains("--nolocalconf"))
    }
}
