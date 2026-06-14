import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick

ShellRoot {
    Component.onCompleted: {
        // QSettings (used by widgets/wallpaper Settings) needs an org identity to write its conf file.
        Qt.application.organizationName = "quickshell";
        Qt.application.organizationDomain = "quickshell";
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: wallPickerWindow
                property var modelData
                screen: modelData
                visible: false
                color: "transparent"
                HyprlandWindow.opacity: 1.0
                // Grab keyboard while open so typing/Esc don't fall through to the app behind.
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "quickshell-wallpaper-picker"
                focusable: true
                anchors {
                    top: true
                    left: true
                    right: true
                    bottom: true
                }

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0.04, 0.04, 0.07, 0.42)
                }

                Loader {
                    id: pickerLoader
                    anchors.fill: parent
                    active: wallPickerWindow.visible
                    source: Qt.resolvedUrl("widgets/wallpaper/WallpaperPicker.qml")
                }

                IpcHandler {
                    target: "wallpaper-toggle-" + modelData.name

                    function setVisible(vis: bool): void {
                        if (vis) {
                            // Set before Loader activates so the embedded Settings element finds an org name.
                            Qt.application.organizationName = "quickshell";
                            Qt.application.organizationDomain = "quickshell";
                        }
                        wallPickerWindow.visible = vis;
                    }

                    function getVisible(): bool {
                        return wallPickerWindow.visible;
                    }
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: dockChooserWindow
                property var modelData
                screen: modelData
                visible: chooserLoader.status === Loader.Ready && chooserLoader.item !== null && chooserLoader.item.chooserVisible
                color: "transparent"
                HyprlandWindow.opacity: 1.0
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                WlrLayershell.layer: WlrLayer.Overlay
                focusable: false
                anchors {
                    top: true
                    left: true
                    right: true
                    bottom: true
                }

                Loader {
                    id: chooserLoader
                    anchors.fill: parent
                    active: true
                    source: Qt.resolvedUrl("widgets/dock/WindowChooserOverlay.qml")

                    onLoaded: {
                        if (item) {
                            item.actionFocus.connect(function(address, workspace) {
                                dockChooserWindow._focusToplevel(address, workspace)
                            })
                        }
                    }
                }

                function _findToplevel(addr) {
                    let tls = Hyprland.toplevels.values
                    if (!tls) return null
                    for (let i = 0; i < tls.length; i++) {
                        if (tls[i] && tls[i].address === addr) return tls[i]
                    }
                    return null
                }

                function _focusToplevel(address, workspaceName) {
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
                    if (chooserLoader.item) chooserLoader.item.chooserVisible = false
                }

                IpcHandler {
                    target: "dock-chooser-" + modelData.name

                    function setChooserVisible(vis: bool): void {
                        if (chooserLoader.item) chooserLoader.item.chooserVisible = vis;
                    }

                    function scheduleHide(): void {
                        if (chooserLoader.item) chooserLoader.item.scheduleHide();
                    }

                    function setSourceHovered(appId: string, hovered: bool): void {
                        if (chooserLoader.item) chooserLoader.item.setSourceHovered(appId, hovered);
                    }

                    function showChooser(appId: string, icon: string, anchorX: int, sourceX: int, sourceBottomOffset: int, sourceWidth: int, sourceHeight: int): void {
                        if (!chooserLoader.item) return;
                        chooserLoader.item.show(appId, icon, anchorX, sourceX, sourceBottomOffset, sourceWidth, sourceHeight);
                    }
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: dockWindow
                property var modelData
                property string screenName: modelData.name
                screen: modelData
                visible: false
                color: "transparent"
                HyprlandWindow.opacity: 0.95
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                WlrLayershell.layer: WlrLayer.Top
                focusable: false
                anchors {
                    bottom: true
                    left: true
                    right: true
                }
                implicitHeight: 86

                Loader {
                    anchors.fill: parent
                    active: dockWindow.visible
                    source: Qt.resolvedUrl("widgets/dock/Dock.qml")

                    onLoaded: {
                        if (item) {
                            item.screenName = dockWindow.screenName;
                        }
                    }
                }

                IpcHandler {
                    target: "dock-toggle-" + modelData.name

                    function setVisible(vis: bool): void {
                        dockWindow.visible = vis;
                    }

                    function getVisible(): bool {
                        return dockWindow.visible;
                    }
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: dockMenuWindow
                property var modelData
                property string menuTargetAppId: ""
                property string menuTargetAddress: ""
                screen: modelData
                visible: menuLoader.status === Loader.Ready && menuLoader.item !== null && menuLoader.item.menuVisible
                color: "transparent"
                HyprlandWindow.opacity: 1.0
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                WlrLayershell.layer: WlrLayer.Overlay
                focusable: false
                anchors {
                    top: true
                    left: true
                    right: true
                    bottom: true
                }

                Loader {
                    id: menuLoader
                    anchors.fill: parent
                    active: true
                    source: Qt.resolvedUrl("widgets/dock/ContextMenuOverlay.qml")

                    onLoaded: {
                        if (item) {
                            item.actionClose.connect(function() {
                                dockMenuWindow._closeToplevel()
                            })
                            item.actionFloat.connect(function() {
                                dockMenuWindow._toggleFloat()
                            })
                            item.actionCloseAll.connect(function() {
                                dockMenuWindow._closeAll()
                            })
                        }
                    }
                }

                function _findToplevel(addr) {
                    let tls = Hyprland.toplevels.values
                    if (!tls) return null
                    for (let i = 0; i < tls.length; i++) {
                        if (tls[i] && tls[i].address === addr) return tls[i]
                    }
                    return null
                }

                function _closeToplevel() {
                    let tl = _findToplevel(menuTargetAddress)
                    if (tl && tl.wayland) tl.wayland.close()
                    if (menuLoader.item) menuLoader.item.menuVisible = false
                }

                function _toggleFloat() {
                    let tl = _findToplevel(menuTargetAddress)
                    if (tl && tl.wayland) tl.wayland.activate()
                    Quickshell.exec(["sh", "-c", "hyprctl dispatch togglefloat"])
                    if (menuLoader.item) menuLoader.item.menuVisible = false
                }

                function _closeAll() {
                    let tls = Hyprland.toplevels.values
                    if (!tls) return
                    for (let i = 0; i < tls.length; i++) {
                        let tl = tls[i]
                        if (!tl) continue
                        let aid = tl.lastIpcObject ? tl.lastIpcObject.class || "" : ""
                        if (!aid) aid = tl.appId || ""
                        if (aid === menuTargetAppId && tl.wayland) tl.wayland.close()
                    }
                    if (menuLoader.item) menuLoader.item.menuVisible = false
                }

                IpcHandler {
                    target: "dock-menu-" + modelData.name

                    function setMenuVisible(vis: bool): void {
                        if (menuLoader.item) menuLoader.item.menuVisible = vis;
                    }

                    function setMenuTarget(appId: string, address: string, anchorX: int): void {
                        dockMenuWindow.menuTargetAppId = appId;
                        dockMenuWindow.menuTargetAddress = address;
                        menuLoader.item.targetAppId = appId;
                        menuLoader.item.targetAddress = address;
                        menuLoader.item.anchorX = anchorX;
                    }

                    function toggleMenuTarget(appId: string, address: string, anchorX: int): void {
                        if (!menuLoader.item) return;

                        if (menuLoader.item.menuVisible && dockMenuWindow.menuTargetAppId === appId) {
                            menuLoader.item.menuVisible = false;
                            return;
                        }

                        dockMenuWindow.menuTargetAppId = appId;
                        dockMenuWindow.menuTargetAddress = address;
                        menuLoader.item.targetAppId = appId;
                        menuLoader.item.targetAddress = address;
                        menuLoader.item.anchorX = anchorX;
                        menuLoader.item.menuVisible = true;
                    }
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: waybarConfigWindow
                property var modelData
                screen: modelData
                visible: false
                color: "transparent"
                HyprlandWindow.opacity: 1.0
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
                WlrLayershell.layer: WlrLayer.Overlay
                focusable: true
                anchors {
                    top: true
                    left: true
                    right: true
                    bottom: true
                }

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 0.45)
                }

                Loader {
                    id: configLoader
                    anchors.fill: parent
                    active: waybarConfigWindow.visible
                    source: Qt.resolvedUrl("widgets/waybar-config/WaybarConfig.qml")
                }

                IpcHandler {
                    target: "waybar-config-toggle-" + modelData.name

                    function setVisible(vis: bool): void {
                        waybarConfigWindow.visible = vis;
                    }

                    function getVisible(): bool {
                        return waybarConfigWindow.visible;
                    }
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: llmManagerWindow
                property var modelData
                screen: modelData
                visible: false
                color: "transparent"
                HyprlandWindow.opacity: 1.0
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "quickshell-llm-manager"
                focusable: true
                anchors {
                    top: true
                    left: true
                    right: true
                    bottom: true
                }

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 0.45)
                }

                Loader {
                    id: llmManagerLoader
                    anchors.fill: parent
                    active: llmManagerWindow.visible
                    source: Qt.resolvedUrl("widgets/llm-manager/LlmManager.qml")
                }

                IpcHandler {
                    target: "llm-manager-toggle-" + modelData.name

                    function setVisible(vis: bool): void {
                        llmManagerWindow.visible = vis;
                    }

                    function getVisible(): bool {
                        return llmManagerWindow.visible;
                    }
                }
            }
        }
    }
}
