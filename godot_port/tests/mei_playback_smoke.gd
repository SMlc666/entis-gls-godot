extends SceneTree

const GAME_DIR := "/mnt/sdb1/devs/yzk2godot/缘之空（全cg步兵版）"


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
	if not player.call("_start_native_mei_movie", GAME_DIR.path_join("opening.mei")):
		_fail("native MEI player refused opening.mei")
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
	for _frame: int in range(8):
		await process_frame
	print("MEI first GOP decode and display: %d ms" % ((Time.get_ticks_usec() - playback_start_usec) / 1000))
	if player.get("mei_movie_anchor_index") <= 0:
		_fail("native MEI playback did not advance to a reference frame")
		return
	if player.get("mei_video_rect").texture == first_texture:
		_fail("native MEI playback did not present a subsequent reordered frame")
		return
	player.call("_on_movie_stop_requested")
	if player.get("mei_movie_active") or player.get("mei_video_rect").visible:
		_fail("native MEI stop did not clear playback state")
		return
	print("PASS native MEI playback displays frames, advances references, and stops")
	player.queue_free()
	await process_frame
	quit(0)


func _fail(message: String) -> void:
	printerr("FAIL %s" % message)
	quit(1)
