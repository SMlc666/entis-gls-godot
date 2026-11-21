extends Control

const CsxVMReader = preload("res://scripts/csx_vm.gd")
const CsxHostClass = preload("res://scripts/csx_host.gd")
const PlayerSettingsState = preload("res://scripts/player_settings_state.gd")
const CgThumbnailCache = preload("res://scripts/cg_thumbnail_cache.gd")
const NativeMessageFadeEffect = preload("res://scripts/native_message_fade_effect.gd")

const CG_CATEGORIES: Array[Dictionary] = [
	{"id": "EA", "name": "春日野 穹", "sub": "Kasugano Sora"},
	{"id": "EB", "name": "依媛 奈绪", "sub": "Yorihime Nao"},
	{"id": "EC", "name": "天女目 瑛", "sub": "Amatsume Akira"},
	{"id": "ED", "name": "渚 一叶", "sub": "Migiwa Kazuha"},
	{"id": "EE", "name": "初佳 / 梢", "sub": "Motoka & Kozue"},
	{"id": "EZ", "name": "剧情共通", "sub": "Common / Story"}
]

const RECOLLECTION_HEROINES: Array[Dictionary] = [
	{
		"heroine": "春日野 穹 (Sora)",
		"tag_id": 0,
		"scenes": [
			{"flag": 1, "scenario": "00_A020", "banner": "REC_SR1.eri", "title": "回想 1 (00_A020)"},
			{"flag": 2, "scenario": "00_A022", "banner": "REC_SR2.eri", "title": "回想 2 (00_A022)"},
			{"flag": 3, "scenario": "00_A025B", "banner": "REC_SR3.eri", "title": "回想 3 (00_A025B)"},
			{"flag": 4, "scenario": "00_A026", "banner": "REC_SR4.eri", "title": "回想 4 (00_A026)"},
			{"flag": 5, "scenario": "00_A032", "banner": "REC_SR5.eri", "title": "回想 5 (00_A032)"},
		]
	},
	{
		"heroine": "依媛 奈绪 (Nao)",
		"tag_id": 1,
		"scenes": [
			{"flag": 6, "scenario": "00_B005", "banner": "REC_NO1.eri", "title": "回想 1 (00_B005)"},
			{"flag": 7, "scenario": "00_B021", "banner": "REC_NO2.eri", "title": "回想 2 (00_B021)"},
			{"flag": 8, "scenario": "00_B025", "banner": "REC_NO3.eri", "title": "回想 3 (00_B025)"},
			{"flag": 9, "scenario": "00_B032", "banner": "REC_NO4.eri", "title": "回想 4 (00_B032)"},
		]
	},
	{
		"heroine": "天女目 瑛 (Akira)",
		"tag_id": 2,
		"scenes": [
			{"flag": 10, "scenario": "00_C019B", "banner": "REC_AK1.eri", "title": "回想 1 (00_C019B)"},
			{"flag": 11, "scenario": "00_C023", "banner": "REC_AK2.eri", "title": "回想 2 (00_C023)"},
			{"flag": 12, "scenario": "00_C034", "banner": "REC_AK3.eri", "title": "回想 3 (00_C034)"},
		]
	},
	{
		"heroine": "渚 一叶 (Kazuha)",
		"tag_id": 3,
		"scenes": [
			{"flag": 13, "scenario": "00_D025B", "banner": "REC_KA1.eri", "title": "回想 1 (00_D025B)"},
			{"flag": 14, "scenario": "00_D028B", "banner": "REC_KA2.eri", "title": "回想 2 (00_D028B)"},
			{"flag": 15, "scenario": "00_D042B", "banner": "REC_KA3.eri", "title": "回想 3 (00_D042B)"},
		]
	},
	{
		"heroine": "乃木坂 初佳 (Motoka)",
		"tag_id": 4,
		"scenes": [
			{"flag": 16, "scenario": "00_E013C", "banner": "REC_MT1.eri", "title": "回想 1 (00_E013C)"},
			{"flag": 17, "scenario": "00_E024B", "banner": "REC_MT2.eri", "title": "回想 2 (00_E024B)"},
			{"flag": 18, "scenario": "00_E036", "banner": "REC_MT3.eri", "title": "回想 3 (00_E036)"},
		]
	}
]

const BGM_TRACKS: Array[Dictionary] = [
	{"file": "BGM01.mio", "title": "道の先、空の向こう", "sub": "道路的前方、苍穹的彼方 (Main Theme)"},
	{"file": "BGM02.mio", "title": "陽だまりの小道", "sub": "阳光洒落的小径"},
	{"file": "BGM02_S.mio", "title": "陽だまりの小道 (Short)", "sub": "阳光洒落的小径 (短版)"},
	{"file": "BGM03.mio", "title": "碧い花", "sub": "碧蓝之花"},
	{"file": "BGM04.mio", "title": "頬をなでる風", "sub": "拂颊微风"},
	{"file": "BGM05.mio", "title": "弾む足取り", "sub": "轻快的脚步"},
	{"file": "BGM06.mio", "title": "遠い日の記憶", "sub": "远昔记忆"},
	{"file": "BGM07.mio", "title": "悠久の想い", "sub": "悠久思念 (Title Theme)"},
	{"file": "BGM08.mio", "title": "夕立のあと", "sub": "阵雨过后"},
	{"file": "BGM09.mio", "title": "星の降る夜", "sub": "星落之夜"},
	{"file": "BGM10.mio", "title": "暮れなずむ空", "sub": "暮色苍茫的天空"},
	{"file": "BGM11.mio", "title": "静かなる夜", "sub": "静寂之夜"},
	{"file": "BGM12.mio", "title": "ざわめく心", "sub": "躁动的心"},
	{"file": "BGM13.mio", "title": "迷いの森", "sub": "迷途之森"},
	{"file": "BGM14.mio", "title": "悲しみの記憶", "sub": "悲伤的记忆"},
	{"file": "BGM15.mio", "title": "届かぬ想い", "sub": "无法传达的思念"},
	{"file": "BGM16.mio", "title": "闇の足音", "sub": "黑暗的足音"},
	{"file": "BGM17.mio", "title": "決意", "sub": "决意"},
	{"file": "BGM18.mio", "title": "寄り添う心", "sub": "依偎的心"},
	{"file": "BGM19.mio", "title": "あなたと", "sub": "与你相伴"},
	{"file": "BGM20.mio", "title": "ぬくもり", "sub": "温暖"},
	{"file": "BGM21.mio", "title": "繋がる想い", "sub": "牵绊的思念"}
]

var game_dir: String = ""
var save_dir_override: String = ""
var csx_script_path: String = ""
var host: CsxHostClass = null
var vm: CsxVMReader = null
var settings_state = PlayerSettingsState.new()

# UI Nodes
var bg_rect: TextureRect
var bustup_container: Control
var bustup_rects: Array[TextureRect] = []
var dialogue_box: Control
var speaker_label: Label
var message_label: RichTextLabel
var indicator: Label
var auto_button: BaseButton
var skip_button: BaseButton
var voice_button: BaseButton
var history_button: BaseButton
var save_button: BaseButton
var load_button: BaseButton
var gallery_button: BaseButton
var qsave_button: BaseButton
var qload_button: BaseButton
var home_button: BaseButton
var config_button: BaseButton
var close_button: BaseButton
var title_label: Label
var choice_container: VBoxContainer
var choice_buttons: Array[Button] = []

# Config / Options Modal UI Nodes
var config_panel: PanelContainer
var is_config_open: bool = false
var cfg_btn_window: TextureButton
var cfg_btn_fullscreen: TextureButton
var cfg_slider_bgm: HSlider
var cfg_slider_se: HSlider
var cfg_slider_system: HSlider
var cfg_slider_voice: HSlider
var cfg_slider_speed: HSlider
var cfg_slider_auto_speed: HSlider
var cfg_check_bgm: TextureButton
var cfg_check_se: TextureButton
var cfg_check_system: TextureButton
var cfg_check_voice: TextureButton
var cfg_btn_voice_details: TextureButton
var is_voice_details_open: bool = false
var voice_details_panel: PanelContainer
var voice_char_buttons: Dictionary = {}
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
var tex_sound_on_normal: Texture2D
var tex_sound_on_checked: Texture2D
var tex_sound_on_focus: Texture2D

# Backlog UI Nodes
var backlog_panel: PanelContainer
var backlog_scroll: ScrollContainer
var backlog_vbox: VBoxContainer
var is_backlog_open: bool = false

# Save/Load Modal UI Nodes
var save_load_panel: PanelContainer
var save_load_box: Control
var save_load_title: Label
var save_load_title_img: TextureRect
var save_load_grid: GridContainer
var save_load_scroll: VScrollBar
var save_load_mode_btn_save: Button
var save_load_mode_btn_load: Button
var btn_qload: TextureButton
var is_save_load_open: bool = false
var save_load_mode: String = "load" # "save" or "load"
var save_load_page: int = 1 # 0: QSave, 1..6: slots 1-60
var page_buttons: Array[Button] = []
var tex_save_title: Texture2D
var tex_load_title: Texture2D
var tex_slot_bg_normal: Texture2D
var tex_slot_bg_focus: Texture2D
var tex_badge_new: Texture2D
var tex_qload_normal: Texture2D
var tex_qload_focus: Texture2D
var tex_save_close_normal: Texture2D
var tex_save_close_focus: Texture2D

# Title Screen UI Nodes
var title_panel: PanelContainer
var title_bg: TextureRect
var title_logo: TextureRect
var title_sublogo: TextureRect
var is_title_mode: bool = false
var native_appreciation_mode: bool = false
var start_in_title: bool = false
var start_scenario: String = "00_Z000"
var native_title_layer: Control
var native_title_canvas: Control
var native_title_controls: Dictionary = {}
var native_title_result_handled: bool = false
var native_title_last_viewport_size: Vector2 = Vector2.ZERO

# Confirmation Dialog
var confirm_panel: PanelContainer
var confirm_label: Label
var confirm_callback: Callable

# Appreciation / Gallery & Jukebox UI Nodes
var appreciation_panel: PanelContainer
var is_appreciation_open: bool = false
var app_mode: String = "cg" # "cg", "rec", or "bgm"
var app_cg_category: String = "EA"
var app_cg_page: int = 1
var app_full_unlock: bool = true
var cg_catalog: Dictionary = {}
var cg_thumbnail_cache = CgThumbnailCache.new()
var cg_grid: GridContainer
var cg_page_label: Label
var cg_category_buttons: Array[Button] = []
var btn_app_cg: Button
var btn_app_rec: Button
var btn_app_bgm: Button
var btn_unlock_toggle: Button
var cg_gallery_container: VBoxContainer
var bgm_jukebox_container: HBoxContainer
var bgm_track_list_vbox: VBoxContainer
var bgm_track_buttons: Array[Button] = []
var bgm_now_playing_label: Label
var bgm_play_btn: Button
var bgm_vol_slider: HSlider
var bgm_vol_label: Label
var current_bgm_track_index: int = -1
var previous_bgm_before_app: String = ""

# Scene Recollection Nodes & State
var is_recollect_mode: bool = false
var recollect_return_tag: int = 0
var app_rec_heroine_index: int = 0
var rec_container: VBoxContainer
var rec_heroine_buttons: Array[Button] = []
var rec_grid: GridContainer
var rec_banner_cache: Dictionary = {}
var app_title_lbl: Label
var app_close_btn: Button

# Appreciation Skin Textures
var tex_app_bg: Texture2D
var tex_app_title: Texture2D
var tex_rec_card_normal: Texture2D
var tex_rec_card_focus: Texture2D
var tex_rec_locked: Texture2D
var tex_rec_btn_normal: Texture2D
var tex_rec_btn_focus: Texture2D
var tex_app_close_normal: Texture2D
var tex_app_close_focus: Texture2D

# Fullscreen CG Viewer Nodes
var cg_fullscreen_panel: PanelContainer
var fullscreen_cg_rect: TextureRect
var fullscreen_info_label: Label
var fullscreen_current_variants: Array = []
var fullscreen_variant_index: int = 0
var fullscreen_scene_id: String = ""
var fullscreen_cat_name: String = ""

# Tone Filter Shader
var tone_material: ShaderMaterial

# Video Player
var video_player: VideoStreamPlayer

# Audio Nodes
var bgm_player: AudioStreamPlayer
var system_player: AudioStreamPlayer
var env_se_player: AudioStreamPlayer
var se_player: AudioStreamPlayer
var voice_player: AudioStreamPlayer

# Execution state
var is_initialized := false
var is_running := false
var auto_mode := false
var skip_mode := false
var auto_timer := 0.0
var indicator_timer := 0.0
var steps_per_frame := 3000
const NATIVE_TITLE_STEPS_PER_FRAME := 600


func _ready() -> void:
	_parse_arguments()
	_build_ui()
	_setup_audio()
	call_deferred("_start_engine")


func _parse_arguments() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a: String = args[i]
		if a == "--title":
			start_in_title = true
		elif a == "--scenario":
			if i + 1 < args.size() and not args[i + 1].begins_with("--"):
				start_scenario = args[i + 1]
				i += 1
		elif a.begins_with("--scenario="):
			start_scenario = a.substr(11)
		elif a == "--game-dir":
			if i + 1 < args.size() and not args[i + 1].begins_with("--"):
				game_dir = args[i + 1]
				i += 1
		elif a.begins_with("--game-dir="):
			game_dir = a.substr(11)
		elif not a.begins_with("--") and game_dir.is_empty():
			game_dir = a
		i += 1


func _normalize_game_root(path: String) -> String:
	var root := path.strip_edges().replace("\\", "/").simplify_path()
	if root.get_extension().to_lower() == "csx":
		root = root.get_base_dir()
	if root.get_file().to_lower() == "system":
		root = root.get_base_dir()
	return root


func _resolve_game_script() -> Dictionary:
	var roots: Array[String] = []
	if not game_dir.strip_edges().is_empty():
		roots.append(_normalize_game_root(game_dir))
	var environment_dir := OS.get_environment("YOSUGA_GAME_DIR").strip_edges()
	if not environment_dir.is_empty():
		roots.append(_normalize_game_root(environment_dir))
	roots.append("res://assets")
	roots.append("user://game")

	var attempted_paths: Array[String] = []
	var visited: Dictionary = {}
	for root_path in roots:
		if root_path.is_empty() or visited.has(root_path):
			continue
		visited[root_path] = true
		for relative_path in ["system/yosuga.csx", "yosuga.csx"]:
			var candidate := root_path.path_join(relative_path)
			attempted_paths.append(candidate)
			if FileAccess.file_exists(candidate):
				return {"game_dir": root_path, "script_path": candidate, "attempted_paths": attempted_paths}
	return {"game_dir": "", "script_path": "", "attempted_paths": attempted_paths}


func _build_ui() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0

	# 1. Background layer
	bg_rect = TextureRect.new()
	bg_rect.name = "Background"
	bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(bg_rect)

	# 2. Bustup container
	bustup_container = Control.new()
	bustup_container.name = "BustupContainer"
	bustup_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bustup_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bustup_container)

	for i in range(5):
		var b_rect := TextureRect.new()
		b_rect.name = "Bustup_%d" % i
		b_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		b_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		b_rect.visible = false
		b_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bustup_container.add_child(b_rect)
		bustup_rects.append(b_rect)

	# 3. Top Header Bar (Makeshift bar deprecated in favor of authentic in-game dialogue menu)
	# Keeping dummy buttons for compatibility
	home_button = Button.new()
	home_button.pressed.connect(_on_home_button_pressed)
	gallery_button = Button.new()
	gallery_button.pressed.connect(_open_appreciation_modal)

	# 4. Authentic EntisGLS Dialogue Box & In-Game Quick Menu (750 x 152)
	dialogue_box = Control.new()
	dialogue_box.name = "DialogueBox"
	dialogue_box.anchor_left = 0.5
	dialogue_box.anchor_right = 0.5
	dialogue_box.anchor_top = 1.0
	dialogue_box.anchor_bottom = 1.0
	dialogue_box.offset_left = -375.0
	dialogue_box.offset_right = 375.0
	dialogue_box.offset_top = -162.0
	dialogue_box.offset_bottom = -10.0
	dialogue_box.custom_minimum_size = Vector2(750, 152)
	dialogue_box.size = Vector2(750, 152)
	dialogue_box.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(dialogue_box)

	var dlg_bg := TextureRect.new()
	dlg_bg.name = "DialogueBackground"
	dlg_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dlg_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dlg_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	dlg_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue_box.add_child(dlg_bg)

	speaker_label = Label.new()
	speaker_label.name = "SpeakerLabel"
	speaker_label.position = Vector2(27, 8)
	speaker_label.size = Vector2(320, 26)
	speaker_label.add_theme_font_size_override("font_size", 18)
	speaker_label.add_theme_color_override("font_color", Color("#e5c07b"))
	speaker_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue_box.add_child(speaker_label)

	message_label = RichTextLabel.new()
	message_label.name = "MessageLabel"
	message_label.text = "正在启动剧情引擎，请稍候..."
	message_label.bbcode_enabled = true
	message_label.install_effect(NativeMessageFadeEffect.new())
	message_label.scroll_active = false
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.position = Vector2(39, 38)
	message_label.size = Vector2(684, 82)
	message_label.add_theme_font_size_override("normal_font_size", 18)
	message_label.add_theme_color_override("default_color", Color("#eeeeee"))
	message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue_box.add_child(message_label)

	indicator = Label.new()
	indicator.name = "Indicator"
	indicator.text = "▼"
	indicator.position = Vector2(700, 96)
	indicator.size = Vector2(24, 24)
	indicator.add_theme_font_size_override("font_size", 16)
	indicator.add_theme_color_override("font_color", Color("#98c379"))
	indicator.visible = false
	indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue_box.add_child(indicator)

	# Voice Replay Button (ID_PAGE_ADV_VOICE at 689, 6)
	voice_button = TextureButton.new()
	voice_button.name = "VoiceReplayBtn"
	voice_button.position = Vector2(689, 6)
	voice_button.size = Vector2(28, 21)
	voice_button.visible = false
	voice_button.pressed.connect(_replay_voice)
	dialogue_box.add_child(voice_button)

	# Close/Hide Dialogue Frame Button (ID_PAGE_ADV_CLOSE at 727, 7)
	close_button = TextureButton.new()
	close_button.name = "CloseDialogueBtn"
	close_button.position = Vector2(727, 7)
	close_button.size = Vector2(16, 17)
	close_button.pressed.connect(_hide_dialogue_box)
	dialogue_box.add_child(close_button)

	# In-game ADV Quick Menu (ID_PAGE_ADV_MENU at 9, 124)
	var menu_box := Control.new()
	menu_box.name = "AdvMenuBox"
	menu_box.position = Vector2(9, 124)
	menu_box.size = Vector2(732, 25)
	dialogue_box.add_child(menu_box)

	qsave_button = TextureButton.new()
	qsave_button.name = "ID_QSAVE"
	qsave_button.position = Vector2(0, 0)
	qsave_button.size = Vector2(84, 25)
	qsave_button.pressed.connect(_on_quick_save)
	menu_box.add_child(qsave_button)

	qload_button = TextureButton.new()
	qload_button.name = "ID_QLOAD"
	qload_button.position = Vector2(85, 0)
	qload_button.size = Vector2(84, 25)
	qload_button.pressed.connect(_on_quick_load)
	menu_box.add_child(qload_button)

	save_button = TextureButton.new()
	save_button.name = "ID_SAVE"
	save_button.position = Vector2(170, 0)
	save_button.size = Vector2(84, 25)
	save_button.pressed.connect(func(): _open_save_load_modal("save"))
	menu_box.add_child(save_button)

	load_button = TextureButton.new()
	load_button.name = "ID_LOAD"
	load_button.position = Vector2(255, 0)
	load_button.size = Vector2(84, 25)
	load_button.pressed.connect(func(): _open_save_load_modal("load"))
	menu_box.add_child(load_button)

	config_button = TextureButton.new()
	config_button.name = "ID_CONFIG"
	config_button.position = Vector2(366, 0)
	config_button.size = Vector2(84, 25)
	config_button.pressed.connect(_open_config_modal)
	menu_box.add_child(config_button)

	auto_button = TextureButton.new()
	auto_button.name = "ID_AUTO"
	auto_button.position = Vector2(478, 0)
	auto_button.size = Vector2(84, 25)
	auto_button.pressed.connect(_toggle_auto)
	menu_box.add_child(auto_button)

	skip_button = TextureButton.new()
	skip_button.name = "ID_SKIP"
	skip_button.position = Vector2(563, 0)
	skip_button.size = Vector2(84, 25)
	skip_button.pressed.connect(_toggle_skip)
	menu_box.add_child(skip_button)

	history_button = TextureButton.new()
	history_button.name = "ID_HISTORY"
	history_button.position = Vector2(648, 0)
	history_button.size = Vector2(84, 25)
	history_button.pressed.connect(_toggle_backlog)
	menu_box.add_child(history_button)

	# 5. Choice Selection Panel (centered overlay)
	choice_container = VBoxContainer.new()
	choice_container.name = "ChoiceContainer"
	choice_container.anchor_left = 0.2
	choice_container.anchor_right = 0.8
	choice_container.anchor_top = 0.25
	choice_container.anchor_bottom = 0.68
	choice_container.alignment = BoxContainer.ALIGNMENT_CENTER
	choice_container.add_theme_constant_override("separation", 14)
	choice_container.visible = false
	add_child(choice_container)

	# 6. Video Player Layer
	_build_video_player()

	# 7. Tone Filter Shader
	_setup_tone_shader()

	# 8. Backlog Modal Overlay
	_build_backlog_ui()

	# 9. Title Screen Overlay
	_build_title_screen_ui()

	# 10. Save/Load Modal Overlay
	_build_save_load_ui()

	# 11. Confirmation Dialog Overlay
	_build_confirm_dialog()

	# 12. Appreciation / Gallery & Jukebox Overlay
	_build_appreciation_ui()

	# 13. Fullscreen CG Viewer Overlay
	_build_cg_fullscreen_viewer()

	# 14. Native Config / Options Modal Overlay
	_build_config_ui()

	# 15. Voice Details Sub-Window Overlay
	_build_voice_details_ui()


func _build_video_player() -> void:
	video_player = VideoStreamPlayer.new()
	video_player.name = "VideoPlayer"
	video_player.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	video_player.expand = true
	video_player.visible = false
	video_player.finished.connect(_on_video_finished)
	add_child(video_player)


