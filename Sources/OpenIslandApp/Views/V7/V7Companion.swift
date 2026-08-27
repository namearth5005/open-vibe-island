import SwiftUI
import OpenIslandCore

/// The companion — a concierge, not a pet.
///
/// Its visual state is a truthful reflection of how the fleet is doing. It has
/// no needs of its own: no hunger meter, no decay, nothing to feed. Its needs
/// are the fleet's needs, and it never demands attention.
///
/// Four rules from the brief govern the construction, each of which has
/// already sent this work the wrong way once:
///
/// 1. **Dark in the room, light in the pill.** A dark silhouette is invisible
///    on the pill's near-black ground. The reference's black cat only works
///    because it sits on a pink sofa, and the pill has no room for furniture.
/// 2. **Marks are a value + saturation jump, not a hue clash.** Body `#2a2623`
///    → accent `#97923f` is only 31° of hue but +0.43 value and +0.42 saturation.
/// 3. **Flat mass survives downsampling; rendered fur does not.** At 28×32pt
///    any modelled shading turns to mush.
/// 4. **Each mood needs a silhouette difference, not just an expression.** At
///    pill size an expression is four pixels.
enum V7CompanionMood: String, CaseIterable, Identifiable, Sendable {
    case asleep
    case working
    case anxious
    case bored
    case celebrating
    case delivering

    var id: String { rawValue }

    /// Shown on the character sheet and in the debug mood switcher.
    var displayName: String {
        switch self {
        case .asleep:      "asleep"
        case .working:     "working"
        case .anxious:     "anxious, pointing"
        case .bored:       "bored"
        case .celebrating: "celebrating"
        case .delivering:  "delivering"
        }
    }

    /// What puts the companion into this mood. Every mood is caused by the
    /// fleet, never by elapsed time or neglect.
    var trigger: String {
        switch self {
        case .asleep:      "nothing running"
        case .working:     "agents busy"
        case .anxious:     "a session is erroring"
        case .bored:       "idle, nothing queued"
        case .celebrating: "a session shipped"
        case .delivering:  "the concierge has news"
        }
    }

    // MARK: Silhouettes — verbatim from board 10

    var viewBox: CGRect {
        switch self {
        case .asleep, .working, .bored: CGRect(x: 0, y: 0, width: 128, height: 80)
        case .anxious:                  CGRect(x: 0, y: 0, width: 136, height: 84)
        case .celebrating:              CGRect(x: 0, y: 0, width: 150, height: 112)
        case .delivering:               CGRect(x: 0, y: 0, width: 126, height: 90)
        }
    }

    /// The one flat mass. No interior modelling, ever.
    var bodyPath: String {
        switch self {
        case .asleep:
            "M16 66 C10 52 20 44 40 43 C62 42 88 42 106 46 C120 49 124 60 118 66 Z"
        case .working:
            "M26 66 C16 66 12 56 16 46 C22 34 34 28 48 28 C52 18 64 12 76 15 C90 18 98 30 96 42 C108 46 114 56 110 66 L102 68 L96 58 L42 58 L36 68 Z"
        case .anxious:
            "M30 78 C18 78 12 66 17 54 C22 42 32 34 46 32 C49 20 61 12 75 14 C89 16 99 28 97 41 L128 24 L123 41 C112 45 108 50 106 58 C104 68 99 76 90 78 Z"
        case .bored:
            "M18 68 C10 58 18 48 38 46 C58 44 84 44 102 48 C116 51 120 62 112 68 L58 68 Z"
        case .celebrating:
            "M52 104 C40 104 34 94 36 82 C38 66 44 56 56 50 C54 34 60 20 74 16 C90 11 106 20 110 34 C114 48 110 60 102 66 C110 76 114 90 110 104 Z"
        case .delivering:
            "M26 78 C16 78 12 68 16 58 C20 44 30 36 44 34 C48 22 60 14 74 16 C90 18 100 30 98 44 C110 48 116 60 112 74 L104 78 L98 66 L40 66 L34 78 Z"
        }
    }

    /// The closed-eye arc. One of only two interior marks.
    var eyePath: String {
        switch self {
        case .asleep:      "M44 54 C50 50 58 50 64 54"
        case .working:     "M58 30 C64 26 72 26 78 30"
        case .anxious:     "M55 30 C61 25 71 25 78 30"
        case .bored:       "M44 57 C50 54 58 54 64 57"
        case .celebrating: "M70 32 C77 27 87 27 94 32"
        case .delivering:  "M60 33 C66 28 76 28 83 33"
        }
    }

