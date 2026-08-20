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

/// Emits at randomised intervals so the companion's unprompted motion has no
/// detectable period. A single idle loop becomes consciously noticeable at
/// roughly ninety seconds, and this view is on screen for eight hours.
struct ArrhythmicSchedule: TimelineSchedule {
    /// A value-type iterator, mirroring every schedule SwiftUI ships --
    /// `PeriodicTimelineSchedule.Entries` and its siblings are all `Sendable`
    /// structs. An `AnyIterator` would box its state in a closure and make
    /// `Entries` non-Sendable, which the protocol does not forbid and so the
    /// compiler would never flag.
    struct Entries: Sequence, IteratorProtocol, Sendable {
        fileprivate var date: Date
        fileprivate let range: ClosedRange<TimeInterval>

        mutating func next() -> Date? {
            date = date.addingTimeInterval(.random(in: range))
            return date
        }
    }

    var range: ClosedRange<TimeInterval>

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(date: startDate, range: range)
    }
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

    /// How far the whole body tips during a hello-wag. Small on purpose: the
    /// point is a sign of life, not a performance.
    private static let wagDegrees: Double = 3.5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if CompanionMotion.shouldAnimate(reduceMotion: reduceMotion) {
                TimelineView(ArrhythmicSchedule(range: 45...180)) { context in
                    still
                        .rotationEffect(.degrees(wagAngle(at: context.date)), anchor: .bottom)
                        .animation(.easeInOut(duration: 0.45), value: context.date)
                }
            } else {
                still
            }
        }
        .frame(width: size * 0.875, height: size)
        .accessibilityLabel(Text("Companion"))
    }

    private var still: some View {
        Image(nsImage: CompanionArt.images[pose] ?? CompanionArt.fallback)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
    }

    /// Alternates the tip direction so successive wags do not all lean the same
    /// way, which would read as a drift rather than a movement.
    private func wagAngle(at date: Date) -> Double {
        let tick = Int(date.timeIntervalSinceReferenceDate)
        return tick.isMultiple(of: 2) ? Self.wagDegrees : -Self.wagDegrees
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
