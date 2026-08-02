import Foundation
import Testing
@testable import OpenIslandCore

struct CreaturePaletteTests {
    /// Deliberately the shipped constant rather than a local copy. An earlier
    /// draft declared its own literal here, which is exactly how a one-channel
    /// drift from `V6Palette.ink` survived unnoticed.
    private let pill = CreaturePalette.pillFill

    /// Known-answer test freezing the value every contrast figure below was
    /// computed against, so the gate cannot be moved by editing the pill.
    ///
    /// It cannot detect drift from `V6Palette.ink` itself — Core has no
    /// visibility into the app target, and this literal would happily agree
    /// with a stale copy. `CreaturePillFillTests` in the app target is what
    /// compares the two.
    @Test
    func pillFillMatchesTheShippedInk() {
        #expect(CreaturePalette.pillFill == CreatureColor(red: 0x0d, green: 0x0d, blue: 0x0f))
    }

    @Test
    func knownAnswerLuminance() {
        #expect(abs(CreatureColor(red: 255, green: 255, blue: 255).relativeLuminance - 1.0) < 0.0001)
        #expect(abs(CreatureColor(red: 0, green: 0, blue: 0).relativeLuminance - 0.0) < 0.0001)
    }

    @Test
    func knownAnswerContrast() {
        let white = CreatureColor(red: 255, green: 255, blue: 255)
        let black = CreatureColor(red: 0, green: 0, blue: 0)
        #expect(abs(CreatureColor.contrastRatio(white, black) - 21.0) < 0.01)
    }

    /// Gate condition 2. Every species must be visible against the pill.
    @Test
    func everySpeciesClearsThreeToOneAgainstThePill() {
        for species in CreatureSpecies.allCases {
            let ratio = CreatureColor.contrastRatio(CreaturePalette.color(for: species), pill)
            #expect(ratio >= 3.0, "\(species.rawValue) is \(ratio):1 against the pill")
        }
    }

    /// Gate condition 3, the colour half.
    @Test
    func speciesSeparateByLuminanceNotOnlyHue() {
        let sorted = CreatureSpecies.allCases
            .map { CreaturePalette.color(for: $0).relativeLuminance }
            .sorted(by: >)
        for (brighter, darker) in zip(sorted, sorted.dropFirst()) {
            let gap = (brighter - darker) * 100
            #expect(gap >= 6.0, "adjacent species differ by only \(gap) luminance points")
        }
    }

    @Test
    func theLadderSpansAUsefulRange() {
        let values = CreatureSpecies.allCases.map { CreaturePalette.color(for: $0).relativeLuminance * 100 }
        let spread = (values.max() ?? 0) - (values.min() ?? 0)
        #expect(spread >= 40, "luminance spread is only \(spread) points")
    }

    /// Known-answer pin for the second ground, matching `pillFillMatchesTheShippedInk`.
    @Test
    func panelGroundMatchesTheMeasuredForegroundWash() {
        #expect(CreaturePalette.panelGround == CreatureColor(red: 0xb4, green: 0xde, blue: 0x6f))
    }

    /// The pill ladder cannot be reused on the panel: the panel ground sits at
    /// L 63.1%, and clearing 3:1 against it requires L <= 17.7%, which the whole
    /// pill ladder except `openCode` sits above. Measured on the pill palette,
    /// five of six species land between 1.08:1 and 2.27:1 there — invisible.
    @Test
    func everySpeciesClearsThreeToOneAgainstThePanelGround() {
        for species in CreatureSpecies.allCases {
            let ratio = CreatureColor.contrastRatio(
                CreaturePalette.panelColor(for: species), CreaturePalette.panelGround
            )
            #expect(ratio >= 3.0, "\(species.rawValue) is \(ratio):1 against the panel ground")
        }
    }

    /// A species has to stay recognisable when the same session is seen on both
    /// surfaces, so the panel values are a compressed restatement of the pill
    /// ladder rather than an independent palette — same order, darker band.
    @Test
    func panelValuesPreserveTheSpeciesRank() {
        let byPill = CreatureSpecies.allCases
            .sorted { CreaturePalette.color(for: $0).relativeLuminance < CreaturePalette.color(for: $1).relativeLuminance }
        let byPanel = CreatureSpecies.allCases
            .sorted { CreaturePalette.panelColor(for: $0).relativeLuminance < CreaturePalette.panelColor(for: $1).relativeLuminance }
        #expect(byPill == byPanel, "panel reorders the ladder: \(byPill) vs \(byPanel)")
    }

    /// Value changes between surfaces; hue must not. The panel colour is the
    /// pill colour scaled in linear light, so chromaticity is preserved and only
    /// brightness moves — otherwise "the blue one" stops being the blue one.
    @Test
    func panelValuesPreserveHue() {
        func chromaticity(_ c: CreatureColor) -> (Double, Double) {
            func linear(_ raw: UInt8) -> Double {
                let v = Double(raw) / 255.0
                return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            let r = linear(c.red), g = linear(c.green), b = linear(c.blue)
            let sum = r + g + b
            guard sum > 0 else { return (0, 0) }
            return (r / sum, g / sum)
        }
        for species in CreatureSpecies.allCases {
            let (pr, pg) = chromaticity(CreaturePalette.color(for: species))
            let (nr, ng) = chromaticity(CreaturePalette.panelColor(for: species))
            #expect(abs(pr - nr) < 0.02 && abs(pg - ng) < 0.02,
                    "\(species.rawValue) hue drifted: (\(pr), \(pg)) -> (\(nr), \(ng))")
        }
    }
}
