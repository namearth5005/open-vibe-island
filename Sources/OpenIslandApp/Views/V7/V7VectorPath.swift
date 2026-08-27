import SwiftUI

/// A minimal SVG path-data parser.
///
/// The companion silhouettes come straight off the design board, where they
/// live as SVG `d` strings. Keeping those strings verbatim in source — rather
/// than hand-transcribing each one into `Path` calls — is what keeps the
/// shapes pixel-accurate and makes re-syncing from a future design handoff a
/// copy-paste rather than a re-draw.
///
/// Supports the commands the board actually uses: `M/m`, `L/l`, `H/h`, `V/v`,
/// `C/c`, `Q/q`, `A/a`, `Z/z`. Anything else is ignored rather than trapped, so a
/// path that picks up an unsupported command degrades to a partial shape
/// instead of crashing the panel.
enum V7VectorPath {

    /// Parses `d`, then maps the result from `viewBox` into `rect`,
    /// preserving aspect ratio and centering — the same contract as SVG's
    /// default `preserveAspectRatio="xMidYMid meet"`.
    static func path(_ d: String, viewBox: CGRect, in rect: CGRect) -> Path {
        let raw = parse(d)
        guard viewBox.width > 0, viewBox.height > 0 else { return raw }

        let scale = min(rect.width / viewBox.width, rect.height / viewBox.height)
        let dx = rect.minX + (rect.width - viewBox.width * scale) / 2 - viewBox.minX * scale
        let dy = rect.minY + (rect.height - viewBox.height * scale) / 2 - viewBox.minY * scale

        return raw.applying(
            CGAffineTransform(translationX: dx, y: dy).scaledBy(x: scale, y: scale)
        )
    }

    /// Parses `d` in its own viewBox coordinate space, untransformed.
    static func parse(_ d: String) -> Path {
        var path = Path()
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero

        var command: Character = "M"
        var numbers: [CGFloat] = []
        var index = d.startIndex

        /// Pulls the next number, tolerating the compact forms SVG allows:
        /// leading signs, exponents, and `.5.5` run together.
        func scanNumber() -> CGFloat? {
            while index < d.endIndex, d[index] == " " || d[index] == "," || d[index] == "\n" || d[index] == "\t" {
                index = d.index(after: index)
            }
            var text = ""
            if index < d.endIndex, d[index] == "-" || d[index] == "+" {
                text.append(d[index])
                index = d.index(after: index)
            }
            var sawDot = false
            while index < d.endIndex {
                let char = d[index]
                if char.isNumber {
                    text.append(char)
                } else if char == ".", !sawDot {
                    sawDot = true
                    text.append(char)
                } else if char == "e" || char == "E" {
                    text.append(char)
                    index = d.index(after: index)
                    if index < d.endIndex, d[index] == "-" || d[index] == "+" {
                        text.append(d[index])
                    } else {
                        continue
                    }
                } else {
                    break
                }
                index = d.index(after: index)
            }
            return text.isEmpty ? nil : CGFloat(Double(text) ?? 0)
        }

        func flush() {
            guard !numbers.isEmpty || command == "Z" || command == "z" else { return }
            let relative = command.isLowercase
            let base: () -> CGPoint = { relative ? current : .zero }

            switch command {
            case "M", "m":
                var cursor = 0
                var first = true
                while cursor + 1 < numbers.count {
                    let origin = base()
                    let point = CGPoint(x: origin.x + numbers[cursor], y: origin.y + numbers[cursor + 1])
                    if first {
                        path.move(to: point)
                        subpathStart = point
                        first = false
                    } else {
                        // Extra pairs after a moveto are implicit linetos.
                        path.addLine(to: point)
                    }
                    current = point
                    cursor += 2
                }
            case "L", "l":
                var cursor = 0
                while cursor + 1 < numbers.count {
                    let origin = base()
                    let point = CGPoint(x: origin.x + numbers[cursor], y: origin.y + numbers[cursor + 1])
                    path.addLine(to: point)
                    current = point
                    cursor += 2
                }
            case "H", "h":
                for value in numbers {
                    let point = CGPoint(x: (relative ? current.x : 0) + value, y: current.y)
                    path.addLine(to: point)
                    current = point
                }
            case "V", "v":
                for value in numbers {
                    let point = CGPoint(x: current.x, y: (relative ? current.y : 0) + value)
                    path.addLine(to: point)
                    current = point
                }
            case "C", "c":
                var cursor = 0
                while cursor + 5 < numbers.count {
                    let origin = base()
                    let control1 = CGPoint(x: origin.x + numbers[cursor], y: origin.y + numbers[cursor + 1])
                    let control2 = CGPoint(x: origin.x + numbers[cursor + 2], y: origin.y + numbers[cursor + 3])
                    let point = CGPoint(x: origin.x + numbers[cursor + 4], y: origin.y + numbers[cursor + 5])
                    path.addCurve(to: point, control1: control1, control2: control2)
                    current = point
                    cursor += 6
                }
            case "Q", "q":
                var cursor = 0
                while cursor + 3 < numbers.count {
                    let origin = base()
                    let control = CGPoint(x: origin.x + numbers[cursor], y: origin.y + numbers[cursor + 1])
                    let point = CGPoint(x: origin.x + numbers[cursor + 2], y: origin.y + numbers[cursor + 3])
                    path.addQuadCurve(to: point, control: control)
                    current = point
                    cursor += 4
                }
            case "A", "a":
                var cursor = 0
                while cursor + 6 < numbers.count {
                    let origin = base()
                    let end = CGPoint(
                        x: origin.x + numbers[cursor + 5],
                        y: origin.y + numbers[cursor + 6]
                    )
                    appendArc(
                        to: &path,
                        from: current,
                        to: end,
                        rx: numbers[cursor],
                        ry: numbers[cursor + 1],
                        xAxisRotationDegrees: numbers[cursor + 2],
                        largeArc: numbers[cursor + 3] != 0,
                        sweep: numbers[cursor + 4] != 0
                    )
                    current = end
                    cursor += 7
                }
            case "Z", "z":
                path.closeSubpath()
                current = subpathStart
            default:
                break
            }
            numbers.removeAll(keepingCapacity: true)
        }

        while index < d.endIndex {
            let char = d[index]
            if char.isLetter {
                flush()
                command = char
                index = d.index(after: index)
                if command == "Z" || command == "z" { flush() }
            } else if char == " " || char == "," || char == "\n" || char == "\t" {
                index = d.index(after: index)
            } else if let value = scanNumber() {
                numbers.append(value)
            } else {
                index = d.index(after: index)
            }
        }
        flush()
        return path
    }

