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
signal movie_requested(movie_file: String, play_mode: int, rewind_frame: int, end_frame: int, repeat: bool, movie_instance_id: int)
signal movie_loop_portion_requested(rewind_frame: int, end_frame: int, repeat: bool, movie_instance_id: int)
signal movie_open_requested(movie_file: String)
signal movie_stop_requested
signal movie_close_requested
signal movie_seek_requested(frame_index: int)
signal tone_filter_updated(filter_type: String)
signal confirmation_requested(prompt: String)

const NoaArchiveReader = preload("res://scripts/noa_archive.gd")
const EriDecoder = preload("res://scripts/eri_decoder.gd")
const MioDecoder = preload("res://scripts/mio_decoder.gd")
const Cp932Decoder = preload("res://scripts/cp932_decoder.gd")
const BoundedFileReader = preload("res://scripts/bounded_file_reader.gd")
const HostCommandQueueClass = preload("res://scripts/host_command_queue.gd")
const MAX_INPUT_CONFIG_BYTES := 4 * 1024 * 1024
const MAX_TONE_FILTER_BYTES := 32 * 1024 * 1024
const MAX_THUMBNAIL_BYTES := 16 * 1024 * 1024
const MAX_THUMBNAIL_DIMENSION := 4096
const MAX_THUMBNAIL_PIXELS := 4 * 1024 * 1024
const DEFAULT_CACHED_MEDIA_BUDGET_BYTES := 192 * 1024 * 1024

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
var cached_media_budget_bytes := DEFAULT_CACHED_MEDIA_BUDGET_BYTES

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
var native_command_dispatch_windows: Dictionary[int, bool] = {}
var yield_for_sprite_activation: bool = false
var is_movie_playing: bool = false
var movie_current_frame: int = -1
var movie_total_frames: int = 0
var movie_stored_frame_count: int = 0
var movie_total_time_ms: int = 0
var movie_opened: bool = false
var active_movie_instance_id: int = -1
var movie_owner_instance_id: int = -1
var movie_owner_ref: WeakRef = null
var movie_resource_request_instance_id: int = -1
var movie_play_result: bool = false
var movie_seek_result: bool = false
var current_tone_filter: String = "NORMAL"
var _command_events = HostCommandQueueClass.new()
var command_overflow_count: int = 0
var command_overflow_reported: bool = false
var virtual_time_ms: int = 1000
var cursor_position_provider: Callable = Callable()
var command_cursor_override: Vector2i = Vector2i.ZERO
var command_cursor_override_valid: bool = false
var pending_confirmation_vm: WeakRef = null
var pending_confirmation_active: bool = false
var pending_confirmation_prompt: String = ""
var command_cursor_override_expires_usec: int = 0
var active_input_filter_ref: WeakRef = null
var active_sprites: Dictionary[int, WeakRef] = {}
var active_messages: Dictionary[int, WeakRef] = {}
var active_effect_sprites: Dictionary[int, WeakRef] = {}
var active_animated_sprites: Dictionary[int, WeakRef] = {}
# EntisGLS initializes AnimationFlag to animeFull (Normal | Action | Effect).
var sprite_animation_flags: int = 7
var active_volume_envelopes: Dictionary[int, WeakRef] = {}
var runtime_sprites: Dictionary[int, WeakRef] = {}
var runtime_resources: Dictionary[int, WeakRef] = {}
var runtime_windows: Dictionary[int, WeakRef] = {}
var runtime_services: Dictionary[int, WeakRef] = {}
var runtime_shutdown: bool = false
var save_dir: String = "user://saves"
const SAVE_SCHEMA_VERSION := 7
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
		if host != null and not host.runtime_shutdown:
			host.runtime_resources[get_instance_id()] = weakref(self)

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
		release_image_data()
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
		if host != null and not host.runtime_shutdown:
			host.runtime_services[get_instance_id()] = weakref(self)

	func load_input_filter(filename: String) -> int:
		filter_file = filename
		input_assignments.clear()
		if host == null:
			return 0
		var input_bytes := PackedByteArray()
		var path := host.game_dir.path_join("system").path_join(filename)
		if FileAccess.file_exists(path):
			var file_result: Dictionary = BoundedFileReader.read(path, MAX_INPUT_CONFIG_BYTES)
			if not file_result.get("ok", false):
				host.last_error = str(file_result.get("error", "无法读取输入过滤器。"))
				return 0
			input_bytes = file_result.get("data", PackedByteArray())
		else:
			var entry := host.read_vfs_entry("system/".path_join(filename))
			if not entry.get("ok", false):
				entry = host.read_vfs_entry(filename)
			if entry.get("ok", false):
				input_bytes = entry.get("data", PackedByteArray())
		if input_bytes.size() > MAX_INPUT_CONFIG_BYTES:
			host.last_error = "输入过滤器超过读取上限 (%d bytes)。" % MAX_INPUT_CONFIG_BYTES
			return 0
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
		if host != null:
			host.active_input_filter_ref = weakref(self)
		return 0

	func close_filter() -> int:
		is_open = false
		if (host != null and host.active_input_filter_ref != null
			and host.active_input_filter_ref.get_ref() == self):
			host.active_input_filter_ref = null
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

	func _native_dispatch_window_id() -> int:
		var target_window: Variant = window_ref
		if target_window is WeakRef:
			target_window = target_window.get_ref()
		if target_window is Object and is_instance_valid(target_window) and target_window.has_method("get_command"):
			return target_window.get_instance_id()
		return -1

	func get_joy_button_pushed(key: int, _dev: int = 0, during_activation: bool = false, window_id: int = -1) -> int:
		if host != null:
			var dispatch_window_id := window_id if window_id != -1 else _native_dispatch_window_id()
			var host_result := host.poll_advance_button(key, during_activation, dispatch_window_id)
			if host_result != 0:
				joy_buttons[key] = _is_button_pressed(key)
				return host_result
		var pressed := _is_button_pressed(key)
		var was_pressed := bool(joy_buttons.get(key, false))
		joy_buttons[key] = pressed
		# Entis exposes a press count here, not a CSX Boolean. Original code
		# compares GetJoyButtonPushed(...) > 0, so a pressed edge must be positive.
		return 1 if pressed and not was_pressed else 0

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
		if host != null and not host.runtime_shutdown:
			host.runtime_services[get_instance_id()] = weakref(self)
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
			var file_result: Dictionary = BoundedFileReader.read(local_path, MAX_TONE_FILTER_BYTES)
			if not file_result.get("ok", false):
				host.last_error = str(file_result.get("error", "无法读取 tone filter。"))
				return 0
			data = file_result.get("data", PackedByteArray())
		else:
			var entry := host.read_vfs_entry("system/".path_join(filename))
			if not entry.get("ok", false):
				entry = host.read_vfs_entry(filename)
			if entry.get("ok", false):
				data = entry.get("data", PackedByteArray())
		if data.size() > MAX_TONE_FILTER_BYTES:
			host.last_error = "Tone filter 超过读取上限 (%d bytes)。" % MAX_TONE_FILTER_BYTES
			return 0
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
		if host != null and not host.runtime_shutdown:
			host.runtime_services[get_instance_id()] = weakref(self)

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

	func _skin_image_descriptor(spec: String) -> Dictionary:
		if spec.is_empty():
			return {}
		var resource_id := spec
		var crop := [0, 0, 0, 0]
		var rect_pos := spec.find(":RECT(")
		if rect_pos != -1:
			resource_id = spec.substr(0, rect_pos)
			var parts := spec.substr(rect_pos + 6).trim_suffix(")").split(",")
			if parts.size() >= 4:
				crop = [int(parts[0]), int(parts[1]), int(parts[2]), int(parts[3])]
		var src_file: String = skin_resources.get(resource_id, "")
		if src_file.is_empty():
			src_file = resource_id.trim_prefix("ID_")
			if not src_file.get_extension().to_lower() == "eri":
				src_file += ".eri"
		return {"filename": src_file, "archive_hint": loaded_archive_name, "crop": crop}

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
			btn_spr.button_image_sources = {
				"normal": _skin_image_descriptor(str(style.get("normal", ""))),
				"focus": _skin_image_descriptor(str(style.get("focus", ""))),
				"pushed": _skin_image_descriptor(str(style.get("pushed", ""))),
				"disabled": _skin_image_descriptor(str(style.get("disabled", "")))
			}

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

		if page_id in ["ID_PAGE_LOAD", "ID_PAGE_SAVE"] and not _create_save_slot_pages(parent_sprite):
			return 0
		parent_sprite.refresh_command_ids()

		return 1

	func _create_save_slot_pages(parent_sprite: HostSprite) -> bool:
		if not skin_pages.has("ID_PAGE_SAVE_INDEX"):
			if host != null:
				host.last_error = "frame.noa 缺少存档卡片模板 ID_PAGE_SAVE_INDEX。"
			return false
		for slot_index in range(1, 10):
			var slot_page := HostSprite.new(0, host)
			slot_page.fields["form_item_id"] = "ID_SELECT%02d" % slot_index
			slot_page.position = Vector2i(87 + ((slot_index - 1) % 3) * 224, 31 + int((slot_index - 1) / 3) * 174)
			slot_page.is_visible = true
			if create_form_page(slot_page, "ID_PAGE_SAVE_INDEX") != 1:
				return false
			parent_sprite.add_sprite(10 + slot_index, slot_page)
		return true

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
	var movie_rewind_frame: int = -1
	var movie_end_frame: int = -1
	var movie_repeat: bool = false
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
	var animation_frame_sizes: Array[Vector2i] = []
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
	var button_image_sources: Dictionary = {}
	var is_activating: bool = false
	var activation_duration_ms: float = 0.0
	var activation_elapsed_ms: float = 0.0
	var activation_start_alpha: int = 0
	var activation_end_alpha: int = 0
	var activation_target_alpha: int = 0
	var activation_fade_enabled: bool = false
	var activation_action_type: int = 0
	var activation_durations: Array[float] = []
	var children: Array = []
	var _parent_sprite_ref: WeakRef = null
	var parent_sprite: HostSprite:
		get:
			return _parent_sprite_ref.get_ref() as HostSprite if _parent_sprite_ref != null else null
		set(value):
			_parent_sprite_ref = weakref(value) if value != null else null
	var _root_window_ref: WeakRef = null
	var root_window: Variant:
		get:
			return _root_window_ref.get_ref() if _root_window_ref != null else null
		set(value):
			_root_window_ref = weakref(value) if value != null else null
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
	var has_window_focus: bool = false
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
		if host != null and not host.runtime_shutdown:
			host.runtime_sprites[get_instance_id()] = weakref(self)

	func _release_owned_movie() -> void:
		if host == null or host.movie_owner_instance_id != get_instance_id():
			return
		host.movie_resource_request_instance_id = get_instance_id()
		host.emit_signal("movie_stop_requested")
		host.emit_signal("movie_close_requested")
		host.is_movie_playing = false
		host.movie_opened = false
		host.active_movie_instance_id = -1
		host.movie_owner_instance_id = -1
		host.movie_owner_ref = null
		host.movie_current_frame = -1
		host.movie_total_frames = 0
		host.movie_stored_frame_count = 0
		host.movie_total_time_ms = 0

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
		var target := find_sprite_item(item_id)
		if target != null:
			target.is_enabled = enabled
		return 0

	func is_enabled_native(item_id: String = "") -> bool:
		if item_id.is_empty():
			return is_enabled
		var target := find_sprite_item(item_id)
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
				animation_frame_sizes.clear()
				for frame: Image in animation_frames:
					animation_frame_sizes.append(Vector2i(frame.get_size()))
				animation_sequence = res.get("frame_sequence", []).duplicate()
				animation_total_time_ms = int(res.get("total_time_ms", 0))
				if animation_sequence.is_empty():
					for frame_index in animation_frames.size():
						animation_sequence.append(frame_index)
				size = Vector2i(image.get_width(), image.get_height())
				is_visible = true
				if not bool(res.get("is_save_thumbnail", false)) and (host.current_bg.is_empty() or filename.begins_with("B") or filename.begins_with("EA")):
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
				animation_frame_sizes.clear()
				for frame: Image in animation_frames:
					animation_frame_sizes.append(Vector2i(frame.get_size()))
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
		_divide_activation()
		activation_target_alpha = b
		activation_fade_enabled = true
		if is_activating:
			activation_start_alpha = get_blend_degree()
			activation_end_alpha = clampi(b, 0, 256)

	func _divide_activation() -> void:
		if not is_activating or activation_action_type != 0 or activation_elapsed_ms <= 0.0 or activation_duration_ms <= 0.0:
			return
		var progress := clampf(activation_elapsed_ms / activation_duration_ms, 0.0, 1.0)
		for index in activation_curves.size():
			var points: Array = activation_curves[index]
			if points.size() < 4:
				continue
			@warning_ignore("integer_division")
			var segments: int = (points.size() - 1) / 3
			var segment := maxi(0, mini(segments - 1, ceili(progress * segments) - 1))
			var t := progress * segments - segment
			var base := segment * 3
			var p: Variant = points[base] * (1.0 - t) + points[base + 1] * t
			var q: Variant = points[base + 1] * (1.0 - t) + points[base + 2] * t
			var r: Variant = points[base + 2] * (1.0 - t) + points[base + 3] * t
			var s: Variant = p * (1.0 - t) + q * t
			var u: Variant = q * (1.0 - t) + r * t
			var remaining: Array = [s * (1.0 - t) + u * t, u, r]
			remaining.append_array(points.slice(base + 3))
			activation_curves[index] = remaining
		activation_start_alpha = get_blend_degree()
		activation_elapsed_ms = 0.0

	func begin_activation(duration: Variant, action_type: int = 0) -> void:
		activation_start_alpha = get_blend_degree()
		activation_end_alpha = clampi(activation_target_alpha, 0, 256)
		activation_durations.clear()
		if duration is Array:
			for item: Variant in duration:
				activation_durations.append(maxf(0.0, float(item)))
		else:
			activation_durations.append(maxf(0.0, float(duration)))
		activation_duration_ms = 0.0
		for item: float in activation_durations:
			activation_duration_ms += item
		activation_action_type = action_type
		activation_elapsed_ms = 0.0
		is_activating = true
		_apply_activation_curves(0.0)
		if activation_duration_ms <= 0.0 or host == null:
			flush_activation()
			return
		host.active_sprites[get_instance_id()] = weakref(self)

	func advance_activation(delta_ms: float) -> void:
		activation_elapsed_ms += delta_ms
		if host != null and (host.sprite_animation_flags & 2) == 0:
			if activation_action_type == 0:
				flush_activation()
			else:
				if activation_fade_enabled:
					set_blend_degree(activation_end_alpha)
				_apply_activation_curves(1.0)
			return
		if activation_action_type == 0 and activation_elapsed_ms >= activation_duration_ms:
			flush_activation()
			return
		var local_time := activation_elapsed_ms
		if activation_action_type == 1:
			local_time = fposmod(local_time, activation_duration_ms)
		elif activation_action_type == 2:
			local_time = fposmod(local_time, activation_duration_ms * 2.0)
			if local_time > activation_duration_ms:
				local_time = activation_duration_ms * 2.0 - local_time
		var progress := 1.0
		var elapsed := local_time
		for index in activation_durations.size():
			var segment_duration := activation_durations[index]
			if segment_duration > 0.0 and elapsed < segment_duration:
				progress = (float(index) + elapsed / segment_duration) / float(activation_durations.size())
				break
			elapsed -= segment_duration
		if activation_fade_enabled:
			set_blend_degree(roundi(lerpf(activation_start_alpha, activation_end_alpha, progress)))
		_apply_activation_curves(progress)

	func _apply_activation_curves(progress: float) -> void:
		for index in [0, 1, 2]:
			var points: Array = activation_curves[index]
			if points.size() < 4:
				continue
			@warning_ignore("integer_division")
			var segments: int = (points.size() - 1) / 3
			var segment := mini(segments - 1, int(ceil(progress * segments)) - 1)
			segment = maxi(0, segment)
			var local_progress := progress * segments - segment
			var inverse := 1.0 - local_progress
			var base := segment * 3
			var value: Variant = points[base] * inverse * inverse * inverse + points[base + 1] * 3.0 * inverse * inverse * local_progress + points[base + 2] * 3.0 * inverse * local_progress * local_progress + points[base + 3] * local_progress * local_progress * local_progress
			if index == 0:
				position = Vector2i(roundi(value.x), roundi(value.y))
			elif index == 1:
				rotation_degrees = float(value)
			else:
				magnification = value

	func flush_activation() -> void:
		if activation_fade_enabled:
			set_blend_degree(activation_end_alpha if is_activating else clampi(activation_target_alpha, 0, 256))
		if is_activating:
			_apply_activation_curves(1.0)
		activation_curves = [[], [], []]
		activation_fade_enabled = false
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
		var target := find_sprite_item(item_id) if not item_id.is_empty() else self
		if target == null:
			return 0
		target.text_content = value
		target.message_visible_count = -1
		target.message_pending = false
		if host != null:
			host.active_messages.erase(target.get_instance_id())
			host.message_output.emit(target)
		return 1

	func get_sprite_text(item_id: String) -> String:
		var target := find_sprite_item(item_id) if not item_id.is_empty() else self
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
		if not is_enabled:
			return false
		var ancestor: HostSprite = self
		while ancestor != null:
			if not ancestor.is_visible or ancestor.transparency >= 256:
				return false
			ancestor = ancestor.parent_sprite
		var render_size := get_render_size()
		if render_size.x <= 0 or render_size.y <= 0:
			return false
		var local_to_host := get_sprite_to_host_transform()
		if absf(local_to_host.determinant()) <= 0.000001:
			return false
		var local_point := local_to_host.affine_inverse() * Vector2(x, y)
		return Rect2(Vector2.ZERO, Vector2(render_size)).has_point(local_point)

	func get_sprite_to_host_transform() -> Transform2D:
		var chain: Array[HostSprite] = []
		var ancestor: HostSprite = self
		while ancestor != null:
			chain.push_front(ancestor)
			ancestor = ancestor.parent_sprite
		var local_to_host := Transform2D.IDENTITY
		for sprite: HostSprite in chain:
			var sprite_transform := Transform2D(
				deg_to_rad(sprite.rotation_degrees),
				sprite.magnification,
				0.0,
				Vector2(sprite.position)
			)
			sprite_transform *= Transform2D(0.0, Vector2.ONE, 0.0, -Vector2(sprite.rev_center))
			local_to_host *= sprite_transform
		return local_to_host

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

	func get_root_window() -> Variant:
		if root_window != null:
			return root_window
		var ancestor := parent_sprite
		while ancestor != null:
			if ancestor.root_window != null:
				return ancestor.root_window
			ancestor = ancestor.parent_sprite
		return null

	func add_sprite(z: int, child: Variant) -> void:
		if child is HostSprite and child != self:
			var ancestor: HostSprite = self
			while ancestor != null:
				if ancestor == child:
					return
				ancestor = ancestor.parent_sprite
			if child.parent_sprite != null and child.parent_sprite != self:
				if child.host != null:
					child.host.flush_sprite_commands(child.get_instance_id())
				child.parent_sprite.children.erase(child)
			if child.root_window != null:
				if child.host != null:
					child.host.flush_sprite_commands(child.get_instance_id())
				child.root_window.root_sprites.erase(child)
				child.root_window = null
			child.z_order = z
			var item_id: String = child.btn_id if not child.btn_id.is_empty() else str(child.fields.get("form_item_id", ""))
			var enabled_items: Dictionary = fields.get("item_enabled_status", {})
			if not item_id.is_empty() and enabled_items.has(item_id):
				child.is_enabled = bool(enabled_items[item_id])
			if not children.has(child):
				children.append(child)
			child.parent_sprite = self
			child.refresh_command_ids()

	func find_form_item(item_id: String) -> HostSprite:
		for child in children:
			if child.btn_id == item_id or child.fields.get("form_item_id") == item_id:
				return child
		return null

	func find_sprite_item(item_path: String) -> HostSprite:
		if item_path.is_empty():
			return self
		var current: HostSprite = self
		for item_id in item_path.split("\\", false):
			current = current.find_form_item(str(item_id)) if current != null else null
			if current == null:
				return null
		return current

	func send_command(item_path: String, command_xml: String) -> int:
		var target := find_sprite_item(item_path)
		if target == null:
			return 0
		var parser := XMLParser.new()
		if parser.open_buffer(command_xml.to_utf8_buffer()) != OK:
			if host != null:
				host.report_unsupported("HostSprite.SendCommand XML")
			return 0
		var root: Dictionary = {}
		var stack: Array[Dictionary] = []
		while parser.read() == OK:
			match parser.get_node_type():
				XMLParser.NODE_ELEMENT:
					var attrs: Dictionary = {}
					for index in range(parser.get_attribute_count()):
						attrs[parser.get_attribute_name(index)] = parser.get_attribute_value(index)
					var node: Dictionary = {"tag": parser.get_node_name(), "attributes": attrs, "children": []}
					if stack.is_empty():
						root = node
					else:
						var parent: Dictionary = stack.back()
						var parent_children: Array = parent.get("children", [])
						parent_children.append(node)
						parent["children"] = parent_children
					if not parser.is_empty():
						stack.append(node)
				XMLParser.NODE_ELEMENT_END:
					if not stack.is_empty():
						stack.pop_back()
		if root.is_empty():
			return 0
		target.fields["last_command"] = command_xml
		target._apply_send_command_node(root)
		return 0

	func _apply_send_command_node(node: Dictionary) -> void:
		var tag := str(node.get("tag", ""))
		var attrs: Dictionary = node.get("attributes", {})
		var handled := true
		match tag:
			"command":
				for child: Dictionary in node.get("children", []):
					_apply_send_command_node(child)
			"basic_flag":
				for key in ["hit_transparency", "modal_first", "modal_end"]:
					if attrs.has(key):
						fields[key] = str(attrs[key]).to_lower() == "true"
			"input":
				for key in ["key", "wheel"]:
					if attrs.has(key):
						fields["input_%s_enabled" % key] = str(attrs[key]).to_lower() == "true"
			"bar":
				if fields.get("control_type", "") == "scroll_bar":
					var axis := str(fields.get("scroll_axis", "horz"))
					var range_key := "scroll_%s_range" % axis
					var position_key := "scroll_%s_pos" % axis
					if attrs.has("range"):
						fields[range_key] = maxi(0, int(str(attrs["range"])))
					if attrs.has("pos"):
						fields[position_key] = clampi(int(str(attrs["pos"])), 0, maxi(0, int(fields.get(range_key, 256))))
			"style":
				var updated_style := message_style.duplicate(true)
				for child: Dictionary in node.get("children", []):
					updated_style[str(child.get("tag", ""))] = child.get("attributes", {}).duplicate(true)
				message_style = updated_style
			"status_reflection":
				fields["button_status_reflection"] = attrs.duplicate(true)
			"status_notification":
				fields["button_status_notification"] = int(str(attrs.get("parameter", "1")))
			"right_click":
				fields["button_right_click_parameter"] = int(str(attrs.get("parameter", "2")))
			"push_repeat":
				fields["button_repeat_before_ms"] = int(str(attrs.get("before_repeat", "0")))
				fields["button_repeat_interval_ms"] = int(str(attrs.get("interval", "0")))
			_:
				handled = false
		if not handled and host != null:
			host.report_unsupported("HostSprite.SendCommand <%s>" % tag)

	func set_form_image(item_id: String, resource_id: String) -> bool:
		var item := find_sprite_item(item_id)
		return item != null and form_resources != null and form_resources._set_form_texture(item, resource_id)

	func refresh_command_ids() -> void:
		var page_id := str(fields.get("form_page_id", ""))
		if page_id == "ID_PAGE_SAVE_INDEX":
			var container_page_id := str(parent_sprite.fields.get("form_page_id", "")) if parent_sprite != null else ""
			var slot_item_id := str(fields.get("form_item_id", ""))
			if container_page_id in ["ID_PAGE_LOAD", "ID_PAGE_SAVE"] and slot_item_id.begins_with("ID_SELECT"):
				for child in children:
					if child is HostSprite and not child.btn_id.is_empty():
						child.full_btn_id = "%s\\\\%s\\\\%s" % [container_page_id, slot_item_id, child.btn_id]
				return
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
			if host != null:
				host.flush_sprite_commands(child.get_instance_id())
			children.erase(child)
			if child.parent_sprite == self:
				child.parent_sprite = null

	func detach_all_sprites() -> void:
		for child: HostSprite in children:
			if child.parent_sprite == self:
				child.parent_sprite = null
		children.clear()

	func release() -> int:
		is_activating = false
		if host != null:
			host.flush_sprite_commands(get_instance_id())
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

	func draw_image(src: Variant, param: Variant = null, frame: int = 0, clip: Variant = null) -> int:
		var src_img: Image = null
		if src is HostSprite:
			if frame == 0:
				src_img = src.image
			elif frame > 0 and frame < src.animation_frames.size():
				src_img = src.animation_frames[frame]
		elif src is HostResource:
			if not src.image_frames.is_empty() and frame >= 0 and frame < src.image_frames.size():
				src_img = src.image_frames[frame]
			elif frame == 0:
				src_img = src.image
		if src_img != null and image != null:
			var dst_pos := Vector2i.ZERO
			var center := Vector2i.ZERO
			var scale := Vector2.ONE
			var draw_transparency := 0
			var angle_degrees := 0.0
			var crossing_degrees := 90.0
			if param != null and param.has_method("get_field"):
				var pt = param.get_field("ptDstPos")
				if pt != null and pt.has_method("get_field"):
					dst_pos = Vector2i(int(pt.get_field("x")), int(pt.get_field("y")))
				var pivot = param.get_field("ptRevCenter")
				if pivot != null and pivot.has_method("get_field"):
					center = Vector2i(int(pivot.get_field("x")), int(pivot.get_field("y")))
				var horz = param.get_field("rHorzUnit")
				var vert = param.get_field("rVertUnit")
				if horz != null: scale.x = float(horz)
				if vert != null: scale.y = float(vert)
				var alpha = param.get_field("nTransparency")
				if alpha != null: draw_transparency = clampi(int(alpha), 0, 256)
				var angle = param.get_field("rRevAngle")
				var crossing = param.get_field("rCrossingAngle")
				if angle != null: angle_degrees = float(angle)
				if crossing != null: crossing_degrees = float(crossing)
			var src_rect := Rect2i(Vector2i.ZERO, src_img.get_size())
			if clip != null and clip.has_method("get_field"):
				var left := int(clip.get_field("left"))
				var top := int(clip.get_field("top"))
				var right := int(clip.get_field("right"))
				var bottom := int(clip.get_field("bottom"))
				src_rect = Rect2i(left, top, maxi(0, right - left), maxi(0, bottom - top)).intersection(src_rect)
			if is_zero_approx(scale.x) or is_zero_approx(scale.y) or src_rect.size.x <= 0 or src_rect.size.y <= 0 or draw_transparency >= 256:
				return 1
			var source_view := src_img.get_region(src_rect)
			if not is_zero_approx(fposmod(angle_degrees, 360.0)) or not is_equal_approx(crossing_degrees, 90.0):
				_draw_transformed_image(source_view, dst_pos, center, scale, angle_degrees, crossing_degrees, draw_transparency)
				texture = ImageTexture.create_from_image(image)
				return 1
			var scaled_size := Vector2i(maxi(1, roundi(src_rect.size.x * absf(scale.x))), maxi(1, roundi(src_rect.size.y * absf(scale.y))))
			if scaled_size != src_rect.size:
				source_view.resize(scaled_size.x, scaled_size.y, Image.INTERPOLATE_BILINEAR)
			if scale.x < 0.0: source_view.flip_x()
			if scale.y < 0.0: source_view.flip_y()
			if draw_transparency > 0:
				source_view.convert(Image.FORMAT_RGBA8)
				var pixels := source_view.get_data()
				for offset in range(3, pixels.size(), 4):
					pixels[offset] = (int(pixels[offset]) * (256 - draw_transparency) + 128) >> 8
				source_view.set_data(scaled_size.x, scaled_size.y, false, Image.FORMAT_RGBA8, pixels)
			var draw_origin := dst_pos - Vector2i(Vector2(center) * scale)
			if scale.x < 0.0: draw_origin.x -= scaled_size.x
			if scale.y < 0.0: draw_origin.y -= scaled_size.y
			image.blend_rect(source_view, Rect2i(Vector2i.ZERO, scaled_size), draw_origin)
			texture = ImageTexture.create_from_image(image)
			return 1
		return 0

	func _draw_transformed_image(source: Image, dst_pos: Vector2i, center: Vector2i, scale: Vector2, angle: float, crossing: float, transparency_value: int) -> void:
		var radians := deg_to_rad(angle)
		var cross_radians := deg_to_rad(angle + crossing)
		var x_axis := Vector2(cos(radians), sin(radians)) * scale.x
		var y_axis := Vector2(cos(cross_radians), sin(cross_radians)) * scale.y
		var transform := Transform2D(x_axis, y_axis, Vector2(dst_pos) - x_axis * center.x - y_axis * center.y)
		if is_zero_approx(transform.determinant()):
			return
		var size_vector := Vector2(source.get_size())
		var bounds := Rect2(transform * Vector2.ZERO, Vector2.ZERO)
		for point: Vector2 in [Vector2(size_vector.x, 0), size_vector, Vector2(0, size_vector.y)]:
			bounds = bounds.expand(transform * point)
		var inverse := transform.affine_inverse()
		var alpha_scale := float(256 - transparency_value) / 256.0
		for y in range(maxi(0, floori(bounds.position.y)), mini(image.get_height(), ceili(bounds.end.y))):
			for x in range(maxi(0, floori(bounds.position.x)), mini(image.get_width(), ceili(bounds.end.x))):
				var sample := inverse * Vector2(x + 0.5, y + 0.5)
				if sample.x >= 0.0 and sample.y >= 0.0 and sample.x < size_vector.x and sample.y < size_vector.y:
					var color := source.get_pixel(floori(sample.x), floori(sample.y))
					color.a *= alpha_scale
					image.set_pixel(x, y, image.get_pixel(x, y).blend(color))

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
		var movie_instance_id := get_instance_id()
		if host != null and not filename.is_empty():
			if host.movie_owner_instance_id != -1 and host.movie_owner_instance_id != movie_instance_id:
				var prior_owner: Variant = host.movie_owner_ref.get_ref() if host.movie_owner_ref != null else null
				if prior_owner != null:
					return 0
				# Recover if a script dropped its last MovieSprite reference before
				# the media owner was explicitly closed.
				host.movie_resource_request_instance_id = host.movie_owner_instance_id
				host.emit_signal("movie_close_requested")
				host.movie_owner_instance_id = -1
				host.movie_owner_ref = null
			host.movie_resource_request_instance_id = movie_instance_id
			host.movie_opened = false
			host.emit_signal("movie_open_requested", filename)
			if host.movie_opened:
				host.movie_owner_instance_id = movie_instance_id
				host.movie_owner_ref = weakref(self)
				return 1
			host.movie_owner_instance_id = -1
			return 0
		return 0

	func play_movie(mode: int = 0) -> int:
		if host == null or filename.is_empty() or host.movie_owner_instance_id != get_instance_id():
			return 0
		host.movie_play_result = false
		host.emit_signal("movie_requested", filename, mode, movie_rewind_frame, movie_end_frame, movie_repeat, get_instance_id())
		return 1 if host.movie_play_result else 0

	func set_rewinding_portion(rewind_pos: int = -1, end_pos: int = -1, repeat: bool = false) -> int:
		if rewind_pos < -1 or end_pos < -1:
			return 0
		var resolved_start := 0 if rewind_pos < 0 else rewind_pos
		var movie_instance_id := get_instance_id()
		var owns_open_movie := host != null and host.movie_owner_instance_id == movie_instance_id
		var total_frames := host.movie_total_frames if owns_open_movie else 0
		var resolved_end := total_frames if end_pos < 0 and total_frames > 0 else end_pos
		var stored_count := host.movie_stored_frame_count if owns_open_movie else 0
		if resolved_end >= 0 and (
			resolved_start >= resolved_end
			or (total_frames > 0 and resolved_end > total_frames)
			or (stored_count > 0 and resolved_start >= stored_count)
		):
			return 0
		movie_rewind_frame = rewind_pos
		movie_end_frame = end_pos
		movie_repeat = repeat
		if host != null and host.is_movie_playing and host.active_movie_instance_id == movie_instance_id:
			host.emit_signal("movie_loop_portion_requested", rewind_pos, end_pos, repeat, movie_instance_id)
		return 1

	func is_movie_playing() -> int:
		if host != null and host.is_movie_playing and host.active_movie_instance_id == get_instance_id():
			return 1
		return 0

	func seek_frame(frame_index: int) -> int:
		if host == null or host.movie_owner_instance_id != get_instance_id() or host.movie_total_frames <= 0 or frame_index < 0 or frame_index >= host.movie_total_frames:
			return 0
		host.movie_resource_request_instance_id = get_instance_id()
		host.movie_seek_result = false
		host.emit_signal("movie_seek_requested", frame_index)
		return 1 if host.movie_seek_result else 0

	func get_current_frame() -> int:
		return host.movie_current_frame if host != null and host.movie_owner_instance_id == get_instance_id() else -1

	func get_total_frame() -> int:
		return host.movie_total_frames if host != null and host.movie_owner_instance_id == get_instance_id() else 0

	func get_total_time() -> int:
		return host.movie_total_time_ms if host != null and host.movie_owner_instance_id == get_instance_id() else 0

	func stop_movie() -> int:
		if host != null and host.movie_owner_instance_id == get_instance_id():
			host.movie_resource_request_instance_id = get_instance_id()
			host.is_movie_playing = false
			host.emit_signal("movie_stop_requested")
		return 0

	func close_movie() -> int:
		if host != null and host.movie_owner_instance_id != get_instance_id():
			return 0
		stop_movie()
		if host != null:
			host.movie_resource_request_instance_id = get_instance_id()
			host.emit_signal("movie_close_requested")
			host.movie_opened = false
			host.active_movie_instance_id = -1
			host.movie_owner_instance_id = -1
			host.movie_owner_ref = null
			host.movie_total_frames = 0
			host.movie_stored_frame_count = 0
			host.movie_total_time_ms = 0
			host.movie_current_frame = -1
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
		if host != null and not host.runtime_shutdown:
			host.runtime_windows[get_instance_id()] = weakref(self)

	func add_sprite(z: int, spr: Variant) -> void:
		if spr is HostSprite:
			if spr.root_window != null and spr.root_window != self and spr.host != null:
				spr.host.flush_sprite_commands(spr.get_instance_id())
			if spr.parent_sprite != null:
				spr.parent_sprite.children.erase(spr)
				spr.parent_sprite = null
			if spr.root_window != null and spr.root_window != self:
				spr.root_window.root_sprites.erase(spr)
			spr.z_order = z
			if not root_sprites.has(spr):
				root_sprites.append(spr)
			spr.root_window = self

	func detach_sprite(spr: Variant) -> void:
		if spr is HostSprite:
			if host != null:
				host.flush_sprite_commands(spr.get_instance_id())
			if _contains_focused_sprite(spr):
				set_focus("")
			root_sprites.erase(spr)
			if spr.root_window == self:
				spr.root_window = null

	func _contains_focused_sprite(sprite: HostSprite) -> bool:
		if sprite == focused_sprite:
			return true
		for child: HostSprite in sprite.children:
			if _contains_focused_sprite(child):
				return true
		return false

	func detach_all_sprites() -> void:
		if host != null:
			host.flush_window_commands(get_instance_id())
		for sprite: HostSprite in root_sprites:
			if sprite.root_window == self:
				sprite.root_window = null
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
		if focused_sprite != null:
			focused_sprite.has_window_focus = false
			if focused_sprite.is_button and focused_sprite.btn_state == "focus":
				var remains_checked := bool(focused_sprite.fields.get("checked", false))
				focused_sprite.set_button_state("pushed" if remains_checked else "normal")
		focused_sprite = target
		focused_path = path
		if target != null:
			target.has_window_focus = true

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
				return active_filter.get_joy_button_pushed(key, 0, during_activation, get_instance_id())
		return host.poll_advance_button(key, during_activation, get_instance_id()) if host != null else 0

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

	func change_display_size(w: int, h: int) -> int:
		if w <= 0 or h <= 0:
			return 1
		viewport_size = Vector2i(w, h)
		if DisplayServer.get_name() != "headless" and DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_size(viewport_size)
		return 0

	func change_cooperation_level(level: int) -> int:
		# The original ChangeDisplay(fFullscreen) helper calls level 3 for its
		# fullscreen branch and level 0 for its windowed branch.
		if DisplayServer.get_name() == "headless":
			return 0
		var requested_mode := DisplayServer.WINDOW_MODE_FULLSCREEN if level == 3 else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != requested_mode:
			DisplayServer.window_set_mode(requested_mode)
		if requested_mode == DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_size(viewport_size)
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
		# against the original CSX poll/flush loop. Runtime page transitions use
		# begin_command_scope(); this API is kept separate until its original
		# Entis semantics are confirmed against the native runtime.
		return 0

	func get_command(p_cmd: Variant = null, _p1: int = 0, _p2: int = 0, _p3: int = 0) -> int:
		if host != null:
			var event: Dictionary = host.pop_command_for_window(get_instance_id())
			if event.is_empty():
				host.clear_native_command_dispatch(get_instance_id())
				return 0
			host.mark_native_command_dispatch(get_instance_id())
			host.clear_command_cursor_override()
			var cmd_id: String = ""
			var full_id: String = ""
			var notification: int = 0
			var parameter: int = 0
			if event is Dictionary:
				cmd_id = event.get("id", "")
				full_id = event.get("full_id", cmd_id)
				notification = int(event.get("notification", event.get("command", 0)))
				parameter = int(event.get("parameter", 0))
				var event_cursor: Variant = event.get("cursor_position", null)
				if event_cursor is Vector2i or event_cursor is Vector2:
					host.set_command_cursor_override(event_cursor)
			if p_cmd != null:
				if p_cmd.has_method("set_field"):
					p_cmd.set_field("strID", cmd_id)
					p_cmd.set_field("strFullID", full_id)
					p_cmd.set_field("nNotification", notification)
					p_cmd.set_field("nParameter", parameter)
				elif "fields" in p_cmd:
					p_cmd.fields["strID"] = cmd_id
					p_cmd.fields["strFullID"] = full_id
					p_cmd.fields["nNotification"] = notification
					p_cmd.fields["nParameter"] = parameter
			return 1
		return 0


