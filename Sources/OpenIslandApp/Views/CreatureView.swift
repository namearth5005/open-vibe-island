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
    /// The resting frame's basename.
    let frameName: String
    /// The frame it alternates with, or `nil` when this one is still.
    let alternateFrameName: String?
    /// The shape drawn when the sprite is missing.
    let fallbackPose: CreaturePose
    let seed: UInt64
    var size: CGSize = CreatureView.pillSize
    /// Where the sprite sits inside `size` when it does not fill it. Sprites are
    /// trimmed to their content, so aspect varies by species and pose and one of
    /// the two axes is always slack. `.bottom` is what puts several creatures on
    /// a shared ground line; the default stays centered so the single-creature
    /// pill is unaffected.
    var alignment: Alignment = .center

    /// A session's creature, which is always in a pose.
    init(
        species: CreatureSpecies,
        pose: CreaturePose,
        seed: UInt64,
        size: CGSize = CreatureView.pillSize,
        alignment: Alignment = .center
    ) {
        self.species = species
        frameName = CreatureSprite.name(for: species, pose: pose)
        alternateFrameName = CreatureSprite.alternateName(for: species, pose: pose)
        fallbackPose = pose
        self.seed = seed
        self.size = size
        self.alignment = alignment
    }

    /// The one companion, which reacts to the whole list and can therefore be in
    /// a state no single session has — `asleep`, which no pose can express.
    ///
    /// A second *initialiser* rather than a second view, so waking up and
    /// falling asleep stay inside one node. Branching on the state in a view
    /// body would make `_ConditionalContent` of it: crossing the boundary would
    /// tear down the subtree, reset the wave and make the day's first session
    /// and its last the only two transitions that structurally cannot animate.
    init(
        species: CreatureSpecies,
        state: CompanionState,
        seed: UInt64,
        size: CGSize = CreatureView.pillSize,
        alignment: Alignment = .center
    ) {
        self.species = species
        frameName = CreatureSprite.name(for: species, state: state)
        alternateFrameName = CreatureSprite.alternateName(for: species, state: state)
        fallbackPose = CreatureSprite.fallbackPose(for: state)
        self.seed = seed
        self.size = size
        self.alignment = alignment
    }

    /// The measured right-slot lane. Width binds, not height.
    static let pillSize = CGSize(width: 28, height: 32)
    /// Panel render, twice the pill.
    static let panelSize = CGSize(width: 56, height: 64)

    /// Slow enough to read as a wave rather than a flicker.
    private static let waveInterval: TimeInterval = 0.45

    @State private var showsAlternate = false

    private var currentSpriteName: String {
        showsAlternate ? (alternateFrameName ?? frameName) : frameName
    }

    var body: some View {
        Group {
            if let sprite = CreatureSprite.image(named: currentSpriteName) {
                Image(nsImage: sprite)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                CreatureSilhouetteShape(seed: seed, pose: fallbackPose)
                    .fill(Color(CreaturePalette.color(for: species)))
            }
        }
        .frame(width: size.width, height: size.height, alignment: alignment)
        .animation(.smooth(duration: 0.28), value: frameName)
        .task(id: frameName) {
            showsAlternate = false
            guard alternateFrameName != nil else { return }
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
