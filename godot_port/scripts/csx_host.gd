extends RefCounted
class_name CsxHost

const AUDIO_PLAY_TYPE_DEVICE := -2147483648
const AUDIO_PLAY_TYPE_NONE := -1
const AUDIO_PLAY_TYPE_MUSIC := 0
const AUDIO_PLAY_TYPE_SOUND := 1
const AUDIO_PLAY_TYPE_VOICE := 2
const AUDIO_PLAY_TYPE_SYSTEM := 3

signal dialogue_updated(entry: Dictionary)
signal message_output(sprite: HostSprite)
signal message_progress(sprite: HostSprite)
signal bg_updated(bg_name: String, texture: Texture2D)
signal bgm_updated(bgm_name: String)
signal movie_requested(movie_file: String, play_mode: int)
signal movie_open_requested(movie_file: String)
signal movie_stop_requested
signal movie_close_requested
signal movie_seek_requested(frame_index: int)
signal choices_updated(choices: Array)
signal tone_filter_updated(filter_type: String)

const NoaArchiveReader = preload("res://scripts/noa_archive.gd")
const EriDecoder = preload("res://scripts/eri_decoder.gd")
const MioDecoder = preload("res://scripts/mio_decoder.gd")
const Cp932Decoder = preload("res://scripts/cp932_decoder.gd")

var game_dir: String = ""
var archives: Dictionary = {} # canonical archive path -> NoaArchiveReader
var vfs_index: Dictionary = {} # normalized entry path -> ordered candidate Array[Dictionary]
var vfs_conflicts: Array[Dictionary] = []
var vfs_warned_conflicts: Dictionary = {}
var image_cache: Dictionary = {} # archive + entry identity -> { "image": Image, "texture": ImageTexture }
var sound_cache: Dictionary = {} # archive + entry identity -> AudioStreamWAV
var image_cache_lru: Array[String] = []
var sound_cache_lru: Array[String] = []
var image_cache_bytes := 0
var sound_cache_bytes := 0
var image_cache_budget_bytes := 256 * 1024 * 1024
var sound_cache_budget_bytes := 64 * 1024 * 1024

var audio_players: Dictionary = {}
var audio_right_players: Dictionary = {}
var audio_total_volumes: Dictionary = {0: 1.0, 1: 1.0, 2: 1.0, 3: 1.0}
var bgm_player: AudioStreamPlayer = null
var env_se_player: AudioStreamPlayer = null
var se_player: AudioStreamPlayer = null
var voice_player: AudioStreamPlayer = null
var system_player: AudioStreamPlayer = null
var voice_char_mutes: Dictionary = {
	"ID_SORA": false,
	"ID_AKIRA": false,
	"ID_NAO": false,
	"ID_KAZUHA": false,
	"ID_MOTOKA": false,
	"ID_KOZUE": false,
	"ID_YAHIRO": false,
	"ID_RYOUHEI": false,
	"ID_OTHER": false
}

var last_error := ""
var unsupported_capabilities_reported: Dictionary = {}
var log_messages: Array[String] = []
var text_history: Array[Dictionary] = [] # { "speaker": ..., "text": ..., "voice": ..., "bg": ... }
var current_speaker: String = ""
var current_dialogue: String = ""
var current_voice: String = ""
var current_bg: String = ""
var current_bg_texture: Texture2D = null
var current_bgm: String = ""
var current_env_se: String = ""

var auto_advance: bool = false
var advance_requested: bool = false
var advance_ticks: int = 0
var skip_input_pending: bool = false
var advance_query_count: int = 0
var is_waiting_input: bool = false
var yield_for_sprite_activation: bool = false
var is_movie_playing: bool = false
var movie_current_frame: int = -1
var movie_total_frames: int = 0
var movie_total_time_ms: int = 0
var movie_opened: bool = false
var current_choices: Array[String] = []
var is_waiting_choice: bool = false
var selected_choice: int = -1
var current_tone_filter: String = "NORMAL"
var command_queue: Array = []
var virtual_time_ms: int = 1000
var cursor_position_provider: Callable = Callable()
var active_input_filter_ref: WeakRef = null
var active_sprites: Dictionary[int, WeakRef] = {}
var active_messages: Dictionary[int, WeakRef] = {}
var active_effect_sprites: Dictionary[int, WeakRef] = {}
var active_animated_sprites: Dictionary[int, WeakRef] = {}
# EntisGLS initializes AnimationFlag to animeFull (Normal | Action | Effect).
var sprite_animation_flags: int = 7
var active_volume_envelopes: Dictionary[int, WeakRef] = {}
var save_dir: String = "user://saves"
const SAVE_SCHEMA_VERSION := 2
const MAX_SAVE_DOCUMENT_BYTES := 16 * 1024 * 1024
const MAX_SERIALIZATION_DEPTH := 256


class HostResource extends RefCounted:
	var name: String = ""
	var archive_name: String = ""
	var entry_index: int = -1
	var unpacked_size: int = 0
	var payload_offset: int = 0
	var host: CsxHost = null
	var is_playing: bool = false
	var is_repeating: bool = false
	var use_channel_default_loop: bool = false
	var current_position: int = 0 # PCM frames
	var playback_end_frame: int = -1
	var playback_rewind_frame: int = -1
	var rewinding_portion_configured: bool = false
	var configured_rewind_frame: int = -1
	var configured_end_frame: int = -1
	var configured_repeat: bool = false
	var volume_envelope: Array[Vector2] = []
	var volume_envelope_duration_ms: float = 0.0
	var volume_envelope_elapsed_ms: float = 0.0
	var volume_left: float = 1.0
	var volume_right: float = 1.0
	var audio_stream: AudioStreamWAV = null
	var audio_channel: String = ""
	var play_type: int = AUDIO_PLAY_TYPE_NONE
	var image: Image = null
	var texture: ImageTexture = null
	var image_frames: Array[Image] = []
	var image_frame_sequence: Array[int] = []
	var image_total_time_ms: int = 0
	var fields: Dictionary = {}

	func _init(p_name: String = "", p_archive: String = "", p_index: int = -1, p_size: int = 0, p_offset: int = 0, p_host: CsxHost = null) -> void:
		name = p_name
		archive_name = p_archive
		entry_index = p_index
		unpacked_size = p_size
		payload_offset = p_offset
		host = p_host

	func load_sound(filename: String, _threshold: int = -1) -> int:
		name = filename
		audio_stream = null
		audio_channel = ""
		if host == null:
			return 0
		var res := host.load_sound(filename, archive_name)
		if res.get("ok", false):
			audio_stream = res["stream"]
			var source_archive := str(res.get("archive", archive_name))
			audio_channel = host.resolve_audio_channel(filename, source_archive)
			if audio_channel.is_empty():
				host.last_error = "音频来源无法归类到播放声道: %s (%s)" % [filename, source_archive]
			return 1
		host.last_error = str(res.get("error", "无法加载音频资源: %s" % filename))
		push_warning(host.last_error)
		return 0

	func attach_sound(source: Variant) -> int:
		if not source is HostResource or source.audio_stream == null:
			return 0
		var sound := source as HostResource
		cancel_volume_envelope()
		name = sound.name
		audio_stream = sound.audio_stream
		audio_channel = sound.audio_channel
		release_image_data()
		return 1

	func release_image_data() -> void:
		image = null
		texture = null
		image_frames.clear()
		image_frame_sequence.clear()
		image_total_time_ms = 0

	func load_image(filename: String) -> int:
		name = filename
		if host != null:
			var res := host.load_image(filename, archive_name)
			if res.get("ok", false):
				image = (res["image"] as Image).duplicate()
				texture = ImageTexture.create_from_image(image)
				image_frames.clear()
				for frame in res.get("frames", [image]):
					image_frames.append((frame as Image).duplicate())
				image_frame_sequence = res.get("frame_sequence", [])
				image_total_time_ms = int(res.get("total_time_ms", 0))
				return 1
		return 0

	func get_pixel(x: int, y: int) -> int:
		if image == null or x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
			return 0
		return _color_to_native_pixel(image.get_pixel(x, y))

	func get_pixel_rect(pixels: Variant, x: int, y: int, width: int, height: int) -> int:
		if image == null or not pixels is Array or width < 0 or height < 0 or width > 65536 or height > 65536 or (height > 0 and width > 65536 / height):
			return 0
		var target: Array = pixels
		for row in range(height):
			for column in range(width):
				var pixel_index := row * width + column
				while target.size() <= pixel_index:
					target.append(null)
				var px := x + column
				var py := y + row
				target[pixel_index] = get_pixel(px, py)
		return 1

	func set_pixel_rect(pixels: Variant, x: int, y: int, width: int, height: int) -> int:
		if image == null or not pixels is Array or width < 0 or height < 0 or width > 65536 or height > 65536 or (height > 0 and width > 65536 / height):
			return 0
		var source: Array = pixels
		if source.size() < width * height:
			return 0
		for row in range(height):
			for column in range(width):
				var pixel_value: Variant = source[row * width + column]
				if not (pixel_value is int or pixel_value is float):
					continue
				var px := x + column
				var py := y + row
				if px >= 0 and py >= 0 and px < image.get_width() and py < image.get_height():
					image.set_pixel(px, py, _native_pixel_to_color(int(pixel_value)))
		if texture != null:
			texture.update(image)
		return 1

	func _color_to_native_pixel(color: Color) -> int:
		return (int(round(color.a * 255.0)) << 24) | (int(round(color.r * 255.0)) << 16) | (int(round(color.g * 255.0)) << 8) | int(round(color.b * 255.0))

	func _native_pixel_to_color(pixel: int) -> Color:
		return Color(float((pixel >> 16) & 0xff) / 255.0, float((pixel >> 8) & 0xff) / 255.0, float(pixel & 0xff) / 255.0, float((pixel >> 24) & 0xff) / 255.0)

	func play(intro: int = -1, flag: int = 0) -> int:
		if host == null or not host.is_valid_audio_play_type(flag):
			if host != null:
				host.report_unsupported("HostResource.Play %s (flag=%d)" % [name, flag])
			return -1
		# The original script uses -1/-2 as start-position sentinels; both start at frame zero.
		var end_frame := configured_end_frame if rewinding_portion_configured else -1
		var rewind_frame := configured_rewind_frame if rewinding_portion_configured else -1
		var repeat := configured_repeat if rewinding_portion_configured else false
		return _play_at(maxi(0, intro), repeat, not rewinding_portion_configured, end_frame, rewind_frame, flag)

	func play_from(start_pos: int = 0, end_pos: int = -1, repeat: bool = false, rewind_pos: int = -1, flag: int = 0) -> int:
		if host == null or not host.is_valid_audio_play_type(flag):
			if host != null:
				host.report_unsupported("HostResource.PlayFrom %s (flag=%d)" % [name, flag])
			return -1
		return _play_at(start_pos, repeat, false, end_pos, rewind_pos, flag)

	func set_rewinding_portion(rewind_pos: int = -1, end_pos: int = -1, repeat: bool = false) -> int:
		if audio_stream == null and host != null and load_sound(name) != 1:
			return 0
		if audio_stream == null:
			return 0
		var frame_bytes := (2 if audio_stream.stereo else 1) * (2 if audio_stream.format == AudioStreamWAV.FORMAT_16_BITS else 1)
		if audio_stream.format not in [AudioStreamWAV.FORMAT_8_BITS, AudioStreamWAV.FORMAT_16_BITS] or frame_bytes <= 0:
			return 0
		@warning_ignore("integer_division")
		var frame_count := audio_stream.data.size() / frame_bytes
		var resolved_end := frame_count if end_pos < 0 else end_pos
		var resolved_rewind := current_position if rewind_pos < 0 and is_playing else (0 if rewind_pos < 0 else rewind_pos)
		if resolved_rewind < 0 or resolved_rewind >= resolved_end or resolved_end > frame_count:
			return 0
		rewinding_portion_configured = true
		configured_rewind_frame = resolved_rewind
		configured_end_frame = resolved_end
		configured_repeat = repeat
		return 1

	func _play_at(start_frame: int, repeat: bool, channel_default_loop: bool = false, end_frame: int = -1, rewind_frame: int = -1, next_play_type: int = AUDIO_PLAY_TYPE_MUSIC) -> int:
		if host == null:
			return 0
		if audio_stream == null and load_sound(name) != 1:
			return 0
		play_type = next_play_type
		if not host.play_audio_stream(audio_stream, name, audio_channel, start_frame, repeat, channel_default_loop, end_frame, rewind_frame, play_type, volume_left, volume_right):
			return 0
		is_playing = true
		current_position = start_frame
		is_repeating = repeat
		use_channel_default_loop = channel_default_loop
		playback_end_frame = end_frame
		# Preserve the original default rewind point when restarting from a paused frame.
		playback_rewind_frame = start_frame if rewind_frame == -1 else rewind_frame
		return 1

	func stop() -> int:
		var stopped := host.stop_audio(name, audio_channel) if host != null else false
		cancel_volume_envelope()
		is_playing = false
		current_position = 0
		play_type = AUDIO_PLAY_TYPE_NONE
		return 1 if stopped else 0

	func pause() -> int:
		if host == null:
			return 0
		var position := host.get_audio_position_frames(name, audio_channel)
		var paused := host.pause_audio(name, audio_channel)
		if paused:
			current_position = position
			is_playing = false
		return 1 if paused else 0

	func restart() -> int:
		if host == null:
			return 0
		var resumed := host.resume_audio(name, audio_channel)
		if not resumed:
			return _play_at(current_position, is_repeating, use_channel_default_loop, playback_end_frame, playback_rewind_frame, play_type)
		is_playing = true
		return 1

	func release() -> int:
		cancel_volume_envelope()
		is_playing = false
		is_repeating = false
		use_channel_default_loop = false
		play_type = AUDIO_PLAY_TYPE_NONE
		current_position = 0
		playback_end_frame = -1
		playback_rewind_frame = -1
		rewinding_portion_configured = false
		configured_rewind_frame = -1
		configured_end_frame = -1
		configured_repeat = false
		audio_stream = null
		image = null
		texture = null
		return 0

	func set_volume(left: float, right: float) -> int:
		var normalized_left := clampf(left, 0.0, 1.0)
		var normalized_right := clampf(right, 0.0, 1.0)
		if host == null:
			return 0
		cancel_volume_envelope()
		volume_left = normalized_left
		volume_right = normalized_right
		if play_type != AUDIO_PLAY_TYPE_NONE and not host.set_resource_audio_volume(audio_channel, volume_left, volume_right, play_type, name):
			return 0
		return 1

	func set_volume_envelope(bezier: Variant, duration: int) -> int:
		if host == null or not (bezier is Object and bezier.has_method("get_field")):
			return 0
		var source: Variant = bezier.get_field("parent")
		if not source is Array or source.size() != 4:
			return 0
		var points: Array[Vector2] = []
		for point in source:
			if not (point is Object and point.has_method("get_field")):
				return 0
			var x: Variant = point.get_field("x")
			var y: Variant = point.get_field("y")
			if not (x is int or x is float) or not (y is int or y is float):
				return 0
			var p := Vector2(float(x), float(y))
			if not is_finite(p.x) or not is_finite(p.y):
				return 0
			points.append(p)
		var has_asymmetric_points := false
		for point: Vector2 in points:
			if not is_equal_approx(point.x, point.y):
				has_asymmetric_points = true
				break
		if has_asymmetric_points and is_playing and not host.ensure_dual_channel_playback(audio_channel):
			host._audio_error("无法为音量包络准备左右独立声道: %s" % name)
			return -1
		volume_envelope = points
		volume_envelope_duration_ms = maxf(0.0, float(duration))
		volume_envelope_elapsed_ms = 0.0
		if volume_envelope_duration_ms <= 0.0:
			advance_volume_envelope(0.0, true)
		else:
			host.active_volume_envelopes[get_instance_id()] = weakref(self)
			_apply_volume_envelope(0.0)
		return 1

	func cancel_volume_envelope() -> int:
		if host != null:
			host.active_volume_envelopes.erase(get_instance_id())
		volume_envelope.clear()
		volume_envelope_duration_ms = 0.0
		volume_envelope_elapsed_ms = 0.0
		return 0

	func is_volume_envelope_pending() -> int:
		return -1 if not volume_envelope.is_empty() and volume_envelope_duration_ms > 0.0 else 0

	func get_volume(left_out: Variant = null, right_out: Variant = null) -> int:
		if left_out is Object and left_out.has_method("set_value"):
			left_out.set_value(volume_left)
		if right_out is Object and right_out.has_method("set_value"):
			right_out.set_value(volume_right)
		return 1

	func advance_volume_envelope(delta_ms: float, force_end: bool = false) -> void:
		if volume_envelope.is_empty():
			return
		volume_envelope_elapsed_ms = volume_envelope_duration_ms if force_end else volume_envelope_elapsed_ms + maxf(0.0, delta_ms)
		var t := 1.0 if volume_envelope_duration_ms <= 0.0 else clampf(volume_envelope_elapsed_ms / volume_envelope_duration_ms, 0.0, 1.0)
		_apply_volume_envelope(t)
		if t >= 1.0:
			volume_left = clampf(volume_envelope[3].x, 0.0, 1.0)
			volume_right = clampf(volume_envelope[3].y, 0.0, 1.0)
			volume_envelope.clear()
			volume_envelope_duration_ms = 0.0
			volume_envelope_elapsed_ms = 0.0
			if host != null:
				host.active_volume_envelopes.erase(get_instance_id())

	func _apply_volume_envelope(t: float) -> void:
		if host == null or volume_envelope.size() != 4:
			return
		var inverse := 1.0 - t
		var value := volume_envelope[0] * inverse * inverse * inverse \
			+ volume_envelope[1] * 3.0 * inverse * inverse * t \
			+ volume_envelope[2] * 3.0 * inverse * t * t \
			+ volume_envelope[3] * t * t * t
		var left := clampf(value.x, 0.0, 1.0)
		var right := clampf(value.y, 0.0, 1.0)
		if host.set_resource_audio_volume(audio_channel, left, right, play_type, name):
			volume_left = left
			volume_right = right

	func get_playing_position() -> int:
		if host != null:
			var position := host.get_audio_position_frames(name, audio_channel)
			if position >= 0:
				return position
		return current_position

	func set_total_volume(flag: int, vol: float) -> int:
		return 1 if host != null and host.set_audio_total_volume(flag, vol) else 0

	func get_total_volume(flag: int) -> float:
		return host.get_audio_total_volume(flag) if host != null else 1.0


