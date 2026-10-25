extends RefCounted

# Mir3 67E29C/67C1B0 stores F1..F12 as '1'..'<' and Shift-F1..F12
# as 'A'..'L'. Existing mir2x alphanumeric bindings remain aliases.
static func event_key(event: InputEventKey) -> int:
	var code := int(event.keycode)
	if code >= KEY_F1 and code <= KEY_F12:
		return (65 if event.shift_pressed else 49) + code - KEY_F1
	var key := code if (code >= KEY_0 and code <= KEY_9) or (code >= KEY_A and code <= KEY_Z) else int(event.unicode)
	if key >= 65 and key <= 90:
		key += 32
	return key if (key >= 48 and key <= 57) or (key >= 97 and key <= 122) else 0


static func label(key: int) -> String:
	if key >= 49 and key <= 60:
		return "F%d" % (key - 48)
	if key >= 65 and key <= 76:
		return "S-F%d" % (key - 64)
	return char(key).to_upper() if key != 0 else ""
