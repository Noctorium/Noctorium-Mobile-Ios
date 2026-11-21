import AVFoundation
import Combine
import MediaPlayer
import UIKit

/// The one player: a queue, the song playing in it, and AVPlayer. Plays on with the screen locked, and answers the lock
/// screen, Control Center, headphones and CarPlay's Now Playing through Apple's own media controls.
@MainActor
final class Player: ObservableObject {
    @Published private(set) var queue: [Track] = []
    @Published private(set) var index = -1
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    /// When the music stops by itself: a time, or the end of the song playing.
    @Published private(set) var sleepAt: Date?
    @Published private(set) var sleepAtEndOfSong = false

    var current: Track? { queue.indices.contains(index) ? queue[index] : nil }
    var upNext: ArraySlice<Track> { index + 1 < queue.count ? queue[(index + 1)...] : [] }

    let store: Store
    private let player = AVPlayer()
    private var timeObserver: Any?
    private var itemObservers: [AnyCancellable] = []
    private var loadTask: Task<Void, Never>?
    private var sleepTimer: Timer?
    private var artwork: (url: URL, image: MPMediaItemArtwork)?

    init(store: Store) {
        self.store = store
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
        player.automaticallyWaitsToMinimizeStalling = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in self?.ticked(time.seconds) }
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let began = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
            Task { @MainActor in if began { self?.pause() } }
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            // Headphones pulled out: pause, as every player does, rather than play out loud.
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
            Task { @MainActor in if reason { self?.pause() } }
        }
        remoteCommands()
    }

    // MARK: - Playing

    func play(_ tracks: [Track], from start: Int = 0) {
        guard !tracks.isEmpty else { return }
        queue = tracks
        index = min(max(start, 0), tracks.count - 1)
        load()
    }

    func shuffle(_ tracks: [Track]) { play(tracks.shuffled()) }

    func playNext(_ track: Track) {
        guard current != nil else { return play([track]) }
        queue.insert(track, at: index + 1)
    }

    func addToQueue(_ track: Track) {
        guard current != nil else { return play([track]) }
        queue.append(track)
    }

    func jump(to i: Int) {
        guard queue.indices.contains(i) else { return }
        index = i
        load()
    }

    func removeFromQueue(at offsets: IndexSet) {
        // Offsets count from the song after the one playing.
        let absolute = IndexSet(offsets.map { $0 + index + 1 })
        queue.remove(atOffsets: absolute)
    }

    func toggle() {
        if isPlaying { pause() } else { resume() }
    }

    func resume() {
        guard current != nil else { return }
        if player.currentItem == nil { return load() }
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        isPlaying = true
        nowPlaying()
    }

    func pause() {
        player.pause()
        isPlaying = false
        nowPlaying()
    }

    func next() {
        if sleepAtEndOfSong { sleepAtEndOfSong = false; pause(); return }
        if index + 1 < queue.count {
            index += 1
            load()
        } else {
            Task { await extend(); if index + 1 < queue.count { index += 1; load() } else { pause() } }
        }
    }

    /// Back to the start once a song is a few seconds in, as every player does; before that, the song before.
    func previous() {
        if position > 5 || index == 0 { seek(to: 0) } else { index -= 1; load() }
    }

    func seek(to seconds: TimeInterval) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        position = seconds
        nowPlaying()
    }

    private func load() {
        guard let track = current else { return }
        loadTask?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
        itemObservers = []
        isLoading = true; isPlaying = false; error = nil
        position = 0; duration = track.duration
        store.played(track)
        nowPlaying()
        loadTask = Task {
            do {
                let (url, headers) = try await address(track)
                guard !Task.isCancelled, current == track else { return }
                start(url, headers: headers)
            } catch {
                guard !Task.isCancelled, current == track else { return }
                failed(error.localizedDescription)
            }
        }
    }

    /// Where a song's audio is. YouTube's is asked of YouTube here; SoundCloud's of the API, and a SoundCloud track
    /// that is locked to its own app plays as the same recording on YouTube Music, as the full Noctorium does.
    private func address(_ track: Track) async throws -> (URL, [String: String]) {
        if track.isYouTube {
            let stream = try await YouTube.stream(track.id)
            return (stream.url, ["User-Agent": stream.userAgent])
        }
        if let url = try? await API.soundCloudStream(track.id) { return (url, [:]) }
        for match in try await sameOnYouTubeMusic(track) {
            if let stream = try? await YouTube.stream(match.id) { return (stream.url, ["User-Agent": stream.userAgent]) }
        }
        throw ServiceError(message: "SoundCloud would not play this, and YouTube Music does not have it")
    }

    private func sameOnYouTubeMusic(_ track: Track) async throws -> [Track] {
        let words = "\(track.title) \(track.artistLine)".replacingOccurrences(of: "[\\[\\](){}]", with: " ", options: .regularExpression)
        let found = try await API.search(words, mode: .youTubeMusic, kind: .songs).tracks.filter(\.isYouTube)
        guard track.duration > 0 else { return Array(found.prefix(3)) }
        return Array(found.filter { abs($0.duration - track.duration) < 10 }.sorted { abs($0.duration - track.duration) < abs($1.duration - track.duration) }.prefix(3))
    }

    private func start(_ url: URL, headers: [String: String]) {
        let asset = AVURLAsset(url: url, options: headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        itemObservers = [
            item.publisher(for: \.status).receive(on: RunLoop.main).sink { [weak self] status in
                guard let self else { return }
                if status == .readyToPlay {
                    self.isLoading = false
                    let seconds = item.duration.seconds
                    if seconds.isFinite, seconds > 0 { self.duration = seconds }
                    self.nowPlaying()
                } else if status == .failed {
                    self.failed(item.error?.localizedDescription ?? "This song would not play")
                }
            },
            NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item).receive(on: RunLoop.main).sink { [weak self] _ in
                self?.next()
            },
        ]
        player.replaceCurrentItem(with: item)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        isPlaying = true
        nowPlaying()
    }

    /// A song that will not play is said so and skipped, rather than the music stopping.
    private func failed(_ why: String) {
        isLoading = false; isPlaying = false; error = why
        nowPlaying()
        let failedAt = index
        guard index + 1 < queue.count else { return }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if self.index == failedAt, self.error == why { self.next() }
        }
    }

    /// More songs like the last one, from its own service's radio, when the queue runs out.
    private var extending = false

    private func extend() async {
        guard store.autoplay, !extending, let last = queue.last else { return }
        extending = true
        defer { extending = false }
        let more = (try? await API.radio(last)) ?? []
        let known = Set(queue.map(\.key))
        queue.append(contentsOf: more.filter { !known.contains($0.key) }.prefix(25))
    }

    private func ticked(_ seconds: Double) {
        guard seconds.isFinite else { return }
        position = seconds
        if let sleepAt, Date() >= sleepAt { self.sleepAt = nil; pause() }
        // Lines up more once the last song in the queue is nearly over, so autoplay carries straight on.
        if index == queue.count - 1, duration > 0, duration - seconds < 15, store.autoplay, !extending {
            Task { await extend() }
        }
    }

    // MARK: - Sleep timer

    func sleep(minutes: Int?) {
        sleepAtEndOfSong = false
        sleepAt = minutes.map { Date().addingTimeInterval(TimeInterval($0 * 60)) }
    }

    func sleepAfterThisSong() { sleepAt = nil; sleepAtEndOfSong = true }

    // MARK: - Lock screen and Control Center

    private func remoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        center.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        center.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        center.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func nowPlaying() {
        guard let track = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artistLine,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let artwork, artwork.url == track.artwork { info[MPMediaItemPropertyArtwork] = artwork.image }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        if let url = track.artwork, artwork?.url != url {
            Task {
                guard let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) else { return }
                self.artwork = (url, MPMediaItemArtwork(boundsSize: image.size) { _ in image })
                if self.current?.artwork == url { self.nowPlaying() }
            }
        }
    }
}
