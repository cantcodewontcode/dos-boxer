import DOSBoxerKit
import SwiftUI
import UniformTypeIdentifiers

/// The games library: box art in a grid. Drop games in to add them;
/// double-click one to play.
struct LibraryView: View {
    let library: GameLibrary
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    /// What the file panel is open for. (One panel per view: SwiftUI only
    /// honors the last `.fileImporter` attached to a view.)
    enum FilePanel { case addGames }
    @State private var filePanel: FilePanel?
    @State private var searchText = ""
    @State private var isDropTargeted = false
    /// Selected games (⌘-click toggles, ⇧-click extends, drag a box).
    @State private var selection: Set<Gamebox.ID> = []
    /// Where a ⇧-click range starts: the last game clicked.
    @State private var selectionAnchor: Gamebox.ID?
    /// Each card's frame in the grid, for drag-to-select.
    @State private var cardFrames: [Gamebox.ID: CGRect] = [:]
    /// The box being dragged out to select games, and what was selected
    /// before it started (kept when ⌘ is held).
    @State private var marquee: CGRect?
    @State private var selectionBeforeMarquee: Set<Gamebox.ID> = []
    @State private var gameToRevert: Gamebox?
    /// The game whose rename / delete popover is showing.
    @State private var renaming: Gamebox.ID?
    /// The games waiting for delete confirmation, and the card the
    /// confirmation is anchored to.
    @State private var deleting: [Gamebox.ID] = []
    @State private var renamingCollection: GameCollection.ID?
    @FocusState private var searchFocused: Bool

    /// Cover width in points, set with the toolbar slider and remembered.
    @AppStorage("CoverSize") private var coverSize = 150.0
    private static let coverSizes = 100.0...260.0
    /// The cover size when a pinch began.
    @State private var pinchStartSize: Double?
    @AppStorage("SortOrder") private var sortOrder: SortOrder = .name
    @AppStorage("LibraryFilter") private var filter: LibraryFilter = .all
    @AppStorage("ShowGameInfo") private var showInfo = false
    /// Whether the game details download was offered (once, on first launch).
    @AppStorage("GameDetailsOffered") private var gameDetailsOffered = false
    @State private var offeringGameDetails = false

    /// When a game was last opened by double-click (cancels a pending rename).
    @State private var lastPlayRequest = Date.distantPast

