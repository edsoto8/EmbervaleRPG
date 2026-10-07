# Embervale — Driftwood Isle demo

A small single-player, low-poly fantasy RPG prototype in the spirit of classic early-2000s MMORPGs.
You arrive by boat on **Driftwood Isle**, a little training island, learn the basics from an
instructor, and then keep playing: chop, fish, light fires, cook, train and trade to level up your
skills.

Built with **Godot 4.7** and GDScript. Everything is generated procedurally at startup: terrain,
buildings, trees, characters, water and sound. There are no purchased or external assets, and no
network access is needed.

## Status

**Rebuild not started.** This directory contains the previous implementation, tests and screenshots
for reference. The checklist tracks the new version, not the state of those historical files. Build the
new version in a separate project directory and preserve this reference copy. The milestones are in
[PLAN.md](PLAN.md), and each one has to end in a runnable game with passing tests before the next begins.

| Document | What it's for |
|---|---|
| [SPEC_GAME.md](SPEC_GAME.md) | Authoritative base game (M1–M4), inventory, performance and pacing |
| [SPEC_SAVE.md](SPEC_SAVE.md) | Canonical JSON schema, legacy import, validation and failure behavior |
| [PLAN.md](PLAN.md) | Architecture, milestone checklist and verification gates (M1–M6) |
| [SPEC_GRAPHICS.md](SPEC_GRAPHICS.md) | Requirements for Milestone 5: lighting, water, wind, quality presets |
| [SPEC_SKILLS.md](SPEC_SKILLS.md) | Requirements for Milestone 6: skills, XP, shop, island tasks |
| [CLAUDE.md](CLAUDE.md) | Commands, conventions, historical engine gotchas and optional delegation workflow |

## The game

1. **Main menu** over a slowly orbiting view of the island: New Game, Continue, Settings, Exit.
2. **Character creation**: name, body type, skin tone, hair style and colour, shirt and pants colour,
   on a draggable turntable preview, with Randomize.
3. **Intro cutscene**: the boat sails up to the dock with you aboard, and the camera sweeps over the
   island while intro messages greet you by name. It can be skipped.
4. **The tutorial**: five objectives, tracked on screen and autosaved as each one completes:
   1. *Learn to move*: walk 4 m with WASD **and** click the glowing marker by the dock.
   2. *Meet the instructor*: talk to Instructor Maelis in the training courtyard.
   3. *Gather logs*: chop trees in the forest clearing until you have 3 logs.
   4. *Check your inventory*: open it with **I** and examine the logs.
   5. *Report back*: receive a **Beginner sword**, watch the camera pan to the exit gate, then reach
      the **Tutorial Complete** screen.
5. **After the tutorial**: Woodcutting, Fishing, Firemaking, Cooking and Attack on the classic RuneScape
   XP curve, Marla's market for buying and selling, and ten island tasks that pay coins.

**The island** has an arrival dock with a moored boat, a village (cottages, well, market stalls,
garden), a fenced training courtyard with dummies, a forest clearing, a fishing pond, and a walled exit
gate facing a distant mainland. **NPCs:** Instructor Maelis, Marla the merchant, Old Tobin by the pond,
and Pip, who wanders the plaza.

## Design decisions

These retain lessons from the previous build. [SPEC_GAME.md](SPEC_GAME.md) defines the current
requirements, and [CLAUDE.md](CLAUDE.md) records implementation guidance.

- **Compatibility (OpenGL 3) renderer**, so it runs on older and integrated GPUs. That rules out FXAA,
  so anti-aliasing is MSAA only.
- **Deterministic generation.** Fixed seeds for the island and terrain noise, and a separate RNG for
  decoration, so quest and test landmark positions never move.
- **Batch static props from the start.** `MeshMerger` merges static props into vertex-coloured chunks,
  and characters merge their own body parts. Budget: **≤ 450 draw calls** in the busiest view on every
  graphics preset, checked with `tests/perf_report.tscn` after anything visible is added.
- **Obstacle collision at least 1 m tall** and a navmesh step height of one cell, so the player never
  gets stuck on a stump the navmesh thinks it can climb.
- **Gameplay and presentation talk through signals.** Gameplay never reaches into UI nodes, and audio
  listens to system signals and explicit world events (such as footsteps and impacts).
- **Saves are backward-compatible.** Optional fields default when missing. Version 2 rebuild saves
  support an explicit import of reference version 1 saves; see [SPEC_SAVE.md](SPEC_SAVE.md).
- **A no-teleport playthrough test** is the definition of done for the tutorial and the skills loop,
  because teleporting tests can't catch places the player can't walk to.

## Controls

| Input | Action |
|---|---|
| W / A / S / D | Move forward / left / back / right (relative to the camera) |
| Shift (hold) | Run (with both keyboard and click movement) |
| Left click on the ground | Walk there (a yellow ✕ marks the destination) |
| Left click on an NPC, tree, fishing spot, fire, dummy or stall | Walk over and talk, chop, fish, cook, train or browse |
| E | Interact with the nearest NPC or object in reach |
| I | Open / close the inventory (click an item to examine it, then Light / Eat / Drop; Drop confirms permanent discard) |
| K | Open / close the Skills panel |
| Space / E / Enter, 1–3 | Continue dialogue / pick a dialogue choice |
| Mouse wheel | Zoom in / out |
| Middle mouse drag, or arrow keys | Rotate and tilt the camera |
| Esc | Pause menu (closes open panels first) |
| Space / Esc / Enter | Skip the intro cutscene or the closing gate sequence |

