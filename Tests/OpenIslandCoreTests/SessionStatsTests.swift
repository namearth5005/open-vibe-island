import Foundation
import Testing
@testable import OpenIslandCore

struct SessionStatsTests {
    /// A fixed local noon, so day bucketing never straddles midnight by accident.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private let now = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 22:13:20 UTC

    private func day(_ offset: Int, hour: Int = 12) -> Date {
        let today = calendar.startOfDay(for: now)
        let base = calendar.date(byAdding: .day, value: -offset, to: today)!
        return calendar.date(byAdding: .hour, value: hour, to: base)!
    }

    private func record(
        _ id: String,
        tool: AgentTool = .claudeCode,
        endedAt: Date,
        durationSeconds: TimeInterval = 60,
        interrupted: Bool = false,
        latency: Double? = nil
    ) -> SessionLogRecord {
        SessionLogRecord(
            sessionID: id,
            tool: tool,
            startedAt: endedAt.addingTimeInterval(-durationSeconds),
            endedAt: endedAt,
            wasInterrupted: interrupted,
            stallCount: latency == nil ? 0 : 1,
            meanGateLatency: latency
        )
    }

    // MARK: - Ranges

    @Test
    func todayCountsOnlyTheLocalDayOfEndedAt() {
        let records = [
            record("today", endedAt: day(0)),
            record("yesterday", endedAt: day(1)),
        ]
        let summary = SessionStats.summary(for: .today, records: records, now: now, calendar: calendar)
        #expect(summary.finished == 1)
    }

    /// A long session that began yesterday and finished today belongs to today —
    /// the log is a record of finishing, not of starting.
    @Test
    func aSessionSpanningMidnightCountsOnTheDayItEnded() {
        let endedToday = day(0, hour: 1)
        let record = record("overnight", endedAt: endedToday, durationSeconds: 4 * 3600)
        let summary = SessionStats.summary(for: .today, records: [record], now: now, calendar: calendar)
        #expect(summary.finished == 1)
    }

    @Test
    func sevenDaysIncludesTodayAndSixDaysBackButNotSeven() {
        let records = [
            record("d0", endedAt: day(0)),
            record("d6", endedAt: day(6)),
            record("d7", endedAt: day(7)),
        ]
        let summary = SessionStats.summary(for: .sevenDays, records: records, now: now, calendar: calendar)
        #expect(summary.finished == 2)
    }

    @Test
    func allTimeIncludesEverything() {
        let records = [record("old", endedAt: day(400)), record("new", endedAt: day(0))]
        let summary = SessionStats.summary(for: .allTime, records: records, now: now, calendar: calendar)
        #expect(summary.finished == 2)
    }

    // MARK: - Finished versus clean

    @Test
    func cleanFinishesExcludeInterruptedButFinishedDoesNot() {
        let records = [
            record("clean", endedAt: day(0)),
            record("broken", endedAt: day(0), interrupted: true),
        ]
        let summary = SessionStats.summary(for: .today, records: records, now: now, calendar: calendar)
        #expect(summary.finished == 2)
        #expect(summary.cleanFinishes == 1)
        #expect(summary.interrupted == 1)
        #expect(summary.interruptedRate == 0.5)
    }

    @Test
    func interruptedRateIsZeroRatherThanUndefinedWhenNothingFinished() {
        let summary = SessionStats.summary(for: .today, records: [], now: now, calendar: calendar)
        #expect(summary.interruptedRate == 0)
        #expect(summary.finished == 0)
        #expect(summary.medianGateLatency == nil)
        #expect(summary.byAgent.isEmpty)
    }

    // MARK: - Latency

    /// Sessions without gates must be absent, not zero — zero would drag the
    /// median toward an answer time nobody ever achieved.
    @Test
    func medianGateLatencyIgnoresSessionsThatHadNoGates() {
        let records = [
            record("a", endedAt: day(0), latency: 10),
            record("b", endedAt: day(0), latency: 20),
            record("nogates", endedAt: day(0), latency: nil),
        ]
        let summary = SessionStats.summary(for: .today, records: records, now: now, calendar: calendar)
        #expect(summary.medianGateLatency == 15)
    }

    @Test
    func medianOfOddCountTakesTheMiddleValue() {
        #expect(SessionStats.median([5, 10, 100]) == 10)
    }

