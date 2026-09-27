# labrynth-pinball

A minimal **Godot 4** pinball game MVP with a light "labyrinth" theme.

- **Engine:** Godot 4.x (developed and verified with **4.7.2**; `project.godot` features target 4.3+)
- **Target:** mobile, **landscape** orientation (desktop works too)
- **Controls:** keyboard plus on-screen virtual buttons (multitouch)
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

Headless import / smoke test (launches the ball up the plunger lane and checks flipper rotation):

```sh
godot --headless --path . --import
godot --headless --path . -- --smoke-test
# optional: tools/verify.sh
```

Capture a PNG of the running game (writes `docs/gameplay.png` by default):

```sh
godot --path . -- --screenshot
```

## Controls

Keyboard and on-screen buttons both use the same Input Map actions, so they can be mixed. Touch buttons support **multitouch** (hold both flippers at once).

| Action | Keyboard | On-screen |
|---|---|---|
| Left flipper | Left, Z, A, `,` | **L** (left side) |
| Right flipper | Right, M, D, `/` | **R** (right side) |
| Charge / release plunger | Space or Down (hold to charge, release to shoot) | **LAUNCH** |
| Pause | Esc or P | **PAUSE** |
| Restart | R or Enter | **RESTART** |

## Gameplay

- Wide 1.16 m × 1.00 m labyrinth table: 5 pop bumpers, 4 stand-up targets, 2 slingshots, 12 maze wall segments.
- 3 balls per game. The ball starts in the plunger lane; charge and release to launch.
- Pop bumpers **100**, slingshots **10**, stand-up targets **500**.
- Drain between the flippers loses a ball. After the last ball, Game Over — press Restart.
- There is no extra ball / ball-save in this MVP.

## Project structure

```
scenes/main.tscn       main scene (world + HUD + touch + overlays)
scripts/               gameplay (world assembly, ball, flippers, plunger, gadgets)
ui/                    HUD / touch / overlay packed scenes
assets/models/         .glb models (one per piece) + layout.json (suggested placements)
assets/blender/        labrynth_models.blend (source, one collection per model)
tools/blender/         generate_models.py (reproducible generator)
tools/verify.sh        headless import + smoke test helper
docs/                  preview + gameplay screenshots
```

The camera frames the wide table to fill a 16:9 landscape screen (narrower screens lock the horizontal FOV instead). Touch buttons sit semi-transparently at the screen edges over the table's dead corners.

The table is assembled at runtime from `assets/models/*.glb` and `layout.json` marker positions. The playfield is tilted **6.5°** about X (top / −Z raised). Physics uses **Jolt**, **180 Hz** ticks, and **continuous collision detection** on the ball (real 27 mm scale).

Launch is a charged velocity impulse (the plunger mesh is animated visually). All static table colliders are primitives generated from `layout.json` (see below). No audio in this MVP. Headless runs may log a missing ALSA device and fall back to the dummy audio driver.

Regenerate all models (from repo root):

```sh
blender -b --factory-startup --python tools/blender/generate_models.py -- --preview docs/preview.png
```

## Models

**Scale:** 1 unit = **1 metre**, real-world-ish pinball parts on a deliberately **wide, landscape-friendly
table: 1.16 m wide × 1.00 m long** (widened from 0.60 × 1.10 so it fills a 16:9 phone screen). Ball is a real 27 mm ball.

**Axes (Godot, Y-up, as imported from the glb):**
- playfield surface is at **y = 0**
- the **far/top** end of the table (bumpers, maze) is **−Z**
- the **player end** (flippers, drain, plunger) is **+Z**
- plunger lane is on the **right** (+X)
- the table is modelled flat — this project tilts the playfield ~6.5° about X (top end up).

