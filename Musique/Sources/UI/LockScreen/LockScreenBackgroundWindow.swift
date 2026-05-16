import AppKit

final class LockScreenBackgroundWindow: NSWindow {
    convenience init(screen: NSScreen) {
        self.init(contentRect: screen.frame,
                  styleMask: .borderless,
                  backing: .buffered,
                  defer: false,
                  screen: screen)
        self.level = NSWindow.Level(rawValue: Int(Int32.max) - 3)
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
        self.isOpaque = false
        self.alphaValue = 1
        self.backgroundColor = .clear
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.isMovable = false
        self.isMovableByWindowBackground = false
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false
        self.animationBehavior = .none
        self.canBecomeVisibleWithoutLogin = true
        self.setFrame(screen.frame, display: false)
    }
}
