import Foundation

/// Deterministic seed for a session's shard.
///
/// Deliberately NOT `hashValue`: Swift seeds `Hasher` randomly per process, so
/// using it would give the same session a different shard on every launch and
/// break the spec's recomputability guarantee. FNV-1a is stable forever.
public enum ShardSeed {
    public static func value(for sessionID: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in sessionID.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

/// Geometry parameters for one shard. Derived, never stored.
public struct ShardForm: Equatable, Sendable {
    /// Per-facet radius multipliers, walking the silhouette clockwise.
    public let facets: [Double]
    /// Rotation of the whole silhouette, radians, over a full turn.
    ///
    /// A narrow tilt range made every shard lean the same way, which read as
    /// "the same shape" at 20pt even when the facets differed. Free rotation is
    /// the cheapest source of apparent variety at this size.
    public let tilt: Double
    /// Vertical stretch. 1.0 is round; below 1 is squat, above is tall.
    public let elongation: Double
    /// Fraction of the available frame the silhouette fills, driven by stage.
    ///
    /// Without this, growth only added facets — and more facets at a fixed radius
    /// reads as *rounder*, not *bigger*, so the shard never appeared to grow.
    /// Stage 0 fills about a third of the frame; stage 6 fills it.
    public let scale: Double

    public init(facets: [Double], tilt: Double, elongation: Double, scale: Double) {
        self.facets = facets
        self.tilt = tilt
        self.elongation = elongation
        self.scale = scale
    }

    /// Growth stage 0...6 from elapsed run seconds.
    /// `floor(log2(1 + duration / 30))`, so stage 6 lands at ~31.5 minutes.
    public static func stage(forDuration seconds: TimeInterval) -> Int {
        guard seconds > 0 else { return 0 }
        let value = Foundation.log2(1.0 + seconds / 30.0)
        return min(6, max(0, Int(value.rounded(.down))))
    }

    public static func make(seed: UInt64, stage: Int) -> ShardForm {
        var rng = SplitMix64(state: seed)
        let clampedStage = min(6, max(0, stage))
        // 3 facets at stage 0 growing to 9 at stage 6.
        let facetCount = 3 + clampedStage
        let facets = (0..<facetCount).map { _ in
            0.55 + rng.nextUnitDouble() * 0.45
        }
        let tilt = rng.nextUnitDouble() * 2 * Double.pi
        let elongation = 0.75 + rng.nextUnitDouble() * 0.6
        // Linear in stage, so a stage-6 shard covers roughly 10x the area of
        // a stage-0 one — growth has to be obvious at 20pt or it isn't growth.
        let scale = Self.minimumScale + Double(clampedStage) / 6.0 * (1.0 - Self.minimumScale)
        return ShardForm(facets: facets, tilt: tilt, elongation: elongation, scale: scale)
    }

    /// Frame fraction a freshly-seeded stage-0 shard occupies.
    ///
    /// This was 0.32, which measured fine in a side-by-side render and was
    /// invisible in the real pill: 0.32 of an 18pt box, further reduced by facet
    /// multipliers and the alternating notch, drew a mark about 3pt across.
    /// A new session has to be *visible*, so growth is the change in size rather
    /// than the difference between nothing and something. The cost is a smaller
    /// growth range — roughly 2.6x the area from stage 0 to 6 instead of 10x —
    /// which is the right trade at this scale.
    static let minimumScale = 0.62
}

/// Small deterministic PRNG so the same seed always walks the same sequence.
struct SplitMix64 {
    private var state: UInt64

    init(state: UInt64) {
        self.state = state
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }

    /// Uniform in 0..<1.
    mutating func nextUnitDouble() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}