    /// Height of the visible grid area.
    @State private var visibleHeight: CGFloat = 0

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: coverSize, maximum: coverSize * 1.2), spacing: coverSize * 0.16,
                  alignment: .top)]
    }

    var body: some View {
        NavigationSplitView {
            LibrarySidebar(library: library, filter: $filter, renamingCollection: $renamingCollection)
                .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 260)
        } detail: {
            detail
        }
        // Search sits at the top of the sidebar (as in Music), so it never
        // crowds the toolbar
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search games")
    }

    private var detail: some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Import Games…", systemImage: "square.and.arrow.down") { filePanel = .addGames }
                        .help("Import game folders, ZIP files or gameboxes")
                    Button("DOS Prompt", systemImage: "apple.terminal") { openWindow(id: "dos-prompt") }
                        .help("Open a DOS prompt")
                }
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItem(placement: .primaryAction) {
                    Menu("Sort", systemImage: "arrow.up.arrow.down") {
                        Picker("Sort By", selection: $sortOrder) {
                            ForEach(SortOrder.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.inline)
                    }
                    .help("Sort games")
                }
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItem(placement: .primaryAction) {
                    Button("Info", systemImage: "sidebar.squares.trailing") { showInfo.toggle() }
                        .help(showInfo ? "Hide game info" : "Show game info")
                }
            }
            // Cover size: a small floating glass control, bottom right
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomTrailing) {
                if !filteredGames.isEmpty {
                    CoverSizeControl(coverSize: $coverSize, range: Self.coverSizes)
                        .padding(16)
                }
            }
            .inspector(isPresented: $showInfo) {
                GameInspector(library: library, games: library.games.filter { selection.contains($0.id) },
                              play: play)
                    .inspectorColumnWidth(min: 260, ideal: 300, max: 420)

            }
            .navigationTitle(filter.title(in: library))
            .navigationSubtitle(subtitle)
            .searchFocused($searchFocused)
            .focusedSceneValue(\.libraryActions, LibraryActions(
                hasSelection: !selection.isEmpty,
                importGames: { filePanel = .addGames },
                play: { if let game = selectedGames.first { play(game) } },
                getInfo: { showInfo = true },
                showInFinder: { NSWorkspace.shared.activateFileViewerSelecting(selectedGames.map(\.url)) },
                selectAll: { selection = Set(filteredGames.map(\.id)) },
                moveToTrash: {
                    deleting = selectedGames.map(\.id)
                },
                find: { searchFocused = true },
                newLibrary: newLibrary,
                openLibrary: openLibrary,
                moveLibrary: moveLibrary,
                newCollection: newCollection,
                toggleInfo: { showInfo.toggle() },
                zoom: { bigger in
                    coverSize = min(max(coverSize + (bigger ? 25 : -25), Self.coverSizes.lowerBound),
                                    Self.coverSizes.upperBound)
                }))
            .onOpenURL { url in
                if ["dosgame", "boxer"].contains(url.pathExtension.lowercased()) {
                    openWindow(value: url)
                } else {
                    library.add([url])
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                importDropped(urls)
                return true
            } isTargeted: { isDropTargeted = $0 }
            .fileImporter(isPresented: Binding(get: { filePanel != nil }, set: { if !$0 { filePanel = nil } }),
                          allowedContentTypes: [.folder, .zip, .dosGame, .boxerGame,
                                                .init(filenameExtension: "pkg") ?? .data],
                          allowsMultipleSelection: filePanel == .addGames) { result in
                guard case .success(let urls) = result, let panel = filePanel else { return }
                switch panel {
                case .addGames: importDropped(urls)
                }
                filePanel = nil
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
            .sheet(isPresented: $offeringGameDetails) { GameDetailsPrompt() }
            // A year, genre or collection that's gone (or from another
            // library) falls back to All Games
            .onChange(of: library.games.map(\.id), initial: true) { fallBackIfFilterIsGone() }
            .onChange(of: library.collections.map(\.id)) { fallBackIfFilterIsGone() }
            .task {
                _ = GameDetailsPack.shared  // brings old game details up to date
                if !gameDetailsOffered {
                    gameDetailsOffered = true
                    offeringGameDetails = true
                }
            }
            #if DEBUG
            .task { runDebugLaunchOptions() }
            #endif
            // Moving games to the Trash: always asked in the middle of the
            // window, wherever the games are in the grid
            .alert(deletingTitle, isPresented: Binding(get: { !deleting.isEmpty }, set: { if !$0 { deleting = [] } })) {
                Button("Move to Trash", role: .destructive) {
                    let doomed = library.games.filter { deleting.contains($0.id) }
                    deleting = []
                    selection.subtract(doomed.map(\.id))
                    library.delete(doomed)
                }
                Button("Cancel", role: .cancel) { deleting = [] }
            } message: {
                Text(deleting.count == 1 ? "Its saved games will also be moved to the Trash."
                     : "Their saved games will also be moved to the Trash.")
            }
            // A game that's already in the library: asked one at a time,
            // or all at once with Apply to All (as the Finder does)
            .sheet(item: Binding(get: { library.duplicates.first }, set: { _ in })) { duplicate in
                DuplicateSheet(duplicate: duplicate, remaining: library.duplicates.count, library: library)
            }
            .modifier(MT32Suggestion(library: library))
            .alert("Failed to import", isPresented: .constant(library.importFailure != nil)) {
                Button("OK") { library.dismissImportFailure() }
            } message: {
                Text(library.importFailure ?? "")
            }
            .alert("Something went wrong", isPresented: .constant(library.lastError != nil)) {
                Button("OK") { library.dismissError() }
            } message: {
                Text(library.lastError ?? "")
            }
    }

    @ViewBuilder private var content: some View {
        if library.games.isEmpty && library.pendingImports.isEmpty {
            EmptyLibrary(isDropTargeted: isDropTargeted, addGames: { filePanel = .addGames })
        } else if filteredGames.isEmpty && library.pendingImports.isEmpty {
            ContentUnavailableView(searchText.isEmpty ? "No Games Here" : "No Matching Games",
                                   systemImage: filter.systemImage,
                                   description: Text(searchText.isEmpty
                                       ? "Games you add to \(filter.title(in: library)) appear here." : "Try a different search."))
        } else {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .center, spacing: coverSize * 0.19) {
                    ForEach(library.pendingImports) { pending in
                        PendingCard(name: pending.name, coverSize: coverSize)
                    }
                    ForEach(filteredGames) { game in
                        card(for: game)
                    }
                }
                .padding(28)
                // Fill at least the visible area, so empty space below the
                // games can be clicked too
                .frame(maxWidth: .infinity, minHeight: visibleHeight, alignment: .top)
                .coordinateSpace(.named("grid"))
                // ⌘A selects every game shown (text fields keep their own)
                .background(GridKeys(selectAll: { selection = Set(filteredGames.map(\.id)) },
                                     removeFromCollection: removeSelectionFromCollection))
                // Clicking empty space clears the selection, as in Finder;
                // dragging there draws a box that selects the games it touches
                .background {
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture {
                            NSApp.keyWindow?.makeFirstResponder(nil)
                            selection = []
                            renaming = nil
                        }
                        .gesture(marqueeGesture)
                }
                .overlay(alignment: .topLeading) {
                    if let marquee {
                        Rectangle()
                            .fill(.tint.opacity(0.12))
                            .strokeBorder(.tint.opacity(0.6), lineWidth: 1)
                            .frame(width: marquee.width, height: marquee.height)
                            .offset(x: marquee.minX, y: marquee.minY)
                            .allowsHitTesting(false)
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { visibleHeight = $0 }
            // Pinch to zoom the covers, like Photos
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let start = pinchStartSize ?? coverSize
                        pinchStartSize = start
                        coverSize = min(max(start * value.magnification, Self.coverSizes.lowerBound),
                                        Self.coverSizes.upperBound)
                    }
                    .onEnded { _ in pinchStartSize = nil }
            )
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

    /// The selected games, in grid order.
    private var selectedGames: [Gamebox] {
        filteredGames.filter { selection.contains($0.id) }
    }

    private var deletingTitle: String {
        if deleting.count == 1, let game = library.games.first(where: { $0.id == deleting[0] }) {
            return "Move “\(game.title)” to the Trash?"
        }
        return "Move \(deleting.count) games to the Trash?"
    }

    // MARK: Libraries

    /// File › New Library…: an empty library in a folder you choose (or make).
    private func newLibrary() {
        chooseFolder(message: "Choose or create a folder for the new library.", prompt: "Create") { folder in
            library.useLibrary(at: folder)
        }
    }

    /// File › Open Library…: switch to another library.
    private func openLibrary() {
        chooseFolder(message: "Choose a DOS Boxer library to open.", prompt: "Open") { folder in
            guard GameLibrary.isLibrary(folder) else {
                library.reportError("That folder isn't a DOS Boxer library. To start one there, use File › New Library.")
                return
            }
            library.useLibrary(at: folder)
        }
    }

    /// File › Move Library…: move this library, games and all, elsewhere.
    private func moveLibrary() {
        chooseFolder(message: "Choose where to move your library. It keeps its name, “\(library.rootURL.lastPathComponent)”.",
                     prompt: "Move") { folder in
            do {
                try library.moveLibrary(into: folder)
            } catch {
                library.reportError("Couldn't move the library: \(error.localizedDescription)")
            }
        }
    }

    private func chooseFolder(message: String, prompt: String, then action: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = message
        panel.prompt = prompt
        guard let window = NSApp.keyWindow else { return }
        panel.beginSheetModal(for: window) { response in
            if response == .OK, let folder = panel.url { action(folder) }
        }
    }

    /// Delete in a collection: take the selected games out of it (they stay
    /// in the library). Returns false when not viewing a collection.
    private func removeSelectionFromCollection() -> Bool {
        guard case .collection(let id) = filter, !selection.isEmpty else { return false }
        for game in selection { library.remove(game, fromCollection: id) }
        selection = []
        return true
    }

    private func fallBackIfFilterIsGone() {
        let exists = switch filter {
        case .year, .genre: library.games.contains { filter.includes($0, in: library) }
        case .collection(let id): library.collections.contains { $0.id == id }
        default: true
        }
        if !exists, !library.games.isEmpty { filter = .all }
    }

    private var filteredGames: [Gamebox] {
        var games = library.games.filter { filter.includes($0, in: library) }
        if !searchText.isEmpty {
            games = games.filter { $0.name.localizedStandardContains(searchText) }
        }
        // Recently Played and Recently Added always list the latest first
        let order: SortOrder = switch filter {
        case .recentlyPlayed: .recentlyPlayed
        case .recentlyAdded: .recentlyAdded
        default: sortOrder
        }
        return order.sorted(games)
    }

    private var subtitle: String {
        let count = filteredGames.count
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

    /// One game in the grid, with its clicks, drags, drops and menus.
    private func card(for game: Gamebox) -> some View {
        GameCard(gamebox: game, isSelected: selection.contains(game.id), coverSize: coverSize,
                 isFindingCover: library.findingCovers.contains(game.id),
                 isRenaming: renaming == game.id,
                 clickName: { _ in
                     // Like Finder: clicking the name of the one selected
                     // game renames it, after a short pause so a double-
                     // click to play doesn't also start a rename
                     let wasOnlySelection = selection == [game.id]
                     click(game)
                     guard wasOnlySelection, !game.isReadOnly else { return }
                     let clickedAt = Date()
                     lastPlayRequest = .distantPast
                     Task {
                         try? await Task.sleep(for: .seconds(0.5))
                         if selection == [game.id], lastPlayRequest < clickedAt {
                             renaming = game.id
                         }
                     }
                 },
                 finishRename: { newName in
                     // Return also ends editing by losing focus; act once
                     guard renaming == game.id else { return }
                     renaming = nil
                     if let newName { library.rename(game, to: newName) }
                 })
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("grid")) } action: {
                cardFrames[game.id] = $0
            }
            // Drag games (the whole selection, if this one's in it)
            // onto a collection in the sidebar
            .draggable(dragPayload(for: game)) {
                DragPreview(game: game, count: targets(for: game).count)
            }
            // Drop an image on a game to make it the cover. Anything else
            // is games to add, as anywhere in the library (a drop this
            // turned down wouldn't reach the library behind it)
            .dropDestination(for: URL.self) { urls, _ in
                if urls.count == 1, ["png", "jpg", "jpeg", "heic"].contains(urls[0].pathExtension.lowercased()) {
                    library.setCover(of: game, to: urls[0])
                } else {
                    importDropped(urls)
                }
                return true
            }
            .onTapGesture(count: 2) { play(game) }
            .simultaneousGesture(TapGesture().onEnded { click(game) })
            .contextMenu { contextMenu(for: game) }
    }

    // MARK: Selection

    /// A click on a game: ⌘ toggles it, ⇧ extends from the last click,
    /// otherwise it becomes the only selected game.
    private func click(_ game: Gamebox) {
        // Clicking a game ends any text editing (e.g. in the info panel)
        NSApp.keyWindow?.makeFirstResponder(nil)
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selection.contains(game.id) { selection.remove(game.id) } else { selection.insert(game.id) }
            selectionAnchor = game.id
        } else if flags.contains(.shift), let anchor = selectionAnchor,
                  let from = filteredGames.firstIndex(where: { $0.id == anchor }),
                  let to = filteredGames.firstIndex(where: { $0.id == game.id }) {
            selection = Set(filteredGames[min(from, to)...max(from, to)].map(\.id))
        } else {
            selection = [game.id]
            selectionAnchor = game.id
        }
    }

    private var marqueeGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("grid"))
            .onChanged { drag in
                if marquee == nil {
                    selectionBeforeMarquee = NSEvent.modifierFlags.contains(.command) ? selection : []
                    renaming = nil
                }
                let box = CGRect(x: min(drag.startLocation.x, drag.location.x),
                                 y: min(drag.startLocation.y, drag.location.y),
                                 width: abs(drag.location.x - drag.startLocation.x),
                                 height: abs(drag.location.y - drag.startLocation.y))
                marquee = box
                let touched = cardFrames.filter { id, frame in
                    frame.intersects(box) && filteredGames.contains { $0.id == id }
                }.keys
                selection = selectionBeforeMarquee.union(touched)
            }
            .onEnded { _ in marquee = nil }
    }

    /// The games an action on `game` applies to: the whole selection if
    /// `game` is part of it, otherwise just `game`.
    private func targets(for game: Gamebox) -> [Gamebox] {
        guard selection.contains(game.id), selection.count > 1 else { return [game] }
        return filteredGames.filter { selection.contains($0.id) }
    }

    /// What dragging `game` carries: the IDs of the games being dragged,
    /// one per line.
    private func dragPayload(for game: Gamebox) -> String {
        targets(for: game).map(\.id.uuidString).joined(separator: "\n")
    }

    @ViewBuilder private func contextMenu(for game: Gamebox) -> some View {
        let games = targets(for: game)
        let single = games.count == 1
        if single {
            Button("Play") { play(game) }
        }
        let allFavorite = games.allSatisfy { $0.info.isFavorite == true }
        Button(allFavorite ? "Remove from Favorites" : "Add to Favorites") {
            library.setFavorite(games, !allFavorite)
        }
        Menu("Add to Collection") {
            ForEach(library.collections) { collection in
                Button(collection.name) { library.add(games.map(\.id), toCollection: collection.id) }
            }
            if !library.collections.isEmpty { Divider() }
            Button("New Collection") {
                let collection = library.createCollection(with: games)
                filter = .collection(collection.id)
                renamingCollection = collection.id
            }
        }
        if case .collection(let id) = filter {
            Button("Remove from Collection") {
                for game in games { library.remove(game.id, fromCollection: id) }
            }
        }
        if single {
            Button("Get Info") {
                selection = [game.id]
                showInfo = true
            }
        }
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(games.map(\.url))
        }
        if single {
            Divider()
            if game.info.launchBoxID == nil {
                Button("Find Game Details") { library.findDetails(for: game) }
                    .disabled(game.isReadOnly)
            } else {
                Button("Forget Game Details") { library.forgetDetails(of: game) }
                    .disabled(game.isReadOnly)
            }
            Button("Find Cover Art") { library.findCoverArt(for: game) }
            Button("Remove Cover Art") { library.removeCover(of: game) }
                .disabled(game.coverURL == nil)
            Divider()
            Button("Rename") {
                selection = [game.id]
                renaming = game.id
            }
            .disabled(game.isReadOnly)
        }
        Divider()
        Button(single ? "Move to Trash…" : "Move \(games.count) Games to Trash…") {
            deleting = games.map(\.id)
        }
        if single {
            Button("Revert to Original…") { gameToRevert = game }
        }
    }

    /// Dropped files: MT-32 ROMs go to Settings › Music (which opens to
    /// show they're installed); everything else is imported as games.
    private func importDropped(_ urls: [URL]) {
        // Sorting ROMs from games reads the files: do it off the main thread
        Task {
            let (games, roms, fonts) = await Task.detached(priority: .userInitiated) {
                var games: [URL] = []
                var roms: [URL] = []
                var fonts: [URL] = []
                for url in urls {
                    if SoundFontSetup.isSoundFont(url) { fonts.append(url) }
                    else if let found = MT32Setup.roms(in: url) { roms += found } else { games.append(url) }
                }
                return (games, roms, fonts)
            }.value
            addDropped(games: games, roms: roms, fonts: fonts)
        }
    }

    private func addDropped(games: [URL], roms: [URL], fonts: [URL]) {
        if !roms.isEmpty || !fonts.isEmpty {
            // Shown even if they were all installed already
            _ = try? MT32Setup.install(from: roms)
            _ = try? SoundFontSetup.install(from: fonts)
            UserDefaults.standard.set(SettingsTab.music.rawValue, forKey: SettingsTab.defaultsKey)
            NotificationCenter.default.post(name: .mt32ROMsChanged, object: nil)
            openSettings()
        }
        if !games.isEmpty { library.add(games) }
    }

    private func newCollection() {
        let collection = library.createCollection()
        filter = .collection(collection.id)
        renamingCollection = collection.id
    }

    private func play(_ game: Gamebox) {
        lastPlayRequest = Date()
        openWindow(value: game.url)
    }
}

