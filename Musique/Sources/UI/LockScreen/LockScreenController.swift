import AppKit
import SwiftUI
import Combine
import os

@MainActor
final class LockScreenController {
    static var shared: LockScreenController?

    private let log = Logger(subsystem: "com.nopxx.musique", category: "LockScreen")
    private let playerMonitor: PlayerMonitor
    private let viewModel: LockScreenViewModel
    private var backgroundWindows: [LockScreenBackgroundWindow] = []
    private var playerWindows: [LockScreenWindow] = []
    private var cancellables = Set<AnyCancellable>()
    private var isLocked = false
    private var raiseTimer: Timer?

    init(playerMonitor: PlayerMonitor) {
        self.playerMonitor = playerMonitor
        self.viewModel = LockScreenViewModel(monitor: playerMonitor)

        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self,
                        selector: #selector(handleScreenLocked),
                        name: NSNotification.Name("com.apple.screenIsLocked"),
                        object: nil)
        dnc.addObserver(self,
                        selector: #selector(handleScreenUnlocked),
                        name: NSNotification.Name("com.apple.screenIsUnlocked"),
                        object: nil)
        dnc.addObserver(self,
                        selector: #selector(handleLockUIShown),
                        name: NSNotification.Name("com.apple.screenLockUIIsShown"),
                        object: nil)
        dnc.addObserver(self,
                        selector: #selector(handleLockUIHidden),
                        name: NSNotification.Name("com.apple.screenLockUIIsHidden"),
                        object: nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        SettingsStore.shared.$data
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.evaluateVisibility() }
            .store(in: &cancellables)

        playerMonitor.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snap in
                guard let self else { return }
                if self.isLocked, snap?.hasTrack != true {
                    self.dismiss()
                } else if self.isLocked {
                    self.evaluateVisibility()
                }
            }
            .store(in: &cancellables)

        log.info("LockScreenController initialised")
        Self.shared = self
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleScreenLocked() {
        log.info("DistributedNotification: screenIsLocked")
        isLocked = true
        evaluateVisibility()
    }

    @objc private func handleScreenUnlocked() {
        log.info("DistributedNotification: screenIsUnlocked")
        isLocked = false
        stopRaiseLoop()
        dismiss()
    }

    @objc private func handleLockUIShown() {
        log.info("DistributedNotification: screenLockUIIsShown — re-raising window")
        raiseAllWindows()
        startRaiseLoop()
    }

    @objc private func handleLockUIHidden() {
        log.info("DistributedNotification: screenLockUIIsHidden")
        stopRaiseLoop()
    }

    @objc private func handleScreensChanged() {
        guard isLocked, !playerWindows.isEmpty else { return }
        log.info("Screen parameters changed — rebuilding windows")
        rebuildWindows()
    }

    func setFullscreenAnimationActive(_ active: Bool) {
        viewModel.fullscreenAnimationActive = active
    }

    private func evaluateVisibility() {
        guard isLocked else { return }
        let s = SettingsStore.shared
        let enabled = s.bool(["lockscreen", "enabled"])
        let hasTrack = playerMonitor.snapshot?.hasTrack == true
        log.info("evaluateVisibility — enabled:\(enabled) hasTrack:\(hasTrack) windows:\(self.playerWindows.count)")
        guard enabled, hasTrack else {
            dismiss()
            return
        }
        if playerWindows.isEmpty {
            present()
        } else {
            applyScreensIfNeeded()
        }
    }

    private func present() {
        let targets = targetScreens()
        log.info("present — \(targets.count) screen(s)")
        for screen in targets {
            let bgWindow = LockScreenBackgroundWindow(screen: screen)
            let bgHost = NSHostingController(rootView: ArtworkLockScreenView(viewModel: viewModel))
            bgHost.view.frame = NSRect(origin: .zero, size: screen.frame.size)
            bgWindow.contentViewController = bgHost
            bgWindow.setFrame(screen.frame, display: true)
            SkyLightOperator.shared.promoteAboveLockScreen(bgWindow)
            bgWindow.makeKeyAndOrderFront(nil)
            backgroundWindows.append(bgWindow)

            let playerWindow = LockScreenWindow(screen: screen)
            let playerHost = NSHostingController(rootView: LockScreenPlayerView(viewModel: viewModel))
            playerHost.view.frame = NSRect(origin: .zero, size: screen.frame.size)
            playerWindow.contentViewController = playerHost
            playerWindow.setFrame(screen.frame, display: true)
            SkyLightOperator.shared.promoteAboveLockScreen(playerWindow)
            playerWindow.makeKeyAndOrderFront(nil)
            playerWindows.append(playerWindow)

            log.info("Windows shown — frame:\(NSStringFromRect(screen.frame), privacy: .public)")
        }
    }

    private func dismiss() {
        stopRaiseLoop()
        guard !backgroundWindows.isEmpty || !playerWindows.isEmpty else { return }
        log.info("dismiss — closing \(self.backgroundWindows.count + self.playerWindows.count) window(s)")
        for window in backgroundWindows {
            window.orderOut(nil)
            window.contentViewController = nil
        }
        for window in playerWindows {
            window.orderOut(nil)
            window.contentViewController = nil
        }
        backgroundWindows.removeAll()
        playerWindows.removeAll()
    }

    /// Re-call `orderFrontRegardless` on every window. macOS's loginwindow
    /// often draws the lock UI ~0.5–1.5s after `screenIsLocked` fires, which
    /// can cover our window. Calling `orderFrontRegardless` again pushes us
    /// back on top.
    private func raiseAllWindows() {
        for window in backgroundWindows {
            window.orderFrontRegardless()
            SkyLightOperator.shared.promoteAboveLockScreen(window)
        }
        for window in playerWindows {
            window.orderFrontRegardless()
            SkyLightOperator.shared.promoteAboveLockScreen(window)
        }
    }

    /// Burst-retry raising the window for ~3s after the lock UI starts to
    /// appear. The lock UI animation can re-cover us multiple times during
    /// the transition; a short repeating timer keeps us in front until the
    /// UI settles.
    private func startRaiseLoop() {
        stopRaiseLoop()
        let start = Date()
        raiseTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                if Date().timeIntervalSince(start) > 3.0 || self.playerWindows.isEmpty {
                    timer.invalidate()
                    self.raiseTimer = nil
                    return
                }
                self.raiseAllWindows()
            }
        }
    }

    private func stopRaiseLoop() {
        raiseTimer?.invalidate()
        raiseTimer = nil
    }

    private func rebuildWindows() {
        dismiss()
        present()
    }

    private func applyScreensIfNeeded() {
        let targetIDs = Set(targetScreens().compactMap(screenID))
        let currentIDs = Set(playerWindows.compactMap { $0.screen.flatMap(screenID) })
        if targetIDs != currentIDs {
            rebuildWindows()
        }
    }

    private func targetScreens() -> [NSScreen] {
        let mode = SettingsStore.shared.string(["lockscreen", "screens"])
        if mode == "all" {
            return NSScreen.screens
        }
        return [NSScreen.main].compactMap { $0 }
    }

    private func screenID(_ screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
