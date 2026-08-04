import OpenIslandCore
import SwiftUI

/// One session's entry in the identity strip: the facts a painted creature has
/// no way to express.
///
/// The scene above renders no strings at all, so this is where *which agent*,
/// *which host* and *which workspace* live. `pose` is carried only so the cell
/// can mirror the raised hand — it is the one piece of state the strip is
/// allowed to know about, because a screen-reader user has the words instead of
/// the gesture.
struct IslandIdentityCell: Equatable, Identifiable, Sendable {
    let id: String
    /// The repo or worktree. Nothing in the picture encodes this — plots are
    /// positions, not names — so it is the strip's whole reason to exist.
    let workspace: String
    let agent: String
    /// `nil` when the session was discovered before its host was known. That is
    /// the same gap that puts the creature at the scene's `workshop`, and it is
    /// a fact rather than an error.
    let host: String?
    /// Stored as a grain rather than as a string so the 26pt badge and the
    /// spoken sentence are two renderings of one rounding, never two.
    let runtime: IslandDurationGrain
    let pose: CreaturePose

    /// A blank line would read as a rendering fault rather than as an unknown,
    /// which is exactly the failure the scene's `workshop` structure avoids.
    ///
    /// Resolved when the layout is built rather than computed on demand: the
    /// layout is the one place that holds a `LanguageManager`, and storing the
    /// finished text keeps this a plain `Equatable` value instead of something
    /// carrying a reference to a translation engine.
    let hostLabel: String

    /// What activating this cell will do.
    ///
    /// The scene is hidden from VoiceOver, so this button is the only way a
    /// screen-reader or keyboard user reaches a creature — which makes it the
    /// only place they can be warned that this particular one answers with a
    /// jump into another app rather than by moving a highlight.
    let activationHint: String

    /// Everything the scene shows, in words.
    ///
    /// The scene is `accessibilityHidden`, so a screen-reader user gets the
    /// whole island from this sentence — which means it carries the state the
    /// picture carries visually, even though the visible cell does not.
    let accessibilityDescription: String

    var elapsed: String { runtime.badge }

    /// The sanctioned exception to "the strip never holds a mood": this cell is
    /// the accessible mirror of the raised hand, so it has to be able to say
    /// *this one* out loud and on screen.
    var needsAttention: Bool { pose.isAskingForYou }
}

extension CreaturePose {
    /// The spoken counterpart of the pose, matching `GeodeShardView`'s
    /// accessibility vocabulary so the pill and the panel describe a blocked
    /// session with the same words.
    func spokenState(_ lang: LanguageManager) -> String {
        lang.t(spokenStateKey)
    }

    /// Separated from the lookup so tests can assert that four poses map to four
    /// distinct keys without depending on what any locale translates them to.
    var spokenStateKey: String {
        switch self {
        case .working: "island.pose.working"
        case .waiting: "island.pose.waiting"
        case .holding: "island.pose.holding"
        case .fallen: "island.pose.fallen"
        }
    }
}

/// The text band under the scene: one cell per creature, plus an honest account
/// of the sessions that did not fit.
///
/// Split from the view for the same reason `IslandSceneLayout` is: the claims
/// worth making here are that nothing overruns 540pt and that no fact gets
/// squeezed out by another, and a view body cannot be asserted on.
///
/// Cells divide the band evenly instead of sitting on the scene's fixed station
/// pitch. At the ceiling the two agree to within a few points, which is when
/// the eye needs the correspondence; below it, honouring the pitch would strand
/// a lone session's name in a 112pt column with 400pt of empty band beside it.
struct IslandIdentityStripLayout: Equatable, Sendable {
    /// How many sessions the strip names before it starts counting instead.
    ///
    /// Was `Self.cellCapacity`, where it was a *spacing* limit —
    /// five plots at the 540pt band's 112pt pitch, below which a creature ran
    /// into its neighbour. The scene is gone; the cap survives because the strip
    /// and the detail row still cap on it, and it is now simply the number of
    /// sessions worth naming rather than a geometry constraint.
    static let cellCapacity = 5

