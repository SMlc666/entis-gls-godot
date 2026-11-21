extends SceneTree

const GAME_DIR := "/mnt/sdb1/devs/yzk2godot/缘之空（全cg步兵版）"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://scenes/adv_player.tscn") as PackedScene
	if scene == null:
		_fail("ADV scene failed to load")
		return
	var player := scene.instantiate()
	player.set("game_dir", GAME_DIR)
	player.set("start_in_title", true)
	root.add_child(player)
	await process_frame
	if not player.call("_start_native_mei_movie", GAME_DIR.path_join("opening.mei"), 0):
		_fail("native MEI player refused opening.mei")
		return
	var frame_info: Array = player.get("mei_movie_frames")
	if frame_info.size() != 2520:
		_fail("expected 2520 MEI video records, got %d" % frame_info.size())
		return
	var start_usec := Time.get_ticks_usec()
	var decoded_count := 1 # the initial I-frame was decoded during movie startup
	while decoded_count < frame_info.size():
		if player.get("mei_movie_queue").is_empty():
			if not player.call("_prepare_next_mei_group"):
				_fail("MEI playback stopped preparing frames at display index %d" % decoded_count)
				return
		var next: Dictionary = player.get("mei_movie_queue").pop_front()
		var index := int(next.get("index", -1))
		if index != decoded_count:
			_fail("MEI display order expected frame %d, got %d" % [decoded_count, index])
			return
		var rgba: PackedByteArray = next.get("rgba", PackedByteArray())
		if rgba.size() != 800 * 600 * 4:
			_fail("MEI frame %d has invalid RGBA size %d" % [index, rgba.size()])
			return
		decoded_count += 1
	print("PASS complete MEI stream: %d frames decoded in %.2f seconds" % [decoded_count, float(Time.get_ticks_usec() - start_usec) / 1000000.0])
	player.call("_on_movie_stop_requested")
	player.queue_free()
	await process_frame
	quit(0)


func _fail(message: String) -> void:
	printerr("FAIL %s" % message)
	quit(1)