class HostInputFilter extends RefCounted:
	var host: CsxHost
	var filter_file: String = ""
	var is_open: bool = false
	var window_ref: Variant = null
	var input_queue: Array = []
	var joy_buttons: Dictionary = {}
	var input_assignments: Dictionary = {}
	var fields: Dictionary = {}

	func _init(p_host: CsxHost) -> void:
		host = p_host
		if host != null:
			host.active_input_filter_ref = weakref(self)

	func load_input_filter(filename: String) -> int:
		filter_file = filename
		input_assignments.clear()
		if host == null:
			return 0
		var input_bytes := PackedByteArray()
		var path := host.game_dir.path_join("system").path_join(filename)
		if FileAccess.file_exists(path):
			input_bytes = FileAccess.get_file_as_bytes(path)
		else:
			var entry := host.read_vfs_entry("system/".path_join(filename))
			if not entry.get("ok", false):
				entry = host.read_vfs_entry(filename)
			if entry.get("ok", false):
				input_bytes = entry.get("data", PackedByteArray())
		if input_bytes.is_empty():
			return 0
		var parser := XMLParser.new()
		if parser.open_buffer(input_bytes) != OK:
			return 0
		var current: Dictionary = {}
		while parser.read() == OK:
			if parser.get_node_type() != XMLParser.NODE_ELEMENT:
				continue
			match parser.get_node_name():
				"key_assign":
					current = {}
				"input":
					current["input_device"] = parser.get_named_attribute_value("device")
					current["input_key"] = parser.get_named_attribute_value("key")
				"output":
					var output_device := parser.get_named_attribute_value("device")
					var output_key := parser.get_named_attribute_value("key")
					if output_device == "joystick" and output_key.begins_with("button:"):
						var button_id := output_key.trim_prefix("button:").to_int()
						var assignment := _decode_input_assignment(str(current.get("input_device", "")), str(current.get("input_key", "")))
						if not assignment.is_empty():
							var key_name := "button:%d" % button_id
							var mappings: Array = input_assignments.get(key_name, [])
							mappings.append(assignment)
							input_assignments[key_name] = mappings
		return 0

	func _decode_input_assignment(device: String, key_name: String) -> Dictionary:
		if device == "keyboard":
			var key_code := 0
			match key_name:
				"up": key_code = KEY_UP
				"down": key_code = KEY_DOWN
				"left": key_code = KEY_LEFT
				"right": key_code = KEY_RIGHT
				_:
					if key_name.begins_with("ascii:"):
						var chars := key_name.trim_prefix("ascii:").to_upper()
						if not chars.is_empty():
							key_code = chars.unicode_at(0)
					elif key_name.begins_with("code:"):
						var code_text := key_name.trim_prefix("code:").trim_suffix("H")
						var virtual_key := code_text.hex_to_int()
						match virtual_key:
							0x09: key_code = KEY_TAB
							0x0D: key_code = KEY_ENTER
							0x10: key_code = KEY_SHIFT
							0x11: key_code = KEY_CTRL
							0x1B: key_code = KEY_ESCAPE
							_:
								if virtual_key >= 0x70 and virtual_key <= 0x7B:
									key_code = KEY_F1 + (virtual_key - 0x70)
			if key_code > 0:
				return {"device": "keyboard", "key": key_code}
		elif device == "mouse" and key_name.begins_with("code:"):
			var button_code := key_name.trim_prefix("code:").to_int()
			if button_code > 0:
				return {"device": "mouse", "key": button_code}
		return {}

	func _is_assignment_pressed(assignment: Dictionary) -> bool:
		match str(assignment.get("device", "")):
			"keyboard":
				return Input.is_key_pressed(int(assignment.get("key", 0)))
			"mouse":
				return Input.is_mouse_button_pressed(int(assignment.get("key", 0)))
		return false

	func _is_button_pressed(key: int) -> bool:
		if not is_open:
			return false
		var mappings: Array = input_assignments.get("button:%d" % key, [])
		for assignment: Dictionary in mappings:
			if _is_assignment_pressed(assignment):
				return true
		return false

	func delete_input_filter() -> int:
		filter_file = ""
		input_assignments.clear()
		return 0

	func open_filter(_mode: int = 0, win: Variant = null) -> int:
		is_open = true
		window_ref = win
		return 0

	func close_filter() -> int:
		is_open = false
		return 0

	func get_input_event(_event_ref: Variant, _timeout: int = 0) -> int:
		return 0

	func flush_input_queue(_limit: int = 0) -> int:
		input_queue.clear()
		return 0

	func get_captured_joy_stick() -> int:
		return 0

	func get_stick_position(_vec_ref: Variant, _dev: int = 0) -> int:
		return 0

	func is_joy_button_pushing(key: int, _dev: int = 0) -> int:
		return -1 if _is_button_pressed(key) else 0

	func get_joy_button_pushed(key: int, _dev: int = 0, during_activation: bool = false) -> int:
		if host != null:
			var host_result := host.poll_advance_button(key, during_activation)
			if host_result != 0:
				joy_buttons[key] = _is_button_pressed(key)
				return host_result
		var pressed := _is_button_pressed(key)
		var was_pressed := bool(joy_buttons.get(key, false))
		joy_buttons[key] = pressed
		return -1 if pressed and not was_pressed else 0

	func flush_joy_button_pushed(_dev: int = 0, _key: int = -1) -> int:
		if host != null:
			host.skip_input_pending = false
		for key in input_assignments.keys():
			var button_id := str(key).trim_prefix("button:").to_int()
			joy_buttons[button_id] = _is_button_pressed(button_id)
		return 0

	func reset_joy_button_pushing(_dev: int = 0, _key: int = -1) -> int:
		if _key >= 0:
			joy_buttons.erase(_key)
		else:
			joy_buttons.clear()
		return 0

	func get_cursor_pos() -> Vector2i:
		return host.get_cursor_position() if host != null else Vector2i.ZERO

	func move_cursor_pos(_x: int, _y: int) -> int:
		return 0

	func add_filter(_in_ev: Variant, _out_ev: Variant) -> int:
		return 0

	func remove_filter(_in_ev: Variant) -> int:
		return 0

	func get_filter(in_ev: Variant) -> Variant:
		return in_ev

	func dispatch_event(_ev: Variant, _pushed: bool) -> int:
		return 0


class HostToneFilter extends RefCounted:
	var host: CsxHost
	var filter_type: String = "NORMAL"
	var tone: Color = Color.WHITE
	var red_table: PackedByteArray = PackedByteArray()
	var green_table: PackedByteArray = PackedByteArray()
	var blue_table: PackedByteArray = PackedByteArray()
	var alpha_table: PackedByteArray = PackedByteArray()
	var tone_flags: int = 0
	var tone_texture: ImageTexture = null
	var fields: Dictionary = {}

	func _init(p_host: CsxHost) -> void:
		host = p_host
		red_table = _tone_table(0, 0)
		green_table = _tone_table(0, 0)
		blue_table = _tone_table(0, 0)
		alpha_table = _tone_table(0, 0)

	func create_tone_filter() -> int:
		return 0

	func delete_tone_filter() -> int:
		filter_type = "NORMAL"
		if host != null:
			host.set_tone_filter("NORMAL")
		return 0

	func set_tone(r: float, g: float, b: float) -> int:
		tone = Color(r, g, b)
		tone_texture = null
		return 0

	func set_general_tone(red_tone: int, red_flag: int, green_tone: int, green_flag: int, blue_tone: int, blue_flag: int, alpha_tone: int, alpha_flag: int, flags: int = 0) -> int:
		var tables := [
			_tone_table(red_tone, red_flag),
			_tone_table(green_tone, green_flag),
			_tone_table(blue_tone, blue_flag),
			_tone_table(alpha_tone, alpha_flag),
		]
		if tables.any(func(table: PackedByteArray) -> bool: return table.is_empty()):
			return -1
		red_table = tables[0]
		green_table = tables[1]
		blue_table = tables[2]
		alpha_table = tables[3]
		tone_flags = flags & 0x0F
		if (tone_flags & 0x01) != 0:
			red_table[0] = 0
			green_table[0] = 0
			blue_table[0] = 0
			alpha_table[0] = 0
		tone_texture = null
		return 0

	func morphing_filter(filter1: HostToneFilter, filter2: HostToneFilter, degree: int) -> int:
		if filter1 == null or filter2 == null:
			return -1
		var amount := clampi(degree, 0, 256)
		var source_weight := _tone_table(-amount, 0)
		var target_weight := _tone_table(amount - 256, 0)
		if source_weight.is_empty() or target_weight.is_empty():
			return -1
		for channel in ["red_table", "green_table", "blue_table", "alpha_table"]:
			var source: PackedByteArray = filter1.get(channel)
			var target: PackedByteArray = filter2.get(channel)
			var mixed := PackedByteArray()
			mixed.resize(256)
			for i in 256:
				# Entis stores the sum in a byte, preserving its 8-bit wrap semantics.
				mixed[i] = (source_weight[source[i]] + target_weight[target[i]]) & 0xFF
			set(channel, mixed)
		tone_flags = filter1.tone_flags
		tone_texture = null
		return 0

	func load_filter_file(filename: String) -> int:
		if host == null or filename.is_empty():
			return 1
		var data := PackedByteArray()
		var local_path := host.game_dir.path_join("system").path_join(filename)
		if FileAccess.file_exists(local_path):
			data = FileAccess.get_file_as_bytes(local_path)
		else:
			var entry := host.read_vfs_entry("system/".path_join(filename))
			if not entry.get("ok", false):
				entry = host.read_vfs_entry(filename)
			if entry.get("ok", false):
				data = entry.get("data", PackedByteArray())
		if data.size() < 80 or data.slice(0, 8) != PackedByteArray([69, 110, 116, 105, 115, 26, 0, 0]):
			return 1
		var tables := {"red": PackedByteArray(), "green": PackedByteArray(), "blue": PackedByteArray(), "alpha": PackedByteArray()}
		var flags := 0
		var offset := 80
		while offset + 16 <= data.size():
			var record_id := data.slice(offset, offset + 8).get_string_from_ascii().strip_edges()
			var length := data.decode_u64(offset + 8)
			offset += 16
			if length > data.size() - offset:
				return 1
			var record := data.slice(offset, offset + int(length))
			if tables.has(record_id):
				if record.size() < 256:
					return 1
				tables[record_id] = record.slice(0, 256)
			elif record_id == "info":
				if record.size() >= 4:
					flags = record.decode_u32(0)
			offset += int(length)
		for channel in ["red", "green", "blue", "alpha"]:
			if tables[channel].size() != 256:
				return 1
		red_table = tables["red"]
		green_table = tables["green"]
		blue_table = tables["blue"]
		alpha_table = tables["alpha"]
		tone_flags = flags
		tone_texture = null
		return 0

	func _tone_table(amount: int, mode: int) -> PackedByteArray:
		var table := PackedByteArray()
		table.resize(256)
		if mode not in [0, 1, 2]:
			return PackedByteArray()
		var tone_value := clampi(amount, -256, 256)
		for value in 256:
			var mapped := value
			match mode:
				0:
					if tone_value > 0:
						mapped = (tone_value - 1) + (value * (256 - tone_value)) / 256
					elif tone_value < 0:
						mapped = (value * (256 + tone_value)) / 256
				1:
					var start := (tone_value >> 1) + 128
					if tone_value >= 0:
						start -= 1
					mapped = ((start << 8) - value * tone_value) >> 8
				2:
					mapped = value + tone_value
			table[value] = clampi(mapped, 0, 255)
		if amount == 0 and mode == 1:
			for value in 256:
				table[value] = 127
		return table

	func get_tone_texture() -> ImageTexture:
		if tone_texture != null:
			return tone_texture
		var pixels := PackedByteArray()
		pixels.resize(256 * 4)
		for value in 256:
			var offset := value * 4
			pixels[offset] = red_table[value]
			pixels[offset + 1] = green_table[value]
			pixels[offset + 2] = blue_table[value]
			pixels[offset + 3] = alpha_table[value]
		var image := Image.create_from_data(256, 1, false, Image.FORMAT_RGBA8, pixels)
		tone_texture = ImageTexture.create_from_image(image)
		return tone_texture

	func get_tone() -> Array:
		return [tone.r, tone.g, tone.b]

	func attach_tone_filter(target: Variant) -> int:
		if target is HostSprite:
			return (target as HostSprite).attach_tone_filter(self)
		return -1

	func set_type(type_name: String) -> void:
		filter_type = type_name.to_upper()
		if host != null:
			host.set_tone_filter(filter_type)

	func get_type() -> String:
		return "ToneFilter"


