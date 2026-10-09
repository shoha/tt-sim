class_name StreamSendWindow

## Window arithmetic for AssetStreamer's ack-based flow control.
##
## A transfer is a byte buffer cut into fixed-size chunks. The host has sent every chunk
## before `next_chunk` and the client has acknowledged every chunk before `acked_chunks`;
## the bytes between the two are in flight. The host sends more only while the bytes in
## flight to a peer stay within the window, so the transport's send buffer never fills
## (SteamMultiplayerPeer drops reliable messages silently when it does). Pure and static
## so the arithmetic is tested without a network.


## Chunks needed to carry `data_size` bytes.
static func chunk_count(data_size: int, chunk_size: int) -> int:
	if data_size <= 0 or chunk_size <= 0:
		return 0
	return ceili(float(data_size) / chunk_size)


## Bytes sent but not yet acknowledged: the chunks from `acked_chunks` up to `next_chunk`,
## the last of which may be short.
static func bytes_in_flight(
	next_chunk: int, acked_chunks: int, data_size: int, chunk_size: int
) -> int:
	var sent_end := mini(next_chunk * chunk_size, data_size)
	var acked_end := mini(acked_chunks * chunk_size, data_size)
	return maxi(sent_end - acked_end, 0)


## How many more chunks may be sent now, with `in_flight_bytes` already unacknowledged
## and `remaining_chunks` left to send. Counts every chunk at full size. A peer with
## nothing in flight always gets one chunk, so a window smaller than a chunk still
## makes progress.
static func chunks_to_send(
	in_flight_bytes: int, window_bytes: int, chunk_size: int, remaining_chunks: int
) -> int:
	if remaining_chunks <= 0 or chunk_size <= 0:
		return 0
	var room := maxi(window_bytes - in_flight_bytes, 0) / chunk_size
	if in_flight_bytes <= 0:
		room = maxi(room, 1)
	return mini(room, remaining_chunks)
