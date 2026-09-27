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
# Wide "landscape-friendly" table: 1.16 m x 1.00 m (was 0.60 x 1.10) so it fills a
# 16:9 phone screen when viewed from the player end.
TABLE_W, TABLE_L = 1.16, 1.00          # outer size (m)
SX = TABLE_W / 1.00                     # x-spread factor for layout designed at 1.0 m width
FLOOR_T = 0.02                          # floor thickness (below z=0)
WALL_H, WALL_T = 0.05, 0.012            # wall height / thickness
BALL_R = 0.0135                         # 27 mm ball (real pinball size)
HX, HY = TABLE_W / 2, TABLE_L / 2
INNER_X = HX - WALL_T                   # inner face of outer walls (x)
INNER_Y = HY - WALL_T                   # inner face of top/bottom walls (y)
LANE_W = 0.037                          # plunger lane inner width
LANE_WALL_X = INNER_X - LANE_W - WALL_T / 2   # plunger lane separator (centre line)
LANE_CX = (LANE_WALL_X + WALL_T / 2 + INNER_X) / 2   # plunger lane centre
PLAY_CX = (-INNER_X + LANE_WALL_X - WALL_T / 2) / 2  # playfield centre x
LANE_TOP_Y = 0.28                       # top end of the lane separator
CHAMFER = 0.15                          # top corner chamfer size (deflects the launch)
FLIP_LEN, FLIP_R0, FLIP_R1, FLIP_H = 0.085, 0.013, 0.007, 0.025   # flipper (was 0.07 long)
FLIP_REST_DEG = 30.0                    # rest angle (tip down)
FLIP_GAP = 0.033                        # gap between flipper tips at rest (ball = 0.027)
FLIP_PIVOT_DX = FLIP_LEN * math.cos(math.radians(FLIP_REST_DEG)) + FLIP_R1 + FLIP_GAP / 2
FLIP_PIVOT_Y = -0.38
GUIDE_TOP_Y = -0.08                     # where the inlane guides meet the side walls
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
    # ball: only partly metallic so it stays bright without an environment map
    "ball":   mat("BallSteel", (0.88, 0.88, 0.92), metal=0.35, rough=0.25),
    "apron":  mat("ApronDark", (0.16, 0.13, 0.22), rough=0.7),
    "flip":   mat("FlipperWhite", (0.95, 0.95, 0.95), rough=0.4),
    "rubber": mat("RubberRed", (0.85, 0.10, 0.10), rough=0.8),
    "cap":    mat("BumperCap", (1.0, 0.85, 0.15), rough=0.3, emit=(0.6, 0.45, 0.05)),
    "dark":   mat("DarkPlastic", (0.08, 0.08, 0.10), rough=0.5),
    "target": mat("TargetGreen", (0.15, 0.85, 0.25), rough=0.4, emit=(0.05, 0.3, 0.08)),
}
layout = {}

# ---------------------------------------------------------------- TABLE
C_table = collection("table")
colliders = {"note": "Godot XZ (table-local), metres. Segments are boxes from p0 to p1 "
             "(thickness t, height h, extended by t at the ends); pockets are convex prisms.",
             "segments": [], "pockets": []}

def gxz(p):  # Blender XY -> Godot XZ
    return [round(p[0], 4), round(-p[1], 4)]

def seg(bm, group, p0, p1, h=WALL_H, t=WALL_T, extend=True, col_t=None, col_shift=0.0):
    """Visual wall + matching collider entry. col_t/col_shift let outer walls get a
    thicker collider that grows outward (away from the playfield) to stop tunnelling."""
    add_wall(bm, p0, p1, h=h, t=t, extend=extend)
    ct = col_t or t
    d = Vector(p1) - Vector(p0); n = Vector((d.y, -d.x)).normalized() * col_shift   # right-hand normal = outward for outer walls
    q0, q1 = Vector(p0) + n, Vector(p1) + n
    colliders["segments"].append({"group": group, "p0": gxz(q0), "p1": gxz(q1), "t": round(ct, 4),
                                  "h": round(h, 4), "extend": extend})

