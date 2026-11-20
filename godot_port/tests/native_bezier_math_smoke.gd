extends SceneTree

const Host = preload("res://scripts/csx_host.gd")
const VM = preload("res://scripts/csx_vm.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game_dir := OS.get_cmdline_user_args()[0]
	var vm := VM.new(Host.new(game_dir))
	if not vm.load_csx(game_dir.path_join("system/yosuga.csx")).get("ok", false):
		_fail("Cannot load original script")
		return
	var curve = vm.create_object("Bezier2D")
	var linear: Dictionary = vm.call_function_sync("Bezier2D::SetLinear", [curve, 0.95, 0.95, 1.0, 1.0])
	var acceleration: Dictionary = vm.call_function_sync("Bezier2D::SetAcceleration", [curve, 3.0, 0.0])
	if not linear.get("ok", false) or not acceleration.get("ok", false):
		_fail("Original curve functions failed")
		return
	var points: Array = curve.get_field("parent")
	for point in points:
		if not point is VM.CsxInstance or point.type_name != "Vector2D":
			_fail("Original acceleration must preserve the four vector control points")
			return
	var expected := [0.95, 1.0, 1.0, 1.0]
	for index in range(4):
		if not is_equal_approx(float(points[index].get_field("x")), expected[index]):
			_fail("Original acceleration must generate the expected cubic control points")
			return
	var sprite := Host.HostSprite.new(1, vm.host)
	vm._dispatch_sprite_method(sprite, "SetBezierCurve", [null, null, curve])
	sprite.begin_activation(300)
	if not sprite.magnification.is_equal_approx(Vector2(0.95, 0.95)):
		_fail("Scale must begin at the original curve's first point")
		return
	vm.host.advance_sprite_animations(0.15)
	if not sprite.magnification.is_equal_approx(Vector2(0.99375, 0.99375)):
		_fail("Scale must follow the original cubic curve at its midpoint")
		return
	vm.host.advance_sprite_animations(0.15)
	if not sprite.magnification.is_equal_approx(Vector2.ONE):
		_fail("Scale must reach the original endpoint")
		return
	print("PASS Original Bezier vector arithmetic and scale animation")
	quit(0)


func _fail(message: String) -> void:
	printerr("FAIL ", message)
	quit(1)
