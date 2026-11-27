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
	var sound_path := game_dir.path_join("sound.noa")

	var csx_hash_before := FileAccess.get_sha256(csx_path)
	var data1_hash_before := FileAccess.get_sha256(data1_path)
	var voice_hash_before := FileAccess.get_sha256(voice_path)
	var sound_hash_before := FileAccess.get_sha256(sound_path)

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

	var bustup_manager: Variant = adv.get_field("bustupMan")
	var bustup_array: Variant = bustup_manager.get_field("spr") if bustup_manager is CsxVMReader.CsxInstance else null
	var bustup_sprite: Variant = bustup_array[0] if bustup_array is Array and not bustup_array.is_empty() else null
	var legacy_bustup_rect: TextureRect = player.bustup_rects[0]
	print("  Bustup 0 HostSprite:")
	if bustup_sprite is CsxHostClass.HostSprite:
		print("    visible: ", bustup_sprite.is_visible)
		print("    position: ", bustup_sprite.position)
		print("    size: ", bustup_sprite.texture.get_size() if bustup_sprite.texture != null else Vector2.ZERO)
		print("    in HostWindow tree: ", player._host_window_contains_sprite(bustup_sprite))
	expect(bustup_sprite is CsxHostClass.HostSprite, "SetBustup must create the original HostSprite instance")
	if bustup_sprite is CsxHostClass.HostSprite:
		expect(bustup_sprite.is_visible and bustup_sprite.texture != null, "Bustup HostSprite must be visible with its decoded resource")
		expect(bustup_sprite.texture.get_size() == Vector2(588, 528), "Bustup texture must match CA02_01M (588, 528)")
		expect(Vector2(bustup_sprite.position.x - bustup_sprite.rev_center.x, bustup_sprite.position.y - bustup_sprite.rev_center.y) == Vector2(106, 122), "Bustup HostSprite must be centered at (106, 122)")
		expect(player._host_window_contains_sprite(bustup_sprite), "Story compositor must own the bustup HostSprite instead of the legacy layer")
	expect(not legacy_bustup_rect.visible, "Legacy bustup fallback must stay hidden when the HostWindow compositor owns the sprite")
	print("  Bustup is retained and displayed by the original HostWindow/HostSprite path.")

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

	print("[4/5] Testing QuickSave, QuickLoad, audio restore and Video Fallback ...")
	# Use a real archive-backed BGM so the CSX Save path records a non-empty
	# playBgm value and the subsequent ScenarioLoop can exercise audio restore.
	var bgm_start: Dictionary = vm.call_function_sync("ScPlayBgm", ["BGM07"], 100_000)
	expect(bgm_start.get("ok", false), "Original ScPlayBgm must start a real BGM before saving")
	expect(host.current_bgm.to_lower() == "bgm07.mio" and player.bgm_player.playing, "BGM07.mio must be active before the save snapshot")
	# QuickSave captures the live CSX scenario object through the original script path.
	var sc_obj_before_save: Variant = vm.globals_by_name.get("scObj", null)
	expect(sc_obj_before_save is CsxVMReader.CsxInstance, "scObj must be an original CSX instance before saving")
	var saved_scenario_call := str(sc_obj_before_save.get_field("scenarioCall"))
	expect(not saved_scenario_call.is_empty(), "Story scenarioCall must identify the active resume point before saving")
	expect(player.save_to_slot(0), "QuickSave through AdvPlayer must succeed")
	expect(str(sc_obj_before_save.get_field("playBgm")).to_lower() == "bgm07", "Original CSX Save must snapshot the active BGM base name")
	var saved_env_se: Variant = sc_obj_before_save.get_field("playEnvSe")
	expect(saved_env_se is Array and saved_env_se.has("SE270"), "Original CSX GetPlayEnvSeList must save the active environmental sound tag")
	var qsave_path := host.get_save_path("QSave.dat")
	var qthumb_path := host.get_thumbnail_path("QSave.dat")
	expect(FileAccess.file_exists(qsave_path), "QSave.dat must exist on disk")
	expect(FileAccess.file_exists(qthumb_path), "QSave.png thumbnail must exist on disk")
	print("  QuickSave created: ", qsave_path, " and thumbnail: ", qthumb_path)

	# Change only in-memory CSX state after the serialized save; loading must
	# recover the actual saved Story continuation before the next VM frame.
	var mutation_marker := "__A04_TEST_MUTATION__"
	sc_obj_before_save.set_field("scenarioCall", mutation_marker)
	expect(sc_obj_before_save.get_field("scenarioCall") == mutation_marker, "Post-save probe mutation must be applied in memory")
	expect(player.load_from_slot(0), "QuickLoad through AdvPlayer must succeed")
	var restored_sc_obj: Variant = vm.globals_by_name.get("scObj", null)
	expect(restored_sc_obj is CsxVMReader.CsxInstance, "QuickLoad must restore scObj as a CSX instance")
	expect(str(restored_sc_obj.get_field("scenarioCall")) == saved_scenario_call, "QuickLoad must restore the saved Story continuation rather than the post-save mutation")
	# The synchronous CSX load sets isLoad before AdvPlayer re-enters ScenarioLoop.
	expect(restored_sc_obj.get_field("isLoad") == -1, "scObj.isLoad should be -1 immediately after quick load")
	expect(str(restored_sc_obj.get_field("playBgm")).to_lower() == "bgm07", "QuickLoad must restore the CSX-saved active BGM base name")
	var restored_env_se: Variant = restored_sc_obj.get_field("playEnvSe")
	expect(restored_env_se is Array and restored_env_se.has("SE270"), "QuickLoad must restore the tagged environmental sound name")
	expect(vm.functions.has("ScenarioLoop") and vm.ip == int(vm.functions.get("ScenarioLoop", -1)), "AdvPlayer must resume from the original ScenarioLoop after loading")
	expect(vm.pending_call_args.size() == 1 and str(vm.pending_call_args[0]) == saved_scenario_call, "ScenarioLoop must receive the saved continuation as its argument")
	expect(vm.call_stack.is_empty() and vm.eval_stack.is_empty(), "ScenarioLoop load restart must clear stale interpreter stacks")
	print("  QuickLoad restored scObj.scenarioCall='%s', BGM='%s', set isLoad=-1, and re-entered ScenarioLoop" % [saved_scenario_call, str(restored_sc_obj.get_field("playBgm"))])
	await process_frame
	expect(host.current_bgm.to_lower() == "bgm07.mio" and player.bgm_player.playing, "Resumed original ScenarioLoop must restart the saved BGM07.mio")
	expect(host.current_env_se.to_lower() == "se270.mio" and host.env_se_player.playing, "Resumed original ScenarioLoop must restart the saved SE270.mio environmental sound")

	# Movie host lifecycle: OpenMovie selects the source; PlayMovie starts it.
	var movie_sprite := CsxHostClass.HostSprite.new(9801, host)
	var movie_requests: Array[String] = []
	var movie_modes: Array[int] = []
	var stop_requests := [0]
	host.movie_requested.connect(func(filename: String, mode: int, _rewind_frame: int, _end_frame: int, _repeat: bool, _sprite_id: int):
		movie_requests.append(filename)
		movie_modes.append(mode)
	)
	host.movie_stop_requested.connect(func(): stop_requests[0] += 1)
	var unopened_movie_sprite := CsxHostClass.HostSprite.new(9800, host)
	unopened_movie_sprite.filename = "opening.mei"
	expect(unopened_movie_sprite.play_movie(0) == 0 and movie_requests.is_empty(), "PlayMovie must fail without a successful OpenMovie even when a filename is set")
	expect(movie_sprite.open_movie("opening.mei") == 1, "OpenMovie must retain the original MEI path")
	expect(movie_requests.is_empty(), "OpenMovie must not start playback before PlayMovie")
	movie_sprite.release()
	expect(host.movie_opened and host.movie_owner_instance_id == movie_sprite.get_instance_id(), "Sprite.Release must not close an explicitly opened MovieSprite resource")
	expect(movie_sprite.play_movie(0x403) == 1 and movie_requests == ["opening.mei"] and movie_modes == [0x403], "PlayMovie must dispatch the selected original movie and native mode flags to the host")
	movie_sprite.stop_movie()
	expect(stop_requests[0] == 1 and not host.is_movie_playing, "StopMovie must stop host playback and clear its state")
	movie_sprite.close_movie()
	expect(movie_sprite.filename.is_empty() and stop_requests[0] == 2, "CloseMovie must stop playback and release the selected path")
	# The host routes original MEI through the in-process decoder only after the
	# owner successfully opens it, then releases it through MovieSprite methods.
	expect(movie_sprite.open_movie("opening.mei") == 1, "OpenMovie must select the original MEI before native playback")
	expect(movie_sprite.play_movie(0) == 1 and host.is_movie_playing and player.mei_movie_active, "PlayMovie must start native MEI playback for the opened original movie")
	movie_sprite.stop_movie()
	expect(not host.is_movie_playing and not player.mei_movie_active, "StopMovie must stop native MEI playback cleanly")
	movie_sprite.close_movie()
	print("  Native MEI movie lifecycle passed!")

	print("[5/5] Verifying original game files are 100% pristine and unmodified ...")
	var csx_hash_after := FileAccess.get_sha256(csx_path)
	var data1_hash_after := FileAccess.get_sha256(data1_path)
	var voice_hash_after := FileAccess.get_sha256(voice_path)
	var sound_hash_after := FileAccess.get_sha256(sound_path)

	expect(csx_hash_before == csx_hash_after, "CSX file must remain completely unmodified!")
	expect(data1_hash_before == data1_hash_after, "data1.noa must remain completely unmodified!")
	expect(voice_hash_before == voice_hash_after, "voice.noa must remain completely unmodified!")
	expect(sound_hash_before == sound_hash_after, "sound.noa must remain completely unmodified!")
	print("  Hashes match perfectly: CSX and NOA files are completely untouched.")

	if player.has_method("_shutdown_runtime_session"):
		player.call("_shutdown_runtime_session")
	expect(bool(player.get("runtime_shutdown")), "AdvPlayer runtime must shut down before test teardown")
	player.free()
	await process_frame
	await create_timer(0.25).timeout
	TestSupport.remove_test_saves(test_save_dir)
	finish_success("PASS All Bustup, Backlog, Save/Load and Video Integration Smoke Tests!")
