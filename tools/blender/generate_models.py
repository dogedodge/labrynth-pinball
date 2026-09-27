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
# Narrow portrait table (0.60 m x 1.10 m, playfield 0.527 m ~ a real 514 mm table),
# made to fill a portrait phone screen viewed from the player end.
TABLE_W, TABLE_L = 0.60, 1.10          # outer size (m)
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
CHAMFER = 0.09                          # top corner chamfer size (deflects the launch)
FLIP_LEN, FLIP_R0, FLIP_R1, FLIP_H = 0.085, 0.013, 0.007, 0.025   # flipper (was 0.07 long)
FLIP_REST_DEG = 30.0                    # rest angle (tip down)
FLIP_GAP = 0.033                        # gap between flipper tips at rest (ball = 0.027)
FLIP_PIVOT_DX = FLIP_LEN * math.cos(math.radians(FLIP_REST_DEG)) + FLIP_R1 + FLIP_GAP / 2
FLIP_PIVOT_Y = -0.43
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
    "apron":  mat("DeadBlock", (0.30, 0.26, 0.36), rough=0.8),
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

# ---- lower playfield: real-pinball style outlane / inlane / slingshot -------
# Built for the LEFT side in x relative to the playfield centre (xr), mirrored
# exactly for the right side. From the side inward:
#   side wall      : outer wall of the outlane (table wall / plunger lane wall)
#   outlane        : 36 mm wide lane straight down to its own drain (real: 35 mm)
#   inlane guide   : thin rail, vertical, then bends and runs down to the flipper
#                    pivot (round post on its top end)
#   inlane         : 34 mm return lane between guide and slingshot (real: 33 mm)
#   slingshot      : triangle above the flipper: outer edge parallel to the inlane,
#                    bottom edge parallel to the angled guide (just above the
#                    flipper), long rubber hypotenuse facing the table centre
# The area under each angled guide is solid (raised block), everything else is playable.
lp = (PLAY_CX - FLIP_PIVOT_DX, FLIP_PIVOT_Y)
rp = (PLAY_CX + FLIP_PIVOT_DX, FLIP_PIVOT_Y)
left_x = -INNER_X                       # inner face of left table wall
right_x = LANE_WALL_X - WALL_T / 2      # inner face of lane wall (right "side wall")
HALF = right_x - PLAY_CX                # = PLAY_CX - left_x (symmetric)
RAIL_T = 0.010                          # inlane guide rail thickness
OUTLANE_W, INLANE_W = 0.036, 0.034
GUIDE_XR = -(HALF - OUTLANE_W - RAIL_T / 2)    # guide centre line
GUIDE_TOP = -0.15                       # top of the inlane guide (post)
GUIDE_BEND = -0.31                      # guide turns toward the flipper here
POST_R = 0.008
gap = FLIP_R0 + 0.004                   # apron walls sit just outside the pivot
# guide ends just above the pivot, slightly past its crest (ball lands on the flipper)
GEND_XR = (lp[0] - PLAY_CX) + 0.002
GEND_Y = FLIP_PIVOT_Y + FLIP_R0 + 0.009
g_slope = (GEND_Y - GUIDE_BEND) / (GEND_XR - GUIDE_XR)           # dy/dx of angled guide
def gy(xr):                             # angled guide centre line
    return GUIDE_BEND + (xr - GUIDE_XR) * g_slope
APRON_XR = (lp[0] - PLAY_CX) - gap
SLING_OUT_XR = GUIDE_XR + RAIL_T / 2 + INLANE_W                    # sling outer edge
_off = (RAIL_T / 2 + INLANE_W) / math.cos(math.atan(-g_slope))     # vertical offset of bottom edge
SLING_BI_XR = -0.07                     # bottom-inner point (above the flipper)
SLING_TOP_Y = -0.20
L = {  # left-side key points (xr, y)
    "G_TOP": (GUIDE_XR, GUIDE_TOP), "G_BEND": (GUIDE_XR, GUIDE_BEND), "G_END": (GEND_XR, GEND_Y),
    "G_BOT": (GUIDE_XR, -INNER_Y), "A_TOP": (APRON_XR, gy(APRON_XR)), "A_BOT": (APRON_XR, -INNER_Y),
    "S_BI": (SLING_BI_XR, gy(SLING_BI_XR) + _off), "S_BO": (SLING_OUT_XR, gy(SLING_OUT_XR) + _off),
    "S_T": (SLING_OUT_XR, SLING_TOP_Y),
}
def Lp(k): return (PLAY_CX + L[k][0], L[k][1])
def Rp(k): return (PLAY_CX - L[k][0], L[k][1])

