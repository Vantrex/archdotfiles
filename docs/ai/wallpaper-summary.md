# Quickshell Wallpaper Picker Implementation Summary

## Date Started: 2026-05-03

## Goal
Replace the existing Rofi-based wallpaper picker with a Quickshell-based overlay widget, inspired by:
https://github.com/ilyamiro/nixos-configuration/tree/master/config/sessions/hyprland/scripts/quickshell/wallpaper

---

## Installed Packages
| Package | Source | Purpose |
|---------|--------|---------|
| `quickshell` | pacman | QML shell for overlay widgets |
| `matugen` | yay/AUR | Generates color palettes from images |
| `imagemagick` | pacman | Thumbnail generation (magick) |
| `awww-git` | already installed | Wallpaper daemon (replaces `swww`) |

---

## File Structure
```
~/dotfiles/
├── install-scripts/
│   ├── install-quickshell.sh
│   └── install-matugen.sh
├── quickshell/.config/quickshell/
│   ├── shell.qml                    ← entry point, PanelWindow per monitor
│   ├── Scaler.qml                   ← rewritten self-contained (no WindowRegistry.js)
│   ├── MatugenColors.qml            ← unused now (inlined into WallpaperPicker)
│   ├── WindowRegistry.js            ← unused now (inlined into WallpaperPicker)
│   ├── qs-wallpaper-toggle.sh       ← IPC toggle script
│   └── widgets/wallpaper/
│       ├── WallpaperPicker.qml      ← main widget (heavily modified, see below)
│       ├── ddg_search.sh            ← DuckDuckGo/Pinterest image search
│       ├── get_ddg_links.py         ← DDG scraper
│       ├── pinterest_search.py      ← Pinterest scraper (custom)
│       └── matugen_reload.sh        ← reloads Kitty/CAVA/SwayNC/GTK themes
└── hyprland/.config/hypr/
    ├── autostart.conf               ← added "exec-once = quickshell &"
    └── keybinds.conf                ← Ctrl+Super+Space → qs-wallpaper-toggle.sh
```

---

## Modifications Made to WallpaperPicker.qml

### Path Changes
- `srcDir` default: `~/Pictures/Wallpapers` → `~/work/walls` (our actual wallpaper dir, 1,642 files in 50+ subdirs)
- `swww img` → `awww img` throughout (same CLI, `awww` is our renamed `swww`)
- Removed NixOS-specific paths (`/run/current-system/sw/bin`)

### Scaler & Theme Inlined
- `WindowRegistry.js` is **not importable** in Quickshell (`Ignoring non-directory import`)
- `import "../"` also failed (`module "../" is not installed`)
- **Solution:** Inlined scaling logic as `_baseScale` property + `s()` function directly in `WallpaperPicker.qml`
- **Solution:** Inlined Catppuccin Mocha palette as a typed `QtObject` with `id: _theme` (color properties expose `.r/.g/.b`)
- Removed `import "../"` from `WallpaperPicker.qml`

### Other Changes
- `mpvpaper` video handling → replaced with `awww img` (animated GIFs work natively)
- `srcModel.recursive: true` → **removed** (not supported in this Qt version); replaced with shell-built `path_map.txt`
- Orphaned code at old line 689-693 → removed (was causing `Unexpected token 'if'` errors)
- Added `categoryMap` + `_categoryFilters` for folder-based filtering (now sourced from `path_map.txt`)
- Matugen theming is opt-in (disabled by default, "M" toggle button)
- DDG + Pinterest search toggle ("DDG"/"PT" button)

---

## shell.qml Architecture
```
ShellRoot
└── Variants { model: Quickshell.screens }
    └── PanelWindow (per monitor)
        ├── Rectangle (#1e1e2e, full screen)
        ├── Loader { active: wallPickerWindow.visible }
        │   └── WallpaperPicker.qml
        └── IpcHandler { target: "wallpaper-toggle-<monitor>" }
            ├── setVisible(bool)
            └── getVisible()
```
- `PanelWindow.visible` defaults to `false`
- `HyprlandWindow.opacity: 0.95` (95% opaque overlay)
- `Loader` only activates when window becomes visible (lazy loading)
- 3 monitors: `HDMI-A-2`, `DP-2`, `DP-3`

---

## Current State (2026-05-04, after fix pass)

### What Works
- Widget loads without fatal QML errors
- Thumbnail generation runs via `triggerThumbGeneration()` (shell `find` + `magick`)
- 1,574 thumbnails generated in `~/.cache/wallpaper_picker/thumbs/`
- Carousel renders with cover-flow/skewed card effect
- Center image is enlarged, side images are smaller and dimmed

### Recently Applied Fixes

