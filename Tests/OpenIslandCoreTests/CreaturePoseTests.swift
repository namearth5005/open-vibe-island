import Foundation
import Testing
@testable import OpenIslandCore

struct CreaturePoseTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func shard(
        frozenSince: Date? = nil,
        isSet: Bool = false,
        isFractured: Bool = false
    ) -> GeodeShard {
        GeodeShard(
            sessionID: "s1", tool: .claudeCode, startedAt: t0,
            frozenSeconds: 0, frozenSince: frozenSince, stallCount: 0,
            stage: 2, isSet: isSet, isFractured: isFractured, updatedAt: t0
        )
    }

    @Test func runningSessionIsWorking() { #expect(CreaturePose(shard: shard()) == .working) }
    @Test func blockedSessionRaisesAHand() { #expect(CreaturePose(shard: shard(frozenSince: t0)) == .waiting) }
    @Test func cleanFinishHoldsTheRewardUp() { #expect(CreaturePose(shard: shard(isSet: true)) == .holding) }
    @Test func interruptKnocksTheCreatureOver() { #expect(CreaturePose(shard: shard(isSet: true, isFractured: true)) == .fallen) }

    /// A finished session is finished even if it was frozen when it ended —
    /// otherwise an interrupt during a permission prompt would show a raised
    /// hand forever, asking for input that will never be consumed.
    @Test
    func completionBeatsFreeze() {
        #expect(CreaturePose(shard: shard(frozenSince: t0, isSet: true)) == .holding)
        #expect(CreaturePose(shard: shard(frozenSince: t0, isSet: true, isFractured: true)) == .fallen)
    }

    /// Only these three must be mutually legible at pill size; `fallen` is
    /// deliberately quiet because an interrupted session is not asking for you.
    @Test
    func attentionPosesAreTheOnesThatDemandLegibility() {
        #expect(CreaturePose.working.demandsPillLegibility)
        #expect(CreaturePose.waiting.demandsPillLegibility)
        #expect(CreaturePose.holding.demandsPillLegibility)
        #expect(!CreaturePose.fallen.demandsPillLegibility)
    }
}