/// How the library grid is ordered. Ties always fall back to the name.
enum SortOrder: String, CaseIterable, Identifiable {
    case name, year, rating, developer, publisher, recentlyPlayed, mostPlayed, recentlyAdded

    var id: Self { self }

    var title: String {
        switch self {
        case .name: "Name"
        case .year: "Year"
        case .rating: "Rating"
        case .developer: "Developer"
        case .publisher: "Publisher"
        case .recentlyPlayed: "Recently Played"
        case .mostPlayed: "Most Played"
        case .recentlyAdded: "Recently Added"
        }
    }

    func sorted(_ games: [Gamebox]) -> [Gamebox] {
        func byName(_ a: Gamebox, _ b: Gamebox) -> Bool {
            GameNames.sortKey(a.name).localizedStandardCompare(GameNames.sortKey(b.name)) == .orderedAscending
        }
        /// Orders by `key` (games without one last), then by name.
        func by<Key: Comparable>(_ key: (Gamebox) -> Key?, descending: Bool) -> [Gamebox] {
            games.sorted { a, b in
                switch (key(a), key(b)) {
                case let (x?, y?) where x != y: descending ? x > y : x < y
                case (_?, nil): true
                case (nil, _?): false
                default: byName(a, b)
                }
            }
        }
        switch self {
        case .name: return games.sorted(by: byName)
        case .year: return by({ $0.year }, descending: false)
        case .rating: return by({ $0.info.communityRating }, descending: true)
        case .developer: return by({ $0.info.developer?.lowercased() }, descending: false)
        case .publisher: return by({ $0.info.publisher?.lowercased() }, descending: false)
        case .recentlyPlayed: return by({ $0.stats.lastPlayed }, descending: true)
        case .mostPlayed: return by({ $0.stats.launches > 0 ? $0.stats.launches : nil }, descending: true)
        case .recentlyAdded: return by({ $0.addedDate }, descending: true)
        }
    }
}

