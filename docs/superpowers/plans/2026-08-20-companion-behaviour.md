# Companion Behaviour Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the companion in the closed pill encode real session state — three resting poses, still by default, with rare unprompted motion and brief transitions.

**Architecture:** A pure `CompanionPose` enum derived from `surfacedSessions` on `AppModel`, mirroring the existing `islandClosedMode` computed property. `CompanionPillView` renders a still image per pose and owns all motion policy. No new subsystem; no session knowledge in the view.

**Tech Stack:** Swift 6.2, SwiftUI, Swift Testing (`import Testing`, `@Test`, `#expect`), macOS 14+.

**Spec:** `docs/superpowers/specs/2026-08-20-companion-behaviour-design.md`

---

## Context you need before starting

The companion already exists and ships **off by default** behind `AppModel.showCompanion`. `CompanionPillView` currently plays a 12-frame wag loop whenever `mode != .idle`. **That continuous loop is the thing this plan removes** — peripheral attention is captured by motion onset involuntarily, so a loop running all day spends attention for no information.

Existing pieces you will touch:
- `Sources/OpenIslandApp/Views/CompanionPillView.swift` — the view and its `CompanionLoop` frame cache
- `Sources/OpenIslandApp/Views/V6NotchContent.swift:228` — `showsCompanion` flag on `V6ClosedPill`
- `Sources/OpenIslandApp/AppModel.swift:854` — `islandClosedMode`, the property your derivation sits beside
- `Sources/OpenIslandApp/Resources/Companion/companion-wag-00..11.png` — current frames, 112×128

`SessionPhase` (in `Sources/OpenIslandCore/AgentSession.swift:109`) has exactly four cases: `running`, `waitingForApproval`, `waitingForAnswer`, `completed`. `phase.requiresAttention` is already defined and covers the two waiting cases.

Source art for the new poses is **already generated** at `~/Documents/openisland-refs/gauntlet/out/light/` — `w1-sit.png`, `w2-drape.png`, `w4-stand.png`, all 2048×2048 on a cream ground. No image generation is needed.

**Known substitution:** the spec calls the resting pose "curled, asleep". No curled cream dog exists — `d4-curl` was generated in the dark colourway and failed legibility (an amorphous blob with no species information). This plan uses `w2-drape` (sprawled on its side) as the sleeping pose. Task 6 verifies it reads at 28×32; if it fails, that is a real finding to report, not something to work around.

---

## File Structure

| File | Responsibility |
|---|---|
| `Sources/OpenIslandApp/CompanionPose.swift` *(create)* | The enum and its asset base names. Pure, no SwiftUI. |
| `Sources/OpenIslandApp/AppModel.swift` *(modify)* | `companionPose` derivation beside `islandClosedMode`. |
| `Sources/OpenIslandApp/Views/CompanionPillView.swift` *(modify)* | Renders a pose; owns motion policy and reduce-motion. |
| `Sources/OpenIslandApp/Views/V6NotchContent.swift` *(modify)* | Passes pose through instead of `mode`. |
| `Sources/OpenIslandApp/Views/IslandPanelView.swift` *(modify)* | Supplies `model.companionPose`. |
| `Sources/OpenIslandApp/Resources/Companion/` *(add)* | `companion-{sleeping,alert,attending}.png` |
| `Tests/OpenIslandAppTests/CompanionPoseTests.swift` *(create)* | Derivation tests over session fixtures. |

---

## Task 1: The pose enum and its derivation

**Files:**
- Create: `Sources/OpenIslandApp/CompanionPose.swift`
- Modify: `Sources/OpenIslandApp/AppModel.swift` (after `islandClosedMode`, currently line 854-859)
- Test: `Tests/OpenIslandAppTests/CompanionPoseTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/OpenIslandAppTests/CompanionPoseTests.swift`:

```swift
import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
struct CompanionPoseTests {
    @Test
    func noSessionsSleeps() {
        let model = AppModel()
        model.state = SessionState(sessions: [])
        #expect(model.companionPose == .sleeping)
    }

    @Test
    func aRunningSessionIsAlert() {
        let model = AppModel()
        model.state = SessionState(sessions: [makeSession(id: "A", phase: .running)])
        #expect(model.companionPose == .alert)
    }

    @Test
    func attentionOutranksRunning() {
        let model = AppModel()
        model.state = SessionState(sessions: [
            makeSession(id: "A", phase: .running),
            makeSession(id: "B", phase: .waitingForApproval),
        ])
        #expect(model.companionPose == .attending)
    }

    @Test
    func waitingForAnswerAlsoAttends() {
        let model = AppModel()
        model.state = SessionState(sessions: [makeSession(id: "A", phase: .waitingForAnswer)])
        #expect(model.companionPose == .attending)
    }

    /// Completion is a transient event, never a resting pose. A finished
    /// session with nothing else running settles back to sleeping.
    @Test
    func completionIsNotARestingPose() {
        let model = AppModel()
        model.state = SessionState(sessions: [makeSession(id: "A", phase: .completed)])
        #expect(model.companionPose == .sleeping)
    }

    /// The companion is indifferent to count -- twelve running agents look
    /// exactly like one. Quantity is the right-slot badge's job.
    @Test
    func poseIsIndifferentToCount() {
        let one = AppModel()
        one.state = SessionState(sessions: [makeSession(id: "A", phase: .running)])

        let many = AppModel()
        many.state = SessionState(sessions: (0..<12).map {
            makeSession(id: "S\($0)", phase: .running)
        })

        #expect(one.companionPose == many.companionPose)
    }

    private func makeSession(id: String, phase: SessionPhase) -> AgentSession {
        let now = Date(timeIntervalSince1970: 100_000)
        var session = AgentSession(
            id: id,
            title: "Claude · \(id)",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: phase,
            summary: "",
            updatedAt: now,
            firstSeenAt: now,
            permissionRequest: nil,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: id,
                paneTitle: "claude ~/\(id)",
                workingDirectory: "/tmp/\(id)",
                terminalSessionID: "ghostty-\(id)"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                transcriptPath: "/tmp/\(id).jsonl",
                currentTool: "Task"
            )
        )
        session.isProcessAlive = true
        session.isHookManaged = true
        return session
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter CompanionPoseTests`
Expected: compile failure — `value of type 'AppModel' has no member 'companionPose'`.

- [ ] **Step 3: Create the enum**

Create `Sources/OpenIslandApp/CompanionPose.swift`:

```swift
import Foundation

/// The companion's resting pose. The pose IS the status readout -- if it did
/// not encode session state it would be decoration sitting beside a separate
/// status display, paying attention-rent for no information.
///
/// There is deliberately no `completed` case. Completion is a transient beat,
/// after which the companion settles into whichever resting pose the remaining
/// sessions call for. A pose that lingered would show a stale fact.
enum CompanionPose: String, CaseIterable, Sendable {
    /// Nothing is running.
    case sleeping
    /// At least one session is working.
    case alert
    /// A session needs approval or an answer.
    case attending

    /// Base name of the still image in the Companion resource directory.
    var assetName: String { "companion-\(rawValue)" }
}
```

- [ ] **Step 4: Add the derivation**

In `Sources/OpenIslandApp/AppModel.swift`, immediately after the closing brace of `islandClosedMode`, add:

```swift
    /// The companion's resting pose. Mirrors `islandClosedMode`'s precedence --
    /// attention first, then running -- but is deliberately indifferent to how
    /// many sessions are in each state. Count is the right slot's job; a drawing
    /// communicates quantity badly and would have to infer an aggregate mood.
    var companionPose: CompanionPose {
        let sessions = surfacedSessions
        if sessions.contains(where: { $0.phase.requiresAttention }) { return .attending }
        if sessions.contains(where: { $0.phase == .running })       { return .alert }
        return .sleeping
    }
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter CompanionPoseTests`
Expected: 6 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/OpenIslandApp/CompanionPose.swift Sources/OpenIslandApp/AppModel.swift Tests/OpenIslandAppTests/CompanionPoseTests.swift
git commit -m "feat: derive a companion pose from session state"
```

---

## Task 2: Export the three pose assets

**Files:**
- Create: `Sources/OpenIslandApp/Resources/Companion/companion-sleeping.png`
- Create: `Sources/OpenIslandApp/Resources/Companion/companion-alert.png`
- Create: `Sources/OpenIslandApp/Resources/Companion/companion-attending.png`

Source art is at `~/Documents/openisland-refs/gauntlet/out/light/`. The cream ground is opaque, so it must be keyed out by colour distance — a luminance threshold will not work, because a cream dog on cream paper has no luminance separation.

- [ ] **Step 1: Export the three stills**

Run this exactly (uses `/usr/bin/python3`, which is the interpreter on this machine with PIL and scipy — Homebrew's `python3` has neither):

```bash
/usr/bin/python3 - <<'PY'
import numpy as np
from PIL import Image
from scipy import ndimage

SRC = "/Users/nambouchara/Documents/openisland-refs/gauntlet/out/light"
OUT = "Sources/OpenIslandApp/Resources/Companion"
BOX = (112, 128)                      # 4x the 28x32 pill slot
POSES = {"sleeping": "w2-drape", "alert": "w4-stand", "attending": "w1-sit"}

