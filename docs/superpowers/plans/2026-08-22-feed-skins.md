# Feed Skins & Collapsible Turns Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the companion feed toward Cat On Chair's paper texture and rounded lettering across three user-switchable grounds, and collapse each turn's tool calls behind an expandable summary row.

**Architecture:** Colour stops being scattered statics and becomes a resolved `FeedTheme` value built from measurable `FeedInk` primitives, so every contrast bar in the spec is asserted by a test rather than written in a comment. `IslandTheme` is a `CaseIterable` enum — `allCases` is the catalogue an unlock layer can filter later. Collapse state is a dictionary of explicit user choices defaulting to "expanded iff newest", held on the view so it survives the two-second transcript reload.

**Tech Stack:** Swift 6.2, SwiftUI, Swift Testing, macOS 14+. No new dependencies, no bundled assets.

**Spec:** `docs/superpowers/specs/2026-08-22-feed-skins-design.md`
**Design canvas:** https://claude.ai/code/artifact/32a9b7d2-e55f-467a-9e85-39c19fa5a636

---

## Before you start

Read the handoff's environment traps: `docs/superpowers/specs/2026-08-22-companion-feed-handoff.md` §6. The three that will cost you an hour each:

1. **`pwd` before every build.** The shell cwd has silently reverted to the main repo mid-session. You must be in `.claude/worktrees/feat+companion-pill`.
2. **`git checkout -- Assets/Brand` before every commit.** `scripts/launch-dev-app.sh` rewrites 28 tracked icon files as a side effect of launching.
3. **Move the pointer off the notch before `swift test`.** `OverlayUICoordinator.updateNotificationAutoCollapse` reads `NSEvent.mouseLocation`; with the pointer inside the expanded island it schedules no timer and `completionNotificationHoverCancelsPendingTimedCollapse` fails. Run `cliclick m:400,900` first.

**Baseline:** `swift test` reports **5 issues**. That is correct and pre-existing (`AppModelSessionListTests`, `AgentsGridRightSlotTests`). More than five means you broke something.

### The screenshot loop — run it where the plan says to

One-time setup:

```bash
mkdir -p /tmp/pyshim
ln -sf /usr/bin/python3 /tmp/pyshim/python3
defaults write app.openisland.dev app.showCompanion -bool true
```

Write `run-dev.sh` in the worktree root (it is gitignored at the end of this plan; do not commit it):

```bash
#!/bin/zsh
export PATH="/tmp/pyshim:$PATH"
exec zsh scripts/launch-dev-app.sh
```

Each capture — **run these as separate commands, the worktree refuses compound shells**:

```bash
pkill -f "Open Island Dev"
zsh run-dev.sh >/tmp/rundev.log 2>&1
cliclick m:700,300 w:30000 m:757,4 w:800 m:757,14 w:800 m:757,24 w:1500
screencapture -x /tmp/shot.png
magick /tmp/shot.png -crop 1010x1000+1010+0 +repage /tmp/shot-crop.png
```

Then **Read `/tmp/shot-crop.png` and look at it.** A claim that something renders correctly without a picture of it rendering correctly is not accepted — the handoff records three such claims that were wrong.

If the capture shows the closed pill (small dog and `×N`), the hover did not take. Park the pointer with `cliclick m:200,700`, wait, and retry. Session discovery needs ~20–30s after launch or you get "Nothing running".

---

## File Structure

| File | Responsibility |
|---|---|
| `Sources/OpenIslandApp/Views/FeedTheme.swift` | **new** — `FeedInk` colour primitive with contrast maths, `FeedTheme` token set, `FeedTheme.resolve`, `FeedGrain` noise tile |
| `Sources/OpenIslandApp/AppModelTypes.swift` | `IslandTheme` enum |
| `Sources/OpenIslandApp/AppModel.swift` | `islandTheme` property, defaults key, register, load |
| `Sources/OpenIslandApp/Views/AgentFeedView.swift` | consume the theme; grain, rounded face, drawn contours, collapse |
| `Sources/OpenIslandApp/Views/IslandPanelView.swift` | pass the resolved theme in |
| `Sources/OpenIslandApp/Views/AppearanceSettingsPane.swift` | theme picker section |
| `Sources/OpenIslandApp/Resources/{en,zh-Hans,zh-Hant}.lproj/Localizable.strings` | theme names |
| `Tests/OpenIslandAppTests/FeedThemeTests.swift` | **new** — contrast bars asserted, token resolution |
| `Tests/OpenIslandAppTests/FeedTurnsTests.swift` | extend — summary text, diff totals, expansion defaulting |

`FeedTheme.swift` is deliberately separate from `AgentFeedView.swift`. The view file is already ~360 lines and the theme is pure, testable, MainActor-free logic — the handoff's §6 records that a MainActor-isolated helper called from a plain test crashes the runner with signal 5, which looks like a build failure. Keep pure things out of the view.

---

## Task 1: `FeedInk` — a colour you can measure

**Files:**
- Create: `Sources/OpenIslandApp/Views/FeedTheme.swift`
- Test: `Tests/OpenIslandAppTests/FeedThemeTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/OpenIslandAppTests/FeedThemeTests.swift`:

```swift
import Foundation
import Testing
@testable import OpenIslandApp

/// Colour in this feature is measured, not asserted. The handoff shipped a
/// `faint` tier at 2.74:1 -- below AA for small text -- because the status
/// tints were measured and the alpha tiers beneath them were not. These tests
/// are what stop that recurring.
struct FeedInkTests {
    @Test
    func parsesHexIntoUnitComponents() {
        let ink = FeedInk(hex: 0xef_e7_d6)
        #expect(abs(ink.red - 0xef / 255.0) < 0.0001)
        #expect(abs(ink.green - 0xe7 / 255.0) < 0.0001)
        #expect(abs(ink.blue - 0xd6 / 255.0) < 0.0001)
    }

    /// Black on white is the defined maximum for WCAG 2.x.
    @Test
    func blackOnWhiteIsTwentyOneToOne() {
        let ratio = FeedInk(hex: 0x00_00_00).contrast(against: FeedInk(hex: 0xff_ff_ff))
        #expect(abs(ratio - 21.0) < 0.01)
    }

    @Test
    func contrastIsSymmetric() {
        let a = FeedInk(hex: 0x12_11_0f)
        let b = FeedInk(hex: 0xf1_ea_d9)
        #expect(abs(a.contrast(against: b) - b.contrast(against: a)) < 0.0001)
    }

    /// The tiers are composited before measuring, so the number is the colour
    /// that actually renders -- not the colour before the ground shows through.
    @Test
    func blendCompositesTowardTheGround() {
        let paper = FeedInk(hex: 0xf1_ea_d9)
        let ink = FeedInk(hex: 0x12_11_0f)
        #expect(FeedInk.blend(paper, over: ink, alpha: 1.0) == paper)
        #expect(FeedInk.blend(paper, over: ink, alpha: 0.0) == ink)

        let half = FeedInk.blend(paper, over: ink, alpha: 0.5)
        #expect(half.red > ink.red && half.red < paper.red)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
swift test --filter FeedInkTests 2>&1 | tail -20
```

