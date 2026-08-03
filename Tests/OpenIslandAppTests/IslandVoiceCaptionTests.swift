import AppKit
import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

/// The one line a creature says when it finishes cleanly.
///
/// Everything worth asserting here is a decision — who speaks, for how long,
/// who wins when two finish at once, and where the plate is drawn — and a view
/// body cannot be asked any of them. So the caption is resolved into a value by
/// `IslandBandLayout` and these tests read that value.
struct IslandVoiceCaptionTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    /// Pinned rather than `.shared`: these tests assert on words, and `.shared`
    /// follows whatever language the machine running them is set to.
    private let lang = LanguageManager(language: .en)

    private func session(
        _ id: String,
        tool: AgentTool = .claudeCode,
        phase: SessionPhase = .running,
        startedMinutesAgo: Double = 8,
        workspace: String = "open-island"
    ) -> AgentSession {
        AgentSession(
            id: id,
            title: id,
            tool: tool,
            phase: phase,
            summary: "Editing AppModel.swift",
            updatedAt: t0,
            firstSeenAt: t0.addingTimeInterval(-startedMinutesAgo * 60),
            jumpTarget: JumpTarget(terminalApp: "Ghostty", workspaceName: workspace, paneTitle: "p")
        )
    }

    /// Through the event path, because `reconcile` cannot produce a fractured
    /// shard — it never claims an interrupt it did not see — and an interrupt is
    /// half of what these tests are about.
    private func geode(
        running: [String] = [],
        finished: [(String, Date)] = [],
        interrupted: [(String, Date)] = [],
        tool: AgentTool = .claudeCode
    ) -> GeodeState {
        var state = GeodeState()
        for id in running + finished.map(\.0) + interrupted.map(\.0) {
            state.apply(.sessionStarted(SessionStarted(
                sessionID: id,
                title: id,
                tool: tool,
                initialPhase: .running,
                summary: "working",
                timestamp: t0.addingTimeInterval(-8 * 60)
            )))
        }
        for (id, at) in finished {
            state.apply(.sessionCompleted(SessionCompleted(sessionID: id, summary: "done", timestamp: at)))
        }
        for (id, at) in interrupted {
            state.apply(.sessionCompleted(
                SessionCompleted(sessionID: id, summary: "stopped", timestamp: at, isInterrupt: true)
            ))
        }
        return state
    }

    private func band(
        _ sessions: [AgentSession],
        geode: GeodeState,
        now: Date? = nil,
        width: CGFloat = 540,
        sceneHeight: IslandSceneHeight = .standard,
        lang: LanguageManager? = nil
    ) -> IslandBandLayout {
        IslandBandLayout(
            sessions: sessions,
            geode: geode,
            selectedSessionID: nil,
            width: width,
            sceneHeight: sceneHeight,
            now: now ?? t0,
            lang: lang ?? self.lang
        )
    }

    // MARK: - Who speaks

    /// Beat 5: a clean completion is the moment the island exists for, and the
    /// line is the only part of that moment made of words.
    @Test
    func aCleanCompletionSpeaks() {
        let layout = band(
            [session("a", phase: .completed)],
            geode: geode(finished: [("a", t0)])
        )

        let voice = layout.voice
        #expect(voice?.sessionID == "a")
        #expect(voice?.text == lang.t(CreatureVoice.lineKey(species: .claude, sessionID: "a")))
        #expect(voice?.text.isEmpty == false)
    }

    /// The acceptance criterion, and the one that has to hold whatever else
    /// changes: an interrupted session is knocked over with scrap at its feet
    /// and says nothing at all.
    @Test
    func anInterruptNeverSpeaks() {
        let layout = band(
            [session("a", phase: .completed)],
            geode: geode(interrupted: [("a", t0)])
        )
        #expect(layout.voice == nil)
    }

    /// Said again against every species, because "never for an interrupt" is a
    /// property of the feature rather than of one fixture.
    @Test
    func noSpeciesSpeaksAfterAnInterrupt() {
        for tool in AgentTool.allCases {
            let layout = band(
                [session("a", tool: tool, phase: .completed)],
                geode: geode(interrupted: [("a", t0)], tool: tool)
            )
            #expect(layout.voice == nil, "\(tool.rawValue) spoke after being interrupted")
        }
    }

    /// A session still working has not finished, cleanly or otherwise. A line
    /// over its head would be the island claiming a result before there is one.
    @Test
    func aRunningSessionNeverSpeaks() {
        #expect(band([session("a")], geode: geode(running: ["a"])).voice == nil)
    }

    /// A session blocked on the human is asking a question, not reporting a
    /// result. The raised hand is the notification; a cheerful line beside it
    /// would compete with the one thing on the band that needs an answer.
    @Test
    func aSessionWaitingOnYouNeverSpeaks() {
        var state = geode(running: ["a"])
        state.apply(.permissionRequested(PermissionRequested(
            sessionID: "a",
            request: PermissionRequest(
                title: "Run command",
                summary: "Run `rm -rf build`",
                affectedPath: "/tmp/build"
            ),
            timestamp: t0
        )))

        #expect(band([session("a", phase: .waitingForApproval)], geode: state).voice == nil)
    }

    @Test
    func anIslandWithNothingFinishedIsSilent() {
        #expect(band([], geode: GeodeState()).voice == nil)
        #expect(band([session("a")], geode: geode(running: ["a"])).voice == nil)
    }

    // MARK: - For how long

    /// A completion is a moment, not a state, so the line has to end by itself.
    /// It borrows the shard's own linger window rather than inventing a second
    /// timer — the pill already uses that constant to decide how long a
    /// finished thing stays on screen, and two answers to one question is how
    /// the pill and the panel end up disagreeing.
    @Test
    func theLineGoesQuietWhenTheLingerWindowCloses() {
        let sessions = [session("a", phase: .completed)]
        let state = geode(finished: [("a", t0)])

        #expect(band(sessions, geode: state, now: t0).voice != nil)
        #expect(
            band(sessions, geode: state, now: t0.addingTimeInterval(GeodeState.lingerWindow - 1)).voice != nil
        )
        #expect(
            band(sessions, geode: state, now: t0.addingTimeInterval(GeodeState.lingerWindow + 1)).voice == nil
        )
    }

    /// The panel rebuilds this layout once a second. A line that moved between
    /// two ticks of the same window would read as a creature muttering.
    @Test
    func theLineIsTheSameOnEveryFrameOfTheWindow() {
        let sessions = [session("a", phase: .completed)]
        let state = geode(finished: [("a", t0)])
        let first = band(sessions, geode: state, now: t0).voice

        for second in stride(from: 0.0, through: GeodeState.lingerWindow - 1, by: 1) {
            #expect(band(sessions, geode: state, now: t0.addingTimeInterval(second)).voice == first)
        }
    }

    /// Two finishes inside one window is the case the design has to answer out
    /// loud. The band shows one line because there is one *current* moment: the
    /// newer completion takes it, and the older line is over rather than queued.
    /// Queuing would leave the island saying something that already happened.
    @Test
    func theNewestCompletionTakesTheLine() {
        let sessions = [session("a", phase: .completed), session("b", phase: .completed)]
        let state = geode(finished: [("a", t0), ("b", t0.addingTimeInterval(5))])

        #expect(band(sessions, geode: state, now: t0.addingTimeInterval(5)).voice?.sessionID == "b")
        // And once both windows have closed the band goes quiet rather than
        // falling back to whatever it was saying before.
        #expect(
            band(sessions, geode: state, now: t0.addingTimeInterval(GeodeState.lingerWindow + 6)).voice == nil
        )
    }

    /// An interrupt is not a completion, so it cannot take the line off a
    /// creature that earned one — it simply is not a candidate.
    @Test
    func anInterruptDoesNotSilenceACleanFinishBesideIt() {
        let sessions = [session("a", phase: .completed), session("b", phase: .completed)]
        let state = geode(finished: [("a", t0)], interrupted: [("b", t0.addingTimeInterval(5))])

        #expect(band(sessions, geode: state, now: t0.addingTimeInterval(5)).voice?.sessionID == "a")
    }

    // MARK: - Where it is drawn

    /// The line belongs to a creature, not to the band, so it stands over the
    /// plot that spoke it. Nothing in the string says which session it is —
    /// position is the whole of the attribution, which is why it is asserted.
    @Test
    func theLineStandsOverItsOwnCreature() {
        let sessions = (0..<3).map { session("s\($0)", phase: .completed) }
        let state = geode(finished: [("s1", t0)])
        let layout = band(sessions, geode: state)

        #expect(layout.voice?.center == layout.scene.stations[1].center)
    }

    /// The scene clips at its own edges, so a plate over the outermost plot
    /// would lose half its words. It slides inward instead — at most half a
    /// station pitch, so it still reads as belonging to the nearest creature.
    @Test
    func theLineNeverLeavesTheBand() throws {
        for width in [CGFloat(520), 540] {
            let sessions = (0..<5).map { session("s\($0)", phase: .completed) }
            for index in 0..<5 {
                let layout = band(
                    sessions,
                    geode: geode(finished: [("s\(index)", t0)]),
                    width: width
                )
                let voice = try #require(layout.voice)
                let half = IslandVoiceCaption.maximumWidth / 2

                #expect(voice.center - half >= IslandVoiceCaption.edgeInset)
                #expect(voice.center + half <= width - IslandVoiceCaption.edgeInset)
                #expect(abs(voice.center - layout.scene.stations[index].center)
                    <= IslandSceneLayout.pitch(width: width) / 2)
            }
        }
    }

    /// Above the creature's head and inside the band at every scene height —
    /// `compact` crops sky off the top, which is exactly where the plate goes.
    @Test
    func theLineSitsInsideTheBandAtEveryHeight() throws {
        for height in IslandSceneHeight.allCases {
            let layout = band(
                [session("a", phase: .completed)],
                geode: geode(finished: [("a", t0)]),
                sceneHeight: height
            )
            let voice = try #require(layout.voice)

            #expect(voice.centerY - IslandVoiceCaption.height / 2 >= 0)
            #expect(voice.centerY + IslandVoiceCaption.height / 2 <= layout.scene.height)
        }
    }

    /// The band is a fixed height so the session list below it does not jump.
    /// The line is drawn over the scene rather than under it for that reason:
    /// a row that appeared for 45 seconds would shove the list down and then
    /// pull it back up.
    @Test
    func theLineDoesNotChangeTheBandsHeight() {
        let sessions = [session("a", phase: .completed)]
        let silent = band(sessions, geode: geode(running: ["a"]))
        let speaking = band(sessions, geode: geode(finished: [("a", t0)]))

        #expect(speaking.voice != nil)
        #expect(speaking.height == silent.height)
        #expect(speaking.height == IslandBandLayout.height(width: 540, sceneHeight: .standard))
    }

    /// The scene draws five plots and collapses the rest into a count. A line
    /// over a creature nobody can see would point at nothing.
    @Test
    func aSessionPastThePlotCeilingNeverSpeaks() {
        let sessions = (0..<8).map { session("s\($0)", phase: .completed) }
        let layout = band(sessions, geode: geode(finished: [("s7", t0)]))

        #expect(layout.scene.overflow == 3)
        #expect(layout.voice == nil)
    }

    // MARK: - Translation

    /// Routed through `LanguageManager`, which is the acceptance criterion: the
    /// line is a key the layout resolves, so a locale is a file rather than a
    /// branch.
    @Test
    func theLineIsWhateverLanguageTheAppIsIn() {
        let sessions = [session("a", phase: .completed)]
        let state = geode(finished: [("a", t0)])

        let english = band(sessions, geode: state, lang: LanguageManager(language: .en)).voice?.text
        let simplified = band(sessions, geode: state, lang: LanguageManager(language: .zhHans)).voice?.text

        #expect(english != nil)
        #expect(simplified != nil)
        #expect(english != simplified)
    }

    /// Resolved when the layout is built, like every other string on the band,
    /// so the caption stays a plain `Equatable` value rather than something
    /// carrying a reference to a translation engine — and so a test can read
    /// the finished words instead of a key.
    @Test
    func theLineIsResolvedIntoTheLayoutRatherThanAtDrawTime() throws {
        let layout = band([session("a", phase: .completed)], geode: geode(finished: [("a", t0)]))
        let voice = try #require(layout.voice)

        #expect(!voice.text.hasPrefix("island.voice."))
    }

    // MARK: - Reading it without seeing it

    /// The plate hangs over the creature that spoke, and that is the whole of
    /// the visible attribution. VoiceOver has no position, so the spoken form
    /// has to name the speaker or it is an orphan sentence between the hidden
    /// scene and the strip.
    @Test
    func theSpokenFormNamesWhichSessionSpoke() throws {
        let sessions = [
            session("a", phase: .completed, workspace: "open-island"),
            session("b", phase: .completed, workspace: "other-repo"),
        ]
        let voice = try #require(
            band(sessions, geode: geode(finished: [("b", t0)])).voice
        )

        #expect(voice.speaker == "other-repo")
        #expect(voice.accessibilityLabel.contains("other-repo"))
        #expect(voice.accessibilityLabel.contains(voice.text))
    }

    /// Borrowed from the identity strip rather than resolved again, so the
    /// plate and the name under the creature can never disagree about which
    /// session this is — including when the name is the strip's own fallback
    /// for a session whose workspace nobody knows.
    @Test
    func theSpokenNameIsTheOneTheStripAlreadyPrints() throws {
        let sessions = [session("a", phase: .completed, workspace: "")]
        let layout = band(sessions, geode: geode(finished: [("a", t0)]))
        let voice = try #require(layout.voice)

        #expect(voice.speaker == layout.strip.cells[0].workspace)
        #expect(!voice.speaker.isEmpty)
    }
}