for pose, src in POSES.items():
    im = Image.open(f"{SRC}/{src}.png").convert("RGB")
    a = np.asarray(im).astype(np.int16)
    edge = np.concatenate([a[:12].reshape(-1, 3), a[-12:].reshape(-1, 3),
                           a[:, :12].reshape(-1, 3), a[:, -12:].reshape(-1, 3)])
    paper = np.median(edge, 0)
    m = ndimage.binary_fill_holes(np.abs(a - paper).sum(2) > 26)
    m = ndimage.binary_closing(m, np.ones((9, 9)))
    rgba = np.dstack([np.asarray(im), (m * 255).astype(np.uint8)])
    ys, xs = np.nonzero(m)
    crop = Image.fromarray(rgba).crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    crop.thumbnail(BOX, Image.LANCZOS)
    canvas = Image.new("RGBA", BOX, (0, 0, 0, 0))
    canvas.paste(crop, ((BOX[0] - crop.width) // 2, (BOX[1] - crop.height) // 2), crop)
    canvas.save(f"{OUT}/companion-{pose}.png")
    print(f"companion-{pose}.png  from {src}  {crop.width}x{crop.height} in {BOX}")
PY
```

Expected output: three lines, one per pose, each reporting a crop smaller than 112×128.

- [ ] **Step 2: Verify the files exist and carry alpha**

Run: `/usr/bin/python3 -c "from PIL import Image; [print(p, Image.open(f'Sources/OpenIslandApp/Resources/Companion/companion-{p}.png').mode) for p in ('sleeping','alert','attending')]"`
Expected: three lines each ending `RGBA`.

- [ ] **Step 3: Commit**

```bash
git add Sources/OpenIslandApp/Resources/Companion/
git commit -m "feat: add companion still poses for each session state"
```

---

## Task 3: Render the pose, still, with reduce-motion honoured

This is the task that removes the continuous loop.

**Files:**
- Modify: `Sources/OpenIslandApp/Views/CompanionPillView.swift` (full rewrite)
- Modify: `Sources/OpenIslandApp/Views/V6NotchContent.swift` (2 call sites, lines ~263 and ~308)
- Modify: `Sources/OpenIslandApp/Views/IslandPanelView.swift:284`

- [ ] **Step 1: Invoke the swiftui-design skill**

Run the `swiftui-design` skill before writing the view. It carries the project's SwiftUI conventions and will keep this consistent with the rest of the app.

- [ ] **Step 2: Rewrite the view to render a still pose**

Replace the entire contents of `Sources/OpenIslandApp/Views/CompanionPillView.swift`:

```swift
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

    var body: some View {
        Image(nsImage: CompanionArt.images[pose] ?? CompanionArt.fallback)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size * 0.875, height: size)
            .accessibilityLabel(Text("Companion"))
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
```

- [ ] **Step 3: Update the two call sites in V6NotchContent.swift**

Replace the `showsCompanion` branch in `externalBody`:

```swift
                if showsCompanion {
                    CompanionPillView(pose: companionPose, size: 24)
                        .frame(width: glyphW, height: 24)
                } else {
                    UnifiedBars(mode: mode, size: 24)
                        .frame(width: glyphW, height: 24)
                }
```

And in `macbookBody`:

```swift
                if showsCompanion {
                    CompanionPillView(pose: companionPose, size: 24)
                        .frame(width: 24, height: 24)
                } else {
                    UnifiedBars(mode: mode, size: 24)
                        .frame(width: 24, height: 24)
                }
```

Then add the property immediately after `showsCompanion` (currently line 228):

```swift
    /// The companion's pose. Ignored when `showsCompanion` is false.
    var companionPose: CompanionPose = .sleeping
```

- [ ] **Step 4: Supply the pose from the real pill**

In `Sources/OpenIslandApp/Views/IslandPanelView.swift`, change the `V6ClosedPill(...)` call so the final two arguments read:

```swift
            showsCompanion: model.showCompanion,
            companionPose: model.companionPose
```

- [ ] **Step 5: Build and confirm zero warnings**

Run: `swift build 2>&1 | grep -E "warning:|error:|Build complete"`
Expected: `Build complete!` and no warning or error lines. This project uses Swift 6 strict concurrency; a warning here is a defect, not noise.

- [ ] **Step 6: Run the full test suite**

Run: `swift test 2>&1 | grep "Test run with"`
Expected: `329 tests` (plus your 6 new ones) with **5 issues**. Those 5 failures are pre-existing on this branch — verified by stashing all changes and re-running. They are in `AppModelSessionListTests` and `AgentsGridRightSlotTests` and are unrelated to the companion. If you see more than 5, you broke something.

- [ ] **Step 7: Commit**

```bash
git add Sources/OpenIslandApp/Views/CompanionPillView.swift Sources/OpenIslandApp/Views/V6NotchContent.swift Sources/OpenIslandApp/Views/IslandPanelView.swift
git commit -m "feat: render the companion as a still pose per session state

Removes the continuous wag loop. Peripheral attention is captured by motion
onset involuntarily, so a loop running all day spends the developer's
attention for no information."
```

---

## Task 4: The hello-wag

Rare, small, unprompted motion at **non-periodic** intervals. This is what separates a status icon from an animal: a thing that moves only when poked is a control; a thing that sometimes moves for no reason is a creature.

The interval must not be detectable as a period. `TimelineView(.periodic(...))` is therefore wrong; a custom schedule with randomised gaps is required.

**Files:**
- Modify: `Sources/OpenIslandApp/Views/CompanionPillView.swift`

- [ ] **Step 1: Add the arrhythmic schedule**

Add to `CompanionPillView.swift`, above the view:

```swift
/// Emits at randomised intervals so the companion's unprompted motion has no
/// detectable period. A single idle loop becomes consciously noticeable at
/// roughly ninety seconds, and this view is on screen for eight hours.
struct ArrhythmicSchedule: TimelineSchedule {
    var range: ClosedRange<TimeInterval>

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        var next = startDate
        var generator = SystemRandomNumberGenerator()
        return AnyIterator {
            next = next.addingTimeInterval(TimeInterval.random(in: range, using: &generator))
            return next
        }
    }
}
```

- [ ] **Step 2: Add the wag to the view**

Replace the `body` of `CompanionPillView` with:

```swift
    /// How far the whole body tips during a hello-wag. Small on purpose: the
    /// point is a sign of life, not a performance.
    private static let wagDegrees: Double = 3.5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                still
            } else {
                TimelineView(ArrhythmicSchedule(range: 45...180)) { context in
                    still
                        .rotationEffect(.degrees(wagAngle(at: context.date)), anchor: .bottom)
                        .animation(.easeInOut(duration: 0.45), value: context.date)
                }
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
```

`still` deliberately carries no `.frame` or `.accessibilityLabel` — both moved up to
the `Group` so they apply identically on both branches. The Task 3 version of `body`
is fully replaced by the above; nothing from it survives.

- [ ] **Step 3: Invoke the swift-concurrency-pro skill**

Run the `swift-concurrency-pro` skill against `CompanionPillView.swift`. `SystemRandomNumberGenerator` inside a `TimelineSchedule` iterator is the kind of construct Swift 6 strict concurrency has opinions about. Fix anything it raises.

- [ ] **Step 4: Make the reduce-motion decision testable**

The spec requires asserting that no animation is scheduled under reduce-motion.
A SwiftUI `@Environment` value cannot be driven from a unit test, so extract the
decision into a pure function that can.

Add to `Sources/OpenIslandApp/CompanionPose.swift`:

```swift
/// Motion policy, separated from the view so it can be tested without SwiftUI.
enum CompanionMotion {
    /// Reduce-motion is honoured unconditionally -- it is an accessibility
    /// setting, not a preference to weigh against aesthetics.
    static func shouldAnimate(reduceMotion: Bool) -> Bool { !reduceMotion }
}
```

In `CompanionPillView`, replace both `reduceMotion` checks with
`CompanionMotion.shouldAnimate(reduceMotion: reduceMotion)`:

```swift
            if CompanionMotion.shouldAnimate(reduceMotion: reduceMotion) {
```

and in the pose-change handler added in Task 5:

```swift
            guard CompanionMotion.shouldAnimate(reduceMotion: reduceMotion) else { return }
```

Append to `Tests/OpenIslandAppTests/CompanionPoseTests.swift`, inside the struct:

```swift
    @Test
    func reduceMotionSuppressesAllAnimation() {
        #expect(CompanionMotion.shouldAnimate(reduceMotion: true) == false)
        #expect(CompanionMotion.shouldAnimate(reduceMotion: false) == true)
    }
```

Run: `swift test --filter CompanionPoseTests`
Expected: 7 tests pass.

- [ ] **Step 5: Build and confirm zero warnings**

Run: `swift build 2>&1 | grep -E "warning:|error:|Build complete"`
Expected: `Build complete!` with no warnings.

- [ ] **Step 6: Commit**

```bash
git add Sources/OpenIslandApp/Views/CompanionPillView.swift Sources/OpenIslandApp/CompanionPose.swift Tests/OpenIslandAppTests/CompanionPoseTests.swift
git commit -m "feat: give the companion rare unprompted motion

Arrhythmic so it has no detectable period, and small enough to cost almost
no attention. A thing that moves only when poked is a control; a thing that
sometimes moves for no reason is a creature."
```

---

## Task 5: Transition beats

A brief animation when the pose changes, with amplitude scaled to how much the change deserves a look: attending > alert > sleeping.

**Files:**
- Modify: `Sources/OpenIslandApp/Views/CompanionPillView.swift`

- [ ] **Step 1: Add per-pose entry amplitude to the enum**

In `Sources/OpenIslandApp/CompanionPose.swift`, add inside the enum:

```swift
    /// How much a transition INTO this pose should be noticed. Needing the
    /// developer earns the largest movement; settling down earns the least.
    var entryScale: Double {
        switch self {
        case .attending: 1.18
        case .alert:     1.08
        case .sleeping:  1.0
        }
    }
```

- [ ] **Step 2: Animate pose changes**

In `CompanionPillView`, add one new stored property alongside `reduceMotion`:

```swift
    @State private var entryPulse = false
```

Then append these two modifiers to the `Group` in `body`, immediately after the
existing `.accessibilityLabel(Text("Companion"))` line:

```swift
        .scaleEffect(entryPulse ? pose.entryScale : 1.0, anchor: .bottom)
        .onChange(of: pose) { _, _ in
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) { entryPulse = true }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.8).delay(0.16)) { entryPulse = false }
        }
