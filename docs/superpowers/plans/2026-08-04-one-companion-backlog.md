# One companion — implementation backlog

> **For agentic workers:** REQUIRED SUB-SKILL: use `superpowers:subagent-driven-development`. Each
> task names the domain skills to build and review with — those are not optional, they are the
> mechanism.

**Spec:** `docs/superpowers/specs/2026-08-04-one-companion-design.md`. Read it first — it explains
why the five-creature island is being replaced rather than polished.

**Goal:** one well-made companion that actually moves, reacts to the session list, and shows how long
you have worked and what you have done.

**Supersedes** `2026-08-04-island-scene-quality.md`. Tasks 4b, 11b and 1c from earlier rounds remain
open human decisions and are carried into the spec.

---

## ASSUMPTIONS (override any of these)

1. **No new art.** 42 creature sprites ship today across 6 characters and 7 poses each. This round
   uses them. If something genuinely needs art that does not exist, **stop and say so** rather than
   shipping without it.
2. **The companion lives in two places, and they have different jobs.** In the *panel* it is a slim
   row that reacts to the list — glanceable, cheap, never competing for height. In its *own surface*
   (task 9) it is large, scenic and slow, and that is where the collection and the receipt live.
   Confirmed by the human 2026-08-04. The panel row must therefore stay minimal: anything that
   invites lingering belongs on the destination surface, not above a list you opened to deal with
   something.
3. **Still behind `islandScene`, still off by default.** A user who has not opted in sees a
   byte-identical panel. Round 1 asserted this and the assertions must keep passing.
4. **The pill companion is untouched** by this round. It is the strongest part of the feature and
   already works.
5. Aggregate state means the companion answers *"does anything need me"*, not *"what is session 3
   doing"*. The list answers the second question better.

---

## [done] 1 — Aggregate companion state

The one reducer: given the whole session list, what is the companion doing?

**Acceptance criteria:**
- Pure function, `OpenIslandCore`, no SwiftUI. Tests call it directly.
- The four states from the spec: **waving** (any session needs you), **working** (something running),
  **resting** (all finished), **asleep** (nothing).
- **Waving wins over everything.** It is the only state that is a request. Assert the precedence
  explicitly, including the awkward mixes — one waiting + three running must wave.
- Reuse `CreaturePose.isAskingForYou` rather than re-spelling the attention rule. Round 1's comment
  on that property explains why two spellings of one fact is how a raised hand ends up looking urgent
  and behaving calm.
- Deterministic: same list → same state, no clock dependence beyond what the session states carry.
- **Do not reuse `IslandSceneLayout`.** That type is being deleted in task 3.

**Build with:** `superpowers:test-driven-development`  **Review with:** `swift-testing-pro`
**Depends on:** nothing

---

## [in-progress] 2 — The companion row

Replace the 309pt band with a slim row: the companion, a timer, today's tally.

**Acceptance criteria:**
- Costs materially less height than the 309pt band it replaces. **State the number.**
- The companion is **large in frame** — the round-1 failure was a 58×54pt creature adrift in a 211pt
  scene. State the creature's share of the row's height as a measured fraction.
- **Timer:** how long you have worked today. `SessionStats.totalRuntime` already computes this — do
  not add a second one. Use `IslandDurationGrain`, the shared duration vocabulary; do not add a
  fourth formatter.
- **Tally:** the day's line. `SessionStats` already has `finished`, `cleanFinishes`, `interrupted`.
- Reads task 1's aggregate state. The row decides nothing about state itself.
- No duplication of the list: **no session names, no per-session rows, no agent labels.** If it says
  something the list already says, cut it.
- `IslandBandLayout.height` still feeds `OverlayPanelController` and the two must not disagree —
  round 1's whole window-sizing argument depends on this contract.
- Localized in all three locales. `LocalizationTests.everyLocaleDefinesTheSameKeys` fails the gate on
  any missing key; `lint-strings.sh` runs `plutil` for syntax only and cannot see this.

**Build with:** `swiftui-design`  **Review with:** `swiftui-pro` + `hig-foundations`
**Depends on:** 1

