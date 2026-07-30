import Foundation
import Testing
@testable import OpenIslandCore

struct SessionLogBackfillTests {
    private func makeRoot() -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("geode-backfill-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// Built per call rather than shared: `ISO8601DateFormatter` is not Sendable,
    /// and Swift Testing runs these concurrently.
    private func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    @discardableResult
    private func writeTranscript(
        root: URL,
        project: String = "-Users-someone-my-repo",
        sessionID: String,
        lines: Int,
        startedAt: String = "2026-07-30T10:00:00.000Z",
        endedAt: Date
    ) -> URL {
        let dir = root.appendingPathComponent(project, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("\(sessionID).jsonl")

        var body = "{\"timestamp\":\"\(startedAt)\",\"type\":\"user\"}\n"
        for index in 1..<max(1, lines - 1) {
            body += "{\"type\":\"assistant\",\"n\":\(index)}\n"
        }
        // Duration comes from the last in-file timestamp, never file mtime.
        body += "{\"timestamp\":\"\(isoString(endedAt))\",\"type\":\"assistant\"}\n"
        try? body.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private let start = ISO8601DateFormatter().date(from: "2026-07-30T10:00:00Z")!

    @Test
    func derivesARecordFromATranscript() {
        let root = makeRoot()
        writeTranscript(root: root, sessionID: "abc-123", lines: 10,
                        endedAt: start.addingTimeInterval(600))

        let records = SessionLogBackfill(rootURL: root).derivedRecords(existingSessionIDs: [])
        #expect(records.count == 1)
        #expect(records.first?.sessionID == "abc-123")
        #expect(records.first?.tool == .claudeCode)
        #expect(records.first?.workspace == "repo")
        #expect(records.first?.duration == 600)
    }

    /// Inference cannot tell a clean finish from an interrupt, and cannot know
    /// how fast gates were answered. It must claim neither.
    @Test
    func derivedRecordsNeverClaimInterruptsOrLatencies() {
        let root = makeRoot()
        writeTranscript(root: root, sessionID: "s1", lines: 10,
                        endedAt: start.addingTimeInterval(600))
        let record = SessionLogBackfill(rootURL: root).derivedRecords(existingSessionIDs: []).first
        #expect(record?.wasInterrupted == false)
        #expect(record?.meanGateLatency == nil)
        #expect(record?.stallCount == 0)
    }

    /// Running back-fill on every launch must not duplicate history, and a
    /// record from real events must always win over one inferred from a file.
    @Test
    func alreadyKnownSessionsAreSkipped() {
        let root = makeRoot()
        writeTranscript(root: root, sessionID: "known", lines: 10,
                        endedAt: start.addingTimeInterval(600))
        let records = SessionLogBackfill(rootURL: root)
            .derivedRecords(existingSessionIDs: ["known"])
        #expect(records.isEmpty)
    }

    @Test
    func tinyTranscriptsAreSkippedAsAbortedStarts() {
        let root = makeRoot()
        writeTranscript(root: root, sessionID: "stub", lines: 2,
                        endedAt: start.addingTimeInterval(600))
        #expect(SessionLogBackfill(rootURL: root).derivedRecords(existingSessionIDs: []).isEmpty)
    }

    @Test
    func veryShortSessionsAreSkipped() {
        let root = makeRoot()
        writeTranscript(root: root, sessionID: "blink", lines: 10,
                        endedAt: start.addingTimeInterval(5))
        #expect(SessionLogBackfill(rootURL: root).derivedRecords(existingSessionIDs: []).isEmpty)
    }

    /// Subagent transcripts are not sessions the human ran, so counting them
    /// would inflate every figure with work the user never supervised.
    @Test
    func subagentTranscriptsAreExcluded() {
        let root = makeRoot()
        writeTranscript(root: root, project: "-Users-someone-repo/subagents",
                        sessionID: "sub-1", lines: 10,
                        endedAt: start.addingTimeInterval(600))
        #expect(SessionLogBackfill(rootURL: root).derivedRecords(existingSessionIDs: []).isEmpty)
    }

    /// A resumed session appended to across days has a first-to-last span of
    /// wall-clock calendar time, not agent runtime. Real data produced a 104-hour
    /// "session"; counting that as runtime would make the headline meaningless.
    @Test
    func multiDaySpansAreExcludedRatherThanClamped() {
        let root = makeRoot()
        writeTranscript(root: root, sessionID: "resumed", lines: 10,
                        endedAt: start.addingTimeInterval(104 * 3600))
        #expect(SessionLogBackfill(rootURL: root).derivedRecords(existingSessionIDs: []).isEmpty)
    }

    @Test
    func aSessionJustUnderTheDurationCapIsKept() {
        let root = makeRoot()
        writeTranscript(root: root, sessionID: "long-but-plausible", lines: 10,
                        endedAt: start.addingTimeInterval(11 * 3600))
        #expect(SessionLogBackfill(rootURL: root).derivedRecords(existingSessionIDs: []).count == 1)
    }

    @Test
    func lastTimestampIsUsedForTheEndNotFileModificationTime() {
        let root = makeRoot()
        let url = writeTranscript(root: root, sessionID: "mtime-lies", lines: 10,
                                  endedAt: start.addingTimeInterval(600))
        // Push mtime years into the future; the derived duration must ignore it.
        try? FileManager.default.setAttributes(
            [.modificationDate: start.addingTimeInterval(400 * 86_400)], ofItemAtPath: url.path
        )
        let record = SessionLogBackfill(rootURL: root).derivedRecords(existingSessionIDs: []).first
        #expect(record?.duration == 600)
    }

    @Test
    func aMissingRootYieldsNothingRatherThanFailing() {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("definitely-not-here-\(UUID().uuidString)")
        #expect(SessionLogBackfill(rootURL: missing).derivedRecords(existingSessionIDs: []).isEmpty)
    }

    @Test
    func transcriptsWithoutAParsableTimestampAreSkipped() {
        let root = makeRoot()
        let dir = root.appendingPathComponent("-Users-someone-repo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("no-time.jsonl")
        try? "{\"a\":1}\n{\"b\":2}\n{\"c\":3}\n{\"d\":4}\n".write(
            to: fileURL, atomically: true, encoding: .utf8
        )
        #expect(SessionLogBackfill(rootURL: root).derivedRecords(existingSessionIDs: []).isEmpty)
    }

    @Test
    func workspaceNameTakesTheTrailingPathComponent() {
        let url = URL(fileURLWithPath: "/x/-Users-nambouchara-speed2-open-vibe-island/s.jsonl")
        #expect(SessionLogBackfill.workspaceName(from: url) == "island")
    }

    @Test
    func firstTimestampAcceptsFractionalAndPlainISO8601() {
        let fractional: [Substring] = ["{\"timestamp\":\"2026-07-30T10:00:00.123Z\"}"]
        let plain: [Substring] = ["{\"timestamp\":\"2026-07-30T10:00:00Z\"}"]
        #expect(SessionLogBackfill.firstTimestamp(in: fractional) != nil)
        #expect(SessionLogBackfill.firstTimestamp(in: plain) != nil)
    }
}
