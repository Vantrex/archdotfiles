import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io

Item {
    id: root
    width: Screen.width
    height: Screen.height

    // Resolve via env so this works for any user.
    property string home: Quickshell.env("HOME") || "/home/marinus"
    property string configDir: home + "/.config/waybar"
    property string mutateScript: configDir + "/scripts/settings-mutate.sh"
    property string themeSetScript: configDir + "/scripts/theme-set.sh"

    property var settings: ({})
    property var families: []   // [{id, name, variants:[{id,label,mode}]}]

    // ------ Settings I/O ----------------------------------------------------
    Process {
        id: settingsReader
        running: false
        command: ["cat", configDir + "/waybar-settings.json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.settings = JSON.parse(this.text); }
                catch (e) { console.log("WaybarConfig: settings parse failed", e); }
            }
        }
    }

    Process {
        id: familiesReader
        running: false
        command: [
            "python3", "-c",
            "import json,os,sys\n" +
            "root='" + configDir + "/themes'\n" +
            "out=[]\n" +
            "for fam in sorted(os.listdir(root)):\n" +
            "    p=os.path.join(root,fam,'family.json')\n" +
            "    if os.path.isfile(p):\n" +
            "        with open(p) as f: out.append(json.load(f))\n" +
            "print(json.dumps(out))"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.families = JSON.parse(this.text); }
                catch (e) { console.log("WaybarConfig: families parse failed", e); }
            }
        }
    }

    // Use Quickshell.execDetached for fire-and-forget commands (matches the
    // pattern in WallpaperPicker.qml where Process reuse proved flaky).
    function exec(args) {
        Quickshell.execDetached(args);
    }

    // After any mutation, settings.json on disk has changed; re-read it after
    // a short delay so the panel UI reflects the new state.
    Timer {
        id: refreshTimer
        interval: 250
        repeat: false
        onTriggered: {
            settingsReader.running = false;
            settingsReader.running = true;
        }
    }

    function mutate(key, value) {
        Quickshell.execDetached([mutateScript, key, JSON.stringify(value)]);
        refreshTimer.restart();
    }
    function setTheme(family, variant) {
        Quickshell.execDetached([themeSetScript, family, variant]);
        refreshTimer.restart();
    }
    function applyBorders() {
        Quickshell.execDetached([home + "/.config/hypr/scripts/apply-border-colors.sh"]);
    }

    Component.onCompleted: {
        settingsReader.running = true;
        familiesReader.running = true;
    }

    // ------ Helpers ---------------------------------------------------------
    function activeFamilyManifest() {
        for (var i = 0; i < families.length; i++) {
            if (families[i].id === settings.themeFamily) return families[i];
        }
        return families.length > 0 ? families[0] : null;
    }

    // ------ Visual constants ------------------------------------------------
    readonly property color cBg:       "#1a1b26"
    readonly property color cBgDeep:   "#16161e"
    readonly property color cBorder:   "#7aa2f7"
    readonly property color cFg:       "#c0caf5"
    readonly property color cFgDim:    "#a9b1d6"
    readonly property color cAccent:   "#7aa2f7"
    readonly property color cAccentOn: "#9ece6a"
    readonly property color cAccentOff:"#414868"

    // Click-outside-to-close
    MouseArea {
        anchors.fill: parent
        onClicked: card.visible ? closePanel() : null
    }

    function closePanel() {
        Quickshell.execDetached([home + "/.config/quickshell/widgets/waybar-config/waybar-config-toggle.sh"]);
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 580
        height: Math.min(parent.height - 40, 840)
        color: root.cBg
        border.color: root.cBorder
        border.width: 2
        radius: 14

        // Swallow clicks so the outer MouseArea doesn't close us.
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            // Header
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Style Settings"
                    color: root.cFg
                    font.pixelSize: 22
                    font.bold: true
                    Layout.fillWidth: true
                }
                Rectangle {
                    width: 28; height: 28; radius: 14
                    color: closeMa.containsMouse ? "#f7768e" : root.cAccentOff
                    Text { anchors.centerIn: parent; text: "×"; color: root.cFg; font.pixelSize: 18; font.bold: true }
                    MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.closePanel() }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: root.cAccentOff }

            // Scrollable content
            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: parent.width
                contentHeight: contentCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: contentCol
                    width: parent.width
                    spacing: 16

                    // ---- Theme section
                    SectionHeader { text: "Theme" }

                    // Family selector (radio row)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Repeater {
                            model: root.families
                            Pill {
                                label: modelData.name
                                active: modelData.id === root.settings.themeFamily
                                onActivated: {
                                    // Switch to family's first dark variant by default
                                    var firstDark = modelData.variants.find(function(v){ return v.mode === "dark" });
                                    var pick = firstDark ? firstDark.id : modelData.variants[0].id;
                                    root.setTheme(modelData.id, pick);
                                }
                            }
                        }
                    }

                    // Variant grid
                    Text { text: "Variant"; color: root.cFgDim; font.pixelSize: 13 }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 4
                        columnSpacing: 8
                        rowSpacing: 8
                        Repeater {
                            model: root.activeFamilyManifest() ? root.activeFamilyManifest().variants : []
                            Pill {
                                label: modelData.label + (modelData.mode === "light" ? " ☀" : "")
                                active: modelData.id === root.settings.themeVariant
                                onActivated: root.setTheme(root.settings.themeFamily, modelData.id)
                            }
                        }
                    }

                    // ---- Transparency
                    SectionHeader { text: "Transparency" }
                    LabeledSlider {
                        label: "Opacity"
                        value: root.settings.transparency !== undefined ? root.settings.transparency : 0.85
                        from: 0.5; to: 1.0; step: 0.05
                        onCommitted: root.mutate("transparency", v)
                    }

                    // ---- Wallpaper-adaptive
                    SectionHeader { text: "Wallpaper Adaptive" }
                    Toggle {
                        label: "Blend matugen colors with theme"
                        active: !!root.settings.wallpaperAdaptive
                        onToggled: root.mutate("wallpaperAdaptive", v)
                    }
                    LabeledSlider {
                        label: "Blend ratio"
                        value: root.settings.adaptiveBlendRatio !== undefined ? root.settings.adaptiveBlendRatio : 0.3
                        from: 0.0; to: 1.0; step: 0.05
                        interactive: !!root.settings.wallpaperAdaptive
                        onCommitted: root.mutate("adaptiveBlendRatio", v)
                    }

                    // ---- Spicetify adaptive
                    SectionHeader { text: "Spicetify Adaptive" }
                    Toggle {
                        label: "Adapt Spotify colors to wallpaper"
                        active: !!root.settings.spicetifyAdaptive
                        onToggled: root.mutate("spicetifyAdaptive", v)
                    }

                    // ---- Window Borders
                    SectionHeader { text: "Window Borders" }
                    Toggle {
                        label: "Blend borders with wallpaper colors"
                        active: !!root.settings.borderAdaptive
                        onToggled: root.mutate("borderAdaptive", v)
                    }
                    Toggle {
                        label: "Vibrant (bright Nord blue)"
                        active: !!root.settings.borderVibrant
                        interactive: !!root.settings.borderAdaptive
                        onToggled: root.mutate("borderVibrant", v)
                    }
                    Toggle {
                        label: "Wallpaper dominance"
                        active: !!root.settings.borderWallpaperDominance
                        interactive: !!root.settings.borderAdaptive
                        onToggled: root.mutate("borderWallpaperDominance", v)
                    }
                    LabeledSlider {
                        label: "Border blend ratio"
                        value: root.settings.borderBlendRatio !== undefined ? root.settings.borderBlendRatio : 0.3
                        from: 0.0; to: 1.0; step: 0.05
                        interactive: !!root.settings.borderAdaptive && !!root.settings.borderWallpaperDominance
                        onCommitted: root.mutate("borderBlendRatio", v)
                    }
                    Toggle {
                        label: "Gradient border"
                        active: root.settings.borderGradient !== false
                        interactive: !!root.settings.borderAdaptive
                        onToggled: root.mutate("borderGradient", v)
                    }
                    Toggle {
                        label: "Adapt inactive border"
                        active: !!root.settings.borderInactiveAdapt
                        interactive: !!root.settings.borderAdaptive
                        onToggled: root.mutate("borderInactiveAdapt", v)
                    }

                    // ---- Features
                    SectionHeader { text: "Features" }
                    Toggle {
                        label: "Rainbow border on active workspace"
                        active: !!(root.settings.features && root.settings.features.rainbowBorder)
                        onToggled: root.mutate("features.rainbowBorder", v)
                    }
                    Toggle {
                        label: "Hyprland mode indicator"
                        active: !!(root.settings.features && root.settings.features.hyprlandMode)
                        onToggled: root.mutate("features.hyprlandMode", v)
                    }
                    Toggle {
                        label: "Network speed monitor"
                        active: !!(root.settings.features && root.settings.features.networkSpeed)
                        onToggled: root.mutate("features.networkSpeed", v)
                    }
                    Toggle {
                        label: "Workspace app icons"
                        active: !!(root.settings.features && root.settings.features.workspaceAppIcons)
                        onToggled: root.mutate("features.workspaceAppIcons", v)
                    }

                    // ---- Module visibility
                    SectionHeader { text: "Modules" }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        rowSpacing: 4
                        columnSpacing: 12
                        Repeater {
                            model: ["workspaces","window","mpris","network","pulseaudio",
                                    "cpu","memory","clock","battery","backlight",
                                    "notifications","tray","networkSpeed","hyprlandMode"]
                            Toggle {
                                label: modelData
                                active: !!(root.settings.modules && root.settings.modules[modelData] !== false)
                                onToggled: root.mutate("modules." + modelData, v)
                            }
                        }
                    }
                }
            }
        }
    }

    // ============ Inline reusable components ===============================

    component SectionHeader: Text {
        Layout.fillWidth: true
        Layout.topMargin: 6
        color: root.cAccent
        font.pixelSize: 15
        font.bold: true
    }

    component Pill: Rectangle {
        property string label: ""
        property bool active: false
        signal activated()
        Layout.preferredHeight: 32
        Layout.fillWidth: true
        radius: 8
        color: ma.containsMouse
            ? Qt.lighter(active ? root.cAccent : root.cAccentOff, 1.15)
            : (active ? root.cAccent : root.cAccentOff)
        Text {
            anchors.centerIn: parent
            text: label
            color: root.cFg
            font.pixelSize: 13
            font.bold: parent.active
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.activated()
        }
    }

    component Toggle: RowLayout {
        property string label: ""
        property bool active: false
        property bool interactive: true
        property bool v: active
        signal toggled()
        Layout.fillWidth: true
        spacing: 10
        Rectangle {
            width: 38; height: 20; radius: 10
            color: parent.active ? root.cAccentOn : root.cAccentOff
            opacity: parent.interactive ? 1.0 : 0.4
            Rectangle {
                width: 16; height: 16; radius: 8
                color: root.cFg
                anchors.verticalCenter: parent.verticalCenter
                x: parent.active ? parent.width - 18 : 2
                Behavior on x { NumberAnimation { duration: 120 } }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                enabled: parent.parent.interactive
                onClicked: {
                    parent.parent.v = !parent.parent.active;
                    parent.parent.toggled();
                }
            }
        }
        Text {
            text: parent.label
            color: parent.interactive ? root.cFg : root.cFgDim
            font.pixelSize: 13
            Layout.fillWidth: true
        }
    }

    component LabeledSlider: ColumnLayout {
        property string label: ""
        property real value: 0
        property real from: 0
        property real to: 1
        property real step: 0.05
        property bool interactive: true
        property real v: value
        signal committed()
        Layout.fillWidth: true
        spacing: 4
        RowLayout {
            Layout.fillWidth: true
            Text { text: parent.parent.label; color: parent.parent.interactive ? root.cFg : root.cFgDim; font.pixelSize: 13; Layout.fillWidth: true }
            Text { text: (parent.parent.v * 100).toFixed(0) + "%"; color: root.cFgDim; font.pixelSize: 12 }
        }
        Rectangle {
            id: track
            Layout.fillWidth: true
            height: 6
            radius: 3
            color: root.cAccentOff
            opacity: parent.interactive ? 1.0 : 0.4
            Rectangle {
                height: parent.height; radius: 3
                color: root.cAccent
                width: parent.width * (parent.parent.v - parent.parent.from) / (parent.parent.to - parent.parent.from)
            }
            Rectangle {
                width: 14; height: 14; radius: 7
                color: root.cFg
                y: -4
                x: track.width * (parent.parent.v - parent.parent.from) / (parent.parent.to - parent.parent.from) - 7
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                enabled: parent.parent.interactive
                preventStealing: true
                function setFromX(mx) {
                    var pct = Math.max(0, Math.min(1, mx / width));
                    var raw = parent.parent.from + pct * (parent.parent.to - parent.parent.from);
                    var snapped = Math.round(raw / parent.parent.step) * parent.parent.step;
                    parent.parent.v = Math.round(snapped * 100) / 100;
                }
                onPressed: setFromX(mouse.x)
                onPositionChanged: if (pressed) setFromX(mouse.x)
                onReleased: parent.parent.committed()
            }
        }
    }
}
