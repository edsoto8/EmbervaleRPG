# Implementation plan and checklist

A RuneScape-inspired RPG demo: main menu → character creation → intro cutscene → five-objective
tutorial on a small island, followed by skills and progression. Each milestone has to end in a runnable
game, and milestones are built one at a time.

## Specification and rebuild status

All boxes refer to the **new rebuild**, which lives in [`EmbervaleRebuild/`](EmbervaleRebuild/). This
repository does not contain the reference implementation, so the rebuild was written from these
specifications. Verification results are recorded in
[`EmbervaleRebuild/VERIFICATION.md`](EmbervaleRebuild/VERIFICATION.md).

- [SPEC_GAME.md](SPEC_GAME.md): authoritative M1–M4 behavior, inventory, performance and pacing.
- [SPEC_SAVE.md](SPEC_SAVE.md): authoritative schema, import and recovery policy.
- [SPEC_GRAPHICS.md](SPEC_GRAPHICS.md): M5 additions.
- [SPEC_SKILLS.md](SPEC_SKILLS.md): M6 additions and exact balance.
- `CLAUDE.md`: development procedures and historical implementation notes.

## Milestone 0: Rebuild foundation

- [x] Create separate rebuild directory; preserve the reference project and screenshots
- [x] Pin Godot 4.7-stable and matching export templates; record engine version in rebuild README
- [x] Use `EmbervaleRebuild` user-data name; isolate test/capture/perf paths before autoload startup
- [x] Establish shared interfaces, input names, physics layers and suite registration for M1
- [ ] Identify a reference Windows PC and record CPU/GPU/driver/OS for the provisional performance target

## Milestone verification gates

Every milestone ends in a runnable project. Import/parse check, applicable suites and visual inspection
are required; do not invoke future suites that have not been built yet.

| Milestone | Automated gate | Human/evidence gate |
|---|---|---|
| M1 | world: movement, reachable landmarks, nav readiness, boundaries, camera | Walk all routes; capture fixed island views |
| M2 | world + flow: validation, intro skip, menu/Continue, isolated saves/settings, write failures | Check window settings, character preview and camera handoff |
| M3 | Previous + tutorial: five objectives, dialogue outcomes, cancellation, full inventory reward retry, save round-trip | Complete tutorial through UI; inspect HUD/dialogue |
| M4 | Previous + polish + no-teleport playthrough from menu through tutorial and Continue | Hear audio, inspect motion, performance report, Windows export/runtime smoke; preserve M4 screenshots |
| M5 | Previous + graphics: live presets, persistence, water/wind/batching, cover | Same-view M4/M5 comparisons, video/live motion, perf on every preset |
| M6 | Previous + skills + no-teleport skills_playthrough; version 1 import, pending rewards, transactions and recovery | Complete all ten tasks, record pacing/perf and native Windows release smoke |

Playthroughs use input/UI, not teleportation, reward injection or direct progress setters. Deterministic
rolls are allowed in the skills playthrough. Skills unit/integration checks cover the full task list;
the no-teleport skills path covers tutorial end through buying the steel axe. Use a timeout wrapper
appropriate to the host for automated runs. Missing Windows/hardware checks stay explicitly unchecked.
After all required gates pass, review the diff and tick only verified boxes; commits follow session
instructions, not an automatic documentation mandate.

## Architecture

| System | Responsibility | Milestone |
|---|---|---|
| `TutorialIsland` + `IslandTerrain` + `PropFactory` | Procedural island, landmarks, navmesh | M1 |
| `PlayerController` | WASD/run input, physics movement, facing | M1 |
| `NavigationController` | Click → ground point → navmesh path → steering | M1 |
| `CameraController` | Follow, zoom, orbit, obstacle avoidance | M1 |
| `CharacterModel` | Procedural humanoid from an appearance dictionary, idle/walk/run | M1 |
| `GameManager` (autoload) | Global state, current character, flow, fades, save snapshot | M2 |
| `SettingsManager` (autoload) | Resolution, fullscreen, volume, mouse sensitivity, graphics quality (`user://settings.json`) | M2, M5 |
| `SaveManager` (autoload) | JSON save slot (`user://savegame.json`) | M2 |
| `UITheme` + menus | Shared theme, main/pause menus, settings and confirm panels | M2 |
| `IntroCutscene` | Boat arrival + island flyover, skippable | M2 |
| `InteractionSystem` | Hover text, click-to-walk-then-interact, E for nearest | M3 |
| `DialogueManager` (autoload) | Dialogue graphs: lines, choices, actions | M3 |
| `QuestManager` (autoload) | Five tutorial objectives, island tasks, autosave trigger | M3, M6 |
| `InventoryManager` (autoload) | 28 slots, stacking, inspection | M3 |
| `TutorialDirector` | World events → quest reports, NPCs, markers, reward, gate sequence | M3 |
| `GameHUD` | Hitpoints, minimap, quest tracker, message log, inventory and dialogue panels | M3 |
| `AudioManager` + `Synth` | Procedurally synthesized music, ambience and SFX | M4 |
| `EnvironmentController` | Sky, sun, post-processing, vignette; applies the graphics quality preset | M5 |
| `SkillsManager` (autoload) + `SkillData` | XP, levels, hitpoints, skill formulas | M6 |
| `SkillsDirector` | Item actions, fire placement, shop, level-up effects | M6 |

