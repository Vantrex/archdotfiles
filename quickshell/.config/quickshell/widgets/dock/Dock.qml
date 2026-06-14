import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "../.."

Item {
    id: dockRoot

    property real dockPadding: 4
    property real itemSpacing: 2
    property real cornerRadius: 22
    property real borderWidth: 1
    property color bgColor: matugen.base
    property color surfaceColor: matugen.mantle
    property color borderColor: matugen.surface1
    property color activeColor: matugen.blue
    property color textColor: matugen.text
    property real iconSize: 56
    property string home: Quickshell.env("HOME") || ""
    property string iconMapScript: home + "/.config/quickshell/widgets/dock/dock-icon-map.sh"
    property var desktopIconMap: ({})
    property var iconCache: ({})
    property bool iconsReady: false
    property string _prevSnapshot: ""
    property string activeWindowAddress: ""
    property string activeWorkspaceName: ""
    property bool activeWorkspaceHasWindows: false
    property string screenName: "unknown"
    property real emptyWidth: 120
    property real emptyHeight: 48

    MatugenColors {
        id: matugen
        sourceFile: "/tmp/qs_dock_colors.json"
    }

    Component.onCompleted: {
        desktopEntryLoader.running = true
        refreshAndRebuild()
    }

    Timer {
        id: rebuildTimer
        interval: 40
        running: false
        repeat: false
        triggeredOnStart: false
        onTriggered: rebuildGroupedApps()
    }

    Timer {
        id: safetyTimer
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: false
        onTriggered: refreshAndRebuild()
    }

    Connections {
        target: Hyprland.toplevels

        function onValuesChanged() {
            scheduleRebuild()
        }
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            dockRoot.onHyprlandEvent(event)
        }
    }

    Process {
        id: desktopEntryLoader
        running: false
        command: ["sh", dockRoot.iconMapScript]
        stdout: StdioCollector {
            onStreamFinished: {
                let map = {}
                let lines = this.text.split("\n")
                for (let i = 0; i < lines.length; i++) {
                    let fields = lines[i].split("\t")
                    if (fields.length !== 3 || !fields[2]) continue
                    let id = fields[0].toLowerCase()
                    let startupClass = fields[1].toLowerCase()
                    if (id && !map[id]) map[id] = fields[2]
                    if (startupClass && !map[startupClass]) map[startupClass] = fields[2]
                }
                dockRoot.desktopIconMap = map
                dockRoot.iconCache = {}
                dockRoot.iconsReady = true
                dockRoot._prevSnapshot = ""
                dockRoot.refreshAndRebuild()
            }
        }
    }

    Process {
        id: hyprctlDispatcher
        running: false
        stdout: StdioCollector {}
    }

    Process {
        id: menuTargetDispatcher
        running: false
        stdout: StdioCollector {}
    }

    Process {
        id: menuVisibilityDispatcher
        running: false
        stdout: StdioCollector {}
    }

    Process {
        id: chooserTargetDispatcher
        running: false
        stdout: StdioCollector {}
    }

    Process {
        id: chooserVisibilityDispatcher
        running: false
        stdout: StdioCollector {}
    }

    Process {
        id: activeWindowLoader
        running: false
        command: ["hyprctl", "activewindow", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let addr = ""
                try {
                    let data = JSON.parse(this.text || "{}")
                    addr = data.address || ""
                } catch (e) {
                    addr = ""
                }
                if (dockRoot.activeWindowAddress !== addr) {
                    dockRoot.activeWindowAddress = addr
                    scheduleRebuild()
                }
            }
        }
    }

    Process {
        id: activeWorkspaceLoader
        running: false
        command: ["hyprctl", "activeworkspace", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let wsName = ""
                let hasWindows = false
                try {
                    let data = JSON.parse(this.text || "{}")
                    wsName = data.name || ""
                    hasWindows = (data.windows || 0) > 0
                } catch (e) {
                    wsName = ""
                    hasWindows = false
                }
                if (dockRoot.activeWorkspaceName !== wsName || dockRoot.activeWorkspaceHasWindows !== hasWindows) {
                    dockRoot.activeWorkspaceName = wsName
                    dockRoot.activeWorkspaceHasWindows = hasWindows
                    scheduleRebuild()
                }
            }
        }
    }

    function onHyprlandEvent(event) {
        let e = event.name || ""
        if (e === "openwindow" || e === "closewindow" ||
            e === "movewindow" || e === "movewindowv2" ||
            e === "movetoworkspace" || e === "movetoworkspacev2" ||
            e === "activewindow" || e === "activewindowv2" ||
            e === "changefloatingmode" || e === "fullscreen" ||
            e === "workspace" || e === "workspacev2") {
            dockRoot.refreshAndRebuild()
        }
    }

    function scheduleRebuild() {
        rebuildTimer.restart()
    }

    function refreshAndRebuild() {
        activeWindowLoader.running = true
        activeWorkspaceLoader.running = true
        Hyprland.refreshToplevels()
        scheduleRebuild()
    }

    function resolveIconName(iconName) {
        if (!iconName) return ""
        if (iconName.charAt(0) === "/") return iconName
        return Quickshell.iconPath(iconName, "application-x-executable")
    }

    function iconify(className) {
        let c = className || ""
        let normalizedClass = c.toLowerCase()
        let cached = iconCache[normalizedClass]
        if (cached) return cached
        if (normalizedClass === "spotify") {
            let spotifyPath = resolveIconName("spotify-client")
            if (!spotifyPath) spotifyPath = resolveIconName("spotify")
            iconCache[normalizedClass] = spotifyPath
            return spotifyPath
        }
        let path = resolveIconName(desktopIconMap[normalizedClass])
        if (!path && Quickshell.hasThemeIcon(c)) {
            path = Quickshell.iconPath(c, "application-x-executable")
        }
        path = path || Quickshell.iconPath("application-x-executable")
        iconCache[normalizedClass] = path
        return path
    }

    function toplevelAppId(tl) {
        if (!tl) return ""
        let appId = ""
        if (tl.wayland) appId = tl.wayland.appId || ""
        if (!appId && tl.lastIpcObject) appId = tl.lastIpcObject.class || ""
        if (!appId) appId = tl.title || ""
        return appId
    }

    function normalizedAppId(appId) {
        return (appId || "").toLowerCase()
    }

    function toplevelTitle(tl) {
        if (!tl) return ""
        if (tl.wayland && tl.wayland.title) return tl.wayland.title
        return tl.title || ""
    }

    function toplevelWorkspace(tl) {
        if (tl && tl.workspace) return tl.workspace.name || "1"
        return "1"
    }

    function toplevelActive(tl) {
        if (!tl) return false
        let activeAddress = dockRoot.activeWindowAddress || ""
        let isActivated = tl.activated || (tl.wayland && tl.wayland.activated)
        let addressMatches = activeAddress !== "" && (tl.address || "") === activeAddress
        let workspaceMatches = !dockRoot.activeWorkspaceName || toplevelWorkspace(tl) === dockRoot.activeWorkspaceName
        return dockRoot.activeWorkspaceHasWindows && workspaceMatches && (isActivated || addressMatches)
    }

    function rebuildGroupedApps() {
        if (!dockRoot.iconsReady) return
        let tlist = Hyprland.toplevels.values
        if (!tlist) return
        let appMap = {}
        for (let i = 0; i < tlist.length; i++) {
            let tl = tlist[i]
            if (!tl) continue
            if (tl.lastIpcObject && tl.lastIpcObject.isinvisible) continue
            let appId = toplevelAppId(tl)
            if (!appId) continue
            let appKey = normalizedAppId(appId)
            if (!appMap[appKey]) {
                appMap[appKey] = {
                    appKey: appKey,
                    appId: appId,
                    displayName: appId,
                    icon: iconify(appId),
                    toplevels: [],
                    isActive: false
                }
            }
            let addr = tl.address || ""
            let wsName = toplevelWorkspace(tl)
            let title = toplevelTitle(tl)
            appMap[appKey].toplevels.push({
                address: addr,
                workspace: wsName,
                title: title || appId,
                active: toplevelActive(tl)
            })
            if (title && appMap[appKey].displayName === appId) {
                appMap[appKey].displayName = appId
            }
            if (toplevelActive(tl)) {
                appMap[appKey].isActive = true
                appMap[appKey].activeAddress = addr
                appMap[appKey].activeWorkspace = wsName
            }
        }
        let apps = []
        for (let key in appMap) {
            apps.push(appMap[key])
        }
        apps.sort(function(a, b) {
            if (a.isActive && !b.isActive) return -1
            if (!a.isActive && b.isActive) return 1
            return a.displayName.localeCompare(b.displayName)
        })
        let snap = ""
        for (let i = 0; i < apps.length; i++) {
            let windowSnap = ""
            for (let j = 0; j < apps[i].toplevels.length; j++) {
                windowSnap += apps[i].toplevels[j].address + "," + apps[i].toplevels[j].workspace + ";"
            }
            snap += apps[i].appKey + ":" + apps[i].isActive + ":" + (apps[i].activeAddress || "") + ":" + apps[i].toplevels.length + ":" + windowSnap + "|"
        }
        if (snap === dockRoot._prevSnapshot) return
        dockRoot._prevSnapshot = snap
        dockModel.clear()
        for (let i = 0; i < apps.length; i++) {
            let app = apps[i]
            let addr = app.activeAddress || app.toplevels[0].address
            let ws = app.activeWorkspace || app.toplevels[0].workspace
            dockModel.append({
                appId: app.appId,
                displayName: app.displayName,
                icon: app.icon || Quickshell.iconPath("application-x-executable"),
                windowCount: app.toplevels.length,
                isActive: app.isActive,
                targetAddress: addr,
                targetWorkspace: ws,
                windowsJson: JSON.stringify(app.toplevels)
            })
        }
    }

    ListModel {
        id: dockModel
    }

    Rectangle {
        id: dockShadow
        anchors {
            horizontalCenter: dockPanel.horizontalCenter
            verticalCenter: dockPanel.verticalCenter
            verticalCenterOffset: 5
        }
        width: dockPanel.width + 8
        height: dockPanel.height + 8
        radius: dockRoot.cornerRadius + 4
        color: "#000000"
        opacity: 0.35
    }

    Rectangle {
        id: dockPanel
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: 12
        }
        width: Math.max(dockContent.width + dockRoot.dockPadding * 2, dockModel.count === 0 ? dockRoot.emptyWidth : 0)
        height: Math.max(dockContent.height + dockRoot.dockPadding * 2, dockModel.count === 0 ? dockRoot.emptyHeight : 0)
        radius: dockRoot.cornerRadius
        gradient: Gradient {
            GradientStop { position: 0.0; color: dockRoot.surfaceColor }
            GradientStop { position: 1.0; color: dockRoot.bgColor }
        }
        border {
            width: dockRoot.borderWidth
            color: dockRoot.borderColor
        }

        Row {
            id: dockContent
            anchors.centerIn: parent
            spacing: dockRoot.itemSpacing
            visible: dockModel.count > 0

            Repeater {
                model: dockModel

                delegate: Loader {
                    active: true
                    asynchronous: false
                    width: dockRoot.iconSize + 8
                    height: dockRoot.iconSize + 8
                    source: Qt.resolvedUrl("DockItem.qml")

                    onLoaded: {
                        if (item) {
                            item.appId = model.appId
                            item.displayName = model.displayName
                            item.icon = model.icon
                            item.windowCount = model.windowCount
                            item.isActive = model.isActive
                            item.themeBlue = dockRoot.activeColor
                            item.themeText = dockRoot.textColor
                            item.themeSurface = dockRoot.surfaceColor
                            item.iconSize = dockRoot.iconSize
                            item.screenName = dockRoot.screenName
                            item.targetAddress = model.targetAddress
                            item.windowsJson = model.windowsJson

                            item.focusWindow.connect(function() {
                                focusApp(model.targetAddress, model.targetWorkspace)
                            })
                            item.closeWindow.connect(function() {
                                closeToplevel(model.targetAddress)
                            })
                            item.toggleFloat.connect(function() {
                                toggleFloatFor(model.targetAddress)
                            })
                            item.closeAll.connect(function() {
                                closeAllByAppId(model.appId)
                            })
                            item.requestMenu.connect(function(appId, address, anchorX) {
                                setChooserVisible(false)
                                openContextMenu(appId, address, anchorX)
                            })
                            item.dismissMenu.connect(function() {
                                setContextMenuVisible(false)
                            })
                            item.requestChooser.connect(function(appId, anchorX, sourceX, sourceY, sourceWidth, sourceHeight) {
                                setContextMenuVisible(false)
                                openChooser(appId, model.icon, anchorX, sourceX, sourceY, sourceWidth, sourceHeight)
                            })
                            item.dismissChooser.connect(function() {
                                scheduleChooserHide()
                            })
                            item.appHoverEntered.connect(function(appId) {
                                setChooserSourceHovered(appId, true)
                            })
                            item.appHoverExited.connect(function(appId) {
                                setChooserSourceHovered(appId, false)
                            })
                        }
                    }
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: dockModel.count === 0
            text: "No windows"
            color: dockRoot.textColor
            opacity: 0.8
            font.pixelSize: 13
        }
    }

    function _hyprctlDispatch(cmd) {
        hyprctlDispatcher.command = ["sh", "-c", "hyprctl dispatch " + cmd]
        hyprctlDispatcher.running = true
    }

    function setContextMenuVisible(vis) {
        menuVisibilityDispatcher.command = [
            "qs", "ipc", "call",
            "dock-menu-" + dockRoot.screenName,
            "setMenuVisible",
            vis ? "true" : "false"
        ]
        menuVisibilityDispatcher.running = true
    }

    function setChooserVisible(vis) {
        chooserVisibilityDispatcher.command = [
            "qs", "ipc", "call",
            "dock-chooser-" + dockRoot.screenName,
            "setChooserVisible",
            vis ? "true" : "false"
        ]
        chooserVisibilityDispatcher.running = true
    }

    function scheduleChooserHide() {
        chooserVisibilityDispatcher.command = [
            "qs", "ipc", "call",
            "dock-chooser-" + dockRoot.screenName,
            "scheduleHide"
        ]
        chooserVisibilityDispatcher.running = true
    }

    function setChooserSourceHovered(appId, hovered) {
        chooserVisibilityDispatcher.command = [
            "qs", "ipc", "call",
            "dock-chooser-" + dockRoot.screenName,
            "setSourceHovered",
            appId || "",
            hovered ? "true" : "false"
        ]
        chooserVisibilityDispatcher.running = true
    }

    function openContextMenu(appId, address, anchorX) {
        menuTargetDispatcher.command = [
            "qs", "ipc", "call",
            "dock-menu-" + dockRoot.screenName,
            "toggleMenuTarget",
            appId || "",
            address || "",
            String(anchorX)
        ]
        menuTargetDispatcher.running = true
    }

    function openChooser(appId, icon, anchorX, sourceX, sourceY, sourceWidth, sourceHeight) {
        chooserTargetDispatcher.command = [
            "qs", "ipc", "call",
            "dock-chooser-" + dockRoot.screenName,
            "showChooser",
            appId || "",
            icon || "",
            String(anchorX),
            String(sourceX),
            String(sourceY),
            String(sourceWidth),
            String(sourceHeight)
        ]
        chooserTargetDispatcher.running = true
    }

    function _findToplevel(addr) {
        let tls = Hyprland.toplevels.values
        if (!tls) return null
        for (let i = 0; i < tls.length; i++) {
            let tl = tls[i]
            if (!tl) continue
            let a = tl.address || ""
            if (a === addr) return tl
        }
        return null
    }

    function focusApp(address, workspaceName) {
        let wss = Hyprland.workspaces.values
        if (wss) {
            for (let i = 0; i < wss.length; i++) {
                if (wss[i].name === workspaceName) {
                    wss[i].activate()
                    break
                }
            }
        }
        let tl = _findToplevel(address)
        if (tl && tl.wayland) tl.wayland.activate()
    }

    function closeToplevel(address) {
        let tl = _findToplevel(address)
        if (tl && tl.wayland) tl.wayland.close()
    }

    function toggleFloatFor(address) {
        let tl = _findToplevel(address)
        if (tl && tl.wayland) tl.wayland.activate()
        _hyprctlDispatch("togglefloat")
    }

    function closeAllByAppId(appId) {
        let tlist = Hyprland.toplevels.values
        if (!tlist) return
        for (let i = 0; i < tlist.length; i++) {
            let tl = tlist[i]
            if (!tl) continue
            let thisAppId = toplevelAppId(tl)
            if (normalizedAppId(thisAppId) === normalizedAppId(appId)) {
                if (tl.wayland) tl.wayland.close()
            }
        }
    }
}
