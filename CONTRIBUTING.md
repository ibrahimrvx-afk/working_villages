# Contributing to Working Villages — Improved Edition

Thank you for wanting to contribute! Here's how to get started.

## Reporting Bugs

Use the [bug report template](.github/ISSUE_TEMPLATE/bug_report.md). Always include:
- The **full error message** from the log (not just the last line)
- Your **Luanti/Minetest version**
- Your **active mods list**

## Suggesting Features

Use the [feature request template](.github/ISSUE_TEMPLATE/feature_request.md).

## Pull Requests

1. **Fork** the repository
2. **Create a branch** for your change: `git checkout -b feature/my-feature`
3. **Make your changes** — see coding guidelines below
4. **Test in-game** before submitting
5. **Open a pull request** with a clear description of what changed and why

## Coding Guidelines

### Lua style
- Use **tabs** for indentation (matches existing code)
- Keep functions short and focused
- Add a comment explaining **why** for non-obvious logic
- Use `pcall` when calling methods on external mod entities (they may not exist or have different signatures)

### Job functions
- Always start with `self:handle_night()`, `self:handle_chest(...)`, `self:handle_job_pos()`
- Use named timers (`self:count_timer("myjob:action")`) to space out actions
- Never pass `self` (villager table) as a puncher/clicker to mob APIs — always use `self.object` or handle drops manually
- Condition functions passed to `collect_nearest_item_by_condition` receive an `ItemStack:to_table()` table, not a plain string — always extract `.name` first:
```lua
local function my_condition(item)
    local name = type(item) == "table" and item.name or item
    return name == "mymod:myitem"
end
```

### New jobs checklist
- [ ] Register with `working_villages.register_job("modname:job_name", {...})`
- [ ] Name uses only `[a-z0-9_:]` characters
- [ ] Add `require` line to `init.lua` **before** `jobs/dual_skill.lua`
- [ ] Add job name to the list in `dual_skill.lua` so combinations are pre-registered
- [ ] Document in README.md

## Running Luacheck

```bash
luacheck working_villagers/ --config .luacheckrc
```
