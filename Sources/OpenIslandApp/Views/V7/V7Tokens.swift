import SwiftUI
import AppKit
import OpenIslandCore

/// v7 "Open Island" collage design system.
///
/// Ported verbatim from board `12 · tokens — one page` of the Claude Design
/// handoff in `design/v7-bundle/`. Two rules govern every surface here and
/// are the usual way this art direction gets built wrong:
///
/// 1. **The collage is content, not chrome.** Art — the companion, the room,
///    furniture, the recap slip — is torn paper and crayon. Functional UI —
///    session lists, rules, meters — is plain, light and unremarkable, sitting
///    on the textured ground. Charm and speed never share a surface.
/// 2. **The seat is the contrast device.** The companion never reads against
///    the wall or the floor. Anything that must be read gets a saturated block
///    behind it with a contour drawn in a *clashing* hue — see ``V7Seat``.
enum V7Tokens {

    // MARK: - Grounds

    enum Ground {
        /// Room wall in shadow.
        static let wall = Color(hex: 0x59703F)
        /// Room wall where the light lands; the Pet tab uses this one.
        static let wallLit = Color(hex: 0x6B8250)
        /// Room floor below the hard horizon.
        static let floor = Color(hex: 0x2A2B20)
        /// The rug under the sofa.
        static let rug = Color(hex: 0x7B5B8A)
        /// Paper stock for slips and shelf cells.
        static let paper = Color(hex: 0xF4ECD6)
        /// Panel ground. Every functional tab sits on this.
        static let ink = Color(hex: 0x17150F)
    }

    // MARK: - Text on ink (all clearing AA)

    enum Text {
        /// 13.9:1 on ink.
        static let primary = Color(hex: 0xECE5D5)
        /// 7.3:1 on ink.
        static let secondary = Color(hex: 0xA89E8C)
        /// 4.6:1 on ink.
        static let tertiary = Color(hex: 0x7C7466)
        /// Body copy inside a plain white card.
        static let onCard = Color(hex: 0x2C2318)
        /// Meta copy inside a plain white card.
        static let onCardMuted = Color(hex: 0x8B8067)
        /// Body copy on a saturated seat.
        static let onSeat = Color(hex: 0x4A2013)
        /// Headline copy on the clay (critical) seat.
        static let onClay = Color(hex: 0x2E1409)
    }

    // MARK: - Seats — a fill never ships without its clashing contour

    /// The signature element. A matched border reads as UI and breaks the
    /// reference, so fill and contour always travel together.
    struct Seat: Equatable {
        var fill: Color
        var contour: Color

        /// Needs your say.
        static let rose = Seat(fill: Color(hex: 0xE3A0A8), contour: Color(hex: 0xC4553F))
        /// A question is waiting.
        static let amber = Seat(fill: Color(hex: 0xDDB14A), contour: Color(hex: 0x3F6D8E))
        /// Resting.
        static let sage = Seat(fill: Color(hex: 0x6F7A54), contour: Color(hex: 0x47543A))
        /// Critical — the escalation seat.
        static let clay = Seat(fill: Color(hex: 0xE26D4F), contour: Color(hex: 0x7D3B1F))
    }

    // MARK: - Status — colour *and* shape, never colour alone

    enum Status {
        static let needsDecision = Color(hex: 0xF4A4A4)
        static let question = Color(hex: 0xFFD58A)
        static let working = Color(hex: 0x6EA7FF)
        static let done = Color(hex: 0x6FB982)
        static let idle = Color(hex: 0xB7B1A4)

        /// Ink-dark foreground used on top of a status chip's fill.
        static let onWorking = Color(hex: 0x0E1B2E)
        static let onDone = Color(hex: 0x0E2415)

        static func tint(for phase: SessionPhase) -> Color {
            switch phase {
            case .waitingForApproval: needsDecision
            case .waitingForAnswer:   question
            case .running:            working
            case .completed:          done
            }
        }

        /// The glyph that carries the same meaning as the colour, so urgency
        /// is never signalled by hue alone.
        static func glyph(for phase: SessionPhase) -> V7StatusGlyph {
            switch phase {
            case .waitingForApproval: .asterisk
            case .waitingForAnswer:   .question
            case .running:            .arc
            case .completed:          .check
            }
        }
    }

    // MARK: - Character marks

    enum Character {
        /// Body in the room, where a seat sits behind it.
        static let bodyDark = Color(hex: 0x221F1C)
        /// Body in the pill and on bare ink — a dark silhouette vanishes there.
        static let bodyLight = Color(hex: 0xF0EAD6)
        /// Alternate body, for the gray cat.
        static let bodyGray = Color(hex: 0x6E6A60)
        /// The warm tan backing paper showing through the tear.
        static let core = Color(hex: 0xB3956A)
        /// Crayon marks on a dark body.
        static let markOnDark = Color(hex: 0xC9CC4E)
        /// Crayon marks on a light body. A value + saturation jump from the
        /// body, *not* a hue clash: #F0EAD6 → #97923F.
        static let markOnLight = Color(hex: 0x97923F)
    }

    // MARK: - Accents

    enum Accent {
        /// The chartreuse crayon underline on the active corner label.
        static let scribble = Color(hex: 0xC9CC4E)
        /// The orange scribble around a primary call to action.
        static let action = Color(hex: 0xE26D4F)
        /// Ink used for a scribble drawn on a saturated seat.
        static let scribbleOnSeat = Color(hex: 0x17150F)
        /// Gains on the recap slip.
        static let gain = Color(hex: 0x3D7A45)
        /// Losses on the recap slip, and locked-rule copy.
        static let loss = Color(hex: 0xB04A34)
        /// A hand-drawn link.
        static let link = Color(hex: 0x3F6D8E)
    }

