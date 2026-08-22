# Companion feed — skins and collapsible turns

Date: 2026-08-22
Branch: `worktree-feat+companion-pill`
Design canvas: https://claude.ai/code/artifact/32a9b7d2-e55f-467a-9e85-39c19fa5a636

Supersedes nothing. Builds directly on
`2026-08-22-companion-feed-handoff.md`, whose four layout defects are closed —
this is the round that follows.

---

## 1. What this is

Two changes to `AgentFeedView`, driven by one reference:

1. **Restyle it toward Cat On Chair** — the texture and the lettering — without
   losing the density that makes the panel readable under time pressure.
2. **Collapse each turn's tool calls**, expandable, collapsed by default.

The reference is the app the user owns (`vibeisland.app` is the product
baseline; Cat On Chair is the *aesthetic* reference, studied from the 38
full-res App Store screens in `~/Documents/openisland-refs/gallery/`).

---

## 2. The one constraint that shapes everything

The handoff established, by measurement, that every status tint in
`IslandDesignPalette` is tuned for ink:

| Phase | On ink | On cream |
|---|---|---|
| waiting for approval | 9.89:1 | 1.64:1 |
| waiting for answer | 13.99:1 | 1.16:1 |
| running | 7.98:1 | 2.03:1 |
| completed | 8.26:1 | 1.96:1 |

A cream panel is therefore not a restyle — it is a redesign of the status
system. That fact is what turns "which ground?" from a taste question into an
architecture question, and it is why the ground became a **preference with
three values** rather than a single decision.

Everything else the reference does — grain, hand-lettering, drawn contours,
the total absence of rules and boxes — is **ground-independent**. Those land
on all three skins identically. That is the load-bearing insight of this
design: the character does not come from the cream.

---

## 3. Decisions settled

| Decision | Choice | Why |
|---|---|---|
| Ground | Three skins, user-switchable | User liked all three; the cost differs per skin, so it is a real choice, not a default |
| Default skin | `inkPaper` | Only skin that keeps the closed pill invisible against the hardware notch |
| Economy | **Not built** | Catalogue is shaped for it; currency, earn rules and unlock UI are deferred |
| Display face | SF Rounded (`design: .rounded`) | Zero-asset, licence-free, hints correctly at 9pt where a drawn face turns to mush |
| Data columns | Stay monospaced | The mono column is what makes the feed scannable; this is the "informative" half being protected |
| Collapse default | Collapsed, **except the newest turn** | All-collapsed makes a running agent look identical to a finished one |
| Preference scope | Global, not per-display-profile | See §4.1 |

---

## 4. Theme model

### 4.1 Where the preference lives

`IslandAppearancePreferences` is stored **per display profile** — notch and
top-bar each keep their own copy, keyed by
`appearanceDefaultsKey(profile, name)`. The theme deliberately does **not** go
there. It becomes a global preference alongside `showCompanion`:

```swift
private static let islandThemeDefaultsKey = "app.islandTheme"
var islandTheme: IslandTheme = .inkPaper { didSet { …persist… } }
```

Reasoning: a theme is an identity, not a layout adaptation. Every other member
of `IslandAppearancePreferences` answers "how should the island lay itself out
on *this* screen"; the theme answers "what is the island made of". A user who
picks Cream card expects it everywhere, not once per monitor.

There is a genuine counter-argument — on an external display the panel is not
hiding a notch, so Full cream is more viable there than on a MacBook — and the
per-profile machinery is already built. It is rejected as speculative. If it is
ever wanted, moving one global key into the per-profile struct is a small,
contained migration.

### 4.2 The catalogue

```swift
enum IslandTheme: String, CaseIterable, Identifiable, Sendable {
    case inkPaper       // default
    case creamCard
    case fullCream

    var id: String { rawValue }
    var displayNameKey: String { "settings.appearance.theme.\(rawValue)" }
}
```

`CaseIterable` is what makes this "collectible-ready" at zero cost:
`allCases` **is** the inventory. An unlock layer later filters that sequence
before the picker renders it, and touches nothing in the render path.

### 4.3 Resolved tokens

`FeedPalette` stops being a set of statics and becomes a resolved value:

```swift
struct FeedTheme: Equatable, Sendable {
    let ground: Color        // the panel's own background
    let surface: Color?      // inner reading card; nil when ground IS the reading surface
    let text: Color
    let dim: Color           // arguments, secondary prose
    let faint: Color         // timestamps, stats
    let hairline: Color      // the turn spine
    let usesPaperTints: Bool

    static func resolve(_ theme: IslandTheme) -> FeedTheme
    func statusTint(for phase: SessionPhase) -> Color
}
```