class HostResourceManager extends RefCounted:
	var host: CsxHost
	var loaded_archive_name: String = ""
	var resource_cache: Dictionary = {} # id_name -> HostResource
	var skin_resources: Dictionary = {} # res_id -> src_filename
	var skin_styles: Dictionary = {}    # style_id -> style_dict
	var skin_pages: Dictionary = {}     # page_id -> page_dict
	var fields: Dictionary = {}

	func _init(p_host: CsxHost) -> void:
		host = p_host

	func load_resource(archive_filename: String) -> int:
		loaded_archive_name = archive_filename
		var noa: NoaArchiveReader = host.get_or_open_archive(archive_filename)
		if noa == null:
			return 0
		resource_cache.clear()
		for i in range(noa.entries.size()):
			var entry: Dictionary = noa.entries[i]
			var entry_name: String = entry["name"]
			var base_id: String = entry_name.get_basename()
			var res := HostResource.new(entry_name, archive_filename, i, entry["unpacked_size"], entry["payload_offset"], host)
			resource_cache[entry_name] = res
			resource_cache[base_id] = res
			resource_cache["ID_" + base_id] = res

		for i in range(noa.entries.size()):
			if String(noa.entries[i]["name"]).nocasecmp_to("system.inf") == 0:
				var inf_res: Dictionary = noa.read_entry(i)
				if inf_res.get("ok", false) and inf_res.has("data"):
					if not _parse_skin_xml(inf_res["data"]):
						return 0
				else:
					host.last_error = "无法读取 %s 中的 system.inf: %s" % [archive_filename, inf_res.get("error", "未知归档错误")]
					return 0
				break
		return 1

	func delete_contents() -> int:
		# Entis ECSResourceManager::DeleteContents clears the manager's
		# ECSGlobal entries, form resources/styles/pages and source filename.
		# CSX runtime globals are a different storage scope and remain intact.
		resource_cache.clear()
		skin_resources.clear()
		skin_styles.clear()
		skin_pages.clear()
		loaded_archive_name = ""
		return 0

	func _parse_skin_xml(raw_bytes: PackedByteArray) -> bool:
		skin_resources.clear()
		skin_styles.clear()
		skin_pages.clear()
		var text_res := _decode_system_inf(raw_bytes)
		if not text_res.get("ok", false):
			host.last_error = str(text_res.get("error", "system.inf 编码无法识别。"))
			return false

		var parser := XMLParser.new()
		if parser.open_buffer(str(text_res.text).to_utf8_buffer()) != OK:
			host.last_error = "system.inf XML 无法打开。"
			return false

		var current_style: Dictionary = {}
		var current_page: Dictionary = {}
		var read_result := parser.read()
		while read_result == OK:
			var ntype := parser.get_node_type()
			if ntype == XMLParser.NODE_ELEMENT:
				var nname := parser.get_node_name()
				var attrs := {}
				for i in range(parser.get_attribute_count()):
					attrs[parser.get_attribute_name(i)] = parser.get_attribute_value(i)

				if nname == "image" and attrs.has("id") and attrs.has("src"):
					skin_resources[attrs["id"]] = attrs["src"]
				elif nname == "image" and not current_page.is_empty() and attrs.has("rsrc"):
					current_page["images"].append({
						"id": attrs.get("id", ""),
						"rsrc": attrs.get("rsrc", ""),
						"x": int(attrs.get("x", "0")),
						"y": int(attrs.get("y", "0")),
					})
				elif nname == "style":
					current_style = {
						"id": attrs.get("id", ""),
						"type": attrs.get("type", "")
					}
					skin_styles[current_style["id"]] = current_style
				elif nname == "arrange":
					if not current_style.is_empty():
						current_style["arrange_type"] = attrs.get("type", "")
						current_style["arrange"] = attrs
				elif nname in ["font", "text", "shadow"] and not current_style.is_empty():
					current_style[nname] = attrs
				elif nname in ["normal", "pushed", "focus", "disabled", "mask", "tracking"]:
					if not current_style.is_empty():
						if attrs.has("image"):
							current_style[nname] = attrs["image"]
						if attrs.has("bar"):
							current_style[nname + "_bar"] = attrs["bar"]
						if attrs.has("column"):
							current_style[nname + "_column"] = attrs["column"]
				elif nname in ["page", "window"]:
					current_page = {
						"id": attrs.get("id", ""),
						"width": int(attrs.get("width", "0")),
						"height": int(attrs.get("height", "0")),
						"bg": attrs.get("bg", ""),
						"buttons": [],
						"scroll_bars": [],
						"images": [],
						"static_texts": []
					}
					skin_pages[current_page["id"]] = current_page
				elif nname == "button" and not current_page.is_empty():
					current_page["buttons"].append({
						"id": attrs.get("id", ""),
						"style": attrs.get("style", ""),
						"x": int(attrs.get("x", "0")),
						"y": int(attrs.get("y", "0")),
						"width": int(attrs.get("width", "0")),
						"height": int(attrs.get("height", "0")),
					})
				elif nname == "scroll_bar" and not current_page.is_empty():
					current_page["scroll_bars"].append({
						"id": attrs.get("id", ""),
						"style": attrs.get("style", ""),
						"x": int(attrs.get("x", "0")),
						"y": int(attrs.get("y", "0")),
						"width": int(attrs.get("width", "0")),
						"height": int(attrs.get("height", "0")),
					})
				elif nname == "static_text" and not current_page.is_empty():
					current_page["static_texts"].append({
						"id": attrs.get("id", ""),
						"style": attrs.get("style", ""),
						"text": attrs.get("text", ""),
						"x": int(attrs.get("x", "0")),
						"y": int(attrs.get("y", "0")),
						"width": int(attrs.get("width", "0")),
						"height": int(attrs.get("height", "0")),
					})
			elif ntype == XMLParser.NODE_ELEMENT_END:
				var nname := parser.get_node_name()
				if nname == "style":
					current_style = {}
				elif nname in ["page", "window"]:
					current_page = {}
			read_result = parser.read()
		if read_result != ERR_FILE_EOF:
			host.last_error = "system.inf XML 解析失败，行 %d。" % parser.get_current_line_number()
			return false
		return true

	func _decode_system_inf(raw_bytes: PackedByteArray) -> Dictionary:
		if raw_bytes.is_empty():
			return {"ok": false, "error": "system.inf 是空文件。"}
		if raw_bytes.size() >= 3 and raw_bytes[0] == 0xEF and raw_bytes[1] == 0xBB and raw_bytes[2] == 0xBF:
			return _decode_utf8_xml(raw_bytes.slice(3))
		if raw_bytes.size() >= 2 and raw_bytes[0] == 0xFF and raw_bytes[1] == 0xFE:
			return _rewrite_xml_encoding(raw_bytes.slice(2).get_string_from_utf16())
		if raw_bytes.size() >= 2 and raw_bytes[0] == 0xFE and raw_bytes[1] == 0xFF:
			var little_endian := raw_bytes.slice(2)
			for i in range(0, little_endian.size() - 1, 2):
				var temp := little_endian[i]
				little_endian[i] = little_endian[i + 1]
				little_endian[i + 1] = temp
			return _rewrite_xml_encoding(little_endian.get_string_from_utf16())

		var header := raw_bytes.slice(0, mini(raw_bytes.size(), 256)).get_string_from_ascii()
		var encoding_match := RegEx.new()
		encoding_match.compile("(?i)encoding\\s*=\\s*['\\\"]([^'\\\"]+)['\\\"]")
		var match_result := encoding_match.search(header)
		var encoding := match_result.get_string(1).to_lower().replace("_", "-") if match_result != null else ""
		if encoding in ["shift-jis", "shiftjis", "windows-31j", "cp932", "sjis"]:
			var decoded: Dictionary = Cp932Decoder.decode_to_utf8(raw_bytes)
			if not decoded.get("ok", false):
				return decoded
			return _rewrite_xml_encoding(str(decoded.text))
		if encoding in ["", "utf-8", "utf8"]:
			return _decode_utf8_xml(raw_bytes)
		return {"ok": false, "error": "不支持 system.inf 声明的字符编码: %s" % encoding}

	func _decode_utf8_xml(raw_bytes: PackedByteArray) -> Dictionary:
		var text := raw_bytes.get_string_from_utf8()
		if text.to_utf8_buffer() != raw_bytes:
			return {"ok": false, "error": "system.inf 含非法 UTF-8，拒绝静默替换字符。"}
		return {"ok": true, "text": text}

	func _rewrite_xml_encoding(text: String) -> Dictionary:
		var declaration := RegEx.new()
		declaration.compile("(?i)(encoding\\s*=\\s*['\\\"])[^'\\\"]+(['\\\"])")
		return {"ok": true, "text": declaration.sub(text, "$1UTF-8$2", true)}

	func _resolve_skin_image(spec: String) -> Dictionary:
		if spec.is_empty():
			return {}
		var res_id := spec
		var crop_rect := Rect2i()
		var has_rect := false
		var rect_pos := spec.find(":RECT(")
		if rect_pos != -1:
			res_id = spec.substr(0, rect_pos)
			var rstr := spec.substr(rect_pos + 6).trim_suffix(")")
			var parts := rstr.split(",")
			if parts.size() >= 4:
				crop_rect = Rect2i(int(parts[0]), int(parts[1]), int(parts[2]), int(parts[3]))
				has_rect = true

		var src_file: String = skin_resources.get(res_id, "")
		if src_file.is_empty():
			src_file = res_id
			if src_file.begins_with("ID_"):
				src_file = src_file.substr(3)
			if not src_file.ends_with(".eri"):
				src_file += ".eri"

		var load_res := host.load_image(src_file, loaded_archive_name)
		if not load_res.get("ok", false) or load_res["image"] == null:
			return {}

		var base_img: Image = load_res["image"]
		var final_img: Image = base_img
		if has_rect and crop_rect.size.x > 0 and crop_rect.size.y > 0:
			var bounded_rect := crop_rect.intersection(Rect2i(Vector2i.ZERO, base_img.get_size()))
			if bounded_rect.size.x > 0 and bounded_rect.size.y > 0:
				final_img = base_img.get_region(bounded_rect)

		var tex := ImageTexture.create_from_image(final_img)
		return {"image": final_img, "texture": tex}

	func create_form_page(parent_sprite: HostSprite, page_id: String) -> int:
		if parent_sprite == null or not skin_pages.has(page_id):
			return 0
		var page: Dictionary = skin_pages[page_id]
		parent_sprite.fields["form_page_id"] = page_id
		var pw: int = page.get("width", 0)
		var ph: int = page.get("height", 0)
		parent_sprite.size = Vector2i(pw, ph)

		parent_sprite.form_resources = self
		var background := _resolve_skin_image(page.get("bg", "")) if not str(page.get("bg", "")).is_empty() else {}
		if not background.is_empty():
			parent_sprite.image = background["image"]
			parent_sprite.texture = background["texture"]
			parent_sprite.size = parent_sprite.image.get_size()
		var buttons: Array = page.get("buttons", [])
		for item: Dictionary in page.get("images", []):
			var item_sprite := HostSprite.new(0, host)
			item_sprite.fields["form_item_id"] = item.get("id", "")
			item_sprite.position = Vector2i(item.get("x", 0), item.get("y", 0))
			item_sprite.is_visible = true
			_set_form_texture(item_sprite, item.get("rsrc", ""))
			parent_sprite.add_sprite(buttons.size(), item_sprite)

		for button_index in range(buttons.size()):
			var btn: Dictionary = buttons[button_index]
			var btn_spr := HostSprite.new(0, host)
			btn_spr.btn_id = btn.get("id", "")
			btn_spr.is_button = true
			btn_spr.position = Vector2i(btn.get("x", 0), btn.get("y", 0))

			var style_id: String = btn.get("style", "")
			var style: Dictionary = skin_styles.get(style_id, {})

			var normal_info := _resolve_skin_image(style.get("normal", ""))
			if not normal_info.is_empty():
				btn_spr.btn_normal_img = normal_info["image"]
				btn_spr.btn_normal_tex = normal_info["texture"]
				btn_spr.image = normal_info["image"]
				btn_spr.texture = normal_info["texture"]
				btn_spr.size = normal_info["image"].get_size()

			var focus_info := _resolve_skin_image(style.get("focus", ""))
			if not focus_info.is_empty():
				btn_spr.btn_focus_img = focus_info["image"]
				btn_spr.btn_focus_tex = focus_info["texture"]

			var pushed_info := _resolve_skin_image(style.get("pushed", ""))
			if not pushed_info.is_empty():
				btn_spr.btn_pushed_img = pushed_info["image"]
				btn_spr.btn_pushed_tex = pushed_info["texture"]

			var disabled_info := _resolve_skin_image(style.get("disabled", ""))
			if not disabled_info.is_empty():
				btn_spr.btn_disabled_img = disabled_info["image"]
				btn_spr.btn_disabled_tex = disabled_info["texture"]

			btn_spr.is_visible = true
			btn_spr.transparency = 0
			parent_sprite.add_sprite(button_index, btn_spr)
		for bar_index in range(page.get("scroll_bars", []).size()):
			var bar: Dictionary = page.scroll_bars[bar_index]
			var bar_sprite := HostSprite.new(0, host)
			bar_sprite.fields["form_item_id"] = bar.get("id", "")
			bar_sprite.fields["control_type"] = "scroll_bar"
			bar_sprite.fields["scroll_axis"] = str(skin_styles.get(str(bar.get("style", "")), {}).get("arrange_type", "horz"))
			bar_sprite.fields["scroll_horz_range"] = 256
			bar_sprite.fields["scroll_horz_pos"] = 0
			bar_sprite.fields["scroll_vert_range"] = 256
			bar_sprite.fields["scroll_vert_pos"] = 0
			bar_sprite.fields["scroll_style_id"] = str(bar.get("style", ""))
			var scroll_style: Dictionary = skin_styles.get(str(bar.get("style", "")), {})
			for state_name in ["normal", "focus", "tracking", "disabled"]:
				var image_info := _resolve_skin_image(str(scroll_style.get("%s_bar" % state_name, "")))
				if not image_info.is_empty():
					bar_sprite.fields["scroll_%s_bar" % state_name] = image_info["texture"]
				var column_info := _resolve_skin_image(str(scroll_style.get("%s_column" % state_name, "")))
				if not column_info.is_empty():
					bar_sprite.fields["scroll_%s_column" % state_name] = column_info["texture"]
			bar_sprite.position = Vector2i(bar.get("x", 0), bar.get("y", 0))
			bar_sprite.size = Vector2i(bar.get("width", 0), bar.get("height", 0))
			bar_sprite.is_visible = true
			bar_sprite.form_resources = self
			parent_sprite.add_sprite(buttons.size() + bar_index, bar_sprite)
		for item: Dictionary in page.get("static_texts", []):
			var text_sprite := HostSprite.new(0, host)
			text_sprite.fields["form_item_id"] = item["id"]
			text_sprite.position = Vector2i(item["x"], item["y"])
			text_sprite.size = Vector2i(item["width"], item["height"])
			text_sprite.is_visible = true
			text_sprite.attach_message_style(self, item["style"])
			text_sprite.text_content = item["text"]
			parent_sprite.add_sprite(buttons.size() + 1, text_sprite)

		parent_sprite.refresh_command_ids()

		return 1

	func _set_form_texture(sprite: HostSprite, resource_id: String) -> bool:
		var info := _resolve_skin_image(resource_id)
		if info.is_empty():
			return false
		sprite.image = info["image"]
		sprite.texture = info["texture"]
		sprite.size = sprite.image.get_size()
		return true


	func get_resource(id_name: String) -> Variant:
		if resource_cache.has(id_name):
			return resource_cache[id_name]
		var trimmed: String = id_name
		if trimmed.begins_with("ID_"):
			trimmed = trimmed.substr(3)
		if resource_cache.has(trimmed):
			return resource_cache[trimmed]
		for k in resource_cache.keys():
			if k.nocasecmp_to(trimmed) == 0 or k.nocasecmp_to(id_name) == 0:
				return resource_cache[k]
		return null


