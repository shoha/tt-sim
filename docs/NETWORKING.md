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
- [Configuration](#configuration)
- [API Reference](#api-reference)

---

## Overview

The networking system uses a **host-authoritative architecture** where one player acts as the host (server) and others connect as clients. Key features:

- **NAT Punchthrough** via Noray server for peer-to-peer connections
- **Relay Fallback** when direct connections fail
- **State Synchronization** for game state and token transforms
- **Late Joiner Support** with full state catch-up
- **Rate-Limited Updates** to prevent network flooding

### Core Components

| Autoload           | Purpose                                            |
| ------------------ | -------------------------------------------------- |
| `NetworkManager`   | Connection lifecycle, player tracking, RPC routing |
| `NetworkStateSync` | State broadcasting, rate limiting, batching        |
| `GameState`        | Authoritative game state storage                   |
| `Noray`            | NAT punchthrough and relay server client           |

---

## Architecture

### Connection States

```gdscript
enum ConnectionState {
    OFFLINE,     # Not connected
    CONNECTING,  # Connecting to Noray or game server
    HOSTING,     # Hosting a game
    JOINED,      # Connected as client
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
signal transform_batch_received(batch: Array)
```

---

## Connection Flow

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

1. Connect to Noray server
2. Register as host → receive OID (room code)
3. Wait for PID (private ID)
4. Register remote address → get `local_port`
5. Start ENet server on registered port
6. Ready for client connections

### Joining a Game

```gdscript
# Join with room code
NetworkManager.join_game("ABC123")

# Handle success
NetworkManager.connection_state_changed.connect(func(old, new):
    if new == NetworkManager.ConnectionState.JOINED:
        print("Connected!")
)
```

**Internal Flow:**

1. Connect to Noray server
2. Register to get PID
3. Register remote address → get `local_port`
4. Request NAT connection with room code
5. Receive connection info (NAT or relay)
6. Create ENet client and connect to host
7. Receive level data and game state

### Disconnecting

```gdscript
NetworkManager.disconnect_game()
```

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
GameState.apply_full_state_dict(state_dict)
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

1. Current level data
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

---

## Configuration

### Network Settings

Settings are stored in `user://settings.cfg`:

```gdscript
# Change Noray server
NetworkManager.set_noray_server("my-server.com", 8890)
NetworkManager.save_network_settings()

# Get current settings
var server = NetworkManager.noray_server_address
var port = NetworkManager.noray_server_port
```

### Default Values

| Setting            | Default         | Description                  |
| ------------------ | --------------- | ---------------------------- |
| Noray Server       | `192.168.0.244` | Noray server address         |
| Noray Port         | `8890`          | Noray server port            |
| Game Port          | `7777`          | ENet game server port        |
| Max Players        | `8`             | Maximum connected players    |
| Connection Timeout | `15s`           | Time before connection fails |

---

## API Reference

### NetworkManager

#### Connection Methods

```gdscript
# Host a game (optional server override)
func host_game(server_override: String = "", port_override: int = 0) -> void

# Join a game with room code
func join_game(room_code: String, server_override: String = "", port_override: int = 0) -> void

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
```

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

```gdscript
# Clients are notified when host disconnects
multiplayer.server_disconnected.connect(func():
    UIManager.show_error("Host disconnected")
    NetworkManager.disconnect_game()
)
```

---

## Noray Integration

The project uses [netfox.noray](https://github.com/foxssake/netfox.noray) for NAT punchthrough.

### How It Works

1. Both host and clients connect to a central Noray server
2. Noray facilitates NAT punchthrough between peers
3. If NAT fails, traffic is relayed through the Noray server

### Room Codes

Room codes (OIDs) are 6-character alphanumeric strings generated by Noray:

```gdscript
NetworkManager.room_code_received.connect(func(code):
    # code example: "A1B2C3"
    share_code_with_friends(code)
)
```
