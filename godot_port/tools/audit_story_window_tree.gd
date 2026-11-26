extends SceneTree

# Runtime audit of the original Story window tree; original game files are
# read-only. Optional --probe-bustup mutates only in-memory host/VM state.
# Usage:
# godot --headless --audio-driver Dummy --path godot_port \
#   --script res://tools/audit_story_window_tree.gd -- GAME_DIR [--probe-bustup]
#
# This tool starts the real AdvPlayer and original CSX. It may advance ordinary
# dialogue waits in the 00_Z005 pass, but it never presses a Godot choice button
# or submits a choice. Saves are redirected to an isolated user:// directory.

const CsxHostClass = preload("res://scripts/csx_host.gd")
const CsxVMReader = preload("res://scripts/csx_vm.gd")

const GAME_CLEAR_SCENARIO := "00_Z005"
const STORY_WINDOW_DATA_INDEX := 4
const FRAME_BUDGET := 2400

var latest_message_output: CsxHostClass.HostSprite = null


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var game_dir := ""
	var probe_bustup := args.has("--probe-bustup")
	for arg: String in args:
		if not arg.begins_with("--"):
			game_dir = arg
			break
	if game_dir.is_empty():
		game_dir = OS.get_environment("YOSUGA_GAME_DIR")
	if game_dir.is_empty():
		printerr("Pass the original game directory after --")
		quit(2)
		return
	var csx_path := game_dir.path_join("system/yosuga.csx")
	var data_path := game_dir.path_join("data1.noa")
	if not FileAccess.file_exists(csx_path) or not FileAccess.file_exists(data_path):
		printerr("Original game files not found under: %s" % game_dir)
		quit(2)
		return
	var csx_hash := FileAccess.get_sha256(csx_path)
	var data_hash := FileAccess.get_sha256(data_path)

	print("Original game: %s" % game_dir)
	print("Read-only tree audit: ScenarioLoop(00_Z000), then original AdvScreen::startSelect in ScenarioLoop(00_Z005)")
	var player = await _start_player(game_dir, "00_Z000", "opening")
	if player == null:
		quit(1)
		return
	_connect_observers(player)
	var reached_message_wait := await _wait_for_story_state(player)
	print("\n===== ScenarioLoop(00_Z000): first body-message wait =====")
	print("reached=%s initialized=%s vm_ip=0x%X wait_input=%s" % [
		str(reached_message_wait), str(player.is_initialized), int(player.vm.ip),
		str(player.host.is_waiting_input)
	])
	_dump_data_window(player, "00_Z000 first body wait")
	_dump_last_message_output(player, "00_Z000 first body wait")
	if probe_bustup:
		_run_bustup_host_probe(player)
	player.queue_free()
	await process_frame
	_remove_audit_saves()

	player = await _start_player(game_dir, "00_Z000", "choice")
	if player == null:
		_remove_audit_saves()
		quit(1)
		return
	_connect_observers(player)
	# Match the game's New Game Clear-state setup used by its existing choice
	# smoke, then enter the authentic ScenarioLoop(00_Z005) without selecting UI.
	var clear_result: Dictionary = player.vm.call_function_sync("OnGameClear", [], 100000)
	if not clear_result.get("ok", false):
		printerr("OnGameClear failed before 00_Z005: %s" % str(clear_result))
		player.queue_free()
		await process_frame
		_remove_audit_saves()
		quit(1)
		return
	_reset_to_scenario(player, GAME_CLEAR_SCENARIO)
	var reached_choice := await _wait_for_original_select(player)
	print("\n===== ScenarioLoop(00_Z005): original AdvScreen::startSelect =====")
	print("reached=%s initialized=%s vm_ip=0x%X wait_input=%s" % [
		str(reached_choice), str(player.is_initialized), int(player.vm.ip),
		str(player.host.is_waiting_input)
	])
	var original_select_active := _stack_contains(player.vm.call_stack, "AdvScreen::startSelect")
	print("original_startSelect_stack=%s" % str(original_select_active))
	print("Godot controls are inspection-only; no choice was submitted.")
	_dump_data_window(player, "00_Z005 selection wait")
	_dump_last_message_output(player, "00_Z005 selection wait")
	player.set_meta("audit_original_select_active", original_select_active)
	player.queue_free()
	await process_frame
	_remove_audit_saves()

	var hashes_unchanged := csx_hash == FileAccess.get_sha256(csx_path) and data_hash == FileAccess.get_sha256(data_path)
	print("\nOriginal CSX and data1.noa unchanged: %s" % str(hashes_unchanged))
	if not hashes_unchanged:
		printerr("Read-only audit detected an original game file hash change.")
		quit(1)
		return
	if not reached_message_wait:
		printerr("Timed out before the first body-message wait in 00_Z000.")
		quit(1)
		return
	if not reached_choice:
		printerr("Timed out before original AdvScreen::startSelect in 00_Z005.")
		quit(1)
		return
	if not original_select_active:
		printerr("Scenario reached a different wait; original AdvScreen::startSelect is not active.")
		quit(1)
		return
	print("PASS Story HostWindow tree audit")
	quit(0)