class HostSprite extends RefCounted:
	var sprite_id: int = 0
	var host: CsxHost = null
	var is_visible: bool = false
	var is_enabled: bool = true
	var transparency: int = 0 # 0 = opaque, 256 = transparent
	var blending: int = 0
	var position: Vector2i = Vector2i.ZERO
	var magnification: Vector2 = Vector2.ONE
	var rotation_degrees: float = 0.0
	var sprite_parameters: Dictionary = {"nFlags": 0, "rCrossingAngle": 90.0, "rgbDimColor": 0, "rgbLightColor": 0xffffff, "rZOrder": 0.0, "rgbColorParam1": 0, "rZScale": 0.0}
	var activation_curves: Array = [[], [], []]
	var rev_center: Vector2i = Vector2i.ZERO
	var size: Vector2i = Vector2i.ZERO
	var z_order: int = 0
	var filename: String = ""
	var archive_hint: String = ""
	var attached_resource: HostResource = null
	var image: Image = null
	var texture: ImageTexture = null
	var alpha_resource: HostResource = null
	var alpha_image: Image = null
	var alpha_texture: ImageTexture = null
	var alpha_range: int = 256
	var back_color: int = 0
	var fill_back_color: bool = true
	var animation_frames: Array[Image] = []
	var animation_sequence: Array[int] = []
	var animation_total_time_ms: int = 0
	var animation_loop_count: int = 0
	var animation_elapsed_ms: float = 0.0
	var animation_duration_ms: float = 0.0
	var animation_begin_sequence: int = 0
	var animation_start_sequence: int = 0
	var animation_turn_sequence: int = -1
	var animation_rewind_sequence: int = 0
	var animation_view_frame: int = -1
	var tone_filter: HostToneFilter = null
	var is_activating: bool = false
	var activation_duration_ms: float = 0.0
	var activation_elapsed_ms: float = 0.0
	var activation_start_alpha: int = 0
	var activation_end_alpha: int = 0
	var activation_target_alpha: int = 0
	var children: Array[HostSprite] = []
	var form_resources: HostResourceManager
	var text_content: String = ""
	var message_style: Dictionary = {}
	var message_char_speed_ms: int = 0
	var message_fade_ms: int = 0
	var message_elapsed_ms: float = 0.0
	var message_visible_count: int = -1
	var message_pending: bool = false
	var is_message_sprite: bool = false
	var font_bordering: bool = false
	var message_cursor_position: Vector2i = Vector2i.ZERO
	var btn_id: String = ""
	var full_btn_id: String = ""
	var is_button: bool = false
	var btn_state: String = "normal"
	var btn_normal_tex: Texture2D = null
	var btn_focus_tex: Texture2D = null
	var btn_pushed_tex: Texture2D = null
	var btn_disabled_tex: Texture2D = null
	var btn_normal_img: Image = null
	var btn_focus_img: Image = null
	var btn_pushed_img: Image = null
	var btn_disabled_img: Image = null
	var fields: Dictionary = {}

	func _init(p_id: int = 0, p_host: CsxHost = null) -> void:
		sprite_id = p_id
		host = p_host

	func set_button_state(p_state: String) -> void:
		btn_state = p_state
		match p_state:
			"focus":
				if btn_focus_tex != null:
					texture = btn_focus_tex
					if btn_focus_img != null: image = btn_focus_img
			"pushed":
				if btn_pushed_tex != null:
					texture = btn_pushed_tex
					if btn_pushed_img != null: image = btn_pushed_img
			"disabled":
				if btn_disabled_tex != null:
					texture = btn_disabled_tex
					if btn_disabled_img != null: image = btn_disabled_img
			_:
				if btn_normal_tex != null:
					texture = btn_normal_tex
					if btn_normal_img != null: image = btn_normal_img

	func enable(enabled: bool, item_id: String = "") -> int:
		if item_id.is_empty():
			is_enabled = enabled
			return 0
		var enabled_items: Dictionary = fields.get("item_enabled_status", {})
		enabled_items[item_id] = enabled
		fields["item_enabled_status"] = enabled_items
		var target := find_form_item(item_id)
		if target != null:
			target.is_enabled = enabled
		return 0

	func is_enabled_native(item_id: String = "") -> bool:
		if item_id.is_empty():
			return is_enabled
		var target := find_form_item(item_id)
		if target != null:
			return target.is_enabled
		var enabled_items: Dictionary = fields.get("item_enabled_status", {})
		return bool(enabled_items.get(item_id, false))

	func attach_message_style(res_mgr: Variant, style_id: String) -> int:
		is_message_sprite = true
		if not (res_mgr is HostResourceManager):
			return 0
		var style: Dictionary = res_mgr.skin_styles.get(style_id, {})
		if style.get("type", "") != "static_text":
			return 0
		message_style = style
		return 0

	func set_default_message_speed(char_speed: int, fade_speed: int, ratio: int) -> int:
		message_char_speed_ms = maxi(0, int(char_speed * ratio / 256))
		message_fade_ms = maxi(0, fade_speed)
		return 0

	func clear_message() -> int:
		text_content = ""
		message_pending = false
		message_visible_count = 0
		if host != null:
			host.active_messages.erase(get_instance_id())
			host.message_output.emit(self)
		return 0

	func output_message(text: String) -> int:
		flush_message()
		text_content = text
		message_elapsed_ms = 0.0
		var count := display_text().length()
		message_pending = count > 0 and (message_char_speed_ms > 0 or message_fade_ms > 0)
		message_visible_count = 0 if message_pending else count
		if host != null:
			if message_pending:
				host.active_messages[get_instance_id()] = weakref(self)
			host.message_output.emit(self)
		return 0

	func set_font_bordering(enabled: bool) -> int:
		font_bordering = enabled
		if host != null and not text_content.is_empty():
			host.message_output.emit(self)
		return 0

	func get_message_cursor_pos() -> Vector2i:
		return message_cursor_position

	func move_message_cursor_pos(x: int, y: int) -> int:
		message_cursor_position = Vector2i(x, y)
		return 0

	func advance_message(delta_ms: float) -> void:
		message_elapsed_ms += delta_ms
		var count := display_text().length()
		var interval := message_char_speed_ms
		message_visible_count = count if interval <= 0 else mini(count, maxi(0, ceili(message_elapsed_ms / interval)))
		var duration := maxi(0, count - 1) * interval + message_fade_ms
		if message_elapsed_ms >= duration:
			flush_message()
		elif host != null:
			host.message_progress.emit(self)

	func flush_message() -> int:
		message_pending = false
		message_visible_count = display_text().length()
		if host != null:
			host.active_messages.erase(get_instance_id())
			host.message_progress.emit(self)
		return 0

	func display_text() -> String:
		# MessageFrame sends this exact leading sequence before dialogue.
		# Retain the raw text for CSX and save data.
		return text_content.trim_prefix("\\s:\\h:\\nb\\ni\\f:")

	func load_image(p_filename: String) -> int:
		filename = p_filename
		if host != null:
			var res := host.load_image(p_filename, archive_hint)
			if res.get("ok", false):
				image = res["image"]
				texture = res["texture"]
				animation_frames = res.get("frames", [image]).duplicate()
				animation_sequence = res.get("frame_sequence", []).duplicate()
				animation_total_time_ms = int(res.get("total_time_ms", 0))
				if animation_sequence.is_empty():
					for frame_index in animation_frames.size():
						animation_sequence.append(frame_index)
				size = Vector2i(image.get_width(), image.get_height())
				is_visible = true
				if host.current_bg.is_empty() or filename.begins_with("B") or filename.begins_with("EA"):
					host.current_bg = p_filename.get_file().get_basename()
					host.current_bg_texture = texture
					host.emit_signal("bg_updated", host.current_bg, texture)
				return 1
		return 0

	func attach_image(res: Variant) -> void:
		if res is HostResource:
			attached_resource = res
			filename = res.name
			archive_hint = res.archive_name
			if res.image == null and not res.name.is_empty():
				res.load_image(res.name)
			if res.image != null:
				image = res.image
				texture = res.texture
				size = Vector2i(image.get_width(), image.get_height())
				animation_frames = res.image_frames.duplicate()
				animation_sequence = res.image_frame_sequence.duplicate()
				animation_total_time_ms = res.image_total_time_ms
				if animation_sequence.is_empty():
					for frame_index in animation_frames.size():
						animation_sequence.append(frame_index)
		elif res is String:
			load_image(res)

	func set_visible(v: int) -> void:
		is_visible = (v != 0)

	func set_transparency(alpha: int) -> void:
		transparency = clampi(alpha, 0, 256)

	func set_blend_degree(degree: int) -> void:
		blending = degree
		if alpha_resource == null or alpha_range >= 256:
			transparency = clampi(degree, 0, 256)

	func get_blend_degree() -> int:
		return blending if alpha_resource != null and alpha_range < 256 else transparency

	func set_blending_envelope(b: int) -> void:
		activation_target_alpha = b

	func begin_activation(duration_ms: int) -> void:
		activation_start_alpha = get_blend_degree()
		activation_end_alpha = clampi(activation_target_alpha, 0, 256)
		activation_duration_ms = float(duration_ms)
		activation_elapsed_ms = 0.0
		is_activating = true
		_apply_activation_curves(0.0)
		if duration_ms <= 0 or host == null:
			flush_activation()
			return
		host.active_sprites[get_instance_id()] = weakref(self)

	func advance_activation(delta_ms: float) -> void:
		activation_elapsed_ms += delta_ms
		if activation_elapsed_ms >= activation_duration_ms:
			flush_activation()
			return
		var progress := activation_elapsed_ms / activation_duration_ms
		set_blend_degree(roundi(lerpf(activation_start_alpha, activation_end_alpha, progress)))
		_apply_activation_curves(progress)

	func _apply_activation_curves(progress: float) -> void:
		for index in [0, 2]:
			var points: Array = activation_curves[index]
			if points.size() != 4:
				continue
			var inverse := 1.0 - progress
			var value: Vector2 = points[0] * inverse * inverse * inverse + points[1] * 3.0 * inverse * inverse * progress + points[2] * 3.0 * inverse * progress * progress + points[3] * progress * progress * progress
			if index == 0:
				position = Vector2i(roundi(value.x), roundi(value.y))
			else:
				magnification = value

	func flush_activation() -> void:
		set_blend_degree(activation_end_alpha if is_activating else clampi(activation_target_alpha, 0, 256))
		if is_activating:
			_apply_activation_curves(1.0)
		activation_curves = [[], [], []]
		is_activating = false
		if host != null:
			host.active_sprites.erase(get_instance_id())
		if fields.has("activation_position"):
			position = fields["activation_position"]
			fields.erase("activation_position")

	func is_activation() -> int:
		return -1 if is_activating else 0

	func move_position(x: int, y: int) -> void:
		position = Vector2i(x, y)

	func create_message(width: int, height: int) -> int:
		if width <= 0 or height <= 0:
			return 0
		is_message_sprite = true
		size = Vector2i(width, height)
		text_content = ""
		message_visible_count = 0
		message_pending = false
		return 1

	func set_sprite_text(item_id: String, value: String) -> int:
		var target := find_form_item(item_id) if not item_id.is_empty() else self
		if target == null:
			target = self
		target.text_content = value
		target.message_visible_count = -1
		target.message_pending = false
		if host != null:
			host.active_messages.erase(target.get_instance_id())
			host.message_output.emit(target)
		return 1

	func get_sprite_text(item_id: String) -> String:
		var target := find_form_item(item_id) if not item_id.is_empty() else self
		return target.text_content if target != null else ""

	func get_render_size() -> Vector2i:
		if str(fields.get("effect_type", "")) == "TileImage":
			var effect_size: Vector2i = fields.get("effect_size", Vector2i.ZERO)
			if effect_size.x > 0 and effect_size.y > 0:
				return effect_size
		return size

	func begin_animation(loop_count: int = 1, begin_sequence: int = 0, animation_time_ms: int = -1, rewind_sequence: int = 0, turn_sequence: int = -1) -> int:
		if animation_frames.is_empty() or animation_sequence.is_empty():
			return -1
		var sequence_length := animation_sequence.size()
		if begin_sequence < 0:
			begin_sequence = animation_begin_sequence
		else:
			begin_sequence = posmod(begin_sequence, sequence_length)
		animation_begin_sequence = begin_sequence
		animation_start_sequence = begin_sequence
		animation_elapsed_ms = 0.0
		animation_loop_count = loop_count
		animation_rewind_sequence = maxi(0, rewind_sequence)
		animation_turn_sequence = sequence_length if turn_sequence < 0 else clampi(turn_sequence + 1, 1, 1000000)
		var total_time := animation_total_time_ms
		animation_duration_ms = float(total_time if animation_time_ms < 0 else maxi(0, animation_time_ms))
		animation_elapsed_ms = float(begin_sequence * total_time / sequence_length)
		_set_animation_frame(animation_sequence[begin_sequence])
		if host != null and animation_loop_count != 0:
			host.active_animated_sprites[get_instance_id()] = weakref(self)
		return 0

	func end_animation() -> int:
		animation_loop_count = 0
		if host != null:
			host.active_animated_sprites.erase(get_instance_id())
		return 0

	func attach_tone_filter(filter: HostToneFilter) -> int:
		tone_filter = filter
		return 0

	func advance_animation(delta_ms: float) -> void:
		if animation_loop_count == 0 or animation_sequence.is_empty():
			return
		if host != null and (host.sprite_animation_flags & 1) == 0:
			if animation_loop_count != -1:
				end_animation()
			return
		var sequence_length := animation_sequence.size()
		var turn_length := maxi(1, animation_turn_sequence)
		var duration := animation_duration_ms
		if duration <= 0:
			return
		animation_elapsed_ms += delta_ms
		if animation_elapsed_ms >= duration:
			var rewind_time := animation_rewind_sequence * duration / turn_length
			if animation_loop_count != -1:
				animation_loop_count -= 1
			if animation_loop_count != 0:
				animation_elapsed_ms = fmod(animation_elapsed_ms - duration, maxf(1.0, duration - rewind_time)) + rewind_time
			else:
				animation_elapsed_ms = maxf(0.0, duration - 1.0)
		var sequence_index := posmod(int(animation_elapsed_ms * turn_length / duration), sequence_length)
		animation_begin_sequence = sequence_index
		_set_animation_frame(animation_sequence[sequence_index])
		if animation_loop_count == 0 and host != null:
			host.active_animated_sprites.erase(get_instance_id())

	func _set_animation_frame(frame_index: int) -> void:
		if frame_index < 0 or frame_index >= animation_frames.size() or animation_view_frame == frame_index:
			return
		animation_view_frame = frame_index
		image = animation_frames[frame_index]
		texture = ImageTexture.create_from_image(image)

	func set_effect_parameter(parameter: Variant, mask: Variant = null) -> int:
		if parameter == null or not parameter is Object or not parameter.has_method("get_field") or str(parameter.get("type_name")) != "EffectParam":
			if host != null:
				host.report_unsupported("HostSprite.SetEffectParameter requires EffectParam")
			return -1
		var effect: Variant = parameter
		var effect_type := str(effect.get_field("strType"))
		if effect_type.is_empty() or effect_type == "Nothing":
			fields.erase("effect_type")
			fields.erase("effect_parameters")
			fields.erase("effect_size")
			fields.erase("effect_scroll")
			fields.erase("effect_elapsed_ms")
			fields.erase("effect_mask")
			fields.erase("effect_shaking_width")
			fields.erase("effect_mesh_size")
			fields.erase("effect_frequency")
			fields.erase("effect_interval_ms")
			fields.erase("effect_degree_step")
			fields.erase("effect_transition")
			if host != null:
				host.active_effect_sprites.erase(get_instance_id())
			return 0
		var known_types := ["TileImage", "FilterWhite", "FilterLight", "FilterBlack", "FilterDark", "RasterScroll", "WaveCircle", "Shimmer", "MeshWarp", "ShadingOff", "ShadingLight", "SmashParticle2D", "SmashParticle3D"]
		if not known_types.has(effect_type):
			if host != null:
				host.report_unsupported("HostSprite.SetEffectParameter %s" % effect_type)
			return -1
		if effect_type not in ["TileImage", "FilterWhite", "FilterLight", "FilterBlack", "FilterDark", "RasterScroll", "WaveCircle", "ShadingOff", "ShadingLight"]:
			if host != null:
				host.report_unsupported("HostSprite.SetEffectParameter %s renderer" % effect_type)
			return -1
		fields["effect_type"] = effect_type
		fields["effect_parameters"] = effect.fields.duplicate(true)
		if effect_type == "TileImage":
			var size_value: Variant = effect.get_field("sizeView")
			var speed_value: Variant = effect.get_field("ptSpeed")
			var width := int(size_value.get_field("w")) if size_value is Object and size_value.has_method("get_field") else 0
			var height := int(size_value.get_field("h")) if size_value is Object and size_value.has_method("get_field") else 0
			if width <= 0 or height <= 0 or width > 8192 or height > 8192 or width * height > 33554432:
				return -1
			fields["effect_size"] = Vector2i(width, height)
			var speed_x: Variant = speed_value.get_field("x") if speed_value is Object and speed_value.has_method("get_field") else 0
			var speed_y: Variant = speed_value.get_field("y") if speed_value is Object and speed_value.has_method("get_field") else 0
			fields["effect_scroll_speed"] = Vector2i(int(speed_x) if speed_x != null else 0, int(speed_y) if speed_y != null else 0)
			fields["effect_scroll"] = Vector2i.ZERO
			fields["effect_elapsed_ms"] = 0.0
			var interval_value: Variant = effect.get_field("nInterval")
			fields["effect_interval_ms"] = maxi(0, int(interval_value) if interval_value != null else 0)
			fields["effect_mask"] = mask if mask is HostResource else null
		elif effect_type == "RasterScroll":
			fields["effect_shaking_width"] = maxi(0, mini(4096, _effect_integer(effect, "nShakingWidth")))
			fields["effect_mesh_size"] = maxi(1, mini(8192, _effect_integer(effect, "nMeshSize", 1)))
			fields["effect_frequency"] = _effect_integer(effect, "nFrequency")
			fields["effect_interval_ms"] = maxi(0, _effect_integer(effect, "nInterval"))
			fields["effect_degree_step"] = _effect_integer(effect, "nDegreeStep")
			fields["effect_transition"] = (_effect_integer(effect, "nFlags") & 1) != 0
			fields["effect_elapsed_ms"] = 0.0
		elif effect_type == "WaveCircle":
			fields["effect_shaking_width"] = maxi(0, mini(4096, _effect_integer(effect, "nShakingWidth")))
			fields["effect_mesh_size"] = maxi(1, mini(8192, _effect_integer(effect, "nMeshSize", 16)))
			fields["effect_frequency"] = _effect_integer(effect, "nFrequency")
			fields["effect_interval_ms"] = maxi(0, _effect_integer(effect, "nInterval"))
			fields["effect_degree_step"] = _effect_integer(effect, "nDegreeStep")
			fields["effect_transition"] = (_effect_integer(effect, "nFlags") & 1) != 0
			fields["effect_elapsed_ms"] = 0.0
		elif effect_type in ["ShadingOff", "ShadingLight"]:
			fields["effect_transition"] = (_effect_integer(effect, "nFlags") & 1) != 0
		else:
			fields.erase("effect_size")
			fields.erase("effect_scroll_speed")
			fields.erase("effect_scroll")
			fields.erase("effect_elapsed_ms")
			fields.erase("effect_interval_ms")
			fields.erase("effect_mask")
			fields.erase("effect_shaking_width")
			fields.erase("effect_mesh_size")
			fields.erase("effect_frequency")
			fields.erase("effect_degree_step")
			fields.erase("effect_transition")
		if host != null:
			host.active_effect_sprites[get_instance_id()] = weakref(self)
		return 0

	func set_mesh_warp_effect(mesh_values: Variant, mesh_list_count: int, mesh_width: int, mesh_height: int, base_values: Variant = null) -> int:
		if not mesh_values is Array or mesh_list_count <= 0 or mesh_list_count > 32 or mesh_width <= 0 or mesh_height <= 0 or mesh_width > 128 or mesh_height > 128:
			return -1
		var vertex_count := (mesh_width + 1) * (mesh_height + 1)
		if vertex_count > 16384 or vertex_count * mesh_list_count > 65536:
			return -1
		var flattened: Array = mesh_values
		if flattened.size() < vertex_count * mesh_list_count * 2:
			return -1
		var mesh_frames: Array[PackedVector2Array] = []
		var value_index := 0
		for _frame_index in range(mesh_list_count):
			var frame := PackedVector2Array()
			frame.resize(vertex_count)
			for point_index in range(vertex_count):
				var x_value: Variant = flattened[value_index]
				var y_value: Variant = flattened[value_index + 1]
				if not (x_value is int or x_value is float) or not (y_value is int or y_value is float):
					return -1
				var point := Vector2(float(x_value), float(y_value))
				if not is_finite(point.x) or not is_finite(point.y) or absf(point.x) > 65536.0 or absf(point.y) > 65536.0:
					return -1
				frame[point_index] = point
				value_index += 2
			mesh_frames.append(frame)
		var base_frame := PackedVector2Array()
		base_frame.resize(vertex_count)
		if base_values is Array:
			var base_array: Array = base_values
			if base_array.size() < vertex_count * 2:
				return -1
			for point_index in range(vertex_count):
				var bx: Variant = base_array[point_index * 2]
				var by: Variant = base_array[point_index * 2 + 1]
				if not (bx is int or bx is float) or not (by is int or by is float):
					return -1
				base_frame[point_index] = Vector2(float(bx), float(by))
		else:
			for row in range(mesh_height + 1):
				for column in range(mesh_width + 1):
					var idx := row * (mesh_width + 1) + column
					base_frame[idx] = Vector2(float(size.x) * column / mesh_width, float(size.y) * row / mesh_height)
		fields["effect_type"] = "MeshWarp"
		fields["effect_mesh_frames"] = mesh_frames
		fields["effect_mesh_base"] = base_frame
		fields["effect_mesh_width"] = mesh_width
		fields["effect_mesh_height"] = mesh_height
		fields["effect_transition"] = true
		fields["effect_render_revision"] = int(fields.get("effect_render_revision", 0)) + 1
		return 0

	func _effect_integer(effect: Variant, field_name: String, default_value: int = 0) -> int:
		var value: Variant = effect.get_field(field_name)
		return int(value) if value is int or value is float or value is bool else default_value

	func modify_animation_flags(add_flags: int, remove_flags: int) -> int:
		if host == null:
			return 0
		host.sprite_animation_flags = (host.sprite_animation_flags | add_flags) & ~remove_flags
		return host.sprite_animation_flags

	func get_scroll_position(item_id: String, axis: String = "horz") -> int:
		var target := find_form_item(item_id)
		if target != null:
			return int(target.fields.get("scroll_%s_pos" % axis, 0))
		var values: Dictionary = fields.get("scroll_%s_positions" % axis, {})
		return int(values.get(item_id, 0))

	func get_scroll_range(item_id: String, axis: String = "horz") -> int:
		var target := find_form_item(item_id)
		if target != null:
			return int(target.fields.get("scroll_%s_range" % axis, 256))
		var ranges: Dictionary = fields.get("scroll_%s_ranges" % axis, {})
		return int(ranges.get(item_id, 256))

	func set_scroll_position(value: int, item_id: String, axis: String = "horz") -> int:
		var target := find_form_item(item_id)
		if target != null:
			var range_value := int(target.fields.get("scroll_%s_range" % axis, 256))
			target.fields["scroll_%s_pos" % axis] = clampi(value, 0, maxi(0, range_value))
			return 1
		var values: Dictionary = fields.get("scroll_%s_positions" % axis, {})
		var ranges: Dictionary = fields.get("scroll_%s_ranges" % axis, {})
		values[item_id] = clampi(value, 0, maxi(0, int(ranges.get(item_id, 256))))
		fields["scroll_%s_positions" % axis] = values
		return 1

	func set_scroll_range(value: int, item_id: String, axis: String = "horz") -> int:
		var target := find_form_item(item_id)
		if target != null:
			target.fields["scroll_%s_range" % axis] = maxi(0, value)
			var position_key := "scroll_%s_pos" % axis
			target.fields[position_key] = mini(int(target.fields.get(position_key, 0)), maxi(0, value))
			return 1
		var ranges: Dictionary = fields.get("scroll_%s_ranges" % axis, {})
		ranges[item_id] = maxi(0, value)
		fields["scroll_%s_ranges" % axis] = ranges
		return set_scroll_position(get_scroll_position(item_id, axis), item_id, axis)

	func is_hit_at(x: int, y: int) -> bool:
		if not is_visible or not is_enabled or transparency >= 256:
			return false
		return get_sprite_rect().has_point(Vector2(x, y))

	func get_sprite_rect() -> Rect2:
		var render_size := get_render_size()
		if render_size.x <= 0 or render_size.y <= 0:
			return Rect2()
		var pivot := Vector2(rev_center)
		var first_corner := Vector2(position) - pivot + pivot - pivot * magnification
		var second_corner := first_corner + Vector2(render_size) * magnification
		var rect_position := Vector2(minf(first_corner.x, second_corner.x), minf(first_corner.y, second_corner.y))
		var rect_size := Vector2(absf(second_corner.x - first_corner.x), absf(second_corner.y - first_corner.y))
		return Rect2(rect_position, rect_size)

	func add_sprite(z: int, child: Variant) -> void:
		if child is HostSprite:
			child.z_order = z
			var item_id: String = child.btn_id if not child.btn_id.is_empty() else str(child.fields.get("form_item_id", ""))
			var enabled_items: Dictionary = fields.get("item_enabled_status", {})
			if not item_id.is_empty() and enabled_items.has(item_id):
				child.is_enabled = bool(enabled_items[item_id])
			if not children.has(child):
				children.append(child)
			child.refresh_command_ids()

	func find_form_item(item_id: String) -> HostSprite:
		for child in children:
			if child.btn_id == item_id or child.fields.get("form_item_id") == item_id:
				return child
		return null

	func set_form_image(item_id: String, resource_id: String) -> bool:
		var item := find_form_item(item_id)
		return item != null and form_resources != null and form_resources._set_form_texture(item, resource_id)

	func refresh_command_ids() -> void:
		var page_id := str(fields.get("form_page_id", ""))
		if not page_id.begins_with("ID_PAGE_TAG"):
			return
		var tag_index := int(page_id.trim_prefix("ID_PAGE_TAG"))
		if tag_index <= 0:
			tag_index = maxi(1, z_order - 9)
		for child in children:
			if child is HostSprite and not child.btn_id.is_empty():
				child.full_btn_id = "ID_PAGE_TAG%d\\\\%s" % [tag_index, child.btn_id]

	func detach_sprite(child: Variant) -> void:
		if child is HostSprite:
			children.erase(child)

	func detach_all_sprites() -> void:
		children.clear()

	func release() -> int:
		is_activating = false
		if host != null:
			host.active_sprites.erase(get_instance_id())
		is_visible = false
		attached_resource = null
		image = null
		texture = null
		alpha_resource = null
		alpha_image = null
		alpha_texture = null
		return 0

	func create_sprite(_format: int, w: int, h: int) -> int:
		var cw := maxi(1, w)
		var ch := maxi(1, h)
		image = Image.create(cw, ch, false, Image.FORMAT_RGBA8)
		image.fill(Color(0, 0, 0, 0))
		texture = ImageTexture.create_from_image(image)
		size = Vector2i(cw, ch)
		return 0

	func set_back_color(rgb: int, enable: bool) -> int:
		back_color = rgb & 0xffffff
		fill_back_color = enable
		return 0

	func set_alpha_image(alpha_res: Variant, alpha_range_value: int = 256) -> int:
		alpha_resource = alpha_res as HostResource if alpha_res is HostResource else null
		alpha_image = null
		alpha_texture = null
		alpha_range = alpha_range_value & 0xffffffff
		if alpha_resource == null:
			return 0
		if alpha_resource.image == null and not alpha_resource.name.is_empty():
			alpha_resource.load_image(alpha_resource.name)
		if alpha_resource.image == null or alpha_resource.image.is_empty():
			alpha_resource = null
			return 0
		alpha_image = alpha_resource.image
		if alpha_range <= 256:
			var mask_size := alpha_image.get_size()
			if image == null or image.get_size() != mask_size or image.get_format() != Image.FORMAT_RGBA8:
				image = Image.create(mask_size.x, mask_size.y, false, Image.FORMAT_RGBA8)
				image.fill(Color(0, 0, 0, 0))
				texture = ImageTexture.create_from_image(image)
				size = Vector2i(mask_size)
			alpha_range = maxi(0, alpha_range)
			var mask: Image = alpha_image.duplicate()
			mask.convert(Image.FORMAT_RGBA8)
			var pixels: PackedByteArray = mask.get_data()
			for offset in range(0, pixels.size(), 4):
				var value: int = pixels[offset]
				pixels[offset + 1] = value
				pixels[offset + 2] = value
				pixels[offset + 3] = 255
			mask.set_data(mask.get_width(), mask.get_height(), false, Image.FORMAT_RGBA8, pixels)
			alpha_texture = ImageTexture.create_from_image(mask)
		return 0

	func fill_rect(rect: Variant = null, color: int = 0, trans: int = 0, _flags: int = 0) -> int:
		if image != null:
			var r := Rect2i(Vector2i.ZERO, size)
			if rect != null and rect.has_method("get_field"):
				var rx := int(rect.get_field("left"))
				var ry := int(rect.get_field("top"))
				var rw := int(rect.get_field("right")) - rx
				var rh := int(rect.get_field("bottom")) - ry
				if rw > 0 and rh > 0:
					r = Rect2i(rx, ry, rw, rh)
			var a := 1.0 - (float(trans) / 256.0) if trans > 0 else 1.0
			var c := _native_rgb_color(color)
			c.a = a
			image.fill_rect(r, c)
			texture = ImageTexture.create_from_image(image)
		return 0

	func _native_rgb_color(rgb: int) -> Color:
		return Color(float((rgb >> 16) & 0xff) / 255.0, float((rgb >> 8) & 0xff) / 255.0, float(rgb & 0xff) / 255.0, 1.0)

	func draw_image(src: Variant, param: Variant = null) -> int:
		var src_img: Image = null
		if src is HostSprite and src.image != null:
			src_img = src.image
		elif src is HostResource and src.image != null:
			src_img = src.image
		if src_img != null and image != null:
			var dst_pos := Vector2i.ZERO
			if param != null and param.has_method("get_field"):
				var pt = param.get_field("ptDstPos")
				if pt != null and pt.has_method("get_field"):
					dst_pos = Vector2i(int(pt.get_field("x")), int(pt.get_field("y")))
			var src_rect := Rect2i(Vector2i.ZERO, src_img.get_size())
			image.blend_rect(src_img, src_rect, dst_pos)
			texture = ImageTexture.create_from_image(image)
			return 1
		return 0

	func get_parameter(param: Variant) -> int:
		if param != null and param.has_method("set_field"):
			for key: String in sprite_parameters:
				param.set_field(key, sprite_parameters[key])
			param.set_field("rHorzUnit", magnification.x)
			param.set_field("rVertUnit", magnification.y)
			param.set_field("rRevAngle", rotation_degrees)
			param.set_field("nImageWidth", size.x)
			param.set_field("nImageHeight", size.y)
			param.set_field("nTransparency", transparency)
			for name in ["ptDstPos", "ptRevCenter"]:
				var point = param.get_field(name)
				if point != null and point.has_method("set_field"):
					var coordinates := position if name == "ptDstPos" else rev_center
					point.set_field("x", coordinates.x)
					point.set_field("y", coordinates.y)
		return 0

	func set_parameter(param: Variant) -> int:
		if param != null and param.has_method("get_field"):
			for key: String in sprite_parameters:
				var value: Variant = param.get_field(key)
				if value != null:
					sprite_parameters[key] = value
			var horz = param.get_field("rHorzUnit")
			var vert = param.get_field("rVertUnit")
			if horz != null:
				magnification.x = float(horz)
			if vert != null:
				magnification.y = float(vert)
			var angle = param.get_field("rRevAngle")
			if angle != null:
				rotation_degrees = float(angle)
			var w = param.get_field("nImageWidth")
			var h = param.get_field("nImageHeight")
			if w != null and h != null:
				size = Vector2i(int(w), int(h))
			var trans = param.get_field("nTransparency")
			if trans != null:
				transparency = clampi(int(trans), 0, 256)
			var pt = param.get_field("ptRevCenter")
			if pt != null and pt.has_method("get_field"):
				rev_center = Vector2i(int(pt.get_field("x")), int(pt.get_field("y")))
			var pos_pt = param.get_field("ptDstPos")
			if pos_pt != null and pos_pt.has_method("get_field"):
				position = Vector2i(int(pos_pt.get_field("x")), int(pos_pt.get_field("y")))
		return 0

	func open_movie(p_filename: String) -> int:
		filename = p_filename
		if host != null and not filename.is_empty():
			host.movie_opened = false
			host.emit_signal("movie_open_requested", filename)
			return 1 if host.movie_opened else 0
		return 0

	func play_movie(mode: int = 0) -> int:
		if host == null or filename.is_empty():
			return 0
		host.emit_signal("movie_requested", filename, mode)
		return 1

	func is_movie_playing() -> int:
		if host != null and host.is_movie_playing:
			return 1
		return 0

	func seek_frame(frame_index: int) -> int:
		if host == null or host.movie_total_frames <= 0 or frame_index < 0 or frame_index >= host.movie_total_frames:
			return 0
		host.emit_signal("movie_seek_requested", frame_index)
		return 1

	func get_current_frame() -> int:
		return host.movie_current_frame if host != null else -1

	func get_total_frame() -> int:
		return host.movie_total_frames if host != null else 0

	func get_total_time() -> int:
		return host.movie_total_time_ms if host != null else 0

	func stop_movie() -> int:
		if host != null:
			host.is_movie_playing = false
			host.emit_signal("movie_stop_requested")
		return 0

	func close_movie() -> int:
		stop_movie()
		if host != null:
			host.emit_signal("movie_close_requested")
			host.movie_opened = false
		filename = ""
		return 0



