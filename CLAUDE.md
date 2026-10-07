# CLAUDE.md — EmbervaleRPG

Godot 4.7-stable / GDScript project, **not .NET**. None of the repo-wide .NET conventions (Dapper, SQLite,
Serilog, `dotnet` commands) apply here. Read [README.md](README.md) for controls and layout, and
[PLAN.md](PLAN.md) for the milestone checklist. Keep PLAN.md up to date as work lands.

## Document authority and reference code

Read [SPEC_GAME.md](SPEC_GAME.md), [SPEC_SAVE.md](SPEC_SAVE.md) and the relevant addendum before building.
They define product behavior; PLAN.md schedules it. The existing implementation is historical reference,
with known gaps in capacity, recovery and save failure handling; reproduce spec behavior instead of
copying those gaps. Keep the reference project intact and use a separate rebuild project/user-data name.
Conventions mentioning existing helpers or tests describe the previous build and can be implemented
with equivalent interfaces. Literal dialogue line counts are not product requirements.

## Commands

Run these from the relevant project directory (`EmbervaleRPG/` for the reference, the new directory for
rebuild). `godot` is the Godot 4.7-stable editor binary; configure an executable alias/path if needed.
Test/capture scenes below are available in the reference and must be recreated milestone by milestone.

Check `godot --version` first. The first import uses `--editor --quit` to exit after importing. Headless
checks run on macOS/Linux/Windows; screenshots/perf require a display and real renderer. `xvfb-run` is
optional for Linux without a display; on macOS/Windows or desktop Linux run `godot` directly. Wrap
unattended runs in GNU `timeout`, macOS `gtimeout` if installed, or the execution tool's deadline. The
commands below show raw engine arguments; no platform-specific timeout utility is mandatory.

```bash
godot --headless --editor --path . --import --quit                                       # rebuild .godot cache / class registry; reports parse errors
godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn     # all suites; exit code 0 = pass
godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- world   # one suite (world | flow | tutorial | polish | playthrough | graphics | skills | skills_playthrough)
godot --headless --path . --fixed-fps 60 --quit-after 600                               # smoke-run the main menu ~10 s, watch for errors
godot --path . --rendering-driver opengl3 --fixed-fps 60 res://tests/capture_screenshots.tscn -- <out_dir>  # visual check
godot --path . --rendering-driver opengl3 --fixed-fps 60 res://tests/capture_views.tscn -- <out_dir> [low|medium|high]  # 6 views, ~1 min
godot --path . --rendering-driver opengl3 --fixed-fps 60 res://tests/capture_skills.tscn -- <out_dir>  # Milestone 6 activities and panels
godot --path . --rendering-driver opengl3 res://tests/perf_report.tscn   # draw calls per view and preset
godot --headless --path . --export-release "Windows Desktop" build/windows/Embervale.exe  # needs export templates
```

The reference smoke run with `--quit-after` reported "2 ObjectDB instances leaked" while menu music
played. Record this separately from normal-run acceptance; the rebuild must verify graceful shutdown
through `GameManager.quit_game()`, which stops audio and waits in real time first. The playthrough suite
is the end-to-end check, because it never teleports. If you change
the layout or obstacles, run it, since teleporting tests can't catch places the player can't walk to.

Run `--import` after adding a new `class_name` script, or other scripts won't resolve the new class. Keep
`--fixed-fps 60` on test and capture runs so game time is deterministic. Without it, the slow software
renderer skips through tweens and cutscenes. If a script fails to compile, the runner hangs instead of
exiting, so use the host timeout/deadline wrapper described above.

**Don't use `-s script.gd` entry points.** Those scripts compile before autoloads are registered, so any
script that references `GameManager`, `SettingsManager` or `SaveManager` fails with "Identifier not
found". Make test and tool entry points small scenes instead, like `tests/test_runner.tscn`. New tests
go in a suite under `tests/suites/` (extend `test_suite.gd` and list the suite in `test_runner.gd`).
Suites that drive scene changes go through `GameManager`. The runner sets `current_scene = null` so those
changes don't free it.

## Rebuild workflow and optional delegation