func _start_player(game_dir: String, scenario: String, suffix: String):
	var scene = load("res://scenes/adv_player.tscn")
	if scene == null:
		printerr("Could not load AdvPlayer scene")
		return null
	var player = scene.instantiate()
	player.game_dir = game_dir
	player.start_scenario = scenario
	player.start_in_title = false
	player.save_dir_override = "user://audit_story_window_tree/%s" % suffix
	root.add_child(player)
	for frame in range(600):
		if player.is_initialized and player.host != null and player.vm != null:
			return player
		await process_frame
	printerr("AdvPlayer did not initialize for %s" % scenario)
	player.queue_free()
	return null


func _connect_observers(player) -> void:
	latest_message_output = null
	player.host.message_output.connect(func(sprite: CsxHostClass.HostSprite) -> void:
		latest_message_output = sprite
	)


func _reset_to_scenario(player, scenario: String) -> void:
	player.is_title_mode = false
	player.native_appreciation_mode = false
	player.is_running = true
	player.host.yield_for_sprite_activation = false
	player.host.is_waiting_input = false
	player.host.begin_command_scope("story-window-audit:%s" % scenario)
	player.vm.ip = player.vm.functions["ScenarioLoop"]
	player.vm.is_halted = false
	player.vm.pending_call_args = [scenario]
	player.vm.pending_return_ip = -1
	player.vm.call_stack.clear()
	player.vm.eval_stack.clear()
	player.start_scenario = scenario


func _wait_for_story_state(player) -> bool:
	for frame in range(FRAME_BUDGET):
		await process_frame
		if player.host.is_waiting_input and latest_message_output != null and latest_message_output.message_style.get("id", "") == "ID_FONT_MESSAGE":
			return true
	return false


func _wait_for_original_select(player) -> bool:
	for frame in range(FRAME_BUDGET):
		await process_frame
		if _stack_contains(player.vm.call_stack, "AdvScreen::startSelect"):
			return true
		if player.host.is_waiting_input:
			# Advance only ordinary dialogue; original selection is identified by
			# the actual CSX call frame above, never a Godot widget flag.
			player._advance_line()
	return false


func _stack_contains(frames: Array, function_name: String) -> bool:
	for frame in frames:
		if frame != null and frame.name == function_name:
			return true
	return false


func _dump_data_window(player, label: String) -> void:
	print("-- %s --" % label)
	if player.vm.data_vars.size() <= STORY_WINDOW_DATA_INDEX:
		print("vm.data_vars[%d] missing (count=%d)" % [STORY_WINDOW_DATA_INDEX, player.vm.data_vars.size()])
		return
	var entry: Variant = player.vm.data_vars[STORY_WINDOW_DATA_INDEX]
	var value: Variant = entry.get("value", null) if entry is Dictionary else null
	print("vm.data_vars[%d].value type=%s" % [STORY_WINDOW_DATA_INDEX, type_string(typeof(value))])
	if not value is CsxHostClass.HostWindow:
		print("No HostWindow at the audited VM data slot.")
		return
	var window := value as CsxHostClass.HostWindow
	print("HostWindow id=%d roots=%d focus='%s' display=%s" % [
		window.get_instance_id(), window.root_sprites.size(), window.focused_path,
		str(window.get_display_size())
	])
	var seen: Dictionary = {}
	for i in range(window.root_sprites.size()):
		_dump_sprite(window.root_sprites[i], "root[%d]" % i, seen)
	_dump_bustup_objects(player, seen)
	if latest_message_output != null:
		print("latest message_output instance=%d path=%s" % [
			latest_message_output.get_instance_id(), str(seen.get(latest_message_output.get_instance_id(), "<not in tree>"))
		])
	else:
		print("latest message_output instance=<none captured>")


