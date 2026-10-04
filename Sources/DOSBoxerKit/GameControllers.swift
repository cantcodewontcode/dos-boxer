import GameController
import Observation

/// The game controllers connected to the Mac, which player each one is, and
/// forwarding their input to the game in front.
///
/// macOS only sends controller input to the frontmost app, so DOS Boxer
/// reads controllers here and passes them to the engine of the active game
/// window, which presents them to DOS as Xbox-style controllers. DOS games
/// support at most two joysticks; the keyboard works for everyone.
@MainActor @Observable
public final class GameControllers {
    public static let shared = GameControllers()

    public struct Pad: Identifiable {
        public let id: ObjectIdentifier
        public let name: String
        /// 0…1, if the controller reports it.
        public var battery: Float?
        /// 0 for player 1, 1 for player 2, nil if not used.
        public var player: Int?
        /// Symbols of the buttons and sticks being pressed now, for testing.
        public var pressed: [String] = []
        fileprivate let controller: GCController
    }

    public private(set) var pads: [Pad] = []

    /// The game that receives controller input (the last game window that
    /// was in front).
    @ObservationIgnored weak var target: Emulator?

    /// Player chosen per controller name, remembered across launches.
    private static let playersKey = "ControllerPlayers"

    private init() {
        GCController.shouldMonitorBackgroundEvents = true
        GCController.controllers().forEach(attach)
        Task { @MainActor in
            for await note in NotificationCenter.default.notifications(named: .GCControllerDidConnect) {
                if let controller = note.object as? GCController { attach(controller) }
            }
        }
        Task { @MainActor in
            for await note in NotificationCenter.default.notifications(named: .GCControllerDidDisconnect) {
                if let controller = note.object as? GCController { detach(controller) }
            }
        }
        GCController.startWirelessControllerDiscovery()
    }

    /// Starts listening.
    public static func start() {
        _ = shared
    }

    /// Makes `pad` player 0 or 1, or unused (nil). A controller already
    /// playing that player swaps to `pad`'s old one.
    public func setPlayer(_ player: Int?, for pad: Pad) {
        guard let index = pads.firstIndex(where: { $0.id == pad.id }) else { return }
        let old = pads[index].player
        if let player, let other = pads.firstIndex(where: { $0.player == player && $0.id != pad.id }) {
            pads[other].player = old
            releaseAll(pads[other], player: player)
        }
        if let old { releaseAll(pads[index], player: old) }
        pads[index].player = player
        rememberPlayers()
    }

    private func attach(_ controller: GCController) {
        guard let pad = controller.extendedGamepad,
              !pads.contains(where: { $0.controller === controller }) else { return }
        // Some (like wired Xbox 360 controllers) only report what kind they are
        let name = controller.vendorName ?? (controller.productCategory.isEmpty ? "Controller"
                                              : controller.productCategory)
        // The player it had last time, else the first free one
        let remembered = (UserDefaults.standard.dictionary(forKey: Self.playersKey) as? [String: Int])?[name]
        let taken = Set(pads.compactMap(\.player))
        let player: Int? = remembered.flatMap { taken.contains($0) ? nil : $0 } ?? [0, 1].first { !taken.contains($0) }
        pads.append(Pad(id: ObjectIdentifier(controller), name: name,
                        battery: Self.battery(of: controller), player: player, controller: controller))
        pad.valueChangedHandler = { gamepad, element in
            MainActor.assumeIsolated { GameControllers.shared.changed(element, in: gamepad, of: controller) }
        }
    }

    private func detach(_ controller: GCController) {
        if let pad = pads.first(where: { $0.controller === controller }), let player = pad.player {
            releaseAll(pad, player: player)
        }
        pads.removeAll { $0.controller === controller }
    }

    private func rememberPlayers() {
        var players = (UserDefaults.standard.dictionary(forKey: Self.playersKey) as? [String: Int]) ?? [:]
        for pad in pads { players[pad.name] = pad.player ?? -1 }
        UserDefaults.standard.set(players, forKey: Self.playersKey)
    }

    /// Lets go of everything, so nothing stays held when a controller
    /// changes player or disconnects.
    private func releaseAll(_ pad: Pad, player: Int) {
        guard let target, target.isRunning else { return }
        let player = Int32(player)
        for axis in Int32(0)...5 { target.joystickAxis(axis, axis == 2 || axis == 5 ? -1 : 0, player: player) }
        for button in Int32(0)...10 { target.joystickButton(button, false, player: player) }
        target.joystickHat(0, player: player)
    }

