extends Node

const Protocol = preload("res://scripts/network/protocol.gd")
var main: Control
var role := ""
var exchange := ""
var expected_uid := 0
var started := false
var finished := false
var sent: Dictionary = {}
var verified: Dictionary = {}
var received: Array[Dictionary] = []
var magic_ids: Array[int] = []
var next_magic := 0
var capturing := 0
var lifetime := false
var cast_times: Dictionary = {}
var cast_counts: Dictionary = {}
var loop_verified: Dictionary = {}
var off_types: Dictionary = {}
var recast_sent := false
var lifetime_done := false
var replay := false
var replay_stage := "wait_on"
var replay_records := 0
var replay_on_count := 0
var replay_off_count := 0
var replay_started_ms := 0
var replay_start_times: Dictionary = {}

func _ready() -> void:
	role = OS.get_environment("MIR3_MAGIC_SCOPE_ROLE")
	exchange = OS.get_environment("MIR3_MAGIC_SCOPE_EXCHANGE")
	lifetime = OS.get_environment("MIR3_MAGIC_SCOPE_LIFETIME") == "1"
	replay = OS.get_environment("MIR3_MAGIC_SCOPE_REPLAY") == "1"
	if replay and role == "observer":
		var caster: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(exchange + "/caster.json"))
		expected_uid = int(caster.uid)
	NetworkClient.connection_changed.connect(func(connected, _message):
		if connected: NetworkClient.login("id_4" if role == "caster" else "id_3", "123456"))
	NetworkClient.message_received.connect(_message)
	NetworkClient.connect_to_server()
	get_tree().create_timer(40.0 if lifetime else 25.0).timeout.connect(func(): _fail("overall timeout"))

func _message(head: int, payload: PackedByteArray) -> void:
	if finished: return
	if head == NetworkClient.SM_LOGINOK:
		NetworkClient.enter_game()
	elif head == NetworkClient.SM_ONLINEOK:
		var data := Protocol.decode_sm_online_ok(payload)
		GameState.set_player_online({"uid": data.uid, "name": data.name, "gender": data.gender, "job": data.job,
			"map_uid": data.mapUID, "x": data.action.x, "y": data.action.y, "direction": data.action.direction})
		main = load("res://scenes/game/main.tscn").instantiate()
		add_child(main)
		var resources: RefCounted = main.get("_resources")
		magic_ids = [resources.magic_id("魔法盾"), resources.magic_id("阴阳法环")]
	elif head == NetworkClient.SM_CASTMAGIC:
		var data := Protocol.decode_sm_cast_magic(payload)
		if not data.is_empty() and data.uid == expected_uid and int(data.magic) in magic_ids:
			if replay and role == "observer":
				_fail("late observer received a fresh cast instead of snapshot")
				return
			received.append(data)
			off_types.erase(1 if int(data.magic) == magic_ids[0] else 2)
			cast_times[int(data.magic)] = Time.get_ticks_msec()
			cast_counts[int(data.magic)] = int(cast_counts.get(int(data.magic), 0)) + 1
	elif head == NetworkClient.SM_CORECORD and replay and role == "observer":
		var record := Protocol.decode_sm_corecord(payload)
		if record.get("uid", 0) == expected_uid: replay_records += 1
	elif head == NetworkClient.SM_BUFF and (lifetime or replay):
		var buff := Protocol.decode_sm_buff(payload)
		if replay and role == "observer" and buff.get("uid", 0) == expected_uid:
			if buff.get("state", 0) == 1: replay_on_count += 1
			elif buff.get("state", 0) == 2: replay_off_count += 1
		if buff.get("uid", 0) == expected_uid and buff.get("state", 0) == 2:
			off_types[int(buff.type)] = Time.get_ticks_msec()
			print("AURA OFF role=%s type=%d" % [role, int(buff.type)])
	elif head in [NetworkClient.SM_LOGINERROR, NetworkClient.SM_ONLINEERROR]:
		_fail("login rejected")

