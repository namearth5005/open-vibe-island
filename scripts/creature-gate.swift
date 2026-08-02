// Phase 0 creature legibility gate — offscreen render harness.
//
// Draws the real `CreatureForm` silhouettes to PNG at the true measured
// right-slot lane (28 x 32 pt) composited on the real pill fill, so a human can
// judge legibility before any art is commissioned. This is the same approach
// that produced `shard-final.png` and `geode-shapes.png` for the geode gate.
//
// Nothing downstream of the gate ships until the PNGs are approved. See
// `docs/superpowers/specs/2026-08-01-island-reward-mechanics-design.md`,
// "Phase 0 — kill gate".
//
// Outputs, into argv[1]:
//   pill-<species>-<pose>.png  every species x pose, true pill size, on the pill
//   grey-<species>.png         every species, colour removed (luminance ladder)
//   panel-<pose>.png           four poses at panel optical size, on the panel green
//   roll-NN.png                20 procedural individuals, seeds 0...19
//   worst-<pose>.png           the worst roll in the three states that must separate
//
// Run via `scripts/creature-gate.sh <outdir>`.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Constants

/// Supersampling factor. Geometry is laid out in *points* and the context is
/// scaled, so each PNG is a magnification of the true shape rather than a shape
/// authored at 4x resolution.
let renderScale: CGFloat = 4

/// The measured creature budget: 44pt right-slot reserve minus 16pt padding,
/// against the 32pt closed pill on a built-in display.
let pillLane = CGSize(width: 28, height: 32)

/// Panel optical size. The spec authors pill and panel creatures separately;
/// this is the 64px-tall panel slot.
let panelLane = CGSize(width: 56, height: 64)

/// One seed shared by every species render, so the value ladder is the only
/// variable between them. Placeholder geometry varies per session seed, not per
/// species, so giving each species its own seed would fake a silhouette
/// difference the model does not actually produce.
let referenceSeed = ShardSeed.value(for: "creature-gate")

/// Panel renders use the brightest species: the panel test is pose separation,
/// and this is the body most likely to wash out on a light ground.
let panelSpecies = CreatureSpecies.claude

/// Rolls use the *darkest* species. Condition 6 is judged on the worst roll, so
/// the procedural sheet is drawn at the bottom of the luminance ladder.
let rollSpecies = CreatureSpecies.openCode

let rollCount = 20

// MARK: - Colour

func cgColor(_ c: CreatureColor) -> CGColor {
    CGColor(
        red: CGFloat(c.red) / 255.0,
        green: CGFloat(c.green) / 255.0,
        blue: CGFloat(c.blue) / 255.0,
        alpha: 1
    )
}

/// Colour removed: collapse to relative luminance, then encode that back
/// through the sRGB transfer function. This is the grey a species *actually*
/// becomes, which is what the luminance ladder has to survive.
func greyscale(_ c: CreatureColor) -> CreatureColor {
    let linear = c.relativeLuminance
    let encoded = linear <= 0.0031308
        ? 12.92 * linear
        : 1.055 * pow(linear, 1.0 / 2.4) - 0.055
    let value = UInt8(max(0, min(255, (encoded * 255).rounded())))
    return CreatureColor(red: value, green: value, blue: value)
}

func hex(_ c: CreatureColor) -> String {
    String(format: "#%02x%02x%02x", c.red, c.green, c.blue)
}

// MARK: - Geometry

