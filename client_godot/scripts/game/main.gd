extends Control

# Game main scene - corresponds to ProcessRun in C++ client
# Manages: world rendering, HUD, input, network message handling

const Protocol = preload("res://scripts/network/protocol.gd")
const CerealReader = preload("res://scripts/network/cereal_reader.gd")
const ActorResourceScript = preload("res://scripts/game/actor_resource.gd")
const WorldPathfinderScript = preload("res://scripts/game/world_pathfinder.gd")
const Mir3TargetLockScript = preload("res://scripts/game/mir3_target_lock.gd")
const Mir3MovementScript = preload("res://scripts/game/mir3_movement.gd")
const RuntimeConfigPanelScript = preload("res://scripts/game/runtime_config_panel.gd")
const MINIMAP_PANEL_PATH := "res://scenes/game/panels/minimap.tscn"
const QUEST_PANEL_PATH := "res://scenes/game/panels/quest.tscn"
const NPC_CHAT_PANEL_PATH := "res://scenes/game/panels/npc_chat.tscn"
const PURCHASE_PANEL_PATH := "res://scenes/game/panels/purchase.tscn"
const AUCTION_PANEL_PATH := "res://scenes/game/panels/auction.tscn"
const FRIEND_CHAT_PANEL_PATH := "res://scenes/game/panels/friend_chat.tscn"
const SECURED_ITEMS_PANEL_PATH := "res://scenes/game/panels/secured_items.tscn"
const TEAM_PANEL_PATH := "res://scenes/game/panels/team.tscn"
const HORSE_PANEL_PATH := "res://scenes/game/panels/horse.tscn"
const GUILD_PANEL_PATH := "res://scenes/game/panels/guild.tscn"
const INPUT_STRING_PANEL_PATH := "res://scenes/game/panels/input_string.tscn"
const RUNTIME_CONFIG_PANEL_PATH := "res://scenes/game/panels/runtime_config.tscn"
const SYS_QSTFSM := "_RSVD_NAME_QST_FSM_4194347313"

# ImMainUI draws its retained-mode boards in this fixed order every frame.
const EXTRA_PANEL_DRAW_LAYERS := {
	MINIMAP_PANEL_PATH: 1,
	NPC_CHAT_PANEL_PATH: 2,
	FRIEND_CHAT_PANEL_PATH: 8,
	AUCTION_PANEL_PATH: 10,
	HORSE_PANEL_PATH: 11,
	GUILD_PANEL_PATH: 12,
	INPUT_STRING_PANEL_PATH: 13,
	RUNTIME_CONFIG_PANEL_PATH: 14,
	QUEST_PANEL_PATH: 15,
	TEAM_PANEL_PATH: 16,
	SECURED_ITEMS_PANEL_PATH: 17,
	PURCHASE_PANEL_PATH: 20,
}

@onready var world_renderer: Control = $WorldRenderer
@onready var inventory_panel: Control = %InventoryPanel
@onready var player_state_panel: Control = %PlayerStatePanel
@onready var skill_panel: Control = %SkillPanel
@onready var quick_bar: Control = %QuickBar
@onready var location_label: Label = $Location
@onready var control_panel: Control = $ControlPanel
@onready var grabbed_item_icon: TextureRect = $GrabbedItemIcon
@onready var skill_buff_hud: Control = $SkillBuffHUD
@onready var team_flag_cursor: TextureRect = $TeamFlagCursor
@onready var death_overlay: ColorRect = $DeathOverlay
@onready var fps_label: Label = $FPS
@onready var map_loading_overlay: Control = $MapLoadingOverlay
@onready var map_loading_text: RichTextLabel = $MapLoadingOverlay/Panel/Text

var game_state: Node = null
var protocol: RefCounted = null

var _ping_pending: bool = false
var _ping_tick: int = 0
var _last_ping_sent_ms: int = 0

const EXTRA_PANELS := {
	KEY_H: "res://scenes/game/panels/horse.tscn",
	KEY_G: "res://scenes/game/panels/guild.tscn",
	KEY_Q: "res://scenes/game/panels/quest.tscn",
	KEY_T: "res://scenes/game/panels/team.tscn",
	KEY_F: "res://scenes/game/panels/friend_chat.tscn",
	KEY_O: "res://scenes/game/panels/runtime_config.tscn",
	KEY_M: MINIMAP_PANEL_PATH,
}

var _extra_panel_nodes: Dictionary = {}
var _pending_purchase: Dictionary = {}
var _pending_chat_group: Array = []
var _resources: RefCounted = ActorResourceScript.new()
var _pathfinder: RefCounted = WorldPathfinderScript.new()
var _next_strike := false
var _swing_magic: Dictionary = {}
var _locked_magic_target_uid := 0
var _magic_focus_uid := 0
var _last_impulse_magic_ms := -3000
var _last_magic_request_ms := -500
var _action_request_gate: RefCounted = preload("res://scripts/game/mir3_request_gate.gd").new()
var _move_path: Array[Vector2i] = []
var _move_step_timer := 0.0
var _ground_input := Mir3MovementScript.new()
var _ground_path_active := false
var _ground_path_goal := Vector2i(-1, -1)
var _last_attack_ms := -10000
var _last_npc_dialogue_ms := -1501
var _last_corpse_interaction_ms := -1001
var _pending_spell_action: Dictionary = {}
var _chase_target_uid := 0
var _shift_chase_active := false
var _follow_focus_uid := 0
var _attack_focus_uid := 0
var _mine_target := Vector2i(-1, -1)
var _pickup_action_timer := -1.0
var _player_action_timer := -1.0
var _player_forced_action_queue: Array[Dictionary] = []
var _player_server_action_queue: Array[Dictionary] = []
var _player_server_move_active := false
var _player_post_forced_action: Dictionary = {}
var _team_flag_active := false
var _summon_spawn_blockers: Dictionary = {}
var _map_loading_hide_serial := 0

# C++ walk motion is six frames at SYS_DEFSPEED (100 ms per frame). Dispatch the
# next one-hop action at the same boundary so a path has no artificial idle gap.
const MOVE_STEP_SECONDS := 0.60
const FORCED_MOVE_SPEED := 500
const PING_INTERVAL_MS := 10_000
const MAP_LOADING_COMPLETE_HOLD_SECONDS := 0.15
const MAP_PRELOAD_WINDOW_WIDTH := 1200
const MAP_PRELOAD_WINDOW_HEIGHT := 1200
const MAP_OBJECT_MAX_WIDTH := 3
const MAP_OBJECT_MAX_HEIGHT := 25
const U32_MASK := 0xFFFFFFFF
const BUFF_TYPE_SHIELD := 1
const BUFF_STATE_OFF := 2

const SWING_MAGIC_NAMES := ["刺杀剑术", "烈火剑法", "翔空剑法", "莲月剑法", "半月弯刀", "十方斩"]
const TARGET_MAGIC_NAMES := [
	"圣言术", "治愈术", "困魔咒", "施毒术", "云寂术", "回生术", "雷电术", "火球术", "大火球", "冰咆哮",
	"龙卷风", "霹雳掌", "风掌", "击风", "月魂断玉", "月魂灵波", "斗转星移", "爆裂火焰", "地狱雷光", "怒神霹雳",
	"灵魂火符", "冰月神掌", "冰月震天", "乾坤大挪移", "群体治愈术", "幽灵盾", "神圣战甲术", "强魔震法", "猛虎强势",
	"集体隐身术", "移花接玉", "诱惑之光",
]
const GROUND_MAGIC_NAMES := ["火墙", "风震天", "地狱火", "冰沙掌", "魄冰刺", "疾光电影", "焰天火雨", "瞬息移动", "异形换位"]
const SELF_MAGIC_NAMES := ["隐身术", "凝血离魂", "妙影无踪", "魔法盾", "铁布衫", "阴阳法环", "抗拒火环", "破血狂杀", "召唤骷髅", "超强召唤骷髅", "召唤神兽"]
const SUMMON_MAGIC_BY_MONSTER := {
	"变异骷髅": "召唤骷髅",
	"超强骷髅": "超强召唤骷髅",
	"神兽": "召唤神兽",
}
const DELAYED_SUMMON_MONSTERS := ["变异骷髅", "超强骷髅"]
const MAGIC_STAGE_RUN := 2


func _ready() -> void:
	game_state = get_node("/root/GameState")
	protocol = Protocol.new()
	_resources.configure_default()
	world_renderer.actor_resource = _resources
	world_renderer.game_state = game_state
	
	inventory_panel.hide()
	player_state_panel.hide()
	skill_panel.hide()
	quick_bar.hide()
	team_flag_cursor.hide()
	skill_panel.z_index = 9
	skill_buff_hud.z_index = 5
	control_panel.z_index = 6
	location_label.z_index = 7
	quick_bar.z_index = 7
	inventory_panel.z_index = 18
	player_state_panel.z_index = 19
	
	# C++ location format: "mapName: x y", font 10 size 15, white, 23 px above the window bottom.
	location_label.add_theme_font_size_override("font_size", 15)
	location_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	
	NetworkClient.message_received.connect(_on_server_message)
	NetworkClient.connection_changed.connect(_on_action_connection_changed)
	game_state.state_changed.connect(_refresh_grabbed_item_icon)
	game_state.creature_removed.connect(_on_creature_removed)
	world_renderer.gui_input.connect(_on_world_gui_input)
	control_panel.connect("minimized_changed", _on_control_panel_minimized_changed)
	_refresh_grabbed_item_icon()
	_ensure_extra_panel(MINIMAP_PANEL_PATH)
	if game_state.player_uid != 0:
		map_loading_overlay.show()
		_on_map_load_progress(0, "")
	_resume_message_dispatch_after_loading_frame()
	
	if OS.has_environment("MIR2X_GAME_SCREENSHOT"):
		inventory_panel.show()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_GAME_SCREENSHOT"))
		get_tree().quit()


func _resume_message_dispatch_after_loading_frame() -> void:
	# Linux receives frame_post_draw reliably here, while the Windows/RDP
	# Compatibility renderer can leave this await suspended forever. Advance the
	# scene once, then mirror C++ ModalStringBoard::drawScreen(true) explicitly.
	await get_tree().process_frame
	RenderingServer.force_draw()
	NetworkClient.resume_message_dispatch()


func _on_world_gui_input(event: InputEvent) -> void:
	_unhandled_input(event)


func _process(delta: float) -> void:
	var motion_delta: float = world_renderer.advance_movement_clocks(delta)
	_process_player_action(motion_delta)
	_process_pickup_action(motion_delta)
	_process_ground_input(delta)
	_process_movement(motion_delta)
	# Update camera
	game_state.scroll_camera_to(world_renderer.player_draw_grid(), motion_delta)
	
	# Update location label
	var map_name: String = game_state.player_map_name
	if map_name.is_empty():
		map_name = "未知地图"
	location_label.text = "%s: %d %d" % [map_name, game_state.player_x, game_state.player_y]
	var locked_uid := _valid_locked_magic_target()
	if locked_uid != 0:
		# 672413/672444 displays the valid locked actor's name.
		location_label.text += "  锁定: %s" % game_state.get_creature(locked_uid).get("name", str(locked_uid))
	
	_process_ping()
	
	# Redraw world
	world_renderer.set_focus_channels(_magic_focus_uid, _follow_focus_uid, _attack_focus_uid)
	world_renderer.queue_redraw()
	_update_death_overlay()
	_update_fps_overlay()
	if grabbed_item_icon.visible:
		grabbed_item_icon.position = get_viewport().get_mouse_position() - grabbed_item_icon.size * 0.5
	_update_team_flag_cursor()


func _exit_tree() -> void:
	if _team_flag_active:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _refresh_grabbed_item_icon() -> void:
	var item: Dictionary = game_state.grabbed_item
	if item.is_empty():
		grabbed_item_icon.hide()
		grabbed_item_icon.texture = null
		return
	var item_id := int(item.get("itemID", 0))
	var icon: Dictionary = _resources.frame("item", _resources.item_package_gfx_id(item_id) | 0x01000000)
	if icon.is_empty():
		grabbed_item_icon.hide()
		grabbed_item_icon.texture = null
		return
	grabbed_item_icon.texture = icon.texture
	grabbed_item_icon.size = icon.texture.get_size()
	grabbed_item_icon.show()


func _input(event: InputEvent) -> void:
	# Releases must reach us even when a panel consumes the GUI event.
	if event is InputEventKey and event.keycode == KEY_SHIFT and not event.pressed:
		_cancel_shift_chase()
	if event is InputEventMouseButton and not event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		_release_ground_input()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_ground_input()


func _release_ground_input() -> void:
	_cancel_shift_chase()
	_ground_input.release()
	if _ground_path_active:
		_move_path.clear()
	_ground_path_active = false
	# Preserve the in-flight animation/cooldown; only unsent work is cancelled.


func _cancel_shift_chase() -> void:
	if _shift_chase_active:
		_move_path.clear()
		_chase_target_uid = 0
	_shift_chase_active = false


func _unhandled_input(event: InputEvent) -> void:
	if map_loading_overlay.visible:
		get_viewport().set_input_as_handled()
		return
	var purchase_panel := _extra_panel_nodes.get(PURCHASE_PANEL_PATH) as Control
	if purchase_panel != null and purchase_panel.visible:
		get_viewport().set_input_as_handled()
		return
	if not event.is_pressed() or event.is_echo():
		return
	if event is InputEventKey and quick_bar.visible:
		var quick_slot: int = event.keycode - KEY_1
		if quick_slot >= 0 and quick_slot < 6:
			quick_bar.call("activate_slot", quick_slot, MOUSE_BUTTON_RIGHT)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.keycode == KEY_QUOTELEFT and _magic_target_lock_enabled():
		_toggle_magic_target_lock()
		get_viewport().set_input_as_handled()
		return
	if _player_input_blocked() or not _player_forced_action_queue.is_empty():
		if event is InputEventKey:
			if event.keycode == KEY_ESCAPE:
				_center_hero()
			elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
				control_panel.call("focus_command")
				get_viewport().set_input_as_handled()
			elif not event.alt_pressed:
				_try_panel_hotkey(event.keycode)
		return
	if event is InputEventMouseButton:
		_handle_mouse_click(event)
		return
	if not event is InputEventKey:
		return
	if event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		control_panel.call("focus_command")
		get_viewport().set_input_as_handled()
		return
	
	# C++ key bindings: ESC=center hero, TAB=pickup, Alt+E=exit, Alt+F=fullscreen
	if event.keycode == KEY_ESCAPE:
		_center_hero()
	elif event.keycode == KEY_TAB:
		_request_pickup()
	elif event.alt_pressed:
		if event.keycode == KEY_E:
			get_tree().quit()
		elif event.keycode == KEY_F:
			var mode := DisplayServer.window_get_mode()
			if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif _try_magic_key(event):
		pass
	else:
		_try_panel_hotkey(event.keycode)


func _try_panel_hotkey(keycode: int) -> bool:
	if keycode == KEY_B:
		_toggle_panel(inventory_panel)
	elif keycode == KEY_C:
		_toggle_panel(player_state_panel)
	elif keycode == KEY_S:
		_toggle_panel(skill_panel)
	elif keycode == KEY_T:
		_on_control_panel_panel_requested(TEAM_PANEL_PATH)
	elif EXTRA_PANELS.has(keycode):
		_toggle_extra_panel(EXTRA_PANELS[keycode])
	else:
		return false
	return true


func handle_panel_escape() -> bool:
	# Child panels can receive _unhandled_key_input() before GameMain receives
	# _unhandled_input(), so repeat the two modal gates here before closing any
	# panel behind them.
	if map_loading_overlay.visible:
		get_viewport().set_input_as_handled()
		return true
	var purchase_panel := _extra_panel_nodes.get(PURCHASE_PANEL_PATH) as Control
	if purchase_panel != null and purchase_panel.visible:
		get_viewport().set_input_as_handled()
		return true
	# Match ImMainUI::processEvent(). Auction, NPC chat and minimap do not consume
	# Escape. Runtime config closes but deliberately returns false.
	var ordered_panels: Array[Control] = [
		_extra_panel_nodes.get(HORSE_PANEL_PATH) as Control,
		_extra_panel_nodes.get(GUILD_PANEL_PATH) as Control,
		_extra_panel_nodes.get(INPUT_STRING_PANEL_PATH) as Control,
		_extra_panel_nodes.get(RUNTIME_CONFIG_PANEL_PATH) as Control,
		_extra_panel_nodes.get(QUEST_PANEL_PATH) as Control,
		_extra_panel_nodes.get(TEAM_PANEL_PATH) as Control,
		_extra_panel_nodes.get(SECURED_ITEMS_PANEL_PATH) as Control,
		inventory_panel,
		player_state_panel,
		_extra_panel_nodes.get(FRIEND_CHAT_PANEL_PATH) as Control,
		skill_panel,
	]
	for panel in ordered_panels:
		if panel != null and panel.visible and panel.has_method("close_for_escape"):
			if bool(panel.call("close_for_escape")):
				get_viewport().set_input_as_handled()
				return true
	return false


func _player_dead() -> bool:
	return game_state.player_health_initialized and game_state.player_hp <= 0


func _player_input_blocked() -> bool:
	return not game_state.player_health_initialized or game_state.player_hp <= 0 or _player_server_move_active or not _player_server_action_queue.is_empty()


func _update_death_overlay() -> void:
	death_overlay.visible = _player_dead()


func _update_fps_overlay() -> void:
	var data: PackedByteArray = game_state.runtime_config.get(6, PackedByteArray())
	fps_label.visible = data.size() >= 2 and data[0] != 0 and data[1] != 0
	if fps_label.visible:
		_layout_fps_overlay(str(Engine.get_frames_per_second()))


func _layout_fps_overlay(text: String) -> Vector2i:
	var font := fps_label.get_theme_font("font")
	var font_size := fps_label.get_theme_font_size("font_size")
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var overlay_size := Vector2i(ceili(text_size.x) + 1, ceili(text_size.y))
	fps_label.text = text
	fps_label.offset_left = -overlay_size.x
	fps_label.offset_top = 0
	fps_label.offset_right = 0
	fps_label.offset_bottom = overlay_size.y
	return overlay_size


func _handle_mouse_click(event: InputEventMouseButton) -> void:
	var grid: Vector2i = world_renderer.grid_from_screen(int(event.position.x), int(event.position.y))
	var focus_uid: int = world_renderer.focus_uid_at_screen(event.position, event.button_index == MOUSE_BUTTON_LEFT)
	if _team_flag_active:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_set_team_flag_cursor(false)
			return
		if event.button_index == MOUSE_BUTTON_LEFT and focus_uid != 0:
			_request_team_flag_target(focus_uid)
			return
	if event.button_index == MOUSE_BUTTON_LEFT and focus_uid in [0, game_state.player_uid] and game_state.grabbed_item.is_empty():
		var mine_front := _ground_mining_front(grid, event.shift_pressed)
		if mine_front != Vector2i(-1, -1):
			_start_mining(mine_front)
			return
	if event.button_index == MOUSE_BUTTON_LEFT and event.alt_pressed and game_state.grabbed_item.is_empty():
		_begin_ground_input(event, grid)
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		_attack_focus_uid = 0
		_follow_focus_uid = 0
		if focus_uid != 0:
			_follow_focus_uid = focus_uid
			if event.alt_pressed and not event.ctrl_pressed:
				var target: Dictionary = game_state.get_creature(focus_uid)
				if int(target.get("type", 0)) == 2:
					control_panel.call("prefill_private_message", str(target.get("name", "")))
		# 67B423–67B4DE: plain and Alt actor hits both fall through to the
		# ground turn/run request. Alt's chat prefill is not a stop action.
		if focus_uid == 0 or not event.ctrl_pressed:
			_begin_ground_input(event, grid)
		elif _ground_input.button == 0:
			# 66DBA7/65F784 marks held repeats; 67B438 then skips the
			# one-shot Ctrl actor request and falls through to ground movement.
			# Retain the press without disturbing an existing route or left hold.
			_ground_input.press(MOUSE_BUTTON_RIGHT, grid, true, event.shift_pressed, event.alt_pressed)
			_ground_input.pending = false
	elif event.button_index == MOUSE_BUTTON_LEFT:
		# The hero's hit rectangle is useful to team targeting, but must not
		# swallow the current-cell ground operation after that mode is handled.
		if focus_uid == game_state.player_uid:
			focus_uid = 0
		if focus_uid != 0:
			var creature: Dictionary = game_state.get_creature(focus_uid)
			if creature.get("type", 0) == 3:
				_release_ground_input()
				_request_npc_dialogue(focus_uid)
			elif creature.get("type", 0) == 1:
				_start_chase(focus_uid)
			elif creature.get("type", 0) == 2 and event.shift_pressed and not event.alt_pressed:
				_start_chase(focus_uid)
				_shift_chase_active = _chase_target_uid != 0
			return
		if not game_state.grabbed_item.is_empty():
			var grabbed: Dictionary = game_state.grabbed_item
			NetworkClient.send_drop_item(grabbed.get("itemID", 0), grabbed.get("seqID", 0), grabbed.get("count", 0))
			return
		if event.shift_pressed and not event.alt_pressed:
			_begin_ground_input(event, grid)
			return
		if grid == Vector2i(game_state.player_x, game_state.player_y):
			# 67B26D–67B2B5 -> 68F984 sends pickup at the hero's current
			# location when idle, without requiring a cached ground-item entry.
			if _ground_input.button == 0 and _move_path.is_empty() and _move_step_timer <= 0.0 \
					and _player_action_timer < 0.0 and _pickup_action_timer < 0.0 \
					and _player_forced_action_queue.is_empty() and not _player_input_blocked():
				_request_pickup()
			_begin_ground_input(event, grid)
			# This click already attempted the current-cell operation. Further
			# requests come from the held-input poll after its 300 ms threshold.
			_ground_input.pending = false
			return
		_begin_ground_input(event, grid)


