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

    // MARK: - Off by default

    /// The whole of "a user who never opens Personalization sees exactly
    /// today's app".
    @Test
    func theIslandIsOffByDefault() {
        clearAppearanceDefaults()
        let model = AppModel()

        #expect(model.islandScene == .off)
        #expect(!model.islandScene.isVisible)
        // Nothing is drawn, which is the claim that actually matters — the
        // preference reading `.off` would be worth nothing if the band were
        // built anyway.
        #expect(model.islandBandLayout(width: 540, now: t0) == nil)
    }

    /// Two things have to say "off" and they are written in different places:
    /// the struct's own default, and the fallback `loadAppearancePreferences`
    /// uses when nothing is stored. A test that only drove `AppModel` would
    /// leave the struct default free to drift, and it is what a future profile
    /// or migration would pick up.
    @Test
    func theStoredDefaultAndTheStructDefaultBothSayOff() {
        #expect(IslandAppearancePreferences().scene == .off)
        #expect(IslandAppearancePreferences().sceneHeight == .standard)
    }

    /// Off by default has to survive the profile the machine happens to resolve
    /// to, or the guarantee holds on one kind of Mac and not the other.
    @Test
    func theIslandIsOffByDefaultInBothProfiles() {
        clearAppearanceDefaults()
        let model = AppModel()

        for profile in IslandAppearanceDisplayProfile.allCases {
            #expect(model.appearancePreferences(for: profile).scene == .off)
        }
    }

    /// Someone who already asked for a creature in the closed pill did not
    /// thereby ask for a landscape in their panel — and turning the island on
    /// must not reach back and change their pill either. The two preferences
    /// govern two surfaces and are deliberately independent.
    @Test
    func theIslandIsIndependentOfTheCreatureRightSlot() {
        clearAppearanceDefaults()
        let model = AppModel()

        model.islandRightSlot = .creature
        #expect(model.islandScene == .off)

        model.islandScene = .on
        #expect(model.islandRightSlot == .creature)

        model.islandScene = .off
        #expect(model.islandRightSlot == .creature)
    }

    // MARK: - Scene height

    @Test
    func sceneHeightOffersExactlyCompactStandardAndTall() {
        #expect(IslandSceneHeight.allCases == [.compact, .standard, .tall])
    }

    /// `standard` is the artwork's own 3.6:1 aspect, so it neither crops nor
    /// reveals; the other two are a real difference either side of it.
    @Test
    func theThreeHeightsAreOrderedAndDistinct() {
        let scales = IslandSceneHeight.allCases.map(\.scale)
        #expect(scales == scales.sorted())
        #expect(Set(scales).count == 3)
        #expect(IslandSceneHeight.standard.scale == 1)
    }

    @Test
    func standardIsTheDefault() {
        clearAppearanceDefaults()
        #expect(AppModel().islandSceneHeight == .standard)
    }

    /// A taller island has to actually be taller in the number the window is
    /// sized from, or the preference is decoration.
    @Test
    func atallerSceneMakesATallerBand() {
        let heights = IslandSceneHeight.allCases.map {
            IslandBandLayout.height(width: 540, sceneHeight: $0)
        }
        #expect(heights == heights.sorted())
        #expect(Set(heights).count == 3)
    }

    /// The window is sized from the static formula and the band is drawn from
    /// an instance. If those two ever disagree the band is clipped or leaves a
    /// gap, and nothing else in the app would notice.
    @Test
    func theHeightTheWindowReservesIsTheHeightTheBandDraws() {
        let sessions = (0..<3).map { session("s\($0)") }
        var geode = GeodeState()
        geode.reconcile(with: sessions, now: t0)

        for height in IslandSceneHeight.allCases {
            for width in [520.0, 540.0] as [CGFloat] {
                let band = IslandBandLayout(
                    sessions: sessions,
                    geode: geode,
                    selectedSessionID: nil,
                    width: width,
                    sceneHeight: height,
                    now: t0,
                    lang: LanguageManager(language: .en)
                )
                #expect(band.height == IslandBandLayout.height(width: width, sceneHeight: height))
            }
        }
    }

    // MARK: - With the island off, nothing changes

    /// The island's only claim on the window is this number, so proving it is
    /// zero while off proves the panel is sized exactly as it was before the
    /// island existed — at every height setting, so a stale `sceneHeight` left
    /// over from a trial cannot leak back in.
    @Test
    func anIslandThatIsOffCostsThePanelNoHeight() {
        clearAppearanceDefaults()
        let model = AppModel()

        for height in IslandSceneHeight.allCases {
            model.islandSceneHeight = height
            #expect(model.islandScene == .off)
            #expect(model.islandBandHeight(width: 540) == 0)
            #expect(model.islandBandHeight(width: 520) == 0)
        }
    }

    /// And when it is on it costs exactly the band, not a rounded-up guess.
    @Test
    func anIslandThatIsOnCostsThePanelExactlyItsBand() {
        clearAppearanceDefaults()
        let model = AppModel()
        model.islandScene = .on
        model.islandSceneHeight = .tall

        #expect(
            model.islandBandHeight(width: 540)
                == IslandBandLayout.height(width: 540, sceneHeight: .tall)
        )
    }

    /// The session list is the panel's actual content, and the island must not
    /// perturb it in either direction — not what is in it, not what order it is
    /// in, not how it is grouped. Asserted both ways round because a preference
    /// that only broke things on the way *back* off would be worse.
    @Test
    func togglingTheIslandDoesNotDisturbTheSessionList() {
        clearAppearanceDefaults()
        let model = AppModel()
        model.islandSessionGroup = .state
        model.state = SessionState(sessions: [
            session("a", phase: .waitingForApproval),
            session("b", phase: .running),
            session("c", phase: .completed),
        ])

        func snapshot() -> ([String], [String]) {
            (model.islandSessionSections.map(\.id), model.islandListSessions.map(\.id))
        }

        let before = snapshot()

        model.islandScene = .on
        #expect(snapshot() == before)

        model.islandSceneHeight = .compact
        #expect(snapshot() == before)

        model.islandScene = .off
        #expect(snapshot() == before)
    }

    // MARK: - Reusing what already exists

    /// Station order is the session list's order. The island does not decide a
    /// second time where a creature stands, so changing how the list is grouped
    /// changes where the creatures are — that is the whole of "honours the
    /// existing `sessionGroup`".
    /// Ungrouped, equally-urgent sessions come out most-recent-first. Grouped by
    /// project they come out by project name. The two orders are deliberately
    /// opposed here, because that opposition is what lets this test tell the
    /// grouped list from the raw one — an island wired to `surfacedSessions`
    /// would keep the recency order and fail.
    @Test
    func stationOrderFollowsTheSessionGroupPreference() throws {
        clearAppearanceDefaults()
        let model = AppModel()
        model.islandScene = .on
        let now = Date()
        model.state = SessionState(sessions: [
            session("zulu", phase: .running, updatedAt: now),
            session("alpha", phase: .running, updatedAt: now.addingTimeInterval(-60)),
        ])

        func stations() throws -> [String] {
            try #require(model.islandBandLayout(width: 540, now: now)).scene.stations.map(\.id)
        }

        model.islandSessionGroup = .none
        let ungrouped = try stations()

        model.islandSessionGroup = .project
        let grouped = try stations()

        // Same sessions, different plots.
        #expect(Set(grouped) == Set(ungrouped))
        #expect(ungrouped == ["zulu", "alpha"])
        #expect(grouped == ["alpha", "zulu"])

        // The strip captions the plots, so it has to agree station for station
        // or cell *n* stops naming creature *n*.
        let band = try #require(model.islandBandLayout(width: 540, now: now))
        #expect(band.strip.cells.map(\.id) == grouped)
        #expect(band.scene.stations.map(\.id) == model.islandListSessions.map(\.id))
    }

    /// The island reuses `completedStaleThreshold` rather than adding a second
    /// idea of when a finished session goes quiet: a completed session moves
    /// between the "just done" and "idle" sections as the threshold changes,
    /// and the island's plots move with it because it reads the same list.
    @Test
    func theIslandReusesTheExistingStaleThreshold() throws {
        clearAppearanceDefaults()
        let model = AppModel()
        model.islandScene = .on
        model.islandSessionGroup = .state
        let now = Date()
        model.state = SessionState(sessions: [
            session("old", phase: .completed, updatedAt: now.addingTimeInterval(-10 * 60)),
            session("fresh", phase: .completed, updatedAt: now),
        ])

        func sections() -> [String] { model.islandSessionSections.map(\.id) }
        func stations() throws -> [String] {
            try #require(model.islandBandLayout(width: 540, now: now)).scene.stations.map(\.id)
        }

        model.completedStaleThreshold = .twoMinutes
        let tight = sections()
        let tightStations = try stations()

        model.completedStaleThreshold = .never
        let loose = sections()
        let looseStations = try stations()

        // Under a two-minute threshold the ten-minute-old session has gone
        // idle; under `never` nothing ever does, so both sit in "just done".
        #expect(tight == ["state-done", "state-idle"])
        #expect(loose == ["state-done"])

        // Every session keeps a plot under both thresholds. This is the
        // assertion that catches a second, hardcoded staleness rule: one that
        // disagreed with the preference would leave a completed session in
        // neither the "done" nor the "idle" section, and the island would
        // quietly lose a creature while the section list still looked sane.
        #expect(Set(tightStations) == ["old", "fresh"])
        #expect(Set(looseStations) == ["old", "fresh"])
    }

    // MARK: - The appearance-profile trap (see e79a005)

    /// `activeAppearanceProfile` is derived from live overlay placement. If a
    /// write can re-resolve that placement, the value goes into one profile and
    /// comes back from the other and the write silently does nothing. Both new
    /// preferences are checked, because the bug was in the shared write path.
    @Test
    func writingTheIslandPreferencesDoesNotChangeTheActiveProfile() {
        clearAppearanceDefaults()
        let model = AppModel()

        let before = model.activeAppearanceProfile
        model.islandScene = .on
        model.islandSceneHeight = .tall

        #expect(model.activeAppearanceProfile == before)
    }

    @Test
    func anIslandPreferenceWriteSurvivesBeingWritten() {
        clearAppearanceDefaults()
        let model = AppModel()

        model.islandScene = .on
        #expect(model.islandScene == .on)

        model.islandSceneHeight = .compact
        #expect(model.islandSceneHeight == .compact)
        // The first write must still be there after the second.
        #expect(model.islandScene == .on)
    }

    /// The two profiles keep their own island, exactly as they keep their own
    /// right slot — a MacBook and an external display are different amounts of
    /// room and the choice should not follow you between them.
    @Test
    func eachProfileKeepsItsOwnIsland() {
        clearAppearanceDefaults()
        let model = AppModel()

        model.updateAppearancePreferences(for: .notch) { $0.scene = .on }
        model.updateAppearancePreferences(for: .topBar) { $0.scene = .off }

        #expect(model.appearancePreferences(for: .notch).scene == .on)
        #expect(model.appearancePreferences(for: .topBar).scene == .off)
    }
}
