extends Node

enum State { WAIT_LAUNCH, PLAYING, BALL_LOST, GAME_OVER }

@onready var world: PinballWorld = $World
@onready var hud: PinballHUD = $UI/HUD
@onready var touch: TouchControls = $UI/TouchControls
@onready var overlays: GameOverlays = $UI/Overlays

var score := 0
var balls_left := PinballData.BALLS_PER_GAME
var state: State = State.WAIT_LAUNCH
var _drain_lock := false
var _user_args: PackedStringArray = []
var _game_id := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("pinball_game")
	_user_args = OS.get_cmdline_user_args()
	world.ball_drained.connect(_on_ball_drained)
	world.plunger_charge_changed.connect(_on_plunger_charge)
	_new_game()
	if _has_arg("--smoke-test"):
		_run_smoke_test()
	elif _has_arg("--screenshot"):
		_run_screenshot()


func _new_game() -> void:
	_game_id += 1
	score = 0
	balls_left = PinballData.BALLS_PER_GAME
	_drain_lock = false
	get_tree().paused = false
	overlays.hide_all()
	_update_hud()
	_serve_ball()


func _serve_ball() -> void:
	state = State.WAIT_LAUNCH
	_drain_lock = false
	world.spawn_ball()
	_update_hud()


func add_score(points: int) -> void:
	if state == State.GAME_OVER:
		return
	score += points
	_update_hud()


func _update_hud() -> void:
	hud.set_status(score, balls_left, state == State.GAME_OVER)


func _on_plunger_charge(ratio: float) -> void:
	touch.set_launch_charge(ratio)
	if state == State.WAIT_LAUNCH and ratio > 0.0:
		state = State.PLAYING


func _on_ball_drained() -> void:
	if _drain_lock or state == State.GAME_OVER or state == State.BALL_LOST:
		return
	_drain_lock = true
	state = State.BALL_LOST
	_lose_ball()


func _lose_ball() -> void:
	var id := _game_id
	balls_left = max(balls_left - 1, 0)
	_update_hud()
	await get_tree().create_timer(0.85).timeout
	if not is_inside_tree() or id != _game_id:
		return
	world.clear_ball()
	if balls_left <= 0:
		state = State.GAME_OVER
		overlays.show_game_over(score)
		_update_hud()
	else:
		_serve_ball()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"pause") and state != State.GAME_OVER:
		_toggle_pause()
	if Input.is_action_just_pressed(&"restart"):
		_new_game()
	_check_out_of_bounds()


func _toggle_pause() -> void:
	if state == State.GAME_OVER:
		return
	var paused := not get_tree().paused
	get_tree().paused = paused
	if paused:
		overlays.show_paused()
	else:
		overlays.hide_all()


func _check_out_of_bounds() -> void:
	if state == State.GAME_OVER or state == State.BALL_LOST:
		return
	if world.ball == null or not is_instance_valid(world.ball):
		return
	var local := world.ball_playfield_position()
	if local.y < -0.25 or local.z > world.table_info("inner_half_z", 0.538) + 0.08:
		_on_ball_drained()


func _has_arg(flag: String) -> bool:
	for arg in _user_args:
		if arg == flag or arg.begins_with(flag + "="):
			return true
	return false


func _arg_value(flag: String, default_value: String) -> String:
	for arg in _user_args:
		if arg.begins_with(flag + "="):
			return arg.substr(flag.length() + 1)
	return default_value


