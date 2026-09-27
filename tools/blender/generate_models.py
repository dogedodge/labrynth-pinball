"""
Generate the low-poly 3D models for labrynth-pinball.

Usage (headless, from repo root):
    blender -b --factory-startup --python tools/blender/generate_models.py -- [--preview /path/preview.png]

Outputs (relative to repo root):
    assets/blender/labrynth_models.blend   source file (one collection per model)
    assets/models/*.glb                    one glTF binary per model
    assets/models/layout.json              suggested placements (Godot coordinates)

Conventions
    1 Blender unit = 1 metre. Blender is Z-up; the glTF exporter converts to Godot's
    Y-up, so Blender (x, y, z) -> Godot (x, z, -y).
    Table top (far end, where the bumpers are) is Blender +Y  == Godot -Z.
    The player / flippers / drain are at Blender -Y           == Godot +Z.
    Playfield surface is at height 0.
"""
import bpy, bmesh, math, os, sys, json
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
MODELS = os.path.join(ROOT, "assets", "models")
BLEND = os.path.join(ROOT, "assets", "blender")
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PREVIEW = argv[argv.index("--preview") + 1] if "--preview" in argv else None

# ---------------------------------------------------------------- dimensions
TABLE_W, TABLE_L = 0.60, 1.10          # outer size (m)
FLOOR_T = 0.02                          # floor thickness (below z=0)
WALL_H, WALL_T = 0.05, 0.012            # wall height / thickness
BALL_R = 0.0135                         # 27 mm ball (real pinball size)
HX, HY = TABLE_W / 2, TABLE_L / 2
INNER_X = HX - WALL_T                   # inner face of outer walls
LANE_WALL_X = 0.245                     # plunger lane separator (centre line)
LANE_CX = (LANE_WALL_X + WALL_T / 2 + INNER_X) / 2   # plunger lane centre
PLAY_CX = (-INNER_X + LANE_WALL_X - WALL_T / 2) / 2  # playfield centre x
FLIP_LEN, FLIP_R0, FLIP_R1, FLIP_H = 0.07, 0.012, 0.006, 0.025
FLIP_PIVOT_DX, FLIP_PIVOT_Y = 0.075, -0.42
BUMPER_R = 0.03

# ---------------------------------------------------------------- helpers
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    s = bpy.context.scene
    s.unit_settings.system = 'METRIC'
    s.unit_settings.scale_length = 1.0

def mat(name, rgb, metal=0.0, rough=0.6, emit=None):
    m = bpy.data.materials.get(name)
    if m: return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = 1.0
    m.diffuse_color = (*rgb, 1)   # viewport / workbench colour
    return m

def collection(name):
    c = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(c)
    return c

def obj_from_bm(name, bm, material, coll, smooth=False):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth = smooth
    me.materials.append(material)
    o = bpy.data.objects.new(name, me)
    coll.objects.link(o)
    return o

def add_box(bm, cx, cy, z0, sx, sy, sz, rot=0.0):
    """Axis box of size sx,sy,sz rotated by rot around Z, bottom at z0."""
    r = bmesh.ops.create_cube(bm, size=1.0)
    vs = r["verts"]
    c, s = math.cos(rot), math.sin(rot)
    for v in vs:
        x, y, z = v.co.x * sx, v.co.y * sy, (v.co.z + 0.5) * sz + z0
        v.co = Vector((cx + x * c - y * s, cy + x * s + y * c, z))

def add_wall(bm, p0, p1, h=WALL_H, t=WALL_T, extend=True):
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    L = d.length + (t if extend else 0)
    mid = (p0 + p1) / 2
    add_box(bm, mid.x, mid.y, 0.0, L, t, h, math.atan2(d.y, d.x))

def add_cyl(bm, cx, cy, z0, r, h, seg=16, r_top=None):
    r_top = r if r_top is None else r_top
    res = bmesh.ops.create_cone(bm, cap_ends=True, segments=seg,
                                radius1=r, radius2=r_top, depth=h)
    for v in res["verts"]:
        v.co += Vector((cx, cy, z0 + h / 2))

