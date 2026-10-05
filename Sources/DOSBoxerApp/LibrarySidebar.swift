import DOSBoxerKit
import SwiftUI

/// Which games the library shows.
enum LibraryFilter: Hashable, Codable, RawRepresentable {
    case all, favorites, recentlyPlayed, neverPlayed
    case year(Int)
    case genre(String)
    case collection(UUID)

    init?(rawValue: String) {
        switch rawValue {
        case "all": self = .all
        case "favorites": self = .favorites
        case "recentlyPlayed": self = .recentlyPlayed
        case "neverPlayed": self = .neverPlayed
        default:
            if rawValue.hasPrefix("collection-"), let id = UUID(uuidString: String(rawValue.dropFirst(11))) {
                self = .collection(id)
            } else if rawValue.hasPrefix("year-"), let year = Int(rawValue.dropFirst(5)) {
                self = .year(year)
            } else if rawValue.hasPrefix("genre-") {
                self = .genre(String(rawValue.dropFirst(6)))
            } else {
                return nil
            }
        }
    }

    var rawValue: String {
        switch self {
        case .all: "all"
        case .favorites: "favorites"
        case .recentlyPlayed: "recentlyPlayed"
        case .neverPlayed: "neverPlayed"
        case .year(let year): "year-\(year)"
        case .genre(let genre): "genre-\(genre)"
        case .collection(let id): "collection-\(id.uuidString)"
        }
    }

    @MainActor func title(in library: GameLibrary) -> String {
        if case .collection(let id) = self {
            return library.collections.first { $0.id == id }?.name ?? "Collection"
        }
        return title
    }

    var title: String {
        switch self {
        case .all: "All Games"
        case .favorites: "Favorites"
        case .recentlyPlayed: "Recently Played"
        case .neverPlayed: "Never Played"
        case .year(let year): String(year)
        case .genre(let genre): genre
        case .collection: "Collection"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .favorites: "heart"
        case .recentlyPlayed: "clock"
        case .neverPlayed: "sparkles"
        case .year: "calendar"
        case .genre: "tag"
        case .collection: "rectangle.stack"
        }
    }

    @MainActor func includes(_ game: Gamebox, in library: GameLibrary) -> Bool {
        switch self {
        case .all: true
        case .favorites: game.info.isFavorite == true
        case .recentlyPlayed: game.stats.lastPlayed != nil
        case .neverPlayed: game.stats.launches == 0
        case .year(let year): game.year == year
        case .genre(let genre): game.info.genreList.contains(genre)
        case .collection(let id): library.collections.first { $0.id == id }?.gameIDs.contains(game.id) ?? false
        }
    }
}

/// The library's sidebar: smart lists, hand-built collections, and years.
struct LibrarySidebar: View {
    let library: GameLibrary
    @Binding var filter: LibraryFilter
    /// The collection whose name is being edited.
    @Binding var renamingCollection: GameCollection.ID?

    var body: some View {
        List(selection: Binding(get: { filter }, set: { if let new = $0 { filter = new } })) {
            Section("Library") {
                ForEach([LibraryFilter.all, .favorites, .recentlyPlayed, .neverPlayed], id: \.self) { item in
                    row(item)
                }
            }
            Section {
                ForEach(library.collections) { collection in
                    collectionRow(collection)
                }
            } header: {
                HStack {
                    Text("Collections")
                    Spacer()
                    Button {
                        newCollection()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    // Lines up with the game counts in the rows below
                    .padding(.trailing, 12)
                    .help("New Collection")
                }
            }
            if !years.isEmpty {
                Section("Years") {
                    ForEach(years, id: \.self) { year in
                        row(.year(year))
                    }
                }
            }
            if !genres.isEmpty {
                Section("Genres") {
                    ForEach(genres, id: \.self) { genre in
                        row(.genre(genre))
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ item: LibraryFilter) -> some View {
        Label(item.title, systemImage: item.systemImage)
            .badge(library.games.filter { item.includes($0, in: library) }.count)
            .tag(item)
    }

    private func collectionRow(_ collection: GameCollection) -> some View {
        CollectionRow(library: library, collection: collection, filter: $filter,
                      renamingCollection: $renamingCollection)
            .tag(LibraryFilter.collection(collection.id))
    }

    private func newCollection() {
        let collection = library.createCollection()
        filter = .collection(collection.id)
        renamingCollection = collection.id
    }

    /// Genres the library's games have, in the standard order.
    private var genres: [String] {
        let present = Set(library.games.flatMap(\.info.genreList))
        return GameGenres.all.filter(present.contains) + present.subtracting(GameGenres.all).sorted()
    }

    private var years: [Int] {
        Set(library.games.compactMap(\.year)).sorted()
    }
}

/// One collection in the sidebar. Games dropped on it are added to it; it
/// lights up while games are dragged over it.
private struct CollectionRow: View {
    let library: GameLibrary
    let collection: GameCollection
    @Binding var filter: LibraryFilter
    @Binding var renamingCollection: GameCollection.ID?
    @State private var isDropTarget = false

    var body: some View {
        Group {
            if renamingCollection == collection.id {
                CollectionNameField(name: collection.name) { newName in
                    renamingCollection = nil
                    if let newName { library.renameCollection(collection.id, to: newName) }
                }
            } else {
                Label(collection.name, systemImage: "rectangle.stack")
                    .badge(collection.gameIDs.filter { id in library.games.contains { $0.id == id } }.count)
            }
        }
        .listRowBackground(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(isDropTarget ? 0.9 : 0))
                .padding(.horizontal, 10)
        )
        // Selected-row text while a drop is over it; otherwise the list's own
        // colours, which dim with the rest when the window isn't in front
        .environment(\.backgroundProminence, isDropTarget ? .increased : .standard)
        // Drop games from the grid onto a collection to add them
        .dropDestination(for: String.self) { payloads, _ in
            // Each payload is one or more game IDs, one per line
            let ids = payloads.flatMap { $0.split(separator: "\n") }.compactMap { UUID(uuidString: String($0)) }
            library.add(ids, toCollection: collection.id)
            return !ids.isEmpty
        } isTargeted: { isDropTarget = $0 }
        .contextMenu {
            Button("Rename") { renamingCollection = collection.id }
            Button("Delete Collection", role: .destructive) {
                if filter == .collection(collection.id) { filter = .all }
                library.deleteCollection(collection.id)
            }
        }
    }
}

/// Edits a collection's name in place; Return saves, Escape cancels.
private struct CollectionNameField: View {
    let name: String
    let done: (String?) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Name", text: $text)
            .focused($focused)
            .onSubmit { finish(text) }
            .onExitCommand { finish(nil) }
            .onChange(of: focused) { _, isFocused in if !isFocused { finish(text) } }
            .onAppear {
                text = name
                focused = true
            }
    }

    @State private var finished = false

    private func finish(_ value: String?) {
        guard !finished else { return }
        finished = true
        done(value)
    }
}
