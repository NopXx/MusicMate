import AppKit
import SwiftUI
import Combine

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let playerMonitor: PlayerMonitor
    private let viewModel: MiniPlayerViewModel
    private var cancellables = Set<AnyCancellable>()

    init(playerMonitor: PlayerMonitor, scrobbler: ScrobblerService) {
        self.playerMonitor = playerMonitor
        self.viewModel = MiniPlayerViewModel(monitor: playerMonitor, scrobbler: scrobbler)
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        self.popover.behavior = .transient
        self.popover.contentSize = NSSize(width: 320, height: 505)
        self.popover.contentViewController = NSHostingController(rootView: MiniPlayerView(viewModel: viewModel))

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
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
            .sink { [weak self] _ in self?.updateTitle(self?.currentEditedSnap()) }
            .store(in: &cancellables)

        updateTitle(currentEditedSnap())
    }

    private func currentEditedSnap() -> NowPlayingSnapshot? {
        playerMonitor.snapshot.map { EditHistoryService.shared.apply($0) }
    }

    private func updateTitle(_ snap: NowPlayingSnapshot?) {
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
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
