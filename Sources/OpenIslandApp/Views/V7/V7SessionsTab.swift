import SwiftUI
import OpenIslandCore

/// **Sessions** — board 5a.
///
/// The inbox folds back in. It was only ever a filter of this same list, so a
/// decision does not deserve its own tab: the card sits in rank position with
/// Allow / Deny / Look and the rule row right there, and the freed corner goes
/// to Usage.
///
/// Two rules shape the layout:
///
/// - **Never require scrolling to reach something that needs the user.**
///   Attention sits at the top; idle collapses to a count and never becomes
///   a row.
/// - **Plain cards.** This is functional UI, so it stays light and
///   unremarkable. The single seat behind the top decision is the only piece
///   of collage on the surface, and it is there because it is the contrast
///   device, not decoration.
struct V7SessionsTab: View {
    var model: AppModel
    var sessions: [AgentSession]
    var referenceDate: Date
    /// The concierge's running tally. Absent until the app records one — the
    /// footer hides rather than showing a zero it cannot stand behind.
    var stats: V7ConciergeStats

    var body: some View {
        let summary = V7FleetSummary(sessions: sessions, referenceDate: referenceDate)

        if summary.needsYou == 0 && summary.total == 0 {
            V7SessionsEmptyState(stats: stats)
        } else {
            populated(summary: summary)
        }
    }

