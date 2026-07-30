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
        #expect(state.displayed(at: t0.addingTimeInterval(600))?.sessionID == "stuck")
    }

    @Test
    func displayedPicksMostRecentlyChangedRunningSessionOtherwise() {
        var state = GeodeState()
        state.apply(started("old", at: t0))
        state.apply(started("new", tool: .codex, at: t0.addingTimeInterval(5)))
        #expect(state.displayed(at: t0.addingTimeInterval(600))?.sessionID == "new")
    }

    @Test
    func displayedIsNilWhenNothingIsLive() {
        var state = GeodeState()
        state.apply(started("s1", at: t0))
        state.apply(completed("s1", at: t0.addingTimeInterval(10)))
        #expect(state.displayed(at: t0.addingTimeInterval(600)) == nil)
    }

    @Test
    func displayedIsNilOnEmptyState() {
        #expect(GeodeState().displayed(at: t0) == nil)
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

    // MARK: - Linger and tally

    /// Finishing work used to leave nothing behind: the shard vanished the moment
    /// it was earned. It now lingers so the reward has a visible trace.
    @Test
    func aFinishedShardLingersBrieflyThenClears() {
        var state = GeodeState()
        state.apply(started("s1", at: t0))
        let finishedAt = t0.addingTimeInterval(120)
        state.apply(completed("s1", at: finishedAt))

        #expect(state.displayed(at: finishedAt.addingTimeInterval(5))?.sessionID == "s1")
        #expect(state.displayed(at: finishedAt.addingTimeInterval(GeodeState.lingerWindow - 1)) != nil)
        #expect(state.displayed(at: finishedAt.addingTimeInterval(GeodeState.lingerWindow + 1)) == nil)
    }

    /// A running session must still outrank a lingering finished one, or the pill
    /// would show stale work while something is actually happening.
    @Test
    func aRunningSessionOutranksALingeringFinishedOne() {
        var state = GeodeState()
        state.apply(started("done", at: t0))
        state.apply(completed("done", at: t0.addingTimeInterval(10)))
        state.apply(started("live", tool: .codex, at: t0.addingTimeInterval(12)))
        #expect(state.displayed(at: t0.addingTimeInterval(20))?.sessionID == "live")
    }

    @Test
    func completedCountTalliesCleanFinishesOnTheSameDay() {
        var state = GeodeState()
        for index in 0..<3 {
            let id = "s\(index)"
            state.apply(started(id, at: t0))
            state.apply(completed(id, at: t0.addingTimeInterval(60)))
        }
        #expect(state.completedCount(on: t0.addingTimeInterval(60)) == 3)
    }

    /// Interrupted work is a record, not an achievement — it must not inflate the
    /// tally, or the number stops meaning "work I finished".
    @Test
    func completedCountExcludesFracturedAndUnfinishedShards() {
        var state = GeodeState()
        state.apply(started("clean", at: t0))
        state.apply(completed("clean", at: t0.addingTimeInterval(60)))
        state.apply(started("broken", tool: .codex, at: t0))
        state.apply(completed("broken", at: t0.addingTimeInterval(60), interrupt: true))
        state.apply(started("running", tool: .cursor, at: t0))
        #expect(state.completedCount(on: t0.addingTimeInterval(60)) == 1)
    }

    @Test
    func completedCountIgnoresOtherDays() {
        var state = GeodeState()
        state.apply(started("yesterday", at: t0))
        state.apply(completed("yesterday", at: t0.addingTimeInterval(60)))
        let nextDay = t0.addingTimeInterval(60 * 60 * 30)
        #expect(state.completedCount(on: nextDay) == 0)
    }

    // MARK: - Reconcile

    private func listSession(
        _ id: String,
        tool: AgentTool = .claudeCode,
        phase: SessionPhase,
        firstSeenAt: Date,
        updatedAt: Date
    ) -> AgentSession {
        var session = AgentSession(
            id: id,
            title: id,
            tool: tool,
            phase: phase,
            summary: "",
            updatedAt: updatedAt,
            firstSeenAt: firstSeenAt
        )
        session.isProcessAlive = true
        return session
    }

    /// Sessions found at startup never emit `sessionStarted`, so without
    /// back-filling the shard slot is empty while the agents grid shows tiles.
    @Test
    func reconcileBackFillsSessionsThatNeverEmittedAStartEvent() {
        var state = GeodeState()
        let session = listSession("discovered", phase: .running,
                                  firstSeenAt: t0, updatedAt: t0.addingTimeInterval(60))
        state.reconcile(with: [session], now: t0.addingTimeInterval(450))
        #expect(state.shard(id: "discovered") != nil)
        #expect(state.displayed(at: t0.addingTimeInterval(600))?.sessionID == "discovered")
        // ~7.5 minutes of elapsed time is growth stage 4.
        #expect(state.shard(id: "discovered")?.stage == 4)
    }

    @Test
    func reconcileMarksCompletedSessionsAsSetSoTheyDoNotDisplay() {
        var state = GeodeState()
        let session = listSession("done", phase: .completed,
                                  firstSeenAt: t0, updatedAt: t0.addingTimeInterval(120))
        state.reconcile(with: [session], now: t0.addingTimeInterval(500))
        #expect(state.shard(id: "done")?.isSet == true)
        #expect(state.displayed(at: t0.addingTimeInterval(600)) == nil)
    }

    @Test
    func reconcileMarksBlockedSessionsAsFrozen() {
        var state = GeodeState()
        let session = listSession("blocked", phase: .waitingForApproval,
                                  firstSeenAt: t0, updatedAt: t0.addingTimeInterval(30))
        state.reconcile(with: [session], now: t0.addingTimeInterval(90))
        #expect(state.shard(id: "blocked")?.isFrozen == true)
    }

    /// Event-derived state is authoritative: a shard built from real events must
    /// never be clobbered by inference from a session snapshot.
    @Test
    func reconcileDoesNotOverwriteShardsBuiltFromEvents() {
        var state = GeodeState()
        state.apply(started("s1", at: t0))
        state.apply(completed("s1", at: t0.addingTimeInterval(60), interrupt: true))
        let session = listSession("s1", phase: .running,
                                  firstSeenAt: t0, updatedAt: t0.addingTimeInterval(60))
        state.reconcile(with: [session], now: t0.addingTimeInterval(500))
        #expect(state.shard(id: "s1")?.isFractured == true)
        #expect(state.shard(id: "s1")?.isSet == true)
    }

    @Test
    func reconcileDropsShardsWhoseSessionDisappeared() {
        var state = GeodeState()
        state.apply(started("gone", at: t0))
        state.reconcile(with: [], now: t0.addingTimeInterval(10))
        #expect(state.shard(id: "gone") == nil)
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
