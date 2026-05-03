import SwiftUI
import AppKit

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var apiKey: String
    @Published var apiSecret: String
    @Published var lastfmEnabled: Bool
    @Published var sessionUser: String
    @Published var hasPendingToken: Bool
    @Published var connecting: Bool = false
    @Published var statusMessage: String = ""

    @Published var scrobblePercent: Int
    @Published var scrobbleMinSeconds: Int

    @Published var notificationsEnabled: Bool
    @Published var notifOnPlay: Bool
    @Published var notifOnScrobble: Bool

    @Published var miniplayerMeta: String
    @Published var miniplayerAnimation: String
    @Published var miniplayerArtworkStyle: String

    @Published var menubarShowIcon: Bool
    @Published var menubarShowTrack: Bool
    @Published var menubarShowArtist: Bool
    @Published var menubarShowState: Bool
    @Published var menubarMaxLength: Int

    @Published var nowPlayingMode: String

    @Published var webhookEnabled: Bool
    @Published var webhookHeartbeat: Int
    @Published var webhookUrls: [String]
    @Published var newWebhookUrl: String = ""

    private let store = SettingsStore.shared
    private var pollTask: Task<Void, Never>?

    init() {
        let lf = store.value(["lastfm"], [String: Any].self) ?? [:]
        self.apiKey = (lf["api_key"] as? String) ?? ""
        self.apiSecret = ""
        self.lastfmEnabled = (lf["enabled"] as? Bool) ?? false
        self.sessionUser = (lf["username"] as? String) ?? ""
        self.hasPendingToken = !((lf["pending_token"] as? String) ?? "").isEmpty

        self.scrobblePercent = store.int(["scrobble", "percent"])
        self.scrobbleMinSeconds = store.int(["scrobble", "min_seconds"])

        self.notificationsEnabled = store.bool(["notifications", "enabled"])
        self.notifOnPlay = store.bool(["notifications", "on_play"])
        self.notifOnScrobble = store.bool(["notifications", "on_scrobble"])

        let meta = store.string(["miniplayer", "meta_display"])
        self.miniplayerMeta = meta.isEmpty ? "artist_album" : meta
        let anim = store.string(["miniplayer", "animation"])
        self.miniplayerAnimation = anim.isEmpty ? "full" : anim
        let style = store.string(["miniplayer", "artwork_style"])
        self.miniplayerArtworkStyle = style.isEmpty ? "classic" : style

        let mode = store.string(["nowplaying", "mode"])
        self.nowPlayingMode = mode.isEmpty ? "mirror" : mode

        self.menubarShowIcon = store.bool(["menubar", "show_icon"])
        self.menubarShowTrack = store.bool(["menubar", "show_track"])
        self.menubarShowArtist = store.bool(["menubar", "show_artist"])
        self.menubarShowState = store.bool(["menubar", "show_state"])
        let ml = store.int(["menubar", "max_length"])
        self.menubarMaxLength = ml > 0 ? ml : 40

        self.webhookEnabled = store.bool(["webhook", "enabled"])
        self.webhookHeartbeat = store.int(["webhook", "heartbeat_seconds"])
        self.webhookUrls = (store.value(["webhook", "urls"], [Any].self) ?? [])
            .compactMap { $0 as? String }
    }

    var hasSession: Bool {
        let lf = store.value(["lastfm"], [String: Any].self) ?? [:]
        return !((lf["session_key"] as? String) ?? "").isEmpty
    }

    func saveKeys() {
        var lf: [String: Any] = ["api_key": apiKey, "enabled": lastfmEnabled]
        if !apiSecret.isEmpty { lf["api_secret"] = apiSecret }
        store.merge(["lastfm": lf])
    }

    func connect() {
        saveKeys()
        let lf = store.value(["lastfm"], [String: Any].self) ?? [:]
        let key = (lf["api_key"] as? String) ?? ""
        let secret = (lf["api_secret"] as? String) ?? ""
        guard !key.isEmpty, !secret.isEmpty else {
            statusMessage = "ต้องใส่ API Key และ Secret ก่อน"
            return
        }
        statusMessage = ""
        connecting = true
        Task { [weak self] in
            let res = await LastFMClient.call(method: "auth.getToken",
                                              params: ["api_key": key], secret: secret)
            await MainActor.run {
                guard let self else { return }
                guard let token = res["token"] as? String else {
                    self.connecting = false
                    self.statusMessage = (res["message"] as? String) ?? "ขอ token ไม่สำเร็จ"
                    return
                }
                self.store.merge(["lastfm": ["pending_token": token]])
                self.hasPendingToken = true
                let authURL = URL(string: "https://www.last.fm/api/auth/?api_key=\(key)&token=\(token)")
                if let authURL { NSWorkspace.shared.open(authURL) }
                self.startPolling()
            }
        }
    }

    func cancelConnect() {
        pollTask?.cancel()
        pollTask = nil
        connecting = false
        store.merge(["lastfm": ["session_key": "", "username": "",
                                "pending_token": "", "enabled": false]])
        hasPendingToken = false
        sessionUser = ""
        lastfmEnabled = false
    }

    func disconnect() {
        cancelConnect()
        statusMessage = "ตัดการเชื่อมต่อแล้ว"
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            for _ in 0..<48 {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if Task.isCancelled { return }
                guard let self else { return }
                let lf = await SettingsStore.shared.value(["lastfm"], [String: Any].self) ?? [:]
                let token = (lf["pending_token"] as? String) ?? ""
                let key = (lf["api_key"] as? String) ?? ""
                let secret = (lf["api_secret"] as? String) ?? ""
                guard !token.isEmpty else { continue }
                let res = await LastFMClient.call(method: "auth.getSession",
                                                  params: ["api_key": key, "token": token],
                                                  secret: secret)
                if let session = res["session"] as? [String: Any],
                   let sk = session["key"] as? String,
                   let name = session["name"] as? String {
                    await MainActor.run {
                        self.store.merge(["lastfm": [
                            "session_key": sk, "username": name,
                            "pending_token": "", "enabled": true,
                        ]])
                        self.sessionUser = name
                        self.lastfmEnabled = true
                        self.hasPendingToken = false
                        self.connecting = false
                        self.statusMessage = "เชื่อมต่อกับ Last.fm เป็น \(name)"
                    }
                    return
                }
            }
            await MainActor.run {
                self?.connecting = false
                self?.hasPendingToken = false
                self?.statusMessage = "หมดเวลารอ — ลองอีกครั้ง"
            }
        }
    }

    func saveScrobbleRules() {
        store.merge(["scrobble": [
            "percent": scrobblePercent,
            "min_seconds": scrobbleMinSeconds,
        ]])
    }

    func saveNotifications() {
        store.merge(["notifications": [
            "enabled": notificationsEnabled,
            "on_play": notifOnPlay,
            "on_scrobble": notifOnScrobble,
        ]])
    }

    func saveNowPlaying() {
        store.merge(["nowplaying": ["mode": nowPlayingMode]])
    }

    func saveWebhook() {
        store.merge(["webhook": [
            "enabled": webhookEnabled,
            "urls": webhookUrls,
            "heartbeat_seconds": webhookHeartbeat,
        ]])
        Task { @MainActor in WebhookDispatcher.shared.reloadHeartbeat() }
    }

    func addWebhookUrl() {
        let trimmed = newWebhookUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, URL(string: trimmed) != nil else { return }
        guard !webhookUrls.contains(trimmed) else { return }
        webhookUrls.append(trimmed)
        newWebhookUrl = ""
        saveWebhook()
    }

    func removeWebhookUrl(_ url: String) {
        webhookUrls.removeAll { $0 == url }
        saveWebhook()
    }

    func saveMenubar() {
        store.merge(["menubar": [
            "show_icon": menubarShowIcon,
            "show_track": menubarShowTrack,
            "show_artist": menubarShowArtist,
            "show_state": menubarShowState,
            "max_length": menubarMaxLength,
        ]])
    }

    func saveMiniplayer() {
        store.merge(["miniplayer": [
            "meta_display": miniplayerMeta,
            "animation": miniplayerAnimation,
            "artwork_style": miniplayerArtworkStyle,
        ]])
    }
}

