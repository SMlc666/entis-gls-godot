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
	if DirAccess.rename_absolute(absolute_slot + ".bak", absolute_slot) != OK:
		printerr("FAIL Could not restore slot 3 for native LoadSaveWindow selection")
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
	_click(continue_button)
	var native_save_load_root: CsxHostClass.HostSprite
	var native_save_load_wrapper: Control
	var native_host_window: CsxHostClass.HostWindow
	for frame in range(180):
		await process_frame
		var native_window: Variant = player.vm.data_vars[4].get("value", null) if player.vm.data_vars.size() > 4 else null
		if _native_stack_has(player.vm.call_stack, "LoadSaveWindow::run") and native_window is CsxHostClass.HostWindow:
			native_host_window = native_window
			for candidate: CsxHostClass.HostSprite in native_window.root_sprites:
				if (
					candidate.size.x >= 600 and candidate.size.x <= 800
					and candidate.size.y >= 500 and candidate.size.y <= 600
					and _find_button_sprite(candidate.children, "ID_QSAVE") != null
				):
					native_save_load_root = candidate
					break
		if native_save_load_root != null:
			native_save_load_wrapper = player.host_sprite_controls.get(native_save_load_root.get_instance_id(), null)
			if native_save_load_wrapper != null and native_save_load_wrapper.is_visible_in_tree():
				break
	if native_save_load_root == null or native_save_load_wrapper == null or not native_save_load_wrapper.is_visible_in_tree():
		printerr("FAIL Original Title Continue must display LoadSaveWindow::run with a visible HostWindow tree (vm_error='%s', host_error='%s')" % [player.vm.last_error, player.host.last_error])
		quit(1)
		return
	if native_save_load_root.size != Vector2i(690, 574) or native_save_load_root.position != Vector2i(400, 300):
		printerr("FAIL Original LoadSaveWindow geometry mismatch: size=%s position=%s" % [native_save_load_root.size, native_save_load_root.position])
		quit(1)
		return
	if _find_button_sprite(native_save_load_root.children, "ID_QSAVE") == null:
		printerr("FAIL Original LoadSaveWindow must expose its ID_QSAVE control")
		quit(1)
		return
	print("  Original Title Continue opened the native LoadSaveWindow HostWindow tree.")
	var native_load_page: CsxHostClass.HostSprite = _find_host_sprite_by_form_page(native_host_window.root_sprites, "ID_PAGE_LOAD")
	var native_slot_page: CsxHostClass.HostSprite = native_load_page.find_form_item("ID_SELECT04") if native_load_page != null else null
	if native_slot_page == null or native_slot_page.position != Vector2i(87, 205) or native_slot_page.size != Vector2i(220, 170):
		printerr("FAIL Native LoadSaveWindow must render slot 04 (Save003) at its original card geometry: sprite=%s position=%s size=%s" % [str(native_slot_page), str(native_slot_page.position) if native_slot_page != null else "null", str(native_slot_page.size) if native_slot_page != null else "null"])
		quit(1)
		return
	var native_slot_button_sprite: CsxHostClass.HostSprite = native_slot_page.find_form_item("ID_SELECT")
	var native_slot_number: CsxHostClass.HostSprite = native_slot_page.find_form_item("ID_NUMBER")
	var native_slot_date: CsxHostClass.HostSprite = native_slot_page.find_form_item("ID_DATE")
	var native_slot_comment: CsxHostClass.HostSprite = native_slot_page.find_form_item("ID_COMMENT")
	if native_slot_button_sprite == null or native_slot_number == null or native_slot_date == null or native_slot_comment == null:
		printerr("FAIL Native Save003 card must expose select, number, date, and comment items")
		quit(1)
		return
	if native_slot_button_sprite.full_btn_id != "ID_PAGE_LOAD\\\\ID_SELECT04\\\\ID_SELECT":
		printerr("FAIL Native Save003 button command path mismatch: %s" % native_slot_button_sprite.full_btn_id)
		quit(1)
		return
	var native_slot_captures: Array = []
	var native_slot_usage: String = player.vm._is_match_usage(native_slot_button_sprite.full_btn_id, "%s&\\\\ID_SELECT&(<0-9>*)&\\\\ID_SELECT&", native_slot_captures)
	if native_slot_usage != "" or native_slot_captures != [4]:
		printerr("FAIL Original LoadSaveWindow slot selector must capture index 4: usage='%s' captures=%s" % [native_slot_usage, str(native_slot_captures)])
		quit(1)
		return
	if native_slot_number.text_content != "０４" or native_slot_date.text_content.is_empty() or native_slot_comment.text_content != str(info3["comment"]):
		printerr("FAIL Native Save003 metadata mismatch: number='%s' date='%s' comment='%s'" % [native_slot_number.text_content, native_slot_date.text_content, native_slot_comment.text_content])
		quit(1)
		return
	var native_slot_thumbnail: CsxHostClass.HostSprite = _find_host_sprite_by_geometry(native_host_window.root_sprites, Vector2i(120, 90), Vector2i(95, 208))
	if native_slot_thumbnail == null or native_slot_thumbnail.children.size() != 1:
		printerr("FAIL Native Save003 thumbnail overlay is missing")
		quit(1)
		return
	var native_slot_thumbnail_image: CsxHostClass.HostSprite = native_slot_thumbnail.children[0]
	if native_slot_thumbnail_image.filename.to_lower() != "save003.dat" or native_slot_thumbnail_image.texture == null or native_slot_thumbnail_image.image == null or native_slot_thumbnail_image.image.get_size() != Vector2i(120, 90):
		printerr("FAIL Native Save003 thumbnail did not load from the isolated save slot: filename='%s' size=%s" % [native_slot_thumbnail_image.filename, str(native_slot_thumbnail_image.size)])
		quit(1)
		return
	print("  Native Save003 card shows the original command path, metadata, and 120x90 thumbnail.")
	if OS.get_environment("Y2K_DUMP_NATIVE_SAVELOAD") == "1":
		var native_buttons: Array[String] = []
		_collect_native_buttons(native_host_window.root_sprites, native_buttons)
		print("  Native Save/Load controls:\n    " + "\n    ".join(native_buttons))
		var stack_names: Array[String] = []
		for frame: Variant in player.vm.call_stack:
			stack_names.append(str(frame.name))
		print("  VM state halted=%s running=%s vm_error='%s' host_error='%s' stack=%s" % [str(player.vm.is_halted), str(player.is_running), player.vm.last_error, player.host.last_error, str(stack_names)])
		_dump_native_sprite_tree(native_host_window.root_sprites, 0)
		var resource_manager: Variant = native_save_load_root.form_resources
		if resource_manager == null:
			print("  Native LoadSave HostSprite has no form resource manager reference.")
		else:
			print("  Form resource archive=%s pages=%s" % [resource_manager.loaded_archive_name, str(resource_manager.skin_pages.keys())])
			for page_id in ["ID_PAGE_LOAD", "ID_PAGE_SAVE"]:
				var page: Dictionary = resource_manager.skin_pages.get(page_id, {})
				var page_buttons: Array[String] = []
				for button: Dictionary in page.get("buttons", []):
					page_buttons.append(str(button.get("id", "")))
				print("  Skin page %s present=%s buttons=%s" % [page_id, not page.is_empty(), str(page_buttons)])
	var native_slot_wrapper: Control = player.host_sprite_controls.get(native_slot_button_sprite.get_instance_id(), null)
	var native_slot_button: TextureButton = native_slot_wrapper.get_node_or_null("NativeButton") if native_slot_wrapper != null else null
	if native_slot_button == null or native_slot_button.disabled:
		printerr("FAIL Native Save003 selector must be enabled and rendered as a TextureButton")
		quit(1)
		return
	_click(native_slot_button)
	for frame in range(120):
		await process_frame
		if player.confirm_panel.is_visible_in_tree():
			break
	if not player.confirm_panel.is_visible_in_tree() or player.confirm_panel.find_child("ID_NO", true, false) == null:
		var native_stack_after_click: Array[String] = []
		for stack_frame: Variant in player.vm.call_stack:
			native_stack_after_click.append(str(stack_frame.name))
		var native_button_window: CsxHostClass.HostWindow = native_slot_button_sprite.get_root_window()
		printerr("FAIL Selecting native Save003 must await the original CSX confirmation (modal=%s title=%s visible=%s disabled=%s mouse_filter=%s global_rect=%s button_window=%s current_window=%s pending=%s scoped_pending=%s stack=%s vm_error='%s' host_error='%s')" % [str(player.is_save_load_open), str(player.is_title_mode), str(native_slot_button.is_visible_in_tree()), str(native_slot_button.disabled), str(native_slot_button.mouse_filter), str(native_slot_button.get_global_rect()), str(native_button_window.get_instance_id()) if native_button_window != null else "null", str(native_host_window.get_instance_id()), str(player.host.has_pending_commands()), str(player.host.has_pending_commands_for_window(native_host_window.get_instance_id())), str(native_stack_after_click), player.vm.last_error, player.host.last_error])
		quit(1)
		return
	_click(player.confirm_panel.find_child("ID_NO", true, false))
	for frame in range(120):
		await process_frame
		if not player.confirm_panel.is_visible_in_tree():
			break
	if player.confirm_panel.is_visible_in_tree() or not _native_stack_has(player.vm.call_stack, "LoadSaveWindow::run") or player.host.pending_confirmation_active:
		printerr("FAIL Rejecting native load confirmation must return to the live LoadSaveWindow")
		quit(1)
		return
	var close_load_event := InputEventKey.new()
	close_load_event.keycode = KEY_Q
	close_load_event.unicode = KEY_Q
	close_load_event.pressed = true
	Input.parse_input_event(close_load_event)
	for frame in range(180):
		await process_frame
		if not _native_stack_has(player.vm.call_stack, "LoadSaveWindow::run"):
			break
	var release_load_event := InputEventKey.new()
	release_load_event.keycode = KEY_Q
	release_load_event.unicode = KEY_Q
	release_load_event.pressed = false
	Input.parse_input_event(release_load_event)
	if _native_stack_has(player.vm.call_stack, "LoadSaveWindow::run") or not player.is_title_mode:
		printerr("FAIL Original LoadSaveWindow must return to the Title() loop on Q")
		quit(1)
		return
	if DirAccess.rename_absolute(absolute_slot, absolute_slot + ".bak") != OK:
		printerr("FAIL Could not re-create interrupted slot commit for backup recovery test")
		quit(1)
		return
	player._open_save_load_modal("load")
	player._select_save_load_page(1)
	var slot_card: TextureButton
	for frame in range(120):
		await process_frame
		slot_card = player.save_load_grid.get_node_or_null("SlotCard_03")
		if player.is_save_load_open and slot_card != null and slot_card.is_visible_in_tree():
			break
	if not player.is_save_load_open or slot_card == null or not slot_card.is_visible_in_tree():
		printerr("FAIL Explicit project Save/Load modal must display recoverable slot 3")
		quit(1)
		return
	if not player.save_load_box.get_global_rect().get_center().is_equal_approx(root.get_visible_rect().get_center()):
		printerr("FAIL Project Save/Load modal panel must be centered")
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

	print("[6/7] Testing accepted native Title Continue load ...")
	player._show_title_screen()
	var reload_continue_button: TextureButton
	for frame in range(120):
		await process_frame
		var reload_title_window: Variant = player.vm.data_vars[4].get("value", null) if player.vm.data_vars.size() > 4 else null
		if reload_title_window is CsxHostClass.HostWindow:
			for sprite: CsxHostClass.HostSprite in reload_title_window.root_sprites:
				if sprite.fields.get("form_page_id") != "ID_PAGE_MENU":
					continue
				var continue_sprite := sprite.find_form_item("ID_CONTINUE")
				var continue_wrapper: Control = player.host_sprite_controls.get(continue_sprite.get_instance_id(), null) if continue_sprite != null else null
				if continue_wrapper != null and continue_wrapper.is_visible_in_tree():
					reload_continue_button = continue_wrapper.get_node_or_null("NativeButton")
		if reload_continue_button != null:
			break
	if reload_continue_button == null:
		printerr("FAIL Re-entered Title() must expose Continue for the native accepted-load path")
		quit(1)
		return
	_click(reload_continue_button)
	var accepted_native_window: CsxHostClass.HostWindow
	var accepted_native_load_root: CsxHostClass.HostSprite
	for frame in range(180):
		await process_frame
		var candidate_window: Variant = player.vm.data_vars[4].get("value", null) if player.vm.data_vars.size() > 4 else null
		if _native_stack_has(player.vm.call_stack, "LoadSaveWindow::run") and candidate_window is CsxHostClass.HostWindow:
			accepted_native_window = candidate_window
			accepted_native_load_root = _find_host_sprite_by_form_page(candidate_window.root_sprites, "ID_PAGE_LOAD")
		if accepted_native_load_root != null:
			break
	if accepted_native_load_root == null:
		printerr("FAIL Native Continue did not open the LoadSaveWindow load page")
		quit(1)
		return
	var accepted_slot_page: CsxHostClass.HostSprite = accepted_native_load_root.find_form_item("ID_SELECT04")
	var accepted_slot_sprite: CsxHostClass.HostSprite = accepted_slot_page.find_form_item("ID_SELECT") if accepted_slot_page != null else null
	var accepted_slot_wrapper: Control = player.host_sprite_controls.get(accepted_slot_sprite.get_instance_id(), null) if accepted_slot_sprite != null else null
	var accepted_slot_button: TextureButton = accepted_slot_wrapper.get_node_or_null("NativeButton") if accepted_slot_wrapper != null else null
	if accepted_slot_button == null or accepted_slot_button.disabled:
		printerr("FAIL Native LoadSaveWindow must enable the populated Save003 slot")
		quit(1)
		return
	_click(accepted_slot_button)
	for frame in range(120):
		await process_frame
		if player.confirm_panel.is_visible_in_tree():
			break
	if not player.confirm_panel.is_visible_in_tree():
		printerr("FAIL Accepted native slot selection must present CSX Confirm")
		quit(1)
		return
	_click(player.confirm_panel.find_child("ID_YES", true, false))
	for frame in range(240):
		await process_frame
		if not player.is_title_mode and not _native_stack_has(player.vm.call_stack, "LoadSaveWindow::run"):
			break
	if player.is_title_mode or player.title_panel.visible or _native_stack_has(player.vm.call_stack, "LoadSaveWindow::run") or player.vm.awaiting_host_confirmation:
		printerr("FAIL Accepting native Save003 confirmation must resume the loaded scenario")
		quit(1)
		return
	var native_load_dialogues := 0
	frames = 0
	while native_load_dialogues < 2 and frames < 200:
		await process_frame
		frames += 1
		if player.host != null and player.host.is_waiting_input:
			native_load_dialogues += 1
			player._advance_line()
	if native_load_dialogues < 2 or not player.vm.last_error.is_empty():
		printerr("FAIL Native LoadSaveWindow load did not resume and advance story dialogue")
		quit(1)
		return
	print("  Native Title Continue loaded Save003 and resumed story input.")

	print("[7/7] Testing ToneFilter Shader Effects & Integrity Check ...")
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
	print("PASS Title Screen, Native LoadSaveWindow, Multi-Slot Save/Load and ToneFilter Smoke Test!")
	TestSupport.remove_test_saves(test_save_dir)
	player.queue_free()
	await process_frame
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