class HostFile extends RefCounted:
	const MODE_READ := 0
	const MODE_WRITE := 1
	const MODE_READ_WRITE := 2
	# Observed in the original Yosuga CSX Save(filename, ...): mode 5 opens a
	# save/create path; preserve the project-local 0/1/2 modes as well.
	const MODE_CREATE_WRITE := 5
	var host: CsxHost = null
	var vm: RefCounted = null
	var current_path: String = ""
	var current_mode: int = 0
	var is_open: bool = false

	func _init(p_host: CsxHost, p_vm: RefCounted = null) -> void:
		host = p_host
		vm = p_vm
		if host != null and not host.runtime_shutdown:
			host.runtime_services[get_instance_id()] = weakref(self)

	func open(path: String, mode: int = 2) -> int:
		is_open = false
		current_path = ""
		if mode not in [MODE_READ, MODE_WRITE, MODE_READ_WRITE, MODE_CREATE_WRITE]:
			return 1
		if host == null or path.is_empty():
			return 1
		if mode in [MODE_READ, MODE_READ_WRITE] and not host.is_file_existing(path):
			return 1
		current_path = path
		current_mode = mode
		is_open = true
		return 0

	func close() -> int:
		is_open = false
		current_path = ""
		return 0

	func save_object(obj: Variant) -> int:
		if not is_open or current_mode == MODE_READ or host == null or current_path.is_empty():
			return 1
		var ok: bool = host.save_object_file(current_path, obj)
		return 0 if ok else 1

	func load_object(obj: Variant) -> int:
		if not is_open or current_mode == MODE_WRITE or host == null or current_path.is_empty():
			return 1
		var ok: bool = host.load_object_file(current_path, obj, vm)
		return 0 if ok else 1

	func save_thumbnail_image(spr: Variant, w: int = 120, h: int = 90) -> int:
		if not is_open or current_mode == MODE_READ or host == null or current_path.is_empty():
			return 1
		return 0 if host.save_thumbnail(current_path, spr, w, h) else 1

	func is_existing(path: String) -> int:
		if host != null:
			return -1 if host.is_file_existing(path) else 0
		return 0

	func dump_context(_path: String = "") -> int:
		return 0

	func output_log_text(path: String, text: String) -> int:
		if not is_open or current_mode == MODE_READ or host == null:
			return 1
		var sp := host.get_save_path(path)
		var absolute_path := ProjectSettings.globalize_path(sp)
		var directory := absolute_path.get_base_dir()
		if not DirAccess.dir_exists_absolute(directory):
			var directory_error := DirAccess.make_dir_recursive_absolute(directory)
			if directory_error != OK:
				host.last_error = "无法创建日志目录: %s (%s)" % [directory, error_string(directory_error)]
				return 1
		if not FileAccess.file_exists(sp):
			var created := FileAccess.open(sp, FileAccess.WRITE)
			if created == null:
				host.last_error = "无法创建日志文件: %s (%s)" % [sp, error_string(FileAccess.get_open_error())]
				return 1
			created.close()
		var f := FileAccess.open(sp, FileAccess.READ_WRITE)
		if f == null:
			host.last_error = "无法打开日志文件: %s (%s)" % [sp, error_string(FileAccess.get_open_error())]
			return 1
		f.seek_end()
		f.store_line(text)
		f.flush()
		var write_error := f.get_error()
		f.close()
		if write_error != OK:
			host.last_error = "日志写入失败: %s (%s)" % [sp, error_string(write_error)]
			return 1
		return 0




