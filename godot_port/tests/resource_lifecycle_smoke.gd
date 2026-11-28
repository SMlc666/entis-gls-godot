extends SceneTree

const CsxHostClass = preload("res://scripts/csx_host.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var resource := CsxHostClass.HostResource.new()
	var base_image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	var frame_image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	var frame_ref: WeakRef = weakref(frame_image)
	resource.image = base_image
	resource.texture = ImageTexture.new()
	resource.image_frames.append(frame_image)
	resource.image_frame_sequence.append(0)
	resource.image_total_time_ms = 120
	base_image = null
	frame_image = null

	if resource.release() != 0:
		_fail("HostResource.Release changed its status code")
		return
	if resource.image != null or resource.texture != null or resource.audio_stream != null:
		_fail("HostResource.Release retained a primary image, texture, or audio reference")
		return
	if not resource.image_frames.is_empty() or not resource.image_frame_sequence.is_empty():
		_fail("HostResource.Release retained decoded frame or animation-sequence references")
		return
	if resource.image_total_time_ms != 0:
		_fail("HostResource.Release retained image animation timing")
		return
	if frame_ref.get_ref() != null:
		_fail("A decoded frame remained strongly referenced after HostResource.Release")
		return
	if resource.release() != 0 or not resource.image_frames.is_empty():
		_fail("HostResource.Release is not idempotent")
		return

	print("PASS HostResource.Release clears decoded image/texture/frame references and is idempotent")
	quit(0)


func _fail(message: String) -> void:
	printerr("FAIL ", message)
	quit(1)
