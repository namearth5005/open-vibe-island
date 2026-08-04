import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

/// The island's preferences, and the promise that having it off changes nothing.
///
/// This is the first task in the island series whose failures are visible, so
/// the claims here are mostly about what does *not* happen: the panel that
/// shipped before the island existed has to still be exactly that panel for
/// anyone who never turns it on.
@MainActor
struct IslandCustomisationTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    /// Every appearance key, both profiles, so one test cannot inherit another's
    /// writes. `UserDefaults` is shared across this target and is the known
    /// source of flakiness in it.
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
        for legacy in ["stateIndicator", "sessionGroup", "sessionSort", "completedStaleThreshold"] {
            UserDefaults.standard.removeObject(forKey: "appearance.island.v8.\(legacy)")
        }
    }

    private func session(
        _ id: String,
        tool: AgentTool = .claudeCode,
        phase: SessionPhase = .running,
        updatedAt: Date? = nil
    ) -> AgentSession {
        var session = AgentSession(
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
        session.isProcessAlive = true
        return session
    }

    // MARK: - The list the companion used to sit above

    /// What this suite used to be: the island band's on/off preference, its
    /// height preference, and the window-sizing contract between them. All three
    /// are gone. The companion left the panel because it stood 8pt above
    /// `sessionPanelHeader`, whose overview chips already answer "does anything
    /// need me" numerically and whose `shippedTodayBadge` already prints the
    /// day's tally — the same duplication that sank the five-creature band.
    ///
    /// Two claims outlived it, and neither was ever really about the island.
    /// They are about the *session list*: that its order is the grouping
    /// preference's to decide, and that "finished long enough ago to go quiet"
    /// has exactly one rule. Both were asserted through the band's plots, so
    /// both are re-pointed here at `islandListSessions` — the list the plots
    /// were only ever mirroring.

    /// Ungrouped, equally-urgent sessions come out most-recent-first. Grouped by
    /// project they come out by project name. The two orders are deliberately
    /// opposed, because that opposition is what tells the grouped list from the
    /// raw one — anything wired to `surfacedSessions` would keep the recency
    /// order and fail.
    @Test
    func listOrderFollowsTheSessionGroupPreference() {
        clearAppearanceDefaults()
        let model = AppModel()
        let now = Date()
        model.state = SessionState(sessions: [
            session("zulu", phase: .running, updatedAt: now),
            session("alpha", phase: .running, updatedAt: now.addingTimeInterval(-60)),
        ])

        model.islandSessionGroup = .none
        let ungrouped = model.islandListSessions.map(\.id)

        model.islandSessionGroup = .project
        let grouped = model.islandListSessions.map(\.id)

        #expect(Set(grouped) == Set(ungrouped))
        #expect(ungrouped == ["zulu", "alpha"])
        #expect(grouped == ["alpha", "zulu"])
    }

    /// One idea of when a finished session goes quiet, not two: a completed
    /// session moves between the "just done" and "idle" sections as
    /// `completedStaleThreshold` changes, and it never falls out of the list
    /// while doing so.
    ///
    /// That second assertion is the one that catches a hardcoded staleness rule
    /// hiding behind the preference — one that disagreed would drop a session
    /// out of both sections while the section list still looked sane.
    @Test
    func theListReusesTheExistingStaleThreshold() {
        clearAppearanceDefaults()
        let model = AppModel()
        model.islandSessionGroup = .state
        let now = Date()
        model.state = SessionState(sessions: [
            session("old", phase: .completed, updatedAt: now.addingTimeInterval(-10 * 60)),
            session("fresh", phase: .completed, updatedAt: now),
        ])

        model.completedStaleThreshold = .twoMinutes
        let tight = model.islandSessionSections.map(\.id)
        let tightListed = Set(model.islandListSessions.map(\.id))

        model.completedStaleThreshold = .never
        let loose = model.islandSessionSections.map(\.id)
        let looseListed = Set(model.islandListSessions.map(\.id))

        #expect(tight == ["state-done", "state-idle"])
        #expect(loose == ["state-done"])
        #expect(tightListed == ["old", "fresh"])
        #expect(looseListed == ["old", "fresh"])
    }

    /// A running session whose process stopped being seen leaves the list.
    ///
    /// Re-pointed from `IslandPoseDistributionTests`, which measured the pose
    /// mix across the band and is deleted with it. This half of that suite was
    /// never about poses: a session the app can no longer find must stop being
    /// listed, or the header counts "1 running" for something that is not.
    @Test
    func aRunningSessionWhoseProcessWentUnseenLeavesTheList() {
        clearAppearanceDefaults()
        let model = AppModel()
        var stale = session("run-0", phase: .running)
        stale.isProcessAlive = false
        stale.processNotSeenCount = 4
        stale.isHookManaged = false
        model.state = SessionState(sessions: [stale, session("done-0", phase: .completed)])

        #expect(model.islandListSessions.contains { $0.id == "run-0" } == false)
    }
}
