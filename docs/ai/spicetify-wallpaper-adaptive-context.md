# Spotify Wallpaper-Adaptive Theming — Full Context

## Objective
Make Spotify dynamically adapt its colors to the desktop wallpaper using matugen v4 color extraction + a spicetify JS extension. No static `color.ini`. No restarts needed for updates.

---

## What Was Done

### 1. Custom Vibrant.js (inline, no dependencies)
- File: `~/.config/spicetify/Extensions/wallpaper-adaptive.js`
- Full implementation of Vibrant.js in vanilla JS: canvas draw → LAB color space histogram → swatch extraction
- Produces 6 swatches: `Vibrant`, `DarkVibrant`, `LightVibrant`, `Muted`, `DarkMuted`, `LightMuted`
- Each swatch has `.getHex()`, `.getRGB()`, `.getLuminance()`, `.getBodytext(bg)`

### 2. Extension Architecture
```
wallpaper-adaptive.js (501 lines)
├── injectCSS(vars) — writes <style id="wallpaper-adaptive-styles"> into <head>
├── applyFromMatugen(mat) — reads /tmp/qs_colors.json, maps to --spice-* vars
├── applyDefaults() — Catppuccin Mocha fallback (always called if no source found)
├── applyFromAlbumArt() — Vibrant.js on cover art (fallback 2)
├── loadWallpaperColors() — XHR fetch of /tmp/qs_colors.json
├── pollColors() — setInterval every 2s to detect wallpaper changes
└── startup() — waits for Spicetify API, registers songchange listener
```

### 3. CSS Variable Mapping (matugen → spicetify)
| matugen key | spicetify var | Purpose |
|---|---|---|
| base/crust/mantle/surface0/text/subtext1/overlay0/overlay1 | --spice-main, --spice-sidebar, etc. | Core palette |
| blue (base08) | --spice-button | Accent color |
| mauve (base0c) | derived from accent | Secondary accent |
| green (base0a) | derived from accent | Tertiary accent |

### 4. matugen-reload.sh Script
- File: `~/.config/spicetify/scripts/matugen-reload.sh`
- Runs `matugen --mode dark image --prefer darkness --json hex <wallpaper>`
- Parses base16 nested format → flat key-value JSON at `/tmp/qs_colors.json`
- Accent keys correctly use lowercase hex: `base08`, `base09`, `base0a`, ... (fixed from buggy `'base{8+i}'`)

### 5. wallpaper-colors.sh Script
- File: `~/.config/spicetify/scripts/wallpaper-colors.sh`
- Static color.ini generator (kept for completeness)
- Also fixed accent key format to `base{8+i:02x}`

### 6. Config Changes
```ini
# config-xpui.ini
current_theme          = dynamic-only    ← switched from "marketplace"
replace_colors         = 0               ← prevents static color overwriting
inject_css             = 1
extensions            = wallpaper-adaptive.js
custom_apps           = marketplace      ← still enabled (user wants to keep it)
```

### 7. Empty Theme Created
- `~/.config/spicetify/Themes/dynamic-only/color.ini` — empty, no hardcoded colors
- Prevents any theme from injecting static overrides

---

## What Is NOT Working

### Primary Issue: Spotify shows default/vanilla theme instead of adaptive colors

**Symptoms:**
- No color adaptation on startup
- DevTools cannot be opened (Ctrl+Shift+J also fails)
- `always_enable_devtools = 0` in config-xpui.ini — set to `1` but needs full Spotify restart which was attempted with `spotify --enable-logging=stderr --v=1 &` but timed out

**Attempted Fixes:**

