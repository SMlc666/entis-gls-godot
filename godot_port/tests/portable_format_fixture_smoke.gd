extends SceneTree

const NoaArchiveReader = preload("res://scripts/noa_archive.gd")
const CsxBytecodeReader = preload("res://scripts/csx_bytecode.gd")
const CgThumbnailCache = preload("res://scripts/cg_thumbnail_cache.gd")

var fixture_dir := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	fixture_dir = "user://test_fixtures/portable_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var absolute_dir := ProjectSettings.globalize_path(fixture_dir)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if mkdir_error != OK:
		_fail("Unable to create isolated fixture directory: %s" % error_string(mkdir_error))
		return

	if not _check_empty_noa_fixture(absolute_dir):
		return
	if not _check_noa_rejections(absolute_dir):
		return
	if not _check_bytecode_bounds():
		return
	if not _check_thumbnail_cache_budget():
		return

	_remove_fixture_dir()
	print("PASS Portable NOA and CSX bytecode fixture smoke test")
	quit(0)


func _check_empty_noa_fixture(absolute_dir: String) -> bool:
	var path := absolute_dir.path_join("empty.noa")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("Unable to create NOA fixture")
		return false
	file.store_buffer(PackedByteArray([0x45, 0x6e, 0x74, 0x69, 0x73, 0x1a, 0x00, 0x00]))
	file.store_32(0x02000400)
	file.store_32(0)
	file.store_buffer("ERISA-Archive file".to_ascii_buffer())
	file.resize(0x40)
	file.close()

	var reader = NoaArchiveReader.new()
	var result: Dictionary = reader.inspect(path)
	if not result.get("ok", false) or result.get("entry_count", -1) != 0:
		_fail("Generated empty NOA header should parse: %s" % result.get("error", "unexpected result"))
		return false
	print("  Generated 64-byte empty NOA header accepted")
	return true


func _check_noa_rejections(absolute_dir: String) -> bool:
	var short_path := absolute_dir.path_join("short.noa")
	var short_file := FileAccess.open(short_path, FileAccess.WRITE)
	short_file.store_buffer(PackedByteArray([0x45, 0x6e, 0x74, 0x69]))
	short_file.close()
	var reader = NoaArchiveReader.new()
	var short_result: Dictionary = reader.inspect(short_path)
	if short_result.get("ok", true) or str(short_result.get("error", "")).is_empty():
		_fail("A truncated NOA header must be rejected with an error")
		return false

	var bad_path := absolute_dir.path_join("bad_header.noa")
	var bad_file := FileAccess.open(bad_path, FileAccess.WRITE)
	bad_file.store_buffer(PackedByteArray())
	bad_file.resize(0x40)
	bad_file.close()
	var bad_result: Dictionary = reader.inspect(bad_path)
	if bad_result.get("ok", true) or str(bad_result.get("error", "")).is_empty():
		_fail("A wrong NOA marker must be rejected with an error")
		return false
	print("  Truncated and invalid NOA headers rejected")
	return true


func _check_bytecode_bounds() -> bool:
	var decoder = CsxBytecodeReader.new()
	var truncated: Dictionary = decoder.decode(PackedByteArray([9]), 0, 1)
	if truncated.get("ok", true) or str(truncated.get("error", "")).is_empty():
		_fail("A return opcode truncated before its operand must fail structurally")
		return false
	var valid: Dictionary = decoder.decode(PackedByteArray([9, 0]), 0, 1)
	if not valid.get("ok", false) or valid.get("instructions", []).size() != 1:
		_fail("A minimal valid return instruction should decode")
		return false
	print("  Truncated opcode rejected and minimal return instruction decoded")
	return true


func _check_thumbnail_cache_budget() -> bool:
	var cache = CgThumbnailCache.new()
	var source := Image.create(1200, 600, false, Image.FORMAT_RGBA8)
	source.fill(Color(0.25, 0.5, 0.75, 1.0))
	var texture: Texture2D = cache.cache_image("oldest", source)
	if texture == null or texture.get_width() > CgThumbnailCache.MAX_DIMENSION or texture.get_height() > CgThumbnailCache.MAX_DIMENSION:
		_fail("Large CG source must be resized to the thumbnail dimension limit")
		return false
	for index in range(50):
		cache.cache_image("image_%d" % index, source)
	if cache.cached_bytes() > CgThumbnailCache.MAX_BYTES:
		_fail("Thumbnail cache must remain within its byte budget")
		return false
	if cache.get_texture("oldest") != null:
		_fail("Thumbnail cache must evict least-recently-used entries over budget")
		return false
	cache.clear()
	if cache.cached_bytes() != 0:
		_fail("Clearing thumbnail cache must release its accounting budget")
		return false
	print("  Large CG thumbnail resized; LRU cache stayed within budget")
	return true


func _remove_fixture_dir() -> void:
	var absolute_dir := ProjectSettings.globalize_path(fixture_dir)
	var directory := DirAccess.open(absolute_dir)
	if directory != null:
		for file_name in directory.get_files():
			DirAccess.remove_absolute(absolute_dir.path_join(file_name))
	DirAccess.remove_absolute(absolute_dir)


func _fail(message: String) -> void:
	printerr("FAIL ", message)
	_remove_fixture_dir()
	quit(1)