    /// 540pt on notch Macs, 520 on external displays — the same band the scene
    /// is drawn into.
    let width: CGFloat
    let cells: [IslandIdentityCell]
    /// Sessions the scene collapsed into its badge. Counted here too, because a
    /// session that vanishes between the two bands is worse than one that never
    /// had a plot.
    let overflow: Int

    /// Three single-line rows and their padding, fixed. Nothing in a cell may
    /// wrap, so the band's height never depends on how long a workspace is
    /// called — see `IslandIdentityStripFitTests`.
    static let height: CGFloat = 64

    /// Matches the session list's own side inset, so the two panel bands share
    /// one left edge.
    static let horizontalInset: CGFloat = 16
    static let cellSpacing: CGFloat = 8
    static let rowSpacing: CGFloat = 2
    static let verticalPadding: CGFloat = 10

    /// Wide enough for the longest agent name and a useful slice of a workspace
    /// name, and no wider: a four-word caption stretched across half a panel
    /// reads as a layout fault, and it would strand the elapsed badge far from
    /// the host it shares a row with.
    static let maximumCellWidth: CGFloat = 172

    /// Mirrors the scene's `+N` badge.
    static let overflowColumnWidth: CGFloat = 34

    /// The elapsed badge is reserved rather than laid out inline, so a long
    /// host name truncates instead of pushing the duration off the row.
    static let elapsedColumnWidth: CGFloat = 26
    static let elapsedSpacing: CGFloat = 4

    static let workspaceFontSize: CGFloat = 11.5
    static let agentFontSize: CGFloat = 10
    static let hostFontSize: CGFloat = 9.5

    /// An island with nobody on it is a state, not a fault. The scene draws an
    /// empty meadow; this says the same thing in words.
    static let emptyMessageKey = "island.strip.empty"

    /// Resolved at construction, like every other string on the band.
    let emptyMessage: String

    /// Sessions are taken in the order given and never re-sorted — the caller
    /// owns ordering, exactly as the scene requires, or cell *n* would stop
    /// captioning station *n*.
    init(
        sessions: [AgentSession],
        geode: GeodeState,
        width: CGFloat,
        now: Date,
        lang: LanguageManager = .shared
    ) {
        self.width = width
        emptyMessage = lang.t(Self.emptyMessageKey)

        cells = sessions.prefix(Self.cellCapacity).map { session in
            let rawHost = session.jumpTarget?.terminalApp.trimmingCharacters(in: .whitespacesAndNewlines)
            let host = rawHost?.isEmpty == false ? rawHost : nil
            let rawWorkspace = session.spotlightWorkspaceName.trimmingCharacters(in: .whitespacesAndNewlines)
            let workspace = rawWorkspace.isEmpty ? lang.t("island.unknownWorkspace") : rawWorkspace
            let pose = geode.pose(for: session.id)
            let runtime = IslandDurationGrain(seconds: session.islandElapsed(at: now))

            return IslandIdentityCell(
                id: session.id,
                workspace: workspace,
                agent: session.tool.displayName,
                host: host,
                runtime: runtime,
                pose: pose,
                hostLabel: host ?? lang.t("island.unknownHost"),
                activationHint: lang.t(
                    pose.isAskingForYou ? "island.strip.hint.jumps" : "island.strip.hint.selects"
                ),
                // Assembled from a format string rather than by concatenation so
                // a translator can reorder the clauses — Chinese puts the host
                // before the agent, which string interpolation cannot express.
                accessibilityDescription: lang.t(
                    "island.strip.spoken",
                    workspace,
                    session.tool.displayName,
                    host ?? lang.t("island.unknownHost.spoken"),
                    pose.spokenState(lang),
                    runtime.spoken(lang)
                )
            )
        }

        // The ceiling is the scene's, not a second one: the strip captions what
        // was drawn, so both bands hide the same sessions.
        overflow = max(0, sessions.count - Self.cellCapacity)

        overflowDescription = overflow > 0
            ? lang.t(overflow == 1 ? "island.overflow.spoken.one" : "island.overflow.spoken.many", overflow)
            : nil
    }

