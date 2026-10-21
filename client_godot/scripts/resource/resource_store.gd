extends RefCounted

# 世界/精灵资源读取入口，独立于具体面板与渲染节点。
#
# 职责：
#   1. 解析资源根目录（环境变量 MIR2X_WORLD_RES / res://world_res / 可执行文件同级 world_res）；
#   2. 首选直接读取 ZSDB 容器（build/Release/res/texture/*.zsdb 由 install_res 生成），
#      不再依赖 godotworldres 导出的 37 万个 PNG；
#   3. 当 ZSDB 缺席时回退到旧解包目录（sprites/<family>/<KEY>.png + <family>.m2xindex + textures/），
#      保证迁移期与旧资源目录都能跑。
#
# 精灵偏移（dx/dy）直接从 ZSDB 文件名解析，与 tools/godotworldres 生成 .m2xindex 的规则一致；
# 旧目录模式下才读取 .m2xindex。

const ZsdbArchiveScript = preload("res://scripts/resource/zsdb_archive.gd")

const SPRITE_FAMILIES := [
	"hero", "hair", "helmet", "weapon", "monster",
	"npc", "item", "equip", "proguse", "selectchar", "magic",
]
const MAP_TEXTURE_ARCHIVE := "map"
const LEGACY_INDEX_MAGIC := "M2SP"

static var _shared = null

var base_path := ""
var texture_path := ""
var last_error := ""
var last_source := ""

var _sprite_archives: Dictionary = {}
var _sprite_offsets: Dictionary = {}
var _texture_archive = null
var _texture_archive_loaded := false


static func shared():
	if _shared == null:
		_shared = new()
		_shared.configure()
	return _shared


static func reset_shared() -> void:
	_shared = null


func is_ready() -> bool:
	return not base_path.is_empty()


func configure() -> bool:
	var candidates := candidate_roots()
	for candidate in candidates:
		if _looks_like_root(candidate):
			return configure_at(candidate)
	last_error = "未找到世界资源目录，候选：%s" % [", ".join(candidates)]
	return false


# 幂等：同路径重复调用直接复用已解析的 ZSDB 索引，换地图时不会反复重建。
func configure_at(root: String) -> bool:
	if root.is_empty():
		last_error = "世界资源目录为空"
		return false
	if root == base_path and is_ready():
		return true
	base_path = root
	texture_path = _pick_texture_root(root)
	_sprite_archives.clear()
	_sprite_offsets.clear()
	_texture_archive = null
	_texture_archive_loaded = false
	last_error = ""
	if texture_path.is_empty():
		last_error = "%s 下没有 texture/*.zsdb，且找不到旧解包目录" % root
	return true


func adopt(root: String) -> bool:
	if root.is_empty() or root == base_path:
		return is_ready() or configure()
	return configure_at(root)


static func candidate_roots() -> Array[String]:
	var roots: Array[String] = []
	var env_path := OS.get_environment("MIR2X_WORLD_RES")
	if not env_path.is_empty():
		roots.append(env_path)
	roots.append("res://world_res")
	if not OS.has_feature("editor"):
		roots.append(OS.get_executable_path().get_base_dir().path_join("world_res"))
	return roots


func sprite_frame(family: String, key: int) -> Dictionary:
	var archive = sprite_archive(family)
	if archive != null and archive.has(key):
		var bytes: PackedByteArray = archive.read(key)
		if bytes.is_empty():
			last_error = archive.last_error
			return {}
		last_source = "zsdb:%s" % family
		return {"bytes": bytes, "offset": archive.frame_offset(key)}

	var legacy := "%s/sprites/%s/%08X.png" % [base_path, family, key]
	var legacy_bytes := FileAccess.get_file_as_bytes(legacy)
	if legacy_bytes.is_empty():
		return {}
	last_source = "png:%s" % family
	return {"bytes": legacy_bytes, "offset": _legacy_offset(family, key)}


func has_sprite(family: String, key: int) -> bool:
	var archive = sprite_archive(family)
	if archive != null:
		return archive.has(key)
	return FileAccess.file_exists("%s/sprites/%s/%08X.png" % [base_path, family, key])


