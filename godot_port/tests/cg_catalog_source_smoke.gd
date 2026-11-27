extends SceneTree

const AdvPlayerScript = preload("res://scripts/adv_player.gd")

class RecordingHost extends "res://scripts/csx_host.gd":
	var image_requests: Array[Dictionary] = []

	func load_image(filename: String, archive_hint: String = "") -> Dictionary:
		var entry: Dictionary = find_vfs_entry(filename, archive_hint)
		image_requests.append({
			"name": filename,
			"archive_hint": archive_hint,
			"archive": str(entry.get("archive", "")),
			"entry_index": int(entry.get("index", -1)),
		})
		var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		return {"ok": not entry.is_empty(), "image": image, "texture": ImageTexture.create_from_image(image)}

var fixture_dir := ""
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	fixture_dir = "user://test_fixtures/cg_sources_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var absolute_dir := ProjectSettings.globalize_path(fixture_dir)
	var expected_data1_archive := absolute_dir.path_join("data1.noa").simplify_path()
	var expected_data2_archive := absolute_dir.path_join("data2.noa").simplify_path()
	var mkdir_error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if mkdir_error != OK:
		_fail("Unable to create isolated CG source fixtures: %s" % error_string(mkdir_error))
		return

	if not _write_archive(absolute_dir.path_join("data1.noa"), ["EA01.eri"]):
		_fail("Unable to create data1.noa fixture")
		return
	if not _write_archive(absolute_dir.path_join("data2.noa"), ["EA01.eri"]):
		_fail("Unable to create data2.noa fixture")
		return

	var host = RecordingHost.new(absolute_dir)
	var data1 = host.get_or_open_archive("data1.noa")
	var data2 = host.get_or_open_archive("data2.noa")
	_check(data1 != null and data1.entries.size() == 1, "data1 fixture should expose one indexed CG entry")
	_check(data2 != null and data2.entries.size() == 1, "data2 fixture should expose one indexed CG entry")
	if data1 != null and data1.entries.size() == 1:
		_check(str(data1.entries[0].get("name", "")) == "EA01.eri", "data1 fixture entry name should match the CG filename pattern")
	var player = AdvPlayerScript.new()
	player.host = host
	player._init_cg_catalog()
	var scenes: Array = player.cg_catalog.get("EA", [])
	_check(scenes.size() == 1 and str(scenes[0].get("scene_id", "")) == "EA01", "Same-name CG entries should group as one scene")
	if scenes.size() != 1:
		player.free()
		_finish()
		return

	var scene: Dictionary = scenes[0]
	var file_refs: Array = scene.get("file_refs", [])
	_check(file_refs.size() == 2, "Catalog should preserve both archive sources for the duplicate CG name")
	_check(scene.get("files", []).size() == 2, "Legacy filename list should preserve both variants")
	if file_refs.size() == 2:
		var first_ref: Dictionary = file_refs[0]
		var second_ref: Dictionary = file_refs[1]
		_check(str(first_ref.get("name", "")) == "EA01.eri", "First catalog source should retain the internal entry name")
		_check(str(first_ref.get("archive_hint", "")) == "data1.noa", "First catalog source should retain data1 archive hint")
		_check(str(second_ref.get("archive_hint", "")) == "data2.noa", "Second catalog source should retain data2 archive hint")
		_check(int(first_ref.get("entry_index", -1)) == 0 and int(second_ref.get("entry_index", -1)) == 0, "Catalog sources should retain entry indices")

		var first_vfs_entry: Dictionary = host.find_vfs_entry(str(first_ref["name"]), str(first_ref["archive_hint"]))
		var second_vfs_entry: Dictionary = host.find_vfs_entry(str(second_ref["name"]), str(second_ref["archive_hint"]))
		_check(str(first_vfs_entry.get("archive", "")) == expected_data1_archive, "data1 hint should resolve to the matching VFS candidate")
		_check(str(second_vfs_entry.get("archive", "")) == expected_data2_archive, "data2 hint should resolve to the matching VFS candidate")
		var first_cache_key := player._cg_thumbnail_cache_key(first_ref)
		var second_cache_key := player._cg_thumbnail_cache_key(second_ref)
		_check(first_cache_key != second_cache_key, "Thumbnail cache keys must differ for the same internal name from different archives")
		_check(first_cache_key.contains("data1.noa") and first_cache_key.contains("ea01.eri#0"), "Thumbnail key should include archive and entry identity")

		var card: Control = player._create_cg_card(scene)
		_check(host.image_requests.size() == 1 and str(host.image_requests[0].get("archive_hint", "")) == "data1.noa", "CG card thumbnail load should pass its source archive hint")
		_check(str(host.image_requests[0].get("archive", "")) == expected_data1_archive, "CG card thumbnail should resolve from its recorded archive")
		_check(player.cg_thumbnail_cache.get_texture(first_cache_key) != null, "CG card should cache its thumbnail under the source identity key")

		player.cg_fullscreen_panel = PanelContainer.new()
		player.fullscreen_cg_rect = TextureRect.new()
		player.fullscreen_info_label = Label.new()
		player._open_cg_fullscreen(scene)
		_check(host.image_requests.size() == 2 and str(host.image_requests[1].get("archive_hint", "")) == "data1.noa", "First fullscreen variant should use its recorded archive")
		player._next_cg_variant()
		_check(player.fullscreen_variant_index == 1 and host.image_requests.size() == 3, "Next fullscreen variant should load the second archive source")
		_check(str(host.image_requests[2].get("archive_hint", "")) == "data2.noa", "Second fullscreen variant should pass data2 archive hint")
		_check(str(host.image_requests[2].get("archive", "")) == expected_data2_archive, "Second fullscreen variant should resolve from data2")
		card.free()
		player.cg_fullscreen_panel.free()
		player.fullscreen_cg_rect.free()
		player.fullscreen_info_label.free()
	player.free()

	_finish()


