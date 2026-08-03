import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

@MainActor
struct RewardObjectArtworkTests {
    /// `RewardObject` is a plain enum in Core, which cannot see the resource
    /// bundle — so nothing in Core notices when a case has no `obj-*.png`. A
    /// missing file does not fail the build and does not throw; the reveal just
    /// shows an empty slot. This is the only place that absence surfaces.
    @Test
    func everyRewardObjectHasShippedArtwork() {
        for object in RewardObject.allCases {
            let name = CreatureSprite.name(for: object)
            #expect(CreatureSprite.image(named: name) != nil, "missing artwork: \(name)")
        }
    }
}
