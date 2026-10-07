# Spec addendum: Mining, Smithing and the first quest (Milestone 7)

This extends [SPEC_GAME.md](SPEC_GAME.md), [SPEC_GRAPHICS.md](SPEC_GRAPHICS.md) and
[SPEC_SKILLS.md](SPEC_SKILLS.md) at Milestone 7. After M6 the island has five skills and ten tasks,
but every activity sits in one of two loops: wood → fire, and fish → food. This milestone adds a third,
longer chain (ore → bar → equipment), a new villager, and the island's first proper **quest**, with
stages, a journal entry in the tracker, and saved progress.

## 1. Goal

Give players something to build towards that spans several places and skills. They meet Brann the
blacksmith, get a pickaxe and hammer, mine copper and tin in a quarry, smelt bronze at his furnace,
hammer a dagger on his anvil and bring it back. After the quest, the same stations let them keep
training Mining and Smithing up to iron gear.

## 2. Constraints (carried over)

- Everything is procedural: the smithy, quarry, rocks, tools, ore and bar icons and sounds are built in code.
- The [performance contract](SPEC_GAME.md#performance-and-pacing-contract) still applies: ≤ 450 draw calls
  on every preset (260 target), and generation < 1.5 s warm, including navigation readiness.
- Tutorial objectives, the M6 tasks and their rewards, and the no-teleport playthroughs stay unchanged.
  Moving scattered props is allowed. Landmarks must stay on reachable, walkable ground.
- Saves stay at version 2. The new `quest.quests` key is optional and defaults to "not started", so
  every earlier rebuild save and every version 1 import still loads ([SPEC_SAVE.md](SPEC_SAVE.md)).
- Every skill roll goes through `SkillsManager.chance()`. Every inventory change that can fail is a
  preflighted transaction. Interrupted actions grant nothing.

## 3. Features

### K1. Two new skills
- **Mining** and **Smithing** join the Skills panel, using the same XP curve, XP drops, level-up
  jingle and sparks. The panel fits seven skills plus hitpoints at 1280 × 720.
- "Reach level 10 in any skill" counts the new skills.

### K2. The quarry
- A gravel quarry north-east of the gate path, joined to it by a short path stub. It holds **three
  copper rocks, three tin rocks and two iron rocks**, ringed by boulders.
- A rock shows coloured ore veins. Clicking it ("Mine Copper rock") walks to it and swings a pickaxe.
  Each completed swing gives **one ore and XP**, and the rock then depletes to grey rubble and
  respawns after a delay. Rubble is not interactable ("The rock has no ore left.").
- Mining requires a pickaxe in the inventory (bronze or steel), the required Mining level, and room
  for the ore. A full inventory stops the attempt before it starts.

### K3. The smithy
- An open-air forge east of the plaza, joined to it by a path. It has a stone **furnace** with a
  glowing mouth under a lean-to roof, an **anvil** on a stump, a water trough, a tool rack and a woodpile.
- **Brann**, the island's blacksmith, stands beside the anvil.
- Both stations open a **crafting panel** listing every recipe with its ingredients, level and XP, and
  Make 1 / Make all buttons. Recipes the player can't make yet are shown disabled with the reason
  (level, missing ore or bars, missing hammer). Choosing one closes the panel and starts a loop that
  repeats until the count is reached, the player moves, ingredients run out or there's no room.
- **Smelting** ("Use Furnace"): bronze bars need one copper ore and one tin ore. Iron bars need one
  iron ore and can fail ("The iron ore is too impure and crumbles away."), which still consumes the ore.
- **Smithing** ("Use Anvil") needs a hammer in the inventory.
- Smithing results are sell-only goods (Marla buys them), except the bronze pickaxe, which mines.

### K4. Brann's quest: "The Smith's Apprentice"
| Stage | Meaning | Tracker |
|---|---|---|
| 0 | Not started | "New quest: talk to Brann at the smithy east of the plaza." |
| 1 | Accepted | Checklist: mine copper ore, mine tin ore, smelt a bronze bar, smith a bronze dagger, bring the dagger to Brann |
| 2 | Complete | "Quest complete" line under the tasks |

- Talking to Brann at stage 0 offers the quest (accept or decline). Accepting moves to stage 1 and
  hands over a **bronze pickaxe and a hammer**, all or nothing. If they don't fit, the quest still
  starts and Brann offers them again on every later talk until they do. He also replaces lost tools
  at stage 1 or 2 if the player has none of that kind.
- Checklist flags (`mined_copper`, `mined_tin`, `smelted_bronze`, `smithed_dagger`) are set by the
  activity events, not by owning items, at any time before the quest completes.
- **Hand-in** needs a bronze dagger in the inventory (flags are guidance, not a gate). It is one
  transaction: remove the dagger and add **60 coins**, then grant **250 Smithing XP and 100 Mining XP**,
  move to stage 2, show a "Quest complete" banner, play the fanfare and save, all in one snapshot. If
  the coins can't be added, nothing changes and Brann explains.
- Completion never replays on load. The quest needs the tutorial to be complete; before that Brann
  says he is busy and to finish Maelis's training first.

### K5. Items and the shop
- New items: copper ore, tin ore, iron ore, bronze bar and iron bar (stackable); bronze dagger, bronze
  helm, iron dagger, iron helm, hammer, bronze pickaxe and steel pickaxe (not stackable). Each has an
  examine line and a drawn icon.
- Marla adds a **steel pickaxe** (50 coins, one at a time, mines 30 % faster) and a **hammer** (5 coins)
  to her stock and buys the new goods.

### K6. Presentation
- The character shows a pickaxe while mining and a hammer while smithing. Each swing lands with an
  impact event, which gives a stone clink and chips at rocks, or an anvil ring and sparks at the anvil.
- The furnace glow flickers, and brightens while smelting. Smoke rises from the chimney.
- The minimap shows the smithy and quarry. Brann has an objective arrow while the quest is waiting to
  be handed in.

### K7. Saving
- `quest.quests` = `{quest_id: {"stage": int, "flags": [string]}}`. Validation ignores unknown quest
  ids, clamps stage to the quest's range, keeps only known flags and drops duplicates. A non-dictionary
  `quests` is a malformed save. Missing → every quest at stage 0.
- Save checkpoints: quest started, checklist flag set, quest completed (after the triggering transaction).
- Rock depletion is not saved; all rocks are full after a load.

## 4. Exact balance

`L` is the current skill level, `R` the requirement.

| Rock | Level | XP | Base seconds | Respawn |
|---|---:|---:|---:|---:|
| Copper | 1 | 17.5 | 2.4 | 8 s |
| Tin | 1 | 17.5 | 2.4 | 8 s |
| Iron | 8 | 35 | 3.0 | 15 s |

Mining time = base × clamp(1 − 0.03 × (L − R), 0.55, 1) × (0.7 with a steel pickaxe). A swing always
yields ore. Rocks hold one ore each.

| Smelt | Ore | Level | XP | Success |
|---|---|---:|---:|---|
| Bronze bar | 1 copper + 1 tin | 1 | 12 | always |
| Iron bar | 1 iron | 8 | 25 | clamp(0.5 + 0.05 × (L − 8), 0.5, 1) |

Smelting takes 1.8 s. Smithing takes 2.4 s per item.

| Smith | Bars | Level | XP | Sells for |
|---|---|---:|---:|---:|
| Bronze dagger | 1 bronze | 1 | 25 | 12 |
| Bronze pickaxe | 1 bronze | 3 | 25 | 10 |
| Bronze helm | 2 bronze | 5 | 50 | 25 |
| Iron dagger | 1 iron | 10 | 50 | 30 |
| Iron helm | 2 iron | 12 | 100 | 60 |

Sell prices: copper and tin ore 3, iron ore 8, bronze bar 8, iron bar 20, hammer 1, steel pickaxe 0
(Marla won't buy back her own pickaxe). Buy prices: steel pickaxe 50, hammer 5.

Each smelt/smith step is one transaction that preflights its outcome (for iron, success and failure).
Ingredients, level and tools are rechecked when each step completes. A level-up mid-loop applies from
the next step.

## 5. Acceptance criteria

- Mining, smelting and smithing work end to end with exact numbers, tool and level requirements,
  depletion and respawn, iron failures, capacity checks and cancellation without grants.
- The quest goes through stages 0 → 1 → 2 with tool recovery, retry when full, a hand-in transaction
  that leaves state and save coherent, and no replay on load.
- `quest.quests` round-trips. Malformed or unknown entries follow K7, and saves without it load at stage 0.
- A new `smithing` suite plus a no-teleport `quest_playthrough` (tutorial-complete start → Brann →
  quarry → furnace → anvil → Brann) pass alongside every earlier suite.
- Every landmark (including `npc_smith`, `smithy`, `furnace`, `anvil`, `quarry`) is reachable from the dock.
- Perf report: ≤ 260 draw calls in every fixed view and preset, and warm generation < 1.5 s.

## 6. Out of scope

Wielding or wearing smithed equipment, combat stats, ore banking, more quests, and saving rock depletion.
