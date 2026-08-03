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

    // MARK: - Backward compatibility

    /// There is a real log on disk written by builds that had neither
    /// `worstGateLatency` nor `isInferred`. Pinned as literal text rather than a
    /// round trip, because a round trip only proves this build agrees with
    /// itself — it would still pass if the on-disk format had changed underneath.
    /// The two lines are the exact shapes older builds emitted: one with no gate
    /// data at all, one carrying only the mean.
    @Test
    func recordsWrittenBeforeTheNewFieldsExistedStillLoad() throws {
        let store = makeStore()
        try FileManager.default.createDirectory(
            at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let legacy = """
        {"sessionID":"82094fd0","wasInterrupted":false,"workspace":"reel","stallCount":0,\
        "endedAt":"2026-07-26T13:21:23Z","tool":"claudeCode","startedAt":"2026-07-26T11:21:40Z"}
        {"sessionID":"e085a66d","wasInterrupted":true,"workspace":"repo","stallCount":2,\
        "meanGateLatency":12.5,"endedAt":"2026-07-26T13:17:54Z","tool":"codex",\
        "startedAt":"2026-07-26T12:16:56Z"}

        """
        try legacy.write(to: store.fileURL, atomically: true, encoding: .utf8)

        let loaded = store.load()
        try #require(loaded.count == 2)

        let old = try #require(loaded.first { $0.sessionID == "82094fd0" })
        #expect(old.tool == .claudeCode)
        #expect(old.workspace == "reel")
        #expect(old.stallCount == 0)
        #expect(old.duration == 7_183)
        #expect(old.meanGateLatency == nil)
        #expect(old.worstGateLatency == nil)
        #expect(old.isInferred == nil)

        let gated = try #require(loaded.first { $0.sessionID == "e085a66d" })
        #expect(gated.wasInterrupted == true)
        #expect(gated.meanGateLatency == 12.5)
        #expect(gated.worstGateLatency == nil)
    }

    @Test
    func theNewFieldsSurviveARoundTrip() {
        let store = makeStore()
        var original = record("s1", stalls: 2, latency: 12.5)
        original.worstGateLatency = 41
        original.isInferred = true
        store.append(original)
        #expect(store.load() == [original])
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
