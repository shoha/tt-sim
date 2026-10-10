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
| `scenes/states/authoring/brush_tool.gd` | `BrushTool` | Gestures and the ring cursor; `decide()`, `Mode`, `sculpt_op()` |
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

- `BrushTool` (created by `GameMap.setup_brush_tool()`) owns gestures and the ring cursor; its
  input table is the pure `BrushTool.decide()`.
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
- The Paint tool is `BrushTool.Mode.PAINT`:
  `AuthoringEditor.begin_surface_stroke(surface, erase)` runs a `SurfaceStroke` (the
  MaskStroke pattern on `MapDocument.surface_weights`: slot claim through `ensure_surface()`,
  trailing empty slots trimmed at stroke end, per-block diffs), blits the ground per frame,
  and regenerates scatter at stroke end only for built or cliff-role surfaces.
- The Sculpt tool is `BrushTool.Mode.SCULPT`: the press's operation is the pure
  `BrushTool.sculpt_op(tile, ctrl, shift)`; Tier's target is `AuthoringEditor.tier_target()`
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
  tool from it; `AuthoringController._select_tool` and `_on_brush_toggled` go through it;
  the F1 help overlay puts each tool's rows between the shared Map building rows.
- A descriptor declares the id, label (rail tooltip and pane title), summary (pane caption
  and help row), rail icon, an optional shortcut (a bare `Key`; none of the seven has one,
  so a key is still free to give), its `BrushTool.Mode`, its own help rows, an unavailable
  tooltip, and its contexts (`ToolDescriptor.AUTHORING`, `PLAY`; every query takes one, and
  play lists no tool yet).
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
- A new tool with gestures of its own still adds a `BrushTool.Mode` and its dispatch in
  `brush_tool.gd` (with a mode object like `WaterBrush` or `BridgeBrush`), and that file is at
  980 lines: its cursor drawing (`_on_draw` onward) is the `BrushCursor` seam to take first.

## Live edits

The GM's terrain events during play (a bridge collapsing, a forest falling, fire, biome and
terrain changes with the authoring brushes; user decision, 2026-10-09) replicate as one side
of authoring history entries. The codec, the apply side and the transport exist
(2026-10-09); the GM's UI (an Events pane) does not yet. Probe and numbers:
`docs/plans/2026-10-09-v0.2-evaluation/probes/live_edits_probe.md` (gitignored). Transport:
[../NETWORKING.md](../NETWORKING.md) "Live map edits".

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
  repeats, gaps and foreign tables): `test_live_edits_table.gd`. Over ENet with three
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
The render job `tool_panes` captures the rail, each tool's pane and the help rows.

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