func _run_smoke_test() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	var report := {}
	var failures: PackedStringArray = []

	if world.ball == null:
		failures.append("ball was not spawned")
	var start := world.ball_playfield_position()
	report["spawn"] = [start.x, start.y, start.z]
	await get_tree().create_timer(0.35).timeout
	var parked := world.ball_playfield_position()
	report["parked"] = [parked.x, parked.y, parked.z]
	if parked.x < world.table_info("lane_wall_x", 0.245):
		failures.append("ball left the plunger lane before launch")

	Input.action_press(&"plunger")
	await get_tree().create_timer(0.55).timeout
	report["plunger_charge"] = world.plunger.charge
	report["ball_frozen"] = world.ball.freeze
	report["ball_before_release"] = [
		world.ball_playfield_position().x,
		world.ball_playfield_position().y,
		world.ball_playfield_position().z,
	]
	Input.action_release(&"plunger")
	await get_tree().create_timer(0.4).timeout

	var launched := world.ball_playfield_position()
	report["after_launch"] = [launched.x, launched.y, launched.z]
	report["ball_velocity"] = [
		world.ball.linear_velocity.x,
		world.ball.linear_velocity.y,
		world.ball.linear_velocity.z,
	]
	var moved_up := launched.z < start.z - 0.20
	# Let the shot finish: it must leave the plunger lane onto the playfield.
	var entered := false
	for i in range(40):
		await get_tree().create_timer(0.05).timeout
		var p := world.ball_playfield_position()
		if p.x < world.table_info("lane_wall_x", 0.245) - 0.02:
			entered = true
			report["entered_playfield_at"] = [p.x, p.y, p.z]
			break
	report["entered_playfield"] = entered
	if not entered:
		failures.append("launched ball never left the plunger lane onto the playfield")
	report["moved_up_lane"] = moved_up
	if not moved_up:
		failures.append(
			"ball did not move up the lane (spawn z=%.3f after z=%.3f)" % [start.z, launched.z]
		)

	if world.left_flipper == null or world.right_flipper == null:
		failures.append("flippers missing")
	else:
		if absf(world.left_flipper.position.z - world.marker_position("Marker_FlipperLeft").z) > 0.01:
			failures.append("left flipper not at player-end marker (z=%.3f)" % world.left_flipper.position.z)
		var left_rest := world.left_flipper.rotation.y
		Input.action_press(&"flipper_left")
		await get_tree().create_timer(0.12).timeout
		var left_active := world.left_flipper.rotation.y
		Input.action_release(&"flipper_left")
		var left_ok := absf(rad_to_deg(left_active) - PinballData.FLIPPER_LEFT_ACTIVE_DEG) < 12.0
		report["left_flipper_rest_deg"] = rad_to_deg(left_rest)
		report["left_flipper_active_deg"] = rad_to_deg(left_active)
		report["left_flipper_ok"] = left_ok
		if not left_ok:
			failures.append("left flipper did not rotate to active angle")

		Input.action_press(&"flipper_right")
		await get_tree().create_timer(0.12).timeout
		var right_active := world.right_flipper.rotation.y
		Input.action_release(&"flipper_right")
		var right_ok := absf(rad_to_deg(right_active) - PinballData.FLIPPER_RIGHT_ACTIVE_DEG) < 12.0
		report["right_flipper_active_deg"] = rad_to_deg(right_active)
		report["right_flipper_ok"] = right_ok
		if not right_ok:
			failures.append("right flipper did not rotate to active angle")

	_check_inlane_collision(report, failures)
	await _check_inlane_ball_block(report, failures)
	await _check_slingshot_no_rest(report, failures)
	await _check_lane_roll(report, failures)
	await _check_launch_sweep(report, failures)

	if failures.is_empty():
		print("SMOKE TEST PASSED")
		print(JSON.stringify(report))
		get_tree().quit(0)
	else:
		printerr("SMOKE TEST FAILED: ", ", ".join(failures))
		print(JSON.stringify(report))
		get_tree().quit(1)


func _playfield_ray(from_local: Vector3, to_local: Vector3) -> Dictionary:
	var space := world.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		world.playfield.to_global(from_local),
		world.playfield.to_global(to_local)
	)
	query.collision_mask = PinballData.LAYER_WORLD
	query.collide_with_areas = false
	return space.intersect_ray(query)


func _sphere_clear(from_local: Vector3, to_local: Vector3, radius: float) -> bool:
	# True if a sphere of the given radius can travel the whole segment.
	var shape := SphereShape3D.new()
	shape.radius = radius
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(world.playfield.global_basis, world.playfield.to_global(from_local))
	q.motion = world.playfield.to_global(to_local) - world.playfield.to_global(from_local)
	q.collision_mask = PinballData.LAYER_WORLD | PinballData.LAYER_GADGET
	var res := world.get_world_3d().direct_space_state.cast_motion(q)
	return res.size() > 0 and res[0] >= 0.999


