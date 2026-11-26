extends "res://tests/smoke_test_base.gd"

const CsxHostClass = preload("res://scripts/csx_host.gd")
const CsxVMReader = preload("res://scripts/csx_vm.gd")
const TestSupport = preload("res://tests/test_support.gd")

const EXPECTED_HASHES := {
	"system/yosuga.csx": "157be9eb39cdc2d3cb654096340ca686f4ef48ac7fd7a6255673ba5f0c79afb6",
	"system/title.noa": "b74f4c62f2dd208393552f3cb9b4287af32121c665c1a27ae57d59b1f713fbbc",
	"system/frame.noa": "b6f5ad7bd4067ad65ab764faaf76fb9442e0d01ab5c88807ecb7c6cddf5cf875",
	"system/option.noa": "054d2f6b7583f09f9b728d38a89da7fa0ef5a16cc334dd8fb576dbdffd768310",
	"data1.noa": "d324c49ed4a80108f68aabaf7a202ec31d1b8f64075918f136944e72ec919831",
	"sound.noa": "166b22277d5398b452241a7502f5e6262de8d28a52d113f3c29673cc7d2a4005"
}

func _verify_hashes(game_dir: String) -> bool:
	for rel_path in EXPECTED_HASHES.keys():
		var full_path := game_dir.path_join(rel_path)
		var file := FileAccess.open(full_path, FileAccess.READ)
		if file == null:
			printerr("Missing file: ", full_path)
			return false
		var h := FileAccess.get_sha256(full_path)
		if h != EXPECTED_HASHES[rel_path]:
			printerr("HASH MISMATCH: %s got %s vs %s" % [rel_path, h, EXPECTED_HASHES[rel_path]])
			return false
	return true

