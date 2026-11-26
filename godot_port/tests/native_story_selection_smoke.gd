extends SceneTree

const CsxHostClass = preload("res://scripts/csx_host.gd")
const CsxVMReader = preload("res://scripts/csx_vm.gd")
const TestSupport = preload("res://tests/test_support.gd")

const TARGET_SCENARIO := "00_Z005"
const SELECT_FUNCTION := "AdvScreen::startSelect"
const TARGET_CHOICE := "敲门"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game_dir := TestSupport.resolve_game_dir(OS.get_cmdline_user_args())
	if game_dir.is_empty():
		printerr("FAIL Pass the original game directory after --")
		quit(2)
		return
	var csx_path := game_dir.path_join("system/yosuga.csx")
	var data_path := game_dir.path_join("data1.noa")
	var csx_hash := FileAccess.get_sha256(csx_path)
	var data_hash := FileAccess.get_sha256(data_path)
	var scene = load("res://scenes/adv_player.tscn")
	if scene == null:
		printerr("FAIL Could not load AdvPlayer")
		quit(1)
		return
	var player = scene.instantiate()
	player.game_dir = game_dir
	player.start_in_title = false
	player.start_scenario = "00_Z000"
	var save_dir: String = TestSupport.configure_player_saves(player, "native_story_selection")
	root.add_child(player)
	for frame in range(600):
		if player.is_initialized and player.vm != null and player.host != null:
			break
		await process_frame
	if not player.is_initialized or not TestSupport.uses_isolated_saves(player.host, save_dir):
		printerr("FAIL AdvPlayer did not initialize with isolated saves")
		await _cleanup(player, save_dir)
		quit(1)
		return

	var clear_result: Dictionary = player.vm.call_function_sync("OnGameClear", [], 100000)
	if not clear_result.get("ok", false):
		printerr("FAIL OnGameClear failed: %s" % str(clear_result))
		await _cleanup(player, save_dir)
		quit(1)
		return
	player.is_title_mode = false
	player.native_appreciation_mode = false
	player.is_running = true
	player.host.is_waiting_input = false
	player.host.begin_command_scope("selection-smoke")
	player.host.clear_command_cursor_override()
	player.vm.ip = player.vm.functions["ScenarioLoop"]
	player.vm.is_halted = false
	player.vm.pending_call_args = [TARGET_SCENARIO]
	player.vm.pending_return_ip = -1
	player.vm.call_stack.clear()
	player.vm.eval_stack.clear()
	player.start_scenario = TARGET_SCENARIO

	print("Advancing original ScenarioLoop(%s) using only ordinary story input until %s." % [TARGET_SCENARIO, SELECT_FUNCTION])
	var reached_original_select := false
	for frame in range(3600):
		await process_frame
		if player._native_stack_contains(SELECT_FUNCTION):
			reached_original_select = true
			break
		if player.host.is_waiting_input:
			player._advance_line()
	if not reached_original_select:
		printerr("FAIL Original AdvScreen::startSelect was not reached")
		await _cleanup(player, save_dir)
		quit(1)
		return
	var selection_frame: CsxVMReader.StackFrame = _find_selection_frame(player.vm.call_stack)
	if selection_frame == null or not (selection_frame.this_obj is CsxVMReader.CsxInstance):
		printerr("FAIL Original startSelect frame did not retain its receiver")
		await _cleanup(player, save_dir)
		quit(1)
		return
	var selection_receiver: CsxVMReader.CsxInstance = selection_frame.this_obj as CsxVMReader.CsxInstance

	if not player.story_window_compositor_active or not player.host_window_layer.visible:
		printerr("FAIL Original selection tree is not shown through HostWindow compositor")
		await _cleanup(player, save_dir)
		quit(1)
		return
	if player.find_child("ChoiceContainer", true, false) != null:
		printerr("FAIL Godot-owned choice controls were created during original startSelect")
		await _cleanup(player, save_dir)
		quit(1)
		return

	var window: CsxHostClass.HostWindow = player.vm.data_vars[4].get("value") as CsxHostClass.HostWindow
	var select_buttons: Array[CsxHostClass.HostSprite] = []
	_collect_select_buttons(window.root_sprites, select_buttons)
	if select_buttons.size() < 2:
		printerr("FAIL Original CSX did not create at least two ID_SELECT buttons in HostWindow")
		print("HostWindow roots=%d stack=%s" % [window.root_sprites.size(), _stack_names(player.vm.call_stack)])
		await _cleanup(player, save_dir)
		quit(1)
		return
	var target_button: CsxHostClass.HostSprite = _find_choice_button(select_buttons, TARGET_CHOICE)
	if target_button == null:
		printerr("FAIL Could not map original choice text '%s' to its button sprite" % TARGET_CHOICE)
		await _cleanup(player, save_dir)
		quit(1)
		return
	var wrapper: Control = player.host_sprite_controls.get(target_button.get_instance_id(), null)
	var native_button: TextureButton = wrapper.get_node_or_null("NativeButton") if wrapper != null else null
	if native_button == null or not native_button.is_visible_in_tree() or native_button.disabled:
		printerr("FAIL Original ID_SELECT button is not interactable in the compositor")
		await _cleanup(player, save_dir)
		quit(1)
		return

	var previous_result: Variant = selection_receiver.get_field("selectResult")
	window.focus_sprite(target_button)
	native_button.pressed.emit()
	var queued_select: Dictionary = player.host.peek_command_for_window(window.get_instance_id())
	if queued_select.is_empty() or str(queued_select.get("id", "")) != "ID_SELECT":
		printerr("FAIL Original HostSprite activation did not enqueue its CSX command")
		await _cleanup(player, save_dir)
		quit(1)
		return
	var queued_cursor: Variant = queued_select.get("cursor_position", null)
	var expected_cursor: Vector2i = player._host_sprite_logical_center(target_button)
	if not queued_cursor is Vector2i or queued_cursor != expected_cursor:
		printerr("FAIL Native selection command did not carry a coordinate inside its original HostSprite")
		await _cleanup(player, save_dir)
		quit(1)
		return
	print("Queued native ID_SELECT for '%s' with focus='%s'; prior selectResult=%s" % [TARGET_CHOICE, window.focused_path, str(previous_result)])

	var select_returned := false
	for frame in range(600):
		await process_frame
		if not player._native_stack_contains(SELECT_FUNCTION):
			select_returned = true
			break
	if not select_returned:
		printerr("FAIL Original startSelect did not consume the native command and return")
		print("queue=%s ip=0x%X stack=%s focus='%s'" % [str(player.host.pending_commands_snapshot()), int(player.vm.ip), _stack_names(player.vm.call_stack), window.focused_path])
		await _cleanup(player, save_dir)
		quit(1)
		return

	var selected_result: Variant = selection_receiver.get_field("selectResult")
	if int(selected_result) != 1:
		printerr("FAIL Original CSX selected result should be 1 for '%s', got %s" % [TARGET_CHOICE, str(selected_result)])
		await _cleanup(player, save_dir)
		quit(1)
		return
	if player.host.has_pending_commands():
		printerr("FAIL Original CSX left a stale native selection command in the Host queue")
		await _cleanup(player, save_dir)
		quit(1)
		return
	if csx_hash != FileAccess.get_sha256(csx_path) or data_hash != FileAccess.get_sha256(data_path):
		printerr("FAIL Original game inputs changed during the read-only scenario test")
		await _cleanup(player, save_dir)
		quit(1)
		return
	print("PASS Original ScenarioLoop -> AdvScreen::startSelect -> HostWindow ID_SELECT -> CSX selectResult=1; no Godot choice UI; source hashes unchanged")
	await _cleanup(player, save_dir)
	quit(0)


