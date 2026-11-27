extends SceneTree

const CsxVMReader = preload("res://scripts/csx_vm.gd")
const CsxHostClass = preload("res://scripts/csx_host.gd")

var _host: Variant = null
var _vm: Variant = null
var _bgm_player: AudioStreamPlayer = null
var _resources: Array = []
var _cleaned := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		await _fail("Pass the original game directory after --")
		return
	var host := CsxHostClass.new(args[0])
	_host = host
	var bgm_player := AudioStreamPlayer.new()
	_bgm_player = bgm_player
	root.add_child(bgm_player)
	host.bgm_player = bgm_player
	var vm := CsxVMReader.new(host)
	_vm = vm
	var previous_host_error := "preserve this earlier diagnostic"
	host.last_error = previous_host_error
	if host.is_file_existing(".mio"):
		await _fail("An empty optional voice name must not make the .mio probe exist")
		return
	if host.last_error != previous_host_error:
		await _fail("A normal missing-file existence query must not overwrite an earlier host diagnostic")
		return
	var missing_file := CsxHostClass.HostFile.new(host, vm)
	if missing_file.is_existing(".mio") != 0 or host.last_error != previous_host_error:
		await _fail("HostFile.IsExisting must return false for the optional .mio probe without changing host error state")
		return
	var is_existing_result: Dictionary = host.call_host_function("IsExisting", [".mio"], vm)
	if not is_existing_result.get("handled", false) or int(is_existing_result.get("result", -1)) != 0 or host.last_error != previous_host_error:
		await _fail("CSX File::IsExisting must report the missing optional .mio path as false without changing host error state")
		return
	if not host.is_file_existing("BGM07.mio") or host.last_error != previous_host_error:
		await _fail("A successful VFS existence query must preserve the previous host diagnostic")
		return
	host.last_error = ""
	var resource := CsxHostClass.HostResource.new("", "", -1, 0, 0, host)
	_resources.append(resource)
	if vm._dispatch_resource_method(resource, "LoadSound", ["BGM07.mio", -1]) != 0:
		await _fail("Resource.LoadSound must return Entis Error success code 0")
		return
	if resource.audio_stream == null:
		await _fail("The original BGM resource must be decoded")
		return
	if vm._dispatch_resource_method(resource, "Play", [-1, CsxHostClass.AUDIO_PLAY_TYPE_MUSIC]) != 0:
		await _fail("Resource.Play must return Entis Error success code 0")
		return
	if vm._dispatch_resource_method(resource, "IsPlaying", []) != -1:
		await _fail("Resource.IsPlaying must return Entis Boolean true as -1")
		return
	if vm._dispatch_resource_method(resource, "SetVolume", [0.5, 0.5]) != 0:
		await _fail("Resource.SetVolume must return Entis Error success code 0")
		return
	var volume_values := {"left": 0.0, "right": 0.0}
	var left := CsxVMReader.CsxRef.new(volume_values, "left")
	var right := CsxVMReader.CsxRef.new(volume_values, "right")
	if vm._dispatch_resource_method(resource, "GetVolume", [left, right]) != 0:
		await _fail("Resource.GetVolume must return Entis Error success code 0")
		return
	if not is_equal_approx(float(volume_values.left), 0.5) or not is_equal_approx(float(volume_values.right), 0.5):
		await _fail("Resource.GetVolume must write both output values")
		return
	if vm._dispatch_resource_method(resource, "Stop", []) != 0:
		await _fail("Resource.Stop must return Entis Error success code 0")
		return
	var unavailable := CsxHostClass.HostResource.new()
	_resources.append(unavailable)
	if vm._dispatch_resource_method(unavailable, "LoadSound", ["missing.mio", -1]) != 1:
		await _fail("Resource.LoadSound must return Entis Error failure code 1")
		return
	await _cleanup()
	print("PASS Resource audio status-code smoke on original BGM07.mio (self-runtime; not SDK differential)")
	quit(0)


func _cleanup() -> void:
	if _cleaned:
		return
	_cleaned = true
	for resource: Variant in _resources:
		if resource is CsxHostClass.HostResource:
			resource.release()
	_resources.clear()
	if _vm != null:
		_vm.shutdown_runtime()
	if _host != null:
		_host.shutdown_runtime()
	if _bgm_player != null and is_instance_valid(_bgm_player):
		_bgm_player.stop()
		_bgm_player.stream = null
		if _bgm_player.get_parent() != null:
			_bgm_player.get_parent().remove_child(_bgm_player)
		_bgm_player.free()
	_bgm_player = null
	_vm = null
	_host = null
	await process_frame
	await create_timer(0.25).timeout


func _fail(message: String) -> void:
	await _cleanup()
	printerr("FAIL ", message)
	quit(1)
