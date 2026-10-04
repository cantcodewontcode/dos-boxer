import AppKit
import SwiftUI

/// The buttons and directions of a game controller, by position. Every
/// modern controller (Xbox, PlayStation, Logitech…) reports this same
/// layout, so a game's controls work whichever controller is plugged in.
public enum ControllerInput: String, Codable, CaseIterable, Identifiable, Sendable {
    case a, b, x, y
    case leftShoulder, rightShoulder, leftTrigger, rightTrigger
    case dpadUp, dpadDown, dpadLeft, dpadRight
    case leftStickUp, leftStickDown, leftStickLeft, leftStickRight
    case leftStickButton, rightStickButton
    case back, start

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .a: "A"
        case .b: "B"
        case .x: "X"
        case .y: "Y"
        case .leftShoulder: "Left Bumper"
        case .rightShoulder: "Right Bumper"
        case .leftTrigger: "Left Trigger"
        case .rightTrigger: "Right Trigger"
        case .dpadUp: "D-Pad Up"
        case .dpadDown: "D-Pad Down"
        case .dpadLeft: "D-Pad Left"
        case .dpadRight: "D-Pad Right"
        case .leftStickUp: "Left Stick Up"
        case .leftStickDown: "Left Stick Down"
        case .leftStickLeft: "Left Stick Left"
        case .leftStickRight: "Left Stick Right"
        case .leftStickButton: "Left Stick Press"
        case .rightStickButton: "Right Stick Press"
        case .back: "Back"
        case .start: "Start"
        }
    }

    public var symbol: String {
        switch self {
        case .a: "a.circle"
        case .b: "b.circle"
        case .x: "x.circle"
        case .y: "y.circle"
        case .leftShoulder: "lb.rectangle.roundedbottom"
        case .rightShoulder: "rb.rectangle.roundedbottom"
        case .leftTrigger: "lt.rectangle.roundedtop"
        case .rightTrigger: "rt.rectangle.roundedtop"
        case .dpadUp: "dpad.up.filled"
        case .dpadDown: "dpad.down.filled"
        case .dpadLeft: "dpad.left.filled"
        case .dpadRight: "dpad.right.filled"
        case .leftStickUp: "l.joystick.tilt.up"
        case .leftStickDown: "l.joystick.tilt.down"
        case .leftStickLeft: "l.joystick.tilt.left"
        case .leftStickRight: "l.joystick.tilt.right"
        case .leftStickButton: "l.joystick.press.down"
        case .rightStickButton: "r.joystick.press.down"
        case .back: "rectangle.on.rectangle"
        case .start: "line.3.horizontal"
        }
    }

    /// The joystick button it is by default (XInput order), if a button.
    var defaultButton: Int32? {
        switch self {
        case .a: 0
        case .b: 1
        case .x: 2
        case .y: 3
        case .leftShoulder: 4
        case .rightShoulder: 5
        case .back: 6
        case .start: 7
        case .leftStickButton: 8
        case .rightStickButton: 9
        default: nil
        }
    }
}

/// What a controller input does in a game instead of its usual job.
public enum ControlAction: Codable, Hashable, Sendable {
    /// Press a key; `name` is how it's shown, e.g. "Space" or "Z".
    case key(scancode: Int32, name: String)
    /// Act as another joystick button (0 A, 1 B, 2 X, 3 Y, …).
    case button(Int32)
    /// Do nothing.
    case nothing

    public var title: String {
        switch self {
        case .key(_, let name): name
        case .button(let number):
            ControllerInput.allCases.first { $0.defaultButton == number }.map { "Joystick \($0.title)" }
                ?? "Joystick Button \(number + 1)"
        case .nothing: "Nothing"
        }
    }
}

/// A game's own controls: per player, what inputs do instead of the usual.
/// Inputs not listed work as a normal joystick.
public struct GameControls: Codable, Equatable, Sendable {
    public var player1: [ControllerInput: ControlAction] = [:]
    public var player2: [ControllerInput: ControlAction] = [:]

