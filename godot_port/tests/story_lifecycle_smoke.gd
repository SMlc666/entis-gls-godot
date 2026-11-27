extends SceneTree

const TestSupport = preload("res://tests/test_support.gd")

const STORY_SCENARIO := "00_Z000"
const SESSION_COUNT := 3


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game_dir := TestSupport.resolve_game_dir(OS.get_cmdline_user_args())
	if game_dir.is_empty():
		printerr("FAIL Pass the original game directory after --")
		quit(2)
		return
	var csx_path := game_dir.path_join("system/yosuga.csx")
	var noa_path := game_dir.path_join("data1.noa")
	var original_hashes := [FileAccess.get_sha256(csx_path), FileAccess.get_sha256(noa_path)]
	for session_index in range(SESSION_COUNT):
		if not await _run_story_session(game_dir, session_index):
			quit(1)
			return
		print("Completed and drained Story session %d/%d" % [session_index + 1, SESSION_COUNT])
	if [FileAccess.get_sha256(csx_path), FileAccess.get_sha256(noa_path)] != original_hashes:
		printerr("FAIL Original CSX or data1.noa changed during lifecycle smoke")
		quit(1)
		return
	print("PASS %d original-CSX Story sessions initialized, waited for input, and shut down cleanly; source hashes unchanged" % SESSION_COUNT)
	quit(0)


func _run_story_session(game_dir: String, session_index: int) -> bool:
	var scene := load("res://scenes/adv_player.tscn") as PackedScene
	if scene == null:
		printerr("FAIL ADV scene failed to load")
		return false
	var player: Variant = scene.instantiate()
	var save_dir: String = TestSupport.configure_player_saves(player, "story_lifecycle_%d" % session_index)
	player.set("game_dir", game_dir)
	player.set("start_in_title", false)
	player.set("start_scenario", STORY_SCENARIO)
	root.add_child(player)
	for _frame in range(600):
		if player.get("is_initialized") and player.get("host") != null and player.get("vm") != null:
			break
		await process_frame
	if not player.get("is_initialized") or not TestSupport.uses_isolated_saves(player.get("host"), save_dir):
		printerr("FAIL Story session %d did not initialize with isolated saves" % session_index)
		await _dispose_player(player, save_dir)
		return false
	var reached_input_wait := false
	for _frame in range(600):
		await process_frame
		var host: Variant = player.get("host")
		if host != null and host.is_waiting_input:
			reached_input_wait = true
			break
	if not reached_input_wait:
		printerr("FAIL Original ScenarioLoop did not reach its first input wait in session %d" % session_index)
		await _dispose_player(player, save_dir)
		return false
	await _dispose_player(player, save_dir)
	return true


func _dispose_player(player: Variant, save_dir: String) -> void:
	if is_instance_valid(player):
		if player.has_method("_shutdown_runtime_session"):
			player.call("_shutdown_runtime_session")
		if not bool(player.get("runtime_shutdown")):
			printerr("FAIL AdvPlayer runtime shutdown hook did not complete")
		player.free()
		await process_frame
		# WAV playbacks are released asynchronously by AudioServer; drain before process-exit leak checks.
		await create_timer(0.25).timeout
	TestSupport.remove_test_saves(save_dir)
