extends SceneTree

const NoaArchiveReader = preload("res://scripts/noa_archive.gd")
const EriDecoder = preload("res://scripts/eri_decoder.gd")
const MioDecoder = preload("res://scripts/mio_decoder.gd")
const ExternalCodec = preload("res://scripts/external_codec.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		_fail("Pass the game directory after --")
		return
	if not ClassDB.class_exists("YzkCodec"):
		_fail("YzkCodec must be loaded before differential decoding")
		return

	var game_dir: String = args[0]
	var title_path := game_dir.path_join("system/title.noa")
	var sound_path := game_dir.path_join("sound.noa")
	var initial_hashes := {
		title_path: FileAccess.get_sha256(title_path),
		sound_path: FileAccess.get_sha256(sound_path),
	}
	var title_reader = NoaArchiveReader.new()
	var sound_reader = NoaArchiveReader.new()
	if not _check(title_reader.inspect(title_path).get("ok", false), "open title.noa"):
		return
	if not _check(sound_reader.inspect(sound_path).get("ok", false), "open sound.noa"):
		return

	var eri_data := _read_named_entry(title_reader, "FRM_0611.eri")
	if not _check(not eri_data.is_empty(), "read title base image"):
		return
	var native_image: Dictionary = EriDecoder.decode(eri_data)
	if not _check(native_image.get("ok", false), "decode ERI through native-first GDScript path"):
		return
	var helper_image: Dictionary = ExternalCodec.convert(eri_data, "entis/eri", "eri", "png")
	if not _check(helper_image.get("ok", false), "decode reference ERI with Linux helper"):
		return
	var reference_image := Image.new()
	if not _check(reference_image.load_png_from_buffer(helper_image["data"]) == OK, "load reference PNG"):
		return
	var actual_image: Image = native_image["image"]
	if not _check(actual_image.get_size() == reference_image.get_size(), "ERI dimensions must match the Linux helper"):
		return
	if not _check(actual_image.get_data() == reference_image.get_data(), "ERI RGBA bytes must match the Linux helper"):
		return

	var mio_data := _read_named_entry(sound_reader, "BGM07.mio")
	if not _check(not mio_data.is_empty(), "read title BGM"):
		return
	var native_audio: Dictionary = MioDecoder.decode(mio_data)
	if not _check(native_audio.get("ok", false), "decode MIO through native-first GDScript path"):
		return
	var helper_audio: Dictionary = ExternalCodec.convert(mio_data, "entis/mio", "mio", "wav")
	if not _check(helper_audio.get("ok", false), "decode reference MIO with Linux helper"):
		return
	var reference_stream := AudioStreamWAV.load_from_buffer(helper_audio["data"])
	var actual_stream: AudioStreamWAV = native_audio["stream"]
	if not _check(reference_stream != null, "load reference WAV"):
		return
	if not _check(actual_stream.mix_rate == reference_stream.mix_rate and actual_stream.stereo == reference_stream.stereo and actual_stream.format == reference_stream.format, "MIO format must match the Linux helper"):
		return
	if not _check(actual_stream.data == reference_stream.data, "MIO PCM bytes must match the Linux helper"):
		return

	for path: String in initial_hashes.keys():
		if not _check(FileAccess.get_sha256(path) == initial_hashes[path], "source archive bytes must remain unchanged: %s" % path):
			return
	print("PASS in-process ERI/MIO decode matches Linux helper byte-for-byte")
	quit(0)


func _read_named_entry(reader: Variant, entry_name: String) -> PackedByteArray:
	for index in range(reader.entries.size()):
		if String(reader.entries[index].get("name", "")).nocasecmp_to(entry_name) == 0:
			var result: Dictionary = reader.read_entry(index)
			return result.get("data", PackedByteArray()) if result.get("ok", false) else PackedByteArray()
	return PackedByteArray()


func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	_fail(message)
	return false


func _fail(message: String) -> void:
	printerr("FAIL ", message)
	quit(1)
