import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

@MainActor
struct CreatureStructureArtworkTests {
    /// A missing structure PNG does not fail the build and does not throw —
    /// `CreatureSprite.image` just returns nil and the creature ends up
    /// standing next to nothing. Resolving every case here is the only place
    /// that absence surfaces.
    @Test
    func everyStructureHasShippedArtwork() {
        for structure in CreatureStructure.allCases {
            let name = CreatureSprite.name(for: structure)
            #expect(CreatureSprite.image(named: name) != nil, "missing artwork: \(name)")
        }
    }
}
