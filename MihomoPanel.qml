import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Popout content. Self-contained: it polls the controller through
// scripts/mihomo-ctl.py and runs the actions itself.
Item {
    id: panel

    implicitWidth: 430
    implicitHeight: 560

    readonly property string helper: Qt.resolvedUrl("scripts/mihomo-ctl.py").toString().replace("file://", "")
    readonly property string pythonBin: SettingsData.getPluginSetting("mihomoTun", "python_bin", "python3")
    readonly property var env: ({
        "MIHOMO_CONTROLLER": SettingsData.getPluginSetting("mihomoTun", "controller", "http://127.0.0.1:9090"),
        "MIHOMO_SECRET_FILE": SettingsData.getPluginSetting("mihomoTun", "secret_file", "/etc/mihomo/.controller-secret"),
        "MIHOMO_UNIT": SettingsData.getPluginSetting("mihomoTun", "unit", "mihomo.service"),
        "MIHOMO_CONFIG_FILE": SettingsData.getPluginSetting("mihomoTun", "config_file", "/etc/mihomo/config.yaml"),
        "MIHOMO_MAX_NODES": String(SettingsData.getPluginSetting("mihomoTun", "max_nodes", 80))
    })

    property var snap: ({})
    property string selGroup: ""
    property string ipText: ""

    readonly property bool active: (snap.service ?? "") === "active"
    readonly property string stateText: active ? "active" : (snap.service ?? "unknown")
    readonly property var groups: snap.groups ?? []
    readonly property var nodes: snap.nodes ?? []
    readonly property string group: selGroup.length > 0 ? selGroup : (snap.group ?? "")

    function run(args) {
        actProc.command = [pythonBin, helper].concat(args);
        actProc.environment = env;
        actProc.running = false;
        actProc.running = true;
    }
    function refresh() {
        pollProc.running = false;
        pollProc.running = true;
    }

    Process {
        id: pollProc
        command: [panel.pythonBin, panel.helper, "status"]
        environment: panel.env
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => { try { panel.snap = JSON.parse(line); } catch (e) {} }
        }
    }
    Process {
        id: actProc
        environment: panel.env
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                try {
                    const r = JSON.parse(line);
                    if (r && r.ok && r.ip) panel.ipText = r.ip;
                    if (r && r.ok) panel.snap = r;
                } catch (e) {}
            }
        }
        onRunningChanged: if (!running) waitTimer.restart()
    }
    Timer { id: waitTimer; interval: 500; repeat: false; onTriggered: panel.refresh() }
    Timer { interval: 8000; running: panel.visible; repeat: true; onTriggered: panel.refresh() }
    Component.onCompleted: refresh()

    // ── small widgets ────────────────────────────────────────────────────────
    component Tile: Rectangle {
        property string label: ""
        property bool on: false
        signal tapped()
        radius: 10
        color: on ? Theme.primary : "transparent"
        border.color: on ? "transparent" : Theme.outlineButton
        border.width: 1
        implicitHeight: 34
        implicitWidth: labelText.implicitWidth + Theme.spacingM * 2
        Text {
            id: labelText
            anchors.centerIn: parent
            text: parent.label
            color: parent.on ? Theme.primaryText ?? Theme.widgetTextColor : Theme.widgetTextColor
            font.pixelSize: Theme.fontSizeSmall
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: parent.tapped() }
    }

    Column {
        anchors.fill: parent
        anchors.margins: Theme.spacingM
        spacing: Theme.spacingS

        // Header
        Row {
            width: parent.width
            spacing: Theme.spacingS

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Mihomo TUN"
                color: Theme.widgetTextColor
                font.pixelSize: Theme.fontSizeSmall + 4
                font.weight: Font.Bold
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: panel.stateText
                color: panel.active ? Theme.primary : Theme.error
                font.pixelSize: Theme.fontSizeSmall
            }
            Item { width: parent.width - parent.childrenRect.width; height: 1 }
            Tile {
                label: panel.active ? "Stop" : "Start"
                on: panel.active
                onTapped: panel.run(["toggle"])
            }
        }

        // Mode
        Row {
            spacing: Theme.spacingS
            Repeater {
                model: ["rule", "global", "direct"]
                Tile {
                    required property string modelData
                    label: modelData
                    on: panel.snap.mode === modelData
                    onTapped: panel.run(["mode", modelData])
                }
            }
        }

        // Groups
        ListView {
            id: groupList
            width: parent.width
            height: 34
            orientation: ListView.Horizontal
            spacing: Theme.spacingS
            clip: true
            model: panel.groups
            delegate: Tile {
                required property string modelData
                label: modelData
                on: panel.group === modelData
                onTapped: {
                    panel.selGroup = modelData;
                    panel.run(["group", modelData]);
                }
            }
        }

        // Nodes
        ListView {
            id: nodeList
            width: parent.width
            height: panel.height - y - 78
            clip: true
            model: panel.nodes
            spacing: 2
            delegate: Rectangle {
                required property var modelData
                width: nodeList.width
                height: 30
                radius: 8
                color: (panel.snap.now ?? "").endsWith(modelData.name) ? Theme.primary : "transparent"
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingS
                    anchors.rightMargin: Theme.spacingS
                    spacing: Theme.spacingS
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - delayText.width - Theme.spacingS
                        text: modelData.name
                        color: Theme.widgetTextColor
                        font.pixelSize: Theme.fontSizeSmall
                        elide: Text.ElideRight
                    }
                    Text {
                        id: delayText
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.delay != null ? modelData.delay + " ms" : ""
                        color: Theme.widgetIconColor
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.run(["select", panel.group, modelData.name])
                }
            }
        }

        // Exit IP
        Row {
            width: parent.width
            spacing: Theme.spacingS
            Tile { label: "Exit IP"; onTapped: panel.run(["ip"]) }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: panel.ipText
                color: Theme.widgetTextColor
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }
}