    @ViewBuilder
    private func populated(summary: V7FleetSummary) -> some View {
        let ranked = rankedSessions
        let attention = ranked.filter(\.phase.requiresAttention)
        let working = ranked.filter { $0.phase == .running }

        VStack(alignment: .leading, spacing: 6) {
            V7Headline(
                title: summary.headline,
                meta: summary.total > 0
                    ? "\(summary.breakdown) · decisions land in place, not in a second tab"
                    : summary.breakdown,
                action: attention.first.map { session in
                    V7HeadlineAction(title: "Jump to most urgent") {
                        model.jumpToSession(session)
                    }
                }
            )

            if let lead = attention.first {
                // The one seat on the surface. Whatever most needs a human
                // gets the saturated block and the clashing contour behind it.
                V7DecisionSeat(model: model, session: lead)
                    .padding(.top, 2)
            }

            // Any further decisions stay as plain cards — a second seat would
            // make neither of them read as the urgent one.
            ForEach(attention.dropFirst()) { session in
                V7AttentionCard(model: model, session: session)
            }

            ForEach(working) { session in
                V7WorkingRow(session: session) {
                    model.jumpToSession(session)
                }
            }

            if let collapsed = summary.collapsedLabel {
                V7CollapsedRow(label: collapsed)
            }

            Spacer(minLength: 0)

            if let handled = stats.handledThisWeekLabel {
                HStack(spacing: 8) {
                    V7StatusGlyphView(glyph: .check, color: V7Tokens.Status.done, size: 10, lineWidth: 2)
                    Text(handled)
                        .font(V7Tokens.Typeface.mono(size: 9.5))
                        .foregroundStyle(V7Tokens.Text.tertiary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// Urgency first, then most recently active. Launch order never wins.
    private var rankedSessions: [AgentSession] {
        sessions
            .filter { !$0.v7IsIdle(at: referenceDate) }
            .sorted { lhs, rhs in
                if lhs.v7UrgencyRank != rhs.v7UrgencyRank {
                    return lhs.v7UrgencyRank < rhs.v7UrgencyRank
                }
                return lhs.islandActivityDate > rhs.islandActivityDate
            }
    }
}

// MARK: - The decision seat

/// The top decision, on the rose seat, with everything needed to answer it
/// without leaving the list.
struct V7DecisionSeat: View {
    var model: AppModel
    var session: AgentSession

    /// Ticking this applies the agent's own suggested rule on allow. It starts
    /// unticked every time: a loosened leash should be a deliberate act.
    @State private var acceptsRule = false

    var body: some View {
        V7Seat(seat: .rose) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(session.v7Headline)
                        .font(V7Tokens.Typeface.ui(size: 14, weight: .semibold))
                        .foregroundStyle(V7Tokens.Text.onCard)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    V7StatusChip(
                        label: session.v7StatusLabel,
                        fill: V7Tokens.Status.tint(for: session.phase),
                        glyph: V7Tokens.Status.glyph(for: session.phase)
                    )
                }

                // The agent's own justification — what it wants and why it
                // claims it is fine.
                if let request = session.permissionRequest {
                    Text(request.summary.isEmpty ? request.title : request.summary)
                        .font(V7Tokens.Typeface.ui(size: 12))
                        .foregroundStyle(V7Tokens.Text.onSeat)
                        .lineLimit(3)
                        .padding(.top, 4)
                } else if let prompt = session.questionPrompt {
                    Text(prompt.title)
                        .font(V7Tokens.Typeface.ui(size: 12))
                        .foregroundStyle(V7Tokens.Text.onSeat)
                        .lineLimit(3)
                        .padding(.top, 4)
                }

                HStack(spacing: 6) {
                    V7AgentDot(color: V7Tokens.agentColor(for: session.tool))
                    Text(session.v7MetaWithReason)
                        .font(V7Tokens.Typeface.mono(size: 9))
                        .foregroundStyle(V7Tokens.Text.onCardMuted)
                        .lineLimit(1)
                }
                .padding(.top, V7Tokens.Rhythm.titleToMeta)

                if session.permissionRequest != nil {
                    permissionActions
                } else if !session.v7AnswerChips.isEmpty {
                    answerChips
                }

                if let rule = session.v7SuggestedRuleLabel {
                    ruleRow(label: rule)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.96))
            }
        }
    }

    /// Buttons say what happens. No "OK", no "Confirm".
    private var permissionActions: some View {
        HStack(spacing: 7) {
            Button("Allow") {
                let updates = session.v7SuggestedRuleUpdates
                model.approvePermission(
                    for: session.id,
                    action: acceptsRule && !updates.isEmpty ? .allowWithUpdates(updates) : .allowOnce
                )
            }
            .buttonStyle(V7SolidButtonStyle())

            Button("Deny") {
                model.approvePermission(for: session.id, action: .deny)
            }
            .buttonStyle(V7OutlineButtonStyle())

            Button("Look") {
                model.jumpToSession(session)
            }
            .buttonStyle(V7OutlineButtonStyle())

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    /// One-tap answers, so a question costs the same as a permission.
    private var answerChips: some View {
        HStack(spacing: 6) {
            ForEach(session.v7AnswerChips.prefix(3), id: \.self) { option in
                Button(option) {
                    model.answerQuestion(for: session.id, answer: .init(answer: option))
                }
                .buttonStyle(V7AnswerChipStyle())
            }
            Button("or reply in the session…") {
                model.jumpToSession(session)
            }
            .buttonStyle(.plain)
            .font(V7Tokens.Typeface.ui(size: 11.5))
            .foregroundStyle(V7Tokens.Text.onCardMuted)

            Spacer(minLength: 0)
        }
        .padding(.top, 7)
    }

    private func ruleRow(label: String) -> some View {
        Button {
            acceptsRule.toggle()
        } label: {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(V7Tokens.Text.onCard.opacity(0.4), lineWidth: 1.5)
                    .background {
                        if acceptsRule {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(V7Tokens.Ground.ink)
                        }
                    }
                    .frame(width: 12, height: 12)
                    .overlay {
                        if acceptsRule {
                            V7StatusGlyphView(
                                glyph: .check,
                                color: V7Tokens.Ground.paper,
                                size: 8,
                                lineWidth: 2
                            )
                        }
                    }

                Text(label)
                    .font(V7Tokens.Typeface.ui(size: 11.5))
                    .foregroundStyle(V7Tokens.Text.onCard.opacity(0.75))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text("its suggestion")
                    .font(V7Tokens.Typeface.mono(size: 8.5))
                    .foregroundStyle(V7Tokens.Text.onCardMuted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(V7Tokens.Text.onCard.opacity(0.1))
                .frame(height: 1)
        }
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(acceptsRule ? "on" : "off"))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Secondary attention card

/// A further decision or question — plain card, so the seat above stays the
/// one urgent thing on the surface.
struct V7AttentionCard: View {
    var model: AppModel
    var session: AgentSession

    var body: some View {
        V7Card {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(session.v7Headline)
                        .font(V7Tokens.Typeface.ui(size: 13, weight: .semibold))
                        .foregroundStyle(V7Tokens.Text.onCard)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    V7StatusChip(
                        label: session.v7StatusLabel,
                        fill: V7Tokens.Status.tint(for: session.phase),
                        glyph: V7Tokens.Status.glyph(for: session.phase)
                    )
                }

                Text(session.v7MetaWithReason)
                    .font(V7Tokens.Typeface.mono(size: 9))
                    .foregroundStyle(V7Tokens.Text.onCardMuted)
                    .lineLimit(1)
                    .padding(.top, 2)

                HStack(spacing: 6) {
                    if session.permissionRequest != nil {
                        Button("Allow") {
                            model.approvePermission(for: session.id, action: .allowOnce)
                        }
                        .buttonStyle(V7SolidButtonStyle())
                        Button("Deny") {
                            model.approvePermission(for: session.id, action: .deny)
                        }
                        .buttonStyle(V7OutlineButtonStyle())
                    } else {
                        ForEach(session.v7AnswerChips.prefix(2), id: \.self) { option in
                            Button(option) {
                                model.answerQuestion(for: session.id, answer: .init(answer: option))
                            }
                            .buttonStyle(V7AnswerChipStyle())
                        }
                    }

                    Button("Look") {
                        model.jumpToSession(session)
                    }
                    .buttonStyle(V7OutlineButtonStyle())

                    Spacer(minLength: 0)
                }
                .padding(.top, 7)
            }
        }
    }
}

// MARK: - Quiet rows

/// A running session. Just a row — nothing here needs a human, so nothing
/// here competes for attention.
struct V7WorkingRow: View {
    var session: AgentSession
    var jump: () -> Void

    var body: some View {
        Button(action: jump) {
            HStack(spacing: 8) {
                Text(session.v7Headline)
                    .font(V7Tokens.Typeface.ui(size: 12.5))
                    .foregroundStyle(V7Tokens.Text.onCard)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                Text(session.v7Meta)
                    .font(V7Tokens.Typeface.mono(size: 9))
                    .foregroundStyle(V7Tokens.Text.onCardMuted)
                    .lineLimit(1)
                    .layoutPriority(-1)

                V7StatusGlyphView(
                    glyph: V7Tokens.Status.glyph(for: session.phase),
                    color: V7Tokens.Status.tint(for: session.phase),
                    size: 10,
                    lineWidth: 2.2
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: V7Tokens.Radius.row, style: .continuous)
                    .fill(Color.white.opacity(0.96))
            }
            .shadow(color: .black.opacity(0.28), radius: 4, y: 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Done and idle, collapsed to a count. Idle sessions never become rows —
/// that is what keeps anything needing the user above the fold.
struct V7CollapsedRow: View {
    var label: String

    var body: some View {
        HStack(spacing: 8) {
            V7StatusGlyphView(glyph: .dash, color: V7Tokens.Status.idle, size: 10, lineWidth: 2)
            Text(label)
                .font(V7Tokens.Typeface.mono(size: 9.5))
                .foregroundStyle(V7Tokens.Text.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: V7Tokens.Radius.row, style: .continuous)
                .fill(V7Tokens.Text.primary.opacity(0.07))
        }
    }
}

// MARK: - Empty state

/// Boards 06 and 07. Emptiness as direction, not mood.
///
/// No filler cards and no prompt to start more work — the panel simply has
/// less to say, and says it. The companion is asleep because nothing is
/// running, which is the truth rather than a mascot asking to be noticed.
struct V7SessionsEmptyState: View {
    var stats: V7ConciergeStats

    var body: some View {
        VStack(spacing: 11) {
            Spacer(minLength: 0)

            // Light body: there is no seat out here, and a dark silhouette
            // would vanish against the ink.
            V7CompanionView(mood: .asleep, bodyTreatment: .light)
                .frame(width: 84, height: 53)

            Text("Nothing needs you. Go build something.")
                .font(V7Tokens.Typeface.hand(size: 19))
                .foregroundStyle(V7Tokens.Text.primary)
                .multilineTextAlignment(.center)

            if let handled = stats.handledThisWeekLabel {
                Text(handled)
                    .font(V7Tokens.Typeface.mono(size: 9.5))
                    .foregroundStyle(V7Tokens.Text.tertiary)
            } else {
                Text("sessions appear as your terminals start agents")
                    .font(V7Tokens.Typeface.mono(size: 9.5))
                    .foregroundStyle(V7Tokens.Text.tertiary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Concierge stats

/// What the concierge has handled on the user's behalf.
///
/// This is the tab's paid value made visible daily, and the board puts a
/// running counter on it — *"214 interruptions handled this week."* The app
/// does not record that yet: nothing currently persists auto-approvals or
/// resolved prompts, so there is no honest number to show.
///
/// Until a store exists, this stays empty and every surface that reads it
/// hides rather than rendering a zero or a placeholder. A fabricated counter
/// would undermine exactly the trust the tab is meant to earn.
struct V7ConciergeStats: Equatable {
    var handledThisWeek: Int?
    var escalatedThisWeek: Int?
    var entries: [Entry] = []

    struct Entry: Equatable, Identifiable {
        var id = UUID()
        /// Reads like *"Approved 12 file reads in reelle-ios. Nothing looked
        /// unusual."* — who, what, and why it claims it is fine.
        var text: String
        var age: String
    }

    static let empty = V7ConciergeStats()

    var handledThisWeekLabel: String? {
        guard let handled = handledThisWeek, handled > 0 else { return nil }
        return "\(handled) handled this week without asking — the log lives here"
    }
}
