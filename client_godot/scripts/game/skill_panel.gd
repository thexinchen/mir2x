extends "res://scripts/game/closable_panel.gd"

const ActorResourceScript = preload("res://scripts/game/actor_resource.gd")
const Shortcuts = preload("res://scripts/game/magic_shortcuts.gd")
const OVERLAY_FONT := preload("res://assets/font/03_MONOWIDE.ttf")
const PAGE_NAMES := ["火", "冰", "雷", "风", "神圣", "暗黑", "幻影", "无"]
const PAGE_TEXTURES: Array[Texture2D] = [
	preload("res://assets/ui/game/skill/05000010.png"),
	preload("res://assets/ui/game/skill/05000011.png"),
	preload("res://assets/ui/game/skill/05000012.png"),
	preload("res://assets/ui/game/skill/05000013.png"),
	preload("res://assets/ui/game/skill/05000014.png"),
	preload("res://assets/ui/game/skill/05000015.png"),
	preload("res://assets/ui/game/skill/05000016.png"),
	preload("res://assets/ui/game/skill/05000017.png"),
]

@onready var page: TextureRect = $PageViewport/Page
@onready var learned_skills: Control = $PageViewport/LearnedSkills
@onready var selection_label: Label = $SelectionLabel
@onready var slider: TextureRect = $Slider
@onready var tab_buttons: Array[TextureButton] = [
	$Tab0, $Tab1, $Tab2, $Tab3, $Tab4, $Tab5, $Tab6, $Tab7,
]

var _state: Node
var _resources: RefCounted = ActorResourceScript.new()
var _selected_tab := 0
var _hovered_tab := -1
var _hovered_magic_id := 0
var _scroll := 0.0
var _scroll_reach := 0.0
var _slider_dragging := false


func _ready() -> void:
	super._ready()
	_resources.configure_default()
	for index in tab_buttons.size():
		tab_buttons[index].pressed.connect(_select_tab.bind(index))
		tab_buttons[index].mouse_entered.connect(_show_tab_name.bind(index))
		tab_buttons[index].mouse_exited.connect(_hide_tab_name.bind(index))
	_state = get_node("/root/GameState")
	_state.state_changed.connect(_refresh_learned_skills)
	$PageViewport.gui_input.connect(_on_page_input)
	$SliderInput.gui_input.connect(_on_slider_input)
	_select_tab(0)


func _select_tab(index: int) -> void:
	var changed := _selected_tab != index
	_selected_tab = index
	if changed:
		_scroll = 0.0
	page.texture = PAGE_TEXTURES[index]
	for button_index in tab_buttons.size():
		tab_buttons[button_index].button_pressed = button_index == index
	_update_selection_label()
	_refresh_learned_skills()


func set_learned_skills(skill_nodes: Array[Control]) -> void:
	_clear_skills()
	for skill_node in skill_nodes:
		learned_skills.add_child(skill_node)


func _refresh_learned_skills() -> void:
	_clear_skills()
	var learned_by_id := {}
	for magic_value in _state.learned_magic:
		var magic: Dictionary = magic_value
		learned_by_id[int(magic.get("magicID", 0))] = magic
	var max_button_reach := 0.0
	for magic_value in _resources.skill_meta.keys():
		var magic_id := int(magic_value)
		var layout: PackedInt32Array = _resources.skill_layout(magic_id)
		if layout.size() < 5 or layout[1] != _selected_tab:
			continue
		var frame: Dictionary = _resources.frame("proguse", layout[0])
		if frame.is_empty():
			continue
		var texture: Texture2D = frame.texture
		var button := TextureButton.new()
		button.set_meta("magic_id", magic_id)
		button.position = Vector2(layout[2] * 60 + 12, layout[3] * 65 + 13)
		button.size = texture.get_size() + Vector2(8, 8)
		button.ignore_texture_size = true
		button.mouse_entered.connect(_show_magic.bind(magic_id))
		button.mouse_exited.connect(_hide_magic.bind(magic_id))
		learned_skills.add_child(button)
		if learned_by_id.has(magic_id):
			var icon := TextureRect.new()
			icon.name = "Icon"
			icon.size = texture.get_size()
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.texture = texture
			button.add_child(icon)

			var level_label := _make_overlay_label("1", 12, Color.YELLOW)
			level_label.position = Vector2(texture.get_width() - 2, texture.get_height() - 1)
			button.add_child(level_label)

			var key: int = _state.magic_keys.get(magic_id, 0)
			if key != 0:
				var key_text: String = Shortcuts.label(key)
				var key_font_size := 20
				while key_font_size > 10 and OVERLAY_FONT.get_string_size(key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, key_font_size).x > button.size.x - 4:
					key_font_size -= 1
				var key_shadow := _make_overlay_label(key_text, key_font_size, Color(0.0, 0.0, 0.0, 224.0 / 255.0))
				key_shadow.position = Vector2(4, 4)
				button.add_child(key_shadow)
				var key_label := _make_overlay_label(key_text, key_font_size, Color(1.0, 128.0 / 255.0, 0.0, 224.0 / 255.0))
				key_label.position = Vector2(2, 2)
				button.add_child(key_label)
		max_button_reach = maxf(max_button_reach, layout[3] * 65.0 + 13.0 + texture.get_height() + 8.0)
	var background_height := float(page.texture.get_height()) if page.texture != null else 329.0
	var page_height := clampf(max_button_reach + 10.0, minf(background_height, 329.0), maxf(background_height, 329.0))
	_scroll_reach = maxf(0.0, page_height - 329.0)
	_apply_scroll()


