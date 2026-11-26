extends SceneTree

const CsxVMReader = preload("res://scripts/csx_vm.gd")
const CsxHostClass = preload("res://scripts/csx_host.gd")
const TestSupport = preload("res://tests/test_support.gd")

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("FAIL Pass game directory after --")
		quit(1)
		return

	var game_dir: String = args[0]
	var csx_path := game_dir.path_join("system/yosuga.csx")
	var data1_path := game_dir.path_join("data1.noa")
	var sound_path := game_dir.path_join("sound.noa")
	var title_noa_path := game_dir.path_join("system/title.noa")

	var csx_hash_before := FileAccess.get_sha256(csx_path)
	var data1_hash_before := FileAccess.get_sha256(data1_path)
	var sound_hash_before := FileAccess.get_sha256(sound_path)
	var title_hash_before := FileAccess.get_sha256(title_noa_path)

	print("[1/6] Launching AdvPlayer in Title Screen mode (--title) ...")
	var scene_res = load("res://scenes/adv_player.tscn")
	if scene_res == null:
		printerr("FAIL Could not load adv_player.tscn")
		quit(1)
		return

	var player = scene_res.instantiate()
	player.game_dir = game_dir
	player.start_in_title = true
	var test_save_dir: String = TestSupport.new_save_dir("title_saveload")
	player.save_dir_override = test_save_dir
	root.add_child(player)

	var wait_frames := 0
	while not player.is_initialized and wait_frames < 200:
		await process_frame
		wait_frames += 1

	if not player.is_initialized:
		printerr("FAIL AdvPlayer failed to initialize in %d frames" % wait_frames)
		quit(1)
		return
	if not TestSupport.uses_isolated_saves(player.host, test_save_dir):
		printerr("FAIL AdvPlayer did not use isolated test saves: %s" % player.host.save_dir)
		quit(1)
		return
	print("  AdvPlayer initialized in %d frames" % wait_frames)

	# Verify Title Screen state
	if not player.is_title_mode:
		printerr("FAIL Expected is_title_mode == true")
		quit(1)
		return
	if not player.title_panel.visible:
		printerr("FAIL Expected title_panel.visible == true")
		quit(1)
		return

	# Verify that the original CSX Title() script created the visible title tree.
	var title_window = null
	var title_wait_frames := 0
	while title_wait_frames < 60:
		await process_frame
		title_wait_frames += 1
		if player.vm.data_vars.size() > 4:
			title_window = player.vm.data_vars[4].get("value", null)
			if title_window is CsxHostClass.HostWindow and _find_button_sprite(title_window.root_sprites, "ID_START") != null:
				break
	if not (title_window is CsxHostClass.HostWindow):
		printerr("FAIL Native Title() did not create a HostWindow")
		quit(1)
		return
	var title_bg_sprite = _find_sprite_by_size(title_window.root_sprites, Vector2i(800, 600))
	var title_logo_sprite = _find_sprite_by_size(title_window.root_sprites, Vector2i(354, 75))
	if title_bg_sprite == null or title_bg_sprite.texture == null:
		printerr("FAIL Native title tree has no 800x600 background texture")
		quit(1)
		return
	if title_logo_sprite == null or title_logo_sprite.texture == null:
		printerr("FAIL Native title tree has no 354x75 logo texture")
		quit(1)
		return
	print("  Native Title() background: %s (%dx%d), logo: (%dx%d)" % [
		title_bg_sprite.filename,
		title_bg_sprite.texture.get_width(), title_bg_sprite.texture.get_height(),
		title_logo_sprite.texture.get_width(), title_logo_sprite.texture.get_height()
	])
	if player.host_window_layer == null or not player.host_window_layer.visible:
		printerr("FAIL Native HostWindow renderer is hidden")
		quit(1)
		return
	if player.title_bg.visible or player.title_logo.visible:
		printerr("FAIL Legacy title artwork should be hidden while the native title runs")
		quit(1)
		return

	# Verify title BGM
	print("  Current Title BGM: %s" % player.host.current_bgm)
	if player.host.current_bgm.to_lower() != "bgm07.mio":
		printerr("FAIL Expected title theme BGM07.mio, got %s" % player.host.current_bgm)
		quit(1)
		return

	var title_stream := player.bgm_player.stream as AudioStreamWAV
	if title_stream == null or title_stream.loop_mode != AudioStreamWAV.LOOP_FORWARD or title_stream.loop_begin != 161922 or title_stream.loop_end != 4973038:
		printerr("FAIL Original Title() must start the BGM07 PCM loop from the CSX parameters")
		quit(1)
		return

	print("[2/6] Transitioning from Title to New Game ...")
	player._on_title_start_game()
	if player.is_title_mode or player.title_panel.visible:
		printerr("FAIL Title panel should be hidden after start game")
		quit(1)
		return

	# Advance scenario to build dialogue history
	var dialogues_seen := 0
	var frames := 0
	while dialogues_seen < 6 and frames < 300:
		await process_frame
		frames += 1
		if player.host != null and player.host.text_history.size() > dialogues_seen:
			dialogues_seen = player.host.text_history.size()
			var last_line: Dictionary = player.host.text_history[-1]
			print("  Dialogue %d: [%s] %s" % [dialogues_seen, last_line.get("speaker", ""), last_line.get("text", "")])
		if player.host != null and player.host.is_waiting_input:
			player._advance_line()

	if dialogues_seen < 4:
		printerr("FAIL Expected at least 4 dialogue lines before save, got %d" % dialogues_seen)
		quit(1)
		return

	print("[3/6] Testing Save/Load Modal & Multi-slot Pagination ...")
	player._open_save_load_modal("save")
	if not player.is_save_load_open or not player.save_load_panel.visible:
		printerr("FAIL Save modal did not open")
		quit(1)
		return

	# Test pagination
	player._select_save_load_page(1) # Page 1: slots 1-10
	print("  Page 1 active, slot count displayed: %d" % player.save_load_grid.get_child_count())
	if player.save_load_grid.get_child_count() != 10:
		printerr("FAIL Expected 10 slots on page 1, got %d" % player.save_load_grid.get_child_count())
		quit(1)
		return

	player._select_save_load_page(2) # Page 2: slots 11-20
	print("  Page 2 active, slot count displayed: %d" % player.save_load_grid.get_child_count())
	if player.save_load_grid.get_child_count() != 10:
		printerr("FAIL Expected 10 slots on page 2, got %d" % player.save_load_grid.get_child_count())
		quit(1)
		return

	player._select_save_load_page(0) # Page 0: Quick save
	print("  Page 0 active, slot count displayed: %d" % player.save_load_grid.get_child_count())
	if player.save_load_grid.get_child_count() != 1:
		printerr("FAIL Expected 1 slot on page 0, got %d" % player.save_load_grid.get_child_count())
		quit(1)
		return

	print("[4/6] Saving to Slot 3 and verifying slot metadata & thumbnail ...")
	player._select_save_load_page(1)
	var ok_save = player.save_to_slot(3)
	if not ok_save:
		printerr("FAIL save_to_slot(3) failed")
		quit(1)
		return

	var info3: Dictionary = player.get_slot_info(3)
	print("  Slot 3 Info: exists=%s, timestamp='%s', comment='%s', has_thumbnail=%s" % [
		info3["exists"], info3["timestamp"], info3["comment"], info3["thumbnail"] != null
	])
	if not info3["exists"]:
		printerr("FAIL Slot 3 reported non-existent after save")
		quit(1)
		return
	if info3["comment"].is_empty():
		printerr("FAIL Slot 3 comment is empty")
		quit(1)
		return
	if info3["thumbnail"] == null:
		printerr("FAIL Slot 3 thumbnail is null")
		quit(1)
		return

	player._close_save_load_modal()
	if player.is_save_load_open or player.save_load_panel.visible:
		printerr("FAIL Save modal did not close")
		quit(1)
		return

	print("[5/6] Testing Return to Title and Loading Slot 3 ...")
	# Return to title screen
	player._show_title_screen()
	if not player.is_title_mode:
		printerr("FAIL Return to title screen failed")
		quit(1)
		return

	var slot_path: String = player.host.get_save_path("Save003.dat")
	var absolute_slot := ProjectSettings.globalize_path(slot_path)
	if DirAccess.rename_absolute(absolute_slot, absolute_slot + ".bak") != OK:
		printerr("FAIL Could not simulate interrupted slot commit")
		quit(1)
		return
	var corrupt_file := FileAccess.open(player.host.get_save_path("Save004.dat"), FileAccess.WRITE)
	corrupt_file.store_string("{}")
	corrupt_file.close()
	if player.get_slot_info(4)["exists"]:
		printerr("FAIL Corrupt slot without a backup must be empty in the slot list")
		quit(1)
		return

	# Use the actual title button and slot-card confirmation.
	var continue_button: TextureButton
	for frame in range(120):
		await process_frame
		var window = player.vm.data_vars[4].get("value")
		if window is CsxHostClass.HostWindow:
			for sprite in window.root_sprites:
				if sprite.fields.get("form_page_id") != "ID_PAGE_MENU":
					continue
				for child in sprite.children:
					if child.btn_id == "ID_CONTINUE":
						var wrapper: Control = player.host_sprite_controls.get(child.get_instance_id())
						if wrapper != null and wrapper.is_visible_in_tree():
							continue_button = wrapper.get_node("NativeButton")
		if continue_button != null:
			break
	if continue_button == null:
		printerr("FAIL Title Continue is missing")
		quit(1)
		return
	player._select_save_load_page(1)
	_click(continue_button)
	await process_frame
	var slot_card: TextureButton = player.save_load_grid.get_node_or_null("SlotCard_03")
	if not player.is_save_load_open or slot_card == null or not slot_card.is_visible_in_tree():
		printerr("FAIL Title Continue must display the slot cards")
		quit(1)
		return
	if not player.save_load_box.get_global_rect().get_center().is_equal_approx(root.get_visible_rect().get_center()):
		printerr("FAIL Title Continue panel must be centered")
		quit(1)
		return
	_click(slot_card)
	if not player.confirm_panel.is_visible_in_tree():
		printerr("FAIL Choosing a saved slot must show the load confirmation")
		quit(1)
		return
	_click(player.confirm_panel.find_child("ID_YES", true, false))

	if player.is_title_mode or player.title_panel.visible:
		printerr("FAIL Loading save did not exit title mode")
		quit(1)
		return

	# Advance scenario again to confirm story continues
	var post_load_dialogues := 0
	frames = 0
	while post_load_dialogues < 3 and frames < 200:
		await process_frame
		frames += 1
		if player.host != null and player.host.is_waiting_input:
			post_load_dialogues += 1
			player._advance_line()

	if post_load_dialogues < 3:
		printerr("FAIL Story did not advance after loading Slot 3")
		quit(1)
		return
	print("  Successfully progressed %d steps after loading Slot 3" % post_load_dialogues)

	print("[6/6] Testing ToneFilter Shader Effects & Integrity Check ...")
	# Test ToneFilter transitions
	player.host.set_tone_filter("SEPIA")
	var sepia_mode = player.tone_material.get_shader_parameter("filter_mode")
	print("  SEPIA filter mode: %s (expected 1)" % sepia_mode)
	if int(sepia_mode) != 1:
		printerr("FAIL Expected filter_mode 1 for SEPIA, got ", sepia_mode)
		quit(1)
		return

	player.host.set_tone_filter("MONO")
	var mono_mode = player.tone_material.get_shader_parameter("filter_mode")
	print("  MONO filter mode: %s (expected 2)" % mono_mode)
	if int(mono_mode) != 2:
		printerr("FAIL Expected filter_mode 2 for MONO, got ", mono_mode)
		quit(1)
		return

	player.host.set_tone_filter("NORMAL")
	var normal_mode = player.tone_material.get_shader_parameter("filter_mode")
	print("  NORMAL filter mode: %s (expected 0)" % normal_mode)
	if int(normal_mode) != 0:
		printerr("FAIL Expected filter_mode 0 for NORMAL, got ", normal_mode)
		quit(1)
		return

	# Integrity verification of original assets
	print("  Verifying pristine status of local game assets...")
	var csx_hash_after := FileAccess.get_sha256(csx_path)
	var data1_hash_after := FileAccess.get_sha256(data1_path)
	var sound_hash_after := FileAccess.get_sha256(sound_path)
	var title_hash_after := FileAccess.get_sha256(title_noa_path)

	if csx_hash_before != csx_hash_after:
		printerr("FAIL csx file modified! Before: %s, After: %s" % [csx_hash_before, csx_hash_after])
		quit(1)
		return
	if data1_hash_before != data1_hash_after:
		printerr("FAIL data1.noa file modified! Before: %s, After: %s" % [data1_hash_before, data1_hash_after])
		quit(1)
		return
	if sound_hash_before != sound_hash_after:
		printerr("FAIL sound.noa file modified! Before: %s, After: %s" % [sound_hash_before, sound_hash_after])
		quit(1)
		return
	if title_hash_before != title_hash_after:
		printerr("FAIL title.noa file modified! Before: %s, After: %s" % [title_hash_before, title_hash_after])
		quit(1)
		return

	print("  All local game archives remain 100% pristine and unmodified.")
	print("PASS Title Screen, Multi-Slot Save/Load and ToneFilter Smoke Test!")
	TestSupport.remove_test_saves(test_save_dir)
	quit(0)


func _find_button_sprite(sprites: Array, button_id: String):
	for sprite in sprites:
		if sprite is CsxHostClass.HostSprite:
			if sprite.btn_id == button_id:
				return sprite
			var child_match = _find_button_sprite(sprite.children, button_id)
			if child_match != null:
				return child_match
	return null


func _find_sprite_by_size(sprites: Array, size: Vector2i):
	for sprite in sprites:
		if sprite is CsxHostClass.HostSprite:
			if sprite.size == size:
				return sprite
			var child_match = _find_sprite_by_size(sprite.children, size)
			if child_match != null:
				return child_match
	return null


func _click(control: Control) -> void:
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = control.get_global_rect().get_center()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		root.push_input(click, true)
