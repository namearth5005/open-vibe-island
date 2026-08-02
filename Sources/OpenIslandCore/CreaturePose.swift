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
