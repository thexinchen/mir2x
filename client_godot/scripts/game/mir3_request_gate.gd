extends RefCounted

# Original 691260 / 691738 / 68F808: strict timeout, then deny that check.
const TIMEOUT_MS := 10000
var pending_token := 0
var sent_ms := 0
var _serial := 0
var _deny_next_check := false

func begin(now_ms: int) -> int:
	_serial += 1
	pending_token = _serial
	sent_ms = now_ms
	_deny_next_check = false
	return pending_token

func ready(now_ms: int) -> bool:
	if _deny_next_check:
		_deny_next_check = false
		return false
	if pending_token == 0:
		return true
	if now_ms - sent_ms > TIMEOUT_MS:
		pending_token = 0
	# A timeout clears the flag but still rejects this particular check.
	return false

func complete(token: int) -> bool:
	if token == 0 or token != pending_token:
		return false
	pending_token = 0
	return true

func expire(token: int, now_ms: int) -> void:
	if token != 0 and token == pending_token and now_ms - sent_ms > TIMEOUT_MS:
		pending_token = 0
		# Transport expiry can precede the next gameplay check.
		_deny_next_check = true

func reset() -> void:
	_serial += 1
	pending_token = 0
	_deny_next_check = false
