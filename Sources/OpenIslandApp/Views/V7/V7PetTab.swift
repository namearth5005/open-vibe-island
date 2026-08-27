import SwiftUI
import OpenIslandCore

/// **Pet** — board 03. The room.
///
/// This is the screenshot-and-share tab and the only one allowed to be slow.
/// It is also the only tab that is collage all the way through: wall, hard
/// horizon, patterned floor, rug, the sofa, and the companion on it.
///
/// The seat does the reading work. The companion is dark-bodied here — which
/// only works *because* the rose sofa sits behind it — and one drawn object
/// lands on the floor per session shipped today, so the day accumulates
/// visibly without anything ever asking to be tended.
struct V7PetTab: View {
    var mood: V7CompanionMood
    /// One floor object per ship today. The room keeps score of real
    /// outcomes; nothing accrues from opening the app.
    var shippedToday: Int
    var recap: V7RecapSummary?
    var shelf: [V7ShelfItem]

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            // The hard horizon. Not a gradient — the reference's wall meets
            // its floor on a line.
            let horizon = size.height * 0.46

            ZStack(alignment: .topLeading) {
                V7Tokens.Ground.wallLit

                V7RoomFloor()
                    .frame(width: size.width, height: size.height - horizon)
                    .offset(y: horizon)

                // The rug, under the sofa.
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(V7Tokens.Ground.rug)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color(hex: 0x4D3557), lineWidth: 3)
                    }
                    .frame(width: size.width * 0.56, height: 84)
                    .offset(x: 18, y: size.height - 252)

                V7Sofa()
                    .frame(width: 210, height: 120)
                    .offset(x: 40, y: size.height - 304)

                V7CompanionView(mood: mood, bodyTreatment: .dark)
                    .frame(width: 104, height: 65)
                    .offset(x: 90, y: size.height - 354)

                floorObjects(in: size)

                Text(shippedLine)
                    .font(V7Tokens.Typeface.hand(size: 18))
                    .foregroundStyle(V7Tokens.Ground.paper)
                    .shadow(color: .black.opacity(0.18), radius: 0, y: 1)
                    .offset(x: V7Tokens.Rhythm.sideInset, y: 50)

                if let recap {
                    V7RecapCorner(recap: recap)
                        .offset(x: size.width - 172, y: 60)
                }

                if !shelf.isEmpty {
                    V7ShelfCard(items: shelf)
                        .padding(.horizontal, V7Tokens.Rhythm.sideInset)
                        .frame(width: size.width, alignment: .leading)
                        .offset(y: size.height - 152)
                }
            }
            .frame(width: size.width, height: size.height)
            .v7Grain(0.38)
        }
    }

    private var shippedLine: String {
        switch shippedToday {
        case 0: "nothing shipped yet today"
        case 1: "1 shipped today"
        default: "\(shippedToday) shipped today"
        }
    }

    /// One object per ship, in fixed positions so the room does not rearrange
    /// itself between glances.
    @ViewBuilder
    private func floorObjects(in size: CGSize) -> some View {
        let items = V7FloorObject.allCases.prefix(max(0, min(6, shippedToday)))
        ForEach(Array(items.enumerated()), id: \.element) { index, object in
            object.view
                .frame(width: object.size.width, height: object.size.height)
                .rotationEffect(.degrees(object.rotation))
                .offset(
                    x: size.width * object.position.x,
                    y: size.height * object.position.y
                )
                .zIndex(Double(index))
        }
    }
}

// MARK: - Room pieces

/// The checkered dark floor below the horizon.
struct V7RoomFloor: View {
    var body: some View {
        ZStack {
            V7Tokens.Ground.floor
            Canvas { context, size in
                // Skewed grid, per `room-black-cat.jpg`. Drawn rather than
                // tiled so the skew stays consistent at any panel height.
                var path = Path()
                let spacing: CGFloat = 46
                let skew: CGFloat = 0.21
                var x = -size.height * skew
                while x < size.width + size.height * skew {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x + size.height * skew, y: size.height))
                    x += spacing
                }
                var y: CGFloat = 0
                while y < size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += spacing
                }
                context.stroke(path, with: .color(Color(hex: 0x8D9470).opacity(0.24)), lineWidth: 1.4)
            }
        }
    }
}

