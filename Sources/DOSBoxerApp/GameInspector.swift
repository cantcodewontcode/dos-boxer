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
                    overview(game)
                    stats(game)
                    programs(game)
                    settings(game)
                    documents(game)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
                // Clicking anywhere else in the panel ends editing
                .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) }
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
AddToCollectionButton(library: library, games: games)
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
            TitleField(name: game.title, enabled: !game.isReadOnly) { newTitle in
                library.rename(game, to: game.name(forTitle: newTitle))
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
AddToCollectionButton(library: library, games: [game])
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func details(_ game: Gamebox) -> some View {
        let info = game.info
        return section("Details") {
            row("Released", game.year.map(String.init) ?? "Unknown")
            DetailField(label: "Developer", value: info.developer, enabled: !game.isReadOnly) { value in
                library.update(game) { $0.developer = value }
            }
            DetailField(label: "Publisher", value: info.publisher, enabled: !game.isReadOnly) { value in
                library.update(game) { $0.publisher = value }
            }
            GenrePills(genres: info.genreList, enabled: !game.isReadOnly) { genres in
                library.update(game) { $0.setGenres(genres) }
            }
            if let players = info.maxPlayers {
                row("Players", (players == 1 ? "1" : "Up to \(players)") + (info.cooperative == true ? " (co-op)" : ""))
            }
            if let ageRating = info.ageRating {
                row("Age Rating", Self.ageRatingText(ageRating))
            }
            if let rating = info.communityRating, (info.communityRatingCount ?? 1) > 0 {
                HStack {
                    Text("Rating").foregroundStyle(.secondary)
                    Spacer()
                    RatingStars(rating: rating)
                        .help("\(rating.formatted(.number.precision(.fractionLength(1)))) out of 5"
                              + (info.communityRatingCount.map { ", from \($0) ratings" } ?? ""))
                }
                .font(.callout)
            }
        }
        .id(game.id)  // fresh fields when the selection changes
    }

    /// "T - Teen" reads as "Teen (T)".
    private static func ageRatingText(_ rating: String) -> String {
        let parts = rating.components(separatedBy: " - ")
        return parts.count == 2 ? "\(parts[1]) (\(parts[0]))" : rating
    }

    @ViewBuilder private func overview(_ game: Gamebox) -> some View {
        if let overview = game.info.overview {
            section("About") { OverviewText(text: overview) }
                .id(game.id)
        }
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
            ControlsButton(controls: game.info.controls) { controls in
                library.update(game) { $0.controls = controls.isEmpty ? nil : controls }
            }
        }
        .disabled(game.isReadOnly)
    }

    @ViewBuilder private func documents(_ game: Gamebox) -> some View {
        let documents = game.documents()
        section("Documents") {
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
            if !documents.isEmpty {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(documents)
                }
                .buttonStyle(.link)
            }
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
                .multilineTextAlignment(.trailing)
                .focused($focused)
                .editingFrame(focused)
                // The edit box overhangs, so the text lines up with plain rows
                .padding(.horizontal, -6)
                .padding(.vertical, -3)
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
            // Return saves (a multi-line field would otherwise add a line)
            .onKeyPress(.return) {
                focused = false
                return .handled
            }
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

/// Drop documents (manuals, maps, notes) here, or click to choose them, to
/// keep them with the game.
private struct DocumentDropZone: View {
    let add: ([URL]) -> Void
    @State private var isTargeted = false
    @State private var choosing = false

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
            .contentShape(.rect)
            .onTapGesture { choosing = true }
            .dropDestination(for: URL.self) { urls, _ in
                add(urls.filter(\.isFileURL))
                return true
            } isTargeted: { isTargeted = $0 }
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { add(urls) }
            }
    }
}

private extension View {
    /// Looks like plain text until you click in, then like an editable text
    /// field while you type (as names do in the grid). The padding is always
    /// there, so nothing moves when editing starts; only the field's
    /// background and border fade in.
    func editingFrame(_ isEditing: Bool) -> some View {
        padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(isEditing ? 1 : 0))
                    .strokeBorder(Color.accentColor.opacity(isEditing ? 0.6 : 0), lineWidth: 1.5)
            }
            .animation(.easeOut(duration: 0.12), value: isEditing)
    }
}

