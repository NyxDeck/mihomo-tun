import QtQuick
import qs.Common
import qs.Modules.Plugins

PluginSettings {
    id: root

    pluginId: "mihomoTun"

    StringSetting {
        settingKey: "controller"
        label: "Controller"
        description: "Mihomo external controller URL."
        defaultValue: "http://127.0.0.1:9090"
    }
    StringSetting {
        settingKey: "secret_file"
        label: "Secret file"
        description: "Local file with the controller secret (never stored here)."
        defaultValue: "/etc/mihomo/.controller-secret"
    }
    StringSetting {
        settingKey: "unit"
        label: "systemd unit"
        description: "Unit controlled by start / stop."
        defaultValue: "mihomo.service"
    }
    StringSetting {
        settingKey: "config_file"
        label: "Config file"
        description: "Mihomo config.yaml (used by the one-time DIRECT rule setup)."
        defaultValue: "/etc/mihomo/config.yaml"
    }
    StringSetting {
        settingKey: "python_bin"
        label: "Python"
        description: "Interpreter that runs the helper."
        defaultValue: "python3"
    }
    StringSetting {
        settingKey: "refresh_ms"
        label: "Refresh (ms)"
        description: "Status polling interval."
        defaultValue: "5000"
    }
    StringSetting {
        settingKey: "max_nodes"
        label: "Max nodes"
        description: "Maximum nodes returned to the panel."
        defaultValue: "80"
    }
    ToggleSetting {
        settingKey: "show_label"
        label: "Show node label"
        description: "Show the selected node beside the bar glyph."
        defaultValue: true
    }
}
