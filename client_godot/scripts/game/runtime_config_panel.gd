extends "res://scripts/game/closable_panel.gd"

const CHECK_TEXTURE := preload("res://assets/ui/game/runtime_config/00000480.png")
const SLIDER_TRACK := preload("res://assets/ui/game/runtime_config/00000460.png")
const SLIDER_FILL := preload("res://assets/ui/game/runtime_config/00000470.png")
const SLIDER_KNOB := preload("res://assets/ui/game/runtime_config/00000081.png")

const WINDOW_SIZES := [
	Vector2i(800, 600),
	Vector2i(960, 600),
	Vector2i(1024, 768),
	Vector2i(1280, 720),
	Vector2i(1280, 768),
	Vector2i(1280, 800),
]
const SOCIAL_CONFIGS := [
	[9, "允许私聊"],
	[10, "允许白字聊天"],
	[11, "允许地图聊天"],
	[12, "允许行会聊天"],
	[13, "允许全服聊天"],
	[14, "允许加入队伍"],
	[15, "允许加入行会"],
	[16, "允许回生术"],
	[17, "允许天地合一"],
	[18, "允许交易"],
	[19, "允许添加好友"],
	[20, "允许行会召唤"],
	[21, "允许行会杀人提示"],
	[22, "允许拜师"],
	[23, "允许好友上线提示"],
]
const GAME_CONFIGS := [
	[24, "强制攻击"],
	[25, "显示体力变化"],
	[26, "满血不显血"],
	[27, "显示血条"],
	[28, "数字显血"],
	[29, "综合数字显示"],
	[30, "标记攻击目标"],
	[31, "单击解除锁定"],
	[32, "显示BUFF图标"],
	[33, "显示BUFF计时"],
	[34, "显示角色名字"],
	[35, "关闭组队血条"],
	[36, "队友染色"],
	[37, "显示队友位置"],
]
const AUXILIARY_CONFIGS := [
	[38, "持续盾"],
	[39, "持续移花接木"],
	[40, "持续金刚"],
	[41, "持续破血"],
	[42, "持续铁布衫"],
]
const PROTECTION_CONFIGS := [
	[43, "自动喝红"],
	[44, "保持满血"],
	[45, "自动喝蓝"],
	[46, "保持满蓝"],
]

var _state: Node
var _updating := false
var _main_page := 0
var _system_tab := 0
var _social_tab := 0
var _game_tab := 0
var _controls: Dictionary = {}
var _sliders: Dictionary = {}
var _friend_radios: Array[Button] = []
var _preview_font_index := 0
var _preview_font_size := 12
var _preview_lines: Array[LineEdit] = []
var _preview_fonts: Array[Font] = []


# C++ closes this board on Escape but returns false, so later boards and the
# world-centering fallback still receive the same key event.
func close_for_escape() -> bool:
	hide()
	return false


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed:
		return
	if event.keycode == KEY_ESCAPE:
		super._unhandled_key_input(event)
		return
	# ImMainUI::processHUDEvent() runs before ImRuntimeConfigBoard. Preserve the
	# two HUD key routes it consumes before this board sees the event.
	if event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		return
	if event.keycode >= KEY_1 and event.keycode <= KEY_6:
		var main := get_parent()
		var quick_bar: Control = null
		if main != null:
			quick_bar = main.get_node_or_null("%QuickBar") as Control
		if quick_bar != null and quick_bar.visible:
			return
	get_viewport().set_input_as_handled()


func _ready() -> void:
	super._ready()
	_state = get_node("/root/GameState")
	_state.state_changed.connect(_refresh_controls)
	var menu_buttons: Array[Button] = [
		$Menu/System,
		$Menu/Social,
		$Menu/Network,
		$Menu/Game,
		$Menu/Help,
	]
	for index in menu_buttons.size():
		var button: Button = menu_buttons[index]
		_style_menu_button(button)
		button.pressed.connect(_select_main_page.bind(index))
	_load_preview_fonts()
	_select_main_page(0)
	_apply_initial_display_config()


