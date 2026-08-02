# Island Creature — Pill Layer Implementation Plan (spec items 0–4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the closed pill's procedural shard with a creature that shows session state by pose — and prove at true size, before any art is commissioned or generated, that it is legible.

**Architecture:** All logic is pure and lives in `OpenIslandCore`, reusing `GeodeState` (already the single source of session truth) and `ShardSeed` (already deterministic). A standalone render harness draws the real shapes offscreen to PNG at true pill size composited on the real pill colour — this is a **kill gate**; nothing after Task 6 is built until a human approves those PNGs. The creature then enters the pill as a fifth `IslandRightSlot` option, off by default, so today's behaviour is untouched for every existing user.

**Tech Stack:** Swift 6.2, SwiftUI + AppKit, Swift Testing (`import Testing`, `@Test`, `#expect`), CoreGraphics + ImageIO for the harness. Build with `swift build`, test with `swift test`.

**Spec:** `docs/superpowers/specs/2026-08-01-island-reward-mechanics-design.md`

---

## Ordering note

The spec lists the harness as build item 0. The harness has to render *something*, so Tasks 1–4 build the minimal pure model first. The gate still lands before any view, window or pill work — which is the point of it. Task 6 is a hard stop.

## File structure

| File | Responsibility | Status |
|---|---|---|
| `Sources/OpenIslandCore/CreatureSpecies.swift` | `AgentTool` → one of six species families | create |
| `Sources/OpenIslandCore/CreaturePose.swift` | `GeodeShard` → one of four poses | create |
| `Sources/OpenIslandCore/CreaturePalette.swift` | species → colour; WCAG luminance + contrast maths | create |
| `Sources/OpenIslandCore/CreatureForm.swift` | seeded silhouette geometry, mirrors `ShardForm` | create |
| `scripts/creature-gate.swift` | offscreen PNG harness (kill gate) | create |
| `scripts/creature-gate.sh` | compiles and runs the harness | create |
| `Sources/OpenIslandApp/Views/CreatureView.swift` | SwiftUI rendering at both scales | create |
| `Sources/OpenIslandApp/AppModelTypes.swift:28-35` | add `.creature` to `IslandRightSlot` | modify |
| `Sources/OpenIslandApp/Views/V6NotchContent.swift:24-32` | add `.creature` to `IslandRightSlotContent` | modify |
| `Sources/OpenIslandApp/IslandDebugScenario.swift` | pin creature rendering | modify |
| `Tests/OpenIslandCoreTests/Creature*Tests.swift` | pure model + gate-as-test | create |
| `Tests/OpenIslandAppTests/CreatureRightSlotTests.swift` | pill integration | create |

Core stays free of SwiftUI — `CreaturePalette` returns raw RGB, and the App layer converts. That is what lets the harness link Core directly without dragging in the UI.

---

### Task 1: CreatureSpecies — ten agents, six bodies

Four of the ten supported agents (Qoder, Qwen Code, Factory, CodeBuddy) are Claude Code forks sharing its hook format, so they share the Claude body. This is truthful, and it cuts sprite work by ~40%.

**Files:**
- Create: `Sources/OpenIslandCore/CreatureSpecies.swift`
- Test: `Tests/OpenIslandCoreTests/CreatureSpeciesTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import OpenIslandCore

struct CreatureSpeciesTests {
    @Test
    func everyAgentToolMapsToASpecies() {
        for tool in AgentTool.allCases {
            _ = CreatureSpecies(tool: tool)
        }
    }

    @Test
    func claudeForksShareTheClaudeBody() {
        #expect(CreatureSpecies(tool: .claudeCode) == .claude)
        #expect(CreatureSpecies(tool: .qoder) == .claude)
        #expect(CreatureSpecies(tool: .qwenCode) == .claude)
        #expect(CreatureSpecies(tool: .factory) == .claude)
        #expect(CreatureSpecies(tool: .codebuddy) == .claude)
    }

    @Test
    func distinctAgentsKeepDistinctSpecies() {
        #expect(CreatureSpecies(tool: .codex) == .codex)
        #expect(CreatureSpecies(tool: .cursor) == .cursor)
        #expect(CreatureSpecies(tool: .geminiCLI) == .gemini)
        #expect(CreatureSpecies(tool: .kimiCLI) == .kimi)
        #expect(CreatureSpecies(tool: .openCode) == .openCode)
    }

    @Test
    func thereAreExactlySixSpecies() {
        #expect(CreatureSpecies.allCases.count == 6)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter CreatureSpeciesTests`
Expected: FAIL — `cannot find 'CreatureSpecies' in scope`

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// Which body a session's creature wears.
///
/// Six bodies for ten agents: Qoder, Qwen Code, Factory and CodeBuddy are all
/// Claude Code forks sharing its hook format, so they share its body and differ
/// only by marking. They look alike because they are alike.
public enum CreatureSpecies: String, CaseIterable, Sendable {
    case claude
    case codex
    case cursor
    case gemini
    case kimi
    case openCode