    /// Converts an SVG elliptical-arc segment to cubic béziers.
    ///
    /// `Path` has no endpoint-parameterised arc, so this does the standard
    /// endpoint → centre conversion from the SVG spec's implementation notes
    /// and then approximates each ≤90° sweep with one cubic. Written against
    /// `addCurve` only, so it depends on nothing beyond the core Path API.
    private static func appendArc(
        to path: inout Path,
        from start: CGPoint,
        to end: CGPoint,
        rx rxIn: CGFloat,
        ry ryIn: CGFloat,
        xAxisRotationDegrees: CGFloat,
        largeArc: Bool,
        sweep: Bool
    ) {
        // Degenerate radii mean a straight line, per the spec.
        var rx = abs(rxIn)
        var ry = abs(ryIn)
        guard rx > .ulpOfOne, ry > .ulpOfOne else {
            path.addLine(to: end)
            return
        }
        if start == end { return }

        let phi = xAxisRotationDegrees * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)

        let dx2 = (start.x - end.x) / 2
        let dy2 = (start.y - end.y) / 2
        let x1p = cosPhi * dx2 + sinPhi * dy2
        let y1p = -sinPhi * dx2 + cosPhi * dy2

        // Scale the radii up if they are too small to span the endpoints.
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let scale = sqrt(lambda)
            rx *= scale
            ry *= scale
        }

        let sign: CGFloat = (largeArc == sweep) ? -1 : 1
        let numerator = max(0, rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p)
        let denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let coefficient = denominator > .ulpOfOne ? sign * sqrt(numerator / denominator) : 0

        let cxp = coefficient * rx * y1p / ry
        let cyp = -coefficient * ry * x1p / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
            guard len > .ulpOfOne else { return 0 }
            let value = min(1, max(-1, dot / len))
            return (ux * vy - uy * vx < 0 ? -1 : 1) * acos(value)
        }

        let ux = (x1p - cxp) / rx, uy = (y1p - cyp) / ry
        let vx = (-x1p - cxp) / rx, vy = (-y1p - cyp) / ry
        let theta1 = angle(1, 0, ux, uy)
        var delta = angle(ux, uy, vx, vy)
        if !sweep, delta > 0 { delta -= 2 * .pi }
        if sweep, delta < 0 { delta += 2 * .pi }

        // One cubic per quarter turn keeps the error below a tenth of a point
        // at the sizes these shapes are drawn.
        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(segments)
        let alpha = 4.0 / 3.0 * tan(step / 4)

        var theta = theta1
        for _ in 0..<segments {
            let cosT1 = cos(theta), sinT1 = sin(theta)
            let theta2 = theta + step
            let cosT2 = cos(theta2), sinT2 = sin(theta2)

            func point(_ cosT: CGFloat, _ sinT: CGFloat) -> CGPoint {
                CGPoint(
                    x: cx + rx * cosPhi * cosT - ry * sinPhi * sinT,
                    y: cy + rx * sinPhi * cosT + ry * cosPhi * sinT
                )
            }
            func derivative(_ cosT: CGFloat, _ sinT: CGFloat) -> CGVector {
                CGVector(
                    dx: -rx * cosPhi * sinT - ry * sinPhi * cosT,
                    dy: -rx * sinPhi * sinT + ry * cosPhi * cosT
                )
            }

            let p1 = point(cosT1, sinT1)
            let p2 = point(cosT2, sinT2)
            let d1 = derivative(cosT1, sinT1)
            let d2 = derivative(cosT2, sinT2)

            path.addCurve(
                to: p2,
                control1: CGPoint(x: p1.x + alpha * d1.dx, y: p1.y + alpha * d1.dy),
                control2: CGPoint(x: p2.x - alpha * d2.dx, y: p2.y - alpha * d2.dy)
            )
            theta = theta2
        }
    }
}