def prism(bm, pts2d, z0, h):
    """Convex prism from 2D points."""
    vs = [bm.verts.new((x, y, z)) for z in (z0, z0 + h) for (x, y) in pts2d]
    bmesh.ops.convex_hull(bm, input=vs)

def circle_pts(cx, cy, r, n):
    return [(cx + r * math.cos(2 * math.pi * i / n), cy + r * math.sin(2 * math.pi * i / n)) for i in range(n)]

def empty(name, loc, coll, rot_z=0.0):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = 'ARROWS'
    e.empty_display_size = 0.03
    e.location = loc
    e.rotation_euler = (0, 0, rot_z)
    coll.objects.link(e)
    return e

# ---------------------------------------------------------------- materials
reset()
M = {
    "floor":  mat("Playfield", (0.10, 0.12, 0.30), rough=0.4),
    "wall":   mat("WallStone", (0.78, 0.72, 0.60), rough=0.8),
    "maze":   mat("MazeTeal",  (0.10, 0.55, 0.55), rough=0.6),
    "guide":  mat("GuideOrange", (0.95, 0.50, 0.10), rough=0.5),
    "chrome": mat("Chrome", (0.85, 0.85, 0.90), metal=1.0, rough=0.15),
    "flip":   mat("FlipperWhite", (0.95, 0.95, 0.95), rough=0.4),
    "rubber": mat("RubberRed", (0.85, 0.10, 0.10), rough=0.8),
    "cap":    mat("BumperCap", (1.0, 0.85, 0.15), rough=0.3, emit=(0.6, 0.45, 0.05)),
    "dark":   mat("DarkPlastic", (0.08, 0.08, 0.10), rough=0.5),
    "target": mat("TargetGreen", (0.15, 0.85, 0.25), rough=0.4, emit=(0.05, 0.3, 0.08)),
}
layout = {}

# ---------------------------------------------------------------- TABLE
C_table = collection("table")
bm = bmesh.new()
add_box(bm, 0, 0, -FLOOR_T, TABLE_W, TABLE_L, FLOOR_T)
obj_from_bm("Floor", bm, M["floor"], C_table)

# outer walls (with angled top corners)
bm = bmesh.new()
cx_ = HX - WALL_T / 2; cy_ = HY - WALL_T / 2; K = 0.09  # corner chamfer size
add_wall(bm, (-cx_, -cy_), (-cx_, cy_ - K))                 # left
add_wall(bm, (cx_, -cy_), (cx_, cy_ - K))                   # right
add_wall(bm, (-cx_ + K, cy_), (cx_ - K, cy_))               # top
add_wall(bm, (-cx_, -cy_), (cx_, -cy_))                     # bottom (drain zone is above this)
add_wall(bm, (-cx_, cy_ - K), (-cx_ + K, cy_), extend=False)  # top-left chamfer
add_wall(bm, (cx_, cy_ - K), (cx_ - K, cy_), extend=False)    # top-right chamfer (deflects launch)
obj_from_bm("OuterWalls", bm, M["wall"], C_table)

# plunger lane separator
bm = bmesh.new()
add_wall(bm, (LANE_WALL_X, -cy_), (LANE_WALL_X, 0.28), extend=False)
obj_from_bm("PlungerLaneWall", bm, M["wall"], C_table)

# inlane guides: from outer/lane wall down towards the flipper pivots
lp = (PLAY_CX - FLIP_PIVOT_DX, FLIP_PIVOT_Y)
rp = (PLAY_CX + FLIP_PIVOT_DX, FLIP_PIVOT_Y)
half = LANE_WALL_X - WALL_T / 2 - PLAY_CX            # half width of playfield
gap = FLIP_R0 + 0.004                                 # guide ends just outside pivot
bm = bmesh.new()
add_wall(bm, (PLAY_CX - half, -0.30), (lp[0] - gap, lp[1] + 0.012))
add_wall(bm, (PLAY_CX + half, -0.30), (rp[0] + gap, rp[1] + 0.012))
# lower apron walls closing the area under the guides (keeps ball out of dead zones)
add_wall(bm, (lp[0] - gap, lp[1] + 0.012), (lp[0] - gap, -cy_))
add_wall(bm, (rp[0] + gap, rp[1] + 0.012), (rp[0] + gap, -cy_))
obj_from_bm("InlaneGuides", bm, M["guide"], C_table)

