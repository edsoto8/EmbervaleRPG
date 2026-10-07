# Spec addendum: Graphics upgrade (Milestone 5)

This extends [SPEC_GAME.md](SPEC_GAME.md) at Milestone 5. Milestones 1–4 must first deliver a
complete, playable tutorial. This milestone makes the game look better without
changing what it is.

## 1. Goal

Make Driftwood Isle look like a polished, cohesive low-poly world: warmer light, livelier water,
vegetation that moves, more detailed characters and richer ground cover. The tutorial and every system
built so far must keep working unchanged.

## 2. Constraints (carried over)

- **Same art direction:** low-poly, flat-shaded, bright and slightly muted early-2000s fantasy. This is
  an upgrade within that style, not a move to realism.
- **Fully procedural:** no imported or purchased models, textures or images. Everything is still built
  from code, primitives and shaders.
- **Compatibility renderer (OpenGL 3)** stays the target, so older and integrated GPUs keep working.
  Effects must work in that renderer. SSR, SDFGI and volumetric fog are unavailable; real-time SSAO
  is excluded by this project's art/performance scope, regardless of engine support. Consult the
  [Godot 4.7 renderer feature table](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html).
- **Performance:** use the [shared measurement contract](SPEC_GAME.md#performance-and-pacing-contract):
  ≤ 450 draw calls on every preset and generation < 1.5 s including navigation readiness.
- **Determinism:** island layout, landmarks and collision must not move. The playthrough suite must
  still pass without changes to its expectations.

## 3. Features

### G1. Lighting and atmosphere
- Warm late-afternoon sun with a slightly golden key light and a cooler sky/ground ambient fill, so lit
  and shadowed faces read clearly.
- Softer, better-filtered shadows that start at the camera and stay crisp near the player.
- Sky and fog colours tuned together so the horizon blends into haze instead of a hard line.
- Subtle bloom on bright highlights (lamps, sun glints on water) and gentle colour grading (contrast,
  saturation) on Medium and High.

### G2. Water
- Colour depends on depth: turquoise shallows over sand fading to deep blue offshore, for both the sea
  and the pond.
- Animated white foam bands along every shoreline, the dock posts' waterline and the pond's edge.
- Moving specular sparkle and a gentle low-poly wave surface.
- Depth comes from a texture baked once from the terrain heightfield, so no depth-buffer reads are
  needed (those aren't reliable in the Compatibility renderer).

### G3. Wind
- Grass, tree canopies, bushes, reeds and flowers sway in a shared, gusting wind. Trunks, buildings
  and the ground stay still.
- Sway must survive mesh batching: the sway weight travels in the vertex colour's alpha channel.

### G4. Terrain
- Baked shading per tile: steeper slopes are slightly darker, and ground under trees and along building
  walls is darker (fake ambient occlusion).
- Softer transitions where paths, sand, grass, plaza and courtyard meet, while keeping the tile look.
- A darker wet-sand band at the waterline.

### G5. Characters
- More detailed procedural models: hands, shoes with soles, a collar and belt buckle, a nose, mouth and
  eyebrows, and hair with more volume.
- A soft rim light in the character shader so characters stand out from the ground at gameplay zoom.
- All existing customisation options, animations and the dialogue portraits keep working.

### G6. Ground cover and props
- More plant variety: ferns, mushrooms, tall grass clumps, several flower types, and lily pads and
  cattails on the pond.
- Border stones along the main paths and a few extra small details (wood piles, buckets).
- All new decoration is batched and fades out with distance like the existing small decor.

### G7. Screen polish
- A subtle vignette, on Medium and High.
- Anti-aliasing chosen by preset (off / 2× / 4× MSAA).

### G8. Graphics quality setting
A new *Graphics quality* option in Settings, applied immediately, saved with the other settings and
defaulting to **Medium**:

| | Low | Medium | High |
|---|---|---|---|
| Shadows | 30 m, low resolution | 50 m | 70 m, high resolution, soft |
| Anti-aliasing | Off | MSAA 2× | MSAA 4× |
| Grass density | 40% | 100% | 100% |
| Wind animation | Grass only | All plants | All plants |
| Bloom + grading | Off | On | On |
| Vignette | Off | On | On |
| Small decor fade | 45 m | 75 m | 100 m |

Low still has shadows: in the Compatibility renderer, turning the sun's shadows off made the whole
scene noticeably darker (found while tuning), so Low uses short, low-resolution shadows instead.
High was first specified with FXAA on top of MSAA 4×, but screen-space AA isn't available in the
Compatibility renderer (Godot warns and ignores it), so it was dropped.

## 4. Acceptance criteria

1. Every feature in section 3 is visible in the screenshot set (`tests/capture_screenshots.tscn`), with
   before and after shots of the same views.
2. Switching quality presets in Settings changes the listed parameters immediately, and the choice
   persists across restarts.
3. All existing test suites pass, including the no-teleport playthrough.
4. A new graphics test suite covers presets, persistence, the water depth bake (shallow near the shore,
   deep offshore), wind weights after batching, the richer character model, and the new ground cover.
5. Draw calls stay within the budget in section 2 on every preset (`tests/perf_report.tscn`).
6. No new warnings or errors in a normal run.
7. Review a short video or live run for water, gusts, anchored stems and transitions; still screenshots
   are evidence of appearance, not animation correctness. Use identical cameras, resolution, seed and
   graphics preset for M4/M5 comparison shots, and retain the M4 captures before implementing M5.

## 5. Out of scope

Day/night cycle, weather, dynamic lights at night, imported assets, a renderer change to Forward+ or
Mobile, terrain texture splatting, and real reflections.
