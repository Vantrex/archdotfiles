hl.window_rule({ match = { class = ".*" }, suppress_event = "maximize" })

hl.window_rule({
  match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
  no_focus = true,
})

hl.window_rule({ match = { class = "^xwaylandvideobridge$" }, opacity = "0.0 override" })
hl.window_rule({ match = { class = "^xwaylandvideobridge$" }, no_anim = true })
hl.window_rule({ match = { class = "^xwaylandvideobridge$" }, no_initial_focus = true })
hl.window_rule({ match = { class = "^xwaylandvideobridge$" }, max_size = "1 1" })
hl.window_rule({ match = { class = "^xwaylandvideobridge$" }, no_blur = true })

hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
hl.workspace_rule({ workspace = "f[1]", gaps_out = 0, gaps_in = 0 })

-- No named-workspace pinning: split-monitor-workspaces' persistent workspaces
-- already give each monitor its own numbered set (reachable via SUPER+1..0).
-- Autostart focuses each target monitor before spawning so the apps land on
-- that monitor's currently-active persistent workspace.

hl.window_rule({ match = { float = false, workspace = "w[tv1]" }, border_size = 0 })
hl.window_rule({ match = { float = false, workspace = "w[tv1]" }, rounding = 0 })
hl.window_rule({ match = { float = false, workspace = "f[1]" }, border_size = 0 })
hl.window_rule({ match = { float = false, workspace = "f[1]" }, rounding = 0 })

hl.window_rule({ match = { class = "firefox" }, no_blur = true })

hl.window_rule({ match = { class = "^com\\.mitchellh\\.ghostty$" }, opacity = "0.9 0.9" })

hl.window_rule({ match = { class = "^jetbrains-.+$", float = true }, tag = "+jb" })
hl.window_rule({ match = { tag = "jb" }, stay_focused = true })
hl.window_rule({ match = { tag = "jb" }, no_initial_focus = true })

hl.layer_rule({ match = { namespace = "^quickshell-wallpaper-picker$" }, blur = true })

if hl.plugin and hl.plugin.split_monitor_workspaces ~= nil then
  hl.config({
    plugin = {
      split_monitor_workspaces = {
        count = 10,
        keep_focused = 1,
        enable_notifications = 0,
        enable_persistent_workspaces = 1,
      },
    },
  })
end
