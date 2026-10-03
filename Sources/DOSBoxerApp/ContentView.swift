import DOSBoxerKit
import SwiftUI

struct ContentView: View {
    let emulator: Emulator

    @State private var choosingFolder = false
    @State private var gameFolder: URL?

    var body: some View {
        ZStack {
            if emulator.isRunning {
                // Inset from the window edges so the rounded window corners
                // never clip the DOS screen.
                EmulatorView(emulator: emulator)
                    .padding(screenInset)
            } else {
                StartCard(emulator: emulator,
                          start: { start(folder: gameFolder) },
                          chooseFolder: { choosingFolder = true })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .navigationTitle(gameFolder?.lastPathComponent ?? "DOS Boxer")
        .navigationSubtitle(mouseHint)
        .toolbar {
            ToolbarItemGroup {
                Button("Choose Game Folder…", systemImage: "folder.badge.plus") {
                    choosingFolder = true
                }
                .help("Choose a folder to use as drive C")
                Button("Restart", systemImage: "arrow.clockwise") {
                    start(folder: gameFolder)
                }
                .help("Restart DOS")
                .disabled(!emulator.isRunning)
                Button("Turn Off", systemImage: "power") {
                    emulator.stop()
                }
                .help("Turn off DOS")
                .disabled(!emulator.isRunning)
            }
        }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            start(folder: url)
        }
        #if DEBUG
        .task { await runDebugLaunchOptions() }
        #endif
    }

    #if DEBUG
    /// Development aid: `-DOSBoxerAutoStart YES` starts DOS at launch, and
    /// `-DOSBoxerAutoRestart <n>` restarts it every n seconds (for testing
    /// session replacement without clicking).
    private func runDebugLaunchOptions() async {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "DOSBoxerAutoStart") else { return }
        start(folder: nil)
        let interval = defaults.integer(forKey: "DOSBoxerAutoRestart")
        guard interval > 0 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(interval))
            start(folder: gameFolder)
        }
    }
    #endif

    private let screenInset: CGFloat = 12

    /// Tells people how to get the mouse in and out of DOS.
    private var mouseHint: String {
        guard emulator.isRunning else { return "" }
        return emulator.isMouseLocked
            ? "Press ⌘⌥ to release the mouse"
            : "Click the screen to use the mouse in DOS"
    }

    /// Starts DOS (replacing any running session) with `folder`, if given,
    /// as drive C.
    private func start(folder: URL?) {
        if folder != gameFolder {
            gameFolder?.stopAccessingSecurityScopedResource()
            gameFolder = folder
            _ = folder?.startAccessingSecurityScopedResource()
        }
        emulator.start(arguments: StartupScript.arguments(
            folderPath: folder?.path(percentEncoded: false),
            folderName: folder?.lastPathComponent))
    }
}

/// Shown while DOS isn't running: a floating glass card over the black screen.
private struct StartCard: View {
    let emulator: Emulator
    let start: () -> Void
    let chooseFolder: () -> Void

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 16) {
                Image(systemName: "pc")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.title2.weight(.semibold))
                Text("Start a DOS prompt, or choose a folder with a game in it to use as drive C.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 320)
                HStack(spacing: 12) {
                    Button("Choose Game Folder…", action: chooseFolder)
                        .buttonStyle(.glass)
                    Button("Start DOS", action: start)
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                }
                .controlSize(.large)
            }
            .padding(32)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
        }
        .padding()
    }

    private var title: String {
        switch emulator.state {
        case .stopping: "Turning off…"
        case .stopped(let code) where code != 0: "DOS stopped unexpectedly"
        default: "DOS Boxer"
        }
    }
}
