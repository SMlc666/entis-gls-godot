extends "res://tests/smoke_test_base.gd"

const TestSupport = preload("res://tests/test_support.gd")

const EXPECTED_HASHES := {
	"system/yosuga.csx": "157be9eb39cdc2d3cb654096340ca686f4ef48ac7fd7a6255673ba5f0c79afb6",
	"system/title.noa": "b74f4c62f2dd208393552f3cb9b4287af32121c665c1a27ae57d59b1f713fbbc",
	"system/frame.noa": "b6f5ad7bd4067ad65ab764faaf76fb9442e0d01ab5c88807ecb7c6cddf5cf875",
	"system/option.noa": "054d2f6b7583f09f9b728d38a89da7fa0ef5a16cc334dd8fb576dbdffd768310",
	"data1.noa": "d324c49ed4a80108f68aabaf7a202ec31d1b8f64075918f136944e72ec919831",
	"sound.noa": "166b22277d5398b452241a7502f5e6262de8d28a52d113f3c29673cc7d2a4005",
}

func _verify_hashes(game_dir: String, step_name: String) -> void:
	for rel_path: String in EXPECTED_HASHES:
		var full_path := game_dir.path_join(rel_path)
		var actual := FileAccess.get_sha256(full_path)
		var expected: String = EXPECTED_HASHES[rel_path]
		expect(actual == expected, "Hash mismatch for %s %s! Expected: %s, Got: %s" % [rel_path, step_name, expected, actual])


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("Usage: godot --script res://tests/native_menu_config_smoke.gd -- <game_dir>")
		quit(1)
		return
	var game_dir: String = args[0]

	print("[1/5] Verifying pristine state of game archives before test ...")
	_verify_hashes(game_dir, "before test")
	print("  Hashes match pristine baseline.")

	print("[2/5] Initializing AdvPlayer and verifying native Dialogue Frame (750x152) ...")
	var scene_res = load("res://scenes/adv_player.tscn")
	expect(scene_res != null, "adv_player.tscn must load")
	var player = scene_res.instantiate()
	player.game_dir = game_dir
	var test_save_dir: String = TestSupport.configure_player_saves(player, "native_menu_config")
	root.add_child(player)

	# Wait for initialization
	var frames := 0
	while not player.is_initialized and frames < 120:
		await process_frame
		frames += 1
	expect(player.is_initialized, "Player failed to initialize")
	expect(TestSupport.uses_isolated_saves(player.host, test_save_dir), "AdvPlayer initialization must use isolated test saves")

	expect(player.dialogue_box != null, "dialogue_box must exist")
	expect(player.dialogue_box.size == Vector2(750, 152), "dialogue_box size must be 750x152, got %s" % str(player.dialogue_box.size))

	var dlg_bg: TextureRect = player.dialogue_box.find_child("DialogueBackground", true, false)
	expect(dlg_bg != null and dlg_bg.texture != null, "dialogue_box must have FRM_0101.eri background texture")
	expect(dlg_bg.texture.get_size() == Vector2(750, 152), "FRM_0101 texture size must be 750x152")
	print("  Dialogue Frame verified: size=(750, 152), texture=FRM_0101.eri")

	print("[3/5] Verifying Native In-Game Menu Buttons (ID_PAGE_ADV_MENU, CLOSE, VOICE) ...")
	expect(player.speaker_label.position == Vector2(27, 8), "speaker_label position mismatch")
	expect(player.message_label.position == Vector2(39, 38), "message_label position mismatch")

	expect(player.voice_button is TextureButton, "voice_button must be TextureButton")
	expect(player.voice_button.position == Vector2(689, 6), "voice_button position mismatch")
	expect(player.voice_button.size == Vector2(28, 21), "voice_button size mismatch")
	expect(player.voice_button.texture_normal != null, "voice_button must have normal texture")

	expect(player.close_button is TextureButton, "close_button must be TextureButton")
	expect(player.close_button.position == Vector2(727, 7), "close_button position mismatch")
	expect(player.close_button.size == Vector2(16, 17), "close_button size mismatch")
	expect(player.close_button.texture_normal != null, "close_button must have normal texture")

	var menu_box: Control = player.dialogue_box.find_child("AdvMenuBox", true, false)
	expect(menu_box != null, "AdvMenuBox must exist inside dialogue_box")
	expect(menu_box.position == Vector2(9, 124), "AdvMenuBox position must be (9, 124)")
	expect(menu_box.size == Vector2(732, 25), "AdvMenuBox size must be (732, 25)")

	var expected_menu_buttons := [
		{"btn": player.qsave_button, "name": "ID_QSAVE", "x": 0},
		{"btn": player.qload_button, "name": "ID_QLOAD", "x": 85},
		{"btn": player.save_button, "name": "ID_SAVE", "x": 170},
		{"btn": player.load_button, "name": "ID_LOAD", "x": 255},
		{"btn": player.config_button, "name": "ID_CONFIG", "x": 366},
		{"btn": player.auto_button, "name": "ID_AUTO", "x": 478},
		{"btn": player.skip_button, "name": "ID_SKIP", "x": 563},
		{"btn": player.history_button, "name": "ID_HISTORY", "x": 648},
	]
	for item in expected_menu_buttons:
		var btn = item["btn"] as TextureButton
		expect(btn != null, "Button %s must be TextureButton" % item["name"])
		expect(btn.position.x == item["x"], "Button %s x pos expected %d, got %d" % [item["name"], item["x"], int(btn.position.x)])
		expect(btn.size == Vector2(84, 25), "Button %s size expected (84, 25), got %s" % [item["name"], str(btn.size)])
		expect(btn.texture_normal != null, "Button %s must have texture_normal" % item["name"])
		expect(btn.texture_hover != null, "Button %s must have texture_hover" % item["name"])
		print("  Button %-10s verified at pos=(%3d, 0) with normal/hover textures" % [item["name"], item["x"]])

	print("[4/5] Testing In-Game Interactions and Native Config Window ...")
	expect(player.is_running, "Story player must be running for modal pause checks")
	expect(not player._is_story_paused(), "Story should initially be unpaused")
	player._toggle_backlog()
	expect(player._is_story_paused(), "Opening backlog must pause story execution")
	player._toggle_backlog()
	expect(not player._is_story_paused(), "Closing backlog must resume story execution")

	# Test hiding and showing dialogue box
	player.close_button.emit_signal("pressed")
	expect(player.dialogue_box.visible == false, "dialogue_box must hide on close_button click")

	# Simulate left click on background to unhide
	var click_event := InputEventMouseButton.new()
	click_event.button_index = MOUSE_BUTTON_LEFT
	click_event.pressed = true
	player._gui_input(click_event)
	expect(player.dialogue_box.visible == true, "dialogue_box must unhide on screen click")
	print("  Dialogue hide/unhide interaction verified.")

	# Test Auto and Skip toggles
	player.auto_button.emit_signal("pressed")
	expect(player.auto_mode == true, "auto_mode must be true")
	player.auto_button.emit_signal("pressed")
	expect(player.auto_mode == false, "auto_mode must be false")

	player.skip_button.emit_signal("pressed")
	expect(player.skip_mode == true, "skip_mode must be true")
	player.skip_button.emit_signal("pressed")
	expect(player.skip_mode == false, "skip_mode must be false")
	print("  Auto and Skip toggle interactions verified.")

	# Test Config Window
	player.config_button.emit_signal("pressed")
	expect(player.is_config_open == true, "is_config_open must be true")
	expect(player.config_panel.visible == true, "config_panel must be visible")
	expect(player._is_story_paused(), "Opening Config must pause story execution")

	var cfg_win_box: Control = player.config_panel.find_child("ConfigWindowBox", true, false)
	expect(cfg_win_box != null, "ConfigWindowBox must exist")
	expect(cfg_win_box.size == Vector2(532, 552), "ConfigWindowBox size must be 532x552")

	var cfg_bg: TextureRect = cfg_win_box.find_child("ConfigBg", true, false)
	expect(cfg_bg != null and cfg_bg.texture != null, "ConfigBg must have FRM_0201 texture")
	expect(cfg_bg.texture.get_size() == Vector2(532, 552), "FRM_0201 texture size must be 532x552")

	# Verify sliders styling
	expect(player.cfg_slider_bgm != null and player.cfg_slider_bgm.position == Vector2(256, 83), "cfg_slider_bgm pos mismatch")
	expect(player.cfg_slider_se != null and player.cfg_slider_se.position == Vector2(256, 110), "cfg_slider_se pos mismatch")
	expect(player.cfg_slider_system != null and player.cfg_slider_system.position == Vector2(256, 137), "cfg_slider_system pos mismatch")
	expect(player.cfg_slider_voice != null and player.cfg_slider_voice.position == Vector2(256, 164), "cfg_slider_voice pos mismatch")

	# Test BGM volume slider
	player.cfg_slider_bgm.value = 0.5
	expect(abs(player.bgm_player.volume_db - linear_to_db(0.5)) < 0.1, "BGM volume must update")
	player.cfg_slider_system.value = 0.36
	expect(is_equal_approx(player.settings_state.audio_volume("system"), 0.36), "System slider must update settings state")
	expect(abs(player.system_player.volume_db - linear_to_db(0.36)) < 0.1, "System slider must update actual system player volume")
	player.cfg_slider_auto_speed.value = 4.2
	expect(is_equal_approx(player.settings_state.auto_delay_seconds(), 4.2), "Auto delay slider must update the active delay")

	# Reset while system audio is muted to verify the state is applied before UI values.
	player.cfg_check_system.emit_signal("pressed")
	expect(player.settings_state.is_muted("system"), "System mute toggle must update settings state")
	expect(player.system_player.volume_db <= -79.9, "System mute toggle must silence system output")
	var default_button: TextureButton = cfg_win_box.find_child("ID_DEFAULT", true, false)
	expect(default_button != null, "ID_DEFAULT button must exist in ConfigWindowBox")
	default_button.emit_signal("pressed")
	expect(not player.settings_state.is_muted("system"), "Default settings must clear system mute")
	expect(is_equal_approx(player.settings_state.audio_volume("system"), 0.8), "Default system volume must be restored")
	expect(abs(player.system_player.volume_db - linear_to_db(0.8)) < 0.1, "Default action must restore actual system player volume")
	expect(is_equal_approx(player.cfg_slider_system.value, 0.8), "Default action must restore system slider")
	expect(is_equal_approx(player.settings_state.auto_delay_seconds(), 2.0), "Default auto delay must be restored")
	expect(is_equal_approx(player.cfg_slider_auto_speed.value, 2.0), "Default action must restore auto delay slider")

	# Close config modal via ID_END
	var btn_end: TextureButton = cfg_win_box.find_child("ID_END", true, false)
	expect(btn_end != null, "ID_END button must exist in ConfigWindowBox")
	btn_end.emit_signal("pressed")
	expect(player.is_config_open == false, "Config modal must close on ID_END click")
	expect(player.config_panel.visible == false, "config_panel must hide")
	expect(not player._is_story_paused(), "Closing Config must resume story execution")
	player._open_voice_details_modal()
	expect(player._is_story_paused(), "Opening Voice Details must pause story execution")
	player._close_voice_details_modal()
	expect(not player._is_story_paused(), "Closing Voice Details must resume story execution")
	print("  Native Config Modal verified: (532x552), sliders, mute toggles, open/close.")

	player._open_config_modal()
	player.cfg_slider_bgm.value = 0.32
	player.cfg_slider_auto_speed.value = 4.2
	player.cfg_check_system.emit_signal("pressed")
	player._toggle_character_voice("ID_SORA")
	btn_end.emit_signal("pressed")
	player.free()
	var restarted = scene_res.instantiate()
	restarted.game_dir = game_dir
	restarted.save_dir_override = test_save_dir
	root.add_child(restarted)
	frames = 0
	while not restarted.is_initialized and frames < 120:
		await process_frame
		frames += 1
	expect(restarted.is_initialized, "Player must initialize again from the same save directory")
	expect(is_equal_approx(restarted.cfg_slider_bgm.value, 0.32), "BGM slider must restore after restarting")
	expect(is_equal_approx(restarted.cfg_slider_auto_speed.value, 4.2), "Auto delay must restore after restarting")
	expect(restarted.system_player.volume_db <= -79.9, "System mute must restore after restarting")
	expect(restarted.host != null and restarted.host.voice_char_mutes.get("ID_SORA", false), "Character mute must restore after restarting")
	restarted.free()

	print("[5/5] Verifying final archive pristine status ...")
	_verify_hashes(game_dir, "after test")
	print("  Original game archives remain 100% pristine and unmodified.")

	TestSupport.remove_test_saves(test_save_dir)
	finish_success("PASS Native Dialogue Menu & Config Modal Smoke Test!")
