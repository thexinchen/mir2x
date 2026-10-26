extends Node

const Resources = preload("res://scripts/game/actor_resource.gd")


func _ready() -> void:
	var resources := Resources.new()
	resources.configure_default()
	var hp := resources.item_potion_effect(6)
	var mp := resources.item_potion_effect(10)
	if hp.is_empty() or mp.is_empty():
		_fail("generate potion_effect.m2xmeta with the updated hero metadata exporter first")
		return
	if hp.flags != 1 or hp.hp != PackedInt32Array([10, 0]) or hp.hp_pulse != PackedInt32Array([20, 1, 3000, 2]) or hp.mp != PackedInt32Array([0, 0]):
		_fail("small HP potion does not match the actual same-name server buff")
		return
	if mp.flags != 1 or mp.mp != PackedInt32Array([10, 0]) or mp.mp_pulse != PackedInt32Array([20, 1, 3000, 2]) or mp.hp != PackedInt32Array([0, 0]):
		_fail("small MP potion does not match the actual same-name server buff")
		return
	if not resources.item_potion_effect(824).is_empty():
		_fail("weapon was incorrectly exported as a potion effect")
		return
	var root := "user://potion_effect_metadata_smoke"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root.path_join("sprites")))
	var path := root.path_join("sprites/potion_effect.m2xmeta")
	var original := FileAccess.get_file_as_bytes(resources.base_path.path_join("sprites/potion_effect.m2xmeta"))
	var count := resources.potion_effects.size()
	var scoped := Resources.new()
	scoped.base_path = root
	var duplicate := original.duplicate()
	duplicate.encode_u32(72, duplicate.decode_u32(12))
	var wrong_version := original.duplicate()
	wrong_version.encode_u32(4, 99)
	for sample in [{"bytes": original, "valid": true}, {"bytes": original.slice(0, original.size() - 1), "valid": false}, {"bytes": PackedByteArray(), "valid": false}, {"bytes": duplicate, "valid": false}, {"bytes": wrong_version, "valid": false}]:
		var data: PackedByteArray = sample.bytes
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(data)
		file.close()
		scoped.call("_load_potion_effects")
		if (sample.valid and scoped.potion_effects.size() != count) or (not sample.valid and not scoped.potion_effects.is_empty()):
			_fail("invalid or truncated metadata left partial/stale effects")
			return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root.path_join("sprites")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root))
	scoped.call("_load_potion_effects")
	if not scoped.potion_effects.is_empty():
		_fail("missing optional metadata retained old effects")
		return
	print("POTION EFFECT METADATA PASS: %d backend potion records, HP/MP flat and percentage values, duration/tps, unrelated item exclusion, truncated/empty/missing/duplicate/version rejection" % count)
	get_tree().quit()


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
