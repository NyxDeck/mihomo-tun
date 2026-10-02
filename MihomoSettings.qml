import QtQuick
import qs.Common
import qs.Modules.Plugins

PluginSettings {
    id: root

    pluginId: "mihomoTun"

    StringSetting {
        settingKey: "controller"
        label: I18n.trFor("mihomoTun", "Controller")
        description: I18n.trFor("mihomoTun", "Mihomo external controller URL.")
        defaultValue: "http://127.0.0.1:9090"
    }
    StringSetting {
        settingKey: "secret_file"
        label: I18n.trFor("mihomoTun", "Secret file")
        description: I18n.trFor("mihomoTun", "Local file with the controller secret (never stored here).")
        defaultValue: "/etc/mihomo/.controller-secret"
    }
    StringSetting {
        settingKey: "unit"
        label: I18n.trFor("mihomoTun", "systemd unit")
        description: I18n.trFor("mihomoTun", "Unit controlled by start / stop.")
        defaultValue: "mihomo.service"
    }
    StringSetting {
        settingKey: "config_file"
        label: I18n.trFor("mihomoTun", "Config file")
        description: I18n.trFor("mihomoTun", "Mihomo config.yaml (used by the one-time DIRECT rule setup).")
        defaultValue: "/etc/mihomo/config.yaml"
    }
    StringSetting {
        settingKey: "python_bin"
        label: I18n.trFor("mihomoTun", "Python")
        description: I18n.trFor("mihomoTun", "Interpreter that runs the helper.")
        defaultValue: "python3"
    }
    StringSetting {
        settingKey: "refresh_ms"
        label: I18n.trFor("mihomoTun", "Refresh (ms)")
        description: I18n.trFor("mihomoTun", "Bar polling interval (lightweight); the panel refreshes fully while open.")
        defaultValue: "15000"
    }
    StringSetting {
        settingKey: "max_nodes"
        label: I18n.trFor("mihomoTun", "Max nodes")
        description: I18n.trFor("mihomoTun", "Maximum nodes returned to the panel.")
        defaultValue: "80"
    }
    ToggleSetting {
        settingKey: "show_label"
        label: I18n.trFor("mihomoTun", "Show node label")
        description: I18n.trFor("mihomoTun", "Show the selected node beside the bar glyph.")
        defaultValue: true
    }
}
