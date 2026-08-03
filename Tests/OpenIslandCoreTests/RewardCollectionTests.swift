import Foundation
import Testing
@testable import OpenIslandCore

struct RewardCollectionTests {
    private static let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func record(
        _ id: String,
        interrupted: Bool = false,
        stalls: Int = 0,
        mean: Double? = nil,
        worst: Double? = nil,
        inferred: Bool? = nil,
        minutes: Double = 5,
        startOffset: TimeInterval = 0
    ) -> SessionLogRecord {
        SessionLogRecord(
            sessionID: id,
            tool: .claudeCode,
            workspace: "repo",
            startedAt: Self.epoch.addingTimeInterval(startOffset),
            endedAt: Self.epoch.addingTimeInterval(startOffset + minutes * 60),
            wasInterrupted: interrupted,
            stallCount: stalls,
            meanGateLatency: mean,
            worstGateLatency: worst,
            isInferred: inferred
        )
    }

    private func makeStore() -> SessionLogStore {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("reward-collection-\(UUID().uuidString)", isDirectory: true)
        return SessionLogStore(fileURL: dir.appendingPathComponent("session-log.jsonl"))
    }

    // MARK: - Earning

    @Test
    func aCleanCompletionContributesItsObjectAndAnInterruptContributesScrap() throws {
        let collection = RewardCollection(records: [
            record("clean", stalls: 1, mean: 2, worst: 2, minutes: 45),
            record("cut", interrupted: true, minutes: 45),
        ])

        let earned = try #require(collection.find(sessionID: "clean"))
        #expect(earned.rarity == .three)
        #expect(RewardObject.pool(for: .three).contains(earned.object))

        let lost = try #require(collection.find(sessionID: "cut"))
        #expect(lost.object == .scrap)
        #expect(lost.rarity == nil)
    }

    /// The projection must agree with the model it projects, or the collection
    /// and the creature holding the object would show different things for the
    /// same session.
    @Test
    func everyFindMatchesTheObjectTheModelYieldsForThatRecord() {
        let records = (0..<25).map { record("s\($0)", stalls: 1, mean: 2, worst: 2, minutes: 45) }
        let collection = RewardCollection(records: records)
        for source in records {
            #expect(collection.find(sessionID: source.sessionID)?.object
                == RewardObject.yield(for: source))
        }
    }

    // MARK: - Persistence

    /// Surviving a relaunch is not something the collection implements — it is a
    /// property of the log it reads. A second store over the same file is the
    /// next launch.
    @Test
    func collectedObjectsSurviveARelaunchThroughTheExistingLog() {
        let store = makeStore()
        store.append(record("kept", stalls: 1, mean: 2, worst: 2, minutes: 45))
        store.append(record("cut", interrupted: true, startOffset: 600))
        let before = RewardCollection(records: store.load())

        let relaunched = SessionLogStore(fileURL: store.fileURL)
        #expect(RewardCollection(records: relaunched.load()) == before)
        #expect(before.finds.count == 2)
        #expect(before.find(sessionID: "cut")?.object == .scrap)
    }

    // MARK: - Back-filled history

    /// History derived from transcripts is rated, not skipped — but it is rated
    /// on what inference can actually support. The island never saw these
    /// sessions, so it cannot testify to stewardship, only to completion.
    @Test
    func backFilledHistoryIsRatedRatherThanSkipped() throws {
        let collection = RewardCollection(records: [record("old", inferred: true, minutes: 240)])
        let find = try #require(collection.find(sessionID: "old"))
        #expect(find.rarity == .one)
        #expect(RewardObject.pool(for: .one).contains(find.object))
    }

    // MARK: - No double award

    /// Structural, not defended: the projection is keyed by session ID, so a
    /// session reconciled, re-appended or back-filled twice cannot contribute
    /// two objects.
    @Test
    func aSessionPresentTwiceIsAwardedOnce() {
        let collection = RewardCollection(records: [
            record("dupe", minutes: 5),
            record("dupe", minutes: 9),
        ])
        #expect(collection.finds.count == 1)
        #expect(collection.tally.values.reduce(0, +) == 1)
    }

    /// Claude Code emits a turn-level Stop and a separate SessionEnd, so the same
    /// session legitimately reaches the log twice.
    @Test
    func aSessionAppendedTwiceToTheLogStillYieldsOneObject() {
        let store = makeStore()
        store.append(record("dupe", minutes: 45, startOffset: 0))
        store.append(record("dupe", minutes: 45, startOffset: 600))
        #expect(RewardCollection(records: store.load()).finds.count == 1)
    }

    // MARK: - Reading the whole collection

    @Test
    func findsReadOldestFirst() {
        let collection = RewardCollection(records: [
            record("c", startOffset: 3_000),
            record("a", startOffset: 0),
            record("b", startOffset: 1_500),
        ])
        #expect(collection.finds.map(\.sessionID) == ["a", "b", "c"])
        // A find is dated by when the session ended, which is what orders them.
        #expect(collection.finds.first?.foundAt == Self.epoch.addingTimeInterval(300))
    }

    @Test
    func theTallyAccountsForEveryFind() {
        let records = (0..<20).map {
            record("s\($0)", stalls: 1, mean: 2, worst: 2, minutes: 45, startOffset: Double($0) * 60)
        }
        let collection = RewardCollection(records: records)
        #expect(collection.tally.values.reduce(0, +) == 20)
        #expect(Set(collection.tally.keys).isSubset(of: Set(RewardObject.pool(for: .three))))
    }

    @Test
    func anEmptyLogCollectsNothing() {
        let collection = RewardCollection(records: [])
        #expect(collection.finds.isEmpty)
        #expect(collection.tally.isEmpty)
        #expect(collection.find(sessionID: "anything") == nil)
    }
}
