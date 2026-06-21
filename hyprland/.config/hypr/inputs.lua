hl.config({
  input = {
    kb_layout = "de",
    kb_variant = "",
    kb_model = "",
    kb_options = "",
    kb_rules = "",
    scroll_factor = 1,
    follow_mouse = 2,
    force_no_accel = 1,
    sensitivity = -0.5,
    touchpad = {
      natural_scroll = false,
    },
  },
  cursor = {
    no_hardware_cursors = false,
  },
})

hl.gesture({
  fingers = 3,
  direction = "horizontal",
  action = "workspace",
})

hl.device({
  name = "epic-mouse-v1",
  sensitivity = -0.5,
})
