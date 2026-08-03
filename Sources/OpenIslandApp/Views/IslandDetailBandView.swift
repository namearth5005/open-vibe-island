import OpenIslandCore
import SwiftUI

/// Clicking a creature, as a rule rather than as a gesture handler.
///
/// The whole of "click to select, click again to deselect" is this one
/// function, so the behaviour can be asserted without rendering anything — a
/// view body cannot be asked what it would do on the second click.
enum IslandSelection {
    /// The selection after clicking `tapped`. Clicking what is already selected
    /// clears it; clicking anything else moves to it, because picking your way
    /// along the band should cost one click per creature, not two.
    static func toggled(current: String?, tapped: String) -> String? {
        current == tapped ? nil : tapped
    }
}

/// What the detail row says about the one selected session.
///
/// The scene says *something needs you*, the strip says *which session*, and
/// this says *what it is actually blocked on and what that has cost so far* —
/// the three numbers a creature has no way to express.
struct IslandSessionDetail: Equatable, Identifiable, Sendable {
    let id: String
    /// Repeated from the strip on purpose: the detail row sits under five cells
    /// and has to name which one it belongs to, or it reads as a caption for
    /// the band rather than for a session.
    let workspace: String
    let pose: CreaturePose
    /// The thing this session is standing there waiting for, or `nil` while it
    /// just works. Kept separate from `headline` so the row can colour a real
    /// question without having to re-derive whether there is one.
    let pendingQuestion: String?
    /// The pending question when there is one, otherwise what the panel's own
    /// cards would say about this session.
    let headline: String
    /// Total time the human has kept this session waiting, across every gate.
    /// `nil` when it has never been blocked, which is a different fact from
    /// having been blocked for under a minute.
    let waiting: IslandDurationGrain?
    let runtime: IslandDurationGrain
    let stallCount: Int

    var waitingBadge: String { waiting?.badge ?? IslandDetailBand.absentBadge }
    var runtimeBadge: String { runtime.badge }
    var stallBadge: String { "\(stallCount)" }

    /// `3` beside a raised-hand glyph is a legend entry, not a sentence.
    static func spokenStalls(_ count: Int) -> String {
        switch count {
        case 0: "never blocked"
        case 1: "blocked once"
        default: "blocked \(count) times"
        }
    }

    /// Everything on the row, in words.
    ///
    /// The three metrics are glyph-and-number pairs on screen, so this sentence
    /// is the only place a screen-reader user learns which number is which.
    var accessibilityDescription: String {
        var parts = [workspace, headline, "\(runtime.spoken) running"]
        if let waiting {
            parts.append("\(waiting.spoken) waiting on you")
        }
        parts.append(Self.spokenStalls(stallCount))
        return parts.joined(separator: ", ")
    }
}

/// The row under the identity strip: what the selected session is doing.
///
/// Split from the view for the same reason the scene and the strip are — the
/// claims worth making are about which session gets described and what its
/// numbers say, and a view body cannot be asserted on.
struct IslandDetailBand: Equatable, Sendable {
    /// 540pt on notch Macs, 520 on external displays — the same band the scene
    /// and the strip are drawn into.
    let width: CGFloat
    /// `nil` when nothing on the island is selected.
    let detail: IslandSessionDetail?

    /// One row of text and its padding, fixed. The session list sits directly
    /// below, and a band that grew when a question arrived would shove the list
    /// down at exactly the moment you were reaching for it.
    static let height: CGFloat = 34

    static let horizontalInset = IslandIdentityStripLayout.horizontalInset
    static let headlineFontSize: CGFloat = 11
    static let metricFontSize: CGFloat = 10
    static let metricSpacing: CGFloat = 10
    static let glyphSpacing: CGFloat = 3

    /// Reserved so the headline truncates instead of pushing the numbers off
    /// the row — the same bargain the strip's elapsed column strikes.
    ///
    /// Wider than the strip's 26pt elapsed column because each of these carries
    /// a glyph as well as a number: `hourglass` plus `<1m` measures 31.5pt, and
    /// the row has 388pt of headline to give up before anything else suffers.
    /// See `IslandDetailBandFitTests`.
    static let metricColumnWidth: CGFloat = 34

    static let emptyMessage = "Select a session to see what it is doing"

    /// A metric with nothing to report. An em dash rather than `0`, because a
    /// zero here would claim a measurement that was never taken.
    static let absentBadge = "—"

