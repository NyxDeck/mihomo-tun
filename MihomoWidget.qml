import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins

// Bar pill: a status-coloured shield glyph plus, optionally, the selected node.
// Left click opens the popout panel (DMS default for a plugin with popoutContent).
PluginComponent {
    id: root

    layerNamespacePlugin: "mihomotun"

    readonly property string helper: Qt.resolvedUrl("scripts/mihomo-ctl.py").toString().replace("file://", "")
    readonly property string pythonBin: SettingsData.getPluginSetting(pluginId, "python_bin", "python3") || "python3"
    readonly property int refreshMs: SettingsData.getPluginSetting(pluginId, "refresh_ms", 5000) || 5000
    readonly property bool showLabel: SettingsData.getPluginSetting(pluginId, "show_label", true) !== false

    property var snap: ({})

    readonly property bool active: (snap.service ?? "") === "active"
    readonly property string nowName: {
        const s = snap.now ?? "";
        const i = s.lastIndexOf("→");
        return i >= 0 ? s.slice(i + 1).trim() : "";
    }

    function poll() {
        poller.running = false;
        poller.running = true;
    }

    Process {
        id: poller
        command: [root.pythonBin, root.helper, "status"]
        environment: ({
            "MIHOMO_CONTROLLER": SettingsData.getPluginSetting(root.pluginId, "controller", "http://127.0.0.1:9090"),
            "MIHOMO_SECRET_FILE": SettingsData.getPluginSetting(root.pluginId, "secret_file", "/etc/mihomo/.controller-secret"),
            "MIHOMO_UNIT": SettingsData.getPluginSetting(root.pluginId, "unit", "mihomo.service"),
            "MIHOMO_CONFIG_FILE": SettingsData.getPluginSetting(root.pluginId, "config_file", "/etc/mihomo/config.yaml")
        })
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                try {
                    root.snap = JSON.parse(line);
                } catch (e) { /* keep the previous snapshot */ }
            }
        }
    }

    Timer {
        interval: root.refreshMs
        running: true
        repeat: true
        onTriggered: root.poll()
    }

    Component.onCompleted: poll()

    component PillContent: Item {
        implicitWidth: row.implicitWidth + Theme.spacingS * 2
        implicitHeight: root.widgetThickness

        Row {
            id: row
            anchors.centerIn: parent
            spacing: Theme.spacingXS

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "\u{F132}"  // fa-shield
                color: root.active ? Theme.primary : Theme.widgetIconColor
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Theme.fontSizeMedium + 4
            }

            Text {
                visible: root.showLabel && root.nowName.length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: root.nowName
                color: Theme.widgetTextColor
                font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideRight
                width: Math.min(implicitWidth, 110)
            }
        }
    }

    horizontalBarPill: Component {
        PillContent {}
    }

    verticalBarPill: Component {
        PillContent {}
    }

    popoutWidth: 430
    popoutHeight: 580
    popoutContent: Component {
        MihomoPanel {}
    }
}
