import QtQuick
import Quickshell
import Quickshell.Hyprland

Item {
    id: root

    property int windowCount: 1
    property string appId: ""
    property string displayName: ""
    property string icon: Quickshell.iconPath("application-x-executable")
    property bool isActive: false
    property color themeText: "#cdd6f4"
    property color themeBlue: "#89b4fa"
    property color themeSurface: "#313244"
    property real iconSize: 56
    property real badgeSize: 20
    property string screenName: "unknown"
    property string targetAddress: ""
    property string windowsJson: "[]"

    signal focusWindow()
    signal closeWindow()
    signal toggleFloat()
    signal closeAll()
    signal requestMenu(string appId, string address, int anchorX)
    signal dismissMenu()
    signal requestChooser(string appId, int anchorX, int sourceX, int sourceY, int sourceWidth, int sourceHeight)
    signal dismissChooser()
    signal appHoverEntered(string appId)
    signal appHoverExited(string appId)

    width: iconSize + 8
    height: iconSize + 8

    Rectangle {
        id: iconRect
        anchors.centerIn: parent
        width: root.iconSize
        height: root.iconSize
        radius: width / 2
        color: "transparent"

        Image {
            anchors.centerIn: parent
            width: parent.width * 0.75
            height: parent.height * 0.75
            source: root.icon
            fillMode: Image.PreserveAspectFit

            Loader {
                anchors.centerIn: parent
                active: !parent.status || parent.status === Image.Error
                sourceComponent: Rectangle {
                    width: parent.width
                    height: parent.height
                    radius: width / 2
                    color: root.themeBlue
                    Text {
                        anchors.centerIn: parent
                        text: root.displayName ? root.displayName.substring(0, 1).toUpperCase() : "?"
                        color: "#ffffff"
                        font.pixelSize: parent.height * 0.5
                        font.bold: true
                    }
                }
            }
        }

        Rectangle {
            anchors {
                bottom: parent.bottom
                left: parent.left
                right: parent.right
                margins: -4
            }
            height: 3
            radius: 1.5
            color: root.isActive ? root.themeBlue : "transparent"
            visible: root.isActive
        }

        Rectangle {
            anchors {
                top: parent.top
                right: parent.right
                margins: -2
            }
            width: root.badgeSize
            height: root.badgeSize
            radius: root.badgeSize / 2
            visible: root.windowCount > 1
            color: root.themeBlue
            Text {
                anchors.centerIn: parent
                text: String(root.windowCount)
                color: "#ffffff"
                font.pixelSize: root.badgeSize * 0.6
                font.bold: true
            }
        }
    }

    PropertyAnimation {
        id: scaleUp
        target: root
        property: "scale"
        to: 1.15
        duration: 120
        easing.type: Easing.OutBack
    }
    PropertyAnimation {
        id: scaleDown
        target: root
        property: "scale"
        to: 1.0
        duration: 100
        easing.type: Easing.InOutQuad
    }

    Timer {
        id: chooserHoverTimer
        interval: 700
        repeat: false
        onTriggered: {
            if (root.windowCount <= 1) return
            let pos = root.mapToItem(null, root.width / 2, 0)
            let sourcePos = iconRect.mapToItem(null, 0, 0)
            root.dismissMenu()
            root.requestChooser(
                root.appId,
                Math.round(pos.x),
                Math.round(sourcePos.x),
                Math.round(sourcePos.y),
                Math.round(iconRect.width),
                Math.round(iconRect.height)
            )
        }
    }

    MouseArea {
        id: iconMouseArea
        anchors.fill: iconRect
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        propagateComposedEvents: false

        onEntered: {
            scaleUp.start()
            root.appHoverEntered(root.appId)
            if (root.windowCount > 1) chooserHoverTimer.restart()
        }
        onExited: {
            chooserHoverTimer.stop()
            root.appHoverExited(root.appId)
            scaleDown.start()
        }

        onPressed: (mouse) => {
            chooserHoverTimer.stop()
            if (mouse.button === Qt.LeftButton) {
                root.dismissMenu()
                root.dismissChooser()
                root.focusWindow()
            } else if (mouse.button === Qt.RightButton) {
                let pos = root.mapToItem(null, root.width / 2, 0)
                scaleDown.start()
                root.dismissChooser()
                root.requestMenu(root.appId, root.targetAddress, Math.round(pos.x))
            }
        }
    }
}
