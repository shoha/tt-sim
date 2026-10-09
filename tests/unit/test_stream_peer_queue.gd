extends GutTest

## StreamPeerQueue: the order in which the host serves peers bulk transfers.


func test_peers_queue_in_the_order_they_ask() -> void:
	var queue := StreamPeerQueue.with_peer([], 5)
	queue = StreamPeerQueue.with_peer(queue, 9)
	queue = StreamPeerQueue.with_peer(queue, 3)
	assert_eq(queue, [5, 9, 3])
	assert_eq(StreamPeerQueue.head(queue), 5)


func test_a_waiting_peer_keeps_its_place() -> void:
	assert_eq(StreamPeerQueue.with_peer([5, 9], 5), [5, 9])


func test_removing_the_head_serves_the_next() -> void:
	var queue := StreamPeerQueue.without_peer([5, 9, 3], 5)
	assert_eq(StreamPeerQueue.head(queue), 9)
	assert_eq(StreamPeerQueue.without_peer([5, 9, 3], 9), [5, 3])


func test_an_empty_queue_has_no_head() -> void:
	assert_eq(StreamPeerQueue.head([]), 0)
	assert_eq(StreamPeerQueue.head(StreamPeerQueue.without_peer([5], 5)), 0)


func test_rotation_sends_the_head_to_the_back() -> void:
	assert_eq(StreamPeerQueue.rotated([5, 9, 3]), [9, 3, 5])
	assert_eq(StreamPeerQueue.rotated([5]), [5])
	assert_eq(StreamPeerQueue.rotated([]), [])


func test_functions_leave_their_input_alone() -> void:
	var queue := [5, 9]
	StreamPeerQueue.with_peer(queue, 3)
	StreamPeerQueue.rotated(queue)
	StreamPeerQueue.without_peer(queue, 5)
	assert_eq(queue, [5, 9])


func test_stall_after_the_timeout_only() -> void:
	assert_false(StreamPeerQueue.is_stalled(1000, 10999, 10000))
	assert_true(StreamPeerQueue.is_stalled(1000, 11000, 10000))
