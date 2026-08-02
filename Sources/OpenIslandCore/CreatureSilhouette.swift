import CoreGraphics
import Foundation

/// Builds the drawable outline for a `CreatureForm`.
///
/// This lives in Core, and is the *only* copy, because the render harness is
/// the gate. If the harness drew one shape and the view drew another, the gate
/// would be measuring something that does not ship — and a comment asking two
/// files to stay in step is a wish, not a mechanism. `scripts/creature-gate.swift`
/// and the app's creature view both call this.
///
/// Pure geometry, no UI: it takes a rect in points and returns a path. Callers
/// supply their own scale, colour and context.
public enum CreatureSilhouette {
    /// The measured right-slot lane: 44pt reserve minus 16pt padding, against
    /// the 32pt closed pill on a built-in display.
    public static let pillLane = CGSize(width: 28, height: 32)

    /// Panel optical size. Pill and panel are separately authored sizes, not one
    /// master scaled — this is the geometry stand-in for the larger one.
    public static let panelLane = CGSize(width: 56, height: 64)

    /// The silhouette for `form`, laid out in points inside `rect`.
    ///
    /// - Parameter includeArms: when false, returns the body alone. Used by the
    ///   gate to measure how far the arms break the body's outline, which is the
    ///   number the pose design is judged on.
    public static func path(
        for form: CreatureForm,
        in rect: CGRect,
        includeArms: Bool = true
    ) -> CGPath {
        let path = CGMutablePath()
        let w = rect.width * CGFloat(form.bodyWidth)
        let h = rect.height * CGFloat(form.bodyHeight)
        let body = CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)

        let transform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .rotated(by: CGFloat(form.tilt))
            .translatedBy(x: -rect.midX, y: -rect.midY)

        // 0 is a soft rounded rectangle, 1 is a full capsule. Corner radius is
        // the cheapest visible difference between two creatures at this size —
        // it costs no lane width, which nothing else here can say.
        let corner = CGFloat(form.roundness)
        path.addRoundedRect(
            in: body,
            cornerWidth: w * (0.26 + corner * 0.24),
            cornerHeight: h * (0.20 + corner * 0.30),
            transform: transform
        )
        guard includeArms else { return path }

        // `shoulder` is a fraction of body height measured from the top;
        // CoreGraphics y grows upward, so this counts down from the body's top.
        let shoulderY = body.minY + body.height * CGFloat(1.0 - form.shoulder)
        let stroke = max(1.0, w * 0.17)
        let halfStroke = stroke / 2

        // A raised arm travels *outward*, not upward. The lane leaves 4.5-6.7pt
        // at the sides and at most 4.2pt above the body — and that headroom is
        // the physical top edge of the display, where nothing can be drawn at
        // all. An earlier version shrank the silhouette as lift rose, which is
        // backwards: the pose that should shout ended up narrowest.
        //
        // Round caps extend half a stroke past the tip, so the limits are inset
        // by that much and a fully raised arm lands exactly on the lane edge.
        let outX = rect.width / 2 - halfStroke
        let outY = min(body.maxY + h * 0.06, rect.maxY - halfStroke)

        for (side, lift) in [(CGFloat(-1), CGFloat(form.armLiftTrailing)),
                             (CGFloat(1), CGFloat(form.armLiftLeading))] {
            let x0 = rect.midX + side * w * 0.44
            // Hanging: tucked along the flank, just proud of the body edge.
            let hangX = x0 + side * w * 0.10
            let hangY = shoulderY - h * 0.22
            let x1 = hangX + (rect.midX + side * outX - hangX) * lift
            let y1 = hangY + (outY - hangY) * lift

            let arm = CGMutablePath()
            arm.move(to: CGPoint(x: x0, y: shoulderY))
            arm.addLine(to: CGPoint(x: x1, y: y1))
            let stroked = arm.copy(
                strokingWithWidth: stroke,
                lineCap: .round, lineJoin: .round, miterLimit: 4
            )
            path.addPath(stroked, transform: transform)
        }
        return path
    }
}
