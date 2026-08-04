// Renders `CompanionRig` to PNG so a human can look at it.
//
// The whole reason round 1 shipped an unsound design is that nothing rendered
// it until a person opened the app. This is that loop, made cheap: it links the
// real `CompanionRig` out of Core — not a copy — so what is judged here is what
// ships.
//
//   zsh scripts/companion-rig-preview.sh [output-directory]

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Palette

struct Skin {
    let name: String
    let surface: (Double, Double, Double)
    let body: (Double, Double, Double)
    let light: (Double, Double, Double)
    let feature: (Double, Double, Double)
}

/// The panel's own surface, and a character sitting on it. `light` is the belly
/// and muzzle; `feature` is the eyes and nose.
func hex(_ v: Int) -> (Double, Double, Double) {
    (Double((v >> 16) & 0xff) / 255, Double((v >> 8) & 0xff) / 255, Double(v & 0xff) / 255)
}

/// Every value measured in `docs/STYLE-SPEC.md` §3. Tier A is the painted surface:
/// dark line on a light wash, which is the inversion the pill cannot use and the
/// panel must.
let skins = [
    Skin(
        name: "tierA",
        surface: hex(0xb4de6f),        // foreground wash
        body: hex(0x766656),           // Claude, panel ladder — 3.58:1 on the wash
        light: hex(0xc4ae8e),          // wood light
        feature: hex(0x211e12)         // line work, 10.82:1 here
    ),
    Skin(
        name: "tierB",
        surface: hex(0x0d0d0f),        // the pill
        body: hex(0xf8d7b7),           // Claude, pill ladder — 14.23:1
        light: hex(0xfdeee0),
        feature: hex(0x211e12)
    ),
]

func color(_ c: (Double, Double, Double), _ alpha: Double = 1) -> CGColor {
    CGColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: alpha)
}

/// Pull a colour toward the surface it is sitting on. This is the whole of
/// "blend in with the background": a cut-out PNG arrives at full saturation and
/// always reads as pasted on, and a vector body can simply be mixed.
func grounded(_ c: (Double, Double, Double), into s: (Double, Double, Double), _ k: Double) -> (Double, Double, Double) {
    (c.0 + (s.0 - c.0) * k, c.1 + (s.1 - c.1) * k, c.2 + (s.2 - c.2) * k)
}

// MARK: - Render

func render(
    _ params: CompanionRigParameters,
    skin: Skin,
    size: CGSize,
    scale: CGFloat
) -> CGImage {
    let pixel = CGSize(width: size.width * scale, height: size.height * scale)
    guard let ctx = CGContext(
        data: nil,
        width: Int(pixel.width),
        height: Int(pixel.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("CGContext allocation failed") }

    ctx.setFillColor(color(skin.surface))
    ctx.fill(CGRect(origin: .zero, size: pixel))
    ctx.scaleBy(x: scale, y: scale)

    let inset = CGRect(origin: .zero, size: size).insetBy(
        dx: size.width * 0.04,
        dy: size.height * 0.02
    )

    let body = grounded(skin.body, into: skin.surface, 0.10)
    let limbTone = grounded(skin.body, into: skin.surface, 0.26)
    let light = grounded(skin.light, into: skin.surface, 0.08)
    // §4: interior line only on the pill; the painted ground may outline freely.
    let outlines = skin.name == "tierA"

    var index = 0
    for layer in CompanionRig.layers(params, in: inset) {
        ctx.addPath(layer.path)
        switch layer.role {
        case .shadow:
            // A real contact shadow: darker than the surface, soft, and sitting
            // *under* the character rather than behind it.
            ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.42))
            ctx.setShadow(offset: .zero, blur: size.height * 0.05)
        case .behind:
            ctx.setFillColor(color(limbTone))
            ctx.setShadow(offset: .zero, blur: 0)
        case .limb:
            ctx.setFillColor(color(limbTone))
            ctx.setShadow(offset: .zero, blur: 0)
        case .body:
            ctx.setFillColor(color(body))
            ctx.setShadow(offset: .zero, blur: 0)
        case .light:
            ctx.setFillColor(color(light))
            ctx.setShadow(offset: .zero, blur: 0)
        case .feature:
            ctx.setFillColor(color(skin.feature))
            ctx.setShadow(offset: .zero, blur: 0)
        case .lid:
            ctx.setFillColor(color(body))
            ctx.setShadow(offset: .zero, blur: 0)
        }
        ctx.fillPath()

        if outlines, layer.role != .shadow {
            ctx.setStrokeColor(color(skin.feature))
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            var wobble = SplitMix64(state: UInt64(bitPattern: Int64(index &* 2_654_435_761)))
            for pass in 0..<3 {
                let jx = (Double(wobble.next() % 1000) / 1000 - 0.5) * size.width * 0.007
                let jy = (Double(wobble.next() % 1000) / 1000 - 0.5) * size.width * 0.007
                let w = size.width * (0.0125 + Double(wobble.next() % 1000) / 1000 * 0.006)
                ctx.saveGState()
                ctx.translateBy(x: jx, y: jy)
                ctx.setLineWidth(w)
                ctx.setAlpha(pass == 0 ? 1.0 : 0.5)
                ctx.addPath(layer.path)
                ctx.strokePath()
                ctx.restoreGState()
            }
            ctx.setAlpha(1)
        }
        index += 1
    }
    ctx.setShadow(offset: .zero, blur: 0)

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { fatalError("cannot create PNG destination at \(url.path)") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("PNG write failed") }
}

