import SwiftUI
import AppKit

/// Collage primitives for the v7 art direction: paper grain, the signature
/// seat, the crayon scribble, and torn paper.
///
/// Everything in this file is *art*. None of it may appear inside a
/// functional list — grain rides art fills only, and hand-lettering never
/// enters a session row. See ``V7Tokens`` for the rule in full.

// MARK: - Paper grain

/// A seed-locked grain tile.
///
/// The reference's grain is a physical property of the paper, so it must never
/// shimmer between frames. The tile is generated once from a fixed seed and
/// cached; every surface draws the same pixels forever.
///
/// MainActor-isolated so the cache needs no `nonisolated(unsafe)`: the only
/// readers are view bodies, which are already on the main actor.
@MainActor
enum V7Grain {
    private static let tileSize = 128

    /// Generated once, on first use, and retained for the process lifetime.
    static let tile: Image = {
        let side = tileSize
        var pixels = [UInt8](repeating: 0, count: side * side)

        // Deterministic LCG — a fixed seed is the whole point. Anything
        // drawing from a system RNG would re-roll the grain per launch.
        var state: UInt64 = 0x5DEECE66D
        func next() -> UInt8 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return UInt8((state >> 33) & 0xFF)
        }

        // Bias toward white so a multiply blend darkens only sparsely; the
        // grain should read as tooth in the paper, not as dirt.
        for index in 0..<pixels.count {
            let value = Int(next())
            pixels[index] = UInt8(min(255, 176 + value / 3))
        }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(
                  width: side,
                  height: side,
                  bitsPerComponent: 8,
                  bitsPerPixel: 8,
                  bytesPerRow: side,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: 0),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              )
        else {
            return Image(nsImage: NSImage(size: NSSize(width: side, height: side)))
        }

        return Image(
            nsImage: NSImage(cgImage: cgImage, size: NSSize(width: side, height: side))
        )
    }()
}

/// Multiplies the seed-locked grain over whatever it is applied to.
///
/// Only art fills get this. `0.38` is the board's value for room grounds and
/// seats; the recap slip and shelf cells use `0.35`.
struct V7GrainOverlay: ViewModifier {
    var opacity: Double = 0.38

    func body(content: Content) -> some View {
        content.overlay {
            V7Grain.tile
                .resizable(resizingMode: .tile)
                .opacity(opacity)
                .blendMode(.multiply)
                .allowsHitTesting(false)
        }
    }
}

extension View {
    /// Applies paper grain. Art surfaces only — never a session row.
    func v7Grain(_ opacity: Double = 0.38) -> some View {
        modifier(V7GrainOverlay(opacity: opacity))
    }
}

// MARK: - The seat

/// **The signature element.** A saturated block with a contour drawn in a
/// clashing hue, sitting behind anything that must be read.
///
/// The character never reads against the wall or the floor; this does that
/// work. Generalised from `room-pink-sofa.jpg`: anything urgent gets a seat.
struct V7Seat<Content: View>: View {
    var seat: V7Tokens.Seat
    var cornerRadius: CGFloat = V7Tokens.Radius.seat
    var padding: CGFloat = 6
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(seat.fill)
                    .v7Grain(0.40)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(seat.contour, lineWidth: V7Tokens.Rhythm.contourWidth)
            }
    }
}

// MARK: - The crayon scribble

/// The hand-drawn ellipse from `screen-home.jpg` — drawn *around* a word,
/// never a button chrome. Used for the active corner label and for the one
/// prominent action on a screen.
///
/// The path is the board's, normalised off its `0 0 120 46` viewBox so it
/// stretches with whatever it wraps.
struct V7Scribble: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width / 120
        let h = rect.height / 46
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }

        var path = Path()
        path.move(to: p(96, 9))
        path.addCurve(to: p(16, 12), control1: p(74, 2), control2: p(36, 3))
        path.addCurve(to: p(18, 37), control1: p(2, 18), control2: p(3, 31))
        path.addCurve(to: p(103, 36), control1: p(40, 45), control2: p(84, 44))
        path.addCurve(to: p(99, 12), control1: p(115, 31), control2: p(114, 18))
        path.addCurve(to: p(78, 8), control1: p(92, 9), control2: p(84, 8))
        return path
    }
}

