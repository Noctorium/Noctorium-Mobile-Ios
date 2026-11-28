import SwiftUI

/// The stats service's answer: the same figures and charts as Noctorium Stats and stats.noctorium.xyz.
struct AccountStats: Decodable {
    struct Share: Decodable { var provider: String; var streams: Int }
    struct TopTrack: Decodable { var title: String; var artist: String; var streams: Int }
    struct TopArtist: Decodable { var artist: String; var streams: Int; var minutes: Int; var tracks: Int }
    struct Point: Decodable { var start: String; var minutes: Int }
    struct Timeline: Decodable { var bucket: String; var points: [Point] }
    struct Hour: Decodable { var hour: Int; var minutes: Int }
    struct Day: Decodable { var day: Int; var minutes: Int }
    struct Play: Decodable { var title: String; var artist: String; var provider: String; var playedAt: String }
    struct Streak: Decodable { var current: Int; var longest: Int }

    var streams: Int
    var uniqueTracks: Int
    var artists: Int
    var msPlayed: Int
    var byProvider: [Share]
    var topTracks: [TopTrack]
    var topArtists: [TopArtist]
    var timeline: Timeline
    var hourly: [Hour]
    var weekdays: [Day]
    var recent: [Play]
    var streak: Streak

    /// A service's name from the code the account records it by; the two YouTubes are one.
    static func serviceName(_ code: String) -> String {
        switch code {
        case "YOUTUBE_MUSIC", "YOUTUBE_VIDEO": return "YouTube Music"
        case "SOUNDCLOUD": return "SoundCloud"
        case "SPOTIFY": return "Spotify"
        case "BANDCAMP": return "Bandcamp"
        case "VK": return "VK"
        case "LOCAL": return "Your files"
        default: return code.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func serviceColour(_ name: String) -> Color {
        switch name {
        case "YouTube Music": return Color(red: 1, green: 0.31, blue: 0.27)
        case "SoundCloud": return Color(red: 1, green: 0.48, blue: 0.1)
        case "Spotify": return Color(red: 0.12, green: 0.84, blue: 0.38)
        case "Bandcamp": return Color(red: 0.38, green: 0.6, blue: 0.66)
        case "VK": return Color(red: 0.3, green: 0.61, blue: 1)
        default: return .accentColor
        }
    }

    /// The split by service, largest first.
    var services: [(name: String, streams: Int)] {
        var counted: [String: Int] = [:]
        for share in byProvider { counted[Self.serviceName(share.provider), default: 0] += share.streams }
        return counted.map { ($0.key, $0.value) }.sorted { $0.streams > $1.streams }
    }
}

private let ranges = [("7d", "7 days"), ("30d", "30 days"), ("90d", "90 days"), ("365d", "Year"), ("all", "All time")]
private let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

private func plays(_ n: Int) -> String { n == 1 ? "1 play" : "\(n) plays" }
private func days(_ n: Int) -> String { n == 1 ? "1 day" : "\(n) days" }
private func listened(_ ms: Int) -> String {
    let minutes = ms / 60_000
    return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
}

/// Noctorium Stats inside Noctorium: the account's listens from every device, with its streaks and charts.
struct StatsView: View {
    @EnvironmentObject private var account: Account
    @Environment(\.dismiss) private var dismiss
    @State private var range = "30d"
    @State private var stats: AccountStats?
    @State private var asked = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !account.signedIn {
                        Text("Your stats come from your Noctorium account: every song played on any device signed in to it, with your streaks and charts. Sign in from your picture's Account.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Span", selection: $range) {
                            ForEach(ranges, id: \.0) { Text($0.1).tag($0.0) }
                        }
                        .pickerStyle(.segmented)
                        if let stats { figures(stats) } else {
                            Text(asked ? "Your stats could not be reached. Try again in a moment." : "Loading…").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Stats")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: range) {
                guard account.signedIn else { return }
                stats = nil
                asked = false
                stats = await account.fullStats(range: range)
                asked = true
            }
        }
    }

    @ViewBuilder private func figures(_ stats: AccountStats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            tile("Listens", "\(stats.streams)")
            tile("Listened", listened(stats.msPlayed))
            tile("Songs", "\(stats.uniqueTracks)")
            tile("Artists", "\(stats.artists)")
            tile("Current streak", days(stats.streak.current))
            tile("Longest streak", days(stats.streak.longest))
        }
        if stats.streams == 0 {
            Text("Nothing played in this span yet.").foregroundStyle(.secondary)
        } else {
            heading(stats.timeline.bucket == "month" ? "Month by month" : "Day by day")
            bars(stats.timeline.points.map(\.minutes), labels: [], height: 110)
            heading("Hour of the day")
            bars(stats.hourly.map(\.minutes), labels: stats.hourly.map { $0.hour % 6 == 0 ? "\($0.hour)" : "" }, height: 80)
            heading("Day of the week")
            bars(stats.weekdays.map(\.minutes), labels: stats.weekdays.map { weekdays[max(0, min(6, $0.day - 1))] }, height: 80)
            heading("Top songs")
            ForEach(Array(stats.topTracks.enumerated()), id: \.offset) { i, song in
                ranked(i, song.title, song.artist, plays(song.streams))
            }
            heading("Top artists")
            ForEach(Array(stats.topArtists.enumerated()), id: \.offset) { i, artist in
                ranked(i, artist.artist, "\(artist.tracks) \(artist.tracks == 1 ? "song" : "songs") · \(artist.minutes) min", plays(artist.streams))
            }
            heading("By service")
            ForEach(stats.services, id: \.name) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text(row.name); Spacer(); Text("\(row.streams * 100 / max(1, stats.streams))%").font(.caption).foregroundStyle(.secondary) }
                    GeometryReader { box in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.2))
                            Capsule().fill(AccountStats.serviceColour(row.name))
                                .frame(width: max(2, box.size.width * CGFloat(row.streams) / CGFloat(max(1, stats.streams))))
                        }
                    }
                    .frame(height: 6)
                }
            }
            if !stats.recent.isEmpty { heading("Recently played") }
            ForEach(Array(stats.recent.enumerated()), id: \.offset) { _, play in
                ranked(nil, play.title, "\(play.artist) · \(AccountStats.serviceName(play.provider))", playedAt(play.playedAt))
            }
        }
    }

    private func playedAt(_ iso: String) -> String {
        let reader = ISO8601DateFormatter()
        reader.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = reader.date(from: iso) else { return "" }
        return date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(.title3.bold()).padding(.top, 12)
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.15)))
    }

    private func ranked(_ index: Int?, _ title: String, _ under: String, _ end: String) -> some View {
        HStack {
            if let index { Text("\(index + 1)").font(.footnote).foregroundStyle(.secondary).frame(width: 24, alignment: .leading) }
            VStack(alignment: .leading) {
                Text(title).lineLimit(1)
                Text(under).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(end).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Bars as tall as their share of the tallest, side by side, with a label under each.
    private func bars(_ values: [Int], labels: [String], height: CGFloat) -> some View {
        let most = CGFloat(max(1, values.max() ?? 0))
        return VStack(spacing: 2) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: max(2, height * CGFloat(value) / most))
                }
            }
            .frame(height: height, alignment: .bottom)
            if labels.contains(where: { !$0.isEmpty }) {
                HStack(spacing: 2) {
                    ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                        Text(label).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).fixedSize().frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}
