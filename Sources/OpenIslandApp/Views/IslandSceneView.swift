import OpenIslandCore
import SwiftUI

/// One session's plot in the scene band: a creature standing at a structure.
///
/// The creature says *which agent*, the structure says *where it runs*. Both are
/// derived, never stored — the same rule the shard and the pose already follow.
struct IslandStation: Equatable, Identifiable, Sendable {
    let id: String
    let species: CreatureSpecies
    let pose: CreaturePose
    let structure: CreatureStructure
    let seed: UInt64
    /// Horizontal center of the plot, in points from the band's leading edge.
    let center: CGFloat
}

/// Where every creature stands in the scene band, and how many did not fit.
///
/// Split out of the view because determinism is the property that matters here
/// and a view body cannot be asserted on: the same sessions in the same order
/// must always place the same creatures in the same spots, or the band becomes
/// a thing you have to re-read instead of glance at.
struct IslandSceneLayout: Equatable, Sendable {
    /// Band width — 540pt on notch Macs, 520 on external displays.
    let width: CGFloat
    let stations: [IslandStation]
    /// Sessions past the plot ceiling. Zero when every session is drawn.
    let overflow: Int

    /// `scene-band.png` is 1080x300px, so the band is 540x150pt at 2x. Height is
    /// derived rather than configurable because a mismatch would stretch the
    /// horizon, and a stretched horizon reads as a rendering bug.
    static let bandAspect: CGFloat = 3.6

    /// Five plots, because the sixth would collide.
    ///
    /// Pitch at the 540pt panel is 112pt; below ~90pt a station's structure runs
    /// into its neighbour's. Six plots would need 78pt.
    static let stationCapacity = 5
    static let minimumStationPitch: CGFloat = 90

    /// Distance from the band edge to the outermost plot's center. This is the
    /// widest a station can get (~40pt either side of its plot, set by the
    /// broadest sprite in the set) plus slack, so a full band touches the inset
    /// with neither end clipping off the edge.
    static let edgeInset: CGFloat = 46

    var height: CGFloat { width / Self.bandAspect }

    /// Sessions are taken in the order given and never re-sorted. Sorting by
    /// state would make creatures swap plots the moment an agent changed what it
    /// was doing, and a scene whose inhabitants move is a scene you have to
    /// re-read; the caller owns ordering.
    init(sessions: [AgentSession], geode: GeodeState, width: CGFloat) {
        self.width = width

        let drawn = sessions.prefix(Self.stationCapacity)
        let centers = Self.centers(count: drawn.count, width: width)

        stations = zip(drawn, centers).map { session, center in
            IslandStation(
                id: session.id,
                species: CreatureSpecies(tool: session.tool),
                // Shared with the identity strip so the picture and the words
                // can never report different states for the same session.
                pose: geode.pose(for: session.id),
                // The jump target is optional — a session discovered before its
                // host is known still has to stand somewhere, and `workshop` is
                // the answer for a host nobody has taught the app about yet.
                structure: session.jumpTarget.map { CreatureStructure(terminalApp: $0.terminalApp) }
                    ?? .workshop,
                seed: ShardSeed.value(for: session.id),
                center: center
            )
        }

        overflow = max(0, sessions.count - Self.stationCapacity)
    }

    /// Constant across plot counts, so spacing does not breathe as sessions come
    /// and go — only the group's extent does.
    static func pitch(width: CGFloat) -> CGFloat {
        (width - edgeInset * 2) / CGFloat(stationCapacity - 1)
    }

    /// Evenly spaced at the fixed pitch, centered on the band. A full band lands
    /// exactly on `edgeInset` at both ends.
    static func centers(count: Int, width: CGFloat) -> [CGFloat] {
        guard count > 0 else { return [] }
        let pitch = pitch(width: width)
        let first = width / 2 - pitch * CGFloat(count - 1) / 2
        return (0..<count).map { first + pitch * CGFloat($0) }
    }
}

/// The opened panel's scene band.
///
/// Carries no strings. Per the design's clarity rule the picture carries state
/// and the text carries identity, so which agent and which workspace belong to
/// the identity strip below — this band may only say that something is running,
/// something needs you, or something finished. The overflow count is the one
/// numeral allowed: it is an amount, not a name.
struct IslandSceneView: View {
    let layout: IslandSceneLayout
    let selectedSessionID: String?
    /// Clicking a plot. The band never decides what a click *means* — it hands
    /// up the ID and the pose it drew and renders whatever comes back, so the
    /// scene and the strip drive one rule rather than two. The pose travels
    /// with the click so that what happens is what the picture promised, even
    /// if the session changed state in the same frame.
    let onActivate: (String, CreaturePose) -> Void

