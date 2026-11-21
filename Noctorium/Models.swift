import Foundation

/// A song, in the shape the hosted API answers with (the web player's `Track`).
struct Track: Codable, Identifiable, Hashable {
    var provider: String
    var id: String
    var title: String
    var artistLine: String
    var artworkUrl: String?
    var durationMs: Double?
    var sourceUrl: String?

    /// One song on one service: the same id on two services is two songs.
    var key: String { "\(provider):\(id)" }
    var isYouTube: Bool { provider.hasPrefix("YOUTUBE") }
    var duration: TimeInterval { (durationMs ?? 0) / 1000 }
    var artwork: URL? { artworkUrl.flatMap(URL.init(string:)) }

    var serviceName: String {
        switch provider {
        case "SOUNDCLOUD": return "SoundCloud"
        case "YOUTUBE_VIDEO": return "YouTube"
        case "YOUTUBE_MUSIC": return "YouTube Music"
        default: return provider.capitalized
        }
    }

    private enum CodingKeys: String, CodingKey { case provider, id, title, artistLine, artists, artworkUrl, durationMs, sourceUrl }
    private struct Artist: Codable { var name: String }

    init(provider: String, id: String, title: String, artistLine: String, artworkUrl: String?, durationMs: Double?, sourceUrl: String?) {
        self.provider = provider; self.id = id; self.title = title; self.artistLine = artistLine
        self.artworkUrl = artworkUrl; self.durationMs = durationMs; self.sourceUrl = sourceUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider = try c.decode(String.self, forKey: .provider)
        id = try c.decode(String.self, forKey: .id)
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        let artists = (try? c.decode([Artist].self, forKey: .artists))?.map(\.name).joined(separator: ", ")
        artistLine = (try? c.decode(String.self, forKey: .artistLine)) ?? artists ?? ""
        artworkUrl = try? c.decode(String.self, forKey: .artworkUrl)
        durationMs = try? c.decode(Double.self, forKey: .durationMs)
        sourceUrl = try? c.decode(String.self, forKey: .sourceUrl)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(provider, forKey: .provider)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(artistLine, forKey: .artistLine)
        try c.encodeIfPresent(artworkUrl, forKey: .artworkUrl)
        try c.encodeIfPresent(durationMs, forKey: .durationMs)
        try c.encodeIfPresent(sourceUrl, forKey: .sourceUrl)
    }

    static func == (a: Track, b: Track) -> Bool { a.key == b.key }
    func hash(into hasher: inout Hasher) { hasher.combine(key) }
}

/// A playlist or an album on a service, opened by its key (`yt:…`, `sc:…`).
struct Playlist: Codable, Identifiable, Hashable {
    var key: String
    var title: String
    var ownerName: String?
    var artworkUrl: String?
    var trackCount: Int?
    var id: String { key }
    var artwork: URL? { artworkUrl.flatMap(URL.init(string:)) }
}

/// An album from a search, which opens as a playlist.
struct Album: Codable {
    var id: String
    var title: String
    var artworkUrl: String?
    var artists: [ArtistName]?
    struct ArtistName: Codable { var name: String }

    var asPlaylist: Playlist {
        Playlist(key: id, title: title, ownerName: artists?.map(\.name).joined(separator: ", "), artworkUrl: artworkUrl, trackCount: nil)
    }
}

struct HomeSection: Codable, Identifiable {
    var id: String?
    var title: String
    var tracks: [Track]
    var playlists: [Playlist]
    var identity: String { id ?? title }
}

struct SearchResults: Codable {
    var tracks: [Track]
    var playlists: [Playlist]
    var albums: [Album]?
}

/// A playlist of the listener's own, kept on the phone.
struct LocalPlaylist: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String
    var tracks: [Track] = []
}

enum SearchMode: String, CaseIterable, Identifiable, Codable {
    case hybrid = "HYBRID", youTubeMusic = "YOUTUBE_MUSIC", soundCloud = "SOUNDCLOUD"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .hybrid: return "Both"
        case .youTubeMusic: return "YouTube Music"
        case .soundCloud: return "SoundCloud"
        }
    }
}

enum SearchKind: String, CaseIterable, Identifiable {
    case songs = "Songs", playlists = "Playlists"
    var id: String { rawValue }
}

func formatTime(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    let s = Int(seconds)
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
}
