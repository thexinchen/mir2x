extends Node

func _ready() -> void:
	GameState.set_player_online({"uid": 101, "name": "aura lifecycle", "map_uid": 24, "x": 3, "y": 3})
	GameState.player_action_type = 2
	GameState.update_health(100, 100, 100, 100)
	GameState.update_creature(202, {"uid": 202, "type": 2, "action_type": 2, "hp": 100, "health_initialized": true})
	for uid in [101, 202]:
		if not _aura(uid, "魔法盾", 13) or not _aura(uid, "阴阳法环", 73):
			_fail("live aura fixture rejected")
			return
	# The caster is202, but this finite strike belongs to target101.
	GameState.add_cast_magic_attachment({"uid": 202, "aimUID": 101, "magic": 5}, "雷电术")
	GameState.trigger_shield_hit(101)
	GameState.update_entity_health({"uid": 101, "hp": 0, "maxHP": 100, "mp": 100, "maxMP": 100})
	if GameState.attached_magic_effects.size() != 3 or _aura(101, "魔法盾", 13):
		_fail("self death retained aura or accepted delayed cast")
		return
	GameState.update_entity_health({"uid": 101, "hp": 100, "maxHP": 100, "mp": 100, "maxMP": 100})
	if GameState.attached_magic_effects.size() != 3 or not _aura(101, "魔法盾", 13):
		_fail("revival resurrected old aura or blocked a new cast")
		return
	GameState.update_entity_health({"uid": 202, "hp": 0, "maxHP": 100, "mp": 100, "maxMP": 100})
	if GameState.attached_magic_effects.size() != 2 or _aura(202, "阴阳法环", 73):
		_fail("remote death retained aura or accepted delayed cast")
		return
	GameState.update_creature(202, {"uid": 202, "type": 2, "action_type": 2, "hp": 100, "health_initialized": true})
	if not _aura(202, "魔法盾", 13):
		_fail("remote live aura fixture rejected")
		return
	GameState.remove_creature(202)
	# Recreate before the renderer gets a frame to prune missing targets.
	GameState.update_creature(202, {"uid": 202, "type": 2, "action_type": 2})
	if GameState.attached_magic_effects.size() != 2:
		_fail("same-frame UID reuse inherited a stale aura")
		return
	if GameState.attached_magic_effects[0].kind != "thunderbolt":
		_fail("caster removal deleted a finite effect attached to another target")
		return
	_aura(202, "阴阳法环", 73)
	GameState.update_creature(202, {"uid": 202, "type": 2, "action_type": 13})
	if GameState.attached_magic_effects.size() != 2 or _aura(202, "魔法盾", 13):
		_fail("dead actor snapshot retained aura or accepted late cast")
		return
	GameState.player_action_type = 13
	if _aura(101, "阴阳法环", 73):
		_fail("death action accepted aura with positive but stale health")
		return
	GameState.remove_actor_attachments(0)
	if GameState.attached_magic_effects.size() != 2:
		_fail("zero UID removed unrelated effects")
		return
	print("AURA LIFECYCLE PASS: self/remote health death, hit removal, delayed cast, revival, same-frame UID reuse, target ownership")
	get_tree().quit()

func _aura(uid: int, name: String, magic: int) -> bool:
	return GameState.add_cast_magic_attachment({"uid": uid, "magic": magic}, name)

func _fail(message: String) -> void:
	push_error("AURA LIFECYCLE " + message)
	get_tree().quit(1)