    /// The single dot. The entire mark vocabulary is this plus the arc —
    /// never pupils, never whisker clusters, never more than five marks.
    var dot: CGPoint {
        switch self {
        case .asleep:      CGPoint(x: 98, y: 53)
        case .working:     CGPoint(x: 87, y: 26)
        case .anxious:     CGPoint(x: 86, y: 24)
        case .bored:       CGPoint(x: 95, y: 55)
        case .celebrating: CGPoint(x: 101, y: 26)
        case .delivering:  CGPoint(x: 90, y: 27)
        }
    }

    /// Where the tail hangs off the mass, in viewBox units.
    var tailAnchor: CGPoint {
        switch self {
        case .asleep:      CGPoint(x: 22, y: 64)
        case .working:     CGPoint(x: 24, y: 62)
        case .anxious:     CGPoint(x: 26, y: 74)
        case .bored:       CGPoint(x: 24, y: 66)
        case .celebrating: CGPoint(x: 44, y: 100)
        case .delivering:  CGPoint(x: 24, y: 74)
        }
    }

    static let tailPath =
        "M0 0 C-13 -2 -19 -15 -10 -25 C-8 -27 -3 -26 -5 -21 C-10 -13 -6 -5 5 -5 Z"

    /// The mood the fleet is actually in.
    ///
    /// Ranked by urgency, not by count: one session needing a human outranks
    /// nine happily running. `anxious` is reserved for a genuine error — it is
    /// the mood that points, and it must stay rare enough to mean something.
    static func forFleet(
        sessions: [AgentSession],
        shippedRecently: Bool = false
    ) -> V7CompanionMood {
        guard !sessions.isEmpty else { return .asleep }

        if sessions.contains(where: { $0.phase.requiresAttention }) {
            return .delivering
        }
        if shippedRecently, sessions.contains(where: { $0.phase == .completed }) {
            return .celebrating
        }
        if sessions.contains(where: { $0.phase == .running }) {
            return .working
        }
        return .bored
    }
}

// MARK: - The body treatment

/// Which body a companion is wearing. The choice is not decorative: a dark
/// body needs a seat behind it, and a light body is the only one that survives
/// the pill's near-black ground.
enum V7CompanionBody {
    /// For the room, where a saturated seat sits behind it.
    case dark
    /// For the pill and bare ink.
    case light
    /// The gray cat, for the character sheet.
    case gray

    var mass: Color {
        switch self {
        case .dark:  V7Tokens.Character.bodyDark
        case .light: V7Tokens.Character.bodyLight
        case .gray:  V7Tokens.Character.bodyGray
        }
    }

    var mark: Color {
        switch self {
        case .dark:  V7Tokens.Character.markOnDark
        case .light: V7Tokens.Character.markOnLight
        case .gray:  V7Tokens.Character.bodyLight
        }
    }
}

// MARK: - The companion view

/// Renders the companion at any size.
///
/// The layer stack, from back to front, is board 3b exactly:
/// tail → tan core (coarse tear, scaled 1.055) → mass (fine tear) → marks.
/// Motion never touches the edge — the layers move as one rigid group, because
/// an animated tear reads as boiling and destroys the illusion that the paper
/// is a physical object.
struct V7CompanionView: View {
    var mood: V7CompanionMood
    var bodyTreatment: V7CompanionBody = .dark
    /// The idle loop. Off for the character sheet and for static contexts.
    var animated: Bool = true
    /// Below this width the tear and the tan core are dropped and the flat
    /// mass is drawn clean — at pill size the fibre is sub-pixel and only
    /// muddies the silhouette.
    var minimumTornWidth: CGFloat = 44

    @State private var bobbing = false
    @State private var tailSwinging = false
    @State private var blinking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var movesIdly: Bool { animated && !reduceMotion }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let box = mood.viewBox
            let scale = min(size.width / box.width, size.height / box.height)
            let torn = size.width >= minimumTornWidth

