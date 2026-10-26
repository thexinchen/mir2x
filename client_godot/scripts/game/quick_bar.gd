extends Control

const ActorResourceScript = preload("res://scripts/game/actor_resource.gd")
const COUNT_FONT := preload("res://assets/font/01_Yahei.ttf")

const SLOT_COUNT := 6
const SLOT_SIZE := 36
const SLOT_START := Vector2(17, 6)
const SLOT_STEP := 42
const DRAG_THRESHOLD := 3.0

const ACTION_NONE := 0
const ACTION_EQUIP := 1
const ACTION_GRAB := 2
const ACTION_CONSUME := 3
const ACTION_RETURN := 4

signal slot_action_requested(action: int, slot: int)

var _state: Node
var _resources: RefCounted = ActorResourceScript.new()
var _pressed_slot := -1
var _press_position := Vector2.ZERO
var _dragging := false
var _placed := false


func _ready() -> void:
	_state = get_node("/root/GameState")
	_resources.configure_default()
	_state.state_changed.connect(_refresh)
	gui_input.connect(_on_bar_input)
	var parent_control := get_parent_control()
	if parent_control != null:
		parent_control.resized.connect(_clamp_position)
	visibility_changed.connect(func():
		if visible:
			_place_initial()
	)
	mouse_exited.connect(func(): _set_hovered_slot(-1))
	_refresh()


func activate_slot(slot: int, button: int) -> int:
	if slot < 0 or slot >= SLOT_COUNT:
		return ACTION_NONE
	if button == MOUSE_BUTTON_RIGHT:
		var item := _belt_item(slot)
		if item.is_empty():
			return ACTION_NONE
		if NetworkClient.send_consume_belt_item(slot) == ERR_BUSY:
			return ACTION_NONE
		AudioService.play_seff_at(_resources.item_sound_effect(int(item.get("itemID", 0))), 0, 0, 0, 0)
		slot_action_requested.emit(ACTION_CONSUME, slot)
		return ACTION_CONSUME
	if button != MOUSE_BUTTON_LEFT:
		return ACTION_NONE
	if not _state.grabbed_item.is_empty():
		var grabbed: Dictionary = _state.grabbed_item
		if _is_beltable(int(grabbed.get("itemID", 0))):
			NetworkClient.send_request_equip_belt(grabbed.get("itemID", 0), grabbed.get("seqID", 0), slot)
			slot_action_requested.emit(ACTION_EQUIP, slot)
			return ACTION_EQUIP
		_state.inventory.append(grabbed)
		AudioService.play_seff_at(_resources.item_sound_effect(int(grabbed.get("itemID", 0))), 0, 0, 0, 0)
		_state.grabbed_item = {}
		_state.state_changed.emit()
		slot_action_requested.emit(ACTION_RETURN, slot)
		return ACTION_RETURN
	if not _belt_item(slot).is_empty():
		NetworkClient.send_request_grab_belt(slot)
		slot_action_requested.emit(ACTION_GRAB, slot)
		return ACTION_GRAB
	return ACTION_NONE


func _refresh() -> void:
	for child in $Slots.get_children():
		child.free()
	for slot in range(SLOT_COUNT):
		var holder := Control.new()
		holder.name = "Slot%d" % slot
		holder.position = SLOT_START + Vector2(SLOT_STEP * slot, 0)
		holder.size = Vector2(SLOT_SIZE, SLOT_SIZE)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		$Slots.add_child(holder)
		var item := _belt_item(slot)
		if item.is_empty():
			continue
		var item_id := int(item.get("itemID", 0))
		var icon: Dictionary = _resources.frame("item", _resources.item_package_gfx_id(item_id) | 0x01000000)
		if not icon.is_empty():
			var image := TextureRect.new()
			image.name = "Icon"
			image.texture = icon.texture
			image.expand_mode = TextureRect.EXPAND_KEEP_SIZE
			image.mouse_filter = Control.MOUSE_FILTER_IGNORE
			image.reset_size()
			image.position = (Vector2(SLOT_SIZE, SLOT_SIZE) - image.size) * 0.5
			holder.add_child(image)
		var count := int(item.get("count", 1))
		if count > 1:
			var count_label := Label.new()
			count_label.name = "Count"
			count_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			count_label.offset_right = -1.0
			count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			count_label.text = str(count)
			count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			count_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
			count_label.add_theme_font_override("font", COUNT_FONT)
			count_label.add_theme_font_size_override("font_size", 10)
			count_label.add_theme_color_override("font_color", Color.WHITE)
			holder.add_child(count_label)
func _on_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var right_slot := _slot_at(event.position)
			if right_slot >= 0:
				activate_slot(right_slot, MOUSE_BUTTON_RIGHT)
			accept_event()
			return
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		if event.pressed:
			_pressed_slot = _slot_at(event.position)
			_press_position = event.position
			_dragging = false
			accept_event()
		else:
			if not _dragging and _pressed_slot >= 0:
				activate_slot(_pressed_slot, MOUSE_BUTTON_LEFT)
			_pressed_slot = -1
			_dragging = false
			accept_event()
	elif event is InputEventMouseMotion:
		_set_hovered_slot(_slot_at(event.position))
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			if not _dragging and event.position.distance_to(_press_position) >= DRAG_THRESHOLD:
				_dragging = true
			if _dragging:
				position += event.relative
				_clamp_position()
				accept_event()


func _slot_at(local_position: Vector2) -> int:
	if local_position.y < SLOT_START.y or local_position.y >= SLOT_START.y + SLOT_SIZE:
		return -1
	for slot in range(SLOT_COUNT):
		var x := SLOT_START.x + SLOT_STEP * slot
		if local_position.x >= x and local_position.x < x + SLOT_SIZE:
			return slot
	return -1


func _belt_item(slot: int) -> Dictionary:
	if slot < 0 or slot >= _state.belt.size():
		return {}
	var value = _state.belt[slot]
	return value if value is Dictionary else {}


func _is_beltable(item_id: int) -> bool:
	return _resources.item_type(item_id) in ["恢复药水", "传送卷轴"]


func _set_hovered_slot(slot: int) -> void:
	$Hover.visible = slot >= 0
	if slot >= 0:
		$Hover.position = SLOT_START + Vector2(SLOT_STEP * slot, 0)


func _place_initial() -> void:
	if get_parent_control() == null:
		return
	place_initial(maxi(0, int(get_parent_control().size.y) - 200))


func place_initial(initial_y: float) -> void:
	if _placed or get_parent_control() == null:
		return
	position = Vector2(0, initial_y)
	_placed = true
	_clamp_position()


func _clamp_position() -> void:
	var parent_control := get_parent_control()
	if parent_control == null:
		return
	position.x = clampf(position.x, 0.0, maxf(0.0, parent_control.size.x - size.x))
	position.y = clampf(position.y, 0.0, maxf(0.0, parent_control.size.y - size.y))
