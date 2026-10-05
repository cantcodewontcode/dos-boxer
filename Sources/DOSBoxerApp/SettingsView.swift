import DOSBoxerKit
import SwiftUI

/// DOS Boxer's settings (⌘,).
struct SettingsView: View {
    /// The open tab, remembered, and set by DOS Boxer to show Music after
    /// MT-32 ROMs are dropped on the library.
    @AppStorage(SettingsTab.defaultsKey) private var tab: SettingsTab = .display

    var body: some View {
        TabView(selection: $tab) {
            Tab("Display", systemImage: "tv", value: .display) { DisplaySettings() }
            Tab("Music", systemImage: "music.note", value: .music) { MusicSettings() }
            Tab("Controllers", systemImage: "gamecontroller", value: .controllers) { ControllerSettings() }
            Tab("Game Details", systemImage: "text.book.closed", value: .gameDetails) { GameDetailsSettings() }
            Tab("Updates", systemImage: "arrow.down.circle", value: .updates) { UpdateSettings() }
        }
        .frame(width: 460)
    }
}

private struct DisplaySettings: View {
    @AppStorage(DisplayLook.defaultsKey) private var look: DisplayLook = .crispPixels

    var body: some View {
        Form {
            Picker("Display Look", selection: $look) {
                ForEach(DisplayLook.allCases) { look in
                    VStack(alignment: .leading) {
                        Text(look.title)
                        Text(look.summary).font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(look)
                }
            }
            .pickerStyle(.radioGroup)
            Text("Games use this look unless you choose another one for a game while playing it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

enum SettingsTab: String {
    case display, music, controllers, gameDetails, updates
    static let defaultsKey = "SettingsTab"
}

/// Roland MT-32 setup: people add their own ROMs once; every game that
/// supports the MT-32 can then use it.
struct MusicSettings: View {
    @State private var status = MT32Setup.status()
    @State private var installed = MT32Setup.installedROMs()
    @State private var choosingROMs = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Roland MT-32") {
                    switch status {
                    case .ready(let model): Label("\(model) ready", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .incomplete: Label("Needs both ROMs", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    case .notInstalled: Text("Not set up").foregroundStyle(.secondary)
                    }
                }
                if let summary = MT32Setup.summary() {
                    Label(summary, systemImage: "memorychip")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Add ROMs…") { choosingROMs = true }
                    if !installed.isEmpty {
                        Button("Remove ROMs", role: .destructive) {
                            try? MT32Setup.removeAll()
                            refresh()
                            message = "The ROMs were removed."
                        }
                    }
                    Spacer()
                    Button("Show in Finder") {
                        try? FileManager.default.createDirectory(at: MT32Setup.romsFolder,
                                                                 withIntermediateDirectories: true)
                        NSWorkspace.shared.activateFileViewerSelecting([MT32Setup.romsFolder])
                    }
                }
                if let message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            } footer: {
                Text("""
                    Many games from the late 1980s and early 1990s were scored for the Roland MT-32. \
                    DOS Boxer needs two ROM files from an MT-32: a control ROM (MT32_CONTROL.ROM) and \
                    a sound ROM (MT32_PCM.ROM), or the CM-32L versions (CM32L_CONTROL.ROM and \
                    CM32L_PCM.ROM). You can find them at \
                    [archive.org](https://archive.org/details/Roland-MT-32-ROMs).
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        // Dropping ROMs (or the archive.org ZIP) anywhere on the tab adds them
        .dropDestination(for: URL.self) { urls, _ in
            install(urls)
            return true
        }
        .fileImporter(isPresented: $choosingROMs, allowedContentTypes: [.data, .folder, .zip],
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            install(urls)
        }
        // ROMs dropped on the library land here too; show them
        .onReceive(NotificationCenter.default.publisher(for: .mt32ROMsChanged)) { _ in refresh() }
    }

    private func install(_ urls: [URL]) {
        let added = (try? MT32Setup.install(from: urls)) ?? 0
        refresh()
        let recognised = urls.contains { MT32Setup.roms(in: $0) != nil }
        message = added == 0 ? (recognised ? "Those ROMs are already installed." : "Those files don't look like MT-32 ROMs.")
            : added == 1 ? "Added 1 ROM." : "Added \(added) ROMs."
    }

    private func refresh() {
        status = MT32Setup.status()
        installed = MT32Setup.installedROMs()
    }
}

extension Notification.Name {
    /// Posted when ROMs were installed from outside Settings.
    static let mt32ROMsChanged = Notification.Name("DOSBoxerMT32ROMsChanged")
}
