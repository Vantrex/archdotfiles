# Waybar Tokyo Night Implementation Plan - AI/LLM Reference

## Last Updated: 2026-05-07

## Status: PLANNING (not yet implemented)

---

## 1. SYSTEM CONTEXT

### OS & Environment
- **OS**: Arch Linux
- **WM**: Hyprland (modular config at `~/.config/hypr/`, symlinked from `~/dotfiles/hyprland/.config/hypr/`)
- **Bar**: waybar 0.15.0 (`reload_style_on_change: true`)
- **Wallpaper daemon**: awww-daemon (replaces swww, same CLI)
- **Overlay widgets**: quickshell (QML-based, IPC system)
- **Color extraction**: matugen (outputs to `/tmp/qs_colors.json`)
- **Notifications**: swaync
- **Monitors**: `HDMI-A-2`, `DP-2`, `DP-3`
- **Dotfiles**: `~/dotfiles/`, symlinked manually (to be migrated to GNU Stow)

### Existing Symlink Structure
```
~/.config/waybar -> ../dotfiles/waybar/.config/waybar
~/.config/hypr  -> ../dotfiles/hyprland/.config/hypr
~/.config/quickshell -> ../dotfiles/quickshell/.config/quickshell
~/.config/ghostty -> ../dotfiles/ghostty/.config/ghostty
```

### Existing Waybar Config
- `config.jsonc`: Full module definitions (532 lines), already functional
- `style.css`: Monolithic (392 lines), hardcoded colors, no CSS variables
- `mouse.sh`: Hardware-specific mouse LED toggle script
- Key modules: workspaces, window, mpris, network, pulseaudio, cpu, memory, clock, battery, backlight, tray, notifications, custom modules

### Existing Quickshell Setup
- `shell.qml`: PanelWindow per monitor, loads `WallpaperPicker.qml`
- `MatugenColors.qml`: Reads `/tmp/qs_colors.json`, exposes Catppuccin Mocha colors as QML properties
- `WallpaperPicker.qml`: Full wallpaper carousel with search, categories, matugen theming
- `matugen_reload.sh`: Reloads kitty, cava, swaync, swayosd, GTK themes
- IPC targets: `wallpaper-toggle-<monitor>`

---

## 2. IMPLEMENTATION GOALS

### Primary Goals
1. Theme waybar with Tokyo Night (all 4 variants: storm, night, moon, day)
2. Make waybar CSS modular (per-module files, `@import`-based composition)
3. Add configurable transparency (50%-100%)
4. Build quickshell config panel for all waybar settings
5. Add wallpaper-adaptive colors (optional, blends TN with matugen output)
6. Implement bonus features (all individually toggleable)

### Bonus Features
- TN variant switcher module (click to cycle storm/night/moon/day)
- Hyprland mode indicator (resize/move/etc)
- Workspace app icons
- Rainbow animated border on active workspace
- Download/upload speed monitor
- Wallpaper adaptive colors (blend ratio configurable)

---

## 3. TARGET FILE STRUCTURE

