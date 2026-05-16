import XCTest
@testable import Musique

final class MusiqueTests: XCTestCase {
    func testSnapshotPlayingFlag() {
        let snap = NowPlayingSnapshot(
            state: "playing", title: "Song", artist: "Artist", album: "Album",
            duration: 200, position: 30, persistentID: "abc"
        )
        XCTAssertTrue(snap.isPlaying)
        XCTAssertTrue(snap.hasTrack)
    }
}
