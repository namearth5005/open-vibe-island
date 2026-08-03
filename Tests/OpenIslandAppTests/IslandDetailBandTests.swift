import AppKit
import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

/// Clicking a creature is a toggle, and a toggle is the one part of this
/// feature that is worth asserting rather than describing: "click again to
/// deselect" is a claim about a transition, and a view body cannot be asked
/// what it would do next.
struct IslandSelectionTests {
    @Test
    func clickingACreatureSelectsThatSession() {
        #expect(IslandSelection.toggled(current: nil, tapped: "a") == "a")
    }

    @Test
    func clickingTheSelectedCreatureAgainClearsTheSelection() {
        #expect(IslandSelection.toggled(current: "a", tapped: "a") == nil)
    }

    /// Two creatures, two clicks: the second must move the selection rather
    /// than clear it, or picking your way along the band would take twice the
    /// clicks and blink the detail row on every step.
    @Test
    func clickingADifferentCreatureMovesTheSelectionInsteadOfClearingIt() {
        #expect(IslandSelection.toggled(current: "a", tapped: "b") == "b")
    }

    @Test
    func selectingAndDeselectingTheSameCreatureReturnsToWhereItStarted() {
        let once = IslandSelection.toggled(current: nil, tapped: "a")
        #expect(IslandSelection.toggled(current: once, tapped: "a") == nil)
    }
}

/// The island writes selection into the app's own `selectedSessionID` rather
/// than keeping a private copy, so the island and the session list can never
/// disagree about which session is selected.
@MainActor
@Suite(.serialized)
struct IslandSelectionAppModelTests {
    private func session(_ id: String, updatedAt: Date) -> AgentSession {
        AgentSession(
            id: id,
            title: id,
            tool: .claudeCode,
            phase: .running,
            summary: "",
            updatedAt: updatedAt,
            firstSeenAt: updatedAt
        )
    }

    @Test
    func clickingACreatureWritesTheAppsOwnSelection() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        model.state = SessionState(sessions: [session("a", updatedAt: now), session("b", updatedAt: now)])

        model.toggleIslandSelection(sessionID: "b")
        #expect(model.selectedSessionID == "b")
        #expect(model.focusedSession?.id == "b")
    }

    @Test
    func clickingTheSelectedCreatureAgainClearsTheAppsOwnSelection() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        model.state = SessionState(sessions: [session("a", updatedAt: now)])

        model.toggleIslandSelection(sessionID: "a")
        model.toggleIslandSelection(sessionID: "a")
        #expect(model.selectedSessionID == nil)
    }
}

