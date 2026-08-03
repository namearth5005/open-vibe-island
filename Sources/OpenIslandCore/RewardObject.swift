import Foundation

/// What a finished session was worth, in stars.
///
/// Always derived, never stored. Rating is a design opinion and design opinions
/// change; a stored star count would freeze last month's opinion into the log
/// and leave old sessions rated by a rule that no longer exists. Recomputing
/// from the recorded facts means a rule change re-rates the whole history.
public enum RewardRarity: Int, CaseIterable, Sendable {
    case one = 1
    case two = 2
    case three = 3
    /// A shipped release. Unreachable: it needs the git/PR watcher that open
    /// question 1 of the design defers, and nothing in the log records a commit,
    /// a PR or a tag. Declared anyway so the ladder is complete and so the next
    /// person to look knows the tier is unbuilt rather than broken —
    /// `RewardObjectTests.fourStarsIsUnreachableUntilTheGitWatcherExists` holds
    /// that line.
    case four = 4

    /// Answer inside this and the wait is unpenalised. Borrowed from Cat on
    /// Chair's cancel window via the design's "wait timer" section.
    public static let graceWindow: TimeInterval = 30

    /// Half an hour of wall clock. Runtime is the one input a user cannot
    /// cheaply mint — the agent has to actually spend the time.
    public static let longRunDuration: TimeInterval = 30 * 60

    /// The tier a finished session earned, or `nil` when it was interrupted.
    ///
    /// `nil` rather than a zero case: an interrupt is the absence of a reward,
    /// not the bottom rung of one. It yields scrap, and scrap has no stars.
    ///
    /// **This departs from the spec's wording, deliberately.** The spec asks for
    /// "clean, zero stalls, and every gate answered inside the grace window",
    /// but `stallCount` in the log counts *gates*, not abandonments —
    /// `GeodeState` increments it on every `permissionRequested` and
    /// `questionAsked`. Read literally, "zero stalls" therefore means "the agent
    /// never asked", which makes the grace-window clause dead code (no gates, no
    /// latencies) and rates the most attentive long session — six gates, all
    /// answered in seconds — beneath a session nobody watched. That inverts the
    /// design's own argument, which is that the human's contribution is
    /// stewardship. So the two clauses are read as one: a stall *is* a gate left
    /// past the grace window, and zero of them is what ★★ asks for. A session
    /// with no gates satisfies it vacuously, exactly as the spec says it should.
    public static func rarity(for record: SessionLogRecord) -> RewardRarity? {
        guard record.isCleanFinish else { return nil }
        // Inference can support "this session happened and finished", and
        // nothing above it: a back-filled record's clean finish, zero stalls and
        // duration are all assertions the back-fill made because it had to write
        // something, not facts anyone observed. ★ is exactly "any clean
        // completion", so it is the whole of what an unwatched session earns.
        guard record.isInferred != true else { return .one }
        guard answeredWithinGrace(record) else { return .one }
        return record.duration >= longRunDuration ? .three : .two
    }

    /// Whether the human kept up with this session's gates.
    ///
    /// The worst gate decides it outright when it is recorded: one answer past
    /// the window loses the tier however fast the rest were. That is the whole
    /// question ★★ asks, and no summary statistic could answer it — which is why
    /// the maximum is now written alongside the mean.
    ///
    /// Records predating that field fall back to the mean, which is a strictly
    /// generous stand-in: all-inside implies mean-inside, so a session that
    /// genuinely qualified is never denied, but 1s and 59s average to exactly
    /// 30s and pass. They are not re-rated under the exact rule because the fact
    /// it needs was never captured, and a lower threshold would not help — one
    /// slow answer can be dragged under any positive bound by enough fast ones.
    ///
    /// Neither recorded is a pass, not a zero: no gates means nothing was
    /// answered late.
    static func answeredWithinGrace(_ record: SessionLogRecord) -> Bool {
        guard let latency = record.worstGateLatency ?? record.meanGateLatency else { return true }
        return latency <= graceWindow
    }
}

/// The thing a finished session leaves on the island.
///
/// One case per `Resources/World/obj-*.png`, `rawValue` matching the filename
/// after the `obj-` prefix, because the bundle is flat and the enum is the only
/// manifest of what art has to exist.
public enum RewardObject: String, CaseIterable, Sendable {
    case bell
    case bloom
    case book
    case coin
    case feather
    case geode
    case ingot
    case key
    case lantern
    /// Beat 6: what an interrupted session leaves at its station. Not a reward,
    /// and not in any tier's pool.
    case scrap
    case seed
    case shard
    case tool

    /// What this session left behind.
    ///
    /// Tier picks the pool and the session seed picks within it, so the object
    /// is the rating made visible — per the design's clarity rule the picture
    /// carries state, and a lantern can only ever have come from a long clean
    /// run. Picking from all twelve regardless of tier would make the reveal say
    /// nothing.
    public static func yield(for record: SessionLogRecord) -> RewardObject {
        guard let rarity = RewardRarity.rarity(for: record) else { return .scrap }
        let pool = pool(for: rarity)

        // Drawn through `SplitMix64` from the session's `ShardSeed`, the way
        // `ShardForm.make` derives its geometry: same seed, same object, every
        // launch. `hashValue` would reshuffle per process.
        var rng = SplitMix64(state: ShardSeed.value(for: record.sessionID))
        return pool[Int(rng.next() % UInt64(pool.count))]
    }

    /// Four objects per tier. Ordinary finds at ★, things that had to be
    /// answered for at ★★, things that had to be waited out at ★★★.
    static func pool(for rarity: RewardRarity) -> [RewardObject] {
        switch rarity {
        case .one:
            [.coin, .feather, .seed, .shard]
        case .two:
            [.bell, .book, .key, .tool]
        case .three, .four:
            // ★★★★ borrows the ★★★ pool because it is unreachable and has no
            // artwork of its own. Shipping the tier means shipping its objects.
            [.bloom, .geode, .ingot, .lantern]
        }
    }
}
