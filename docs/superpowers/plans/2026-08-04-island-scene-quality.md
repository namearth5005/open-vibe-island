# Island scene quality — round 2 backlog

> **For agentic workers:** REQUIRED SUB-SKILL: use `superpowers:subagent-driven-development` to
> implement task-by-task. Each task names the domain skills to build and review with — those are not
> optional, they are the mechanism.

**Goal:** the island stops reading as five identical stickers on a landscape and starts reading as a
place with individuals in it.

**Where this came from.** Round 1 (13 tasks, 30 commits, 708 tests) built the whole island layer and
it works. Then a human looked at it running for the first time and the verdict was: the plumbing is
solid, the surface is weak. This backlog is that critique, made checkable.

The screenshot that produced it: **five identical bears, four identical sheds**, on a landscape
occupying ~70% of the pixels and carrying no information.

---

## ASSUMPTIONS (override any of these)

1. **The art is not being regenerated.** 57 PNGs shipped and passed the contrast gate. This round
   composes, animates and varies what exists. If a task genuinely needs new art it must say so and
   stop rather than quietly shipping without it.
2. **The reference is Cat on Chair**, whose charm is that the cats *inhabit* a space — different
   depths, postures, sizes — not that the art is more detailed than ours.
3. **Off by default still holds.** Every change here lands inside `islandScene == .on`. A user who
   has not opted in must see a byte-identical panel, exactly as round 1 asserted.
4. **Motion must survive Reduce Motion.** `hig-foundations` treats a cross-fade as the substitute for
   motion, not an absence of feedback.
5. The 5-plot cap (`stationCapacity`) stays. Raising it is a coordinated change across the scene, the
   strip, the `+N` badge and task 11's correspondence tests — out of scope unless a task proves it is
   the blocker.

---

## [in-progress] 1 — DIAGNOSE: is state actually reaching the picture?

**This gates everything else.** "The picture carries state" is the claim the entire feature rests
on. In the observed screenshot all five creatures appeared to be in `holding` — arms up, cradling the
orb — while the session list read *1 running, 7 done, 3 idle*.

Two very different explanations, and the fix differs completely:

- **(a) A bug.** Pose is not reaching `IslandStation`, or the running session was not among the five
  plotted. `IslandSceneView.swift:80` reads `geode.pose(for: session.id)`;
  `CreaturePose.swift:51` falls back to `.working` when no shard exists.
- **(b) Working as designed, and the design is the problem.** Four of five plotted sessions genuinely
  *were* finished, so four identical `holding` bears is *correct output* — and useless. If so, the
  real defect is that the common case (everything done, one agent) has no visual answer.

**Acceptance criteria:**
- A test that constructs sessions in all four states — running, waiting, finished, interrupted — and
  asserts `IslandSceneLayout` gives each a **distinct** pose. Not a smoke test: assert the specific
  pose per state, so a regression names which one broke.
- A test for a session the geode has never seen (no shard) pinning the `.working` fallback.
- **State the verdict, (a) or (b), with evidence.** If (a), fix it. If (b), say so plainly and record
  it — task 2 is then the real fix and this task must not paper over it.
- Report what fraction of a realistic session mix lands on each pose. If 80% of plots are `holding`
  in normal use, that is the finding, and it belongs in the report.

**Build with:** `superpowers:test-driven-development`  **Review with:** `swift-testing-pro`
**Depends on:** nothing

---

## [todo] 2 — Individuals, not repetitions: seeded per-workspace variation

The species axis is dead in practice. It maps 10 tools → 6 creatures, but a typical user runs **one
agent**, so every creature is the same bear. Meanwhile the thing that genuinely differs —
`angelshark`, `dugong`, `speed2` — is invisible in the picture.

**Acceptance criteria:**
- A creature's appearance varies **deterministically by workspace**, not by session — the same
  project looks the same tomorrow. Seed off the workspace identity, not the session ID.
- Use `ShardSeed` (FNV-1a). **Not `hashValue`** — Swift seeds `Hasher` per process, so it will not
  survive a relaunch. `CreatureVoice` already does this correctly; copy that pattern including the
  salt discipline (`RewardObject.yield` and `CreatureVoice` collide without distinct salts —
  see commit `f4498b2`).
