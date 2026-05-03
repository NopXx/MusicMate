import Foundation
import SQLite3

@MainActor
enum MigrationService {
    private static let flagKey: [String] = ["migration", "imported_v1"]

    /// Runs once on first launch. Imports settings, history events, and edit
    /// rules from the legacy apple-music (Python) install if found.
    static func runIfNeeded() async {
        let settings = SettingsStore.shared
        if settings.bool(flagKey) { return }

        guard let sourceDir = findSourceDirectory() else {
            settings.merge(["migration": ["imported_v1": true]])
            return
        }
        NSLog("[Migration] importing from \(sourceDir.path)")

        importSettings(from: sourceDir.appendingPathComponent("settings.json"))
        await importEditHistory(from: sourceDir.appendingPathComponent("edit_history.json"))
        await importEvents(from: sourceDir.appendingPathComponent("history.db"))

        settings.merge(["migration": ["imported_v1": true]])
        NSLog("[Migration] done")
    }

    private static func findSourceDirectory() -> URL? {
        let fm = FileManager.default
        let candidates: [URL] = [
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Desktop/vibe-code/apple-music"),
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support/apple-music"),
        ]
        return candidates.first { fm.fileExists(atPath: $0.path) }
    }

    // MARK: - settings.json

    private static func importSettings(from url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        var patch: [String: Any] = [:]

        if let lf = json["lastfm"] as? [String: Any] {
            // import api keys + session for last.fm
            var dst: [String: Any] = [:]
            for k in ["api_key", "api_secret", "session_key", "username", "enabled"] {
                if let v = lf[k] { dst[k] = v }
            }
            if !dst.isEmpty { patch["lastfm"] = dst }
        }

        if let s = json["scrobble"] as? [String: Any] {
            patch["scrobble"] = s
        }

        if let n = json["notifications"] as? [String: Any] {
            patch["notifications"] = n
        }

        if let wh = json["webhook"] as? [String: Any] {
            var dst: [String: Any] = [:]
            if let urls = wh["urls"] as? [Any] {
                dst["urls"] = urls.compactMap { $0 as? String }.filter { !$0.isEmpty }
            } else if let single = wh["url"] as? String, !single.isEmpty {
                dst["urls"] = [single]
            }
            if let enabled = wh["enabled"] as? Bool { dst["enabled"] = enabled }
            if let hb = wh["heartbeat_seconds"] as? Int { dst["heartbeat_seconds"] = hb }
            if !dst.isEmpty { patch["webhook"] = dst }
        }

        if let mp = json["miniplayer"] as? [String: Any] {
            // skip animation_quality / artwork_quality if we don't use them, but store anyway
            patch["miniplayer"] = mp
        }

        if !patch.isEmpty {
            SettingsStore.shared.merge(patch)
            NSLog("[Migration] settings imported")
        }
    }

    // MARK: - edit_history.json

    private static func importEditHistory(from url: URL) async {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        var imported = 0
        for (key, raw) in json {
            guard let entry = raw as? [String: Any] else { continue }
            // key format: "ARTIST||||TRACK"
            let parts = key.components(separatedBy: "||||")
            guard parts.count == 2 else { continue }
            let artistMatch = parts[0]
            let trackMatch = parts[1]
            guard !artistMatch.isEmpty else { continue }

            let artistTo = (entry["artist"] as? String) ?? ""
            let trackTo  = (entry["track"]  as? String) ?? ""
            let albumTo  = (entry["album"]  as? String) ?? ""

            // skip if replacements equal match (no-op)
            if artistTo == artistMatch && trackTo == trackMatch && albumTo.isEmpty { continue }

            let rule = EditRule(
                id: 0,
                artistMatch: artistMatch, trackMatch: trackMatch, albumMatch: "",
                artistTo: artistTo == artistMatch ? "" : artistTo,
                trackTo:  trackTo  == trackMatch  ? "" : trackTo,
                albumTo:  albumTo
            )
            _ = await HistoryStore.shared.addEditRule(rule)
            imported += 1
        }
        NSLog("[Migration] edit rules imported: \(imported)")
        await EditHistoryService.shared.reload()
    }

    // MARK: - history.db (events table)

    private static func importEvents(from url: URL) async {
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        var src: OpaquePointer?
        guard sqlite3_open_v2(url.path, &src, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            NSLog("[Migration] failed to open source db")
            return
        }
        defer { sqlite3_close(src) }

        var stmt: OpaquePointer?
        let sql = "SELECT timestamp, event_type, track_name, artist_name, album_name, duration, position FROM events ORDER BY timestamp ASC;"
        guard sqlite3_prepare_v2(src, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        var imported = 0
        while sqlite3_step(stmt) == SQLITE_ROW {
            let ts = sqlite3_column_int64(stmt, 0)
            let evt = String(cString: sqlite3_column_text(stmt, 1))
            let track = String(cString: sqlite3_column_text(stmt, 2))
            let artist = String(cString: sqlite3_column_text(stmt, 3))
            let album: String = {
                guard let raw = sqlite3_column_text(stmt, 4) else { return "" }
                return String(cString: raw)
            }()
            let dur = sqlite3_column_double(stmt, 5)
            let pos = sqlite3_column_double(stmt, 6)
            await HistoryStore.shared.insertEvent(
                type: evt, title: track, artist: artist, album: album,
                duration: dur, position: pos,
                at: Date(timeIntervalSince1970: TimeInterval(ts))
            )
            imported += 1
        }
        NSLog("[Migration] events imported: \(imported)")
    }
}
