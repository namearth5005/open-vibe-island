# The Island — Reward & Progression Mechanics

**Date:** 2026-08-01
**Status:** Design approved, not yet implemented
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

Contrast ratios against the closed pill fill `#0c0d0f` (`V6Palette.ink`):

| Colour | Role | Contrast |
|---|---|---|
| `#211e12` | the reference style's signature outline | **1.17:1 — invisible** |
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

## Phase 0 — kill gate (blocking)

**Nothing else in this spec may be built until this passes.** This mirrors the geode Phase 0 gate.

Build an offscreen render harness — same approach that produced `shard-final.png` and `geode-shapes.png` —
that draws real SwiftUI shapes to PNG at **true 28 × 32 pt composited on `#0c0d0f`** and at **64px on the
panel ground**, for all four poses across all six species, plus 20 procedural individual variations within
one species.

Pass conditions:

1. At true pill size **on the actual pill colour**, calm / asking / collectable are mutually
   distinguishable at a glance, judged on the worst roll, not the best.
2. Every species and pose clears **≥3:1 against `#0c0d0f`** as a measured number, not a judgement.
3. At 64px, all four poses are distinguishable and the six species are distinguishable from silhouette
   alone **with colour removed**.
4. No procedural individual reads as a dud or as a different species.

Known from the prototype: *working* and *knocked-over* do **not** separate at pill size. This is accepted —
an interrupted session deliberately is not asking for attention — so the pill has **three** legible states,
not six. The tipped pose is still *drawn* (beat 6 below); it is simply not required to be distinguishable
from calm. If condition 1 or 2 fails, this design does not ship in the pill and the panel-only variant is
the fallback.

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

### Rarity

Reward magnitude attaches to properties that are expensive to fake:

| Tier | Condition |
|---|---|
| ★ | any clean completion |
| ★★ | clean, zero stalls, and every gate answered inside the grace window |
| ★★★ | clean, ≥30 min runtime, zero stalls |
| ★★★★ | a shipped release (**requires the git watcher — not built**) |

A session with **no gates at all** satisfies the ★★ condition vacuously and qualifies. This is
deliberate: a run that never needed the human is exactly the outcome the tier is rewarding.

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

### The receipt

`Open Island Inc.` Line items, positive in green and negative in red: clean finishes, answers inside the
grace window, shipped, interrupted, total time kept waiting, best run, TOTAL. Torn-paper treatment.

Every one of these numbers already exists in `SessionLog` / `SessionStats`, which today renders them as
medians and sparklines. **This is the same data as a thing somebody would screenshot.** It is the
cheapest high-charm item in this spec and a reasonable standalone first slice if the rest is deferred.

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
`#0c0d0f` rather than on white.

## Build order

0. **Render harness + kill gate.** Blocking. No other task starts until it passes. Renders composited on
   `#0c0d0f`, with contrast measured rather than eyeballed, and a colour-removed pass.
1. **Window geometry spike.** Prove the pill can draw *below* the capsule.
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
- **Contrast, as a test not a review:** every species × pose asserts ≥3:1 against `#0c0d0f`. This is
  computable, so it should fail the build rather than a design review.
- **Greyscale separation:** the six species must remain distinguishable with colour removed.
- **Palette conformance:** no colour literals outside `IslandDesignPalette.swift`.
- Preference matrix: island on/off × each `rightSlot` × each `sessionGroup` renders without layout break.
- Opt-out: with the island disabled, the panel must be byte-identical in behaviour to today.
- Appearance-profile independence, per `e79a005` — a preference write must not change the active profile.

## Risks

| Risk | Severity | Mitigation |
|---|---|---|
| Creature illegible in a 28 × 32 pt lane on `#0c0d0f` | kills the pill half | Phase 0 gate, measured ≥3:1, judged on the worst roll |
| Species indistinguishable without hue | fails colour-blind users and degrades at pill size | Silhouette carries species; spread values deliberately; gate condition 3 tests with colour removed |
| Window geometry cannot draw outside the capsule | weakens the notification | Phase 1 spike before art; downward only |
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
   run it on a generated batch. If species clear ≥3:1 on `#0c0d0f`, separate in greyscale, and stay
   coherent across 24 poses with no hand touch-up, generation is sufficient and the question closes.

## Process notes

Design derived from two references supplied by the owner, with frames and transcripts preserved at
`~/Desktop/openisland-refs/`:

- *This Simple App Makes $18K/Month* (Starter Story) — design and business method.
- *AI Makes Pokémon with ONLY Images* (tef) — asset production pipeline.

Interactive prototypes for both bars were built and reviewed before this spec was written.