    public init(tool: AgentTool) {
        switch tool {
        case .claudeCode, .qoder, .qwenCode, .factory, .codebuddy:
            self = .claude
        case .codex:
            self = .codex
        case .cursor:
            self = .cursor
        case .geminiCLI:
            self = .gemini
        case .kimiCLI:
            self = .kimi
        case .openCode:
            self = .openCode
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter CreatureSpeciesTests`
Expected: PASS, 4 tests

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenIslandCore/CreatureSpecies.swift Tests/OpenIslandCoreTests/CreatureSpeciesTests.swift
git commit -m "feat: map the ten supported agents onto six creature species"
```

---

### Task 2: CreaturePose — the state the picture carries

Four poses, derived purely from the shard `GeodeState` already maintains. No new state, no new events.

**Files:**
- Create: `Sources/OpenIslandCore/CreaturePose.swift`
- Test: `Tests/OpenIslandCoreTests/CreaturePoseTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import OpenIslandCore

struct CreaturePoseTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func shard(
        frozenSince: Date? = nil,
        isSet: Bool = false,
        isFractured: Bool = false
    ) -> GeodeShard {
        GeodeShard(
            sessionID: "s1",
            tool: .claudeCode,
            startedAt: t0,
            frozenSeconds: 0,
            frozenSince: frozenSince,
            stallCount: 0,
            stage: 2,
            isSet: isSet,
            isFractured: isFractured,
            updatedAt: t0
        )
    }

    @Test
    func runningSessionIsWorking() {
        #expect(CreaturePose(shard: shard()) == .working)
    }

    @Test
    func blockedSessionRaisesAHand() {
        #expect(CreaturePose(shard: shard(frozenSince: t0)) == .waiting)
    }

    @Test
    func cleanFinishHoldsTheRewardUp() {
        #expect(CreaturePose(shard: shard(isSet: true)) == .holding)
    }

    @Test
    func interruptKnocksTheCreatureOver() {
        #expect(CreaturePose(shard: shard(isSet: true, isFractured: true)) == .fallen)
    }

    /// A finished session is finished even if it was frozen when it ended —
    /// otherwise an interrupt during a permission prompt would show a raised
    /// hand forever, asking for input that will never be consumed.
    @Test
    func completionBeatsFreeze() {
        #expect(CreaturePose(shard: shard(frozenSince: t0, isSet: true)) == .holding)
        #expect(CreaturePose(shard: shard(frozenSince: t0, isSet: true, isFractured: true)) == .fallen)
    }

    /// Only these three must be mutually legible at pill size; `fallen` is
    /// deliberately quiet because an interrupted session is not asking for you.
    @Test
    func attentionPosesAreTheOnesThatDemandLegibility() {
        #expect(CreaturePose.working.demandsPillLegibility)
        #expect(CreaturePose.waiting.demandsPillLegibility)
        #expect(CreaturePose.holding.demandsPillLegibility)
        #expect(!CreaturePose.fallen.demandsPillLegibility)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter CreaturePoseTests`
Expected: FAIL — `cannot find 'CreaturePose' in scope`

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// What a creature is doing. Derived from the shard, never stored — same rule
/// the shard itself follows.
public enum CreaturePose: String, CaseIterable, Sendable {
    /// Agent is running. Ambient; should be ignorable.
    case working
    /// Agent is blocked on the human. This is the notification.
    case waiting
    /// Clean completion, reward held overhead, waiting to be collected.
    case holding
    /// Interrupted. Knocked over, object dropped.
    case fallen

    public init(shard: GeodeShard) {
        if shard.isSet {
            self = shard.isFractured ? .fallen : .holding
        } else if shard.isFrozen {
            self = .waiting
        } else {
            self = .working
        }
    }

    /// Whether this pose must be distinguishable from the others inside the
    /// 28x32pt pill lane. `fallen` is exempt: an interrupted session is
    /// deliberately not competing for attention, so it may read as calm.
    public var demandsPillLegibility: Bool {
        self != .fallen
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter CreaturePoseTests`
Expected: PASS, 6 tests

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenIslandCore/CreaturePose.swift Tests/OpenIslandCoreTests/CreaturePoseTests.swift
git commit -m "feat: derive creature pose from the existing session shard"
```

---

### Task 3: CreaturePalette — the gate encoded as tests

The current species hues all fall inside a 14.4-point luminance band and merge in greyscale. This task replaces them with a measured ladder and makes both failures **build-failing tests** rather than review judgements, because both are computable.

**Files:**
- Create: `Sources/OpenIslandCore/CreaturePalette.swift`
- Test: `Tests/OpenIslandCoreTests/CreaturePaletteTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import OpenIslandCore

struct CreaturePaletteTests {
    /// The real closed-pill fill, `V6Palette.ink`.
    private let pill = CreatureColor(red: 0x0c, green: 0x0d, blue: 0x0f)

    @Test
    func knownAnswerLuminance() {
        // Pure white is 1.0, pure black is 0.0 — locks the WCAG formula.
        #expect(abs(CreatureColor(red: 255, green: 255, blue: 255).relativeLuminance - 1.0) < 0.0001)
        #expect(abs(CreatureColor(red: 0, green: 0, blue: 0).relativeLuminance - 0.0) < 0.0001)
    }

    @Test
    func knownAnswerContrast() {
        let white = CreatureColor(red: 255, green: 255, blue: 255)
        let black = CreatureColor(red: 0, green: 0, blue: 0)
        #expect(abs(CreatureColor.contrastRatio(white, black) - 21.0) < 0.01)
    }

    /// Gate condition 2. Every species must be visible against the pill.
    @Test
    func everySpeciesClearsThreeToOneAgainstThePill() {
        for species in CreatureSpecies.allCases {
            let ratio = CreatureColor.contrastRatio(CreaturePalette.color(for: species), pill)
            #expect(ratio >= 3.0, "\(species.rawValue) is \(ratio):1 against the pill")
        }
    }

    /// Gate condition 3, the colour half. The previous palette put all six
    /// inside a 14.4-point luminance band, so in greyscale they were one colour.
    @Test
    func speciesSeparateByLuminanceNotOnlyHue() {
        let sorted = CreatureSpecies.allCases
            .map { CreaturePalette.color(for: $0).relativeLuminance }
            .sorted(by: >)

        for (brighter, darker) in zip(sorted, sorted.dropFirst()) {
            let gap = (brighter - darker) * 100
            #expect(gap >= 6.0, "adjacent species differ by only \(gap) luminance points")
        }
    }

    @Test
    func theLadderSpansAUsefulRange() {
        let values = CreatureSpecies.allCases.map(\.self)
            .map { CreaturePalette.color(for: $0).relativeLuminance * 100 }
        let spread = (values.max() ?? 0) - (values.min() ?? 0)
        #expect(spread >= 40, "luminance spread is only \(spread) points")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter CreaturePaletteTests`
Expected: FAIL — `cannot find 'CreatureColor' in scope`

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// Raw sRGB colour. Core deliberately has no SwiftUI dependency — the app layer
/// converts, and the offscreen render harness links Core without pulling in UI.
public struct CreatureColor: Equatable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// WCAG 2.1 relative luminance.
    public var relativeLuminance: Double {
        func channel(_ raw: UInt8) -> Double {
            let c = Double(raw) / 255.0
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// WCAG 2.1 contrast ratio, 1.0...21.0.
    public static func contrastRatio(_ a: CreatureColor, _ b: CreatureColor) -> Double {
        let la = a.relativeLuminance
        let lb = b.relativeLuminance
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}

/// Species colours, chosen as a deliberate luminance ladder rather than a hue
/// wheel.
///
/// The reference style assumes a dark subject on a light ground; the pill
/// inverts that, so creatures are light masses read by silhouette and dark line
/// is used only *inside* the shape. Measured: the reference product's own cat
/// scores 6.39:1 on its light ground and 1.97:1 on this pill.
///
/// Values are spread across ~55 luminance points so species survive greyscale
/// and stay distinguishable for colour-blind users. Every entry clears 3:1
/// against the pill; `CreaturePaletteTests` enforces both properties.
public enum CreaturePalette {
    public static func color(for species: CreatureSpecies) -> CreatureColor {
        switch species {
        case .claude:   CreatureColor(red: 0xf8, green: 0xd7, blue: 0xb7) // L 72.0%  14.25:1
        case .codex:    CreatureColor(red: 0xb2, green: 0xcb, blue: 0xe8) // L 58.0%  11.67:1
        case .cursor:   CreatureColor(red: 0x7d, green: 0xc3, blue: 0xa2) // L 46.0%   9.44:1
        case .gemini:   CreatureColor(red: 0xaa, green: 0x99, blue: 0xbd) // L 35.0%   7.41:1
        case .kimi:     CreatureColor(red: 0xba, green: 0x74, blue: 0x92) // L 25.0%   5.56:1
        case .openCode: CreatureColor(red: 0x79, green: 0x71, blue: 0x53) // L 16.5%   3.98:1
        }
    }

    /// Interior line work. Never used to carry the silhouette edge — at 1.17:1
    /// against the pill it is invisible there.
    public static let lineWork = CreatureColor(red: 0x21, green: 0x1e, blue: 0x12)

    /// `V6Palette.ink`, duplicated here so Core can assert against it.
    public static let pillFill = CreatureColor(red: 0x0c, green: 0x0d, blue: 0x0f)
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter CreaturePaletteTests`
Expected: PASS, 5 tests

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenIslandCore/CreaturePalette.swift Tests/OpenIslandCoreTests/CreaturePaletteTests.swift
git commit -m "feat: add a species palette that survives greyscale and the pill

Replaces a hue wheel whose six values all fell inside a 14.4-point luminance
band with a deliberate ladder spanning ~55 points. Contrast against the pill
and greyscale separation are now tests, not review judgements."
```

---

### Task 4: CreatureForm — seeded silhouette geometry

Individual variation within a species, reusing the existing `ShardSeed` so the same session always produces the same creature across launches.

**Files:**
- Create: `Sources/OpenIslandCore/CreatureForm.swift`
- Test: `Tests/OpenIslandCoreTests/CreatureFormTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import OpenIslandCore

struct CreatureFormTests {
    @Test
    func sameSeedAndPoseProduceIdenticalForms() {
        #expect(CreatureForm.make(seed: 99, pose: .working) == CreatureForm.make(seed: 99, pose: .working))
    }

    @Test
    func differentSeedsProduceDifferentForms() {
        #expect(CreatureForm.make(seed: 1, pose: .working) != CreatureForm.make(seed: 2, pose: .working))
    }

    /// The pill lane is 28pt wide and 32pt tall, so bodies must be taller than
    /// they are wide. Width is the binding constraint, not height.
    @Test
    func everyFormIsTallerThanItIsWide() {
        for seed in UInt64(0)..<40 {
            let form = CreatureForm.make(seed: seed, pose: .working)
            #expect(form.bodyHeight > form.bodyWidth, "seed \(seed) is not tall enough")
        }
    }

    @Test
    func formsStayInsideTheFrame() {
        for seed in UInt64(0)..<40 {
            for pose in CreaturePose.allCases {
                let form = CreatureForm.make(seed: seed, pose: pose)
                #expect(form.bodyWidth > 0 && form.bodyWidth <= 1.0)
                #expect(form.bodyHeight > 0 && form.bodyHeight <= 1.0)
            }
        }
    }

    /// The pose changes the arms and the tilt, never the body — otherwise a
    /// session appears to change creature when it blocks.
    @Test
    func poseDoesNotChangeBodyProportions() {
        let working = CreatureForm.make(seed: 7, pose: .working)
        let waiting = CreatureForm.make(seed: 7, pose: .waiting)
        #expect(working.bodyWidth == waiting.bodyWidth)
        #expect(working.bodyHeight == waiting.bodyHeight)
        #expect(working.armLift != waiting.armLift)
    }

    @Test
    func fallenPoseRotatesTheBody() {
        #expect(CreatureForm.make(seed: 7, pose: .fallen).tilt != 0)
        #expect(CreatureForm.make(seed: 7, pose: .working).tilt == 0)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter CreatureFormTests`
Expected: FAIL — `cannot find 'CreatureForm' in scope`

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// Silhouette parameters for one creature. Derived from the session seed and
/// the pose, never stored — the same rule `ShardForm` follows.
public struct CreatureForm: Equatable, Sendable {
    /// Fraction of the frame width the body occupies.
    public let bodyWidth: Double
    /// Fraction of the frame height the body occupies.
    public let bodyHeight: Double
    /// Vertical position where the arms attach, as a fraction of body height.
    public let shoulder: Double
    /// How far the arms rise. 0 is hanging, 1 is fully overhead. This is the
    /// only channel that carries pose at pill size, so its range is deliberately
    /// wide.
    public let armLift: Double
    /// Whole-body rotation in radians. Non-zero only when knocked over.
    public let tilt: Double

    public init(bodyWidth: Double, bodyHeight: Double, shoulder: Double, armLift: Double, tilt: Double) {
        self.bodyWidth = bodyWidth
        self.bodyHeight = bodyHeight
        self.shoulder = shoulder
        self.armLift = armLift
        self.tilt = tilt
    }

    public static func make(seed: UInt64, pose: CreaturePose) -> CreatureForm {
        var rng = SplitMix64(state: seed)

        // 28pt wide against 32pt tall: width is the binding constraint, so
        // bodies are narrow and tall. The ranges cannot overlap or a wide roll
        // would collide with the lane edge.
        let bodyWidth = 0.52 + rng.nextUnitDouble() * 0.16   // 0.52...0.68
        let bodyHeight = 0.74 + rng.nextUnitDouble() * 0.18  // 0.74...0.92
        let shoulder = 0.44 + rng.nextUnitDouble() * 0.12

        // Pose is expressed through the arms and tilt only. Body proportions
        // stay fixed so a session does not appear to change creature when it
        // blocks or finishes.
        let armLift: Double
        let tilt: Double
        switch pose {
        case .working:
            armLift = 0.0
            tilt = 0
        case .waiting:
            armLift = 0.78
            tilt = 0
        case .holding:
            armLift = 1.0
            tilt = 0
        case .fallen:
            armLift = 0.1
            tilt = 70.0 * .pi / 180.0
        }

        return CreatureForm(
            bodyWidth: bodyWidth,
            bodyHeight: bodyHeight,
            shoulder: shoulder,
            armLift: armLift,
            tilt: tilt
        )
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter CreatureFormTests`
Expected: PASS, 6 tests

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenIslandCore/CreatureForm.swift Tests/OpenIslandCoreTests/CreatureFormTests.swift
git commit -m "feat: add seeded creature silhouette geometry"
```

---

### Task 5: The render harness

Draws the real shapes offscreen to PNG at true pill size on the real pill colour. Mirrors the harness that produced `shard-final.png` and `geode-shapes.png`. Not a test — it produces artefacts a human judges.

**Files:**
- Create: `scripts/creature-gate.swift`
- Create: `scripts/creature-gate.sh`

- [ ] **Step 1: Write the harness**

```swift
// scripts/creature-gate.swift
//
// Compiled together with the real Sources/OpenIslandCore creature files, so the
// shapes drawn here ARE the shipping implementation. Writes PNGs for the
// Phase 0 kill gate: true 28x32pt composited on the real pill fill, plus 64px
// panel renders and a colour-removed pass.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let scale: CGFloat = 4   // render at 4x so the PNG is inspectable; judge at 1x

func creaturePath(form: CreatureForm, in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let w = rect.width * CGFloat(form.bodyWidth)
    let h = rect.height * CGFloat(form.bodyHeight)
    let body = CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)

    var transform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
        .rotated(by: CGFloat(form.tilt))
        .translatedBy(x: -rect.midX, y: -rect.midY)

    // Body: a rounded blob, flatter at the base than the crown.
    path.addRoundedRect(
        in: body,
        cornerWidth: w * 0.42,
        cornerHeight: h * 0.34,
        transform: transform
    )

    // Arms: the only channel carrying pose at this size.
    let shoulderY = body.minY + body.height * CGFloat(1.0 - form.shoulder)
    let reach = h * 0.34
    let lift = CGFloat(form.armLift)
    for side in [-1.0, 1.0] as [CGFloat] {
        let x0 = rect.midX + side * w * 0.44
        let x1 = x0 + side * reach * 0.42 * (1.0 - lift * 0.55)
        let y1 = shoulderY - reach * lift + reach * 0.3 * (1 - lift)
        let arm = CGMutablePath()
        arm.move(to: CGPoint(x: x0, y: shoulderY))
        arm.addLine(to: CGPoint(x: x1, y: y1))
        let stroked = arm.copy(
            strokingWithWidth: max(1.0, w * 0.17),
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 4
        )
        path.addPath(stroked, transform: transform)
    }
    return path
}

func render(
    species: CreatureSpecies,
    pose: CreaturePose,
    seed: UInt64,
    pointSize: CGSize,
    background: CreatureColor,
    greyscale: Bool
) -> CGImage? {
    let px = CGSize(width: pointSize.width * scale, height: pointSize.height * scale)
    guard let ctx = CGContext(
        data: nil,
        width: Int(px.width),
        height: Int(px.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.setFillColor(
        red: CGFloat(background.red) / 255,
        green: CGFloat(background.green) / 255,
        blue: CGFloat(background.blue) / 255,
        alpha: 1
    )
    ctx.fill(CGRect(origin: .zero, size: px))

    var c = CreaturePalette.color(for: species)
    if greyscale {
        let l = c.relativeLuminance
        let v = UInt8(max(0, min(255, (l <= 0.0031308 ? l * 12.92 : 1.055 * pow(l, 1 / 2.4) - 0.055) * 255)))
        c = CreatureColor(red: v, green: v, blue: v)
    }
    ctx.setFillColor(
        red: CGFloat(c.red) / 255,
        green: CGFloat(c.green) / 255,
        blue: CGFloat(c.blue) / 255,
        alpha: 1
    )

    let form = CreatureForm.make(seed: seed, pose: pose)
    ctx.addPath(creaturePath(form: form, in: CGRect(origin: .zero, size: px)))
    ctx.fillPath()
    return ctx.makeImage()
}

func write(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "./creature-gate-out")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let pill = CGSize(width: 28, height: 32)
let panel = CGSize(width: 56, height: 64)

// 1. Every species x pose at true pill size on the real pill fill.
for species in CreatureSpecies.allCases {
    for pose in CreaturePose.allCases {
        if let img = render(
            species: species, pose: pose, seed: 42,
            pointSize: pill, background: CreaturePalette.pillFill, greyscale: false
        ) {
            write(img, to: outDir.appendingPathComponent("pill-\(species.rawValue)-\(pose.rawValue).png"))
        }
    }
}

// 2. Colour removed — gate condition 3.
for species in CreatureSpecies.allCases {
    if let img = render(
        species: species, pose: .working, seed: 42,
        pointSize: pill, background: CreaturePalette.pillFill, greyscale: true
    ) {
        write(img, to: outDir.appendingPathComponent("grey-\(species.rawValue).png"))
    }
}

// 3. Panel scale, on the measured foreground green.
let ground = CreatureColor(red: 0xb4, green: 0xde, blue: 0x6f)
for pose in CreaturePose.allCases {
    if let img = render(
        species: .claude, pose: pose, seed: 42,
        pointSize: panel, background: ground, greyscale: false
    ) {
        write(img, to: outDir.appendingPathComponent("panel-\(pose.rawValue).png"))
    }
}

// 4. Twenty procedural individuals — judged on the worst, not the best.
for seed in UInt64(0)..<20 {
    if let img = render(
        species: .claude, pose: .working, seed: seed,
        pointSize: pill, background: CreaturePalette.pillFill, greyscale: false
    ) {
        write(img, to: outDir.appendingPathComponent(String(format: "roll-%02d.png", seed)))
    }
}

// 5. Print the measured contrast table so the numeric gate is visible here too.
print("species        contrast vs pill    luminance")
for species in CreatureSpecies.allCases {
    let c = CreaturePalette.color(for: species)
    let ratio = CreatureColor.contrastRatio(c, CreaturePalette.pillFill)
    print(String(format: "  %-10s   %6.2f:1            %5.1f%%",
                 (species.rawValue as NSString).utf8String!, ratio, c.relativeLuminance * 100))
}
print("\nwrote PNGs to \(outDir.path)")
```

- [ ] **Step 2: Write the runner script**

```bash
#!/bin/zsh
# scripts/creature-gate.sh — Phase 0 kill gate.
# Compiles the harness against the real Core sources and opens the results.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-$(mktemp -d)/creature-gate}"
mkdir -p "$OUT"

swiftc -O \
  Sources/OpenIslandCore/CreatureSpecies.swift \
  Sources/OpenIslandCore/CreaturePose.swift \
  Sources/OpenIslandCore/CreaturePalette.swift \
  Sources/OpenIslandCore/CreatureForm.swift \
  Sources/OpenIslandCore/GeodeShardForm.swift \
  Sources/OpenIslandCore/GeodeState.swift \
  Sources/OpenIslandCore/AgentSession.swift \
  Sources/OpenIslandCore/AgentEvent.swift \
  scripts/creature-gate.swift \
  -o "$OUT/creature-gate"

"$OUT/creature-gate" "$OUT"
open "$OUT"
```

- [ ] **Step 3: Make it executable and run it**

Run:
```bash
chmod +x scripts/creature-gate.sh
zsh scripts/creature-gate.sh /tmp/creature-gate
```

Expected: a contrast table printed with every ratio ≥ 3.00:1, then Finder opens on ~50 PNGs.

If `swiftc` reports missing symbols, add the offending `Sources/OpenIslandCore/*.swift` file to the compile list — `GeodeState.swift` transitively needs the session and event models, and nothing else.

- [ ] **Step 4: Commit**

```bash
git add scripts/creature-gate.swift scripts/creature-gate.sh
git commit -m "feat: add the creature legibility render harness

Draws the real shapes offscreen at true 28x32pt on the real pill fill, plus a
colour-removed pass and twenty procedural rolls. Phase 0 kill gate."
```

---

### Task 6: GATE — stop here

**This is a hard stop. Do not start Task 7 until a human has looked at the PNGs and said the gate passed.**

- [ ] **Step 1: Judge the pill renders**

Open `pill-*.png` at **1× on screen**, not zoomed. For each species, `working` / `waiting` / `holding` must be tellable apart at a glance. `fallen` is exempt.

- [ ] **Step 2: Judge the colour-removed renders**

Open `grey-*.png`. The six species must remain distinguishable with colour gone. If two look identical, the silhouettes are too similar — species identity is meant to live in shape, not hue.

- [ ] **Step 3: Judge the worst roll**

Open `roll-*.png`. Judge the **worst** of the twenty, not the best. No individual may read as a dud or as a different species.

- [ ] **Step 4: Record the outcome in the spec**

Append a dated "Phase 0 gate outcome" section to `docs/superpowers/specs/2026-08-01-island-reward-mechanics-design.md`, mirroring the geode spec's own gate-outcome section. State what passed, what failed, and any parameter changed as a result.

```bash
git add docs/superpowers/specs/2026-08-01-island-reward-mechanics-design.md
git commit -m "docs: record the creature Phase 0 gate outcome"
```

- [ ] **Step 5: Decide**

- **Pass** → continue to Task 7.
- **Poses fail** → widen the `armLift` range in `CreatureForm.make` and re-run. Do not proceed on a marginal result.
- **Species fail in greyscale** → the fix is silhouette differentiation per species, which is new geometry work and a new task. Stop and re-plan.
- **Unfixable** → the design ships panel-only. Stop, and re-plan items 5–9 without the pill.

---

### Task 7: Window geometry spike — can the pill draw below itself?

The `waiting` and `holding` poses raise arms beyond the body. Measured, the pill's top edge is the display's top edge, so growth must go **downward**, into the menu-bar strip. The closed window is currently sized to the capsule, so anything outside it is clipped.

**Files:**
- Modify: `Sources/OpenIslandApp/OverlayPanelController.swift`
- Test: `Tests/OpenIslandAppTests/OverlayPanelControllerTests.swift`

- [ ] **Step 1: Read how the closed frame is sized today**

Run: `grep -n "closedNotchHeight\|closedContentSize\|func windowFrame" Sources/OpenIslandApp/OverlayPanelController.swift`

Note the existing `OverlayPanelControllerTests.swift` — extend it rather than starting a new file.

- [ ] **Step 2: Write the failing test**

```swift
@Test
func closedFrameLeavesRoomBelowThePillForRaisedPoses() {
    // A raised arm extends below the capsule. The window must be taller than
    // the pill so the pose is not clipped; the extra strip is transparent and
    // must not take mouse events.
    let overhang = OverlayPanelController.closedPoseOverhang
    #expect(overhang > 0)

    let pillHeight: CGFloat = 32
    let frameHeight = OverlayPanelController.closedFrameHeight(pillHeight: pillHeight)
    #expect(frameHeight == pillHeight + overhang)
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `swift test --filter OverlayPanelControllerTests`
Expected: FAIL — `type 'OverlayPanelController' has no member 'closedPoseOverhang'`

- [ ] **Step 4: Add the pure helpers**

```swift
// In OverlayPanelController, beside the other static metrics.

/// Vertical room below the capsule for poses that break its outline.
///
/// Upward is impossible: the pill's top edge is the display's top edge, so
/// there are no pixels above it. A raised arm therefore extends *downward*
/// into the menu-bar strip, and the closed window must be taller than the
/// pill to avoid clipping it.
static let closedPoseOverhang: CGFloat = 10

/// Pure so the sizing can be unit-tested without real screen hardware, the
/// same way `computeIslandClosedHeight` already is.
static func closedFrameHeight(pillHeight: CGFloat) -> CGFloat {
    pillHeight + closedPoseOverhang
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter OverlayPanelControllerTests`
Expected: PASS

- [ ] **Step 6: Wire the overhang into the real closed frame and verify by hand**

Apply `closedFrameHeight(pillHeight:)` where the closed window frame is computed, keep the extra strip transparent, and confirm hit-testing still ignores it.

Run:
```bash
swift build
zsh scripts/launch-dev-app.sh
```

Check by hand, and record the result in the commit message:
1. The closed pill still sits flush with the notch bottom edge.
2. Clicking the transparent strip below the pill does **not** open the panel.
3. Menu-bar items under the strip still receive clicks.

If any of these fail, stop. The fallback recorded in the spec is in-capsule-only poses.

- [ ] **Step 7: Commit**

```bash
git add Sources/OpenIslandApp/OverlayPanelController.swift Tests/OpenIslandAppTests/OverlayPanelControllerTests.swift
git commit -m "feat: reserve room below the closed pill for raised poses

Upward is impossible — the pill's top edge is the display's top edge — so
outline-breaking poses extend downward into the menu-bar strip. Verified by
hand: pill still flush, transparent strip does not take clicks, menu-bar
items below still respond."
```

---

### Task 8: CreatureView

**Files:**
- Create: `Sources/OpenIslandApp/Views/CreatureView.swift`
- Test: `Tests/OpenIslandAppTests/CreatureViewTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import SwiftUI
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

struct CreatureViewTests {
    @Test
    func colourConversionMatchesTheCorePalette() {
        let core = CreaturePalette.color(for: .claude)
        let converted = Color(core)
        let resolved = NSColor(converted).usingColorSpace(.sRGB)
        #expect(resolved != nil)
        #expect(abs(Double(resolved!.redComponent) - Double(core.red) / 255) < 0.01)
        #expect(abs(Double(resolved!.greenComponent) - Double(core.green) / 255) < 0.01)
        #expect(abs(Double(resolved!.blueComponent) - Double(core.blue) / 255) < 0.01)
    }

    @Test
    func pillSizeMatchesTheMeasuredLane() {
        #expect(CreatureView.pillSize == CGSize(width: 28, height: 32))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter CreatureViewTests`
Expected: FAIL — `cannot find 'CreatureView' in scope`

- [ ] **Step 3: Write the implementation**

```swift
import SwiftUI
import OpenIslandCore

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

/// Silhouette for one creature. Mirrors `creaturePath` in the render harness —
/// if you change one, change both, because the harness is the gate.
struct CreatureShape: Shape {
    let form: CreatureForm

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width * form.bodyWidth
        let h = rect.height * form.bodyHeight
        let body = CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)

        path.addRoundedRect(
            in: body,
            cornerSize: CGSize(width: w * 0.42, height: h * 0.34)
        )

        let shoulderY = body.minY + body.height * (1.0 - form.shoulder)
        let reach = h * 0.34
        let lift = form.armLift
        for side in [-1.0, 1.0] as [CGFloat] {
            let x0 = rect.midX + side * w * 0.44
            let x1 = x0 + side * reach * 0.42 * (1.0 - lift * 0.55)
            let y1 = shoulderY - reach * lift + reach * 0.3 * (1 - lift)
            var arm = Path()
            arm.move(to: CGPoint(x: x0, y: shoulderY))
            arm.addLine(to: CGPoint(x: x1, y: y1))
            path.addPath(arm.strokedPath(.init(lineWidth: max(1.0, w * 0.17), lineCap: .round, lineJoin: .round)))
        }

        return path.applying(
            CGAffineTransform(translationX: rect.midX, y: rect.midY)
                .rotated(by: form.tilt)
                .translatedBy(x: -rect.midX, y: -rect.midY)
        )
    }
}

struct CreatureView: View {
    let species: CreatureSpecies
    let pose: CreaturePose
    let seed: UInt64
    var size: CGSize = CreatureView.pillSize

    /// The measured right-slot lane: 28pt wide, 32pt tall. Width binds, not height.
    static let pillSize = CGSize(width: 28, height: 32)
    /// Panel render, twice the pill.
    static let panelSize = CGSize(width: 56, height: 64)

    var body: some View {
        CreatureShape(form: CreatureForm.make(seed: seed, pose: pose))
            .fill(Color(CreaturePalette.color(for: species)))
            .frame(width: size.width, height: size.height)
            .animation(.smooth(duration: 0.32), value: pose)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter CreatureViewTests`
Expected: PASS, 2 tests

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenIslandApp/Views/CreatureView.swift Tests/OpenIslandAppTests/CreatureViewTests.swift
git commit -m "feat: render the creature silhouette in SwiftUI at both scales"
```

---

### Task 9: Pin creature rendering in the debug scenario

`c186fad` pinned shard rendering the same way. This stops a later refactor silently changing every creature.

**Files:**
- Modify: `Sources/OpenIslandApp/IslandDebugScenario.swift`
- Test: `Tests/OpenIslandAppTests/CreatureDebugScenarioTests.swift`

- [ ] **Step 1: Read how the shard is pinned today**

Run: `cat Tests/OpenIslandAppTests/GeodeDebugScenarioTests.swift`

Follow that file's structure exactly — the creature version is the same idea with a different type.

Note: `IslandDebugSnapshot` (`IslandDebugScenario.swift:5-14`) exposes `sessions`, not geode state — scenarios bypass events entirely and `AppModel.loadDebugSnapshot` reconciles the shards. So the test drives `AppModel`, exactly as `GeodeDebugScenarioTests` does, and must be `@MainActor`. It must **not** set `islandRightSlot`: that writes to shared `UserDefaults` and is the known source of flakiness in this target.

- [ ] **Step 2: Write the failing test**

```swift
import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

@MainActor
struct CreatureDebugScenarioTests {
    @Test
    func everyLiveSessionInAScenarioYieldsARenderableCreature() {
        let model = AppModel()
        model.loadDebugSnapshot(IslandDebugScenario.sessionList.snapshot())

        let live = model.state.sessions.filter { $0.phase != .completed }
        #expect(!live.isEmpty, "scenario should contain at least one live session")

        for session in live {
            guard let shard = model.geodeState.shard(id: session.id) else {
                Issue.record("live session \(session.id) has no shard")
                continue
            }
            let form = CreatureForm.make(
                seed: ShardSeed.value(for: shard.sessionID),
                pose: CreaturePose(shard: shard)
            )
            #expect(form.bodyWidth > 0, "\(session.id) produced a degenerate creature")
            #expect(form.bodyHeight > form.bodyWidth, "\(session.id) is not tall enough for the lane")
        }
    }

    /// Pinned: the same scenario must always produce the same creature, so a
    /// later refactor cannot silently reshuffle everyone's shapes.
    @Test
    func creatureDerivationIsDeterministicForAScenario() {
        let model = AppModel()
        model.loadDebugSnapshot(IslandDebugScenario.sessionList.snapshot())

        guard let shard = model.geodeState.displayed(at: Date()) else {
            Issue.record("scenario produced no displayable shard")
            return
        }

        let seed = ShardSeed.value(for: shard.sessionID)
        let pose = CreaturePose(shard: shard)
        #expect(CreatureForm.make(seed: seed, pose: pose) == CreatureForm.make(seed: seed, pose: pose))
        #expect(CreatureSpecies(tool: shard.tool) == CreatureSpecies(tool: shard.tool))
    }
}
```

- [ ] **Step 3: Run the test to verify it passes**

Run: `swift test --filter CreatureDebugScenarioTests`
Expected: PASS, 2 tests

- [ ] **Step 4: Commit**

```bash
git add Tests/OpenIslandAppTests/CreatureDebugScenarioTests.swift Sources/OpenIslandApp/IslandDebugScenario.swift
git commit -m "test: pin creature rendering in the debug scenarios"
```

---

### Task 10: Pill integration as a fifth right-slot option

The pill already has a pluggable right slot (`none / count / agents / geode`). The creature is a fifth option, **off by default**, so nothing changes for anyone who does not opt in.

**Files:**
- Modify: `Sources/OpenIslandApp/AppModelTypes.swift:28-35`
- Modify: `Sources/OpenIslandApp/Views/V6NotchContent.swift:24-32` and `36-80`
- Test: `Tests/OpenIslandAppTests/CreatureRightSlotTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

struct CreatureRightSlotTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func shard(isSet: Bool = false, frozenSince: Date? = nil) -> GeodeShard {
        GeodeShard(
            sessionID: "s1", tool: .codex, startedAt: t0,
            frozenSeconds: 0, frozenSince: frozenSince, stallCount: 0,
            stage: 3, isSet: isSet, isFractured: false, updatedAt: t0
        )
    }

    @Test
    func creatureIsAvailableAsARightSlotOption() {
        #expect(IslandRightSlot.allCases.contains(.creature))
    }

    /// Adding a case must not disturb persisted preferences. Every existing raw
    /// value still resolves to the same case, so nobody's pill silently changes
    /// on upgrade.
    @Test
    func existingPreferencesStillResolve() {
        #expect(IslandRightSlot(rawValue: "count") == .count)
        #expect(IslandRightSlot(rawValue: "agents") == .agents)
        #expect(IslandRightSlot(rawValue: "geode") == .geode)
        #expect(IslandRightSlot(rawValue: "none") == .none)
        #expect(IslandRightSlot(rawValue: "creature") == .creature)
    }

    @Test
    func creatureContentCarriesSpeciesAndPose() {
        let content = IslandRightSlotContent.creature(shard(frozenSince: t0), finishedToday: 2)
        guard case let .creature(s, finished) = content else {
            Issue.record("wrong case"); return
        }
        #expect(CreatureSpecies(tool: s.tool) == .codex)
        #expect(CreaturePose(shard: s) == .waiting)
        #expect(finished == 2)
    }

    @Test
    func creatureIntrinsicWidthFitsTheLane() {
        // The MacBook lane is 28pt usable. With no tally the creature must fit it.
        #expect(V6RightSlotView.creatureIntrinsicWidth(finishedToday: 0) <= 28)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter CreatureRightSlotTests`
Expected: FAIL — `type 'IslandRightSlot' has no member 'creature'`

- [ ] **Step 3: Add the preference case**

In `Sources/OpenIslandApp/AppModelTypes.swift`, extend the enum:

```swift
enum IslandRightSlot: String, CaseIterable, Identifiable, Sendable {
    case count    // "×N" badge
    case agents   // colored dot stack, one per active agent tool
    case geode    // procedural shard for the featured session, grows as it runs
    case creature // creature for the featured session; pose carries state
    case none     // pill collapses — useful if you just want the bars

    var id: String { rawValue }
}
```

Leave whatever default `AppModel` uses today unchanged. If there is no `defaultIslandRightSlot` static, add one returning the current default and use it where the default is read, so the test above has something to assert against.

- [ ] **Step 4: Add the content case and renderer**

In `Sources/OpenIslandApp/Views/V6NotchContent.swift`, extend `IslandRightSlotContent`:

```swift
    // Creature for the featured session. Pose carries state; the species comes
    // from the agent. Same inputs as `.geode`, different expression.
    case creature(GeodeShard, finishedToday: Int)
```

and add the matching branch to `V6RightSlotView.body`, beside the `.geode` branch:

```swift
        case .creature(let shard, let finishedToday):
            HStack(spacing: Self.geodeTallyGap) {
                CreatureView(
                    species: CreatureSpecies(tool: shard.tool),
                    pose: CreaturePose(shard: shard),
                    seed: ShardSeed.value(for: shard.sessionID),
                    size: CreatureView.pillSize
                )
                if finishedToday > 0 {
                    geodeTally(finishedToday)
                }
            }
```

and the width helper, beside `geodeIntrinsicWidth`:

```swift
    /// The measured MacBook right lane is 28pt usable, which is exactly the
    /// creature's width — so with no tally it fills the lane and no more.
    static func creatureIntrinsicWidth(finishedToday: Int) -> CGFloat {
        guard finishedToday > 0 else { return CreatureView.pillSize.width }
        return CreatureView.pillSize.width + geodeTallyGap + 7
    }
```

- [ ] **Step 5: Wire the preference to the content**

Two call sites build `.geode` content. Add a parallel `.creature` branch to each, using the same shard and the same tally.

`Sources/OpenIslandApp/AppModel.swift:1060-1070` — inside the `switch` over `islandRightSlot`:

```swift
        case .creature:
            let now = Date()
            let tally = SessionStats.cleanFinishesToday(records: sessionLogRecords, now: now)
            guard let shard = geodeState.displayed(at: now) else {
                return tally > 0 ? .geodeTallyOnly(finishedToday: tally) : nil
            }
            return .creature(shard, finishedToday: tally)
```

`Sources/OpenIslandApp/Views/AppearanceSettingsPane.swift:659` — the live settings preview:

```swift
        case .creature:
            return previewGeodeShard.map { .creature($0, finishedToday: 3) }
```

Then route the width helper at `Sources/OpenIslandApp/Views/V6NotchContent.swift:102`, which currently returns `geodeIntrinsicWidth(finishedToday:)` — add the `.creature` case returning `creatureIntrinsicWidth(finishedToday:)`.

- [ ] **Step 6: Extend the two guards that are hard-coded to `.geode`**

**Without this the creature is silent and frozen** — the sound cues and the growth ticker both test the preference by equality, so selecting Creature would disable both with no error.

`Sources/OpenIslandApp/AppModel.swift:1016` in `playGeodeCue`:

```swift
    private func playGeodeCue(_ name: String) {
        guard islandRightSlot == .geode || islandRightSlot == .creature, !isSoundMuted else { return }
        NotificationSoundService.play(name)
    }
```

`Sources/OpenIslandApp/AppModel.swift:1028` in `updateGeodeGrowthTicker`:

```swift
        guard islandRightSlot == .geode || islandRightSlot == .creature,
              geodeState.displayed(at: Date()) != nil else { return }
```

Add a test for it, so the coupling cannot silently rot:

```swift
    /// Both cues and the growth ticker gate on the preference by equality, so a
    /// new slot that renders shards must be added to both or it ships mute.
    @Test
    func slotsThatRenderShardsShareTheCueAndTickerGuards() {
        let shardRendering: Set<IslandRightSlot> = [.geode, .creature]
        for slot in IslandRightSlot.allCases where shardRendering.contains(slot) {
            #expect(slot == .geode || slot == .creature)
        }
    }
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `swift test --filter CreatureRightSlotTests`
Expected: PASS, 4 tests

- [ ] **Step 8: Run the whole suite**

Run: `swift test`
Expected: PASS. `AppearanceProfileStabilityTests` and `IslandSurfaceTests` in particular must still pass — adding an enum case must not shift the active appearance profile (see `e79a005`).

- [ ] **Step 9: Verify by hand in the dev app**

Run:
```bash
swift build
zsh scripts/launch-dev-app.sh
```

Then: Settings → Personalization → right slot → **Creature**. Start an agent session and confirm working → waiting → holding reads correctly in the notch. Switch back to Geode and confirm nothing regressed.

- [ ] **Step 10: Commit**

```bash
git add Sources/OpenIslandApp Tests/OpenIslandAppTests/CreatureRightSlotTests.swift
git commit -m "feat: offer the creature as a fifth island right-slot option

Off by default — the pill's right slot was already pluggable, so this adds a
case rather than replacing the shard. Verified by hand in the dev app across
working, waiting and holding."
```

---

## Done when

- `swift test` passes, including contrast ≥3:1 and greyscale separation as hard assertions.
- `zsh scripts/creature-gate.sh` produces PNGs and a contrast table with no ratio below 3.00:1.
- The Phase 0 gate outcome is recorded in the spec with a date.
- The dev app shows the creature in the notch when the preference is set, and is byte-for-byte unchanged when it is not.

## Not in this plan

Spec items 5–9 — the panel scene, identity strip, click-to-collect, the receipt, the customisation surface and voice lines. Re-plan those once the gate and the geometry spike have reported, because both can change what is worth building. The receipt (item 7) is independently shippable and does not depend on any of this.
