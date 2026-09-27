# labrynth-pinball

A minimal **Godot 4** pinball game MVP with a light "labyrinth" theme.

- **Engine:** Godot 4.x (developed and verified with **4.7.2**; `project.godot` features target 4.3+)
- **Target:** mobile, **portrait** orientation (720×1280 base; tall 19.5:9 / 20:9 phones and 4:3 tablets supported; desktop works too)
- **Controls:** keyboard plus portrait touch controls (multitouch flipper zones)
- **Models:** built procedurally in **Blender** (script in `tools/blender/`), exported as `.glb`
- **Binary assets** (`.glb`, `.blend`, images, audio, fonts, …) are stored with **Git LFS** — run `git lfs install` and `git lfs pull` so the real models are present.

![assembled models](docs/preview.png)

![gameplay](docs/gameplay.png)

## How to run

1. Install [Godot 4.x](https://godotengine.org/download) (4.7.2 matches the author) and [Git LFS](https://git-lfs.com/).
2. From the repo root:

```sh
git lfs pull
godot --path .          # or open this folder in the Godot editor and press Play
```

Headless checks (import, smoke test, whole-table rest test):

```sh
godot --headless --path . --import
godot --headless --path . -- --smoke-test
godot --headless --path . -s tools/rest_grid_test.gd
# or everything at once (set GODOT=/path/to/godot if needed):
tools/verify.sh
```

The smoke test launches the ball (weak / medium / full power must all reach the playfield), checks the
flippers, fires max-speed (12 m/s) shots at the walls, guide rails and chamfer (no tunnelling), checks that
the plunger lane and all inlanes/outlanes are clear for a ball, drops balls around the slingshots (none may
come to rest) and rolls a ball down every inlane (must reach the flippers) and outlane (must drain).
`tools/rest_grid_test.gd` drops ~290 balls on a 35 mm grid over the whole playfield and fails if any comes
to rest above the flippers.

Capture a PNG of the running game (writes `docs/gameplay.png` by default; `--resolution` picks the phone size):

```sh
godot --path . --resolution 720x1280 -- --screenshot
godot --path . --resolution 1080x2400 -- --screenshot=/tmp/20x9.png
```

Diagnostic renders (need a display, e.g. `xvfb-run`): top-down orthographic view (optionally cropped to the
lower playfield) and slingshot close-ups, with the rubber faces magenta and the kick directions as cyan arrows:

```sh
godot --path . --resolution 720x1280 -s tools/diag_render.gd -- --mode=top --crop_top=0.45 --out=/tmp/top.png
godot --path . --resolution 720x1280 -s tools/diag_render.gd -- --mode=close --side=left --out=/tmp/close.png
```

## Controls

Keyboard and touch both drive the same Input Map actions, so they can be mixed.

Portrait touch layout (multitouch; semi-transparent, nothing covers the playfield except the LAUNCH button
over the plunger lane on 16:9 screens):

- **Left / right flipper:** tap anywhere on the **left / right half** of the screen below the top bar.
  Both halves can be held at once; sliding a finger across the middle switches flippers.
  (Only a faint "LEFT FLIPPER / RIGHT FLIPPER" hint is drawn at the bottom edge.)
- **LAUNCH:** button in the bottom-right corner (right thumb), over the plunger. Hold to charge, release to shoot.
- **PAUSE** (top-left) and **RESTART** (top-right) are small buttons in the top bar; score and balls sit
  between them.

| Action | Keyboard | Touch |
|---|---|---|
| Left flipper | Left, Z, A, `,` | left half of the screen |
| Right flipper | Right, M, D, `/` | right half of the screen |
| Charge / release plunger | Space or Down (hold to charge, release to shoot) | **LAUNCH** (bottom-right) |
| Pause | Esc or P | **PAUSE** (top-left) |
| Restart | R or Enter | **RESTART** (top-right) |

## Gameplay

- 3 balls per game. The ball starts in the plunger lane; charge and release to launch.
- Pop bumpers **100**, slingshots **10**, stand-up targets **500**.
- Drain between the flippers, or down either outlane, loses a ball. After the last ball, Game Over — press Restart.
- There is no extra ball / ball-save in this MVP.

## Project structure

```
scenes/main.tscn       main scene (world + HUD + touch + overlays)
scripts/               gameplay (world assembly, camera fit, ball, flippers, plunger, gadgets, touch UI)
ui/                    HUD / touch / overlay packed scenes
assets/models/         .glb models (one per piece) + layout.json (suggested placements)
assets/blender/        labrynth_models.blend (source, one collection per model)
tools/blender/         generate_models.py (reproducible generator)
tools/verify.sh        headless import + smoke test + rest grid test
tools/rest_grid_test.gd  whole-table "no resting spot" test
tools/diag_render.gd   top-down / close-up diagnostic renders
docs/                  preview + gameplay screenshots
```

The table is assembled at runtime from `assets/models/*.glb` and `layout.json` marker positions. The playfield is tilted **6.5°** about X (top / −Z raised). Physics uses **Jolt**, **180 Hz** ticks, and **continuous collision detection** on the ball (real 27 mm scale).

The camera looks down the table from the player end (66° below the playfield plane, 30° FOV) and is
**auto-framed** on every viewport resize: the whole table (outer walls included) is fitted into the screen
below the top HUD bar, as large as possible. On 9:16 it fills the width and almost the full height; on tall
phones (20:9) it fills the width and the spare height goes mostly below the table (launch button area); on
4:3 tablets it fills the height. `project.godot` uses a 720×1280 portrait base with `canvas_items` / `expand`
stretch, so the UI never crops.

Launch is a charged velocity impulse (the plunger mesh is animated visually). All static table colliders are
primitives generated from `layout.json` (see below). No audio in this MVP. Headless runs may log a missing ALSA device and fall back to the dummy audio driver.

Regenerate all models (from repo root):

```sh
blender -b --factory-startup --python tools/blender/generate_models.py -- --preview docs/preview.png
```

## Models

**Scale:** 1 unit = **1 metre**, real-world-ish pinball proportions. Table is 0.60 m wide × 1.10 m long;
ball is a real 27 mm ball.

**Axes (Godot, Y-up, as imported from the glb):**
- playfield surface is at **y = 0**
- the **far/top** end of the table (bumpers, maze) is **−Z**
- the **player end** (flippers, drain, plunger) is **+Z**
- plunger lane is on the **right** (+X)
- the table is modelled flat — this project tilts the playfield ~6.5° about X (top end up).

| File | Size (x × y × z, m) | Origin / pivot | Notes |
|---|---|---|---|
| `table.glb` | 0.60 × 0.07 × 1.10 | centre of the playfield **surface** (floor top, y=0) | Child meshes: `Floor` (0.02 m thick, below y=0), `OuterWalls` (0.05 m high, 12 mm thick, 0.09 m chamfered top corners), `PlungerLaneWall`, `InlaneGuides` (inlane guide rails with a round post on top, angled to end just above each flipper pivot, outlane inner walls and apron walls), `DeadBlocks` (raised solid blocks under the angled guides — no open pockets), `MazeWalls` (labyrinth segments + side deflectors, 0.04 m high; every top edge slopes so nothing is a ledge). Also contains `Marker_*` Node3D placement markers (see below). |
| `flipper.glb` | 0.108 × 0.029 × 0.029 | **pivot axis** centre, at floor level | Bat points along **+X** (length **0.085 m** pivot→tip centre, pivot radius 13 mm, tip radius 7 mm, height 25 mm). Use as **left** flipper directly; for the **right** flipper rotate 180° about Y. Angles: left rest `−30°`, up `+30°`; right rest `210°`, up `150°`. Tip gap at rest: **33 mm** (ball 27 mm). |
| `ball.glb` | Ø 0.027 | sphere centre | Radius **0.0135 m**. Place centre at y = 0.0135 to rest on the floor. |
| `bumper.glb` | Ø 0.06 × 0.043 | base centre at floor level (y=0) | Round pop bumper: dark base, red skirt (radius 0.024), yellow emissive cap (radius 0.03). |
| `plunger.glb` | 0.03 × 0.022 × 0.097 | centre of the plunger head's **front face**, floor level | Head faces **−Z** (up the lane); rod + knob extend toward +Z past the bottom wall (intended). |
| `slingshot_left.glb` / `slingshot_right.glb` | 0.1235 × 0.039 × 0.1881 | triangle centroid at floor level | Real-pinball slingshot above each flipper: outer edge runs alongside the inlane (34 mm from the guide), bottom edge parallel to the angled inlane guide just above the flipper, and the long red rubber **kicking face** (hypotenuse, 0.21 m, ~32° from the table axis) faces the table centre, sloping up and outward from just above the flipper tip. The 10 mm rubber band has rounded ends wrapping the two corner posts (chrome caps). Only hits on the rubber face kick (perpendicular to it, inward/up: left (0.843, 0, −0.537), right mirrored); the other edges are passive. Kick direction, face and edges are in `layout.json` → `slingshots`. Exact mirrors. |
| `target.glb` | 0.03 × 0.035 × 0.0095 | base centre at floor level | Stand-up target; green face points toward the player (+Z). Placed flush against the top wall. |
| `drain.glb` | 0.1482 × 0.015 × 0.004 | centre of lip, floor level | Decorative lip between the apron walls below the flippers; the centre drain Area3D sits here. The two outlanes have their own (invisible) drain Area3Ds at `Marker_DrainOutlaneLeft/Right`. |

All materials are simple Principled BSDF colours (no textures) → import as `StandardMaterial3D`. Low poly (≤ 20-segment cylinders, 16×10 ball).

### Placement markers (`table.glb` → `Marker_*` nodes; also in `assets/models/layout.json`)

Positions are Godot coordinates relative to the table origin (metres).

| Marker | Position (x, y, z) | rot Y |
|---|---|---|
| Marker_FlipperLeft | (−0.1216, 0, 0.43) | 0° |
| Marker_FlipperRight | (0.0726, 0, 0.43) | 180° |
| Marker_Plunger | (0.2695, 0, 0.49) | – |
| Marker_BallSpawn | (0.2695, 0.0135, 0.4745) | – |
| Marker_Bumper1 / 2 / 3 | (−0.0995, 0, −0.20) / (0.0505, 0, −0.20) / (−0.0245, 0, −0.29) | – |
| Marker_SlingshotLeft / Right (triangle centroid) | (−0.1702, 0, 0.2896) / (0.1212, 0, 0.2896) | – |
| Marker_Target1 / 2 (back flush on the top wall) | (−0.12, 0, −0.531) / (0.07, 0, −0.531) | – |
| Marker_Drain | (−0.0245, 0, 0.50) | – |
| Marker_DrainOutlaneLeft / Right | (−0.27, 0, 0.50) / (0.221, 0, 0.50) | – |

Playfield centre line (between the flippers) is x = −0.0245; plunger lane centre x = 0.2695 (lane wall at x = 0.245,
inner width 37 mm). A ball launched up the lane hits the chamfered top-right corner and is deflected left across the top.

Lower playfield (each side, from the wall inward, mirrored about x = −0.0245): side wall (table wall / plunger-lane
wall) → **outlane** (36 mm, drains) → **inlane guide rail** (10 mm, post on top at z = 0.15, bends at z = 0.31 and
angles down to just above the flipper pivot) → **inlane** (34 mm, feeds the flipper) → **slingshot** above the
flipper. Side deflectors on both walls (z ≈ −0.10 → −0.04) turn balls running down a wall toward the slingshots
instead of straight into an outlane. `layout.json` → `lanes` has the inlane/outlane centreline paths, guide and
side-wall x; `drains` has the drain sizes; `colliders.posts` the guide posts.

### Colliders come from `layout.json`

`generate_models.py` also writes a `colliders` section to `layout.json` — the floor box, every wall segment
(outer walls, lane splitter, inlane guides, outlane walls, apron walls, maze), the round guide posts, the solid
dead-area fills, the glass height and the lane gate — computed from the same numbers as the meshes.
`scripts/world.gd` builds primitive `BoxShape3D` / `ConvexPolygonShape3D` / `CylinderShape3D` colliders from
it, so the physics always matches the regenerated table. Outer-wall colliders are 4 cm thick (growing outward)
to resist tunnelling. Slingshots use exact convex hulls of their meshes.

### Physics notes for the small real-world scale

- Ball uses **continuous collision detection**; physics runs at **180 Hz** with Jolt.
- `physics/jolt_physics_3d/simulation/speculative_contact_distance` is lowered to **4 mm**: the default 20 mm is
  almost a ball diameter and produced "ghost" bounces off nearby wall corners (a full-power launch bounced off the
  right inlane corner).
- The plunger-lane gate clears **both** its collision layer and mask while open (Godot collides when either
  side's mask matches, so layer 0 alone still blocked the launch). It closes once the ball is in the playfield.
- The glass collider sits at 65 mm so the 27 mm ball can never hop over the 40–50 mm walls.
- Anti-balance nudge: a ball that is perfectly still for 0.8 s above the flippers (outside the plunger lane) is
  balancing on an unstable point (e.g. exactly on top of a rounded slingshot corner) and gets a tiny random push
  (6 cm/s), like the vibration of a real table. Real rest pockets would still trap it and are caught by the tests.

## License

TBD.
