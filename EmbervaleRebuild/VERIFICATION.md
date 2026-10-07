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
