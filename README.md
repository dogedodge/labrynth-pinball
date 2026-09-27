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

The table is assembled at runtime from `assets/models/*.glb` and `layout.json` marker positions. The playfield is tilted **6.5°** about X (top / −Z raised). Physics uses **Jolt**, **180 Hz** ticks, and **continuous collision detection** on the ball (real 27 mm scale).

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
| `table.glb` | 0.60 × 0.07 × 1.10 | centre of the playfield **surface** (floor top, y=0) | Child meshes: `Floor` (0.02 m thick, below y=0), `OuterWalls` (0.05 m high, 12 mm thick, chamfered top corners), `PlungerLaneWall`, `InlaneGuides` (angled guides + apron walls down to the bottom wall), `MazeWalls` (labyrinth segments, 0.04 m high). Also contains `Marker_*` Node3D placement markers (see below). |
| `flipper.glb` | 0.091 × 0.029 × 0.027 | **pivot axis** centre, at floor level | Bat points along **+X** (length 0.07 m pivot→tip centre, pivot radius 12 mm, tip radius 6 mm, height 25 mm, sits 1 mm above floor). Use as **left** flipper directly; for the **right** flipper rotate 180° about Y (shape is symmetric, avoid negative scale). Rotate about local **Y**. Suggested angles: left rest `rotation_y = −30°`, up `+30°`; right rest `210°` (−150°), up `150°`. |
| `ball.glb` | Ø 0.027 | sphere centre | Radius **0.0135 m**. Place centre at y = 0.0135 to rest on the floor. Chrome material. |
| `bumper.glb` | Ø 0.06 × 0.043 | base centre at floor level (y=0) | Round pop bumper: dark base, red skirt (radius 0.024), yellow emissive cap (radius 0.03). A cylinder collider r≈0.024–0.03, h≈0.043 works. |
| `plunger.glb` | 0.03 × 0.022 × 0.097 | centre of the plunger head's **front face** (the face the ball touches), floor level | Head faces **−Z** (up the lane); rod + knob extend toward +Z (past the table's bottom wall — that's intended). Animate by moving along Z. |
| `slingshot_left.glb` / `slingshot_right.glb` | 0.046 × 0.035 × 0.113 | triangle centroid at floor level | Triangular block with red rubber kicker on the face pointing toward the playfield centre. Separate left/right meshes (mirrored), no rotation needed. |
| `target.glb` | 0.03 × 0.035 × 0.0095 | base centre at floor level | Stand-up target; green face points toward the player (+Z). |
| `drain.glb` | 0.106 × 0.015 × 0.004 | centre of lip, floor level | Low decorative lip between the apron walls below the flippers. Put the drain **Area3D** there (the actual "drain" is the area between the flippers and the bottom wall). |

All materials are simple Principled BSDF colours (no textures) → import as `StandardMaterial3D`. Low poly (≤ 20-segment cylinders, 16×10 ball).

### Placement markers (`table.glb` → `Marker_*` nodes; also in `assets/models/layout.json`)

Positions are Godot coordinates relative to the table origin (metres).

| Marker | Position (x, y, z) | rot Y |
|---|---|---|
| Marker_FlipperLeft | (−0.0995, 0, 0.42) | 0° |
| Marker_FlipperRight | (0.0505, 0, 0.42) | 180° |
| Marker_Plunger | (0.2695, 0, 0.50) | 0° |
| Marker_BallSpawn | (0.2695, 0.0135, 0.4845) | – |
| Marker_Bumper1 / 2 / 3 | (−0.0995, 0, −0.20) / (0.0505, 0, −0.20) / (−0.0245, 0, −0.29) | – |
| Marker_SlingshotLeft / Right | (−0.1845, 0, 0.24) / (0.1355, 0, 0.24) | – |
| Marker_Target1 / 2 | (−0.19, 0, −0.465) / (0.13, 0, −0.465) | – |
| Marker_Drain | (−0.0245, 0, 0.51) | – |

Playfield centre line (between the flippers) is x = −0.0245 (the plunger lane takes the right 0.04 m).
Plunger lane: inner x ≈ 0.251 … 0.288; ball launched up the lane hits the chamfered top-right corner and is deflected left.

### Physics tips for the small real-world scale

- Enable **continuous collision detection** on the ball (`RigidBody3D.continuous_cd = true`), and consider raising `physics/common/physics_ticks_per_second` to 120+ (the ball is 27 mm, walls are 10–12 mm thick).
- Jolt physics (default in recent Godot 4) handles small objects well; keep collision margins small.
- Use simple primitive colliders for the ball/bumpers; trimesh (`create_trimesh_collision`) or boxes for table walls.

## License

TBD.
