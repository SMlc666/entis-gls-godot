extends SceneTree

const CsxHostClass = preload("res://scripts/csx_host.gd")
const TestSupport = preload("res://tests/test_support.gd")

const START_SCENARIO := "00_Z000"
const CONFIG_COMMAND := "ID_CONFIG"
const CONFIG_PAGE := "ID_PAGE_CONFIG"
const NATIVE_CONFIG_RUN := "ConfigWindow::run"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game_dir := TestSupport.resolve_game_dir(OS.get_cmdline_user_args())
	if game_dir.is_empty():
		_fail("Pass the original game directory after --")
		return
	var original_hashes := _hash_original_inputs(game_dir)
	if original_hashes.is_empty():
		_fail("Could not hash the original CSX/NOA inputs")
		return

	var scene = load("res://scenes/adv_player.tscn")
	if scene == null:
		_fail("Could not load AdvPlayer scene")
		return
	var player = scene.instantiate()
	player.game_dir = game_dir
	player.start_in_title = false
	player.start_scenario = START_SCENARIO
	var save_dir: String = TestSupport.configure_player_saves(player, "native_story_config")
	root.add_child(player)
	for frame in range(600):
		if player.is_initialized and player.vm != null and player.host != null:
			break
		await process_frame
	if not player.is_initialized or not TestSupport.uses_isolated_saves(player.host, save_dir):
		await _fail_after_cleanup(player, save_dir, original_hashes, "AdvPlayer did not initialize with isolated saves")
		return

	var story_window: CsxHostClass.HostWindow = null
	var config_sprite: CsxHostClass.HostSprite = null
	for frame in range(900):
		await process_frame
		if player.vm.data_vars.size() > 4:
			var active_window: Variant = player.vm.data_vars[4].get("value", null)
			if active_window is CsxHostClass.HostWindow:
				story_window = active_window
				config_sprite = _find_button(story_window.root_sprites, CONFIG_COMMAND)
		if (
			story_window != null
			and config_sprite != null
			and config_sprite.is_enabled
			and player.host.is_waiting_input
			and _stack_has(player.vm.call_stack, "AdvScreen::hitret")
		):
			break
	if story_window == null or config_sprite == null or not player.host.is_waiting_input or not _stack_has(player.vm.call_stack, "AdvScreen::hitret"):
		var failure_message := "Original Story quick menu did not reach the ID_CONFIG input wait (button=%s waiting=%s stack=%s)" % [str(config_sprite), str(player.host.is_waiting_input), _stack_names(player.vm.call_stack)]
		await _fail_after_cleanup(player, save_dir, original_hashes, failure_message)
		return

	var config_wrapper: Control = player.host_sprite_controls.get(config_sprite.get_instance_id(), null)
	var config_button: TextureButton = config_wrapper.get_node_or_null("NativeButton") as TextureButton if config_wrapper != null else null
	if config_button == null or not config_button.is_visible_in_tree() or config_button.disabled:
		await _fail_after_cleanup(player, save_dir, original_hashes, "Original Story ID_CONFIG is not interactive")
		return
	if player.host.pending_command_count() != 0:
		await _fail_after_cleanup(player, save_dir, original_hashes, "Expected an empty native command queue before clicking ID_CONFIG")
		return

	var story_window_id := story_window.get_instance_id()
	var config_sprite_id := config_sprite.get_instance_id()
	var command_scope: int = player.host.current_command_scope()
	config_button.pressed.emit()
	var queued_event: Dictionary = player.host.peek_command_for_window(story_window_id)
	if (
		queued_event.get("id", "") != CONFIG_COMMAND
		or queued_event.get("full_id", "") != CONFIG_COMMAND
		or int(queued_event.get("window_id", -1)) != story_window_id
		or int(queued_event.get("source_sprite_id", -1)) != config_sprite_id
		or int(queued_event.get("scope_generation", -1)) != command_scope
		or player.host.is_waiting_input
	):
		await _fail_after_cleanup(player, save_dir, original_hashes, "Native ID_CONFIG activation did not enqueue the correctly owned command and wake the Story VM: %s" % str(queued_event))
		return

	var config_page: CsxHostClass.HostSprite = null
	var native_config_started := false
	for frame in range(600):
		await process_frame
		native_config_started = _stack_has(player.vm.call_stack, NATIVE_CONFIG_RUN)
		config_page = _find_form_page(story_window.root_sprites, CONFIG_PAGE)
		if config_page != null and native_config_started and not player.host.is_native_command_dispatch_pending(story_window_id):
			break
	if config_page == null or not native_config_started or player.host.is_native_command_dispatch_pending(story_window_id):
		var active_command: Dictionary = player.host.peek_command_for_window(story_window_id)
		var failure_message := "Original Story ID_CONFIG did not complete dispatch into ConfigWindow::run / ID_PAGE_CONFIG (page=%s stack=%s waiting=%s dispatch_pending=%s queued=%s vm_error='%s' host_error='%s' ip=0x%X)" % [str(config_page), _stack_names(player.vm.call_stack), str(player.host.is_waiting_input), str(player.host.is_native_command_dispatch_pending(story_window_id)), str(active_command), player.vm.last_error, player.host.last_error, player.vm.ip]
		await _fail_after_cleanup(player, save_dir, original_hashes, failure_message)
		return

	var config_page_wrapper: Control = player.host_sprite_controls.get(config_page.get_instance_id(), null)
	if config_page_wrapper == null or not config_page_wrapper.is_visible_in_tree():
		await _fail_after_cleanup(player, save_dir, original_hashes, "Original ID_PAGE_CONFIG did not project as a visible HostWindow page")
		return
	if config_page_wrapper.size != Vector2(532, 552) or config_page_wrapper.position != Vector2(134, 24):
		var failure_message := "Original ConfigWindow page geometry changed: position=%s size=%s" % [str(config_page_wrapper.position), str(config_page_wrapper.size)]
		await _fail_after_cleanup(player, save_dir, original_hashes, failure_message)
		return
	if player.is_title_mode or player.is_config_open:
		await _fail_after_cleanup(player, save_dir, original_hashes, "Story ID_CONFIG must use the original CSX ConfigWindow, not the title or project-owned fallback state")
		return
	if player.vm.last_error.contains("File::IsExisting") or player.host.last_error.contains("VFS entry not found: .mio"):
		var failure_message := "The optional empty voice .mio existence probe must not leave an error behind (vm='%s' host='%s')" % [player.vm.last_error, player.host.last_error]
		await _fail_after_cleanup(player, save_dir, original_hashes, failure_message)
		return

	await _cleanup(player, save_dir)
	if not _original_inputs_unchanged(original_hashes):
		_fail("Original CSX or NOA inputs changed during the read-only Story ConfigWindow smoke")
		return
	print("PASS Original Story ID_CONFIG -> AdvScreen::hitret -> ConfigWindow::run -> visible ID_PAGE_CONFIG; event ownership, dispatch wait, and optional .mio probe verified; original hashes unchanged")
	quit(0)

