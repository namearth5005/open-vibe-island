import SwiftUI
import OpenIslandCore

/// Faceted shard silhouette. Every parameter — facet radii, tilt, stretch, and
/// the stage-driven scale — comes from the pure `ShardForm`, so a given session
/// always draws the same outline at a given stage.
///
/// Alternating vertices are pulled inward, which is what turns a blob into
/// something angular. Verified legible at 20pt against `V6Palette.ink`.
struct GeodeShardShape: Shape {
    let form: ShardForm

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard form.facets.count >= 3 else { return path }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 * form.scale
        let step = (2 * Double.pi) / Double(form.facets.count)

        for (index, multiplier) in form.facets.enumerated() {
            // Odd vertices pulled in to make points rather than bulges.
            let inset = index.isMultiple(of: 2) ? multiplier : multiplier * Self.notchDepth
            let angle = form.tilt + step * Double(index)
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle) * inset) * radius,
                y: center.y + CGFloat(sin(angle) * inset * form.elongation * Self.stretch) * radius
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }

    /// How far inward the alternating vertices pull. Lower is spikier.
    private static let notchDepth: Double = 0.52
    /// Extra vertical exaggeration on top of the form's own elongation.
    private static let stretch: Double = 1.35
}

/// One shard at pill scale.
///
/// The frozen state is this feature's notification channel — when a session
/// blocks on the human the shard stops growing and desaturates. That change has
/// to be readable in peripheral vision, so it moves on two channels at once
/// (hue drains *and* motion stops) rather than relying on colour alone.
struct GeodeShardView: View {
    let shard: GeodeShard
    var size: CGFloat = 18

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        shape
            .frame(width: size, height: size)
            .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: shard.isFrozen)
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
    }

    // MARK: - Rendering

    @ViewBuilder
    private var shape: some View {
        if reduceMotion {
            // No growth pop — the stage change still applies, it just doesn't
            // overshoot. Size continues to communicate progress.
            styledShard
        } else {
            styledShard
                .keyframeAnimator(
                    initialValue: 1.0,
                    trigger: shard.stage
                ) { content, value in
                    content.scaleEffect(value)
                } keyframes: { _ in
                    // Overshoot then settle. This is the beat that makes each
                    // growth step feel like something happened.
                    KeyframeTrack {
                        SpringKeyframe(1.18, duration: 0.18, spring: .snappy)
                        SpringKeyframe(1.0, duration: 0.28, spring: .smooth)
                    }
                }
        }
    }

    private var styledShard: some View {
        // `shard.form` re-derives geometry from the seed on every access, so it
        // is read once per render rather than once per layer.
        let form = shard.form
        return GeodeShardShape(form: form)
            .fill(fillColor)
            .overlay {
                if shard.isFractured {
                    GeodeFractureLine()
                        .stroke(V6Palette.ink.opacity(0.85), lineWidth: fractureWidth)
                }
            }
            .overlay {
                // Increased-contrast users get an explicit outline so the frozen
                // state does not depend on a subtle luminance shift.
                if contrast == .increased {
                    GeodeShardShape(form: form)
                        .stroke(V6Palette.paper.opacity(shard.isFrozen ? 0.9 : 0.35), lineWidth: 1)
                }
            }
    }

    private var fillColor: Color {
        guard !shard.isFrozen else {
            // Matte, drained, obviously inert.
            return V6Palette.paper.opacity(contrast == .increased ? 0.45 : 0.30)
        }
        let brand = Color(hex: shard.tool.brandColorHex) ?? V6Palette.paper
        return contrast == .increased ? brand : brand.opacity(0.95)
    }

    private var fractureWidth: CGFloat {
        contrast == .increased ? 1.6 : 1.0
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        "\(shard.tool.displayName) session"
    }

    private var accessibilityValue: String {
        if shard.isFrozen {
            return "waiting for you"
        }
        if shard.isFractured {
            return "interrupted"
        }
        if shard.isSet {
            return "finished"
        }
        return "running, stage \(shard.stage) of 6"
    }
}

/// A single cleave across the silhouette. One line reads at 18pt where a
/// spider-web of cracks would turn to mush.
private struct GeodeFractureLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.20, y: rect.minY + rect.height * 0.70))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.24, y: rect.minY + rect.height * 0.26))
        return path
    }
}
