import AppKit
import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

struct IslandIdentityStripTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func session(
        _ id: String,
        tool: AgentTool = .claudeCode,
        phase: SessionPhase = .running,
        title: String = "",
        terminalApp: String? = nil,
        workspace: String = "island",
        startedMinutesAgo: Double = 12,
        updatedMinutesAgo: Double = 0
    ) -> AgentSession {
        AgentSession(
            id: id,
            title: title,
            tool: tool,
            phase: phase,
            summary: "",
            updatedAt: t0.addingTimeInterval(-updatedMinutesAgo * 60),
            firstSeenAt: t0.addingTimeInterval(-startedMinutesAgo * 60),
            jumpTarget: terminalApp.map {
                JumpTarget(terminalApp: $0, workspaceName: workspace, paneTitle: "p")
            }
        )
    }

    private func geode(for sessions: [AgentSession]) -> GeodeState {
        var state = GeodeState()
        state.reconcile(with: sessions, now: t0)
        return state
    }

    private func strip(
        _ sessions: [AgentSession],
        width: CGFloat = 540
    ) -> IslandIdentityStripLayout {
        IslandIdentityStripLayout(
            sessions: sessions,
            geode: geode(for: sessions),
            width: width,
            now: t0
        )
    }

    // MARK: - What the band contains

    @Test
    func anEmptyIslandHasNoCellsAndSaysSoDeliberately() {
        let band = strip([])
        #expect(band.cells.isEmpty)
        #expect(band.overflow == 0)
        #expect(band.isEmpty)
        #expect(!IslandIdentityStripLayout.emptyMessage.isEmpty)
    }

    @Test
    func oneCellPerVisibleSessionInTheOrderGiven() {
        let band = strip([session("c"), session("a"), session("b")])
        #expect(band.cells.map(\.id) == ["c", "a", "b"])
    }

    /// The scene collapses everything past the plot ceiling into a badge. The
    /// strip is the accessible mirror of the scene, so it has to account for
    /// those sessions rather than let them disappear between the two bands.
    @Test
    func sessionsPastThePlotCeilingAreCountedNotDropped() {
        let twelve = (0..<12).map { session("s\($0)") }
        let band = strip(twelve)
        #expect(band.cells.count == IslandSceneLayout.stationCapacity)
        #expect(band.overflow == 7)
        #expect(band.overflowBadge == "+7")
        #expect(band.overflowDescription?.contains("7") == true)
    }

    @Test
    func nothingIsHiddenWhenEverySessionFits() {
        let band = strip((0..<5).map { session("s\($0)") })
        #expect(band.overflow == 0)
        #expect(band.overflowBadge == nil)
        #expect(band.overflowDescription == nil)
    }

    /// The two bands are built from the same sessions and the same ceiling, so
    /// cell *n* is always the creature at station *n*. If they ever disagreed
    /// the strip would be captioning the wrong creature.
    @Test
    func theStripAndTheSceneAgreeOnWhoIsVisible() {
        let sessions = (0..<8).map { session("s\($0)") }
        let scene = IslandSceneLayout(sessions: sessions, geode: geode(for: sessions), width: 540)
        let band = strip(sessions)
        #expect(band.cells.map(\.id) == scene.stations.map(\.id))
        #expect(band.overflow == scene.overflow)
    }

    // MARK: - The four facts

    @Test
    func eachCellCarriesTheFactsThePictureCannotSay() {
        let band = strip([
            session("a", tool: .codex, terminalApp: "Ghostty", workspace: "open-island", startedMinutesAgo: 12),
        ])
        let cell = band.cells[0]
        #expect(cell.workspace == "open-island")
        #expect(cell.agent == "Codex")
        #expect(cell.hostLabel == "Ghostty")
        #expect(cell.elapsed == "12m")
    }

    /// The jump target is optional, and a session discovered before its host is
    /// known is exactly the session standing at the scene's `workshop`. A blank
    /// line there would read as a rendering fault rather than as an unknown.
    @Test
    func aSessionWithNoKnownHostSaysSoRatherThanShowingNothing() {
        let cell = strip([session("a")]).cells[0]
        #expect(cell.host == nil)
        #expect(!cell.hostLabel.isEmpty)
    }

    @Test
    func workspaceComesFromTheJumpTargetAndFallsBackToTheTitle() {
        let fromTarget = strip([session("a", terminalApp: "Ghostty", workspace: "repo")]).cells[0]
        #expect(fromTarget.workspace == "repo")

        let fromTitle = strip([session("b", title: "Claude Code · worktree")]).cells[0]
        #expect(fromTitle.workspace == "worktree")

        let neither = strip([session("c")]).cells[0]
        #expect(!neither.workspace.isEmpty)
    }

    /// Elapsed is how long the session has been going, not how long since its
    /// last event — a run you started this morning reads as hours old even when
    /// it printed a line a second ago.
    @Test
    func elapsedIsRuntimeNotTimeSinceTheLastEvent() {
        let cell = strip([session("a", startedMinutesAgo: 90, updatedMinutesAgo: 0)]).cells[0]
        #expect(cell.elapsed == "1h")
    }

    /// A finished session's number has to stop climbing, or the band keeps
    /// reporting work that is not happening.
    @Test
    func aFinishedSessionsElapsedStopsAtItsLastEvent() {
        let cell = strip([
            session("a", phase: .completed, startedMinutesAgo: 90, updatedMinutesAgo: 60),
        ]).cells[0]
        #expect(cell.elapsed == "30m")
    }

    // MARK: - The clarity rule

    /// The strip carries identity; the picture carries state. Attention is the
    /// single sanctioned exception, so every other visible field has to be
    /// phase-blind — same session, same words, whatever it is doing.
    @Test
    func noStateVocabularyLeaksIntoTheVisibleCell() {
        let cells = SessionPhase.allCases.map { phase in
            strip([
                session("a", terminalApp: "Ghostty", workspace: "repo", startedMinutesAgo: 12, updatedMinutesAgo: 0),
            ].map { var copy = $0; copy.phase = phase; return copy }).cells[0]
        }

        for cell in cells.dropFirst() {
            #expect(cell.workspace == cells[0].workspace)
            #expect(cell.agent == cells[0].agent)
            #expect(cell.hostLabel == cells[0].hostLabel)
            #expect(cell.elapsed == cells[0].elapsed)
        }
    }

    /// The one exception, and it must mirror the raised hand exactly — the
    /// strip is what a screen-reader user has instead of the gesture.
    @Test
    func attentionMirrorsTheRaisedHandPose() {
        let sessions = [
            session("running"),
            session("approval", phase: .waitingForApproval),
            session("answer", phase: .waitingForAnswer),
            session("done", phase: .completed),
        ]
        let scene = IslandSceneLayout(sessions: sessions, geode: geode(for: sessions), width: 540)
        let band = strip(sessions)

        for (cell, station) in zip(band.cells, scene.stations) {
            #expect(cell.needsAttention == (station.pose == .waiting))
        }
        #expect(band.cells.map(\.needsAttention) == [false, true, true, false])
    }

    // MARK: - Accessibility

    /// This band is the island's accessible surface: the scene is hidden from
    /// VoiceOver, so anything the picture shows has to be spoken here.
    @Test
    func everyCellSpeaksTheFactsAndTheStateTheSceneShows() {
        let cell = strip([
            session("a", tool: .geminiCLI, phase: .waitingForApproval, terminalApp: "Ghostty",
                    workspace: "open-island", startedMinutesAgo: 12),
        ]).cells[0]

        let spoken = cell.accessibilityDescription
        #expect(spoken.contains("open-island"))
        #expect(spoken.contains("Gemini CLI"))
        #expect(spoken.contains("Ghostty"))
        #expect(spoken.contains("12 minutes"))
        #expect(spoken.contains(CreaturePose.waiting.spokenState))
    }

    @Test
    func theSpokenStateDistinguishesEveryPoseTheSceneCanDraw() {
        let spoken = CreaturePose.allCases.map(\.spokenState)
        #expect(Set(spoken).count == CreaturePose.allCases.count)
        #expect(spoken.allSatisfy { !$0.isEmpty })
    }

    /// "12m" reads aloud as "twelve em". The badge is for a 26pt column; the
    /// sentence is for a voice, and they are two renderings of one decision.
    @Test
    func theBadgeAndTheSpokenFormNeverDisagreeAboutTheUnit() {
        let cases: [(TimeInterval, String, String)] = [
            (0, "<1m", "less than a minute"),
            (59, "<1m", "less than a minute"),
            (60, "1m", "1 minute"),
            (12 * 60, "12m", "12 minutes"),
            (3_599, "59m", "59 minutes"),
            (3_600, "1h", "1 hour"),
            (23 * 3_600, "23h", "23 hours"),
            (86_400, "1d", "1 day"),
            (3 * 86_400, "3d", "3 days"),
        ]

        for (seconds, badge, spoken) in cases {
            let grain = IslandDurationGrain(seconds: seconds)
            #expect(grain.badge == badge)
            #expect(grain.spoken == spoken)
        }
    }

    /// A clock that jumps backwards must not produce a negative duration.
    @Test
    func aBackwardsClockStillReadsAsAFreshSession() {
        #expect(IslandDurationGrain(seconds: -500).badge == "<1m")
    }

    // MARK: - Geometry

    /// 540pt on notch Macs, 520 on external, with and without a reserved
    /// overflow column: nothing may run past the band's edge.
    @Test
    func everyCellAndTheOverflowColumnFitInsideTheBand() {
        for width in [520.0, 540.0] as [CGFloat] {
            for count in 1...IslandSceneLayout.stationCapacity {
                for overflow in [0, 4] {
                    let cellWidth = IslandIdentityStripLayout.cellWidth(
                        count: count, width: width, overflow: overflow
                    )
                    var used = IslandIdentityStripLayout.horizontalInset * 2
                    used += cellWidth * CGFloat(count)
                    used += IslandIdentityStripLayout.cellSpacing * CGFloat(count - 1)
                    if overflow > 0 {
                        used += IslandIdentityStripLayout.overflowColumnWidth
                        used += IslandIdentityStripLayout.cellSpacing
                    }
                    #expect(used <= width + 0.001, "\(count) cells at \(width) overflow \(overflow)")
                    #expect(cellWidth > 0)
                }
            }
        }
    }

    @Test
    func reservingTheOverflowColumnActuallyNarrowsTheCells() {
        let full = IslandIdentityStripLayout.cellWidth(count: 5, width: 540, overflow: 0)
        let reserved = IslandIdentityStripLayout.cellWidth(count: 5, width: 540, overflow: 3)
        #expect(reserved < full)
    }

    /// A lone session must not stretch its caption across the whole panel — a
    /// four-word cell 500pt wide reads as a layout fault, and it would strand
    /// the elapsed badge half a panel away from the host it belongs to.
    @Test
    func aCellNeverGrowsWiderThanItsContentNeeds() {
        for count in 1...IslandSceneLayout.stationCapacity {
            let cellWidth = IslandIdentityStripLayout.cellWidth(count: count, width: 540, overflow: 0)
            #expect(cellWidth <= IslandIdentityStripLayout.maximumCellWidth + 0.001)
        }
    }

    /// The host line shares its row with the elapsed badge. If the badge's
    /// reservation ever ate the row the host would vanish entirely rather than
    /// truncate, which is the difference between graceful and broken.
    @Test
    func theHostKeepsRoomBesideTheElapsedBadge() {
        for width in [520.0, 540.0] as [CGFloat] {
            let band = IslandIdentityStripLayout(
                sessions: (0..<12).map { session("s\($0)") },
                geode: geode(for: (0..<12).map { session("s\($0)") }),
                width: width,
                now: t0
            )
            #expect(band.hostWidth > 0)
            #expect(band.hostWidth + IslandIdentityStripLayout.elapsedColumnWidth
                + IslandIdentityStripLayout.elapsedSpacing <= band.cellWidth + 0.001)
        }
    }

    @Test
    func theBandIsTheSameHeightWhateverItHolds() {
        #expect(strip([]).height == strip((0..<12).map { session("s\($0)") }).height)
    }
}

