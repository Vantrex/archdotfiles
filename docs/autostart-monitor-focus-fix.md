# Autostart Monitor Focus Fix

**Date**: 2026-05-11
**Related**: [hyprland-lua-migration-summary.md](./hyprland-lua-migration-summary.md)

## Problem

On Hyprland startup, the terminal was spawning on DP-2 alongside Spotify instead of on DP-3. The cursor also remained on DP-2 instead of returning to DP-3 at the end of the autostart sequence.

**Expected behavior**:
1. Terminal spawns on DP-3 (main monitor)
2. Spotify spawns on DP-2 (left monitor)
3. Cursor returns to DP-3

**Actual behavior**:
- Both terminal and Spotify spawned on DP-2
- Cursor stayed on DP-2

## Root Cause

The `focus_monitor()` function in `autostart.lua` was using `hyprctl dispatch` to execute Lua dispatcher expressions from the shell:

```lua
-- OLD (broken)
local function focus_monitor(name)
  return [[hyprctl dispatch 'hl.dsp.focus({ monitor = "]] .. name .. [[" })']]
end

hl.exec_cmd(
  "hyprpm reload -n && sleep 2 && "
  .. focus_monitor("DP-3") .. " && sleep 1 && " .. programs.terminal
)
```

This approach has two problems:

1. **`hyprctl dispatch` + Lua expressions is unreliable in Lua config mode** — In Hyprland 0.55+, when the config is loaded via Lua (`hyprland.lua`), `hyprctl dispatch '<lua-expression>'` may not evaluate the Lua expression correctly. The expression `hl.dsp.focus({ monitor = "DP-3" })` needs to be evaluated by Hyprland's Lua interpreter, but `hyprctl dispatch` is designed for old-style hyprlang dispatcher strings, not Lua values.

2. **Race condition with shell sequencing** — Even if `hyprctl dispatch` worked, the `&&` chaining relies on the focus change persisting across separate `hl.exec_cmd` invocations. Since `hl.exec_cmd` spawns an asynchronous shell process, there's no guarantee the focus dispatcher completes before the next command in the chain runs.

## Solution

Replace the shell-based `hyprctl dispatch` approach with direct Lua API calls using `hl.dispatch()` and `hl.dsp.focus()`, sequenced with `hl.timer()` for reliable timing.

### Key Changes

| Before (broken) | After (fixed) |
|---|---|
| `hyprctl dispatch 'hl.dsp.focus(...)'` via shell | `hl.dispatch(hl.dsp.focus({ monitor = "..." }))` directly in Lua |
| `sleep N && cmd1 && cmd2` shell pipelines | `hl.timer(callback, { timeout = N*1000, type = "oneshot" })` |
| Timer objects created inline (GC risk) | Timer objects stored in `AutostartTimers` table to prevent GC |

### Detailed Breakdown

#### 1. Timer Retention Table

```lua
local AutostartTimers = {}
```

Timer objects must be retained to prevent garbage collection. The migration summary noted that `hl.timer()` proved unreliable when spawned from `hl.on("hyprland.start", ...)` — likely because the timer objects weren't retained and were GC'd before firing. Storing them in a module-level table keeps them alive.

#### 2. Direct Lua Dispatcher

```lua
local function focus_monitor(name)
  hl.dispatch(hl.dsp.focus({ monitor = name }))
end
```

Instead of generating a shell command string, this function calls Hyprland's Lua API directly. `hl.dsp.focus({ monitor = name })` creates a dispatcher value, and `hl.dispatch()` fires it synchronously within the timer callback.

#### 3. Timer-Based Sequencing

```lua
-- Step 1: After plugin reload settles, focus DP-3 and launch terminal
AutostartTimers.terminal = hl.timer(function()
  focus_monitor("DP-3")
  hl.exec_cmd(programs.terminal)
end, { timeout = 2000, type = "oneshot" })

-- Step 2: Focus DP-2 and launch Spotify
AutostartTimers.spotify = hl.timer(function()
  focus_monitor("DP-2")
  hl.exec_cmd("spotify")
end, { timeout = 4000, type = "oneshot" })

-- Step 3: Return focus to DP-3
AutostartTimers.refocus = hl.timer(function()
  focus_monitor("DP-3")
end, { timeout = 6000, type = "oneshot" })
```

