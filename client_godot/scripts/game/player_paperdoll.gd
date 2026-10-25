extends Control

const ActorResourceScript = preload("res://scripts/game/actor_resource.gd")

var _state: Node
var _resources: RefCounted = ActorResourceScript.new()
var _appearance: Dictionary = {}


func set_appearance(gender: bool, desp: Dictionary) -> void:
	_appearance = {"gender": gender, "desp": desp.duplicate(true)}
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_state = get_node("/root/GameState")
	_resources.configure_default()
	_state.state_changed.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	var anchor := Vector2(72, 142)
	var gender: bool = _appearance.get("gender", _state.player_gender)
	var desp: Dictionary = _appearance.get("desp", _state.player_desp)
	_draw_equip_frame(0 if gender else 1, anchor)
	var wear: Dictionary = desp.get("wear", {}) if not _appearance.is_empty() else _state.wear
	for location in [1, 3, 2]:
		var item: Dictionary = wear.get(location, {})
		var item_id: int = item.get("itemID", 0)
		if item_id == 0:
			continue
		var package_gfx_id: int = _resources.item_package_gfx_id(item_id)
		if package_gfx_id >= 0:
			_draw_equip_frame(package_gfx_id | 0x01000000, anchor)
	if not wear.has(2):
		var hair: int = desp.get("hair", 0)
		if hair > 0:
			_draw_equip_frame((0x3C if gender else 0x46) + hair - 1, anchor)


func _draw_equip_frame(key: int, anchor: Vector2) -> void:
	var sprite: Dictionary = _resources.frame("equip", key)
	if sprite.is_empty():
		return
	var offset: Vector2i = sprite.offset
	draw_texture(sprite.texture, anchor + Vector2(offset))
