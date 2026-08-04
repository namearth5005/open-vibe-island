# One companion — design

**Status:** supersedes the island scene layer built in round 1 and the round-2 quality backlog.
Written 2026-08-04 after seeing the built island running and judging the design unsound.

---

## The decision

**One creature, not one per session.**

A single well-made companion that is genuinely animated, reacts to what the session list is doing,
and shows how long you have worked and what you have done.

## Why the previous design failed

Round 1 built it correctly and the tests prove it. Looking at it running proved the *design* wrong,
which no test could have caught.

**The band duplicated the list and lost.** At 760pt the band cost **309pt** of vertical space (211
scene + 64 identity strip + 34 detail band) to say which sessions exist, what agent each is, and what
state it is in. The session list directly beneath said the same three things — and its **12pt
coloured dot was more legible than the entire 211pt meadow.** Twenty-five times the space, less
information delivered.

**Three structural consequences, all observed:**

1. **The species axis was dead.** Ten tools mapped to six creatures, but a typical user runs *one*
   agent. Every creature was the same bear. The one axis that genuinely varied — the workspace —
   was invisible in the picture.
2. **80% of plots landed on one pose.** Measured, not guessed: of the observed mix, 4 of 5 plots and
   10 of 11 sessions were `holding`. Half the pose vocabulary was unused, and the 5-plot cap was not
   the constraint — no choice of five could have done better.
3. **The one distinction that was drawn could not be read.** `working` and `holding` were the same
   silhouette in the same posture, separated by paw position and a ~10px orb in a 58×54pt box.

**And the frame was scaled without the subject.** Widening the panel 540 → 760 made it worse: the
creature box is fixed at 58×54pt, so the gaps between neighbours grew from ~62pt to ~112pt and the
share of width that was actually creature fell from 54% to 38%. The hill got grander; the bears did
not.

**Root cause.** The reference product is a *destination* — you open it to look at your cat, and
nothing competes with the cat. Open Island's panel is a *tool* — you open it because an agent needs
you. Putting a destination inside a tool made both worse: the scene was too cramped to be charming,
and it pushed the useful part down the screen.

Every symptom — flat blending, no animation, identical creatures — was downstream of that.

## What one companion fixes

- **No duplication.** The cat does not represent sessions, so it cannot lose to the list at a job it
  was never doing. It *reacts* to the list.
- **The animation budget concentrates.** One character animated well is reachable. Six species × N
  poses animated well was not — and "really well-made and actually moves" was the ask.
- **One identity across surfaces.** The 28pt companion in the notch and the larger one in the panel
  are the *same individual*, not two instances of a taxonomy. That is a far stronger character.
- **Space.** One slim companion row instead of 309pt.

## What survives

Everything built in round 1 except the scene composition:

| Kept | Now used for |
|---|---|
| 42 creature sprites, 6 characters | **Choose your companion** — a preference, not an agent taxonomy |
| `CreaturePose` | Aggregate state, not per-session state |
| `CreatureVoice` (72 lines × 3 locales) | The companion speaks |
| `Receipt` + `SessionStats` | **"What you have done"** — already exactly this |
| `SessionStats.totalRuntime` | **The timer** — no new data needed |
| `RewardObject`, `RewardCollection` | What accumulates |
| `ShardSeed` / `SplitMix64` | Deterministic idle phase, voice, rewards |
| `CreaturePalette` + contrast gate | Unchanged; still the legibility floor |

## What is removed

- `IslandSceneLayout`'s five stations and the landscape band
- `IslandIdentityStripView` — the list already names sessions
- `IslandDetailBandView` — the list already carries detail
- `CreatureStructure` (terminal/IDE → building) — 5 of 6 rows read `Unknown` in practice
- `CreatureSpecies(tool:)` as a *mapping*; the enum survives as the companion roster

## The companion's behaviour

The cat reads **aggregate** state, so its job is unambiguous at a glance:

| List state | Companion |
|---|---|
| any session waiting on you | **waves** — the single attention-getting behaviour |
| something running | working, idle-animated |
| all finished | resting with the day's reward |
| nothing | asleep |

The precedence matters: waving must win over everything, because it is the only state that is a
request. This is the same argument `CreaturePose.isAskingForYou` already encodes.

## Open questions for the human

1. **Placement.** The companion sits in the panel near the list. Whether it *also* gets a larger
   destination surface (its own window, where the collection and receipt live and it can be scenic)
   is a separate call — the panel version does not depend on it.
2. **Idle motion cost.** The panel already rebuilds at 1Hz via `TimelineView`. Genuine animation
   wants more. The frame rate has to be chosen against battery, and stated.
3. **Carried forward, still undecided:** `4b` (deselect does not survive an agent event), `11b` (only
   relevant if any capped scene returns), `1c` (`fallen` is close to unreachable — interrupt is not a
   `SessionPhase` and back-filled shards never fracture).

## Non-goals

Unchanged from the original spec: no currency, no shop, no IAP, no telemetry, no accounts, nothing
that breaks local-first. The companion is not a game and there is nothing to spend.