## Running the game

These commands run the reference project while the rebuild is unstarted. Use the new directory path
when it exists; the rebuild uses application/user-data name `EmbervaleRebuild`.

1. Install [Godot 4.7-stable](https://godotengine.org/download/archive/4.7-stable/) (the standard build, not .NET).
2. In the Godot Project Manager, choose **Import** and select `EmbervaleRPG/project.godot`.
3. Press **F5** (Run Project).

From a terminal: `godot --path EmbervaleRPG`.

The reference game saves and settings go to `user://savegame.json` and `user://settings.json`:
`%APPDATA%\Godot\app_userdata\Embervale\` on Windows, `~/.local/share/godot/app_userdata/Embervale/` on
Linux and `~/Library/Application Support/Godot/app_userdata/Embervale/` on macOS.

**Windows build:** install the export templates once (*Editor → Manage Export Templates*), then run
`godot --headless --path EmbervaleRPG --export-release "Windows Desktop" build/windows/Embervale.exe`.
`build/` is gitignored.

## Automated checks

The reference headless test runner (`tests/test_runner.tscn`) loads the real scenes and drives them with simulated
input. It redirects save and settings files, but that is not evidence of complete startup isolation.
The rebuild must isolate them before autoload initialization. Planned suites, one or more per milestone:

| Suite | Milestone | Covers |
|---|---|---|
| `world` | M1 | Generation, movement, click pathfinding, camera, boundaries |
| `flow` | M2 | Menu, settings, character creation, intro, pause, save and Continue |
| `tutorial` | M3 | All five objectives through real input paths, autosaves, NPCs |
| `polish` | M4 | Batching, ambient life, audio triggers, animation polish |
| `playthrough` | M4 | Menu → Tutorial Complete → Continue, **no teleporting**, with pacing report |
| `graphics` | M5 | Quality presets, water depth bake, wind, terrain shading, ground cover |
| `skills` | M6 | XP formulas, every skill, shop, island tasks, loading older saves |
| `skills_playthrough` | M6 | Tutorial end → steel axe, **no teleporting**, with pacing report |

See [CLAUDE.md](CLAUDE.md#commands) for commands. The rebuild must implement the
[verification gates](PLAN.md#milestone-verification-gates), including isolated file paths before
autoload startup and capacity/failure cases absent from some reference tests.

### What can't be verified automatically

Plan for a person to check these at the end of each milestone:

- **Running on real Windows.** The export can be built and its pack run on Linux, but the `.exe` itself
  needs a Windows PC (Wine has crashed before the engine starts).
- **Feel:** frame rate on real GPUs, mouse and camera sensitivity, smoothness on high-refresh monitors.
- **Window settings:** resolution and fullscreen changes are skipped under the headless display server.
- **How it sounds:** sounds are checked numerically (peak, RMS, clipping, loop points), not by ear.
- **How it looks:** screenshots are reviewed by eye, and tuning on a software renderer can differ
  slightly from real GPU drivers. Check wind and water in motion with a video or live run.

## Project layout (target)

```
EmbervaleRPG/
├── project.godot      # input map, autoloads, physics layer names, renderer settings
├── scenes/            # ui/ (main menu, character creation), world/ (island, environment), player/, camera/
├── scripts/
│   ├── autoload/      # Settings, Save, Inventory, Skills, Quest, Dialogue, Audio, Game (in that order)
│   ├── world/         # terrain, island builder, PropFactory, MeshMerger, interaction, skill objects
│   ├── player/        # PlayerController, NavigationController
│   ├── camera/        # CameraController
│   ├── characters/    # CharacterModel
│   ├── cutscene/      # IntroCutscene
│   ├── tutorial/      # TutorialDirector, TutorialDialogues (all dialogue content)
│   ├── skills/        # SkillData, SkillsDirector, shop
│   ├── items/         # ItemDB
│   ├── npc/           # villagers
│   ├── audio/         # Synth (every sound generated in code)
│   └── ui/            # UITheme, menus, HUD, panels
├── shaders/           # flat-shaded low-poly material, water, vignette
├── tests/             # test_runner.tscn + suites/, capture scenes, perf_report.tscn
└── export_presets.cfg # Windows Desktop
```

### Physics layers

| Layer | Name | Used by |
|---|---|---|
| 1 | ground | Terrain, dock and bridge decks |
| 2 | obstacles | Every solid prop (trees, houses, fences, rocks…) |
| 3 | boundary | Invisible shoreline, pond and dock-rail walls |
| 4 | player | The player body |
| 5 | interactables | NPC bodies and click areas around interactable objects |
| 6 | camera_blockers | Buildings and walls the camera must not pass through |

The navmesh is baked from layers 1–3. Clicks are ray-cast against layers 1, 2 and 5 (including areas),
so invisible walls never catch clicks and clicking a tree's canopy counts as clicking the tree.
