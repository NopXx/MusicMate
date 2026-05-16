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
        // Skip transitional snapshots where Music.app hasn't fully settled
        // (artist briefly empty during a track switch).
        guard !snap.artist.isEmpty else { return }
        let key = "\(snap.persistentID)|\(snap.title)|\(snap.artist)|\(snap.album)".lowercased()
        guard key != lastArtworkKey else {
            WidgetDataManager.shared.update(snapshot: snap, artwork: artwork, palette: palette)
            return
        }
        lastArtworkKey = key
        // Do not clear artwork and palette here so the UI smoothly holds the
        // previous artwork until the new one is fetched, avoiding rapid
        // SwiftUI transitions that break NSViewRepresentables.

        // Tell the widget immediately that the track changed, with nil artwork.
        // Otherwise it would render the new title/artist with the previous
        // track's artwork until the async lookup below completes.
        WidgetDataManager.shared.update(snapshot: snap, artwork: nil, palette: nil)

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
        scheduleFallbackRefresh()
    }

    func previous() {
        MusicAppController.previous()
        scheduleFallbackRefresh()
    }

    /// Music.app posts `com.apple.Music.playerInfo` after the track actually
    /// advances; PlayerMonitor observes that and refreshes itself. We schedule
    /// a delayed refresh purely as a safety net in case the notification is
    /// missed, well after Music.app has had time to switch tracks.
    private func scheduleFallbackRefresh() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.monitor?.refresh()
        }
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
        let target = !notificationsEnabled
        if target {
            Task { @MainActor in
                let granted = await NotificationService.shared.ensureAuthorized()
                guard granted else {
                    notificationsEnabled = false
                    SettingsStore.shared.merge(["notifications": ["enabled": false]])
                    return
                }
                notificationsEnabled = true
                SettingsStore.shared.merge(["notifications": ["enabled": true]])
            }
        } else {
            notificationsEnabled = false
            SettingsStore.shared.merge(["notifications": ["enabled": false]])
        }
    }
}