/// One game in the grid: its box art with the name underneath. The name
/// turns into a text field while the game is being renamed.
private struct GameCard: View {
    let gamebox: Gamebox
    let isSelected: Bool
    let coverSize: Double
    /// Looking for box art: the cover shows a spinner.
    let isFindingCover: Bool
    let isRenaming: Bool
    /// Called when the name is clicked, with whether the game was already
    /// selected before this click.
    let clickName: (_ wasSelected: Bool) -> Void
    /// Called with the new name, or nil if renaming was canceled.
    let finishRename: (String?) -> Void

    @State private var editedName = ""
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            CoverImage(gamebox: gamebox, isLoading: isFindingCover)
                .frame(height: coverSize * 1.25, alignment: .bottom)
            if isRenaming {
                // Grows to a second line only when the name needs it
                TextField("Name", text: $editedName, axis: .vertical)
                    .lineLimit(1...2)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .font(.callout.weight(.medium))
                    .focused($nameFieldFocused)
                    .onSubmit { finishRename(editedName.replacingOccurrences(of: "\n", with: " ")) }
                    // Return saves (a multi-line field would otherwise add a line)
                    .onKeyPress(.return) {
                        finishRename(editedName.replacingOccurrences(of: "\n", with: " "))
                        return .handled
                    }
                    .onExitCommand { finishRename(nil) }
                    .onChange(of: nameFieldFocused) { _, focused in
                        // Clicking away keeps the new name, as in Finder
                        if !focused { finishRename(editedName.replacingOccurrences(of: "\n", with: " ")) }
                    }
                    .onAppear {
                        editedName = gamebox.title
                        nameFieldFocused = true
                    }
            } else {
                Text(gamebox.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .help(gamebox.name)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(isSelected ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.clear),
                                in: .capsule)
                    // `isSelected` here is the state before this click
                    .onTapGesture { clickName(isSelected) }
            }
        }
        .contentShape(.rect)
        .help("Double-click to play")
    }
}