    private func changed(_ element: GCControllerElement, in pad: GCExtendedGamepad, of controller: GCController) {
        guard let index = pads.firstIndex(where: { $0.controller === controller }) else { return }
        pads[index].pressed = Self.pressedSymbols(pad)
        pads[index].battery = Self.battery(of: controller)
        guard let playerIndex = pads[index].player, let target, target.isRunning else { return }
        let player = Int32(playerIndex)
        let controls = target.controls[playerIndex]

        // Inputs the game's controls change: act on presses and releases
        let id = pads[index].id
        let now = Self.held(pad)
        let before = heldInputs[id] ?? []
        heldInputs[id] = now
        for input in now.symmetricDifference(before) {
            let isDown = now.contains(input)
            switch controls[input] {
            case .key(let scancode, _)?: target.key(scancode: scancode, isDown: isDown)
            case .button(let number)?: target.joystickButton(number, isDown, player: player)
            case .nothing?, nil: break
            }
        }

        // Everything else works as a normal joystick
        let changesStick = [ControllerInput.leftStickUp, .leftStickDown, .leftStickLeft, .leftStickRight]
            .contains { controls[$0] != nil }
        switch element {
        case pad.leftThumbstick where !changesStick:
            target.joystickAxis(0, pad.leftThumbstick.xAxis.value, player: player)
            target.joystickAxis(1, -pad.leftThumbstick.yAxis.value, player: player)  // SDL: down is positive
        case pad.rightThumbstick:
            target.joystickAxis(3, pad.rightThumbstick.xAxis.value, player: player)
            target.joystickAxis(4, -pad.rightThumbstick.yAxis.value, player: player)
        case pad.leftTrigger where controls[.leftTrigger] == nil:
            target.joystickAxis(2, pad.leftTrigger.value * 2 - 1, player: player)    // 0…1 → full axis
        case pad.rightTrigger where controls[.rightTrigger] == nil:
            target.joystickAxis(5, pad.rightTrigger.value * 2 - 1, player: player)
        case pad.dpad:
            var hat: Int32 = 0
            if pad.dpad.up.isPressed && controls[.dpadUp] == nil { hat |= 1 }
            if pad.dpad.right.isPressed && controls[.dpadRight] == nil { hat |= 2 }
            if pad.dpad.down.isPressed && controls[.dpadDown] == nil { hat |= 4 }
            if pad.dpad.left.isPressed && controls[.dpadLeft] == nil { hat |= 8 }
            target.joystickHat(hat, player: player)
        default:
            for (button, number) in Self.buttons(of: pad) where button === element {
                // Buttons the game's controls change were handled above
                if let input = ControllerInput.allCases.first(where: { $0.defaultButton == number }),
                   controls[input] != nil { continue }
                target.joystickButton(number, button?.isPressed ?? false, player: player)
            }
        }
    }

    /// Inputs held down per controller, to spot presses and releases.
    @ObservationIgnored private var heldInputs: [ObjectIdentifier: Set<ControllerInput>] = [:]

    /// Lets go of keys held through a game's controls (e.g. before the
    /// controls change).
    func releaseHeldKeys() {
        guard let target else { return }
        for pad in pads {
            guard let player = pad.player else { continue }
            for input in heldInputs[pad.id] ?? [] {
                if case .key(let scancode, _)? = target.controls[player][input] {
                    target.key(scancode: scancode, isDown: false)
                }
            }
        }
        heldInputs = [:]
    }

    /// The controller inputs pressed now, with sticks and triggers counted
    /// past halfway.
    private static func held(_ pad: GCExtendedGamepad) -> Set<ControllerInput> {
        let threshold: Float = 0.5
        let stick = pad.leftThumbstick
        let checks: [(ControllerInput, Bool)] = [
            (.a, pad.buttonA.isPressed), (.b, pad.buttonB.isPressed),
            (.x, pad.buttonX.isPressed), (.y, pad.buttonY.isPressed),
            (.leftShoulder, pad.leftShoulder.isPressed), (.rightShoulder, pad.rightShoulder.isPressed),
            (.leftTrigger, pad.leftTrigger.value > threshold), (.rightTrigger, pad.rightTrigger.value > threshold),
            (.dpadUp, pad.dpad.up.isPressed), (.dpadDown, pad.dpad.down.isPressed),
            (.dpadLeft, pad.dpad.left.isPressed), (.dpadRight, pad.dpad.right.isPressed),
            (.leftStickUp, stick.yAxis.value > threshold), (.leftStickDown, stick.yAxis.value < -threshold),
            (.leftStickLeft, stick.xAxis.value < -threshold), (.leftStickRight, stick.xAxis.value > threshold),
            (.leftStickButton, pad.leftThumbstickButton?.isPressed ?? false),
            (.rightStickButton, pad.rightThumbstickButton?.isPressed ?? false),
            (.back, pad.buttonOptions?.isPressed ?? false), (.start, pad.buttonMenu.isPressed),
        ]
        return Set(checks.filter(\.1).map(\.0))
    }

    /// The battery level, if the controller has a battery and reports it.
    private static func battery(of controller: GCController) -> Float? {
        guard let battery = controller.battery, battery.batteryState != .unknown else { return nil }
        return battery.batteryLevel
    }

    private static func buttons(of pad: GCExtendedGamepad) -> [(GCControllerButtonInput?, Int32)] {
        [(pad.buttonA, 0), (pad.buttonB, 1), (pad.buttonX, 2), (pad.buttonY, 3),
         (pad.leftShoulder, 4), (pad.rightShoulder, 5), (pad.buttonOptions, 6), (pad.buttonMenu, 7),
         (pad.leftThumbstickButton, 8), (pad.rightThumbstickButton, 9), (pad.buttonHome, 10)]
    }

    /// What's being pressed or pushed, as the controller's own symbols.
    private static func pressedSymbols(_ pad: GCExtendedGamepad) -> [String] {
        var symbols: [String] = []
        func add(_ element: GCControllerElement, _ fallback: String) {
            symbols.append(element.sfSymbolsName ?? fallback)
        }
        let deadZone: Float = 0.3
        for direction in [pad.dpad.up, pad.dpad.down, pad.dpad.left, pad.dpad.right] where direction.isPressed {
            add(direction, "dpad")
        }
        for stick in [pad.leftThumbstick, pad.rightThumbstick]
        where abs(stick.xAxis.value) > deadZone || abs(stick.yAxis.value) > deadZone {
            add(stick, "circle.circle")
        }
        for trigger in [pad.leftTrigger, pad.rightTrigger] where trigger.value > deadZone {
            add(trigger, "button.horizontal")
        }
        for (button, _) in buttons(of: pad) {
            if let button, button.isPressed { add(button, "circle.fill") }
        }
        return symbols
    }
}
