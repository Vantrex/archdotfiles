import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../.."

Item {
    id: ctxRoot

    property string targetAppId: ""
    property string targetAddress: ""
    property int anchorX: width / 2
    property bool menuVisible: false
    readonly property int menuWidth: 168
    readonly property int menuHeight: 116
    readonly property int edgeMargin: 8
    readonly property int dockOffset: 2

    MatugenColors {
        id: matugen
        sourceFile: "/tmp/qs_dock_colors.json"
    }

    Component.onCompleted: {
        Hyprland.rawEvent.connect(function(event) {
            let e = event.name || event.eventName || ""
            if (e === "focus" || e === "createWindow" || e === "destroyWindow" ||
                e === "openwindow" || e === "closewindow") {
                ctxRoot.menuVisible = false
            }
        })
    }

    signal actionClose()
    signal actionFloat()
    signal actionCloseAll()

    function menuX() {
        let centered = ctxRoot.anchorX - ctxRoot.menuWidth / 2
        let maxX = Math.max(ctxRoot.edgeMargin, ctxRoot.width - ctxRoot.menuWidth - ctxRoot.edgeMargin)
        return Math.max(ctxRoot.edgeMargin, Math.min(centered, maxX))
    }

    MouseArea {
        anchors.fill: parent
        enabled: ctxRoot.menuVisible
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: ctxRoot.menuVisible = false
    }

    Rectangle {
        id: menuPanel
        x: ctxRoot.menuX()
        y: Math.max(ctxRoot.edgeMargin, ctxRoot.height - ctxRoot.dockOffset - height)
        width: ctxRoot.menuWidth
        height: ctxRoot.menuHeight
        visible: ctxRoot.menuVisible
        opacity: ctxRoot.menuVisible ? 1 : 0
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

        Column {
            id: menuContent
            anchors.fill: parent
            anchors.margins: 4
            spacing: 2

            Repeater {
                model: [
                    { text: qsTr("Close"), action: "close", danger: false },
                    { text: qsTr("Toggle Float"), action: "float", danger: false },
                    { text: "", action: "separator", danger: false },
                    { text: qsTr("Close All"), action: "closeAll", danger: true }
                ]

                delegate: Item {
                    width: menuContent.width
                    height: modelData.action === "separator" ? 6 : 32

                    Rectangle {
                        visible: modelData.action === "separator"
                        anchors.centerIn: parent
                        width: parent.width
                        height: 1
                        color: "#89b4fa"
                        opacity: 0.5
                    }

                    Rectangle {
                        visible: modelData.action !== "separator"
                        anchors.fill: parent
                        radius: 4
                        property bool hovered: false
                        color: hovered ? "#45475a" : "transparent"

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            text: modelData.text
                            color: modelData.danger ? "#f38ba8" : "#cdd6f4"
                            font.pixelSize: 13
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            propagateComposedEvents: false
                            onEntered: parent.hovered = true
                            onExited: parent.hovered = false
                            onClicked: {
                                if (modelData.action === "close") ctxRoot.actionClose()
                                else if (modelData.action === "float") ctxRoot.actionFloat()
                                else if (modelData.action === "closeAll") ctxRoot.actionCloseAll()
                                ctxRoot.menuVisible = false
                            }
                        }
                    }
                }
            }
        }
    }
}