bm = bmesh.new()
add_box(bm, 0, 0, -FLOOR_T, TABLE_W, TABLE_L, FLOOR_T)
obj_from_bm("Floor", bm, M["floor"], C_table)
colliders["floor"] = {"size": [TABLE_W + 0.02, FLOOR_T, TABLE_L + 0.02], "y": -FLOOR_T / 2}
colliders["glass_height"] = 0.065   # low glass: ball (27 mm) cannot hop the 40-50 mm walls

# outer walls (angled top corners). Colliders are 4 cm thick, growing outward.
bm = bmesh.new()
cx_ = HX - WALL_T / 2; cy_ = HY - WALL_T / 2; K = CHAMFER
OT, OS = 0.04, (0.04 - WALL_T) / 2
seg(bm, "outer", (-cx_, cy_ - K), (-cx_, -cy_), col_t=OT, col_shift=OS)     # left
seg(bm, "outer", (cx_, -cy_), (cx_, cy_ - K), col_t=OT, col_shift=OS)       # right
seg(bm, "outer", (cx_ - K, cy_), (-cx_ + K, cy_), col_t=OT, col_shift=OS)   # top
seg(bm, "outer", (-cx_, -cy_), (cx_, -cy_), col_t=OT, col_shift=OS)         # bottom
seg(bm, "outer", (-cx_ + K, cy_), (-cx_, cy_ - K), extend=False, col_t=OT, col_shift=OS)  # top-left chamfer
seg(bm, "outer", (cx_, cy_ - K), (cx_ - K, cy_), extend=False, col_t=OT, col_shift=OS)    # top-right chamfer
obj_from_bm("OuterWalls", bm, M["wall"], C_table)

# plunger lane separator
bm = bmesh.new()
seg(bm, "lane", (LANE_WALL_X, -cy_), (LANE_WALL_X, LANE_TOP_Y), extend=False)
obj_from_bm("PlungerLaneWall", bm, M["wall"], C_table)
colliders["lane_gate"] = {"center": gxz((LANE_WALL_X, LANE_TOP_Y + 0.05)), "size": [0.012, 0.045, 0.10]}

# inlane guides: from the side walls down to the flipper pivots
lp = (PLAY_CX - FLIP_PIVOT_DX, FLIP_PIVOT_Y)
rp = (PLAY_CX + FLIP_PIVOT_DX, FLIP_PIVOT_Y)
left_x = -INNER_X                       # inner face of left wall
right_x = LANE_WALL_X - WALL_T / 2      # inner face of lane wall
gap = FLIP_R0 + 0.004                   # apron walls sit just outside the pivot
# The guide ends just above the pivot, slightly past its crest, so a ball rolling
# off the guide lands on the sloped flipper instead of balancing on top of the
# round pivot (which made it stall there).
GEND_L = (lp[0] + 0.002, lp[1] + FLIP_R0 + 0.009)
GEND_R = (rp[0] - 0.002, rp[1] + FLIP_R0 + 0.009)
def on_guide(p0, p1, x):
    return (x, p0[1] + (p1[1] - p0[1]) * (x - p0[0]) / (p1[0] - p0[0]))
AL = on_guide((left_x, GUIDE_TOP_Y), GEND_L, lp[0] - gap)    # apron wall tops
AR = on_guide((right_x, GUIDE_TOP_Y), GEND_R, rp[0] + gap)
SLING_A_DX = 0.07          # A sits this far (in x) outward from the guide end
SLING_FACE_LEN = 0.16
SLING_FACE_DEG = 55.0      # kicking face angle from horizontal (guide is ~32 deg)
def guide_y_left(x):
    return on_guide((left_x, GUIDE_TOP_Y), GEND_L, x)[1]
_ax = GEND_L[0] - SLING_A_DX
SL_A = (_ax, guide_y_left(_ax))
_a = math.radians(SLING_FACE_DEG)
SL_B = (SL_A[0] - SLING_FACE_LEN * math.cos(_a), SL_A[1] + SLING_FACE_LEN * math.sin(_a))
SL_D = (SL_B[0], guide_y_left(SL_B[0]))
_gs = (GUIDE_TOP_Y - GEND_L[1]) / (GEND_L[0] - left_x)            # guide slope (y per -x)
SL_W = (left_x, SL_B[1] + (SL_B[0] - left_x) * _gs)                 # deflector parallel to guide
def mirror(p):
    return (2 * PLAY_CX - p[0], p[1])
