import Foundation

/// Which slice of history a summary covers.
public enum StatsRange: String, CaseIterable, Identifiable, Sendable {
    case today
    case sevenDays
    case allTime

    public var id: String { rawValue }
}

/// One agent's share of a range.
public struct AgentStatsSlice: Equatable, Sendable {
    public let tool: AgentTool
    public let finished: Int
    public let runtime: TimeInterval
}

/// A computed summary. Everything the Stats view renders comes from here.
public struct StatsSummary: Equatable, Sendable {
    /// Any completed session.
    public let finished: Int
    /// Completed without an interrupt.
    public let cleanFinishes: Int
    public let interrupted: Int
    public let totalRuntime: TimeInterval
    /// Median of per-session mean gate latency, over sessions that had gates.
    public let medianGateLatency: Double?
    /// Every second an agent in this range stood blocked on the human, summed.
    ///
    /// Reconstructed exactly rather than approximated: `meanGateLatency` is
    /// `frozenSeconds / stallCount` by construction, so the product restores the
    /// seconds the shard actually counted. Sessions that never blocked
    /// contribute nothing, which is why this can be zero on a busy day.
    public let totalWaiting: TimeInterval
    /// The longest single clean session in the range. `nil` when the range
    /// contains no clean finish — an interrupt is not a run, however long it
    /// went before it was killed.
    public let longestCleanRun: TimeInterval?
    /// Sessions the app watched live *and* that recorded an answer time.
    ///
    /// The denominator for "was the human keeping up". Deliberately narrower
    /// than `finished`: a session that never asked has no answer to be judged,
    /// and an inferred one has answer times that were never observed at all.
    public let gatedSessions: Int
    /// Of `gatedSessions`, how many kept every gate inside
    /// `RewardRarity.graceWindow`.
    public let answeredInsideGrace: Int
    /// Sessions in this range that were derived from a transcript rather than
    /// watched. Kept as a count rather than as a filter because callers need to
    /// *say* how much of a figure was inferred, not to recompute it.
    public let inferred: Int
    public let byAgent: [AgentStatsSlice]

    public var interruptedRate: Double {
        guard finished > 0 else { return 0 }
        return Double(interrupted) / Double(finished)
    }
}

/// Self-comparison figures — the reason to reopen the view.
///
/// Deliberately contains no streak. Streaks share a vocabulary with these but
/// produce the opposite retention outcome: something you can break is a reason
/// to quit, whereas a number that is merely higher or lower than last week asks
/// nothing of the user.
public struct StatsComparison: Equatable, Sendable {
    /// Clean finishes in the trailing 7 days ending today.
    public let trailingSeven: Int
    /// Clean finishes in the 7 days before that.
    public let priorSeven: Int
    /// Best single local day, all time, by clean finishes.
    public let personalBestDay: Int
    /// Clean finishes today.
    public let today: Int
    /// Oldest to newest, 7 entries ending today.
    public let sparkline: [Int]

    public var delta: Int { trailingSeven - priorSeven }

    public var isPersonalBestToday: Bool {
        today > 0 && today >= personalBestDay
    }
}

