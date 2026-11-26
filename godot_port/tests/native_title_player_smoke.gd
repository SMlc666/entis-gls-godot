extends SceneTree

const CsxHostClass = preload("res://scripts/csx_host.gd")
const CsxVMClass = preload("res://scripts/csx_vm.gd")
const TestSupport = preload("res://tests/test_support.gd")

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		_fail("Pass game directory after --")
		return

	var game_dir: String = args[0]
	var scene_res = load("res://scenes/adv_player.tscn")
	if not _require(scene_res != null, "AdvPlayer scene must load"): return
	var player = scene_res.instantiate()
	player.game_dir = game_dir
	player.start_in_title = true
	player.steps_per_frame = 500
	var test_save_dir: String = TestSupport.configure_player_saves(player, "native_title_player")
	root.add_child(player)

	var frames := 0
	while not player.is_initialized and frames < 300:
		await process_frame
		frames += 1
	if not _require(player.is_initialized, "AdvPlayer must initialize"): return
	if not _require(TestSupport.uses_isolated_saves(player.host, test_save_dir), "AdvPlayer initialization must use isolated test saves"): return

	frames = 0
	var native_window = null
	var start_sprite = null
	var continue_sprite = null
	while frames < 60:
		await process_frame
		frames += 1
		if player.vm != null and player.vm.data_vars.size() > 4:
			native_window = player.vm.data_vars[4].get("value", null)
			if native_window is CsxHostClass.HostWindow:
				start_sprite = _find_button_sprite(native_window.root_sprites, "ID_START")
				continue_sprite = _find_button_sprite(native_window.root_sprites, "ID_CONTINUE")
			if (start_sprite != null and continue_sprite != null
			and player.host_sprite_controls.has(start_sprite.get_instance_id())
			and player.host_sprite_controls.has(continue_sprite.get_instance_id())
			and player.host_sprite_controls[start_sprite.get_instance_id()].is_visible_in_tree()
			and _native_stack_has(player.vm.call_stack, "GetCommand")):
				break
	if not _require(native_window is CsxHostClass.HostWindow, "Native Title() must create its HostWindow"): return
	if not _require(start_sprite != null and continue_sprite != null, "Native Title() must expose its original Start and Continue commands"): return
	var focus_root := CsxHostClass.HostSprite.new(9100, player.host)
	var unnamed := CsxHostClass.HostSprite.new(9101, player.host)
	var focus_child := CsxHostClass.HostSprite.new(9102, player.host)
	focus_root.fields["form_item_id"] = "FOCUS_ROOT"
	focus_child.btn_id = "FOCUS_CHILD"
	focus_child.is_button = true
	focus_root.children.append(unnamed)
	unnamed.children.append(focus_child)
	native_window.add_sprite(0, focus_root)
	native_window.set_focus("FOCUS_ROOT\\FOCUS_CHILD")
	if not _require(native_window.focused_sprite == focus_child and native_window.get_focus() == "FOCUS_ROOT\\FOCUS_CHILD", "Native focus lookup must traverse unnamed Sprite containers"): return
	native_window.detach_sprite(focus_root)
	if not _require(native_window.focused_sprite == null and native_window.get_focus().is_empty(), "Removing a focused Sprite subtree must clear native focus"): return
	var focus_start_wrapper: Control = player.host_sprite_controls.get(start_sprite.get_instance_id(), null)
	var focus_continue_wrapper: Control = player.host_sprite_controls.get(continue_sprite.get_instance_id(), null)
	var focus_start_button: TextureButton = focus_start_wrapper.get_node_or_null("NativeButton") if focus_start_wrapper != null else null
	var focus_continue_button: TextureButton = focus_continue_wrapper.get_node_or_null("NativeButton") if focus_continue_wrapper != null else null
	if not _require(focus_start_button != null and focus_continue_button != null, "Original title commands must expose focusable buttons"): return
	focus_start_button.grab_focus()
	if not _require(focus_start_button.has_focus() and native_window.focused_sprite == start_sprite, "Godot button focus must update the native window"): return
	focus_continue_button.grab_focus()
	if not _require(focus_continue_button.has_focus() and native_window.focused_sprite == continue_sprite, "Moving keyboard focus must update the native window"): return
	player._sync_host_window_canvas()
	if not _require(focus_continue_button.has_focus(), "Native focus synchronization must not restore the previously focused button"): return
	native_window.set_focus("")
	player._sync_host_window_canvas()
	if not _require(not focus_continue_button.has_focus(), "Clearing native focus must release the matching Godot button focus"): return
	for command_id: String in ["ID_CONFIG", "ID_EXITGAME"]:
		if not _require(_find_button_sprite(native_window.root_sprites, command_id) != null, "Native Title() must expose its original %s command" % command_id): return
	if not _require(player.is_title_mode and player.is_running, "Title() must run asynchronously in title mode"): return
	if not _require(player.host_window_layer.visible, "Native HostWindow renderer must be visible"): return
	var effect_sprite := CsxHostClass.HostSprite.new(9001, player.host)
	effect_sprite.position = Vector2i(80, 80)
	effect_sprite.size = Vector2i(64, 64)
	effect_sprite.image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	effect_sprite.texture = ImageTexture.create_from_image(effect_sprite.image)
	var wave_effect := CsxVMClass.CsxInstance.new("EffectParam")
	wave_effect.set_field("strType", "WaveCircle")
	wave_effect.set_field("nShakingWidth", 5)
	wave_effect.set_field("nMeshSize", 8)
	wave_effect.set_field("nFrequency", 12)
	wave_effect.set_field("nFlags", 1)
	if not _require(effect_sprite.set_effect_parameter(wave_effect) == 0, "Native WaveCircle parameters must be accepted"): return
	player._sync_host_sprite(effect_sprite, player.host_window_canvas, {}, false)
	var effect_wrapper: Control = player.host_sprite_controls.get(effect_sprite.get_instance_id(), null)
	var effect_texture: TextureRect = effect_wrapper.get_node_or_null("NativeTexture") if effect_wrapper != null else null
	var effect_material := effect_texture.material as ShaderMaterial if effect_texture != null else null
	if not _require(effect_material != null and effect_material.get_shader_parameter("effect_mode") == 7, "WaveCircle must reach the native TextureRect shader renderer"): return
	if not _require(effect_material.shader.code.contains("wave_front") and effect_material.shader.code.contains("1.0 - transition_alpha * transition_alpha") and effect_material.get_shader_parameter("raster_transition") == true, "WaveCircle shader must apply the native radial curve and SDK transparency transition"): return
	var masked_sprite := CsxHostClass.HostSprite.new(9002, player.host)
	masked_sprite.position = Vector2i(160, 80)
	masked_sprite.size = Vector2i(2, 1)
	masked_sprite.is_visible = true
	masked_sprite.image = Image.create(2, 1, false, Image.FORMAT_RGBA8)
	masked_sprite.image.fill(Color.WHITE)
	masked_sprite.texture = ImageTexture.create_from_image(masked_sprite.image)
	var alpha_resource := CsxHostClass.HostResource.new("smoke_alpha", "", -1, 0, 0, player.host)
	alpha_resource.image = Image.create(2, 1, false, Image.FORMAT_RGBA8)
	alpha_resource.image.fill(Color.WHITE)
	if not _require(masked_sprite.set_alpha_image(alpha_resource, 128) == 0, "Alpha mask must attach before rendering"): return
	masked_sprite.set_blend_degree(96)
	player._sync_host_sprite(masked_sprite, player.host_window_canvas, {}, false)
	var masked_wrapper: Control = player.host_sprite_controls.get(masked_sprite.get_instance_id(), null)
	var masked_texture: TextureRect = masked_wrapper.get_node_or_null("NativeTexture") if masked_wrapper != null else null
	var masked_material := masked_texture.material as ShaderMaterial if masked_texture != null else null
	if not _require(masked_material != null and masked_material.get_shader_parameter("alpha_mask_ready") == true, "Alpha mask must activate shader compositing without another sprite effect"): return
	if not _require(masked_material.get_shader_parameter("alpha_mask_texture") == masked_sprite.alpha_texture and masked_material.get_shader_parameter("alpha_mask_range") == 128.0 and masked_material.get_shader_parameter("alpha_mask_blend") == 96.0, "Alpha mask image, range and SetBlendDegree must reach native shader uniforms"): return
	var adv_instance: Variant = player.vm.globals_by_name.get("adv", null)
	if not _require(adv_instance is CsxVMClass.CsxInstance, "Original AdvScreen instance must be available to the story renderer"): return
	player.is_title_mode = false
	adv_instance.set_field("sprTemp", {"transition": masked_sprite})
	player._sync_adv_temp_sprites(adv_instance)
	var transition_node: TextureRect = player.adv_temp_controls.get(masked_sprite.get_instance_id(), null)
	var transition_material := transition_node.material as ShaderMaterial if transition_node != null else null
	if not _require(transition_node != null and transition_node.is_visible_in_tree(), "AdvScreen temporary sprites must render in the story transition layer"): return
	if not _require(transition_material != null and transition_material.get_shader_parameter("alpha_mask_ready") == true and transition_material.get_shader_parameter("alpha_mask_texture") == masked_sprite.alpha_texture, "AdvScreen temporary sprites must apply the native alpha mask texture"): return
	adv_instance.set_field("sprTemp", {})
	player._sync_adv_temp_sprites(adv_instance)
	var back_color_sprite := CsxHostClass.HostSprite.new(9003, player.host)
	back_color_sprite.is_visible = true
	back_color_sprite.size = Vector2i(16, 16)
	back_color_sprite.set_back_color(0x123456, true)
	back_color_sprite.children.append(CsxHostClass.HostSprite.new(9004, player.host))
	var back_color_seen: Dictionary = {}
	player._sync_host_sprite(back_color_sprite, player.host_window_canvas, back_color_seen, false)
	var back_color_wrapper: Control = player.host_sprite_controls.get(back_color_sprite.get_instance_id(), null)
	var back_color_node: ColorRect = back_color_wrapper.get_node_or_null("NativeBackColor") if back_color_wrapper != null else null
	if not _require(back_color_node != null and back_color_node.visible and back_color_node.color.to_html(false) == "123456", "Native sprite containers must fill their configured Entis back color before child sprites (node=%s visible=%s color=%s children=%d)" % [str(back_color_node != null), str(back_color_node.visible if back_color_node != null else false), back_color_node.color.to_html(false) if back_color_node != null else "missing", back_color_sprite.children.size()]): return
	player.is_title_mode = true
	var mesh_values: Array = [
		0.0, 0.0, 64.0, 0.0, 0.0, 64.0, 64.0, 64.0,
		0.0, 0.0, 64.0, 10.0, 10.0, 64.0, 64.0, 64.0,
	]
	effect_sprite.blending = 128
	if not _require(player.vm._dispatch_sprite_method(effect_sprite, "SetMeshWarpEffect", [mesh_values, 2, 1, 1]) == 0, "Original SetMeshWarpEffect must accept two flattened mesh poses"): return
	player._sync_host_sprite(effect_sprite, player.host_window_canvas, {}, false)
	var mesh_wrapper: Control = player.host_sprite_controls.get(effect_sprite.get_instance_id(), null)
	var mesh_node: MeshInstance2D = mesh_wrapper.get_node_or_null("NativeMeshWarp") if mesh_wrapper != null else null
	if not _require(mesh_node != null and mesh_node.mesh != null and mesh_node.texture == effect_sprite.texture, "MeshWarp must render as a textured native mesh"): return
	var mesh_arrays: Array = mesh_node.mesh.surface_get_arrays(0)
	var mesh_vertices: PackedVector3Array = mesh_arrays[Mesh.ARRAY_VERTEX]
	if not _require(mesh_vertices.size() == 4 and mesh_vertices[1].is_equal_approx(Vector3(64.0, 5.0, 0.0)), "MeshWarp degree must interpolate the original vertex poses"): return
	if not _require(is_equal_approx(mesh_node.modulate.a, 0.75) and not effect_texture.visible, "MeshWarp transition must use SDK transparency and replace the flat image"):
		return
	var shading_effect := CsxVMClass.CsxInstance.new("EffectParam")
	shading_effect.set_field("strType", "ShadingOff")
	shading_effect.set_field("nFlags", 1)
	if not _require(effect_sprite.set_effect_parameter(shading_effect) == 0, "Native ShadingOff parameters must be accepted"): return
	player._sync_host_sprite(effect_sprite, player.host_window_canvas, {}, false)
	effect_material = effect_texture.material as ShaderMaterial
	if not _require(effect_material != null and effect_material.get_shader_parameter("effect_mode") == 8, "ShadingOff must reach the native shader renderer"): return
	if not _require(effect_material.get_shader_parameter("shading_levels_ready") == true, "ShadingOff must build and bind all five native filtered image levels"): return
	var shading_levels: Array = effect_texture.get_meta("native_shading_levels", [])
	if not _require(shading_levels.size() == 5, "ShadingOff must cache source and four native 4:2:1 filter levels"): return
	var cached_second_level: Texture2D = shading_levels[1]
	player._sync_host_sprite(effect_sprite, player.host_window_canvas, {}, false)
	if not _require(effect_texture.get_meta("native_shading_levels", []).size() == 5 and effect_material.get_shader_parameter("shading_levels_ready") == true, "ShadingOff cache must persist across frame synchronization"): return
	shading_effect.set_field("strType", "ShadingLight")
	if not _require(effect_sprite.set_effect_parameter(shading_effect) == 0, "Native ShadingLight parameters must be accepted"): return
	player._sync_host_sprite(effect_sprite, player.host_window_canvas, {}, false)
	if not _require(effect_material.get_shader_parameter("effect_mode") == 9 and effect_material.get_shader_parameter("shading_levels_ready") == true and effect_texture.get_meta("native_shading_levels")[1] == cached_second_level, "ShadingLight must reuse the native filtered levels"): return
	var tile_sprite := CsxHostClass.HostSprite.new(9002, player.host)
	var original_tile_texture: Texture2D = start_sprite.btn_normal_tex if start_sprite.btn_normal_tex != null else start_sprite.texture
	if not _require(original_tile_texture != null, "TileImage validation must use a texture loaded from the original game resources"): return
	tile_sprite.size = Vector2i(original_tile_texture.get_size())
	tile_sprite.texture = original_tile_texture
	tile_sprite.image = original_tile_texture.get_image()
	var tile_effect := CsxVMClass.CsxInstance.new("EffectParam")
	var tile_view := CsxVMClass.CsxInstance.new("ISize")
	tile_view.set_field("w", 800)
	tile_view.set_field("h", 600)
	var tile_speed := CsxVMClass.CsxInstance.new("IPoint")
	tile_speed.set_field("x", 1)
	tile_speed.set_field("y", 0)
	tile_effect.set_field("strType", "TileImage")
	tile_effect.set_field("nInterval", 100)
	tile_effect.set_field("nDegreeStep", 0)
	tile_effect.set_field("sizeView", tile_view)
	tile_effect.set_field("ptSpeed", tile_speed)
	if not _require(tile_sprite.set_effect_parameter(tile_effect) == 0, "Original TileImage parameters must be accepted"): return
	player._sync_host_sprite(tile_sprite, player.host_window_canvas, {}, false)
	var tile_wrapper: Control = player.host_sprite_controls.get(tile_sprite.get_instance_id(), null)
	var tile_texture: TextureRect = tile_wrapper.get_node_or_null("NativeTexture") if tile_wrapper != null else null
	var tile_material := tile_texture.material as ShaderMaterial if tile_texture != null else null
	var expected_repeat := Vector2(800.0, 600.0) / Vector2(original_tile_texture.get_size())
	if not _require(tile_material != null and tile_material.get_shader_parameter("effect_mode") == 1 and tile_material.get_shader_parameter("repeat_scale").is_equal_approx(expected_repeat), "TileImage must render an 800x600 view by repeating the original source texture"): return
	player.host.sprite_animation_flags |= 4
	player.host.advance_sprite_animations(0.1)
	player._sync_host_sprite(tile_sprite, player.host_window_canvas, {}, false)
	var expected_scroll := Vector2(-799.0 / original_tile_texture.get_width(), 0.0)
	if not _require(tile_material.get_shader_parameter("scroll_uv").is_equal_approx(expected_scroll), "TileImage speed must advance in source-pixel units at each 100 ms interval"): return
	await process_frame
	var hand_made_menu = player.title_panel.find_child("TitleMenu", true, false)
	if not _require(hand_made_menu != null and not hand_made_menu.visible, "Hand-authored title menu must be hidden"): return
	var config_sprite = null
	for sprite in native_window.root_sprites:
		if sprite.fields.get("form_page_id") == "ID_PAGE_MENU":
			config_sprite = _find_button_sprite(sprite.children, "ID_CONFIG")
			break
	var config_wrapper: Control = player.host_sprite_controls.get(config_sprite.get_instance_id(), null) if config_sprite != null else null
	var config_button: TextureButton = config_wrapper.get_node_or_null("NativeButton") if config_wrapper != null else null
	if not _require(config_button != null, "Native Title() must expose an interactive ID_CONFIG"): return
	config_button.emit_signal("pressed")
	var native_config: CsxHostClass.HostSprite = null
	var config_wait_frames := 0
	while config_wait_frames < 180:
		await process_frame
		config_wait_frames += 1
		native_config = _find_form_page(native_window.root_sprites, "ID_PAGE_CONFIG")
		var config_wrapper_candidate: Control = player.host_sprite_controls.get(native_config.get_instance_id(), null) if native_config != null else null
		if native_config != null and config_wrapper_candidate != null and config_wrapper_candidate.is_visible_in_tree():
			break
	var native_config_wrapper: Control = player.host_sprite_controls.get(native_config.get_instance_id(), null) if native_config != null else null
	if not _require(native_config != null and _native_stack_has(player.vm.call_stack, "ConfigWindow::run"), "ID_CONFIG must enter the original CSX ConfigWindow"): return
	if not _require(native_config_wrapper != null and native_config_wrapper.is_visible_in_tree(), "The original ID_PAGE_CONFIG must render above the title screen"): return
	if not _require(native_config_wrapper.position.is_equal_approx(Vector2(134, 24)) and native_config_wrapper.size.is_equal_approx(Vector2(532, 552)), "The original 532x552 settings page must retain its centered 800x600 coordinates"): return
	var native_bgm_scroll: CsxHostClass.HostSprite = _find_form_item(native_config.children, "ID_VOL_BGM")
	var native_bgm_control: Range = player.host_sprite_controls[native_bgm_scroll.get_instance_id()].get_node_or_null("NativeScroll") if native_bgm_scroll != null else null
	if not _require(native_bgm_control != null and native_bgm_control.editable, "The original BGM scrollbar must be interactive"): return
	var scroll_test_value := int(native_bgm_control.value) + 1
	if scroll_test_value > int(native_bgm_control.max_value):
		scroll_test_value = int(native_bgm_control.value) - 1
	native_bgm_control.value = scroll_test_value
	if not _require(player.host.has_pending_commands(), "Changing the native BGM scrollbar must queue an Entis notification"): return
	var scroll_event: Dictionary = player.host.peek_last_command_for_window(native_window.get_instance_id())
	if not _require(scroll_event.get("id") == "ID_VOL_BGM" and scroll_event.get("notification") == 4 and scroll_event.get("parameter") == scroll_test_value, "Native scrollbar tracking must send notification 4 with its position"): return
	var config_return_sprite: CsxHostClass.HostSprite = _find_button_sprite(native_config.children, "ID_TITLE")
	var config_return_wrapper: Control = player.host_sprite_controls.get(config_return_sprite.get_instance_id(), null) if config_return_sprite != null else null
	var config_return_button: TextureButton = config_return_wrapper.get_node_or_null("NativeButton") if config_return_wrapper != null else null
	if not _require(config_return_button != null and config_return_button.is_visible_in_tree(), "The original ID_TITLE button must be available on ConfigWindow"): return
	config_return_button.emit_signal("pressed")
	config_wait_frames = 0
	var native_yes_sprite: CsxHostClass.HostSprite = null
	while config_wait_frames < 180:
		await process_frame
		config_wait_frames += 1
		native_yes_sprite = _find_button_sprite(native_window.root_sprites, "ID_YES")
		if native_yes_sprite != null and _native_stack_has(player.vm.call_stack, "Confirm"):
			break
	var native_yes_wrapper: Control = player.host_sprite_controls.get(native_yes_sprite.get_instance_id(), null) if native_yes_sprite != null else null
	var native_yes_button: TextureButton = native_yes_wrapper.get_node_or_null("NativeButton") if native_yes_wrapper != null else null
	if not _require(native_yes_button != null and native_yes_button.is_visible_in_tree(), "The original confirmation page must be visible and interactive"): return
	native_yes_button.emit_signal("pressed")
	config_wait_frames = 0
	while config_wait_frames < 180 and _find_form_page(native_window.root_sprites, "ID_PAGE_CONFIG") != null:
		await process_frame
		config_wait_frames += 1
	if not _require(_find_form_page(native_window.root_sprites, "ID_PAGE_CONFIG") == null and player.is_title_mode, "The original ID_TITLE command must close ConfigWindow and return to Title()"): return
	if not _require(player.vm.last_error.is_empty(), "Native ConfigWindow must complete without a VM error"): return
	var native_continue_wrapper: Control = player.host_sprite_controls.get(continue_sprite.get_instance_id(), null)
	var native_continue_button: TextureButton = native_continue_wrapper.get_node_or_null("NativeButton") if native_continue_wrapper != null else null
	if not _require(native_continue_button != null and native_continue_button.is_visible_in_tree(), "Native Title() Continue must remain interactive after ConfigWindow"): return
	native_continue_button.emit_signal("pressed")
	var native_save_load_root: CsxHostClass.HostSprite = null
	config_wait_frames = 0
	while config_wait_frames < 180:
		await process_frame
		config_wait_frames += 1
		if _native_stack_has(player.vm.call_stack, "LoadSaveWindow::run"):
			for candidate: CsxHostClass.HostSprite in native_window.root_sprites:
				if (
					candidate.size.x >= 600 and candidate.size.x <= 800
					and candidate.size.y >= 500 and candidate.size.y <= 600
					and _find_button_sprite(candidate.children, "ID_QSAVE") != null
				):
					native_save_load_root = candidate
					break
		if native_save_load_root != null:
			break
	var native_save_load_wrapper: Control = player.host_sprite_controls.get(native_save_load_root.get_instance_id(), null) if native_save_load_root != null else null
	if not _require(native_save_load_root != null and native_save_load_wrapper != null and native_save_load_wrapper.is_visible_in_tree(), "Title Continue must display the original LoadSaveWindow above the title screen"): return
	if not _require(native_save_load_root.size == Vector2i(690, 574) and native_save_load_root.position == Vector2i(400, 300), "The original LoadSaveWindow must preserve its 690x574 centered geometry"): return
	var native_quick_save_sprite: CsxHostClass.HostSprite = _find_button_sprite(native_save_load_root.children, "ID_QSAVE")
	if not _require(native_quick_save_sprite != null and not native_quick_save_sprite.is_enabled, "An empty original save store must show the disabled quick-load control"): return
	var native_input_filter: Variant = null
	for input_var_index: int in player.vm.data_vars.size():
		var input_var: Dictionary = player.vm.data_vars[input_var_index]
		if input_var.get("name", "") == "input":
			native_input_filter = input_var.get("value", null)
			break
	if not _require(
		native_input_filter is CsxHostClass.HostInputFilter
		and native_input_filter.filter_file == "input.xml"
		and native_input_filter.input_assignments.get("button:5", []).size() > 0,
		"The original input.xml Q-to-button-5 mapping must be available to LoadSaveWindow after the title window detaches it (value=%s open=%s file=%s mappings=%s)" % [
			str(native_input_filter),
			str(native_input_filter.is_open if native_input_filter is CsxHostClass.HostInputFilter else false),
			str(native_input_filter.filter_file if native_input_filter is CsxHostClass.HostInputFilter else ""),
			str(native_input_filter.input_assignments.get("button:5", []) if native_input_filter is CsxHostClass.HostInputFilter else [])
		]
	): return
	if not _require(not native_input_filter.is_open and player.host.active_input_filter_ref == null, "CloseFilter must detach the input filter from the completed title window"): return
	var quit_load_event := InputEventKey.new()
	quit_load_event.keycode = KEY_Q
	quit_load_event.unicode = KEY_Q
	quit_load_event.pressed = true
	Input.parse_input_event(quit_load_event)
	config_wait_frames = 0
	while config_wait_frames < 180 and _native_stack_has(player.vm.call_stack, "LoadSaveWindow::run"):
		await process_frame
		config_wait_frames += 1
	var release_load_event := InputEventKey.new()
	release_load_event.keycode = KEY_Q
	release_load_event.unicode = KEY_Q
	release_load_event.pressed = false
	Input.parse_input_event(release_load_event)
	if not _require(not _native_stack_has(player.vm.call_stack, "LoadSaveWindow::run") and player.is_title_mode, "The original input.xml Q command must return from LoadSaveWindow to Title()"): return
	var exit_requested := OS.get_cmdline_user_args().has("--verify-exit")
	if exit_requested:
		var exit_sprite = _find_button_sprite(native_window.root_sprites, "ID_EXITGAME")
		var exit_wrapper: Control = player.host_sprite_controls.get(exit_sprite.get_instance_id())
		if not _require(exit_wrapper.is_visible_in_tree(), "Exit must be visible before clicking"): return
		TestSupport.remove_test_saves(test_save_dir)
		print("Clicking native Exit button")
		exit_wrapper.get_node("NativeButton").emit_signal("pressed")
		await create_timer(0.25).timeout
		_fail("Native Exit button did not quit the game")
		return

	var gallery_entry: Button = player.host_window_layer.find_child("NativeTitleGalleryEntry", true, false)
	if not _require(gallery_entry != null and gallery_entry.is_visible_in_tree(), "Title must expose the original appreciation flow"): return
	_click(gallery_entry)
	frames = 0
	var native_app_window = null
	var rec_tab_sprite = null
	var cg_item_sprite = null
	while frames < 60:
		await process_frame
		frames += 1
		if player.native_appreciation_mode and player.vm.data_vars.size() > 4:
			native_app_window = player.vm.data_vars[4].get("value", null)
			if native_app_window is CsxHostClass.HostWindow:
				rec_tab_sprite = _find_button_sprite(native_app_window.root_sprites, "ID_REC")
				cg_item_sprite = _find_button_sprite(native_app_window.root_sprites, "ID_CGSEL1")
			if (rec_tab_sprite != null and cg_item_sprite != null
			and player.host_sprite_controls.has(rec_tab_sprite.get_instance_id())
			and player.host_sprite_controls.has(cg_item_sprite.get_instance_id())):
				break
	if not _require(player.is_title_mode and player.native_appreciation_mode, "Native CSX Appreciation() must start"): return
	if not _require(native_app_window is CsxHostClass.HostWindow, "Appreciation() must create its native HostWindow"): return
	if not _require(rec_tab_sprite != null and cg_item_sprite != null, "Native Appreciation() must create original recollection and CG controls"): return
	if not _require(not player.is_appreciation_open and not player.appreciation_panel.visible, "Native Appreciation() must not show the custom gallery panel"): return
	var native_cg_wrapper: Control = player.host_sprite_controls.get(cg_item_sprite.get_instance_id(), null)
	var native_cg_button: TextureButton = native_cg_wrapper.get_node_or_null("NativeButton") if native_cg_wrapper != null else null
	if not _require(native_cg_button != null and native_cg_button.texture_normal != null, "Native CG item must render its CSX button texture"): return
	var thumb_page: Control = native_cg_wrapper.get_parent()
	for frame in range(60):
		if thumb_page.position.x >= 0 and thumb_page.position.y > 34:
			break
		await process_frame
	if not _require(thumb_page.position.x >= 0 and thumb_page.position.y > 34, "Original CG form must use its scripted position and pivot"): return
	if not _require(thumb_page.get_node("NativeTexture").texture != null, "Original CG form must load its background from the form resource"): return
	var original_tags: Array[Control] = []
	for root_sprite in native_app_window.root_sprites:
		for child in root_sprite.children:
			if str(child.fields.get("form_page_id", "")).begins_with("ID_PAGE_TAG"):
				original_tags.append(player.host_sprite_controls[child.get_instance_id()])
	if not _require(original_tags.size() == 6, "Appreciation must render all six original character rows"): return
	var rows: Dictionary = {}
	for tag in original_tags:
		rows[tag.position.y] = true
	if not _require(rows.size() == original_tags.size(), "Original character rows must not overlap at their animation destinations"): return
	var rec_tab_wrapper: Control = player.host_sprite_controls.get(rec_tab_sprite.get_instance_id(), null)
	var native_rec_tab_button: TextureButton = rec_tab_wrapper.get_node_or_null("NativeButton") if rec_tab_wrapper != null else null
	if not _require(native_rec_tab_button != null, "Native recollection tab must render as a TextureButton"): return
	if not _require(rec_tab_sprite.full_btn_id == "ID_PAGE_TAG1\\\\ID_REC", "Nested Appreciation button must preserve its full CSX command path"): return
	var rec_captures: Array = []
	if not _require(player.vm._is_match_usage(rec_tab_sprite.full_btn_id, "&ID_PAGE_TAG&(<0-9>*)&\\\\ID_REC&", rec_captures) == "" and rec_captures == [1], "CSX IsMatchUsage must match nested page commands and capture the one-based page index"): return
	var appreciation_view = null
	for app_frame: Variant in player.vm.call_stack:
		if app_frame.name == "Appreciation":
			appreciation_view = app_frame.get_local("view")
			break
	if not _require(appreciation_view != null, "Appreciation() must retain its native AppreciationView instance"): return
	_click(native_rec_tab_button)
	frames = 0
	while frames < 60:
		await process_frame
		frames += 1
	if not _require(not player.host.has_pending_commands() and not player.vm.is_halted and player.vm.last_error.is_empty(), "Native appreciation tab command must reach the running CSX loop"): return
	var tag_sprites = appreciation_view.get_field("sprTag")
	if not _require(tag_sprites is Array and player.vm._dispatch_array_method(tag_sprites, "IsButtonChecked", ["ID_REC"]) == -1, "CSX IsButtonChecked must find a selected button in the Appreciation sprite array"): return
	if not _require(int(appreciation_view.get_field("selPage")) == 3, "Native ID_REC must switch the original AppreciationView to its recollection page"): return
	var second_tag_sprite = _find_button_sprite(tag_sprites.slice(1, 2), "ID_TAG")
	if not _require(second_tag_sprite != null, "Native Appreciation must expose the second character tag"): return
	var second_tag: Control = player.host_sprite_controls[second_tag_sprite.get_instance_id()]
	var second_tag_button: TextureButton = second_tag.get_node("NativeButton")
	# The left edge belongs to the character tag, away from its page controls.
	_click(second_tag_button, Vector2(25, 15))
	for frame in range(30):
		await process_frame
	if not _require(not player.vm.is_halted and player.vm.last_error.is_empty(), "Native character tag must switch without a VM error"): return
	var bgm21_sprite = _find_button_sprite(native_app_window.root_sprites, "ID_BGM21")
	var bgm21_wrapper: Control = player.host_sprite_controls.get(bgm21_sprite.get_instance_id(), null) if bgm21_sprite != null else null
	var bgm21_button: TextureButton = bgm21_wrapper.get_node_or_null("NativeButton") if bgm21_wrapper != null else null
	if not _require(bgm21_button != null, "Native Appreciation must expose BGM21 control"): return
	var bgm_before_select: String = player.host.current_bgm
	_click(bgm21_button)
	frames = 0
	while frames < 60:
		await process_frame
		frames += 1
	if not _require(player.host.current_bgm == "BGM02_S.mio" and player.host.current_bgm != bgm_before_select, "Native ID_BGM21 must select its original BGM track"): return
	var native_close_sprite = _find_button_sprite(native_app_window.root_sprites, "ID_CLOSE")
	if not _require(native_close_sprite != null, "Native Appreciation() must expose a close command"): return
	var native_close_wrapper: Control = player.host_sprite_controls.get(native_close_sprite.get_instance_id(), null)
	var native_close_button: TextureButton = native_close_wrapper.get_node_or_null("NativeButton") if native_close_wrapper != null else null
	if not _require(native_close_button != null, "Native Appreciation close command must be interactive"): return
	var escape_event := InputEventKey.new()
	escape_event.keycode = KEY_ESCAPE
	escape_event.pressed = true
	root.push_input(escape_event, true)
	if not _require(player.is_title_mode and not player.native_appreciation_mode and not player.vm.is_halted, "Closing native Appreciation() must return to Title()"): return

	frames = 0
	start_sprite = null
	while frames < 60:
		await process_frame
		frames += 1
		native_window = player.vm.data_vars[4].get("value", null)
		if native_window is CsxHostClass.HostWindow:
			start_sprite = _find_button_sprite(native_window.root_sprites, "ID_START")
		if (start_sprite != null and player.host_sprite_controls.has(start_sprite.get_instance_id())
		and _native_stack_has(player.vm.call_stack, "GetCommand")):
			break
	if not _require(start_sprite != null, "Re-entered Title() must rebuild ID_START"): return
	var start_wrapper: Control = player.host_sprite_controls.get(start_sprite.get_instance_id(), null)
	if not _require(start_wrapper != null, "ID_START must have a rendered Control"): return
	var start_button: TextureButton = start_wrapper.get_node_or_null("NativeButton")
	if not _require(start_button != null, "ID_START must render as an interactive TextureButton"): return
	if not _require(start_button.texture_normal == start_sprite.btn_normal_tex, "ID_START must use the original button texture"): return

	start_button.emit_signal("pressed")
	var transition_seconds := 0.0
	var saw_start_fade := false
	while player.is_title_mode and transition_seconds < 5.0:
		await process_frame
		transition_seconds += player.get_process_delta_time()
		for sprite in native_window.root_sprites:
			if sprite.is_activating and sprite.activation_duration_ms == 3000.0 and sprite.transparency > 0 and sprite.transparency < 256:
				saw_start_fade = true
				break
	if not _require(saw_start_fade, "Native Start must render an intermediate frame of the scripted fade"): return
	if not _require(not player.is_title_mode, "Native ID_START must leave the title screen"): return
	if not _require(player.is_running, "ID_START must start the scenario loop"): return
	var timeout_result: Dictionary = player.vm.call_function_sync("Title", [], 1)
	if not _require(not timeout_result.get("ok", true) and timeout_result.get("timeout", false), "A synchronous Title() budget exhaustion must report timeout failure"): return

	print("PASS Native CSX Title() and Appreciation() Player Smoke Test!")
	TestSupport.remove_test_saves(test_save_dir)
	player.free()
	await process_frame
	await process_frame
	quit(0)


