import SwiftUI
import AppKit

struct LockScreenPlayerView: View {
    @ObservedObject var viewModel: LockScreenViewModel
    @State private var isLargeArtwork: Bool = false

    var body: some View {
        GeometryReader { geo in
            let snap = viewModel.snapshot
            let artworkURLString = viewModel.artwork.artworkUltraURL
                ?? viewModel.artwork.artworkURL
            let animationURLString = viewModel.animatedArtwork
                ? (viewModel.artwork.animationURL ?? viewModel.artwork.animationTallURL)
                : nil

            let staticURL = artworkURLString.flatMap(URL.init(string:))
            let animURL = animationURLString.flatMap(URL.init(string:))

            let largeSize = min(geo.size.height * 0.50, geo.size.width * 0.55)
            let cardWidth = min(680, geo.size.width * 0.55)

            ZStack {
                BackgroundLayer(
                    palette: viewModel.palette,
                    artworkURL: staticURL
                )

                if let snap, snap.hasTrack {
                    VStack(spacing: 28) {
                        if isLargeArtwork {
                            ArtworkLayer(
                                staticURL: staticURL,
                                animatedURL: animURL,
                                size: largeSize
                            )
                            .onTapGesture {
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                                    isLargeArtwork = false
                                }
                            }
                            .transition(.scale(scale: 0.92).combined(with: .opacity))
                        }

                        NowPlayingCard(
                            snap: snap,
                            showAlbum: viewModel.showAlbum,
                            showProgress: viewModel.showProgress,
                            width: cardWidth,
                            staticURL: staticURL,
                            animatedURL: animURL,
                            animatedArtwork: viewModel.animatedArtwork,
                            showInlineArtwork: !isLargeArtwork,
                            onArtworkTap: {
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                                    isLargeArtwork = true
                                }
                            }
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, CGFloat(viewModel.padding) + 40)
                    .padding(.horizontal, CGFloat(viewModel.padding))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }
}

private struct BackgroundLayer: View {
    let palette: ArtworkPalette
    let artworkURL: URL?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(palette.gradientStart),
                    Color(palette.gradientMid),
                    Color(palette.gradientEnd),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let url = artworkURL {
                AsyncImage(url: url) { phase in
                    if let img = phase.image {
                        img.resizable()
                            .aspectRatio(contentMode: .fill)
                            .blur(radius: 60)
                            .saturation(2.4)
                            .brightness(-0.15)
                            .opacity(0.78)
                    } else {
                        Color.clear
                    }
                }
                .clipped()
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.45)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .clear, location: 0.18),
                    .init(color: .black, location: 0.32),
                    .init(color: .black, location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

private struct ArtworkLayer: View {
    let staticURL: URL?
    let animatedURL: URL?
    let size: CGFloat

    var body: some View {
        ZStack {
            if let staticURL {
                AsyncImage(url: staticURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Color.white.opacity(0.05)
                    }
                }
            } else {
                Color.white.opacity(0.05)
            }

            if let animatedURL {
                AnimatedArtworkView(url: animatedURL, contentMode: .fill, cornerRadius: 28)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.55), radius: 36, x: 0, y: 22)
    }
}

private struct NowPlayingCard: View {
    let snap: NowPlayingSnapshot
    let showAlbum: Bool
    let showProgress: Bool
    let width: CGFloat
    let staticURL: URL?
    let animatedURL: URL?
    let animatedArtwork: Bool
    let showInlineArtwork: Bool
    let onArtworkTap: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 16) {
                if showInlineArtwork {
                    artworkThumbnail
                        .onTapGesture { onArtworkTap() }
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }

                VStack(alignment: showInlineArtwork ? .leading : .center, spacing: 4) {
                    Text(snap.title)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: showInlineArtwork ? .leading : .center)

                    Text(snap.artist)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: showInlineArtwork ? .leading : .center)

                    if showAlbum && !snap.album.isEmpty {
                        Text(snap.album)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.top, 1)
                            .frame(maxWidth: .infinity, alignment: showInlineArtwork ? .leading : .center)
                    }
                }
            }

            if showProgress && snap.duration > 0 {
                ProgressBar(elapsed: snap.position, duration: snap.duration)
            }

            HStack(spacing: 56) {
                ControlGlyph(systemName: "backward.fill", size: 26)
                ControlGlyph(systemName: snap.isPlaying ? "pause.fill" : "play.fill", size: 34)
                ControlGlyph(systemName: "forward.fill", size: 26)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 18)
    }

    @ViewBuilder
    private var artworkThumbnail: some View {
        ZStack {
            if let staticURL {
                AsyncImage(url: staticURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Color.white.opacity(0.08)
                    }
                }
            } else {
                Color.white.opacity(0.08)
            }

            if animatedArtwork, let animatedURL {
                AnimatedArtworkView(url: animatedURL, contentMode: .fill, cornerRadius: 12)
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                    Capsule()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 4)

            HStack {
                Text(format(elapsed))
                Spacer()
                Text("-" + format(max(0, duration - elapsed)))
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.55))
            .monospacedDigit()
        }
    }

    private func format(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