func _build_backlog_ui() -> void:
	backlog_panel = PanelContainer.new()
	backlog_panel.name = "BacklogPanel"
	backlog_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backlog_panel.visible = false
	backlog_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var backdrop_style := StyleBoxFlat.new()
	backdrop_style.bg_color = Color(0.02, 0.03, 0.05, 0.82)
	backlog_panel.add_theme_stylebox_override("panel", backdrop_style)
	add_child(backlog_panel)

	var center_root := Control.new()
	center_root.name = "BacklogCenterRoot"
	center_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backlog_panel.add_child(center_root)

	var win_box := Control.new()
	win_box.name = "BacklogWindowBox"
	win_box.anchor_left = 0.5
	win_box.anchor_right = 0.5
	win_box.anchor_top = 0.5
	win_box.anchor_bottom = 0.5
	win_box.offset_left = -350.0
	win_box.offset_right = 351.0
	win_box.offset_top = -252.0
	win_box.offset_bottom = 252.0
	win_box.custom_minimum_size = Vector2(701, 504)
	win_box.size = Vector2(701, 504)
	center_root.add_child(win_box)

	var bg_rect := TextureRect.new()
	bg_rect.name = "BacklogBg"
	bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win_box.add_child(bg_rect)

	var close_btn := Button.new()
	close_btn.name = "BacklogCloseBtn"
	close_btn.text = "✕"
	close_btn.position = Vector2(665, 8)
	close_btn.size = Vector2(28, 28)
	close_btn.flat = true
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.pressed.connect(_toggle_backlog)
	win_box.add_child(close_btn)

	backlog_scroll = ScrollContainer.new()
	backlog_scroll.name = "BacklogScroll"
	backlog_scroll.position = Vector2(24, 18)
	backlog_scroll.size = Vector2(650, 468)
	backlog_scroll.follow_focus = true
	win_box.add_child(backlog_scroll)

	backlog_vbox = VBoxContainer.new()
	backlog_vbox.name = "BacklogVBox"
	backlog_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	backlog_vbox.add_theme_constant_override("separation", 14)
	backlog_scroll.add_child(backlog_vbox)



func _setup_audio() -> void:
	bgm_player = AudioStreamPlayer.new()
	bgm_player.name = "BgmPlayer"
	add_child(bgm_player)

	system_player = AudioStreamPlayer.new()
	system_player.name = "SystemPlayer"
	add_child(system_player)

	env_se_player = AudioStreamPlayer.new()
	env_se_player.name = "EnvSePlayer"
	add_child(env_se_player)

	se_player = AudioStreamPlayer.new()
	se_player.name = "SePlayer"
	add_child(se_player)

	voice_player = AudioStreamPlayer.new()
	voice_player.name = "VoicePlayer"
	add_child(voice_player)


func _object_has_property(target: Object, property_name: String) -> bool:
	for property: Dictionary in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _start_engine() -> void:
	var game_files := _resolve_game_script()
	csx_script_path = str(game_files.get("script_path", ""))
	if csx_script_path.is_empty():
		var checked_paths: Array = game_files.get("attempted_paths", [])
		var paths_text := ""
		for path in checked_paths:
			paths_text += ("\n" if not paths_text.is_empty() else "") + str(path)
		message_label.text = (
			"[color=#e06c75]未找到原版脚本 yosuga.csx，播放器未启动。[/color]\n\n"
			+ "请将游戏资源目录作为命令行参数传入，或设置环境变量 YOSUGA_GAME_DIR。"
			+ "也可将资源放入 res://assets 或 user://game。\n\n"
			+ "已检查位置：\n" + paths_text
		)
		push_error("[AdvPlayer] yosuga.csx not found; refusing to start the game runtime.")
		return
	game_dir = str(game_files.get("game_dir", ""))
	print("[AdvPlayer] Using game resources from: %s" % game_dir)

	host = CsxHostClass.new(game_dir)
	host.cursor_position_provider = Callable(self, "_get_native_cursor_position")
	if not save_dir_override.is_empty():
		host.save_dir = save_dir_override
	host.bgm_player = bgm_player
	if _object_has_property(host, "system_player"):
		host.set("system_player", system_player)
	host.env_se_player = env_se_player
	host.se_player = se_player
	host.voice_player = voice_player
	_restore_player_settings()
	_apply_config_state()

	host.dialogue_updated.connect(_on_dialogue_updated)
	host.message_output.connect(_on_message_output)
	host.message_progress.connect(_on_message_progress)
	host.bg_updated.connect(_on_bg_updated)
	host.choices_updated.connect(_on_choices_updated)
	host.movie_requested.connect(_on_movie_requested)
	host.movie_stop_requested.connect(_on_movie_stop_requested)
	host.tone_filter_updated.connect(_on_tone_filter_updated)
	_apply_dialogue_skin()
	_apply_config_skin()
	_apply_voice_details_skin()
	_apply_save_load_skin()
	_apply_backlog_skin()
	_apply_confirm_skin()
	_apply_appreciation_skin()

	vm = CsxVMReader.new(host)
	_init_cg_catalog()

	var csx_path := csx_script_path
	message_label.text = "正在加载脚本: %s ..." % csx_path
	var load_res := vm.load_csx(csx_path)
	if not load_res.get("ok", false):
		message_label.text = "[color=#e06c75]加载脚本失败: %s[/color]" % load_res.get("error", "")
		return

	message_label.text = "正在执行脚本初始化..."
	var pro_res := vm.execute_prologues()
	if not pro_res.get("ok", false):
		message_label.text = "[color=#e06c75]Prologue 执行失败: %s[/color]" % pro_res.get("error", "")
		return

	var init_res := vm.call_function_sync("Initialize", [], 500_000)
	if not init_res.get("ok", false):
		message_label.text = "[color=#e06c75]Initialize() 失败: %s[/color]" % init_res.get("error", "")
		return

	var setup_res := vm.call_function_sync("SetupAdvScreen", [], 100_000)
	if not setup_res.get("ok", false):
		message_label.text = "[color=#e06c75]SetupAdvScreen() 失败: %s[/color]" % setup_res.get("error", "")
		return

	# Native Initialize() may set Entis category master volumes. Restore the
	# user's persisted settings after it has finished, before script playback.
	_apply_config_state()
	is_initialized = true

	if start_in_title:
		_show_title_screen()
		return

	# Start scenario driver via ScenarioLoop
	if not vm.functions.has("ScenarioLoop"):
		message_label.text = "[color=#e06c75]未找到主剧情循环 ScenarioLoop[/color]"
		return

	vm.ip = vm.functions["ScenarioLoop"]
	vm.is_halted = false
	vm.pending_call_args = [start_scenario]
	vm.pending_return_ip = -1
	vm.call_stack.clear()
	vm.eval_stack.clear()

	is_running = true
	print("[AdvPlayer] Engine started successfully with ScenarioLoop('%s')." % start_scenario)


func _process(delta: float) -> void:
	if not is_initialized:
		return
	if host != null:
		host.advance_audio_envelopes(delta)
	if is_title_mode:
		if not is_running or is_appreciation_open or is_config_open or is_save_load_open or confirm_panel.visible:
			return
		host.advance_sprite_animations(delta)
		_process_native_title()
		return
	if _is_story_paused():
		return

	host.advance_sprite_animations(delta)
	_update_native_dialogue_transform()
	_update_bustups()

	# Handle blinking advance indicator
	indicator_timer += delta * 4.0
	if host.is_waiting_input and not host.is_waiting_choice:
		indicator.visible = int(indicator_timer) % 2 == 0
	else:
		indicator.visible = false

	# If waiting for choice selection, pause automatic advance
	if host != null and host.is_waiting_choice:
		return

	# Auto advance handling
	if auto_mode and host.is_waiting_input:
		auto_timer += delta
		if voice_player != null and voice_player.playing:
			auto_timer = 0.0
		elif auto_timer >= settings_state.auto_delay_seconds():
			auto_timer = 0.0
			_advance_line()

	# Skip mode handling
	if skip_mode and host != null and host.is_waiting_input:
		_advance_line()

	# Activation checks yield for one frame so the script can recheck the sprite.
	host.yield_for_sprite_activation = false

	# Run VM steps if not waiting for player input or choices
	if host != null and not host.is_waiting_input and not host.is_waiting_choice:
		var executed := 0
		var limit := steps_per_frame if not skip_mode else steps_per_frame * 3
		while not host.is_waiting_input and not host.is_waiting_choice and not host.yield_for_sprite_activation and executed < limit and not vm.is_halted:
			if not vm.step():
				is_running = false
				message_label.text = "[color=#e06c75]VM 执行中断: %s[/color]" % vm.last_error
				print("[AdvPlayer] VM halted with error: ", vm.last_error)
				break
			executed += 1
		if is_recollect_mode and (vm.is_halted or not is_running):
			_end_scene_recollection()
			return


func _is_story_paused() -> bool:
	return (
		not is_running
		or is_save_load_open
		or is_backlog_open
		or is_config_open
		or is_voice_details_open
		or is_appreciation_open
		or (confirm_panel != null and confirm_panel.visible)
		or (cg_fullscreen_panel != null and cg_fullscreen_panel.visible)
	)


func _gui_input(event: InputEvent) -> void:
	if is_title_mode or is_save_load_open or (confirm_panel != null and confirm_panel.visible) or is_appreciation_open or (cg_fullscreen_panel != null and cg_fullscreen_panel.visible) or is_config_open or is_voice_details_open:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if not is_backlog_open:
				_toggle_backlog()
				accept_event()
				return
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if is_backlog_open:
				_toggle_backlog()
				accept_event()
				return
			elif dialogue_box != null:
				dialogue_box.visible = not dialogue_box.visible
				accept_event()
				return
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if dialogue_box != null and not dialogue_box.visible:
				dialogue_box.visible = true
				accept_event()
				return
			if not is_backlog_open and host != null and host.is_waiting_input and not host.is_waiting_choice:
				_advance_line()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_CTRL:
		if host != null and not _is_story_paused():
			host.skip_input_pending = true
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			if is_title_mode and native_appreciation_mode:
				_close_native_appreciation()
				get_viewport().set_input_as_handled()
				return
			if cg_fullscreen_panel != null and cg_fullscreen_panel.visible:
				_close_cg_fullscreen()
				get_viewport().set_input_as_handled()
				return
			if is_voice_details_open:
				_close_voice_details_modal()
				get_viewport().set_input_as_handled()
				return
			if is_config_open:
				_close_config_modal()
				get_viewport().set_input_as_handled()
				return
			if is_appreciation_open:
				_close_appreciation_modal()
				get_viewport().set_input_as_handled()
				return
			if confirm_panel != null and confirm_panel.visible:
				_close_confirm_dialog()
				get_viewport().set_input_as_handled()
				return
			if is_save_load_open:
				_close_save_load_modal()
				get_viewport().set_input_as_handled()
				return
			if is_backlog_open:
				_toggle_backlog()
				get_viewport().set_input_as_handled()
				return
			if not is_title_mode:
				_open_config_modal()
				get_viewport().set_input_as_handled()
				return
		elif (cg_fullscreen_panel != null and cg_fullscreen_panel.visible):
			if event.keycode == KEY_RIGHT or event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
				_next_cg_variant()
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_LEFT:
				_prev_cg_variant()
				get_viewport().set_input_as_handled()
				return
		elif event.keycode == KEY_PAGEUP:
			if not is_backlog_open and not is_title_mode and not is_save_load_open and not is_appreciation_open and not is_config_open:
				_toggle_backlog()
				get_viewport().set_input_as_handled()
				return
	if is_title_mode or is_save_load_open or (confirm_panel != null and confirm_panel.visible) or is_appreciation_open or (cg_fullscreen_panel != null and cg_fullscreen_panel.visible) or is_config_open or is_voice_details_open:
		return
	if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and (event.keycode == KEY_SPACE or event.keycode == KEY_ENTER)):
		if dialogue_box != null and not dialogue_box.visible:
			dialogue_box.visible = true
			get_viewport().set_input_as_handled()
			return
		if not is_backlog_open and host != null and host.is_waiting_input and not host.is_waiting_choice:
			_advance_line()


func _advance_line() -> void:
	if host != null:
		host.advance_ticks = 1
		host.is_waiting_input = false
		auto_timer = 0.0


func _update_native_dialogue_transform() -> void:
	if vm == null or vm.data_vars.size() <= 4 or dialogue_box == null:
		return
	var window = vm.data_vars[4].get("value", null)
	if not window is CsxHostClass.HostWindow:
		return
	for sprite in window.root_sprites:
		for child in sprite.children:
			if child.message_style.get("id") == "ID_FONT_MESSAGE":
				dialogue_box.pivot_offset = Vector2(sprite.rev_center)
				dialogue_box.scale = sprite.magnification
				dialogue_box.modulate.a = 1.0 - float(sprite.transparency) / 256.0
				return


func _update_bustups() -> void:
	if vm == null:
		return
	var adv = vm.globals_by_name.get("adv", null)
	if not (adv is CsxVMReader.CsxInstance):
		return
	var base_sprite: Variant = adv.get_field("sprAdvBase")
	var active_tone_filter: CsxHostClass.HostToneFilter = base_sprite.tone_filter if base_sprite is CsxHostClass.HostSprite else null
	if tone_material != null and active_tone_filter != null:
		tone_material.set_shader_parameter("tone_lut", active_tone_filter.get_tone_texture())
		tone_material.set_shader_parameter("tone_flags", active_tone_filter.tone_flags)
		tone_material.set_shader_parameter("use_tone_lut", true)
	elif tone_material != null:
		tone_material.set_shader_parameter("use_tone_lut", false)
	var bm = adv.get_field("bustupMan")
	if not (bm is CsxVMReader.CsxInstance):
		return
	var sprs: Array = bm.get_field("spr")
	for i in range(mini(sprs.size(), bustup_rects.size())):
		var spr = sprs[i]
		var b_rect: TextureRect = bustup_rects[i]
		if spr is CsxHostClass.HostSprite and spr.is_visible and spr.texture != null:
			b_rect.visible = true
			if b_rect.texture != spr.texture:
				b_rect.texture = spr.texture
			var tex_w: int = spr.texture.get_width()
			var tex_h: int = spr.texture.get_height()
			b_rect.size = Vector2(tex_w, tex_h)
			var ox: float = spr.rev_center.x if spr.rev_center != Vector2i.ZERO else (tex_w / 2.0)
			var oy: float = spr.rev_center.y if spr.rev_center != Vector2i.ZERO else float(tex_h)
			b_rect.position = Vector2(spr.position.x - ox, spr.position.y - oy)
			b_rect.modulate.a = 1.0 - (float(spr.transparency) / 256.0)
		else:
			b_rect.visible = false


func _on_choices_updated(choices: Array) -> void:
	for btn in choice_buttons:
		if is_instance_valid(btn):
			btn.queue_free()
	choice_buttons.clear()

	if choices.is_empty():
		choice_container.visible = false
		return

	choice_container.visible = true
	for i in range(choices.size()):
		var choice_text: String = str(choices[i])
		var btn := Button.new()
		btn.text = choice_text
		btn.custom_minimum_size = Vector2(0, 52)
		btn.add_theme_font_size_override("font_size", 18)

		var normal_style := StyleBoxFlat.new()
		normal_style.bg_color = Color(0.08, 0.12, 0.18, 0.92)
		normal_style.border_color = Color(0.35, 0.45, 0.6, 0.8)
		normal_style.set_border_width_all(2)
		normal_style.set_corner_radius_all(6)
		btn.add_theme_stylebox_override("normal", normal_style)

		var hover_style := StyleBoxFlat.new()
		hover_style.bg_color = Color(0.15, 0.22, 0.32, 0.95)
		hover_style.border_color = Color(0.55, 0.7, 0.9, 1.0)
		hover_style.set_border_width_all(2)
		hover_style.set_corner_radius_all(6)
		btn.add_theme_stylebox_override("hover", hover_style)

		var pressed_style := StyleBoxFlat.new()
		pressed_style.bg_color = Color(0.2, 0.3, 0.45, 0.98)
		pressed_style.border_color = Color(0.7, 0.85, 1.0, 1.0)
		pressed_style.set_border_width_all(2)
		pressed_style.set_corner_radius_all(6)
		btn.add_theme_stylebox_override("pressed", pressed_style)

		btn.pressed.connect(_on_choice_clicked.bind(i))
		choice_container.add_child(btn)
		choice_buttons.append(btn)


func _on_choice_clicked(index: int) -> void:
	if host != null:
		print("[AdvPlayer] Player selected choice %d: %s" % [index + 1, host.current_choices[index] if index < host.current_choices.size() else ""])
		host.selected_choice = index + 1
		host.is_waiting_choice = false
		host.current_choices.clear()
	choice_container.visible = false
	for btn in choice_buttons:
		if is_instance_valid(btn):
			btn.queue_free()
	choice_buttons.clear()


func _on_movie_requested(movie_file: String) -> void:
	print("[AdvPlayer] Movie playback requested: %s" % movie_file)
	var base_name := movie_file.get_file().get_basename()
	var candidates: Array[String] = [
		game_dir.path_join(base_name + ".ogv"),
		game_dir.path_join("movie").path_join(base_name + ".ogv"),
		"user://video/".path_join(base_name + ".ogv"),
		"res://video/".path_join(base_name + ".ogv")
	]
	var found_path := ""
	for c in candidates:
		if FileAccess.file_exists(c):
			found_path = c
			break

	if not found_path.is_empty():
		print("[AdvPlayer] Playing video fallback from: ", found_path)
		var stream := VideoStreamTheora.new()
		stream.file = found_path
		video_player.stream = stream
		video_player.visible = true
		video_player.play()
		host.is_movie_playing = true
	else:
		print("[AdvPlayer] Proprietary MEI video '%s' requested, no OGV fallback found. Skipping movie safely." % movie_file)
		host.is_movie_playing = false


func _on_video_finished() -> void:
	video_player.stop()
	video_player.visible = false
	if host != null:
		host.is_movie_playing = false
	print("[AdvPlayer] Video playback finished.")


func _on_movie_stop_requested() -> void:
	if video_player != null:
		video_player.stop()
		video_player.visible = false
	if host != null:
		host.is_movie_playing = false


func _on_dialogue_updated(entry: Dictionary) -> void:
	var voc: String = entry.get("voice", "")
	voice_button.visible = not voc.is_empty()
	auto_timer = 0.0

	# Check background texture
	if host != null and host.current_bg_texture != null and bg_rect.texture != host.current_bg_texture:
		bg_rect.texture = host.current_bg_texture


func _on_message_output(sprite: CsxHostClass.HostSprite) -> void:
	if not is_initialized or is_title_mode:
		return
	if sprite.message_style.get("id") == "ID_FONT_NAME":
		speaker_label.position = Vector2(sprite.position - sprite.rev_center)
		if speaker_label.get_meta("message_style", {}) != sprite.message_style:
			_apply_native_text_style(speaker_label, sprite.message_style)
			speaker_label.set_meta("message_style", sprite.message_style)
		speaker_label.text = sprite.display_text()
		return
	if sprite.message_style.get("id") != "ID_FONT_MESSAGE":
		return
	message_label.position = Vector2(sprite.position - sprite.rev_center)
	if sprite.size.x > 0 and sprite.size.y > 0:
		message_label.size = Vector2(sprite.size)
	if message_label.get_meta("message_style", {}) != sprite.message_style:
		_apply_native_text_style(message_label, sprite.message_style)
		message_label.set_meta("message_style", sprite.message_style)
	message_label.text = _format_native_message(sprite)
	message_label.visible_characters = sprite.message_visible_count
	if not sprite.message_pending:
		_clear_native_message_fade_effect()


func _on_message_progress(sprite: CsxHostClass.HostSprite) -> void:
	if sprite.message_style.get("id") == "ID_FONT_MESSAGE":
		if not sprite.message_pending:
			message_label.text = _format_native_message(sprite)
		message_label.visible_characters = sprite.message_visible_count
		if not sprite.message_pending:
			_clear_native_message_fade_effect()


func _format_native_message(sprite: CsxHostClass.HostSprite) -> String:
	var text := sprite.display_text().replace("[", "[lb]").replace("]", "[rb]")
	if not sprite.message_pending or sprite.message_fade_ms <= 0:
		return text
	if message_label.custom_effects.is_empty():
		message_label.install_effect(NativeMessageFadeEffect.new())
	return "[native_fade interval_ms=%d fade_ms=%d]%s[/native_fade]" % [sprite.message_char_speed_ms, sprite.message_fade_ms, text]


func _clear_native_message_fade_effect() -> void:
	if not message_label.custom_effects.is_empty():
		message_label.custom_effects = []
		message_label.reload_effects()


func _on_bg_updated(bg_name: String, texture: Texture2D) -> void:
	if texture != null:
		bg_rect.texture = texture
		print("[AdvPlayer] Background updated to: ", bg_name)


func _toggle_auto() -> void:
	auto_mode = not auto_mode
	if auto_button is Button:
		(auto_button as Button).text = "自动: 开" if auto_mode else "自动: 关"
	elif auto_button is TextureButton:
		(auto_button as TextureButton).modulate = Color(1.3, 1.3, 1.3, 1.0) if auto_mode else Color(1.0, 1.0, 1.0, 1.0)
	auto_timer = 0.0


func _toggle_skip() -> void:
	skip_mode = not skip_mode
	if skip_button is Button:
		(skip_button as Button).text = "快进: 开" if skip_mode else "快进: 关"
	elif skip_button is TextureButton:
		(skip_button as TextureButton).modulate = Color(1.3, 1.3, 1.3, 1.0) if skip_mode else Color(1.0, 1.0, 1.0, 1.0)


func _hide_dialogue_box() -> void:
	if dialogue_box != null:
		dialogue_box.visible = false


func _show_dialogue_box() -> void:
	if dialogue_box != null:
		dialogue_box.visible = true


func _replay_voice() -> void:
	if host != null and not host.current_voice.is_empty():
		host.play_voice(host.current_voice)


func _toggle_backlog() -> void:
	is_backlog_open = not is_backlog_open
	backlog_panel.visible = is_backlog_open
	if is_backlog_open:
		_populate_backlog()
		call_deferred("_scroll_backlog_to_bottom")


func _scroll_backlog_to_bottom() -> void:
	if backlog_scroll != null:
		var v_bar := backlog_scroll.get_v_scroll_bar()
		if v_bar != null:
			backlog_scroll.scroll_vertical = int(v_bar.max_value)


