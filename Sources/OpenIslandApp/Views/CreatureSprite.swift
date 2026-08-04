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

    /// Resource basename for the one companion in an aggregate state.
    ///
    /// Three of the four states wear a pose's artwork, because the companion
    /// waving and a session's creature waving are the same gesture and drawing
    /// them from two files is how they end up looking like two characters.
    ///
    /// `asleep` is the exception and needs no new art: `<species>-side` ships
    /// for all six characters — a profile with its eyes closed and its arms
    /// down — and until now no code path drew it. It is the only frame in the
    /// set that can say "nothing is happening" without also saying something
    /// about a session, which is exactly what an empty list means.
    static func name(for species: CreatureSpecies, state: CompanionState) -> String {
        switch state {
        case .waving: name(for: species, pose: .waiting)
        case .working: name(for: species, pose: .working)
        case .resting: name(for: species, pose: .holding)
        case .asleep: "\(species.rawValue)-\(sleepingComponent)"
        }
    }

    /// The alternate frame for states that animate. `nil` when the state is
    /// still — which is every state but the wave, because motion that happens
    /// when nothing is wrong trains the eye to ignore motion.
    static func alternateName(for species: CreatureSpecies, state: CompanionState) -> String? {
        state == .waving ? alternateName(for: species, pose: .waiting) : nil
    }

    /// What the fallback silhouette draws when a companion frame is missing.
    ///
    /// `asleep` has no pose — the companion is not standing in for a session at
    /// all — so it degrades to the plain standing shape rather than to
    /// `holding`, which would have it clutching a reward it was never given.
    static func fallbackPose(for state: CompanionState) -> CreaturePose {
        switch state {
        case .waving: .waiting
        case .working, .asleep: .working
        case .resting: .holding
        }
    }

    private static let sleepingComponent = "side"

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