Each timer callback focuses the target monitor THEN launches the application, ensuring the window appears on the correct monitor. The focus change is synchronous within the callback, so there's no race condition.

#### 4. `hyprpm reload -n` Handling

The plugin reload (`hyprpm reload -n`) was previously chained before the terminal launch. It was initially dropped from the rewrite (see Follow-up Fix below for why this broke the plugin). It was restored as `hl.exec_cmd("hyprpm reload -n")` at the top of the `hyprland.start` callback, running asynchronously. The 2-second timer delay gives the plugin time to settle before any windows spawn.

## API References

- **`hl.dispatch(dispatcher_value)`** — Fires a dispatcher value synchronously. Used to execute `hl.dsp.focus()` within timer callbacks.
- **`hl.dsp.focus({ monitor = "name" })`** — Creates a focus dispatcher targeting a specific monitor by name.
- **`hl.timer(callback, { timeout = ms, type = "oneshot" })`** — Creates a one-shot timer that fires after `ms` milliseconds. Returns a timer object that must be retained.
- **`hl.exec_cmd(command)`** — Spawns an asynchronous process. Does not block or wait for completion.

## Files Modified

| File | Change |
|---|---|
| `hyprland/.config/hypr/autostart.lua` | Rewrote monitor focus logic to use native Lua API with timers |

## Follow-up Fix: split-monitor-workspaces Plugin Not Loading (2026-05-11)

After the above fix, the monitor focus worked correctly, but the `split-monitor-workspaces` plugin stopped loading. Two separate issues were identified:

### Issue 1: Missing `hyprpm reload -n`

When rewriting `autostart.lua`, the `hyprpm reload -n` command was removed from the shell chain. The old config had it embedded:

```lua
-- OLD (had hyprpm reload in the chain)
hl.exec_cmd(
  "hyprpm reload -n && sleep 2 && "
  .. focus_monitor("DP-3") .. " && sleep 1 && " .. programs.terminal
)
```

The rewrite dropped it entirely, so the plugin was never loaded at startup.

**Fix**: Added `hl.exec_cmd("hyprpm reload -n")` as the first line of the `hyprland.start` callback, ensuring the plugin loads before any timers fire.

### Issue 2: Wrong Plugin Key in Guard

`workspace-rules.lua` had:

```lua
-- OLD (broken — hyphens don't match Lua table key)
if hl.plugin and hl.plugin["split-monitor-workspaces"] ~= nil then
  hl.config({
    plugin = {
      ["split-monitor-workspaces"] = { ... }
    }
  })
end
```

Per the [plugin docs](https://github.com/zjeffer/split-monitor-workspaces), Hyprland normalizes plugin names by replacing hyphens with underscores. The correct key is `split_monitor_workspaces`. The guard was always `nil`, so plugin config was silently skipped.

**Fix**: Changed to:

```lua
if hl.plugin and hl.plugin.split_monitor_workspaces ~= nil then
  hl.config({
    plugin = {
      split_monitor_workspaces = { ... }
    }
  })
end
```

### Files Modified (Follow-up)

| File | Change |
|---|---|
| `hyprland/.config/hypr/autostart.lua` | Added `hl.exec_cmd("hyprpm reload -n")` at top of callback |
| `hyprland/.config/hypr/workspace-rules.lua` | Fixed plugin key from `["split-monitor-workspaces"]` to `split_monitor_workspaces` |

## Verification

After applying all fixes, reboot or restart Hyprland and verify:
1. Terminal opens on DP-3
2. Spotify opens on DP-2
3. Cursor is on DP-3 after autostart completes
4. Workspace numbering is per-monitor (1-10 on each monitor, not global 1-30)
