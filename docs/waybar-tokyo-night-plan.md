# Tokyo Night Waybar - Implementation Plan

> **Date**: 2026-05-07 &nbsp;|&nbsp; **Status**: Planning &nbsp;|&nbsp; **AI reference**: [`docs/ai/waybar-tokyo-night-plan.md`](./ai/waybar-tokyo-night-plan.md)

---

## What We're Building

A **modular, Tokyo Night-themed waybar** that's transparent, configurable through a quickshell panel, and optionally adapts its colors to your wallpaper. Every feature is individually toggleable. All files managed via GNU Stow.

---

## Your Current Setup

| Component | Version | Notes |
|-----------|---------|-------|
| Hyprland | modular config | 13 source files in `~/.config/hypr/` |
| waybar | 0.15.0 | `reload_style_on_change: true` |
| awww-daemon | git | Wallpaper daemon (replaces swww) |
| quickshell | installed | QML overlay widgets, IPC system |
| matugen | installed | Color extraction from wallpapers |
| swaync | running | Notification daemon |
| Monitors | 3 | `HDMI-A-2`, `DP-2`, `DP-3` |

---

## File Structure After Implementation

```
~/.config/waybar/                          ← stow symlinked
├── config.jsonc                           # Module definitions
├── style.css                              # CSS entry point (@import chain)
├── themes/                                # Tokyo Night variant themes
│   ├── active.css                         # → symlink to current variant
│   ├── tokyo-night-storm.css
│   ├── tokyo-night-night.css
│   ├── tokyo-night-moon.css
│   └── tokyo-night-day.css
├── modules/                               # Per-module CSS
│   ├── base.css                           # Fonts, resets, window bg
│   ├── workspaces.css
│   ├── window.css
│   ├── system.css                         # CPU, memory
│   ├── media.css                          # MPRIS
│   ├── network.css
│   ├── network-speed.css                  # Bonus: speed monitor
│   ├── audio.css                          # PulseAudio + sliders
│   ├── clock.css
│   ├── battery.css
│   ├── mode.css                           # Bonus: Hyprland mode
│   ├── backlight.css
│   ├── notifications.css
│   ├── tray.css
│   ├── custom.css                         # Spacers, padding, led
│   └── animations.css                     # Rainbow border, transitions
├── scripts/
│   ├── theme-switcher.sh                  # Cycle TN variants
│   ├── wallpaper-adapt.sh                 # Blend TN + wallpaper colors
│   ├── network-speed.sh                   # Emit up/down speeds
│   └── mode-indicator.sh                  # Emit current Hyprland mode
├── waybar-settings.json                   # Persisted config
└── mouse.sh                               # (preserved, hardware-specific)

~/.config/quickshell/widgets/waybar-config/  ← stow symlinked
├── WaybarConfig.qml                       # Config panel widget
└── config-toggle.sh                       # Toggle via keybind
```

---

## Core Features

### Tokyo Night - All 4 Variants

| Variant | Background | Accent | Vibe |
|---------|-----------|--------|------|
| **Storm** | `#24283b` | Blue `#7aa2f7` | Balanced, most popular |
| **Night** | `#1a1b26` | Blue `#7aa2f7` | Darkest, high contrast |
| **Moon** | `#222436` | Red `#ff5370` | Softer, muted |
| **Day** | `#e1e2e7` | Blue `#2e7de9` | Light mode |

Switch between variants by clicking a module in the bar, or through the quickshell config panel.

### Transparency

Pick your opacity: **50%** (very see-through) to **100%** (solid). The bar background uses the Tokyo Night palette with your chosen alpha channel. Your wallpaper shows through.

### Modular CSS

Each module has its own CSS file. Want to tweak the clock? Edit `modules/clock.css` -- waybar reloads instantly. No more hunting through a 400-line monolithic stylesheet.

### Wallpaper-Adaptive Colors (Optional)

When enabled, waybar colors gently shift toward your wallpaper's palette. Tokyo Night stays as the base -- it doesn't replace it, just tints it. Blend ratio is adjustable from 0% (pure TN) to 100% (full wallpaper colors). Default: 30%.

---

## Bonus Features (All Toggleable)

| Feature | What It Does |
|---------|-------------|
| TN Variant Switcher | Click a module to cycle Storm / Night / Moon / Day |
| Hyprland Mode Indicator | Shows when you're in resize, move, or float mode |
| Workspace App Icons | Shows which apps are on each workspace |
| Rainbow Animated Border | Active workspace border cycles through TN rainbow colors |
| Download Speed Monitor | Shows real-time network upload/download speeds |
| Wallpaper Adaptive Colors | Waybar colors shift to match your wallpaper |