func _check_inlane_collision(report: Dictionary, failures: PackedStringArray) -> void:
	# Walls must block rays through them; lanes must let a ball-sized sphere pass.
	# All positions come from layout.json so they follow the table geometry.
	var lf := world.marker_position("Marker_FlipperLeft")
	var rf := world.marker_position("Marker_FlipperRight")
	var lanes: Dictionary = world.get_layout().get("lanes", {})
	var iz := world.table_info("inner_half_z", 0.538)
	var y := 0.02
	var blockers := [
		["left_apron", Vector3(lf.x + 0.04, y, lf.z + 0.07), Vector3(lf.x - 0.08, y, lf.z + 0.07)],
		["right_apron", Vector3(rf.x - 0.04, y, rf.z + 0.07), Vector3(rf.x + 0.08, y, rf.z + 0.07)],
		["top_wall", Vector3(0.0, y, -iz + 0.1), Vector3(0.0, y, -iz - 0.05)],
	]
	for side in ["left", "right"]:
		var ln: Dictionary = lanes.get(side, {})
		if ln.is_empty():
			failures.append("layout has no lane data for " + side)
			continue
		var s := -1.0 if side == "left" else 1.0
		var gx := float(ln["guide_x"])
		var wx := float(ln["side_wall_x"])
		# inlane -> outlane through the guide rail; outlane -> outside / plunger lane through the side wall
		blockers.append([side + "_guide", Vector3(gx - s * 0.02, y, 0.25), Vector3(gx + s * 0.02, y, 0.25)])
		blockers.append([side + "_side_wall", Vector3(wx - s * 0.02, y, 0.35), Vector3(wx + s * 0.03, y, 0.35)])
	for spec in blockers:
		var hit: Dictionary = _playfield_ray(spec[1], spec[2])
		report[String(spec[0]) + "_hit"] = not hit.is_empty()
		if hit.is_empty():
			failures.append("%s not blocking a playfield ray" % spec[0])
	# lanes: a ball-sized sphere must be able to roll along every lane segment
	var r := PinballData.BALL_RADIUS
	# plunger lane: nothing (guide ends, posts, pockets) may poke into it
	var sp := world.marker_position("Marker_BallSpawn")
	var lane_ok := _sphere_clear(Vector3(sp.x, r + 0.003, sp.z - 0.02), Vector3(sp.x, r + 0.003, -0.27), r - 0.0008)
	report["plunger_lane_clear"] = lane_ok
	if not lane_ok:
		failures.append("plunger lane is obstructed")
	for side in ["left", "right"]:
		var ln: Dictionary = lanes.get(side, {})
		for lane in ["inlane", "outlane"]:
			var pts: Array = ln.get(lane, [])
			var ok := pts.size() >= 2
			for i in range(pts.size() - 1):
				var a := Vector3(float(pts[i][0]), r + 0.003, float(pts[i][1]))
				var b := Vector3(float(pts[i + 1][0]), r + 0.003, float(pts[i + 1][1]))
				ok = ok and _sphere_clear(a, b, r - 0.0008)  # same radius as the ball collider
			report["%s_%s_clear" % [side, lane]] = ok
			if not ok:
				failures.append("%s %s is blocked for a ball" % [side, lane])