func _select_main_page(index: int) -> void:
	_main_page = clampi(index, 0, 4)
	_rebuild_page()


func _rebuild_page() -> void:
	for child in $SystemPage.get_children():
		$SystemPage.remove_child(child)
		child.queue_free()
	_controls.clear()
	_sliders.clear()
	_friend_radios.clear()
	_preview_lines.clear()
	match _main_page:
		0:
			_build_system_page()
		1:
			_build_social_page()
		2:
			pass # Original C++ network page is intentionally empty.
		3:
			_build_game_page()
		4:
			pass # Original C++ help page is intentionally empty.
	_refresh_controls()


func _build_system_page() -> void:
	_add_tabs(["系统", "外观"], _system_tab, _select_system_tab)
	if _system_tab == 0:
		_add_label("ResolutionLabel", "分辨率", Vector2(0, 40), Vector2(45, 20))
		var resolution := OptionButton.new()
		resolution.name = "Resolution"
		resolution.position = Vector2(45, 35)
		resolution.size = Vector2(90, 26)
		for size_value in WINDOW_SIZES:
			resolution.add_item("%d×%d" % [size_value.x, size_value.y])
		resolution.item_selected.connect(_set_resolution)
		$SystemPage.add_child(resolution)
		_controls[47] = resolution

		_add_label("IMELabel", "输入法", Vector2(0, 70), Vector2(45, 20))
		var ime := OptionButton.new()
		ime.name = "IME"
		ime.position = Vector2(45, 65)
		ime.size = Vector2(145, 26)
		for label in ["禁用", "使用内置输入法", "使用系统输入法"]:
			ime.add_item(label)
		ime.item_selected.connect(_set_ime)
		$SystemPage.add_child(ime)
		_controls[7] = ime

		_add_check("Fullscreen", 5, "全屏显示", Vector2(0, 115))
		_add_check("ShowFPS", 6, "显示FPS", Vector2(0, 140))
		_add_check("BGM", 1, "背景音乐", Vector2(0, 180))
		_add_slider("BGMVolume", "音乐音量", 2, 1, 205.0)
		_add_check("SEFF", 3, "动作声效", Vector2(0, 240))
		_add_slider("SEFFVolume", "声效音量", 4, 3, 265.0)
	else:
		_build_appearance_page()


func _build_appearance_page() -> void:
	_add_label("WidgetLabel", "控件", Vector2(0, 40), Vector2(120, 18))
	_add_label("FontLabel", "字体", Vector2(140, 40), Vector2(130, 18))
	_add_label("SizeLabel", "字号", Vector2(280, 40), Vector2(80, 18))
	var widget := OptionButton.new()
	widget.name = "PreviewWidget"
	widget.position = Vector2(0, 58)
	widget.size = Vector2(120, 26)
	widget.add_item("系统信息")
	widget.add_item("命令行")
	$SystemPage.add_child(widget)
	var font_select := OptionButton.new()
	font_select.name = "PreviewFont"
	font_select.position = Vector2(140, 58)
	font_select.size = Vector2(130, 26)
	for font_name in ["微软雅黑", "文泉驿点阵宋体 A", "文泉驿点阵宋体 B"]:
		font_select.add_item(font_name)
	font_select.select(_preview_font_index)
	font_select.item_selected.connect(_set_preview_font)
	$SystemPage.add_child(font_select)
	var size_select := SpinBox.new()
	size_select.name = "PreviewSize"
	size_select.position = Vector2(280, 58)
	size_select.size = Vector2(80, 26)
	size_select.min_value = 5
	size_select.max_value = 25
	size_select.step = 1
	size_select.value = _preview_font_size
	size_select.value_changed.connect(_set_preview_size)
	$SystemPage.add_child(size_select)
	var preview_frame := Panel.new()
	preview_frame.name = "PreviewFrame"
	preview_frame.position = Vector2(0, 100)
	preview_frame.size = Vector2(410, 80)
	preview_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color.TRANSPARENT
	frame_style.set_border_width_all(1)
	frame_style.border_color = Color(0.5, 0.5, 0.5, 1)
	preview_frame.add_theme_stylebox_override("panel", frame_style)
	$SystemPage.add_child(preview_frame)
	_add_preview_line("EnglishPreview", "The quick brown fox jumps over the lazy dog.", 105.0)
	_add_preview_line("ChinesePreview", "快速的棕色狐狸跳过了懒狗。", 135.0)
	_apply_preview_font()


