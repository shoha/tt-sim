# Authoring mode and brushes

The in-game state in which an author builds a new map or dresses an existing one, and the
brushes that edit the map document. The long form is
[../ARCHITECTURE.md](../ARCHITECTURE.md) "Authoring Flow" (its Brushes part for the tools) and
[../UI_SYSTEMS.md](../UI_SYSTEMS.md) "Authoring Mode"; the hub with decisions and open work is
[../MAP_AUTHORING.md](../MAP_AUTHORING.md). This doc holds the system's map and the rules the
code keeps (moved from `AGENTS.md` Key Conventions on 2026-10-09). A recipe for adding a tool
stays in `AGENTS.md` "Adding Features" ("New authoring tool").

## Map

| File | Class | Role |
|------|-------|------|
| `scenes/root.gd` | | The root state machine: `State.AUTHORING`, `request_authoring(level, return_to)` |
| `scenes/states/authoring/authoring_controller.gd` | `AuthoringController` | Owns the state: its own `LevelEnvironmentManager`, the load, `write_level()` |
| `scenes/states/playing/map_source_loader.gd` | `MapSourceLoader` | The load shared with `LevelPlayLoader`; `separate_props`, `install()` |
| `scenes/states/authoring/new_map_dialog.gd` | `NewMapDialog` | The new-map dialog |
| `utils/new_map.gd` | `NewMap` | Size, base surface from the biome, starting cover; `create_dressing` |
| `scenes/states/authoring/authoring_session.gd` | `AuthoringSession` | The dirty state |
| `scenes/states/authoring/authoring_autosave.gd` | `AuthoringAutosave` | Autosave |
| `scenes/states/authoring/authoring_history.gd` | `AuthoringHistory` | The undo seam |
| `scenes/states/authoring/authoring_tokens.gd` | `AuthoringTokens` | The level's tokens, spawned as play does, saved back as placements |
| `utils/token_grounding.gd` | `TokenGrounding` | Sets saved tokens down on ground that moved (authoring and play load) |
| `scenes/states/authoring/tool_registry.gd` | `ToolRegistry` | Every map tool in rail order; the panel, the controller and F1 help read it |
| `scenes/states/authoring/tools/tool_descriptor.gd` | `ToolDescriptor` | One tool's declaration and its hooks; `BiomeTool` ... `BridgeTool` beside it |
| `scenes/states/authoring/authoring_panel.gd` | `AuthoringPanel` | The tool drawer: rail, panes, the session footer, Escape |
| `scenes/states/authoring/brush_tool.gd` | `BrushTool` | The host every tool's gestures share: pointer, ground ray, size, dab stroke, `decide()`; dispatches to the tool's mode |
| `scenes/states/authoring/brush_mode.gd` | `BrushMode` | One tool's gestures and cursor; `BiomeBrush`, `ThinBrush`, `PlaceBrush`, `SculptBrush` (`sculpt_op()`), `PaintBrush`, `WaterBrush`, `BridgeBrush` beside it |
| `scenes/states/authoring/brush_cursor.gd` | `BrushCursor` | The cursor overlay and the ring every mode can draw |
| `scenes/states/authoring/authoring_editor.gd` | `AuthoringEditor` | One per opened map; owns the edits |
| `scenes/states/authoring/height_editor.gd` | `HeightEditor` | `AuthoringEditor.heights`: sculpt strokes and the height work they, water edits and live edits share |
| `utils/live_edit_codec.gd`, `utils/live_edit_reader.gd` | `LiveEditCodec`, `LiveEditReader` | Live edits: a history entry's redo or undo side as bytes, the decode checks, the peer's queue, chunks and the sender's pacing |
| `scenes/states/playing/live_edits.gd` | `LiveEdits` | A table's live edits on every peer: the play-side editor, the op log, sending (GM) and catching up (clients) |
| `utils/mask_stroke.gd`, `utils/mask_brush.gd` | `MaskStroke`, `MaskBrush` | Mask strokes and their pure rules |
| `utils/surface_stroke.gd` | `SurfaceStroke` | The Paint tool's stroke |
| `utils/height_brush.gd` | `HeightBrush` | Sculpt rules: `tier_target_level`, `tier_goal()` |
| `utils/base_scatter_eraser.gd` | `BaseScatterEraser` | A dressed GLB's own scatter, re-filtered live |
| `utils/prop_rows.gd` | `PropRows` | Prop rows in `AuthoredProps` |
| `utils/scatter_shrink.gd` | `ScatterShrink` | Removed scatter shrinks out |

## Model

- `Root.State.AUTHORING` is appended to the state enum and is offline only:
  `Root.request_authoring(level, return_to)` is the one entry, refused while networked. It
  builds or dresses a map inside the real `GameMap` (`setup_authoring()`: GameplayMenu hidden
  and disabled; token drag stays on while no brush is active).