- Five sessions of the same agent in five workspaces must be **visually distinguishable at a glance**
  — assert the derived variation differs, not merely that the function runs.
- Variation must not break the contrast gate. Whatever axis is chosen (tint, scale, accessory,
  flip), every resulting creature still clears **3:1 on both grounds** — `zsh scripts/creature-gate.sh`
  stays exit 0. Note the true worst today is **3.68:1**, not much headroom; a tint that darkens will
  fail.
- Two sessions in the *same* workspace (the observed `dugong` × 2) must still be tellable apart —
  decide how and defend it.

**Build with:** `swiftui-design`  **Review with:** `swiftui-pro`
**Depends on:** 1

---

## [todo] 3 — Composition: a scene, not a row

Currently five plots, evenly spaced, one baseline, one size. The reference's charm is inhabitation.

**Acceptance criteria:**
- Position carries meaning: whoever is **waiting on you** is the most prominent; finished sessions
  recede. Define the rule and assert it — given a mixed set, the waiting session's plot must be
  measurably more prominent (nearer front/centre/larger) than a finished one's.
- Depth: creatures sit at different distances, with **scale following depth** so nearer is bigger.
- Plots must not collide at any width from **360pt** (the `openedPanelWidth` floor) to the current
  760pt, and must not overlap the `+N` overflow badge. Assert across that range.
- Ordering stability: a creature must not swap plots because an agent changed state mid-render — the
  round-1 comment on `IslandSceneLayout.init` explains why. If prominence now depends on state, that
  tension is real: resolve it explicitly and say how.

**Build with:** `swiftui-design`  **Review with:** `swiftui-pro` + `hig-foundations`
**Depends on:** 1

---

## [todo] 4 — Scale: the subject should dominate

The hill is ~70% of the band and says nothing. Creatures are ~8% and say everything.

**Acceptance criteria:**
- Creatures occupy a materially larger share of the band height — state the before/after fraction as
  a measured number, not an impression.
- Still legible at `compact` and at the 360pt floor.
- The band's height contract is unchanged: `IslandBandLayout.height` still feeds
  `OverlayPanelController` and the two must not disagree. Round 1's whole window-sizing argument
  depends on this.

**Build with:** `swiftui-design`  **Review with:** `swiftui-pro`
**Depends on:** 3

---

## [todo] 5 — Ground the creatures in the scene

**Raised twice by the user and still open.** The creatures read as stickers pasted on a painting.
This is the single most-repeated piece of feedback across the whole project.

The background is good and the art is good — the failure is at the seam.

**Acceptance criteria:**
- Contact shadows anchoring each creature to the ground plane, scaled with depth.
- Edge treatment so the sprite's cut-out edge stops reading as a cut-out — the reference's creatures
  share the background's paper tooth and slight colour bleed.
- Colour harmony: creatures pick up a little of the scene's ambient light rather than sitting at
  full saturation against it.
- **The contrast gate still passes** — grounding must not be bought by dimming the creature into the
  background. `zsh scripts/creature-gate.sh` exit 0, and say what the new worst ratio is.
- Compare before/after by rendering both and looking. Attach what you looked at.

**Build with:** `swiftui-design`  **Review with:** `swiftui-pro`
**Depends on:** 4

---

## [todo] 6 — Motion: idle life and real transitions

**Also raised twice.** Today the only motion in the whole island is `waiting` alternating two frames
at 0.45s. Everything else is static. The reference app is alive even when nothing is happening.

**Acceptance criteria:**
- Idle motion: creatures are subtly alive when nothing is happening — breathing, sway, blink.
  Deterministic phase offset per creature so five do not pulse in lockstep. Seed it; do not use
  wall-clock modulo alone.
- State transitions animate rather than cut — a session finishing should be a visible little event,
  not a sprite swap.
- Arrival and departure: a session appearing or leaving the island animates in/out.
- **Reduce Motion**: one decision, owned by the parent, degrading to a cross-fade — not a dead
  branch on each child. Round 1 removed exactly such a dead branch (`swiftui-pro` caught it in task
  10); do not reintroduce the pattern.
- Motion must not cause the band to resize — `IslandBandLayout.height` is a contract. Assert it.
- **Cost:** the panel already rebuilds at 1Hz via `TimelineView`. Anything faster must justify itself;
  say what frame rate was chosen and why.