/// The rose sofa — the contrast device, at room scale.
struct V7Sofa: View {
    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 210, geometry.size.height / 120)
            ZStack(alignment: .topLeading) {
                // Legs.
                Path { path in
                    path.move(to: CGPoint(x: 30 * scale, y: 106 * scale))
                    path.addLine(to: CGPoint(x: 30 * scale, y: 118 * scale))
                    path.move(to: CGPoint(x: 180 * scale, y: 106 * scale))
                    path.addLine(to: CGPoint(x: 180 * scale, y: 118 * scale))
                }
                .stroke(Color(hex: 0x4D3557), style: StrokeStyle(lineWidth: 5 * scale, lineCap: .round))

                // Back, then seat — both in rose with the clashing contour.
                sofaBlock(x: 16, y: 20, width: 178, height: 64, radius: 16, scale: scale)
                sofaBlock(x: 8, y: 66, width: 194, height: 40, radius: 12, scale: scale)
            }
        }
    }

    private func sofaBlock(
        x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, radius: CGFloat, scale: CGFloat
    ) -> some View {
        RoundedRectangle(cornerRadius: radius * scale, style: .continuous)
            .fill(V7Tokens.Seat.rose.fill)
            .overlay {
                RoundedRectangle(cornerRadius: radius * scale, style: .continuous)
                    .strokeBorder(V7Tokens.Seat.rose.contour, lineWidth: 3 * scale)
            }
            .frame(width: width * scale, height: height * scale)
            .offset(x: x * scale, y: y * scale)
    }
}

// MARK: - Floor objects

/// The drawn things that land on the floor, one per ship.
///
/// Deliberately ordinary objects — a bone, a ball, a plant. Nothing here is a
/// reward the app hands out for attention; each one marks work that shipped.
enum V7FloorObject: CaseIterable, Hashable {
    case bone
    case ball
    case plant
    case mug
    case cushion
    case star

    var size: CGSize {
        switch self {
        case .bone:    CGSize(width: 34, height: 18)
        case .ball:    CGSize(width: 22, height: 22)
        case .plant:   CGSize(width: 26, height: 24)
        case .mug:     CGSize(width: 20, height: 18)
        case .cushion: CGSize(width: 26, height: 20)
        case .star:    CGSize(width: 22, height: 20)
        }
    }

    /// Fractions of the panel, so the room scales without the objects
    /// drifting off the floor.
    var position: CGPoint {
        switch self {
        case .bone:    CGPoint(x: 0.60, y: 0.60)
        case .ball:    CGPoint(x: 0.71, y: 0.66)
        case .plant:   CGPoint(x: 0.80, y: 0.62)
        case .mug:     CGPoint(x: 0.55, y: 0.69)
        case .cushion: CGPoint(x: 0.84, y: 0.70)
        case .star:    CGPoint(x: 0.90, y: 0.58)
        }
    }

    var rotation: Double {
        switch self {
        case .bone:    -8
        case .ball:     0
        case .plant:    0
        case .mug:      6
        case .cushion: -5
        case .star:    10
        }
    }

    private var viewBox: CGRect {
        switch self {
        case .bone:    CGRect(x: 0, y: 0, width: 34, height: 18)
        case .ball:    CGRect(x: 0, y: 0, width: 24, height: 24)
        case .plant:   CGRect(x: 0, y: 0, width: 24, height: 22)
        case .mug:     CGRect(x: 0, y: 0, width: 22, height: 20)
        case .cushion: CGRect(x: 0, y: 0, width: 24, height: 18)
        case .star:    CGRect(x: 0, y: 0, width: 24, height: 22)
        }
    }

