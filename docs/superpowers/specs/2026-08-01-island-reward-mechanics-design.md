# The Island — Reward & Progression Mechanics

**Date:** 2026-08-01
**Status:** Built on `feat/island-creature`, behind an off-by-default preference. Reconciled with the
shipped code on 2026-08-04 — sections carrying a dated **Amended** / **Superseded** / **Obsolete** /
**Resolved** note describe what shipped; the prose above each such note is the original design and is
kept as the record of what was intended. What is *proven* versus what still needs a human eye is in
`docs/DEMO-READINESS.md`, not here.
**Scope:** The expressive layer across both bars (closed pill + opened panel). Phase 0 is a kill gate.
**Supersedes:** nothing. **Extends:** `2026-07-30-geode-session-crystals-design.md`,
`2026-07-31-session-log-and-stats-design.md`

## Summary

Sessions become **creatures that work at stations on a small island**. Starting a session brings a
creature to its station. When the agent blocks on the human, the creature stops and **raises a hand** —
that gesture replaces the grey desaturation as the notification, and clicking it performs the jump-back
we already implement. A clean finish makes the creature hold an object overhead; clicking collects it and
the object lands on the island. An interrupt knocks the creature over and leaves scrap. At the end of the
day the whole thing totals up as a **printed receipt**.

The island lives in the opened panel. The closed pill shows one creature — the one that most wants
attention — and signals state by **breaking the capsule's outline** rather than by adding detail it
cannot afford in a 28 × 32 pt lane.

Everything here is a preference. One toggle returns both bars to exactly what ships today.

## Why this shape

The design is a deliberate translation of Cat on Chair (Pomodoro timer, 127K downloads, ~$80K over 8–9
months, $18K in the last 30 days, built solo). Its designer states the generative question outright:
*"How do we replicate the physical experience of having a cat in a digital app?"* Gift-on-success,
trash-on-failure, tap-to-meow and the furniture all fall out of that one question.

**Our question is not the same one, because the roles are inverted.** In Cat on Chair the human does the
work and the cat keeps company. In Open Island **the agent does the work and the human is the one being
waited on**. So the creature is the worker, and the user's contribution is *stewardship*: start good work,
answer it quickly, don't abandon it, ship it.

That inversion resolves the standing tension about rewarding prompting. The requirement was that
prompting must feel rewarding; the objection was that prompt volume is farmable and rewards burning
tokens. Both hold, because:

> **Prompting doesn't pay. Prompting summons.**

Starting a session brings a worker to a station — presence, exactly like the cat jumping on the chair, and
zero points. What pays is **answering fast** (already logged as reply latency), **finishing clean**
(already logged as `isInterrupt`), and **shipping**. Farming prompts yields a crowded island of idle
workers and nothing else.

The second reason for this shape is that it is **not decoration bolted onto a tool**. The gesture *is* the
notification and the click *is* the jump-back. The expressive layer and the useful layer are the same
interaction.

## Relationship to the geode spec

The geode spec's core claim was **"the stop is the notification"** — the crystal freezes and desaturates
when an agent blocks. That claim survives; only its *expression* changes. A raised arm is the same signal
with more amplitude and a direction: grey says something is wrong, a raised arm says what to do about it.

Concretely:

- `GeodeState` and its event mapping are **reused as-is**. All four transitions this design needs already
  exist there.
- `CrystalSeed` / `GeodeShardForm` procedural generation is **reused** for per-session individual variation
  within a species.
- Per-agent hue mapping is **kept but demoted**. Measured: the six proposed species hues all fall
  inside a 14.4-point luminance band, with no adjacent pair separated by more than 4.3. In greyscale
  they are one colour. Hue therefore **reinforces** species identity; it cannot carry it. Silhouette
  carries it. See "Measured constraints" below.
- Saturation is **freed**: blocked is now a gesture, so grey reverts to meaning stale
  (reuse the existing `staleThreshold` preference, do not invent a second one).
- Silhouette **stops carrying duration**. Today growth maxes at 31 minutes and then never changes again;
  duration moves to the panel where there is room for it.

## Measured constraints

All figures below were measured on real hardware and real code, not estimated. They supersede the
"~20pt pill" framing this project has been carrying since the original handoff brief, which was wrong.

### Geometry

| Surface | Width | Height | Source |
|---|---|---|---|
| Closed pill, built-in display | 277 (44 + 189 notch + 44) | 32 | `safeAreaInsets.top`, measured 1512×982 |
| Closed pill, external display | fluid, min 70 | 24 | `topStatusBarHeight` |
| **Right-slot lane (the creature budget)** | **28 usable** | **32** | 44 reserve − 16 pad |
| Opened panel, notch | 540 | 32 + content | `preferredNotchOpenedPanelWidth` |
| Opened panel, top bar | 520 | 24 + content | `preferredTopBarOpenedPanelWidth` |
| Notification panel | 620 | auto | `preferredNotificationPanelWidth` |

Two consequences. **The creature budget is width-constrained, not height-constrained** — 28pt wide
against 32pt tall — so bodies are tall and slim with tucked arms. And **the pill cannot draw above
itself**: its top edge *is* the physical top edge of the display, so anything drawn there is off-screen,
not clipped. Outline-breaking gestures must extend **downward** into the menu-bar strip. Proving that is
Phase 1.

At 540pt the station pitch is ~118pt for four sessions. Below ~90pt structures collide, so the ceiling is
**five visible stations**; beyond that, overflow collapses to counted dots rather than shrinking or
scrolling.

### Value, which is the real art constraint

Contrast ratios against the closed pill fill `#0d0d0f` (`V6Palette.ink`):

| Colour | Role | Contrast |
|---|---|---|
| `#211e12` | the reference style's signature outline | **1.16:1 — invisible** |
| `#b73b3a` | accent / interrupted | 3.43:1 — weak |
| `#856a47` | structure dark | 3.84:1 — weak |
| `#b4de6f` | light wash | 12.61:1 |

Empirically confirmed against the reference product's own artwork: their cat, downscaled to exactly this
budget (53×64 px), averages `#4f412f` and scores **6.39:1 on their light ground but 1.97:1 on our pill** —
identical art, 3.2× worse, purely from what sits behind it.