- Authoring is a faithful preview of play (2026-10-09; there is no "Try" step). The level's
  tokens spawn as play spawns them (`AuthoringTokens`: models preloaded, then
  `BoardTokenFactory.create_from_placement_async` into the same DragAndDrop3D), so occlusion
  fade, drag landing, the float rule and grid snap come from `GameMap` as in play. A move,
  turn or resize is one `AuthoringHistory` entry and marks the session unsaved; a save
  copies every token back into its placement (`write_placements`). Authoring adds and
  removes no tokens. F3 opens play's `PerformanceOverlay` and `DebugRenderToggles`
  (`AuthoringController.setup`; log rows are tagged map "unknown").
- Tokens follow their ground (`TokenGrounding`): a token that no longer stands where a drop
  at its spot would land (ground sculpted, carved or filled under it, a dressed GLB
  re-exported) is set straight down there, from its own top, or from above the map when
  raised ground buried it. Authoring re-grounds after each edit settles (one physics frame
  on) and before each save; a play-time load re-grounds every placement as it spawns
  (`LevelPlayLoader`, before tracking, so GameState and peers get the grounded position).
  Props have no collision, so a token inside a placed prop stays there; authoring shows it.
- Save equals reload. `ScatterGenerator` snaps the rows it generates to the saved precision
  (`MapDocumentIO.snap_rows`, `ROW_DECIMALS` 6), so a regenerated cell and the same cell
  read back are bit-equal. A save replans the ground layers from scratch when the session's
  plan ran out of slots (`AuthoredTerrain.replan_ground_layers`), as every load plans.
  `test_authoring_save_reload.gd` edits through `AuthoringEditor` (sculpt, Paint, a biome
  stroke, a prop), saves, reloads through `MapSourceLoader` and compares every
  `MapFingerprint` key; the fingerprint sorts each asset's rows, since play merges props
  into the scatter node.
- `AuthoringController` (`scenes/states/authoring/`) owns its own `LevelEnvironmentManager`,
  loads through `MapSourceLoader` (shared with `LevelPlayLoader`; `separate_props` keeps props
  in `AuthoredProps`) and `MapSourceLoader.install()`, and treats the `MapDocument` as the
  source of truth: rows are copied back from the AuthoredScatter nodes before each write.
- New maps come from `NewMapDialog` + `NewMap` (size, base surface from the biome, starting
  cover). A GLB-only level opens as a dressing layer (`NewMap.create_dressing`).
- Save is `AuthoringController.write_level()`: `map.ttmap` first, then `level.json`, then the
  thumbnail. Dirty is `AuthoringSession`. Autosave is `AuthoringAutosave`
  (`_autosave/map.ttmap` + `map_level.json`). The undo seam is `AuthoringHistory`
  (`record({label, undo, redo, bytes})`, capped at 100 entries and 64 MB).
- One camera model (`MapViewFit`, 2026-10-09), owned by `AuthoringController` and
  `LevelPlayController` alike: zoom-out reaches the whole map, never less than 20
  (`GameMap.set_zoom_limits`, `fit_zoom_for_extent`, margin 1.08, 12 m of canopy above the
  highest ground); an authored map without a GLB pans within its own extent; every frame the
  near plane follows the highest ground and the sun's shadow distance follows the view
  (`LevelEnvironmentManager.fit_shadow_distance_to_view`). The extent is the document's, or a
  Blender map's mesh bounds when it has none. Authoring refits when a sculpt moved the ground's
  range, play when the GM changes the map scale. Play at whole-map zoom measured 11.2 to 14.5
  ms GPU median from 200 to 400 ft maps (size_probe, 2026-10-09).
- Packed arrays are shared by reference in GDScript: duplicate before handing one to a worker
  or keeping it for undo ([../CONVENTIONS.md](../CONVENTIONS.md) Threading Gotchas).

## Authoring

- `BrushTool` (created by `GameMap.setup_brush_tool()`) hosts the gestures; its input table is
  the pure `BrushTool.decide()`, and each tool's own gestures are its `BrushMode` (Tools
  below).
- `AuthoringEditor` (one per opened map) owns the edits. `MaskStroke` writes the document's
  masks, with its rules in the pure `MaskBrush`: `(1 - t^2)^2` falloff, exposure
  `1 - exp(-3 w s)` toward the target, the biome replacement contest, and the erase mask's
  thin-then-erase noise rule.
