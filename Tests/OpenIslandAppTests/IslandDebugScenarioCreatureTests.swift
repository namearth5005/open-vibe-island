import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

/// The attention rule, driven the way the DEV pane and the screenshot harness
/// drive it: load a scenario, then ask what each session's creature is doing.
///
/// `GeodeDebugScenarioTests` pins the shard behind the *closed pill* for these
/// same scenarios. This is the rule laid over it, and the shard being present
/// says nothing about it: a creature can stand there calmly while its session
/// is blocked, and a scenario is exactly the state used to demo and screenshot
/// the app, where that fails nothing.
///
/// **What this suite used to be.** It asserted three claims about the panel's
/// island band — that a creature was *there*, that its hand was up when its
/// session was asking, and that the name under it was its own. The band is
/// gone: the companion left the panel because it duplicated the session-list
/// header. Two of those claims went with it, because a plot that is not drawn
/// cannot be misplaced or mislabelled. The middle one did not — a raised hand
/// still means a session is asking for you, on the pill and on whatever surface
/// the companion lands on next — so it is re-pointed here at the pose rather
/// than at the station that used to carry it.
///
/// Walks the scenarios in a loop rather than taking them as `@Test(arguments:)`:
/// it needs a total over the whole set to show it was not vacuous, and
/// parameterized cases run in parallel, which would put concurrent writes on the
/// appearance defaults this target shares.
@MainActor
struct IslandDebugScenarioCreatureTests {
    /// A hand goes up for exactly the sessions that are asking for something —
    /// no more, and never none.
    ///
    /// The count is derived from the scenarios rather than written down, so
    /// adding a scenario cannot make it wrong. Only the floor beneath it is a
    /// literal, and that is there to stop the whole thing passing on a set where
    /// nobody ever waves.
    @Test
    func aCreatureRaisesItsHandExactlyWhenItsSessionIsAskingForOne() throws {
        let now = Date()
        var waving = 0
        var blocked = 0

        for scenario in IslandDebugScenario.allCases {
            let model = AppModel()
            model.loadDebugSnapshot(scenario.snapshot(at: now))
            blocked += model.state.sessions.filter(\.phase.requiresAttention).count

            for session in model.state.sessions {
                let pose = model.geodeState.pose(for: session.id)
                #expect(
                    pose.isAskingForYou == session.phase.requiresAttention,
                    """
                    \(scenario.rawValue): \(session.id) is \(session.phase) but its creature is \
                    \(pose)
                    """
                )
                if pose.isAskingForYou { waving += 1 }
            }
        }

        #expect(waving == blocked, "\(blocked) sessions were asking for something and \(waving) hands went up")
        #expect(waving > 0, "no scenario blocked a session, so the loop proved nothing")
    }
}
