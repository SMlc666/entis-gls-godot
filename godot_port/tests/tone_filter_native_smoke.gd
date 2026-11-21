extends SceneTree

const CsxVMReader = preload("res://scripts/csx_vm.gd")
const CsxHostClass = preload("res://scripts/csx_host.gd")


func _initialize() -> void:
	var vm := CsxVMReader.new(CsxHostClass.new(""))
	var source := CsxVMReader.CsxInstance.new("ToneFilter")
	var target := CsxVMReader.CsxInstance.new("ToneFilter")
	var output := CsxVMReader.CsxInstance.new("ToneFilter")
	var source_filter := vm._tone_filter_for_value(source)
	var target_filter := vm._tone_filter_for_value(target)
	if source_filter == null or target_filter == null:
		_fail("ToneFilter CsxInstance values must retain a native host bridge")
		return
	if vm._dispatch_tone_filter_method(source_filter, "SetGeneralTone", [64, 0, 0, 0, 0, 0, 0, 0]) != 0:
		_fail("SetGeneralTone failed for source filter")
		return
	if vm._dispatch_tone_filter_method(target_filter, "SetGeneralTone", [-64, 0, 0, 0, 0, 0, 0, 0]) != 0:
		_fail("SetGeneralTone failed for target filter")
		return
	if vm._dispatch_tone_filter_method(vm._tone_filter_for_value(output), "MorphingFilter", [source, target, 0]) != 0:
		_fail("MorphingFilter failed for CsxInstance arguments")
		return
	if output.native_tone_filter.red_table != source.native_tone_filter.red_table:
		_fail("MorphingFilter degree 0 must copy the source LUT")
		return
	if vm._dispatch_tone_filter_method(vm._tone_filter_for_value(output), "MorphingFilter", [source, target, 256]) != 0:
		_fail("MorphingFilter degree 256 failed")
		return
	if output.native_tone_filter.red_table != target.native_tone_filter.red_table:
		_fail("MorphingFilter degree 256 must copy the target LUT")
		return
	print("PASS native ToneFilter CsxInstance bridge and morph endpoints")
	quit(0)


func _fail(message: String) -> void:
	printerr("FAIL ", message)
	quit(1)
