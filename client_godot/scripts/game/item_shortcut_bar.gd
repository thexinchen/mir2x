extends Control

const Model = preload("res://scripts/game/mir3_item_shortcuts.gd")
const ActorResource = preload("res://scripts/game/actor_resource.gd")
const SLOT_X := [65, 105, 146, 186, 226, 266, 306, 346, 386, 426]
signal slot_action_requested(action: int, slot: int)
var inventory_panel: Control
var _resources := ActorResource.new()
var _state: Node
var _refresh_queued := false
var _display_items: Array = []


func _ready() -> void:
	_state = get_node("/root/GameState")
	_resources.configure_default()
	position = Vector2(0, -40)
	size = Vector2(480, 40)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_state.state_changed.connect(_queue_refresh)
	NetworkClient.item_use_state_changed.connect(_queue_refresh)
	_refresh()


func _queue_refresh() -> void:
	if _refresh_queued: return
	_refresh_queued = true
	call_deferred("_refresh")


func _refresh() -> void:
	_refresh_queued = false
	var items: Array = []
	for slot in Model.SLOT_COUNT:
		items.append(_state.item_shortcuts.resolve(slot, _state.inventory, _state.grabbed_item, NetworkClient.pending_item_use) if _state.inventory_initialized or not NetworkClient.is_connected_to_server() else _state.item_shortcuts.bindings[slot].get("item", {}))
	# Scene/chat changes share state_changed; leave unchanged HUD nodes intact.
	if items == _display_items: return
	_display_items = items.duplicate(true)
	for child in get_children(): child.free()
	for slot in Model.SLOT_COUNT:
		var holder := Panel.new()
		holder.name = "Slot%d" % slot
		holder.position = Vector2(SLOT_X[slot], 8)
		holder.size = Vector2(29, 32)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.03, 0.03, 0.02, 0.85)
		style.border_color = Color(0.45, 0.40, 0.25)
		style.set_border_width_all(1)
		holder.add_theme_stylebox_override("panel", style)
		holder.gui_input.connect(_slot_input.bind(slot))
		add_child(holder)
		var item: Dictionary = items[slot]
		if not item.is_empty():
			holder.tooltip_text = "%s ×%d" % [_resources.item_name(int(item.itemID)), int(item.count)]
			var frame: Dictionary = _resources.frame("item", _resources.item_package_gfx_id(int(item.itemID)) | 0x01000000)
			if not frame.is_empty():
				var icon := TextureRect.new()
				icon.texture = frame.texture
				icon.position = Vector2.ONE
				icon.size = Vector2(27, 30)
				icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
				icon.modulate.a = 1.0 if int(item.count) > 0 else 0.35
				holder.add_child(icon)
			if int(item.count) != 1: _label(holder, str(item.count), Vector2(0, 16), HORIZONTAL_ALIGNMENT_RIGHT)
		_label(holder, str((slot + 1) % 10), Vector2.ZERO, HORIZONTAL_ALIGNMENT_LEFT)


func _label(holder: Control, text: String, at: Vector2, alignment: HorizontalAlignment) -> void:
	var label := Label.new()
	label.text = text
	label.position = at
	label.size = Vector2(28, 14)
	label.horizontal_alignment = alignment
	label.add_theme_font_size_override("font_size", 10)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(label)


func activate_slot(slot: int, button: int) -> int:
	if slot < 0 or slot >= Model.SLOT_COUNT: return 0
	if button == MOUSE_BUTTON_LEFT:
		if not _state.grabbed_item.is_empty():
			_state.cancel_shortcut_drag()
			var item: Dictionary = _state.grabbed_item
			if not _state.item_shortcuts.bind_item(slot, item, _resources.item_is_packable(int(item.itemID))): return 0
			var present := false
			for current: Dictionary in _state.inventory:
				if current.get("itemID", 0) == item.get("itemID", 0) and current.get("seqID", 0) == item.get("seqID", 0): present = true
			if not present: _state.inventory.append(item)
			_state.grabbed_item = {}
			_state.grabbed_shortcut = {}
		elif not _state.grabbed_shortcut.is_empty():
			_state.grabbed_shortcut = _state.item_shortcuts.place_drag(slot, _state.grabbed_shortcut)
		elif not _state.item_shortcuts.bindings[slot].is_empty():
			_state.grabbed_shortcut = _state.item_shortcuts.begin_drag(slot)
		else: return 0
		_state.state_changed.emit()
		slot_action_requested.emit(1, slot)
		return 1
	if button != MOUSE_BUTTON_RIGHT or inventory_panel == null: return 0
	var resolved: Dictionary = _state.item_shortcuts.resolve(slot, _state.inventory, _state.grabbed_item, NetworkClient.pending_item_use)
	if resolved.is_empty() or int(resolved.get("count", 0)) <= 0 or int(NetworkClient.get("_item_use_pending_token")) != 0: return 0
	var error: int = inventory_panel.call("_use_inventory_item", resolved)
	if error != OK and error != ERR_UNCONFIGURED: return 0
	slot_action_requested.emit(3, slot)
	return 3


func _slot_input(event: InputEvent, slot: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		activate_slot(slot, event.button_index)
		get_viewport().set_input_as_handled()
