class_name PinballData
extends Object

## Shared pinball constants. Layout positions come from assets/models/layout.json.

const BALL_RADIUS := 0.0135
const BALL_MASS := 0.08
const BALL_MAX_SPEED := 12.0
const TABLE_TILT_DEG := 6.5
const BALLS_PER_GAME := 3

const SCORE_BUMPER := 100
const SCORE_SLINGSHOT := 10
const SCORE_TARGET := 500

const FLIPPER_LEFT_REST_DEG := -30.0
const FLIPPER_LEFT_ACTIVE_DEG := 30.0
const FLIPPER_RIGHT_REST_DEG := 210.0
const FLIPPER_RIGHT_ACTIVE_DEG := 150.0

const LAYER_WORLD := 1
const LAYER_BALL := 2
const LAYER_FLIPPER := 4
const LAYER_GADGET := 8
const LAYER_DRAIN := 16
const LAYER_PLUNGER := 32