# labyrinth-style wall segments in the upper playfield (gaps >= 6 cm, ball is 2.7 cm)
maze = [
    ((-0.23, 0.26), (-0.23, 0.40)), ((-0.23, 0.40), (-0.15, 0.40)),   # upper-left L
    ((0.17, 0.26), (0.17, 0.40)),   ((0.17, 0.40), (0.09, 0.40)),     # upper-right L
    ((-0.07, 0.40), (0.01, 0.40)),                                     # top centre bar
    ((-0.03, 0.40), (-0.03, 0.34)),                                    # T stem
    ((-0.23, 0.12), (-0.17, 0.12)),                                    # left stub
    ((0.17, 0.12), (0.11, 0.12)),                                      # right stub
]
bm = bmesh.new()
for a, b in maze: add_wall(bm, a, b, h=0.04, t=0.01)
obj_from_bm("MazeWalls", bm, M["maze"], C_table)

# placement markers (exported as Node3D in the glb)
P = {
    "Marker_FlipperLeft":  ((lp[0], lp[1], 0), 0.0),
    "Marker_FlipperRight": ((rp[0], rp[1], 0), math.pi),
    "Marker_Plunger":      ((LANE_CX, -0.50, 0), 0.0),
    "Marker_BallSpawn":    ((LANE_CX, -0.50 + BALL_R + 0.002, BALL_R), 0.0),
    "Marker_Bumper1":      ((PLAY_CX - 0.075, 0.20, 0), 0.0),
    "Marker_Bumper2":      ((PLAY_CX + 0.075, 0.20, 0), 0.0),
    "Marker_Bumper3":      ((PLAY_CX, 0.29, 0), 0.0),
    "Marker_SlingshotLeft":  ((PLAY_CX - 0.16, -0.24, 0), 0.0),
    "Marker_SlingshotRight": ((PLAY_CX + 0.16, -0.24, 0), 0.0),
    "Marker_Target1":      ((-0.19, 0.465, 0), 0.0),
    "Marker_Target2":      ((0.13, 0.465, 0), 0.0),
    "Marker_Drain":        ((PLAY_CX, -0.51, 0), 0.0),
}
for n, (loc, rz) in P.items():
    empty(n, loc, C_table, rz)
    x, y, z = loc
    layout[n] = {"godot_position": [round(x, 4), round(z, 4), round(-y, 4)],
                 "godot_rotation_y_deg": round(math.degrees(rz), 1)}

# ---------------------------------------------------------------- FLIPPER
C_flip = collection("flipper")
bm = bmesh.new()
pts = circle_pts(0, 0, FLIP_R0, 16) + circle_pts(FLIP_LEN, 0, FLIP_R1, 12)
prism(bm, pts, 0.001, FLIP_H)
obj_from_bm("Flipper", bm, M["flip"], C_flip)
bm = bmesh.new()   # red rubber band slightly outside the bat
pts = circle_pts(0, 0, FLIP_R0 + 0.0015, 16) + circle_pts(FLIP_LEN, 0, FLIP_R1 + 0.0015, 12)
prism(bm, pts, 0.008, 0.008)
obj_from_bm("FlipperRubber", bm, M["rubber"], C_flip)
bm = bmesh.new()
add_cyl(bm, 0, 0, FLIP_H + 0.001, 0.005, 0.004, seg=12)
obj_from_bm("FlipperPivotCap", bm, M["chrome"], C_flip)

# ---------------------------------------------------------------- BALL
C_ball = collection("ball")
bm = bmesh.new()
bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=BALL_R)
obj_from_bm("Ball", bm, M["chrome"], C_ball, smooth=True)

