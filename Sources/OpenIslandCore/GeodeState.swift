import Foundation

/// One session's shard. Geometry is derived from the session ID seed and the
/// current stage — never persisted, always recomputable.
public struct GeodeShard: Equatable, Sendable {
    public let sessionID: String
    public let tool: AgentTool
    public let startedAt: Date
    /// Wall-clock seconds already spent frozen. Excluded from growth.
    public var frozenSeconds: TimeInterval
    /// Set while the session is blocked on the human; nil while it runs.
    public var frozenSince: Date?
    public var stallCount: Int
    public var stage: Int
    public var isSet: Bool
    public var isFractured: Bool
    /// Timestamp of the last event that touched this shard. Breaks ties when
    /// choosing which shard the pill displays.
    public var updatedAt: Date

    public var isFrozen: Bool {
        frozenSince != nil
    }

    public var form: ShardForm {
        ShardForm.make(seed: ShardSeed.value(for: sessionID), stage: stage)
    }

    /// Mean seconds the human took to answer this session's gates.
    ///
    /// Frozen time is, by construction, exactly the time spent waiting on the
    /// human — so total frozen seconds over stall count is the mean answer
    /// latency, with no extra bookkeeping. `nil` when there were no gates, which
    /// is meaningfully different from zero.
    public var meanGateLatency: Double? {
        guard stallCount > 0 else { return nil }
        return frozenSeconds / Double(stallCount)
    }
}

/// Pure reducer over `AgentEvent`, mirroring the project rule that session
/// mutation lives in exactly one place. Nothing outside this type may mutate a
/// shard, and no shard geometry is ever stored — only the facts it derives from.
public struct GeodeState: Equatable, Sendable {
    private var shardsBySessionID: [String: GeodeShard] = [:]

    public init() {}

    public func shard(id: String) -> GeodeShard? {
        shardsBySessionID[id]
    }

    /// How long a finished shard stays on screen before the pill goes quiet.
    ///
    /// Without this the reward for finishing work is a sound and then nothing —
    /// the shard vanishes the instant it is earned. Lingering leaves a visible
    /// trace of the thing you just completed.
    public static let lingerWindow: TimeInterval = 45

    /// The shard the closed pill should render, or nil when nothing is live and
    /// nothing finished recently.
    ///
    /// Priority: stalled beats running beats recently-finished. The freeze is the
    /// notification channel, so it must never be hidden behind a session that
    /// merely started later.
    public func displayed(at now: Date) -> GeodeShard? {
        let live = shardsBySessionID.values.filter { !$0.isSet }
        let stalled = live.filter(\.isFrozen)

        if let shard = mostRecent(stalled) { return shard }
        if let shard = mostRecent(live) { return shard }

        return mostRecent(
            shardsBySessionID.values.filter {
                $0.isSet && now.timeIntervalSince($0.updatedAt) <= Self.lingerWindow
            }
        )
    }

    /// Shards finished cleanly on the same local day as `now`. Drives the small
    /// tally beside the live shard — the first thing in this feature that
    /// accumulates rather than evaporating.
    public func completedCount(on now: Date, calendar: Calendar = .current) -> Int {
        shardsBySessionID.values.filter {
            $0.isSet && !$0.isFractured && calendar.isDate($0.updatedAt, inSameDayAs: now)
        }.count
    }