func _check_inlane_ball_block(report: Dictionary, failures: PackedStringArray) -> void:
	# Fire the ball at max speed into walls / rails and check it never ends up
	# behind them (anti-tunnelling). Each shot: start, velocity (table-local).
	if world.ball == null or not is_instance_valid(world.ball):
		failures.append("no ball for wall impact test")
		return
	world.plunger.bind_ball(null)
	var ix := world.table_info("inner_half_x", 0.288)
	var iz := world.table_info("inner_half_z", 0.538)
	var lane_x := world.table_info("lane_wall_x", 0.245)
	var r := PinballData.BALL_RADIUS
	var pockets: Array[PackedVector2Array] = []
	var col: Dictionary = world.get_layout().get("colliders", {})
	for raw in col.get("pockets", []):
		var poly := PackedVector2Array()
		for q in raw:
			poly.append(Vector2(float(q[0]), float(q[1])))
		pockets.append(poly)
	var lanes: Dictionary = world.get_layout().get("lanes", {})
	var lg_x := float(lanes.get("left", {}).get("guide_x", -0.247))
	var rg_x := float(lanes.get("right", {}).get("guide_x", 0.198))
	var guide_top_z := float(lanes.get("left", {}).get("inlane", [[0, 0.13]])[0][1])
	var shots := [
		["left_guide", Vector3(lg_x + 0.017, r, 0.25), Vector3(-12.0, 0.0, 0.3)],
		["right_guide", Vector3(rg_x - 0.017, r, 0.25), Vector3(12.0, 0.0, 0.3)],
		["left_outlane_wall", Vector3(lg_x - 0.022, r, 0.30), Vector3(-12.0, 0.0, 0.3)],
		["right_outlane_wall", Vector3(rg_x + 0.022, r, 0.30), Vector3(12.0, 0.0, 0.3)],
		["left_wall", Vector3(-ix + 0.03, r, -0.20), Vector3(-12.0, 0.0, 0.5)],
		["lane_wall", Vector3(lane_x - 0.03, r, -0.11), Vector3(12.0, 0.0, -0.3)],
		["top_wall", Vector3(-0.02, r, -iz + 0.2), Vector3(0.3, 0.0, -12.0)],
		["top_right_chamfer", Vector3(0.12, r, -iz + 0.15), Vector3(8.0, 0.0, -8.0)],
	]
	for shot in shots:
		world.ball.freeze = false
		world.ball.position = shot[1]
		world.ball.linear_velocity = Vector3.ZERO
		world.ball.launch(world.playfield.global_transform.basis * Vector3(shot[2]))
		var worst := Vector3.ZERO
		var escaped := false
		for i in range(12):
			await get_tree().physics_frame
			await get_tree().physics_frame
			if world.ball == null or not is_instance_valid(world.ball):
				failures.append("ball disappeared during %s impact test" % shot[0])
				return
			var pos := world.ball_playfield_position()
			var p2 := Vector2(pos.x, pos.z)
			var out := pos.x < -ix or pos.x > ix or pos.z < -iz or pos.z > iz or pos.y < -0.02
			# beyond the centre line of the top-right chamfer wall
			out = out or (pos.x - pos.z) > (ix + iz + 0.012 - world.table_info("chamfer", 0.09))
			for poly in pockets:
				out = out or Geometry2D.is_point_in_polygon(p2, poly)
			if shot[0] == "lane_wall" or shot[0] == "right_outlane_wall":
				out = out or pos.x > lane_x
			# a shot from the inlane must never end up in the outlane (through the rail)
			if shot[0] == "left_guide":
				out = out or (pos.x < lg_x - 0.006 and pos.z > guide_top_z + 0.02)
			if shot[0] == "right_guide":
				out = out or (pos.x > rg_x + 0.006 and pos.z > guide_top_z + 0.02)
			if out:
				escaped = true
				worst = pos
				break
			worst = pos
		report[String(shot[0]) + "_impact"] = [worst.x, worst.y, worst.z]
		if escaped:
			failures.append("ball tunneled through %s (x=%.3f z=%.3f)" % [shot[0], worst.x, worst.z])


