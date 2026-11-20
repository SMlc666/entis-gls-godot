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

	var csx_hash_before := FileAccess.get_sha256(csx_path)
	var data1_hash_before := FileAccess.get_sha256(data1_path)

	print("[1/5] Instantiating AdvPlayer scene for interactive choice test ...")
	var scene_res = load("res://scenes/adv_player.tscn")
	if scene_res == null:
		printerr("FAIL Could not load adv_player.tscn")
		quit(1)
		return

	var player = scene_res.instantiate()
	player.game_dir = game_dir
	var test_save_dir: String = TestSupport.configure_player_saves(player, "choice_interaction")
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
	print("  AdvPlayer initialized successfully.")

	print("[2/5] Enabling gameClear flag and switching target to sc00_Z005 ...")
	# Call OnGameClear so all route choices are active
	player.vm.call_function_sync("OnGameClear", [])

	# Set VM to execute ScenarioLoop with 00_Z005
	player.vm.ip = player.vm.functions["ScenarioLoop"]
	player.vm.pending_call_args = ["00_Z005"]
	player.vm.pending_return_ip = -1
	player.vm.call_stack.clear()
	player.vm.eval_stack.clear()
	player.host.is_waiting_input = false
	player.host.is_waiting_choice = false
	player.host.selected_choice = -1
	player.host.current_choices.clear()

	print("[3/5] Advancing dialogue until choice selection prompt appears ...")
	var choice_reached := false
	var advance_count := 0
	const CHOICE_FRAME_BUDGET := 1200
	for f in range(CHOICE_FRAME_BUDGET):
		await process_frame
		if player.host.is_waiting_choice:
			choice_reached = true
			print("  Choice prompt reached at frame %d!" % f)
			break
		if player.host.is_waiting_input:
			player._advance_line()
			advance_count += 1

	if not choice_reached:
		printerr("FAIL Did not reach interactive choice in %d frames (advanced %d times)" % [CHOICE_FRAME_BUDGET, advance_count])
		quit(1)
		return

	print("  Active choices recorded by host: %s" % str(player.host.current_choices))
	print("  Choice container visible: %s, button count: %d" % [
		player.choice_container.visible, player.choice_buttons.size()
	])

	if player.host.current_choices.size() < 2:
		printerr("FAIL Expected at least 2 choices, got %d" % player.host.current_choices.size())
		quit(1)
		return

	var choice_0_text: String = player.choice_buttons[0].text
	var choice_1_text: String = player.choice_buttons[1].text
	print("  Button 0: '%s'" % choice_0_text)
	print("  Button 1: '%s'" % choice_1_text)

	if not ("敲门" in choice_0_text):
		printerr("FAIL Expected '敲门' in choice 0, got '%s'" % choice_0_text)
		quit(1)
		return

	print("[4/5] Simulating player clicking Choice 0 ('敲门') and verifying branch execution ...")
	var history_len_before: int = player.host.text_history.size()
	# Click Choice 0
	player.choice_buttons[0].pressed.emit()

	# Process frames to let scenario branch execute
	for f in range(60):
		await process_frame
		if player.host.is_waiting_input:
			player._advance_line()

	print("  Choice container visible after selection: %s" % player.choice_container.visible)
	print("  is_waiting_choice after selection: %s" % player.host.is_waiting_choice)
	print("  Total dialogue history lines: %d (new lines: %d)" % [
		player.host.text_history.size(), player.host.text_history.size() - history_len_before
	])

	# Check the new dialogue lines from the chosen branch
	var saw_knock_branch := false
	for i in range(history_len_before, player.host.text_history.size()):
		var line: Dictionary = player.host.text_history[i]
		var txt: String = line.get("text", "")
		print("  Post-choice dialogue: [%s] %s" % [line.get("speaker", ""), txt])
		if "敲" in txt or "门" in txt or "手" in txt or "声" in txt:
			saw_knock_branch = true
	if not saw_knock_branch:
		printerr("FAIL Choice 0 did not produce any expected knock/door branch dialogue")
		quit(1)
		return

	print("  Verified branch progression after interactive choice selection.")

	print("[5/5] Verifying original game files are 100% pristine and unmodified ...")
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
	print("PASS Choice Selection and Branch Execution Smoke Test")
	quit(0)
