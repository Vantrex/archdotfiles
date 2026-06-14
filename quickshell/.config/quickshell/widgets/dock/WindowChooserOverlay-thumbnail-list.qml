import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../.."

Item {
    id: chooserRoot

    property string targetAppId: ""
    property string appIcon: Quickshell.iconPath("application-x-executable")
    property int anchorX: width / 2
    property int sourceX: 0
    property int sourceY: 0
    property int sourceWidth: 0
    property int sourceHeight: 0
    property double openedAt: 0
    property real pointerX: -1
    property real pointerY: -1
    property bool sourceHovered: false
    property bool chooserVisible: false
    property var windows: []
    readonly property int rowHeight: 112
    readonly property int menuWidth: 520
    readonly property int edgeMargin: 8
    readonly property int dockOffset: 2
    readonly property int maxVisibleRows: 5
    readonly property int panelHeight: Math.min(windows.length, maxVisibleRows) * rowHeight + 8

    signal actionFocus(string address, string workspace)

    MatugenColors {
        id: matugen
        sourceFile: "/tmp/qs_dock_colors.json"
    }

    Component.onCompleted: {
        Hyprland.rawEvent.connect(function(event) {
            let e = event.name || event.eventName || ""
            if (e === "focus" || e === "createWindow" || e === "destroyWindow" ||
                e === "openwindow" || e === "closewindow" || e === "activewindow" ||
                e === "activewindowv2" || e === "workspace" || e === "workspacev2") {
                chooserRoot.chooserVisible = false
            }
        })
    }

    Timer {
        id: hideTimer
        interval: 180
        repeat: false
        onTriggered: {
            if (chooserRoot.isPointerInKeepZone()) {
                return
            }
            chooserRoot.chooserVisible = false
        }
    }

    Timer {
        id: openGraceTimer
        interval: 350
        repeat: false
        onTriggered: {
            if (!chooserRoot.chooserVisible) return
            if (!chooserRoot.isInPanel(chooserRoot.pointerX, chooserRoot.pointerY) &&
                !chooserRoot.sourceHovered) {
                chooserRoot.scheduleHide()
            }
        }
    }

    function toplevelAppId(tl) {
        if (!tl) return ""
        let appId = ""
        if (tl.wayland) appId = tl.wayland.appId || ""
        if (!appId && tl.lastIpcObject) appId = tl.lastIpcObject.class || ""
        if (!appId) appId = tl.title || ""
        return appId
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

    function matchingWindows(appId) {
        let result = []
        let tls = Hyprland.toplevels.values
        if (!tls) return result
        for (let i = 0; i < tls.length; i++) {
            let tl = tls[i]
            if (!tl) continue
            if (tl.lastIpcObject && tl.lastIpcObject.isinvisible) continue
            if (toplevelAppId(tl) !== appId) continue
            result.push({
                address: tl.address || "",
                workspace: toplevelWorkspace(tl),
                title: toplevelTitle(tl) || appId,
                active: tl.activated || (tl.wayland && tl.wayland.activated) || false,
                captureSource: tl.wayland || null
            })
        }
        return result
    }

    function show(appId, icon, x, sourceX, sourceBottomOffset, sourceWidth, sourceHeight) {
        let matched = matchingWindows(appId || "")
        chooserRoot.targetAppId = appId || ""
        chooserRoot.appIcon = icon || Quickshell.iconPath("application-x-executable")
        chooserRoot.windows = matched
        chooserRoot.anchorX = x
        chooserRoot.sourceWidth = sourceWidth || 56
        chooserRoot.sourceHeight = sourceHeight || 56
        chooserRoot.sourceX = chooserRoot.anchorX - chooserRoot.sourceWidth / 2
        chooserRoot.sourceY = chooserRoot.height - 12 - 72 + (72 - chooserRoot.sourceHeight) / 2
        chooserRoot.openedAt = Date.now()
        chooserRoot.pointerX = chooserRoot.sourceX + chooserRoot.sourceWidth / 2
        chooserRoot.pointerY = chooserRoot.sourceY + chooserRoot.sourceHeight / 2
        chooserRoot.sourceHovered = true
        hideTimer.stop()
        openGraceTimer.restart()
        chooserRoot.chooserVisible = matched.length > 1
    }

    function scheduleHide() {
        if (chooserRoot.chooserVisible) hideTimer.restart()
    }

    function setSourceHovered(appId, hovered) {
        if (!chooserRoot.chooserVisible) return
        if ((appId || "") !== chooserRoot.targetAppId) {
            if (hovered) chooserRoot.chooserVisible = false
            return
        }
        chooserRoot.sourceHovered = hovered
        if (hovered) {
            hideTimer.stop()
        } else {
            chooserRoot.scheduleHide()
        }
    }

    function menuX() {
        let centered = chooserRoot.anchorX - chooserRoot.menuWidth / 2
        let maxX = Math.max(chooserRoot.edgeMargin, chooserRoot.width - chooserRoot.menuWidth - chooserRoot.edgeMargin)
        return Math.max(chooserRoot.edgeMargin, Math.min(centered, maxX))
    }

    function menuY() {
        return Math.max(chooserRoot.edgeMargin, chooserRoot.height - chooserRoot.dockOffset - chooserPanel.height)
    }

    function isInPanel(x, y) {
        return x >= chooserPanel.x && x <= chooserPanel.x + chooserPanel.width &&
            y >= chooserPanel.y && y <= chooserPanel.y + chooserPanel.height
    }

    function isInSourceApp(x, y) {
        if (chooserRoot.sourceWidth <= 0 || chooserRoot.sourceHeight <= 0) return false
        return x >= chooserRoot.sourceX && x <= chooserRoot.sourceX + chooserRoot.sourceWidth &&
            y >= chooserRoot.sourceY && y <= chooserRoot.sourceY + chooserRoot.sourceHeight
    }

    function isInOpenGracePeriod() {
        return Date.now() - chooserRoot.openedAt < 350
    }

    function updatePointer(x, y) {
        chooserRoot.pointerX = x
        chooserRoot.pointerY = y
    }

    function isPointerInKeepZone() {
        return chooserRoot.isInPanel(chooserRoot.pointerX, chooserRoot.pointerY) ||
            chooserRoot.sourceHovered ||
            chooserRoot.isInOpenGracePeriod()
    }

    MouseArea {
        anchors.fill: parent
        enabled: chooserRoot.chooserVisible
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onPositionChanged: (mouse) => {
            chooserRoot.updatePointer(mouse.x, mouse.y)
            if (chooserRoot.isPointerInKeepZone()) {
                hideTimer.stop()
            } else {
                chooserRoot.scheduleHide()
            }
        }

        onClicked: (mouse) => {
            if (!chooserRoot.isInPanel(mouse.x, mouse.y)) chooserRoot.chooserVisible = false
        }

        // Entering the chooser panel can make this fullscreen catcher lose hover.
        // Panel/delegate exits handle hiding from that point.
    }

    Rectangle {
        id: chooserPanel
        x: chooserRoot.menuX()
        y: chooserRoot.menuY()
        width: chooserRoot.menuWidth
        height: chooserRoot.panelHeight
        visible: chooserRoot.chooserVisible
        opacity: chooserRoot.chooserVisible ? 1 : 0
        radius: 8
        color: matugen.surface0
        border {
            width: 1
            color: matugen.blue
        }

        Behavior on x {
            NumberAnimation {
                duration: 100
                easing.type: Easing.OutQuad
            }
        }

        NumberAnimation on opacity {
            duration: 120
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onEntered: {
                chooserRoot.updatePointer(chooserPanel.x + 1, chooserPanel.y + 1)
                hideTimer.stop()
            }
            onExited: chooserRoot.scheduleHide()
        }

        ListView {
            id: windowList
            anchors.fill: parent
            anchors.margins: 4
            clip: true
            interactive: chooserRoot.windows.length > chooserRoot.maxVisibleRows
            boundsBehavior: Flickable.StopAtBounds
            model: chooserRoot.windows

            delegate: Rectangle {
                id: windowDelegate

                width: windowList.width
                height: chooserRoot.rowHeight
                radius: 5
                property bool hovered: false
                color: hovered ? "#45475a" : "transparent"

                Rectangle {
                    id: previewFrame
                    anchors {
                        left: parent.left
                        leftMargin: 8
                        verticalCenter: parent.verticalCenter
                    }
                    width: 160
                    height: 90
                    radius: 6
                    clip: true
                    color: "#11111b"
                    border {
                        width: 1
                        color: windowDelegate.hovered ? matugen.blue : "#313244"
                    }

                    ScreencopyView {
                        id: preview
                        anchors.fill: parent
                        captureSource: modelData.captureSource
                        live: chooserRoot.chooserVisible && windowDelegate.hovered
                        paintCursor: false
                        constraintSize: Qt.size(previewFrame.width, previewFrame.height)

                        Component.onCompleted: captureFrame()
                        onCaptureSourceChanged: captureFrame()
                        onVisibleChanged: {
                            if (visible) captureFrame()
                        }
                    }

                    Image {
                        anchors.centerIn: parent
                        width: 36
                        height: 36
                        source: chooserRoot.appIcon
                        fillMode: Image.PreserveAspectFit
                        visible: !preview.hasContent
                        opacity: 0.9
                    }
                }

                Column {
                    anchors {
                        left: previewFrame.right
                        leftMargin: 12
                        right: parent.right
                        rightMargin: 12
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 6

                    Text {
                        width: parent.width
                        text: modelData.title || chooserRoot.targetAppId
                        color: "#cdd6f4"
                        font.pixelSize: 14
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                    }

                    Text {
                        width: parent.width
                        text: "Workspace " + (modelData.workspace || "?")
                        color: "#a6adc8"
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }

                Rectangle {
                    anchors {
                        left: parent.left
                        top: parent.top
                        bottom: parent.bottom
                    }
                    width: 3
                    radius: 1.5
                    visible: modelData.active || false
                    color: matugen.blue
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    propagateComposedEvents: false
                    onEntered: {
                        parent.hovered = true
                        let pos = parent.mapToItem(chooserRoot, 1, 1)
                        chooserRoot.updatePointer(pos.x, pos.y)
                        hideTimer.stop()
                    }
                    onExited: {
                        parent.hovered = false
                    }
                    onClicked: {
                        chooserRoot.actionFocus(modelData.address || "", modelData.workspace || "")
                        chooserRoot.chooserVisible = false
                    }
                }
            }
        }
    }
}
