extends SceneTree

const CsxHostClass = preload("res://scripts/csx_host.gd")
const CsxVMReader = preload("res://scripts/csx_vm.gd")
const AdvPlayerScript = preload("res://scripts/adv_player.gd")
const TestSupport = preload("res://tests/test_support.gd")

const MESSAGE_STYLE_ID := "ID_FONT_MESSAGE"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _test_transformed_surface_geometry():
		quit(1)
		return
	if not _test_button_surface_opacity():
		quit(1)
		return
	var game_dir := TestSupport.resolve_game_dir(OS.get_cmdline_user_args())
	if game_dir.is_empty():
		printerr("FAIL Pass the original game directory after --")
		quit(2)
		return
	var csx_path := game_dir.path_join("system/yosuga.csx")
	var data_path := game_dir.path_join("data1.noa")
	var csx_hash := FileAccess.get_sha256(csx_path)
	var data_hash := FileAccess.get_sha256(data_path)

	var scene = load("res://scenes/adv_player.tscn")
	if scene == null:
		printerr("FAIL Could not load AdvPlayer scene")
		quit(1)
		return
	var player = scene.instantiate()
	player.game_dir = game_dir
	player.start_in_title = false
	player.start_scenario = "00_Z000"
	var save_dir: String = TestSupport.configure_player_saves(player, "native_story_compositor")
	root.add_child(player)
	for frame in range(600):
		if player.is_initialized and player.host != null and player.vm != null:
			break
		await process_frame
	if not player.is_initialized or not TestSupport.uses_isolated_saves(player.host, save_dir):
		printerr("FAIL AdvPlayer did not initialize with isolated saves")
		await _cleanup(player, save_dir)
		quit(1)
		return

	var latest_messages: Array[CsxHostClass.HostSprite] = []
	player.host.message_output.connect(func(sprite: CsxHostClass.HostSprite) -> void:
		if sprite.is_message_sprite and sprite.message_style.get("id", "") == MESSAGE_STYLE_ID and not sprite.display_text().is_empty():
			latest_messages.append(sprite)
	)
	var reached_wait := false
	for frame in range(600):
		await process_frame
		if not latest_messages.is_empty():
			var candidate: CsxHostClass.HostSprite = latest_messages.back()
			if player.host_sprite_controls.has(candidate.get_instance_id()):
				reached_wait = true
				break
	if not reached_wait:
		printerr("FAIL Original ScenarioLoop did not project its first body MessageSprite")
		await _cleanup(player, save_dir)
		quit(1)
		return

	var latest_message: CsxHostClass.HostSprite = latest_messages.back()
	for frame in range(4):
		await process_frame
	player._sync_host_window_canvas()
	if not player.story_window_compositor_active or not player.host_window_layer.visible:
		printerr("FAIL Story HostWindow tree was not selected as the active renderer")
		await _cleanup(player, save_dir)
		quit(1)
		return
	if player.dialogue_box.visible or player.bg_rect.visible:
		printerr("FAIL The legacy dialogue or background surface is still drawn under the original tree")
		await _cleanup(player, save_dir)
		quit(1)
		return

	var message_wrapper: Control = player.host_sprite_controls.get(latest_message.get_instance_id(), null)
	var message_label: RichTextLabel = message_wrapper.get_node_or_null("NativeText") if message_wrapper != null else null
	if message_wrapper == null or message_label == null:
		printerr("FAIL MessageSprite was not projected to a RichTextLabel wrapper")
		await _cleanup(player, save_dir)
		quit(1)
		return
	if message_label.get_parsed_text() != latest_message.display_text():
		printerr("FAIL Projected message text differs from the original MessageSprite")
		await _cleanup(player, save_dir)
		quit(1)
		return
	if message_label.visible_characters != latest_message.message_visible_count:
		printerr("FAIL Projected reveal count does not track MessageSprite state")
		await _cleanup(player, save_dir)
		quit(1)
		return
	if message_wrapper.position != Vector2(latest_message.position - latest_message.rev_center):
		printerr("FAIL Projected message position differs from HostSprite geometry")
		await _cleanup(player, save_dir)
		quit(1)
		return
	var original_message_style: Dictionary = latest_message.message_style.duplicate(true)
	latest_message.message_style = {"font": {"face": "DejaVu Sans", "size": "22"}}
	player._sync_host_window_canvas()
	if not message_label.has_theme_font_override("normal_font"):
		printerr("FAIL A named HostSprite font style was not applied")
		await _cleanup(player, save_dir)
		quit(1)
		return
	latest_message.message_style = {}
	player._sync_host_window_canvas()
	if message_label.has_theme_font_override("normal_font"):
		printerr("FAIL Resetting a HostSprite to the default style retained the old font override")
		await _cleanup(player, save_dir)
		quit(1)
		return
	latest_message.message_style = original_message_style
	player._sync_host_window_canvas()

	var window: CsxHostClass.HostWindow = player.vm.data_vars[4].get("value") as CsxHostClass.HostWindow
	var button_sprites: Array[CsxHostClass.HostSprite] = []
	for sprite: CsxHostClass.HostSprite in window.root_sprites:
		_collect_buttons(sprite, button_sprites)
	if button_sprites.size() < 10:
		printerr("FAIL Expected the original quick menu, close and voice buttons in the HostWindow tree")
		await _cleanup(player, save_dir)
		quit(1)
		return
	for sprite: CsxHostClass.HostSprite in button_sprites:
		var wrapper: Control = player.host_sprite_controls.get(sprite.get_instance_id(), null)
		if wrapper == null or wrapper.get_node_or_null("NativeButton") == null:
			printerr("FAIL Original button %s has no projected native button" % sprite.btn_id)
			await _cleanup(player, save_dir)
			quit(1)
			return

	var qsave_button: CsxHostClass.HostSprite = null
	for sprite: CsxHostClass.HostSprite in button_sprites:
		if sprite.btn_id == "ID_QSAVE":
			qsave_button = sprite
			break
	if qsave_button == null or not player.host.is_waiting_input:
		printerr("FAIL Story message did not reach an advance wait with its original quick-save command")
		await _cleanup(player, save_dir)
		quit(1)
		return
	var advance_ticks_before_command: int = player.host.advance_ticks
	var qsave_wrapper: Control = player.host_sprite_controls.get(qsave_button.get_instance_id(), null)
	var qsave_control: TextureButton = qsave_wrapper.get_node_or_null("NativeButton") if qsave_wrapper != null else null
	if qsave_control == null:
		printerr("FAIL Original ID_QSAVE has no projected TextureButton")
		await _cleanup(player, save_dir)
		quit(1)
		return
	qsave_control.pressed.emit()
	if player.host.pending_command_count() != 1:
		printerr("FAIL Native QSave activation did not enqueue exactly one bounded HostWindow event")
		await _cleanup(player, save_dir)
		quit(1)
		return
	if player.host.is_waiting_input or player.host.advance_ticks != advance_ticks_before_command:
		printerr("FAIL Native HostWindow command did not wake the VM independently of dialogue advance")
		await _cleanup(player, save_dir)
		quit(1)
		return
	var story_window: CsxHostClass.HostWindow = player.vm.data_vars[4].get("value") as CsxHostClass.HostWindow
	var queued_command: Dictionary = player.host.peek_command_for_window(story_window.get_instance_id())
	if queued_command.get("id") != "ID_QSAVE" or int(queued_command.get("window_id", -1)) != story_window.get_instance_id() or int(queued_command.get("source_sprite_id", -1)) != qsave_button.get_instance_id():
		printerr("FAIL Native command lost its original ID, window owner, or sprite owner")
		await _cleanup(player, save_dir)
		quit(1)
		return
	# This compositor smoke checks the producer contract. The separate original
	# selection smoke drives a queued command through the full CSX wait/return path.
	player.host.begin_command_scope("story-smoke-input-reset")
	player.host.is_waiting_input = true
	# A keyboard/programmatic command can leave a one-shot cursor point unused.
	# A later pointer click must still enqueue the current physical pointer point.
	player.last_host_input_was_pointer = true
	qsave_control.pressed.emit()
	var pointer_event: Dictionary = player.host.peek_last_command_for_window(story_window.get_instance_id())
	var expected_pointer: Vector2i = player._get_host_cursor_position()
	var queued_pointer: Variant = pointer_event.get("cursor_position", null)
	if not queued_pointer is Vector2i or queued_pointer != expected_pointer:
		printerr("FAIL New pointer command inherited a stale cursor override instead of the current pointer position")
		await _cleanup(player, save_dir)
		quit(1)
		return
	player.host.begin_command_scope("story-smoke-cleanup")
	player.host.is_waiting_input = true
	player.last_host_input_was_pointer = false

	# This probe is explicitly synthetic. It verifies that an active original
	# bustup already attached under the Story base sprite is not painted twice.
	var adv: Variant = player.vm.globals_by_name.get("adv", null)
	var set_result: Dictionary = player.vm.call_function_sync("SetBustup", ["CA02_01M", 0, 0], 100000)
	var update_result: Dictionary = player.vm.call_function_sync("AdvScreen::update", [adv, 0, 0], 100000)
	if not set_result.get("ok", false) or not update_result.get("ok", false):
		printerr("FAIL Original SetBustup/AdvScreen::update probe failed")
		await _cleanup(player, save_dir)
		quit(1)
		return
	player._sync_host_window_canvas()
	player._update_bustups()
	var bustup_manager: Variant = adv.get_field("bustupMan") if adv is CsxVMReader.CsxInstance else null
	var bustup_sprites: Variant = bustup_manager.get_field("spr") if bustup_manager is CsxVMReader.CsxInstance else []
	var bustup: CsxHostClass.HostSprite = bustup_sprites[0] as CsxHostClass.HostSprite if bustup_sprites is Array and not bustup_sprites.is_empty() else null
	var bustup_wrapper: Control = player.host_sprite_controls.get(bustup.get_instance_id(), null) if bustup != null else null
	if bustup_wrapper == null or not bustup_wrapper.visible or player.bustup_rects[0].visible:
		printerr("FAIL Attached original bustup was not rendered solely through the HostWindow compositor")
		await _cleanup(player, save_dir)
		quit(1)
		return

	var hashes_unchanged := csx_hash == FileAccess.get_sha256(csx_path) and data_hash == FileAccess.get_sha256(data_path)
	if not hashes_unchanged:
		printerr("FAIL Original CSX or data1.noa changed during read-only Story smoke")
		await _cleanup(player, save_dir)
		quit(1)
		return
	print("PASS Original Story HostWindow compositor: MessageSprite, reveal state, %d buttons, viewport surface, attached bustup; original hashes unchanged" % button_sprites.size())
	await _cleanup(player, save_dir)
	quit(0)


