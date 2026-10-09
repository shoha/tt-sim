class_name StreamPeerQueue

## The host's queue of peers waiting for bulk transfers (AssetStreamer).
##
## Steam sends each connection at its configured SendRateMin whatever the real uplink can
## carry and has no one-to-many send, so serving N clients at once would push N times that
## rate out of the host. The host therefore serves one peer at a time: the queue holds peer
## ids in the order they first asked, the head is the only peer whose chunks are sent, and
## it leaves the queue when its transfers finish or it disconnects. A head that stops
## acknowledging for the stall timeout goes to the back so one stuck peer cannot block the
## others. Pure and static so the order is tested without a network; the queue is an Array
## of peer ids and every function returns a new one.


## The queue with `peer_id` at the back, unless it is already waiting.
static func with_peer(queue: Array, peer_id: int) -> Array:
	var result := queue.duplicate()
	if not result.has(peer_id):
		result.append(peer_id)
	return result


## The queue without `peer_id`.
static func without_peer(queue: Array, peer_id: int) -> Array:
	return queue.filter(func(p): return p != peer_id)


## The queue with its head moved to the back (a stalled peer gives up its turn).
static func rotated(queue: Array) -> Array:
	if queue.size() < 2:
		return queue.duplicate()
	var result := queue.slice(1)
	result.append(queue[0])
	return result


## The peer being served, or 0 when nobody waits.
static func head(queue: Array) -> int:
	return int(queue[0]) if not queue.is_empty() else 0


## Whether the served peer has made no ack progress for `timeout_ms`.
static func is_stalled(last_progress_ms: int, now_ms: int, timeout_ms: int) -> bool:
	return now_ms - last_progress_ms >= timeout_ms
