# Quickshell Application Dock

A macOS-style dock powered by Quickshell that shows all open applications, supports toggling via `SUPER + D`, focuses applications on left-click (switching to their workspace if needed), and provides a right-click context menu for window management.

## File Overview

```
quickshell/.config/quickshell/
├── shell.qml                          # root — adds dock PanelWindow per monitor
└── widgets/dock/
    ├── Dock.qml                       # main dock bar, window grouping, dispatch
    ├── DockItem.qml                   # per-app icon, hover, click, context menu
    └── dock-toggle.sh                 # toggle visibility via qs ipc call

hyprland/.config/hypr/
└── keybinds.lua                       # SUPER+D binding added
```

## How It Works

### 1. Toggle Mechanism (`SUPER + D`)

**Flow:** `keybinds.lua` → `dock-toggle.sh` → `qs ipc call` → `IpcHandler` in `shell.qml` → dock visibility

When `SUPER + D` is pressed:

1. Hyprland dispatches `exec_cmd` pointing to `dock-toggle.sh`
2. The script determines the active monitor from `hyprctl activeworkspace`
3. It calls `qs ipc call dock-toggle-<monitor> setVisible true/false`
4. The `IpcHandler` in `shell.qml` receives the call and toggles `dockWindow.visible`
5. The `Loader` inside the dock window lazily loads `Dock.qml` when visible (memory-efficient)

State is tracked in `/tmp/qs_dock_state` — same pattern as the wallpaper picker and waybar config toggle. Pressing `SUPER + D` again hides the dock on **all** monitors (not just the one it was opened on), preventing orphaned docks.

### 2. Window Enumeration and Grouping (`Dock.qml`)

**Source of truth:** `Hyprland.toplevels` — Quickshell's reactive `ObjectModel<HyprlandToplevel>` that mirrors Hyprland's window list.

**Grouping algorithm** (runs every 800ms via `Timer`, plus on `Component.onCompleted`):

1. Iterate all entries in `Hyprland.toplevels`
2. Extract `appId` from `toplevel.wayland.appId` (falls back to `toplevel.title`)
3. Skip entries with no identifier and skip invisible layer-surface windows (detected via `lastIpcObject.isinvisible`)
4. Group into a map keyed by `appId`. Each group tracks:
   - Array of toplevels belonging to that app
   - Whether any of them is currently activated
   - The `address` and `workspace.name` of the first toplevel in the group (used as the representative for focus/close actions)
5. Sort: active apps first, then alphabetical
6. Push into a `ListModel` (`dockModel`) which drives the `Repeater`

**Why polling?** The `Hyprland.toplevels` ObjectModel emits `itemInserted`/`itemRemoved` signals, but the internal state of individual toplevels (e.g. activation changes, workspace moves) may not always trigger model-level events. An 800ms poll is a pragmatic balance between responsiveness and overhead.

### 3. Focus on Left-Click (`DockItem.qml` → `Dock.qml`)

When a dock item is left-clicked:

1. `DockItem` emits the `focusWindow()` signal
2. The signal is connected (in `Dock.qml`'s `onLoaded`) to `focusApp(address, workspaceName)`
3. `focusApp` dispatches two Hyprland commands:
   - `workspace <name>` — switches to the workspace where the target window lives
   - `focuswindowaddress <address>` — focuses the specific window by its Hyprland address

This two-step dispatch is necessary because `focuswindowaddress` alone may fail if the window is on a different workspace. Switching workspace first ensures the target is reachable.

### 4. Context Menu on Right-Click (`DockItem.qml`)

A `QsMenu` with four `QsMenuItem` entries is defined declaratively in each `DockItem`. On right-click, `QsMenuEntry.display(root, x, y)` shows the native system menu at the click position.

**Menu actions:**

| Action | What it does |
|--------|-------------|
| Focus Window | Same as left-click: switches workspace + focuses window |
| Close Window | `closewindowaddress <addr>` — closes the representative window |
| Toggle Float | `focuswindowaddress <addr>` then `togglefloat` — toggles floating mode |
| Close All | Iterates `Hyprland.toplevels`, collects all addresses matching the same `appId`, dispatches `closewindowaddress` for each |

### 5. Visual Feedback

- **Active indicator**: A 3px blue dot beneath the icon when the app has a focused window
- **Count badge**: A circular badge in the top-right corner showing the number of windows for that app (hidden when count = 1)
- **Hover animation**: 15% scale-up with `OutBack` easing on hover, smooth return on leave
- **Icon fallback**: Tries `Qt.platformTheme.icon(appId).source`. If the icon fails to load, shows a blue circle with the first letter of the app name
- **Dock background**: Semi-transparent rounded rectangle (`#1e1e2ecc`) with a subtle border

### 6. Per-Monitor Dock

Each monitor gets its own `PanelWindow` instance (declared in `shell.qml` via `Variants` over `Quickshell.screens`). Each instance:

- Has its own `IpcHandler` with a monitor-scoped target (`dock-toggle-DP-3`, `dock-toggle-DP-2`, etc.)
- Lists all windows across all workspaces (not just the monitor's workspaces)
- Sits at `WlrLayer.Bottom` — below regular windows but above the wallpaper
- Uses `WlrKeyboardFocus.Ignore` — the dock doesn't steal keyboard focus
- Is non-focusable (`focusable: false`) so clicks outside dock items pass through

### 7. Layer Stack

The dock uses `WlrLayer.Bottom` which places it:

```
Top:  Overlay (wallpaper picker, waybar config)
      ...
Middle: Top (regular application windows)
Bottom: Bottom (dock ← lives here)
        Background
Lowest: Background (wallpaper)
```

This means regular windows will visually sit above the dock, which is the desired behavior for a bottom-centered macOS-style dock. If you want the dock always visible above windows, change `WlrLayer.Bottom` to `WlrLayer.Overlay` in `shell.qml`.

## Dispatch Commands Reference

| Hyprland Dispatch | Purpose |
|---|---|
| `workspace <name>` | Switch to workspace by name/number |
| `focuswindowaddress <hex>` | Focus a window by its Hyprland memory address |
| `closewindowaddress <hex>` | Close a specific window |
| `togglefloat` | Toggle float on the currently focused window |

## Tuning

| Property | File | Default | Description |
|----------|------|---------|-------------|
| `refreshInterval` | `Dock.qml` | 800ms | How often the window list is rebuilt |
| `iconSize` | `Dock.qml` | 56px | Size of each dock icon |
| `cornerRadius` | `Dock.qml` | 18 | Dock bar corner radius |
| `itemSpacing` | `Dock.qml` | 8 | Gap between icons |
| `bgColor` / `borderColor` | `Dock.qml` | Catppuccin | Semi-transparent hex colors |

## Future Improvements

- **Matugen color integration**: Currently hardcodes Catppuccin Mocha colors. Could be wired to `MatugenColors.qml` for live theme switching.
- **Workspace-scoped dock**: Show only windows on the current workspace, with a toggle for "all workspaces".
- **Drag to reorder**: Persistent custom ordering of dock items.
- **Move to workspace submenu**: The context menu could include "Move to workspace 1-10" entries.
- **Event-driven updates**: Replace the polling timer with reactive bindings to `Hyprland.toplevels.itemInserted` / `itemRemoved` / `itemChanged`.