extension View {
    /// Draws the crayon ellipse around this view. The overhang matches the
    /// board: 13pt horizontally, 7pt vertically, outside the text box.
    func v7Scribbled(_ color: Color, lineWidth: CGFloat = 2.2, active: Bool = true) -> some View {
        background {
            if active {
                V7Scribble()
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .padding(.horizontal, -13)
                    .padding(.vertical, -7)
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Torn paper

/// A paper slip with torn top and bottom edges, per `screen-receipt.jpg`.
///
/// The tear is a fixed zig-zag rather than a random one — the same reason the
/// grain is seed-locked. Paper does not have soft corners, so the sides stay
/// square and the radius token for paper is 3.
struct V7TornPaper: Shape {
    /// How deep the tear bites into the slip, in points.
    var bite: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        // Alternating offsets, sampled from the board's clip-path.
        let ripple: [CGFloat] = [0.62, 0.24, 0.74, 0.16, 0.66, 0.28, 0.70, 0.20, 0.62,
                                 0.24, 0.74, 0.20, 0.66, 0.32, 0.70, 0.20, 0.62, 0.28, 0.58]
        let steps = ripple.count - 1
        let dx = rect.width / CGFloat(steps)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + ripple[0] * bite))
        for index in 1...steps {
            path.addLine(to: CGPoint(
                x: rect.minX + dx * CGFloat(index),
                y: rect.minY + ripple[index] * bite
            ))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - ripple[steps] * bite))
        for index in stride(from: steps - 1, through: 0, by: -1) {
            path.addLine(to: CGPoint(
                x: rect.minX + dx * CGFloat(index),
                y: rect.maxY - ripple[index] * bite
            ))
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Plain surfaces
//
// Everything below is deliberately unremarkable. `screen-tasklist.jpg` is the
// governing reference: plain white rounded cards, ordinary rows, no grain, no
// hand-lettering. Charm and speed never share a surface.

/// The plain card that carries functional content.
struct V7Card<Content: View>: View {
    var cornerRadius: CGFloat = V7Tokens.Radius.card
    var horizontalPadding: CGFloat = 12
    var verticalPadding: CGFloat = 8
    /// Slightly knocked back for content that is done or collapsed.
    var recessed: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(recessed ? 0.90 : 0.96))
            }
            .shadow(color: Color.black.opacity(recessed ? 0 : 0.30), radius: 5, y: 4)
    }
}

/// A status chip: fill + glyph + label. Never the fill alone.
struct V7StatusChip: View {
    var label: String
    var fill: Color
    var glyph: V7StatusGlyph
    var foreground: Color = V7Tokens.Text.onCard

    var body: some View {
        HStack(spacing: 4) {
            V7StatusGlyphView(glyph: glyph, color: foreground, size: 9)
            Text(label)
                .font(V7Tokens.Typeface.mono(size: 9.5))
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background {
            RoundedRectangle(cornerRadius: V7Tokens.Radius.chip, style: .continuous)
                .fill(fill)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

/// The small agent dot that precedes a meta line.
struct V7AgentDot: View {
    var color: Color
    var size: CGFloat = 6

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A pill-shaped outline button — `Deny`, `Look`, `Keep holding`.
struct V7OutlineButtonStyle: ButtonStyle {
    var tint: Color = V7Tokens.Text.onCard
    var borderOpacity: Double = 0.25

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(V7Tokens.Typeface.ui(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 2.5)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(tint.opacity(borderOpacity), lineWidth: 1.5)
            }
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// The one solid button on a decision card — `Allow`.
struct V7SolidButtonStyle: ButtonStyle {
    var fill: Color = V7Tokens.Ground.ink
    var tint: Color = V7Tokens.Ground.paper

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(V7Tokens.Typeface.ui(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 13)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(fill)
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// A hand-lettered action wrapped in the crayon ellipse — the screen's one
/// prominent verb, per `screen-home.jpg`'s "Start".
struct V7ScribbleButtonStyle: ButtonStyle {
    var tint: Color = V7Tokens.Text.primary
    var scribble: Color = V7Tokens.Accent.action

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(V7Tokens.Typeface.hand(size: 14.5))
            .foregroundStyle(tint)
            .padding(.horizontal, 15)
            .padding(.vertical, 5)
            .v7Scribbled(scribble, lineWidth: 2.3)
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

/// A one-tap answer chip for a structured question.
struct V7AnswerChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(V7Tokens.Typeface.mono(size: 10.5))
            .foregroundStyle(V7Tokens.Text.onCard)
            .padding(.horizontal, 11)
            .padding(.vertical, 2.5)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(V7Tokens.Text.onCard.opacity(0.25), lineWidth: 1.5)
            }
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// The plain toggle used on Rules and Usage. Deliberately ordinary.
struct V7Switch: View {
    var isOn: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isOn ? V7Tokens.Ground.ink : V7Tokens.Text.onCard.opacity(0.18))
            .frame(width: 32, height: 19)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(isOn ? V7Tokens.Ground.paper : .white)
                    .frame(width: 14, height: 14)
                    .padding(.horizontal, 2.5)
            }
            .accessibilityHidden(true)
    }
}