/// Confirms moving games to the Trash, in a glass popover by a cover.

/// What follows the pointer when dragging games: the cover, with a count
/// badge for several.
private struct DragPreview: View {
    let game: Gamebox
    let count: Int

    var body: some View {
        CoverImage(gamebox: game)
            .frame(width: 80, height: 100)
            .overlay(alignment: .topTrailing) {
                if count > 1 {
                    Text("\(count)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.red, in: .capsule)
                        .offset(x: 8, y: -8)
                }
            }
    }
}

/// A game still being copied into the library.
private struct PendingCard: View {
    let name: String
    let coverSize: Double

    var body: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary)
                .aspectRatio(0.8, contentMode: .fit)
                .overlay { ProgressView() }
                .frame(height: coverSize * 1.25, alignment: .bottom)
            Text("Importing \(name)…")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
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
            Text("Import Your DOS Games")
                .font(.title2.weight(.semibold))
            Text("Drop game folders or ZIP files here. DOS Boxer keeps a copy of each game in your library, so your originals stay untouched.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 340)
            Button("Import Games…", action: addGames)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        }
        .padding(32)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// ⌘A in this view's window selects all games, unless text is being edited
/// (where it selects the text, as usual).
/// Keys for the game grid: ⌘A selects all games, unless text is being
/// edited; Delete (without ⌘) removes the selection from the collection
/// being viewed, unless the sidebar or a text field has the keyboard.
private struct GridKeys: NSViewRepresentable {
    let selectAll: () -> Void
    /// Returns whether it removed anything.
    let removeFromCollection: () -> Bool