// MARK: - Settings tab enum

private enum SettingsTab: String, CaseIterable, Identifiable {
    case lastfm, scrobble, nowPlaying, notifications, webhooks, menubar, miniplayer, editRules, history

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lastfm: return "Last.fm"
        case .scrobble: return "Scrobble"
        case .nowPlaying: return "Now Playing"
        case .notifications: return "แจ้งเตือน"
        case .webhooks: return "Webhooks"
        case .menubar: return "Menu Bar"
        case .miniplayer: return "Mini Player"
        case .editRules: return "Edit Rules"
        case .history: return "ประวัติ"
        }
    }

    var icon: String {
        switch self {
        case .lastfm: return "music.note.list"
        case .scrobble: return "checkmark.seal"
        case .nowPlaying: return "lock.iphone"
        case .notifications: return "bell"
        case .webhooks: return "link"
        case .menubar: return "menubar.rectangle"
        case .miniplayer: return "play.rectangle"
        case .editRules: return "pencil.and.list.clipboard"
        case .history: return "clock.arrow.circlepath"
        }
    }
}

// MARK: - Root view

struct SettingsView: View {
    @StateObject var vm = SettingsViewModel()
    @State private var selection: SettingsTab = .lastfm

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selection) { tab in
                Label(tab.label, systemImage: tab.icon).tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            Group {
                switch selection {
                case .lastfm:        LastfmTab(vm: vm)
                case .scrobble:      ScrobbleTab(vm: vm)
                case .nowPlaying:    NowPlayingTab(vm: vm)
                case .notifications: NotificationsTab(vm: vm)
                case .webhooks:      WebhooksTab(vm: vm)
                case .menubar:       MenubarTab(vm: vm)
                case .miniplayer:    MiniplayerTab(vm: vm)
                case .editRules:     EditRulesTab()
                case .history:       HistoryTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(minWidth: 720, idealWidth: 760, minHeight: 520, idealHeight: 560)
    }
}

// MARK: - Last.fm

private struct LastfmTab: View {
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        Form {
            Section {
                if vm.hasSession {
                    HStack(spacing: 10) {
                        Circle().fill(.green).frame(width: 8, height: 8)
                        Text("เชื่อมต่อแล้วเป็น")
                        Text(vm.sessionUser).bold()
                        Spacer()
                    }
                    Toggle("เปิดใช้งาน Scrobbling", isOn: $vm.lastfmEnabled)
                        .onChange(of: vm.lastfmEnabled) { _, _ in vm.saveKeys() }
                    Button("ตัดการเชื่อมต่อ", role: .destructive) { vm.disconnect() }
                } else {
                    HStack(spacing: 10) {
                        Circle().fill(.secondary).frame(width: 8, height: 8)
                        Text("ยังไม่ได้เชื่อมต่อ").foregroundStyle(.secondary)
                        Spacer()
                    }
                    LabeledContent("API Key") {
                        TextField("", text: $vm.apiKey)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { vm.saveKeys() }
                    }
                    LabeledContent("Shared Secret") {
                        SecureField("", text: $vm.apiSecret)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { vm.saveKeys() }
                    }
                    HStack {
                        Spacer()
                        if vm.connecting {
                            Button("ยกเลิก") { vm.cancelConnect() }
                            Button("กำลังรอการอนุมัติ…") {}.disabled(true)
                        } else {
                            Button("Connect with Last.fm") {
                                vm.saveKeys()
                                vm.connect()
                            }
                            .keyboardShortcut(.defaultAction)
                            .disabled(vm.apiKey.isEmpty || vm.apiSecret.isEmpty)
                        }
                    }
                    Link("ขอ API key ฟรี →",
                         destination: URL(string: "https://www.last.fm/api/account/create")!)
                        .font(.caption)
                }
                if !vm.statusMessage.isEmpty {
                    Text(vm.statusMessage).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                SectionHeader(icon: "music.note.list",
                              title: "เชื่อมต่อ Last.fm",
                              subtitle: "ส่ง now-playing และ scrobble เพลงไปที่ Last.fm")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Scrobble

private struct ScrobbleTab: View {
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Stepper(value: $vm.scrobblePercent, in: 25...100, step: 5) {
                    LabeledContent("เล่นครบ") {
                        Text("\(vm.scrobblePercent)%").monospacedDigit()
                    }
                }
                .onChange(of: vm.scrobblePercent) { _, _ in vm.saveScrobbleRules() }

                Stepper(value: $vm.scrobbleMinSeconds, in: 10...120, step: 5) {
                    LabeledContent("เพลงต้องยาวอย่างน้อย") {
                        Text("\(vm.scrobbleMinSeconds) วินาที").monospacedDigit()
                    }
                }
                .onChange(of: vm.scrobbleMinSeconds) { _, _ in vm.saveScrobbleRules() }
            } header: {
                SectionHeader(icon: "checkmark.seal",
                              title: "กฎการ Scrobble",
                              subtitle: "เกณฑ์ที่ใช้ตัดสินว่าเพลงควรถูก scrobble หรือไม่")
            } footer: {
                Text("ค่ามาตรฐานของ Last.fm: 50% หรือ 4 นาที (อย่างใดอย่างหนึ่งถึงก่อน) และเพลงต้องยาวอย่างน้อย 30 วินาที")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Now Playing

private struct NowPlayingTab: View {
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Picker("โหมด", selection: $vm.nowPlayingMode) {
                    Text("Mirror — ปล่อยให้ Music.app ทำเอง").tag("mirror")
                    Text("Takeover — MusicMate เป็น Now Playing").tag("takeover")
                }
                .pickerStyle(.radioGroup)
                .onChange(of: vm.nowPlayingMode) { _, _ in vm.saveNowPlaying() }
            } header: {
                SectionHeader(icon: "lock.iphone",
                              title: "Lockscreen / Control Center",
                              subtitle: "เลือกว่าใครจะเป็น Now Playing app บน lockscreen")
            } footer: {
                Text(vm.nowPlayingMode == "takeover"
                     ? "MusicMate จะแสดงบน lockscreen / Control Center พร้อม artwork ของเรา และรับคำสั่ง play/pause/next/prev"
                     : "Music.app จะเป็นแอปที่แสดงบน lockscreen เอง MusicMate แค่ฟังสถานะอย่างเดียว")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Notifications

private struct NotificationsTab: View {
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("เปิดการแจ้งเตือน", isOn: $vm.notificationsEnabled)
                    .onChange(of: vm.notificationsEnabled) { _, _ in vm.saveNotifications() }
                Toggle("เมื่อเริ่มเล่นเพลง", isOn: $vm.notifOnPlay)
                    .disabled(!vm.notificationsEnabled)
                    .onChange(of: vm.notifOnPlay) { _, _ in vm.saveNotifications() }
                Toggle("เมื่อ Scrobble สำเร็จ", isOn: $vm.notifOnScrobble)
                    .disabled(!vm.notificationsEnabled)
                    .onChange(of: vm.notifOnScrobble) { _, _ in vm.saveNotifications() }
            } header: {
                SectionHeader(icon: "bell",
                              title: "การแจ้งเตือน",
                              subtitle: "Banner ของ macOS เมื่อมีกิจกรรมการฟัง")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Webhooks

private struct WebhooksTab: View {
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("เปิดใช้งาน Webhooks", isOn: $vm.webhookEnabled)
                    .onChange(of: vm.webhookEnabled) { _, _ in vm.saveWebhook() }
                Stepper(value: $vm.webhookHeartbeat, in: 0...3600, step: 30) {
                    LabeledContent("Heartbeat") {
                        Text(vm.webhookHeartbeat == 0 ? "ปิด" : "ทุก \(vm.webhookHeartbeat) วินาที")
                            .monospacedDigit()
                    }
                }
                .disabled(!vm.webhookEnabled)
                .onChange(of: vm.webhookHeartbeat) { _, _ in vm.saveWebhook() }
            } header: {
                SectionHeader(icon: "link",
                              title: "Webhooks",
                              subtitle: "POST JSON ไปยัง endpoint ของคุณเมื่อมี event")
            } footer: {
                Text("Payload format ตรงกับ Music-Scrobbler — eventName: nowplaying / paused / scrobble")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if vm.webhookUrls.isEmpty {
                    Text("ยังไม่มี URL").foregroundStyle(.secondary).font(.callout)
                } else {
                    ForEach(vm.webhookUrls, id: \.self) { url in
                        HStack {
                            Text(url).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button {
                                vm.removeWebhookUrl(url)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack {
                    TextField("https://example.com/webhook", text: $vm.newWebhookUrl)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { vm.addWebhookUrl() }
                    Button("เพิ่ม") { vm.addWebhookUrl() }
                        .disabled(vm.newWebhookUrl.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("URL ปลายทาง").font(.subheadline.weight(.semibold))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Menu Bar

private struct MenubarTab: View {
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("แสดงไอคอน ♪", isOn: $vm.menubarShowIcon)
                    .onChange(of: vm.menubarShowIcon) { _, _ in vm.saveMenubar() }
                Toggle("แสดงสถานะการเล่น (▶ / ❙❙)", isOn: $vm.menubarShowState)
                    .onChange(of: vm.menubarShowState) { _, _ in vm.saveMenubar() }
                Toggle("แสดงชื่อเพลง", isOn: $vm.menubarShowTrack)
                    .onChange(of: vm.menubarShowTrack) { _, _ in vm.saveMenubar() }
                Toggle("แสดงศิลปิน", isOn: $vm.menubarShowArtist)
                    .onChange(of: vm.menubarShowArtist) { _, _ in vm.saveMenubar() }
                Stepper(value: $vm.menubarMaxLength, in: 10...120, step: 5) {
                    LabeledContent("ความยาวสูงสุด") {
                        Text("\(vm.menubarMaxLength) ตัวอักษร").monospacedDigit()
                    }
                }
                .onChange(of: vm.menubarMaxLength) { _, _ in vm.saveMenubar() }
            } header: {
                SectionHeader(icon: "menubar.rectangle",
                              title: "Menu Bar",
                              subtitle: "ปรับว่า status item จะแสดงข้อมูลอะไรบ้าง")
            } footer: {
                Text("ตัวอย่าง: ♪ ▶ ชื่อเพลง — ศิลปิน")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Mini Player

private struct MiniplayerTab: View {
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Picker("รูปแบบ Artwork", selection: $vm.miniplayerArtworkStyle) {
                    Text("Classic — artwork ตรงกลาง").tag("classic")
                    Text("Immersive — full-bleed").tag("fullbleed")
                }
                .onChange(of: vm.miniplayerArtworkStyle) { _, _ in vm.saveMiniplayer() }

                Picker("ข้อมูลที่แสดง", selection: $vm.miniplayerMeta) {
                    Text("ศิลปิน").tag("artist")
                    Text("อัลบั้ม").tag("album")
                    Text("ศิลปิน — อัลบั้ม").tag("artist_album")
                }
                .onChange(of: vm.miniplayerMeta) { _, _ in vm.saveMiniplayer() }

                Picker("Animated artwork", selection: $vm.miniplayerAnimation) {
                    Text("ปิด").tag("off")
                    Text("เฉพาะปก").tag("art")
                    Text("เต็ม (รวม backdrop)").tag("full")
                }
                .onChange(of: vm.miniplayerAnimation) { _, _ in vm.saveMiniplayer() }
            } header: {
                SectionHeader(icon: "play.rectangle",
                              title: "Mini Player",
                              subtitle: "ปรับหน้าตา mini player ใน menu bar")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Edit Rules

@MainActor
private final class EditRulesViewModel: ObservableObject {
    @Published var rules: [EditRule] = []
    @Published var artistMatch: String = ""
    @Published var trackMatch: String = ""
    @Published var albumMatch: String = ""
    @Published var artistTo: String = ""
    @Published var trackTo: String = ""
    @Published var albumTo: String = ""

    func load() async {
        await EditHistoryService.shared.reload()
        self.rules = EditHistoryService.shared.rules
    }

    func add() async {
        await EditHistoryService.shared.add(
            artistMatch: artistMatch, trackMatch: trackMatch, albumMatch: albumMatch,
            artistTo: artistTo, trackTo: trackTo, albumTo: albumTo
        )
        artistMatch = ""; trackMatch = ""; albumMatch = ""
        artistTo = ""; trackTo = ""; albumTo = ""
        await load()
    }

    func remove(_ rule: EditRule) async {
        await EditHistoryService.shared.delete(id: rule.id)
        await load()
    }

    // MARK: - Import / Export (apple-music edit_history.json format)

    func exportToFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "edit_history.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        var dict: [String: [String: String]] = [:]
        for rule in rules {
            let key = "\(rule.artistMatch)||||\(rule.trackMatch)"
            dict[key] = [
                "artist": rule.artistTo.isEmpty ? rule.artistMatch : rule.artistTo,
                "track":  rule.trackTo.isEmpty  ? rule.trackMatch  : rule.trackTo,
                "album":  rule.albumTo,
                "timestamp": String(Date().timeIntervalSince1970),
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict,
                                                     options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func importFromFile() async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let existing = Set(rules.map { "\($0.artistMatch)||||\($0.trackMatch)".lowercased() })

        for (key, raw) in json {
            guard let entry = raw as? [String: Any] else { continue }
            let parts = key.components(separatedBy: "||||")
            guard parts.count == 2 else { continue }
            let artistMatch = parts[0]
            let trackMatch = parts[1]
            guard !artistMatch.isEmpty else { continue }
            if existing.contains("\(artistMatch)||||\(trackMatch)".lowercased()) { continue }

            let artistTo = (entry["artist"] as? String) ?? ""
            let trackTo  = (entry["track"]  as? String) ?? ""
            let albumTo  = (entry["album"]  as? String) ?? ""
            await EditHistoryService.shared.add(
                artistMatch: artistMatch, trackMatch: trackMatch, albumMatch: "",
                artistTo: artistTo == artistMatch ? "" : artistTo,
                trackTo:  trackTo  == trackMatch  ? "" : trackTo,
                albumTo:  albumTo
            )
        }
        await load()
    }
}

private struct EditRulesTab: View {
    @StateObject private var vm = EditRulesViewModel()

    var body: some View {
        Form {
            Section {
                if vm.rules.isEmpty {
                    Text("ยังไม่มี rule").foregroundStyle(.secondary).font(.callout)
                } else {
                    ForEach(vm.rules) { rule in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(matchLabel(rule)).font(.callout)
                                Text("→ " + replacementLabel(rule))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                Task { await vm.remove(rule) }
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } header: {
                HStack(alignment: .top, spacing: 10) {
                    SectionHeader(icon: "pencil.and.list.clipboard",
                                  title: "Edit Rules",
                                  subtitle: "แก้ metadata อัตโนมัติก่อน scrobble / webhook")
                    Spacer()
                    Menu {
                        Button("Import…") { Task { await vm.importFromFile() } }
                        Button("Export…") { vm.exportToFile() }
                            .disabled(vm.rules.isEmpty)
                    } label: {
                        Image(systemName: "square.and.arrow.up.on.square")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }

            Section {
                LabeledContent("Artist (ต้องระบุ)") {
                    TextField("", text: $vm.artistMatch).textFieldStyle(.roundedBorder)
                }
                LabeledContent("Track (ถ้ามี)") {
                    TextField("", text: $vm.trackMatch).textFieldStyle(.roundedBorder)
                }
                LabeledContent("Album (ถ้ามี)") {
                    TextField("", text: $vm.albumMatch).textFieldStyle(.roundedBorder)
                }
            } header: {
                Text("ค่าที่ต้องการตรงกัน (match)").font(.subheadline.weight(.semibold))
            }

            Section {
                LabeledContent("Artist ใหม่") {
                    TextField("", text: $vm.artistTo).textFieldStyle(.roundedBorder)
                }
                LabeledContent("Track ใหม่") {
                    TextField("", text: $vm.trackTo).textFieldStyle(.roundedBorder)
                }
                LabeledContent("Album ใหม่") {
                    TextField("", text: $vm.albumTo).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Spacer()
                    Button("เพิ่ม Rule") { Task { await vm.add() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(vm.artistMatch.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("ค่าที่ต้องการแทน (เว้นว่าง = ใช้ของเดิม)").font(.subheadline.weight(.semibold))
            }
        }
        .formStyle(.grouped)
        .task { await vm.load() }
    }

    private func matchLabel(_ r: EditRule) -> String {
        var parts = [r.artistMatch]
        if !r.trackMatch.isEmpty { parts.append(r.trackMatch) }
        if !r.albumMatch.isEmpty { parts.append(r.albumMatch) }
        return parts.joined(separator: " | ")
    }

    private func replacementLabel(_ r: EditRule) -> String {
        let a = r.artistTo.isEmpty ? r.artistMatch : r.artistTo
        let t = r.trackTo.isEmpty ? (r.trackMatch.isEmpty ? "*" : r.trackMatch) : r.trackTo
        let alb = r.albumTo.isEmpty ? (r.albumMatch.isEmpty ? "*" : r.albumMatch) : r.albumTo
        return "\(a) | \(t) | \(alb)"
    }
}

// MARK: - History

@MainActor
private final class HistoryViewModel: ObservableObject {
    @Published var events: [HistoryEvent] = []
    @Published var totalCount: Int = 0
    @Published var pendingCount: Int = 0

    func load() async {
        async let evts = HistoryStore.shared.recentEvents(limit: 200)
        async let total = HistoryStore.shared.eventsCount()
        async let pending = HistoryStore.shared.pendingCount()
        self.events = await evts
        self.totalCount = await total
        self.pendingCount = await pending
    }
}

private struct HistoryTab: View {
    @StateObject private var vm = HistoryViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3).foregroundStyle(.tint).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ประวัติการเล่น").font(.headline)
                    Text("\(vm.totalCount) events ทั้งหมด · \(vm.pendingCount) scrobble ค้าง")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await vm.load() }
                } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            Table(vm.events) {
                TableColumn("เวลา") { e in
                    Text(e.timestamp, style: .relative).foregroundStyle(.secondary).font(.caption)
                }
                .width(min: 80, ideal: 100)
                TableColumn("Event") { e in
                    Text(e.eventType).font(.caption.monospaced())
                }
                .width(min: 60, ideal: 70)
                TableColumn("เพลง") { e in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(e.trackName).lineLimit(1)
                        Text("\(e.artistName) — \(e.albumName)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .task { await vm.load() }
    }
}

// MARK: - Section header

private struct SectionHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
