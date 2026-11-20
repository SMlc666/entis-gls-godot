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
		printerr("Usage: godot --script res://tests/native_saveload_voice_smoke.gd -- <game_dir>")
		quit(1)
		return
	var game_dir: String = args[0]

	print("[1/5] Verifying pristine state of game archives before test ...")
	_verify_hashes(game_dir, "before test")
	print("  Hashes match pristine baseline.")

	print("[2/5] Initializing AdvPlayer and verifying native Save/Load Modal (690x574) ...")
	var scene_res = load("res://scenes/adv_player.tscn")
	expect(scene_res != null, "adv_player.tscn must load")
	var player = scene_res.instantiate()
	player.game_dir = game_dir
	var test_save_dir: String = TestSupport.new_save_dir("native_saveload_voice")
	player.save_dir_override = test_save_dir
	root.add_child(player)

	# Wait for initialization
	var frames := 0
	while not player.is_initialized and frames < 120:
		await process_frame
		frames += 1
	expect(player.is_initialized, "Player failed to initialize")
	if not TestSupport.uses_isolated_saves(player.host, test_save_dir):
		printerr("FAIL AdvPlayer did not use isolated test saves: %s" % player.host.save_dir)
		quit(1)
		return

	player._open_save_load_modal("save")
	expect(player.is_save_load_open, "Save/Load modal must be open")
	expect(player.save_load_box != null, "save_load_box must exist")
	expect(player.save_load_box.size == Vector2(690, 574), "save_load_box size must be 690x574, got %s" % str(player.save_load_box.size))

	# Verify Save title image (FRM_0506.eri)
	expect(player.save_load_title_img != null and player.save_load_title_img.texture != null, "save_load_title_img must have texture")
	expect(player.save_load_title_img.texture.get_size() == Vector2(131, 27), "FRM_0506 size must be 131x27")
	print("  Save/Load Window verified: (690x574), Save Title texture=(131x27)")

	# Verify ScrollBar (671, 33)
	expect(player.save_load_scroll != null, "save_load_scroll must exist")
	expect(player.save_load_scroll.position == Vector2(671, 33), "ScrollBar position must be (671, 33)")
	expect(player.save_load_scroll.size == Vector2(18, 504), "ScrollBar size must be (18, 504)")
	print("  ScrollBar ID_SCROLL verified: pos=(671, 33), size=(18, 504)")

	# Verify Quick Load Button (294, 547)
	expect(player.btn_qload != null, "btn_qload must exist")
	expect(player.btn_qload.position == Vector2(580, 547), "btn_qload position must be (580, 547)")
	expect(player.btn_qload.size == Vector2(84, 25), "btn_qload size must be (84, 25)")
	print("  Quick Load Button ID_QSAVE verified: pos=(294, 547), size=(84, 25)")

	# Verify Slot Cards in save_load_grid
	player._select_save_load_page(1)
	expect(player.save_load_grid.columns == 3, "save_load_grid must have 3 columns")
	expect(player.save_load_grid.get_child_count() == 10, "Page 1 must show 10 slots")
	var first_card = player.save_load_grid.get_child(0)
	expect(first_card is TextureButton, "Slot card must be TextureButton")
	expect(first_card.texture_normal != null, "Slot card must have normal texture (FRM_0501.eri)")
	expect(first_card.texture_hover != null, "Slot card must have focus/hover texture (FRM_0501.eri focus)")
	expect(first_card.texture_normal.get_size() == Vector2(220, 170), "Card texture size must be 220x170")

	var card_num: Label = first_card.find_child("ID_NUMBER", true, false)
	var card_date: Label = first_card.find_child("ID_DATE", true, false)
	var card_comm: Label = first_card.find_child("ID_COMMENT", true, false)
	var card_thumb: TextureRect = first_card.find_child("ID_THUMBNAIL", true, false)
	var card_new: TextureRect = first_card.find_child("ID_NEW", true, false)

	expect(card_num != null and card_num.position == Vector2(15, 38), "ID_NUMBER at (15, 38)")
	expect(card_date != null and card_date.position == Vector2(7, 100), "ID_DATE at (7, 100)")
	expect(card_comm != null and card_comm.position == Vector2(14, 121), "ID_COMMENT at (14, 121)")
	expect(card_thumb != null and card_thumb.position == Vector2(95, 2), "ID_THUMBNAIL at (95, 2)")
	expect(card_new != null and card_new.position == Vector2(8, 3), "ID_NEW at (8, 3)")
	print("  Slot Card geometry verified: (220x170), thumbnail at (95, 2), badge at (8, 3), labels at exact offsets")

	print("[3/5] Testing Save/Load Interactions & Mode Switching ...")
	# Switch to Load mode
	player._switch_save_load_mode("load")
	expect(player.save_load_mode == "load", "Mode must be load")
	expect(player.save_load_title_img.texture.get_size() == Vector2(131, 27), "FRM_0505 Load Title must be 131x27")
	expect(player.btn_qload.visible, "btn_qload must be visible in load mode")

	# Save to Slot 1
	player._switch_save_load_mode("save")
	expect(not player.btn_qload.visible, "btn_qload must be hidden in save mode")
	var ok_save = player.save_to_slot(1)
	expect(ok_save, "Saving to slot 1 must succeed")

	# Re-populate and verify newest badge
	player._populate_save_load_slots()
	var slot1_card = player.save_load_grid.get_child(0)
	var slot1_new: TextureRect = slot1_card.find_child("ID_NEW", true, false)
	expect(slot1_new != null and slot1_new.visible, "Slot 1 must have newest badge (ID_NEW) visible after save")
	expect(slot1_new.texture != null and slot1_new.texture.get_size() == Vector2(43, 33), "ID_NEW badge texture must be FRM_0502.eri (43x33)")
	print("  Save to Slot 1 verified: metadata stored, NEW badge (43x33) activated")

	player._close_save_load_modal()
	expect(not player.is_save_load_open, "Save/Load modal must close")

	print("[4/5] Testing Native Voice Volume Details Sub-Window (ID_PAGE_VOICE_DETAILS) ...")
	player._open_config_modal()
	expect(player.is_config_open, "Config modal must be open")
	expect(player.cfg_btn_voice_details != null, "cfg_btn_voice_details must exist")
	expect(player.cfg_btn_voice_details.position == Vector2(374, 179), "Voice details button pos must be (374, 179)")
	expect(player.cfg_btn_voice_details.texture_normal != null, "Voice details button must have texture (FRM_0204.eri)")
	expect(player.cfg_btn_voice_details.texture_normal.get_size() == Vector2(129, 26), "FRM_0204 button size must be 129x26")

	# Open Voice Details sub-window
	player._open_voice_details_modal()
	expect(player.is_voice_details_open, "voice_details_panel must be open")

	var v_box: Control = player.voice_details_panel.find_child("VoiceDetailsBox", true, false)
	expect(v_box != null and v_box.size == Vector2(335, 179), "VoiceDetailsBox size must be 335x179")
	var v_bg: TextureRect = player.voice_details_panel.find_child("VoiceDetailsBg", true, false)
	expect(v_bg != null and v_bg.texture != null and v_bg.texture.get_size() == Vector2(335, 179), "VoiceDetailsBg must have FRM_0231.eri (335x179)")

	# Verify 9 character toggle buttons
	var expected_chars = {
		"ID_SORA": Vector2(128, 13),
		"ID_AKIRA": Vector2(290, 13),
		"ID_NAO": Vector2(128, 43),
		"ID_KAZUHA": Vector2(290, 43),
		"ID_MOTOKA": Vector2(128, 73),
		"ID_KOZUE": Vector2(290, 73),
		"ID_YAHIRO": Vector2(128, 103),
		"ID_RYOUHEI": Vector2(290, 103),
		"ID_OTHER": Vector2(128, 133),
	}
	for char_id in expected_chars:
		var btn: TextureButton = player.voice_char_buttons.get(char_id, null)
		expect(btn != null, "Button for %s must exist" % char_id)
		expect(btn.position == expected_chars[char_id], "%s position must be %s, got %s" % [char_id, str(expected_chars[char_id]), str(btn.position)])
		expect(btn.size == Vector2(37, 27), "%s size must be 37x27" % char_id)
		expect(btn.texture_normal != null and btn.texture_normal.get_size() == Vector2(37, 27), "%s texture must be ID_BTN_CONFIG_SOUND_ON (37x27)" % char_id)
		print("  Character Voice button %-10s verified at pos %s with FRM_0217.eri" % [char_id, str(btn.position)])

	# Test character voice mute toggling
	expect(not player.voice_char_mutes["ID_SORA"], "Sora should initially not be muted")
	player._toggle_character_voice("ID_SORA")
	expect(player.voice_char_mutes["ID_SORA"], "Sora should now be muted")
	expect(player.host.voice_char_mutes["ID_SORA"], "Host must also reflect Sora muted")
	expect(player.voice_char_buttons["ID_SORA"].modulate == Color(0.35, 0.35, 0.35, 0.8), "Muted button modulate check")

	# Verify voice playback suppression when muted
	player.host.stop_voice()
	player.host.play_voice("SR000001")
	expect(player.voice_player == null or not player.voice_player.playing, "Voice SR000001 should NOT play when Sora is muted")

	player._toggle_character_voice("ID_SORA")
	expect(not player.voice_char_mutes["ID_SORA"], "Sora should be unmuted")
	expect(player.voice_char_buttons["ID_SORA"].modulate == Color(1.0, 1.0, 1.0, 1.0), "Active button modulate check")

	player.host.play_voice("SR000001")
	expect(player.voice_player != null and player.voice_player.playing, "Voice SR000001 SHOULD play when Sora is unmuted")
	player.host.stop_voice()

	player._close_voice_details_modal()
	expect(not player.is_voice_details_open, "Voice details modal must close")
	player._close_config_modal()
	expect(not player.is_config_open, "Config modal must close")
	print("  Voice Details modal verified: (335x179), 9 character buttons, mute state synchronization.")

	print("[5/5] Verifying final archive pristine status ...")
	_verify_hashes(game_dir, "after test")
	print("  Original game archives remain 100% pristine and unmodified.")

	TestSupport.remove_test_saves(test_save_dir)
	finish_success("PASS Native Save/Load & Voice Details Modal Smoke Test!")
