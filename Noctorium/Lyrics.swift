import Foundation

/// A song's lyrics from LRCLIB, the open lyrics library: synced, a line at a time, when it has them, and plain
/// otherwise.
struct Lyrics {
    struct Line: Identifiable { var id: Int; var time: TimeInterval; var text: String }
    var lines: [Line]
    var synced: Bool

    /// The line being sung at [time]: the last one that has started.
    func current(at time: TimeInterval) -> Int? {
        guard synced else { return nil }
        return lines.lastIndex { $0.time <= time + 0.3 }
    }

    private struct Reply: Decodable { var syncedLyrics: String?; var plainLyrics: String?; var duration: Double? }

    static func find(for track: Track) async -> Lyrics? {
        let artist = track.artistLine.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? track.artistLine
        // A video's title often carries the artist and extras; LRCLIB's search copes with that where its exact match cannot.
        let title = track.title.replacingOccurrences(of: #"\s*[\(\[].*?(official|video|audio|lyrics|visualizer|remaster).*?[\)\]]"#, with: "", options: [.regularExpression, .caseInsensitive])
        var exact = URLComponents(string: "https://lrclib.net/api/get")!
        exact.queryItems = [URLQueryItem(name: "artist_name", value: artist), URLQueryItem(name: "track_name", value: title)]
        if track.duration > 0 { exact.queryItems?.append(URLQueryItem(name: "duration", value: String(Int(track.duration)))) }
        if let reply: Reply = await fetch(exact.url!), let lyrics = parse(reply) { return lyrics }
        var search = URLComponents(string: "https://lrclib.net/api/search")!
        search.queryItems = [URLQueryItem(name: "q", value: "\(artist) \(title)")]
        if let replies: [Reply] = await fetch(search.url!) {
            let close = replies.filter { track.duration <= 0 || abs(($0.duration ?? 0) - track.duration) < 10 }
            for reply in close.sorted(by: { ($0.syncedLyrics != nil ? 0 : 1) < ($1.syncedLyrics != nil ? 0 : 1) }) {
                if let lyrics = parse(reply) { return lyrics }
            }
        }
        return nil
    }

    private static func fetch<T: Decodable>(_ url: URL) async -> T? {
        var request = URLRequest(url: url)
        request.setValue("Noctorium for iOS (https://github.com/Noctorium)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func parse(_ reply: Reply) -> Lyrics? {
        if let synced = reply.syncedLyrics, !synced.isEmpty {
            let lines = parseLRC(synced)
            if !lines.isEmpty { return Lyrics(lines: lines, synced: true) }
        }
        if let plain = reply.plainLyrics, !plain.isEmpty {
            let lines = plain.components(separatedBy: "\n").enumerated().map { Line(id: $0.offset, time: 0, text: $0.element) }
            return Lyrics(lines: lines, synced: false)
        }
        return nil
    }

    /// `[mm:ss.xx] words` lines, in time order.
    static func parseLRC(_ text: String) -> [Line] {
        var lines: [(TimeInterval, String)] = []
        for raw in text.components(separatedBy: "\n") {
            guard let close = raw.firstIndex(of: "]"), raw.hasPrefix("[") else { continue }
            let stamp = raw[raw.index(after: raw.startIndex)..<close]
            let parts = stamp.split(separator: ":")
            guard parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) else { continue }
            lines.append((minutes * 60 + seconds, String(raw[raw.index(after: close)...]).trimmingCharacters(in: .whitespaces)))
        }
        return lines.sorted { $0.0 < $1.0 }.enumerated().map { Line(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }
}
