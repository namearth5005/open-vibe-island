import SwiftUI

/// The four tabs, ranked by urgency rather than launch order.
///
/// Board 5a's structure: the inbox was only ever a filter of the session list,
/// so it folds back in and the freed corner goes to Usage.
enum V7Tab: String, CaseIterable, Identifiable, Sendable {
    case sessions
    case usage
    case pet
    case rules

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sessions: "Sessions"
        case .usage:    "Usage"
        case .pet:      "Pet"
        case .rules:    "Rules"
        }
    }

    /// Which corner this label lives in. There is no tab bar — navigation is
    /// four hand-lettered words in the four corners, per `screen-home.jpg`.
    var corner: Alignment {
        switch self {
        case .sessions: .topLeading
        case .usage:    .topTrailing
        case .pet:      .bottomLeading
        case .rules:    .bottomTrailing
        }
    }
}

/// A single hand-lettered corner label, with the crayon ellipse when active
/// and an optional urgency badge.
struct V7CornerTabLabel: View {
    var tab: V7Tab
    var isActive: Bool
    /// Count of things needing a human. Rendered as count **and** glyph, so
    /// urgency never rides on colour alone.
    var attentionCount: Int = 0
    /// Set on the Pet tab, where the label sits over the lit wall rather than
    /// over ink and needs to hold its own against it.
    var overArt: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(tab.title)
                    .font(V7Tokens.Typeface.hand(size: 15))
                    .foregroundStyle(labelColor)
                    .v7Scribbled(V7Tokens.Accent.scribble, active: isActive)

                if attentionCount > 0 {
                    HStack(spacing: 2) {
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
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(V7Tokens.Status.needsDecision)
                    }
                }
            }
            .shadow(color: .black.opacity(overArt ? 0.20 : 0), radius: 0, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            attentionCount > 0
                ? Text("\(tab.title), \(attentionCount) need you")
                : Text(tab.title)
        )
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }

    private var labelColor: Color {
        if isActive { return V7Tokens.Text.primary }
        return overArt ? V7Tokens.Ground.paper : V7Tokens.Text.secondary
    }
}

/// Lays the four corner labels over a tab's content.
///
/// Content is inset 46pt from the left and right edges — the notch shape masks
/// 22pt each side plus 24pt of breathing room — and clears the header and
/// footer bands the labels occupy. That geometry is fixed.
struct V7PanelChrome<Content: View>: View {
    @Binding var selection: V7Tab
    var attentionCount: Int
    /// True on the Pet tab, where the room runs edge to edge behind the labels.
    var labelsOverArt: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            content()
                .padding(.horizontal, V7Tokens.Rhythm.sideInset)
                .padding(.top, V7Tokens.Panel.headerHeight)
                .padding(.bottom, V7Tokens.Panel.footerHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            ForEach(V7Tab.allCases) { tab in
                V7CornerTabLabel(
                    tab: tab,
                    isActive: selection == tab,
                    attentionCount: tab == .sessions ? attentionCount : 0,
                    overArt: labelsOverArt
                ) {
                    selection = tab
                }
                .padding(.horizontal, V7Tokens.Rhythm.sideInset)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: tab.corner)
            }
        }
    }
}

// MARK: - Shared headline

/// The one-line answer to "what is going on", plus its meta line.
///
/// The default view must be readable in under two seconds, and this is the
/// line that does it. Active voice, sentence case, no apology.
struct V7Headline: View {
    var title: String
    var meta: String
    /// An optional prominent action — at most one per screen.
    var action: (title: String, run: () -> Void)?

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: V7Tokens.Rhythm.titleToMeta) {
                Text(title)
                    .font(V7Tokens.Typeface.hand(size: 19))
                    .foregroundStyle(V7Tokens.Text.primary)
                    .lineLimit(1)
                Text(meta)
                    .font(V7Tokens.Typeface.mono(size: 9.5))
                    .foregroundStyle(V7Tokens.Text.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let action {
                Button(action.title, action: action.run)
                    .buttonStyle(V7ScribbleButtonStyle())
                    .fixedSize()
            }
        }
    }
}
