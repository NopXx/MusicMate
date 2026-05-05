import SwiftUI
import AppKit

struct LockScreenPlayerView: View {
    @ObservedObject var viewModel: LockScreenViewModel

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

            // Layout — iOS-style centered:
            //   60% of vertical space → artwork (square, capped by width)
            //   gap
            //   ~30% of vertical space → frosted glass card
            let artworkSize = min(geo.size.height * 0.55, geo.size.width * 0.6)
            let cardWidth = min(640, geo.size.width * 0.55)

            ZStack {
                BackgroundLayer(
                    palette: viewModel.palette,
                    artworkURL: staticURL,
                    blurAmount: CGFloat(viewModel.backgroundBlur)
                )

                if let snap, snap.hasTrack {
                    VStack(spacing: 36) {
                        ArtworkLayer(
                            staticURL: staticURL,
                            animatedURL: animURL,
                            size: artworkSize
                        )

                        NowPlayingCard(
                            snap: snap,
                            showAlbum: viewModel.showAlbum,
                            showProgress: viewModel.showProgress,
                            width: cardWidth
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(CGFloat(viewModel.padding))
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
    let blurAmount: CGFloat

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

            if let url = artworkURL, blurAmount > 0 {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .blur(radius: max(0, min(80, blurAmount)))
                            .opacity(0.55)
                    default:
                        Color.clear
                    }
                }
            }

            Color.black.opacity(0.30)
        }
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

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Text(snap.title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(snap.artist)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if showAlbum && !snap.album.isEmpty {
                    Text(snap.album)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.top, 1)
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
