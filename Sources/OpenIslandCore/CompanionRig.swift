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
        /// The one bright note in the drawing — a glow, a highlight, an inner
        /// ear. Bounded by the body, so it is free of the ground's contrast
        /// floor and is where the destination surface gets its colour back.
        case accent
    }

    public let role: Role
    public let path: CGPath
    /// Fill rule. A path with two subpaths and even-odd fill is a shape with a
    /// hole in it, which is a silhouette cue nothing else in this rig can make.
    public let evenOdd: Bool

    public init(role: Role, path: CGPath, evenOdd: Bool = false) {
        self.role = role
        self.path = path
        self.evenOdd = evenOdd
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

// MARK: - Character directions

/// Six body plans, kept as alternatives rather than as a roster.
///
/// The brief they answer is a silhouette one: at 20pt the only thing a viewer
/// gets is the outline's aspect, its major protrusions, and its holes. Two
/// round animals are the same drawing at that size no matter how different
/// their faces are, which is how the previous two passes both ended up
/// proposing the same blob twice. So these are separated by *outline signature*
/// first and by species second:
///
/// | | signature |
/// |---|---|
/// | `cat` | tall cone, two sharp points on top, a hook up one side |
/// | `otter` | long horizontal bar, head lifted at one end |
/// | `ghost` | smooth dome over a scalloped hem, no ground contact |
/// | `earling` | two huge round lobes over a tiny body — top-heavy T |
/// | `coil` | narrow vertical stalk standing in a ring with a real hole |
/// | `shard` | straight edges only, a jagged crown, no curve anywhere |
public enum CompanionCharacter: String, CaseIterable, Sendable {
    case cat, otter, ghost, earling, coil, shard
}

extension CompanionRig {
    /// Width over height of the box this character wants.
    ///
    /// Per-character rather than one shared frame because a horizontal body
    /// squeezed into a tall frame just becomes a small one — the whole point of
    /// `otter` is the axis, and the axis only exists if the frame gives it room.
    public static func aspect(for character: CompanionCharacter) -> Double {
        switch character {
        case .cat: 0.72
        case .otter: 1.70
        case .ghost: 0.86
        case .earling: 1.30
        case .coil: 0.78
        case .shard: 0.80
        }
    }

    /// Everything this character is made of, in draw order.
    public static func layers(
        _ p: CompanionRigParameters,
        character: CompanionCharacter,
        in rect: CGRect
    ) -> [CompanionLayer] {
        let canvas = RigCanvas(rect: rect)
        switch character {
        case .cat: return CatPlan(p: p, c: canvas).layers()
        case .otter: return OtterPlan(p: p, c: canvas).layers()
        case .ghost: return GhostPlan(p: p, c: canvas).layers()
        case .earling: return EarlingPlan(p: p, c: canvas).layers()
        case .coil: return CoilPlan(p: p, c: canvas).layers()
        case .shard: return ShardPlan(p: p, c: canvas).layers()
        }
    }
}

// MARK: - Drawing primitives

/// Unit space and the shapes that can be built in it.
///
/// x and y are both 0...1 fractions of the frame, y growing upward. The one
/// wrinkle worth stating: a *length* given as an x-fraction and the same length
/// given as a y-fraction are different physical lengths unless the frame is
/// square, and these frames deliberately are not. `hx(_:)` converts a
/// height-fraction into the x-fraction that draws the same physical size, which
/// is what round things and even-width ribbons need.
struct RigCanvas {
    let rect: CGRect

    var aspect: Double { rect.width / rect.height }

    func pt(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
    }

    /// A height-fraction expressed as the x-fraction of the same physical length.
    func hx(_ d: Double) -> Double { d * rect.height / rect.width }

    func apply(_ path: CGPath, _ t: CGAffineTransform?) -> CGPath {
        guard var t else { return path }
        return path.copy(using: &t) ?? path
    }

    func ellipse(_ cx: Double, _ cy: Double, _ w: Double, _ h: Double, _ t: CGAffineTransform? = nil) -> CGPath {
        let centre = pt(cx, cy)
        let box = CGRect(
            x: centre.x - rect.width * w / 2,
            y: centre.y - rect.height * h / 2,
            width: rect.width * w,
            height: rect.height * h
        )
        var transform = t ?? .identity
        return CGPath(ellipseIn: box, transform: &transform)
    }

    /// A circle of diameter `d`, given as a fraction of the frame's height.
    func circle(_ cx: Double, _ cy: Double, _ d: Double, _ t: CGAffineTransform? = nil) -> CGPath {
        ellipse(cx, cy, hx(d), d, t)
    }

    /// Straight edges, closed. The only shape `shard` is allowed.
    func poly(_ pts: [(Double, Double)], _ t: CGAffineTransform? = nil) -> CGPath {
        let path = CGMutablePath()
        guard let first = pts.first else { return path }
        path.move(to: pt(first.0, first.1))
        for q in pts.dropFirst() { path.addLine(to: pt(q.0, q.1)) }
        path.closeSubpath()
        return apply(path, t)
    }

    /// A closed smooth curve *through* the given points.
    ///
    /// The single most important addition to this rig. Everything the previous
    /// passes drew was an ellipse or a union of ellipses, and a union of
    /// ellipses is a blob by construction — no amount of parameter tuning gets
    /// a jaw, a shoulder, or a haunch out of it. Catmull–Rom converted to cubic
    /// Bézier lets a silhouette be *authored* as a handful of landmarks.
    func curve(_ pts: [(Double, Double)], tension: Double = 1.0, _ t: CGAffineTransform? = nil) -> CGPath {
        let path = CGMutablePath()
        let n = pts.count
        guard n >= 3 else { return path }
        let p = pts.map { pt($0.0, $0.1) }
        path.move(to: p[0])
        for i in 0..<n {
            let p0 = p[(i - 1 + n) % n]
            let p1 = p[i]
            let p2 = p[(i + 1) % n]
            let p3 = p[(i + 2) % n]
            let k = CGFloat(tension) / 6
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) * k, y: p1.y + (p2.y - p0.y) * k)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) * k, y: p2.y - (p3.y - p1.y) * k)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        path.closeSubpath()
        return apply(path, t)
    }

    /// A tapered ribbon along a spine: tails, coils, limbs, wisps.
    ///
    /// Half-widths are in height-fractions and are interpolated along the
    /// spine, so a tail can be thick where it leaves the body and fine at the
    /// tip. A constant-width stroke is what made the committed rig's tail read
    /// as a door handle.
    func band(
        _ spine: [(Double, Double)],
        _ half: [Double],
        _ t: CGAffineTransform? = nil
    ) -> CGPath {
        let n = spine.count
        let path = CGMutablePath()
        guard n >= 2, half.count == n else { return path }

        func cr(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ u: Double) -> Double {
            0.5 * ((2 * b) + (-a + c) * u
                + (2 * a - 5 * b + 4 * c - d) * u * u
                + (-a + 3 * b - 3 * c + d) * u * u * u)
        }

        var centres: [CGPoint] = []
        var widths: [CGFloat] = []
        let steps = 10
        for i in 0..<(n - 1) {
            let a = spine[max(0, i - 1)], b = spine[i]
            let c = spine[i + 1], d = spine[min(n - 1, i + 2)]
            for s in 0..<steps {
                let u = Double(s) / Double(steps)
                centres.append(pt(cr(a.0, b.0, c.0, d.0, u), cr(a.1, b.1, c.1, d.1, u)))
                widths.append(CGFloat((half[i] + (half[i + 1] - half[i]) * u) * rect.height))
            }
        }
        centres.append(pt(spine[n - 1].0, spine[n - 1].1))
        widths.append(CGFloat(half[n - 1] * rect.height))

        let m = centres.count
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for i in 0..<m {
            let prev = centres[max(0, i - 1)]
            let next = centres[min(m - 1, i + 1)]
            var tx = next.x - prev.x
            var ty = next.y - prev.y
            let len = max(1e-6, (tx * tx + ty * ty).squareRoot())
            tx /= len; ty /= len
            let nx = -ty, ny = tx
            left.append(CGPoint(x: centres[i].x + nx * widths[i], y: centres[i].y + ny * widths[i]))
            right.append(CGPoint(x: centres[i].x - nx * widths[i], y: centres[i].y - ny * widths[i]))
        }

        path.move(to: left[0])
        for q in left.dropFirst() { path.addLine(to: q) }
        for q in right.reversed() { path.addLine(to: q) }
        path.closeSubpath()
        return apply(path, t)
    }

    /// A closed ring: outer boundary and an inner one, even-odd filled by the
    /// caller so the middle is genuinely empty rather than painted the ground's
    /// colour. Painting it would break the moment the ground changed.
    func ring(
        cx: Double, cy: Double,
        outer: Double, thickness: Double,
        squash: Double = 1.0,
        _ t: CGAffineTransform? = nil
    ) -> CGPath {
        let path = CGMutablePath()
        let inner = max(0.01, outer - thickness)
        path.addPath(ellipse(cx, cy, hx(outer * 2), outer * 2 * squash))
        path.addPath(ellipse(cx, cy, hx(inner * 2), inner * 2 * squash))
        return apply(path, t)
    }

    /// Rotation about a point given in unit space.
    func pivot(_ x: Double, _ y: Double, _ radians: Double, _ base: CGAffineTransform = .identity) -> CGAffineTransform {
        let o = pt(x, y)
        return CGAffineTransform(translationX: o.x, y: o.y)
            .rotated(by: CGFloat(radians))
            .translatedBy(x: -o.x, y: -o.y)
            .concatenating(base)
    }
}