func _populate_backlog() -> void:
	for c in backlog_vbox.get_children():
		backlog_vbox.remove_child(c)
		c.queue_free()

	if host == null or host.text_history.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "暂无剧情历史记录。"
		empty_lbl.add_theme_color_override("font_color", Color("#7f848e"))
		backlog_vbox.add_child(empty_lbl)
		return

	for entry in host.text_history:
		var spk: String = entry.get("speaker", "")
		var txt: String = entry.get("text", "")
		var voc: String = entry.get("voice", "")

		var item_panel := PanelContainer.new()
		var item_style := StyleBoxFlat.new()
		item_style.bg_color = Color(0.08, 0.10, 0.15, 0.8)
		item_style.set_corner_radius_all(6)
		item_panel.add_theme_stylebox_override("panel", item_style)

		var imargin := MarginContainer.new()
		imargin.add_theme_constant_override("margin_left", 14)
		imargin.add_theme_constant_override("margin_right", 14)
		imargin.add_theme_constant_override("margin_top", 10)
		imargin.add_theme_constant_override("margin_bottom", 10)
		item_panel.add_child(imargin)

		var ivbox := VBoxContainer.new()
		ivbox.add_theme_constant_override("separation", 6)
		imargin.add_child(ivbox)

		var top_row := HBoxContainer.new()
		ivbox.add_child(top_row)

		var spk_lbl := Label.new()
		spk_lbl.text = spk if not spk.is_empty() else "（旁白）"
		spk_lbl.add_theme_font_size_override("font_size", 16)
		spk_lbl.add_theme_color_override("font_color", Color("#e5c07b") if not spk.is_empty() else Color("#98c379"))
		spk_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top_row.add_child(spk_lbl)

		if not voc.is_empty():
			var v_btn := Button.new()
			v_btn.text = "🔊 重听"
			v_btn.add_theme_font_size_override("font_size", 13)
			v_btn.pressed.connect(func(): if host != null: host.play_voice(voc))
			top_row.add_child(v_btn)

		var msg_lbl := Label.new()
		msg_lbl.text = txt
		msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		msg_lbl.add_theme_font_size_override("font_size", 16)
		msg_lbl.add_theme_color_override("font_color", Color("#dedede"))
		ivbox.add_child(msg_lbl)

		backlog_vbox.add_child(item_panel)


func _on_quick_save() -> void:
	save_to_slot(0)


func _on_quick_load() -> void:
	load_from_slot(0)


# ==============================================================================
# Tone Filter Shader Setup
# ==============================================================================

const TONE_SHADER_CODE = """
shader_type canvas_item;

uniform int filter_mode = 0; // fallback filter presets
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform bool use_tone_lut = false;
uniform sampler2D tone_lut : filter_nearest;
uniform int tone_flags = 0;

float tone_coord(float value) {
	return (floor(clamp(value, 0.0, 1.0) * 255.0 + 0.5) + 0.5) / 256.0;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (use_tone_lut) {
		if ((tone_flags & 8) != 0) {
			float gray = dot(c.rgb, vec3(0.299, 0.587, 0.114));
			c.rgb = vec3(gray);
		} else if ((tone_flags & 4) != 0) {
				// Match EntisGLS eglRGBtoYUV/eglYUVtoRGB byte coefficients.
				float y = (c.r * 75.0 + c.g * 149.0 + c.b * 32.0) / 256.0;
				float u = (c.r * -43.0 + c.g * -85.0 + c.b * 128.0) / 256.0 + 0.5;
				float v = (c.r * 121.0 + c.g * -100.0 + c.b * -21.0) / 256.0 + 0.5;
				// eglApplyToneTable receives blue, green, red tables. In YUV storage,
				// byte 0 is Y, byte 1 is U and byte 2 is V.
				y = texture(tone_lut, vec2(tone_coord(y), 0.5)).b;
				u = texture(tone_lut, vec2(tone_coord(u), 0.5)).g - 0.5;
				v = texture(tone_lut, vec2(tone_coord(v), 0.5)).r - 0.5;
				c.rgb = clamp(vec3(
					y + 1.5 * v,
					y - 0.375 * u - 0.75 * v,
					y + 1.75 * u), 0.0, 1.0);
		} else {
			c.r = texture(tone_lut, vec2(tone_coord(c.r), 0.5)).r;
			c.g = texture(tone_lut, vec2(tone_coord(c.g), 0.5)).g;
			c.b = texture(tone_lut, vec2(tone_coord(c.b), 0.5)).b;
		}
		c.a = texture(tone_lut, vec2(tone_coord(c.a), 0.5)).a;
		if ((tone_flags & 2) != 0) c.rgb *= c.a;
	} else if (filter_mode == 1) { // SEPIA
		float gray = dot(c.rgb, vec3(0.299, 0.587, 0.114));
		vec3 sepia = vec3(gray * 1.2, gray * 0.95, gray * 0.7);
		c.rgb = mix(c.rgb, clamp(sepia, 0.0, 1.0), intensity);
	} else if (filter_mode == 2) { // MONO
		float gray = dot(c.rgb, vec3(0.299, 0.587, 0.114));
		c.rgb = mix(c.rgb, vec3(gray), intensity);
	} else if (filter_mode == 3) { // NEGATIVE
		vec3 neg = vec3(1.0) - c.rgb;
		c.rgb = mix(c.rgb, neg, intensity);
	}
	COLOR = c;
}
"""

func _setup_tone_shader() -> void:
	var shader := Shader.new()
	shader.code = TONE_SHADER_CODE
	tone_material = ShaderMaterial.new()
	tone_material.shader = shader
	tone_material.set_shader_parameter("filter_mode", 0)
	tone_material.set_shader_parameter("intensity", 1.0)
	bg_rect.material = tone_material
	for b in bustup_rects:
		b.material = tone_material


func _on_tone_filter_updated(filter_type: String) -> void:
	var mode := 0
	var f_upper := filter_type.to_upper()
	if f_upper == "SEPIA":
		mode = 1
	elif f_upper in ["MONO", "GRAY", "MONOCHROME"]:
		mode = 2
	elif f_upper in ["NEGATIVE", "INVERT"]:
		mode = 3
	else:
		mode = 0
	if tone_material != null:
		tone_material.set_shader_parameter("use_tone_lut", false)
		tone_material.set_shader_parameter("filter_mode", mode)
	print("[AdvPlayer] Tone filter set to: %s (mode %d)" % [filter_type, mode])


# ==============================================================================
# Confirmation Dialog
# ==============================================================================

func _build_confirm_dialog() -> void:
	confirm_panel = PanelContainer.new()
	confirm_panel.name = "ConfirmModal"
	confirm_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	confirm_panel.visible = false
	confirm_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var backdrop_style := StyleBoxFlat.new()
	backdrop_style.bg_color = Color(0.0, 0.0, 0.0, 0.7)
	confirm_panel.add_theme_stylebox_override("panel", backdrop_style)
	add_child(confirm_panel)

	var center := Control.new()
	center.name = "ConfirmCenterRoot"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	confirm_panel.add_child(center)

	var dialog_box := Control.new()
	dialog_box.name = "ConfirmWindowBox"
	dialog_box.anchor_left = 0.5
	dialog_box.anchor_right = 0.5
	dialog_box.anchor_top = 0.5
	dialog_box.anchor_bottom = 0.5
	dialog_box.offset_left = -400.0
	dialog_box.offset_right = 400.0
	dialog_box.offset_top = -60.0
	dialog_box.offset_bottom = 60.0
	dialog_box.custom_minimum_size = Vector2(800, 120)
	dialog_box.size = Vector2(800, 120)
	center.add_child(dialog_box)

	var bg_rect := TextureRect.new()
	bg_rect.name = "ConfirmBg"
	bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialog_box.add_child(bg_rect)

	confirm_label = Label.new()
	confirm_label.text = "确定要执行此操作吗？"
	confirm_label.position = Vector2(50, 20)
	confirm_label.size = Vector2(700, 36)
	confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_label.add_theme_font_size_override("font_size", 18)
	confirm_label.add_theme_color_override("font_color", Color("#eeeeee"))
	dialog_box.add_child(confirm_label)

	var ok_btn := TextureButton.new()
	ok_btn.name = "ID_YES"
	ok_btn.position = Vector2(286, 75)
	ok_btn.size = Vector2(82, 25)
	ok_btn.pressed.connect(_on_confirm_dialog_ok)
	dialog_box.add_child(ok_btn)

	var cancel_btn := TextureButton.new()
	cancel_btn.name = "ID_NO"
	cancel_btn.position = Vector2(447, 75)
	cancel_btn.size = Vector2(82, 25)
	cancel_btn.pressed.connect(_close_confirm_dialog)
	dialog_box.add_child(cancel_btn)


func _show_confirm_dialog(prompt: String, callback: Callable) -> void:
	confirm_callback = callback
	confirm_panel.z_index = 4096 if is_title_mode else 0
	confirm_label.text = prompt
	confirm_panel.visible = true


func _close_confirm_dialog() -> void:
	confirm_panel.visible = false
	confirm_callback = Callable()


func _on_confirm_dialog_ok() -> void:
	confirm_panel.visible = false
	if confirm_callback.is_valid():
		confirm_callback.call()
	confirm_callback = Callable()


func _apply_confirm_skin() -> void:
	if host == null or confirm_panel == null:
		return
	var res_mgr := CsxHostClass.HostResourceManager.new(host)
	if res_mgr.load_resource("frame.noa") != 1:
		return

	var win_box: Control = confirm_panel.find_child("ConfirmWindowBox", true, false)
	if win_box == null:
		return

	var bg_rect: TextureRect = win_box.find_child("ConfirmBg", true, false)
	var bg_res := host.load_image("FRM_0401.eri", res_mgr.loaded_archive_name)
	if bg_res.get("ok", false) and bg_res.get("texture") != null and bg_rect != null:
		bg_rect.texture = bg_res["texture"]

	var yes_btn: TextureButton = win_box.find_child("ID_YES", true, false)
	if yes_btn != null:
		var st: Dictionary = res_mgr.skin_styles.get("ID_BTN_CONFIRM_YES", {})
		var normal_info := res_mgr._resolve_skin_image(st.get("normal", ""))
		var focus_info := res_mgr._resolve_skin_image(st.get("focus", ""))
		var pushed_info := res_mgr._resolve_skin_image(st.get("pushed", ""))
		if normal_info.has("texture"): yes_btn.texture_normal = normal_info["texture"]
		if focus_info.has("texture"): yes_btn.texture_hover = focus_info["texture"]
		if pushed_info.has("texture"): yes_btn.texture_pressed = pushed_info["texture"]
		elif focus_info.has("texture"): yes_btn.texture_pressed = focus_info["texture"]

	var no_btn: TextureButton = win_box.find_child("ID_NO", true, false)
	if no_btn != null:
		var st: Dictionary = res_mgr.skin_styles.get("ID_BTN_CONFIRM_NO", {})
		var normal_info := res_mgr._resolve_skin_image(st.get("normal", ""))
		var focus_info := res_mgr._resolve_skin_image(st.get("focus", ""))
		var pushed_info := res_mgr._resolve_skin_image(st.get("pushed", ""))
		if normal_info.has("texture"): no_btn.texture_normal = normal_info["texture"]
		if focus_info.has("texture"): no_btn.texture_hover = focus_info["texture"]
		if pushed_info.has("texture"): no_btn.texture_pressed = pushed_info["texture"]
		elif focus_info.has("texture"): no_btn.texture_pressed = focus_info["texture"]


# ==============================================================================
# Title Screen UI & Logic
# ==============================================================================

func _build_title_screen_ui() -> void:
	title_panel = PanelContainer.new()
	title_panel.name = "TitlePanel"
	title_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_panel.visible = false
	title_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 1.0)
	title_panel.add_theme_stylebox_override("panel", style)
	add_child(title_panel)

	# Title background
	title_bg = TextureRect.new()
	title_bg.name = "TitleBg"
	title_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	title_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_panel.add_child(title_bg)

	# Title Logo
	title_logo = TextureRect.new()
	title_logo.name = "TitleLogo"
	title_logo.position = Vector2(223, 95)
	title_logo.size = Vector2(354, 75)
	title_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_panel.add_child(title_logo)

	# Title Sublogo
	title_sublogo = TextureRect.new()
	title_sublogo.name = "TitleSublogo"
	title_sublogo.position = Vector2(511, 171)
	title_sublogo.size = Vector2(68, 25)
	title_sublogo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title_sublogo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title_sublogo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_panel.add_child(title_sublogo)

	# Button menu container
	var menu_box := VBoxContainer.new()
	menu_box.name = "TitleMenu"
	menu_box.anchor_left = 0.58
	menu_box.anchor_right = 0.92
	menu_box.anchor_top = 0.55
	menu_box.anchor_bottom = 0.90
	menu_box.add_theme_constant_override("separation", 12)
	menu_box.alignment = BoxContainer.ALIGNMENT_CENTER
	title_panel.add_child(menu_box)

	var start_btn := Button.new()
	start_btn.name = "TitleStartBtn"
	start_btn.text = "▶ 开始新游戏 (Start Game)"
	start_btn.custom_minimum_size = Vector2(0, 42)
	start_btn.add_theme_font_size_override("font_size", 17)
	start_btn.pressed.connect(_on_title_start_game)
	menu_box.add_child(start_btn)

	var continue_btn := Button.new()
	continue_btn.name = "TitleContinueBtn"
	continue_btn.text = "📂 读取存档 (Continue)"
	continue_btn.custom_minimum_size = Vector2(0, 42)
	continue_btn.add_theme_font_size_override("font_size", 17)
	continue_btn.pressed.connect(func(): _open_save_load_modal("load"))
	menu_box.add_child(continue_btn)

	var config_btn := Button.new()
	config_btn.name = "TitleConfigBtn"
	config_btn.text = "⚙ 选项设置 (Config)"
	config_btn.custom_minimum_size = Vector2(0, 42)
	config_btn.add_theme_font_size_override("font_size", 17)
	config_btn.pressed.connect(_open_config_modal)
	menu_box.add_child(config_btn)

	var qload_btn := Button.new()
	qload_btn.name = "TitleQloadBtn"
	qload_btn.text = "⚡ 快速读取 (Quick Load)"
	qload_btn.custom_minimum_size = Vector2(0, 42)
	qload_btn.add_theme_font_size_override("font_size", 17)
	qload_btn.pressed.connect(_on_quick_load)
	menu_box.add_child(qload_btn)

	var gallery_btn := Button.new()
	gallery_btn.name = "TitleGalleryBtn"
	gallery_btn.text = "🎨 鉴赏与回想 (Extra / Gallery)"
	gallery_btn.custom_minimum_size = Vector2(0, 42)
	gallery_btn.add_theme_font_size_override("font_size", 17)
	gallery_btn.pressed.connect(_open_appreciation_modal)
	menu_box.add_child(gallery_btn)

	var quit_btn := Button.new()
	quit_btn.name = "TitleQuitBtn"
	quit_btn.text = "✕ 退出游戏 (Exit)"
	quit_btn.custom_minimum_size = Vector2(0, 42)
	quit_btn.add_theme_font_size_override("font_size", 17)
	quit_btn.pressed.connect(func(): get_tree().quit(0))
	menu_box.add_child(quit_btn)

	# The original CSX Title() function owns the title-window tree. Render that
	# HostWindow separately from the legacy fallback menu above.
	native_title_layer = Control.new()
	native_title_layer.name = "NativeTitleLayer"
	native_title_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	native_title_layer.visible = false
	native_title_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(native_title_layer)

	native_title_canvas = Control.new()
	native_title_canvas.name = "NativeTitleCanvas"
	native_title_canvas.position = Vector2.ZERO
	native_title_canvas.size = Vector2(800, 600)
	native_title_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	native_title_canvas.clip_contents = true
	native_title_layer.add_child(native_title_canvas)


func _load_title_assets() -> void:
	if host == null:
		return
	var bg_res := host.load_image("FRM_0611.eri", "title.noa")
	if bg_res.get("ok", false) and bg_res.get("texture") != null:
		title_bg.texture = bg_res["texture"]
	var logo_res := host.load_image("FRM_0612.eri", "title.noa")
	if logo_res.get("ok", false) and logo_res.get("texture") != null:
		title_logo.texture = logo_res["texture"]
	var sublogo_res := host.load_image("FRM_0613.eri", "title.noa")
	if sublogo_res.get("ok", false) and sublogo_res.get("texture") != null:
		title_sublogo.texture = sublogo_res["texture"]

	_apply_native_title_skin()

	# Play title theme
	host.play_bgm("BGM07.mio")


func _apply_native_title_skin() -> void:
	if host == null or title_panel == null:
		return
	var res_mgr := CsxHostClass.HostResourceManager.new(host)
	if res_mgr.load_resource("title.noa") != 1:
		return
	var page_spr := CsxHostClass.HostSprite.new(0, host)
	if res_mgr.create_form_page(page_spr, "ID_PAGE_MENU_FULL") != 1:
		return

	var menu_box: Control = title_panel.find_child("TitleMenu", true, false)
	if menu_box != null:
		menu_box.set_anchors_preset(Control.PRESET_TOP_LEFT)
		menu_box.position = Vector2(338, 324)
		menu_box.size = Vector2(127, 155)
		if menu_box is VBoxContainer:
			(menu_box as VBoxContainer).add_theme_constant_override("separation", 7)

	var qload_btn: Control = title_panel.find_child("TitleQloadBtn", true, false)
	if qload_btn != null:
		qload_btn.visible = false

	var btn_map := {
		"ID_START": title_panel.find_child("TitleStartBtn", true, false),
		"ID_CONTINUE": title_panel.find_child("TitleContinueBtn", true, false),
		"ID_CONFIG": title_panel.find_child("TitleConfigBtn", true, false),
		"ID_APPRECIATION": title_panel.find_child("TitleGalleryBtn", true, false),
		"ID_EXITGAME": title_panel.find_child("TitleQuitBtn", true, false),
	}

	for child in page_spr.children:
		var btn: Button = btn_map.get(child.btn_id, null)
		if btn != null:
			btn.text = ""
			btn.icon = child.btn_normal_tex
			btn.flat = true
			btn.custom_minimum_size = Vector2(127, 24)
			var empty_style := StyleBoxEmpty.new()
			btn.add_theme_stylebox_override("normal", empty_style)
			btn.add_theme_stylebox_override("hover", empty_style)
			btn.add_theme_stylebox_override("pressed", empty_style)
			btn.add_theme_stylebox_override("focus", empty_style)

			var normal_tex: Texture2D = child.btn_normal_tex
			var focus_tex: Texture2D = child.btn_focus_tex
			var pushed_tex: Texture2D = child.btn_pushed_tex if child.btn_pushed_tex else focus_tex
			btn.mouse_entered.connect(func(): if focus_tex: btn.icon = focus_tex)
			btn.mouse_exited.connect(func(): if normal_tex: btn.icon = normal_tex)
			btn.button_down.connect(func(): if pushed_tex: btn.icon = pushed_tex)
			btn.button_up.connect(func(): if btn.is_hovered() and focus_tex: btn.icon = focus_tex else: if normal_tex: btn.icon = normal_tex)

	if not title_panel.has_node("TitleVersionLabel"):
		var ver_label := Label.new()
		ver_label.name = "TitleVersionLabel"
		ver_label.text = "Ver 1.01"
		ver_label.position = Vector2(730, 575)
		ver_label.add_theme_font_size_override("font_size", 13)
		ver_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
		title_panel.add_child(ver_label)


func _show_title_screen() -> void:
	if title_bg != null: title_bg.visible = false
	if title_logo != null: title_logo.visible = false
	if title_sublogo != null: title_sublogo.visible = false
	var old_menu := title_panel.find_child("TitleMenu", true, false) if title_panel != null else null
	if old_menu is Control: old_menu.visible = false
	var old_version := title_panel.find_child("TitleVersionLabel", true, false) if title_panel != null else null
	if old_version is Control: old_version.visible = false
	title_panel.visible = true
	if not _start_native_title_script():
		# Keep a visible fallback if this CSX build has no native Title function.
		_load_title_assets()
		if title_bg != null: title_bg.visible = true
		if title_logo != null: title_logo.visible = true
		if title_sublogo != null: title_sublogo.visible = true
		if old_menu is Control: old_menu.visible = true
		return
	print("[AdvPlayer] Switched to original CSX Title() screen.")


func _start_native_title_script() -> bool:
	if vm == null or host == null or not vm.functions.has("Title"):
		return false
	if native_title_layer != null:
		native_title_layer.visible = true
	if native_title_canvas != null:
		for old_child in native_title_canvas.get_children():
			native_title_canvas.remove_child(old_child)
			old_child.queue_free()
	native_title_controls.clear()
	native_appreciation_mode = false
	if title_panel != null:
		title_panel.visible = true
	host.command_queue.clear()
	vm.ip = vm.functions["Title"]
	vm.is_halted = false
	vm.pending_call_args.clear()
	vm.pending_return_ip = -1
	vm.call_stack.clear()
	vm.eval_stack.clear()
	vm.last_return_value = null
	vm.last_error = ""
	native_title_result_handled = false
	is_title_mode = true
	is_running = true
	return true


func _start_native_appreciation_script() -> bool:
	if vm == null or host == null or not vm.functions.has("Appreciation"):
		return false
	if native_title_layer != null:
		native_title_layer.visible = true
	if native_title_canvas != null:
		for old_child in native_title_canvas.get_children():
			native_title_canvas.remove_child(old_child)
			old_child.queue_free()
	native_title_controls.clear()
	host.command_queue.clear()
	vm.ip = vm.functions["Appreciation"]
	vm.is_halted = false
	vm.pending_call_args.clear()
	vm.pending_return_ip = -1
	vm.call_stack.clear()
	vm.eval_stack.clear()
	vm.last_return_value = null
	vm.last_error = ""
	native_title_result_handled = false
	native_appreciation_mode = true
	is_title_mode = true
	is_running = true
	print("[AdvPlayer] Switched to original CSX Appreciation() screen.")
	return true


func _close_native_appreciation() -> void:
	if not native_appreciation_mode:
		return
	_start_native_title_script()


func _process_native_title() -> void:
	if vm == null or host == null:
		return
	_sync_native_title_canvas()
	if vm.is_halted:
		if native_appreciation_mode:
			_start_native_title_script()
		else:
			_handle_native_title_return()
		return
	var executed := 0
	host.yield_for_sprite_activation = false
	while executed < NATIVE_TITLE_STEPS_PER_FRAME and not vm.is_halted and not host.yield_for_sprite_activation:
		if not vm.step():
			is_running = false
			message_label.text = "[color=#e06c75]标题脚本执行中断: %s[/color]" % vm.last_error
			var frames: Array[String] = []
			for frame: Variant in vm.call_stack:
				frames.append(str(frame.name))
			push_error("[AdvPlayer] Native screen stopped at 0x%X (%s): %s" % [vm.ip, " > ".join(frames), vm.last_error])
			return
		executed += 1
	_sync_native_title_canvas()
	if vm.is_halted:
		if native_appreciation_mode:
			_start_native_title_script()
		else:
			_handle_native_title_return()