**Build with:** `swiftui-design`  **Review with:** `swiftui-pro` + `hig-foundations`
**Depends on:** 5

---

## [todo] 7 — Anchor the voice plate to whoever spoke

Observed floating at the far left, hanging over a structure, with no visual link to any creature. It
reads as a caption for the whole island.

**Acceptance criteria:**
- The plate points at its speaker — tail, connector, or proximity — so attribution is unambiguous.
- Never clipped by the band edge and never overlapping the `+N` badge, at every width 360–760pt and
  every scene height. Assert across that range; the leftmost and rightmost plots are the hard cases.
- Keeps its accessibility label ("workspace, line") from round 1.
- Still costs the band no height — `theLineDoesNotChangeTheBandsHeight` must keep passing.

**Build with:** `swiftui-design`  **Review with:** `swiftui-pro` + `accessibility-tester`
**Depends on:** 3

---

## [todo] 8 — Tell duplicate workspaces apart

Two rows both read `dugong`, both `Unknown`, both `<1m`. In the strip and the session list they are
indistinguishable.

**Acceptance criteria:**
- Two sessions in the same workspace are distinguishable in the identity strip.
- Whatever distinguishes them must be **stable** — not "session 1 / session 2" by arrival order,
  which renumbers when one ends.
- Localized in all three locales. `LocalizationTests.everyLocaleDefinesTheSameKeys` fails the gate on
  any key missing from zh-Hans or zh-Hant — this is the real check, `lint-strings.sh` only runs
  `plutil` for syntax.

**Build with:** `swiftui-design`  **Review with:** `swiftui-pro`
**Depends on:** 2

---

## [todo] 9 — Look at it and write down what is still wrong

Round 1 shipped `docs/DEMO-READINESS.md` on the principle that the honest inventory of what is *not*
proven is the more valuable half. This round ends the same way — and this time a human has already
proven the automated checks miss the thing that matters.

**Acceptance criteria:**
- Render the band at every scene height × {360, 520, 760}pt with a realistic mixed session set, and
  **look at the output**. Attach it.
- Update `docs/DEMO-READINESS.md`: what round 2 fixed, what it did not, what still needs eyes.
- Full gate green, `zsh scripts/creature-gate.sh` exit 0, and state the worst contrast ratio after
  tasks 2 and 5 have both moved the palette's effective appearance.
- Be explicit about anything that looked worse in a case the tests do not cover.

**Build with:** `superpowers:verification-before-completion`  **Review with:** none
**Depends on:** 6, 7, 8

---

## Known traps, carried from round 1

- **`CreaturePalette`'s trailing comments are stale** by up to 0.05. Recompute from the source, never
  transcribe the comments. True worst is 3.68:1 (gemini on pill).
- **`.process("Resources")` flattens the bundle** — filenames are globally unique and coupled to enum
  `rawValue`s. Renaming a case breaks artwork lookup; the artwork tests catch it.
- **Profile trap:** `loadDebugSnapshot` can flip `activeAppearanceProfile`. Write preferences *after*
  the snapshot, or write both profiles.
- **Known flake, not yours:** `completionNotificationHoverCancelsPendingTimedCollapse` fails ~2 in 20
  runs under load. Pre-existing, unrelated. Re-run and say so.
## You already have the art for tasks 3 and 6

**12 sprites ship today that no code path draws** — `<species>-side.png` and `<species>-walk1.png`,
for all six species. They were generated in the art round and then never wired up.

- **`side`** — a calm profile/three-quarter pose, eyes closed, arms down. This is the *"different
  body angles"* the project asked for and never got. It is what a creature at the back of the scene
  should look like, and it breaks the wall of identical front-facing bears on its own.
- **`walk1`** — mid-stride. Arrival, departure, and idle wandering.

`CreatureSprite.fileComponent(for:)` only maps `working / waiting / holding / fallen`, plus `wave2`
as the wave's second frame. Adding these means extending that mapping — and note the artwork tests
(`CreatureSpriteTests.everySpeciesAndPoseHasArtwork`) iterate `CreaturePose.allCases`, so a new pose
case is required to have artwork for **all six species** or the gate fails. All twelve files exist,
so that is satisfiable today.

**Tasks 3 and 6 must check these before asking for new art.** Assumption 1 says this round does not
regenerate artwork; this is why that assumption is affordable.