**The conclusion is narrower than "painterly cannot work small".** It survives fine at 53×64 — silhouette
and soft internal banding both read. What fails is *dark-subject-on-light-ground*, which is the assumption
the entire reference style is built on and which our pill inverts. Therefore:

- Pill creatures are **light masses read by silhouette**. Dark line is used only *inside* the shape,
  never to carry its edge.
- The palette's midtones (`#97b76a`, `#94ab5a`, `#c4ae8e`) cluster in luminance and will merge at pill
  size. Species values must be **deliberately spread**, not just hue-shifted.
- Pill and panel creatures are **separately authored optical sizes**, not one master scaled down.

**Superseded 2026-08-04, during implementation.** The second bullet is now *impossible*, not merely
hard. Deliberately spreading species by value assumes one ground to spread against; the shipped
sprites are shown on two opposite ones, which pins all six into an eleven-point window. See "The
palette after the first real sprites" below.

## Phase 0 — kill gate (blocking)

**Nothing else in this spec may be built until this passes.** This mirrors the geode Phase 0 gate.

Build an offscreen render harness — same approach that produced `shard-final.png` and `geode-shapes.png` —
that draws real SwiftUI shapes to PNG at **true 28 × 32 pt composited on `#0d0d0f`** and at **64px on the
panel ground**, for all four poses across all six species, plus 20 procedural individual variations within
one species.

Pass conditions:

1. At true pill size **on the actual pill colour**, calm / asking / collectable are mutually
   distinguishable at a glance, judged on the worst roll, not the best.
2. Every species and pose clears **≥3:1 against `#0d0d0f`** as a measured number, not a judgement.
3. At 64px, all four poses are distinguishable.
4. **Greyscale separation:** with colour removed, the six species remain tellable apart. The luminance
   ladder carries this, so it is testable on placeholder geometry and is asserted in
   `CreaturePaletteTests`. **The ladder did not survive the real sprites** — silhouette carries this
   condition now, which is what condition 5 was always for. See "The palette after the first real
   sprites" below.
5. **Silhouette separation:** the six species are distinguishable from shape alone. This is
   **deferred to the first real asset batch** and is *not* testable on the placeholder shapes — those
   vary per session seed, not per species, so all six bodies are currently the same shape in different
   values. Deliberate: species-distinct silhouettes are an art deliverable, not a procedural one.
   Whoever draws the assets owns this condition, and the gate re-runs against it.
6. No procedural individual reads as a dud or as a different species.

Conditions 1, 2 and 4 gate the **system** and run now. Conditions 3, 5 and 6 gate the **art** and run
again on real sprites. Running the gate twice is the intent, not a workaround — the current pass answers
"does the mechanism work", the later one answers "does the drawing work".

An earlier HTML prototype suggested *working* and *knocked-over* would not separate at pill size, and this
spec previously accepted that. **The gate disproved it** — see the outcome below. The tipped pose is the
most legible of the four.

If condition 1 or 2 fails, this design does not ship in the pill and the panel-only variant is the
fallback.

## Phase 0 gate outcome — 2026-08-02

Run via `scripts/creature-gate.sh` against the real `CreatureForm` / `CreaturePalette`, 54 PNGs, judged at
true 28 × 32 pt on `#0d0d0f` at 1× and 2× rasterisation — not at the 4× render.

**Numeric half: PASS.** Worst species contrast 3.98:1 (openCode), well clear of 3:1. The greyscale
luminance ladder resolves into six clean, mutually distinguishable steps. Condition 2 and condition 4
both hold. Lane fit holds too: worst overflow 0.46 pt across 20 seeds × 4 poses, so the 70° tilt fits.

**Condition 1: FAIL.** *waiting* and *holding* do not separate at true pill size.

Root cause, measured rather than judged: **the arms are geometrically incapable of leaving the body.**
`reach` is `0.34 × bodyHeight` while the body top sits `0.5 × bodyHeight` above centre, so at full lift
the arm tip reaches at best `midY + 0.40h` — still inside the mass. Protrusion above the body measured
**+0.00 pt for all three upright poses**. What separates the poses visually is therefore not a raised arm
but an interior dark counter where the pill shows through the arm/flank gap, and that counter is nearly
identical between *waiting* and *holding*.

Compounding it, sideways extent runs **backwards**: calm *working* is the widest silhouette at +3.86 pt,
reward-bearing *holding* the narrowest at +1.98 pt. The pose that should shout has the tightest outline.

Corrections to this spec that the gate forced:

- *fallen* is the **most** legible pose, not the least. The 70° tilt is unmistakable at true size. The
  prior assumption above was wrong and has been struck.
- **The palette does not survive the panel ground.** Five of six species measure under 3:1 against
  `#b4de6f` (claude 1.13:1, codex 1.08:1, cursor 1.34:1, gemini 1.70:1, kimi 2.27:1); only openCode
  clears at 3.17:1. `lineWork` `#211e12` measures 10.82:1 there versus 1.16:1 on the pill. The palette is
  a **single-ground** palette built for a dark pill. "Separately authored optical sizes" must extend to
  **value**: panel creatures need dark bodies, or a dark plate behind them.
- Procedural variety is low. The 20 rolls contain no duds and none reads as a different species, so
  condition 6 passes on its letter, but they read as one creature at slightly different proportions.
  `bodyWidth` 0.52–0.68 and `bodyHeight` 0.74–0.92 are too narrow a range to perceive at this size.

## Phase 0 re-gate — 2026-08-02, condition 1 now passes

Option (a) was taken and the geometry fixed. One correction to the diagnosis above: **`reach` could not
simply be increased.** The proposed fix needs up to 14.7 pt of reach, and the lane offers at most 4.2 pt of
headroom above the body — which is itself the physical top edge of the display, where nothing can be drawn.
Vertical was never available. The sides carry 4.5–6.7 pt each, and that is the only axis with room.

So magnitude was replaced with **count and symmetry**. `CreatureForm` now carries `armLiftLeading` and
`armLiftTrailing` instead of a single `armLift`:

| Pose | Arms | Reads as |
|---|---|---|
| `working` | 0.0 / 0.0 | compact, symmetric |
| `waiting` | **1.0 / 0.0** | **lopsided** — one arm out |
| `holding` | 1.0 / 1.0 | wide, symmetric |
| `fallen` | 0.1 / 0.1 | tucked, tilted 70° |