# ---------------------------------------------------------------- BUMPER
C_bump = collection("bumper")
bm = bmesh.new(); add_cyl(bm, 0, 0, 0.0, BUMPER_R, 0.005, seg=20)
obj_from_bm("BumperBase", bm, M["dark"], C_bump)
bm = bmesh.new(); add_cyl(bm, 0, 0, 0.005, BUMPER_R * 0.8, 0.022, seg=20)
obj_from_bm("BumperSkirt", bm, M["rubber"], C_bump)
bm = bmesh.new(); add_cyl(bm, 0, 0, 0.027, BUMPER_R, 0.008, seg=20)
add_cyl(bm, 0, 0, 0.035, BUMPER_R * 0.85, 0.008, seg=20, r_top=BUMPER_R * 0.45)
obj_from_bm("BumperCap", bm, M["cap"], C_bump)

# ---------------------------------------------------------------- PLUNGER
C_plng = collection("plunger")
bm = bmesh.new(); add_box(bm, 0, -0.006, 0.001, 0.03, 0.012, 0.022)   # head; front face at y=0
obj_from_bm("PlungerHead", bm, M["dark"], C_plng)
bm = bmesh.new()
res = bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=0.004, radius2=0.004, depth=0.07)
for v in res["verts"]:
    v.co = Vector((v.co.x, v.co.z - 0.012 - 0.035, v.co.y + 0.012))   # rod along -Y
obj_from_bm("PlungerRod", bm, M["chrome"], C_plng)
bm = bmesh.new()
res = bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=0.009, radius2=0.009, depth=0.015)
for v in res["verts"]:
    v.co = Vector((v.co.x, v.co.z - 0.082 - 0.0075, v.co.y + 0.012))
obj_from_bm("PlungerKnob", bm, M["rubber"], C_plng)

# ---------------------------------------------------------------- SLINGSHOTS (left + mirrored right)
def slingshot(name, sign):
    C = collection(name)
    tri = [(0.0, 0.045), (0.0, -0.045), (0.04, -0.065)]      # left version: kicker faces +X
    cx = sum(p[0] for p in tri) / 3; cy = sum(p[1] for p in tri) / 3
    tri = [((x - cx) * sign, y - cy) for x, y in tri]
    bm = bmesh.new(); prism(bm, tri, 0.0, 0.035)
    obj_from_bm(name.title().replace("_", "") + "Body", bm, M["guide"], C)
    # rubber kicker strip along the hypotenuse
    a, b = Vector((*tri[0], 0)), Vector((*tri[2], 0))
    bm = bmesh.new(); add_wall(bm, a, b, h=0.03, t=0.006, extend=False)
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0.003 * sign, 0.0015, 0.003))
    obj_from_bm(name.title().replace("_", "") + "Kicker", bm, M["rubber"], C)
    return C
C_sl = slingshot("slingshot_left", 1)
C_sr = slingshot("slingshot_right", -1)

# ---------------------------------------------------------------- STANDUP TARGET
C_tgt = collection("target")
bm = bmesh.new(); add_box(bm, 0, 0.004, 0.0, 0.006, 0.006, 0.035)
obj_from_bm("TargetPost", bm, M["dark"], C_tgt)
bm = bmesh.new(); add_box(bm, 0, 0.0, 0.008, 0.03, 0.005, 0.025)      # face towards -Y (player)
obj_from_bm("TargetFace", bm, M["target"], C_tgt)

# ---------------------------------------------------------------- DRAIN (apron trough cover)
C_drn = collection("drain")
bm = bmesh.new()
w = 2 * (FLIP_PIVOT_DX - FLIP_R0 - 0.004) - WALL_T      # fits between the apron walls
add_box(bm, 0, -0.012, 0.0, w, 0.004, 0.015)             # low lip, front at y=-0.014
obj_from_bm("DrainLip", bm, M["dark"], C_drn)

# ---------------------------------------------------------------- save + export
os.makedirs(MODELS, exist_ok=True); os.makedirs(BLEND, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BLEND, "labrynth_models.blend"), compress=True)

EXPORTS = {"table": C_table, "flipper": C_flip, "ball": C_ball, "bumper": C_bump,
           "plunger": C_plng, "slingshot_left": C_sl, "slingshot_right": C_sr,
           "target": C_tgt, "drain": C_drn}