    var isEmpty: Bool { cells.isEmpty }
    var height: CGFloat { Self.height }
    var cellWidth: CGFloat { Self.cellWidth(count: cells.count, width: width, overflow: overflow) }

    /// What the host line has left once the elapsed badge has taken its column.
    var hostWidth: CGFloat {
        max(0, cellWidth - Self.elapsedColumnWidth - Self.elapsedSpacing)
    }

    /// Deliberately the same glyph the scene puts in its own corner: one badge
    /// in the picture and the same badge in the text reads as a legend entry
    /// rather than as two unrelated counts.
    var overflowBadge: String? {
        overflow > 0 ? "+\(overflow)" : nil
    }

    /// `+3` is a glyph, not a sentence, and this band is where a screen-reader
    /// user learns those sessions exist at all.
    ///
    /// Two keys rather than one with a count, because plural agreement is not a
    /// property a format string can carry across the languages this app ships.
    let overflowDescription: String?

    /// Even division of whatever the overflow column left behind, capped.
    static func cellWidth(count: Int, width: CGFloat, overflow: Int) -> CGFloat {
        guard count > 0 else { return 0 }

        var available = width - horizontalInset * 2
        if overflow > 0 {
            available -= overflowColumnWidth + cellSpacing
        }
        available -= cellSpacing * CGFloat(count - 1)

        return min(maximumCellWidth, max(0, available) / CGFloat(count))
    }
}

/// The opened panel's identity strip.
///
/// Per the design's clarity rule the picture carries state and the text carries
/// identity, so this band names things and does not colour them — with the one
/// exception of a session that is waiting on you, which is the accessible
/// mirror of the creature's raised hand.
///
/// It is also the island's accessible surface: the scene is hidden from
/// VoiceOver on purpose, so every cell here speaks the state the picture shows.
/// That is why selection is reachable here and not only by clicking a creature
/// — each cell is a real `Button`, so Tab reaches it and Space activates it.
///
/// Activating a cell does exactly what clicking its creature does, jump and
/// all, because a keyboard path that could only ever select would leave the
/// island's one useful action reachable by mouse alone.
struct IslandIdentityStripView: View {
    let layout: IslandIdentityStripLayout
    let selectedSessionID: String?
    let onActivate: (String, CreaturePose) -> Void