func _request_npc_dialogue(uid: int, now_ms := -1) -> bool:
	var now: int = Time.get_ticks_msec() if now_ms < 0 else now_ms
	# 67B05F rejects held-repeat dispatch; this entry is reached only by the
	# actual click branch. 67B073/67B079 reject elapsed <= 1500 ms globally,
	# including when the user switches to another NPC.
	if now - _last_npc_dialogue_ms <= 1500:
		return false
	_last_npc_dialogue_ms = now
	NetworkClient.send_npc_event(uid, "", "_RSVD_NAME_ENTER_90360178872")
	return true


func _begin_ground_input(event: InputEventMouseButton, grid: Vector2i) -> void:
	var force_attack := event.button_index == MOUSE_BUTTON_LEFT and event.shift_pressed and not event.alt_pressed
	var harvest := event.button_index == MOUSE_BUTTON_LEFT and event.alt_pressed
	if grid == Vector2i(game_state.player_x, game_state.player_y) and not force_attack and not harvest:
		# The decision layer treats the current cell as a no-op. Preserve the
		# current operation, but remember the press for later held redirection.
		_ground_input.press(event.button_index, grid, event.ctrl_pressed, force_attack, harvest)
		return
	var remaining := _move_step_timer
	var previous_button: int = _ground_input.button
	var previous_held: float = _ground_input.held_seconds
	_cancel_movement()
	_move_step_timer = remaining
	_ground_input.button = previous_button
	_ground_input.held_seconds = previous_held
	_ground_input.press(event.button_index, grid, event.ctrl_pressed, force_attack, harvest)


func _ground_occupied() -> Dictionary:
	var occupied := {}
	for uid in game_state.creatures:
		if int(uid) == game_state.player_uid:
			continue
		var creature: Dictionary = game_state.creatures[uid]
		if int(creature.get("action_type", 2)) != 13:
			occupied[Vector2i(creature.get("x", -1), creature.get("y", -1))] = true
	return occupied


func _action_request_ready(now_ms := -1) -> bool:
	if not NetworkClient.is_connected_to_server():
		_action_request_gate.reset()
		return true
	return _action_request_gate.ready(Time.get_ticks_msec() if now_ms < 0 else now_ms)


func _send_player_action(payload: PackedByteArray) -> Error:
	if not NetworkClient.is_connected_to_server():
		return NetworkClient.send_action(payload)
	var token: int = _action_request_gate.begin(Time.get_ticks_msec())
	var uid: int = game_state.player_uid
	var map_uid: int = game_state.player_map_uid
	var result := NetworkClient.send_action_request(payload, _on_action_receipt.bind(token, uid, map_uid), _on_action_timeout.bind(token, uid, map_uid))
	if result != OK:
		_action_request_gate.complete(token)
	return result


func _on_action_receipt(head: int, _payload: PackedByteArray, token: int, uid: int, map_uid: int) -> void:
	if uid == game_state.player_uid and map_uid == game_state.player_map_uid and head in [NetworkClient.SM_OK, NetworkClient.SM_ERROR]:
		_action_request_gate.complete(token)


func _on_action_timeout(_head: int, _payload: PackedByteArray, token: int, uid: int, map_uid: int) -> void:
	if uid == game_state.player_uid and map_uid == game_state.player_map_uid:
		_action_request_gate.expire(token, Time.get_ticks_msec())


func _on_action_connection_changed(_connected: bool, _message: String) -> void:
	_action_request_gate.reset()


func _on_creature_removed(uid: int) -> void:
	if uid == 0:
		return
	# 6799BE–679A5B clears matching target pointers when an actor leaves.
	if _locked_magic_target_uid == uid:
		_locked_magic_target_uid = 0
	if _magic_focus_uid == uid:
		_magic_focus_uid = 0
	if _follow_focus_uid == uid:
		_follow_focus_uid = 0
	if _attack_focus_uid == uid:
		_attack_focus_uid = 0
	if _chase_target_uid == uid:
		_chase_target_uid = 0
		_move_path.clear()
		_shift_chase_active = false
	_summon_spawn_blockers.erase(uid)


func _process_ground_input(delta: float) -> void:
	if _player_server_move_active or not _player_server_action_queue.is_empty():
		# Authority-driven motion pauses held dispatch; mouse release still
		# arrives through _input(), and holding may resume when it completes.
		if _ground_input.button != 0:
			_ground_input.held_seconds += delta
		_ground_input.pending = false
		return
	if _ground_input.button == 0:
		return
	if _player_input_blocked() or not _player_forced_action_queue.is_empty() or map_loading_overlay.visible:
		_release_ground_input()
		return
	if not _action_request_ready():
		_ground_input.held_seconds += delta
		return
	var hovered := get_viewport().gui_get_hovered_control()
	var over_world := hovered == world_renderer or (hovered != null and world_renderer.is_ancestor_of(hovered))
	_ground_input.advance(delta, _mouse_grid(), Input.is_key_pressed(KEY_CTRL), over_world, _ground_path_active, Input.is_key_pressed(KEY_SHIFT), Input.is_key_pressed(KEY_ALT))
	if not _ground_input.pending:
		return
	var from := Vector2i(game_state.player_x, game_state.player_y)
	if _ground_input.target != from and (_mine_target.x >= 0 or _chase_target_uid != 0):
		# A press at the current cell may later become a real held request.
		# Cancel its old operation once, without losing the held-button state.
		var remaining := _move_step_timer
		_cancel_movement(false)
		_move_step_timer = remaining
	# Consume a request, not an entire click-to-destination path. Held input
	# regenerates it after 300 ms. Existing animation gates control step cadence.
	_ground_input.pending = false
	if _move_step_timer > 0.0 or _player_action_timer >= 0.0 or _pickup_action_timer >= 0.0:
		return
	if _ground_input.button == MOUSE_BUTTON_LEFT and game_state.grabbed_item.is_empty():
		var mine_front := _ground_mining_front(_ground_input.target, Input.is_key_pressed(KEY_SHIFT))
		if mine_front != Vector2i(-1, -1):
			_start_mining(mine_front)
			return
	if _ground_input.button == MOUSE_BUTTON_LEFT and not _ground_input.force_attack and not _ground_input.harvest and _ground_input.target == from:
		if _move_path.is_empty() and _chase_target_uid == 0 and _mine_target.x < 0:
			_request_pickup()
		return
	if _ground_input.button == MOUSE_BUTTON_LEFT and not _ground_input.force_attack and not _ground_input.harvest and Time.get_ticks_msec() - _last_attack_ms <= 1000:
		return
	var occupied := _ground_occupied()
	var decision: Dictionary = _ground_input.decide(from, world_renderer.can_walk, occupied)
	if decision.has("harvest"):
		_try_harvest_corpse(_ground_input.target, int(decision.harvest))
		return
	if decision.has("attack"):
		var front: Vector2i = from + Mir3MovementScript.DIRECTIONS[int(decision.attack) - 1]
		_send_attack_action(0, front)
		return
	if decision.has("path"):
		_ground_path_goal = decision.path
		_move_path = _find_ground_path(from, occupied)
		_ground_path_active = not _move_path.is_empty()
		if _ground_path_active:
			return
		# Mir3 falls back to a walking decision when a run path cannot start.
		_ground_input.running = false
		decision = _ground_input.decide(from, world_renderer.can_walk, occupied)
	if decision.has("move"):
		var next: Vector2i = decision.move
		if _send_move_action(next.x, next.y):
			_move_step_timer = MOVE_STEP_SECONDS
	elif decision.has("turn") and int(decision.turn) != game_state.player_direction:
		var stand := {"type": 2, "speed": 100, "direction": int(decision.turn), "x": from.x, "y": from.y, "aimX": from.x, "aimY": from.y, "aimUID": 0}
		_send_player_action(Protocol.encode_cm_action(game_state.player_uid, game_state.player_map_uid, stand))
		game_state.player_direction = int(decision.turn)
		_set_player_action(2)


func _find_corpse_near(grid: Vector2i) -> int:
	# 679018 walks the actor list in order, selecting the first corpse within
	# one cell of the clicked location, rather than the nearest to the hero.
	for uid in game_state.creatures:
		var creature: Dictionary = game_state.creatures[uid]
		if int(creature.get("action_type", 2)) == 13 \
				and absi(int(creature.get("x", -100)) - grid.x) <= 1 \
				and absi(int(creature.get("y", -100)) - grid.y) <= 1:
			return int(uid)
	return 0


func _try_harvest_corpse(grid: Vector2i, direction: int, now_ms := -1) -> bool:
	if not _action_request_ready():
		return false
	var now: int = Time.get_ticks_msec() if now_ms < 0 else now_ms
	if now - _last_corpse_interaction_ms <= 1000:
		return false
	_last_corpse_interaction_ms = now
	var corpse_uid := _find_corpse_near(grid)
	if corpse_uid != 0:
		NetworkClient.send_harvest_corpse(corpse_uid)
	# 67AFCC/67AFF7 enqueue the same bend action with or without a corpse.
	# Use the existing bend animation, without the delayed ground-pickup timer.
	var action := {"type": 8, "speed": 100, "direction": direction, "x": game_state.player_x, "y": game_state.player_y}
	_send_player_action(Protocol.encode_cm_action(game_state.player_uid, game_state.player_map_uid, action))
	game_state.player_direction = direction
	_set_player_action(8)
	_player_action_timer = _action_duration(8, 100, 2)
	return true


func _start_move_to(destination: Vector2i) -> void:
	var active_move_remaining := _move_step_timer if game_state.player_action_type in [3, 5] else 0.0
	_cancel_movement()
	_move_step_timer = maxf(0.0, active_move_remaining)
	_move_path = _find_path([destination])


func _on_minimap_move_requested(destination: Vector2i) -> void:
	if _player_input_blocked() or map_loading_overlay.visible or not _player_forced_action_queue.is_empty():
		return
	_start_move_to(destination)


func _start_chase(target_uid: int) -> void:
	var remaining := _move_step_timer if game_state.player_action_type in [3, 5] else 0.0
	_cancel_movement()
	_move_step_timer = remaining
	_attack_focus_uid = target_uid
	_chase_target_uid = target_uid
	# Selecting the next target must not truncate a committed walking segment.
	if remaining <= 0.0 and _player_action_timer < 0.0 and _pickup_action_timer < 0.0 and _action_request_ready():
		_plan_chase_path()


func _cancel_movement(cancel_ground_input := true) -> void:
	if cancel_ground_input:
		_release_ground_input()
	else:
		_ground_path_active = false
	_move_path.clear()
	_move_step_timer = 0.0
	_pending_spell_action.clear()
	_chase_target_uid = 0
	_mine_target = Vector2i(-1, -1)


func _try_magic_key(event: InputEventKey) -> bool:
	# 67C1B0 clears 729CF0 after every function-key dispatch, including
	# empty slots and rejected spells, without releasing held mouse input.
	if event.keycode >= KEY_F1 and event.keycode <= KEY_F12:
		_ground_input.pending = false
	var key: int = preload("res://scripts/game/magic_shortcuts.gd").event_key(event)
	if key == 0:
		return false
	var magic_id := 0
	for configured_magic in game_state.magic_keys:
		if int(game_state.magic_keys[configured_magic]) == key:
			magic_id = int(configured_magic)
			break
	if magic_id <= 0 or not _has_learned_magic(magic_id):
		return false
	var layout: PackedInt32Array = _resources.skill_layout(magic_id)
	if layout.size() >= 5 and (layout[4] & 1) != 0:
		return true
	_cast_magic(magic_id, _mouse_grid())
	return true


func _has_learned_magic(magic_id: int) -> bool:
	for magic_value in game_state.learned_magic:
		if magic_value is Dictionary and int(magic_value.get("magicID", 0)) == magic_id:
			return true
		if magic_value is int and int(magic_value) == magic_id:
			return true
	return false


func _mouse_grid() -> Vector2i:
	var mouse := get_viewport().get_mouse_position()
	return world_renderer.grid_from_screen(int(mouse.x), int(mouse.y))


func _magic_target_lock_enabled() -> bool:
	var data: PackedByteArray = game_state.runtime_config.get(49, PackedByteArray())
	return data.size() >= 2 and data[0] != 0 and data[1] != 0


func _toggle_magic_target_lock() -> void:
	# 660BE8: same/empty hover clears; a different corpse leaves the lock.
	var hovered: int = world_renderer.focus_uid_at_screen(get_viewport().get_mouse_position(), false, true)
	if hovered == 0 or hovered == _locked_magic_target_uid:
		_locked_magic_target_uid = 0
	else:
		var actor: Dictionary = game_state.get_creature(hovered)
		if not actor.is_empty() and actor.get("action_type", 0) != 13:
			_locked_magic_target_uid = hovered


func _valid_locked_magic_target() -> int:
	if not _magic_target_lock_enabled() or _locked_magic_target_uid == 0:
		return 0
	var actor: Dictionary = game_state.get_creature(_locked_magic_target_uid)
	return _locked_magic_target_uid if not actor.is_empty() and actor.get("action_type", 0) != 13 else 0


func _update_magic_focus(_mouse_grid: Vector2i, magic_id := 0) -> int:
	# 67CA30 / 67CD24 allow the currently hovered corpse for legacy spell 77.
	# The history fallback below still requires a live actor (67CA7D/67CD08).
	var include_dead: bool = _resources.magic_names.get(magic_id, "") == "回生术"
	var focus_uid: int = world_renderer.focus_uid_at_screen(get_viewport().get_mouse_position(), false, include_dead)
	if focus_uid != 0:
		var candidate: Dictionary = game_state.get_creature(focus_uid)
		if not candidate.is_empty() and (include_dead or candidate.get("action_type", 0) != 13):
			_magic_focus_uid = focus_uid
			return _magic_focus_uid
	if _magic_focus_uid != 0:
		var focus: Dictionary = game_state.get_creature(_magic_focus_uid)
		if focus.is_empty() or focus.get("action_type", 0) == 13:
			_magic_focus_uid = 0
	return _magic_focus_uid


func _cast_magic(magic_id: int, mouse_grid: Vector2i) -> bool:
	var magic_name: String = _resources.magic_names.get(magic_id, "")
	# Original 67CF44 resolves a spell target only in its casting branch.
	# Sword toggles and the special kick command must not replace magic focus.
	var focus_uid := 0
	if magic_name not in SWING_MAGIC_NAMES and magic_name != "空拳刀法":
		# Actual spells still refresh focus before the cooldown rejection.
		focus_uid = _update_magic_focus(mouse_grid, magic_id)
	if not _magic_ready(magic_id):
		# Original command gate drops rapid repeats without adding chat feedback.
		if (magic_name in SWING_MAGIC_NAMES or magic_name in ["野蛮冲撞", "空拳刀法"]) and Time.get_ticks_msec() - _last_magic_request_ms < 500:
			return false
		game_state.add_chat_log("%s尚未冷却" % _resources.magic_names.get(magic_id, "技能"), 3)
		return false
	if magic_name in SWING_MAGIC_NAMES:
		_last_magic_request_ms = Time.get_ticks_msec()
		_swing_magic[magic_id] = not bool(_swing_magic.get(magic_id, false))
		game_state.add_chat_log("%s%s" % ["开启" if _swing_magic[magic_id] else "关闭", magic_name], 0)
		return true
	if magic_name == "空拳刀法":
		# 67D070–67D081 updates the 27/36 shared gate before enqueueing.
		_last_impulse_magic_ms = Time.get_ticks_msec()
		_last_magic_request_ms = _last_impulse_magic_ms
		return _send_spell_action(12, magic_id, mouse_grid, focus_uid)
	# 67C98A/67CCB9 routes eligible self/ground spells through the same
	# live scene-member lock override as target spells. Keep special commands out.
	if magic_name in SELF_MAGIC_NAMES or magic_name in GROUND_MAGIC_NAMES or magic_name in TARGET_MAGIC_NAMES:
		if _magic_target_lock_enabled() and Mir3TargetLockScript.ALLOWED.has(magic_name):
			var locked_uid := _valid_locked_magic_target()
			if locked_uid != 0:
				focus_uid = locked_uid
			# 67CCCC writes the resolved lock into current spell focus before
			# the busy gate. Independent lock storage does not bypass focus.
			_magic_focus_uid = focus_uid
			return _send_spell_action(9, magic_id, mouse_grid, focus_uid)
	if magic_name in SELF_MAGIC_NAMES:
		return _send_spell_action(9, magic_id, Vector2i(game_state.player_x, game_state.player_y), game_state.player_uid)
	if magic_name in GROUND_MAGIC_NAMES:
		return _send_spell_action(9, magic_id, _ground_spell_grid(mouse_grid, magic_name == "瞬息移动"), 0)
	if magic_name in TARGET_MAGIC_NAMES:
		# 67CB50 / 67CD89 normalize unowned targets just like ground casts.
		# Legacy healing (2) has a separate self-coordinate branch.
		var target_grid := mouse_grid
		if focus_uid == 0 and magic_name != "治愈术":
			target_grid = _ground_spell_grid(mouse_grid)
		return _send_spell_action(9, magic_id, target_grid, focus_uid)
	return false


func _ground_spell_grid(mouse_grid: Vector2i, force_front := false) -> Vector2i:
	var target := mouse_grid
	var map: RefCounted = world_renderer.world_resource
	# 67CB50–67CBCC / 67CD89–67CE05 clamp before the same-cell step.
	if map.width > 0 and map.height > 0:
		target = Vector2i(clampi(target.x, 0, map.width - 1), clampi(target.y, 0, map.height - 1))
	var origin := Vector2i(game_state.player_x, game_state.player_y)
	# 67CE88 also overrides legacy spell 21 (瞬息移动) with a front cell.
	if target == origin:
		var facing := int(game_state.player_direction)
		if facing >= 1 and facing <= 8:
			target = origin + Mir3MovementScript.DIRECTIONS[facing - 1]
	# 67CE26 computes the direction from normalized tile coordinates before
	# 67CEAF projects directional exceptions one cell ahead.
	if force_front:
		var facing := Mir3MovementScript.screen_direction(target - origin)
		target = origin + Mir3MovementScript.DIRECTIONS[facing - 1]
	return target


func _general_spell_aim(mouse_grid: Vector2i, focus_uid: int, project_front: bool) -> Dictionary:
	var origin := Vector2i(game_state.player_x, game_state.player_y)
	var actor: Dictionary = game_state.get_creature(focus_uid)
	var target := _ground_spell_grid(mouse_grid)
	var direction := Mir3MovementScript.screen_direction(target - origin)
	if focus_uid != 0 and not actor.is_empty():
		target = Vector2i(actor.get("x", mouse_grid.x), actor.get("y", mouse_grid.y))
		# 67CC59 captures screen-facing before target substitution/projection.
		var draw_grid: Vector2 = world_renderer.player_draw_grid()
		var anchor := Vector2i(roundi(draw_grid.x * 48) - int(game_state.view_x), roundi(draw_grid.y * 32) - int(game_state.view_y))
		direction = Mir3MovementScript.screen_direction(Vector2i(get_viewport().get_mouse_position()) - anchor)
	else:
		focus_uid = 0
	if project_front:
		# 67CE75 bitmap includes dispatch 8. Other current bitmap members
		# are not eligible for this setting-forced general branch.
		target = origin + Mir3MovementScript.DIRECTIONS[direction - 1]
	if focus_uid != 0:
		# 67CEF2 turns toward the actor AFTER projecting the coordinates.
		direction = Mir3MovementScript.direction(origin, Vector2i(actor.get("x", origin.x), actor.get("y", origin.y))) + 1
	return {"grid": target, "uid": focus_uid, "direction": direction}


