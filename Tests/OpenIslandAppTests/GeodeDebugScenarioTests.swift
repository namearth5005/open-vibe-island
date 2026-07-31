import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

/// The shard is driven by `GeodeState`, which is fed from `AgentEvent`. Debug
/// scenarios and the screenshot harness bypass events entirely and assign
/// `state` directly, so without reconciliation the shard would be invisible in
/// exactly the situations used to demo and screenshot the app.
@MainActor
struct GeodeDebugScenarioTests {
    @Test
    func loadingADebugScenarioPopulatesTheShardState() {
        let model = AppModel()
        model.loadDebugSnapshot(IslandDebugScenario.sessionList.snapshot())

        let live = model.state.sessions.filter { $0.phase != .completed }
        // Asserted explicitly: without this the loop below passes vacuously if
        // the scenario ever changes to contain only finished sessions.
        #expect(!live.isEmpty, "scenario should contain at least one live session")

        for session in live {
            #expect(
                model.geodeState.shard(id: session.id) != nil,
                "live session \(session.id) has no shard, so the pill would render empty"
            )
        }
    }

    /// A shard must be *selectable*, not merely present — the pill renders
    /// `displayed`, and a scenario full of shards with none displayable would
    /// still screenshot as an empty slot.
    ///
    /// Deliberately does not set `islandRightSlot`: that writes to the shared
    /// `UserDefaults` every other suite reads, which is the existing source of
    /// flakiness in this target. Asserting on the state the slot renders from
    /// tests the same thing without the global write.
    @Test
    func aDebugScenarioProducesADisplayableShard() {
        let model = AppModel()
        model.loadDebugSnapshot(IslandDebugScenario.sessionList.snapshot())
        #expect(model.geodeState.displayed(at: Date()) != nil)
    }

    /// An approval scenario is the one that matters most for demos: it is the
    /// frozen state, which is the feature's entire notification mechanism.
    @Test
    func anApprovalScenarioProducesAFrozenShard() {
        let model = AppModel()
        model.loadDebugSnapshot(IslandDebugScenario.approvalCard.snapshot())

        let blocked = model.state.sessions.filter(\.phase.requiresAttention)
        #expect(!blocked.isEmpty, "approval scenario should contain a blocked session")

        for session in blocked {
            #expect(model.geodeState.shard(id: session.id)?.isFrozen == true)
        }
    }

    /// Scenario snapshots replace state wholesale; shards for sessions that are
    /// no longer present must not linger and be picked as the displayed shard.
    @Test
    func switchingScenariosDropsShardsForSessionsThatAreGone() {
        let model = AppModel()
        model.loadDebugSnapshot(IslandDebugScenario.sessionList.snapshot())
        let firstIDs = Set(model.state.sessions.map(\.id))

        model.loadDebugSnapshot(IslandDebugScenario.approvalCard.snapshot())
        let secondIDs = Set(model.state.sessions.map(\.id))

        for staleID in firstIDs.subtracting(secondIDs) {
            #expect(model.geodeState.shard(id: staleID) == nil)
        }
    }
}
