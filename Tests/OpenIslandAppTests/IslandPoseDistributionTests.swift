import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

/// What the island actually draws for a normal day's sessions.
///
/// `IslandSceneLayoutTests` proves each state reaches its own pose. That is a
/// per-session claim and it holds. This suite asks the question that per-session
/// claim cannot answer: given the mix a real user has in front of them, how many
/// *different* creatures end up on the meadow?
///
/// It exists because round 1 shipped a band that passed every pose test and then
/// read, to the first human who opened it, as five identical bears. The session
/// list at the time said *1 running, 7 done, 3 idle*. The mix is reproduced here
/// verbatim so the answer is a number in the gate rather than an impression, and
/// so that task 2's variation work has a before to be measured against.
///
/// Serialized because the whole suite drives `AppModel`, whose island
/// preferences live in the `UserDefaults` this test target shares.
@MainActor
@Suite(.serialized)
struct IslandPoseDistributionTests {
    /// Every appearance key, both profiles, before every test — a value another
    /// suite left behind would otherwise decide the grouping these tests
    /// measure.
    init() {
        clearAppearanceDefaults()
    }

    private func clearAppearanceDefaults() {
        for profile in ["notch", "topBar"] {
            for key in ["rightSlot", "centerLabel", "usageDisplay", "stateIndicator",
                        "sessionGroup", "sessionSort", "completedStaleThreshold",
                        "scene", "sceneHeight"] {
                UserDefaults.standard.removeObject(
                    forKey: "appearance.island.v8.\(profile).\(key)"
                )
            }
        }
    }

    /// One agent in one workspace, which is the case the island was reported
    /// against and the case assumption 2 of the round-2 backlog calls typical.
    /// `isProcessAlive` defaults to true because a finished Claude Code session
    /// whose TUI is still open is exactly that, and because `isVisibleInIsland`
    /// drops a completed session whose process has gone — a mix built without it
    /// would never reach the island at all.
    private func session(
        _ id: String,
        phase: SessionPhase,
        updatedAt: Date,
        alive: Bool = true
    ) -> AgentSession {
        var session = AgentSession(
            id: id,
            title: id,
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: phase,
            summary: "",
            updatedAt: updatedAt,
            firstSeenAt: updatedAt.addingTimeInterval(-900),
            jumpTarget: JumpTarget(terminalApp: "Ghostty", workspaceName: "dugong", paneTitle: "p")
        )
        session.isProcessAlive = alive
        return session
    }

    /// The observed mix: one running session, seven finished inside the stale
    /// threshold, three finished outside it. `runningIsAlive` is the one knob,
    /// because whether the running session's process was seen is the only thing
    /// that changes the answer.
    private func observedMix(now: Date, runningIsAlive: Bool = true) -> [AgentSession] {
        var sessions = [
            session("run-0", phase: .running, updatedAt: now.addingTimeInterval(-30), alive: runningIsAlive)
        ]
        sessions += (0..<7).map {
            session("done-\($0)", phase: .completed, updatedAt: now.addingTimeInterval(-60 - Double($0) * 10))
        }
        sessions += (0..<3).map {
            session("idle-\($0)", phase: .completed, updatedAt: now.addingTimeInterval(-3_600 - Double($0) * 10))
        }
        return sessions
    }

    /// Grouping and sort are written rather than inherited, and default to the
    /// shipped values — the configuration the reported screenshot was taken in.
    /// They live in the same shared defaults `init()` has just cleared, so
    /// writing them is what keeps another suite from choosing where the
    /// creatures stand.
    private func model(
        sessions: [AgentSession],
        group: IslandSessionGroup = .none,
        sort: IslandSessionSort = .attention
    ) -> AppModel {
        let model = AppModel()
        model.islandScene = .on
        model.islandSessionGroup = group
        model.islandSessionSort = sort
        model.state = SessionState(sessions: sessions)
        return model
    }

    /// The finding this task was opened to establish.
    ///
    /// Eleven sessions, ten of them finished, five plots. The band is *correct*
    /// — the running session is drawn working and every finished one is drawn
    /// holding — and it is four identical creatures either way. Pinned as an
    /// exact sequence rather than a count so that task 2 changing it has to
    /// change this number and say what it changed it to.
    @Test
    func theObservedSessionMixDrawsFourIdenticalFinishedCreatures() throws {
        let now = Date()
        let model = model(sessions: observedMix(now: now))
        let band = try #require(model.islandBandLayout(width: 540, now: now))

        #expect(band.scene.stations.map(\.pose) == [.working, .holding, .holding, .holding, .holding])
        #expect(band.scene.overflow == 6)

        // The running session is plotted, and plotted first — which is the half
        // of hypothesis (a) that could have been true and is not.
        #expect(band.scene.stations.first?.id == "run-0")
    }

