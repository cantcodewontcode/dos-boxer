import SwiftUI

/// One game, playing in its own window with its own DOS session.
public struct GameWindow: View {
    let url: URL
    /// Where the game's saves go, if not inside the gamebox.
    let savesFolder: URL?
    /// Called when the game quits back to DOS by itself (DOS Boxer returns
    /// to the library).
    let gameEnded: () -> Void
    /// Where the screenshot button saves pictures.
    let screenshotsFolder: URL
    @Environment(\.dismiss) private var dismiss

    public init(url: URL, savesFolder: URL? = nil,
                screenshotsFolder: URL = Gamebox.defaultScreenshotsFolder,
                gameEnded: @escaping () -> Void = {}) {
        self.url = url
        self.savesFolder = savesFolder
        self.screenshotsFolder = screenshotsFolder
        self.gameEnded = gameEnded
    }

    @State private var emulator = Emulator()
    @State private var gamebox: Gamebox?
    @State private var phase: Phase = .loading
    @State private var restartCount = 0
    /// The glass controls show while the pointer is moving over the game.
    @State private var showControls = false
    /// When the current session started, for play stats.
    @State private var sessionStart: Date?
    @State private var lastPointerMove = Date.distantPast
    /// Set by "Play Anyway" when another Mac has the game open.
    @State private var ignoreOtherComputer = false
    @State private var start: Gamebox.Start = .game
    /// True when the person stopped DOS themselves (Turn Off, Restart,
    /// switching programs), so the window stays open instead of closing.
    @State private var stoppedByUser = false

    enum Phase: Equatable {
        case loading
        case downloading(Double)
        /// Another Mac sharing the library is playing this game right now.
        case inUseElsewhere(String)
        case playing
        case failed(String)
    }

    public var body: some View {
        ZStack {
            if emulator.isRunning {
                DOSScreen(emulator: emulator)
                    .onContinuousHover { phase in
                        if case .active = phase { pointerMoved() }
                    }
                GameOverlay(emulator: emulator, gamebox: gamebox, screenshotsFolder: screenshotsFolder,
                            isVisible: showControls && !emulator.isMouseLocked,
                            keepVisible: pointerMoved)
            } else {
                StatusCard(gamebox: gamebox, phase: phase, emulatorState: emulator.state,
                           playAgain: { stoppedByUser = true; restartCount += 1 },
                           playAnyway: { ignoreOtherComputer = true; restartCount += 1 },
                           close: { dismiss() })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .navigationTitle(gamebox?.name ?? url.deletingPathExtension().lastPathComponent)
        .toolbar {
            MouseHint(emulator: emulator)
            ToolbarItemGroup(placement: .primaryAction) {
                if let gamebox, !gamebox.info.launchers.isEmpty {
                    Menu("Programs", systemImage: "list.bullet") {
                        ForEach(gamebox.info.launchers) { launcher in
                            Button(launcher.title) { run(.launcher(launcher)) }
                        }
                        Divider()
                        Button("DOS Prompt") { run(.prompt) }
                    }
                    .help("Run another of the game's programs")
                }
                Button("Restart", systemImage: "arrow.clockwise") {
                    stoppedByUser = true
                    restartCount += 1
                }
                .help("Restart the game")
                .disabled(!emulator.isRunning)
                Button("Turn Off", systemImage: "power") {
                    stoppedByUser = true
                    emulator.stop()
                }
                .help("Turn off DOS")
                .disabled(!emulator.isRunning)
            }
        }
        .task(id: restartCount) { await prepareAndPlay() }
        .onChange(of: emulator.state) { _, state in
            if state == .running {
                stoppedByUser = false
                sessionStart = Date()
            }
            if case .stopped = state, let gamebox {
                GameboxPresence.clearInUse(gamebox)
                endSession(gamebox)
            }
            // The game ended by itself (it quit back to DOS, which then
            // exited): close and go back to the library
            if case .stopped(0) = state, !stoppedByUser, start != .prompt,
               gamebox?.info.closesWhenGameEnds == true {
                gameEnded()
                dismiss()
            }
        }
        .onDisappear {
            emulator.stop()
            if let gamebox {
                GameboxPresence.clearInUse(gamebox)
                endSession(gamebox)
            }
        }
    }

    /// Counts a finished session towards the game's play stats.
    private func endSession(_ gamebox: Gamebox) {
        guard let start = sessionStart else { return }
        sessionStart = nil
        PlayStats.recordSession(of: gamebox, startedAt: start)
    }

    /// Shows the glass controls, hiding them again once the pointer rests.
    private func pointerMoved() {
        lastPointerMove = Date()
        showControls = true
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if Date().timeIntervalSince(lastPointerMove) >= 2.4 { showControls = false }
        }
    }

    /// Opens the gamebox, fetches any cloud-only files, then starts DOS.
    private func prepareAndPlay() async {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            phase = .failed("This game isn't where it used to be. It may have been moved, renamed or deleted.")
            return
        }
        do {
            var gamebox = try Gamebox.open(url)
            if let savesFolder { gamebox.externalSavesURL = savesFolder }
            self.gamebox = gamebox
            if !ignoreOtherComputer, let other = GameboxPresence.otherComputerPlaying(gamebox) {
                phase = .inUseElsewhere(other)
                return
            }
            if !GameboxDownloads.missingFiles(in: url).files.isEmpty {
                phase = .downloading(0)
                try await GameboxDownloads.downloadAll(in: url) { fraction in
                    Task { @MainActor in phase = .downloading(fraction) }
                }
            }
            phase = .playing
            launch()
        } catch is CancellationError {
            return
        } catch {
            phase = .failed("DOS Boxer couldn't open this game. \(error.localizedDescription)")
        }
    }

