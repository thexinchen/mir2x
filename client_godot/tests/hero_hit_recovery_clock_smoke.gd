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
 main.call("_handle_action_data", {"uid":101,"mapUID":1 << 35,"action":{"type":11,"speed":100,"direction":3,"x":10,"y":10}})
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
