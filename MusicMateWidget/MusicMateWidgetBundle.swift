import WidgetKit
import SwiftUI

@main
struct MusicMateWidgetBundle: WidgetBundle {
    var body: some Widget {
        NowPlayingWidget()
    }
}

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let title: String
    let artist: String
}

struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: .now, title: "Not Playing", artist: "—")
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        completion(Timeline(entries: [load()], policy: .never))
    }

    private func load() -> NowPlayingEntry {
        let defaults = UserDefaults(suiteName: "group.com.nopxx.MusicMate")
        let title = defaults?.string(forKey: "nowPlaying.title") ?? "Not Playing"
        let artist = defaults?.string(forKey: "nowPlaying.artist") ?? "—"
        return NowPlayingEntry(date: .now, title: title, artist: artist)
    }
}

struct NowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NowPlaying", provider: NowPlayingProvider()) { entry in
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title).font(.headline).lineLimit(1)
                Text(entry.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding()
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Now Playing")
        .description("Shows the current track from MusicMate.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
