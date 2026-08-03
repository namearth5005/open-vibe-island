import Foundation
import Testing
@testable import OpenIslandCore

struct RewardObjectTests {
    private static let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func record(
        id: String = "s1",
        interrupted: Bool = false,
        stalls: Int = 0,
        latency: Double? = nil,
        worst: Double? = nil,
        inferred: Bool? = nil,
        minutes: Double = 5
    ) -> SessionLogRecord {
        SessionLogRecord(
            sessionID: id,
            tool: .claudeCode,
            startedAt: Self.epoch,
            endedAt: Self.epoch.addingTimeInterval(minutes * 60),
            wasInterrupted: interrupted,
            stallCount: stalls,
            meanGateLatency: latency,
            worstGateLatency: worst,
            isInferred: inferred
        )
    }

    // MARK: - The catalogue

    /// The enum is the manifest for `Resources/World/obj-*.png`. A case with no
    /// asset renders nothing and an asset with no case is dead weight nobody
    /// notices, so the count is pinned here and the filenames are checked in the
    /// app target, which is the only target that can see the bundle.
    @Test
    func thereAreThirteenObjectsAndExactlyOneOfThemIsScrap() {
        #expect(RewardObject.allCases.count == 13)
        #expect(RewardObject.allCases.contains(.scrap))
    }

    // MARK: - Interrupts

    /// Beat 6 of the design: an interrupt knocks the creature over and leaves
    /// scrap at its station. Scrap is the absence of a reward, not a low-tier
    /// one, which is why it has no rarity rather than zero stars.
    @Test
    func anInterruptedSessionLeavesScrapAndHasNoRarity() {
        let interrupted = record(interrupted: true, minutes: 90)
        #expect(RewardObject.yield(for: interrupted) == .scrap)
        #expect(RewardRarity.rarity(for: interrupted) == nil)
    }

    /// An interrupt outranks every other fact: a ninety-minute run with instant
    /// answers still leaves scrap, because the work did not land.
    @Test
    func noCleanSessionEverLeavesScrap() {
        for minutes in [0.0, 1, 29, 30, 31, 600] {
            for latency in [nil, 0, 1, 30, 31, 3600] as [Double?] {
                let clean = record(latency: latency, minutes: minutes)
                #expect(RewardObject.yield(for: clean) != .scrap, "\(minutes)m \(latency as Any)")
            }
        }
    }

    // MARK: - Rarity

    @Test
    func anyCleanCompletionEarnsAtLeastOneStar() {
        let sloppy = record(stalls: 3, latency: 600, minutes: 0)
        #expect(RewardRarity.rarity(for: sloppy) == .one)
    }

    /// The tier rewards stewardship, and a run that never had to interrupt the
    /// human is the purest form of it — there was nothing to answer late.
    @Test
    func aSessionThatNeverNeededTheHumanEarnsTwoStarsVacuously() {
        #expect(RewardRarity.rarity(for: record(stalls: 0, latency: nil)) == .two)
    }

    /// The point of the tier: answering fast is the lever the human actually
    /// controls. A session with gates that were all answered promptly rates the
    /// same as one that never asked.
    @Test
    func promptlyAnsweredGatesEarnTwoStars() {
        #expect(RewardRarity.rarity(for: record(stalls: 4, latency: 3)) == .two)
    }

    @Test
    func aGateLeftPastTheGraceWindowDropsBackToOneStar() {
        #expect(RewardRarity.rarity(for: record(stalls: 1, latency: 45)) == .one)
    }

    /// Thirty seconds, from the design's grace window. The boundary is inclusive
    /// because the window is stated as "answer within 30 seconds".
    @Test
    func theGraceWindowIsThirtySecondsAndItsBoundaryIsInclusive() {
        #expect(RewardRarity.graceWindow == 30)
        #expect(RewardRarity.rarity(for: record(stalls: 1, latency: 30)) == .two)
        #expect(RewardRarity.rarity(for: record(stalls: 1, latency: 30.001)) == .one)
    }

    @Test
    func aLongCleanAttentiveRunEarnsThreeStars() {
        #expect(RewardRarity.rarity(for: record(stalls: 2, latency: 5, minutes: 45)) == .three)
        #expect(RewardRarity.rarity(for: record(latency: nil, minutes: 45)) == .three)
    }

