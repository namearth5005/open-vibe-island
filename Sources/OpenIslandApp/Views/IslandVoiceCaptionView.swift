import OpenIslandCore
import SwiftUI

/// The one line a creature says when it finishes cleanly, and where it stands.
///
/// **Why it is drawn over the scene rather than in a band of its own.** A clean
/// completion is a moment, not a state: it lasts one linger window and then it
/// is over. A band that appeared for those 45 seconds would grow the panel and
/// shove the session list down at the moment the user's eye was on the island,
/// then pull it back up again — the same failure the detail row's fixed height
/// exists to avoid. The scene already reserves painted sky above every
/// creature's head, so the line costs no layout at all.
///
/// **Why not the detail row, which is the band allowed both a mood and a
/// string.** That row leads with `spotlightPrimaryText` — the agent's last
/// message. Replacing it with flavour text would hide what the session actually
/// said behind what its creature says about having said it, and it would only
/// ever appear for the one session that happens to be selected.
///
/// **What it does to the design's clarity rule.** The rule is that the picture
/// carries state and the text carries identity, and the scene therefore carries
/// no strings. This line is the sanctioned exception, on the same grounds as the
/// overflow badge's numeral: it names nothing. It says neither which agent nor
/// which workspace, and every fact about the session it belongs to is still
/// printed in the strip directly below. It is the pose said out loud.
struct IslandVoiceCaption: Equatable, Sendable {
    /// Whose line it is. Nothing in the text says so — position is the whole of
    /// the visible attribution, which is why the geometry below is asserted.
    let sessionID: String
    /// The same workspace name the identity strip prints under this creature,
    /// reused rather than resolved again so the two can never name one session
    /// differently. Never drawn: it exists only for the accessibility label,
    /// where position cannot do the attributing.
    let speaker: String
    /// Resolved when the layout is built, like every other string on the band,
    /// so this stays a plain `Equatable` value instead of one carrying a
    /// reference to a translation engine.
    let text: String
    /// Centre of the plate, in points from the band's leading edge. Already
    /// clamped: the scene clips at its own edges and half a sentence is worse
    /// than none.
    let center: CGFloat
    let centerY: CGFloat

    /// What a screen-reader user hears.
    ///
    /// Sighted attribution is entirely positional — the plate hangs over the
    /// creature that spoke. VoiceOver has no position, so without the speaker
    /// this would be an orphan sentence between the hidden scene and the strip,
    /// with nothing saying which of five sessions said it. Naming it here does
    /// not put a string in the picture: it is never drawn.
    var accessibilityLabel: String { "\(speaker), \(text)" }

    /// Roughly six English words, or a dozen Chinese characters. Wider than
    /// this and a line over the middle plot would reach across its neighbours;
    /// the lines are written to fit rather than the plate written to hold them.
    static let maximumWidth: CGFloat = 180
    static let height: CGFloat = 20
    static let edgeInset: CGFloat = 8
    /// Clear of the head, close enough to belong to it.
    static let gapAboveCreature: CGFloat = 4
    static let fontSize: CGFloat = 10
    static let horizontalPadding: CGFloat = 8

    /// The line the island is speaking right now, or `nil` for silence.
    ///
    /// Only stations are considered, so a session past the scene's plot ceiling
    /// never speaks — a line over a creature nobody can see would point at
    /// nothing, and the count in the overflow badge is the honest thing to show
    /// instead.
    static func resolve(
        scene: IslandSceneLayout,
        strip: IslandIdentityStripLayout,
        geode: GeodeState,
        now: Date,
        lang: LanguageManager
    ) -> IslandVoiceCaption? {
        let speakers = scene.stations.compactMap { station -> (IslandStation, GeodeShard, String)? in
            guard let shard = geode.shard(id: station.id),
                  isFresh(shard, at: now),
                  // The gate that keeps an interrupt silent. It lives in Core,
                  // beside the pose vocabulary it reads, rather than here.
                  let key = CreatureVoice.lineKey(for: shard)
            else { return nil }
            return (station, shard, key)
        }

        // Two sessions finishing inside one window is a real case, and the
        // answer is that there is one *current* moment: the newer completion
        // takes the line. The older one is not queued behind it — replaying a
        // line after its moment has passed would have the island reporting
        // something that already happened. Ties break on session ID, matching
        // `GeodeState.displayed(at:)`, so the pill and the panel never pick
        // different winners for the same instant.
        guard let (station, _, key) = speakers.max(by: { lhs, rhs in
            lhs.1.updatedAt == rhs.1.updatedAt
                ? lhs.0.id < rhs.0.id
                : lhs.1.updatedAt < rhs.1.updatedAt
        }) else { return nil }

        return IslandVoiceCaption(
            sessionID: station.id,
            speaker: strip.cells.first { $0.id == station.id }?.workspace
                ?? lang.t("island.unknownWorkspace"),
            text: lang.t(key),
            center: clampedCenter(station.center, width: scene.width),
            centerY: centerY(sceneHeight: scene.height)
        )
    }

