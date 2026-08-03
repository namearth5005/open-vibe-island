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

    var elapsed: String { runtime.badge }

    /// The sanctioned exception to "the strip never holds a mood": this cell is
    /// the accessible mirror of the raised hand, so it has to be able to say
    /// *this one* out loud and on screen.
    var needsAttention: Bool { pose == .waiting }

    /// A blank line would read as a rendering fault rather than as an unknown,
    /// which is exactly the failure the scene's `workshop` structure avoids.
    var hostLabel: String { host ?? "Unknown host" }

    /// Everything the scene shows, in words.
    ///
    /// The scene is `accessibilityHidden`, so a screen-reader user gets the
    /// whole island from this sentence — which means it carries the state the
    /// picture carries visually, even though the visible cell does not.
    var accessibilityDescription: String {
        "\(workspace), \(agent) at \(host ?? "an unknown host"), \(pose.spokenState), \(runtime.spoken) elapsed"
    }
}

extension CreaturePose {
    /// The spoken counterpart of the pose, matching `GeodeShardView`'s
    /// accessibility vocabulary so the pill and the panel describe a blocked
    /// session with the same words.
    var spokenState: String {
        switch self {
        case .working: "running"
        case .waiting: "waiting for you"
        case .holding: "finished"
        case .fallen: "interrupted"
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
    static let emptyMessage = "No sessions on the island"

    /// Sessions are taken in the order given and never re-sorted — the caller
    /// owns ordering, exactly as the scene requires, or cell *n* would stop
    /// captioning station *n*.
    init(sessions: [AgentSession], geode: GeodeState, width: CGFloat, now: Date) {
        self.width = width

        cells = sessions.prefix(IslandSceneLayout.stationCapacity).map { session in
            let host = session.jumpTarget?.terminalApp.trimmingCharacters(in: .whitespacesAndNewlines)
            let workspace = session.spotlightWorkspaceName.trimmingCharacters(in: .whitespacesAndNewlines)

            return IslandIdentityCell(
                id: session.id,
                workspace: workspace.isEmpty ? "Unknown workspace" : workspace,
                agent: session.tool.displayName,
                host: host?.isEmpty == false ? host : nil,
                runtime: IslandDurationGrain(seconds: session.islandElapsed(at: now)),
                pose: geode.pose(for: session.id)
            )
        }

        // The ceiling is the scene's, not a second one: the strip captions what
        // was drawn, so both bands hide the same sessions.
        overflow = max(0, sessions.count - IslandSceneLayout.stationCapacity)
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
    var overflowDescription: String? {
        guard overflow > 0 else { return nil }
        return overflow == 1
            ? "1 more session not shown"
            : "\(overflow) more sessions not shown"
    }

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
struct IslandIdentityStripView: View {
    let layout: IslandIdentityStripLayout

    var body: some View {
        HStack(spacing: IslandIdentityStripLayout.cellSpacing) {
            if layout.isEmpty {
                Text(IslandIdentityStripLayout.emptyMessage)
                    .font(.system(size: IslandIdentityStripLayout.agentFontSize, weight: .medium))
                    .foregroundStyle(V6Palette.paper.opacity(0.42))
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(layout.cells) { cell in
                    IslandIdentityCellView(
                        cell: cell,
                        width: layout.cellWidth,
                        hostWidth: layout.hostWidth
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
        .background(attentionBacking)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cell.accessibilityDescription)
    }

    private var workspaceColor: Color {
        cell.needsAttention
            ? IslandDesignPalette.Status.waitingAggregate
            : V6Palette.paper.opacity(0.92)
    }

    @ViewBuilder
    private var attentionBacking: some View {
        if cell.needsAttention {
            let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
            shape
                .fill(IslandDesignPalette.Status.waitingAggregate.opacity(0.14))
                // Increased-contrast users get an explicit edge rather than a
                // wash they may not resolve — the same accommodation the shard
                // makes for its frozen state.
                .overlay {
                    if contrast == .increased {
                        shape.stroke(IslandDesignPalette.Status.waitingAggregate.opacity(0.85), lineWidth: 1)
                    }
                }
                // Wider than the text so the highlight reads as a panel rather
                // than as a box drawn round three words, but not so wide that
                // two adjacent waiting sessions run into each other; inset
                // vertically so it does not butt against the scene above.
                .padding(EdgeInsets(top: 3, leading: -3, bottom: 3, trailing: -3))
        }
    }
}
