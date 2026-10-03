import DOSBoxerKit
import SwiftUI
import UniformTypeIdentifiers

/// The games library: box art in a grid. Drop games in to add them;
/// double-click one to play.
struct LibraryView: View {
    let library: GameLibrary
    @Environment(\.openWindow) private var openWindow

    @State private var addingGames = false
    @State private var choosingLocation = false
    @State private var searchText = ""
    @State private var isDropTargeted = false
    @State private var selection: Gamebox.ID?
    @State private var gameToRevert: Gamebox?

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 24)]

    var body: some View {
        content
            .navigationTitle("Library")
            .navigationSubtitle(subtitle)
            .searchable(text: $searchText, prompt: "Search games")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if library.importsInProgress > 0 {
                        ProgressView().controlSize(.small).help("Adding games…")
                    }
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Add Games…", systemImage: "plus") { addingGames = true }
                        .help("Add game folders, ZIP files or gameboxes")
                    Menu("Library", systemImage: "ellipsis") {
                        Button("Show Library in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([library.rootURL])
                        }
                        Button("Choose Library Location…") { choosingLocation = true }
                        Divider()
                        Button("Open DOS Prompt") { openWindow(id: "dos-prompt") }
                    }
                }
            }
            .onOpenURL { url in
                if ["dosgame", "boxer"].contains(url.pathExtension.lowercased()) {
                    openWindow(value: url)
                } else {
                    library.add([url])
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                library.add(urls)
                return true
            } isTargeted: { isDropTargeted = $0 }
            .fileImporter(isPresented: $addingGames,
                          allowedContentTypes: [.folder, .zip, .dosGame],
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { library.add(urls) }
            }
            .fileImporter(isPresented: $choosingLocation, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { library.useLibrary(at: url) }
            }
            .confirmationDialog("Revert \(gameToRevert?.name ?? "this game") to how it was added?",
                                isPresented: .constant(gameToRevert != nil), presenting: gameToRevert) { game in
                Button("Revert", role: .destructive) {
                    library.revertToOriginal(game)
                    gameToRevert = nil
                }
                Button("Cancel", role: .cancel) { gameToRevert = nil }
            } message: { _ in
                Text("Saved games, high scores and settings the game changed will be deleted.")
            }
            #if DEBUG
            .task { runDebugLaunchOptions() }
            #endif
            .alert("Something went wrong", isPresented: .constant(library.lastError != nil)) {
                Button("OK") { library.dismissError() }
            } message: {
                Text(library.lastError ?? "")
            }
    }

    @ViewBuilder private var content: some View {
        if library.games.isEmpty {
            EmptyLibrary(isDropTargeted: isDropTargeted, addGames: { addingGames = true })
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 28) {
                    ForEach(filteredGames) { game in
                        GameCard(gamebox: game, isSelected: selection == game.id)
                            .onTapGesture(count: 2) { play(game) }
                            .simultaneousGesture(TapGesture().onEnded { selection = game.id })
                            .contextMenu {
                                Button("Play") { play(game) }
                                Button("Show in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([game.url])
                                }
                                Divider()
                                Button("Revert to Original…") { gameToRevert = game }
                            }
                    }
                }
                .padding(28)
            }
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.tint, lineWidth: 3)
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var filteredGames: [Gamebox] {
        guard !searchText.isEmpty else { return library.games }
        return library.games.filter { $0.name.localizedStandardContains(searchText) }
    }

    private var subtitle: String {
        let count = library.games.count
        return count == 1 ? "1 game" : "\(count) games"
    }

    #if DEBUG
    /// Development aid: `-DOSBoxerImport "<path>|<path>"` adds games at launch;
    /// `-DOSBoxerPlay <name>` opens that game once it's in the library.
    /// (`-LibraryPath <folder>` picks a scratch library.)
    private func runDebugLaunchOptions() {
        let defaults = UserDefaults.standard
        if let paths = defaults.string(forKey: "DOSBoxerImport") {
            library.add(paths.split(separator: "|").map { URL(filePath: String($0)) })
        }
        if let name = defaults.string(forKey: "DOSBoxerPlay") {
            Task {
                for _ in 0..<60 {
                    if let game = library.games.first(where: { $0.name == name }) {
                        play(game)
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        }
    }
    #endif

    private func play(_ game: Gamebox) {
        openWindow(value: game.url)
    }
}

/// One game in the grid: its box art with the name underneath.
private struct GameCard: View {
    let gamebox: Gamebox
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 10) {
            CoverImage(gamebox: gamebox)
                .frame(height: 190, alignment: .bottom)
            Text(gamebox.name)
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isSelected ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.clear),
                            in: .capsule)
        }
        .contentShape(.rect)
        .help("Double-click to play")
    }
}

/// First-run state: a glass card inviting people to drop games in.
private struct EmptyLibrary: View {
    let isDropTargeted: Bool
    let addGames: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: isDropTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(isDropTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            Text("Add Your DOS Games")
                .font(.title2.weight(.semibold))
            Text("Drop game folders or ZIP files here. DOS Boxer keeps a copy of each game in your library, so your originals stay untouched.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 340)
            Button("Add Games…", action: addGames)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        }
        .padding(32)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
