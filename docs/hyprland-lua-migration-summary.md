# Hyprland Config Migration: Hyprlang → Lua

**Date**: 2026-05-11
**Plan**: [hyprland-lua-migration.md](../../docs/hyprland-lua-migration.md)

## What Changed

Hyprland 0.55+ deprecated hyprlang in favor of Lua. All `.conf` files in `~/.config/hypr/` were converted to `.lua` using the new Lua API.

## Backup

Original config backed up to `~/.config/hypr.backup.20260511_170048/`

## Files Converted (12 total)

| Old | New | API Used |
|---|---|---|
| `hyprland.conf` | `hyprland.lua` | `require()` |
| `programs.conf` | `programs.lua` | Module (`return M`) |
| `monitors.conf` | `monitors.lua` | `hl.monitor()` |
| `looksandfeel.conf` | `looksandfeel.lua` | `hl.config()` |
| `keybinds.conf` | `keybinds.lua` | `hl.bind()` |
| `autostart.conf` | `autostart.lua` | `hl.on("hyprland.start", ...)` |
| `environment.conf` | `environment.lua` | `hl.env()` |
| `animations.conf` | `animations.lua` | `hl.bezier()`, `hl.animation()` |
| `inputs.conf` | `inputs.lua` | `hl.config()`, `hl.gesture()`, `hl.device()` |
| `misc.conf` | `misc.lua` | `hl.config()` |
| `layout.conf` | `layout.lua` | `hl.config()` |
| `workspace-rules.conf` | `workspace-rules.lua` | `hl.window_rule()`, `hl.workspace_rule()`, `hl.config()` |

`xdph.conf` was left unchanged — it's for `xdg-desktop-portal-hyprland`, not Hyprland itself.

## Key Syntax Mappings

- `source = file.conf` → `require("file")`
- `$var = val` → module exports (`M.var = val`)
- `monitor = name, res, pos, scale` → `hl.monitor({ output, mode, position, scale })`
- `bind = MOD, KEY, dispatch, args` → `hl.bind("MOD + KEY", hl.dsp.xxx(...))` — single key string, no `{mods=...}` form
- Mouse binds: `hl.bind("MOD + mouse:272", ..., { mouse = true })`
- Bind flag suffixes: `bindl` → `{ locked = true }`, `binde` → `{ repeating = true }`, `bindel`/`bindle` → both, `bindr` → `{ release = true }`
- `exec-once = cmd` → `hl.on("hyprland.start", function() hl.exec_cmd("cmd") end)`. Shell pipelines (`&&`, `|`) need `sh -c "..."` — `hl.exec_cmd` doesn't invoke a shell
- `env = KEY,VAL` → `hl.env("KEY", "VAL")`
- `windowrule = rule` → `hl.window_rule({ match = {}, effect = val })`; match keys use `float`/`pin` (not `floating`/`pinned`); `opacity` is a string (`"0.7 0.8"`, `"0.0 override"`); `max_size 1 1` → `max_size = "1 1"`; `suppress_event maximize` → `suppress_event = "maximize"`
- `workspace = sel, opts` → `hl.workspace_rule({ workspace = "sel", ... })`
- Sections (`general {}`, `input {}`, etc.) → `hl.config({ section = {} })`
- Per-device blocks → `hl.device({ name = "...", ... })`, **not** nested in `hl.config`
- Dotted config keys (e.g. `col.active_border`) → string keys: `["col.active_border"] = "..."` (plain `col.active_border = ...` is a Lua syntax error)
- `animation = name, on, speed, curve_name, [style]` → `hl.animation({ leaf, enabled, speed, bezier, style? })` — field is **`bezier`**, not `curve`
- Dispatchers: `killactive` → `hl.dsp.window.close()` (use `close`, not `kill` — `kill` is forceful)

## Custom Dispatchers

Plugin dispatchers (`split-workspace`, `split-movetoworkspace`) are bridged via `hl.exec_cmd("hyprctl dispatch ...")` since they aren't native `hl.dsp` functions.

## Post-migration Fixes (2026-05-11)

A wiki-cross-checked review flagged several bugs in the initial conversion. All are fixed in the current `.lua` files:

- `looksandfeel.lua`: `col.active_border` / `col.inactive_border` quoted as string keys (was a Lua syntax error — caught by `luac -p`)
- `animations.lua`: `curve =` → `bezier =`
- `inputs.lua`: per-device block moved from `hl.config({ device = ... })` to `hl.device({...})`
- `keybinds.lua`:
  - mouse binds rewritten as `hl.bind("MOD + mouse:272", ..., { mouse = true })`
  - media keys use `{ locked = true, repeating = true }` instead of the invented `exclusive = true`
  - `SUPER + C` killactive → `hl.dsp.window.close()` (was `kill`)
  - `SUPER + O` got `{ release = true }` (was a `bindr`)
  - workspace 1–10 binds collapsed into a loop
- `workspace-rules.lua`:
  - `match` uses `float`/`pin` (not `floating`/`pinned`)
  - `opacity` rewritten as strings (`"0.7 0.8"`, `"0.0 override"`)
  - `size = { 1, 1 }` → `max_size = "1 1"`
  - `suppress_resize_event = true` → `suppress_event = "maximize"`
- `autostart.lua`: shell pipelines wrapped in `sh -c '...'`
- `keybinds.lua`: arrow-key focus moves now use `hl.dsp.focus({ direction = "l" })` — `hl.dsp.focus` is itself callable; there is no `.move` sub-namespace

## Post-runtime Fixes (2026-05-11, after first `hyprctl reload`)

Five errors surfaced from `hyprctl configerrors` that `luac -p` couldn't catch — they only show up at Hyprland's config-load step:

- `animations.lua`: `hl.bezier(...)` doesn't exist. Rewritten to `hl.curve(name, { type = "bezier", points = { {x1,y1}, {x2,y2} } })`. Animations still reference curves via `bezier = "<name>"` (correct).
- `looksandfeel.lua`: gradient string `"rgba(...) rgba(...) 45deg"` is rejected. The Lua API needs a gradient *table* — `["col.active_border"] = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 }`.
- `misc.lua`: `vfr` is unknown; the key is `vrr` (Variable Refresh Rate, integer 0/1/2 — not boolean).
- `layout.lua`: `dwindle.pseudotile` was removed in 0.55+; dropped the line (pseudotile is now per-window via `hl.dsp.window.pseudo()`).
- `workspace-rules.lua`: plugin config errors with "unknown config key" because plugins load after parse. Wrapped in `if hl.plugin and hl.plugin["split-monitor-workspaces"] ~= nil then ... end`.

