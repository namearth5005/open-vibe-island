import Foundation

/// Which of the six bodies the one companion wears.
///
/// The roster was cut, so nobody picks this and nothing derives it per session.
/// It cannot be derived per session either: `CreatureSpecies(tool:)` is what the
/// *pill* uses, and the pill draws whichever session is featured right now — a
/// rule that would change the companion's body every time the featured shard
/// moved. The destination surface is meant to hold one individual you come back
/// to, and an individual whose species follows the front-most session is not an
/// individual.
///
/// So it reads the log instead: the agent you have actually finished the most
/// work with. That is stable across a session, honest about a multi-agent setup
/// (a Codex user gets the Codex body, not a Claude one), and needs no
/// preference, no store and no migration.
public enum CompanionIdentity {
    /// The species with the most finished sessions behind it.
    ///
    /// Counted by *species* rather than by tool, because the four Claude Code
    /// forks share a body — counting by tool would split one companion's history
    /// four ways and let a minority agent win.
    ///
    /// Ties go to whoever finished most recently, and a tie in that goes to the
    /// declaration order of `CreatureSpecies`. Both tiebreaks exist so the answer
    /// is a function of the log and not of dictionary iteration order; without
    /// them the companion could change body between two launches with no session
    /// in between.
    public static func species(for records: [SessionLogRecord]) -> CreatureSpecies {
        var counts: [CreatureSpecies: Int] = [:]
        var lastFinished: [CreatureSpecies: Date] = [:]

        for record in SessionLogStore.deduplicated(records) {
            let species = CreatureSpecies(tool: record.tool)
            counts[species, default: 0] += 1
            lastFinished[species] = max(lastFinished[species] ?? .distantPast, record.endedAt)
        }

        guard !counts.isEmpty else { return fallback }

        // Ranked over `allCases` rather than over the dictionary, and with the
        // declaration index as the last key, so the comparison is a total order
        // on a fixed sequence. `sorted(by:)` is not stable, so "leave ties
        // alone" is not a tiebreak — it has to be spelled out.
        let ranked = CreatureSpecies.allCases.enumerated()
            .filter { counts[$0.element] != nil }
            .max { lhs, rhs in
                let lhsKey = (counts[lhs.element] ?? 0, lastFinished[lhs.element] ?? .distantPast, -lhs.offset)
                let rhsKey = (counts[rhs.element] ?? 0, lastFinished[rhs.element] ?? .distantPast, -rhs.offset)
                return lhsKey < rhsKey
            }

        return ranked?.element ?? fallback
    }

    /// What stands on the stage before there is any history to read.
    ///
    /// A first launch has no answer to "who do you work with", so this is a
    /// choice rather than a derivation, and it is the only Claude-specific line
    /// in the feature: `claude` is the one body every Claude Code fork also
    /// wears, so it is the single sprite set the largest share of first runs
    /// would have landed on anyway. It is replaced by the real answer as soon as
    /// one session finishes.
    public static let fallback: CreatureSpecies = .claude
}