/// Builds the creature silhouette for `form` inside `rect`, in points.
///
/// Placeholder geometry: a rounded capsule body plus two stroked arms. There is
/// no interior line work — `CreaturePalette.lineWork` sits at 1.16:1 against the
/// pill, so anything drawn with it there is invisible and would only flatter the
/// render. The gate judges silhouette alone, which is what the pill actually has.
func creaturePath(form: CreatureForm, in rect: CGRect, includeArms: Bool = true) -> CGPath {
    let path = CGMutablePath()
    let w = rect.width * CGFloat(form.bodyWidth)
    let h = rect.height * CGFloat(form.bodyHeight)
    let body = CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)

    let transform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
        .rotated(by: CGFloat(form.tilt))
        .translatedBy(x: -rect.midX, y: -rect.midY)

    path.addRoundedRect(in: body, cornerWidth: w * 0.42, cornerHeight: h * 0.34, transform: transform)
    guard includeArms else { return path }

    // `shoulder` is a fraction of body height measured from the top; CoreGraphics
    // y grows upward, so this counts down from the body's top edge.
    let shoulderY = body.minY + body.height * CGFloat(1.0 - form.shoulder)
    let stroke = max(1.0, w * 0.17)
    let halfStroke = stroke / 2

    // A raised arm travels *outward*, not upward. The lane leaves 4.5-6.7pt at
    // the sides and at most 4.2pt above the body — and that headroom is the
    // physical top edge of the display, where nothing can be drawn at all. The
    // first version of this harness shrank the silhouette as lift rose, which
    // is backwards: the pose that should shout ended up narrowest.
    //
    // Round caps extend half a stroke past the tip, so the limits are inset by
    // that much and a fully raised arm lands exactly on the lane edge.
    let outX = rect.width / 2 - halfStroke
    let outY = min(body.maxY + h * 0.06, rect.maxY - halfStroke)

    for (side, lift) in [(CGFloat(-1), CGFloat(form.armLiftTrailing)),
                         (CGFloat(1), CGFloat(form.armLiftLeading))] {
        let x0 = rect.midX + side * w * 0.44
        // Hanging: tucked along the flank, just proud of the body edge.
        let hangX = x0 + side * w * 0.10
        let hangY = shoulderY - h * 0.22
        let x1 = hangX + (rect.midX + side * outX - hangX) * lift
        let y1 = hangY + (outY - hangY) * lift

        let arm = CGMutablePath()
        arm.move(to: CGPoint(x: x0, y: shoulderY))
        arm.addLine(to: CGPoint(x: x1, y: y1))
        let stroked = arm.copy(
            strokingWithWidth: stroke,
            lineCap: .round, lineJoin: .round, miterLimit: 4
        )
        path.addPath(stroked, transform: transform)
    }
    return path
}

// MARK: - Raster

func render(size: CGSize, ground: CreatureColor, body: CreatureColor, form: CreatureForm) -> CGImage {
    let pixelWidth = Int((size.width * renderScale).rounded())
    let pixelHeight = Int((size.height * renderScale).rounded())
    guard let ctx = CGContext(
        data: nil,
        width: pixelWidth,
        height: pixelHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("CGContext allocation failed") }

    ctx.setFillColor(cgColor(ground))
    ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(pixelWidth), height: CGFloat(pixelHeight)))

    // Everything past this point is in points, at true lane size.
    ctx.scaleBy(x: renderScale, y: renderScale)
    ctx.setFillColor(cgColor(body))
    ctx.addPath(creaturePath(form: form, in: CGRect(origin: .zero, size: size)))
    ctx.fillPath()

    guard let image = ctx.makeImage() else { fatalError("makeImage failed") }
    return image
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { fatalError("cannot create PNG destination at \(url.path)") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("PNG write failed: \(url.path)") }
}

// MARK: - Measurement

/// The seed whose `waiting` silhouette is the least lopsided.
///
/// Condition 1 is judged on the worst roll, and asymmetry is what carries
/// `waiting`, so this is the roll the gate is actually decided on. A wide body
/// leaves the least room to put an arm into, so the worst case lives at the top
/// of the width range rather than in the middle of it.
func worstWaitingRollSeed(in frame: CGRect, count: Int) -> UInt64 {
    var worst = CGFloat.greatestFiniteMagnitude
    var seed: UInt64 = 0
    for candidate in 0..<count {
        let form = CreatureForm.make(seed: UInt64(candidate), pose: .waiting)
        let body = creaturePath(form: form, in: frame, includeArms: false).boundingBoxOfPath
        let full = creaturePath(form: form, in: frame).boundingBoxOfPath
        let asymmetry = abs((full.maxX - body.maxX) - (body.minX - full.minX))
        if asymmetry < worst { worst = asymmetry; seed = UInt64(candidate) }
    }
    return seed
}

/// How far the silhouette pokes outside the lane it has to live in.
func laneOverflow(_ box: CGRect, in frame: CGRect) -> CGFloat {
    max(
        max(frame.minX - box.minX, box.maxX - frame.maxX),
        max(frame.minY - box.minY, box.maxY - frame.maxY)
    )
}

func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
}

// MARK: - Entry point

@main
enum CreatureGate {
    static func main() throws {
        guard CommandLine.arguments.count > 1 else {
            FileHandle.standardError.write(Data("usage: creature-gate <output-directory>\n".utf8))
            exit(2)
        }
        let out = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let written = renderSheets(into: out)
        reportContrast()
        reportGeometry()
        print("")
        print("\(written) PNGs written to \(out.path)")
    }

    // MARK: Sheets

