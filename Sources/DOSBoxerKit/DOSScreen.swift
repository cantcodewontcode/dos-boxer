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
