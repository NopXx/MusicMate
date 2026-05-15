import Foundation

@MainActor
final class PendingScrobbleQueue {
    static let shared = PendingScrobbleQueue()

    private let settings = SettingsStore.shared
    private var retryTimer: Timer?
    private var draining: Bool = false

    func start() {
        Task { await drain() }
        retryTimer?.invalidate()
        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.drain() }
        }
        RunLoop.main.add(timer, forMode: .common)
        retryTimer = timer
    }

    func drain() async {
        guard !draining else { return }
        draining = true
        defer { draining = false }

        guard credentialsConfigured() else { return }
        let pending = await HistoryStore.shared.loadPendingScrobbles(limit: 50)
        guard !pending.isEmpty else { return }

        let lf = settings.value(["lastfm"], [String: Any].self) ?? [:]
        let key = LastFMSecrets.resolveKey(lf["api_key"] as? String)
        let secret = LastFMSecrets.resolveSecret(lf["api_secret"] as? String)
        let session = (lf["session_key"] as? String) ?? ""

        for item in pending {
            var params: [String: String] = [
                "api_key": key,
                "sk": session,
                "track": item.track,
                "artist": item.artist,
                "album": item.album,
                "duration": String(Int(item.duration)),
                "timestamp": String(Int(item.timestamp.timeIntervalSince1970)),
            ]
            // strip empty fields just in case
            if params["album"]?.isEmpty == true { params.removeValue(forKey: "album") }
            let res = await LastFMClient.call(method: "track.scrobble",
                                              params: params, secret: secret, post: true)
            if res["scrobbles"] != nil {
                await HistoryStore.shared.deletePendingScrobble(id: item.id)
            } else {
                let msg = (res["message"] as? String) ?? "unknown"
                await HistoryStore.shared.markPendingFailure(id: item.id, error: msg)
                NSLog("[PendingScrobbleQueue] retry failed for #\(item.id): \(msg)")
            }
        }
    }

    private func credentialsConfigured() -> Bool {
        let lf = settings.value(["lastfm"], [String: Any].self) ?? [:]
        let enabled = (lf["enabled"] as? Bool) ?? false
        let key = LastFMSecrets.resolveKey(lf["api_key"] as? String)
        let secret = LastFMSecrets.resolveSecret(lf["api_secret"] as? String)
        let session = (lf["session_key"] as? String) ?? ""
        return enabled && !key.isEmpty && !secret.isEmpty && !session.isEmpty
    }
}