func poll_advance_button(key: int, during_activation: bool, window_id: int = -1) -> int:
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
	# A queued native command wakes the CSX, but the script may poll advance
	# buttons before it inspects the command ID. Do not re-arm the scheduler's
	# input wait until that command has been dispatched and the next empty
	# GetCommand poll is reached.
	if not is_native_command_dispatch_pending(window_id):
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


func mark_native_command_dispatch(window_id: int) -> void:
	if not runtime_shutdown and runtime_windows.has(window_id):
		native_command_dispatch_windows[window_id] = true


func clear_native_command_dispatch(window_id: int) -> void:
	native_command_dispatch_windows.erase(window_id)


func is_native_command_dispatch_pending(window_id: int = -1) -> bool:
	_prune_native_command_dispatch_windows()
	if window_id == -1:
		return not native_command_dispatch_windows.is_empty()
	return native_command_dispatch_windows.has(window_id)


func _prune_native_command_dispatch_windows() -> void:
	var stale_window_ids: Array[int] = []
	for window_id: int in native_command_dispatch_windows.keys():
		var window_ref: Variant = runtime_windows.get(window_id, null)
		if not window_ref is WeakRef or window_ref.get_ref() == null:
			stale_window_ids.append(window_id)
	for window_id: int in stale_window_ids:
		native_command_dispatch_windows.erase(window_id)


func begin_command_scope(context_id: String) -> int:
	if runtime_shutdown:
		return -1
	var scope := _command_events.begin_scope(context_id)
	native_command_dispatch_windows.clear()
	clear_command_cursor_override()
	command_overflow_reported = false
	return scope


func pending_command_count() -> int:
	return _command_events.pending_count


func current_command_scope() -> int:
	return _command_events.scope_generation


func has_pending_commands() -> bool:
	return _command_events.pending_count > 0


func has_pending_commands_for_window(window_id: int) -> bool:
	return not _command_events.peek_for_window(window_id, _command_events.scope_generation).is_empty()


func peek_command_for_window(window_id: int) -> Dictionary:
	return _command_events.peek_for_window(window_id, _command_events.scope_generation)


func peek_last_command_for_window(window_id: int) -> Dictionary:
	return _command_events.peek_last_for_window(window_id, _command_events.scope_generation)


func pending_commands_snapshot() -> Array[Dictionary]:
	return _command_events.snapshot(_command_events.scope_generation)


func pop_command_for_window(window_id: int) -> Dictionary:
	return _command_events.pop_for_window(window_id, _command_events.scope_generation)


func flush_window_commands(window_id: int) -> int:
	return _command_events.flush_window(window_id, _command_events.scope_generation)


func flush_sprite_commands(sprite_id: int) -> int:
	return _command_events.flush_source_sprite(sprite_id, _command_events.scope_generation)


func push_command(
	cmd: String,
	full_id: String = "",
	notification: int = 0,
	parameter: int = 0,
	cursor_pos: Variant = null,
	source_window: Variant = null,
	expected_scope: int = -1,
	coalesce_key: String = "",
	source_sprite: Variant = null
) -> bool:
	if runtime_shutdown:
		return false
	var command := {
		"id": cmd,
		"full_id": full_id if not full_id.is_empty() else cmd,
		"notification": notification,
		"parameter": parameter,
	}
	if cursor_pos is Vector2i or cursor_pos is Vector2:
		command["cursor_position"] = Vector2i(roundi(cursor_pos.x), roundi(cursor_pos.y))
	var source_window_id := -1
	if source_window is HostWindow:
		if source_window.host != self or not runtime_windows.has(source_window.get_instance_id()):
			return false
		source_window_id = source_window.get_instance_id()
	if source_sprite is HostSprite:
		command["source_sprite_id"] = source_sprite.get_instance_id()
	if coalesce_key.is_empty() and notification == 4:
		coalesce_key = "notification:%s" % cmd
	var scope: int = _command_events.scope_generation if expected_scope < 0 else expected_scope
	var sequence := _command_events.enqueue(command, scope, source_window_id, coalesce_key)
	if sequence < 0:
		command_overflow_count += 1
		if not command_overflow_reported:
			command_overflow_reported = true
			push_warning("Host command queue rejected an event (capacity=%d, scope=%d, rejected=%d)" % [_command_events.capacity, _command_events.scope_generation, command_overflow_count])
		return false
	# The Story scheduler pauses the VM after an empty advance-button poll.
	# A native window command must resume the original CSX command loop without
	# synthesizing an advance tick; the script decides what that command means.
	if is_waiting_input:
		is_waiting_input = false
	return true


func set_command_cursor_override(position: Variant) -> void:
	if not (position is Vector2i or position is Vector2):
		clear_command_cursor_override()
		return
	command_cursor_override = Vector2i(roundi(position.x), roundi(position.y))
	command_cursor_override_valid = true
	command_cursor_override_expires_usec = Time.get_ticks_usec() + 500000


func clear_command_cursor_override() -> void:
	command_cursor_override_valid = false
	command_cursor_override_expires_usec = 0


func set_tone_filter(type_name: String) -> void:
	current_tone_filter = type_name.to_upper()
	emit_signal("tone_filter_updated", current_tone_filter)


func _init(p_game_dir: String = "") -> void:
	game_dir = p_game_dir
	if not game_dir.is_empty():
		init_vfs()


func shutdown_runtime() -> void:
	if runtime_shutdown:
		return
	if pending_confirmation_active:
		resolve_confirmation(0)
	runtime_shutdown = true
	if active_input_filter_ref != null:
		var active_filter: Variant = active_input_filter_ref.get_ref()
		if active_filter != null and active_filter.has_method("close_filter"):
			active_filter.close_filter()
	active_input_filter_ref = null
	cursor_position_provider = Callable()
	_command_events.shutdown()
	native_command_dispatch_windows.clear()
	clear_command_cursor_override()
	movie_owner_ref = null
	movie_owner_instance_id = -1
	active_movie_instance_id = -1
	is_movie_playing = false
	for window_ref: WeakRef in runtime_windows.values():
		var window: Variant = window_ref.get_ref()
		if window is HostWindow:
			window.detach_all_sprites()
			window.focused_sprite = null
			window.fields.clear()
			window.host = null
	for sprite_ref: WeakRef in runtime_sprites.values():
		var sprite: Variant = sprite_ref.get_ref()
		if not sprite is HostSprite:
			continue
		sprite.detach_all_sprites()
		sprite.parent_sprite = null
		sprite.root_window = null
		sprite.release()
		sprite.fields.clear()
		sprite.sprite_parameters.clear()
		sprite.message_style.clear()
		sprite.activation_curves = [[], [], []]
		sprite.activation_durations.clear()
		sprite.animation_frames.clear()
		sprite.animation_sequence.clear()
		sprite.image = null
		sprite.texture = null
		sprite.alpha_image = null
		sprite.alpha_texture = null
		sprite.attached_resource = null
		sprite.alpha_resource = null
		sprite.tone_filter = null
		sprite.form_resources = null
		sprite.btn_normal_tex = null
		sprite.btn_focus_tex = null
		sprite.btn_pushed_tex = null
		sprite.btn_disabled_tex = null
		sprite.btn_normal_img = null
		sprite.btn_focus_img = null
		sprite.btn_pushed_img = null
		sprite.btn_disabled_img = null
		sprite.host = null
	for resource_ref: WeakRef in runtime_resources.values():
		var resource: Variant = resource_ref.get_ref()
		if not resource is HostResource:
			continue
		resource.volume_envelope.clear()
		resource.fields.clear()
		resource.audio_stream = null
		resource.image = null
		resource.texture = null
		resource.image_frames.clear()
		resource.image_frame_sequence.clear()
		resource.host = null
	for service_ref: WeakRef in runtime_services.values():
		var service: Variant = service_ref.get_ref()
		if service is HostInputFilter:
			service.close_filter()
			service.host = null
			service.window_ref = null
			service.input_queue.clear()
			service.input_assignments.clear()
			service.joy_buttons.clear()
			service.fields.clear()
		elif service is HostToneFilter:
			service.host = null
			service.tone_texture = null
			service.fields.clear()
			service.red_table.clear()
			service.green_table.clear()
			service.blue_table.clear()
			service.alpha_table.clear()
		elif service is HostResourceManager:
			service.host = null
			service.resource_cache.clear()
			service.skin_resources.clear()
			service.skin_styles.clear()
			service.skin_pages.clear()
			service.fields.clear()
		elif service is HostFile:
			service.close()
			service.host = null
			service.vm = null
	for player: Variant in [bgm_player, env_se_player, se_player, voice_player, system_player]:
		if player is AudioStreamPlayer:
			player.stop()
			player.stream_paused = false
			player.stream = null
	for player_value: Variant in audio_players.values() + audio_right_players.values():
		if player_value is AudioStreamPlayer:
			player_value.stop()
			player_value.stream_paused = false
			player_value.stream = null
	audio_players.clear()
	audio_right_players.clear()
	bgm_player = null
	env_se_player = null
	se_player = null
	voice_player = null
	system_player = null
	active_sprites.clear()
	active_messages.clear()
	active_effect_sprites.clear()
	active_animated_sprites.clear()
	active_volume_envelopes.clear()
	runtime_windows.clear()
	runtime_services.clear()
	runtime_sprites.clear()
	runtime_resources.clear()
	archives.clear()
	vfs_index.clear()
	vfs_conflicts.clear()
	vfs_warned_conflicts.clear()
	clear_resource_caches()
	current_bg_texture = null


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
	var normalized_request := archive_filename.replace("\\", "/")
	var archive_file := normalized_request.get_file()
	var candidate_paths: Array[String] = []
	# An explicitly supplied path is authoritative. Searching the standard
	# basename fallbacks first can silently open a different archive with the
	# same filename (for example game_dir/system/foo.noa instead of game_dir/foo.noa).
	if normalized_request.is_absolute_path() or normalized_request.begins_with("res://") or normalized_request.begins_with("user://"):
		candidate_paths.append(normalized_request)
	candidate_paths.append_array([
		game_dir.path_join("system").path_join(archive_file),
		game_dir.path_join(archive_file),
		"res://assets/system/".path_join(archive_file),
		"res://assets/".path_join(archive_file),
		"user://game/system/".path_join(archive_file),
		"user://game/".path_join(archive_file),
		"user://assets/system/".path_join(archive_file),
		"user://assets/".path_join(archive_file)
	])
	if not candidate_paths.has(normalized_request):
		candidate_paths.append(normalized_request)
	var found_path := ""
	for path in candidate_paths:
		if FileAccess.file_exists(path):
			found_path = path
			break

	if found_path.is_empty():
		last_error = "未找到资源归档: %s" % archive_filename
		return null
	# Keep filesystem identity case-sensitive. Virtual entry names are normalized
	# separately; lowercasing a physical archive path aliases distinct Linux files.
	var canonical_path := ProjectSettings.globalize_path(found_path).simplify_path()
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
	var normalized_hint := archive_hint.replace("\\", "/").simplify_path()
	if normalized_hint.is_empty():
		return false
	var canonical_archive := archive_path.replace("\\", "/").simplify_path()
	var is_physical_hint := normalized_hint.is_absolute_path() or normalized_hint.begins_with("res://") or normalized_hint.begins_with("user://") or FileAccess.file_exists(normalized_hint)
	if is_physical_hint:
		var physical_hint := ProjectSettings.globalize_path(normalized_hint).replace("\\", "/").simplify_path()
		return canonical_archive == physical_hint
	var folded_hint := normalized_hint.to_lower()
	var folded_archive := canonical_archive.to_lower()
	if folded_hint.contains("/"):
		return folded_archive == folded_hint or folded_archive.ends_with("/" + folded_hint)
	return folded_archive.get_file() == folded_hint.get_file()


