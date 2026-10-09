# Sound Effects Reference

This document catalogs all sound effects used (or expected) across the game, organized by category. The `AudioManager` autoload manages playback across four audio buses: **Master**, **Music**, **SFX**, and **UI**.

---

## Audio File Locations

| Category | Directory                    | Format |
|----------|------------------------------|--------|
| UI       | `res://assets/audio/ui/`     | `.wav` |
| SFX      | `res://assets/audio/sfx/`    | `.wav` |

`tools/generate_sfx.py --install` renders every sound in `tools/sfx_spec.py` into these
directories and writes `res://assets/audio/sfx_manifest.json`, the table `AudioManager` loads
at startup: each sound's file, bus, gain, pitch jitter, cooldown and priority. A file that is
not in the manifest is never played; a name that is not in the manifest warns once.

---

## Playing a Sound

There is one entry point:

```gdscript
AudioManager.play(&"confirm")
AudioManager.play(&"token_drop", drop_volume_db, drop_pitch)  # gain offset (dB), pitch scale
```

Everything about how a sound plays lives in its `SoundSpec` in `tools/sfx_spec.py`, never at
the call site. The optional arguments are only for sounds that follow a quantity: the token drop
adds a height-driven gain and base pitch, the (disabled) whoosh a speed-driven pitch. The
playback fields are:

| Field | Meaning |
|---|---|
| `volume_db` | Player gain on top of the rendered peak. |
| `pitch_jitter` | Random pitch offset per play, in semitones either way (default 0.5). |
| `cooldown_s` | Minimum seconds between two plays of the sound; a request inside it is dropped. |
| `priority` | Coalescing tier, below. |

**One sound per gesture.** `play()` queues the request, and `AudioManager` flushes the queue once
a frame, after every other node's `_process`. On each bus (UI, SFX) only the highest-priority
request of the frame plays; ties keep the first. So a click that confirms a dialog and closes it
is heard as the confirm alone, and a dialog no longer needs to suppress its own close sound. The buses coalesce separately, so a
splash on the board is never silenced by a click in a menu. The tiers (`PRIORITY_*` in
`sfx_spec.py`):

| Tier | Value | Sounds |
|---|---|---|
| Alert | 50 | `error` |
| Outcome | 40 | `confirm`, `cancel`, `success`, `leave_game` |
| Event | 30 | `open`, `close`, `transition`, `splash_enter`, `splash_exit` |
| Tap | 20 | `click`, `token_pickup`, `token_drop` |
| Faint | 10 | `tick`, `hover`, `token_hover`, `token_slide`, `token_whoosh` |