Rules: keep gameplay logic separate from presentation, and use signals between independent systems. For
example, `ClickMarker` only listens to `NavigationController` signals, and `TutorialIsland` exposes
`landmarks` for the quests and minimap to use.

## Milestone 1: Playable world

Spec: [SPEC_GAME.md](SPEC_GAME.md#world-and-navigation-m1).

- [x] Create the Godot 4.7 project (Compatibility renderer, input map, named physics layers)
- [x] Generate the tutorial island procedurally (deterministic seeds)
  - [x] Tile-coloured, flat-shaded heightfield terrain with beaches, paths, plaza and courtyard paving
  - [x] Arrival dock with a moored boat (player spawns here)
  - [x] Village: five cottages, well, market stalls, lamp posts, signpost, fenced garden
  - [x] Training courtyard: fence with west entrance, training dummies, weapon rack
  - [x] Forest clearing (open centre kept free for choppable trees), stumps, log pile
  - [x] Fishing pond with rocks and reeds
  - [x] Exit gate: gatehouse, stone walls, bridge towards a distant mainland
  - [x] Scattered trees, rocks, bushes, flowers, grass; sea and sky
  - [x] Invisible shoreline, pond and dock-rail boundaries
  - [x] Runtime navmesh bake + `navigation_ready` signal
- [x] Controllable character (procedural low-poly model, idle/walk/run blending)
- [x] WASD movement: camera-relative, diagonals normalised, smooth turning, Shift to run
- [x] Point-and-click movement with pathfinding around obstacles; keyboard cancels it immediately
- [x] Destination marker
- [x] Camera: smooth follow, wheel zoom (clamped), middle-drag/arrow orbit, no interruption of movement,
      pulls in to keep buildings from hiding the player
- [x] Headless gameplay tests + screenshot capture (test runner as a scene, so autoloads load)
- [x] README with launch/test instructions
- [x] Batch static props sufficiently to meet the shared performance contract; M4 extends batching/polish

## Milestone 2: Introductory experience

Specs: [base flow](SPEC_GAME.md#menu-character-and-intro-m2), [saving](SPEC_SAVE.md).

- [x] `GameManager` autoload + fade transitions between scenes
- [x] Main menu over an orbiting island view: title/logo, New Game, Continue (disabled with no save),
      Settings, Exit; confirmation before New Game replaces a save
- [x] Settings: resolution, fullscreen, volume, mouse sensitivity; applied immediately, persisted; UI
      scales with resolution (`canvas_items` stretch)
- [x] Character creation: name (validated), body type, skin, hair style/colour, shirt/pants colour,
      rotating and draggable preview, Randomize, Create Character (reuses `CharacterModel.appearance`)
- [x] Intro cutscene in the world scene: boat sails in with the player aboard, island flyover, three intro
      messages, letterbox, skip (button / Space / Esc / Enter), seamless hand-off to the gameplay camera
- [x] `run/main_scene` → main menu
- [x] Version 2 `SaveManager` per SPEC_SAVE.md (character, stage, position; saved on create, after the intro, on Save & Main
      Menu / Save & Exit / window close) and the pause menu

## Milestone 3: Tutorial systems

Specs: [tutorial](SPEC_GAME.md#tutorial-npc-dialogue-and-hud-m3),
[inventory transactions](SPEC_GAME.md#inventory-and-transactions).

- [x] `InteractionSystem`: interactables layer (5) incl. canopy click areas, hover text + hand cursor,
      click-to-walk-then-interact, `E` for the nearest one
- [x] Instructor Maelis + three villagers (Marla and Old Tobin stationary, Pip wandering)
- [x] `DialogueManager` + dialogue panel (live 3D portrait, typed text, Continue, numbered choices,
      actions such as giving the sword); the message log hides while talking
- [x] Five choppable trees in the forest clearing: cancellable chop action with an axe swing, logs,
      stumps that regrow after 20 s
- [x] `InventoryManager` + inventory panel (`I` or button, 4×7 grid, icons, names, quantities, click to
      examine)
- [x] `QuestManager` with the five objectives (WASD 4 m + click marker; talk; 3 logs; open inventory and
      examine logs; return → Beginner sword), autosave after each objective
- [x] HUD: hitpoints, minimap (island, player arrow, villagers, objective star), quest tracker with
      checklist, message log
- [x] Exit-gate camera sequence (skippable) + "Tutorial Complete" screen (Continue Exploring / Return to
      Main Menu)
- [x] Save extended with quest progress and inventory; Continue restores both
- [x] Inventory transaction preflight, cancellation and retryable sword delivery; legacy M2–M5 fixture imports

## Milestone 4: Polish

Spec: [polish and acceptance](SPEC_GAME.md#polish-and-acceptance-m4).

- [x] Animation: smooth turn-to-face (player and NPCs), talk gestures, a cheer on objective completion,
      idle head glances, footstep events from the stride
- [x] Environment: clouds circling the island, gulls, chimney smoke, wood chips and tree shake on each
      axe strike
- [x] Performance: `MeshMerger` batches static props into vertex-coloured chunks; small decor fades out
      beyond 75 m; `tests/perf_report.tscn`
- [x] Procedurally synthesized audio (`Synth` + `AudioManager`): menu theme, surf louder near the shore,
      birdsong, footsteps, chop, pickup, UI click, dialogue, inventory, objective jingle, tutorial
      fanfare; SFX/Ambience/Music buses; slow recipes rendered on a worker thread
- [x] Graceful quit (`GameManager.quit_game`: save, stop audio, short real-time wait), also on window close
- [x] **No-teleport playthrough suite** from main menu to Tutorial Complete and back via Continue
- [x] Windows export preset; release export builds and runs
- [ ] Windows runtime smoke test on a real Windows PC

## Milestone 5: Graphics upgrade

Spec: [SPEC_GRAPHICS.md](SPEC_GRAPHICS.md).

- [x] G8 Graphics quality setting (Low / Medium / High), applied live, persisted, in the Settings panel
- [x] G1 Lighting and atmosphere: warm 38° key light, cool fill, softer shadows, sky/fog blend, bloom +
      grading
- [x] G2 Water: signed depth texture baked from the terrain, turquoise shallows → deep blue, animated
      shore foam, foam rings at dock/bridge posts, sparkle
- [x] G3 Wind: plant sway that survives batching, stems anchored at the root, gusts
- [x] G4 Terrain: slope + fake AO shading, softened transitions, wet-sand band
- [x] G5 Characters: hands, boots, collar, buckle, mouth, ears, eye highlights, fuller hair, rim light
- [x] G6 Ground cover: ferns, mushrooms, tall grass, flowers, lily pads, cattails, path border stones,
      wood piles, a bucket
- [x] G7 Screen polish: vignette, MSAA by preset
- [x] Graphics test suite; perf budget met on every preset; before/after screenshots

## Milestone 6: Skills and progression

Spec: [SPEC_SKILLS.md](SPEC_SKILLS.md).

- [x] S1 `SkillsManager` autoload: five skills + hitpoints, RuneScape XP curve, level-ups, XP drops,
      level-up jingle and sparks, Skills panel (K)
- [x] S2 Woodcutting XP; oak (lvl 5) and willow (lvl 10) trees that give several logs; faster with
      level and the steel axe
- [x] S3 Fishing: rod + tinderbox from Old Tobin, two pond fishing spots, shrimp / trout, repeat until
      moved or full
- [x] S4 Firemaking: Light from the inventory, fires that burn out, placement rules, failures
- [x] S5 Cooking on fires with burn chance; Eat heals; hitpoints regenerate
- [x] S6 Attack training on the courtyard dummies (up to level 10)
- [x] S7 Coins and Marla's shop, opened from her stall
- [x] S8 Island tasks after the tutorial, with coin rewards and a finale
- [x] S9 Save nested skills/hitpoints, tasks and pending rewards; version 1 imports and earlier rebuild saves load
- [x] S10 Exact balance formulas, activity cancellation, capacity transactions and gear recovery
- [x] Full task/reward coverage, including tutorial-time credit and repeated Continue without duplicate grants
- [x] Skills suite + no-teleport skills playthrough; hard perf limit ≤ 450 draw calls on every preset (≤ 260 optimization target)