Arms now travel *outward* to the lane edge as lift rises rather than inward, correcting the backwards
width relationship. Measured on the reference body: `working` breaks the outline +2.20 pt both sides,
`waiting` +5.18 / +2.20, `holding` +5.18 both. Protrusion above the body is +2.94 pt for the raised poses,
up from +0.00. Lane overflow is unchanged at 0.46 pt worst.

**Judged on the worst roll**, as the condition requires — the widest body, in the darkest species, at 1×
and 2× rasterisation. *waiting* holds 2.43 pt of asymmetry and *holding*'s weaker arm still breaks by
4.74 pt. All three states separate. The gate now renders `worst-<pose>.png` so this is inspectable rather
than asserted.

**Condition 1: PASS.** Conditions 2 and 4 still pass unchanged. Conditions 3, 5 and 6 remain art-gated and
re-run on the first real asset batch.

The rule that carries this — *state is signalled by how many limbs are out, not how far* — is recorded in
`docs/STYLE-SPEC.md` §6, because the illustrator inherits the rule rather than the geometry.

### The panel ground, also resolved

The single-ground finding above stands — the pill ladder genuinely cannot be reused on `#b4de6f`. What
changed is that the ladder is now **restated** for the panel rather than abandoned. `CreaturePalette`
gained `panelGround` and `panelColor(for:)`, which scales each species in linear light into an L 3–14%
band: same order, same hues, dark enough to read on a light ground.

| Species | Pill on panel | Panel value | On panel |
|---|---|---|---|
| Claude | 1.13:1 | `#766656` | 3.58:1 |
| Codex | 1.08:1 | `#535f6e` | 4.22:1 |
| Cursor | 1.34:1 | `#385b4b` | 4.92:1 |
| Gemini | 1.70:1 | `#4e4658` | 5.82:1 |
| Kimi | 2.27:1 | `#563342` | 6.99:1 |
| OpenCode | 3.17:1 | `#343022` | 8.56:1 |

Derived rather than hand-picked, so the 3:1 property holds by construction. Checked desaturated as well
as in colour — the previous panel renders vanished under greyscale, and these do not. Panel renders in
the gate now use these values.

**Obsolete 2026-08-04, during implementation — this whole subsection describes a problem that no
longer exists.** The two-ground band below moved every species down into L 14.9–16.0%, and at those
values the *pill* colours already clear 3:1 on `#b4de6f` unaided: claude 3.25:1, codex 3.39:1, cursor
3.26:1, gemini 3.42:1, kimi 3.24:1, openCode 3.28:1. The table above — 1.08:1 to 2.27:1 — was
measured against the old ladder and no longer describes anything shipped. `scripts/creature-gate.sh`
still prints its "pill values cannot be reused here" heading and then answers **"was already fine"**
on all six rows, which is the finding rather than a bug in the gate.

`panelGround` and `panelColor(for:)` are therefore **superseded but not dead**, and were deliberately
left in place: `scripts/creature-gate.swift` renders and reports through them in three places, and
four tests in `CreaturePaletteTests` assert on them. Nothing in the shipped app has ever called
either — the panel draws creatures over painted scene artwork (`scene-band.png`), not over a flat
wash. Retiring them is a change to the gate's output and to test coverage, which is a decision for
whoever next re-runs the art gate, not a docs edit.

### Procedural variety, also resolved

Not by widening the proportions. Width is the lane's binding constraint and the raised-arm gesture needs
the side room, so widening would have bought individuality by spending legibility — the two compete for
the same budget. `CreatureForm` gained a `roundness` channel instead: silhouette shape from boxy to full
capsule at constant width, which costs no horizontal room.

Re-gated afterwards. Pose separations are unchanged (2.43 pt asymmetry, 4.74 pt weaker arm), worst lane
overflow 0.57 pt, and the 20 rolls now show visibly distinct outlines with no dud and no species
confusion.

### The window overhang is not needed

Phase 1 was to prove the pill can draw **below** the capsule, on the reasoning that raised arms must escape
downward because they cannot go up. The sideways fix removes that need: measured across 20 seeds × 4 poses,
**nothing is drawn above the lane at all**, and the worst spill of any kind is 0.57 pt on the *left* edge
from the `fallen` tilt. The creature is fully contained by the pill it already has.

Growing the closed window into the menu-bar strip would therefore be building for a gesture that no longer
exists, at the cost of a transparent overhang that has to be proven not to eat menu-bar clicks. **Not
built.** If a later art batch wants a gesture that leaves the capsule, this becomes live again — the
constraint is recorded in `docs/STYLE-SPEC.md` §6, and `CreatureSilhouetteTests` asserts the containment
that makes it unnecessary today.

**Confirmed skipped 2026-08-04, after the whole build.** Concretely, **Task 7 of
`docs/superpowers/plans/2026-08-02-island-creature-pill.md`** — "Window geometry spike: can the pill
draw below itself?" — was never started. It would have added
`OverlayPanelController.closedPoseOverhang` and `closedFrameHeight(pillHeight:)`; neither symbol
exists anywhere in the tree, and `OverlayPanelController` is untouched by this branch. Build order
item 1 and the "window-geometry risk" section below both still describe it as blocking work. It is
not: it was made unnecessary before it was due, and the re-gate above is the evidence.

Two consequences the rest of this spec should be read against:

- **The closed pill never grows.** `V6RightSlotView` draws `.creature` at a fixed
  `CreatureView.pillSize` inside the existing lane, and only the finished-today tally can change the
  pill's width — the same rule `.geode` already followed. The seven-beats table's beat 5, "object
  floats above the capsule, glowing", is **not what shipped**: the pill shows the `holding` pose plus
  that numeric tally, entirely inside the outline. The reward object itself is a panel thing.
- **The panel carries every gesture that wanted room**, which is why nothing above needed the
  overhang. The reveal, the ★ rating, the voice line and the collected object are all opened-panel
  surfaces with hundreds of points to spend; the pill's job reduced to "which one session most wants
  you", which fits in 28 × 32 pt. The design's expressive load moved to the surface that could afford
  it rather than the window being grown to afford it.

### One definition of the shape

