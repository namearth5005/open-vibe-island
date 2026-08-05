import Foundation
import Testing
@testable import OpenIslandCore

/// Who the companion is.
///
/// The roster was cut, so this is now the only thing that decides which of the
/// six bodies the destination surface draws. It has to be a function of the log
/// and nothing else: a companion whose species depends on dictionary ordering,
/// on which session happens to be featured, or on the order the log was read in
/// is not an individual, and the whole argument for going from five creatures to
/// one was that one individual is a stronger character than a taxonomy.
struct CompanionIdentityTests {
    private func record(
        _ id: String,
        tool: AgentTool,
        endedAt: Date = Date(timeIntervalSince1970: 1_000_000),
        interrupted: Bool = false
    ) -> SessionLogRecord {
        SessionLogRecord(
            sessionID: id,
            tool: tool,
            workspace: "w",
            startedAt: endedAt.addingTimeInterval(-600),
            endedAt: endedAt,
            wasInterrupted: interrupted,
            stallCount: 0
        )
    }

    @Test
    func anEmptyLogWearsTheFallbackBody() {
        #expect(CompanionIdentity.species(for: []) == CompanionIdentity.fallback)
    }

    @Test
    func theAgentYouFinishTheMostWorkWithGetsTheBody() {
        let records = [
            record("1", tool: .codex),
            record("2", tool: .codex),
            record("3", tool: .claudeCode),
        ]
        #expect(CompanionIdentity.species(for: records) == .codex)
    }

    /// The four Claude Code forks share a body, so counting by tool would split
    /// one companion's history four ways and hand the surface to a minority
    /// agent that had never out-worked it.
    @Test
    func theClaudeForksCountAsOneCompanionRatherThanFour() {
        let records = [
            record("1", tool: .claudeCode),
            record("2", tool: .qoder),
            record("3", tool: .qwenCode),
            record("4", tool: .cursor),
            record("5", tool: .cursor),
            record("6", tool: .cursor),
        ]
        #expect(CompanionIdentity.species(for: records) == .claude)
    }

    @Test
    func aTieGoesToWhoeverFinishedMostRecently() {
        let old = Date(timeIntervalSince1970: 1_000_000)
        let recent = old.addingTimeInterval(3_600)
        let records = [
            record("1", tool: .geminiCLI, endedAt: recent),
            record("2", tool: .kimiCLI, endedAt: old),
        ]
        #expect(CompanionIdentity.species(for: records) == .gemini)
    }

    /// The order the log was read in is not a fact about you.
    @Test
    func theOrderOfTheLogDoesNotChangeTheAnswer() {
        let records = [
            record("1", tool: .codex),
            record("2", tool: .claudeCode),
            record("3", tool: .codex),
            record("4", tool: .openCode),
        ]
        let answer = CompanionIdentity.species(for: records)
        #expect(CompanionIdentity.species(for: records.reversed()) == answer)
        #expect(CompanionIdentity.species(for: records.shuffled()) == answer)
    }

    /// Two identical answers in a row is not enough — dictionary iteration is
    /// stable within a process. Repeating a genuinely tied log many times is
    /// what catches a comparison that leans on hashing.
    @Test
    func aFullyTiedLogStillAnswersTheSameWayEveryTime() {
        let sameInstant = Date(timeIntervalSince1970: 1_000_000)
        let records = CreatureSpecies.allCases.enumerated().map { index, species in
            record("\(index)", tool: tool(for: species), endedAt: sameInstant)
        }
        let answers = Set((0..<50).map { _ in CompanionIdentity.species(for: records.shuffled()) })
        #expect(answers.count == 1)
    }

    /// The collection deduplicates by session ID and so does this — a session
    /// logged live and back-filled must not vote twice.
    @Test
    func aSessionPresentTwiceIsCountedOnce() {
        let duplicated = record("dup", tool: .cursor)
        let records = [duplicated, duplicated, record("other", tool: .codex), record("other2", tool: .codex)]
        #expect(CompanionIdentity.species(for: records) == .codex)
    }

    /// An interrupted session is still time you spent with that agent. The
    /// receipt charges for the interrupt; the body does not.
    @Test
    func anInterruptedSessionStillCountsTowardTheBody() {
        let records = [
            record("1", tool: .kimiCLI, interrupted: true),
            record("2", tool: .kimiCLI, interrupted: true),
            record("3", tool: .claudeCode),
        ]
        #expect(CompanionIdentity.species(for: records) == .kimi)
    }

    private func tool(for species: CreatureSpecies) -> AgentTool {
        switch species {
        case .claude: .claudeCode
        case .codex: .codex
        case .cursor: .cursor
        case .gemini: .geminiCLI
        case .kimi: .kimiCLI
        case .openCode: .openCode
        }
    }
}
