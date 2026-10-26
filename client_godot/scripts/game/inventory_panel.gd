extends "res://scripts/game/closable_panel.gd"

const ActorResourceScript = preload("res://scripts/game/actor_resource.gd")
const ItemTooltipFormatterScript = preload("res://scripts/game/item_tooltip_formatter.gd")
const ItemTooltipRendererScript = preload("res://scripts/game/item_tooltip_renderer.gd")
const GRID_COLUMNS := 10
const GRID_VISIBLE_ROWS := 10
const CELL_SIZE := 38
const SLIDER_TRACK_TOP := 56.0
const SLIDER_BAR_TOP := 63.0
const SLIDER_TRAVEL := 368.0
const EMBLEM_FPS := 8.0
const EMBLEM_FRAME_COUNT := 10
const TOOLTIP_WIDTH := 220.0
const TOOLTIP_MIN_HEIGHT := 40.0
const TOOLTIP_PADDING := 10.0
const TOOLTIP_LINE_HEIGHT := 15.0
const TOOLTIP_FONT_SIZE := 12

const OP_NONE := 0
const OP_TRADE := 1
const OP_SECURE := 2
const OP_REPAIR := 3

const REPAIR_NORMAL := preload("res://assets/ui/game/inventory/000000b1.png")
const REPAIR_DOWN := preload("res://assets/ui/game/inventory/000000b2.png")
const TRADE_NORMAL := preload("res://assets/ui/game/inventory/000000b3.png")
const TRADE_DOWN := preload("res://assets/ui/game/inventory/000000b4.png")
const SECURE_NORMAL := preload("res://assets/ui/game/inventory/000000b5.png")
const SECURE_DOWN := preload("res://assets/ui/game/inventory/000000b6.png")

var _state: Node
var _resources: RefCounted = ActorResourceScript.new()
var _bins: Dictionary = {} # item key -> {x,y,w,h,item}
var _grid_snapshot: Dictionary = {}
var _selected_key := ""
var _grabbed_origin := Vector2i.ZERO
var _scroll_row := 0
var _scroll_value := 0.0
var _slider_dragging := false
var _emblem_time := 0.0
var _emblem_frame := -1
var _tooltip_key := ""
var _repack_index := 0


func _ready() -> void:
	super._ready()
	_state = get_node("/root/GameState")
	_resources.configure_default()
	_state.state_changed.connect(_refresh)
	$SortButton.pressed.connect(_repack)
	$SortButton.pressed.connect(AudioService.play_ui_click)
	$CloseButton.pressed.connect(_close_operation)
	$CloseButton.pressed.connect(AudioService.play_ui_click)
	$ItemGrid.gui_input.connect(_on_grid_input)
	$SliderTrack.gui_input.connect(_on_slider_input)
	$OperationButton.pressed.connect(_commit_operation)
	$OperationButton.pressed.connect(AudioService.play_ui_click)
	_bind_overlay_button($SortButton)
	_bind_overlay_button($CloseButton)
	ItemTooltipRendererScript.configure($ItemTooltip, true, true)
	_refresh()
	_update_emblem()


func _process(delta: float) -> void:
	_emblem_time += delta
	var frame := int(_emblem_time * EMBLEM_FPS) % EMBLEM_FRAME_COUNT
	if frame != _emblem_frame:
		_update_emblem(frame)
	if $ItemTooltip.visible:
		if is_visible_in_tree():
			_update_tooltip_position()
		else:
			_hide_item_tooltip()


func _bind_overlay_button(button: TextureButton) -> void:
	button.set_meta("overlay_hovered", false)
	button.set_meta("overlay_pressed", false)
	button.modulate.a = 0.0
	button.mouse_entered.connect(_set_overlay_hovered.bind(button, true))
	button.mouse_exited.connect(_set_overlay_hovered.bind(button, false))
	button.button_down.connect(_set_overlay_pressed.bind(button, true))
	button.button_up.connect(_set_overlay_pressed.bind(button, false))


func _set_overlay_hovered(button: TextureButton, hovered: bool) -> void:
	button.set_meta("overlay_hovered", hovered)
	_update_overlay_alpha(button)


func _set_overlay_pressed(button: TextureButton, pressed: bool) -> void:
	button.set_meta("overlay_pressed", pressed)
	_update_overlay_alpha(button)


