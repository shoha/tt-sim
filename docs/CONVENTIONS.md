# Code Conventions & Gotchas

This document covers coding patterns, conventions, and non-obvious gotchas that aren't covered by the other docs. It supplements [ARCHITECTURE.md](ARCHITECTURE.md) and the `.cursor/rules/` files.

## Table of Contents

- [RPC Patterns](#rpc-patterns)
- [Signal Disconnection](#signal-disconnection)
- [Token Scene Structure & Factory Requirement](#token-scene-structure--factory-requirement)
- [Token Transform Hierarchy](#token-transform-hierarchy)
- [Placeholder Token Upgrade Flow](#placeholder-token-upgrade-flow)
- [Token Highlight (SelectionGlowRenderer)](#token-highlight-selectionglowrenderer)
- [Camera System](#camera-system)
- [Drag and Drop Integration](#drag-and-drop-integration)
- [Settings Persistence](#settings-persistence)
- [RootNetworkHandler vs NetworkManager](#rootnetworkhandler-vs-networkmanager)
- [Level Folder Format](#level-folder-format)

---

## RPC Patterns

RPCs live on `NetworkManager` and `AssetStreamer`. Follow these conventions when adding new RPCs.

### Naming

All RPC methods are private and prefixed with `_rpc_`:

```gdscript
@rpc("authority", "call_remote", "reliable")
func _rpc_send_level_data(level_dict: Dictionary) -> void:
    level_data_received.emit(level_dict)
```

### Authority & Reliability

| Direction | Annotation | Use Case |
|-----------|------------|----------|
| Host → Client | `@rpc("authority", "call_remote", "reliable")` | State updates, level data, game state |
| Host → Client | `@rpc("authority", "call_remote", "unreliable")` | Transform updates (rate-limited) |
| Client → Host | `@rpc("any_peer", "call_remote", "reliable")` | Client requests, P2P asset requests |

### Vector3 Serialization in RPCs

**Godot RPCs do not serialize `Vector3` directly.** Convert to `Array` for transport:

```gdscript
# Sending (client)
_rpc_client_token_transform.rpc_id(1, network_id, [pos.x, pos.y, pos.z], rot_arr, scale_arr)

# Receiving (host)
@rpc("any_peer", "call_remote", "unreliable")
func _rpc_client_token_transform(net_id: String, pos_arr: Array, rot_arr: Array, scale_arr: Array) -> void:
    var pos := Vector3(pos_arr[0], pos_arr[1], pos_arr[2])
    client_token_transform_received.emit(sender_id, net_id, pos, rot, scale)
```

This applies to `Vector3`, `Color`, and other engine types. Use `Array` or `Dictionary` for RPC arguments. A high-rate or bulk message goes as one `PackedByteArray` argument instead (SceneMultiplayer copies it raw): the host's token transforms are `TokenTransformPack` messages, half the bytes of the Array form.

### Signal Emission Pattern

RPC methods should emit signals rather than performing logic directly. This keeps the RPC layer thin and testable:

```gdscript
# RPC method (thin - just emit)
@rpc("authority", "call_remote", "reliable")
func _rpc_receive_token_state(net_id: String, token_dict: Dictionary) -> void:
    token_state_received.emit(net_id, token_dict)

# Caller (sends)
func broadcast_token_properties(token: BoardToken) -> void:
    var state = TokenState.from_board_token(token)
    _rpc_receive_token_state.rpc(state.network_id, state.to_dict())
```

---

## Signal Disconnection

### Rule: Disconnect Autoload Signals in `_exit_tree()`

Non-autoload nodes that connect to autoload signals **must** disconnect in `_exit_tree()` to prevent callbacks on freed nodes:

```gdscript
func _ready() -> void:
    NetworkManager.player_joined.connect(_on_player_joined)

func _exit_tree() -> void:
    if NetworkManager.player_joined.is_connected(_on_player_joined):
        NetworkManager.player_joined.disconnect(_on_player_joined)
```

### Always Guard with `is_connected()`

Check before disconnecting to avoid errors if the signal was never connected or already disconnected:

```gdscript
# Good
if SomeAutoload.some_signal.is_connected(_handler):
    SomeAutoload.some_signal.disconnect(_handler)

# Bad - will error if not connected
SomeAutoload.some_signal.disconnect(_handler)
```

### Animated Panel Variant

For panels that use `animate_out()` before `queue_free()`, disconnect in `_on_before_animate_out()` instead of `_exit_tree()`:

```gdscript
func _on_before_animate_out() -> void:
    UIManager.unregister_overlay($ColorRect as Control)
    if AssetManager.packs_loaded.is_connected(_on_packs_loaded):
        AssetManager.packs_loaded.disconnect(_on_packs_loaded)
```

### State-Based Variant

For nodes that persist across states (like `Root`), disconnect when exiting the relevant state rather than in `_exit_tree()`:

```gdscript
func _exit_playing_state() -> void:
    # Disconnect signals that were connected in _enter_playing_state()
    if NetworkManager.game_sync.transform_batch_received.is_connected(_on_transform_batch):
        NetworkManager.game_sync.transform_batch_received.disconnect(_on_transform_batch)
```

`RootNetworkHandler` provides static helpers `connect_client_signals()` / `disconnect_client_signals()` for this pattern.

---

## Token Scene Structure & Factory Requirement

### Factory Requirement

**`BoardToken` instances must be created via `BoardTokenFactory`.** The factory sets up the full scene hierarchy, collision, selection glow, drop indicator, and marks the token as `_factory_created`. `BoardToken._enter_tree()` checks this flag.

```gdscript
# Correct
var token = await BoardTokenFactory.create_from_asset_async(pack_id, asset_id, variant_id)

# Wrong - will fail
var token = BoardToken.new()
```

### Scene Hierarchy

```
BoardToken (Node3D)
├── DraggableToken (Draggable3D)
│   ├── RigidBody3D
│   │   ├── CollisionShape3D
│   │   ├── SelectionGlowRenderer (QuadMesh with selection_glow.gdshader)
│   │   └── Model (Armature/Skeleton3D/Mesh — or PlaceholderToken while loading)
│   └── DropIndicatorRenderer (ImmediateMesh — child of DraggableToken, not RigidBody3D)
└── BoardTokenController (handles input, context menu, rotation, scaling)
```

### Key Signals

| Signal | Source | When |
|--------|--------|------|
| `transform_changed` | `BoardToken` | Single discrete change (drop, rotate, scale complete) |
| `transform_updated` | `BoardToken` | Continuous updates during drag/rotate/scale (throttled by `Constants.NETWORK_TRANSFORM_UPDATE_INTERVAL`) |
| `health_changed` | `BoardToken` | Health or max_health changed (carries old value for animations) |

---

## Token Transform Hierarchy

The token uses a nested transform chain that requires careful synchronization.

### The Problem

`RigidBody3D` is nested under `DraggableToken` under `BoardToken`. During drag, only the `RigidBody3D` moves. After drop, the hierarchy must be re-synchronized.

### Sync Mechanism

`DraggableToken._sync_parent_position()` runs after every drag/drop:

1. Copies `rigid_body.global_position` and `global_rotation` up to `BoardToken`
2. Resets `DraggableToken` and `RigidBody3D` local transforms to origin

This means **after sync, `BoardToken.global_position` is the canonical position.**

### Reading Position

```gdscript
# After sync (normal gameplay) — use BoardToken
var pos = token.global_position

# During drag (before sync) — use RigidBody3D
var rb = token.get_rigid_body()
var pos = rb.global_position

# For occlusion fade — use CollisionShape3D AABB center
# (not BoardToken position, which is at the feet)
```

### Setting Position

```gdscript
# Host or initial placement — immediate
token.set_transform_immediate(position, rotation, scale)

# Client receiving network update — interpolated
token.set_interpolation_target(position, rotation, scale)
```

Both methods delegate to `DraggableToken`, which handles the nested hierarchy correctly.

---

## Placeholder Token Upgrade Flow

When a model isn't cached in memory, tokens start as placeholders (pulsing cubes) and upgrade in-place when the model loads.

### Flow

```
1. BoardTokenFactory.create_from_asset_async()
   ├── Model in memory cache? → Real token returned instantly
   ├── Model on disk (not cached)? → Placeholder returned
   │   └── tree_entered → _async_upgrade_placeholder(path)
   └── Model needs download? → Placeholder returned
       └── AssetManager.asset_available → _async_upgrade_placeholder(path)

2. BoardToken._async_upgrade_placeholder(path)
   ├── await AssetManager.get_model_instance_from_path(path)  (background thread)
   ├── Guard: is_instance_valid(self) && is_inside_tree()
   ├── await get_tree().process_frame  (one frame yield)
   └── BoardTokenFactory.apply_model_upgrade(self, model)

3. BoardTokenFactory.apply_model_upgrade()
   ├── Remove PlaceholderToken child from RigidBody3D
   ├── Add real model as child
   ├── Update collision shape
   ├── Preserve floor Y position (prevent sinking/floating)
   ├── Update SelectionGlowRenderer size
   └── Set meta("is_placeholder", false)
```

### Gotchas

- The `BoardToken` instance **stays the same** — it's upgraded in-place, not replaced.
- `_pending_tokens` in the factory tracks tokens waiting for downloads; cleaned up via `tree_exiting`.
- After every `await`, always re-check `is_instance_valid(self)` — the token may have been freed during the async operation.
- Floor Y preservation prevents tokens from sinking into or floating above the map after model swap (different collision shapes have different heights).

---

## Token Highlight (SelectionGlowRenderer)

`scenes/board_token/selection_glow_renderer.gd`, driven through `BoardToken.add_highlight()`, `set_highlight_color()` and `set_highlighted()`.

- `show_glow()` only tweens alpha. RGB is whatever colour was last set, so a stale tint survives until something resets it.
- On un-highlight call **both** `set_highlight_color(SelectionGlowRenderer.DEFAULT_GLOW_COLOR)` and `set_highlighted(false)`. Skipping the colour reset leaves the previous tint on the next hover.
- `set_highlighted()` early-returns when the state is unchanged, so set the colour **before** calling `set_highlighted(true)` when changing colours.
- `DEFAULT_GLOW_COLOR` is gold `Color(1.0, 0.8, 0.2, 0.6)`; the measure tool's AoE highlight is orange `AOE_HIGHLIGHT_COLOR` in `measure_tool.gd`.

---

## Camera System

Camera control lives in `CameraController` (`scenes/states/playing/camera_controller.gd`), a child the `game_map.gd` scene drives.

### View modes (the seam)

`CameraController` is a thin owner: the single `Camera3D` and `CameraHolder`, the yaw and pitch state (`CameraView`), camera shake, the compass, the Home / turn / top-down keys, the tool wiring for `rmb_can_start_pan`, and one active `ViewMode` (`scenes/states/playing/view_mode.gd`, an interface of hooks with harmless defaults: `activate`, `deactivate`, `process(delta)`, `handle_input(event) -> bool`, pan, zoom, `apply_pitch`, `view_center_offset`, `update_camera_offset`, `ground_top_changed`, `reset_home`, bounds, `is_at_rest`, `mode_name`, `fov_deg`). `OrbitView` (`orbit_view.gd`) is the shipped mode and holds everything orthographic: pan by screen delta, zoom as `size` toward the cursor, the pan bounds on the ground-level view centre, `update_camera_offset` and the near-plane hold, WASD and edge pan. A second mode (the eye) extends `ViewMode` and is swapped in with `CameraController.set_view_mode(mode)`; the old mode is deactivated first (held keys, velocity, pans and glides stop, an Alt + drag orbit ends). `CameraController.view_mode()` is the active one; `game_state`'s camera block reports `view_mode`, `yaw`, `pitch` and `fov` (0 for orthographic), and the render-job `view` op sets yaw, pitch and zoom through the public API. `CameraRig.metres_per_pixel(camera, viewport_px, distance)` and `CameraRig.screen_of(camera, point)` (null behind the eye) are the projection-independent helpers the overlays will move to; `Camera3D.size` is stale under a perspective camera, so new code should not read it. Tests and probes still reach the orbit state through the controller's underscore names (`_target_zoom`, `_get_view_center_ground_offset`, ...), which forward to `OrbitView`.

### Orientation (Read Before Placing Anything "Toward the Camera")

The camera stands at +x, +z of what it looks at and looks along (-1, -1) in map XZ: a 45 degree yaw, pitched down 21.6 degrees, orthographic. "Toward the camera" is therefore the +x+z diagonal, not +z. Anything placed to face the camera or to stay clear of it (a landform's stage, a bluff, a lake's corner) uses `StartingLandform.VIEW` / `NEAR`; the phase 5 recipes assumed -z and put a hill's stage on its side until the judgment set caught it (`docs/systems/landforms.md`, Model). At 21.6 degrees a 6 m canopy hides about 15 m of ground behind it.

### Controls

| Input | Action | Implementation |
|-------|--------|----------------|
| Scroll wheel | Zoom | `camera_node.size` (orthographic), interpolated toward `_target_zoom` |
| WASD | Pan (isometric) | `cameraholder_node.translate()` with isometric direction mapping |
| Edge of screen | Pan (during drag) | Reads `drag_and_drop_node.edge_pan_direction` |
| Mouse near edge | Pan (idle) | `_handle_edge_panning()` with configurable margin |
| Q / E | Turn the view a quarter (no brush out) | `CameraRig.event_turn`, `CameraController.turn_view` |
| Alt+Q / Alt+E | Turn the view while an authoring brush is out (Q / E turn the brush; `[` `]` stay the brush size and never turn the view: owner verdict CR2, 2026-11-02) | same |
| Compass buttons (top right) | Turn the view, always | `CameraCompass` |
| Home | Reset position, zoom, turn and tilt (the turn and tilt first, then the glide) | `_reset_camera_to_home`, `CameraView.go_home` |
| Alt + left drag | Tilt (vertical drag, pitch 21.6 to 90) and orbit (horizontal drag, free yaw) | `CameraRig.orbit_action`, `CameraView.handle_orbit_input`, called first in `GameMap._input` |
| O | Top-down toggle: 0.5 s eased to pitch 90, a second press returns to the pitch it left | `CameraRig.is_top_down_key`, `CameraPitch.toggle_top_down` |
| Compass tilt row (top right) | Flatter and steeper arrows (15 degrees) and an elevation gauge that is the top-down button | `CameraCompass` |
| V (card eyeglide, owner verdict SL1, 2026-11-03) | Step down to the street (the eye view) and back up, with the 1.3 s glide; a second key press only lands a glide in flight | `CameraRig.is_street_key`, `CameraView.toggle_street` |
| Flatter tilt at home (compass arrow, or an Alt + drag pulled 8 degrees below home) | The same step down to the street; at the eye the steepest look down (the steeper arrow at 60) climbs back up | `CameraView.tilt_by`, `orbit_by`, `CameraRig.STREET_PULL_DEG` |
| F9 (debug key, card eyeview, 2026-11-02) | The same toggle as V (works in authoring too, which V and the tilt refuse); the hint bar swaps to the street row like any entry to the eye | `CameraController._unhandled_key_input`, `CameraView.toggle_street` |

In the eye view (`EyeView`, `scenes/states/playing/eye_view.gd`; pure maths `utils/eye_rig.gd`, `tests/unit/test_eye_view.gd`; owner verdicts SL3 to SL6) the same keys mean: WASD walk relative to the facing at 5 m/s (Shift 10), the wheel is the lens (vertical fov 40 to 75, default 60, 3 degrees a notch), a left, middle or right drag on the ground grabs it (a ray flatter than 6 degrees below the horizon grabs nothing), a double-click on the ground glides there, Q / E / Alt + drag turn about the eye, Alt + drag vertical looks from 35 up to 60 down, Home returns to the orbit view and runs its Home. The eye is 1.6 m times the map root's scale above the ground (eased), perspective, near 0.05, far 600, `sky_custom_fov` 0, and stays 1.5 m inside the map document's extent (the orbit bounds when the map has no document). Walls and doors stop the eye (card eyecollide, `utils/eye_collider.gd`: a 0.55 m x map scale sphere (wide enough not to fit a 1.0 m recipe door, which is an open hole in the collision; a wider gate still lets it through) swept in segments of at most its radius against the terrain-layer bodies of structures, walls and crossings, the authored ground's own body excluded, sliding along what it meets; tokens, grass, scatter and tree crowns have no body). O leaves the eye (restoring the orbit pose) and then toggles top-down. A camera shake is added on top of the eye pose. The world viewport is raised to MSAA 4x while in the eye and put back on leaving (`GameMap.eye_view_antialiasing`). The consumers of `Camera3D.size` are adapted: the canopy fade (`EyeCanopy`), picking and the overlays below. Map and model of the whole eye view: [systems/eye_view.md](systems/eye_view.md).

The glide between the orbit view and the eye (card eyeglide SR3, owner verdicts SL1 and EN1, 2026-11-03: "dolly zoom with the fog dip, 1.3 s glide", then EN2: no dip; `EyeGlide` in `scenes/states/playing/eye_glide.gd`, pure maths `utils/eye_glide_rig.gd`, `tests/unit/test_eye_glide.gd`, probe `tools/render_jobs/probes/eye_glide.gd`): `CameraView.enter_street()` / `leave_street()` / `toggle_street()` (V, F9, the tilt past home) hold the last orbit frame as a veil, switch to the eye mode the frame after and `EyeView` then runs the glide from its `process`; the eye mode (and so EyeSky) stays active for the whole glide in both directions, and going out the orbit view takes over on the last frame (`EyeView.deactivate` restores its pose exactly, so a skipped or finished glide ends at the exact target pose). It is a dolly zoom: a perspective camera on the home view's axis `V / (2 tan 1 degree)` back (974 m on the hamlet, 745 m on the wild map) with a 2 degree field of view, which draws the home picture, dropping onto the eye with `d(q) = (d0 + 3) e^(-lam q) - 3` and `fov = min(lens, 2 atan(V / 2d))` (the pivot plane keeps its size; V is the orthographic view height) while the pitch and height blend onto the eye's over q 0.45..1, `q` the smoothstep of the time. Companions, all per frame: near 0.05 throughout, far `max(600, d + 300)`, `EyeSky.fog_offset = d` (the fog, which `StreetSkyLook.fog_range` scales to the map with 25 and 85 m as its floors, is measured from the camera, so without it the screen is flat fog), and the sun's shadow distance, which `MapViewFit.follow` already fits to the camera as it stands (1279 m at the start, 100 m below d 43). There is no fog dip in the middle (owner verdict EN2, 2026-11-03: "remove the fog in the zoom"): the straight path on the home axis passes through whatever stands between the home camera and the pivot (roofs, walls, tree crowns), as the probe measured. The two ends are dissolves of a frozen frame (a window read-back, `EyeGlide.freeze_veil`, 0.25 s; the switch waits one frame so the veil has been drawn, measured: made in the switch frame it came up a frame late, a one-frame flicker): the orbit's grey skirt haze and the eye's foot-coloured fog differ in one frame otherwise (first glide frame change 15.7 against 0.2; before the veil the probe measured 10.9 then 5.9), and the same at the end of the climb. A frame that stalls (the sky shader's first compile costs about 80 ms) advances the glide by at most 0.05 s. Any key, pan press, wheel notch, compass button or Alt + drag ends the glide at its target pose before it acts (`EyeView.skip_view_glide`, `cancel_glide`); `EyeGlide.allowed()` is false (the change is instant, as before) when `EyeGlide.enabled` is off or the operating system asks for reduced motion (`UiMotion.reduced`). A "Smooth view change" Settings checkbox is not built yet (it needs a scene row, `settings_menu.gd` wiring and the save/reset paths; `EyeGlide.enabled` is the switch it would set). Authoring never glides (`leave_eye` is instant).

Play tools at the eye (card eyepick, `utils/view_ground.gd` `ViewGround`, `tests/unit/test_view_ground.gd`, `test_eye_pick.gd`): the drag target under a perspective camera is the first ground the cursor ray meets on the map's height field (`DragController.ground_height`, set by `GameMap.set_grid_ground`; never a wall or roof), a ray flatter than 6 degrees below the horizon names no ground and the token stays; "the view centre on the ground" (new token and party landing, the sun ring, the grid's fade centre) is the point `ViewGround.AHEAD_M` (5 m) ahead of the eye (`eye_point`); the weather box is 20 m around the eye (`WeatherRenderer.emission_half_extent`); overlay lines use `CameraRig.screen_segment` / `screen_runs` / `screen_of` so nothing behind the eye is drawn (measure, ruler, sun ring, volume label, token pins); dirty checks compare `CameraRig.view_key` (pose, projection, size, fov). Entering authoring (`GameMap.setup_authoring`) calls `CameraController.leave_eye()`. The orbit view is unchanged on every one of these paths (`camera_trace` 0 diff). Authoring brushes and the token ghost were not swept.

The hint bar chip (`Q E` or `Alt + Q E`, `CameraRig.turn_hint`) and the compass tooltip name the mapping that is live.

The hint bar follows the view (card eyehints, owner board EL1, 2026-11-03): `EyeView.activate` calls `UIManager.set_street_hints(true)` and `deactivate` calls it with false, which swaps the play base hints between the orbit row and the street row (`CameraRig.play_hints(street)`: Esc Pause, WASD Walk, Shift + WASD Run, Scroll Lens, Q E Turn view, F9 or V Leave, M Measure, F1 Help; no Home, no grid, no Alt + drag). The run chip is `Shift + WASD`, not `Shift`, because a token drag lays a `Shift` free-move hint on that key and removes it after. The view is remembered in `InputHints` (`set_street`, `is_street`), so the controls-profile change and the next map's default hints come out right, and an empty bar (not playing) stays empty. `GameplayMenuController._exit_tree` resets it.

### View yaw (turning the view)

The view turns in 90 degree snaps: 45 (home), 135, 225, 315, as the camera's compass azimuth. `CameraController` eases the CameraHolder's yaw over about 0.35 s (`CameraYaw`, `CameraRig.TURN_SECONDS`) about the ground point under the screen centre, so the stage stays in frame, and applies it inside `_process` before it publishes `canopy_fade_view` (the foliage shaders' camera-pass test reads it; the 2 m `shadow_caster_push` now keys off the engine's `IN_SHADOW_PASS` instead, so no turn speed can sink the crowns). The holder carries the yaw, so its local pan axes follow it: W is always away from the viewer. W/S speed uses the live elevation (`CameraRig.vertical_pan_factor`), so it matches A/D on screen. The sun stays fixed in the world; the view is local to each player (not synced). A landed turn emits `view_turned`, which `MapViewFit` answers with a refit of the zoom limit and pan bounds for the new basis. The maths is in `utils/camera_rig.gd` (pure, tested in `tests/unit/test_camera_rig.gd`); a render-job probe (`tools/render_jobs/probes/camera_rig.gd`, jobs `camera_rig_*`) shoots stills and a fixed-rate clip of a snap.

### View pitch (tilt and top-down)

The pitch is the camera's elevation: 21.6 degrees is home, 90 is straight down, and nothing flatter than home is allowed (the owner has not judged flatter; street level is a later stage). `CameraView` (`scenes/states/playing/camera_view.gd`) owns the yaw and pitch state (`CameraYaw`, `CameraPitch`) and keeps the ground point under the screen centre fixed through every change: a pitch change swings the Camera3D child's basis, built from an explicit horizontal right axis so 90 has no gimbal (`CameraRig.camera_basis`), and its offset about that axis (`pitched_offset`), then moves the holder by whatever the pivot slipped. At home pitch the camera takes the scene's own basis and offset exactly. Orthographic, so the picture depends on the basis and pivot only; `_update_camera_offset` keeps the near plane above the ground and canopies at every pitch (`near_plane_hold` uses the live back axis, tested at 21.6 to 90), and `view_tilted` (every frame of a tilt) makes `MapViewFit` refit the zoom limit (a square map seen from above needs a wider view) and the pan bounds for the live basis.

An Alt + left drag is decided by `CameraRig.orbit_action` before every tool in `GameMap._input`, so a token drag, a brush stroke or a selection never starts under it; it does not begin over the UI or while a token, brush or tool drag owns the mouse. Dragging down raises the camera 0.2 degrees a pixel, dragging sideways turns it 0.3 degrees a pixel (picture dragged right turns the camera left); the move is direct (no inertia). Q / E and the compass snap from the free yaw to the next 45 + 90k. Edge pan (a token dragged to the screen edge) pauses while Alt is held or an orbit runs. Pan speed follows the live pitch: W's ground factor is 1 / sin(pitch) (`vertical_pan_factor`), so W and A cover the same screen distance at every pitch; the keyboard and the edge pan share it (`tests/unit/test_camera_pitch.gd` drives both at 21.6, 35, 50, 70 and 90).

Above about 55 degrees of pitch (full from 70, `CameraRig.marker_strength`) every token gets a map pin (`TokenMarkers`, `shaders/token_marker.gdshader`): a round head, `HEAD_PX` (44) px across whatever the zoom (the world viewport's own pixels, which under the canvas_items stretch are the UI's, so it scales with the window as the UI does), showing the token's own picture, with a short tail whose tip stands on the token's top edge as the camera sees it (`top_edge_metres`: footprint edge from above, the head of a standing figure from the side), so the token is never covered. One MultiMesh quad per token turned to face the camera, drawn on top without a depth test, lower-on-screen pins over higher ones: one draw call for any token count. The pictures live in one atlas texture (`TokenPortraits`, 16 x 16 cells of 64 px) so the pins share one material; a picture is made once per token identity and kept: an avatar's is `AvatarThumbnails`' picture of its recipe, a pack token's is the pack's icon (`AssetManager.resolver.resolve_icon_sync`), any other model is drawn once from its own meshes in a private SubViewport lit like the roster icons (`tools/roster/render_icons.gd`); each is cropped to head and chest when the figure is tall (`portrait_rect`). Jobs run one a frame from a queue; until a picture is ready, or when it cannot be made (headless, atlas full), the pin shows a disc in the token's vivid colour (palette texture, material or vertex colours, `TokenMarkers.vivid`), which is also the pin's tail and the picture's backdrop. A token hidden from players gets no pin for a player and a dimmed one for the GM (`TokenMarkers.pin_alpha`). It does no work below the threshold (the atlas is not even made). A pin is a target once the fade has brought it to `HIT_MIN_STRENGTH` (0.5), tested in screen space against its head circle (`pick_pin`): the pin under the pointer draws in front of the others (moved last in the same MultiMesh, so still one draw call), a tenth larger with a whiter rim, and where heads overlap the pointer the nearest centre wins; a left press on a pin calls `Draggable3D.press_at` on that token's `DraggableToken`, the entry a press on its body takes (same permission and R-key rules), and is consumed only when that press armed a drag. A token hidden from a player has no pin, so no hover or click. Hover and clicks are off while the pointer is over interface, outside the window or a token is held. A token's footprint is its collision shape's box: an avatar's capsule, a pack token's hull of its meshes (`TokenShape`, the same box as the model's own bounds; the mesh bounds stand only for a token with no shape).

A pack token's collision shape (`scenes/board_token/token_shape.gd`) is the convex hull of every visible mesh's vertices, in the rigid body's space and baked into the shape's points, so the shape node sits at the origin and each reader of a token's size, base and top (grounding, drop indicator, water depth, glow, occlusion fade, the pin) sees the model's own size. A skinned mesh is taken as its skeleton poses it (each vertex follows its main bone; a sheep's vertex data lies on its side), and an authored `-convcolonly` shape is moved into the same space. The shape used to come from the mesh resource alone (`Mesh.create_convex_shape`, raw units) while the model's root carries the scale (a horse's 0.435, a pig's 0.197 under an armature of 100), so a horse's was 2.3 times its model and a pig's a speck (measured 2026-11-02, fixed in the `collshapes` card). The same card fixed `DraggableToken.set_lean`: the lean reset set a model root's whole basis to the identity, which dropped that scale, so a pack animal stood at its raw size (a pig five times as big) after any placement, network update or drag. `tests/unit/test_token_shape.gd` checks every built-in beast and folk model against its bounds.

### Isometric Direction Mapping

Camera movement directions at the home yaw (45) are rotated 45 degrees for isometric view; the holder's local axes turn with the yaw, so these are the directions in the holder's frame:

```
Forward (W) = (-1, 0, -1)  (up-left on screen)
Backward (S) = (+1, 0, +1) (down-right on screen)
Left (A) = (-1, 0, +1)     (down-left on screen)
Right (D) = (+1, 0, -1)    (up-right on screen)
```

### Zoom

- Uses orthographic projection; zoom changes `camera_node.size`
- Zooms toward the cursor position (not screen center)
- Zoom is disabled while dragging (scroll controls token height during drag)
- Zoom is disabled when mouse is over GUI panels

### Camera Offset Scaling (Near-Plane Culling Prevention)

The Camera3D sits at a local offset from CameraHolder. At large `camera.size` values (zoom out or aspect correction on narrow windows), the bottom screen edge's ray origin can drop below Y=0 — meaning ground geometry is behind the near plane and gets culled.

**Fix**: `_update_camera_offset()` scales the Camera3D local position proportionally with `camera.size`. For an orthographic camera, translating along the view direction has zero visual effect but moves the near plane further from the ground, preventing culling. Called after every `camera.size` change (`_ready`, `handle_zoom`, `_on_viewport_size_changed`).

- `_base_camera_offset` and `_base_camera_size` are captured in `_ready()` before any modification.
- In `handle_zoom()` the offset update must run **after** the zoom-toward-cursor correction, because `world_before` and `world_after` have to be computed from the same camera position.
- `project_position(corner, 0)` returns near-plane coordinates (on the held near plane, tens of metres up and behind the camera), not ground level. For any ground-footprint calculation use `project_ray_origin` + `project_ray_normal` and intersect with Y = 0.
- Side effect worth knowing: because the camera distance scales with `camera.size`, anything centred on the camera (SDFGI cascades, for example) re-centres on zoom. See `docs/lighting-and-environment.md` "SDFGI banding under the orthographic camera".
- **Moving the camera back is not free.** The picture is unchanged, but the sun's shadow distance and cascade splits and the presets' exponential fog are measured from the camera: 50 m back made the top of the home frame up to 11 levels brighter. To clear something in front of the camera, move the near plane, not the camera.
- **The near plane is negative by design.** `_hold_near_plane_over_canopies` pulls `near` back behind the camera (about -61 m at home, -53 at a 150 ft map's full authoring zoom-out) until the bottom corners' ray origins stand `CANOPY_CLEARANCE` (24 m) above the highest ground, so no canopy is sliced or culled at any zoom (Polish, 2026-10-05; `PERFORMANCE.md` "Close-zoom canopy fade"). Consequence: `project_ray_origin` starts behind the camera, so a ray cast from it needs a long reach (the token-hover and measure rays use 1000 m), and the top of the frame at zoom 20 is about 116 m from its origin.

### Camera Bounds

The camera is soft-clamped to the loaded map's geometry AABB to prevent panning too far from the map. Void/padding around the map is expected and desired.

- **View-center clamping**: Bounds constrain the **ground-level view center** (the screen center projected to Y=0 via ray intersection), not the camera holder position. This is necessary because the isometric camera is at a large local offset from the holder (~11 units in X and Z), so clamping the holder directly produces asymmetric panning.
- **Margin**: `MAP_BOUNDS_MARGIN_FACTOR` (0.15) expands the AABB by 15% of the map size per side, giving breathing room around the map edges.
- **Degenerate axes**: When the map bounds collapse on an axis, the view centers on that axis.
- **Initial snap**: `_clamp_camera_to_bounds()` runs immediately after `_compute_map_bounds()` in `notify_map_loaded()` so the first user input doesn't cause a jump.
- **Key helper**: `_get_view_center_ground_offset()` computes the XZ offset from holder to ground-level view center. This offset varies with camera offset scaling but is recomputed each frame.

### Aspect Ratio Correction

`compute_aspect_corrected_size()` scales `camera_node.size` up on viewports narrower than 16:9 so the visible horizontal world extent stays constant across all aspect ratios. The correction is applied at startup and on every viewport resize via `_on_viewport_size_changed()`. `_target_zoom` always stores the reference 16:9 height; `handle_zoom()` lerps toward the corrected value.

### Input Handling Gotcha

Camera zoom uses `_input()` instead of `_unhandled_input()` because events from `SubViewportContainer` may not propagate to `_unhandled_input()`. Keyboard movement uses `_unhandled_key_input()`.

---

## Drag and Drop Integration

### The drag system

Our own code (`scenes/drag/`, `utils/drag_math.gd`, `utils/drag_state.gd`); the third-party
DragAndDrop3D addon it replaced (2026-10-31) is gone, so no outside licence is carried.

1. `Draggable3D` finds its first `CollisionObject3D` below it (its `body`)
2. On a left press on the body it calls `DragController.press()` (the controller is found
   through the `drag_controller` group)
3. `DragController` arms a `DragState`; the drag begins once the mouse has travelled
   `drag_threshold_px` (5px) from the press, and emits `dragging_started`
4. Each frame, raycasts to the ground (once per frame, from the last pointer event) and eases the
   body toward the hit point (`DragMath.eased`)
5. Left release drops it on the exact target XZ (`dragging_stopped`); right click or Escape
   cancels (`dragging_cancelled`); the mouse wheel steps the held height
6. The rules without a scene (threshold, snap and ground resolve, easing, landing, edge pan) are
   `DragMath`; the idle / pending / active machine is `DragState`; both have unit tests
   (`test_drag_math.gd`, `test_drag_state.gd`, `test_drag_controller.gd`)

### Physics Conventions

| Layer | Purpose |
|-------|---------|
| Layer 1 | Terrain/board — used by drag raycast and drop-position raycast |
| Other layers | Token collision — not included in terrain raycasts |

- Tokens use `RigidBody3D` with `gravity_scale = 0`
- Position is set directly during drag; no physics simulation
- The raycast excludes the dragged object via its `RID`
- Map `StaticBody3D` nodes have `input_ray_pickable = false` (set by `GlbUtils.disable_static_body_picking()`) so viewport picking reaches tokens behind walls

### DraggableToken Extensions

`DraggableToken` extends `Draggable3D` with:
- `dragging_allowed` gate (for permission checks)
- `height_offset` for pickup height (updated when scale or collision changes)
- Network interpolation: `set_network_target()` / `set_transform_immediate()`
- `input_ray_pickable = false` during settle animation to prevent re-picking

---

## Settings Persistence

### Architecture

Settings use a single `user://settings.cfg` (ConfigFile) but are **decentralized** — each system reads/writes its own section independently. The path is centralized in `Paths.SETTINGS_PATH`.

### Current Sections

| Section | Keys | Managed By |
|---------|------|------------|
| `audio` | `master`, `music`, `sfx`, `ui` | `SettingsMenu` |
| `graphics` | `fullscreen`, `vsync`, `lofi_enabled`, `token_shading` (0 Painted, the default, or 1 Original), `token_ghost_enabled` (default true), `occlusion_fade_enabled`, `canopy_fade_enabled` (default false), `antialiasing`, `rendering_method`, `shadow_quality`, `render_scale` (0 Auto or a percent, default 100), `idle_throttle` (default true: 15 fps unfocused, 5 minimised), `water_quality`, `ssao_enabled`, `ssr_enabled`, `sdfgi_enabled` | `SettingsMenu`, `GameMap` |
| `grid_visuals` | `cell_tint_opacity`, `line_thickness`, `fade_radius` | `SettingsMenu`, `GameMap` |
| `network` | `noray_server`, `noray_port`, `debug_logging`, `p2p_enabled` | `NetworkManager`, `SettingsMenu` |
| `player` | `name` | `NetworkManager` |
| `updates` | `check_prereleases` | `UpdateManager`, `SettingsMenu` |
| `controls` | `input_profile` | `InputProfile` |
| `ui` | `show_values`, `interface_size` | `UiPreferences` |
| `foliage` | `library` (`treecube` default, `plantgen`), `package_path` (a plantgen package folder, empty by default; dev setting, no menu row) | `FoliageLibrary`, the F3 debug panel |

### Adding New Settings

1. Choose an appropriate section (or create a new one)
2. Use `Paths.SETTINGS_PATH` for the file path (never hardcode `"user://settings.cfg"`)
3. Load with `ConfigFile.load(Paths.SETTINGS_PATH)` in `_ready()` or setup
4. **Always check the return value** of `config.load()` — if it fails with anything other than `ERR_FILE_NOT_FOUND`, warn before overwriting:
   ```gdscript
   var config = ConfigFile.new()
   var err = config.load(Paths.SETTINGS_PATH)
   if err != OK and err != ERR_FILE_NOT_FOUND:
       push_warning("Failed to load settings (err=%d), writing section only" % err)
   config.set_value("my_section", "my_key", value)
   config.save(Paths.SETTINGS_PATH)
   ```
5. Guard against missing keys with `config.get_value(section, key, default_value)`

---

## RootNetworkHandler vs NetworkManager

### Separation of Concerns

| Component | Role | Scope |
|-----------|------|-------|
| `NetworkManager` (autoload) | Connection lifecycle, RPC transport, player tracking | Always active |
| `RootNetworkHandler` (static helpers) | Client-side token state → visual mapping | Active during PLAYING state only |

### RootNetworkHandler Responsibilities

- Connect/disconnect client signals for the PLAYING state
- Handle token transform, transform batch, token state, token removed
- Apply full game state to token visuals
- Create tokens from `TokenState` via `BoardTokenFactory`

### Usage Pattern

```gdscript
# In Root._enter_playing_state()
RootNetworkHandler.connect_client_signals(self)

# In Root._exit_playing_state()
RootNetworkHandler.disconnect_client_signals(self)
```

The handler takes `LevelPlayController` and `GameMap` as arguments so it can manipulate tokens and the map without being coupled to `Root`.

---

## Level Folder Format

### On-Disk Structure

```
user://levels/
├── my_dungeon/
│   ├── level.json    # LevelData serialized as JSON
│   ├── map.glb       # Bundled Blender map (copied during save; optional if map.ttmap exists)
│   ├── map.ttmap     # Authored map document (optional if map.glb exists)
│   └── thumbnail.png  # 320x180 capture of the last in-play save (optional)
├── forest_encounter/
│   ├── level.json
│   └── map.glb
└── _autosave/
    └── level.json    # Autosave (cleared after manual save)
```

`LevelManager.levels_dir` is the root of this tree, and tests redirect it to a temp directory so no real save is touched.

### level.json Format

```json
{
  "level_name": "My Dungeon",
  "level_description": "A dark underground maze",
  "author": "DM Name",
  "created_at": 1700000000,
  "modified_at": 1700001000,
  "level_folder": "my_dungeon",
  "map_path": "map.glb",
  "map_document": "",
  "map_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
  "map_offset": {"x": 0.0, "y": 0.0, "z": 0.0},
  "light_intensity_scale": 0.005,
  "environment_preset": "dungeon_dark",
  "environment_overrides": {
    "fog_enabled": true,
    "fog_density": 0.03,
    "ambient_light_color": "#1a1a2e"
  },
  "lofi_overrides": {
    "pixelation": 2.0,
    "color_depth": 16.0
  },
  "token_placements": [
    {
      "placement_id": "1700000000_1234",
      "pack_id": "creatures",
      "asset_id": "wolf",
      "variant_id": "default",
      "position": {"x": 0.0, "y": 0.0, "z": 0.0},
      "rotation_y": 0.0,
      "scale": {"x": 1.0, "y": 1.0, "z": 1.0},
      "token_name": "Wolf",
      "is_player_controlled": false,
      "max_health": 100,
      "current_health": 100,
      "is_visible_to_players": true,
      "status_effects": [],
      "is_alive": true
    }
  ]
}
```

### Key Conventions

- `map_path` is **relative** in folder-based levels (e.g., `"map.glb"`), resolved via `LevelData.get_absolute_map_path()`
- `map_path` is **absolute** in legacy `.tres` levels (e.g., `"res://assets/models/maps/..."`)
- `map_document` is `""` or `"map.ttmap"` (the only values `from_dict()` accepts). A folder level has `map_path`, `map_document`, or both; an empty `map_path` is a map built in tt-sim
- `map_hashes` never appears in a saved `level.json`: the host adds it to the level dict it broadcasts (see NETWORKING.md "Level Map Files")
- Colors in `environment_overrides` are stored as hex strings (`"#ff0000"`)
- Autosave writes to `user://levels/_autosave/level.json` and is cleared after manual save
- Folder names are generated via `Paths.sanitize_level_name()`: lowercase, spaces to underscores, restricted charset

---

## Threading & Async Patterns

The project uses several async patterns. Mixing them up causes hangs or crashes.

### Pattern 1: WorkerThreadPool (preferred for one-off jobs)

Used by `GlbUtils` and `LevelManager` for background loading:

```gdscript
var task_id = WorkerThreadPool.add_task(func():
    # Heavy work here (runs on background thread)
    _result = _do_expensive_parsing(data)
)

# Poll until done (main thread stays responsive)
while not WorkerThreadPool.is_task_completed(task_id):
    await get_tree().process_frame

# MUST call this after completion to clean up
WorkerThreadPool.wait_for_task_completion(task_id)
```

### Pattern 2: ResourceLoader.load_threaded (for Godot resources)

Used by `LevelManager` and `AssetModelCache` for `.tres` and `.tscn` files:

```gdscript
ResourceLoader.load_threaded_request(path)

while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
    await get_tree().process_frame

var resource = ResourceLoader.load_threaded_get(path)
```

### Pattern 3: Dedicated Thread (for long-running workers)

Used by `AssetPackTab` for icon loading:

```gdscript
var _thread := Thread.new()

func _start_loading():
    _thread.start(_load_icons_worker)

func _load_icons_worker():
    for item in items:
        call_deferred("_add_item_to_list", item)  # Main thread callback
```

### Threading Gotchas

1. **Deferred callbacks on freed nodes**: If a `Thread` calls `call_deferred()` and the target node is freed before the deferred call runs, it crashes. Stop threads in `_exit_tree()` and guard deferred callbacks with `is_instance_valid(self)` at the start of every deferred method:
   ```gdscript
   func _deferred_callback(data) -> void:
       if not is_instance_valid(self):
           return
       # safe to use self here
   ```

2. **Always call `wait_for_task_completion()`**: After `WorkerThreadPool.is_task_completed()` returns true, you must call `wait_for_task_completion()` to release the task. Skipping this leaks.

3. **Mutex usage**: `AssetCacheManager` uses mutexes to protect cache dictionaries from concurrent access. New cache operations must follow the same locking pattern:
   ```gdscript
   _mutex.lock()
   var result = _cache.get(key, null)
   _mutex.unlock()
   ```

4. **Post-await validity**: After any `await`, re-check `is_instance_valid(self)` and `is_inside_tree()` before accessing node properties. The node may have been freed during the yield.

5. **Packed arrays are shared, not copied**: in Godot 4.7 GDScript, `var b := a` for a `PackedByteArray` (or any packed array), passing one to a function, or reading one out of a Dictionary or a property, gives a reference to the same buffer; a write through any of them shows in all (measured 2026-09-26). Anything handed to a worker thread, or kept as a "before" copy for undo, must be `.duplicate()`d, and an array a worker may be reading must be replaced (a new array assigned) rather than resized or appended in place. `AuthoredScatter._snapshot()` and `MaskStroke` do this; the older comment that called them copy-on-write was wrong.

6. **No background resource loads under `--headless`**: Godot 4.7.1's dummy renderer (what `--headless` runs: GUT, CI, CLI tools) keeps textures and materials in RID owners that are not thread-safe, so a texture or material created on a worker thread races every other one being created (on another worker or the main thread): "Parameter "t" is null" in `texture_2d_initialize`, "Parameter "material" is null" in `material_set_shader`, and a segfault in a stress probe (2026-09-27; the real renderers were clean). It made GUT runs flaky ("Unexpected Errors" in whichever test was loading). Any threaded load of a GLB, scene or texture (`ResourceLoader.load_threaded_request`, GLTF generation on `WorkerThreadPool`) checks `GlbUtils.threaded_loads_safe()` and loads in place when it is false. Pure data work (scatter generation, rock keeping, document parsing) stays on workers everywhere.

7. **A crash with no backtrace is off the main thread**: Godot's Windows crash handler wraps only the main thread, so a segfault on a worker (pipeline compilation, a loader thread, a driver thread) exits 139 with nothing in the log or `user://logs/`, at a different script line each run. Bisect and A/B the suspect instead of chasing the last printed line. The case that taught it (2026-10-13): `out_metallic = has_orm_texture ? orm.b : 0.0;` in `shaders/wind_foliage_include.gdshaderinc` (0fe3d41) crashed every opening of a saved authored map in authoring (the render jobs' `dress`) on Godot 4.7.2 / Vulkan, while a new map drew fine; `orm.b * float(has_orm_texture)` does not, and `test_wind_foliage_orm.gd` keeps the ternary out.

---

## Input Actions

Custom input actions defined in `project.godot`:

| Action | Binding | Used By |
|--------|---------|---------|
| `camera_move_forward` | W | `game_map.gd` — camera pan (isometric) |
| `camera_move_backward` | S | `game_map.gd` — camera pan |
| `camera_move_left` | A | `game_map.gd` — camera pan |
| `camera_move_right` | D | `game_map.gd` — camera pan |
| `camera_zoom_in` | Mouse wheel up | `game_map.gd` — orthographic zoom |
| `camera_zoom_out` | Mouse wheel down | `game_map.gd` — orthographic zoom |
| `rotate_model` | Middle mouse | `board_token_controller.gd` — token rotation (Shift = scale) |
| `camera_reset` | Home, C | `game_map.gd` — reset camera to default position |
| `select_token` | Left double-click | Defined but not currently referenced in code |

**Alternative bindings (trackpad / compact keyboard):** In addition to the primary bindings above, several actions have alternative bindings that always work regardless of profile:

| Action | Primary (Mouse) | Alternative (Trackpad) |
|--------|-----------------|------------------------|
| Camera pan | MMB drag | RMB drag on empty space |
| Token rotate | MMB drag on token | R + LMB drag |
| Token scale | Shift+MMB drag on token | Shift+R + LMB drag |
| Camera reset | Home | C (added to `camera_reset` action) |

`InputProfile` autoload manages which labels appear in the hint overlay and settings. See `autoloads/input_profile.gd`.

**Undo/Redo**: `Ctrl+Z` / `Ctrl+Y` are handled directly via `_unhandled_key_input()` in `level_editor.gd`, not through the input map.

---

## GUI-Over-3D Input Blocking

### The Problem

The 3D viewport renders inside a `SubViewportContainer`. UI panels (asset browser, drawers, menus) overlap the viewport. Without filtering, camera zoom and token interaction occur when scrolling or clicking on UI panels.

### The Solution

`game_map.gd` uses `_is_mouse_over_gui()` to block 3D input when the mouse is over UI:

```gdscript
func _is_mouse_over_gui() -> bool:
    var hovered = get_viewport().gui_get_hovered_control()
    if hovered == null:
        return false
    if hovered == _sub_viewport_container:
        return false  # The 3D viewport itself — allow 3D input
    return true       # Any other control — block 3D input
```

This is checked before processing camera zoom and edge panning.

### Implications for New UI

- New UI panels that overlap the viewport will **automatically** block 3D input if they have interactive controls (controls with `mouse_filter = STOP`)
- Pure layout containers with `mouse_filter = IGNORE` do **not** block 3D input (their children might, but the container itself doesn't)
- If a new panel should **not** block 3D input (e.g., a transparent HUD overlay), set all its controls to `mouse_filter = PASS` or `IGNORE`

### Nested clip masks draw blank

A control that clips with `clip_children` (a `LevelCard`'s or `RoomRows` map well, a
`CardThumb`) draws nothing in a real render when an ancestor is a `clip_children` mask too
(`ScrollFade` makes its ScrollContainer one). The library grid's pictures went blank twice on
2026-10-10, once with a hand-made mask and once with `ScrollFade` on the grid; headless GUT runs
pass either way, so only a render job shows it. Fade or round such content another way (a
shader on the content, a gradient drawn over it), and check a capture.

---

## Token Animation System

### Factory Requirement

Like `BoardToken`, the `BoardTokenAnimationTree` **must be created via `BoardTokenAnimationTreeFactory.create()`**. It checks `_factory_created` in `_enter_tree()`.

### Animation States

The animation tree uses an `AnimationNodeStateMachinePlayback` with these states:

| State | Trigger | Description |
|-------|---------|-------------|
| `battlewait01` | Default / health increased | Idle animation |
| `damage01` | `health_changed` when `previous > current` | Damage reaction |
| `down01` | `health_changed` when `new_health == 0` | Death/knockout |

### Scene Structure

The `AnimationTree` is added as a child of the `RigidBody3D`. Its `tree_root` node path must point to the model root (parent of `AnimationPlayer`) so bone paths resolve correctly. The factory handles this wiring.

### Update rate (TokenAnimationLod)

The tree does not process itself: on `_ready` it registers with its viewport's `TokenAnimationLod`
(`scenes/board_token/token_animation_lod.gd`), which puts it and the players it reads in the manual
callback mode and calls `advance()` with the time since the last step: every frame while the token is
highlighted (selected or hovered), dragged, or within 2 s of a health reaction (`touch`); at 30 Hz,
staggered, while it is idle and on screen; never while it is off screen (perf audit F-tokens-3,
2026-11-09: 15-20 us per token per frame before). Code that plays a clip on a token outside the state
machine must `touch` the tree, or it will step at the idle rate. `TokenAnimationLod.set_enabled(false,
tree)` hands every mixer back its own per-frame processing.

### Adding New Animations

1. Add the animation state to the `AnimationNodeStateMachine` in `board_token_animation_tree.tscn`
2. Add transition logic in `board_token_animation_tree.gd`'s `_on_health_changed()` or equivalent handler
3. Ensure the GLB model includes the animation with matching name
