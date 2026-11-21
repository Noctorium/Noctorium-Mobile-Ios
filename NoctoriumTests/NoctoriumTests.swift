import XCTest
@testable import Noctorium

final class NoctoriumTests: XCTestCase {
    func testLRCLinesAreReadInTimeOrder() {
        let lines = Lyrics.parseLRC("[00:12.50] second\n[00:01.00] first\nno stamp\n[01:02.00] third")
        XCTAssertEqual(lines.map(\.text), ["first", "second", "third"])
        XCTAssertEqual(lines[2].time, 62, accuracy: 0.01)
        let lyrics = Lyrics(lines: lines, synced: true)
        XCTAssertEqual(lyrics.current(at: 13), 1)
        XCTAssertNil(lyrics.current(at: 0))
    }

    func testTrackReadsTheAPIsShape() throws {
        let json = #"{"key":"YOUTUBE_MUSIC:abc","provider":"YOUTUBE_MUSIC","id":"abc","title":"Song","artists":[{"id":"1","name":"A","provider":"YOUTUBE_MUSIC"},{"id":"2","name":"B","provider":"YOUTUBE_MUSIC"}],"durationMs":201000,"sourceUrl":"https://music.youtube.com/watch?v=abc"}"#
        let track = try JSONDecoder().decode(Track.self, from: Data(json.utf8))
        XCTAssertEqual(track.artistLine, "A, B")
        XCTAssertEqual(track.duration, 201)
        XCTAssertTrue(track.isYouTube)
        // Kept on the phone and read back the same.
        let again = try JSONDecoder().decode(Track.self, from: JSONEncoder().encode(track))
        XCTAssertEqual(again, track)
        XCTAssertEqual(again.artistLine, "A, B")
    }

    func testTheBestAACFormatIsPicked() {
        let formats: [[String: Any]] = [
            ["mimeType": "audio/webm; codecs=\"opus\"", "bitrate": 160_000, "url": "https://x/opus"],
            ["mimeType": "audio/mp4; codecs=\"mp4a.40.2\"", "bitrate": 130_000, "url": "https://x/aac-high"],
            ["mimeType": "audio/mp4; codecs=\"mp4a.40.5\"", "bitrate": 48_000, "url": "https://x/aac-low"],
            ["mimeType": "video/mp4", "bitrate": 900_000, "url": "https://x/video"],
        ]
        XCTAssertEqual(YouTube.pick(formats)?.absoluteString, "https://x/aac-high")
    }

    // The live services, from wherever the tests run.

    func testLiveSearchFindsSongsOnBothServices() async throws {
        let found = try await API.search("daft punk", mode: .hybrid, kind: .songs)
        XCTAssertFalse(found.tracks.isEmpty)
        XCTAssertTrue(found.tracks.contains { $0.isYouTube })
        XCTAssertTrue(found.tracks.contains { $0.provider == "SOUNDCLOUD" })
    }

    func testLiveYouTubeHandsOverAnAudioAddress() async throws {
        let stream = try await YouTube.stream("PzYrr7K1dvU")
        XCTAssertEqual(stream.url.host?.hasSuffix("googlevideo.com"), true)
    }
}