func find_vfs_entries(filename: String, archive_hint: String = "") -> Array[Dictionary]:
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
	var matches: Array[Dictionary] = []
	var seen: Dictionary = {}
	var saw_candidate := false
	for c in candidates:
		if vfs_index.has(c):
			saw_candidate = true
			var entries: Array = vfs_index[c] if vfs_index[c] is Array else [vfs_index[c]]
			if archive_hint.is_empty() and entries.size() > 1 and not vfs_warned_conflicts.has(c):
				vfs_warned_conflicts[c] = true
				push_warning("VFS 条目有多个归档候选，按加载顺序选择首项: %s；请查阅 get_vfs_conflict_report()" % c)
			for entry: Dictionary in entries:
				if not archive_hint.is_empty() and not _archive_matches_hint(str(entry.get("archive", "")), archive_hint):
					continue
				var cache_key := _vfs_cache_key(entry)
				if not seen.has(cache_key):
					seen[cache_key] = true
					matches.append(entry)
	if matches.is_empty():
		if not archive_hint.is_empty() and saw_candidate:
			last_error = "VFS 归档提示与条目候选不匹配: %s (%s)" % [filename, archive_hint]
		else:
			last_error = "VFS entry not found: %s" % filename
	return matches


func find_vfs_entry(filename: String, archive_hint: String = "") -> Dictionary:
	var entries := find_vfs_entries(filename, archive_hint)
	return entries[0] if not entries.is_empty() else {}


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
	var entries := find_vfs_entries(filename, archive_hint)
	if entries.is_empty():
		return {"ok": false, "error": last_error if not last_error.is_empty() else "VFS entry not found: %s" % filename}
	var last_read_error := ""
	for entry in entries:
		var result := _read_vfs_candidate(entry)
		if result.get("ok", false):
			return result
		last_read_error = str(result.get("error", "VFS candidate read failed"))
	last_error = last_read_error
	return {"ok": false, "error": last_read_error}


func get_save_path(filename: String) -> String:
	return save_dir.path_join(filename.get_file())


func get_thumbnail_path(filename: String) -> String:
	var save_path := get_save_path(filename)
	var thumbnail_document := _read_thumbnail_document(save_path)
	if thumbnail_document.get("ok", false):
		var document: Dictionary = thumbnail_document["document"]
		if document.has("thumbnail_file"):
			var referenced_file := str(document.get("thumbnail_file", ""))
			if referenced_file.is_empty():
				return ""
			if not _is_safe_thumbnail_filename(referenced_file):
				return ""
			return save_dir.path_join(referenced_file)
	return _legacy_thumbnail_path(filename)


func _legacy_thumbnail_path(filename: String) -> String:
	return save_dir.path_join(filename.get_file().get_basename() + ".png")


func _is_safe_thumbnail_filename(filename: String) -> bool:
	return not filename.is_empty() and filename == filename.get_file() and not filename.contains("..") and filename.to_lower().ends_with(".png")


func _read_thumbnail_document(save_path: String) -> Dictionary:
	var save_data: Dictionary = BoundedFileReader.read(save_path, MAX_SAVE_DOCUMENT_BYTES)
	if not save_data.get("ok", false):
		return {}
	var parser := JSON.new()
	if parser.parse((save_data.get("data", PackedByteArray()) as PackedByteArray).get_string_from_utf8()) != OK:
		return {}
	if not parser.data is Dictionary or not parser.data.get("__yzk_save_document__", false):
		return {}
	return {"ok": true, "document": parser.data}


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
	# File::IsExisting is routinely used for optional resources. A normal VFS
	# miss is a false predicate, not a host failure; preserve any earlier error
	# rather than reporting the expected absence as the current diagnostic.
	var previous_error := last_error
	var exists := not find_vfs_entry(filename).is_empty()
	if not exists and last_error == "VFS entry not found: %s" % filename:
		last_error = previous_error
	return exists



func load_image(filename: String, archive_hint: String = "") -> Dictionary:
	var save_image_name := filename.get_file()
	var save_image_stem := save_image_name.get_basename().to_lower()
	if save_image_name.get_extension().to_lower() == "dat" and save_image_stem.begins_with("save"):
		var thumbnail_result := load_thumbnail_image(save_image_name)
		if not thumbnail_result.get("ok", false):
			last_error = str(thumbnail_result.get("error", "无法读取存档缩略图。"))
			return {"ok": false, "error": last_error}
		var thumbnail_image: Image = thumbnail_result["image"]
		var thumbnail_texture := ImageTexture.create_from_image(thumbnail_image)
		var thumbnail_frames: Array[Image] = [thumbnail_image]
		var thumbnail_sequence: Array[int] = [0]
		return {
			"ok": true,
			"image": thumbnail_image,
			"texture": thumbnail_texture,
			"frames": thumbnail_frames,
			"frame_sequence": thumbnail_sequence,
			"total_time_ms": 0,
			"is_save_thumbnail": true
		}
	var norm := _normalize_vfs_path(filename)
	if not norm.ends_with(".eri"):
		norm += ".eri"
	var entries := find_vfs_entries(norm, archive_hint)
	if entries.is_empty():
		return {"ok": false, "error": last_error if not last_error.is_empty() else "无法在 VFS 中找到图片: %s" % norm}
	var candidate_error := ""
	for entry in entries:
		var cache_key := _vfs_cache_key(entry)
		if image_cache.has(cache_key):
			var item: Dictionary = image_cache[cache_key]
			image_cache_lru.erase(cache_key)
			image_cache_lru.append(cache_key)
			return item.duplicate()
		var entry_res := _read_vfs_candidate(entry)
		if not entry_res.get("ok", false):
			candidate_error = str(entry_res.get("error", "VFS image candidate read failed"))
			continue
		var dec_res := EriDecoder.decode(entry_res["data"])
		if not dec_res.get("ok", false):
			candidate_error = str(dec_res.get("error", "ERI image decode failed"))
			continue
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
			_trim_combined_media_cache()
		return image_result
	last_error = candidate_error
	return {"ok": false, "error": candidate_error if not candidate_error.is_empty() else "无法在 VFS 中找到图片: %s" % norm}


func load_sound(filename: String, archive_hint: String = "") -> Dictionary:
	var norm := _normalize_vfs_path(filename)
	if not norm.ends_with(".mio"):
		norm += ".mio"
	var entries := find_vfs_entries(norm, archive_hint)
	if entries.is_empty():
		return {"ok": false, "error": last_error if not last_error.is_empty() else "无法在 VFS 中找到音频: %s" % norm}
	var candidate_error := ""
	for entry in entries:
		var cache_key := _vfs_cache_key(entry)
		if sound_cache.has(cache_key):
			sound_cache_lru.erase(cache_key)
			sound_cache_lru.append(cache_key)
			return {"ok": true, "stream": sound_cache[cache_key], "archive": str(entry.get("archive", "")), "entry_name": str(entry.get("entry_name", norm))}
		var entry_res := _read_vfs_candidate(entry)
		if not entry_res.get("ok", false):
			candidate_error = str(entry_res.get("error", "VFS audio candidate read failed"))
			continue
		var dec_res := MioDecoder.decode(entry_res["data"])
		if not dec_res.get("ok", false):
			candidate_error = str(dec_res.get("error", "MIO 音频解码失败: %s" % norm))
			continue
		var stream: AudioStreamWAV = dec_res["stream"]
		var stream_bytes := stream.data.size()
		if stream_bytes <= sound_cache_budget_bytes:
			sound_cache[cache_key] = stream
			sound_cache_lru.append(cache_key)
			sound_cache_bytes += stream_bytes
			_trim_sound_cache()
			_trim_combined_media_cache()
		return {"ok": true, "stream": stream, "archive": str(entry_res.get("archive", entry.get("archive", ""))), "entry_name": str(entry_res.get("entry_name", norm))}
	last_error = candidate_error
	return {"ok": false, "error": candidate_error if not candidate_error.is_empty() else "无法在 VFS 中找到音频: %s" % norm}


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


func _trim_combined_media_cache() -> void:
	# This budget covers only entries still owned by the decode caches. Sprites,
	# players, GPU textures, and active decoder buffers can extend their lifetime.
	while image_cache_bytes + sound_cache_bytes > cached_media_budget_bytes:
		if image_cache_bytes >= sound_cache_bytes and not image_cache_lru.is_empty():
			var oldest_image: String = image_cache_lru.pop_front()
			if image_cache.has(oldest_image):
				var cached_image: Dictionary = image_cache[oldest_image]
				image_cache_bytes = maxi(0, image_cache_bytes - int(cached_image.get("bytes", 0)))
				image_cache.erase(oldest_image)
		elif not sound_cache_lru.is_empty():
			var oldest_sound: String = sound_cache_lru.pop_front()
			if sound_cache.has(oldest_sound):
				var cached_sound: AudioStreamWAV = sound_cache[oldest_sound]
				sound_cache_bytes = maxi(0, sound_cache_bytes - cached_sound.data.size())
				sound_cache.erase(oldest_sound)
		else:
			break


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
	if command_cursor_override_valid:
		var now_usec := Time.get_ticks_usec()
		if now_usec <= command_cursor_override_expires_usec:
			var position := command_cursor_override
			clear_command_cursor_override()
			return position
		clear_command_cursor_override()
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


func present_pending_confirmation() -> void:
	if pending_confirmation_active:
		confirmation_requested.emit(pending_confirmation_prompt)


func resolve_confirmation(result: int) -> bool:
	if not pending_confirmation_active:
		return false
	var target_vm: Variant = pending_confirmation_vm.get_ref() if pending_confirmation_vm != null else null
	pending_confirmation_vm = null
	pending_confirmation_active = false
	pending_confirmation_prompt = ""
	if target_vm == null or not target_vm.has_method("resolve_host_confirmation"):
		return false
	return bool(target_vm.call("resolve_host_confirmation", result))


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
			if (
				vm != null
				and vm.has_method("can_defer_host_call")
				and bool(vm.call("can_defer_host_call"))
				and not get_signal_connection_list("confirmation_requested").is_empty()
				and not pending_confirmation_active
			):
				pending_confirmation_vm = weakref(vm)
				pending_confirmation_active = true
				pending_confirmation_prompt = str(args[0]) if not args.is_empty() else "确定要继续吗？"
				return {"handled": true, "deferred": true}
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


func save_thumbnail(filename: String, spr: Variant, w: int = 120, h: int = 90) -> bool:
	var thumbnail_data := _make_thumbnail_png(spr, w, h)
	if not thumbnail_data.get("ok", false):
		last_error = str(thumbnail_data.get("error", "无法生成缩略图"))
		return false
	var save_path := get_save_path(filename)
	var thumbnail_document := _read_thumbnail_document(save_path)
	if not thumbnail_document.get("ok", false):
		return _commit_thumbnail_data(filename, thumbnail_data, _legacy_thumbnail_path(filename))
	var document: Dictionary = thumbnail_document["document"].duplicate(true)
	var thumbnail_file := ""
	var thumbnail_hash := ""
	if thumbnail_data.get("has_image", false):
		thumbnail_file = _new_thumbnail_filename(filename)
		thumbnail_hash = _sha256_bytes(thumbnail_data.get("bytes", PackedByteArray()))
		if thumbnail_hash.is_empty() or not _write_thumbnail_file(save_dir.path_join(thumbnail_file), thumbnail_data.get("bytes", PackedByteArray())):
			last_error = "无法在提交缩略图元数据前写入图像。"
			return false
	document["thumbnail_file"] = thumbnail_file
	document["thumbnail_sha256"] = thumbnail_hash
	var encoded_document := JSON.stringify(document)
	if encoded_document.to_utf8_buffer().size() > MAX_SAVE_DOCUMENT_BYTES or not write_save_atomically(save_path, encoded_document):
		if not thumbnail_file.is_empty():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(save_dir.path_join(thumbnail_file)))
		return false
	_cleanup_unreferenced_thumbnails(filename)
	return true


func _make_thumbnail_png(spr: Variant, w: int, h: int) -> Dictionary:
	if w <= 0 or h <= 0:
		return {"ok": false, "error": "缩略图尺寸必须为正数。"}
	var img: Image = null
	if spr is HostSprite and spr.texture != null:
		img = spr.texture.get_image()
	elif spr is HostSprite and spr.image != null:
		img = spr.image
	elif current_bg_texture != null:
		img = current_bg_texture.get_image()
	if img == null:
		return {"ok": true, "has_image": false, "bytes": PackedByteArray()}
	var copy := img.duplicate()
	copy.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var png_bytes: PackedByteArray = copy.save_png_to_buffer()
	if png_bytes.is_empty():
		return {"ok": false, "error": "Godot 无法编码存档缩略图。"}
	return {"ok": true, "has_image": true, "bytes": png_bytes}


func _commit_thumbnail_data(filename: String, thumbnail_data: Dictionary, output_path: String = "") -> bool:
	var tp := output_path if not output_path.is_empty() else get_thumbnail_path(filename)
	var dir := tp.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		if DirAccess.make_dir_recursive_absolute(dir) != OK:
			return false
	if not thumbnail_data.get("ok", false):
		return false
	if not thumbnail_data.get("has_image", false):
		if FileAccess.file_exists(tp):
			return DirAccess.remove_absolute(ProjectSettings.globalize_path(tp)) == OK
		return true
	var temporary_path := tp + ".tmp.png"
	var backup_path := tp + ".bak.png"
	if FileAccess.file_exists(temporary_path):
		if DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path)) != OK:
			return false
	if FileAccess.file_exists(backup_path):
		if DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path)) != OK:
			return false
	var temporary := FileAccess.open(temporary_path, FileAccess.WRITE)
	if temporary == null:
		return false
	temporary.store_buffer(thumbnail_data.get("bytes", PackedByteArray()))
	temporary.flush()
	var temporary_error := temporary.get_error()
	temporary.close()
	if temporary_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
		return false
	var absolute_thumbnail := ProjectSettings.globalize_path(tp)
	var absolute_temporary := ProjectSettings.globalize_path(temporary_path)
	var absolute_backup := ProjectSettings.globalize_path(backup_path)
	var had_previous := FileAccess.file_exists(tp)
	if had_previous and DirAccess.rename_absolute(absolute_thumbnail, absolute_backup) != OK:
		DirAccess.remove_absolute(absolute_temporary)
		return false
	if DirAccess.rename_absolute(absolute_temporary, absolute_thumbnail) != OK:
		if had_previous:
			DirAccess.rename_absolute(absolute_backup, absolute_thumbnail)
		DirAccess.remove_absolute(absolute_temporary)
		return false
	if had_previous:
		DirAccess.remove_absolute(absolute_backup)
	print("[CSX Host] Saved thumbnail to: ", tp)
	return true


func _sha256_bytes(bytes: PackedByteArray) -> String:
	var hasher := HashingContext.new()
	if hasher.start(HashingContext.HASH_SHA256) != OK or hasher.update(bytes) != OK:
		return ""
	return hasher.finish().hex_encode()


func _new_thumbnail_filename(filename: String) -> String:
	var save_filename := get_save_path(filename).get_file()
	return "%s.%d_%d.png" % [save_filename, Time.get_ticks_usec(), randi()]