    /// Invisible to clicks, so empty space behind it still clears the selection.
    final class PassThroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> NSView {
        let view = PassThroughView()
        context.coordinator.view = view
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak coordinator = context.coordinator] event in
            guard let coordinator, let window = coordinator.view?.window, event.window === window,
                  !(window.firstResponder is NSText) else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if modifiers == .command, event.charactersIgnoringModifiers == "a" {
                coordinator.selectAll()
                return nil
            }
            // Delete (backspace or forward delete), not ⌘⌫ (Move to Trash), and
            // not while the sidebar list has the keyboard (deletes a collection)
            if modifiers.isEmpty, event.keyCode == 51 || event.keyCode == 117,
               !(window.firstResponder is NSTableView), coordinator.removeFromCollection() {
                return nil
            }
            return event
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.selectAll = selectAll
        context.coordinator.removeFromCollection = removeFromCollection
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(selectAll: selectAll, removeFromCollection: removeFromCollection) }

    final class Coordinator {
        var selectAll: () -> Void
        var removeFromCollection: () -> Bool
        weak var view: NSView?
        var monitor: Any?
        init(selectAll: @escaping () -> Void, removeFromCollection: @escaping () -> Bool) {
            self.selectAll = selectAll
            self.removeFromCollection = removeFromCollection
        }
    }
}