    /// The shard's own linger window — the constant the closed pill already
    /// uses to decide how long a finished thing stays on screen. A second
    /// timeout here would be a second answer to one question, and the two would
    /// drift until the pill and the panel disagreed about whether a session had
    /// just finished.
    ///
    /// A negative age means the completion is stamped in the future, which a
    /// clock adjustment can produce. That is not a moment that has happened yet.
    static func isFresh(_ shard: GeodeShard, at now: Date) -> Bool {
        let age = now.timeIntervalSince(shard.updatedAt)
        return age >= 0 && age <= GeodeState.lingerWindow
    }

    /// Slides inward at the outermost plots rather than clipping. The shift is
    /// at most half a station pitch, so the plate still sits nearer its own
    /// creature than anyone else's — asserted, because position is the only
    /// thing saying who spoke.
    static func clampedCenter(_ center: CGFloat, width: CGFloat) -> CGFloat {
        let half = maximumWidth / 2
        let lower = half + edgeInset
        let upper = width - half - edgeInset
        guard lower < upper else { return width / 2 }
        return min(max(center, lower), upper)
    }

    /// Just above the creature's head, wherever the chosen scene height puts
    /// it. `compact` crops sky off the top, which is exactly where this goes, so
    /// the result is clamped back inside the band rather than trusted.
    static func centerY(sceneHeight: CGFloat) -> CGFloat {
        let creatureTop = sceneHeight * IslandSceneView.groundFraction - IslandStationView.height
        let natural = creatureTop - gapAboveCreature - height / 2
        return min(max(natural, height / 2 + edgeInset), sceneHeight - height / 2 - edgeInset)
    }
}

/// The plate the line is printed on.
///
/// Drawn as an overlay on the scene by `IslandBandView` rather than inside it,
/// which is what keeps it reachable by VoiceOver: the scene marks itself
/// `accessibilityHidden` on the grounds that everything in it is also carried in
/// words by the identity strip, and this line is the one thing in the band that
/// is *only* words.
struct IslandVoiceCaptionView: View {
    let caption: IslandVoiceCaption

    var body: some View {
        Text(caption.text)
            .font(.system(size: IslandVoiceCaption.fontSize, weight: .medium))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(V6Palette.paper.opacity(0.92))
            .padding(.horizontal, IslandVoiceCaption.horizontalPadding)
            .frame(maxWidth: IslandVoiceCaption.maximumWidth, minHeight: IslandVoiceCaption.height)
            // The scene behind it is a painting with a bright sky and a dark
            // meadow, so the plate carries its own ground rather than trusting
            // whatever pixels it lands on.
            .background(
                Capsule(style: .continuous)
                    .fill(V6Palette.ink.opacity(0.74))
            )
            .fixedSize(horizontal: true, vertical: false)
            .position(x: caption.center, y: caption.centerY)
            // Never a control: the creature underneath is the button, and a
            // plate that swallowed its click would break the one gesture the
            // scene has.
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(caption.accessibilityLabel)
            // A cross-fade unconditionally: Reduce Motion is about movement,
            // scale and parallax, and a fade is the substitute it asks for
            // rather than something to suppress. The parent owns the one
            // Reduce Motion decision this line needs, so there is no second
            // opinion here to keep in step with it.
            .transition(.opacity)
    }
}