func _write_archive(path: String, entry_names: Array[String]) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(PackedByteArray([0x45, 0x6e, 0x74, 0x69, 0x73, 0x1a, 0x00, 0x00]))
	file.store_32(0x02000400)
	file.store_32(0)
	var marker := "ERISA-Archive file".to_ascii_buffer()
	file.store_buffer(marker)
	for _index in range(40 - marker.size()):
		file.store_8(0)
	for _padding in range(8):
		file.store_8(0)
	file.store_buffer("DirEntry".to_ascii_buffer())
	var section_size := 4
	for entry_name in entry_names:
		section_size += 40 + entry_name.to_utf8_buffer().size()
	file.store_64(section_size)
	file.store_32(entry_names.size())
	for entry_name in entry_names:
		var name_bytes := entry_name.to_utf8_buffer()
		file.store_64(0)
		file.store_32(0)
		file.store_32(0)
		file.store_64(0)
		for _reserved in range(8):
			file.store_8(0)
		file.store_32(0)
		file.store_32(name_bytes.size())
		file.store_buffer(name_bytes)
	var ok := file.get_error() == OK
	file.close()
	return ok


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _fail(message: String) -> void:
	failures.append(message)
	_finish()


func _finish() -> void:
	_remove_fixture_dir()
	if failures.is_empty():
		print("PASS CG catalog archive identity and thumbnail cache key smoke test")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL ", failure)
		quit(1)


func _remove_fixture_dir() -> void:
	if fixture_dir.is_empty():
		return
	var absolute_dir := ProjectSettings.globalize_path(fixture_dir)
	var directory := DirAccess.open(absolute_dir)
	if directory != null:
		for file_name in directory.get_files():
			DirAccess.remove_absolute(absolute_dir.path_join(file_name))
	DirAccess.remove_absolute(absolute_dir)
