extends "res://scripts/game/closable_panel.gd"

const ActorResourceScript = preload("res://scripts/game/actor_resource.gd")
const EmojiResourceScript = preload("res://scripts/game/emoji_resource.gd")
const MIN_BOARD_WIDTH := 300.0
const MARGIN := 35.0
const FONT_PATHS := [
	"res://assets/font/00_SIMSUN.ttf",
	"res://assets/font/01_Yahei.ttf",
	"res://assets/font/02_CALIBRI.ttf",
	"res://assets/font/03_MONOWIDE.ttf",
	"res://assets/font/04_YaHei_Consolas_Hybrid.ttf",
	"res://assets/font/05_NSIMSUN.ttf",
	"res://assets/font/06_YaHei_Monaco_Hybrid.ttf",
	"res://assets/font/07_fusion-pixel-12px-monospaced-zh_hans.ttf",
	"res://assets/font/08_fusion-pixel-12px-proportional-zh_hans.ttf",
	"res://assets/font/09_WenQuanYi_Bitmap_Song_15_px.ttf",
	"res://assets/font/0A_WenQuanYi_Bitmap_Song_15_px.ttf",
	"res://assets/font/0B_WenQuanYi_Bitmap_Song_15_px.ttf",
	"res://assets/font/0C_WenQuanYi_Bitmap_Song_18_px.ttf",
	"res://assets/font/0D_WenQuanYi_Bitmap_Song_18_px.ttf",
]
const FONT_NAME_IDS := {
	"SIMSUN": 0,
	"Yahei": 1,
	"CALIBRI": 2,
	"MONOWIDE": 3,
	"YaHei_Consolas_Hybrid": 4,
	"NSIMSUN": 5,
	"YaHei_Monaco_Hybrid": 6,
	"fusion-pixel-12px-monospaced-zh_hans": 7,
	"fusion-pixel-12px-proportional-zh_hans": 8,
	"WenQuanYi_Bitmap_Song_15_px": 9,
	"unifont_17_0_04": 11,
	"WenQuanYi_Bitmap_Song_18_px": 12,
}

var _state: Node
var _resources: RefCounted = ActorResourceScript.new()
var _emoji_resources: RefCounted = EmojiResourceScript.new()
var _emoji_frames: Array[Dictionary] = []
var _paragraph_labels: Array[RichTextLabel] = []
var _dialog_content_size := Vector2.ONE
var _hover_meta := ""
var _pressed_meta := ""


func _ready() -> void:
	super._ready()
	_state = get_node("/root/GameState")
	_resources.configure_default()
	_state.state_changed.connect(_refresh)
	$Dialog.meta_clicked.connect(_on_meta_clicked)
	$Dialog.meta_hover_started.connect(_on_meta_hover_started)
	$Dialog.meta_hover_ended.connect(_on_meta_hover_ended)
	$Dialog.gui_input.connect(_on_dialog_gui_input)
	$Dialog.clip_contents = false
	_refresh()


func _refresh() -> void:
	var dialog: Dictionary = _state.npc_dialog
	var face_frame: Dictionary = _resources.frame("proguse", 0x50000000 | _npc_id(dialog.get("npcUID", 0)))
	$Face.texture = face_frame.get("texture")
	$Face.visible = $Face.texture != null
	_render_dialog(dialog.get("xmlLayout", ""), _hover_meta)
	_apply_layout.call_deferred()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	for emoji in _emoji_frames:
		if emoji.frame_count <= 1 or emoji.fps <= 0:
			continue
		var frame_index := floori(float(now - emoji.start_ms) * emoji.fps / 1000.0) % int(emoji.frame_count)
		if frame_index == emoji.frame:
			continue
		emoji.frame = frame_index
		var columns := maxi(1, floori(float(emoji.atlas.atlas.get_width()) / emoji.width))
		var region: Rect2 = emoji.atlas.region
		region.position = Vector2((frame_index % columns) * emoji.width, floori(float(frame_index) / columns) * emoji.height)
		emoji.atlas.region = region


