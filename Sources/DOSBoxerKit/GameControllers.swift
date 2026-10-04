import GameController

/// Forwards game controllers to the game in front.
///
/// macOS only sends controller input to the frontmost app, so DOS Boxer
/// reads controllers here and passes them to the engine of the active game
/// window, which presents them to DOS as an Xbox-style controller.
@MainActor
final class GameControllers {
    static let shared = GameControllers()

    /// The game that receives controller input (the last game window that
    /// was in front).
    weak var target: Emulator?

    private init() {
        GCController.controllers().forEach(attach)
        Task { @MainActor in
            for await note in NotificationCenter.default.notifications(named: .GCControllerDidConnect) {
                if let controller = note.object as? GCController { attach(controller) }
            }
        }
        GCController.startWirelessControllerDiscovery()
    }

    /// Starts listening (call once a game window exists).
    static func start() {
        _ = shared
    }

    private func attach(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        pad.valueChangedHandler = { gamepad, element in
            MainActor.assumeIsolated { GameControllers.shared.changed(element, in: gamepad) }
        }
    }

    private func changed(_ element: GCControllerElement, in pad: GCExtendedGamepad) {
        guard let target, target.isRunning else { return }
        switch element {
        case pad.leftThumbstick:
            target.joystickAxis(0, pad.leftThumbstick.xAxis.value)
            target.joystickAxis(1, -pad.leftThumbstick.yAxis.value)  // SDL: down is positive
        case pad.rightThumbstick:
            target.joystickAxis(3, pad.rightThumbstick.xAxis.value)
            target.joystickAxis(4, -pad.rightThumbstick.yAxis.value)
        case pad.leftTrigger:
            target.joystickAxis(2, pad.leftTrigger.value * 2 - 1)    // 0…1 → full axis
        case pad.rightTrigger:
            target.joystickAxis(5, pad.rightTrigger.value * 2 - 1)
        case pad.dpad:
            var hat: Int32 = 0
            if pad.dpad.up.isPressed { hat |= 1 }
            if pad.dpad.right.isPressed { hat |= 2 }
            if pad.dpad.down.isPressed { hat |= 4 }
            if pad.dpad.left.isPressed { hat |= 8 }
            target.joystickHat(hat)
        default:
            let buttons: [(GCControllerButtonInput?, Int32)] = [
                (pad.buttonA, 0), (pad.buttonB, 1), (pad.buttonX, 2), (pad.buttonY, 3),
                (pad.leftShoulder, 4), (pad.rightShoulder, 5), (pad.buttonOptions, 6), (pad.buttonMenu, 7),
                (pad.leftThumbstickButton, 8), (pad.rightThumbstickButton, 9), (pad.buttonHome, 10),
            ]
            for (button, index) in buttons where button === element {
                target.joystickButton(index, button?.isPressed ?? false)
            }
        }
    }
}
