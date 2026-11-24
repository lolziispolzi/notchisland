import XCTest
@testable import NotchIsland

final class NotchGeometryTests: XCTestCase {
    // 14" MacBook Pro-like layout: 1512 wide, 186 pt notch.
    private let frame = NSRect(x: 0, y: 0, width: 1512, height: 982)

    private func notched() -> NotchGeometry {
        NotchGeometry.notched(screenFrame: frame, notchHeight: 32, leftAreaWidth: 663, rightAreaWidth: 663)
    }

    func testNotchRectFromAuxiliaryAreas() {
        XCTAssertEqual(notched().notchRect, NSRect(x: 663, y: 950, width: 186, height: 32))
        XCTAssertTrue(notched().hasNotch)
    }

    func testPanelIsCenteredOnNotchAndTouchesTop() {
        let g = notched()
        XCTAssertEqual(g.panelFrame.midX, g.notchRect.midX)
        XCTAssertEqual(g.panelFrame.maxY, frame.maxY)
        XCTAssertEqual(g.panelFrame.height, NotchGeometry.openSize.height)
    }

    func testHoverRectCoversNotchAndTopEdge() {
        let g = notched()
        XCTAssertTrue(g.hoverRect().contains(NSPoint(x: g.notchRect.midX, y: frame.maxY - 1)))
        XCTAssertFalse(g.hoverRect().contains(NSPoint(x: 100, y: frame.maxY - 1)))
    }

    func testHoverRectGrowsWithLiveActivity() {
        let g = notched()
        XCTAssertEqual(g.hoverRect(extraWidth: 80).width, g.hoverRect().width + 80)
        XCTAssertEqual(g.hoverRect(extraWidth: 80).midX, g.notchRect.midX)
    }

    func testOpenRectContainsHoverRect() {
        let g = notched()
        XCTAssertTrue(g.openRect.contains(g.hoverRect().insetBy(dx: 0, dy: 1)))
    }

    func testFakeNotchUsesMenuBarHeight() {
        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let visible = NSRect(x: 0, y: 0, width: 1920, height: 1055)
        let g = NotchGeometry.fake(screenFrame: screen, visibleFrame: visible)
        XCTAssertFalse(g.hasNotch)
        XCTAssertEqual(g.notchRect.height, 25)
        XCTAssertEqual(g.notchRect.midX, screen.midX)
        XCTAssertEqual(g.notchRect.maxY, screen.maxY)
    }
}

final class NotchShapeTests: XCTestCase {
    func testPathFillsRect() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 32)
        let path = NotchShape(topRadius: 6, bottomRadius: 10).path(in: rect)
        XCTAssertEqual(path.boundingRect, rect)
    }
}

final class PlaybackUpdateTests: XCTestCase {
    func testSpotifyNotification() {
        let info: [AnyHashable: Any] = [
            "Player State": "Playing",
            "Name": "Song",
            "Artist": "Artist",
            "Album": "Album",
            "Duration": NSNumber(value: 215_000),
            "Playback Position": NSNumber(value: 12.5),
        ]
        let update = PlaybackUpdate.from(userInfo: info, player: .spotify)
        XCTAssertEqual(update.state, .playing)
        XCTAssertEqual(update.track, Track(title: "Song", artist: "Artist", album: "Album", duration: 215))
        XCTAssertEqual(update.position, 12.5)
    }

    func testMusicNotification() {
        let info: [AnyHashable: Any] = [
            "Player State": "Paused",
            "Name": "Song",
            "Artist": "Artist",
            "Total Time": NSNumber(value: 180_000),
        ]
        let update = PlaybackUpdate.from(userInfo: info, player: .music)
        XCTAssertEqual(update.state, .paused)
        XCTAssertEqual(update.track?.duration, 180)
        XCTAssertEqual(update.track?.album, "")
        XCTAssertNil(update.position)
    }

    func testStoppedNotification() {
        XCTAssertEqual(PlaybackUpdate.from(userInfo: ["Player State": "Stopped"], player: .music), .stopped)
    }

    func testScriptOutputMusicWithCommaDecimals() {
        let output = "playing\nSong\nArtist\nAlbum\n245,3\n10,5"
        let update = PlaybackUpdate.from(scriptOutput: output, player: .music)
        XCTAssertEqual(update?.state, .playing)
        XCTAssertEqual(update?.track?.duration, 245.3)
        XCTAssertEqual(update?.position, 10.5)
    }

    func testScriptOutputSpotifyDurationInMilliseconds() {
        let output = "paused\nSong\nArtist\nAlbum\n200000\n3.0"
        XCTAssertEqual(PlaybackUpdate.from(scriptOutput: output, player: .spotify)?.track?.duration, 200)
    }

    func testScriptOutputStoppedAndGarbage() {
        XCTAssertEqual(PlaybackUpdate.from(scriptOutput: "stopped", player: .music), .stopped)
        XCTAssertNil(PlaybackUpdate.from(scriptOutput: "nonsense", player: .music))
    }
}

final class FormattingTests: XCTestCase {
    func testTimeFormat() {
        XCTAssertEqual(TimeFormat.string(0), "0:00")
        XCTAssertEqual(TimeFormat.string(-3), "0:00")
        XCTAssertEqual(TimeFormat.string(.nan), "0:00")
        XCTAssertEqual(TimeFormat.string(65.9), "1:05")
        XCTAssertEqual(TimeFormat.string(3723), "1:02:03")
    }

    func testBatterySymbols() {
        XCTAssertEqual(BatteryInfo(percent: 5, isCharging: false, isPluggedIn: false).symbolName, "battery.0percent")
        XCTAssertEqual(BatteryInfo(percent: 50, isCharging: false, isPluggedIn: false).symbolName, "battery.50percent")
        XCTAssertEqual(BatteryInfo(percent: 95, isCharging: false, isPluggedIn: false).symbolName, "battery.100percent")
        XCTAssertEqual(BatteryInfo(percent: 40, isCharging: true, isPluggedIn: true).symbolName, "battery.100percent.bolt")
        XCTAssertTrue(BatteryInfo(percent: 15, isCharging: false, isPluggedIn: false).isLow)
        XCTAssertFalse(BatteryInfo(percent: 15, isCharging: true, isPluggedIn: true).isLow)
    }
}