func _build_social_page() -> void:
	_add_tabs(["社交", "好友"], _social_tab, _select_social_tab)
	if _social_tab == 0:
		for index in SOCIAL_CONFIGS.size():
			var entry: Array = SOCIAL_CONFIGS[index]
			var x := 0.0 if index < 5 else 200.0
			var row := index if index < 5 else index - 5
			_add_check("Config%d" % int(entry[0]), int(entry[0]), str(entry[1]), Vector2(x, 40 + row * 25))
	else:
		_add_label("FriendPolicyLabel", "当加我为好友时：", Vector2(0, 40), Vector2(220, 18))
		var labels := ["允许任何人加我为好友", "拒绝任何人加我为好友", "好友申请验证"]
		for index in labels.size():
			var radio := _make_check_button("FriendPolicy%d" % index, labels[index], Vector2(0, 65 + index * 25))
			radio.toggled.connect(_on_friend_policy_toggled.bind(index))
			$SystemPage.add_child(radio)
			_friend_radios.append(radio)


func _build_game_page() -> void:
	_add_tabs(["常用", "辅助", "保护"], _game_tab, _select_game_tab)
	if _game_tab == 0:
		for index in GAME_CONFIGS.size():
			var entry: Array = GAME_CONFIGS[index]
			_add_check("Config%d" % int(entry[0]), int(entry[0]), str(entry[1]), Vector2(0, 40 + index * 25))
		_add_check("Config49", 49, "·键锁定法术目标", Vector2(200, 40))
	elif _game_tab == 1:
		for index in AUXILIARY_CONFIGS.size():
			var entry: Array = AUXILIARY_CONFIGS[index]
			var y := 40 + index * 25 + (25 if index >= 3 else 0)
			_add_check("Config%d" % int(entry[0]), int(entry[0]), str(entry[1]), Vector2(0, y))
	else:
		for index in PROTECTION_CONFIGS.size():
			var entry: Array = PROTECTION_CONFIGS[index]
			_add_check("Config%d" % int(entry[0]), int(entry[0]), str(entry[1]), Vector2(0, 40 + index * 25))
		_add_label("WaitLabel", "等待", Vector2(0, 150), Vector2(40, 20))
		var wait_seconds := SpinBox.new()
		wait_seconds.name = "UnusedWaitSeconds"
		wait_seconds.position = Vector2(40, 145)
		wait_seconds.size = Vector2(50, 26)
		wait_seconds.min_value = 0
		wait_seconds.max_value = 999
		$SystemPage.add_child(wait_seconds)
		_add_label("SecondsLabel", "秒", Vector2(95, 150), Vector2(30, 20))


func _add_tabs(labels: Array[String], selected: int, callback: Callable) -> void:
	var x := 0.0
	for index in labels.size():
		var button := Button.new()
		button.name = "Tab%d" % index
		button.text = labels[index]
		button.flat = true
		button.position = Vector2(x, -2)
		button.size = Vector2(48, 20)
		button.add_theme_color_override("font_color", Color.WHITE)
		button.add_theme_color_override("font_hover_color", Color.RED)
		if index == selected:
			var selected_style := StyleBoxFlat.new()
			selected_style.bg_color = Color(0.905882, 0.905882, 0.741176, 0.392157)
			selected_style.content_margin_left = 4
			selected_style.content_margin_right = 4
			button.add_theme_stylebox_override("normal", selected_style)
		button.pressed.connect(callback.bind(index))
		$SystemPage.add_child(button)
		x += 58.0
	var separator := ColorRect.new()
	separator.name = "Separator"
	separator.position = Vector2(0, 18)
	separator.size = Vector2(410, 1)
	separator.color = Color(0.905882, 0.905882, 0.741176, 0.392157)
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$SystemPage.add_child(separator)


