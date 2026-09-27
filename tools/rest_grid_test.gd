extends SceneTree
## Whole-table "no resting spots" test (run: godot --headless --path . -s tools/rest_grid_test.gd).
## Drops a ball (non-interacting, invisible to the drain) on every free point of a
## 35 mm grid over the playfield above the flippers, flippers down, simulates 12 s
## and fails if any ball is still stationary above the flipper line.
var main; var w; var t := 0.0; var balls := []; var started := false; var zmax := 0.38
func _initialize():
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
func _physics_process(delta):
	t += delta
	w = main.get_node("World")
	if t > 0.3 and not started:
		started = true
		var space = w.get_world_3d().direct_space_state
		var probe := SphereShape3D.new(); probe.radius = 0.0155
		var pockets = []
		for raw in w.get_layout()["colliders"]["pockets"]:
			var poly := PackedVector2Array()
			for c in raw: poly.append(Vector2(c[0], c[1]))
			pockets.append(poly)
		var ix: float = w.table_info("inner_half_x", 0.288)
		var iz: float = w.table_info("inner_half_z", 0.538)
		zmax = w.marker_position("Marker_FlipperLeft").z - 0.05
		var x := -ix + 0.016
		while x < w.table_info("lane_wall_x", 0.245) - 0.01:
			var z := -iz + 0.016
			while z < zmax:
				var p2 = Vector2(x, z); var bad = false
				for poly in pockets: bad = bad or Geometry2D.is_point_in_polygon(p2, poly)
				var q := PhysicsShapeQueryParameters3D.new(); q.shape = probe
				q.transform = Transform3D(w.playfield.global_basis, w.playfield.to_global(Vector3(x, 0.0175, z)))
				q.collision_mask = 1 | 4 | 8
				if not bad and space.intersect_shape(q, 1).is_empty():
					var b := PinballBall.new(); w.playfield.add_child(b); b.collision_layer = 0
					b.position = Vector3(x, 0.0145, z); b.set_meta("s", p2); balls.append(b)
				z += 0.035
			x += 0.035
	if started and absf(t - 10.3) < delta * 0.5:
		for b in balls: b.set_meta("p10", w.playfield.to_local(b.global_position))
	if started and t > 12.3:
		var n := 0
		for b in balls:
			var p = w.playfield.to_local(b.global_position)
			if b.linear_velocity.length() < 0.03 and p.z < zmax and b.has_meta("p10") and p.distance_to(b.get_meta("p10")) < 0.005:
				n += 1; print("REST start ", b.get_meta("s"), " -> ", Vector2(p.x, p.z))
		print("REST GRID: %d balls, %d resting above flippers" % [balls.size(), n])
		print("REST GRID TEST PASSED" if n == 0 else "REST GRID TEST FAILED")
		quit(0 if n == 0 else 1)
	return false
