class_name Layers
extends RefCounted
## Physics layer bits, matching the names in project.godot.

const GROUND := 1
const OBSTACLES := 2
const BOUNDARY := 4
const PLAYER := 8
const INTERACTABLES := 16
const CAMERA_BLOCKERS := 32

## Layers the navmesh is baked from and the player collides with.
const WALKABLE_SOURCES := GROUND | OBSTACLES | BOUNDARY
## Layers a mouse click is ray-cast against (areas included), so invisible walls never catch clicks.
const CLICKABLE := GROUND | OBSTACLES | INTERACTABLES
