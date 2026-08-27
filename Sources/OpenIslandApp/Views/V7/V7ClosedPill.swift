import SwiftUI
import OpenIslandCore

/// **The collapsed pill** — board 08. Roughly 180 × 32pt in the notch, of
/// which the companion occupies about 28 × 32.
///
/// Light body, always. A dark silhouette is invisible on near-black, and the
/// reference's black cat only works because it sits on a pink sofa — the pill
/// has no room for furniture.
///
/// The pill earns silence. With nothing running it shows no count and no glow;
/// it only speaks when the fleet has something to say, and even then it asks
/// rather than interrupts. Escalations never auto-expand the panel.
struct V7ClosedPill: View {
    var mood: V7CompanionMood
    var label: String
    /// Rendered as a count *and* a glyph. Never colour alone.
    var attentionCount: Int
    /// The quiet status shape shown when nothing needs a human.
    var trailingGlyph: (glyph: V7StatusGlyph, color: Color)?
    var width: CGFloat = 180
    var height: CGFloat = 32

    var body: some View {
        HStack(spacing: 7) {
            V7CompanionPillPlate(mood: mood, width: 26, height: height - 6)

            Text(label)
                .font(V7Tokens.Typeface.mono(size: 10, weight: attentionCount > 0 ? .bold : .regular))
                .foregroundStyle(
                    attentionCount > 0 ? V7Tokens.Text.primary : V7Tokens.Text.secondary
                )
                .lineLimit(1)

            Spacer(minLength: 0)

            if attentionCount > 0 {
                HStack(spacing: 3) {
                    V7StatusGlyphView(
                        glyph: .asterisk,
                        color: V7Tokens.Text.onCard,
                        size: 7,
                        lineWidth: 2
                    )
                    Text("\(attentionCount)")
                        .font(V7Tokens.Typeface.mono(size: 9, weight: .bold))
                        .foregroundStyle(V7Tokens.Text.onCard)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 1.5)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(V7Tokens.Status.needsDecision)
                }
            } else if let trailing = trailingGlyph {
                V7StatusGlyphView(
                    glyph: trailing.glyph,
                    color: trailing.color,
                    size: 10,
                    lineWidth: 2
                )
            }
        }
        .padding(.leading, 7)
        .padding(.trailing, attentionCount > 0 ? 10 : 12)
        .frame(width: width, height: height)
        .background {
            V6ClosedPillShape(cornerRadius: height / 2)
                .fill(V7Tokens.Ground.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Open Island"))
        .accessibilityValue(
            attentionCount > 0
                ? Text("\(attentionCount) need you")
                : Text(label)
        )
    }

    /// The pill's whole state, derived from the fleet. Every mood here is
    /// caused by the sessions; none of it is a timer or a mascot's whim.
    static func state(
        for sessions: [AgentSession],
        shippedRecently: Bool = false
    ) -> (mood: V7CompanionMood, label: String, attention: Int, glyph: (V7StatusGlyph, Color)?) {
        let attention = sessions.filter(\.phase.requiresAttention).count
        let working = sessions.filter { $0.phase == .running }.count
        let mood = V7CompanionMood.forFleet(sessions: sessions, shippedRecently: shippedRecently)

        if attention > 0 {
            return (mood, "\(attention) need you", attention, nil)
        }
        if shippedRecently {
            return (mood, "shipped", 0, (.check, V7Tokens.Status.done))
        }
        if working > 0 {
            return (mood, "\(working) working", 0, (.arc, V7Tokens.Status.working))
        }
        if sessions.isEmpty {
            // No count, no glow. Silence is a legitimate state.
            return (.asleep, "all quiet", 0, nil)
        }
        return (mood, "idle", 0, (.dash, V7Tokens.Status.idle))
    }
}
