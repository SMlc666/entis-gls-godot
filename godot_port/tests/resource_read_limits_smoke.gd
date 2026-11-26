extends SceneTree

const BoundedFileReader = preload("res://scripts/bounded_file_reader.gd")
const CsxIndexReader = preload("res://scripts/csx_index.gd")
const CsxHostClass = preload("res://scripts/csx_host.gd")

var fixture_dir := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	fixture_dir = "user://test_fixtures/read_limits_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var absolute_dir := ProjectSettings.globalize_path(fixture_dir)
	if DirAccess.make_dir_recursive_absolute(absolute_dir) != OK:
		_fail("Could not create resource-limit fixtures")
		return
	var small_path := absolute_dir.path_join("small.bin")
	var small_file := FileAccess.open(small_path, FileAccess.WRITE)
	small_file.store_buffer(PackedByteArray([1, 2, 3, 4]))
	small_file.close()
	var small_result: Dictionary = BoundedFileReader.read(small_path, 4)
	_check(small_result.get("ok", false) and small_result.get("data") == PackedByteArray([1, 2, 3, 4]), "A file at the configured limit must read completely")

	var oversized_path := absolute_dir.path_join("oversized.bin")
	var oversized_file := FileAccess.open(oversized_path, FileAccess.WRITE)
	oversized_file.store_8(0)
	var resize_error := oversized_file.resize(4 * 1024 * 1024 + 1)
	oversized_file.close()
	_check(resize_error == OK, "Sparse oversized fixture must be created")
	var oversized_result: Dictionary = BoundedFileReader.read(oversized_path, 4 * 1024 * 1024)
	_check(not oversized_result.get("ok", true) and str(oversized_result.get("error", "")).contains("超过读取上限"), "Oversized files must be rejected before allocating their contents")

	var oversized_csx_path := absolute_dir.path_join("oversized.csx")
	var oversized_csx := FileAccess.open(oversized_csx_path, FileAccess.WRITE)
	oversized_csx.store_8(0)
	resize_error = oversized_csx.resize(CsxIndexReader.MAX_CSX_FILE_BYTES + 1)
	oversized_csx.close()
	_check(resize_error == OK, "Sparse oversized CSX fixture must be created")
	var index_reader = CsxIndexReader.new()
	var index_result: Dictionary = index_reader.inspect(oversized_csx_path)
	_check(not index_result.get("ok", true) and str(index_result.get("error", "")).contains("超过读取上限"), "CSX files above the whole-file cap must be rejected during inspection")
	var host = CsxHostClass.new("")
	host.cached_media_budget_bytes = 5
	host.image_cache["image"] = {"bytes": 4}
	host.image_cache_lru.append("image")
	host.image_cache_bytes = 4
	var sound := AudioStreamWAV.new()
	sound.data = PackedByteArray([1, 2, 3, 4])
	host.sound_cache["sound"] = sound
	host.sound_cache_lru.append("sound")
	host.sound_cache_bytes = sound.data.size()
	host._trim_combined_media_cache()
	_check(host.image_cache_bytes + host.sound_cache_bytes <= host.cached_media_budget_bytes, "Image and audio cache entries must share one combined resident-cache budget")

	_remove_fixture_dir()
	if failures.is_empty():
		print("PASS bounded file, CSX input, and combined media cache limit smoke test")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL ", failure)
		quit(1)


var failures: Array[String] = []


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _fail(message: String) -> void:
	printerr("FAIL ", message)
	_remove_fixture_dir()
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
