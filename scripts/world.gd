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
		# Outer walls and the plunger-lane splitter use primitive boxes (more
		# reliable at this scale than a single outer-wall trimesh AABB contact).
		if mesh_instance.name == "Floor":
			_add_floor(playfield, floor_mat)
		elif mesh_instance.name == "MazeWalls":
			ModelUtil.add_trimesh_collision(mesh_instance, wall_mat)

	_add_outer_wall_boxes(playfield, wall_mat)
	_add_glass(playfield)
	_add_lane_gate(playfield)

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

	for i in range(1, 4):
		var bumper := PinballBumper.new()
		bumper.name = "Bumper%d" % i
		bumper.position = marker_position("Marker_Bumper%d" % i)
		playfield.add_child(bumper)

	var sling_l := PinballSlingshot.new()
	sling_l.name = "SlingshotLeft"
	sling_l.is_left = true
	sling_l.position = marker_position("Marker_SlingshotLeft")
	playfield.add_child(sling_l)

	var sling_r := PinballSlingshot.new()
	sling_r.name = "SlingshotRight"
	sling_r.is_left = false
	sling_r.position = marker_position("Marker_SlingshotRight")
	playfield.add_child(sling_r)

	var target_1 := PinballTarget.new()
	target_1.name = "Target1"
	target_1.position = marker_position("Marker_Target1")
	playfield.add_child(target_1)

	var target_2 := PinballTarget.new()
	target_2.name = "Target2"
	target_2.position = marker_position("Marker_Target2")
	playfield.add_child(target_2)

	drain = PinballDrain.new()
	drain.name = "Drain"
	drain.position = marker_position("Marker_Drain")
	playfield.add_child(drain)
	drain.ball_drained.connect(func() -> void: ball_drained.emit())

	_add_lights()
	_add_camera()
	_add_environment()


func _add_floor(parent: Node3D, phys_mat: PhysicsMaterial) -> void:
	var body := StaticBody3D.new()
	body.name = "FloorBody"
	body.physics_material_override = phys_mat
	body.collision_layer = PinballData.LAYER_WORLD
	body.collision_mask = PinballData.LAYER_BALL
	parent.add_child(body)
	var box := BoxShape3D.new()
	box.size = Vector3(0.62, 0.02, 1.12)
	var cs := CollisionShape3D.new()
	cs.shape = box
	cs.position = Vector3(0.0, -0.01, 0.0)
	body.add_child(cs)


func _add_outer_wall_boxes(parent: Node3D, phys_mat: PhysicsMaterial) -> void:
	var walls := [
		["WallLeft", Vector3(-0.296, 0.025, 0.0), Vector3(0.008, 0.05, 1.10)],
		["WallRight", Vector3(0.296, 0.025, 0.0), Vector3(0.008, 0.05, 1.10)],
		["WallTop", Vector3(0.0, 0.025, -0.546), Vector3(0.60, 0.05, 0.008)],
		["WallBottom", Vector3(0.0, 0.025, 0.546), Vector3(0.60, 0.05, 0.008)],
		["WallTopRightChamfer", Vector3(0.255, 0.025, -0.505), Vector3(0.12, 0.05, 0.010)],
		["WallTopLeftChamfer", Vector3(-0.255, 0.025, -0.505), Vector3(0.12, 0.05, 0.010)],
		["WallLane", Vector3(0.240, 0.025, 0.132), Vector3(0.008, 0.05, 0.824)],
		# Inlanes / apron (kept inside the playfield so they cannot pinch the plunger lane).
		["WallInlaneLeft", Vector3(-0.177, 0.025, 0.354), Vector3(0.20, 0.05, 0.010)],
		["WallInlaneRight", Vector3(0.153, 0.025, 0.354), Vector3(0.20, 0.05, 0.010)],
		["WallApronLeft", Vector3(-0.116, 0.025, 0.48), Vector3(0.010, 0.05, 0.14)],
		["WallApronRight", Vector3(0.067, 0.025, 0.48), Vector3(0.010, 0.05, 0.14)],
	]
	var chamfer_yaw := {
		"WallTopRightChamfer": deg_to_rad(-45),
		"WallTopLeftChamfer": deg_to_rad(45),
		"WallInlaneLeft": deg_to_rad(32),
		"WallInlaneRight": deg_to_rad(-32),
	}
	for spec in walls:
		var body := StaticBody3D.new()
		body.name = String(spec[0])
		body.physics_material_override = phys_mat
		body.collision_layer = PinballData.LAYER_WORLD
		body.collision_mask = PinballData.LAYER_BALL
		parent.add_child(body)
		var box := BoxShape3D.new()
		box.size = spec[2]
		var cs := CollisionShape3D.new()
		cs.shape = box
		cs.position = spec[1]
		if chamfer_yaw.has(body.name):
			cs.rotation.y = chamfer_yaw[body.name]
		body.add_child(cs)


func _add_glass(parent: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "Glass"
	body.collision_layer = PinballData.LAYER_WORLD
	body.collision_mask = PinballData.LAYER_BALL
	parent.add_child(body)
	var box := BoxShape3D.new()
	box.size = Vector3(0.60, 0.004, 1.10)
	var cs := CollisionShape3D.new()
	cs.shape = box
	cs.position = Vector3(0.0, 0.16, 0.0)
	body.add_child(cs)


func _add_lane_gate(parent: Node3D) -> void:
	# One-way gate at the top of the plunger lane: open while the ball is launching
	# up the lane, closed once it is in the playfield so it cannot fall back in.
	_shot_gate = StaticBody3D.new()
	_shot_gate.name = "LaneGate"
	_shot_gate.collision_layer = PinballData.LAYER_WORLD
	_shot_gate.collision_mask = PinballData.LAYER_BALL
	parent.add_child(_shot_gate)
	var box := BoxShape3D.new()
	box.size = Vector3(0.012, 0.045, 0.10)
	var cs := CollisionShape3D.new()
	cs.shape = box
	cs.position = Vector3(0.245, 0.022, -0.33)
	_shot_gate.add_child(cs)
	_set_gate_open(true)


func _set_gate_open(open: bool) -> void:
	if _shot_gate == null:
		return
	_shot_gate.collision_layer = 0 if open else PinballData.LAYER_WORLD


func _physics_process(_delta: float) -> void:
	if ball == null or not is_instance_valid(ball) or playfield == null:
		return
	var local := playfield.to_local(ball.global_position)
	if local.x < 0.18 and local.z < -0.08:
		_set_gate_open(false)


func _add_camera() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 34.0
	camera.near = 0.02
	camera.far = 25.0
	camera.current = true
	playfield.add_child(camera)
	camera.position = Vector3(-0.0245, 1.18, 1.08)
	camera.look_at(playfield.to_global(Vector3(-0.0245, 0.0, -0.06)), playfield.global_transform.basis.y)


func _add_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 1.15
	sun.shadow_enabled = false
	sun.rotation_degrees = Vector3(-48, 28, 8)
	add_child(sun)

	var fill := OmniLight3D.new()
	fill.name = "Fill"
	fill.light_energy = 0.35
	fill.omni_range = 2.5
	playfield.add_child(fill)
	fill.position = Vector3(-0.02, 0.55, -0.1)


func _add_environment() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.145, 0.15, 0.17)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.48, 0.52, 0.6)
	env.ambient_light_energy = 0.62
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