Verified with `hyprctl configerrors` returning empty (modulo a benign internal `hl.dispatch(submap)` warning that appears even with empty user config — emitted by Hyprland's built-in default submap context, unrelated to the user lua files). All 59 binds register.

## Post-reboot Fixes (2026-05-11)

After reboot, hotkeys appeared to "not work" — actually, only the ones that shelled out via `hl.exec_cmd("hyprctl dispatch ...")` were broken. In Hyprland 0.55+ Lua mode, `hyprctl dispatch <oldsyntax>` is parsed as Lua and silently fails (errors like `return hl.dispatch(killactive):1: hl.dispatch: expected a dispatcher`).

All affected binds in `keybinds.lua` were rewritten to use the Lua API directly:

| Old | New |
|---|---|
| `hyprctl dispatch exit` | `hl.dsp.exit()` |
| `hyprctl dispatch split-workspace N` | `hl.plugin.split_monitor_workspaces.workspace(N)` |
| `hyprctl dispatch split-movetoworkspace N` | `hl.plugin.split_monitor_workspaces.move_to_workspace(N)` |
| `hyprctl dispatch movetoworkspace special:magic` | `hl.dsp.window.move({ workspace = "special:magic" })` |
| `hyprctl dispatch workspace e+1` / `e-1` | `hl.dsp.focus({ workspace = "e+1" })` / `"e-1"` |

Plugin Lua API discovery: each loaded plugin appears at `hl.plugin.<name>` (with hyphens normalised to underscores, e.g. `split-monitor-workspaces` → `split_monitor_workspaces`). The methods exposed by split-monitor-workspaces (1.2.0) are: `workspace`, `move_to_workspace`, `move_to_workspace_silent`, `cycle_workspaces` (takes `"next"`/`"prev"`), `change_monitor`, `change_monitor_silent`, `max_workspaces`, `monitor_priority`, `grab_rogue_windows`.

## Post-second-reboot Fixes (2026-05-11)

After reboot, three issues surfaced:

1. **Scroll-wheel direction was reversed** — original conf had `mouse_down → e+1` (next) and `mouse_up → e-1` (prev). User prefers the opposite. Swapped to `mouse_down → prev`, `mouse_up → next`.

2. **Autostart focus-monitor / terminal / spotify didn't fire** — went through two rewrites:
   - **First attempt** (broken): wrapped the chain in `sh -c '...'`, which collided with the inner `'...'` around the hyprctl arg and terminated the outer quotes early.
   - **Second attempt** (also broken): rewrote with `hl.timer(fn, { timeout = ms, type = "oneshot" })`. Timers fire fine from bind callbacks but proved unreliable when spawned in bulk from `hl.on("hyprland.start", ...)` — terminal and spotify never launched. Possibly a GC issue (the timer objects aren't retained) or hyprland.start timing.
   - **Final fix**: drop the outer `sh -c`, drop `hl.timer`, just pass the shell pipeline straight to `hl.exec_cmd` (which already invokes a shell):

   ```lua
   local function focus_monitor(name)
     return [[hyprctl dispatch 'hl.dsp.focus({ monitor = "]] .. name .. [[" })']]
   end

   hl.exec_cmd("sleep 0.5 && " .. focus_monitor("DP-3") .. " && " .. programs.terminal)
   ```

   Generated command string: `sleep 0.5 && hyprctl dispatch 'hl.dsp.focus({ monitor = "DP-3" })' && ghostty` — valid shell, no nested-quote conflict.

3. **Scroll wheel was monitor-global** — switched from `hl.dsp.focus({ workspace = "e±1" })` to `hl.plugin.split_monitor_workspaces.cycle_workspaces("next"/"prev")` so wheel-scroll cycles within the current monitor's workspace set only.

## Post-third-reboot Fixes (2026-05-13)

After reboot, three more autostart issues surfaced — all caused by the focus-then-spawn pattern racing with window-map timing:

1. **`split-monitor-workspaces` didn't auto-load on compositor start** — the plugin only became active after running `hyprpm update` manually. Fix: include `hyprpm reload -n` as the first step of the autostart pipeline so the plugin is guaranteed loaded before any window spawns.

2. **Spotify spawned without a visible window** — the previous `workspace = "name:music silent"` window rule sent the surface to a workspace that DP-2 wasn't currently showing. Dropped the `silent` flag, and (next iteration) moved the workspace targeting onto the `hl.dsp.exec_cmd` spawn rules.

3. **Terminal opened on the wrong monitor (DP-2) despite a `hyprctl dispatch 'hl.dsp.focus({ monitor = "DP-3" })'` step right before it** — even with everything serialized into one `&&` chain, the focus dispatch returned before the window-spawn actually consumed the new focus, so ghostty landed on whatever monitor Spotify had pulled focus to.

**Real fix**: stop trying to choreograph focus around the spawns. `hl.exec_cmd(cmd, rules?)` and `hl.dsp.exec_cmd(cmd, rules?)` both accept a one-shot rules table — including `workspace` — that's applied to the spawned window directly. Pin a named workspace to each monitor, then launch each app onto its workspace.

```lua
-- workspace-rules.lua
hl.workspace_rule({ workspace = "name:main",  monitor = "DP-3", default = true })
hl.workspace_rule({ workspace = "name:music", monitor = "DP-2", default = true })

-- autostart.lua (single shell pipeline)
hl.exec_cmd(
  [[hyprpm reload -n ]] ..
  [[&& sleep 2 ]] ..
  [[&& hyprctl dispatch 'hl.dsp.exec_cmd("]] .. programs.terminal ..
    [[", { workspace = "name:main" })' ]] ..
  [[&& hyprctl dispatch 'hl.dsp.exec_cmd("spotify", { workspace = "name:music" })' ]] ..
  [[&& sleep 2 ]] ..
  [[&& hyprctl dispatch 'hl.dsp.focus({ monitor = "DP-3" })']]
)
```

This eliminates the focus-race entirely: each spawn carries its own workspace assignment, and `default = true` on both workspace rules ensures DP-3 shows `name:main` and DP-2 shows `name:music` at boot. The final focus dispatch just parks the cursor on the main monitor.

### Follow-up: named workspaces aren't reachable via SUPER+1..0

The named-workspace approach above worked perfectly for placement but broke `SUPER+1..0` access — `name:main` and `name:music` live outside split-monitor-workspaces' numbered set, so the plugin's `workspace(N)` dispatcher can't reach them.

**Fix**: drop named workspaces entirely; go back to focus-then-spawn but with proper sleeps after each focus dispatch so the change actually propagates before the next command. With `enable_persistent_workspaces = 1`, each monitor's *first* persistent workspace is what `SUPER+1` jumps to on that monitor — so spawning on the currently-active workspace == spawning on `SUPER+1`.

```lua
-- workspace-rules.lua — no name:main / name:music pinning anymore
-- (plugin's persistent workspaces handle per-monitor numbering)

-- autostart.lua
hl.exec_cmd(
  [[hyprpm reload -n ]] ..
  [[&& sleep 2 ]] ..
  [[&& hyprctl dispatch 'hl.dsp.focus({ monitor = "DP-3" })' ]] ..
  [[&& sleep 0.6 ]] ..  -- focus change must propagate before spawn
  [[&& hyprctl dispatch 'hl.dsp.exec_cmd("]] .. programs.terminal .. [[")' ]] ..
  [[&& sleep 1.5 ]] .. -- window must map before refocus, or it drifts
  [[&& hyprctl dispatch 'hl.dsp.focus({ monitor = "DP-2" })' ]] ..
  [[&& sleep 0.6 ]] ..
  [[&& hyprctl dispatch 'hl.dsp.exec_cmd("spotify")' ]] ..
  [[&& sleep 2 ]] ..
  [[&& hyprctl dispatch 'hl.dsp.focus({ monitor = "DP-3" })']]
)
```

The earlier "spawning in the same frame" race was caused by zero/no sleep between the focus dispatch and the spawn. With **0.6s after the focus** and **1.5s after the spawn** (so the window finishes mapping before focus moves on), apps land on their intended monitors *and* on `SUPER+1`-reachable workspaces.

## Key API references discovered along the way

- `hl.exec_cmd(cmd, rules?)` and `hl.dsp.exec_cmd(cmd, rules?)` — second arg is a one-shot rules table applied to the spawned window (e.g. `{ workspace = "name:main" }`). Useful when you need rule-level placement, but bypasses split-monitor-workspaces' numbered set (i.e. the resulting workspace isn't reachable via `SUPER+N`). For accessible placement, prefer focus-then-spawn with sleeps.
- **Focus-then-spawn timing**: `hyprctl dispatch '...'` returns immediately. To make focus changes visible to the next command, sleep ~0.5s after a focus dispatch *and* ~1–2s after a spawn (so the window finishes mapping before focus moves on).
- `hl.timer(fn, { timeout = ms, type = "oneshot" | "repeat" })` — returns a timer obj with `:set_enabled(bool)` / `:is_enabled()`
- `hl.dispatch(<dispatcher>)` — fires a dispatcher value (e.g. `hl.dispatch(hl.dsp.focus({...}))`)
- `hyprctl dispatch '<lua-expression>'` — same effect from a shell; pass the **dispatcher value** (`hl.dsp.focus({...})`), **not** `hl.dispatch(hl.dsp.focus({...}))` — hyprctl wraps it for you
- `hyprpm reload -n` — needs to run on compositor start before any window spawn that depends on a plugin (e.g. split-monitor-workspaces); plugins don't auto-load reliably on the initial config parse

Verified with `luac -p *.lua` — all 13 files parse cleanly.

## Validation

Before rebooting into the new config, run `luac -p *.lua` in `~/.config/hypr/`. Hyprland's Lua API still won't be exercised until the compositor reloads, but `luac` will at least catch syntax errors.

## Related Fixes

- **[Autostart Monitor Focus Fix](./autostart-monitor-focus-fix.md)** — Terminal/Spotify spawning on wrong monitor after Lua migration. Root cause: `hyprctl dispatch` with Lua expressions doesn't work reliably in Lua config mode. Fixed by using `hl.dispatch(hl.dsp.focus(...))` directly with `hl.timer()` for sequencing.

## Rollback

If Hyprland fails to start, restore from `~/.config/hypr.backup.20260511_170048/` or remove `hyprland.lua` so Hyprland falls back to `hyprland.conf`.