    // MARK: - Agents

    /// The per-agent dot colour. `AgentTool.brandColorHex` is already the
    /// authority here — it was hard-coded from the v6 handoff and the v7
    /// board uses the same hexes — so this just parses it rather than
    /// keeping a second copy that could drift.
    static func agentColor(for tool: AgentTool) -> Color {
        Color(hexString: tool.brandColorHex) ?? Text.secondary
    }

    // MARK: - Rhythm

    enum Rhythm {
        /// The notch masks 22pt each side, plus 24pt of breathing room.
        /// Content never crosses this inset.
        static let sideInset: CGFloat = 46
        static let rowPadding: CGFloat = 11
        /// Between a title and its meta line.
        static let titleToMeta: CGFloat = 3
        /// Between stacked cards.
        static let stack: CGFloat = 8
        static let contourWidth: CGFloat = 2.5
    }

    enum Radius {
        /// Seats.
        static let seat: CGFloat = 13
        /// Plain cards.
        static let card: CGFloat = 12
        /// Rows inside a card.
        static let row: CGFloat = 11
        /// Paper does not have soft corners.
        static let paper: CGFloat = 3
        /// Status chips and small controls.
        static let chip: CGFloat = 7
    }

    enum Panel {
        /// The geometry is fixed: 560 × 560pt maximum, and the default view
        /// must be readable in under two seconds.
        static let maxWidth: CGFloat = 560
        static let maxHeight: CGFloat = 560
        /// Reserved for the corner labels at the top of the panel.
        static let headerHeight: CGFloat = 46
        /// Reserved for the corner labels at the bottom.
        static let footerHeight: CGFloat = 40
    }

    // MARK: - Type — three faces, and only three

    enum Typeface {
        /// Hand display and numerals. Falls back to a rounded system face
        /// until the licensed textured hand is bundled; `Caveat` and
        /// `Patrick Hand` were the board's explicit stand-ins.
        static func hand(size: CGFloat, weight: Font.Weight = .regular) -> Font {
            if let custom = NSFont(name: "Patrick Hand", size: size) {
                return Font(custom as CTFont).weight(weight)
            }
            return .system(size: size, weight: weight, design: .rounded)
        }

        /// Hand numerals, for counts and totals.
        static func handNumeral(size: CGFloat) -> Font {
            if let custom = NSFont(name: "Caveat", size: size) {
                return Font(custom as CTFont).weight(.bold)
            }
            return .system(size: size, weight: .bold, design: .rounded)
        }

        /// Running UI copy — a clean sans.
        static func ui(size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight)
        }

        /// Strictly for data that lines up: commands, paths, elapsed times,
        /// diffs. Never for prose.
        static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
    }
}

// MARK: - Status glyphs

/// The shape half of "colour **and** shape". Each case draws the same mark the
/// board uses, sized to a 12×12 box and scaled to fit.
enum V7StatusGlyph {
    case asterisk
    case question
    case arc
    case check
    case dash

    /// Stroked, not filled — every glyph is a single crayon stroke.
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 12
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * s, y: rect.minY + y * s)
        }

        var path = Path()
        switch self {
        case .asterisk:
            path.move(to: p(6, 1.5));   path.addLine(to: p(6, 10.5))
            path.move(to: p(2, 3.8));   path.addLine(to: p(10, 8.2))
            path.move(to: p(10, 3.8));  path.addLine(to: p(2, 8.2))
        case .question:
            path.move(to: p(3.6, 4.2))
            path.addCurve(to: p(6.1, 1.3), control1: p(3.6, 2.2), control2: p(5.1, 1.3))
            path.addCurve(to: p(8.7, 3.7), control1: p(7.7, 1.3), control2: p(8.7, 2.3))
            path.addCurve(to: p(6.1, 7.3), control1: p(8.7, 5.2), control2: p(6.1, 5.5))
            path.move(to: p(6.1, 10.4));  path.addLine(to: p(6.1, 10.6))
        case .arc:
            path.move(to: p(10.5, 6))
            path.addArc(
                center: p(6, 6),
                radius: 4.5 * s,
                startAngle: .degrees(0),
                endAngle: .degrees(-90),
                clockwise: true
            )
        case .check:
            path.move(to: p(2, 6.6))
            path.addLine(to: p(4.9, 9.4))
            path.addLine(to: p(10, 2.8))
        case .dash:
            path.move(to: p(2.6, 6));   path.addLine(to: p(9.4, 6))
        }
        return path
    }
}

/// Renders a ``V7StatusGlyph`` at a given size and stroke colour.
struct V7StatusGlyphView: View {
    var glyph: V7StatusGlyph
    var color: Color
    var size: CGFloat = 9
    var lineWidth: CGFloat = 1.8

    var body: some View {
        Canvas { context, canvasSize in
            let path = glyph.path(in: CGRect(origin: .zero, size: canvasSize))
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Color helpers

extension Color {
    /// `Color(hex: 0xE3A0A8)` — keeps the board's hexes readable in source.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// Parses `"#d97742"` / `"d97742"`. Returns nil for anything else so the
    /// caller can fall back rather than silently rendering black.
    init?(hexString: String) {
        var trimmed = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") { trimmed.removeFirst() }
        guard trimmed.count == 6, let value = UInt32(trimmed, radix: 16) else { return nil }
        self.init(hex: value)
    }
}