func _update_overlay_alpha(button: TextureButton) -> void:
	button.modulate.a = 1.0 if button.get_meta("overlay_hovered", false) or button.get_meta("overlay_pressed", false) else 0.0


func _update_emblem(frame := 0) -> void:
	_emblem_frame = frame
	var resource: Dictionary = _resources.frame("proguse", 0x04000010 + frame)
	$Emblem.visible = not resource.is_empty()
	if resource.is_empty():
		return
	$Emblem.texture = resource.texture
	$Emblem.size = resource.texture.get_size()


static func _format_gold(value: int) -> String:
	var digits := str(maxi(0, value))
	var formatted := ""
	for index in range(digits.length()):
		if index > 0 and (digits.length() - index) % 3 == 0:
			formatted += ","
		formatted += digits.substr(index, 1)
	return formatted


func _refresh() -> void:
	var tooltip_key := _tooltip_key
	_sync_bins()
	_refresh_operation()
	_update_scroll_from_value()
	$Gold.text = _format_gold(_state.player_gold)
	# Movement/health share state_changed with inventory updates. Keep the
	# existing controls (and hover) when their items and layout did not change.
	var selection := _selected_key if int(_state.inventory_operation.get("invOp", OP_NONE)) != OP_NONE else ""
	var grid_state := {"bins": _bins, "scroll_row": _scroll_row, "selection": selection}
	if grid_state == _grid_snapshot:
		return
	_grid_snapshot = grid_state.duplicate(true)
	_rebuild_grid()
	if not tooltip_key.is_empty() and _bins.has(tooltip_key):
		_show_item_tooltip(_bins[tooltip_key].item)
	else:
		_hide_item_tooltip()


func _rebuild_grid() -> void:
	for child in $ItemGrid.get_children():
		child.free()
	for key in _bins:
		var bin: Dictionary = _bins[key]
		var display_y := (int(bin.y) - _scroll_row) * CELL_SIZE
		if display_y + int(bin.h) * CELL_SIZE <= 0 or display_y >= GRID_VISIBLE_ROWS * CELL_SIZE:
			continue
		var item: Dictionary = bin.item
		var item_id := int(item.get("itemID", 0))
		var button := TextureButton.new()
		button.position = Vector2(int(bin.x) * CELL_SIZE, display_y)
		button.size = Vector2(int(bin.w) * CELL_SIZE, int(bin.h) * CELL_SIZE)
		button.ignore_texture_size = true
		var icon: Dictionary = _inventory_icon(item_id)
		if not icon.is_empty():
			var image := TextureRect.new()
			var image_size: Vector2 = icon.texture.get_size()
			image.name = "Icon"
			image.position = (button.size - image_size) / 2.0
			image.size = image_size
			image.mouse_filter = Control.MOUSE_FILTER_IGNORE
			image.texture = icon.texture
			image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			button.add_child(image)
		button.mouse_entered.connect(_show_item_tooltip.bind(item))
		button.mouse_exited.connect(_hide_item_tooltip)
		button.gui_input.connect(func(event: InputEvent): _on_item_input(event, key))
		$ItemGrid.add_child(button)
		if int(item.get("count", 1)) > 1:
			var count_label := Label.new()
			count_label.name = "Count"
			count_label.position = Vector2(button.size.x * 0.5, -2)
			count_label.size = Vector2(button.size.x, 16)
			count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			count_label.text = str(item.get("count", 1))
			count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			count_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
			count_label.add_theme_font_size_override("font_size", 10)
			count_label.add_theme_color_override("font_color", Color.YELLOW)
			button.add_child(count_label)
		var selected: bool = key == _selected_key and int(_state.inventory_operation.get("invOp", OP_NONE)) != OP_NONE
		var overlay := ColorRect.new()
		overlay.name = "Overlay"
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.color = Color(0, 0, 1, 48.0 / 255.0) if selected else Color.TRANSPARENT
		button.add_child(overlay)
		button.mouse_entered.connect(func(): overlay.color = Color(1, 1, 1, 48.0 / 255.0))
		button.mouse_exited.connect(func(): overlay.color = Color(0, 0, 1, 48.0 / 255.0) if selected else Color.TRANSPARENT)