The silhouette moved out of the harness into `CreatureSilhouette` in Core, and the harness now calls it.
The plan had the view "mirror" the harness with a comment asking both to be edited together, which is the
same arrangement that let the pill fill drift from `V6Palette.ink` for several commits. A gate that
measures a copy of the shipped geometry does not gate anything. Verified behaviour-preserving: the 57
renders are byte-identical across the move.

The measurable half of the gate is now `CreatureSilhouetteTests` — nothing above the lane, `waiting`
lopsided and the other poses not, `holding` breaking both sides, `working` quietest. Mutation-checked:
collapsing `waiting` into `holding` and sending the arms upward each fail it loudly.

Still open: the aesthetic target for the pill creature — small painterly figure versus bold flat glyph —
and whether `waiting` should alternate which arm it raises. Both tracked in `docs/STYLE-SPEC.md` §11.

## The palette after the first real sprites — 2026-08-04

Conditions 3, 5 and 6 were left art-gated above, to re-run "on the first real asset batch". The gate
gained a mode that measures shipped PNGs rather than procedural shapes (`4bbc787`), the batch was put
through it, and what broke was the **palette**, not the art (`84fb35a`). The pill then rendered from
the sprites rather than from `CreatureSilhouette` (`206d5bb`).

### The luminance ladder is gone. A two-ground band replaced it

The ladder assumed a creature is drawn once and shown on **one** ground. It is drawn once and shown on
**two opposite** ones, and the same pixels have to survive both:

| Ground | Constant | Luminance |
|---|---|---|
| Closed pill | `CreaturePalette.pillFill` `#0d0d0f` | L 0.4% |
| Light paper | `CreaturePalette.paperGround` `#ece3e1` | L 78.2% |

Clearing 3:1 against both pins every species inside an **eleven-point window**:

- **L ≥ 11.2%** (`CreaturePalette.minimumLuminance`) or it disappears on the pill
- **L ≤ 22.7%** (`CreaturePalette.maximumLuminance`) or it disappears on paper

Neither bound is a round number: both are the exact luminance at which a colour hits 3:1 against its
ground, and `CreaturePaletteTests.theBandBoundsAreTheRealThreeToOneCrossings` re-derives them from the
two constants — so changing a ground forces the band to be recomputed rather than nudged. The asset
pipeline normalises each generated sprite to `targetLuminance` 17%, centred so neither ground is close
to its limit, using `scaledToLuminance` so only value moves and hue does not.

Six species cannot be six points apart inside an eleven-point window. **The ladder is gone.** The
shipped values sit within 1.1 luminance points of each other:

| Species | Value | L | On pill | On paper |
|---|---|---|---|---|
| Claude | `#a55d27` | 16.0% | 3.88:1 | 3.97:1 |
| Codex | `#3870a4` | 15.1% | 3.72:1 | 4.14:1 |
| Cursor | `#7e62a5` | 15.9% | 3.86:1 | 3.98:1 |
| Gemini | `#337a36` | 14.9% | 3.68:1 | 4.18:1 |
| Kimi | `#836e13` | 16.0% | 3.89:1 | 3.96:1 |
| OpenCode | `#9d6115` | 15.8% | 3.84:1 | 4.01:1 |

Hexes are `CreaturePalette.color(for:)`; the ratios are recomputed from those constants. *The
per-case trailing comments in `CreaturePalette.swift` are stale by up to 0.05 and should not be
trusted over this table* — gemini is annotated "L 15.2% pill 3.73 paper 4.13" and actually measures
14.9% / 3.68 / 4.18. Nothing crosses 3:1 either way, so this is an annotation defect rather than a
palette defect — but the worst contrast in the system is gemini's **3.68:1** on the pill, and the
comments are the reason a slightly rosier number has been repeated from them.

What the band retires, and what it does not:

- **Retired:** value as a species cue. Greyscale separation (condition 4) is now carried by
  **silhouette**, which is where this spec said species identity lives from the beginning — the
  ladder was only ever the placeholder-geometry stand-in for a shape difference the placeholder
  shapes could not express. Condition 5 stopped being deferred work and became the mechanism.
- **Retired:** the argument that the old ladder passed. It only ever passed because nobody asked it
  the paper question; it failed that ground outright.
- **Kept:** hue per family. It is brand recognition now, not disambiguation — which is what the
  "kept but demoted" line under *Relationship to the geode spec* already said, and the band simply
  finishes the demotion.

## Non-goals

- No shop, no currency to spend, no IAP, no paid tier. GPL closes that off and it is out of scope.
- No streaks, no daily tending, no login bonus. A broken streak is a reason to uninstall.
- No pet to feed or maintain. No battles, no party.
- No server, no accounts, no telemetry, no leaderboard. Local-first is not negotiable.
- No social comparison in v1. See "Farmability" below for why this matters more than it looks.
- Not a replacement for the session list. It is a preference over it.

## Design

### The seven beats

| # | Trigger | Pill | Panel |
|---|---|---|---|
| 1 | no session | slot of island — horizon, hill, sun | the place, with today's objects lying in it |
| 2 | `sessionStarted` | creature appears, calm, inside the outline | creature walks to its station and starts working |
| 3 | `permissionRequested` / `questionAsked` | **arm + bubble break the top edge** | creature stands, raises hand; wait timer starts |
| 4 | user answers | returns to calm | returns to working |
| 5 | `sessionCompleted`, clean | object floats above the capsule, glowing | reveal: tonal cut to dark, ★-rated object, one voice line |
| 6 | `sessionCompleted`, `isInterrupt` | creature tipped, outline intact | creature knocked over, scrap left at station |
| 7 | end of day / on demand | — | the receipt |

### The wait timer, and the grace window

This is our analogue of Cat on Chair's focus timer, and it runs the other way. Theirs counts **down** a
commitment the user made. Ours counts **up** from the moment an agent blocks.

Cat on Chair shows *"Hold to cancel — cancel within 30s for no penalty."* We borrow the grace window:
answer within **30 seconds** and the session is unpenalised. Past it, accumulated wait lands on the receipt
as idle time. Reply latency is already computed for the Stats pane; this surfaces it live.

