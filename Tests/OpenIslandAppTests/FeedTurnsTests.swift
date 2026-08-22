import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// The feed read as a wall of lines because prose, the tools it triggered and
/// the next prose block all sat at the same rhythm. Grouping is what makes a
/// turn separable at a glance, so the grouping rule is pinned here.
struct FeedTurnsTests {
    private func entry(_ id: String, _ kind: AgentFeedEntry.Kind) -> AgentFeedEntry {
        AgentFeedEntry(id: id, timestamp: Date(timeIntervalSince1970: 0), kind: kind)
    }

    @Test
    func toolsAttachToTheProseAboveThem() {
        let turns = FeedTurns.grouped([
            entry("1", .said("Reading the panel")),
            entry("2", .ran(tool: "Read", argument: "IslandPanelView.swift")),
            entry("3", .ran(tool: "Grep", argument: "clipShape")),
        ])

        #expect(turns.count == 1)
        #expect(turns[0].lead.count == 1)
        #expect(turns[0].actions.count == 2)
    }

    @Test
    func proseAfterToolsStartsANewTurn() {
        let turns = FeedTurns.grouped([
            entry("1", .said("first")),
            entry("2", .ran(tool: "Read", argument: "a.swift")),
            entry("3", .said("second")),
            entry("4", .edited(file: "b.swift", added: 2, removed: 1)),
        ])

        #expect(turns.count == 2)
        #expect(turns[0].id == "1")
        #expect(turns[1].id == "3")
        #expect(turns[1].actions.count == 1)
    }

    /// A record is thinking, then text, then tools. Thinking must not split off
    /// into a turn of its own containing one grey word.
    @Test
    func thinkingStaysWithTheProseItPrecedes() {
        let turns = FeedTurns.grouped([
            entry("1", .thought(tokens: nil)),
            entry("2", .said("Found it")),
            entry("3", .ran(tool: "Bash", argument: "swift build")),
        ])

        #expect(turns.count == 1)
        #expect(turns[0].lead.count == 2)
        #expect(turns[0].actions.count == 1)
    }

    /// A tail can begin mid-turn, so the first entry is often a tool call with
    /// no prose above it. That must still render, not be dropped.
    @Test
    func toolsWithNoProseAboveThemStillForATurn() {
        let turns = FeedTurns.grouped([
            entry("1", .ran(tool: "Read", argument: "a.swift")),
            entry("2", .said("now I see")),
        ])

        #expect(turns.count == 2)
        #expect(turns[0].lead.isEmpty)
        #expect(turns[0].actions.count == 1)
        #expect(turns[1].lead.count == 1)
    }

    @Test
    func everyEntrySurvivesGrouping() {
        let entries = [
            entry("1", .said("a")),
            entry("2", .ran(tool: "Read", argument: "a.swift")),
            entry("3", .thought(tokens: nil)),
            entry("4", .said("b")),
            entry("5", .edited(file: "b.swift", added: 1, removed: 0)),
        ]
        let grouped = FeedTurns.grouped(entries).flatMap { $0.lead + $0.actions }

        #expect(grouped.map(\.id) == ["1", "2", "3", "4", "5"])
    }

    @Test
    func emptyFeedHasNoTurns() {
        #expect(FeedTurns.grouped([]).isEmpty)
    }
}

/// The timestamp column is narrow. A 12-hour locale renders `12:57 AM` into it
/// and the column shows `12:5…`, so the feed forces a fixed 24-hour stamp.
struct FeedClockTests {
    private let utc = TimeZone(identifier: "UTC")!

    @Test
    func padsToFiveCharactersRegardlessOfHour() {
        let midnight = Date(timeIntervalSince1970: 57 * 60)
        #expect(FeedClock.stamp(midnight, in: utc) == "00:57")
    }

    @Test
    func usesTwentyFourHourClockForAfternoonTimes() {
        let afternoon = Date(timeIntervalSince1970: (13 * 3600) + (5 * 60))
        #expect(FeedClock.stamp(afternoon, in: utc) == "13:05")
    }
}

/// Spec §6. The summary row is what a reader sees instead of the block, so its
/// text and its diff totals are pinned here.
struct FeedTurnSummaryTests {
    private func entry(_ id: String, _ kind: AgentFeedEntry.Kind) -> AgentFeedEntry {
        AgentFeedEntry(id: id, timestamp: Date(timeIntervalSince1970: 0), kind: kind)
    }

    /// The header shipped "1 files"; pluralisation lives in one testable place now.
    @Test
    func labelPluralisesOnlyWhenItShould() {
        #expect(FeedTurnSummary.label(actionCount: 1) == "1 action")
        #expect(FeedTurnSummary.label(actionCount: 4) == "4 actions")
        #expect(FeedTurnSummary.label(actionCount: 0) == "0 actions")
    }

    @Test
    func diffTotalsSumOnlyTheEdits() {
        let turns = FeedTurns.grouped([
            entry("1", .said("working")),
            entry("2", .edited(file: "a.swift", added: 10, removed: 3)),
            entry("3", .edited(file: "b.swift", added: 5, removed: 1)),
            entry("4", .ran(tool: "Bash", argument: "swift build")),
        ])

        #expect(turns.count == 1)
        #expect(turns[0].actionCount == 3)
        #expect(turns[0].linesAdded == 15)
        #expect(turns[0].linesRemoved == 4)
        #expect(turns[0].hasDiff)
    }

    @Test
    func aTurnWithNoEditsHasNoDiff() {
        let turns = FeedTurns.grouped([
            entry("1", .said("looking")),
            entry("2", .ran(tool: "Read", argument: "a.swift")),
        ])
        #expect(turns[0].hasDiff == false)
    }
}

/// Spec §6.2. The newest turn is open by default; a turn the user touched keeps
/// their choice permanently. The distinction matters -- with a set of flips
/// rather than absolute values, a newest turn the user collapsed would spring
/// back open the moment a newer turn arrived and its default changed.
struct FeedExpansionTests {
    @Test
    func newestIsOpenAndOlderAreShutByDefault() {
        let state = FeedExpansion()
        #expect(state.isExpanded(turnID: "new", isNewest: true))
        #expect(state.isExpanded(turnID: "old", isNewest: false) == false)
    }

    @Test
    func anExplicitChoiceWins() {
        var state = FeedExpansion()
        state.toggle(turnID: "old", isNewest: false)
        #expect(state.isExpanded(turnID: "old", isNewest: false))

        state.toggle(turnID: "new", isNewest: true)
        #expect(state.isExpanded(turnID: "new", isNewest: true) == false)
    }

    /// The regression the dictionary exists to prevent.
    @Test
    func aCollapsedNewestTurnStaysShutAsItAges() {
        var state = FeedExpansion()
        state.toggle(turnID: "t", isNewest: true)      // user collapses the live turn
        #expect(state.isExpanded(turnID: "t", isNewest: true) == false)
        // a newer turn arrives; "t" is no longer newest
        #expect(state.isExpanded(turnID: "t", isNewest: false) == false)
    }

    @Test
    func anUntouchedTurnCollapsesOnItsOwnAsItAges() {
        let state = FeedExpansion()
        #expect(state.isExpanded(turnID: "t", isNewest: true))
        #expect(state.isExpanded(turnID: "t", isNewest: false) == false)
    }
}
