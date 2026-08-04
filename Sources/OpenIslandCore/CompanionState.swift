import Foundation

/// What the one companion is doing, read off the whole session list at once.
///
/// A separate type from `CreaturePose`, which describes *a session*. This
/// describes *you*: whether anything wants you, whether anything is happening,
/// whether the day's work is done. The two enums look alike and are not — a
/// pose is total over shards, so it can never say "nothing", and `fallen` is a
/// fact about one interrupted session that means nothing in aggregate. Adding
/// `asleep` to `CreaturePose` would break `CreaturePose(shard:)`, which has to
/// map every shard to a case, and would oblige `CreatureSprite` to name a file
/// for a case no shard can produce.
///
/// Declared in precedence order: waving outranks working outranks resting.
/// `asleep` is the empty list, which nothing else can be.
public enum CompanionState: String, CaseIterable, Sendable {
    /// Something is asking you for an answer. The only state that is a
    /// *request*, so it outranks everything else.
    case waving
    /// An agent is running. Ambient; should be ignorable.
    case working
    /// Every session on the list has stopped. The day's work, sitting there.
    case resting
    /// The list is empty.
    case asleep

    /// The one decision the companion makes.
    ///
    /// Reads the shard rather than `SessionPhase`, for the reason
    /// `CreaturePose.isAskingForYou` exists at all: the companion in the panel
    /// and the creature in the pill are meant to be the same individual, and the
    /// pill reads the shard. Two spellings of "a hand is up" is how one of them
    /// ends up waving while the other sits still. In practice they cannot
    /// disagree either — `AppModel` reconciles the shard state against the
    /// session list on every mutation, and both the event path and the back-fill
    /// path derive the freeze from `SessionPhase.requiresAttention`. A session
    /// whose shard has genuinely not landed reads as calm, because a missed wave
    /// is recoverable and a phantom one is not.
    ///
    /// `asleep` is the empty list and nothing else. It is deliberately not "and
    /// nothing recent": the list already decides when a finished session stops
    /// being shown (`completedStaleThreshold`), so a second staleness clock here
    /// could only disagree with the first. Work that finished yesterday and is
    /// still on the list is still yours — the companion rests beside it, and
    /// only sleeps once the list itself is empty. That makes `resting` the
    /// common case, which is the point: it is the state worth looking at.
    public init(sessions: [AgentSession], geode: GeodeState) {
        guard !sessions.isEmpty else {
            self = .asleep
            return
        }

        let poses = sessions.map { geode.pose(for: $0.id) }

        if poses.contains(where: \.isAskingForYou) {
            self = .waving
        } else if poses.contains(.working) {
            self = .working
        } else {
            self = .resting
        }
    }
}
