extends "res://tests/smoke_test_base.gd"

const CsxHostClass = preload("res://scripts/csx_host.gd")
const CsxVMClass = preload("res://scripts/csx_vm.gd")
const TestSupport = preload("res://tests/test_support.gd")


class FailingThumbnailHost extends "res://scripts/csx_host.gd":
	var fail_thumbnail_writes: bool = false

	func _write_thumbnail_file(path: String, png_bytes: PackedByteArray) -> bool:
		if fail_thumbnail_writes:
			return false
		return super._write_thumbnail_file(path, png_bytes)


class AnimationFixtureHost extends "res://scripts/csx_host.gd":
	var resource_audio_volume_updates: Array[Dictionary] = []

	func load_image(filename: String, _archive_hint: String = "") -> Dictionary:
		var basename := filename.get_file().get_basename().to_upper()
		if basename not in ["FRAME_FIXTURE", "BUTTON_NORMAL", "BUTTON_FOCUS", "BUTTON_PUSHED", "BUTTON_DISABLED"]:
			return super.load_image(filename, _archive_hint)
		var frame_a := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		var frame_b := Image.create(3, 1, false, Image.FORMAT_RGBA8)
		frame_a.fill(Color.RED)
		frame_b.fill(Color.BLUE)
		var frames: Array = [frame_a, frame_b] if basename == "FRAME_FIXTURE" else [frame_a]
		return {"ok": true, "image": frames[0], "texture": ImageTexture.create_from_image(frames[0]), "frames": frames, "frame_sequence": [0, 1] if frames.size() == 2 else [0], "total_time_ms": 120}

	func load_sound(filename: String, _archive_hint: String = "") -> Dictionary:
		if filename.get_file().get_basename().to_upper() != "SE_TEST_SAVE":
			return super.load_sound(filename, _archive_hint)
		var stream := AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = 8000
		stream.stereo = true
		stream.data.resize(8000 * 2 * 2)
		return {"ok": true, "stream": stream, "archive": "fixture.noa"}

	func resolve_audio_channel(filename: String, _archive_hint: String = "") -> String:
		if filename.get_file().get_basename().to_upper() == "SE_TEST_SAVE":
			return "se"
		return super.resolve_audio_channel(filename, _archive_hint)

	func set_resource_audio_volume(channel: String, resource_volume: float, resource_volume_right: float = -1.0, play_type: int = -2, resource_name: String = "") -> bool:
		resource_audio_volume_updates.append({
			"channel": channel,
			"left": resource_volume,
			"right": resource_volume if resource_volume_right < 0.0 else resource_volume_right,
			"play_type": play_type,
			"name": resource_name
		})
		return true


func _initialize() -> void:
	call_deferred("_run")


func _break_fixture_cycles(value: Variant) -> void:
	if value is CsxVMClass.CsxInstance:
		var instance := value as CsxVMClass.CsxInstance
		instance.fields.erase("self")
		var cyclic_fields: Variant = instance.fields.get("cyclic_fields")
		if cyclic_fields is Dictionary:
			cyclic_fields.clear()
		instance.fields.erase("cyclic_fields")
		_break_fixture_cycles(instance.fields.get("sprite"))
		return
	if value is CsxHostClass.HostSprite:
		var sprite := value as CsxHostClass.HostSprite
		for child: Variant in sprite.children.duplicate():
			_break_fixture_cycles(child)
		sprite.fields.erase("root_owner")
		sprite.fields.erase("children_alias")
		sprite.detach_all_sprites()
		sprite.clear_message()
		sprite.release()


