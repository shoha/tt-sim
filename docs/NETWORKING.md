# Networking Guide

This document covers the multiplayer networking system, including connection management, state synchronization, and the host-authoritative architecture.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Connection Flow](#connection-flow)
- [State Synchronization](#state-synchronization)
- [Player Roles](#player-roles)
- [Late Joiner Support](#late-joiner-support)
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
3. On `lobby_created` callback: create `SteamMultiplayerPeer` host
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
4. On `lobby_joined` callback: get host Steam ID, create `SteamMultiplayerPeer` client
5. Wait for Godot's `connected_to_server` signal
6. Receive level data and game state

### Disconnecting

```gdscript
NetworkManager.disconnect_game()
```

Leaves the Steam lobby, closes the multiplayer peer, and clears all state.

### Transport Resilience

Steam SDR (Steam Datagram Relay) handles transport-level resilience including packet retransmission and route optimization. There is no application-level reconnection logic — if the connection drops entirely, the client is disconnected and must rejoin.

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

Testing multiplayer requires **two game instances with different Steam accounts**. The recommended setup runs the Godot editor as one peer and an exported debug build as the second.

#### One-time setup

1. **Create a free second Steam account** at [store.steampowered.com](https://store.steampowered.com). No purchase needed — App ID 480 (SpaceWar) works with any account.

2. **Launch the secondary Steam client** and log in:

```powershell
.\scripts\launch-test-peer.ps1 -SetupSteam
```

This runs `steam.exe -master_ipc_name_override tt-sim-testing -userchooser`, which opens a separate Steam client with its own IPC channel. Log in with the second account. The secondary client stays running in the background — you only need to do this once per session.

#### Testing workflow

1. Open tt-sim in the **Godot editor** and hit Play. Host a game — you'll get a room code.

2. In a **PowerShell terminal**, launch the second peer:

```powershell
.\scripts\launch-test-peer.ps1
```

This exports a debug build to `build/windows-debug/` and launches it connected to the secondary Steam account. Join with the room code from step 1.

#### Script options

| Flag | Effect |
|------|--------|
| `-SetupSteam` | Launch the secondary Steam client for login |
| `-SkipExport` | Reuse the last debug build (faster when only host-side code changed) |
| `-ExportOnly` | Export the debug build without launching |
| (no flags) | Export + launch |

#### How it works

Steam identifies peers by Steam ID. Two instances on the same account share the same ID and cannot form a connection. The script solves this by running a second Steam client with a separate IPC name (`-master_ipc_name_override`) and pointing the debug build at it via the `steam_master_ipc_name_override` environment variable. Each instance then has a distinct Steam ID.

#### Limitations

- The debug build must be re-exported to pick up code changes. Use `-SkipExport` when you only changed host-side logic and just need a connected peer.
- Both instances share the same machine's resources (CPU, GPU, network). Performance profiling should use separate machines.

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
