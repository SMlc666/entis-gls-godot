extends SceneTree

const NoaArchiveReader = preload("res://scripts/noa_archive.gd")
const EriMetadata = preload("res://scripts/eri_metadata.gd")
const EriDecoder = preload("res://scripts/eri_decoder.gd")
const ErisanDecoder = preload("res://scripts/erisan_decoder.gd")
const MioDecoder = preload("res://scripts/mio_decoder.gd")
const EntisSections = preload("res://scripts/entis_sections.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		printerr("Usage: godot --headless --path godot_port --script res://tests/linux_preview_smoke.gd -- /path/to/game")
		quit(2)
		return
	var game_dir := args[0]
	var archive_path := game_dir.path_join("data1.noa")
	var before := FileAccess.get_sha256(archive_path)
	if not _check(not before.is_empty(), "read initial archive hash"):
		quit(1)
		return

	var reader = NoaArchiveReader.new()
	var inspected: Dictionary = reader.inspect(archive_path)
	if not _check(inspected.get("ok", false), "open data1.noa"):
		quit(1)
		return
	var sample_index := -1
	for index in range(reader.entries.size()):
		if reader.entries[index]["name"] == "B01a.eri":
			sample_index = index
			break
	if not _check(sample_index >= 0, "find B01a.eri"):
		quit(1)
		return
	_check(not reader.read_entry(sample_index, 10).get("ok", false), "reject reads over caller limit")
	var content: Dictionary = reader.read_entry(sample_index)
	if not _check(content.get("ok", false), "read ERI entry"):
		quit(1)
		return
	var metadata: Dictionary = EriMetadata.inspect(content["data"])
	if not _check(metadata.get("ok", false), "parse ERI metadata"):
		quit(1)
		return
	_check(metadata["width"] == 800 and metadata["height"] == 600, "read ERI dimensions")
	_check(not EriMetadata.inspect(content["data"].slice(0, 70)).get("ok", false), "reject truncated ERI")
	var image_result: Dictionary = EriDecoder.decode(content["data"])
	if _check(image_result.get("ok", false), "decode ERI image"):
		var image: Image = image_result["image"]
		_check(image.get_width() == 800 and image.get_height() == 600, "decoded image dimensions")

	var scene = load("res://scenes/archive_inspector.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene._on_file_selected(archive_path)
	_check(scene.entries_list.item_count == mini(reader.entries.size(), scene.PAGE_SIZE), "paginate archive entries")
	scene._next_page()
	_check(scene.visible_indices[0] == scene.PAGE_SIZE, "navigate to second page")
	scene.search_input.text = "B01a.eri"
	scene._on_search_changed(scene.search_input.text)
	_check(scene.visible_indices.has(sample_index), "filter archive entries")
	scene._on_entry_selected(scene.visible_indices.find(sample_index))
	_check(scene.preview.texture != null, "show decoded image in UI")
	var title_path := game_dir.path_join("system/title.noa")
	var title_hash := FileAccess.get_sha256(title_path)
	var title: Dictionary = reader.inspect(title_path)
	if _check(title.get("ok", false), "open title archive"):
		var compressed_index := -1
		for index in range(reader.entries.size()):
			if reader.entries[index]["encoding_flags"] == 0x80000010 and String(reader.entries[index]["name"]).get_extension().to_lower() == "eri":
				compressed_index = index
				break
		if _check(compressed_index >= 0, "find compressed title entry"):
			var title_content: Dictionary = reader.read_entry(compressed_index)
			if _check(title_content.get("ok", false), "decompress title entry"):
				_check(EriMetadata.inspect(title_content["data"]).get("ok", false), "parse decompressed ERI")
				scene._on_file_selected(title_path)
				scene._on_entry_selected(compressed_index)
				_check(scene.preview.texture != null, "show compressed title image in UI")
			var header: Dictionary = reader.read_payload_header(compressed_index)
			if _check(header.get("ok", false) and int(header["stored_size"]) >= 4, "read compressed payload header"):
				var raw_file := FileAccess.open(title_path, FileAccess.READ)
				raw_file.seek(int(reader.entries[compressed_index]["payload_offset"]) + 16)
				var corrupted := raw_file.get_buffer(int(header["stored_size"]))
				corrupted[corrupted.size() - 1] ^= 1
				_check(not ErisanDecoder.decode(corrupted, int(reader.entries[compressed_index]["unpacked_size"])).get("ok", false), "reject corrupted ERISAN checksum")
	_check(title_hash == FileAccess.get_sha256(title_path), "title archive bytes unchanged")
	var voice_path := game_dir.path_join("voice.noa")
	scene._on_file_selected(voice_path)
	_check(scene.entries_list.item_count == scene.PAGE_SIZE, "paginate large voice archive")
	scene._on_entry_selected(0)
	if _check(scene.audio_player.stream != null and scene.audio_controls.visible, "decode voice stream in UI"):
		_check(scene.audio_player.stream.get_length() > 0, "voice has positive duration")
		scene._play_audio()
		_check(scene.audio_player.playing, "start voice playback")
		scene._stop_audio()
		_check(not scene.audio_player.playing, "stop voice playback")
	var voice_data: Dictionary = scene.reader.read_entry(0)
	if _check(voice_data.get("ok", false), "read voice entry"):
		_check(not MioDecoder.decode(voice_data["data"].slice(0, 70)).get("ok", false), "reject truncated MIO")
		var oversized: PackedByteArray = voice_data["data"].duplicate()
		var voice_header: Dictionary = EntisSections.find(oversized, 64, oversized.size(), "Header")
		if _check(voice_header.get("ok", false), "find MIO header"):
			var sound_info: Dictionary = EntisSections.find(oversized, voice_header["start"], voice_header["end"], "SoundInf")
			if _check(sound_info.get("ok", false), "find MIO sound information"):
				oversized.encode_u32(int(sound_info["start"]) + 28, 0xffffffff)
				_check(not MioDecoder.decode(oversized).get("ok", false), "reject excessive decoded audio size")
	var csx_path := game_dir.path_join("system/yosuga.csx")
	var csx_hash := FileAccess.get_sha256(csx_path)
	scene._on_csx_selected(csx_path)
	_check(scene.csx_index.functions.size() == 780 and scene.csx_index.prologue_addresses.size() == 321, "read CSX function table")
	_check(scene.csx_index.sections.size() == 6, "respect declared CSX section boundary")
	_check(scene.entries_list.item_count == scene.PAGE_SIZE, "paginate CSX function names")
	scene.search_input.text = "AddSelect"
	scene._on_search_changed(scene.search_input.text)
	if _check(scene.entries_list.item_count > 0, "search CSX function names"):
		scene._on_entry_selected(0)
		_check(scene.details_label.text.contains("AddSelect"), "show selected CSX function")
		_check(scene.details_label.text.contains("指令预览") and not scene.details_label.text.contains("无法继续解码"), "decode selected CSX function")
	_check(not scene.csx_index.inspect(archive_path).get("ok", false), "reject non-CSX file")
	var source_csx := FileAccess.open(csx_path, FileAccess.READ)
	var truncated_path := "user://csx-truncated-%d.csx" % OS.get_process_id()
	var truncated := FileAccess.open(truncated_path, FileAccess.WRITE)
	truncated.store_buffer(source_csx.get_buffer(64))
	truncated.close()
	source_csx.close()
	_check(not scene.csx_index.inspect(truncated_path).get("ok", false), "reject truncated CSX content")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(truncated_path))
	_check(csx_hash == FileAccess.get_sha256(csx_path), "CSX bytes unchanged")
	scene.queue_free()
	_check(not reader.inspect(game_dir.path_join("yosuga.exe")).get("ok", false), "reject non-NOA file")
	_check(not reader.read_entry(0).get("ok", false), "reject reads after failed inspect")
	_check(before == FileAccess.get_sha256(archive_path), "archive bytes unchanged")

	if failures == 0:
		print("PASS Linux NOA/CSX and ERI/MIO preview integration")
	quit(1 if failures else 0)


func _check(condition: bool, description: String) -> bool:
	if not condition:
		failures += 1
		printerr("FAIL: ", description)
	return condition