class HostWindow extends RefCounted:
	var host: CsxHost
	var viewport_size: Vector2i = Vector2i(800, 600)
	var root_sprites: Array[HostSprite] = []
	var fields: Dictionary = {}
	var focused_sprite: HostSprite = null
	var focused_path: String = ""

	func _init(p_host: CsxHost) -> void:
		host = p_host

	func add_sprite(z: int, spr: Variant) -> void:
		if spr is HostSprite:
			spr.z_order = z
			if not root_sprites.has(spr):
				root_sprites.append(spr)

	func detach_sprite(spr: Variant) -> void:
		if spr is HostSprite:
			if _contains_focused_sprite(spr):
				set_focus("")
			root_sprites.erase(spr)

	func _contains_focused_sprite(sprite: HostSprite) -> bool:
		if sprite == focused_sprite:
			return true
		for child: HostSprite in sprite.children:
			if _contains_focused_sprite(child):
				return true
		return false

	func detach_all_sprites() -> void:
		root_sprites.clear()
		set_focus("")

	func set_focus(path: String) -> int:
		var current: Array = root_sprites
		var target: HostSprite = null
		var parts := path.split("\\", false)
		for part: String in parts:
			target = _find_focus_item(current, part)
			if target == null:
				break
			current = target.children
		_apply_focus(target, path if target != null else "")
		return 0

	func _find_focus_item(sprites: Array, id: String) -> HostSprite:
		for sprite: HostSprite in sprites:
			if sprite.btn_id == id or str(sprite.fields.get("form_item_id", "")) == id:
				return sprite
		for sprite: HostSprite in sprites:
			var found := _find_focus_item(sprite.children, id)
			if found != null:
				return found
		return null

	func _apply_focus(target: HostSprite, path: String) -> void:
		if focused_sprite != null and focused_sprite.is_button and focused_sprite.btn_state == "focus":
			focused_sprite.set_button_state("normal")
		focused_sprite = target
		focused_path = path
		if target != null and target.is_button:
			target.set_button_state("focus")

	func get_focus() -> String:
		return focused_path

	func focus_sprite(sprite: HostSprite) -> void:
		var path := _find_focus_path(root_sprites, sprite, "")
		if not path.is_empty():
			_apply_focus(sprite, path)

	func _find_focus_path(sprites: Array, target: HostSprite, prefix: String) -> String:
		for sprite: HostSprite in sprites:
			var id := sprite.btn_id if not sprite.btn_id.is_empty() else str(sprite.fields.get("form_item_id", ""))
			var path := prefix
			if not id.is_empty():
				path += ("\\" if not path.is_empty() else "") + id
			if sprite == target:
				return path
			var child_path := _find_focus_path(sprite.children, target, path)
			if not child_path.is_empty():
				return child_path
		return ""

	func get_display_size() -> Vector2i:
		return viewport_size

	func get_parameter(param: Variant) -> int:
		if param != null and param.has_method("set_field"):
			param.set_field("nImageWidth", viewport_size.x)
			param.set_field("nImageHeight", viewport_size.y)
			param.set_field("nTransparency", 0)
			for point_name in ["ptDstPos", "ptRevCenter"]:
				var point: Variant = param.get_field(point_name) if param.has_method("get_field") else null
				if point != null and point.has_method("set_field"):
					point.set_field("x", 0)
					point.set_field("y", 0)
		return 0

	func show_cursor(_show_flag: int) -> int:
		return 0

	func set_optional_func_flag(_flag: int) -> int:
		return 0

	func lock() -> int:
		return 0

	func get_joy_button_pushed(key: int, _dev: int = 0, during_activation: bool = false) -> int:
		if host != null and host.active_input_filter_ref != null:
			var active_filter = host.active_input_filter_ref.get_ref()
			if active_filter is HostInputFilter:
				return active_filter.get_joy_button_pushed(key, 0, during_activation)
		return host.poll_advance_button(key, during_activation) if host != null else 0

	func is_joy_button_pushing(key: int, _dev: int = 0) -> int:
		if host != null and host.active_input_filter_ref != null:
			var active_filter = host.active_input_filter_ref.get_ref()
			if active_filter is HostInputFilter:
				return active_filter.is_joy_button_pushing(key)
		return 0

	func unlock() -> int:
		return 0

	func create_display(_mode: int = 0, _depth: int = 0, w: int = 800, h: int = 600) -> int:
		viewport_size = Vector2i(w, h)
		return 0

	func change_display(_fullscreen: int) -> int:
		return 0

	func update_rect() -> int:
		return 0

	func flush_joy_button_pushed() -> int:
		if host != null:
			host.skip_input_pending = false
			if host.active_input_filter_ref != null:
				var active_filter = host.active_input_filter_ref.get_ref()
				if active_filter is HostInputFilter:
					return active_filter.flush_joy_button_pushed()
		return 0

	func flush_command_queue(_flag: int = -1) -> int:
		# This queue contains complete UI commands already received by Godot,
		# not raw OS input waiting to be sampled. Dropping it here races clicks
		# against the original CSX poll/flush loop. Screen transitions clear it.
		return 0

	func get_command(p_cmd: Variant = null, _p1: int = 0, _p2: int = 0, _p3: int = 0) -> int:
		if host != null and host.command_queue.size() > 0:
			var event = host.command_queue.pop_front()
			var cmd_id: String = ""
			var full_id: String = ""
			var cmd_num: int = 1
			if event is Dictionary:
				cmd_id = event.get("id", "")
				full_id = event.get("full_id", cmd_id)
				cmd_num = event.get("command", 1)
			elif event is String:
				cmd_id = event
				full_id = cmd_id
				cmd_num = 1
			if p_cmd != null:
				if p_cmd.has_method("set_field"):
					p_cmd.set_field("strID", cmd_id)
					p_cmd.set_field("strFullID", full_id)
					p_cmd.set_field("nCommand", cmd_num)
				elif "fields" in p_cmd:
					p_cmd.fields["strID"] = cmd_id
					p_cmd.fields["strFullID"] = full_id
					p_cmd.fields["nCommand"] = cmd_num
			return 1
		return 0


class HostFile extends RefCounted:
	var host: CsxHost = null
	var current_path: String = ""
	var current_mode: int = 0
	var is_open: bool = false

	func _init(p_host: CsxHost) -> void:
		host = p_host

	func open(path: String, mode: int = 2) -> int:
		current_path = path
		current_mode = mode
		if host != null:
			if mode == 2:
				if not host.is_file_existing(path):
					is_open = false
					return 1
			is_open = true
			return 0
		is_open = false
		return 1

	func close() -> int:
		is_open = false
		current_path = ""
		return 0

	func save_object(obj: Variant) -> int:
		if not is_open or host == null or current_path.is_empty():
			return 1
		var ok: bool = host.save_object_file(current_path, obj)
		return 0 if ok else 1

	func load_object(obj: Variant) -> int:
		if not is_open or host == null or current_path.is_empty():
			return 1
		var ok: bool = host.load_object_file(current_path, obj)
		return 0 if ok else 1

	func save_thumbnail_image(spr: Variant, w: int = 120, h: int = 90) -> int:
		if host != null and not current_path.is_empty():
			host.save_thumbnail(current_path, spr, w, h)
		return 0

	func is_existing(path: String) -> int:
		if host != null:
			return -1 if host.is_file_existing(path) else 0
		return 0

	func dump_context(_path: String = "") -> int:
		return 0

	func output_log_text(path: String, text: String) -> int:
		if host != null:
			var sp := host.get_save_path(path)
			var f := FileAccess.open(sp, FileAccess.WRITE_READ)
			if f != null:
				f.seek_end()
				f.store_line(text)
		return 0




func poll_advance_button(key: int, during_activation: bool) -> int:
	if during_activation:
		yield_for_sprite_activation = true
	if key == 4:
		var skip_pressed := skip_input_pending
		skip_input_pending = false
		return 1 if skip_pressed else 0
	if key != 1:
		return 0
	var pushed := advance_ticks > 0 or auto_advance
	if advance_ticks > 0:
		advance_ticks -= 1
	is_waiting_input = not pushed and not during_activation
	return 1 if pushed else 0


func advance_sprite_animations(delta: float) -> void:
	for sprite_id in active_messages.keys():
		var sprite := active_messages[sprite_id].get_ref() as HostSprite
		if sprite == null:
			active_messages.erase(sprite_id)
		else:
			sprite.advance_message(delta * 1000.0)
	for sprite_id in active_sprites.keys():
		var sprite := active_sprites[sprite_id].get_ref() as HostSprite
		if sprite == null:
			active_sprites.erase(sprite_id)
		else:
			sprite.advance_activation(delta * 1000.0)
	for sprite_id in active_animated_sprites.keys():
		var sprite := active_animated_sprites[sprite_id].get_ref() as HostSprite
		if sprite == null:
			active_animated_sprites.erase(sprite_id)
		else:
			sprite.advance_animation(delta * 1000.0)
	for sprite_id in active_effect_sprites.keys():
		var sprite := active_effect_sprites[sprite_id].get_ref() as HostSprite
		if sprite == null:
			active_effect_sprites.erase(sprite_id)
			continue
		var effect_type := str(sprite.fields.get("effect_type", ""))
		if effect_type not in ["TileImage", "RasterScroll", "WaveCircle"]:
			continue
		var interval := int(sprite.fields.get("effect_interval_ms", 0))
		if interval <= 0:
			continue
		var elapsed := float(sprite.fields.get("effect_elapsed_ms", 0.0)) + delta * 1000.0
		var steps := int(elapsed / interval)
		sprite.fields["effect_elapsed_ms"] = fmod(elapsed, float(interval))
		if steps <= 0:
			continue
		if effect_type == "TileImage":
			var tile_view_size := sprite.get_render_size()
			if (sprite_animation_flags & 4) == 0 or tile_view_size.x <= 0 or tile_view_size.y <= 0:
				continue
			var scroll: Vector2i = sprite.fields.get("effect_scroll", Vector2i.ZERO)
			var speed: Vector2i = sprite.fields.get("effect_scroll_speed", Vector2i.ZERO)
			scroll += speed * steps
			if speed.x > 0:
				scroll.x = posmod(scroll.x, tile_view_size.x) - tile_view_size.x
			elif speed.x < 0:
				scroll.x = posmod(scroll.x, tile_view_size.x)
			if speed.y > 0:
				scroll.y = posmod(scroll.y, tile_view_size.y) - tile_view_size.y
			elif speed.y < 0:
				scroll.y = posmod(scroll.y, tile_view_size.y)
			sprite.fields["effect_scroll"] = scroll
		elif (sprite_animation_flags & 4) != 0:
			var degree := sprite.blending + steps * int(sprite.fields.get("effect_degree_step", 0))
			while degree >= 0x300:
				degree -= 0x100
			sprite.blending = degree
		elif sprite.blending != 0:
			sprite.blending = 0


func advance_audio_envelopes(delta: float) -> void:
	for resource_id in active_volume_envelopes.keys():
		var resource := active_volume_envelopes[resource_id].get_ref() as HostResource
		if resource == null:
			active_volume_envelopes.erase(resource_id)
		else:
			resource.advance_volume_envelope(delta * 1000.0)


func push_command(cmd: String, full_id: String = "") -> void:
	if full_id.is_empty() or full_id == cmd:
		command_queue.append(cmd)
	else:
		command_queue.append({"id": cmd, "full_id": full_id, "command": 1})


func set_tone_filter(type_name: String) -> void:
	current_tone_filter = type_name.to_upper()
	emit_signal("tone_filter_updated", current_tone_filter)


func _init(p_game_dir: String = "") -> void:
	game_dir = p_game_dir
	if not game_dir.is_empty():
		init_vfs()


func init_vfs() -> void:
	var standard_archives: Array[String] = [
		"data1.noa",
		"data2.noa",
		"sound.noa",
		"voice.noa",
		"system/frame.noa",
		"system/title.noa",
		"system/option.noa"
	]
	for arc in standard_archives:
		get_or_open_archive(arc)


