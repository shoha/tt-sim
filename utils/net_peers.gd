class_name NetPeers

## Questions about the local multiplayer peer that are safe to ask during teardown.
##
## A MultiplayerAPI keeps its peer object after the transport has closed: when the host ends
## the session, a client's ENet peer is already closed when NetworkManager announces OFFLINE
## (the state change comes before it drops the peer, so listeners never see a half-cleared
## manager), and every MultiplayerAPI call that reaches the closed peer logs "The multiplayer
## instance isn't currently active". Code that may run then (state listeners, refreshes)
## asks here instead of calling get_unique_id() behind a bare null check. Static so it is
## tested without a network.


## True while `mp` has a peer that is connected or still connecting: false with no API, no
## peer, or a peer whose transport has closed. The default offline peer counts as live.
static func is_live(mp: MultiplayerAPI) -> bool:
	if mp == null or mp.multiplayer_peer == null:
		return false
	var status := mp.multiplayer_peer.get_connection_status()
	return status != MultiplayerPeer.CONNECTION_DISCONNECTED


## The local peer's id while `mp` is live (is_live()), else `fallback`. Offline (the default
## offline peer) it is 1, as the server's.
static func local_id(mp: MultiplayerAPI, fallback: int = 0) -> int:
	return mp.get_unique_id() if is_live(mp) else fallback
