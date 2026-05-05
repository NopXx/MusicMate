import AppKit
import SwiftUI
import Combine
import os

@MainActor
final class LockScreenController: ObservableObject {
    static var shared: LockScreenController?

    @Published private(set) var isShowingTestPresentation: Bool = false

    private let log = Logger(subsystem: "com.nopxx.MusicMate", category: "LockScreen")
    private let playerMonitor: PlayerMonitor
    private let viewModel: LockScreenViewModel
    private var windows: [LockScreenWindow] = []
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
                if (self.isLocked || self.isShowingTestPresentation), snap?.hasTrack != true {
                    self.dismiss()
                } else if self.isLocked || self.isShowingTestPresentation {
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
        if !isShowingTestPresentation { dismiss() }
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
        guard isLocked || isShowingTestPresentation, !windows.isEmpty else { return }
        log.info("Screen parameters changed — rebuilding windows")
        rebuildWindows()
    }

    /// Force-show the lock screen window without waiting for a real lock event.
    /// Used by Settings → Lock Screen → "Show Now" for testing the overlay
    /// without locking the machine.
    func toggleTestPresentation() {
        isShowingTestPresentation.toggle()
        log.info("Test presentation toggled → \(self.isShowingTestPresentation)")
        if isShowingTestPresentation {
            present()
        } else if !isLocked {
            dismiss()
        }
    }

    private func evaluateVisibility() {
        guard isLocked || isShowingTestPresentation else { return }
        let s = SettingsStore.shared
        let enabled = s.bool(["lockscreen", "enabled"])
        let hasTrack = playerMonitor.snapshot?.hasTrack == true
        log.info("evaluateVisibility — enabled:\(enabled) hasTrack:\(hasTrack) windows:\(self.windows.count)")
        guard enabled, hasTrack else {
            dismiss()
            return
        }
        if windows.isEmpty {
            present()
        } else {
            applyScreensIfNeeded()
        }
    }

    private func present() {
        let targets = targetScreens()
        log.info("present — \(targets.count) screen(s)")
        for screen in targets {
            let window = LockScreenWindow(screen: screen)
            let host = NSHostingController(rootView: LockScreenPlayerView(viewModel: viewModel))
            host.view.frame = NSRect(origin: .zero, size: screen.frame.size)
            window.contentViewController = host
            window.setFrame(screen.frame, display: true)
            // Promote into a private SkyLight space pinned above the lock UI
            // BEFORE ordering front — SkyLightWindow does this in the same
            // order so the window's first composite already happens in the
            // promoted space.
            SkyLightOperator.shared.promoteAboveLockScreen(window)
            window.makeKeyAndOrderFront(nil)
            log.info("Window shown — frame:\(NSStringFromRect(screen.frame), privacy: .public) windowNumber:\(window.windowNumber)")
            windows.append(window)
        }
    }

    private func dismiss() {
        stopRaiseLoop()
        guard !windows.isEmpty else { return }
        log.info("dismiss — closing \(self.windows.count) window(s)")
        for window in windows {
            window.orderOut(nil)
            window.contentViewController = nil
        }
        windows.removeAll()
    }

    /// Re-call `orderFrontRegardless` on every window. macOS's loginwindow
    /// often draws the lock UI ~0.5–1.5s after `screenIsLocked` fires, which
    /// can cover our window. Calling `orderFrontRegardless` again pushes us
    /// back on top.
    private func raiseAllWindows() {
        for window in windows {
            window.orderFrontRegardless()
            // Re-assert the SkyLight promotion in case the WindowServer
            // demoted us during the lock-UI animation.
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
                if Date().timeIntervalSince(start) > 3.0 || self.windows.isEmpty {
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
        let currentIDs = Set(windows.compactMap { $0.screen.flatMap(screenID) })
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
