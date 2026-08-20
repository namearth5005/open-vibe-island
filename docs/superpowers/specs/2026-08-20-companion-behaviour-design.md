# Companion behaviour design

Date: 2026-08-20
Status: design, approved for planning
Branch: `feat/companion-pill`

## What this covers

How the companion animal in the closed pill behaves — what it reacts to, when it
moves, and what it must never do. It does not cover art production; that is
recorded separately in the reference corpus at `~/Documents/openisland-refs/`.

The art already exists. `CompanionPillView` renders a twelve-frame loop and is
wired to a `showCompanion` preference, off by default. What does not exist is any
reason for it to move at a particular moment. Today it animates whenever
`mode != .idle`, which is a placeholder and — per the evidence below — actively
wrong.

## The problem with what we shipped

The current view wags continuously for as long as any session is running. Peripheral
attentional capture is triggered by motion **onset**, involuntarily and bottom-up,
and it fires even when the motion is irrelevant to the task. Every loop restart is
a fresh onset. A companion that loops all day spends a developer's attention
continuously in exchange for no information — a cost they cannot articulate and
will eventually resolve by turning the feature off.

Continuous idle motion is therefore the first thing to remove.

## What the companion is

**A colleague, not a supervisor, and not a pet.**

It reacts to what the *agents* are doing. It never reacts to what the *user* is
doing, has not done, or has failed to keep up. This single rule is what separates
this design from every habit-forming companion in the consumer market, and it is
also the divergence from the app that inspired it.

*Cat On Chair* is built for presence: you are at the desk, the cat is on the chair,
for twenty-five minutes. Open Island is the opposite situation. You start agents
and walk away. You come back to find out what happened. The companion's job is not
to sit with you — it is to have been watching while you were gone.

## Evidence the design rests on

Attachment to a companion that demands nothing is demonstrated, not hypothetical.
Sung, Guo, Grinter & Christensen studied 30 Roomba households (Ubicomp 2007): 21 of
30 gave it a name, 18 believed it had "intentions, feelings, and unique
characteristics", three listed it as a household member. A Roomba cannot be fed,
cannot die, and asks for nothing.

The mechanism matters more than the result. Owners "latched onto the randomness of
Roomba's movement … as being something that triggered an expression of
personality", reading behaviour like bumping the same wall as character because it
was "different from the routine movements of machines".

**We get that mechanism for free, with a real signal underneath.** Agent sessions
stall, succeed, request permission, and thrash. A companion that renders that
faithfully is doing what the Roomba did accidentally. We do not need to invent
unpredictability; we need to avoid smoothing away the unpredictability we have.

Two supporting findings:

- Animal Crossing players (Tong et al., CHI PLAY 2021) named "no anxiety about
  damaging the relationship" among their top reasons for feeling more warmth from
  NPCs than from human players. A relationship that cannot be damaged is more
  valuable, not less.
- Guilt-based retention actively costs users: broken streaks suppress engagement
  below baseline. Obligation is not merely distasteful in a work tool, it is
  counterproductive.

Two mascot programmes independently converged on the primary constraint. Cameron
McEfee, who ran GitHub's Octocat programme: "Having found this quality to be
detrimental to the likability of other mascots, notably Clippy, I modified our
guidelines to require that the Octocat must never speak, instead showing emotion
through context, action, and expression." Mailchimp's guide says the same of
Freddie. Expression is permitted; utterance is not. A character that emotes makes
no truth claim and cannot be wrong.

### Why this is not Clippy

Clippy's failure is usually mis-attributed to its animation. The documented cause
is false-confidence *inference*: Horvitz's Lumiere project built a Bayesian model
of user intent, and shipping Office replaced it with a cruder rule-based system
specifically so it would trigger more often. The intrusiveness was a deliberate
product decision.

Our companion infers nothing. A permission request is a ground-truth event
arriving over the bridge socket. We are not tuning a confidence threshold; we have
removed the variable. **This is the property to protect: the moment the companion
expresses something we had to guess at, we are back in Clippy's problem space.**

One caution carried forward: Clippy tested *well* with general audiences and was
rejected by technical users. General delight is not evidence for this feature. It
has to be judged by developers.

## Behaviour

### States

The pose is the readout. If the companion's pose does not encode state, it is
decoration sitting next to a status display, paying attention-rent for no
information — and that is the version that gets removed. Clarus the dogcow earned
forty years of affection by living *inside* the page-orientation preview, where
the character was a by-product of conveying information.

There are **three** resting poses. Completion is deliberately not a fourth: it is a
transient beat, after which the companion settles into whichever resting pose the
remaining sessions call for. Giving "completed" its own persistent pose would mean
the pill shows a stale fact — a session that finished an hour ago is not current
state, and a pose that lingers stops being a readout.

| Session state | Resting pose | Motion on entry |
|---|---|---|
| No sessions | Curled, asleep | — |
| One or more running | Standing, alert | Brief |
| Needs approval or answer | Sitting up, looking at the user | Brief, largest amplitude |
| A session completed | *(transient)* → settles to curled or alert | Brief |

The companion is indifferent to **count**. Twelve running agents and one running
agent look identical. Quantity is the `×12` badge's job, which it does well and a
drawing does badly. Encoding aggregate mood across N sessions would also require
inferring something, which rule 3 forbids.

