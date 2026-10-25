extends "res://scripts/game/closable_panel.gd"

const Resources = preload("res://scripts/game/actor_resource.gd")
const WearPanel = preload("res://scripts/game/player_state_panel.gd")
const Formatter = preload("res://scripts/game/item_tooltip_formatter.gd")
const Tooltip = preload("res://scripts/game/item_tooltip_renderer.gd")
var _resources: RefCounted = Resources.new()
var inspected_uid := 0
const SLOT_NAMES := {4: "鞋", 5: "项链", 6: "手镯", 7: "手镯", 8: "戒指", 9: "戒指", 10: "火把", 11: "护身符"}


func _ready() -> void:
	super._ready()
	_resources.configure_default()
	Tooltip.configure($ItemTooltip, true, true)


func set_actor(uid: int, actor: Dictionary, desp: Dictionary) -> void:
	inspected_uid = uid
	$Name.text = str(actor.get("name", uid))
	$CharacterLayers.set_appearance(bool(actor.get("gender", false)), desp)
	for child in $EquipmentSlots.get_children():
		child.free()
	$ItemTooltip.hide()
	var wear: Dictionary = desp.get("wear", {})
	for location in WearPanel.WEAR_GRIDS:
		var grid: Rect2 = WearPanel.WEAR_GRIDS[location]
		var slot := Control.new()
		slot.name = "Slot%d" % location
		slot.position = grid.position
		slot.size = grid.size
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		$EquipmentSlots.add_child(slot)
		var item: Dictionary = wear.get(location, {}).duplicate(true)
		slot.set_meta("item", item)
		if location >= 4:
			var frame := Panel.new()
			frame.size = slot.size
			frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0, 0, 0, 0.25)
			style.border_color = Color(0.6, 0.5, 0.3, 0.7)
			style.set_border_width_all(1)
			frame.add_theme_stylebox_override("panel", style)
			slot.add_child(frame)
		if item.is_empty():
			if SLOT_NAMES.has(location):
				var label := Label.new()
				label.text = SLOT_NAMES[location]
				label.size = slot.size
				label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				label.add_theme_font_size_override("font_size", 11)
				label.modulate = Color(0.7, 0.65, 0.5)
				label.mouse_filter = Control.MOUSE_FILTER_IGNORE
				slot.add_child(label)
			continue
		if location >= 4:
			var frame: Dictionary = _resources.frame("item", _resources.item_package_gfx_id(item.get("itemID", 0)) | 0x01000000)
			if not frame.is_empty():
				var image := TextureRect.new()
				image.name = "Icon"
				image.texture = frame.texture
				image.position = (slot.size - Vector2(image.texture.get_size())) / 2.0
				image.mouse_filter = Control.MOUSE_FILTER_IGNORE
				slot.add_child(image)
		slot.mouse_entered.connect(_show_item.bind(item))
		slot.mouse_exited.connect(func(): $ItemTooltip.hide())


func _show_item(item: Dictionary) -> void:
	var lines: Array[String] = Formatter.plain_layout_lines(item, _resources)
	Tooltip.show_lines($ItemTooltip, lines, 220.0, 40.0, Vector2(10, 10), 15.0, 12)
	Tooltip.update_position($ItemTooltip, false)


func _process(_delta: float) -> void:
	if $ItemTooltip.visible:
		if is_visible_in_tree():
			Tooltip.update_position($ItemTooltip, false)
		else:
			$ItemTooltip.hide()
