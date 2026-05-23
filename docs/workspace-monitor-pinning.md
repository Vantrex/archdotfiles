# Workspace / Monitor Pinning

**Date**: 2026-05-12
**Supersedes**: focus-then-spawn approach in [autostart-monitor-focus-fix.md](./autostart-monitor-focus-fix.md)

## Goal

Make certain autostart apps (e.g. Spotify) reliably land on a specific monitor without relying on the racy "focus monitor, then exec" sequence in `autostart.lua`.

## Why the old approach broke

`autostart.lua` used `hl.dispatch(hl.dsp.focus({ monitor = name }))` inside a timer, then `hl.exec_cmd(...)` on the next line. The `hl.dsp` namespace exposes a generic `focus` dispatcher (focus-by-direction / window), not `focusmonitor`. Passing `{ monitor = "..." }` to it doesn't focus the monitor — at best it's a no-op, at worst it raises inside the timer callback and aborts the rest, so the subsequent `exec_cmd` for the app never runs. Net effect: terminal and Spotify silently fail to spawn.

## Current solution: workspace rules + window rule

Defined in `hyprland/.config/hypr/workspace-rules.lua`:

```lua
hl.workspace_rule({ workspace = "name:music", monitor = "DP-2", default = true })
hl.window_rule({ match = { class = "^Spotify$" }, workspace = "name:music silent" })
```

How it works:

- The named workspace `music` is permanently bound to monitor `DP-2`.
- Any window matching class `Spotify` is sent to `name:music` at open time, silently (no workspace switch).
- The `workspace` window rule is evaluated **only when the window is mapped**. Moving Spotify to another workspace afterwards sticks — the rule does not re-apply.

`autostart.lua` then just calls `hl.exec_cmd("spotify")` with no focus dance; routing is the window rule's job.

### Trade-offs

- ✅ No race with monitor focus; works even if DP-3 isn't initially focused.
- ✅ Survives Hyprland reloads — the rule is part of config, not transient state.
- ⚠️ Fires for **every** Spotify window the session sees. If you close Spotify and reopen it, it goes back to DP-2. That's usually desired; if not, see the options below.

## Configurable options

### Option A — Extend to the terminal

If you also want the autostart terminal pinned to DP-3, mirror the Spotify rule:

```lua
hl.workspace_rule({ workspace = "name:term", monitor = "DP-3", default = true })
hl.window_rule({ match = { class = "^com\\.mitchellh\\.ghostty$" }, workspace = "name:term silent" })
```

Caveat: this also pins **every subsequent** ghostty window. If you want only the autostart terminal pinned and later terminals to follow focus, use Option C below.

### Option B — One-shot rule via event listener (auto-removes after first match)

Apply the workspace placement only once per Hyprland session, then forget it. Register a listener for `window.open_early`, move the matching window, and unsubscribe.

```lua
-- In autostart.lua, inside the hyprland.start callback:
local sub
sub = hl.on("window.open_early", function(win)
  if win.class == "Spotify" then
    hl.dispatch(hl.dsp.exec_raw("movetoworkspacesilent name:music,address:" .. win.address))
    sub:unsubscribe()
  end
end)
hl.exec_cmd("spotify")
```

Trade-offs:

- ✅ Rule is gone after first match — reopening Spotify mid-session lands wherever you are.
- ⚠️ More moving parts; depends on `HL.EventSubscription:unsubscribe()` existing — verify against `/usr/share/hypr/stubs/hl.meta.lua` before relying on it. The exact field name for the window address / class may differ; introspect `win` if needed.
- ⚠️ Closing and *re*opening Spotify in the same session won't be auto-pinned.

### Option C — Per-spawn rule via `exec_cmd` options

`hl.exec_cmd` accepts a second `rules` argument that applies to **only the window spawned by that call**, with no persistent config entry on the app's class:

```lua
hl.exec_cmd("spotify",          { workspace = "name:music silent" })
hl.exec_cmd(programs.terminal,  { workspace = "name:term silent" })
```

Combined with the `workspace_rule` bindings above (`name:music` → DP-2, `name:term` → DP-3), this is effectively a one-shot at autostart time — no `hl.window_rule` on the app class needed. Subsequent launches via keybind/menu are unaffected.

Trade-offs:

- ✅ Truly one-shot per `exec_cmd` invocation; cleanest separation between "autostart placement" and "general rules".
- ✅ No event-listener bookkeeping.
- ⚠️ Relies on the exact shape of the rules table (`workspace = "name:X silent"` as a single string vs. separate keys). Confirm by checking Hyprland's Lua API docs or by experiment — fall back to the persistent windowrule if it misbehaves.

## Recommendation

Stay on the default static rule (Spotify only) until a concrete annoyance shows up. Switch to **Option C** if you find yourself wanting the same treatment for the terminal without polluting general window-rule behavior. Reach for **Option B** only if you specifically need "first window of the session, then never again."
