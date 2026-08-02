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
    /// Silhouette shape, 0 boxy through 1 fully rounded.
    ///
    /// Individuality has to come from a channel the lane can afford. Width is
    /// the binding constraint and the raised-arm gesture needs the side room,
    /// so proportions stay in a narrow band and *shape* carries the variation
    /// instead — which costs no space at all.
    public let roundness: Double
    /// How far the leading (trailing-edge-of-lane) arm rises. 0 hangs, 1 is
    /// fully out.
    ///
    /// "Fully out" is deliberately not "overhead": the lane leaves at most
    /// 4.2pt above the body, and the pill's top edge is the physical top edge
    /// of the display, so a raised arm has nowhere to go but sideways.
    public let armLiftLeading: Double
    /// How far the trailing arm rises, on the same scale.
    ///
    /// The two arms are separate because pose cannot be carried by magnitude
    /// here. One arm out reads as *asking*; two read as *presenting*. That
    /// asymmetry survives at 28x32pt where a difference of degree does not —
    /// the Phase 0 gate failed on a single scalar for exactly this reason.
    public let armLiftTrailing: Double
    /// Whole-body rotation in radians. Non-zero only when knocked over.
    public let tilt: Double

    public init(
        bodyWidth: Double,
        bodyHeight: Double,
        shoulder: Double,
        roundness: Double,
        armLiftLeading: Double,
        armLiftTrailing: Double,
        tilt: Double
    ) {
        self.bodyWidth = bodyWidth
        self.bodyHeight = bodyHeight
        self.shoulder = shoulder
        self.roundness = roundness
        self.armLiftLeading = armLiftLeading
        self.armLiftTrailing = armLiftTrailing
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
        let roundness = rng.nextUnitDouble()

        // Pose is expressed through the arms and tilt only. Body proportions
        // stay fixed so a session does not appear to change creature when it
        // blocks or finishes.
        //
        // The three pill-legible states are separated by *how many* arms are
        // out, not how far. An earlier single-scalar version graded 0 / 0.78 /
        // 1.0 and the gate found `waiting` and `holding` indistinguishable at
        // true size — 22% of a range that itself has only ~5pt to move in.
        let leading: Double
        let trailing: Double
        let tilt: Double
        switch pose {
        case .working: leading = 0.0; trailing = 0.0; tilt = 0
        case .waiting: leading = 1.0; trailing = 0.0; tilt = 0
        case .holding: leading = 1.0; trailing = 1.0; tilt = 0
        case .fallen:  leading = 0.1; trailing = 0.1; tilt = 70.0 * .pi / 180.0
        }

        return CreatureForm(
            bodyWidth: bodyWidth, bodyHeight: bodyHeight,
            shoulder: shoulder, roundness: roundness,
            armLiftLeading: leading, armLiftTrailing: trailing,
            tilt: tilt
        )
    }
}
