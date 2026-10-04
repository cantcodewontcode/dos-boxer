import DOSBoxerKit
import SwiftUI

/// What the library window can do from the menu bar.
struct LibraryActions {
    /// Something is selected in the grid.
    var hasSelection: Bool
    var importGames: () -> Void
    var play: () -> Void
    var getInfo: () -> Void
    var showInFinder: () -> Void
    var selectAll: () -> Void
    var moveToTrash: () -> Void
    var find: () -> Void
    var chooseLocation: () -> Void
    var newCollection: () -> Void
    var toggleInfo: () -> Void
    /// true for bigger covers, false for smaller.
    var zoom: (_ bigger: Bool) -> Void
}

extension FocusedValues {
    @Entry var libraryActions: LibraryActions?
}

/// The File, Edit and View menu items for the library.
struct LibraryCommands: Commands {
    let library: GameLibrary
    @FocusedValue(\.libraryActions) private var actions
    @Environment(\.openWindow) private var openWindow
    @AppStorage("SortOrder") private var sortOrder: SortOrder = .name

    private var hasSelection: Bool { actions?.hasSelection ?? false }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Collection") { actions?.newCollection() }
                .keyboardShortcut("n")
                .disabled(actions == nil)
            Button("New DOS Prompt") { openWindow(id: "dos-prompt") }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Divider()
            Button("Import Games…") { actions?.importGames() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(actions == nil)
            Divider()
            Button("Play") { actions?.play() }
                .keyboardShortcut("o")
                .disabled(!hasSelection)
            Button("Get Info") { actions?.getInfo() }
                .keyboardShortcut("i")
                .disabled(!hasSelection)
            Button("Show in Finder") { actions?.showInFinder() }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(!hasSelection)
            Divider()
            Button("Show Library in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([library.rootURL])
            }
            Button("Show Screenshots in Finder") {
                try? FileManager.default.createDirectory(at: library.screenshotsURL, withIntermediateDirectories: true)
                NSWorkspace.shared.activateFileViewerSelecting([library.screenshotsURL])
            }
            Button("Choose Library Location…") { actions?.chooseLocation() }
                .disabled(actions == nil)
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Move to Trash…") { actions?.moveToTrash() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!hasSelection)
        }
        CommandGroup(after: .textEditing) {
            Button("Find Games") { actions?.find() }
                .keyboardShortcut("f")
                .disabled(actions == nil)
        }
        CommandGroup(before: .toolbar) {
            Picker("Sort By", selection: $sortOrder) {
                ForEach(SortOrder.allCases) { Text($0.title).tag($0) }
            }
            Button("Show Info Panel") { actions?.toggleInfo() }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(actions == nil)
            Divider()
            Button("Bigger Covers") { actions?.zoom(true) }
                .keyboardShortcut("+")
                .disabled(actions == nil)
            Button("Smaller Covers") { actions?.zoom(false) }
                .keyboardShortcut("-")
                .disabled(actions == nil)
            Divider()
        }
    }
}

/// The Game menu: controls for the game window in front.
struct GameCommands: Commands {
    @FocusedValue(\.gameActions) private var game

    var body: some Commands {
        CommandMenu("Game") {
            Button(game?.isPaused == true ? "Resume" : "Pause") { game?.togglePause() }
                .keyboardShortcut("p")
                .disabled(game?.isRunning != true)
            Button("Toggle Full Screen") { NSApp.keyWindow?.toggleFullScreen(nil) }
                .keyboardShortcut(.return)
                .disabled(game == nil)
            Button("Take Screenshot") { game?.takeScreenshot() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(game?.isRunning != true)
            Divider()
            Button("Faster") { game?.changeSpeed(true) }
                .keyboardShortcut("]")
                .disabled(game?.isRunning != true)
            Button("Slower") { game?.changeSpeed(false) }
                .keyboardShortcut("[")
                .disabled(game?.isRunning != true)
            Button("Next Disc") { game?.nextDisc() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(game?.isRunning != true || game?.hasMoreDiscs != true)
            Divider()
            Picker("Display Look", selection: Binding(get: { game?.look }, set: { game?.setLook($0) })) {
                Text("Default").tag(DisplayLook?.none)
                Divider()
                ForEach(DisplayLook.allCases) { Text($0.title).tag(DisplayLook?.some($0)) }
            }
            .disabled(game == nil)
            Button("Controls…") { game?.editControls() }
                .disabled(game == nil)
            Menu("Programs") {
                ForEach(game?.launchers ?? []) { launcher in
                    Button(launcher.displayName) { game?.run(.launcher(launcher)) }
                }
                Divider()
                Button("DOS Prompt") { game?.run(.prompt) }
            }
            .disabled(game == nil)
            Divider()
            Button("Restart") { game?.restart() }
                .keyboardShortcut("r")
                .disabled(game == nil)
            Button("Turn Off") { game?.turnOff() }
                .disabled(game?.isRunning != true)
        }
    }
}

/// Cover size: a small floating Liquid Glass capsule over the grid.
struct CoverSizeControl: View {
    @Binding var coverSize: Double
    let range: ClosedRange<Double>

    var body: some View {
        Slider(value: $coverSize, in: range)
            .frame(width: 120)
            .controlSize(.small)
            .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular.interactive(), in: .capsule)
        .help("Cover size")
    }
}
