import CoreGraphics
import Foundation

/// Everything that can move about the companion, as continuous values.
///
/// Every field is a *pose* parameter, never a state: nothing here knows what a
/// session is. That separation is what makes the character animatable at all —
/// `CompanionState` has four values and a pet that can only be in four
/// positions reads as a slideshow, so the state picks a target and the rig is
/// interpolated toward it.
///
/// Ranges are documented per field and clamped on the way in. A rig that
/// silently accepted 3.0 for `blink` would draw an eyelid through the skull,
/// and the failure would be a screenshot nobody took.
public struct CompanionRigParameters: Equatable, Sendable {
    /// 0...1. Chest rise. The whole character is alive or dead on this one.
    public var breath: Double
    /// -1...1. Weight shift, about the feet.
    public var sway: Double
    /// 0...1. Eyelid closure. 1 is fully shut.
    public var blink: Double
    /// 0...1 each. Arm raised outward from the flank.
    public var armLiftLeading: Double
    public var armLiftTrailing: Double
    /// -1...1. Head turn, left to right.
    public var headTurn: Double
    /// -1...1. Head tilt — the curious one.
    public var headTilt: Double
    /// 0...1. Ears up and forward.
    public var earPerk: Double
    /// 0...1. Settled down: body lower and wider, head sunk toward it. This is
    /// what sleeping is, rather than a separate sleeping drawing.
    public var settle: Double
    /// -1...1. Tail swish.
    public var tailSwish: Double

    public init(
        breath: Double = 0,
        sway: Double = 0,
        blink: Double = 0,
        armLiftLeading: Double = 0,
        armLiftTrailing: Double = 0,
        headTurn: Double = 0,
        headTilt: Double = 0,
        earPerk: Double = 0.5,
        settle: Double = 0,
        tailSwish: Double = 0
    ) {
        func unit(_ v: Double) -> Double { min(1, max(0, v)) }
        func signed(_ v: Double) -> Double { min(1, max(-1, v)) }

        self.breath = unit(breath)
        self.sway = signed(sway)
        self.blink = unit(blink)
        self.armLiftLeading = unit(armLiftLeading)
        self.armLiftTrailing = unit(armLiftTrailing)
        self.headTurn = signed(headTurn)
        self.headTilt = signed(headTilt)
        self.earPerk = unit(earPerk)
        self.settle = unit(settle)
        self.tailSwish = signed(tailSwish)
    }
}

/// One drawable piece, and what it is for.
///
/// The rig returns pieces rather than a single merged path because a pet that
/// is one flat silhouette is exactly the sticker the human has objected to
/// three times. Depth needs a belly lighter than the flank and a muzzle lighter
/// again, and that needs the renderer to know which is which.
///
/// `@unchecked Sendable` because `CGPath` is not marked `Sendable` by
/// CoreGraphics. Every path here is built inside `layers(_:in:)`, never handed
/// out mutable and never mutated after construction, so the value is immutable
/// in fact even though the type system cannot say so.
public struct CompanionLayer: @unchecked Sendable {
    public enum Role: String, Sendable {
        /// Contact shadow on the ground. Drawn first, under everything.
        case shadow
        /// Behind the body: tail, far ear.
        case behind
        /// The main mass — head, body, limbs.
        case body
        /// Lighter shading: belly, muzzle, inner ear.
        case light
        /// Limbs and tail — the same hue as the body, a shade off it, so an arm
        /// crossing the chest reads as an arm instead of vanishing.
        case limb
        /// The eyes and nose.
        case feature
        /// The eyelid, drawn in body colour over the eye.
        case lid
    }

    public let role: Role
    public let path: CGPath

    public init(role: Role, path: CGPath) {
        self.role = role
        self.path = path
    }
}

