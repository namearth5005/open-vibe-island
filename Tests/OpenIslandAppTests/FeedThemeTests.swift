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

    /// The reading surface only. `everyChromeTokenClearsAAOnTheGround` covers
    /// the rest of the panel -- this one measures against `surface ?? ground`,
    /// so on Cream card it can only ever see the card body.
    @Test(arguments: IslandTheme.allCases)
    func everyTextTokenClearsAA(theme: IslandTheme) {
        let t = FeedTheme.resolve(theme)
        let reading = t.surface ?? t.ground

        #expect(t.text.contrast(against: reading) >= textBar)
        #expect(t.dim.contrast(against: reading) >= textBar)
        #expect(t.faint.contrast(against: reading) >= textBar)
    }

    /// The header and footer sit on `ground`, not on the reading surface.
    ///
    /// This is the assertion that was missing: with only the reading-surface
    /// test above, Cream card's chrome rendered in the card's own ink at
    /// 1.16:1 and the suite stayed green through a clean build, a passing run
    /// and a screenshot nobody had taken yet.
    @Test(arguments: IslandTheme.allCases)
    func everyChromeTokenClearsAAOnTheGround(theme: IslandTheme) {
        let t = FeedTheme.resolve(theme)

        #expect(
            t.chromeText.contrast(against: t.ground) >= textBar,
            "\(theme.rawValue)/chromeText = \(t.chromeText.contrast(against: t.ground))"
        )
        #expect(
            t.chromeDim.contrast(against: t.ground) >= textBar,
            "\(theme.rawValue)/chromeDim = \(t.chromeDim.contrast(against: t.ground))"
        )
        #expect(
            t.chromeFaint.contrast(against: t.ground) >= textBar,
            "\(theme.rawValue)/chromeFaint = \(t.chromeFaint.contrast(against: t.ground))"
        )
    }

    /// The status tints reach the chrome as text, not only as the dot: the
    /// header prints the phase word and the turn's diff totals, and the footer
    /// tints a pill per waiting agent. They carry the text bar there.
    @Test(arguments: IslandTheme.allCases)
    func everyChromeStatusTintClearsAAOnTheGround(theme: IslandTheme) {
        let t = FeedTheme.resolve(theme)

        for phase in SessionPhase.allCases {
            let tint = t.chromeInk(for: phase)
            #expect(
                tint.contrast(against: t.ground) >= textBar,
                "\(theme.rawValue)/\(phase) = \(tint.contrast(against: t.ground))"
            )
        }
    }

    /// Regression guard for the defect this round fixes: Cream card drew its
    /// header in `creamText` on the ink panel -- ink on ink, 1.16:1.
    @Test
    func creamCardChromeIsNoLongerTheCardsOwnInk() {
        let t = FeedTheme.resolve(.creamCard)

        #expect(t.chromeText != t.text)
        #expect(t.text.contrast(against: t.ground) < 1.5)
        #expect(t.chromeText.contrast(against: t.ground) > 10)
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
            #expect(t.chromeInk(for: phase).contrast(against: t.ground) >= graphicBar)
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

struct FeedThemeChromeResolutionTests {
    /// Only Cream card has two grounds. On the other two the chrome tier is
    /// the reading tier, so introducing it moved nothing there.
    @Test(arguments: [IslandTheme.inkPaper, IslandTheme.fullCream])
    func skinsWithoutACardShareOneTextTier(theme: IslandTheme) {
        let t = FeedTheme.resolve(theme)

        #expect(t.chromeText == t.text)
        #expect(t.chromeDim == t.dim)
        #expect(t.chromeFaint == t.faint)
    }

    /// The predicate the panel uses to decide whether a colour tuned for ink
    /// still works where it is putting it. Cream card is the interesting case:
    /// its reading surface is cream but its chrome stands on the ink panel, so
    /// it answers the same as Ink paper.
    @Test
    func chromeGroundIsLightOnlyWhereTheChromeStandsOnCream() {
        #expect(FeedTheme.resolve(.inkPaper).chromeGroundIsLight == false)
        #expect(FeedTheme.resolve(.creamCard).chromeGroundIsLight == false)
        #expect(FeedTheme.resolve(.fullCream).chromeGroundIsLight)
    }

    @Test
    func creamCardResolvesADistinctChromeTier() {
        let t = FeedTheme.resolve(.creamCard)

        #expect(t.chromeText != t.text)
        #expect(t.chromeDim != t.dim)
        #expect(t.chromeFaint != t.faint)
        // The chrome is the ink skin's own tier, not a third invention.
        #expect(t.chromeText == FeedTheme.resolve(.inkPaper).text)
        #expect(t.chromeDim == FeedTheme.resolve(.inkPaper).dim)
        #expect(t.chromeFaint == FeedTheme.resolve(.inkPaper).faint)
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
    /// Paper is the default because the reference's own utility panels are
    /// paper. The spec originally defaulted to ink so the closed pill would
    /// stay hidden against the hardware notch; that reason no longer holds,
    /// because the pill fills with `V6Palette.ink` directly in `V6NotchContent`
    /// and never reads the theme.
    @Test
    func defaultsToFullCream() {
        UserDefaults.standard.removeObject(forKey: "app.islandTheme")
        #expect(AppModel().islandTheme == .fullCream)
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
