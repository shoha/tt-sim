# UI taste

The standard tt-sim's interface is judged against: rules with ids (C colour, T type, S
spacing, M motion, I interaction, W writing, G game) that makers, the critic and the audits
cite the same way, then the user's verdicts, which outrank every rule. The reference is the
suite's: painterly and luminous (Studio Ghibli backgrounds), never grey or muddy, with Tiny
Glade's calm. Token names (paper, glass, ink, chalk, persimmon, lake, madder, moss) are the
Painted Table tokens of the 2026-10-09 theme recommendation, defined in `ThemeColors` and built
into the paper and glass themes by `themes/painted_theme_base.gd`. Sizes are 1080p virtual px.

Some rules and review methods here are adapted from Impeccable by Paul Bakaus
(https://github.com/pbakaus/impeccable), Apache License 2.0.

**Tools.** Makers cite rule ids per surface they change. `tools/render_jobs/jobs/ui_tour.json`
captures every top screen at 1280x720 and 1920x1080; the `tt-sim-ui-critic` agent judges
those captures against this file before the coordinator and the user. The GUT test
`tests/unit/test_ui_theme_bypass.gd` counts colour literals, theme overrides and literal font
sizes per file against `tests/ui_bypass_baseline.json`, and a count may only fall.

## Colour

- **C1** One role table. `ThemeColors` holds the roles; the paper and glass themes remap them.
  A `Color(` literal in a UI scene or script is a finding unless it reads a role (3D materials
  and gizmos are exempt).
- **C2** Solid text colours. Secondary text uses its own solid role (`ink_soft`,
  `chalk_soft`), never a dimmed `TEXT` or a `modulate` alpha. Glass is the one translucent
  material; its text pairs are checked over white and over the darkest map.
- **C3** Tinted neutrals are mandatory (stricter than Impeccable, which makes them optional):
  no UI token with R = G = B. Paper neutrals lean warm, glass neutrals lean plum
  (`chalk_soft #CFC5D6`).
- **C4** No pure black. The scrim is `#2B2140` at 0.30 plus blur; shadows are warm brown
  `#5A3B2A`. `Color(0, 0, 0, a)` in UI code is a finding.
- **C5** Warm means do, cool means is. One persimmon fill per screen, on the primary action;
  lake shows state; madder fills only a danger-confirm button; moss never fills. The default
  `Button` is the quiet secondary and `Primary` is an explicit variation, so an unthemed
  control can never inherit the fill.
- **C6** Contrast in every state (rest, hover, pressed, disabled): text 4.5:1, large text
  3:1, controls, icons and focus rings 3:1. Hovers may only deepen.
- **C7** Colour is never the only cue: HP, download state, the GM badge and danger each also
  carry an icon or a word.
- **C8** Ramps are built in OKLCH (`Color.from_ok_hsl`, name to confirm in a probe): hover and
  press steps lower lightness at the same hue and trim saturation near white and black, which
  keeps darks from going muddy. Paper and glass are two designed leaves: if it stops play it
  is paper, if play continues it is glass.

## Type

- **T1** Few sizes, clear steps: Fraunces 56 / 26 / 19 (wordmark, title, heading), Inter 16 /
  15 / 14 (body, label, caption). Adjacent roles differ by 2 px or a weight step; body 16 and
  label 15 are 1 px apart, so label differs by weight.
- **T2** Caption 14 is the floor. A `font_size` under 14 is a finding; Interface size Auto
  (`content_scale_factor`) keeps the floor at 13 physical px or more at 720p.
- **T3** Fraunces only where only it can serve: the wordmark, titles, headings and the Play
  together question. Never in rows or buttons.
- **T4** The default `Label` is body 16.
- **T5** Light text on glass gets a little more weight and leading; step weight before size.
  Judged at 720p.
- **T6** Real and long copy at every size: player, map and session names ellipsize
  (`text_overrun_behavior`) with a tooltip; captions autowrap; every screen lays out on the
  1280x720 canvas.

## Spacing

- **S1** A 4-based scale: 4, 8, 12, 16, 24, 32, as theme constants. A literal in
  `add_theme_constant_override` is drift.
- **S2** Proximity first, containers when proximity fails. Never a card or sheet inside
  another; a sheet holds rows.
- **S3** Cards only for equivalent items (levels, avatars, shelf maps); settings and token
  actions are rows.
- **S4** More space above a heading than below it, carried by `MenuHeader` and the theme, not
  set per scene.
- **S5** Width tokens (sheets 420 / 600 / 960, drawer 396) and a max content width; nothing
  stretched to the window, no full-width form fields.
- **S6** Targets about 44: rows 44, controls and footer buttons 40.

## Motion

- **M1** Duration bands: 100-150 ms for feedback, 150-300 ms for state, 300-500 ms for an
  overlay, 500-800 ms for one authored entrance; exits are faster than entrances. Our modal
  sits under the overlay band on purpose (0.22 s in, 0.15 s out); the long moments are
  authored ones only (Host's wash into the room, the table move).
- **M2** No bounce, elastic or overshoot on panels (`TRANS_BACK`, `TRANS_ELASTIC`,
  `TRANS_BOUNCE`); a 6% back-out only on a small tile or icon hover. Arrivals use
  `TRANS_QUART` or `TRANS_EXPO` with `EASE_OUT`.
- **M3** Animate transform and opacity (`offset_transform_*`, `modulate`), never `position`,
  `size` or `custom_minimum_size` of a container child.
- **M4** Stagger only what reads as a list, skip spacers, cap the whole entrance near 0.35 s;
  nothing staggers on a surface opened often (pause).
- **M5** Reduce motion is fewer and gentler, not none: it removes lift, drift, seam travel and
  stagger and keeps fades and press colour.
- **M6** Loops stop when covered or hidden; no idle `_process` in UI; a killed entrance tween
  snaps to its visible end.
- **M7** Spectacle belongs to the board (a bridge falling, fire spreading); the UI around it
  stays still.

## Interaction

- **I1** Every control type has normal, hover, pressed, disabled and focus styles; focus is a
  drawn ring, never `StyleBoxEmpty`. Loading, error and empty states where they apply.
- **I2** Visible keyboard focus in a logical order; a composite control is one stop (the Play
  together card: Left and Right pick a face).
- **I3** A modal only to interrupt or to protect focus. Join grows in place on the card; the
  room is a drawer in play; table events are glass chips.
- **I4** Prefer undo when recovery is safe: GM terrain events and brush edits in play undo.
  Confirms only for Save into map, Discard and End session.
- **I5** An empty state says what goes there, why, and offers one action, with a picture
  (an empty shelf: a painted placeholder and "Set out a map").
- **I6** Review in bounded passes: one batch of findings, fix them all, at most one confirm
  round. The critic runs at most twice per card.

## Writing

- **W1** Labels are a verb and an object ("Set out this map"); never OK, Yes or Submit.
- **W2** A confirm names the action and its consequence in the message and on the button:
  "End the session? Everyone goes back to their title screen." / "End session".
- **W3** Errors say what failed, why when known, and how to recover; no codes. "No room has
  that code. Check it with your host."
- **W4** Loading names the real operation ("Loading Oak's Lab"), determinate when it can be;
  no invented progress.
- **W5** One word per concept: session, room, table, shelf, map, GM, party, avatar, token.
  "Level" stays internal.
- **W6** Whole translatable sentences through `tr()` with placeholders, no concatenation, no
  fixed widths on text.
- **W7** Icon-only controls carry a name: `tooltip_text` and an accessible name
  (`accessibility_name`, Godot 4.5+, to confirm in a probe).

## Anti-patterns

**Apply as written.** Pure black and pure grey. Grey text on colour. Bounce and elastic
easing. Gradient text. Nested cards; cards for items that are not equivalent. Text glyphs or
emoji as icons ("+ Add Token", toast "! X i"). Hard offset shadows. A modal where nothing needs
interrupting. Accents scattered with no role; the primary colour spent on decoration. Colour as
the only cue. Animated layout properties. Generic labels and vague calls to action. Everything
at equal weight. Status-chip soup. One-off spacing. Content hidden in its default state.
Stacked translucent layers. Staggering everything. Celebrating ordinary clicks; faked
progress. Re-showing dismissed onboarding. Monospace as costume (a room code is data and may
use it).

**Adapted for a game.**
- Glass is our in-play material because play continues behind it. Blur only on the stop-play
  scrim, measured for GPU cost; never on persistent HUD.
- Inter is fine for body at small sizes; the fault would be Inter as the only voice.
- The italic "Play together?" above the card is allowed only as that control's own question,
  never as a category eyebrow over a heading. The critic judges it.
- Paper `#FAF3E3` passes only as lit paper over a bright painted sky, never as a cream page
  over a void. The critic looks for muddy cream ("AI beige").
- A glow or side stripe marks state (selection, focus, the `IconRail` indicator); at rest,
  or on a toast or card, it is decoration.
- Hover lift is feedback on tiles, not the motion idea; the motion idea is the wash and a
  world that responds. Backdrop drift (60-90 s) is the painted world breathing; it stops
  under Reduce motion and when covered.
- Paper or glass is chosen by use (play stopped or live), never by category; a map's mood
  sets only the backdrop.
- Engine surfaces are themed too (`LineEdit` caret and selection, `ScrollBar`,
  `TooltipPanel`, `PopupMenu`); tabular figures for HP and counts; help text near 60
  characters a line.

**Game anti-patterns.**

| Id | Anti-pattern | Seen (0.2 evaluation) |
|---|---|---|
| G1 | Black scrims, and a double scrim when a dialog stacks on another | 0.6 alpha in nine scenes; confirm over pause |
| G2 | A control type with no theme entry inherits the primary fill | accent-filled `OptionButton` |
| G3 | Captions dimmed twice, then shrunk | `Caption` at 70% alpha plus `TEXT_MUTED` |
| G4 | Overshoot on modals | `TRANS_BACK` on 13 modals |
| G5 | Entrances that stagger spacers | the title's last target lands at 1.7 s |
| G6 | Semantic fills off their meaning | green Save, danger-filled Remove |
| G7 | Theme values copied by hand; StyleBoxes built in code | toasts, hints, drawer, download queue |
| G8 | Motion that means the wrong thing or never rests | shake on a danger confirm; idle pulses |
| G9 | Layout that jumps or spills | the asset browser resizes per tab; help scrolls sideways |
| G10 | A dark void outside play | the first screens are the least painterly |
| G11 | UI covering the thing it acts on | the token menu covers its token |
| G12 | UI brighter or busier than the board in play | the board must stay the brightest thing |
| G13 | A modal or full-screen notice for a table event peers did not choose | bridge collapse, fire, a forest falling: a glass chip, and the world shows it |
| G14 | Host-only truth shown as if shared | GM-only download progress or pending edits, unlabelled |

## Verdicts

The user's decisions about the interface, newest last. They outrank every rule above; a card
that conflicts with one stops and asks. Add each new verdict here with its date.

- **2026-10-04** Painterly, after Studio Ghibli backgrounds: bright and lively, a few bold
  soft-edged shapes, luminous colour, never grey, muddy or fussy. Tiny Glade is the reference
  for simplicity: direct gestures instead of forms, and no way to make something ugly.
- **2026-10-09** Theme direction: **Painted Table**, with Dusk's colour rule ("warm means do,
  cool means is") and quiet default button, and Toybox's Join in place. Scrim 30% plus blur.
- **2026-10-09** **Room first**: a session is a room of people that can exist with no map. The
  GM sets maps out from a shelf; leaving a map returns everyone to the room. A map is the
  wrong primitive for hosting; a social lobby stays possible.
- **2026-10-09** No Host control far from what it acts on.
- **2026-10-09** **Join happens in place**: the Join half of the Play together card becomes the
  room-code field. There is no separate join screen.
- **2026-10-09** A session remembers its tables across nights: a session file with Resume.
- **2026-10-09** Map creation: no "Try" step; "From image" never in the default view; custom
  dimensions under Advanced.
- **2026-10-09** Map-informed mood is wanted, done tastefully: curated moods, backdrop only,
  controls fixed.
- **2026-10-09** Terrain events wanted during play: bridge collapse, forest falls, fire, and
  biome and terrain changes through the existing brush tools. (The UI rules for them are G13,
  M7 and I4.)