SR_A, SR_B, SR_D, SR_W = (mirror(p) for p in (SL_A, SL_B, SL_D, SL_W))
SR_W = (right_x, SR_W[1])
bm = bmesh.new()
# Visible/colliding guide only from under the slingshot (D) down to the flipper;
# above D it would be buried between two solid fills anyway.
seg(bm, "inlane", SL_D, GEND_L, t=0.014, extend=False)
seg(bm, "inlane", SR_D, GEND_R, t=0.014, extend=False)
# apron walls closing the area under the guides
seg(bm, "inlane", AL, (AL[0], -INNER_Y), t=0.014)
seg(bm, "inlane", AR, (AR[0], -INNER_Y), t=0.014)
obj_from_bm("InlaneGuides", bm, M["guide"], C_table)
# solid pocket fills behind the guides (not rendered; physics only)
e = 0.006
POCKET_L = [(left_x, GUIDE_TOP_Y), (left_x, -INNER_Y), (AL[0], -INNER_Y), AL]
POCKET_R = [(right_x, GUIDE_TOP_Y), (right_x, -INNER_Y), (AR[0], -INNER_Y), AR]
colliders["pockets"] = [
    [gxz(p) for p in [(left_x - e, GUIDE_TOP_Y - e), (left_x - e, -INNER_Y - e),
                      (AL[0] - e, -INNER_Y - e), (AL[0] - e, AL[1] - e)]],
    [gxz(p) for p in [(right_x, GUIDE_TOP_Y - e), (right_x, -INNER_Y - e),
                      (AR[0] + e, -INNER_Y - e), (AR[0] + e, AR[1] - e)]],
]

# ---- slingshots: sit ON the inlane guide, no gaps --------------------------
# Left side (right is mirrored about the playfield centre line x = PLAY_CX):
#   A = bottom point, on the guide just above the flipper
#   B = top point, up and outward, 0.16 m from A along the kicking face
#   D = point on the guide directly below B
# Triangle A-B-D is the slingshot body (back edge A-D flush on the guide), the
# rubber kicking face A-B faces the table centre. Above it a deflector wall runs
# from B up to the side wall (W), and the space W-B-D-guide top is a solid fill,
# so the playfield boundary wall -> W -> B -> A -> flipper only ever descends
# toward the flipper: there is no corner or pocket where a ball can come to rest.
SLING_T = 0.012
bm = bmesh.new()
for (b_, w_, sgn) in ((SL_B, SL_W, 1), (SR_B, SR_W, -1)):
    # shift the deflector wall into the fill by t/2 so its face passes exactly through B
    d_ = Vector(w_) - Vector(b_); n_ = Vector((d_.y, -d_.x)).normalized() * (SLING_T / 2) * sgn
    seg(bm, "deflector", tuple(Vector(b_) - n_), tuple(Vector(w_) - n_), t=SLING_T, extend=False)
obj_from_bm("SlingDeflectors", bm, M["guide"], C_table)
e2 = 0.004
colliders["pockets"] += [
    [gxz(p) for p in [(left_x - e2, GUIDE_TOP_Y), (left_x - e2, SL_W[1]), SL_B, SL_D]],
    [gxz(p) for p in [(right_x, GUIDE_TOP_Y), (right_x, SR_W[1]), SR_B, SR_D]],
]
SLING_FILL_L = [(left_x, GUIDE_TOP_Y), SL_W, SL_B, SL_D]
SLING_FILL_R = [(right_x, GUIDE_TOP_Y), SR_W, SR_B, SR_D]
def centroid(pts):
    return (sum(p[0] for p in pts) / 3, sum(p[1] for p in pts) / 3)
SL_C = centroid((SL_A, SL_B, SL_D)); SR_C = centroid((SR_A, SR_B, SR_D))
def kick_dir(a_, b_, sgn):
    f = Vector(b_) - Vector(a_); n = Vector((-f.y, f.x)).normalized() * -sgn   # inward normal
    return [round(n.x, 4), 0.0, round(-n.y, 4)]                               # Godot XZ