func _handle_native_title_return() -> void:
	if native_title_result_handled:
		return
	native_title_result_handled = true
	var result := int(vm.last_return_value) if vm.last_return_value is int or vm.last_return_value is float else 0
	match result:
		1:
			_on_title_start_game()
		3:
			if not _start_native_appreciation_script():
				_start_native_title_script()
		_:
			# A zero result is used by native sub-flows such as cancel/back.
			# Re-enter Title() to return to its original command loop.
			_start_native_title_script()


func _sync_native_title_canvas() -> void:
	if native_title_canvas == null or vm == null or vm.data_vars.size() <= 4:
		return
	var viewport_size := get_viewport_rect().size
	if viewport_size != native_title_last_viewport_size:
		native_title_last_viewport_size = viewport_size
		var scale_factor := minf(viewport_size.x / 800.0, viewport_size.y / 600.0)
		native_title_canvas.scale = Vector2.ONE * scale_factor
		native_title_canvas.position = (viewport_size - Vector2(800, 600) * scale_factor) * 0.5
		native_title_canvas.size = Vector2(800, 600)
	var window = vm.data_vars[4].get("value", null)
	if not (window is CsxHostClass.HostWindow):
		return
	var filter_title_depth := is_title_mode and not native_appreciation_mode
	var seen: Dictionary = {}
	_sync_native_sprite_children(window.root_sprites, native_title_canvas, seen, filter_title_depth)
	for instance_id in native_title_controls.keys():
		if not seen.has(instance_id):
			var stale_node: Node = native_title_controls[instance_id]
			if is_instance_valid(stale_node):
				stale_node.queue_free()
			native_title_controls.erase(instance_id)


func _get_native_cursor_position() -> Vector2i:
	var viewport_size := get_viewport_rect().size
	var scale_factor := minf(viewport_size.x / 800.0, viewport_size.y / 600.0)
	if scale_factor <= 0.0:
		return Vector2i.ZERO
	var canvas_origin := (viewport_size - Vector2(800.0, 600.0) * scale_factor) * 0.5
	var logical_position := (get_global_mouse_position() - canvas_origin) / scale_factor
	return Vector2i(roundi(logical_position.x), roundi(logical_position.y))


func _sync_native_sprite_children(sprites: Array, parent: Control, seen: Dictionary, filter_title_depth: bool) -> void:
	# Keep painting and mouse hit order consistent with the source depth.
	var ordered := sprites.duplicate()
	ordered.sort_custom(func(a: CsxHostClass.HostSprite, b: CsxHostClass.HostSprite): return a.z_order > b.z_order)
	var next_index := parent.get_child_count()
	for child in parent.get_children():
		if child.has_meta("native_sprite_id"):
			next_index = child.get_index()
			break
	for sprite: CsxHostClass.HostSprite in ordered:
		_sync_native_title_sprite(sprite, parent, seen, filter_title_depth)
		var wrapper: Control = native_title_controls[sprite.get_instance_id()]
		if wrapper.get_index() != next_index:
			parent.move_child(wrapper, next_index)
		next_index += 1


func _sync_native_title_sprite(sprite: CsxHostClass.HostSprite, parent: Control, seen: Dictionary, filter_title_depth: bool) -> void:
	var instance_id := sprite.get_instance_id()
	seen[instance_id] = true
	var wrapper: Control = native_title_controls.get(instance_id, null)
	if wrapper == null or not is_instance_valid(wrapper):
		wrapper = Control.new()
		wrapper.name = "NativeSprite_%d" % sprite.sprite_id
		wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrapper.z_as_relative = true
		wrapper.set_meta("native_sprite_id", instance_id)
		native_title_controls[instance_id] = wrapper
		if sprite.is_button:
			var button := TextureButton.new()
			button.name = "NativeButton"
			button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			button.ignore_texture_size = true
			button.stretch_mode = TextureButton.STRETCH_SCALE
			button.focus_mode = Control.FOCUS_ALL
			button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			button.pressed.connect(_on_native_title_button_pressed.bind(sprite))
			wrapper.add_child(button)
		elif sprite.fields.get("control_type", "") == "scroll_bar":
			var scroll_control: Range = VSlider.new() if str(sprite.fields.get("scroll_axis", "horz")) == "vert" else HSlider.new()
			scroll_control.name = "NativeScroll"
			scroll_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			scroll_control.step = 1.0
			scroll_control.focus_mode = Control.FOCUS_ALL
			scroll_control.mouse_filter = Control.MOUSE_FILTER_STOP
			scroll_control.value_changed.connect(_on_native_scroll_changed.bind(sprite))
			wrapper.add_child(scroll_control)
		else:
			var texture_rect := TextureRect.new()
			texture_rect.name = "NativeTexture"
			texture_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
			texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			wrapper.add_child(texture_rect)
		var label := Label.new()
		label.name = "NativeText"
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", Color(1, 1, 1, 0.86))
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrapper.add_child(label)
		parent.add_child(wrapper)
		if filter_title_depth and sprite.fields.get("form_page_id") == "ID_PAGE_MENU":
			var gallery := Button.new()
			gallery.name = "NativeTitleGalleryEntry"
			gallery.text = "鉴赏与回想"
			gallery.position = Vector2(25, 126)
			gallery.size = Vector2(127, 24)
			gallery.pressed.connect(_start_native_appreciation_script)
			wrapper.add_child(gallery)
	elif wrapper.get_parent() != parent:
		wrapper.reparent(parent)
	wrapper.position = Vector2(sprite.position - sprite.rev_center)
	wrapper.pivot_offset = Vector2(sprite.rev_center)
	wrapper.scale = sprite.magnification
	var display_text := sprite.display_text()
	var fallback_size := Vector2(72, 22) if not display_text.is_empty() else Vector2.ZERO
	if sprite.is_button:
		fallback_size = Vector2(127, 24)
	elif sprite.fields.get("control_type", "") == "scroll_bar":
		var axis := str(sprite.fields.get("scroll_axis", "horz"))
		fallback_size = Vector2(160, 18) if axis == "horz" else Vector2(18, 160)
	var render_size := sprite.get_render_size()
	wrapper.size = Vector2(render_size) if render_size.x > 0 and render_size.y > 0 else fallback_size
	var current_effect_type := str(sprite.fields.get("effect_type", ""))
	var raster_width := int(sprite.fields.get("effect_shaking_width", 0)) if current_effect_type == "RasterScroll" else 0
	if raster_width > 0:
		wrapper.position.x -= raster_width
		wrapper.size.x += raster_width * 2
	if sprite.fields.get("control_type", "") == "scroll_bar" and sprite.size.x > 0:
		if sprite.size.y <= 0:
			wrapper.size.y = 18
	if parent == native_title_canvas and ((filter_title_depth and sprite.z_order < 52000)
			or (native_appreciation_mode and sprite.z_order >= 52000)):
		wrapper.visible = false
	else:
		wrapper.visible = sprite.is_visible
	wrapper.modulate.a = 1.0 - clampf(float(sprite.transparency) / 256.0, 0.0, 1.0)
	var native_button: TextureButton = wrapper.get_node_or_null("NativeButton")
	if native_button != null:
		if sprite.btn_state == "pushed" and sprite.btn_pushed_tex != null:
			native_button.texture_normal = sprite.btn_pushed_tex
		else:
			native_button.texture_normal = sprite.btn_normal_tex if sprite.btn_normal_tex != null else sprite.texture
		native_button.texture_hover = sprite.btn_focus_tex
		native_button.texture_pressed = sprite.btn_pushed_tex if sprite.btn_pushed_tex != null else sprite.btn_focus_tex
		native_button.texture_disabled = sprite.btn_disabled_tex
		native_button.disabled = sprite.btn_state == "disabled"
		native_button.mouse_filter = Control.MOUSE_FILTER_IGNORE if sprite.transparency >= 256 or native_button.disabled else Control.MOUSE_FILTER_STOP
		native_button.focus_mode = Control.FOCUS_NONE if sprite.transparency >= 256 or native_button.disabled else Control.FOCUS_ALL
	var native_texture: TextureRect = wrapper.get_node_or_null("NativeTexture")
	if native_texture != null:
		native_texture.texture = sprite.texture
		var is_mesh_warp := str(sprite.fields.get("effect_type", "")) == "MeshWarp" and sprite.texture != null
		native_texture.visible = sprite.texture != null and not is_mesh_warp
		var native_mesh: MeshInstance2D = wrapper.get_node_or_null("NativeMeshWarp")
		if is_mesh_warp:
			if native_mesh == null:
				native_mesh = MeshInstance2D.new()
				native_mesh.name = "NativeMeshWarp"
				wrapper.add_child(native_mesh)
			var mesh_state := [int(sprite.fields.get("effect_render_revision", 0)), sprite.blending, sprite.size, sprite.texture.get_instance_id()]
			if native_mesh.get_meta("mesh_state", []) != mesh_state:
				native_mesh.mesh = _build_native_mesh_warp(sprite)
				native_mesh.set_meta("mesh_state", mesh_state)
			native_mesh.texture = sprite.texture
			native_mesh.visible = native_mesh.mesh != null
			var warp_degree := clampf(float(sprite.blending) / 256.0, 0.0, 1.0)
			native_mesh.modulate.a = 1.0 - warp_degree * warp_degree if bool(sprite.fields.get("effect_transition", false)) else 1.0
		elif native_mesh != null:
			native_mesh.visible = false
		var effect_type := str(sprite.fields.get("effect_type", ""))
		var effect_mode: int = int({"TileImage": 1, "FilterWhite": 2, "FilterLight": 3, "FilterBlack": 4, "FilterDark": 5, "RasterScroll": 6, "WaveCircle": 7, "ShadingOff": 8, "ShadingLight": 9}.get(effect_type, 0))
		if effect_mode > 0 and sprite.texture != null:
			var effect_material: ShaderMaterial = native_texture.get_meta("native_effect_material") as ShaderMaterial if native_texture.has_meta("native_effect_material") else null
			if effect_material == null:
				var effect_shader := Shader.new()
				effect_shader.code = """
				shader_type canvas_item;
			uniform vec2 repeat_scale = vec2(1.0, 1.0);
			uniform vec2 scroll_uv = vec2(0.0, 0.0);
			uniform int effect_mode = 0;
			uniform int blend_degree = 0;
			uniform int raster_degree = 0;
			uniform float raster_shaking_width = 0.0;
			uniform float raster_mesh_size = 1.0;
			uniform float raster_frequency = 0.0;
			uniform bool raster_transition = false;
			uniform sampler2D shading_level_0;
			uniform sampler2D shading_level_1;
			uniform sampler2D shading_level_2;
			uniform sampler2D shading_level_3;
			uniform sampler2D shading_level_4;
			uniform bool shading_levels_ready = false;
			void fragment() {
				vec2 uv = UV;
				if (effect_mode == 1) uv = fract(UV * repeat_scale + scroll_uv);
				if (effect_mode == 6) {
					float degree = float(raster_degree);
					float amplitude = raster_shaking_width;
					if (degree < 256.0) amplitude *= degree / 256.0;
					float source_y = UV.y / TEXTURE_PIXEL_SIZE.y;
					float phase = 3.14159265 * raster_frequency * degree / 256.0;
					float wavelength = 3.14159265 / max(1.0, raster_mesh_size);
					float shift = round(amplitude * sin(source_y * wavelength + phase));
					float source_width = 1.0 / TEXTURE_PIXEL_SIZE.x;
					uv.x = UV.x * (1.0 + 2.0 * raster_shaking_width / source_width)
						- raster_shaking_width / source_width - shift / source_width;
				}
				if (effect_mode == 7) {
					vec2 source_size = 1.0 / TEXTURE_PIXEL_SIZE;
					vec2 grid_count = ceil(source_size / max(vec2(raster_mesh_size), vec2(1.0)));
					vec2 grid_pos = UV * grid_count;
					vec2 radial = grid_pos - grid_count * 0.5;
					float distance_to_center = length(radial);
					float wave_front = float(raster_degree) / 256.0 * raster_frequency;
					if (distance_to_center > 0.0 && distance_to_center <= wave_front) {
						float displacement = sin((wave_front - distance_to_center) * 0.78539816339) * raster_shaking_width;
						if (displacement < 0.0 && (UV.x <= 0.0 || UV.y <= 0.0 || UV.x >= 1.0 || UV.y >= 1.0)) displacement = 0.0;
						uv -= normalize(radial) * displacement / max(grid_count, vec2(1.0));
					}
				}
				vec4 sampled = texture(TEXTURE, uv);
				if ((effect_mode == 8 || effect_mode == 9) && shading_levels_ready) {
					int shade_degree = clamp(blend_degree, 0, 256);
					int shade_index = min(shade_degree >> 6, 3);
					float shade_mix = float(shade_degree & 63) / 63.0;
					if (shade_degree >= 256) shade_mix = 1.0;
					vec4 shade_a = texture(shading_level_0, UV);
					vec4 shade_b = texture(shading_level_1, UV);
					if (shade_index == 1) { shade_a = texture(shading_level_1, UV); shade_b = texture(shading_level_2, UV); }
					else if (shade_index == 2) { shade_a = texture(shading_level_2, UV); shade_b = texture(shading_level_3, UV); }
					else if (shade_index == 3) { shade_a = texture(shading_level_3, UV); shade_b = texture(shading_level_4, UV); }
					sampled = mix(shade_a, shade_b, shade_mix);
					if (effect_mode == 9) sampled.rgb = mix(sampled.rgb, vec3(1.0), pow(float(shade_degree) / 256.0, 2.0));
					if (raster_transition) sampled.a *= 1.0 - pow(float(shade_degree) / 256.0, 2.0);
				}
				if ((effect_mode == 6 || effect_mode == 7) && raster_transition) {
					float transition_alpha = clamp(float(raster_degree) / 256.0, 0.0, 1.0);
					sampled.a *= 1.0 - transition_alpha * transition_alpha;
				}
				vec3 channels = floor(sampled.rgb * 255.0 + vec3(0.5));
				int degree = clamp(blend_degree, 0, 256);
				if (effect_mode == 2 && degree > 0) {
					channels = vec3(float(degree - 1)) + floor(channels * float(256 - degree) / 256.0);
				} else if (effect_mode == 3) {
					channels = min(channels + vec3(float(degree)), vec3(255.0));
				} else if (effect_mode == 4) {
					channels = floor(channels * float(256 - degree) / 256.0);
				} else if (effect_mode == 5) {
					channels = max(channels - vec3(float(degree)), vec3(0.0));
				}
				COLOR = vec4(clamp(channels / 255.0, vec3(0.0), vec3(1.0)), sampled.a) * COLOR;
			}
				"""
				effect_material = ShaderMaterial.new()
				effect_material.shader = effect_shader
				native_texture.set_meta("native_effect_material", effect_material)
			var source_size := Vector2(sprite.texture.get_size())
			var effect_size := Vector2(sprite.get_render_size())
			var tile_scroll: Vector2i = sprite.fields.get("effect_scroll", Vector2i.ZERO)
			effect_material.set_shader_parameter("repeat_scale", effect_size / source_size if effect_mode == 1 else Vector2.ONE)
			effect_material.set_shader_parameter("scroll_uv", Vector2(tile_scroll) / source_size if effect_mode == 1 else Vector2.ZERO)
			effect_material.set_shader_parameter("effect_mode", effect_mode)
			effect_material.set_shader_parameter("blend_degree", clampi(sprite.blending, 0, 256))
			effect_material.set_shader_parameter("raster_degree", sprite.blending)
			effect_material.set_shader_parameter("raster_shaking_width", float(sprite.fields.get("effect_shaking_width", 0)))
			effect_material.set_shader_parameter("raster_mesh_size", float(sprite.fields.get("effect_mesh_size", 1)))
			effect_material.set_shader_parameter("raster_frequency", float(sprite.fields.get("effect_frequency", 0)))
			effect_material.set_shader_parameter("raster_transition", bool(sprite.fields.get("effect_transition", false)))
			if effect_mode == 8 or effect_mode == 9:
				var shade_cache_key := [sprite.texture.get_instance_id()]
				var shade_textures: Array = native_texture.get_meta("native_shading_levels", [])
				if native_texture.get_meta("native_shading_key", []) != shade_cache_key:
					shade_textures.clear()
					var codec: Object = ClassDB.instantiate("YzkCodec")
					var source_image := sprite.texture.get_image()
					if codec != null and codec.has_method("build_shading_levels") and source_image != null and not source_image.is_empty() and source_image.get_width() * source_image.get_height() <= 8388608:
						source_image.convert(Image.FORMAT_RGBA8)
						var level_data: Array = codec.call("build_shading_levels", source_image.get_data(), source_image.get_width(), source_image.get_height())
						for bytes: PackedByteArray in level_data:
							var level_image := Image.create_from_data(source_image.get_width(), source_image.get_height(), false, Image.FORMAT_RGBA8, bytes)
							shade_textures.append(ImageTexture.create_from_image(level_image))
					if shade_textures.size() == 5:
						native_texture.set_meta("native_shading_levels", shade_textures)
						native_texture.set_meta("native_shading_key", shade_cache_key)
					else:
						native_texture.set_meta("native_shading_key", shade_cache_key)
						native_texture.set_meta("native_shading_levels", [])
						push_warning("YzkCodec unavailable or invalid image for native Shading effect")
				if shade_textures.size() == 5:
					effect_material.set_shader_parameter("shading_levels_ready", true)
					effect_material.set_shader_parameter("shading_level_0", shade_textures[0])
					effect_material.set_shader_parameter("shading_level_1", shade_textures[1])
					effect_material.set_shader_parameter("shading_level_2", shade_textures[2])
					effect_material.set_shader_parameter("shading_level_3", shade_textures[3])
					effect_material.set_shader_parameter("shading_level_4", shade_textures[4])
				else:
					effect_material.set_shader_parameter("shading_levels_ready", false)
			native_texture.material = effect_material
		else:
			native_texture.material = null
	var native_scroll: Range = wrapper.get_node_or_null("NativeScroll")
	if native_scroll != null:
		var axis := str(sprite.fields.get("scroll_axis", "horz"))
		var item_id := str(sprite.fields.get("form_item_id", ""))
		var range_key := "scroll_%s_range" % axis
		var pos_key := "scroll_%s_pos" % axis
		native_scroll.min_value = 0.0
		native_scroll.max_value = float(maxi(0, int(sprite.fields.get(range_key, 256))))
		native_scroll.value = float(clampi(int(sprite.fields.get(pos_key, 0)), 0, int(native_scroll.max_value)))
		native_scroll.editable = sprite.is_visible and sprite.transparency < 256
		for state_name in ["normal", "focus", "tracking", "disabled"]:
			var bar_texture := sprite.fields.get("scroll_%s_bar" % state_name) as Texture2D
			if bar_texture != null:
				var icon_name := "grabber" if state_name == "normal" else "grabber_highlight" if state_name == "focus" else "grabber_pressed" if state_name == "tracking" else "grabber_disabled"
				native_scroll.add_theme_icon_override(icon_name, bar_texture)
		var column_texture := sprite.fields.get("scroll_normal_column") as Texture2D
		if column_texture != null and (not native_scroll.has_meta("native_scroll_track") or native_scroll.get_meta("native_scroll_track") != column_texture):
			var track := StyleBoxTexture.new()
			track.texture = column_texture
			track.texture_margin_left = 2.0
			track.texture_margin_right = 2.0
			track.texture_margin_top = 2.0
			track.texture_margin_bottom = 2.0
			native_scroll.add_theme_stylebox_override("slider", track)
			native_scroll.set_meta("native_scroll_track", column_texture)
	var native_label: Label = wrapper.get_node_or_null("NativeText")
	if native_label != null:
		native_label.text = display_text
		native_label.visible = not display_text.is_empty()
		if not sprite.message_style.is_empty() and native_label.get_meta("message_style", {}) != sprite.message_style:
			_apply_native_text_style(native_label, sprite.message_style)
			native_label.set_meta("message_style", sprite.message_style)
	if not sprite.children.is_empty():
		_sync_native_sprite_children(sprite.children, wrapper, seen, filter_title_depth)


func _build_native_mesh_warp(sprite: CsxHostClass.HostSprite) -> ArrayMesh:
	var frames: Array = sprite.fields.get("effect_mesh_frames", [])
	var base: PackedVector2Array = sprite.fields.get("effect_mesh_base", PackedVector2Array())
	var cells_x := int(sprite.fields.get("effect_mesh_width", 0))
	var cells_y := int(sprite.fields.get("effect_mesh_height", 0))
	if frames.is_empty() or base.is_empty() or cells_x <= 0 or cells_y <= 0:
		return null
	var frame_index := 0
	var frame_blend := 0.0
	if frames.size() > 1:
		var interval := 256 / (frames.size() - 1)
		frame_index = mini(frames.size() - 1, sprite.blending * (frames.size() - 1) / 256)
		if frame_index < frames.size() - 1:
			frame_blend = clampf(float(sprite.blending - frame_index * interval) / maxf(1.0, float(interval)), 0.0, 1.0)
	var current_frame: PackedVector2Array = frames[frame_index]
	var next_frame: PackedVector2Array = frames[mini(frame_index + 1, frames.size() - 1)]
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	vertices.resize(base.size())
	uvs.resize(base.size())
	var texture_size := Vector2(sprite.texture.get_size())
	for i in range(base.size()):
		var point := current_frame[i].lerp(next_frame[i], frame_blend)
		vertices[i] = Vector3(point.x, point.y, 0.0)
		uvs[i] = Vector2(base[i].x / maxf(1.0, texture_size.x), base[i].y / maxf(1.0, texture_size.y))
	var indices := PackedInt32Array()
	indices.resize(cells_x * cells_y * 6)
	var write_index := 0
	var row_width := cells_x + 1
	for row in range(1, cells_y + 1):
		for column in range(1, cells_x + 1):
			var top_left := (row - 1) * row_width + column - 1
			var top_right := top_left + 1
			var bottom_left := row * row_width + column - 1
			var bottom_right := bottom_left + 1
			indices[write_index] = top_left
			indices[write_index + 1] = top_right
			indices[write_index + 2] = bottom_left
			indices[write_index + 3] = bottom_right
			indices[write_index + 4] = top_right
			indices[write_index + 5] = bottom_left
			write_index += 6
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _on_native_scroll_changed(value: float, sprite: CsxHostClass.HostSprite) -> void:
	var axis := str(sprite.fields.get("scroll_axis", "horz"))
	sprite.fields["scroll_%s_pos" % axis] = int(round(value))


