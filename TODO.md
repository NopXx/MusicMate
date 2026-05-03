# MusicMate — TODO

อ้างอิงแผนเต็มที่ `~/.claude/plans/desktop-app-fizzy-whale.md`

---

## ✅ เสร็จแล้ว

### Foundation
- [x] Xcode project skeleton (xcodegen) — 3 targets: app, widget, tests
- [x] App Group: `group.com.nopxx.MusicMate`
- [x] Min target macOS 14, Bundle ID `com.nopxx.MusicMate`
- [x] Entitlements: Apple Events, network client, app-sandbox = false

### Player integration
- [x] `PlayerMonitor` — event-driven via `com.apple.Music.playerInfo` notification + 1s polling fallback
- [x] `MusicAppController` — NSAppleScript wrapper สำหรับ playpause / next / prev / seek / snapshot
- [x] Snapshot script ใช้ `<<MMSEP>>` separator + escape `theState` (กัน reserved word)

### Menu bar
- [x] `NSStatusItem` + `NSPopover` host SwiftUI
- [x] Title อัปเดตชื่อเพลงปัจจุบัน (max 40 chars + ellipsis)

### Mini player (SwiftUI)
- [x] 3 layouts: Classic / Tall (auto for portrait video) / Immersive (opt-in)
- [x] `AnimatedArtworkView` — AVPlayer + AVPlayerLooper retained ใน Coordinator
- [x] ตำแหน่งของ Icon ในโหมด Classic Not Tall ของ Mini player (เลื่อนลงไปอยู่ที่ด้านล่างสุด) เหมือน Tall
- [x] Static artwork fallback ผ่าน `AsyncImage`
- [x] Blurred backdrop + dominant-color gradient
- [x] Progress bar + remaining time + scrobble percent indicator
- [x] Play/Pause/Next/Prev + footer (settings, notifications toggle, quit)

### Artwork
- [x] `ArtworkService` (actor) — เรียก `apple-music-artwork-search.vercel.app/api/search`
- [x] Best-match logic: track+artist+album → track+artist → first
- [x] In-memory cache by track key
- [x] `ColorExtractor` (actor) — sample saturated pixels เพื่อ accent + average สำหรับ gradient

### Settings
- [x] `SettingsStore` — JSON-backed file ที่ `~/Library/Application Support/MusicMate/settings.json`
- [x] Deep merge + defaults + public snapshot (กัน api_secret หลุด)
- [x] SwiftUI `SettingsView` (TabView): Last.fm / Scrobble / แจ้งเตือน / Mini Player
- [x] Live update mini player เมื่อแก้ settings

### Last.fm
- [x] `LastFMClient` — sign params (MD5 via CryptoKit) + call API
- [x] `ScrobblerService` — subscribe `PlayerMonitor.$snapshot`
- [x] `track.updateNowPlaying` ตอนเริ่มเพลง
- [x] `track.scrobble` เมื่อ played ≥ percent setting (default 50%) + duration > min_seconds
- [x] กัน scrobble ซ้ำต่อ track key (persistent ID)
- [x] Auth flow: `auth.getToken` → เปิด browser → poll `auth.getSession` ทุก 2.5s

---

## 🚧 กำลังทำ / ยังไม่ทำ

### Widget extension (day 12-13)
- [ ] `App Group UserDefaults(suiteName:)` write track snapshot ตอน `PlayerMonitor` update
  - title, artist, album, artworkURL, state, positionAt timestamp
- [ ] Save artwork PNG ลง shared container (widget fetch network ไม่เสถียร)
- [ ] `WidgetCenter.shared.reloadAllTimelines()` ทุกครั้งที่เพลงเปลี่ยน
- [ ] Widget UI: small / medium ใช้ artwork + title + artist
- [ ] Progress timeline (entries ห่าง 30s ถึงปลายเพลง)

### Now Playing / Lockscreen / Control Center (day 14-15)
- [x] `MPNowPlayingInfoCenter` integration
- [x] `MPNowPlayingSession` + `becomeActive()` / `resignActive()` สำหรับ Takeover mode
- [x] **Mirror mode** (default) — observe Music.app เฉยๆ ไม่ register
- [x] **Takeover mode** — `becomeActive` + publish `nowPlayingInfo` (artwork สวยกว่า)
- [x] `MPRemoteCommandCenter` forward play/pause/next/prev/seek → AppleScript
- [x] Settings toggle ระหว่าง 2 modes