    static func renderSheets(into out: URL) -> Int {
        var written = 0
        func write(_ image: CGImage, _ name: String) {
            writePNG(image, to: out.appendingPathComponent(name))
            written += 1
        }

        // 1. Every species x pose at true pill size on the real pill fill.
        for species in CreatureSpecies.allCases {
            for pose in CreaturePose.allCases {
                let image = render(
                    size: pillLane,
                    ground: CreaturePalette.pillFill,
                    body: CreaturePalette.color(for: species),
                    form: CreatureForm.make(seed: referenceSeed, pose: pose)
                )
                write(image, "pill-\(species.rawValue)-\(pose.rawValue).png")
            }
        }

        // 2. Colour removed. Ground and body both collapse to their luminance
        //    greys, so this is a genuine desaturation of the pill rather than a
        //    grey creature floating on a still-coloured background.
        for species in CreatureSpecies.allCases {
            let image = render(
                size: pillLane,
                ground: greyscale(CreaturePalette.pillFill),
                body: greyscale(CreaturePalette.color(for: species)),
                form: CreatureForm.make(seed: referenceSeed, pose: .working)
            )
            write(image, "grey-\(species.rawValue).png")
        }

        // 3. Panel optical size on the panel green, in panel values. The pill
        //    values are not reused here — on this ground they measure 1.08:1 to
        //    2.27:1 and simply are not there.
        for pose in CreaturePose.allCases {
            let image = render(
                size: panelLane,
                ground: CreaturePalette.panelGround,
                body: CreaturePalette.panelColor(for: panelSpecies),
                form: CreatureForm.make(seed: referenceSeed, pose: pose)
            )
            write(image, "panel-\(pose.rawValue).png")
        }

        // 4. Procedural individuals, seeds 0...19, at true pill size.
        for seed in 0..<rollCount {
            let image = render(
                size: pillLane,
                ground: CreaturePalette.pillFill,
                body: CreaturePalette.color(for: rollSpecies),
                form: CreatureForm.make(seed: UInt64(seed), pose: .working)
            )
            write(image, String(format: "roll-%02d.png", seed))
        }

        // 5. The worst roll in the three states that must separate. Condition 1
        //    is judged here, not on the reference body, so the gate renders it
        //    rather than leaving a reviewer to hunt for it.
        let worstSeed = worstWaitingRollSeed(in: CGRect(origin: .zero, size: pillLane), count: rollCount)
        for pose in CreaturePose.allCases where pose.demandsPillLegibility {
            let image = render(
                size: pillLane,
                ground: CreaturePalette.pillFill,
                body: CreaturePalette.color(for: rollSpecies),
                form: CreatureForm.make(seed: worstSeed, pose: pose)
            )
            write(image, "worst-\(pose.rawValue).png")
        }

        return written
    }

    // MARK: Numbers

    static func reportContrast() {
        print("Creature legibility gate")
        print("")
        print("Contrast against the pill fill \(hex(CreaturePalette.pillFill)) (CreaturePalette.pillFill)")
        print(pad("species", 12) + pad("colour", 10) + pad("luminance", 12) + "contrast")

        var worst = Double.greatestFiniteMagnitude
        for species in CreatureSpecies.allCases {
            let colour = CreaturePalette.color(for: species)
            let ratio = CreatureColor.contrastRatio(colour, CreaturePalette.pillFill)
            worst = min(worst, ratio)
            print(
                pad(species.rawValue, 12)
                    + pad(hex(colour), 10)
                    + pad(String(format: "%.1f%%", colour.relativeLuminance * 100), 12)
                    + String(format: "%.2f:1", ratio)
            )
        }
        print(String(format: "worst %.2f:1 — gate needs >= 3.00:1 — %@",
                     worst, worst >= 3.0 ? "PASS" : "FAIL"))

        // The panel ground inverts the figure/ground relationship the pill
        // palette is built for, so the panel has its own values. Both columns
        // are printed because the second only makes sense next to the first.
        let ground = CreaturePalette.panelGround
        print("")
        print("Panel ground \(hex(ground)) — pill values cannot be reused here")
        print(pad("species", 12) + pad("pill value", 20) + pad("panel value", 20) + "verdict")
        var worstPanel = Double.greatestFiniteMagnitude
        for species in CreatureSpecies.allCases {
            let reused = CreatureColor.contrastRatio(CreaturePalette.color(for: species), ground)
            let panel = CreaturePalette.panelColor(for: species)
            let ratio = CreatureColor.contrastRatio(panel, ground)
            worstPanel = min(worstPanel, ratio)
            print(
                pad(species.rawValue, 12)
                    + pad(String(format: "%@ %.2f:1", hex(CreaturePalette.color(for: species)), reused), 20)
                    + pad(String(format: "%@ %.2f:1", hex(panel), ratio), 20)
                    + (reused >= 3.0 ? "was already fine" : "was invisible")
            )
        }
        print(String(format: "worst %.2f:1 — needs >= 3.00:1 — %@",
                     worstPanel, worstPanel >= 3.0 ? "PASS" : "FAIL"))
    }

