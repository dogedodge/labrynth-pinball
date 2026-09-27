class_name PinballWorld
extends Node3D

signal ball_drained
signal plunger_charge_changed(ratio: float)

const TABLE_PATH := "res://assets/models/table.glb"

var playfield: Node3D
var camera: Camera3D
var left_flipper: PinballFlipper
var right_flipper: PinballFlipper
var plunger: PinballPlunger
var drain: PinballDrain
var ball: PinballBall
var spawn_local := Vector3(0.2695, 0.0135, 0.4845)

var _layout: Dictionary = {}
var _shot_gate: StaticBody3D


func _ready() -> void:
	_load_layout()
	_build()


func _load_layout() -> void:
	var file := FileAccess.open("res://assets/models/layout.json", FileAccess.READ)
	if file == null:
		push_error("Could not read layout.json")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_layout = parsed


func marker_position(marker_name: String) -> Vector3:
	if _layout.has(marker_name):
		var raw: Variant = _layout[marker_name].get("godot_position", [])
		if raw is Array and raw.size() >= 3:
			return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return Vector3.ZERO


func _build() -> void:
	playfield = Node3D.new()
	playfield.name = "Playfield"
	playfield.rotation_degrees.x = PinballData.TABLE_TILT_DEG
	add_child(playfield)

	var table: Node3D = ModelUtil.instantiate_glb(TABLE_PATH)
	table.name = "Table"
	playfield.add_child(table)

	var wall_mat := ModelUtil.physics_material(0.06, 0.38)
	var floor_mat := ModelUtil.physics_material(0.22, 0.12)
	for mesh_instance in ModelUtil.find_meshes(table):
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# All static table colliders (floor, outer walls, lane splitter, inlanes, maze,
	# pocket fills, lane gate) are primitive shapes generated from the
	# "colliders" section of layout.json, which tools/blender/generate_models.py
	# writes from the same numbers it uses to build the visible meshes.
	var col: Dictionary = _layout.get("colliders", {})
	_add_floor(playfield, floor_mat, col.get("floor", {}))
	for spec in col.get("segments", []):
		_add_wall_segment_spec(playfield, wall_mat, spec)
	var pocket_i := 0
	for pts in col.get("pockets", []):
		pocket_i += 1
		_add_pocket_fill(playfield, wall_mat, "Pocket%d" % pocket_i, _vec2_array(pts))
	var post_i := 0
	for post in col.get("posts", []):
		post_i += 1
		_add_post(playfield, wall_mat, "Post%d" % post_i, post)
	_add_glass(playfield, float(col.get("glass_height", 0.12)))
	_add_lane_gate(playfield, col.get("lane_gate", {}))

	spawn_local = marker_position("Marker_BallSpawn")

	left_flipper = PinballFlipper.new()
	left_flipper.name = "FlipperLeft"
	left_flipper.input_action = &"flipper_left"
	left_flipper.rest_angle_deg = PinballData.FLIPPER_LEFT_REST_DEG
	left_flipper.active_angle_deg = PinballData.FLIPPER_LEFT_ACTIVE_DEG
	left_flipper.position = marker_position("Marker_FlipperLeft")
	left_flipper.rotation.y = deg_to_rad(left_flipper.rest_angle_deg)
	playfield.add_child(left_flipper)

	right_flipper = PinballFlipper.new()
	right_flipper.name = "FlipperRight"
	right_flipper.input_action = &"flipper_right"
	right_flipper.rest_angle_deg = PinballData.FLIPPER_RIGHT_REST_DEG
	right_flipper.active_angle_deg = PinballData.FLIPPER_RIGHT_ACTIVE_DEG
	right_flipper.position = marker_position("Marker_FlipperRight")
	right_flipper.rotation.y = deg_to_rad(right_flipper.rest_angle_deg)
	playfield.add_child(right_flipper)

	plunger = PinballPlunger.new()
	plunger.name = "Plunger"
	var plunger_pos := marker_position("Marker_Plunger")
	plunger.position = plunger_pos
	playfield.add_child(plunger)
	plunger.setup(playfield, plunger_pos.z)
	plunger.charge_changed.connect(func(r: float) -> void: plunger_charge_changed.emit(r))

	for marker in _markers_with_prefix("Marker_Bumper"):
		var bumper := PinballBumper.new()
		bumper.name = marker.trim_prefix("Marker_")
		bumper.position = marker_position(marker)
		playfield.add_child(bumper)

	var sling_l := PinballSlingshot.new()
	sling_l.name = "SlingshotLeft"
	sling_l.is_left = true
	sling_l.position = marker_position("Marker_SlingshotLeft")
	sling_l.kick_local = _sling_kick("Marker_SlingshotLeft")
	sling_l.face_local = _sling_face("Marker_SlingshotLeft")
	playfield.add_child(sling_l)

	var sling_r := PinballSlingshot.new()
	sling_r.name = "SlingshotRight"
	sling_r.is_left = false
	sling_r.position = marker_position("Marker_SlingshotRight")
	sling_r.kick_local = _sling_kick("Marker_SlingshotRight")
	sling_r.face_local = _sling_face("Marker_SlingshotRight")
	playfield.add_child(sling_r)

	for marker in _markers_with_prefix("Marker_Target"):
		var target := PinballTarget.new()
		target.name = marker.trim_prefix("Marker_")
		target.position = marker_position(marker)
		playfield.add_child(target)

	# Centre drain (below the flippers) plus one drain at the bottom of each outlane.
	var drains: Dictionary = _layout.get("drains", {"Marker_Drain": {}})
	for marker in drains.keys():
		var spec: Dictionary = drains[marker]
		var d := PinballDrain.new()
		d.name = String(marker).trim_prefix("Marker_")
		var sz: Array = spec.get("size", [0.22, 0.04, 0.07])
		d.size = Vector3(float(sz[0]), float(sz[1]), float(sz[2]))
		d.show_visual = bool(spec.get("visual", true))
		d.position = marker_position(String(marker))
		playfield.add_child(d)
		d.ball_drained.connect(func() -> void: ball_drained.emit())
		if marker == "Marker_Drain":
			drain = d

	_add_lights()
	_add_camera()
	_add_environment()


