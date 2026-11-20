extends "res://tests/smoke_test_base.gd"

const NoaArchiveReader = preload("res://scripts/noa_archive.gd")
const CsxVMReader = preload("res://scripts/csx_vm.gd")
const CsxHostClass = preload("res://scripts/csx_host.gd")
const TestSupport = preload("res://tests/test_support.gd")

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game_dir := TestSupport.resolve_game_dir(OS.get_cmdline_user_args())
	if game_dir.is_empty():
		printerr("Usage: set YOSUGA_GAME_DIR or pass the game directory after --")
		quit(2)
		return

	var csx_path := game_dir.path_join("system/yosuga.csx")
	var data1_path := game_dir.path_join("data1.noa")
	var voice_path := game_dir.path_join("voice.noa")

	var csx_hash_before := FileAccess.get_sha256(csx_path)
	var data1_hash_before := FileAccess.get_sha256(data1_path)
	var voice_hash_before := FileAccess.get_sha256(voice_path)

	print("[1/5] Instantiating AdvPlayer scene with bustups & backlog ...")
	var scene_res = load("res://scenes/adv_player.tscn")
	if scene_res == null:
		printerr("FAIL Could not load adv_player.tscn")
		quit(1)
		return

	var player = scene_res.instantiate()
	player.game_dir = game_dir
	var test_save_dir: String = TestSupport.new_save_dir("bustup")
	player.save_dir_override = test_save_dir
	root.add_child(player)

	# Process frames until engine starts
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

	# Advance 5 lines of dialogue
	for _i in range(5):
		player._advance_line()
		await process_frame
		await process_frame

	print("[2/5] Testing Bustup Rendering & Positioning ...")
	# Invoke SetBustup on slot 0 and run AdvScreen::update
	var vm: CsxVMReader = player.vm
	var host: CsxHostClass = player.host
	var adv = vm.globals_by_name.get("adv", null)
	expect(adv != null, "AdvScreen instance must exist in vm globals")

	var set_res := vm.call_function_sync("SetBustup", ["CA02_01M", 0, 0], 100_000)
	expect(set_res.get("ok", false), "SetBustup call must succeed")
	var up_res := vm.call_function_sync("AdvScreen::update", [adv, 0, 0], 100_000)
	expect(up_res.get("ok", false), "AdvScreen::update call must succeed")

	# Let process update bustup TextureRects
	await process_frame
	await process_frame

	var b_rect: TextureRect = player.bustup_rects[0]
	print("  Bustup 0 state:")
	print("    visible: ", b_rect.visible)
	print("    size: ", b_rect.size)
	print("    position: ", b_rect.position)
	print("    modulate.a: ", b_rect.modulate.a)
	print("    has texture: ", b_rect.texture != null)

	expect(b_rect.visible == true, "Bustup slot 0 must be visible")
	expect(b_rect.texture != null, "Bustup slot 0 must have a texture")
	expect(b_rect.size == Vector2(588, 528), "Bustup size should match CA02_01M (588, 528)")
	expect(b_rect.position == Vector2(106, 122), "Bustup position should be centered at (106, 122)")
	expect(is_equal_approx(b_rect.modulate.a, 1.0), "Bustup opacity must be 1.0 (fully opaque)")
	print("  Bustup slot 0 verified successfully!")

	print("[3/5] Testing Message Backlog Modal UI ...")
	expect(not player.is_backlog_open, "Backlog should initially be closed")
	expect(not player.backlog_panel.visible, "Backlog panel should initially be hidden")

	# Open backlog
	player._toggle_backlog()
	await process_frame
	expect(player.is_backlog_open, "Backlog should be marked open")
	expect(player.backlog_panel.visible, "Backlog panel should be visible")
	var item_count: int = player.backlog_vbox.get_child_count()
	print("  Backlog contains %d dialogue entries" % item_count)
	expect(item_count > 0, "Backlog should display recorded dialogues")

	# Close backlog
	player._toggle_backlog()
	await process_frame
	expect(not player.is_backlog_open, "Backlog should be closed after toggle")
	expect(not player.backlog_panel.visible, "Backlog panel should be hidden after toggle")
	print("  Backlog modal toggle and item list verified!")

	print("[4/5] Testing QuickSave, QuickLoad and Video Fallback ...")
	# Quick Save
	player._on_quick_save()
	var qsave_path := host.get_save_path("QSave.dat")
	var qthumb_path := host.get_thumbnail_path("QSave.dat")
	expect(FileAccess.file_exists(qsave_path), "QSave.dat must exist on disk")
	expect(FileAccess.file_exists(qthumb_path), "QSave.png thumbnail must exist on disk")
	print("  QuickSave created: ", qsave_path, " and thumbnail: ", qthumb_path)

	# Quick Load
	player._on_quick_load()
	await process_frame
	var scObj = vm.global_vars[4]["value"]
	expect(scObj.fields.get("isLoad") == -1, "scObj.isLoad should be -1 after quick load")
	print("  QuickLoad restored scenario state successfully!")

	# Video Fallback test
	player._on_movie_requested("opening.mei")
	expect(not host.is_movie_playing, "Proprietary MEI movie should safely fallback/skip without hanging")
	print("  Movie fallback handled gracefully!")

	print("[5/5] Verifying original game files are 100% pristine and unmodified ...")
	var csx_hash_after := FileAccess.get_sha256(csx_path)
	var data1_hash_after := FileAccess.get_sha256(data1_path)
	var voice_hash_after := FileAccess.get_sha256(voice_path)

	expect(csx_hash_before == csx_hash_after, "CSX file must remain completely unmodified!")
	expect(data1_hash_before == data1_hash_after, "data1.noa must remain completely unmodified!")
	expect(voice_hash_before == voice_hash_after, "voice.noa must remain completely unmodified!")
	print("  Hashes match perfectly: CSX and NOA files are completely untouched.")

	TestSupport.remove_test_saves(test_save_dir)
	finish_success("PASS All Bustup, Backlog, Save/Load and Video Integration Smoke Tests!")
