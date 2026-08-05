import AppKit
import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

/// The destination surface, measured.
///
/// Round 1 shipped a creature at 58 × 54pt inside a 211pt scene and every test
/// passed. The number that was wrong was a *size*, and no test asserted a size,
/// because the size was an emergent consequence of five layout constants. These
/// tests exist so that failure mode is closed: the share of the frame the
/// companion occupies is now a claim the gate checks, at every window size and
/// for every body and state it can be drawn in.
@MainActor
struct CompanionSurfaceLayoutTests {
    /// What round 1 achieved: 54pt of creature in a 211pt band. The destination
    /// has to beat this by a wide margin or it is the same mistake in a bigger
    /// window.
    static let roundOneHeightShare: CGFloat = 54.0 / 211.0

    /// The floor every body and state clears. Deliberately well above round 1
    /// and well below what the tallest, narrowest sprite happens to reach, so it
    /// asserts the design rather than transcribing today's arithmetic.
    static let floor: CGFloat = 0.60

    /// The shapes the window actually opens at, plus wider ones, because
    /// `windowResizability(.contentMinSize)` lets a user drag it out but the
    /// surface is what it is when it opens.
    private static let openingSizes: [CGSize] = [
        CompanionSurfaceLayout.defaultSize,
        CompanionSurfaceLayout.minimumSize,
        CGSize(width: 1_400, height: 620),
        CGSize(width: 1_000, height: 800),
    ]

    private func aspect(_ species: CreatureSpecies, _ state: CompanionState) -> CGFloat {
        CompanionSurfaceLayout.aspect(of: CreatureSprite.name(for: species, state: state))
    }

