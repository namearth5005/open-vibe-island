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
    static func height(width: CGFloat, sceneHeight: IslandSceneHeight) -> CGFloat {
        IslandSceneLayout.height(width: width, scale: sceneHeight.scale)
            + IslandIdentityStripLayout.height
            + IslandDetailBand.height
    }

    /// Sessions arrive already grouped and sorted — see `AppModel.`
    /// `islandListSessions`. Nothing here re-orders them: the scene's plots, the
    /// strip's cells and the detail row's reachable set are all the first five
    /// of *this* array, so a caller that passed a different order would break
    /// the correspondence between a creature and the name under it.
    init(
        sessions: [AgentSession],
        geode: GeodeState,
        selectedSessionID: String?,
        width: CGFloat,
        sceneHeight: IslandSceneHeight,
        now: Date,
        lang: LanguageManager = .shared
    ) {
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

    var width: CGFloat { scene.width }

    /// The instance's own total, which must equal what `height(width:sceneHeight:)`
    /// promised the window sizer — asserted rather than assumed, because the two
    /// diverging is exactly the bug that clips a band or leaves a gap under it.
    var height: CGFloat { scene.height + strip.height + detail.height }
}

/// The island, above the session list.
///
/// A plain vertical stack and nothing else. Every decision worth making — what
/// stands where, what is named, what is described — was made by the three
/// layouts before this view was handed one, which is what keeps this file short
/// and the composition point in `IslandPanelView` a single line.
struct IslandBandView: View {
    let layout: IslandBandLayout
    let selectedSessionID: String?
    /// Handed straight through to both interactive bands so the scene and the
    /// strip drive one rule rather than two — the creature and its name are the
    /// same button drawn twice.
    let onActivate: (String, CreaturePose) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            IslandSceneView(
                layout: layout.scene,
                selectedSessionID: selectedSessionID,
                onActivate: onActivate
            )
            // Over the scene rather than inside it, for two reasons: the scene
            // hides itself from VoiceOver and this line is the one part of the
            // band that is only words, and a line drawn in the stack would add
            // its height to the panel for the 45 seconds it exists.
            .overlay {
                if let voice = layout.voice {
                    IslandVoiceCaptionView(caption: voice)
                        // Keyed on the speaker, so a handover from one creature
                        // to another is an insert and a remove rather than one
                        // plate. Without this the `if let` keeps its identity
                        // across the change and `.position` animates instead —
                        // the plate slides across the band, hanging for a
                        // quarter second over creatures that did not say it,
                        // which is exactly the attribution the geometry exists
                        // to make.
                        .id(voice.sessionID)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: layout.voice)

            IslandIdentityStripView(
                layout: layout.strip,
                selectedSessionID: selectedSessionID,
                onActivate: onActivate
            )

            IslandDetailBandView(band: layout.detail)
        }
        .frame(width: layout.width, height: layout.height)
    }
}