func _collect_buttons(sprite: CsxHostClass.HostSprite, target: Array[CsxHostClass.HostSprite]) -> void:
	if sprite.is_button:
		target.append(sprite)
	for child: CsxHostClass.HostSprite in sprite.children:
		_collect_buttons(child, target)


func _test_transformed_surface_geometry() -> bool:
	var target := Rect2(Vector2.ZERO, Vector2(800, 600))
	if not AdvPlayerScript._transformed_rect_covers_rect(Transform2D.IDENTITY, target, target):
		printerr("FAIL An identity 800x600 sprite must cover the logical viewport")
		return false
	var translated := Transform2D(0.0, Vector2.ONE, 0.0, Vector2(1, 0))
	if AdvPlayerScript._transformed_rect_covers_rect(translated, target, target):
		printerr("FAIL A translated 800x600 sprite must not cover the viewport's far edge")
		return false
	var pivoted_scale := (
		Transform2D(0.0, Vector2(2.0, 1.5), 0.0, Vector2(600, 450))
		* Transform2D(0.0, Vector2.ONE, 0.0, Vector2(-400, -300))
	)
	if not AdvPlayerScript._transformed_rect_covers_rect(pivoted_scale, target, target):
		printerr("FAIL A non-uniformly scaled sprite with a non-zero pivot should cover the viewport")
		return false
	var rotate_about_center := (
		Transform2D(PI / 4.0, Vector2.ONE, 0.0, Vector2(400, 300))
		* Transform2D(0.0, Vector2.ONE, 0.0, Vector2(-400, -300))
	)
	if AdvPlayerScript._transformed_rect_covers_rect(rotate_about_center, target, target):
		printerr("FAIL Rotated AABB overlap must not count as full viewport coverage")
		return false
	var parent_transform := Transform2D(0.0, Vector2(1.5, 1.25), 0.0, Vector2.ZERO)
	var child_transform := Transform2D(0.0, Vector2.ONE, 0.0, Vector2(-100.0 / 1.5, -50.0 / 1.25))
	if not AdvPlayerScript._transformed_rect_covers_rect(parent_transform * child_transform, target, target):
		printerr("FAIL Composed parent and child transforms should preserve viewport coverage")
		return false
	print("PASS transformed HostWindow surface coverage geometry")
	return true


