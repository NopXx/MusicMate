import AppKit

final class LockScreenWindow: NSWindow {
    convenience init(screen: NSScreen) {
        self.init(contentRect: screen.frame,
                  styleMask: .borderless,
                  backing: .buffered,
                  defer: false,
                  screen: screen)
        // Layering above the macOS lock UI is actually performed by
        // `SkyLightOperator` (private CGS space pinned at
        // NotificationCenterAtScreenLock level). The high level here is just
        // for the "Show Now" test path when the screen isn't locked.
        self.level = NSWindow.Level(rawValue: Int(Int32.max) - 2)
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
        self.ignoresMouseEvents = false
        self.isMovable = false
        self.isMovableByWindowBackground = false
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false
        self.animationBehavior = .none
        // Required for the window to render in the loginwindow / lock UI
        // context — without this the WindowServer suppresses the window.
        self.canBecomeVisibleWithoutLogin = true
        self.setFrame(screen.frame, display: false)
    }
}
