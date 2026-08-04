import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

/// The island band, driven the way the DEV pane and the screenshot harness
/// drive it: load a scenario, then ask `AppModel` what the band contains.
///
/// `GeodeDebugScenarioTests` pins the shard behind the *closed pill* for these
/// same scenarios. This is the panel half, and the shard being present says
/// nothing about it: a creature can be dropped by the five-plot cap, can be
/// captioned by somebody else's name, or can stand there calmly while its
/// session is blocked. Scenarios are exactly the states used to demo and
/// screenshot the app, where none of that fails anything.
///
/// Three claims, each chosen because a user would notice it: the creature is
/// *there*, its hand is up when and only when its session is asking for
/// something, and the name under it is its own. Artwork is deliberately not
/// re-checked here — `CreatureSpriteTests.everySpeciesAndPoseHasArtwork` and
/// `CreatureStructureArtworkTests` already resolve every species, pose and
/// structure that exists, and a scenario can only ever reach a subset of those.
///
/// Each test walks the scenarios in a loop rather than taking them as
/// `@Test(arguments:)`. Two of the three need a total over the whole set to show
/// they were not vacuous — some scenarios contain no live session and some block
/// nobody — and parameterized cases run in parallel, which would put concurrent
/// writes on the appearance defaults this target shares.
@MainActor
struct IslandDebugScenarioCreatureTests {
    /// A scenario loaded with the island switched on, and the band it produces.
    ///
    /// The write order is deliberate. `loadDebugSnapshot` calls
    /// `overlay.applyOverlayState`, which can re-resolve placement and therefore
    /// flip `activeAppearanceProfile`; a preference written *before* the snapshot
    /// would land in one profile and be read back from the other, and the island
    /// would silently stay off. Every assertion below would then pass while
    /// asserting nothing, which is why the band is `#require`d rather than
    /// optional-chained: an island that failed to turn on fails the test here
    /// instead of emptying it.
    ///
    /// Grouping and sort are written rather than inherited: they live in the
    /// shared `UserDefaults` this whole target reads, so a value another suite
    /// left behind would otherwise decide where the creatures stand. They are
    /// set to the shipped defaults, which is the configuration a demo or a
    /// screenshot actually runs in. `islandRightSlot` is never written — that
    /// one governs the closed pill and is the known source of flakiness here.
    private func band(
        for scenario: IslandDebugScenario,
        now: Date,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> (model: AppModel, band: IslandBandLayout) {
        let model = AppModel()
        model.loadDebugSnapshot(scenario.snapshot(at: now))
        model.islandScene = .on
        model.islandSessionGroup = .none
        model.islandSessionSort = .attention

        let band = try #require(
            model.islandBandLayout(width: 540, now: now),
            "\(scenario.rawValue): island is off, so nothing else here asserts anything",
            sourceLocation: sourceLocation
        )
        return (model, band)
    }

    /// Nobody is left standing on an empty meadow, and no session that is still
    /// going gets collapsed into the `+N` badge.
    ///
    /// The cap is five plots against nine sessions, so *which* five is a real
    /// decision — one made by session ranking, grouping and the cap together,
    /// none of which the island itself owns. A live session losing its plot to
    /// five finished ones is how this breaks, and it breaks quietly: the badge
    /// still counts it, so the band goes on looking correct.
    @Test
    func everyLiveSessionInAScenarioStandsOnTheIsland() throws {
        let now = Date()
        var liveSeen = 0

        for scenario in IslandDebugScenario.allCases {
            let (model, band) = try band(for: scenario, now: now)
            let plotted = Set(band.scene.stations.map(\.id))

            #expect(
                plotted.isEmpty == false,
                "\(scenario.rawValue): nobody is on the island, which is what a band that failed to build looks like"
            )

            let live = model.state.sessions.filter { $0.phase != .completed }
            liveSeen += live.count
            for session in live {
                #expect(
                    plotted.contains(session.id),
                    "\(scenario.rawValue): live session \(session.id) has no plot, so it is a number in the corner"
                )
            }
        }

        // Two scenarios are entirely finished sessions on purpose, so the inner
        // loop must not be trusted to have examined anything. Asserted across the
        // set rather than per scenario for that reason.
        #expect(liveSeen > 0, "no scenario contained a live session, so the loop proved nothing")
    }

    /// The raised hand is the whole notification, so it has to be exactly as
    /// common as the thing it notifies about.
    ///
    /// Asserted in both directions, and then again by count. A missed wave leaves
    /// a blocked agent looking busy; a phantom wave sends the user to a terminal
    /// that wanted nothing, which is the worse of the two because it teaches them
    /// to stop looking. The count is derived from the scenarios rather than
    /// written down, so adding a scenario cannot make it wrong — only the floor
    /// beneath it is a literal, and that is there to stop the whole thing passing
    /// on an island where nobody ever waves.
    @Test
    func aCreatureRaisesItsHandExactlyWhenItsSessionIsAskingForOne() throws {
        let now = Date()
        var waving = 0
        var blocked = 0

        for scenario in IslandDebugScenario.allCases {
            let (model, band) = try band(for: scenario, now: now)
            blocked += model.state.sessions.filter(\.phase.requiresAttention).count

            for station in band.scene.stations {
                let session = try #require(
                    model.state.sessions.first { $0.id == station.id },
                    "\(scenario.rawValue): station \(station.id) belongs to no session in state"
                )
                #expect(
                    station.pose.isAskingForYou == session.phase.requiresAttention,
                    """
                    \(scenario.rawValue): \(session.id) is \(session.phase) but its creature is \
                    \(station.pose)
                    """
                )
                if station.pose.isAskingForYou { waving += 1 }
            }
        }

        #expect(waving == blocked, "\(blocked) sessions were asking for something and \(waving) hands went up")
        #expect(waving > 0, "no scenario blocked a session, so the loop proved nothing")
    }

    /// The scene carries no text at all, so a creature's whole identity is the
    /// cell drawn under it. If the two bands ever disagree about which session is
    /// at position *n*, every name on the island is wrong by one and nothing
    /// about the band looks broken.
    ///
    /// The overflow counts go with them, because the other way to lose a session
    /// is for one band to hide it while the other draws it.
    @Test
    func everyCreatureIsNamedByTheCellBeneathIt() throws {
        let now = Date()

        for scenario in IslandDebugScenario.allCases {
            let (model, band) = try band(for: scenario, now: now)

            #expect(
                band.strip.cells.map(\.id) == band.scene.stations.map(\.id),
                "\(scenario.rawValue): the names under the creatures are not those creatures' names"
            )

            let listed = model.islandListSessions.count
            #expect(band.scene.stations.count == min(listed, IslandSceneLayout.stationCapacity))
            #expect(band.scene.overflow == listed - band.scene.stations.count)
            #expect(band.strip.overflow == band.scene.overflow)
        }
    }
}
