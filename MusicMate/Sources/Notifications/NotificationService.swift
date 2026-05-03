import Foundation
import UserNotifications
import Combine
import AppKit

@MainActor
final class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()

    private let settings = SettingsStore.shared
    private weak var monitor: PlayerMonitor?
    private weak var scrobbler: ScrobblerService?
    private var cancellables = Set<AnyCancellable>()

    private var lastNotifiedTrackKey: String = ""
    private var lastNotifiedScrobbleKey: String = ""
    private var authorized: Bool = false

    func attach(monitor: PlayerMonitor, scrobbler: ScrobblerService) {
        self.monitor = monitor
        self.scrobbler = scrobbler

        UNUserNotificationCenter.current().delegate = self
        requestAuthorizationIfNeeded()

        monitor.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snap in self?.handleSnapshot(snap) }
            .store(in: &cancellables)

        scrobbler.$hasScrobbled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] scrobbled in
                guard scrobbled else { return }
                self?.handleScrobble()
            }
            .store(in: &cancellables)
    }

    private func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] s in
            switch s.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                Task { @MainActor in self?.authorized = true }
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    Task { @MainActor in self?.authorized = granted }
                }
            default:
                Task { @MainActor in self?.authorized = false }
            }
        }
    }

    private func enabled() -> Bool {
        authorized && settings.bool(["notifications", "enabled"])
    }

    private func handleSnapshot(_ snap: NowPlayingSnapshot?) {
        guard enabled(), settings.bool(["notifications", "on_play"]) else { return }
        guard let snap, snap.hasTrack, snap.isPlaying else { return }
        let key = trackKey(snap)
        guard key != lastNotifiedTrackKey else { return }
        lastNotifiedTrackKey = key
        Task { await postNotification(id: "play-\(key)",
                                      title: snap.title,
                                      subtitle: snap.artist,
                                      body: snap.album,
                                      artworkLookup: (snap.title, snap.artist, snap.album)) }
    }

    private func handleScrobble() {
        guard enabled(), settings.bool(["notifications", "on_scrobble"]) else { return }
        guard let snap = monitor?.snapshot, snap.hasTrack else { return }
        let key = trackKey(snap)
        guard key != lastNotifiedScrobbleKey else { return }
        lastNotifiedScrobbleKey = key
        Task { await postNotification(id: "scrobble-\(key)",
                                      title: "Scrobbled to Last.fm",
                                      subtitle: snap.title,
                                      body: snap.artist,
                                      artworkLookup: (snap.title, snap.artist, snap.album)) }
    }

    private func postNotification(id: String, title: String, subtitle: String, body: String,
                                  artworkLookup: (String, String, String)?) async {
        let content = UNMutableNotificationContent()
        content.title = title
        if !subtitle.isEmpty { content.subtitle = subtitle }
        if !body.isEmpty { content.body = body }
        content.sound = nil

        if let (t, a, alb) = artworkLookup,
           let attachment = await artworkAttachment(title: t, artist: a, album: alb) {
            content.attachments = [attachment]
        }

        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        do { try await UNUserNotificationCenter.current().add(request) }
        catch { NSLog("[Notifications] add error: \(error.localizedDescription)") }
    }

    private func artworkAttachment(title: String, artist: String, album: String) async -> UNNotificationAttachment? {
        let result = await ArtworkService.shared.lookup(title: title, artist: artist, album: album)
        guard let urlString = result.artworkURL ?? result.artworkUltraURL,
              let url = URL(string: urlString) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("MusicMateNotificationArtwork", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let fileURL = dir.appendingPathComponent("\(UUID().uuidString).jpg")
            try data.write(to: fileURL, options: .atomic)
            return try UNNotificationAttachment(identifier: "artwork", url: fileURL,
                                                options: [UNNotificationAttachmentOptionsTypeHintKey: "public.jpeg"])
        } catch {
            NSLog("[Notifications] artwork download error: \(error.localizedDescription)")
            return nil
        }
    }

    private func trackKey(_ snap: NowPlayingSnapshot) -> String {
        if !snap.persistentID.isEmpty { return snap.persistentID }
        return "\(snap.title)|\(snap.artist)|\(snap.album)".lowercased()
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }
}
