extends SceneTree

const Host = preload("res://scripts/csx_host.gd")
const TestSupport = preload("res://tests/test_support.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		_fail("Pass game directory after --")
		return
	var game_dir: String = args[0]
	var csx_path := game_dir.path_join("system/yosuga.csx")
	var noa_path := game_dir.path_join("data1.noa")
	var csx_hash := FileAccess.get_sha256(csx_path)
	var noa_hash := FileAccess.get_sha256(noa_path)
	var scene := load("res://scenes/adv_player.tscn") as PackedScene
	if scene == null:
		_fail("AdvPlayer scene must load")
		return
	var player = scene.instantiate()
	player.game_dir = game_dir
	player.start_in_title = false
	var save_dir: String = TestSupport.configure_player_saves(player, "native_adv_screen_sprite")
	root.add_child(player)
	var frames := 0
	while not player.is_initialized and frames < 300:
		await process_frame
		frames += 1
	if not player.is_initialized or not TestSupport.uses_isolated_saves(player.host, save_dir):
		_fail("Original AdvScreen must initialize with isolated test saves")
		return
	var adv = player.vm.globals_by_name.get("adv", null)
	if adv == null or not adv.has_method("get_field"):
		_fail("Original AdvScreen instance must exist")
		return
	var sprite: Host.HostSprite = adv.get_field("sprCg")
	frames = 0
	while (sprite == null or not sprite.is_visible or sprite.texture == null) and frames < 600:
		await process_frame
		frames += 1
	if sprite == null or not sprite.is_visible or sprite.texture == null:
		_fail("Original opening scenario must load its visible CG Sprite")
		return
	player._sync_adv_cg_sprite(sprite)
	if not player.adv_cg_layer.visible or player.bg_rect.visible:
		_fail("Visible original CG Sprite must replace the stretched background fallback")
		return
	if player.adv_cg_rect.texture != sprite.texture:
		_fail("Native CG renderer must use the original Sprite texture")
		return
	if player.adv_cg_rect.position != Vector2(sprite.position - sprite.rev_center):
		_fail("Native CG renderer must preserve original Sprite position and reverse center")
		return
	if player.adv_cg_rect.size != Vector2(sprite.get_render_size()) or player.adv_cg_rect.scale != sprite.magnification:
		_fail("Native CG renderer must preserve original dimensions and magnification")
		return
	if sprite.filename != "B27A.eri" or sprite.size != Vector2i(800, 1200) or sprite.position != Vector2i(0, -300):
		_fail("The startup CG's original 800x1200 vertical-pan state must reach the renderer")
		return
	if FileAccess.get_sha256(csx_path) != csx_hash or FileAccess.get_sha256(noa_path) != noa_hash:
		_fail("Original CSX and NOA files must remain unchanged")
		return
	print("PASS original AdvScreen B27A CG position, scale, clip and texture mapping")
	player.queue_free()
	await process_frame
	quit(0)


func _fail(message: String) -> void:
	printerr("FAIL ", message)
	quit(1)