/// Shared pose arithmetic. Every plan wants breath, sway and settle to mean the
/// same thing, and a character that interpreted `settle` its own way would make
/// the four states stop matching across directions.
struct RigPose {
    let p: CompanionRigParameters
    let c: RigCanvas

    /// Chest rise. Small on purpose — breath that reads as a lift is not breath.
    var rise: Double { p.breath * 0.016 }
    var settle: Double { p.settle }
    /// Weight shift, about the point the feet touch the ground.
    func stance(groundY: Double, amount: Double = 0.045) -> CGAffineTransform {
        c.pivot(0.5, groundY, Double(p.sway) * amount)
    }
    /// Eye opening, 0...1.
    var open: Double { 1 - p.blink }
}

// MARK: - Cat

/// The obvious one, done on purpose rather than by default.
///
/// A sitting cat is a *cone*, not a circle: wide haunches, a chest that narrows
/// all the way to the shoulders, and a head that is a rounded wedge with cheek
/// flare rather than a ball. The two cues that carry it at 20pt are the ear
/// triangles — tall, sharp, set wide — and the tail, which is deliberately not
/// wrapped around the feet where it would vanish into the body's own outline,
/// but hooked up one side with air between it and the flank.
struct CatPlan {
    let p: CompanionRigParameters
    let c: RigCanvas
    var pose: RigPose { RigPose(p: p, c: c) }

    var groundY: Double { 0.055 }
    var s: Double { p.settle }
    var rise: Double { pose.rise }
    var wide: Double { 1 + s * 0.09 }
    var top: Double { 0.615 - s * 0.09 + rise }
    var headCX: Double { 0.5 + Double(p.headTurn) * 0.050 }
    var headCY: Double { 0.755 - s * 0.10 + rise * 0.8 }