| Attempt | Result |
|---|---|
| Inline styles via `style.setProperty()` | ❌ Too late — Spotify computed element styles before extension ran |
| CSS `<style>` injection into `<head>` | ⏳ Not verified (can't open DevTools) |
| Switched theme to `dynamic-only` (empty color.ini) | ✅ Applied, but needs Spotify restart |
| Removed `spicetify apply` from wallpaper-colors.sh | ✅ Prevents unwanted restarts |
| Fixed matugen accent key format (`base08-base0f`) | ✅ Verified: `/tmp/qs_colors.json` now has valid colors |

### Root Cause Hypothesis (unverified)

**Most likely:** Spotify reads CSS custom properties at initialization time and caches them. Our extension's `injectCSS()` writes variables into `<head>`, but if the timing is wrong — or if any stylesheet uses `var(--spice-*)` before our `<style>` element is parsed — those lookups resolve to empty/undefined values that get baked in.

**Secondary possibility:** The marketplace custom app (`custom_apps = marketplace`) injects its own background/wallpaper overlay via React rendering, which visually overrides our theme even if colors are correct.

---

## Verification Steps Needed (when DevTools works)

### Step 1: Check CSS variables exist
Open Console in Spotify DevTools → run:
```js
getComputedStyle(document.documentElement).getPropertyValue('--spice-main')
// Should return something like "#2e2c30" not "" or "undefined"
```

### Step 2: Check extension logs
Look for `[wallpaper-adaptive]` messages in Console. Expected output on success:
```
[wallpaper-adaptive] Applied wallpaper colors
```

If you see `No color source available, using defaults` → the XHR to `/tmp/qs_colors.json` is failing (CORS restriction from `file://` protocol).

### Step 3: Check for marketplace overlay
Inspect any element with a background/wallpaper class. If it has an inline style or background-image set by React, the marketplace app is overriding our theme visually even if CSS vars are correct.

---

## File Inventory

| File | Status | Notes |
|---|---|---|
| `~/.config/spicetify/Extensions/wallpaper-adaptive.js` | ✅ Written (501 lines) | CSS style injection, Vibrant.js inline, polling loop |
| `~/.config/spicetify/scripts/matugen-reload.sh` | ✅ Written | matugen v4 parsing with correct accent keys |
| `~/.config/spicetify/scripts/wallpaper-colors.sh` | ✅ Fixed | Accent key format corrected |
| `~/.config/spicetify/Themes/dynamic-only/color.ini` | ✅ Created (empty) | No static color overrides |
| `~/.config/spicetify/config-xpui.ini` | ✅ Modified | theme=dynamic-only, replace_colors=0 |
| `~/.config/spicetify/CustomApps/marketplace/` | ⚠️ Still loaded | May inject its own wallpaper overlay |
| `~/.config/spicetify/Themes/marketplace/color.ini` | ⚠️ Not cleared | Has hardcoded colors but theme is no longer active |

---

## Next Actions (Priority Order)

1. **Verify DevTools works** — `always_enable_devtools = 1` was set, restart Spotify and try Ctrl+Shift+J
2. **Check if CSS variables are actually present** in `<head>` or via `getComputedStyle`
3. **If marketplace custom app is overriding visually**, either disable it (`custom_apps =`) or patch its React code to not inject background styles
4. **If XHR fails due to CORS** (file:// protocol), switch from XMLHttpRequest to a different mechanism — perhaps use the filesystem watcher approach with a named pipe, or have matugen-reload.sh write directly to Spotify's raw assets directory

---

## Key Technical Details for Future Agents

### How spicetify extensions work
- Extensions are loaded as IIFE scripts into Spotify's DOM after bootstrap
- `Spicetify` API is available globally once the app initializes
- Use `Spicetify.showNotification()` to verify extension loaded successfully
- `Spicetify.Player.addEventListener("songchange", callback)` fires on track changes

### How CSS variables should be injected
```js
// WRONG — inline styles may be too late:
document.documentElement.style.setProperty("--spice-main", "#1e1e2e");

// RIGHT — stylesheet element in <head>:
var styleEl = document.createElement("style");
styleEl.id = "wallpaper-adaptive-styles";
document.head.appendChild(styleEl);
styleEl.textContent = ":root { --spice-main: #1e1e2e; ... }";
```

### matugen v4 JSON format (base16)
```json
{
  "base16": {
    "base08": { "dark": { "color": "#d97b2f" }, "default": {...}, "light": {...} },
    "base09": { "dark": { "color": "#178ea9" }, ... },
    "base0a": { "dark": { "color": "#2e9dab" }, ... }
  }
}
```
Accent keys are `base08` through `base0f` (lowercase hex). Python f-string must use `'base{8+i:02x}'` not `'base{8+i}'`.

### The marketplace custom app problem
The marketplace app loads from GitHub and renders a React UI. It may inject background/wallpaper styles via:
- `document.body.style.backgroundImage`
- A `<style>` element with `.main-view-container` or similar selectors
- Inline styles on root container elements

To diagnose: search for any element matching `.main-view-container, body, html` that has a non-default background-image or background-color set after extension loads.