    /// Runtime alone does not buy the top tier — a long run the human abandoned
    /// mid-way is not the thing being rewarded.
    @Test
    func aLongRunWithAnAbandonedGateStaysAtOneStar() {
        #expect(RewardRarity.rarity(for: record(stalls: 1, latency: 120, minutes: 45)) == .one)
    }

    @Test
    func theLongRunThresholdIsThirtyMinutes() {
        #expect(RewardRarity.longRunDuration == 30 * 60)
        #expect(RewardRarity.rarity(for: record(minutes: 29.9)) == .two)
        #expect(RewardRarity.rarity(for: record(minutes: 30)) == .three)
    }

    /// Rarity reads session facts and nothing else, so the same facts under a
    /// different identity rate identically. This is what lets a rule change
    /// re-rate the whole history instead of stranding records rated under the
    /// old rule.
    @Test
    func rarityDependsOnSessionFactsAndNotOnIdentity() {
        for id in ["a", "b", "zzz-9", ""] {
            #expect(
                RewardRarity.rarity(for: record(id: id, latency: 2, minutes: 45)) == .three,
                "\(id)"
            )
        }
    }

    /// ★★★★ needs a shipped release, which needs the git/PR watcher listed as
    /// open question 1 in the design. It is declared so the ladder is complete
    /// and the tier is not quietly reinvented, and asserted unreachable so the
    /// next person to find it knows it is unbuilt rather than broken.
    @Test
    func fourStarsIsUnreachableUntilTheGitWatcherExists() {
        var reached: Set<RewardRarity> = []
        for minutes in [0.0, 0.5, 29.9, 30, 31, 1440] {
            for latency in [nil, 0, 5, 29, 30, 31, 600] as [Double?] {
                for worst in [nil, 0, 30, 31, 600] as [Double?] {
                    for stalls in [0, 1, 9] {
                        for inferred in [nil, true, false] as [Bool?] {
                            for interrupted in [true, false] {
                                let any = record(
                                    interrupted: interrupted,
                                    stalls: stalls,
                                    latency: latency,
                                    worst: worst,
                                    inferred: inferred,
                                    minutes: minutes
                                )
                                if let rarity = RewardRarity.rarity(for: any) {
                                    reached.insert(rarity)
                                }
                            }
                        }
                    }
                }
            }
        }
        #expect(!reached.contains(.four))
        #expect(reached == [.one, .two, .three])
    }

    // MARK: - The worst gate

    /// The case the mean could not see. Two gates at 1s and 59s average to
    /// exactly 30s and used to earn ★★, although one of them blew the window by
    /// twice over. The recorded maximum decides it outright.
    @Test
    func oneAbandonedGateCostsTheTierNoMatterHowFastTheOthersWere() {
        #expect(RewardRarity.rarity(for: record(stalls: 2, latency: 30, worst: 59)) == .one)
        #expect(RewardRarity.rarity(for: record(stalls: 40, latency: 1, worst: 600)) == .one)
    }

    /// The maximum outranks the mean at every tier, including the long-run one:
    /// runtime never buys back a gate nobody answered.
    @Test
    func theWorstGateDecidesEvenWhenTheMeanWouldPass() {
        #expect(RewardRarity.rarity(for: record(stalls: 2, latency: 2, worst: 31, minutes: 45)) == .one)
        #expect(RewardRarity.rarity(for: record(stalls: 2, latency: 2, worst: 30, minutes: 45)) == .three)
    }

    /// Records written before the worst gate was recorded do not carry it, and
    /// the fact cannot be recovered — so they keep the mean's one-sided reading
    /// rather than being re-rated on a field that is absent. All-inside implies
    /// mean-inside, so no session that qualified is denied; only the reverse
    /// leaks, and only for history.
    @Test
    func recordsWrittenBeforeTheWorstGateExistedFallBackToTheMean() {
        #expect(RewardRarity.rarity(for: record(stalls: 2, latency: 30, worst: nil)) == .two)
        #expect(RewardRarity.rarity(for: record(stalls: 2, latency: 45, worst: nil)) == .one)
    }

    // MARK: - Inferred history

    /// Back-filled records are inference from a transcript: their clean finish,
    /// their zero stall count and their duration are all asserted rather than
    /// observed. ★ is the whole of what that supports — the island was not
    /// running, so it cannot testify that anyone answered anything.
    @Test
    func historyInferredFromATranscriptCannotClaimMoreThanOneStar() {
        #expect(RewardRarity.rarity(for: record(inferred: true, minutes: 240)) == .one)
        #expect(RewardRarity.rarity(for: record(stalls: 1, latency: 1, worst: 1, inferred: true)) == .one)
        #expect(RewardObject.pool(for: .one).contains(RewardObject.yield(for: record(inferred: true))))
    }

    /// Absent means observed: every record already on disk predates the flag and
    /// must keep the rating it had.
    @Test
    func aRecordWithNoProvenanceFlagIsTreatedAsObserved() {
        #expect(RewardRarity.rarity(for: record(inferred: nil, minutes: 45)) == .three)
        #expect(RewardRarity.rarity(for: record(inferred: false, minutes: 45)) == .three)
    }

    /// Inference never claims an interrupt, so it can never manufacture scrap
    /// either — the floor is ★, not nothing.
    @Test
    func inferredHistoryStillNeverLeavesScrap() {
        #expect(RewardObject.yield(for: record(inferred: true, minutes: 240)) != .scrap)
    }

    // MARK: - Which object

    /// The object is the rating made visible, so the pools must not overlap: a
    /// lantern can only ever have come from a ★★★ run.
    @Test
    func everyTierDrawsFromItsOwnPoolAndTheyDoNotOverlap() {
        var seen: [RewardObject: RewardRarity] = [:]
        for index in 0..<200 {
            let id = "s\(index)"
            for (latency, minutes) in [(600.0, 1.0), (2.0, 1.0), (2.0, 45.0)] {
                let clean = record(id: id, stalls: 1, latency: latency, minutes: minutes)
                guard let rarity = RewardRarity.rarity(for: clean) else { continue }
                let object = RewardObject.yield(for: clean)
                #expect(seen[object] == nil || seen[object] == rarity, "\(object) crosses tiers")
                seen[object] = rarity
            }
        }
        #expect(Set(seen.values) == [.one, .two, .three])
    }

    /// Twelve objects and one scrap: artwork that no session can ever draw is
    /// shipped weight nothing else in the build notices. Mirrors
    /// `CreatureStructureTests.noStructureIsOrphaned`.
    @Test
    func everyObjectExceptScrapIsReachable() {
        var reached: Set<RewardObject> = [.scrap]
        for index in 0..<200 {
            let id = "s\(index)"
            for (latency, minutes) in [(600.0, 1.0), (2.0, 1.0), (2.0, 45.0)] {
                reached.insert(
                    RewardObject.yield(
                        for: record(id: id, stalls: 1, latency: latency, minutes: minutes)
                    )
                )
            }
        }
        let orphans = Set(RewardObject.allCases).subtracting(reached)
        #expect(orphans.isEmpty, "unreachable artwork: \(orphans.map(\.rawValue).sorted())")
    }

    @Test
    func theSameSessionAlwaysYieldsTheSameObject() {
        let clean = record(id: "abc-123", stalls: 1, latency: 2, minutes: 45)
        let first = RewardObject.yield(for: clean)
        for _ in 0..<50 {
            #expect(RewardObject.yield(for: clean) == first)
        }
    }

    /// Pinned to literals for the same reason `ShardSeed` is: the object has to
    /// survive a relaunch, and a `hashValue`-based pick would silently reshuffle
    /// it every process. `abc-123` is the ID `GeodeShardFormTests` already pins;
    /// drawing it through `SplitMix64` selects the second entry of each pool.
    @Test
    func objectSelectionSurvivesARelaunch() {
        #expect(RewardObject.yield(for: record(id: "abc-123", latency: 600)) == .feather)
        #expect(RewardObject.yield(for: record(id: "abc-123", latency: 2)) == .book)
        #expect(
            RewardObject.yield(for: record(id: "abc-123", latency: 2, minutes: 45)) == .geode
        )
    }
}