/// A contact sheet, so the poses are judged against each other rather than one
/// at a time — which is how round 1 shipped four poses that were three.
func sheet(_ images: [CGImage], columns: Int, cell: CGSize, scale: CGFloat, surface: (Double, Double, Double)) -> CGImage {
    let rows = Int(ceil(Double(images.count) / Double(columns)))
    let gap: CGFloat = 8 * scale
    let w = CGFloat(columns) * cell.width * scale + CGFloat(columns + 1) * gap
    let h = CGFloat(rows) * cell.height * scale + CGFloat(rows + 1) * gap

    guard let ctx = CGContext(
        data: nil, width: Int(w), height: Int(h),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("CGContext allocation failed") }

    ctx.setFillColor(CGColor(srgbRed: surface.0 * 0.6, green: surface.1 * 0.6, blue: surface.2 * 0.6, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

    for (i, image) in images.enumerated() {
        let col = i % columns
        let row = i / columns
        let x = gap + CGFloat(col) * (cell.width * scale + gap)
        let y = h - gap - CGFloat(row + 1) * cell.height * scale - CGFloat(row) * gap
        ctx.draw(image, in: CGRect(x: x, y: y, width: cell.width * scale, height: cell.height * scale))
    }
    return ctx.makeImage()!
}

// MARK: - Main

@main
struct CompanionRigPreview {
    static func main() throws {
        let out = URL(fileURLWithPath: CommandLine.arguments.count > 1
            ? CommandLine.arguments[1]
            : NSTemporaryDirectory() + "companion-rig")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        /// The two sizes that matter: the pill lane and a destination-surface render.
        let sizes: [(String, CGSize, CGFloat)] = [
            ("pill", CGSize(width: 28, height: 32), 12),
            ("large", CGSize(width: 120, height: 132), 4),
        ]

        /// Named attitudes, so the sheet can be read.
        let poses: [(String, CompanionRigParameters)] = [
            ("idle-out", CompanionRigParameters(breath: 0, earPerk: 0.55)),
            ("idle-in", CompanionRigParameters(breath: 1, earPerk: 0.6)),
            ("blink", CompanionRigParameters(breath: 0.5, blink: 1, earPerk: 0.5)),
            ("sway-left", CompanionRigParameters(breath: 0.4, sway: -1, earPerk: 0.5, tailSwish: -1)),
            ("sway-right", CompanionRigParameters(breath: 0.4, sway: 1, earPerk: 0.5, tailSwish: 1)),
            ("waiting-ONE-out", CompanionRigParameters(breath: 0.6, armLiftLeading: 1, headTilt: 0.3, earPerk: 1)),
            ("holding-BOTH-out", CompanionRigParameters(breath: 0.6, armLiftLeading: 1, armLiftTrailing: 1, earPerk: 0.8)),
            ("curious", CompanionRigParameters(breath: 0.5, headTurn: 0.8, headTilt: 0.7, earPerk: 1)),
            ("look-away", CompanionRigParameters(breath: 0.5, headTurn: -0.9, earPerk: 0.35)),
            ("resting", CompanionRigParameters(breath: 0.3, blink: 0.35, earPerk: 0.2, settle: 0.5)),
            ("asleep", CompanionRigParameters(breath: 0.2, blink: 1, earPerk: 0, settle: 1, tailSwish: 0.4)),
            ("asleep-in", CompanionRigParameters(breath: 1, blink: 1, earPerk: 0, settle: 1, tailSwish: 0.5)),
        ]

        var written = 0
        for skin in skins {
            for (label, size, scale) in sizes {
                var frames: [CGImage] = []
                for (name, params) in poses {
                    let image = render(params, skin: skin, size: size, scale: scale)
                    frames.append(image)
                    writePNG(image, to: out.appendingPathComponent("\(skin.name)-\(label)-\(name).png"))
                    written += 1
                }
                let contact = sheet(frames, columns: 4, cell: size, scale: scale, surface: skin.surface)
                writePNG(contact, to: out.appendingPathComponent("SHEET-\(skin.name)-\(label).png"))
                written += 1
            }
        }

        print("\(written) PNGs written to \(out.path)")
    }
}