func _build_bbcode(xml: String, hover_meta: String = "", pressed_meta: String = "", line_width_override: float = -1.0) -> String:
	if xml.is_empty():
		return ""
	var parser := XMLParser.new()
	if parser.open_buffer(xml.to_utf8_buffer()) != OK:
		return _escape_bbcode(xml)
	var result := ""
	var tag_stack: Array[String] = []
	var font_path_stack: Array[String] = [""]
	var font_size_stack: Array[int] = [$Dialog.get_theme_font_size("normal_font_size")]
	var word_space_stack: Array[int] = [0]
	var no_wrap_depth := 0
	var line_width: float = line_width_override if line_width_override >= 0.0 else _dialog_line_width()
	var current_line_width := 0.0
	var atomic_result_start := -1
	var atomic_width := 0.0
	var atomic_has_text := false
	var atomic_word_space := 0
	while parser.read() == OK:
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				var name := parser.get_node_name().to_lower()
				var effective_font_path: String = font_path_stack.back()
				var effective_font_size: int = font_size_stack.back()
				var effective_word_space: int = word_space_stack.back()
				if name == "par":
					if not result.is_empty() and not result.ends_with("\n"):
						result += "\n"
					current_line_width = 0.0
					var par_tags: Array[String] = []
					var align := _xml_attribute(parser, "align", "justify").to_lower()
					if align == "justify":
						result += "[fill]"
						par_tags.append("fill")
					elif align == "center":
						result += "[center]"
						par_tags.append("center")
					elif align == "right":
						result += "[right]"
						par_tags.append("right")
					var par_font := _xml_attribute(parser, "font", "")
					if not par_font.is_empty():
						effective_font_path = _paragraph_font_path(par_font)
						result += "[font=%s]" % effective_font_path
						par_tags.append("font")
					effective_font_size = max(1, int(_xml_attribute(parser, "size", "15")))
					if effective_font_size != 15:
						result += "[font_size=%d]" % effective_font_size
						par_tags.append("font_size")
					effective_word_space = int(_xml_attribute(parser, "wordSpace", "0"))
					if effective_word_space != 0:
						result += "[font glyph_spacing=%d]" % effective_word_space
						par_tags.append("font")
					var par_color := _xml_attribute(parser, "color", "")
					if not par_color.is_empty():
						result += "[color=%s]" % _bbcode_color(par_color)
						par_tags.append("color")
					var par_bgcolor := _xml_attribute(parser, "bgcolor", "")
					if not par_bgcolor.is_empty():
						result += "[bgcolor=%s]" % _bbcode_color(par_bgcolor)
						par_tags.append("bgcolor")
					tag_stack.append("par:%s" % ",".join(par_tags))
				elif name == "event":
					var wrap_enabled := _parse_bool(_xml_attribute(parser, "wrap", "true"))
					if not wrap_enabled:
						atomic_result_start = result.length()
						atomic_width = 0.0
						atomic_has_text = false
						atomic_word_space = effective_word_space
					var event := {
						"id": _xml_attribute(parser, "id", ""),
						"path": _xml_attribute(parser, "path", ""),
						"args": _xml_optional_attribute(parser, "args"),
						"close": _parse_bool(_xml_attribute(parser, "close", "0")),
					}
					var meta := JSON.stringify(event)
					var event_color := "#ff00ff" if meta == pressed_meta else ("#00ff00" if meta == hover_meta else "#ffff00")
					var event_tags: Array[String] = []
					var event_font := _inline_font_path(_xml_attribute(parser, "font", ""))
					if not event_font.is_empty():
						effective_font_path = event_font
						result += "[font=%s]" % event_font
						event_tags.append("font")
					var event_size: Variant = _xml_optional_attribute(parser, "size")
					if event_size != null:
						effective_font_size = max(1, int(event_size))
						result += "[font_size=%d]" % effective_font_size
						event_tags.append("font_size")
					result += "[color=%s][url=%s]" % [event_color, meta]
					var event_tag := "event" if wrap_enabled else "event-nowrap"
					tag_stack.append("%s:%s" % [event_tag, ",".join(event_tags)] if not event_tags.is_empty() else event_tag)
					if not wrap_enabled:
						no_wrap_depth += 1
				elif name == "t":
					var text_tags: Array[String] = []
					var text_font := _inline_font_path(_xml_attribute(parser, "font", ""))
					if not text_font.is_empty():
						effective_font_path = text_font
						result += "[font=%s]" % text_font
						text_tags.append("font")
					var text_size: Variant = _xml_optional_attribute(parser, "size")
					if text_size != null:
						effective_font_size = max(1, int(text_size))
						result += "[font_size=%d]" % effective_font_size
						text_tags.append("font_size")
					var text_color := _xml_attribute(parser, "color", "")
					if not text_color.is_empty():
						result += "[color=%s]" % _bbcode_color(text_color)
						text_tags.append("color")
					var text_bgcolor := _xml_attribute(parser, "bgcolor", "")
					if not text_bgcolor.is_empty():
						result += "[bgcolor=%s]" % _bbcode_color(text_bgcolor)
						text_tags.append("bgcolor")
					tag_stack.append("t:%s" % ",".join(text_tags))
				elif name == "emoji":
					var emoji_id := int(_xml_attribute(parser, "id", "0"))
					result += "[[MIR2X_EMOJI:%d]]" % emoji_id
					var emoji_definition := _emoji_definition(emoji_id)
					if not emoji_definition.is_empty():
						current_line_width = _advance_object_width(current_line_width, emoji_definition.width, line_width, effective_word_space)
					tag_stack.append("emoji")
				else:
					tag_stack.append(name)
				font_path_stack.append(effective_font_path)
				font_size_stack.append(effective_font_size)
				word_space_stack.append(effective_word_space)
				if parser.is_empty():
					var empty_tag: String = tag_stack.pop_back()
					if empty_tag.begins_with("event-nowrap"):
						var empty_placement: Array = _place_atomic_width(result, atomic_result_start, atomic_width, current_line_width, line_width, atomic_word_space)
						current_line_width = empty_placement[0]
						result = empty_placement[1]
						atomic_result_start = -1
						atomic_width = 0.0
						atomic_has_text = false
					result = _close_tag(result, empty_tag)
					if empty_tag.begins_with("event-nowrap"):
						no_wrap_depth -= 1
					font_path_stack.pop_back()
					font_size_stack.pop_back()
					word_space_stack.pop_back()
			XMLParser.NODE_ELEMENT_END:
				if not tag_stack.is_empty():
					var closed_tag: String = tag_stack.pop_back()
					if closed_tag.begins_with("event-nowrap"):
						var placement: Array = _place_atomic_width(result, atomic_result_start, atomic_width, current_line_width, line_width, atomic_word_space)
						current_line_width = placement[0]
						result = placement[1]
						atomic_result_start = -1
						atomic_width = 0.0
						atomic_has_text = false
					result = _close_tag(result, closed_tag)
					if closed_tag.begins_with("event-nowrap"):
						no_wrap_depth -= 1
					font_path_stack.pop_back()
					font_size_stack.pop_back()
					word_space_stack.pop_back()
			XMLParser.NODE_TEXT:
				var text := parser.get_node_data()
				result += _escape_bbcode(text)
				if no_wrap_depth > 0:
					var text_width := _text_width(text, font_path_stack.back(), font_size_stack.back(), word_space_stack.back())
					if atomic_has_text and not text.is_empty():
						text_width += word_space_stack.back()
					atomic_width += text_width
					atomic_has_text = atomic_has_text or not text.is_empty()
				else:
					current_line_width = _advance_line_width(current_line_width, text, line_width, font_path_stack.back(), font_size_stack.back(), word_space_stack.back())
	return result