    func layers() -> [CompanionLayer] {
        let stance = pose.stance(groundY: groundY)
        let head = c.pivot(0.5, headCY - 0.145, Double(p.headTilt) * 0.20, stance)
        var out: [CompanionLayer] = []

        out.append(.init(role: .shadow, path: c.ellipse(
            0.5 + Double(p.sway) * 0.03, groundY - 0.008,
            0.70 + s * 0.10, 0.045
        )))

        // Tail first: it passes behind the near flank at the root, which is what
        // makes it read as attached rather than parked alongside.
        out.append(.init(role: .behind, path: c.band(
            [
                (0.50, 0.115), (0.71, 0.058), (0.62, 0.028), (0.40, 0.018),
                (0.20, 0.045), (0.075, 0.15), (0.045, 0.33),
                (0.095, 0.475 + Double(p.tailSwish) * 0.030),
                (0.175, 0.545 + Double(p.tailSwish) * 0.055),
            ],
            [0.058, 0.055, 0.050, 0.046, 0.040, 0.034, 0.028, 0.021, 0.013],
            stance
        )))

        // Ears behind the skull so the skull's edge closes over their bases.
        for side in [-1.0, 1.0] {
            let bx = headCX + side * 0.170
            let by = headCY + 0.122
            let droop = 1 - p.earPerk
            let t = c.pivot(bx, by, -side * droop * 0.42, head)
            out.append(.init(role: .body, path: ear(bx, by, side, 1.0, t)))
            out.append(.init(role: .accent, path: ear(bx, by, side, 0.52, t)))
        }

        // A sitting cat is a cone, not a circle: wide haunches, a chest that
        // narrows all the way to the shoulders. The flank landmarks bulge
        // slightly rather than running straight, which is the difference
        // between an animal and a wedge of cheese.
        out.append(.init(role: .body, path: c.curve([
            (0.5 - 0.315 * wide, 0.080), (0.5 - 0.350 * wide, 0.185),
            (0.5 - 0.330 * wide, 0.310), (0.5 - 0.255 * wide, 0.440),
            (0.5 - 0.175 * wide, top - 0.030), (0.5 - 0.130 * wide, top),
            (0.5 + 0.130 * wide, top), (0.5 + 0.175 * wide, top - 0.030),
            (0.5 + 0.255 * wide, 0.440), (0.5 + 0.330 * wide, 0.310),
            (0.5 + 0.350 * wide, 0.185), (0.5 + 0.315 * wide, 0.080),
            (0.5, groundY),
        ], tension: 0.85, stance)))

        // Chest blaze, the drawing's mid value. Narrow and pushed left of
        // centre — a symmetric oval on the chest is a bib, not a marking.
        out.append(.init(role: .light, path: c.curve([
            (0.5 - 0.020, 0.470), (0.5 + 0.095, 0.360), (0.5 + 0.110, 0.215),
            (0.5 - 0.010, 0.130), (0.5 - 0.125, 0.215), (0.5 - 0.130, 0.360),
        ], tension: 0.9, stance)))

        // Arms *after* the body, so a sitting cat has forelegs down its front
        // rather than two limbs that only exist when they are raised.
        for (side, lift) in [(-1.0, p.armLiftTrailing), (1.0, p.armLiftLeading)] {
            out.append(contentsOf: arm(side: side, lift: lift, stance))
        }

        // Cheek flare and a blunt chin. The head is the largest single mass,
        // which is the whole difference between a pet and a mascot.
        out.append(.init(role: .body, path: c.curve([
            (headCX - 0.255, headCY + 0.030), (headCX - 0.225, headCY + 0.125),
            (headCX - 0.100, headCY + 0.172), (headCX + 0.100, headCY + 0.172),
            (headCX + 0.225, headCY + 0.125), (headCX + 0.255, headCY + 0.030),
            (headCX + 0.180, headCY - 0.105), (headCX, headCY - 0.150),
            (headCX - 0.180, headCY - 0.105),
        ], tension: 0.95, head)))

        out.append(.init(role: .light, path: c.curve([
            (headCX, headCY - 0.005), (headCX + 0.140, headCY - 0.055),
            (headCX + 0.115, headCY - 0.125), (headCX, headCY - 0.140),
            (headCX - 0.115, headCY - 0.125), (headCX - 0.140, headCY - 0.055),
        ], tension: 0.9, head)))
        out.append(.init(role: .feature, path: c.poly([
            (headCX - 0.038, headCY - 0.038), (headCX + 0.038, headCY - 0.038),
            (headCX, headCY - 0.080),
        ], head)))
        // Two whiskers a side. Invisible at 20pt by design — they are one of the
        // things the destination surface has the pixels for and the pill does not.
        for side in [-1.0, 1.0] {
            for (dy, spread) in [(0.012, 0.055), (-0.020, 0.030)] {
                out.append(.init(role: .feature, path: c.band(
                    [
                        (headCX + side * 0.090, headCY - 0.062 + dy),
                        (headCX + side * 0.260, headCY - 0.055 + dy + spread * 0.4),
                        (headCX + side * 0.395, headCY - 0.048 + dy + spread),
                    ],
                    [0.008, 0.005, 0.002], head
                )))
            }
        }

        out.append(contentsOf: eyes(head))
        return out
    }

    /// One ear: a sharp triangle with a slight outward lean, which is the single
    /// cue separating this from every round animal in the set.
    func ear(_ bx: Double, _ by: Double, _ side: Double, _ scale: Double, _ t: CGAffineTransform) -> CGPath {
        c.poly([
            (bx - side * 0.082 * scale, by - 0.005),
            (bx + side * 0.034 * scale, by + 0.168 * scale),
            (bx + side * 0.088 * scale, by - 0.012),
        ], t)
    }

    func arm(side: Double, lift: Double, _ t: CGAffineTransform) -> [CompanionLayer] {
        // The shoulder slides inward as the arm comes up: parked at the flank
        // it is a foreleg, and a foreleg drawn down the middle of the chest is
        // a stripe.
        let sx = 0.5 + side * (0.205 - lift * 0.065)
        let sy = 0.395 + lift * 0.085
        let hx = 0.5 + side * (0.170 + lift * 0.300)
        let hy = 0.098 + lift * 0.520
        let mx = sx + (hx - sx) * 0.55 + side * lift * 0.055
        let my = sy + (hy - sy) * 0.50 - (1 - lift) * 0.030
        return [
            .init(role: .limb, path: c.band(
                [(sx, sy), (mx, my), (hx, hy)],
                [0.042, 0.038, 0.031], t
            )),
            .init(role: .limb, path: c.ellipse(hx, hy - 0.008, 0.135, 0.055, t)),
        ]
    }