func _send_spell_action(action_type: int, magic_id: int, aim_grid: Vector2i, aim_uid: int) -> bool:
	# 67D563 -> 68F640 -> 6DB938 rejects ordinary casts while another
	# committed action is still active. Keep the separate walking brake path.
	if action_type == 9 and (_pickup_action_timer >= 0.0 or (game_state.player_action_type not in [2, 3, 5] and _player_action_timer >= 0.0)):
		return false
	if action_type == 9 and not _action_request_ready():
		return false
	# 67D5A7 stamps ordinary cast acceptance before movement braking/enqueueing.
	if action_type == 9:
		_last_magic_request_ms = Time.get_ticks_msec()
	var direction_override := 0
	var magic_name: String = _resources.magic_names.get(magic_id, "")
	var aim_resolved := action_type == 9 and _magic_target_lock_enabled() and Mir3TargetLockScript.ALLOWED.has(magic_name)
	if aim_resolved:
		var resolved := _general_spell_aim(aim_grid, aim_uid, magic_name == "抗拒火环")
		aim_grid = resolved.grid
		aim_uid = resolved.uid
		direction_override = resolved.direction
	var original_kick := action_type == 12 and magic_name == "空拳刀法"
	if original_kick:
		aim_uid = 0
		aim_grid = Vector2i(game_state.player_x, game_state.player_y)
	if not aim_resolved and (original_kick or (action_type == 9 and aim_uid == 0 and magic_name == "治愈术")):
		# 677548 / 67CC59 / 67D0C2 capture screen-facing before enqueueing.
		var draw_grid: Vector2 = world_renderer.player_draw_grid()
		var anchor := Vector2i(roundi(draw_grid.x * 48) - int(game_state.view_x), roundi(draw_grid.y * 32) - int(game_state.view_y))
		# 67D0AC shifts the kick origin 32 screen pixels upward.
		if original_kick:
			anchor.y -= 32
		direction_override = Mir3MovementScript.screen_direction(Vector2i(get_viewport().get_mouse_position()) - anchor)
	elif not aim_resolved and action_type == 9 and aim_uid == 0:
		# 67CBED / 67CE26 call the same sector routine on TILE deltas here.
		# This turn is independent of terrain traversability.
		direction_override = Mir3MovementScript.screen_direction(aim_grid - Vector2i(game_state.player_x, game_state.player_y))
	var pending_action := {
		"action_type": action_type,
		"magic_id": magic_id,
		"aim_grid": aim_grid,
		"aim_uid": aim_uid,
		"direction_override": direction_override,
		"aim_resolved": aim_resolved,
	}
	if not _pending_spell_action.is_empty():
		_pending_spell_action = pending_action
		return true
	if _should_brake_movement_for_spell():
		_cancel_movement()
		_pending_spell_action = pending_action
		game_state.player_action_speed = 200
		game_state.player_action_started_ms = Time.get_ticks_msec() - 150
		_move_step_timer = 0.15
		game_state.state_changed.emit()
		return true
	_cancel_movement()
	return _execute_spell_action(action_type, magic_id, aim_grid, aim_uid, direction_override, aim_resolved)


func _should_brake_movement_for_spell() -> bool:
	if game_state.player_action_type not in [3, 5] or game_state.player_action_started_ms <= 0:
		return false
	var duration_ms := 600.0 * 100.0 / float(clampi(game_state.player_action_speed, 20, 500))
	return float(Time.get_ticks_msec() - game_state.player_action_started_ms) < duration_ms * 0.5


func _release_pending_spell() -> void:
	if _pending_spell_action.is_empty() or not _action_request_ready():
		return
	var pending_action := _pending_spell_action
	_pending_spell_action = {}
	_execute_spell_action(
		pending_action.get("action_type", 9),
		pending_action.get("magic_id", 0),
		pending_action.get("aim_grid", Vector2i(game_state.player_x, game_state.player_y)),
		pending_action.get("aim_uid", 0),
		pending_action.get("direction_override", 0),
		pending_action.get("aim_resolved", false),
	)


func _execute_spell_action(action_type: int, magic_id: int, aim_grid: Vector2i, aim_uid: int, direction_override := 0, aim_resolved := false) -> bool:
	var target_grid := aim_grid
	var requested_aim_uid := aim_uid
	# Preserve a resolved coordinate/direction snapshot through braking.
	if not aim_resolved and aim_uid == game_state.player_uid:
		target_grid = Vector2i(game_state.player_x, game_state.player_y)
	elif not aim_resolved and aim_uid != 0:
		var target: Dictionary = game_state.get_creature(aim_uid)
		if target.is_empty():
			aim_uid = 0
		else:
			target_grid = Vector2i(target.get("x", aim_grid.x), target.get("y", aim_grid.y))
	var direction: int = int(game_state.player_direction)
	if action_type == 12:
		direction = direction_override if direction_override >= 1 and direction_override <= 8 else _spinkick_direction(game_state.player_uid, {
			"x": game_state.player_x,
			"y": game_state.player_y,
			"aimUID": aim_uid,
		})
	elif direction_override >= 1 and direction_override <= 8:
		direction = direction_override
	elif action_type == 9 and aim_uid != 0 and aim_uid != game_state.player_uid:
		# 67CADF / 67CEF2 use 6FEC28 for actor targets, not 6FEE68 sectors.
		direction = Mir3MovementScript.direction(Vector2i(game_state.player_x, game_state.player_y), target_grid) + 1
	else:
		var can_turn: bool = true
		# C++ ActionSpell only inserts a turn for a live UID target or a
		# traversable ground target. Invalid map-edge clicks keep the current
		# direction while the spell itself is still cast.
		if action_type == 9:
			can_turn = aim_uid != 0 if requested_aim_uid != 0 else world_renderer.can_walk(target_grid.x, target_grid.y)
		if can_turn:
			direction = _direction_to(game_state.player_x, game_state.player_y, target_grid.x, target_grid.y)
	if direction == 0:
		direction = game_state.player_direction
	# Legacy heal 2 keeps the mouse-derived facing but sends self coordinates
	# with UID 0 when no actor was selected (67CD5A–67CD75).
	if action_type == 9 and requested_aim_uid == 0 and _resources.magic_names.get(magic_id, "") == "治愈术":
		target_grid = Vector2i(game_state.player_x, game_state.player_y)
	if action_type != 12 and direction != game_state.player_direction:
		var stand := {
			"type": 2, "speed": 100, "direction": direction,
			"x": game_state.player_x, "y": game_state.player_y,
			"aimX": game_state.player_x, "aimY": game_state.player_y, "aimUID": 0,
		}
		_send_player_action(Protocol.encode_cm_action(game_state.player_uid, game_state.player_map_uid, stand))
		game_state.player_direction = direction
	var action := {
		"type": action_type, "speed": 100, "direction": direction_override if action_type == 12 else direction,
		"x": game_state.player_x, "y": game_state.player_y,
		"aimX": target_grid.x, "aimY": target_grid.y, "aimUID": aim_uid,
		"magicID": magic_id,
	}
	_send_player_action(Protocol.encode_cm_action(game_state.player_uid, game_state.player_map_uid, action))
	game_state.magic_cast_times[magic_id] = Time.get_ticks_msec()
	if action_type == 12:
		game_state.player_direction = direction
	if action_type == 9:
		var effect := action.duplicate(true)
		if _resources.magic_cast_motion(magic_id) == 7:
			effect["direction"] = 5
			game_state.player_direction = 5
		effect["uid"] = game_state.player_uid
		game_state.add_magic_effect(effect, "local_action")
	_set_player_action(action_type, action.speed, magic_id)
	_player_action_timer = _action_duration(action_type, action.speed, 2, magic_id)
	return true


func _plan_chase_path() -> void:
	var creature: Dictionary = game_state.get_creature(_chase_target_uid)
	if creature.is_empty() or creature.get("action_type", 0) == 13:
		_chase_target_uid = 0
		_move_path.clear()
		return
	var target := Vector2i(creature.get("x", 0), creature.get("y", 0))
	if _grid_distance(Vector2i(game_state.player_x, game_state.player_y), target) <= 1:
		_move_path.clear()
		_send_attack_action(_chase_target_uid)
		return
	var goals: Array[Vector2i] = []
	for direction in WorldPathfinderScript.DIRECTIONS:
		goals.append(target + direction)
	_move_path = _find_path(goals)
	_move_step_timer = 0.0 if not _move_path.is_empty() else 0.25


func _ground_mining_front(target: Vector2i, shift: bool) -> Vector2i:
	var weapon: Dictionary = game_state.wear.get(3, {})
	if not _resources.item_can_mine(int(weapon.get("itemID", 0))):
		return Vector2i(-1, -1)
	var from := Vector2i(game_state.player_x, game_state.player_y)
	var facing: int = Mir3MovementScript.direction(from, target)
	var front: Vector2i = from + Mir3MovementScript.DIRECTIONS[facing]
	# 67AE1C–67AEFC precedes Alt and is also reached by held dispatch.
	return front if shift or not world_renderer.can_walk(front.x, front.y) else Vector2i(-1, -1)


func _start_mining(target: Vector2i) -> void:
	var remaining := _move_step_timer
	_cancel_movement()
	_move_step_timer = remaining
	_mine_target = target
	if _move_step_timer <= 0.0 and _player_action_timer < 0.0 and _pickup_action_timer < 0.0:
		_send_mine_action()


func _plan_mine_path() -> void:
	var weapon: Dictionary = game_state.wear.get(3, {})
	if not _resources.item_can_mine(int(weapon.get("itemID", 0))):
		_mine_target = Vector2i(-1, -1)
		return
	# 66DED9–66DF8C repeats against the current facing's adjacent wall;
	# it never finds a route to the original clicked cell.
	var facing: int = clampi(game_state.player_direction, 1, 8) - 1
	_mine_target = Vector2i(game_state.player_x, game_state.player_y) + Mir3MovementScript.DIRECTIONS[facing]
	if not world_renderer.can_walk(_mine_target.x, _mine_target.y):
		_send_mine_action()


func _find_path(goals: Array[Vector2i]) -> Array[Vector2i]:
	var player_position := Vector2i(game_state.player_x, game_state.player_y)
	var occupied := _ground_occupied()
	occupied.erase(player_position)
	return _pathfinder.find_path(player_position, goals, world_renderer.can_walk, occupied, 50000, 2)


func _find_ground_path(from: Vector2i, occupied: Dictionary) -> Array[Vector2i]:
	var resource: RefCounted = world_renderer.world_resource
	return _pathfinder.find_mir3_path(from, _ground_path_goal, world_renderer.can_walk, occupied, 50000, Rect2i(0, 0, resource.width, resource.height))


func _process_movement(delta: float) -> void:
	if _pickup_action_timer >= 0.0 or _player_action_timer >= 0.0:
		return
	if _move_path.is_empty():
		if _mine_target.x >= 0:
			_move_step_timer = maxf(0.0, _move_step_timer - delta)
			if _move_step_timer > 0.0:
				return
			if game_state.player_action_type != 2:
				_set_player_action(2)
			if _action_request_ready():
				_plan_mine_path()
			return
		if _chase_target_uid == 0:
			# A server stand can leave a retry delay without a move animation.
			# Advance that delay while idle too, or held input remains blocked.
			_move_step_timer = maxf(0.0, _move_step_timer - delta)
			if _move_step_timer <= 0.0:
				if game_state.player_action_type in [3, 5]:
					_set_player_action(2)
				_release_pending_spell()
			return
		_move_step_timer -= delta
		if _move_step_timer > 0.0:
			return
		_set_player_action(2)
		if _action_request_ready():
			_plan_chase_path()
		return
	_move_step_timer -= delta
	if _move_step_timer > 0.0:
		return
	if not _action_request_ready():
		return
	var next: Vector2i = _move_path.front()
	if not _send_move_action(next.x, next.y):
		# A creature/door or a server correction may invalidate a previously
		# computed hop. Replan before consuming it or starting another cooldown.
		var from := Vector2i(game_state.player_x, game_state.player_y)
		if _ground_path_active:
			_move_path = _find_ground_path(from, _ground_occupied())
			_ground_path_active = not _move_path.is_empty()
		else:
			var goals: Array[Vector2i] = [_move_path.back()]
			_move_path = _find_path(goals)
		return
	_move_path.pop_front()
	_move_step_timer = MOVE_STEP_SECONDS
	if _move_path.is_empty():
		_ground_path_active = false


func _send_move_action(aim_x: int, aim_y: int) -> bool:
	if not _action_request_ready():
		return false
	var from := Vector2i(game_state.player_x, game_state.player_y)
	if not Mir3MovementScript.can_step(from, Vector2i(aim_x, aim_y), world_renderer.can_walk, _ground_occupied()):
		return false
	# ACTION_MOVE = 3
	var action := {
		"type": 3,  # ACTION_MOVE
		"speed": 100,  # SYS_DEFSPEED
		"direction": _direction_to(game_state.player_x, game_state.player_y, aim_x, aim_y),
		"x": game_state.player_x,
		"y": game_state.player_y,
		"aimX": aim_x,
		"aimY": aim_y,
		"aimUID": 0,
	}
	var action_data := Protocol.encode_cm_action(game_state.player_uid, game_state.player_map_uid, action)
	_send_player_action(action_data)
	game_state.player_direction = action.direction
	game_state.player_action_from_x = game_state.player_x
	game_state.player_action_from_y = game_state.player_y
	game_state.player_x = aim_x
	game_state.player_y = aim_y
	_player_action_timer = -1.0
	_set_player_action(3, action.speed, 0, _grid_distance(Vector2i(action.x, action.y), Vector2i(action.aimX, action.aimY)))
	_play_action_seff(game_state.player_uid, action, {
		"uid": game_state.player_uid,
		"type": 2,
		"gender": game_state.player_gender,
		"desp": game_state.player_desp,
		"action_started_ms": game_state.player_action_started_ms,
		"action_step": game_state.player_action_step,
	})
	return true


func _grid_distance(from: Vector2i, to: Vector2i) -> int:
	return maxi(absi(from.x - to.x), absi(from.y - to.y))


func _send_attack_action(target_uid: int, ground_target := Vector2i(-1, -1)) -> void:
	if not _action_request_ready():
		return
	_last_attack_ms = Time.get_ticks_msec()
	# ACTION_ATTACK = 7
	var creature: Dictionary = game_state.get_creature(target_uid)
	var tx: int = ground_target.x if target_uid == 0 and ground_target != Vector2i(-1, -1) else creature.get("x", game_state.player_x)
	var ty: int = ground_target.y if target_uid == 0 and ground_target != Vector2i(-1, -1) else creature.get("y", game_state.player_y)
	var action := {
		"type": 7,  # ACTION_ATTACK
		"speed": 100,  # SYS_DEFSPEED
		"direction": _direction_to(game_state.player_x, game_state.player_y, tx, ty),
		"x": game_state.player_x,
		"y": game_state.player_y,
		"aimX": tx,
		"aimY": ty,
		"aimUID": target_uid,
		"magicID": _consume_attack_magic_id(_direction_to(game_state.player_x, game_state.player_y, tx, ty)),
	}
	var action_data := Protocol.encode_cm_action(game_state.player_uid, game_state.player_map_uid, action)
	_send_player_action(action_data)
	if action.magicID > 0:
		game_state.magic_cast_times[action.magicID] = Time.get_ticks_msec()
	game_state.player_direction = action.direction
	_set_player_action(7, action.speed, action.magicID)
	_player_action_timer = _action_duration(7, action.speed, 2, action.magicID)


func _send_mine_action() -> void:
	if not _action_request_ready():
		return
	var direction := _direction_to(game_state.player_x, game_state.player_y, _mine_target.x, _mine_target.y)
	var action := {
		"type": 14,
		"speed": 100,
		"direction": direction,
		"x": _mine_target.x,
		"y": _mine_target.y,
	}
	_send_player_action(Protocol.encode_cm_action(game_state.player_uid, game_state.player_map_uid, action))
	game_state.player_direction = direction
	_set_player_action(14, action.speed)
	_player_action_timer = _action_duration(14, action.speed, 2)


func _consume_attack_magic_id(facing := 0) -> int:
	if _next_strike:
		_next_strike = false
		var next_magic: int = _resources.magic_id("攻杀剑术")
		if next_magic > 0:
			return next_magic
	for magic_name in ["莲月剑法", "翔空剑法", "烈火剑法"]:
		var swing_magic: int = _resources.magic_id(magic_name)
		if swing_magic > 0 and bool(_swing_magic.get(swing_magic, false)):
			_swing_magic[swing_magic] = false
			return swing_magic
	# 677EA3–677EBC / 67B760: persistent thrust requires a live attackable
	# actor exactly two cells ahead; charged strikes above keep priority.
	var thrust: int = _resources.magic_id("刺杀剑术")
	if bool(_swing_magic.get(thrust, false)) and _has_learned_magic(thrust) and _thrust_target_ahead(facing):
		return thrust
	for magic_name in ["十方斩", "半月弯刀"]:
		var swing_magic: int = _resources.magic_id(magic_name)
		if swing_magic > 0 and bool(_swing_magic.get(swing_magic, false)):
			return swing_magic
	var physical_magic: int = _resources.magic_id("物理攻击")
	return physical_magic


func _thrust_target_ahead(facing: int) -> bool:
	if facing < 1 or facing > 8:
		return false
	var target: Vector2i = Vector2i(game_state.player_x, game_state.player_y) + Mir3MovementScript.DIRECTIONS[facing - 1] * 2
	for uid in game_state.creatures:
		if int(uid) == game_state.player_uid:
			continue
		var actor: Dictionary = game_state.creatures[uid]
		if int(actor.get("type", 0)) not in [1, 2] or int(actor.get("action_type", 2)) == 13:
			continue
		if Vector2i(actor.get("x", -1), actor.get("y", -1)) == target:
			return true
	return false


func _magic_ready(magic_id: int, now_ms := -1) -> bool:
	var now: int = Time.get_ticks_msec() if now_ms < 0 else now_ms
	var magic_name: String = _resources.magic_names.get(magic_id, "")
	# 67D050–67D061: command skills share a 500ms accepted-request gate.
	if (magic_name in SWING_MAGIC_NAMES or magic_name in ["野蛮冲撞", "空拳刀法"]) and now - _last_magic_request_ms < 500:
		return false
	# 67D041: both legacy 27 and 36 require elapsed >= 3000 ms.
	if _resources.magic_names.get(magic_id, "") in ["野蛮冲撞", "空拳刀法"] and now - _last_impulse_magic_ms < 3000:
		return false
	var layout: PackedInt32Array = _resources.skill_layout(magic_id)
	var cool_down := layout[5] if layout.size() >= 6 else 0
	if cool_down <= 0 or not game_state.magic_cast_times.has(magic_id):
		return true
	return now - int(game_state.magic_cast_times[magic_id]) >= cool_down


func _direction_to(from_x: int, from_y: int, to_x: int, to_y: int) -> int:
	var dx := signi(to_x - from_x)
	var dy := signi(to_y - from_y)
	if dx == 0 and dy == 0:
		return 0
	if dy < 0:
		return 8 if dx < 0 else (2 if dx > 0 else 1)
	if dy > 0:
		return 6 if dx < 0 else (4 if dx > 0 else 5)
	return 7 if dx < 0 else 3


func _center_hero() -> void:
	game_state.center_camera_on_grid(world_renderer.player_draw_grid())


func _on_control_panel_minimized_changed(minimized: bool) -> void:
	game_state.hud_minimized = minimized
	location_label.visible = not minimized


func _request_pickup() -> void:
	if not _action_request_ready():
		return
	NetworkClient.send_pickup(game_state.player_x, game_state.player_y, game_state.player_map_uid)


func _begin_pickup_action() -> void:
	if not _action_request_ready():
		return
	if _pickup_action_timer >= 0.0:
		return
	var action := {
		"type": 8,
		"speed": 100,
		"direction": game_state.player_direction,
		"x": game_state.player_x,
		"y": game_state.player_y,
	}
	_send_player_action(Protocol.encode_cm_action(game_state.player_uid, game_state.player_map_uid, action))
	_player_action_timer = -1.0
	_set_player_action(8, action.speed)
	_pickup_action_timer = 0.2


func _process_pickup_action(delta: float) -> void:
	if _pickup_action_timer < 0.0:
		return
	_pickup_action_timer -= delta
	if _pickup_action_timer > 0.0:
		return
	if not _action_request_ready():
		_pickup_action_timer = 0.0
		return
	_pickup_action_timer = -1.0
	NetworkClient.send_pickup(game_state.player_x, game_state.player_y, game_state.player_map_uid)
	_set_player_action(2)


