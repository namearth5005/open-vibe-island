import Testing
@testable import OpenIslandCore

struct CreatureSpeciesTests {
    /// Switch exhaustiveness already guarantees at compile time that every tool
    /// produces *some* species, so asserting that proves nothing. The property
    /// worth testing is the other direction: a species no tool can reach is a
    /// body that never renders, which the compiler is happy to accept.
    @Test
    func everyToolLandsInTheSixSpeciesAndNoSpeciesIsOrphaned() {
        let reached = Set(AgentTool.allCases.map { CreatureSpecies(tool: $0) })
        #expect(AgentTool.allCases.count == 10)
        #expect(reached.isSubset(of: Set(CreatureSpecies.allCases)))

        let orphans = Set(CreatureSpecies.allCases).subtracting(reached)
        #expect(orphans.isEmpty, "no tool maps to \(orphans.map(\.rawValue).sorted())")
    }

    @Test
    func claudeForksShareTheClaudeBody() {
        #expect(CreatureSpecies(tool: .claudeCode) == .claude)
        #expect(CreatureSpecies(tool: .qoder) == .claude)
        #expect(CreatureSpecies(tool: .qwenCode) == .claude)
        #expect(CreatureSpecies(tool: .factory) == .claude)
        #expect(CreatureSpecies(tool: .codebuddy) == .claude)
    }

    @Test
    func distinctAgentsKeepDistinctSpecies() {
        #expect(CreatureSpecies(tool: .codex) == .codex)
        #expect(CreatureSpecies(tool: .cursor) == .cursor)
        #expect(CreatureSpecies(tool: .geminiCLI) == .gemini)
        #expect(CreatureSpecies(tool: .kimiCLI) == .kimi)
        #expect(CreatureSpecies(tool: .openCode) == .openCode)
    }

    @Test
    func thereAreExactlySixSpecies() {
        #expect(CreatureSpecies.allCases.count == 6)
    }
}
