import Combine
import Foundation
import Security
import UIKit

/// Whether a listen counts, as every Noctorium counts it: half a minute, or half the song if it is shorter.
func listenCounts(heard: TimeInterval, duration: TimeInterval) -> Bool {
    heard >= (duration > 0 ? min(duration / 2, 30) : 30)
}

/// The Noctorium account: signed in from the browser with a code -- Discord, Telegram or email, on the
/// account service's own page -- as every Noctorium signs in. Once signed in, what is played here is counted, and what
/// is playing is said, for the listener's Discord status and Telegram bio. The token is kept in the Keychain.
@MainActor
final class Account: ObservableObject {
    static let service = URL(string: "https://service.noctorium.xyz")!

    @Published private(set) var name = UserDefaults.standard.string(forKey: "account.name") ?? ""
    @Published private(set) var streams = 0
    @Published private(set) var code: String?
    @Published private(set) var pageURL: URL?
    @Published private(set) var message: String?
    @Published private(set) var token: String? = Keychain.read()

    var signedIn: Bool { token != nil }

    private let player: Player
    private var waiting: Task<Void, Never>?
    private var watching: [AnyCancellable] = []

    init(player: Player) {
        self.player = player
        // What was heard: the player's clock moving forward while it plays, not a jump from a seek.
        player.$position.sink { [weak self] seconds in Task { @MainActor in self?.ticked(seconds) } }.store(in: &watching)
        player.$index.combineLatest(player.$isPlaying).sink { [weak self] _, _ in
            Task { @MainActor in self?.playingChanged() }
        }.store(in: &watching)
        if signedIn { Task { await refresh() } }
    }

    // MARK: - The service

    private func call(_ path: String, body: Any? = nil) async -> (Int, [String: Any])? {
        var request = URLRequest(url: URL(string: path, relativeTo: Self.service)!)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        guard let reply = try? await URLSession.shared.data(for: request),
              let status = (reply.1 as? HTTPURLResponse)?.statusCode else { return nil }
        return (status, (try? JSONSerialization.jsonObject(with: reply.0)) as? [String: Any] ?? [:])
    }

    private func refresh() async {
        if let me = await call("/api/auth/me"), me.0 == 401 {
            return signOut(because: "Your Noctorium sign-in ran out. Sign in again.")
        }
        if let stats = await call("/api/stats?range=all"), (200..<300).contains(stats.0) {
            streams = (stats.1["streams"] as? Int) ?? streams
        }
    }

    // MARK: - Signing in

    /// Signs in with a code: opens the service's page, where the listener signs in and presses Allow, and waits.
    func signIn() {
        guard !signedIn, waiting == nil else { return }
        message = nil
        waiting = Task {
            defer { waiting = nil }
            guard let reply = await call("/api/auth/device", body: [String: String]()), (200..<300).contains(reply.0),
                  case let start = reply.1, let code = start["code"] as? String, let poll = start["pollToken"] as? String,
                  let page = (start["url"] as? String).flatMap(URL.init(string:)) else {
                message = "The Noctorium service could not be reached. Try again."
                return
            }
            self.code = code
            pageURL = page
            _ = await UIApplication.shared.open(page)
            let until = Date().addingTimeInterval(TimeInterval((start["expiresIn"] as? Int) ?? 600))
            let every = UInt64(min(max((start["interval"] as? Int) ?? 3, 1), 30)) * 1_000_000_000
            let query = poll.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? poll
            defer { self.code = nil; pageURL = nil }
            while Date() < until {
                try? await Task.sleep(nanoseconds: every)
                if Task.isCancelled { return }
                guard let reply = await call("/api/auth/device/poll?token=\(query)"), reply.0 != 202, reply.0 < 500 else { continue }
                let (status, said) = reply
                if (200..<300).contains(status), let token = said["token"] as? String, let user = said["user"] as? [String: Any] {
                    Keychain.save(token)
                    self.token = token
                    name = (user["displayName"] as? String) ?? ""
                    UserDefaults.standard.set(name, forKey: "account.name")
                    await refresh()
                } else {
                    message = (said["error"] as? String) ?? "That sign-in did not go through. Start again."
                }
                return
            }
            message = "The code expired. Start again for a new one."
        }
    }

    func cancel() {
        waiting?.cancel()
        waiting = nil
        code = nil
        pageURL = nil
    }

    func signOut(because why: String? = nil) {
        cancel()
        if token != nil { Task { _ = await call("/api/now-playing", body: ["track": NSNull()]) } }
        Keychain.delete()
        token = nil
        name = ""
        streams = 0
        reported = ""
        message = why
    }

    // MARK: - What is played: counted once it counts, and said while it plays

    private var heardKey = ""
    private var heard: TimeInterval = 0
    private var lastPosition: TimeInterval = 0
    private var startedAt = Date()
    private var counted = false

    private func ticked(_ seconds: TimeInterval) {
        guard let track = player.current else { return }
        if track.key != heardKey {
            heardKey = track.key; heard = 0; counted = false; startedAt = Date(); lastPosition = seconds
            return
        }
        let step = seconds - lastPosition
        lastPosition = seconds
        if player.isPlaying, step > 0, step < 2.5 { heard += step }
        guard signedIn, !counted, listenCounts(heard: heard, duration: player.duration) else { return }
        counted = true
        let play: [String: Any] = [
            "clientId": UUID().uuidString, "provider": track.provider, "trackId": track.id, "title": track.title,
            "artist": track.artistLine, "msPlayed": Int(heard * 1000), "playedAt": ISO8601DateFormatter().string(from: startedAt),
        ]
        Task {
            if let sent = await call("/api/plays", body: ["plays": [play]]), (200..<300).contains(sent.0) { await refresh() }
        }
    }

    private var reported = ""
    private var nowPlayingTask: Task<Void, Never>?

    /// What is playing, once it has settled for a few seconds -- skipping through songs is not worth a status each --
    /// and again every five minutes while it plays, as Discord's status lasts only so long.
    private func playingChanged() {
        guard signedIn else { return }
        let key = player.isPlaying ? (player.current?.key ?? "") : ""
        guard key != reported else { return }
        nowPlayingTask?.cancel()
        nowPlayingTask = Task {
            if !key.isEmpty { try? await Task.sleep(nanoseconds: 3_000_000_000) }
            while !Task.isCancelled {
                let track = player.isPlaying ? player.current : nil
                reported = track?.key ?? ""
                var now: Any = NSNull()
                if let track {
                    var t: [String: Any] = [
                        "title": track.title, "artist": track.artistLine, "provider": track.provider,
                        "durationMs": Int(player.duration * 1000), "positionMs": Int(player.position * 1000),
                    ]
                    t["artworkUrl"] = track.artworkUrl
                    t["url"] = track.sourceUrl
                    now = t
                }
                _ = await call("/api/now-playing", body: ["track": now])
                guard track != nil else { return }
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
            }
        }
    }
}

/// The account token, in the Keychain rather than in the app's settings file.
private enum Keychain {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "xyz.noctorium.account",
        kSecAttrAccount as String: "token",
    ]

    static func read() -> String? {
        var item: CFTypeRef?
        var ask = query
        ask[kSecReturnData as String] = true
        guard SecItemCopyMatching(ask as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String) {
        delete()
        var add = query
        add[kSecValueData as String] = Data(token.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func delete() { SecItemDelete(query as CFDictionary) }
}
