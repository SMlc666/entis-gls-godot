extends SceneTree

const Host = preload("res://scripts/csx_host.gd")
const TestSupport = preload("res://tests/test_support.gd")
var _save_dir := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_save_dir = TestSupport.new_save_dir("thumbnail_bounds")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_save_dir))
	var host = Host.new("")
	host.save_dir = _save_dir
	var png := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	png.fill(Color(0.2, 0.4, 0.8, 1.0))
	var valid_png := png.save_png_to_buffer()
	var manifest_path: String = host.get_save_path("QSave.dat")
	var manifest := {
		"__yzk_save_document__": true,
		"thumbnail_file": "legacy_preview.png"
	}
	if not _write_bytes(_save_dir.path_join("legacy_preview.png"), valid_png):
		_fail("Could not write valid PNG fixture")
		return
	if not _write_text(manifest_path, JSON.stringify(manifest)):
		_fail("Could not write legacy save manifest")
		return
	if not host.is_thumbnail_current("QSave.dat"):
		_fail("Legacy thumbnail without a hash must still pass bounded PNG validation")
		return
	var loaded: Dictionary = host.load_thumbnail_image("QSave.dat")
	if not loaded.get("ok", false) or (loaded.get("image") as Image).get_size() != Vector2i(2, 2):
		_fail("Valid legacy PNG must decode after header and file-size checks")
		return

	manifest["thumbnail_file"] = "bomb.png"
	if not _write_bytes(_save_dir.path_join("bomb.png"), _png_header(100000, 100000)):
		_fail("Could not write PNG bomb header fixture")
		return
	if not _write_text(manifest_path, JSON.stringify(manifest)):
		_fail("Could not update legacy save manifest")
		return
	if host.is_thumbnail_current("QSave.dat"):
		_fail("A PNG declaring dimensions above the cap must not be accepted as current")
		return
	if host.load_thumbnail_image("QSave.dat").get("ok", false):
		_fail("A PNG bomb header must be rejected before image decoding")
		return

	manifest["thumbnail_sha256"] = "not-the-hash"
	if not _write_text(manifest_path, JSON.stringify(manifest)):
		_fail("Could not update hashed save manifest")
		return
	if host.is_thumbnail_current("QSave.dat") or host.load_thumbnail_image("QSave.dat").get("ok", false):
		_fail("A hashed thumbnail must still satisfy bounded PNG and digest checks")
		return

	TestSupport.remove_test_saves(_save_dir)
	host.shutdown_runtime()
	print("PASS thumbnail byte, PNG header, pixel budget and legacy manifest checks")
	quit(0)


func _png_header(width: int, height: int) -> PackedByteArray:
	var bytes := PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10])
	_append_u32_be(bytes, 13)
	bytes.append_array("IHDR".to_ascii_buffer())
	_append_u32_be(bytes, width)
	_append_u32_be(bytes, height)
	bytes.append_array(PackedByteArray([8, 6, 0, 0, 0]))
	_append_u32_be(bytes, 0) # CRC is irrelevant: dimensions must be rejected before decode.
	return bytes


func _append_u32_be(bytes: PackedByteArray, value: int) -> void:
	bytes.append((value >> 24) & 0xff)
	bytes.append((value >> 16) & 0xff)
	bytes.append((value >> 8) & 0xff)
	bytes.append(value & 0xff)


func _write_bytes(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.close()
	return true


func _write_text(path: String, value: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(value)
	file.close()
	return true


func _fail(message: String) -> void:
	if not _save_dir.is_empty():
		TestSupport.remove_test_saves(_save_dir)
	printerr("FAIL ", message)
	quit(1)
