local programs = require("programs")

hl.on("hyprland.start", function()
  -- Daemons and utilities (no ordering required).
  hl.exec_cmd("swaync")
  hl.exec_cmd(os.getenv("HOME") .. "/.config/waybar/scripts/settings-apply.sh")
  hl.exec_cmd("waybar 2>/dev/null")
  hl.exec_cmd("awww-daemon")
  hl.exec_cmd(os.getenv("HOME") .. "/.config/quickshell/widgets/wallpaper/matugen-startup.sh")
  hl.exec_cmd("quickshell")
  hl.exec_cmd("wl-paste --type text --watch cliphist store")
  hl.exec_cmd("wl-paste --type image --watch cliphist store")

  -- Focus each target monitor, wait for the focus change to settle, then
  -- spawn onto its currently-active workspace. Because the plugin's
  -- persistent workspaces map SUPER+N to the monitor's Nth workspace, this
  -- puts ghostty on whatever workspace SUPER+1 on DP-3 reaches (and spotify
  -- on DP-2's equivalent).
  --
  --   1. `hyprpm reload -n` — split-monitor-workspaces doesn't auto-load on
  --      compositor start.
  --   2. Sleep 2s — let plugin settle.
  --   3. Focus DP-3, sleep 0.6s for the focus change to land, then spawn
  --      terminal. Sleep 1.5s for ghostty's window to actually map so it
  --      can't drift onto DP-2 when focus shifts next.
  --   4. Focus DP-2, sleep 0.6s, spawn spotify.
  --   5. Sleep 2s, refocus DP-3 so the cursor ends on the main monitor.
  hl.exec_cmd(
    [[hyprpm reload -n ]] ..
    [[&& sleep 2 ]] ..
    [[&& hyprctl dispatch 'hl.dsp.focus({ monitor = "DP-3" })' ]] ..
    [[&& sleep 0.6 ]] ..
    [[&& hyprctl dispatch 'hl.dsp.exec_cmd("]] .. programs.terminal .. [[")' ]] ..
    [[&& sleep 1.5 ]] ..
    [[&& hyprctl dispatch 'hl.dsp.focus({ monitor = "DP-2" })' ]] ..
    [[&& sleep 0.6 ]] ..
    [[&& hyprctl dispatch 'hl.dsp.exec_cmd("env QT_QPA_PLATFORM=wayland GDK_BACKEND=wayland spotify")' ]] ..
    [[&& sleep 1 ]] ..
    [[&& hyprctl dispatch 'hl.dsp.focus({ monitor = "DP-3" })']]
  )
end)