/// The measurable half: what the band claims about fitting text, checked
/// against real font metrics rather than asserted in a comment.
@MainActor
struct IslandIdentityStripFitTests {
    private func width(_ string: String, size: CGFloat, weight: NSFont.Weight, monospaced: Bool = false) -> CGFloat {
        let font = monospaced
            ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
            : NSFont.systemFont(ofSize: size, weight: weight)
        return (string as NSString).size(withAttributes: [.font: font]).width
    }

    private func lineHeight(_ size: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: size)
        return (font.ascender - font.descender + font.leading).rounded(.up)
    }

    /// The narrowest cell the band can produce — five sessions on an external
    /// display with the overflow column reserved.
    private var narrowestCellWidth: CGFloat {
        IslandIdentityStripLayout.cellWidth(count: 5, width: 520, overflow: 1)
    }

    /// The agent name is one of the two facts the picture is forbidden to carry
    /// alone, and six species cover ten agents — so a truncated agent name is a
    /// genuinely ambiguous one. Every name must survive the worst cell.
    @Test
    func everyAgentNameFitsTheNarrowestCellWithoutTruncating() {
        for tool in AgentTool.allCases {
            let measured = width(
                tool.displayName,
                size: IslandIdentityStripLayout.agentFontSize,
                weight: .medium
            )
            #expect(measured <= narrowestCellWidth, "\(tool.displayName) needs \(measured)pt")
        }
    }

    @Test
    func everyElapsedBadgeFitsItsReservedColumn() {
        let durations: [TimeInterval] = [0, 60, 59 * 60, 3_600, 23 * 3_600, 86_400, 99 * 86_400]
        for seconds in durations {
            let measured = width(
                IslandDurationGrain(seconds: seconds).badge,
                size: IslandIdentityStripLayout.hostFontSize,
                weight: .medium,
                monospaced: true
            )
            #expect(measured <= IslandIdentityStripLayout.elapsedColumnWidth)
        }
    }

    /// Three single-line rows and their padding, measured. The band is a fixed
    /// height, so text that no longer fits would be clipped rather than
    /// reflowed — this is what stops a font bump from silently doing that.
    @Test
    func threeSingleLineRowsFitTheFixedBandHeight() {
        let rows = lineHeight(IslandIdentityStripLayout.workspaceFontSize)
            + lineHeight(IslandIdentityStripLayout.agentFontSize)
            + lineHeight(IslandIdentityStripLayout.hostFontSize)
        let total = rows
            + IslandIdentityStripLayout.rowSpacing * 2
            + IslandIdentityStripLayout.verticalPadding * 2
        #expect(total <= IslandIdentityStripLayout.height)
    }
}
