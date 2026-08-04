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

    /// The session pose the companion borrows its frame from, or `nil` when
    /// there is no session behind it.
    ///
    /// Only `asleep` is `nil`, and that is the point: an empty list is the one
    /// companion state no shard can produce, so it is the one with no pose to
    /// borrow. Everything else is a pose the pill already draws, which is what
    /// keeps the two surfaces one individual rather than two.
    var pose: CreaturePose? {
        switch self {
        case .waving: .waiting
        case .working: .working
        case .resting: .holding
        case .asleep: nil
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
/// left is the two facts the list genuinely does not carry — how long you have
/// worked today, and what the day came to — plus one companion reacting to the
/// list in aggregate rather than representing it.
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
    let finishedToday: Int
    let interruptedToday: Int
    /// Everything the picture shows, in words. Resolved at construction like
    /// every other island string, so this stays a plain `Equatable` value
    /// instead of carrying a reference to a translation engine.
    let accessibilityDescription: String
    let workedLabel: String
    let doneBadge: String
    /// `nil` on a clean day. A permanent "0 stopped" would be a scold, and an
    /// interrupt is not a failure worth a standing reminder.
    let stoppedBadge: String?

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

    /// The three text weights on the row, as opacities of `V6Palette.paper`.
    ///
    /// Named rather than written at each `foregroundStyle` because every one of
    /// them has to clear 4.5:1 against the panel's ink and a fourth tier added
    /// by eye would not. The island's other bands go down to 0.38, which they
    /// can afford because the picture beside them carries the meaning; this row
    /// has four words in total and every one of them is load-bearing.
    static let primaryTextOpacity: Double = 1
    static let secondaryTextOpacity: Double = 0.72
    static let tertiaryTextOpacity: Double = 0.55

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
        finishedToday = today.cleanFinishes
        interruptedToday = today.interrupted

        workedLabel = lang.t("island.companion.worked")
        let done = lang.t("island.companion.done", today.cleanFinishes)
        doneBadge = done
        let stopped = today.interrupted > 0
            ? lang.t("island.companion.stopped", today.interrupted)
            : nil
        stoppedBadge = stopped

        // The visible badges said again rather than a second vocabulary invented
        // for VoiceOver: two ways of saying one tally is how the spoken row ends
        // up describing a day the screen is not showing.
        let tally = [done, stopped].compactMap { $0 }.joined(separator: ", ")
        accessibilityDescription = lang.t(
            "island.companion.spoken",
            state.spokenState(lang),
            worked.spoken(lang),
            tally
        )
    }
}

/// The opened panel's companion row.
///
/// One character, a duration and the day's tally, in that reading order. The
/// companion is bound by the row's height rather than by a fixed box, which is
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
                    .foregroundStyle(V6Palette.paper.opacity(IslandCompanionRow.tertiaryTextOpacity))
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(row.doneBadge)
                    .foregroundStyle(V6Palette.paper.opacity(IslandCompanionRow.secondaryTextOpacity))

                if let stopped = row.stoppedBadge {
                    Text(stopped)
                        .foregroundStyle(V6Palette.paper.opacity(IslandCompanionRow.tertiaryTextOpacity))
                }
            }
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
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
/// Three of the four states are poses the pill already draws, so they go through
/// `CreatureView` and inherit its wave animation and its cross-fade between
/// poses — the companion in the notch and the one in the panel are meant to be
/// the same individual, and sharing the drawing code is how that stays true
/// rather than being asserted. `asleep` is the exception: no session, so no pose
/// to borrow, so it draws the calm profile directly.
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
        if let pose = state.pose {
            // `CreatureView` already sizes itself and owns the wave's frame
            // alternation, so the companion inherits the pill's animation rather
            // than running a second copy of it that could fall out of step.
            CreatureView(
                species: species,
                pose: pose,
                seed: Self.seed,
                size: size,
                alignment: .bottom
            )
        } else {
            calmProfile
                .frame(width: size.width, height: size.height, alignment: .bottom)
        }
    }

    @ViewBuilder
    private var calmProfile: some View {
        if let sprite = CreatureSprite.image(
            named: CreatureSprite.name(for: species, state: state)
        ) {
            Image(nsImage: sprite)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            // Degrades to the shape the legibility gate measured, exactly as the
            // pill does — a missing asset must not leave an empty slot.
            CreatureSilhouetteShape(seed: Self.seed, pose: CreatureSprite.fallbackPose(for: state))
                .fill(Color(CreaturePalette.color(for: species)))
        }
    }
}