func _add_check(node_name: String, key: int, label: String, position_value: Vector2) -> void:
	var button := _make_check_button(node_name, label, position_value)
	button.toggled.connect(_on_bool_toggled.bind(key))
	$SystemPage.add_child(button)
	_controls[key] = button


func _make_check_button(node_name: String, label: String, position_value: Vector2) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = label
	button.toggle_mode = true
	button.flat = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.position = position_value
	button.size = Vector2(195, 18)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.RED)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 24
	for style_name in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(style_name, empty)
	var frame := Panel.new()
	frame.name = "CheckFrame"
	frame.position = Vector2(0, 1)
	frame.size = Vector2(16, 16)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color.TRANSPARENT
	frame_style.set_border_width_all(1)
	frame_style.border_color = Color(0.905882, 0.905882, 0.741176, 0.501961)
	frame.add_theme_stylebox_override("panel", frame_style)
	button.add_child(frame)
	var mark := TextureRect.new()
	mark.name = "Mark"
	mark.position = Vector2(2.5, 4)
	mark.size = Vector2(11, 9)
	mark.texture = CHECK_TEXTURE
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.visible = false
	button.add_child(mark)
	button.toggled.connect(func(value: bool): mark.visible = value)
	return button


func _add_slider(node_name: String, label: String, key: int, active_key: int, y: float) -> void:
	_add_label(node_name + "Label", label, Vector2(0, y), Vector2(65, 18))
	var slider := HSlider.new()
	slider.name = node_name
	slider.position = Vector2(65, y - 5)
	slider.size = Vector2(84, 18)
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	var track_style := StyleBoxTexture.new()
	track_style.texture = SLIDER_TRACK
	track_style.texture_margin_left = 3
	track_style.texture_margin_top = 3
	track_style.texture_margin_right = 3
	track_style.texture_margin_bottom = 3
	var fill_style := StyleBoxTexture.new()
	fill_style.texture = SLIDER_FILL
	slider.add_theme_stylebox_override("slider", track_style)
	slider.add_theme_stylebox_override("grabber_area", fill_style)
	slider.add_theme_icon_override("grabber", SLIDER_KNOB)
	slider.add_theme_icon_override("grabber_highlight", SLIDER_KNOB)
	slider.value_changed.connect(_on_float_changed.bind(key))
	$SystemPage.add_child(slider)
	_controls[key] = slider
	_sliders[key] = {"slider": slider, "active_key": active_key, "label": $SystemPage.get_node(node_name + "Label")}


func _add_label(node_name: String, text: String, position_value: Vector2, size_value: Vector2) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.position = position_value
	label.size = size_value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$SystemPage.add_child(label)
	return label


func _add_preview_line(node_name: String, text: String, y: float) -> void:
	var line := LineEdit.new()
	line.name = node_name
	line.text = text
	line.position = Vector2(4, y)
	line.size = Vector2(402, 24)
	line.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	line.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	line.text_changed.connect(func(_value: String): _apply_preview_font())
	$SystemPage.add_child(line)
	_preview_lines.append(line)


func _style_menu_button(button: Button) -> void:
	button.add_theme_color_override("font_color", Color.YELLOW)
	button.add_theme_color_override("font_hover_color", Color.RED)
	button.add_theme_color_override("font_pressed_color", Color.RED)
	for style_name in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(style_name, StyleBoxEmpty.new())


func _select_system_tab(index: int) -> void:
	_system_tab = index
	_rebuild_page()


