# Verification log

Automated results from the development container (Linux, Godot 4.7-stable, Mesa llvmpipe software
renderer under Xvfb). Software-renderer frame times are not representative of real GPUs; draw-call
counts and generation times are. Native Windows and real-hardware checks are listed as not done.

## Milestone 1 — Playable world

- Import/parse: clean.
- `world` suite: 17 passed, 0 failed (generation, determinism, landmark reachability, keyboard speed and
  direction, diagonal normalisation, run speed, camera-relative movement, click-to-walk with marker,
  keyboard cancelling click navigation, pathing around a cottage, far-water click rejection, dock/pond/
  shore boundaries, zoom/pitch clamps, orbit not cancelling movement, camera pull-in at buildings,
  obstacle collision heights).
- Perf report (1280 × 720, llvmpipe): generation cold 632 ms, warm median 493 ms (< 1500 ms).
  Peak draw calls: dock 43, village 38, forest 28, overview 18 (hard limit 450, target 260).
- Fixed-view captures inspected by eye (dock, village, forest, courtyard, pond, gate, overview).
- Not verified here: walking every route by hand, camera feel on real hardware.

## Milestone 2 — Introductory experience

- Import/parse: clean (`tests/check_scripts.tscn`: every script compiles).
- `world` + `flow` suites: 43 passed, 0 failed. `flow` covers isolated data paths, menu Continue state,
  settings apply/persist/sanitise/corrupt file/write failure, the settings panel, name validation,
  creation validation, Randomize (all fields change, name suggested only when empty) and drag/auto
  rotation, creation saving and starting the intro, intro skip via Space/Esc/Enter/button and watching
  to the end (identical final state, single save, player appears at 11 s, three messages in order),
  mid-intro save replaying the intro, Continue restoring position, pause/resume, inaccessible
  positions resetting to the dock, cancelled New Game keeping the old save, creation save failure,
  Save & Main Menu failure with retry, window close failure and retry, direct world runs never saving,
  schema validation rules, newer-version rejection, atomic write failures at each step, corrupt
  primary recovery from backup (damaged file preserved), and version 1 imports (three fixtures).
- Smoke run of the main menu (`--quit-after 600`): no errors or warnings.
- Screenshots inspected (`tests/capture_screenshots.tscn`): main menu, settings, character creation,
  intro boat/flyover/dock, gameplay, pause.
- Not verified here: window resolution/fullscreen changes (skipped under the headless display server),
  character preview feel and camera hand-off on real hardware.

## Milestone 3 — Tutorial systems

- Import/parse: clean (all scripts compile).
- `world` + `flow` + `tutorial`: 67 passed, 0 failed. `tutorial` drives every objective through real
  input (WASD, clicks projected from the camera, E, I, Space/number keys, HUD buttons): movement in
  both orders and the click-only marker rule, Maelis before movement (no progress), the introduction
  with informational branches returning to choices and the reveal-then-advance key behaviour,
  dialogue blocking movement and world clicks, clicking trees to walk and chop to three logs, 2 s
  chops cancelled by movement, pause freezing a chop, full-inventory chop refusal, early logs counting
  on activation, inventory inspection rules (panel must be open during the objective; earlier
  inspections don't count), Esc closing the inventory before pausing, the full-inventory sword retry
  ending in the gate sequence and Tutorial Complete with completion and sword saved together, no
  replay or duplicate sword on Continue, the gate sequence watched for 7.2 s and Return to Main Menu,
  NPC presence/dialogue and Pip's 5 m wander, reaching Marla across her counter, hover text, UI clicks
  never moving the player, confirmed Drop with the sword protected, a mid-tutorial save round trip,
  and the imported completed-tutorial sword repair (once; retryable through Maelis when full).
- Screenshots inspected: tutorial HUD, dialogue with live portrait, inventory, gate pan, Tutorial
  Complete.
- Not verified here: completing the tutorial by hand on real hardware.

## Milestone 4 — Polish

- Import/parse: clean (all scripts compile).
- All suites (`world`, `flow`, `tutorial`, `polish`, `playthrough`) pass. `polish` covers batching
  (no loose static shared-material meshes; boat, dummies and choppable trees kept separate), 75 m
  decor fade, clouds/gulls/chimney smoke moving, two axe strikes per chop (shake, chips, chop sound),
  audio triggers (menu/island music, ambience, UI click, wooden footsteps, inventory, jingle, pickup,
  dialogue, fanfare), surf quieter inland, numeric checks of every synthesised sound (no clipping,
  audible RMS, seamless loops), deterministic worker renders, turn-to-face, talk gesture, cheer,
  idle glances, stride footsteps, and Save & Exit stopping audio before a real-time wait.
- No-teleport playthrough: main menu -> typed name -> full intro -> five objectives by clicks and
  keys -> gate sequence -> Tutorial Complete -> Return to Main Menu -> Continue (completed tutorial,
  one sword, position restored). Zero frame-to-frame jumps. Diagnostic pacing (accelerated,
  dialogue advanced instantly): movement 46 s, dialogue 1 s, action 6 s, idle 0.3 s, cutscenes 22 s.
  Human pacing (target 5-10 min) is not measured here.
- Perf report (`docs/perf_m4.txt`, llvmpipe, HUD included): generation cold 795 ms, warm median
  560 ms; worst view 106 draw calls (limit 450, target 260).
- Windows release export (`--export-release "Windows Desktop"`) builds `Embervale.exe` + `.pck`
  with the 4.7-stable templates; the exported pack runs cleanly on Linux headless and rendered.
  **Not done:** running the `.exe` on a real Windows PC, frame rate on real GPUs, listening to the
  audio by ear, live motion review.
- M4 captures retained for M5 comparison: `docs/screenshots/m4/` (same cameras as
  `tests/capture_views.tscn`).
