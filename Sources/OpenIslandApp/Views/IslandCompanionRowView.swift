import OpenIslandCore
import SwiftUI

extension CompanionState {
    /// What the companion is doing, in words.
    ///
    /// The row draws no state text — the picture carries the state, which is the
    /// same clarity rule the scene followed — so this is read out loud and
    /// nowhere else. A screen-reader user gets the companion from this sentence
    /// or not at all.
    func spokenState(_ lang: LanguageManager) -> String {
        lang.t(spokenStateKey)
    }

    /// Separated from the lookup so a test can prove four states map to four
    /// distinct keys without depending on what any locale translates them to.
    var spokenStateKey: String {
        switch self {
        case .waving: "island.companion.state.waving"
        case .working: "island.companion.state.working"
        case .resting: "island.companion.state.resting"
        case .asleep: "island.companion.state.asleep"
        }
    }
}

/// The slim row that replaced the island band.
///
/// Round 1 spent 309pt saying which sessions exist, what agent each is and what
/// state it is in — all three of which the session list directly below said
/// better, and its 12pt coloured dot said more legibly than the whole 211pt
/// meadow. So this row is defined as much by what it may not say as by what it
/// says: **no session names, no per-session rows, no agent labels**. What is
/// left is one fact the panel does not carry anywhere else — how long you have
/// worked today — and one companion reacting to the list in aggregate rather
/// than representing it.
///
/// The day's tally went the same way for the same reason: `IslandPanelView.`
/// `shippedTodayBadge` already prints it, with a week-over-week delta, a few
/// points below. Saying it twice in one panel is round 1's mistake at a
/// smaller scale.
///
/// Split from the view for the same reason every other island layout is: the
/// claims worth making are about what the row costs and what it says, and a
/// view body cannot be asked either question.
struct IslandCompanionRow: Equatable, Sendable {
    /// 540pt on notch Macs, 520 on external displays.
    let width: CGFloat
    /// The user's `IslandSceneHeight`, as a multiplier.
    let heightScale: CGFloat
    /// What the companion is doing, read off the whole list by the one reducer.
    /// The row decides nothing about this.
    let state: CompanionState
    let species: CreatureSpecies
    /// How long agents have worked for you today. `SessionStats.totalRuntime`
    /// already computes this; held as a grain rather than as a string so the
    /// badge and the spoken sentence are two renderings of one rounding.
    let workedToday: IslandDurationGrain
    /// Everything the picture shows, in words. Resolved at construction like
    /// every other island string, so this stays a plain `Equatable` value
    /// instead of carrying a reference to a translation engine.
    let accessibilityDescription: String
    let workedLabel: String

    /// Base row height, before the user's height preference scales it.
    ///
    /// 72pt against the 309pt it replaces — the band was 4.3x this, and it is
    /// the panel's own content that gets the difference back. Chosen as roughly
    /// what a companion needs to be drawn *large*, which is the number that
    /// actually matters: round 1's failure was not that 211pt was too much, it
    /// was that only a quarter of it was creature.
    static let baseHeight: CGFloat = 72

    /// The companion's share of the row's height.
    ///
    /// Round 1 drew a 54pt creature in a 211pt scene — 26%. Three times that
    /// share is what "large in frame" has to mean, and the remaining 22% is the
    /// row's vertical padding rather than scenery.
    static let creatureHeightFraction: CGFloat = 0.78

    /// The character drawn until task 4 makes it a preference.
    ///
    /// One named constant rather than a literal at the draw site, so turning it
    /// into a choice is a change in one place.
    static let defaultSpecies: CreatureSpecies = .claude

    static let horizontalInset: CGFloat = 16
    static let contentSpacing: CGFloat = 14

    /// The row's two text weights, as opacities of `V6Palette.paper`.
    ///
    /// Named rather than written at each `foregroundStyle` because both have to
    /// clear 4.5:1 against the panel's ink and a third tier added by eye would
    /// not. The island's other bands go down to 0.38 and can afford it, because
    /// a creature stands beside them carrying the same fact; this row has three
    /// words in total and the quiet one is the only thing that says what the
    /// number counts.
    static let primaryTextOpacity: Double = 1
    static let secondaryTextOpacity: Double = 0.58

