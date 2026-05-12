import SwiftUI
import AppKit

struct LockScreenPlayerView: View {
    @ObservedObject var viewModel: LockScreenViewModel

    var body: some View {
        GeometryReader { geo in
            let snap = viewModel.snapshot
            let animationURLString = viewModel.animatedArtwork
                ? (viewModel.artwork.animationURL ?? viewModel.artwork.animationTallURL)
                : nil
            let animURL = animationURLString.flatMap(URL.init(string:))

            let largeSize = min(geo.size.height * 0.40, geo.size.width * 0.38)
            let cardWidth = min(350, geo.size.width * 0.35)

            ZStack {
                if viewModel.isLargeArtwork && !viewModel.fullscreenAnimationActive {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                                viewModel.isLargeArtwork = false
                            }
                        }
                }

                if viewModel.isLargeArtwork && !viewModel.fullscreenAnimationActive {
                    VStack {
                        LiquidGlassClockView(glassVariant: viewModel.clockGlassStyle)
                            .padding(.top, 110)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                }

                if let snap, snap.hasTrack {
                    VStack(spacing: 20) {
                        if viewModel.isLargeArtwork && !viewModel.fullscreenAnimationActive && animURL == nil {
                            ArtworkLayer(
                                artworkImage: viewModel.artworkImage,
                                animatedURL: animURL,
                                size: largeSize
                            )
                            .onTapGesture {
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                                    viewModel.isLargeArtwork = false
                                }
                            }
                            .transition(.scale(scale: 0.92).combined(with: .opacity))
                        }

                        NowPlayingCard(
                            snap: snap,
                            showAlbum: viewModel.showAlbum,
                            showProgress: viewModel.showProgress,
                            width: cardWidth,
                            artworkImage: viewModel.artworkImage,
                            animatedURL: animURL,
                            animatedArtwork: viewModel.animatedArtwork,
                            showInlineArtwork: !viewModel.isLargeArtwork && !viewModel.fullscreenAnimationActive,
                            onArtworkTap: {
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                                    viewModel.isLargeArtwork = true
                                }
                            }
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, CGFloat(viewModel.padding) + 160)
                    .padding(.horizontal, CGFloat(viewModel.padding))
                }
            }
        }
        .ignoresSafeArea()
    }
}

private struct LiquidGlassClockView: View {
    var glassVariant: GlassTextVariant = .regular

    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f.string(from: now)
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: now)
    }

    var body: some View {
        VStack(spacing: 8) {
            GlassEffectText(
                text: dateString,
                font: NSFont.systemFont(ofSize: 32, weight: .semibold),
                variant: glassVariant
            )
            GlassEffectText(
                text: timeString,
                font: NSFont.systemFont(ofSize: 150, weight: .bold),
                variant: glassVariant
            )
        }
        .onReceive(timer) { now = $0 }
    }
}

private struct ArtworkLayer: View {
    let artworkImage: NSImage?
    let animatedURL: URL?
    let size: CGFloat

    var body: some View {
        ZStack {
            if let animatedURL {
                AnimatedArtworkView(url: animatedURL, staticImage: artworkImage, contentMode: .fill, cornerRadius: 20)
            } else if let nsImage = artworkImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.white.opacity(0.05)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.55), radius: 36, x: 0, y: 22)
    }
}

private struct NowPlayingCard: View {
    let snap: NowPlayingSnapshot
    let showAlbum: Bool
    let showProgress: Bool
    let width: CGFloat
    let artworkImage: NSImage?
    let animatedURL: URL?
    let animatedArtwork: Bool
    let showInlineArtwork: Bool
    let onArtworkTap: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                if showInlineArtwork {
                    artworkThumbnail
                        .onTapGesture { onArtworkTap() }
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }

                VStack(alignment: showInlineArtwork ? .leading : .center, spacing: 2) {
                    Text(snap.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: showInlineArtwork ? .leading : .center)

                    Text(snap.artist)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: showInlineArtwork ? .leading : .center)
                }

                if snap.isPlaying {
                    EqualizerIcon()
                }
            }

            if showProgress && snap.duration > 0 {
                ProgressBar(elapsed: snap.position, duration: snap.duration)
            }

            HStack(spacing: 44) {
                ControlGlyph(systemName: "backward.fill", size: 22)
                    .onTapGesture { MusicAppController.previous() }
                ControlGlyph(systemName: snap.isPlaying ? "pause.fill" : "play.fill", size: 28)
                    .onTapGesture { MusicAppController.playPause() }
                ControlGlyph(systemName: "forward.fill", size: 22)
                    .onTapGesture { MusicAppController.next() }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.clear)
                .glassEffect(
                    Glass.clear.tint(.white.opacity(0.05)),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .opacity(0.6)
        )
    }

    @ViewBuilder
    private var artworkThumbnail: some View {
        ZStack {
            if animatedArtwork, let animatedURL {
                AnimatedArtworkView(url: animatedURL, staticImage: artworkImage, contentMode: .fill, cornerRadius: 8)
            } else if let nsImage = artworkImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.white.opacity(0.08)
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct EqualizerIcon: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 3, height: animate ? barHeight(i) : 4)
            }
        }
        .frame(width: 16, height: 16)
        .onAppear { animate = true }
        .animation(
            .easeInOut(duration: 0.5)
                .repeatForever(autoreverses: true)
                .delay(Double.random(in: 0...0.2)),
            value: animate
        )
    }

    private func barHeight(_ index: Int) -> CGFloat {
        switch index {
        case 0: return 10
        case 1: return 14
        default: return 8
        }
    }
}

private struct ControlGlyph: View {
    let systemName: String
    let size: CGFloat

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size * 1.6, height: size * 1.6)
    }
}

private struct ProgressBar: View {
    let elapsed: Double
    let duration: Double

    var body: some View {
        let progress = duration > 0 ? min(1, max(0, elapsed / duration)) : 0
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                    Capsule()
                        .fill(Color.white.opacity(0.75))
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 3)

            HStack {
                Text(format(elapsed))
                Spacer()
                Text(format(duration))
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.45))
            .monospacedDigit()
        }
    }

    private func format(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
