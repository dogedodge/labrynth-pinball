class_name PinballHUD
extends Control

var _score: Label
var _balls: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_score = _make_label(42)
	_score.anchor_left = 0.22
	_score.anchor_right = 0.78
	_score.anchor_top = 0.03
	_score.anchor_bottom = 0.12
	_score.offset_left = 0
	_score.offset_right = 0
	_score.offset_top = 0
	_score.offset_bottom = 0
	_balls = _make_label(22)
	_balls.anchor_left = 0.22
	_balls.anchor_right = 0.78
	_balls.anchor_top = 0.11
	_balls.anchor_bottom = 0.18
	_balls.offset_left = 0
	_balls.offset_right = 0
	_balls.offset_top = 0
	_balls.offset_bottom = 0
	set_status(0, PinballData.BALLS_PER_GAME, false)


func _make_label(size: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(1, 0.95, 0.82))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 8)
	add_child(label)
	return label


func set_status(score: int, balls_left: int, game_over: bool) -> void:
	_score.text = str(score)
	if game_over:
		_balls.text = "GAME OVER"
	else:
		_balls.text = "BALLS  %d" % balls_left
