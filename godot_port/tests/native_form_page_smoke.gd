extends "res://tests/smoke_test_base.gd"

const CsxHostClass = preload("res://scripts/csx_host.gd")
const CsxVMReader = preload("res://scripts/csx_vm.gd")
const TestSupport = preload("res://tests/test_support.gd")

const EXPECTED_HASHES := {
	"system/yosuga.csx": "157be9eb39cdc2d3cb654096340ca686f4ef48ac7fd7a6255673ba5f0c79afb6",
	"system/title.noa": "b74f4c62f2dd208393552f3cb9b4287af32121c665c1a27ae57d59b1f713fbbc",
	"system/frame.noa": "b6f5ad7bd4067ad65ab764faaf76fb9442e0d01ab5c88807ecb7c6cddf5cf875",
	"system/option.noa": "054d2f6b7583f09f9b728d38a89da7fa0ef5a16cc334dd8fb576dbdffd768310",
	"data1.noa": "d324c49ed4a80108f68aabaf7a202ec31d1b8f64075918f136944e72ec919831",
	"sound.noa": "166b22277d5398b452241a7502f5e6262de8d28a52d113f3c29673cc7d2a4005",
}

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("FAIL Pass game directory after --")
		quit(1)
		return

	var game_dir: String = args[0]
	print("[1/5] Verifying initial pristine state of game archives ...")
	for rel_path in EXPECTED_HASHES.keys():
		var full_path := game_dir.path_join(rel_path)
		var h := FileAccess.get_sha256(full_path)
		expect(h == EXPECTED_HASHES[rel_path], "Hash mismatch for %s before test" % rel_path)
	print("  All archive hashes match expected baseline.")

	print("[2/5] Testing system.inf XML skin parsing from NOA archives ...")
	var host := CsxHostClass.new(game_dir)
	var test_save_dir := TestSupport.new_save_dir("native_form_page")
	host.save_dir = test_save_dir
	var res_mgr := CsxHostClass.HostResourceManager.new(host)

	# Test title.noa skin
	var ret_title := res_mgr.load_resource("title.noa")
	expect(ret_title == 1, "load_resource('title.noa') must succeed")
	expect(res_mgr.skin_pages.has("ID_PAGE_MENU_FULL"), "title.noa must define ID_PAGE_MENU_FULL")
	expect(res_mgr.skin_pages.has("ID_PAGE_MENU"), "title.noa must define ID_PAGE_MENU")
	expect(res_mgr.skin_styles.has("ID_BTN_TITLE_START"), "title.noa must define ID_BTN_TITLE_START style")
	expect(res_mgr.skin_resources.has("ID_FRM_0621"), "title.noa must map ID_FRM_0621 resource")
	print("  title.noa skin parsed: %d pages, %d styles, %d resources" % [
		res_mgr.skin_pages.size(), res_mgr.skin_styles.size(), res_mgr.skin_resources.size()
	])

	# Test frame.noa skin
	var frame_mgr := CsxHostClass.HostResourceManager.new(host)
	var ret_frame := frame_mgr.load_resource("frame.noa")
	expect(ret_frame == 1, "load_resource('frame.noa') must succeed")
	expect(frame_mgr.skin_pages.has("ID_PAGE_ADV_MENU"), "frame.noa must define ID_PAGE_ADV_MENU")
	expect(frame_mgr.skin_styles.has("ID_BTN_ADV_SAVE"), "frame.noa must define ID_BTN_ADV_SAVE style")
	print("  frame.noa skin parsed: %d pages, %d styles, %d resources" % [
		frame_mgr.skin_pages.size(), frame_mgr.skin_styles.size(), frame_mgr.skin_resources.size()
	])

	print("[3/5] Testing CreateFormPage and Button Sub-atlas Extraction ...")
	var page_spr := CsxHostClass.HostSprite.new(10, host)
	var form_ret := res_mgr.create_form_page(page_spr, "ID_PAGE_MENU_FULL")
	expect(form_ret == 1, "create_form_page('ID_PAGE_MENU_FULL') must succeed")
	expect(page_spr.children.size() == 5, "ID_PAGE_MENU_FULL must instantiate 5 button child sprites")

	var expected_buttons := ["ID_START", "ID_CONTINUE", "ID_CONFIG", "ID_APPRECIATION", "ID_EXITGAME"]
	for i in range(expected_buttons.size()):
		var child = page_spr.children[i]
		var expected_id: String = expected_buttons[i]
		expect(child.btn_id == expected_id, "Child %d expected %s, got %s" % [i, expected_id, child.btn_id])
		expect(child.is_button, "Child %s must have is_button == true" % expected_id)
		expect(child.btn_normal_tex != null, "Child %s must have valid normal texture" % expected_id)
		expect(child.btn_focus_tex != null, "Child %s must have valid focus texture" % expected_id)
		expect(child.size == Vector2i(127, 24), "Child %s size must be 127x24, got %s" % [expected_id, child.size])
		# Verify button state changes
		child.set_button_state("focus")
		expect(child.texture == child.btn_focus_tex, "Child %s texture must switch to focus" % expected_id)
		child.set_button_state("normal")
		expect(child.texture == child.btn_normal_tex, "Child %s texture must switch to normal" % expected_id)
		print("  Button %s: size=%s, pos=%s, sub-atlas verified" % [expected_id, child.size, child.position])

	var select_page := CsxHostClass.HostSprite.new(11, host)
	expect(frame_mgr.create_form_page(select_page, "ID_PAGE_ADVSELECT") == 1, "The native choice form must load")
	var text_sprite: CsxHostClass.HostSprite = null
	for child in select_page.children:
		if child.fields.get("form_item_id") == "ID_TEXT":
			text_sprite = child
			break
	expect(text_sprite != null, "The choice form must create its original static text sprite")
	if text_sprite != null:
		expect(text_sprite.position == Vector2i(6, 8) and text_sprite.size == Vector2i(565, 36), "Static text must keep its original bounds")
		expect(text_sprite.message_style.get("id") == "ID_FONT_SELECT", "Static text must use its declared style")
		expect(text_sprite.text_content == frame_mgr.skin_pages["ID_PAGE_ADVSELECT"]["static_texts"][0]["text"], "Static text must use its declared content")
		var player = load("res://scenes/adv_player.tscn").instantiate()
		var label := Label.new()
		root.add_child(label)
		player._apply_native_text_style(label, text_sprite.message_style)
		expect(label.get_theme_font_size("font_size") == int(text_sprite.message_style["font"]["size"]), "The native canvas must use the declared font size")
		expect(label.get_theme_constant("shadow_offset_y") == int(text_sprite.message_style["shadow"]["y"]), "The native canvas must use the declared shadow offset")
		label.free()
		player.free()

	print("[4/5] Testing VM execution of native Title() with Command Injection ...")
	var vm := CsxVMReader.new(host)
	var load_res := vm.load_csx(game_dir.path_join("system/yosuga.csx"))
	expect(load_res.get("ok", false), "VM must load yosuga.csx")
	vm.execute_prologues()
	vm.call_function_sync("Initialize", [], 500_000)

	var title_addr: int = vm.functions["Title"]
	vm.ip = title_addr
	vm.pending_call_args = []
	vm.pending_return_ip = -1
	vm.call_stack.clear()
	vm.eval_stack.clear()
	vm.is_halted = false

	# Step until GetCommand loop (approx step 4550)
	var steps := 0
	while steps < 4560 and not vm.is_halted:
		if not vm.step():
			break
		steps += 1

	var screen_win = vm.data_vars[4]["value"] as CsxHostClass.HostWindow
	expect(screen_win != null, "data_vars[4] must be HostWindow")
	var command := CsxVMReader.CsxInstance.new("WndSpriteCmd")
	host.push_command("ID_CONFIG")
	expect(screen_win.get_command(command) == 1, "GetCommand must dequeue a queued native button click")
	expect(command.get_field("strID") == "ID_CONFIG" and command.get_field("strFullID") == "ID_CONFIG", "A native button click must preserve its item IDs")
	expect(command.get_field("nNotification") == 0 and command.get_field("nParameter") == 0, "Native QueueCommand defaults must match Entis notification and parameter defaults")
	host.push_command("ID_VOL_BGM", "ID_VOL_BGM", 4, 128)
	expect(screen_win.get_command(command) == 1, "GetCommand must dequeue a native scrollbar tracking event")
	expect(command.get_field("nNotification") == 4 and command.get_field("nParameter") == 128, "Native scrollbar tracking must preserve ncTracking and its position")
	expect(screen_win.root_sprites.size() == 4, "HostWindow must contain 4 root sprites in Title mode")
	var title_menu: CsxHostClass.HostSprite = screen_win.root_sprites[2]
	var title_commands := ["ID_START", "ID_CONTINUE", "ID_CONFIG", "ID_EXITGAME"]
	expect(title_menu.children.size() == title_commands.size(), "ID_PAGE_MENU must contain its 4 original commands")
	for i in range(title_commands.size()):
		expect(title_menu.children[i].btn_id == title_commands[i], "Title command %d must be %s" % [i, title_commands[i]])
	expect(screen_win.root_sprites[3].text_content == "Ver 1.01", "Version sprite must have 'Ver 1.01'")
	print("  Title() sprite hierarchy verified: 4 root sprites, 4 original menu commands, version string 'Ver 1.01'.")

	# Inject ID_START into host command queue
	host.push_command("ID_START")
	while steps < 6000 and not vm.is_halted:
		host.advance_sprite_animations(1.0 / 60.0)
		if not vm.step():
			break
		steps += 1

	expect(vm.is_halted, "Title() must halt/return after ID_START")
	expect(vm.last_return_value == 1, "Title() return value must be 1 for ID_START (New Game)")
	print("  Title() returned 1 (New Game) after processing ID_START event.")
	var delete_result := res_mgr.delete_contents()
	expect(delete_result == 0, "DeleteContents must return the Entis SDK default integer result")
	expect(res_mgr.loaded_archive_name.is_empty() and res_mgr.resource_cache.is_empty(), "DeleteContents must release the loaded resource map")
	expect(res_mgr.skin_resources.is_empty() and res_mgr.skin_styles.is_empty() and res_mgr.skin_pages.is_empty(), "DeleteContents must clear form skin resources, styles, and pages")

	print("[5/5] Verifying final archive pristine status ...")
	for rel_path in EXPECTED_HASHES.keys():
		var full_path := game_dir.path_join(rel_path)
		var h := FileAccess.get_sha256(full_path)
		expect(h == EXPECTED_HASHES[rel_path], "Hash mismatch for %s after test" % rel_path)
	print("  Original game archives remain 100% pristine and unmodified.")

	TestSupport.remove_test_saves(test_save_dir)
	finish_success("PASS Native Form Page and EntisGLS Skin Smoke Test!")