    /// Shared with `OverlayPanelController` through `IslandBandLayout` so the
    /// window's height budget and the row actually drawn are one number.
    static func height(scale: CGFloat) -> CGFloat {
        baseHeight * scale
    }

    var height: CGFloat { Self.height(scale: heightScale) }
    var creatureHeight: CGFloat { height * Self.creatureHeightFraction }
    var workedBadge: String { workedToday.badge }

    init(
        sessions: [AgentSession],
        geode: GeodeState,
        records: [SessionLogRecord],
        species: CreatureSpecies = IslandCompanionRow.defaultSpecies,
        width: CGFloat,
        heightScale: CGFloat = 1,
        now: Date,
        lang: LanguageManager = .shared
    ) {
        self.width = width
        self.heightScale = heightScale
        self.species = species

        let state = CompanionState(sessions: sessions, geode: geode)
        self.state = state

        let today = SessionStats.summary(for: .today, records: records, now: now)
        let worked = IslandDurationGrain(seconds: today.totalRuntime)
        workedToday = worked
        workedLabel = lang.t("island.companion.worked")

        // Exactly what the row draws, in the order it draws it — nothing more.
        // The day's tally is deliberately absent here because it is absent from
        // the row: `IslandPanelView.shippedTodayBadge` already renders it 8pt
        // below, and a VoiceOver sentence that described it would be announcing
        // the header's content from the companion's element.
        accessibilityDescription = lang.t(
            "island.companion.spoken",
            state.spokenState(lang),
            worked.spoken(lang)
        )
    }
}

/// The opened panel's companion row.
///
/// One character and one duration, in that reading order. The companion is
/// bound by the row's height rather than by a fixed box, which is
/// the whole structural difference from round 1: widening the panel used to
/// make the creature a smaller share of it, and now it cannot.
struct IslandCompanionRowView: View {
    let row: IslandCompanionRow

    var body: some View {
        HStack(spacing: IslandCompanionRow.contentSpacing) {
            IslandCompanionView(
                state: row.state,
                species: row.species,
                height: row.creatureHeight
            )

            VStack(alignment: .leading, spacing: 0) {
                Text(row.workedBadge)
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .foregroundStyle(V6Palette.paper.opacity(IslandCompanionRow.primaryTextOpacity))
                    .monospacedDigit()

                Text(row.workedLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(V6Palette.paper.opacity(IslandCompanionRow.secondaryTextOpacity))
            }

            Spacer(minLength: 8)
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.horizontal, IslandCompanionRow.horizontalInset)
        .frame(width: row.width, height: row.height)
        // No background of its own: the panel surface is already `V6Palette.ink`,
        // and the row painting it again is the "sticker pasted on" reading the
        // human has objected to three times. Task 6 grounds it properly.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityDescription)
    }
}

/// The companion itself, at whatever size the row gives it.
///
/// One `CreatureView` for all four states, never a branch on the state.
///
/// Drawing the companion through the same view the pill uses is what keeps the
/// two surfaces one individual rather than two that happen to look alike — it
/// inherits the wave's frame alternation and the cross-fade between frames
/// rather than running a second copy that could fall out of step. And keeping
/// it to a single node is what leaves waking up and falling asleep animatable:
/// an `if` here would be `_ConditionalContent`, and crossing that boundary
/// tears the subtree down.
struct IslandCompanionView: View {
    let state: CompanionState
    let species: CreatureSpecies
    let height: CGFloat

    /// One companion, so one seed. Only the fallback silhouette reads it, but a
    /// seed that changed per render would make a missing sprite flicker between
    /// shapes.
    private static let seed = ShardSeed.value(for: "companion")

    /// Wider than tall because sprites are trimmed to their content and the
    /// broadest standing pose is very nearly square — so height binds and every
    /// character comes out the same size.
    private var size: CGSize {
        CGSize(width: height * 1.08, height: height)
    }

    var body: some View {
        CreatureView(
            species: species,
            state: state,
            seed: Self.seed,
            size: size,
            alignment: .bottom
        )
    }
}
