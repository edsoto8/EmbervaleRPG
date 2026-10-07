# Base game specification — clean-slate rebuild (M1–M4)

This is the authoritative base-game specification. [SPEC_GRAPHICS.md](SPEC_GRAPHICS.md) and
[SPEC_SKILLS.md](SPEC_SKILLS.md) extend it; [SPEC_SAVE.md](SPEC_SAVE.md) owns persistence.
[PLAN.md](PLAN.md) schedules implementation. `CLAUDE.md` contains development guidance, not additional
product requirements. If documents conflict, fix the conflict before implementing the affected feature.

Numbers below preserve the reference game's behavior unless marked **rebuild improvement** or
**provisional target**. Existing scripts, scenes, tests and `docs/screenshots/` are historical reference
materials, not proof that any rebuild milestone is complete. Reimplement in a separate project directory
and preserve this reference project. The rebuild must be understandable from these specifications.

## Scope and technical baseline

Single-player, offline, English-language desktop fantasy RPG demo. The playable area is Driftwood Isle;
the mainland is scenery. No network services, multiplayer, combat enemies or death. All visual and audio
assets are generated in code; UI and the project icon may use code-authored vector shapes. No purchased
or imported third-party art. Use Godot **4.7-stable**, standard GDScript build, Compatibility renderer,
60 Hz physics and physics interpolation. Use matching export templates. Record any later engine upgrade
in the docs and revalidate rendering, saves and tests.

