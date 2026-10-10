# Networking Guide

This document covers the multiplayer networking system, including connection management, state synchronization, and the host-authoritative architecture.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Connection Flow](#connection-flow)
- [State Synchronization](#state-synchronization)
- [Player Roles](#player-roles)
- [Sessions: the room and the table](#sessions-the-room-and-the-table)
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

`NetworkManager` creates three child nodes in its `_ready` that carry the rest of the RPCs. They
are not autoloads; reach them through the manager:

| Child (node path) | Class | Carries |
| ----------------- | ----- | ------- |
| `NetworkManager.game_sync` (`/root/NetworkManager/GameSync`) | `NetworkGameSync` (`autoloads/network_game_sync.gd`) | Table play: token transforms, state and removal, drag locks, live visual settings (see [NetworkGameSync](#networkgamesync)) |
| `NetworkManager.permissions` (`/root/NetworkManager/Permissions`) | `NetworkPermissions` (`autoloads/network_permissions.gd`) | Token permission requests, responses and broadcasts; avatar recipe edits |
| `NetworkManager.session` (`/root/NetworkManager/Session`) | `SessionChannel` (`autoloads/session_channel.gd`) | The session: the room, the shelf of maps, the table pointer, players by Steam id, and where a joiner lands (see [Sessions](#sessions-the-room-and-the-table)) |

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
version reason and not "Host disconnected". The host admits a joiner to the session
(`SessionChannel.admit_peer()`: the room, or `LateJoinerSync.sync_peer()` at a table) only once
its player info passes the gate, so a rejected client is never moved into the room or `PLAYING`
and the message appears on the join screen, where `LobbyClient` keeps the `connection_failed`
reason on screen through the following `OFFLINE` state change.

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

## Sessions: the room and the table

A hosted session is a room of people that can exist with no map (Room first, user decision
2026-10-09). It begins when hosting starts and ends when the host leaves; the GM sets maps out
from a shelf, and leaving a map returns everyone to the room. Nobody reconnects in between: the
Steam lobby, the multiplayer peer, the room code and every client's peer id outlive every map.
`SessionChannel` (`NetworkManager.session`) holds it; `Root.State.ROOM` is its screen, the
RoomPanel full screen (`RoomScreen`), and at a table the same panel is the room drawer
(`RoomDrawer`, Tab). Both read the session summary; see [UI_SYSTEMS.md](UI_SYSTEMS.md) "The
room".

**Phases.** The host's session is in the room (`is_open()`, no table) or at a table (one map
out). Hosting starts in the room (`SessionChannel` begins on `HOSTING`). `open()` (host) clears
the late-joiner level snapshot (`clear_level_data()`: nothing is served, `is_game_in_progress()`
is false) and sends every client `_rpc_room_opened`; `close()` comes just before
`notify_game_starting()`, and the level broadcast that follows sets the table pointer.

**Shelf and table pointer.** The shelf is the session's maps, each a MapRef `{"folder",
"map_path", "hashes", "name"}` keyed by `ref_key()`, the level folder or, for a level without
one, its res:// map path; the name is what the room lists. The GM adds a map from the room
(Add a map, a picker over the library) through `shelve(level_dict)`, which hashes its files and
leaves the room open. `broadcast_level_data()` calls `note_table_out()` with the payload (map
hashes added), so every map that goes out, from the room or by a map change in play, lands on
the shelf too; setting a shelved map out again refreshes its hashes. Root sets a shelf map out
by key (`Root.set_out(key)` from the room, `Root.move_table(key)` from the drawer), and its
TableMover loads the level from the host's library by its folder and lays over it what this
session did to that map (see "Table moves" below). `get_table()` is that key, `""` in the room. Only the host changes any of it; it sends
clients a summary (`_rpc_session_summary`, sanitized on arrival by `sanitize_summary()`: known
keys, typed values, bounded sizes) after every change, so clients read the same getters and
`session_changed` fires on every peer.

**Players by Steam id.** `get_players()` is session id -> `{"name", "peer_id"}`. The session id
is the Steam id as a decimal string (`SteamMultiplayerPeer.get_steam_id_for_peer_id`, and
`Steam.getSteamID()` for the host itself). A transport without Steam ids (the ENet scenarios,
GUT) has no identity of its own, so there it is `"enet-"` plus the `session_key` the joiner
reports in its player info (`SessionChannel.SESSION_KEY`, cleaned by `clean_key()`: 1 to 32
letters, digits, `-` or `_`), or plus its peer id when it reports none; a key held by a player
still connected is not taken. Steam ignores the key, so a client cannot claim another player's
identity there, and a stale connection of the same Steam id gives its entry to the new one. A player who leaves keeps its entry with `peer_id` 0, and a rejoin (a new peer
id, the same session id) reuses it, so the party and its grants map a session id to whatever
peer id it has now (`peer_for()`, `session_id_of()`). The Steam path is not verified yet: real
Steam could not run on 2026-10-09.

**Holdings: readiness is download state.** There is no manual Ready. After every summary, and
again on `_rpc_room_opened`, a client works out which shelf maps it already holds at the host's
content (`holds_map()`: a map that ships with the game, or every hashed file in its own level
folder with the same hash or in the download cache) and reports the keys when they changed
(`_rpc_report_holdings`, `any_peer`: the host keeps only shelf keys, under the sender's own
session id, `note_holdings()`). The host counts itself as holding every shelf map.
`get_holdings()` (session id -> keys) rides in the summary, and the room shows it ("3 of 4 have
it"). Set out never waits for it: a player without the map downloads it at the table as before.
A host that sent no hashes for a folder map leaves it counted as not held.

**Prefetch: shelf maps come in the background** (`SessionPrefetch`,
`NetworkManager.session.prefetch`). Before it, a client downloaded a map only when it was set
out, and the host serves one peer at a time, so a 20 MB map at Steam's 1 MB/s kept the fourth
player waiting about 40 s. Now every client fetches the shelf maps it lacks as soon as the GM
adds them, while it waits in the room or plays at a table:

- *Order.* The map on the table, then the GM's selected shelf map (`select_map()`, which
  `RoomPanel.select()` calls on the GM's side; `"selected"` in the summary), then shelf order
  (`SessionPrefetch.order()`). A client fetches one map at a time, every missing file of it at
  once (`missing_variants()`), so both headers arrive together and its progress is by bytes. A
  client re-runs the step on every summary and on `room_opened`, deferred to the end of the
  frame, so several summaries arriving together count once.
- *Requests.* Each file is `AssetStreamer.request_map_file_from_host(folder, variant, priority,
  true)`: a prefetch takes none of the client's two download slots (it waits at the host, not
  here). A table request for a file being prefetched takes that download over (its prefetch
  flag clears) instead of asking again. A finished map lands in the download cache, the client
  reports its holdings at once, and the table's load finds it there
  (`LevelPlayLoader._resolve_map_sources`) with no second transfer.
- *The table first.* The host classes every transfer at every send: a prefetch is a level map
  file of a folder other than the one on the table (`AssetStreamer.is_prefetch_transfer`), and
  everything else (token assets, the table's own map files) is a table transfer. A peer with a
  table transfer is served before peers with only prefetches (`StreamPeerQueue.served`), and
  within one peer the table's transfers take the window first. A prefetch that is passed over
  keeps its place, its acknowledged chunks and its in-flight window, and resumes once no table
  transfer is left; a prefetch of the map just set out is a table transfer from then on.
- *Cancel.* A map that leaves the shelf (`unshelve()`, host; the map on the table cannot) is
  dropped: the host stops sending its files to everyone (`drop_level_transfers`), and each
  client cancels its fetch on the summary (`AssetStreamer.cancel_download`, which tells the host
  through `_rpc_cancel_asset`), never a download the table's load took over. A map whose fetch
  fails is left for the table's load. The room has no Remove control yet; `unshelve()` is the
  engine's.
- *Progress.* Each client reports `{ref key: percent}` for the map it is getting and 0 for each
  waiting behind it (`_rpc_report_progress`, at most every 0.25 s and only on a change); the
  host keeps shelf keys only, by the sender's session id (`note_progress()`), and sends every
  client the whole map (`_rpc_progress`) on each change; it also rides in the summary
  (`"progress"`, sanitized on arrival). `progress_changed` fires on every peer, and the room
  updates its rows in place (`RoomPanel.show_progress()`): "Getting it · 40%" in lake, "Waiting
  to get it" while a map waits its turn, "Has it" once held.

**The party** (`NetworkManager.session.party`, `SessionParty`, `autoloads/session_party.gd`,
host only). Players' avatars belong to the session, not to a map.

- *Grants by session id.* GameState keeps CONTROL grants by the peer ids at the table, and
  `TokenPermissionHandler` clears a leaver's. The party keeps every deliberate grant and revoke
  (`GameState.token_permission_granted` / `token_permission_revoked`, which the clears never
  emit) as session id -> network ids (`get_grants()`), and drops a token's when the token is
  removed (`token_removed`, which a table's teardown emits for every token). `admit_peer()`
  calls `restore_grants()` before any table state goes out, so a player who rejoins controls
  its tokens again under its new peer id; the late joiner's full state carries the grant. The
  GM's Revoke control also drops the grants of players who are away (`revoke_all()`).
- *Members.* A member is an avatar token a session player controls; an avatar nobody controls
  and every prop stay with the map. Granting a player an avatar adopts it: it leaves the
  active level's placements (`TokenSpawner.release_placement`), so saving the map no longer
  writes it; when its last owner loses it, it gets a placement again (`restore_placement`).
- *Travel.* Root calls `take()` before a table goes (Return everyone to the room, or a map
  change in play): each member as `{"state": TokenState dict, "owners": [session ids]}`, plain
  data a session file can write (`get_members()`). Once the next map has loaded
  (`Root._on_level_play_loaded`), `set_out()` rebuilds each member under its own network id
  outside that map's placements (`TokenSpawner.place_session_token`), on a block one 5 ft
  square apart around the map's spawn point (`LevelData.spawn_point`, optional, written only
  when `has_spawn_point`; no authoring tool sets it yet) or, without one, the camera's ground
  point; grants it again to each owner connected now (an owner who is away gets it on
  rejoining); and a physics frame later sets each down with `TokenGrounding.reground` (cast
  from above the map when it starts buried), shows it with its arrival, and sends the full
  state. A client that was connected then gets the full state again on its table-loaded report,
  since a state that lands before its loader's `clear_level()` is wiped (see Late Joiner
  Support). A member the new map already has (a placement saved before it was adopted) is not
  placed twice; its owners get it back where the map put it.
- *Known gap.* An avatar the GM spawns in play and saves into the map before granting it is
  saved under its placement id, which differs from its network id; if the session returns to
  that map, the map's copy and the party's member both appear.

**Where a joiner lands.** `NetworkManager._rpc_send_player_info()` calls `admit_peer()` once for
each new peer that passed the version gate. In the room the joiner gets `_rpc_room_opened` and
Root enters `ROOM`; at a table it gets `LateJoinerSync.sync_peer()` (game_starting, the level,
then the state after its table-loaded report, below). Only a peer that is still connected is
sent anything.

**Root's transitions** (`scenes/root.gd`; entering ROOM never connects, the action that leads
there does):

| From > to | Action | What happens |
|-----------|--------|--------------|
| TITLE > ROOM (host) | Host with a map: `host_session(level)` | `host_game()` with an "Opening a room..." wait; ROOM on `HOSTING`; on `connection_failed` the title stays, with the reason |
| TITLE > ROOM or PLAYING (client) | Join: the join form (`LobbyClient`) over the hidden title | Connect joins; the form stays locked ("Connected. Joining the room...") until ROOM on `room_opened`, or PLAYING on `game_starting` when a table is out; a rejected client stays on the form |
| ROOM (host) | Entering with a map from Host | The map is shelved and selected in the room |
| ROOM > PLAYING | The room's Set out this map: `set_out(key)`, then `_on_lobby_start_game()` | Refused with "Choose a map to set out first" when no map is pending; else `close()`, `notify_game_starting()`, PLAYING broadcasts the level |
| PLAYING > ROOM | Pause > Return everyone to the room (host): `return_to_room()`, a table move to the room | After TableMover's prompt (only when the table changed) and notice: the table's state is kept, saved or discarded, the party is taken, `open()`, then the table (GameMap, tokens, GameState) is torn down on every peer |
| PLAYING > PLAYING | The drawer's Move the table to the selected map (`move_table(key)`) | After the same prompt and notice: the party is taken; the next map comes with its kept state; the level broadcast moves the table pointer |

#### Table moves

`TableMover` (`scenes/table_mover.gd`, a child of Root) runs both moves for the host. A map is a
template: nothing a session does changes its level folder unless the GM picks Save into map.
`changes()` compares the table with its map: the tokens a save writes
(`LevelPlayController.has_unsaved_tokens()`, which counts only tokens with a placement, so the
party never does), the look (`TableStates.look_of()`, every live-synced visual field and the
grid scale, against the look the map loaded with; a save of the map moves it) and the live
edits' op log. When anything changed the GM is asked once, Keep for this session (the
default, focused), Save into map or Discard; Escape stays. Then `SessionChannel.announce_move()`
(`_rpc_table_moving`, text clipped, seconds bounded to `MAX_NOTICE_S`) shows every peer the
notice (`TableMoveNotice`, `NOTICE_S` = 3 s), and the GM's Stay here calls it off
(`cancel_move()`). At its end `move_now()` settles the table: Keep stores `TableStates.capture()`
(the placements synced from their tokens, the look, the op log) under the shelf key when the
table differs from its map, else forgets it; Save into map writes the edited document
(`MapDocumentIO.write`, when there were live edits) and then the level (the HUD's save path);
Discard forgets it. Arriving at a map, its kept state is laid over the template's LevelData
before it is set out (`TableStates.overlay()`), so every peer and every late joiner gets the
tokens and the look in the level broadcast and snapshot, and its op log goes to
`LevelPlayController.replay_log`: the host's `LiveEdits` applies it before the tokens land and
keeps it as its log, so clients and late joiners catch up on it as on any table's log. The
state is memory only (a session file keeps it later) and is forgotten when a session begins or
ends. A restored token comes back under its placement id, so a token placed in play returns
with a new network id (the party keeps theirs).
| (any) > PLAYING, map loaded | `_on_level_play_loaded()` (host) | The party is set out on the new map |
| ROOM or PLAYING > TITLE | Leave or End session (the room, the drawer), Return to Title | Title first, then `disconnect_game()`, so a voluntary leave is not read as a lost connection; the host leaving ends the session (End session asks first) |

A client that loses the host in the room gets the same "Disconnected" dialog as at a table.

---

## Late Joiner Support

When a player joins while a table is out, they automatically receive
(`autoloads/late_joiner_sync.gd`; a player joining while the room is open gets `room_opened`
instead, see [Sessions](#sessions-the-room-and-the-table)):

1. `_rpc_game_starting` (`send_game_starting_to_peer()`), which moves them into `PLAYING`
2. Current level data (`send_level_snapshot_to_peer()`): the `_current_level_dict` snapshot
   `broadcast_level_data()` stored, with every live visual edit since folded in through
   `update_level_snapshot()`. NetworkManager treats the snapshot as opaque; the caller's patch
   knows the keys (`LevelVisualState.patch_level_dict()` for visual settings)
3. The table's live edit log, when the map has a document: the joiner's `LiveEdits` asks for
   it as its map is installed, and applies it at once when its last op is in (see
   [Live map edits](#live-map-edits))
4. Full game state (all tokens, avatars, permissions and drag locks), held by the host until
   the client reports its table loaded, then sent behind any live edit messages still queued
   (`NetworkGameSync.after_live_edits()`), so the tokens land on the edited ground

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
  `AssetStreamer.level_map_file_for_request(asset_id, variant_id, servable_folders)`: the
  requested folder must sanitize to the level on the table or to a map on the session's shelf
  (`SessionChannel.servable_folders()`, checked with `is_level_request_authorized`), and the
  variant must be `"map"` (map.glb) or `"ttmap"` (map.ttmap)
  (`Paths.get_level_map_file_for_variant`). Anything else, any other saved level included, is
  answered with `_rpc_asset_not_found`; neither client-controlled value ever becomes a path.
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
  is served once the head's transfers finish or it disconnects, except that a peer with a
  table transfer goes before peers with only prefetches (see "Prefetch" under Sessions). A
  file several peers ask for is sent to each in turn. For the served peer, `AssetStreamer` keeps at most
  `SEND_WINDOW_BYTES` (256 KB) of chunks unacknowledged, shared across its transfers
  (`StreamSendWindow`, `utils/stream_send_window.gd`); the client acks the unbroken run
  of chunks it holds, and the host only moves an ack forward. A served peer that acks
  nothing new for `STALL_TIMEOUT_MS` (10 s) is logged and moved to the back of the queue,
  its transfers rewound to the last ack so its next turn resumes from there (wherever it stood
  in the queue); acks from a waiting peer send nothing. The window exists because `SteamMultiplayerPeer` silently
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
only there. Prefetch is covered by `test_asset_streamer_prefetch.gd` (the table first across
peers and within one, promotion at set out, slots, take-over, cancel, reuse at set out) and
`test_session_prefetch.gd` (order, percent, reports, cancel on unshelve, failure), and between
real peers by the ENet scenario `enet_prefetch`.

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

Headless processes on 127.0.0.1 run the whole game over `ENetMultiplayerPeer` (the scenario
sets NetworkManager's peer and state the way the Steam lobby callbacks would), on the shipped
res:// map, so nothing downloads and no second Steam account is needed. One launcher runs any
scenario, with one command form (allowlist it once):

`godot --headless --path D:/dev/tt-sim res://tests/net/net_launcher.tscn -- --data-root=net_launcher --scenario=<name> [--peers=2] [--timeout-s=180] [--port=28471]`

It starts `tests/net/<name>.tscn` as N peer processes (`host`, `client`, then `client2`...),
waits for them, kills any still running 30 s past the timeout, and exits 0 only when every
peer exited 0 with a passing `NET_RESULT {json}` line and the real user's data is untouched.
It prints each peer's `NET_RESULT` and a final `NET_LAUNCH {json}` line. Logs stay in
`.godot/net_runs/<name>/` until the next run of that scenario: `<role>.log` (the scenario's
log), `<role>.godot.log` (the engine's, through `--log-file`) and the `rv.*` rendezvous files.

The processes never share `user://` stores. Each peer starts with `--data-root=net_<name>_<role>`
and the launcher with its own `--data-root` (it refuses to start peers without one), so
`Paths` puts every per-user store of that process (levels, settings, the asset cache and its
index, user asset packs, avatars, updates, perf logs, the warm-up marker) under
`user://_test_roots/<root>/` instead of where the shipped game keeps it. Before this, local
clients wrote one shared asset cache index at once and each evicted a real cached model to fit
its download. The launcher also records the modification time of every file in the shipped
stores (`Paths.store_paths("user://")` and the import source index, `user://import_sources.cfg`)
before the peers start, and it deletes every test root of the run at the end, pass or fail. A
GUT run gets such a root without an argument (`Paths.gut_data_root`, see `AGENTS.md` "Running
tests from the CLI").

The run fails on what a test peer must never do, and on nothing else: a file that existed
before the run was modified or deleted (`shipped_files_changed` lists each as `modified <path>`
or `deleted <path>`), or a new file or folder appeared under a store only a misdirected peer
writes, the asset cache and its index, `user_assets/` and `updates/` (listed as `added
<path>`). Every other new file or folder is information: `shipped_files_added` counts them and
`shipped_files_added_sample` lists the first ten, and the launcher prints a line when there are
any. That is deliberate. Other sessions' render jobs create and delete their own `_<task>_`
level folders in the real `user://levels/` while a launch runs (`_biglf_*`, `_ui_tour_room`,
`_p4*`), and used to fail every run that overlapped one although every peer passed; `levels/`,
`avatars/`, `perf_logs/`, `settings.cfg` and the import index are written by such jobs too, so a
new file there says nothing about the peers. What still fails a run without a peer being at
fault is another session modifying or deleting a file that already existed, such as a job
re-saving a level that was there before the launch or rewriting `import_sources.cfg`: the
`shipped_files_changed` paths say whose it is, and a re-run settles it. The snapshot stats the
files on the worker threads (about 31,600 files in 0.6 s with the listing, against 3.0 s one at
a time, taken before and again after the peers; `shipped_snapshot_ms` in the report). The
comparison is `compare_snapshots()` in `tests/net/net_launcher.gd`, covered by
`tests/unit/test_net_launcher_store_check.gd`.

A scenario is a scene whose script reads `--role`, `--rendezvous` (an absolute path prefix
for the files the roles coordinate through), `--out`, `--timeout-s` and `--port`, writes its
log and one `NET_RESULT {json}` line to `--out` and quits 0 on a pass; extending
`enet_late_joiner.gd` gives the boot, ENet setup and rendezvous.

- `enet_late_joiner`: the client joins after the host placed an avatar and must see it once
  its table has loaded (`LateJoinerSync`'s hold).
- `enet_game_sync`: after that late join, the client moves a token it was given CONTROL of
  (drag-lock claim, transform, release) and receives its resting position; the host renames
  it, removes a second token and changes the light intensity. Both logs show each message
  arriving with the right sender, and the host's copy of the token locked through
  `grant_drag_lock()` and unlocked through `release_drag_lock()`.
- `enet_leave_mid_drag`: the client claims the drag lock on a token it controls, sends a
  transform and leaves (`disconnect_game()`) without releasing it. After `player_left` the
  host's lock is free, `drag_lock_released` fired on the host, its copy of the token is
  unlocked with dragging allowed, and a GM drag claims and releases the lock. With the old
  leave path the host's copy stayed locked to the departed peer (`host_token_unlocked_ok` and
  `host_drag_allowed_ok` false).

- `enet_session_room` (`--peers=5 --timeout-s=420`): the session room, its party and the
  table moves (TableMover). Each client reports its role as its session key. Table A is a flat
  authored map the host builds in its own test root (the clients download its `map.ttmap`);
  table B is the shipped map under a level folder of its own. client and client2 join at the
  start and land in the room; the host sets table A out from the shelf (`Root.set_out`), places
  Hero A (granted to client, so it leaves A's placements) and Bystander A (nobody's), raises the
  ground with the play-side editor (one live edit) and moves Bystander A; table A then counts as
  changed in tokens and terrain, not look. The host moves the table to the room
  (`TableMover.move_now`, Keep: A's state is kept with Bystander A and one op, without Hero A;
  host and clients check no tokens, nothing served, the session open with no table; the
  party is Hero A, owned by `enet-client`), client3 joins in the room, and the host sets out
  table B. On table B Hero A is back under its network id, grounded (within 5 cm of where a
  drop there lands), controlled by client only, and absent from the placements a save of table
  B writes (the host saves and reloads it once Hero B has landed); Bystander A stayed behind.
  The shelf ends as both folders and the pointer on table B. Every client keeps its peer id with
  no offline event; the host keeps one peer object and room code. client then leaves the way the
  pause menu does, with no "connection lost" dialog (the host keeps its entry with no peer and
  its grant by session id), rejoins through the join screen with a new peer id, lands at table
  B and controls Hero A again. Table B, saved and with the party not counted, is unchanged, so
  the drawer's Move the table here (`Root.move_table`) asks nothing and counts down; client,
  client2 and client3 get the notice ("Moving the table to Session table A"), and on table A
  every peer has Bystander A where it was moved (0.0 m off), the ground at the raise as high as
  the host's (0.599 m, from 0.0) and one op in its live edits' log; client4 joins there as a
  late joiner and gets the same, without ever seeing the room. The host ends with five session
  players. Passed on 2026-10-10 in about 8.9 s on the host.
- `enet_live_edits` (`--peers=3 --timeout-s=300`): live map edits (see "Live map edits"
  below). The host builds a 120 ft authored level (forest west of a river, a plank bridge) in
  its own test root before it opens the room, so both clients download its `map.ttmap`. With
  client at the table, the host stands Scout where the raise will go and runs six ops as the
  GM's Events pane does: the sculpt raise, a forest clear (Thin with Ctrl) and a sculpt lower
  are strokes of GameMap's play brush armed by `PlayEvents.pick` and driven over the board,
  a forest fall and a bridge collapse are terrain events (`TerrainEvents.start`: the event
  travels, both boards play it, then its labelled op), and the undo of the lower (a height
  op's before side) is `PlayEvents.undo`, Ctrl+Z's path. client's `MapFingerprint` equals the
  host's after each, and its Scout stands where the host's does (the host's `LiveEditGround`
  set it down on the raised ground and sent it); client played both events. The host drops
  Hero onto the raised ground; client2 then joins at the table, downloads the original map,
  takes the log (six ops, no motion) and matches the host's final fingerprint, with Hero and
  Scout resting on its own ground at the host's heights. Passed on 2026-10-10 in about 20.8 s
  on the host (Scout 0.041 m before the raise, 0.294 m after on every peer; Hero 0.628 m;
  client events_played 2; no shipped file changed).
- `enet_prefetch` (`--peers=4 --timeout-s=240`): prefetch from the room (see "Prefetch"
  under Sessions). The host builds Fen (the shipped GLB copied into a folder of its own, 20.5
  MB), Mill and Pond (flat authored maps) and Secret (never shelved) in its own test root.
  client and client2 join the room; the host shelves Fen, and once both report progress on
  it, shelves Mill then Pond and selects Pond. Each client's files arrive Fen, Pond (the GM's
  pick), Mill (shelf order), and the host relays real percents (Fen 0, 1, 8, 24 ... 93 for
  one client, the other waiting at 0 for its turn). client2 asks for Secret's map file and is
  refused ("Asset not found on host"). Once the host's holdings show both clients holding
  all three, it sets Fen out: both load it with no download (`MapDownloadCoordinator` never
  starts). client3 joins at the table: its load downloads Fen (the table's map, first),
  then it fetches Pond and Mill at the table, and every client ends holding all three.
  Passed on 2026-10-10 in about 10.5 s on the host (held 3.4 s after Fen was shelved).

All three earlier ones passed through the launcher on 2026-10-09, each in about 1.4 s on the
host, with no shipped store file changed (31,435 files watched) and every test root removed;
`enet_session_room` passed the same way in about 4.9 s on the host. With the party and the
rejoin it passed on every peer later on 2026-10-09 in about 5.5 s on the host (three runs); the
launcher's store check then flagged only level folders other sessions were writing into the real
store at the time (`_biglf_*`, `_p4b3_*`), never the scenario's own, which is why new files are
now only reported. `enet_late_joiner` through the launcher with that change: `pass:true`,
`shipped_files_changed:[]`, and the other session's new level folder
(`user://levels/_biglf_lakeshore_4_320x160/`) in `shipped_files_added`.

The launcher fails a run at once (killing every peer) when a peer has not opened its scenario
log 60 s after the start (`STARTUP_S`): a scenario script that fails to parse leaves a bare scene
that never quits, and its `<role>.godot.log` holds the parse error. Scenario scripts are not
loaded by `--quit-after 1`, so a parse error there only shows up this way.

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

### SessionChannel

`NetworkManager.session`, node `/root/NetworkManager/Session`, `autoloads/session_channel.gd`.
The model is in [Sessions](#sessions-the-room-and-the-table).

```gdscript
# Every peer (clients read the host's summary)
func is_open() -> bool                    # in the room
func get_table() -> String                # ref_key of the map on the table, "" in the room
func get_shelf() -> Array[Dictionary]     # MapRefs {"folder", "map_path", "hashes", "name"}
func get_players() -> Dictionary          # session id -> {"name", "peer_id"}
func get_holdings() -> Dictionary         # session id -> ref keys of the shelf maps it holds
func get_selected() -> String             # the GM's selected shelf map, fetched after the table's
func summary() -> Dictionary              # {"open", "table", "shelf", "players", "holdings",
                                          #  "selected", "progress"}
func peer_for(session_id: String) -> int
func session_id_of(peer_id: int) -> String
static func holds_map(ref: Dictionary, cached_file: Callable) -> bool
static func missing_variants(ref: Dictionary, cached_file: Callable) -> Array  # files to fetch
signal room_opened                        # client: the host opened the room
signal session_changed                    # shelf, table pointer, players or holdings changed
func report_holdings() -> void            # client: after a summary, in the room, a fetch done

# Host
func open() -> void                       # Return everyone to the room
func close() -> void                      # just before game_starting
func shelve(level_dict: Dictionary) -> String         # the room's Add a map; returns its key
func unshelve(key: String) -> bool        # off the shelf (never the table's); stops its transfers
func select_map(key: String) -> void      # the GM's selection (RoomPanel.select)
func servable_folders() -> Array          # the whitelist: the table's folder and the shelf's
func note_table_out(level_dict: Dictionary) -> void   # from broadcast_level_data()
func note_holdings(session_id: String, keys: Variant) -> void  # a client's report, shelf keys only
func admit_peer(peer_id: int, reported: Dictionary = {}) -> StringName
                                          # from _rpc_send_player_info() with the reported info;
                                          # restores a returning player's grants; &"room" or &"table"
var party: SessionParty
var prefetch: SessionPrefetch
```

### SessionPrefetch

`NetworkManager.session.prefetch`, node `/root/NetworkManager/Session/Prefetch`,
`autoloads/session_prefetch.gd`. The model is in
[Sessions](#sessions-the-room-and-the-table) ("Prefetch").

```gdscript
# Every peer
func get_progress() -> Dictionary         # session id -> {ref key: percent}, 0 while waiting
signal progress_changed                   # a player's progress changed (RoomPanel.show_progress)

# Client
func step(shelf: Array, table: String, selected: String) -> void  # on every summary (deferred)
func current_key() -> String              # the map being fetched, or ""

# Host
func note_progress(session_id: String, raw: Variant, shelf_keys: Array) -> void

# Pure
static func order(shelf: Array, table: String, selected: String) -> Array[Dictionary]
static func map_percent(files: Array) -> int  # by bytes, 0 until every size is known, at most 99
```

### SessionParty

`NetworkManager.session.party`, node `/root/NetworkManager/Session/Party`,
`autoloads/session_party.gd`. Host only. The model is in
[Sessions](#sessions-the-room-and-the-table) ("The party").

```gdscript
func attach(controller: LevelPlayController) -> void  # Root, once: the table the party lands on
func get_grants() -> Dictionary           # session id -> network ids it controls
func owners_of(network_id: String) -> Array[String]
func get_members() -> Array[Dictionary]   # between tables: {"state": TokenState dict, "owners"}
func take() -> int                        # before a table goes
func set_out() -> int                     # once the next map has loaded
func restore_grants(session_id: String, peer_id: int) -> int   # from admit_peer()
func revoke_all(network_id: String) -> void                    # the GM's Revoke control
static func members_of(states: Dictionary, grants: Dictionary) -> Array[Dictionary]
static func landing_spots(centre: Vector3, count: int, spacing := SPACING_M) -> Array[Vector3]
static func landing_point(level: LevelData, game_map: GameMap) -> Vector3   # spawn point, else camera
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
func release_drag_lock(network_id: String, peer_id: int) -> bool
func broadcast_live_edit(table_key: int, index: int, bytes: PackedByteArray) -> void
func send_live_edit_log(peer_id: int, table_key: int, ops: Array[PackedByteArray]) -> void  # 0: every client
func after_live_edits(then: Callable) -> void   # behind every live edit message queued
func live_edits_waiting() -> int
func broadcast_terrain_event(bytes: PackedByteArray) -> void  # TerrainEvent.encode, through the outbox
```

`NetworkStateSync` decides when the token sends go out (throttling, batching, keeping
`GameState` in step); call it, not these, for token updates.

`grant_drag_lock()` is the one place the host hands out a drag lock, both to itself (peer 1,
from `DraggableToken` when the GM starts a drag) and to a client whose claim passed its CONTROL
check (`NetworkTokenSync`). It claims the lock in `GameState`, emits `drag_lock_granted` on the
host as well (so the host's copy of the token locks through the same listener as every
client's), and broadcasts the grant. It returns false, sending nothing, when another peer holds
the lock; the claim path then sends `send_drag_lock_denied()`.

`release_drag_lock()` is its mirror and the one place a lock is freed: the GM's drop (peer 1,
`DraggableToken`), a client's release (`NetworkTokenSync`, which then snaps the host's copy to
the last received position and broadcasts it), and a client that left mid-drag
(`TokenPermissionHandler` on `player_left`, for every lock `GameState.get_drag_locks_held_by()`
lists). It releases the lock in `GameState`, emits `drag_lock_released` on the host as well, so
the host's copy unlocks through the same listener as every client's, and broadcasts the release.
It returns false, sending nothing, unless the given peer holds the lock. Before it, the
leave path cleared `GameState` and told the clients but left the host's copy locked to the
departed peer, so the GM could not drag that token again.

#### Client Methods

```gdscript
func send_client_token_transform(network_id: String, pos: Vector3, rot: Vector3, scl: Vector3) -> void
func send_drag_lock_claim(network_id: String) -> void
func send_drag_lock_release(network_id: String) -> void
func request_live_edit_log() -> void
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
signal live_edit_received(table_key, index, bytes)   # one op, whole, not yet checked
signal live_edit_log_received(table_key, count)      # a log header; `count` ops follow
signal terrain_event_received(bytes)                 # 32 bytes, not yet decoded

# Every peer: the host's own grant_drag_lock() emits it too
signal drag_lock_granted(network_id, locker_peer_id)

# Host, from a client (sender from the transport)
signal client_token_transform_received(sender_id, network_id, position, rotation, scale)
signal client_drag_lock_claimed(sender_id, network_id)
signal client_drag_lock_released(sender_id, network_id)
signal live_edit_log_requested(sender_id)            # rate-limited, players only
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
| `_rpc_live_edit_chunk` | host -> clients or one client | reliable, paced by the outbox (`LIVE_EDIT_BYTES_PER_SECOND`, 512 KB/s); reassembled, capped at `LiveEditCodec.MAX_BYTES` | `live_edit_received` once an op is whole |
| `_rpc_live_edit_log` | host -> clients or one client | reliable, in the outbox's order | `live_edit_log_received` |
| `_rpc_request_live_edit_log` | client -> host | reliable, one answered per `LIVE_EDIT_LOG_REQUEST_INTERVAL` (2 s) a player | `live_edit_log_requested` |
| `_rpc_terrain_event` | host -> clients | reliable, in the outbox's order; authority-only, a host ignores it, any length but `TerrainEvent.EVENT_BYTES` (32) is dropped | `terrain_event_received` |

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

#### Live map edits

The GM changes the map during play with the authoring brushes (sculpt, paint, biome, clear,
water, crossings, props; a bridge collapsing, a forest falling, fire) and every peer, a late
joiner included, ends with the same map. The ops and their checks are
[systems/authoring.md](systems/authoring.md) "Live edits"; this is their transport.

- **One service a table, every peer** (`LiveEdits`, `scenes/states/playing/live_edits.gd`):
  `LevelPlayController.start_live_edits()` makes it once a map built from a map document is
  installed (`LevelPlayLoader._finalize_map_loading`, the download path too) and frees it
  with the map, so the log clears when the table changes. A map with no document (a Blender
  map played as it is) gets none: `LevelPlayController.live_edits` is null and
  `LiveEdits.refusal(null)` says why. Play loads a document's map with its props apart
  (`MapSourceLoader.keep_props_apart`) on every peer so the play-side editor can edit it.
- **Only the host sends.** The GM's side records into `LiveEdits.history`; each entry
  recorded, undone or redone becomes one op once the editor's height work has drained, is
  appended to `LiveEdits.op_log` (a plain `Array[PackedByteArray]`, the table's events for a
  session file) and goes out through `broadcast_live_edit()`. The chunk and header RPCs are
  authority-only; clients only receive.
- **Order.** Every live edit message (chunks of at most `LiveEditCodec.CHUNK_BYTES`, 64 KB;
  log headers; `after_live_edits()` callbacks) leaves through one outbox, in order, at most
  512 KB a second (a broadcast counted once): Steam drops reliable messages past about 512 KB
  queued. A client reassembles each op (`LiveEditCodec.Assembler`: parts in order, at most
  `MAX_CHUNKS`, at most `MAX_BYTES`, 4 MB) and its `LiveEdits` applies ops in index order
  through a `LiveEditCodec.Queue` stepped once a frame.
- **Catching up.** A client's `LiveEdits` calls `request_live_edit_log()` as soon as it exists;
  the host answers with `send_live_edit_log()`: a header (the table key, a random number drawn
  when the host's service starts, and the op count) and every op so far. A service takes ops
  only of the table whose header it has and only at the next index, so ops broadcast before
  the header or twice are dropped and the log fills the gap. When the catch-up's last op is
  in, the queue applies it all at once (`Queue.drain()`). A host whose service starts after a
  client's announces its header to every client (`send_live_edit_log(0, ...)`). A client with a
  level queued behind the one loading starts no service for the doomed table.
- **Late joiners.** `LateJoinerSync.sync_peer` sends the full state through
  `after_live_edits()`, behind the catch-up the joiner's service asked for while its map was
  installing (before its load completed and it reported), so the joiner's ground is edited
  before its tokens are placed. A joiner that downloads the map reports before the map is in;
  it gets the state first and the log once the map arrives, and its tokens (host positions,
  no gravity) stand on the edited ground once the catch-up drains.
- **Hostile bytes.** `LiveEditCodec.decode` checks every op against the receiver's document
  and palette; a refused op stops that table taking any more (`LiveEdits.problem`, one
  warning), so a misbehaving host cannot make a client print an engine error for every op.
  A request for the log is answered at most once in two seconds a player, since the answer
  can be megabytes.
- **Tokens follow the ground.** Once the edits so far have settled on a peer (sent or applied,
  the terrain's chunks rebuilt, two physics frames on), its `LiveEditGround` (a child of the
  service) refits the view to the ground. On the host it also sets every token down on the
  ground as it is now (`TokenGrounding`) and sends each one that moved with
  `NetworkStateSync.broadcast_token_properties` (reliable, GameState kept in step), so a token
  on raised ground stands on it on every peer and one on a bridge that went sits in the water.
  Clients take the host's positions and never re-ground on their own.
- **Terrain events** (a bridge collapsing, a forest falling; `TerrainEvents`, a child of the
  service). An event is not document state: the host sends its few parameters (`TerrainEvent`,
  32 bytes: version, kind, crossing id, table key, centre, radius, duration, lead, seed) with
  `broadcast_terrain_event()` through the same outbox, so it never overtakes an op queued
  before it (the crossing it takes down is on the client when it arrives). Every peer plays
  the motion from the event alone. There is no shared clock: the host waits the event's lead
  (`TerrainEvent.LEAD_S`, 0.1 s, a typical hop; 0 in solo play) before it plays, a client plays
  on receipt. Once the motion has played, the host makes the change it ends in on its live
  editor as one ordinary history entry (the crossing removed, or a Clear over the area), which
  goes out as an op; it reaches a client after the client's motion when latency is near the
  lead. A client takes an event only through `TerrainEvent.decode` (wrong length or version,
  unknown kind, non-finite or out-of-range values refused), only for its own table key and
  only while its service takes ops, and drops anything else without a word. A late joiner
  never sees the motion: it gets the op in its catch-up like any other.
- **Saving.** Live edits change the session's copy of the map (the loaded document and
  nodes), never `map.ttmap`.

The GM's UI is the Events pane (`PlayEvents`, [systems/authoring.md](systems/authoring.md)
"Live edits"). ENet scenario: `tests/net/enet_live_edits` (three peers: the host builds an
authored level in its test root and changes it through the play brush and two terrain events,
a client follows six ops with an equal `MapFingerprint` and a re-grounded token after each and
plays both events, a late joiner downloads
the original map, catches up and matches, its tokens resting on the raised ground at the
host's heights).

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
func get_drag_locks_held_by(peer_id: int) -> Array[String]
func clear_drag_locks_for_peer(peer_id: int) -> void
```

These change `GameState` only. Table play frees locks through
`NetworkGameSync.release_drag_lock()`, which also unlocks the token copies.

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

`LobbyClient._on_connection_failed()` shows `"Connection failed: <reason>"` in the join
form's status label. While hosting is starting from the title, `Root` shows the reason as an
error toast (`UIManager.show_error`) and stays on the title. Once in `ROOM` or `PLAYING`, a
client's drop shows `Root`'s generic "Disconnected" dialog instead, which does not include the
reason.

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