func get_or_open_archive(archive_filename: String) -> NoaArchiveReader:
	var archive_file := archive_filename.replace("\\", "/").get_file()
	var candidate_paths: Array[String] = [
		game_dir.path_join("system").path_join(archive_file),
		game_dir.path_join(archive_file),
		"res://assets/system/".path_join(archive_file),
		"res://assets/".path_join(archive_file),
		"user://game/system/".path_join(archive_file),
		"user://game/".path_join(archive_file),
		"user://assets/system/".path_join(archive_file),
		"user://assets/".path_join(archive_file),
		archive_filename
	]
	var found_path := ""
	for path in candidate_paths:
		if FileAccess.file_exists(path):
			found_path = path
			break

	if found_path.is_empty():
		last_error = "未找到资源归档: %s" % archive_filename
		return null
	var canonical_path := ProjectSettings.globalize_path(found_path).simplify_path().to_lower()
	if archives.has(canonical_path):
		return archives[canonical_path]

	var noa := NoaArchiveReader.new()
	var res: Dictionary = noa.inspect(found_path)
	if not res.get("ok", false):
		last_error = "无法读取资源归档 %s: %s" % [found_path, res.get("error", "未知错误")]
		return null

	archives[canonical_path] = noa
	for i in range(noa.entries.size()):
		var entry: Dictionary = noa.entries[i]
		if str(entry.get("kind", "")) != "file":
			continue
		var en := _normalize_vfs_path(str(entry.get("name", "")))
		if en.is_empty():
			continue
		var candidate := {
			"reader": noa,
			"index": i,
			"archive": canonical_path,
			"entry_name": en,
		}
		var candidates: Array = vfs_index.get(en, [])
		candidates.append(candidate)
		vfs_index[en] = candidates
		if candidates.size() > 1:
			var conflict_index := -1
			for conflict_pos in range(vfs_conflicts.size()):
				if str(vfs_conflicts[conflict_pos].get("entry", "")) == en:
					conflict_index = conflict_pos
					break
			var conflict := {"entry": en, "candidates": _describe_vfs_candidates(candidates)}
			if conflict_index < 0:
				vfs_conflicts.append(conflict)
			else:
				vfs_conflicts[conflict_index] = conflict
	return noa


func _normalize_vfs_path(path: String) -> String:
	return path.replace("\\", "/").simplify_path().trim_prefix("./").to_lower()


func _describe_vfs_candidates(candidates: Array) -> Array[Dictionary]:
	var descriptions: Array[Dictionary] = []
	for candidate: Dictionary in candidates:
		descriptions.append({
			"archive": str(candidate.get("archive", "")),
			"entry": str(candidate.get("entry_name", "")),
			"index": int(candidate.get("index", -1)),
		})
	return descriptions


func get_vfs_conflict_report() -> Array[Dictionary]:
	var report: Array[Dictionary] = []
	for conflict: Dictionary in vfs_conflicts:
		report.append(conflict.duplicate(true))
	return report


func _vfs_cache_key(entry: Dictionary) -> String:
	return "%s::%s#%d" % [
		str(entry.get("archive", "")),
		str(entry.get("entry_name", "")),
		int(entry.get("index", -1)),
	]


func _archive_matches_hint(archive_path: String, archive_hint: String) -> bool:
	var hint := archive_hint.replace("\\", "/").simplify_path().to_lower()
	if hint.begins_with("res://") or hint.begins_with("user://"):
		hint = ProjectSettings.globalize_path(hint).simplify_path().to_lower()
	var canonical_archive := archive_path.replace("\\", "/").simplify_path().to_lower()
	if hint.is_empty():
		return false
	if hint.contains("/"):
		return canonical_archive == hint or canonical_archive.ends_with("/" + hint)
	return canonical_archive.get_file() == hint.get_file()


func find_vfs_entry(filename: String, archive_hint: String = "") -> Dictionary:
	var raw := _normalize_vfs_path(filename)
	var base := raw.get_file()
	var candidates: Array[String] = [
		raw,
		raw + ".eri",
		raw + ".mio",
		base,
		base + ".eri",
		base + ".mio"
	]
	for c in candidates:
		if vfs_index.has(c):
			var entries: Array = vfs_index[c] if vfs_index[c] is Array else [vfs_index[c]]
			if not archive_hint.is_empty():
				for entry: Dictionary in entries:
					if _archive_matches_hint(str(entry.get("archive", "")), archive_hint):
						return entry
				last_error = "VFS 归档提示与条目候选不匹配: %s (%s)" % [filename, archive_hint]
				return {}
			if entries.size() > 1 and not vfs_warned_conflicts.has(c):
				vfs_warned_conflicts[c] = true
				push_warning("VFS 条目有多个归档候选，按加载顺序选择首项: %s；请查阅 get_vfs_conflict_report()" % c)
			return entries[0] if not entries.is_empty() else {}
	last_error = "VFS entry not found: %s" % filename
	return {}


func _read_vfs_candidate(entry: Dictionary) -> Dictionary:
	var reader: NoaArchiveReader = entry.get("reader")
	if reader == null:
		return {"ok": false, "error": "VFS 候选没有有效归档读取器。"}
	var result: Dictionary = reader.read_entry(int(entry.get("index", -1)))
	if result.get("ok", false):
		result["archive"] = str(entry.get("archive", ""))
		result["entry_name"] = str(entry.get("entry_name", ""))
		result["entry_index"] = int(entry.get("index", -1))
		result["cache_key"] = _vfs_cache_key(entry)
	return result


func read_vfs_entry(filename: String, archive_hint: String = "") -> Dictionary:
	var entry := find_vfs_entry(filename, archive_hint)
	if entry.is_empty():
		return {"ok": false, "error": last_error if not last_error.is_empty() else "VFS entry not found: %s" % filename}
	return _read_vfs_candidate(entry)


func get_save_path(filename: String) -> String:
	return save_dir.path_join(filename.get_file())


func get_thumbnail_path(filename: String) -> String:
	var base := filename.get_file().get_basename()
	return save_dir.path_join(base + ".png")


func _is_story_save(path: String) -> bool:
	var filename := path.get_file().trim_suffix(".bak").to_lower()
	return filename == "qsave.dat" or (filename.length() == 11 and filename.begins_with("save") and filename.ends_with(".dat") and filename.substr(4, 3).is_valid_int())


func is_file_existing(filename: String) -> bool:
	if filename.is_empty():
		return false
	var sp := get_save_path(filename)
	if _is_story_save(sp):
		return not read_save_snapshot(sp).is_empty()
	if FileAccess.file_exists(sp) or (FileAccess.file_exists(sp + ".bak") and not read_save_snapshot(sp).is_empty()):
		return true
	if FileAccess.file_exists(game_dir.path_join(filename)) or FileAccess.file_exists(game_dir.path_join("system").path_join(filename)) or FileAccess.file_exists("user://".path_join(filename)):
		return true
	return not find_vfs_entry(filename).is_empty()



func load_image(filename: String, archive_hint: String = "") -> Dictionary:
	var norm := _normalize_vfs_path(filename)
	if not norm.ends_with(".eri"):
		norm += ".eri"
	var entry := find_vfs_entry(norm, archive_hint)
	if entry.is_empty():
		return {"ok": false, "error": last_error if not last_error.is_empty() else "无法在 VFS 中找到图片: %s" % norm}
	var cache_key := _vfs_cache_key(entry)
	if image_cache.has(cache_key):
		var item: Dictionary = image_cache[cache_key]
		image_cache_lru.erase(cache_key)
		image_cache_lru.append(cache_key)
		return item.duplicate()

	var entry_res := _read_vfs_candidate(entry)
	if not entry_res.get("ok", false):
		return {"ok": false, "error": "无法在 VFS 中找到图片: %s" % norm}

	var dec_res := EriDecoder.decode(entry_res["data"])
	if not dec_res.get("ok", false):
		return dec_res

	var img: Image = dec_res["image"]
	var tex := ImageTexture.create_from_image(img)
	var frames: Array = dec_res.get("frames", [img])
	var frame_sequence: Array = dec_res.get("frame_sequence", [])
	var total_time_ms := int(dec_res.get("total_time_ms", 0))
	var estimated_bytes := img.get_data().size() * maxi(2, frames.size())
	var image_result := {"ok": true, "image": img, "texture": tex, "frames": frames, "frame_sequence": frame_sequence, "total_time_ms": total_time_ms}
	if estimated_bytes <= image_cache_budget_bytes:
		image_cache[cache_key] = image_result.merged({"bytes": estimated_bytes})
		image_cache_lru.append(cache_key)
		image_cache_bytes += estimated_bytes
		_trim_image_cache()
	return image_result


func load_sound(filename: String, archive_hint: String = "") -> Dictionary:
	var norm := _normalize_vfs_path(filename)
	if not norm.ends_with(".mio"):
		norm += ".mio"
	var entry := find_vfs_entry(norm, archive_hint)
	if entry.is_empty():
		return {"ok": false, "error": last_error if not last_error.is_empty() else "无法在 VFS 中找到音频: %s" % norm}
	var cache_key := _vfs_cache_key(entry)
	if sound_cache.has(cache_key):
		sound_cache_lru.erase(cache_key)
		sound_cache_lru.append(cache_key)
		return {
			"ok": true,
			"stream": sound_cache[cache_key],
			"archive": str(entry.get("archive", "")),
			"entry_name": str(entry.get("entry_name", norm)),
		}

	var entry_res := _read_vfs_candidate(entry)
	if not entry_res.get("ok", false):
		return {"ok": false, "error": "无法在 VFS 中找到音频: %s" % norm}

	var dec_res := MioDecoder.decode(entry_res["data"])
	if not dec_res.get("ok", false):
		last_error = str(dec_res.get("error", "MIO 音频解码失败: %s" % norm))
		return dec_res

	var stream: AudioStreamWAV = dec_res["stream"]
	var stream_bytes := stream.data.size()
	if stream_bytes <= sound_cache_budget_bytes:
		sound_cache[cache_key] = stream
		sound_cache_lru.append(cache_key)
		sound_cache_bytes += stream_bytes
		_trim_sound_cache()
	return {
		"ok": true,
		"stream": stream,
		"archive": str(entry_res.get("archive", entry.get("archive", ""))),
		"entry_name": str(entry_res.get("entry_name", norm)),
	}


func _trim_image_cache() -> void:
	while image_cache_bytes > image_cache_budget_bytes and not image_cache_lru.is_empty():
		var oldest: String = image_cache_lru.pop_front()
		if not image_cache.has(oldest):
			continue
		var cached: Dictionary = image_cache[oldest]
		image_cache_bytes = maxi(0, image_cache_bytes - int(cached.get("bytes", 0)))
		image_cache.erase(oldest)


func _trim_sound_cache() -> void:
	while sound_cache_bytes > sound_cache_budget_bytes and not sound_cache_lru.is_empty():
		var oldest: String = sound_cache_lru.pop_front()
		if not sound_cache.has(oldest):
			continue
		var cached: AudioStreamWAV = sound_cache[oldest]
		sound_cache_bytes = maxi(0, sound_cache_bytes - cached.data.size())
		sound_cache.erase(oldest)


func clear_resource_caches() -> void:
	image_cache.clear()
	image_cache_lru.clear()
	image_cache_bytes = 0
	sound_cache.clear()
	sound_cache_lru.clear()
	sound_cache_bytes = 0


func resolve_audio_channel(name: String, archive_hint: String = "") -> String:
	var n := name.get_file().to_lower()
	if n.begins_with("bgm"):
		return "bgm"
	if n.begins_with("se270"):
		return "env_se"
	if n.begins_with("se"):
		return "se"
	if n.begins_with("sr") or n.begins_with("so") or n.begins_with("ak") or n.begins_with("no") or n.begins_with("na") or n.begins_with("ka") or n.begins_with("mt") or n.begins_with("mo") or n.begins_with("ko") or n.begins_with("yh") or n.begins_with("ya") or n.begins_with("rh") or n.begins_with("ry") or n.begins_with("vo"):
		return "voice"
	if n.begins_with("system") or n.begins_with("sys"):
		return "system"
	var archive := archive_hint.get_file().to_lower()
	if archive == "voice.noa":
		return "voice"
	return ""


func get_cursor_position() -> Vector2i:
	if cursor_position_provider.is_valid():
		var value: Variant = cursor_position_provider.call()
		if value is Vector2i:
			return value
		if value is Vector2:
			return Vector2i(roundi(value.x), roundi(value.y))
	return Vector2i.ZERO


func _audio_player_for_channel(channel: String) -> AudioStreamPlayer:
	match channel.strip_edges().to_lower():
		"bgm": return bgm_player
		"env_se": return env_se_player
		"se": return se_player
		"voice": return voice_player
		"system": return system_player
		_: return null


func _right_audio_player_for_channel(channel: String) -> AudioStreamPlayer:
	var player: Variant = audio_right_players.get(channel.strip_edges().to_lower())
	return player as AudioStreamPlayer if player is AudioStreamPlayer else null


func _set_audio_player_volume(player: AudioStreamPlayer, linear_volume: float) -> void:
	var volume := clampf(linear_volume, 0.0, 1.0)
	player.volume_db = -80.0 if volume <= 0.0001 else linear_to_db(volume)


func _make_audio_lane_stream(source: AudioStreamWAV, lane: int) -> AudioStreamWAV:
	var result := source.duplicate() as AudioStreamWAV
	if result == null or lane not in [0, 1]:
		return null
	var sample_bytes := 1 if source.format == AudioStreamWAV.FORMAT_8_BITS else 2
	if source.format not in [AudioStreamWAV.FORMAT_8_BITS, AudioStreamWAV.FORMAT_16_BITS]:
		return null
	var source_channels := 2 if source.stereo else 1
	var source_frame_bytes := sample_bytes * source_channels
	if source_frame_bytes == 0 or source.data.size() % source_frame_bytes != 0:
		return null
	var frame_count := source.data.size() / source_frame_bytes
	var output := PackedByteArray()
	output.resize(frame_count * sample_bytes * 2)
	if sample_bytes == 1:
		output.fill(128)
	else:
		output.fill(0)
	var source_data := source.data
	for frame in range(frame_count):
		var source_channel := lane if source.stereo else 0
		var source_offset := frame * source_frame_bytes + source_channel * sample_bytes
		var output_offset := frame * sample_bytes * 2 + lane * sample_bytes
		for byte_index in range(sample_bytes):
			output[output_offset + byte_index] = source_data[source_offset + byte_index]
	result.data = output
	result.stereo = true
	return result


func play_audio_stream(stream: AudioStreamWAV, name: String, channel_hint: String = "", start_frame: int = 0, repeat: bool = false, channel_default_loop: bool = true, end_frame: int = -1, rewind_frame: int = -1, play_type: int = -2, resource_volume: float = 1.0, resource_volume_right: float = -1.0) -> bool:
	if stream == null:
		_audio_error("音频流为空: %s" % name)
		return false
	var channel := channel_hint.strip_edges().to_lower() if not channel_hint.strip_edges().is_empty() else resolve_audio_channel(name)
	if channel.is_empty():
		_audio_error("无法确定音频资源的播放声道: %s" % name)
		return false
	var player := _audio_player_for_channel(channel)
	var right_player := _right_audio_player_for_channel(channel)
	if player == null:
		_audio_error("音频声道尚未初始化: %s" % channel)
		return false
	if channel == "voice" and _voice_is_muted(name):
		return false
	# Entis uses PCM frames, while AudioStreamPlayer.play takes seconds.
	var bytes_per_frame := (2 if stream.stereo else 1) * (2 if stream.format == AudioStreamWAV.FORMAT_16_BITS else 1)
	if stream.format not in [AudioStreamWAV.FORMAT_8_BITS, AudioStreamWAV.FORMAT_16_BITS] or stream.mix_rate <= 0:
		_audio_error("音频区间需要 PCM 数据: %s" % name)
		return false
	var pcm := stream.data
	@warning_ignore("integer_division")
	var frame_count := pcm.size() / bytes_per_frame
	var end := frame_count if end_frame == -1 else end_frame
	var rewind := start_frame if rewind_frame == -1 else rewind_frame
	var should_loop := repeat or (channel_default_loop and channel in ["bgm", "env_se"])
	var left_volume := clampf(resource_volume, 0.0, 1.0)
	var right_volume := left_volume if resource_volume_right < 0.0 else clampf(resource_volume_right, 0.0, 1.0)
	var use_dual_channels := not is_equal_approx(left_volume, right_volume)
	if use_dual_channels and right_player == null:
		_audio_error("左右声道音量不同时需要双路音频播放器: %s" % name)
		return false
	if start_frame < 0 or start_frame >= end or end > frame_count or (should_loop and (rewind < 0 or rewind >= end)):
		_audio_error("无效的音频采样帧区间: %s (start=%d, end=%d, rewind=%d, frames=%d)" % [name, start_frame, end, rewind, frame_count])
		return false

	# Keep cached PCM untouched. WAV loop markers only take effect in loop mode.
	var playback_stream := stream.duplicate() as AudioStreamWAV
	if should_loop:
		playback_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		playback_stream.loop_begin = rewind
		playback_stream.loop_end = end
	else:
		playback_stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
		if end < frame_count:
			playback_stream.data = pcm.slice(0, end * bytes_per_frame)
	if use_dual_channels:
		var left_stream := _make_audio_lane_stream(playback_stream, 0)
		var right_stream := _make_audio_lane_stream(playback_stream, 1)
		if left_stream == null or right_stream == null:
			_audio_error("无法拆分左右声道音频流: %s" % name)
			return false
		player.stream = left_stream
		right_player.stream = right_stream
	else:
		player.stream = playback_stream
		if right_player != null:
			right_player.stop()
			right_player.stream = null
	player.stream_paused = false
	player.set_meta("csx_audio_name", name.to_lower())
	if play_type == -2:
		play_type = _default_audio_play_type(channel)
	player.set_meta("csx_play_type", play_type)
	player.set_meta("csx_resource_volume", left_volume)
	player.set_meta("csx_resource_volume_left", left_volume)
	player.set_meta("csx_resource_volume_right", right_volume)
	player.set_meta("csx_dual_channel", use_dual_channels)
	if use_dual_channels:
		right_player.stream_paused = false
		right_player.set_meta("csx_audio_name", name.to_lower())
		right_player.set_meta("csx_play_type", play_type)
		right_player.set_meta("csx_resource_volume", right_volume)
		right_player.set_meta("csx_resource_volume_left", left_volume)
		right_player.set_meta("csx_resource_volume_right", right_volume)
		right_player.set_meta("csx_dual_channel", true)
	if not set_resource_audio_volume(channel, left_volume, right_volume, play_type, name):
		return false
	player.play(float(start_frame) / stream.mix_rate)
	if use_dual_channels:
		right_player.play(float(start_frame) / stream.mix_rate)
	match channel:
		"bgm":
			current_bgm = name
			emit_signal("bgm_updated", name)
		"env_se": current_env_se = name
		"voice": current_voice = name
	last_error = ""
	print("[CSX Host] Playing %s: %s" % [channel, name])
	return true


func _audio_error(message: String) -> void:
	last_error = message
	push_warning(message)


func _voice_is_muted(name: String) -> bool:
	var char_key := _voice_character_key(name)
	return bool(voice_char_mutes.get(char_key, false))


func _voice_character_key(name: String) -> String:
	var prefix := name.get_file().substr(0, mini(2, name.get_file().length())).to_upper()
	match prefix:
		"SR", "SO": return "ID_SORA"
		"AK": return "ID_AKIRA"
		"NO", "NA": return "ID_NAO"
		"KA": return "ID_KAZUHA"
		"MT", "MO": return "ID_MOTOKA"
		"KO": return "ID_KOZUE"
		"YH", "YA": return "ID_YAHIRO"
		"RH", "RY": return "ID_RYOUHEI"
		_: return "ID_OTHER"