    /// The claim that matters, and it is stronger than a percentage: at every
    /// size the window opens at, for every body and every state, the companion
    /// is as tall as the stage allows. Nothing beside it — not the record
    /// column, not the padding — is what limits it.
    ///
    /// Round 1 failed exactly here. Its creature was bounded by a constant, so
    /// widening the panel 540 → 760 moved the frame and left the subject where
    /// it was.
    @Test
    func theFrameAndNotTheColumnIsWhatBoundsTheCompanion() {
        for size in Self.openingSizes {
            let box = CompanionSurfaceLayout.companionBox(
                inStage: CompanionSurfaceLayout.stageSize(in: size)
            )
            for species in CreatureSpecies.allCases {
                for state in CompanionState.allCases {
                    let drawn = CompanionSurfaceLayout.drawnSize(aspect: aspect(species, state), in: box)
                    #expect(
                        abs(drawn.height - box.height) < 0.001,
                        "\(species.rawValue)/\(state.rawValue) at \(size) is width-limited"
                    )
                }
            }
        }
    }

    @Test
    func everyBodyAndStateFillsMostOfTheFrame() {
        for size in Self.openingSizes {
            for species in CreatureSpecies.allCases {
                for state in CompanionState.allCases {
                    let share = CompanionSurfaceLayout.heightShare(aspect: aspect(species, state), in: size)
                    #expect(
                        share >= Self.floor,
                        "\(species.rawValue)/\(state.rawValue) at \(size) is \(share) of the frame"
                    )
                }
            }
        }
    }

    /// The one shape that costs the companion height, stated rather than hidden.
    ///
    /// The record column is a fixed 348pt because the paper does not reflow, so
    /// a window dragged into portrait gives the stage no more width while giving
    /// the frame more height, and the two widest bodies become width-limited.
    /// This is geometry, not a bug — a 1.05-aspect figure 60% as tall as a 900pt
    /// window would need 565pt of stage and there are 452. What is asserted is
    /// that the degradation is graceful: still far larger than round 1's band,
    /// which is the failure that must not come back.
    @Test
    func aPortraitWindowCostsTheWidestBodiesHeightButNeverBackToRoundOne() {
        let portrait = [CGSize(width: 800, height: 900), CGSize(width: 760, height: 760)]
        for size in portrait {
            for species in CreatureSpecies.allCases {
                for state in CompanionState.allCases {
                    let share = CompanionSurfaceLayout.heightShare(aspect: aspect(species, state), in: size)
                    #expect(
                        share > Self.roundOneHeightShare * 1.5,
                        "\(species.rawValue)/\(state.rawValue) at \(size) is \(share) of the frame"
                    )
                }
            }
        }
    }

    @Test
    func theCompanionIsMoreThanTwiceRoundOnesShareOfTheFrame() {
        let share = CompanionSurfaceLayout.heightShare(
            aspect: aspect(.claude, .resting),
            in: CompanionSurfaceLayout.defaultSize
        )
        #expect(share > Self.roundOneHeightShare * 2)
    }

    /// The failure the design document names outright: widening the frame made
    /// round 1 *worse*, because the creature box was a constant. Here the box is
    /// a fraction, so the share holds.
    @Test
    func wideningTheWindowDoesNotShrinkTheCompanionsShare() {
        let narrow = CompanionSurfaceLayout.heightShare(
            aspect: aspect(.claude, .resting), in: CGSize(width: 800, height: 620))
        let wide = CompanionSurfaceLayout.heightShare(
            aspect: aspect(.claude, .resting), in: CGSize(width: 1_400, height: 620))
        #expect(abs(wide - narrow) < 0.001)
    }

    @Test
    func theDrawnCompanionNeverOverflowsItsBox() {
        for size in Self.openingSizes {
            let box = CompanionSurfaceLayout.companionBox(
                inStage: CompanionSurfaceLayout.stageSize(in: size)
            )
            for species in CreatureSpecies.allCases {
                for state in CompanionState.allCases {
                    let drawn = CompanionSurfaceLayout.drawnSize(aspect: aspect(species, state), in: box)
                    #expect(drawn.width <= box.width + 0.001)
                    #expect(drawn.height <= box.height + 0.001)
                }
            }
        }
    }

    /// Every frame the surface asks for is a file that ships. A missing one
    /// degrades to the procedural silhouette silently, which would quietly
    /// replace the art this whole task exists to show at size.
    @Test
    func everyStateHasShippedArtworkForEveryBody() {
        for species in CreatureSpecies.allCases {
            for state in CompanionState.allCases {
                let name = CreatureSprite.name(for: species, state: state)
                #expect(CreatureSprite.image(named: name) != nil, "missing \(name)")
            }
        }
    }

    /// The companion stands *into* the meadow, not on the boundary between two
    /// colours. Asserted because it is the difference between a figure in a
    /// place and a sticker on a background, and it is invisible to every other
    /// check here.
    @Test
    func theCompanionsFeetLandBelowTheHorizon() {
        let stage = CompanionSurfaceLayout.stageSize(in: CompanionSurfaceLayout.defaultSize)
        let horizon = CompanionSurfaceLayout.horizon(inStage: stage)
        let baseline = stage.height * CompanionSurfaceLayout.skyHeadroomFraction
            + CompanionSurfaceLayout.companionBox(inStage: stage).height
        #expect(baseline > horizon)
        #expect(baseline - horizon == CompanionSurfaceLayout.groundBite)
    }
}

/// The record column: the two things that had no home.
@MainActor
struct CompanionRecordTests {
    /// The receipt is wired to one range and cannot describe another, which is
    /// why the Stats pane had to gate it. The destination has no range control
    /// at all, so this is the fact that replaces the gate.
    @Test
    func theReceiptOnlyEverDescribesToday() {
        #expect(Receipt.range == .today)
    }