bm = bmesh.new()      # inlane guide rails, outlane inner walls, apron walls
for P_ in (Lp, Rp):
    seg(bm, "inlane", P_("G_TOP"), P_("G_BEND"), t=RAIL_T)
    seg(bm, "inlane", P_("G_BEND"), P_("G_END"), t=RAIL_T, extend=False)
    seg(bm, "inlane", P_("G_BEND"), P_("G_BOT"), t=RAIL_T)
    # apron wall: starts just below the guide rail (must not poke up into the inlane exit)
    seg(bm, "inlane", (P_("A_TOP")[0], P_("A_TOP")[1] - RAIL_T / 2), P_("A_BOT"), t=0.014, extend=False)
    add_cyl(bm, *P_("G_TOP"), 0.0, POST_R, WALL_H, seg=12)       # round post on the guide top
obj_from_bm("InlaneGuides", bm, M["guide"], C_table)
colliders["posts"] = [{"center": gxz(P_("G_TOP")), "r": POST_R, "h": WALL_H} for P_ in (Lp, Rp)]

# solid dead areas (colliders) + raised blocks (visual)
DEAD = []
for P_ in (Lp, Rp):
    DEAD.append([P_("G_BEND"), P_("A_TOP"), P_("A_BOT"), P_("G_BOT")])                      # under guide
colliders["pockets"] = [[gxz(p) for p in poly] for poly in DEAD]
bm = bmesh.new()
for poly in DEAD:
    prism(bm, poly, 0.0, WALL_H - 0.004)
obj_from_bm("DeadBlocks", bm, M["apron"], C_table)

# slingshot triangles (body mesh lives in slingshot_*.glb, placed at the centroid)
SL_TRI = (Lp("S_BI"), Lp("S_T"), Lp("S_BO"))      # face = S_BI -> S_T (hypotenuse)
SR_TRI = (Rp("S_BI"), Rp("S_T"), Rp("S_BO"))
def centroid(pts):
    return (sum(p[0] for p in pts) / 3, sum(p[1] for p in pts) / 3)
SL_C = centroid(SL_TRI); SR_C = centroid(SR_TRI)
def kick_dir(a_, b_, sgn):
    f = Vector(b_) - Vector(a_); n = Vector((-f.y, f.x)).normalized() * -sgn   # inward normal
    return [round(n.x, 4), 0.0, round(-n.y, 4)]                               # Godot XZ
def sling_info(tri, sgn):
    return {"kick_dir": kick_dir(tri[0], tri[1], sgn), "face": [gxz(tri[0]), gxz(tri[1])],
            "edges": [[gxz(tri[i]), gxz(tri[(i + 1) % 3])] for i in range(3)]}
layout["slingshots"] = {"Marker_SlingshotLeft": sling_info(SL_TRI, 1),
                        "Marker_SlingshotRight": sling_info(SR_TRI, -1)}
OUTLANE_CX = -(HALF - OUTLANE_W / 2)
INLANE_CX = GUIDE_XR + RAIL_T / 2 + INLANE_W / 2
BOT_Y = -(INNER_Y - 0.048)              # plunger tip / outlane bottom test point
DRAIN_Y = -(INNER_Y - 0.038)
def lane_paths(sgn):   # centre lines of the lanes (Godot XZ), used by the tests
    m = lambda xr, y: gxz((PLAY_CX + sgn * xr, y))
    return {
        "inlane": [m(INLANE_CX, GUIDE_TOP + 0.02), m(INLANE_CX, gy(INLANE_CX) + _off / 2),
                   m(SLING_BI_XR, gy(SLING_BI_XR) + _off / 2)],
        "outlane": [m(OUTLANE_CX, GUIDE_TOP + 0.02), m(OUTLANE_CX, BOT_Y)],
        "guide_x": round(PLAY_CX + sgn * GUIDE_XR, 4),
        "side_wall_x": round(PLAY_CX + sgn * -HALF, 4),
    }
layout["lanes"] = {"left": lane_paths(1), "right": lane_paths(-1)}
layout["drains"] = {
    "Marker_Drain": {"size": [2 * gap + 2 * FLIP_PIVOT_DX - 0.03, 0.04, 0.07], "visual": True},
    "Marker_DrainOutlaneLeft": {"size": [OUTLANE_W, 0.04, 0.07], "visual": False},
    "Marker_DrainOutlaneRight": {"size": [OUTLANE_W, 0.04, 0.07], "visual": False},
}