func _close_tag(result: String, name: String) -> String:
	if name.begins_with("par:") or name.begins_with("t:"):
		var is_paragraph := name.begins_with("par:")
		var tags := name.substr(name.find(":") + 1).split(",", false)
		tags.reverse()
		for tag in tags:
			result += "[/%s]" % tag
		if is_paragraph and not result.ends_with("\n"):
			result += "\n"
		return result
	match name:
		"par":
			if not result.ends_with("\n"):
				result += "\n"
		"event", "event-nowrap":
			result += "[/url][/color]"
	if name.begins_with("event:") or name.begins_with("event-nowrap:"):
		result += "[/url][/color]"
		var tags := name.substr(name.find(":") + 1).split(",", false)
		tags.reverse()
		for tag in tags:
			result += "[/%s]" % tag
	return result


func _apply_layout() -> void:
	var face_size := Vector2.ZERO
	if $Face.visible:
		face_size = $Face.texture.get_size()
	var board_width := maxf(get_viewport_rect().size.x / 3.0, MIN_BOARD_WIDTH)
	var line_width := board_width - MARGIN * (3.0 if $Face.visible else 2.0) - face_size.x
	line_width = maxf(1.0, line_width)
	var content_width := maxf(1.0, ceilf(_dialog_content_size.x))
	var content_height := maxf(1.0, ceilf(_dialog_content_size.y))
	var panel_width := MARGIN * (3.0 if $Face.visible else 2.0) + face_size.x + content_width
	var panel_height := MARGIN * 2.0 + maxf(face_size.y, content_height)
	custom_minimum_size = Vector2.ZERO
	size = Vector2(panel_width, panel_height)
	custom_minimum_size = size
	$Upper.size = Vector2(panel_width, panel_height - 44.0)
	$Lower.position = Vector2(0.0, panel_height - 44.0)
	$Lower.size = Vector2(panel_width, 44.0)
	$Face.position = Vector2(MARGIN, MARGIN)
	$Face.size = face_size
	$Dialog.position = Vector2(MARGIN * 2.0 + face_size.x if $Face.visible else MARGIN, (panel_height - content_height) * 0.5)
	$Dialog.size = Vector2(content_width, content_height)
	$CloseButton.position = Vector2(panel_width - 40.0, panel_height - 43.0)


