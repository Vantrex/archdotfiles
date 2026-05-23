# Wallpaper-Adaptive Spotify Theming — Issue Report

## Goal
Implement wallpaper-adaptive theming for Spotify via Spicetify using a dynamic JavaScript extension that reads matugen color output at runtime, avoiding static `color.ini` generation.

---

## Current State

### What's been implemented:
1. **Custom Vibrant.js** (`Extensions/wallpaper-adaptive.js`) — Full inline implementation (canvas → LAB histogram → swatch extraction) with 6 swatches matching the original Vibrant.js API: `Vibrant`, `DarkVibrant`, `LightVibrant`, `Muted`, `DarkMuted`, `LightMuted`. Each has `.getHex()`, `.getRGB()`, `.getLuminance()`, `.getBodytext(bg)`.

2. **Extension registered** in `config-xpui.ini`:
   ```ini
   extensions = wallpaper-adaptive.js
   replace_colors = 0
   ```

3. **`matugen-reload.sh`** — Generates `/tmp/qs_colors.json` from current wallpaper via matugen v4 → ImageMagick fallback, then triggers waybar adaptive update.

4. **Marketplace `color.ini` cleared** — All hardcoded colors removed so the dynamic extension is sole source of truth.

5. **`wallpaper-colors.sh`** — Static color.ini generator (kept for completeness), but no longer runs `spicetify apply`.

---

## The Problem

Despite all changes, Spotify still shows the default vanilla theme. Colors are not being applied.

### Root Causes Identified:
1. **No `/tmp/qs_colors.json` existed** — matugen hadn't been run on the current wallpaper yet (fixed by `matugen-reload.sh`).
2. **Accent keys format mismatch** — Python f-string `'base{8 + i}'` produced `base8`, `base9` instead of matugen v4's `base08`, `base09`. Fixed in both scripts.
3. **No fallback colors set** — When no source was available, the extension logged a message but never called `setRootColor()` → zero CSS variables → vanilla Spotify. Added `applyDefaults()`.

### Likely Remaining Issue (FIXED):

The dynamic extension was using `document.documentElement.style.setProperty()` which sets **inline styles** on `:root`. However, Spotify's stylesheet likely reads CSS variables at initialization time via `getComputedStyle` and caches them. By the time our extension runs, elements have already locked in their colors from empty/undefined variable values.

### Fix Applied (2025-05-08):

Switched to injecting a `<style>` element into `<head>` with all CSS variables defined on `:root`:
```js
var styleEl = document.createElement("style");
styleEl.id = "wallpaper-adaptive-styles";
document.head.appendChild(styleEl);

function injectCSS(vars) {
    var lines = [];
    for (var key in vars) {
        if (!vars.hasOwnProperty(key)) continue;
        lines.push("  --" + key + ": " + vars[key] + ";");
    }
    styleEl.textContent = ":root {\n" + lines.join("\n") + "\n}";
}
```

This ensures the cascade resolves correctly when Spotify's stylesheet uses `var(--spice-*)` — the variables are defined in the document head before any element-specific styles compute.

---

## What to Try Next (if still not working):

### Quick diagnostic:
Open Spotify DevTools (Ctrl+Shift+I) and run in Console:
```js
getComputedStyle(document.documentElement).getPropertyValue('--spice-main')
```
If this returns empty, check the `<head>` element for `#wallpaper-adaptive-styles` — it should contain all CSS variables.

### If still not working after fix:

**Option A — Use `Spicetify.CSS.insert()` API:**
```js
Spicetify.CSS.insert(`
  :root { --spice-main: #1e1e2e !important; ... }
`);
```

**Option B — Patch the color.ini approach differently:**
Have `wallpaper-colors.sh` write a minimal `color.ini` with only the variables that matter, and keep `replace_colors = 1`. This is less elegant but more reliable since spicetify's build-time injection guarantees specificity.

### Wallpaper change hook:
The extension polls `/tmp/qs_colors.json` every 2 seconds — this should work for wallpaper changes as long as `matugen-reload.sh` runs on each change. Add to your hyprland autostart or use `hyprctl bind` with a wallpaper-change signal.

---

## Files Modified (latest)
- `~/.config/spicetify/Extensions/wallpaper-adaptive.js` — **FIXED**: switched from inline styles (`style.setProperty`) to `<style>` element injection in `<head>`. This ensures CSS variables resolve correctly via the cascade before Spotify computes element styles.
- `~/.config/spicetify/config-xpui.ini` — `extensions = wallpaper-adaptive.js`, `replace_colors = 0`
- `~/.config/spicetify/scripts/matugen-reload.sh` — New script for matugen → JSON generation
- `~/.config/spicetify/Themes/marketplace/color.ini` — Cleared all hardcoded colors
- `~/.config/spicetify/scripts/wallpaper-colors.sh` — Removed `spicetify apply`, fixed accent key format

## Files Created
- `~/.config/spicetify/scripts/matugen-reload.sh` (new)