func _find_button(sprites: Array, button_id: String) -> CsxHostClass.HostSprite:
	for sprite: Variant in sprites:
		if sprite is CsxHostClass.HostSprite:
			if sprite.is_button and sprite.btn_id == button_id:
				return sprite
			var nested := _find_button(sprite.children, button_id)
			if nested != null:
				return nested
	return null

func _find_form_page(sprites: Array, page_id: String) -> CsxHostClass.HostSprite:
	for sprite: Variant in sprites:
		if sprite is CsxHostClass.HostSprite:
			if str(sprite.fields.get("form_page_id", "")) == page_id:
				return sprite
			var nested := _find_form_page(sprite.children, page_id)
			if nested != null:
				return nested
	return null

func _stack_has(stack: Array, function_name: String) -> bool:
	for frame: Variant in stack:
		if frame.name == function_name:
			return true
	return false

func _stack_names(stack: Array) -> String:
	var names: PackedStringArray = []
	for frame: Variant in stack:
		names.append(str(frame.name))
	return " > ".join(names)

func _hash_original_inputs(game_dir: String) -> Dictionary:
	var paths := [
		game_dir.path_join("system/yosuga.csx"),
		game_dir.path_join("data1.noa"),
		game_dir.path_join("sound.noa"),
		game_dir.path_join("system/title.noa"),
		game_dir.path_join("system/frame.noa"),
		game_dir.path_join("system/option.noa"),
	]
	var hashes: Dictionary = {}
	for path: String in paths:
		if not FileAccess.file_exists(path):
			return {}
		hashes[path] = FileAccess.get_sha256(path)
	return hashes

func _original_inputs_unchanged(hashes: Dictionary) -> bool:
	for path: String in hashes.keys():
		if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != hashes[path]:
			return false
	return true

func _fail_after_cleanup(player: Node, save_dir: String, hashes: Dictionary, message: String) -> void:
	await _cleanup(player, save_dir)
	if not hashes.is_empty() and not _original_inputs_unchanged(hashes):
		message += " (original input hash mismatch after cleanup)"
	_fail(message)

func _cleanup(player: Node, save_dir: String) -> void:
	if is_instance_valid(player):
		if player.has_method("_shutdown_runtime_session"):
			player.call("_shutdown_runtime_session")
		player.free()
		await process_frame
		await create_timer(0.25).timeout
	TestSupport.remove_test_saves(save_dir)

func _fail(message: String) -> void:
	printerr("FAIL ", message)
	quit(1)