func _npc_id(uid: int) -> int:
	return _state.uid_record_id(uid)


func _xml_attribute(parser: XMLParser, name: String, fallback: String) -> String:
	for index in parser.get_attribute_count():
		if parser.get_attribute_name(index) == name:
			return parser.get_attribute_value(index)
	return fallback


func _xml_optional_attribute(parser: XMLParser, name: String) -> Variant:
	for index in parser.get_attribute_count():
		if parser.get_attribute_name(index) == name:
			return parser.get_attribute_value(index)
	return null


func _paragraph_font_path(value: String) -> String:
	var font_id := _font_id(value, true)
	return FONT_PATHS[font_id if font_id >= 0 else 0]


func _inline_font_path(value: String) -> String:
	var font_id := _font_id(value, false)
	return FONT_PATHS[font_id] if font_id >= 0 else ""


func _font_id(value: String, allow_name: bool) -> int:
	if value.is_valid_int():
		var font_id := int(value)
		return font_id if font_id >= 0 and font_id < FONT_PATHS.size() else -1
	if allow_name:
		return int(FONT_NAME_IDS.get(value, 0))
	return -1


func _bbcode_color(value: String) -> String:
	var color := value.to_lower()
	if color.begins_with("rgb("):
		var regex := RegEx.new()
		regex.compile("0x([0-9a-fA-F]{2})")
		var matches := regex.search_all(color)
		if matches.size() == 3:
			return "#%s%s%s" % [matches[0].get_string(1), matches[1].get_string(1), matches[2].get_string(1)]
	return color


func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]").replace("]", "[rb]")