func play_bgm(name: String) -> void:
	_play_named_audio(name, "bgm")


func stop_bgm() -> void:
	current_bgm = ""
	_stop_channel_players("bgm")
	print("[CSX Host] Stopped BGM")


func play_env_se(name: String) -> void:
	_play_named_audio(name, "env_se")


func stop_env_se() -> void:
	current_env_se = ""
	_stop_channel_players("env_se")
	print("[CSX Host] Stopped EnvSE")


func play_se(name: String) -> void:
	_play_named_audio(name, "se")


func stop_se() -> void:
	_stop_channel_players("se")


func play_voice(name: String) -> void:
	if _voice_is_muted(name):
		return
	_play_named_audio(name, "voice")


func _play_named_audio(name: String, channel: String) -> bool:
	var res := load_sound(name)
	if not res.get("ok", false):
		_audio_error(str(res.get("error", "无法加载音频资源: %s" % name)))
		return false
	return play_audio_stream(res.get("stream"), name, channel)


func stop_voice() -> void:
	current_voice = ""
	_stop_channel_players("voice")


func _stop_channel_players(channel: String) -> void:
	var player := _audio_player_for_channel(channel)
	var right_player := _right_audio_player_for_channel(channel)
	if player != null:
		player.stop()
		player.stream_paused = false
		player.set_meta("csx_dual_channel", false)
	if right_player != null:
		right_player.stop()
		right_player.stream = null
		right_player.stream_paused = false
		right_player.set_meta("csx_dual_channel", false)


func stop_audio(name: String, channel_hint: String = "") -> bool:
	var channel := channel_hint.strip_edges().to_lower() if not channel_hint.strip_edges().is_empty() else resolve_audio_channel(name)
	var player := _audio_player_for_channel(channel)
	if player == null:
		_audio_error("无法停止未知音频声道 '%s' (resource: %s)" % [channel, name])
		return false
	player.stop()
	player.stream_paused = false
	player.set_meta("csx_play_type", AUDIO_PLAY_TYPE_NONE)
	var right_player := _right_audio_player_for_channel(channel)
	if right_player != null:
		right_player.stop()
		right_player.stream = null
		right_player.stream_paused = false
		right_player.set_meta("csx_play_type", AUDIO_PLAY_TYPE_NONE)
		player.set_meta("csx_dual_channel", false)
	match channel:
		"bgm":
			current_bgm = ""
			emit_signal("bgm_updated", "")
		"env_se": current_env_se = ""
		"voice": current_voice = ""
	return true


func pause_audio(name: String, channel_hint: String = "") -> bool:
	var channel := channel_hint.strip_edges().to_lower() if not channel_hint.strip_edges().is_empty() else resolve_audio_channel(name)
	var player := _audio_player_for_channel(channel)
	if player == null or not player.playing or player.get_meta("csx_audio_name", "") != name.to_lower():
		last_error = "无法暂停当前未播放的音频声道: %s (%s)" % [channel, name]
		return false
	player.stream_paused = true
	var right_player := _right_audio_player_for_channel(channel)
	if right_player != null and bool(player.get_meta("csx_dual_channel", false)):
		right_player.stream_paused = true
	return true


func resume_audio(name: String, channel_hint: String = "") -> bool:
	var channel := channel_hint.strip_edges().to_lower() if not channel_hint.strip_edges().is_empty() else resolve_audio_channel(name)
	var player := _audio_player_for_channel(channel)
	if player == null or player.stream == null or player.get_meta("csx_audio_name", "") != name.to_lower():
		last_error = "无法恢复未初始化的音频声道: %s (%s)" % [channel, name]
		return false
	if player.stream_paused:
		player.stream_paused = false
		var right_player := _right_audio_player_for_channel(channel)
		if right_player != null and bool(player.get_meta("csx_dual_channel", false)):
			right_player.stream_paused = false
		return true
	return false


func get_audio_position_frames(name: String, channel_hint: String = "") -> int:
	var channel := channel_hint.strip_edges().to_lower() if not channel_hint.strip_edges().is_empty() else resolve_audio_channel(name)
	var player := _audio_player_for_channel(channel)
	if player == null or not player.playing or not player.stream is AudioStreamWAV or player.get_meta("csx_audio_name", "") != name.to_lower():
		return -1
	return roundi(player.get_playback_position() * player.stream.mix_rate)


func set_audio_channel_volume(channel: String, linear_volume: float) -> bool:
	var normalized_channel := channel.strip_edges().to_lower()
	var player := _audio_player_for_channel(normalized_channel)
	if player == null:
		last_error = "音频声道尚未初始化，无法设置音量: %s" % normalized_channel
		return false
	var volume := clampf(linear_volume, 0.0, 1.0)
	_set_audio_player_volume(player, volume)
	var right_player := _right_audio_player_for_channel(normalized_channel)
	if right_player != null and bool(player.get_meta("csx_dual_channel", false)):
		_set_audio_player_volume(right_player, volume)
	return true


func is_valid_audio_play_type(play_type: int) -> bool:
	return play_type in [AUDIO_PLAY_TYPE_DEVICE, AUDIO_PLAY_TYPE_NONE, AUDIO_PLAY_TYPE_MUSIC, AUDIO_PLAY_TYPE_SOUND, AUDIO_PLAY_TYPE_VOICE, AUDIO_PLAY_TYPE_SYSTEM]


func _default_audio_play_type(channel: String) -> int:
	match channel:
		"bgm": return AUDIO_PLAY_TYPE_MUSIC
		"env_se", "se": return AUDIO_PLAY_TYPE_SOUND
		"voice": return AUDIO_PLAY_TYPE_VOICE
		"system": return AUDIO_PLAY_TYPE_SYSTEM
		_: return AUDIO_PLAY_TYPE_NONE


func set_resource_audio_volume(channel: String, resource_volume: float, resource_volume_right: float = -1.0, play_type: int = -2, resource_name: String = "") -> bool:
	if play_type == -2:
		play_type = _default_audio_play_type(channel)
	var factor := float(audio_total_volumes.get(play_type, 1.0)) if play_type in [0, 1, 2, 3] else 1.0
	var player := _audio_player_for_channel(channel)
	if player == null:
		return false
	if not resource_name.is_empty() and str(player.get_meta("csx_audio_name", "")) != resource_name.to_lower():
		return true
	var left_volume := clampf(resource_volume, 0.0, 1.0)
	var right_volume := left_volume if resource_volume_right < 0.0 else clampf(resource_volume_right, 0.0, 1.0)
	if not is_equal_approx(left_volume, right_volume) and _right_audio_player_for_channel(channel) == null:
		last_error = "左右声道音量不同时需要双路音频播放器: %s" % channel
		return false
	player.set_meta("csx_resource_volume", left_volume)
	player.set_meta("csx_resource_volume_left", left_volume)
	player.set_meta("csx_resource_volume_right", right_volume)
	player.set_meta("csx_play_type", play_type)
	if not is_equal_approx(left_volume, right_volume) and player.stream != null:
		if not ensure_dual_channel_playback(channel):
			return false
	var right_player := _right_audio_player_for_channel(channel)
	if bool(player.get_meta("csx_dual_channel", false)):
		if right_player == null:
			return false
		right_player.set_meta("csx_resource_volume", right_volume)
		right_player.set_meta("csx_resource_volume_left", left_volume)
		right_player.set_meta("csx_resource_volume_right", right_volume)
		right_player.set_meta("csx_play_type", play_type)
		_set_audio_player_volume(player, left_volume * factor)
		_set_audio_player_volume(right_player, right_volume * factor)
		return true
	return set_audio_channel_volume(channel, left_volume * factor)


func ensure_dual_channel_playback(channel: String) -> bool:
	var normalized_channel := channel.strip_edges().to_lower()
	var player := _audio_player_for_channel(normalized_channel)
	var right_player := _right_audio_player_for_channel(normalized_channel)
	if player == null or right_player == null:
		return false
	if bool(player.get_meta("csx_dual_channel", false)):
		return true
	if player.stream == null or not player.stream is AudioStreamWAV:
		return false
	var name := str(player.get_meta("csx_audio_name", ""))
	if name.is_empty():
		return false
	var source := player.stream as AudioStreamWAV
	var left_stream := _make_audio_lane_stream(source, 0)
	var right_stream := _make_audio_lane_stream(source, 1)
	if left_stream == null or right_stream == null:
		return false
	var was_active := player.playing or player.stream_paused
	var position := roundi(player.get_playback_position() * source.mix_rate) if was_active else 0
	var was_paused := player.stream_paused
	var play_type := int(player.get_meta("csx_play_type", _default_audio_play_type(normalized_channel)))
	var left_volume := float(player.get_meta("csx_resource_volume_left", 1.0))
	var right_volume := float(player.get_meta("csx_resource_volume_right", left_volume))
	player.stop()
	right_player.stop()
	player.stream = left_stream
	right_player.stream = right_stream
	player.set_meta("csx_dual_channel", true)
	right_player.set_meta("csx_audio_name", name)
	right_player.set_meta("csx_play_type", play_type)
	right_player.set_meta("csx_dual_channel", true)
	right_player.set_meta("csx_resource_volume_left", left_volume)
	right_player.set_meta("csx_resource_volume_right", right_volume)
	right_player.set_meta("csx_resource_volume", right_volume)
	if was_active:
		player.play(float(position) / source.mix_rate)
		right_player.play(float(position) / source.mix_rate)
		player.stream_paused = was_paused
		right_player.stream_paused = was_paused
	var factor := float(audio_total_volumes.get(play_type, 1.0)) if play_type in [0, 1, 2, 3] else 1.0
	_set_audio_player_volume(player, left_volume * factor)
	_set_audio_player_volume(right_player, right_volume * factor)
	return true


func get_audio_total_volume(play_type: int) -> float:
	if play_type == AUDIO_PLAY_TYPE_DEVICE:
		var master_bus := AudioServer.get_bus_index("Master")
		return db_to_linear(AudioServer.get_bus_volume_db(master_bus)) if master_bus >= 0 else 1.0
	if play_type in [0, 1, 2, 3]:
		return float(audio_total_volumes.get(play_type, 1.0))
	return 1.0


func set_audio_total_volume(play_type: int, linear_volume: float) -> bool:
	var volume := clampf(linear_volume, 0.0, 1.0)
	if play_type == AUDIO_PLAY_TYPE_DEVICE:
		var master_bus := AudioServer.get_bus_index("Master")
		if master_bus < 0:
			return false
		AudioServer.set_bus_volume_db(master_bus, -80.0 if volume <= 0.0001 else linear_to_db(volume))
		return true
	if play_type not in [0, 1, 2, 3]:
		return true # Entis treats unknown total-volume selectors as unity/no-op.
	audio_total_volumes[play_type] = volume
	for channel in ["bgm", "env_se", "se", "voice", "system"]:
		var player := _audio_player_for_channel(channel)
		if player != null and player.stream != null and int(player.get_meta("csx_play_type", -1)) == play_type:
			var resource_volume_left := float(player.get_meta("csx_resource_volume_left", player.get_meta("csx_resource_volume", 1.0)))
			var resource_volume_right := float(player.get_meta("csx_resource_volume_right", resource_volume_left))
			set_resource_audio_volume(channel, resource_volume_left, resource_volume_right, play_type, str(player.get_meta("csx_audio_name", "")))
	return true


func get_audio_channel_volume(channel: String) -> float:
	var player := _audio_player_for_channel(channel)
	if player == null:
		return 0.0
	return db_to_linear(player.volume_db)


func report_unsupported(capability: String) -> void:
	last_error = "当前未实现宿主能力: %s" % capability
	if not unsupported_capabilities_reported.has(capability):
		unsupported_capabilities_reported[capability] = true
		push_warning(last_error)


func call_host_function(func_name: String, args: Array, vm: RefCounted) -> Dictionary:
	match func_name:
		"GetCurrentTime":
			if auto_advance:
				virtual_time_ms += 100
				return {"handled": true, "result": virtual_time_ms}
			return {"handled": true, "result": Time.get_ticks_msec()}
		"GetLocalTime":
			var dt := Time.get_datetime_dict_from_system()
			var time_obj: Variant = null
			if vm != null and vm.has_method("create_object"):
				time_obj = vm.create_object("Time")
			if time_obj != null and time_obj.has_method("set_field"):
				time_obj.set_field("nYear", dt["year"])
				time_obj.set_field("nMonth", dt["month"])
				time_obj.set_field("nDay", dt["day"])
				time_obj.set_field("nWeek", dt["weekday"])
				time_obj.set_field("nHour", dt["hour"])
				time_obj.set_field("nMinute", dt["minute"])
				time_obj.set_field("nSecond", dt["second"])
				time_obj.set_field("nMilliSecond", Time.get_ticks_msec() % 1000)
				time_obj.set_field("nDayOfWeek", dt["weekday"])
			return {"handled": true, "result": time_obj}
		"IsHitSprite":
			if args.size() >= 3 and args[0] is HostSprite:
				var sprite := args[0] as HostSprite
				return {"handled": true, "result": -1 if sprite.is_hit_at(int(args[1]), int(args[2])) else 0}
			return {"handled": true, "result": 0}
		"IsHitRect":
			if args.size() >= 3 and args[0] != null and args[0].has_method("get_field"):
				var rect_value: Variant = args[0]
				var left := float(rect_value.get_field("left"))
				var top := float(rect_value.get_field("top"))
				var right := float(rect_value.get_field("right"))
				var bottom := float(rect_value.get_field("bottom"))
				var hit := float(args[1]) >= left and float(args[1]) < right and float(args[2]) >= top and float(args[2]) < bottom
				return {"handled": true, "result": -1 if hit else 0}
			return {"handled": true, "result": 0}
		"InitRandom":
			return {"handled": true, "result": 0}
		"Sleep":
			return {"handled": true, "result": 0}
		"Trace":
			var msg := ""
			for a in args:
				msg += str(a) + " "
			log_messages.append(msg.strip_edges())
			print("[CSX Trace] ", msg.strip_edges())
			return {"handled": true, "result": 0}
		"Debug":
			if args.size() > 0:
				var dmsg: String = str(args[0])
				log_messages.append("[Debug] " + dmsg)
				if dmsg.begins_with("CG-"):
					var cg_name := dmsg.substr(3)
					current_bg = cg_name
					var img_res := load_image(cg_name)
					if img_res.get("ok", false):
						current_bg_texture = img_res["texture"]
						emit_signal("bg_updated", current_bg, current_bg_texture)
				elif dmsg.begins_with("Tone-"):
					var tf_name := dmsg.substr(5)
					set_tone_filter(tf_name)
			return {"handled": true, "result": 0}
		"WaitUntilSpriteActive":
			return {"handled": true, "result": 0}
		"HitWait":
			return {"handled": true, "result": 0}
		"UpdateWindow", "Window::UpdateWindow":
			return {"handled": true, "result": 0}
		"IsLoad":
			return {"handled": true, "result": 0}
		"LeaveLoad":
			return {"handled": true, "result": 0}
		"Confirm":
			return {"handled": true, "result": 0}
		"ProcessUserInput":
			return {"handled": true, "result": 0}
		"PlayBgm", "RestartBgm", "ScRestartBgm", "ScPlayBgm":
			if args.size() > 0:
				play_bgm(str(args[0]))
			return {"handled": true, "result": 0}
		"StopBgm", "ScStopBgm":
			stop_bgm()
			return {"handled": true, "result": 0}
		"ScPlayEnvSe":
			if args.size() > 0:
				play_env_se(str(args[0]))
			return {"handled": true, "result": 0}
		"ScStopEnvSe":
			stop_env_se()
			return {"handled": true, "result": 0}
		"ScPlaySe", "PlaySe":
			if args.size() > 0:
				play_se(str(args[0]))
			return {"handled": true, "result": 0}
		"StopSe", "ScStopSe":
			stop_se()
			return {"handled": true, "result": 0}
		"PlayVoice", "ScPlayVoice":
			if args.size() > 0:
				play_voice(str(args[0]))
			return {"handled": true, "result": 0}
		"StopVoice", "ScStopVoice":
			stop_voice()
			return {"handled": true, "result": 0}
		"LoadObject":
			if args.size() >= 2:
				var path := str(args[0])
				var obj = args[1]
				var ok := load_object_file(path, obj, vm)
				return {"handled": true, "result": 0 if ok else 1}
			return {"handled": true, "result": 1}
		"SaveObject":
			if args.size() >= 2:
				var path := str(args[0])
				var obj = args[1]
				var ok := save_object_file(path, obj)
				return {"handled": true, "result": 0 if ok else 1}
			return {"handled": true, "result": 1}
		"IsExisting", "File::IsExisting":
			var filename: String = str(args[args.size() - 1]) if args.size() > 0 else ""
			var exists: bool = is_file_existing(filename)
			return {"handled": true, "result": -1 if exists else 0}
		_:
			return {"handled": false}


func save_thumbnail(filename: String, spr: Variant, w: int = 120, h: int = 90) -> void:
	var tp := get_thumbnail_path(filename)
	var dir := tp.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

	var img: Image = null
	if spr is HostSprite and spr.texture != null:
		img = spr.texture.get_image()
	elif spr is HostSprite and spr.image != null:
		img = spr.image
	elif current_bg_texture != null:
		img = current_bg_texture.get_image()

	if img != null:
		var copy := img.duplicate()
		copy.resize(w, h, Image.INTERPOLATE_BILINEAR)
		copy.save_png(tp)
		print("[CSX Host] Saved thumbnail to: ", tp)


func save_object_file(filename: String, obj: Variant) -> bool:
	var sp := get_save_path(filename)
	var serialization_state := {"error": "", "objects": [], "next_id": 1, "count": 0}
	var s_data = _serialize_value_checked(obj, [], 0, serialization_state)
	if not str(serialization_state.error).is_empty():
		last_error = "存档对象无法序列化: %s" % serialization_state.error
		push_error(last_error)
		return false
	var document := {
		"__yzk_save_document__": true,
		"schema_version": SAVE_SCHEMA_VERSION,
		"payload": s_data
	}
	var json_str := JSON.stringify(document)
	if json_str.to_utf8_buffer().size() > MAX_SAVE_DOCUMENT_BYTES:
		last_error = "存档超过大小上限 (%d bytes)。" % MAX_SAVE_DOCUMENT_BYTES
		push_error(last_error)
		return false
	if not write_save_atomically(sp, json_str):
		return false
	if not FileAccess.file_exists(get_thumbnail_path(filename)):
		save_thumbnail(filename, null, 120, 90)
	print("[CSX Host] Successfully saved object to: ", sp)
	return true