    var body: some View {
        HStack(spacing: IslandIdentityStripLayout.cellSpacing) {
            if layout.isEmpty {
                Text(layout.emptyMessage)
                    .font(.system(size: IslandIdentityStripLayout.agentFontSize, weight: .medium))
                    .foregroundStyle(V6Palette.paper.opacity(0.42))
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(layout.cells) { cell in
                    Button {
                        onActivate(cell.id, cell.pose)
                    } label: {
                        IslandIdentityCellView(
                            cell: cell,
                            width: layout.cellWidth,
                            hostWidth: layout.hostWidth,
                            isSelected: cell.id == selectedSessionID
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(cell.accessibilityDescription)
                    .accessibilityHint(cell.activationHint)
                    // Selection is a state a screen reader announces, not a
                    // colour it can see. Without this the ring would be the
                    // only thing that said which session is selected.
                    .accessibilityAddTraits(
                        cell.id == selectedSessionID ? [.isButton, .isSelected] : .isButton
                    )
                }

                if let badge = layout.overflowBadge, let spoken = layout.overflowDescription {
                    Text(badge)
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(V6Palette.paper.opacity(0.5))
                        .frame(width: IslandIdentityStripLayout.overflowColumnWidth, alignment: .trailing)
                        .accessibilityLabel(spoken)
                }
            }
        }
        .padding(.horizontal, IslandIdentityStripLayout.horizontalInset)
        .frame(width: layout.width, height: layout.height)
        .accessibilityElement(children: .contain)
    }
}

/// One cell: three single-line rows, most-specific first.
///
/// Each fact owns its own row so no fact can starve another — a long workspace
/// name truncates itself rather than pushing the agent or the host out of the
/// cell, which is the difference between truncating gracefully and losing
/// information.
private struct IslandIdentityCellView: View {
    let cell: IslandIdentityCell
    let width: CGFloat
    let hostWidth: CGFloat
    let isSelected: Bool

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: IslandIdentityStripLayout.rowSpacing) {
            Text(cell.workspace)
                .font(.system(size: IslandIdentityStripLayout.workspaceFontSize, weight: .semibold))
                .foregroundStyle(workspaceColor)

            Text(cell.agent)
                .font(.system(size: IslandIdentityStripLayout.agentFontSize, weight: .medium))
                .foregroundStyle(V6Palette.paper.opacity(0.66))

            HStack(spacing: IslandIdentityStripLayout.elapsedSpacing) {
                Text(cell.hostLabel)
                    .font(.system(size: IslandIdentityStripLayout.hostFontSize))
                    .frame(width: hostWidth, alignment: .leading)

                Text(cell.elapsed)
                    .font(.system(size: IslandIdentityStripLayout.hostFontSize, weight: .medium, design: .monospaced))
                    .frame(width: IslandIdentityStripLayout.elapsedColumnWidth, alignment: .trailing)
            }
            .foregroundStyle(V6Palette.paper.opacity(0.48))
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(width: width, alignment: .leading)
        .padding(.vertical, IslandIdentityStripLayout.verticalPadding)
        .background(cellBacking)
        .overlay(selectionRing)
        // The enclosing button owns this cell's label and traits, so the cell
        // itself must not also publish one or VoiceOver would find two.
        .accessibilityHidden(true)
    }

    /// Attention and selection are separate channels and can be true at once:
    /// the amber wash means *this one needs you*, the lift and ring mean *this
    /// is the one the detail row is describing*. Folding them into one
    /// treatment would make selecting a waiting session hide that it is
    /// waiting.
    ///
    /// Both sit on the same shape and the same insets so a cell that is
    /// both reads as one panel rather than as two boxes of different size.
    private static let backingShape = RoundedRectangle(cornerRadius: 7, style: .continuous)

    /// Wider than the text so the highlight reads as a panel rather than as a
    /// box drawn round three words, but not so wide that two adjacent cells run
    /// into each other; inset vertically so it does not butt against the scene.
    private static let backingInsets = EdgeInsets(top: 3, leading: -3, bottom: 3, trailing: -3)

    /// Both washes go behind the text. A selection fill drawn over it would
    /// veil the very name it is pointing at.
    @ViewBuilder
    private var cellBacking: some View {
        ZStack {
            attentionBacking

            if isSelected {
                Self.backingShape
                    .fill(V6Palette.paper.opacity(0.09))
                    .padding(Self.backingInsets)
            }
        }
    }

    /// The edge, over the text, because a 1pt line has to sit above the wash to
    /// be an edge at all. A lift this faint is easy to miss on its own against
    /// a dark panel; the ring is what makes it unambiguous.
    @ViewBuilder
    private var selectionRing: some View {
        if isSelected {
            Self.backingShape
                .stroke(V6Palette.paper.opacity(0.5), lineWidth: 1)
                .padding(Self.backingInsets)
                .allowsHitTesting(false)
        }
    }

    private var workspaceColor: Color {
        cell.needsAttention
            ? IslandDesignPalette.Status.waitingAggregate
            : V6Palette.paper.opacity(0.92)
    }

    @ViewBuilder
    private var attentionBacking: some View {
        if cell.needsAttention {
            Self.backingShape
                .fill(IslandDesignPalette.Status.waitingAggregate.opacity(0.14))
                // Increased-contrast users get an explicit edge rather than a
                // wash they may not resolve — the same accommodation the shard
                // makes for its frozen state.
                .overlay {
                    if contrast == .increased {
                        Self.backingShape
                            .stroke(IslandDesignPalette.Status.waitingAggregate.opacity(0.85), lineWidth: 1)
                    }
                }
                .padding(Self.backingInsets)
        }
    }
}