/// A game made for the MT-32 was added and no MT-32 files are installed:
/// suggest setting them up in Settings › Music (asked once).
private struct MT32Suggestion: ViewModifier {
    let library: GameLibrary
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content.alert(library.mt32Suggestion.map { "Hear “\($0.title)” with a Roland MT-32?" } ?? "",
                      isPresented: Binding(get: { library.mt32Suggestion != nil }, set: { _ in }),
                      presenting: library.mt32Suggestion) { _ in
            Button("Set Up MT-32…") {
                library.dismissMT32Suggestion()
                UserDefaults.standard.set(SettingsTab.music.rawValue, forKey: SettingsTab.defaultsKey)
                openSettings()
            }
            Button("Not Now", role: .cancel) { library.dismissMT32Suggestion() }
        } message: { _ in
            Text("Its music was composed for this classic synthesizer. Add the MT-32 files once to hear it, and every game like it, as intended.")
        }
    }
}

/// A game being added that's already in the library: keep both, skip or
/// replace. With several waiting, the choice applies to them all.
private struct DuplicateSheet: View {
    let duplicate: GameLibrary.DuplicateImport
    let remaining: Int
    let library: GameLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(remaining > 1 ? "Duplicate games detected" : duplicate.existing.title)
                .font(.headline)
            Text(remaining > 1
                 ? "Some of the games being imported are already in your library. Do you want to replace them?"
                 : "This game is already in your library. Do you want to replace it?")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Keep Both") { choose(.keepBoth) }
                Button("Skip", role: .cancel) { choose(.skip) }
                    .keyboardShortcut(.cancelAction)
                Button("Replace") { choose(.replace) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func choose(_ choice: GameLibrary.DuplicateChoice) {
        if remaining > 1 { library.resolveAll(choice) } else { library.resolve(duplicate, choice) }
    }
}