`surface` is what distinguishes Cream card from the other two: `inkPaper` and
`fullCream` return `nil` (the ground is the reading surface); `creamCard`
returns the cream, and the body renders inside it while header and footer stay
on the ground.

`statusTint(for:)` returns `IslandDesignPalette.Status.tint(for:)` unchanged
when `usesPaperTints` is false. **`IslandDesignPalette` is not modified** — it
is used across the whole app, and this change stays inside the feed.

`FeedTheme.resolve` is pure and lives outside the view, so it is unit-testable
without a MainActor hop (see the handoff's §6 signal-5 trap).

---

## 5. The hand

Four moves, applied identically to all three skins.

**Grain.** A 128×128 fractal-noise tile, generated once via Core Graphics into
a cached `CGImage` held in a `static let`, tiled across the surface with
`.blendMode(.overlay)` at low opacity. No asset ships; it is deterministic and
cheap to composite. Rebuilding it per frame would be the obvious mistake — it
is built once, at first use.

**No rules.** Cat On Chair contains not one divider or boxed container in the
entire app. Both `Divider()`s in the feed are removed; separation comes from
spacing and the grain edge.

**Drawn contours.** Filled chips (`tag`, the footer's session pills) become
stroked outlines. The reference outlines its numerals and scribbles an ellipse
around *Start* rather than drawing a button — the stroke, not the fill, is what
reads as hand-made.

**Two faces, held apart.** `design: .rounded` on the display tier — workspace
name, status word, tool labels, empty state. The monospace tier is untouched:
timestamps and tool arguments stay `design: .monospaced`. This preserves the
handoff's "two text tiers only" rule; it changes the *face*, not the hierarchy.

---

## 6. Collapse

### 6.1 What a collapsed turn shows

`▸ 4 actions`, plus the turn's net diff when it edited anything:
`▸ 3 actions   +473 −49`.

The count, never the tool names — names would wrap, which is D3 from the
handoff reintroduced by the back door. The diff badge survives collapse because
"what changed" is the single most valuable signal in the block, and keeping it
visible is what makes collapsing safe rather than merely tidy.

A turn with **no actions** gets **no summary row at all** — prose only. Nothing
should look clickable that isn't.

### 6.2 Default state

Expanded iff newest, until the user says otherwise:

```swift
@State private var explicit: [String: Bool] = [:]

func isExpanded(_ turn: FeedTurn, isNewest: Bool) -> Bool {
    explicit[turn.id] ?? isNewest
}
```

A dictionary of *explicit choices*, not a set of flips. The distinction
matters: with a flip-set, a newest turn the user collapsed would spring back
open the moment a newer turn arrived and its default changed. With absolute
values, a touched turn keeps the user's choice permanently and an untouched one
follows the default as it ages out of newest.

`explicit` lives on the view, not in the feed data. Turn ids derive from the
transcript's own record uuids, so they are stable across a re-parse — the
`AgentFeed` value is replaced every two seconds and the expansion survives it.

### 6.3 Interaction

The whole summary row is the hit target, not the chevron. `Button` with
`.buttonStyle(.plain)`, an accessibility label naming the turn, and the chevron
rotating 90° on open.

### 6.4 Pure helpers

Added to `FeedTurn`, all pure and outside the view:

```swift
var actionCount: Int
var linesAdded: Int        // summed over .edited actions
var linesRemoved: Int
var hasDiff: Bool
```

plus `FeedTurnSummary.label(actionCount:)` returning `"1 action"` /
`"4 actions"` — pluralisation in one testable place, since the header already
shipped a `1 files` bug for want of exactly this.

---

## 7. Settings

A theme section in `AppearanceSettingsPane`, rendered with its existing
`SettingsPreviewStage` so the preview is the real feed rather than a picture of
one. Three swatches, `allCases`-driven, current selection ringed in the accent.

Strings land in all three bundles — `en`, `zh-Hans`, `zh-Hant` — matching
`settings.general.showCompanion`'s existing pattern.

---

## 7.5 Measured colour — computed 2026-08-22

Computed, not asserted. Method: WCAG 2.x relative luminance, sRGB, ratio
`(L₁+0.05)/(L₂+0.05)`. Alpha tiers are composited against their ground first,
so the figure is the colour that actually renders.

### Two findings that changed the design

**The `faint` tier shipped below AA.** `V6Palette.paper.opacity(0.34)` on
`#0d0d0f` measures **2.74:1** — the timestamp column, the stats line and the
empty-state subtitle are all under the 4.5:1 bar for small text. The handoff
measured the status *tints* and nobody measured the alpha tiers beneath them.
This round fixes it: `faint` becomes 0.50 on ink.

**An automated tint search produces the wrong palette.** Maximising lightness
subject to ≥4.5:1 returns `#d10f0f` and `#005ded` — fully saturated, and the
opposite of the reference's muted world. The paper tints below are hand-picked
from Cat On Chair's own palette and clear the bar anyway.

### Ink skins — ground warmed `#0d0d0f` → `#12110f`

Warming costs about 3% contrast; everything still clears comfortably.

| Token | Value | Ratio |
|---|---|---|
| text | `paper` @ 0.94 → `#e4ddcd` | 13.95:1 |
| dim | `paper` @ 0.66 → `#a5a094` | 7.24:1 |
| faint | `paper` @ 0.50 → `#827e74` | 4.66:1 |
| approval | `#f4a4a4` unchanged | 9.61:1 |
| answer | `#ffd58a` unchanged | 13.60:1 |
| running | `#6ea7ff` unchanged | 7.76:1 |
| completed | `#6fb982` unchanged | 8.03:1 |

### Paper skins — ground `#efe7d6`

| Token | Value | Ratio |
|---|---|---|
| text | `#241f1a` | 13.28:1 |
| dim | `#241f1a` @ 0.80 → `#4d4740` | 7.45:1 |
| faint | `#241f1a` @ 0.66 → `#69635a` | 4.83:1 |
| approval | `#a8432f` brick | 4.87:1 |
| answer | `#8a5a12` deep amber | 4.81:1 |
| running | `#24608f` dusty blue | 5.43:1 |
| completed | `#3d6b3d` sage | 5.07:1 |

Hairlines are non-text and carry no bar: ink spine `paper` @ 0.14 (1.41:1),
paper spine `#241f1a` @ 0.20 (1.49:1). Both are meant to be barely there.

---

## 8. Verification

The figures in §7.5 are computed. They are also **asserted in tests** —
`FeedInk.contrast(against:)` is real code, not a comment, so a future tweak
that drops a token below its bar fails the suite rather than shipping.

| Check | Method | Bar |
|---|---|---|
| Every text token, every skin | `FeedInk.contrast(against:)` in a unit test | ≥ 4.5:1 |
| Status dot | Same, as a non-text graphic | ≥ 3:1 |
| `FeedTheme.resolve` | Plain unit tests, all three skins | Every token set, `surface` nil iff not `creamCard` |
| Turn summary + diff totals | Plain unit tests | 0 / 1 / n actions, with and without edits |
| `isExpanded` defaulting | Plain unit tests | Newest open; touched turn keeps its choice as it ages |
| Each skin on device | Launch, hover, screenshot, **look** | One capture per skin, per the handoff's §4 loop |
| Regression | `swift build` / `swift test` | Zero warnings; 5 known issues, no more |

Any tint failing its bar is retuned before it ships. Shipping a measured
failure with a caveat is not an option here — the whole reason three skins
exist is that the first measurement was taken seriously.

Screenshot loop caveat from the handoff's §6 applies: move the pointer off the
notch (`cliclick m:400,900`) before `swift test`, or
`completionNotificationHoverCancelsPendingTimedCollapse` fails and the count
reads 6.

---

## 9. Files

| File | Change |
|---|---|
| `Sources/OpenIslandApp/AppModelTypes.swift` | `IslandTheme` enum |
| `Sources/OpenIslandApp/AppModel.swift` | `islandTheme` property, defaults key, register, load |
| `Sources/OpenIslandApp/Views/FeedTheme.swift` | **new** — token resolution, paper tints, grain tile |
| `Sources/OpenIslandApp/Views/AgentFeedView.swift` | theme-aware palette, grain, rounded face, drawn contours, collapse |
| `Sources/OpenIslandApp/Views/IslandPanelView.swift` | pass the resolved theme in |
| `Sources/OpenIslandApp/Views/AppearanceSettingsPane.swift` | theme section |
| `Sources/OpenIslandApp/Resources/{en,zh-Hans,zh-Hant}.lproj/Localizable.strings` | theme names |
| `Tests/OpenIslandAppTests/FeedThemeTests.swift` | **new** — token resolution, contrast |
| `Tests/OpenIslandAppTests/FeedTurnsTests.swift` | summary, diff totals, expansion defaulting |

---

## 10. Out of scope

Deferred deliberately, and the catalogue is shaped so each can land later
without touching the render path:

- Currency ledger, earn rules, unlock gate, inventory screen, equip flow,
  balance tuning
- A bundled hand-lettered face
- Per-display-profile themes (§4.1)
- Parsers for Codex, Gemini and Cursor transcripts — still out, per the handoff
- Wiring the companion pose to the feed; the completion card