func _process_player_action(delta: float) -> void:
	if _player_action_timer < 0.0:
		if not _player_server_action_queue.is_empty() and _player_forced_action_queue.is_empty():
			_player_server_move_active = false
			_handle_action_data(_player_server_action_queue.pop_front(), true)
		return
	_player_action_timer -= delta
	if _player_action_timer <= 0.0:
		_player_action_timer = -1.0
		_player_server_move_active = false
		if not _player_server_action_queue.is_empty() and _player_forced_action_queue.is_empty():
			_handle_action_data(_player_server_action_queue.pop_front(), true)
			return
		if _player_forced_action_queue.is_empty():
			if _player_post_forced_action.is_empty():
				_set_player_action(2)
			else:
				var pending := _player_post_forced_action
				_player_post_forced_action = {}
				_handle_action_data(pending, true)
		else:
			_advance_player_forced_action()


func _start_player_death_action(action: Dictionary) -> void:
	_cancel_movement()
	_pickup_action_timer = -1.0
	_player_action_timer = -1.0
	_player_post_forced_action = {}
	var start := Vector2i(game_state.player_x, game_state.player_y)
	var target := Vector2i(action.get("x", start.x), action.get("y", start.y))
	_player_forced_action_queue = _forced_correction_steps(start, target, 2)
	if start != target and _player_forced_action_queue.is_empty():
		return
	_player_forced_action_queue.append({"kind": "death", "action": action.duplicate(true)})
	_advance_player_forced_action()


func _advance_player_forced_action() -> void:
	if _player_forced_action_queue.is_empty():
		return
	var queued: Dictionary = _player_forced_action_queue.pop_front()
	if queued.get("kind", "") == "move":
		game_state.player_action_from_x = queued.from_x
		game_state.player_action_from_y = queued.from_y
		game_state.player_x = queued.x
		game_state.player_y = queued.y
		game_state.player_direction = queued.direction
		_set_player_action(3, FORCED_MOVE_SPEED, 0, queued.step)
		_player_action_timer = _action_duration(3, FORCED_MOVE_SPEED, 2)
		return
	var action: Dictionary = queued.get("action", {})
	game_state.player_action_from_x = game_state.player_x
	game_state.player_action_from_y = game_state.player_y
	_set_player_action(13, 100)
	_player_action_timer = _action_duration(13, 100, 2) if not _player_post_forced_action.is_empty() else -1.0
	_play_action_seff(game_state.player_uid, action, {
		"uid": game_state.player_uid,
		"type": 2,
		"gender": game_state.player_gender,
		"desp": game_state.player_desp,
		"action_started_ms": game_state.player_action_started_ms,
	})


func _forced_correction_steps(start: Vector2i, target: Vector2i, max_step: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if start == target:
		return result
	var goals: Array[Vector2i] = [target]
	var path: Array[Vector2i] = _pathfinder.find_path(start, goals, world_renderer.can_walk, {})
	if path.is_empty():
		push_error("unable to build forced correction path: %s -> %s" % [start, target])
		return result
	var from := start
	var index := 0
	while index < path.size():
		var direction_delta := path[index] - from
		direction_delta = Vector2i(signi(direction_delta.x), signi(direction_delta.y))
		var endpoint: Vector2i = path[index]
		var step := 1
		index += 1
		while index < path.size() and step < max_step and path[index] - endpoint == direction_delta:
			endpoint = path[index]
			step += 1
			index += 1
		result.append({
			"kind": "move",
			"from_x": from.x,
			"from_y": from.y,
			"x": endpoint.x,
			"y": endpoint.y,
			"direction": _direction_to(from.x, from.y, endpoint.x, endpoint.y),
			"step": step,
		})
		from = endpoint
	return result


func _set_player_action(action_type: int, speed := 100, magic_id := 0, action_step := 0) -> void:
	game_state.player_action_type = action_type
	game_state.player_action_speed = speed
	game_state.player_action_magic_id = magic_id
	game_state.player_action_step = action_step
	game_state.player_action_started_ms = Time.get_ticks_msec()
	game_state.state_changed.emit()


func _action_duration(action_type: int, speed: int, creature_type: int, magic_id := 0) -> float:
	var frame_count := 0
	match action_type:
		1:
			if creature_type == 1:
				frame_count = 10
			else:
				return -1.0
		3, 5: frame_count = 6
		6: return 0.01
		7:
			if creature_type == 1:
				frame_count = 6
			else:
				var magic_name: String = _resources.magic_names.get(magic_id, "")
				var primary_frames := 10 if magic_name in ["翔空剑法", "莲月剑法", "十方斩"] else 6
				var primary_speed := 150 if magic_name == "十方斩" else 100
				return float(primary_frames) * 0.1 * 100.0 / float(clampi(primary_speed, 20, 500)) + 0.3
		8: frame_count = 2
		9:
			if creature_type == 1:
				frame_count = 10
			else:
				return _hero_spell_action_duration(magic_id)
		11: frame_count = 2 if creature_type == 1 else 3
		12, 13: frame_count = 10
		14: frame_count = 9
		_: return -1.0
	return float(frame_count) * 0.1 * 100.0 / float(clampi(speed, 20, 500))


func _hero_spell_action_duration(magic_id: int) -> float:
	var startup_meta: PackedInt32Array = _resources.magic_layout(magic_id, 1)
	if startup_meta.is_empty():
		return 0.5
	var cast_motion: int = _resources.magic_cast_motion(magic_id)
	var minimum_effect_frames := 8 if cast_motion == 2 else 10
	var primary_duration := float(maxi(startup_meta[2], minimum_effect_frames)) * 0.1 * 100.0 / float(clampi(startup_meta[4], 20, 500))
	return primary_duration + (0.6 if cast_motion == 2 else 0.0)


func _creature_action_duration(action_type: int, speed: int, creature: Dictionary, magic_id := 0) -> float:
	if creature.get("type", 0) == 3 and action_type == 2 and creature.get("npc_motion", 0) == 2:
		var npc_frames := _npc_motion_frame_count(creature.get("npc_id", 0), 2)
		return float(npc_frames) * 0.1 if npc_frames > 0 else -1.0
	if creature.get("type", 0) == 1 and action_type == 10:
		var transform: Dictionary = _resources.monster_transform(creature.get("monster_id", 0))
		if not transform.is_empty():
			var sequence: PackedInt32Array = transform.active_transform if creature.get("monster_stand_mode", false) else transform.hidden_transform
			return float(sequence[2]) * 0.1 * 100.0 / float(clampi(speed, 20, 500))
	if creature.get("type", 0) == 1 and action_type in [1, 7, 9, 11, 13]:
		var body_sequence: PackedInt32Array = _resources.monster_body_sequence(creature.get("monster_id", 0), action_type, magic_id)
		return float(body_sequence[1]) * 0.1 * 100.0 / float(clampi(speed, 20, 500))
	return _action_duration(action_type, speed, creature.get("type", 0), magic_id)


func _play_action_seff(uid: int, action: Dictionary, creature: Dictionary) -> void:
	var action_type: int = action.get("type", 0)
	var creature_type: int = creature.get("type", 2 if uid == game_state.player_uid else 0)
	var source_x: int = action.get("x", creature.get("x", game_state.player_x))
	var source_y: int = action.get("y", creature.get("y", game_state.player_y))
	if creature_type == 1:
		var monster_id: int = creature.get("monster_id", 0)
		var seff_action := 1 if creature.get("action_type", action_type) == 10 else action_type
		_play_seff(_resources.monster_seff(monster_id, seff_action), source_x, source_y)
		return
	if creature_type != 2:
		return
	match action_type:
		3:
			var move_step: int = creature.get("action_step", 0)
			if move_step <= 0:
				move_step = _grid_distance(
					Vector2i(action.get("x", source_x), action.get("y", source_y)),
					Vector2i(action.get("aimX", source_x), action.get("aimY", source_y)),
				)
			var step_seff_base := 0x01000003 if move_step == 2 else 0x01000001
			_schedule_hero_step_seff(uid, action, creature, 1, step_seff_base)
			_schedule_hero_step_seff(uid, action, creature, 4, step_seff_base + 1)
		7, 14:
			var weapon_id := _wear_item_id(creature, 3)
			_play_seff(0x01010032 + _resources.item_weapon_sound(weapon_id), source_x, source_y)
		11:
			_play_seff(0x01030000 + (138 if int(creature.get("gender", 0)) != 0 else 139), source_x, source_y)
			_play_seff(_hero_hit_seff(action.get("aimUID", 0), _wear_item_id(creature, 1) > 0), source_x, source_y)


func _schedule_hero_step_seff(uid: int, action: Dictionary, creature: Dictionary, frame: int, seff_id: int) -> void:
	var speed := clampi(action.get("speed", 100), 20, 500)
	var token: int = creature.get("action_started_ms", game_state.player_action_started_ms)
	var delay := float(frame) * 0.1 * 100.0 / float(speed)
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		if uid == game_state.player_uid:
			if game_state.player_action_type != 3 or game_state.player_action_started_ms != token:
				return
		else:
			var current: Dictionary = game_state.get_creature(uid)
			if current.get("action_type", 0) != 3 or current.get("action_started_ms", -1) != token:
				return
		var ratio := float(frame) / 6.0
		var x := roundi(lerpf(float(action.get("x", 0)), float(action.get("aimX", action.get("x", 0))), ratio))
		var y := roundi(lerpf(float(action.get("y", 0)), float(action.get("aimY", action.get("y", 0))), ratio))
		_play_seff(seff_id, x, y)
	)


func _hero_hit_seff(from_uid: int, has_dress: bool) -> int:
	var bare_id := 83 if has_dress else 73
	match (from_uid >> 59) & 0xF:
		4:
			return 0x01010000 + bare_id
		5:
			var attacker: Dictionary = game_state.get_creature(from_uid)
			if from_uid == game_state.player_uid:
				attacker = {"desp": game_state.player_desp}
			var weapon_sound: int = _resources.item_weapon_sound(_wear_item_id(attacker, 3))
			var impact_ids := [80, 82, 80, 80, 81, 80, 83, 83] if has_dress else [70, 72, 70, 70, 71, 70, 73, 73]
			return 0x01010000 + impact_ids[clampi(weapon_sound, 0, 7)]
	return 0x01010000 + bare_id


func _wear_item_id(creature: Dictionary, location: int) -> int:
	var desp: Dictionary = creature.get("desp", game_state.player_desp if creature.get("uid", game_state.player_uid) == game_state.player_uid else {})
	var wear: Dictionary = desp.get("wear", {})
	return wear.get(location, {}).get("itemID", 0)


func _play_seff(seff_id: int, x: int, y: int) -> void:
	AudioService.play_seff_at(seff_id, x, y, game_state.player_x, game_state.player_y)


func _on_server_message(head_code: int, payload: PackedByteArray) -> void:
	match head_code:
		NetworkClient.SM_STARTGAMESCENE:
			_handle_start_game_scene(payload)
		NetworkClient.SM_ACTION:
			_handle_action(payload)
		NetworkClient.SM_HEALTH:
			_handle_health(payload)
		NetworkClient.SM_NEXTSTRIKE:
			_next_strike = true
		NetworkClient.SM_PLAYERCONFIG:
			_handle_player_config(payload)
		NetworkClient.SM_PLAYERWLDESP:
			_handle_player_wl_desp(payload)
		NetworkClient.SM_EXP:
			_handle_exp(payload)
		NetworkClient.SM_GOLD:
			_handle_gold(payload)
		NetworkClient.SM_PING:
			_handle_ping(payload)
		NetworkClient.SM_TEXT:
			_handle_text(payload)
		NetworkClient.SM_PLAYERSAY:
			_handle_player_say(payload)
		NetworkClient.SM_PLAYERBROADCAST:
			_handle_player_broadcast(payload)
		NetworkClient.SM_NOTIFYDEAD:
			_handle_notify_dead(payload)
		NetworkClient.SM_OFFLINE:
			var data := Protocol.decode_sm_offline(payload)
			if data.get("mapUID", 0) == game_state.player_map_uid:
				game_state.remove_creature(data.get("uid", 0))
		NetworkClient.SM_PICKUPERROR:
			_handle_pickup_error(payload)
		NetworkClient.SM_MISS:
			_handle_miss(payload)
		NetworkClient.SM_BUFF:
			_handle_buff(payload)
		NetworkClient.SM_BUFFIDLIST:
			_handle_buff_id_list(payload)
		NetworkClient.SM_INVENTORY:
			_handle_inventory(payload)
		NetworkClient.SM_BELT:
			_handle_belt(payload)
		NetworkClient.SM_STRIKEGRID:
			var sg := Protocol.decode_sm_strike_grid(payload)
			# Flash grid red briefly (C++ stores timestamp, draws red overlay for 1s)
			game_state.strike_grids["%d,%d" % [sg.get("x", 0), sg.get("y", 0)]] = Time.get_ticks_msec()
		NetworkClient.SM_CASTMAGIC:
			_handle_cast_magic(payload)
		NetworkClient.SM_CORECORD:
			_handle_corecord(payload)
		NetworkClient.SM_PLAYERNAME:
			_handle_player_name(payload)
		NetworkClient.SM_DEADFADEOUT:
			var data := Protocol.decode_sm_dead_fade_out(payload)
			if data.get("mapUID", 0) == game_state.player_map_uid:
				_request_dead_fade_out(data.get("uid", 0))
		NetworkClient.SM_REMOVEITEM:
			if payload.size() >= 10:
				game_state.remove_item(payload.decode_u32(0), payload.decode_u32(4), payload.decode_u16(8))
		NetworkClient.SM_REMOVEGROUNDITEM:
			# SMRemoveGroundItem: X(u16) + Y(u16) + ID(u32) + DBID(u32)
			if payload.size() >= 12:
				var rx: int = payload.decode_u16(0)
				var ry: int = payload.decode_u16(2)
				var rid: int = payload.decode_u32(4)
				game_state.remove_ground_item(rx, ry, rid)
		NetworkClient.SM_GROUNDITEMIDLIST:
			_handle_ground_item_id_list(payload)
		NetworkClient.SM_EQUIPWEAR:
			_handle_equip_wear(payload)
		NetworkClient.SM_EQUIPWEARERROR:
			_handle_equip_wear_error(payload)
		NetworkClient.SM_GRABWEAR:
			_handle_grab_wear(payload)
		NetworkClient.SM_GRABWEARERROR:
			_handle_grab_wear_error(payload)
		NetworkClient.SM_EQUIPBELT:
			_handle_equip_belt(payload)
		NetworkClient.SM_EQUIPBELTERROR:
			_handle_equip_belt_error(payload)
		NetworkClient.SM_GRABBELT:
			_handle_grab_belt(payload)
		NetworkClient.SM_GRABBELTERROR:
			_handle_grab_belt_error(payload)
		NetworkClient.SM_UPDATEITEM:
			_handle_update_item(payload)
		NetworkClient.SM_SHOWSECUREDITEMLIST:
			_handle_secured_items(payload)
		NetworkClient.SM_REMOVESECUREDITEM:
			if payload.size() >= 8:
				game_state.remove_secured_item(payload.decode_u32(0), payload.decode_u32(4))
		NetworkClient.SM_TEAMCANDIDATE:
			_handle_team_candidate(payload)
		NetworkClient.SM_TEAMMEMBERLIST:
			_handle_team_members(payload)
		NetworkClient.SM_QUESTDESPLIST:
			_handle_quest_list(payload)
		NetworkClient.SM_QUESTDESPUPDATE:
			_handle_quest_update(payload)
		NetworkClient.SM_LEARNEDMAGICLIST:
			_handle_learned_magic(payload)
		NetworkClient.SM_GROUNDFIREWALLLIST:
			_handle_ground_firewalls(payload)
		NetworkClient.SM_NPCXMLLAYOUT:
			_handle_npc_xml(payload)
		NetworkClient.SM_NPCSELL:
			_handle_npc_sell(payload)
		NetworkClient.SM_SELLITEMLIST:
			_handle_sell_item_list(payload)
		NetworkClient.SM_BUYSUCCEED:
			_handle_buy_succeed(payload)
		NetworkClient.SM_BUYERROR:
			_handle_buy_error(payload)
		NetworkClient.SM_STARTINPUT:
			_handle_start_input(payload)
		NetworkClient.SM_STARTINVOP:
			_handle_start_inventory_operation(payload)
		NetworkClient.SM_INVOPCOST:
			_handle_inventory_operation_cost(payload)
		NetworkClient.SM_FRIENDLIST:
			_handle_friend_list(payload)
		NetworkClient.SM_CHATMESSAGELIST:
			_handle_chat_message_list(payload)
		NetworkClient.SM_CREATECHATGROUP:
			_handle_chat_group(payload)
		NetworkClient.SM_ADDFRIENDACCEPTED:
			_handle_friend_result(payload, true)
		NetworkClient.SM_ADDFRIENDREJECTED:
			_handle_friend_result(payload, false)


func _handle_start_game_scene(payload: PackedByteArray) -> void:
	var reader := CerealReader.new(payload)
	var data := reader.read_sd_start_game_scene()
	if not _reader_ok(reader, "SM_STARTGAMESCENE"):
		return
	if data.get("uid", 0) != game_state.player_uid or data.get("mapUID", 0) != game_state.player_map_uid:
		push_error("SM_STARTGAMESCENE identity mismatch")
		return
	_action_request_gate.reset()
	_cancel_movement()
	_pickup_action_timer = -1.0
	_player_action_timer = -1.0
	_player_forced_action_queue.clear()
	_player_server_action_queue.clear()
	_player_server_move_active = false
	_player_post_forced_action = {}
	# 68669A -> 676FA4 clears current/history targets with the old scene.
	_locked_magic_target_uid = 0
	_magic_focus_uid = 0
	_follow_focus_uid = 0
	_attack_focus_uid = 0
	_summon_spawn_blockers.clear()
	game_state.start_game_scene(data)
	NetworkClient.send_query_gold()
	if _load_world_map(game_state.player_map_id):
		game_state.player_map_name = world_renderer.world_resource.map_name
		AudioService.play_map_bgm(world_renderer.world_resource.bgm_id)
	else:
		AudioService.stop_bgm()
	_center_hero()


func _handle_action(payload: PackedByteArray) -> void:
	_handle_action_data(Protocol.decode_sm_action(payload))


func _matches_active_move(uid: int, action: Dictionary, creature: Dictionary) -> bool:
	var action_type: int = action.get("type", 0)
	if action_type not in [3, 5]:
		return false
	var from_x: int = action.get("x", 0)
	var from_y: int = action.get("y", 0)
	var end_x: int = action.get("aimX", from_x)
	var end_y: int = action.get("aimY", from_y)
	var speed: int = action.get("speed", 100)
	if uid == game_state.player_uid:
		return game_state.player_action_type == action_type \
				and game_state.player_action_from_x == from_x \
				and game_state.player_action_from_y == from_y \
				and game_state.player_x == end_x \
				and game_state.player_y == end_y \
				and game_state.player_action_speed == speed
	return not creature.is_empty() \
			and creature.get("action_type", 0) == action_type \
			and creature.get("action_from_x", creature.get("x", 0)) == from_x \
			and creature.get("action_from_y", creature.get("y", 0)) == from_y \
			and creature.get("x", 0) == end_x \
			and creature.get("y", 0) == end_y \
			and creature.get("action_speed", 100) == speed