/// "+": adds games to a collection, chosen from a small glass popover. A real
/// button (not a menu), so it matches the buttons beside it in size.
private struct AddToCollectionButton: View {
    let library: GameLibrary
    let games: [Gamebox]
    @State private var choosing = false

    var body: some View {
        Button {
            choosing = true
        } label: {
            Image(systemName: "plus")
                .frame(height: 22)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .help("Add to Collection")
        .popover(isPresented: $choosing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Add to Collection")
                    .font(.headline)
                    .padding(.bottom, 6)
                ForEach(library.collections) { collection in
                    Button {
                        library.add(games.map(\.id), toCollection: collection.id)
                        choosing = false
                    } label: {
                        Label(collection.name, systemImage: "rectangle.stack")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
                if !library.collections.isEmpty { Divider().padding(.vertical, 4) }
                Button {
                    library.createCollection(named: "Untitled Collection", with: games)
                    choosing = false
                } label: {
                    Label("New Collection", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            }
            .padding(14)
            .frame(minWidth: 200)
        }
    }
}

/// Genres as pills. Remove one with its ×; add one from the known list.
private struct GenrePills: View {
    let genres: [String]
    let enabled: Bool
    let save: ([String]) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Genres").foregroundStyle(.secondary)
            Spacer(minLength: 16)
            FlowLayout(spacing: 4, alignment: .trailing) {
                ForEach(genres, id: \.self) { genre in
                    Pill(title: genre, removable: enabled) { save(genres.filter { $0 != genre }) }
                }
                if enabled {
                    Menu {
                        ForEach(GameGenres.all.filter { !genres.contains($0) }, id: \.self) { genre in
                            Button(genre) { save(genres + [genre]) }
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption.weight(.semibold))
                            .frame(width: 22, height: 20)
                            .background(.quaternary, in: .capsule)
                            .contentShape(.capsule)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Add Genre")
                }
            }
        }
        .font(.callout)
    }
}

private struct Pill: View {
    let title: String
    let removable: Bool
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 3) {
            Text(title)
            if removable && hovering {
                Button(action: remove) {
                    Image(systemName: "xmark").font(.caption2.weight(.bold))
                }
                .buttonStyle(.plain)
                .help("Remove")
            }
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(.quaternary, in: .capsule)
        .onHover { hovering = $0 }
    }
}

/// Lays views out in rows, wrapping onto new lines as needed.
private struct FlowLayout: Layout {
    var spacing: CGFloat
    var alignment: HorizontalAlignment = .leading

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = alignment == .trailing ? bounds.maxX - row.width : bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : spacing + size.width
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let added = rows[rows.count - 1].indices.isEmpty ? size.width : spacing + size.width
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += added
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}

/// Five stars, filled to the nearest half.
private struct RatingStars: View {
    let rating: Double

    var body: some View {
        let halves = Int((rating * 2).rounded())
        HStack(spacing: 1) {
            ForEach(0..<5) { star in
                Image(systemName: halves >= (star + 1) * 2 ? "star.fill"
                      : halves == star * 2 + 1 ? "star.leadinghalf.filled" : "star")
            }
        }
        .font(.caption)
        .foregroundStyle(.orange)
    }
}

/// A description: the first few lines, with Show More to read the rest in
/// place.
private struct OverviewText: View {
    let text: String
    @State private var expanded = false
    @State private var shownHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.callout)
                .lineLimit(expanded ? nil : 4)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shownHeight = $0 }
                // The whole text, unseen, to know whether four lines cut it short
                .background(alignment: .topLeading) {
                    Text(text)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                }
            if expanded || fullHeight > shownHeight + 1 {
                Button(expanded ? "Show Less" : "Show More") {
                    withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() }
                }
                .buttonStyle(.link)
                .font(.callout)
            }
        }
    }
}

/// "Controller: Standard" with a button to change what the buttons do.
private struct ControlsButton: View {
    let controls: GameControls?
    let save: (GameControls) -> Void
    @State private var editing = false

    var body: some View {
        HStack {
            Text("Controller").foregroundStyle(.secondary)
            Spacer()
            Button(controls?.isEmpty == false ? "Customized" : "Standard") { editing = true }
                .buttonStyle(.link)
        }
        .font(.callout)
        .sheet(isPresented: $editing) {
            ControlsEditor(controls: controls ?? GameControls(), save: save)
        }
    }
}
