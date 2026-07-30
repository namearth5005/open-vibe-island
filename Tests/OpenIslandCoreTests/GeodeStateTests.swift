import Foundation
import Testing
@testable import OpenIslandCore

struct GeodeStateTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func started(
        _ id: String,
        tool: AgentTool = .claudeCode,
        phase: SessionPhase = .running,
        at: Date
    ) -> AgentEvent {
        .sessionStarted(
            SessionStarted(
                sessionID: id,
                title: "Session \(id)",
                tool: tool,
                initialPhase: phase,
                summary: "working",
                timestamp: at
            )
        )
    }

    private func phaseChange(_ id: String, _ phase: SessionPhase, at: Date) -> AgentEvent {
        .activityUpdated(
            SessionActivityUpdated(
                sessionID: id,
                summary: "\(phase)",
                phase: phase,
                timestamp: at
            )
        )
    }

    private func completed(_ id: String, at: Date, interrupt: Bool = false) -> AgentEvent {
        .sessionCompleted(
            SessionCompleted(
                sessionID: id,
                summary: "done",
                timestamp: at,
                isInterrupt: interrupt ? true : nil
            )
        )
    }

    private func resolved(_ id: String, at: Date) -> AgentEvent {
        .actionableStateResolved(
            ActionableStateResolved(sessionID: id, summary: "resolved", timestamp: at)
        )
    }

    // MARK: - Seeding

    @Test
    func sessionStartedSeedsAShard() {
        var state = GeodeState()
        state.apply(started("s1", at: t0))
        let shard = state.shard(id: "s1")
        #expect(shard != nil)
        #expect(shard?.isFrozen == false)
        #expect(shard?.isFractured == false)
        #expect(shard?.isSet == false)
        #expect(shard?.stage == 0)
    }

    /// A session discovered while already blocked must start frozen, or the pill
    /// would show it growing while it actually waits on the human.
    @Test
    func sessionStartedWhileBlockedBeginsFrozen() {
        var state = GeodeState()
        state.apply(started("s1", phase: .waitingForApproval, at: t0))
        #expect(state.shard(id: "s1")?.isFrozen == true)
        #expect(state.shard(id: "s1")?.stallCount == 1)
    }

    @Test
    func eventsForUnknownSessionsAreIgnored() {
        var state = GeodeState()
        state.apply(completed("never-started", at: t0))
        state.apply(phaseChange("never-started", .waitingForApproval, at: t0))
        #expect(state.shard(id: "never-started") == nil)
    }

    // MARK: - Growth

    @Test
    func stageGrowsWithElapsedTime() {
        var state = GeodeState()
        state.apply(started("s1", at: t0))
        state.advance(to: t0.addingTimeInterval(30))
        #expect(state.shard(id: "s1")?.stage == 1)
        state.advance(to: t0.addingTimeInterval(1_890))
        #expect(state.shard(id: "s1")?.stage == 6)
    }

    @Test
    func stallFreezesGrowthAndCountsTheStall() {
        var state = GeodeState()
        state.apply(started("s1", at: t0))
        state.apply(phaseChange("s1", .waitingForApproval, at: t0.addingTimeInterval(10)))
        #expect(state.shard(id: "s1")?.isFrozen == true)
        #expect(state.shard(id: "s1")?.stallCount == 1)

        state.advance(to: t0.addingTimeInterval(10))
        let frozenStage = state.shard(id: "s1")?.stage
        state.advance(to: t0.addingTimeInterval(1_890))
        #expect(state.shard(id: "s1")?.stage == frozenStage)
    }

    @Test
    func resumingUnfreezesAndGrowthContinuesMinusFrozenTime() {
        var state = GeodeState()
        state.apply(started("s1", at: t0))
        state.apply(phaseChange("s1", .waitingForApproval, at: t0.addingTimeInterval(10)))
        state.apply(phaseChange("s1", .running, at: t0.addingTimeInterval(70)))
        #expect(state.shard(id: "s1")?.isFrozen == false)
        // 60s frozen, so at wall-clock 90s only 30s of growth has accrued.
        state.advance(to: t0.addingTimeInterval(90))
        #expect(state.shard(id: "s1")?.stage == 1)
    }

    @Test
    func actionableStateResolvedAlsoThaws() {
        var state = GeodeState()
        state.apply(started("s1", at: t0))
        state.apply(.permissionRequested(
            PermissionRequested(
                sessionID: "s1",
                request: PermissionRequest(title: "Approve", summary: "Run tool", affectedPath: "/tmp"),
                timestamp: t0.addingTimeInterval(10)
            )
        ))
        #expect(state.shard(id: "s1")?.isFrozen == true)
        state.apply(resolved("s1", at: t0.addingTimeInterval(40)))
        #expect(state.shard(id: "s1")?.isFrozen == false)
    }

    /// Repeated stall events for an already-stalled session must not double-count,
    /// because both a hook and a transcript watcher can report the same block.
    @Test
    func repeatedStallEventsDoNotDoubleCount() {
        var state = GeodeState()
        state.apply(started("s1", at: t0))
        state.apply(phaseChange("s1", .waitingForApproval, at: t0.addingTimeInterval(10)))
        state.apply(phaseChange("s1", .waitingForAnswer, at: t0.addingTimeInterval(12)))
        #expect(state.shard(id: "s1")?.stallCount == 1)
    }

    // MARK: - Completion

    @Test
    func cleanCompletionSetsTheShardUnfractured() {
        var state = GeodeState()
        state.apply(started("s1", at: t0))
        state.apply(completed("s1", at: t0.addingTimeInterval(120)))
        #expect(state.shard(id: "s1")?.isSet == true)
        #expect(state.shard(id: "s1")?.isFractured == false)
    }

    @Test
    func interruptedCompletionFractures() {
        var state = GeodeState()
        state.apply(started("s1", at: t0))
        state.apply(completed("s1", at: t0.addingTimeInterval(120), interrupt: true))
        #expect(state.shard(id: "s1")?.isSet == true)
        #expect(state.shard(id: "s1")?.isFractured == true)
    }

    @Test
    func aSetShardStopsGrowing() {
        var state = GeodeState()
        state.apply(started("s1", at: t0))
        state.apply(completed("s1", at: t0.addingTimeInterval(120)))
        let finalStage = state.shard(id: "s1")?.stage
        state.advance(to: t0.addingTimeInterval(100_000))
        #expect(state.shard(id: "s1")?.stage == finalStage)
    }

    // MARK: - Display selection

    /// The freeze IS the notification, so a stalled session must win the pill even
    /// when another session is running and changed more recently.
    @Test
    func displayedPrefersAStalledSessionOverARunningOne() {
        var state = GeodeState()
        state.apply(started("stuck", tool: .codex, at: t0))
        state.apply(phaseChange("stuck", .waitingForApproval, at: t0.addingTimeInterval(1)))
        state.apply(started("running", at: t0.addingTimeInterval(5)))
        #expect(state.displayed?.sessionID == "stuck")
    }

    @Test
    func displayedPicksMostRecentlyChangedRunningSessionOtherwise() {
        var state = GeodeState()
        state.apply(started("old", at: t0))
        state.apply(started("new", tool: .codex, at: t0.addingTimeInterval(5)))
        #expect(state.displayed?.sessionID == "new")
    }

    @Test
    func displayedIsNilWhenNothingIsLive() {
        var state = GeodeState()
        state.apply(started("s1", at: t0))
        state.apply(completed("s1", at: t0.addingTimeInterval(10)))
        #expect(state.displayed == nil)
    }

    @Test
    func displayedIsNilOnEmptyState() {
        #expect(GeodeState().displayed == nil)
    }

    // MARK: - Determinism and lifecycle

    @Test
    func geometryIsStableAcrossIdenticalEventStreams() {
        var a = GeodeState()
        var b = GeodeState()
        a.apply(started("same-id", at: t0))
        b.apply(started("same-id", at: t0))
        #expect(a.shard(id: "same-id")?.form == b.shard(id: "same-id")?.form)
    }

    @Test
    func pruneDropsShardsForSessionsNoLongerTracked() {
        var state = GeodeState()
        state.apply(started("keep", at: t0))
        state.apply(started("drop", tool: .codex, at: t0))
        state.prune(keeping: ["keep"])
        #expect(state.shard(id: "keep") != nil)
        #expect(state.shard(id: "drop") == nil)
    }
}