    /// Flat bundle, bare filename — see `CreatureSprite.image(named:)`.
    static let backgroundName = "scene-band"

    /// Where feet meet the ground, as a fraction of band height. Puts the plots
    /// on the near meadow with their heads against the hill rather than the sky.
    private static let groundFraction: CGFloat = 0.88

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Behind the artwork rather than instead of it: a missing background
            // leaves the band dark, never transparent onto the panel below.
            Rectangle().fill(V6Palette.ink)

            if let background = CreatureSprite.image(named: Self.backgroundName) {
                Image(nsImage: background)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            }

            ForEach(layout.stations) { station in
                IslandStationView(
                    station: station,
                    isSelected: station.id == selectedSessionID
                )
                .onTapGesture { onActivate(station.id, station.pose) }
                .position(
                    x: station.center,
                    y: layout.height * Self.groundFraction - IslandStationView.height / 2
                )
            }

            if layout.overflow > 0 {
                // Up in the sky, not down on the ground: a full band puts a
                // creature in every bottom corner, and a badge there would sit
                // on top of one of them.
                IslandOverflowBadge(count: layout.overflow)
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
                    .padding(10)
            }
        }
        .frame(width: layout.width, height: layout.height)
        .clipped()
        // Decorative to VoiceOver on purpose. Everything here is also carried in
        // words by the identity strip, and narrating a landscape would put the
        // scene between a screen-reader user and the session list.
        .accessibilityHidden(true)
    }
}

/// One plot: the structure set back and to the left, the creature in front of
/// its near corner, both standing on the same ground line.
struct IslandStationView: View {
    let station: IslandStation
    let isSelected: Bool

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Wider than it is tall, because sprites are trimmed to their content and
    /// the broadest standing pose is very nearly square. Every standing creature
    /// is therefore bound by the box's *height* and comes out the same size,
    /// which is what makes a row of mixed species read as one scene.
    ///
    /// `fallen` is the deliberate exception: those sprites are wider still, so
    /// they bind on width and render shorter — a knocked-over creature ought to
    /// be lower than a standing one.
    static let creatureBox = CGSize(width: 58, height: 54)
    static let structureSide: CGFloat = 42
    static var height: CGFloat { max(creatureBox.height, structureSide) }

    /// Offsets from the plot center. The creature overlaps the structure's near
    /// corner, which is what makes the pair read as one station rather than as
    /// two unrelated sprites. The pair leans right of the plot so that its
    /// combined footprint straddles the plot evenly — otherwise the outermost
    /// station on a full band sits visibly closer to its edge than its opposite
    /// number does to the other.
    private static let structureOffsetX: CGFloat = -19
    private static let creatureOffsetX: CGFloat = 9

    /// Light on the ground the pair is standing on, rather than a box drawn
    /// round it: a rectangle here would read as a UI control dropped into a
    /// painting, and the plot is a place, not a cell.
    private static let markerSize = CGSize(width: 62, height: 16)

    var body: some View {
        ZStack(alignment: .bottom) {
            groundMarker

            if let image = CreatureSprite.image(named: CreatureSprite.name(for: station.structure)) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: Self.structureSide, height: Self.structureSide)
                    .offset(x: Self.structureOffsetX)
            }

            CreatureView(
                species: station.species,
                pose: station.pose,
                seed: station.seed,
                size: Self.creatureBox,
                alignment: .bottom
            )
            .offset(x: Self.creatureOffsetX)
        }
        .frame(height: Self.height, alignment: .bottom)
        // The sprites are mostly transparent, so without this only the painted
        // pixels of a creature would answer a click.
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    /// Selection is the strong state and hover only a hint that the plot
    /// answers to a click — hover has to be visible enough to invite the click
    /// and faint enough that nobody mistakes it for the selection.
    ///
    /// Light on dark, which is the opposite of the overflow badge's rule and
    /// for the same reason: the badge sits up in the bright sky, and the plots
    /// stand on the near meadow, which is the darkest part of the painting.
    @ViewBuilder
    private var groundMarker: some View {
        Ellipse()
            .fill(V6Palette.paper)
            .frame(width: Self.markerSize.width, height: Self.markerSize.height)
            .blur(radius: 6)
            .opacity(isSelected ? 0.5 : (isHovered ? 0.16 : 0))
            .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: isSelected)
            .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: isHovered)
            .offset(x: Self.creatureOffsetX, y: 4)
            .allowsHitTesting(false)
    }
}

/// The sessions that did not fit, as a count.
///
/// Ink rather than the pill's translucent paper, because this sits over a bright
/// landscape where a light wash would disappear.
private struct IslandOverflowBadge: View {
    let count: Int

    var body: some View {
        Text("+\(count)")
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(V6Palette.paper)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(V6Palette.ink.opacity(0.72)))
    }
}
