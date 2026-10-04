import DOSBoxerKit
import SwiftUI

/// The fold-out info panel on the right of the library: the selected game's
/// cover, stats, programs, settings and documents.
struct GameInspector: View {
    let library: GameLibrary
    let game: Gamebox?
    let play: (Gamebox) -> Void

    var body: some View {
        if let game {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(game)
                    stats(game)
                    programs(game)
                    settings(game)
                    documents(game)
                }
                .padding(20)
            }
        } else {
            ContentUnavailableView("No Game Selected", systemImage: "info.circle",
                                   description: Text("Select a game to see its details."))
        }
    }

    private func header(_ game: Gamebox) -> some View {
        VStack(spacing: 14) {
            CoverImage(gamebox: game)
                .frame(maxHeight: 280)
            Text(game.name)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button("Play") { play(game) }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                Button {
                    library.toggleFavorite(game)
                } label: {
                    Image(systemName: game.info.isFavorite == true ? "heart.fill" : "heart")
                        .foregroundStyle(game.info.isFavorite == true ? AnyShapeStyle(.pink) : AnyShapeStyle(.primary))
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .help(game.info.isFavorite == true ? "Remove from Favorites" : "Add to Favorites")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func stats(_ game: Gamebox) -> some View {
        section("Activity") {
            row("Released", game.year.map(String.init) ?? "Unknown")
            row("Times played", game.stats.launches == 0 ? "Never" : game.stats.launches.formatted())
            if let last = game.stats.lastPlayed {
                row("Last played", last.formatted(.relative(presentation: .named)))
            }
            if game.stats.secondsPlayed >= 60 {
                row("Time played", Duration.seconds(game.stats.secondsPlayed)
                    .formatted(.units(allowed: [.hours, .minutes], width: .wide)))
            }
            if let added = game.addedDate {
                row("Added", added.formatted(date: .abbreviated, time: .omitted))
            }
        }
    }

    @ViewBuilder private func programs(_ game: Gamebox) -> some View {
        if game.info.launchers.count > 1 {
            section("Starts With") {
                Picker("Program", selection: Binding(
                    get: { game.defaultLauncher?.id },
                    set: { id in
                        if let launcher = game.info.launchers.first(where: { $0.id == id }) {
                            library.setDefaultLauncher(launcher, of: game)
                        }
                    })) {
                    ForEach(game.info.launchers) { Text($0.title).tag(Optional($0.id)) }
                }
                .labelsHidden()
                .disabled(game.isReadOnly)
            }
        }
    }

    private func settings(_ game: Gamebox) -> some View {
        section("Settings") {
            Picker("Display look", selection: Binding(
                get: { game.info.displayLook },
                set: { look in library.update(game) { $0.displayLook = look } })) {
                Text("Default (\(DisplayLook.appDefault.title))").tag(DisplayLook?.none)
                Divider()
                ForEach(DisplayLook.allCases) { Text($0.title).tag(DisplayLook?.some($0)) }
            }
            Toggle("Return to the library when the game ends", isOn: Binding(
                get: { game.info.closesWhenGameEnds },
                set: { on in library.update(game) { $0.quitsWhenGameEnds = on ? nil : false } }))
        }
        .disabled(game.isReadOnly)
    }

    @ViewBuilder private func documents(_ game: Gamebox) -> some View {
        let documents = game.documents()
        section("Documents") {
            if documents.isEmpty {
                Text("None came with this game.").foregroundStyle(.secondary)
            }
            ForEach(documents, id: \.self) { document in
                Button {
                    NSWorkspace.shared.open(document)
                } label: {
                    Label(document.lastPathComponent, systemImage: document.pathExtension.lowercased() == "pdf"
                          ? "book.pages" : "doc.text")
                        .lineLimit(1)
                }
                .buttonStyle(.link)
            }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([game.url])
            }
            .buttonStyle(.link)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.callout)
    }
}
