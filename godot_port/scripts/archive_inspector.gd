extends Control

const NoaArchiveReader = preload("res://scripts/noa_archive.gd")
const EriMetadata = preload("res://scripts/eri_metadata.gd")
const EriDecoder = preload("res://scripts/eri_decoder.gd")
const MioDecoder = preload("res://scripts/mio_decoder.gd")
const CsxIndexReader = preload("res://scripts/csx_index.gd")
const CsxBytecodeReader = preload("res://scripts/csx_bytecode.gd")
const PAGE_SIZE := 250

var reader = NoaArchiveReader.new()
var csx_index = CsxIndexReader.new()
var csx_bytecode = CsxBytecodeReader.new()
var csx_image := PackedByteArray()
var current_mode := "noa"
var file_picker: FileDialog
var csx_picker: FileDialog
var path_label: Label
var status_label: Label
var entries_list: ItemList
var details_label: Label
var preview: TextureRect
var audio_controls: HBoxContainer
var audio_player: AudioStreamPlayer
var search_input: LineEdit
var previous_button: Button
var next_button: Button
var page_label: Label
var filtered_indices: Array[int] = []
var visible_indices: Array[int] = []
var page_index := 0


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("#10151d")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	margin.add_child(page)

	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 16)
	page.add_child(heading)

	var title := Label.new()
	title.text = "Entis 资源与脚本查看器"
	title.add_theme_font_size_override("font_size", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)

	var open_button := Button.new()
	open_button.text = "打开 .noa 文件"
	open_button.custom_minimum_size = Vector2(170, 44)
	open_button.pressed.connect(_open_file_picker)
	heading.add_child(open_button)
	var csx_button := Button.new()
	csx_button.text = "打开 .csx 文件"
	csx_button.custom_minimum_size = Vector2(170, 44)
	csx_button.pressed.connect(_open_csx_picker)
	heading.add_child(csx_button)

	path_label = Label.new()
	path_label.text = "请选择游戏目录中的 .noa 或 .csx 文件。"
	path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(path_label)

	status_label = Label.new()
	status_label.text = "读取 NOA 索引、预览图片和播放音频。"
	status_label.add_theme_color_override("font_color", Color("#9fb3c8"))
	page.add_child(status_label)

	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 8)
	page.add_child(navigation)
	search_input = LineEdit.new()
	search_input.placeholder_text = "搜索名称"
	search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_input.text_changed.connect(_on_search_changed)
	navigation.add_child(search_input)
	previous_button = Button.new()
	previous_button.text = "上一页"
	previous_button.pressed.connect(_previous_page)
	navigation.add_child(previous_button)
	page_label = Label.new()
	page_label.text = "0 / 0"
	navigation.add_child(page_label)
	next_button = Button.new()
	next_button.text = "下一页"
	next_button.pressed.connect(_next_page)
	navigation.add_child(next_button)
	previous_button.disabled = true
	next_button.disabled = true

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(split)

	var list_panel := PanelContainer.new()
	list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(list_panel)

	entries_list = ItemList.new()
	entries_list.select_mode = ItemList.SELECT_SINGLE
	entries_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entries_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	entries_list.item_selected.connect(_on_entry_selected)
	list_panel.add_child(entries_list)

	var detail_panel := PanelContainer.new()
	detail_panel.custom_minimum_size = Vector2(340, 0)
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(detail_panel)

	var detail_margin := MarginContainer.new()
	detail_margin.add_theme_constant_override("margin_left", 18)
	detail_margin.add_theme_constant_override("margin_top", 18)
	detail_margin.add_theme_constant_override("margin_right", 18)
	detail_margin.add_theme_constant_override("margin_bottom", 18)
	detail_panel.add_child(detail_margin)

	var detail_content := VBoxContainer.new()
	detail_content.add_theme_constant_override("separation", 12)
	detail_margin.add_child(detail_content)

	var details_scroll := ScrollContainer.new()
	details_scroll.custom_minimum_size = Vector2(0, 160)
	details_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_content.add_child(details_scroll)
	details_label = Label.new()
	details_label.text = "选择左侧条目查看索引信息。"
	details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_scroll.add_child(details_label)

	audio_controls = HBoxContainer.new()
	audio_controls.visible = false
	detail_content.add_child(audio_controls)
	var play_button := Button.new()
	play_button.text = "播放音频"
	play_button.pressed.connect(_play_audio)
	audio_controls.add_child(play_button)
	var stop_button := Button.new()
	stop_button.text = "停止"
	stop_button.pressed.connect(_stop_audio)
	audio_controls.add_child(stop_button)
	audio_player = AudioStreamPlayer.new()
	add_child(audio_player)

	preview = TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size = Vector2(0, 220)
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_content.add_child(preview)

	file_picker = FileDialog.new()
	file_picker.title = "选择 Entis NOA 归档"
	file_picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_picker.access = FileDialog.ACCESS_FILESYSTEM
	file_picker.filters = PackedStringArray(["*.noa ; Entis NOA archive"])
	file_picker.file_selected.connect(_on_file_selected)
	add_child(file_picker)
	csx_picker = FileDialog.new()
	csx_picker.title = "选择 Cotopha CSX 脚本"
	csx_picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	csx_picker.access = FileDialog.ACCESS_FILESYSTEM
	csx_picker.filters = PackedStringArray(["*.csx ; Cotopha CSX script"])
	csx_picker.file_selected.connect(_on_csx_selected)
	add_child(csx_picker)