    func eyes(_ t: CGAffineTransform) -> [CompanionLayer] {
        var out: [CompanionLayer] = []
        let openH = 0.112
        let h = openH * pose.open
        for side in [-1.0, 1.0] {
            let ex = headCX + side * 0.120
            let ey = headCY + 0.038
            if h > 0.012 {
                out.append(.init(role: .feature, path: c.ellipse(
                    ex, ey - (openH - h) / 2, 0.130, h, t
                )))
                out.append(.init(role: .accent, path: c.circle(
                    ex + side * 0.024, ey + h * 0.20, min(0.034, h * 0.42), t
                )))
            } else {
                out.append(.init(role: .feature, path: c.ellipse(
                    ex, ey - openH / 2, 0.130, 0.022, t
                )))
            }
        }
        return out
    }
}

// MARK: - Otter

/// The horizontal one.
///
/// Everything else in this set stands up; this lies along the ground and is a
/// bar rather than a tower. The axis *is* the character, so the frame is 1.70
/// wide — squeezing it into a tall lane does not make a long animal, it makes a
/// small one, which is worth knowing before anyone chooses it.
struct OtterPlan {
    let p: CompanionRigParameters
    let c: RigCanvas
    var pose: RigPose { RigPose(p: p, c: c) }

    var groundY: Double { 0.10 }
    var s: Double { p.settle }
    var rise: Double { pose.rise }
    var headCX: Double { 0.790 + Double(p.headTurn) * 0.020 }
    var headCY: Double { 0.570 - s * 0.100 + rise * 0.8 }

    func layers() -> [CompanionLayer] {
        let stance = pose.stance(groundY: groundY, amount: 0.020)
        let head = c.pivot(headCX - 0.06, headCY - 0.15, Double(p.headTilt) * 0.18, stance)
        var out: [CompanionLayer] = []

        out.append(.init(role: .shadow, path: c.ellipse(
            0.48, groundY - 0.030, 0.80, 0.070
        )))

        // Tail: thick where it leaves the rump, fine at the tip, lifted clear of
        // the ground so the long axis ends in a flick instead of a stump.
        out.append(.init(role: .behind, path: c.band(
            [
                (0.310, 0.290), (0.185, 0.245), (0.095, 0.215),
                (0.038, 0.290 + Double(p.tailSwish) * 0.060),
                (0.020, 0.430 + Double(p.tailSwish) * 0.110),
            ],
            [0.175, 0.152, 0.115, 0.070, 0.026], stance
        )))

        // Far forelimb, behind the chest.
        out.append(contentsOf: arm(lift: p.armLiftTrailing, far: true, stance))
        for x in [0.330, 0.615] {
            out.append(.init(role: .limb, path: c.ellipse(x, groundY + 0.005, 0.080, 0.075, stance)))
        }

        // One unbroken back line from rump to skull. The neck landmark is the
        // load-bearing one: without it the head arrives as a ball parked on a
        // sausage, which is what the first pass drew.
        out.append(.init(role: .body, path: c.curve([
            (0.205, 0.130), (0.160, 0.310), (0.215, 0.470),
            (0.345, 0.540 + rise), (0.530, 0.560 + rise), (0.680, 0.535 + rise),
            (0.775, 0.470 + rise * 0.6), (0.800, 0.360), (0.775, 0.235),
            (0.660, 0.130), (0.450, 0.100), (0.300, 0.108),
        ], tension: 0.95, stance)))

        // Belly, the lighter front. Runs the length of the body — on a long
        // animal a round belly patch reads as a stain.
        out.append(.init(role: .light, path: c.curve([
            (0.265, 0.145), (0.430, 0.122), (0.625, 0.150),
            (0.720, 0.240), (0.660, 0.320), (0.430, 0.330), (0.275, 0.265),
        ], tension: 0.9, stance)))

        // Small round ears — the anti-cat cue, and the reason this silhouette
        // cannot be read as the same animal lying down.
        for dx in [-0.062, 0.052] {
            out.append(.init(role: .body, path: c.circle(
                headCX + dx, headCY + 0.185 + p.earPerk * 0.020, 0.125, head
            )))
            out.append(.init(role: .accent, path: c.circle(
                headCX + dx, headCY + 0.183 + p.earPerk * 0.020, 0.058, head
            )))
        }

        out.append(.init(role: .body, path: c.curve([
            (headCX - 0.115, headCY + 0.030), (headCX - 0.098, headCY + 0.160),
            (headCX - 0.015, headCY + 0.212), (headCX + 0.085, headCY + 0.150),
            (headCX + 0.125, headCY + 0.020), (headCX + 0.100, headCY - 0.130),
            (headCX - 0.020, headCY - 0.185), (headCX - 0.112, headCY - 0.100),
        ], tension: 0.95, head)))

        // Pale muzzle mask, pushed forward: the snout is what makes it a river
        // animal rather than a bear cub in profile.
        out.append(.init(role: .light, path: c.curve([
            (headCX + 0.020, headCY + 0.030), (headCX + 0.110, headCY - 0.010),
            (headCX + 0.098, headCY - 0.125), (headCX - 0.010, headCY - 0.168),
            (headCX - 0.070, headCY - 0.080), (headCX - 0.050, headCY + 0.010),
        ], tension: 0.9, head)))
        out.append(.init(role: .feature, path: c.ellipse(
            headCX + 0.078, headCY - 0.040, 0.075, 0.075, head
        )))

        out.append(contentsOf: eyes(head))
        out.append(contentsOf: arm(lift: p.armLiftLeading, far: false, stance))
        return out
    }

