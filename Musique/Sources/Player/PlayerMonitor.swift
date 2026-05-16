import Foundation
import Combine
import AppKit

@MainActor
final class PlayerMonitor: ObservableObject {
    @Published private(set) var snapshot: NowPlayingSnapshot?

    private let musicBundleID = "com.apple.Music"
    private var musicApp: MusicApplication?

    private var basePosition: Double = 0
    private var basePositionAt: Date = .distantPast
    private var tickTimer: Timer?
    private var observerToken: NSObjectProtocol?

    init() {
        if let raw = SBApplication(bundleIdentifier: musicBundleID) {
            NSLog("[PlayerMonitor] SBApplication class=\(type(of: raw))")
            self.musicApp = unsafeBitCast(raw, to: MusicApplication.self)
            NSLog("[PlayerMonitor] MusicApplication ready (via unsafeBitCast)")
        } else {
            NSLog("[PlayerMonitor] SBApplication(bundleIdentifier:) returned nil")
            self.musicApp = nil
        }
    }

    func start() {
        let center = DistributedNotificationCenter.default()
        observerToken = center.addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            NSLog("[PlayerMonitor] notification: \(note.userInfo ?? [:])")
            Task { @MainActor in self?.refresh() }
        }
        refresh()
        startTickTimer()
    }

    func refresh() {
        guard isMusicRunning() else {
            NSLog("[PlayerMonitor] refresh: Music.app not running")
            snapshot = nil
            return
        }
        guard let app = musicApp else {
            NSLog("[PlayerMonitor] refresh: musicApp nil")
            snapshot = nil
            return
        }

        let rawState = app.playerState
        let stateStr: String
        switch rawState {
        case MusicEPlSPlaying, MusicEPlSFastForwarding, MusicEPlSRewinding: stateStr = "playing"
        case MusicEPlSPaused: stateStr = "paused"
        case MusicEPlSStopped: stateStr = "stopped"
        default: stateStr = "stopped"
        }
        NSLog("[PlayerMonitor] state raw=\(rawState) -> \(stateStr)")

        guard stateStr != "stopped" else {
            snapshot = nil
            return
        }
        guard let track = app.currentTrack else {
            NSLog("[PlayerMonitor] currentTrack is nil")
            snapshot = nil
            return
        }

        let pos = app.playerPosition
        let snap = NowPlayingSnapshot(
            state: stateStr,
            title: track.name ?? "",
            artist: track.artist ?? "",
            album: track.album ?? "",
            duration: track.duration,
            position: pos,
            persistentID: track.persistentID ?? ""
        )
        NSLog("[PlayerMonitor] snap title=\(snap.title) artist=\(snap.artist) dur=\(snap.duration) pos=\(snap.position)")
        basePosition = snap.position
        basePositionAt = Date()
        snapshot = snap
    }

    private func isMusicRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == musicBundleID }
    }

    private func startTickTimer() {
        tickTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func tick() {
        guard var snap = snapshot, snap.isPlaying else { return }
        let elapsed = Date().timeIntervalSince(basePositionAt)
        let newPos = basePosition + elapsed
        if snap.duration > 0 && newPos > snap.duration {
            snap.position = snap.duration
        } else {
            snap.position = newPos
        }
        snapshot = snap
    }

    deinit {
        if let token = observerToken {
            DistributedNotificationCenter.default().removeObserver(token)
        }
        tickTimer?.invalidate()
    }
}
