extends SceneTree

const CsxHostClass = preload("res://scripts/csx_host.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var host = CsxHostClass.new()
	var sprite = CsxHostClass.HostSprite.new(1, host)
	var first_image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	var second_image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	var first_ref: WeakRef = weakref(first_image)
	var second_ref: WeakRef = weakref(second_image)
	sprite.animation_frames.append(first_image)
	sprite.animation_frames.append(second_image)
	sprite.animation_frame_sizes.append(Vector2i(2, 2))
	sprite.animation_frame_sizes.append(Vector2i(2, 2))
	sprite.animation_sequence.append(0)
	sprite.animation_sequence.append(1)
	sprite.animation_total_time_ms = 100
	if sprite.begin_animation(-1) != 0:
		_fail("HostSprite.begin_animation failed for synthetic frames")
		return
	if not host.active_animated_sprites.has(sprite.get_instance_id()):
		_fail("Looping animation was not registered with its host")
		return
	first_image = null
	second_image = null

	if sprite.release() != 0:
		_fail("HostSprite.Release changed its status code")
		return
	if not _is_released(sprite, host):
		_fail("HostSprite.Release retained image, animation, timing, or registry state")
		return
	if first_ref.get_ref() != null or second_ref.get_ref() != null:
		_fail("HostSprite.Release retained a strong reference to a former animation Image")
		return

	host.advance_sprite_animations(0.05)
	if not _is_released(sprite, host):
		_fail("Host animation advance restored sprite resources or registry state after Release")
		return
	if sprite.release() != 0 or not _is_released(sprite, host):
		_fail("HostSprite.Release is not idempotent")
		return

	print("PASS HostSprite.Release clears animation resources, stops scheduling, and is idempotent")
	quit(0)


func _is_released(sprite: Variant, host: Variant) -> bool:
	return sprite.image == null \
		and sprite.texture == null \
		and sprite.alpha_resource == null \
		and sprite.alpha_image == null \
		and sprite.alpha_texture == null \
		and sprite.attached_resource == null \
		and sprite.animation_frames.is_empty() \
		and sprite.animation_frame_sizes.is_empty() \
		and sprite.animation_sequence.is_empty() \
		and sprite.animation_total_time_ms == 0 \
		and sprite.animation_loop_count == 0 \
		and sprite.animation_elapsed_ms == 0.0 \
		and sprite.animation_duration_ms == 0.0 \
		and sprite.animation_begin_sequence == 0 \
		and sprite.animation_start_sequence == 0 \
		and sprite.animation_turn_sequence == -1 \
		and sprite.animation_rewind_sequence == 0 \
		and sprite.animation_view_frame == -1 \
		and not host.active_animated_sprites.has(sprite.get_instance_id())


func _fail(message: String) -> void:
	printerr("FAIL ", message)
	quit(1)
