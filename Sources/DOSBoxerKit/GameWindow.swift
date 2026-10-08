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
    /// A short glass notice over the game ("Screenshot saved", the mouse
    /// hint), which fades by itself and can't be clicked.
    @State private var notice: String?
    /// The app-wide look, so a change in Settings shows up straight away.
    @AppStorage(DisplayLook.defaultsKey) private var appLook: DisplayLook = .crispPixels
    /// When the current session started, for play stats.
    @State private var sessionStart: Date?
    /// Set by "Play Anyway" when another Mac has the game open.
    @State private var ignoreOtherComputer = false
    @State private var start: Gamebox.Start = .game
    /// Which of the CD drive's discs is in it (sessions start with the first).
    @State private var discIndex = 0
    /// True when the person stopped DOS themselves (Turn Off, Restart,
    /// switching programs), so the window stays open instead of closing.
    @State private var stoppedByUser = false
    @State private var editingControls = false
    @State private var suggestingMT32 = false
    @Environment(\.openSettings) private var openSettings
    @State private var speedSave: Task<Void, Never>?
    /// The game was paused for the controls sheet, so resume it after.
    @State private var pausedForControls = false

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
                GameNotices(notice: notice, isPaused: emulator.isPaused)
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
            ToolbarItemGroup(placement: .primaryAction) {
                if let gamebox, !gamebox.info.launchers.isEmpty {
                    Menu("Programs", systemImage: "apple.terminal") {
                        programItems(gamebox)
                    }
                    .help("Run another of the game's programs")
                }
                Button(emulator.isPaused ? "Resume" : "Pause",
                       systemImage: emulator.isPaused ? "play.fill" : "pause.fill") { togglePause() }
                    .help(emulator.isPaused ? "Resume (⌘P)" : "Pause (⌘P)")
                    .disabled(!emulator.isRunning)
                Menu("Display Look", systemImage: "tv") {
                    lookPicker
                }
                .help("Display look")
                if discs.count > 1 {
                    Menu("Disc", systemImage: "opticaldisc") {
                        discPicker
                    }
                    .help("Choose the disc in the CD drive")
                    .disabled(!emulator.isRunning)
                }
                Button("Controls", systemImage: "gamecontroller") { editingControls = true }
                    .help("Controller controls for this game")
                    .disabled(gamebox == nil)
                Button("Take Screenshot", systemImage: "camera") { takeScreenshot() }
                    .help("Take a screenshot (⇧⌘S)")
                    .disabled(!emulator.isRunning)
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right") {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
                .help("Enter or leave full screen (⌘↩)")
                Button("Turn Off", systemImage: "power") { turnOff() }
                    .help("Turn off DOS")
                    .disabled(!emulator.isRunning)
            }
        }
        .focusedSceneValue(\.gameActions, gameActions)
        .alert("This option plays music on a Roland MT-32", isPresented: $suggestingMT32) {
            Button("Set Up MT-32…") {
                UserDefaults.standard.set("music", forKey: "SettingsTab")
                openSettings()
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Add the MT-32 files in Settings to hear it as composed.")
        }
        .sheet(isPresented: $editingControls) {
            ControlsEditor(controls: gamebox?.info.controls ?? GameControls(), save: setControls)
        }
        // The game waits while its controls are being changed
        .onChange(of: editingControls) { _, editing in
            if editing, emulator.isRunning, !emulator.isPaused {
                emulator.togglePause()
                pausedForControls = true
            } else if !editing, pausedForControls {
                pausedForControls = false
                if emulator.isPaused { emulator.togglePause() }
            }
        }
        .task(id: restartCount) { await prepareAndPlay() }
        .onChange(of: appLook) { applyLook() }
        // Speed chosen in the info panel: use it now
        .onReceive(NotificationCenter.default.publisher(for: Gamebox.speedChosen)) { note in
            guard (note.object as? URL)?.standardizedFileURL == url.standardizedFileURL,
                  var updated = gamebox, let saved = try? Gamebox.open(url) else { return }
            updated.info.settings = saved.info.settings
            gamebox = updated
            let speed = updated.currentSpeed
            emulator.setSpeed(realMode: speed.realMode, protectedMode: speed.protectedMode)
        }
        .onChange(of: emulator.isMouseLocked) { _, locked in
            if locked { show("Press ⌘⌥ to release the mouse", for: 3) }
        }
        .onChange(of: emulator.state) { _, state in
            if state == .running {
                stoppedByUser = false
                sessionStart = Date()
                noteSlowMT32Start()
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

    /// Uses the game's own look, or the app-wide one.
    private func applyLook() {
        emulator.displayLook = gamebox?.info.displayLook ?? appLook
    }

    /// Sets (or with nil, clears) this game's own look, remembering it in
    /// the gamebox.
    private func setLook(_ look: DisplayLook?) {
        guard var updated = gamebox else { return }
        updated.info.displayLook = look
        if !updated.isReadOnly { try? updated.save() }
        gamebox = updated
        applyLook()
    }

    /// Saves the game's controller controls and uses them right away.
    private func setControls(_ controls: GameControls) {
        guard var updated = gamebox else { return }
        updated.info.controls = controls.isEmpty ? nil : controls
        if !updated.isReadOnly { try? updated.save() }
        gamebox = updated
        emulator.controls = controls
    }

    /// Saves the speed the game is running at, a moment after it changed,
    /// so it starts at that speed next time.
    private func rememberSpeed() {
        speedSave?.cancel()
        speedSave = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, var updated = gamebox, let speed = emulator.frames?.speed(),
                  !speed.realMode.isEmpty else { return }
            for (key, value) in [("cpu cpu_cycles", speed.realMode), ("cpu cpu_cycles_protected", speed.protectedMode)] {
                updated.info.settings[key] = value.isEmpty ? nil : value
            }
            if !updated.isReadOnly { try? updated.save() }
            gamebox = updated
        }
    }

    /// Counts a finished session toward the game's play stats.
    private func endSession(_ gamebox: Gamebox) {
        guard let start = sessionStart else { return }
        sessionStart = nil
        PlayStats.recordSession(of: gamebox, startedAt: start)
    }

    // MARK: Actions (toolbar and the Game menu)

    private var gameActions: GameActions {
        GameActions(
            isRunning: emulator.isRunning,
            isPaused: emulator.isPaused,
            hasMoreDiscs: gamebox?.info.drives.contains { !($0.moreDiscs ?? []).isEmpty } ?? false,
            discs: discs,
            discIndex: discIndex,
            selectDisc: selectDisc,
            look: gamebox?.info.displayLook,
            launchers: gamebox?.info.launchers ?? [],
            togglePause: togglePause,
            takeScreenshot: takeScreenshot,
            changeSpeed: { faster in
                emulator.changeSpeed(faster: faster)
                show(faster ? "Faster" : "Slower")
                rememberSpeed()
            },
            nextDisc: {
                emulator.nextDisc()
                if !discs.isEmpty { discIndex = (discIndex + 1) % discs.count }
                show("Next disc")
            },
            setLook: { look in
                setLook(look)
                show(look?.title ?? "Default look")
            },
            run: run,
            editControls: { editingControls = true },
            restart: {
                stoppedByUser = true
                restartCount += 1
            },
            turnOff: turnOff)
    }

    @ViewBuilder private func programItems(_ gamebox: Gamebox) -> some View {
        let listed = Gamebox.listed(gamebox.info.launchers)
        ForEach(listed.choices) { launcher in
            Button(launcher.displayName) { run(.launcher(launcher)) }
        }
        if !listed.choices.isEmpty && !listed.others.isEmpty { Divider() }
        ForEach(listed.others) { launcher in
            Button(launcher.displayName) { run(.launcher(launcher)) }
        }
        Divider()
        Button("DOS Prompt") { run(.prompt) }
    }

    private var lookPicker: some View {
        Picker("Display Look", selection: Binding(get: { gamebox?.info.displayLook },
                                                  set: { gameActions.setLook($0) })) {
            Text("Default").tag(DisplayLook?.none)
            Divider()
            ForEach(DisplayLook.allCases) { Text($0.title).tag(DisplayLook?.some($0)) }
        }
        .pickerStyle(.inline)
    }

    private func togglePause() {
        emulator.togglePause()
    }

    private func turnOff() {
        stoppedByUser = true
        emulator.stop()
    }

    private func takeScreenshot() {
        guard let gamebox, let png = emulator.currentFrame()?.pngData() else { return }
        do {
            _ = try gamebox.saveScreenshot(png, in: screenshotsFolder)
            show("Screenshot saved")
        } catch {
            show("Couldn't save the screenshot")
        }
    }

    /// Shows a short notice over the game.
    private func show(_ message: String, for seconds: Double = 1.6) {
        notice = message
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if notice == message { notice = nil }
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
            emulator.displayLook = gamebox.effectiveDisplayLook
            emulator.controls = gamebox.info.controls ?? GameControls()
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

    /// Some games sit on a black screen for half a minute setting up their
    /// MT-32 music: say so, so it doesn't look stuck.
    private func noteSlowMT32Start() {
        let program: Gamebox.Launcher? = switch start {
        case .game: gamebox?.defaultLauncher
        case .launcher(let launcher): launcher
        case .prompt: nil
        }
        guard gamebox?.startsSlowlyWithMT32(program) == true else { return }
        show("This game sets up its MT-32 music first. This takes up to 30 seconds.", for: 10)
    }

    /// The discs the current session has in its CD drive, by name.
    private var discs: [String] { gamebox?.discNames(for: start) ?? [] }

    private var discPicker: some View {
        Picker("Disc", selection: Binding(get: { discIndex }, set: selectDisc)) {
            ForEach(Array(discs.enumerated()), id: \.offset) { index, name in
                Text(name).tag(index)
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }

    /// Puts disc `index` in the drive: DOSBox swaps to the next disc each
    /// time, so it steps round to it.
    private func selectDisc(_ index: Int) {
        guard discs.indices.contains(index), index != discIndex else { return }
        for _ in 0..<((index - discIndex + discs.count) % discs.count) { emulator.nextDisc() }
        discIndex = index
        show(discs[index])
    }

    /// Runs something else from the game's toolbar menu.
    private func run(_ newStart: Gamebox.Start) {
        // MT-32 music without the ROMs: offer to set them up (the game still
        // starts; its music falls back to the Mac's synthesizer)
        if case .launcher(let launcher) = newStart, Gamebox.usesMT32(launcher), !MT32Setup.isReady {
            suggestingMT32 = true
        }
        stoppedByUser = true
        start = newStart
        launch()
    }

    private func launch() {
        guard let gamebox else { return }
        discIndex = 0
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
                if code != 0 {
                    Text("DOS stopped unexpectedly.").foregroundStyle(.secondary)
                }
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
    /// Looking for box art: the stand-in shows a spinner instead of the
    /// floppy disk.
    let isLoading: Bool

    public init(gamebox: Gamebox?, isLoading: Bool = false) {
        self.gamebox = gamebox
        self.isLoading = isLoading
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
                    if isLoading {
                        ProgressView()
                    } else {
                        // Phosphor's floppy disk (MIT; see Licenses/)
                        Image("FloppyDisk", bundle: Bundle(for: Emulator.self))
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 48, height: 48)
                            .foregroundStyle(.secondary)
                    }
                }
                .aspectRatio(0.8, contentMode: .fit)
        }
    }
}
