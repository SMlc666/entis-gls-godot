extends RefCounted
class_name CsxHost

signal dialogue_updated(entry: Dictionary)
signal bg_updated(bg_name: String, texture: Texture2D)
signal bgm_updated(bgm_name: String)
signal movie_requested(movie_file: String)
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
var advance_query_count: int = 0
var is_waiting_input: bool = false
var is_movie_playing: bool = false
var current_choices: Array[String] = []
var is_waiting_choice: bool = false
var selected_choice: int = -1
var current_tone_filter: String = "NORMAL"
var command_queue: Array = []
var virtual_time_ms: int = 1000
var active_sprites: Dictionary[int, WeakRef] = {}
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
	var current_position: int = 0
	var volume_left: float = 1.0
	var volume_right: float = 1.0
	var audio_stream: AudioStreamWAV = null
	var audio_channel: String = ""
	var image: Image = null
	var texture: ImageTexture = null
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

	func load_image(filename: String) -> int:
		name = filename
		if host != null:
			var res := host.load_image(filename, archive_name)
			if res.get("ok", false):
				image = res["image"]
				texture = res["texture"]
				return 1
		return 0

	func play(_intro: int = -1, _flag: int = 0) -> int:
		return _play_at(0, false, true)

	func play_from(start_pos: int = 0, end_pos: int = -1, repeat: bool = false, rewind_pos: int = -1, flag: int = 0) -> int:
		if end_pos != -1 or rewind_pos != -1 or flag != 0:
			if host != null:
				host.report_unsupported("HostResource.PlayFrom end_pos/rewind_pos/flag")
			return -1
		return _play_at(start_pos, repeat, false)

	func _play_at(start_pos: int, repeat: bool, channel_default_loop: bool = false) -> int:
		if host == null:
			return 0
		if start_pos < 0:
			host.last_error = "HostResource.PlayFrom 起始位置不能为负数。"
			push_warning(host.last_error)
			return 0
		if audio_stream == null and load_sound(name) != 1:
			return 0
		var started := host.play_audio_stream(audio_stream, name, audio_channel, start_pos, repeat, channel_default_loop)
		is_playing = started
		current_position = start_pos if started else 0
		is_repeating = repeat if started else false
		use_channel_default_loop = channel_default_loop if started else false
		return 1 if started else 0

	func stop() -> int:
		var stopped := host.stop_audio(name, audio_channel) if host != null else false
		is_playing = false
		current_position = 0
		return 1 if stopped else 0

	func pause() -> int:
		if host == null:
			return 0
		current_position = host.get_audio_position_msec(name, audio_channel)
		var paused := host.pause_audio(name, audio_channel)
		is_playing = false if paused else is_playing
		return 1 if paused else 0

	func restart() -> int:
		if host == null:
			return 0
		var resumed := host.resume_audio(name, audio_channel)
		if not resumed:
			return _play_at(current_position, is_repeating, use_channel_default_loop)
		is_playing = true
		return 1

	func release() -> int:
		is_playing = false
		is_repeating = false
		use_channel_default_loop = false
		audio_stream = null
		image = null
		texture = null
		return 0

	func set_volume(left: float, right: float) -> int:
		var normalized_left := clampf(left, 0.0, 1.0)
		var normalized_right := clampf(right, 0.0, 1.0)
		if not is_equal_approx(normalized_left, normalized_right):
			if host != null:
				host.report_unsupported("HostResource.SetVolume asymmetric stereo values")
			return -1
		if host == null or not host.set_audio_channel_volume(audio_channel, normalized_left):
			return 0
		volume_left = normalized_left
		volume_right = normalized_right
		return 1

	func set_volume_envelope(_bezier: Variant, _duration: int) -> int:
		if host != null:
			host.report_unsupported("HostResource.SetVolumeEnvelope")
		return -1

	func cancel_volume_envelope() -> int:
		if host != null:
			host.report_unsupported("HostResource.CancelVolumeEnvelope")
		return -1

	func get_playing_position() -> int:
		return current_position

	func set_total_volume(_flag: int, _vol: float) -> int:
		return set_volume(_vol, _vol)

	func get_total_volume(_flag: int) -> float:
		return (volume_left + volume_right) * 0.5