            ZStack {
                tail(scale: scale, in: size)

                if torn {
                    // The warm tan backing paper showing through the tear.
                    // Scaled 1.055 with a coarser seed so it peeks past the
                    // mass — this is what sells torn paper rather than vector.
                    V7TornEdge(
                        d: mood.bodyPath,
                        viewBox: box,
                        amplitude: 2.4,
                        seed: 3,
                        coherence: 3
                    )
                    .fill(V7Tokens.Character.core)
                    .scaleEffect(1.055, anchor: .init(x: 0.5, y: 0.66))
                }

                Group {
                    if torn {
                        V7TornEdge(d: mood.bodyPath, viewBox: box, amplitude: 1.3, seed: 7)
                            .fill(bodyTreatment.mass)
                    } else {
                        V7VectorShape(mood.bodyPath, viewBox: box)
                            .fill(bodyTreatment.mass)
                    }
                }

                marks(scale: scale, in: size)
            }
            .frame(width: size.width, height: size.height)
            // The whole rig bobs as one rigid piece. 1.6pt and half a degree —
            // small enough to read as breathing, never as bouncing.
            .rotationEffect(.degrees(bobbing ? 0.5 : 0), anchor: .bottom)
            .offset(y: bobbing ? 1.6 : 0)
        }
        .onAppear(perform: startIdleLoop)
        .onChange(of: movesIdly) { _, _ in startIdleLoop() }
        .animation(.easeInOut(duration: 0.2), value: mood)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(mood.displayName))
        .accessibilityValue(Text(mood.trigger))
    }

    // MARK: Layers

    @ViewBuilder
    private func tail(scale: CGFloat, in size: CGSize) -> some View {
        let anchor = mood.tailAnchor
        let box = mood.viewBox
        let offsetX = (size.width - box.width * scale) / 2 + anchor.x * scale
        let offsetY = (size.height - box.height * scale) / 2 + anchor.y * scale

        Path { path in
            path.addPath(
                V7VectorPath.parse(V7CompanionMood.tailPath),
                transform: CGAffineTransform(scaleX: scale, y: scale)
            )
        }
        .fill(bodyTreatment.mass)
        .rotationEffect(.degrees(tailSwinging ? 7 : -5), anchor: .topLeading)
        .offset(x: offsetX, y: offsetY)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    @ViewBuilder
    private func marks(scale: CGFloat, in size: CGSize) -> some View {
        let box = mood.viewBox
        let dx = (size.width - box.width * scale) / 2
        let dy = (size.height - box.height * scale) / 2
        // Marks stay crisp — only the paper tears — and their stroke scales
        // up at small sizes so they survive the pill.
        let strokeWidth = max(2.6 * scale, size.width < minimumTornWidth ? 1.4 : 1.0)
        let dotRadius = max(2.8 * scale, size.width < minimumTornWidth ? 1.5 : 1.0)

        ZStack(alignment: .topLeading) {
            V7VectorShape(mood.eyePath, viewBox: box)
                .stroke(
                    bodyTreatment.mark,
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .frame(width: size.width, height: size.height)
                // One slow blink. Scaling the arc flat is the whole gesture.
                .scaleEffect(y: blinking ? 0.12 : 1, anchor: .center)

            Circle()
                .fill(bodyTreatment.mark)
                .frame(width: dotRadius * 2, height: dotRadius * 2)
                .offset(
                    x: dx + mood.dot.x * scale - dotRadius,
                    y: dy + mood.dot.y * scale - dotRadius
                )
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    // MARK: The idle loop
    //
    // Rigid transforms only: bob 3.4s, tail 2.9s, blink ~6s. The animal
    // arrives once and stays — it does not wander or patrol.

    private func startIdleLoop() {
        guard movesIdly else {
            bobbing = false
            tailSwinging = false
            blinking = false
            return
        }
        withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
            bobbing = true
        }
        withAnimation(.easeInOut(duration: 1.45).repeatForever(autoreverses: true)) {
            tailSwinging = true
        }
        // The blink is a flick inside a long cycle, not a slow squint, so it
        // gets its own short animation rather than a symmetric autoreverse.
        withAnimation(
            .easeInOut(duration: 0.12)
                .repeatForever(autoreverses: true)
                .delay(6.2)
        ) {
            blinking = true
        }
    }
}

// MARK: - The pill plate

/// The companion at true 28×32, flat, no tear, no tan core.
///
/// This is the brutal test: flat mass survives downsampling, rendered fur does
/// not. Ships as a pre-baked light-body plate; until those land this draws the
/// same silhouette clean.
struct V7CompanionPillPlate: View {
    var mood: V7CompanionMood
    var width: CGFloat = 28
    var height: CGFloat = 32

    var body: some View {
        V7CompanionView(
            mood: mood,
            bodyTreatment: .light,
            animated: false,
            // Force the clean path at every pill size.
            minimumTornWidth: .greatestFiniteMagnitude
        )
        .frame(width: width, height: height)
    }
}
