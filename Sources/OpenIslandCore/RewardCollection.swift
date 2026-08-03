import Foundation

/// One object and the session that left it.
public struct RewardFind: Equatable, Sendable {
    public let sessionID: String
    public let object: RewardObject
    /// `nil` for scrap. An interrupt is the absence of a reward, not its bottom
    /// rung, so it has no stars rather than zero.
    public let rarity: RewardRarity?
    public let foundAt: Date

    init(record: SessionLogRecord) {
        sessionID = record.sessionID
        object = RewardObject.yield(for: record)
        rarity = RewardRarity.rarity(for: record)
        foundAt = record.endedAt
    }
}

/// Everything the session log says has been found.
///
/// A projection, computed on demand and written nowhere. Collection needs no
/// store of its own because it is not state: an object is a pure function of a
/// `SessionLogRecord`, and the log already survives relaunch and is already
/// back-filled from transcripts. Persisting a collected object would fossilise
/// the rating that produced it — the thing `RewardRarity` exists to avoid — and
/// hand the feature a second source of truth to drift from the first.
///
/// Double-awarding is impossible rather than guarded against: the projection is
/// keyed by session ID through the store's own `deduplicated(_:)` rule, so a
/// session reconciled twice, appended twice, or logged live *and* back-filled
/// still contributes exactly one find.
public struct RewardCollection: Equatable, Sendable {
    /// One per finished session, oldest first. Interrupted sessions are present
    /// as scrap: they are part of the record, not part of the reward.
    public let finds: [RewardFind]

    public init(records: [SessionLogRecord]) {
        finds = SessionLogStore.deduplicated(records).map(RewardFind.init(record:))
    }

    /// How many of each object the log accounts for.
    public var tally: [RewardObject: Int] {
        finds.reduce(into: [:]) { counts, find in counts[find.object, default: 0] += 1 }
    }

    public func find(sessionID: String) -> RewardFind? {
        finds.first { $0.sessionID == sessionID }
    }
}
