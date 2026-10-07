# Embervale rebuild

The clean-slate rebuild of the Driftwood Isle demo, built from the specifications one directory up
([SPEC_GAME.md](../SPEC_GAME.md), [SPEC_SAVE.md](../SPEC_SAVE.md), [SPEC_GRAPHICS.md](../SPEC_GRAPHICS.md),
[SPEC_SKILLS.md](../SPEC_SKILLS.md)) and scheduled by [PLAN.md](../PLAN.md).

- **Engine:** Godot **4.7-stable** (standard build, not .NET), `4.7.stable.official.5b4e0cb0f`.
  Compatibility (OpenGL 3) renderer.
- **Flow:** `run/main_scene` is the main menu. Saves happen on character creation, when the intro
  finishes or is skipped, at checkpoints, on Save & Main Menu / Save & Exit and on window close.
- **User data:** application/user-data name `EmbervaleRebuild`, so the reference game's `Embervale`
  saves and settings are never touched. Saves: `user://savegame.json`; settings: `user://settings.json`.
- **Everything is procedural:** terrain, props, characters, water and (from M4) audio are generated in
  code. No imported art.

## Running

1. Install [Godot 4.7-stable](https://godotengine.org/download/archive/4.7-stable/).
2. Import `EmbervaleRebuild/project.godot` in the Project Manager and press **F5**, or run
   `godot --path EmbervaleRebuild`.

Controls are listed in the [top-level README](../README.md#controls).

## Checks

Run from this directory. Wrap unattended runs in a timeout (GNU `timeout`, macOS `gtimeout`, or your
tool's deadline): a script that fails to compile makes the runner hang instead of exiting.

```bash
godot --headless --editor --path . --import --quit                          # rebuild class cache, report parse errors
godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn        # all suites; exit code 0 = pass
godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- world   # one suite
godot --headless --path . --fixed-fps 60 --quit-after 600                    # smoke-run the main menu ~10 s
godot --headless --path . res://tests/check_scripts.tscn                      # every script compiles
godot --path . --rendering-driver opengl3 --fixed-fps 60 res://tests/capture_screenshots.tscn -- <out_dir>  # flow screenshots
godot --path . --rendering-driver opengl3 --fixed-fps 60 res://tests/capture_views.tscn -- <out_dir>  # fixed views
godot --path . --rendering-driver opengl3 res://tests/perf_report.tscn [-- <report.txt>]           # draw calls + generation
```

godot --headless --path . --export-release "Windows Desktop" build/windows/Embervale.exe            # needs 4.7-stable export templates
```

```bash
godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- playthrough  # no-teleport tutorial run + pacing report
```

On Linux without a display, prefix the rendering commands with `xvfb-run -a -s "-screen 0 1280x720x24"`.

Test, capture and perf scenes (anything under `res://tests/`) and runs given the `--isolated` user
argument store data in `user://test_runs/<pid>/`, chosen before any autoload starts (`AppPaths`). The
`EMBERVALE_DATA_DIR` environment variable overrides the data directory explicitly.

`tools/gen_project.py` regenerates the `[input]` section of `project.godot`.

## Status

See the checklist in [PLAN.md](../PLAN.md). Results of the latest verification run are recorded in
[VERIFICATION.md](VERIFICATION.md).
