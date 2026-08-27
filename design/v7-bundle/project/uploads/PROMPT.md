<!-- PASTE EVERYTHING BELOW THIS LINE INTO CLAUDE DESIGN -->
<!-- Attach all 10 images from the `attach/` folder in the same message. -->
<!-- In Claude Design, first select the project: "Cat On Chair — design system" -->

Design **Open Island**. Work against the tokens and components in the selected
design system — do not invent a new palette or type scale; the system already
carries the colour, type, rhythm, the seat, the room, the paper slip, the
companion and the plain card/row.

Ten reference images are attached. They are cited **by filename** throughout —
`screen-home.jpg`, `char-black-cat.jpg` and so on. Read each one before designing
the section that cites it.

Two things govern everything and are the most common way this brief goes wrong:

1. **The collage is content, not chrome.** Art is torn paper and crayon; functional
   UI is plain, light and unremarkable. Charm and speed never share a surface.
   Terminals and Inbox are plain cards. Pet is the room.
2. **The seat is the contrast device.** The character never reads against the wall
   or floor — a saturated block with a clashing drawn contour behind it does that
   work.

Deliver the five items in the Deliver section at the end. Start with the four tabs.

---


---

Design **Open Island**, a macOS panel that hangs from the MacBook notch and acts as
an ambient control surface for developers running 3–10 AI coding agents (Claude
Code, Codex, Cursor, Gemini) across many terminals at once. It floats above
whatever they already run; it is not an IDE and not a terminal.

The differentiator is a companion character that works as a **concierge**: it reads
the agents' permission prompts and questions, auto-handles routine ones according
to the user's rules, compresses the rest into one-tap decisions, and escalates only
what genuinely needs a human. Its visual state is a truthful reflection of how the
fleet is doing — never a game demanding attention.

Audience: developers who live in dark terminals, are allergic to manipulative
gamification, and genuinely love charm when it is earned.

## The surface — exact

- **Expanded panel: 560 × 560pt maximum.** Content must stay **46pt clear of the
  left and right edges** — the notch shape masks 22pt each side, plus 24pt of
  breathing room. Do not design narrower; the geometry is fixed.
- **Collapsed pill:** a slim rounded shape in the notch, roughly 180 × 32pt, of
  which the character occupies about **28 × 32pt**. Design this too.
- The default view must be readable in under two seconds.

## Art direction — this is the whole brief

The reference is **Cat On Chair**, an iOS focus timer. The client owns it. Study the
attached screens closely; the governing rule is not obvious and most people get it
backwards.

**`screen-home.jpg`** — their home screen. A cream paper card floats on a textured
green ground. Navigation is **four hand-lettered words in the four corners**
(Collect, Settings, Stats, Shop) — no tab bar. The clock is hand-drawn numerals.
The one control on screen is the word **"Start" inside a scribbled blue ellipse** —
drawn around the word, not a button.

**`screen-tasklist.jpg`** — their todo list, sound mixer and stats. **Plain white
rounded cards. Ordinary rows, checkboxes, sliders, a system calendar, a segmented
control.** No collage, no hand-lettering, no paper grain inside them.

> **THE RULE: the collage is content, not chrome.**
> Every piece of *art* — the character, the room, furniture, achievement cards,
> reward slips — is torn paper, crayon and soft pastel. Every piece of *functional
> UI* — lists, settings, pickers, stats — is plain, light and unremarkable, sitting
> on the textured ground. Charm and speed never share a surface.

Apply that literally: **Terminals and Inbox are plain cards. Pet is the room.**

**`room-pink-sofa.jpg`** — the second rule: **the seat is the contrast device.** The
character never reads against the wall or the floor; the furniture behind it does
that work. Generalise it — anything that must be read gets a saturated block behind
it with a contour drawn in a *clashing* hue.

**`room-black-cat.jpg`** — where the hand belongs: headline type and the room.
Saturated wall, checkered dark floor, hard horizon, drawn contour around the sofa.

**`screen-receipt.jpg`** — a torn paper slip at an angle, itemised, gains in green,
losses in red, a bold TOTAL. Use this form for the weekly recap.

**`screen-reward.jpg`** — a single drawn object, centred, a name and one warm line.
Use this form for a completion card.

**`screen-gallery.jpg`** — plain card, plain segmented control, plain grid, and a
piece of collage art in every cell. Use this form for the cosmetics shelf.

## The character

**`char-black-cat.jpg`** is one frame at native resolution. One flat dark mass. The
edge is **ragged, fibrous and semi-transparent** — torn paper with a warm tan core
showing through. Two chartreuse curves, white almond eyes, three rose whisker ticks.
That is the entire vocabulary. It is **not** a flat vector mascot; crisp bezier edges
are the one thing this style is not.

**`char-white-cat.jpg`** and **`char-gray-cat.jpg`** are the same construction in
other bodies.

Four rules, each measured, each of which has already sent work the wrong way:

1. **The pill character must be light-bodied.** A dark silhouette is invisible on
   the pill's near-black ground. Their black cat only works because it sits on a
   pink sofa, and the pill has no room for furniture. **Dark in the room, light in
   the pill.**
2. **Interior accent marks are a value + saturation jump, not a hue clash.** Body
   `#2a2623` → accent `#97923f` is only 31° of hue but +0.43 value and +0.42
   saturation. Make marks *lighter and more saturated*, not opposite.
