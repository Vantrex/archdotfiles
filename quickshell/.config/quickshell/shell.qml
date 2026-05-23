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
                HyprlandWindow.opacity: 0.95
                // Grab keyboard while open so typing/Esc don't fall through to the app behind.
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
                    color: "#1e1e2e"
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
}
