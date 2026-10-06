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
    /// Watches for ⌘⌥ in this window whatever has keyboard focus, so the
    /// mouse can always be let go.
    private var releaseMonitor: Any?

    init(emulator: Emulator) {
        self.emulator = emulator
        super.init(frame: .zero, device: MTLCreateSystemDefaultDevice())
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        preferredFramesPerSecond = 120
        renderer = FrameRenderer(view: self, emulator: emulator)
        emulator.releaseMouse = { [weak self] in self?.unlockMouse() }
        delegate = renderer
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public override var acceptsFirstResponder: Bool { true }

    /// Leaving the window (the game stopped, or the window closed): give the
    /// mouse back first.
    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { unlockMouse() }
        super.viewWillMove(toWindow: newWindow)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let releaseMonitor { NSEvent.removeMonitor(releaseMonitor) }
        releaseMonitor = window == nil ? nil : NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            if let self, event.window === self.window,
               event.modifierFlags.isSuperset(of: [.command, .option]) {
                self.unlockMouse()
            }
            return event
        }
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

    /// The Mac's pointer movement, turned into game pixels: moving across
    /// the picture moves the game's cursor across the game's screen, as the
    /// pointer would cross the window.
    public override func mouseMoved(with event: NSEvent) {
        guard mouseLocked else { return }
        let scale = gamePixelsPerPoint()
        emulator.mouseMoved(dx: event.deltaX * scale, dy: event.deltaY * scale)
    }

    /// Game pixels per point of the picture as drawn (fitted inside the view).
    private func gamePixelsPerPoint() -> Double {
        guard let size = emulator.frames?.frameSize(), bounds.width > 0, bounds.height > 0 else { return 1 }
        // The picture is drawn at 4:3, as large as fits
        let drawnWidth = min(bounds.width, bounds.height * 4 / 3)
        return size.width / drawnWidth
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
