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

	var rotated := Host.HostSprite.new(5, host)
	rotated.is_visible = true
	rotated.position = Vector2i(200, 200)
	rotated.rev_center = Vector2i(50, 10)
	rotated.size = Vector2i(100, 20)
	rotated.rotation_degrees = 45.0
	_expect(rotated.is_hit_at(228, 228), "Rotated sprite hit testing must accept a point inside its rendered quad")
	_expect(not rotated.is_hit_at(245, 200), "Rotated sprite hit testing must reject an unrotated-rectangle false positive")

	var focus_window := Host.HostWindow.new(host)
	var selected := Host.HostSprite.new(6, host)
	selected.btn_id = "ID_SELECTED"
	selected.is_button = true
	selected.is_visible = true
	selected.size = Vector2i(100, 40)
	selected.set_button_state("pushed")
	focus_window.add_sprite(0, selected)
	_expect(vm._dispatch_sprite_method(selected, "IsButtonChecked", ["ID_SELECTED"]) == -1, "A pushed native button must be reported as checked")
	focus_window.focus_sprite(selected)
	_expect(selected.has_window_focus and selected.btn_state == "pushed", "Applying window focus must not overwrite a selected button's pushed state")
	_expect(vm._dispatch_sprite_method(selected, "IsButtonChecked", ["ID_SELECTED"]) == -1, "IsButtonChecked must remain true after a selected button receives focus")
	focus_window.set_focus("")
	_expect(not selected.has_window_focus and selected.btn_state == "pushed", "Clearing focus must preserve the selected button state")
	_expect(vm._dispatch_sprite_method(selected, "CheckButton", ["ID_SELECTED", 0]) == 0, "CheckButton must clear persistent selection")
	_expect(vm._dispatch_sprite_method(selected, "CheckButton", ["ID_SELECTED", 1]) == 0, "CheckButton must set persistent selection")
	focus_window.focus_sprite(selected)
	_expect(vm._dispatch_sprite_method(selected, "IsButtonChecked", ["ID_SELECTED"]) == -1, "Persistent CheckButton selection must survive focus changes")

	var message := Host.HostSprite.new(3, host)
	vm._dispatch_sprite_method(message, "CreateMessage", [800, 152])
	vm._dispatch_sprite_method(message, "MoveCursorPos", [37, 42])
	var point := VM.CsxInstance.new("Point")
	vm._dispatch_sprite_method(message, "GetCursorPos", [point])
	_expect(int(point.get_field("x")) == 37 and int(point.get_field("y")) == 42, "Message cursor coordinates must round trip through the native API")
	_expect(vm._dispatch_sprite_method(message, "SetFontBordering", [-1]) == 0 and message.font_bordering, "SetFontBordering must update native message state")

	var window := Host.HostWindow.new(host)
	_expect(vm._dispatch_window_method(window, "Refresh", []) == 0, "Window.Refresh must complete as a native no-op on the retained Godot scene")
	_expect(vm._dispatch_window_method(window, "ChangeDisplaySize", [800, 600]) == 0 and window.viewport_size == Vector2i(800, 600), "Native ChangeDisplaySize must update the CSX display dimensions")
	_expect(vm._dispatch_window_method(window, "ChangeCooperationLevel", [3]) == 0, "Native fullscreen cooperation level must be accepted")
	_expect(vm._dispatch_window_method(window, "ChangeDisplaySize", [1024, 600]) == 0 and window.viewport_size == Vector2i(1024, 600), "Native ChangeDisplaySize must accept the windowed dimensions")
	_expect(vm._dispatch_window_method(window, "ChangeCooperationLevel", [0]) == 0, "Native windowed cooperation level must be accepted")
	_expect(host.last_error.is_empty(), "Implemented native methods must not set an unsupported-capability error")
	print("PASS native sprite methods and native display size/cooperation calls")
	quit(0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	printerr("FAIL ", message)
	quit(1)