# labyrinth wall segments in the upper playfield (all gaps >= 5 cm, ball 2.7 cm).
# No perfectly horizontal tops: every ledge slopes (~15 deg) so balls roll off.
c = PLAY_CX
maze = [
    ((-0.23, 0.26), (-0.23, 0.40)), ((-0.23, 0.40), (-0.15, 0.38)),      # upper-left L
    ((0.18, 0.26), (0.18, 0.40)),   ((0.18, 0.40), (0.10, 0.38)),        # upper-right L
    ((c - 0.05, 0.40), (c, 0.415)), ((c, 0.415), (c + 0.05, 0.40)),      # top centre roof (^)
    ((c, 0.415), (c, 0.36)),                                              # stem
    # side deflectors: attached to the side walls, sloping down and inward (~27 deg),
    # so a ball running down a side wall is turned toward the slingshots instead of
    # dropping straight into the outlane
    ((-INNER_X, 0.10), (c - 0.145, 0.04)), ((LANE_WALL_X - WALL_T / 2, 0.10), (c + 0.145, 0.04)),
]
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
    "Marker_Plunger":      ((LANE_CX, BOT_Y, 0), 0.0),
    "Marker_BallSpawn":    ((LANE_CX, BOT_Y + BALL_R + 0.002, BALL_R), 0.0),
    "Marker_Bumper1":      ((c - 0.075, 0.20, 0), 0.0),
    "Marker_Bumper2":      ((c + 0.075, 0.20, 0), 0.0),
    "Marker_Bumper3":      ((c, 0.29, 0), 0.0),
    "Marker_SlingshotLeft":  ((SL_C[0], SL_C[1], 0), 0.0),    # triangle centroid
    "Marker_SlingshotRight": ((SR_C[0], SR_C[1], 0), 0.0),
    "Marker_Target1":      ((-0.12, TARGET_Y, 0), 0.0),
    "Marker_Target2":      ((0.07, TARGET_Y, 0), 0.0),
    "Marker_Drain":        ((c, DRAIN_Y, 0), 0.0),
    "Marker_DrainOutlaneLeft":  ((c + OUTLANE_CX, DRAIN_Y, 0), 0.0),
    "Marker_DrainOutlaneRight": ((c - OUTLANE_CX, DRAIN_Y, 0), 0.0),
}
for n, (loc, rz) in P.items():
    empty(n, loc, C_table, rz)
    x, y, z = loc
    layout[n] = {"godot_position": [round(x, 4), round(z, 4), round(-y, 4)],
                 "godot_rotation_y_deg": round(math.degrees(rz), 1)}
layout["table"] = {"width": TABLE_W, "length": TABLE_L, "inner_half_x": round(INNER_X, 4),
                   "inner_half_z": round(INNER_Y, 4), "playfield_center_x": round(PLAY_CX, 4),
                   "lane_center_x": round(LANE_CX, 4), "lane_wall_x": round(LANE_WALL_X, 4),
                   "flipper_length": FLIP_LEN, "flipper_tip_gap": FLIP_GAP, "chamfer": CHAMFER}
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
    """Body = triangle (S_BI, S_T, S_BO) from the table layout, re-centred on its
    centroid. White plastic body, thick red rubber on the hypotenuse S_BI -> S_T,
    which faces the table centre."""
    C = collection(name)
    tri = [(x - cen[0], y - cen[1]) for x, y in tri_world]
    bm = bmesh.new(); prism(bm, tri, 0.0, 0.035)
    obj_from_bm(name.title().replace("_", "") + "Body", bm, M["flip"], C)
    a_, b_ = Vector((*tri[0], 0)), Vector((*tri[1], 0))
    f = (b_ - a_).normalized(); n = Vector((-f.y, f.x, 0)) * -sign        # inward normal
    # rubber: a 10 mm "stadium" band along the face with rounded ends that wrap the
    # two corners (like a rubber ring around the corner posts), so there is no flat
    # end cap a ball could balance on at the slingshot's top point
    RR = 0.005
    ca, cb = a_ + n * RR, b_ + n * RR
    bm = bmesh.new()
    prism(bm, circle_pts(ca.x, ca.y, RR, 12) + circle_pts(cb.x, cb.y, RR, 12), 0.003, 0.032)
    obj_from_bm(name.title().replace("_", "") + "Kicker", bm, M["rubber"], C)
    bm = bmesh.new()   # chrome post caps at the two rubber corners (visual)
    for cc in (ca, cb):
        add_cyl(bm, cc.x, cc.y, 0.035, 0.0035, 0.004, seg=12)
    obj_from_bm(name.title().replace("_", "") + "Posts", bm, M["chrome"], C)
    return C
C_sl = slingshot("slingshot_left", SL_TRI, SL_C, 1)
C_sr = slingshot("slingshot_right", SR_TRI, SR_C, -1)

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
    for i, c in enumerate(lineup):            # 2 columns x 4 rows, scaled x2
        x = 0.50 + 0.32 * (i % 2); y = 0.44 - 0.32 * (i // 2)
        dup(c, (x, y, 0), 0.0, 1.6)
    sc = bpy.context.scene
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    sc.collection.objects.link(cam); sc.camera = cam
    cam.location = (0.3, -1.40, 1.55)
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