func _process(_delta: float) -> void:
	if finished or main == null or main.get_node("MapLoadingOverlay").visible or GameState.player_hp <= 0:
		return
	if not started:
		if role == "caster":
			expected_uid = GameState.player_uid
			FileAccess.open(exchange + "/caster.json", FileAccess.WRITE).store_string(JSON.stringify({"uid": str(expected_uid)}))
			started = true
		elif FileAccess.file_exists(exchange + "/caster.json"):
			var caster: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(exchange + "/caster.json"))
			expected_uid = int(caster.uid)
			var actor: Dictionary = GameState.get_creature(expected_uid)
			if actor.is_empty(): return
			main.set_process(false)
			GameState.view_x = int(actor.x) * 48 - 400
			GameState.view_y = int(actor.y) * 32 - 280
			FileAccess.open(exchange + "/observer.ready", FileAccess.WRITE).store_string("ready")
			started = true
		else:
			return
	var renderer: Node = main.get_node("WorldRenderer")
	renderer.queue_redraw()
	if replay and role == "observer":
		_check_replay(renderer)
		return
	for packet in received:
		var magic_id: int = packet.magic
		if verified.has(magic_id): continue
		var active: Dictionary = renderer.call("_resolve_attached_magic", Time.get_ticks_msec())
		var kind := "shield" if magic_id == magic_ids[0] else "yin_yang_ring"
		var matches: Array = active.get(expected_uid, []).filter(func(effect): return effect.magic_id == magic_id and effect.kind == kind)
		if packet.mapUID != GameState.player_map_uid:
			_fail("wire map=%d expected=%d magic=%d rendered_matches=%d" % [packet.mapUID, GameState.player_map_uid, magic_id, matches.size()])
			return
		if matches.is_empty():
			_fail("valid scoped reply did not create resolved attachment magic=%d" % magic_id)
			return
		var effect: Dictionary = matches[0]
		var resources: RefCounted = main.get("_resources")
		if resources.frame("magic", effect.meta[0] + effect.direction * effect.meta[3] + effect.frame).is_empty():
			_fail("resolved attachment has no actual sprite")
			return
		verified[magic_id] = true
		if role == "observer": _capture(magic_id)
		print("MAGIC MAP SCOPE VERIFIED role=%s magic=%d map=%d" % [role, magic_id, packet.mapUID])
	if lifetime and verified.size() == magic_ids.size():
		_check_lifetime(renderer)
		if finished: return
	if role == "caster":
		if not replay and not FileAccess.file_exists(exchange + "/observer.ready"): return
		if next_magic < magic_ids.size():
			var mid := magic_ids[next_magic]
			if sent.has(mid):
				if verified.has(mid): next_magic += 1
				return
			if main.get("_player_action_timer") >= 0.0 or not main.call("_action_request_ready"):
				return
			# Protocol fixture: exercise normal action transport and real replies;
			# do not claim that this validates class/skill-book learning rules.
			if not main.call("_send_spell_action", 9, mid, Vector2i(GameState.player_x, GameState.player_y), GameState.player_uid):
				_fail("could not submit spell fixture")
				return
			sent[mid] = true
		elif replay:
			FileAccess.open(exchange + "/auras.ready", FileAccess.WRITE).store_string("ready")
			if FileAccess.file_exists(exchange + "/observer.done"): _pass()
		elif lifetime and not recast_sent:
			if Time.get_ticks_msec() - int(cast_times.get(magic_ids[0], Time.get_ticks_msec())) < 5000: return
			if main.get("_player_action_timer") >= 0.0 or not main.call("_action_request_ready"): return
			if not main.call("_send_spell_action", 9, magic_ids[0], Vector2i(GameState.player_x, GameState.player_y), GameState.player_uid):
				_fail("could not submit shield recast")
				return
			recast_sent = true
		elif (not lifetime or lifetime_done) and FileAccess.file_exists(exchange + "/observer.done"):
			_pass()
	elif verified.size() == magic_ids.size() and capturing == 0 and (not lifetime or lifetime_done):
		FileAccess.open(exchange + "/observer.done", FileAccess.WRITE).store_string("done")
		_pass()