Expected: build failure, `cannot find 'FeedInk' in scope`.

- [ ] **Step 3: Write `FeedInk`**

Create `Sources/OpenIslandApp/Views/FeedTheme.swift`:

```swift
import SwiftUI
import OpenIslandCore

/// A colour the feed can measure.
///
/// The feed's contrast bars are enforced by tests rather than written in
/// comments, and that needs a colour type that knows its own luminance.
/// `SwiftUI.Color` does not expose components portably, so the feed's palette
/// is authored in this type and converted to `Color` at the point of use.
///
/// Pure and outside the view on purpose: a MainActor-isolated helper called
/// from a plain test crashes the runner with signal 5.
struct FeedInk: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255.0,
            green: Double((hex >> 8) & 0xff) / 255.0,
            blue: Double(hex & 0xff) / 255.0
        )
    }

    var color: Color { Color(red: red, green: green, blue: blue) }

    /// Flattens `foreground` at `alpha` onto `ground`, so contrast is measured
    /// on the colour that actually reaches the screen.
    static func blend(_ foreground: FeedInk, over ground: FeedInk, alpha: Double) -> FeedInk {
        FeedInk(
            red: foreground.red * alpha + ground.red * (1 - alpha),
            green: foreground.green * alpha + ground.green * (1 - alpha),
            blue: foreground.blue * alpha + ground.blue * (1 - alpha)
        )
    }

    /// WCAG 2.x relative luminance, sRGB.
    var luminance: Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    func contrast(against other: FeedInk) -> Double {
        let a = luminance
        let b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
```

- [ ] **Step 4: Run the tests and watch them pass**

```bash
swift test --filter FeedInkTests 2>&1 | grep "Test run with"
```

Expected: `Test run with 4 tests ... passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenIslandApp/Views/FeedTheme.swift Tests/OpenIslandAppTests/FeedThemeTests.swift
git commit -m "feat: add a colour primitive the feed can measure"
```

---

## Task 2: `FeedTheme` tokens, with the contrast bars as tests

**Files:**
- Modify: `Sources/OpenIslandApp/Views/FeedTheme.swift`
- Test: `Tests/OpenIslandAppTests/FeedThemeTests.swift`

Every number below comes from spec §7.5 and was computed, not chosen.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/OpenIslandAppTests/FeedThemeTests.swift`:

```swift
import OpenIslandCore

/// Spec §7.5. Every text token on every skin clears WCAG AA for small text;
/// the status dot is a non-text graphic and clears 3:1. If a future tweak
/// drops one below its bar, this fails instead of shipping.
struct FeedThemeContrastTests {
    private let textBar = 4.5
    private let graphicBar = 3.0

    @Test(arguments: IslandTheme.allCases)
    func everyTextTokenClearsAA(theme: IslandTheme) {
        let t = FeedTheme.resolve(theme)
        let reading = t.surface ?? t.ground

        #expect(t.text.contrast(against: reading) >= textBar)
        #expect(t.dim.contrast(against: reading) >= textBar)
        #expect(t.faint.contrast(against: reading) >= textBar)
    }

    @Test(arguments: IslandTheme.allCases)
    func everyStatusTintClearsAA(theme: IslandTheme) {
        let t = FeedTheme.resolve(theme)
        let reading = t.surface ?? t.ground

        for phase in SessionPhase.allCases {
            let tint = t.ink(for: phase)
            #expect(
                tint.contrast(against: reading) >= textBar,
                "\(theme.rawValue)/\(phase) = \(tint.contrast(against: reading))"
            )
        }
    }

    /// The header's status dot sits on the panel ground, not the reading
    /// surface -- on Cream card those are different colours.
    @Test(arguments: IslandTheme.allCases)
    func statusDotClearsGraphicBarOnTheGround(theme: IslandTheme) {
        let t = FeedTheme.resolve(theme)
        for phase in SessionPhase.allCases {
            #expect(t.headerInk(for: phase).contrast(against: t.ground) >= graphicBar)
        }
    }

    /// Regression guard for the defect this round fixes: the shipped `faint`
    /// tier measured 2.74:1.
    @Test
    func faintTierIsNoLongerBelowAA() {
        let t = FeedTheme.resolve(.inkPaper)
        #expect(t.faint.contrast(against: t.ground) > 4.5)
    }
}

struct FeedThemeResolutionTests {
    /// Cream card is the only skin with an inner reading surface. The other two
    /// read directly on their ground.
    @Test
    func onlyCreamCardHasASeparateSurface() {
        #expect(FeedTheme.resolve(.inkPaper).surface == nil)
        #expect(FeedTheme.resolve(.fullCream).surface == nil)
        #expect(FeedTheme.resolve(.creamCard).surface != nil)
    }

    @Test
    func inkSkinsKeepTheExistingStatusTints() {
        let t = FeedTheme.resolve(.inkPaper)
        #expect(t.ink(for: .running) == FeedInk(hex: 0x6e_a7_ff))
    }