func _dump_bustup_objects(player, window_seen: Dictionary) -> void:
	print("-- adv.bustupMan.spr membership --")
	var adv: Variant = player.vm.globals_by_name.get("adv", null)
	if not adv is CsxVMReader.CsxInstance:
		print("globals_by_name['adv'] type=%s" % type_string(typeof(adv)))
		return
	var bustup_man: Variant = adv.get_field("bustupMan")
	if not bustup_man is CsxVMReader.CsxInstance:
		print("adv.bustupMan type=%s" % type_string(typeof(bustup_man)))
		return
	var bustups: Variant = bustup_man.get_field("spr")
	if not bustups is Array:
		print("adv.bustupMan.spr type=%s" % type_string(typeof(bustups)))
		return
	for index in range(bustups.size()):
		var value: Variant = bustups[index]
		if not value is CsxHostClass.HostSprite:
			print("spr[%d] type=%s" % [index, type_string(typeof(value))])
			continue
		var sprite := value as CsxHostClass.HostSprite
		var parent_id: int = sprite.parent_sprite.get_instance_id() if sprite.parent_sprite != null else -1
		var root_id: int = sprite.root_window.get_instance_id() if sprite.root_window != null else -1
		var texture_info := "none"
		if sprite.texture != null:
			texture_info = "%s %dx%d" % [sprite.filename, sprite.texture.get_width(), sprite.texture.get_height()]
		var tree_path := str(window_seen.get(sprite.get_instance_id(), "<not in tree>"))
		print("spr[%d] instance=%d visible=%s position=%s texture=%s parent=%d root_window=%d tree_path=%s" % [
			index, sprite.get_instance_id(), str(sprite.is_visible), str(sprite.position),
			texture_info, parent_id, root_id, tree_path
		])


func _run_bustup_host_probe(player) -> void:
	print("\n===== Explicit host/CSX API probe: SetBustup + AdvScreen::update =====")
	print("This is an explicit diagnostic mutation of runtime state, not a natural ScenarioLoop event.")
	var adv: Variant = player.vm.globals_by_name.get("adv", null)
	if adv == null:
		print("Probe skipped: globals_by_name['adv'] is null.")
		return
	var set_result: Dictionary = player.vm.call_function_sync("SetBustup", ["CA02_01M", 0, 0], 100000)
	print("SetBustup ok=%s return=%s error='%s'" % [
		str(set_result.get("ok", false)), str(set_result.get("value", null)), str(set_result.get("error", ""))
	])
	if not set_result.get("ok", false):
		return
	var update_result: Dictionary = player.vm.call_function_sync("AdvScreen::update", [adv, 0, 0], 100000)
	print("AdvScreen::update ok=%s return=%s error='%s'" % [
		str(update_result.get("ok", false)), str(update_result.get("value", null)), str(update_result.get("error", ""))
	])
	_dump_data_window(player, "explicit SetBustup/AdvScreen::update probe")


func _dump_sprite(sprite: CsxHostClass.HostSprite, path: String, seen: Dictionary) -> void:
	if seen.has(sprite.get_instance_id()):
		print("%s -> repeated instance=%d" % [path, sprite.get_instance_id()])
		return
	seen[sprite.get_instance_id()] = path
	var texture_info := "none"
	if sprite.texture != null:
		texture_info = "%s %dx%d" % [sprite.filename, sprite.texture.get_width(), sprite.texture.get_height()]
	var style_id := str(sprite.message_style.get("id", ""))
	var text_sample := sprite.display_text().substr(0, 48).replace("\n", "\\n")
	var item_id := str(sprite.fields.get("form_item_id", ""))
	var selected_index := str(sprite.fields.get("select_index", sprite.fields.get("nSelectIndex", "")))
	print("%s sprite_id=%d instance=%d visible=%s pos=%s size=%s style=%s message=%s text='%s' btn='%s' full_btn='%s' item_id='%s' select_index='%s' btn_state='%s' texture=%s" % [
		path, sprite.sprite_id, sprite.get_instance_id(), str(sprite.is_visible), str(sprite.position),
		str(sprite.size), style_id, str(sprite.is_message_sprite), text_sample,
		sprite.btn_id, sprite.full_btn_id, item_id, selected_index, sprite.btn_state, texture_info
	])
	for index in range(sprite.children.size()):
		var child: Variant = sprite.children[index]
		if child is CsxHostClass.HostSprite:
			_dump_sprite(child, "%s/child[%d]" % [path, index], seen)
		else:
			print("%s/child[%d] non-sprite type=%s" % [path, index, type_string(typeof(child))])


func _dump_last_message_output(player, label: String) -> void:
	if latest_message_output == null:
		print("%s message_output: <none captured>" % label)
		return
	var sprite := latest_message_output
	print("%s message_output id=%d style=%s text='%s'" % [
		label, sprite.get_instance_id(), str(sprite.message_style.get("id", "")),
		sprite.display_text().substr(0, 80).replace("\n", "\\n")
	])


func _remove_audit_saves() -> void:
	_remove_directory_contents(ProjectSettings.globalize_path("user://audit_story_window_tree"))


func _remove_directory_contents(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		push_warning("Could not clean audit save directory: %s" % path)
		return
	directory.list_dir_begin()
	while true:
		var name := directory.get_next()
		if name.is_empty():
			break
		if name == "." or name == "..":
			continue
		var child_path := path.path_join(name)
		if directory.current_is_dir():
			_remove_directory_contents(child_path)
			DirAccess.remove_absolute(child_path)
		else:
			DirAccess.remove_absolute(child_path)
	directory.list_dir_end()
	directory = null
	DirAccess.remove_absolute(path)