    /// The near forelimb is drawn last, over everything.
    ///
    /// A raised paw on a horizontal animal has to clear the *head*, not the
    /// back — the head is the highest point and an arm that stops at the
    /// shoulder line disappears behind it. That is why the lifted hand travels
    /// forward as well as up.
    func arm(lift: Double, far: Bool, _ t: CGAffineTransform) -> [CompanionLayer] {
        let back = far ? 0.085 : 0.0
        let sx = 0.715 - back
        let sy = 0.275
        let hx = 0.760 - back + lift * 0.145
        let hy = 0.115 + lift * 0.815
        let role: CompanionLayer.Role = far ? .behind : .limb
        return [
            .init(role: role, path: c.band(
                [(sx, sy), (sx + (hx - sx) * 0.5 + 0.020, sy + (hy - sy) * 0.5 - 0.040), (hx, hy)],
                [0.082, 0.066, 0.046], t
            )),
            .init(role: role, path: c.circle(hx, hy, 0.115, t)),
        ]
    }

    func eyes(_ t: CGAffineTransform) -> [CompanionLayer] {
        var out: [CompanionLayer] = []
        let openH = 0.105
        let h = openH * pose.open
        for (dx, dy) in [(-0.056, 0.075), (0.050, 0.066)] {
            let ex = headCX + dx
            let ey = headCY + dy
            if h > 0.012 {
                out.append(.init(role: .feature, path: c.ellipse(
                    ex, ey - (openH - h) / 2, 0.062, h, t
                )))
                out.append(.init(role: .accent, path: c.circle(ex + 0.012, ey + h * 0.22, min(0.030, h * 0.40), t)))
            } else {
                out.append(.init(role: .feature, path: c.ellipse(ex, ey - openH / 2, 0.062, 0.020, t)))
            }
        }
        return out
    }
}

// MARK: - Ghost

/// The not-quite-an-animal.
///
/// No ears, no tail, no legs, and — the part that carries at 20pt — no ground
/// contact: it hangs above its own shadow, and the gap under it is a silhouette
/// cue in its own right. The hem is scalloped rather than straight so the
/// bottom edge is as identifiable as the top, and the whole outline is one
/// continuous curve, which is precisely what nothing else in this set is.
struct GhostPlan {
    let p: CompanionRigParameters
    let c: RigCanvas
    var pose: RigPose { RigPose(p: p, c: c) }

    var s: Double { p.settle }
    var rise: Double { pose.rise }
    /// Hover height. Settling brings it down toward the ground without ever
    /// landing — a ghost that touches down is a blob.
    var lift: Double { 0.10 - s * 0.055 + rise * 1.6 }
    var headCX: Double { 0.5 + Double(p.headTurn) * 0.045 }

    func layers() -> [CompanionLayer] {
        let stance = c.pivot(0.5, 0.05, Double(p.sway) * 0.035)
        let tilt = c.pivot(0.5, 0.35 + lift, Double(p.headTilt) * 0.13, stance)
        var out: [CompanionLayer] = []

        // Small and soft, and detached: the shadow of something that is not
        // standing on anything.
        out.append(.init(role: .shadow, path: c.ellipse(
            0.5 + Double(p.sway) * 0.05, 0.045, 0.42 + s * 0.10, 0.038
        )))

        out.append(.init(role: .body, path: body(tilt)))
        // A pale core, held well inside the hem so the drawing has a light
        // centre without touching the ground's contrast floor. Offset up and
        // to one side: a concentric one reads as a target.
        out.append(.init(role: .light, path: c.curve([
            (0.480, 0.590 + lift), (0.625, 0.500 + lift), (0.640, 0.375 + lift),
            (0.500, 0.300 + lift), (0.365, 0.350 + lift), (0.350, 0.500 + lift),
        ], tension: 0.95, tilt)))

        // Wisps, not arms. Same colour as the body — a darker limb tone on a
        // creature with no joints reads as a hole punched in it.
        for (side, armLift) in [(-1.0, p.armLiftTrailing), (1.0, p.armLiftLeading)] {
            out.append(.init(role: .body, path: c.band(
                [
                    (0.5 + side * 0.270, 0.480 + lift),
                    (0.5 + side * (0.400 + armLift * 0.075), 0.430 + lift + armLift * 0.250),
                    (0.5 + side * (0.470 + armLift * 0.075), 0.320 + lift + armLift * 0.500),
                ],
                [0.062, 0.042, 0.016], tilt
            )))
        }

        out.append(contentsOf: eyes(tilt))
        // A small open mouth. On a face with no muzzle and no nose this is the
        // only thing that makes two dots read as eyes rather than as holes.
        out.append(.init(role: .feature, path: c.ellipse(
            headCX, 0.580 + lift, 0.072, 0.056, tilt
        )))
        return out
    }

    /// One closed outline: a bell, then four scallops back along the bottom.
    func body(_ t: CGAffineTransform) -> CGPath {
        let path = CGMutablePath()
        let hem = 0.230 + lift
        let flutter = 0.030 * (0.4 + p.breath * 0.6)
        let drift = Double(p.tailSwish) * 0.030

        path.move(to: c.pt(0.120, hem + 0.010))
        path.addCurve(
            to: c.pt(0.500, 0.965 + lift * 0.35),
            control1: c.pt(0.075, 0.640 + lift),
            control2: c.pt(0.185, 0.965 + lift * 0.35)
        )
        path.addCurve(
            to: c.pt(0.880, hem + 0.010),
            control1: c.pt(0.815, 0.965 + lift * 0.35),
            control2: c.pt(0.925, 0.640 + lift)
        )

        let xs = [0.880, 0.690, 0.500, 0.310, 0.120]
        let ends = [0.010, -0.014, 0.018, -0.010, 0.010]
        for i in 0..<4 {
            path.addQuadCurve(
                to: c.pt(xs[i + 1], hem + ends[i + 1]),
                control: c.pt(
                    (xs[i] + xs[i + 1]) / 2 + drift,
                    hem - 0.145 - flutter * Double(i.isMultiple(of: 2) ? 1 : -1)
                )
            )
        }
        path.closeSubpath()
        return c.apply(path, t)
    }