    @Test
    func paperSkinsUseTheirOwnTints() {
        let t = FeedTheme.resolve(.fullCream)
        #expect(t.ink(for: .running) != FeedInk(hex: 0x6e_a7_ff))
    }
}
```

- [ ] **Step 2: Run and watch it fail**

```bash
swift test --filter FeedTheme 2>&1 | tail -20
```

Expected: `cannot find 'FeedTheme' in scope` and `cannot find 'IslandTheme' in scope`.

- [ ] **Step 3: Add `IslandTheme` to `AppModelTypes.swift`**

Append to `Sources/OpenIslandApp/AppModelTypes.swift`:

```swift
/// What the island is made of.
///
/// `CaseIterable` is load-bearing rather than incidental: `allCases` *is* the
/// theme catalogue, so a future unlock layer filters this sequence before the
/// picker renders it and touches nothing in the render path.
enum IslandTheme: String, CaseIterable, Identifiable, Sendable {
    case inkPaper
    case creamCard
    case fullCream

    var id: String { rawValue }

    /// Localisation key for the picker. Matches `settings.general.showCompanion`'s pattern.
    var displayNameKey: String { "settings.appearance.theme.\(rawValue)" }
}
```

- [ ] **Step 4: Add `FeedTheme` to `FeedTheme.swift`**

Append to `Sources/OpenIslandApp/Views/FeedTheme.swift`:

```swift
/// The feed's resolved colour, one value per skin.
///
/// Replaces the old `FeedPalette` statics. `IslandDesignPalette` is deliberately
/// NOT modified -- it is used across the whole app, and paper-ground tints are
/// a feed concern.
struct FeedTheme: Equatable, Sendable {
    /// The panel's own background.
    let ground: FeedInk
    /// Inner reading card. `nil` when the ground IS the reading surface.
    let surface: FeedInk?
    let text: FeedInk
    let dim: FeedInk
    let faint: FeedInk
    let hairline: FeedInk

    let approval: FeedInk
    let answer: FeedInk
    let running: FeedInk
    let completed: FeedInk

    /// Status colour for text sitting on the reading surface.
    func ink(for phase: SessionPhase) -> FeedInk {
        switch phase {
        case .waitingForApproval: approval
        case .waitingForAnswer: answer
        case .running: running
        case .completed: completed
        }
    }

    /// Status colour for the header, which sits on `ground` even when the body
    /// has its own surface. On Cream card those are different colours, so the
    /// header keeps the ink tints while the body uses the paper ones.
    func headerInk(for phase: SessionPhase) -> FeedInk {
        surface == nil ? ink(for: phase) : Self.inkTints.ink(for: phase)
    }

    func color(for phase: SessionPhase) -> Color { ink(for: phase).color }
    func headerColor(for phase: SessionPhase) -> Color { headerInk(for: phase).color }

    // MARK: Resolution

    // Grounds. Ink is warmed from #0d0d0f so it reads as paper rather than
    // glass; that costs about 3% contrast and everything still clears (§7.5).
    private static let inkGround = FeedInk(hex: 0x12_11_0f)
    private static let creamGround = FeedInk(hex: 0xef_e7_d6)
    private static let paperText = FeedInk(hex: 0xf1_ea_d9)
    private static let creamText = FeedInk(hex: 0x24_1f_1a)

    private struct StatusSet {
        let approval: FeedInk
        let answer: FeedInk
        let running: FeedInk
        let completed: FeedInk

        func ink(for phase: SessionPhase) -> FeedInk {
            switch phase {
            case .waitingForApproval: approval
            case .waitingForAnswer: answer
            case .running: running
            case .completed: completed
            }
        }
    }

    /// Unchanged from `IslandDesignPalette.Status` -- these are the measured
    /// ink tints the whole app already uses.
    private static let inkTints = StatusSet(
        approval: FeedInk(hex: 0xf4_a4_a4),
        answer: FeedInk(hex: 0xff_d5_8a),
        running: FeedInk(hex: 0x6e_a7_ff),
        completed: FeedInk(hex: 0x6f_b9_82)
    )

    /// Hand-picked from Cat On Chair's own palette. An automated search that
    /// maximises lightness subject to 4.5:1 returns #d10f0f and #005ded --
    /// fully saturated, and the opposite of the reference's muted world.
    private static let paperTints = StatusSet(
        approval: FeedInk(hex: 0xa8_43_2f),
        answer: FeedInk(hex: 0x8a_5a_12),
        running: FeedInk(hex: 0x24_60_8f),
        completed: FeedInk(hex: 0x3d_6b_3d)
    )

    static func resolve(_ theme: IslandTheme) -> FeedTheme {
        switch theme {
        case .inkPaper:
            onInk(ground: inkGround, surface: nil)
        case .creamCard:
            onPaper(ground: inkGround, surface: creamGround)
        case .fullCream:
            onPaper(ground: creamGround, surface: nil)
        }
    }

    private static func onInk(ground: FeedInk, surface: FeedInk?) -> FeedTheme {
        FeedTheme(
            ground: ground,
            surface: surface,
            text: .blend(paperText, over: ground, alpha: 0.94),
            dim: .blend(paperText, over: ground, alpha: 0.66),
            faint: .blend(paperText, over: ground, alpha: 0.50),
            hairline: .blend(paperText, over: ground, alpha: 0.14),
            approval: inkTints.approval,
            answer: inkTints.answer,
            running: inkTints.running,
            completed: inkTints.completed
        )
    }

