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
    /// honours the last `.fileImporter` attached to a view.)
    enum FilePanel { case addGames, chooseLocation }
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
    @State private var deletingAnchor: Gamebox.ID?
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
                    deletingAnchor = deleting.first
                },
                find: { searchFocused = true },
                chooseLocation: { filePanel = .chooseLocation },
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
                          allowedContentTypes: filePanel == .chooseLocation ? [.folder] : [.folder, .zip, .dosGame, .boxerGame],
                          allowsMultipleSelection: filePanel == .addGames) { result in
                guard case .success(let urls) = result, let panel = filePanel else { return }
                switch panel {
                case .addGames: importDropped(urls)
                case .chooseLocation: if let url = urls.first { library.useLibrary(at: url) }
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
            .task {
                if !gameDetailsOffered {
                    gameDetailsOffered = true
                    offeringGameDetails = true
                }
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
                // Edit › Select All (⌘A) selects every game shown, when the
                // grid has focus (text fields keep their own Select All)
                .focusable()
                .focusEffectDisabled()
                .onCommand(#selector(NSText.selectAll(_:))) {
                    selection = Set(filteredGames.map(\.id))
                }
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

    private var filteredGames: [Gamebox] {
        var games = library.games.filter { filter.includes($0, in: library) }
        if !searchText.isEmpty {
            games = games.filter { $0.name.localizedStandardContains(searchText) }
        }
        // Recently Played always lists the latest first
        return (filter == .recentlyPlayed ? SortOrder.recentlyPlayed : sortOrder).sorted(games)
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
            // Drop an image on a game to make it the cover
            .dropDestination(for: URL.self) { urls, _ in
                guard let image = urls.first(where: {
                    ["png", "jpg", "jpeg", "heic"].contains($0.pathExtension.lowercased())
                }) else { return false }
                library.setCover(of: game, to: image)
                return true
            }
            .popover(isPresented: Binding(get: { deletingAnchor == game.id },
                                          set: { if !$0 { deletingAnchor = nil; deleting = [] } }),
                     arrowEdge: .bottom) {
                DeletePopover(games: library.games.filter { deleting.contains($0.id) }) {
                    let doomed = library.games.filter { deleting.contains($0.id) }
                    deletingAnchor = nil
                    deleting = []
                    selection.subtract(doomed.map(\.id))
                    library.delete(doomed)
                } cancel: {
                    deletingAnchor = nil
                    deleting = []
                }
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
            deletingAnchor = game.id
        }
        if single {
            Button("Revert to Original…") { gameToRevert = game }
        }
    }

    /// Dropped files: MT-32 ROMs go to Settings › Music (which opens to
    /// show they're installed); everything else is imported as games.
    private func importDropped(_ urls: [URL]) {
        var games: [URL] = []
        var roms: [URL] = []
        for url in urls {
            if let found = MT32Setup.roms(in: url) { roms += found } else { games.append(url) }
        }
        if !roms.isEmpty, (try? MT32Setup.install(from: roms)) ?? 0 > 0 {
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
    case name, year, recentlyPlayed, mostPlayed, recentlyAdded

    var id: Self { self }

    var title: String {
        switch self {
        case .name: "Name"
        case .year: "Year"
        case .recentlyPlayed: "Recently Played"
        case .mostPlayed: "Most Played"
        case .recentlyAdded: "Recently Added"
        }
    }

    func sorted(_ games: [Gamebox]) -> [Gamebox] {
        func byName(_ a: Gamebox, _ b: Gamebox) -> Bool {
            a.name.localizedStandardCompare(b.name) == .orderedAscending
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
    let isRenaming: Bool
    /// Called when the name is clicked, with whether the game was already
    /// selected before this click.
    let clickName: (_ wasSelected: Bool) -> Void
    /// Called with the new name, or nil if renaming was cancelled.
    let finishRename: (String?) -> Void

    @State private var editedName = ""
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            CoverImage(gamebox: gamebox)
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
private struct DeletePopover: View {
    let games: [Gamebox]
    let delete: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(games.count == 1 ? "Move “\(games[0].name)” to the Trash?" : "Move \(games.count) games to the Trash?")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(games.count == 1 ? "Its saved games will also be moved to the Trash."
                 : "Their saved games will also be moved to the Trash.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                Button("Move to Trash", role: .destructive, action: delete)
                    .buttonStyle(.glassProminent)
                    .tint(.red)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .frame(width: 280)
        .padding(18)
    }
}

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
