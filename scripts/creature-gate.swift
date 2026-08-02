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

/// Measured foreground green of the opened panel. Not in Core — Core only owns
/// the surfaces it must assert against.
let panelGround = CreatureColor(red: 0xb4, green: 0xde, blue: 0x6f)

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
    let reach = h * 0.34
    let lift = CGFloat(form.armLift)
    for side in [-1.0, 1.0] as [CGFloat] {
        let x0 = rect.midX + side * w * 0.44
        let x1 = x0 + side * reach * 0.42 * (1.0 - lift * 0.55)
        // armLift 0 hangs, 1 is fully overhead. Because y grows upward, lift has
        // to *add* to y — writing it the other way draws `holding` with its arms
        // pointing at the floor.
        let y1 = shoulderY + reach * lift - reach * 0.3 * (1 - lift)
        let arm = CGMutablePath()
        arm.move(to: CGPoint(x: x0, y: shoulderY))
        arm.addLine(to: CGPoint(x: x1, y: y1))
        let stroked = arm.copy(
            strokingWithWidth: max(1.0, w * 0.17),
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

        // 3. Panel optical size on the panel green.
        for pose in CreaturePose.allCases {
            let image = render(
                size: panelLane,
                ground: panelGround,
                body: CreaturePalette.color(for: panelSpecies),
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
        // palette is built for. Printed because the panel PNGs cannot be read
        // honestly without it.
        print("")
        print("Same colours against the panel ground \(hex(panelGround)) (informational)")
        for species in CreatureSpecies.allCases {
            let ratio = CreatureColor.contrastRatio(CreaturePalette.color(for: species), panelGround)
            print(pad(species.rawValue, 12) + String(format: "%.2f:1", ratio))
        }
    }

    static func reportGeometry() {
        // Arms are the only channel carrying pose at pill size, so measure
        // whether they actually leave the body instead of eyeballing it.
        let frame = CGRect(origin: .zero, size: pillLane)
        print("")
        print("Arm break beyond the body outline, 28 x 32 pt lane (reference seed)")
        print(pad("pose", 10) + pad("armLift", 10) + pad("sideways", 14)
            + pad("above", 14) + "clipped by lane")

        for pose in CreaturePose.allCases {
            let form = CreatureForm.make(seed: referenceSeed, pose: pose)
            let bodyBox = creaturePath(form: form, in: frame, includeArms: false).boundingBoxOfPath
            let fullBox = creaturePath(form: form, in: frame).boundingBoxOfPath
            let sideways = max(fullBox.maxX - bodyBox.maxX, bodyBox.minX - fullBox.minX)
            let above = fullBox.maxY - bodyBox.maxY
            let clipped = laneOverflow(fullBox, in: frame)
            print(
                pad(pose.rawValue, 10)
                    + pad(String(format: "%.2f", form.armLift), 10)
                    + pad(String(format: "%+.2f pt", sideways), 14)
                    + pad(String(format: "%+.2f pt", above), 14)
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
    }
}
