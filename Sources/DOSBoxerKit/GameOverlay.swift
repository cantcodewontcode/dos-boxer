import SwiftUI

/// Liquid Glass controls floating over a running game: speed, volume, next
/// disc and screenshot. They appear when the pointer moves over the game and
/// fade away when it rests, or while the mouse is captured by DOS.
struct GameOverlay: View {
    let emulator: Emulator
    let gamebox: Gamebox?
    let screenshotsFolder: URL
    let isVisible: Bool
    /// Called while the pointer is over the controls, to keep them showing.
    var keepVisible: () -> Void = {}

    @State private var toast: String?
    @State private var showingVolume = false
    @Namespace private var glass

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 12) {
                    if let toast {
                        Text(toast)
                            .font(.callout.weight(.medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .glassEffect(.regular, in: .capsule)
                            .glassEffectID("toast", in: glass)
                    }
                    if isVisible {
                        controls
                            .onContinuousHover { phase in
                                if case .active = phase { keepVisible() }
                            }
                    }
                }
            }
            .animation(.smooth(duration: 0.3), value: isVisible)
            .animation(.smooth(duration: 0.3), value: toast)
            .animation(.smooth(duration: 0.3), value: showingVolume)
        }
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            control("Slower", systemImage: "tortoise") {
                emulator.changeSpeed(faster: false)
                flash("Slower")
            }
            control("Faster", systemImage: "hare") {
                emulator.changeSpeed(faster: true)
                flash("Faster")
            }

            HStack(spacing: 8) {
                Button {
                    showingVolume.toggle()
                } label: {
                    Image(systemName: volumeSymbol)
                        .frame(width: 22)
                }
                .buttonStyle(.plain)
                .help("Volume")
                if showingVolume {
                    Slider(value: Bindable(emulator).volume, in: 0...1)
                        .frame(width: 120)
                        .help("Game volume")
                }
            }
            .font(.title3)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .glassEffect(.regular.interactive(), in: .capsule)
            .glassEffectID("volume", in: glass)

            if hasMoreDiscs {
                control("Next Disc", systemImage: "opticaldisc") {
                    emulator.nextDisc()
                    flash("Next disc")
                }
            }
            control("Screenshot", systemImage: "camera") {
                takeScreenshot()
            }
        }
    }

    private func control(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .glassEffectID(title, in: glass)
        .help(title)
    }

    private var volumeSymbol: String {
        switch emulator.volume {
        case 0: "speaker.slash"
        case ..<0.34: "speaker.wave.1"
        case ..<0.67: "speaker.wave.2"
        default: "speaker.wave.3"
        }
    }

    private var hasMoreDiscs: Bool {
        gamebox?.info.drives.contains { !($0.moreDiscs ?? []).isEmpty } ?? false
    }

    private func takeScreenshot() {
        guard let gamebox, let png = emulator.currentFrame()?.pngData() else { return }
        do {
            _ = try gamebox.saveScreenshot(png, in: screenshotsFolder)
            flash("Screenshot saved")
        } catch {
            flash("Couldn't save the screenshot")
        }
    }

    /// Shows a short glass message above the controls.
    private func flash(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if toast == message { toast = nil }
        }
    }
}
