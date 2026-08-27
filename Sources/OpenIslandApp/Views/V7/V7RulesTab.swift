import SwiftUI
import OpenIslandCore

/// **Rules** — board 04. The boring tab, done plainly.
///
/// This is where trust in the automation is won, so it gets no charm at all:
/// plain cards, ordinary rows, ordinary toggles. Trust per repo is drawn as
/// **leash length** — a loose leash auto-approves almost everything, a tight
/// one escalates everything — because a number would invite tuning and a
/// drawing invites understanding.
struct V7RulesTab: View {
    var rules: V7RulesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                V7CompanionView(mood: .asleep, bodyTreatment: .light, animated: false)
                    .frame(width: 40, height: 25)
                VStack(alignment: .leading, spacing: V7Tokens.Rhythm.titleToMeta) {
                    Text("Loose leash, fewer questions.")
                        .font(V7Tokens.Typeface.hand(size: 19))
                        .foregroundStyle(V7Tokens.Text.primary)
                    Text("trust is per repo — the session list obeys it")
                        .font(V7Tokens.Typeface.mono(size: 9.5))
                        .foregroundStyle(V7Tokens.Text.tertiary)
                }
                Spacer(minLength: 0)
            }

            if rules.isEmpty {
                emptyState
            } else {
                leashCard
                patternsCard
                quietCard
            }

            Spacer(minLength: 0)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Spacer(minLength: 0)
            Text("No rules yet.")
                .font(V7Tokens.Typeface.hand(size: 17))
                .foregroundStyle(V7Tokens.Text.secondary)
            Text("accept an agent's suggested rule from a decision to start a leash")
                .font(V7Tokens.Typeface.mono(size: 9.5))
                .foregroundStyle(V7Tokens.Text.tertiary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var leashCard: some View {
        V7Card(verticalPadding: 9, horizontalPadding: 13) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Leash, per repo")
                    .font(V7Tokens.Typeface.ui(size: 12.5, weight: .semibold))
                    .foregroundStyle(V7Tokens.Text.onCard)
                    .padding(.bottom, 1)

                ForEach(rules.leashes) { leash in
                    HStack(spacing: 10) {
                        Text(leash.repo)
                            .font(V7Tokens.Typeface.mono(size: 10.5))
                            .foregroundStyle(V7Tokens.Text.onCard)
                            .frame(width: 112, alignment: .leading)
                            .lineLimit(1)

                        V7LeashDrawing(slack: leash.slack)
                            .frame(width: 150, height: 18)

                        Text(leash.note)
                            .font(V7Tokens.Typeface.mono(size: 8.5))
                            .foregroundStyle(V7Tokens.Text.onCardMuted)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                    .overlay(alignment: .top) { hairline }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(leash.repo))
                    .accessibilityValue(Text(leash.note))
                }
            }
        }
    }

    private var patternsCard: some View {
        V7Card(verticalPadding: 9, horizontalPadding: 13) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Auto-approve")
                    .font(V7Tokens.Typeface.ui(size: 12.5, weight: .semibold))
                    .foregroundStyle(V7Tokens.Text.onCard)
                    .padding(.bottom, 1)

                ForEach(rules.patterns) { pattern in
                    HStack(spacing: 10) {
                        Text(pattern.pattern)
                            .font(V7Tokens.Typeface.mono(size: 11))
                            .foregroundStyle(V7Tokens.Text.onCard)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(pattern.scope)
                            .font(V7Tokens.Typeface.mono(size: 9.5))
                            .foregroundStyle(V7Tokens.Text.onCardMuted)
                        V7Switch(isOn: pattern.enabled)
                    }
                    .padding(.vertical, 4)
                    .overlay(alignment: .top) { hairline }
                }

                // Some things are not a setting. Saying so out loud is part of
                // why the rest of the automation gets believed.
                HStack(spacing: 10) {
                    Text("git push --force")
                        .font(V7Tokens.Typeface.mono(size: 11))
                        .foregroundStyle(V7Tokens.Accent.loss)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(V7Tokens.Accent.loss)
                    Spacer(minLength: 0)
                    Text("always asks — not a setting")
                        .font(V7Tokens.Typeface.mono(size: 9.5))
                        .foregroundStyle(V7Tokens.Accent.loss)
                }
                .padding(.vertical, 4)
                .overlay(alignment: .top) { hairline }
            }
        }
    }

    private var quietCard: some View {
        V7Card(verticalPadding: 9, horizontalPadding: 13) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Quiet & batching")
                    .font(V7Tokens.Typeface.ui(size: 12.5, weight: .semibold))
                    .foregroundStyle(V7Tokens.Text.onCard)
                    .padding(.bottom, 1)

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Quiet hours")
                            .font(V7Tokens.Typeface.ui(size: 12.5))
                            .foregroundStyle(V7Tokens.Text.onCard)
                        Text(rules.quietHoursNote)
                            .font(V7Tokens.Typeface.mono(size: 8.5))
                            .foregroundStyle(V7Tokens.Text.onCardMuted)
                    }
                    Spacer(minLength: 0)
                    V7Switch(isOn: rules.quietHoursEnabled)
                }
                .padding(.vertical, 4.5)
                .overlay(alignment: .top) { hairline }

                HStack(spacing: 10) {
                    Text("Batch the non-urgent")
                        .font(V7Tokens.Typeface.ui(size: 12.5))
                        .foregroundStyle(V7Tokens.Text.onCard)
                    Spacer(minLength: 0)
                    Text(rules.batchInterval)
                        .font(V7Tokens.Typeface.mono(size: 10))
                        .foregroundStyle(V7Tokens.Text.onCard)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background {
                            RoundedRectangle(cornerRadius: V7Tokens.Radius.chip, style: .continuous)
                                .fill(V7Tokens.Text.onCard.opacity(0.07))
                        }
                }
                .padding(.vertical, 4.5)
                .overlay(alignment: .top) { hairline }

                HStack(spacing: 10) {
                    Text("Escalation sound")
                        .font(V7Tokens.Typeface.ui(size: 12.5))
                        .foregroundStyle(V7Tokens.Text.onCard)
                    Spacer(minLength: 0)
                    V7Switch(isOn: rules.escalationSound)
                }
                .padding(.vertical, 4.5)
                .overlay(alignment: .top) { hairline }
            }
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(V7Tokens.Text.onCard.opacity(0.08))
            .frame(height: 1)
    }
}