```
~/dotfiles/
├── waybar/.config/waybar/
│   ├── config.jsonc              # Main waybar config (module JSON definitions)
│   ├── style.css                 # CSS entry point: @import chain
│   ├── themes/
│   │   ├── tokyo-night-storm.css   # TN Storm CSS variables
│   │   ├── tokyo-night-night.css   # TN Night CSS variables
│   │   ├── tokyo-night-moon.css    # TN Moon CSS variables
│   │   └── tokyo-night-day.css     # TN Day CSS variables
│   ├── modules/
│   │   ├── base.css                # Global: fonts, resets, window#waybar bg
│   │   ├── workspaces.css          # #workspaces, button states
│   │   ├── window.css              # #window
│   │   ├── system.css              # #cpu, #memory
│   │   ├── media.css               # #mpris
│   │   ├── network.css             # #network
│   │   ├── network-speed.css       # #custom-network-speed (bonus)
│   │   ├── audio.css               # #pulseaudio, sliders
│   │   ├── clock.css               # #clock
│   │   ├── battery.css             # #battery, #upower
│   │   ├── mode.css                # #hyprland-mode (bonus)
│   │   ├── backlight.css           # #backlight
│   │   ├── notifications.css       # #custom-notification
│   │   ├── tray.css                # #tray
│   │   ├── custom.css              # spacers, padding, led, etc.
│   │   └── animations.css          # keyframes, transitions, rainbow border
│   ├── scripts/
│   │   ├── theme-switcher.sh       # Cycle TN variant, write ~/.cache/waybar/active-theme
│   │   ├── wallpaper-adapt.sh      # Blend matugen colors + TN → adaptive CSS file
│   │   ├── network-speed.sh        # Output download/upload speeds for waybar custom module
│   │   └── mode-indicator.sh       # Output current Hyprland mode
│   └── waybar-settings.json        # Persisted config (transparency, features, etc.)
│
├── quickshell/.config/quickshell/
│   └── widgets/
│       └── waybar-config/
│           ├── WaybarConfig.qml     # Config panel widget
│           └── config-toggle.sh    # Toggle script (bound to keybind)
│
└── docs/
    ├── waybar-tokyo-night-plan.md  # Human-readable plan
    └── ai/
        └── waybar-tokyo-night-plan.md  # This file
```

---

## 4. TECHNICAL SPECIFICATIONS

### 4.1 CSS Variable Naming Convention

All theme files define the same variables with different values:

```css
:root {
  /* Base colors */
  --wb-bg: <hex>;           /* Main background */
  --wb-bg-dark: <hex>;      /* Darker background for sidebars/groups */
  --wb-bg-r: <int>;         /* Red component of --wb-bg (for alpha) */
  --wb-bg-g: <int>;         /* Green component of --wb-bg */
  --wb-bg-b: <int>;         /* Blue component of --wb-bg */
  --wb-bg-alpha: <float>;   /* Transparency level (0.5-1.0) */

  /* Text colors */
  --wb-fg: <hex>;           /* Primary foreground */
  --wb-fg-dark: <hex>;      /* Dimmed foreground */
  --wb-comment: <hex>;      /* Muted/comment color */

  /* Accent colors */
  --wb-blue: <hex>;
  --wb-green: <hex>;
  --wb-red: <hex>;
  --wb-purple: <hex>;
  --wb-cyan: <hex>;
  --wb-yellow: <hex>;
  --wb-magenta: <hex>;
  --wb-teal: <hex>;
  --wb-orange: <hex>;

  /* Derived colors */
  --wb-border: <hex>;       /* Border color (usually blue or cyan) */
  --wb-highlight: <hex>;    /* Highlight/selection background */
  --wb-tooltip-bg: <hex>;   /* Tooltip background */
}
```

### 4.2 Transparency Mechanism

Background is set via:
```css
window#waybar {
  background-color: rgba(var(--wb-bg-r), var(--wb-bg-g), var(--wb-bg-b), var(--wb-bg-alpha));
}
```

`--wb-bg-alpha` is written to a separate file `~/.cache/waybar/transparency.css` by the quickshell config panel, which is `@import`ed in `style.css`.

### 4.3 Theme Switching Mechanism

- Active theme stored in `~/.cache/waybar/active-theme` (plain text: `storm`, `night`, `moon`, or `day`)
- `style.css` uses a shell-based approach: a wrapper script regenerates `style.css` with the correct `@import` line when theme changes
- Alternative: use waybar's `exec` module to watch `active-theme` file and regenerate imports
- Simpler approach: `style.css` has a fixed `@import` chain but the active theme file is symlinked to `~/.config/waybar/themes/active.css`, and only `active.css` is imported

**Chosen approach**: Symlink `active.css` → `tokyo-night-<variant>.css`. `style.css` imports `themes/active.css`. Theme switcher updates the symlink. waybar reloads on change.

### 4.4 Wallpaper-Adaptive Colors

