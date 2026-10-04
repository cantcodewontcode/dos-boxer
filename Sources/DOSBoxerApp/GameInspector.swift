import DOSBoxerKit
import SwiftUI

/// The fold-out info panel on the right of the library: the selected game's
/// cover, stats, programs, settings and documents.
struct GameInspector: View {
    let library: GameLibrary
    /// The selected games.
    let games: [Gamebox]
    let play: (Gamebox) -> Void

    var body: some View {
        if games.count > 1 {
            multipleSelection
        } else if let game = games.first {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(game)
                    details(game)
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

    /// The three header buttons share one height (a glass menu is otherwise
    /// a little shorter than a glass button).
    private static let buttonContentHeight: CGFloat = 22

    /// Several games selected: what can be done to all of them.
    private var multipleSelection: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text("\(games.count) Games Selected")
                .font(.title3.weight(.semibold))
            HStack(spacing: 10) {
                let allFavorite = games.allSatisfy { $0.info.isFavorite == true }
                Button {
                    library.setFavorite(games, !allFavorite)
                } label: {
                    Image(systemName: allFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(allFavorite ? AnyShapeStyle(.pink) : AnyShapeStyle(.primary))
                }
                .buttonStyle(.glass)
                .help(allFavorite ? "Remove from Favorites" : "Add to Favorites")
                Menu {
                    ForEach(library.collections) { collection in
                        Button(collection.name) { library.add(games.map(\.id), toCollection: collection.id) }
                    }
                    if !library.collections.isEmpty { Divider() }
                    Button("New Collection") { library.createCollection(named: "Untitled Collection", with: games) }
                } label: {
                    Image(systemName: "plus")
                }
                .menuIndicator(.hidden)
                .buttonStyle(.glass)
                .fixedSize()
                .help("Add to Collection")
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func header(_ game: Gamebox) -> some View {
        VStack(spacing: 14) {
            CoverImage(gamebox: game)
                .frame(maxHeight: 280)
            // Click the name to rename the game
            TitleField(name: game.name, enabled: !game.isReadOnly) { newName in
                library.rename(game, to: newName)
            }
            .id(game.id)
            HStack(spacing: 10) {
                Button { play(game) } label: {
                    Text("Play").frame(height: Self.buttonContentHeight)
                }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                Button {
                    library.toggleFavorite(game)
                } label: {
                    Image(systemName: game.info.isFavorite == true ? "heart.fill" : "heart")
                        .foregroundStyle(game.info.isFavorite == true ? AnyShapeStyle(.pink) : AnyShapeStyle(.primary))
                        .frame(height: Self.buttonContentHeight)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .help(game.info.isFavorite == true ? "Remove from Favorites" : "Add to Favorites")
                Menu {
                    ForEach(library.collections) { collection in
                        Button(collection.name) { library.add([game.id], toCollection: collection.id) }
                    }
                    if !library.collections.isEmpty { Divider() }
                    Button("New Collection") { library.createCollection(named: "Untitled Collection", with: [game]) }
                } label: {
                    Image(systemName: "plus")
                        .frame(height: Self.buttonContentHeight)
                }
                .menuIndicator(.hidden)
                .buttonStyle(.glass)
                .controlSize(.large)
                .fixedSize()
                .help("Add to Collection")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func details(_ game: Gamebox) -> some View {
        section("Details") {
            row("Released", game.year.map(String.init) ?? "Unknown")
            DetailField(label: "Publisher", value: game.info.publisher, enabled: !game.isReadOnly) { value in
                library.update(game) { $0.publisher = value }
            }
            DetailField(label: "Developer", value: game.info.developer, enabled: !game.isReadOnly) { value in
                library.update(game) { $0.developer = value }
            }
            DetailField(label: "Genre", value: game.info.genre, enabled: !game.isReadOnly) { value in
                library.update(game) { $0.genre = value }
            }
        }
        .id(game.id)  // fresh fields when the selection changes
    }

    private func stats(_ game: Gamebox) -> some View {
        section("Activity") {
            row("Times played", game.stats.launches == 0 ? "Never" : game.stats.launches.formatted())
            row("Last played", game.stats.lastPlayed.map { $0.formatted(.relative(presentation: .named)) } ?? "Never")
            row("Added", game.addedDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Unknown")
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
                    ForEach(game.info.launchers) { Text($0.displayName).tag(Optional($0.id)) }
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
                Text("Default").tag(DisplayLook?.none)
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
                Text("None yet.").foregroundStyle(.secondary)
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
            if !game.isReadOnly {
                DocumentDropZone { files in
                    do {
                        try game.addDocuments(files)
                        library.reload()
                    } catch {
                        library.reportError("Couldn't add the documents: \(error.localizedDescription)")
                    }
                }
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

/// A detail like the publisher: shown as a value, edited in place.
private struct DetailField: View {
    let label: String
    let value: String?
    let enabled: Bool
    let save: (String?) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            TextField(label, text: $text, prompt: Text("Add \(label.lowercased())"))
                .textFieldStyle(.plain)
                .multilineTextAlignment(focused ? .leading : .trailing)
                .focused($focused)
                .editingFrame(focused)
                .disabled(!enabled)
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
        }
        .font(.callout)
        .onAppear { text = value ?? "" }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (value ?? "") else { return }
        save(trimmed.isEmpty ? nil : trimmed)
    }
}

/// The game's name, edited in place: click it, type, press Return.
private struct TitleField: View {
    let name: String
    let enabled: Bool
    let save: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Name", text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.title3.weight(.semibold))
            .multilineTextAlignment(.center)
            .lineLimit(1...3)
            .focused($focused)
            .editingFrame(focused)
            .disabled(!enabled)
            .onSubmit(commit)
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            .onAppear { text = name }
            .help(enabled ? "Click to rename" : "")
    }

    private func commit() {
        let trimmed = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { text = name } else if trimmed != name { save(trimmed) }
    }
}

/// Drop documents (manuals, maps, notes) here to keep them with the game.
private struct DocumentDropZone: View {
    let add: ([URL]) -> Void
    @State private var isTargeted = false

    var body: some View {
        Label("Drop documents here to add them", systemImage: "doc.badge.plus")
            .font(.callout)
            .foregroundStyle(isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
            .dropDestination(for: URL.self) { urls, _ in
                add(urls.filter(\.isFileURL))
                return true
            } isTargeted: { isTargeted = $0 }
    }
}

private extension View {
    /// Looks like plain text until you click in, then like an editable
    /// text field while you type (as names do in the grid).
    func editingFrame(_ isEditing: Bool) -> some View {
        padding(.horizontal, isEditing ? 6 : 0)
            .padding(.vertical, isEditing ? 3 : 0)
            .background {
                if isEditing {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(nsColor: .textBackgroundColor))
                        .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1.5)
                }
            }
            .animation(.easeOut(duration: 0.12), value: isEditing)
    }
}
