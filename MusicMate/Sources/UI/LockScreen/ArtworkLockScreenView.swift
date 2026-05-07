import SwiftUI
import AppKit

struct ArtworkLockScreenView: View {
    @ObservedObject var viewModel: LockScreenViewModel

    var body: some View {
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

            if let nsImage = viewModel.artworkImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 60)
                    .saturation(2.4)
                    .brightness(-0.15)
                    .opacity(0.78)
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.45)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .opacity(viewModel.isLargeArtwork ? 1 : 0)
        .animation(.easeInOut(duration: 0.4), value: viewModel.isLargeArtwork)
        .ignoresSafeArea()
    }
}
