import SwiftUI

/// The running DOS screen, inset so the rounded window corners never clip it.
public struct DOSScreen: View {
    let emulator: Emulator

    public init(emulator: Emulator) {
        self.emulator = emulator
    }

    public var body: some View {
        EmulatorView(emulator: emulator)
            .padding(12)
    }
}

/// Plain toolbar text (no glass: it's a hint, not a control) telling people
/// how to get the mouse in and out of DOS.
public struct MouseHint: ToolbarContent {
    let emulator: Emulator

    public init(emulator: Emulator) {
        self.emulator = emulator
    }

    public var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Text(hint)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
        .sharedBackgroundVisibility(.hidden)
    }

    private var hint: String {
        guard emulator.isRunning else { return "" }
        return emulator.isMouseLocked
            ? "Press ⌘⌥ to release the mouse"
            : "Click the screen to use the mouse in DOS"
    }
}
