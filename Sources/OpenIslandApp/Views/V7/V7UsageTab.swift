import SwiftUI
import OpenIslandCore

/// **Usage** — board 5c.
///
/// Merging the inbox into Sessions frees a corner, and this spends it on what
/// the codebase already measures: the Claude 5-hour and 7-day windows, and the
/// Codex weekly window.
///
/// The near-limit meter is what makes this a tab rather than a settings pane —
/// it changes where you route work, so it belongs where you can see it.
struct V7UsageTab: View {
    var model: AppModel
    var sessions: [AgentSession]
    var referenceDate: Date

    var body: some View {
        let meters = self.meters

        VStack(alignment: .leading, spacing: 7) {
            V7Headline(
                title: headline(for: meters),
                meta: meters.isEmpty
                    ? "no usage data yet — it appears once an agent reports a limit"
                    : "the fleet's limits, where routing decisions get made"
            )

            if meters.isEmpty {
                emptyState
            } else {
                V7Card(verticalPadding: 10, horizontalPadding: 13) {
                    VStack(spacing: 0) {
                        ForEach(Array(meters.enumerated()), id: \.element.id) { index, meter in
                            V7UsageMeterRow(meter: meter, showsDivider: index > 0)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    /// Names the constraint if there is one; otherwise says so plainly.
    private func headline(for meters: [V7UsageMeter]) -> String {
        guard !meters.isEmpty else { return "No limits reported." }
        if let tight = meters.filter({ $0.isNearLimit }).max(by: { $0.percent < $1.percent }) {
            return "\(tight.name) is close to its limit."
        }
        return "Fuel, at a glance."
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Spacer(minLength: 0)
            V7CompanionView(mood: .bored, bodyTreatment: .light)
                .frame(width: 72, height: 45)
            Text("Nothing to meter yet.")
                .font(V7Tokens.Typeface.hand(size: 17))
                .foregroundStyle(V7Tokens.Text.secondary)
            Text("claude and codex report their windows once they run")
                .font(V7Tokens.Typeface.mono(size: 9.5))
                .foregroundStyle(V7Tokens.Text.tertiary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    /// Reads the snapshots the app already collects. Nothing is synthesised —
    /// a provider with no snapshot simply has no meter.
    private var meters: [V7UsageMeter] {
        var result: [V7UsageMeter] = []

        if let claude = model.claudeUsageSnapshot {
            if let window = claude.fiveHour {
                result.append(
                    V7UsageMeter(
                        id: "claude-5h",
                        name: "claude",
                        window: "5h window",
                        percent: window.roundedUsedPercentage,
                        color: V7Tokens.agentColor(for: .claudeCode),
                        note: Self.resetNote(window.resetsAt, at: referenceDate)
                    )
                )
            }
            if let window = claude.sevenDay {
                result.append(
                    V7UsageMeter(
                        id: "claude-7d",
                        name: "claude",
                        window: "weekly",
                        percent: window.roundedUsedPercentage,
                        color: V7Tokens.agentColor(for: .claudeCode),
                        note: Self.resetNote(window.resetsAt, at: referenceDate)
                    )
                )
            }
        }

        if let codex = model.codexUsageSnapshot {
            for window in codex.windows {
                result.append(
                    V7UsageMeter(
                        id: "codex-\(window.key)",
                        name: "codex",
                        window: window.label.lowercased(),
                        percent: Int(window.usedPercentage.rounded()),
                        color: V7Tokens.agentColor(for: .codex),
                        note: Self.resetNote(window.resetsAt, at: referenceDate)
                    )
                )
            }
        }

        return result
    }

    /// `resets 2:40 pm` / `resets monday`. Never a countdown — a ticking
    /// number is pressure, and nothing here is urgent.
    private static func resetNote(_ date: Date?, at referenceDate: Date) -> String {
        guard let date, date > referenceDate else { return "" }

        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: referenceDate) {
            formatter.dateFormat = "h:mm a"
            return "resets \(formatter.string(from: date).lowercased())"
        }
        if let days = calendar.dateComponents([.day], from: referenceDate, to: date).day, days < 7 {
            formatter.dateFormat = "EEEE"
            return "resets \(formatter.string(from: date).lowercased())"
        }
        formatter.dateFormat = "MMM d"
        return "resets \(formatter.string(from: date))"
    }
}

/// One provider window.
struct V7UsageMeter: Identifiable, Equatable {
    var id: String
    var name: String
    var window: String
    var percent: Int
    var color: Color
    var note: String

    /// The threshold at which routing should change. Below this the meter is
    /// information; above it, it is advice.
    var isNearLimit: Bool { percent >= 80 }
}

/// A meter row: name, window, hand numeral, bar, and what happens next.
struct V7UsageMeterRow: View {
    var meter: V7UsageMeter
    var showsDivider: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                V7AgentDot(color: meter.color)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] }

                Text("\(meter.name) · \(meter.window)")
                    .font(V7Tokens.Typeface.mono(size: 11))
                    .foregroundStyle(V7Tokens.Text.onCard)

                Spacer(minLength: 0)

                // Hand numerals — this is a number a human reads, not data
                // that has to line up.
                Text("\(meter.percent)%")
                    .font(V7Tokens.Typeface.handNumeral(size: 20))
                    .foregroundStyle(
                        meter.isNearLimit ? V7Tokens.Accent.loss : V7Tokens.Text.onCard
                    )
            }

            GeometryReader { geometry in
                let fraction = min(1, max(0, Double(meter.percent) / 100))
                ZStack(alignment: .leading) {
                    Capsule().fill(V7Tokens.Text.onCard.opacity(0.08))
                    Capsule()
                        .fill(meter.color)
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: 8)
            .padding(.top, 5)

            // Near-limit gets a glyph as well as a colour, like every other
            // urgent thing on the board.
            HStack(spacing: 5) {
                if meter.isNearLimit {
                    V7StatusGlyphView(
                        glyph: .asterisk,
                        color: V7Tokens.Accent.loss,
                        size: 8,
                        lineWidth: 1.8
                    )
                    Text("near limit — route new work elsewhere")
                        .font(V7Tokens.Typeface.mono(size: 8.5))
                        .foregroundStyle(V7Tokens.Accent.loss)
                } else if !meter.note.isEmpty {
                    Text(meter.note)
                        .font(V7Tokens.Typeface.mono(size: 8.5))
                        .foregroundStyle(V7Tokens.Text.onCardMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 3)
        }
        .padding(.vertical, 6)
        .overlay(alignment: .top) {
            if showsDivider {
                Rectangle()
                    .fill(V7Tokens.Text.onCard.opacity(0.08))
                    .frame(height: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(meter.name) \(meter.window)"))
        .accessibilityValue(Text("\(meter.percent) percent used"))
    }
}