**Amended 2026-08-04, during implementation.** The window is `RewardRarity.graceWindow`, and the
question "did this session keep inside it" is answered in exactly **one** function —
`RewardRarity.answeredWithinGrace(_:)`. Both consumers call it rather than restating it: the ★★ tier,
and `SessionStats.summary`, which builds the receipt's `answeredInsideGrace` count from
`gated.filter(RewardRarity.answeredWithinGrace)`. That is deliberate, and it is the *only* coupling
between the two: the receipt otherwise refuses to read `RewardCollection` at all, for the reason
given under "The receipt". One shared predicate is what stops "in time" meaning one thing on the
receipt and another on the object a session leaves behind; two copies would drift the first time the
rule was re-tuned.

The two surfaces still legitimately disagree on the **no-gates** case, which is not drift but
different questions. A session nobody asked anything of passes `answeredWithinGrace` vacuously, so it
earns ★★ — a tier is a judgement about a whole session, and "never needed you" is exactly what that
tier rewards. The receipt excludes it from both numerator and denominator, because a *count of
answers* that included a session with no questions would simply be false.

### Rarity

Reward magnitude attaches to properties that are expensive to fake:

| Tier | Condition |
|---|---|
| ★ | any clean completion |
| ★★ | clean, and no gate left past the 30s grace window |
| ★★★ | ★★ and ≥30 min runtime |
| ★★★★ | a shipped release (**requires the git watcher — not built**) |

A session with **no gates at all** satisfies the ★★ condition vacuously and qualifies. This is
deliberate: a run that never needed the human is exactly the outcome the tier is rewarding.

**★★★★ shipped as an unreachable case, on purpose.** It is declared so the ladder is complete and so
the next reader knows the tier is *unbuilt* rather than *broken*, and
`RewardObjectTests.fourStarsIsUnreachableUntilTheGitWatcherExists` holds that line — if someone wires
the watcher, that test is the one that tells them what else to finish. It borrows the ★★★ object pool
because it has no artwork of its own; shipping the tier means shipping its objects. Its counterpart
on the receipt, the *shipped* line, is likewise not printed. Both wait on open question 1.

**Corrected 2026-08-04, during implementation.** These tiers previously read "zero stalls **and**
every gate answered inside the grace window". That is degenerate: `stallCount` counts *gates*, not
abandonments, and `meanGateLatency` is `frozenSeconds / stallCount` — so `stallCount == 0` implies
`meanGateLatency == nil`, and the grace clause can never execute. The rule collapsed to "clean and
the agent never asked you anything", making the 30s window dead in the entire system.

It also inverted this spec's own argument. A 45-minute clean run with six gates each answered in
three seconds scored ★, *below* an unattended six-minute run at ★★ — while the design says the
user's contribution is stewardship and answering fast is what pays. The two clauses are now read as
one statement: **a stall is a gate left past the grace window**, and zero of them is what ★★ asks
for. Both clauses are live, the vacuous case is preserved, and the tiers nest.

**Inferred history is capped at ★.** Back-fill derives records from transcripts, which cannot
show gate timings — so it writes `stallCount: 0` and `meanGateLatency: nil`, and those read
downstream as *observed* facts rather than absent ones. Under the tier rules that is a vacuous
★★ pass. Measured against the real log: 80 sessions rated **39 ★★★, 39 ★★, 1 ★, 1 scrap** — the
rarest tier was the most common thing in the collection. Records therefore carry provenance, and
an inferred record cannot exceed ★: inference supports "this happened and finished", which is
exactly what ★ means, and nothing above it. Objects come from sessions the island actually
watched.

The provenance is `SessionLogRecord.isInferred`, written by `SessionLogBackfill` and read in two
places, both of which treat "we did not watch this" as *absent* rather than as *zero*:
`RewardRarity.rarity(for:)` returns `.one` early on it, and `SessionStats.summary` drops it from
`gated` so it cannot enter the receipt's answers line. It is `Bool?` rather than `Bool` because
records predating the flag must stay decodable, which is why every test is `!= true` and never
`== false`.

Records written before that flag existed keep their inflated ratings and cannot be repaired —
back-fill skips known session IDs, and re-appending loses to the log's latest-`endedAt` dedup.

An earlier limit, now closed: the log records `meanGateLatency`, not the worst gate, so "no gate past grace" is
measured by the mean. The approximation is **one-sided** — all-gates-inside implies mean-inside, so
no qualifying session is ever denied; only the reverse leaks (1s + 59s averages to exactly 30s and
passes). Tightening the threshold does not close it, since enough fast answers drag any single slow
gate under any positive bound. The real fix is recording the worst gate alongside the mean, which is
a change to what is *written* to the log. `worstGateLatency` is now recorded, and rarity reads
it, falling back to the mean for records written before it existed.

### Farmability — read this before adding anything social

It is tempting to claim reward magnitude and farmability are inversely correlated, with a merged PR as the
"unfakeable" event. **That is false for this app's user.** A solo developer on their own repo opens and
merges a PR in ten seconds with no reviewer. Commits, PRs and merges are all trivially mintable.

The only genuinely unfakeable axis is *did another human accept your work* — an external contributor's PR
merged into your repo, or yours into someone else's.

More importantly: **farmability is a function of the social dimension, not of the event.** In a
single-player local app with no leaderboard, farming is cheat codes in your own save file. The concern is
imported from competitive games and mostly does not apply. **The moment anything comparative is added, the
whole problem is inherited at once.** Any future social feature must revisit this section first.

### Species taxonomy

Six bodies, not ten. Four of the ten supported agents — Qoder, Qwen Code, Factory, CodeBuddy — are Claude
Code forks sharing its hook format, so they are colour/marking variants of the Claude body rather than
distinct species. This is truthful, not a shortcut, and it cuts sprite work by roughly 40%.

| Family | Covers |
|---|---|
| Claude | Claude Code, Claude Desktop, Qoder, Qwen Code, Factory, CodeBuddy |
| Codex | Codex CLI, Codex Desktop |
| Cursor | Cursor |
| Gemini | Gemini CLI |
| Kimi | Kimi CLI |
| OpenCode | OpenCode |

Three levels of mapping, all from data already resolved for jump-back:

- **Creature = agent.** Species from the family table; individual variation from the existing seed generator.
- **Structure = terminal / IDE.** Ghostty a single screen, Orca a roofed hall of panes, tmux a split-pane
  box, VS Code a building, JetBrains a tower.
- **Plot = workspace / repo.**

### Voice

One written line on completion, drawn from the species' personality. Roughly 12 lines per family, written
by hand — this is a writing task, not a code task. Cat on Chair gives each cat a backstory and a name, and
naming is what makes users say "mine".