When enabled:
1. `wallpaper-adapt.sh` is called on wallpaper change (hooked via awww or hyprland exec-once)
2. Script reads `/tmp/qs_colors.json` (matugen output) and TN base palette
3. Blends each channel: `result = TN_color * (1 - ratio) + wall_color * ratio`
4. Outputs blended CSS variables to `~/.cache/waybar/adaptive-colors.css`
5. If `adaptive-colors.css` exists and adaptive mode is enabled, it `@import`s after the base theme (overriding TN values)
6. Blend ratio stored in `waybar-settings.json`, default 0.3

### 4.5 Configuration Persistence

Settings stored in `~/.config/waybar/waybar-settings.json`:

```json
{
  "theme": "storm",
  "transparency": 0.85,
  "wallpaperAdaptive": false,
  "adaptiveBlendRatio": 0.3,
  "features": {
    "themeSwitcher": true,
    "hyprlandMode": true,
    "workspaceAppIcons": true,
    "rainbowBorder": true,
    "networkSpeed": true
  },
  "modules": {
    "workspaces": true,
    "window": true,
    "mpris": true,
    "network": true,
    "pulseaudio": true,
    "cpu": true,
    "memory": true,
    "clock": true,
    "battery": true,
    "backlight": true,
    "notifications": true,
    "tray": true,
    "networkSpeed": true,
    "hyprlandMode": true
  }
}
```

### 4.6 Quickshell Config Panel

`WaybarConfig.qml` will:
- Be loaded via `shell.qml` (new `PanelWindow` or added to existing loader)
- Read/write `waybar-settings.json`
- Provide UI controls for all settings
- Trigger `waybar` reload via `hyprctl dispatch exec waybar` or by touching `style.css`
- Toggle via IPC target `waybar-config-toggle-<monitor>`
- Toggle script: `config-toggle.sh` (same pattern as `qs-wallpaper-toggle.sh`)

---

## 5. TOKYO NIGHT COLOR DATA

### Storm
```
bg=#24283b bg_dark=#1f2335 fg=#c0caf5 fg_dark=#a9b1d6
blue=#7aa2f7 green=#9ece6a red=#f7768e purple=#9d7cd8
cyan=#7dcfff yellow=#e0af68 magenta=#bb9af7 teal=#1abc9c
orange=#ff9e64 comment=#565f89 border=#1d202f
```

### Night
```
bg=#1a1b26 bg_dark=#16161e fg=#c0caf5 fg_dark=#a9b1d6
blue=#7aa2f7 green=#9ece6a red=#f7768e purple=#9d7cd8
cyan=#7dcfff yellow=#e0af68 magenta=#bb9af7 teal=#1abc9c
orange=#ff9e64 comment=#565f89 border=#1d202f
```

### Moon
```
bg=#222436 bg_dark=#1e2030 fg=#c0caf5 fg_dark=#a9b1d6
blue=#7aa2f7 green=#9ece6a red=#ff5370 purple=#9d7cd8
cyan=#7dcfff yellow=#e0af68 magenta=#bb9af7 teal=#1abc9c
orange=#ff9e64 comment=#444b6a border=#1b1b29
```

### Day
```
bg=#e1e2e7 bg_dark=#d6d7dc fg=#3760bf fg_dark=#2e3440
blue=#2e7de9 green=#519a63 red=#c53b53 purple=#6e59d9
cyan=#0f4b62 yellow=#c49a00 magenta=#a829cf teal=#336866
orange=#b15c00 comment=#9699a3 border=#c4c4cc
```

---

## 6. IMPLEMENTATION STEPS (ORDERED)

### Phase 1: Foundation
1. Migrate symlinks to GNU Stow (`.stow-local` for user-specific paths)
2. Create `themes/` directory with 4 TN variant CSS files
3. Create `active.css` symlink → `tokyo-night-storm.css`
4. Create `modules/` directory with per-module CSS files
5. Rewrite `style.css` as `@import` entry point
6. Verify waybar loads correctly with modular CSS

### Phase 2: Transparency & Theme Switching
7. Add RGB component variables to each theme file
8. Create `~/.cache/waybar/transparency.css` with `--wb-bg-alpha`
9. Write `theme-switcher.sh` (cycles variants, updates symlink)
10. Add theme switcher module to `config.jsonc`
11. Test all 4 variants and transparency levels