- `flush()`, once per frame, sends the changed sample rectangle to
  `AuthoredTerrain.update_biome_region()`, `AuthoredScatter.request_region()` and
  `BaseScatterEraser.refresh()` (a dressed GLB's own scatter, re-filtered live with the
  loader's rule).
- Props are `PropRows` rows in `AuthoredProps`.
- History stores per-block (40 x 40 samples) ZSTD mask diffs and per-cell prop rows, never
  whole documents.
- Removed scatter shrinks out (`ScatterShrink`).
- The Paint tool's mode is `PaintBrush`:
  `AuthoringEditor.begin_surface_stroke(surface, erase)` runs a `SurfaceStroke` (the
  MaskStroke pattern on `MapDocument.surface_weights`: slot claim through `ensure_surface()`,
  trailing empty slots trimmed at stroke end, per-block diffs), blits the ground per frame,
  and regenerates scatter at stroke end only for built or cliff-role surfaces.
- The Sculpt tool's mode is `SculptBrush`: the press's operation is the pure
  `SculptBrush.sculpt_op(tile, ctrl, shift)`; Tier's target is `AuthoringEditor.tier_target()`
  (a whole tier, `HeightBrush.tier_target_level`) and its cliff profile `HeightBrush.tier_goal()`
  (tops exactly on `k * tier_height_m`). Height edits and their refresh calls are in
  [authored_terrain.md](authored_terrain.md). `HeightEditor` (`AuthoringEditor.heights`, split
  out on 2026-10-09 like `WaterEditor` and `CrossingEditor`) runs the strokes and owns the
  height work: chunks within `TERRAIN_BUDGET_USEC` (4 ms) and plant and prop snapping within
  `SNAP_BUDGET_USEC` (2.5 ms) a frame, the collision, rock keeping, the regeneration;
  `AuthoringEditor`'s height entry points (`begin_height_stroke`, `has_height_work`,
  `step_height_work`, `finish_height_work`) forward to it. A sculpt diff carries the samples
  it changed (`HeightStroke.finish`, "changed"), and undo and redo redo only those, not the
  diff's whole 40-sample blocks (a block reaching the grid's edge also refreshed the skirt).

## Tools

- One registry (2026-10-09): `ToolRegistry` lists one `ToolDescriptor` per tool, in rail
  order (Biome, Thin / Clear, Place, Sculpt, Paint, Water, Bridge), and nothing else lists
  tools. `AuthoringPanel` builds its rail items (`ToolRegistry.rail_items`) and one pane per
  tool from it; `AuthoringController._select_tool` goes through it (and hands the brush the
  descriptor, `BrushTool.use_tool`); the F1 help overlay puts each tool's rows between the
  shared Map building rows.
- A descriptor declares the id, label (rail tooltip and pane title), summary (pane caption
  and help row), rail icon, an optional shortcut (a bare `Key`; none of the seven has one,
  so a key is still free to give), its `brush_mode` (the `BrushMode` class its gestures run
  in), its own help rows, an unavailable tooltip, and its contexts
  (`ToolDescriptor.AUTHORING`, `PLAY`; every query takes one). Play lists Biome, Thin /
  Clear, Sculpt, Paint, Water and Bridge, the GM's Events pane (see "Live edits"); Place is
  authoring's alone. `works_on(editor)` is the map half of `can_select`, asked of an editor
  alone, so play asks it of the live editor.
  A tool whose pane sets what its mode paints has a static `of(brush)` returning that mode,
  typed (`SculptTool.of(brush).tile`, `WaterTool.of(brush).depth`).
- Hooks, which read the controller's public state only: `can_select` refuses a pick the open
  map cannot take (Sculpt, Paint: the document's own ground; Water, Bridge:
  `WaterTool.has_water_work`), `armed` leaves the brush put down while it has nothing to
  work with (Biome before a biome is picked, Paint without a surface), `prepare` warms what
  the first stroke would wait on (Paint's textures, Water's falls and flow materials,
  Bridge's crossings), and `refresh` sets the rail item's state after the map opens and after
  every edit, undo and redo (`_refresh_tools`).
- Panes: the seven tools' panes are `AuthoringPanel`'s own (`_build_pane`: five inline, plus
  `WaterToolPane` and `BridgeToolPane`, whose signals the panel relays to the controller). A
  new tool returns its pane class from `build_pane` and wires it in `connect_pane`, so it
  edits neither hub.
- Gestures (2026-10-10): `BrushTool` is a host that knows no tool by name. It keeps the
  pointer and its ground ray, the press and its modifiers, the brush size and flow, and the
  dab stroke with its dwell gain, and routes the current tool's press, frames, release,
  cancel, size step, target removal and cursor to its `BrushMode`. `BrushTool.mode_for`
  makes one mode per tool and keeps it, so a tile picked survives switching tools.
- A mode's hooks (`brush_mode.gd` has the contract): `press` returns true when it began an
  editor stroke the host is to dab (Biome, Thin, Sculpt, Paint, a pond or a water erase);
  otherwise the mode does its own work in `frame`, `end` and `cancel` (Place's prop,
  Water's river line, Bridge's line). `step` is the Shift+wheel and bracket gesture,
  `picks` / `has_target` / `remove_target` the Place-style target under the pointer,
  `sees_crossings` lets the ray pick crossings (Bridge), `fades` and `fade_focus` the canopy
  fade, `min_radius` and `stroke_radius` the ring's size, `hit_past_edge` a mode's own ground
  past the map edge (a river). A refused press or release emits the host's one `refused`
  signal with the reason, which the controller toasts.
- Cursor: `draw_cursor(brush, cursor)` draws on `BrushCursor`'s overlay; the default is the
  conformed ring (`BrushCursor.draw_ring`, in `cursor_tint` with `cursor_text` under it).
  Sculpt conforms it to the document's heights every frame, Water draws its previews under
  it, and Place and Bridge draw cursors of their own.
- Modes reach the editor and the host only, never `AuthoringController`, so a play-side host
  (the GM's Events pane over `LiveEdits.editor`) can run the same modes. A new tool with
  gestures adds its `BrushMode` subclass beside `water_brush.gd` and names it in its
  descriptor; it edits no brush code.

## Live edits

The GM's terrain events during play (a bridge collapsing, a forest falling, fire, biome and
terrain changes with the authoring brushes; user decision, 2026-10-09) replicate as one side
of authoring history entries. The codec, the apply side and the transport exist
(2026-10-09), and the GM's UI, the Events pane, with its first two presets (2026-10-10).
Probe and numbers:
`docs/plans/2026-10-09-v0.2-evaluation/probes/live_edits_probe.md` (gitignored). Transport:
[../NETWORKING.md](../NETWORKING.md) "Live map edits".

- **The Events pane** (`EventsPane`, `PlayEvents`, `scenes/states/playing/events/`): the
  Visuals drawer's last rail item (wand), so the GM's alone. It lists the play brushes
  (`ToolRegistry.tools(PLAY)`) as toggling tiles, then the picked brush's controls built from
  the authoring panes' parts (Sculpt's shape tiles, the palette biome and surface tiles,
  `WaterToolPane` and `BridgeToolPane` with their headers hidden, one Advanced foldout with
  size and strength); the presets with spectacle (Drop bridge, Topple trees, Start a fire)
  take a field headed "Happenings" (`EventPresets.HEADING`), one row of three, above the
  brushes. The
  picked tool's controls stand directly under its own field (`show_tool` moves them), and a
  preset put away takes its line and Advanced with it (`PlayEvents` forgets the pick), so the
  pane is as fresh. The look's foot (Revert look, Save look) steps out under it. A map
  that takes no live edits says why in the pane (`PlayEvents.refusal_for`: a player, a Blender
  map without a document, the table still setting out, a client's side); a brush the map
  cannot take is a disabled tile with its descriptor's unavailable tooltip (set through
  `TileRow.set_tile_tooltip`, so a refit on the drawer opening keeps it).