**Amended 2026-08-04, during implementation.** Twelve lines per family shipped, and they shipped
**in all three locales, not English-only**. The backlog assumed flavour text was too large a
translation surface to block the mechanic and would be back-filled later; that assumption could not
survive, because `LocalizationTests.everyLocaleDefinesTheSameKeys` fails the gate on any key missing
from zh-Hans or zh-Hant. "English-only" and "routed through `LanguageManager`" cannot both hold. All
72 lines exist in en / zh-Hans / zh-Hant — 216 strings.

The split that made that cheap: `CreatureVoice` lives in Core and returns a **key**, never a string,
and the app resolves it. `CreatureVoice.lineKey(for:)` returns `nil` for anything that is not the
`holding` pose, so "never on an interrupt" is a property of the function rather than a rule its
callers have to remember. The line is drawn as an **overlay on the scene band**, not as a fourth
band, so it costs the layout no height and the session list does not move when a session finishes.

One load-bearing detail: the line is seeded `ShardSeed.value(for: "voice:" + sessionID)`. The salt
matters — `RewardObject.yield` takes the same first `SplitMix64` draw from the *unsalted* seed and
reduces it mod 4, so without the prefix the object index would be exactly the line index mod 4 and a
coin could only ever pair with three of its twelve lines.

### The receipt

`Open Island Inc.` Line items, positive in green and negative in red: clean finishes, answers inside the
grace window, shipped, interrupted, total time kept waiting, best run, TOTAL. Torn-paper treatment.

Every one of these numbers already exists in `SessionLog` / `SessionStats`, which today renders them as
medians and sparklines. **This is the same data as a thing somebody would screenshot.** It is the
cheapest high-charm item in this spec and a reasonable standalone first slice if the rest is deferred.

**Amended 2026-08-04, during implementation.** Four corrections the build forced:

- **It is not in the panel.** This spec draws the receipt as a panel beat — beat 7, "end of day / on
  demand". It shipped in the **Stats pane**, gated on `range == .today`
  (`StatsSettingsPane.swift:196`), and `Receipt` is hard-wired to `StatsRange.today` internally. The
  reason is that a receipt is a *record* and the panel is *live state*: printing today's till roll
  beside a seven-day grid would put two different arithmetics on one screen and let the paper
  contradict the numbers under it. The panel keeps the beats that are live — the reveal, the voice
  line, the object — and the receipt sits where the day is already being totted up.
- **"Every one of these numbers already exists" was not true.** `finished`, `cleanFinishes` and
  `interrupted` did. *Time kept waiting*, *best run* and *answers inside the grace window* did not
  exist anywhere and had to be derived. They now live in `StatsSummary` as `totalWaiting`,
  `longestCleanRun`, and `gatedSessions` / `answeredInsideGrace`, computed in the pass
  `SessionStats.summary` already makes — rather than in the view, which would have made the
  receipt a second stats engine free to drift from the first.
- **The TOTAL is sessions, not points.** No point value is invented. This spec has no scoring
  system and its non-goals rule out a currency, so a points column would have been an economy with
  nothing to spend it on and an arbitrary weight per line to re-tune forever. The amount column is
  instead the unit the receipt already deals in: a clean finish is `+1`, an interrupt is `-1`, and
  TOTAL is the difference. That is the reference product's `+50 / -2 / TOTAL +48` shape with the
  multiplier set to one — which is why the quantity column collapses away entirely. The lines that
  are *not* sessions (a wait, a longest run, a count of answers) therefore cannot enter the total
  and are printed below it as a memo block, which is standard till-roll grammar and keeps the rule
  "add up the signed column" true.
- **"Shipped" is not printed.** It depends on the git watcher that open question 1 defers, exactly
  as ★★★★ does. Printing a line that is permanently `0` would teach the reader the receipt lies.
  *Sessions run* takes its place, which is the item count a till roll wants anyway.

Back-filled sessions are counted and credited like any other — inference genuinely supports "this
session happened and finished", which is the whole of what those lines claim — but are excluded from
the answers line, because gate timings are the one thing a transcript cannot show. The gap is printed
rather than swallowed: the receipt says how many of the day's sessions it only inferred. The receipt
deliberately does **not** read `RewardCollection`: rarity is a rating and a receipt is a record, and
importing the ★ ladder would make the day's arithmetic move whenever the rating rule was re-tuned.

### The clarity rule

**The picture carries state. The text carries identity.**

The scene never holds a string; the strip never holds a mood. A painted creature can say *something needs
you* from across the room; it can never say *which workspace*. Cat on Chair never had to solve this — one
cat, one timer. We have up to six concurrent sessions and a support matrix of 10 agents and 15+
terminals, and the identity strip is the price of the picture.

| The picture may say | The picture must never be the only source of |
|---|---|
| something is running | which agent |
| something needs you now | which workspace / repo |
| something finished well | how long |
| something broke | what the question actually is |
| how much you've done | anything requiring a second look |

### Panel layout

Four bands: **scene → identity strip → detail for the selected session → usage footer.** Clicking a
creature highlights its cell and fills the detail band with the pending question, wait time, runtime, and
the existing `Jump to pane` / Allow / Deny actions.

### Pill layout

In a 28 × 32 pt lane detail is unaffordable, so **state is signalled by breaking the capsule's outline**.
Calm states stay inside it; states that want attention poke out of it — **downward**, since the pill's top
edge is the display's top edge. A changed silhouette registers in peripheral vision long before a face
resolves.

Beyond two concurrent sessions, stop drawing bodies: one body (the most urgent) plus dots in agent hue.
Never more than one silhouette competing.

**Amended 2026-08-04, during implementation.** "Poke out of it" is not what shipped and is not
needed. The outline breaks *sideways within the lane* — `waiting` raises one arm, `holding` two — so
every pose stays inside the capsule and the closed window was never resized. Beyond one body the pill
shows the featured creature plus the finished-today tally, reusing `.geode`'s existing rule that only
the tally may change the pill's width.

### Customisation, and full opt-out

This design **slots into preferences that already exist** rather than replacing them:

- `rightSlot` already offers `none / count / agents / geode`. The creature is a **fifth option**.
- `stateIndicator` (`animatedDot / bar / glyph / tint`) is the existing precedent that the expressive
  layer is swappable by preference.