func _show_item_tooltip(item: Dictionary) -> void:
	_tooltip_key = _item_key(item)
	var lines: Array[String] = ItemTooltipFormatterScript.plain_layout_lines(item, _resources)
	ItemTooltipRendererScript.show_lines($ItemTooltip, lines, TOOLTIP_WIDTH, TOOLTIP_MIN_HEIGHT, Vector2(TOOLTIP_PADDING, TOOLTIP_PADDING), TOOLTIP_LINE_HEIGHT, TOOLTIP_FONT_SIZE)
	_update_tooltip_position()


func _hide_item_tooltip() -> void:
	_tooltip_key = ""
	$ItemTooltip.hide()


func _update_tooltip_position(mouse_position: Variant = null) -> void:
	ItemTooltipRendererScript.update_position($ItemTooltip, true, mouse_position)


func _sync_bins() -> void:
	var live: Dictionary = {}
	for item in _state.inventory:
		var key := _item_key(item)
		live[key] = true
		if _bins.has(key):
			_bins[key]["item"] = item
			continue
		var size := _item_grid_size(int(item.get("itemID", 0)))
		var position := _find_free_position(size.x, size.y)
		_bins[key] = {"x": position.x, "y": position.y, "w": size.x, "h": size.y, "item": item}
	for key in _bins.keys():
		if not live.has(key):
			_bins.erase(key)
	if not _bins.has(_selected_key):
		_selected_key = ""


func _item_grid_size(item_id: int) -> Vector2i:
	var icon: Dictionary = _inventory_icon(item_id)
	if icon.is_empty():
		return Vector2i.ONE
	var texture: Texture2D = icon.texture
	return Vector2i(maxi(1, ceili(float(texture.get_width()) / CELL_SIZE)), maxi(1, ceili(float(texture.get_height()) / CELL_SIZE)))


func _inventory_icon(item_id: int) -> Dictionary:
	return _resources.frame("item", _resources.item_package_gfx_id(item_id) | 0x01000000)


func _find_free_position(width: int, height: int) -> Vector2i:
	for y in range(1000):
		for x in range(GRID_COLUMNS - width + 1):
			if not _occupied(x, y, width, height):
				return Vector2i(x, y)
	return Vector2i(0, 1000)


func _occupied(x: int, y: int, width: int, height: int, except_key: String = "") -> bool:
	for key in _bins:
		if key == except_key:
			continue
		var bin: Dictionary = _bins[key]
		if x < int(bin.x) + int(bin.w) and x + width > int(bin.x) and y < int(bin.y) + int(bin.h) and y + height > int(bin.y):
			return true
	return false


func _on_item_input(event: InputEvent, key: String) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_on_grid_input(event)
		return
	if event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		return
	get_viewport().set_input_as_handled()
	if event.button_index == MOUSE_BUTTON_LEFT and not _state.grabbed_shortcut.is_empty():
		_state.cancel_shortcut_drag()
		_state.state_changed.emit()
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		_consume_or_equip(key)
	elif event.button_index == MOUSE_BUTTON_LEFT:
		if int(_state.inventory_operation.get("invOp", OP_NONE)) != OP_NONE:
			call_deferred("_select_operation_item", key)
		else:
			call_deferred("_grab_item", key)


func _on_grid_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and not _state.grabbed_shortcut.is_empty():
			_state.cancel_shortcut_drag()
			_state.state_changed.emit()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			var max_row := _max_scroll_row()
			if max_row <= 0:
				return
			_scroll_value = maxf(0.0, _scroll_value - 1.0 / max_row)
			_refresh()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var max_row := _max_scroll_row()
			if max_row <= 0:
				return
			_scroll_value = minf(1.0, _scroll_value + 1.0 / max_row)
			_refresh()
		elif event.button_index == MOUSE_BUTTON_LEFT and not _state.grabbed_item.is_empty():
			_place_grabbed(Vector2i(floori(event.position.x / CELL_SIZE), floori(event.position.y / CELL_SIZE) + _scroll_row))


func _on_slider_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_slider_dragging = event.pressed
		$Slider.modulate = Color.WHITE if _slider_dragging else Color(0.5, 0.5, 0.5, 1.0)
		if event.pressed:
			_set_slider_from_track_y(event.position.y)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _slider_dragging:
		_set_slider_from_track_y(event.position.y)
		get_viewport().set_input_as_handled()


func _set_slider_from_track_y(track_y: float) -> void:
	_scroll_value = clampf((track_y + SLIDER_TRACK_TOP - SLIDER_BAR_TOP) / SLIDER_TRAVEL, 0.0, 1.0)
	_refresh()