    private static func onPaper(ground: FeedInk, surface: FeedInk?) -> FeedTheme {
        let reading = surface ?? ground
        return FeedTheme(
            ground: ground,
            surface: surface,
            text: creamText,
            dim: .blend(creamText, over: reading, alpha: 0.80),
            faint: .blend(creamText, over: reading, alpha: 0.66),
            hairline: .blend(creamText, over: reading, alpha: 0.20),
            approval: paperTints.approval,
            answer: paperTints.answer,
            running: paperTints.running,
            completed: paperTints.completed
        )
    }
}
```

- [ ] **Step 5: Confirm `SessionPhase` is iterable**

```bash
grep -n "public enum SessionPhase" Sources/OpenIslandCore/AgentSession.swift
```

Expected: `public enum SessionPhase: String, Codable, Sendable, CaseIterable`. It already conforms, so `@Test(arguments:)` over `SessionPhase.allCases` compiles as written — no change needed. This step exists only so you do not go looking when the parameterised tests reference it.

- [ ] **Step 6: Run the tests**

```bash
cliclick m:400,900
swift test --filter FeedTheme 2>&1 | grep "Test run with"
```

Expected: all pass. If a contrast expectation fails, the failure message names the skin, phase and measured ratio — **retune the tint, do not lower the bar.**

- [ ] **Step 7: Commit**

```bash
git add Sources/OpenIslandApp/Views/FeedTheme.swift Sources/OpenIslandApp/AppModelTypes.swift Tests/OpenIslandAppTests/FeedThemeTests.swift
git commit -m "feat: resolve feed colour per skin, with the contrast bars as tests"
```

---

## Task 3: Persist the theme preference

**Files:**
- Modify: `Sources/OpenIslandApp/AppModel.swift` (near `showCompanionDefaultsKey` at line 24, the property block around line 257, the defaults registration around line 606, and the load around line 612)
- Test: `Tests/OpenIslandAppTests/FeedThemeTests.swift`

Spec §4.1: this is a **global** preference, not per-display-profile. A theme answers "what is the island made of", not "how does it lay itself out on this screen".

- [ ] **Step 1: Write the failing test**

Append to `Tests/OpenIslandAppTests/FeedThemeTests.swift`:

```swift
@MainActor
struct IslandThemePreferenceTests {
    @Test
    func defaultsToInkPaper() {
        UserDefaults.standard.removeObject(forKey: "app.islandTheme")
        #expect(AppModel().islandTheme == .inkPaper)
    }

    @Test
    func roundTripsThroughUserDefaults() {
        let model = AppModel()
        model.islandTheme = .creamCard
        #expect(UserDefaults.standard.string(forKey: "app.islandTheme") == "creamCard")

        UserDefaults.standard.removeObject(forKey: "app.islandTheme")
    }

    /// An unknown or corrupted value must not strand the panel on a skin that
    /// does not exist.
    @Test
    func unknownStoredValueFallsBackToTheDefault() {
        UserDefaults.standard.set("chartreuse", forKey: "app.islandTheme")
        #expect(AppModel().islandTheme == .inkPaper)

        UserDefaults.standard.removeObject(forKey: "app.islandTheme")
    }
}
```

- [ ] **Step 2: Run and watch it fail**

```bash
swift test --filter IslandThemePreferenceTests 2>&1 | tail -20
```

Expected: `value of type 'AppModel' has no member 'islandTheme'`.

- [ ] **Step 3: Add the key**

In `Sources/OpenIslandApp/AppModel.swift`, beside `showCompanionDefaultsKey` (line 24):

```swift
    private static let islandThemeDefaultsKey = "app.islandTheme"
```

- [ ] **Step 4: Add the property**

Directly after the `showCompanion` property block (around line 257–262), matching its shape exactly:

```swift
    /// What the island is made of. Global rather than per-display-profile:
    /// every member of `IslandAppearancePreferences` answers "how should this
    /// screen lay out", while a theme answers "what is this made of".
    var islandTheme: IslandTheme = .inkPaper {
        didSet {
            guard hasFinishedInit, islandTheme != oldValue else { return }
            UserDefaults.standard.set(islandTheme.rawValue, forKey: Self.islandThemeDefaultsKey)
        }
    }
```

- [ ] **Step 5: Register the default and load it**

In the defaults dictionary (around line 606, beside `Self.showCompanionDefaultsKey: false`):

```swift
            Self.islandThemeDefaultsKey: IslandTheme.inkPaper.rawValue,
```

Beside the `showCompanion` load (around line 612):

```swift
        islandTheme = UserDefaults.standard.string(forKey: Self.islandThemeDefaultsKey)
            .flatMap(IslandTheme.init(rawValue:)) ?? .inkPaper
```

- [ ] **Step 6: Run the tests**

```bash
cliclick m:400,900
swift test --filter IslandThemePreferenceTests 2>&1 | grep "Test run with"
```

Expected: 3 tests pass.

- [ ] **Step 7: Full suite, then commit**

```bash
cliclick m:400,900
swift test 2>&1 | grep "Test run with"
```

Expected: **5 issues**, no more.

```bash
git add Sources/OpenIslandApp/AppModel.swift Tests/OpenIslandAppTests/FeedThemeTests.swift
git commit -m "feat: persist the island theme preference"
```

---

## Task 4: Feed consumes the theme — ink skin only

No visual change is intended yet beyond the warmer ground and the fixed `faint` tier. This task swaps the plumbing so later tasks are small.

**Files:**
- Modify: `Sources/OpenIslandApp/Views/AgentFeedView.swift`
- Modify: `Sources/OpenIslandApp/Views/IslandPanelView.swift:427-432`

- [ ] **Step 1: Add the property to `AgentFeedView`**

Beside `sideInset`:

```swift
    /// Resolved once by the panel and passed down, so the whole feed renders
    /// from one value rather than reaching for globals.
    let theme: FeedTheme
```

- [ ] **Step 2: Replace every `FeedPalette` and status reference**

Delete the `enum FeedPalette` block at the bottom of `AgentFeedView.swift` entirely. Then replace throughout the file:

| Was | Becomes |
|---|---|
| `FeedPalette.text` | `theme.text.color` |
| `FeedPalette.dim` | `theme.dim.color` |
| `FeedPalette.faint` | `theme.faint.color` |
| `FeedPalette.hairline` | `theme.hairline.color` |
| `FeedPalette.text.opacity(0.92)` | `theme.text.color` |
| `IslandDesignPalette.Status.tint(for: session.phase)` | `theme.headerColor(for: session.phase)` |
| `IslandDesignPalette.Status.completed` | `theme.color(for: .completed)` |
| `IslandDesignPalette.Status.waitingForApproval` | `theme.color(for: .waitingForApproval)` |
| `IslandDesignPalette.Status.waitingForAnswer` | `theme.color(for: .waitingForAnswer)` |
| `IslandDesignPalette.Status.running` | `theme.color(for: .running)` |
| `V6Palette.ink` (the `.background`) | `theme.ground.color` |

In `toolTint(_:)`, the `Read/Glob/Grep` case becomes `theme.dim.color` and the `Task/Agent` case keeps its literal — it is not a status colour. Change its signature to return `Color` as before.

- [ ] **Step 3: Pass it from the panel**

In `Sources/OpenIslandApp/Views/IslandPanelView.swift`, the `AgentFeedView` call:

```swift
                AgentFeedView(
                    session: focus,
                    others: model.islandListSessions.filter { $0.id != focus.id },
                    sideInset: sessionListSideInset,
                    theme: FeedTheme.resolve(model.islandTheme)
                )