- `sessionGroup` (`none / state / agent / project`) should drive station layout rather than inventing a
  parallel concept.
- `staleThreshold` is reused for staleness. Do not add a second threshold.

User-facing customisation: swap or recolour the species per agent; **rename** a creature; override the
structure per workspace; reorder plots by dragging; season auto-by-date, pinned, or off; night palette
follows system appearance; earned objects are draggable and their placement is the only thing that makes
two islands differ.

**Non-negotiable:** one toggle returns the panel to today's session list and the pill to `geode` or
`count`. Nothing about jump-back, hooks, permission flows or usage may depend on the island. A notch
utility that forces whimsy on a working developer gets uninstalled by exactly the users we want.

## Architecture

| Concern | Where |
|---|---|
| Species/pose model, pure | `OpenIslandCore` — new `IslandCreature.swift`, alongside `GeodeShardForm` |
| State → pose mapping | reuse `GeodeState`; add a pure `pose(for:)` |
| Creature view | `OpenIslandApp/Views` — new `CreatureView.swift`, sibling of `GeodeShardView` |
| Scene / stations | new `IslandSceneView.swift` |
| Receipt | new `ReceiptView.swift`, reading `SessionStats` |
| Pill integration | extend the existing `rightSlot` enum; no rewrite |
| Panel integration | new band inside `IslandPanelView`, behind the preference |

`IslandPanelView.swift` is already 2776 lines. The scene, strip and receipt go in **new files**; only the
composition point changes there. Do not grow that file further.

### Artwork lookup is coupled to enum `rawValue`s

**Recorded 2026-08-04, during implementation.** This was not anticipated and is the sharpest
maintenance edge the island layer added.

`Package.swift` declares the app target's resources as `.process("Resources")`. `.process`
**flattens the directory tree**: sprites live in `Sources/OpenIslandApp/Resources/Creatures/` and
world assets in `Resources/World/`, but both land at the **bundle root**. Asking for a `Creatures`
subdirectory returns `nil`. `CreatureSprite.image(named:)` therefore looks up a bare filename with
no subdirectory, and the comment there says so.

Two consequences:

- **Filenames are globally unique across every resource directory**, not just within their own.
  This is why structures and objects carry prefixes — `CreatureSprite.name(for:)` builds
  `"struct-\(structure.rawValue)"` and `"obj-\(object.rawValue)"`. Bare `terminal`, `editor`, `key`
  or `shard` would be a collision waiting for whoever adds the next resource.
- **The enum `rawValue` *is* the filename.** `CreatureSprite.name(for:pose:)` builds
  `"\(species.rawValue)-\(pose)"`, and `RewardObject`'s cases are declared to match
  `Resources/World/obj-*.png` after the prefix. Renaming a case renames a file lookup. At runtime
  that fails **silently and safely** — a missing sprite degrades to the procedural
  `CreatureSilhouette` rather than erroring, which is deliberate, because the offscreen gate links
  Core without a bundle at all.

Because the runtime failure is silent, the guard has to be a test, and it is: `CreatureSpriteTests`
(every species × pose, plus the wave frame), `CreatureStructureArtworkTests`,
`RewardObjectArtworkTests` and `IslandSceneLayoutTests` each assert that every enum case resolves to
real artwork. A rename therefore fails `swift test` rather than shipping a panel full of grey
placeholders — but only for cases those tests enumerate. **Add an enum case and its sprite in the
same change, and never rename one without the other.**

### The window-geometry risk

Breaking the capsule outline is the riskiest part of this design and it is **not a drawing change**. The
closed overlay frame is sized to the capsule (`closedNotchHeight`, `IslandPanelView.swift:333`, with
`OverlayPanelController` / `IslandChromeMetrics`). A raised arm or floating object extending beyond the
pill is clipped unless the window is larger than the pill and transparent around it.

The gesture must extend **downward** — measured, the pill's top edge is the physical top edge of the
display, so upward has no pixels at all.

This must be proven in Phase 1 before any art depends on it. If it cannot be solved cleanly, the fallback
is in-capsule-only poses, which costs the peripheral-vision property and weakens but does not kill
the design.

**Resolved 2026-08-04 — the fallback is what shipped, and it was not a fallback.** The sideways
arm-count fix contained the gesture inside the lane, so the spike (pill plan Task 7) was never run
and `OverlayPanelController` was never touched. Read this section as history: no art depends on
drawing outside the capsule, and `CreatureSilhouetteTests` asserts the containment. See "The window
overhang is not needed" above.

## Art direction and production

### Two tiers of one style

The reference style is built on a **dark subject against a light ground**. The panel reproduces that
faithfully; the pill inverts it and therefore needs its own treatment. This is not a compromise — it is
the standard grammar of the tradition being borrowed from (painted backgrounds, simplified characters
drawn over them).

| | Tier A — panel | Tier B — pill |
|---|---|---|
| Surfaces | 540pt scene, backgrounds, seasons, receipt, reveal | creatures ≤64px, structures, reward objects |
| Treatment | full painterly: flat washes, diagonal dry-brush on midground masses only, wobbly variable-width dark outlines | same palette and line language; **light mass, silhouette-first**; dark line only *inside* the shape; no interior texture at pill size |
| Authored | at panel size | **separately, at pill size** — never scaled down |

Measured palette (sampled from the reference, spring key). Winter uses the same structure with a cream
base and deep-red accent, which is why seasons are cheap:

| Role | Hex |
|---|---|
| Sky | `#7bc9a4` (teal-green — the scene is one green family, not sky-blue plus green) |
| Hills far → near | `#93c17e` · `#97b76a` · `#94ab5a` · `#90a352` |
| Contact band (darkest) | `#709458` |
| Foreground (brightest) | `#b4de6f` · `#bce080` |
| Warm neutrals | `#c4ae8e` · `#9d8f6c` · `#856a47` · `#71513c` |
| Accents | `#b73b3a` · `#ca8065` · `#739f8a` |
| Line work | `#211e12` |

Five rules derived by measuring their artwork, all of which the panel must obey:

1. **Flat washes, never gradients.** What reads as shading is a separate flat band.
2. **Directional dry-brush at ~62°, following the form, on midground masses only.** Sky and foreground
   are flat.
