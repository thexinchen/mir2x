extends "res://tests/network_runtime_config_persistence_smoke.gd"


func _write_from_actual_panel() -> void:
	var check := _lock_checkbox()
	if check.button_pressed:
		_fail("new lock setting should initially be disabled", 21)
		return
	check.button_pressed = true
	if not _main.call("_magic_target_lock_enabled"):
		_fail("actual setting did not enable lock logic", 22)
		return
	await get_tree().create_timer(1.0).timeout
	_pass("lock writer")


func _verify_fresh_login() -> void:
	var expected := not OS.has_environment("MIR3_LOCK_EXPECT_OFF")
	var check := _lock_checkbox()
	if check.button_pressed != expected or _main.call("_magic_target_lock_enabled") != expected:
		_fail("fresh login did not restore target lock setting", 23)
		return
	if expected:
		check.button_pressed = false
		await get_tree().create_timer(1.0).timeout
	_pass("lock restored" if expected else "lock cleanup verified")


func _lock_checkbox() -> Button:
	var panel := _main.call("_ensure_extra_panel", RUNTIME_PANEL_PATH) as Control
	panel.show()
	panel.call("_select_main_page", 3)
	return panel.get_node("SystemPage/Config49") as Button