- **Arming** (`PlayEvents`): a pick arms GameMap's own `BrushTool` (`setup_brush_tool`, made
  on first use) with `editor` the live editor and the level's units, the mode set from the
  pane as `AuthoringController` sets it. The brush's tile again, Esc or a right click puts it
  away; Biome waits for a biome, and Paint takes the surface its pane opens on. While it is
  out its keys lead the hint bar (`PlayEvents.hints_for`, at most five, one line at 720p with
  the drawer open: the gestures, then for every brush `[ ]` Size or Width, Ctrl+Z Undo and Esc
  "Put away Sculpt", which names it), token drag and the right-button pan are off (GameMap's
  modal-tool rules), Ctrl+Z and Ctrl+Y undo and redo through `live_edits.history` (GameMap
  leaves Ctrl+Z to the brush's owner while one is out; their toasts read "Raise undone"), and
  an edit that changed a lot (`PlayEvents.is_large`: a river, pond or crossing edit, or a
  stroke whose entry holds 12 KB or more; one 4 m mound is about 4 KB, a 9 m Clear sweep 15
  KB) offers Undo in a toast while it is still the newest entry (`AuthoringHistory.is_newest`):
  "Cleared for everyone at the table" (`PlayEvents.done_phrase`), one line at 720p (a toast
  hugs its line, up to 360 px, 520 with an action, `ToastContainer.ACTION_MAX_WIDTH`). A click
  that never leaves its spot (within `DWELL_RADIUS`) gets at least `PLAY_CLICK_SECONDS` (0.6 s)
  of exposure, topped up when the stroke ends (`BrushTool.min_stroke_seconds`, set on a pick
  and cleared when the brush is put away; authoring keeps `CLICK_SECONDS`), so a GM's quick
  Sculpt click raises a visible mound (over 0.12 m at radius 4; `CLICK_SECONDS` alone gives
  about 0.05 m).
- **Presets with spectacle** (`EventPresets`, play-only `ToolDescriptor`s outside
  `ToolRegistry`; `CollapseMode`, `ToppleMode`, BrushModes with a `fired(event)` signal). Tile
  labels say what the cursor pills say, and the icons show the break (`bridge-broken`,
  `tree-falling`) so no preset repeats a brush's picture. Both events undo, so both cursors
  wear one warm ochre (`ToppleMode.TINT`, `ThemeColors.OCHRE_LIGHT`; madder is the danger
  confirm's alone). Drop bridge outlines the deck under the pointer, with a thin chalk edge
  0.1 m inside the ochre (`CollapseMode.EDGE`: the ochre alone vanished over a sunlit plank
  deck) and "Drop bridge" in a chip under the outline's lowest point
  (`BrushCursor.draw_readout`, as Topple's), and fires on a click; it is a disabled tile on a
  map with no deck crossing (`PlayEvents.has_bridge`; tooltip
  `EventPresets.NO_BRIDGE_TOOLTIP`, and the caption "No bridge on this map" under the preset
  tiles, `EventsPane.preset_note`, since a disabled tile alone read as one at rest), and
  stepping stones or a ford draw the small ring in chalk_soft (`CollapseMode.REFUSED_TINT`:
  nothing happens there, so not the "do" ochre), say "Only a bridge falls" and refuse a click.
  Topple trees fires on a click within its ring ("Topple trees"; a drag widens the ring,
  Advanced shows its size alone) and marks each tree that will fall with a small ochre spot
  on the ground at its foot, inside the ring (`ToppleMode.base_marks`: exactly
  `ForestFall.trees_near`, each spot 3 % of its tree's height in radius and 9 to 36 px
  across, searched again when the ring moves 0.3 m or every 0.5 s; a blaze across the trunk
  before it floated over undergrowth where no trunk showed); a spot with no tree is refused by
  toast (`TerrainEvents.NO_TREES`). The cursor pills and the brush readouts are glass chips
  (`MapOverlayUtils.draw_chip`: the hint bar's Chip, chalk caption 14). Hint rows: Drop bridge
  Click, Ctrl+Z, Esc "Put away"; Topple trees Click, Drag "Wider stand", `[ ]`, Ctrl+Z, Esc
  "Put away" (the first key names the preset). Start a fire (`IgniteMode`, a ToppleMode:
  the same ring, click and drag; icon Tabler `flame`) draws the ochre ring with "Start a
  fire" and no marks (the whole forest in the ring burns); where no tree stands in the ring
  (the burnt forest's own snags do not count, `FireSweep.burnable`) the ring is chalk_soft
  with "Only a forest burns" (`IgniteMode.ring_look`) and a release is refused through the
  brush's `refused` (`TerrainEvents.NO_FOREST`). Hint row: Click "Start a fire", Drag "Wider
  fire", `[ ]`, Ctrl+Z, Esc. A fired event goes to `TerrainEvents.start`;
  the drawer steps aside as it starts (`stroke_started`) and the preset stays armed for the
  next one, until Drop bridge has no bridge left and puts itself away.
- **Terrain events** (`TerrainEvent`, `utils/terrain_event.gd`; `TerrainEvents`,
  `scenes/states/playing/events/terrain_events.gd`, a child of `LiveEdits` made in
  `LiveEdits.create`, `LiveEdits.events`): an event is a few parameters (kind, table key,
  centre, radius or crossing id, duration, the host's lead, a seed; 32 bytes), never document
  state. The GM's side checks it (`refusal_for`: at most `MAX_ACTIVE` 4 at once, the bridge
  still there and not already falling, a tree in the circle), stamps the table key and the
  lead (0.1 s hosting, 0 solo), broadcasts it (NETWORKING.md "Live map edits") and plays it
  after the lead; a client plays it on receipt. One clock, `advance(delta)` (`_process`, tests
  and the render probe call it). Once the motion has played, the GM's side makes the change on
  the live editor as one history entry labelled as its tile, "Drop bridge" or "Topple trees"
  (`TerrainEvents.label_for`, `EventPresets.for_kind`; so Ctrl+Z says "Topple trees undone"),
  with `entry.preset` its kind (`_on_recorded` is connected before PlayEvents hears the
  history, so the label is set first): the crossing removed (`crossings.remove`), or one CLEAR
  dab of 2 s at 1.3x the radius (99.8 % of the density at the fall's radius), or for a fire
  ("Start a fire", 4 s) a group of two strokes (`TerrainEvents._burn`,
  `AuthoringHistory.begin_group`/`end_group`: one entry whose `parts` redo in order and undo
  in reverse): the burnt biome painted over the forest (one dab at 1.2x the radius for 3 s:
  MaskStroke's contest hands the ground to it out to about the radius and thins the forest
  past it), then ash laid over it (one Paint dab at 1.25x for 2.5 s), as
  ASSET_PIPELINE.md "Fire" says (`FireSweep.plan_for`: the palette biome whose `biome` is
  `burnt_forest`, else a Clear as a fall's, which a map with a full biome list gets too; the
  surface `ash`, else `dirt_peat`, else none). LiveEdits sends an entry as its ops
  (`LiveEditCodec.ops_of`: one, or one per part, reversed for an undo), so a late joiner gets
  only the ops (a fire's two) and an undo restores the map without replaying anything. A fire
  or a fall refuses a circle where either is already under way, and a fire one with no tree
  but the burnt forest's snags. The GM's toast for the entry always offers Undo
  (`PlayEvents.PRESET_DONE`: "The bridge fell for everyone at the table", "The trees fell
  ...", "The forest burned ..."); a client's side shows its players a chip without Undo as
  the event starts playing (`TerrainEvents.show_notice`, `NOTICES`: "The bridge fell", "Trees
  fell in the forest", "A fire swept through the forest", 5 s; UI_TASTE G13, G14). Each wears
  the event's own icon (`icon_for`: `bridge-broken`, `tree-falling`, `flame`) in the info
  tint. An effect stays, drawing nothing, until
  its change lands (the crossing node freed, every held cell's scatter rebuilt) or
  `RELEASE_AFTER_S` (8 s), then lets go of what it hid (`release()`).
- **The effects** (`scenes/states/playing/events/`), bounded so a frame only sets transforms:
  `BridgeCollapse` cuts the crossing node's own meshes into at most 10 pieces by triangle
  centroid along the span (index-only per piece, sharing the vertex arrays and materials; the
  cut runs once), hides the crossing, shudders it 0.35 s, breaks it from the middle out over
  0.55 s, tips and drops each piece under gravity, throws spray where a piece meets the water
  (`WaterGeometry.level_at`), and sinks and shrinks the pieces in the last 0.3 s (2.2 s).
  `ForestFall` finds the drawn trees from AuthoredScatter's public API (`trees_near`:
  `cell_rows`, `get_cell_node`, `get_growing_nodes`, `row_keys`,
  `ScatterRows.instance_order`, the node's `visible_instance_count`), hides up to 48 instances
  by a zero-scale transform in their chunk and animates stand-in MultiMeshes of the same
  meshes: a ripple from the centre (0.6 s, 0.15 s jitter), a lean then an accelerating fall
  (0.8-1.0 s) to a rest angle propped on the crown (`rest_angle`, 62-88 deg from the mesh's
  bounds), a 5 deg rebound, then they settle into the ground (2.8 s). A falling tree goes
  still: the stand-in's instance colours multiply the mesh's authored wind weights (vertex
  COLOR R sway, G flutter) and `calm_weight` takes both to 0 over the first 40 % of its fall,
  so it stops swaying and the canopy fade, which always keeps a trunk (flutter under
  `CANOPY_LIMB_FLUTTER`), keeps its whole crown. Before, a crown lying toward the camera near
  the view centre sat in the fade's depth band (about 70 % of its cards gone at zoom 16) and
  read as a bare log; the render job's `fall_3_nofade` A/B shows the fallen crowns now match
  with the fade off. `ScatterShrink.hold` keeps the Clear's rebuild from standing the held
  instances up to shrink them. Puffs (`EventPuffs`, one pooled MultiMesh of 96 puffs, no
  allocation while they play; `shaders/event_puff.gdshader`: an unshaded lobed soft shape lit
  from above over a cool shade, melting into what it touches by a depth proximity fade, drawn
  after the water's transparent pass at render priority 2, in the graphics warm-up) come in
  three kinds: a blob faces the camera with its length along a world axis as it falls on
  screen (upright, along a trunk, or along a drop's flight), drawn a little toward the camera
  so a fallen crown does not swallow it; a plume is a column standing on its point that
  shoots up and falls back into a mound (`plume_rise`), upright or leaning out; a ring lies
  flat on the water and spreads, thinning. Dust is golden ochre at alpha 0.5, two puffs per
  tree as its crown lands: a squat billow there, rolling on the way it fell, and a long roll
  along the trunk sliding to one side (three small puffs at 0.4 all but vanished). A splash
  is sized to its piece (1.1-1.8 m): a crown column, three tongues leaning out, three drops
  on arcs, and a foam ring spreading to twice the piece's size over about 1.5 s, white on top
  over a pale blue shade and a bluer clear rim (eight tongues a fifth of a plank wide read as
  confetti at tabletop zoom; round puffs as cotton or steam). Eight puffs a splash, so all
  ten pieces fit the pool. `FireSweep` (a ForestFall: the same search, stand-ins, holds and
  release through its hooks `_find`, `_make_puffs`, `_tree_entry`, `_stand_in_mesh`) runs a
  front out from the click (the nearest tree catches at once, the farthest 2.0 s later,
  0.25 s jitter), and the fire reads through the trees themselves: each stand-in draws a copy
  of its tree's mesh whose surfaces use `wind_foliage_burn.gdshader` (the wind material
  duplicated, its shader swapped), and over its 1.2-1.5 s burn the instance's custom data
  (`burn_progress`) takes its crown through the burn in bold patches about a metre across
  (height plus slow noise): hot yellow only along the leading edge, then ember red-orange
  with deep red patches (a second, finer noise; emission), dimming as it goes to charcoal,
  the leaf cards burning away from a glowing edge until a bare charred snag stands. Bark
  never glows, it only chars (a glowing trunk read as a thin orange beam). One painted
  flame (`FlameAtlas`: a 4-frame flipbook of three tongues in red, amber and pale gold bands,
  painted once into an RG8 texture, cross-faded on the shader's clock) stands on each crown
  as it catches, sized by the crown's width (0.85 of it, within 0.22-0.38 of the tree's
  height; sized by height a narrow pine's stood as a beam), a smaller second beside it
  (across the view) on half the trees, a spark on a third; half the trees and a two-billow
  column over the middle throw up smoke: painted cumulus billows of seven lobes melted into
  one outline, a grey-violet body over a dark violet underside with each lobe's upper rim in
  cream gold, nearly opaque, spreading as they rise, their lobes breaking apart late
  (the billow's age rides in its custom data) and their alpha held to 85 % of their life
  (`smoke_fade`). No ground glow. The snags shrink away about their feet over the last
  0.6 s (`snag_transform`) as the change lands. Two pools sized so one fire's every puff fits
  at once (`EventPuffs.new(capacity, priority)`: smoke 50 at priority 3, flames 144 at 4).
  Puff and shader colours are linear and the scene's filmic tonemap (white 1.0) shows a low
  value lighter still than raising it to 1/2.2 does, so each is picked through that curve
  (measured in a capture: linear 0.147, 0.124, 0.172 shows 0.54, 0.5, 0.57; 0.85, 0.58, 0.265
  shows 0.96, 0.88, 0.68): the first look's amber (0.7 green) and lilac smoke (0.6-0.8)
  showed as cream and pink mist, and a plum body lit rust underneath as salmon. The
  fire-look card (2026-10-10) probed three approaches side by side (bold opaque tongues, the
  trees burning, a painted flipbook): the burning trees read as a fire at tabletop zoom and
  the sprites alone did not, and the painted flame read as a flame where the procedural
  tongue read as an egg, so it is the trees plus painted flames. Fire's kinds hold their
  alpha to 65 % of their life (`fire_fade`). Headless,
  `surface_get_arrays` may return nothing and MultiMesh transforms read identity, so the
  effects compute from the document's rows and tolerate empty meshes; tests check behaviour,
  not pixels (the render job `terrain_events` checks the look).
- **The board is the GM's while they work** (UI_TASTE G11): the drawer stays open while a
  brush and its settings are picked, and the first press on the board sends it aside
  (`BrushTool.gesture_started` -> `PlayEvents.stroke_started`; GameplayMenuController closes
  it, keeping any look changes), so no ring works on ground under the glass. Chosen over a
  compact brush strip because the brushes' controls (biome and surface tiles, Water's shape,
  depth and flow) do not fit a strip, and because the board, not the panel, is where the work
  is judged. The brush stays out, named in the hint bar; the Events rail item stays tinted and
  opens the pane again. The canopy over the ring opens only while a press is held
  (`BrushTool.fade_held_only`, set by PlayEvents and cleared when it puts the brush away), so
  the GM sees the result whole once they let go. Add token and Save map fade out while an
  open drawer covers them (`GameplayMenuController.on_drawers_moved`).
- **The ground follows** (`LiveEditGround`, a child of the service on every peer): once the
  edits have settled it refits the camera, pan and shadow bounds and the reflection probe
  (`LevelPlayController.refit_view_to_ground`), samples a Blender map's grid ground again when
  its water or crossings changed (an authored map's grid follows the terrain by itself), and on
  the GM's side sets every token down on the new ground and sends the moved ones to every peer
  (NETWORKING.md "Live map edits").

- **The table's service** (`LiveEdits`, `scenes/states/playing/live_edits.gd`): every peer
  of a table set out from a map document has one, a play-side `AuthoringEditor` (no UI,
  `water.use_worker` on) over its own loaded copy (`LevelPlayController.live_edits`, made by
  `start_live_edits()` once the map is installed, freed with it). The GM's side runs the
  brushes on `live_edits.editor`, which records into `live_edits.history`; the history's
  `recorded`, `undone` and `redone` signals turn each entry into one op once the editor's
  height work has drained, appended to `op_log` (plain bytes, the table's events for a session
  file). A client checks and applies ops in order through a `LiveEditCodec.Queue`; a catch-up
  (a late joiner's) is applied at once (`Queue.drain()`). A Blender map with no document takes
  none (`LiveEdits.refusal()`). Live edits change the session's copy, never `map.ttmap`; a
  later "Save into map" would.
- **Op format** (`LiveEditCodec`): `{"v": 1, "kind", "args", "redo"}`, one op per history
  entry's redo or undo, at most `MAX_BYTES` (4 MB, crossing in 64 KB chunks). The six kinds
  and the public methods they go through, which are the methods history binds: `mask`
  `AuthoringEditor.apply_mask_diff`, `surface` `apply_surface_diff`, `props` `set_prop_cell`,
  `height` `HeightEditor.apply_diff`, `water` `WaterEditor.apply_edit`, `crossings`
  `CrossingEditor.apply_list`. One side travels: a record or redo its after side, an undo its
  before side (`"redo": false`: diffs with their before blocks, records with their `*_before`
  fields, applied with `redo` false, so a kept rock goes back into the scatter and a mask the
  stroke allocated is dropped as the host's undo does); both id lists of a diff travel either
  way (`SurfaceStroke.changes_plants` reads both). A props or crossings undo is the same method
  with the before rows or list. Water bodies and crossings travel as the document's JSON
  (`MapWaterIO.body_json`, `MapCrossingIO.crossing_json`). `op_of(entry, editor, undo)` reads
  the entry's redo or undo Callable; it finishes the host's height work first, since a
  sculpt's record is complete only once its kept rocks land. Payloads on a 200 ft map: 0.1 to
  10 KB.
- **Checks** (`LiveEditReader`, run by `decode(bytes, doc, palette_root)`): the byte cap
  before `bytes_to_var` (which refuses objects); version and kind; rectangles inside the grid;
  mask names whitelisted (`MaskStroke.apply_diff` sets the property a diff names); every block
  decompressed to exactly its rectangle's size; slot bytes within the op's biome list; finite
  heights within `MAX_ABS_HEIGHT_M`; a pond mask of 0 or the grid's samples whose bytes all
  name ponds; a wet dressing of 0 or 4 bytes a sample; bodies and crossings through
  `MapWaterIO.parse_bodies` and `MapCrossingIO.parse_list`; rows `MapDocumentIO.row_ok`
  accepts, in their own cell, that cell on the map, at most 200k an op; palette biome, surface
  and asset ids (tables cached per palette, `palette_ids`). A fresh op is built from the
  checked values. Malformed bytes and over-inflating ZSTD are refused but print an engine
  error first, so a client's `LiveEdits` stops taking ops after the first refusal (the map is
  out of step from there; `problem` says why) and only the host sends.
- **Order and frame cost:** `apply(op, editor)` finishes whatever height work an earlier op
  left first (a props op must see the rocks a sculpt kept; a later op's regeneration must not
  be snapped twice), so order holds whoever calls it. A `height` or `water` op passes `spread`:
  its heights go into the document and the queue and the call returns (about 1 ms); the
  editor's `step_height_work()` drains the chunks and the snap within the budgets above, the
  collision on a frame of its own, then the rest on the next (`HeightEditor.after_work`:
  props, kept rocks, the settle, the wet dressing, the regeneration). `LiveEditCodec.Queue` is
  the peer's driver: `push(bytes)` as payloads arrive, `step()` once a frame, which steps the
  height work and applies the next op only on a frame that began with none, at most one a
  frame. Worst frames measured headless on the probe's 200 ft map (indicative, a shared
  machine): sculpt raise 49 to 16-23 ms (the apply 0.9 ms; what remains is the water
  surface's swap after the wet dressing refresh, 13-15 ms, that every sculpt on a map with
  water pays in authoring too), sculpt lower 27 to 13, crater 19 to 7, river erase 66 to 8
  (the skirt build moved to the water's worker, [water.md](water.md) "Past the map edge");
  paint, clear, bridge and pond ops 7-12 ms as before.
- **Identity** (`test_live_map_edits.gd`): nine ops on a saved 200 ft level reach a peer, and
  a reload of the host's saved document, with every `MapFingerprint` key equal (rows exactly:
  generated rows snap to the saved precision) and the documents equal. Hostile payloads, the
  undo side, chunks and pacing: `test_live_edit_codec.gd`. The table's service (a forest
  clear, a sculpt, a bridge removal and its undo reaching a client and a late joiner; dropped
  repeats, gaps and foreign tables): `test_live_edits_table.gd`. Terrain events: the wire form
  and its bounds and the RPC's checks `test_terrain_event.gd`; a collapse and a fall on a GM
  and a client copy, the labelled entry, the undo and a late joiner `test_terrain_events.gd`;
  the presets in the pane and the click minimum `test_play_events.gd`. Over ENet with three
  processes: `tests/net/enet_live_edits` ([../NETWORKING.md](../NETWORKING.md) "ENet
  scenarios").

## Verification

Unit tests in `tests/unit/`: `test_authoring_open.gd`, `test_authoring_session.gd`,
`test_authoring_save.gd`, `test_authoring_history_cap.gd`, `test_authoring_editor.gd`,
`test_authoring_sculpt.gd`, `test_brush_tool_input.gd`, `test_mask_brush.gd`,
`test_mask_stroke.gd`, `test_prop_rows.gd`, `test_new_map.gd`, `test_new_map_build.gd`,
`test_live_edit_codec.gd`, `test_live_edits_table.gd`, `test_live_map_edits.gd`,
`test_tool_registry.gd` (every
registered tool on the rail, with a pane and in help; unique ids, shortcuts and brush modes).
`test_brush_tool_input.gd` also checks that the brush runs each registered tool's own mode
and keeps it across switches. The render job `tool_panes` captures the rail, each tool's pane
and the help rows. The 2026-10-10 split was checked with a before and after run of a cursor
job (every tool's cursor, Ctrl variants, a held river and a held bridge line on a bare
100 ft map; 16 full-size captures): no pixel moved by more than 8 levels outside two stray
3D pixels that also differ in the raw SubViewport captures.

## Open work

See [../MAP_AUTHORING.md](../MAP_AUTHORING.md) "Open work".

## History

- 2026-10-09: map and rules moved here from `AGENTS.md` Key Conventions.
- 2026-10-09: `HeightEditor` split out of `AuthoringEditor`; live edits (`LiveEditCodec`,
  public apply entry points, spread height work, the peer's queue).
- 2026-10-09: live edits transport: `AuthoringHistory` signals, undo as the before side, the
  table's `LiveEdits` service, chunked and paced over `NetworkGameSync` with a catch-up log
  for late joiners; play keeps a document's props apart (`keep_props_apart`).
- 2026-10-09: the tool registry (`ToolRegistry`, one `ToolDescriptor` per tool); the panel's
  `RAIL_ITEMS` and the controller's per-tool select and mode tables are gone.
- 2026-10-10: brush modes: `BrushTool` (980 lines) split into a host (about 500), the
  cursor (`BrushCursor`) and one `BrushMode` per tool, named by its descriptor's
  `brush_mode`; the `BrushTool.Mode` enum, `ToolRegistry.for_mode` and the three
  per-tool refusal signals are gone (one `refused`).
