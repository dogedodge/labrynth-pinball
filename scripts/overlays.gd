class_name GameOverlays
extends Control

var _dim: ColorRect
var _title: Label
var _detail: Label
var _hint: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

	_dim = ColorRect.new()
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.color = Color(0.02, 0.02, 0.04, 0.55)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.anchor_left = 0.08
	box.anchor_right = 0.92
	box.anchor_top = 0.34
	box.anchor_bottom = 0.62
	add_child(box)

	_title = _label(48, Color(1, 0.92, 0.7))
	box.add_child(_title)
	_detail = _label(28, Color(0.95, 0.95, 0.95))
	box.add_child(_detail)
	_hint = _label(18, Color(0.8, 0.82, 0.86))
	box.add_child(_hint)


func _label(size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	return label


func show_paused() -> void:
	_title.text = "PAUSED"
	_detail.text = ""
	_hint.text = "Tap PAUSE or press Esc / P to resume"
	visible = true


func show_game_over(score: int) -> void:
	_title.text = "GAME OVER"
	_detail.text = "Score  %d" % score
	_hint.text = "Tap RESTART or press R / Enter"
	visible = true


func hide_all() -> void:
	visible = false