### Motion policy

Motion is the scarcest resource in the design. It is spent in exactly two ways.

**Transitions.** A brief animation on state change, with amplitude scaled to how
much the change deserves a look: needs-approval > completed > started. Never
animate in response to something the user just did themselves.

**The hello-wag.** Rare, small, unprompted motion at *non-periodic* intervals. It
fires from **any** resting pose, not only the sleeping one — a curled companion
shifts in its sleep, an alert one flicks an ear. "None at rest" in the table above
means no *looping* motion; it does not mean frozen. This is the one concession to
aliveness and it is load-bearing: a thing that
moves only when poked is a control; a thing that sometimes moves for no reason is a
creature. Qoobo's specification is the model — "it occasionally wags just to say
hello."

These two requirements appear to conflict with "idle must be still". They do not.
The tension resolves on **amplitude and periodicity, not presence**. A 1.5-second
loop running all day is the tax. A small movement every few minutes at random
intervals costs almost nothing in attention and is the whole difference between an
icon and an animal. Rare, small, arrhythmic.

A single idle loop becomes consciously noticeable at roughly ninety seconds (craft
convention, not research). The companion is visible for eight hours. Nothing may
repeat on a detectable period.

### Timing

**Reactions must render within 140 ms of the event reaching the app.** Michotte's
launching effect — the perception that one event caused another — collapses beyond
roughly this delay. Past it, a reaction stops reading as response and starts
reading as playback, which forfeits the contingency that makes the companion feel
alive.

This is a constraint on the bridge → `AppModel` → view path, not on the art, and it
is the highest-value thing in this document to get right.

### Gaze

With no click channel, gaze is the primary aliveness signal and the cheapest — a
pupil is a few pixels. It must be *accurate*: in animacy studies, detection fails
once heading deviates more than about 30° from the true target. Approximate gaze
does not land. If the companion looks at something, it must actually look at it.

Gaze is deferred to a later phase; the current art has fixed eyes. Recorded here so
the art commissioned next is drawn with a separable eye layer.

## Hard rules

Violating any of these is the failure mode, not a rough edge.

1. **Never speaks.** No speech bubbles, no first person, no copy in its voice.
2. **Never blocks.** Zero pixels between the developer and any action.
3. **Never infers.** Ground-truth bridge state only.
4. **Never editorialises about the user.** No streaks, no "idle for 20 minutes", no
   praise for productivity, no reference to absence.
5. **Never degrades.** No death, no decay, no state that worsens while away.
6. **Neutral on failure.** When something breaks the companion goes neutral — not
   sympathetic, not sad. A dejected animal after a failed build reads as commentary
   on the developer.
7. **Convenient seams.** The existing off switch, plus honouring reduce-motion
   unconditionally. Disabling the companion must lose no information — if it does,
   it is load-bearing rather than optional.
8. **Escalation is silent.** An unanswered approval must not grow larger animation
   or nag.

## Architecture

Small, and deliberately so.

- `CompanionPose` — an enum of the three resting poses (`sleeping`, `alert`,
  `attending`). Pure, derived from `surfacedSessions` by the same rule that
  produces `islandClosedMode`. Testable without a view. Completion is not a case;
  it is signalled separately as a transient event so the pose can settle.
- `CompanionPillView` — renders a pose, plus transition and hello-wag motion.
  Owns no session knowledge.
- `AppModel.companionPose` — the derivation, alongside `islandClosedMode`.
- Assets — one still per pose, plus short transition sequences, full-canvas and
  pre-registered so the view needs no per-frame offsets.

The view already exists and needs the state input; the derivation is a computed
property beside one that already does nearly the same job. No new subsystem.

## Out of scope

- **Gifts, trash, collection, currency, furniture.** The reward-mechanics spec of
  2026-08-01 is a product direction needing its own decomposition. Nothing here
  depends on it.
- **The 44-frame entrance.** The full arrival sequence requires rigid-body plus
  trajectory decomposition rather than a static base. Phase two.
- **Room scenes.** The companion on furniture against a background is a different
  surface from the pill.
- **Naming the companion.** Cheap and effective, but it is a product decision.

## Risks

**The art may not carry four distinct poses at 28×32.** Measured: a light-bodied
companion stays legible at that size and a dark one does not. Not yet measured:
whether *curled* is distinguishable from *standing* at 28 pixels. `d4-curl` already
failed this test in the dark set — it read as an amorphous blob with no species
information. Verify by rendering each candidate pose at true size before
commissioning the set.

**140 ms may not be achievable** through the existing bridge path. Measure before
building around it. If it cannot be met, contingency is lost and the companion
falls back to being a state display — still worth having, but the aliveness claim
should then be dropped rather than asserted.

**We cannot verify appeal ourselves.** The Clippy history says general audiences
are the wrong judges. This needs developers looking at it in a real menu bar for a
day.

## Testing

- `CompanionPose` derivation: unit tests over session fixtures, mirroring the
  existing `islandClosedMode` tests.
- Reduce-motion: assert no animation is scheduled when the accessibility setting
  is on.
- Legibility: render every pose at 28×32 on `#0d0d0f` and confirm species reads.
- Latency: measure event-to-render and assert the 140 ms budget.
