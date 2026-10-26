extends Node
func _ready() -> void:
 NetworkClient.disconnect_from_server()
 GameState.player_uid = 101
 GameState.player_map_uid = 1 << 35
 GameState.player_hp = 100
 var main = load("res://scenes/game/main.tscn").instantiate()
 add_child(main)
 main.set_process(false)
 await get_tree().create_timer(0.4).timeout
 # Match the zero-initialized C++ ActionHitted wire layout independently.
 var payload := PackedByteArray()
 payload.resize(43)
 payload.encode_u64(0, 101)
 payload.encode_u64(8, 1 << 35)
 payload.encode_u16(16, 11) # type=11; speed bits remain zero
 payload[18] = 3
 payload.encode_s16(19, 10)
 payload.encode_s16(21, 10)
 main.call("_on_server_message", NetworkClient.SM_ACTION, payload)
 if GameState.player_action_speed != 100:
  push_error("Zero wire speed must use default Hero hit speed")
  get_tree().quit(1)
  return
 var peer_uid: int = (5 << 59) | 302
 GameState.update_creature(peer_uid, {"uid":peer_uid,"type":2,"x":12,"y":10,"direction":3,"action_type":2})
 payload.encode_u64(0, peer_uid)
 main.call("_on_server_message", NetworkClient.SM_ACTION, payload)
 if GameState.get_creature(peer_uid).get("action_speed", 0) != 100:
  push_error("Remote Hero hit must also use default speed")
  get_tree().quit(1)
  return
 GameState.player_action_started_ms = Time.get_ticks_msec() - 150
 main.call("_process_player_action", 1.0 / 30.0)
 if GameState.player_action_type != 11:
  push_error("Hit ended before its original duration")
  get_tree().quit(1)
  return
 GameState.player_action_started_ms = Time.get_ticks_msec() - 350
 main.call("_process_player_action", 1.0 / 30.0)
 if GameState.player_action_type != 2 or main.get("_player_action_timer") >= 0:
  push_error("Hit visual finished but input recovery still waits on capped movement clock")
  get_tree().quit(1)
  return
 print("HIT RECOVERY CLOCK PASS: preserves 300ms; no extra wait after delayed frame")
 get_tree().quit()
