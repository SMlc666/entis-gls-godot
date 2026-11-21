extends SceneTree

const CsxVMReader = preload("res://scripts/csx_vm.gd")
const CsxHostClass = preload("res://scripts/csx_host.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		_fail("Pass the original game directory after --")
		return
	var host := CsxHostClass.new(args[0])
	var bgm_player := AudioStreamPlayer.new()
	root.add_child(bgm_player)
	host.bgm_player = bgm_player
	var vm := CsxVMReader.new(host)
	var resource := CsxHostClass.HostResource.new("", "", -1, 0, 0, host)
	if vm._dispatch_resource_method(resource, "LoadSound", ["BGM07.mio", -1]) != 0:
		_fail("Resource.LoadSound must return Entis Error success code 0")
		return
	if resource.audio_stream == null:
		_fail("The original BGM resource must be decoded")
		return
	if vm._dispatch_resource_method(resource, "Play", [-1, CsxHostClass.AUDIO_PLAY_TYPE_MUSIC]) != 0:
		_fail("Resource.Play must return Entis Error success code 0")
		return
	if vm._dispatch_resource_method(resource, "IsPlaying", []) != -1:
		_fail("Resource.IsPlaying must return Entis Boolean true as -1")
		return
	if vm._dispatch_resource_method(resource, "SetVolume", [0.5, 0.5]) != 0:
		_fail("Resource.SetVolume must return Entis Error success code 0")
		return
	var volume_values := {"left": 0.0, "right": 0.0}
	var left := CsxVMReader.CsxRef.new(volume_values, "left")
	var right := CsxVMReader.CsxRef.new(volume_values, "right")
	if vm._dispatch_resource_method(resource, "GetVolume", [left, right]) != 0:
		_fail("Resource.GetVolume must return Entis Error success code 0")
		return
	if not is_equal_approx(float(volume_values.left), 0.5) or not is_equal_approx(float(volume_values.right), 0.5):
		_fail("Resource.GetVolume must write both output values")
		return
	if vm._dispatch_resource_method(resource, "Stop", []) != 0:
		_fail("Resource.Stop must return Entis Error success code 0")
		return
	var unavailable := CsxHostClass.HostResource.new()
	if vm._dispatch_resource_method(unavailable, "LoadSound", ["missing.mio", -1]) != 1:
		_fail("Resource.LoadSound must return Entis Error failure code 1")
		return
	print("PASS Resource audio API Error codes match Entis SDK on original BGM07.mio")
	quit(0)


func _fail(message: String) -> void:
	printerr("FAIL ", message)
	quit(1)