---

## [todo] 3 — Remove the scene layer

Delete what the companion replaces, now that nothing renders it.

**Acceptance criteria:**
- Removed: `IslandSceneLayout` and its five stations, `IslandIdentityStripView`,
  `IslandDetailBandView`, `CreatureStructure` and the terminal→building mapping, and the scene
  background assets that nothing else uses.
- Their tests go with them — but **read each test first**. Any that pins behaviour the companion
  still has (the attention rule, duration formatting, localization parity) must be **re-pointed, not
  deleted**. Report which you kept and where they went.
- No orphaned resources: a sprite or PNG nothing references is dead weight in the bundle. List what
  you removed.
- `CreatureSpecies` survives — task 4 turns it into the companion roster.
- Full gate green after removal.

**Build with:** none  **Review with:** `swiftui-pro`
**Depends on:** 2

---

## [todo] 4 — Choose your companion

Six characters ship. Make them a choice instead of an agent taxonomy nobody could perceive.

**Acceptance criteria:**
- A preference in `AppearanceSettingsPane` picking one of the six. Match the pane's existing idiom.
- **`CreatureSpecies(tool:)` stops deciding.** The mapping is what made every creature identical for
  a single-agent user; it must not survive as a silent fallback.
- Persisted, and surviving a relaunch. **Profile trap:** `loadDebugSnapshot` can flip
  `activeAppearanceProfile`, so a preference written *before* it lands in the wrong profile — write
  after, or write both profiles via `updateAppearancePreferences(for:)`.
- Default is a deliberate choice, not the first enum case. Say which and why.
- The pill companion follows the same preference — one individual, two scales, per the spec.
- All six clear the contrast gate. `zsh scripts/creature-gate.sh` exit 0; true worst today is
  **3.68:1** against a 3:1 floor, so headroom is thin.

**Build with:** `swiftui-design`  **Review with:** `swiftui-pro`
**Depends on:** 3

---

## [todo] 5 — Make it actually move

**This is the ask.** Today the only motion in the entire feature is `waiting` alternating two frames
at 0.45s. "Really well-made and actually moves" is the whole point of going to one companion — the
budget is no longer divided six ways.

**Acceptance criteria:**
- Idle life: breathing, sway, blink — alive when nothing is happening.
- State transitions animate rather than cut. A session finishing should be a visible little event.
- The wave is unmistakably the attention behaviour and reads differently from idle motion. This is
  the one signal that must never be missed.
- **Unused art check first:** `<species>-side.png` and `<species>-walk1.png` ship for all six
  characters and **no code path draws them**. `side` is a calm profile pose; `walk1` is mid-stride.
  Check whether these give you transitions and depth before asking for anything new.
- **Reduce Motion:** one decision, owned by the parent, degrading to a cross-fade — not a dead branch
  on each child. Round 1 introduced exactly such a dead branch and `swiftui-pro` caught it; do not
  reintroduce the pattern.
- **State the frame rate and defend it against battery.** The panel rebuilds at 1Hz today; anything
  faster must justify itself.
- Motion must not resize the row. Assert it.

**Build with:** `swiftui-design`  **Review with:** `swiftui-pro` + `hig-foundations`
**Depends on:** 4

---

## [todo] 6 — Ground the companion

**Raised three times by the human and never fixed.** The creature reads as a sticker pasted on, not
something sitting in the interface. With one companion there is finally budget to do it properly.

**Acceptance criteria:**
- A contact shadow anchoring it to whatever it sits on.
- Edge treatment so the sprite's cut-out edge stops reading as a cut-out.
- It picks up a little of the surrounding surface rather than sitting at full saturation against it.
- **Grounding must not be bought by dimming it into the background.** `zsh scripts/creature-gate.sh`
  exit 0, and state the new worst ratio.
- Render before/after at the real drawn size and **look at both**. Attach what you looked at.

**Build with:** `swiftui-design`  **Review with:** `swiftui-pro`
**Depends on:** 5

---

## [todo] 7 — The companion speaks

72 voice lines × 3 locales already ship. Round 1 hung the plate at the far left of the band with no
link to any creature; with one companion, attribution is no longer ambiguous.

