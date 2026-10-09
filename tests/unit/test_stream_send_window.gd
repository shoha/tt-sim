extends GutTest

## StreamSendWindow: the window arithmetic behind AssetStreamer's flow control.

const CHUNK := 32768
const WINDOW := 256 * 1024


func test_chunk_count_rounds_up() -> void:
	assert_eq(StreamSendWindow.chunk_count(0, CHUNK), 0)
	assert_eq(StreamSendWindow.chunk_count(1, CHUNK), 1)
	assert_eq(StreamSendWindow.chunk_count(CHUNK, CHUNK), 1)
	assert_eq(StreamSendWindow.chunk_count(CHUNK + 1, CHUNK), 2)


func test_bytes_in_flight_counts_sent_minus_acked() -> void:
	var size := 10 * CHUNK
	assert_eq(StreamSendWindow.bytes_in_flight(0, 0, size, CHUNK), 0)
	assert_eq(StreamSendWindow.bytes_in_flight(5, 2, size, CHUNK), 3 * CHUNK)
	assert_eq(StreamSendWindow.bytes_in_flight(5, 5, size, CHUNK), 0)


func test_bytes_in_flight_uses_the_short_last_chunk() -> void:
	var size := 3 * CHUNK + 100
	assert_eq(StreamSendWindow.bytes_in_flight(4, 3, size, CHUNK), 100)
	assert_eq(StreamSendWindow.bytes_in_flight(4, 0, size, CHUNK), size)


func test_an_empty_window_fills_to_its_size() -> void:
	assert_eq(StreamSendWindow.chunks_to_send(0, WINDOW, CHUNK, 100), WINDOW / CHUNK)


func test_a_full_window_sends_nothing() -> void:
	assert_eq(StreamSendWindow.chunks_to_send(WINDOW, WINDOW, CHUNK, 100), 0)
	assert_eq(StreamSendWindow.chunks_to_send(WINDOW + CHUNK, WINDOW, CHUNK, 100), 0)


func test_a_partly_full_window_sends_whole_chunks_only() -> void:
	assert_eq(StreamSendWindow.chunks_to_send(WINDOW - CHUNK, WINDOW, CHUNK, 100), 1)
	assert_eq(StreamSendWindow.chunks_to_send(WINDOW - CHUNK + 1, WINDOW, CHUNK, 100), 0)


func test_never_more_than_remain() -> void:
	assert_eq(StreamSendWindow.chunks_to_send(0, WINDOW, CHUNK, 3), 3)
	assert_eq(StreamSendWindow.chunks_to_send(0, WINDOW, CHUNK, 0), 0)


func test_a_window_smaller_than_a_chunk_still_progresses() -> void:
	assert_eq(StreamSendWindow.chunks_to_send(0, CHUNK / 2, CHUNK, 5), 1)
	assert_eq(StreamSendWindow.chunks_to_send(CHUNK, CHUNK / 2, CHUNK, 5), 0)