3. **Flat mass survives downsampling; rendered fur does not.** At 28×32pt any
   modelled shading turns to mush.
4. **Each mood needs a silhouette difference, not just an expression.** At pill size
   an expression is four pixels.

The animal **arrives once and stays.** It does not wander or patrol. Its loop is a
tail moving and a head tilting — small.

Six moods: **asleep** (nothing running), **working** (agents busy), **anxious and
pointing** (a session is erroring), **bored** (an agent idle with nothing queued),
**celebrating** (a session shipped), **delivering** (the concierge has something to
say).

## The four tabs

Ranked by urgency, not launch order, throughout. Urgency must be legible via colour
**and** icon or shape — never colour alone.

### 1 · Terminals (default)

Plain cards. One card per session carrying: what the agent is doing (the headline),
the repo or worktree, an agent badge, elapsed time, and status. One prominent
**"Jump to most urgent"** action.

Use these real strings:

- `find the cc history and reconcile it` — rudderfish — claude — 17m — **needs decision**
- `swift build` — open-vibe-island `feat/companion-pill` — claude — <1m — working
- `relaunched on the same build, probe recording` — stuck-clips — claude — 1m — done
- `write the PreToolUse contention guard` — reelle-ios — codex — 51m — idle
- `survey the fifteen Bāo assets` — zhende — claude — 1h — idle

Agent badge colours: claude `#d97742`, codex `#4aa3df`, cursor `#7a5cff`, gemini
`#42e86b`. Show ten sessions in one artboard and one session in another — density
stress test both ways. **Never require scrolling to reach something that needs the
user**; idle sessions collapse to a count.

### 2 · Inbox

The concierge's queue, and where the paid value is visible daily. It should feel
like a competent chief of staff, not a notification dump.

Top — pending decisions as compact cards. Each names the session, the action, and
the agent's own justification:

> **Session 3 wants to delete 3 test files it says are obsolete.**
> Allow · Deny · Look

Every permission card also offers a **rule** row, because the agent supplies one:

> *Always allow Read in this project*

Below — the handled log, with a running counter: **"214 interruptions handled this
week."** Lines read like: *"Approved 12 file reads in reelle-ios. Nothing looked
unusual."*

Empty state: **"Nothing needs you. Go build something."** Emptiness as direction,
not mood.

### 3 · Pet

The room. This is the screenshot-and-share tab and the only one allowed to be slow.

Wall, hard horizon, patterned floor, a rug, and the character. **One drawn object on
the floor per session shipped today** — a bone, a ball, a plant — so the day
accumulates visibly. A weekly recap card in the form of `screen-receipt.jpg`. A
cosmetics shelf in the form of `screen-gallery.jpg`: hats and desk accessories
earned from real outcomes — completed turns, lines changed, and days with at least
one ship.

### 4 · Rules

Boring tab done beautifully; this is where trust in the automation is won.

Trust per repo or session visualised as **leash length** — loose leash means
auto-approve almost everything, tight leash means escalate everything. A list of
auto-approve patterns. Do-not-disturb and batching settings.

## Key moments to design

- The collapsed pill: character plus urgency count, and the concept of expanding.
- **A critical escalation.** How does *"you really need to look at this"* read
  without panic? Solve this explicitly — it is the hardest state in the product.
- Mood transitions across at least four states.
- Terminals with one session versus ten.

## Tokens

Grounds and marks, taken off the reference:
`#59703f` wall · `#2a2b20` floor · `#e3a0a8` seat · `#c4553f` contour ·
`#c9cc4e` accent mark · `#f4ecd6` paper · `#17150f` ink

Text on the ink ground, all clearing AA:
`#ece5d5` primary · `#a89e8c` secondary · `#7c7466` tertiary

Status: needs approval `#f4a4a4` · question `#ffd58a` · working `#6ea7ff` ·
done `#6fb982` · idle a neutral grey.

**Type.** A textured hand for display type and numerals; a clean sans for running UI
copy; monospace strictly for data that lines up — commands, paths, elapsed times,
diffs. Keep it to three faces.

**Rhythm.** 46pt side inset, 11pt row padding, 3pt between a title and its meta
line. Radii 12–14 on seats, 3–4 on paper slips — paper does not have soft corners.

**The signature element is the seat**, not the pet: a saturated block with a
clashing drawn contour behind anything that must be read.

## Microcopy

Active voice, sentence case, plain verbs. Buttons say what happens: *Allow*, *Deny*,
*Jump to session*. Every concierge line names **who, what, and why they claim it is
fine.** Errors explain and direct; they never apologise or go vague. Rewards
celebrate shipping — *"PR merged — treat earned"* — never app-opening. The
character is warm, brief and competent; never needy, never guilt-tripping.

## Do not

- Do not make the character a crisp flat vector. Torn edges are the style.
- Do not put collage texture or hand-lettering inside functional lists.
- Do not give the character a hunger meter, decay, or any need of its own. Its needs
  are the fleet's needs.
- Do not use a fake macOS menu bar or window chrome around the panel.
- Do not signal urgency with colour alone.
- Do not design the panel narrower than 560pt.

## Deliver

1. All four tabs at 560 × 560, dark.
2. The collapsed pill, plus an expand-transition concept.
3. A character sheet: six moods in the chosen construction, shown at both room size
   and 28×32pt so the silhouette test is visible.
4. One shareable weekly-recap card.
5. A one-page token sheet: palette, type pairing, radius and spacing rhythm, and the
   single signature element.