    @Test
    func medianOfEmptyIsNil() {
        #expect(SessionStats.median([]) == nil)
    }

    // MARK: - Per agent

    @Test
    func perAgentSplitCountsAndSumsRuntimeSortedByVolume() {
        let records = [
            record("a", tool: .codex, endedAt: day(0), durationSeconds: 100),
            record("b", tool: .claudeCode, endedAt: day(0), durationSeconds: 50),
            record("c", tool: .claudeCode, endedAt: day(0), durationSeconds: 70),
        ]
        let summary = SessionStats.summary(for: .today, records: records, now: now, calendar: calendar)
        #expect(summary.byAgent.first?.tool == .claudeCode)
        #expect(summary.byAgent.first?.finished == 2)
        #expect(summary.byAgent.first?.runtime == 120)
        #expect(summary.totalRuntime == 220)
    }

    // MARK: - Comparison

    @Test
    func trailingSevenComparesAgainstThePriorSeven() {
        var records: [SessionLogRecord] = []
        for offset in 0..<7 { records.append(record("recent\(offset)", endedAt: day(offset))) }
        for offset in 7..<14 {
            records.append(record("older\(offset)", endedAt: day(offset)))
            records.append(record("older\(offset)b", endedAt: day(offset)))
        }
        let comparison = SessionStats.comparison(records: records, now: now, calendar: calendar)
        #expect(comparison.trailingSeven == 7)
        #expect(comparison.priorSeven == 14)
        #expect(comparison.delta == -7)
    }

    @Test
    func comparisonExcludesInterruptedSessionsFromEveryFigure() {
        let records = [
            record("clean", endedAt: day(0)),
            record("broken", endedAt: day(0), interrupted: true),
        ]
        let comparison = SessionStats.comparison(records: records, now: now, calendar: calendar)
        #expect(comparison.today == 1)
        #expect(comparison.trailingSeven == 1)
        #expect(comparison.personalBestDay == 1)
    }

    @Test
    func personalBestIsTheHighestSingleDayEver() {
        let records = [
            record("a", endedAt: day(30)),
            record("b", endedAt: day(30)),
            record("c", endedAt: day(30)),
            record("d", endedAt: day(0)),
        ]
        let comparison = SessionStats.comparison(records: records, now: now, calendar: calendar)
        #expect(comparison.personalBestDay == 3)
        #expect(comparison.isPersonalBestToday == false)
    }

    @Test
    func todayTiesTheRecordAndCountsAsAPersonalBest() {
        let records = [record("a", endedAt: day(30)), record("b", endedAt: day(0))]
        let comparison = SessionStats.comparison(records: records, now: now, calendar: calendar)
        #expect(comparison.isPersonalBestToday)
    }

    /// A day with no work must not read as a record-equalling day.
    @Test
    func anEmptyDayIsNotAPersonalBest() {
        let comparison = SessionStats.comparison(records: [], now: now, calendar: calendar)
        #expect(comparison.isPersonalBestToday == false)
        #expect(comparison.personalBestDay == 0)
    }

    @Test
    func sparklineHasSevenEntriesOldestFirstEndingToday() {
        let records = [
            record("today", endedAt: day(0)),
            record("t1", endedAt: day(6)),
            record("t2", endedAt: day(6)),
        ]
        let comparison = SessionStats.comparison(records: records, now: now, calendar: calendar)
        #expect(comparison.sparkline.count == 7)
        #expect(comparison.sparkline.first == 2)
        #expect(comparison.sparkline.last == 1)
    }

    // MARK: - Pill tally parity

    /// The notch tally and the Stats view sit inches apart; they must never
    /// disagree, so both read this one function.
    @Test
    func cleanFinishesTodayMatchesTheTodaySummary() {
        let records = [
            record("a", endedAt: day(0)),
            record("b", endedAt: day(0), interrupted: true),
            record("c", endedAt: day(1)),
        ]
        let tally = SessionStats.cleanFinishesToday(records: records, now: now, calendar: calendar)
        let summary = SessionStats.summary(for: .today, records: records, now: now, calendar: calendar)
        #expect(tally == summary.cleanFinishes)
        #expect(tally == 1)
    }
}
