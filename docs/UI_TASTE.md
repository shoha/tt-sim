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
- **C4** No pure black. The scrim is `#2B2140` at 0.30 plus blur; shadows are ink-tinted,
  `#2B2335` at 0.16 at rest and 0.22 lifted (warm brown read as a beige lip over the sky), and
  plum near-black `#0E0B14` at 0.25 under glass. `Color(0, 0, 0, a)` in UI code is a finding.
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
  (`content_scale_factor`, THEME_GUIDE "Interface Size") keeps it at 13 physical px or more on
  every window 669 px tall and up (1.40 at 720p).
- **T3** Fraunces only where only it can serve: the wordmark, titles, headings, the Play
  together question and the card's two faces, Host and Join (the card's own words on its
  washes, not buttons in a row; coordinator decision 2026-10-10). Never in rows or buttons.
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
  stretched to the window, no full-width form fields. One declared wide token, 1280, for the
  avatar builder's three columns (rail, panes, preview). Pause and confirms are 420, Settings
  720 (its sentences and two-column rows need it; canvas width less a 32 px margin on a narrow
  one) and the new-map dialog 600 (the new-map dialog takes 960 on a canvas under 880 px, so its
  fields stay in view at 720p); a card grid adds columns rather than stretch a card past 400.
- **S6** Targets about 44: rows 44, controls and footer buttons 40.

## Motion