    public init() {}

    public var isEmpty: Bool { player1.isEmpty && player2.isEmpty }

    public subscript(player: Int) -> [ControllerInput: ControlAction] {
        get { player == 0 ? player1 : player2 }
        set { if player == 0 { player1 = newValue } else { player2 = newValue } }
    }
}

// MARK: - Editing

/// Sets up a game's controls: for player 1 and 2, what each controller
/// button and direction does (a key, another button, or nothing).
public struct ControlsEditor: View {
    @State private var controls: GameControls
    @State private var player = 0
    @State private var capturing: ControllerInput?
    private let save: (GameControls) -> Void
    @Environment(\.dismiss) private var dismiss

    public init(controls: GameControls, save: @escaping (GameControls) -> Void) {
        _controls = State(initialValue: controls)
        self.save = save
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("Player", selection: $player) {
                Text("Player 1").tag(0)
                Text("Player 2").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            Form {
                ForEach(ControllerInput.allCases) { input in
                    LabeledContent {
                        actionMenu(for: input)
                    } label: {
                        Label(input.title, systemImage: input.symbol)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Reset") { controls[player] = [:] }
                    .disabled(controls[player].isEmpty)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Done") {
                    save(controls)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 420, height: 560)
        .background(KeyCapture(isActive: capturing != nil) { scancode, name in
            if scancode >= 0, let input = capturing {
                controls[player][input] = .key(scancode: scancode, name: name)
            }
            capturing = nil
        })
    }

    @ViewBuilder private func actionMenu(for input: ControllerInput) -> some View {
        if capturing == input {
            Text("Press a key…")
                .foregroundStyle(.tint)
        } else {
            Menu(controls[player][input]?.title ?? "Joystick") {
                Button("Joystick") { controls[player][input] = nil }
                Button("Key…") { capturing = input }
                Menu("Joystick Button") {
                    ForEach(ControllerInput.allCases.filter { $0.defaultButton != nil }) { other in
                        Button(other.title) { controls[player][input] = .button(other.defaultButton!) }
                    }
                }
                Divider()
                Button("Nothing") { controls[player][input] = .nothing }
            }
            .fixedSize()
            .foregroundStyle(controls[player][input] == nil ? .secondary : .primary)
        }
    }
}

/// While active, takes the next key pressed (Escape cancels).
private struct KeyCapture: NSViewRepresentable {
    let isActive: Bool
    let captured: (Int32, String) -> Void

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.captured = captured
        context.coordinator.setActive(isActive)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator {
        var captured: ((Int32, String) -> Void)?
        private var monitor: Any?

        func setActive(_ active: Bool) {
            if active, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                    guard let self else { return event }
                    // Shift, Control and Option count when pressed, not released
                    if event.type == .flagsChanged {
                        let held = event.modifierFlags.intersection([.shift, .control, .option])
                        guard !held.isEmpty, [56, 60, 59, 62, 58, 61].contains(event.keyCode) else { return nil }
                    }
                    if event.keyCode == 53 {  // Escape cancels
                        self.captured?(-1, "")
                    } else if let scancode = KeyboardMapper.scancode(forKeyCode: event.keyCode) {
                        self.captured?(scancode, Self.name(of: event))
                    }
                    return nil
                }
            } else if !active, let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        static func name(of event: NSEvent) -> String {
            let named: [UInt16: String] = [
                56: "Shift", 60: "Right Shift", 59: "Control", 62: "Right Control",
                58: "Option", 61: "Right Option", 49: "Space", 36: "Return", 48: "Tab", 51: "Backspace", 117: "Delete",
                123: "Left Arrow", 124: "Right Arrow", 125: "Down Arrow", 126: "Up Arrow",
                115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
                122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
                98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            ]
            if let name = named[event.keyCode] { return name }
            return event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        }
    }
}