func _markers_with_prefix(prefix: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for key in _layout.keys():
		if String(key).begins_with(prefix):
			out.append(String(key))
	out.sort()
	return out


func _sling_kick(marker: String) -> Vector3:
	var slings: Dictionary = _layout.get("slingshots", {})
	var raw: Variant = slings.get(marker, {}).get("kick_dir", [])
	if raw is Array and raw.size() >= 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return Vector3.ZERO


func _sling_face(marker: String) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var raw: Variant = _layout.get("slingshots", {}).get(marker, {}).get("face", [])
	if raw is Array and raw.size() == 2:
		for q in raw:
			out.append(Vector2(float(q[0]), float(q[1])))
	return out


func get_layout() -> Dictionary:
	return _layout


func table_info(key: String, default_value: float) -> float:
	var info: Dictionary = _layout.get("table", {})
	return float(info.get(key, default_value))


func _vec2_array(raw: Variant) -> Array:
	var out: Array = []
	if raw is Array:
		for p in raw:
			out.append(Vector2(float(p[0]), float(p[1])))
	return out


func _new_static(parent: Node3D, body_name: String, phys_mat: PhysicsMaterial) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.physics_material_override = phys_mat
	body.collision_layer = PinballData.LAYER_WORLD
	body.collision_mask = PinballData.LAYER_BALL
	parent.add_child(body)
	return body


func _add_floor(parent: Node3D, phys_mat: PhysicsMaterial, spec: Dictionary) -> void:
	var body := _new_static(parent, "FloorBody", phys_mat)
	var raw: Array = spec.get("size", [1.02, 0.02, 1.02])
	var box := BoxShape3D.new()
	box.size = Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	var cs := CollisionShape3D.new()
	cs.shape = box
	cs.position = Vector3(0.0, float(spec.get("y", -0.01)), 0.0)
	body.add_child(cs)


var _segment_count := {}


func _add_wall_segment_spec(parent: Node3D, phys_mat: PhysicsMaterial, spec: Dictionary) -> void:
	var group := String(spec.get("group", "wall"))
	var n := int(_segment_count.get(group, 0)) + 1
	_segment_count[group] = n
	var p0: Array = spec["p0"]
	var p1: Array = spec["p1"]
	var t := float(spec.get("t", 0.012))
	_add_wall_segment(
		parent,
		phys_mat,
		"Wall%s%d" % [group.capitalize(), n],
		Vector3(float(p0[0]), 0.0, float(p0[1])),
		Vector3(float(p1[0]), 0.0, float(p1[1])),
		t,
		float(spec.get("h", 0.05)),
		t if bool(spec.get("extend", true)) else 0.0
	)


func _add_wall_segment(
	parent: Node3D,
	phys_mat: PhysicsMaterial,
	seg_name: String,
	p0: Vector3,
	p1: Vector3,
	thickness := 0.014,
	height := 0.05,
	extra_length := -1.0
) -> void:
	var delta := Vector3(p1.x - p0.x, 0.0, p1.z - p0.z)
	var length := delta.length() + (thickness if extra_length < 0.0 else extra_length)
	var mid := (p0 + p1) * 0.5
	var body := _new_static(parent, seg_name, phys_mat)
	var box := BoxShape3D.new()
	box.size = Vector3(length, height, thickness)
	var cs := CollisionShape3D.new()
	cs.shape = box
	cs.position = Vector3(mid.x, height * 0.5, mid.z)
	cs.rotation.y = atan2(-delta.z, delta.x)
	body.add_child(cs)


func _add_pocket_fill(
	parent: Node3D,
	phys_mat: PhysicsMaterial,
	fill_name: String,
	pts_xz: Array,
	height := 0.05
) -> void:
	# Solid fills behind the inlane rails. A 12 m/s ball moves ~67 mm per physics
	# tick, so a thin wall alone can still be tunneled; the volume cannot.
	var points := PackedVector3Array()
	for raw in pts_xz:
		var p: Vector2 = raw
		points.append(Vector3(p.x, 0.0, p.y))
		points.append(Vector3(p.x, height, p.y))
	var body := _new_static(parent, fill_name, phys_mat)
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)


