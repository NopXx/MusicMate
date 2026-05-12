import SwiftUI
import Combine
import AppKit

@MainActor
final class MiniPlayerViewModel: ObservableObject {
    @Published var snapshot: NowPlayingSnapshot?
    @Published var artwork: ArtworkResult = ArtworkResult()
    @Published var palette: ArtworkPalette = .default
    @Published var hasScrobbled: Bool = false
    @Published var scrobblePercent: Double = 0
    @Published var notificationsEnabled: Bool = true
    @Published var miniplayerAnimation: String = "full"
    @Published var miniplayerMeta: String = "artist_album"
    @Published var artworkStyle: String = "classic"
    @Published var showFullscreenAnimation: Bool = false
    @Published var animationFullscreenEnabled: Bool = false

    private weak var monitor: PlayerMonitor?
    private weak var scrobbler: ScrobblerService?
    private var cancellables = Set<AnyCancellable>()
    private var lastArtworkKey: String = ""
    private var lastPaletteURL: String = ""

    init(monitor: PlayerMonitor, scrobbler: ScrobblerService) {
        self.monitor = monitor
        self.scrobbler = scrobbler
        self.notificationsEnabled = SettingsStore.shared.bool(["notifications", "enabled"])
        let anim = SettingsStore.shared.string(["miniplayer", "animation"])
        self.miniplayerAnimation = anim.isEmpty ? "full" : anim
        let meta = SettingsStore.shared.string(["miniplayer", "meta_display"])
        self.miniplayerMeta = meta.isEmpty ? "artist_album" : meta
        let style = SettingsStore.shared.string(["miniplayer", "artwork_style"])
        self.artworkStyle = style.isEmpty ? "classic" : style
        self.animationFullscreenEnabled = SettingsStore.shared.bool(["miniplayer", "animation_fullscreen"])

        SettingsStore.shared.$data
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.notificationsEnabled = SettingsStore.shared.bool(["notifications", "enabled"])
                let a = SettingsStore.shared.string(["miniplayer", "animation"])
                self.miniplayerAnimation = a.isEmpty ? "full" : a
                let m = SettingsStore.shared.string(["miniplayer", "meta_display"])
                self.miniplayerMeta = m.isEmpty ? "artist_album" : m
                let st = SettingsStore.shared.string(["miniplayer", "artwork_style"])
                self.artworkStyle = st.isEmpty ? "classic" : st
                self.animationFullscreenEnabled = SettingsStore.shared.bool(["miniplayer", "animation_fullscreen"])
            }
            .store(in: &cancellables)

        monitor.$snapshot
            .combineLatest(EditHistoryService.shared.$rules)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rawSnap, _ in
                guard let self else { return }
                let edited = rawSnap.map { EditHistoryService.shared.apply($0) }
                self.snapshot = edited
                self.handleTrackUpdate(edited)
                WidgetDataManager.shared.update(
                    snapshot: edited,
                    artwork: edited != nil ? self.artwork : nil,
                    palette: edited != nil ? self.palette : nil
                )
            }
            .store(in: &cancellables)

        scrobbler.$hasScrobbled
            .receive(on: DispatchQueue.main)
            .assign(to: \.hasScrobbled, on: self)
            .store(in: &cancellables)

        scrobbler.$scrobblePercent
            .receive(on: DispatchQueue.main)
            .assign(to: \.scrobblePercent, on: self)
            .store(in: &cancellables)
    }

    private func handleTrackUpdate(_ snap: NowPlayingSnapshot?) {
        guard let snap, snap.hasTrack else {
            artwork = ArtworkResult()
            palette = .default
            lastArtworkKey = ""
            lastPaletteURL = ""
            WidgetDataManager.shared.update(snapshot: nil, artwork: nil, palette: nil)
            return
        }
        let key = snap.persistentID.isEmpty
            ? "\(snap.title)|\(snap.artist)|\(snap.album)".lowercased()
            : snap.persistentID
        guard key != lastArtworkKey else {
            WidgetDataManager.shared.update(snapshot: snap, artwork: artwork, palette: palette)
            return
        }
        lastArtworkKey = key
        // Do not clear artwork and palette here so the UI smoothly holds the
        // previous artwork until the new one is fetched, avoiding rapid
        // SwiftUI transitions that break NSViewRepresentables.

        let title = snap.title, artist = snap.artist, album = snap.album
        Task { [weak self] in
            let result = await ArtworkService.shared.lookup(title: title, artist: artist, album: album)
            await MainActor.run {
                guard let self else { return }
                guard self.lastArtworkKey == key else { return }
                self.artwork = result
                WidgetDataManager.shared.update(
                    snapshot: self.snapshot,
                    artwork: result,
                    palette: self.palette
                )
                if let url = result.artworkURL, !url.isEmpty, url != self.lastPaletteURL {
                    self.lastPaletteURL = url
                    Task { [weak self] in
                        let palette = await ColorExtractor.shared.palette(for: url)
                        await MainActor.run {
                            guard let self, self.lastPaletteURL == url else { return }
                            self.palette = palette
                            WidgetDataManager.shared.update(
                                snapshot: self.snapshot,
                                artwork: self.artwork,
                                palette: palette
                            )
                        }
                    }
                }
            }
        }
    }

    func playPause() {
        MusicAppController.playPause()
        monitor?.refresh()
    }

    func next() {
        MusicAppController.next()
        monitor?.refresh()
    }

    func previous() {
        MusicAppController.previous()
        monitor?.refresh()
    }

    /// Save an edit rule for the currently playing track. Match keys use the
    /// raw snapshot from the monitor (before `apply()`), so editing is
    /// idempotent even if a rule already transforms this track.
    func saveEditForCurrentTrack(artist: String, track: String, album: String) {
        guard let raw = monitor?.snapshot, raw.hasTrack else { return }
        let trimArtist = artist.trimmingCharacters(in: .whitespaces)
        let trimTrack  = track.trimmingCharacters(in: .whitespaces)
        let trimAlbum  = album.trimmingCharacters(in: .whitespaces)
        Task {
            await EditHistoryService.shared.add(
                artistMatch: raw.artist,
                trackMatch: raw.title,
                albumMatch: "",
                artistTo: trimArtist == raw.artist ? "" : trimArtist,
                trackTo:  trimTrack  == raw.title  ? "" : trimTrack,
                albumTo:  trimAlbum  == raw.album  ? "" : trimAlbum
            )
        }
    }

    func toggleNotifications() {
        notificationsEnabled.toggle()
        SettingsStore.shared.merge(["notifications": ["enabled": notificationsEnabled]])
    }
}