class HostInputFilter extends RefCounted:
	var host: CsxHost
	var filter_file: String = ""
	var is_open: bool = false
	var window_ref: Variant = null
	var input_queue: Array = []
	var joy_buttons: Dictionary = {}
	var fields: Dictionary = {}

	func _init(p_host: CsxHost) -> void:
		host = p_host

	func load_input_filter(filename: String) -> int:
		filter_file = filename
		return 0

	func delete_input_filter() -> int:
		filter_file = ""
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

	func is_joy_button_pushing(_key: int, _dev: int = 0) -> int:
		return 0

	func get_joy_button_pushed(key: int, _dev: int = 0) -> int:
		# print("query key=", key, " adv_ticks=", host.advance_ticks if host else 0)
		if host != null:
			if host.advance_ticks > 0 and key == 1:
				host.advance_ticks -= 1
				host.is_waiting_input = false
				return 1
			if host.auto_advance and key == 1:
				host.is_waiting_input = false
				return 1
			if key == 1:
				host.is_waiting_input = true
		return 0

	func flush_joy_button_pushed(_dev: int = 0, _key: int = -1) -> int:
		return 0

	func reset_joy_button_pushing(_dev: int = 0, _key: int = -1) -> int:
		return 0

	func get_cursor_pos() -> Vector2i:
		return Vector2i.ZERO

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
	var fields: Dictionary = {}

	func _init(p_host: CsxHost) -> void:
		host = p_host

	func create_tone_filter() -> int:
		return 0

	func delete_tone_filter() -> int:
		filter_type = "NORMAL"
		if host != null:
			host.set_tone_filter("NORMAL")
		return 0

	func set_tone(r: float, g: float, b: float) -> int:
		tone = Color(r, g, b)
		return 0

	func get_tone() -> Array:
		return [tone.r, tone.g, tone.b]

	func attach_tone_filter(_target: Variant) -> int:
		return 0

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

		var buttons: Array = page.get("buttons", [])
		for btn in buttons:
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
			parent_sprite.add_sprite(0, btn_spr)
		for item: Dictionary in page.get("static_texts", []):
			var text_sprite := HostSprite.new(0, host)
			text_sprite.fields["form_item_id"] = item["id"]
			text_sprite.position = Vector2i(item["x"], item["y"])
			text_sprite.size = Vector2i(item["width"], item["height"])
			text_sprite.is_visible = true
			text_sprite.attach_message_style(self, item["style"])
			text_sprite.output_message(item["text"])
			parent_sprite.add_sprite(buttons.size() + 1, text_sprite)

		parent_sprite.refresh_command_ids()

		return 1

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
	var transparency: int = 0 # 0 = opaque, 256 = transparent
	var blending: int = 0
	var position: Vector2i = Vector2i.ZERO
	var rev_center: Vector2i = Vector2i.ZERO
	var size: Vector2i = Vector2i.ZERO
	var z_order: int = 0
	var filename: String = ""
	var archive_hint: String = ""
	var attached_resource: HostResource = null
	var image: Image = null
	var texture: ImageTexture = null
	var is_activating: bool = false
	var activation_duration_ms: float = 0.0
	var activation_elapsed_ms: float = 0.0
	var activation_start_alpha: int = 0
	var activation_end_alpha: int = 0
	var children: Array[HostSprite] = []
	var text_content: String = ""
	var message_style: Dictionary = {}
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

	func attach_message_style(res_mgr: Variant, style_id: String) -> int:
		if not (res_mgr is HostResourceManager):
			return 0
		var style: Dictionary = res_mgr.skin_styles.get(style_id, {})
		if style.get("type", "") != "static_text":
			return 0
		message_style = style
		return 0

	func output_message(text: String) -> int:
		text_content = text
		return 0

	func load_image(p_filename: String) -> int:
		filename = p_filename
		if host != null:
			var res := host.load_image(p_filename, archive_hint)
			if res.get("ok", false):
				image = res["image"]
				texture = res["texture"]
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
		elif res is String:
			load_image(res)

	func set_visible(v: int) -> void:
		is_visible = (v != 0)

	func set_transparency(alpha: int) -> void:
		transparency = clampi(alpha, 0, 256)

	func set_blending_envelope(b: int) -> void:
		blending = b

	func begin_activation(duration_ms: int) -> void:
		activation_start_alpha = transparency
		activation_end_alpha = clampi(blending, 0, 256)
		activation_duration_ms = float(duration_ms)
		activation_elapsed_ms = 0.0
		is_activating = true
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
		transparency = roundi(lerpf(activation_start_alpha, activation_end_alpha, progress))

	func flush_activation() -> void:
		transparency = activation_end_alpha if is_activating else clampi(blending, 0, 256)
		is_activating = false
		if host != null:
			host.active_sprites.erase(get_instance_id())

	func is_activation() -> int:
		return -1 if is_activating else 0

	func move_position(x: int, y: int) -> void:
		position = Vector2i(x, y)

	func add_sprite(z: int, child: Variant) -> void:
		if child is HostSprite:
			child.z_order = z
			if not children.has(child):
				children.append(child)
			child.refresh_command_ids()

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
		return 0

	func create_sprite(_format: int, w: int, h: int) -> int:
		var cw := maxi(1, w)
		var ch := maxi(1, h)
		image = Image.create(cw, ch, false, Image.FORMAT_RGBA8)
		image.fill(Color(0, 0, 0, 0))
		texture = ImageTexture.create_from_image(image)
		size = Vector2i(cw, ch)
		return 0

	func set_back_color(_rgb: int, _enable: bool) -> int:
		return 0

	func set_alpha_image(_alpha_res: Variant, _range: int = 0) -> int:
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
			var c := Color.hex(color)
			c.a = a
			image.fill_rect(r, c)
			texture = ImageTexture.create_from_image(image)
		return 0

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
			param.set_field("nImageWidth", size.x)
			param.set_field("nImageHeight", size.y)
			param.set_field("nTransparency", transparency)
		return 0

	func set_parameter(param: Variant) -> int:
		if param != null and param.has_method("get_field"):
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
		if host != null:
			print("[CSX Host] OpenMovie requested: %s" % p_filename)
			host.emit_signal("movie_requested", p_filename)
		return 1

	func play_movie(_mode: int = 0) -> int:
		return 0

	func is_movie_playing() -> int:
		if host != null and host.is_movie_playing:
			return 1
		return 0

	func stop_movie() -> int:
		if host != null:
			host.is_movie_playing = false
		return 0

	func close_movie() -> int:
		if host != null:
			host.is_movie_playing = false
		return 0



