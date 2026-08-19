import SwiftUI

/// Frame timing of the companion loop, matching the reference art at 8fps.
private enum CompanionLoop {
    static let frameDuration: Double = 0.125
    static let frameCount = 12

    /// Decoding twelve PNGs per tick would stutter in the menu bar, so they
    /// are decoded once and held.
    static let frames: [NSImage] = (0..<frameCount).map { index in
        let name = String(format: "companion-wag-%02d", index)
        guard let url = Bundle.appResources.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else {
            return NSImage(size: NSSize(width: 1, height: 1))
        }
        return image
    }

    /// Frame index derived from wall-clock time rather than a counter, so the
    /// loop stays correct across view rebuilds and never accumulates drift.
    static func index(at date: Date) -> Int {
        let ticks = Int(date.timeIntervalSinceReferenceDate / frameDuration)
        return ((ticks % frameCount) + frameCount) % frameCount
    }
}

/// The companion animal rendered inside the closed pill.
///
/// Frames come from the reference construction: one body drawing held still
/// while a single severed part rotates. Every frame is pre-composited on a
/// shared canvas with a shared crop, so the character cannot drift between
/// frames — position and dimensions are carried by the images themselves and
/// this view never needs per-frame offsets.
///
/// The body is deliberately light. At 28×32 there is no room for furniture, so
/// the seat-as-contrast trick the source art uses in room scenes is
/// unavailable and the body itself has to carry the contrast against the
/// near-black pill. A dark companion measures as unreadable here.
struct CompanionPillView: View {
    var size: CGFloat = 24
    /// Held on its first frame when idle; only animates when there is activity.
    var isAnimating: Bool = true

    var body: some View {
        Group {
            if isAnimating {
                TimelineView(.periodic(from: .now, by: CompanionLoop.frameDuration)) { context in
                    frameImage(CompanionLoop.index(at: context.date))
                }
            } else {
                frameImage(0)
            }
        }
        .frame(width: size * 0.875, height: size)
        .accessibilityLabel(Text("Companion"))
    }

    private func frameImage(_ index: Int) -> some View {
        Image(nsImage: CompanionLoop.frames[index])
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
    }
}

#Preview("Companion in the closed pill") {
    VStack(spacing: 20) {
        V6ClosedPill(
            mode: .idle,
            label: "Reviewing",
            rightSlot: nil,
            layout: .external,
            showsCompanion: true
        )
        CompanionPillView(size: 96)
            .padding(24)
            .background(V6Palette.ink)
    }
    .padding(40)
    .background(Color.black)
}