    /// Four of the five plots carry one pose.
    ///
    /// Stated as a fraction because "most of the island is the same creature"
    /// is the defect, and a fraction is the only form of it that whatever task
    /// 2 lands can be compared against.
    @Test
    func fourOfTheFivePlotsCarryTheSamePose() throws {
        let now = Date()
        let model = model(sessions: observedMix(now: now))
        let band = try #require(model.islandBandLayout(width: 540, now: now))

        let plotted = band.scene.stations.map(\.pose)
        #expect(plotted.filter { $0 == .holding }.count == 4)
        #expect(Set(plotted).count == 2, "the whole band carries two of the four available poses")
    }

    /// And the plots are not an unlucky slice: ten of the eleven sessions
    /// behind them are the same pose too, so no choice of five could have done
    /// better. Two of the four poses never occur at all.
    @Test
    func tenOfTheElevenSessionsBehindThePlotsCarryTheSamePose() {
        let now = Date()
        let model = model(sessions: observedMix(now: now))

        let listed = model.islandListSessions.map { model.geodeState.pose(for: $0.id) }
        #expect(listed.count == 11)
        #expect(listed.filter { $0 == .holding }.count == 10)
        #expect(listed.filter { $0 == .working }.count == 1)
        #expect(listed.filter { $0 == .waiting }.count == 0)
        #expect(listed.filter { $0 == .fallen }.count == 0)
    }

    /// Not an artefact of how the list happens to be grouped or sorted.
    ///
    /// Every combination the user can pick reaches the same five poses, so
    /// nothing the user can do to the session list makes the picture say more.
    /// Cartesian product on purpose: it is the whole preference space, and it
    /// is eight cases.
    @Test(arguments: IslandSessionGroup.allCases, IslandSessionSort.allCases)
    func everyGroupingAndSortReachesTheSameFivePoses(
        group: IslandSessionGroup,
        sort: IslandSessionSort
    ) throws {
        let now = Date()
        let model = model(sessions: observedMix(now: now), group: group, sort: sort)
        let band = try #require(model.islandBandLayout(width: 540, now: now))

        #expect(
            band.scene.stations.map(\.pose) == [.working, .holding, .holding, .holding, .holding],
            "group \(group.rawValue) / sort \(sort.rawValue) draws a different island"
        )
    }

    /// The rest of hypothesis (a), closed off: a session the list calls running
    /// cannot be one the meadow left out.
    ///
    /// `AppModel.displayPriority` scores a live process at 12,000 against the
    /// `running` phase's 2,000, so on paper a finished session outranks a
    /// running one — but only a session whose process is alive can be finished
    /// *and* still on the island, and a running session whose process is alive
    /// carries the same 12,000. The two never actually compete.
    @Test
    func everyRunningSessionOnTheListHasAPlot() throws {
        let now = Date()
        let model = model(sessions: observedMix(now: now))
        let band = try #require(model.islandBandLayout(width: 540, now: now))

        let plotted = Set(band.scene.stations.map(\.id))
        let running = model.islandListSessions.filter { $0.phase == .running }
        #expect(running.isEmpty == false, "no running session in the list, so this proved nothing")
        for session in running {
            #expect(plotted.contains(session.id), "\(session.id) is listed as running but has no plot")
        }
    }

    /// And it cannot be lost the other way either: a running session whose
    /// process stops being seen does not linger as an unplotted row.
    /// `isVisibleInIsland` drops it from the island entirely, so the list can
    /// never read "1 running" over a meadow with nothing running on it.
    ///
    /// The band that is left really is five identical creatures — but the words
    /// above it have stopped claiming otherwise, which is the difference between
    /// this and the screenshot that opened this task.
    @Test
    func aRunningSessionWhoseProcessWentUnseenLeavesTheListAndTheMeadowTogether() throws {
        let now = Date()
        let model = model(sessions: observedMix(now: now, runningIsAlive: false))
        let band = try #require(model.islandBandLayout(width: 540, now: now))

        #expect(model.islandListSessions.contains { $0.id == "run-0" } == false)
        #expect(band.scene.stations.contains { $0.id == "run-0" } == false)
        #expect(band.scene.stations.map(\.pose) == [.holding, .holding, .holding, .holding, .holding])
    }

    /// The vocabulary is not broken, it is unused: a mix that *does* contain
    /// different states draws different creatures. Three rather than four,
    /// because the fourth needs a completion event and this test is about the
    /// path from the session list rather than about the shard reducer.
    ///
    /// Through `AppModel` rather than through `IslandSceneLayout` directly —
    /// `IslandSceneLayoutTests.theFourStatesReachFourDifferentPoses` already
    /// pins the layout, and what this adds is that nothing between the app's
    /// session list and the band flattens them on the way.
    @Test
    func aMixThatContainsThreeStatesDrawsThreeDifferentCreatures() throws {
        let now = Date()
        let model = model(sessions: [
            session("blocked", phase: .waitingForApproval, updatedAt: now),
            session("running", phase: .running, updatedAt: now),
            session("done", phase: .completed, updatedAt: now),
        ])

        let band = try #require(model.islandBandLayout(width: 540, now: now))
        #expect(Set(band.scene.stations.map(\.pose)) == [.working, .waiting, .holding])
    }
}