```

- [ ] **Step 4: Build clean**

```bash
swift build 2>&1 | grep -E "error:|warning:"
```

Expected: **no output.** This project is Swift 6 strict concurrency; a warning is a defect.

- [ ] **Step 5: Screenshot and look**

Run the capture recipe from *Before you start*, then Read `/tmp/shot-crop.png`.

Check explicitly:
- The panel still renders (nothing went blank).
- Timestamps are **visibly more readable** than before — that is the `faint` fix, 2.74:1 → 4.66:1.
- The ground is very slightly warmer, not obviously different.

- [ ] **Step 6: Commit**

```bash
git checkout -- Assets/Brand
cliclick m:400,900
swift test 2>&1 | grep "Test run with"
git add Sources/OpenIslandApp/Views/AgentFeedView.swift Sources/OpenIslandApp/Views/IslandPanelView.swift
git commit -m "fix: render the feed from a resolved theme and lift faint above AA"
```

---

## Task 5: The grain

**Files:**
- Modify: `Sources/OpenIslandApp/Views/FeedTheme.swift`
- Modify: `Sources/OpenIslandApp/Views/AgentFeedView.swift`

- [ ] **Step 1: Add `FeedGrain`**

Append to `Sources/OpenIslandApp/Views/FeedTheme.swift`:

```swift
/// The paper grain, built once.
///
/// A 128x128 tile of value noise, generated into a `CGImage` at first use and
/// tiled across the surface. No asset ships and the result is deterministic --
/// a seeded generator, not `Double.random`, so the texture does not crawl
/// between renders.
///
/// MainActor-isolated because it is only ever used from views, and that keeps
/// the cached image out of Swift 6's global-mutable-state rules.
@MainActor
enum FeedGrain {
    static let tile: Image = Image(decorative: make(), scale: 1)

    private static let side = 128

    private static func make() -> CGImage {
        var seed: UInt64 = 0x5f3a_c91e
        func next() -> Double {
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            return Double(seed % 1000) / 1000.0
        }

        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let value = UInt8(120 + next() * 135)
            pixels[index] = value
            pixels[index + 1] = value
            pixels[index + 2] = value
            pixels[index + 3] = 255
        }

        let context = CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        return context!.makeImage()!
    }
}

extension View {
    /// Lays paper grain over a surface. Overlay blend keeps it a texture rather
    /// than a fog -- it darkens and lightens the ground instead of veiling it.
    func feedGrain(opacity: Double = 0.30) -> some View {
        overlay {
            FeedGrain.tile
                .resizable(resizingMode: .tile)
                .blendMode(.overlay)
                .opacity(opacity)
                .allowsHitTesting(false)
        }
    }
}
```

- [ ] **Step 2: Apply it**

In `AgentFeedView.body`, on the root `VStack`, after `.background(theme.ground.color)`:

```swift
        .background(theme.ground.color)
        .feedGrain()
```

- [ ] **Step 3: Build clean**

```bash
swift build 2>&1 | grep -E "error:|warning:"
```

Expected: no output. If `CGContext` init warns about `&pixels` escaping, restructure with `pixels.withUnsafeMutableBytes { }` and build the context inside the closure.

- [ ] **Step 4: Screenshot and look**

Capture, then Read the PNG. Check:
- The surface reads as **paper, not noise** — if it looks like TV static, drop the opacity to 0.20 and recapture.
- Text is not muddied. Grain must sit under legibility, not over it.

- [ ] **Step 5: Commit**

```bash
git checkout -- Assets/Brand
git add Sources/OpenIslandApp/Views/FeedTheme.swift Sources/OpenIslandApp/Views/AgentFeedView.swift
git commit -m "feat: lay paper grain over the feed surface"
```

---

## Task 6: The hand — rounded face, no rules, drawn contours

**Files:**
- Modify: `Sources/OpenIslandApp/Views/AgentFeedView.swift`

- [ ] **Step 1: Rounded display face**

Add `design: .rounded` to these fonts only. **Do not touch anything already carrying `design: .monospaced`** — the mono column is what makes the feed scannable.

| Element | New font |
|---|---|
| workspace name | `.system(size: 13, weight: .bold, design: .rounded)` |
| status word | `.system(size: 10, weight: .semibold, design: .rounded)` |
| `label(_:tint:)` tool name | `.system(size: 9, weight: .bold, design: .rounded)` |
| `tag(_:)` branch | `.system(size: 9, weight: .semibold, design: .rounded)` |
| empty-state title | `.system(size: 11.5, weight: .medium, design: .rounded)` |
| empty-state subtitle | `.system(size: 10, design: .rounded)` |
| footer "N others" | `.system(size: 10.5, weight: .semibold, design: .rounded)` |
| footer session pills | `.system(size: 9, weight: .semibold, design: .rounded)` |
| `.said` prose | `.system(size: 11.5, design: .rounded)` |
| `thinking` | `.system(size: 11, design: .rounded)` |

- [ ] **Step 2: Remove the rules**

Delete both `Divider().overlay(FeedPalette.hairline)` lines from `body`. The `VStack(spacing: 0)` becomes:

```swift
        VStack(spacing: 0) {
            header
            body(for: feed)
            footer
        }
```

Separation now comes from the existing header/footer padding. If the header and body read as touching in the screenshot, add `.padding(.top, 2)` to the body — **not** a rule.

- [ ] **Step 3: Drawn contours**

Replace the fill in `tag(_:)`:

```swift
    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(theme.dim.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(theme.dim.color.opacity(0.45), lineWidth: 1)
            )
            .lineLimit(1)
            .truncationMode(.middle)
    }