    /// Sessions are taken in the order given and truncated at the scene's plot
    /// ceiling, so this band can only ever describe a creature that is actually
    /// on the island. `selectedSessionID` is the whole app's selection and may
    /// well point somewhere else — at an overflowed session, or at one that has
    /// since gone — and captioning that would describe a creature nobody can
    /// see.
    init(
        sessions: [AgentSession],
        geode: GeodeState,
        selectedSessionID: String?,
        width: CGFloat,
        now: Date
    ) {
        self.width = width

        guard let selectedSessionID,
              let session = sessions
                  .prefix(IslandSceneLayout.stationCapacity)
                  .first(where: { $0.id == selectedSessionID })
        else {
            detail = nil
            return
        }

        // Shared with the scene and the strip so the picture, the name and the
        // numbers can never report different states for one session.
        let pose = geode.pose(for: session.id)
        let shard = geode.shard(id: session.id)
        let stallCount = shard?.stallCount ?? 0

        let workspace = session.spotlightWorkspaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let headline = session.spotlightPrimaryText.trimmingCharacters(in: .whitespacesAndNewlines)

        detail = IslandSessionDetail(
            id: session.id,
            workspace: workspace.isEmpty ? "Unknown workspace" : workspace,
            pose: pose,
            pendingQuestion: session.islandPendingQuestion,
            // A blank row would read as a rendering fault rather than as a
            // session with nothing to report — the same failure the strip's
            // "Unknown host" avoids. The pose is already the island's word for
            // what a session is doing, so it stands in rather than a new one.
            headline: headline.isEmpty ? pose.spokenState : headline,
            waiting: stallCount > 0
                ? IslandDurationGrain(seconds: shard?.waitedSeconds(at: now) ?? 0)
                : nil,
            runtime: IslandDurationGrain(seconds: session.islandElapsed(at: now)),
            stallCount: stallCount
        )
    }

    var isEmpty: Bool { detail == nil }
    var height: CGFloat { Self.height }

    /// What the headline has left once the three metric columns have taken
    /// theirs.
    var headlineWidth: CGFloat {
        let metrics = Self.metricColumnWidth * 3 + Self.metricSpacing * 3
        return max(0, width - Self.horizontalInset * 2 - metrics)
    }
}

/// The opened panel's detail row.
///
/// The band above it is forbidden strings and the strip beside it is forbidden
/// state; this row is the one place allowed both, because "what is this session
/// blocked on, and how long has that cost" cannot be said any other way.
struct IslandDetailBandView: View {
    let band: IslandDetailBand

    /// Waited, ran, and how many times it stopped to ask. Named so the fit
    /// tests measure the glyphs this row actually draws rather than a list
    /// someone has to remember to keep in step.
    static let metricSymbols = ["hourglass", "clock", "hand.raised"]

    var body: some View {
        Group {
            if let detail = band.detail {
                content(for: detail)
            } else {
                Text(IslandDetailBand.emptyMessage)
                    .font(.system(size: IslandDetailBand.headlineFontSize))
                    .foregroundStyle(V6Palette.paper.opacity(0.38))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.horizontal, IslandDetailBand.horizontalInset)
        .frame(width: band.width, height: band.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(band.detail?.accessibilityDescription ?? IslandDetailBand.emptyMessage)
    }

    private func content(for detail: IslandSessionDetail) -> some View {
        HStack(spacing: IslandDetailBand.metricSpacing) {
            VStack(alignment: .leading, spacing: 0) {
                Text(detail.workspace)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(V6Palette.paper.opacity(0.42))

                Text(detail.headline)
                    .font(.system(
                        size: IslandDetailBand.headlineFontSize,
                        weight: detail.pendingQuestion == nil ? .regular : .semibold
                    ))
                    // The one coloured thing on the row, and only ever for a
                    // question actually waiting on you — the same amber the
                    // strip reserves for a raised hand.
                    .foregroundStyle(
                        detail.pendingQuestion == nil
                            ? V6Palette.paper.opacity(0.78)
                            : IslandDesignPalette.Status.waitingAggregate
                    )
            }
            .frame(width: band.headlineWidth, alignment: .leading)

            IslandDetailMetric(symbol: Self.metricSymbols[0], value: detail.waitingBadge)
            IslandDetailMetric(symbol: Self.metricSymbols[1], value: detail.runtimeBadge)
            IslandDetailMetric(symbol: Self.metricSymbols[2], value: detail.stallBadge)
        }
    }
}

/// One number and the glyph that says what it counts.
///
/// Glyph-plus-number rather than a labelled pair because three labels would not
/// fit a 540pt row beside a question — the words live in the row's
/// accessibility sentence instead, which is where a screen-reader user needs
/// them anyway.
private struct IslandDetailMetric: View {
    let symbol: String
    let value: String

    var body: some View {
        HStack(spacing: IslandDetailBand.glyphSpacing) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .medium))
            Text(value)
                .font(.system(size: IslandDetailBand.metricFontSize, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(V6Palette.paper.opacity(0.5))
        .frame(width: IslandDetailBand.metricColumnWidth, alignment: .trailing)
    }
}