struct IslandDetailBandTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func session(
        _ id: String,
        tool: AgentTool = .claudeCode,
        phase: SessionPhase = .running,
        summary: String = "Editing AppModel.swift",
        permission: PermissionRequest? = nil,
        question: QuestionPrompt? = nil,
        startedMinutesAgo: Double = 26,
        updatedMinutesAgo: Double = 0,
        workspace: String = "open-island"
    ) -> AgentSession {
        AgentSession(
            id: id,
            title: id,
            tool: tool,
            phase: phase,
            summary: summary,
            updatedAt: t0.addingTimeInterval(-updatedMinutesAgo * 60),
            firstSeenAt: t0.addingTimeInterval(-startedMinutesAgo * 60),
            permissionRequest: permission,
            questionPrompt: question,
            jumpTarget: JumpTarget(terminalApp: "Ghostty", workspaceName: workspace, paneTitle: "p")
        )
    }

    /// Mirrors what `AppModel` does on every session change, so the shards these
    /// tests read are the ones production would hand the band.
    private func geode(for sessions: [AgentSession]) -> GeodeState {
        var state = GeodeState()
        state.reconcile(with: sessions, now: t0)
        return state
    }

    private func band(
        _ sessions: [AgentSession],
        selecting id: String?,
        geode: GeodeState? = nil,
        width: CGFloat = 540
    ) -> IslandDetailBand {
        IslandDetailBand(
            sessions: sessions,
            geode: geode ?? self.geode(for: sessions),
            selectedSessionID: id,
            width: width,
            now: t0
        )
    }

    // MARK: - What the band is looking at

    @Test
    func nothingIsSelectedUntilSomethingIs() {
        let empty = band([session("a")], selecting: nil)
        #expect(empty.detail == nil)
        #expect(empty.isEmpty)
        #expect(!IslandDetailBand.emptyMessage.isEmpty)
    }

    /// The band follows the selection, not the running order — otherwise
    /// clicking the third creature would describe the first one.
    @Test
    func theBandDescribesTheSelectedSessionNotTheFirstOne() {
        let sessions = [session("a"), session("b"), session("c")]
        #expect(band(sessions, selecting: "c").detail?.id == "c")
    }

    /// `selectedSessionID` is the whole app's selection, so it can point at a
    /// session the island never drew — one past the plot ceiling, or one that
    /// has since gone. Describing it anyway would caption a creature that is
    /// not on the band.
    @Test
    func aSelectionThatIsNotOnTheIslandDescribesNothing() {
        let sessions = (0..<8).map { session("s\($0)") }
        #expect(band(sessions, selecting: "s7").detail == nil)
        #expect(band(sessions, selecting: "nobody").detail == nil)
    }

    // MARK: - The pending question

    @Test
    func aPermissionRequestIsWhatTheBandLeadsWith() {
        let request = PermissionRequest(
            title: "Run command",
            summary: "Run `rm -rf build`",
            affectedPath: "/tmp/build"
        )
        let detail = band(
            [session("a", phase: .waitingForApproval, permission: request)],
            selecting: "a"
        ).detail

        #expect(detail?.pendingQuestion == "Run `rm -rf build`")
        #expect(detail?.headline == "Run `rm -rf build`")
    }

    @Test
    func aQuestionPromptIsWhatTheBandLeadsWith() {
        let prompt = QuestionPrompt(title: "Which branch should I target?", options: ["main", "dev"])
        let detail = band(
            [session("a", phase: .waitingForAnswer, question: prompt)],
            selecting: "a"
        ).detail

        #expect(detail?.pendingQuestion == "Which branch should I target?")
        #expect(detail?.headline == "Which branch should I target?")
    }

    /// A running agent is not asking you anything, and saying it is would turn
    /// the band into a second, permanently-lit notification.
    @Test
    func aRunningSessionHasNoPendingQuestion() {
        let detail = band([session("a", summary: "Editing AppModel.swift")], selecting: "a").detail
        #expect(detail?.pendingQuestion == nil)
        #expect(detail?.headline == "Editing AppModel.swift")
    }

    /// The band leads with the same words the panel's own cards use, so a
    /// session cannot describe itself one way in the island and another way in
    /// the list directly below it.
    @Test
    func theHeadlineNeverDisagreesWithThePanelsOwnSurfaceText() {
        let request = PermissionRequest(title: "t", summary: "Run `rm -rf build`", affectedPath: "")
        let sessions = [
            session("a"),
            session("b", phase: .waitingForApproval, permission: request),
            session("c", phase: .completed, summary: "Done"),
        ]

        for one in sessions {
            let detail = band(sessions, selecting: one.id).detail
            #expect(detail?.headline == one.spotlightPrimaryText)
        }
    }

    /// A blank row reads as a rendering fault rather than as an unknown — the
    /// same failure the identity strip's "Unknown host" avoids. The pose is
    /// already the island's word for what a session is doing, so it is the
    /// fallback rather than a new vocabulary.
    @Test
    func theHeadlineFallsBackToTheSpokenPoseRatherThanGoingBlank() {
        let detail = band([session("a", summary: "   ")], selecting: "a").detail
        #expect(detail?.headline == CreaturePose.working.spokenState)
    }

    // MARK: - The three numbers

    /// Runtime is the same measurement the identity strip's badge makes. Two
    /// renderings of one number is fine; two numbers is a bug.
    @Test
    func runtimeIsTheSameElapsedTheIdentityStripShows() {
        let sessions = [session("a", startedMinutesAgo: 26)]
        let detail = band(sessions, selecting: "a").detail
        let cell = IslandIdentityStripLayout(
            sessions: sessions, geode: geode(for: sessions), width: 540, now: t0
        ).cells[0]

        #expect(detail?.runtime == cell.runtime)
        #expect(detail?.runtimeBadge == "26m")
    }

    /// Wait time is how long the human has kept this session standing there —
    /// the geode's own frozen accounting, not a second stopwatch.
    @Test
    func waitTimeIsHowLongTheHumanHasKeptItWaiting() {
        let waiting = session("a", phase: .waitingForApproval, updatedMinutesAgo: 4)
        let detail = band([waiting], selecting: "a").detail

        #expect(detail?.waiting?.badge == "4m")
        #expect(detail?.stallCount == 1)
    }

    /// Frozen time accrues across gates: two answered stalls are two entries in
    /// one total, so the band can say "you have cost this session 9 minutes"
    /// rather than only ever reporting the current one.
    @Test
    func waitTimeAddsUpEveryGateNotJustTheCurrentOne() {
        var state = GeodeState()
        state.apply(.sessionStarted(SessionStarted(
            sessionID: "a", title: "a", tool: .claudeCode, summary: "", timestamp: t0.addingTimeInterval(-1_800)
        )))
        state.apply(.permissionRequested(PermissionRequested(
            sessionID: "a",
            request: PermissionRequest(title: "t", summary: "s", affectedPath: ""),
            timestamp: t0.addingTimeInterval(-1_500)
        )))
        state.apply(.actionableStateResolved(ActionableStateResolved(
            sessionID: "a", summary: "", timestamp: t0.addingTimeInterval(-1_200)
        )))
        state.apply(.questionAsked(QuestionAsked(
            sessionID: "a",
            prompt: QuestionPrompt(title: "q", options: []),
            timestamp: t0.addingTimeInterval(-540)
        )))
        state.apply(.actionableStateResolved(ActionableStateResolved(
            sessionID: "a", summary: "", timestamp: t0.addingTimeInterval(-300)
        )))

        let detail = band([session("a")], selecting: "a", geode: state).detail
        // 300s at the first gate plus 240s at the second.
        #expect(detail?.waiting?.badge == "9m")
        #expect(detail?.stallCount == 2)
    }

    /// A session still standing there has to keep counting, or the number
    /// freezes at the moment it was blocked and stops being a reason to act.
    @Test
    func aSessionStillWaitingKeepsCounting() {
        var state = GeodeState()
        state.apply(.sessionStarted(SessionStarted(
            sessionID: "a", title: "a", tool: .claudeCode, summary: "", timestamp: t0.addingTimeInterval(-1_800)
        )))
        state.apply(.permissionRequested(PermissionRequested(
            sessionID: "a",
            request: PermissionRequest(title: "t", summary: "s", affectedPath: ""),
            timestamp: t0.addingTimeInterval(-420)
        )))

        let detail = band([session("a")], selecting: "a", geode: state).detail
        #expect(detail?.waiting?.badge == "7m")
    }

    /// "Under a minute" and "never asked you for anything" are different facts,
    /// and rendering the second as the first would invent a wait that never
    /// happened.
    @Test
    func aSessionThatNeverStalledReportsNoWaitRatherThanZero() {
        let detail = band([session("a")], selecting: "a").detail
        #expect(detail?.stallCount == 0)
        #expect(detail?.waiting == nil)
        #expect(detail?.waitingBadge == IslandDetailBand.absentBadge)
    }

    @Test
    func stallCountIsSpokenAsAnAmountNotAGlyph() {
        #expect(IslandSessionDetail.spokenStalls(0) == "never blocked")
        #expect(IslandSessionDetail.spokenStalls(1) == "blocked once")
        #expect(IslandSessionDetail.spokenStalls(4) == "blocked 4 times")
    }

    // MARK: - One pose, one source

    /// The scene, the strip and this band draw the same session three times.
    /// All three read the pose from the geode, so they cannot report different
    /// states for one creature.
    @Test
    func poseComesFromTheGeodeExactlyAsTheSceneReadsIt() {
        let sessions = [
            session("running"),
            session("approval", phase: .waitingForApproval),
            session("answer", phase: .waitingForAnswer),
            session("done", phase: .completed),
        ]
        let shared = geode(for: sessions)
        let scene = IslandSceneLayout(sessions: sessions, geode: shared, width: 540)

        for station in scene.stations {
            let detail = band(sessions, selecting: station.id, geode: shared).detail
            #expect(detail?.pose == station.pose)
        }
    }

    // MARK: - Accessibility

    /// The scene is hidden from VoiceOver and the strip speaks identity, so
    /// every number this band puts on screen has to have a spoken counterpart
    /// here or it exists for sighted users only.
    @Test
    func theBandSpeaksEveryNumberItShows() {
        let request = PermissionRequest(title: "t", summary: "Run `rm -rf build`", affectedPath: "")
        let detail = band(
            [session("a", phase: .waitingForApproval, permission: request, startedMinutesAgo: 26, updatedMinutesAgo: 4)],
            selecting: "a"
        ).detail

        let spoken = detail?.accessibilityDescription ?? ""
        #expect(spoken.contains("Run `rm -rf build`"))
        #expect(spoken.contains("4 minutes"))
        #expect(spoken.contains("26 minutes"))
        #expect(spoken.contains(IslandSessionDetail.spokenStalls(1)))
    }

    @Test
    func aSessionThatNeverStalledSaysSoOutLoud() {
        let spoken = band([session("a")], selecting: "a").detail?.accessibilityDescription ?? ""
        #expect(spoken.contains(IslandSessionDetail.spokenStalls(0)))
        // A wait of zero must be absent, not rendered as "less than a minute".
        #expect(!spoken.contains(IslandDurationGrain(seconds: 0).spoken))
    }

    // MARK: - Geometry

    /// The band sits between the strip and the session list. A height that
    /// depended on its contents would shove the list up and down every time a
    /// question arrived.
    @Test
    func theBandIsTheSameHeightWhateverItHolds() {
        #expect(band([session("a")], selecting: nil).height == band([session("a")], selecting: "a").height)
    }

    /// 540pt on notch Macs, 520 on external. The headline is the only elastic
    /// thing on the row, so if the metric columns ever ate it the question
    /// would vanish rather than truncate.
    @Test
    func theHeadlineKeepsRoomBesideTheThreeMetrics() {
        for width in [520.0, 540.0] as [CGFloat] {
            let row = band([session("a")], selecting: "a", width: width)
            #expect(row.headlineWidth > 0)

            let used = IslandDetailBand.horizontalInset * 2
                + row.headlineWidth
                + IslandDetailBand.metricColumnWidth * 3
                + IslandDetailBand.metricSpacing * 3
            #expect(used <= width + 0.001)
        }
    }
}

