# Save and settings contract

This owns persistence for all milestones. Runtime settings are separate from adventure saves.
The new project uses application/user-data name **EmbervaleRebuild** so normal testing never overwrites
the reference game's `Embervale` files. Files are `user://savegame.json` and `user://settings.json`.
Test/capture/performance runs select isolated paths before autoload startup, never production paths.

## Compatibility policy

The rebuild writes schema **version 2** from M2 onward; optional M3/M6 fields gain defaults as listed
below. It reads earlier rebuild saves and supports an **explicit import** of reference-game version 1
saves from M2–M6. Import reads a selected copy, validates/migrates it and writes version 2 in the rebuild
directory; the original stays untouched. This import is a compatibility requirement, not automatic
discovery or a second save slot. Versions above 2 are rejected with an explanatory message; unknown
optional keys in supported versions are ignored. “Older saves load” means backward compatibility.

## Canonical schema

`hitpoints` is nested inside `skills`, never a top-level field in newly written saves. This complete
example represents a new character before the intro. Empty `inventory.slots` is expanded to 28 nulls
when loading. A missing `player` is intentional during intro. Appearance colours are six-digit RGB
strings without `#`; yaw is radians.

```json
{
  "version": 2,
  "saved_at": "2026-10-06T00:00:00Z",
  "character": {
    "name": "Adventurer",
    "appearance": {
      "body_type": 1,
      "skin_tone": "e0b48f",
      "hair_style": 1,
      "hair_color": "5a3a1e",
      "shirt_color": "2f4f7a",
      "pants_color": "8a6a2f"
    }
  },
  "stage": "intro",
  "quest": {
    "index": 0,
    "wasd_distance": 0,
    "marker_reached": false,
    "inventory_opened": false,
    "logs_inspected": false,
    "tasks": [],
    "pending_task_rewards": []
  },
  "inventory": {"slots": []},
  "skills": {
    "xp": {"attack": 0, "woodcutting": 0, "fishing": 0, "firemaking": 0, "cooking": 0},
    "hitpoints": 10
  }
}
```

For stage `island`, optionally add `"player": {"position": [4, 0.47, 50], "yaw": 0}`. This illustrates
the shape, not a guaranteed valid location; validate positions against the generated world. Slot entries
are null or, for example, `{"id": "logs", "qty": 3}`. Task fields contain task IDs from the skills spec.

| Field | Validation/default |
|---|---|
| version | Required integer 1 or 2; never silently reinterpret unsupported versions |
| saved_at | UTC timestamp when written; informational, not needed to load |
| character | Required dictionary; missing/wrong type rejects save |
| character.name / appearance | Validate with base spec; invalid/missing name → Adventurer; appearance fields independently default to base palette/enums |
| stage | Missing → island for legacy saves; only intro/island allowed; other values reject save |
| player | Missing/invalid → dock spawn; finite three-number position and finite yaw required; inaccessible positions reset to dock after navigation readiness |
| quest | Missing → tutorial index 0 with no progress; index integer clamped 0–5; distance finite and clamped 0–4; flags must be booleans, else false |
| quest.tasks | Unique known task IDs; missing → empty; unknown IDs ignored |
| quest.pending_task_rewards | Unique IDs also present in tasks; missing → empty; represents completed tasks whose coins remain unpaid |
| inventory | Missing → empty 28-slot inventory; at most 28 entries; unknown items, nonpositive/noninteger quantities or invalid structures reject save with explanation |
| skills.xp | Missing → zero for each skill; finite nonnegative numbers, clamped to XP cap in skills spec; unknown skills ignored |
| skills.hitpoints | Missing → 10; integer clamped 1–10 |

Quantities and coin arithmetic must remain within the exact-integer JSON range 1–9,007,199,254,740,991;
an operation exceeding this limit fails without mutation. Nonstackable slots have qty 1. Duplicate
stackable slots are consolidated if valid; too many resulting slots reject the save rather than lose items.
Validation completes before any runtime state changes. Wrong types for present containers reject the save;
absent optional containers use defaults. Never coerce malformed values into item grants.

Load inventory, then skills, then quest while progression/reward/save listeners are suppressed. Restore
player only after world navigation readiness. Resume into PLAYING for island saves, or replay intro for
intro saves. Transient actions, fire locations, regrowth timers, RNG state, camera zoom, dialogue and
modal panels are not saved; trees reset and fires disappear on reload. Hitpoint regeneration restarts
its 30 s timer; there is no offline regeneration or progress.

## Version 1 migration and repair

Reference version 1 uses the same character/stage/player/inventory/quest structures and
`skills: {xp, hitpoints}`; pre-M6 files omit skills/tasks. Apply the defaults above, set version 2 in
memory, and default pending rewards to empty (legacy completed tasks are treated as already paid).
If a legacy top-level `hitpoints` exists without nested `skills.hitpoints`, move it inside skills; nested
wins if both exist. Imported completed tutorials missing the sword receive one replacement, subject to
inventory capacity, before training is allowed; Maelis offers retryable recovery if full. Imported
skill levels meeting task thresholds mark those tasks complete once and pay their defined rewards if
not already in `tasks`; suppress duplicate grants on subsequent loads. Do not infer event tasks merely
from item ownership: purchased food must not count as player cooking.

Keep version 1 fixture files for character-only M2, quest/inventory M3–M5, and full M6 saves. Store them
under tests with synthetic data. Tests exercise actual migration and Continue, not direct state injection.

## Write timing and failure behavior

Save on successful character creation, intro finish/skip, completed tutorial objective, task completion,
pending reward payment, Save & Main Menu, Save & Exit and window close while an adventure is loaded.
No periodic autosave is promised: actions since the last listed checkpoint can be lost after a crash.
Task/objective state, reward and XP from the triggering action must be coherent in the same snapshot;
defer saves until the gameplay transaction and all its reports finish.

Write a temporary file, close/validate it, preserve a known-good backup and replace the destination.
Do not delete the only valid save before replacement succeeds. On corrupt primary, offer backup recovery
with a message; preserve the corrupt file for inspection. No valid file → Continue disabled. I/O failure
shows a visible error and keeps the previous save. Failed character replacement stays in creation;
failed Save & Main Menu/Exit stays in the game and offers retry or an explicit leave-without-saving
choice. A close request must not silently discard progress when saving fails.

## Settings

Persist `resolution: [width, height]`, `fullscreen`, `master_volume`, `mouse_sensitivity`, and from M5
`graphics_quality` (0 Low, 1 Medium, 2 High). Defaults/ranges are in the base and graphics specs. Unknown
keys are ignored; invalid values use their defaults, unsupported resolutions use 1280 × 720. Corrupt or
missing settings use defaults and never prevent startup. Failed settings writes show a message; changes
still apply in memory. New Game never resets settings. Tests set paths before settings are loaded.

## Acceptance

Cover round-trip saves at each milestone, optional-key defaults, version 1 import, unsupported versions,
corrupt primary/backup recovery, inaccessible positions, malformed inventories, write/replace failures,
cancelled New Game, atomic reward/XP snapshots, full-inventory pending rewards and no duplicate grants
after repeated Continue. Confirm production reference saves/settings remain untouched by test tools.