class HostWindow extends RefCounted:
	var host: CsxHost
	var viewport_size: Vector2i = Vector2i(800, 600)
	var root_sprites: Array[HostSprite] = []
	var fields: Dictionary = {}

	func _init(p_host: CsxHost) -> void:
		host = p_host

	func add_sprite(z: int, spr: Variant) -> void:
		if spr is HostSprite:
			spr.z_order = z
			if not root_sprites.has(spr):
				root_sprites.append(spr)

	func detach_sprite(spr: Variant) -> void:
		if spr is HostSprite:
			root_sprites.erase(spr)

	func detach_all_sprites() -> void:
		root_sprites.clear()

	func get_display_size() -> Vector2i:
		return viewport_size

	func show_cursor(_show_flag: int) -> int:
		return 0

	func set_optional_func_flag(_flag: int) -> int:
		return 0

	func lock() -> int:
		return 0

	func get_joy_button_pushed(key: int, _dev: int = 0) -> int:
		# print("query key=", key, " adv_ticks=", host.advance_ticks if host else 0)
		if host != null:
			if host.advance_ticks > 0 and key == 1:
				host.advance_ticks -= 1
				host.is_waiting_input = false
				return 1
			if host.auto_advance and key == 1:
				host.is_waiting_input = false
				return 1
			if key == 1:
				host.is_waiting_input = true
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