func _open_file_picker() -> void:
	file_picker.popup_centered_ratio(0.8)


func _open_csx_picker() -> void:
	csx_picker.popup_centered_ratio(0.8)


func _reset_view(path: String) -> void:
	csx_image = PackedByteArray()
	audio_player.stop()
	audio_player.stream = null
	audio_controls.visible = false
	path_label.text = path
	entries_list.clear()
	filtered_indices.clear()
	visible_indices.clear()
	page_index = 0
	search_input.set_block_signals(true)
	search_input.text = ""
	search_input.set_block_signals(false)
	page_label.text = "0 / 0"
	previous_button.disabled = true
	next_button.disabled = true
	preview.texture = null
	details_label.text = "正在读取索引……"


func _on_file_selected(path: String) -> void:
	current_mode = "noa"
	_reset_view(path)
	var result: Dictionary = reader.inspect(path)
	if not result.get("ok", false):
		status_label.text = "读取失败：%s" % result.get("error", "未知错误")
		details_label.text = "归档保持未修改。"
		return

	_rebuild_filter()

	var directory_count := 0
	for entry in reader.entries:
		if entry["kind"] == "directory":
			directory_count += 1
	status_label.text = "索引读取完成：%d 个条目，%d 个 section，归档 %s。" % [
			result["entry_count"],
			result["section_count"],
			_format_bytes(result["archive_size"]),
		]
	if directory_count > 0:
		status_label.text += " 检测到 %d 个目录条目；嵌套索引将在下一步处理。" % directory_count
	if reader.entries.is_empty():
		details_label.text = "未找到可显示的文件条目。section：%s" % str(result["sections"])


func _on_csx_selected(path: String) -> void:
	current_mode = "csx"
	_reset_view(path)
	var result: Dictionary = csx_index.inspect(path)
	if not result.get("ok", false):
		status_label.text = "读取失败：%s" % result.get("error", "未知错误")
		details_label.text = "无法显示脚本函数。"
		return
	for section in csx_index.sections:
		if section["name"] == "image" and int(section["size"]) <= 64 * 1024 * 1024:
			var file := FileAccess.open(path, FileAccess.READ)
			if file != null:
				file.seek(section["offset"])
				csx_image = file.get_buffer(section["size"])
			break
	_rebuild_filter()
	status_label.text = "CSX 索引：%d 个命名函数，%d 个初始化地址，%d 个 section。" % [
		result["functions"], result["prologues"], csx_index.sections.size(),
	]
	if int(result["trailing_bytes"]) > 0:
		status_label.text += " 文件尾有 %d 字节位于声明范围之外。" % result["trailing_bytes"]