Every feature can be turned on or off individually through the quickshell panel.

---

## Quickshell Configuration Panel

A dedicated overlay widget lets you control everything:

- **Theme selector**: Pick Storm, Night, Moon, or Day
- **Transparency slider**: 50% to 100%
- **Wallpaper adaptive toggle**: On/off with blend ratio slider
- **Feature toggles**: Each bonus feature has its own switch
- **Module visibility**: Show/hide individual bar modules

Settings are saved to `waybar-settings.json` and persist across restarts.

---

## How It Works Under the Hood

### Theme Switching
A symlink `active.css` points to the current variant file. `style.css` imports `themes/active.css`. When you switch themes, the symlink updates and waybar reloads automatically.

### Transparency
Each theme file includes RGB component variables for the background color. The alpha value is written to a separate CSS file that's imported after the theme, overriding just the opacity.

### Wallpaper Adaptation
When a wallpaper changes, matugen extracts colors (already wired up). `wallpaper-adapt.sh` blends those with the TN palette and writes a CSS override file. waybar picks it up on its next reload cycle.

### Module Visibility
Uses CSS `display: none` on module IDs -- no waybar restart needed. Changes are instant.

---

## Implementation Order

1. **Foundation** -- Stow setup, split CSS into modules, create theme files
2. **Transparency & Switching** -- Alpha channel, theme switcher script
3. **Quickshell Panel** -- Config widget, persistence, live reload
4. **Bonus Features** -- Each feature implemented one at a time
5. **Wallpaper Adaptation** -- Integrate with matugen pipeline
6. **Polish** -- Test all combinations, animations, transitions

---

## Color Reference

<details>
<summary><b>Tokyo Night Storm</b></summary>

bg: `#24283b` · bg_dark: `#1f2335` · fg: `#c0caf5` · fg_dark: `#a9b1d6`
blue: `#7aa2f7` · green: `#9ece6a` · red: `#f7768e` · purple: `#9d7cd8`
cyan: `#7dcfff` · yellow: `#e0af68` · magenta: `#bb9af7` · teal: `#1abc9c`
orange: `#ff9e64` · comment: `#565f89` · border: `#1d202f`

</details>

<details>
<summary><b>Tokyo Night Night</b></summary>

bg: `#1a1b26` · bg_dark: `#16161e` · fg: `#c0caf5` · fg_dark: `#a9b1d6`
blue: `#7aa2f7` · green: `#9ece6a` · red: `#f7768e` · purple: `#9d7cd8`
cyan: `#7dcfff` · yellow: `#e0af68` · magenta: `#bb9af7` · teal: `#1abc9c`
orange: `#ff9e64` · comment: `#565f89` · border: `#1d202f`

</details>

<details>
<summary><b>Tokyo Night Moon</b></summary>

bg: `#222436` · bg_dark: `#1e2030` · fg: `#c0caf5` · fg_dark: `#a9b1d6`
blue: `#7aa2f7` · green: `#9ece6a` · red: `#ff5370` · purple: `#9d7cd8`
cyan: `#7dcfff` · yellow: `#e0af68` · magenta: `#bb9af7` · teal: `#1abc9c`
orange: `#ff9e64` · comment: `#444b6a` · border: `#1b1b29`

</details>

<details>
<summary><b>Tokyo Night Day</b></summary>

bg: `#e1e2e7` · bg_dark: `#d6d7dc` · fg: `#3760bf` · fg_dark: `#2e3440`
blue: `#2e7de9` · green: `#519a63` · red: `#c53b53` · purple: `#6e59d9`
cyan: `#0f4b62` · yellow: `#c49a00` · magenta: `#a829cf` · teal: `#336866`
orange: `#b15c00` · comment: `#9699a3` · border: `#c4c4cc`

</details>

---

## What Stays, What Changes

### Preserved as-is
- `mouse.sh` -- your hardware-specific mouse LED script
- `WallpaperPicker.qml` -- working wallpaper picker
- `qs-wallpaper-toggle.sh` -- pattern to follow for new toggle scripts

### Extended
- `matugen_reload.sh` -- adds waybar reload to the reload chain

### Rewritten
- `style.css` -- becomes an `@import` entry point
- `config.jsonc` -- adds new modules

### Created New
- Everything under `themes/`, `modules/`, `scripts/`, and `waybar-config/`
