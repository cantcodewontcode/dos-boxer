import DOSBoxerKit
import SwiftUI

/// Which games the library shows.
enum LibraryFilter: Hashable, Codable, RawRepresentable {
    case all, favorites, recentlyPlayed, neverPlayed
    case decade(Int)

    init?(rawValue: String) {
        switch rawValue {
        case "all": self = .all
        case "favorites": self = .favorites
        case "recentlyPlayed": self = .recentlyPlayed
        case "neverPlayed": self = .neverPlayed
        default:
            guard rawValue.hasPrefix("decade-"), let year = Int(rawValue.dropFirst(7)) else { return nil }
            self = .decade(year)
        }
    }

    var rawValue: String {
        switch self {
        case .all: "all"
        case .favorites: "favorites"
        case .recentlyPlayed: "recentlyPlayed"
        case .neverPlayed: "neverPlayed"
        case .decade(let year): "decade-\(year)"
        }
    }

    var title: String {
        switch self {
        case .all: "All Games"
        case .favorites: "Favorites"
        case .recentlyPlayed: "Recently Played"
        case .neverPlayed: "Never Played"
        case .decade(let year): "\(year)s"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .favorites: "heart"
        case .recentlyPlayed: "clock"
        case .neverPlayed: "sparkles"
        case .decade: "calendar"
        }
    }

    func includes(_ game: Gamebox) -> Bool {
        switch self {
        case .all: true
        case .favorites: game.info.isFavorite == true
        case .recentlyPlayed: game.stats.lastPlayed != nil
        case .neverPlayed: game.stats.launches == 0
        case .decade(let start): game.year.map { $0 / 10 * 10 == start } ?? false
        }
    }
}

/// The library's sidebar: smart lists, then one entry per decade.
struct LibrarySidebar: View {
    let library: GameLibrary
    @Binding var filter: LibraryFilter

    var body: some View {
        List(selection: Binding(get: { filter }, set: { if let new = $0 { filter = new } })) {
            Section("Library") {
                ForEach([LibraryFilter.all, .favorites, .recentlyPlayed, .neverPlayed], id: \.self) { item in
                    row(item)
                }
            }
            if !decades.isEmpty {
                Section("Decades") {
                    ForEach(decades, id: \.self) { decade in
                        row(.decade(decade))
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ item: LibraryFilter) -> some View {
        Label(item.title, systemImage: item.systemImage)
            .badge(library.games.filter(item.includes).count)
            .tag(item)
    }

    private var decades: [Int] {
        Set(library.games.compactMap { $0.year.map { $0 / 10 * 10 } }).sorted()
    }
}
