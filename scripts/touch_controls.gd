class_name TouchControls
extends Control
## Portrait touch layout (multitouch):
##   - left / right flipper: the whole left / right half of the screen below the
##     HUD band is a tap zone (invisible except a faint hint at the bottom edge)
##   - LAUNCH: round-cornered button bottom-right (right thumb), over the plunger lane
##   - PAUSE / RESTART: small buttons in the top HUD band
## Keyboard controls keep working alongside.

const TOP_BAND := 0.075   # matches PinballWorld.FIT_TOP (HUD band above the table)

var left_flipper: VirtualButton
var right_flipper: VirtualButton
var launch: VirtualButton
var pause_btn: VirtualButton
var restart_btn: VirtualButton

var _held: Dictionary = {}
var _action_counts: Dictionary = {}
var _buttons: Array[VirtualButton] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var flip := Color(0.95, 0.55, 0.12, 0.9)
	# Zones first: buttons added later win the hit test (launch over the right zone).
	left_flipper = _add_button(&"flipper_left", "< LEFT FLIPPER", flip, 0.0, TOP_BAND, 0.5, 1.0, 20, true)
	right_flipper = _add_button(&"flipper_right", "RIGHT FLIPPER >", flip, 0.5, TOP_BAND, 1.0, 1.0, 20, true)
	launch = _add_button(&"plunger", "LAUNCH", Color(0.2, 0.8, 0.45, 0.95), 0.80, 0.875, 0.99, 0.99, 20)
	# keep the right zone's hint clear of the launch button
	right_flipper.hint_anchor = Vector2(0.0, 0.6)
	left_flipper.hint_anchor = Vector2(0.2, 1.0)
	pause_btn = _add_button(&"pause", "PAUSE", Color(0.7, 0.75, 0.85, 0.9), 0.015, 0.01, 0.16, 0.062, 15)
	restart_btn = _add_button(&"restart", "RESTART", Color(0.85, 0.35, 0.3, 0.9), 0.84, 0.01, 0.985, 0.062, 15)


func _add_button(action: StringName, text: String, accent: Color, l: float, t: float, r: float, b: float, font_size := 22, zone := false) -> VirtualButton:
	var btn := VirtualButton.new()
	btn.action = action
	btn.label_text = text
	btn.accent = accent
	btn.font_size = font_size
	btn.zone = zone
	btn.anchor_left = l
	btn.anchor_top = t
	btn.anchor_right = r
	btn.anchor_bottom = b
	var pad := 0 if zone else 4
	btn.offset_left = pad
	btn.offset_top = pad
	btn.offset_right = -pad
	btn.offset_bottom = -pad
	add_child(btn)
	_buttons.append(btn)
	return btn


func set_launch_charge(ratio: float) -> void:
	if launch:
		launch.set_charge(ratio)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _held.has(touch.index):
				return
			var btn := _hit(touch.position)
			if btn:
				_held[touch.index] = btn
				_press(btn)
				get_viewport().set_input_as_handled()
		else:
			if _held.has(touch.index):
				var btn: VirtualButton = _held[touch.index]
				_held.erase(touch.index)
				_release(btn)
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		# A finger sliding from one flipper zone to the other switches flippers.
		var drag := event as InputEventScreenDrag
		if _held.has(drag.index):
			var cur: VirtualButton = _held[drag.index]
			var now := _hit(drag.position)
			if cur.zone and now != null and now.zone and now != cur:
				_release(cur)
				_held[drag.index] = now
				_press(now)


func _hit(screen_pos: Vector2) -> VirtualButton:
	for i in range(_buttons.size() - 1, -1, -1):
		var btn := _buttons[i]
		if btn.get_global_rect().has_point(screen_pos):
			return btn
	return null


func _press(btn: VirtualButton) -> void:
	var n := int(_action_counts.get(btn.action, 0))
	_action_counts[btn.action] = n + 1
	if n == 0:
		Input.action_press(btn.action)
	btn.set_held(true)


func _release(btn: VirtualButton) -> void:
	var n := int(_action_counts.get(btn.action, 0)) - 1
	if n <= 0:
		_action_counts[btn.action] = 0
		Input.action_release(btn.action)
		btn.set_held(false)
	else:
		_action_counts[btn.action] = n
