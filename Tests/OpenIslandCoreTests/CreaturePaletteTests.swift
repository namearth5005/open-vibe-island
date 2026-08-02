import Testing
@testable import OpenIslandCore

struct CreaturePaletteTests {
    /// The real closed-pill fill, `V6Palette.ink`.
    private let pill = CreatureColor(red: 0x0c, green: 0x0d, blue: 0x0f)

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
}