    private var shapes: [(d: String, fill: Color, stroke: Color)] {
        switch self {
        case .bone:
            [("M7 4.5 A3.6 3.6 0 1 0 7 12.5 L27 12.5 A3.6 3.6 0 1 0 27 4.5 A3.6 3.6 0 0 0 24 6.2 L10 6.2 A3.6 3.6 0 0 0 7 4.5 Z",
              Color(hex: 0xECE4CD), V7Tokens.Seat.rose.contour)]
        case .ball:
            [("M12 12 m-9.5 0 a9.5 9.5 0 1 0 19 0 a9.5 9.5 0 1 0 -19 0",
              V7Tokens.Accent.link, Color(hex: 0xD9A03F))]
        case .plant:
            [("M7 13 L17 13 L15.6 20 L8.4 20 Z", Color(hex: 0xE26D4F), Color(hex: 0x7D3B1F)),
             ("M12 13 C6 10 5 4 11 2 C14 7 14 10 12 13 Z M12 13 C12 6 16 2 20 4 C20 9 16 12 12 13 Z",
              Color(hex: 0x6F7A54), Color(hex: 0x47543A))]
        case .mug:
            [("M4 4 L15 4 L14.2 16 L4.8 16 Z", Color(hex: 0xDDB14A), V7Tokens.Accent.link)]
        case .cushion:
            [("M2.5 9 C6.5 4 13 4 17 9 C13 14 6.5 14 2.5 9 Z M17 9 L22.5 5 L21.5 9 L22.5 13 Z",
              V7Tokens.Ground.rug, Color(hex: 0x4D3557))]
        case .star:
            [("M12 2 L14.6 8 L21 8.6 L16.2 12.8 L17.8 19 L12 15.6 L6.2 19 L7.8 12.8 L3 8.6 L9.4 8 Z",
              Color(hex: 0xFFD58A), Color(hex: 0xB8862E))]
        }
    }

    @ViewBuilder
    var view: some View {
        ZStack {
            ForEach(Array(shapes.enumerated()), id: \.offset) { _, shape in
                V7VectorShape(shape.d, viewBox: viewBox)
                    .fill(shape.fill)
                    .overlay {
                        V7VectorShape(shape.d, viewBox: viewBox)
                            .stroke(shape.stroke, style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
                    }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Recap corner

/// The torn slip in the room's corner, previewing the weekly recap.
struct V7RecapCorner: View {
    var recap: V7RecapSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("this week")
                .font(V7Tokens.Typeface.hand(size: 12))
                .foregroundStyle(V7Tokens.Text.onCardMuted)
            Text(recap.totalLabel)
                .font(V7Tokens.Typeface.handNumeral(size: 30))
                .foregroundStyle(V7Tokens.Accent.gain)
                .padding(.top, 4)
            Text("the full slip →")
                .font(V7Tokens.Typeface.mono(size: 8.5))
                .foregroundStyle(V7Tokens.Text.onCardMuted)
                .padding(.top, 3)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .frame(width: 128, alignment: .leading)
        .background {
            // Paper does not have soft corners.
            RoundedRectangle(cornerRadius: V7Tokens.Radius.paper, style: .continuous)
                .fill(V7Tokens.Ground.paper)
                .v7Grain(0.35)
        }
        .rotationEffect(.degrees(4))
        .shadow(color: .black.opacity(0.34), radius: 7, y: 7)
    }
}

// MARK: - Shelf

/// A cosmetic earned from a real outcome — completed turns, lines changed, or
/// a day with at least one ship. Never from opening the app.
struct V7ShelfItem: Identifiable, Equatable {
    var id: String
    var label: String
    /// What earned it, or what is still needed.
    var requirement: String
    var earned: Bool
    var object: V7FloorObject
}

/// The cosmetics shelf, in the form of `screen-gallery.jpg`: a plain card, a
/// plain segmented control, a plain grid — and a piece of collage art in every
/// cell. The card is chrome; only the cells are art.
struct V7ShelfCard: View {
    var items: [V7ShelfItem]

    var body: some View {
        V7Card(verticalPadding: 10) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("Shelf — earned from ships")
                        .font(V7Tokens.Typeface.ui(size: 12.5, weight: .semibold))
                        .foregroundStyle(V7Tokens.Text.onCard)
                    Spacer(minLength: 0)
                }

                HStack(spacing: 9) {
                    ForEach(items.prefix(4)) { item in
                        VStack(spacing: 0) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(hex: 0xECE4CD))
                                    .v7Grain(0.32)
                                item.object.view
                                    .frame(width: 32, height: 30)
                            }
                            .frame(height: 52)

                            Text(item.label)
                                .font(V7Tokens.Typeface.mono(size: 8.5))
                                .foregroundStyle(V7Tokens.Text.onCard.opacity(0.75))
                                .padding(.top, 4)
                            Text(item.requirement)
                                .font(V7Tokens.Typeface.mono(size: 8))
                                .foregroundStyle(V7Tokens.Text.onCardMuted)
                        }
                        // Unearned items are visible but dimmed — the shelf
                        // shows what is possible without nagging for it.
                        .opacity(item.earned ? 1 : 0.45)
                    }
                }
                .padding(.top, 9)
            }
        }
    }
}
