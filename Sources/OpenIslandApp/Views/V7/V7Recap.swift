import SwiftUI

/// **The weekly recap** — board 11, in the form of `screen-receipt.jpg`.
///
/// A torn paper slip at an angle, itemised, gains in green, losses in red, a
/// bold TOTAL. It celebrates *shipping* — never app-opening, never streaks of
/// attention — because the whole product falls apart the moment the character
/// starts rewarding the user for looking at it.
struct V7RecapSummary: Equatable {
    var dateRange: String
    var lines: [Line]
    /// What the concierge handled so the user did not have to.
    var total: Int

    struct Line: Identifiable, Equatable {
        var id: String { label }
        var label: String
        var value: String
        var tone: Tone

        enum Tone { case gain, loss, neutral }
    }

    var totalLabel: String { total >= 0 ? "+\(total)" : "\(total)" }
}

extension V7RecapSummary.Line.Tone {
    var color: Color {
        switch self {
        case .gain:    V7Tokens.Accent.gain
        case .loss:    V7Tokens.Accent.loss
        case .neutral: V7Tokens.Text.onCard
        }
    }
}

/// The shareable slip. Exports at 2× on paper, with no app chrome around it.
struct V7RecapSlip: View {
    var recap: V7RecapSummary
    /// The slip sits at a slight angle, as a physical object would.
    var angle: Double = -2.5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("the week, settled")
                    .font(V7Tokens.Typeface.hand(size: 20))
                    .foregroundStyle(V7Tokens.Text.onCard)
                Spacer(minLength: 0)
                Text(recap.dateRange)
                    .font(V7Tokens.Typeface.mono(size: 9))
                    .foregroundStyle(V7Tokens.Text.onCardMuted)
            }

            perforation.padding(.top, 10).padding(.bottom, 6)

            ForEach(recap.lines) { line in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(line.label)
                        .font(V7Tokens.Typeface.hand(size: 15.5))
                        .foregroundStyle(V7Tokens.Text.onCard)
                    Spacer(minLength: 0)
                    Text(line.value)
                        .font(V7Tokens.Typeface.handNumeral(size: 22))
                        .foregroundStyle(line.tone.color)
                }
                .padding(.vertical, 2.5)
            }

            perforation.padding(.vertical, 8)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("TOTAL, handled without you")
                    .font(V7Tokens.Typeface.hand(size: 16, weight: .bold))
                    .foregroundStyle(V7Tokens.Text.onCard)
                Spacer(minLength: 0)
                Text(recap.totalLabel)
                    .font(V7Tokens.Typeface.handNumeral(size: 34))
                    .foregroundStyle(V7Tokens.Accent.gain)
            }

            HStack(spacing: 10) {
                V7CompanionView(mood: .asleep, bodyTreatment: .dark, animated: false)
                    .frame(width: 34, height: 21)
                Text("your fleet, minded —\nopen island")
                    .font(V7Tokens.Typeface.hand(size: 12.5))
                    .foregroundStyle(V7Tokens.Text.onCard.opacity(0.75))
                Spacer(minLength: 0)
                V7Barcode().frame(width: 92, height: 20).opacity(0.8)
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 21)
        .frame(width: 380, alignment: .leading)
        .background {
            V7TornPaper(bite: 5)
                .fill(V7Tokens.Ground.paper)
                .v7Grain(0.35)
        }
        .rotationEffect(.degrees(angle))
        .shadow(color: .black.opacity(0.30), radius: 14, y: 14)
    }

    /// The tear-off rule. A dashed line drawn directly — stroking a 1pt-high
    /// rectangle insets it out of existence.
    private var perforation: some View {
        GeometryReader { geometry in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0.75))
                path.addLine(to: CGPoint(x: geometry.size.width, y: 0.75))
            }
            .stroke(
                V7Tokens.Text.onCard.opacity(0.28),
                style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
            )
        }
        .frame(height: 1.5)
    }
}

/// Decorative barcode on the slip. Fixed bars, not random — a receipt's
/// barcode is a printed thing, not noise.
struct V7Barcode: View {
    private static let thin: [CGFloat] = [3, 9, 13, 22, 31, 36, 48, 57, 66, 74, 83, 92, 101, 110]
    private static let thick: [CGFloat] = [6, 17, 27, 42, 53, 62, 70, 88, 97, 106]

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 116
            Canvas { context, size in
                var path = Path()
                for x in Self.thin {
                    path.move(to: CGPoint(x: x * scale, y: 0))
                    path.addLine(to: CGPoint(x: x * scale, y: size.height))
                }
                context.stroke(path, with: .color(V7Tokens.Text.onCard), lineWidth: 1.4)

                var heavy = Path()
                for x in Self.thick {
                    heavy.move(to: CGPoint(x: x * scale, y: 0))
                    heavy.addLine(to: CGPoint(x: x * scale, y: size.height))
                }
                context.stroke(heavy, with: .color(V7Tokens.Text.onCard), lineWidth: 3)
            }
        }
        .accessibilityHidden(true)
    }
}
