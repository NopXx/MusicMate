import AppKit
import SwiftUI
import Combine

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let playerMonitor: PlayerMonitor
    private let viewModel: MiniPlayerViewModel
    private let animationFullscreenController: AnimationFullscreenController
    private var cancellables = Set<AnyCancellable>()

    private var dynamicIslandModel: MenuBarDynamicIslandModel?
    private var hostingView: NSHostingView<MenuBarDynamicIslandView>?
    private var currentStyle: String = ""

    init(playerMonitor: PlayerMonitor, scrobbler: ScrobblerService) {
        self.playerMonitor = playerMonitor
        self.viewModel = MiniPlayerViewModel(monitor: playerMonitor, scrobbler: scrobbler)
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        self.animationFullscreenController = AnimationFullscreenController(viewModel: self.viewModel)
        self.popover.behavior = .transient
        self.popover.contentSize = NSSize(width: 320, height: 505)
        self.popover.contentViewController = NSHostingController(rootView: MiniPlayerView(viewModel: viewModel))

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp])
        }

        playerMonitor.$snapshot
            .combineLatest(EditHistoryService.shared.$rules)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] raw, _ in
                let edited = raw.map { EditHistoryService.shared.apply($0) }
                self?.updateTitle(edited)
            }
            .store(in: &cancellables)

        SettingsStore.shared.$data
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyStyle()
                self?.updateTitle(self?.currentEditedSnap())
            }
            .store(in: &cancellables)

        applyStyle()
        updateTitle(currentEditedSnap())
    }

    private func currentEditedSnap() -> NowPlayingSnapshot? {
        playerMonitor.snapshot.map { EditHistoryService.shared.apply($0) }
    }

    private func applyStyle() {
        let style = SettingsStore.shared.string(["menubar", "style"])
        let resolved = style.isEmpty ? "text" : style
        if resolved == currentStyle { return }
        currentStyle = resolved

        guard let button = statusItem.button else { return }

        hostingView?.removeFromSuperview()
        hostingView = nil
        dynamicIslandModel = nil

        if resolved == "dynamic_island" {
            MusicAudioLevelMonitor.shared.start()
            let model = MenuBarDynamicIslandModel(monitor: playerMonitor)
            let host = NSHostingView(rootView: MenuBarDynamicIslandView(model: model))
            host.translatesAutoresizingMaskIntoConstraints = false
            button.title = ""
            button.image = nil
            button.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                host.topAnchor.constraint(equalTo: button.topAnchor),
                host.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            ])
            self.dynamicIslandModel = model
            self.hostingView = host
            statusItem.length = NSStatusItem.variableLength
        } else {
            statusItem.length = NSStatusItem.variableLength
        }
    }

    private func updateTitle(_ snap: NowPlayingSnapshot?) {
        guard currentStyle == "text" else { return }
        guard let button = statusItem.button else { return }
        let s = SettingsStore.shared
        let showIcon   = s.bool(["menubar", "show_icon"])
        let showTrack  = s.bool(["menubar", "show_track"])
        let showArtist = s.bool(["menubar", "show_artist"])
        let showState  = s.bool(["menubar", "show_state"])
        let maxLength  = max(8, s.int(["menubar", "max_length"]))

        var parts: [String] = []
        if showIcon { parts.append("♪") }

        if let snap, snap.hasTrack {
            if showState { parts.append(snap.isPlaying ? "▶" : "❙❙") }
            var info: [String] = []
            if showTrack { info.append(snap.title) }
            if showArtist { info.append(snap.artist) }
            let infoStr = info.joined(separator: " — ")
            if !infoStr.isEmpty { parts.append(infoStr) }
        } else if !showIcon {
            parts.append("MusicMate")
        }

        var label = parts.joined(separator: " ")
        if label.isEmpty { label = "♪ MusicMate" }
        if label.count > maxLength {
            label = String(label.prefix(maxLength)) + "…"
        }
        button.title = label
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if currentStyle == "dynamic_island",
           let event = NSApp.currentEvent,
           handleIslandClick(event: event, in: button) {
            return
        }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func handleIslandClick(event: NSEvent, in button: NSStatusBarButton) -> Bool {
        guard SettingsStore.shared.bool(["menubar", "show_state"]) else { return false }
        let loc = button.convert(event.locationInWindow, from: nil)
        let outerPad: CGFloat = 3
        let innerPad: CGFloat = 12
        let artworkW: CGFloat = 18
        let spacing: CGFloat = 14
        let iconW: CGFloat = 14
        let iconStartX = outerPad + innerPad + artworkW + spacing
        let iconEndX = iconStartX + iconW
        if loc.x >= iconStartX && loc.x <= iconEndX {
            MusicAppController.playPause()
            return true
        }
        return false
    }
}