func _write_thumbnail_file(path: String, png_bytes: PackedByteArray) -> bool:
	if path.is_empty() or png_bytes.is_empty() or not _is_safe_thumbnail_filename(path.get_file()):
		return false
	var directory := ProjectSettings.globalize_path(path.get_base_dir())
	if not DirAccess.dir_exists_absolute(directory) and DirAccess.make_dir_recursive_absolute(directory) != OK:
		return false
	if FileAccess.file_exists(path):
		return false
	var temporary_path := path + ".tmp"
	if FileAccess.file_exists(temporary_path) and DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path)) != OK:
		return false
	var temporary := FileAccess.open(temporary_path, FileAccess.WRITE)
	if temporary == null:
		return false
	temporary.store_buffer(png_bytes)
	temporary.flush()
	var write_error := temporary.get_error()
	temporary.close()
	if write_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
		return false
	var verification: Dictionary = BoundedFileReader.read(temporary_path, MAX_THUMBNAIL_BYTES)
	if not verification.get("ok", false) or _sha256_bytes(verification.get("data", PackedByteArray())) != _sha256_bytes(png_bytes):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
		return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary_path), ProjectSettings.globalize_path(path)) != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
		return false
	return true


func _thumbnail_reference_for_save(save_path: String) -> String:
	var thumbnail_document := _read_thumbnail_document(save_path)
	if not thumbnail_document.get("ok", false):
		return ""
	var document: Dictionary = thumbnail_document["document"]
	if document.has("thumbnail_file"):
		var referenced_file := str(document.get("thumbnail_file", ""))
		return referenced_file if _is_safe_thumbnail_filename(referenced_file) else ""
	return save_path.get_file().trim_suffix(".bak").get_basename() + ".png"


func _cleanup_unreferenced_thumbnails(filename: String) -> void:
	var referenced := {}
	for save_path in [get_save_path(filename), get_save_path(filename) + ".bak"]:
		var reference := _thumbnail_reference_for_save(save_path)
		if not reference.is_empty():
			referenced[reference] = true
	var directory := DirAccess.open(save_dir)
	if directory == null:
		return
	var prefix := get_save_path(filename).get_file() + "."
	for child_name in directory.get_files():
		if not child_name.begins_with(prefix) or not child_name.to_lower().ends_with(".png"):
			continue
		if not referenced.has(child_name):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(save_dir.path_join(child_name)))


func is_thumbnail_current(filename: String) -> bool:
	var thumbnail_document := _read_thumbnail_document(get_save_path(filename))
	if not thumbnail_document.get("ok", false):
		return false
	var document: Dictionary = thumbnail_document["document"]
	var thumbnail_path := get_thumbnail_path(filename)
	if not document.has("thumbnail_sha256"):
		if thumbnail_path.is_empty():
			return true
		var legacy_read := _read_bounded_thumbnail(thumbnail_path)
		return bool(legacy_read.get("ok", false)) # Legacy metadata has no hash; still bound the PNG before use.
	var expected_hash := str(document.get("thumbnail_sha256", ""))
	if expected_hash.is_empty():
		return thumbnail_path.is_empty() or not FileAccess.file_exists(thumbnail_path)
	var thumbnail_data := _read_bounded_thumbnail(thumbnail_path)
	if not thumbnail_data.get("ok", false):
		return false
	return _sha256_bytes(thumbnail_data.get("data", PackedByteArray())) == expected_hash


func load_thumbnail_image(filename: String) -> Dictionary:
	var thumbnail_path := get_thumbnail_path(filename)
	if thumbnail_path.is_empty():
		return {"ok": false, "error": "存档没有缩略图。"}
	var thumbnail_document := _read_thumbnail_document(get_save_path(filename))
	if not thumbnail_document.get("ok", false):
		return {"ok": false, "error": "缩略图清单无效。"}
	var document: Dictionary = thumbnail_document["document"]
	var thumbnail_data := _read_bounded_thumbnail(thumbnail_path)
	if not thumbnail_data.get("ok", false):
		return thumbnail_data
	if document.has("thumbnail_sha256"):
		var expected_hash := str(document.get("thumbnail_sha256", ""))
		if expected_hash.is_empty() or _sha256_bytes(thumbnail_data["data"]) != expected_hash:
			return {"ok": false, "error": "缩略图哈希与存档清单不匹配。"}
	var image := Image.new()
	var decode_error := image.load_png_from_buffer(thumbnail_data["data"])
	if decode_error != OK:
		return {"ok": false, "error": "PNG 缩略图解码失败: %s" % error_string(decode_error)}
	if not _thumbnail_dimensions_allowed(image.get_width(), image.get_height()):
		return {"ok": false, "error": "缩略图解码尺寸超过限制。"}
	return {"ok": true, "image": image}


func _read_bounded_thumbnail(path: String) -> Dictionary:
	var read_result: Dictionary = BoundedFileReader.read(path, MAX_THUMBNAIL_BYTES)
	if not read_result.get("ok", false):
		return read_result
	var bytes: PackedByteArray = read_result["data"]
	if bytes.size() < 24 or bytes.slice(0, 8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]):
		return {"ok": false, "error": "缩略图不是有效 PNG 文件。"}
	if _read_png_u32(bytes, 8) != 13 or bytes.slice(12, 16).get_string_from_ascii() != "IHDR":
		return {"ok": false, "error": "PNG 缩略图缺少规范 IHDR 头。"}
	var width := _read_png_u32(bytes, 16)
	var height := _read_png_u32(bytes, 20)
	if not _thumbnail_dimensions_allowed(width, height):
		return {"ok": false, "error": "PNG 缩略图声明尺寸超过限制 (%d x %d)。" % [width, height]}
	return {"ok": true, "data": bytes, "width": width, "height": height}


func _read_png_u32(bytes: PackedByteArray, offset: int) -> int:
	return (int(bytes[offset]) << 24) | (int(bytes[offset + 1]) << 16) | (int(bytes[offset + 2]) << 8) | int(bytes[offset + 3])


func _thumbnail_dimensions_allowed(width: int, height: int) -> bool:
	return width > 0 and height > 0 and width <= MAX_THUMBNAIL_DIMENSION and height <= MAX_THUMBNAIL_DIMENSION and width <= MAX_THUMBNAIL_PIXELS / height
func save_object_file(filename: String, obj: Variant) -> bool:
	var sp := get_save_path(filename)
	var thumbnail_data := _make_thumbnail_png(null, 120, 90)
	if not thumbnail_data.get("ok", false):
		last_error = "无法生成存档缩略图: %s" % thumbnail_data.get("error", "未知错误")
		return false
	var serialization_state := {"error": "", "objects": [], "next_id": 1, "count": 0}
	var s_data = _serialize_value_checked(obj, [], 0, serialization_state)
	if not str(serialization_state.error).is_empty():
		last_error = "存档对象无法序列化: %s" % serialization_state.error
		push_error(last_error)
		return false
	var thumbnail_file := ""
	var thumbnail_hash := ""
	if thumbnail_data.get("has_image", false):
		thumbnail_file = _new_thumbnail_filename(filename)
		thumbnail_hash = _sha256_bytes(thumbnail_data.get("bytes", PackedByteArray()))
		if thumbnail_hash.is_empty() or not _write_thumbnail_file(save_dir.path_join(thumbnail_file), thumbnail_data.get("bytes", PackedByteArray())):
			last_error = "无法在提交存档前写入校验过的缩略图: %s" % thumbnail_file
			push_error(last_error)
			return false
	var document := {
		"__yzk_save_document__": true,
		"schema_version": SAVE_SCHEMA_VERSION,
		"thumbnail_file": thumbnail_file,
		"thumbnail_sha256": thumbnail_hash,
		"payload": s_data
	}
	var json_str := JSON.stringify(document)
	if json_str.to_utf8_buffer().size() > MAX_SAVE_DOCUMENT_BYTES:
		if not thumbnail_file.is_empty():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(save_dir.path_join(thumbnail_file)))
		last_error = "存档超过大小上限 (%d bytes)。" % MAX_SAVE_DOCUMENT_BYTES
		push_error(last_error)
		return false
	if not write_save_atomically(sp, json_str):
		if not thumbnail_file.is_empty():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(save_dir.path_join(thumbnail_file)))
		return false
	_cleanup_unreferenced_thumbnails(filename)
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
	var candidate_paths: Array[String] = [sp, sp + ".bak"]
	if not FileAccess.file_exists(sp) and not FileAccess.file_exists(sp + ".bak"):
		for directory in [game_dir, game_dir.path_join("system")]:
			if not game_dir.is_empty():
				candidate_paths.append(directory.path_join(filename))
	var saw_document := false
	var failures: Array[String] = []
	for candidate_path in candidate_paths:
		var payload: Variant = _read_save_payload(candidate_path)
		if payload == null:
			continue
		saw_document = true
		if not _validate_save_graph(payload) or not _save_payload_matches_target(payload, target_obj):
			failures.append("%s: 存档结构或目标对象类型无效" % candidate_path)
			continue
		# Build and validate an isolated object graph first. Resource loading and
		# all fallible checks finish before the caller's root is mutated.
		var restore_context := {
			"objects": {},
			"strict_resources": true,
			"defer_runtime_bindings": true,
			"error": ""
		}
		var staged: Variant = deserialize_into(null, payload, vm, restore_context)
		if staged == null or not str(restore_context.get("error", "")).is_empty():
			failures.append("%s: %s" % [candidate_path, str(restore_context.get("error", "未知反序列化错误"))])
			continue
		_rebind_staged_root(staged, target_obj)
		if not _commit_staged_root(target_obj, staged):
			failures.append("%s: 无法提交已验证的存档对象图" % candidate_path)
			continue
		_register_restored_runtime_bindings(target_obj, [])
		print("[CSX Host] Successfully loaded object from: ", candidate_path)
		return true
	last_error = "存档%s: %s" % ["不存在或内容无效" if not saw_document else "恢复失败", "; ".join(failures) if not failures.is_empty() else sp]
	return false


func _commit_staged_root(target: Variant, staged: Variant) -> bool:
	if target == null or staged == null:
		return false
	if target is Array and staged is Array:
		var destination_array: Array = target
		if destination_array.is_typed():
			var required_builtin := destination_array.get_typed_builtin()
			var required_class := destination_array.get_typed_class_name()
			var required_script: Script = destination_array.get_typed_script()
			for item: Variant in staged:
				if required_builtin != TYPE_NIL and typeof(item) != required_builtin:
					return false
				if not required_class.is_empty() and (not item is Object or item.get_class() != required_class):
					return false
				if required_script != null and (not item is Object or item.get_script() != required_script):
					return false
		destination_array.clear()
		for item in staged:
			destination_array.append(item)
		return true
	if target is Dictionary and staged is Dictionary:
		(target as Dictionary).clear()
		for key in staged.keys():
			(target as Dictionary)[key] = staged[key]
		return true
	if target is HostSprite and staged is HostSprite:
		var destination := target as HostSprite
		var source := staged as HostSprite
		var runtime_host := destination.host if destination.host != null else source.host
		destination.filename = source.filename
		destination.archive_hint = source.archive_hint
		destination.position = source.position
		destination.rev_center = source.rev_center
		destination.magnification = source.magnification
		destination.rotation_degrees = source.rotation_degrees
		destination.is_enabled = source.is_enabled
		destination.blending = source.blending
		destination.activation_curves = source.activation_curves
		destination.sprite_parameters = source.sprite_parameters
		destination.message_style = source.message_style
		destination.size = source.size
		destination.z_order = source.z_order
		destination.is_visible = source.is_visible
		destination.transparency = source.transparency
		destination.back_color = source.back_color
		destination.fill_back_color = source.fill_back_color
		destination.movie_rewind_frame = source.movie_rewind_frame
		destination.movie_end_frame = source.movie_end_frame
		destination.movie_repeat = source.movie_repeat
		destination.attached_resource = source.attached_resource
		destination.alpha_resource = source.alpha_resource
		destination.alpha_image = source.alpha_image
		destination.alpha_texture = source.alpha_texture
		destination.alpha_range = source.alpha_range
		destination.animation_loop_count = source.animation_loop_count
		destination.animation_elapsed_ms = source.animation_elapsed_ms
		destination.animation_duration_ms = source.animation_duration_ms
		destination.animation_begin_sequence = source.animation_begin_sequence
		destination.animation_start_sequence = source.animation_start_sequence
		destination.animation_turn_sequence = source.animation_turn_sequence
		destination.animation_rewind_sequence = source.animation_rewind_sequence
		destination.animation_view_frame = source.animation_view_frame
		destination.is_activating = source.is_activating
		destination.activation_duration_ms = source.activation_duration_ms
		destination.activation_elapsed_ms = source.activation_elapsed_ms
		destination.activation_start_alpha = source.activation_start_alpha
		destination.activation_end_alpha = source.activation_end_alpha
		destination.activation_target_alpha = source.activation_target_alpha
		destination.activation_fade_enabled = source.activation_fade_enabled
		destination.activation_action_type = source.activation_action_type
		destination.activation_durations = source.activation_durations
		destination.btn_id = source.btn_id
		destination.full_btn_id = source.full_btn_id
		destination.is_button = source.is_button
		destination.btn_state = source.btn_state
		destination.text_content = source.text_content
		destination.message_char_speed_ms = source.message_char_speed_ms
		destination.message_fade_ms = source.message_fade_ms
		destination.message_elapsed_ms = source.message_elapsed_ms
		destination.message_visible_count = source.message_visible_count
		destination.message_pending = source.message_pending
		destination.is_message_sprite = source.is_message_sprite
		destination.font_bordering = source.font_bordering
		destination.message_cursor_position = source.message_cursor_position
		destination.fields = source.fields
		destination.image = source.image
		destination.texture = source.texture
		destination.animation_frames = source.animation_frames
		destination.animation_frame_sizes = source.animation_frame_sizes.duplicate()
		destination.animation_sequence = source.animation_sequence
		destination.animation_total_time_ms = source.animation_total_time_ms
		destination.tone_filter = source.tone_filter
		if destination.tone_filter != null and destination.tone_filter.host == null:
			destination.tone_filter.host = runtime_host
		if destination.attached_resource != null and destination.attached_resource.host == null:
			destination.attached_resource.host = runtime_host
		if destination.alpha_resource != null and destination.alpha_resource.host == null:
			destination.alpha_resource.host = runtime_host
		destination.button_image_sources = source.button_image_sources
		destination.host = runtime_host
		destination.detach_all_sprites()
		destination.children = source.children
		for child: HostSprite in destination.children:
			child.parent_sprite = destination
		return true
	if target is HostToneFilter and staged is HostToneFilter:
		var destination_filter := target as HostToneFilter
		var source_filter := staged as HostToneFilter
		var runtime_host := destination_filter.host if destination_filter.host != null else source_filter.host
		destination_filter.filter_type = source_filter.filter_type
		destination_filter.tone = source_filter.tone
		destination_filter.red_table = source_filter.red_table.duplicate()
		destination_filter.green_table = source_filter.green_table.duplicate()
		destination_filter.blue_table = source_filter.blue_table.duplicate()
		destination_filter.alpha_table = source_filter.alpha_table.duplicate()
		destination_filter.tone_flags = source_filter.tone_flags
		destination_filter.tone_texture = null
		destination_filter.fields = source_filter.fields
		destination_filter.host = runtime_host
		return true
	if target is HostResource and staged is HostResource:
		var destination := target as HostResource
		var source := staged as HostResource
		var runtime_host := destination.host if destination.host != null else source.host
		if runtime_host != null:
			runtime_host.active_volume_envelopes.erase(destination.get_instance_id())
		destination.name = source.name
		destination.archive_name = source.archive_name
		destination.entry_index = source.entry_index
		destination.unpacked_size = source.unpacked_size
		destination.payload_offset = source.payload_offset
		destination.is_playing = source.is_playing
		destination.current_position = source.current_position
		destination.playback_end_frame = source.playback_end_frame
		destination.playback_rewind_frame = source.playback_rewind_frame
		destination.is_repeating = source.is_repeating
		destination.use_channel_default_loop = source.use_channel_default_loop
		destination.volume_left = source.volume_left
		destination.volume_right = source.volume_right
		destination.play_type = source.play_type
		destination.volume_envelope.assign(source.volume_envelope)
		destination.volume_envelope_duration_ms = source.volume_envelope_duration_ms
		destination.volume_envelope_elapsed_ms = source.volume_envelope_elapsed_ms
		destination.fields = source.fields
		destination.audio_stream = source.audio_stream
		destination.audio_channel = source.audio_channel
		destination.image = source.image
		destination.texture = source.texture
		destination.image_frames = source.image_frames
		destination.image_frame_sequence = source.image_frame_sequence
		destination.image_total_time_ms = source.image_total_time_ms
		destination.host = runtime_host
		return true
	if target is RefCounted and staged is RefCounted and target.get("type_name") != null and staged.get("type_name") != null:
		target.type_name = staged.type_name
		target.fields = staged.fields
		target.field_names = staged.field_names.duplicate()
		return true
	return false