    private func mostRecent(_ shards: some Collection<GeodeShard>) -> GeodeShard? {
        shards.max { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.sessionID < rhs.sessionID
            }
            return lhs.updatedAt < rhs.updatedAt
        }
    }

    public mutating func apply(_ event: AgentEvent) {
        switch event {
        case let .sessionStarted(payload):
            shardsBySessionID[payload.sessionID] = GeodeShard(
                sessionID: payload.sessionID,
                tool: payload.tool,
                startedAt: payload.timestamp,
                frozenSeconds: 0,
                frozenSince: payload.initialPhase.requiresAttention ? payload.timestamp : nil,
                stallCount: payload.initialPhase.requiresAttention ? 1 : 0,
                stage: 0,
                isSet: false,
                isFractured: false,
                updatedAt: payload.timestamp
            )

        case let .activityUpdated(payload):
            guard var shard = shardsBySessionID[payload.sessionID] else { return }
            if payload.phase.requiresAttention {
                if shard.frozenSince == nil {
                    shard.frozenSince = payload.timestamp
                    shard.stallCount += 1
                }
            } else {
                shard.frozenSeconds += frozenElapsed(of: shard, upTo: payload.timestamp)
                shard.frozenSince = nil
            }
            shard.updatedAt = payload.timestamp
            shardsBySessionID[payload.sessionID] = shard

        case let .permissionRequested(payload):
            freeze(payload.sessionID, at: payload.timestamp)

        case let .questionAsked(payload):
            freeze(payload.sessionID, at: payload.timestamp)

        case let .actionableStateResolved(payload):
            thaw(payload.sessionID, at: payload.timestamp)

        case let .sessionCompleted(payload):
            guard var shard = shardsBySessionID[payload.sessionID] else { return }
            shard.frozenSeconds += frozenElapsed(of: shard, upTo: payload.timestamp)
            shard.frozenSince = nil
            shard.stage = ShardForm.stage(
                forDuration: growthSeconds(of: shard, upTo: payload.timestamp)
            )
            shard.isSet = true
            shard.isFractured = payload.isInterrupt == true
            shard.updatedAt = payload.timestamp
            shardsBySessionID[payload.sessionID] = shard

        case .jumpTargetUpdated,
             .sessionMetadataUpdated,
             .claudeSessionMetadataUpdated,
             .geminiSessionMetadataUpdated,
             .openCodeSessionMetadataUpdated,
             .cursorSessionMetadataUpdated:
            break
        }
    }

    /// Recompute growth stages. Driven by a timer in the app layer, because
    /// elapsed time is not an event.
    public mutating func advance(to now: Date) {
        for (id, shard) in shardsBySessionID where !shard.isSet {
            var updated = shard
            updated.stage = ShardForm.stage(forDuration: growthSeconds(of: shard, upTo: now))
            shardsBySessionID[id] = updated
        }
    }

    /// Drop shards for sessions no longer tracked, so state cannot grow unbounded.
    public mutating func prune(keeping liveSessionIDs: Set<String>) {
        shardsBySessionID = shardsBySessionID.filter { liveSessionIDs.contains($0.key) }
    }

    /// Back-fill shards for sessions that never produced a `sessionStarted`
    /// event, and drop shards whose session has gone.
    ///
    /// Sessions can reach `SessionState` without passing through `apply(_:)` —
    /// startup discovery, debug snapshots, and direct assignment all do this.
    /// Without back-filling, the shard slot renders empty while the agents grid
    /// shows tiles, which reads as a broken feature. Existing shards are never
    /// overwritten, so event-derived state always wins over inference.
    public mutating func reconcile(with sessions: [AgentSession], now: Date) {
        for session in sessions where shardsBySessionID[session.id] == nil {
            let isDone = session.phase == .completed
            let needsAttention = session.phase.requiresAttention
            let endpoint = isDone ? session.updatedAt : now
            let elapsed = max(0, endpoint.timeIntervalSince(session.firstSeenAt))

            shardsBySessionID[session.id] = GeodeShard(
                sessionID: session.id,
                tool: session.tool,
                startedAt: session.firstSeenAt,
                frozenSeconds: 0,
                frozenSince: needsAttention ? session.updatedAt : nil,
                stallCount: needsAttention ? 1 : 0,
                stage: ShardForm.stage(forDuration: elapsed),
                isSet: isDone,
                // Inference cannot tell a clean finish from an interrupt, and
                // claiming a fracture that did not happen is worse than missing
                // one, so back-filled shards are never fractured.
                isFractured: false,
                updatedAt: session.updatedAt
            )
        }

        prune(keeping: Set(sessions.map(\.id)))
    }

    private mutating func freeze(_ sessionID: String, at timestamp: Date) {
        guard var shard = shardsBySessionID[sessionID], shard.frozenSince == nil else { return }
        shard.frozenSince = timestamp
        shard.stallCount += 1
        shard.updatedAt = timestamp
        shardsBySessionID[sessionID] = shard
    }

    private mutating func thaw(_ sessionID: String, at timestamp: Date) {
        guard var shard = shardsBySessionID[sessionID] else { return }
        shard.frozenSeconds += frozenElapsed(of: shard, upTo: timestamp)
        shard.frozenSince = nil
        shard.updatedAt = timestamp
        shardsBySessionID[sessionID] = shard
    }

    private func frozenElapsed(of shard: GeodeShard, upTo now: Date) -> TimeInterval {
        guard let since = shard.frozenSince else { return 0 }
        return max(0, now.timeIntervalSince(since))
    }

    /// Elapsed wall clock minus every frozen interval: growth accrues only while
    /// the agent is actually working, never while it waits on the human.
    private func growthSeconds(of shard: GeodeShard, upTo now: Date) -> TimeInterval {
        let wall = max(0, now.timeIntervalSince(shard.startedAt))
        let frozen = shard.frozenSeconds + frozenElapsed(of: shard, upTo: now)
        return max(0, wall - frozen)
    }
}