A sound inside its cooldown is dropped when requested, before coalescing, so it never outranks a
lower sound that would otherwise play. Two sounds carry one today: `tick` (80 ms, formerly the
Settings sliders' own throttle), so a fast slider drag or a held key ticks about twelve times a
second at most, and `token_hover` (150 ms), so sweeping the mouse across a row of tokens chirps
once rather than once per token.

**Only the user's actions sound.** A sound marks something the player did or something that
happened to them, never code putting a control in step:

- Toggles tick on `pressed`, which only a click emits, not `toggled`, which also fires when code
  sets `button_pressed`. Code that shows a saved value (Settings opening, Reset) sets controls
  with `set_pressed_no_signal` / `set_value_no_signal`, or holds its slider ticks while a tween
  moves them (Settings' Reset).
- Background work is quiet until it means something to the player: a pack download plays nothing
  per asset variant (five finishing 120 ms apart used to stack +4.3 LU and fill the UI voice
  pool, cutting clicks off); the pack's own toast plays `success` or `error` once.
- `token_hover` plays only for a token the local player can drag now
  (`DraggableToken.dragging_allowed`), so the chirp says "you can move this".

**Pause.** `AudioManager` runs with `PROCESS_MODE_ALWAYS`: the pause menu's own sounds play
while the tree is paused, and a drop or splash already playing when the game pauses finishes
instead of freezing and resurfacing on unpause.

**Bus volumes.** The Settings sliders call `AudioManager.set_bus_volume(AudioManager.BUS_*, 0..1)`;
`AudioManager` also applies the saved values at startup. There is no other bus-volume code. The
slider position maps to gain through a squared taper, `AudioManager.slider_to_db(p)` =
`linear_to_db(p * p)`: half way is -12 dB, a quarter -24 dB, a tenth -40 dB, zero silent.
Loudness grows with roughly the 0.6 power of sound pressure, so gain ~ position^1.7 makes the
slider track how loud it sounds, and squared is the nearest simple curve; the old linear taper put
half way at only -6 dB. Saved settings are slider percentages, so a saved 50% now sounds quieter
than it did.

---

## Modular Sound Wiring

Sound effects are wired up **automatically** wherever possible so that new UI elements get sounds without manual intervention.

### Automatic Button Sounds (via SceneTree)

`AudioManager` listens to `SceneTree.node_added`. Every `BaseButton` that enters the scene tree automatically gets:

- **`pressed`** → `play(&"click")`; a `CheckButton` or `CheckBox` plays `tick` instead, 2 dB
  louder when it turns on. Both listen to `pressed`, so a toggle set from code is silent.
- **`mouse_entered`** → `play(&"hover")` -- currently **off**: the connection
  is skipped unless `AudioManager.BUTTON_HOVER_SOUND_ENABLED` is flipped to `true`. Toggles
  (`CheckButton`/`CheckBox`) are excluded from it regardless, since they already tick.

**Opting out:** To silence a specific button (e.g. because it plays a specialized sound instead), set metadata before or during `_ready()`:

```gdscript
button.set_meta("ui_silent", true)
```

The auto-connect defers to the button's `ready` signal, so metadata set during `_ready()` is respected.

### Automatic Panel Sounds (via base classes)

There are **two** panel base classes that handle animation and sounds automatically:

#### `AnimatedVisibilityContainer` (extends `Control`)

For in-scene panels that show/hide within the UI tree.

- **`animate_in()`** → `play(&"open")`
- **`animate_out()`** → `play(&"close")`
- **Opt out:** set `play_open_close_sounds = false` in inspector or script. A panel opened by a
  button no longer needs to: the button's click and the panel's open land in the same frame and
  the open wins.

Panels using this: `TokenContextMenu`, `AssetBrowserContainer`, `LevelEditor`

#### `AnimatedCanvasLayerPanel` (extends `CanvasLayer`)

For full-screen overlay panels with a backdrop (`ColorRect`) + centered content (`CenterContainer/PanelContainer`).

- **`animate_in()`** → `play(&"open")`
- **`animate_out()`** → `play(&"close")`
- **Opt out:** set `play_sounds = false` in inspector or script
- Provides lifecycle hooks: `_on_panel_ready()`, `_on_after_animate_in()`, `_on_before_animate_out()`, `_on_after_animate_out()`

Panels using this: `SettingsMenu`, `PauseOverlay`, `ConfirmationDialogUI`, `UpdateDialogUI`

#### `LevelEditor` popups

The level editor's `_animate_popup_in()` / `_animate_popup_out()` methods also play open/close sounds.

The level editor's `LoadDialog` and `DeleteConfirmDialog` also play close sounds when dismissed via the X button (`close_requested` signal).

### Specialized Button Sounds

Some buttons play specialized sounds instead of the generic click:

| Button                             | Sound                | How                                      |
|------------------------------------|----------------------|------------------------------------------|
| Confirmation dialog "Confirm"      | `confirm` (or the dialog's `confirm_sound`, e.g. `leave_game` for Return to Title) | Button has `ui_silent` meta; calls `play()`; outranks the dialog's close |
| Confirmation dialog "Cancel"       | `cancel`             | Button has `ui_silent` meta; calls `play()`; outranks the dialog's close |
| Avatar builder "Save" / "Add to board" | `confirm`        | `AvatarBuilder.confirm()` calls `play()`; outranks the button's click and the panel's close |
| Avatar builder "Cancel" (and Escape) | `cancel`           | `AvatarBuilder.cancel()` calls `play()`; outranks the click and the close |

---

## UI Sounds (Bus: UI)

Played with `AudioManager.play(&"<name>")`. The volume, jitter (semitones either way), cooldown
and priority columns mirror `tools/sfx_spec.py`, which is the source of truth. A toggle plays
`tick` 2 dB louder when it turns on than when it turns off.

| Sound          | Volume | Jitter | Cooldown | Priority | Description                       | Wiring              |
|----------------|--------|--------|----------|----------|-----------------------------------|----------------------|
| `click`        | 0 dB   | 0.5    | -        | 20       | Button press / tap                | **Auto** (all buttons) |
| `hover`        | -6 dB  | 0.5    | -        | 10       | Button hover / focus              | Disabled             |
| `open`         | 0 dB   | 0.5    | -        | 30       | Menu or panel opening             | **Auto** (panels)    |
| `close`        | 0 dB   | 0.5    | -        | 30       | Menu or panel closing             | **Auto** (panels)    |
| `success`      | 0 dB   | 0.5    | -        | 40       | Success feedback                  | Success toasts (one per finished pack download); a player joining, in the lobby and mid-game (`PlayerListDrawer`); connecting to a lobby; a game update downloaded |
| `error`        | 0 dB   | 0.5    | -        | 50       | Error feedback                    | Error toasts (one per failed pack download); a failed connect; a game update download that failed |
| `confirm`      | 0 dB   | 0.5    | -        | 40       | Dialog accept (confirmation dialog, avatar builder, pickers) | **Wired**            |
| `cancel`       | 0 dB   | 0.5    | -        | 40       | Cancel / back action              | **Wired**            |
| `tick`         | -8 dB  | 0.5    | 80 ms    | 10       | Slider / toggle / checkbox tick   | **Auto** (toggles, on a click only); Settings sliders when the user moves them; a player leaving (lobby and mid-game); tabs, rails, foldouts, menus |
| `transition`   | -3 dB  | 0      | -        | 30       | Scene / state transition whoosh   | Called by `TransitionOverlay`; nothing calls `UIManager.fade_out`/`fade_in`/`transition` yet, so it never plays |
| `leave_game`   | 0 dB   | 0      | -        | 40       | Returning to title from a game    | **Wired**            |

---

## SFX Sounds (Bus: SFX)

Played with `AudioManager.play(&"<name>")`; columns as for the UI table.

| Sound           | Volume | Jitter | Cooldown | Priority | Description                          | Status        |
|-----------------|--------|--------|----------|----------|--------------------------------------|---------------|
| `token_pickup`  | 0 dB   | 0.5    | -        | 20       | Picking up / starting to drag a token| **Wired**     |
| `token_drop`    | 0 dB   | 0.7    | -        | 20       | Dropping / placing a token           | **Wired**     |
| `token_slide`   | -3 dB  | 0.5    | -        | 10       | Token sliding / movement on board    | Not wired     |
| `token_hover`   | -6 dB  | 0.5    | 150 ms   | 10       | Mouse hovering over a token the player can drag | **Wired**     |
| `token_whoosh`  | -3 dB  | 1.3    | -        | 10       | Rapid drag swoosh (velocity-based)   | Disabled      |
| `splash_enter`  | 0 dB   | 0.5    | -        | 30       | Token entering a water zone          | **Wired**     |
| `splash_exit`   | -3 dB  | 0.5    | -        | 30       | Token leaving a water zone           | **Wired**     |

### Where SFX Sounds Are Used

| Sound              | File                      | Trigger                          |
|--------------------|---------------------------|----------------------------------|
| `token_pickup` | `draggable_token.gd`    | Drag start                      |
| `token_drop`   | `draggable_token.gd`    | Settle start (immediate on drop); gain -3 to +2 dB and pitch 1.1 to 0.85 by drop height |
| `token_hover`  | `board_token_controller.gd` | Mouse enters the rigid body of a token the local player can drag (`wants_hover_sound()`: `DraggableToken.dragging_allowed`, false without CONTROL permission or while another peer holds the drag lock) |
| `token_whoosh` | `draggable_token.gd`    | Horizontal drag speed >= 10 units/sec (0.15s cooldown, velocity-scaled pitch) -- trigger still wired, but the call is skipped while `AudioManager.TOKEN_WHOOSH_SOUND_ENABLED` is false |
| `splash_enter` | `scenes/effects/water_zone.gd` (`_on_body_entered`) | Token's collision shape enters a water zone |
| `splash_exit`  | `scenes/effects/water_zone.gd` (`_on_body_exited`) | Token's collision shape fully exits a water zone |

### Additional SFX Candidates (Not Yet in the Palette)

Interactions that could benefit from a sound. Adding one is a spec entry, an install and a call
(see "Adding a Sound" below); there is no file to source, since every sound in the palette is
synthesized.

| Proposed Sound    | Description                                    | Where to Wire                          |
|-------------------|------------------------------------------------|----------------------------------------|
| `token_snap`      | Token snapping to grid position                | `drag_and_drop_3d.gd` snap logic       |
| `token_rotate`    | Token rotation snap                            | `board_token_controller.gd` rotation   |
| `token_scale`     | Token scale change                             | `board_token_controller.gd` scaling    |
| `token_cancel`    | Drag cancelled / token returns to origin       | `draggable_token.gd` cancel handler    |
| `level_start`     | Level begins loading / transition starts       | `level_play_controller.gd`             |
| `level_complete`  | Level finishes loading / ready to play         | `level_play_controller.gd` / `root.gd` |

---

## Audio Bus Layout

```
Master
├── Music   (background music, not yet implemented)
├── SFX     (game interaction sounds — tokens, level events)
│   ├── Effect: LowPassFilter  (cutoff 7kHz — softens digital sharpness)
│   └── Effect: Reverb          (small room, 12% wet — subtle physical space)
└── UI      (interface sounds — clicks, hovers, panels)
    └── Effect: LowPassFilter  (cutoff 7kHz — warm, muffled-speaker feel)
```

Master, SFX and UI each have a volume slider (0–100%, squared taper; see "Bus volumes" above)
on the Settings menu. The Music row is hidden (`SettingsMenu.SHOW_MUSIC_VOLUME`) until the game
has music; its bus and saved value are kept.

### Lo-fi Bus Effects

The SFX and UI buses have effects applied to achieve a warm, lo-fi aesthetic. These are configured in `default_bus_layout.tres` and can be tweaked in the Godot editor (bottom panel → Audio tab).

| Bus | Effect | Key Settings | Purpose |
|-----|--------|-------------|---------|
| SFX | LowPassFilter | cutoff: 7kHz | Rolls off harsh highs for a warm tone |
| SFX | Reverb | room: 0.2, wet: 12%, damping: 0.7 | Subtle sense of physical space (tabletop feel) |
| UI  | LowPassFilter | cutoff: 7kHz | Softens UI clicks/chimes to match the lo-fi vibe |

**Tuning tips:**
- Lower the cutoff (e.g. 5kHz) for a more muffled, retro feel
- Raise the cutoff (e.g. 10kHz) if sounds feel too dull
- Increase reverb wet (e.g. 0.2) for more spatial depth, decrease (e.g. 0.05) for drier sound
- All changes are audible immediately in the editor's Audio tab

---

## Sound Design Guidelines

Every sound is synthesized by a stdlib Python toolchain in `tools/` (`sfx_spec.py`,
`sfx_synth.py`, `sfx_render.py`, `sfx_measure.py`, driven by `generate_sfx.py`), not sourced as
audio files. There is no format/sample-rate/channel checklist to follow when adding a sound — the
renderer always writes 44100 Hz mono `.wav`. What matters is how each sound is specified. The
table below is the palette as it currently ships; the source of truth is `tools/sfx_spec.py`.

### The Palette

| Sound | Bus | Pitch | Attack | Length | Filter / noise |
|---|---|---|---|---|---|
| `click` | ui | E4 | 2 ms | 58 ms | lp 2000 Hz, noise 0.02 |
| `hover` | ui | E5 | 2 ms | 38 ms | lp 2000 Hz, noise 0.02 |
| `tick` | ui | A4 | 3 ms | 45 ms | lp 2000 Hz, noise 0.02 |
| `open` | ui | C4 glide +5 st | 60 ms | 175 ms | lp 2000 Hz, noise 0.02 |
| `close` | ui | G4 glide -5 st | 60 ms | 175 ms | lp 2000 Hz, noise 0.02 |
| `confirm` | ui | E4 glide +4 st | 90 ms | 190 ms | lp 2000 Hz, noise 0.02 |
| `cancel` | ui | D4 glide -4 st | 58 ms | 168 ms | lp 2000 Hz, noise 0.02 |
| `success` | ui | C4+E4+A4 chord | 14 ms | 300 ms | lp 2400 Hz, noise 0.02 |
| `error` | ui | C4+D4+E4 chord | 27 ms | 300 ms | lp 2400 Hz, noise 0.02 |
| `transition` | ui | G4 glide -12 st | 55 ms | 260 ms | lp 2000 Hz, noise 0.42 |
| `leave_game` | ui | C4 glide -7 st | 100 ms | 460 ms | lp 2000 Hz, noise 0.02 |
| `token_hover` | sfx | E5 | 2 ms | 38 ms | lp 2000 Hz, noise 0.02 |
| `token_pickup` | sfx | E3 glide +2 st | 5 ms | 150 ms | lp 2000 Hz, noise 0.02 |
| `token_drop` | sfx | A2 glide -2 st | 8 ms | 190 ms | lp 1800 Hz, noise 0.02 |
| `token_slide` | sfx | A2 | 30 ms | 320 ms | lp 1800 Hz, noise 0.02 |
| `token_whoosh` | sfx | E4 glide -9 st | 45 ms | 340 ms | lp 2000 Hz, noise 0.45 |
| `splash_enter` | sfx | C3 glide +22 st | 6 ms | 610 ms | lp 2800 Hz, noise 0.66 |
| `splash_exit` | sfx | G4 glide -22 st | 5 ms | 610 ms | lp 2800 Hz, noise 0.66 |

### Design Rules the Palette Follows

- **Scale.** Every pitch comes from C major pentatonic (C, D, E, G, A). Sounds overlap constantly
  in play (a hover while a panel closes, a pickup while a tick fires), and restricting every note
  to one scale means overlapping sounds never clash, regardless of which two happen to land at the
  same time.
- **No melodies.** No sound plays a sequence of notes — each is a single struck note (or, for
  `success`/`error`, a single struck chord). Where a sound needs a sense of direction, that comes
  from a pitch *glide* within the one note rather than a second note: `open` glides up, `close`
  glides down, mirroring the action. A note sequence reads as a little tune, which is the wrong
  register for interface feedback — it draws attention to itself instead of confirming an action.
  `tools/tests/test_sfx_spec.py::test_no_sound_plays_a_note_sequence` enforces this at the spec
  level, so a future edit can't reintroduce a melody by accident.
- **Two chords, mirrored.** `success` is C4+E4+A4, a sixth chord — consonant and warm without
  reading as a fanfare. `error` is C4+D4+E4, a cluster — the same three-note construction, but
  built on seconds instead of thirds, so it grinds where `success` resolves. They share attack
  shape, chord size, and duration on purpose: they are a matched pair, differing only in the
  interval structure that makes one feel resolved and the other feel wrong.
- **Attacks are bimodal.** Quick interaction sounds (`click`, `hover`, `tick`, `error`, the token
  taps) onset in 2-8 ms; deliberate sounds (`open`, `close`, `confirm`, `cancel`, `success`,
  `leave_game`) swell over 40-115 ms. An earlier version of this palette used a uniform minimum
  onset of 12 ms, on the theory that a slow attack is what makes a sound feel soft. That was wrong
  for small sounds — it made `click` and `hover` feel sluggish instead of soft — and it was
  disproved by measuring a reference CC0 pack whose `click` and `hover` onset in under 2 ms and
  still sound soft. Softness in a small sound comes from being short and dark, not from a slow
  onset; length and low-pass cutoff do the work a slow attack was wrongly assigned to do.
- **Dark at source.** Each sound's low-pass cutoff sits at 1800-2800 Hz, set per sound rather than
  relying on the bus-level filter (see "Audio Bus Layout" below) to do all the darkening. The two
  swishes (`transition`, `token_whoosh`) and the two splashes carry real noise (0.42-0.66 mix);
  everything else is nearly pure tone (0.02 noise mix — present but not audible as texture).

### Physical Limits Worth Knowing

These caused real failures while tuning the palette and will cause them again for anyone who
edits `tools/sfx_spec.py` without re-running `--verify`:

- **A low fundamental cannot present a fast onset.** One cycle of A2 (110 Hz) is about 9 ms, so
  `token_drop` cannot honestly declare a 3 ms attack — there isn't enough waveform yet at 3 ms for
  the envelope to have risen. It declares 8 ms instead, which is close to the physical floor for
  that pitch.
- **A chord's onset is governed by how its notes beat, not by its declared attack.** `error` is
  C4+D4+E4; the closely-spaced frequencies beat against each other at roughly 32 Hz, so the
  measured envelope doesn't actually peak until about 30 ms in, no matter what attack is declared
  in the spec. It declares 27 ms, which is why the gate's attack band (see below) has to tolerate
  some slack rather than demanding an exact match.

### Regenerating and Iterating

`tools/sfx_spec.py` is the file to edit for ordinary tuning — one `SoundSpec` dataclass per
sound, covering pitch, glide, attack, length, low-pass cutoff, and noise timeline. The rendering
engine (`sfx_synth.py`, `sfx_render.py`) should not need to change to retune an existing sound or
add a new one within the existing palette style.

```bash
python tools/generate_sfx.py --verify                        # check the palette against its targets
python tools/generate_sfx.py --variants 3 --sheet --as-bus    # audition set plus per-bus sheets
python tools/generate_sfx.py --only click --variants 5        # work on one sound
python tools/generate_sfx.py --install                        # write into assets/audio/, with the manifest
python tools/generate_sfx.py --manifest                       # playback-only edit: rewrite just the manifest
godot --headless --import --path .                            # after installing
godot --path . tests/test_soundboard.tscn                     # audition in-engine, on the real buses
```

- `--sheet` writes one WAV per bus (`sheet_ui.wav`, `sheet_sfx.wav`) containing every sound on
  that bus, separated by 600 ms of silence, so the whole family can be judged together instead of
  one file at a time — this is how cross-sound consistency (the pentatonic scale, the bimodal
  attacks) actually gets checked by ear.
- `--as-bus` additionally filters each sheet through an ffmpeg approximation of the effect chain
  in `default_bus_layout.tres` (the same low-pass/reverb settings documented in "Audio Bus
  Layout" below), producing `sheet_ui_bus.wav` / `sheet_sfx_bus.wav`. This is what the sound will
  actually sound like in-game, not just as a raw render. Silently skipped if `ffmpeg` isn't on
  PATH.
- `--variants N` renders N differently-seeded takes of each selected sound; variant 0 is always
  the plain, unsuffixed filename, since that's the one `--install` uses.
- `--install` writes variant 0 of every sound into `assets/audio/<bus>/<name>.wav`, writes
  `assets/audio/sfx_manifest.json`, and removes any stale `.ogg` (and `.ogg.import`) file with
  the same name, which the manifest would never point at and nothing else would clean up.
- `--manifest` rewrites only the manifest. Use it after changing a playback field
  (`volume_db`, `pitch_jitter`, `cooldown_s`, `priority`); those never change a rendered file.
  `tools/tests/test_sfx_spec.py` fails while the committed manifest disagrees with the spec.
- `tests/test_soundboard.tscn` (backed by `tests/test_soundboard.gd`) is a standalone scene that
  loads candidate files with `AudioStreamWAV.load_from_file()` (bypassing Godot's resource cache)
  from a scratch directory — `%TEMP%/tt-sim-sfx` by default, the same directory
  `generate_sfx.py --out` writes to — fresh on every button press. That means the scene can stay
  open across a whole tuning session: regenerate a sound with `generate_sfx.py`, click its button
  in the still-open soundboard, hear the new take through the real UI/SFX buses, repeat.

**Method note:** when feedback on a sound is about character ("too bright", "too soft") rather
than a specific number, don't regenerate the whole palette and hope. Instead, build ONE sound several
ways, varying a single property at a time (e.g. five `click` variants at different low-pass
cutoffs, via `--only click --variants 5`), concatenate them into a short sheet, and ask which one
is closest. That converts a vague judgement call into one short listen and a single answer, and
it is far cheaper — in both render time and listening time — than regenerating the whole palette
on a guess.

### What the Gate Checks

`--verify` and the equivalent assertions in `tools/tests/test_sfx_render.py` apply the same four
checks to every sound in `tools/sfx_spec.py`:

- **Attack.** Measured attack time lands within a band around the sound's own declared
  `attack_ms`: at least 0.6x the declared value, at most `attack_ms + 5 ms`. The band is
  asymmetric and generous on the high side because of the physical limits above — a low note or a
  beating chord can't hit its declared attack exactly.
- **Warmth (high-band energy).** High-band RMS ratio must sit at or under the sound's own
  `max_high_band_db` ceiling, and no more than 12 dB below it. This check is deliberately
  two-sided. An earlier version of the gate had only the ceiling, which meant a palette 20 dB
  darker than intended — i.e. muffled well past the intended warmth — passed every check while
  sounding wrong. The floor exists specifically to catch that failure mode.
- **Peak.** Measured peak must land in [-4, -2] dBFS.
- **Duration.** Measured duration must be within 20% of the sound's declared `total_ms`.

**What this does and doesn't mean:** the gate verifies that the renderer does what the palette
declares — that `tools/sfx_spec.py`'s numbers and the actual rendered audio agree. It does not
encode taste. A sound can pass every one of these four checks and still sound wrong — too bright
for its role, too similar to a neighboring sound, or just not what was wanted. Passing `--verify`
is a necessary check after any spec edit, not a substitute for listening to the sheet.

### Volume Normalization

All audio files are automatically normalized on commit via a pre-commit hook. This ensures consistent perceived loudness regardless of the source.

**Rule:**

| Location | Method | Target | Tolerance |
|---|---|---|---|
| `assets/audio/ui/`, `assets/audio/sfx/` | Peak normalization (gain + limiter) | -3 dBFS | ±1.5 dB |
| Everywhere else (e.g. sustained music) | LUFS (EBU R128 measurement + gain + limiter) | -18 LUFS | ±1.5 dB |

One-shot sound effects under `ui/` and `sfx/` are always peak-normalized, regardless of length. A designed palette is authored to a uniform peak ceiling, and the relative levels between sounds are intentional; LUFS normalization matches perceived loudness file by file, which overrides that intent and can limit a long, quiet-tailed effect until it clips. LUFS remains correct for sustained material such as music.

**Setup (one-time):**

```bash
python tools/hooks/install.py
```

**Requirements:** `ffmpeg` on PATH:

```bash
# Windows
scoop install ffmpeg

# macOS
brew install ffmpeg

# Ubuntu / Debian
sudo apt install ffmpeg

# Fedora
sudo dnf install ffmpeg

# Arch
sudo pacman -S ffmpeg
```

**How it works:**
- The pre-commit hook detects staged audio files in `assets/audio/`
- Measures loudness (LUFS) and peak levels via `tools/normalize_audio.py`
- Applies the exact gain needed to reach the target, with a hard limiter at -1 dBTP to prevent clipping
- Re-stages the normalized files so the commit includes corrected versions
- Files already within tolerance are skipped (idempotent — re-running does nothing)
- If ffmpeg is not installed, the hook prints a warning and continues (non-blocking)

**Manual usage:**

```bash
python tools/normalize_audio.py                 # Normalize all audio files
python tools/normalize_audio.py --dry-run       # Preview without modifying
python tools/normalize_audio.py --target -16    # Custom LUFS target
python tools/normalize_audio.py --peak -1       # Custom peak target for short files
python tools/normalize_audio.py --backup        # Keep originals as .bak
```

---

## Adding Sounds to New UI Elements

### Buttons
No action needed. Any `BaseButton` added to the scene tree automatically plays a click sound (and a
hover sound too, if `AudioManager.BUTTON_HOVER_SOUND_ENABLED` is turned back on). To opt out:

```gdscript
my_button.set_meta("ui_silent", true)
```

### Panels / Dialogs
- **In-scene panel** (shows/hides within UI): extend `AnimatedVisibilityContainer`. Sounds are automatic.
- **Full-screen overlay** (backdrop + centered dialog): extend `AnimatedCanvasLayerPanel`. Sounds are automatic. Override `_on_panel_ready()` for setup, and use lifecycle hooks for custom behavior:

```gdscript
extends AnimatedCanvasLayerPanel
class_name MyDialog

func _on_panel_ready() -> void:
    # Connect signals, load data, etc.
    my_button.pressed.connect(_on_my_button_pressed)

func _on_after_animate_in() -> void:
    my_button.grab_focus()

func _on_after_animate_out() -> void:
    closed.emit()
    queue_free()
```

### Adding a Sound
A new sound is a spec, an install and a call; nothing in `audio_manager.gd` changes.

1. **Spec.** Add a `SoundSpec` entry in `tools/sfx_spec.py` (see "Regenerating and Iterating"
   above): its bus (`"ui"` or `"sfx"`), the synthesis fields, and the playback fields
   (`volume_db`, `pitch_jitter`, `cooldown_s`, and a `priority` tier from "Playing a Sound").
   There is no file to source, since the palette is synthesized, not sampled. Render and
   audition it (`generate_sfx.py --only <name> --variants N --sheet`), then run
   `generate_sfx.py --verify` to confirm it passes the gate.
2. **Install.** `generate_sfx.py --install` writes the `.wav` and the manifest entry; then
   re-import (`godot --headless --import --path .`) and commit both, with the `.wav.import`.
3. **Call.** `AudioManager.play(&"<name>")` from the game code that owns the moment.

`tools/tests/test_sfx_spec.py` checks that the spec, the installed files and the committed
manifest name the same sounds, so a missed step fails the test rather than playing silence.

---

## Implementation Checklist

### Phase 1: Audio Files
- [x] `assets/audio/ui/click.wav`
- [x] `assets/audio/ui/hover.wav`
- [x] `assets/audio/ui/open.wav`
- [x] `assets/audio/ui/close.wav`
- [x] `assets/audio/ui/success.wav`
- [x] `assets/audio/ui/error.wav`
- [x] `assets/audio/ui/confirm.wav`
- [x] `assets/audio/ui/cancel.wav`
- [x] `assets/audio/ui/tick.wav`
- [x] `assets/audio/ui/transition.wav`
- [x] `assets/audio/ui/leave_game.wav`
- [x] `assets/audio/sfx/token_pickup.wav`
- [x] `assets/audio/sfx/token_drop.wav`
- [ ] `assets/audio/sfx/token_slide.wav` (generated and installed, not wired to any trigger yet)
- [x] `assets/audio/sfx/token_hover.wav`
- [x] `assets/audio/sfx/token_whoosh.wav`
- [x] `assets/audio/sfx/splash_enter.wav`
- [x] `assets/audio/sfx/splash_exit.wav`

All files are generated by `tools/generate_sfx.py --install` from the `SoundSpec` entries in
`tools/sfx_spec.py` (see "Regenerating and Iterating" above) — there are no third-party CC0 packs
to track or license anymore. Regeneration is deterministic: running `--install` from a clean
checkout reproduces byte-identical files to the ones committed (verified — `--install`, `--seed`
defaults to 0, and neither `generate_sfx.py` nor `sfx_synth.py` reads any other source of
randomness for variant 0). All files still pass through the pre-commit normalization hook like
any other audio file (see "Volume Normalization" above); in practice they already render at the
palette's own peak target and normalization is a no-op.

### Phase 2: Wiring (done)
- [x] Auto-connect all button click/hover sounds via `SceneTree.node_added` -- hover has since been
  turned off via `AudioManager.BUTTON_HOVER_SOUND_ENABLED`; click stays automatic
- [x] Panel open/close sounds in `AnimatedVisibilityContainer` base class
- [x] Panel sounds via `AnimatedCanvasLayerPanel` base class (SettingsMenu, PauseOverlay, ConfirmationDialogUI, UpdateDialogUI)
- [x] Level editor popup sounds (open/close + X button close on LoadDialog and DeleteConfirmDialog)
- [x] Specialized confirm/cancel sounds in `ConfirmationDialogUI`
- [x] Token drop sound plays at settle start (immediate feedback on release)
- [x] Token whoosh sound on rapid drag (velocity-based trigger with pitch scaling) -- since turned
  off via `AudioManager.TOKEN_WHOOSH_SOUND_ENABLED`; the trigger stays wired
- [x] One entry point, `AudioManager.play(&"name")`, driven by the manifest; one sound per
  gesture through per-frame coalescing; pause no longer freezes a playing sound
- [x] Only user actions sound: toggles tick on `pressed`, Settings loads and resets without
  ticks, downloads chime once per pack (the toast), `token_hover` only on draggable tokens with
  a 150 ms cooldown; avatar builder plays confirm/cancel; a mid-game join plays `success` as the
  lobby does; volume sliders use a squared taper and the Music row is hidden
- [ ] Wire `token_slide` to token movement
- [ ] Sounds for authoring actions (prop place/remove, undo/redo), with the palette work

### Phase 3: Expanded SFX (optional)
- [ ] Add token snap, rotate, scale, cancel sounds to the palette
- [ ] Add level transition sounds to the palette
- [ ] Wire the new sounds to game interactions