func _render_dialog(xml: String, hover_meta: String = "", pressed_meta: String = "") -> void:
	$Dialog.clear()
	for label in _paragraph_labels:
		if is_instance_valid(label):
			$Dialog.remove_child(label)
			label.queue_free()
	_paragraph_labels.clear()
	_emoji_frames.clear()
	_dialog_content_size = Vector2.ONE
	var paragraph_y := 0.0
	var content_width := 0.0
	for paragraph_xml in _paragraph_xmls(xml):
		var width_attribute: Variant = _element_attribute(paragraph_xml, "lineWidth")
		var paragraph_width := maxi(0, int(width_attribute)) if width_attribute != null else ceili(_dialog_line_width())
		var line_space_attribute: Variant = _element_attribute(paragraph_xml, "lineSpace")
		var line_space := maxi(0, int(line_space_attribute)) if line_space_attribute != null else 0
		var label := _create_paragraph_label(paragraph_width, line_space)
		label.position = Vector2(0.0, paragraph_y)
		$Dialog.add_child(label)
		_paragraph_labels.append(label)
		var bbcode := _build_bbcode(paragraph_xml, hover_meta, pressed_meta, paragraph_width).trim_suffix("\n")
		_append_rich_text(label, bbcode)
		var paragraph_content_width := maxf(1.0, ceilf(label.get_content_width()))
		if paragraph_width == 0:
			label.size.x = paragraph_content_width
		var align_attribute: Variant = _element_attribute(paragraph_xml, "align")
		var paragraph_align := str(align_attribute).to_lower() if align_attribute != null else "justify"
		if paragraph_align in ["right", "center"]:
			paragraph_content_width = maxf(paragraph_content_width, paragraph_width)
		var paragraph_height := maxf(_paragraph_default_font_height(paragraph_xml), ceilf(label.get_content_height()))
		label.size.y = paragraph_height
		paragraph_y += paragraph_height
		content_width = maxf(content_width, paragraph_content_width)
	_dialog_content_size = Vector2(maxf(1.0, content_width), maxf(1.0, paragraph_y))


func _paragraph_xmls(xml: String) -> Array[String]:
	var regex := RegEx.new()
	if regex.compile("(?is)<par\\b[^>]*(?:/>|>.*?</par\\s*>)") != OK:
		return []
	var result: Array[String] = []
	for match_result in regex.search_all(xml):
		result.append(match_result.get_string())
	return result


func _element_attribute(xml: String, attribute: String) -> Variant:
	var parser := XMLParser.new()
	if parser.open_buffer(xml.to_utf8_buffer()) != OK:
		return null
	while parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT and parser.get_node_name().to_lower() == "par":
			return _xml_optional_attribute(parser, attribute)
	return null


func _create_paragraph_label(paragraph_width: int, line_space: int) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = false
	label.scroll_active = false
	label.selection_enabled = false
	label.clip_contents = false
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY if paragraph_width > 0 else TextServer.AUTOWRAP_OFF
	label.size = Vector2(maxf(1.0, paragraph_width), 1.0)
	label.add_theme_font_override("normal_font", $Dialog.get_theme_font("normal_font"))
	label.add_theme_font_size_override("normal_font_size", $Dialog.get_theme_font_size("normal_font_size"))
	label.add_theme_color_override("default_color", Color.WHITE)
	label.add_theme_constant_override("text_highlight_h_padding", 0)
	label.add_theme_constant_override("text_highlight_v_padding", 0)
	label.add_theme_constant_override("line_separation", line_space)
	label.meta_clicked.connect(_on_meta_clicked)
	label.meta_hover_started.connect(_on_meta_hover_started)
	label.meta_hover_ended.connect(_on_meta_hover_ended)
	label.gui_input.connect(_on_dialog_gui_input)
	return label


func _paragraph_default_font_height(paragraph_xml: String) -> float:
	var font_attribute: Variant = _element_attribute(paragraph_xml, "font")
	var font: Font = load(_paragraph_font_path(str(font_attribute))) if font_attribute != null else $Dialog.get_theme_font("normal_font")
	var size_attribute: Variant = _element_attribute(paragraph_xml, "size")
	var font_size: int = maxi(1, int(size_attribute)) if size_attribute != null else $Dialog.get_theme_font_size("normal_font_size")
	return font.get_height(font_size)