- **M1** Duration bands: 100-150 ms for feedback, 150-300 ms for state, 300-500 ms for an
  overlay, 500-800 ms for one authored entrance; exits are faster than entrances. Our modal
  sits under the overlay band on purpose (0.22 s in, 0.15 s out); the long moments are
  authored ones only (Host's wash into the room, the table move). Named exception: the
  painted backdrop's change of light (0.6 s, `PaintedBackdrop.FADE_S`) is the world changing,
  not chrome, so it runs past the overlay band; no control waits on it.
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
- **W4** Loading names the real operation ("Loading Old Mill"), determinate when it can be;
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

## 2026-11-15 foundation pass (card ui-painted-theme)

Written after the owner asked for the UI to match the painterly look, with colour and motion
chosen on good UX principles. The audit found the Painted Table already is that language (warm
paper, ink, persimmon and lake over a sky gradient, plum glass in play; the 2026-11-09 painter
frames agree with it: teal conifers, lime birch, lilac rock, cream stone), so the pass fixes
what was measurably wrong and centralises the rest. It changes no owner verdict.

- **Decision: one theme, not one per look.** The Look setting (Classic, Painted, Map's choice)
  paints the board only; the paper and glass leaves are the painterly UI for both, and nothing
  switches the UI theme with it. Reasons: the UI is never drawn by the painter, a Classic board
  under the same chrome costs nothing, and a second theme doubles every contrast and focus check
  for no player-visible gain. A map in Classic still gets glass over it, which is dark plum.
- **Decision: no brush-edge or paper-grain texture on panels.** The 2026-10-10 verdict
  (solid colours and subtle gradients until painterly UI is revisited) stands. Panels keep their
  flat fill, pencil edge and ink shadow. The place to spend painterly effort is the backdrop and
  the board, not chrome.
- **C9 Colour-vision safety.** Success, warning, danger and info are told apart in simulated
  protanopia and deuteranopia by CIE76 dE of 15 or more, in tritanopia by 7 or more, on both
  leaves (`tests/unit/test_ui_accessibility.gd`, Machado 2009 matrices), and each kind also
  carries its own icon (C7). Moss and madder collapsed to one olive-brown for a deuteranope (dE
  2.3), so SUCCESS is now `SEA_GREEN #1B7653` on paper and `MINT #86E3B4` on glass; `MOSS` and
  `MOSS_LIGHT` stay for the 3D tints that read them.
- **C6 addendum.** Every button type answers the pointer: rest, hover and press are three
  different fills. The danger button had one colour for all three; it now steps `MADDER`,
  `MADDER_HOVER #962B35`, `MADDER_PRESS #84252E`. A disabled Ghost steps from the soft text
  role down to the track role (its rest text is the soft role, so it read as live).
- **M-tokens.** `UiMotion` (`utils/ui_motion.gd`) is the one place motion is decided and
  `Constants.ANIM_*` alias it. Bands: feedback 90 to 120 ms (`FEEDBACK_IN_S` 0.12,
  `FEEDBACK_OUT_S` 0.10, `PRESS_S` 0.09), state and panels 160 to 240 ms (`STATE_S` 0.16,
  `PANEL_IN_S` 0.22, `PANEL_OUT_S` 0.16, `ENTRANCE_S` 0.24), nothing past 400 ms
  (`LARGE_MAX_S`). `ARRIVE_TRANS` is `TRANS_QUART` ease out, `EXIT_TRANS` `TRANS_CUBIC` ease in;
  `CELEBRATE_TRANS` (`TRANS_BACK`) is named so a celebration can use it and nothing else does.
  `tests/unit/test_ui_motion.gd` also fails if a panel, drawer, hover or toast source uses
  `TRANS_BACK`, `TRANS_ELASTIC` or `TRANS_BOUNCE`.
- **M2 amended.** The 6% back-out on a tile or icon hover is gone: hover scale eases out with
  `ARRIVE_TRANS`, so no functional control overshoots. Sheets start at 0.96 and settle at 1.0
  (they started at 0.9 and overshot under `TRANS_BACK`, G4); the token menu and asset browser
  follow.
- **M4 amended.** A list staggers by `STAGGER_S` 30 ms (it was 80 ms, which put an eight-row
  menu at 0.94 s), trimmed by `UiMotion.stagger_step()` so the whole entrance ends within
  `STAGGER_CAP_S` 0.36 s. The lift rides `offset_transform_position`, so rows no longer move by
  `position` (M3) and no container re-sorts at the end.
- **M5 implemented: Reduce motion.** Settings > Accessibility > Reduce motion (saved `ui/reduce_motion`,
  applied at once, `UiPreferences.load_reduce_motion` / `save_reduce_motion`) joins the OS
  reduce-animation flag in `UiMotion.reduced()`. Under it, sheets, popups, the asset browser,
  the download panel and pane swaps fade over at most `FADE_ONLY_S` 0.12 with no scale, lift or
  slide; a drawer fades in and cuts out; hover and press keep their colour but not their scale;
  stagger collapses to one simultaneous fade; the level card thumbnail does not zoom. Input is
  never blocked in either mode.
- **Not done here (for the menu cards).** The glass HUD (authoring, gameplay) is still dark
  plum at 0.90 opacity, which is the least painterly surface left; whether authoring, which
  does not run a table, should be paper rather than glass is the map-building card's call, with
  the owner. See `docs/THEME_GUIDE.md` "Foundation pass" for the per-screen list.

## 2026-11-15 settings pass (card ui-settings)

The Settings menu was a wall of controls under eight bare labels. New rules for any sheet of
settings (the Settings menu is the first user; `docs/UI_SYSTEMS.md` "Settings Menu" has the
mechanics). Reduce motion now lives under Settings > Accessibility, not Graphics.

- **T-S1 A setting says what it does under its name.** Every row that is not self-evident carries
  one plain sentence of `Caption` text directly under it (flush, so the pair reads as one item;
  the gap between rows is wider than the gap inside one). The tooltip is the long form and may
  repeat it; it is never the only place the effect is said. Write for a player, not an engine:
  "Smooths jagged edges on foliage", not "MSAA".
- **T-S2 Group by what the player is trying to do, most used first.** A tab with more than about
  five rows is split under headings (Look and quality before Display before Effects, then
  Performance, then an Advanced foldout for what almost nobody changes). Motion and size options
  that help a player read live in Accessibility, together.
- **T-S3 Reset is per group and global, and says when there is nothing to reset.** A group's Reset
  is quiet (Ghost) and reads "Defaults", off, while the group is at its defaults; a group of one
  row has none (its row is the reset). Reset all is quiet while nothing differs from the defaults,
  and when it acts it says so with an Undo toast. Defaults are read from one place so a reset can
  never disagree with a fresh install.
- **T-S4 Say what is saved.** A sheet that stages changes shows `All changes applied` or `Unsaved
  changes: ...` in words (the tone is secondary, never the only cue, C7), Apply is off while
  there is nothing to apply, and closing with unsaved changes puts everything back and says so.
  A row that is cheap to show previews on the board as it moves; a row that is not (a window
  mode, a renderer, a resize) waits for Apply.
- **T-S5 A long sheet can be searched, and every control is reachable without a mouse.** Search
  matches names and sentences, lists groups with a name match before groups that only mention it
  in a sentence, and the first Escape clears it (the field has no second X beside the sheet's
  close). A sheet that scrolls says "More below" while more waits there. Section tabs take focus, Tab walks
  rows in reading order, the scroll follows focus, shoulder buttons or Ctrl+Page Up/Down change
  section. A sheet sizes to the canvas (Interface size, window) and keeps its height across
  sections.

## 2026-11-15 gameplay HUD pass (card ui-hud)

Written after the owner asked for the gameplay screens' menus to be refined; the goal behind it
is that players can find and select their tokens. It adds rules for the play HUD and changes no
verdict (the solid colours and subtle gradients of 2026-10-10 stand; no paper grain).

- **I7 The HUD helps find a token.** Every token on the table is reachable from a list, not
  only by hunting the board: the roster drawer (T) lists them by name, a press selects, centres
  the camera and pulses the token, a hovered row lights its token. A player's own tokens come first;
  a token the GM hid is never listed to players (G14). Health is in words and a bar with its track
  showing, never colour alone (C7). A row shows the token's face (the picture of its map pin) and
  identical names are numbered ("Goblin 2"), because a name alone cannot tell three goblins apart.
- **I9 A token that was asked for is marked where nothing can cover it.** The thin glow on the
  token itself is hidden by a tree or a bright meadow (about 1.2:1 against grass), so what the
  roster picks or points at is also drawn in screen space in front of the world: an ink-outlined
  chalk ring on the ground (3:1 against any board by its two bands) and a portrait pin, whatever
  the Token pins setting says (the player just asked where it is). Pulse and recentre stay.
- **M8 A toast is read, not chased.** It arrives with a short slide (10 px) and fade, leaves faster,
  stays while the pointer rests on it, and the same words again count on the toast already up ("x3")
  instead of stacking. Kinds differ by icon and colour (C7). At most five stand. A toast with no
  time on it, and every error, has a visible 40 px close control (a click on it works too), and a
  kept error leaves after 12 s. The toast column stands 16 px clear of the hint bar.
- **I8 Help that has taught steps back.** The hint bar fades after 20 s unchanged and returns
  when the hints change or the pointer goes to the bottom edge; a tool's own hints never fade, and F1
  always lists every key.
- **S7 HUD targets.** Buttons the player presses in play are at least 40 px at Interface size
  1.0 (Add token and Save map were 31; the camera cluster's buttons were 34 and 26); icon-only
  controls carry a tooltip with their key, and the roster's tab also says "Tokens" (a bare icon
  was not found by the critic). Known gap: the Visuals rail's 36 px items (`IconRail.ITEM_SIZE` is
  shared with the authoring rail, whose twelve tools need the height).
- **Decision: the roster is a drawer, not a floating panel.** A drawer is the HUD's one pattern for
  a list beside the board (the room, the Visuals rail), joins the free-span logic that keeps the
  hint bar and toasts clear, and costs nothing while closed. It is 304 px, narrower than the 396
  token, because it is a list; at 1280x720 Auto it ends left of the board centre.

## 2026-11-15 map building (card ui-authoring)

Written after the owner asked for the menus to match the look; this is map building's part.
Code: `docs/UI_SYSTEMS.md` "Map building chrome". Decisions are the card's and the owner may
reverse the first with one constant.

- **Decision: the map tools are paper, glass one constant away.** Building a map stops play, so
  by C8 ("if it stops play it is paper") its drawer and rail are paper (`AuthoringChrome.
  SURFACE_PAPER`). Why: the dark plum slab sat over the brightest painted board as the heaviest
  thing on screen, and the owner's own menus are paper. The risk is the opposite: a cream
  panel is the brightest thing beside a dense dark forest (G12), so the panel is a card as tall
  as its pane (`FIT_HEIGHT`) and leaves the board visible under a short pane. The glass
  variant is complete (drawer, rail, panes, first-strokes card, all theme-driven) and was
  captured at runtime. Chips over the board (brush readout, hint bar, toasts) stay glass,
  because they sit over any biome and need the dark plate for legibility.
- **Grouped rail.** Twelve tools in one column read as noise; four runs with a gap between
  them (land, shape, features, build) let the eye find a tool by what it does, and the actions
  sit apart under them (G-grouping, nothing is hidden or removed).
- **Words say the state.** Undo and Redo name the edit they act on and say "Nothing to undo"
  when off; each does so in a toast ("Undid Raise") so the effect is seen without looking at the
  drawer. Save says whether anything is unsaved and answers Ctrl+S. The map name field lost its
  caption: the pane's title is what the drawer is about.
- **Once-only onboarding.** A small paper card says the first strokes in two lines, the first
  time only, and goes at "Got it" or at the first edit; it fades, never slides.
- **Motion.** The drawer keeps UiMotion's panel in and out (0.22 and 0.16 s, quart out);
  under Reduce motion it fades in and cuts out. The card's height followed a pane swap with a
  jump in round 1; round 2 eases it (below).

### 2026-11-16 map building round 2 (card ui-authoring, the critic's ranked fixes)

- **The active tool is a chip, not a stripe (C7, G1).** The selected rail item, and any held-active
  one, has a wash of the state colour (lake, alpha 0.36, rim 0.85) behind its icon
  (`IconRail.chip`, on for the map tools only), so the active tool reads at a glance at 720p.
- **Targets and runs.** Rail items are 46 px squares (43 real px in a 1280x720 window), the
  Undo, Redo, Save and Leave actions stand in a second column beside the tools so all of it
  still fits 720p, and the break between runs is 20 px.
- **A lead and a More (S4, G5).** A pane's help is one or two lines that say enough to start;
  the rest sits behind a closed "More" foldout (Biome, Place, Sculpt, Water). The water lead is
  two lines where it was eight.
- **An empty state is one action (I5).** The Village pane with no village shows a picture, "No
  village yet", a plain sentence and one button, "Draw a street", that goes to the Wall tool. The
  plaza gesture line waits until there is a village.
- **Choices are told apart and read in ink (C6).** The Place pane's biome rows are ink, not the
  soft grey, and use the Biome tile's short names. Oak, birch, pine, bush, boulder and cactus have
  different icons, chosen by words in the species key (four new icons: christmas-tree, plant,
  stone, cactus).
- **Unsaved is a word (C7).** Save shows the word "Unsaved" under its icon as well as the dot, in
  the narrow `RailNote` size (11), until the map is saved.
- **Footprint.** The drawer is 364 virtual px (about 340 real at 720p) and its card is square
  where it meets the rail (a rounded corner there left a notch of board between them). While a
  brush is down on the board the card steps back to 30% (`CardDimmer`), then returns on release.
  The card's height eases over `UiMotion.STATE_S` (0.16 s) on a pane swap and cuts under Reduce
  motion.
- **More below, said plainly.** A tall pane (Place, Biome) that can scroll further shows a band
  over its foot, the surface colour rising to nearly solid, with a small down chevron
  (`MoreBelowFade`, through `PaneStack.more_below_fade`); it eases in, and goes when the scroll
  reaches the end. It is a band and a chevron, not the Settings card's words, because a drawer
  has no free line to keep (SettingsChrome's line is that card's).

## 2026-11-16 map building 3 (card ui-authoring3, the owner's verdict on round 2)

The owner disliked the rail going to two columns and the card's rounded corners meeting a straight
rail edge, and asked for the most-used tools to be simpler. Code: `UI_SYSTEMS.md` "Map building
chrome" (round 3).

- **One column of seven (C1, S3).** Biome, Place, Sculpt, Paint, Water, Build, Fire, 52 px items
  (about 48 real px at 720p), in three runs (land, shape, make). Thin / Clear is Place's erase
  tab, Bridge is Water's Crossing tab, Wall, Buildings and Villages are Build's tabs: the rail was
  twelve tools, and a person looks for "Water", not for "Bridge" beside it. Every tool id, brush
  mode and pane is unchanged; a tab is the old rail item moved inside its hub.
- **No flat edge meets a curve (G-shape).** The rail is a rounded capsule that stands still; the
  card is a separate rounded card 12 px beside it, the same radius and paper. The card no longer
  slides out of the rail's edge, so the pair reads as a tool belt and its panel.
- **Actions leave the rail.** Undo, Redo, Save and Leave are a small paper pill at the top, right
  of whichever of rail or card is outermost, with a wider gap before Leave and the word "Unsaved"
  beside Save's dot. They are not tools, so they do not share the tools' column.
- **A key per tool, shown where it is read.** B Biome, P Place, T Sculpt (terrain), K Paint
  (colour), H Water (H2O), U Build, F Fire, chosen by mnemonic against the keys already taken
  (camera W A S D Q E, C and Home, O, V, M; the roster's T is play-only), plus the digits 1 to 7
  in rail order as a second binding (authoring only; in play they stay the F3 debug toggles).
  Each rail item carries its key as a small corner label, the tooltip says "Water (H or 5)", F1
  lists them, and the key pressed again steps a hub's tabs. Round 4 (ui-authoring3): rail glyphs
  26 px in a 52 px tile, a landscape glyph for Biome, a pin for Place, a house for Build; every
  pane card has a title row (tool icon and name) over its hub tabs; one lead per pane with the
  rest behind a closed More; the pill has a divider and the word Leave before the exit.
- **The basics sit above the fold (S4).** Each pane opens with its picker and a Size row; the
  gesture lead sits behind More and strength behind Advanced. The card needs no scroll for the
  basics at 1280x720 (a long catalogue such as Paint's surfaces or the buildings scrolls past its
  first row, as before).

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
- **2026-10-10** (coordinator) In Join mode Join is the one persimmon fill; the back disc steps
  back to paper with a persimmon arrow. Persimmon and lake hovers deepen (C6, C8). Fraunces
  stays on the card's Host and Join faces (T3).
- **2026-10-09** A session remembers its tables across nights: a session file with Resume.
- **2026-10-09** Map creation: no "Try" step; "From image" never in the default view; custom
  dimensions under Advanced.
- **2026-10-09** Map-informed mood is wanted, done tastefully: curated moods, backdrop only,
  controls fixed.
- **2026-10-09** Terrain events wanted during play: bridge collapse, forest falls, fire, and
  biome and terrain changes through the existing brush tools. (The UI rules for them are G13,
  M7 and I4.)
- **2026-10-10** The Play together card's blurred seam is disliked ("blurry down the middle").
  Keep one pill with the two colours, but the seam between Host and Join is a crisp
  hand-painted edge with a thin paper line: no soft bleed, no blur. The washes may keep a
  gentle tone inside each half. Soft blur on a control edge reads as out of focus, not painted.
  Follow-up the same day: each colour runs solid right up to the seam line; any lighter
  watercolour tone sits in the open middle of each half, away from the seam, so nothing soft
  frames the middle.
- **2026-10-10** The painterly aspects of the UI are landing sloppy. Until revisited, the UI
  uses solid colours and subtle gradients: the Play together card (solid halves, a subtle
  gradient, a crisp line), the title and room backdrop (a soft sky gradient in the map's mood;
  no painted clouds, hills or trees), and map placeholders (a simple two-tone gradient with the
  initial). The board itself (the 3D world) is not affected.
- **2026-10-10** Scroll bars over content lists (the library grid first): only the handle,
  visible only while the pointer is over the list, fading in and out; no bare track.
- **2026-10-10** UI once-over. Nothing clips or crowds: icons fit their rail or panel (the
  authoring tool rail clipped), and no label crowds or overlaps its control (choosing the time
  of day was crowded). One kind of thing behaves one way: selecting a map you made and
  selecting a Bundled map showed their details in different places and in different forms;
  a map's details have one place and one shape, whatever its source. The main menu's mix of
  painterly, paper and gradient reads half-baked: make it beautiful, functional and clear,
  one coherent material language within the solid-colour-and-subtle-gradient direction.
- **2026-10-11** Fewer UI and UX primitives, reused: a tool should be easy to pick up for
  anyone who knows another. When two tools do the same kind of thing, they use the same
  primitive the same way, not a lookalike: drawing a line of fire uses the river's ribbon
  (tinted fire orange), and choosing Area or Line for Fire uses the same Shape field as Water's
  River and Pond (and Start a fire's Circle and Path), with the same Tab key, tile layout, icons
  for line and area, and wording. Before adding a control, find the one that already does this
  job and use it; a new primitive needs a reason the existing one cannot serve.
- **2026-10-11** The small offset applied to the Host and Join icons on hover (the 2 px lift)
  reads weird and inconsistent: no other control's icon moves on hover. Hover changes colour
  and shadow, never an icon's position.
- **2026-10-18** "i think c as well. let's be sure that all of the shapes and iconography are
  consistent with the river tool. ideally they share some amount of functionality and
  modularity". Decision (card F5e): the Fire Line ships card F5d's variant C (persimmon rails
  at both edges, the coverage falling to nearly clear along the centre line, chalk chevrons
  down the middle), and the river and the fire line are one line tool in two tints: one
  gesture (`LineGesture`) and one ribbon (`LineRibbon`) that each tool passes a style. Every
  shape, icon and key is the same (round caps, the edge and its ink outline and glow, chalk
  chevrons on ink, the ring at the line's width, the chip, the Shape tiles, the hint bar's
  wording) except where the meaning differs: the tint, the fill (the river's even translucent
  band, the fire's rails) and the words. Both erase ribbons share one structure, the salmon
  edge and chevrons, over an interior that parts from what it erases. Card F5f (a consistency
  critic, 2026-10-18): an erase never hides what it erases. Its interior is a low wash (0.08 to
  0.14; at half coverage the river went a flat dusty rose and the lake over flames went grey
  mud, and even at 0.12 to 0.2 the salmon greyed the blue water), so the salmon edge, glow and chevrons say "erase", each on a strong ink outline the
  erase ring shares; the rails keep their weight but fall to clear in a thin seam.
- **2026-10-18** "ensure that the widths and presence of colors (like the outer edge of the
  fire line tool) are consistent between water and fire. basically, fire should just be an
  orange-coded version of the visuals for water and vice versa". Decision (card F5h): the
  river and the fire line are one look in two hues. Both pass one LineRibbon style, equal key
  for key but the tint keys (the band and edge in lake or persimmon, the glow in light lake or
  ember, the theme's paired ramps): every width, alpha, edge, glow, ink, cap, chevron and fill
  profile is one, and so is the erase (one style for the river's erase and the fire's put-out).
  The fill is one for both: the rails (option R) by default, the river's even fill (option E)
  kept as data to compare; in the dark ramp hues the even fill read as a faint murky veil
  (grey-teal for the river, brown-olive for the fire), so R reads better for both. Every line
  is one stroke, the ring's included: the tint 2.5 px over ink at 0.85 and 5.5 px on a glow
  of the tint, at rest and in erase alike (the lay ring was a 2 px hairline on a faint shadow,
  under 3:1 over bright grass). The one erase salmon moved toward chalk-pink (#FFB6A8), so on
  its ink it holds 3:1 over flames, ash, night water and bright grass, and an erase keeps its
  full colour at night (dimmed, a paler #FFCEC4 was needed, and it read near-white beside
  Thin's cream and Paint's tan rings).
- **2026-10-19** "go with C". Decision (cards F6 to F6c): Start a fire's Path is the third
  line tool in the same look, its hue deep amber (`ThemeColors.AMBER_DEEP` on the ring's light
  ochre glow), chosen over a deep ochre (merged with the golden meadow and the lightest of the
  three line tools) and a deeper ochre (olive by day, bronze at night). The colour says which
  tool; the rails say where trees catch, narrowing over about one half-width where only the
  ground burns; chalk_soft only for a path refused whole, as the refused Circle. No tool's ring
  at rest carries a mark of its shape: the chip's words tell the shapes apart.
- **2026-10-25** Collections manager (the owner's review). A collection that fails shows a legible
  "Needs attention" pill in place of its on switch, in a column every row shares, its row dimmed;
  reasons are one plain sentence and what to do, the technical text behind a Details toggle; an
  older file than the installed copy is refused, the same version is a Reinstall; no dialog says
  "plants" (the collection word, through LibraryNames); the folders are rescanned on open, on
  focus and on Refresh and never watched; a button's shadow is never clipped by the scroll that
  holds it (ShadowGutter and its audit); an error is on the card and in the footer in red with an
  icon, never only a toast, and a toast always draws above a scrim.
- **2026-11-02** Camera and token pin (the owner's review of the camera rig, board items CK, CR,
  CT, PN). Q / E turn the view whenever no brush is out, Alt + Q / Alt + E under a brush, and `[`
  `]` stay the brush size; the screen always shows which mapping is live (hint chip, compass
  tooltip). Alt + left drag tilts and orbits, O toggles top-down, Home resets everything. From above
  every token wears a map pin: a round picture of the token with a tail whose tip touches it, not a
  ring. It is much bigger than first tried (44 px, not 24: "much bigger to be readable at any
  zoom"), constant in screen space at every zoom, has no heavy outline (a thin soft rim), and a
  pin under the mouse comes to the front of crowded ones so it can be selected. A pin is
  never a way to learn where a hidden token stands.