func _require(condition: bool, message: String) -> bool:
	if not condition:
		_fail(message)
		return false
	return true


func _fail(message: String) -> void:
	printerr("FAIL ", message)
	quit(1)


func _find_button_sprite(sprites: Array, button_id: String):
	for sprite in sprites:
		if sprite is CsxHostClass.HostSprite:
			if sprite.btn_id == button_id:
				return sprite
			var child_match = _find_button_sprite(sprite.children, button_id)
			if child_match != null:
				return child_match
	return null


func _find_form_item(sprites: Array, item_id: String):
	for sprite in sprites:
		if sprite is CsxHostClass.HostSprite:
			if str(sprite.fields.get("form_item_id", "")) == item_id:
				return sprite
			var child_match = _find_form_item(sprite.children, item_id)
			if child_match != null:
				return child_match
	return null


func _find_form_page(sprites: Array, page_id: String):
	for sprite in sprites:
		if sprite is CsxHostClass.HostSprite:
			if str(sprite.fields.get("form_page_id", "")) == page_id:
				return sprite
	return null


func _native_stack_has(stack: Array, function_name: String) -> bool:
	for frame: Variant in stack:
		if frame.name == function_name:
			return true
	return false


func _click(control: Control, local_position := Vector2(-1, -1)) -> void:
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = control.get_global_rect().get_center() if local_position.x < 0 else control.get_global_transform() * local_position
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		root.push_input(click, true)
