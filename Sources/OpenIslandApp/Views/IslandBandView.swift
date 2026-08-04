import OpenIslandCore
import SwiftUI

/// The three island bands as one block, and the height they come to.
///
/// Tasks 2–4 built the scene, the strip and the detail row as separate pieces
/// that knew nothing about each other beyond a shared width. This is where they
/// become one thing: they are always drawn together, they always caption the
/// same sessions in the same order, and — because the panel's height is decided
/// by AppKit before SwiftUI ever runs — the space they need has to be a number
/// somebody can ask for in advance.
///
/// That is the whole reason this type exists rather than three calls at the
/// composition point. `OverlayPanelController` sizes the window from
/// `height(width:sceneHeight:)`; the panel draws `IslandBandView` from an
/// instance. One formula, two readers, so the window cannot be sized for a band
/// of a different height than the one drawn into it.
struct IslandBandLayout: Equatable, Sendable {
    /// The whole of what the island now draws.
    ///
    /// The three layouts below are still built because task 3 owns removing
    /// them and the tests that pin them; nothing renders them any more.
    let companion: IslandCompanionRow
    let scene: IslandSceneLayout
    let strip: IslandIdentityStripLayout
    let detail: IslandDetailBand
    /// What a creature that has just finished cleanly is saying, or `nil` for
    /// silence — which is almost always. Drawn over the scene, so it is absent
    /// from `height` on purpose: a completion is a moment, and a moment may not
    /// resize the panel.
    let voice: IslandVoiceCaption?

    /// What the band costs, without building one.
    ///
    /// Static because the window is sized before there is anything to draw —
    /// `panelSize(for:on:)` runs whenever the screen or the session list
    /// changes, and constructing three layouts there to read one number would
    /// mean walking the session list on every screen-configuration event.
    /// Width no longer enters it: the row is one line of content beside one
    /// character, so it costs the same on a 520pt external display as on a
    /// 760pt panel. That is the structural fix, not a simplification — round
    /// 1's height was derived from width through the scene's aspect, which is
    /// how widening the panel made the creature a *smaller* share of it.
    static func height(width: CGFloat, sceneHeight: IslandSceneHeight) -> CGFloat {
        IslandCompanionRow.height(scale: sceneHeight.scale)
    }

    /// Sessions arrive already grouped and sorted — see `AppModel.`
    /// `islandListSessions`. Nothing here re-orders them: the scene's plots, the
    /// strip's cells and the detail row's reachable set are all the first five
    /// of *this* array, so a caller that passed a different order would break
    /// the correspondence between a creature and the name under it.
    init(
        sessions: [AgentSession],
        geode: GeodeState,
        records: [SessionLogRecord] = [],
        species: CreatureSpecies = IslandCompanionRow.defaultSpecies,
        selectedSessionID: String?,
        width: CGFloat,
        sceneHeight: IslandSceneHeight,
        now: Date,
        lang: LanguageManager = .shared
    ) {
        companion = IslandCompanionRow(
            sessions: sessions,
            geode: geode,
            records: records,
            species: species,
            width: width,
            heightScale: sceneHeight.scale,
            now: now,
            lang: lang
        )

        let scene = IslandSceneLayout(
            sessions: sessions,
            geode: geode,
            width: width,
            heightScale: sceneHeight.scale
        )
        self.scene = scene
        let strip = IslandIdentityStripLayout(
            sessions: sessions,
            geode: geode,
            width: width,
            now: now,
            lang: lang
        )
        self.strip = strip
        // After the strip, because the caption borrows the name the strip has
        // already resolved for its speaker rather than resolving a second one.
        voice = IslandVoiceCaption.resolve(
            scene: scene,
            strip: strip,
            geode: geode,
            now: now,
            lang: lang
        )
        detail = IslandDetailBand(
            sessions: sessions,
            geode: geode,
            selectedSessionID: selectedSessionID,
            width: width,
            now: now,
            lang: lang
        )
    }

    var width: CGFloat { companion.width }

    /// The instance's own total, which must equal what `height(width:sceneHeight:)`
    /// promised the window sizer — asserted rather than assumed, because the two
    /// diverging is exactly the bug that clips a band or leaves a gap under it.
    var height: CGFloat { companion.height }
}

/// The island, above the session list.
///
/// One row and nothing else. Every decision worth making — what the companion
/// is doing, what the day came to — was made by `IslandCompanionRow` before
/// this view was handed one, which is what keeps the composition point in
/// `IslandPanelView` a single line.
///
/// It is not interactive. Round 1's band was, because a creature stood for a
/// session and clicking it meant something; this companion stands for the list
/// as a whole, and the list itself is directly below and already clickable.
struct IslandBandView: View {
    let layout: IslandBandLayout

    var body: some View {
        // No frame here: `IslandCompanionRowView` already sizes itself from the
        // same layout, and a second copy of the numbers is a second place they
        // can disagree.
        IslandCompanionRowView(row: layout.companion)
    }
}