    static func reportGeometry() {
        // Arms are the only channel carrying pose at pill size, so measure
        // whether they actually leave the body instead of eyeballing it.
        let frame = CGRect(origin: .zero, size: pillLane)
        print("")
        print("Arm break beyond the body outline, 28 x 32 pt lane (reference seed)")
        print(pad("pose", 10) + pad("arms", 12) + pad("widest side", 14)
            + pad("narrow side", 14) + pad("above", 12) + "clipped by lane")

        for pose in CreaturePose.allCases {
            let form = CreatureForm.make(seed: referenceSeed, pose: pose)
            let bodyBox = creaturePath(form: form, in: frame, includeArms: false).boundingBoxOfPath
            let fullBox = creaturePath(form: form, in: frame).boundingBoxOfPath
            // Reported per side, because asymmetry is now the pose signal: a
            // single averaged figure would hide the very thing that separates
            // `waiting` from `holding`.
            let leadOut = fullBox.maxX - bodyBox.maxX
            let trailOut = bodyBox.minX - fullBox.minX
            let above = fullBox.maxY - bodyBox.maxY
            let clipped = laneOverflow(fullBox, in: frame)
            print(
                pad(pose.rawValue, 10)
                    + pad(String(format: "%.1f/%.1f", form.armLiftLeading, form.armLiftTrailing), 12)
                    + pad(String(format: "%+.2f pt", max(leadOut, trailOut)), 14)
                    + pad(String(format: "%+.2f pt", min(leadOut, trailOut)), 14)
                    + pad(String(format: "%+.2f pt", above), 12)
                    + (clipped > 0.01 ? String(format: "%.2f pt", clipped) : "—")
            )
        }

        var worst: CGFloat = 0
        var label = ""
        for seed in 0..<rollCount {
            for pose in CreaturePose.allCases {
                let form = CreatureForm.make(seed: UInt64(seed), pose: pose)
                let clip = laneOverflow(
                    creaturePath(form: form, in: frame).boundingBoxOfPath, in: frame
                )
                if clip > worst {
                    worst = clip
                    label = "seed \(seed) / \(pose.rawValue)"
                }
            }
        }
        print(worst > 0.01
            ? String(format: "worst lane overflow across %d seeds x 4 poses: %.2f pt (%@)",
                     rollCount, worst, label)
            : "no roll overflows the lane")

        // Condition 1 is judged on the worst roll, so the separations that carry
        // it are measured across every seed rather than on the reference body.
        // A wide body has the least room to put an arm into, so the worst case
        // here is the widest roll, not the average one.
        var worstAsymmetry = CGFloat.greatestFiniteMagnitude
        var asymmetrySeed = 0
        var worstHoldingBreak = CGFloat.greatestFiniteMagnitude
        var holdingSeed = 0
        for seed in 0..<rollCount {
            let waiting = CreatureForm.make(seed: UInt64(seed), pose: .waiting)
            let wBody = creaturePath(form: waiting, in: frame, includeArms: false).boundingBoxOfPath
            let wFull = creaturePath(form: waiting, in: frame).boundingBoxOfPath
            // How lopsided `waiting` is — the cue that separates it from both
            // neighbours. Zero would mean it had gone symmetric.
            let asymmetry = abs((wFull.maxX - wBody.maxX) - (wBody.minX - wFull.minX))
            if asymmetry < worstAsymmetry { worstAsymmetry = asymmetry; asymmetrySeed = seed }

            let holding = CreatureForm.make(seed: UInt64(seed), pose: .holding)
            let hBody = creaturePath(form: holding, in: frame, includeArms: false).boundingBoxOfPath
            let hFull = creaturePath(form: holding, in: frame).boundingBoxOfPath
            let quietSide = min(hFull.maxX - hBody.maxX, hBody.minX - hFull.minX)
            if quietSide < worstHoldingBreak { worstHoldingBreak = quietSide; holdingSeed = seed }
        }
        print(String(format: "worst roll — waiting asymmetry %.2f pt (seed %d), holding weaker arm %.2f pt (seed %d)",
                     worstAsymmetry, asymmetrySeed, worstHoldingBreak, holdingSeed))
    }
}