func sprite_archive(family: String):
	if _sprite_archives.has(family):
		return _sprite_archives[family]
	var archive = null
	for directory in _archive_roots():
		var candidate: String = directory.path_join("%s.zsdb" % family)
		if not FileAccess.file_exists(candidate):
			continue
		var loaded = ZsdbArchiveScript.new()
		if loaded.open(candidate):
			archive = loaded
		else:
			last_error = loaded.last_error
		break
	_sprite_archives[family] = archive
	return archive


func texture_bytes(texture_id: int) -> PackedByteArray:
	var archive = texture_archive()
	if archive != null and archive.has(texture_id):
		var bytes: PackedByteArray = archive.read(texture_id)
		if not bytes.is_empty():
			last_source = "zsdb:map"
			return bytes
	if base_path.is_empty():
		return PackedByteArray()
	var legacy := "%s/textures/%08X.png" % [base_path, texture_id]
	var legacy_bytes := FileAccess.get_file_as_bytes(legacy)
	if not legacy_bytes.is_empty():
		last_source = "png:map"
	return legacy_bytes


func texture_archive():
	if _texture_archive_loaded:
		return _texture_archive
	_texture_archive_loaded = true
	for directory in _archive_roots():
		var candidate: String = directory.path_join("%s.zsdb" % MAP_TEXTURE_ARCHIVE)
		if not FileAccess.file_exists(candidate):
			continue
		var loaded = ZsdbArchiveScript.new()
		if loaded.open(candidate):
			_texture_archive = loaded
		else:
			last_error = loaded.last_error
		break
	return _texture_archive


func meta_path(file_name: String) -> String:
	return "%s/sprites/%s" % [base_path, file_name]


func map_path(map_id: int) -> String:
	return "%s/maps/%08X.m2xmap" % [base_path, map_id]


func has_map(map_id: int) -> bool:
	return FileAccess.file_exists(map_path(map_id))


func _archive_roots() -> Array[String]:
	var roots: Array[String] = []
	if not texture_path.is_empty():
		roots.append(texture_path)
	if not base_path.is_empty():
		roots.append(base_path)
	return roots


func _looks_like_root(root: String) -> bool:
	if root.is_empty():
		return false
	if FileAccess.file_exists(root.path_join("texture").path_join("%s.zsdb" % MAP_TEXTURE_ARCHIVE)):
		return true
	for family in SPRITE_FAMILIES:
		if FileAccess.file_exists(root.path_join("texture").path_join("%s.zsdb" % family)):
			return true
	if FileAccess.file_exists(root.path_join("sprites").path_join("monster.m2xmeta")):
		return true
	return false


func _pick_texture_root(root: String) -> String:
	var env_path := OS.get_environment("MIR2X_TEXTURE_RES")
	if not env_path.is_empty() and FileAccess.file_exists(env_path.path_join("%s.zsdb" % MAP_TEXTURE_ARCHIVE)):
		return env_path
	var side_by_side: String = root.path_join("texture")
	if FileAccess.file_exists(side_by_side.path_join("%s.zsdb" % MAP_TEXTURE_ARCHIVE)):
		return side_by_side
	for family in SPRITE_FAMILIES:
		if FileAccess.file_exists(side_by_side.path_join("%s.zsdb" % family)):
			return side_by_side
	# 旧解包目录：没有 zsdb，但可能存在 sprites/<family>/ 与 textures/
	if DirAccess.dir_exists_absolute(root.path_join("sprites")):
		return ""
	return ""


func _legacy_offset(family: String, key: int) -> Vector2i:
	if not _sprite_offsets.has(family):
		_sprite_offsets[family] = _load_legacy_index(family)
	return _sprite_offsets[family].get(key, Vector2i.ZERO)


func _load_legacy_index(family: String) -> Dictionary:
	var offsets := {}
	var file := FileAccess.open("%s/sprites/%s.m2xindex" % [base_path, family], FileAccess.READ)
	if file == null:
		return offsets
	if file.get_buffer(4).get_string_from_ascii() != LEGACY_INDEX_MAGIC:
		return offsets
	if file.get_32() != 1:
		return offsets
	var count := file.get_32()
	for _index in range(count):
		var key := file.get_32()
		var dx := file.get_16()
		var dy := file.get_16()
		if dx & 0x8000:
			dx -= 0x10000
		if dy & 0x8000:
			dy -= 0x10000
		offsets[key] = Vector2i(dx, dy)
	return offsets
