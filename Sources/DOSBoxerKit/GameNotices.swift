import SwiftUI

/// Glass notices over a running game: "Paused", and short messages like
/// "Screenshot saved" or how to release the mouse. They can't be clicked,
/// so a click always goes to the game.
public struct GameNotices: View {
    let notice: String?
    let isPaused: Bool
    @Namespace private var glass

    public init(notice: String?, isPaused: Bool) {
        self.notice = notice
        self.isPaused = isPaused
    }

    public var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 12) {
                if isPaused {
                    Label("Paused", systemImage: "pause.fill")
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: .capsule)
                        .glassEffectID("paused", in: glass)
                }
                if let notice {
                    Text(notice)
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .glassEffect(.regular, in: .capsule)
                        .glassEffectID("notice", in: glass)
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: notice)
        .animation(.smooth(duration: 0.3), value: isPaused)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 32)
        .allowsHitTesting(false)
    }
}

/// What a game window can do, for the Game menu in the menu bar.
public struct GameActions {
    public var isRunning: Bool
    public var isPaused: Bool
    public var hasMoreDiscs: Bool
    public var look: DisplayLook?
    public var launchers: [Gamebox.Launcher]
    public var togglePause: () -> Void
    public var takeScreenshot: () -> Void
    public var changeSpeed: (_ faster: Bool) -> Void
    public var nextDisc: () -> Void
    public var setLook: (DisplayLook?) -> Void
    public var run: (Gamebox.Start) -> Void
    public var restart: () -> Void
    public var turnOff: () -> Void
}

extension FocusedValues {
    @Entry public var gameActions: GameActions?
}