### Notifications (day 11)
- [ ] `NotificationService` — `UNUserNotificationCenter` wrapper
- [ ] On track change: banner + artwork thumbnail
- [ ] On scrobble success: optional banner
- [ ] เคารพ settings: enabled / on_play / on_scrobble

### Webhooks (day 11)
- [ ] `WebhookDispatcher` — async URLSession fan-out
- [ ] Payload shape เทียบ Music-Scrobbler (ดู [server.py:879+](../apple-music/server.py))
- [ ] Settings UI สำหรับ webhook URLs (add / remove / heartbeat)

### History store (day 9)
- [ ] เลือก SQLite library: GRDB หรือ SQLite.swift
- [ ] Schema: `plays`, `edit_history`, `pending_scrobbles`
- [ ] Migration import จาก `~/Desktop/vibe-code/apple-music/history.db`
- [ ] Settings tab "ประวัติ" + export CSV

### Edit history (day 9)
- [ ] `EditHistoryService` — apply rules ก่อน scrobble (artist/track/album rewrites)
- [ ] Settings UI: เพิ่ม/แก้/ลบ rules
- [ ] Retry artwork ด้วยชื่อเดิมถ้า edited ชื่อแล้วหา artwork ไม่เจอ

### Pending scrobble queue (day 6-8 enhancement)
- [ ] เก็บ scrobble ที่ส่งไม่ผ่านลง SQLite `pending_scrobbles`
- [ ] Retry ตอน launch + ทุก 5 นาที
- [ ] Bulk submit รวมหลายแถวต่อ request

### ScriptingBridge upgrade (optional — performance)
- [ ] Generate `Music.h` จาก `sdef`/`sdp`
- [ ] แทน NSAppleScript polling → typed Swift API
- [ ] Lower CPU เพราะไม่ต้อง parse string ทุกวินาที

### Polish
- [ ] Localization: `Localizable.strings` (TH + EN) แทน hardcoded ไทย
- [ ] App icon + Dock icon (LSUIElement = NO ตอน first-run welcome?)
- [ ] Code signing + notarization สำหรับ release
- [ ] Auto-update mechanism (Sparkle หรือ GitHub releases)

---

## 🐞 Known issues

- **AVPlayer animated mp4 error -12860** — ใน unsigned dev build บางเครื่อง mp4 จาก `mvod.itunes.apple.com` decode ไม่ผ่าน
  - Workaround เผื่อเจอ: download mp4 → cache ใน `/tmp` → play จาก file URL
  - Likely fix: code-signed build จะดีขึ้น
- **Sandbox subprocess noise** — WebContent process logs สิ่งที่ไม่เกี่ยวกับ feature เรา; ignore ได้

---

## 🗂️ Migration จาก apple-music (Python)

- [ ] First-launch import: copy `settings.json` จาก path ของ Python install
- [ ] Import `history.db` (เมื่อทำ HistoryStore แล้ว)
- [ ] Import `edit_history.json`
- [ ] Migrate Last.fm session_key → Keychain (ถ้าเลือกย้าย)

---

## 📋 Verification matrix (เมื่อทุก feature เสร็จ)

| Feature | Test |
|---|---|
| Menu bar | Title อัปเดตภายใน 1s |
| Mini player Classic | Artwork 272×272 ตรงกลาง + blurred backdrop |
| Mini player Tall | Portrait mp4 full-bleed + content overlay |
| Mini player Immersive | Full-bleed ทุกเพลง |
| Scrobbling | Last.fm/user/X เห็นรายการภายใน 30s |
| Now Playing (takeover) | Lockscreen แสดง artwork + transport |
| Control Center | App เราโผล่ใน Now Playing tile |
| Widget | Refresh ภายใน 2s เมื่อเปลี่ยนเพลง |
| Webhooks | Payload ตรงกับ Python version |
| Edit history | Rule "A → B" → scrobble โชว์ B |
| Notifications | Banner ตอนเปลี่ยนเพลง + artwork |
| Migration | Import settings + history สำเร็จ |