/// The plate is one line at a fixed maximum width and it does not wrap, so a
/// line that outgrew it would be truncated to an ellipsis — the creature would
/// be cut off mid-sentence. There are 216 of these strings across three
/// locales, which is exactly the number nobody is going to eyeball.
struct IslandVoiceCaptionFitTests {
    private func width(_ string: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: IslandVoiceCaption.fontSize, weight: .medium)
        return (string as NSString).size(withAttributes: [.font: font]).width
    }

    @Test
    func everyLineFitsOnOneLineInEveryLocale() {
        let available = IslandVoiceCaption.maximumWidth - IslandVoiceCaption.horizontalPadding * 2

        for locale in [LanguageManager.AppLanguage.en, .zhHans, .zhHant] {
            let lang = LanguageManager(language: locale)
            for key in CreatureVoice.allLineKeys {
                let line = lang.t(key)
                #expect(
                    width(line) <= available,
                    "\(key) in \(locale.rawValue) needs \(width(line))pt of \(available): \(line)"
                )
            }
        }
    }

    /// The plate is drawn a fixed height and the text is vertically centred in
    /// it, so a font that grew past the plate would clip rather than push it
    /// open.
    @Test
    func theLineFitsTheHeightOfItsPlate() {
        let font = NSFont.systemFont(ofSize: IslandVoiceCaption.fontSize, weight: .medium)
        #expect(font.ascender - font.descender <= IslandVoiceCaption.height)
    }
}