    func eyes(_ t: CGAffineTransform) -> [CompanionLayer] {
        var out: [CompanionLayer] = []
        let openH = 0.185
        let h = openH * pose.open
        for side in [-1.0, 1.0] {
            let ex = headCX + side * 0.145
            let ey = 0.755 + lift
            if h > 0.020 {
                out.append(.init(role: .feature, path: c.ellipse(ex, ey - (openH - h) / 2, 0.155, h, t)))
                out.append(.init(role: .accent, path: c.circle(ex + side * 0.030, ey + h * 0.22, min(0.055, h * 0.36), t)))
            } else {
                out.append(.init(role: .feature, path: c.ellipse(ex, ey - openH / 2, 0.155, 0.028, t)))
            }
        }
        return out
    }
}

extension CGPath {
    /// `copy(using:)` with the transform passed by value, so a computed
    /// transform can be applied inline.
    func copyOffset(_ t: CGAffineTransform) -> CGPath {
        var t = t
        return copy(using: &t) ?? self
    }
}

// MARK: - Earling

/// The one where a non-body feature is the whole design.
///
/// The ears span the full frame and the body is a third of it, so the outline
/// is top-heavy — a mushroom, not a figure. Deliberately *round* ears, because
/// the cat already owns pointed ones and two characters separated only by ear
/// curvature would be the same mistake in a new coat.
struct EarlingPlan {
    let p: CompanionRigParameters
    let c: RigCanvas
    var pose: RigPose { RigPose(p: p, c: c) }

    var groundY: Double { 0.060 }
    var s: Double { p.settle }
    var rise: Double { pose.rise }
    var headCX: Double { 0.5 + Double(p.headTurn) * 0.030 }
    var headCY: Double { 0.440 - s * 0.055 + rise * 0.8 }

    func layers() -> [CompanionLayer] {
        let stance = pose.stance(groundY: groundY, amount: 0.035)
        let head = c.pivot(0.5, headCY - 0.170, Double(p.headTilt) * 0.16, stance)
        var out: [CompanionLayer] = []

        out.append(.init(role: .shadow, path: c.ellipse(
            0.5 + Double(p.sway) * 0.025, groundY - 0.010, 0.40 + s * 0.08, 0.048
        )))

        // Far ear behind the skull, near ear in front of it — the overlap is
        // what stops two big discs reading as a flat pair of wings.
        out.append(.init(role: .behind, path: earPath(-1, 1.0, head)))

        out.append(.init(role: .behind, path: c.band(
            [(0.5 + 0.130, 0.150), (0.5 + 0.190, 0.115), (0.5 + 0.215, 0.095 + Double(p.tailSwish) * 0.030)],
            [0.028, 0.017, 0.007], stance
        )))
        out.append(contentsOf: arm(side: -1, lift: p.armLiftTrailing, behind: true, stance))

        out.append(.init(role: .body, path: c.curve([
            (0.5 - 0.145, 0.078), (0.5 - 0.160, 0.170), (0.5 - 0.118, 0.290),
            (0.5, 0.340 + rise), (0.5 + 0.118, 0.290), (0.5 + 0.160, 0.170),
            (0.5 + 0.145, 0.078), (0.5, groundY),
        ], tension: 0.9, stance)))
        out.append(.init(role: .light, path: c.ellipse(0.5, 0.180, 0.165, 0.175, stance)))
        for side in [-1.0, 1.0] {
            out.append(.init(role: .limb, path: c.ellipse(0.5 + side * 0.100, groundY + 0.006, 0.090, 0.052, stance)))
        }
        out.append(contentsOf: arm(side: 1, lift: p.armLiftLeading, behind: false, stance))

        out.append(.init(role: .body, path: c.curve([
            (headCX - 0.150, headCY + 0.020), (headCX - 0.122, headCY + 0.140),
            (headCX, headCY + 0.185), (headCX + 0.122, headCY + 0.140),
            (headCX + 0.150, headCY + 0.020), (headCX + 0.090, headCY - 0.140),
            (headCX, headCY - 0.180), (headCX - 0.090, headCY - 0.140),
        ], tension: 0.95, head)))

        out.append(.init(role: .body, path: earPath(1, 1.0, head)))
        out.append(.init(role: .accent, path: earPath(1, 0.55, head)))
        out.append(.init(role: .accent, path: earPath(-1, 0.55, head)))

        out.append(.init(role: .light, path: c.ellipse(headCX, headCY - 0.085, 0.180, 0.090, head)))
        out.append(.init(role: .feature, path: c.poly([
            (headCX - 0.030, headCY - 0.048), (headCX + 0.030, headCY - 0.048), (headCX, headCY - 0.085),
        ], head)))
        out.append(contentsOf: eyes(head))
        return out
    }

    func arm(side: Double, lift: Double, behind: Bool, _ t: CGAffineTransform) -> [CompanionLayer] {
        let role: CompanionLayer.Role = behind ? .behind : .limb
        let sx = 0.5 + side * 0.105
        let sy = 0.245
        let hx = 0.5 + side * (0.155 + lift * 0.245)
        let hy = 0.100 + lift * 0.360
        return [
            .init(role: role, path: c.band(
                [(sx, sy), (sx + (hx - sx) * 0.55, sy + (hy - sy) * 0.5), (hx, hy)],
                [0.052, 0.044, 0.033], t
            )),
            .init(role: role, path: c.circle(hx, hy, 0.064, t)),
        ]
    }

    /// One ear. `scale` shrinks it toward its base for the inner-ear plate.
    func earPath(_ side: Double, _ scale: Double, _ t: CGAffineTransform) -> CGPath {
        let bx = headCX + side * 0.100
        let by = headCY + 0.100
        func q(_ dx: Double, _ dy: Double) -> (Double, Double) {
            (bx + side * dx * scale, by + dy * scale)
        }
        let path = c.curve([
            q(-0.020, -0.060), q(0.080, 0.010), q(0.235, 0.150),
            q(0.300, 0.330), q(0.215, 0.455), q(0.075, 0.400), q(0.018, 0.190),
        ], tension: 0.95)
        // Perk rotates the whole ear about its base rather than lengthening it,
        // so a flattened ear widens the outline instead of shortening it.
        let perk = c.pivot(bx, by, -side * (1 - p.earPerk) * 0.55, t)
        return path.copyOffset(perk)
    }

