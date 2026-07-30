import Foundation
import Testing
@testable import OpenIslandCore

struct SessionLogTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func record(
        _ id: String,
        tool: AgentTool = .claudeCode,
        endedOffset: TimeInterval = 60,
        interrupted: Bool = false,
        stalls: Int = 0,
        latency: Double? = nil
    ) -> SessionLogRecord {
        SessionLogRecord(
            sessionID: id,
            tool: tool,
            workspace: "repo",
            startedAt: t0,
            endedAt: t0.addingTimeInterval(endedOffset),
            wasInterrupted: interrupted,
            stallCount: stalls,
            meanGateLatency: latency
        )
    }

    private func makeStore() -> SessionLogStore {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("geode-log-\(UUID().uuidString)", isDirectory: true)
        return SessionLogStore(fileURL: dir.appendingPathComponent("session-log.jsonl"))
    }

    // MARK: - Round trip

    @Test
    func appendThenLoadReturnsEqualRecords() {
        let store = makeStore()
        let original = record("s1", stalls: 2, latency: 12.5)
        #expect(store.append(original))
        #expect(store.load() == [original])
    }

    @Test
    func loadOnMissingFileReturnsEmptyRatherThanFailing() {
        #expect(makeStore().load().isEmpty)
    }

    @Test
    func appendsAccumulateAcrossCalls() {
        let store = makeStore()
        store.append(record("s1", endedOffset: 60))
        store.append(record("s2", endedOffset: 120))
        store.append(record("s3", endedOffset: 180))
        #expect(store.load().count == 3)
    }

    // MARK: - Dedupe

    /// Claude Code emits a turn-level Stop and a separate SessionEnd, so the same
    /// session legitimately completes twice. Counting both would inflate every
    /// downstream figure.
    @Test
    func duplicateSessionIDsCollapseKeepingTheLatestEnd() {
        let store = makeStore()
        store.append(record("dupe", endedOffset: 60))
        store.append(record("dupe", endedOffset: 300))

        let loaded = store.load()
        #expect(loaded.count == 1)
        #expect(loaded.first?.endedAt == t0.addingTimeInterval(300))
    }

    @Test
    func anEarlierDuplicateArrivingLastDoesNotOverwriteTheLaterOne() {
        let store = makeStore()
        store.append(record("dupe", endedOffset: 300))
        store.append(record("dupe", endedOffset: 60))
        #expect(store.load().first?.endedAt == t0.addingTimeInterval(300))
    }

    @Test
    func deduplicatedSortsOldestFirst() {
        let deduped = SessionLogStore.deduplicated([
            record("c", endedOffset: 300),
            record("a", endedOffset: 60),
            record("b", endedOffset: 120),
        ])
        #expect(deduped.map(\.sessionID) == ["a", "b", "c"])
    }

    // MARK: - Corruption tolerance

    /// One bad write must not be able to destroy a year of history.
    @Test
    func malformedLinesAreSkippedAndTheRestStillLoad() throws {
        let store = makeStore()
        store.append(record("good1", endedOffset: 60))

        let handle = try FileHandle(forWritingTo: store.fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("this is not json\n".utf8))
        try handle.close()

        store.append(record("good2", endedOffset: 120))

        let loaded = store.load()
        #expect(loaded.count == 2)
        #expect(loaded.map(\.sessionID).sorted() == ["good1", "good2"])
    }

    @Test
    func blankLinesAreIgnored() throws {
        let store = makeStore()
        store.append(record("s1"))
        let handle = try FileHandle(forWritingTo: store.fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\n\n\n".utf8))
        try handle.close()
        #expect(store.load().count == 1)
    }

    // MARK: - Record semantics

    /// A clock adjustment mid-session must not produce negative runtime that
    /// silently subtracts from a total.
    @Test
    func durationClampsAtZeroWhenTheClockMovedBackwards() {
        let backwards = SessionLogRecord(
            sessionID: "weird",
            tool: .codex,
            startedAt: t0.addingTimeInterval(100),
            endedAt: t0,
            wasInterrupted: false,
            stallCount: 0
        )
        #expect(backwards.duration == 0)
    }

    @Test
    func cleanFinishIsTheInverseOfInterrupted() {
        #expect(record("a", interrupted: false).isCleanFinish)
        #expect(!record("b", interrupted: true).isCleanFinish)
    }

    @Test
    func knownSessionIDsReflectsWhatIsStored() {
        let store = makeStore()
        store.append(record("a"))
        store.append(record("b", tool: .codex))
        #expect(store.knownSessionIDs() == ["a", "b"])
    }
}
