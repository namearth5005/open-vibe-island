import Foundation
import Testing
@testable import OpenIslandCore

/// Which line a finished creature speaks.
///
/// The choice is a pure function of the session, which is the whole point: a
/// line that was re-rolled on every frame would flicker under the panel's
/// one-second timeline, and a line that was re-rolled on every launch would
/// stop being *that session's* line at all.
struct CreatureVoiceTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func started(_ id: String, tool: AgentTool = .claudeCode, at: Date) -> AgentEvent {
        .sessionStarted(
            SessionStarted(
                sessionID: id,
                title: id,
                tool: tool,
                initialPhase: .running,
                summary: "working",
                timestamp: at
            )
        )
    }

    private func completed(_ id: String, at: Date, interrupt: Bool = false) -> AgentEvent {
        .sessionCompleted(
            SessionCompleted(
                sessionID: id,
                summary: "done",
                timestamp: at,
                isInterrupt: interrupt ? true : nil
            )
        )
    }

    /// Built through the event path rather than by hand, so what these tests
    /// read is the shard production would hand the island.
    private func shard(
        _ id: String,
        tool: AgentTool = .claudeCode,
        finish: Bool = true,
        interrupt: Bool = false
    ) -> GeodeShard {
        var state = GeodeState()
        state.apply(started(id, tool: tool, at: t0))
        if finish {
            state.apply(completed(id, at: t0.addingTimeInterval(60), interrupt: interrupt))
        }
        return state.shard(id: id)!
    }

    // MARK: - The shape of the vocabulary

    /// The design asks for roughly twelve lines per *family*, and a family is
    /// exactly a `CreatureSpecies` — six bodies, not ten tools. Writing twelve
    /// per tool would give the four Claude Code forks their own voices while
    /// the taxonomy says they are one creature wearing different markings.
    @Test
    func everySpeciesHasTwelveLines() {
        for species in CreatureSpecies.allCases {
            #expect(CreatureVoice.lineKeys(for: species).count == CreatureVoice.linesPerSpecies)
        }
        #expect(CreatureVoice.linesPerSpecies == 12)
        #expect(CreatureVoice.allLineKeys.count == 72)
    }

    /// A duplicated key is a line that can never be reached and a translation
    /// nobody will notice is missing.
    @Test
    func everyLineKeyIsItsOwn() {
        #expect(Set(CreatureVoice.allLineKeys).count == CreatureVoice.allLineKeys.count)
    }

    /// Two species sharing a line would undo the reason the lines exist. The
    /// keys are namespaced by species, so this is really a check that nothing
    /// namespaced them by accident.
    @Test
    func everyLineBelongsToExactlyOneSpecies() {
        for species in CreatureSpecies.allCases {
            for key in CreatureVoice.lineKeys(for: species) {
                #expect(key.hasPrefix("island.voice.\(species.rawValue)."))
            }
        }
    }

    // MARK: - Deterministic, across processes

    /// The claim that matters, and the only way to make it in a test: literal
    /// expectations.
    ///
    /// Re-calling the function inside one test proves nothing about stability —
    /// `hashValue` would pass that too, because Swift seeds `Hasher` once per
    /// process and it stays put for the run. These literals were computed from
    /// FNV-1a and SplitMix64 by hand, outside Swift, and every `swift test` is a
    /// fresh process: a seeding scheme that moved between launches could not
    /// keep matching them.
    @Test
    func theSameSessionSpeaksTheSameLineInEveryProcess() {
        #expect(CreatureVoice.lineKey(species: .claude, sessionID: "a") == "island.voice.claude.03")
        #expect(CreatureVoice.lineKey(species: .claude, sessionID: "b") == "island.voice.claude.04")
        #expect(CreatureVoice.lineKey(species: .codex, sessionID: "session-1") == "island.voice.codex.09")
        #expect(CreatureVoice.lineKey(species: .gemini, sessionID: "open-island") == "island.voice.gemini.07")
        #expect(
            CreatureVoice.lineKey(species: .openCode, sessionID: "claude-abc-123")
                == "island.voice.openCode.06"
        )
    }

    /// The seed is the session ID and nothing else — not the species, not the
    /// clock, not the pose. Two creatures of different species finishing the
    /// same session cannot happen, but the island rebuilds its layout every
    /// second and must land on the same line each time.
    @Test
    func theLineDoesNotMoveBetweenFrames() {
        let first = CreatureVoice.lineKey(for: shard("s1"))
        for _ in 0..<50 {
            #expect(CreatureVoice.lineKey(for: shard("s1")) == first)
        }
    }

    /// Twelve lines that only ever produce three of themselves would be nine
    /// lines of dead translation. Five hundred sessions is far more than a user
    /// will ever have, which is the point: the modulo has to reach the whole
    /// vocabulary, not most of it.
    @Test
    func everyLineIsReachable() {
        for species in CreatureSpecies.allCases {
            let spoken = Set((0..<500).map { CreatureVoice.lineKey(species: species, sessionID: "s\($0)") })
            #expect(spoken.count == CreatureVoice.linesPerSpecies, "\(species) only ever speaks \(spoken.count)")
        }
    }

    /// The reward object is drawn from the same session ID through the same
    /// generator, so an unsalted seed would lock the two together: the object
    /// index would be the line index modulo the pool size, forever. A user who
    /// saw a coin would then only ever hear three of that species' twelve
    /// lines. This asserts the pairing is not that function.
    @Test
    func theLineIsNotLockedToTheRewardObject() {
        var sawADifferentPairing = false

        for index in 0..<200 {
            let id = "s\(index)"
            let record = SessionLogRecord(
                sessionID: id,
                tool: .claudeCode,
                startedAt: t0,
                endedAt: t0.addingTimeInterval(60),
                wasInterrupted: false,
                stallCount: 0
            )
            let rarity = RewardRarity.rarity(for: record)!
            let pool = RewardObject.pool(for: rarity)
            let objectIndex = pool.firstIndex(of: RewardObject.yield(for: record))!

            let key = CreatureVoice.lineKey(species: .claude, sessionID: id)
            let lineIndex = CreatureVoice.lineKeys(for: .claude).firstIndex(of: key)!

            if objectIndex != lineIndex % pool.count { sawADifferentPairing = true }
        }

        #expect(sawADifferentPairing, "the voice line is just the reward object's draw wearing a hat")
    }

    // MARK: - Never for an interrupt

    /// Beat 6 of the design is a creature knocked over with scrap at its feet.
    /// It has nothing to say, and the *function* is what has to know that —
    /// pushing the rule out to the caller would leave every future call site
    /// free to get it wrong.
    @Test
    func anInterruptedSessionSaysNothing() {
        for species in CreatureSpecies.allCases {
            for tool in AgentTool.allCases where CreatureSpecies(tool: tool) == species {
                #expect(CreatureVoice.lineKey(for: shard("s-\(tool.rawValue)", tool: tool, interrupt: true)) == nil)
            }
        }
    }

    /// A session still running has not finished cleanly either. Only the pose
    /// the design calls `holding` — reward held overhead, waiting to be
    /// collected — speaks.
    @Test
    func onlyACleanCompletionSpeaks() {
        #expect(CreatureVoice.lineKey(for: shard("running", finish: false)) == nil)
        #expect(CreatureVoice.lineKey(for: shard("clean")) != nil)
        #expect(CreatureVoice.lineKey(for: shard("broken", interrupt: true)) == nil)
    }

    /// Said as a claim about the pose vocabulary rather than about three
    /// hand-picked fixtures, so a fifth pose could not quietly acquire a voice.
    @Test
    func holdingIsTheOnlyPoseWithALine() {
        let cases: [(GeodeShard, CreaturePose)] = [
            (shard("running", finish: false), .working),
            (shard("clean"), .holding),
            (shard("broken", interrupt: true), .fallen),
        ]

        for (shard, expected) in cases {
            #expect(CreaturePose(shard: shard) == expected)
            #expect((CreatureVoice.lineKey(for: shard) != nil) == (expected == .holding))
        }
    }

    /// A finished session's line comes from the body it wears, so the four
    /// Claude Code forks all speak Claude's lines. That is the taxonomy being
    /// honest rather than a shortcut: they share a hook format because they are
    /// the same program.
    @Test
    func aForkSpeaksItsParentsLines() {
        for tool in [AgentTool.qoder, .qwenCode, .factory, .codebuddy] {
            let key = CreatureVoice.lineKey(for: shard("s1", tool: tool))
            #expect(key == CreatureVoice.lineKey(for: shard("s1", tool: .claudeCode)))
            #expect(key?.hasPrefix("island.voice.claude.") == true)
        }
    }
}
