import AppKit
import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

/// The slim row that replaces the island band.
///
/// Round 1's band cost 309pt to say what the session list's 12pt dot said
/// better. The claims here are mostly about that: how little the row costs, how
/// much of it is actually creature, and — the one that keeps the design honest
/// — that it says nothing the list already says.
@MainActor
struct IslandCompanionRowTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    /// Scene 211pt + identity strip 64pt + detail band 34pt, measured at the
    /// 760pt panel. Kept here rather than in the source because it is a fact
    /// about the design being replaced, not about the one being built.
    private let replacedBandHeight: CGFloat = 309

    /// The creature box was fixed at 58x54pt inside a 211pt scene. This is the
    /// number the new row has to beat, and beating it is the whole point.
    private let replacedCreatureFraction: CGFloat = 54.0 / 211.0

    private let lang = LanguageManager(language: .en)

    private func session(
        _ id: String,
        phase: SessionPhase = .running,
        tool: AgentTool = .claudeCode,
        title: String = "untitled"
    ) -> AgentSession {
        var session = AgentSession(
            id: id,
            title: title,
            tool: tool,
            origin: .live,
            attachmentState: .attached,
            phase: phase,
            summary: "",
            updatedAt: t0,
            firstSeenAt: t0
        )
        session.isProcessAlive = true
        return session
    }

    private func record(
        _ id: String,
        seconds: TimeInterval,
        endedAt: Date? = nil,
        interrupted: Bool = false,
        workspace: String? = nil,
        tool: AgentTool = .claudeCode
    ) -> SessionLogRecord {
        let end = endedAt ?? t0
        return SessionLogRecord(
            sessionID: id,
            tool: tool,
            workspace: workspace,
            startedAt: end.addingTimeInterval(-seconds),
            endedAt: end,
            wasInterrupted: interrupted,
            stallCount: 0
        )
    }

    private func row(
        sessions: [AgentSession] = [],
        records: [SessionLogRecord] = [],
        scale: CGFloat = 1,
        width: CGFloat = 540
    ) -> IslandCompanionRow {
        var geode = GeodeState()
        geode.reconcile(with: sessions, now: t0)
        return IslandCompanionRow(
            sessions: sessions,
            geode: geode,
            records: records,
            species: IslandCompanionRow.defaultSpecies,
            width: width,
            heightScale: scale,
            now: t0,
            lang: lang
        )
    }

    // MARK: - The space it costs

    /// The whole reason this round exists. 309pt of panel to say what a 12pt
    /// dot said better; the row has to be a different order of cost, not a trim.
    @Test
    func theRowCostsFarLessThanTheBandItReplaces() {
        let height = IslandCompanionRow.height(scale: 1)
        #expect(height < replacedBandHeight / 3)
        // And even the largest setting stays well under.
        #expect(IslandCompanionRow.height(scale: IslandSceneHeight.tall.scale) < 100)
    }

    /// Round 1's creature was 54pt adrift in a 211pt scene — a quarter of the
    /// band. Sitting the same sprite in a smaller row is not the fix on its own;
    /// it has to actually fill it.
    @Test
    func theCompanionIsLargeInFrame() {
        let row = row()
        let fraction = row.creatureHeight / row.height
        #expect(fraction > 0.7)
        #expect(fraction > replacedCreatureFraction * 2.5)
    }

    /// The height preference has to keep meaning something now that the scene it
    /// was written for is going away.
    @Test
    func aTallerRowIsActuallyTaller() {
        let heights = IslandSceneHeight.allCases.map { IslandCompanionRow.height(scale: $0.scale) }
        #expect(heights == heights.sorted())
        #expect(Set(heights).count == IslandSceneHeight.allCases.count)
    }

    /// The window is sized from the static formula and the row is drawn from an
    /// instance. The two disagreeing clips the row or leaves a gap, and nothing
    /// else in the app would notice.
    @Test
    func theHeightTheWindowReservesIsTheHeightTheRowDraws() {
        for scale in IslandSceneHeight.allCases.map(\.scale) {
            #expect(row(scale: scale).height == IslandCompanionRow.height(scale: scale))
        }
    }

    // MARK: - It reads the aggregate state, and decides nothing

    @Test
    func theRowWavesWhenASessionNeedsYou() {
        let sessions = [session("a"), session("b", phase: .waitingForApproval)]
        #expect(row(sessions: sessions).state == .waving)
    }

    @Test
    func theRowSleepsWithNothingOnTheList() {
        #expect(row().state == .asleep)
    }

    /// The row must not re-derive the state. Whatever the reducer says for a
    /// list, the row says for the same list.
    @Test
    func theRowNeverDisagreesWithTheReducer() {
        let sessions = [
            session("a", phase: .completed),
            session("b", phase: .running),
        ]
        var geode = GeodeState()
        geode.reconcile(with: sessions, now: t0)
        #expect(row(sessions: sessions).state == CompanionState(sessions: sessions, geode: geode))
    }

    // MARK: - The timer

    /// `SessionStats.totalRuntime` already computes this. The row renders it
    /// through `IslandDurationGrain`, the shared duration vocabulary, so the
    /// island has one rounding rather than a fourth formatter.
    @Test
    func theTimerIsTodaysRuntimeInTheSharedGrain() {
        let records = [
            record("a", seconds: 3_600),
            record("b", seconds: 3_600),
        ]
        #expect(row(records: records).workedToday == IslandDurationGrain(seconds: 7_200))
        #expect(row(records: records).workedBadge == "2h")
    }

    /// "Today" is today. A long run yesterday must not inflate this morning.
    @Test
    func yesterdaysWorkIsNotOnTodaysClock() {
        let yesterday = t0.addingTimeInterval(-86_400)
        let records = [record("old", seconds: 18_000, endedAt: yesterday)]
        #expect(row(records: records).workedToday == .underAMinute)
    }

    @Test
    func aDayWithNoFinishedWorkStillDrawsARow() {
        let row = row()
        #expect(row.workedBadge == IslandDurationGrain.underAMinute.badge)
        #expect(row.finishedToday == 0)
        #expect(row.interruptedToday == 0)
    }

    // MARK: - The tally

    @Test
    func theTallyCountsTodaysCleanFinishes() {
        let records = [
            record("a", seconds: 60),
            record("b", seconds: 60),
            record("c", seconds: 60, interrupted: true),
        ]
        #expect(row(records: records).finishedToday == 2)
        #expect(row(records: records).interruptedToday == 1)
    }

    /// An interrupt is not a failure worth shouting about, so it only appears
    /// when there was one. A permanent "0 stopped" would be a scold.
    @Test
    func aCleanDayShowsNoInterruptBadge() {
        #expect(row(records: [record("a", seconds: 60)]).stoppedBadge == nil)
        #expect(row(records: [record("a", seconds: 60, interrupted: true)]).stoppedBadge != nil)
    }

    // MARK: - It does not duplicate the list

    /// The design's central rule. The row sits directly above the session list;
    /// anything it says that the list already says is the round-1 failure
    /// happening again in less space.
    @Test
    func theRowNamesNoSessionNoWorkspaceAndNoAgent() {
        let sessions = [
            session("a", tool: .codex, title: "refactor the parser"),
            session("b", phase: .waitingForApproval, tool: .geminiCLI, title: "fix the flake"),
        ]
        let records = [record("a", seconds: 3_600, workspace: "open-vibe-island", tool: .codex)]
        let drawn = row(sessions: sessions, records: records)

        let text = [
            drawn.workedBadge,
            drawn.workedLabel,
            drawn.doneBadge,
            drawn.stoppedBadge,
            drawn.accessibilityDescription,
        ].compactMap { $0 }.joined(separator: " ")

        for forbidden in ["refactor the parser", "fix the flake", "open-vibe-island", "a", "b"]
        where forbidden.count > 2 {
            #expect(text.contains(forbidden) == false, "row leaked \(forbidden)")
        }
        for tool in AgentTool.allCases {
            #expect(text.contains(tool.displayName) == false, "row leaked \(tool.displayName)")
        }
    }

    // MARK: - Accessibility

    /// The picture carries the state, so a screen-reader user gets it from here
    /// or not at all.
    @Test(arguments: CompanionState.allCases)
    func everyStateIsSaidOutLoud(state: CompanionState) {
        let phrase = lang.t(state.spokenStateKey)
        #expect(phrase != state.spokenStateKey)
        #expect(phrase.isEmpty == false)
    }

    @Test
    func fourStatesHaveFourDistinctKeys() {
        let keys = CompanionState.allCases.map(\.spokenStateKey)
        #expect(Set(keys).count == CompanionState.allCases.count)
    }

    @Test
    func theRowSpeaksTheStateThePictureShows() {
        let waving = row(sessions: [session("a", phase: .waitingForAnswer)])
        #expect(waving.accessibilityDescription.contains(lang.t(CompanionState.waving.spokenStateKey)))
        #expect(row().accessibilityDescription.contains(lang.t(CompanionState.asleep.spokenStateKey)))
    }

    // MARK: - It can be read

    /// `V6Palette.paper` at `alpha` over `V6Palette.ink`, which is what the
    /// panel actually composites — an opacity is not a colour until it has been
    /// blended against what is behind it.
    private func blendedPaper(alpha: Double) -> CreatureColor {
        let paper = (r: 0xf1, g: 0xea, b: 0xd9)
        let ink = (r: 0x0d, g: 0x0d, b: 0x0f)
        func mix(_ over: Int, _ under: Int) -> UInt8 {
            UInt8((Double(over) * alpha + Double(under) * (1 - alpha)).rounded())
        }
        return CreatureColor(
            red: mix(paper.r, ink.r),
            green: mix(paper.g, ink.g),
            blue: mix(paper.b, ink.b)
        )
    }

    /// Every word on the row clears WCAG AA for body text.
    ///
    /// The island's other bands go down to 0.38 paper and get away with it,
    /// because a creature stands beside them carrying the same fact. This row
    /// has no such redundancy: "worked today" is the only thing that says what
    /// the big number counts, so a tier that is merely *visible* is not enough.
    @Test(arguments: [
        IslandCompanionRow.primaryTextOpacity,
        IslandCompanionRow.secondaryTextOpacity,
        IslandCompanionRow.tertiaryTextOpacity,
    ])
    func everyTextTierClearsTheContrastFloor(opacity: Double) {
        let ratio = CreatureColor.contrastRatio(
            blendedPaper(alpha: opacity),
            CreatureColor(red: 0x0d, green: 0x0d, blue: 0x0f)
        )
        #expect(ratio >= 4.5, "\(opacity) paper on ink is \(ratio):1")
    }

    /// Three tiers, actually distinct, in the order the eye should read them.
    @Test
    func theTextTiersAreOrderedAndDistinct() {
        let tiers = [
            IslandCompanionRow.tertiaryTextOpacity,
            IslandCompanionRow.secondaryTextOpacity,
            IslandCompanionRow.primaryTextOpacity,
        ]
        #expect(tiers == tiers.sorted())
        #expect(Set(tiers).count == 3)
    }

    // MARK: - It fits

    private func measure(_ text: String, size: CGFloat, weight: NSFont.Weight, rounded: Bool = false) -> CGFloat {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        let font: NSFont = {
            guard rounded, let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
            return NSFont(descriptor: descriptor, size: size) ?? base
        }()
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    /// The row is one line and the panel is as narrow as 360pt, so a locale
    /// whose words are longer has to be *measured* rather than assumed. Chinese
    /// "今日工作时长" is the case that would go first, and truncation here would
    /// silently eat the label that says what the number means.
    ///
    /// Worst case on purpose: a two-digit tally, a two-character duration and
    /// an interrupt badge present, which is the widest a real day gets.
    @Test(arguments: [LanguageManager.AppLanguage.en, .zhHans, .zhHant])
    func theRowFitsTheNarrowestPanelInEveryLocale(language: LanguageManager.AppLanguage) {
        let lang = LanguageManager(language: language)
        let records = (0..<99).map { record("c\($0)", seconds: 3_600) }
            + (0..<99).map { record("i\($0)", seconds: 60, interrupted: true) }

        var geode = GeodeState()
        let row = IslandCompanionRow(
            sessions: [],
            geode: geode,
            records: records,
            species: IslandCompanionRow.defaultSpecies,
            width: 360,
            heightScale: 1,
            now: t0,
            lang: lang
        )
        geode.reconcile(with: [], now: t0)

        let creature = row.creatureHeight * 1.08
        let timer = max(
            measure(row.workedBadge, size: 21, weight: .semibold, rounded: true),
            measure(row.workedLabel, size: 10, weight: .medium)
        )
        let tally = max(
            measure(row.doneBadge, size: 11, weight: .medium),
            measure(row.stoppedBadge ?? "", size: 11, weight: .medium)
        )

        // Three gaps at the stack's spacing, plus the spacer's own floor.
        let required = IslandCompanionRow.horizontalInset * 2
            + creature
            + IslandCompanionRow.contentSpacing * 3
            + timer
            + 8
            + tally

        #expect(required <= 360, "\(language.rawValue) needs \(required)pt")
    }

    // MARK: - Artwork

    /// `asleep` has no session behind it and so no pose to borrow. `side` is the
    /// calm profile that ships for all six characters and that nothing drew
    /// before now — exactly the gap it was cut for.
    @Test
    func theCompanionDrawsACalmProfileWhenNothingIsRunning() {
        #expect(CreatureSprite.name(for: .claude, state: .asleep) == "claude-side")
        #expect(CreatureSprite.name(for: .claude, state: .waving) == "claude-waiting")
        #expect(CreatureSprite.name(for: .claude, state: .working) == "claude-working")
        #expect(CreatureSprite.name(for: .claude, state: .resting) == "claude-holding")
    }

    /// The row draws three of the four states through `CreatureView`, keyed by
    /// `CompanionState.pose`, and the sprite table names them independently.
    /// Those two agreeing is what stops the companion and the pill's creature
    /// from being two characters that happen to look alike.
    @Test(arguments: CreatureSpecies.allCases)
    func theBorrowedPoseAndTheSpriteTableAgree(species: CreatureSpecies) throws {
        for state in CompanionState.allCases {
            guard let pose = state.pose else {
                #expect(state == .asleep)
                continue
            }
            #expect(
                CreatureSprite.name(for: species, state: state)
                    == CreatureSprite.name(for: species, pose: pose)
            )
        }
    }

    /// Every character has a frame for every aggregate state, or some user's
    /// companion vanishes in one of the four.
    @Test(arguments: CreatureSpecies.allCases)
    func everyCharacterHasArtForEveryState(species: CreatureSpecies) {
        for state in CompanionState.allCases {
            let name = CreatureSprite.name(for: species, state: state)
            #expect(
                Bundle.appResources.url(forResource: name, withExtension: "png") != nil,
                "missing \(name).png"
            )
        }
    }
}