func _handle_action_data(data: Dictionary, correction_applied := false) -> void:
	var uid: int = data.get("uid", 0)
	var action: Dictionary = data.get("action", {})
	var action_map_uid: int = data.get("mapUID", 0)
	if action_map_uid != game_state.player_map_uid:
		if uid != game_state.player_uid:
			return
		_switch_player_map(action_map_uid, action)
	var x: int = action.get("x", 0)
	var y: int = action.get("y", 0)
	var action_type: int = action.get("type", 0)
	var direction: int = action.get("direction", 0)
	if _summon_spawn_blockers.has(uid):
		return
	var action_step := _grid_distance(Vector2i(x, y), Vector2i(action.get("aimX", x), action.get("aimY", y))) if action_type in [3, 5] else 0
	if action_type == 9 and _resources.magic_cast_motion(action.get("magicID", 0)) == 7:
		direction = 5
	var creature: Dictionary = game_state.get_creature(uid) if uid != game_state.player_uid else {}
	# Normal client moves are broadcast only to other actors. Self moves can be
	# server-driven, so ignore only an exact active duplicate; do not discard
	# arbitrary self movement as an acknowledgement of local prediction.
	if not correction_applied and _matches_active_move(uid, action, creature):
		return
	if uid == game_state.player_uid:
		if action_type == 6:
			_player_server_action_queue.clear()
			_player_server_move_active = false
		elif not correction_applied and (_player_server_move_active or not _player_server_action_queue.is_empty()):
			# 6DB054 appends received actor actions instead of replacing the
			# motion already on screen. Keep later stand/hit packets in order.
			if _player_server_action_queue.is_empty() or _player_server_action_queue.back() != data:
				_player_server_action_queue.append(data.duplicate(true))
			return
	var previous_creature := creature.duplicate(true)
	var is_new_creature := creature.is_empty()
	if not creature.is_empty() and creature.has("motion_action_queue"):
		creature.erase("motion_action_queue")
		game_state.update_creature(uid, creature)
		previous_creature = creature.duplicate(true)
	var reviving_player: bool = uid == game_state.player_uid and action_type == 2 and game_state.player_hp > 0
	if uid == game_state.player_uid:
		if not _player_forced_action_queue.is_empty():
			if reviving_player:
				_player_post_forced_action = data.duplicate(true)
			return
		if game_state.player_action_type == 13:
			if not reviving_player:
				return
			if not correction_applied:
				_player_post_forced_action = data.duplicate(true)
				var death_duration := _action_duration(13, game_state.player_action_speed, 2)
				var elapsed := float(Time.get_ticks_msec() - game_state.player_action_started_ms) / 1000.0
				_player_action_timer = maxf(0.001, death_duration - elapsed)
				return
	if previous_creature.get("action_type", 0) == 13 or not previous_creature.get("forced_action_queue", []).is_empty():
		return
	if previous_creature.get("monster_pending_forced_action", {}).get("type", 0) == 13:
		return
	if action_type == 1 and (uid == game_state.player_uid or not creature.is_empty()):
		return
	if uid != game_state.player_uid and creature.is_empty():
		match _creature_type_from_uid(uid):
			2:
				NetworkClient.send_query_corecord(uid)
				return
			0:
				return
	if action_type == 13:
		if uid == game_state.player_uid:
			_start_player_death_action(action)
			return
		if not creature.is_empty():
			var death_creature_type: int = creature.get("type", _creature_type_from_uid(uid))
			if death_creature_type in [1, 2] and not (death_creature_type == 1 and creature.get("action_type", 0) == 10):
				_start_creature_death_action(uid, action, creature)
				return
	if action_type == 11 and not creature.is_empty() and creature.get("type", _creature_type_from_uid(uid)) == 1:
		var hit_transform: Dictionary = _resources.monster_transform(creature.get("monster_id", 0))
		if bool(hit_transform.get("reveal_on_hit", false)):
			if creature.get("action_type", 0) != 10 and bool(creature.get("monster_stand_mode", false)):
				_start_monster_current_hitted_action(uid, action, creature)
				return
		elif creature.get("action_type", 0) != 10:
			_start_monster_motion_action(uid, action, creature)
			return
	if action_type == 7:
		direction = _attack_direction(uid, action)
	elif action_type == 9 and _resources.magic_cast_motion(action.get("magicID", 0)) != 7:
		direction = _spell_direction(uid, action)
	elif action_type == 12 and direction < 1:
		direction = _spinkick_direction(uid, action)
	elif action_type in [3, 5] and direction < 1:
		# ActionMove has no direction field in C++; its ActionNode bytes are zero.
		# Hero/ClientMonster derive the facing from the movement endpoints.
		direction = _direction_to(x, y, action.get("aimX", x), action.get("aimY", y))
	elif action_type == 14:
		# ActionMine.x/y is the mine target rather than the actor position, and
		# its C++ ActionNode conversion always clears direction. Hero derives the
		# swing facing from its current motion endpoint to the target grid.
		var mine_from_x: int = game_state.player_x if uid == game_state.player_uid else creature.get("x", x)
		var mine_from_y: int = game_state.player_y if uid == game_state.player_uid else creature.get("y", y)
		direction = _direction_to(mine_from_x, mine_from_y, x, y)
	if not correction_applied and uid != game_state.player_uid and not creature.is_empty() and creature.get("type", _creature_type_from_uid(uid)) == 2 and action_type in [2, 3, 7, 8, 9, 12]:
		var correction_start := Vector2i(creature.get("x", x), creature.get("y", y))
		if correction_start != Vector2i(x, y):
			_start_remote_player_motion_action(uid, data, creature)
			return
	if not creature.is_empty() and creature.get("type", _creature_type_from_uid(uid)) == 1 and _resources.monster_behave_mode(creature.get("monster_id", 0)) == 2:
		for queue_key in ["motion_action_queue", "forced_action_queue", "monster_pending_action", "monster_pending_forced_action", "monster_pending_form_modes"]:
			creature.erase(queue_key)
		if action_type in [2, 4] and creature.get("x", x) == x and creature.get("y", y) == y:
			game_state.update_creature(uid, creature)
			return
	if not creature.is_empty() and creature.get("type", _creature_type_from_uid(uid)) == 1 and action_type in [2, 3, 7] and _resources.monster_behave_mode(creature.get("monster_id", 0)) != 2:
		var motion_monster_id: int = creature.get("monster_id", 0)
		var motion_transform: Dictionary = _resources.monster_transform(motion_monster_id)
		var correction_waits_for_form := false
		if not motion_transform.is_empty():
			if action_type == 7:
				correction_waits_for_form = creature.get("action_type", 0) == 10 or not bool(creature.get("monster_stand_mode", false))
			elif action_type == 2:
				correction_waits_for_form = creature.get("action_type", 0) == 10 or _monster_action_flag(action) != bool(creature.get("monster_stand_mode", false))
		if _resources.monster_motion_correction(motion_monster_id, action_type) and not correction_waits_for_form:
			var queued_monster_action := action.duplicate(true)
			queued_monster_action["direction"] = direction
			_start_monster_motion_action(uid, queued_monster_action, creature)
			return
		if action_type == 2 and not motion_transform.is_empty() and not correction_waits_for_form:
			return
	if action_type == 6:
		if uid == game_state.player_uid:
			# Original 683AAE -> 6DE2CA refreshes the command clock on self relocation.
			_action_request_gate.reset()
			_last_magic_request_ms = Time.get_ticks_msec()
		var space_magic_id: int = _resources.magic_id("瞬息移动")
		if space_magic_id > 0:
			var space_effect := action.duplicate(true)
			space_effect["uid"] = uid
			space_effect["magicID"] = space_magic_id
			game_state.add_magic_effect(space_effect, "space_move")
	if action_type == 9 and action.get("magicID", 0) > 0:
		if uid != game_state.player_uid or not _has_pending_local_magic(action.get("magicID", 0)):
			var effect := action.duplicate(true)
			effect["uid"] = uid
			effect["direction"] = direction
			game_state.add_magic_effect(effect, "action")
	if action_type == 11 and (uid == game_state.player_uid or creature.get("type", _creature_type_from_uid(uid)) != 1):
		game_state.trigger_shield_hit(uid)
	
	if uid == game_state.player_uid:
		if action_type in [3, 5]:
			_cancel_movement(false)
			_pickup_action_timer = -1.0
			_player_server_move_active = true
		# Update player position and direction
		if action_type in [11, 14]:
			game_state.player_action_from_x = game_state.player_x
			game_state.player_action_from_y = game_state.player_y
		else:
			game_state.player_action_from_x = x
			game_state.player_action_from_y = y
			game_state.player_x = action.get("aimX", x) if _action_uses_aim_position(action_type) else x
			game_state.player_y = action.get("aimY", y) if _action_uses_aim_position(action_type) else y
		if action_type != 11 and direction >= 1:
			game_state.player_direction = direction
		_set_player_action(action_type, action.get("speed", 100), action.get("magicID", 0), action_step)
		_player_action_timer = _action_duration(action_type, action.get("speed", 100), 2, action.get("magicID", 0))
		if action_type == 2:
			# reportStand() cancels the old route after a rejected move. Clear
			# its latch too, including when the final node was already sent,
			# so a still-held button can produce the next cursor request.
			_ground_path_active = false
			if not _move_path.is_empty():
				_move_path.clear()
				_move_step_timer = 0.25
		elif action_type == 13:
			_move_path.clear()
			_chase_target_uid = 0
		_play_action_seff(uid, action, {"uid": uid, "type": 2, "gender": game_state.player_gender, "desp": game_state.player_desp, "action_started_ms": game_state.player_action_started_ms})
	else:
		# Update or create creature
		var continued_monster_action := false
		var creature_type: int = creature.get("type", _creature_type_from_uid(uid))
		var monster_id: int = creature.get("monster_id", game_state.uid_record_id(uid) if creature_type == 1 else 0)
		var stored_action_type := _creature_stored_action_type(action_type, creature_type, monster_id)
		if is_new_creature and creature_type == 1 and action_type == 1:
			var monster_name: String = _resources.monster_name(monster_id)
			var summon_magic_name: String = SUMMON_MAGIC_BY_MONSTER.get(monster_name, "")
			if not summon_magic_name.is_empty():
				game_state.add_chat_log("使用魔法: %s" % summon_magic_name, 1)
				if monster_name in DELAYED_SUMMON_MONSTERS:
					_start_summon_spawn(uid, monster_id, action, summon_magic_name)
					return
		if creature.is_empty():
			var inferred_type := creature_type
			creature = {
				"uid": uid,
				"x": action.get("aimX", x) if _action_uses_aim_position(action_type) else x,
				"y": action.get("aimY", y) if _action_uses_aim_position(action_type) else y,
				"action_from_x": x,
				"action_from_y": y,
				"type": inferred_type,
				"name": "",
				"action_type": stored_action_type,
				"action_started_ms": Time.get_ticks_msec(),
				"action_speed": action.get("speed", 100),
				"action_magic_id": action.get("magicID", 0),
				"action_step": action_step,
				"direction": direction if direction >= 1 else (1 if inferred_type == 3 else _direction_to(x, y, action.get("aimX", x), action.get("aimY", y))),
			}
			if inferred_type == 1:
				creature["monster_id"] = monster_id
				var spawn_direction: int = _resources.monster_spawn_direction(monster_id) if action_type == 1 else 0
				if spawn_direction > 0:
					creature["direction"] = spawn_direction
				if action_type == 1 and _resources.monster_spawn_look(monster_id) > 0:
					creature["monster_stand_look"] = _resources.monster_spawn_look(monster_id)
			elif inferred_type == 3:
				creature["npc_id"] = game_state.uid_record_id(uid)
		else:
			if action_type == 14 or (action_type == 11 and creature_type == 2):
				creature["action_from_x"] = creature.get("x", x)
				creature["action_from_y"] = creature.get("y", y)
			else:
				creature["action_from_x"] = x
				creature["action_from_y"] = y
				creature["x"] = action.get("aimX", x) if _action_uses_aim_position(action_type) else x
				creature["y"] = action.get("aimY", y) if _action_uses_aim_position(action_type) else y
			creature["action_type"] = stored_action_type
			creature["action_started_ms"] = Time.get_ticks_msec()
			creature["action_speed"] = action.get("speed", 100)
			creature["action_magic_id"] = action.get("magicID", 0)
			creature["action_step"] = action_step
			if not (action_type == 11 and creature_type == 2) and direction >= 1:
				creature["direction"] = direction
		if creature_type == 1:
			stored_action_type = _configure_monster_form(creature, action_type, stored_action_type, action, is_new_creature, previous_creature)
			creature["action_type"] = stored_action_type
			continued_monster_action = creature.get("monster_transform_continued", false)
			creature.erase("monster_transform_continued")
		elif creature_type == 3:
			_configure_npc_motion(creature, action_type, action)
		game_state.update_creature(uid, creature)
		if is_new_creature and creature_type == 1:
			_query_initial_creature_state(uid, true)
			if action_type == 1:
				NetworkClient.send_query_corecord(uid)
		if action_type == 7 and stored_action_type != 10 and world_renderer.supports_monster_attack_magic(action.get("magicID", 0)):
			var attack_effect := action.duplicate(true)
			attack_effect["uid"] = uid
			game_state.add_magic_effect(attack_effect, "monster_attack")
		if creature_type == 1 and stored_action_type == 13:
			_queue_monster_death_effect(uid, creature)
		if creature_type == 1 and stored_action_type == 1:
			_queue_monster_spawn_effect(uid, creature)
		if creature_type == 1 and stored_action_type == 10:
			_queue_monster_transform_effect(uid, creature)
		if not continued_monster_action:
			var duration := _creature_action_duration(stored_action_type, action.get("speed", 100), creature, action.get("magicID", 0))
			if duration > 0.0:
				_schedule_creature_idle(uid, stored_action_type, creature.get("action_started_ms", 0), duration)
			_play_action_seff(uid, action, creature)


func _switch_player_map(map_uid: int, action: Dictionary) -> void:
	_action_request_gate.reset()
	_cancel_movement()
	_pickup_action_timer = -1.0
	_player_action_timer = -1.0
	_player_forced_action_queue.clear()
	_player_server_action_queue.clear()
	_player_server_move_active = false
	_player_post_forced_action = {}
	_locked_magic_target_uid = 0
	_magic_focus_uid = 0
	_follow_focus_uid = 0
	_attack_focus_uid = 0
	_summon_spawn_blockers.clear()
	game_state.switch_player_map(map_uid, action.get("x", 0), action.get("y", 0))
	if _load_world_map(game_state.player_map_id):
		game_state.player_map_name = world_renderer.world_resource.map_name
		AudioService.play_map_bgm(world_renderer.world_resource.bgm_id)
	else:
		AudioService.stop_bgm()
	_center_hero()
	# 6866F2 -> 6DE2CA stamps after the new map and player location are ready.
	_last_magic_request_ms = Time.get_ticks_msec()


func _start_summon_spawn(uid: int, monster_id: int, action: Dictionary, magic_name: String) -> void:
	var magic_id: int = _resources.magic_id(magic_name)
	if magic_id <= 0:
		return
	var token := Time.get_ticks_usec()
	_summon_spawn_blockers[uid] = {
		"token": token,
		"map_uid": game_state.player_map_uid,
		"monster_id": monster_id,
		"action": action.duplicate(true),
	}
	var effect := action.duplicate(true)
	effect["uid"] = uid
	effect["magicID"] = magic_id
	effect["aimX"] = action.get("x", 0)
	effect["aimY"] = action.get("y", 0)
	effect["summon_uid"] = uid
	game_state.add_magic_effect(effect, "summon_spawn")
	get_tree().create_timer(_summon_spawn_delay(magic_id)).timeout.connect(_finish_summon_spawn.bind(uid, token))


func _summon_spawn_delay(magic_id: int) -> float:
	var run_meta: PackedInt32Array = _resources.magic_layout(magic_id, MAGIC_STAGE_RUN)
	if run_meta.size() < 5:
		return 1.0
	var fps := 10.0 * maxi(1, run_meta[4]) / 100.0
	return maxf(0.1, 10.0 / fps)


func _finish_summon_spawn(uid: int, token: int) -> void:
	var blocker: Dictionary = _summon_spawn_blockers.get(uid, {})
	if blocker.is_empty() or blocker.get("token", 0) != token:
		return
	_summon_spawn_blockers.erase(uid)
	_remove_summon_spawn_effect(uid)
	if blocker.get("map_uid", 0) != game_state.player_map_uid or not game_state.get_creature(uid).is_empty():
		return
	var action: Dictionary = blocker.get("action", {})
	var x: int = action.get("x", 0)
	var y: int = action.get("y", 0)
	var monster_id: int = blocker.get("monster_id", 0)
	var direction: int = _resources.monster_spawn_direction(monster_id)
	if direction < 1:
		direction = 6
	game_state.update_creature(uid, {
		"uid": uid,
		"x": x,
		"y": y,
		"action_from_x": x,
		"action_from_y": y,
		"type": 1,
		"name": "",
		"monster_id": monster_id,
		"action_type": 2,
		"action_started_ms": Time.get_ticks_msec(),
		"action_speed": action.get("speed", 100),
		"action_magic_id": 0,
		"action_step": 0,
		"direction": direction,
	})
	NetworkClient.send_query_uid_buff(uid)
	NetworkClient.send_query_corecord(uid)


func _remove_summon_spawn_effect(uid: int) -> void:
	var pending: Array = []
	for effect_value in game_state.magic_effects:
		var effect: Dictionary = effect_value
		if effect.get("source", "") != "summon_spawn" or effect.get("summon_uid", 0) != uid:
			pending.append(effect)
	game_state.magic_effects = pending


func _load_world_map(map_id: int) -> bool:
	AudioService.stop_seff()
	map_loading_overlay.show()
	_map_loading_hide_serial += 1
	world_renderer.loading_map = true
	_on_map_load_progress(0, "")
	var loaded: bool = world_renderer.load_map(map_id)
	if loaded:
		call_deferred("_preload_visible_map_textures", _map_loading_hide_serial, game_state.player_x, game_state.player_y)
	else:
		world_renderer.loading_map = false
		map_loading_overlay.hide()
	return loaded


func _preload_visible_map_textures(serial: int, center_grid_x: int, center_grid_y: int) -> void:
	# Mirrors ProcessRun::loadMap(): map data accounts for 0..40%, then textures
	# around the hero are retrieved grid-by-grid for 40..100%.
	var resource: RefCounted = world_renderer.world_resource
	_on_map_load_progress(40, resource.map_name)
	await get_tree().process_frame

	var map_width: int = resource.width
	var map_height: int = resource.height
	var x0: int = clampi(center_grid_x - MAP_PRELOAD_WINDOW_WIDTH / 2 / GameState.GRID_XP - MAP_OBJECT_MAX_WIDTH, 0, map_width)
	var x1: int = clampi(center_grid_x + MAP_PRELOAD_WINDOW_WIDTH / 2 / GameState.GRID_XP + MAP_OBJECT_MAX_WIDTH, 0, map_width)
	var y0: int = clampi(center_grid_y - MAP_PRELOAD_WINDOW_HEIGHT / 2 / GameState.GRID_YP - MAP_OBJECT_MAX_HEIGHT, 0, map_height)
	var y1: int = clampi(center_grid_y + MAP_PRELOAD_WINDOW_HEIGHT / 2 / GameState.GRID_YP + MAP_OBJECT_MAX_HEIGHT, 0, map_height)
	var total_grid_count: int = maxi(1, (y1 - y0 + 1) * (x1 - x0 + 1))
	var done_grid_count := 0
	var last_ratio := 0

	for y in range(y0, y1):
		for x in range(x0, x1 + 1):
			if x < map_width and y < map_height:
				var cell_key: int = x + y * map_width
				if x % 2 == 0 and y % 2 == 0 and resource.tiles.has(cell_key):
					resource.texture(int(resource.tiles[cell_key]))
				for depth in [0, 1]:
					var cell_objects: Array = resource.objects[depth].get(cell_key, [])
					for object_data_value in cell_objects:
						var object_data: PackedInt32Array = object_data_value
						if not object_data.is_empty():
							resource.texture(object_data[0])

			var current_ratio := roundi(float(done_grid_count) * 60.0 / float(total_grid_count))
			done_grid_count += 1
			if current_ratio > last_ratio:
				last_ratio = current_ratio
				if serial != _map_loading_hide_serial:
					return
				_on_map_load_progress(40 + current_ratio, resource.map_name)
				await get_tree().process_frame

	if serial != _map_loading_hide_serial:
		return
	_on_map_load_progress(100, resource.map_name)
	await get_tree().process_frame
	await get_tree().create_timer(MAP_LOADING_COMPLETE_HOLD_SECONDS).timeout
	if serial == _map_loading_hide_serial:
		world_renderer.loading_map = false
		world_renderer.queue_redraw()
		map_loading_overlay.hide()


func _on_map_load_progress(progress: int, map_name: String) -> void:
	_set_map_loading_progress(progress, map_name)


func _set_map_loading_progress(progress: int, map_name: String) -> void:
	var display_name := map_name.get_slice("_", 0)
	if display_name.is_empty():
		display_name = "地图%d" % game_state.player_map_id
	map_loading_text.text = "[center]加载地图[color=red]%s[/color]\n完成[color=red]%%%d[/color][/center]" % [display_name, clampi(progress, 0, 100)]


func _spinkick_direction(uid: int, action: Dictionary) -> int:
	var explicit_direction := int(action.get("direction", 0))
	if explicit_direction >= 1 and explicit_direction <= 8:
		return explicit_direction
	var fallback: int = game_state.player_direction if uid == game_state.player_uid else int(game_state.get_creature(uid).get("direction", 5))
	var aim_uid := int(action.get("aimUID", 0))
	var aim: Dictionary
	if aim_uid == game_state.player_uid:
		aim = {"x": game_state.player_x, "y": game_state.player_y}
	else:
		aim = game_state.get_creature(aim_uid)
	if aim.is_empty():
		return fallback
	var x := int(action.get("x", 0))
	var y := int(action.get("y", 0))
	var aim_x := int(aim.get("x", 0))
	var aim_y := int(aim.get("y", 0))
	if maxi(absi(x - aim_x), absi(y - aim_y)) != 1:
		return fallback
	return _direction_to(aim_x, aim_y, x, y)


