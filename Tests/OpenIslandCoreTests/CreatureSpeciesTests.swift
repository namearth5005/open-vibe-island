import Testing
@testable import OpenIslandCore

struct CreatureSpeciesTests {
    @Test
    func everyAgentToolMapsToASpecies() {
        for tool in AgentTool.allCases { _ = CreatureSpecies(tool: tool) }
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
