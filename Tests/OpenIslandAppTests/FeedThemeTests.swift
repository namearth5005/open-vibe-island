import Foundation
import OpenIslandCore
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

/// Spec §7.5. Every text token on every skin clears WCAG AA for small text;
/// the status dot is a non-text graphic and clears 3:1. If a future tweak
/// drops one below its bar, this fails instead of shipping.
struct FeedThemeContrastTests {
    private let textBar = 4.5
    private let graphicBar = 3.0

    @Test(arguments: IslandTheme.allCases)
    func everyTextTokenClearsAA(theme: IslandTheme) {
        let t = FeedTheme.resolve(theme)
        let reading = t.surface ?? t.ground

        #expect(t.text.contrast(against: reading) >= textBar)
        #expect(t.dim.contrast(against: reading) >= textBar)
        #expect(t.faint.contrast(against: reading) >= textBar)
    }

    @Test(arguments: IslandTheme.allCases)
    func everyStatusTintClearsAA(theme: IslandTheme) {
        let t = FeedTheme.resolve(theme)
        let reading = t.surface ?? t.ground

        for phase in SessionPhase.allCases {
            let tint = t.ink(for: phase)
            #expect(
                tint.contrast(against: reading) >= textBar,
                "\(theme.rawValue)/\(phase) = \(tint.contrast(against: reading))"
            )
        }
    }

    /// The header's status dot sits on the panel ground, not the reading
    /// surface -- on Cream card those are different colours.
    @Test(arguments: IslandTheme.allCases)
    func statusDotClearsGraphicBarOnTheGround(theme: IslandTheme) {
        let t = FeedTheme.resolve(theme)
        for phase in SessionPhase.allCases {
            #expect(t.headerInk(for: phase).contrast(against: t.ground) >= graphicBar)
        }
    }

    /// Regression guard for the defect this round fixes: the shipped `faint`
    /// tier measured 2.74:1.
    @Test
    func faintTierIsNoLongerBelowAA() {
        let t = FeedTheme.resolve(.inkPaper)
        #expect(t.faint.contrast(against: t.ground) > 4.5)
    }
}

struct FeedThemeResolutionTests {
    /// Cream card is the only skin with an inner reading surface. The other two
    /// read directly on their ground.
    @Test
    func onlyCreamCardHasASeparateSurface() {
        #expect(FeedTheme.resolve(.inkPaper).surface == nil)
        #expect(FeedTheme.resolve(.fullCream).surface == nil)
        #expect(FeedTheme.resolve(.creamCard).surface != nil)
    }

    @Test
    func inkSkinsKeepTheExistingStatusTints() {
        let t = FeedTheme.resolve(.inkPaper)
        #expect(t.ink(for: .running) == FeedInk(hex: 0x6e_a7_ff))
    }

    @Test
    func paperSkinsUseTheirOwnTints() {
        let t = FeedTheme.resolve(.fullCream)
        #expect(t.ink(for: .running) != FeedInk(hex: 0x6e_a7_ff))
    }
}

@MainActor
struct IslandThemePreferenceTests {
    @Test
    func defaultsToInkPaper() {
        UserDefaults.standard.removeObject(forKey: "app.islandTheme")
        #expect(AppModel().islandTheme == .inkPaper)
    }

    @Test
    func roundTripsThroughUserDefaults() {
        let model = AppModel()
        model.islandTheme = .creamCard
        #expect(UserDefaults.standard.string(forKey: "app.islandTheme") == "creamCard")

        UserDefaults.standard.removeObject(forKey: "app.islandTheme")
    }

    /// An unknown or corrupted value must not strand the panel on a skin that
    /// does not exist.
    @Test
    func unknownStoredValueFallsBackToTheDefault() {
        UserDefaults.standard.set("chartreuse", forKey: "app.islandTheme")
        #expect(AppModel().islandTheme == .inkPaper)

        UserDefaults.standard.removeObject(forKey: "app.islandTheme")
    }
}