func advance_sprite_animations(delta: float) -> void:
	for sprite_id in active_sprites.keys():
		var sprite := active_sprites[sprite_id].get_ref() as HostSprite
		if sprite == null:
			active_sprites.erase(sprite_id)
		else:
			sprite.advance_activation(delta * 1000.0)


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
		return {"ok": true, "image": item["image"], "texture": item["texture"]}

	var entry_res := _read_vfs_candidate(entry)
	if not entry_res.get("ok", false):
		return {"ok": false, "error": "无法在 VFS 中找到图片: %s" % norm}

	var dec_res := EriDecoder.decode(entry_res["data"])
	if not dec_res.get("ok", false):
		return dec_res

	var img: Image = dec_res["image"]
	var tex := ImageTexture.create_from_image(img)
	var estimated_bytes := img.get_data().size() * 2
	if estimated_bytes <= image_cache_budget_bytes:
		image_cache[cache_key] = {"image": img, "texture": tex, "bytes": estimated_bytes}
		image_cache_lru.append(cache_key)
		image_cache_bytes += estimated_bytes
		_trim_image_cache()
	return {"ok": true, "image": img, "texture": tex}


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


func _audio_player_for_channel(channel: String) -> AudioStreamPlayer:
	match channel.strip_edges().to_lower():
		"bgm": return bgm_player
		"env_se": return env_se_player
		"se": return se_player
		"voice": return voice_player
		"system": return system_player
		_: return null


func play_audio_stream(stream: AudioStreamWAV, name: String, channel_hint: String = "", start_pos_msec: int = 0, repeat: bool = false, channel_default_loop: bool = true) -> bool:
	if stream == null:
		_audio_error("音频流为空: %s" % name)
		return false
	var channel := channel_hint.strip_edges().to_lower() if not channel_hint.strip_edges().is_empty() else resolve_audio_channel(name)
	if channel.is_empty():
		_audio_error("无法确定音频资源的播放声道: %s" % name)
		return false
	var player := _audio_player_for_channel(channel)
	if player == null:
		_audio_error("音频声道尚未初始化: %s" % channel)
		return false
	if start_pos_msec < 0:
		_audio_error("音频起始位置不能为负数: %s (%d ms)" % [name, start_pos_msec])
		return false
	if channel == "voice" and _voice_is_muted(name):
		return false
	# load_sound() returns a cached WAV stream. Loop policy belongs to this
	# playback, so duplicate before changing it to avoid mutating other handles.
	var playback_stream := stream.duplicate() as AudioStreamWAV
	if playback_stream == null:
		_audio_error("无法复制音频流用于播放: %s" % name)
		return false
	playback_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if repeat or (channel_default_loop and channel in ["bgm", "env_se"]) else AudioStreamWAV.LOOP_DISABLED
	player.stream = playback_stream
	player.stream_paused = false
	player.play(maxf(0.0, float(start_pos_msec) / 1000.0))
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
	if bgm_player != null:
		bgm_player.stop()
	print("[CSX Host] Stopped BGM")


func play_env_se(name: String) -> void:
	_play_named_audio(name, "env_se")


func stop_env_se() -> void:
	current_env_se = ""
	if env_se_player != null:
		env_se_player.stop()
	print("[CSX Host] Stopped EnvSE")


func play_se(name: String) -> void:
	_play_named_audio(name, "se")


