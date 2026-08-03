# Creature Art — Generation Prompts

Companion to `docs/STYLE-SPEC.md`. That document is the standard; this one turns it into
prompts you can paste into an image generator, and defines what counts as a pass.

This exists to run the falsifying test in `docs/art-production-evaluation.md` §7: generate one
species × four poses from our own written spec, composite them at true size on the real pill,
and judge them blind. If they pass, the economics move toward generated art and a commission
shrinks to style-guide-plus-QC. If they fail, we have spent almost nothing to learn it.

## Two rules that decide whether the output is usable at all

**Never upload another product's artwork, screenshots, or frames to a generator.**
Image-conditioned generation on someone else's work is the legally weakest form of style
copying, it would sit permanently in the history of a public GPL repository, and it produces a
derivative rather than something we own. Everything below is written from measured values and
our own rules, which are unprotectable ideas. That is the whole point of having a spec.

**Native transparency, not background removal.** Matting a soft painted edge fringes, and every
sprite composites over a coloured ground. If the tool cannot emit real alpha, its output is a
sketch to redraw from, not an asset.

---

## 1. Style preamble

Paste this above every prompt.

> Flat vector-style character sprite, front-facing, full body, centred, on a fully transparent
> background. Hand-drawn character with a soft wobbly outline of slightly varying width. Two to
> four flat colour values only — no gradients, no gouache texture, no paper grain, no drop
> shadow, no ground shadow, no background scenery. Simple, bold, highly readable silhouette
> with generous negative space around the limbs. Cosy, friendly, calm. No text, no letters, no
> numbers, no logos, no UI, no frame, no border.

## 2. Hard geometry

The lane is 28 × 32 points — taller than it is wide, and width is the binding constraint.

> The body is tall and narrow, occupying roughly 60% of the image width and 85% of its height,
> centred with clear empty margin on every side. Arms are short and stubby and stay level with
> or below the shoulders. Nothing extends above the top of the head. Keep at least a clear gap
> between each arm and the body so the outline reads as separate shapes.

Nothing above the head is a hard rule, not a preference: the pill's top edge is the physical
top edge of the display, so anything drawn above it is off-screen rather than clipped.

## 3. Species silhouettes

Six bodies for ten agents. They must be tellable apart **from outline alone**, so each is a
different shape rather than the same shape in a different colour — that is the one gate
condition placeholder geometry could never satisfy.

| Species | Body colour | Silhouette direction |
|---|---|---|
| Claude | `#f8d7b7` | Broad rounded boulder of a body, low wide-set ears, wide planted stance |
| Codex | `#b2cbe8` | Tall narrow column, flat squared-off top, straight parallel sides |
| Cursor | `#7dc3a2` | Teardrop body rising to a single tall pointed crest |
| Gemini | `#aa99bd` | Body topped by two distinct rounded peaks, twin-lobed head |
| Kimi | `#ba7492` | Soft pear-shaped body with two long ears drooping down the sides |
| OpenCode | `#797153` | Squat wide trapezoid, flat top, short stubby limbs, heavy and grounded |

Append to the prompt, substituting both values:

> The creature's body is a single flat shape in the colour {HEX}. {SILHOUETTE DIRECTION}. The
> outline and any interior detail are very dark brown `#211e12`, used only inside the shape and
> never around its outer edge.

## 4. The four poses

State is signalled by **how many arms are out, not how far**. This is measured, not stylistic:
the lane offers at most 4.2pt above the body, so a raised arm has nowhere to go but sideways,
and a difference of degree does not survive at this size. One arm out reads as *asking*, two as
*presenting*.

| Pose | Meaning | Prompt clause |
|---|---|---|
| `working` | running, ambient | *Both arms hang down close to the body. Calm, compact, symmetrical, eyes half closed.* |
| `waiting` | blocked on you | *Exactly one arm is raised out to the side, clearly away from the body. The other hangs down. Deliberately lopsided. Alert, looking up.* |
| `holding` | done, collect me | *Both arms are raised out to the sides, symmetrical, holding a small round object between them. Pleased.* |
| `fallen` | interrupted | *The whole body is tipped over onto its side at about seventy degrees, limbs tucked in. Sleepy rather than distressed.* |

`fallen` is the only pose exempt from being distinguishable at pill size.

## 5. Output

- One sprite per prompt. **Do not** ask for a sheet — multi-subject grids drift in style
  between cells and cannot be matted cleanly.
- Square canvas, at least 512 × 512, transparent PNG.
- Generate several per pose and cull. Consistency across a set is the known weak point of every
  generator, so overgenerate and keep only what matches.
- Name files `<species>-<pose>.png`.

## 6. Panel variants

The opened panel is a *light* ground (`#b4de6f`), which inverts everything above. Pill and panel
are separately authored, never one master scaled.

> Full watercolour illustration with visible granulation and soft wet edges, richer detail, a
> face with visible eyes, on a transparent background.

Use the panel values from `STYLE-SPEC.md` §3.4 — `#766656`, `#535f6e`, `#385b4b`, `#4e4658`,
`#563342`, `#343022` — not the pill values. On the panel ground the pill values measure 1.08:1
to 2.27:1 and are invisible.

## 7. How output is judged

Drop the PNGs in a folder and run:

```
zsh scripts/creature-gate.sh /tmp/gate --sprites <folder>
```

The harness composites them at true 28 × 32 pt on the real pill fill and at panel size on the
panel ground, and prints measured contrast. Judge the PNGs at 1×, not zoomed.

**Pass conditions**, unchanged from the Phase 0 gate:

1. `working` / `waiting` / `holding` mutually distinguishable at true pill size, judged on the
   worst sprite rather than the best.
2. Every sprite clears **3:1** against `#0d0d0f`, measured.
3. All four poses distinguishable at panel size.
4. The six species stay tellable apart with colour removed.
5. The six species are distinguishable **from silhouette alone**. This is the condition the
   placeholder could never meet and the real reason to generate art at all.
6. Style is coherent across the set with zero hand touch-up.

Condition 6 is the one to watch. A generator that produces four lovely sprites in four slightly
different styles has failed, and it will be tempting to forgive it.