func _add_post(parent: Node3D, phys_mat: PhysicsMaterial, post_name: String, spec: Dictionary) -> void:
	var body := _new_static(parent, post_name, phys_mat)
	var c: Array = spec["center"]
	var cyl := CylinderShape3D.new()
	cyl.radius = float(spec.get("r", 0.008))
	cyl.height = float(spec.get("h", 0.05))
	var cs := CollisionShape3D.new()
	cs.shape = cyl
	cs.position = Vector3(float(c[0]), cyl.height * 0.5, float(c[1]))
	body.add_child(cs)


func _add_glass(parent: Node3D, height: float) -> void:
	var body := _new_static(parent, "Glass", null)
	var box := BoxShape3D.new()
	box.size = Vector3(table_info("width", 1.0), 0.004, table_info("length", 1.0))
	var cs := CollisionShape3D.new()
	cs.shape = box
	cs.position = Vector3(0.0, height, 0.0)
	body.add_child(cs)


func _add_lane_gate(parent: Node3D, spec: Dictionary) -> void:
	# One-way gate at the top of the plunger lane: open while the ball is launching
	# up the lane, closed once it is in the playfield so it cannot fall back in.
	_shot_gate = _new_static(parent, "LaneGate", null)
	var center: Array = spec.get("center", [0.245, -0.33])
	var size: Array = spec.get("size", [0.012, 0.045, 0.10])
	var box := BoxShape3D.new()
	box.size = Vector3(float(size[0]), float(size[1]), float(size[2]))
	var cs := CollisionShape3D.new()
	cs.shape = box
	cs.position = Vector3(float(center[0]), float(size[1]) * 0.5, float(center[1]))
	_shot_gate.add_child(cs)
	_set_gate_open(true)


func _set_gate_open(open: bool) -> void:
	if _shot_gate == null:
		return
	# Clear both layer and mask: Godot collides when either side's mask matches,
	# so a gate with layer 0 but mask=ball would still block the launch.
	_shot_gate.collision_layer = 0 if open else PinballData.LAYER_WORLD
	_shot_gate.collision_mask = 0 if open else PinballData.LAYER_BALL


func _physics_process(_delta: float) -> void:
	if ball == null or not is_instance_valid(ball) or playfield == null:
		return
	var local := playfield.to_local(ball.global_position)
	if local.x < table_info("lane_wall_x", 0.245) - 0.06 and local.z < -0.08:
		_set_gate_open(false)


