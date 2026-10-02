import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

// Daemon: polls the mihomo controller through scripts/mihomo-ctl.py, publishes
// the snapshot for the bar widgets to render, and exposes IPC actions. One
// poller for the shell, however many widgets are on screen.
//
// The periodic poll is the lightweight `watch` subcommand (service + selected
// node only). The full `status` snapshot — groups, nodes, mode, version — runs
// on demand for IPC; the panel fetches it itself while it is open.
PluginComponent {
    id: daemon

    property var snapshot: ({})

    PluginGlobalVar {
        id: snapshotVar

        varName: "snapshot"
        defaultValue: ({})
    }

    function publish(value) {
        snapshot = value;
        snapshotVar.set(value);
    }

    readonly property string pid: (pluginId && pluginId.length > 0) ? pluginId : "mihomoTun"
    readonly property string helper: Qt.resolvedUrl("scripts/mihomo-ctl.py").toString().replace("file://", "")

    function setting(key, fallback) {
        const v = SettingsData.getPluginSetting(pid, key, fallback);
        return (v === undefined || v === null || v === "") ? fallback : v;
    }

    readonly property string pythonBin: setting("python_bin", "python3")
    readonly property int refreshMs: setting("refresh_ms", 15000)
    readonly property string controller: setting("controller", "http://127.0.0.1:9090")
    readonly property string secretFile: setting("secret_file", "/etc/mihomo/.controller-secret")
    readonly property string unit: setting("unit", "mihomo.service")
    readonly property string configFile: setting("config_file", "/etc/mihomo/config.yaml")

    property var env: ({
        "MIHOMO_CONTROLLER": controller,
        "MIHOMO_SECRET_FILE": secretFile,
        "MIHOMO_UNIT": unit,
        "MIHOMO_CONFIG_FILE": configFile
    })

    readonly property string service: snapshot.service ?? "unknown"
    readonly property bool active: service === "active"
    readonly property string mode: snapshot.mode ?? "rule"
    readonly property string current: snapshot.now ?? ""
    readonly property bool reachable: snapshot.ok === true

    function refresh() {
        watchProc.running = false;
        watchProc.running = true;
    }

    function refreshFull() {
        statusProc.running = false;
        statusProc.running = true;
    }

    function action(args) {
        actionProc.command = [pythonBin, helper].concat(args);
        actionProc.environment = env;
        actionProc.running = false;
        actionProc.running = true;
        actionProc._refresh = true;
    }

    // Lightweight: service state and the selected node only, for the bar pill.
    Process {
        id: watchProc
        command: [daemon.pythonBin, daemon.helper, "watch"]
        environment: daemon.env
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                try {
                    daemon.publish(JSON.parse(line));
                } catch (e) {
                    daemon.publish({ ok: false, error: "bad json" });
                }
            }
        }
    }

    // Full snapshot (groups, nodes, mode, version). On demand for IPC; the panel
    // runs its own `status` while it is open.
    Process {
        id: statusProc
        command: [daemon.pythonBin, daemon.helper, "status"]
        environment: daemon.env
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                try {
                    daemon.publish(JSON.parse(line));
                } catch (e) {
                    daemon.publish({ ok: false, error: "bad json" });
                }
            }
        }
    }

    // Actions must not publish their own (partial) JSON into the shared
    // snapshot: it lacks service/now, so the bar pill would blank out until the
    // next poll. A watch refresh after the action republishes instead.
    Process {
        id: actionProc
        property bool _refresh: false
        environment: daemon.env
        onRunningChanged: {
            if (!running && _refresh) {
                _refresh = false;
                refreshTimer.restart();
            }
        }
    }

    Timer {
        interval: daemon.refreshMs
        running: true
        repeat: true
        onTriggered: daemon.refresh()
    }

    Timer {
        id: refreshTimer
        interval: 400
        repeat: false
        onTriggered: daemon.refresh()
    }

    Component.onCompleted: refresh()

    // dms ipc call mihomoTun <function> [args...]
    IpcHandler {
        target: "mihomoTun"

        function toggle(): string {
            daemon.action(["toggle"]);
            return daemon.active ? "stopping" : "starting";
        }
        function status(): string {
            daemon.refreshFull();
            return JSON.stringify(daemon.snapshot);
        }
        function mode(m: string): string {
            daemon.action(["mode", m]);
            return "mode " + m;
        }
        function select(group: string, node: string): string {
            daemon.action(["select", group, node]);
            return group + " -> " + node;
        }
        function ip(): string {
            daemon.action(["ip"]);
            return "checking";
        }
    }
}