func _initialize() -> void:
	print("==================================================================")
	print("🧪 Starting Scene Recollection & Appreciation Smoke Test")
	print("==================================================================")

	var game_dir := TestSupport.resolve_game_dir(OS.get_cmdline_user_args())
	if game_dir.is_empty():
		printerr("Usage: set YOSUGA_GAME_DIR or pass the game directory after --")
		quit(2)
		return

	# Phase 1: Verify Initial Hash Integrity
	print("\n[Phase 1] Verifying 100% untouched game file SHA-256 hashes...")
	expect(_verify_hashes(game_dir), "Original game files were modified!")
	print("  ✓ All 6 core archive and script hashes are PRISTINE.")

	# Phase 2: Instantiate AdvPlayer and inspect UI creation
	print("\n[Phase 2] Instantiating AdvPlayer and verifying Appreciation & Recollection UI...")
	var scene_res = load("res://scenes/adv_player.tscn")
	expect(scene_res != null, "adv_player.tscn must load")
	var player = scene_res.instantiate()
	player.game_dir = game_dir
	var test_save_dir: String = TestSupport.configure_player_saves(player, "scene_recollection")
	root.add_child(player)

	var frames := 0
	while not player.is_initialized and frames < 120:
		await process_frame
		frames += 1
	expect(player.is_initialized, "Player failed to initialize")
	expect(TestSupport.uses_isolated_saves(player.host, test_save_dir), "AdvPlayer initialization must use isolated test saves")

	expect(player.appreciation_panel != null, "appreciation_panel must be created")
	expect(player.btn_app_rec != null, "btn_app_rec must be created")
	expect(player.rec_container != null, "rec_container must be created")
	expect(player.rec_heroine_buttons.size() == 5, "Must have 5 heroine tab buttons")
	expect(player.rec_grid != null, "rec_grid must be created")
	expect(player.rec_grid.columns == 2, "Recollection grid must be 2 columns")
	print("  ✓ Appreciation & Recollection UI nodes created successfully.")

	# Phase 3: Verify Authentic Skinning from option.noa
	print("\n[Phase 3] Verifying authentic skin textures from option.noa...")
	expect(player.tex_app_bg != null, "tex_app_bg must be loaded from FRM_0701.eri")
	expect(player.tex_app_bg.get_size() == Vector2(800, 600), "Background must be 800x600")
	expect(player.tex_app_title != null, "tex_app_title must be loaded from FRM_0702.eri")
	expect(player.tex_rec_card_normal != null, "tex_rec_card_normal must be resolved from FRM_0734")
	expect(player.tex_rec_card_normal.get_size() == Vector2(242, 90), "Card normal must be 242x90")
	expect(player.tex_rec_card_focus != null, "tex_rec_card_focus must be resolved from FRM_0734")
	expect(player.tex_rec_card_focus.get_size() == Vector2(242, 90), "Card focus must be 242x90")
	expect(player.tex_rec_locked != null, "tex_rec_locked must be loaded from FRM_0735.eri")
	expect(player.tex_rec_locked.get_size() == Vector2(242, 90), "Locked frame must be 242x90")
	expect(player.tex_rec_btn_normal != null, "tex_rec_btn_normal must be resolved from FRM_0724")
	expect(player.tex_rec_btn_normal.get_size() == Vector2(41, 28), "Rec tab button must be 41x28")
	print("  ✓ All authentic appreciation skin textures resolved accurately.")

	# Phase 4: Test Recollection Mode Switching & 18 Scenes across 5 Heroines
	print("\n[Phase 4] Testing Recollection Catalog (18 scenes across 5 heroines)...")
	player._open_appreciation_modal()
	player._switch_app_mode("rec")
	expect(player.app_mode == "rec", "Must switch to 'rec' mode")
	expect(player.rec_container.visible == true, "rec_container must be visible")
	expect(player.cg_gallery_container.visible == false, "cg_gallery_container must be hidden")
	expect(player.bgm_jukebox_container.visible == false, "bgm_jukebox_container must be hidden")

	var expected_counts := [5, 4, 3, 3, 3]
	var heroines := ["穹 (Sora)", "奈绪 (Nao)", "瑛 (Akira)", "一叶 (Kazuha)", "初佳 (Motoka)"]
	var total_scenes := 0
	for h_idx in range(5):
		player._switch_rec_heroine(h_idx)
		var cards = player.rec_grid.get_children()
		expect(cards.size() == expected_counts[h_idx], "%s must have %d cards, got %d" % [heroines[h_idx], expected_counts[h_idx], cards.size()])
		total_scenes += cards.size()
		print("    - Heroine %d [%s]: %d recollection scenes verified." % [h_idx, heroines[h_idx], cards.size()])
	expect(total_scenes == 18, "Total recollection scenes must be 18, got %d" % total_scenes)
	print("  ✓ All 18 recollection scenes populated and verified across all 5 heroines.")

	# Phase 5: Test Full Unlock vs Locked state
	print("\n[Phase 5] Testing lock/unlock modes...")
	player.app_full_unlock = false
	player._populate_rec_grid()
	var locked_cards = player.rec_grid.get_children()
	for c in locked_cards:
		var btn = c.get_child(0)
		expect(btn is TextureButton, "Card child 0 must be TextureButton")
		expect(btn.texture_normal == player.tex_rec_locked or btn.disabled, "When locked, must show lock texture")
	print("  ✓ Full unlock OFF: Locked cards correctly display FRM_0735 locked banner.")

	player.app_full_unlock = true
	player._populate_rec_grid()
	var unlocked_cards = player.rec_grid.get_children()
	for c in unlocked_cards:
		var btn = c.get_child(0)
		expect(btn is TextureButton, "Card child 0 must be TextureButton")
		expect(btn.texture_normal == player.tex_rec_card_normal, "When unlocked, card must use FRM_0734 normal texture")
		expect(btn.get_child_count() > 0, "Card button must have inner banner TextureRect")
	print("  ✓ Full unlock ON: Cards correctly display authentic character banners.")

	# Phase 6: Test Scene Recollection Execution & Return Flow
	print("\n[Phase 6] Testing Scene Recollection launch & return flow...")
	player._switch_rec_heroine(0) # Sora
	player.host.is_waiting_input = true
	player.host.push_command("ID_STALE_CHOICE", "ID_STALE_CHOICE", 0, 0, Vector2i(400, 300))
	player.host.advance_ticks = 2
	player.host.skip_input_pending = true
	player.host.yield_for_sprite_activation = true
	player.auto_mode = true
	player.skip_mode = true
	player._start_scene_recollection("00_A020", 0)

	expect(player.is_recollect_mode == true, "is_recollect_mode must be true")
	expect(player.recollect_return_tag == 0, "recollect_return_tag must be 0")
	expect(player.is_appreciation_open == false, "Appreciation modal must be closed during playback")
	expect(player.is_title_mode == false, "Title mode must be false during playback")
	expect(not player.host_window_layer.visible, "Title sprites must not cover recollection playback")
	expect(player.is_running == true, "Engine must be running recollection scenario")
	expect(not player.host.is_waiting_input, "Recollection launch must clear stale dialogue wait")
	expect(not player.host.has_pending_commands() and not player.host.command_cursor_override_valid, "Recollection launch must clear stale native commands and cursor override")
	expect(player.host.advance_ticks == 0 and not player.host.skip_input_pending and not player.host.yield_for_sprite_activation, "Recollection launch must clear stale advance and activation state")
	expect(not player.auto_mode and not player.skip_mode, "Recollection launch must not inherit auto or skip mode")

	# Step VM a few cycles to confirm dialogue progression
	for s in range(500):
		if not await _step_vm_cooperatively(player):
			break
		if player.host.is_waiting_input:
			player.host.is_waiting_input = false # advance line

	print("    - Successfully executed recollection scenario '00_A020'.")

	# End recollection and test return
	player.host.is_waiting_input = true
	player.host.push_command("ID_STALE_TITLE", "ID_STALE_TITLE", 0, 0, Vector2i(400, 300))
	player.host.advance_ticks = 1
	player.host.skip_input_pending = true
	player.host.yield_for_sprite_activation = true
	player._end_scene_recollection()
	expect(player.is_recollect_mode == false, "is_recollect_mode must be false after exit")
	expect(player.is_appreciation_open == true, "Appreciation modal must be re-opened")
	expect(player.app_mode == "rec", "Appreciation modal must return to 'rec' mode")
	expect(player.app_rec_heroine_index == 0, "Heroine tab must be restored to Sora (0)")
	expect(not player.host.is_waiting_input, "Returning to title must clear old story wait")
	expect(not player.host.has_pending_commands() and not player.host.command_cursor_override_valid, "Returning to title must clear stale native commands and cursor override")
	expect(player.host.advance_ticks == 0 and not player.host.skip_input_pending and not player.host.yield_for_sprite_activation, "Returning to title must clear old pending input and activation state")
	print("  ✓ Exited recollection: returned seamlessly to Appreciation View on the same heroine tab.")

	# Phase 7: Final Hash Verification
	print("\n[Phase 7] Final pristine file integrity check...")
	expect(_verify_hashes(game_dir), "Original game files were modified!")
	print("  ✓ All 6 core archive and script hashes remain 100% UNTOUCHED.")

	print("\n==================================================================")
	TestSupport.remove_test_saves(test_save_dir)
	finish_success("🎉 ALL SCENE RECOLLECTION & APPRECIATION TESTS PASSED!")


func _step_vm_cooperatively(player: Variant) -> bool:
	if not player.vm.step():
		return false
	while player.vm.refresh_cooperative_sleep():
		player.host.advance_sprite_animations(1.0 / 60.0)
		await process_frame
	return true