func _check_launch_sweep(report: Dictionary, failures: PackedStringArray) -> void:
	# Weak, medium and full-power launches must all leave the plunger lane onto
	# the playfield (a full-power shot used to bounce off the right inlane corner).
	var lane_x := world.table_info("lane_wall_x", 0.245)
	_drain_lock = true   # keep the game logic from serving balls meanwhile
	for hold in [0.06, 0.3, 0.7]:
		world.spawn_ball()
		await get_tree().create_timer(0.3).timeout
		Input.action_press(&"plunger")
		await get_tree().create_timer(hold).timeout
		Input.action_release(&"plunger")
		var entered := false
		var top_z := 1.0
		for i in range(60):
			await get_tree().create_timer(0.05).timeout
			var p := world.ball_playfield_position()
			top_z = minf(top_z, p.z)
			if p.x < lane_x - 0.03:
				entered = true
				break
		report["launch_hold_%.2f" % hold] = [entered, snappedf(top_z, 0.001)]
		if not entered:
			failures.append("launch (hold %.2f s) did not reach the playfield (min z %.3f)" % [hold, top_z])
	_drain_lock = false


func _seg_dist(p: Vector2, raw: Array) -> float:
	var a := Vector2(float(raw[0][0]), float(raw[0][1]))
	var b := Vector2(float(raw[1][0]), float(raw[1][1]))
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))


func _check_lane_roll(report: Dictionary, failures: PackedStringArray) -> void:
	# A ball dropped at the top of each inlane must roll out onto the flipper;
	# one dropped at the top of each outlane must roll down to the outlane drain.
	var lanes: Dictionary = world.get_layout().get("lanes", {})
	var cx := world.table_info("playfield_center_x", -0.0245)
	var lf_z := world.marker_position("Marker_FlipperLeft").z
	var balls: Array = []
	for side in ["left", "right"]:
		for lane in ["inlane", "outlane"]:
			var p0: Array = lanes[side][lane][0]
			var b := PinballBall.new()
			world.playfield.add_child(b)
			b.collision_layer = 0
			b.position = Vector3(float(p0[0]), PinballData.BALL_RADIUS + 0.001, float(p0[1]) + 0.01)
			b.set_meta("tag", side + "_" + lane)
			balls.append(b)
	await get_tree().create_timer(3.0).timeout
	for b in balls:
		var pos: Vector3 = world.playfield.to_local(b.global_position)
		var tag := String(b.get_meta("tag"))
		var ok: bool
		if tag.ends_with("inlane"):
			ok = pos.z > lf_z - 0.07 and absf(pos.x - cx) < 0.16   # at the flippers / centre drain
		else:
			ok = pos.z > world.table_info("inner_half_z", 0.538) - 0.10 and absf(pos.x - cx) > 0.22   # bottom of the outlane
		report["roll_" + tag] = [snappedf(pos.x, 0.001), snappedf(pos.z, 0.001), ok]
		if not ok:
			failures.append("%s roll test ended at x=%.3f z=%.3f" % [tag, pos.x, pos.z])
		b.queue_free()


func _edges_dist(p: Vector2, edges: Array) -> float:
	var d := INF
	for e in edges:
		d = minf(d, _seg_dist(p, e))
	return d


