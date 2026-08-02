import Testing
@testable import OpenIslandCore

struct CreatureFormTests {
    @Test
    func sameSeedAndPoseProduceIdenticalForms() {
        #expect(CreatureForm.make(seed: 99, pose: .working) == CreatureForm.make(seed: 99, pose: .working))
    }

    @Test
    func differentSeedsProduceDifferentForms() {
        #expect(CreatureForm.make(seed: 1, pose: .working) != CreatureForm.make(seed: 2, pose: .working))
    }

    /// The pill lane is 28pt wide and 32pt tall, so bodies must be taller than
    /// they are wide. Width is the binding constraint, not height.
    @Test
    func everyFormIsTallerThanItIsWide() {
        for seed in UInt64(0)..<40 {
            let form = CreatureForm.make(seed: seed, pose: .working)
            #expect(form.bodyHeight > form.bodyWidth, "seed \(seed) is not tall enough")
        }
    }

    /// Pins the outer envelope of the sampling ranges. Because `nextUnitDouble()`
    /// is uniform in `0..<1` the upper bounds are never attained, so this catches a
    /// range that widens past the lane edge but not one that silently narrows, not merely "inside the frame" — a body
    /// 0.99 of the lane wide would satisfy the loose bound and still collide
    /// with the lane edge, which is the failure the ranges exist to prevent.
    @Test
    func bodyProportionsStayInsideTheirSampledRanges() {
        for seed in UInt64(0)..<200 {
            for pose in CreaturePose.allCases {
                let form = CreatureForm.make(seed: seed, pose: pose)
                #expect(form.bodyWidth >= 0.52 && form.bodyWidth <= 0.68, "width \(form.bodyWidth) at seed \(seed)")
                #expect(form.bodyHeight >= 0.74 && form.bodyHeight <= 0.92, "height \(form.bodyHeight) at seed \(seed)")
                #expect(form.shoulder >= 0.44 && form.shoulder <= 0.56, "shoulder \(form.shoulder) at seed \(seed)")
            }
        }
    }

    /// The pose changes the arms and the tilt, never the body — otherwise a
    /// session appears to change creature when it blocks. All three body
    /// channels are checked across all four poses, since any one of them
    /// leaking pose would break the illusion.
    @Test
    func poseDoesNotChangeBodyProportions() {
        let reference = CreatureForm.make(seed: 7, pose: .working)
        for pose in CreaturePose.allCases {
            let form = CreatureForm.make(seed: 7, pose: pose)
            #expect(form.bodyWidth == reference.bodyWidth, "\(pose.rawValue) changed width")
            #expect(form.bodyHeight == reference.bodyHeight, "\(pose.rawValue) changed height")
            #expect(form.shoulder == reference.shoulder, "\(pose.rawValue) changed shoulder")
        }
    }

    /// Arm lift is the entire pose vocabulary at pill size, so the values are
    /// pinned rather than merely required to differ: softening `waiting` toward
    /// `working` would silently cost the notification its legibility.
    @Test
    func eachPosePinsItsArmLifts() {
        let working = CreatureForm.make(seed: 7, pose: .working)
        #expect(working.armLiftLeading == 0.0 && working.armLiftTrailing == 0.0)

        let waiting = CreatureForm.make(seed: 7, pose: .waiting)
        #expect(waiting.armLiftLeading == 1.0 && waiting.armLiftTrailing == 0.0)

        let holding = CreatureForm.make(seed: 7, pose: .holding)
        #expect(holding.armLiftLeading == 1.0 && holding.armLiftTrailing == 1.0)

        let fallen = CreatureForm.make(seed: 7, pose: .fallen)
        #expect(fallen.armLiftLeading == 0.1 && fallen.armLiftTrailing == 0.1)
    }

    /// The load-bearing invariant. The lane offers at most 4.2pt of headroom
    /// above the body and the pill cannot draw above itself, so a raised arm
    /// cannot clear the body — magnitude alone gave `waiting` and `holding`
    /// near-identical silhouettes and failed the Phase 0 gate.
    ///
    /// Asymmetry is what separates them: exactly one raised arm means "asking",
    /// two means "collect me". Symmetry is therefore an invariant of every other
    /// pose, not an incidental property of these constants.
    @Test
    func onlyWaitingIsAsymmetric() {
        for seed in UInt64(0)..<40 {
            for pose in CreaturePose.allCases {
                let form = CreatureForm.make(seed: seed, pose: pose)
                let asymmetric = form.armLiftLeading != form.armLiftTrailing
                #expect(
                    asymmetric == (pose == .waiting),
                    "\(pose.rawValue) asymmetry \(asymmetric) at seed \(seed)"
                )
            }
        }
    }

    /// `waiting` and `holding` must never collapse into the same silhouette
    /// again. They share a raised leading arm, so the trailing arm is the only
    /// thing carrying the distinction and it has to stay fully apart.
    @Test
    func waitingAndHoldingDifferByAWholeArm() {
        let waiting = CreatureForm.make(seed: 7, pose: .waiting)
        let holding = CreatureForm.make(seed: 7, pose: .holding)
        #expect(waiting.armLiftLeading == holding.armLiftLeading)
        #expect(holding.armLiftTrailing - waiting.armLiftTrailing == 1.0)
    }

    @Test
    func fallenPoseRotatesTheBodyBySeventyDegrees() {
        #expect(CreatureForm.make(seed: 7, pose: .fallen).tilt == 70.0 * Double.pi / 180.0)
        for pose in CreaturePose.allCases where pose != .fallen {
            #expect(CreatureForm.make(seed: 7, pose: pose).tilt == 0, "\(pose.rawValue) is tilted")
        }
    }
}