func _select_social_tab(index: int) -> void:
	_social_tab = index
	_rebuild_page()


func _select_game_tab(index: int) -> void:
	_game_tab = index
	_rebuild_page()


func _on_bool_toggled(value: bool, key: int) -> void:
	if _updating:
		return
	_set_local_archive(key, _bool_archive(value))
	if key == 1:
		AudioService.set_bgm_enabled(value)
	elif key == 3:
		AudioService.set_seff_enabled(value)
	elif key == 5:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if value else DisplayServer.WINDOW_MODE_WINDOWED)
	NetworkClient.send_runtime_bool(key, value)
	_refresh_slider_activity()


func _on_float_changed(value: float, key: int) -> void:
	if _updating:
		return
	var ratio := value / 100.0
	_set_local_archive(key, _float_archive(ratio))
	if key == 2:
		AudioService.set_bgm_volume(ratio)
	else:
		AudioService.set_seff_volume(ratio)
	NetworkClient.send_runtime_float(key, ratio)


func _on_friend_policy_toggled(value: bool, index: int) -> void:
	if _updating or not value:
		return
	_set_local_archive(48, _int_archive(index))
	NetworkClient.send_runtime_int(48, index)
	_refresh_friend_radios()


func _set_resolution(index: int) -> void:
	if _updating or index < 0 or index >= WINDOW_SIZES.size():
		return
	var window_size: Vector2i = WINDOW_SIZES[index]
	_set_local_archive(47, _pair_archive(window_size))
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		get_tree().root.size = window_size
	NetworkClient.send_runtime_pair(47, window_size.x, window_size.y)


func _set_ime(index: int) -> void:
	if _updating:
		return
	var protocol_value := clampi(index, 0, 2) + 1
	_set_local_archive(7, _int_archive(protocol_value))
	NetworkClient.send_runtime_int(7, protocol_value)


func _set_preview_font(index: int) -> void:
	_preview_font_index = clampi(index, 0, maxi(0, _preview_fonts.size() - 1))
	_apply_preview_font()


func _set_preview_size(value: float) -> void:
	_preview_font_size = clampi(roundi(value), 5, 25)
	_apply_preview_font()


func _load_preview_fonts() -> void:
	for path in [
		"res://assets/font/01_Yahei.ttf",
		"res://assets/font/0A_WenQuanYi_Bitmap_Song_15_px.ttf",
		"res://assets/font/0B_WenQuanYi_Bitmap_Song_15_px.ttf",
	]:
		var font := load(path) as Font
		if font:
			_preview_fonts.append(font)


func _apply_preview_font() -> void:
	for line in _preview_lines:
		if not _preview_fonts.is_empty():
			line.add_theme_font_override("font", _preview_fonts[_preview_font_index])
		line.add_theme_font_size_override("font_size", _preview_font_size)


func _refresh_controls() -> void:
	if _state == null:
		return
	_updating = true
	for key_value in _controls:
		var key: int = key_value
		var control: Control = _controls[key]
		if control is OptionButton:
			if key == 7:
				(control as OptionButton).select(clampi(_config_int(7, 1), 1, 3) - 1)
			elif key == 47:
				(control as OptionButton).select(_window_size_index(_config_pair(47, Vector2i(800, 600))))
		elif control is HSlider:
			(control as HSlider).value = _config_float(key, _default_float(key)) * 100.0
		elif control is Button:
			(control as Button).button_pressed = _config_bool(key, _default_bool(key))
	_refresh_friend_radios()
	_refresh_slider_activity()
	_updating = false


func _refresh_friend_radios() -> void:
	var policy := clampi(_config_int(48, 2), 0, 2)
	for index in _friend_radios.size():
		_friend_radios[index].set_pressed_no_signal(index == policy)
		var mark := _friend_radios[index].get_node("Mark") as TextureRect
		mark.visible = index == policy


