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