func _apply_native_text_style(label: Control, style: Dictionary) -> void:
	var font: Dictionary = style.get("font", {})
	var arrange: Dictionary = style.get("arrange", {})
	var text: Dictionary = style.get("text", {})
	var shadow: Dictionary = style.get("shadow", {})
	var rich := label is RichTextLabel
	var font_key := "normal_font" if rich else "font"
	var font_size_key := "normal_font_size" if rich else "font_size"
	var color_key := "default_color" if rich else "font_color"
	var spacing_key := "line_separation" if rich else "line_spacing"
	var face := str(font.get("face", ""))
	if not face.is_empty():
		var system_font := SystemFont.new()
		system_font.font_names = PackedStringArray([face])
		system_font.font_weight = 700 if font.get("bold") == "true" else 400
		system_font.font_italic = font.get("italic") == "true"
		label.add_theme_font_override(font_key, system_font)
	var font_size := maxi(1, int(font.get("size", 13)))
	label.add_theme_font_size_override(font_size_key, font_size)
	label.add_theme_color_override(color_key, _native_text_color(text))
	label.add_theme_color_override("font_shadow_color", _native_text_color(shadow) if not shadow.is_empty() else Color.TRANSPARENT)
	label.add_theme_constant_override("shadow_offset_x", int(shadow.get("x", 0)))
	label.add_theme_constant_override("shadow_offset_y", int(shadow.get("y", 0)))
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	match arrange.get("align", "left"):
		"center": label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		"right": label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_: label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	if arrange.has("line_height"):
		var metrics := label.get_theme_font(font_key).get_height(font_size)
		label.add_theme_constant_override(spacing_key, int(arrange["line_height"]) - roundi(metrics))


func _native_text_color(attributes: Dictionary) -> Color:
	var value := str(attributes.get("color", "00FFFFFFH")).to_upper().trim_suffix("H")
	var color := Color.hex(((value.hex_to_int() & 0xffffff) << 8) | 0xff)
	color.a = 1.0 - clampf(float(attributes.get("transparency", 0)) / 256.0, 0.0, 1.0)
	return color


func _on_native_title_button_pressed(sprite: CsxHostClass.HostSprite) -> void:
	if is_config_open or is_save_load_open or is_appreciation_open or confirm_panel.visible:
		return
	if native_appreciation_mode and sprite.btn_id == "ID_CLOSE":
		_close_native_appreciation()
		return
	if is_title_mode and not native_appreciation_mode:
		match sprite.btn_id:
			"ID_CONFIG":
				_open_config_modal()
				return
			"ID_APPRECIATION", "ID_APPLICIATION":
				_start_native_appreciation_script()
				return
			"ID_CONTINUE":
				_open_save_load_modal()
				return
			"ID_EXITGAME":
				get_tree().quit(0)
				return
	if host != null and not sprite.btn_id.is_empty():
		# Native radio/check buttons retain their selected state so the CSX
		# IsButtonChecked() branches and pushed artwork stay in sync.
		if not sprite.full_btn_id.is_empty() or sprite.btn_id in ["ID_REC", "ID_PAGE1", "ID_PAGE2", "ID_TAG"]:
			sprite.set_button_state("pushed")
		host.push_command(sprite.btn_id, sprite.full_btn_id)


func _apply_dialogue_skin() -> void:
	if host == null or dialogue_box == null:
		return
	var res_mgr := CsxHostClass.HostResourceManager.new(host)
	if res_mgr.load_resource("frame.noa") != 1:
		return

	# 1. Dialogue box background (FRM_0101.eri: 750x152)
	var dlg_bg: TextureRect = dialogue_box.find_child("DialogueBackground", true, false)
	var frame_res := host.load_image("FRM_0101.eri", res_mgr.loaded_archive_name)
	if frame_res.get("ok", false) and frame_res.get("texture") != null:
		if dlg_bg != null:
			dlg_bg.texture = frame_res["texture"]
		else:
			var style_tex := StyleBoxTexture.new()
			style_tex.texture = frame_res["texture"]
			dialogue_box.add_theme_stylebox_override("panel", style_tex)

	# 2. Voice button skin (ID_PAGE_ADV_VOICE -> ID_BTN_ADV_VOICE -> FRM_0105.eri)
	var v_page := CsxHostClass.HostSprite.new(0, host)
	if res_mgr.create_form_page(v_page, "ID_PAGE_ADV_VOICE") == 1 and not v_page.children.is_empty():
		var child = v_page.children[0]
		if voice_button is TextureButton:
			var tb := voice_button as TextureButton
			tb.texture_normal = child.btn_normal_tex
			tb.texture_hover = child.btn_focus_tex
			tb.texture_pressed = child.btn_pushed_tex if child.btn_pushed_tex else child.btn_focus_tex

	# 3. Close dialogue frame button (ID_PAGE_ADV_CLOSE -> ID_BTN_ADV_CLOSE -> FRM_0119.eri)
	var c_page := CsxHostClass.HostSprite.new(0, host)
	if res_mgr.create_form_page(c_page, "ID_PAGE_ADV_CLOSE") == 1 and not c_page.children.is_empty():
		var child = c_page.children[0]
		if close_button is TextureButton:
			var tb := close_button as TextureButton
			tb.texture_normal = child.btn_normal_tex
			tb.texture_hover = child.btn_focus_tex
			tb.texture_pressed = child.btn_pushed_tex if child.btn_pushed_tex else child.btn_focus_tex

	# 4. In-game menu buttons (ID_PAGE_ADV_MENU -> 8 buttons)
	var m_page := CsxHostClass.HostSprite.new(0, host)
	if res_mgr.create_form_page(m_page, "ID_PAGE_ADV_MENU") == 1:
		var btn_map := {
			"ID_QSAVE": qsave_button,
			"ID_QLOAD": qload_button,
			"ID_SAVE": save_button,
			"ID_LOAD": load_button,
			"ID_CONFIG": config_button,
			"ID_AUTO": auto_button,
			"ID_SKIP": skip_button,
			"ID_HISTORY": history_button,
		}
		for child in m_page.children:
			var btn: BaseButton = btn_map.get(child.btn_id, null)
			if btn is TextureButton:
				var tb := btn as TextureButton
				tb.texture_normal = child.btn_normal_tex
				tb.texture_hover = child.btn_focus_tex
				tb.texture_pressed = child.btn_pushed_tex if child.btn_pushed_tex else child.btn_focus_tex
				tb.texture_disabled = child.btn_disabled_tex


func _apply_backlog_skin() -> void:
	if host == null or backlog_panel == null:
		return
	var win_box: Control = backlog_panel.find_child("BacklogWindowBox", true, false)
	if win_box == null:
		return
	var bg_rect: TextureRect = win_box.find_child("BacklogBg", true, false)
	var bg_res := host.load_image("FRM_0301.eri", "frame.noa")
	if bg_res.get("ok", false) and bg_res.get("texture") != null and bg_rect != null:
		bg_rect.texture = bg_res["texture"]


func _build_config_ui() -> void:
	config_panel = PanelContainer.new()
	config_panel.name = "ConfigModal"
	# Draw above the native title sprites, including the frontmost depth.
	config_panel.z_index = 4096
	config_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	config_panel.visible = false
	config_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var backdrop_style := StyleBoxFlat.new()
	backdrop_style.bg_color = Color(0.02, 0.03, 0.05, 0.82)
	config_panel.add_theme_stylebox_override("panel", backdrop_style)
	add_child(config_panel)

	var center_root := Control.new()
	center_root.name = "ConfigCenterRoot"
	center_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	config_panel.add_child(center_root)

	var win_box := Control.new()
	win_box.name = "ConfigWindowBox"
	win_box.anchor_left = 0.5
	win_box.anchor_right = 0.5
	win_box.anchor_top = 0.5
	win_box.anchor_bottom = 0.5
	win_box.offset_left = -266.0
	win_box.offset_right = 266.0
	win_box.offset_top = -276.0
	win_box.offset_bottom = 276.0
	win_box.custom_minimum_size = Vector2(532, 552)
	win_box.size = Vector2(532, 552)
	center_root.add_child(win_box)

	var bg_rect := TextureRect.new()
	bg_rect.name = "ConfigBg"
	bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win_box.add_child(bg_rect)

	# Screen mode buttons
	cfg_btn_window = TextureButton.new()
	cfg_btn_window.name = "ID_WINDOW"
	cfg_btn_window.position = Vector2(216, 25)
	cfg_btn_window.size = Vector2(106, 23)
	cfg_btn_window.pressed.connect(func(): DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED))
	win_box.add_child(cfg_btn_window)

	cfg_btn_fullscreen = TextureButton.new()
	cfg_btn_fullscreen.name = "ID_FULLSCREEN"
	cfg_btn_fullscreen.position = Vector2(382, 26)
	cfg_btn_fullscreen.size = Vector2(106, 23)
	cfg_btn_fullscreen.pressed.connect(func(): DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN))
	win_box.add_child(cfg_btn_fullscreen)

	# Sound mute toggles
	cfg_check_bgm = TextureButton.new()
	cfg_check_bgm.name = "ID_CHECK_BGM"
	cfg_check_bgm.position = Vector2(191, 76)
	cfg_check_bgm.size = Vector2(37, 27)
	cfg_check_bgm.pressed.connect(_toggle_bgm_mute)
	win_box.add_child(cfg_check_bgm)

	cfg_check_se = TextureButton.new()
	cfg_check_se.name = "ID_CHECK_SE"
	cfg_check_se.position = Vector2(191, 103)
	cfg_check_se.size = Vector2(37, 27)
	cfg_check_se.pressed.connect(_toggle_se_mute)
	win_box.add_child(cfg_check_se)

	cfg_check_system = TextureButton.new()
	cfg_check_system.name = "ID_CHECK_SYSTEM"
	cfg_check_system.position = Vector2(191, 130)
	cfg_check_system.size = Vector2(37, 27)
	cfg_check_system.pressed.connect(_toggle_system_mute)
	win_box.add_child(cfg_check_system)

	cfg_check_voice = TextureButton.new()
	cfg_check_voice.name = "ID_CHECK_VOICE"
	cfg_check_voice.position = Vector2(191, 157)
	cfg_check_voice.size = Vector2(37, 27)
	cfg_check_voice.pressed.connect(_toggle_voice_mute)
	win_box.add_child(cfg_check_voice)

	# Volume sliders
	cfg_slider_bgm = HSlider.new()
	cfg_slider_bgm.name = "ID_VOL_BGM"
	cfg_slider_bgm.position = Vector2(256, 83)
	cfg_slider_bgm.size = Vector2(218, 16)
	cfg_slider_bgm.min_value = 0.0
	cfg_slider_bgm.max_value = 1.0
	cfg_slider_bgm.step = 0.02
	cfg_slider_bgm.value = settings_state.audio_volume("bgm")
	cfg_slider_bgm.value_changed.connect(_on_cfg_bgm_vol_changed)
	win_box.add_child(cfg_slider_bgm)

	cfg_slider_se = HSlider.new()
	cfg_slider_se.name = "ID_VOL_SE"
	cfg_slider_se.position = Vector2(256, 110)
	cfg_slider_se.size = Vector2(218, 16)
	cfg_slider_se.min_value = 0.0
	cfg_slider_se.max_value = 1.0
	cfg_slider_se.step = 0.02
	cfg_slider_se.value = settings_state.audio_volume("se")
	cfg_slider_se.value_changed.connect(_on_cfg_se_vol_changed)
	win_box.add_child(cfg_slider_se)

	cfg_slider_system = HSlider.new()
	cfg_slider_system.name = "ID_VOL_SYSTEM"
	cfg_slider_system.position = Vector2(256, 137)
	cfg_slider_system.size = Vector2(218, 16)
	cfg_slider_system.min_value = 0.0
	cfg_slider_system.max_value = 1.0
	cfg_slider_system.step = 0.02
	cfg_slider_system.value = settings_state.audio_volume("system")
	cfg_slider_system.value_changed.connect(_on_cfg_system_vol_changed)
	win_box.add_child(cfg_slider_system)

	cfg_slider_voice = HSlider.new()
	cfg_slider_voice.name = "ID_VOL_VOICE"
	cfg_slider_voice.position = Vector2(256, 164)
	cfg_slider_voice.size = Vector2(218, 16)
	cfg_slider_voice.min_value = 0.0
	cfg_slider_voice.max_value = 1.0
	cfg_slider_voice.step = 0.02
	cfg_slider_voice.value = settings_state.audio_volume("voice")
	cfg_slider_voice.value_changed.connect(_on_cfg_voice_vol_changed)
	win_box.add_child(cfg_slider_voice)

	cfg_btn_voice_details = TextureButton.new()
	cfg_btn_voice_details.name = "ID_VOICE_DETAILS"
	cfg_btn_voice_details.position = Vector2(374, 179)
	cfg_btn_voice_details.size = Vector2(129, 26)
	cfg_btn_voice_details.pressed.connect(_open_voice_details_modal)
	win_box.add_child(cfg_btn_voice_details)

	cfg_slider_speed = HSlider.new()
	cfg_slider_speed.name = "ID_MESSAGE_SPEED"
	cfg_slider_speed.position = Vector2(250, 312)
	cfg_slider_speed.size = Vector2(218, 16)
	cfg_slider_speed.min_value = 500.0
	cfg_slider_speed.max_value = 10000.0
	cfg_slider_speed.step = 250.0
	cfg_slider_speed.value = float(settings_state.message_speed())
	cfg_slider_speed.value_changed.connect(_on_cfg_message_speed_changed)
	win_box.add_child(cfg_slider_speed)

	cfg_slider_auto_speed = HSlider.new()
	cfg_slider_auto_speed.name = "ID_AUTOMODE_SPEED"
	cfg_slider_auto_speed.position = Vector2(250, 467)
	cfg_slider_auto_speed.size = Vector2(218, 16)
	cfg_slider_auto_speed.min_value = 1.0
	cfg_slider_auto_speed.max_value = 5.0
	cfg_slider_auto_speed.step = 0.2
	cfg_slider_auto_speed.value = settings_state.auto_delay_seconds()
	cfg_slider_auto_speed.value_changed.connect(_on_cfg_auto_delay_changed)
	win_box.add_child(cfg_slider_auto_speed)

	# Bottom action buttons
	var btn_default := TextureButton.new()
	btn_default.name = "ID_DEFAULT"
	btn_default.position = Vector2(30, 512)
	btn_default.size = Vector2(129, 26)
	btn_default.pressed.connect(_on_config_default_pressed)
	win_box.add_child(btn_default)

	var btn_title := TextureButton.new()
	btn_title.name = "ID_TITLE"
	btn_title.position = Vector2(245, 511)
	btn_title.size = Vector2(129, 26)
	btn_title.pressed.connect(func():
		_close_config_modal()
		if not is_title_mode:
			_on_home_button_pressed()
	)
	win_box.add_child(btn_title)

	var btn_end := TextureButton.new()
	btn_end.name = "ID_END"
	btn_end.position = Vector2(374, 511)
	btn_end.size = Vector2(129, 26)
	btn_end.pressed.connect(func():
		_close_config_modal()
		if is_title_mode:
			get_tree().quit(0)
	)
	win_box.add_child(btn_end)


func _apply_config_skin() -> void:
	if host == null or config_panel == null:
		return
	var res_mgr := CsxHostClass.HostResourceManager.new(host)
	if res_mgr.load_resource("frame.noa") != 1:
		return

	var win_box: Control = config_panel.find_child("ConfigWindowBox", true, false)
	if win_box == null:
		return

	# Background FRM_0201.eri
	var bg_rect: TextureRect = win_box.find_child("ConfigBg", true, false)
	var bg_res := host.load_image("FRM_0201.eri", res_mgr.loaded_archive_name)
	if bg_res.get("ok", false) and bg_res.get("texture") != null and bg_rect != null:
		bg_rect.texture = bg_res["texture"]

	# Slider style overrides
	var track_info := res_mgr._resolve_skin_image("ID_FRM_0221")
	var knob_info := res_mgr._resolve_skin_image("ID_FRM_0222:RECT(0,0,13,13)")
	var knob_focus := res_mgr._resolve_skin_image("ID_FRM_0222:RECT(13,0,13,13)")

	var sliders: Array[HSlider] = [
		cfg_slider_bgm, cfg_slider_se, cfg_slider_system,
		cfg_slider_voice, cfg_slider_speed, cfg_slider_auto_speed
	]
	for sl in sliders:
		if sl == null:
			continue
		if knob_info.has("texture"):
			sl.add_theme_icon_override("grabber", knob_info["texture"])
		if knob_focus.has("texture"):
			sl.add_theme_icon_override("grabber_highlight", knob_focus["texture"])
		if track_info.has("texture"):
			var style_track := StyleBoxTexture.new()
			style_track.texture = track_info["texture"]
			sl.add_theme_stylebox_override("slider", style_track)

	# Skin buttons defined in ID_PAGE_CONFIG
	var page_cfg: Dictionary = res_mgr.skin_pages.get("ID_PAGE_CONFIG", {})
	for btn_def in page_cfg.get("buttons", []):
		var bid: String = btn_def.get("id", "")
		var target_btn: Control = win_box.find_child(bid, true, false)
		if target_btn is TextureButton:
			var tb := target_btn as TextureButton
			var st_id: String = btn_def.get("style", "")
			var st: Dictionary = res_mgr.skin_styles.get(st_id, {})
			var normal_info := res_mgr._resolve_skin_image(st.get("normal", ""))
			var focus_info := res_mgr._resolve_skin_image(st.get("focus", ""))
			var pushed_info := res_mgr._resolve_skin_image(st.get("pushed", ""))
			if normal_info.has("texture"):
				tb.texture_normal = normal_info["texture"]
			if focus_info.has("texture"):
				tb.texture_hover = focus_info["texture"]
			if pushed_info.has("texture"):
				tb.texture_pressed = pushed_info["texture"]
			elif focus_info.has("texture"):
				tb.texture_pressed = focus_info["texture"]


func _on_cfg_bgm_vol_changed(val: float) -> void:
	settings_state.set_audio_volume("bgm", val)
	_apply_audio_channel("BGM", bgm_player)


func _on_cfg_se_vol_changed(val: float) -> void:
	settings_state.set_audio_volume("se", val)
	_apply_audio_channel("SE", se_player)


func _on_cfg_system_vol_changed(val: float) -> void:
	settings_state.set_audio_volume("system", val)
	_apply_audio_channel("SYSTEM", system_player)


func _on_cfg_voice_vol_changed(val: float) -> void:
	settings_state.set_audio_volume("voice", val)
	_apply_audio_channel("VOICE", voice_player)


func _on_cfg_message_speed_changed(val: float) -> void:
	settings_state.set_message_speed(int(val))
	steps_per_frame = settings_state.message_speed()


func _on_cfg_auto_delay_changed(val: float) -> void:
	settings_state.set_auto_delay_seconds(val)
	auto_timer = 0.0


func _apply_audio_channel(channel: String, fallback_player: AudioStreamPlayer) -> void:
	var volume := settings_state.audio_volume(channel)
	var muted := settings_state.is_muted(channel)
	var handled_by_host := false
	if host != null and host.has_method("set_audio_total_volume"):
		var effective_volume := 0.0 if muted else volume
		var play_type := int({"BGM": CsxHostClass.AUDIO_PLAY_TYPE_MUSIC, "SE": CsxHostClass.AUDIO_PLAY_TYPE_SOUND, "VOICE": CsxHostClass.AUDIO_PLAY_TYPE_VOICE, "SYSTEM": CsxHostClass.AUDIO_PLAY_TYPE_SYSTEM}.get(channel.to_upper(), CsxHostClass.AUDIO_PLAY_TYPE_NONE))
		handled_by_host = bool(host.call("set_audio_total_volume", play_type, effective_volume))
	if handled_by_host:
		return
	var volume_db := -80.0 if (muted or volume <= 0.01) else linear_to_db(volume)
	if fallback_player != null:
		fallback_player.volume_db = volume_db
	if channel == "SE" and env_se_player != null:
		env_se_player.volume_db = volume_db


func _apply_config_state() -> void:
	steps_per_frame = settings_state.message_speed()
	if cfg_slider_bgm != null:
		cfg_slider_bgm.set_value_no_signal(settings_state.audio_volume("bgm"))
	if cfg_slider_se != null:
		cfg_slider_se.set_value_no_signal(settings_state.audio_volume("se"))
	if cfg_slider_system != null:
		cfg_slider_system.set_value_no_signal(settings_state.audio_volume("system"))
	if cfg_slider_voice != null:
		cfg_slider_voice.set_value_no_signal(settings_state.audio_volume("voice"))
	if cfg_slider_speed != null:
		cfg_slider_speed.set_value_no_signal(float(settings_state.message_speed()))
	if cfg_slider_auto_speed != null:
		cfg_slider_auto_speed.set_value_no_signal(settings_state.auto_delay_seconds())
	_apply_audio_channel("BGM", bgm_player)
	_apply_audio_channel("SE", se_player)
	_apply_audio_channel("SYSTEM", system_player)
	_apply_audio_channel("VOICE", voice_player)
	_refresh_mute_indicators()


func _refresh_mute_indicators() -> void:
	if cfg_check_bgm != null:
		cfg_check_bgm.modulate = Color(0.5, 0.5, 0.5, 1.0) if settings_state.is_muted("bgm") else Color.WHITE
	if cfg_check_se != null:
		cfg_check_se.modulate = Color(0.5, 0.5, 0.5, 1.0) if settings_state.is_muted("se") else Color.WHITE
	if cfg_check_system != null:
		cfg_check_system.modulate = Color(0.5, 0.5, 0.5, 1.0) if settings_state.is_muted("system") else Color.WHITE
	if cfg_check_voice != null:
		cfg_check_voice.modulate = Color(0.5, 0.5, 0.5, 1.0) if settings_state.is_muted("voice") else Color.WHITE


func _toggle_bgm_mute() -> void:
	settings_state.set_muted("bgm", not settings_state.is_muted("bgm"))
	_apply_audio_channel("BGM", bgm_player)
	_refresh_mute_indicators()


func _toggle_se_mute() -> void:
	settings_state.set_muted("se", not settings_state.is_muted("se"))
	_apply_audio_channel("SE", se_player)
	_refresh_mute_indicators()


func _toggle_system_mute() -> void:
	settings_state.set_muted("system", not settings_state.is_muted("system"))
	_apply_audio_channel("SYSTEM", system_player)
	_refresh_mute_indicators()


func _toggle_voice_mute() -> void:
	settings_state.set_muted("voice", not settings_state.is_muted("voice"))
	_apply_audio_channel("VOICE", voice_player)
	_refresh_mute_indicators()


func _on_config_default_pressed() -> void:
	settings_state.reset_defaults()
	_apply_config_state()


func _restore_player_settings() -> void:
	var snapshot := host.read_save_snapshot(host.get_save_path("player-settings.json"), true, true)
	var values: Dictionary = snapshot.get("payload", {})
	settings_state.restore(values)
	var character_mutes: Variant = values.get("voice_char_mutes")
	if character_mutes is Dictionary:
		for char_id in voice_char_buttons:
			var muted: Variant = character_mutes.get(char_id)
			if muted is bool:
				voice_char_mutes[char_id] = muted
				host.voice_char_mutes[char_id] = muted