**Acceptance criteria:**
- Reuses `CreatureVoice` unchanged. **Do not re-seed or re-key** — the `"voice:"` salt is
  load-bearing (`RewardObject.yield` draws from the same unsalted seed; see commit `f4498b2`).
- Shown on clean completion, never on an interrupt.
- Never clipped, at every panel width **360–760pt**.
- Keeps its accessibility label from round 1.
- Costs the row no height.

**Build with:** `swiftui-design`  **Review with:** `swiftui-pro` + `accessibility-tester`
**Depends on:** 5

---

## [todo] 9 — The companion's own place

**The destination surface.** Confirmed as direction by the human. Everything above lives in the panel
and must stay out of the way; this is the opposite — somewhere you *go*, where the companion is large
and properly animated and nothing competes with it.

This is what the reference product actually is: you open it to look at your companion. The panel row
is the glance; this is the visit.

**It is also the right home for two things currently mounted awkwardly:**
- **The receipt** — round 1 put it in the Stats pane gated on `range == .today`, which was the least
  bad option available at the time. It is a printed daily record and it belongs somewhere you visit.
- **The collection** — `RewardCollection` is built and has no home at all. Objects accumulate and the
  user has never seen them.

**Acceptance criteria:**
- A surface the user can open deliberately — decide window vs tab vs sheet and defend it against how
  macOS menu-bar utilities usually do this.
- The companion is **large**. The round-1 failure was a 58×54pt creature adrift in a 211pt scene; the
  point of a destination is that the subject dominates. State its share of the frame.
- The receipt moves here from the Stats pane. **Read `StatsSettingsPane.swift:196` for why it was
  gated on `.today`** — `Receipt` is hard-wired to `StatsRange.today`, so it must not end up beside a
  seven-day figure it can contradict.
- The collection is shown — what has been earned, and what has not.
- Opening it must not disturb the panel or the pill.
- Localized in all three locales; `everyLocaleDefinesTheSameKeys` fails the gate on any missing key.

**Build with:** `swiftui-design`  **Review with:** `swiftui-pro` + `hig-foundations`
**Depends on:** 6, 7

---

## [todo] 8 — Look at it and say what is still wrong

Round 1 shipped `docs/DEMO-READINESS.md` on the principle that the honest inventory of what is *not*
proven is the more valuable half. **This round exists because a human looked at the built thing and
found the design unsound — something no test caught.** So this task is not optional.

**Acceptance criteria:**
- Render the companion row in all four aggregate states × {360, 520, 760}pt and **look at it**.
  Attach it.
- Rewrite `docs/DEMO-READINESS.md` for the companion design; the island-scene sections are obsolete.
- Full gate green, `zsh scripts/creature-gate.sh` exit 0, worst contrast stated after task 6.
- **Say plainly whether it is actually better** than the five-creature band, and what still is not.

**Build with:** `superpowers:verification-before-completion`  **Review with:** none
**Depends on:** 7, 9

---

## Known traps

- **`CreaturePalette`'s trailing comments are stale** by up to 0.05. Recompute from source; true
  worst is 3.68:1 (gemini on pill).
- **`.process("Resources")` flattens the bundle** — filenames are globally unique and coupled to enum
  `rawValue`s. Round 1 lost 4 sprites to `openCode` vs `opencode` casing.
- **Profile trap:** write preferences *after* `loadDebugSnapshot`, or write both profiles.
- **Two known flakes, neither yours.** Both are load-dependent and pre-existing:
  `completionNotificationHoverCancelsPendingTimedCollapse` (~2 in 20 runs), and
  `CodexAppServerTimeoutTests.swift:30` `sendRequestThrowsTimeoutWhenAppServerNeverReplies` (1 in 15),
  which guards a 0.1s timeout with a 2.0s wall-clock budget and trips when the suite takes 11s
  instead of the usual 2-7s. Re-run and say so.
- **`lastActionMessage` is never rendered.** Anything a user must see has to be in the view.
- **Baseline:** 720 tests in 74 suites, green at `c7204da`.
