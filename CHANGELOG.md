# Changelog

All notable changes to this project will be documented here.

## [Unreleased] — Improved Fork

### Added
- **Wizard Stick** (`working_villages:wizard_stick`) — craftable tool with full GUI wizard for villager management. Replaces manual form navigation. Features: job assignment, dual job assignment, work area definition (circle/square), work hours, bed assignment, home assignment, chest auto-assign, rename, speed control, teleport, pause/resume, chat bubble toggle, chicken config, inventory view, job data reset.
- **Chickener job** (`working_villages:job_chickener`) — collects eggs, hatches them, randomly feeds chickens wheat seeds, breeds chickens using seeds from chest, culls excess chickens, collects raw chicken, deposits to chest. Min/max chicken counts configurable via Wizard Stick.
- **Fisher job** (`working_villages:job_fisher`) — finds water edges, fishes with 40% catch chance per attempt, deposits fish to chest.
- **Dual Skill system** — combine any two jobs into one villager. All common combinations pre-registered at load time. Assign via Wizard Stick.
- **Mood system** — villager mood (0–100) updates every 30s based on conditions (bed, home, working, stuck). Displayed in wizard GUI and optionally as a chat bubble.
- **Work Hours system** — per-villager work start/end hour. Villager auto-pauses outside shift window.
- **Work Area constraint** — circle or square zones set via Wizard Stick + ground click. Pathfinder respects boundary.
- **Speed control** — set per-villager walk speed via Wizard Stick.
- **Bed assignment** — click any bed block via Wizard Stick to assign it.
- **Home assignment** — click any ground position via Wizard Stick to set home.

### Fixed
- **Pathfinder fence/wall stuck** — Villagers no longer clip through or get stuck in fence corners. Fences, walls, bars, gates, railings are treated as solid horizontal barriers. Diagonal transitions through fence corners are blocked.
- **Stuck-in-corner recovery** — Villager detects being stuck on same waypoint for 80+ ticks and applies random nudge to escape, then re-paths.
- **Farmer random drop collection** — Farmer no longer picks up grass, sticks, or other random ground items. Only collects items with `farming:` prefix matching known crop/seed definitions.
- **Farmer cond crash** — `is_farming_item` now correctly handles both table (`ItemStack:to_table()`) and string inputs.
- **Chickener kill_chicken crash** — No longer calls `on_punch` with villager entity (crashes `creatura`/`animalia` which expect a real player ObjectRef). Now removes entity directly and adds drops manually.
- **Chickener try_breed crash** — No longer calls `on_rightclick` with villager entity. Uses `pcall`-wrapped feed API + direct chick spawn.
- **Dual job name invalid characters** — Job names now use `working_villages:dual_a_b` format (only `[a-z0-9_]`) instead of `++` separator.
- **Dual job load-time error** — Registrations happen synchronously at load time, not deferred with `minetest.after`.
- **Chest handling compatibility** — `handle_chest` now checks both `pos_data.chest` (Wizard Stick) and `pos_data.chest_pos` (original) for compatibility.

### Changed
- **Farmer item collection** — Switched from `farming_plants.is_plant` (node name check) to `is_farming_item` (item name whitelist) for ground item collection.
- **Chickener feathers** — Feathers are now discarded rather than collected or deposited.

### Removed
- **Woodcutter job** — Removed from this fork (upstream woodcutter.lua still present but not loaded).