layout["slingshots"] = {
    "Marker_SlingshotLeft": {"kick_dir": kick_dir(SL_A, SL_B, 1),
                             "face": [gxz(SL_A), gxz(SL_B)], "deflector": [gxz(SL_B), gxz(SL_W)]},
    "Marker_SlingshotRight": {"kick_dir": kick_dir(SR_A, SR_B, -1),
                              "face": [gxz(SR_A), gxz(SR_B)], "deflector": [gxz(SR_B), gxz(SR_W)]},
}

# raised apron plates over the dead pockets behind the guides (visual cue that
# these areas are out of play; physics uses the pocket colliders above)
bm = bmesh.new()
for poly in (POCKET_L, POCKET_R, SLING_FILL_L, SLING_FILL_R):
    prism(bm, poly, 0.0, 0.03)
obj_from_bm("ApronPlates", bm, M["apron"], C_table)

# labyrinth wall segments across the wide upper playfield (all gaps >= 4 cm, ball 2.7 cm)
c = PLAY_CX
def X(x):  # x designed for a 1.0 m table -> spread across the actual width
    return c + (x - c) * SX
maze_1m = [
    # no perfectly horizontal tops: every ledge slopes (~15 deg) so balls roll off
    ((-0.40, 0.14), (-0.40, 0.30)), ((-0.40, 0.30), (-0.29, 0.27)),      # upper-left L
    ((0.33, 0.14), (0.33, 0.30)),   ((0.33, 0.30), (0.22, 0.27)),        # upper-right L
    ((c - 0.06, 0.32), (c, 0.34)), ((c, 0.34), (c + 0.06, 0.32)),        # top centre roof (^)
    ((c, 0.34), (c, 0.30)),                                               # stem
    ((-0.25, 0.10), (-0.23, 0.20)), ((0.20, 0.10), (0.18, 0.20)),        # inner pillars (leaning: no flat cap to balance on)
    ((-0.44, 0.08), (-0.375, 0.06)), ((0.39, 0.08), (0.326, 0.06)),     # side stubs, sloped toward the centre
    ((c - 0.20, -0.02), (c - 0.14, 0.02)), ((c + 0.20, -0.02), (c + 0.14, 0.02)),  # mid chevrons
]
maze = [((X(a_[0]), a_[1]), (X(b_[0]), b_[1])) for a_, b_ in maze_1m]
bm = bmesh.new()
for a_, b_ in maze: seg(bm, "maze", a_, b_, h=0.04, t=0.01)
obj_from_bm("MazeWalls", bm, M["maze"], C_table)

# stand-up targets flush against the top wall: back of the target touches the wall,
# so there is no ledge behind it where a ball could come to rest
TARGET_Y = INNER_Y - 0.007

# placement markers (exported as Node3D in the glb)
P = {
    "Marker_FlipperLeft":  ((lp[0], lp[1], 0), 0.0),
    "Marker_FlipperRight": ((rp[0], rp[1], 0), math.pi),
    "Marker_Plunger":      ((LANE_CX, -0.44, 0), 0.0),
    "Marker_BallSpawn":    ((LANE_CX, -0.44 + BALL_R + 0.002, BALL_R), 0.0),
    "Marker_Bumper1":      ((X(c - 0.09), 0.12, 0), 0.0),
    "Marker_Bumper2":      ((X(c + 0.09), 0.12, 0), 0.0),
    "Marker_Bumper3":      ((c, 0.22, 0), 0.0),
    "Marker_Bumper4":      ((X(c - 0.30), 0.04, 0), 0.0),
    "Marker_Bumper5":      ((X(c + 0.28), 0.04, 0), 0.0),
    "Marker_SlingshotLeft":  ((SL_C[0], SL_C[1], 0), 0.0),    # triangle centroid
    "Marker_SlingshotRight": ((SR_C[0], SR_C[1], 0), 0.0),
    "Marker_Target1":      ((X(-0.30), TARGET_Y, 0), 0.0),
    "Marker_Target2":      ((X(-0.16), TARGET_Y, 0), 0.0),
    "Marker_Target3":      ((X(0.09), TARGET_Y, 0), 0.0),
    "Marker_Target4":      ((X(0.23), TARGET_Y, 0), 0.0),
    "Marker_Drain":        ((c, -0.45, 0), 0.0),
}
for n, (loc, rz) in P.items():
    empty(n, loc, C_table, rz)
    x, y, z = loc
    layout[n] = {"godot_position": [round(x, 4), round(z, 4), round(-y, 4)],
                 "godot_rotation_y_deg": round(math.degrees(rz), 1)}
