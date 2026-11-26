extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	if not ClassDB.class_exists("YzkCodec"):
		_fail("native GDExtension must register YzkCodec")
		return
	var args := OS.get_cmdline_user_args()
	var game_dir := args[0] if not args.is_empty() else ""
	if game_dir.is_empty():
		_fail("pass the game directory containing opening.mei")
		return
	var movie_path := game_dir.path_join("opening.mei")
	var movie := FileAccess.get_file_as_bytes(movie_path)
	if movie.is_empty():
		_fail("could not read %s" % movie_path)
		return
	var codec: Object = ClassDB.instantiate("YzkCodec")
	if codec == null or not codec.has_method("get_mei_index_stats"):
		_fail("YzkCodec must expose MEI index reuse statistics")
		return

	var open_started := Time.get_ticks_usec()
	var opened: Dictionary = codec.call("decode_mei", movie)
	var open_elapsed_us := Time.get_ticks_usec() - open_started
	_check(opened.get("ok", false), "opening.mei must open: %s" % opened.get("error", "unknown"), failures)
	if not opened.get("ok", false):
		_failures_out(failures)
		return
	var frames: Array = opened.get("video_frame_info", [])
	_check(frames.size() == opened.get("frame_record_count", -1), "opened frame metadata must match the frame index", failures)
	var initial_stats: Dictionary = codec.call("get_mei_index_stats")
	_check(initial_stats.get("valid", false) and initial_stats.get("build_count", 0) == 1,
		"opening.mei must build its frame index exactly once", failures)

	var first_i := _find_frame(frames, 0, "I")
	_check(first_i >= 0, "opening.mei must contain an I-frame", failures)
	if first_i < 0:
		_failures_out(failures)
		return
	var frame_elapsed_us := 0
	var first_i_started := Time.get_ticks_usec()
	var first_result: Dictionary = codec.call("decode_mei_i_frame", movie, first_i)
	frame_elapsed_us += Time.get_ticks_usec() - first_i_started
	_check(first_result.get("ok", false), "random access to the first I-frame must succeed", failures)
	if not first_result.get("ok", false):
		_failures_out(failures)
		return
	_check(first_result.get("rgba", PackedByteArray()) == opened.get("first_frame_rgba", PackedByteArray()),
		"indexed random access must match the first frame decoded during open", failures)
	var previous_reference: PackedByteArray = first_result.get("reference_rgba", PackedByteArray())

	# Decode one real P anchor and a B frame that references it, mirroring the
	# playback path that delays B output until its forward reference is decoded.
	var later_i := _find_frame(frames, first_i + 1, "I")
	var first_p := _find_frame(frames, first_i + 1, "P", later_i if later_i >= 0 else -1)
	if first_p >= 0:
		var p_started := Time.get_ticks_usec()
		var p_result: Dictionary = codec.call("decode_mei_p_frame", movie, first_p, previous_reference)
		frame_elapsed_us += Time.get_ticks_usec() - p_started
		_check(p_result.get("ok", false), "P-frame after the initial I anchor must decode", failures)
		if p_result.get("ok", false):
			var b_index := _find_frame(frames, first_i + 1, "B", first_p)
			if b_index >= 0:
				var b_started := Time.get_ticks_usec()
				var b_result: Dictionary = codec.call("decode_mei_b_frame", movie, b_index,
					previous_reference, p_result.get("reference_rgba", PackedByteArray()))
				frame_elapsed_us += Time.get_ticks_usec() - b_started
				_check(b_result.get("ok", false), "B-frame between real anchors must decode", failures)

	# A later I-frame and a return seek exercise the same indexed random-access
	# calls used by playback without changing the existing public API.
	if later_i >= 0:
		var seek_started := Time.get_ticks_usec()
		var later_result: Dictionary = codec.call("decode_mei_i_frame", movie, later_i)
		frame_elapsed_us += Time.get_ticks_usec() - seek_started
		_check(later_result.get("ok", false), "random seek to a later I-frame must decode", failures)
	var return_seek_started := Time.get_ticks_usec()
	var return_seek: Dictionary = codec.call("decode_mei_i_frame", movie, first_i)
	frame_elapsed_us += Time.get_ticks_usec() - return_seek_started
	_check(return_seek.get("ok", false), "seek back to the first I-frame must decode", failures)
	var independent_frames: Array[int] = []
	var search_from := first_i + 1
	while true:
		var next_i := _find_frame(frames, search_from, "I")
		if next_i < 0:
			break
		independent_frames.append(next_i)
		search_from = next_i + 1
	const SEEK_ITERATIONS := 128
	for seek_iteration in SEEK_ITERATIONS:
		var seek_target := first_i if independent_frames.is_empty() else independent_frames[seek_iteration % independent_frames.size()]
		var seek_started := Time.get_ticks_usec()
		var seek_result: Dictionary = codec.call("decode_mei_i_frame", movie, seek_target)
		frame_elapsed_us += Time.get_ticks_usec() - seek_started
		_check(seek_result.get("ok", false), "repeated random seek %d must decode" % seek_target, failures)

	var reused_stats: Dictionary = codec.call("get_mei_index_stats")
	_check(reused_stats.get("build_count", 0) == 1 and reused_stats.get("reuse_count", 0) >= SEEK_ITERATIONS + 3,
		"playback and seek frame calls must reuse the opening index", failures)
	_check(int(reused_stats.get("validation_us", 0)) > 0,
		"MEI index statistics must report validation time", failures)
	print("MEI index benchmark: input_bytes=%d frames=%d seeks=%d open_ms=%.3f validation_ms=%.3f frame_decode_ms=%.3f builds=%d reuses=%d" % [
		movie.size(), frames.size(), SEEK_ITERATIONS, float(open_elapsed_us) / 1000.0,
		float(reused_stats.get("validation_us", 0)) / 1000.0,
		float(frame_elapsed_us) / 1000.0,
		int(reused_stats.get("build_count", 0)), int(reused_stats.get("reuse_count", 0))])

	# A distinct but byte-identical copy is a new immutable snapshot and must
	# rebuild the index before any offsets from it are trusted.
	var detached_copy := PackedByteArray()
	detached_copy.append_array(movie)
	var copied_result: Dictionary = codec.call("decode_mei_i_frame", detached_copy, first_i)
	var copied_stats: Dictionary = codec.call("get_mei_index_stats")
	_check(copied_result.get("ok", false) and copied_stats.get("build_count", 0) == 2,
		"a distinct byte-identical PackedByteArray must build an index for its own snapshot", failures)

	# Mutating that snapshot must detach it (copy-on-write) and force another
	# validation, so the live cached source cannot become stale in place.
	var changed_movie := detached_copy
	changed_movie[0] = 0
	var changed_result: Dictionary = codec.call("decode_mei_i_frame", changed_movie, first_i)
	var changed_stats: Dictionary = codec.call("get_mei_index_stats")
	_check(not changed_result.get("ok", true) and changed_stats.get("build_count", 0) == 3,
		"a modified movie buffer must rebuild and reject its invalid MEI index", failures)

	if failures.is_empty():
		print("PASS real opening.mei playback and seek reuse the validated frame index")
		quit(0)
	else:
		_failures_out(failures)


func _find_frame(frames: Array, begin: int, picture_type: String, end: int = -1) -> int:
	var limit := frames.size() if end < 0 else mini(end, frames.size())
	for index in range(maxi(begin, 0), limit):
		if str(frames[index].get("picture_type", "")) == picture_type:
			return index
	return -1


func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _fail(message: String) -> void:
	printerr("FAIL ", message)
	quit(1)


func _failures_out(failures: Array[String]) -> void:
	for failure in failures:
		printerr("FAIL ", failure)
	quit(1)