func _attack_direction(uid: int, action: Dictionary) -> int:
	var fallback: int = game_state.player_direction if uid == game_state.player_uid else int(game_state.get_creature(uid).get("direction", 5))
	var aim_uid := int(action.get("aimUID", 0))
	if aim_uid == 0:
		var requested: int = action.get("direction", 0)
		return requested if requested >= 1 and requested <= 8 else fallback
	var aim: Dictionary
	if aim_uid == game_state.player_uid:
		aim = {"x": game_state.player_x, "y": game_state.player_y}
	else:
		aim = game_state.get_creature(aim_uid)
	if aim.is_empty():
		return fallback
	var x := int(action.get("x", 0))
	var y := int(action.get("y", 0))
	var aim_x := int(aim.get("x", 0))
	var aim_y := int(aim.get("y", 0))
	if x == aim_x and y == aim_y:
		return fallback
	return _direction_to(x, y, aim_x, aim_y)


func _spell_direction(uid: int, action: Dictionary) -> int:
	var fallback: int = game_state.player_direction if uid == game_state.player_uid else int(game_state.get_creature(uid).get("direction", 5))
	var aim_x := int(action.get("aimX", action.get("x", 0)))
	var aim_y := int(action.get("aimY", action.get("y", 0)))
	var aim_uid := int(action.get("aimUID", 0))
	if aim_uid != 0:
		var aim: Dictionary
		if aim_uid == game_state.player_uid:
			aim = {"x": game_state.player_x, "y": game_state.player_y}
		else:
			aim = game_state.get_creature(aim_uid)
		if aim.is_empty():
			return fallback
		aim_x = int(aim.get("x", aim_x))
		aim_y = int(aim.get("y", aim_y))
	var x := int(action.get("x", 0))
	var y := int(action.get("y", 0))
	if x == aim_x and y == aim_y:
		return fallback
	return _direction_to(x, y, aim_x, aim_y)


func _has_pending_local_magic(magic_id: int) -> bool:
	var now := Time.get_ticks_msec()
	for effect_value in game_state.magic_effects:
		var effect: Dictionary = effect_value
		if effect.get("source", "") == "local_action" and int(effect.get("magicID", 0)) == magic_id and now - int(effect.get("start_time", 0)) < 1500:
			return true
	return false


func _action_uses_aim_position(action_type: int) -> bool:
	return action_type in [3, 5, 6]


func _creature_stored_action_type(action_type: int, creature_type: int, monster_id := 0) -> int:
	# C++ ClientMonster::onActionJump() immediately replaces the jump with a
	# standing motion at action.x/y. Keeping ACTION_JUMP here would freeze the
	# stand sprite at its final frame because only ACTION_STAND loops.
	if creature_type != 1:
		return action_type
	if action_type == 4:
		return 2
	# Most monsters are born standing. TaoDog redirects its look, while monk
	# zombies and sand stone men keep their look and play the real spawn motion.
	if action_type == 1 and _resources.monster_spawn_look(monster_id) == 0 and _resources.monster_spawn_effect_magic_id(monster_id) == 0:
		return 2
	return action_type


func _monster_action_flag(action: Dictionary) -> bool:
	var ext: PackedByteArray = action.get("extParam", PackedByteArray())
	return not ext.is_empty() and ext[0] != 0


func _configure_npc_motion(creature: Dictionary, action_type: int, action: Dictionary) -> void:
	if action_type == 1:
		creature["npc_motion"] = 0
	elif action_type == 2:
		var ext: PackedByteArray = action.get("extParam", PackedByteArray())
		creature["npc_motion"] = clampi(ext[0] if not ext.is_empty() else 0, 0, 2)
	else:
		return
	# ClientNPC aggregate construction leaves MotionNode::speed at SYS_DEFSPEED.
	creature["action_speed"] = 100


func _npc_motion_frame_count(npc_id: int, motion: int) -> int:
	if npc_id == 56:
		return 12
	if npc_id in [59, 64, 65]:
		return 1
	return 4 if motion in [0, 1] else 0


func _configure_monster_form(creature: Dictionary, action_type: int, stored_action_type: int, action: Dictionary, constructor_state: bool, previous := {}) -> int:
	var transform: Dictionary = _resources.monster_transform(creature.get("monster_id", 0))
	if transform.is_empty():
		return stored_action_type
	var current_mode := bool(creature.get("monster_stand_mode", false))
	creature.erase("monster_pending_action")
	var form_queue: Array = previous.get("monster_pending_form_modes", []).duplicate()
	var final_mode: bool = bool(form_queue.back()) if not form_queue.is_empty() else current_mode
	var was_transforming: bool = not constructor_state and previous.get("action_type", 0) == 10
	var requested_mode := current_mode
	match action_type:
		1:
			requested_mode = false
		2, 10:
			requested_mode = _monster_action_flag(action)
		3, 5, 7, 11:
			requested_mode = true
	if constructor_state:
		creature["monster_stand_mode"] = requested_mode
		creature.erase("monster_pending_form_modes")
		return stored_action_type
	if action_type in [4, 6]:
		creature.erase("monster_pending_form_modes")
		creature.erase("monster_pending_forced_action")
		creature["monster_stand_mode"] = final_mode
		return stored_action_type
	if action_type == 13 and (was_transforming or not form_queue.is_empty()):
		creature["monster_pending_forced_action"] = {
			"type": 13,
			"speed": action.get("speed", 100),
			"magic_id": action.get("magicID", 0),
			"action": action.duplicate(true),
			"state": _monster_pending_state(creature),
		}
		if not form_queue.is_empty():
			creature["monster_pending_form_modes"] = form_queue
		_restore_monster_transform_state(creature, previous, true)
		creature["monster_stand_mode"] = current_mode
		creature["monster_transform_continued"] = was_transforming
		return 10
	var form_request := action_type in [2, 10]
	var correction_action: bool = _resources.monster_motion_correction(creature.get("monster_id", 0), action_type)
	var queued_action: bool = action_type == 7 or (action_type == 11 and (transform.reveal_on_hit or was_transforming)) or (action_type == 2 and correction_action)
	var needs_reveal: bool = (action_type == 7 or (action_type == 11 and transform.reveal_on_hit) or (action_type == 2 and correction_action and requested_mode)) and not final_mode
	if form_request and not constructor_state and requested_mode != final_mode:
		if was_transforming:
			form_queue.append(requested_mode)
		else:
			current_mode = requested_mode
		stored_action_type = 10
	elif form_request and was_transforming:
		stored_action_type = 10
	elif action_type == 10:
		stored_action_type = previous.get("action_type", 2)
		_restore_monster_transform_state(creature, previous, true)
		creature["monster_transform_continued"] = true
	elif needs_reveal:
		if was_transforming:
			form_queue.append(true)
		else:
			current_mode = true
		stored_action_type = 10
	if queued_action and (stored_action_type == 10 or was_transforming):
		creature["monster_pending_action"] = {
			"type": action_type,
			"speed": action.get("speed", 100),
			"magic_id": action.get("magicID", 0),
			"action": action.duplicate(true),
			"state": _monster_pending_state(creature),
		}
		stored_action_type = 10
	if not form_queue.is_empty():
		creature["monster_pending_form_modes"] = form_queue
	else:
		creature.erase("monster_pending_form_modes")
	if stored_action_type == 10 and not constructor_state:
		_restore_monster_transform_state(creature, previous, was_transforming)
		creature["action_speed"] = previous.get("action_speed", 100) if was_transforming else 100
		creature["action_magic_id"] = previous.get("action_magic_id", 0) if was_transforming else 0
		creature["monster_transform_continued"] = was_transforming
	creature["monster_stand_mode"] = current_mode
	return stored_action_type


func _monster_pending_state(creature: Dictionary) -> Dictionary:
	var state := {}
	for key in ["x", "y", "action_from_x", "action_from_y", "direction", "action_step"]:
		if creature.has(key):
			state[key] = creature[key]
	return state


func _restore_monster_transform_state(creature: Dictionary, previous: Dictionary, restore_timing: bool) -> void:
	for key in ["x", "y", "action_from_x", "action_from_y", "direction", "action_step"]:
		if previous.has(key):
			creature[key] = previous[key]
	if restore_timing:
		for key in ["action_started_ms", "action_speed", "action_magic_id"]:
			if previous.has(key):
				creature[key] = previous[key]


func _start_creature_death_action(uid: int, action: Dictionary, creature: Dictionary) -> void:
	var start := Vector2i(creature.get("x", action.get("x", 0)), creature.get("y", action.get("y", 0)))
	var target := Vector2i(action.get("x", start.x), action.get("y", start.y))
	var max_step := 2 if creature.get("type", 0) == 2 else 1
	var queue: Array[Dictionary] = _forced_correction_steps(start, target, max_step)
	if start != target and queue.is_empty():
		return
	queue.append({"kind": "death", "action": action.duplicate(true)})
	creature["forced_action_queue"] = queue
	game_state.update_creature(uid, creature)
	_advance_creature_forced_action(uid)


func _start_monster_motion_action(uid: int, action: Dictionary, creature: Dictionary) -> void:
	var start := Vector2i(creature.get("x", action.get("x", 0)), creature.get("y", action.get("y", 0)))
	var target := Vector2i(action.get("x", start.x), action.get("y", start.y))
	var queue: Array[Dictionary] = _forced_correction_steps(start, target, 1)
	if start != target and queue.is_empty():
		return
	queue.append({"kind": "action", "action": action.duplicate(true)})
	creature["motion_action_queue"] = queue
	game_state.update_creature(uid, creature)
	_advance_creature_motion_action(uid)


func _start_remote_player_motion_action(uid: int, data: Dictionary, creature: Dictionary) -> void:
	var action: Dictionary = data.get("action", {})
	var start := Vector2i(creature.get("x", action.get("x", 0)), creature.get("y", action.get("y", 0)))
	var target := Vector2i(action.get("x", start.x), action.get("y", start.y))
	var queue: Array[Dictionary] = _forced_correction_steps(start, target, 1)
	if start != target and queue.is_empty():
		return
	queue.append({"kind": "player_action", "data": data.duplicate(true)})
	creature["motion_action_queue"] = queue
	game_state.update_creature(uid, creature)
	_advance_creature_motion_action(uid)


func _start_monster_current_hitted_action(uid: int, action: Dictionary, creature: Dictionary) -> void:
	var current_action := action.duplicate(true)
	current_action["x"] = creature.get("x", action.get("x", 0))
	current_action["y"] = creature.get("y", action.get("y", 0))
	current_action["direction"] = 1
	_start_monster_motion_action(uid, current_action, creature)


func _advance_creature_motion_action(uid: int) -> void:
	var creature: Dictionary = game_state.get_creature(uid)
	var queue: Array = creature.get("motion_action_queue", [])
	if creature.is_empty() or queue.is_empty():
		return
	var queued: Dictionary = queue.pop_front()
	if queue.is_empty():
		creature.erase("motion_action_queue")
	else:
		creature["motion_action_queue"] = queue
	creature["action_started_ms"] = Time.get_ticks_msec()
	creature["action_magic_id"] = 0
	if queued.get("kind", "") == "move":
		creature["action_from_x"] = queued.from_x
		creature["action_from_y"] = queued.from_y
		creature["x"] = queued.x
		creature["y"] = queued.y
		creature["direction"] = queued.direction
		creature["action_type"] = 3
		creature["action_speed"] = FORCED_MOVE_SPEED
		creature["action_step"] = 1
		game_state.update_creature(uid, creature)
		_schedule_creature_idle(uid, 3, creature.action_started_ms, _creature_action_duration(3, FORCED_MOVE_SPEED, creature))
		return
	if queued.get("kind", "") == "player_action":
		game_state.update_creature(uid, creature)
		_handle_action_data(queued.get("data", {}), true)
		return
	var action: Dictionary = queued.get("action", {})
	var action_type: int = action.get("type", 2)
	var action_x: int = action.get("x", creature.get("x", 0))
	var action_y: int = action.get("y", creature.get("y", 0))
	creature["action_from_x"] = action_x
	creature["action_from_y"] = action_y
	if _action_uses_aim_position(action_type):
		creature["x"] = action.get("aimX", action_x)
		creature["y"] = action.get("aimY", action_y)
	else:
		creature["x"] = action_x
		creature["y"] = action_y
	creature["direction"] = action.get("direction", creature.get("direction", 1))
	creature["action_type"] = _creature_stored_action_type(action_type, 1, creature.get("monster_id", 0))
	creature["action_speed"] = action.get("speed", 100)
	creature["action_magic_id"] = action.get("magicID", 0)
	creature["action_step"] = _grid_distance(Vector2i(action_x, action_y), Vector2i(creature.x, creature.y)) if action_type in [3, 5] else 0
	game_state.update_creature(uid, creature)
	if action_type == 11:
		game_state.trigger_shield_hit(uid)
	if action_type == 7 and world_renderer.supports_monster_attack_magic(action.get("magicID", 0)):
		var attack_effect := action.duplicate(true)
		attack_effect["uid"] = uid
		game_state.add_magic_effect(attack_effect, "monster_attack")
	_play_action_seff(uid, action, creature)
	var duration := _creature_action_duration(creature.action_type, creature.action_speed, creature, creature.action_magic_id)
	if duration > 0.0:
		_schedule_creature_idle(uid, creature.action_type, creature.action_started_ms, duration)


func _advance_creature_forced_action(uid: int) -> void:
	var creature: Dictionary = game_state.get_creature(uid)
	var queue: Array = creature.get("forced_action_queue", [])
	if creature.is_empty() or queue.is_empty():
		return
	var queued: Dictionary = queue.pop_front()
	if queue.is_empty():
		creature.erase("forced_action_queue")
	else:
		creature["forced_action_queue"] = queue
	creature["action_started_ms"] = Time.get_ticks_msec()
	creature["action_magic_id"] = 0
	if queued.get("kind", "") == "move":
		creature["action_from_x"] = queued.from_x
		creature["action_from_y"] = queued.from_y
		creature["x"] = queued.x
		creature["y"] = queued.y
		creature["direction"] = queued.direction
		creature["action_type"] = 3
		creature["action_speed"] = FORCED_MOVE_SPEED
		creature["action_step"] = queued.step
		game_state.update_creature(uid, creature)
		_schedule_creature_idle(uid, 3, creature.action_started_ms, _creature_action_duration(3, FORCED_MOVE_SPEED, creature))
		return
	var action: Dictionary = queued.get("action", {})
	creature["action_from_x"] = creature.get("x", 0)
	creature["action_from_y"] = creature.get("y", 0)
	creature["action_type"] = 13
	creature["action_speed"] = 100
	creature["action_step"] = 0
	game_state.update_creature(uid, creature)
	if creature.get("type", 0) == 1:
		_queue_monster_death_effect(uid, creature)
	_play_action_seff(uid, action, creature)


func _schedule_creature_idle(uid: int, action_type: int, started_ms: int, delay: float) -> void:
	_schedule_creature_idle_check(uid, action_type, started_ms, delay, delay)


func _schedule_creature_idle_check(uid: int, action_type: int, started_ms: int, duration: float, wait_time: float) -> void:
	get_tree().create_timer(wait_time).timeout.connect(func() -> void:
		var creature: Dictionary = game_state.get_creature(uid)
		if creature.is_empty() or creature.get("action_type", 0) != action_type or creature.get("action_started_ms", -1) != started_ms:
			return
		if action_type in [3, 5]:
			var remaining: float = duration - float(world_renderer.creature_movement_elapsed_seconds(uid, started_ms))
			if remaining > 0.001:
				_schedule_creature_idle_check(uid, action_type, started_ms, duration, remaining)
				return
		_finish_creature_action(uid, action_type, started_ms)
	)


func _finish_creature_action(uid: int, action_type: int, started_ms: int) -> void:
	var creature: Dictionary = game_state.get_creature(uid)
	if creature.is_empty() or creature.get("action_type", 0) != action_type or creature.get("action_started_ms", -1) != started_ms:
		return
	if not creature.get("forced_action_queue", []).is_empty():
		_advance_creature_forced_action(uid)
		return
	if not creature.get("motion_action_queue", []).is_empty():
		_advance_creature_motion_action(uid)
		return
	var pending: Dictionary = creature.get("monster_pending_action", {})
	var forced_pending: Dictionary = creature.get("monster_pending_forced_action", {})
	creature.erase("monster_pending_action")
	creature["action_started_ms"] = Time.get_ticks_msec()
	var form_queue: Array = creature.get("monster_pending_form_modes", [])
	if action_type == 10 and not form_queue.is_empty():
		creature["monster_stand_mode"] = bool(form_queue.pop_front())
		if form_queue.is_empty():
			creature.erase("monster_pending_form_modes")
		else:
			creature["monster_pending_form_modes"] = form_queue
		creature["action_speed"] = 100
		creature["action_magic_id"] = 0
		if not pending.is_empty():
			creature["monster_pending_action"] = pending
		game_state.update_creature(uid, creature)
		_queue_monster_transform_effect(uid, creature)
		_play_action_seff(uid, {"type": 10, "x": creature.get("x", 0), "y": creature.get("y", 0)}, creature)
		var transform_duration := _creature_action_duration(10, 100, creature)
		_schedule_creature_idle(uid, 10, creature.action_started_ms, transform_duration)
		return
	if action_type == 10 and not forced_pending.is_empty():
		creature.erase("monster_pending_forced_action")
		creature.erase("monster_pending_form_modes")
		game_state.update_creature(uid, creature)
		_start_creature_death_action(uid, forced_pending.get("action", {}), creature)
		return
	if action_type == 10 and not pending.is_empty():
		var pending_type: int = pending.get("type", 0)
		if pending_type == 11:
			game_state.update_creature(uid, creature)
			if _resources.monster_transform(creature.get("monster_id", 0)).get("reveal_on_hit", false):
				_start_monster_current_hitted_action(uid, pending.get("action", {}), creature)
			else:
				_start_monster_motion_action(uid, pending.get("action", {}), creature)
			return
		if _resources.monster_motion_correction(creature.get("monster_id", 0), pending_type):
			game_state.update_creature(uid, creature)
			_start_monster_motion_action(uid, pending.get("action", {}), creature)
			return
		for key in pending.get("state", {}):
			creature[key] = pending.state[key]
		creature["action_type"] = pending.get("type", 2)
		creature["action_speed"] = pending.get("speed", 100)
		creature["action_magic_id"] = pending.get("magic_id", 0)
		game_state.update_creature(uid, creature)
		_play_action_seff(uid, pending.get("action", {}), creature)
		var duration := _creature_action_duration(creature.action_type, creature.action_speed, creature, creature.action_magic_id)
		if duration > 0.0:
			_schedule_creature_idle(uid, creature.action_type, creature.action_started_ms, duration)
		return
	if creature.get("type", 0) == 3 and creature.get("npc_motion", 0) == 2:
		creature["npc_motion"] = 1
		creature["action_type"] = 2
		creature["action_speed"] = 100
		game_state.update_creature(uid, creature)
		return
	creature["action_type"] = 2
	game_state.update_creature(uid, creature)


