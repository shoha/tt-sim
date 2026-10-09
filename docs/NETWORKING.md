# Networking Guide

This document covers the multiplayer networking system, including connection management, state synchronization, and the host-authoritative architecture.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Connection Flow](#connection-flow)
- [State Synchronization](#state-synchronization)
- [Player Roles](#player-roles)
- [Late Joiner Support](#late-joiner-support)
- [Level Map Files](#level-map-files)
- [Token Synchronization](#token-synchronization)
- [Development Setup](#development-setup)
- [API Reference](#api-reference)
- [Steam Integration](#steam-integration)

---

## Overview

The networking system uses a **host-authoritative architecture** where one player acts as the host (server) and others connect as clients. Key features:

- **Steam Networking** — connections use Steam lobbies and `SteamMultiplayerPeer` (Valve SDR relay, no server infrastructure)
- **State Synchronization** for game state and token transforms
- **Late Joiner Support** with full state catch-up
- **Rate-Limited Updates** to prevent network flooding

### Core Components

| Autoload           | Purpose                                            |
| ------------------ | -------------------------------------------------- |
| `NetworkManager`   | Connection lifecycle, player tracking, RPC routing |
| `NetworkStateSync` | State broadcasting, rate limiting, batching        |
| `GameState`        | Authoritative game state storage                   |

### Dependencies

| Component | Source |
|-----------|--------|
| GodotSteam GDExtension | `addons/godotsteam/` — provides `Steam` singleton and `SteamMultiplayerPeer` |
| `LobbyCode` | `utils/lobby_code.gd` — base-36 encode/decode for Steam lobby IDs |

---

## Architecture

### Connection States

```gdscript
enum ConnectionState {
    OFFLINE,       # Not connected
    CONNECTING,    # Creating/joining Steam lobby
    HOSTING,       # Hosting a game
    JOINED,        # Connected as client
}
```

### Signals

```gdscript
# Connection lifecycle
signal connection_state_changed(old_state, new_state)
signal room_code_received(code: String)
signal connection_failed(reason: String)
signal connection_timeout()

# Player management
signal player_joined(peer_id: int, player_info: Dictionary)
signal player_left(peer_id: int)

# Game state
signal game_starting()
signal level_data_received(level_dict: Dictionary)
signal late_joiner_connected(peer_id: int)
signal game_state_received(state_dict: Dictionary)

# Token updates (clients)
signal token_transform_received(network_id, position, rotation, scale)
signal token_state_received(network_id, token_dict)
signal token_removed_received(network_id)
signal transform_batch_received(batch: Dictionary)

# Visual settings (clients)
signal visual_settings_received(settings: Dictionary)
```

---

## Connection Flow

### Steam Initialization

Steam is initialized **lazily** on the first `host_game()` or `join_game()` call via `_ensure_steam_initialized()`. This calls `Steam.steamInitEx()` which reads the App ID from `steam_appid.txt`. If Steam is not running, a dialog prompts the user to launch Steam and quit.

`Steam.run_callbacks()` is called every frame in `_process()` once initialized.

### Hosting a Game

```gdscript
# Start hosting
NetworkManager.host_game()

# Wait for room code
NetworkManager.room_code_received.connect(func(code):
    print("Share this code: ", code)
)
```

**Internal Flow:**

1. Initialize Steam (if not already)
2. `Steam.createLobby(LOBBY_TYPE_PRIVATE, MAX_PLAYERS)`
3. On `lobby_created` callback: publish the game version as lobby data
   (`VersionGate.LOBBY_DATA_KEY`, `"tt_version"`), then create `SteamMultiplayerPeer` host
4. Encode lobby ID to base-36 room code via `LobbyCode.encode()`
5. Emit `room_code_received` — ready for client connections

### Joining a Game

Players can join via **room code** (typed in lobby UI) or **Steam invite** (overlay).

```gdscript
# Join with room code
NetworkManager.join_game("1abc2d")

# Handle success
NetworkManager.connection_state_changed.connect(func(old, new):
    if new == NetworkManager.ConnectionState.JOINED:
        print("Connected!")
)
```

**Internal Flow:**

1. Initialize Steam (if not already)
2. Decode base-36 room code to lobby ID via `LobbyCode.decode()`
3. `Steam.joinLobby(lobby_id)`
4. On `lobby_joined` callback: read the host's `"tt_version"` lobby data and stop with a
   version-mismatch `connection_failed` if it differs (see [Same-version gate](#same-version-gate));
   otherwise get host Steam ID, create `SteamMultiplayerPeer` client
5. Wait for Godot's `connected_to_server` signal
6. Exchange player info; the host re-checks the reported version before admitting the player
7. Receive level data and game state (a late joiner's sync starts only after step 6 passes)

### Same-version gate

A player can only join a game hosted on exactly the same version
(`application/config/version`, via `UpdateVersion.get_current()`); any string difference,
including a dev-build suffix, is a mismatch. The rules live in `VersionGate`
(`utils/version_gate.gd`) as pure static functions, tested in `tests/unit/test_version_gate.gd`.

| Check | Where | On mismatch |
|-------|-------|-------------|
| Lobby data (fast path) | Client, `_on_lobby_joined()`, before `create_client` | `_handle_connection_error(VersionGate.mismatch_message(...))`: leaves the lobby, never connects |
| Player info (authoritative) | Host, `_rpc_send_player_info()` via `VersionGate.is_player_info_accepted()` | Peer is not added to `_players`; host sends `_rpc_version_rejected(host_version)`, then force-disconnects the peer after `VERSION_REJECT_DISCONNECT_DELAY` (1 s) |

Clients send their version under `"version"` in `_local_player_info`. A host from before the
gate publishes no lobby version, which the client reads as `""` and reports as "an older
version"; a client from before the gate sends no version and the host rejects it.

On `_rpc_version_rejected` the client leaves on its own (deferred `_handle_connection_error`)
with the version message, before the host's delayed disconnect lands, so the player sees the
version reason and not "Host disconnected". The host defers a late joiner's
`_sync_late_joiner()` until the player info passes the gate, so a rejected client is never
pushed into `PLAYING` and the message appears on the join screen, where `LobbyClient` keeps
the `connection_failed` reason on screen through the following `OFFLINE` state change.

### Disconnecting

```gdscript
NetworkManager.disconnect_game()
```

Leaves the Steam lobby, closes the multiplayer peer, and clears all state.

### Transport Resilience

Steam SDR (Steam Datagram Relay) handles transport-level resilience including packet retransmission and route optimization. There is no application-level reconnection logic — if the connection drops entirely, the client is disconnected and must rejoin.

**Send limits (measured 2026-10-09, two peers on one machine).** `SteamMultiplayerPeer`
silently drops reliable messages once more than about 512 KB is queued for a peer
(Steam's default send buffer): a single 1 MB RPC never arrived, and of four 256 KB RPCs
sent back to back only the first two did, with no error and no disconnect. Throughput was
about 256 KB/s (Steam's default send rate). Anything that sends more than a few hundred KB
must wait for the receiver's acks before sending more.

---

## State Synchronization

### Authority Model

The host has **full authority** over game state. Clients receive updates only.

```gdscript
# Check if current instance can modify state
if GameState.has_authority():
    GameState.update_token_property(network_id, "current_health", 50)
```

### GameState API

```gdscript
# Register a new token
GameState.register_token(token_state)

# Update a property
GameState.update_token_property(network_id, "display_name", "Dragon")

# Remove a token
GameState.remove_token(network_id)

# Get all tokens
var tokens = GameState.get_all_token_states()

# Export/import full state
var state_dict = GameState.get_full_state_dict()
GameState.apply_full_state_dict(state_dict)  # Destructive: clears and rebuilds (initial sync)
GameState.merge_full_state_dict(state_dict)  # Non-destructive: updates in place (reconciliation)
```

### Batch Updates

For multiple state changes, use batch mode to suppress signals until complete:

```gdscript
GameState.begin_batch_update()
for token in tokens:
    GameState.register_token(token.get_state())
GameState.end_batch_update()
# Emits state_batch_complete signal
```

---

## Player Roles

### Role Types

```gdscript
enum PlayerRole {
    PLAYER,  # Regular player (limited interaction)
    GM,      # Game Master (full control)
}
```

The host is **always** the GM. Other players join as PLAYER by default.

### Checking Roles

```gdscript
if NetworkManager.is_host():
    # This instance is the host/GM
    pass

if NetworkManager.get_local_role() == NetworkManager.PlayerRole.GM:
    # Has GM privileges
    pass
```

### Player Information

```gdscript
# Set local player name
NetworkManager.set_player_name("Alice")

# Get all connected players
var players = NetworkManager.get_players()
# Returns: { peer_id: { "name": "Alice", "role": PlayerRole.GM }, ... }
```

---

## Late Joiner Support

When a player joins mid-game, they automatically receive:

1. Current level data (with signal-driven ACK and timeout — no polling)
2. Full game state (all tokens and their states)

### Host-Side Handling

```gdscript
# Automatic - handled by NetworkManager
NetworkManager.late_joiner_connected.connect(func(peer_id):
    print("Late joiner connected: ", peer_id)
    # State is automatically sent
)
```

### Client-Side Handling

```gdscript
# Level data arrives first
NetworkManager.level_data_received.connect(func(level_dict):
    load_level_from_dict(level_dict)
)

# Then full game state
NetworkManager.game_state_received.connect(func(state_dict):
    apply_game_state(state_dict)
)
```

---

## Level Map Files

A level's map is up to two files in its folder: `map.glb` (Blender-made) and `map.ttmap`
(authored in tt-sim). A client without them downloads them from the host through
`AssetStreamer` under the pack id `Paths.LEVEL_MAPS_PACK_ID` (`"_level_maps"`), the
level folder as asset id, and a variant id naming the file.

- **Host whitelist.** `_rpc_request_asset` serves a level map only through
  `AssetStreamer.level_map_file_for_request(asset_id, variant_id, active_folder)`: the
  requested folder must sanitize to the active level (`is_level_request_authorized`,
  unchanged) and the variant must be `"map"` (map.glb) or `"ttmap"` (map.ttmap)
  (`Paths.get_level_map_file_for_variant`). Anything else is answered with
  `_rpc_asset_not_found`; neither client-controlled value ever becomes a path.
- **Client.** `request_map_file_from_host(folder, variant)` (file type `"model"` for the
  GLB, `Paths.LEVEL_MAP_DOCUMENT_FILE_TYPE` for the document, cached as `.glb` /
  `.ttmap` under `user://asset_cache/_level_maps/<folder>/`). `MapDownloadCoordinator`
  is told which files are missing and which are already here, waits for every one, then
  loads through the async `LevelPlayLoader.load_map_sources_async` (over the shared
  `MapSourceLoader`) and finalizes. A GLB
  that fails to download fails the map; a document that fails beside a GLB lets the GLB
  load alone (as on the host); a document-only map fails.
- **Stale cache.** `NetworkManager.broadcast_level_data()` adds `map_hashes` (variant id
  -> SHA-256 of the host's file, `MapFileHash`, cached per file version: about 57 ms for
  a 15 MB GLB the first time, under 1 ms after) to the level dict it sends and keeps for
  late joiners. The cache stores each level map file's hash beside its entry (hashed from
  memory on download, or once from disk for an older entry), and
  `AssetCacheManager.get_cached_path_matching()` drops a copy whose hash differs, so a map
  the host re-saved downloads again. A client also ignores a same-named local level file
  whose hash differs. Hashes are validated (64 lowercase hex, known variants only).
- **Signal arity.** `AssetStreamer`'s `asset_received` / `asset_failed` /
  `transfer_progress` pass a trailing `file_type`; every listener must accept it, since
  Godot 4 refuses to call a handler with fewer parameters. Until 2026-09-26 the
  coordinator's four-parameter handlers were never called, so client map downloads never
  completed.

Not yet exercised over a real Steam connection: the unit tests
(`test_map_download_coordinator.gd`, `test_level_map_streaming.gd`) cover the
coordinator, whitelist, cache and hash logic with a streamer double.

---

## Token Synchronization

### Transform Updates (Unreliable, Rate-Limited)

Transform updates are sent via unreliable channel with rate limiting to prevent flooding.

```gdscript
# Host broadcasts transform changes
NetworkStateSync.broadcast_token_transform(token)
```

**Rate Limiting:**

- Maximum 20 updates/second per token (`TRANSFORM_SEND_INTERVAL = 0.05`)
- Transforms are batched every ~30ms (`TRANSFORM_BATCH_INTERVAL = 0.033`)

### Property Updates (Reliable)

Property changes are sent reliably to ensure delivery.

```gdscript
# Host broadcasts property changes
NetworkStateSync.broadcast_token_properties(token)
```

### Client-Side Interpolation

Clients use interpolation for smooth movement:

```gdscript
# In token handler
NetworkManager.token_transform_received.connect(func(id, pos, rot, scale):
    var token = get_token_by_network_id(id)
    if token:
        token.set_interpolation_target(pos, rot, scale)
)
```

### Token Removal

```gdscript
# Host notifies all clients
NetworkStateSync.broadcast_token_removed(network_id)
```

### Periodic Reconciliation

The host runs a 2-second reconciliation timer that syncs token positions to all clients. This catches any drift between GameState and the visual tokens.

**Important:** Reconciliation skips tokens that are currently under client authority:
- Tokens drag-locked by a non-host peer (the client is actively dragging)
- Tokens still network-interpolating on the host (client just dropped, host visual hasn't converged)

This prevents the host's interpolating visual position from overwriting GameState with stale data, which would cause tokens to snap back on the client.

Reconciliation uses per-token transform broadcasts (unreliable channel) rather than full state blasts, avoiding the destructive clear-and-rebuild path that would reset client-side permissions and drag locks.

---

## Development Setup

### Steam App ID

The Steam App ID is read from `steam_appid.txt` in the project root. This file is **gitignored** — each environment provides its own:

- **Development:** `480` (Valve's SpaceWar test app) — works with any Steam account
- **Production:** Real Steam App ID (4591070)
- **CI builds:** Written from the `STEAM_APP_ID` GitHub Actions secret

A template is provided at `steam_appid.txt.example`. Copy it to get started:

```bash
cp steam_appid.txt.example steam_appid.txt
```

For production testing, replace `480` with `4591070`.

### Prerequisites

- **Steam must be running** before launching the game or editor
- GodotSteam GDExtension is bundled at `addons/godotsteam/` (no separate install needed)
- If Steam is not running, the game shows a dialog prompting the user to launch it

### Local Multiplayer Testing

Testing multiplayer requires **two game instances with different Steam accounts**. Steam
identifies peers by Steam ID, so two instances on one account cannot connect. On one
machine the second account's Steam client runs inside a
[Sandboxie-Plus](https://sandboxie-plus.com) box, and the second game instance runs in the
same box so it talks to that client. Both instances run the project from source; nothing
is exported.

`-master_ipc_name_override` (an older version of this setup) does not work: a second
Steam client from the same install hangs before startup while the main one runs (checked
2026-10-09).

#### One-time setup

1. **Install Sandboxie-Plus:** `winget install --id Sandboxie.Plus --exact` (needs admin
   once, for its driver).
2. **Create a free second Steam account** at
   [store.steampowered.com](https://store.steampowered.com). App ID 480 (SpaceWar) works
   with any account; a free (limited) account can join a private lobby by room code
   (hosting from one is untested).
3. **Start Steam in the box** and pick or log in the second account:

```powershell
.\scripts\launch-test-peer.ps1 -SetupSteam
```

This creates the `SteamAlt` box if needed and starts Steam in it. The box's Steam window
may keep showing its loading spinner; the account is logged on anyway (the box's copy of
`logs/connection_log.txt`, under `C:\Sandbox\<user>\SteamAlt\drive\C\Program Files (x86)\Steam\`,
shows `Logged On`). It stays running; do this once per login session.

#### Testing workflow

1. Open tt-sim in the **Godot editor** and hit Play. Host a game to get a room code.
2. Launch the second peer, which runs the current source in the box:

```powershell
.\scripts\launch-test-peer.ps1
```

Join with the room code from step 1. `-GodotArgs` passes extra Godot arguments (a scene
path, `--headless`); `-Box` picks another box, one per extra account for 3+ peers.

#### Automated runs (agents)

Two headless peers work without a human (probe, 2026-10-09): the host runs unsandboxed,
the client in the box.

- Command form for the boxed peer, from Bash:
  `"/c/Program Files/Sandboxie-Plus/Start.exe" /box:SteamAlt //wait "<godot exe>" --headless --path D:/dev/tt-sim <scene> -- <args>`.
  Git Bash rewrites `/wait` and `/terminate` as file paths, so they must be written
  `//wait` and `//terminate` (a single slash shows "Could not invoke program... cannot
  find the file specified"). `//wait` blocks until Godot exits and returns its exit code.
  Pass the explicit Godot exe; the `godot` wrapper does not resolve inside the box.
- The boxed process's stdout does not come back. It writes results to a file in a folder
  the box has as an `OpenFilePath` (`SbieIni.exe append SteamAlt OpenFilePath <folder>`);
  writes anywhere else, including `user://`, go to the box's private copy under
  `C:\Sandbox\<user>\SteamAlt\`. Its Godot log is at
  `C:\Sandbox\<user>\SteamAlt\user\current\AppData\Roaming\Godot\app_userdata\TTSim\logs\godot.log`.
- Steam init: `Steam.steamInitEx(480, false)` sets the app id without `steam_appid.txt`
  (which Steam reads from the process working directory).
- Steam's global fake lag/loss settings (`setGlobalConfigValueInt32` /
  `setGlobalConfigValueFloat` with `NETWORKING_CONFIG_FAKE_PACKET_*`) return success but
  had no measurable effect on a `SteamMultiplayerPeer` connection between two peers on
  this machine. Simulate bad networks in a test-side transport wrapper instead.

#### Limitations

- Both instances share the same machine's resources (CPU, GPU, network). Performance profiling should use separate machines.
- Two peers on one machine measure near-zero network latency (pings of 14-21 ms are
  Godot frame granularity), so latency bugs need simulated conditions.

### Configuration

#### Settings

Player name is stored in `Paths.SETTINGS_PATH` (`user://settings.cfg`) under the `[player]` section.

#### Constants

| Setting            | Value | Description                  |
| ------------------ | ----- | ---------------------------- |
| Max Players        | `8`   | Maximum connected players    |
| Connection Timeout | `15s` | Time before connection fails |

---

## API Reference

### NetworkManager

#### Connection Methods

```gdscript
# Host a game
func host_game() -> void

# Join a game with room code (base-36 encoded lobby ID)
func join_game(room_code: String) -> void

# Disconnect from current game
func disconnect_game() -> void
```

#### Status Methods

```gdscript
func is_host() -> bool           # Is this instance the host?
func is_client() -> bool         # Is this instance a client?
func is_networked() -> bool      # Is connected to a network game?
func get_connection_state() -> ConnectionState
```

#### Player Methods

```gdscript
func set_player_name(name: String) -> void
func get_player_name() -> String
func get_players() -> Dictionary  # { peer_id: player_info }
func get_local_role() -> PlayerRole
```

#### Game State Methods (Host Only)

```gdscript
func notify_game_starting() -> void
func broadcast_level_data(level_dict: Dictionary) -> void
func broadcast_game_state(state_dict: Dictionary) -> void
func broadcast_visual_settings(settings: Dictionary) -> void
```

`broadcast_visual_settings()`'s `settings` payload is `LevelVisualState.to_broadcast_dict()`
(`resources/level_visual_state.gd`) -- full snapshot from `GameplayMenuController` Save/Cancel, or a
partial per-field batch from `VisualBroadcastThrottle` during live edits (any subset of the same
keys: `light_intensity`, `environment_preset`, `environment_overrides`, `lofi_overrides`,
`weather_overrides`, `foliage_overrides`, `sun_settings`, `water_style`, `water_overrides`). On the
client, `visual_settings_received` is handled by `LevelPlayController._on_visual_settings_received()`, which
rebuilds a `LevelVisualState` from the current level, patches it with `patch_from_broadcast_dict()`,
writes it back with `apply_to_level_data()`, and re-applies the *whole* state via
`apply_visual_state()` -- not just the changed fields -- for every (throttled) broadcast.

### NetworkStateSync

#### Broadcast Methods (Host Only)

```gdscript
func broadcast_token_transform(token: BoardToken) -> void
func broadcast_token_properties(token: BoardToken) -> void
func broadcast_token_removed(network_id: String) -> void
func broadcast_full_state() -> void
func send_full_state_to_peer(peer_id: int) -> void
```

### GameState

#### Token Management

```gdscript
func register_token(state: TokenState) -> void
func remove_token(network_id: String) -> void
func get_token_state(network_id: String) -> TokenState
func get_all_token_states() -> Dictionary
func has_authority() -> bool
```

#### Property Updates

```gdscript
func update_token_property(network_id: String, property: String, value: Variant) -> void
func sync_from_board_token(token: BoardToken) -> void
func apply_to_board_token(network_id: String, token: BoardToken) -> void
```

#### Batch Operations

```gdscript
func begin_batch_update() -> void
func end_batch_update() -> void
```

#### Serialization

```gdscript
func get_full_state_dict() -> Dictionary
func apply_full_state_dict(data: Dictionary) -> void
func merge_full_state_dict(data: Dictionary) -> void
```

#### Drag Locks

```gdscript
func claim_drag_lock(network_id: String, peer_id: int) -> bool
func release_drag_lock(network_id: String) -> void
func get_drag_lock(network_id: String) -> int
func clear_drag_locks_for_peer(peer_id: int) -> void
```

Drag locks are included in `get_full_state_dict()` (when non-empty) so late joiners know which tokens are currently being dragged. They are preserved by `merge_full_state_dict()` and restored by `apply_full_state_dict()`.

---

## Error Handling

### Connection Failures

```gdscript
NetworkManager.connection_failed.connect(func(reason):
    UIManager.show_error("Connection failed: " + reason)
)

NetworkManager.connection_timeout.connect(func():
    UIManager.show_error("Connection timed out")
)
```

### Server Disconnection

When the host disconnects, clients receive a `connection_failed("Host disconnected")` signal and transition to `OFFLINE`. A disconnect dialog is shown automatically.

### Where `connection_failed` reaches the player

Only the lobby screens listen: `LobbyClient._on_connection_failed()` shows
`"Connection failed: <reason>"` in the join screen's status label, and `LobbyHost` shows the
reason as an error toast (`UIManager.show_error`) and cancels hosting. Once in `PLAYING`, a drop shows `Root`'s generic "Disconnected" dialog
instead, which does not include the reason.

---

## Steam Integration

The project uses [GodotSteam](https://codeberg.org/godotsteam/godotsteam) GDExtension for Steam API access.

### How It Works

1. Host creates a **private Steam lobby** — only invited players or those with the room code can join
2. Room codes are **base-36 encoded lobby IDs** (e.g., `1abc2d`) — shorter and case-insensitive
3. `SteamMultiplayerPeer` wraps Steam Networking Sockets, providing the same `MultiplayerPeer` interface as `ENetMultiplayerPeer`
4. All traffic routes through **Valve's SDR relay network** — no port forwarding or NAT punchthrough needed

### Room Codes

Room codes are base-36 encoded Steam lobby IDs, produced by the `LobbyCode` utility:

```gdscript
# Encoding (host side)
var code = LobbyCode.encode(lobby_id)  # e.g., "1abc2d"

# Decoding (client side, case-insensitive)
var lobby_id = LobbyCode.decode("1ABC2D")  # same result
```

### Steam Invite

The host lobby includes an **Invite** button that opens the Steam overlay invite dialog:

```gdscript
NetworkManager.open_invite_overlay()
```