func _persist_player_settings() -> void:
	if host == null:
		return
	var values := settings_state.to_dictionary()
	values["voice_char_mutes"] = voice_char_mutes
	host.write_save_atomically(host.get_save_path("player-settings.json"), JSON.stringify(values))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_config_open:
		_persist_player_settings()


func _open_config_modal() -> void:
	if config_panel == null:
		return
	is_config_open = true
	config_panel.visible = true
	print("[AdvPlayer] Opened native Config Window.")


func _close_config_modal() -> void:
	if config_panel == null:
		return
	_persist_player_settings()
	is_config_open = false
	config_panel.visible = false
	print("[AdvPlayer] Closed native Config Window.")


func _exit_title_to_game() -> void:
	is_title_mode = false
	title_panel.visible = false
	if native_title_layer != null:
		native_title_layer.visible = false
	print("[AdvPlayer] Exited Title Screen.")


func _on_title_start_game() -> void:
	_exit_title_to_game()
	if vm != null and vm.functions.has("ScenarioLoop"):
		vm.ip = vm.functions["ScenarioLoop"]
		vm.is_halted = false
		vm.pending_call_args = [start_scenario]
		vm.pending_return_ip = -1
		vm.call_stack.clear()
		vm.eval_stack.clear()
		is_running = true
		print("[AdvPlayer] Started new game with scenario '%s'." % start_scenario)


func _on_home_button_pressed() -> void:
	if is_recollect_mode:
		_show_confirm_dialog("确定要退出场景回想吗？", _end_scene_recollection)
	else:
		_show_confirm_dialog("确定要返回标题画面吗？未保存的进度将会丢失。", _show_title_screen)


# ==============================================================================
# Voice Volume Details Sub-Window (ID_PAGE_VOICE_DETAILS)
# ==============================================================================

func _build_voice_details_ui() -> void:
	voice_details_panel = PanelContainer.new()
	voice_details_panel.name = "VoiceDetailsPanel"
	voice_details_panel.z_index = config_panel.z_index
	voice_details_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	voice_details_panel.visible = false
	voice_details_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var overlay_style := StyleBoxFlat.new()
	overlay_style.bg_color = Color(0, 0, 0, 0.45)
	voice_details_panel.add_theme_stylebox_override("panel", overlay_style)
	add_child(voice_details_panel)

	# Container box 335 x 179 centered
	var win_box := Control.new()
	win_box.name = "VoiceDetailsBox"
	win_box.anchor_left = 0.5
	win_box.anchor_right = 0.5
	win_box.anchor_top = 0.5
	win_box.anchor_bottom = 0.5
	win_box.offset_left = -167.0
	win_box.offset_right = 168.0
	win_box.offset_top = -89.0
	win_box.offset_bottom = 90.0
	voice_details_panel.add_child(win_box)

	var bg_rect := TextureRect.new()
	bg_rect.name = "VoiceDetailsBg"
	bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	win_box.add_child(bg_rect)

	# Close button at top right
	var close_btn := TextureButton.new()
	close_btn.name = "ID_CLOSE"
	close_btn.position = Vector2(310, 4)
	close_btn.size = Vector2(16, 17)
	close_btn.pressed.connect(_close_voice_details_modal)
	win_box.add_child(close_btn)

	var char_defs := [
		{"id": "ID_SORA", "pos": Vector2(128, 13)},
		{"id": "ID_AKIRA", "pos": Vector2(290, 13)},
		{"id": "ID_NAO", "pos": Vector2(128, 43)},
		{"id": "ID_KAZUHA", "pos": Vector2(290, 43)},
		{"id": "ID_MOTOKA", "pos": Vector2(128, 73)},
		{"id": "ID_KOZUE", "pos": Vector2(290, 73)},
		{"id": "ID_YAHIRO", "pos": Vector2(128, 103)},
		{"id": "ID_RYOUHEI", "pos": Vector2(290, 103)},
		{"id": "ID_OTHER", "pos": Vector2(128, 133)},
	]
	voice_char_buttons.clear()
	for cd in char_defs:
		var btn := TextureButton.new()
		btn.name = cd["id"]
		btn.position = cd["pos"]
		btn.size = Vector2(37, 27)
		btn.pressed.connect(_toggle_character_voice.bind(cd["id"]))
		win_box.add_child(btn)
		voice_char_buttons[cd["id"]] = btn


func _apply_voice_details_skin() -> void:
	if host == null or voice_details_panel == null:
		return
	var res_mgr := CsxHostClass.HostResourceManager.new(host)
	if res_mgr.load_resource("frame.noa") != 1:
		return

	var win_box: Control = voice_details_panel.find_child("VoiceDetailsBox", true, false)
	if win_box == null:
		return

	var bg_rect: TextureRect = win_box.find_child("VoiceDetailsBg", true, false)
	var bg_res := host.load_image("FRM_0231.eri", res_mgr.loaded_archive_name)
	if bg_res.get("ok", false) and bg_res.get("texture") != null and bg_rect != null:
		bg_rect.texture = bg_res["texture"]

	var close_btn: TextureButton = win_box.find_child("ID_CLOSE", true, false)
	if close_btn != null:
		var st_close: Dictionary = res_mgr.skin_styles.get("ID_BTN_ADV_CLOSE", {})
		var n_c := res_mgr._resolve_skin_image(st_close.get("normal", ""))
		var f_c := res_mgr._resolve_skin_image(st_close.get("focus", ""))
		if n_c.has("texture"): close_btn.texture_normal = n_c["texture"]
		if f_c.has("texture"): close_btn.texture_hover = f_c["texture"]

	var st_snd: Dictionary = res_mgr.skin_styles.get("ID_BTN_CONFIG_SOUND_ON", {})
	var snd_normal := res_mgr._resolve_skin_image(st_snd.get("normal", ""))
	var snd_focus := res_mgr._resolve_skin_image(st_snd.get("focus", ""))
	var snd_pushed := res_mgr._resolve_skin_image(st_snd.get("pushed", ""))
	if snd_normal.has("texture"): tex_sound_on_normal = snd_normal["texture"]
	if snd_focus.has("texture"): tex_sound_on_focus = snd_focus["texture"]
	if snd_pushed.has("texture"): tex_sound_on_checked = snd_pushed["texture"]

	for char_id in voice_char_buttons:
		var btn: TextureButton = voice_char_buttons[char_id]
		if btn != null:
			if tex_sound_on_normal != null: btn.texture_normal = tex_sound_on_normal
			if tex_sound_on_focus != null: btn.texture_hover = tex_sound_on_focus
			if tex_sound_on_checked != null: btn.texture_pressed = tex_sound_on_checked
			_update_voice_char_button_visual(char_id)


func _open_voice_details_modal() -> void:
	if voice_details_panel == null:
		return
	is_voice_details_open = true
	voice_details_panel.visible = true
	for char_id in voice_char_buttons:
		_update_voice_char_button_visual(char_id)
	print("[AdvPlayer] Opened native Voice Details Window.")


func _close_voice_details_modal() -> void:
	if voice_details_panel == null:
		return
	is_voice_details_open = false
	voice_details_panel.visible = false
	print("[AdvPlayer] Closed native Voice Details Window.")


func _toggle_character_voice(char_id: String) -> void:
	var cur_val: bool = voice_char_mutes.get(char_id, false)
	voice_char_mutes[char_id] = not cur_val
	if host != null:
		host.voice_char_mutes[char_id] = not cur_val
	_update_voice_char_button_visual(char_id)
	print("[AdvPlayer] Voice for %s set to %s" % [char_id, "MUTED" if voice_char_mutes[char_id] else "ACTIVE"])


func _update_voice_char_button_visual(char_id: String) -> void:
	var btn: TextureButton = voice_char_buttons.get(char_id, null)
	if btn == null:
		return
	var is_muted: bool = voice_char_mutes.get(char_id, false)
	if is_muted:
		btn.modulate = Color(0.35, 0.35, 0.35, 0.8)
	else:
		btn.modulate = Color(1.0, 1.0, 1.0, 1.0)


# ==============================================================================
# Save / Load Modal UI & Slot Logic (方案 B: 原生皮肤与视口规格)
# ==============================================================================

func _build_save_load_ui() -> void:
	save_load_panel = PanelContainer.new()
	save_load_panel.name = "SaveLoadPanel"
	save_load_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	save_load_panel.visible = false
	save_load_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.05, 0.88)
	save_load_panel.add_theme_stylebox_override("panel", style)
	add_child(save_load_panel)

	var center := Control.new()
	center.name = "SaveLoadCenterRoot"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	save_load_panel.add_child(center)

	# Authentic 690 x 574 window box centered
	save_load_box = Control.new()
	save_load_box.name = "SaveLoadWindowBox"
	save_load_box.anchor_left = 0.5
	save_load_box.anchor_right = 0.5
	save_load_box.anchor_top = 0.5
	save_load_box.anchor_bottom = 0.5
	save_load_box.offset_left = -345.0
	save_load_box.offset_right = 345.0
	save_load_box.offset_top = -287.0
	save_load_box.offset_bottom = 287.0
	center.add_child(save_load_box)

	# Header Title Image (FRM_0506 / FRM_0505 at 8, 0, size 131x27)
	save_load_title_img = TextureRect.new()
	save_load_title_img.name = "SaveLoadTitleImg"
	save_load_title_img.position = Vector2(8, 0)
	save_load_title_img.size = Vector2(131, 27)
	save_load_box.add_child(save_load_title_img)

	# Compatibility Title Label
	save_load_title = Label.new()
	save_load_title.name = "SaveLoadTitle"
	save_load_title.text = "💾 游戏存档 / Save"
	save_load_title.position = Vector2(148, 2)
	save_load_title.add_theme_font_size_override("font_size", 16)
	save_load_title.add_theme_color_override("font_color", Color("#abb2bf"))
	save_load_box.add_child(save_load_title)

	# Mode toggle buttons (Save / Load)
	save_load_mode_btn_save = Button.new()
	save_load_mode_btn_save.name = "BtnModeSave"
	save_load_mode_btn_save.text = "💾 存档模式"
	save_load_mode_btn_save.position = Vector2(340, 0)
	save_load_mode_btn_save.size = Vector2(90, 26)
	save_load_mode_btn_save.pressed.connect(func(): _switch_save_load_mode("save"))
	save_load_box.add_child(save_load_mode_btn_save)

	save_load_mode_btn_load = Button.new()
	save_load_mode_btn_load.name = "BtnModeLoad"
	save_load_mode_btn_load.text = "📂 读档模式"
	save_load_mode_btn_load.position = Vector2(438, 0)
	save_load_mode_btn_load.size = Vector2(90, 26)
	save_load_mode_btn_load.pressed.connect(func(): _switch_save_load_mode("load"))
	save_load_box.add_child(save_load_mode_btn_load)

	# Close button at top right (pos 665, 4, size 16x17)
	var close_btn := TextureButton.new()
	close_btn.name = "ID_CLOSE"
	close_btn.position = Vector2(665, 4)
	close_btn.size = Vector2(16, 17)
	close_btn.pressed.connect(_close_save_load_modal)
	save_load_box.add_child(close_btn)

	# Quick Load Button beside the page bar (ID_QSAVE)
	btn_qload = TextureButton.new()
	btn_qload.name = "ID_QSAVE"
	btn_qload.position = Vector2(580, 547)
	btn_qload.size = Vector2(84, 25)
	btn_qload.pressed.connect(_on_quick_load_clicked)
	save_load_box.add_child(btn_qload)

	# ScrollBar at (671, 33), size 18x504
	save_load_scroll = VScrollBar.new()
	save_load_scroll.name = "ID_SCROLL"
	save_load_scroll.position = Vector2(671, 33)
	save_load_scroll.size = Vector2(18, 504)
	save_load_scroll.min_value = 0.0
	save_load_scroll.max_value = 5.0
	save_load_scroll.step = 1.0
	save_load_scroll.value = 0.0
	save_load_scroll.value_changed.connect(func(v: float): _select_save_load_page(int(v) + 1))
	save_load_box.add_child(save_load_scroll)

	# Scroll Container & Grid Container for slots (668 x 508 at 0, 33)
	var scroll := ScrollContainer.new()
	scroll.name = "SaveSlotScroll"
	scroll.position = Vector2(0, 33)
	scroll.size = Vector2(668, 508)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	save_load_box.add_child(scroll)

	save_load_grid = GridContainer.new()
	save_load_grid.name = "SaveLoadGrid"
	save_load_grid.columns = 3
	save_load_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_load_grid.add_theme_constant_override("h_separation", 4)
	save_load_grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(save_load_grid)

	# Page buttons (0..6)
	page_buttons.clear()
	var page_labels: Array[String] = [
		"⚡ 快存/快读", "第 1 页", "第 2 页", "第 3 页", "第 4 页", "第 5 页", "第 6 页"
	]
	var page_bar := HBoxContainer.new()
	page_bar.name = "SavePageBar"
	page_bar.position = Vector2(8, 547)
	page_bar.add_theme_constant_override("separation", 6)
	save_load_box.add_child(page_bar)

	for p in range(page_labels.size()):
		var p_btn := Button.new()
		p_btn.name = "PageBtn_%d" % p
		p_btn.text = page_labels[p]
		p_btn.pressed.connect(_select_save_load_page.bind(p))
		page_bar.add_child(p_btn)
		page_buttons.append(p_btn)


func _apply_save_load_skin() -> void:
	if host == null or save_load_panel == null:
		return
	var res_mgr := CsxHostClass.HostResourceManager.new(host)
	if res_mgr.load_resource("frame.noa") != 1:
		return

	# Load titles
	var save_title_res := host.load_image("FRM_0506.eri", res_mgr.loaded_archive_name)
	if save_title_res.get("ok", false) and save_title_res.get("texture") != null:
		tex_save_title = save_title_res["texture"]

	var load_title_res := host.load_image("FRM_0505.eri", res_mgr.loaded_archive_name)
	if load_title_res.get("ok", false) and load_title_res.get("texture") != null:
		tex_load_title = load_title_res["texture"]

	# Slot backgrounds
	var card_norm := res_mgr._resolve_skin_image("ID_FRM_0501:RECT(0,0,220,170)")
	if card_norm.has("texture"): tex_slot_bg_normal = card_norm["texture"]
	var card_foc := res_mgr._resolve_skin_image("ID_FRM_0501:RECT(220,0,220,170)")
	if card_foc.has("texture"): tex_slot_bg_focus = card_foc["texture"]

	# NEW badge
	var badge_res := host.load_image("FRM_0502.eri", res_mgr.loaded_archive_name)
	if badge_res.get("ok", false) and badge_res.get("texture") != null:
		tex_badge_new = badge_res["texture"]

	# QLoad button
	var qload_st: Dictionary = res_mgr.skin_styles.get("ID_BTN_ADV_QLOAD", {})
	var ql_norm := res_mgr._resolve_skin_image(qload_st.get("normal", ""))
	var ql_foc := res_mgr._resolve_skin_image(qload_st.get("focus", ""))
	if ql_norm.has("texture"): tex_qload_normal = ql_norm["texture"]
	if ql_foc.has("texture"): tex_qload_focus = ql_foc["texture"]

	if btn_qload != null:
		if tex_qload_normal != null: btn_qload.texture_normal = tex_qload_normal
		if tex_qload_focus != null: btn_qload.texture_hover = tex_qload_focus

	# Close button
	var close_st: Dictionary = res_mgr.skin_styles.get("ID_BTN_ADV_CLOSE", {})
	var cl_norm := res_mgr._resolve_skin_image(close_st.get("normal", ""))
	var cl_foc := res_mgr._resolve_skin_image(close_st.get("focus", ""))
	if cl_norm.has("texture"): tex_save_close_normal = cl_norm["texture"]
	if cl_foc.has("texture"): tex_save_close_focus = cl_foc["texture"]

	var close_btn: TextureButton = save_load_box.find_child("ID_CLOSE", true, false)
	if close_btn != null:
		if tex_save_close_normal != null: close_btn.texture_normal = tex_save_close_normal
		if tex_save_close_focus != null: close_btn.texture_hover = tex_save_close_focus

	# Scrollbar
	if save_load_scroll != null:
		var scrl_st: Dictionary = res_mgr.skin_styles.get("ID_SCRL_HISTORY", {})
		var col_img := host.load_image("FRM_0302.eri", res_mgr.loaded_archive_name)
		var bar_norm := res_mgr._resolve_skin_image(scrl_st.get("normal_bar", ""))
		var bar_foc := res_mgr._resolve_skin_image(scrl_st.get("focus_bar", ""))
		if bar_norm.has("texture"):
			save_load_scroll.add_theme_icon_override("grabber", bar_norm["texture"])
		if bar_foc.has("texture"):
			save_load_scroll.add_theme_icon_override("grabber_highlight", bar_foc["texture"])
		if col_img.get("ok", false) and col_img.get("texture") != null:
			var track_style := StyleBoxTexture.new()
			track_style.texture = col_img["texture"]
			save_load_scroll.add_theme_stylebox_override("scroll", track_style)

	_update_save_load_mode_buttons()


func _apply_appreciation_skin() -> void:
	if host == null or appreciation_panel == null:
		return
	var res_mgr := CsxHostClass.HostResourceManager.new(host)
	if res_mgr.load_resource("option.noa") != 1:
		return

	# Background FRM_0701.eri (800x600)
	var bg_res := host.load_image("FRM_0701.eri", res_mgr.loaded_archive_name)
	if bg_res.get("ok", false) and bg_res.get("texture") != null:
		tex_app_bg = bg_res["texture"]
		var panel_style := StyleBoxTexture.new()
		panel_style.texture = tex_app_bg
		appreciation_panel.add_theme_stylebox_override("panel", panel_style)

	# Title image FRM_0702.eri (131x26)
	var title_res := host.load_image("FRM_0702.eri", res_mgr.loaded_archive_name)
	if title_res.get("ok", false) and title_res.get("texture") != null:
		tex_app_title = title_res["texture"]

	# Recollection Card Frames
	var card_norm := res_mgr._resolve_skin_image("ID_FRM_0734:RECT(0,0,242,90)")
	if card_norm.has("texture"): tex_rec_card_normal = card_norm["texture"]

	var card_foc := res_mgr._resolve_skin_image("ID_FRM_0734:RECT(242,0,242,90)")
	if card_foc.has("texture"): tex_rec_card_focus = card_foc["texture"]

	# Locked Banner FRM_0735.eri (242x90)
	var lock_res := host.load_image("FRM_0735.eri", res_mgr.loaded_archive_name)
	if lock_res.get("ok", false) and lock_res.get("texture") != null:
		tex_rec_locked = lock_res["texture"]

	# Recollection Button FRM_0724.eri (41x28)
	var rec_norm := res_mgr._resolve_skin_image("ID_FRM_0724:RECT(0,0,41,28)")
	if rec_norm.has("texture"): tex_rec_btn_normal = rec_norm["texture"]

	var rec_foc := res_mgr._resolve_skin_image("ID_FRM_0724:RECT(41,0,41,28)")
	if rec_foc.has("texture"): tex_rec_btn_focus = rec_foc["texture"]

	# Close Button FRM_0119.eri (16x17)
	var close_norm := res_mgr._resolve_skin_image("ID_FRM_0119:RECT(0,0,16,17)")
	if close_norm.has("texture"): tex_app_close_normal = close_norm["texture"]

	var close_foc := res_mgr._resolve_skin_image("ID_FRM_0119:RECT(16,0,16,17)")
	if close_foc.has("texture"): tex_app_close_focus = close_foc["texture"]

	if app_close_btn != null and tex_app_close_normal != null:
		app_close_btn.icon = tex_app_close_normal


func _open_save_load_modal(mode: String = "load") -> void:
	if is_title_mode and mode == "save":
		mode = "load"
	save_load_mode = mode
	is_save_load_open = true
	save_load_panel.z_index = 4096 if is_title_mode else 0
	save_load_panel.visible = true
	if save_load_mode_btn_save != null:
		save_load_mode_btn_save.visible = not is_title_mode
	_update_save_load_mode_buttons()
	_populate_save_load_slots()
	print("[AdvPlayer] Opened native Save/Load Modal (%s mode)." % mode)


func _close_save_load_modal() -> void:
	is_save_load_open = false
	save_load_panel.visible = false
	print("[AdvPlayer] Closed native Save/Load Modal.")


func _switch_save_load_mode(mode: String) -> void:
	save_load_mode = mode
	_update_save_load_mode_buttons()
	_populate_save_load_slots()


func _update_save_load_mode_buttons() -> void:
	if save_load_mode == "save":
		if save_load_title != null: save_load_title.text = "💾 游戏存档 (Save)"
		if save_load_title_img != null and tex_save_title != null:
			save_load_title_img.texture = tex_save_title
		if btn_qload != null:
			btn_qload.visible = false
		if save_load_mode_btn_save != null: save_load_mode_btn_save.modulate = Color("#98c379")
		if save_load_mode_btn_load != null: save_load_mode_btn_load.modulate = Color("#ffffff")
	else:
		if save_load_title != null: save_load_title.text = "📂 读取存档 (Load)"
		if save_load_title_img != null and tex_load_title != null:
			save_load_title_img.texture = tex_load_title
		if btn_qload != null:
			btn_qload.visible = true
		if save_load_mode_btn_load != null: save_load_mode_btn_load.modulate = Color("#61afef")
		if save_load_mode_btn_save != null: save_load_mode_btn_save.modulate = Color("#ffffff")


func _select_save_load_page(page: int) -> void:
	save_load_page = page
	for i in range(page_buttons.size()):
		if i == page:
			page_buttons[i].modulate = Color("#e5c07b")
		else:
			page_buttons[i].modulate = Color("#ffffff")
	if save_load_scroll != null and page >= 1:
		save_load_scroll.value = float(page - 1)
	_populate_save_load_slots()


func _on_quick_load_clicked() -> void:
	var info := get_slot_info(0)
	if info["exists"]:
		_show_confirm_dialog("确定要读取快速存档 (QSave) 吗？未保存的进度将会丢失。", func(): load_from_slot(0))
	else:
		print("[AdvPlayer] Quick Save is empty, cannot load.")


