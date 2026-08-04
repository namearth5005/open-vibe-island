import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

struct IslandSceneLayoutTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func session(
        _ id: String,
        tool: AgentTool = .claudeCode,
        phase: SessionPhase = .running,
        terminalApp: String? = nil
    ) -> AgentSession {
        AgentSession(
            id: id,
            title: id,
            tool: tool,
            phase: phase,
            summary: "",
            updatedAt: t0,
            firstSeenAt: t0,
            jumpTarget: terminalApp.map {
                JumpTarget(terminalApp: $0, workspaceName: "w", paneTitle: "p")
            }
        )
    }

    /// Mirrors what `AppModel` does on every session change, so the shards these
    /// tests read are the ones production would hand the scene.
    private func geode(for sessions: [AgentSession]) -> GeodeState {
        var state = GeodeState()
        state.reconcile(with: sessions, now: t0)
        return state
    }

    private func layout(_ sessions: [AgentSession], width: CGFloat = 540) -> IslandSceneLayout {
        IslandSceneLayout(sessions: sessions, geode: geode(for: sessions), width: width)
    }

    @Test
    func emptyIslandHasNoStationsAndNothingHidden() {
        let scene = layout([])
        #expect(scene.stations.isEmpty)
        #expect(scene.overflow == 0)
    }

    @Test
    func stationsFollowTheOrderTheyWereGivenIn() {
        let scene = layout([session("c"), session("a"), session("b")])
        #expect(scene.stations.map(\.id) == ["c", "a", "b"])
    }

    /// Below ~90pt of pitch the structures collide, which is what caps the band
    /// at five plots. Everything past that is counted, not drawn.
    @Test
    func sixthSessionAndBeyondBecomesACountNotACreature() {
        let six = (0..<6).map { session("s\($0)") }
        #expect(layout(six).stations.count == IslandSceneLayout.stationCapacity)
        #expect(layout(six).overflow == 1)

        let twelve = (0..<12).map { session("s\($0)") }
        #expect(layout(twelve).stations.count == IslandSceneLayout.stationCapacity)
        #expect(layout(twelve).overflow == 7)
    }

    @Test
    func fiveSessionsAllGetAPlot() {
        let scene = layout((0..<5).map { session("s\($0)") })
        #expect(scene.stations.count == 5)
        #expect(scene.overflow == 0)
    }

    @Test
    func stationsAreEvenlySpacedAndCenteredOnTheBand() {
        for count in 1...IslandSceneLayout.stationCapacity {
            let centers = layout((0..<count).map { session("s\($0)") }).stations.map(\.center)
            let pitches = zip(centers, centers.dropFirst()).map { $1 - $0 }
            for pitch in pitches {
                #expect(abs(pitch - IslandSceneLayout.pitch(width: 540)) < 0.001)
            }
            let mid = (centers.first! + centers.last!) / 2
            #expect(abs(mid - 270) < 0.001, "count \(count) is off-center")
        }
    }

    /// A full band must sit exactly on the edge inset — that inset is the widest
    /// station's own half-footprint, so anything wider would clip.
    @Test
    func aFullBandStopsAtTheEdgeInset() {
        let centers = layout((0..<5).map { session("s\($0)") }).stations.map(\.center)
        #expect(abs(centers.first! - IslandSceneLayout.edgeInset) < 0.001)
        #expect(abs(centers.last! - (540 - IslandSceneLayout.edgeInset)) < 0.001)
    }

    /// 540pt on notch Macs, 520 on external. Both must clear the collision floor
    /// with five plots, or the ceiling of five is wrong.
    @Test
    func bothPanelWidthsClearTheCollisionFloor() {
        for width in [520.0, 540.0] as [CGFloat] {
            #expect(IslandSceneLayout.pitch(width: width) >= IslandSceneLayout.minimumStationPitch)
        }
    }

    @Test
    func sameSessionsInTheSameOrderProduceTheSameLayout() {
        let sessions = [
            session("a", tool: .codex, phase: .waitingForApproval, terminalApp: "Ghostty"),
            session("b", tool: .cursor, phase: .completed, terminalApp: "Cursor"),
            session("c", tool: .kimiCLI),
        ]
        #expect(layout(sessions) == layout(sessions))
    }

    @Test
    func theCreatureSaysWhichAgentAndTheStructureSaysWhereItRuns() {
        let scene = layout([
            session("a", tool: .qwenCode, terminalApp: "Ghostty"),
            session("b", tool: .codex, terminalApp: "IntelliJ IDEA"),
        ])
        #expect(scene.stations[0].species == .claude)
        #expect(scene.stations[0].structure == .terminal)
        #expect(scene.stations[1].species == .codex)
        #expect(scene.stations[1].structure == .tower)
    }

    /// The jump target is optional — a session discovered before its host is
    /// known still has to stand somewhere.
    @Test
    func aSessionWithNoKnownHostStandsAtTheWorkshop() {
        let scene = layout([session("a")])
        #expect(scene.stations[0].structure == .workshop)
    }

    // MARK: - Pose, one state at a time
    //
    // Split one state per test rather than asserted together, because the whole
    // claim the island rests on is that the picture carries state: a regression
    // here has to name *which* state stopped arriving, not just that one did.
    // `CreaturePoseTests` pins the same four derivations on the shard itself;
    // these pin that they survive the trip through `IslandSceneLayout`, which is
    // the only place a session's pose and its plot are joined.

    /// The pose the band draws for a one-session island.
    ///
    /// `#require`d rather than subscripted so that a layout which stopped
    /// producing stations at all fails the test that asked, instead of trapping
    /// and taking the rest of the run with it.
    private func drawnPose(
        of session: AgentSession,
        geode: GeodeState? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> CreaturePose {
        let scene = IslandSceneLayout(
            sessions: [session],
            geode: geode ?? self.geode(for: [session]),
            width: 540
        )
        return try #require(scene.stations.first, sourceLocation: sourceLocation).pose
    }

    @Test
    func aRunningSessionIsDrawnWorking() throws {
        #expect(try drawnPose(of: session("a")) == .working)
    }

    /// Both blocked phases collapse to the one raised hand on purpose — the
    /// picture says "it needs you", and *what* it needs is the strip's job.
    @Test(arguments: [SessionPhase.waitingForApproval, .waitingForAnswer])
    func aSessionBlockedOnTheHumanIsDrawnWaiting(phase: SessionPhase) throws {
        #expect(try drawnPose(of: session("a", phase: phase)) == .waiting)
    }

    @Test
    func aFinishedSessionIsDrawnHolding() throws {
        #expect(try drawnPose(of: session("a", phase: .completed)) == .holding)
    }

    /// Interruption is not a `SessionPhase` — it arrives only as `isInterrupt`
    /// on the completion event, so this is the one pose that cannot be reached
    /// by describing a session's state.
    @Test
    func anInterruptedSessionIsDrawnFallen() throws {
        let interrupted = session("a", phase: .completed)
        var geode = self.geode(for: [interrupted])
        geode.apply(.sessionCompleted(
            SessionCompleted(sessionID: "a", summary: "stopped", timestamp: t0, isInterrupt: true)
        ))
        #expect(try drawnPose(of: interrupted, geode: geode) == .fallen)
    }

    /// The four states must land on four *different* poses, or the band is
    /// drawing a distinction it cannot show. Asserted as a set as well as a
    /// sequence, so that two states quietly collapsing onto one sprite fails
    /// here rather than being discovered by looking at the panel.
    @Test
    func theFourStatesReachFourDifferentPoses() {
        let sessions = [
            session("running"),
            session("blocked", phase: .waitingForAnswer),
            session("done", phase: .completed),
            session("stopped", phase: .completed),
        ]
        var geode = self.geode(for: sessions)
        geode.apply(.sessionCompleted(
            SessionCompleted(sessionID: "stopped", summary: "stopped", timestamp: t0, isInterrupt: true)
        ))
        let poses = IslandSceneLayout(sessions: sessions, geode: geode, width: 540).stations.map(\.pose)

        #expect(poses == [.working, .waiting, .holding, .fallen])
        #expect(Set(poses).count == 4, "two of the four states are drawn as the same creature")
    }

    /// A session the shard state has not caught up with reads as calm rather
    /// than as an alarm — the picture may never invent an attention state it
    /// was not told about.
    ///
    /// Checked for every phase, not just a running one: the fallback also has
    /// to refuse to turn a finished session into a wave.
    @Test(arguments: SessionPhase.allCases)
    func aSessionWithNoShardYetReadsAsWorking(phase: SessionPhase) throws {
        #expect(
            try drawnPose(of: session("a", phase: phase), geode: GeodeState()) == .working,
            "\(phase) invented a pose without a shard"
        )
    }

    /// A session that arrives by discovery rather than by hook events is
    /// back-filled by `GeodeState.reconcile`, which never fractures a shard —
    /// so an interrupted session the app only learned about at launch is drawn
    /// holding its reward up, exactly like a clean finish.
    ///
    /// Deliberate (claiming a fracture that did not happen is worse than
    /// missing one) but it is why `fallen` is close to unreachable in practice:
    /// everything on screen at launch came through this path.
    @Test
    func anInterruptTheAppOnlyDiscoveredIsDrawnAsACleanFinish() throws {
        #expect(try drawnPose(of: session("a", phase: .completed)) == .holding)
    }

    /// Individual variation reuses the existing seed generator, so a creature
    /// keeps its identity across the pill and the panel.
    @Test
    func seedMatchesTheSessionIdentity() {
        let scene = layout([session("session-42")])
        #expect(scene.stations[0].seed == ShardSeed.value(for: "session-42"))
    }

    /// The band is the pre-cropped 540x150pt artwork, so height is not a free
    /// parameter — a mismatched height would stretch the horizon.
    @Test
    func bandHeightFollowsTheArtworkAspect() {
        #expect(abs(layout([], width: 540).height - 150) < 0.001)
        #expect(layout([], width: 520).height < 150)
    }
}

