import Foundation

/// What a creature says when it finishes cleanly.
///
/// Twelve lines per species and nothing else — no rarity variants, no per-tool
/// voices. The design asks for "roughly 12 lines per family", and a family is
/// exactly a `CreatureSpecies`: the four Claude Code forks share a body because
/// they share a hook format, and giving them separate voices would contradict
/// the taxonomy the whole island is drawn from.
///
/// This type picks the line; it never reads one. The text lives in the app's
/// `Localizable.strings` and is resolved through `LanguageManager`, so adding a
/// locale is a file rather than a branch, and Core stays free of anything that
/// has to know what language the user reads.
public enum CreatureVoice {
    /// Per species, so 72 lines and 216 strings across the three shipped
    /// locales. Deliberately not shared between species: shared flavour text is
    /// what would make six creatures read as one, which is the opposite of the
    /// reason the lines exist.
    public static let linesPerSpecies = 12

    /// Two digits so the keys sort the way they are numbered. `island.voice.
    /// claude.1` and `island.voice.claude.12` sort adjacent, which makes a
    /// missing line very easy to miss in a 300-line strings file.
    public static func lineKeys(for species: CreatureSpecies) -> [String] {
        (1...linesPerSpecies).map { "island.voice.\(species.rawValue).\(String(format: "%02d", $0))" }
    }

    /// Every key the strings files have to define, for the localization gate.
    /// `LanguageManager.t(_:)` falls back to the key itself, so an untranslated
    /// line ships as `island.voice.kimi.07` on screen with nothing reporting it.
    public static var allLineKeys: [String] {
        CreatureSpecies.allCases.flatMap(lineKeys(for:))
    }

    /// The line this session speaks, whatever else happens to it.
    ///
    /// Seeded from the session ID through `ShardSeed`, the way `ShardForm.make`
    /// derives geometry and `RewardObject.yield` picks an object: same session,
    /// same line, on every frame and every launch. `hashValue` would not do —
    /// Swift seeds `Hasher` randomly per process, so the creature would say
    /// something different after a restart and the line would stop being *its*
    /// line.
    ///
    /// The session ID is the whole of the seed. Not the species (a session has
    /// one agent for its whole life, so folding it in would change nothing), and
    /// not the clock (the panel rebuilds this layout once a second, and a line
    /// that moved between ticks would read as muttering).
    public static func lineKey(species: CreatureSpecies, sessionID: String) -> String {
        var rng = SplitMix64(state: ShardSeed.value(for: seedSalt + sessionID))
        return lineKeys(for: species)[Int(rng.next() % UInt64(linesPerSpecies))]
    }

    /// Salted so the line is not the reward object's draw wearing a hat.
    ///
    /// `RewardObject.yield` takes the first `SplitMix64` output from the *plain*
    /// session seed and reduces it modulo a four-object pool. An unsalted seed
    /// here would take the same output and reduce it modulo twelve — making the
    /// object index exactly the line index modulo four, forever. A user who
    /// found a coin would then only ever hear three of that species' twelve
    /// lines. Prefixing the string before hashing decorrelates the two
    /// completely and stays as stable as FNV-1a itself.
    static let seedSalt = "voice:"

    /// The line this shard has earned, or `nil` when it has not earned one.
    ///
    /// The gate lives here rather than at the call site because "never for an
    /// interrupt" is an acceptance criterion, and a criterion enforced by
    /// whoever happens to be calling is a criterion one new call site can
    /// break. `holding` is the design's own word for a clean completion with
    /// its reward held overhead; `fallen` is beat 6, knocked over with scrap at
    /// its feet, and it has nothing to say. A session still running or still
    /// blocked on the human has not finished at all.
    public static func lineKey(for shard: GeodeShard) -> String? {
        guard CreaturePose(shard: shard) == .holding else { return nil }
        return lineKey(species: CreatureSpecies(tool: shard.tool), sessionID: shard.sessionID)
    }
}
