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
    @State private var droppedSoundFonts: [URL] = []

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
                HStack {
                    // Both ROMs in: nothing more to add
                    if !MT32Setup.isReady {
                        Button("Add ROMs…") { choosingROMs = true }
                    }
                    if !installed.isEmpty {
                        Button("Remove ROMs", role: .destructive) {
                            try? MT32Setup.removeAll()
                            refresh()
                        }
                        Spacer()
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([MT32Setup.romsFolder])
                        }
                    }
                }
            } footer: {
                Text("""
                    Many games were scored for the Roland MT-32. To support these in DOS Boxer, a control \
                    ROM and sound ROM file are needed. You can find them at \
                    [archive.org](https://archive.org/details/Roland-MT-32-ROMs).
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SoundCanvasSection(dropped: $droppedSoundFonts)
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        // Dropping ROMs (or the archive.org ZIP), or a SoundFont, anywhere on
        // the tab adds them
        .dropDestination(for: URL.self) { urls, _ in
            let fonts = urls.filter(SoundFontSetup.isSoundFont)
            if !fonts.isEmpty { droppedSoundFonts = fonts }
            let rest = urls.filter { !SoundFontSetup.isSoundFont($0) }
            if !rest.isEmpty { install(rest) }
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
        _ = try? MT32Setup.install(from: urls)
        refresh()
    }

    private func refresh() {
        status = MT32Setup.status()
        installed = MT32Setup.installedROMs()
    }
}

/// Sound Canvas music: a SoundFont, downloaded (GeneralUser GS, from DOS
/// Boxer's own copy) or the player's own.
private struct SoundCanvasSection: View {
    @Binding var dropped: [URL]
    @State private var name = SoundFontSetup.installedName
    @State private var progress: Double?
    @State private var choosing = false

    var body: some View {
        Section {
            LabeledContent("Roland Sound Canvas") {
                if let progress {
                    ProgressView(value: progress).frame(width: 120)
                } else if name != nil {
                    Label("Sound Canvas ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Text("Not set up").foregroundStyle(.secondary)
                }
            }
            HStack {
                // One SoundFont at a time (DOSBox plays one): once there is
                // one, it can only be removed (adding another replaces it)
                if name == nil {
                    Button("Install GeneralUser GS") { download() }
                        .disabled(progress != nil)
                    Button("Add SoundFont…") { choosing = true }
                        .disabled(progress != nil)
                } else {
                    Button("Remove", role: .destructive) {
                        try? SoundFontSetup.removeAll()
                        refresh()
                    }
                    Spacer()
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([SoundFontSetup.folder])
                    }
                }
            }
        } footer: {
            Text("""
                Many games were scored for the Roland Sound Canvas. To support these in DOS Boxer, \
                please Install GeneralUser GS, a free SoundFont developed by S. Christian Collins which \
                replicates the sound, or provide your own alternative SoundFont.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.init(filenameExtension: "sf2") ?? .data],
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result else { return }
            _ = try? SoundFontSetup.install(from: urls)
            refresh()
        }
        .onChange(of: dropped) { _, urls in
            guard !urls.isEmpty else { return }
            _ = try? SoundFontSetup.install(from: urls)
            dropped = []
            refresh()
        }
        // SoundFonts dropped on the library land here too
        .onReceive(NotificationCenter.default.publisher(for: .mt32ROMsChanged)) { _ in refresh() }
    }

    private func download() {
        progress = 0
        Task {
            try? await SoundFontSetup.download { value in Task { @MainActor in progress = value } }
            progress = nil
            refresh()
        }
    }

    private func refresh() { name = SoundFontSetup.installedName }
}

extension Notification.Name {
    /// Posted when ROMs were installed from outside Settings.
    static let mt32ROMsChanged = Notification.Name("DOSBoxerMT32ROMsChanged")
}
