import Foundation

/// What the listener keeps: liked songs, what they played lately, their own playlists and their settings. On the phone
/// only, as JSON in the app's own folder.
@MainActor
final class Store: ObservableObject {
    @Published private(set) var liked: [Track] = []
    @Published private(set) var recent: [Track] = []
    @Published private(set) var playlists: [LocalPlaylist] = []
    @Published var searchMode: SearchMode = .hybrid { didSet { save() } }
    @Published var autoplay: Bool = true { didSet { save() } }

    private struct Saved: Codable {
        var liked: [Track] = []
        var recent: [Track] = []
        var playlists: [LocalPlaylist] = []
        var searchMode: SearchMode = .hybrid
        var autoplay: Bool = true
    }

    private let file: URL = {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("noctorium.json")
    }()
    private var loading = true

    init() {
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            liked = saved.liked; recent = saved.recent; playlists = saved.playlists
            searchMode = saved.searchMode; autoplay = saved.autoplay
        }
        loading = false
    }

    private func save() {
        guard !loading else { return }
        let saved = Saved(liked: liked, recent: recent, playlists: playlists, searchMode: searchMode, autoplay: autoplay)
        if let data = try? JSONEncoder().encode(saved) { try? data.write(to: file, options: .atomic) }
    }

    func isLiked(_ track: Track) -> Bool { liked.contains(track) }

    func toggleLike(_ track: Track) {
        if let i = liked.firstIndex(of: track) { liked.remove(at: i) } else { liked.insert(track, at: 0) }
        save()
    }

    func played(_ track: Track) {
        recent.removeAll { $0 == track }
        recent.insert(track, at: 0)
        recent = Array(recent.prefix(50))
        save()
    }

    func clearHistory() { recent = []; save() }

    @discardableResult
    func createPlaylist(_ title: String) -> LocalPlaylist {
        let playlist = LocalPlaylist(title: title.isEmpty ? "New playlist" : title)
        playlists.insert(playlist, at: 0)
        save()
        return playlist
    }

    func add(_ track: Track, to playlist: LocalPlaylist) {
        guard let i = playlists.firstIndex(where: { $0.id == playlist.id }), !playlists[i].tracks.contains(track) else { return }
        playlists[i].tracks.append(track)
        save()
    }

    func remove(at offsets: IndexSet, from playlist: LocalPlaylist) {
        guard let i = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[i].tracks.remove(atOffsets: offsets)
        save()
    }

    func rename(_ playlist: LocalPlaylist, to title: String) {
        guard let i = playlists.firstIndex(where: { $0.id == playlist.id }), !title.isEmpty else { return }
        playlists[i].title = title
        save()
    }

    func delete(_ playlist: LocalPlaylist) {
        playlists.removeAll { $0.id == playlist.id }
        save()
    }

    func playlist(_ id: UUID) -> LocalPlaylist? { playlists.first { $0.id == id } }
}