```

- [ ] **Step 3: Build and confirm zero warnings**

Run: `swift build 2>&1 | grep -E "warning:|error:|Build complete"`
Expected: `Build complete!` with no warnings.

- [ ] **Step 4: Verify reduce-motion suppresses both motions**

Run: `defaults write com.apple.universalaccess reduceMotion -bool true`
Then launch and confirm the companion never moves. Then restore:
`defaults write com.apple.universalaccess reduceMotion -bool false`

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenIslandApp/CompanionPose.swift Sources/OpenIslandApp/Views/CompanionPillView.swift
git commit -m "feat: animate the companion briefly when its pose changes"
```

---

## Task 6: Verify legibility at true size

The spec flags this as a risk: `d4-curl` already failed this test in the dark colourway, reading as an amorphous blob with no species information. `w2-drape` is being used as the sleeping pose and has not been checked.

**Files:**
- No source changes. This is a measurement.

- [ ] **Step 1: Render all three poses at 28×32 on the pill ground**

```bash
/usr/bin/python3 - <<'PY'
from PIL import Image
OUT = "Sources/OpenIslandApp/Resources/Companion"
PILL, MAG = (28, 32), 9
cells = []
for pose in ("sleeping", "alert", "attending"):
    im = Image.open(f"{OUT}/companion-{pose}.png").convert("RGBA")
    im.thumbnail(PILL, Image.LANCZOS)
    plate = Image.new("RGBA", PILL, (13, 13, 15, 255))
    plate.alpha_composite(im, ((PILL[0] - im.width) // 2, (PILL[1] - im.height) // 2))
    cells.append(plate.resize((PILL[0] * MAG, PILL[1] * MAG), Image.NEAREST))
g, w, h = 14, PILL[0] * MAG, PILL[1] * MAG
sheet = Image.new("RGB", (3 * w + 4 * g, h + 2 * g), (38, 38, 38))
for i, c in enumerate(cells):
    sheet.paste(c.convert("RGB"), (g + i * (w + g), g))
sheet.save("/tmp/companion-legibility.png")
print("wrote /tmp/companion-legibility.png -- order: sleeping, alert, attending")
PY
```