func _refresh_slider_activity() -> void:
	for key_value in _sliders:
		var entry: Dictionary = _sliders[key_value]
		var active_key := int(entry.active_key)
		var enabled := _config_bool(active_key, _default_bool(active_key))
		var slider := entry.slider as HSlider
		var label := entry.label as Label
		slider.editable = enabled
		slider.modulate = Color.WHITE if enabled else Color(0.5, 0.5, 0.5, 1)
		label.modulate = Color.WHITE if enabled else Color(0.5, 0.5, 0.5, 1)


func _apply_initial_display_config() -> void:
	apply_display_config(_state.runtime_config)


func _display_settings(config: Dictionary) -> Dictionary:
	return decode_display_settings(config)


static func decode_display_settings(config: Dictionary) -> Dictionary:
	var fullscreen_data: PackedByteArray = config.get(5, PackedByteArray())
	var size_data: PackedByteArray = config.get(47, PackedByteArray())
	var fullscreen := fullscreen_data.size() >= 2 and fullscreen_data[0] != 0 and fullscreen_data[1] != 0
	var window_size := Vector2i(800, 600)
	if size_data.size() >= 9 and size_data[0] != 0:
		window_size = Vector2i(size_data.decode_s32(1), size_data.decode_s32(5))
	if window_size.x <= 0 or window_size.y <= 0:
		window_size = Vector2i(800, 600)
	return {"fullscreen": fullscreen, "window_size": window_size}


static func apply_display_config(config: Dictionary) -> Dictionary:
	var settings := decode_display_settings(config)
	if DisplayServer.get_name() == "headless":
		return settings
	var scene_tree := Engine.get_main_loop() as SceneTree
	if settings.fullscreen:
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
			scene_tree.root.size = settings.window_size
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		scene_tree.root.size = settings.window_size
	return settings


func _config_bool(key: int, fallback: bool) -> bool:
	var data: PackedByteArray = _state.runtime_config.get(key, PackedByteArray())
	return data[1] != 0 if data.size() >= 2 and data[0] != 0 else fallback


func _config_float(key: int, fallback: float) -> float:
	var data: PackedByteArray = _state.runtime_config.get(key, PackedByteArray())
	return data.decode_float(1) if data.size() >= 5 and data[0] != 0 else fallback


func _config_int(key: int, fallback: int) -> int:
	var data: PackedByteArray = _state.runtime_config.get(key, PackedByteArray())
	return data.decode_s32(1) if data.size() >= 5 and data[0] != 0 else fallback


func _config_pair(key: int, fallback: Vector2i) -> Vector2i:
	var data: PackedByteArray = _state.runtime_config.get(key, PackedByteArray())
	return Vector2i(data.decode_s32(1), data.decode_s32(5)) if data.size() >= 9 and data[0] != 0 else fallback


func _default_bool(key: int) -> bool:
	if key == 1:
		return AudioService.bgm_enabled
	if key == 3:
		return AudioService.seff_enabled
	return key not in [5, 6, 49]


func _default_float(key: int) -> float:
	return AudioService.bgm_volume if key == 2 else AudioService.seff_volume


func _window_size_index(value: Vector2i) -> int:
	var index := WINDOW_SIZES.find(value)
	return index if index >= 0 else 0


func _set_local_archive(key: int, archive: PackedByteArray) -> void:
	_state.runtime_config[key] = archive


func _bool_archive(value: bool) -> PackedByteArray:
	return PackedByteArray([1, 1 if value else 0, 0])


func _float_archive(value: float) -> PackedByteArray:
	var result := PackedByteArray([1, 0, 0, 0, 0, 0])
	result.encode_float(1, value)
	return result


func _int_archive(value: int) -> PackedByteArray:
	var result := PackedByteArray([1, 0, 0, 0, 0, 0])
	result.encode_s32(1, value)
	return result


func _pair_archive(value: Vector2i) -> PackedByteArray:
	var result := PackedByteArray([1, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	result.encode_s32(1, value.x)
	result.encode_s32(5, value.y)
	return result