/// The companion's body, drawn from numbers instead of from a PNG.
///
/// Vector rather than sprite for three reasons the sprite set cannot answer.
/// It can breathe, blink and shift its weight continuously, where 7 static
/// frames per character can only cut between attitudes. It can be *grounded* —
/// the contact shadow is computed from where the feet actually are this frame,
/// rather than a blur pasted under a cut-out. And it takes its colours from the
/// caller, so it can pick up the surface it is sitting on instead of arriving
/// at full saturation against it.
///
/// Proportions are deliberately neotenic: the head is the largest single mass
/// and the eyes sit low and wide on it. That is the whole difference between a
/// pet and a mascot, and it is cheaper to state here than to rediscover.
///
/// Pure geometry, no UI, and the only copy — same rule `CreatureSilhouette`
/// follows, so the offscreen render harness and the app draw one character.
public enum CompanionRig {
    /// Everything the character is made of, in draw order.
    public static func layers(
        _ p: CompanionRigParameters,
        in rect: CGRect
    ) -> [CompanionLayer] {
        Builder(p: p, rect: rect).layers()
    }

    /// The unit-space footprint the character keeps at every pose, as a
    /// fraction of `rect`. Callers size the frame from this so that breathing
    /// and swaying cannot change the layout around it.
    public static let footprint = CGSize(width: 0.92, height: 0.98)

    private struct Builder {
        let p: CompanionRigParameters
        let rect: CGRect