func _handle_corecord(payload: PackedByteArray) -> void:
	var data := Protocol.decode_sm_corecord(payload)
	if data.get("mapUID", 0) != game_state.player_map_uid:
		return
	var uid: int = data.get("uid", 0)
	var action: Dictionary = data.get("action", {})
	if not game_state.get_creature(uid).is_empty():
		_handle_action_data({
			"uid": uid,
			"mapUID": data.get("mapUID", 0),
			"action": action,
		})
		return
	
	# Determine creature type from UID type bits
	# UID type is in bits 59-62 (4 bits at offset 59)
	# UID_NPC=3, UID_MON=4, UID_PLY=5
	var c_type := _creature_type_from_uid(uid)
	var action_type: int = action.get("type", 0)
	var direction: int = action.get("direction", 0)
	if action_type in [3, 5] and direction < 1:
		direction = _direction_to(
			action.get("x", 0), action.get("y", 0),
			action.get("aimX", action.get("x", 0)), action.get("aimY", action.get("y", 0)),
		)
	
	var creature: Dictionary = game_state.get_creature(uid)
	var is_new := creature.is_empty()
	if is_new and c_type not in [1, 2]:
		return
	if creature.is_empty():
		creature = {
			"uid": uid,
			"x": action.get("aimX", action.get("x", 0)) if _action_uses_aim_position(action.get("type", 0)) else action.get("x", 0),
			"y": action.get("aimY", action.get("y", 0)) if _action_uses_aim_position(action.get("type", 0)) else action.get("y", 0),
			"type": c_type,
			"name": "",
			"action_type": action_type,
			"action_started_ms": Time.get_ticks_msec(),
			"action_speed": action.get("speed", 100),
			"action_magic_id": action.get("magicID", 0),
			"action_from_x": action.get("x", 0),
			"action_from_y": action.get("y", 0),
			"direction": direction,
		}
	else:
		creature["action_from_x"] = action.get("x", 0)
		creature["action_from_y"] = action.get("y", 0)
		creature["x"] = action.get("aimX", action.get("x", 0)) if _action_uses_aim_position(action.get("type", 0)) else action.get("x", 0)
		creature["y"] = action.get("aimY", action.get("y", 0)) if _action_uses_aim_position(action.get("type", 0)) else action.get("y", 0)
		creature["type"] = c_type
		creature["action_type"] = action_type
		creature["action_started_ms"] = Time.get_ticks_msec()
		creature["action_speed"] = action.get("speed", 100)
		creature["action_magic_id"] = action.get("magicID", 0)
		if direction >= 1:
			creature["direction"] = direction
	
	# Parse union data for additional info
	var union_data: PackedByteArray = data.get("union_data", PackedByteArray())
	if union_data.size() >= 4:
		match c_type:
			1:  # Monster: MonsterID (u32)
				creature["monster_id"] = union_data.decode_u32(0)
			2:  # Player: gender:1, job:3, Level:32
				var gj: int = union_data[0]
				creature["gender"] = gj & 1
				creature["job"] = (gj >> 1) & 7
				creature["level"] = union_data.decode_u32(1) if union_data.size() >= 5 else 0
			3:  # NPC: NPCID (u32)
				creature["npc_id"] = union_data.decode_u32(0)
	if c_type == 1:
		var monster_id: int = creature.get("monster_id", game_state.uid_record_id(uid))
		creature["action_type"] = _creature_stored_action_type(action_type, c_type, monster_id)
		var spawn_direction: int = _resources.monster_spawn_direction(monster_id) if is_new and action_type == 1 else 0
		if spawn_direction > 0:
			creature["direction"] = spawn_direction
		if is_new and action_type == 1 and _resources.monster_spawn_look(monster_id) > 0:
			creature["monster_stand_look"] = _resources.monster_spawn_look(monster_id)
		creature["action_type"] = _configure_monster_form(creature, action_type, creature["action_type"], action, true, {})
	
	game_state.update_creature(uid, creature)
	_query_initial_creature_state(uid, is_new)
	var stored_action_type: int = creature.get("action_type", action_type)
	if c_type == 1 and stored_action_type == 13:
		_queue_monster_death_effect(uid, creature)
	if c_type == 1 and stored_action_type == 1:
		_queue_monster_spawn_effect(uid, creature)
	if c_type == 1 and stored_action_type == 10:
		_queue_monster_transform_effect(uid, creature)
	var duration := _creature_action_duration(stored_action_type, action.get("speed", 100), creature, action.get("magicID", 0))
	if duration > 0.0:
		_schedule_creature_idle(uid, stored_action_type, creature.get("action_started_ms", 0), duration)
	_play_action_seff(uid, action, creature)


func _query_initial_creature_state(uid: int, is_new: bool) -> Dictionary:
	if not is_new or _creature_type_from_uid(uid) not in [1, 2]:
		return {}
	var queries := {"buff": NetworkClient.send_query_uid_buff(uid)}
	if _creature_type_from_uid(uid) == 2:
		queries["name"] = NetworkClient.send_query_player_name(uid)
		queries["appearance"] = NetworkClient.send_query_player_wldesp(uid)
	return queries


func _queue_monster_death_effect(uid: int, creature: Dictionary) -> void:
	var magic_id: int = _resources.monster_death_magic_id(creature.get("monster_id", 0))
	if magic_id <= 0:
		return
	var started_ms: int = creature.get("action_started_ms", Time.get_ticks_msec())
	for effect_value in game_state.attached_magic_effects:
		var effect: Dictionary = effect_value
		if effect.get("kind", "") == "monster_death" and effect.get("target_uid", 0) == uid and effect.get("action_started_ms", -1) == started_ms:
			return
	game_state.attached_magic_effects.append({
		"magicID": magic_id,
		"target_uid": uid,
		"start_time": started_ms,
		"action_started_ms": started_ms,
		"cycles": 1,
		"kind": "monster_death",
		"stage": 2,
	})
	game_state.state_changed.emit()


func _queue_monster_transform_effect(uid: int, creature: Dictionary) -> void:
	var magic_id: int = _resources.monster_transform_effect_magic_id(creature.get("monster_id", 0))
	if magic_id <= 0:
		return
	var started_ms: int = creature.get("action_started_ms", Time.get_ticks_msec())
	for effect_value in game_state.magic_effects:
		var effect: Dictionary = effect_value
		if effect.get("source", "") == "monster_transform" and effect.get("uid", 0) == uid and effect.get("action_started_ms", -1) == started_ms:
			return
	var speed := clampi(creature.get("action_speed", 100), 20, 500)
	game_state.magic_effects.append({
		"magicID": magic_id,
		"uid": uid,
		"x": creature.get("x", 0),
		"y": creature.get("y", 0),
		"source": "monster_transform",
		"start_time": started_ms + roundi(9.0 * 100.0 * 100.0 / speed),
		"action_started_ms": started_ms,
	})
	game_state.state_changed.emit()


func _queue_monster_spawn_effect(uid: int, creature: Dictionary) -> void:
	var magic_id: int = _resources.monster_spawn_effect_magic_id(creature.get("monster_id", 0))
	if magic_id <= 0:
		return
	var started_ms: int = creature.get("action_started_ms", Time.get_ticks_msec())
	for effect_value in game_state.magic_effects:
		var effect: Dictionary = effect_value
		if effect.get("source", "") == "monster_spawn_ground" and effect.get("uid", 0) == uid and effect.get("action_started_ms", -1) == started_ms:
			return
	var speed := clampi(creature.get("action_speed", 100), 20, 500)
	game_state.magic_effects.append({
		"magicID": magic_id,
		"uid": uid,
		"x": creature.get("x", 0),
		"y": creature.get("y", 0),
		"direction": creature.get("direction", 1),
		"source": "monster_spawn_ground",
		"start_time": started_ms + roundi(9.0 * 100.0 * 100.0 / speed),
		"action_started_ms": started_ms,
	})
	game_state.state_changed.emit()


func _creature_type_from_uid(uid: int) -> int:
	match (uid >> 59) & 0xF:
		3: return 3 # NPC
		4: return 1 # Monster
		5: return 2 # Player
		_: return 0


func _handle_health(payload: PackedByteArray) -> void:
	var reader := CerealReader.new(payload)
	var data := reader.read_sd_health()
	if _reader_ok(reader, "SM_HEALTH"):
		game_state.update_entity_health(data)


func _handle_exp(payload: PackedByteArray) -> void:
	if payload.size() < 4:
		return
	var previous: int = game_state.player_exp
	var current: int = Protocol.decode_sm_exp(payload)
	game_state.update_exp(current)
	if current > previous and previous > 0:
		game_state.add_chat_log("你获得了经验值%d" % (current - previous), 1)


func _handle_gold(payload: PackedByteArray) -> void:
	if payload.size() < 4:
		return
	var previous: int = game_state.player_gold
	var current: int = Protocol.decode_sm_gold(payload)
	game_state.update_gold(current)
	if current > previous:
		_play_seff(0x0102006A, game_state.player_x, game_state.player_y)
	if current != previous:
		game_state.add_chat_log("你%s了%d金币" % ["获得" if current > previous else "失去", absi(current - previous)], 1)


func _process_ping() -> void:
	var current_ms := Time.get_ticks_msec()
	if not NetworkClient.is_connected_to_server():
		_ping_pending = false
		_last_ping_sent_ms = current_ms
		return
	if _ping_pending or current_ms <= _last_ping_sent_ms + PING_INTERVAL_MS:
		return
	_last_ping_sent_ms = current_ms
	var wire_tick := current_ms & U32_MASK
	if NetworkClient.send_ping(wire_tick) == OK:
		_ping_pending = true
		_ping_tick = wire_tick


func _handle_ping(payload: PackedByteArray) -> void:
	if payload.size() < 4 or not _ping_pending:
		return
	var echoed_tick: int = Protocol.decode_sm_ping(payload)
	if echoed_tick != _ping_tick:
		return
	var elapsed: int = ((Time.get_ticks_msec() & U32_MASK) - echoed_tick) & U32_MASK
	if elapsed > 0x7FFFFFFF:
		return
	_ping_pending = false
	game_state.add_chat_log("延迟%dms" % elapsed, 1)


func _handle_update_item(payload: PackedByteArray) -> void:
	var reader := CerealReader.new(payload)
	var item := reader.read_sd_update_item()
	if not _reader_ok(reader, "SM_UPDATEITEM"):
		return
	var item_id: int = item.get("itemID", 0)
	var item_count: int = item.get("count", 0)
	if item_id == 0 or item.get("seqID", 0) <= 0 or item_count <= 0 or not _resources.item_meta.has(item_id):
		return
	if _resources.item_type(item_id) != "金币" and item_count > (99 if _resources.item_is_packable(item_id) else 1):
		return
	var changed: int = game_state.update_item(item)
	if changed == 0:
		return
	var item_name: String = _resources.item_name(item_id)
	if _resources.item_is_packable(item_id):
		game_state.add_chat_log("你%s了%d个%s" % ["获得" if changed > 0 else "失去", absi(changed), item_name], 1)
	else:
		game_state.add_chat_log("你%s了%s" % ["获得" if changed > 0 else "失去", item_name], 1)
	if changed > 0:
		control_panel.call("start_button_blink", "Inventory", 5000)
		_play_seff(_resources.item_sound_effect(item_id), game_state.player_x, game_state.player_y)


func _handle_text(payload: PackedByteArray) -> void:
	# SM_TEXT is type-3 (variable), raw UTF-8 text bytes (not cereal)
	var text := payload.get_string_from_utf8()
	game_state.add_chat_log(text, 1)


func _handle_player_say(payload: PackedByteArray) -> void:
	var data := Protocol.decode_sm_player_say(payload)
	var uid: int = data.get("uid", 0)
	var content: String = data.get("content", "")
	var creature: Dictionary = game_state.get_creature(uid)
	if uid == game_state.player_uid or creature.get("type", 0) == 2:
		game_state.add_player_say(uid, content)
	if uid != game_state.player_uid:
		game_state.add_chat_log(content, 0)


func _handle_player_broadcast(payload: PackedByteArray) -> void:
	var data := Protocol.decode_sm_player_broadcast(payload)
	if data.is_empty():
		return
	var uid: int = data.get("uid", 0)
	var content: String = data.get("content", "")
	var player_name := ""
	if uid == game_state.player_uid:
		player_name = game_state.player_name
	else:
		var creature: Dictionary = game_state.get_creature(uid)
		if creature.get("type", 0) == 2:
			player_name = creature.get("name", "")
	game_state.add_chat_log("%s: %s" % [player_name, content] if not player_name.is_empty() else content, 1)


func _handle_inventory(payload: PackedByteArray) -> void:
	var reader := CerealReader.new(payload)
	var items := reader.read_sd_inventory()
	if _reader_ok(reader, "SM_INVENTORY"):
		game_state.update_inventory(items)


func _handle_belt(payload: PackedByteArray) -> void:
	var reader := CerealReader.new(payload)
	var items := reader.read_sd_belt()
	if _reader_ok(reader, "SM_BELT"):
		game_state.update_belt(items)


func _handle_ground_item_id_list(payload: PackedByteArray) -> void:
	var reader := CerealReader.new(payload)
	var data := reader.read_sd_ground_item_id_list()
	var map_uid: int = data.get("mapUID", 0)
	if map_uid != game_state.player_map_uid:
		return
	# The server sends incremental grid snapshots: only replace grids present in this message.
	game_state.update_ground_item_grids(data.get("grids", []))


func _handle_cast_magic(payload: PackedByteArray) -> void:
	var data := Protocol.decode_sm_cast_magic(payload)
	if data.is_empty() or data.get("mapUID", 0) != game_state.player_map_uid:
		return
	var magic_name: String = _resources.magic_names.get(data.get("magic", 0), "")
	if magic_name.is_empty():
		return
	game_state.add_cast_magic_attachment(data, magic_name)
	game_state.add_chat_log("使用魔法: %s" % magic_name, 1)


func _handle_miss(payload: PackedByteArray) -> void:
	var uid: int = Protocol.decode_sm_miss(payload)
	var c: Dictionary
	if uid == game_state.player_uid:
		c = {"x": game_state.player_x, "y": game_state.player_y}
	else:
		c = game_state.get_creature(uid)
		if c.is_empty():
			return
	var x: int = c.get("x", 0)
	var y: int = c.get("y", 0)
	game_state.add_ascend_miss(
		x * GameState.GRID_XP + GameState.GRID_XP / 2 - 20,
		y * GameState.GRID_YP - GameState.GRID_YP,
	)


func _handle_player_name(payload: PackedByteArray) -> void:
	var reader := CerealReader.new(payload)
	var data := reader.read_sd_player_name()
	if not _reader_ok(reader, "SM_PLAYERNAME"):
		return
	var uid: int = data.get("uid", 0)
	var name: String = data.get("name", "")
	var name_color := _normalize_player_name_color(data.get("nameColor", 0))
	if uid == game_state.player_uid:
		game_state.player_name = name
		game_state.player_name_color = name_color
		game_state.state_changed.emit()
		return
	var c: Dictionary = game_state.get_creature(uid)
	if c.get("type", 0) == 2:
		c["name"] = name
		c["name_color"] = name_color
		game_state.update_creature(uid, c)


func _normalize_player_name_color(value: int) -> int:
	var rgb := value & 0x00FFFFFF
	return 0xFF000000 | (rgb if rgb != 0 else 0x00FFFFFF)


func _handle_player_config(payload: PackedByteArray) -> void:
	var reader := CerealReader.new(payload)
	var config := reader.read_sd_player_config()
	if _reader_ok(reader, "SM_PLAYERCONFIG"):
		game_state.magic_keys = config.get("magicKeys", {})
		game_state.runtime_config = config.get("runtimeConfig", {})
		AudioService.apply_runtime_config(game_state.runtime_config)
		RuntimeConfigPanelScript.apply_display_config(game_state.runtime_config)
		game_state.state_changed.emit()


func _handle_player_wl_desp(payload: PackedByteArray) -> void:
	var reader := CerealReader.new(payload)
	var data := reader.read_sd_uid_wldesp()
	if not _reader_ok(reader, "SM_PLAYERWLDESP"):
		return
	var uid: int = data.get("uid", 0)
	if uid == game_state.player_uid:
		game_state.player_desp = data.get("desp", {})
		game_state.wear = game_state.player_desp.get("wear", {})
		game_state.state_changed.emit()
	elif not game_state.get_creature(uid).is_empty():
		var creature: Dictionary = game_state.get_creature(uid)
		creature["desp"] = data.get("desp", {})
		game_state.update_creature(uid, creature)


func _handle_buff_id_list(payload: PackedByteArray) -> void:
	var reader := CerealReader.new(payload)
	var data := reader.read_sd_buff_id_list()
	if not _reader_ok(reader, "SM_BUFFIDLIST"):
		return
	var uid: int = data.get("uid", 0)
	if uid == game_state.player_uid:
		game_state.buff_list = data.get("ids", [])
		game_state.state_changed.emit()
	elif not game_state.get_creature(uid).is_empty():
		var creature: Dictionary = game_state.get_creature(uid)
		creature["buffs"] = data.get("ids", [])
		game_state.update_creature(uid, creature)


func _handle_buff(payload: PackedByteArray) -> void:
	var data := Protocol.decode_sm_buff(payload)
	if data.get("type", 0) != BUFF_TYPE_SHIELD or data.get("state", 0) != BUFF_STATE_OFF:
		return
	var uid: int = data.get("uid", 0)
	if uid != game_state.player_uid:
		var creature: Dictionary = game_state.get_creature(uid)
		if creature.get("type", 0) != 2:
			return
	var shield_id: int = _resources.magic_id("魔法盾")
	if shield_id == 0:
		return
	var remaining: Array = []
	var removed := false
	for effect_value in game_state.attached_magic_effects:
		var effect: Dictionary = effect_value
		if effect.get("target_uid", 0) == uid and effect.get("magicID", 0) == shield_id:
			removed = true
		else:
			remaining.append(effect)
	if removed:
		game_state.attached_magic_effects = remaining
		game_state.state_changed.emit()


func _handle_equip_wear(payload: PackedByteArray) -> void:
	var reader := CerealReader.new(payload)
	var data := reader.read_sd_equip_wear()
	if not _reader_ok(reader, "SM_EQUIPWEAR"):
		return
	var uid: int = data.get("uid", 0)
	if uid == game_state.player_uid:
		game_state.wear[data.get("wltype", 0)] = data.get("item", {})
		var equipped: Dictionary = data.get("item", {})
		if game_state.grabbed_item.get("itemID", 0) == equipped.get("itemID", 0) and game_state.grabbed_item.get("seqID", 0) == equipped.get("seqID", 0):
			game_state.grabbed_item = {}
		_play_seff(_resources.item_sound_effect(int(equipped.get("itemID", 0))), game_state.player_x, game_state.player_y)
		game_state.state_changed.emit()
	elif not game_state.get_creature(uid).is_empty():
		var creature: Dictionary = game_state.get_creature(uid)
		var desp: Dictionary = creature.get("desp", {})
		var wear_data: Dictionary = desp.get("wear", {})
		wear_data[data.get("wltype", 0)] = data.get("item", {})
		desp["wear"] = wear_data
		creature["desp"] = desp
		game_state.update_creature(uid, creature)


func _handle_grab_wear(payload: PackedByteArray) -> void:
	var reader := CerealReader.new(payload)
	var data := reader.read_sd_grab_wear()
	if _reader_ok(reader, "SM_GRABWEAR"):
		game_state.wear.erase(data.get("wltype", 0))
		if not game_state.grabbed_item.is_empty():
			_play_seff(_resources.item_sound_effect(int(game_state.grabbed_item.get("itemID", 0))), game_state.player_x, game_state.player_y)
			game_state.inventory.append(game_state.grabbed_item)
		game_state.grabbed_item = data.get("item", {})
		_play_seff(_resources.item_sound_effect(int(game_state.grabbed_item.get("itemID", 0))), game_state.player_x, game_state.player_y)
		game_state.state_changed.emit()


func _handle_equip_belt(payload: PackedByteArray) -> void:
	var reader := CerealReader.new(payload)
	var data := reader.read_sd_equip_belt()
	if not _reader_ok(reader, "SM_EQUIPBELT"):
		return
	var slot: int = data.get("slot", -1)
	if slot >= 0 and slot < game_state.belt.size():
		var equipped: Dictionary = data.get("item", {})
		game_state.belt[slot] = equipped
		if game_state.grabbed_item.get("itemID", 0) == equipped.get("itemID", 0) and game_state.grabbed_item.get("seqID", 0) == equipped.get("seqID", 0):
			game_state.grabbed_item = {}
		_play_seff(_resources.item_sound_effect(int(equipped.get("itemID", 0))), game_state.player_x, game_state.player_y)
		game_state.state_changed.emit()


func _handle_grab_belt(payload: PackedByteArray) -> void:
	var reader := CerealReader.new(payload)
	var data := reader.read_sd_grab_belt()
	if not _reader_ok(reader, "SM_GRABBELT"):
		return
	var slot: int = data.get("slot", -1)
	if slot >= 0 and slot < game_state.belt.size():
		game_state.belt[slot] = {}
		if not game_state.grabbed_item.is_empty():
			_play_seff(_resources.item_sound_effect(int(game_state.grabbed_item.get("itemID", 0))), game_state.player_x, game_state.player_y)
			game_state.inventory.append(game_state.grabbed_item)
		game_state.grabbed_item = data.get("item", {})
		_play_seff(_resources.item_sound_effect(int(game_state.grabbed_item.get("itemID", 0))), game_state.player_x, game_state.player_y)
		game_state.state_changed.emit()


func _handle_pickup_error(payload: PackedByteArray) -> void:
	if payload.size() < 4:
		return
	var item_id := payload.decode_u32(0)
	if _resources.item_meta.has(item_id):
		game_state.add_chat_log("无法捡起%s" % _resources.item_name(item_id), 1)
	elif item_id > 0:
		game_state.add_chat_log("无法捡起物品ID = %d" % item_id, 1)
	else:
		game_state.add_chat_log("当前无法捡起物品，请稍后再试", 1)