Windows Desktop is the release target; macOS and Linux are development platforms. Native Windows
validation is required before release. Engine baseline:
[Godot 4.7 stable archive](https://godotengine.org/download/archive/4.7-stable/).

## World and navigation (M1)

One unit is one metre; +X is east, −Z is north, Y is height. The terrain is a 128 × 128 m heightfield
with 1 m tiles and an irregular island approximately 46 m in radius. Sea height is 0; pond surface 0.18;
dock deck 0.42. Island RNG seed is 4242, terrain noise seed 1987 (frequency 0.045, two octaves).
Decoration and skill placement use independent RNGs, seeds 4343 and 4444. Cosmetic additions must not
change established navigation, landmarks or quest routes. Exact decorative placement is not an acceptance
requirement; the named regions, counts and accessible routes below are.

| Region | Required layout and content |
|---|---|
| Arrival dock | South coast at X = 4; 3 m deck width, moored boat, landward movement marker, rail boundaries |
| Village | Plaza centre (X, Z) = (0, 18), radius 6.5 m; well, market stalls, lamps, signpost, fenced garden |
| Cottages | Five; centres (−11, 12), (−12, 24), (11, 25), (−7, 33), (12, 14.5); doors face plaza |
| Courtyard | X 17–33, Z −2.5–10.5; paving, fence with west entrance at (18, 4), dummies and weapon rack |
| Forest | Clearing centre (−24, −12), radius 6.5 m; five normal choppable trees from M3, stumps and log pile |
| Pond | Centre (20, −22), radius 6.5 m; bank access, rocks and reeds; fishing added in M6 |
| Exit | North-coast gatehouse, walls, bridge and distant mainland; boundary prevents mainland travel |

Paths connect dock → village, village → courtyard, village → forest, village → pond and village → gate.
Place trees, houses and collision outside those routes. No swimming, jumping, building interiors or
step-up mechanic. Shoreline, pond and dock rail boundaries prevent falls into inaccessible water.

`TutorialIsland.landmarks` exposes ground-supported `Vector3` positions: `dock`, `move_marker`,
`village`, `courtyard`, `courtyard_entrance`, `forest_clearing`, `fishing_pond`, `exit_gate`,
`npc_instructor`, `npc_merchant`, `npc_fisher`, `npc_wanderer`, `training_dummy`; M6 adds `oak_tree`
and `willow_tree`. Spawn on the dock facing north. Maelis stands at (21.5, 4); the representative dummy
at (27.6, 4); Marla faces the plaza; Tobin stands on the pond's south bank; Pip wanders within 5 m of
their plaza home. Heights come from generated ground, not hardcoded flat Y values.

Bake navigation from ground, obstacle and boundary layers. Cell size/height 0.25 m, agent radius 0.5 m,
height 1.75 m, maximum climb 0.25 m and slope 40°. Expose `navigation_ready` and a readiness flag after
bake and map synchronization. All landmarks and usable objects must have reachable approach points.
Solid low props use sufficiently tall collision (about 1 m) to remain navigation obstacles.

## Movement, camera and interaction

| Parameter | Value |
|---|---|
| Walk / run | 3.4 / 6.2 m/s; Shift works with keyboard and click movement |
| Acceleration / turning | 30 m/s² / interpolation factor `min(12 × delta, 1)` |
| Path waypoint / arrival tolerance | 0.35 / 0.3 m |
| Click projection / stuck timeout | Reject ground targets over 3 m from walkable ground; cancel after 1.25 s without progress |
| Camera initial distance / pitch / yaw | 14 m / 48° / 0 radians |
| Zoom | 5–24 m; wheel step 1.5 m; smoothing rate 10 |
| Camera follow | Focus 1.1 m above player; smoothing rate 10 |
| Orbit | Pitch 28–72°; middle drag 0.35°/pixel × user sensitivity; arrow keys 110°/s |
| Click interaction ranges | NPC 2 m; tree 1.7 m; fish 3 m; fire 1.8 m; dummy 1.9 m; stall 3.2 m |

WASD is camera-relative and diagonal speed is normalized. Keyboard input cancels click navigation and
pending interactions immediately. Camera orbit/zoom never cancels movement. Buildings and walls on
`camera_blockers` pull the camera inward; trees and small props do not. Models face local −Z.

Ground clicks show a yellow destination cross. Click an object to walk within its range and use it once;
E uses the nearest object within its range plus 1 m, without auto-walking. Hover shows verb and name
with a hand cursor. Objects implement `interaction_verb/name/range/position()` and `interact(player)`
and join `interactable`. Failed/unreachable interactions post a message and leave controls usable.

**Rebuild improvement:** only one timed action or pending interaction may own player control. Moving,
clicking a new destination or starting a different action cancels the old action before any reward or
consumption. Pausing freezes action and world timers. Dialogue/shop/completion modals cancel actions
and block world input; UI clicks never move the player. Inventory/Skills panels allow gameplay to continue
but consume their own input. Esc closes the topmost panel first, otherwise opens pause during PLAYING.

## Menu, character and intro (M2)

Main menu: slowly orbiting island, title, New Game, Continue, Settings and Exit. Continue is enabled only
for a valid supported save. New Game asks before replacing a save; backing out of character creation
preserves the old save. Replacement happens only after successful character creation and saving.

Names are trimmed, 1–12 ASCII letters/digits with single spaces between words, matching
`^[A-Za-z0-9]+( [A-Za-z0-9]+)*$`. Invalid names show a reason and disable Create. Body types: Slim,
Average, Broad (0–2); hair: Bald, Short, Long, Ponytail, Mohawk (0–4).

| Palette | Six-digit RGB options, in order |
|---|---|
| Skin | f3d2b3, e0b48f, c68e63, 9c6a43, 6e4a2f, 4a3121 |
| Hair | 2b2018, 5a3a1e, a5662f, d8b45a, b8452c, 8c8c8c, f0ead6 |
| Shirt/pants | 7a2e2e, 2f4f7a, 3e6b35, 8a6a2f, 5b3d6e, c9c1a8, 3a3a3a, b5622a |

Default: Average, skin e0b48f, Short hair 5a3a1e, shirt 2f4f7a, pants 8a6a2f. Preview rotates at
0.6 rad/s; drag outside UI rotates at 0.012 rad/pixel, pausing auto-rotation for 2 s. Randomize changes
all appearance fields and supplies a suggested name only if the name is empty. Appearance persists
identically into gameplay and dialogue portraits.

Settings apply immediately and persist separately: windowed 1280 × 720 default; supported resolutions
1280 × 720, 1600 × 900, 1920 × 1080, 2560 × 1440; fullscreen false; master volume 0.8 in [0, 1];
mouse sensitivity 1.0 in [0.25, 2.5]. M5 adds graphics quality, default Medium. UI uses `canvas_items`
stretch, remains readable at 720p, and supports keyboard focus/activation in menus and dialogue.

Intro: 14.6 s total, boat arrival 10.5 s, player becomes visible on dock at 11 s; letterbox and island
flyover settle into the gameplay camera. Show these messages in order:

1. **Welcome, {name}.** Every legend of Embervale began with a single voyage. Yours begins today.
2. **Driftwood Isle.** A small island where new adventurers learn to find their way, speak with the
   locals and gather what they need.
3. **Your journey begins.** Step onto the dock and explore. Move with WASD, or click where you want to go.

Skip button, Space, Esc and Enter all produce the same final state as watching: moored boat, player on
dock, gameplay camera and enabled controls, stage `island`, saved once. Never duplicate a player or award
progress when skipping. Mid-intro saves restart the intro on Continue. Scene fades last 0.35 s per side.
Pause offers Resume, Settings, Save & Main Menu, Save & Exit. Window close uses the same graceful save
and audio shutdown path. Menu-only sessions and direct world-scene runs must not create a save.

## Tutorial, NPC dialogue and HUD (M3)

Objectives complete in order, autosaving after their complete state and rewards are committed:

| ID | Completion rule |
|---|---|
| learn_to_move | Accumulate 4 m of actual keyboard movement, then reach the dock marker via click navigation within 1.6 m; either substep may occur first |
| talk_to_instructor | Finish Maelis's introductory conversation, including accepting the three-log assignment |
| collect_logs | Own at least 3 normal logs; logs obtained early count when this objective activates |
| inspect_inventory | Have inventory open during this objective and examine owned normal logs; earlier inspections do not count |
| return_to_instructor | Finish Maelis's reward conversation and successfully receive one Beginner sword |

Normal trees give one log after a cancellable 2 s chop, become stumps and regrow after 20 s. A basic axe
is an implicit animation/tool, not a required inventory item. The three tutorial logs are not consumed
by Maelis. If discarded or used, gather more. Rewards never duplicate on repeating dialogue or Continue.

Dialogue has typed text, live character portrait, Continue and up to three numbered choices. Space/E/
Enter first reveals unfinished text, then advances; 1–3 chooses a displayed option. Gameplay movement is
disabled while talking and the message log is hidden. Content belongs in `TutorialDialogues`.

| Speaker / state | Required conversation content and actions |
|---|---|
| Maelis, before movement objective | Explain WASD and the marker; no progression |
| Maelis, introduction | Greet by name, describe training; choices about island, residents or readiness; informational branches return to choices; ready assigns 3 logs west of village |
| Maelis, gathering | Report current normal-log count out of 3 and explain click/E chopping |
| Maelis, inventory | Explain I and examining logs |
| Maelis, return | Congratulate by name, give sword once, explain northern gate, accept thanks; only successful reward delivery finishes tutorial |
| Maelis, afterward | Wish player safe travels; mention practice activities and dummies |
| Marla, during tutorial | Explain trade unlocks after training |
| Marla, afterward | Direct player to stall and mention buying logs/fish and selling steel axe |
| Tobin, missing gear (M6) | Offer borrowing gear or leaving; accepting gives missing rod/tinderbox and explains fishing/fire/cooking |
| Tobin, equipped (M6) | Give fishing/cooking tip; mention trout when Fishing ≥ 5 |
| Pip | Say they arrived/hope to become an adventurer; player encourages practice |

Dialogue wording and line counts may be edited if these branch outcomes and actions remain. Test behavior,
not incidental line counts. Avoid suggesting the mainland is already playable. Marla's shop opens from
the stall after tutorial completion, not from a dialogue choice.

HUD: hitpoints (10 before M6), minimap with island/player facing/NPCs/objective star, five-objective
tracker with substep checklist, message log, Inventory button; M6 adds Skills and XP drops. Final tracker
title is **Ready for adventure**, with island tasks below it. The gate camera pan lasts 7.2 s and can be
skipped with the intro controls; it ends at **Tutorial Complete**, offering Continue Exploring or Return
to Main Menu. Continue restores a completed tutorial without replaying rewards or the closing sequence.
The gate remains scenery; Continue Exploring stays on the island.

## Inventory and transactions

28 slots in a 4 × 7 grid, each empty or `{id, qty}`. Logs, all raw/cooked/burnt fish, bread and coins
stack in one slot per item ID; sword, rods, tinderboxes and steel axe use one slot per item. No gameplay
stack cap; quantities must remain positive integers within safe numeric limits (see save spec).
Full means an addition cannot fit, not simply that all 28 slots are occupied. Existing stacks can grow.
Clicking an item examines it and shows applicable actions; M6 supplies Light/Eat/Drop.

**Rebuild improvements:** reward delivery, buying, selling and cooking transformations are transactions.
Preflight the final inventory, including slots freed by consumption/payment, before changing anything.
Cooking must reserve capacity for either cooked or burnt output. Failure grants no XP, removes no items
or coins, leaves progress incomplete and explains how to make room. Tutorial sword delivery remains
retryable. Task rewards that cannot fit remain pending and are paid once when room exists; save pending
rewards explicitly. A task pays before its autosave, never again on reload.

Drop permanently discards the selected item's entire stack, creates no world object, and asks for
confirmation showing quantity. Beginner sword cannot be dropped or sold. Tobin replaces missing basic
rod/tinderbox for free, with repeatable requests if capacity is insufficient; an oak rod counts as having
a rod. A discarded upgraded tool can be repurchased. No inventory capacity failure may softlock training.

## Polish and acceptance (M4)

Smooth facing, idle glances, talk gestures, objective cheer, stride footsteps; circling clouds, gulls,
chimney smoke, tree shake and wood chips. Batch static props; animated/hidden parts remain independent.
Small decor fades at 75 m before M5. Generate music, shore-distance surf, birds, footsteps, chop, pickup,
UI click, dialogue, inventory, objective jingle and tutorial fanfare, routed through Music/Ambience/SFX
and Master. Slow synthesis may run on a worker with its own RNG. Shutdown releases audio gracefully.

Use [PLAN.md](PLAN.md#milestone-verification-gates) for per-milestone gates. Tests must isolate save/settings
paths before autoloads read or write them. Unit fixtures may teleport; playthroughs use real input and
continuous reachable routes, without direct progress setters. Test cancellation, full inventories,
skip/reload, reward retry and input blocked by UI as well as successful paths. Visually inspect fixed
views and manually check sound, window settings and camera feel. Screenshots alone cannot verify motion.

## Performance and pacing contract

Hard render limit: **≤ 450 total draw calls per frame**, including shadow passes, in every measured view
on every preset. **≤ 260 is an optimization target**, not a second acceptance limit. Test at 1280 × 720
with a real Compatibility renderer, fixed seed, VSync off and warmed scene. Measure dock (yaw 0 rad,
distance 14 m, pitch 48°), village (0.6, 16, 45°), forest (0.8, 18, 50°), and overview focused at
(0, 0, 4), (0, 95, 72°). Collect at least 120 frames after 30 warmup frames and report peak draw calls.
M6 adds the pond with fishing/fire effects and courtyard with training effects active.

Generation limit: **< 1.5 s median across five warm loads**, from world instantiation until
`navigation_ready`, including terrain, collision, batching, water bake and navigation. Report cold-load
time separately. Do not substitute CPU node-construction time for playable-world readiness.

**Provisional hardware target:** Windows laptop, Intel Core i5-8250U/UHD 620, 8 GB RAM; Low at 720p aims
for ≥ 30 FPS (95th-percentile frame time ≤ 33.3 ms) over a 60 s route. Record actual CPU/GPU/driver/OS,
engine and release build with results. This is a proposed baseline, not a measured support claim;
confirm it on an available reference PC before declaring release performance complete. Medium/High
use the same draw-call gate, with frame times reported on the tested hardware.

**Provisional human pacing targets:** tutorial 5–10 min without skipping dialogue; tutorial-end → steel
axe 5–15 min; all island tasks 15–30 min after tutorial. Report movement, dialogue, action and idle time
separately. Deterministic accelerated/headless playthrough timings are diagnostic, not substitutes for
human pacing validation. Tune targets/formulas explicitly if playtesting disagrees.
