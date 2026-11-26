extends SceneTree

const Queue = preload("res://scripts/host_command_queue.gd")


func _initialize() -> void:
	var queue = Queue.new(2)
	var scope := queue.begin_scope("title")
	var first := queue.enqueue({"id": "ID_START"}, scope)
	var second := queue.enqueue({"id": "ID_CONFIG"}, scope)
	if first <= 0 or second <= first:
		_fail("Accepted commands must receive monotonically increasing sequences")
		return
	if queue.enqueue({"id": "ID_EXIT"}, scope) != -1 or queue.pending_count != 2:
		_fail("Queue capacity must reject overflow without growing")
		return
	var preview: Dictionary = queue.peek(scope)
	preview["id"] = "MUTATED"
	if queue.peek(scope).get("id") != "ID_START":
		_fail("Peek must not expose mutable internal queue data")
		return
	var event: Dictionary = queue.pop(scope)
	if event.get("id") != "ID_START" or event.get("sequence") != first:
		_fail("Commands must dequeue in FIFO order with metadata")
		return
	if queue.pop(scope).get("id") != "ID_CONFIG" or queue.pending_count != 0:
		_fail("Second command must remain queued until consumed")
		return
	var accepted_before_scope_change := queue.enqueue({"id": "OLD_PAGE"}, scope)
	if accepted_before_scope_change <= 0:
		_fail("Current scope should accept commands")
		return
	var next_scope := queue.begin_scope("story")
	if next_scope == scope or queue.pending_count != 0:
		_fail("Beginning a scope must invalidate old queued commands")
		return
	if queue.enqueue({"id": "STALE"}, scope) != -1:
		_fail("An event carrying an old scope token must be rejected")
		return
	var current_sequence := queue.enqueue({"id": "CURRENT"}, next_scope)
	if current_sequence <= accepted_before_scope_change:
		_fail("Event sequence must remain monotonic across scope changes")
		return
	if not queue.flush(next_scope) or queue.pending_count != 0 or queue.scope_generation != next_scope:
		_fail("Flush must clear commands without changing the current scope")
		return
	if queue.enqueue({"id": "WRONG_SCOPE"}, scope) != -1:
		_fail("A stale scope token must stay invalid after flush")
		return
	queue.shutdown()
	if not queue.closed or queue.pending_count != 0 or queue.enqueue({"id": "AFTER_CLOSE"}) != -1:
		_fail("Shutdown must clear and permanently close the queue")
		return
	if queue.begin_scope("restart") != -1:
		_fail("A shut down queue must not start another scope")
		return
	var window_queue = Queue.new(8)
	var window_scope := window_queue.begin_scope("multi-window")
	window_queue.enqueue({"id": "W10_FIRST"}, window_scope, 10)
	window_queue.enqueue({"id": "LEGACY_UNBOUND"}, window_scope)
	window_queue.enqueue({"id": "W20_FIRST"}, window_scope, 20)
	window_queue.enqueue({"id": "W10_SECOND"}, window_scope, 10)
	var w20_event: Dictionary = window_queue.pop_for_window(20, window_scope)
	if w20_event.get("id") != "LEGACY_UNBOUND":
		_fail("A window must accept the earliest legacy unbound command")
		return
	w20_event = window_queue.pop_for_window(20, window_scope)
	if w20_event.get("id") != "W20_FIRST":
		_fail("A window must consume its own event while preserving others")
		return
	if window_queue.pop_for_window(10, window_scope).get("id") != "W10_FIRST":
		_fail("Other-window events must not disturb FIFO order for this window")
		return
	if window_queue.pop_for_window(10, window_scope).get("id") != "W10_SECOND":
		_fail("All events for a window must remain available in order")
		return
	window_queue.enqueue({"id": "W10_DROP_A"}, window_scope, 10)
	window_queue.enqueue({"id": "W20_KEEP"}, window_scope, 20)
	window_queue.enqueue({"id": "LEGACY_KEEP"}, window_scope)
	window_queue.enqueue({"id": "W10_DROP_B"}, window_scope, 10)
	if window_queue.flush_window(10, window_scope) != 2:
		_fail("flush_window must remove only commands owned by that window")
		return
	if window_queue.pending_count != 2 or window_queue.pop_for_window(20, window_scope).get("id") != "W20_KEEP":
		_fail("flush_window must preserve the other window's event")
		return
	if window_queue.pop_for_window(20, window_scope).get("id") != "LEGACY_KEEP":
		_fail("flush_window must preserve legacy unbound events")
		return
	window_queue.enqueue({"id": "SPRITE_DROP_A", "source_sprite_id": 9001}, window_scope, 10)
	window_queue.enqueue({"id": "SPRITE_KEEP", "source_sprite_id": 9002}, window_scope, 10)
	window_queue.enqueue({"id": "SPRITE_DROP_B", "source_sprite_id": 9001}, window_scope, 20)
	if window_queue.flush_source_sprite(9001, window_scope) != 2:
		_fail("Detaching a sprite must invalidate its queued events")
		return
	if window_queue.pop_for_window(10, window_scope).get("source_sprite_id") != 9002:
		_fail("Sprite command invalidation must preserve other sprite events")
		return
	var coalesce_queue = Queue.new(3)
	var coalesce_scope := coalesce_queue.begin_scope("scroll")
	var button_sequence := coalesce_queue.enqueue({"id": "BUTTON_A"}, coalesce_scope, 10)
	coalesce_queue.enqueue({"id": "SCROLL", "value": 1}, coalesce_scope, 10, "volume")
	var other_window_sequence := coalesce_queue.enqueue({"id": "BUTTON_B"}, coalesce_scope, 20)
	var latest_scroll_sequence := coalesce_queue.enqueue({"id": "SCROLL", "value": 2}, coalesce_scope, 10, "volume")
	if latest_scroll_sequence <= other_window_sequence or latest_scroll_sequence <= button_sequence:
		_fail("A coalesced event must receive a fresh globally increasing sequence")
		return
	if coalesce_queue.pending_count != 3:
		_fail("Coalescing should replace the prior notification without filling the queue")
		return
	var coalesced_first: Dictionary = coalesce_queue.pop_for_window(10, coalesce_scope)
	var coalesced_latest: Dictionary = coalesce_queue.pop_for_window(10, coalesce_scope)
	if coalesced_first.get("id") != "BUTTON_A" or coalesced_latest.get("value") != 2 or coalesced_latest.get("sequence") != latest_scroll_sequence:
		_fail("Coalescing must keep ordinary FIFO and deliver only the latest keyed value")
		return
	print("PASS host command queue bounded FIFO, scope and shutdown contract")
	quit(0)


func _fail(message: String) -> void:
	printerr("FAIL ", message)
	quit(1)
