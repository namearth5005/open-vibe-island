import OpenIslandCore
import SwiftUI

extension Color {
    init(_ creature: CreatureColor) {
        self.init(
            .sRGB,
            red: Double(creature.red) / 255,
            green: Double(creature.green) / 255,
            blue: Double(creature.blue) / 255,
            opacity: 1
        )
    }
}

/// One session's creature.
///
/// Renders the shipped sprite when it exists and falls back to the procedural
/// silhouette when it does not, so a missing asset degrades to a readable shape
/// rather than an empty slot.
///
/// `waiting` alternates between two frames — the raised arm and the bent
/// mid-wave. That is deliberate: at 28 × 32 pt motion is far more detectable in
/// peripheral vision than detail is, and the wave is the notification. Every
/// other pose is still, because a pose that moves when nothing is wrong trains
/// the eye to ignore movement.
struct CreatureView: View {
    let species: CreatureSpecies
    let pose: CreaturePose
    let seed: UInt64
    var size: CGSize = CreatureView.pillSize

    /// The measured right-slot lane. Width binds, not height.
    static let pillSize = CGSize(width: 28, height: 32)
    /// Panel render, twice the pill.
    static let panelSize = CGSize(width: 56, height: 64)

    /// Slow enough to read as a wave rather than a flicker.
    private static let waveInterval: TimeInterval = 0.45

    @State private var showsAlternate = false

    private var currentSpriteName: String {
        if showsAlternate, let alternate = CreatureSprite.alternateName(for: species, pose: pose) {
            return alternate
        }
        return CreatureSprite.name(for: species, pose: pose)
    }

    var body: some View {
        Group {
            if let sprite = CreatureSprite.image(named: currentSpriteName) {
                Image(nsImage: sprite)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                CreatureSilhouetteShape(seed: seed, pose: pose)
                    .fill(Color(CreaturePalette.color(for: species)))
            }
        }
        .frame(width: size.width, height: size.height)
        .animation(.smooth(duration: 0.28), value: pose)
        .task(id: pose) {
            showsAlternate = false
            guard pose == .waiting, CreatureSprite.alternateName(for: species, pose: pose) != nil else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.waveInterval))
                if Task.isCancelled { return }
                showsAlternate.toggle()
            }
        }
    }
}

/// Fallback silhouette, drawn from the same `CreatureSilhouette` definition the
/// gate harness measures — so what a missing sprite degrades to is exactly what
/// was legibility-tested, not a second guess at it.
struct CreatureSilhouetteShape: Shape {
    let seed: UInt64
    let pose: CreaturePose

    func path(in rect: CGRect) -> Path {
        Path(CreatureSilhouette.path(for: CreatureForm.make(seed: seed, pose: pose), in: rect))
    }
}
