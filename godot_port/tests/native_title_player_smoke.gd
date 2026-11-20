extends SceneTree

const CsxHostClass = preload("res://scripts/csx_host.gd")
const TestSupport = preload("res://tests/test_support.gd")

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		_fail("Pass game directory after --")
		return

	var game_dir: String = args[0]
	var scene_res = load("res://scenes/adv_player.tscn")
	if not _require(scene_res != null, "AdvPlayer scene must load"): return
	var player = scene_res.instantiate()
	player.game_dir = game_dir
	player.start_in_title = true
	player.steps_per_frame = 500
	var test_save_dir: String = TestSupport.configure_player_saves(player, "native_title_player")
	root.add_child(player)

	var frames := 0
	while not player.is_initialized and frames < 300:
		await process_frame
		frames += 1
	if not _require(player.is_initialized, "AdvPlayer must initialize"): return
	if not _require(TestSupport.uses_isolated_saves(player.host, test_save_dir), "AdvPlayer initialization must use isolated test saves"): return

	frames = 0
	var native_window = null
	var start_sprite = null
	var continue_sprite = null
	while frames < 60:
		await process_frame
		frames += 1
		if player.vm != null and player.vm.data_vars.size() > 4:
			native_window = player.vm.data_vars[4].get("value", null)
			if native_window is CsxHostClass.HostWindow:
				start_sprite = _find_button_sprite(native_window.root_sprites, "ID_START")
				continue_sprite = _find_button_sprite(native_window.root_sprites, "ID_CONTINUE")
			if (start_sprite != null and continue_sprite != null
			and player.native_title_controls.has(start_sprite.get_instance_id())
			and player.native_title_controls.has(continue_sprite.get_instance_id())
			and player.native_title_controls[start_sprite.get_instance_id()].is_visible_in_tree()
			and _native_stack_has(player.vm.call_stack, "GetCommand")):
				break
	if not _require(native_window is CsxHostClass.HostWindow, "Native Title() must create its HostWindow"): return
	if not _require(start_sprite != null and continue_sprite != null, "Native Title() must expose its original Start and Continue commands"): return
	for command_id: String in ["ID_CONFIG", "ID_EXITGAME"]:
		if not _require(_find_button_sprite(native_window.root_sprites, command_id) != null, "Native Title() must expose its original %s command" % command_id): return
	if not _require(player.is_title_mode and player.is_running, "Title() must run asynchronously in title mode"): return
	if not _require(player.native_title_layer.visible, "Native HostWindow renderer must be visible"): return
	var hand_made_menu = player.title_panel.find_child("TitleMenu", true, false)
	if not _require(hand_made_menu != null and not hand_made_menu.visible, "Hand-authored title menu must be hidden"): return
	var config_sprite = null
	for sprite in native_window.root_sprites:
		if sprite.fields.get("form_page_id") == "ID_PAGE_MENU":
			config_sprite = _find_button_sprite(sprite.children, "ID_CONFIG")
			break
	var config_wrapper: Control = player.native_title_controls.get(config_sprite.get_instance_id(), null) if config_sprite != null else null
	var config_button: TextureButton = config_wrapper.get_node_or_null("NativeButton") if config_wrapper != null else null
	if not _require(config_button != null, "Native Title() must expose an interactive ID_CONFIG"): return
	config_button.emit_signal("pressed")
	await process_frame
	var config_box: Control = player.config_panel.find_child("ConfigWindowBox", true, false)
	var config_bg: TextureRect = config_box.find_child("ConfigBg", true, false)
	var config_return_button: TextureButton = config_box.find_child("ID_TITLE", true, false)
	if not _require(player.is_config_open and config_bg.is_visible_in_tree() and config_bg.texture != null, "Title Config must show its skinned panel"): return
	if not _require(config_box.get_global_rect().get_center().is_equal_approx(root.get_visible_rect().get_center()), "Title Config panel must be centered"): return
	if not _require(config_return_button.is_visible_in_tree() and config_box.get_global_rect().encloses(config_return_button.get_global_rect()), "Title Config close button must be inside the panel"): return
	player.cfg_slider_bgm.value = 0.5
	if not _require(is_equal_approx(player.settings_state.audio_volume("bgm"), 0.5), "Title Config must update player settings"): return
	config_return_button.emit_signal("pressed")
	if not _require(not player.is_config_open, "Title Config close button must close the panel"): return

	config_button.emit_signal("pressed")
	var escape_event := InputEventKey.new()
	escape_event.keycode = KEY_ESCAPE
	escape_event.pressed = true
	player._unhandled_input(escape_event)
	await process_frame
	if not _require(player.is_title_mode and not player.is_config_open and config_button.is_visible_in_tree(), "Escape must return from Config to the title menu"): return
	var exit_requested := OS.get_cmdline_user_args().has("--verify-exit")
	if exit_requested:
		var exit_sprite = _find_button_sprite(native_window.root_sprites, "ID_EXITGAME")
		var exit_wrapper: Control = player.native_title_controls.get(exit_sprite.get_instance_id())
		if not _require(exit_wrapper.is_visible_in_tree(), "Exit must be visible before clicking"): return
		TestSupport.remove_test_saves(test_save_dir)
		print("Clicking native Exit button")
		exit_wrapper.get_node("NativeButton").emit_signal("pressed")
		await create_timer(0.25).timeout
		_fail("Native Exit button did not quit the game")
		return

	# This release's original Title() menu has Start, Continue, Config and ExitGame.
	# Appreciation() is a separate CSX screen, not a Title() command.
	if not _require(player._start_native_appreciation_script(), "Player must be able to enter the original CSX Appreciation() screen"): return
	frames = 0
	var native_app_window = null
	var rec_tab_sprite = null
	var cg_item_sprite = null
	while frames < 60:
		await process_frame
		frames += 1
		if player.native_appreciation_mode and player.vm.data_vars.size() > 4:
			native_app_window = player.vm.data_vars[4].get("value", null)
			if native_app_window is CsxHostClass.HostWindow:
				rec_tab_sprite = _find_button_sprite(native_app_window.root_sprites, "ID_REC")
				cg_item_sprite = _find_button_sprite(native_app_window.root_sprites, "ID_CGSEL1")
			if (rec_tab_sprite != null and cg_item_sprite != null
			and player.native_title_controls.has(rec_tab_sprite.get_instance_id())
			and player.native_title_controls.has(cg_item_sprite.get_instance_id())):
				break
	if not _require(player.is_title_mode and player.native_appreciation_mode, "Native CSX Appreciation() must start"): return
	if not _require(native_app_window is CsxHostClass.HostWindow, "Appreciation() must create its native HostWindow"): return
	if not _require(rec_tab_sprite != null and cg_item_sprite != null, "Native Appreciation() must create original recollection and CG controls"): return
	if not _require(not player.is_appreciation_open and not player.appreciation_panel.visible, "Native Appreciation() must not show the custom gallery panel"): return
	var native_cg_wrapper: Control = player.native_title_controls.get(cg_item_sprite.get_instance_id(), null)
	var native_cg_button: TextureButton = native_cg_wrapper.get_node_or_null("NativeButton") if native_cg_wrapper != null else null
	if not _require(native_cg_button != null and native_cg_button.texture_normal != null, "Native CG item must render its CSX button texture"): return
	var rec_tab_wrapper: Control = player.native_title_controls.get(rec_tab_sprite.get_instance_id(), null)
	var native_rec_tab_button: TextureButton = rec_tab_wrapper.get_node_or_null("NativeButton") if rec_tab_wrapper != null else null
	if not _require(native_rec_tab_button != null, "Native recollection tab must render as a TextureButton"): return
	if not _require(rec_tab_sprite.full_btn_id == "ID_PAGE_TAG1\\\\ID_REC", "Nested Appreciation button must preserve its full CSX command path"): return
	var rec_captures: Array = []
	if not _require(player.vm._is_match_usage(rec_tab_sprite.full_btn_id, "&ID_PAGE_TAG&(<0-9>*)&\\\\ID_REC&", rec_captures) == "" and rec_captures == [1], "CSX IsMatchUsage must match nested page commands and capture the one-based page index"): return
	var appreciation_view = null
	for app_frame: Variant in player.vm.call_stack:
		if app_frame.name == "Appreciation":
			appreciation_view = app_frame.get_local("view")
			break
	if not _require(appreciation_view != null, "Appreciation() must retain its native AppreciationView instance"): return
	native_rec_tab_button.emit_signal("pressed")
	frames = 0
	while frames < 60:
		await process_frame
		frames += 1
	if not _require(player.host.command_queue.is_empty() and not player.vm.is_halted and player.vm.last_error.is_empty(), "Native appreciation tab command must reach the running CSX loop"): return
	var tag_sprites = appreciation_view.get_field("sprTag")
	if not _require(tag_sprites is Array and player.vm._dispatch_array_method(tag_sprites, "IsButtonChecked", ["ID_REC"]) == -1, "CSX IsButtonChecked must find a selected button in the Appreciation sprite array"): return
	if not _require(int(appreciation_view.get_field("selPage")) == 3, "Native ID_REC must switch the original AppreciationView to its recollection page"): return
	var bgm21_sprite = _find_button_sprite(native_app_window.root_sprites, "ID_BGM21")
	var bgm21_wrapper: Control = player.native_title_controls.get(bgm21_sprite.get_instance_id(), null) if bgm21_sprite != null else null
	var bgm21_button: TextureButton = bgm21_wrapper.get_node_or_null("NativeButton") if bgm21_wrapper != null else null
	if not _require(bgm21_button != null, "Native Appreciation must expose BGM21 control"): return
	var bgm_before_select: String = player.host.current_bgm
	bgm21_button.emit_signal("pressed")
	frames = 0
	while frames < 60:
		await process_frame
		frames += 1
	if not _require(player.host.current_bgm == "BGM02_S.mio" and player.host.current_bgm != bgm_before_select, "Native ID_BGM21 must select its original BGM track"): return
	var native_close_sprite = _find_button_sprite(native_app_window.root_sprites, "ID_CLOSE")
	if not _require(native_close_sprite != null, "Native Appreciation() must expose a close command"): return
	var native_close_wrapper: Control = player.native_title_controls.get(native_close_sprite.get_instance_id(), null)
	var native_close_button: TextureButton = native_close_wrapper.get_node_or_null("NativeButton") if native_close_wrapper != null else null
	if not _require(native_close_button != null, "Native Appreciation close command must be interactive"): return
	native_close_button.emit_signal("pressed")
	if not _require(player.is_title_mode and not player.native_appreciation_mode and not player.vm.is_halted, "Closing native Appreciation() must return to Title()"): return

	frames = 0
	start_sprite = null
	while frames < 60:
		await process_frame
		frames += 1
		native_window = player.vm.data_vars[4].get("value", null)
		if native_window is CsxHostClass.HostWindow:
			start_sprite = _find_button_sprite(native_window.root_sprites, "ID_START")
		if (start_sprite != null and player.native_title_controls.has(start_sprite.get_instance_id())
		and _native_stack_has(player.vm.call_stack, "GetCommand")):
			break
	if not _require(start_sprite != null, "Re-entered Title() must rebuild ID_START"): return
	var start_wrapper: Control = player.native_title_controls.get(start_sprite.get_instance_id(), null)
	if not _require(start_wrapper != null, "ID_START must have a rendered Control"): return
	var start_button: TextureButton = start_wrapper.get_node_or_null("NativeButton")
	if not _require(start_button != null, "ID_START must render as an interactive TextureButton"): return
	if not _require(start_button.texture_normal == start_sprite.btn_normal_tex, "ID_START must use the original button texture"): return

	start_button.emit_signal("pressed")
	var transition_seconds := 0.0
	while player.is_title_mode and transition_seconds < 5.0:
		await process_frame
		transition_seconds += player.get_process_delta_time()
	if not _require(not player.is_title_mode, "Native ID_START must leave the title screen"): return
	if not _require(player.is_running, "ID_START must start the scenario loop"): return
	var timeout_result: Dictionary = player.vm.call_function_sync("Title", [], 1)
	if not _require(not timeout_result.get("ok", true) and timeout_result.get("timeout", false), "A synchronous Title() budget exhaustion must report timeout failure"): return

	print("PASS Native CSX Title() and Appreciation() Player Smoke Test!")
	TestSupport.remove_test_saves(test_save_dir)
	player.free()
	await process_frame
	await process_frame
	quit(0)


func _require(condition: bool, message: String) -> bool:
	if not condition:
		_fail(message)
		return false
	return true


func _fail(message: String) -> void:
	printerr("FAIL ", message)
	quit(1)


func _find_button_sprite(sprites: Array, button_id: String):
	for sprite in sprites:
		if sprite is CsxHostClass.HostSprite:
			if sprite.btn_id == button_id:
				return sprite
			var child_match = _find_button_sprite(sprite.children, button_id)
			if child_match != null:
				return child_match
	return null


func _native_stack_has(stack: Array, function_name: String) -> bool:
	for frame: Variant in stack:
		if frame.name == function_name:
			return true
	return false
