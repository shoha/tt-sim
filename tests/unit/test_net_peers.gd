extends GutTest

## NetPeers: the local peer's id asked without touching a closed transport. When the host ends
## the session, a client's ENet peer is closed before NetworkManager announces OFFLINE, and a
## listener that called get_unique_id() on it logged "The multiplayer instance isn't currently
## active".

## A port nothing listens on; the client below never polls, so nothing is sent.
const PORT := 28499


func test_no_api_or_no_peer_is_not_live() -> void:
	assert_false(NetPeers.is_live(null))
	assert_eq(NetPeers.local_id(null, 7), 7)
	var mp := SceneMultiplayer.new()
	mp.multiplayer_peer = null
	assert_false(NetPeers.is_live(mp))
	assert_eq(NetPeers.local_id(mp), 0)


func test_the_offline_peer_is_live_as_the_server() -> void:
	var mp := SceneMultiplayer.new()
	assert_true(NetPeers.is_live(mp), "the default offline peer")
	assert_eq(NetPeers.local_id(mp), 1)


func test_a_closed_transport_is_not_live() -> void:
	var mp := SceneMultiplayer.new()
	var peer := ENetMultiplayerPeer.new()
	assert_eq(peer.create_client("127.0.0.1", PORT), OK)
	mp.multiplayer_peer = peer
	assert_true(NetPeers.is_live(mp), "connecting")
	assert_eq(NetPeers.local_id(mp), peer.get_unique_id())
	peer.close()
	assert_same(mp.multiplayer_peer, peer, "the API keeps its closed peer")
	assert_false(NetPeers.is_live(mp))
	assert_eq(NetPeers.local_id(mp), 0)
	assert_eq(NetPeers.local_id(mp, 1), 1, "the caller's fallback")
	mp.multiplayer_peer = null