    /// The column is sized so the paper's own cap is what limits it. If the
    /// column were narrower the slip would silently shrink instead, which is the
    /// one thing a printed document may not do.
    @Test
    func theColumnIsWideEnoughForTheWholeSlip() {
        let receipt = Receipt(
            records: [],
            now: Date(),
            width: CompanionSurfaceLayout.receiptBandWidth,
            lang: LanguageManager(language: .en)
        )
        #expect(receipt.paperWidth == Receipt.maximumPaperWidth)
        #expect(
            receipt.paperWidth + CompanionSurfaceLayout.recordPadding * 2
                <= CompanionSurfaceLayout.recordWidth
        )
    }

    /// The shelf shows the twelve rewards and nothing else. Scrap is what an
    /// interrupt leaves and is in no tier's pool; printing it as a thirteenth
    /// collectible would make an abandoned session look like a find.
    @Test
    func theShelfHoldsEveryRewardExactlyOnceAndNoScrap() {
        let shelved = RewardCollectionView.shelved
        #expect(Set(shelved).count == shelved.count)
        #expect(!shelved.contains(.scrap))
        #expect(Set(shelved) == Set(RewardObject.allCases).subtracting([.scrap]))
    }

    /// `RewardRarity.four` borrows `three`'s pool, so walking `allCases` would
    /// print the same four objects under two different star counts.
    @Test
    func noObjectIsShelvedUnderTwoTiers() {
        var seen = Set<RewardObject>()
        for tier in RewardRarity.distinctPools {
            for object in RewardObject.pool(for: tier) {
                #expect(seen.insert(object).inserted, "\(object.rawValue) is in two pools")
            }
        }
        #expect(seen.count == 12)
    }

    /// Found and unfound have to be distinguishable without colour: the shelf
    /// draws an unfound object desaturated, and a screen reader gets neither the
    /// grey nor the count.
    @Test
    func anUnfoundObjectSaysSoInWords() {
        let lang = LanguageManager(language: .en)
        let locked = lang.t("companion.collection.locked")
        #expect(locked != "companion.collection.locked")
        #expect(!locked.isEmpty)
    }

    @Test
    func everyObjectHasItsOwnName() {
        let keys = RewardObject.allCases.map(\.nameKey)
        #expect(Set(keys).count == RewardObject.allCases.count)
    }

    @Test
    func everyCompanionStateHasItsOwnCaption() {
        let keys = CompanionState.allCases.map(\.captionKey)
        #expect(Set(keys).count == CompanionState.allCases.count)
    }
}

/// Every mark on the surface, measured against the ground it is drawn on.
///
/// The same claim `ReceiptPaperTests` makes about the paper, for the same
/// reason: this surface is where the day's record is read, and a record set in
/// text nobody can read is not a record. It caught a real defect — the first
/// draft used `.opacity(0.42)` and `.opacity(0.6)` for its secondary text, which
/// measure 3.57:1 and 3.80:1.
struct CompanionContrastTests {
    @Test
    func everyMarkOnTheRecordColumnClearsBodyTextContrast() {
        for ink in [
            CompanionPalette.Record.stock,
            CompanionPalette.Record.strong,
            CompanionPalette.Record.body,
            CompanionPalette.Record.quiet,
        ] {
            let ratio = CreatureColor.contrastRatio(ink, CompanionPalette.Record.ground)
            #expect(ratio >= CompanionPalette.bodyTextContrast, "\(ink) measures \(ratio)")
        }
    }

