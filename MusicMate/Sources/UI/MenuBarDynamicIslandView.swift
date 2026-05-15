import SwiftUI
import AppKit
import Combine

@MainActor
final class MenuBarDynamicIslandModel: ObservableObject {
    @Published var snapshot: NowPlayingSnapshot?
    @Published var artwork: NSImage?
    @Published var accent: NSColor?

    private let monitor: PlayerMonitor
    private var cancellables = Set<AnyCancellable>()
    private var artworkTask: Task<Void, Never>?
    private var paletteTask: Task<Void, Never>?
    private var lastArtworkKey: String = ""

    init(monitor: PlayerMonitor) {
        self.monitor = monitor
        monitor.$snapshot
            .combineLatest(EditHistoryService.shared.$rules)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] raw, _ in
                guard let self else { return }
                let edited = raw.map { EditHistoryService.shared.apply($0) }
                self.snapshot = edited
                self.refreshArtwork(for: edited)
            }
            .store(in: &cancellables)
    }

    private func refreshArtwork(for snap: NowPlayingSnapshot?) {
        guard let snap, snap.hasTrack else {
            artworkTask?.cancel()
            paletteTask?.cancel()
            artwork = nil
            accent = nil
            lastArtworkKey = ""
            return
        }
        let key = "\(snap.title)|\(snap.artist)|\(snap.album)"
        if key == lastArtworkKey { return }
        lastArtworkKey = key
        artworkTask?.cancel()
        paletteTask?.cancel()
        let title = snap.title
        let artist = snap.artist
        let album = snap.album
        artworkTask = Task { [weak self] in
            let result = await ArtworkService.shared.lookup(title: title, artist: artist, album: album)
            guard !Task.isCancelled else { return }
            guard let urlString = result.artworkURL, let url = URL(string: urlString) else {
                await MainActor.run {
                    self?.artwork = nil
                    self?.accent = nil
                }
                return
            }
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let image = NSImage(data: data) {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if self?.lastArtworkKey == key {
                        self?.artwork = image
                    }
                }
            }
            let palette = await ColorExtractor.shared.palette(for: urlString)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if self?.lastArtworkKey == key {
                    self?.accent = palette.accent
                }
            }
        }
    }
}

struct MenuBarDynamicIslandView: View {
    @ObservedObject var model: MenuBarDynamicIslandModel
    @ObservedObject var settings = SettingsStore.shared
    @ObservedObject var audio = MusicAudioLevelMonitor.shared

    private var showState: Bool { settings.bool(["menubar", "show_state"]) }

    var body: some View {
        HStack(spacing: 14) {
            artworkView
            if let snap = model.snapshot, snap.hasTrack {
                if showState {
                    Image(systemName: snap.isPlaying ? "play.fill" : "pause.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.primary)
                }
                WaveBarsView(bands: audio.bands, isPlaying: snap.isPlaying)
            } else {
                Text("MusicMate")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(height: 22)
        .background(pillBackground)
        .padding(.horizontal, 3)
        .onAppear { MusicAudioLevelMonitor.shared.start() }
    }

    @ViewBuilder
    private var pillBackground: some View {
        let accent = model.accent.map { Color(nsColor: $0) } ?? Color.primary
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(accent.opacity(0.22))
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(accent.opacity(0.55), lineWidth: 0.8)
        }
    }

    @ViewBuilder
    private var artworkView: some View {
        if let image = model.artwork {
            Image(nsImage: image)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fill)
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .fill(Color.secondary.opacity(0.25))
                .frame(width: 18, height: 18)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                )
        }
    }
}

private struct WaveBarsView: View {
    let bands: [Float]
    let isPlaying: Bool
    private let count = 7

    var body: some View {
        HStack(alignment: .center, spacing: 1.5) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(Color.primary)
                    .frame(width: 2, height: barHeight(i))
                    .animation(.easeOut(duration: 0.05), value: barHeight(i))
            }
        }
        .frame(height: 11)
    }

    private func barHeight(_ i: Int) -> CGFloat {
        let base: CGFloat = 2.5
        guard isPlaying, i < bands.count else { return base }
        let v = CGFloat(min(1, max(0, bands[i])))
        return base + v * 7.5
    }
}