func _make_overlay_label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text_value
	label.add_theme_font_override("font", OVERLAY_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _clear_skills() -> void:
	for child in learned_skills.get_children():
		child.free()


func _show_tab_name(index: int) -> void:
	_hovered_tab = index
	_update_selection_label()


func _hide_tab_name(index: int) -> void:
	if _hovered_tab == index:
		_hovered_tab = -1
		_update_selection_label()


func _show_magic(magic_id: int) -> void:
	_hovered_magic_id = magic_id
	_update_selection_label()


func _hide_magic(magic_id: int) -> void:
	if _hovered_magic_id == magic_id:
		_hovered_magic_id = 0
		_update_selection_label()


func _update_selection_label() -> void:
	if _hovered_tab >= 0:
		selection_label.text = "元素【%s】" % PAGE_NAMES[_hovered_tab]
	elif _hovered_magic_id != 0:
		selection_label.text = "元素【%s】%s" % [PAGE_NAMES[_selected_tab], _resources.magic_names.get(_hovered_magic_id, "")]
	else:
		selection_label.text = "元素【%s】" % PAGE_NAMES[_selected_tab]


func _on_page_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll = maxf(0.0, _scroll - 0.1)
			_apply_scroll()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll = minf(1.0, _scroll + 0.1)
			_apply_scroll()


func _on_slider_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_slider_dragging = event.pressed
		if event.pressed:
			_set_scroll_from_slider(event.position.y)
		accept_event()
	elif event is InputEventMouseMotion and _slider_dragging:
		_set_scroll_from_slider(event.position.y)
		accept_event()


func _set_scroll_from_slider(local_y: float) -> void:
	_scroll = clampf((local_y - 7.0) / 266.0, 0.0, 1.0)
	_apply_scroll()


func _apply_scroll() -> void:
	var offset := -_scroll_reach * _scroll
	page.position.y = offset
	learned_skills.position.y = offset
	slider.position.y = 67.0 + _scroll * 266.0


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not visible or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		super._unhandled_key_input(event)
		return
	if _hovered_magic_id == 0:
		return
	# Original67E2D8 claims digit item keys without checking slot visibility.
	# Ten inventory shortcuts own all digits, including an empty slot.
	if event.keycode >= KEY_0 and event.keycode <= KEY_9:
		var main := get_parent()
		var quick_bar: Control = null
		if main != null:
			quick_bar = main.get_node_or_null("ControlPanel/ItemShortcuts") as Control
		if quick_bar != null:
			return
	var key: int = Shortcuts.event_key(event)
	if key == 0:
		return
	if not _has_learned_magic(_hovered_magic_id):
		get_viewport().set_input_as_handled()
		return
	var layout: PackedInt32Array = _resources.skill_layout(_hovered_magic_id)
	if layout.size() >= 5 and (layout[4] & 1) != 0:
		_state.add_chat_log("无法为被动技能设置快捷键：%s" % _resources.magic_names.get(_hovered_magic_id, ""), 1)
		get_viewport().set_input_as_handled()
		return
	for magic_id in _state.magic_keys.keys():
		if _state.magic_keys[magic_id] == key:
			_state.magic_keys.erase(magic_id)
	_state.magic_keys[_hovered_magic_id] = key
	NetworkClient.send_set_magic_key(_hovered_magic_id, key)
	_refresh_learned_skills()
	get_viewport().set_input_as_handled()


func _has_learned_magic(magic_id: int) -> bool:
	for magic_value in _state.learned_magic:
		if int((magic_value as Dictionary).get("magicID", 0)) == magic_id:
			return true
	return false