| File | Size (x × y × z, m) | Origin / pivot | Notes |
|---|---|---|---|
| `table.glb` | 1.16 × 0.07 × 1.00 | centre of the playfield **surface** (floor top, y=0) | Child meshes: `Floor` (0.02 m thick, below y=0), `OuterWalls` (0.05 m high, 12 mm thick, 0.15 m chamfered top corners), `PlungerLaneWall`, `InlaneGuides` (long angled guides + apron walls), `ApronPlates` (raised dark plates marking the dead pockets behind the guides), `MazeWalls` (12 labyrinth segments, 0.04 m high). Also contains `Marker_*` Node3D placement markers (see below). |
| `flipper.glb` | 0.108 × 0.029 × 0.029 | **pivot axis** centre, at floor level | Bat points along **+X** (length **0.085 m** pivot→tip centre, pivot radius 13 mm, tip radius 7 mm, height 25 mm). Use as **left** flipper directly; for the **right** flipper rotate 180° about Y. Angles: left rest `−30°`, up `+30°`; right rest `210°`, up `150°`. Tip gap at rest: **33 mm** (ball 27 mm). |
| `ball.glb` | Ø 0.027 | sphere centre | Radius **0.0135 m**. Light, partly metallic steel so it stays visible without an environment map. |
| `bumper.glb` | Ø 0.06 × 0.043 | base centre at floor level (y=0) | Round pop bumper: dark base, red skirt, yellow emissive cap. |
| `plunger.glb` | 0.03 × 0.022 × 0.097 | centre of the plunger head's **front face**, floor level | Head faces **−Z** (up the lane); rod + knob extend toward +Z past the bottom wall (intended). |
| `slingshot_left.glb` / `slingshot_right.glb` | 0.046 × 0.035 × 0.113 | triangle centroid at floor level | Rubber kicker faces the playfield centre. Separate mirrored meshes. |
| `target.glb` | 0.03 × 0.035 × 0.0095 | base centre at floor level | Stand-up target; face points toward the player (+Z). |
| `drain.glb` | 0.1482 × 0.015 × 0.004 | centre of lip, floor level | Decorative lip between the apron walls below the flippers; the drain Area3D sits here. |

All materials are simple Principled BSDF colours (no textures). Low poly.

### Placement markers (`table.glb` → `Marker_*` nodes; also in `assets/models/layout.json`)

Positions are Godot coordinates relative to the table origin (metres). The game places one bumper /
target per `Marker_Bumper*` / `Marker_Target*` entry, so adding markers in the generator adds gadgets.

| Marker | Position (x, y, z) | rot Y |
|---|---|---|
| Marker_FlipperLeft | (−0.1216, 0, 0.38) | 0° |
| Marker_FlipperRight | (0.0726, 0, 0.38) | 180° |
| Marker_Plunger | (0.5495, 0, 0.44) | – |
| Marker_BallSpawn | (0.5495, 0.0135, 0.4245) | – |
| Marker_Bumper1…5 | (−0.1289, 0, −0.12) / (0.0799, 0, −0.12) / (−0.0245, 0, −0.22) / (−0.3725, 0, −0.04) / (0.3003, 0, −0.04) | – |
| Marker_SlingshotLeft / Right | (−0.2565, 0, 0.2) / (0.2075, 0, 0.2) | – |
| Marker_Target1…4 | (−0.3441, 0, −0.42) / (−0.1817, 0, −0.42) / (0.1083, 0, −0.42) / (0.2707, 0, −0.42) | – |
| Marker_Drain | (−0.0245, 0, 0.45) | – |

Playfield centre line (between the flippers) is x = -0.0245; plunger lane centre x = 0.5495 (lane wall at x = 0.525).
A ball launched up the lane hits the chamfered top-right corner and is deflected left across the top.

### Colliders come from `layout.json`

`generate_models.py` also writes a `colliders` section to `layout.json` — the floor box, every wall
segment (outer walls, lane splitter, inlane guides, apron walls, maze), the solid pocket fills behind
the guides, the glass height and the lane gate — computed from the same numbers as the meshes.
`scripts/world.gd` builds primitive `BoxShape3D` / `ConvexPolygonShape3D` colliders from it, so the
physics always matches the regenerated table. Outer-wall colliders are 4 cm thick (growing outward)
to resist tunnelling.

### Physics notes for the small real-world scale

- Ball uses **continuous collision detection**; physics runs at **180 Hz** with Jolt.
- `physics/jolt_physics_3d/simulation/speculative_contact_distance` is lowered to **4 mm** (default 20 mm is
  almost a ball diameter and produced "ghost" bounces off nearby wall corners, e.g. stopping the launch).
- The glass collider sits at 65 mm so the 27 mm ball can never hop over the 40–50 mm walls.

## License

TBD.
