import AppKit
import OpenIslandCore
import SwiftUI

/// Loads creature artwork out of the app resource bundle.
///
/// Sprites are the real artwork; `CreatureSilhouette` is the fallback that
/// renders when a sprite is missing. Keeping the fallback is not politeness —
/// the offscreen gate harness links Core without the app bundle, and a missing
/// asset should degrade to a readable shape rather than an empty slot.
@MainActor
enum CreatureSprite {
    /// Resource basename for one frame, e.g. `claude-waiting`.
    static func name(for species: CreatureSpecies, pose: CreaturePose) -> String {
        "\(species.rawValue)-\(fileComponent(for: pose))"
    }

    /// Resource basename for a structure, e.g. `struct-tower`. Prefixed rather
    /// than bare because the bundle is flat (see `image(named:)`) and `terminal`
    /// or `editor` alone would be a collision waiting to happen.
    static func name(for structure: CreatureStructure) -> String {
        "struct-\(structure.rawValue)"
    }

    /// Resource basename for a reward object, e.g. `obj-lantern`. Prefixed for
    /// the same reason structures are — `key` or `shard` alone would collide in
    /// a flat bundle.
    static func name(for object: RewardObject) -> String {
        "obj-\(object.rawValue)"
    }

    /// `CreaturePose` cases and the artwork filenames diverge in one place:
    /// `waiting` ships two frames so the raised arm can animate, and the second
    /// is named `wave2` rather than a pose of its own.
    private static func fileComponent(for pose: CreaturePose) -> String {
        switch pose {
        case .working: "working"
        case .waiting: "waiting"
        case .holding: "holding"
        case .fallen: "fallen"
        }
    }

    /// The alternate frame for poses that animate. `nil` when the pose is still.
    static func alternateName(for species: CreatureSpecies, pose: CreaturePose) -> String? {
        guard pose == .waiting else { return nil }
        return "\(species.rawValue)-wave2"
    }

    /// Cached because the pill re-renders on every tick and `NSImage(contentsOf:)`
    /// hits the disk each call.
    private static let cache = NSCache<NSString, NSImage>()

    /// Looked up by bare filename, no subdirectory.
    ///
    /// `Package.swift` declares `.process("Resources")`, which **flattens** the
    /// tree — the sprites live in `Resources/Creatures/` on disk but land at the
    /// bundle root. Asking for a `Creatures` subdirectory silently returns nil,
    /// which degrades to the fallback silhouette rather than erroring, so this
    /// is worth stating explicitly. Filenames are therefore globally unique
    /// across every resource directory, not just within their own.
    static func image(named name: String) -> NSImage? {
        if let hit = cache.object(forKey: name as NSString) { return hit }
        guard let url = Bundle.appResources.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }

    static func image(for species: CreatureSpecies, pose: CreaturePose) -> NSImage? {
        image(named: name(for: species, pose: pose))
    }
}
