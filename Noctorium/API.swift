import Foundation

struct ServiceError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

/// The hosted web player's API, which reads YouTube Music and SoundCloud and answers in small JSON lists.
enum API {
    static let base = "https://noctorium-music.vercel.app/api/music"

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.urlCache = URLCache(memoryCapacity: 4 << 20, diskCapacity: 0)
        return URLSession(configuration: config)
    }()

    private struct Failure: Decodable { var error: String? }

    private static func get<T: Decodable>(_ query: [URLQueryItem], as type: T.Type) async throws -> T {
        var parts = URLComponents(string: base)!
        let region = Locale.current.region?.identifier ?? "US"
        parts.queryItems = query + [URLQueryItem(name: "hl", value: "en"), URLQueryItem(name: "gl", value: region.count == 2 ? region : "US")]
        let (data, _) = try await session.data(from: parts.url!)
        if let failure = try? JSONDecoder().decode(Failure.self, from: data), let message = failure.error {
            throw ServiceError(message: message)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func search(_ query: String, mode: SearchMode, kind: SearchKind) async throws -> SearchResults {
        var items = [URLQueryItem(name: "op", value: "search"), URLQueryItem(name: "q", value: query), URLQueryItem(name: "mode", value: mode.rawValue)]
        if kind == .playlists { items.append(URLQueryItem(name: "kind", value: "PLAYLISTS")) }
        return try await get(items, as: SearchResults.self)
    }

    private struct HomeReply: Decodable { var sections: [HomeSection] }

    static func home() async throws -> [HomeSection] {
        try await get([URLQueryItem(name: "op", value: "home")], as: HomeReply.self).sections
            .filter { !$0.tracks.isEmpty || !$0.playlists.isEmpty }
    }

    struct PlaylistReply: Decodable { var title: String?; var tracks: [Track]?; var ownerName: String? }

    static func playlist(_ key: String) async throws -> PlaylistReply {
        try await get([URLQueryItem(name: "op", value: "playlist"), URLQueryItem(name: "key", value: key)], as: PlaylistReply.self)
    }

    private struct TracksReply: Decodable { var tracks: [Track] }

    /// Songs like this one, for autoplay once the queue runs out.
    static func radio(_ track: Track) async throws -> [Track] {
        try await get([URLQueryItem(name: "op", value: "radio"), URLQueryItem(name: "key", value: track.key)], as: TracksReply.self).tracks
    }

    struct Opened: Decodable {
        var track: Track?
        var playlist: PlaylistKey?
        struct PlaylistKey: Decodable { var key: String }
    }

    /// A YouTube, YouTube Music or SoundCloud link: a song to play or a playlist to open.
    static func link(_ url: String) async throws -> Opened {
        try await get([URLQueryItem(name: "op", value: "link"), URLQueryItem(name: "url", value: url)], as: Opened.self)
    }

    private struct StreamReply: Decodable { var url: String }

    /// A SoundCloud track's audio: an MP3 or an AAC stream, both of which AVPlayer plays.
    static func soundCloudStream(_ id: String) async throws -> URL {
        let reply = try await get([URLQueryItem(name: "op", value: "stream"), URLQueryItem(name: "id", value: id)], as: StreamReply.self)
        guard let url = URL(string: reply.url) else { throw ServiceError(message: "SoundCloud sent no address") }
        return url
    }
}