3. **Wobbly, variable-width dark outlines** — the strongest "not vector" signal.
4. **Type is knocked out**, not filled, so it never fights the scene.
5. **Value inversion**: foreground is the brightest area, the mid band the darkest. This is what makes
   objects pop, and it is why the greyscale test passes.

Put these in `IslandDesignPalette.swift` as a named season palette and forbid colour literals elsewhere.
Palette conformance is a lint rule, not a guideline — it is the mechanism that stops the app drifting
back to generic over twenty commits.

### Producing the assets

The pipeline demonstrated in the reference video (one dense prompt → shared canvas → overgenerate and
cull → hand to a coding agent under a no-outside-assets constraint → the agent's missing-asset manifest
becomes the next prompt) is sound and should be used. Two amendments from evaluation
(`docs/art-production-evaluation.md`):

- **Drive a generator directly rather than through Lovart.** Lovart is an orchestration wrapper over
  public models; its consistency feature is context injection rather than enforcement, and its
  transparency is generate-then-matte, which fringes exactly on wobbly painterly outlines.
- **Do not use screenshots of the reference product as generator input.** Its style was drawn by a named
  human illustrator. Brief from the measured palette and the five rules above — those are unprotectable
  ideas and are already written down here.

The Phase 0 gate runs on the **first real asset batch**, not on placeholder art, and composited on
`#0d0d0f` rather than on white.

## Build order

0. **Render harness + kill gate.** Blocking. No other task starts until it passes. Renders composited on
   `#0d0d0f`, with contrast measured rather than eyeballed, and a colour-removed pass.
1. ~~**Window geometry spike.** Prove the pill can draw *below* the capsule.~~ **Skipped** — the
   re-gate removed the need before the task came due. Nothing was drawn outside the lane, so nothing
   had to be proven. See "The window overhang is not needed".
2. **`IslandCreature` + `pose(for:)`,** pure, unit-tested against `GeodeState` transitions.
3. **`CreatureView`** at both scales, pinned in the debug scenario the way shard rendering already is.
4. **Pill integration** as a fifth `rightSlot` option, off by default.
5. **Panel scene + identity strip,** behind the preference, list mode still default.
6. **Click behaviour** — wire to the existing jump-back and collect.
7. **The receipt** from `SessionStats`.
8. **Customisation surface** in `AppearanceSettingsPane`.
9. **Voice lines,** ~12 per family.

Items 7 and 8 are independently shippable. If the gate fails at 0, item 7 still stands alone.

**This is more than one implementation plan.** Plan items **0–4** first — through the pill, which is where
all the risk lives — and re-plan 5–9 once the gate and the geometry spike have reported. Do not attempt a
single plan spanning the whole build order.

## Testing

- Pure pose mapping: unit tests over every `GeodeState` transition, mirroring the existing reducer tests.
- Rendering: pin creature output in `IslandDebugScenario` and the harness, exactly as `c186fad` did for
  shard rendering.
- Determinism: same seed → same individual, asserted.
- **Contrast, as a test not a review:** every species × pose asserts ≥3:1 against `#0d0d0f`. This is
  computable, so it should fail the build rather than a design review.
- **Greyscale separation:** the six species must remain distinguishable with colour removed.
- **Palette conformance:** no colour literals outside `IslandDesignPalette.swift`.
- Preference matrix: island on/off × each `rightSlot` × each `sessionGroup` renders without layout break.
- Opt-out: with the island disabled, the panel must be byte-identical in behaviour to today.
- Appearance-profile independence, per `e79a005` — a preference write must not change the active profile.

## Risks

| Risk | Severity | Mitigation |
|---|---|---|
| Creature illegible in a 28 × 32 pt lane on `#0d0d0f` | kills the pill half | Phase 0 gate, measured ≥3:1, judged on the worst roll |
| Species indistinguishable without hue | fails colour-blind users and degrades at pill size | Silhouette carries species; spread values deliberately; gate condition 3 tests with colour removed |
| ~~Window geometry cannot draw outside the capsule~~ **closed** | weakens the notification | Retired: the pose never leaves the capsule, so the spike was skipped. `CreatureSilhouetteTests` asserts containment |
| Art reads as generic AI output | kills the whole premise — the reference's growth came from *not* looking generated | Cull hard; palette conformance as a lint rule; the six-family taxonomy gives distinct silhouettes to aim at |
| Scene hides operational information | makes the tool worse | The clarity rule; the strip is mandatory, not optional |
| `IslandPanelView` grows unmanageable | maintenance | New files; composition point only |
| Scope sprawl into a game | never ships | Non-goals are binding; items 7/8 shippable alone |

## Open questions

1. **Git/PR watcher.** ★★★★ rarity and the "shipped" reward line depend on commits/PRs/releases, which
   are not collected today. Everything else in this spec works without it.
2. **Revenue.** Cat on Chair's $18K/month comes from a shop this project cannot have. What transfers is
   its *growth* mechanism — both hosts attribute virality to the app "not looking vibe coded", spreading
   through an Instagram post at 2M views and a Threads repost, unpaid. For a free GPL tool the currency is
   stars, word of mouth and screenshots. If actual revenue is wanted, that is a separate product decision
   and GPL makes it genuinely hard.
3. **Social dimension.** Deferred. Re-read the farmability section before designing any of it.
4. **Who draws the assets.** Evaluation (`docs/art-production-evaluation.md`) ranks a commissioned
   illustrator first on quality and licensing, and notes that purely AI-generated output is not
   copyrightable and so cannot be meaningfully licensed in this repo. Generated assets are viable for
   development placeholders regardless, and the owner's position is that a good prompt plus good
   references can carry further than that. **The cheapest way to settle it is the Phase 0 gate itself**:
   run it on a generated batch. If species clear ≥3:1 on `#0d0d0f`, separate in greyscale, and stay
   coherent across 24 poses with no hand touch-up, generation is sufficient and the question closes.

## Process notes

Design derived from two references supplied by the owner, with frames and transcripts preserved at
`~/Desktop/openisland-refs/`:

- *This Simple App Makes $18K/Month* (Starter Story) — design and business method.
- *AI Makes Pokémon with ONLY Images* (tef) — asset production pipeline.

Interactive prototypes for both bars were built and reviewed before this spec was written.
