import SwiftUI
import Combine
import AppKit

@MainActor
final class LockScreenViewModel: ObservableObject {
    @Published var snapshot: NowPlayingSnapshot?
    @Published var artwork: ArtworkResult = ArtworkResult()
    @Published var artworkImage: NSImage?
    @Published var palette: ArtworkPalette = .default
    @Published var isLargeArtwork: Bool = false

    @Published var showAlbum: Bool = true
    @Published var showProgress: Bool = true
    @Published var animatedArtwork: Bool = true
    @Published var backgroundBlur: Int = 60
    @Published var padding: Int = 32

    private weak var monitor: PlayerMonitor?
    private var cancellables = Set<AnyCancellable>()
    private var lastArtworkKey: String = ""
    private var lastPaletteURL: String = ""

    init(monitor: PlayerMonitor) {
        self.monitor = monitor
        readSettings()

        SettingsStore.shared.$data
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.readSettings() }
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
    }

    private func readSettings() {
        let s = SettingsStore.shared
        showAlbum = s.bool(["lockscreen", "show_album"])
        showProgress = s.bool(["lockscreen", "show_progress"])
        animatedArtwork = s.bool(["lockscreen", "animated_artwork"])
        let blur = s.int(["lockscreen", "background_blur"])
        backgroundBlur = blur > 0 ? blur : 60
        let pad = s.int(["lockscreen", "padding"])
        padding = pad > 0 ? pad : 32
    }

    private func handleTrackUpdate(_ snap: NowPlayingSnapshot?) {
        guard let snap, snap.hasTrack else {
            artwork = ArtworkResult()
            artworkImage = nil
            palette = .default
            lastArtworkKey = ""
            lastPaletteURL = ""
            return
        }
        let key = snap.persistentID.isEmpty
            ? "\(snap.title)|\(snap.artist)|\(snap.album)".lowercased()
            : snap.persistentID
        guard key != lastArtworkKey else { return }
        lastArtworkKey = key

        let title = snap.title, artist = snap.artist, album = snap.album
        Task { [weak self] in
            let result = await ArtworkService.shared.lookup(title: title, artist: artist, album: album)
            let imgURLString = result.artworkUltraURL ?? result.artworkURL
            var downloadedImage: NSImage?
            if let imgURLString, let imgURL = URL(string: imgURLString) {
                if let (data, _) = try? await URLSession.shared.data(from: imgURL) {
                    downloadedImage = NSImage(data: data)
                }
            }
            await MainActor.run {
                guard let self, self.lastArtworkKey == key else { return }
                self.artwork = result
                self.artworkImage = downloadedImage
                if let url = result.artworkURL, !url.isEmpty, url != self.lastPaletteURL {
                    self.lastPaletteURL = url
                    Task { [weak self] in
                        let palette = await ColorExtractor.shared.palette(for: url)
                        await MainActor.run {
                            guard let self, self.lastPaletteURL == url else { return }
                            self.palette = palette
                        }
                    }
                }
            }
        }
    }
}