for fname, coll in EXPORTS.items():
    bpy.ops.object.select_all(action='DESELECT')
    for o in coll.objects: o.select_set(True)
    bpy.context.view_layer.objects.active = coll.objects[0]
    bpy.ops.export_scene.gltf(filepath=os.path.join(MODELS, fname + ".glb"),
                              export_format='GLB', use_selection=True,
                              export_apply=True, export_yup=True,
                              export_extras=False, export_lights=False, export_cameras=False)
    dims = [0, 0, 0]
    meshes = [o for o in coll.objects if o.type == 'MESH']
    if meshes:
        lo = [min(min((o.matrix_world @ Vector(c))[i] for c in o.bound_box) for o in meshes) for i in range(3)]
        hi = [max(max((o.matrix_world @ Vector(c))[i] for c in o.bound_box) for o in meshes) for i in range(3)]
        # Godot size (x, y, z) = Blender (x, z, y)
        dims = [round(hi[0] - lo[0], 4), round(hi[2] - lo[2], 4), round(hi[1] - lo[1], 4)]
    layout.setdefault("_model_sizes_godot_xyz_m", {})[fname] = dims
    print("exported", fname, dims)

with open(os.path.join(MODELS, "layout.json"), "w") as f:
    json.dump({"units": "metres", "coords": "Godot (Y-up), table.glb origin at playfield centre, surface y=0; "
               "far/top end of table is -Z, player/flippers at +Z", **layout}, f, indent=2)

# ---------------------------------------------------------------- preview render (not saved to .blend)
if PREVIEW:
    from mathutils import Matrix
    def dup(coll, loc, rz=0.0, scale=1.0):
        R = Matrix.Rotation(rz, 4, 'Z')
        for o in coll.objects:
            if o.type != 'MESH': continue
            n = o.copy(); n.data = o.data
            n.matrix_world = Matrix.Translation(loc) @ R @ Matrix.Scale(scale, 4) @ o.matrix_world
            bpy.context.scene.collection.objects.link(n)
    # assembled table
    # flippers shown at their suggested rest angle (tip 30 deg down)
    dup(C_flip, P["Marker_FlipperLeft"][0], math.radians(-30)); dup(C_flip, P["Marker_FlipperRight"][0], math.pi + math.radians(30))
    for i in (1, 2, 3): dup(C_bump, P[f"Marker_Bumper{i}"][0])
    dup(C_sl, P["Marker_SlingshotLeft"][0]); dup(C_sr, P["Marker_SlingshotRight"][0])
    dup(C_tgt, P["Marker_Target1"][0]); dup(C_tgt, P["Marker_Target2"][0])
    dup(C_plng, P["Marker_Plunger"][0]); dup(C_ball, P["Marker_BallSpawn"][0])
    dup(C_ball, (PLAY_CX + 0.02, -0.1, BALL_R)); dup(C_drn, P["Marker_Drain"][0])
    # hide originals except table; line up individual models (scaled x3) beside the table
    for c in EXPORTS.values():
        if c is not C_table: c.hide_render = True
    lineup = (C_flip, C_ball, C_bump, C_plng, C_sl, C_sr, C_tgt, C_drn)
    for i, c in enumerate(lineup):            # 2 columns x 4 rows, scaled x2.5
        x = 0.50 + 0.30 * (i % 2); y = 0.36 - 0.26 * (i // 2)
        dup(c, (x, y, 0), 0.0, 2.5)
    sc = bpy.context.scene
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    sc.collection.objects.link(cam); sc.camera = cam
    cam.location = (0.3, -1.35, 1.45)
    cam.rotation_euler = (math.radians(45), 0, 0)
    cam.data.lens = 30
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", 'SUN'))
    sun.data.energy = 3; sun.rotation_euler = (math.radians(40), math.radians(20), math.radians(30))
    sc.collection.objects.link(sun)
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.light = 'STUDIO'
    sc.display.shading.color_type = 'MATERIAL'
    sc.display.shading.show_shadows = True
    sc.display.shading.show_cavity = True
    sc.display.shading.show_object_outline = True
    sc.render.resolution_x, sc.render.resolution_y = 1600, 1200
    sc.render.film_transparent = False
    sc.world = bpy.data.worlds.new("W"); sc.world.color = (0.2, 0.2, 0.22)
    sc.render.filepath = PREVIEW
    bpy.ops.render.render(write_still=True)
    print("preview written", PREVIEW)