func _check_slingshot_no_rest(report: Dictionary, failures: PackedStringArray) -> void:
	# Drop test balls on a grid around both slingshots (kicking faces, deflectors
	# and the guide just below) with the flippers down, simulate a few seconds,
	# and require that none of them comes to rest near a slingshot.
	var slings: Dictionary = world.get_layout().get("slingshots", {})
	if slings.is_empty():
		failures.append("layout has no slingshot data")
		return
	var space := world.get_world_3d().direct_space_state
	var probe := SphereShape3D.new()
	probe.radius = PinballData.BALL_RADIUS + 0.002
	var balls: Array = []
	for key in slings.keys():
		var sl: Dictionary = slings[key]
		var edges: Array = sl["edges"]
		var xs: Array = []
		var zs: Array = []
		for e in edges:
			xs.append(float(e[0][0]))
			zs.append(float(e[0][1]))
		var x0: float = xs.min() - 0.08
		var x1: float = xs.max() + 0.08
		var z0: float = zs.min() - 0.10
		var z1: float = zs.max() + 0.04
		var x := x0
		while x <= x1:
			var z := z0
			while z <= z1:
				var p2 := Vector2(x, z)
				if _edges_dist(p2, edges) < 0.09:
					# probe sits 2 mm above the floor so it only detects walls / gadgets
					var local := Vector3(x, PinballData.BALL_RADIUS + 0.004, z)
					var q := PhysicsShapeQueryParameters3D.new()
					q.shape = probe
					q.transform = Transform3D(world.playfield.global_basis, world.playfield.to_global(local))
					q.collision_mask = PinballData.LAYER_WORLD | PinballData.LAYER_GADGET | PinballData.LAYER_FLIPPER
					var inside_pocket := false
					for raw in world.get_layout().get("colliders", {}).get("pockets", []):
						var poly := PackedVector2Array()
						for c in raw:
							poly.append(Vector2(float(c[0]), float(c[1])))
						if Geometry2D.is_point_in_polygon(p2, poly):
							inside_pocket = true
					if not inside_pocket and space.intersect_shape(q, 1).is_empty():
						var b := PinballBall.new()
						b.name = "SlingTestBall%d" % balls.size()
						world.playfield.add_child(b)
						b.collision_layer = 0  # invisible to the drain and other test balls
						b.position = local
						b.set_meta("start", p2)
						b.set_meta("sling", key)
						balls.append(b)
				z += 0.03
			x += 0.03
	# plus balls dropped right onto each slingshot's top corner (balance-point check)
	for key in slings.keys():
		var top := Vector2(0.0, INF)
		for e in slings[key]["edges"]:
			if float(e[0][1]) < top.y:
				top = Vector2(float(e[0][0]), float(e[0][1]))
		for dx in [-0.006, -0.003, -0.001, 0.0, 0.001, 0.003, 0.006, 0.01]:
			var b := PinballBall.new()
			world.playfield.add_child(b)
			b.collision_layer = 0
			b.position = Vector3(top.x + dx, PinballData.BALL_RADIUS + 0.001, top.y - 0.03)
			b.set_meta("start", Vector2(top.x + dx, top.y - 0.03))
			b.set_meta("sling", key)
			balls.append(b)
	report["sling_test_balls"] = balls.size()
	if balls.size() < 20:
		failures.append("too few slingshot test positions (%d)" % balls.size())
	await get_tree().create_timer(5.0).timeout
	var stuck: Array = []
	var at_bottom := 0
	var lf_z := world.marker_position("Marker_FlipperLeft").z
	for b in balls:
		var pos: Vector3 = world.playfield.to_local(b.global_position)
		var p2 := Vector2(pos.x, pos.z)
		var sl: Dictionary = slings[b.get_meta("sling")]
		var near: bool = _edges_dist(p2, sl["edges"]) < 0.10
		if pos.z > lf_z - 0.06:
			at_bottom += 1
		if b.linear_velocity.length() < 0.03 and near:
			var s0: Vector2 = b.get_meta("start")
			stuck.append("start(%.2f,%.2f)->rest(%.3f,%.3f)" % [s0.x, s0.y, pos.x, pos.z])
		b.queue_free()
	report["sling_test_at_flippers_or_drain"] = at_bottom
	report["sling_test_stuck"] = stuck
	if not stuck.is_empty():
		failures.append("%d balls came to rest near a slingshot: %s" % [stuck.size(), ", ".join(stuck)])


func _run_screenshot() -> void:
	var path := _arg_value("--screenshot", "docs/gameplay.png")
	if not path.begins_with("/") and not path.begins_with("res://") and not path.begins_with("user://"):
		path = ProjectSettings.globalize_path("res://").path_join(path)
	# Launch so the table is in play, then capture.
	await get_tree().create_timer(0.3).timeout
	Input.action_press(&"plunger")
	await get_tree().create_timer(0.5).timeout
	Input.action_release(&"plunger")
	Input.action_press(&"flipper_left")
	Input.action_press(&"flipper_right")
	await get_tree().create_timer(0.55).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	Input.action_release(&"flipper_left")
	Input.action_release(&"flipper_right")
	if err != OK:
		printerr("Failed to save screenshot to ", path, " err=", err)
		get_tree().quit(1)
		return
	print("SCREENSHOT SAVED ", path)
	get_tree().quit(0)