func get_slot_info(slot: int) -> Dictionary:
	var info := {
		"slot": slot,
		"exists": false,
		"comment": "",
		"timestamp": "",
		"thumbnail": null
	}
	if host == null:
		return info

	var save_path := _readable_slot_path(slot)
	if save_path.is_empty():
		return info
	info["exists"] = true
	var modified := FileAccess.get_modified_time(save_path)
	var time := Time.get_datetime_dict_from_unix_time(modified)
	info["timestamp"] = "%04d/%02d/%02d %02d:%02d:%02d" % [time.year, time.month, time.day, time.hour, time.minute, time.second]
	if slot == 0:
		info["comment"] = "快速存档 (Quick Save)"

	if slot > 0 and vm != null:
		var sys_obj = vm.globals_by_name.get("sysObj", null)
		if sys_obj is CsxVMReader.CsxInstance:
			var bookmarks: Variant = sys_obj.get_field("bookmark")
			if bookmarks is Array and slot < bookmarks.size():
				var bookmark: Variant = bookmarks[slot]
				if bookmark is CsxVMReader.CsxInstance and bookmark.get_field("fSave") != 0 and not save_path.ends_with(".bak"):
					info["comment"] = str(bookmark.get_field("comment"))

	var thumb_path := host.get_thumbnail_path(_slot_save_path(slot).get_file())
	if not save_path.ends_with(".bak") and FileAccess.file_exists(thumb_path):
		var img := Image.load_from_file(thumb_path)
		if img != null:
			info["thumbnail"] = ImageTexture.create_from_image(img)
	return info


func _populate_save_load_slots() -> void:
	for c in save_load_grid.get_children():
		save_load_grid.remove_child(c)
		c.queue_free()

	# Find newest slot among all saves
	var newest_slot: int = -1
	var newest_time: int = -1
	if host != null:
		for slot in range(61):
			var path := _readable_slot_path(slot)
			if path.is_empty():
				continue
			var modified := FileAccess.get_modified_time(path)
			if modified > newest_time:
				newest_time = modified
				newest_slot = slot

	var slots_to_show: Array[int] = []
	if save_load_page == 0:
		slots_to_show.append(0)
	else:
		var start_slot: int = (save_load_page - 1) * 10 + 1
		for s in range(start_slot, start_slot + 10):
			if s <= 60:
				slots_to_show.append(s)

	for slot_idx in slots_to_show:
		_add_slot_card(slot_idx, slot_idx == newest_slot)


func _add_slot_card(slot_idx: int, is_newest: bool = false) -> void:
	var info := get_slot_info(slot_idx)

	var card_btn := TextureButton.new()
	card_btn.name = "SlotCard_%02d" % slot_idx
	card_btn.custom_minimum_size = Vector2(218, 166)
	card_btn.size = Vector2(220, 170)
	card_btn.ignore_texture_size = true
	card_btn.stretch_mode = TextureButton.STRETCH_SCALE
	if tex_slot_bg_normal != null:
		card_btn.texture_normal = tex_slot_bg_normal
	if tex_slot_bg_focus != null:
		card_btn.texture_hover = tex_slot_bg_focus
		card_btn.texture_pressed = tex_slot_bg_focus

	# Thumbnail (sprThumb) at (95, 2), size 120x90
	var thumb_rect := TextureRect.new()
	thumb_rect.name = "ID_THUMBNAIL"
	thumb_rect.position = Vector2(95, 2)
	thumb_rect.size = Vector2(120, 90)
	thumb_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if info["thumbnail"] != null:
		thumb_rect.texture = info["thumbnail"]
	card_btn.add_child(thumb_rect)

	# NEW badge (ID_NEW) at (8, 3), size 43x33
	var new_badge := TextureRect.new()
	new_badge.name = "ID_NEW"
	new_badge.position = Vector2(8, 3)
	new_badge.size = Vector2(43, 33)
	new_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tex_badge_new != null:
		new_badge.texture = tex_badge_new
	new_badge.visible = info["exists"] and is_newest
	card_btn.add_child(new_badge)

	# Slot Number (ID_NUMBER) at (15, 38)
	var num_lbl := Label.new()
	num_lbl.name = "ID_NUMBER"
	num_lbl.position = Vector2(15, 38)
	num_lbl.text = ("⚡ 快存" if slot_idx == 0 else "No. %02d" % slot_idx)
	num_lbl.add_theme_font_size_override("font_size", 15)
	num_lbl.add_theme_color_override("font_color", Color("#e5c07b"))
	num_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_btn.add_child(num_lbl)

	# Save Date/Time (ID_DATE) at (7, 100)
	var time_lbl := Label.new()
	time_lbl.name = "ID_DATE"
	time_lbl.position = Vector2(7, 100)
	time_lbl.text = info["timestamp"] if info["exists"] else "----/--/-- --:--:--"
	time_lbl.add_theme_font_size_override("font_size", 12)
	time_lbl.add_theme_color_override("font_color", Color("#abb2bf") if info["exists"] else Color("#5c6370"))
	time_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_btn.add_child(time_lbl)

	# Save Comment (ID_COMMENT) at (14, 121)
	var comment_lbl := Label.new()
	comment_lbl.name = "ID_COMMENT"
	comment_lbl.position = Vector2(14, 121)
	comment_lbl.size = Vector2(195, 42)
	comment_lbl.text = info["comment"] if info["exists"] else "（无存档数据）"
	comment_lbl.add_theme_font_size_override("font_size", 11)
	comment_lbl.add_theme_color_override("font_color", Color("#98c379") if info["exists"] else Color("#5c6370"))
	comment_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	comment_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	comment_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_btn.add_child(comment_lbl)

	card_btn.pressed.connect(_on_slot_clicked.bind(slot_idx, info))
	save_load_grid.add_child(card_btn)


func _on_slot_clicked(slot_idx: int, info: Dictionary) -> void:
	if save_load_mode == "save":
		if info["exists"]:
			_show_confirm_dialog("确定要覆盖存档 Slot %02d 吗？" % slot_idx, func(): save_to_slot(slot_idx))
		else:
			save_to_slot(slot_idx)
	else: # load
		if info["exists"]:
			_show_confirm_dialog("确定要读取存档 Slot %02d 吗？未保存的进度将会丢失。" % slot_idx, func(): load_from_slot(slot_idx))
		else:
			print("[AdvPlayer] Slot %02d is empty, cannot load." % slot_idx)


func save_to_slot(slot: int) -> bool:
	if vm == null or not is_running:
		print("[AdvPlayer] Cannot save: engine not running.")
		return false
	if host == null:
		return false
	var save_path := _slot_save_path(slot)
	var res: Dictionary
	if slot == 0:
		res = vm.call_function_sync("QuickSave", [], 100_000)
	else:
		res = vm.call_function_sync("NormalSave", [slot, [], []], 100_000)

	if _is_csx_operation_success(res) and _is_valid_save_document(save_path):
		print("[AdvPlayer] Successfully saved to Slot %02d" % slot)
		message_label.text = "[color=#98c379]★ 存档成功 (Slot %02d)[/color]\n" % slot + host.current_dialogue
		_populate_save_load_slots()
		return true
	else:
		var error_text := _csx_operation_error(res)
		if not _is_valid_save_document(save_path):
			error_text = "目标存档不存在或内容无效" if error_text.is_empty() else error_text + "；目标存档不存在或内容无效"
		print("[AdvPlayer] Save to Slot %02d failed: %s" % [slot, error_text])
		message_label.text = "[color=#e06c75]存档失败: %s[/color]" % error_text
		return false


func load_from_slot(slot: int) -> bool:
	if vm == null or host == null:
		print("[AdvPlayer] Cannot load: VM or host is null.")
		return false
	var save_path := _slot_save_path(slot)
	if _readable_slot_path(slot).is_empty():
		var error_text := "存档不存在或 JSON 内容无效: %s" % save_path
		print("[AdvPlayer] Load from Slot %02d failed: %s" % [slot, error_text])
		message_label.text = "[color=#e06c75]读档失败: %s[/color]" % error_text
		return false

	var res: Dictionary
	if slot == 0:
		res = vm.call_function_sync("QuickLoad", [0], 100_000)
	else:
		res = vm.call_function_sync("NormalLoad", [slot], 100_000)

	if not _is_csx_operation_success(res):
		var error_text := _csx_operation_error(res)
		print("[AdvPlayer] Load from Slot %02d failed: %s" % [slot, error_text])
		message_label.text = "[color=#e06c75]读档失败: %s[/color]" % error_text
		return false

	print("[AdvPlayer] Successfully loaded from Slot %02d" % slot)
	_close_save_load_modal()

	var sc_obj = vm.globals_by_name.get("scObj", null)
	var current_sc: String = start_scenario
	if sc_obj is CsxVMReader.CsxInstance:
		var sc_call: String = str(sc_obj.get_field("scenarioCall"))
		if not sc_call.is_empty():
			current_sc = sc_call

	if is_title_mode:
		_exit_title_to_game()

	# Re-enter ScenarioLoop
	if vm.functions.has("ScenarioLoop"):
		vm.ip = vm.functions["ScenarioLoop"]
		vm.is_halted = false
		vm.pending_call_args = [current_sc]
		vm.pending_return_ip = -1
		vm.call_stack.clear()
		vm.eval_stack.clear()
		is_running = true

	if host.current_bg_texture != null:
		bg_rect.texture = host.current_bg_texture
	speaker_label.text = host.current_speaker
	message_label.text = "[color=#98c379]★ 已读取存档 (Slot %02d)[/color]\n" % slot + host.current_dialogue
	return true


func _slot_save_path(slot: int) -> String:
	return host.get_save_path("QSave.dat" if slot == 0 else "Save%03d.dat" % slot)


func _is_csx_operation_success(result: Dictionary) -> bool:
	if not result.get("ok", false) or not result.has("result"):
		return false
	var value: Variant = result["result"]
	if value is bool:
		return value
	if value is int or value is float:
		return is_zero_approx(float(value))
	return false


func _csx_operation_error(result: Dictionary) -> String:
	if not result.get("ok", false):
		return str(result.get("error", "VM 调用失败"))
	if not result.has("result"):
		return "CSX 保存/读取函数没有返回业务状态"
	return "CSX 保存/读取函数返回失败状态 %s" % str(result["result"])


func _readable_slot_path(slot: int) -> String:
	if slot < 0 or slot > 60:
		return ""
	var snapshot := host.read_save_snapshot(_slot_save_path(slot), true, true)
	return str(snapshot.get("path", ""))


func _is_valid_save_document(path: String) -> bool:
	return not host.read_save_snapshot(path, false, true).is_empty()


# ==============================================================================
# Appreciation / Gallery & Jukebox Methods
# ==============================================================================

func _init_cg_catalog() -> void:
	cg_catalog.clear()
	for cat in CG_CATEGORIES:
		cg_catalog[cat["id"]] = []

	if host == null:
		return

	var archive_sources: Array[Dictionary] = []
	for archive_hint: String in ["data1.noa", "data2.noa"]:
		var archive = host.get_or_open_archive(archive_hint)
		if archive == null:
			continue
		for entry_index in range(archive.entries.size()):
			archive_sources.append({
				"entry": archive.entries[entry_index],
				"archive_hint": archive_hint,
				"entry_index": entry_index,
			})

	var grouped: Dictionary = {}
	for cat in CG_CATEGORIES:
		grouped[cat["id"]] = {}

	for source: Dictionary in archive_sources:
		var entry: Dictionary = source["entry"]
		var name_str: String = str(entry["name"]).to_upper()
		if name_str.ends_with(".ERI") and name_str.length() >= 5 and name_str.begins_with("E"):
			var cat_id: String = name_str.substr(0, 2)
			if grouped.has(cat_id):
				var base_name: String = name_str.get_basename()
				var i: int = 2
				while i < base_name.length() and base_name[i].is_valid_int():
					i += 1
				var scene_id: String = base_name.substr(0, i)
				if not grouped[cat_id].has(scene_id):
					grouped[cat_id][scene_id] = []
				grouped[cat_id][scene_id].append({
					"name": str(entry["name"]),
					"archive_hint": str(source["archive_hint"]),
					"entry_index": int(source["entry_index"]),
				})

	for cat_id in grouped.keys():
		var scene_ids: Array = grouped[cat_id].keys()
		scene_ids.sort()
		var scene_list: Array[Dictionary] = []
		for s_id in scene_ids:
			var file_refs: Array = grouped[cat_id][s_id]
			file_refs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var a_name := str(a.get("name", "")).to_lower()
				var b_name := str(b.get("name", "")).to_lower()
				if a_name != b_name:
					return a_name < b_name
				var a_archive := str(a.get("archive_hint", "")).to_lower()
				var b_archive := str(b.get("archive_hint", "")).to_lower()
				if a_archive != b_archive:
					return a_archive < b_archive
				return int(a.get("entry_index", -1)) < int(b.get("entry_index", -1))
			)
			var files: Array[String] = []
			for file_ref: Dictionary in file_refs:
				files.append(str(file_ref.get("name", "")))
			scene_list.append({
				"scene_id": s_id,
				"files": files,
				"file_refs": file_refs,
				"first_file": files[0] if files.size() > 0 else "",
				"first_file_ref": file_refs[0] if file_refs.size() > 0 else {},
			})
		cg_catalog[cat_id] = scene_list

	print("[AdvPlayer] CG Catalog initialized: %d categories loaded." % cg_catalog.size())


func _build_appreciation_ui() -> void:
	appreciation_panel = PanelContainer.new()
	appreciation_panel.name = "AppreciationPanel"
	appreciation_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	appreciation_panel.visible = false
	appreciation_panel.z_index = 25
	appreciation_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.04, 0.05, 0.08, 0.97)
	panel_style.border_color = Color(0.25, 0.35, 0.5, 0.8)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	appreciation_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(appreciation_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	appreciation_panel.add_child(margin)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 14)
	margin.add_child(main_vbox)

	# 1. Header with title, mode switcher, unlock toggle, close button
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	main_vbox.add_child(header)

	var title_lbl := Label.new()
	title_lbl.text = "🎨 鉴赏与回想 (Extra Gallery & Jukebox)"
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.add_theme_color_override("font_color", Color("#abb2bf"))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_lbl)
	app_title_lbl = title_lbl

	btn_app_cg = Button.new()
	btn_app_cg.text = "🖼️ CG 鉴赏"
	btn_app_cg.custom_minimum_size = Vector2(110, 36)
	btn_app_cg.pressed.connect(func(): _switch_app_mode("cg"))
	header.add_child(btn_app_cg)

	btn_app_rec = Button.new()
	btn_app_rec.text = "🎬 场景回想"
	btn_app_rec.custom_minimum_size = Vector2(110, 36)
	btn_app_rec.pressed.connect(func(): _switch_app_mode("rec"))
	header.add_child(btn_app_rec)

	btn_app_bgm = Button.new()
	btn_app_bgm.text = "🎵 音乐回想"
	btn_app_bgm.custom_minimum_size = Vector2(110, 36)
	btn_app_bgm.pressed.connect(func(): _switch_app_mode("bgm"))
	header.add_child(btn_app_bgm)

	btn_unlock_toggle = Button.new()
	btn_unlock_toggle.text = "🔓 全解锁: 开"
	btn_unlock_toggle.custom_minimum_size = Vector2(110, 36)
	btn_unlock_toggle.pressed.connect(_toggle_unlock_mode)
	header.add_child(btn_unlock_toggle)

	var close_btn := Button.new()
	close_btn.text = "✕ 关闭 (ESC)"
	close_btn.custom_minimum_size = Vector2(100, 36)
	close_btn.pressed.connect(_close_appreciation_modal)
	header.add_child(close_btn)
	app_close_btn = close_btn

	# 2. CG Gallery Sub-Container
	cg_gallery_container = VBoxContainer.new()
	cg_gallery_container.name = "CgGalleryContainer"
	cg_gallery_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cg_gallery_container.add_theme_constant_override("separation", 12)
	main_vbox.add_child(cg_gallery_container)

	# Category Tabs
	var cat_hbox := HBoxContainer.new()
	cat_hbox.add_theme_constant_override("separation", 8)
	cg_gallery_container.add_child(cat_hbox)

	cg_category_buttons.clear()
	for cat in CG_CATEGORIES:
		var btn := Button.new()
		btn.text = "%s (%s)" % [cat["name"], cat["id"]]
		btn.custom_minimum_size = Vector2(115, 34)
		var cat_id: String = cat["id"]
		btn.pressed.connect(func(): _switch_cg_category(cat_id))
		cat_hbox.add_child(btn)
		cg_category_buttons.append(btn)

	# CG Cards Scroll / Center Container
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	cg_gallery_container.add_child(scroll)

	var grid_center := CenterContainer.new()
	grid_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid_center)

	cg_grid = GridContainer.new()
	cg_grid.columns = 4
	cg_grid.add_theme_constant_override("h_separation", 18)
	cg_grid.add_theme_constant_override("v_separation", 18)
	grid_center.add_child(cg_grid)

	# CG Pagination Bar
	var cg_page_bar := HBoxContainer.new()
	cg_page_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	cg_page_bar.add_theme_constant_override("separation", 16)
	cg_gallery_container.add_child(cg_page_bar)

	var btn_cg_prev := Button.new()
	btn_cg_prev.text = "◀ 上一页"
	btn_cg_prev.custom_minimum_size = Vector2(90, 32)
	btn_cg_prev.pressed.connect(_prev_cg_page)
	cg_page_bar.add_child(btn_cg_prev)

	cg_page_label = Label.new()
	cg_page_label.text = "第 1 / 1 页"
	cg_page_label.add_theme_font_size_override("font_size", 15)
	cg_page_bar.add_child(cg_page_label)

	var btn_cg_next := Button.new()
	btn_cg_next.text = "下一页 ▶"
	btn_cg_next.custom_minimum_size = Vector2(90, 32)
	btn_cg_next.pressed.connect(_next_cg_page)
	cg_page_bar.add_child(btn_cg_next)

	# 3. Scene Recollection Sub-Container
	rec_container = VBoxContainer.new()
	rec_container.name = "RecollectionContainer"
	rec_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rec_container.visible = false
	rec_container.add_theme_constant_override("separation", 14)
	main_vbox.add_child(rec_container)

	# Heroine Tabs
	var rec_tab_hbox := HBoxContainer.new()
	rec_tab_hbox.add_theme_constant_override("separation", 10)
	rec_container.add_child(rec_tab_hbox)

	rec_heroine_buttons.clear()
	for idx in range(RECOLLECTION_HEROINES.size()):
		var hero: Dictionary = RECOLLECTION_HEROINES[idx]
		var h_btn := Button.new()
		h_btn.text = hero["heroine"]
		h_btn.custom_minimum_size = Vector2(130, 34)
		var h_idx := idx
		h_btn.pressed.connect(func(): _switch_rec_heroine(h_idx))
		rec_tab_hbox.add_child(h_btn)
		rec_heroine_buttons.append(h_btn)

	# Recollection Grid Scroll
	var rec_scroll := ScrollContainer.new()
	rec_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rec_scroll.follow_focus = true
	rec_container.add_child(rec_scroll)

	var rec_grid_center := CenterContainer.new()
	rec_grid_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rec_grid_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rec_scroll.add_child(rec_grid_center)

	rec_grid = GridContainer.new()
	rec_grid.columns = 2
	rec_grid.add_theme_constant_override("h_separation", 24)
	rec_grid.add_theme_constant_override("v_separation", 20)
	rec_grid_center.add_child(rec_grid)

	# 4. BGM Jukebox Sub-Container
	bgm_jukebox_container = HBoxContainer.new()
	bgm_jukebox_container.name = "BgmJukeboxContainer"
	bgm_jukebox_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bgm_jukebox_container.visible = false
	bgm_jukebox_container.add_theme_constant_override("separation", 24)
	main_vbox.add_child(bgm_jukebox_container)

	# Left: Track List Scroll
	var track_scroll := ScrollContainer.new()
	track_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	track_scroll.size_flags_stretch_ratio = 1.3
	bgm_jukebox_container.add_child(track_scroll)

	bgm_track_list_vbox = VBoxContainer.new()
	bgm_track_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bgm_track_list_vbox.add_theme_constant_override("separation", 6)
	track_scroll.add_child(bgm_track_list_vbox)

	bgm_track_buttons.clear()
	for i in range(BGM_TRACKS.size()):
		var track: Dictionary = BGM_TRACKS[i]
		var t_btn := Button.new()
		t_btn.text = "No.%02d  %s  (%s)" % [i + 1, track["title"], track["file"]]
		t_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		t_btn.custom_minimum_size = Vector2(0, 34)
		var track_idx := i
		t_btn.pressed.connect(func(): _play_jukebox_bgm(track_idx))
		bgm_track_list_vbox.add_child(t_btn)
		bgm_track_buttons.append(t_btn)

	# Right: Now Playing & Controls
	var jukebox_right := VBoxContainer.new()
	jukebox_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jukebox_right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	jukebox_right.size_flags_stretch_ratio = 1.0
	jukebox_right.add_theme_constant_override("separation", 18)
	bgm_jukebox_container.add_child(jukebox_right)

	# Playing Card Panel
	var card_panel := PanelContainer.new()
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.08, 0.10, 0.15, 0.9)
	card_style.border_color = Color(0.3, 0.45, 0.65, 0.6)
	card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(6)
	card_panel.add_theme_stylebox_override("panel", card_style)
	jukebox_right.add_child(card_panel)

	var card_margin := MarginContainer.new()
	card_margin.add_theme_constant_override("margin_left", 20)
	card_margin.add_theme_constant_override("margin_right", 20)
	card_margin.add_theme_constant_override("margin_top", 24)
	card_margin.add_theme_constant_override("margin_bottom", 24)
	card_panel.add_child(card_margin)

	var card_vbox := VBoxContainer.new()
	card_vbox.add_theme_constant_override("separation", 12)
	card_margin.add_child(card_vbox)

	var icon_lbl := Label.new()
	icon_lbl.text = "🎵"
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.add_theme_font_size_override("font_size", 42)
	card_vbox.add_child(icon_lbl)

	bgm_now_playing_label = Label.new()
	bgm_now_playing_label.text = "选择曲目以开始播放\nSelect a track to play"
	bgm_now_playing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bgm_now_playing_label.add_theme_font_size_override("font_size", 16)
	bgm_now_playing_label.add_theme_color_override("font_color", Color("#abb2bf"))
	card_vbox.add_child(bgm_now_playing_label)

	# Controls Bar
	var ctrl_hbox := HBoxContainer.new()
	ctrl_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	ctrl_hbox.add_theme_constant_override("separation", 14)
	jukebox_right.add_child(ctrl_hbox)

	var btn_prev_track := Button.new()
	btn_prev_track.text = "◀◀ 上一首"
	btn_prev_track.custom_minimum_size = Vector2(90, 36)
	btn_prev_track.pressed.connect(_prev_jukebox_bgm)
	ctrl_hbox.add_child(btn_prev_track)

	bgm_play_btn = Button.new()
	bgm_play_btn.text = "▶ 播放"
	bgm_play_btn.custom_minimum_size = Vector2(80, 36)
	bgm_play_btn.pressed.connect(_toggle_jukebox_bgm)
	ctrl_hbox.add_child(bgm_play_btn)

	var btn_stop_track := Button.new()
	btn_stop_track.text = "■ 停止"
	btn_stop_track.custom_minimum_size = Vector2(80, 36)
	btn_stop_track.pressed.connect(_stop_jukebox_bgm)
	ctrl_hbox.add_child(btn_stop_track)

	var btn_next_track := Button.new()
	btn_next_track.text = "下一首 ▶▶"
	btn_next_track.custom_minimum_size = Vector2(90, 36)
	btn_next_track.pressed.connect(_next_jukebox_bgm)
	ctrl_hbox.add_child(btn_next_track)

	# Volume Control
	var vol_box := HBoxContainer.new()
	vol_box.add_theme_constant_override("separation", 10)
	jukebox_right.add_child(vol_box)

	var vol_icon := Label.new()
	vol_icon.text = "🔊 音量:"
	vol_box.add_child(vol_icon)

	bgm_vol_slider = HSlider.new()
	bgm_vol_slider.min_value = 0.0
	bgm_vol_slider.max_value = 100.0
	bgm_vol_slider.value = 80.0
	bgm_vol_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bgm_vol_slider.value_changed.connect(_on_bgm_vol_changed)
	vol_box.add_child(bgm_vol_slider)

	bgm_vol_label = Label.new()
	bgm_vol_label.text = "80%"
	bgm_vol_label.custom_minimum_size = Vector2(40, 0)
	vol_box.add_child(bgm_vol_label)


