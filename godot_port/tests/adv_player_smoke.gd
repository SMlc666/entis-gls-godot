extends SceneTree

const NoaArchiveReader = preload("res://scripts/noa_archive.gd")
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
	var voice_path := game_dir.path_join("voice.noa")
	var sound_path := game_dir.path_join("sound.noa")

	var csx_hash_before := FileAccess.get_sha256(csx_path)
	var data1_hash_before := FileAccess.get_sha256(data1_path)

	print("[1/4] Instantiating AdvPlayer scene ...")
	var scene_res = load("res://scenes/adv_player.tscn")
	if scene_res == null:
		printerr("FAIL Could not load adv_player.tscn")
		quit(1)
		return

	var player = scene_res.instantiate()
	player.game_dir = game_dir
	var test_save_dir: String = TestSupport.configure_player_saves(player, "adv_player")
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
		printerr("FAIL AdvPlayer initialization must use isolated test saves")
		quit(1)
		return
	print("  AdvPlayer initialized in %d frames" % wait_frames)

	print("[2/4] Advancing scenario lines via simulated player clicks ...")
	var dialogues_seen: Array[Dictionary] = []
	var native_outputs: Array[Dictionary] = []
	var native_names: Array[Dictionary] = []
	player.host.message_output.connect(func(sprite):
		if sprite.message_style.get("id") == "ID_FONT_NAME" and not sprite.text_content.is_empty():
			native_names.append({"text": sprite.text_content, "displayed": player.speaker_label.text, "size": player.speaker_label.get_theme_font_size("font_size")})
		if sprite.message_style.get("id") == "ID_FONT_MESSAGE" and not sprite.text_content.is_empty():
			var label: RichTextLabel = player.message_label
			native_outputs.append({
				"raw": sprite.text_content,
				"displayed": label.text,
				"position_matches": label.position == Vector2(sprite.position - sprite.rev_center),
				"font_matches": label.get_theme_font_size("normal_font_size") == int(sprite.message_style["font"]["size"]),
				"shadow_matches": label.get_theme_constant("shadow_offset_y") == int(sprite.message_style["shadow"]["y"]),
			})
	)
	var elapsed := 0.0
	var saw_activation_poll := false
	var saw_dialogue_scale := false
	while (native_outputs.is_empty() or not player.host.is_waiting_input) and elapsed < 8.0:
		await process_frame
		elapsed += player.get_process_delta_time()
		saw_activation_poll = saw_activation_poll or player.host.yield_for_sprite_activation
		saw_dialogue_scale = saw_dialogue_scale or (player.dialogue_box.scale.x < 1.0 and player.dialogue_box.scale.x >= 0.95)
	if native_outputs.is_empty() or not player.host.is_waiting_input:
		printerr("FAIL The opening animation must finish without a click and reach the first dialogue wait")
		quit(1)
		return
	var first_message := native_outputs.size()
	for frame in range(3):
		await process_frame
	if native_outputs.size() != first_message or not player.host.is_waiting_input:
		printerr("FAIL The dialogue wait must hold until input arrives")
		quit(1)
		return

	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	player._unhandled_input(enter)
	elapsed = 0.0
	while native_outputs.size() == first_message and elapsed < 5.0:
		await process_frame
		elapsed += player.get_process_delta_time()
	if native_outputs.size() == first_message:
		printerr("FAIL One Enter press must advance to the next native message")
		quit(1)
		return

	var total_frames := 0
	while dialogues_seen.size() < 16 and total_frames < 800:
		await process_frame
		total_frames += 1

		if player.host != null:
			while dialogues_seen.size() < player.host.text_history.size():
				var entry: Dictionary = player.host.text_history[dialogues_seen.size()]
				dialogues_seen.append(entry)
				print("  Line %d: [%s] %s%s" % [
					dialogues_seen.size(),
					entry.get("speaker", ""),
					entry.get("text", ""),
					(" (voice: %s)" % entry.get("voice")) if not entry.get("voice", "").is_empty() else ""
				])

		saw_activation_poll = saw_activation_poll or player.host.yield_for_sprite_activation
		saw_dialogue_scale = saw_dialogue_scale or (player.dialogue_box.scale.x < 1.0 and player.dialogue_box.scale.x >= 0.95)
		if player.host != null and player.host.is_waiting_input:
			player._advance_line()

	print("  Observed %d dialogue lines in %d frames" % [dialogues_seen.size(), total_frames])
	print("  Debug state: is_running=%s is_halted=%s last_error='%s' is_waiting_input=%s ip=0x%X text_history_len=%d" % [
		player.is_running,
		player.vm.is_halted if player.vm else false,
		player.vm.last_error if player.vm else "",
		player.host.is_waiting_input if player.host else false,
		player.vm.ip if player.vm else 0,
		player.host.text_history.size() if player.host else 0
	])
	if dialogues_seen.size() < 10:
		printerr("FAIL Expected at least 10 dialogue lines, got %d" % dialogues_seen.size())
		quit(1)
		return

	print("[3/4] Verifying Visuals, Audio & UI state ...")
	# Check background texture
	if player.bg_rect.texture == null:
		printerr("FAIL Background texture is null")
		quit(1)
		return
	var tex_w: int = player.bg_rect.texture.get_width()
	var tex_h: int = player.bg_rect.texture.get_height()
	print("  Active Background Texture: %s (%dx%d)" % [player.host.current_bg, tex_w, tex_h])
	if tex_w != 800:
		printerr("FAIL Expected background width 800, got %d" % tex_w)
		quit(1)
		return

	# Check UI text matches current dialogue
	print("  Speaker label: '%s'" % player.speaker_label.text)
	print("  Message label: '%s'" % player.message_label.text)
	if player.message_label.text.is_empty():
		printerr("FAIL Message label is empty")
		quit(1)
		return

	if native_names.is_empty():
		printerr("FAIL Original script must output at least one speaker name")
		quit(1)
		return
	for name in native_names:
		if name["text"] != name["displayed"] or name["size"] != 32:
			printerr("FAIL The name label must follow the original MessageSprite")
			quit(1)
			return

	# The native message command must update the visible shell with its payload.
	if not saw_dialogue_scale:
		printerr("FAIL Expected the native dialogue box scale animation")
		quit(1)
		return
	if not saw_activation_poll:
		printerr("FAIL Expected to observe at least one native activation input poll")
		quit(1)
		return
	if native_outputs.size() < 10:
		printerr("FAIL Expected at least 10 native body text commands")
		quit(1)
		return
	const MESSAGE_PREFIX := "\\s:\\h:\\nb\\ni\\f:"
	for output in native_outputs:
		var raw: String = output["raw"]
		if not raw.begins_with(MESSAGE_PREFIX) or output["displayed"] != raw.trim_prefix(MESSAGE_PREFIX):
			printerr("FAIL Native body text must display without its control prefix")
			quit(1)
			return
		if not output["position_matches"] or not output["font_matches"] or not output["shadow_matches"]:
			printerr("FAIL Native body text must use the MessageSprite position, font size, and shadow")
			quit(1)
			return

	# Check audio players
	print("  EnvSE playing stream: %s" % str(player.env_se_player.stream))
	if player.env_se_player.stream == null:
		printerr("FAIL EnvSE stream was not assigned to audio player")
		quit(1)
		return

	# Check voice was assigned
	print("  Voice playing stream: %s" % str(player.voice_player.stream))
	if player.voice_player.stream == null:
		printerr("FAIL Voice stream was not assigned to voice audio player")
		quit(1)
		return

	print("[4/4] Verifying original game files are 100% pristine and unmodified ...")
	var csx_hash_after := FileAccess.get_sha256(csx_path)
	var data1_hash_after := FileAccess.get_sha256(data1_path)
	if csx_hash_before != csx_hash_after:
		printerr("FAIL CSX file hash changed! Modified original game files!")
		quit(1)
		return
	if data1_hash_before != data1_hash_after:
		printerr("FAIL data1.noa hash changed! Modified original game files!")
		quit(1)
		return
	print("  Hashes match perfectly: CSX and NOA files are completely untouched.")

	TestSupport.remove_test_saves(test_save_dir)
	print("PASS AdvPlayer Interactive VN Integration Smoke Test")
	quit(0)
