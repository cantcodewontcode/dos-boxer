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
/// Clicking the screen locks the mouse to the game; pressing ⌘ (or switching
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
        renderer = FrameRenderer(view: self, frames: emulator.frames)
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
    }

    @objc private func windowLostFocus() {
        unlockMouse()
    }

    // MARK: Keyboard

    public override func keyDown(with event: NSEvent) {
        // Leave ⌘ shortcuts to the app menus
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

    public override func flagsChanged(with event: NSEvent) {
        guard let change = KeyboardMapper.modifierChange(keyCode: event.keyCode, flags: event.modifierFlags) else { return }
        if event.modifierFlags.contains(.command) {
            unlockMouse()
        }
        // ⌘ belongs to the Mac, not DOS
        if change.scancode == 227 || change.scancode == 231 { return }
        emulator.key(scancode: change.scancode, isDown: change.isDown)
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
        window?.acceptsMouseMovedEvents = true
        NSCursor.hide()
        CGAssociateMouseAndMouseCursorPosition(0)
    }

    private func unlockMouse() {
        guard mouseLocked else { return }
        mouseLocked = false
        CGAssociateMouseAndMouseCursorPosition(1)
        NSCursor.unhide()
    }
}