    func eyes(_ t: CGAffineTransform) -> [CompanionLayer] {
        var out: [CompanionLayer] = []
        let openH = 0.125
        let h = openH * pose.open
        for side in [-1.0, 1.0] {
            let ex = headCX + side * 0.072
            let ey = headCY + 0.025
            if h > 0.014 {
                out.append(.init(role: .feature, path: c.ellipse(ex, ey - (openH - h) / 2, 0.090, h, t)))
                out.append(.init(role: .accent, path: c.circle(ex + side * 0.018, ey + h * 0.22, min(0.038, h * 0.40), t)))
            } else {
                out.append(.init(role: .feature, path: c.ellipse(ex, ey - openH / 2, 0.090, 0.022, t)))
            }
        }
        return out
    }
}

// MARK: - Coil

/// The one you recognise by its hole.
///
/// A tail coiled into a genuine even-odd ring — the middle is empty, not
/// painted the ground's colour, so it shows whatever the character is standing
/// on and survives a change of ground. It is the only interior negative space
/// in this set, which is what makes it unmistakable at 20pt and is the entire
/// reason it is here.
///
/// The body stands *beside* the coil rather than out of its middle. That is not
/// a composition preference: a stalk wide enough to read at 20pt is wider than
/// the hole, so a centred body fills in the one feature the character exists
/// for. The offset is what keeps the hole a hole.
struct CoilPlan {
    let p: CompanionRigParameters
    let c: RigCanvas
    var pose: RigPose { RigPose(p: p, c: c) }

    var s: Double { p.settle }
    var rise: Double { pose.rise }
    var ringCX: Double { 0.620 }
    var ringCY: Double { 0.205 }
    var stalkX: Double { 0.375 }
    var headCX: Double { 0.430 + Double(p.headTurn) * 0.055 }
    var headCY: Double { 0.775 - s * 0.190 + rise }

    func layers() -> [CompanionLayer] {
        let stance = c.pivot(0.5, 0.05, Double(p.sway) * 0.030)
        let head = c.pivot(headCX, headCY - 0.130, Double(p.headTilt) * 0.22, stance)
        var out: [CompanionLayer] = []

        out.append(.init(role: .shadow, path: c.ellipse(0.53, 0.035, 0.84, 0.050)))

        out.append(.init(
            role: .body,
            path: c.ring(cx: ringCX, cy: ringCY, outer: 0.190, thickness: 0.074, squash: 0.95, stance),
            evenOdd: true
        ))
        // Belly plates on the near face of the coil, held inside the band.
        out.append(.init(role: .light, path: c.band(
            [(ringCX - 0.190, 0.140), (ringCX - 0.070, 0.055), (ringCX + 0.080, 0.055), (ringCX + 0.195, 0.140)],
            [0.012, 0.026, 0.026, 0.012], stance
        )))

        let bend = Double(p.tailSwish) * 0.030 + Double(p.sway) * 0.020
        out.append(.init(role: .body, path: c.band(
            [
                (stalkX - 0.010, 0.115),
                (stalkX + 0.020, 0.250),
                (stalkX - 0.035 + bend, 0.410),
                (stalkX + 0.045 - bend, 0.560),
                (headCX, headCY - 0.115),
            ],
            [0.108, 0.100, 0.088, 0.078, 0.070], stance
        )))
        for (side, lift) in [(-1.0, p.armLiftTrailing), (1.0, p.armLiftLeading)] {
            let sx = stalkX + 0.030 + side * 0.045
            let sy = 0.545
            let hx = stalkX + 0.030 + side * (0.085 + lift * 0.250)
            let hy = 0.415 + lift * 0.310
            out.append(.init(role: .limb, path: c.band(
                [(sx, sy), (sx + (hx - sx) * 0.55, sy + (hy - sy) * 0.45), (hx, hy)],
                [0.036, 0.029, 0.021], stance
            )))
            out.append(.init(role: .limb, path: c.circle(hx, hy, 0.048, stance)))
        }

        // Two backswept horns. Perk lifts them; flattened they lie along the
        // skull, which is a different outline rather than a shorter one.
        for side in [-1.0, 1.0] {
            let bx = headCX + side * 0.075
            let by = headCY + 0.065
            let t = c.pivot(bx, by, -side * (1 - p.earPerk) * 0.85, head)
            out.append(.init(role: .behind, path: c.band(
                [(bx, by), (bx + side * 0.110, by + 0.090), (bx + side * 0.170, by + 0.195)],
                [0.040, 0.026, 0.007], t
            )))
        }

        out.append(.init(role: .body, path: c.curve([
            (headCX - 0.155, headCY + 0.010), (headCX - 0.090, headCY + 0.120),
            (headCX + 0.060, headCY + 0.120), (headCX + 0.165, headCY + 0.025),
            (headCX + 0.180, headCY - 0.080), (headCX + 0.020, headCY - 0.125),
            (headCX - 0.130, headCY - 0.080),
        ], tension: 0.95, head)))
        out.append(.init(role: .light, path: c.curve([
            (headCX + 0.035, headCY - 0.005), (headCX + 0.145, headCY - 0.020),
            (headCX + 0.145, headCY - 0.075), (headCX + 0.010, headCY - 0.105),
            (headCX - 0.045, headCY - 0.045),
        ], tension: 0.9, head)))
        out.append(.init(role: .feature, path: c.ellipse(headCX + 0.135, headCY - 0.045, 0.065, 0.032, head)))

        out.append(contentsOf: eyes(head))
        return out
    }