1. **`_theme` color bindings** — converted from JS object to typed `QtObject` with `property color` fields. `_theme.X.r/.g/.b` now resolve. **NOT TESTED!** (loads cleanly, visual correctness not yet user-confirmed)
2. **Scroll wheel** — `scrollThreshold` lowered from `s(300)` to `s(80)`; throttle bumped to 180ms; delegate Behaviors at 320ms `OutCubic`; `highlightMoveDuration` 320. **NOT TESTED!** (user previously reported it as snappy-but-buggy at 220ms/60ms throttle, retuned)
3. **Click-to-select** — reverted to original behavior: clicking any thumbnail applies that wallpaper. **NOT TESTED!**
4. **`verticalCenter of null` warnings** — guarded with `parent ? parent.verticalCenter : undefined`. **NOT TESTED!**
5. **Bash syntax errors** — removed stray `|| true` lines after `cp ... /tmp/lock_bg.png` (cached + download branches). **NOT TESTED!**
6. **WebP thumbnails** — thumb generator now writes WebP sources as `.png` thumbnails (and video thumbs as `000_<base>.png`). **NOT TESTED!** (cache wiped + regen triggered)
7. **Recursive scanning + category filtering** — `srcModel`/`categoryModel` removed. Thumbnail script writes `~/.cache/wallpaper_picker/path_map.txt` (`thumb|src_full_path|category` per line); a `Process` + 2 s `Timer` parses it into `sourcePathMap`, `categoryMap`, and `_categoryFilters`. **NOT TESTED!**
8. **`applyWallpaper` source path** — now resolves the real source via `sourcePathMap[safeFileName]` instead of assuming flat layout under `srcDir`. **NOT TESTED!**
9. **Dynamic theme updates** — added inline `Process` + 1.5 s `Timer` in `WallpaperPicker.qml` that reads `/tmp/qs_colors.json` and updates `_theme` in place. **NOT TESTED!**
10. **Esc-to-close** — Escape now closes the picker via `Window.window.visible = false`. Falls back to clearing search filter / blurring search input first if those are active. **NOT TESTED!**
11. **Filter bar stability** — `filterBarBackground.width` is now a fixed centered width `Math.min(s(1180), window.width - s(80))`, with `clip:true`. Stops the bar from shifting horizontally when notification text changes during scroll. **NOT TESTED!**
12. **Top bar Y-axis jump** — `isReady` now latches via `_hasBeenReady` set from `localFolderModel.onStatusChanged`, so transient `Loading` flickers no longer animate the bar back up. **NOT TESTED!**
13. **Continuous "infinite" scroll feel** — wheel handler removed throttle, threshold lowered to `s(40)`, and now consumes the accumulator in chunks of N steps so fast wheel spins navigate many items per event. delegate Behaviors trimmed to 180ms; `highlightMoveDuration` 180. **NOT TESTED!**
14. **Keyboard focus grab** — `WlrLayershell.keyboardFocus = Exclusive` + `WlrLayershell.layer = Overlay` + `focusable: true` on the PanelWindow. Stops keystrokes/Esc from reaching the app behind. **NOT TESTED!**
15. **Thumb gen race** — added a PID-based lock (`~/.cache/wallpaper_picker/.thumb_gen.lock`) so concurrent `qs` restarts don't truncate `path_map.txt.tmp` mid-write.
16. **Scrollable category bar** — categories are no longer crammed into the top filter bar. New `categoryBarBackground` rectangle sits just below the top bar, same width, with an inner `Flickable` (`HorizontalFlick`) wrapping a Row of category pills. A wheel `MouseArea` translates vertical scroll into `catFlick.contentX` so the wheel scrolls the row sideways. Bar fades in once `_categoryFilters` populates.
17. **Toggle script targets active monitor only** — `qs-wallpaper-toggle.sh` parses `hyprctl activeworkspace` (no `jq` dep) for the focused monitor and only toggles `wallpaper-toggle-<that-monitor>`. The hide path still broadcasts to every monitor as a safety net.
18. **Video/GIF apply** — `applyWallpaper` for `isVideo` now branches by extension: `.gif` → passed straight to `awww img`; `.mp4 / .mkv / .webm / .mov` → fall back to the first-frame PNG thumb because `awww`/`swww` only handles still images and animated GIFs. Real video playback would need `mpvpaper` (not currently installed).
19. **Auto-close on select** — new `autoCloseToggleBtn` ("X" pill, default ON, persisted in `Settings.autoCloseEnabled`). When ON, `applyWallpaper` calls `Qt.callLater(closePanel)` after dispatching its bash script, in both the local and the search/download branches.
20. **Keybind / focus + interaction fixes** — PanelWindow gets `WlrLayershell.keyboardFocus = Exclusive`, `WlrLayershell.layer = Overlay`, `focusable: true` so keystrokes/Esc no longer leak to the app behind. `STATE_FILE` (`/tmp/qs_wallpicker_state`) re-synced after manual IPC tests.
21. **Focused wallpaper name** — `focusedNameLabel` Text element anchored above the bottom of the screen, centered, shows the cleaned filename (drops the `000_` video prefix and the file extension) of the currently focused carousel item. Reads from `window.activeModel.get(view.currentIndex).fileName`.
22. **Custom tooltip overlay** — single `globalTooltip` Rectangle (no `QtQuick.Controls` dep) driven by `window.showTooltip(target, text)` / `hideTooltip(target)` from each button's `MouseArea.onContainsMouseChanged`. Positioned just below the hovered target, clamped to screen bounds, fades in/out. Wired to: monitor-selector icon, matugen "M", auto-close "X", WEB/LOCAL search-mode pill, DDG/PT source, search pause/play, search magnifier, submit arrow, and the small color/Video/All filter pills.
23. **Offline / Online search toggle** — new `searchModeBtn` (`"LOCAL"` / `"WEB"`, default `LOCAL`, kept in `window.searchMode`). In LOCAL mode `searchInput.onTextEdited` updates `window.offlineQuery`, bumps `cacheVersion`, and `checkItemMatchesFilter` returns matches against `localProxyModel` filenames (substring match). DDG/Pinterest source toggle, the Pause/Resume button, and the Submit arrow all hide while in LOCAL mode. WEB mode behaves as before (DDG / Pinterest scrape with downloaded thumbs).
24. **Debounced online search** (2026-05-04) — new `onlineSearchDebounce` Timer (500 ms, non-repeating). In WEB mode, `searchInput.onTextEdited` calls `onlineSearchDebounce.restart()`, so the DDG/Pinterest pipeline fires automatically after the user stops typing — Enter / submit button no longer required. Empty input stops the timer. The timer's `onTriggered` skips the run if the trimmed text matches `searchState.query` (avoids duplicate searches when nothing changed). `triggerOnlineSearch()` no longer drops `searchInput.focus` itself (was yanking focus mid-typing); that focus drop now lives only in the explicit submit paths (`onAccepted`, submit-button click) and in the LOCAL toggle path (which also calls `onlineSearchDebounce.stop()`).
25. **Debounced offline search** (2026-05-04) — new `offlineSearchDebounce` Timer (250 ms, non-repeating, with a `pending` string property). In LOCAL mode, `searchInput.onTextEdited` now writes the typed text into `offlineSearchDebounce.pending` and calls `restart()` instead of mutating `window.offlineQuery` synchronously. `onTriggered` commits `pending` → `offlineQuery`, bumps `cacheVersion`, and calls `updateVisibleCount()`. Stops thrashing the proxy filter on every keystroke for users with large local libraries. `searchModeBtn` toggle path also calls `offlineSearchDebounce.stop()` on both branches so a pending fire doesn't clobber the explicit mode-switch state. Quickshell was restarted after this change (ran `qs kill` → `qs -d`, instance `xsc59eiet`).

