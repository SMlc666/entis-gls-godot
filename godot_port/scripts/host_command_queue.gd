extends RefCounted
class_name HostCommandQueue

## Bounded queue for complete HostWindow commands. Advance/skip state is owned
## by CsxHost and is intentionally not represented here.
const DEFAULT_CAPACITY := 128

var capacity: int = DEFAULT_CAPACITY
var scope_generation: int = 0
var context_id: String = ""
var closed: bool = false

var _next_sequence: int = 1
var _entries: Array[Dictionary] = []


func _init(max_capacity: int = DEFAULT_CAPACITY) -> void:
	capacity = maxi(1, max_capacity)


var pending_count: int:
	get:
		return _entries.size()


func snapshot(expected_scope: int = -1) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if closed or not _scope_matches(expected_scope):
		return result
	for entry: Dictionary in _entries:
		result.append(entry.duplicate(true))
	return result


func begin_scope(new_context_id: String) -> int:
	## Starts a new interaction context and invalidates every queued event from
	## the previous one. Returns -1 after shutdown.
	if closed:
		return -1
	scope_generation += 1
	context_id = new_context_id
	_entries.clear()
	return scope_generation


func enqueue(
	payload: Dictionary,
	expected_scope: int = -1,
	window_id: int = -1,
	coalesce_key: String = ""
) -> int:
	## Returns the monotonic event sequence, or -1 when stale, closed, invalid,
	## or at capacity. An omitted scope token means a synchronous producer in
	## the current context. Asynchronous callbacks must capture and pass the
	## scope token they received when they were registered.
	if closed or not (expected_scope == -1 or expected_scope == scope_generation):
		return -1
	if not coalesce_key.is_empty():
		for index in range(_entries.size() - 1, -1, -1):
			var queued: Dictionary = _entries[index]
			if int(queued.get("window_id", -1)) == window_id and str(queued.get("coalesce_key", "")) == coalesce_key:
				_entries.remove_at(index)
	if _entries.size() >= capacity:
		return -1
	var entry: Dictionary = payload.duplicate(true)
	entry["sequence"] = _next_sequence
	entry["scope_generation"] = scope_generation
	entry["context_id"] = context_id
	entry["window_id"] = window_id
	entry["coalesce_key"] = coalesce_key
	_entries.append(entry)
	var accepted_sequence := _next_sequence
	_next_sequence += 1
	return accepted_sequence


func peek(expected_scope: int = -1) -> Dictionary:
	if closed or not _scope_matches(expected_scope) or _entries.is_empty():
		return {}
	return _entries[0].duplicate(true)


func peek_for_window(window_id: int, expected_scope: int = -1) -> Dictionary:
	if closed or not _scope_matches(expected_scope):
		return {}
	for entry: Dictionary in _entries:
		var owner_window := int(entry.get("window_id", -1))
		if owner_window == window_id or owner_window == -1:
			return entry.duplicate(true)
	return {}


func peek_last_for_window(window_id: int, expected_scope: int = -1) -> Dictionary:
	if closed or not _scope_matches(expected_scope):
		return {}
	for index in range(_entries.size() - 1, -1, -1):
		var entry: Dictionary = _entries[index]
		var owner_window := int(entry.get("window_id", -1))
		if owner_window == window_id or owner_window == -1:
			return entry.duplicate(true)
	return {}


func pop(expected_scope: int = -1) -> Dictionary:
	if closed or not _scope_matches(expected_scope) or _entries.is_empty():
		return {}
	return _entries.pop_front().duplicate(true)


func pop_for_window(window_id: int, expected_scope: int = -1) -> Dictionary:
	## Returns the earliest event for this window or a legacy unbound event.
	## Events for other windows remain in place, preserving their relative order.
	if closed or not _scope_matches(expected_scope):
		return {}
	for index in _entries.size():
		var entry: Dictionary = _entries[index]
		var owner_window := int(entry.get("window_id", -1))
		if owner_window == window_id or owner_window == -1:
			return _entries.pop_at(index).duplicate(true)
	return {}


func flush(expected_scope: int = -1) -> bool:
	## Flushes pending commands without changing the interaction generation.
	if closed or not _scope_matches(expected_scope):
		return false
	_entries.clear()
	return true


func flush_window(window_id: int, expected_scope: int = -1) -> int:
	## Removes only events explicitly owned by this window. Legacy unbound and
	## other-window events remain queued. Returns the number of removed events.
	if closed or not _scope_matches(expected_scope):
		return 0
	var removed := 0
	for index in range(_entries.size() - 1, -1, -1):
		if int(_entries[index].get("window_id", -1)) == window_id:
			_entries.remove_at(index)
			removed += 1
	return removed


func flush_source_sprite(sprite_id: int, expected_scope: int = -1) -> int:
	if closed or not _scope_matches(expected_scope):
		return 0
	var removed := 0
	for index in range(_entries.size() - 1, -1, -1):
		if int(_entries[index].get("source_sprite_id", -1)) == sprite_id:
			_entries.remove_at(index)
			removed += 1
	return removed


func shutdown() -> void:
	if closed:
		return
	closed = true
	scope_generation += 1
	context_id = ""
	_entries.clear()


func _scope_matches(expected_scope: int) -> bool:
	return expected_scope == -1 or expected_scope == scope_generation