func _test_button_surface_opacity() -> bool:
	var player_script := AdvPlayerScript.new()
	var sprite := CsxHostClass.HostSprite.new()
	sprite.is_button = true
	var opaque_image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	opaque_image.fill(Color.WHITE)
	var transparent_image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	transparent_image.fill(Color(1.0, 1.0, 1.0, 0.5))
	var opaque_texture := ImageTexture.create_from_image(opaque_image)
	var transparent_texture := ImageTexture.create_from_image(transparent_image)
	sprite.texture = opaque_texture
	sprite.btn_normal_tex = transparent_texture
	sprite.btn_focus_tex = opaque_texture
	sprite.btn_pushed_tex = opaque_texture
	sprite.btn_disabled_tex = opaque_texture
	if player_script._host_sprite_has_opaque_surface(sprite):
		printerr("FAIL A transparent button state must not be masked by the sprite's opaque fallback texture")
		player_script.free()
		return false
	sprite.btn_normal_tex = opaque_texture
	if not player_script._host_sprite_has_opaque_surface(sprite):
		printerr("FAIL A button with opaque state textures should cover its surface")
		player_script.free()
		return false
	var expired_texture := ImageTexture.create_from_image(opaque_image)
	player_script.host_texture_opacity_cache[expired_texture.get_instance_id()] = {"texture_ref": weakref(expired_texture), "opaque": true}
	expired_texture = null
	player_script._prune_host_texture_opacity_cache()
	for cache_entry: Dictionary in player_script.host_texture_opacity_cache.values():
		var texture_ref: Variant = cache_entry.get("texture_ref", null)
		if texture_ref is WeakRef and texture_ref.get_ref() == null:
			printerr("FAIL Expired texture opacity cache entries must be removed")
			player_script.free()
			return false
	player_script.free()
	print("PASS button opacity classification and stale texture-cache cleanup")
	return true


func _cleanup(player: Node, save_dir: String) -> void:
	if is_instance_valid(player):
		player.free()
	TestSupport.remove_test_saves(save_dir)
