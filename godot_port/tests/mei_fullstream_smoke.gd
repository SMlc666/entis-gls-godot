extends SceneTree

const TestSupport = preload("res://tests/test_support.gd")

var player: Node = null
var test_save_dir := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game_dir := TestSupport.resolve_game_dir(OS.get_cmdline_user_args())
	if game_dir.is_empty():
		_fail("Pass the original game directory after --")
		return
	var csx_path := game_dir.path_join("system/yosuga.csx")
	var noa_path := game_dir.path_join("data1.noa")
	var mei_path := game_dir.path_join("opening.mei")
	var original_hashes := [FileAccess.get_sha256(csx_path), FileAccess.get_sha256(noa_path), FileAccess.get_sha256(mei_path)]
	var scene := load("res://scenes/adv_player.tscn") as PackedScene
	if scene == null:
		_fail("ADV scene failed to load")
		return
	player = scene.instantiate()
	test_save_dir = TestSupport.configure_player_saves(player, "mei_fullstream")
	player.set("game_dir", game_dir)
	player.set("start_in_title", true)
	root.add_child(player)
	for _frame in range(600):
		if player.get("is_initialized"):
			break
		await process_frame
	if not player.get("is_initialized") or not TestSupport.uses_isolated_saves(player.get("host"), test_save_dir):
		_fail("ADV player did not initialize with isolated test saves")
		return
	if not player.call("_start_native_mei_movie", mei_path, 0):
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
	var current_hashes := [FileAccess.get_sha256(csx_path), FileAccess.get_sha256(noa_path), FileAccess.get_sha256(mei_path)]
	if current_hashes != original_hashes:
		_fail("original CSX, NOA, or MEI changed during the read-only full-stream smoke")
		return
	print("PASS complete MEI stream: %d frames decoded in %.2f seconds; original hashes unchanged" % [decoded_count, float(Time.get_ticks_usec() - start_usec) / 1000000.0])
	player.call("_on_movie_stop_requested")
	_cleanup()
	quit(0)


func _cleanup() -> void:
	if is_instance_valid(player):
		player.free()
	player = null
	if not test_save_dir.is_empty():
		TestSupport.remove_test_saves(test_save_dir)
		test_save_dir = ""


func _fail(message: String) -> void:
	printerr("FAIL %s" % message)
	_cleanup()
	quit(1)
