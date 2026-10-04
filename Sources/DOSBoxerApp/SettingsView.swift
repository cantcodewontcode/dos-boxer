import DOSBoxerKit
import SwiftUI

/// DOS Boxer's settings (⌘,).
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Display", systemImage: "tv") { DisplaySettings() }
            Tab("Music", systemImage: "music.note") { MusicSettings() }
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

/// Roland MT-32 setup: people add their own ROMs once; every game that
/// supports the MT-32 can then use it.
private struct MusicSettings: View {
    @State private var status = MT32Setup.status()
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
                HStack {
                    Button("Add ROMs…") { choosingROMs = true }
                    if status != .notInstalled {
                        Button("Remove ROMs", role: .destructive) {
                            try? MT32Setup.removeAll()
                            status = MT32Setup.status()
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
                Text("Many games from the late 1980s and early 1990s were scored for the Roland MT-32. Add a control ROM and a PCM ROM from your own MT-32 or CM-32L, and games set up for it will use it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .fileImporter(isPresented: $choosingROMs, allowedContentTypes: [.data, .folder],
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            let added = (try? MT32Setup.install(from: urls)) ?? 0
            status = MT32Setup.status()
            message = added == 0 ? "Those files don't look like MT-32 ROMs."
                : added == 1 ? "Added 1 ROM." : "Added \(added) ROMs."
        }
    }
}