        /// Unit space: x and y both 0...1, y growing upward from the ground
        /// line, origin at the frame's bottom-left.
        func pt(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        func sz(_ w: Double, _ h: Double) -> CGSize {
            CGSize(width: rect.width * w, height: rect.height * h)
        }

        /// An ellipse given its centre and size in unit space.
        func ellipse(cx: Double, cy: Double, w: Double, h: Double, _ t: CGAffineTransform? = nil) -> CGPath {
            let size = sz(w, h)
            let centre = pt(cx, cy)
            let box = CGRect(
                x: centre.x - size.width / 2,
                y: centre.y - size.height / 2,
                width: size.width,
                height: size.height
            )
            var transform = t ?? .identity
            return CGPath(ellipseIn: box, transform: &transform)
        }

        /// A limb, as a round-capped stroke from shoulder to hand.
        func limb(from: CGPoint, to: CGPoint, width: Double) -> CGPath {
            let line = CGMutablePath()
            line.move(to: from)
            line.addLine(to: to)
            return line.copy(
                strokingWithWidth: rect.width * width,
                lineCap: .round,
                lineJoin: .round,
                miterLimit: 4
            )
        }

        // MARK: - Derived geometry

        /// Weight shift rotates the whole character about the point the feet
        /// touch the ground, so a sway never lifts it off its own shadow.
        var stance: CGAffineTransform {
            let pivot = pt(0.5, groundY)
            let angle = CGFloat(p.sway) * 0.05
            return CGAffineTransform(translationX: pivot.x, y: pivot.y)
                .rotated(by: angle)
                .translatedBy(x: -pivot.x, y: -pivot.y)
        }

        var groundY: Double { 0.035 }

        /// Breath lifts the chest and, a little less, the head — a body that
        /// rises perfectly rigidly reads as a lift, not a breath.
        var chestRise: Double { p.breath * 0.018 }

        var bodyCY: Double { 0.31 - p.settle * 0.050 + chestRise * 0.4 }
        var bodyW: Double { 0.46 + p.settle * 0.085 }
        var bodyH: Double { 0.42 - p.settle * 0.075 + chestRise }

        /// The head sinks toward the body as the character settles, which is
        /// what makes a curled-up sleeper rather than a shorter standing one.
        var headCY: Double { 0.70 - p.settle * 0.145 + chestRise * 0.8 }
        var headCX: Double { 0.5 + p.headTurn * 0.055 }
        var headW: Double { 0.50 }
        var headH: Double { 0.44 }

        /// Tilt pivots at the neck, not at the head's own centre — rotating a
        /// head about its middle detaches it from the shoulders.
        var headTransform: CGAffineTransform {
            let neck = pt(0.5, headCY - headH * 0.42)
            return CGAffineTransform(translationX: neck.x, y: neck.y)
                .rotated(by: CGFloat(p.headTilt) * 0.20)
                .translatedBy(x: -neck.x, y: -neck.y)
                .concatenating(stance)
        }

        func layers() -> [CompanionLayer] {
            var out: [CompanionLayer] = []
            // `copy(using:)` takes the transform `inout`; it does not mutate it.
            var stanceT = stance

            // Contact shadow, computed from the stance rather than pasted under
            // it: a lean puts more of the character over one foot, and the
            // shadow shortens and slides with it.
            let shadowCX = 0.5 + Double(p.sway) * 0.035
            let shadowW = 0.54 + p.settle * 0.12 - abs(Double(p.sway)) * 0.04
            out.append(.init(
                role: .shadow,
                path: ellipse(cx: shadowCX, cy: groundY + 0.004, w: shadowW, h: 0.050)
            ))

            // Tail: thick at the root, tapering, curling *around* the near hip
            // rather than sticking out. Built as a filled outline instead of a
            // stroked line, because a constant-width stroke is what made the
            // first pass read as a door handle.
            out.append(.init(role: .limb, path: tailPath(&stanceT)))

            // Haunches, then feet — drawn before the body so its edge overlaps
            // them and the leg reads as joined rather than parked alongside.
            for side in [-1.0, 1.0] {
                out.append(.init(
                    role: .limb,
                    path: ellipse(
                        cx: 0.5 + side * (0.155 + p.settle * 0.035),
                        cy: groundY + 0.055,
                        w: 0.185, h: 0.105, stance
                    )
                ))
            }

            // Ears: tall and pointed, set wide. This is the single cue that
            // separates a cat from a bear, and the first pass got it wrong by
            // drawing two circles.
            for side in [-1.0, 1.0] {
                let baseX = 0.5 + side * 0.175 + p.headTurn * 0.050
                let baseY = headCY + headH * 0.26
                let base = pt(baseX, baseY)
                let perk = CGAffineTransform(translationX: base.x, y: base.y)
                    .rotated(by: CGFloat(side * (0.34 - p.earPerk * 0.30)))
                    .translatedBy(x: -base.x, y: -base.y)
                    .concatenating(headTransform)

                out.append(.init(role: .body, path: ear(baseX: baseX, baseY: baseY, scale: 1.0, perk)))
                out.append(.init(role: .light, path: ear(baseX: baseX, baseY: baseY, scale: 0.52, perk)))
            }

            // Arms, before the body: the shoulder end disappears under the
            // chest, which is what a joint looks like.
            for (side, lift) in [(-1.0, p.armLiftTrailing), (1.0, p.armLiftLeading)] {
                let shoulder = pt(0.5 + side * bodyW * 0.24, bodyCY + bodyH * 0.22)
                let hand = pt(
                    0.5 + side * (bodyW * 0.60 + lift * 0.175),
                    bodyCY - bodyH * 0.26 + lift * (headH * 0.95)
                )
                // Upper arm thick where it leaves the shoulder, forearm
                // thinner, then a paw — three pieces so the limb tapers instead
                // of arriving as one capsule.
                let elbow = CGPoint(
                    x: shoulder.x + (hand.x - shoulder.x) * 0.55,
                    y: shoulder.y + (hand.y - shoulder.y) * 0.55
                )
                let upper = limb(from: shoulder, to: elbow, width: 0.098)
                let fore = limb(from: elbow, to: hand, width: 0.076)
                let paw = CGMutablePath()
                let pawR = rect.width * 0.052
                paw.addEllipse(in: CGRect(
                    x: hand.x - pawR, y: hand.y - pawR,
                    width: pawR * 2, height: pawR * 2
                ))
                for piece in [upper, fore, paw as CGPath] {
                    out.append(.init(role: .limb, path: piece.copy(using: &stanceT) ?? piece))
                }
            }

            // Body, then the lighter front.
            out.append(.init(
                role: .body,
                path: ellipse(cx: 0.5, cy: bodyCY, w: bodyW, h: bodyH, stance)
            ))
            out.append(.init(
                role: .light,
                path: ellipse(
                    cx: 0.5, cy: bodyCY - bodyH * 0.12,
                    w: bodyW * 0.56, h: bodyH * 0.62, stance
                )
            ))

            // Head over the shoulders.
            out.append(.init(
                role: .body,
                path: ellipse(cx: headCX, cy: headCY, w: headW, h: headH, headTransform)
            ))

            // Muzzle low and wide, nose above it.
            out.append(.init(
                role: .light,
                path: ellipse(
                    cx: headCX, cy: headCY - headH * 0.24,
                    w: 0.235, h: 0.150, headTransform
                )
            ))
            out.append(.init(
                role: .feature,
                path: ellipse(
                    cx: headCX, cy: headCY - headH * 0.12,
                    w: 0.062, h: 0.046, headTransform
                )
            ))

            out.append(contentsOf: eyes())
            return out
        }

        /// Both eyes and their lids.
        ///
        /// The eye is *clipped from the top* rather than covered by a lid drawn
        /// over it. A lid ellipse laid on top of a round eye leaves a curved
        /// lower edge, and a curved lower edge on a half-closed eye is a scowl
        /// — the first pass made "resting" look furious.
        func eyes() -> [CompanionLayer] {
            var out: [CompanionLayer] = []
            let openH = 0.115
            let visible = openH * (1 - p.blink)

            for side in [-1.0, 1.0] {
                let eyeCX = headCX + side * 0.128
                let eyeCY = headCY + headH * 0.10

                if visible > 0.012 {
                    // Sits on the lower lid line, so closing drops the top edge
                    // and the eye shuts downward the way an eye does.
                    out.append(.init(
                        role: .feature,
                        path: ellipse(
                            cx: eyeCX,
                            cy: eyeCY - (openH - visible) / 2,
                            w: 0.092, h: visible,
                            headTransform
                        )
                    ))
                } else {
                    // Fully shut: a flat lash line, which reads as closed where
                    // an absent eye reads as a hole.
                    out.append(.init(
                        role: .feature,
                        path: ellipse(
                            cx: eyeCX, cy: eyeCY - openH / 2,
                            w: 0.092, h: 0.020,
                            headTransform
                        )
                    ))
                }
            }
            return out
        }

        /// A tapered tail: an outline down one side and back up the other, so
        /// it is thick where it leaves the body and fine at the tip.
        func tailPath(_ t: inout CGAffineTransform) -> CGPath {
            let swish = Double(p.tailSwish)
            let rootX = 0.5 + 0.13
            let rootY = bodyCY - bodyH * 0.40
            let tipX = 0.5 + 0.40 + swish * 0.030
            let tipY = bodyCY + bodyH * (0.30 + Double(swish) * 0.14)

            let path = CGMutablePath()
            path.move(to: pt(rootX, rootY - 0.055))
            path.addQuadCurve(
                to: pt(tipX, tipY),
                control: pt(0.5 + 0.42, rootY - 0.045)
            )
            path.addQuadCurve(
                to: pt(rootX, rootY + 0.055),
                control: pt(0.5 + 0.255, rootY + 0.030)
            )
            path.closeSubpath()
            return path.copy(using: &t) ?? path
        }

        /// One ear, as a rounded triangle standing on the skull.
        func ear(baseX: Double, baseY: Double, scale: Double, _ t: CGAffineTransform) -> CGPath {
            let w = 0.150 * scale
            let h = 0.185 * scale
            let path = CGMutablePath()
            path.move(to: pt(baseX - w / 2, baseY))
            path.addQuadCurve(
                to: pt(baseX, baseY + h),
                control: pt(baseX - w * 0.34, baseY + h * 0.72)
            )
            path.addQuadCurve(
                to: pt(baseX + w / 2, baseY),
                control: pt(baseX + w * 0.34, baseY + h * 0.72)
            )
            path.closeSubpath()
            var transform = t
            return path.copy(using: &transform) ?? path
        }

    }
}
