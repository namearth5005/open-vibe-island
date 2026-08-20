import SwiftUI

/// Image cache for the companion's poses.
///
/// Decoding a PNG on every render would stutter in the menu bar, so each pose
/// is decoded once on first use and held.
private enum CompanionArt {
    static let images: [CompanionPose: NSImage] = {
        var out: [CompanionPose: NSImage] = [:]
        for pose in CompanionPose.allCases {
            guard let url = Bundle.appResources.url(forResource: pose.assetName, withExtension: "png"),
                  let image = NSImage(contentsOf: url)
            else { continue }
            out[pose] = image
        }
        return out
    }()

    static let fallback = NSImage(size: NSSize(width: 1, height: 1))
}

/// The companion animal in the closed pill.
///
/// The pose IS the readout: sleeping when nothing runs, alert while agents
/// work, attending when one needs the developer. It is STILL at rest -- a loop
/// running all day spends peripheral attention continuously (motion onset is
/// involuntary) in exchange for no information.
///
/// The body is deliberately light. At 28x32 there is no room for furniture, so
/// the seat-as-contrast trick the source art uses in room scenes is unavailable
/// and the body itself must carry contrast against the near-black pill.
struct CompanionPillView: View {
    var pose: CompanionPose
    var size: CGFloat = 24

    var body: some View {
        Image(nsImage: CompanionArt.images[pose] ?? CompanionArt.fallback)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size * 0.875, height: size)
            .accessibilityLabel(Text("Companion"))
    }
}

#Preview("Companion poses") {
    VStack(spacing: 20) {
        ForEach(CompanionPose.allCases, id: \.self) { pose in
            HStack(spacing: 24) {
                CompanionPillView(pose: pose, size: 24)
                CompanionPillView(pose: pose, size: 96)
            }
            .padding(16)
            .background(V6Palette.ink)
        }
    }
    .padding(40)
    .background(Color.black)
}