func _rebind_staged_root(staged: Variant, target: Variant) -> void:
	var visited: Array = [staged]
	if staged is Array:
		for index in staged.size():
			staged[index] = _replace_root_references(staged[index], staged, target, visited)
	elif staged is Dictionary:
		for key in staged.keys():
			staged[key] = _replace_root_references(staged[key], staged, target, visited)
	elif staged is HostSprite:
		var sprite := staged as HostSprite
		sprite.fields = _replace_root_references(sprite.fields, staged, target, visited)
		sprite.sprite_parameters = _replace_root_references(sprite.sprite_parameters, staged, target, visited)
		sprite.message_style = _replace_root_references(sprite.message_style, staged, target, visited)
		sprite.activation_curves = _replace_root_references(sprite.activation_curves, staged, target, visited)
		sprite.attached_resource = _replace_root_references(sprite.attached_resource, staged, target, visited)
		sprite.alpha_resource = _replace_root_references(sprite.alpha_resource, staged, target, visited)
		sprite.tone_filter = _replace_root_references(sprite.tone_filter, staged, target, visited)
		sprite.activation_durations = _replace_root_references(sprite.activation_durations, staged, target, visited)
		sprite.button_image_sources = _replace_root_references(sprite.button_image_sources, staged, target, visited)
		sprite.children = _replace_root_references(sprite.children, staged, target, visited)
	elif staged is HostToneFilter:
		var tone_filter := staged as HostToneFilter
		tone_filter.fields = _replace_root_references(tone_filter.fields, staged, target, visited)
	elif staged is HostResource:
		(staged as HostResource).fields = _replace_root_references((staged as HostResource).fields, staged, target, visited)
	elif staged is RefCounted and staged.get("type_name") != null and staged.get("fields") is Dictionary:
		staged.fields = _replace_root_references(staged.fields, staged, target, visited)


func _replace_root_references(value: Variant, old_root: Variant, new_root: Variant, visited: Array) -> Variant:
	if is_same(value, old_root):
		return new_root
	if value == null or not (value is Array or value is Dictionary or value is RefCounted):
		return value
	for seen in visited:
		if is_same(seen, value):
			return value
	visited.append(value)
	if value is Array:
		var array_value: Array = value
		for index in array_value.size():
			array_value[index] = _replace_root_references(array_value[index], old_root, new_root, visited)
	elif value is Dictionary:
		var dictionary_value: Dictionary = value
		for key in dictionary_value.keys():
			dictionary_value[key] = _replace_root_references(dictionary_value[key], old_root, new_root, visited)
	elif value is HostSprite:
		var sprite := value as HostSprite
		sprite.fields = _replace_root_references(sprite.fields, old_root, new_root, visited)
		sprite.sprite_parameters = _replace_root_references(sprite.sprite_parameters, old_root, new_root, visited)
		sprite.message_style = _replace_root_references(sprite.message_style, old_root, new_root, visited)
		sprite.activation_curves = _replace_root_references(sprite.activation_curves, old_root, new_root, visited)
		sprite.attached_resource = _replace_root_references(sprite.attached_resource, old_root, new_root, visited)
		sprite.alpha_resource = _replace_root_references(sprite.alpha_resource, old_root, new_root, visited)
		sprite.tone_filter = _replace_root_references(sprite.tone_filter, old_root, new_root, visited)
		sprite.activation_durations = _replace_root_references(sprite.activation_durations, old_root, new_root, visited)
		sprite.button_image_sources = _replace_root_references(sprite.button_image_sources, old_root, new_root, visited)
		sprite.children = _replace_root_references(sprite.children, old_root, new_root, visited)
	elif value is HostToneFilter:
		var tone_filter := value as HostToneFilter
		tone_filter.fields = _replace_root_references(tone_filter.fields, old_root, new_root, visited)
	elif value is HostResource:
		var resource := value as HostResource
		resource.fields = _replace_root_references(resource.fields, old_root, new_root, visited)
	elif value.get("type_name") != null and value.get("fields") is Dictionary:
		value.fields = _replace_root_references(value.fields, old_root, new_root, visited)
	return value


func _register_restored_runtime_bindings(value: Variant, visited: Array) -> void:
	if value == null or not (value is Array or value is Dictionary or value is RefCounted):
		return
	for seen in visited:
		if is_same(seen, value):
			return
	visited.append(value)
	if value is Array:
		for item in value:
			_register_restored_runtime_bindings(item, visited)
	elif value is Dictionary:
		for item in value.values():
			_register_restored_runtime_bindings(item, visited)
	elif value is HostSprite:
		var sprite := value as HostSprite
		if sprite.host != null:
			sprite.host.active_messages.erase(sprite.get_instance_id())
			sprite.host.active_sprites.erase(sprite.get_instance_id())
			sprite.host.active_animated_sprites.erase(sprite.get_instance_id())
			if sprite.message_pending:
				sprite.host.active_messages[sprite.get_instance_id()] = weakref(sprite)
			if sprite.is_activating:
				sprite.host.active_sprites[sprite.get_instance_id()] = weakref(sprite)
			if sprite.animation_loop_count != 0:
				sprite.host.active_animated_sprites[sprite.get_instance_id()] = weakref(sprite)
		_register_restored_runtime_bindings(sprite.fields, visited)
		_register_restored_runtime_bindings(sprite.sprite_parameters, visited)
		_register_restored_runtime_bindings(sprite.message_style, visited)
		_register_restored_runtime_bindings(sprite.activation_curves, visited)
		_register_restored_runtime_bindings(sprite.activation_durations, visited)
		_register_restored_runtime_bindings(sprite.attached_resource, visited)
		_register_restored_runtime_bindings(sprite.alpha_resource, visited)
		_register_restored_runtime_bindings(sprite.tone_filter, visited)
		_register_restored_runtime_bindings(sprite.button_image_sources, visited)
		_register_restored_runtime_bindings(sprite.children, visited)
	elif value is HostToneFilter:
		_register_restored_runtime_bindings((value as HostToneFilter).fields, visited)
	elif value is HostResource:
		var resource := value as HostResource
		if resource.host != null:
			resource.host.active_volume_envelopes.erase(resource.get_instance_id())
			if resource.is_volume_envelope_pending() != 0:
				resource.host.active_volume_envelopes[resource.get_instance_id()] = weakref(resource)
		_register_restored_runtime_bindings(resource.fields, visited)
	elif value.get("type_name") != null and value.get("fields") is Dictionary:
		_register_restored_runtime_bindings(value.fields, visited)


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
	if not _validate_save_graph(parsed):
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


func _validate_save_graph(value: Variant) -> bool:
	var state := {"count": 0, "ids": {}, "nodes": {}, "refs": [], "typed_refs": []}
	if not _validate_save_graph_node(value, 0, state):
		return false
	for ref_id: Variant in state.refs:
		if not state.ids.has(ref_id):
			return false
	for typed_ref: Dictionary in state.typed_refs:
		if typed_ref.type == "IntegerArray":
			var array_node: Variant = state.nodes.get(typed_ref.id, null)
			if not _validate_integer_array_node(array_node):
				return false
		elif state.ids.get(typed_ref.id, "") != typed_ref.type:
			return false
	return true


static func _normalize_save_object_id(value: Variant) -> String:
	if not (value is int or value is float):
		return ""
	var numeric_id := float(value)
	if not is_finite(numeric_id) or numeric_id <= 0.0 or numeric_id > 250000.0 or numeric_id != floor(numeric_id):
		return ""
	return str(int(numeric_id))


func _validate_encoded_container(value: Variant, expected_type: String, state: Dictionary) -> bool:
	if value is Dictionary and value.has("__ref__"):
		var reference_id := _normalize_save_object_id(value["__ref__"])
		if reference_id.is_empty():
			return false
		state.typed_refs.append({"id": reference_id, "type": expected_type})
		return true
	if expected_type == "Dictionary" and value is Dictionary:
		return not value.has("__type__") or value.get("__type__") == "Dictionary"
	if expected_type == "Array" and value is Array:
		return true
	if not value is Dictionary or value.get("__type__") != expected_type:
		return false
	return true


func _validate_encoded_integer_array(value: Variant, state: Dictionary) -> bool:
	if value is Dictionary and value.has("__ref__"):
		var reference_id := _normalize_save_object_id(value["__ref__"])
		if reference_id.is_empty():
			return false
		state.typed_refs.append({"id": reference_id, "type": "IntegerArray"})
		return true
	if value is Array:
		for item: Variant in value:
			if not _is_save_integer(item):
				return false
		return true
	if not value is Dictionary or value.get("__type__") != "Array":
		return false
	return _validate_integer_array_node(value)


func _validate_integer_array_node(value: Variant) -> bool:
	if not value is Dictionary or value.get("__type__") != "Array":
		return false
	var items: Variant = value.get("items", [])
	if not items is Array:
		return false
	for item: Variant in items:
		if item is Dictionary and item.get("__type__") == "Integer":
			var integer_value: Variant = item.get("value")
			if integer_value is String:
				if not integer_value.is_valid_int():
					return false
			elif not _is_save_integer(integer_value):
				return false
		elif not _is_save_integer(item):
			return false
	return true


func _validate_encoded_button_sources(value: Variant, state: Dictionary) -> bool:
	if not _validate_encoded_container(value, "Dictionary", state):
		return false
	if value is Dictionary and value.has("__ref__"):
		return true
	var sources: Variant = value
	if value is Dictionary and value.get("__type__") == "Dictionary":
		sources = value.get("items", {})
	if not sources is Dictionary:
		return false
	for state_name in sources.keys():
		if state_name not in ["normal", "focus", "pushed", "disabled"]:
			return false
		var descriptor: Variant = sources[state_name]
		if descriptor is Dictionary and descriptor.get("__type__") == "Dictionary":
			descriptor = descriptor.get("items", {})
		if not descriptor is Dictionary:
			return false
		if descriptor.has("filename") and not descriptor["filename"] is String:
			return false
		if descriptor.has("archive_hint") and not descriptor["archive_hint"] is String:
			return false
		if descriptor.has("crop"):
			var crop: Variant = descriptor["crop"]
			if crop is Dictionary and crop.get("__type__") == "Array":
				crop = crop.get("items", [])
			if not crop is Array or crop.size() != 4:
				return false
			for component: Variant in crop:
				if component is Dictionary and component.get("__type__") == "Integer":
					var encoded_value: Variant = component.get("value")
					if encoded_value is String:
						if not encoded_value.is_valid_int():
							return false
					elif not _is_save_integer(encoded_value):
						return false
				elif not _is_save_integer(component):
					return false
	return true


func _validate_sprite_curves(value: Variant) -> bool:
	if value is Dictionary and value.get("__type__") == "Array":
		value = value.get("items", [])
	if not value is Array or value.size() != 3:
		return false
	for curve_index in value.size():
		var curve: Variant = value[curve_index]
		if curve is Dictionary and curve.get("__type__") == "Array":
			curve = curve.get("items", [])
		if not curve is Array:
			return false
		for point: Variant in curve:
			if point is Dictionary and point.get("__type__") == "Array":
				point = point.get("items", [])
			if curve_index == 1:
				if not _is_save_number(point):
					return false
			elif not point is Array or point.size() != 2 or not _is_save_number(point[0]) or not _is_save_number(point[1]):
				return false
	return true


func _validate_save_graph_node(value: Variant, depth: int, state: Dictionary) -> bool:
	if depth > MAX_SERIALIZATION_DEPTH:
		return false
	state.count = int(state.count) + 1
	if int(state.count) > 250000:
		return false
	if value is Array:
		for item in value:
			if not _validate_save_graph_node(item, depth + 1, state):
				return false
		return true
	if not value is Dictionary:
		return true
	if value.has("__ref__"):
		var ref_id: Variant = value["__ref__"]
		var ref_key := _normalize_save_object_id(ref_id)
		if ref_key.is_empty():
			return false
		state.refs.append(ref_key)
		return value.size() == 1
	if value.has("__type__"):
		var type_name := str(value["__type__"])
		if type_name not in ["Integer", "CsxInstance", "HostSprite", "HostToneFilter", "HostResource", "Array", "Dictionary"]:
			return false
		if value.has("__id__"):
			# Integer wrappers are inline scalars, not identity-bearing objects.
			# Accepting an ID here would allow a __ref__ that hydration can never
			# resolve because scalar values are not registered in context.objects.
			if type_name == "Integer":
				return false
			var object_id_key := _normalize_save_object_id(value["__id__"])
			if object_id_key.is_empty():
				return false
			if state.ids.has(object_id_key):
				return false
			state.ids[object_id_key] = type_name
			state.nodes[object_id_key] = value
		match type_name:
			"Integer":
				var integer_value: Variant = value.get("value")
				if integer_value is String:
					return integer_value.is_valid_int()
				return _is_save_integer(integer_value)
			"CsxInstance":
				if not value.get("class_name", "") is String or not value.get("fields", {}) is Dictionary:
					return false
				return _validate_save_graph_node(value.get("fields", {}), depth + 1, state)
			"HostSprite":
				for field_name in ["filename", "archive_hint", "btn_id", "full_btn_id", "btn_state", "text_content"]:
					if value.has(field_name) and not value[field_name] is String:
						return false
				for field_name in ["rotation_degrees", "message_elapsed_ms", "animation_elapsed_ms", "animation_duration_ms"]:
					if value.has(field_name) and not _is_save_number(value[field_name]):
						return false
				for field_name in ["z_order", "transparency", "back_color", "message_char_speed_ms", "message_fade_ms", "message_visible_count", "blending", "alpha_range", "animation_total_time_ms", "animation_begin_sequence", "animation_start_sequence", "animation_turn_sequence", "animation_rewind_sequence", "animation_view_frame", "animation_loop_count", "movie_rewind_frame", "movie_end_frame"]:
					if value.has(field_name) and not _is_save_integer(value[field_name]):
						return false
				for field_name in ["is_visible", "is_enabled", "fill_back_color", "is_button", "message_pending", "movie_repeat", "is_message_sprite", "font_bordering"]:
					if value.has(field_name) and not value[field_name] is bool:
						return false
				for field_name in ["children", "attached_resource", "alpha_resource", "activation_state", "tone_filter", "button_image_sources", "animation_frame_sizes", "activation_curves", "animation_sequence"]:
					if value.has(field_name) and not _validate_save_graph_node(value[field_name], depth + 1, state):
						return false
				for field_name in ["sprite_parameters", "message_style", "fields", "button_image_sources"]:
					if value.has(field_name) and not _validate_encoded_container(value[field_name], "Dictionary", state):
						return false
				if value.has("activation_curves") and not _validate_sprite_curves(value["activation_curves"]):
					return false
				if value.has("animation_sequence") and not _validate_encoded_integer_array(value["animation_sequence"], state):
					return false
				if value.has("button_image_sources") and not _validate_encoded_button_sources(value["button_image_sources"], state):
					return false
				if value.has("tone_filter") and value["tone_filter"] != null:
					if not _validate_encoded_container(value["tone_filter"], "HostToneFilter", state):
						return false
				if value.has("animation_frame_sizes"):
					var frame_sizes: Variant = value["animation_frame_sizes"]
					if not frame_sizes is Array:
						return false
					for frame_size: Variant in frame_sizes:
						if not frame_size is Array or frame_size.size() != 2 or not _is_save_integer(frame_size[0]) or not _is_save_integer(frame_size[1]) or int(frame_size[0]) <= 0 or int(frame_size[1]) <= 0:
							return false
				for field_name in ["attached_resource", "alpha_resource"]:
					if value.has(field_name) and value[field_name] != null:
						if not _validate_encoded_container(value[field_name], "HostResource", state):
							return false
				for field_name in ["position", "rev_center", "magnification", "size", "message_cursor_position"]:
					if value.has(field_name):
						var vector_value: Variant = value[field_name]
						if not vector_value is Array or vector_value.size() != 2:
							return false
						for component in vector_value:
							if not _is_save_number(component):
								return false
				if value.has("activation_state"):
					var activation: Variant = value["activation_state"]
					if not activation is Dictionary:
						return false
					for field_name in ["duration_ms", "elapsed_ms"]:
						if activation.has(field_name) and not _is_save_number(activation[field_name]):
							return false
					for field_name in ["start_alpha", "end_alpha", "target_alpha", "action_type"]:
						if activation.has(field_name) and not _is_save_integer(activation[field_name]):
							return false
					for field_name in ["is_activating", "fade_enabled"]:
						if activation.has(field_name) and not activation[field_name] is bool:
							return false
				return true
			"HostToneFilter":
				if value.has("filter_type") and not value["filter_type"] is String:
					return false
				if value.has("tone_flags") and not _is_save_integer(value["tone_flags"]):
					return false
				if value.has("tone"):
					var tone_values: Variant = value["tone"]
					if not tone_values is Array or tone_values.size() != 4:
						return false
					for component: Variant in tone_values:
						if not _is_save_number(component):
							return false
				for field_name in ["red_table", "green_table", "blue_table", "alpha_table"]:
					if not value.has(field_name) or not value[field_name] is Array or value[field_name].size() != 256:
						return false
					for table_value: Variant in value[field_name]:
						if not _is_save_integer(table_value) or int(table_value) < 0 or int(table_value) > 255:
							return false
				if value.has("fields"):
					return _validate_save_graph_node(value["fields"], depth + 1, state) and _validate_encoded_container(value["fields"], "Dictionary", state)
				return true
			"HostResource":
				for field_name in ["name", "archive_name"]:
					if value.has(field_name) and not value[field_name] is String:
						return false
				for field_name in ["entry_index", "unpacked_size", "payload_offset", "position_frames", "current_position", "playback_end_frame", "playback_rewind_frame"]:
					if value.has(field_name) and not _is_save_integer(value[field_name]):
						return false
				for field_name in ["is_playing", "is_repeating", "use_channel_default_loop"]:
					if value.has(field_name) and not value[field_name] is bool:
						return false
				for field_name in ["volume_left", "volume_right"]:
					if value.has(field_name) and not _is_save_number(value[field_name]):
						return false
				if value.has("play_type") and (
						not _is_save_integer(value["play_type"])
						or int(value["play_type"]) not in [AUDIO_PLAY_TYPE_DEVICE, AUDIO_PLAY_TYPE_NONE, AUDIO_PLAY_TYPE_MUSIC, AUDIO_PLAY_TYPE_SOUND, AUDIO_PLAY_TYPE_VOICE, AUDIO_PLAY_TYPE_SYSTEM]
					):
					return false
				var envelope_keys := ["volume_envelope", "volume_envelope_duration_ms", "volume_envelope_elapsed_ms"]
				var has_envelope_state := false
				for envelope_key: String in envelope_keys:
					has_envelope_state = has_envelope_state or value.has(envelope_key)
				if has_envelope_state:
					if not value.has("volume_envelope") or not value.has("volume_envelope_duration_ms") or not value.has("volume_envelope_elapsed_ms"):
						return false
					var envelope: Variant = value["volume_envelope"]
					var duration: Variant = value["volume_envelope_duration_ms"]
					var elapsed: Variant = value["volume_envelope_elapsed_ms"]
					if not envelope is Array or (envelope.size() != 0 and envelope.size() != 4):
						return false
					if not _is_save_number(duration) or not _is_save_number(elapsed) or float(duration) < 0.0 or float(elapsed) < 0.0:
						return false
					if envelope.is_empty():
						if float(duration) != 0.0 or float(elapsed) != 0.0:
							return false
					else:
						if float(duration) <= 0.0 or float(elapsed) >= float(duration):
							return false
						for point: Variant in envelope:
							if not point is Array or point.size() != 2 or not _is_save_number(point[0]) or not _is_save_number(point[1]):
								return false
				if value.has("fields"):
					return value["fields"] is Dictionary and _validate_save_graph_node(value["fields"], depth + 1, state)
				return true
			"Array":
				if not value.get("items", []) is Array:
					return false
				return _validate_save_graph_node(value.get("items", []), depth + 1, state)
			"Dictionary":
				if value.has("entries"):
					var entries: Variant = value["entries"]
					if not entries is Array:
						return false
					for entry in entries:
						if not entry is Array or entry.size() != 2:
							return false
						if not _validate_save_graph_node(entry[0], depth + 1, state) or not _validate_save_graph_node(entry[1], depth + 1, state):
							return false
					return true
				if not value.get("items", {}) is Dictionary:
					return false
				return _validate_save_graph_node(value.get("items", {}), depth + 1, state)
	for key in value.keys():
		if not _validate_save_graph_node(value[key], depth + 1, state):
			return false
	return true


