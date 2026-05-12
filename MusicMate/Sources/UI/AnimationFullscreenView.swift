import SwiftUI
import AppKit

struct AnimationFullscreenView: View {
    @ObservedObject var viewModel: MiniPlayerViewModel
    let onDismiss: () -> Void

    private var animationURL: URL? {
        let s = viewModel.artwork.animationSquareUltraURL ?? viewModel.artwork.animationURL
        guard let s, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private var artworkURL: URL? {
        guard let s = viewModel.artwork.artworkURL, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                backgroundLayer(width: geo.size.width, height: geo.size.height)

                fullscreenAnimationLayer(width: geo.size.width, height: geo.size.height)

                VStack {
                    Spacer()

                    trackInfo

                    Spacer()

                    Text("กดเพื่อปิด")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.bottom, 36)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .onExitCommand { onDismiss() }
        .onChange(of: viewModel.snapshot?.hasTrack ?? false) { _, hasTrack in
            if !hasTrack { onDismiss() }
        }
    }

    @ViewBuilder
    private func backgroundLayer(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(viewModel.palette.gradientStart),
                    Color(viewModel.palette.gradientMid),
                    Color(viewModel.palette.gradientEnd),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let url = artworkURL {
                AsyncImage(url: url) { phase in
                    if let img = phase.image {
                        img.resizable()
                            .aspectRatio(contentMode: .fill)
                            .blur(radius: 80)
                            .saturation(2.0)
                            .brightness(-0.15)
                            .opacity(0.5)
                    }
                }
                .frame(width: width, height: height)
                .clipped()
            }

            Color.black.opacity(0.35)
        }
    }

    @ViewBuilder
    private func fullscreenAnimationLayer(width: CGFloat, height: CGFloat) -> some View {
        let size = min(width, height) * 0.5
        ZStack {
            if let url = animationURL {
                AnimatedArtworkView(url: url, contentMode: .fit, cornerRadius: 0)
                    .frame(width: size, height: size)
            } else if let url = artworkURL {
                AsyncImage(url: url) { phase in
                    if let img = phase.image {
                        img.resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        LinearGradient(
                            colors: [
                                Color(viewModel.palette.gradientStart),
                                Color(viewModel.palette.gradientMid),
                                Color(viewModel.palette.gradientEnd),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
            } else {
                LinearGradient(
                    colors: [
                        Color(viewModel.palette.gradientStart),
                        Color(viewModel.palette.gradientMid),
                        Color(viewModel.palette.gradientEnd),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            LinearGradient(
                colors: [
                    .black.opacity(0.15),
                    .black.opacity(0.0),
                    .black.opacity(0.55),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(width: width, height: height)
        .clipped()
    }

    @ViewBuilder
    private var trackInfo: some View {
        VStack(spacing: 6) {
            Text(viewModel.snapshot?.title ?? "")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(viewModel.snapshot?.artist ?? "")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
    }
}
