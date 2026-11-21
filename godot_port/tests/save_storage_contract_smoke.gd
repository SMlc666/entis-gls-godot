extends "res://tests/smoke_test_base.gd"

const CsxHostClass = preload("res://scripts/csx_host.gd")
const CsxVMClass = preload("res://scripts/csx_vm.gd")
const TestSupport = preload("res://tests/test_support.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var test_save_dir := TestSupport.new_save_dir("save_storage_contract")
	var host = CsxHostClass.new("")
	host.save_dir = test_save_dir
	var vm = CsxVMClass.new(host)
	var file_name := "round_trip.json"
	var source = CsxVMClass.CsxInstance.new("SaveFixture")
	var source_sprite = CsxHostClass.HostSprite.new(7, host)
	source_sprite.filename = "FRM_TEST.eri"
	source_sprite.archive_hint = "fixture.noa"
	source_sprite.position = Vector2i(31, 47)
	source_sprite.rev_center = Vector2i(15, 20)
	source_sprite.magnification = Vector2(0.95, 0.97)
	source_sprite.message_style = {"id": "ID_FONT_MESSAGE", "font": {"size": "24"}}
	source_sprite.is_visible = true
	source_sprite.transparency = 12
	source_sprite.fields = {"checked": true, "page": 3, "metadata": {"label": "fixture"}}
	var source_resource = CsxHostClass.HostResource.new("fixture.eri", "fixture.noa", 2, 16, 128, host)
	source_resource.is_playing = true
	source_resource.current_position = 2400
	source_resource.playback_end_frame = 8400
	source_resource.playback_rewind_frame = 1200
	source_resource.is_repeating = true
	source_resource.fields = {"kind": "image", "custom_state": [1, "two", false]}
	source.set_field("sprite", source_sprite)
	source.set_field("sprite_alias", source_sprite)
	source.set_field("resource", source_resource)
	var cyclic_fields: Dictionary = {}
	cyclic_fields["self"] = cyclic_fields
	source.set_field("cyclic_fields", cyclic_fields)
	source.set_field("counter", 42)

	expect(host.save_object_file(file_name, source), "A valid snapshot must save")
	var save_path: String = host.get_save_path(file_name)
	var stable_contents := FileAccess.get_file_as_string(save_path)
	expect(not stable_contents.is_empty() and JSON.parse_string(stable_contents) != null, "Saved snapshot must be complete valid JSON")

	var restored = CsxVMClass.CsxInstance.new("SaveFixture")
	expect(host.load_object_file(file_name, restored, vm), "The saved fixture must load")
	expect(restored.type_name == "SaveFixture", "CsxInstance type must round-trip")
	expect(restored.get_field("counter") == 42, "Primitive CSX fields must round-trip")
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
		expect(restored_sprite.filename == "FRM_TEST.eri", "HostSprite filename must round-trip")
		expect(restored_sprite.archive_hint == "fixture.noa", "HostSprite archive identity must round-trip")
		expect(restored_sprite.position == Vector2i(31, 47), "HostSprite position must round-trip")
		expect(restored_sprite.rev_center == Vector2i(15, 20), "HostSprite pivot must round-trip")
		expect(restored_sprite.magnification.is_equal_approx(Vector2(0.95, 0.97)), "HostSprite magnification must round-trip")
		expect(restored_sprite.message_style.get("font", {}).get("size") == "24", "HostSprite message style must round-trip")
		expect(restored_sprite.is_visible and restored_sprite.transparency == 12, "HostSprite visibility state must round-trip")
		expect(restored_sprite.fields.get("checked") == true, "HostSprite.fields must round-trip")
		expect(restored_sprite.fields.get("metadata", {}).get("label") == "fixture", "Nested HostSprite.fields must round-trip")
	var restored_resource: Variant = restored.get_field("resource")
	expect(restored_resource is CsxHostClass.HostResource, "HostResource must restore as a HostResource")
	if restored_resource is CsxHostClass.HostResource:
		expect(restored_resource.name == "fixture.eri", "HostResource name must round-trip")
		expect(restored_resource.is_playing, "HostResource playback state must round-trip")
		expect(restored_resource.current_position == 2400, "Saved playback position must retain its frame units")
		expect(restored_resource.is_repeating and restored_resource.playback_end_frame == 8400 and restored_resource.playback_rewind_frame == 1200, "Custom playback loop must survive save and load")
		expect(restored_resource.fields.get("custom_state") == [1, "two", false], "HostResource.fields values must round-trip with their original types")
	var restored_cycle: Variant = restored.get_field("cyclic_fields")
	expect(restored_cycle is Dictionary and is_same(restored_cycle, restored_cycle.get("self")), "Cyclic dictionaries must round-trip without recursion")

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
	expect(host.load_object_file(slot_name, final_loaded, vm), "Missing primary snapshot must load from backup")
	expect(final_loaded.get_field("counter") == 42, "Recovered backup must contain the earlier state")
	var damaged := FileAccess.open(slot_path, FileAccess.WRITE)
	damaged.store_string("{}")
	damaged.close()
	expect(host.load_object_file(slot_name, final_loaded, vm), "Structurally invalid primary must load from backup")
	expect(final_loaded.get_field("counter") == 42, "Invalid primary must not replace the valid backup")
	expect(host.save_object_file(slot_name, source), "Saving after recovery must succeed")
	expect(not host.read_save_snapshot(backup_path, false).is_empty(), "Saving after recovery must retain the valid backup")

	var corrupt_slot := FileAccess.open(host.get_save_path("Save004.dat"), FileAccess.WRITE)
	corrupt_slot.store_string("{}")
	corrupt_slot.close()
	expect(not host.is_file_existing("Save004.dat"), "A damaged slot without a backup must be unavailable")

	TestSupport.remove_test_saves(test_save_dir)
	finish_success("PASS Save storage atomicity and object round-trip contract smoke test")