- [ ] **Step 2: Look at it and judge**

Open `/tmp/companion-legibility.png`. For each of the three, answer: **can you tell it is a dog?** Ears, legs and tail should read.

- [ ] **Step 3: Record the outcome**

If all three read, note it in the commit message and continue.

If one fails — most likely `sleeping`, since a sprawled shape at 28px is close to the failure mode `d4-curl` hit — **stop and report it**. Do not compensate by scaling the art up or picking a pose that reads but does not mean the right thing. A pose that cannot be distinguished is a missing asset, and the honest fix is to generate a proper curled pose in the cream colourway.

- [ ] **Step 4: Commit the finding**

```bash
git commit --allow-empty -m "test: verify companion poses read at 28x32

<record which poses read and which did not>"
```

---

## Task 7: Measure the event-to-render latency

The spec carries a 140 ms budget: past roughly that delay a reaction stops reading as a response and starts reading as playback, which forfeits the contingency that makes the companion feel alive. This task **measures**; it does not optimise. If the budget is missed, that is a finding to report.

**Files:**
- Modify: `Sources/OpenIslandApp/AppModel.swift` (temporary instrumentation, removed in step 4)

- [ ] **Step 1: Add temporary instrumentation**

In `AppModel.swift`, inside `companionPose`, add as the first line of the getter:

