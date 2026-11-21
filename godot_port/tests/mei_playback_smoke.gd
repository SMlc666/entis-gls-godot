extends SceneTree

const GAME_DIR := "/mnt/sdb1/devs/yzk2godot/缘之空（全cg步兵版）"
const CsxHostClass = preload("res://scripts/csx_host.gd")


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
	if not player.call("_start_native_mei_movie", GAME_DIR.path_join("opening.mei"), 0x02):
		_fail("native MEI player refused looping playback mode")
		return
	player.set("mei_movie_anchor_index", player.get("mei_movie_frames").size() - 1)
	player.call("_process_mei_movie", float(player.get("mei_movie_frame_duration")) + 0.01)
	if not player.get("mei_movie_active") or player.get("mei_movie_anchor_index") != 0 or player.get("mei_movie_displayed_index") != 0:
		_fail("original PlayMovie loop flag did not restart at the first MEI frame (active=%s anchor=%s display=%s queue=%d)" % [str(player.get("mei_movie_active")), str(player.get("mei_movie_anchor_index")), str(player.get("mei_movie_displayed_index")), (player.get("mei_movie_queue") as Array).size()])
		return
	player.call("_on_movie_stop_requested")
	movie_resource.close_movie()
	if movie_resource.get_total_frame() != 0 or movie_resource.get_current_frame() != -1 or player.get("mei_movie_codec") != null:
		_fail("MovieSprite close did not release decoder state and metadata")
		return
	print("PASS native MEI playback displays/reorders frames, honors loop/no-skip modes, seek, and lifecycle")
	player.queue_free()
	await process_frame
	quit(0)


func _fail(message: String) -> void:
	printerr("FAIL %s" % message)
	quit(1)