func write_save_atomically(save_path: String, content: String) -> bool:
	var absolute_save := ProjectSettings.globalize_path(save_path)
	var directory := absolute_save.get_base_dir()
	if not DirAccess.dir_exists_absolute(directory):
		var error := DirAccess.make_dir_recursive_absolute(directory)
		if error != OK:
			last_error = "无法创建存档目录: %s (%s)" % [directory, error_string(error)]
			push_error(last_error)
			return false
	var temporary_path := absolute_save + ".tmp"
	var backup_path := absolute_save + ".bak"
	if FileAccess.file_exists(temporary_path):
		var remove_temp_error := DirAccess.remove_absolute(temporary_path)
		if remove_temp_error != OK:
			last_error = "无法清理临时存档: %s (%s)" % [temporary_path, error_string(remove_temp_error)]
			push_error(last_error)
			return false
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		last_error = "无法创建临时存档: %s (%s)" % [temporary_path, error_string(FileAccess.get_open_error())]
		push_error(last_error)
		return false
	file.store_string(content)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary_path)
		last_error = "临时存档写入失败: %s" % error_string(write_error)
		push_error(last_error)
		return false
	var verify_file := FileAccess.open(temporary_path, FileAccess.READ)
	if verify_file == null or verify_file.get_length() != content.to_utf8_buffer().size():
		if verify_file != null:
			verify_file.close()
		DirAccess.remove_absolute(temporary_path)
		last_error = "临时存档回读长度校验失败。"
		push_error(last_error)
		return false
	var verified_text := verify_file.get_as_text()
	verify_file.close()
	var parsed := JSON.new()
	if parsed.parse(verified_text) != OK or not verified_text == content:
		DirAccess.remove_absolute(temporary_path)
		last_error = "临时存档回读 JSON 校验失败。"
		push_error(last_error)
		return false
	# Keep the current document readable until the new primary is committed.
	# If the primary is corrupt, keep the existing backup for recovery.
	if _read_save_payload(absolute_save) != null:
		var backup_temporary_path := backup_path + ".tmp"
		var backup_error := DirAccess.copy_absolute(absolute_save, backup_temporary_path)
		if backup_error == OK:
			backup_error = DirAccess.rename_absolute(backup_temporary_path, backup_path)
		if backup_error != OK:
			DirAccess.remove_absolute(backup_temporary_path)
			DirAccess.remove_absolute(temporary_path)
			last_error = "无法保留旧存档: %s (%s)" % [absolute_save, error_string(backup_error)]
			push_error(last_error)
			return false
	var commit_error := DirAccess.rename_absolute(temporary_path, absolute_save)
	if commit_error != OK:
		DirAccess.remove_absolute(temporary_path)
		last_error = "无法提交新存档: %s (%s)" % [absolute_save, error_string(commit_error)]
		push_error(last_error)
		return false
	return true


func load_object_file(filename: String, target_obj: Variant, vm: RefCounted = null) -> bool:
	var sp := get_save_path(filename)
	var snapshot := read_save_snapshot(sp)
	if snapshot.is_empty() and not FileAccess.file_exists(sp):
		for directory in [game_dir, game_dir.path_join("system")]:
			if not game_dir.is_empty():
				snapshot = read_save_snapshot(directory.path_join(filename), false)
				if not snapshot.is_empty():
					break
	if snapshot.is_empty():
		last_error = "存档不存在或内容无效: %s" % sp
		return false
	deserialize_into(target_obj, snapshot["payload"], vm, {"objects": {}})
	print("[CSX Host] Successfully loaded object from: ", snapshot["path"])
	return true


func read_save_snapshot(path: String, allow_backup: bool = true, object_only: bool = false) -> Dictionary:
	if path.is_empty():
		return {}
	var payload: Variant = _read_save_payload(path)
	if payload != null and (not object_only or payload is Dictionary):
		return {"path": path, "payload": payload}
	if allow_backup:
		return read_save_snapshot(path + ".bak", false, object_only)
	return {}


func _read_save_payload(sp: String) -> Variant:
	var f := FileAccess.open(sp, FileAccess.READ)
	if f == null:
		return null
	if f.get_length() <= 0 or f.get_length() > MAX_SAVE_DOCUMENT_BYTES:
		f.close()
		return null
	var parser := JSON.new()
	var error := parser.parse(f.get_as_text())
	f.close()
	if error != OK:
		return null
	var parsed: Variant = parser.data
	if parsed is Dictionary and parsed.get("__yzk_save_document__", false):
		var version: Variant = parsed.get("schema_version")
		if not (version is int or version is float) or version != floor(version) or version < 1 or version > SAVE_SCHEMA_VERSION:
			return null
		parsed = parsed.get("payload")
	if not (parsed is Dictionary or parsed is Array):
		return null
	if _is_story_save(sp) and not (parsed is Dictionary and parsed.get("__type__") == "CsxInstance" and parsed.get("fields") is Dictionary):
		return null
	if not _validate_save_tree(parsed, 0, {"count": 0}):
		return null
	return parsed


func _validate_save_tree(value: Variant, depth: int, state: Dictionary) -> bool:
	if depth > MAX_SERIALIZATION_DEPTH:
		return false
	state.count = int(state.count) + 1
	if int(state.count) > 250000:
		return false
	if value is Array:
		for item in value:
			if not _validate_save_tree(item, depth + 1, state):
				return false
	elif value is Dictionary:
		if value.size() > 100000:
			return false
		for key in value.keys():
			if not _validate_save_tree(value[key], depth + 1, state):
				return false
	return true


static func serialize_value(val: Variant) -> Variant:
	var state := {"error": "", "objects": [], "next_id": 1, "count": 0}
	var result: Variant = _serialize_value_checked(val, [], 0, state)
	return null if not str(state.error).is_empty() else result


static func _serialize_value_checked(val: Variant, active_stack: Array, depth: int, state: Dictionary) -> Variant:
	if not str(state.get("error", "")).is_empty():
		return null
	if depth > MAX_SERIALIZATION_DEPTH:
		state.error = "对象嵌套深度超过 %d" % MAX_SERIALIZATION_DEPTH
		return null
	state.count = int(state.get("count", 0)) + 1
	if int(state.count) > 250000:
		state.error = "对象图节点数超过 250000"
		return null
	if val == null or val is bool or val is float or val is String:
		return val
	if val is int:
		return {"__type__": "Integer", "value": val}
	var track_identity := val is RefCounted or val is Array or val is Dictionary
	var object_id := 0
	if track_identity:
		for seen: Dictionary in state.objects:
			if is_same(seen["value"], val):
				return {"__ref__": int(seen["id"])}
		object_id = int(state.next_id)
		state.next_id = object_id + 1
		state.objects.append({"value": val, "id": object_id})
	var result: Variant = null
	if val is RefCounted:
		if val is HostSprite:
			var sprite: HostSprite = val
			result = {
				"__type__": "HostSprite",
				"__id__": object_id,
				"filename": sprite.filename,
				"archive_hint": sprite.archive_hint,
				"position": [sprite.position.x, sprite.position.y],
				"rev_center": [sprite.rev_center.x, sprite.rev_center.y],
				"magnification": [sprite.magnification.x, sprite.magnification.y],
				"rotation_degrees": sprite.rotation_degrees,
				"sprite_parameters": _serialize_value_checked(sprite.sprite_parameters, active_stack, depth + 1, state),
				"message_style": _serialize_value_checked(sprite.message_style, active_stack, depth + 1, state),
				"size": [sprite.size.x, sprite.size.y],
				"z_order": sprite.z_order,
				"is_visible": sprite.is_visible,
				"transparency": sprite.transparency,
				"back_color": sprite.back_color,
				"fill_back_color": sprite.fill_back_color,
				"btn_id": sprite.btn_id,
				"is_button": sprite.is_button,
				"btn_state": sprite.btn_state,
				"text_content": sprite.text_content,
				"message_char_speed_ms": sprite.message_char_speed_ms,
				"message_fade_ms": sprite.message_fade_ms,
				"message_elapsed_ms": sprite.message_elapsed_ms,
				"message_visible_count": sprite.message_visible_count,
				"message_pending": sprite.message_pending,
				"fields": _serialize_value_checked(sprite.fields, active_stack, depth + 1, state)
			}
		elif val is HostResource:
			var resource: HostResource = val
			result = {
				"__type__": "HostResource",
				"__id__": object_id,
				"name": resource.name,
				"archive_name": resource.archive_name,
				"entry_index": resource.entry_index,
				"unpacked_size": resource.unpacked_size,
				"payload_offset": resource.payload_offset,
				"is_playing": resource.is_playing,
				"position_frames": resource.get_playing_position(),
				"playback_end_frame": resource.playback_end_frame,
				"playback_rewind_frame": resource.playback_rewind_frame,
				"is_repeating": resource.is_repeating,
				"use_channel_default_loop": resource.use_channel_default_loop,
				"volume_left": resource.volume_left,
				"volume_right": resource.volume_right,
				"fields": _serialize_value_checked(resource.fields, active_stack, depth + 1, state)
			}
		elif val.get_script() != null and val.get("type_name") != null and val.get("fields") is Dictionary:
			var serialized_fields: Dictionary = {}
			for key in val.fields.keys():
				serialized_fields[str(key)] = _serialize_value_checked(val.fields[key], active_stack, depth + 1, state)
			result = {"__type__": "CsxInstance", "__id__": object_id, "class_name": val.type_name, "fields": serialized_fields}
		else:
			state.error = "不支持的对象类型 %s" % val.get_class()
	elif val is Array:
		var serialized_array: Array = []
		for item in val:
			serialized_array.append(_serialize_value_checked(item, active_stack, depth + 1, state))
		result = {"__type__": "Array", "__id__": object_id, "items": serialized_array}
	elif val is Dictionary:
		var serialized_dictionary: Dictionary = {}
		for key in val.keys():
			serialized_dictionary[str(key)] = _serialize_value_checked(val[key], active_stack, depth + 1, state)
		result = {"__type__": "Dictionary", "__id__": object_id, "items": serialized_dictionary}
	else:
		state.error = "不支持的 Variant 类型 %s" % type_string(typeof(val))
	return result


static func deserialize_into(target: Variant, data: Variant, vm: RefCounted = null, context: Dictionary = {}) -> Variant:
	if data == null:
		return null
	if not context.has("objects"):
		context.objects = {}
	if data is Dictionary and data.has("__ref__"):
		return context.objects.get(str(data["__ref__"]), null)
	if data is Dictionary and data.has("__type__"):
		var t_type: String = data["__type__"]
		if t_type == "Integer":
			return int(data.get("value", 0))
		if t_type == "CsxInstance":
			var cname: String = data.get("class_name", "")
			var fields_data: Dictionary = data.get("fields", {})
			var inst = target
			if not (inst != null and inst.get_script() != null and inst.get("type_name") != null):
				if vm != null and vm.has_method("create_object"):
					inst = vm.create_object(cname)
				if inst == null:
					var CsxVMClass = load("res://scripts/csx_vm.gd")
					inst = CsxVMClass.CsxInstance.new(cname)
			if data.has("__id__"):
				context.objects[str(data["__id__"])] = inst
			inst.fields.clear()
			for k in fields_data.keys():
				inst.fields[k] = deserialize_value(fields_data[k], vm, context)
			return inst
		elif t_type == "HostSprite":
			var sprite: HostSprite = target if target is HostSprite else HostSprite.new(0, _host_from_vm(vm))
			if data.has("__id__"):
				context.objects[str(data["__id__"])] = sprite
			sprite.filename = str(data.get("filename", ""))
			sprite.archive_hint = str(data.get("archive_hint", ""))
			var pos: Array = data.get("position", [0, 0])
			sprite.position = Vector2i(int(pos[0]), int(pos[1])) if pos.size() >= 2 else Vector2i.ZERO
			var center: Array = data.get("rev_center", [0, 0])
			sprite.rev_center = Vector2i(int(center[0]), int(center[1])) if center.size() >= 2 else Vector2i.ZERO
			var magnification: Array = data.get("magnification", [1.0, 1.0])
			sprite.magnification = Vector2(float(magnification[0]), float(magnification[1])) if magnification.size() >= 2 else Vector2.ONE
			sprite.rotation_degrees = float(data.get("rotation_degrees", 0.0))
			if data.has("sprite_parameters"):
				var saved_parameters: Variant = deserialize_value(data["sprite_parameters"], vm, context)
				if saved_parameters is Dictionary:
					sprite.sprite_parameters.merge(saved_parameters, true)
			if data.has("message_style"):
				var style = deserialize_value(data["message_style"], vm, context)
				if style is Dictionary:
					sprite.message_style = style
			var sprite_size: Array = data.get("size", [0, 0])
			sprite.size = Vector2i(int(sprite_size[0]), int(sprite_size[1])) if sprite_size.size() >= 2 else Vector2i.ZERO
			sprite.z_order = int(data.get("z_order", 0))
			sprite.is_visible = bool(data.get("is_visible", false))
			sprite.transparency = int(data.get("transparency", 0))
			sprite.back_color = int(data.get("back_color", 0)) & 0xffffff
			sprite.fill_back_color = bool(data.get("fill_back_color", true))
			sprite.btn_id = str(data.get("btn_id", ""))
			sprite.is_button = bool(data.get("is_button", false))
			sprite.btn_state = str(data.get("btn_state", "normal"))
			sprite.text_content = str(data.get("text_content", ""))
			sprite.message_char_speed_ms = maxi(0, int(data.get("message_char_speed_ms", 0)))
			sprite.message_fade_ms = maxi(0, int(data.get("message_fade_ms", 0)))
			sprite.message_elapsed_ms = maxf(0.0, float(data.get("message_elapsed_ms", 0.0)))
			sprite.message_visible_count = clampi(int(data.get("message_visible_count", sprite.display_text().length())), -1, sprite.display_text().length())
			sprite.message_pending = bool(data.get("message_pending", false))
			if sprite.message_pending and sprite.host != null:
				sprite.host.active_messages[sprite.get_instance_id()] = weakref(sprite)
			sprite.fields = deserialize_value(data.get("fields", {}), vm, context) if data.get("fields", {}) is Dictionary else {}
			if not sprite.filename.is_empty() and sprite.host != null and sprite.filename.get_extension().to_lower() == "eri":
				var image_res := sprite.host.load_image(sprite.filename, sprite.archive_hint)
				if image_res.get("ok", false):
					sprite.image = image_res["image"]
					sprite.texture = image_res["texture"]
			return sprite
		elif t_type == "HostResource":
			var resource_host := _host_from_vm(vm)
			var resource: HostResource = target if target is HostResource else HostResource.new(
				str(data.get("name", "")),
				str(data.get("archive_name", "")),
				int(data.get("entry_index", -1)),
				int(data.get("unpacked_size", 0)),
				int(data.get("payload_offset", 0)),
				resource_host
			)
			resource.host = resource_host if resource_host != null else resource.host
			if data.has("__id__"):
				context.objects[str(data["__id__"])] = resource
			resource.name = str(data.get("name", ""))
			resource.archive_name = str(data.get("archive_name", ""))
			resource.entry_index = int(data.get("entry_index", -1))
			resource.unpacked_size = int(data.get("unpacked_size", 0))
			resource.payload_offset = int(data.get("payload_offset", 0))
			resource.is_playing = bool(data.get("is_playing", false))
			resource.current_position = int(data.get("position_frames", 0))
			resource.playback_end_frame = int(data.get("playback_end_frame", -1))
			resource.playback_rewind_frame = int(data.get("playback_rewind_frame", -1))
			resource.is_repeating = bool(data.get("is_repeating", false))
			resource.use_channel_default_loop = bool(data.get("use_channel_default_loop", false))
			resource.volume_left = clampf(float(data.get("volume_left", 1.0)), 0.0, 1.0)
			resource.volume_right = clampf(float(data.get("volume_right", 1.0)), 0.0, 1.0)
			resource.fields = deserialize_value(data.get("fields", {}), vm, context) if data.get("fields", {}) is Dictionary else {}
			if resource_host != null:
				var extension := resource.name.get_extension().to_lower()
				if extension == "mio":
					resource.load_sound(resource.name)
					if not data.has("position_frames") and resource.audio_stream != null:
						var legacy_msec := float(data.get("current_position", 0))
						resource.current_position = roundi(legacy_msec * resource.audio_stream.mix_rate / 1000.0)
				elif extension == "eri":
					resource.load_image(resource.name)
			return resource
		elif t_type == "Array":
			var array_value: Array = []
			if data.has("__id__"):
				context.objects[str(data["__id__"])] = array_value
			for item in data.get("items", []):
				array_value.append(deserialize_value(item, vm, context))
			return array_value
		elif t_type == "Dictionary":
			var dictionary_value: Dictionary = {}
			if data.has("__id__"):
				context.objects[str(data["__id__"])] = dictionary_value
			var items: Variant = data.get("items", {})
			if items is Dictionary:
				for key in items.keys():
					dictionary_value[key] = deserialize_value(items[key], vm, context)
			return dictionary_value
	elif data is Array:
		var arr: Array = target if (target is Array) else []
		arr.clear()
		for i in range(data.size()):
			arr.append(deserialize_value(data[i], vm, context))
		return arr
	elif data is Dictionary:
		var dict: Dictionary = target if (target is Dictionary) else {}
		dict.clear()
		for k in data.keys():
			dict[k] = deserialize_value(data[k], vm, context)
		return dict
	return data


static func deserialize_value(data: Variant, vm: RefCounted = null, context: Dictionary = {}) -> Variant:
	if data is Dictionary and data.has("__type__"):
		return deserialize_into(null, data, vm, context)
	elif data is Dictionary and data.has("__ref__"):
		return deserialize_into(null, data, vm, context)
	elif data is Array:
		var arr := []
		for it in data:
			arr.append(deserialize_value(it, vm, context))
		return arr
	elif data is Dictionary:
		var dict := {}
		for k in data.keys():
			dict[k] = deserialize_value(data[k], vm, context)
		return dict
	return data


static func _host_from_vm(vm: RefCounted) -> CsxHost:
	if vm == null:
		return null
	var candidate: Variant = vm.get("host")
	return candidate if candidate is CsxHost else null



func record_dialogue(speaker: String, text: String, voice: String = "") -> void:
	var entry := {
		"speaker": speaker,
		"text": text,
		"voice": voice,
		"bg": current_bg
	}
	text_history.append(entry)
	current_speaker = speaker
	current_dialogue = text
	current_voice = voice
	if not voice.is_empty():
		play_voice(voice)
	emit_signal("dialogue_updated", entry)
	print("[CSX Dialogue] [%s] %s%s" % [speaker, text, (" (voice: %s)" % voice) if not voice.is_empty() else ""])


func record_choices(items: Array) -> void:
	current_choices.clear()
	for it in items:
		current_choices.append(str(it))
	emit_signal("choices_updated", current_choices)
	print("[CSX Host] Choices presented: %s" % str(current_choices))
