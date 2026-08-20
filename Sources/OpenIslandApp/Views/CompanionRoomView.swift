import SwiftUI
import OpenIslandCore

/// Room artwork, decoded once. Same reasoning as `CompanionArt`: decoding on
/// every render would stutter, and these are larger.
private enum RoomArt {
    static func image(_ name: String, _ ext: String) -> NSImage? {
        guard let url = Bundle.appResources.url(forResource: name, withExtension: ext) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    static let wall = image("room-wall", "jpg")
    static let floor = image("room-floor", "jpg")
    static let companion = image("room-companion", "png")
    static let rug = image("room-rug", "png")
}

/// The opened island rendered as the companion's room.
///
/// The composition is borrowed wholesale from the reference art, and it is
/// load-bearing rather than decorative: **text on the wall, scene on the
/// floor.** The wall is a quiet, low-texture plane, so session rows sit on it
/// at full contrast with no plate behind them. All the pattern and grain lives
/// below the horizon where no text goes. That is what lets the panel be a warm
/// illustrated place and still be read under time pressure.
///
/// The urgent row is an ink-inverted plate rather than a warm accent. On warm
/// paper, near-black is the loudest thing available and — critically — it is a
/// hue absent from the illustration, so it keeps a pop-out channel the artwork
/// cannot compete in.
struct CompanionRoomView: View {
    var sessions: [AgentSession]

    /// The panel's height is content-driven -- roughly 145pt with one session,
    /// 550pt with twelve -- and the view cannot widen or lengthen it from here.
    /// So the room scales with whatever it is given rather than demanding a
    /// minimum: a fixed floor height simply pushes the scene below the clip.
    /// The companion shrinks with the floor so it is never cropped.
    /// Below this the panel cannot hold a scene AND a readable row -- at 145pt
    /// the floor takes 49, the headline 26, and the single remaining row gets
    /// clipped mid-height by the horizon. Under it the room drops the floor
    /// entirely and becomes a warm wall, which still reads and never crops text.
    private static let minRoomHeight: CGFloat = 260

    private func floorHeight(for size: CGSize) -> CGFloat {
        size.height >= Self.minRoomHeight ? size.height * 0.34 : 0
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                room(size: geo.size)
                // Clamped to the wall. Text must never cross the horizon onto
                // the patterned floor -- the floor carries all the grain, and
                // legibility depends on text staying on the quiet plane.
                // A ScrollView here collapses inside the ZStack, so the row
                // count is capped to what the wall can hold instead.
                sessionList(rowLimit: rowsThatFit(in: geo.size))
                    .padding(.horizontal, 22)
                    .padding(.top, 16)
                    .frame(
                        maxWidth: geo.size.width * 0.82,
                        maxHeight: geo.size.height - floorHeight(for: geo.size) - 20,
                        alignment: .topLeading
                    )
                    .clipped()
            }
        }
    }

    // MARK: Room

    private func room(size: CGSize) -> some View {
        let floorH = floorHeight(for: size)
        return ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                plate(RoomArt.wall).frame(height: max(0, size.height - floorH))
                plate(RoomArt.floor).frame(height: floorH)
            }

            // No rug. At panel size it renders as a sliver behind the chair
            // legs and reads as debris rather than grounding.
            if floorH > 0, let dog = RoomArt.companion {
                Image(nsImage: dog)
                    .resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(height: floorH * 1.30)
                    .offset(y: -floorH * 0.04)
                    .padding(.trailing, size.width * 0.05)
            }
        }
        .clipped()
    }

    private func plate(_ image: NSImage?) -> some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                RoomPalette.paper
            }
        }
    }

    // MARK: List

    /// Roughly how many rows the wall can hold, from the measured row height
    /// plus spacing, after the headline has taken its share.
    private func rowsThatFit(in size: CGSize) -> Int {
        let available = size.height - floorHeight(for: size) - 20 - 16 - 26
        return max(1, Int(available / 52))
    }

    private func sessionList(rowLimit: Int) -> some View {
        let shown = Array(sessions.prefix(rowLimit))
        let hidden = sessions.count - shown.count
        return VStack(alignment: .leading, spacing: 14) {
            Text(headline)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(RoomPalette.ink)

            if sessions.isEmpty {
                Text("Start a coding agent in your terminal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(RoomPalette.inkSoft)
            }

            ForEach(shown, id: \.id) { session in
                row(for: session)
            }

            if hidden > 0 {
                Text("+\(hidden) more")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(RoomPalette.inkSoft)
            }
        }
    }

    private var headline: String {
        if sessions.isEmpty { return "Nothing running" }
        let running = sessions.filter { $0.phase == .running }.count
        switch running {
        case 0:  return "All done"
        case 1:  return "1 agent working"
        default: return "\(running) agents working"
        }
    }

    @ViewBuilder
    private func row(for session: AgentSession) -> some View {
        let urgent = session.phase.requiresAttention
        VStack(alignment: .leading, spacing: 3) {
            Text(session.jumpTarget?.workspaceName ?? session.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(urgent ? RoomPalette.paper : RoomPalette.ink)
            Text(session.phase.displayName)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(urgent ? RoomPalette.paperDim : RoomPalette.inkSoft)
        }
        .padding(.horizontal, urgent ? 10 : 0)
        .padding(.vertical, urgent ? 7 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if urgent {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(RoomPalette.ink)
            }
        }
    }
}

/// Two text tiers only. A third would land on the elapsed-time column, and on
/// warm textured paper it measures around 3:1 -- readable on a good display at
/// 2x and not at a glance on a dim external monitor.
enum RoomPalette {
    static let paper = Color(red: 0.969, green: 0.945, blue: 0.902)
    static let paperDim = Color(red: 0.913, green: 0.871, blue: 0.808)
    static let ink = Color(red: 0.173, green: 0.141, blue: 0.118)
    static let inkSoft = Color(red: 0.408, green: 0.353, blue: 0.298)
}
