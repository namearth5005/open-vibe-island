import SwiftUI
import OpenIslandCore

/// Your agent history, summarised.
///
/// Deliberately contains no goal, target, streak or notification. The numbers
/// sit there being interesting; they never ask anything of the user. That is the
/// difference between self-comparison, which sustains, and habit mechanics,
/// which spike and then churn.
struct StatsSettingsPane: View {
    @Bindable var model: AppModel

    /// Reached through the model, matching every other settings pane.
    /// `LanguageManager` is not injected into the SwiftUI environment anywhere in
    /// this app, so `@Environment(LanguageManager.self)` traps at render time.
    private var lang: LanguageManager { model.lang }

    @State private var range: StatsRange = .today
    /// Captured once per render pass so every figure on screen refers to the
    /// same instant — otherwise "today" could change mid-layout at midnight.
    private var now: Date { Date() }

    private var records: [SessionLogRecord] { model.sessionLogRecords }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                rangePicker
                summaryGrid
                comparisonBlock
                agentBreakdown
                if records.isEmpty { emptyState }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Range

    private var rangePicker: some View {
        Picker("", selection: $range) {
            Text(lang.t("settings.stats.range.today")).tag(StatsRange.today)
            Text(lang.t("settings.stats.range.sevenDays")).tag(StatsRange.sevenDays)
            Text(lang.t("settings.stats.range.allTime")).tag(StatsRange.allTime)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: - Summary

    private var summary: StatsSummary {
        SessionStats.summary(for: range, records: records, now: now)
    }

    private var summaryGrid: some View {
        let summary = self.summary
        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: 12)],
            alignment: .leading,
            spacing: 12
        ) {
            statTile(
                value: "\(summary.cleanFinishes)",
                label: lang.t("settings.stats.metric.finished")
            )
            statTile(
                value: Self.durationText(summary.totalRuntime),
                label: lang.t("settings.stats.metric.runtime")
            )
            statTile(
                value: summary.medianGateLatency.map(Self.latencyText) ?? "—",
                label: lang.t("settings.stats.metric.gateLatency")
            )
            statTile(
                value: summary.finished > 0
                    ? "\(Int((summary.interruptedRate * 100).rounded()))%"
                    : "—",
                label: lang.t("settings.stats.metric.interrupted")
            )
        }
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Comparison

    private var comparisonBlock: some View {
        let comparison = SessionStats.comparison(records: records, now: now)
        return VStack(alignment: .leading, spacing: 12) {
            Text(lang.t("settings.stats.comparison.title"))
                .font(.system(size: 13, weight: .semibold))

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("\(comparison.trailingSeven)")
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                        if comparison.priorSeven > 0 || comparison.trailingSeven > 0 {
                            Text(Self.deltaText(comparison.delta))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(comparison.delta >= 0 ? .green : .secondary)
                        }
                    }
                    Text(lang.t("settings.stats.comparison.thisWeek"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(comparison.personalBestDay)")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text(lang.t("settings.stats.comparison.best"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
                Sparkline(values: comparison.sparkline)
                    .frame(width: 132, height: 42)
            }

            if comparison.isPersonalBestToday {
                Text(lang.t("settings.stats.comparison.bestToday"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Agents

    @ViewBuilder
    private var agentBreakdown: some View {
        let slices = summary.byAgent
        if !slices.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(lang.t("settings.stats.byAgent"))
                    .font(.system(size: 13, weight: .semibold))

                ForEach(slices, id: \.tool) { slice in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color(hex: slice.tool.brandColorHex) ?? .gray)
                            .frame(width: 9, height: 9)
                        Text(slice.tool.displayName)
                            .font(.system(size: 12))
                        Spacer(minLength: 8)
                        Text(Self.durationText(slice.runtime))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("\(slice.finished)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .frame(minWidth: 28, alignment: .trailing)
                    }
                }
            }
            .padding(14)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var emptyState: some View {
        Text(lang.t("settings.stats.empty"))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
    }

    // MARK: - Formatting

    static func durationText(_ seconds: TimeInterval) -> String {
        guard seconds >= 60 else { return "\(Int(seconds))s" }
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    static func latencyText(_ seconds: Double) -> String {
        seconds < 60 ? "\(Int(seconds.rounded()))s" : "\(Int((seconds / 60).rounded()))m"
    }

    static func deltaText(_ delta: Int) -> String {
        delta > 0 ? "+\(delta)" : "\(delta)"
    }
}

/// Bar sparkline of daily counts, oldest on the left.
///
/// Bars rather than a line: with seven integer values, often small ones, a line
/// chart implies a continuity the data does not have.
private struct Sparkline: View {
    let values: [Int]

    var body: some View {
        let peak = max(values.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                GeometryReader { proxy in
                    let fraction = Double(value) / Double(peak)
                    // Zero days still show a sliver, so the axis stays legible
                    // and a gap reads as "nothing" rather than as missing data.
                    let height = max(2, proxy.size.height * fraction)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index == values.count - 1 ? Color.orange : Color.secondary.opacity(0.55))
                        .frame(height: height)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
    }
}
