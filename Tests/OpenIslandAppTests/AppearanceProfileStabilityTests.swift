import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

/// `activeAppearanceProfile` is derived from live overlay placement. If that
/// placement can resolve *between* a preference write and the following read,
/// the value goes into one profile and comes back from the other — the write
/// silently does nothing.
///
/// This is the bug that made the session-list tests fail on a notch Mac while
/// passing on hardware without one.
@MainActor
struct AppearanceProfileStabilityTests {
    private func clearAppearanceDefaults() {
        for profile in ["notch", "topBar"] {
            for key in ["rightSlot", "centerLabel", "stateIndicator",
                        "sessionGroup", "sessionSort", "completedStaleThreshold"] {
                UserDefaults.standard.removeObject(
                    forKey: "appearance.island.v8.\(profile).\(key)"
                )
            }
        }
        for legacy in ["stateIndicator", "sessionGroup", "sessionSort", "completedStaleThreshold"] {
            UserDefaults.standard.removeObject(forKey: "appearance.island.v8.\(legacy)")
        }
    }

    /// A preference write must still be readable afterwards, whatever the
    /// overlay does in between.
    @Test
    func aPreferenceWriteSurvivesAPlacementRefresh() {
        clearAppearanceDefaults()
        let model = AppModel()

        // Writing the preference internally triggers the placement refresh that
        // used to flip the active profile out from under the value just written,
        // so the plain write is the reproduction — no extra call needed.
        model.islandSessionGroup = .state

        #expect(model.islandSessionGroup == .state)
    }

    /// The profile must not change merely because a preference was written.
    @Test
    func writingAPreferenceDoesNotChangeTheActiveProfile() {
        clearAppearanceDefaults()
        let model = AppModel()

        let before = model.activeAppearanceProfile
        model.islandSessionGroup = .state
        model.completedStaleThreshold = .fiveMinutes

        #expect(model.activeAppearanceProfile == before)
    }

    /// Grouping is the user-visible symptom: the sections collapse to a single
    /// "all" bucket when the write lands in the inactive profile.
    @Test
    func groupingAppliesAfterBeingSet() {
        clearAppearanceDefaults()
        let model = AppModel()
        model.islandSessionGroup = .state

        var running = AgentSession(
            id: "running", title: "s", tool: .codex, origin: .live,
            attachmentState: .attached, phase: .running,
            summary: "", updatedAt: Date()
        )
        running.isProcessAlive = true
        model.state = SessionState(sessions: [running])

        #expect(model.islandSessionSections.map(\.id) != ["all"])
    }
}