    /// Runs something else from the game's toolbar menu.
    private func run(_ newStart: Gamebox.Start) {
        stoppedByUser = true
        start = newStart
        launch()
    }

    private func launch() {
        guard let gamebox else { return }
        do {
            emulator.start(arguments: try gamebox.sessionArguments(start))
            GameboxPresence.markInUse(gamebox)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

/// Shown while a game isn't on screen: loading, downloading, or stopped.
private struct StatusCard: View {
    let gamebox: Gamebox?
    let phase: GameWindow.Phase
    let emulatorState: Emulator.State
    let playAgain: () -> Void
    let playAnyway: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            CoverImage(gamebox: gamebox)
                .frame(width: 120, height: 150)
            Text(gamebox?.name ?? "")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            detail
        }
        .padding(32)
        .frame(maxWidth: 380)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .padding()
    }

    @ViewBuilder private var detail: some View {
        switch phase {
        case .loading:
            ProgressView().controlSize(.small)
        case .downloading(let fraction):
            VStack(spacing: 8) {
                Text("Downloading the game's files…").foregroundStyle(.secondary)
                ProgressView(value: fraction).frame(width: 200)
            }
        case .inUseElsewhere(let computer):
            Text("This game is open on \(computer). Playing it on two Macs at once can mix up saved games.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Close", action: close).buttonStyle(.glass)
                Button("Play Anyway", action: playAnyway).buttonStyle(.glassProminent)
            }
            .controlSize(.large)
        case .failed(let message):
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Close", action: close).buttonStyle(.glass)
        case .playing:
            switch emulatorState {
            case .stopping:
                Text("Turning off…").foregroundStyle(.secondary)
            case .stopped(let code):
                Text(code == 0 ? "The game has finished." : "DOS stopped unexpectedly.")
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button("Close", action: close).buttonStyle(.glass)
                    Button("Play Again", action: playAgain)
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                }
                .controlSize(.large)
            default:
                ProgressView().controlSize(.small)
            }
        }
    }
}

/// A game's box art, or a simple stand-in when it has none.
public struct CoverImage: View {
    let gamebox: Gamebox?

    public init(gamebox: Gamebox?) {
        self.gamebox = gamebox
    }

    public var body: some View {
        if let url = gamebox?.coverURL, let image = NSImage(contentsOf: url) {
            // (Reloaded whenever the library reloads, so new covers show up)
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(.rect(cornerRadius: 6))
                .shadow(radius: 6, y: 3)
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary)
                .overlay {
                    // Phosphor's floppy disk (MIT; see Licenses/)
                    Image("FloppyDisk", bundle: Bundle(for: Emulator.self))
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 48, height: 48)
                        .foregroundStyle(.secondary)
                }
                .aspectRatio(0.8, contentMode: .fit)
        }
    }
}
