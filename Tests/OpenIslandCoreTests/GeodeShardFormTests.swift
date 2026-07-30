import Foundation
import Testing
@testable import OpenIslandCore

struct GeodeShardFormTests {
    /// The spec requires a session's shard to be identical across runs, so the
    /// seed must not use Swift's per-process-randomized Hasher.
    @Test
    func seedIsStableForTheSameSessionID() {
        #expect(ShardSeed.value(for: "abc-123") == ShardSeed.value(for: "abc-123"))
    }

    @Test
    func seedDiffersForDifferentSessionIDs() {
        #expect(ShardSeed.value(for: "abc-123") != ShardSeed.value(for: "abc-124"))
    }

    /// Known-answer test: locks the FNV-1a implementation so a later refactor
    /// cannot silently reshuffle everyone's existing shards.
    @Test
    func seedMatchesKnownFNV1aValue() {
        #expect(ShardSeed.value(for: "a") == 0xaf63dc4c8601ec8c)
    }

    @Test
    func sameSeedAndStageProduceIdenticalForm() {
        let a = ShardForm.make(seed: 99, stage: 3)
        let b = ShardForm.make(seed: 99, stage: 3)
        #expect(a == b)
    }

    @Test
    func facetCountGrowsWithStage() {
        let small = ShardForm.make(seed: 7, stage: 0)
        let large = ShardForm.make(seed: 7, stage: 6)
        #expect(large.facets.count > small.facets.count)
    }

    @Test
    func facetRadiiStayInRange() {
        for stage in 0...6 {
            let form = ShardForm.make(seed: 4242, stage: stage)
            for radius in form.facets {
                #expect(radius >= 0.55)
                #expect(radius <= 1.0)
            }
        }
    }

    /// Every shard leaning the same way read as "the same shape" at 20pt, so
    /// tilt must cover a full turn — it is the cheapest variety at this size.
    @Test
    func tiltSpansAFullRotationAcrossSeeds() {
        let tilts = (0..<200).map { ShardForm.make(seed: UInt64($0) &* 2_654_435_761, stage: 4).tilt }
        #expect(tilts.allSatisfy { $0 >= 0 && $0 <= 2 * Double.pi })
        // Every quadrant should be represented over 200 rolls.
        let quadrants = Set(tilts.map { Int($0 / (Double.pi / 2)) })
        #expect(quadrants.count == 4)
    }

    /// The whole premise is that the shard visibly grows. Facet count alone
    /// reads as "rounder", not "bigger", so scale must rise with stage.
    @Test
    func scaleGrowsMonotonicallyWithStage() {
        let scales = (0...6).map { ShardForm.make(seed: 11, stage: $0).scale }
        for (lower, higher) in zip(scales, scales.dropFirst()) {
            #expect(higher > lower)
        }
    }

    @Test
    func scaleSpansMinimumToFullFrame() {
        #expect(ShardForm.make(seed: 11, stage: 0).scale == ShardForm.minimumScale)
        #expect(ShardForm.make(seed: 11, stage: 6).scale == 1.0)
    }

    /// A mature shard should cover several times the area of a new one, or the
    /// growth signal is too weak to notice at 20pt.
    @Test
    func matureCrystalCoversAtLeastFiveTimesTheAreaOfANewOne() {
        let new = ShardForm.make(seed: 11, stage: 0).scale
        let mature = ShardForm.make(seed: 11, stage: 6).scale
        #expect((mature * mature) / (new * new) >= 5.0)
    }

    @Test
    func stageForDurationFollowsTheSpecCurve() {
        #expect(ShardForm.stage(forDuration: 0) == 0)
        #expect(ShardForm.stage(forDuration: 30) == 1)
        #expect(ShardForm.stage(forDuration: 1_890) == 6)
        // Capped at 6 no matter how long the session ran.
        #expect(ShardForm.stage(forDuration: 86_400) == 6)
    }
}
