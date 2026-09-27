class_name VirtualButton
extends Control
## Touch button. `zone = true` makes it a large, almost invisible tap zone: no
## panel, just a faint hint label along its bottom edge and a light tint while held.

@export var action: StringName = &""
@export var label_text := ""
@export var accent := Color(0.95, 0.52, 0.12, 0.9)
@export var font_size := 22
@export var zone := false
## Horizontal anchors (left, right) of the hint label inside a zone.
@export var hint_anchor := Vector2(0.0, 1.0)

const IDLE_BG := Color(0.08, 0.09, 0.12, 0.35)

var held := false
var _panel: Panel
var _label: Label
var _style: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style = StyleBoxFlat.new()
	_style.set_content_margin_all(8)
	if zone:
		_style.bg_color = Color(0, 0, 0, 0)
		_style.set_border_width_all(0)
	else:
		_style.bg_color = IDLE_BG
		_style.border_color = accent
		_style.set_border_width_all(2)
		_style.set_corner_radius_all(16)

	_panel = Panel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.add_theme_stylebox_override("panel", _style)
	add_child(_panel)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.text = label_text
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM if zone else VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if zone:
		_label.anchor_left = hint_anchor.x
		_label.anchor_right = hint_anchor.y
		_label.offset_bottom = -6
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.45 if zone else 0.95))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6 if zone else 0.85))
	_label.add_theme_constant_override("outline_size", 4 if zone else 5)
	add_child(_label)


func set_held(is_held: bool) -> void:
	held = is_held
	if _style == null:
		return
	if zone:
		_style.bg_color = Color(accent.r, accent.g, accent.b, 0.07) if is_held else Color(0, 0, 0, 0)
		return
	if is_held:
		_style.bg_color = Color(accent.r, accent.g, accent.b, 0.55)
		_style.border_color = Color.WHITE
	else:
		_style.bg_color = IDLE_BG
		_style.border_color = accent


func set_charge(ratio: float) -> void:
	if _style == null or zone:
		return
	if held:
		return
	_style.bg_color = Color(0.08 + 0.5 * ratio, 0.09, 0.12, IDLE_BG.a + 0.35 * ratio)