    /// Measured against **every** ground the stage has, not just the one the
    /// caption happens to sit on today. A mark that only clears the meadow is a
    /// mark that fails the moment it is moved up the hill.
    @Test
    func everyMarkOnTheStageClearsBodyTextContrastOnEveryGround() {
        let grounds = [
            ("meadow", CompanionPalette.Stage.ground),
            ("skyLow", CompanionPalette.Stage.skyLow),
            ("skyHigh", CompanionPalette.Stage.skyHigh),
            ("hill", CompanionPalette.Stage.hill),
        ]
        for ink in [CompanionPalette.Stage.ink, CompanionPalette.Stage.quietInk] {
            for (name, ground) in grounds {
                let ratio = CreatureColor.contrastRatio(ink, ground)
                #expect(
                    ratio >= CompanionPalette.bodyTextContrast,
                    "\(ink) measures \(ratio) on \(name)"
                )
            }
        }
    }

    /// The hill is the *darkest* ground on the stage, so it is the one that
    /// binds — and the meadow, being the lightest, is the one that proves least.
    ///
    /// This test previously asserted the opposite of its own name and passed:
    /// it checked that the sky is darker than the meadow, called that "the sky
    /// is lighter", and concluded the meadow binds. For dark marks on light
    /// grounds contrast is `(ground + 0.05) / (ink + 0.05)`, which *falls* as
    /// the ground darkens. Under the wrong reading, `quietInk` was derived to
    /// clear 4.5:1 on the meadow and measured 3.42:1 on the hill crest.
    @Test
    func theHillIsTheDarkestGroundSoTheHillIsTheBindingGround() {
        let meadow = CompanionPalette.Stage.ground.relativeLuminance
        for other in [
            CompanionPalette.Stage.skyHigh,
            CompanionPalette.Stage.skyLow,
            CompanionPalette.Stage.hill,
        ] {
            #expect(other.relativeLuminance < meadow)
        }

        // The binding ground is the darkest one, and that is the hill.
        let hill = CompanionPalette.Stage.hill.relativeLuminance
        for other in [
            CompanionPalette.Stage.ground,
            CompanionPalette.Stage.skyHigh,
            CompanionPalette.Stage.skyLow,
        ] {
            #expect(hill <= other.relativeLuminance)
        }
        #expect(CompanionPalette.Stage.bindingGround == CompanionPalette.Stage.hill)

        // And the binding ground really is the worst case, not merely the
        // darkest: the ratio it yields is the lowest of the four.
        let worst = CreatureColor.contrastRatio(
            CompanionPalette.Stage.quietInk, CompanionPalette.Stage.bindingGround
        )
        for ground in [
            CompanionPalette.Stage.ground,
            CompanionPalette.Stage.skyHigh,
            CompanionPalette.Stage.skyLow,
        ] {
            #expect(worst <= CreatureColor.contrastRatio(CompanionPalette.Stage.quietInk, ground))
        }
    }

    /// The three weights have to be distinguishable from each other, or the
    /// ladder is one colour written three ways.
    @Test
    func theRecordsThreeWeightsAreActuallyThreeWeights() {
        let ladder = [
            CompanionPalette.Record.quiet,
            CompanionPalette.Record.body,
            CompanionPalette.Record.strong,
        ]
        let luminances = ladder.map(\.relativeLuminance)
        #expect(luminances == luminances.sorted())
        for (lower, higher) in zip(luminances, luminances.dropFirst()) {
            // Far enough apart to be told apart on screen, not merely unequal.
            #expect(higher - lower > 0.05, "\(lower) and \(higher) are one weight")
        }
    }

    /// The stage's own colours are the spec's scene palette, not a second set
    /// invented for one view — the same check `ReceiptPaperTests` makes of the
    /// stock.
    @Test
    func theStageUsesTheSpecsSceneColours() {
        #expect(CompanionPalette.Stage.ground == CreatureColor(red: 0xB4, green: 0xDE, blue: 0x6F))
        #expect(CompanionPalette.Stage.ink == IslandDesignPalette.Paper.ink)
        #expect(CompanionPalette.Record.stock == IslandDesignPalette.Paper.stock)
    }
}

/// Opening the surface must leave the two things that already work alone.
@MainActor
@Suite(.serialized)
struct CompanionWindowTests {
    @Test
    func theCompanionIsItsOwnWindowAndNotTheSettingsOne() {
        #expect(CompanionWindow.id != "settings")
        #expect(CompanionWindow.title != "Open Island Settings")
    }

    /// The native window title is matched on by `showCompanion`, so it must not
    /// be a translated string — switching language would otherwise stop the
    /// window from being found and brought forward.
    @Test
    func theWindowTitleIsNotTakenFromTheStringsTable() {
        for locale in [LanguageManager.AppLanguage.en, .zhHans, .zhHant] {
            let lang = LanguageManager(language: locale)
            #expect(lang.t(CompanionWindow.titleKey) != CompanionWindow.title)
        }
    }

    /// The acceptance criterion, asserted rather than asserted-to: opening the
    /// window goes through one closure and touches no overlay state.
    @Test
    func openingTheWindowDisturbsNeitherThePanelNorThePill() {
        _ = NSApplication.shared
        let model = AppModel()
        let surface = model.islandSurface
        let status = model.notchStatus
        let slot = model.islandRightSlot
        var opened = 0
        model.openCompanionWindow = { opened += 1 }

        model.showCompanion()

        #expect(opened == 1)
        #expect(model.islandSurface == surface)
        #expect(model.notchStatus == status)
        #expect(model.islandRightSlot == slot)
    }
}
