import DOSBoxerKit
import SwiftUI

/// What the library window can do from the menu bar.
struct LibraryActions {
    var importGames: () -> Void
    var chooseLocation: () -> Void
    var newCollection: () -> Void
    var toggleInfo: () -> Void
    /// true for bigger covers, false for smaller.
    var zoom: (_ bigger: Bool) -> Void
}

extension FocusedValues {
    @Entry var libraryActions: LibraryActions?
}

/// The File and View menu items for the library.
struct LibraryCommands: Commands {
    let library: GameLibrary
    @FocusedValue(\.libraryActions) private var actions
    @Environment(\.openWindow) private var openWindow
    @AppStorage("SortOrder") private var sortOrder: SortOrder = .name

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
        }
        CommandGroup(after: .saveItem) {
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
        CommandGroup(before: .toolbar) {
            Picker("Sort By", selection: $sortOrder) {
                ForEach(SortOrder.allCases) { Text($0.title).tag($0) }
            }
            Button("Show Info") { actions?.toggleInfo() }
                .keyboardShortcut("i")
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
