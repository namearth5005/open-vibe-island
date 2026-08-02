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

    @Test
    func formsStayInsideTheFrame() {
        for seed in UInt64(0)..<40 {
            for pose in CreaturePose.allCases {
                let form = CreatureForm.make(seed: seed, pose: pose)
                #expect(form.bodyWidth > 0 && form.bodyWidth <= 1.0)
                #expect(form.bodyHeight > 0 && form.bodyHeight <= 1.0)
            }
        }
    }

    /// The pose changes the arms and the tilt, never the body — otherwise a
    /// session appears to change creature when it blocks.
    @Test
    func poseDoesNotChangeBodyProportions() {
        let working = CreatureForm.make(seed: 7, pose: .working)
        let waiting = CreatureForm.make(seed: 7, pose: .waiting)
        #expect(working.bodyWidth == waiting.bodyWidth)
        #expect(working.bodyHeight == waiting.bodyHeight)
        #expect(working.armLift != waiting.armLift)
    }

    @Test
    func fallenPoseRotatesTheBody() {
        #expect(CreatureForm.make(seed: 7, pose: .fallen).tilt != 0)
        #expect(CreatureForm.make(seed: 7, pose: .working).tilt == 0)
    }
}
