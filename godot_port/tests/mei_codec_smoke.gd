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
	var operation_flag_counts := {}
	for frame_variant: Variant in frames:
		var operation_flags := int(frame_variant.get("operation_flags", -1))
		operation_flag_counts[operation_flags] = int(operation_flag_counts.get(operation_flags, 0)) + 1
		if (operation_flags & 0x0c) != 0:
			_fail("opening.mei unexpectedly requests an ERI loop filter: %s" % frame_variant)
			return
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
	if operation_flag_counts != {0: 582, 1: 259, 3: 1679}:
		_fail("unexpected ERI operation flag distribution: %s" % operation_flag_counts)
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
	var image_record_ordinal := 0
	for index: int in range(second_i_index):
		if str(frames[index].get("record_type", "")) == "ImageFrm":
			image_record_ordinal += 1
	var second_image_header := _find_record_header(original, "ImageFrm", image_record_ordinal)
	if second_image_header < 0:
		_fail("could not locate the second I-frame in the read-only source bytes")
		return
	var filtered_mei := original.duplicate()
	var original_operation_flags := int(frames[second_i_index].get("operation_flags", 0))
	if filtered_mei[second_image_header] != 0x28 or filtered_mei[second_image_header + 1] != original_operation_flags:
		_fail("second I-frame section lookup does not match the parsed frame metadata")
		return
	filtered_mei[second_image_header + 1] |= 0x08
	if filtered_mei[second_image_header + 1] != (original_operation_flags | 0x08):
		_fail("could not enable the local 4-2-1 operation-table flag in memory")
		return
	var filtered_i: Variant = codec.call("decode_mei_i_frame", filtered_mei, second_i_index)
	if not filtered_i is Dictionary or not filtered_i.get("ok", false):
		_fail("SDK 4-2-1 loop-filter I-frame decode failed")
		return
	var filtered_pixels: PackedByteArray = filtered_i.get("rgba", PackedByteArray())
	var filtered_byte_count := 0
	for index: int in second_pixels.size():
		if second_pixels[index] != filtered_pixels[index]:
			filtered_byte_count += 1
	if filtered_byte_count == 0:
		_fail("SDK local 4-2-1 frame flag did not filter the second I-frame")
		return
	if _changed_byte_count(second_pixels, filtered_i.get("reference_rgba", PackedByteArray())) != 0:
		_fail("local filtering changed the raw I-frame prediction reference")
		return
	var full_filtered_mei := original.duplicate()
	full_filtered_mei[second_image_header + 1] |= 0x04
	var full_filtered_i: Variant = codec.call("decode_mei_i_frame", full_filtered_mei, second_i_index)
	if not full_filtered_i is Dictionary or not full_filtered_i.get("ok", false):
		_fail("SDK full-frame 4-2-1 operation-table decode failed")
		return
	if _changed_byte_count(second_pixels, full_filtered_i.get("rgba", PackedByteArray())) == 0:
		_fail("SDK full-frame 0x04 operation-table flag did not filter the I-frame")
		return
	var forced_filtered_i: Variant = codec.call("decode_mei_i_frame", original, second_i_index, 0x0800)
	if not forced_filtered_i is Dictionary or not forced_filtered_i.get("ok", false):
		_fail("SDK UseLoopFilter mode failed on an I-frame")
		return
	if _changed_byte_count(second_pixels, forced_filtered_i.get("rgba", PackedByteArray())) == 0:
		_fail("SDK UseLoopFilter did not force full-frame 4-2-1 filtering")
		return
	if _changed_byte_count(second_pixels, forced_filtered_i.get("reference_rgba", PackedByteArray())) != 0:
		_fail("full-frame filtering changed the raw I-frame prediction reference")
		return
	var no_filter_mei := original.duplicate()
	no_filter_mei[second_image_header + 1] |= 0x0c
	var suppressed_i: Variant = codec.call("decode_mei_i_frame", no_filter_mei, second_i_index, 0x0400)
	if not suppressed_i is Dictionary or not suppressed_i.get("ok", false):
		_fail("SDK NoLoopFilter mode failed on an I-frame")
		return
	if _changed_byte_count(second_pixels, suppressed_i.get("rgba", PackedByteArray())) != 0:
		_fail("SDK NoLoopFilter did not suppress both operation-table filters")
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
	if not codec.has_method("decode_mei_p_frame"):
		_fail("YzkCodec must expose reference-based MEI P-frame decoding")
		return
	var first_p: Variant = codec.call("decode_mei_p_frame", original, 3, first_frame)
	if not first_p is Dictionary or not first_p.get("ok", false):
		_fail("first P-frame decode failed: %s" % (first_p.get("error", "invalid result") if first_p is Dictionary else "invalid result"))
		return
	var p_pixels: PackedByteArray = first_p.get("rgba", PackedByteArray())
	if p_pixels.size() != 800 * 600 * 4:
		_fail("first P-frame RGBA output has wrong size: %d" % p_pixels.size())
		return
	for pixel_index: int in range(3, p_pixels.size(), 4):
		if p_pixels[pixel_index] != 255:
			_fail("first P-frame alpha is not opaque at byte %d" % pixel_index)
			return
	var second_p: Variant = codec.call("decode_mei_p_frame", original, 6, p_pixels)
	if not second_p is Dictionary or not second_p.get("ok", false):
		_fail("second P-frame decode failed: %s" % (second_p.get("error", "invalid result") if second_p is Dictionary else "invalid result"))
		return
	var second_p_pixels: PackedByteArray = second_p.get("rgba", PackedByteArray())
	if second_p_pixels.size() != 800 * 600 * 4:
		_fail("second P-frame RGBA output has wrong size: %d" % second_p_pixels.size())
		return
	if not codec.has_method("decode_mei_b_frame"):
		_fail("YzkCodec must expose reference-based MEI B-frame decoding")
		return
	var first_b: Variant = codec.call("decode_mei_b_frame", original, 1, first_frame, p_pixels)
	if not first_b is Dictionary or not first_b.get("ok", false):
		_fail("first B-frame decode failed: %s" % (first_b.get("error", "invalid result") if first_b is Dictionary else "invalid result"))
		return
	var b_pixels: PackedByteArray = first_b.get("rgba", PackedByteArray())
	if b_pixels.size() != 800 * 600 * 4:
		_fail("first B-frame RGBA output has wrong size: %d" % b_pixels.size())
		return
	for pixel_index: int in range(3, b_pixels.size(), 4):
		if b_pixels[pixel_index] != 255:
			_fail("first B-frame alpha is not opaque at byte %d" % pixel_index)
			return
	var second_b: Variant = codec.call("decode_mei_b_frame", original, 2, first_frame, p_pixels)
	if not second_b is Dictionary or not second_b.get("ok", false):
		_fail("second B-frame decode failed: %s" % (second_b.get("error", "invalid result") if second_b is Dictionary else "invalid result"))
		return
	var second_b_pixels: PackedByteArray = second_b.get("rgba", PackedByteArray())
	if second_b_pixels.size() != 800 * 600 * 4:
		_fail("second B-frame RGBA output has wrong size: %d" % second_b_pixels.size())
		return
	var third_b: Variant = codec.call("decode_mei_b_frame", original, 4, p_pixels, second_p_pixels)
	if not third_b is Dictionary or not third_b.get("ok", false):
		_fail("B-frame after the next P anchor failed: %s" % (third_b.get("error", "invalid result") if third_b is Dictionary else "invalid result"))
		return
	var fourth_b: Variant = codec.call("decode_mei_b_frame", original, 5, p_pixels, second_p_pixels)
	if not fourth_b is Dictionary or not fourth_b.get("ok", false):
		_fail("second B-frame after the next P anchor failed: %s" % (fourth_b.get("error", "invalid result") if fourth_b is Dictionary else "invalid result"))
		return
	var following_p_index := -1
	var following_b_index := -1
	for index: int in range(second_i_index + 1, frames.size()):
		var picture_type := str(frames[index].get("picture_type", ""))
		if picture_type == "B" and following_b_index < 0:
			following_b_index = index
		elif picture_type == "P":
			following_p_index = index
			break
	if following_p_index < 0 or following_b_index < 0:
		_fail("second GOP has no B/P frames to verify UseLoopFilter propagation")
		return
	var filtered_second_i: Variant = codec.call("decode_mei_i_frame", original, second_i_index, 0x0800)
	if not filtered_second_i is Dictionary or not filtered_second_i.get("ok", false):
		_fail("SDK UseLoopFilter mode failed on the second I-frame")
		return
	var baseline_following_p: Variant = codec.call("decode_mei_p_frame", original, following_p_index, second_pixels)
	var forced_following_p: Variant = codec.call("decode_mei_p_frame", original, following_p_index,
		filtered_second_i.get("reference_rgba", second_pixels), 0x0800)
	if (not baseline_following_p is Dictionary or not baseline_following_p.get("ok", false)
		or not forced_following_p is Dictionary or not forced_following_p.get("ok", false)):
		_fail("SDK UseLoopFilter mode failed on a P-frame")
		return
	if _changed_byte_count(baseline_following_p.get("rgba", PackedByteArray()),
		forced_following_p.get("rgba", PackedByteArray())) == 0:
		_fail("SDK UseLoopFilter did not force full-frame filtering on a P-frame")
		return
	if _changed_byte_count(baseline_following_p.get("rgba", PackedByteArray()),
		forced_following_p.get("reference_rgba", PackedByteArray())) != 0:
		_fail("full-frame filtering changed the raw P-frame prediction reference")
		return
	var baseline_following_b: Variant = codec.call("decode_mei_b_frame", original, following_b_index,
		second_pixels, baseline_following_p.get("rgba", PackedByteArray()))
	var forced_following_b: Variant = codec.call("decode_mei_b_frame", original, following_b_index,
		filtered_second_i.get("reference_rgba", second_pixels),
		forced_following_p.get("reference_rgba", PackedByteArray()), 0x0800)
	if (not baseline_following_b is Dictionary or not baseline_following_b.get("ok", false)
		or not forced_following_b is Dictionary or not forced_following_b.get("ok", false)):
		_fail("SDK UseLoopFilter mode failed on a B-frame")
		return
	if _changed_byte_count(baseline_following_b.get("rgba", PackedByteArray()),
		forced_following_b.get("rgba", PackedByteArray())) == 0:
		_fail("SDK UseLoopFilter did not force full-frame filtering on a B-frame")
		return
	if _changed_byte_count(baseline_following_b.get("rgba", PackedByteArray()),
		forced_following_b.get("reference_rgba", PackedByteArray())) != 0:
		_fail("full-frame filtering changed the raw B-frame prediction reference")
		return
	var b_as_p: Variant = codec.call("decode_mei_p_frame", original, 1, first_frame)
	if not b_as_p is Dictionary or b_as_p.get("ok", true):
		_fail("P-frame decoder must reject a bidirectional B-frame")
		return
	if FileAccess.get_file_as_bytes(movie_path) != original:
		_fail("decode_mei modified the original movie")
		return
	print("PASS MEI audio, I/P/B decode, SDK loop-filter modes, and reference-buffer preservation")
	quit(0)


func _fail(message: String) -> void:
	printerr("FAIL %s" % message)
	quit(1)


func _find_record_header(data: PackedByteArray, record_name: String, ordinal: int) -> int:
	var signature := record_name.to_ascii_buffer()
	var found := 0
	for offset: int in range(data.size() - signature.size()):
		var matches := true
		for index: int in signature.size():
			if data[offset + index] != signature[index]:
				matches = false
				break
		if not matches:
			continue
		if found == ordinal:
			return offset + signature.size() + 8
		found += 1
	return -1


func _changed_byte_count(left: PackedByteArray, right: PackedByteArray) -> int:
	if left.size() != right.size():
		return maxi(left.size(), right.size())
	var changed := 0
	for index: int in left.size():
		if left[index] != right[index]:
			changed += 1
	return changed
