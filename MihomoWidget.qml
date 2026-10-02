import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

// Bar pill: a status-coloured routing glyph plus, optionally, the selected node.
// Left click opens the popout panel (DMS default for a plugin with popoutContent).
PluginComponent {
    id: root

    layerNamespacePlugin: "mihomotun"

    readonly property bool showLabel: SettingsData.getPluginSetting(pluginId, "show_label", true) !== false

    // Cap the node name so a long one cannot stretch the bar. Expressed in font
    // units (~9 small characters) so it follows the shell font scale instead of
    // a fixed pixel width.
    readonly property real labelMaxWidth: Theme.fontSizeSmall * 9

    // The daemon owns the polling and publishes the snapshot; a bar widget only
    // renders it. Spawning `mihomo-ctl.py status` from here ran once per widget
    // instance on a 5 s timer, on top of the daemon doing exactly the same.
    PluginGlobalVar {
        id: snapshotVar

        varName: "snapshot"
        defaultValue: ({})
    }

    readonly property var snap: snapshotVar.value ?? ({})

    readonly property bool active: (snap.service ?? "") === "active"
    readonly property string nowName: {
        const s = snap.now ?? "";
        const i = s.lastIndexOf("→");
        return i >= 0 ? s.slice(i + 1).trim() : "";
    }

    component PillContent: Item {
        implicitWidth: row.implicitWidth + Theme.spacingS * 2
        implicitHeight: root.widgetThickness

        Row {
            id: row
            anchors.centerIn: parent
            spacing: Theme.spacingXS

            DankIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "swap_horiz"
                size: Theme.iconSize
                color: root.active ? Theme.primary : Theme.widgetIconColor
            }

            StyledText {
                visible: root.showLabel && root.nowName.length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: root.nowName
                color: Theme.widgetTextColor
                font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideRight
                width: Math.min(implicitWidth, root.labelMaxWidth)
            }
        }
    }

    horizontalBarPill: Component {
        PillContent {}
    }

    verticalBarPill: Component {
        PillContent {}
    }

    popoutWidth: 440
    popoutHeight: 620
    popoutContent: Component {
        MihomoPanel {}
    }
}