```

And the footer's session pills — replace `.background(…, in: RoundedRectangle(cornerRadius: 3))` with the same stroked overlay at radius 9, using the attention tint for the stroke when `attention` is true.

- [ ] **Step 4: Build clean**

```bash
swift build 2>&1 | grep -E "error:|warning:"
```

- [ ] **Step 5: Review with the SwiftUI skill**

Invoke the `swiftui-pro` skill against `Sources/OpenIslandApp/Views/AgentFeedView.swift` and `FeedTheme.swift`. Apply anything it flags on modern API usage and view-identity.

- [ ] **Step 6: Screenshot and look**

Capture, Read the PNG. Check:
- Names and labels are visibly **rounder**; timestamps and arguments are still monospaced.
- No divider lines anywhere.
- Branch tag and footer pills are outlined, not filled.
- Nothing clips at either edge — the handoff's D1 must not regress.

- [ ] **Step 7: Commit**

```bash
git checkout -- Assets/Brand
cliclick m:400,900
swift test 2>&1 | grep "Test run with"
git add Sources/OpenIslandApp/Views/AgentFeedView.swift
git commit -m "feat: give the feed the reference's hand"
```

---

## Task 7: Collapse — the pure parts

**Files:**
- Modify: `Sources/OpenIslandApp/Views/AgentFeedView.swift` (the `FeedTurn` / `FeedTurns` block near the bottom)
- Test: `Tests/OpenIslandAppTests/FeedTurnsTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/OpenIslandAppTests/FeedTurnsTests.swift`:

```swift
/// Spec §6. The summary row is what a reader sees instead of the block, so its
/// text and its diff totals are pinned here.
struct FeedTurnSummaryTests {
    private func entry(_ id: String, _ kind: AgentFeedEntry.Kind) -> AgentFeedEntry {
        AgentFeedEntry(id: id, timestamp: Date(timeIntervalSince1970: 0), kind: kind)
    }

    /// The header shipped "1 files"; pluralisation lives in one testable place now.
    @Test
    func labelPluralisesOnlyWhenItShould() {
        #expect(FeedTurnSummary.label(actionCount: 1) == "1 action")
        #expect(FeedTurnSummary.label(actionCount: 4) == "4 actions")
        #expect(FeedTurnSummary.label(actionCount: 0) == "0 actions")
    }

    @Test
    func diffTotalsSumOnlyTheEdits() {
        let turns = FeedTurns.grouped([
            entry("1", .said("working")),
            entry("2", .edited(file: "a.swift", added: 10, removed: 3)),
            entry("3", .edited(file: "b.swift", added: 5, removed: 1)),
            entry("4", .ran(tool: "Bash", argument: "swift build")),
        ])

        #expect(turns.count == 1)
        #expect(turns[0].actionCount == 3)
        #expect(turns[0].linesAdded == 15)
        #expect(turns[0].linesRemoved == 4)
        #expect(turns[0].hasDiff)
    }

    @Test
    func aTurnWithNoEditsHasNoDiff() {
        let turns = FeedTurns.grouped([
            entry("1", .said("looking")),
            entry("2", .ran(tool: "Read", argument: "a.swift")),
        ])
        #expect(turns[0].hasDiff == false)
    }
}

/// Spec §6.2. The newest turn is open by default; a turn the user touched keeps
/// their choice permanently. The distinction matters -- with a set of flips
/// rather than absolute values, a newest turn the user collapsed would spring
/// back open the moment a newer turn arrived and its default changed.
struct FeedExpansionTests {
    @Test
    func newestIsOpenAndOlderAreShutByDefault() {
        let state = FeedExpansion()
        #expect(state.isExpanded(turnID: "new", isNewest: true))
        #expect(state.isExpanded(turnID: "old", isNewest: false) == false)
    }

    @Test
    func anExplicitChoiceWins() {
        var state = FeedExpansion()
        state.toggle(turnID: "old", isNewest: false)
        #expect(state.isExpanded(turnID: "old", isNewest: false))

        state.toggle(turnID: "new", isNewest: true)
        #expect(state.isExpanded(turnID: "new", isNewest: true) == false)
    }

    /// The regression the dictionary exists to prevent.
    @Test
    func aCollapsedNewestTurnStaysShutAsItAges() {
        var state = FeedExpansion()
        state.toggle(turnID: "t", isNewest: true)      // user collapses the live turn
        #expect(state.isExpanded(turnID: "t", isNewest: true) == false)
        // a newer turn arrives; "t" is no longer newest
        #expect(state.isExpanded(turnID: "t", isNewest: false) == false)
    }

    @Test
    func anUntouchedTurnCollapsesOnItsOwnAsItAges() {
        let state = FeedExpansion()
        #expect(state.isExpanded(turnID: "t", isNewest: true))
        #expect(state.isExpanded(turnID: "t", isNewest: false) == false)
    }
}
```

- [ ] **Step 2: Run and watch it fail**

```bash
swift test --filter "FeedTurnSummaryTests|FeedExpansionTests" 2>&1 | tail -20
```

Expected: `cannot find 'FeedTurnSummary' in scope`.

- [ ] **Step 3: Implement**

In `Sources/OpenIslandApp/Views/AgentFeedView.swift`, extend `FeedTurn`:

```swift
extension FeedTurn {
    var actionCount: Int { actions.count }

    var linesAdded: Int {
        actions.reduce(0) { total, entry in
            if case .edited(_, let added, _) = entry.kind { return total + added }
            return total
        }
    }

    var linesRemoved: Int {
        actions.reduce(0) { total, entry in
            if case .edited(_, _, let removed) = entry.kind { return total + removed }
            return total
        }
    }

    var hasDiff: Bool { linesAdded > 0 || linesRemoved > 0 }
}

/// The one place the feed pluralises. The header shipped "1 files" for want of
/// exactly this.
enum FeedTurnSummary {
    static func label(actionCount: Int) -> String {
        "\(actionCount) action\(actionCount == 1 ? "" : "s")"
    }
}

/// Which turns are open.
///
/// A dictionary of *explicit choices*, not a set of flips. With a flip-set, a
/// newest turn the user collapsed would spring back open the moment a newer
/// turn arrived and its default changed underneath it.
struct FeedExpansion: Equatable, Sendable {
    private var explicit: [String: Bool] = [:]

