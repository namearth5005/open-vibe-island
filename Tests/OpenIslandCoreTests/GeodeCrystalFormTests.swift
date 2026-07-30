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

    /// The whole premise is that the crystal visibly grows. Facet count alone
    /// reads as "rounder", not "bigger", so scale must rise with stage.
    @Test
    func scaleGrowsMonotonicallyWithStage() {
        let scales = (0...6).map { CrystalForm.make(seed: 11, stage: $0).scale }
        for (lower, higher) in zip(scales, scales.dropFirst()) {
            #expect(higher > lower)
        }
    }

    @Test
    func scaleSpansMinimumToFullFrame() {
        #expect(CrystalForm.make(seed: 11, stage: 0).scale == CrystalForm.minimumScale)
        #expect(CrystalForm.make(seed: 11, stage: 6).scale == 1.0)
    }

    /// A mature crystal should cover several times the area of a new one, or the
    /// growth signal is too weak to notice at 20pt.
    @Test
    func matureCrystalCoversAtLeastFiveTimesTheAreaOfANewOne() {
        let new = CrystalForm.make(seed: 11, stage: 0).scale
        let mature = CrystalForm.make(seed: 11, stage: 6).scale
        #expect((mature * mature) / (new * new) >= 5.0)
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