@MainActor
struct IslandSceneArtworkTests {
    /// A missing background PNG does not fail the build — the band would just
    /// render as a flat rectangle. Resolving it here is the only place that
    /// absence surfaces.
    @Test
    func theSceneBandArtworkIsShipped() {
        #expect(CreatureSprite.image(named: IslandSceneView.backgroundName) != nil)
    }

    /// Sprites are trimmed to their content, so a species that is drawn broader
    /// than the station box would bind on width and render shorter than its
    /// neighbours — a row of creatures at different heights standing on the same
    /// ground. New artwork that breaks this fails here rather than in a glance
    /// at the panel.
    ///
    /// `fallen` is exempt on purpose: those sprites *should* bind on width, so a
    /// knocked-over creature lies lower than a standing one.
    @Test
    func standingSpritesAllReachTheSameHeight() {
        let box = IslandStationView.creatureBox
        let boxAspect = box.width / box.height

        for species in CreatureSpecies.allCases {
            var names = CreaturePose.allCases
                .filter { $0 != .fallen }
                .map { CreatureSprite.name(for: species, pose: $0) }
            names += [CreatureSprite.alternateName(for: species, pose: .waiting)].compactMap { $0 }

            for name in names {
                guard let image = CreatureSprite.image(named: name) else {
                    Issue.record("missing artwork: \(name)")
                    continue
                }
                let aspect = image.size.width / image.size.height
                #expect(aspect <= boxAspect, "\(name) is too broad for the station box")
            }
        }
    }
}