func _on_entry_selected(index: int) -> void:
	if index < 0 or index >= visible_indices.size():
		return
	audio_player.stop()
	audio_player.stream = null
	audio_controls.visible = false
	preview.texture = null
	var entry_index := visible_indices[index]
	if current_mode == "csx":
		var function: Dictionary = csx_index.functions[entry_index]
		var detail := "函数：%s\nimage 内地址：0x%08X\n\n指令预览（最多 12 条，尚未执行）：\n" % [function["name"], function["address"]]
		var decoded: Dictionary = csx_bytecode.decode(csx_image, int(function["address"]), 12)
		for instruction in decoded["instructions"]:
			var operands := str(instruction["operands"])
			if operands.length() > 180:
				operands = operands.left(180) + "…"
			detail += "\n%08X  %s  %s" % [instruction["address"], instruction["name"], operands]
		if not decoded.get("ok", false):
			detail += "\n\n无法继续解码：%s" % decoded["error"]
		details_label.text = detail
		return
	var entry: Dictionary = reader.entries[entry_index]
	var details := "名称：%s\n类型：%s\n解压后大小：%s\n属性 flags：0x%08X\n编码标记：0x%08X\n数据偏移：0x%X" % [
		entry["name"],
		"目录" if entry["kind"] == "directory" else "文件",
		_format_bytes(entry["unpacked_size"]),
		entry["flags"],
		entry["encoding_flags"],
		entry["payload_offset"],
	]
	if entry["kind"] == "file":
		var header: Dictionary = reader.read_payload_header(entry_index)
		if header.get("ok", false):
			details += "\n\n数据记录：%s\n记录大小：%s\n" % [
				header["magic"],
				_format_bytes(header["stored_size"]),
			]
			details += "记录标记匹配。" if header["matches_filedata"] else "记录标记与 filedata 不符。"
		else:
			details += "\n\n无法读取数据记录：%s" % header.get("error", "未知错误")
		if String(entry["name"]).get_extension().to_lower() == "eri":
			var content: Dictionary = reader.read_entry(entry_index, 16 * 1024 * 1024)
			if content.get("ok", false):
				var image_info: Dictionary = EriMetadata.inspect(content["data"])
				if image_info.get("ok", false):
					details += "\n\nERI：%d × %d，%d 位\n图像编码：0x%08X" % [
						image_info["width"], image_info["height"], image_info["bit_depth"], image_info["architecture"],
					]
					if image_info["has_reference"]:
						details += "\n\n图片引用了底图，暂不支持合成预览。"
					else:
						var decoded: Dictionary = EriDecoder.decode(content["data"])
						if decoded.get("ok", false):
							preview.texture = ImageTexture.create_from_image(decoded["image"])
						else:
							details += "\n\n预览不可用：%s" % decoded.get("error", "未知错误")
				else:
					details += "\n\n无法读取 ERI 信息：%s" % image_info.get("error", "未知错误")
			else:
				details += "\n\n无法读取 ERI 内容：%s" % content.get("error", "未知错误")
		elif String(entry["name"]).get_extension().to_lower() == "mio":
			var content: Dictionary = reader.read_entry(entry_index, 16 * 1024 * 1024)
			if content.get("ok", false):
				var decoded: Dictionary = MioDecoder.decode(content["data"])
				if decoded.get("ok", false):
					audio_player.stream = decoded["stream"]
					audio_controls.visible = true
					details += "\n\n音频时长：%.1f 秒" % audio_player.stream.get_length()
				else:
					details += "\n\n音频不可用：%s" % decoded.get("error", "未知错误")
			else:
				details += "\n\n无法读取 MIO 内容：%s" % content.get("error", "未知错误")
	details_label.text = details


func _on_search_changed(_text: String) -> void:
	_rebuild_filter()


func _rebuild_filter() -> void:
	filtered_indices.clear()
	var needle := search_input.text.strip_edges().to_lower()
	var active_entries := _active_entries()
	for index in range(active_entries.size()):
		if needle.is_empty() or String(active_entries[index]["name"]).to_lower().contains(needle):
			filtered_indices.append(index)
	page_index = 0
	_render_page()


func _render_page() -> void:
	entries_list.clear()
	visible_indices.clear()
	preview.texture = null
	audio_player.stop()
	audio_player.stream = null
	audio_controls.visible = false
	details_label.text = "选择左侧条目查看资源。"
	var total_pages := ceili(float(filtered_indices.size()) / PAGE_SIZE)
	var start := page_index * PAGE_SIZE
	var end := mini(start + PAGE_SIZE, filtered_indices.size())
	var active_entries := _active_entries()
	for filtered_index in range(start, end):
		var entry_index := filtered_indices[filtered_index]
		var entry: Dictionary = active_entries[entry_index]
		visible_indices.append(entry_index)
		if current_mode == "csx":
			entries_list.add_item("函数  %s  ·  0x%08X" % [entry["name"], entry["address"]])
		else:
			var kind_text := "目录" if entry["kind"] == "directory" else "文件"
			entries_list.add_item("%s  %s  ·  %s" % [kind_text, entry["name"], _format_bytes(entry["unpacked_size"])])
	page_label.text = "%d / %d" % [page_index + 1 if total_pages > 0 else 0, total_pages]
	previous_button.disabled = page_index <= 0
	next_button.disabled = page_index + 1 >= total_pages


func _active_entries() -> Array[Dictionary]:
	if current_mode == "csx":
		return csx_index.functions
	return reader.entries


func _previous_page() -> void:
	if page_index > 0:
		page_index -= 1
		_render_page()


func _next_page() -> void:
	if (page_index + 1) * PAGE_SIZE < filtered_indices.size():
		page_index += 1
		_render_page()


func _play_audio() -> void:
	if audio_player.stream != null:
		audio_player.play()


func _stop_audio() -> void:
	audio_player.stop()


func _format_bytes(byte_count: int) -> String:
	var value := float(byte_count)
	var units := ["B", "KiB", "MiB", "GiB"]
	var unit_index := 0
	while value >= 1024.0 and unit_index < units.size() - 1:
		value /= 1024.0
		unit_index += 1
	return "%.1f %s" % [value, units[unit_index]]