func _collect_select_buttons(sprites: Array, target: Array[CsxHostClass.HostSprite]) -> void:
	for sprite: CsxHostClass.HostSprite in sprites:
		if sprite.is_button and sprite.btn_id == "ID_SELECT":
			target.append(sprite)
		_collect_select_buttons(sprite.children, target)


func _find_choice_button(buttons: Array[CsxHostClass.HostSprite], text: String) -> CsxHostClass.HostSprite:
	for button: CsxHostClass.HostSprite in buttons:
		var row: CsxHostClass.HostSprite = button.parent_sprite
		if row == null:
			continue
		for sibling: CsxHostClass.HostSprite in row.children:
			if sibling.is_message_sprite and sibling.display_text() == text:
				return button
	return null


func _stack_names(frames: Array) -> String:
	var names: PackedStringArray = []
	for frame in frames:
		names.append(str(frame.name))
	return " > ".join(names)


func _find_selection_frame(frames: Array) -> CsxVMReader.StackFrame:
	for frame: CsxVMReader.StackFrame in frames:
		if frame.name == SELECT_FUNCTION:
			return frame
	return null


func _cleanup(player: Node, save_dir: String) -> void:
	if is_instance_valid(player):
		player.free()
	TestSupport.remove_test_saves(save_dir)
