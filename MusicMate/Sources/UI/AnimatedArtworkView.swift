import SwiftUI
import AVKit

struct AnimatedArtworkView: NSViewRepresentable {
    let url: URL?
    var contentMode: ContentMode = .fill
    var cornerRadius: CGFloat = 0

    enum ContentMode { case fill, fit }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.cornerRadius = cornerRadius
        return view
    }

    func updateNSView(_ view: PlayerView, context: Context) {
        view.cornerRadius = cornerRadius
        view.gravity = (contentMode == .fill) ? .resizeAspectFill : .resizeAspect
        view.coordinator = context.coordinator
        view.load(url: url)
    }

    static func dismantleNSView(_ view: PlayerView, coordinator: Coordinator) {
        view.cleanup()
        coordinator.looper = nil
        coordinator.queuePlayer?.pause()
        coordinator.queuePlayer = nil
    }

    final class Coordinator {
        var queuePlayer: AVQueuePlayer?
        var looper: AVPlayerLooper?
    }

    final class PlayerView: NSView {
        var coordinator: Coordinator?
        var cornerRadius: CGFloat = 0 {
            didSet { layer?.cornerRadius = cornerRadius }
        }
        var gravity: AVLayerVideoGravity = .resizeAspectFill {
            didSet { playerLayer?.videoGravity = gravity }
        }
        private var playerLayer: AVPlayerLayer?
        private var lastURL: URL?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer = CALayer()
            layer?.masksToBounds = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            playerLayer?.frame = bounds
        }

        func load(url: URL?) {
            guard url != lastURL else { return }
            lastURL = url
            cleanup()
            guard let url else { return }

            let item = AVPlayerItem(url: url)
            let queue = AVQueuePlayer(playerItem: item)
            queue.isMuted = true
            queue.actionAtItemEnd = .none
            queue.automaticallyWaitsToMinimizeStalling = false
            let looper = AVPlayerLooper(player: queue, templateItem: item)
            coordinator?.queuePlayer = queue
            coordinator?.looper = looper

            let pl = AVPlayerLayer(player: queue)
            pl.frame = bounds
            pl.videoGravity = gravity
            layer?.addSublayer(pl)
            playerLayer = pl
            queue.play()
        }

        func cleanup() {
            playerLayer?.removeFromSuperlayer()
            playerLayer = nil
            coordinator?.looper = nil
            coordinator?.queuePlayer?.pause()
            coordinator?.queuePlayer = nil
        }
    }
}
