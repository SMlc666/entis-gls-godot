extends "res://tests/smoke_test_base.gd"

const TestSupport = preload("res://tests/test_support.gd")

const EXPECTED_HASHES: Dictionary = {
	"system/yosuga.csx": "157be9eb39cdc2d3cb654096340ca686f4ef48ac7fd7a6255673ba5f0c79afb6",
	"system/title.noa": "b74f4c62f2dd208393552f3cb9b4287af32121c665c1a27ae57d59b1f713fbbc",
	"data1.noa": "d324c49ed4a80108f68aabaf7a202ec31d1b8f64075918f136944e72ec919831",
	"sound.noa": "166b22277d5398b452241a7502f5e6262de8d28a52d113f3c29673cc7d2a4005"
}

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game_dir := TestSupport.resolve_game_dir(OS.get_cmdline_user_args())
	if game_dir.is_empty():
		printerr("Usage: set YOSUGA_GAME_DIR or pass the game directory after --")
		quit(2)
		return

	print("[1/6] Instantiating AdvPlayer in Title Screen mode ...")
	var adv_scene: PackedScene = load("res://scenes/adv_player.tscn")
	var player = adv_scene.instantiate()
	player.game_dir = game_dir
	player.start_in_title = true
	var test_save_dir: String = TestSupport.configure_player_saves(player, "appreciation")
	root.add_child(player)

	for _i in range(5):
		await process_frame
	expect(TestSupport.uses_isolated_saves(player.host, test_save_dir), "AdvPlayer initialization must use isolated test saves")

	expect(player.is_title_mode, "AdvPlayer should be in title mode")
	expect(player.title_panel != null and player.title_panel.visible, "Title panel should be visible")
	print("[2/6] Opening the compatibility Gallery modal ...")
	player._open_appreciation_modal()
	await process_frame
	expect(player.is_appreciation_open, "is_appreciation_open must be true")
	expect(player.appreciation_panel.visible, "appreciation_panel must be visible")
	expect(not player.native_title_layer.visible, "Title sprites must not overlap the gallery")
	expect(player.cg_catalog.size() == 6, "cg_catalog must have 6 categories")

	var total_scenes := 0
	for cat in ["EA", "EB", "EC", "ED", "EE", "EZ"]:
		var scenes: Array = player.cg_catalog.get(cat, [])
		total_scenes += scenes.size()
		print("  Category %s: %d scenes" % [cat, scenes.size()])
	expect(total_scenes == 79, "Total CG scenes should be 79 (found %d)" % total_scenes)

	print("[3/6] Testing Category tabs, Pagination and CG Thumbnails ...")
	# Check Category EA (Sora)
	player._switch_cg_category("EA")
	await process_frame
	expect(player.app_cg_category == "EA", "Category should be EA")
	expect(player.cg_grid.get_child_count() == 8, "Page 1 of EA should have 8 cards")

	# Test Next Page
	player._next_cg_page()
	await process_frame
	expect(player.app_cg_page == 2, "Page should be 2")
	expect(player.cg_grid.get_child_count() == 8, "Page 2 of EA should have 8 cards")

	# Switch to EZ (Common) - 4 scenes
	player._switch_cg_category("EZ")
	await process_frame
	expect(player.app_cg_category == "EZ", "Category should be EZ")
	expect(player.cg_grid.get_child_count() == 4, "EZ should have 4 cards")

	# Switch back to EA
	player._switch_cg_category("EA")
	player.app_cg_page = 1
	player._populate_cg_grid()
	await process_frame

	print("[4/6] Testing Fullscreen CG Viewer and Variant Cycling ...")
	var ea_scenes: Array = player.cg_catalog["EA"]
	var scene0: Dictionary = ea_scenes[0] # EA01
	player._open_cg_fullscreen(scene0)
	await process_frame

	expect(player.cg_fullscreen_panel.visible, "Fullscreen panel must be visible")
	expect(player.fullscreen_current_variants.size() == 8, "EA01 should have 8 variants")
	expect(player.fullscreen_variant_index == 0, "Initial variant index should be 0")
	var initial_tex = player.fullscreen_cg_rect.texture
	expect(initial_tex != null, "Fullscreen texture should be loaded")
	print("  EA01 Variant 0 texture: %dx%d" % [initial_tex.get_width(), initial_tex.get_height()])

	# Advance to next variant
	player._next_cg_variant()
	expect(player.fullscreen_variant_index == 1, "Variant index should be 1 after next")
	print("  EA01 Variant 1: %s" % player.fullscreen_info_label.text)

	# Cycle back
	player._prev_cg_variant()
	expect(player.fullscreen_variant_index == 0, "Variant index should be 0 after prev")

	# Close fullscreen
	player._close_cg_fullscreen()
	expect(not player.cg_fullscreen_panel.visible, "Fullscreen panel should be hidden")
	print("  Fullscreen CG viewer passed successfully.")

	print("[5/6] Testing BGM Jukebox Mode & Audio Playback ...")
	player._switch_app_mode("bgm")
	await process_frame

	expect(player.app_mode == "bgm", "Mode should be bgm")
	expect(player.bgm_jukebox_container.visible, "Bgm jukebox container should be visible")
	expect(player.bgm_track_buttons.size() == 22, "Should have 22 BGM track buttons")

	# Play track 0: BGM01.mio
	player._play_jukebox_bgm(0)
	expect(player.current_bgm_track_index == 0, "Track index should be 0")
	expect(player.bgm_player.stream != null, "BGM player stream should not be null")
	print("  Now playing: %s" % player.bgm_now_playing_label.text.replace("\n", " - "))

	# Next track: BGM02.mio
	player._next_jukebox_bgm()
	expect(player.current_bgm_track_index == 1, "Track index should be 1")

	# Volume test
	player._on_bgm_vol_changed(65.0)
	expect(player.bgm_vol_label.text == "65%", "BGM volume label should be 65%")

	# Stop track
	player._stop_jukebox_bgm()
	expect(not player.bgm_player.playing, "BGM player should be stopped")

	# Close the gallery while a jukebox track is playing.
	player._play_jukebox_bgm(1)
	player.app_close_btn.emit_signal("pressed")
	expect(not player.is_appreciation_open, "is_appreciation_open should be false")
	expect(player.is_title_mode, "Should remain in title mode")
	expect(player.native_title_layer.visible, "Closing gallery must restore the native title")
	for frame in range(120):
		if player.host.current_bgm.to_lower() == "bgm07.mio":
			break
		await process_frame
	expect(player.host.current_bgm.to_lower() == "bgm07.mio", "Closing gallery must restore the title theme")
	expect(player.current_bgm_track_index == -1, "Title theme must not appear as a selected jukebox track")
	print("  BGM Jukebox passed successfully.")

	print("[6/6] Verifying Android candidate VFS path resolution & pristine game files ...")
	var host = player.host
	var vfs_title = host.find_vfs_entry("FRM_0611.eri")
	expect(not vfs_title.is_empty(), "FRM_0611.eri must be resolved in VFS")
	var vfs_sound = host.find_vfs_entry("BGM01.mio")
	expect(not vfs_sound.is_empty(), "BGM01.mio must be resolved in VFS")
	var archive_title = host.get_or_open_archive("title.noa")
	expect(archive_title != null, "title.noa must be opened via get_or_open_archive")

	for rel_path in EXPECTED_HASHES.keys():
		var full_path := game_dir.path_join(rel_path)
		var file := FileAccess.open(full_path, FileAccess.READ)
		expect(file != null, "Cannot read file: %s" % full_path)
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		while file.get_position() < file.get_length():
			var chunk := file.get_buffer(65536)
			ctx.update(chunk)
		var actual := ctx.finish().hex_encode()
		var expected: String = EXPECTED_HASHES[rel_path]
		expect(actual == expected, "SHA-256 mismatch for %s: expected %s, got %s" % [rel_path, expected, actual])

	print("  Original game archives remain 100% pristine and unmodified.")
	TestSupport.remove_test_saves(test_save_dir)
	finish_success("PASS Appreciation, Fullscreen CG Gallery and BGM Jukebox Smoke Test!")
