import AppKit
import MetalKit
import SwiftUI

/// The DOS screen. Shows emulator frames and forwards keyboard and mouse
/// input while it has focus.
public struct EmulatorView: NSViewRepresentable {
    private let emulator: Emulator

    public init(emulator: Emulator) {
        self.emulator = emulator
    }

    public func makeNSView(context: Context) -> EmulatorMTKView {
        EmulatorMTKView(emulator: emulator)
    }

    public func updateNSView(_ view: EmulatorMTKView, context: Context) {}
}

/// An MTKView that renders the emulator and captures input.
///
/// Clicking the screen locks the mouse to the game; pressing ⌘⌥ (or switching
/// away) gives it back.
public final class EmulatorMTKView: MTKView {
    private let emulator: Emulator
    private var renderer: FrameRenderer?
    private var mouseLocked = false

    init(emulator: Emulator) {
        self.emulator = emulator
        super.init(frame: .zero, device: MTLCreateSystemDefaultDevice())
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        preferredFramesPerSecond = 120
        renderer = FrameRenderer(view: self, emulator: emulator)
        delegate = renderer
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public override var acceptsFirstResponder: Bool { true }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        NotificationCenter.default.addObserver(self, selector: #selector(windowLostFocus),
                                               name: NSWindow.didResignKeyNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(windowGotFocus),
                                               name: NSWindow.didBecomeKeyNotification, object: window)
        // Controllers go to this game from the start
        GameControllers.shared.target = emulator
    }

    @objc private func windowGotFocus() {
        GameControllers.shared.target = emulator
    }

    @objc private func windowLostFocus() {
        releaseModifiersInDOS()
        unlockMouse()
    }

    // MARK: Keyboard

    public override func keyDown(with event: NSEvent) {
        // ⌘P pauses (as in DOSBox Staging)
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "p" {
            emulator.togglePause()
            // Give the mouse back so the controls can be clicked
            if emulator.isPaused { unlockMouse() }
            return
        }
        // Leave other ⌘ shortcuts to the app menus
        if event.modifierFlags.contains(.command) {
            super.keyDown(with: event)
            return
        }
        guard !event.isARepeat, let scancode = KeyboardMapper.scancode(forKeyCode: event.keyCode) else { return }
        emulator.key(scancode: scancode, isDown: true)
    }

    public override func keyUp(with event: NSEvent) {
        guard let scancode = KeyboardMapper.scancode(forKeyCode: event.keyCode) else { return }
        emulator.key(scancode: scancode, isDown: false)
    }

    /// Modifier keys DOS currently has held down, so we can let go of them
    /// on its behalf.
    private var modifiersDownInDOS: Set<Int32> = []

    /// Modifiers work like this:
    /// - ⌘ belongs to the Mac and is never sent to DOS.
    /// - While ⌘ is held, other modifiers aren't sent either, so ⌘⌥ (release
    ///   the mouse) doesn't press Alt in the game.
    /// - If ⌥ went down first, DOS gets its key-up as soon as ⌘ joins it.
    public override func flagsChanged(with event: NSEvent) {
        let flags = event.modifierFlags
        guard let change = KeyboardMapper.modifierChange(keyCode: event.keyCode, flags: flags) else { return }

        if flags.contains(.command) {
            releaseModifiersInDOS()
            if flags.contains(.option) {
                unlockMouse()
            }
            return
        }
        if KeyboardMapper.isCommand(scancode: change.scancode) { return }

        if change.isDown {
            modifiersDownInDOS.insert(change.scancode)
            emulator.key(scancode: change.scancode, isDown: true)
        } else if modifiersDownInDOS.remove(change.scancode) != nil {
            emulator.key(scancode: change.scancode, isDown: false)
        }
    }

    private func releaseModifiersInDOS() {
        for scancode in modifiersDownInDOS {
            emulator.key(scancode: scancode, isDown: false)
        }
        modifiersDownInDOS.removeAll()
    }

    /// Edit > Paste: types the clipboard's text into DOS.
    @objc public func paste(_ sender: Any?) {
        if let text = NSPasteboard.general.string(forType: .string) {
            emulator.paste(text)
        }
    }

    // MARK: Mouse

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if !mouseLocked {
            lockMouse()
            return
        }
        emulator.mouseButton(1, isDown: true)
    }

    public override func mouseUp(with event: NSEvent) {
        if mouseLocked { emulator.mouseButton(1, isDown: false) }
    }

    public override func rightMouseDown(with event: NSEvent) {
        if mouseLocked { emulator.mouseButton(3, isDown: true) }
    }

    public override func rightMouseUp(with event: NSEvent) {
        if mouseLocked { emulator.mouseButton(3, isDown: false) }
    }

    public override func mouseMoved(with event: NSEvent) {
        if mouseLocked { emulator.mouseMoved(dx: event.deltaX, dy: event.deltaY) }
    }

    public override func mouseDragged(with event: NSEvent) { mouseMoved(with: event) }
    public override func rightMouseDragged(with event: NSEvent) { mouseMoved(with: event) }

    private func lockMouse() {
        guard emulator.isRunning else { return }
        mouseLocked = true
        emulator.isMouseLocked = true
        window?.acceptsMouseMovedEvents = true
        NSCursor.hide()
        CGAssociateMouseAndMouseCursorPosition(0)
    }

    private func unlockMouse() {
        guard mouseLocked else { return }
        mouseLocked = false
        emulator.isMouseLocked = false
        CGAssociateMouseAndMouseCursorPosition(1)
        NSCursor.unhide()
    }
}
