import Foundation
import Testing
@testable import OpenIslandApp

/// Colour in this feature is measured, not asserted. The handoff shipped a
/// `faint` tier at 2.74:1 -- below AA for small text -- because the status
/// tints were measured and the alpha tiers beneath them were not. These tests
/// are what stop that recurring.
struct FeedInkTests {
    @Test
    func parsesHexIntoUnitComponents() {
        let ink = FeedInk(hex: 0xef_e7_d6)
        #expect(abs(ink.red - 0xef / 255.0) < 0.0001)
        #expect(abs(ink.green - 0xe7 / 255.0) < 0.0001)
        #expect(abs(ink.blue - 0xd6 / 255.0) < 0.0001)
    }

    /// Black on white is the defined maximum for WCAG 2.x.
    @Test
    func blackOnWhiteIsTwentyOneToOne() {
        let ratio = FeedInk(hex: 0x00_00_00).contrast(against: FeedInk(hex: 0xff_ff_ff))
        #expect(abs(ratio - 21.0) < 0.01)
    }

    @Test
    func contrastIsSymmetric() {
        let a = FeedInk(hex: 0x12_11_0f)
        let b = FeedInk(hex: 0xf1_ea_d9)
        #expect(abs(a.contrast(against: b) - b.contrast(against: a)) < 0.0001)
    }

    /// The tiers are composited before measuring, so the number is the colour
    /// that actually renders -- not the colour before the ground shows through.
    @Test
    func blendCompositesTowardTheGround() {
        let paper = FeedInk(hex: 0xf1_ea_d9)
        let ink = FeedInk(hex: 0x12_11_0f)
        #expect(FeedInk.blend(paper, over: ink, alpha: 1.0) == paper)
        #expect(FeedInk.blend(paper, over: ink, alpha: 0.0) == ink)

        let half = FeedInk.blend(paper, over: ink, alpha: 0.5)
        #expect(half.red > ink.red && half.red < paper.red)
    }
}