func _update_scroll_from_value() -> void:
	_scroll_value = clampf(_scroll_value, 0.0, 1.0)
	_scroll_row = roundi(_max_scroll_row() * _scroll_value)
	$Slider.position.y = SLIDER_TRACK_TOP + _scroll_value * SLIDER_TRAVEL


func _grab_item(key: String) -> void:
	if not _bins.has(key):
		return
	if not _state.grabbed_shortcut.is_empty():
		_state.cancel_shortcut_drag()
		_state.state_changed.emit()
		return
	var bin: Dictionary = _bins[key]
	var old_grabbed: Dictionary = _state.grabbed_item
	var selected: Dictionary = bin.item
	_play_item_sound(int(selected.get("itemID", 0)))
	_grabbed_origin = Vector2i(bin.x, bin.y)
	_state.inventory.erase(selected)
	_bins.erase(key)
	if not old_grabbed.is_empty():
		_play_item_sound(int(old_grabbed.get("itemID", 0)))
		_state.inventory.append(old_grabbed)
		var old_size := _item_grid_size(int(old_grabbed.get("itemID", 0)))
		_bins[_item_key(old_grabbed)] = {"x": _grabbed_origin.x, "y": _grabbed_origin.y, "w": old_size.x, "h": old_size.y, "item": old_grabbed}
	_state.grabbed_item = selected
	_state.state_changed.emit()


func _place_grabbed(grid: Vector2i) -> void:
	var item: Dictionary = _state.grabbed_item
	_play_item_sound(int(item.get("itemID", 0)))
	var size := _item_grid_size(int(item.get("itemID", 0)))
	var x := grid.x - floori(size.x * 0.5)
	var y := grid.y - floori(size.y * 0.5)
	if x < 0 or x + size.x > GRID_COLUMNS or y < 0 or _occupied(x, y, size.x, size.y):
		var fallback := _find_free_position(size.x, size.y)
		x = fallback.x
		y = fallback.y
	_state.inventory.append(item)
	_bins[_item_key(item)] = {"x": x, "y": y, "w": size.x, "h": size.y, "item": item}
	_state.grabbed_item = {}
	_state.state_changed.emit()


func _consume_or_equip(key: String) -> Error:
	if not _bins.has(key):
		return ERR_INVALID_PARAMETER
	return _use_inventory_item(_bins[key].item)


func _use_inventory_item(item: Dictionary) -> Error:
	var item_type: String = _resources.item_type(int(item.get("itemID", 0)))
	if item_type in ["恢复药水", "强化药水", "技能书"] or (item_type == "传送卷轴" and _resources.item_name(int(item.get("itemID", 0))) == "随机传送卷"):
		var error := NetworkClient.send_consume_item(item.get("itemID", 0), item.get("seqID", 0), 1)
		if error == ERR_BUSY:
			return error
		_play_item_sound(int(item.get("itemID", 0)))
		return error
	var wear_types := {"衣服": 1, "头盔": 2, "武器": 3, "鞋": 4, "项链": 5, "手镯": 6, "戒指": 8}
	if wear_types.has(item_type):
		_play_item_sound(int(item.get("itemID", 0)))
		var wear_type: int = wear_types[item_type]
		if not _resources.item_can_wear(int(item.get("itemID", 0)), wear_type, bool(_state.player_gender)):
			return ERR_INVALID_PARAMETER
		return NetworkClient.send_request_equip_wear(item.get("itemID", 0), item.get("seqID", 0), wear_type)
	return ERR_INVALID_PARAMETER


func _play_item_sound(item_id: int) -> void:
	if item_id > 0:
		AudioService.play_seff_at(_resources.item_sound_effect(item_id), 0, 0, 0, 0)


func _select_operation_item(key: String) -> void:
	var bin: Dictionary = _bins.get(key, {})
	if bin.is_empty():
		return
	var item: Dictionary = bin.item
	var operation: Dictionary = _state.inventory_operation
	var allowed: Array = operation.get("typeList", [])
	if not allowed.has(_resources.item_type(int(item.get("itemID", 0)))):
		_state.add_chat_log("该物品类型不能用于当前操作", 3)
		_selected_key = ""
		return
	_selected_key = key
	_state.inventory_operation_cost = {}
	NetworkClient.send_npc_event(operation.get("uid", 0), "", operation.get("queryTag", ""), "%d:%d" % [item.get("itemID", 0), item.get("seqID", 0)])
	_refresh()