func _build_cg_fullscreen_viewer() -> void:
	cg_fullscreen_panel = PanelContainer.new()
	cg_fullscreen_panel.name = "CgFullscreenPanel"
	cg_fullscreen_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cg_fullscreen_panel.visible = false
	cg_fullscreen_panel.z_index = 35
	cg_fullscreen_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0, 0, 0, 1)
	cg_fullscreen_panel.add_theme_stylebox_override("panel", bg_style)
	add_child(cg_fullscreen_panel)

	# Main Image
	fullscreen_cg_rect = TextureRect.new()
	fullscreen_cg_rect.name = "FullscreenCgRect"
	fullscreen_cg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fullscreen_cg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fullscreen_cg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	fullscreen_cg_rect.mouse_filter = Control.MOUSE_FILTER_PASS
	cg_fullscreen_panel.add_child(fullscreen_cg_rect)

	# Click overlay to advance variants
	fullscreen_cg_rect.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_next_cg_variant()
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_close_cg_fullscreen()
	)

	# Top HUD
	var top_hud := PanelContainer.new()
	top_hud.anchor_right = 1.0
	top_hud.custom_minimum_size = Vector2(0, 44)
	var top_hud_style := StyleBoxFlat.new()
	top_hud_style.bg_color = Color(0.02, 0.03, 0.05, 0.8)
	top_hud.add_theme_stylebox_override("panel", top_hud_style)
	cg_fullscreen_panel.add_child(top_hud)

	var top_margin := MarginContainer.new()
	top_margin.add_theme_constant_override("margin_left", 16)
	top_margin.add_theme_constant_override("margin_right", 16)
	top_hud.add_child(top_margin)

	var top_hbox := HBoxContainer.new()
	top_margin.add_child(top_hbox)

	fullscreen_info_label = Label.new()
	fullscreen_info_label.text = ""
	fullscreen_info_label.add_theme_font_size_override("font_size", 16)
	fullscreen_info_label.add_theme_color_override("font_color", Color("#abb2bf"))
	fullscreen_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(fullscreen_info_label)

	var exit_fs_btn := Button.new()
	exit_fs_btn.text = "✕ 退出 (ESC)"
	exit_fs_btn.pressed.connect(_close_cg_fullscreen)
	top_hbox.add_child(exit_fs_btn)

	# Bottom HUD
	var bot_hud := PanelContainer.new()
	bot_hud.anchor_top = 1.0
	bot_hud.anchor_right = 1.0
	bot_hud.anchor_bottom = 1.0
	bot_hud.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bot_hud.custom_minimum_size = Vector2(0, 44)
	var bot_hud_style := StyleBoxFlat.new()
	bot_hud_style.bg_color = Color(0.02, 0.03, 0.05, 0.8)
	bot_hud.add_theme_stylebox_override("panel", bot_hud_style)
	cg_fullscreen_panel.add_child(bot_hud)

	var bot_margin := MarginContainer.new()
	bot_margin.add_theme_constant_override("margin_left", 16)
	bot_margin.add_theme_constant_override("margin_right", 16)
	bot_hud.add_child(bot_margin)

	var bot_hbox := HBoxContainer.new()
	bot_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	bot_hbox.add_theme_constant_override("separation", 20)
	bot_margin.add_child(bot_hbox)

	var prev_v_btn := Button.new()
	prev_v_btn.text = "◀ 上一差分 (←)"
	prev_v_btn.pressed.connect(_prev_cg_variant)
	bot_hbox.add_child(prev_v_btn)

	var hint_lbl := Label.new()
	hint_lbl.text = "点击画面或使用方向键 / 空格切换差分"
	hint_lbl.add_theme_color_override("font_color", Color("#5c6370"))
	bot_hbox.add_child(hint_lbl)

	var next_v_btn := Button.new()
	next_v_btn.text = "下一差分 (→ / 空格) ▶"
	next_v_btn.pressed.connect(_next_cg_variant)
	bot_hbox.add_child(next_v_btn)


func _open_appreciation_modal() -> void:
	if cg_catalog.is_empty():
		_init_cg_catalog()

	is_appreciation_open = true
	appreciation_panel.visible = true
	if is_title_mode:
		native_title_layer.hide()

	bgm_vol_slider.set_value_no_signal(settings_state.audio_volume("bgm") * 100.0)
	bgm_vol_label.text = "%d%%" % roundi(bgm_vol_slider.value)
	_switch_app_mode(app_mode)
	print("[AdvPlayer] Opened Appreciation Modal (mode: %s)." % app_mode)


func _close_appreciation_modal() -> void:
	is_appreciation_open = false
	appreciation_panel.visible = false
	_apply_audio_channel("BGM", bgm_player)

	if is_title_mode:
		var restore_music := host != null and (host.current_bgm.to_lower() != "bgm07.mio" or not bgm_player.playing or bgm_player.stream_paused)
		if vm != null and vm.functions.has("Title"):
			if vm.is_halted or restore_music:
				_start_native_title_script()
			else:
				native_title_layer.show()
		elif restore_music:
			host.play_bgm("BGM07.mio")
	current_bgm_track_index = -1
	bgm_play_btn.text = "▶ 播放"
	print("[AdvPlayer] Closed Appreciation Modal.")


func _switch_app_mode(mode: String) -> void:
	app_mode = mode
	if mode == "cg":
		btn_app_cg.add_theme_color_override("font_color", Color("#61afef"))
		if btn_app_rec != null: btn_app_rec.remove_theme_color_override("font_color")
		btn_app_bgm.remove_theme_color_override("font_color")
		cg_gallery_container.visible = true
		if rec_container != null: rec_container.visible = false
		bgm_jukebox_container.visible = false
		_switch_cg_category(app_cg_category)
	elif mode == "rec":
		btn_app_cg.remove_theme_color_override("font_color")
		if btn_app_rec != null: btn_app_rec.add_theme_color_override("font_color", Color("#61afef"))
		btn_app_bgm.remove_theme_color_override("font_color")
		cg_gallery_container.visible = false
		if rec_container != null: rec_container.visible = true
		bgm_jukebox_container.visible = false
		_switch_rec_heroine(app_rec_heroine_index)
	else:
		btn_app_bgm.add_theme_color_override("font_color", Color("#61afef"))
		btn_app_cg.remove_theme_color_override("font_color")
		if btn_app_rec != null: btn_app_rec.remove_theme_color_override("font_color")
		cg_gallery_container.visible = false
		if rec_container != null: rec_container.visible = false
		bgm_jukebox_container.visible = true
		_update_jukebox_ui()


func _switch_cg_category(cat_id: String) -> void:
	app_cg_category = cat_id
	app_cg_page = 1
	for i in range(CG_CATEGORIES.size()):
		var cat = CG_CATEGORIES[i]
		if i < cg_category_buttons.size():
			var btn := cg_category_buttons[i]
			if cat["id"] == cat_id:
				btn.add_theme_color_override("font_color", Color("#98c379"))
			else:
				btn.remove_theme_color_override("font_color")
	_populate_cg_grid()


func _switch_rec_heroine(heroine_idx: int) -> void:
	app_rec_heroine_index = clampi(heroine_idx, 0, RECOLLECTION_HEROINES.size() - 1)
	for i in range(rec_heroine_buttons.size()):
		var btn: Button = rec_heroine_buttons[i]
		if i == app_rec_heroine_index:
			btn.add_theme_color_override("font_color", Color("#98c379"))
		else:
			btn.remove_theme_color_override("font_color")
	_populate_rec_grid()


func is_recollect_unlocked(flag_id: int) -> bool:
	if app_full_unlock:
		return true
	if vm != null:
		var sys_obj = vm.globals_by_name.get("sysObj", null)
		if sys_obj is CsxVMReader.CsxInstance:
			var rf = sys_obj.get_field("recollectFlag")
			if rf is CsxVMReader.CsxInstance:
				var flags = (rf as CsxVMReader.CsxInstance).get_field("flag")
				if flags is Array:
					var idx: int = flag_id / 32
					var shift: int = flag_id % 32
					if idx >= 0 and idx < flags.size():
						var val: int = int(flags[idx]) if flags[idx] != null else 0
						return ((val >> shift) & 1) != 0
	return false


func _populate_rec_grid() -> void:
	if rec_grid == null:
		return
	for c in rec_grid.get_children():
		rec_grid.remove_child(c)
		c.queue_free()

	if app_rec_heroine_index < 0 or app_rec_heroine_index >= RECOLLECTION_HEROINES.size():
		app_rec_heroine_index = 0

	var hero: Dictionary = RECOLLECTION_HEROINES[app_rec_heroine_index]
	var scenes: Array = hero.get("scenes", [])
	for s in scenes:
		var card := _create_recollect_card(s, app_rec_heroine_index)
		rec_grid.add_child(card)


func _create_recollect_card(scene_info: Dictionary, heroine_idx: int) -> Control:
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(242, 122)
	vbox.add_theme_constant_override("separation", 6)

	var btn := TextureButton.new()
	btn.custom_minimum_size = Vector2(242, 90)
	btn.ignore_texture_size = false
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED

	var is_unlocked: bool = is_recollect_unlocked(int(scene_info.get("flag", 0)))
	var banner_name: String = str(scene_info.get("banner", ""))

	if is_unlocked:
		if tex_rec_card_normal != null: btn.texture_normal = tex_rec_card_normal
		if tex_rec_card_focus != null: btn.texture_hover = tex_rec_card_focus

		var banner_rect := TextureRect.new()
		banner_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		banner_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		banner_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		banner_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

		if not banner_name.is_empty():
			if rec_banner_cache.has(banner_name):
				banner_rect.texture = rec_banner_cache[banner_name]
			elif host != null:
				var res := host.load_image(banner_name)
				if res.get("ok", false) and res.get("texture") != null:
					rec_banner_cache[banner_name] = res["texture"]
					banner_rect.texture = res["texture"]
		btn.add_child(banner_rect)

		var sc_name: String = str(scene_info.get("scenario", ""))
		btn.pressed.connect(func(): _start_scene_recollection(sc_name, heroine_idx))
	else:
		if tex_rec_locked != null:
			btn.texture_normal = tex_rec_locked
		else:
			btn.disabled = true
		btn.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN

	vbox.add_child(btn)

	var title_lbl := Label.new()
	if is_unlocked:
		title_lbl.text = "%s  [%s]" % [scene_info.get("title", ""), scene_info.get("scenario", "")]
		title_lbl.add_theme_color_override("font_color", Color("#abb2bf"))
	else:
		title_lbl.text = "🔒 未解锁 (剧情未完成)"
		title_lbl.add_theme_color_override("font_color", Color("#5c6370"))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 13)
	vbox.add_child(title_lbl)

	return vbox


func _start_scene_recollection(scenario_name: String, heroine_idx: int) -> void:
	if vm == null or not vm.functions.has("ScenarioLoop"):
		return

	is_recollect_mode = true
	recollect_return_tag = heroine_idx

	_exit_title_to_game()
	_close_appreciation_modal()

	if vm.functions.has("EnterRecollectMode"):
		vm.call_function_sync("EnterRecollectMode", [], 1000)

	if host != null:
		host.stop_bgm()
	if bg_rect != null:
		bg_rect.texture = null
	for b in bustup_rects:
		b.visible = false
		b.texture = null

	message_label.text = ""
	if speaker_label != null:
		speaker_label.text = ""
	if dialogue_box != null:
		dialogue_box.visible = true

	vm.ip = vm.functions["ScenarioLoop"]
	vm.pending_call_args = [scenario_name]
	vm.pending_return_ip = -1
	vm.call_stack.clear()
	vm.eval_stack.clear()
	vm.is_halted = false
	is_running = true
	print("[AdvPlayer] Started Scene Recollection: %s (Heroine tag %d)." % [scenario_name, heroine_idx])


func _end_scene_recollection() -> void:
	if not is_recollect_mode:
		return
	is_recollect_mode = false
	is_running = false

	if vm != null and vm.functions.has("LeaveRecollectMode"):
		vm.call_function_sync("LeaveRecollectMode", [], 1000)

	if host != null:
		host.stop_bgm()
	if bg_rect != null:
		bg_rect.texture = null
	for b in bustup_rects:
		b.visible = false
		b.texture = null

	_show_title_screen()
	_open_appreciation_modal()
	_switch_app_mode("rec")
	_switch_rec_heroine(recollect_return_tag)
	print("[AdvPlayer] Finished Scene Recollection, returned to Appreciation view.")


func _toggle_unlock_mode() -> void:
	app_full_unlock = not app_full_unlock
	if app_full_unlock:
		btn_unlock_toggle.text = "🔓 全解锁: 开"
		btn_unlock_toggle.remove_theme_color_override("font_color")
	else:
		btn_unlock_toggle.text = "🔒 全解锁: 关"
		btn_unlock_toggle.add_theme_color_override("font_color", Color("#e5c07b"))
	if app_mode == "cg":
		_populate_cg_grid()
	elif app_mode == "rec":
		_populate_rec_grid()


func _populate_cg_grid() -> void:
	if cg_grid == null:
		return

	# Remove existing cards
	for c in cg_grid.get_children():
		cg_grid.remove_child(c)
		c.queue_free()

	var scenes: Array = cg_catalog.get(app_cg_category, [])
	var per_page := 8
	var total_pages := maxi(1, int(ceil(float(scenes.size()) / float(per_page))))
	app_cg_page = clampi(app_cg_page, 1, total_pages)
	cg_page_label.text = "第 %d / %d 页 (共 %d 个场景)" % [app_cg_page, total_pages, scenes.size()]

	var start_idx := (app_cg_page - 1) * per_page
	var end_idx := mini(start_idx + per_page, scenes.size())

	for i in range(start_idx, end_idx):
		var scene: Dictionary = scenes[i]
		var card := _create_cg_card(scene)
		cg_grid.add_child(card)


func _create_cg_card(scene: Dictionary) -> Control:
	var container := VBoxContainer.new()
	container.custom_minimum_size = Vector2(170, 155)
	container.add_theme_constant_override("separation", 6)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(170, 120)
	btn.clip_contents = true

	var thumb_rect := TextureRect.new()
	thumb_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	thumb_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(thumb_rect)

	var first_file_ref: Dictionary = scene.get("first_file_ref", {})
	if first_file_ref.is_empty():
		var legacy_first_file: String = str(scene.get("first_file", ""))
		if not legacy_first_file.is_empty():
			first_file_ref = {"name": legacy_first_file, "archive_hint": "", "entry_index": -1}
	var first_file := str(first_file_ref.get("name", ""))
	var thumbnail_key := _cg_thumbnail_cache_key(first_file_ref)
	if not first_file.is_empty():
		var cached_thumbnail: Texture2D = cg_thumbnail_cache.get_texture(thumbnail_key)
		if cached_thumbnail != null:
			thumb_rect.texture = cached_thumbnail
		elif host != null:
			var img_res: Dictionary = host.load_image(first_file, str(first_file_ref.get("archive_hint", "")))
			if img_res.get("ok", false) and img_res.get("image") is Image:
				thumb_rect.texture = cg_thumbnail_cache.cache_image(thumbnail_key, img_res["image"])

	btn.pressed.connect(func(): _open_cg_fullscreen(scene))
	container.add_child(btn)

	var lbl := Label.new()
	lbl.text = "%s  (%d 差分)" % [scene.get("scene_id", ""), scene.get("files", []).size()]
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color("#abb2bf"))
	container.add_child(lbl)

	return container


func _prev_cg_page() -> void:
	var scenes: Array = cg_catalog.get(app_cg_category, [])
	var per_page := 8
	var total_pages := maxi(1, int(ceil(float(scenes.size()) / float(per_page))))
	if app_cg_page > 1:
		app_cg_page -= 1
		_populate_cg_grid()


func _next_cg_page() -> void:
	var scenes: Array = cg_catalog.get(app_cg_category, [])
	var per_page := 8
	var total_pages := maxi(1, int(ceil(float(scenes.size()) / float(per_page))))
	if app_cg_page < total_pages:
		app_cg_page += 1
		_populate_cg_grid()


func _open_cg_fullscreen(scene: Dictionary) -> void:
	fullscreen_current_variants = scene.get("file_refs", [])
	if fullscreen_current_variants.is_empty():
		for file_name: String in scene.get("files", []):
			fullscreen_current_variants.append({"name": file_name, "archive_hint": "", "entry_index": -1})
	fullscreen_variant_index = 0
	fullscreen_scene_id = scene.get("scene_id", "")
	fullscreen_cat_name = ""
	for cat in CG_CATEGORIES:
		if cat["id"] == app_cg_category:
			fullscreen_cat_name = cat["name"]
			break

	if fullscreen_current_variants.is_empty():
		return

	cg_fullscreen_panel.visible = true
	_display_fullscreen_variant()
	print("[AdvPlayer] Opened fullscreen CG: %s (%d variants)." % [fullscreen_scene_id, fullscreen_current_variants.size()])


func _close_cg_fullscreen() -> void:
	cg_fullscreen_panel.visible = false
	fullscreen_current_variants.clear()


func _display_fullscreen_variant() -> void:
	if fullscreen_current_variants.is_empty() or host == null:
		return
	var file_ref: Dictionary = fullscreen_current_variants[fullscreen_variant_index] if fullscreen_current_variants[fullscreen_variant_index] is Dictionary else {"name": str(fullscreen_current_variants[fullscreen_variant_index]), "archive_hint": "", "entry_index": -1}
	var file_name := str(file_ref.get("name", ""))
	var archive_hint := str(file_ref.get("archive_hint", ""))
	var img_res: Dictionary = host.load_image(file_name, archive_hint)
	if img_res.get("ok", false) and img_res.get("texture") != null:
		fullscreen_cg_rect.texture = img_res["texture"]

	fullscreen_info_label.text = "【%s】 %s  (%d / %d)   [%s]" % [
		fullscreen_cat_name,
		fullscreen_scene_id,
		fullscreen_variant_index + 1,
		fullscreen_current_variants.size(),
		file_name
	]


func _cg_thumbnail_cache_key(file_ref: Dictionary) -> String:
	var archive_hint := str(file_ref.get("archive_hint", "")).replace("\\", "/").to_lower()
	var entry_name := str(file_ref.get("name", "")).replace("\\", "/").simplify_path().to_lower()
	var entry_index := int(file_ref.get("entry_index", -1))
	return "%s::%s#%d" % [archive_hint, entry_name, entry_index]


func _next_cg_variant() -> void:
	if fullscreen_current_variants.size() <= 1:
		return
	fullscreen_variant_index = (fullscreen_variant_index + 1) % fullscreen_current_variants.size()
	_display_fullscreen_variant()


func _prev_cg_variant() -> void:
	if fullscreen_current_variants.size() <= 1:
		return
	fullscreen_variant_index = (fullscreen_variant_index - 1 + fullscreen_current_variants.size()) % fullscreen_current_variants.size()
	_display_fullscreen_variant()


# Jukebox Functions
func _play_jukebox_bgm(index: int) -> void:
	if index < 0 or index >= BGM_TRACKS.size() or host == null:
		return
	current_bgm_track_index = index
	var track: Dictionary = BGM_TRACKS[index]
	host.play_bgm(track["file"])
	bgm_play_btn.text = "⏸ 暂停"
	_update_jukebox_ui()
	print("[AdvPlayer] Jukebox playing: %s (%s)" % [track["title"], track["file"]])


func _toggle_jukebox_bgm() -> void:
	if bgm_player == null:
		return
	if current_bgm_track_index < 0:
		_play_jukebox_bgm(0)
		return

	if bgm_player.stream_paused:
		bgm_player.stream_paused = false
		bgm_play_btn.text = "⏸ 暂停"
	elif bgm_player.playing:
		bgm_player.stream_paused = true
		bgm_play_btn.text = "▶ 播放"
	else:
		_play_jukebox_bgm(current_bgm_track_index)


func _stop_jukebox_bgm() -> void:
	if host != null:
		host.stop_bgm()
	if bgm_player != null:
		bgm_player.stop()
	current_bgm_track_index = -1
	bgm_play_btn.text = "▶ 播放"
	_update_jukebox_ui()


func _prev_jukebox_bgm() -> void:
	var total := BGM_TRACKS.size()
	var idx := (current_bgm_track_index - 1 + total) % total
	_play_jukebox_bgm(idx)


func _next_jukebox_bgm() -> void:
	var total := BGM_TRACKS.size()
	var idx := (current_bgm_track_index + 1) % total
	_play_jukebox_bgm(idx)


func _on_bgm_vol_changed(value: float) -> void:
	if bgm_vol_label != null:
		bgm_vol_label.text = "%d%%" % int(value)
	if bgm_player != null:
		if value <= 0.0:
			bgm_player.volume_db = -80.0
		else:
			bgm_player.volume_db = linear_to_db(value / 100.0)


func _update_jukebox_ui() -> void:
	for i in range(bgm_track_buttons.size()):
		var btn: Button = bgm_track_buttons[i]
		if i == current_bgm_track_index:
			btn.add_theme_color_override("font_color", Color("#98c379"))
		else:
			btn.remove_theme_color_override("font_color")

	if current_bgm_track_index >= 0 and current_bgm_track_index < BGM_TRACKS.size():
		var track: Dictionary = BGM_TRACKS[current_bgm_track_index]
		bgm_now_playing_label.text = "正在播放: No.%02d  %s\n%s" % [
			current_bgm_track_index + 1,
			track["title"],
			track["sub"]
		]
	else:
		bgm_now_playing_label.text = "选择曲目以开始播放\nSelect a track to play"