    func eyes(_ t: CGAffineTransform) -> [CompanionLayer] {
        var out: [CompanionLayer] = []
        let openH = 0.090
        let h = openH * pose.open
        for (dx, dy) in [(-0.072, 0.030), (0.058, 0.022)] {
            let ex = headCX + dx
            let ey = headCY + dy
            if h > 0.012 {
                out.append(.init(role: .feature, path: c.ellipse(ex, ey - (openH - h) / 2, 0.100, h, t)))
                out.append(.init(role: .accent, path: c.circle(ex + 0.020, ey + h * 0.20, min(0.030, h * 0.42), t)))
            } else {
                out.append(.init(role: .feature, path: c.ellipse(ex, ey - openH / 2, 0.100, 0.018, t)))
            }
        }
        return out
    }
}

// MARK: - Shard

/// The angular one. No curve anywhere in the silhouette.
///
/// Every other direction here is built from smooth closed curves; this is built
/// from straight edges only, and that alone separates it at any size. The crown
/// spikes give it a jagged top where the ghost has a dome and the earling has
/// two lobes, and the interior facets are what make it a drawing rather than a
/// polygon — they are the destination surface's whole job on this character.
struct ShardPlan {
    let p: CompanionRigParameters
    let c: RigCanvas
    var pose: RigPose { RigPose(p: p, c: c) }

    var s: Double { p.settle }
    var rise: Double { pose.rise }
    /// Hovers, and settles toward the ground without landing.
    var hover: Double { 0.055 - s * 0.040 + rise * 1.2 }
    var headTilt: Double { Double(p.headTilt) * 0.16 }

    func layers() -> [CompanionLayer] {
        let stance = c.pivot(0.5, 0.05, Double(p.sway) * 0.045 + headTilt * 0.35)
        var out: [CompanionLayer] = []

        out.append(.init(role: .shadow, path: c.ellipse(
            0.5 + Double(p.sway) * 0.05, 0.040, 0.52 + s * 0.10, 0.042
        )))

        for (side, lift) in [(-1.0, p.armLiftTrailing), (1.0, p.armLiftLeading)] {
            let sx = 0.5 + side * 0.185
            let sy = 0.420 + hover
            let hx = 0.5 + side * (0.330 + lift * 0.185)
            let hy = 0.180 + hover + lift * 0.520
            out.append(.init(role: .limb, path: c.band(
                [(sx, sy), (sx + (hx - sx) * 0.5, sy + (hy - sy) * 0.5), (hx, hy)],
                [0.075, 0.048, 0.018], stance
            )))
            out.append(.init(role: .limb, path: c.poly([
                (hx - 0.105, hy + 0.014), (hx, hy + 0.100), (hx + 0.105, hy - 0.008), (hx, hy - 0.094),
            ], stance)))
        }

        // Crown. Perk raises the spikes; flattened they still break the outline,
        // because a jagged top with short teeth is not a smooth top.
        let perk = 0.55 + p.earPerk * 0.55
        for (cx, baseY, half, h, lean) in [
            (0.290, 0.640 + hover, 0.062, 0.230 * perk, -0.055),
            (0.500, 0.790 + hover, 0.082, 0.250 * perk, 0.014),
            (0.705, 0.640 + hover, 0.062, 0.195 * perk, 0.062),
        ] {
            out.append(.init(role: .body, path: c.poly([
                (cx - half, baseY), (cx + lean, baseY + h), (cx + half, baseY - 0.012),
            ], stance)))
        }

        // A cut gem, not a rounded one: long straight runs and a single point
        // at the bottom. Short edges read as a curve at 20pt, which is the one
        // thing this direction cannot afford.
        out.append(.init(role: .body, path: c.poly([
            (0.500, 0.820 + hover), (0.815, 0.635 + hover), (0.870, 0.365 + hover),
            (0.665, 0.145 + hover), (0.500, 0.070 + hover), (0.335, 0.145 + hover),
            (0.130, 0.365 + hover), (0.185, 0.635 + hover),
        ], stance)))

        // Facets: the drawing's whole value structure, all of it interior and
        // therefore free of the ground's contrast floor.
        out.append(.init(role: .light, path: c.poly([
            (0.520, 0.620 + hover), (0.760, 0.470 + hover),
            (0.585, 0.215 + hover), (0.470, 0.280 + hover),
        ], stance)))
        out.append(.init(role: .accent, path: c.poly([
            (0.480, 0.620 + hover), (0.240, 0.470 + hover),
            (0.330, 0.295 + hover), (0.450, 0.330 + hover),
        ], stance)))
        out.append(.init(role: .light, path: c.poly([
            (0.500, 0.225 + hover), (0.660, 0.185 + hover),
            (0.500, 0.085 + hover), (0.350, 0.185 + hover),
        ], stance)))

        out.append(contentsOf: eyes(stance))
        return out
    }

    /// Angular slits, closing by flattening rather than by shrinking.
    ///
    /// A bright core inside each: an unrelieved black quad on a faceted body
    /// reads as a chipped-out socket rather than as an eye, which is what the
    /// first pass drew.
    func eyes(_ t: CGAffineTransform) -> [CompanionLayer] {
        var out: [CompanionLayer] = []
        let h = 0.085 * pose.open + 0.016
        for side in [-1.0, 1.0] {
            let cx = 0.5 + side * 0.150
            let cy = 0.615 + hover
            func slit(_ k: Double, _ dx: Double, _ dy: Double) -> CGPath {
                c.poly([
                    (cx + dx - side * 0.082 * k, cy + dy - h * 0.15 * k),
                    (cx + dx - side * 0.034 * k, cy + dy + h * 0.85 * k),
                    (cx + dx + side * 0.082 * k, cy + dy + h * 0.45 * k),
                    (cx + dx + side * 0.034 * k, cy + dy - h * 0.55 * k),
                ], t)
            }
            out.append(.init(role: .feature, path: slit(1.0, 0, 0)))
            if pose.open > 0.35 {
                out.append(.init(role: .accent, path: slit(0.30, -side * 0.022, h * 0.20)))
            }
        }
        return out
    }
}
