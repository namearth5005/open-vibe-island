import Foundation
import Testing
@testable import OpenIslandApp

/// Agent prose is markdown; a transcript stores it verbatim. Without stripping,
/// the feed shows raw asterisks and backticks as characters — which is exactly
/// what the first live run looked like.
struct FeedTextTests {
    @Test
    func stripsBoldAndCode() {
        #expect(FeedText.plain("**It's live**, and it shows `AgentFeedView.swift`")
            == "It's live, and it shows AgentFeedView.swift")
    }

    @Test
    func flattensMultipleLinesIntoOne() {
        #expect(FeedText.plain("first line\nsecond line") == "first line second line")
    }

    @Test
    func dropsHeadingAndListMarkers() {
        #expect(FeedText.plain("## Heading\n- a point\n- another")
            == "Heading a point another")
    }

    @Test
    func leavesOrdinaryProseAlone() {
        let prose = "The diff comes from the transcript, not from git."
        #expect(FeedText.plain(prose) == prose)
    }

    @Test
    func trimsSurroundingWhitespace() {
        #expect(FeedText.plain("  \n  spaced  \n ") == "spaced")
    }
}
