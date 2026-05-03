import Foundation
import AppKit

enum MusicAppController {
    private static let app: MusicApplication? = {
        guard let raw = SBApplication(bundleIdentifier: "com.apple.Music") else { return nil }
        return unsafeBitCast(raw, to: MusicApplication.self)
    }()

    private static let queue = DispatchQueue(label: "com.nopxx.musicmate.scriptingbridge", qos: .userInitiated)

    @MainActor static func play()      { run { $0.playOnce(false) } }
    @MainActor static func pause()     { run { $0.pause() } }
    @MainActor static func playPause() { run { $0.playpause() } }
    @MainActor static func next()      { run { $0.nextTrack() } }
    @MainActor static func previous()  { run { $0.previousTrack() } }

    @MainActor static func setPlayerPosition(_ seconds: Double) {
        run { $0.playerPosition = seconds }
    }

    private static func run(_ block: @escaping (MusicApplication) -> Void) {
        guard isMusicRunning(), let app else { return }
        queue.async { block(app) }
    }

    private static func isMusicRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.Music" }
    }
}

struct NowPlayingSnapshot {
    var state: String
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var position: Double
    var persistentID: String

    var isPlaying: Bool { state.lowercased() == "playing" }
    var hasTrack: Bool { !title.isEmpty }
}