// MARK: - The leash

/// Trust drawn as leash length.
///
/// A long, slack line means the agent runs; a short taut one means it checks
/// in constantly. Reading it takes no legend, which is the point — this is the
/// screen where a number would invite fiddling.
struct V7LeashDrawing: View {
    /// `0` is fully tight (escalate everything), `1` fully loose.
    var slack: Double

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let clamped = min(1, max(0, slack))
            // The post stays put; the collar travels, and the line between
            // them sags in proportion to how far it has to reach.
            let endX = width * (0.22 + 0.72 * clamped)
            let sag = height * (0.18 + 0.55 * clamped)

            ZStack(alignment: .topLeading) {
                Path { path in
                    // The post.
                    path.move(to: CGPoint(x: 8, y: height * 0.2))
                    path.addLine(to: CGPoint(x: 8, y: height * 0.85))
                    // The line, sagging under its own slack.
                    path.move(to: CGPoint(x: 8, y: height * 0.42))
                    path.addCurve(
                        to: CGPoint(x: endX, y: height * 0.45),
                        control1: CGPoint(x: width * 0.3, y: height * 0.42 + sag),
                        control2: CGPoint(x: width * 0.7, y: height * 0.42 + sag)
                    )
                }
                .stroke(
                    V7Tokens.Text.onCard.opacity(0.6),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )

                // The collar.
                Circle()
                    .strokeBorder(V7Tokens.Text.onCard.opacity(0.6), lineWidth: 2)
                    .frame(width: 8, height: 8)
                    .offset(x: endX - 4, y: height * 0.45 - 4)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Model

/// The rules the concierge obeys.
///
/// **This has no backing store yet.** The app currently persists no leash, no
/// auto-approve pattern list, no quiet hours and no batching interval — the
/// board designs them, and the plumbing is a separate piece of work.
///
/// Until that lands, the tab renders whatever it is handed and shows an empty
/// state when handed nothing, rather than displaying invented rules that would
/// imply the automation is doing something it is not.
struct V7RulesModel: Equatable {
    var leashes: [Leash] = []
    var patterns: [Pattern] = []
    var quietHoursEnabled = false
    var quietHoursNote = "off — every escalation comes straight through"
    var batchInterval = "off"
    var escalationSound = false

    struct Leash: Identifiable, Equatable {
        var id: String { repo }
        var repo: String
        /// 0 = escalate everything, 1 = auto-approve almost everything.
        var slack: Double
        /// Why it sits where it does, in plain words.
        var note: String
    }

    struct Pattern: Identifiable, Equatable {
        var id: String { "\(pattern)|\(scope)" }
        var pattern: String
        var scope: String
        var enabled: Bool
    }

    var isEmpty: Bool { leashes.isEmpty && patterns.isEmpty }

    static let empty = V7RulesModel()
}