## Portrait camera: looks down the table from the player end at a fixed angle and
## is automatically framed so the whole table (outer walls included) fills the
## screen area left free by the HUD band at the top. Re-fitted whenever the
## viewport size changes, so tall phones (19.5:9, 20:9) and 4:3 tablets all show
## the complete table as large as possible.
const CAMERA_FOV := 30.0          # vertical FOV (deg)
const CAMERA_PITCH_DEG := 66.0    # view direction below the playfield plane (90 = top-down)
## Screen margins (fractions of the viewport) kept free of the table.
const FIT_TOP := 0.075            # score / pause / restart band
const FIT_BOTTOM := 0.035          # room for the flipper hints on 4:3 tablets
const FIT_SIDE := 0.012
const FIT_VALIGN := 0.25          # 0 = table at the top of the free area, 0.5 = centred


func _add_camera() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = CAMERA_FOV
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.02
	camera.far = 25.0
	camera.current = true
	playfield.add_child(camera)
	fit_camera()
	get_viewport().size_changed.connect(fit_camera)


func _table_corners() -> Array[Vector3]:
	var hx := table_info("width", 0.6) * 0.5
	var hz := table_info("length", 1.1) * 0.5
	var out: Array[Vector3] = []
	for x in [-hx, hx]:
		for z in [-hz, hz]:
			for y in [0.0, 0.05]:
				out.append(Vector3(x, y, z))
	return out


func fit_camera() -> void:
	if camera == null or not camera.is_inside_tree():
		return
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	# Everything below is in normalised screen coordinates (0..1, y down), so it
	# does not depend on the stretch mode's logical vs. physical pixel size.
	var aspect := vp.x / vp.y
	var tan_h := tan(deg_to_rad(CAMERA_FOV) * 0.5)
	var avail := Rect2(FIT_SIDE, FIT_TOP, 1.0 - 2.0 * FIT_SIDE, 1.0 - FIT_TOP - FIT_BOTTOM)
	var pitch := deg_to_rad(CAMERA_PITCH_DEG)
	var dir := Vector3(0.0, -sin(pitch), -cos(pitch))   # toward the far end, down
	var basis := Basis.looking_at(dir, Vector3.UP)
	var target := Vector3(table_info("playfield_center_x", 0.0), 0.0, 0.0)
	var dist := 2.0
	var corners := _table_corners()
	for i in range(60):
		var xf := Transform3D(basis, target - dir * dist)
		var inv := xf.affine_inverse()
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for c in corners:
			var p := inv * c
			var depth := maxf(-p.z, 0.001)
			var sp := Vector2(0.5 + 0.5 * p.x / (depth * tan_h * aspect), 0.5 - 0.5 * p.y / (depth * tan_h))
			lo = lo.min(sp)
			hi = hi.max(sp)
		var bb := Rect2(lo, hi - lo)
		var scale := maxf(bb.size.x / avail.size.x, bb.size.y / avail.size.y)
		# Spare vertical space (tall phones) goes mostly below the table, where the
		# launch button and flipper hints live.
		var want := Vector2(
			avail.get_center().x,
			avail.position.y + (avail.size.y - bb.size.y) * FIT_VALIGN + bb.size.y * 0.5
		)
		var off := bb.get_center() - want
		var h := 2.0 * dist * tan_h
		target += basis.x * off.x * h * aspect - basis.y * off.y * h
		dist *= lerpf(1.0, scale, 0.8)
		if absf(scale - 1.0) < 0.0005 and off.length() < 0.0005:
			break
	camera.transform = Transform3D(basis, target - dir * dist)


func _add_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 0.8
	sun.shadow_enabled = false
	sun.rotation_degrees = Vector3(-48, 28, 8)
	add_child(sun)

	var fill := OmniLight3D.new()
	fill.name = "Fill"
	fill.light_energy = 0.12
	fill.omni_range = 2.5
	playfield.add_child(fill)
	fill.position = Vector3(-0.02, 0.6, 0.0)


func _add_environment() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.145, 0.15, 0.17)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.48, 0.52, 0.6)
	env.ambient_light_energy = 0.38
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_env.environment = env
	add_child(world_env)


func spawn_ball() -> PinballBall:
	clear_ball()
	_set_gate_open(true)
	ball = PinballBall.new()
	ball.name = "Ball"
	playfield.add_child(ball)
	ball.position = spawn_local
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.freeze = true
	plunger.bind_ball(ball)
	return ball


func clear_ball() -> void:
	if ball != null and is_instance_valid(ball):
		ball.queue_free()
	ball = null
	if plunger:
		plunger.bind_ball(null)


func ball_playfield_position() -> Vector3:
	if ball == null or not is_instance_valid(ball) or playfield == null:
		return Vector3.ZERO
	return playfield.to_local(ball.global_position)
