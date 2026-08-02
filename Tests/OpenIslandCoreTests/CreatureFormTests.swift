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

    /// Pins the actual sampling ranges, not merely "inside the frame" — a body
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

    /// Arm lift is the entire pose vocabulary at pill size, so the four values
    /// are pinned rather than merely required to differ: softening `waiting`
    /// toward `working` would silently cost the notification its legibility.
    @Test
    func eachPosePinsItsArmLift() {
        #expect(CreatureForm.make(seed: 7, pose: .working).armLift == 0.0)
        #expect(CreatureForm.make(seed: 7, pose: .waiting).armLift == 0.78)
        #expect(CreatureForm.make(seed: 7, pose: .holding).armLift == 1.0)
        #expect(CreatureForm.make(seed: 7, pose: .fallen).armLift == 0.1)
    }

    @Test
    func fallenPoseRotatesTheBodyBySeventyDegrees() {
        #expect(CreatureForm.make(seed: 7, pose: .fallen).tilt == 70.0 * Double.pi / 180.0)
        for pose in CreaturePose.allCases where pose != .fallen {
            #expect(CreatureForm.make(seed: 7, pose: pose).tilt == 0, "\(pose.rawValue) is tilted")
        }
    }
}