Go one milestone at a time and use [PLAN.md verification gates](PLAN.md#milestone-verification-gates).
The main session owns layout/landmarks, GameManager flow/save snapshots, tutorial wiring, batching and
performance checks. Lay shared groundwork first: project.godot input/physics/autoload declarations,
public manager signatures/signals, suite registration and UITheme. Add later managers when their
milestone begins; do not require M6 dependencies for M1 tests.

Delegation is optional and must match available tools and session authorization. No particular agent
names, reviewer plugin or worktree-isolation parameter is required. If parallel agents are used, assign
explicit file ownership and provide actual separate worktrees/checkouts; otherwise run overlapping work
sequentially. Each work unit receives the specs, files it may edit, signals/APIs it consumes or exposes,
its test suite and host-appropriate commands. Agents report changes, verification and needed shared-file
updates; shared files stay with the main session.

After integration: import/parse, run all currently applicable suites, then milestone playthroughs when
available (tutorial playthrough from M4, skills playthrough from M6), inspect visuals and record perf.
Review the diff using available review tooling; unavailable named agents/plugins do not block work.
Tick only completed and verified checklist items. Commit only when authorized by the session.

Good independent units include terrain/props, character model, player/navigation, camera, menus,
cutscene, dialogue UI, inventory UI and audio; graphics/skills units become independent after their
shared APIs exist. Units editing the same world/HUD/director files run sequentially.

## Conventions

- **Everything is procedural.** Meshes come from `PropFactory` primitives plus the shared flat-shaded
  shader (`shaders/lowpoly.gdshader`). Don't add imported art unless the spec changes. Use
  `PropFactory.mat(color)` for materials (cached), not new `StandardMaterial3D`s.
- **Determinism.** The island uses fixed seeds (`TutorialIsland.generation_seed`, the
  `IslandTerrain.noise` seed). Tests and future quests depend on the `landmarks` positions, so if you
  change the layout, check that landmarks are still on walkable ground.
- **Physics layers** (named in `project.godot`): 1 ground, 2 obstacles, 3 boundary (invisible), 4 player,
  5 interactables, 6 camera_blockers. Solid props must be `StaticBody3D`s under `nav_region` so the
  runtime navmesh bake carves around them. Decor without collision goes under `_decor`.
- **Navigation readiness.** Map sync is synchronous (`navigation/world/map_use_async_iterations=false`),
  but still wait for `TutorialIsland.navigation_ready` (or `is_navigation_ready`) before issuing path
  queries.
- **Physics interpolation is on.** Move bodies in `_physics_process`. Nodes moved per rendered frame
  (camera rig, click marker) set `physics_interpolation_mode = OFF`. Call `reset_physics_interpolation()`
  after teleporting.
- **Autoloads.** `GameManager` owns flow (new game, continue, return to menu), the current character
  and the save snapshot (`build_save_data()`). Extend that function when adding quest or inventory
  state. `SaveManager` only reads, writes and validates JSON. `SettingsManager` persists separately from the
  save. Nothing is saved until `GameManager.adventure_loaded` is true (a character was created or
  loaded), so running the world scene directly (F6) never writes a save.
- **Autoload order matters** (`project.godot`): Settings, Save, Inventory, Skills, Quest, Dialogue,
  Audio, then Game.
  GameManager's `_ready` connects to QuestManager. The save holds `character`, `stage`, `player`,
  `quest` (`QuestManager.to_dict()`, including island `tasks`), `inventory` (`InventoryManager.to_dict()`)
  and `skills` (`SkillsManager.to_dict()`: XP and hitpoints). Load the inventory before the quest,
  because quest checks read item counts. Every new key must default sensibly when missing, so older
  saves keep loading. Use SPEC_SAVE.md for validation, migration, pending rewards and write failures.
- **Tutorial wiring.** Gameplay objects report to autoloads (`QuestManager.report_*`,
  `InventoryManager.add_item/inspect`, `GameManager.post_message`). `TutorialDirector` (a world node)
  turns world events into those reports and owns NPC spawning, objective markers, the sword reward and
  the gate sequence. Dialogue content lives only in `TutorialDialogues`. Autoload signals outlive the
  world, so disconnect them in `_exit_tree`, as the director does.
- **Interaction interface (duck-typed).** Anything clickable or usable with E implements
  `interaction_verb()`, `interaction_name()`, `interaction_range()`, `interaction_position()` and
  `interact(player)`, and joins the `interactable` group. Put its click shape on layer 5 (an Area3D child
  is fine; `InteractionSystem.interactable_from()` resolves an area to its parent). These calls return
  Variant, so give results explicit types (`var d: Vector3 = target.interaction_position()`); `:=` fails
  to compile.
- **Static prop batching.** `TutorialIsland._merge_meshes()` replaces every MeshInstance3D that uses a
  shared `PropFactory.mat()` material with vertex-coloured chunks (`MeshMerger`). Anything that moves,
  animates or toggles visibility must stay out of the merge: add it to the `keep` list (as with the boat
  and `choppable_trees`), or create it after `_merge_meshes()` (as `AmbientLife` is).
- **Obstacle heights.** The navmesh step height (`agent_max_climb`) is one cell (0.25 m) and the player
  has no step-up logic, so any collision shape shorter than that becomes a trap. Keep obstacle collision
  at least about 1 m tall even when the visual mesh is low (stumps, rocks).
- **Audio.** Gameplay never calls `AudioManager` for game events: it listens to autoload signals
  (inventory, quest, dialogue) and to button presses through `SceneTree.node_added`. Scenes only start or
  stop music and ambience and forward a few world events (footsteps, axe impacts, inventory toggle). New
  sounds are static recipes on `Synth`; slow ones go in `AudioManager.PRERENDERED`. Worker-thread recipes
  must use their own `RandomNumberGenerator`. Under the headless display server one-shots are counted
  (`AudioManager.count()`) but not started.
- **Timed player actions** go through `await player.perform_action(name, seconds, face_point)`, which
  returns false if movement cancelled it. `CharacterModel.play_action(name, duration)` animates "chop",
  "fish", "attack", "light", "cook", "eat", "talk" and "cheer" (showing the axe, rod or sword as needed);
  a positive duration stops it automatically. `face_towards()` turns smoothly; `face_yaw()` snaps.
- **Graphics presets.** `EnvironmentController` (root of `environment.tscn`) applies the sun, MSAA,
  post-processing, vignette and the `wind_strength` shader global; `TutorialIsland.apply_graphics_quality()`
  handles grass density and the small-decor fade. Both listen to `SettingsManager.settings_changed`. The
  Compatibility renderer has no screen-space AA (FXAA), and turning sun shadows off darkens the scene, so
  Low keeps short shadows. Keep the sun's default shadow biases and four splits; lowering them caused
  acne stripes.
- **Wind.** `PropFactory.mat(color, sway)` / `PropFactory.swaying(mi, weight, anchored)` mark plant parts.
  MeshMerger bakes the weight into vertex alpha (`1 - weight`; anchored meshes ramp from root to tip), so
  never put other data in vertex alpha of batched props.
- **Water depth.** `TutorialIsland._bake_water_depth()` bakes signed depth (`WATER_LAND_OFFSET` above the
  surface included) for the sea and pond after generation; the water shader discards fragments over
  ground above the still-water line. Add posts that stand in the sea to `_water_posts`.
- **Terrain shading.** The visible terrain mesh is built after all props (`_build_terrain_mesh()`), using
  `_occluders` (`_occlude(pos, radius, strength)`) for fake AO. Collision is built first in
  `_build_ground()`.
- **Ground cover** uses `_cover_rng`, not `_rng`: drawing extra numbers from `_rng` would move every prop
  placed after it. Do the same for any future decoration.
- **Characters** get the rim-lit materials in `CharacterModel._apply_rim()` after building:
  `PropFactory.character_vertex_mat()` on the merged body parts, `character_mat()` on the props. Neither
  is a shared material, so characters never end up in the island's batches.
- **Skills (Milestone 6).** Numbers and formulas live in `SkillData`; XP, levels and hitpoints in the
  `SkillsManager` autoload. Every skill check rolls through `SkillsManager.chance()`, so tests make luck
  deterministic with `SkillsManager.roll_override`. Repeating actions (chopping oaks, fishing, cooking,
  training) are `while` loops around `player.perform_action()` that stop when it returns false. An
  object with such a loop must not be freed while it waits (see `Campfire`, which frees itself after
  cooking stops). `SkillsDirector` (world node) handles inventory item actions, fire placement, Tobin's
  rod, the shop and level-up sparks. Island tasks are in `QuestManager` (`report_task()`).
- **Dialogue and tracker.** The shop opens from `MarketCounter` (the stall). Island tasks appear
  beneath "Ready for adventure". The reference tutorial test assumes a one-line `merchant_chat`; this
  is historical coupling. Rebuild tests assert dialogue outcomes, allowing wording/line-count edits.
- **Draw calls.** Mesh surfaces/materials and shadow passes contribute calls; node count alone is
  not the budget. Use SPEC_GAME.md's measurement contract (450 hard limit, 260 target).
  Characters merge each body part (`CharacterModel._merge_parts()`; `part_count` keeps the pre-merge
  count); oaks, willows, dummies and clouds merge themselves in `_ready`. Props that show and hide (axe,
  rod, sword, stumps) stay separate. Check `tests/perf_report.tscn` after adding anything visible.
- **Vertex colours are not linearised.** In this renderer a vertex colour renders like the same value
  in the `albedo` uniform, so `MeshMerger` stores colours as-is. (The terrain still converts, because
  its tile colours were tuned that way from Milestone 1.)
- Don't name static functions after `Object` methods. `ItemDB.get_name()` clashed with
  `Object.get_name()`, so it's `display_name()`.
- **UI is built in code** with `UITheme` builders (`UITheme.button/label/panel/...`) and the shared
  theme. Modal panels (`SettingsPanel`, `ConfirmPanel`) free themselves and close on Esc. Anything that must
  work while paused sets `process_mode = PROCESS_MODE_ALWAYS`.
- **Game states** (`GameManager.State`): MAIN_MENU, CHARACTER_CREATION, CUTSCENE, PLAYING, PAUSED. The
  pause menu only opens in PLAYING. The world disables player, click and camera input during the intro
  through `world.set_gameplay_enabled()`.
- **Signals between systems.** Presentation listens to gameplay signals (for example, `ClickMarker` ←
  `NavigationController.destination_set`). Don't have gameplay code reach into UI nodes.
- **Model orientation.** Characters face local −Z. `PlayerController` rotates `CharacterModel`, not the
  body.
- Hand-written `.tscn` files: verify serialized transforms in the pinned engine. Prefer saving a
  known-good editor transform over guessing matrix ordering when generating a scene.
- Commit the `*.uid` and `*.import` files Godot generates. `.godot/` is ignored.