layout["table"] = {"width": TABLE_W, "length": TABLE_L, "inner_half_x": round(INNER_X, 4),
                   "inner_half_z": round(INNER_Y, 4), "playfield_center_x": round(PLAY_CX, 4),
                   "lane_center_x": round(LANE_CX, 4), "lane_wall_x": round(LANE_WALL_X, 4),
                   "flipper_length": FLIP_LEN, "flipper_tip_gap": FLIP_GAP}
layout["colliders"] = colliders

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
obj_from_bm("Ball", bm, M["ball"], C_ball, smooth=True)

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
def slingshot(name, tri_world, cen, sign):
    """Body = triangle A-B-D (world coords from the table layout) re-centred on its
    centroid; red rubber strip on the kicking face A-B (facing the table centre)."""
    C = collection(name)
    tri = [(x - cen[0], y - cen[1]) for x, y in tri_world]
    bm = bmesh.new(); prism(bm, tri, 0.0, 0.035)
    obj_from_bm(name.title().replace("_", "") + "Body", bm, M["guide"], C)
    a_, b_ = Vector((*tri[0], 0)), Vector((*tri[1], 0))
    f = (b_ - a_).normalized(); n = Vector((-f.y, f.x, 0)) * -sign        # inward normal
    bm = bmesh.new(); add_wall(bm, a_ + f * 0.004, b_ - f * 0.004, h=0.03, t=0.006, extend=False)
    bmesh.ops.translate(bm, verts=bm.verts, vec=n * 0.003 + Vector((0, 0, 0.003)))
    obj_from_bm(name.title().replace("_", "") + "Kicker", bm, M["rubber"], C)
    return C
C_sl = slingshot("slingshot_left", (SL_A, SL_B, SL_D), SL_C, 1)
C_sr = slingshot("slingshot_right", (SR_A, SR_B, SR_D), SR_C, -1)

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
               "far/top end of table is -Z, player/flippers at +Z", **layout}, f, indent=1)

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
    dup(C_flip, P["Marker_FlipperLeft"][0], math.radians(-FLIP_REST_DEG)); dup(C_flip, P["Marker_FlipperRight"][0], math.pi + math.radians(FLIP_REST_DEG))
    for k in P:
        if k.startswith("Marker_Bumper"): dup(C_bump, P[k][0])
        if k.startswith("Marker_Target"): dup(C_tgt, P[k][0])
    dup(C_sl, P["Marker_SlingshotLeft"][0]); dup(C_sr, P["Marker_SlingshotRight"][0])
    dup(C_plng, P["Marker_Plunger"][0]); dup(C_ball, P["Marker_BallSpawn"][0])
    dup(C_ball, (PLAY_CX + 0.02, -0.1, BALL_R)); dup(C_drn, P["Marker_Drain"][0])
    # hide originals except table; line up individual models (scaled x3) beside the table
    for c in EXPORTS.values():
        if c is not C_table: c.hide_render = True
    lineup = (C_flip, C_ball, C_bump, C_plng, C_sl, C_sr, C_tgt, C_drn)
    for i, c in enumerate(lineup):            # 2 columns x 4 rows, scaled x2.5
        x = 0.72 + 0.30 * (i % 2); y = 0.36 - 0.26 * (i // 2)
        dup(c, (x, y, 0), 0.0, 2.5)
    sc = bpy.context.scene
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    sc.collection.objects.link(cam); sc.camera = cam
    cam.location = (0.35, -1.45, 1.65)
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
