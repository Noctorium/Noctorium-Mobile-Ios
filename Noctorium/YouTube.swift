import Foundation

/// A YouTube song's audio address, asked for on this phone: YouTube hands its addresses out for the device that asks,
/// so the hosted API cannot ask for it. It asks as the clients yt-dlp uses for the same reason -- visionOS first, then
/// Android VR -- which answer with plain addresses, with no JavaScript to run and no token to make.
enum YouTube {
    struct Stream { var url: URL; var userAgent: String }

    private struct Client {
        var name: String
        var number: Int
        var version: String
        var userAgent: String
        var extra: [String: Any]
    }

    private static let clients = [
        Client(name: "VISIONOS", number: 101, version: "1.02",
               userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15",
               extra: ["deviceMake": "Apple", "deviceModel": "RealityDevice17,1", "osName": "visionOS", "osVersion": "26.5.23O471"]),
        Client(name: "ANDROID_VR", number: 28, version: "1.65.10",
               userAgent: "com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip",
               extra: ["deviceMake": "Oculus", "deviceModel": "Quest 3", "androidSdkVersion": 32, "osName": "Android", "osVersion": "12L"]),
    ]

    /// Who this phone is to YouTube, as a browser's first visit would be told; without it YouTube takes the request for
    /// a bot. Read once from the small file YouTube's own pages read it from.
    private static var visitor: String?

    private static func visitorData() async -> String? {
        if let visitor { return visitor }
        var request = URLRequest(url: URL(string: "https://www.youtube.com/sw.js_data")!)
        request.setValue(clients[0].userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request), let text = String(data: data, encoding: .utf8) else { return nil }
        guard let range = text.range(of: #""(Cg[A-Za-z0-9_%=-]{20,})""#, options: .regularExpression) else { return nil }
        let found = String(text[range].dropFirst().dropLast())
        visitor = found
        return found
    }

    static func stream(_ videoId: String) async throws -> Stream {
        var why = "YouTube would not play this song"
        let visitorData = await visitorData()
        for client in clients {
            do {
                var context: [String: Any] = ["clientName": client.name, "clientVersion": client.version, "hl": "en", "gl": "US", "userAgent": client.userAgent]
                client.extra.forEach { context[$0.key] = $0.value }
                if let visitorData { context["visitorData"] = visitorData }
                let body: [String: Any] = ["context": ["client": context], "videoId": videoId, "contentCheckOk": true, "racyCheckOk": true]
                var request = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false")!)
                request.httpMethod = "POST"
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")
                request.setValue(String(client.number), forHTTPHeaderField: "X-YouTube-Client-Name")
                request.setValue(client.version, forHTTPHeaderField: "X-YouTube-Client-Version")
                request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
                if let visitorData { request.setValue(visitorData, forHTTPHeaderField: "X-Goog-Visitor-Id") }
                let (data, _) = try await URLSession.shared.data(for: request)
                guard let reply = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                if let status = reply["playabilityStatus"] as? [String: Any], (status["status"] as? String) != "OK" {
                    why = (status["reason"] as? String) ?? why
                    continue
                }
                let formats = ((reply["streamingData"] as? [String: Any])?["adaptiveFormats"] as? [[String: Any]]) ?? []
                if let url = pick(formats) { return Stream(url: url, userAgent: client.userAgent) }
            } catch {
                why = error.localizedDescription
            }
        }
        throw ServiceError(message: why)
    }

    /// The best audio-only AAC format with a plain address: what AVPlayer plays everywhere.
    static func pick(_ formats: [[String: Any]]) -> URL? {
        let audio = formats.filter { (($0["mimeType"] as? String) ?? "").hasPrefix("audio/mp4") && $0["url"] != nil }
        let best = audio.max { (($0["bitrate"] as? Int) ?? 0) < (($1["bitrate"] as? Int) ?? 0) }
        return (best?["url"] as? String).flatMap(URL.init(string:))
    }
}
