import Foundation
import Testing
@testable import OpenIslandCore

struct AgentFeedTests {
    /// Shapes here are copied from a real Claude Code transcript, not invented.
    private func record(_ json: String) -> Data { Data(json.utf8) }

    @Test
    func parsesProseAsSaid() {
        let feed = ClaudeTranscriptFeedReader.parse(record("""
        {"type":"assistant","uuid":"a1","timestamp":"2026-08-22T09:02:51.000Z","message":{"model":"claude-opus-5","content":[{"type":"text","text":"Fair. Let me look at the transcript."}]}}
        """))
        #expect(feed.entries.count == 1)
        #expect(feed.entries[0].kind == .said("Fair. Let me look at the transcript."))
        #expect(feed.summary.model == "claude-opus-5")
    }

    @Test
    func toolCallsShowTheirMostUsefulArgument() {
        let feed = ClaudeTranscriptFeedReader.parse(record("""
        {"type":"assistant","uuid":"a2","timestamp":"2026-08-22T09:03:00.000Z","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"swift build","description":"Build the package"}},{"type":"tool_use","name":"Read","input":{"file_path":"/Users/x/Sources/App/Thing.swift"}},{"type":"tool_use","name":"WebSearch","input":{"query":"swift timeline schedule"}}]}}
        """))
        #expect(feed.entries.count == 3)
        // Bash prefers the human description over the raw command.
        #expect(feed.entries[0].kind == .ran(tool: "Bash", argument: "Build the package"))
        // Path tools show the basename, never the full path.
        #expect(feed.entries[1].kind == .ran(tool: "Read", argument: "Thing.swift"))
        #expect(feed.entries[2].kind == .ran(tool: "WebSearch", argument: "swift timeline schedule"))
    }

    /// The diff comes out of the transcript rather than out of git, so it counts
    /// only what this agent changed.
    @Test
    func editsYieldLineCounts() {
        let feed = ClaudeTranscriptFeedReader.parse(record("""
        {"type":"assistant","uuid":"a3","timestamp":"2026-08-22T09:04:00.000Z","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/tmp/A.swift","old_string":"one\\ntwo","new_string":"one\\ntwo\\nthree\\nfour"}}]}}
        """))
        #expect(feed.entries[0].kind == .edited(file: "A.swift", added: 4, removed: 2))
        #expect(feed.summary.linesAdded == 4)
        #expect(feed.summary.linesRemoved == 2)
        #expect(feed.summary.filesTouched == 1)
    }

    @Test
    func writeCountsAsAllAdded() {
        let feed = ClaudeTranscriptFeedReader.parse(record("""
        {"type":"assistant","uuid":"a4","timestamp":"2026-08-22T09:05:00.000Z","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/tmp/New.swift","content":"a\\nb\\nc"}}]}}
        """))
        #expect(feed.entries[0].kind == .edited(file: "New.swift", added: 3, removed: 0))
    }

    @Test
    func usageAccumulatesAcrossTurns() {
        let feed = ClaudeTranscriptFeedReader.parse(record("""
        {"type":"assistant","uuid":"a5","timestamp":"2026-08-22T09:06:00.000Z","message":{"content":[{"type":"text","text":"one"}],"usage":{"output_tokens":100,"cache_read_input_tokens":900}}}
        {"type":"assistant","uuid":"a6","timestamp":"2026-08-22T09:06:30.000Z","message":{"content":[{"type":"text","text":"two"}],"usage":{"output_tokens":40,"cache_read_input_tokens":1200}}}
        """))
        #expect(feed.summary.outputTokens == 140)
        // Cache reads are a running total in the source, so take the latest.
        #expect(feed.summary.cacheReadTokens == 1200)
    }

    @Test
    func subagentRecordsAreMarked() {
        let feed = ClaudeTranscriptFeedReader.parse(record("""
        {"type":"assistant","uuid":"a7","isSidechain":true,"timestamp":"2026-08-22T09:07:00.000Z","message":{"content":[{"type":"text","text":"from a subagent"}]}}
        """))
        #expect(feed.entries[0].isSidechain)
    }

    /// Non-assistant records make up most of the file and must be ignored.
    @Test
    func ignoresNonAssistantRecords() {
        let feed = ClaudeTranscriptFeedReader.parse(record("""
        {"type":"user","uuid":"u1","message":{"content":"hello"}}
        {"type":"file-history-snapshot","uuid":"f1"}
        {"type":"assistant","uuid":"a8","timestamp":"2026-08-22T09:08:00.000Z","message":{"content":[{"type":"text","text":"only me"}]}}
        """))
        #expect(feed.entries.count == 1)
    }

    /// Reading a tail can start mid-line; a broken leading fragment must not
    /// take the rest of the parse with it.
    @Test
    func survivesATruncatedFirstLine() {
        let feed = ClaudeTranscriptFeedReader.parse(record("""
        ent":[{"type":"text","text":"half a record"}]}}
        {"type":"assistant","uuid":"a9","timestamp":"2026-08-22T09:09:00.000Z","message":{"content":[{"type":"text","text":"intact"}]}}
        """))
        #expect(feed.entries.count == 1)
        #expect(feed.entries[0].kind == .said("intact"))
    }

    @Test
    func emptyTextIsDropped() {
        let feed = ClaudeTranscriptFeedReader.parse(record("""
        {"type":"assistant","uuid":"a10","timestamp":"2026-08-22T09:10:00.000Z","message":{"content":[{"type":"text","text":"   "}]}}
        """))
        #expect(feed.entries.isEmpty)
    }

    @Test
    func limitKeepsTheMostRecentEntries() {
        let lines = (0..<10).map { i in
            "{\"type\":\"assistant\",\"uuid\":\"n\(i)\",\"timestamp\":\"2026-08-22T09:00:0\(i)Z\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"line \(i)\"}]}}"
        }.joined(separator: "\n")
        let feed = ClaudeTranscriptFeedReader.parse(record(lines), limit: 3)
        #expect(feed.entries.count == 3)
        #expect(feed.entries.last?.kind == .said("line 9"))
    }
}