func _collect_native_buttons(sprites: Array, output: Array[String]) -> void:
	for sprite: CsxHostClass.HostSprite in sprites:
		var form_page_id := str(sprite.fields.get("form_page_id", ""))
		var form_item_id := str(sprite.fields.get("form_item_id", ""))
		var control_type := str(sprite.fields.get("control_type", ""))
		if sprite.is_button or not sprite.btn_id.is_empty() or not sprite.full_btn_id.is_empty() or not form_page_id.is_empty() or not form_item_id.is_empty() or not control_type.is_empty():
			output.append("button=%s full=%s page=%s item=%s control=%s text=%s size=%s enabled=%s visible=%s" % [
				sprite.btn_id, sprite.full_btn_id, form_page_id, form_item_id, control_type, sprite.display_text(), str(sprite.size), str(sprite.is_enabled), str(sprite.is_visible)
			])
		_collect_native_buttons(sprite.children, output)


func _dump_native_sprite_tree(sprites: Array, depth: int) -> void:
	for sprite: CsxHostClass.HostSprite in sprites:
		var manager_name := "null"
		if sprite.form_resources != null:
			manager_name = str(sprite.form_resources.loaded_archive_name)
		print("%sSPR id=%d button=%s full=%s page=%s item=%s control=%s size=%s pos=%s visible=%s enabled=%s children=%d image=%s texture=%s manager=%s scroll=%s range=%s text='%s'" % [
			"  ".repeat(depth), sprite.get_instance_id(), sprite.btn_id, sprite.full_btn_id,
			str(sprite.fields.get("form_page_id", "")), str(sprite.fields.get("form_item_id", "")),
			str(sprite.fields.get("control_type", "")), str(sprite.size), str(sprite.position),
			str(sprite.is_visible), str(sprite.is_enabled), sprite.children.size(),
			str(sprite.image != null), str(sprite.texture != null), manager_name,
			str(sprite.fields.get("scroll_position", "")), str(sprite.fields.get("scroll_range", "")), sprite.display_text()
		])
		_dump_native_sprite_tree(sprite.children, depth + 1)


func _find_host_sprite_by_form_page(sprites: Array, page_id: String) -> CsxHostClass.HostSprite:
	for sprite in sprites:
		if not sprite is CsxHostClass.HostSprite:
			continue
		if str(sprite.fields.get("form_page_id", "")) == page_id:
			return sprite
		var nested_match := _find_host_sprite_by_form_page(sprite.children, page_id)
		if nested_match != null:
			return nested_match
	return null


func _find_host_sprite_by_geometry(sprites: Array, target_size: Vector2i, target_position: Vector2i) -> CsxHostClass.HostSprite:
	for sprite in sprites:
		if not sprite is CsxHostClass.HostSprite:
			continue
		if sprite.size == target_size and sprite.position == target_position and sprite.is_visible:
			return sprite
		var nested_match = _find_host_sprite_by_geometry(sprite.children, target_size, target_position)
		if nested_match != null:
			return nested_match
	return null


func _native_stack_has(stack: Array, function_name: String) -> bool:
	for frame: Variant in stack:
		if frame.name == function_name:
			return true
	return false


func _click(control: Control) -> void:
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = control.get_global_rect().get_center()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		root.push_input(click, true)
