import XCTest
@testable import MusicMate

final class MusicMateTests: XCTestCase {
    func testSnapshotPlayingFlag() {
        let snap = NowPlayingSnapshot(
            state: "playing", title: "Song", artist: "Artist", album: "Album",
            duration: 200, position: 30, persistentID: "abc"
        )
        XCTAssertTrue(snap.isPlaying)
        XCTAssertTrue(snap.hasTrack)
    }
}
