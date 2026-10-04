import DOSBoxerKit
import SwiftUI

/// Settings › Controllers: what's connected, which player each controller
/// is, and a live test.
struct ControllerSettings: View {
    private let controllers = GameControllers.shared

    var body: some View {
        Form {
            Section {
                if controllers.pads.isEmpty {
                    Text("No controllers connected")
                        .foregroundStyle(.secondary)
                }
                ForEach(controllers.pads) { pad in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(pad.name, systemImage: "gamecontroller")
                            if let battery = pad.battery {
                                Image(systemName: Self.batterySymbol(battery))
                                    .foregroundStyle(.secondary)
                                    .help("Battery \(Int(battery * 100))%")
                            }
                            Spacer()
                            Picker("Player", selection: Binding(
                                get: { pad.player },
                                set: { controllers.setPlayer($0, for: pad) })) {
                                Text("Player 1").tag(Int?.some(0))
                                Text("Player 2").tag(Int?.some(1))
                                Divider()
                                Text("Not Used").tag(Int?.none)
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        PressedButtons(symbols: pad.pressed)
                    }
                    .padding(.vertical, 2)
                }
            } footer: {
                Text("DOS games support up to two controllers. The keyboard always works too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private static func batterySymbol(_ level: Float) -> String {
        switch level {
        case ..<0.15: "battery.0percent"
        case ..<0.4: "battery.25percent"
        case ..<0.65: "battery.50percent"
        case ..<0.9: "battery.75percent"
        default: "battery.100percent"
        }
    }
}

/// The buttons being pressed right now, or a hint to try some.
private struct PressedButtons: View {
    let symbols: [String]

    var body: some View {
        HStack(spacing: 6) {
            if symbols.isEmpty {
                Text("Press a button to test it")
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                    Image(systemName: symbol)
                        .foregroundStyle(.tint)
                }
            }
        }
        .font(.callout)
        .frame(height: 20)
    }
}
