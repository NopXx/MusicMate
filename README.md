# MusicMate

A native macOS menu bar companion for Apple Music — Last.fm scrobbling, listening history, webhooks, edit-rules, notifications, and a polished mini player.

Written in Swift / SwiftUI. Talks to Music.app via ScriptingBridge. Replaces an older Python/PyObjC implementation with a faster, event-driven, system-integrated build.

## Features

- **Menu bar status item** — configurable display (icon, play state, track, artist, max length)
- **Mini player popover** — three layouts (Classic / Tall / Immersive), animated artwork, blurred backdrop, dominant-color gradient, scrubber
- **Last.fm scrobbling** — `track.updateNowPlaying` on play, `track.scrobble` once per play (configurable threshold), with auth flow and Keychain-style local config
- **Pending scrobble queue** — failed scrobbles are persisted to SQLite and retried on launch + every 5 minutes
- **Now Playing integration** — `MPNowPlayingInfoCenter` Mirror or Takeover modes for lock screen / Control Center
- **Notifications** — banner with artwork on track change and scrobble success
- **Webhooks** — POST JSON payloads in Music-Scrobbler format with optional heartbeat
- **Listening history** — every play / pause / resume / scrobble event is recorded to SQLite; viewable in Settings
- **Edit rules** — automatically rewrite artist / track / album metadata before scrobbling, configurable inline from the mini player or in Settings
- **Import / export** — Edit-rule JSON is interchangeable with the legacy apple-music Python edition
- **First-launch migration** — automatically imports settings, history, and edit rules from a sibling `apple-music` Python install

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build

```sh
xcodegen generate
xcodebuild -project MusicMate.xcodeproj -scheme MusicMate -configuration Debug build
```

Or open `MusicMate.xcodeproj` in Xcode and Run.

The generated `.xcodeproj` is not committed — regenerate it from `project.yml` whenever you pull.

## Architecture

```
PlayerMonitor          ──┐
  ScriptingBridge        │
  + DistributedNotif     ├─►  ScrobblerService  ──►  Last.fm
  + 1 Hz tick timer      │      └─► PendingScrobbleQueue (retry)
                         │
                         ├─►  NowPlayingService (Mirror / Takeover)
                         │
                         ├─►  WebhookDispatcher
                         │
                         ├─►  NotificationService
                         │
                         ├─►  HistoryRecorder ──► HistoryStore (SQLite)
                         │
                         └─►  MenuBarController + MiniPlayer (SwiftUI)

EditHistoryService  ──►  applies rules before scrobble / webhook / display
```

- `PlayerMonitor` owns a single `MusicApplication` ScriptingBridge object and listens to `com.apple.Music.playerInfo` distributed notifications. A 1 Hz timer ticks position locally; full state resyncs only fire on actual events.
- `MusicAppController` issues control commands (play / pause / next / prev / seek) through ScriptingBridge on a background queue.
- `HistoryStore` is an `actor` wrapping `sqlite3` directly — no third-party dependency.

## Settings

All user data lives under `~/Library/Application Support/MusicMate/`:

- `settings.json` — JSON-merged with defaults
- `history.db` — events, edit rules, pending scrobbles

## Project layout

```
MusicMate/
  Sources/
    App.swift
    Player/                  PlayerMonitor, MusicAppController, NowPlayingService
      Bridge/                Music.h (sdef-generated), MusicStubs.m
    Scrobbler/               LastFMClient, ScrobblerService, PendingScrobbleQueue
    Artwork/                 ArtworkService, ColorExtractor
    History/                 HistoryStore, HistoryRecorder, EditHistoryService
    Notifications/           NotificationService
    Webhooks/                WebhookDispatcher
    Settings/                SettingsStore, MigrationService
    UI/                      MenuBarController, MiniPlayer*, SettingsView, SettingsWindowController
  MusicMate-Bridging-Header.h
  Info.plist
  MusicMate.entitlements
MusicMateWidget/             (skeleton — not yet implemented)
MusicMateTests/
project.yml                  (xcodegen)
```

## Permissions

The first time MusicMate sends a command to Music.app, macOS will prompt for **Apple Events** automation permission. If you deny it, control buttons stop working — re-enable it under **System Settings → Privacy & Security → Automation → MusicMate → Music**.

## Status

Most features described above are implemented and working. Outstanding:

- Widget extension (target exists as a skeleton)
- Last.fm session-key migration to Keychain
- Localization / `Localizable.strings`
- App icon, code signing, notarization, auto-update

See [TODO.md](TODO.md) for the live punch list.

## Acknowledgements

Reference Python implementation that this project is reimagining: a sibling `apple-music` directory in the same workspace.

Artwork lookup uses [`apple-music-artwork-search`](https://apple-music-artwork-search.vercel.app/).

## License

MIT
