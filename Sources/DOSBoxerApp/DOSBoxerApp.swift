import DOSBoxerKit
import SwiftUI

@main
struct DOSBoxerApp: App {
    @State private var library = GameLibrary()

    init() {
        // DOS Boxer's windows don't use tabs; drop View › Show Tab Bar
        NSWindow.allowsAutomaticWindowTabbing = false
        // macOS draws the app icon (made in Icon Composer) the first time
        // it's asked for and hands out a blank placeholder meanwhile; ask now,
        // so the update window and About show the real one
        if let icon = NSImage(named: NSImage.applicationIconName) {
            var rect = CGRect(x: 0, y: 0, width: 128, height: 128)
            _ = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        }
        // Starts Sparkle, which checks for updates in the background
        _ = Updates.shared
    }

    var body: some Scene {
        Window("Library", id: "library") {
            LibraryView(library: library)
                .frame(minWidth: 560, minHeight: 420)
        }
        // Gameboxes opened from Finder (double-click, or dropped on the Dock
        // icon) arrive here; the library window opens a game window for each.
        .handlesExternalEvents(matching: ["*"])
        .defaultSize(width: 980, height: 680)
        .defaultLaunchBehavior(.presented)
        .commands {
            LibraryCommands(library: library)
            GameCommands()
            AboutCommands()
            UpdateCommands()
        }

        Window("About DOS Boxer", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .restorationBehavior(.disabled)
        .defaultPosition(.center)

        WindowGroup("Game", for: URL.self) { $url in
            if let url {
                GameWindowScene(url: url, screenshotsFolder: library.screenshotsURL)
            }
        }
        .defaultSize(width: 960, height: 720)
        // Don't reopen games at launch: the gamebox may have moved, and
        // starting DOS unasked would be surprising
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
        }

        Window("DOS Prompt", id: "dos-prompt") {
            DOSPromptView()
                .frame(minWidth: 640, minHeight: 480)
        }
        .defaultSize(width: 960, height: 720)
        .defaultLaunchBehavior(.suppressed)
    }
}

/// A game window that returns to the library when the game ends.
private struct GameWindowScene: View {
    let url: URL
    let screenshotsFolder: URL
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        GameWindow(url: url, screenshotsFolder: screenshotsFolder) { openWindow(id: "library") }
            .frame(minWidth: 640, minHeight: 480)
            // In full screen, the toolbar slides in only when you point at the top
            .windowToolbarFullScreenVisibility(.onHover)
    }
}

