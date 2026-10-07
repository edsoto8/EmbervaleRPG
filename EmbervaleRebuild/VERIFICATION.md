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

## Milestone 5 — Graphics upgrade

- Import/parse: clean. The test runner now installs an engine `Logger` (`tests/error_catcher.gd`), so
  any runtime script error during a test fails that test.
- All suites pass (85 tests). `graphics` covers live presets (shadow distance, MSAA off/2x/4x, bloom
  and grading, vignette, decor fade 45/75/100 m, grass density 40%/100%, wind scope), persistence
  and the Settings control (default Medium), the baked water depth (shallow at the shore, deep
  offshore, negative over land; pond deep in the middle), wind weights surviving batching (rigid
  trunks, swaying canopies, anchored grass), wet sand and softened terrain transitions, the richer
  character (rim light, merged parts, every hair style), the new ground cover and glowing lanterns.
- Perf report (`docs/perf_m5.txt`, llvmpipe, HUD on): generation cold 1034 ms, warm median 807 ms;
  worst view 158 draw calls on High (limit 450, target 260); every view/preset passes.
- Same-camera M4/M5 captures: `docs/screenshots/m4/`, `docs/screenshots/m5/` (Medium, HUD hidden),
  side by side in `docs/screenshots/compare/`; Low/High samples in `docs/screenshots/m5_low|high/`.
- Normal rendered runs: only the driver's "Could not set V-Sync mode" warning (llvmpipe). Graceful
  shutdown verified with `tests/quit_check.tscn` (menu music playing, `GameManager.quit_game()`):
  no leaks. A raw `--quit-after` smoke run still reports 2 leaked ObjectDB instances because it
  bypasses that shutdown path (recorded separately, as CLAUDE.md asks).
- **Not done:** a video or live review of water, gusts, anchored stems and transitions in motion,
  and frame times on real GPUs.

## Milestone 6 — Skills and progression

- Import/parse: clean (72 scripts compile).
- All suites pass: 111 tests after the review fixes below (`world`, `flow`, `tutorial`, `polish`, `graphics`, `skills`,
  `playthrough`, `skills_playthrough`). `skills` covers the XP table (83 / 388 / 1,154 / 13,034,431),
  the cap, single notification for multi-level gains, every S10 formula, normal/oak/willow chopping
  with requirements, continuous loops, depletion after the log, the steel axe, Tobin's gear (and the
  repeatable full-inventory case), fishing loops, failed casts, stack growth in a full pack and the
  trout capacity rule, firemaking placement rules, failure-and-retry, fire burn-out, cooking order,
  burning and singeing, capacity reservation, the fire expiring mid-cook, eating and healing rules,
  regeneration (30 s, frozen while paused), Attack training to level 10, the shop (buy/sell one/all,
  refusals, freed-slot transactions, no partial changes), the tracker, pending rewards, the finale
  once, tasks during the tutorial, level tasks on import (paid once), the Skills panel, XP drops,
  level-up message/sparks/jingle, and save round-trips including older saves without skills.
- No-teleport skills playthrough from the end of the tutorial: Tobin's gear -> fishing -> chopping
  -> lighting a fire -> cooking -> eating -> selling to Marla -> buying the steel axe, by clicks and
  keys only with deterministic rolls; zero jumps. Diagnostic pacing (accelerated): movement 33 s,
  actions 41 s. Human pacing targets (5-15 min to the steel axe, 15-30 min for all tasks) are not
  measured here.
- Perf report (`docs/perf_m6.txt`): warm generation 832 ms; worst view 190 draw calls (courtyard
  with training), pond with fishing 186, every preset under the 260 target and 450 limit.
- Windows release export rebuilt; the pack runs cleanly on Linux and excludes the test scenes.
- Screenshots of the whole flow, including fishing, a fire, the Skills panel, the shop and training:
  `docs/screenshots/flow/`.
- **Not done (needs a person or hardware):** completing all ten tasks by hand and recording human
  pacing, a native Windows release smoke test, frame rates on the provisional i5-8250U/UHD 620
  laptop, listening to the audio, and live motion review.

## Final review

An independent code review against the specs found six issues, all fixed with regression tests
where practical: several pending task rewards could be paid more than once when a slot freed up;
Drop could discard a stack that changed while the confirmation was open; writing a new save over a
corrupt primary destroyed it (it is now preserved); lighting and fishing now recheck the tinderbox
and rod at completion; pending rewards that fit and logs already held are credited on load; a
pending interaction that gets stuck now says "You can't reach that."

## Graphics revamp and game-feel pass

- Terrain: flagstone plaza/courtyard (hashed shades, no checkerboard), meadow patches in the grass.
  Props: multi-lobed canopies with shaded undersides and root wedges, four-tier pines,
  timber-framed cottages with shutters/window boxes/door steps/chimney caps, bushier bushes with
  berries. Variation comes from position hashes, so the island RNG sequence and every prop position
  are unchanged (world suite: determinism, landmarks and reachability still pass).
- HUD/feel: hearts bar, centred level-up/task banner, message log fading after 8 s idle, minimap
  fires and fishing spots, hover ring under interactables, running dust, villagers looking at the
  player, ember emblem on the menu.
- All suites pass (111 tests). Perf (`docs/perf_revamp.txt`): worst view 210 draw calls (target 260,
  limit 450); warm generation 1221 ms (limit 1500) on a container that measured ~1.7x slower than
  the M6 run even on untouched stages. Generation was trimmed (path bounding-box rejects, deep-sea
  texels skipped in the depth bake) to keep margin.
- Screenshots: `docs/screenshots/flow/` (whole flow) and `docs/screenshots/revamp/` (fixed views).