func stop_se() -> void:
	if se_player != null:
		se_player.stop()


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
	if voice_player != null:
		voice_player.stop()


func stop_audio(name: String, channel_hint: String = "") -> bool:
	var channel := channel_hint.strip_edges().to_lower() if not channel_hint.strip_edges().is_empty() else resolve_audio_channel(name)
	var player := _audio_player_for_channel(channel)
	if player == null:
		_audio_error("无法停止未知音频声道 '%s' (resource: %s)" % [channel, name])
		return false
	player.stop()
	player.stream_paused = false
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
	if player == null or not player.playing:
		last_error = "无法暂停当前未播放的音频声道: %s (%s)" % [channel, name]
		return false
	player.stream_paused = true
	return true


func resume_audio(name: String, channel_hint: String = "") -> bool:
	var channel := channel_hint.strip_edges().to_lower() if not channel_hint.strip_edges().is_empty() else resolve_audio_channel(name)
	var player := _audio_player_for_channel(channel)
	if player == null or player.stream == null:
		last_error = "无法恢复未初始化的音频声道: %s (%s)" % [channel, name]
		return false
	if player.stream_paused:
		player.stream_paused = false
		return true
	return false


func get_audio_position_msec(name: String, channel_hint: String = "") -> int:
	var channel := channel_hint.strip_edges().to_lower() if not channel_hint.strip_edges().is_empty() else resolve_audio_channel(name)
	var player := _audio_player_for_channel(channel)
	if player == null:
		return 0
	return int(round(player.get_playback_position() * 1000.0))


func set_audio_channel_volume(channel: String, linear_volume: float) -> bool:
	var normalized_channel := channel.strip_edges().to_lower()
	var player := _audio_player_for_channel(normalized_channel)
	if player == null:
		last_error = "音频声道尚未初始化，无法设置音量: %s" % normalized_channel
		return false
	var volume := clampf(linear_volume, 0.0, 1.0)
	player.volume_db = -80.0 if volume <= 0.0001 else linear_to_db(volume)
	return true


func get_audio_channel_volume(channel: String) -> float:
	var player := _audio_player_for_channel(channel)
	if player == null:
		return 0.0
	return db_to_linear(player.volume_db)


func report_unsupported(capability: String) -> void:
	last_error = "当前未实现宿主能力: %s" % capability
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
				"size": [sprite.size.x, sprite.size.y],
				"z_order": sprite.z_order,
				"is_visible": sprite.is_visible,
				"transparency": sprite.transparency,
				"btn_id": sprite.btn_id,
				"is_button": sprite.is_button,
				"btn_state": sprite.btn_state,
				"text_content": sprite.text_content,
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
				"current_position": resource.current_position,
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
			var sprite_size: Array = data.get("size", [0, 0])
			sprite.size = Vector2i(int(sprite_size[0]), int(sprite_size[1])) if sprite_size.size() >= 2 else Vector2i.ZERO
			sprite.z_order = int(data.get("z_order", 0))
			sprite.is_visible = bool(data.get("is_visible", false))
			sprite.transparency = int(data.get("transparency", 0))
			sprite.btn_id = str(data.get("btn_id", ""))
			sprite.is_button = bool(data.get("is_button", false))
			sprite.btn_state = str(data.get("btn_state", "normal"))
			sprite.text_content = str(data.get("text_content", ""))
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
			resource.current_position = int(data.get("current_position", 0))
			resource.volume_left = clampf(float(data.get("volume_left", 1.0)), 0.0, 1.0)
			resource.volume_right = clampf(float(data.get("volume_right", 1.0)), 0.0, 1.0)
			resource.fields = deserialize_value(data.get("fields", {}), vm, context) if data.get("fields", {}) is Dictionary else {}
			if resource_host != null:
				var extension := resource.name.get_extension().to_lower()
				if extension == "mio":
					resource.load_sound(resource.name)
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
