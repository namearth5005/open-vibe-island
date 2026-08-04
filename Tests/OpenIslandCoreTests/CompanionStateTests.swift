import Foundation
import Testing
@testable import OpenIslandCore

/// What the one companion is doing, given the whole session list.
///
/// The companion does not represent sessions — it reacts to them in aggregate.
/// So every claim here is about the list as a whole, and none of them may
/// depend on which session happens to be first.
struct CompanionStateTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func session(
        _ id: String,
        phase: SessionPhase = .running,
        tool: AgentTool = .claudeCode,
        updatedAt: Date? = nil
    ) -> AgentSession {
        AgentSession(
            id: id,
            title: id,
            tool: tool,
            origin: .live,
            attachmentState: .attached,
            phase: phase,
            summary: "",
            updatedAt: updatedAt ?? t0,
            firstSeenAt: t0
        )
    }

    /// Mirrors `AppModel.state.didSet`, which reconciles the shard state against
    /// every session on every mutation. Building fixtures any other way would
    /// test a list the panel can never actually hand over.
    private func companion(_ sessions: [AgentSession], now: Date? = nil) -> CompanionState {
        var geode = GeodeState()
        geode.reconcile(with: sessions, now: now ?? t0)
        return CompanionState(sessions: sessions, geode: geode)
    }

    /// One session sitting in a chosen pose, plus the shard state that puts it
    /// there. `fallen` needs the event path because inference never fractures a
    /// back-filled shard.
    private func list(holding pose: CreaturePose) -> ([AgentSession], GeodeState) {
        let phase: SessionPhase = switch pose {
        case .working: .running
        case .waiting: .waitingForApproval
        case .holding, .fallen: .completed
        }
        let only = session("s1", phase: phase)

        var geode = GeodeState()
        if pose == .fallen {
            geode.apply(.sessionStarted(SessionStarted(
                sessionID: "s1",
                title: "s1",
                tool: .claudeCode,
                initialPhase: .running,
                summary: "",
                timestamp: t0
            )))
            geode.apply(.sessionCompleted(SessionCompleted(
                sessionID: "s1",
                summary: "",
                timestamp: t0,
                isInterrupt: true
            )))
        }
        geode.reconcile(with: [only], now: t0)

        return ([only], geode)
    }

    // MARK: - The four states

    @Test
    func anEmptyListIsAsleep() {
        #expect(companion([]) == .asleep)
    }

    @Test
    func aRunningSessionIsWorking() {
        #expect(companion([session("s1")]) == .working)
    }

    @Test
    func aSessionWaitingOnApprovalWaves() {
        #expect(companion([session("s1", phase: .waitingForApproval)]) == .waving)
    }

    @Test
    func aSessionWaitingOnAnAnswerWaves() {
        #expect(companion([session("s1", phase: .waitingForAnswer)]) == .waving)
    }

    @Test
    func aFinishedListRests() {
        #expect(companion([session("s1", phase: .completed)]) == .resting)
    }

    // MARK: - Waving wins

    /// The awkward mix the spec names outright. Waving is the only state that is
    /// a *request*, so it can never be outvoted by however much is merely
    /// happening.
    @Test
    func oneWaitingSessionOutvotesThreeRunning() {
        let sessions = [
            session("run1"),
            session("run2"),
            session("run3"),
            session("ask", phase: .waitingForApproval),
        ]
        #expect(companion(sessions) == .waving)
    }

    /// Every phase a session can be in, all present at once.
    @Test
    func wavingSurvivesEveryOtherStateAtOnce() {
        let sessions = SessionPhase.allCases.map { session($0.rawValue, phase: $0) }
        #expect(companion(sessions) == .waving)
    }

    /// Below waving, running still beats finished: a companion that rests while
    /// an agent is mid-run would say the work is over before it is.
    @Test
    func anythingRunningOutranksEverythingFinished() {
        let sessions = [
            session("done1", phase: .completed),
            session("run", phase: .running),
            session("done2", phase: .completed),
        ]
        #expect(companion(sessions) == .working)
    }

    // MARK: - One spelling of the attention rule

    /// The attention rule is `CreaturePose.isAskingForYou` and nothing else: for
    /// every pose a session can hold, the companion waves exactly when that pose
    /// is asking for you. A second spelling here is how a raised hand ends up
    /// looking urgent and behaving calm.
    @Test(arguments: CreaturePose.allCases)
    func theCompanionWavesForExactlyThePosesThatAskForYou(pose: CreaturePose) throws {
        let (sessions, geode) = list(holding: pose)
        try #require(geode.pose(for: "s1") == pose)
        #expect((CompanionState(sessions: sessions, geode: geode) == .waving) == pose.isAskingForYou)
    }

    /// An interrupt is a finish, not an emergency. `fallen` is deliberately the
    /// quiet pose — the session stopped, nobody is being asked for anything.
    @Test
    func anInterruptIsFinishedNotAnEmergency() {
        let (sessions, geode) = list(holding: .fallen)
        #expect(CompanionState(sessions: sessions, geode: geode) == .resting)
    }

    /// The pill's creature and the panel's companion are meant to be one
    /// individual, so they must never disagree about whether a hand is up. The
    /// pill picks one shard with `displayed(at:)`; the companion reads the whole
    /// list. Both answers come off the same freeze.
    @Test
    func theCompanionWavesExactlyWhenThePillDoes() throws {
        let waiting = [session("run"), session("ask", phase: .waitingForApproval)]
        var waitingGeode = GeodeState()
        waitingGeode.reconcile(with: waiting, now: t0)
        #expect(try #require(waitingGeode.displayed(at: t0)).isFrozen == true)
        #expect(CompanionState(sessions: waiting, geode: waitingGeode) == .waving)

        let calm = [session("run")]
        var calmGeode = GeodeState()
        calmGeode.reconcile(with: calm, now: t0)
        #expect(try #require(calmGeode.displayed(at: t0)).isFrozen == false)
        #expect(CompanionState(sessions: calm, geode: calmGeode) == .working)
    }

    /// Answering the last open gate puts the hand down. A wave that outlives its
    /// request is worse than no wave at all.
    @Test
    func answeringTheLastGateStopsTheWave() {
        var geode = GeodeState()
        geode.apply(.sessionStarted(SessionStarted(
            sessionID: "s1",
            title: "s1",
            tool: .claudeCode,
            initialPhase: .running,
            summary: "",
            timestamp: t0
        )))
        geode.apply(.permissionRequested(PermissionRequested(
            sessionID: "s1",
            request: PermissionRequest(title: "Write", summary: "", affectedPath: "/tmp"),
            timestamp: t0
        )))
        let asking = [session("s1", phase: .waitingForApproval)]
        #expect(CompanionState(sessions: asking, geode: geode) == .waving)

        geode.apply(.actionableStateResolved(ActionableStateResolved(
            sessionID: "s1",
            summary: "",
            timestamp: t0.addingTimeInterval(5)
        )))
        #expect(CompanionState(sessions: [session("s1")], geode: geode) == .working)
    }

    // MARK: - What "nothing" means

    /// `asleep` means the list is empty, never "nothing recent". Work finished
    /// yesterday is still yours and still on screen, so the companion rests
    /// beside it. When the list stops showing it — the list already owns that
    /// call, via `completedStaleThreshold` — the companion sees nothing and
    /// sleeps. One staleness rule, not two.
    @Test
    func workFinishedLongAgoStillRests() {
        let yesterday = t0.addingTimeInterval(-86_400)
        #expect(companion([session("s1", phase: .completed, updatedAt: yesterday)]) == .resting)
    }

    /// Sessions the shard state has never heard of are still sessions. Asleep is
    /// about the list being empty, never about the app not knowing yet — and an
    /// unknown session reads as calm rather than inventing a wave.
    @Test
    func sessionsWithNoShardsYetAreNotAsleep() {
        #expect(CompanionState(sessions: [session("s1")], geode: GeodeState()) == .working)
    }

    // MARK: - Deterministic

    /// The companion takes no clock of its own, so a list that has not changed
    /// cannot change what it is doing just because time passed. Anything that
    /// ages is the list's decision, made before the companion ever sees it.
    @Test
    func timePassingAloneDoesNotChangeWhatTheCompanionDoes() {
        let sessions = [session("done", phase: .completed), session("run")]
        #expect(companion(sessions, now: t0) == .working)
        #expect(companion(sessions, now: t0.addingTimeInterval(86_400)) == .working)
    }

    /// The companion reads the list in aggregate, so nothing about it may depend
    /// on the order the caller happens to sort by — and the caller re-sorts on
    /// every preference change.
    @Test
    func theOrderOfTheListDoesNotChangeTheAnswer() {
        let sessions = [
            session("a", phase: .completed),
            session("b", phase: .running),
            session("c", phase: .completed),
        ]
        #expect(companion(sessions) == .working)
        #expect(companion(sessions.reversed()) == .working)
        #expect(companion([sessions[1], sessions[2], sessions[0]]) == .working)
    }
}
