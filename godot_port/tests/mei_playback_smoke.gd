extends SceneTree

const GAME_DIR := "/mnt/sdb1/devs/yzk2godot/缘之空（全cg步兵版）"
const CsxHostClass = preload("res://scripts/csx_host.gd")
const CsxVMClass = preload("res://scripts/csx_vm.gd")
const TestSupport = preload("res://tests/test_support.gd")

var test_save_dir := ""
var test_player: Node = null

class FailingGopCodec extends RefCounted:
	var decoded_b_frames := 0
	var pixels := PackedByteArray([0, 0, 0, 255])

	func decode_mei_p_frame(_input: PackedByteArray, _index: int, _previous: PackedByteArray, _flags: int = 0) -> Dictionary:
		return {"ok": true, "rgba": pixels, "reference_rgba": pixels, "width": 1, "height": 1}

	func decode_mei_b_frame(_input: PackedByteArray, _index: int, _previous: PackedByteArray, _next: PackedByteArray, _flags: int = 0) -> Dictionary:
		decoded_b_frames += 1
		if decoded_b_frames == 2:
			return {"ok": false, "error": "injected B-frame failure"}
		return {"ok": true, "rgba": pixels, "width": 1, "height": 1}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://scenes/adv_player.tscn") as PackedScene
	if scene == null:
		_fail("ADV scene failed to load")
		return
	var player := scene.instantiate()
	test_player = player
	test_save_dir = TestSupport.new_save_dir("mei_playback")
	player.set("save_dir_override", test_save_dir)
	player.set("game_dir", GAME_DIR)
	player.set("start_in_title", true)
	root.add_child(player)
	await process_frame
	if not TestSupport.uses_isolated_saves(player.get("host"), test_save_dir):
		_fail("AdvPlayer did not use isolated MEI smoke saves")
		return
	var valid_initial_frame := {
		"first_frame_decoded": true,
		"video_frame_info": [{"picture_type": "I"}],
		"width": 2,
		"height": 2,
		"first_frame_rgba": PackedByteArray([0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255]),
		"first_frame_reference_rgba": PackedByteArray([0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255])
	}
	if not player.call("_has_valid_mei_initial_frame", valid_initial_frame):
		_fail("MEI initial-frame gate rejected a correctly sized decoded I-frame")
		return
	var incomplete_initial_frame: Dictionary = valid_initial_frame.duplicate(true)
	incomplete_initial_frame["first_frame_decoded"] = false
	if player.call("_has_valid_mei_initial_frame", incomplete_initial_frame):
		_fail("MEI initial-frame gate accepted a frame the decoder marked as incomplete")
		return
	var truncated_initial_frame: Dictionary = valid_initial_frame.duplicate(true)
	truncated_initial_frame["first_frame_rgba"] = PackedByteArray([0, 0, 0, 255])
	if player.call("_has_valid_mei_initial_frame", truncated_initial_frame):
		_fail("MEI initial-frame gate accepted an RGBA buffer with a mismatched byte length")
		return
	player.set("mei_movie_audio_clock_enabled", false) # Manual delta checks below use a deterministic test clock.
	player.set("mei_movie_frame_duration", 0.05)
	player.set("mei_movie_frames", [{}, {}, {}, {}, {}, {}, {}, {}, {}, {}])
	if int(player.call("_update_mei_audio_clock_frame", 0.16)) != 3 or int(player.call("_update_mei_audio_clock_frame", 0.08)) != 3:
		_fail("MEI audio clock mapping must follow the media position and reject backward audio jitter")
		return
	var playback_start_usec := Time.get_ticks_usec()
	var movie_resource := CsxHostClass.HostSprite.new(9802, player.get("host"))
	if movie_resource.open_movie("opening.mei") != 1:
		_fail("MovieSprite failed to open the original opening.mei")
		return
	var second_movie_resource := CsxHostClass.HostSprite.new(9802, player.get("host"))
	if second_movie_resource.sprite_id != movie_resource.sprite_id or second_movie_resource.get_instance_id() == movie_resource.get_instance_id():
		_fail("MovieSprite resource ownership must use object identity, not its reusable drawing sprite id")
		return
	var opened_codec: Object = player.get("mei_movie_codec")
	var second_open_result := second_movie_resource.open_movie("opening.mei")
	var second_play_result := second_movie_resource.play_movie(0)
	var second_seek_result := second_movie_resource.seek_frame(0)
	if second_open_result != 0 or second_play_result != 0 or second_seek_result != 0:
		_fail("A second MovieSprite incorrectly acquired or operated the first sprite's shared native decoder (open=%d play=%d seek=%d owner=%d second=%d)" % [second_open_result, second_play_result, second_seek_result, int(player.get("host").movie_owner_instance_id), second_movie_resource.get_instance_id()])
		return
	if movie_resource.get_total_frame() != 2521 or player.get("mei_movie_codec") != opened_codec:
		_fail("Rejecting a second MovieSprite disturbed the current owner's decoder")
		return
	var original_filename := movie_resource.filename
	movie_resource.filename = "missing_movie_resource.mei"
	if movie_resource.play_movie(0) != 0:
		_fail("MovieSprite reported success when no native or fallback movie could start")
		return
	movie_resource.filename = original_filename
	if movie_resource.get_total_frame() != 2521 or movie_resource.get_total_time() != 126000:
		_fail("MovieSprite did not expose metadata immediately after OpenMovie")
		return
	if player.get("mei_movie_active") or player.get("mei_video_rect").visible:
		_fail("OpenMovie started presentation without PlayMovie")
		return
	if movie_resource.play_movie(0) != 1:
		_fail("MovieSprite failed to play the opened MEI resource")
		return
	print("MEI startup including audio decode: %d ms" % ((Time.get_ticks_usec() - playback_start_usec) / 1000))
	if not player.get("mei_movie_active") or not player.get("mei_video_rect").visible or not player.get("mei_video_backdrop").visible:
		_fail("native MEI player did not enter visible playback state")
		return
	var first_texture: Texture2D = player.get("mei_video_rect").texture
	var first_image: Image = player.get("mei_movie_image")
	if first_texture == null or first_texture.get_width() != 800 or first_texture.get_height() != 600:
		_fail("native MEI player did not show the 800x600 source frame")
		return
	if player.get("mei_video_rect").stretch_mode != TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
		_fail("native MEI player does not preserve the source aspect ratio")
		return
	if movie_resource.seek_frame(4) != 1 or movie_resource.get_current_frame() != 4 or player.get("mei_movie_displayed_index") != 4:
		_fail("MovieSprite seek did not decode and present the requested B-frame")
		return
	if movie_resource.seek_frame(0) != 1 or movie_resource.get_current_frame() != 0:
		_fail("MovieSprite could not seek back to the initial I-frame")
		return
	if movie_resource.seek_frame(2521) != 0:
		_fail("MovieSprite accepted a frame beyond its declared frame count")
		return
	if int(player.call("_prepare_next_mei_group")) != 1 or int(player.call("_prepare_next_mei_group")) != 1:
		_fail("native MEI player could not prepare the first two reference groups")
		return
	var expected_group_indices := [1, 2, 3, 4, 5, 6]
	var prepared: Array = player.get("mei_movie_queue")
	if prepared.size() < expected_group_indices.size():
		_fail("native MEI player prepared too few reordered frames")
		return
	for index: int in expected_group_indices.size():
		if int(prepared[index].get("index", -1)) != expected_group_indices[index]:
			_fail("native MEI playback reordered frame %d incorrectly" % index)
			return
	player.call("_process_mei_movie", float(player.get("mei_movie_frame_duration")) * 3.1)
	if player.get("mei_movie_displayed_index") != 3:
		_fail("native MEI player did not skip overdue frames to catch up with its media clock")
		return
	for _frame: int in range(8):
		await process_frame
	print("MEI first two GOPs and 8 display ticks: %d ms" % ((Time.get_ticks_usec() - playback_start_usec) / 1000))
	if player.get("mei_movie_anchor_index") <= 0:
		_fail("native MEI playback did not advance to a reference frame")
		return
	if player.get("mei_movie_displayed_index") <= 0:
		_fail("native MEI playback did not present a subsequent reordered frame")
		return
	if player.get("mei_video_rect").texture != first_texture or player.get("mei_movie_image") != first_image:
		_fail("native MEI playback recreated its image or texture instead of updating the frame surface")
		return
	player.call("_on_movie_stop_requested")
	if player.get("mei_movie_active") or player.get("mei_video_rect").visible:
		_fail("native MEI stop did not clear playback state")
		return
	if movie_resource.play_movie(0x0400) != 1 or int(player.get("mei_movie_decode_flags")) != 0x0400:
		_fail("MovieSprite did not forward SDK NoLoopFilter into native MEI decoding")
		return
	player.call("_on_movie_stop_requested")
	if movie_resource.seek_frame(0) != 1 or movie_resource.get_current_frame() != 0:
		_fail("MovieSprite could not reset its open stream before testing a new decode mode")
		return
	if not player.call("_start_native_mei_movie", GAME_DIR.path_join("opening.mei"), 0x0807):
		_fail("native MEI player refused SDK UseLoopFilter and no-skip playback mode")
		return
	if int(player.get("mei_movie_decode_flags")) != 0x0800:
		_fail("SDK UseLoopFilter was not retained by native MEI playback")
		return
	player.call("_process_mei_movie", float(player.get("mei_movie_frame_duration")) * 3.1)
	if player.get("mei_movie_displayed_index") != 1 or (player.get("mei_movie_queue") as Array).size() != 2:
		_fail("SDK NoSkipFrame mode dropped overdue frames instead of displaying one at a time")
		return
	player.call("_process_mei_movie", 0.001)
	if player.get("mei_movie_displayed_index") != 2:
		_fail("SDK NoSkipFrame mode did not continue through the overdue frame backlog")
		return
	player.call("_on_movie_stop_requested")
	if player.get("mei_movie_codec") == null or movie_resource.get_total_frame() != 2521 or movie_resource.get_total_time() != 126000:
		_fail("MovieSprite stop released its open decoder or metadata")
		return
	if movie_resource.seek_frame(4) != 1 or movie_resource.get_current_frame() != 4 or player.get("mei_movie_active"):
		_fail("MovieSprite could not seek while stopped with the MEI resource still open")
		return
	var expected_resume_seconds := float(floori(4.0 * 126000.0 / 2521.0)) / 1000.0
	if not is_equal_approx(float(player.call("_mei_frame_position_seconds", 4)), expected_resume_seconds):
		_fail("MEI audio seek time does not match Entis FrameIndexToTime scaling")
		return
	if (
		movie_resource.play_movie(0) != 1
		or not player.get("mei_movie_active")
		or player.get("mei_movie_displayed_index") != 4
		or movie_resource.get_current_frame() != 4
	):
		_fail("PlayMovie after StopMovie must resume the stopped movie position")
		return
	player.call("_on_movie_stop_requested")
	if not player.call("_start_native_mei_movie", GAME_DIR.path_join("opening.mei"), 0x02):
		_fail("native MEI player refused looping playback mode")
		return
	var loop_queue: Array = player.get("mei_movie_queue")
	loop_queue.clear()
	player.set("mei_movie_anchor_index", player.get("mei_movie_frames").size() - 1)
	player.set("mei_movie_displayed_index", player.get("mei_movie_frames").size() - 1)
	player.call("_process_mei_movie", float(player.get("mei_movie_frame_duration")) + 0.01)
	if not player.get("mei_movie_active") or player.get("mei_movie_anchor_index") != 0 or player.get("mei_movie_displayed_index") != 0:
		_fail("original PlayMovie loop flag did not restart at the first MEI frame (active=%s anchor=%s display=%s queue=%d)" % [str(player.get("mei_movie_active")), str(player.get("mei_movie_anchor_index")), str(player.get("mei_movie_displayed_index")), (player.get("mei_movie_queue") as Array).size()])
		return
	player.call("_on_movie_stop_requested")
	var movie_vm := CsxVMClass.new(player.get("host"))
	var movie_frames: Array = player.get("mei_movie_frames")
	var loop_anchor := -1
	for frame_index in range(10, movie_frames.size()):
		if str(movie_frames[frame_index].get("picture_type", "")) == "I":
			loop_anchor = frame_index
			break
	if loop_anchor < 0:
		_fail("opening.mei has no I-frame available for a loop seek test")
		return
	var first_next_group_frame := -1
	for frame_index in range(loop_anchor + 1, movie_frames.size()):
		var picture_type := str(movie_frames[frame_index].get("picture_type", ""))
		if picture_type == "B":
			if first_next_group_frame < 0:
				first_next_group_frame = frame_index
		elif picture_type in ["I", "P"]:
			if first_next_group_frame < 0:
				first_next_group_frame = frame_index
			break
	if first_next_group_frame <= loop_anchor:
		_fail("opening.mei could not provide a valid first frame for the next GOP")
		return
	if movie_resource.play_movie(0x02) != 1:
		_fail("MovieSprite failed to start a one-shot movie before setting an active rewind interval")
		return
	var terminal_frame_dispatch: Variant = movie_vm._dispatch_sprite_method(movie_resource, "SetRewindingPortion", [0, 2521, 1])
	if terminal_frame_dispatch != 0 or int(player.get("mei_movie_loop_end_frame")) != 2520:
		_fail("MovieSprite did not map the SDK-declared terminal frame 2521 to opening.mei's stored-record EOF boundary 2520")
		return
	var unavailable_start_dispatch: Variant = movie_vm._dispatch_sprite_method(movie_resource, "SetRewindingPortion", [2520, 2521, 1])
	if unavailable_start_dispatch == 0:
		_fail("MovieSprite accepted frame 2520 as a loop start even though opening.mei has no stored record at that index")
		return
	var disable_loop_dispatch: Variant = movie_vm._dispatch_sprite_method(movie_resource, "SetRewindingPortion", [0, 2521, 0])
	if disable_loop_dispatch != 0 or player.get("mei_movie_loop"):
		_fail("active MovieSprite.SetRewindingPortion(repeat=false) did not override the PlayMovie loop flag")
		return
	var loop_dispatch: Variant = movie_vm._dispatch_sprite_method(movie_resource, "SetRewindingPortion", [loop_anchor, first_next_group_frame, -1])
	if loop_dispatch != 0 or int(player.get("mei_movie_loop_start_frame")) != loop_anchor or int(player.get("mei_movie_loop_end_frame")) != first_next_group_frame or not player.get("mei_movie_loop"):
		_fail("MovieSprite.SetRewindingPortion did not configure the active exclusive loop interval through the VM")
		return
	if movie_resource.seek_frame(loop_anchor) != 1:
		_fail("MovieSprite could not seek to the loop start before the boundary tick")
		return
	player.call("_process_mei_movie", float(player.get("mei_movie_frame_duration")) * 3.1)
	if not player.get("mei_movie_active") or int(player.get("mei_movie_displayed_index")) != loop_anchor or int(player.get("host").movie_current_frame) != loop_anchor:
		_fail("opening.mei displayed the exclusive end at the first queued frame of a new GOP instead of seeking back")
		return
	if not is_zero_approx(float(player.get("mei_movie_elapsed"))):
		_fail("MEI loop seek consumed overdue ticks from the previous playback segment")
		return
	var expected_loop_audio_position := float(player.call("_mei_frame_position_seconds", loop_anchor))
	var actual_loop_audio_position := float(player.get("mei_audio_player").get_playback_position())
	if absf(actual_loop_audio_position - expected_loop_audio_position) > 0.2:
		_fail("MovieSprite loop seek did not synchronize MEI audio to the loop start frame")
		return
	player.call("_on_movie_stop_requested")
	if movie_vm._dispatch_sprite_method(movie_resource, "SetRewindingPortion", [loop_anchor, first_next_group_frame, 0]) != 0:
		_fail("MovieSprite rejected a valid non-repeating playback end interval")
		return
	if movie_resource.play_movie(0) != 1 or movie_resource.seek_frame(loop_anchor) != 1:
		_fail("MovieSprite could not start and seek the non-repeating interval")
		return
	player.call("_process_mei_movie", float(player.get("mei_movie_frame_duration")) + 0.01)
	if player.get("mei_movie_active") or player.get("host").is_movie_playing:
		_fail("MovieSprite repeat=false did not stop at its exclusive end frame")
		return
	movie_resource.close_movie()
	if (movie_resource.get_total_frame() != 0 or movie_resource.get_current_frame() != -1
		or player.get("mei_movie_codec") != null or player.get("mei_audio_player").stream != null):
		_fail("MovieSprite close did not release decoder state and metadata")
		return
	if second_movie_resource.open_movie("opening.mei") != 1 or second_movie_resource.play_movie(0) != 1:
		_fail("Closing the owner did not release the shared decoder to a different MovieSprite")
		return
	if player.get("host").active_movie_instance_id != second_movie_resource.get_instance_id() or movie_resource.is_movie_playing() != 0 or second_movie_resource.is_movie_playing() != 1:
		_fail("MovieSprite playback status leaked across resource identities")
		return
	second_movie_resource.close_movie()
	player.get("host").movie_total_frames = 1
	if movie_resource.seek_frame(0) != 0:
		_fail("MovieSprite reported a successful seek after its decoder had been closed")
		return
	player.get("host").movie_total_frames = 0
	if movie_vm._dispatch_sprite_method(movie_resource, "SetRewindingPortion", [0, 2521, 1]) != 0:
		_fail("MovieSprite could not store a valid rewind portion while closed for the next open")
		return
	if movie_resource.open_movie("opening.mei") != 1 or movie_resource.play_movie(0) != 1:
		_fail("MovieSprite did not retain a rewind portion configured after close when reopened")
		return
	if int(player.get("mei_movie_loop_start_frame")) != 0 or int(player.get("mei_movie_loop_end_frame")) != 2520 or not player.get("mei_movie_loop"):
		_fail("MovieSprite did not apply its pre-play rewind portion after reopening")
		return
	player.call("_on_movie_stop_requested")
	movie_resource.close_movie()
	var released_movie := CsxHostClass.HostSprite.new(9804, player.get("host"))
	if released_movie.open_movie("opening.mei") != 1 or released_movie.release() != 0:
		_fail("MovieSprite.Release must succeed without substituting for CloseMovie")
		return
	if player.get("host").movie_owner_instance_id != released_movie.get_instance_id() or player.get("mei_movie_codec") == null:
		_fail("MovieSprite.Release incorrectly performed CloseMovie instead of retaining the open stream")
		return
	released_movie.close_movie()
	if player.get("host").movie_owner_instance_id != -1 or player.get("mei_movie_codec") != null:
		_fail("MovieSprite.CloseMovie did not release the open stream after Release")
		return
	var abandoned_movie: Variant = CsxHostClass.HostSprite.new(9805, player.get("host"))
	if abandoned_movie.open_movie("opening.mei") != 1:
		_fail("A MovieSprite with no explicit CloseMovie could not open the original stream")
		return
	var abandoned_movie_id: int = abandoned_movie.get_instance_id()
	abandoned_movie = null
	await process_frame
	if (player.get("host").movie_owner_instance_id != -1 or player.get("mei_movie_codec") != null
		or player.get("host").movie_owner_ref != null or player.get("mei_audio_player").stream != null):
		_fail("Dropping the last MovieSprite reference did not close its decoder and release PCM")
		return
	if abandoned_movie_id == player.get("host").movie_owner_instance_id:
		_fail("Destroyed MovieSprite identity remained registered as the host movie owner")
		return
	var failing_codec := FailingGopCodec.new()
	player.set("mei_movie_codec", failing_codec)
	player.set("mei_movie_bytes", PackedByteArray([0]))
	var synthetic_frames: Array[Dictionary] = [
		{"picture_type": "I"},
		{"picture_type": "B"},
		{"picture_type": "B"},
		{"picture_type": "P"},
	]
	var movie_frames_for_test: Array = player.get("mei_movie_frames")
	movie_frames_for_test.assign(synthetic_frames)
	player.set("mei_movie_width", 1)
	player.set("mei_movie_height", 1)
	player.set("mei_movie_anchor_index", 0)
	player.set("mei_movie_anchor_rgba", failing_codec.pixels)
	(player.get("mei_movie_queue") as Array).clear()
	var failed_group_status := int(player.call("_prepare_next_mei_group"))
	if failed_group_status != -1 or not (player.get("mei_movie_queue") as Array).is_empty() or int(player.get("mei_movie_anchor_index")) != 0:
		_fail("A partially decoded MEI GOP must report failure without committing queue or reference state")
		return
	failing_codec.decoded_b_frames = 0
	movie_frames_for_test.assign([{"picture_type": "I"}])
	var eof_status := int(player.call("_prepare_next_mei_group"))
	if eof_status != 0:
		_fail("A clean MEI end of stream must remain distinct from a frame decode failure")
		return
	movie_frames_for_test.assign(synthetic_frames)
	player.set("mei_movie_elapsed", 0.0)
	player.set("mei_movie_frame_duration", 0.05)
	player.set("mei_movie_active", true)
	player.set("mei_movie_loop", true)
	player.get("host").is_movie_playing = true
	player.call("_process_mei_movie", 0.05)
	if player.get("mei_movie_active") or player.get("host").is_movie_playing:
		_fail("A corrupt MEI GOP must stop playback instead of restarting a damaged loop")
		return
	print("PASS MEI distinguishes EOF from decode failure and commits GOPs atomically")
	print("PASS native MEI playback displays/reorders frames, seeks exclusive rewind portions with synchronized audio, honors loop/no-skip modes, and preserves lifecycle")
	player.queue_free()
	await process_frame
	TestSupport.remove_test_saves(test_save_dir)
	test_player = null
	test_save_dir = ""
	quit(0)


func _fail(message: String) -> void:
	printerr("FAIL %s" % message)
	if test_player != null and is_instance_valid(test_player):
		test_player.free()
	test_player = null
	if not test_save_dir.is_empty():
		TestSupport.remove_test_saves(test_save_dir)
	test_save_dir = ""
	quit(1)