### Known Bugs / Open Items

- **`QSettings` init warning still appears** — `Qt.application.organizationName` set in `shell.qml:Component.onCompleted` and again in `IpcHandler.setVisible` doesn't reach `QSettings` in time (Settings element constructed during synchronous Loader load). Persistence may silently fail. Non-critical; if needed, replace the `Settings` element with a manual JSON file written via `Process`.
- **`path_map.txt` had to be regenerated by hand** after the QML thumb script lost races on the previous restarts. With the new PID lock this should self-heal, but if the picker shows fewer wallpapers than expected, run the loop in `triggerThumbGeneration()` directly in a shell as a one-off.

---

## What Still Needs to Be Done

1. Restart quickshell and verify each "NOT TESTED!" fix above
2. Wipe `~/.cache/wallpaper_picker/thumbs` once so WebP thumbs regenerate as PNG
3. Confirm `~/.cache/wallpaper_picker/path_map.txt` is created and populated after first thumb pass
4. Verify category filter buttons appear in the filter bar and filter correctly
5. Test apply with a wallpaper from a subdirectory (e.g. `~/work/walls/abstract/foo.png`) — both image and video
6. Test matugen-on toggle + dynamic theme reload (write something to `/tmp/qs_colors.json` and watch colors update)

---

## Quickshell Restart Procedure
After any QML change:
```bash
qs kill
rm -rf /run/user/1000/quickshell/vfs/29ce5a83c35601439380f5acc2779ea0
qs -d
sleep 2
qs ipc call wallpaper-toggle-DP-3 setVisible true
```

## Useful Commands
```bash
qs list                    # show running instances
qs log                     # show logs
qs kill                    # kill all instances
qs ipc show                # show IPC targets
qs ipc call <target> <fn>  # call IPC function
```