func _check_replay(renderer: Node) -> void:
	if replay_started_ms == 0: replay_started_ms = Time.get_ticks_msec()
	var active: Dictionary = renderer.call("_resolve_attached_magic", Time.get_ticks_msec())
	var effects: Array = active.get(expected_uid, [])
	var resources: RefCounted = main.get("_resources")
	match replay_stage:
		"wait_on", "wait_repeat", "wait_recreate":
			var required_on := 2 if replay_stage == "wait_on" else (4 if replay_stage == "wait_repeat" else 6)
			if replay_on_count < required_on:
				if Time.get_ticks_msec() - replay_started_ms > 3000:
					_fail("missing aura snapshot state stage=%s records=%d ON=%d" % [replay_stage, replay_records, replay_on_count])
				return
			if effects.size() != 2:
				_fail("snapshot did not create exactly two auras: %s" % effects)
				return
			for effect in effects:
				if int(effect.magic_id) not in magic_ids or effect.meta != resources.magic_loop_layout(effect.magic_id, 2):
					_fail("snapshot did not start directly on loop continuation")
					return
			for effect in GameState.attached_magic_effects:
				if effect.get("target_uid", 0) != expected_uid: continue
				var mid: int = effect.magicID
				if replay_stage == "wait_repeat" and int(effect.start_time) != int(replay_start_times[mid]):
					_fail("duplicate snapshot reset aura playback")
					return
				replay_start_times[mid] = effect.start_time
			if replay_stage == "wait_on":
				_capture(magic_ids[1])
				replay_stage = "wait_repeat"
				NetworkClient.send_query_corecord(expected_uid)
			elif replay_stage == "wait_repeat":
				GameState.remove_creature(expected_uid)
				NetworkClient.send_query_corecord(expected_uid)
				replay_stage = "wait_recreate"
			else:
				replay_stage = "wait_expiry"
			replay_started_ms = Time.get_ticks_msec()
		"wait_expiry":
			if replay_off_count < 2: return
			if not effects.is_empty():
				# The two real timers may expire in separate network frames.
				if replay_off_count >= 2: _fail("expiry retained snapshot aura")
				return
			NetworkClient.send_query_corecord(expected_uid)
			replay_stage = "wait_expired_snapshot"
		"wait_expired_snapshot":
			if replay_off_count < 4: return
			if not effects.is_empty() or replay_on_count != 6 or replay_records < 4:
				_fail("expired snapshot resurrected an aura")
				return
			FileAccess.open(exchange + "/observer.done", FileAccess.WRITE).store_string("done")
			print("AURA REPLAY PASS observer: late login without cast, duplicate preservation, UID recreation, actual expiry, expired snapshot")
			_pass()

func _check_lifetime(renderer: Node) -> void:
	var active: Dictionary = renderer.call("_resolve_attached_magic", Time.get_ticks_msec())
	var resources: RefCounted = main.get("_resources")
	for index in magic_ids.size():
		var mid := magic_ids[index]
		var matches: Array = active.get(expected_uid, []).filter(func(effect): return effect.magic_id == mid)
		var off_type := index + 1
		if off_types.has(off_type):
			if not matches.is_empty():
				_fail("OFF did not remove matching aura type=%d" % off_type)
				return
			if Time.get_ticks_msec() - int(cast_times[mid]) < 9000:
				_fail("old expiry closed recast aura type=%d" % off_type)
				return
			continue
		if matches.size() != 1:
			_fail("sustained aura missing or stacked magic=%d count=%d" % [mid, matches.size()])
			return
		if Time.get_ticks_msec() - int(cast_times[mid]) >= 3000:
			if matches[0].meta != resources.magic_loop_layout(mid, 2):
				_fail("sustained aura used intro instead of continuation")
				return
			if not loop_verified.has(mid):
				print("AURA LOOP role=%s magic=%d gfx=%08X frames=%d" % [role, mid, matches[0].meta[0], matches[0].meta[2]])
				if role == "observer": _capture(mid)
			loop_verified[mid] = true
	if off_types.has(2) and not off_types.has(1) and cast_counts.get(magic_ids[0], 0) == 2:
		loop_verified["independent_off"] = true
	lifetime_done = off_types.has(1) and off_types.has(2) and loop_verified.size() == 3 and cast_counts.get(magic_ids[0], 0) == 2

func _capture(magic_id: int) -> void:
	capturing += 1
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(exchange + "/magic-%d.png" % magic_id)
	capturing -= 1

func _pass() -> void:
	finished = true
	print("NETWORK MAGIC MAP SCOPE PASS " + role + ": shield and yin-yang actual wire map and resolved attachments")
	if lifetime: print("AURA LIFETIME PASS " + role + ": loop textures, recast replacement, stale expiry suppression, independent OFF")
	NetworkClient.disconnect_from_server()
	get_tree().quit()

func _fail(message: String) -> void:
	if finished: return
	finished = true
	push_error("MAGIC MAP SCOPE " + role + " " + message)
	NetworkClient.disconnect_from_server()
	get_tree().quit(1)
