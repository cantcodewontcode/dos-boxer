import DOSBoxerKit
import SwiftUI

/// A plain DOS prompt, not tied to a gamebox; handy for poking around or
/// running a game straight from a folder.
struct DOSPromptView: View {
    @State private var emulator = Emulator()

    @State private var choosingFolder = false
    @State private var gameFolder: URL?

    var body: some View {
        ZStack {
            if emulator.isRunning {
                // Inset from the window edges so the rounded window corners
                // never clip the DOS screen.
                DOSScreen(emulator: emulator)
            } else if case .stopped = emulator.state {
                // Only after DOS has been turned off; it starts by itself
                StoppedCard(emulator: emulator, start: { start(folder: gameFolder) })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .navigationTitle(gameFolder?.lastPathComponent ?? "DOS Prompt")
        // Straight into a DOS prompt
        .onAppear { if emulator.state == .idle { start(folder: nil) } }
        .onDisappear { emulator.stop() }
        .toolbar {
            MouseHint(emulator: emulator)

            ToolbarItemGroup(placement: .primaryAction) {
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
            useFolder(url)
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

    /// Makes `folder` drive C: mounted straight into the running session
    /// (no restart), or used to start a new one.
    private func useFolder(_ folder: URL) {
        guard emulator.isRunning else {
            start(folder: folder)
            return
        }
        if emulator.mount(folder: folder) {
            gameFolder = folder
        } else {
            start(folder: folder)
        }
    }

    /// Starts DOS (replacing any running session) with `folder`, if given,
    /// as drive C.
    private func start(folder: URL?) {
        gameFolder = folder
        emulator.start(arguments: StartupScript.arguments(
            folderPath: folder?.path(percentEncoded: false),
            folderName: folder?.lastPathComponent))
    }
}

/// Shown after DOS has been turned off.
private struct StoppedCard: View {
    let emulator: Emulator
    let start: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.title3.weight(.semibold))
            Button("Start DOS", action: start)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private var title: String {
        if case .stopped(let code) = emulator.state, code != 0 { return "DOS stopped unexpectedly" }
        return "DOS is turned off"
    }
}
