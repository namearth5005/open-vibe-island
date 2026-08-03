import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

struct CreatureRightSlotTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func shard(isSet: Bool = false, frozenSince: Date? = nil) -> GeodeShard {
        GeodeShard(
            sessionID: "s1", tool: .codex, startedAt: t0,
            frozenSeconds: 0, frozenSince: frozenSince, stallCount: 0,
            stage: 3, isSet: isSet, isFractured: false, updatedAt: t0
        )
    }

    @Test
    func creatureIsAvailableAsARightSlotOption() {
        #expect(IslandRightSlot.allCases.contains(.creature))
    }

    /// Adding a case must not disturb persisted preferences. Every existing raw
    /// value still resolves to the same case, so nobody's pill silently changes
    /// on upgrade.
    @Test
    func existingPreferencesStillResolve() {
        #expect(IslandRightSlot(rawValue: "count") == .count)
        #expect(IslandRightSlot(rawValue: "agents") == .agents)
        #expect(IslandRightSlot(rawValue: "geode") == .geode)
        #expect(IslandRightSlot(rawValue: "none") == IslandRightSlot.none)
        #expect(IslandRightSlot(rawValue: "creature") == .creature)
    }

    /// Sound cues and the growth ticker gate on this predicate. They previously
    /// tested `== .geode` by equality in three places, which meant a new
    /// shard-rendering slot would ship silent and frozen with no error anywhere.
    @Test
    func shardRenderingSlotsAreNamedNotEnumerated() {
        #expect(IslandRightSlot.geode.rendersShard)
        #expect(IslandRightSlot.creature.rendersShard)
        #expect(!IslandRightSlot.count.rendersShard)
        #expect(!IslandRightSlot.agents.rendersShard)
        #expect(!IslandRightSlot.none.rendersShard)
    }

    @Test
    func creatureContentCarriesSpeciesAndPose() {
        let content = IslandRightSlotContent.creature(shard(frozenSince: t0), finishedToday: 2)
        guard case let .creature(s, finished) = content else {
            Issue.record("wrong case")
            return
        }
        #expect(CreatureSpecies(tool: s.tool) == .codex)
        #expect(CreaturePose(shard: s) == .waiting)
        #expect(finished == 2)
    }

    /// The MacBook right lane is 28pt usable, so with no tally the creature
    /// fills it exactly and no more.
    @Test
    func creatureIntrinsicWidthFitsTheLane() {
        #expect(V6RightSlotView.creatureIntrinsicWidth(finishedToday: 0) <= 28)
        #expect(
            V6RightSlotView.intrinsicWidth(of: .creature(shard(), finishedToday: 0)) <= 28
        )
    }

    /// Width must not change as the session moves through its states, or the
    /// pill would resize on every transition.
    @Test
    func widthIsStableAcrossPoses() {
        let running = V6RightSlotView.intrinsicWidth(of: .creature(shard(), finishedToday: 1))
        let waiting = V6RightSlotView.intrinsicWidth(
            of: .creature(shard(frozenSince: t0), finishedToday: 1))
        let done = V6RightSlotView.intrinsicWidth(
            of: .creature(shard(isSet: true), finishedToday: 1))
        #expect(running == waiting)
        #expect(waiting == done)
    }
}

@MainActor
struct CreatureSpriteTests {
    /// Every pose of every species must have shipped artwork. A missing sprite
    /// falls back to the procedural silhouette, which is a safety net rather
    /// than an intended appearance — so its absence should fail here, not
    /// quietly render a placeholder to a user.
    @Test
    func everySpeciesAndPoseHasArtwork() {
        for species in CreatureSpecies.allCases {
            for pose in CreaturePose.allCases {
                let nm = CreatureSprite.name(for: species, pose: pose)
                #expect(
                    CreatureSprite.image(for: species, pose: pose) != nil,
                    "missing sprite: \(nm) [species=\(species.rawValue) pose=\(pose.rawValue)]"
                )
            }
        }
    }

    /// `waiting` is the only animated pose — the wave is the notification.
    /// Every other pose is still, because motion when nothing is wrong trains
    /// the eye to ignore motion.
    @Test
    func onlyWaitingAnimates() {
        for species in CreatureSpecies.allCases {
            #expect(CreatureSprite.alternateName(for: species, pose: .waiting) != nil)
            for pose in CreaturePose.allCases where pose != .waiting {
                #expect(CreatureSprite.alternateName(for: species, pose: pose) == nil)
            }
        }
    }

    @Test
    func theWaveFrameIsAlsoShipped() {
        for species in CreatureSpecies.allCases {
            guard let name = CreatureSprite.alternateName(for: species, pose: .waiting) else {
                Issue.record("\(species.rawValue) has no wave frame")
                continue
            }
            #expect(CreatureSprite.image(named: name) != nil, "missing artwork: \(name)")
        }
    }
}