static func _is_save_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _is_save_integer(value: Variant) -> bool:
	return _is_save_number(value) and float(value) == floor(float(value))


func _save_payload_matches_target(payload: Variant, target: Variant) -> bool:
	if target == null or not payload is Dictionary or not payload.has("__type__"):
		return true
	match str(payload["__type__"]):
		"CsxInstance":
			return target is RefCounted and target.has_method("get_field") and target.has_method("set_field") and target.get("type_name") == str(payload.get("class_name", ""))
		"HostSprite":
			return target is HostSprite
		"HostResource":
			return target is HostResource
		"HostToneFilter":
			return target is HostToneFilter
		"Array":
			return target is Array
		"Dictionary":
			return target is Dictionary
		"Integer":
			return false
	return true


static func serialize_value(val: Variant) -> Variant:
	var state := {"error": "", "objects": [], "next_id": 1, "count": 0}
	var result: Variant = _serialize_value_checked(val, [], 0, state)
	return null if not str(state.error).is_empty() else result


static func _serialize_sprite_activation_curves(curves: Array, active_stack: Array, depth: int, state: Dictionary) -> Variant:
	var packed_curves: Array = []
	if curves.size() != 3:
		state.error = "HostSprite 激活曲线必须包含三条通道。"
		return null
	for curve_index in curves.size():
		var curve: Variant = curves[curve_index]
		if not curve is Array:
			state.error = "HostSprite 激活曲线格式无效。"
			return null
		var packed_curve: Array = []
		for point: Variant in curve:
			if point is Vector2:
				if curve_index == 1:
					state.error = "HostSprite 旋转曲线点必须是数字。"
					return null
				packed_curve.append([point.x, point.y])
			elif point is int or point is float:
				if curve_index != 1:
					state.error = "HostSprite 位置和缩放曲线点必须是 Vector2。"
					return null
				packed_curve.append(point)
			else:
				state.error = "HostSprite 激活曲线点类型无效。"
				return null
		packed_curves.append(packed_curve)
	return packed_curves


static func _pack_byte_table(table: PackedByteArray) -> Array:
	var packed: Array = []
	for value in table:
		packed.append(int(value))
	return packed


static func _serialize_sprite_frame_sizes(sprite: HostSprite) -> Array:
	var sizes: Array = []
	if not sprite.animation_frames.is_empty():
		for frame: Image in sprite.animation_frames:
			sizes.append([frame.get_width(), frame.get_height()])
	else:
		for frame_size: Vector2i in sprite.animation_frame_sizes:
			sizes.append([frame_size.x, frame_size.y])
	return sizes


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
		return {"__type__": "Integer", "value": str(val)}
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
				"is_enabled": sprite.is_enabled,
				"blending": sprite.blending,
				"activation_curves": _serialize_sprite_activation_curves(sprite.activation_curves, active_stack, depth + 1, state),
				"sprite_parameters": _serialize_value_checked(sprite.sprite_parameters, active_stack, depth + 1, state),
				"message_style": _serialize_value_checked(sprite.message_style, active_stack, depth + 1, state),
				"size": [sprite.size.x, sprite.size.y],
				"z_order": sprite.z_order,
				"is_visible": sprite.is_visible,
				"transparency": sprite.transparency,
				"back_color": sprite.back_color,
				"fill_back_color": sprite.fill_back_color,
				"movie_rewind_frame": sprite.movie_rewind_frame,
				"movie_end_frame": sprite.movie_end_frame,
				"movie_repeat": sprite.movie_repeat,
				"attached_resource": _serialize_value_checked(sprite.attached_resource, active_stack, depth + 1, state),
				"alpha_resource": _serialize_value_checked(sprite.alpha_resource, active_stack, depth + 1, state),
				"alpha_range": sprite.alpha_range,
				"animation_loop_count": sprite.animation_loop_count,
				"animation_elapsed_ms": sprite.animation_elapsed_ms,
				"animation_duration_ms": sprite.animation_duration_ms,
				"animation_begin_sequence": sprite.animation_begin_sequence,
				"animation_start_sequence": sprite.animation_start_sequence,
				"animation_turn_sequence": sprite.animation_turn_sequence,
				"animation_rewind_sequence": sprite.animation_rewind_sequence,
				"animation_view_frame": sprite.animation_view_frame,
				"animation_total_time_ms": sprite.animation_total_time_ms,
				"animation_frame_sizes": _serialize_sprite_frame_sizes(sprite),
				"animation_sequence": _serialize_value_checked(sprite.animation_sequence, active_stack, depth + 1, state),
				"activation_state": {
					"is_activating": sprite.is_activating,
					"duration_ms": sprite.activation_duration_ms,
					"elapsed_ms": sprite.activation_elapsed_ms,
					"start_alpha": sprite.activation_start_alpha,
					"end_alpha": sprite.activation_end_alpha,
					"target_alpha": sprite.activation_target_alpha,
					"fade_enabled": sprite.activation_fade_enabled,
					"action_type": sprite.activation_action_type,
					"durations": _serialize_value_checked(sprite.activation_durations, active_stack, depth + 1, state)
				},
				"btn_id": sprite.btn_id,
				"full_btn_id": sprite.full_btn_id,
				"button_image_sources": _serialize_value_checked(sprite.button_image_sources, active_stack, depth + 1, state),
				"is_button": sprite.is_button,
				"btn_state": sprite.btn_state,
				"text_content": sprite.text_content,
				"message_char_speed_ms": sprite.message_char_speed_ms,
				"message_fade_ms": sprite.message_fade_ms,
				"message_elapsed_ms": sprite.message_elapsed_ms,
				"message_visible_count": sprite.message_visible_count,
				"message_pending": sprite.message_pending,
				"is_message_sprite": sprite.is_message_sprite,
				"font_bordering": sprite.font_bordering,
				"message_cursor_position": [sprite.message_cursor_position.x, sprite.message_cursor_position.y],
				"tone_filter": _serialize_value_checked(sprite.tone_filter, active_stack, depth + 1, state),
				"children": _serialize_value_checked(sprite.children, active_stack, depth + 1, state),
				"fields": _serialize_value_checked(sprite.fields, active_stack, depth + 1, state)
			}
		elif val is HostToneFilter:
			var tone_filter: HostToneFilter = val
			result = {
				"__type__": "HostToneFilter",
				"__id__": object_id,
				"filter_type": tone_filter.filter_type,
				"tone": [tone_filter.tone.r, tone_filter.tone.g, tone_filter.tone.b, tone_filter.tone.a],
				"tone_flags": tone_filter.tone_flags,
				"red_table": _pack_byte_table(tone_filter.red_table),
				"green_table": _pack_byte_table(tone_filter.green_table),
				"blue_table": _pack_byte_table(tone_filter.blue_table),
				"alpha_table": _pack_byte_table(tone_filter.alpha_table),
				"fields": _serialize_value_checked(tone_filter.fields, active_stack, depth + 1, state)
			}
		elif val is HostResource:
			var resource: HostResource = val
			var serialized_envelope: Array = []
			for point: Vector2 in resource.volume_envelope:
				serialized_envelope.append([point.x, point.y])
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
				"play_type": resource.play_type,
				"volume_envelope": serialized_envelope,
				"volume_envelope_duration_ms": resource.volume_envelope_duration_ms,
				"volume_envelope_elapsed_ms": resource.volume_envelope_elapsed_ms,
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
		var all_string_keys := true
		for key in val.keys():
			if not key is String:
				all_string_keys = false
				break
		if all_string_keys:
			var serialized_dictionary: Dictionary = {}
			for key in val.keys():
				serialized_dictionary[key] = _serialize_value_checked(val[key], active_stack, depth + 1, state)
			result = {"__type__": "Dictionary", "__id__": object_id, "items": serialized_dictionary}
		else:
			var entries: Array = []
			for key in val.keys():
				if not (key is String or key is int or key is float or key is bool):
					state.error = "不支持的字典键类型 %s" % type_string(typeof(key))
					return null
				entries.append([
					_serialize_value_checked(key, active_stack, depth + 1, state),
					_serialize_value_checked(val[key], active_stack, depth + 1, state)
				])
			result = {"__type__": "Dictionary", "__id__": object_id, "entries": entries}
	else:
		state.error = "不支持的 Variant 类型 %s" % type_string(typeof(val))
	return result


static func _prepare_deserialization_context(data: Variant, target: Variant, vm: RefCounted, context: Dictionary) -> void:
	context["objects"] = {}
	context["hydrating"] = {}
	context["_prepared"] = true
	if data is Dictionary and data.has("__id__") and target != null:
		var target_id := _normalize_save_object_id(data["__id__"])
		if target_id.is_empty():
			_set_restore_error(context, "存档对象 ID 格式无效。")
			return
		context.objects[target_id] = target
	_preallocate_deserialization_objects(data, vm, context)


static func _preallocate_deserialization_objects(value: Variant, vm: RefCounted, context: Dictionary) -> void:
	if value is Array:
		for item in value:
			_preallocate_deserialization_objects(item, vm, context)
		return
	if not value is Dictionary:
		return
	if value.has("__type__") and value.has("__id__"):
		var id_key := _normalize_save_object_id(value["__id__"])
		if id_key.is_empty():
			_set_restore_error(context, "存档对象 ID 格式无效。")
			return
		if not context.objects.has(id_key):
			var type_name := str(value["__type__"])
			var object: Variant = null
			match type_name:
				"CsxInstance":
					var saved_class_name := str(value.get("class_name", ""))
					# Save restoration allocates a data shell; it must not execute the
					# script constructor and repeat story side effects.
					object = load("res://scripts/csx_vm.gd").CsxInstance.new(saved_class_name)
				"HostSprite":
					object = HostSprite.new(0, _host_from_vm(vm))
				"HostToneFilter":
					object = HostToneFilter.new(_host_from_vm(vm))
				"HostResource":
					object = HostResource.new(str(value.get("name", "")), str(value.get("archive_name", "")), int(value.get("entry_index", -1)), int(value.get("unpacked_size", 0)), int(value.get("payload_offset", 0)), _host_from_vm(vm))
				"Array":
					object = []
				"Dictionary":
					object = {}
			if object != null:
				context.objects[id_key] = object
	for key in value.keys():
		_preallocate_deserialization_objects(value[key], vm, context)


