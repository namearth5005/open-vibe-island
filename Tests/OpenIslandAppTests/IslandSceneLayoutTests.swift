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

    @Test
    func poseComesFromTheSessionsOwnShard() {
        let scene = layout([
            session("running"),
            session("blocked", phase: .waitingForAnswer),
            session("done", phase: .completed),
        ])
        #expect(scene.stations[0].pose == .working)
        #expect(scene.stations[1].pose == .waiting)
        #expect(scene.stations[2].pose == .holding)
    }

    /// A session the shard state has not caught up with reads as calm rather
    /// than as an alarm — the picture must never invent an attention state.
    @Test
    func aSessionWithNoShardYetReadsAsWorking() {
        let sessions = [session("a")]
        let scene = IslandSceneLayout(sessions: sessions, geode: GeodeState(), width: 540)
        #expect(scene.stations[0].pose == .working)
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
