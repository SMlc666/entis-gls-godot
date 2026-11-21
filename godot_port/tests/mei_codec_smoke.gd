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
	var frames: Array = result.get("video_frame_info", [])
	if frames.size() != 2520:
		_fail("expected 2520 video frame records, got %d" % frames.size())
		return
	var expected_pictures := ["I", "B", "B", "P", "B", "B", "P", "B"]
	for index: int in expected_pictures.size():
		var frame: Dictionary = frames[index]
		if int(frame.get("index", -1)) != index or str(frame.get("picture_type", "")) != expected_pictures[index]:
			_fail("unexpected frame metadata at index %d: %s" % [index, frame])
			return
	var i_count := 0
	var p_count := 0
	var b_count := 0
	for frame_variant: Variant in frames:
		match str(frame_variant.get("picture_type", "")):
			"I": i_count += 1
			"P": p_count += 1
			"B": b_count += 1
			_:
				_fail("unknown MEI frame type: %s" % frame_variant)
				return
	if i_count != 582 or p_count != 259 or b_count != 1679:
		_fail("unexpected I/P/B frame counts: %d/%d/%d" % [i_count, p_count, b_count])
		return
	if not codec.has_method("decode_mei_i_frame"):
		_fail("YzkCodec must expose random access to independent MEI I-frames")
		return
	var second_i_index := -1
	for index: int in range(1, frames.size()):
		if str(frames[index].get("picture_type", "")) == "I":
			second_i_index = index
			break
	if second_i_index < 0:
		_fail("MEI stream has no second I-frame to validate random access")
		return
	var second_i: Variant = codec.call("decode_mei_i_frame", original, second_i_index)
	if not second_i is Dictionary or not second_i.get("ok", false):
		_fail("second I-frame decode failed: %s" % (second_i.get("error", "invalid result") if second_i is Dictionary else "invalid result"))
		return
	if int(second_i.get("frame_index", -1)) != second_i_index:
		_fail("I-frame decoder returned the wrong frame index")
		return
	var second_pixels: PackedByteArray = second_i.get("rgba", PackedByteArray())
	if second_pixels.size() != 800 * 600 * 4:
		_fail("second I-frame RGBA output has wrong size: %d" % second_pixels.size())
		return
	if int(second_i.get("min_luma", 0)) >= int(second_i.get("max_luma", 0)):
		_fail("second I-frame reconstruction produced a uniform image")
		return
	var b_frame: Variant = codec.call("decode_mei_i_frame", original, 1)
	if not b_frame is Dictionary or b_frame.get("ok", true):
		_fail("random access must not decode a differential B-frame without references")
		return
	if result.get("video_frames_decoded", true):
		_fail("decoder must not claim that ERI Layer-3 frames are decoded")
		return
	if not result.get("first_frame_entropy_decoded", false):
		_fail("first I-frame entropy decode failed: %s" % result.get("video_error", "missing error"))
		return
	if int(result.get("first_frame_coefficient_count", -1)) != 729600:
		_fail("expected 729600 decoded first-frame coefficients, got %s" % result.get("first_frame_coefficient_count", "missing"))
		return
	var coefficients: PackedByteArray = result.get("first_frame_coefficients", PackedByteArray())
	if coefficients.size() != 729600:
		_fail("first I-frame coefficient payload has wrong size: %d" % coefficients.size())
		return
	if not result.get("first_frame_decoded", false):
		_fail("first I-frame pixel reconstruction failed: %s" % result.get("video_error", "missing error"))
		return
	var first_frame: PackedByteArray = result.get("first_frame_rgba", PackedByteArray())
	if first_frame.size() != 800 * 600 * 4:
		_fail("first I-frame RGBA output has wrong size: %d" % first_frame.size())
		return
	for pixel_index: int in range(3, first_frame.size(), 4):
		if first_frame[pixel_index] != 255:
			_fail("first I-frame alpha is not opaque at byte %d" % pixel_index)
			return
	if FileAccess.get_file_as_bytes(movie_path) != original:
		_fail("decode_mei modified the original movie")
		return
	print("PASS MEI container/audio decode and random access to native I-frames")
	quit(0)


func _fail(message: String) -> void:
	printerr("FAIL %s" % message)
	quit(1)