/// Pure computation over log records.
///
/// No file access and no ambient clock — the caller passes `now` — so every
/// figure is reproducible and testable, including across day and week boundaries.
public enum SessionStats {
    public static func summary(
        for range: StatsRange,
        records: [SessionLogRecord],
        now: Date,
        calendar: Calendar = .current
    ) -> StatsSummary {
        let scoped = filter(records, range: range, now: now, calendar: calendar)

        let interrupted = scoped.filter(\.wasInterrupted).count
        let latencies = scoped.compactMap(\.meanGateLatency).sorted()

        var runtimeByTool: [AgentTool: TimeInterval] = [:]
        var countByTool: [AgentTool: Int] = [:]
        for record in scoped {
            runtimeByTool[record.tool, default: 0] += record.duration
            countByTool[record.tool, default: 0] += 1
        }

        // Built in steps: the fused map-and-sort chain exceeded the type-checker's
        // budget, and splitting it is cheaper than annotating every closure.
        var slices: [AgentStatsSlice] = []
        for (tool, count) in countByTool {
            let runtime: TimeInterval = runtimeByTool[tool] ?? 0
            slices.append(AgentStatsSlice(tool: tool, finished: count, runtime: runtime))
        }
        let byAgent: [AgentStatsSlice] = slices.sorted { lhs, rhs in
            if lhs.finished != rhs.finished { return lhs.finished > rhs.finished }
            return lhs.tool.rawValue < rhs.tool.rawValue
        }

        // Inference can support "this session happened and finished" — that is
        // what a transcript proves — and nothing about how fast anyone answered
        // it: back-fill writes no latencies because a transcript has none.
        // Taking its silence for an answer time is the same inflation the
        // `isInferred` flag was added to stop, so the grace figures are drawn
        // from watched sessions alone.
        let gated = scoped.filter {
            $0.isInferred != true && ($0.worstGateLatency ?? $0.meanGateLatency) != nil
        }

        return StatsSummary(
            finished: scoped.count,
            cleanFinishes: scoped.filter(\.isCleanFinish).count,
            interrupted: interrupted,
            totalRuntime: scoped.reduce(0) { $0 + $1.duration },
            medianGateLatency: median(latencies),
            totalWaiting: scoped.reduce(0) { $0 + ($1.meanGateLatency ?? 0) * Double($1.stallCount) },
            longestCleanRun: scoped.filter(\.isCleanFinish).map(\.duration).max(),
            gatedSessions: gated.count,
            // The rarity ladder's rule, called rather than restated, so "in
            // time" cannot come to mean one thing on the receipt and another on
            // the object a session leaves behind.
            answeredInsideGrace: gated.filter(RewardRarity.answeredWithinGrace).count,
            inferred: scoped.filter { $0.isInferred == true }.count,
            byAgent: byAgent
        )
    }

    public static func comparison(
        records: [SessionLogRecord],
        now: Date,
        calendar: Calendar = .current
    ) -> StatsComparison {
        let clean = records.filter(\.isCleanFinish)
        let today = calendar.startOfDay(for: now)

        // Day offset 0 is today, 1 is yesterday, and so on.
        func cleanFinishes(dayOffset: Int) -> Int {
            guard let dayStart = calendar.date(byAdding: .day, value: -dayOffset, to: today),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
            else {
                return 0
            }
            return clean.filter { $0.endedAt >= dayStart && $0.endedAt < dayEnd }.count
        }

        let trailing = (0..<7).reduce(0) { $0 + cleanFinishes(dayOffset: $1) }
        let prior = (7..<14).reduce(0) { $0 + cleanFinishes(dayOffset: $1) }

        var perDay: [Date: Int] = [:]
        for record in clean {
            perDay[calendar.startOfDay(for: record.endedAt), default: 0] += 1
        }

        return StatsComparison(
            trailingSeven: trailing,
            priorSeven: prior,
            personalBestDay: perDay.values.max() ?? 0,
            today: cleanFinishes(dayOffset: 0),
            // Oldest first so it reads left to right.
            sparkline: (0..<7).reversed().map { cleanFinishes(dayOffset: $0) }
        )
    }

    /// Clean finishes on the local day containing `now`. Used by the pill tally
    /// so the number in the notch and the number in the Stats view agree.
    public static func cleanFinishesToday(
        records: [SessionLogRecord],
        now: Date,
        calendar: Calendar = .current
    ) -> Int {
        records.filter { $0.isCleanFinish && calendar.isDate($0.endedAt, inSameDayAs: now) }.count
    }

    // MARK: - Internals

    static func filter(
        _ records: [SessionLogRecord],
        range: StatsRange,
        now: Date,
        calendar: Calendar
    ) -> [SessionLogRecord] {
        switch range {
        case .allTime:
            return records
        case .today:
            return records.filter { calendar.isDate($0.endedAt, inSameDayAs: now) }
        case .sevenDays:
            let today = calendar.startOfDay(for: now)
            guard let start = calendar.date(byAdding: .day, value: -6, to: today) else {
                return records
            }
            return records.filter { $0.endedAt >= start }
        }
    }

    /// Median of per-session means, not a pooled median over every gate: one
    /// session with forty gates should not be able to dominate the figure.
    static func median(_ sorted: [Double]) -> Double? {
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
