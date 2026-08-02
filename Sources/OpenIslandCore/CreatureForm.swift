import Foundation

/// Silhouette parameters for one creature. Derived from the session seed and
/// the pose, never stored — the same rule `ShardForm` follows.
public struct CreatureForm: Equatable, Sendable {
    /// Fraction of the frame width the body occupies.
    public let bodyWidth: Double
    /// Fraction of the frame height the body occupies.
    public let bodyHeight: Double
    /// Vertical position where the arms attach, as a fraction of body height.
    public let shoulder: Double
    /// How far the arms rise. 0 is hanging, 1 is fully overhead. This is the
    /// only channel that carries pose at pill size, so its range is deliberately
    /// wide.
    public let armLift: Double
    /// Whole-body rotation in radians. Non-zero only when knocked over.
    public let tilt: Double

    public init(bodyWidth: Double, bodyHeight: Double, shoulder: Double, armLift: Double, tilt: Double) {
        self.bodyWidth = bodyWidth
        self.bodyHeight = bodyHeight
        self.shoulder = shoulder
        self.armLift = armLift
        self.tilt = tilt
    }

    public static func make(seed: UInt64, pose: CreaturePose) -> CreatureForm {
        var rng = SplitMix64(state: seed)

        // 28pt wide against 32pt tall: width is the binding constraint, so
        // bodies are narrow and tall. The ranges cannot overlap or a wide roll
        // would collide with the lane edge.
        let bodyWidth = 0.52 + rng.nextUnitDouble() * 0.16   // 0.52...0.68
        let bodyHeight = 0.74 + rng.nextUnitDouble() * 0.18  // 0.74...0.92
        let shoulder = 0.44 + rng.nextUnitDouble() * 0.12

        // Pose is expressed through the arms and tilt only. Body proportions
        // stay fixed so a session does not appear to change creature when it
        // blocks or finishes.
        let armLift: Double
        let tilt: Double
        switch pose {
        case .working: armLift = 0.0;  tilt = 0
        case .waiting: armLift = 0.78; tilt = 0
        case .holding: armLift = 1.0;  tilt = 0
        case .fallen:  armLift = 0.1;  tilt = 70.0 * .pi / 180.0
        }

        return CreatureForm(
            bodyWidth: bodyWidth, bodyHeight: bodyHeight,
            shoulder: shoulder, armLift: armLift, tilt: tilt
        )
    }
}