static func deserialize_into(target: Variant, data: Variant, vm: RefCounted = null, context: Dictionary = {}) -> Variant:
	if data == null or not str(context.get("error", "")).is_empty():
		return null
	if not context.get("_prepared", false):
		_prepare_deserialization_context(data, target, vm, context)
	if data is Dictionary and data.has("__ref__"):
		var reference_key := _normalize_save_object_id(data["__ref__"])
		if reference_key.is_empty():
			_set_restore_error(context, "存档对象引用 ID 格式无效。")
			return null
		return context.objects.get(reference_key, null)
	if data is Dictionary and data.has("__type__"):
		var t_type: String = data["__type__"]
		if t_type == "Integer":
			var saved_integer: Variant = data.get("value", 0)
			return int(saved_integer) if saved_integer is int or saved_integer is float or (saved_integer is String and saved_integer.is_valid_int()) else 0
		if t_type == "CsxInstance":
			var cname: String = data.get("class_name", "")
			var fields_data: Dictionary = data.get("fields", {})
			var object_key := _normalize_save_object_id(data.get("__id__", 0))
			var inst: Variant = context.objects.get(object_key, target)
			if not (inst != null and inst.get_script() != null and inst.get("type_name") != null):
				var CsxVMClass = load("res://scripts/csx_vm.gd")
				inst = CsxVMClass.CsxInstance.new(cname)
			if data.has("__id__"):
				context.objects[object_key] = inst
				context.hydrating[object_key] = true
			inst.type_name = cname
			inst.fields.clear()
			inst.field_names.clear()
			for k in fields_data.keys():
				inst.fields[k] = deserialize_value(fields_data[k], vm, context)
				inst.field_names.append(str(k))
			return inst
		elif t_type == "HostSprite":
			var object_key := _normalize_save_object_id(data.get("__id__", 0))
			var sprite: HostSprite = context.objects.get(object_key, target) as HostSprite
			if sprite == null:
				sprite = HostSprite.new(0, _host_from_vm(vm))
			if vm != null:
				sprite.host = _host_from_vm(vm)
			if data.has("__id__"):
				context.objects[object_key] = sprite
				context.hydrating[object_key] = true
			sprite.filename = str(data.get("filename", ""))
			sprite.archive_hint = str(data.get("archive_hint", ""))
			var pos: Array = data.get("position", [0, 0])
			sprite.position = Vector2i(int(pos[0]), int(pos[1])) if pos.size() >= 2 else Vector2i.ZERO
			var center: Array = data.get("rev_center", [0, 0])
			sprite.rev_center = Vector2i(int(center[0]), int(center[1])) if center.size() >= 2 else Vector2i.ZERO
			var magnification: Array = data.get("magnification", [1.0, 1.0])
			sprite.magnification = Vector2(float(magnification[0]), float(magnification[1])) if magnification.size() >= 2 else Vector2.ONE
			sprite.rotation_degrees = float(data.get("rotation_degrees", 0.0))
			sprite.is_enabled = bool(data.get("is_enabled", true))
			sprite.blending = int(data.get("blending", 0))
			var saved_curves: Variant = deserialize_value(data.get("activation_curves", [[], [], []]), vm, context)
			if saved_curves is Array:
				sprite.activation_curves = saved_curves
				for curve_index in [0, 2]:
					if curve_index < sprite.activation_curves.size() and sprite.activation_curves[curve_index] is Array:
						var restored_curve: Array = sprite.activation_curves[curve_index]
						for point_index in restored_curve.size():
							var restored_point: Variant = restored_curve[point_index]
							if restored_point is Array and restored_point.size() == 2:
								restored_curve[point_index] = Vector2(float(restored_point[0]), float(restored_point[1]))
			else:
				sprite.activation_curves = [[], [], []]
			if data.has("sprite_parameters"):
				var saved_parameters: Variant = deserialize_value(data["sprite_parameters"], vm, context)
				if saved_parameters is Dictionary:
					sprite.sprite_parameters = saved_parameters
			else:
				sprite.sprite_parameters = {"nFlags": 0, "rCrossingAngle": 90.0, "rgbDimColor": 0, "rgbLightColor": 0xffffff, "rZOrder": 0.0, "rgbColorParam1": 0, "rZScale": 0.0}
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
			sprite.movie_rewind_frame = int(data.get("movie_rewind_frame", -1))
			sprite.movie_end_frame = int(data.get("movie_end_frame", -1))
			sprite.movie_repeat = bool(data.get("movie_repeat", false))
			var attached: Variant = deserialize_value(data.get("attached_resource"), vm, context)
			sprite.attached_resource = attached as HostResource if attached is HostResource else null
			if data.get("attached_resource") != null and not attached is HostResource:
				_set_restore_error(context, "HostSprite attached_resource 不是 HostResource。")
			var alpha: Variant = deserialize_value(data.get("alpha_resource"), vm, context)
			sprite.alpha_resource = alpha as HostResource if alpha is HostResource else null
			if data.get("alpha_resource") != null and not alpha is HostResource:
				_set_restore_error(context, "HostSprite alpha_resource 不是 HostResource。")
			sprite.alpha_range = int(data.get("alpha_range", 256))
			sprite.animation_loop_count = int(data.get("animation_loop_count", 0))
			sprite.animation_elapsed_ms = maxf(0.0, float(data.get("animation_elapsed_ms", 0.0)))
			sprite.animation_duration_ms = maxf(0.0, float(data.get("animation_duration_ms", 0.0)))
			sprite.animation_begin_sequence = int(data.get("animation_begin_sequence", 0))
			sprite.animation_start_sequence = int(data.get("animation_start_sequence", sprite.animation_begin_sequence))
			sprite.animation_turn_sequence = int(data.get("animation_turn_sequence", -1))
			sprite.animation_rewind_sequence = int(data.get("animation_rewind_sequence", 0))
			sprite.animation_view_frame = int(data.get("animation_view_frame", -1))
			sprite.animation_total_time_ms = int(data.get("animation_total_time_ms", sprite.animation_total_time_ms))
			var saved_frame_sizes: Variant = data.get("animation_frame_sizes", [])
			if saved_frame_sizes is Array:
				sprite.animation_frame_sizes.clear()
				for frame_size: Array in saved_frame_sizes:
					sprite.animation_frame_sizes.append(Vector2i(int(frame_size[0]), int(frame_size[1])))
			var expected_frame_sizes: Array[Vector2i] = sprite.animation_frame_sizes.duplicate()
			var saved_sequence: Variant = deserialize_value(data.get("animation_sequence", sprite.animation_sequence), vm, context)
			if saved_sequence is Array:
				sprite.animation_sequence.assign(saved_sequence)
			var activation_state: Variant = data.get("activation_state", {})
			if activation_state is Dictionary:
				sprite.is_activating = bool(activation_state.get("is_activating", false))
				sprite.activation_duration_ms = maxf(0.0, float(activation_state.get("duration_ms", 0.0)))
				sprite.activation_elapsed_ms = maxf(0.0, float(activation_state.get("elapsed_ms", 0.0)))
				sprite.activation_start_alpha = int(activation_state.get("start_alpha", 0))
				sprite.activation_end_alpha = int(activation_state.get("end_alpha", 0))
				sprite.activation_target_alpha = int(activation_state.get("target_alpha", 0))
				sprite.activation_fade_enabled = bool(activation_state.get("fade_enabled", false))
				sprite.activation_action_type = int(activation_state.get("action_type", 0))
				var saved_durations: Variant = deserialize_value(activation_state.get("durations", []), vm, context)
				if saved_durations is Array:
					for duration: Variant in saved_durations:
						if not _is_save_number(duration):
							_set_restore_error(context, "HostSprite 激活时长列表包含非数字值。")
							break
						sprite.activation_durations.append(float(duration))
				else:
					_set_restore_error(context, "HostSprite 激活时长列表格式无效。")
			sprite.btn_id = str(data.get("btn_id", ""))
			sprite.full_btn_id = str(data.get("full_btn_id", sprite.btn_id))
			var saved_button_sources: Variant = deserialize_value(data.get("button_image_sources", {}), vm, context)
			sprite.button_image_sources = saved_button_sources if saved_button_sources is Dictionary else {}
			sprite.is_button = bool(data.get("is_button", false))
			sprite.btn_state = str(data.get("btn_state", "normal"))
			sprite.text_content = str(data.get("text_content", ""))
			sprite.message_char_speed_ms = maxi(0, int(data.get("message_char_speed_ms", 0)))
			sprite.message_fade_ms = maxi(0, int(data.get("message_fade_ms", 0)))
			sprite.message_elapsed_ms = maxf(0.0, float(data.get("message_elapsed_ms", 0.0)))
			sprite.message_visible_count = clampi(int(data.get("message_visible_count", sprite.display_text().length())), -1, sprite.display_text().length())
			sprite.message_pending = bool(data.get("message_pending", false))
			sprite.is_message_sprite = bool(data.get("is_message_sprite", false))
			sprite.font_bordering = bool(data.get("font_bordering", false))
			var cursor_position: Array = data.get("message_cursor_position", [0, 0])
			sprite.message_cursor_position = Vector2i(int(cursor_position[0]), int(cursor_position[1])) if cursor_position.size() >= 2 else Vector2i.ZERO
			var saved_tone_filter: Variant = deserialize_value(data.get("tone_filter"), vm, context)
			if saved_tone_filter is HostToneFilter:
				sprite.tone_filter = saved_tone_filter
				if sprite.tone_filter.host == null:
					sprite.tone_filter.host = sprite.host
			elif data.get("tone_filter") != null:
				_set_restore_error(context, "HostSprite tone_filter 不是 HostToneFilter。")
			if sprite.message_pending and sprite.host != null and not context.get("defer_runtime_bindings", false):
				sprite.host.active_messages[sprite.get_instance_id()] = weakref(sprite)
			sprite.fields = deserialize_value(data.get("fields", {}), vm, context) if data.get("fields", {}) is Dictionary else {}
			sprite.detach_all_sprites()
			var saved_children: Variant = deserialize_value(data.get("children", {"__type__": "Array", "items": []}), vm, context)
			if saved_children is Array:
				sprite.children = saved_children
				for child: Variant in saved_children:
					if not child is HostSprite:
						_set_restore_error(context, "HostSprite 子节点不是有效精灵对象。")
						break
					if child.parent_sprite != null and child.parent_sprite != sprite:
						_set_restore_error(context, "HostSprite 子节点被多个父精灵引用。")
						break
					sprite.add_sprite(child.z_order, child)
					if child.parent_sprite != sprite:
						_set_restore_error(context, "HostSprite 子节点关系形成循环。")
						break
			elif data.has("children"):
				_set_restore_error(context, "HostSprite 子节点列表格式无效。")
			if not sprite.filename.is_empty() and sprite.host != null and sprite.filename.get_extension().to_lower() == "eri":
				var image_res := sprite.host.load_image(sprite.filename, sprite.archive_hint)
				if image_res.get("ok", false):
					sprite.image = image_res["image"]
					sprite.texture = image_res["texture"]
					sprite.animation_frames.clear()
					for frame: Variant in image_res.get("frames", [sprite.image]):
						if frame is Image:
							sprite.animation_frames.append(frame)
					sprite.animation_frame_sizes.clear()
					for frame: Image in sprite.animation_frames:
						sprite.animation_frame_sizes.append(Vector2i(frame.get_size()))
					if not data.has("animation_sequence"):
						sprite.animation_sequence.assign(image_res.get("frame_sequence", []))
						sprite.animation_total_time_ms = int(image_res.get("total_time_ms", sprite.animation_total_time_ms))
				elif context.get("strict_resources", false):
					_set_restore_error(context, "无法恢复 HostSprite 图像 %s: %s" % [sprite.filename, image_res.get("error", "资源缺失或解码失败")])
			elif not sprite.filename.is_empty() and sprite.filename.get_extension().to_lower() == "eri" and context.get("strict_resources", false):
				_set_restore_error(context, "无法恢复 HostSprite 图像 %s: VM 未绑定 Host" % sprite.filename)
			if sprite.attached_resource != null:
				if sprite.attached_resource.image == null and not sprite.attached_resource.name.is_empty():
					sprite.attached_resource.load_image(sprite.attached_resource.name)
				if sprite.attached_resource.image != null:
					sprite.image = sprite.attached_resource.image
					sprite.texture = sprite.attached_resource.texture
					sprite.animation_frames.assign(sprite.attached_resource.image_frames)
					sprite.animation_frame_sizes.clear()
					for frame: Image in sprite.animation_frames:
						sprite.animation_frame_sizes.append(Vector2i(frame.get_size()))
					if not data.has("animation_sequence"):
						sprite.animation_sequence.assign(sprite.attached_resource.image_frame_sequence)
						sprite.animation_total_time_ms = sprite.attached_resource.image_total_time_ms
			if not expected_frame_sizes.is_empty():
				if sprite.animation_frames.size() != expected_frame_sizes.size():
					sprite.animation_frame_sizes = expected_frame_sizes
					if context.get("strict_resources", false):
						_set_restore_error(context, "HostSprite 动画帧像素无法从存档资源描述符恢复。")
				else:
					for frame_index in sprite.animation_frames.size():
						var frame: Image = sprite.animation_frames[frame_index]
						if Vector2i(frame.get_size()) != expected_frame_sizes[frame_index] and context.get("strict_resources", false):
							_set_restore_error(context, "HostSprite 动画帧尺寸与保存的元数据不符。")
					sprite.animation_frame_sizes = expected_frame_sizes
			if sprite.animation_view_frame >= 0:
				if sprite.animation_view_frame < sprite.animation_frames.size():
					sprite.image = sprite.animation_frames[sprite.animation_view_frame]
					sprite.texture = ImageTexture.create_from_image(sprite.image)
				elif context.get("strict_resources", false):
					_set_restore_error(context, "HostSprite 当前动画帧索引越界。")
			if sprite.alpha_resource != null:
				sprite.set_alpha_image(sprite.alpha_resource, sprite.alpha_range)
			_restore_sprite_button_images(sprite, context)
			if sprite.animation_loop_count != 0 and sprite.host != null and not context.get("defer_runtime_bindings", false):
				sprite.host.active_animated_sprites[sprite.get_instance_id()] = weakref(sprite)
			if sprite.is_activating and sprite.host != null and not context.get("defer_runtime_bindings", false):
				sprite.host.active_sprites[sprite.get_instance_id()] = weakref(sprite)
			return sprite
		elif t_type == "HostToneFilter":
			var object_key := _normalize_save_object_id(data.get("__id__", 0))
			var tone_filter: HostToneFilter = context.objects.get(object_key, target) as HostToneFilter
			if tone_filter == null:
				tone_filter = HostToneFilter.new(_host_from_vm(vm))
			if data.has("__id__"):
				context.objects[object_key] = tone_filter
				context.hydrating[object_key] = true
			tone_filter.host = _host_from_vm(vm) if _host_from_vm(vm) != null else tone_filter.host
			tone_filter.filter_type = str(data.get("filter_type", "NORMAL")).to_upper()
			var tone_values: Array = data.get("tone", [1.0, 1.0, 1.0, 1.0])
			if tone_values.size() == 4:
				tone_filter.tone = Color(float(tone_values[0]), float(tone_values[1]), float(tone_values[2]), float(tone_values[3]))
			for channel_name in ["red_table", "green_table", "blue_table", "alpha_table"]:
				var table_values: Variant = data.get(channel_name, [])
				var restored_table := PackedByteArray()
				if not table_values is Array or table_values.size() != 256:
					_set_restore_error(context, "HostToneFilter %s 表格长度无效。" % channel_name)
					continue
				for table_value: Variant in table_values:
					if not _is_save_integer(table_value) or int(table_value) < 0 or int(table_value) > 255:
						_set_restore_error(context, "HostToneFilter %s 表格含无效值。" % channel_name)
						break
					restored_table.append(int(table_value))
				if restored_table.size() == 256:
					tone_filter.set(channel_name, restored_table)
			tone_filter.tone_flags = int(data.get("tone_flags", 0))
			var saved_fields: Variant = deserialize_value(data.get("fields", {}), vm, context)
			if saved_fields is Dictionary:
				tone_filter.fields = saved_fields
			tone_filter.tone_texture = null
			return tone_filter
		elif t_type == "HostResource":
			var resource_host := _host_from_vm(vm)
			var object_key := _normalize_save_object_id(data.get("__id__", 0))
			var resource: HostResource = context.objects.get(object_key, target) as HostResource
			if resource == null:
				resource = HostResource.new(
				str(data.get("name", "")),
				str(data.get("archive_name", "")),
				int(data.get("entry_index", -1)),
				int(data.get("unpacked_size", 0)),
				int(data.get("payload_offset", 0)),
				resource_host
				)
			resource.host = resource_host if resource_host != null else resource.host
			if data.has("__id__"):
				context.objects[object_key] = resource
				context.hydrating[object_key] = true
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
			resource.play_type = int(data.get("play_type", AUDIO_PLAY_TYPE_NONE))
			resource.volume_envelope.clear()
			var saved_envelope: Variant = data.get("volume_envelope", [])
			if saved_envelope is Array:
				for point: Variant in saved_envelope:
					if point is Array and point.size() == 2 and _is_save_number(point[0]) and _is_save_number(point[1]):
						resource.volume_envelope.append(Vector2(float(point[0]), float(point[1])))
					else:
						_set_restore_error(context, "HostResource 音量包络控制点格式无效。")
						break
			elif data.has("volume_envelope"):
				_set_restore_error(context, "HostResource 音量包络格式无效。")
			resource.volume_envelope_duration_ms = float(data.get("volume_envelope_duration_ms", 0.0))
			resource.volume_envelope_elapsed_ms = float(data.get("volume_envelope_elapsed_ms", 0.0))
			resource.fields = deserialize_value(data.get("fields", {}), vm, context) if data.get("fields", {}) is Dictionary else {}
			if resource_host != null:
				var extension := resource.name.get_extension().to_lower()
				if extension == "mio":
					var sound_loaded := resource.load_sound(resource.name) != 0
					if not sound_loaded and context.get("strict_resources", false):
						_set_restore_error(context, "无法恢复 HostResource 音频 %s: %s" % [resource.name, resource_host.last_error])
					if not data.has("position_frames") and resource.audio_stream != null:
						var legacy_msec := float(data.get("current_position", 0))
						resource.current_position = roundi(legacy_msec * resource.audio_stream.mix_rate / 1000.0)
				elif extension == "eri":
					if resource.load_image(resource.name) == 0 and context.get("strict_resources", false):
						_set_restore_error(context, "无法恢复 HostResource 图像 %s" % resource.name)
			elif not resource.name.is_empty() and resource.name.get_extension().to_lower() in ["mio", "eri"] and context.get("strict_resources", false):
				_set_restore_error(context, "无法恢复 HostResource %s: VM 未绑定 Host" % resource.name)
			return resource
		elif t_type == "Array":
			var object_key := _normalize_save_object_id(data.get("__id__", 0))
			var array_value: Array = context.objects.get(object_key, [])
			array_value.clear()
			if data.has("__id__"):
				context.objects[object_key] = array_value
				context.hydrating[object_key] = true
			for item in data.get("items", []):
				array_value.append(deserialize_value(item, vm, context))
			return array_value
		elif t_type == "Dictionary":
			var object_key := _normalize_save_object_id(data.get("__id__", 0))
			var dictionary_value: Dictionary = context.objects.get(object_key, {})
			dictionary_value.clear()
			if data.has("__id__"):
				context.objects[object_key] = dictionary_value
				context.hydrating[object_key] = true
			var items: Variant = data.get("items", {})
			if data.has("entries") and data["entries"] is Array:
				for entry: Array in data["entries"]:
					var restored_key: Variant = deserialize_value(entry[0], vm, context)
					dictionary_value[restored_key] = deserialize_value(entry[1], vm, context)
			elif items is Dictionary:
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
	if not str(context.get("error", "")).is_empty():
		return null
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


static func _set_restore_error(context: Dictionary, message: String) -> void:
	if str(context.get("error", "")).is_empty():
		context["error"] = message


static func _restore_sprite_button_images(sprite: HostSprite, context: Dictionary) -> void:
	if sprite.button_image_sources.is_empty():
		return
	if sprite.host == null:
		if context.get("strict_resources", false):
			_set_restore_error(context, "无法恢复 HostSprite 按钮图像：VM 未绑定 Host。")
		return
	for state_name in ["normal", "focus", "pushed", "disabled"]:
		var descriptor: Variant = sprite.button_image_sources.get(state_name, {})
		if not descriptor is Dictionary or descriptor.is_empty():
			continue
		var filename := str(descriptor.get("filename", ""))
		var archive_hint := str(descriptor.get("archive_hint", ""))
		var image_result := sprite.host.load_image(filename, archive_hint)
		if not image_result.get("ok", false):
			if context.get("strict_resources", false):
				_set_restore_error(context, "无法恢复 HostSprite %s 按钮图像 %s。" % [state_name, filename])
			continue
		var restored_image: Image = image_result.get("image")
		var crop: Variant = descriptor.get("crop", [0, 0, 0, 0])
		if crop is Array and crop.size() == 4 and int(crop[2]) > 0 and int(crop[3]) > 0:
			var bounded := Rect2i(int(crop[0]), int(crop[1]), int(crop[2]), int(crop[3])).intersection(Rect2i(Vector2i.ZERO, restored_image.get_size()))
			if bounded.size.x > 0 and bounded.size.y > 0:
				restored_image = restored_image.get_region(bounded)
		var restored_texture := ImageTexture.create_from_image(restored_image)
		match state_name:
			"normal":
				sprite.btn_normal_img = restored_image
				sprite.btn_normal_tex = restored_texture
			"focus":
				sprite.btn_focus_img = restored_image
				sprite.btn_focus_tex = restored_texture
			"pushed":
				sprite.btn_pushed_img = restored_image
				sprite.btn_pushed_tex = restored_texture
			"disabled":
				sprite.btn_disabled_img = restored_image
				sprite.btn_disabled_tex = restored_texture
	sprite.set_button_state(sprite.btn_state)



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