func _handle_notify_dead(payload: PackedByteArray) -> void:
	var uid := Protocol.decode_sm_notify_dead(payload)
	if uid == 0:
		return
	if uid == game_state.player_uid:
		if not _player_forced_action_queue.is_empty():
			return
		_cancel_movement()
		_pickup_action_timer = -1.0
		_player_action_timer = -1.0
		_set_player_action(13)
		return
	var creature: Dictionary = game_state.get_creature(uid)
	if creature.is_empty() or creature.get("action_type", 0) == 13 or not creature.get("forced_action_queue", []).is_empty() or creature.get("monster_pending_forced_action", {}).get("type", 0) == 13:
		return
	var death_action := {
		"type": 13,
		"speed": 100,
		"direction": creature.get("direction", 1),
		"x": creature.get("x", 0),
		"y": creature.get("y", 0),
	}
	var previous := creature.duplicate(true)
	creature["action_type"] = 13
	creature["action_started_ms"] = Time.get_ticks_msec()
	creature["action_speed"] = 100
	creature["action_magic_id"] = 0
	if creature.get("type", 0) == 1:
		creature["action_type"] = _configure_monster_form(creature, 13, 13, death_action, false, previous)
		creature.erase("monster_transform_continued")
	game_state.update_creature(uid, creature)
	if creature.get("action_type", 0) == 13:
		_queue_monster_death_effect(uid, creature)
		_play_action_seff(uid, death_action, creature)


func _request_dead_fade_out(uid: int) -> void:
	var creature: Dictionary = game_state.get_creature(uid)
	var creature_type: int = creature.get("type", 0)
	if creature.get("action_type", 0) != 13:
		return
	if creature_type == 1 and not _resources.monster_dead_fade_out(creature.get("monster_id", 0)):
		return
	if creature_type != 1 and creature_type != 2:
		return
	creature["dead_fade_requested_ms"] = Time.get_ticks_msec()
	game_state.update_creature(uid, creature)


func _handle_equip_wear_error(payload: PackedByteArray) -> void:
	if payload.size() < 10:
		return
	var item_id := payload.decode_u32(0)
	match payload.decode_u16(8):
		1, 2: game_state.add_chat_log("无效的物品", 3)
		3: game_state.add_chat_log("无法放置：%s" % _resources.item_name(item_id), 3)


func _handle_grab_wear_error(payload: PackedByteArray) -> void:
	if payload.size() >= 2 and payload.decode_u16(0) == 2:
		game_state.add_chat_log("无法取下装备", 3)


func _handle_equip_belt_error(payload: PackedByteArray) -> void:
	if payload.size() < 10:
		return
	var item_id := payload.decode_u32(0)
	match payload.decode_u16(8):
		1, 2: game_state.add_chat_log("无效的物品", 3)
		3: game_state.add_chat_log("无法装备：%s" % _resources.item_name(item_id), 3)


func _handle_grab_belt_error(_payload: PackedByteArray) -> void:
	pass


func _handle_secured_items(payload: PackedByteArray) -> void:
	var reader := CerealReader.new(payload)
	var items := reader.read_sd_show_secured_item_list()
	if _reader_ok(reader, "SM_SHOWSECUREDITEMLIST"):
		_show_secured_items(items)


func _show_secured_items(items: Array) -> void:
	game_state.set_secured_items(items)
	var npc_panel := _extra_panel_nodes.get(NPC_CHAT_PANEL_PATH) as Control
	var secured_panel := _ensure_extra_panel(SECURED_ITEMS_PANEL_PATH)
	secured_panel.position = Vector2(0, npc_panel.size.y if npc_panel != null and npc_panel.visible else 0)
	secured_panel.call("_clamp_to_viewport")
	secured_panel.show()
	secured_panel.move_to_front()
	inventory_panel.position = Vector2(size.x - inventory_panel.size.x, 0)
	inventory_panel.call("_clamp_to_viewport")
	inventory_panel.show()
	inventory_panel.move_to_front()


func _handle_team_candidate(payload: PackedByteArray) -> void:
	var reader := CerealReader.new(payload)
	var candidate := reader.read_sd_team_candidate()
	if _reader_ok(reader, "SM_TEAMCANDIDATE"):
		game_state.add_team_candidate(candidate)


func _handle_team_members(payload: PackedByteArray) -> void:
	var reader := CerealReader.new(payload)
	var team := reader.read_sd_team_member_list()
	if _reader_ok(reader, "SM_TEAMMEMBERLIST"):
		game_state.set_team_member_list(team.get("teamLeader", 0), team.get("members", []))


func _handle_quest_list(payload: PackedByteArray) -> void:
	var reader := CerealReader.new(payload)
	var quests := reader.read_sd_quest_desp_list()
	if _reader_ok(reader, "SM_QUESTDESPLIST"):
		game_state.set_quest_list(quests)


func _handle_quest_update(payload: PackedByteArray) -> void:
	var reader := CerealReader.new(payload)
	var update := reader.read_sd_quest_desp_update()
	if not _reader_ok(reader, "SM_QUESTDESPUPDATE"):
		return
	game_state.update_quest_description(update.get("name", ""), update.get("fsm", ""), update.get("desp"), SYS_QSTFSM)
	var quest_panel := _extra_panel_nodes.get(QUEST_PANEL_PATH) as Control
	if quest_panel == null or not quest_panel.visible:
		control_panel.call("start_button_blink", "Quest")


func _handle_learned_magic(payload: PackedByteArray) -> void:
	var reader := CerealReader.new(payload)
	var magic_list := reader.read_sd_learned_magic_list()
	if _reader_ok(reader, "SM_LEARNEDMAGICLIST"):
		game_state.learned_magic = magic_list
		game_state.state_changed.emit()


func _handle_ground_firewalls(payload: PackedByteArray) -> void:
	var reader := CerealReader.new(payload)
	var data := reader.read_sd_ground_firewall_list()
	if _reader_ok(reader, "SM_GROUNDFIREWALLLIST") and data.get("mapUID", 0) == game_state.player_map_uid:
		var firewall_id: int = _resources.magic_id("火墙")
		var changes: Dictionary = game_state.reconcile_firewalls(
			data.get("firewalls", []),
			Time.get_ticks_msec(),
			_resources.magic_id("魔法特效_火焰灰烬"),
		)
		var seff_id: int = _resources.magic_seff(firewall_id, 2)
		for firewall_value in changes.get("added", []):
			var firewall: Dictionary = firewall_value
			_play_seff(seff_id, firewall.get("x", 0), firewall.get("y", 0))


func _handle_npc_xml(payload: PackedByteArray) -> void:
	var reader := CerealReader.new(payload)
	var data := reader.read_sd_npc_xml_layout()
	if _reader_ok(reader, "SM_NPCXMLLAYOUT"):
		game_state.npc_dialog = data
		game_state.state_changed.emit()
		var purchase_panel := _extra_panel_nodes.get(PURCHASE_PANEL_PATH) as Control
		if purchase_panel:
			purchase_panel.hide()
		_ensure_extra_panel("res://scenes/game/panels/npc_chat.tscn").show()


func _handle_npc_sell(payload: PackedByteArray) -> void:
	var reader := CerealReader.new(payload)
	var data := reader.read_sd_npc_sell()
	if _reader_ok(reader, "SM_NPCSELL"):
		_show_purchase(data)


func _show_purchase(data: Dictionary) -> void:
	game_state.set_npc_sell(data)
	var npc_panel := _extra_panel_nodes.get(NPC_CHAT_PANEL_PATH) as Control
	var purchase_panel := _ensure_extra_panel(PURCHASE_PANEL_PATH)
	purchase_panel.position = Vector2(0.0, npc_panel.size.y) if npc_panel and npc_panel.visible else Vector2.ZERO
	purchase_panel.call("_clamp_to_viewport")
	purchase_panel.show()
	purchase_panel.move_to_front()


func _handle_sell_item_list(payload: PackedByteArray) -> void:
	var reader := CerealReader.new(payload)
	var data := reader.read_sd_sell_item_list()
	if _reader_ok(reader, "SM_SELLITEMLIST"):
		game_state.npc_sell_detail = data if int(data.get("npcUID", 0)) == int(game_state.npc_sell.get("npcUID", 0)) else {}
		game_state.state_changed.emit()


func _handle_buy_succeed(payload: PackedByteArray) -> void:
	if payload.size() < 16:
		return
	var npc_uid := payload.decode_u64(0)
	var item_id := payload.decode_u32(8)
	var seq_id := payload.decode_u32(12)
	if game_state.npc_sell.get("npcUID", 0) != npc_uid or game_state.npc_sell_detail.get("npcUID", 0) != npc_uid or _resources.item_is_packable(item_id):
		return
	var list: Array = game_state.npc_sell_detail.get("list", [])
	for index in range(list.size()):
		var item: Dictionary = list[index].get("item", {})
		if item.get("itemID", 0) == item_id and item.get("seqID", 0) == seq_id:
			list.remove_at(index)
			game_state.npc_sell_detail["list"] = list
			game_state.state_changed.emit()
			return


func _handle_buy_error(payload: PackedByteArray) -> void:
	if payload.size() < 18:
		return
	game_state.add_chat_log("金币不够" if payload.decode_u16(16) == 4 else "购买失败", 3)


func _handle_start_input(payload: PackedByteArray) -> void:
	var reader := CerealReader.new(payload)
	var data := reader.read_sd_start_input()
	if _reader_ok(reader, "SM_STARTINPUT"):
		_pending_purchase = {}
		_pending_chat_group.clear()
		game_state.pending_input = data
		game_state.state_changed.emit()
		var panel := _ensure_extra_panel("res://scenes/game/panels/input_string.tscn")
		panel.configure(data.get("title", ""), data.get("show", false))


func _handle_start_inventory_operation(payload: PackedByteArray) -> void:
	var reader := CerealReader.new(payload)
	var operation := reader.read_sd_start_inv_op()
	if not _reader_ok(reader, "SM_STARTINVOP"):
		return
	game_state.start_inventory_operation(operation)
	inventory_panel.show()
	inventory_panel.position = Vector2(size.x - inventory_panel.size.x, 0)
	inventory_panel.call("_clamp_to_viewport")
	inventory_panel.move_to_front()


func _handle_inventory_operation_cost(payload: PackedByteArray) -> void:
	if payload.size() < 16:
		return
	game_state.set_inventory_operation_cost({
		"invOp": payload.decode_u32(0),
		"itemID": payload.decode_u32(4),
		"seqID": payload.decode_u32(8),
		"cost": payload.decode_u32(12),
	})


func _handle_friend_list(payload: PackedByteArray) -> void:
	var reader := CerealReader.new(payload)
	var friends := reader.read_sd_chat_peer_list()
	if _reader_ok(reader, "SM_FRIENDLIST"):
		game_state.set_chat_friends(friends)


func _handle_chat_message_list(payload: PackedByteArray) -> void:
	var reader := CerealReader.new(payload)
	var messages := reader.read_sd_chat_message_list()
	if not _reader_ok(reader, "SM_CHATMESSAGELIST"):
		return
	_apply_chat_messages(messages)


func _apply_chat_messages(messages: Array) -> void:
	for message in messages:
		game_state.add_chat_message(message)
		_query_chat_reference(message)
	control_panel.call("start_button_blink", "Friend", 5000)


func _query_chat_reference(message: Dictionary) -> void:
	var refer: Variant = message.get("refer")
	if refer == null or game_state.chat_messages.has(int(refer)):
		return
	NetworkClient.query_chat_message(int(refer), func(head: int, response: PackedByteArray):
		if head != NetworkClient.SM_OK:
			return
		var reader := CerealReader.new(response)
		var referenced := reader.read_sd_chat_message()
		if _reader_ok(reader, "CM_QUERYCHATMESSAGE"):
			game_state.cache_chat_message(referenced)
	)


func _handle_chat_group(payload: PackedByteArray) -> void:
	var reader := CerealReader.new(payload)
	var peer := reader.read_sd_chat_peer()
	if _reader_ok(reader, "SM_CREATECHATGROUP"):
		game_state.add_chat_group(peer, "你已经加入了群聊，现在就可以聊天了。")


func _handle_friend_result(payload: PackedByteArray, accepted: bool) -> void:
	var reader := CerealReader.new(payload)
	var peer := reader.read_sd_chat_peer()
	if not _reader_ok(reader, "SM_ADDFRIEND"):
		return
	_apply_friend_result(peer, accepted)


func _apply_friend_result(peer: Dictionary, accepted: bool) -> void:
	var name: String = peer.get("name", "对方")
	if accepted:
		var cpid := int(peer.get("cpid", 0))
		for current in game_state.chat_friends:
			if int(current.get("cpid", 0)) == cpid:
				return
		game_state.add_chat_peer(peer, true, "%s已经通过你的好友申请，现在可以开始聊天了。" % name)
		game_state.add_chat_log("%s已经通过了你的好友请求" % name, 1)
	else:
		game_state.add_chat_log("%s已经拒绝了你的好友请求" % name, 1)


func _reader_ok(reader: RefCounted, packet_name: String) -> bool:
	if not reader.valid:
		push_error("%s parse failed: %s" % [packet_name, reader.error])
		return false
	if not reader.at_end():
		push_error("%s has %d unread archive bytes" % [packet_name, reader.remaining()])
		return false
	return true


func _decode_u64_payload(buf: PackedByteArray, offset: int) -> int:
	if buf.size() < offset + 8:
		return 0
	return buf.decode_u32(offset) | (buf.decode_u32(offset + 4) << 32)


func _on_control_panel_panel_requested(scene_path: String) -> void:
	if scene_path.ends_with("/inventory.tscn"):
		_toggle_panel(inventory_panel)
	elif scene_path.ends_with("/player_state.tscn"):
		_toggle_panel(player_state_panel)
	elif scene_path.ends_with("/skill.tscn"):
		_toggle_panel(skill_panel)
	elif scene_path == TEAM_PANEL_PATH:
		if _player_has_team():
			_toggle_extra_panel(scene_path)
			var team_panel := _extra_panel_nodes.get(scene_path) as Control
			if team_panel != null and team_panel.visible:
				team_panel.call("_reset_scroll")
		else:
			_set_team_flag_cursor(true)
	else:
		_toggle_extra_panel(scene_path)


func _player_has_team() -> bool:
	for member_value in game_state.team_members:
		if member_value is Dictionary and int(member_value.get("uid", 0)) == game_state.player_uid:
			return true
	return false


func _set_team_flag_cursor(active: bool) -> void:
	_team_flag_active = active
	team_flag_cursor.visible = active
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN if active else Input.MOUSE_MODE_VISIBLE)
	if active:
		_update_team_flag_cursor()


func _update_team_flag_cursor() -> void:
	if not _team_flag_active:
		return
	var frame_index := _team_flag_frame_index(Time.get_ticks_msec())
	var frame: Dictionary = _resources.frame("proguse", 0x210 + frame_index)
	if not frame.is_empty():
		team_flag_cursor.texture = frame.texture
		team_flag_cursor.size = frame.texture.get_size()
	team_flag_cursor.position = get_viewport().get_mouse_position()


func _team_flag_frame_index(now_ms: int) -> int:
	return int(now_ms / 200) % 13


func _request_team_flag_target(uid: int) -> Error:
	if uid != game_state.player_uid and game_state.get_creature(uid).get("type", 0) != 2:
		return ERR_INVALID_PARAMETER
	return NetworkClient.send_request_join_team(uid)


func _on_control_panel_quick_bar_toggled() -> void:
	if not quick_bar.visible:
		quick_bar.call("place_initial", control_panel.call("quick_bar_initial_y"))
	quick_bar.visible = not quick_bar.visible


func _on_control_panel_magic_key_hud_toggled() -> void:
	game_state.magic_key_hud_visible = not game_state.magic_key_hud_visible
	game_state.state_changed.emit()


func minimap_hud_width() -> float:
	var panel := _extra_panel_nodes.get(MINIMAP_PANEL_PATH) as Control
	if panel == null or not panel.visible:
		return 0.0
	var texture_rect := panel.get_node_or_null("MapViewport/MapTexture") as TextureRect
	return panel.size.x if texture_rect != null and texture_rect.texture != null else 0.0


func _on_quick_bar_close_pressed() -> void:
	AudioService.play_ui_click()
	quick_bar.hide()


func _toggle_panel(panel: Control) -> void:
	panel.visible = not panel.visible
	if panel.visible:
		panel.move_to_front()


func _toggle_extra_panel(scene_path: String) -> void:
	var panel := _ensure_extra_panel(scene_path)
	if not panel:
		return
	if scene_path == MINIMAP_PANEL_PATH:
		if not panel.call("has_map_texture"):
			game_state.add_chat_log("没有可用的地图", 3)
			return
		panel.call("toggle_requested_visibility")
		if panel.visible:
			panel.move_to_front()
		return
	_toggle_panel(panel)


func _ensure_extra_panel(scene_path: String) -> Control:
	var panel := _extra_panel_nodes.get(scene_path) as Control
	if panel:
		return panel
	var packed := load(scene_path) as PackedScene
	if not packed:
		return null
	panel = packed.instantiate() as Control
	add_child(panel)
	panel.z_index = int(EXTRA_PANEL_DRAW_LAYERS.get(scene_path, 0))
	panel.position = _extra_panel_initial_position(scene_path, panel.size)
	if scene_path == MINIMAP_PANEL_PATH:
		panel.move_requested.connect(_on_minimap_move_requested)
		panel.call("set_requested_visible", true)
	else:
		panel.hide()
	_extra_panel_nodes[scene_path] = panel
	if scene_path.ends_with("/input_string.tscn") and panel.has_signal("committed"):
		panel.committed.connect(_on_input_committed)
		panel.cancelled.connect(_on_input_cancelled)
	if scene_path.ends_with("/purchase.tscn") and panel.has_signal("quantity_requested"):
		panel.quantity_requested.connect(_on_purchase_quantity_requested)
	if scene_path == FRIEND_CHAT_PANEL_PATH and panel.has_signal("group_name_requested"):
		panel.group_name_requested.connect(_on_friend_group_name_requested)
	return panel


func _extra_panel_initial_position(scene_path: String, panel_size: Vector2) -> Vector2:
	var renderer_center := Vector2(floorf(size.x * 0.5), floorf(size.y * 0.5))
	match scene_path:
		"res://scenes/game/panels/horse.tscn":
			return renderer_center + Vector2(-128, -161)
		"res://scenes/game/panels/guild.tscn":
			return renderer_center + Vector2(-297, -222)
		QUEST_PANEL_PATH:
			return renderer_center + Vector2(-145, -223)
		TEAM_PANEL_PATH:
			return renderer_center + Vector2(-129, -122)
		FRIEND_CHAT_PANEL_PATH:
			return renderer_center + Vector2(-250, -250)
		"res://scenes/game/panels/runtime_config.tscn":
			return renderer_center + Vector2(-255, -234)
		"res://scenes/game/panels/input_string.tscn":
			return renderer_center + Vector2(-179, -134)
		SECURED_ITEMS_PANEL_PATH, PURCHASE_PANEL_PATH, NPC_CHAT_PANEL_PATH:
			return Vector2.ZERO
		MINIMAP_PANEL_PATH:
			return Vector2(size.x - panel_size.x, 0.0)
		_:
			return (size - panel_size) * 0.5


func _on_input_committed(value: String) -> void:
	if not _pending_purchase.is_empty():
		var count := value.to_int()
		if count > 0:
			NetworkClient.send_buy(
				_pending_purchase.get("npcUID", 0),
				_pending_purchase.get("itemID", 0),
				0,
				count,
			)
		else:
			game_state.add_chat_log("无效输入:%s" % value, 3)
		_pending_purchase = {}
		return
	if not _pending_chat_group.is_empty():
		var ids := _pending_chat_group.duplicate()
		_pending_chat_group.clear()
		if value.is_empty():
			game_state.add_chat_log("无效输入:%s" % value, 3)
			return
		var friend_panel := _ensure_extra_panel(FRIEND_CHAT_PANEL_PATH)
		friend_panel.call("create_group_named", value, ids)
		return
	var input: Dictionary = game_state.pending_input
	NetworkClient.send_npc_event(input.get("uid", 0), "", input.get("commitTag", ""), value)
	game_state.pending_input = {}


func _on_input_cancelled() -> void:
	_pending_purchase = {}
	_pending_chat_group.clear()
	game_state.pending_input = {}


func _on_purchase_quantity_requested(npc_uid: int, item_id: int, item_name: String) -> void:
	_pending_chat_group.clear()
	game_state.pending_input = {}
	_pending_purchase = {"npcUID": npc_uid, "itemID": item_id}
	var panel := _ensure_extra_panel("res://scenes/game/panels/input_string.tscn")
	panel.configure("请输入你要购买%s的数量" % item_name, false)


func _on_friend_group_name_requested(ids: Array) -> void:
	_pending_purchase = {}
	game_state.pending_input = {}
	_pending_chat_group = ids.duplicate()
	var panel := _ensure_extra_panel("res://scenes/game/panels/input_string.tscn")
	panel.configure("请输入你要建立的群名称", false)
