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
/// `C/c`, `Q/q`, `Z/z`. Anything else is ignored rather than trapped, so a
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
