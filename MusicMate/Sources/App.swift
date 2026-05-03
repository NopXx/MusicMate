import SwiftUI
import AppKit

@main
struct MusicMateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?

    private(set) var menuBarController: MenuBarController?
    let playerMonitor = PlayerMonitor()
    let scrobbler = ScrobblerService()
    let nowPlaying = NowPlayingService()
    private(set) var settingsWindow = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        Task { await MigrationService.runIfNeeded() }
        scrobbler.attach(monitor: playerMonitor)
        nowPlaying.attach(monitor: playerMonitor)
        NotificationService.shared.attach(monitor: playerMonitor, scrobbler: scrobbler)
        WebhookDispatcher.shared.attach(monitor: playerMonitor, scrobbler: scrobbler)
        HistoryRecorder.shared.attach(monitor: playerMonitor, scrobbler: scrobbler)
        PendingScrobbleQueue.shared.start()
        menuBarController = MenuBarController(playerMonitor: playerMonitor, scrobbler: scrobbler)
        playerMonitor.start()
    }

    func openSettings() { settingsWindow.show() }
}
