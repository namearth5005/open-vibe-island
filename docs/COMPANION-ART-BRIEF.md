# Companion art brief — measured from full-resolution reference

**Supersedes the art-direction sections of `STYLE-SPEC.md`.** That document was written from a
118×272 crop of a video composite; this one is measured from 38 App Store screenshots at 1320×2868.
Several of its conclusions about medium were wrong and are corrected here. Its *contrast* work — the
two-ground constraint, the luminance band, the pill gate — stands unchanged and still binds.

**Subject: dogs, not cats.** The reference is a cat product. We are building a dog companion. The
style below is a set of unprotectable, measurable qualities — medium, mark-making, palette, ground.
Do not reproduce their characters, their compositions, or their named items.

---

## What the medium actually is

The single most important correction. This is **coloured pencil / wax crayon on textured paper**.
Not gouache, not watercolour, not vector.

| Property | Specification |
|---|---|
| **Mark** | Individual strokes stay visible. Fur is *scribbled loops*, not a filled shape. Upholstery is directional hatching. Nothing is a flat fill. |
| **Outline** | Mostly absent. Forms separate by texture and value. Where a line exists it is a crayon line in a **related hue** (a terracotta contour on a pink chair), and it breaks, thickens and skips. **Never a uniform contour, never black.** |
| **Ground** | Off-white paper with visible fibre. Paper tooth shows *through* every stroke — the texture is under the art, not layered on top. |
| **Edges** | Soft and slightly ragged. Colour stops short of the line in places and runs past it in others. |
| **Confidence over precision** | The reference's cat is nearly abstract — a scribble that reads as fur — and it works. **Looseness is the style.** Refinement is the failure mode. |

## Palette

Muted and warm. Nothing saturated, nothing pure, no black.

| Role | Character |
|---|---|
| Ground | Off-white paper, warm |
| Primary | Sage green, olive |
| Warm accent | Terracotta, brick, dusty rose |
| Cool accent | Dusty purple, faded teal |
| Darks | Warm charcoal — never `#000` |

Contrast still binds: every companion value must clear **3:1 on both grounds** (near-black pill,
light paper). See `CreaturePalette` and `scripts/creature-gate.sh` — that gate is not negotiable and
the current worst is 3.68:1, so headroom is thin.

## What is painted and what is not

The correction that matters most for implementation. The reference is a **mix**, and copying the
wrong half is expensive:

- **Painted** — the room, furniture, rug, objects, the companion. This is where all the craft goes.
- **Conventional UI** — reward cards are clean off-white sheets with rounded corners, a solid green
  button, plain body copy in a rounded sans. Ordinary components.
- **Hand-lettered** — only three things: the timer numerals, the primary action word, and the nav
  labels.

**We do not need to letter our interface.** We need the art to be a real medium and the UI to
recede.

## Composition

- The companion comes to **a place** — a seat, a mat, a spot. The place persists across themes; only
  its form changes.
- Before a session the place is **empty**. The empty state is a promise, not a blank.
- Objects are a **vignette**, loosely arranged, with generous paper around them. Not a scene that
  fills the frame.
- One small persistent object (theirs is a framed picture) anchors identity in the same position.

## Voice

Cheap, high-charm, and entirely unprotectable as a *technique*:

- The companion has a **name** and speaks in first person.
- Rewards are **named with flavour text** — a noun plus a wry line.
- Failure is **gentle and specific**, never a penalty screen.
- A **commitment device** is printed on the focus surface itself.

Write our own. Do not reuse theirs.

---

## Generation prompts

For an image model. Generate on a **shared canvas** as a sprite sheet so the set stays consistent,
then cull — the approach `docs/art-production-evaluation.md` already recommends.

### Base style string

> Children's-book illustration in **coloured pencil and wax crayon on textured off-white paper**.
> Visible individual pencil strokes; fur drawn as loose scribbled loops. No outlines, or only a
> broken crayon line in a related warm hue — never black, never uniform width. Paper grain shows
> through every stroke. Muted warm palette: sage, terracotta, cream, dusty purple, warm charcoal.
> Soft ragged edges, colour slightly off-register from any line. Loose and confident, not refined.
> Flat lighting, no gradients, no gloss, no digital airbrush.

### Subject — the dog

> A small round friendly dog, front-facing, sitting. Simple: two dot eyes, a small nose, soft ears.
> Nearly abstract, built from scribbled strokes rather than clean shapes. Full body, centred,
> isolated on plain paper background, generous margin.

### Pose set (one canvas, six cells, consistent character)

| Cell | Prompt suffix |
|---|---|
| working | `…sitting calmly, facing forward, paws down` |
| waiting | `…sitting, one front paw raised in a small wave, head tilted, alert` |
| holding | `…sitting, holding a small wrapped gift in both front paws` |
| resting | `…curled up asleep, eyes closed, tail tucked` |
| side | `…seen from the side, standing, tail up` |
| walking | `…mid-stride, walking, one paw forward` |

### Rejection criteria

Cull anything with: a uniform outline of any colour · flat unmodulated fill · glossy or airbrushed
highlights · black used anywhere · a symmetric machine-drawn face · sharp vector edges · visible
digital-brush repetition.

### Acceptance gate

`scripts/creature-gate.sh` must exit 0 — every sprite clears 3:1 against both the near-black pill
and light paper. Art that fails the gate is not shipped regardless of how good it looks at size.

---

## Provenance

Reference screenshots are held outside the repository for study. **No reference imagery ships here**,
and this brief is written from measured, unprotectable properties — medium, palette, mark behaviour
— rather than from their artwork. The subject is deliberately different.