/// A `Shape` that draws SVG path data scaled into its frame.
struct V7VectorShape: Shape {
    var d: String
    var viewBox: CGRect

    init(_ d: String, viewBox: CGRect) {
        self.d = d
        self.viewBox = viewBox
    }

    func path(in rect: CGRect) -> Path {
        V7VectorPath.path(d, viewBox: viewBox, in: rect)
    }
}

// MARK: - The torn edge

/// Roughens a path so its edge reads as a tear rather than a bezier.
///
/// The board's edge is `feTurbulence` + `feDisplacementMap`, which has no
/// SwiftUI equivalent — and the design system's own verdict is that the true
/// fibrous, semi-transparent edge is a *material* that needs matted raster
/// plates (see `design/v7-bundle`, boards 3c and 4a). This is the documented
/// dev stand-in: it displaces the flattened outline by seeded noise, so the
/// silhouette stops reading as crisp vector.
///
/// The seed is fixed per layer. That is load-bearing — a re-rolled seed would
/// make the edge boil between frames, which the brief calls out explicitly as
/// the failure mode to avoid. The paper is a physical object; it holds still.
struct V7TornEdge: Shape {
    var d: String
    var viewBox: CGRect
    /// Displacement amplitude in viewBox units.
    var amplitude: CGFloat = 1.6
    /// Fixed per layer: the coarse tan core and the fine mass use different
    /// seeds so their tears do not line up.
    var seed: UInt64 = 7
    /// How many outline samples share one noise target. Higher values give a
    /// coarser, more paper-like tear; 1 would give per-point static.
    var coherence: Int = 4

    func path(in rect: CGRect) -> Path {
        let source = V7VectorPath.path(d, viewBox: viewBox, in: rect)
        guard viewBox.width > 0, viewBox.height > 0 else { return source }

        let scale = min(rect.width / viewBox.width, rect.height / viewBox.height)
        let amp = amplitude * scale
        // Below roughly a third of a point the tear is invisible and the
        // extra geometry is wasted — the pill draws at 28x32 and wants the
        // clean silhouette anyway.
        guard amp > 0.3 else { return source }

        var state = seed &* 2_654_435_761 &+ 1
        func random() -> CGVector {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let x = CGFloat(Double((state >> 33) & 0xFFFF) / 65535.0) * 2 - 1
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let y = CGFloat(Double((state >> 33) & 0xFFFF) / 65535.0) * 2 - 1
            return CGVector(dx: x, dy: y)
        }

        // Lerp toward a fresh target every `coherence` samples. Independent
        // per-point noise reads as static; a slowly varying offset reads as
        // torn fibre.
        var from = random()
        var to = random()
        var tick = 0
        func nextOffset() -> CGVector {
            let t = CGFloat(tick % coherence) / CGFloat(coherence)
            tick += 1
            if tick % coherence == 0 {
                from = to
                to = random()
            }
            return CGVector(
                dx: (from.dx + (to.dx - from.dx) * t) * amp,
                dy: (from.dy + (to.dy - from.dy) * t) * amp
            )
        }

        var result = Path()
        var opened = false
        source
            .flattened(flatness: 1.2)
            .forEach { element in
                switch element {
                case .move(let point):
                    let offset = nextOffset()
                    result.move(to: CGPoint(x: point.x + offset.dx, y: point.y + offset.dy))
                    opened = true
                case .line(let point):
                    let offset = nextOffset()
                    result.addLine(to: CGPoint(x: point.x + offset.dx, y: point.y + offset.dy))
                case .closeSubpath:
                    result.closeSubpath()
                default:
                    break
                }
            }
        return opened ? result : source
    }
}