func _commit_operation() -> Error:
	if _selected_key.is_empty() or not _bins.has(_selected_key):
		return ERR_INVALID_PARAMETER
	var item: Dictionary = _bins[_selected_key].item
	var operation: Dictionary = _state.inventory_operation
	if int(operation.get("invOp", OP_NONE)) == OP_NONE:
		return ERR_INVALID_PARAMETER
	var allowed: Array = operation.get("typeList", [])
	if not allowed.has(_resources.item_type(int(item.get("itemID", 0)))):
		return ERR_INVALID_PARAMETER
	return NetworkClient.send_npc_event(operation.get("uid", 0), "", operation.get("commitTag", ""), "%d:%d" % [item.get("itemID", 0), item.get("seqID", 0)])


func _refresh_operation() -> void:
	var mode := int(_state.inventory_operation.get("invOp", OP_NONE))
	$Title.text = {OP_NONE: "【背包】", OP_TRADE: "【请选择出售物品】", OP_SECURE: "【请选择存储物品】", OP_REPAIR: "【请选择修理物品】"}.get(mode, "【背包】")
	$SortButton.visible = mode == OP_NONE
	var show_operation := mode != OP_NONE and not _selected_key.is_empty()
	$OperationBackground.visible = show_operation
	$OperationButton.visible = show_operation
	if mode == OP_TRADE:
		$OperationButton.texture_normal = TRADE_NORMAL
		$OperationButton.texture_pressed = TRADE_DOWN
	elif mode == OP_SECURE:
		$OperationButton.texture_normal = SECURE_NORMAL
		$OperationButton.texture_pressed = SECURE_DOWN
	else:
		$OperationButton.texture_normal = REPAIR_NORMAL
		$OperationButton.texture_pressed = REPAIR_DOWN
	var cost: Dictionary = _state.inventory_operation_cost
	var cost_matches := false
	if show_operation and not cost.is_empty() and _bins.has(_selected_key):
		var selected_item: Dictionary = _bins[_selected_key].item
		cost_matches = int(cost.get("itemID", 0)) == int(selected_item.get("itemID", -1)) and int(cost.get("seqID", 0)) == int(selected_item.get("seqID", -1))
	$OperationCost.visible = cost_matches
	$OperationCost.text = _format_gold(int(cost.get("cost", 0)))


func _close_operation() -> void:
	_selected_key = ""
	_state.clear_inventory_operation()


func _repack() -> void:
	var pack_method := _repack_index
	_repack_index += 1
	var items: Array = _state.inventory.duplicate()
	items.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return _repack_item_before(left, right, pack_method)
	)
	_bins.clear()
	for item: Dictionary in items:
		var size := _item_grid_size(int(item.get("itemID", 0)))
		var position := _find_free_position(size.x, size.y)
		_bins[_item_key(item)] = {"x": position.x, "y": position.y, "w": size.x, "h": size.y, "item": item}
	_scroll_row = 0
	_scroll_value = 0.0
	_refresh()


func _repack_item_before(left: Dictionary, right: Dictionary, pack_method: int) -> bool:
	var left_key := _repack_sort_key(left, pack_method)
	var right_key := _repack_sort_key(right, pack_method)
	for index in range(left_key.size()):
		if left_key[index] == right_key[index]:
			continue
		return left_key[index] > right_key[index] if pack_method % 2 else left_key[index] < right_key[index]
	return false


func _repack_sort_key(item: Dictionary, pack_method: int) -> Array:
	var item_id := int(item.get("itemID", 0))
	var size := _item_grid_size(item_id)
	var key: Array = [size.x * size.y, item_id, _resources.item_type(item_id)]
	var swap_index := absi(pack_method) % key.size()
	var first: Variant = key[0]
	key[0] = key[swap_index]
	key[swap_index] = first
	return key


func _max_scroll_row() -> int:
	var rows := 0
	for bin in _bins.values():
		rows = maxi(rows, int(bin.y) + int(bin.h))
	return maxi(0, rows - GRID_VISIBLE_ROWS)


func _item_key(item: Dictionary) -> String:
	return "%d:%d" % [item.get("itemID", 0), item.get("seqID", 0)]
