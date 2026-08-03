import Foundation

/// What a creature is doing. Derived from the shard, never stored — same rule
/// the shard itself follows.
public enum CreaturePose: String, CaseIterable, Sendable {
    /// Agent is running. Ambient; should be ignorable.
    case working
    /// Agent is blocked on the human. This is the notification.
    case waiting
    /// Clean completion, reward held overhead, waiting to be collected.
    case holding
    /// Interrupted. Knocked over, object dropped.
    case fallen

    public init(shard: GeodeShard) {
        if shard.isSet {
            self = shard.isFractured ? .fallen : .holding
        } else if shard.isFrozen {
            self = .waiting
        } else {
            self = .working
        }
    }

    /// Whether this pose must be distinguishable from the others inside the
    /// 28x32pt pill lane. `fallen` is exempt: an interrupted session is
    /// deliberately not competing for attention, so it may read as calm.
    public var demandsPillLegibility: Bool { self != .fallen }
}

public extension GeodeState {
    /// The pose a session's creature holds right now.
    ///
    /// Lives here rather than at each call site because the island draws the
    /// same session twice — once as a picture, once as words — and the two must
    /// never disagree about what it is doing.
    ///
    /// A session whose shard has not landed yet reads as calm. The picture may
    /// never invent an attention state it was not told about; a missed wave is
    /// recoverable, a phantom one is not.
    func pose(for sessionID: String) -> CreaturePose {
        shard(id: sessionID).map(CreaturePose.init(shard:)) ?? .working
    }
}
