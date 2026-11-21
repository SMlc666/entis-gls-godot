extends SceneTree

const Host = preload("res://scripts/csx_host.gd")
const VM = preload("res://scripts/csx_vm.gd")


func _initialize() -> void:
	var host := Host.new("")
	var vm := VM.new(host)
	var parent := Host.HostSprite.new(1, host)
	var button := Host.HostSprite.new(2, host)
	button.btn_id = "ID_TEST_BUTTON"
	button.is_button = true
	button.is_visible = true
	button.size = Vector2i(100, 40)
	parent.add_sprite(0, button)
	_expect(vm._dispatch_sprite_method(parent, "Enable", [0, "ID_TEST_BUTTON"]) == 0, "Enable must return the native success value")
	_expect(not button.is_enabled and vm._dispatch_sprite_method(parent, "IsEnabled", ["ID_TEST_BUTTON"]) == 0, "Enable(false) and IsEnabled must agree for a child form item")
	_expect(not button.is_hit_at(10, 10), "A disabled child sprite must not receive hit testing")
	parent.detach_sprite(button)
	button = Host.HostSprite.new(4, host)
	button.btn_id = "ID_TEST_BUTTON"
	button.is_button = true
	parent.add_sprite(0, button)
	_expect(not button.is_enabled, "A disabled form-item state must survive child recreation")
	vm._dispatch_sprite_method(parent, "Enable", [-1, "ID_TEST_BUTTON"])
	_expect(button.is_enabled and vm._dispatch_sprite_method(parent, "IsEnabled", ["ID_TEST_BUTTON"]) == -1, "Enable(true) must restore child interaction")

	var message := Host.HostSprite.new(3, host)
	vm._dispatch_sprite_method(message, "CreateMessage", [800, 152])
	vm._dispatch_sprite_method(message, "MoveCursorPos", [37, 42])
	var point := VM.CsxInstance.new("Point")
	vm._dispatch_sprite_method(message, "GetCursorPos", [point])
	_expect(int(point.get_field("x")) == 37 and int(point.get_field("y")) == 42, "Message cursor coordinates must round trip through the native API")
	_expect(vm._dispatch_sprite_method(message, "SetFontBordering", [-1]) == 0 and message.font_bordering, "SetFontBordering must update native message state")

	var window := Host.HostWindow.new(host)
	_expect(vm._dispatch_window_method(window, "Refresh", []) == 0, "Window.Refresh must complete as a native no-op on the retained Godot scene")
	_expect(host.last_error.is_empty(), "Implemented native methods must not set an unsupported-capability error")
	print("PASS native sprite Enable, message cursor/border, and window Refresh methods")
	quit(0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	printerr("FAIL ", message)
	quit(1)