func _append_rich_text(label: RichTextLabel, bbcode: String) -> void:
	var cursor := 0
	while cursor < bbcode.length():
		var marker_start := bbcode.find("[[MIR2X_EMOJI:", cursor)
		if marker_start < 0:
			label.append_text(bbcode.substr(cursor))
			break
		label.append_text(bbcode.substr(cursor, marker_start - cursor))
		var marker_end := bbcode.find("]]", marker_start)
		if marker_end < 0:
			label.append_text(bbcode.substr(marker_start))
			break
		var emoji_id := int(bbcode.substr(marker_start + 14, marker_end - marker_start - 14))
		var emoji: Dictionary = _emoji_resources.frame(emoji_id)
		if not emoji.is_empty():
			label.add_image(emoji.texture, emoji.width, emoji.height)
			emoji["atlas"] = emoji.texture
			emoji["start_ms"] = Time.get_ticks_msec()
			emoji["frame"] = 0
			_emoji_frames.append(emoji)
		cursor = marker_end + 2


func _emoji_definition(emoji_id: int) -> Dictionary:
	return _emoji_resources.definition(emoji_id)


func _dialog_line_width() -> float:
	var face_width: float = float($Face.texture.get_width()) if $Face.visible and $Face.texture != null else 0.0
	var board_width := maxf(get_viewport_rect().size.x / 3.0, MIN_BOARD_WIDTH)
	return maxf(1.0, board_width - MARGIN * (3.0 if $Face.visible else 2.0) - face_width)


func _text_width(text: String, font_path: String = "", font_size: int = 0, word_space: int = 0) -> float:
	var font: Font = load(font_path) if not font_path.is_empty() else $Dialog.get_theme_font("normal_font")
	var size: int = font_size if font_size > 0 else $Dialog.get_theme_font_size("normal_font_size")
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	return width + max(0, text.length() - 1) * word_space


func _advance_line_width(current: float, text: String, line_width: float, font_path: String = "", font_size: int = 0, word_space: int = 0) -> float:
	for index in text.length():
		var character: String = text[index]
		if character == "\n":
			current = 0.0
			continue
		var character_width: float = _text_width(character, font_path, font_size)
		if current > 0.0:
			character_width += word_space
		current = character_width if line_width > 0.0 and current > 0.0 and current + character_width > line_width else current + character_width
	return current


func _advance_object_width(current: float, width: float, line_width: float, word_space: int = 0) -> float:
	var advance := width + (word_space if current > 0.0 else 0)
	return width if line_width > 0.0 and current > 0.0 and current + advance > line_width else current + advance


func _place_atomic_width(bbcode: String, start: int, atomic_width: float, current: float, line_width: float, word_space: int) -> Array:
	var advance := atomic_width + (word_space if current > 0.0 else 0)
	if line_width > 0.0 and current > 0.0 and current + advance > line_width and atomic_width <= line_width:
		bbcode = bbcode.insert(start, "\n")
		current = 0.0
	return [_advance_object_width(current, atomic_width, line_width, word_space), bbcode]


func _parse_bool(value: String) -> bool:
	return value.to_lower() in ["1", "true", "yes", "on"]


func _on_meta_clicked(meta: Variant) -> void:
	var event = JSON.parse_string(str(meta))
	if not event is Dictionary or event.get("id", "").is_empty():
		return
	var path: String = event.get("path", "")
	if path.is_empty():
		path = _state.npc_dialog.get("eventPath", "")
	NetworkClient.send_npc_event(
		_state.npc_dialog.get("npcUID", 0),
		path,
		event.get("id", ""),
		event.get("args", ""),
	)
	if event.get("close", false):
		hide()


func _on_meta_hover_started(meta: Variant) -> void:
	_hover_meta = str(meta)
	_render_dialog(_state.npc_dialog.get("xmlLayout", ""), _hover_meta)


func _on_meta_hover_ended(meta: Variant) -> void:
	if _hover_meta != str(meta):
		return
	_hover_meta = ""
	_render_dialog(_state.npc_dialog.get("xmlLayout", ""))


func _on_dialog_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
		return
	_pressed_meta = _hover_meta if event.pressed else ""
	_render_dialog(_state.npc_dialog.get("xmlLayout", ""), _hover_meta, _pressed_meta)
