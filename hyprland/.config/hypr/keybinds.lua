local programs = require("programs")
local home = os.getenv("HOME")

hl.bind("SUPER + RETURN", hl.dsp.exec_cmd(programs.terminal))
hl.bind("SUPER + B", hl.dsp.exec_cmd(programs.browser))
hl.bind("SUPER + SPACE", hl.dsp.exec_cmd(programs.menu))
hl.bind("CTRL + SUPER + SPACE", hl.dsp.exec_cmd(home .. "/.config/quickshell/qs-wallpaper-toggle.sh"))
hl.bind("CTRL + SUPER + T", hl.dsp.exec_cmd(home .. "/.config/quickshell/widgets/waybar-config/waybar-config-toggle.sh"))
hl.bind("SUPER + C", hl.dsp.window.close())
hl.bind("SUPER + M", hl.dsp.exit())
hl.bind("SUPER + E", hl.dsp.exec_cmd(programs.fileManager))
hl.bind("SUPER + F", hl.dsp.window.float({ action = "toggle" }))
hl.bind("SUPER + P", hl.dsp.window.pseudo())
hl.bind("SUPER + J", hl.dsp.layout("togglesplit"))

hl.bind("INSERT", hl.dsp.exec_cmd("sh -c '" .. home .. "/.config/scripts/region-screenshot.sh'"))
hl.bind("SUPER + V", hl.dsp.exec_cmd("sh -c 'cliphist list | rofi -dmenu | cliphist decode | wl-copy'"))

hl.bind("SUPER + LEFT", hl.dsp.focus({ direction = "l" }))
hl.bind("SUPER + RIGHT", hl.dsp.focus({ direction = "r" }))
hl.bind("SUPER + UP", hl.dsp.focus({ direction = "u" }))
hl.bind("SUPER + DOWN", hl.dsp.focus({ direction = "d" }))

for i = 1, 10 do
  local key = (i == 10) and "0" or tostring(i)
  hl.bind("SUPER + " .. key, function() hl.plugin.split_monitor_workspaces.workspace(i) end)
  hl.bind("SUPER + SHIFT + " .. key, function() hl.plugin.split_monitor_workspaces.move_to_workspace(i) end)
end

hl.bind("SUPER + S", hl.dsp.workspace.toggle_special("magic"))
hl.bind("SUPER + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

hl.bind("SUPER + mouse_down", function() hl.plugin.split_monitor_workspaces.cycle_workspaces("prev") end)
hl.bind("SUPER + mouse_up", function() hl.plugin.split_monitor_workspaces.cycle_workspaces("next") end)

hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true, repeating = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"), { locked = true, repeating = true })

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("vol --up"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("vol --down"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("bri --up"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("bri --down"), { locked = true, repeating = true })
hl.bind("XF86Search", hl.dsp.exec_cmd("launchpad"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

hl.bind("SUPER + O", hl.dsp.exec_cmd(home .. "/.config/hypr/scripts/toggle_lmb.sh"), { release = true })