/// The measurable half: what the row claims about fitting numbers, checked
/// against real font and symbol metrics rather than asserted in a comment.
@MainActor
struct IslandDetailBandFitTests {
    private func badgeWidth(_ string: String) -> CGFloat {
        let font = NSFont.monospacedSystemFont(
            ofSize: IslandDetailBand.metricFontSize,
            weight: .medium
        )
        return (string as NSString).size(withAttributes: [.font: font]).width
    }

    private func symbolWidth(_ name: String) -> CGFloat? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 8, weight: .medium)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)?
            .size.width
    }

    /// Each metric is a glyph and a number in a fixed 30pt column. A duration
    /// that outgrew it would be clipped rather than truncated, which turns
    /// "99d" into a different, wrong number.
    @Test
    func everyGlyphAndNumberFitsItsReservedColumn() {
        let badges = ["<1m", "59m", "23h", "99d", "0", "99"]

        for symbol in IslandDetailBandView.metricSymbols {
            let glyph = symbolWidth(symbol)
            #expect(glyph != nil, "\(symbol) is not a symbol this OS ships")

            for badge in badges {
                let measured = (glyph ?? 0) + IslandDetailBand.glyphSpacing + badgeWidth(badge)
                #expect(
                    measured <= IslandDetailBand.metricColumnWidth,
                    "\(symbol) \(badge) needs \(measured)pt"
                )
            }
        }
    }
}
