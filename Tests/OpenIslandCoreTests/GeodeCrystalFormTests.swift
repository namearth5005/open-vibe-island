import Foundation
import Testing
@testable import OpenIslandCore

struct GeodeCrystalFormTests {
    /// The spec requires a session's crystal to be identical across runs, so the
    /// seed must not use Swift's per-process-randomized Hasher.
    @Test
    func seedIsStableForTheSameSessionID() {
        #expect(CrystalSeed.value(for: "abc-123") == CrystalSeed.value(for: "abc-123"))
    }

    @Test
    func seedDiffersForDifferentSessionIDs() {
        #expect(CrystalSeed.value(for: "abc-123") != CrystalSeed.value(for: "abc-124"))
    }

    /// Known-answer test: locks the FNV-1a implementation so a later refactor
    /// cannot silently reshuffle everyone's existing crystals.
    @Test
    func seedMatchesKnownFNV1aValue() {
        #expect(CrystalSeed.value(for: "a") == 0xaf63dc4c8601ec8c)
    }

    @Test
    func sameSeedAndStageProduceIdenticalForm() {
        let a = CrystalForm.make(seed: 99, stage: 3)
        let b = CrystalForm.make(seed: 99, stage: 3)
        #expect(a == b)
    }

    @Test
    func facetCountGrowsWithStage() {
        let small = CrystalForm.make(seed: 7, stage: 0)
        let large = CrystalForm.make(seed: 7, stage: 6)
        #expect(large.facets.count > small.facets.count)
    }

    @Test
    func facetRadiiStayInRange() {
        for stage in 0...6 {
            let form = CrystalForm.make(seed: 4242, stage: stage)
            for radius in form.facets {
                #expect(radius >= 0.55)
                #expect(radius <= 1.0)
            }
        }
    }

    @Test
    func stageForDurationFollowsTheSpecCurve() {
        #expect(CrystalForm.stage(forDuration: 0) == 0)
        #expect(CrystalForm.stage(forDuration: 30) == 1)
        #expect(CrystalForm.stage(forDuration: 1_890) == 6)
        // Capped at 6 no matter how long the session ran.
        #expect(CrystalForm.stage(forDuration: 86_400) == 6)
    }
}
