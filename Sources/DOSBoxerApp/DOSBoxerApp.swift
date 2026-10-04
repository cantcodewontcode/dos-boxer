import DOSBoxerKit
import SwiftUI

@main
struct DOSBoxerApp: App {
    @State private var library = GameLibrary()

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
            CommandGroup(after: .newItem) {
                OpenDOSPromptButton()
            }
        }

        WindowGroup("Game", for: URL.self) { $url in
            if let url {
                GameWindowScene(url: url, screenshotsFolder: library.screenshotsURL)
            }
        }
        .defaultSize(width: 960, height: 720)
        // Don't reopen games at launch: the gamebox may have moved, and
        // starting DOS unasked would be surprising
        .restorationBehavior(.disabled)

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
    }
}

private struct OpenDOSPromptButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("New DOS Prompt") { openWindow(id: "dos-prompt") }
            .keyboardShortcut("n", modifiers: [.command, .option])
    }
}