func _run() -> void:
	var test_save_dir := TestSupport.new_save_dir("save_storage_contract")
	var host = AnimationFixtureHost.new("")
	host.save_dir = test_save_dir
	var vm = CsxVMClass.new(host)
	var thumbnail_source := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	thumbnail_source.fill(Color.RED)
	host.current_bg_texture = ImageTexture.create_from_image(thumbnail_source)
	var thumbnail_fixture = CsxVMClass.CsxInstance.new("ThumbnailFixture")
	expect(host.save_object_file("thumbnail_sync.json", thumbnail_fixture), "A thumbnail fixture save must succeed")
	var red_thumbnail_path: String = host.get_thumbnail_path("thumbnail_sync.json")
	var red_thumbnail := FileAccess.get_file_as_bytes(red_thumbnail_path)
	thumbnail_source.fill(Color.BLUE)
	host.current_bg_texture = ImageTexture.create_from_image(thumbnail_source)
	expect(host.save_object_file("thumbnail_sync.json", thumbnail_fixture), "Updating the thumbnail fixture save must succeed")
	var blue_thumbnail_path: String = host.get_thumbnail_path("thumbnail_sync.json")
	var blue_thumbnail := FileAccess.get_file_as_bytes(blue_thumbnail_path)
	expect(red_thumbnail_path != blue_thumbnail_path and not red_thumbnail.is_empty() and not blue_thumbnail.is_empty() and red_thumbnail != blue_thumbnail, "Saving a new snapshot must commit a new thumbnail generation")
	var backup_document: Variant = JSON.parse_string(FileAccess.get_file_as_string(host.get_save_path("thumbnail_sync.json") + ".bak"))
	var backup_thumbnail_path: String = host.save_dir.path_join(str(backup_document.get("thumbnail_file", ""))) if backup_document is Dictionary else ""
	expect(backup_thumbnail_path == red_thumbnail_path and FileAccess.file_exists(backup_thumbnail_path), "The backup snapshot must retain its own thumbnail generation")
	expect(host.is_thumbnail_current("thumbnail_sync.json"), "A committed thumbnail must match the hash recorded by its save")
	expect(host.save_object_file("thumbnail_sync.dat", thumbnail_fixture), "A second save with the same basename and another extension must save")
	expect(FileAccess.file_exists(blue_thumbnail_path) and FileAccess.file_exists(red_thumbnail_path) and host.is_thumbnail_current("thumbnail_sync.json"), "Thumbnail cleanup must preserve generations referenced by another full save filename")
	thumbnail_source.fill(Color.GREEN)
	host.current_bg_texture = ImageTexture.create_from_image(thumbnail_source)
	expect(host.save_thumbnail("thumbnail_sync.json", null, 4, 4), "SaveThumbnailImage must update the manifest when its save already exists")
	var explicit_thumbnail_path: String = host.get_thumbnail_path("thumbnail_sync.json")
	var explicit_backup_document: Variant = JSON.parse_string(FileAccess.get_file_as_string(host.get_save_path("thumbnail_sync.json") + ".bak"))
	var explicit_backup_thumbnail: String = host.save_dir.path_join(str(explicit_backup_document.get("thumbnail_file", ""))) if explicit_backup_document is Dictionary else ""
	expect(explicit_thumbnail_path != blue_thumbnail_path and host.is_thumbnail_current("thumbnail_sync.json"), "Explicit thumbnail writes must atomically update the current manifest hash")
	expect(explicit_backup_thumbnail == blue_thumbnail_path and FileAccess.file_exists(explicit_backup_thumbnail), "Explicit thumbnail updates must preserve the prior snapshot's preview")
	host.current_bg_texture = null
	expect(host.save_object_file("thumbnail_sync.json", thumbnail_fixture) and host.get_thumbnail_path("thumbnail_sync.json").is_empty() and host.is_thumbnail_current("thumbnail_sync.json"), "A save without a preview image must record that state and keep the backup's image available")
	thumbnail_source.fill(Color.RED)
	host.current_bg_texture = ImageTexture.create_from_image(thumbnail_source)
	var failing_host := FailingThumbnailHost.new("")
	failing_host.save_dir = test_save_dir
	failing_host.current_bg_texture = host.current_bg_texture
	expect(failing_host.save_object_file("thumbnail_failure.json", thumbnail_fixture), "The initial save for thumbnail failure injection must succeed")
	var failure_save_path: String = failing_host.get_save_path("thumbnail_failure.json")
	var previous_failure_save := FileAccess.get_file_as_bytes(failure_save_path)
	failing_host.fail_thumbnail_writes = true
	thumbnail_source.fill(Color.BLUE)
	failing_host.current_bg_texture = ImageTexture.create_from_image(thumbnail_source)
	expect(not failing_host.save_object_file("thumbnail_failure.json", thumbnail_fixture), "A thumbnail write failure must fail before the save manifest is committed")
	expect(FileAccess.get_file_as_bytes(failure_save_path) == previous_failure_save, "Thumbnail commit failure must roll the main save back to its previous version")
	expect(failing_host.is_thumbnail_current("thumbnail_failure.json"), "A failed thumbnail generation must leave the previously committed save image current")
	# Keep the established fixture's visual source independent from thumbnail tests.
	host.current_bg_texture = null
	var file_name := "round_trip.json"
	var source = CsxVMClass.CsxInstance.new("SaveFixture")
	var source_sprite = CsxHostClass.HostSprite.new(7, host)
	source_sprite.filename = "FRAME_FIXTURE.eri"
	source_sprite.archive_hint = "fixture.noa"
	source_sprite.position = Vector2i(31, 47)
	source_sprite.rev_center = Vector2i(15, 20)
	source_sprite.magnification = Vector2(0.95, 0.97)
	source_sprite.message_style = {"id": "ID_FONT_MESSAGE", "font": {"size": "24"}}
	source_sprite.is_enabled = false
	source_sprite.blending = 37
	source_sprite.movie_rewind_frame = 3
	source_sprite.movie_end_frame = 17
	source_sprite.movie_repeat = true
	source_sprite.alpha_range = 192
	source_sprite.animation_loop_count = -1
	source_sprite.animation_elapsed_ms = 125.5
	source_sprite.animation_duration_ms = 500.0
	source_sprite.animation_begin_sequence = 2
	source_sprite.animation_start_sequence = 1
	source_sprite.animation_turn_sequence = 4
	source_sprite.animation_rewind_sequence = 1
	source_sprite.animation_view_frame = 1
	source_sprite.animation_total_time_ms = 700
	source_sprite.animation_sequence.assign([0, 1, 2])
	source_sprite.activation_curves = [[Vector2(0, 2), Vector2(100, 80)], [], []]
	source_sprite.is_activating = true
	source_sprite.activation_duration_ms = 300.0
	source_sprite.activation_elapsed_ms = 90.0
	source_sprite.activation_start_alpha = 0
	source_sprite.activation_end_alpha = 256
	source_sprite.activation_target_alpha = 128
	source_sprite.activation_fade_enabled = true
	source_sprite.activation_action_type = 2
	source_sprite.activation_durations.assign([100.0, 200.0])
	source_sprite.is_message_sprite = true
	source_sprite.font_bordering = true
	source_sprite.message_cursor_position = Vector2i(12, 34)
	source_sprite.full_btn_id = "ID_PAGE\\ID_BUTTON"
	source_sprite.is_button = true
	source_sprite.btn_state = "focus"
	source_sprite.button_image_sources = {
		"normal": {"filename": "BUTTON_NORMAL.eri", "archive_hint": "fixture.noa", "crop": [0, 0, 0, 0]},
		"focus": {"filename": "BUTTON_FOCUS.eri", "archive_hint": "fixture.noa", "crop": [0, 0, 0, 0]},
		"pushed": {"filename": "BUTTON_PUSHED.eri", "archive_hint": "fixture.noa", "crop": [0, 0, 0, 0]},
		"disabled": {"filename": "BUTTON_DISABLED.eri", "archive_hint": "fixture.noa", "crop": [0, 0, 0, 0]}
	}
	source_sprite.animation_frames.assign([Image.create(2, 2, false, Image.FORMAT_RGBA8), Image.create(3, 1, false, Image.FORMAT_RGBA8)])
	source_sprite.animation_frame_sizes.assign([Vector2i(2, 2), Vector2i(3, 1)])
	var source_tone_filter := CsxHostClass.HostToneFilter.new(host)
	source_tone_filter.filter_type = "CUSTOM"
	source_tone_filter.set_tone(0.25, 0.5, 0.75)
	expect(source_tone_filter.set_general_tone(24, 0, -31, 1, 46, 2, -12, 0, 5) == 0, "Tone filter fixture tables must be configured")
	source_sprite.attach_tone_filter(source_tone_filter)
	source_sprite.is_visible = true
	source_sprite.transparency = 12
	source_sprite.fields = {"checked": true, "page": 3, "metadata": {"label": "fixture"}}
	var source_sprite_child = CsxHostClass.HostSprite.new(8, host)
	source_sprite_child.filename = "child.fixture"
	source_sprite_child.position = Vector2i(5, 9)
	source_sprite_child.text_content = "pending child"
	source_sprite_child.message_char_speed_ms = 100
	source_sprite_child.message_fade_ms = 1000
	source_sprite_child.message_pending = true
	source_sprite.add_sprite(4, source_sprite_child)
	source_sprite_child.fields["root_owner"] = source_sprite
	source_sprite.fields["children_alias"] = source_sprite.children
	var source_resource = CsxHostClass.HostResource.new("fixture.resource", "fixture.noa", 2, 16, 128, host)
	source_resource.is_playing = true
	source_resource.current_position = 2400
	source_resource.playback_end_frame = 8400
	source_resource.playback_rewind_frame = 1200
	source_resource.is_repeating = true
	source_resource.fields = {"kind": "image", "custom_state": [1, "two", false]}
	source_sprite.attached_resource = source_resource
	source.set_field("sprite", source_sprite)
	source.set_field("sprite_alias", source_sprite)
	source.set_field("resource", source_resource)
	source.set_field("integer_keys", {7: "numeric key", "7": "string key"})
	var cyclic_fields: Dictionary = {}
	cyclic_fields["self"] = cyclic_fields
	source.set_field("cyclic_fields", cyclic_fields)
	source.set_field("counter", 42)
	source.set_field("wide_integer", 9007199254740993)
	source.set_field("self", source)

	expect(host.save_object_file(file_name, source), "A valid snapshot must save")
	var save_path: String = host.get_save_path(file_name)
	var stable_contents := FileAccess.get_file_as_string(save_path)
	expect(not stable_contents.is_empty() and JSON.parse_string(stable_contents) != null, "Saved snapshot must be complete valid JSON")

	var restored = CsxVMClass.CsxInstance.new("SaveFixture")
	expect(host.load_object_file(file_name, restored, vm), "The saved fixture must load")
	expect(restored.type_name == "SaveFixture", "CsxInstance type must round-trip")
	expect(restored.get_field("counter") == 42, "Primitive CSX fields must round-trip")
	expect(restored.get_field("wide_integer") == 9007199254740993, "64-bit integers beyond JSON's exact IEEE-754 range must round-trip exactly")
	expect(is_same(restored.get_field("self"), restored), "A staged restore must rebind references to its root onto the existing destination object")
	var old_sprite_document: Dictionary = CsxHostClass.serialize_value(source_sprite)
	old_sprite_document.erase("rev_center")
	old_sprite_document.erase("magnification")
	old_sprite_document.erase("message_style")
	var old_sprite = CsxHostClass.deserialize_into(null, old_sprite_document)
	expect(old_sprite.rev_center == Vector2i.ZERO and old_sprite.magnification == Vector2.ONE, "Older sprite saves must use the original default transform")

	var restored_sprite: Variant = restored.get_field("sprite")
	expect(restored_sprite is CsxHostClass.HostSprite, "HostSprite must restore as a HostSprite")
	expect(is_same(restored_sprite, restored.get_field("sprite_alias")), "Repeated HostSprite references must preserve object identity")
	if restored_sprite is CsxHostClass.HostSprite:
		expect(restored_sprite.filename == "FRAME_FIXTURE.eri", "HostSprite filename must round-trip")
		expect(restored_sprite.archive_hint == "fixture.noa", "HostSprite archive identity must round-trip")
		expect(restored_sprite.position == Vector2i(31, 47), "HostSprite position must round-trip")
		expect(restored_sprite.rev_center == Vector2i(15, 20), "HostSprite pivot must round-trip")
		expect(restored_sprite.magnification.is_equal_approx(Vector2(0.95, 0.97)), "HostSprite magnification must round-trip")
		expect(restored_sprite.message_style.get("font", {}).get("size") == "24", "HostSprite message style must round-trip")
		expect(not restored_sprite.is_enabled and restored_sprite.blending == 37 and restored_sprite.alpha_range == 192, "HostSprite enabled, blend and alpha mask state must round-trip")
		expect(restored_sprite.movie_rewind_frame == 3 and restored_sprite.movie_end_frame == 17 and restored_sprite.movie_repeat, "HostSprite movie loop configuration must round-trip")
		expect(restored_sprite.animation_loop_count == -1 and restored_sprite.animation_elapsed_ms == 125.5 and restored_sprite.animation_sequence == [0, 1, 2], "HostSprite animation playback state must round-trip")
		expect(restored_sprite.activation_curves[0] == [Vector2(0, 2), Vector2(100, 80)] and restored_sprite.is_activating and restored_sprite.activation_elapsed_ms == 90.0, "HostSprite activation state and curves must round-trip")
		expect(restored_sprite.is_message_sprite and restored_sprite.font_bordering and restored_sprite.message_cursor_position == Vector2i(12, 34), "HostSprite message rendering state must round-trip")
		expect(restored_sprite.full_btn_id == "ID_PAGE\\ID_BUTTON", "HostSprite fully qualified button ID must round-trip")
		expect(restored_sprite.animation_frames.size() == 2 and restored_sprite.animation_frame_sizes == [Vector2i(2, 2), Vector2i(3, 1)] and restored_sprite.animation_frames[1].get_size() == Vector2i(3, 1), "HostSprite animation frames must reload from the saved resource descriptor with frame metadata")
		expect(restored_sprite.tone_filter is CsxHostClass.HostToneFilter and restored_sprite.tone_filter.filter_type == "CUSTOM" and restored_sprite.tone_filter.tone.is_equal_approx(Color(0.25, 0.5, 0.75, 1.0)), "HostSprite tone filter parameters must round-trip")
		expect(restored_sprite.tone_filter.red_table == source_tone_filter.red_table and restored_sprite.tone_filter.green_table == source_tone_filter.green_table and restored_sprite.tone_filter.blue_table == source_tone_filter.blue_table and restored_sprite.tone_filter.alpha_table == source_tone_filter.alpha_table, "Tone filter LUTs must round-trip exactly")
		expect(restored_sprite.btn_normal_tex != null and restored_sprite.btn_focus_tex != null and restored_sprite.btn_pushed_tex != null and restored_sprite.btn_disabled_tex != null and restored_sprite.texture == restored_sprite.btn_focus_tex, "Button states must rebuild textures from resource descriptors and restore selected state")
		expect(restored_sprite.is_visible and restored_sprite.transparency == 12, "HostSprite visibility state must round-trip")
		expect(restored_sprite.children.size() == 1 and restored_sprite.children[0].parent_sprite == restored_sprite and restored_sprite.children[0].position == Vector2i(5, 9), "HostSprite child hierarchy must round-trip with repaired weak parent links")
		expect(is_same(restored_sprite.children, restored_sprite.fields.get("children_alias")), "HostSprite child array identity must survive restoration when another field aliases it")
		expect(is_same(restored_sprite.children[0].fields.get("root_owner"), restored_sprite), "Child references to their saved root sprite must rebind to the restored sprite")
		expect(host.active_messages.has(restored_sprite.children[0].get_instance_id()), "Pending child messages must be registered after restoring the sprite tree")
		var visible_before_child_advance: int = restored_sprite.children[0].message_visible_count
		host.advance_sprite_animations(0.2)
		expect(restored_sprite.children[0].message_visible_count > visible_before_child_advance, "Restored pending child messages must continue advancing")
		expect(restored_sprite.fields.get("checked") == true, "HostSprite.fields must round-trip")
		expect(restored_sprite.fields.get("metadata", {}).get("label") == "fixture", "Nested HostSprite.fields must round-trip")
	var restored_resource: Variant = restored.get_field("resource")
	expect(restored_resource is CsxHostClass.HostResource, "HostResource must restore as a HostResource")
	expect(restored_sprite is CsxHostClass.HostSprite and is_same(restored_sprite.attached_resource, restored_resource), "HostSprite attached-resource identity must round-trip through the shared object graph")
	if restored_resource is CsxHostClass.HostResource:
		expect(restored_resource.name == "fixture.resource", "HostResource name must round-trip")
		expect(restored_resource.is_playing, "HostResource playback state must round-trip")
		expect(restored_resource.current_position == 2400, "Saved playback position must retain its frame units")
		expect(restored_resource.is_repeating and restored_resource.playback_end_frame == 8400 and restored_resource.playback_rewind_frame == 1200, "Custom playback loop must survive save and load")
		expect(restored_resource.fields.get("custom_state") == [1, "two", false], "HostResource.fields values must round-trip with their original types")

	# Persist an active audio curve and its explicit play category. The fixture
	# provides a generated WAV in memory, so no original or commercial audio is read.
	var audio_source = CsxVMClass.CsxInstance.new("AudioSaveFixture")
	var audio_resource = CsxHostClass.HostResource.new("SE_TEST_SAVE.mio", "fixture.noa", 0, 0, 0, host)
	expect(audio_resource.load_sound(audio_resource.name) == 1, "Generated audio fixture must load through HostResource")
	audio_resource.play_type = CsxHostClass.AUDIO_PLAY_TYPE_MUSIC
	audio_resource.volume_left = 0.8
	audio_resource.volume_right = 0.7
	audio_resource.volume_envelope.assign([
		Vector2(0.8, 0.7), Vector2(0.7, 0.6), Vector2(0.5, 0.4), Vector2(0.3, 0.2)
	])
	audio_resource.volume_envelope_duration_ms = 1000.0
	audio_resource.volume_envelope_elapsed_ms = 250.0
	audio_source.set_field("resource", audio_resource)
	expect(host.save_object_file("audio_envelope.json", audio_source), "An in-flight audio envelope must save")
	var audio_restored = CsxVMClass.CsxInstance.new("AudioSaveFixture")
	expect(host.load_object_file("audio_envelope.json", audio_restored, vm), "An in-flight audio envelope must restore")
	var restored_audio_resource: Variant = audio_restored.get_field("resource")
	expect(restored_audio_resource is CsxHostClass.HostResource, "Audio save fixture must restore a HostResource")
	if restored_audio_resource is CsxHostClass.HostResource:
		expect(restored_audio_resource.play_type == CsxHostClass.AUDIO_PLAY_TYPE_MUSIC, "HostResource play type must survive save/load")
		expect(restored_audio_resource.audio_channel == "se", "Restored audio channel must resolve from its resource descriptor")
		expect(restored_audio_resource.volume_envelope.size() == 4 and is_equal_approx(restored_audio_resource.volume_envelope_elapsed_ms, 250.0), "The pending volume envelope and elapsed progress must round-trip")
		expect(host.active_volume_envelopes.has(restored_audio_resource.get_instance_id()), "A restored pending envelope must register only after object graph commit")
		host.resource_audio_volume_updates.clear()
		host.advance_audio_envelopes(0.25)
		expect(not host.resource_audio_volume_updates.is_empty(), "A restored pending volume envelope must continue advancing")
		if not host.resource_audio_volume_updates.is_empty():
			var envelope_update: Dictionary = host.resource_audio_volume_updates.back()
			expect(envelope_update.get("channel") == "se" and envelope_update.get("play_type") == CsxHostClass.AUDIO_PLAY_TYPE_MUSIC, "Resumed audio automation must use the restored channel and play type")
			expect(is_equal_approx(float(envelope_update.get("left", -1.0)), 0.5875) and is_equal_approx(float(envelope_update.get("right", -1.0)), 0.4875), "Resumed automation must continue from the saved 250 ms position")
			expect(is_equal_approx(restored_audio_resource.volume_envelope_elapsed_ms, 500.0), "Resumed audio automation must advance its elapsed time")
			expect(restored_audio_resource.set_volume(0.9, 0.8) == 1, "Restored audio volume updates must keep their audio category")
			var explicit_volume_update: Dictionary = host.resource_audio_volume_updates.back()
			expect(explicit_volume_update.get("play_type") == CsxHostClass.AUDIO_PLAY_TYPE_MUSIC, "HostResource.SetVolume must pass its restored play type")

	# Schema 6 snapshots predate these fields; missing values keep their legacy defaults.
	var legacy_audio_payload: Dictionary = CsxHostClass.serialize_value(audio_resource)
	legacy_audio_payload.erase("play_type")
	legacy_audio_payload.erase("volume_envelope")
	legacy_audio_payload.erase("volume_envelope_duration_ms")
	legacy_audio_payload.erase("volume_envelope_elapsed_ms")
	var legacy_audio_file := FileAccess.open(host.get_save_path("legacy_audio_v6.json"), FileAccess.WRITE)
	legacy_audio_file.store_string(JSON.stringify({"__yzk_save_document__": true, "schema_version": 6, "payload": legacy_audio_payload}))
	legacy_audio_file.close()
	var legacy_audio_target := CsxHostClass.HostResource.new("", "", -1, 0, 0, host)
	legacy_audio_target.play_type = CsxHostClass.AUDIO_PLAY_TYPE_VOICE
	legacy_audio_target.volume_envelope.assign([Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ZERO])
	legacy_audio_target.volume_envelope_duration_ms = 2000.0
	legacy_audio_target.volume_envelope_elapsed_ms = 200.0
	host.active_volume_envelopes[legacy_audio_target.get_instance_id()] = weakref(legacy_audio_target)
	expect(host.load_object_file("legacy_audio_v6.json", legacy_audio_target, vm), "A schema 6 audio resource without envelope fields must remain loadable")
	expect(legacy_audio_target.play_type == CsxHostClass.AUDIO_PLAY_TYPE_NONE and legacy_audio_target.volume_envelope.is_empty() and legacy_audio_target.volume_envelope_duration_ms == 0.0 and legacy_audio_target.volume_envelope_elapsed_ms == 0.0, "Legacy audio restoration must reset newer state to legacy defaults")
	expect(not host.active_volume_envelopes.has(legacy_audio_target.get_instance_id()), "Legacy audio restoration must unregister a stale target envelope")

	var restored_cycle: Variant = restored.get_field("cyclic_fields")
	expect(restored_cycle is Dictionary and is_same(restored_cycle, restored_cycle.get("self")), "Cyclic dictionaries must round-trip without recursion")
	var restored_integer_keys: Dictionary = restored.get_field("integer_keys")
	expect(restored_integer_keys.size() == 2 and restored_integer_keys.get(7) == "numeric key" and restored_integer_keys.get("7") == "string key", "Integer dictionary keys must retain their type without colliding with string keys")

	# JSON may present a reference before its object definition. The graph pass
	# must allocate the later object before resolving this earlier reference.
	var forward_path: String = host.get_save_path("forward_reference.json")
	var forward_payload := {
		"__type__": "CsxInstance",
		"__id__": 1,
		"class_name": "SaveFixture",
		"fields": {
			"alias": {"__ref__": 2},
			"later": {"__type__": "Array", "__id__": 2, "items": ["resolved"]}
		}
	}
	var forward_file := FileAccess.open(forward_path, FileAccess.WRITE)
	forward_file.store_string(JSON.stringify({"__yzk_save_document__": true, "schema_version": CsxHostClass.SAVE_SCHEMA_VERSION, "payload": forward_payload}))
	forward_file.close()
	var forward_target = CsxVMClass.CsxInstance.new("SaveFixture")
	expect(host.load_object_file("forward_reference.json", forward_target, vm), "A valid forward reference in JSON must resolve")
	expect(is_same(forward_target.get_field("alias"), forward_target.get_field("later")) and forward_target.get_field("alias") == ["resolved"], "Forward reference must share the later array object")
	# Godot's JSON parser can represent integer tokens as integral floats. They
	# normalize to canonical integer keys; fractional IDs remain invalid.
	var fractional_id_file := FileAccess.open(host.get_save_path("fractional_id.json"), FileAccess.WRITE)
	fractional_id_file.store_string(JSON.stringify({"__yzk_save_document__": true, "schema_version": CsxHostClass.SAVE_SCHEMA_VERSION, "payload": {"__type__": "CsxInstance", "__id__": 1.25, "class_name": "SaveFixture", "fields": {"counter": 999}}}))
	fractional_id_file.close()
	expect(not host.load_object_file("fractional_id.json", restored, vm) and restored.get_field("counter") == 42, "Fractional object IDs must be rejected without changing the destination")

	# A malformed tagged value is rejected before any target field is replaced.
	var malformed_path: String = host.get_save_path("malformed_transaction.json")
	var malformed_file := FileAccess.open(malformed_path, FileAccess.WRITE)
	var malformed_payload := {"__type__": "CsxInstance", "__id__": 1, "class_name": "SaveFixture", "fields": {"counter": 99, "broken": {"__type__": "HostSprite", "__id__": 2, "position": "bad"}}}
	malformed_file.store_string(JSON.stringify({"__yzk_save_document__": true, "schema_version": CsxHostClass.SAVE_SCHEMA_VERSION, "payload": malformed_payload}))
	malformed_file.close()
	expect(not host.load_object_file("malformed_transaction.json", restored, vm), "Structurally invalid tagged data must be rejected")
	expect(restored.get_field("counter") == 42, "Rejected deserialization must leave the existing target unchanged")
	var invalid_sprite_cases: Array[Dictionary] = [
		{"name": "fields", "field": "fields", "value": {"__type__": "Array", "__id__": 6, "items": []}},
		{"name": "sprite_parameters", "field": "sprite_parameters", "value": {"__type__": "Array", "__id__": 6, "items": []}},
		{"name": "message_style", "field": "message_style", "value": {"__type__": "Array", "__id__": 6, "items": []}},
		{"name": "activation_curves", "field": "activation_curves", "value": [[], [], ["wrong-element"]]},
		{"name": "animation_sequence", "field": "animation_sequence", "value": {"__type__": "Array", "__id__": 6, "items": ["wrong-element"]}}
	]
	for invalid_case: Dictionary in invalid_sprite_cases:
		var invalid_sprite_payload := {
			"__type__": "CsxInstance", "__id__": 1, "class_name": "SaveFixture",
			"fields": {"counter": {"__type__": "Integer", "value": "999"}, "sprite": {
				"__type__": "HostSprite", "__id__": 2,
				"fields": {"__type__": "Dictionary", "__id__": 3, "items": {}},
				"sprite_parameters": {"__type__": "Dictionary", "__id__": 4, "items": {}},
				"message_style": {"__type__": "Dictionary", "__id__": 5, "items": {}},
				"activation_curves": [[], [], []],
				"animation_sequence": {"__type__": "Array", "__id__": 7, "items": []}
			}}
		}
		invalid_sprite_payload.fields.sprite[invalid_case.field] = invalid_case.value
		var invalid_case_name := "invalid_sprite_%s.json" % invalid_case.name
		var invalid_case_file := FileAccess.open(host.get_save_path(invalid_case_name), FileAccess.WRITE)
		invalid_case_file.store_string(JSON.stringify({"__yzk_save_document__": true, "schema_version": CsxHostClass.SAVE_SCHEMA_VERSION, "payload": invalid_sprite_payload}))
		invalid_case_file.close()
		expect(not host.load_object_file(invalid_case_name, restored, vm) and restored.get_field("counter") == 42, "Semantic-invalid HostSprite %s data must be rejected without mutating the target" % invalid_case.field)
	var integer_reference_path: String = host.get_save_path("integer_reference.json")
	var integer_reference_file := FileAccess.open(integer_reference_path, FileAccess.WRITE)
	var integer_reference_payload := {"__type__": "CsxInstance", "__id__": 1, "class_name": "SaveFixture", "fields": {
		"a": {"__ref__": 2}, "b": {"__type__": "Integer", "__id__": 2, "value": "9"}
	}}
	integer_reference_file.store_string(JSON.stringify({"__yzk_save_document__": true, "schema_version": CsxHostClass.SAVE_SCHEMA_VERSION, "payload": integer_reference_payload}))
	integer_reference_file.close()
	expect(not host.load_object_file("integer_reference.json", restored, vm), "Scalar Integer wrappers must not serve as object-reference targets")
	expect(restored.get_field("counter") == 42, "Rejected scalar reference graph must leave its target unchanged")
	var missing_resource_path: String = host.get_save_path("missing_resource_transaction.json")
	var missing_resource_file := FileAccess.open(missing_resource_path, FileAccess.WRITE)
	var missing_resource_payload := {
		"__type__": "CsxInstance", "__id__": 1, "class_name": "SaveFixture",
		"fields": {
			"counter": {"__type__": "Integer", "value": "123"},
			"resource": {"__type__": "HostResource", "__id__": 2, "name": "MISSING_AUDIO.mio", "archive_name": "MISSING.noa", "fields": {}}
		}
	}
	missing_resource_file.store_string(JSON.stringify({"__yzk_save_document__": true, "schema_version": CsxHostClass.SAVE_SCHEMA_VERSION, "payload": missing_resource_payload}))
	missing_resource_file.close()
	expect(not host.load_object_file("missing_resource_transaction.json", restored, vm), "A missing media resource must fail before committing the staged object graph")
	expect(restored.get_field("counter") == 42 and is_same(restored.get_field("self"), restored), "Failed resource restoration must leave the destination's existing object graph unchanged")
	var strict_fallback_path: String = host.get_save_path("strict_fallback.json")
	source.set_field("counter", 42)
	expect(host.save_object_file("strict_fallback.json", source), "Strict fallback fixture primary must save")
	source.set_field("counter", 43)
	expect(host.save_object_file("strict_fallback.json", source), "Strict fallback fixture backup must be retained")
	var strict_failure_payload := {
		"__type__": "CsxInstance", "__id__": 1, "class_name": "SaveFixture",
		"fields": {
			"counter": {"__type__": "Integer", "value": "999"},
			"missing": {"__type__": "HostResource", "__id__": 2, "name": "MISSING_AUDIO.mio", "archive_name": "MISSING.noa", "fields": {}}
		}
	}
	var strict_failure_file := FileAccess.open(strict_fallback_path, FileAccess.WRITE)
	strict_failure_file.store_string(JSON.stringify({"__yzk_save_document__": true, "schema_version": CsxHostClass.SAVE_SCHEMA_VERSION, "payload": strict_failure_payload}))
	strict_failure_file.close()
	var strict_fallback_target = CsxVMClass.CsxInstance.new("SaveFixture")
	strict_fallback_target.set_field("counter", 77)
	expect(host.load_object_file("strict_fallback.json", strict_fallback_target, vm), "A strict primary resource failure must fall back to the backup")
	expect(strict_fallback_target.get_field("counter") == 42, "Successful backup recovery must commit only the backup graph")
	source.set_field("counter", 42)
	expect(host.save_object_file("semantic_fallback.json", source), "Semantic fallback fixture first snapshot must save")
	expect(host.save_object_file("semantic_fallback.json", source), "Semantic fallback fixture backup must save")
	var semantic_bad_payload := {
		"__type__": "CsxInstance", "__id__": 1, "class_name": "SaveFixture",
		"fields": {
			"counter": {"__type__": "Integer", "value": "999"},
			"sprite": {"__type__": "HostSprite", "__id__": 2, "fields": {"__type__": "Array", "__id__": 3, "items": []}}
		}
	}
	var semantic_bad_file := FileAccess.open(host.get_save_path("semantic_fallback.json"), FileAccess.WRITE)
	semantic_bad_file.store_string(JSON.stringify({"__yzk_save_document__": true, "schema_version": CsxHostClass.SAVE_SCHEMA_VERSION, "payload": semantic_bad_payload}))
	semantic_bad_file.close()
	var semantic_target = CsxVMClass.CsxInstance.new("SaveFixture")
	semantic_target.set_field("counter", 77)
	expect(host.load_object_file("semantic_fallback.json", semantic_target, vm), "A semantic-invalid primary must fall back to the valid backup")
	expect(semantic_target.get_field("counter") == 42, "The semantic-invalid candidate must not commit its counter before backup restore")
	var root_dictionary: Dictionary = {"previous": "keep until commit"}
	var dictionary_source: Dictionary = {}
	dictionary_source["label"] = "restored"
	dictionary_source["self"] = dictionary_source
	expect(host.save_object_file("root_dictionary.json", dictionary_source), "A cyclic dictionary root must save")
	expect(host.load_object_file("root_dictionary.json", root_dictionary, vm), "A dictionary root must load into the caller's existing container")
	expect(root_dictionary.get("label") == "restored" and is_same(root_dictionary.get("self"), root_dictionary), "Root dictionary identity and self-reference must survive staged commit")
	var root_sprite = CsxHostClass.HostSprite.new(8, host)
	root_sprite.sprite_parameters["stale_target_key"] = true
	expect(host.save_object_file("root_sprite.json", source_sprite), "A root HostSprite snapshot must save")
	expect(host.load_object_file("root_sprite.json", root_sprite, vm), "A root HostSprite snapshot must load into the supplied instance")
	expect(not root_sprite.sprite_parameters.has("stale_target_key"), "Restoring a sprite must replace, not merge, its saved parameter dictionary")
	expect(root_sprite.children.size() == 1 and root_sprite.children[0].parent_sprite == root_sprite, "Root HostSprite restoration must replace its child tree and rebind parent links")
	expect(is_same(root_sprite.children[0].fields.get("root_owner"), root_sprite), "Root HostSprite references from descendants must rebind to the caller's root instance")
	expect(is_same(root_sprite.children, root_sprite.fields.get("children_alias")), "Root HostSprite commit must preserve child-array aliases to its fields")

	# HostFile calls must carry their creating VM into object restoration.
	var vm_file: Variant = vm.create_object("File")
	_break_fixture_cycles(restored)
	expect(vm_file.open(file_name, 2) == 0 and vm_file.load_object(restored) == 0, "HostFile.LoadObject must retain its creating VM context")
	expect(restored.get_field("sprite") is CsxHostClass.HostSprite and restored.get_field("sprite").host == host, "HostFile restoration must bind restored host objects to the active host")
	var log_file := CsxHostClass.HostFile.new(host, vm)
	expect(log_file.open("append.log", CsxHostClass.HostFile.MODE_READ) == 1, "READ mode must require an existing file")
	expect(log_file.open("append.log", CsxHostClass.HostFile.MODE_WRITE) == 0, "WRITE mode must open a new file")
	expect(log_file.load_object(restored) != 0, "WRITE mode must reject object loads")
	expect(log_file.output_log_text("append.log", "first") == 0, "First OutputLogText append must return success")
	expect(log_file.close() == 0 and log_file.output_log_text("append.log", "closed") != 0, "Closed HostFile must reject writes")
	expect(log_file.open("append.log", CsxHostClass.HostFile.MODE_READ_WRITE) == 0, "READ_WRITE mode must open an existing file")
	expect(log_file.output_log_text("append.log", "second") == 0, "Second OutputLogText append must return success")
	expect(FileAccess.get_file_as_string(host.get_save_path("append.log")) == "first\nsecond\n", "HostFile.OutputLogText must append without truncating prior lines")
	expect(log_file.open(file_name, CsxHostClass.HostFile.MODE_READ) == 0 and log_file.load_object(restored) == 0, "READ mode must permit loads from an existing file")
	expect(log_file.save_object(restored) != 0 and log_file.output_log_text("append.log", "blocked") != 0, "READ mode must reject all HostFile writes")
	expect(log_file.open("missing.log", CsxHostClass.HostFile.MODE_READ_WRITE) != 0, "READ_WRITE mode must reject a missing file")
	expect(log_file.open("new.log", CsxHostClass.HostFile.MODE_WRITE) == 0 and log_file.load_object(restored) != 0, "WRITE mode must reject reads while permitting creation")
	var disconnected_log := CsxHostClass.HostFile.new(null, vm)
	expect(disconnected_log.output_log_text("append.log", "unavailable") != 0, "OutputLogText must report failure when no host is bound")
	var blocked_log_path := ProjectSettings.globalize_path(host.get_save_path("blocked.log"))
	expect(DirAccess.make_dir_recursive_absolute(blocked_log_path) == OK, "Create a directory at the log file path to inject an open failure")
	expect(log_file.output_log_text("blocked.log", "unavailable") != 0 and not host.last_error.is_empty(), "OutputLogText must report file-open failures instead of returning success")

	# A structurally invalid oversized object is rejected before replacing the
	# previous valid snapshot.
	var too_deep: Array = []
	var nested: Array = too_deep
	for _index in range(CsxHostClass.MAX_SERIALIZATION_DEPTH + 8):
		var child: Array = []
		nested.append(child)
		nested = child
	expect(not host.save_object_file(file_name, too_deep), "Over-depth snapshot must fail instead of exhausting recursion")
	expect(FileAccess.get_file_as_string(save_path) == stable_contents, "Failed save must preserve the previous complete snapshot")
	var final_loaded = CsxVMClass.CsxInstance.new("SaveFixture")
	expect(host.load_object_file(file_name, final_loaded, vm), "Previous snapshot must remain readable after failed save")
	expect(final_loaded.get_field("counter") == 42, "Previous snapshot contents must remain intact")

	var slot_name := "Save003.dat"
	var slot_path: String = host.get_save_path(slot_name)
	var backup_path := slot_path + ".bak"
	source.set_field("counter", 42)
	expect(host.save_object_file(slot_name, source), "First story snapshot must save")
	source.set_field("counter", 43)
	expect(host.save_object_file(slot_name, source), "Second story snapshot must keep a backup")
	expect(DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path)) == OK, "Simulate interruption after primary snapshot moved to backup")
	expect(host.is_file_existing(slot_name), "Story slot with only a valid backup must remain available")
	_break_fixture_cycles(final_loaded)
	expect(host.load_object_file(slot_name, final_loaded, vm), "Missing primary snapshot must load from backup")
	expect(final_loaded.get_field("counter") == 42, "Recovered backup must contain the earlier state")
	var damaged := FileAccess.open(slot_path, FileAccess.WRITE)
	damaged.store_string("{}")
	damaged.close()
	_break_fixture_cycles(final_loaded)
	expect(host.load_object_file(slot_name, final_loaded, vm), "Structurally invalid primary must load from backup")
	expect(final_loaded.get_field("counter") == 42, "Invalid primary must not replace the valid backup")
	expect(host.save_object_file(slot_name, source), "Saving after recovery must succeed")
	expect(not host.read_save_snapshot(backup_path, false).is_empty(), "Saving after recovery must retain the valid backup")
	expect(host.save_object_file("typed_commit_failure.json", ["backup snapshot"]), "Typed-array commit failure backup must save")
	expect(host.save_object_file("typed_commit_failure.json", ["primary snapshot"]), "Typed-array commit failure primary must save")
	var typed_target: Array[int] = [77]
	expect(not host.load_object_file("typed_commit_failure.json", typed_target, vm), "Both incompatible typed-array snapshots must fail before commit")
	expect(typed_target == [77], "Failed primary and backup commits must leave the caller's typed target unchanged")

	var corrupt_slot := FileAccess.open(host.get_save_path("Save004.dat"), FileAccess.WRITE)
	corrupt_slot.store_string("{}")
	corrupt_slot.close()
	expect(not host.is_file_existing("Save004.dat"), "A damaged slot without a backup must be unavailable")

	# Break the deliberate reference cycles so this contract test measures the
	# restored graph without leaving test-owned RefCounted cycles at shutdown.
	_break_fixture_cycles(source)
	_break_fixture_cycles(restored)
	_break_fixture_cycles(final_loaded)
	_break_fixture_cycles(strict_fallback_target)
	_break_fixture_cycles(semantic_target)
	_break_fixture_cycles(old_sprite)
	_break_fixture_cycles(root_sprite)
	dictionary_source.clear()
	root_dictionary.clear()
	TestSupport.remove_test_saves(test_save_dir)
	var shutdown_window := CsxHostClass.HostWindow.new(host)
	var shutdown_sprite := CsxHostClass.HostSprite.new(50, host)
	shutdown_window.add_sprite(0, shutdown_sprite)
	var shutdown_resource := CsxHostClass.HostResource.new("shutdown.mio", "fixture.noa", 0, 0, 0, host)
	shutdown_resource.fields["live"] = true
	var shutdown_manager := CsxHostClass.HostResourceManager.new(host)
	shutdown_manager.resource_cache["live"] = shutdown_resource
	host.active_messages[shutdown_sprite.get_instance_id()] = weakref(shutdown_sprite)
	host.shutdown_runtime()
	host.shutdown_runtime()
	expect(host.runtime_shutdown and host.runtime_sprites.is_empty() and host.runtime_resources.is_empty() and host.runtime_windows.is_empty() and host.runtime_services.is_empty(), "Host shutdown must be idempotent and release tracked runtime roots")
	expect(shutdown_window.root_sprites.is_empty() and shutdown_sprite.host == null and shutdown_resource.host == null and shutdown_manager.host == null, "Host shutdown must detach windows and clear host links on sprites, resources and managers")
	expect(host.active_messages.is_empty() and host.active_sprites.is_empty() and host.archives.is_empty() and host.image_cache.is_empty() and host.sound_cache.is_empty(), "Host shutdown must clear active registries, archives and media caches")
	finish_success("PASS Save storage atomicity and object round-trip contract smoke test")
