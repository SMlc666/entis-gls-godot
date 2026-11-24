extends SceneTree

const GAME_DIR := "/mnt/sdb1/devs/yzk2godot/缘之空（全cg步兵版）"
const CsxHostClass = preload("res://scripts/csx_host.gd")
const CsxVMClass = preload("res://scripts/csx_vm.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://scenes/adv_player.tscn") as PackedScene
	if scene == null:
		_fail("ADV scene failed to load")
		return
	var player := scene.instantiate()
	player.set("game_dir", GAME_DIR)
	player.set("start_in_title", true)
	root.add_child(player)
	await process_frame
	var playback_start_usec := Time.get_ticks_usec()
	var movie_resource := CsxHostClass.HostSprite.new(9802, player.get("host"))
	if movie_resource.open_movie("opening.mei") != 1:
		_fail("MovieSprite failed to open the original opening.mei")
		return
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
	if not player.call("_prepare_next_mei_group") or not player.call("_prepare_next_mei_group"):
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
	if player.get("mei_video_rect").texture != first_texture:
		_fail("native MEI playback recreated its texture instead of updating the frame surface")
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
	if movie_resource.play_movie(0) != 1:
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
	var loop_dispatch: Variant = movie_vm._dispatch_sprite_method(movie_resource, "SetRewindingPortion", [loop_anchor, first_next_group_frame, -1])
	if loop_dispatch != 0 or int(player.get("mei_movie_loop_start_frame")) != loop_anchor or int(player.get("mei_movie_loop_end_frame")) != first_next_group_frame or not player.get("mei_movie_loop"):
		_fail("MovieSprite.SetRewindingPortion did not configure the active exclusive loop interval through the VM")
		return
	if movie_resource.seek_frame(loop_anchor) != 1:
		_fail("MovieSprite could not seek to the loop start before the boundary tick")
		return
	player.call("_process_mei_movie", float(player.get("mei_movie_frame_duration")) + 0.01)
	if not player.get("mei_movie_active") or int(player.get("mei_movie_displayed_index")) != loop_anchor or int(player.get("host").movie_current_frame) != loop_anchor:
		_fail("opening.mei displayed the exclusive end at the first queued frame of a new GOP instead of seeking back")
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
	if movie_resource.get_total_frame() != 0 or movie_resource.get_current_frame() != -1 or player.get("mei_movie_codec") != null:
		_fail("MovieSprite close did not release decoder state and metadata")
		return
	print("PASS native MEI playback displays/reorders frames, seeks exclusive rewind portions with synchronized audio, honors loop/no-skip modes, and preserves lifecycle")
	player.queue_free()
	await process_frame
	quit(0)


func _fail(message: String) -> void:
	printerr("FAIL %s" % message)
	quit(1)