### Phase 3: Quickshell Config Panel
12. Create `WaybarConfig.qml` widget
13. Create `config-toggle.sh` and add to Hyprland keybinds
14. Wire up all settings to `waybar-settings.json`
15. Implement live reload (touch `style.css` or trigger waybar restart)

### Phase 4: Bonus Features
16. Implement rainbow animated border (`animations.css`)
17. Implement Hyprland mode indicator (`mode-indicator.sh` + `mode.css`)
18. Implement workspace app icons
19. Implement network speed monitor (`network-speed.sh` + `network-speed.css`)

### Phase 5: Wallpaper Adaptation
20. Write `wallpaper-adapt.sh` (blend matugen + TN)
21. Hook into wallpaper change event
22. Wire toggle and blend ratio to quickshell panel
23. Add waybar reload to `matugen_reload.sh`

### Phase 6: Polish
24. Test all feature combinations
25. Verify performance (no lag on reload)
26. Document keybinds and usage

---

## 7. KEY CONSIDERATIONS FOR IMPLEMENTATION

### CSS Reload Behavior
- waybar's `reload_style_on_change: true` watches `style.css` for modifications
- To trigger reload after changing a setting: `touch ~/.config/waybar/style.css`
- Changing the `active.css` symlink target DOES trigger reload (symlink change counts as modification)

### Module Visibility
- To show/hide modules dynamically: regenerate `config.jsonc` with the correct `modules-left`/`modules-center`/`modules-right` arrays, then restart waybar
- Alternative: use CSS `visibility: hidden` / `display: none` on specific module IDs (less clean but no restart needed)
- **Chosen approach**: CSS `display: none` for per-module visibility (no restart needed, instant)

### Script Modules
- Custom script modules use `exec` and `exec-if` in `config.jsonc`
- Scripts output plain text or JSON to `stdout`
- `return-type` set to `"text"` or `"json"` accordingly
- `interval` controls polling frequency

### awww Integration
- awww-daemon doesn't have a built-in webhook system
- Hook via Hyprland's `exec` on wallpaper keybind, or poll wallpaper path
- Alternative: modify `matugen_reload.sh` to also call `wallpaper-adapt.sh`

### Stow Configuration
- Use `.stow-local` file to exclude user-specific paths (like `/home/anik/` references)
- The `mouse.sh` script is hardware-specific, keep as-is or make configurable
- `config.jsonc` has hardcoded paths that need templating or variable substitution

### Performance
- Avoid excessive `interval` values in script modules (1s minimum for polling scripts)
- CSS `@import` has negligible overhead (waybar processes at load time)
- Rainbow animation uses CSS `@keyframes`, GPU-accelerated, no performance concern

---

## 8. EXISTING FILES TO PRESERVE / MODIFY

### Preserve As-Is
- `mouse.sh` - hardware-specific, don't touch
- `WallpaperPicker.qml` - working wallpaper picker, don't modify
- `matugen_reload.sh` - extend, don't replace
- `qs-wallpaper-toggle.sh` - pattern to follow for new toggle scripts

### Modify
- `config.jsonc` - add new modules (theme switcher, mode indicator, network speed)
- `style.css` - complete rewrite as `@import` entry point
- `matugen_reload.sh` - add waybar reload line
- `shell.qml` - add waybar config widget loader
- `autostart.conf` - may need adjustments if waybar startup changes

### Create New
- All files listed in Section 3 (target file structure)

---

## 9. VERIFICATION CHECKLIST

After implementation, verify:
- [ ] waybar starts without errors
- [ ] All 4 TN variants apply correctly
- [ ] Transparency slider works (50%-100%)
- [ ] Theme switcher module cycles variants on click
- [ ] Quickshell config panel opens/closes
- [ ] Settings persist across restarts
- [ ] Wallpaper adaptive mode blends colors correctly
- [ ] Rainbow border animates on active workspace
- [ ] Network speed module shows correct values
- [ ] Hyprland mode indicator updates on mode change
- [ ] Individual modules can be hidden/shown
- [ ] `reload_style_on_change` works for all CSS changes
- [ ] No visual regressions on any of 3 monitors
- [ ] Stow symlinks resolve correctly
