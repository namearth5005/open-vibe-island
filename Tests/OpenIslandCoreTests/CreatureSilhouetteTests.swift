import CoreGraphics
import Testing
@testable import OpenIslandCore

/// The Phase 0 gate's pass conditions, as tests.
///
/// The gate itself is a human judging PNGs, which is the right way to answer
/// "does this read". But the geometry it depends on can regress silently
/// between gate runs, so the measurable half lives here where CI sees it.
/// Thresholds sit below the measured worst case with margin — they are guards
/// against the property disappearing, not pins on the exact numbers.
struct CreatureSilhouetteTests {
    private let lane = CGRect(origin: .zero, size: CreatureSilhouette.pillLane)
    private let seeds = UInt64(0)..<40

    private func bounds(_ seed: UInt64, _ pose: CreaturePose, arms: Bool = true) -> CGRect {
        CreatureSilhouette.path(
            for: CreatureForm.make(seed: seed, pose: pose), in: lane, includeArms: arms
        ).boundingBoxOfPath
    }

    /// The load-bearing constraint of the whole design. The lane's top edge is
    /// the physical top edge of the display — pixels above it are not clipped,
    /// they are off-screen. Anything that starts drawing upward is invisible,
    /// so this is asserted strictly rather than with a tolerance.
    @Test
    func nothingIsDrawnAboveTheLane() {
        for seed in seeds {
            for pose in CreaturePose.allCases {
                let box = bounds(seed, pose)
                #expect(box.maxY <= lane.maxY + 0.001,
                        "\(pose.rawValue) at seed \(seed) draws \(box.maxY - lane.maxY)pt above the lane")
            }
        }
    }

    /// Sideways is where the room is, but it is not unlimited — a body that
    /// spills far past the lane collides with the neighbouring slot.
    @Test
    func nothingSpillsFarOutOfTheLaneSideways() {
        for seed in seeds {
            for pose in CreaturePose.allCases {
                let box = bounds(seed, pose)
                let spill = max(lane.minX - box.minX, box.maxX - lane.maxX)
                #expect(spill < 1.0, "\(pose.rawValue) at seed \(seed) spills \(spill)pt sideways")
            }
        }
    }

    /// Condition 1, the half that can be measured. `waiting` is the
    /// notification, and what makes it one is that it is lopsided — a symmetric
    /// `waiting` is indistinguishable from `holding`, which is exactly how the
    /// gate failed the first time.
    @Test
    func onlyWaitingHasALopsidedSilhouette() {
        for seed in seeds {
            for pose in CreaturePose.allCases where pose != .fallen {
                let body = bounds(seed, pose, arms: false)
                let full = bounds(seed, pose)
                let asymmetry = abs((full.maxX - body.maxX) - (body.minX - full.minX))
                if pose == .waiting {
                    #expect(asymmetry >= 2.0,
                            "waiting at seed \(seed) is only \(asymmetry)pt lopsided")
                } else {
                    #expect(asymmetry < 0.001,
                            "\(pose.rawValue) at seed \(seed) is \(asymmetry)pt lopsided")
                }
            }
        }
    }

    /// Both of `holding`'s arms must leave the body, or it collapses back into
    /// `waiting`. The weaker arm is the one that carries the distinction.
    @Test
    func holdingBreaksTheOutlineOnBothSides() {
        for seed in seeds {
            let body = bounds(seed, .holding, arms: false)
            let full = bounds(seed, .holding)
            let weaker = min(full.maxX - body.maxX, body.minX - full.minX)
            #expect(weaker >= 4.0, "holding at seed \(seed) breaks only \(weaker)pt on its weaker side")
        }
    }

    /// `working` is the ambient state and must stay quiet — if its outline
    /// broke as much as the attention states, nothing would read as urgent.
    @Test
    func workingIsTheQuietestSilhouette() {
        for seed in seeds {
            let body = bounds(seed, .working, arms: false)
            let working = bounds(seed, .working)
            let waiting = bounds(seed, .waiting)
            let workingBreak = working.maxX - body.maxX
            let waitingBreak = waiting.maxX - body.maxX
            #expect(waitingBreak > workingBreak + 2.0,
                    "seed \(seed): waiting breaks \(waitingBreak)pt vs working \(workingBreak)pt")
        }
    }
}