    func isExpanded(turnID: String, isNewest: Bool) -> Bool {
        explicit[turnID] ?? isNewest
    }

    mutating func toggle(turnID: String, isNewest: Bool) {
        explicit[turnID] = !isExpanded(turnID: turnID, isNewest: isNewest)
    }
}
```

- [ ] **Step 4: Run the tests**

```bash
cliclick m:400,900
swift test --filter "FeedTurnSummaryTests|FeedExpansionTests" 2>&1 | grep "Test run with"
```

Expected: 8 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenIslandApp/Views/AgentFeedView.swift Tests/OpenIslandAppTests/FeedTurnsTests.swift
git commit -m "feat: add the turn summary and expansion rules"
```

---

## Task 8: Collapse — the UI

**Files:**
- Modify: `Sources/OpenIslandApp/Views/AgentFeedView.swift`

- [ ] **Step 1: Hold the state**

Beside `@State private var feed`:

```swift
    @State private var expansion = FeedExpansion()
```

- [ ] **Step 2: Tell `turnView` which turn is newest**

In `body(for:)`, replace the `ForEach` over turns:

```swift
                VStack(alignment: .leading, spacing: 16) {
                    let turns = FeedTurns.grouped(feed.entries)
                    ForEach(Array(turns.enumerated()), id: \.element.id) { index, turn in
                        turnView(turn, isNewest: index == turns.count - 1)
                    }
                }
```

- [ ] **Step 3: Rewrite `turnView`**

```swift
    private func turnView(_ turn: FeedTurn, isNewest: Bool) -> some View {
        let expanded = expansion.isExpanded(turnID: turn.id, isNewest: isNewest)

        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(turn.lead.enumerated()), id: \.element.id) { index, entry in
                row(for: entry, showsStamp: index == 0)
            }

            if !turn.actions.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    summaryRow(turn, isNewest: isNewest, expanded: expanded)
                    if expanded {
                        ForEach(turn.actions) { row(for: $0) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, actionIndent)
                .padding(.top, turn.lead.isEmpty ? 0 : 2)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(theme.hairline.color)
                        .frame(width: 1)
                        .padding(.leading, spineIndent)
                }
            }
        }
    }

    /// The whole row is the target, not the chevron -- a 9pt glyph is not a
    /// hit area.
    private func summaryRow(_ turn: FeedTurn, isNewest: Bool, expanded: Bool) -> some View {
        Button {
            expansion.toggle(turnID: turn.id, isNewest: isNewest)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(theme.faint.color)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 9, alignment: .leading)

                Text(FeedTurnSummary.label(actionCount: turn.actionCount))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.faint.color)
                    .lineLimit(1)

                Spacer(minLength: 4)

                // Kept visible while shut: "what changed" is the one signal
                // worth seeing without expanding.
                if turn.hasDiff {
                    if turn.linesAdded > 0 {
                        Text("+\(turn.linesAdded)")
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.color(for: .completed))
                            .fixedSize()
                    }
                    if turn.linesRemoved > 0 {
                        Text("−\(turn.linesRemoved)")
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.color(for: .waitingForApproval))
                            .fixedSize()
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(FeedTurnSummary.label(actionCount: turn.actionCount)), \(expanded ? "expanded" : "collapsed")"
        )
        .animation(.easeOut(duration: 0.16), value: expanded)
    }
```

- [ ] **Step 4: Build clean**

```bash
swift build 2>&1 | grep -E "error:|warning:"
```

- [ ] **Step 5: Screenshot and look**

Capture, Read the PNG. Check:
- Older turns show `▸ N actions`; the **newest turn is expanded**.
- A turn that edited files shows its diff badge while collapsed.
- A prose-only turn shows **no** summary row.
- The spine still runs beside the collapsed summary.

- [ ] **Step 6: Capture the interaction too**

Hover, then click a collapsed summary row and recapture:

```bash
cliclick m:400,900
zsh run-dev.sh >/tmp/rundev.log 2>&1
cliclick m:700,300 w:30000 m:757,4 w:800 m:757,14 w:800 m:757,24 w:1500
screencapture -x /tmp/before.png
```

Find a summary row's screen coordinates from the capture, click it, and capture again as `/tmp/after.png`. Read both. The clicked turn must open and the others must be unchanged.

- [ ] **Step 7: Commit**

```bash
git checkout -- Assets/Brand
cliclick m:400,900
swift test 2>&1 | grep "Test run with"
git add Sources/OpenIslandApp/Views/AgentFeedView.swift
git commit -m "feat: collapse each turn behind an expandable summary row"
```

---

## Task 9: The Cream card surface

**Files:**
- Modify: `Sources/OpenIslandApp/Views/AgentFeedView.swift`

Only Cream card has a `surface`. The body renders inside it; header and footer stay on the ground.

- [ ] **Step 1: Wrap the scrolling body**

In `body(for:)`, wrap the `ScrollView`'s content:

```swift
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    let turns = FeedTurns.grouped(feed.entries)
                    ForEach(Array(turns.enumerated()), id: \.element.id) { index, turn in
                        turnView(turn, isNewest: index == turns.count - 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, theme.surface == nil ? sideInset : 13)
                .padding(.vertical, theme.surface == nil ? 10 : 12)
                .background {
                    if let surface = theme.surface {
                        RoundedRectangle(cornerRadius: 13)
                            .fill(surface.color)
                            .feedGrain(opacity: 0.22)
                    }
                }
                .padding(.horizontal, theme.surface == nil ? 0 : sideInset - 9)
            }
```

The inner padding drops to 13 when a card exists because the card's own inset replaces part of the panel inset — the total to the panel edge stays comfortable. **Verify this by screenshot, not arithmetic.**

- [ ] **Step 2: Build clean**

```bash
swift build 2>&1 | grep -E "error:|warning:"
```

- [ ] **Step 3: Screenshot each skin**

For each of `inkPaper`, `creamCard`, `fullCream`:

