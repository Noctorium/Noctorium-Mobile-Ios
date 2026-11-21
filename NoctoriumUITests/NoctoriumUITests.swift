import XCTest

/// The app in the simulator, as somebody would use it: Home, a search, a song played, Now playing and its lyrics,
/// with a picture of each kept in the test results.
final class NoctoriumUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launch()
    }

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testSearchPlayAndNowPlaying() throws {
        // Home's rows come from the network.
        _ = app.buttons.matching(identifier: "track-row").firstMatch.waitForExistence(timeout: 20)
        snap("1-home")

        app.tabBars.buttons["Search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("daft punk\n")
        let song = app.buttons.matching(identifier: "track-row").firstMatch
        XCTAssertTrue(song.waitForExistence(timeout: 30), "no songs came back")
        snap("2-search")

        song.tap()
        let mini = app.otherElements["mini-player"]
        XCTAssertTrue(mini.waitForExistence(timeout: 10))
        let playing = NSPredicate(format: "value == 'playing'")
        expectation(for: playing, evaluatedWith: mini)
        waitForExpectations(timeout: 45)
        sleep(4)
        snap("3-playing")

        mini.staticTexts.firstMatch.tap()
        XCTAssertTrue(app.buttons["play-pause"].waitForExistence(timeout: 10))
        sleep(2)
        snap("4-now-playing")

        app.buttons["Lyrics"].tap()
        sleep(6)
        snap("5-lyrics")
    }
}
