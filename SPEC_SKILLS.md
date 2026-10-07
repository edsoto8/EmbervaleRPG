# Spec addendum: Skills and progression (Milestone 6)

This extends [SPEC_GAME.md](SPEC_GAME.md) and [SPEC_GRAPHICS.md](SPEC_GRAPHICS.md) at Milestone 6.
In the planned M5 build the tutorial is complete, but afterward there is nothing to do.
This milestone adds the classic gather → process → use loop with experience and levels, so the
island is fun to keep playing.

## 1. Goal

Every few seconds of play should move a number up. Players chop, fish, light fires, cook, eat and
train, and they earn coins to buy better tools. A short list of island tasks gives them something to
aim for after the tutorial.

## 2. Constraints (carried over)

- Same art direction and everything procedural: tools, fish, fires, icons and sounds are built in code.
- Compatibility renderer. Use the shared [performance contract](SPEC_GAME.md#performance-and-pacing-contract):
  ≤ 450 draw calls on every preset, generation < 1.5 s including navigation readiness.
- The rebuilt M3/M4 tutorial retains its five objective outcomes, dialogue branches and no-teleport
  route. Tests follow the base spec's behavioral contracts. Chopping now also gives Woodcutting XP.
- Earlier rebuild saves and explicitly imported reference-game saves must load, as defined in
  [SPEC_SAVE.md](SPEC_SAVE.md); absent skills start at zero XP and full health.
- Gameplay logic stays out of the UI. Systems talk through autoload signals, as before.

## 3. Features

### S1. Skills, experience and levels
- Five skills: **Woodcutting, Fishing, Firemaking, Cooking and Attack**, plus **Hitpoints** (10).
- RuneScape-style XP curve: level 2 at 83 XP, level 5 at 388 and level 10 at 1,154, up to level 99.
- Each XP gain shows a small floating "+25 Woodcutting" drop by the minimap.
- A level-up posts "Congratulations, your Woodcutting level is now 5.", plays a jingle and sends a
  burst of gold sparks around the player.
- A **Skills** panel (button, or **K**) lists every skill with its level, XP and a progress bar to
  the next level.

### S2. Woodcutting
- The five tutorial trees are normal trees (level 1, 25 XP, one log, then a stump).
- **Oak trees** (level 5, 40 XP) and **willow trees** (level 10, 65 XP) are new. They can give several
  logs before they fall, and the player keeps chopping until the tree falls, the pack is full or they
  move.
- Chopping gets faster with level and with a better axe.
- Trees above the player's level say "You need a Woodcutting level of 5 to chop this tree."

### S3. Fishing
- Old Tobin gives a **fishing rod** and a **tinderbox** when asked.
- Two **fishing spots** ripple near the pond's south shore. Clicking one walks to the bank and casts.
- The player keeps fishing until they move or the pack fills.
- They catch **raw shrimp** (level 1, 10 XP). From level 5 they sometimes catch **raw trout**
  (50 XP).
- The catch rate rises with level.

### S4. Firemaking
- Selecting logs in the inventory offers **Light** (this needs a tinderbox).
- The player kneels, and a fire springs up in front of them. It burns for 60 s, then fades to ashes.
- XP: 40 for logs, 60 for oak logs, 90 for willow logs (levels 1 / 5 / 10).
- Lighting can fail at low levels ("You fail to light a fire"), and the player then tries again
  automatically.
- No fire can be lit on the dock or bridge, inside the plaza or courtyard, or next to another fire.

### S5. Cooking and eating
- Clicking a fire while carrying raw fish cooks it, one fish after another until none are left.
- Shrimp: level 1, 30 XP. Trout: level 5, 70 XP.
- The burn chance falls with level, and nothing burns from about 15 levels above a fish's level.
- Burnt fish is worthless, and burning food can singe the player's fingers (−1 hitpoint).
- Selecting cooked food offers **Eat**. Shrimp heals 3 hitpoints and trout heals 7.
- Hitpoints also regenerate slowly (1 every 30 s) and never drop below 1, because there is no combat
  yet.

### S6. Attack training
- The courtyard dummies can be attacked once the player has the Beginner sword. Each swing takes
  1.2 s, gives 8 Attack XP and makes the dummy wobble.
- Dummies teach nothing past Attack level 10, like the classic game's training dummies.

### S7. Coins and the shop
- **Coins** are a stackable item.
- After the tutorial, clicking Marla's stall (**Browse Market stall**) opens a shop panel. Her chat
  stays a single line, because a tutorial test relies on it; it mentions the stall instead.
- **Selling:** logs (2 / 5 / 8 coins for normal / oak / willow), raw and cooked fish (shrimp 1 / 4,
  trout 5 / 12).
- **Buying:**
  - **Steel axe** (60 coins): action duration multiplied by 0.70
  - **Oak fishing rod** (45 coins): +15 percentage points catch chance
  - spare **Tinderbox** (5 coins)
  - **Bread** (6 coins): heals 2
- The player's best tool is used automatically.

### S8. Island tasks
After Tutorial Complete, the quest tracker lists **Island tasks** under its "Ready for adventure"
title, showing the next three tasks not yet done:

1. Catch a shrimp
2. Light a fire
3. Cook a fish
4. Eat some food you cooked
5. Chop an oak tree
6. Sell something to Marla
7. Buy the steel axe
8. Reach Attack level 5
9. Chop a willow tree
10. Reach level 10 in any skill

Tasks count during the tutorial and may complete in any order, even when not among the three displayed.
Show the tracker after the tutorial. Reward once per task, with pending delivery when inventory cannot
accept coins. Finishing all of them shows "Driftwood Isle mastered!" with a fanfare once, not on reload.
Use activity events, not generic item acquisition, to distinguish cooking from buying cooked food.
Eating player-cooked shrimp/trout counts even at full health; bread does not satisfy that task. Since
fish stacks have no provenance, require that the cook-fish task has completed and that the player eats
shrimp/trout; do not require per-fish provenance. Level tasks check current XP on migration as well as
level-up events.

| Task ID | Coins |
|---|---:|
| catch_shrimp | 10 |
| light_fire | 10 |
| cook_fish | 10 |
| eat_cooked | 10 |
| chop_oak | 15 |
| sell_item | 10 |
| buy_steel_axe | 20 |
| attack_5 | 20 |
| chop_willow | 25 |
| level_10 | 50 |

### S9. Saving
The save gains `skills: {xp, hitpoints}` and island tasks/pending rewards inside `quest`. There is no
top-level `hitpoints` field. [SPEC_SAVE.md](SPEC_SAVE.md) defines versions, migrations, validation,
checkpoint timing and transaction ordering. Older saves without skills load with every skill at level 1.

### S10. Exact balance and activity rules

These numbers preserve reference `SkillData` behavior. `L` is the current skill level, `R` the required
level, `clamp(x, lo, hi)` bounds x. Reject an action below R before consuming anything or rolling luck.

| Tree | R | XP/log | Base seconds/log | Depletion chance/log | Regrow seconds |
|---|---:|---:|---:|---:|---:|
| Normal | 1 | 25 | 2.0 | 1.0 | 20 |
| Oak | 5 | 40 | 2.6 | 0.30 | 25 |
| Willow | 10 | 65 | 3.0 | 0.25 | 30 |

Place four oaks along the forest's outer edge and three willows around the pond, leaving the south
fishing bank clear. Chopping time = base × `clamp(1 − 0.03 × (L − R), 0.55, 1)` × axe multiplier
(0.70 with steel axe, otherwise 1). Award one log/XP before rolling depletion. The basic axe is implicit.

Fishing casts last 2.4 s. Catch probability = `clamp(0.40 + 0.04 × (L − 1), 0.40, 0.85)` plus
0.15 with oak rod, capped at 1. Successful catches roll trout probability: zero below level 5;
otherwise `clamp(0.25 + 0.03 × (L − 5), 0.25, 0.60)`. Failed casts grant no XP/item. Before a cast,
require capacity for every eligible output type; existing stacks can accept more even with 28 occupied
slots. Fish until movement/cancellation or output capacity fails, not a fixed stack-size limit.

Lighting attempts last 1.8 s; success probability `clamp(0.60 + 0.05 × (L − R), 0.60, 1)`.
Failure consumes no log/XP and retries; success consumes one log and lights one fire, not a repeating
log-burning loop. Place it 1 m ahead on accessible dry terrain, ≥ 2 m from other active fires, outside
plaza/courtyard with 0.5 m margin, clear of obstacles within 0.45 m. Dock, bridge, water and inaccessible
ground are forbidden. Revalidate placement and inventory at completion. Fire burns 60 s including a
3 s fade, then disappears; it must cancel a waiting cook safely. Fires are not restored on Continue.

Cooking lasts 1.8 s/fish, eligible trout before shrimp. Burn-free levels are 16 for shrimp and 20 for
trout. Below that level, burn probability = `0.55 × (stop_burn − L) / (stop_burn − R)`; above it, zero.
Success gives the specified Cooking XP; burning gives burnt fish and zero XP, with independent 0.35
chance of −1 HP. Reserve capacity for either result before starting; failure preserves raw fish.
Stop on movement, expired fire or no eligible raw fish/capacity. Eating lasts 1 s, consumes one item,
heals up to 10 HP, and is allowed at full HP. HP regen grants 1 per uninterrupted 30 s of PLAYING while
below maximum; pause freezes the timer, full HP resets it. HP cannot fall below 1.

Attack swings give 8 XP each at 1.2 s; stop once level 10 is reached (no new swing at level 10).
All activities use the shared cancellable action API and grant nothing for an interrupted attempt.
Best owned tool applies automatically; no equipment slots or consumable tools. Roll checks through
`SkillsManager.chance()` so tests can provide deterministic rolls.

XP threshold for level n is `floor(sum(floor(i + 300 × 2^(i/7)), i=1..n−1) / 4)`; level 1 is 0.
Level is the highest threshold reached, capped at 99. Total XP caps at 1.5 × the level-99 threshold
(13,034,431); progress at level 99 is 100%. One gain crossing several levels emits one notification
with the final level. Keep fractional XP in saves; never store levels separately.

Stacking and capacity follow [SPEC_GAME.md](SPEC_GAME.md#inventory-and-transactions). Items Marla buys:
normal/oak/willow logs 2/5/8; raw shrimp/trout 1/5; cooked shrimp/trout 4/12; bread 2. Burnt fish and
tools/sword cannot be sold. Bread heals 2; shrimp 3; trout 7. Shop stock is unlimited, buys one item per
click, sells one or all of a selected item. Reject buying a second steel axe/oak rod; spare tinderboxes
are allowed. Transactions preflight final coin/output capacity and commit atomically. Tobin replaces
missing basic gear for free. Drop is confirmed permanent discard, with sword protected.

## 4. Acceptance criteria

1. Everything in section 3 works in game through real input (clicking, E, the inventory buttons, the
   shop panel).
2. A new **skills** test suite covers:
   - the XP table, level-ups, level requirements, tool bonuses and chance formulas
   - every activity giving XP and items
   - burning and eating, the shop, island tasks, the Skills panel and XP drops
   - save/load, including loading an old save
3. A **no-teleport skills playthrough** starts after the tutorial and covers: get the rod from
   Tobin, catch fish, light a fire, cook, eat, sell to Marla and buy the steel axe.
4. All previously implemented rebuild suites still pass, including the tutorial playthrough; add
   checks for new behavior without weakening earlier objective/navigation expectations.
5. The performance budget is still met (`tests/perf_report.tscn`).

## 5. Out of scope

Combat with enemies, death, equipment slots, a bank, dropping items on the ground as world objects,
the mainland, multiple save slots, and skill-based quests beyond the island tasks.
