extends SceneTree

const HostClass = preload("res://scripts/csx_host.gd")

var fixture_dir := ""
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	fixture_dir = "user://test_fixtures/vfs_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var absolute_dir := ProjectSettings.globalize_path(fixture_dir)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if mkdir_error != OK:
		printerr("FAIL could not create isolated VFS fixture directory: %s" % error_string(mkdir_error))
		quit(1)
		return

	var first_path := absolute_dir.path_join("first.noa")
	var second_path := absolute_dir.path_join("second.noa")
	var duplicate_path := absolute_dir.path_join("duplicate.noa")
	var priority_root := absolute_dir.path_join("priority")
	var priority_system := priority_root.path_join("system")
	DirAccess.make_dir_recursive_absolute(priority_system)
	if not _write_archive(first_path, ["Shared/entry.eri", "token"]):
		_fail("could not write first archive")
		return
	if not _write_archive(second_path, ["Shared/entry.eri", "token.eri"]):
		_fail("could not write second archive")
		return
	if not _write_archive(duplicate_path, ["same.eri", "same.eri"]):
		_fail("could not write duplicate-entry archive")
		return
	if not _write_archive(priority_system.path_join("choice.noa"), ["shadowed.eri"]):
		_fail("could not write standard fallback archive")
		return
	if not _write_archive(priority_root.path_join("choice.noa"), ["authoritative.eri"]):
		_fail("could not write explicitly requested archive")
		return

	var host = HostClass.new()
	_check(host.get_or_open_archive(first_path) != null, "first NOA fixture should index")
	_check(host.get_or_open_archive(second_path) != null, "second NOA fixture should index")
	var first := host.find_vfs_entry("Shared/entry.eri")
	var second := host.find_vfs_entry("Shared/entry.eri", second_path)
	var canonical_first := ProjectSettings.globalize_path(first_path).simplify_path()
	var canonical_second := ProjectSettings.globalize_path(second_path).simplify_path()
	_check(not first.is_empty() and str(first.get("archive", "")) == canonical_first, "unhinted collision should choose deterministic first-loaded candidate")
	_check(not second.is_empty() and str(second.get("archive", "")) == canonical_second, "archive hint should select the matching archive candidate")
	_check(host.find_vfs_entry("SHARED/ENTRY.ERI").get("entry_name") == "shared/entry.eri", "archive path lookup should normalize case on Linux hosts")
	var extension_alias := host.find_vfs_entry("token", second_path)
	_check(not extension_alias.is_empty() and extension_alias.get("entry_name") == "token.eri", "an archive hint must search later extension aliases instead of stopping at an earlier mismatched candidate")
	_check(host._vfs_cache_key(first) != host._vfs_cache_key(second), "same internal path in different archives must have different cache keys")
	_check(host.get_vfs_conflict_report().size() == 1, "cross-archive conflict must be exposed in the conflict report")
	_check(host.find_vfs_entry("Shared/entry.eri", "missing.noa").is_empty(), "unmatched archive hint must fail instead of silently selecting another archive")
	_check(host.last_error.contains("归档提示"), "unmatched archive hint should leave an actionable error")

	# An explicit physical path wins over conventional system/<basename> probing,
	# even when a different archive with the same filename exists there.
	var priority_host = HostClass.new(priority_root)
	var authoritative_archive := priority_root.path_join("choice.noa")
	_check(priority_host.get_or_open_archive(authoritative_archive) != null, "explicit archive path must open")
	_check(not priority_host.find_vfs_entry("authoritative.eri", authoritative_archive).is_empty(), "explicit archive path must beat same-basename standard fallback")
	_check(priority_host.find_vfs_entry("shadowed.eri", authoritative_archive).is_empty(), "same-basename fallback must not satisfy an explicit archive hint")

	_check(host.get_or_open_archive(duplicate_path) != null, "duplicate-name NOA fixture should index")
	var duplicate_entries := host.find_vfs_entry("same.eri", duplicate_path)
	_check(not duplicate_entries.is_empty() and int(duplicate_entries.get("index", -1)) == 0, "same-archive duplicate should retain deterministic first-entry order")
	var duplicate_report := host.get_vfs_conflict_report()
	var saw_same_archive_duplicate := false
	for conflict: Dictionary in duplicate_report:
		if str(conflict.get("entry", "")) == "same.eri" and conflict.get("candidates", []).size() == 2:
			saw_same_archive_duplicate = true
	_check(saw_same_archive_duplicate, "same-archive duplicate entries must remain visible in the conflict report")

	_remove_fixture_dir()
	if failures.is_empty():
		print("PASS VFS archive identity, collision diagnostics, and cache-key smoke test")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL ", failure)
		quit(1)


func _write_archive(path: String, entry_names: Array[String]) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(PackedByteArray([0x45, 0x6e, 0x74, 0x69, 0x73, 0x1a, 0x00, 0x00]))
	file.store_32(0x02000400)
	file.store_32(0)
	var marker := "ERISA-Archive file".to_ascii_buffer()
	file.store_buffer(marker)
	file.store_buffer(PackedByteArray())
	for _index in range(40 - marker.size()):
		file.store_8(0)
	for _header_padding in range(8):
		file.store_8(0)
	file.store_buffer("DirEntry".to_ascii_buffer())
	var section_size := 4
	for entry_name in entry_names:
		section_size += 40 + entry_name.to_utf8_buffer().size()
	file.store_64(section_size)
	file.store_32(entry_names.size())
	for entry_name in entry_names:
		var name_bytes := entry_name.to_utf8_buffer()
		file.store_64(0) # unpacked size
		file.store_32(0) # regular file
		file.store_32(0) # uncompressed
		file.store_64(0) # relative payload offset; this test reads only the index
		for _reserved in range(8):
			file.store_8(0)
		file.store_32(0) # extra field size
		file.store_32(name_bytes.size())
		file.store_buffer(name_bytes)
	var result := file.get_error() == OK
	file.close()
	return result


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