```bash
defaults write app.openisland.dev app.islandTheme -string "creamCard"
pkill -f "Open Island Dev"
zsh run-dev.sh >/tmp/rundev.log 2>&1
cliclick m:700,300 w:30000 m:757,4 w:800 m:757,14 w:800 m:757,24 w:1500
screencapture -x /tmp/skin-creamCard.png
magick /tmp/skin-creamCard.png -crop 1010x1000+1010+0 +repage /tmp/skin-creamCard-crop.png
```

Read all three crops. Check per skin:
- Nothing clips at either edge (handoff D1).
- Every timestamp is readable — this is the measured `faint` tier in the real world.
- Status word and tints are legible on that ground.
- On Cream card, the card's edges are inside the panel and the header/footer sit on ink.

- [ ] **Step 4: Reset and commit**

```bash
defaults write app.openisland.dev app.islandTheme -string "inkPaper"
git checkout -- Assets/Brand
git add Sources/OpenIslandApp/Views/AgentFeedView.swift
git commit -m "feat: give the cream card skin its own reading surface"
```

---

## Task 10: The settings picker

**Files:**
- Modify: `Sources/OpenIslandApp/Views/AppearanceSettingsPane.swift`
- Modify: `Sources/OpenIslandApp/Resources/{en,zh-Hans,zh-Hant}.lproj/Localizable.strings`

- [ ] **Step 1: Add the strings**

`en.lproj/Localizable.strings`:

```
"settings.appearance.theme" = "Island theme";
"settings.appearance.theme.inkPaper" = "Ink paper";
"settings.appearance.theme.creamCard" = "Cream card";
"settings.appearance.theme.fullCream" = "Full cream";
```

`zh-Hans.lproj/Localizable.strings`:

```
"settings.appearance.theme" = "灵动岛主题";
"settings.appearance.theme.inkPaper" = "墨纸";
"settings.appearance.theme.creamCard" = "米色卡片";
"settings.appearance.theme.fullCream" = "全米色";
```

`zh-Hant.lproj/Localizable.strings`:

```
"settings.appearance.theme" = "靈動島主題";
"settings.appearance.theme.inkPaper" = "墨紙";
"settings.appearance.theme.creamCard" = "米色卡片";
"settings.appearance.theme.fullCream" = "全米色";
```

- [ ] **Step 2: Add the section**

Read how `stateIndicatorSection` builds its option rows (around `AppearanceSettingsPane.swift:397-424`) and follow that shape exactly. Add `themeSection` to the pane's body list, before `previewSection`. Bind to `model.islandTheme` directly — it is global, not part of `editingPreferences`.

Drive the rows from `IslandTheme.allCases`, so an unlock filter later has one place to sit. Each row shows a swatch filled with `FeedTheme.resolve(theme).ground.color`, and for `creamCard` a two-band swatch (ink over cream) so the composition is visible.

- [ ] **Step 3: Build clean**

```bash
swift build 2>&1 | grep -E "error:|warning:"
```

- [ ] **Step 4: Screenshot the settings pane**

```bash
pkill -f "Open Island Dev"
zsh run-dev.sh >/tmp/rundev.log 2>&1
```

Open Settings from the island header (gear icon), go to Appearance, capture, and Read it. Check the three rows render, the current one is marked, and clicking one changes the panel.

- [ ] **Step 5: Commit**

```bash
git checkout -- Assets/Brand
cliclick m:400,900
swift test 2>&1 | grep "Test run with"
git add Sources/OpenIslandApp/Views/AppearanceSettingsPane.swift Sources/OpenIslandApp/Resources
git commit -m "feat: add the island theme picker to appearance settings"
```

---

## Task 11: Review and close out

- [ ] **Step 1: Concurrency review**

Invoke the `swift-concurrency-pro` skill against `FeedTheme.swift` and `AgentFeedView.swift`. `FeedGrain` is `@MainActor` and holds a cached `Image`; confirm that is the right isolation and that nothing else introduced shared mutable state.

- [ ] **Step 2: SwiftUI review**

Invoke `swiftui-pro` against both view files. Apply what it flags.

- [ ] **Step 3: Full verification**

```bash
pwd
```

Expected: `.../.claude/worktrees/feat+companion-pill`

```bash
swift build 2>&1 | grep -E "error:|warning:"
```

Expected: no output.

```bash
cliclick m:400,900
swift test 2>&1 | grep "Test run with"
```

Expected: **5 issues**, no more.

- [ ] **Step 4: Final evidence — one capture per skin**

Re-run Task 9's per-skin capture. Attach all three to the final report. Confirm against the handoff's original acceptance criteria, which must not have regressed:

- `Opus 5` reads in full at the left edge; the status word reads in full at the right
- Every timestamp complete, no cut digits
- No tool row wraps
- Turns visually separable

- [ ] **Step 5: Update the spec's status**

Add a line at the top of `docs/superpowers/specs/2026-08-22-feed-skins-design.md` recording that it is implemented, and note anything that changed during the build.

- [ ] **Step 6: Clean up and commit**

```bash
rm -f run-dev.sh
git checkout -- Assets/Brand
git status --short
```

`git status` must show only intended files. Then commit the spec update.

---

## Self-review notes

Checked against the spec:

- §4.1 preference scope → Task 3
- §4.2 catalogue → Task 2 step 3
- §4.3 resolved tokens → Task 2
- §5 grain / no rules / drawn contours / two faces → Tasks 5, 6
- §6.1 summary content → Tasks 7, 8
- §6.2 default state → Task 7 (`FeedExpansion`)
- §6.3 hit target → Task 8 step 3
- §6.4 pure helpers → Task 7
- §7 settings → Task 10
- §7.5 measured colour → Task 2, asserted as tests
- §8 verification → every task's screenshot step, plus Task 11

Naming is consistent throughout: `FeedInk`, `FeedTheme.resolve`, `FeedTheme.ink(for:)`, `FeedTheme.color(for:)`, `FeedTheme.headerColor(for:)`, `FeedGrain.tile`, `FeedTurnSummary.label(actionCount:)`, `FeedExpansion.isExpanded(turnID:isNewest:)` / `.toggle(turnID:isNewest:)`.

One thing deliberately left to the implementer's eye rather than specified: the exact grain opacity and the Cream card's inner padding. Both are stated with a starting value and a screenshot check, because the handoff proved that this panel's spacing cannot be reasoned about from the code.