```swift
        let poseClock = CFAbsoluteTimeGetCurrent()
        defer {
            let ms = (CFAbsoluteTimeGetCurrent() - poseClock) * 1000
            if ms > 1 { print("[companion] pose derivation \(String(format: "%.2f", ms))ms") }
        }
```

- [ ] **Step 2: Exercise it against real sessions**

Run: `zsh scripts/harness.sh smoke`

Note: if `scripts/launch-dev-app.sh` is used instead, it runs `generate_brand_icons.py`, which needs PIL. Homebrew's `python3` lacks it. Prefix with a shim: `mkdir -p /tmp/pyshim && ln -sf /usr/bin/python3 /tmp/pyshim/python3` then run with `PATH=/tmp/pyshim:$PATH`. That script also **rewrites 28 tracked brand icon files** as a side effect — `git checkout -- Assets/Brand` afterwards.

- [ ] **Step 3: Record the numbers**

The derivation itself should be well under 1 ms — it is two array scans. The real risk is upstream, in bridge → `AppModel` propagation. Record what you observe.

- [ ] **Step 4: Remove the instrumentation and commit the finding**

```bash
git checkout -- Sources/OpenIslandApp/AppModel.swift
git commit --allow-empty -m "test: measure companion pose derivation latency

<record the measured figures and whether the 140ms budget holds>"
```

---

## Task 8: Review pass

- [ ] **Step 1: Invoke the swiftui-pro skill**

Run `swiftui-pro` against `CompanionPillView.swift`, `CompanionPose.swift` and the `V6NotchContent.swift` changes. Fix what it raises.

- [ ] **Step 2: Invoke the swift-testing-pro skill**

Run `swift-testing-pro` against `CompanionPoseTests.swift`. Fix what it raises.

- [ ] **Step 3: Final build and test**

Run: `swift build 2>&1 | grep -E "warning:|error:|Build complete"`
Expected: `Build complete!`, no warnings.

Run: `swift test 2>&1 | grep "Test run with"`
Expected: 5 issues, all pre-existing.

- [ ] **Step 4: Commit any review fixes**

```bash
git add -A
git commit -m "refactor: apply SwiftUI and testing review feedback"
```

---

## Hard rules — how each is satisfied

The spec's eight hard rules are constraints, not tasks. Recording where each is met
so a reviewer can check them rather than trust them:

| Rule | Where it holds |
|---|---|
| Never speaks | No text is rendered anywhere in `CompanionPillView`. |
| Never blocks | The view is inert inside a pill that is already the click target. |
| Never infers | `companionPose` reads `SessionPhase` only — ground truth off the bridge. |
| Never editorialises about the user | The derivation has no input other than session phase. No timers, no absence tracking. |
| Never degrades | Pose is computed fresh every render; there is no stored state to decay. |
| Neutral on failure | Satisfied by construction — there is no sad or sympathetic pose to enter. A completed session settles to `sleeping` regardless of outcome. |
| Convenient seams | `showCompanion` toggle already ships; reduce-motion is honoured in Task 4 step 4. |
| Escalation is silent | An unanswered approval holds `.attending` indefinitely with no growth — the pose does not change again, so no further transition fires. |

---

## Out of scope

Explicitly not in this plan, per the spec:

- **Gaze.** The current art has fixed eyes. Gaze needs a separable eye layer and must aim within 30° of the true target to register at all — approximate gaze does not land. Phase two.
- **The 44-frame entrance.** Needs rigid-body plus trajectory decomposition rather than a static base.
- **Gifts, trash, collection, currency.** A separate product direction.
- **Naming the companion.** A product decision, not an engineering one.
