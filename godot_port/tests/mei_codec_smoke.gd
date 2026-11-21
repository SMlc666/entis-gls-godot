extends SceneTree


func _initialize() -> void:
	if not ClassDB.class_exists("YzkCodec"):
		_fail("native GDExtension must register YzkCodec")
		return
	var codec: Object = ClassDB.instantiate("YzkCodec")
	if codec == null or not codec.has_method("decode_mei"):
		_fail("YzkCodec must expose decode_mei")
		return
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		_fail("usage: mei_codec_smoke.gd -- /path/to/YosugaGame")
		return
	var movie_path := args[0].path_join("opening.mei")
	if not FileAccess.file_exists(movie_path):
		_fail("opening.mei not found at %s" % movie_path)
		return
	var original := FileAccess.get_file_as_bytes(movie_path)
	var result: Variant = codec.call("decode_mei", original)
	if not result is Dictionary or not result.get("ok", false):
		_fail("decode_mei failed: %s" % (result.get("error", "invalid result") if result is Dictionary else "invalid result"))
		return
	var expected := {
		"width": 800,
		"height": 600,
		"frame_count": 2521,
		"frame_record_count": 2520,
		"duration_ms": 126000,
		"sample_count_per_channel": 5556600,
		"channels": 2,
		"sample_rate": 44100,
		"bits_per_sample": 16,
	}
	for key: String in expected:
		if int(result.get(key, -1)) != expected[key]:
			_fail("%s expected %s, got %s" % [key, expected[key], result.get(key, "missing")])
			return
	var decoded_audio: PackedByteArray = result.get("audio_data", PackedByteArray())
	if decoded_audio.size() != 22226400:
		_fail("expected audio output of 22226400 bytes, got %d" % decoded_audio.size())
		return
	if result.get("video_frames_decoded", true):
		_fail("decoder must not claim that ERI Layer-3 frames are decoded")
		return
	if not str(result.get("video_error", "")).contains("Layer-3"):
		_fail("undecoded video boundary must identify ERI Layer-3")
		return
	if FileAccess.get_file_as_bytes(movie_path) != original:
		_fail("decode_mei modified the original movie")
		return
	print("PASS MEI container/audio decode; ERI video-frame boundary is explicit")
	quit(0)


func _fail(message: String) -> void:
	printerr("FAIL %s" % message)
	quit(1)
