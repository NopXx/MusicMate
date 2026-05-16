import Foundation
import Combine

@MainActor
final class HistoryRecorder {
    static let shared = HistoryRecorder()

    private weak var monitor: PlayerMonitor?
    private weak var scrobbler: ScrobblerService?
    private var cancellables = Set<AnyCancellable>()

    private var lastTrackKey: String = ""
    private var lastIsPlaying: Bool = false
    private var lastScrobbleKey: String = ""

    func attach(monitor: PlayerMonitor, scrobbler: ScrobblerService) {
        self.monitor = monitor
        self.scrobbler = scrobbler

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

    private func handleSnapshot(_ snap: NowPlayingSnapshot?) {
        guard let snap, snap.hasTrack else {
            if !lastTrackKey.isEmpty {
                Task { await HistoryStore.shared.insertEvent(
                    type: "stopped", title: "", artist: "", album: "",
                    duration: 0, position: 0
                ) }
                lastTrackKey = ""
                lastIsPlaying = false
            }
            return
        }
        let key = trackKey(snap)
        let event: String?
        if key != lastTrackKey {
            event = "play"
        } else if snap.isPlaying != lastIsPlaying {
            event = snap.isPlaying ? "resume" : "pause"
        } else {
            event = nil
        }
        lastTrackKey = key
        lastIsPlaying = snap.isPlaying
        if let event {
            Task { await HistoryStore.shared.insertEvent(
                type: event, title: snap.title, artist: snap.artist, album: snap.album,
                duration: snap.duration, position: snap.position
            ) }
        }
    }

    private func handleScrobble() {
        guard let snap = monitor?.snapshot, snap.hasTrack else { return }
        let key = trackKey(snap)
        guard key != lastScrobbleKey else { return }
        lastScrobbleKey = key
        Task { await HistoryStore.shared.insertEvent(
            type: "scrobble", title: snap.title, artist: snap.artist, album: snap.album,
            duration: snap.duration, position: snap.position
        ) }
    }

    private func trackKey(_ snap: NowPlayingSnapshot) -> String {
        if !snap.persistentID.isEmpty { return snap.persistentID }
        return "\(snap.title)|\(snap.artist)|\(snap.album)".lowercased()
    }
}
