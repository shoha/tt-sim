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
| `NetworkManager`   | Connection lifecycle, player tracking, level start, late-joiner level snapshot |
| `NetworkStateSync` | State broadcasting, rate limiting, batching        |
| `GameState`        | Authoritative game state storage                   |

`NetworkManager` creates two child nodes in its `_ready` that carry the rest of the RPCs. They
are not autoloads; reach them through the manager:

| Child (node path) | Class | Carries |
| ----------------- | ----- | ------- |
| `NetworkManager.game_sync` (`/root/NetworkManager/GameSync`) | `NetworkGameSync` (`autoloads/network_game_sync.gd`) | Table play: token transforms, state and removal, drag locks, live visual settings (see [NetworkGameSync](#networkgamesync)) |
| `NetworkManager.permissions` (`/root/NetworkManager/Permissions`) | `NetworkPermissions` (`autoloads/network_permissions.gd`) | Token permission requests, responses and broadcasts; avatar recipe edits |

Callers send through each node's typed `send_*` / `broadcast_*` methods and listen to its
signals; nothing outside a node calls its `_rpc_*` methods.

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
signal table_loaded(peer_id: int)  # host: a client's level load completed
```

Token, drag-lock and visual-settings signals live on `NetworkManager.game_sync`
(`NetworkGameSync`); see [its API](#networkgamesync).

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

The gate is also what lets the RPC layout change freely between versions. Godot addresses an
RPC by its node path and by the method's index among that node's RPC names, sorted, so adding,
removing or moving an RPC changes what an older peer would send and expect. Moving the table-play
RPCs from `/root/NetworkManager` to `/root/NetworkManager/GameSync` (2026-10-09) is one such
change. It is safe because both peers always run the same build. The gate RPCs themselves stay
on `NetworkManager`, but their indices shift with every change to its RPC list too. Two builds
that report the same version (two dev checkouts) pass both checks, so nothing catches an RPC
layout difference between them: test two peers on the same commit.

Clients send their version under `"version"` in `_local_player_info`. A host from before the
gate publishes no lobby version, which the client reads as `""` and reports as "an older
version"; a client from before the gate sends no version and the host rejects it.

On `_rpc_version_rejected` the client leaves on its own (deferred `_handle_connection_error`)
with the version message, before the host's delayed disconnect lands, so the player sees the
version reason and not "Host disconnected". The host defers a late joiner's
`LateJoinerSync.sync_peer()` until the player info passes the gate, so a rejected client is never
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

When a player joins mid-game, they automatically receive (`autoloads/late_joiner_sync.gd`):

1. `_rpc_game_starting` (`send_game_starting_to_peer()`), which moves them into `PLAYING`
2. Current level data (`send_level_snapshot_to_peer()`): the `_current_level_dict` snapshot
   `broadcast_level_data()` stored, with every live visual edit since folded in through
   `update_level_snapshot()`. NetworkManager treats the snapshot as opaque; the caller's patch
   knows the keys (`LevelVisualState.patch_level_dict()` for visual settings)
3. Full game state (all tokens, avatars, permissions and drag locks), held by the host until
   the client reports its table loaded

The hold matters. The client's `LevelPlayLoader` yields three frames and then
`clear_level()` resets `GameState`, so a state that lands inside that yield is wiped.
Until 2026-10-09 the client ACKed on mere receipt of the level data and the host sent the
state on that ACK, which put it inside the yield: every late joiner lost the table, and
reconciliation (positions only) never repaired it. Now `Root._on_level_loading_completed()`
calls `NetworkManager.report_table_loaded()` (`_rpc_table_loaded`, sender taken from the
transport) after the load, and the host's `table_loaded(peer_id)` releases the state.

The hold ends on the report; early, with nothing sent, when the peer leaves `_players` or the
host stops hosting; and after `LateJoinerSync.TABLE_LOADED_TIMEOUT` (300 s) with the state
sent anyway, since the client is long past its clear by then. The cap is generous because the
report waits for token model downloads, and a 20 MB map takes about 13 s per peer at Steam's
1 MB/s. A client does not report while a queued level is about to clear its table again.

A mid-game level change does not have this race: the host sends no full state with it. The
new table travels in the level data itself (token placements, whose network ids are the
placement ids on every peer), and the host rebuilds its own `GameState` from the same
placements. A state broadcast that reaches a client before its clear describes the old table,
which the clear rightly discards.

### Host-Side Handling

```gdscript
# Automatic - handled by NetworkManager and LateJoinerSync
NetworkManager.late_joiner_connected.connect(func(peer_id):
    print("Late joiner connected: ", peer_id)
    # Emitted after the state was sent, once the peer's table loaded
)
```

### Client-Side Handling

```gdscript
# Level data arrives first
NetworkManager.level_data_received.connect(func(level_dict):
    load_level_from_dict(level_dict)
)

# When the load completes, report it; the host then sends the full state
NetworkManager.report_table_loaded()

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

- **Flow control.** The host serves bulk transfers to one peer at a time: peers wait in a
  host-wide FIFO in the order they first asked (`StreamPeerQueue`,
  `utils/stream_peer_queue.gd`), only the head peer's chunks are sent, and the next peer
  is served once the head's transfers finish or it disconnects. A file several peers ask
  for is sent to each in turn. For the served peer, `AssetStreamer` keeps at most
  `SEND_WINDOW_BYTES` (256 KB) of chunks unacknowledged, shared across its transfers
  (`StreamSendWindow`, `utils/stream_send_window.gd`); the client acks the unbroken run
  of chunks it holds, and the host only moves an ack forward. A served peer that acks
  nothing new for `STALL_TIMEOUT_MS` (10 s) is logged and moved to the back of the queue,
  its transfers rewound to the last ack so its next turn resumes from there; acks from a
  waiting peer send nothing. The window exists because `SteamMultiplayerPeer` silently
  drops reliable messages once about 512 KB is queued (see
  [Transport Resilience](#transport-resilience)): before it, a 12.9 MB compressed map
  stalled at 21 of 394 chunks with the host reporting "Finished sending". Resume keeps
  the chunks already received when the file is unchanged.
- **Send rate.** `SteamNetConfig.apply_defaults()` (`utils/steam_net_config.gd`) runs right
  after Steam initialises and sets the global SendRateMin to 1 MB/s and SendRateMax to
  4 MB/s, per connection. SendRateMin is the setting that counts: raising only the max
  changed nothing, and Steam sends at the min whatever the real uplink carries. Because
  the rate is per connection and Steam has no one-to-many send, the one-peer-at-a-time
  queue above is what keeps the host's total upload near 1 MB/s whatever the player
  count. The same map took 51 s at Steam's default, 13 s at 1 MB/s, 3.4 s at 4 MB/s.

Exercised over a real Steam connection by `tests/net/steam_map_download.tscn` (not in the
GUT suite; see [Automated runs](#automated-runs-agents)). The unit tests
(`test_map_download_coordinator.gd`, `test_level_map_streaming.gd`,
`test_asset_streamer_flow_control.gd`, `test_stream_send_window.gd`,
`test_stream_peer_queue.gd`) cover the coordinator, whitelist, cache, hash, window and
queue logic with a streamer double; with one alt account, more than one client is tested
only there.

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
NetworkManager.game_sync.token_transform_received.connect(func(id, pos, rot, scale):
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
  this machine. Simulate bad networks in a test-side transport wrapper instead. (Global
  config does reach these connections: SendRateMin changes throughput.)
- Regression scenario: `tests/net/steam_map_download.tscn`. Run the host unsandboxed
  with `--role=host` and the client in the box with `--role=client`, both with the same
  `--rendezvous` file and each with its own `--out` log in the box's OpenFilePath folder;
  allow `--timeout-s` of about 240. `--level` must start with `_nettest_`; the host
  copies the map into that level and deletes it afterwards, and the client clears its
  own cached copy, so no manual cache cleanup is needed. Each side writes one
  `NET_RESULT {json}` line.

#### ENet scenarios (no Steam)

Two headless processes on 127.0.0.1 run the whole game over `ENetMultiplayerPeer` (the
scenario sets NetworkManager's peer and state the way the Steam lobby callbacks would), on the
shipped res:// map, so nothing downloads and no second Steam account is needed. Both share
`user://`. Start the host in the background, then the client, with the same `--rendezvous`
path prefix and each with its own `--out` log:

`godot --headless --path D:/dev/tt-sim res://tests/net/<scenario>.tscn -- --role=host|client --rendezvous=<abs prefix> --out=<abs log> --timeout-s=180`

Each side writes one `NET_RESULT {json}` line and exits 0 on a pass.

- `enet_late_joiner.tscn`: the client joins after the host placed an avatar and must see it
  once its table has loaded (`LateJoinerSync`'s hold).
- `enet_game_sync.tscn`: after that late join, the client moves a token it was given CONTROL
  of (drag-lock claim, transform, release) and receives its resting position; the host renames
  it, removes a second token and changes the light intensity. Both logs show each message
  arriving with the right sender, and the host's copy of the token locked through
  `grant_drag_lock()`. Passed on 2026-10-09 (about 4 s on the host).

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
func send_game_state_to_peer(peer_id: int, state_dict: Dictionary) -> void
func send_game_starting_to_peer(peer_id: int) -> void   # late joiner (LateJoinerSync)
func send_level_snapshot_to_peer(peer_id: int) -> void  # late joiner (LateJoinerSync)
func update_level_snapshot(patch: Callable) -> void     # patch: func(Dictionary) -> Dictionary
```

`update_level_snapshot()` is a no-op while no level is active, so a patch never fabricates a
snapshot.

#### Client Methods

```gdscript
func report_table_loaded() -> void  # after a level load; releases a late joiner's state
```

### NetworkGameSync

`NetworkManager.game_sync`, node `/root/NetworkManager/GameSync`, `autoloads/network_game_sync.gd`.
Table play once a level is loaded. Every inbound client RPC only acts on the host and takes the
sender from the transport; the listeners (`NetworkTokenSync` on the host) check CONTROL and lock
ownership.

#### Host Methods

```gdscript
func broadcast_token_transform(network_id: String, pos: Vector3, rot: Vector3, scl: Vector3) -> void
func send_token_transform_to_peer(peer_id: int, network_id: String, pos: Vector3, rot: Vector3, scl: Vector3) -> void
func broadcast_transform_batch(batch: Dictionary) -> void
func broadcast_token_state(network_id: String, token_dict: Dictionary) -> void
func broadcast_token_removed(network_id: String) -> void
func broadcast_visual_settings(settings: Dictionary) -> void
func grant_drag_lock(network_id: String, peer_id: int) -> bool
func send_drag_lock_denied(peer_id: int, network_id: String) -> void
func broadcast_drag_lock_released(network_id: String) -> void
```

`NetworkStateSync` decides when the token sends go out (throttling, batching, keeping
`GameState` in step); call it, not these, for token updates.

`grant_drag_lock()` is the one place the host hands out a drag lock, both to itself (peer 1,
from `DraggableToken` when the GM starts a drag) and to a client whose claim passed its CONTROL
check (`NetworkTokenSync`). It claims the lock in `GameState`, emits `drag_lock_granted` on the
host as well (so the host's copy of the token locks through the same listener as every
client's), and broadcasts the grant. It returns false, sending nothing, when another peer holds
the lock; the claim path then sends `send_drag_lock_denied()`. Releases are not merged: each
caller releases in `GameState` and on its own token, then calls `broadcast_drag_lock_released()`.

#### Client Methods

```gdscript
func send_client_token_transform(network_id: String, pos: Vector3, rot: Vector3, scl: Vector3) -> void
func send_drag_lock_claim(network_id: String) -> void
func send_drag_lock_release(network_id: String) -> void
```

#### Signals

```gdscript
# Clients, from the host
signal token_transform_received(network_id, position, rotation, scale)
signal token_state_received(network_id, token_dict)
signal token_removed_received(network_id)
signal transform_batch_received(batch: Dictionary)
signal visual_settings_received(settings: Dictionary)
signal drag_lock_denied(network_id)      # the denied client only
signal drag_lock_released(network_id)

# Every peer: the host's own grant_drag_lock() emits it too
signal drag_lock_granted(network_id, locker_peer_id)

# Host, from a client (sender from the transport)
signal client_token_transform_received(sender_id, network_id, position, rotation, scale)
signal client_drag_lock_claimed(sender_id, network_id)
signal client_drag_lock_released(sender_id, network_id)
```

#### RPCs

| RPC | Direction | Channel | Emits |
|-----|-----------|---------|-------|
| `_rpc_receive_token_transform` | host -> clients | unreliable | `token_transform_received` |
| `_rpc_receive_transform_batch` | host -> clients | unreliable | `transform_batch_received` |
| `_rpc_receive_token_state` | host -> clients | reliable | `token_state_received` |
| `_rpc_receive_token_removed` | host -> clients | reliable | `token_removed_received` |
| `_rpc_receive_visual_settings` | host -> clients | reliable | `visual_settings_received` |
| `_rpc_drag_lock_granted` | host -> clients | reliable | `drag_lock_granted` |
| `_rpc_drag_lock_denied` | host -> one client | reliable | `drag_lock_denied` |
| `_rpc_drag_lock_released` | host -> clients | reliable | `drag_lock_released` |
| `_rpc_client_token_transform` | client -> host | unreliable, dropped when a token's updates arrive faster than `CLIENT_TRANSFORM_RATE_LIMIT` (0.05 s) | `client_token_transform_received` |
| `_rpc_client_claim_drag_lock` | client -> host | reliable | `client_drag_lock_claimed` |
| `_rpc_client_release_drag_lock` | client -> host | reliable | `client_drag_lock_released` |

The client used to ACK every full state (`_rpc_state_sync_ack`, `state_sync_complete`); nothing
listened, and both were removed on 2026-10-09. A late joiner's state is released by
`report_table_loaded()` instead.

#### Visual settings

`broadcast_visual_settings()`'s `settings` payload is `LevelVisualState.to_broadcast_dict()`
(`resources/level_visual_state.gd`) -- full snapshot from `GameplayMenuController` Save/Cancel, or a
partial per-field batch from `VisualBroadcastThrottle` during live edits (any subset of the same
keys: `light_intensity`, `environment_preset`, `environment_overrides`, `lofi_overrides`,
`weather_overrides`, `foliage_overrides`, `sun_settings`, `water_style`, `water_overrides`). On the
client, `visual_settings_received` is handled by `LevelPlayController._on_visual_settings_received()`, which
rebuilds a `LevelVisualState` from the current level, patches it with `patch_from_broadcast_dict()`,
writes it back with `apply_to_level_data()`, and re-applies the *whole* state via
`apply_visual_state()` -- not just the changed fields -- for every (throttled) broadcast.

On the host, the same broadcast also patches the late-joiner snapshot through
`NetworkManager.update_level_snapshot()` with `LevelVisualState.patch_level_dict()`, which maps
each broadcast key onto the `LevelData.to_dict()` field it stands for (`light_intensity` to
`light_intensity_scale`, `sun_settings` nested under `visual_settings.sun`, the rest 1:1).

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
