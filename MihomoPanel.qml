import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets

// Popout content for the mihomoTun plugin.
//
// Written for people who just want their proxy to work: every section carries a
// plain-language label and, where the concept is not obvious, a one-line hint.
// Overview / Subscriptions / Direct rules mirror the original plugin's pages.
Item {
    id: panel

    readonly property int pad: Theme.spacingM

    implicitWidth: 424
    implicitHeight: mainColumn.implicitHeight + pad * 2

    // injected by PluginPopout
    property var closePopout: null
    property var parentPopout: null

    // ── i18n ─────────────────────────────────────────────────────────────────
    readonly property bool zh: (Qt.locale().name || "").toLowerCase().indexOf("zh") === 0
    readonly property var strings: ({
        title: ["网络代理", "Network proxy"],
        product: ["Mihomo TUN", "Mihomo TUN"],
        running: ["已开启", "On"],
        stopped: ["已关闭", "Off"],
        unknown: ["状态未知", "Unknown"],
        start: ["开启代理", "Turn on"],
        stop: ["关闭代理", "Turn off"],

        navMain: ["总览", "Overview"],
        navSubs: ["订阅", "Subscriptions"],
        navDirect: ["直连规则", "Direct rules"],

        exitIp: ["出口 IP 地址", "Exit IP"],
        exitIpHint: ["你上网时网站看到的地址；开启代理后应该变成节点所在地",
                     "The address websites see. With the proxy on it becomes the node's location."],
        check: ["查询", "Check"],

        mode: ["代理模式", "Proxy mode"],
        mRule: ["规则", "Rule"],
        mGlobal: ["全局", "Global"],
        mDirect: ["直连", "Direct"],
        modeHintRule: ["按规则自动分流：国内直连，其它走代理（推荐）",
                       "Split automatically: domestic sites direct, everything else proxied (recommended)"],
        modeHintGlobal: ["所有流量都走代理", "Everything goes through the proxy"],
        modeHintDirect: ["所有流量都不走代理", "Nothing goes through the proxy"],

        groups: ["节点分组", "Node groups"],
        groupsHint: ["不同类型的网站可以走不同的分组（比如视频站单独一组）",
                     "Different kinds of sites can use different groups (a video-only group, say)"],

        nodes: ["节点（线路）", "Nodes (lines)"],
        nodesHint: ["点一下切换线路；先点「测速」再挑快的",
                    "Tap to switch. Tap Test latency first, then pick a fast one"],
        loading: ["正在读取…", "Loading…"],
        noNodes: ["这个分组里没有可切换的节点", "No switchable nodes in this group"],
        truncated: ["节点太多，只显示前 %1 个", "Only the first %1 nodes are listed"],
        testDelay: ["测速", "Test latency"],
        delayDone: ["已测速 %1 个节点", "Tested %1 nodes"],
        delayBest: ["，最快 %1 毫秒", ", best %1 ms"],

        webPanel: ["网页控制台", "Web console"],
        copySecret: ["复制管理密钥", "Copy secret"],
        updateProvider: ["更新订阅", "Update subscription"],
        webPanelHint: ["没有找到本机控制台；点它会打开在线控制台，并把管理密钥放进剪贴板",
                       "No local console found; tapping opens the hosted one and copies the secret"],
        hostedPanelOpened: ["已打开在线控制台，密钥在剪贴板里，粘贴即可连接",
                            "Hosted console opened; the secret is in your clipboard"],

        subsHint: ["订阅决定你能用哪些节点；更新后会拉到最新节点",
                   "A subscription decides which nodes you get; updating pulls the latest ones"],
        updateAll: ["全部更新", "Update all"],
        addSubscription: ["添加订阅", "Add subscription"],
        noProviders: ["还没有添加订阅，所以没有节点可用",
                      "No subscription yet, so there are no nodes to use"],
        name: ["名称（自己起）", "Name (anything you like)"],
        url: ["订阅链接", "Subscription link"],
        save: ["保存", "Save"],
        cancel: ["取消", "Cancel"],
        edit: ["改名或换链接", "Edit"],
        update: ["更新", "Update"],
        remove: ["移除", "Remove"],
        delete: ["删除", "Delete"],
        confirmDelete: ["再点一次确认", "Tap again to confirm"],
        updatedAt: ["更新于 %1", "Updated %1"],
        neverUpdated: ["还没有更新过", "Never updated"],
        nodeCount: ["%1 个节点", "%1 nodes"],
        quotaUnknown: ["已用流量未知", "Usage unavailable"],
        expires: ["%1 到期", "Expires %1"],

        directRules: ["直连规则", "Direct rules"],
        directHelp: ["这里列的网站不走代理，直接连接。一般放国内网站、银行、局域网地址。",
                     "Sites listed here skip the proxy. Usually domestic sites, banks, LAN addresses."],
        directPlaceholder: ["例如 example.com 或 203.0.113.7/24", "e.g. example.com or 203.0.113.7/24"],
        addDirect: ["添加", "Add"],
        directEmpty: ["还没有添加直连规则", "No direct rules yet"],
        configured: ["直连规则已生效", "Direct rules are active"],
        notConfigured: ["直连规则还没初始化：复制下面的命令，在终端执行一次即可（只需一次）",
                        "Direct rules are not set up yet: copy the command below and run it once in a terminal"],
        copySetup: ["复制命令", "Copy command"],
        clearAll: ["全部清空", "Clear all"],
        copySetupDone: ["命令已复制，终端里粘贴执行一次即可",
                        "Command copied; paste it into a terminal once"],
        reload: ["重新加载", "Reload"],

        copied: ["已复制到剪贴板", "Copied to the clipboard"],
        needFields: ["名称和链接都要填", "Name and link are both required"],
        working: ["处理中…", "Working…"]
    })
    function tr(key, subst) {
        const pair = strings[key];
        let text = pair ? (zh ? pair[0] : pair[1]) : key;
        if (subst !== undefined)
            text = text.replace("%1", subst);
        return text;
    }
    function modeHint() {
        const mode = snap.mode ?? "rule";
        if (mode === "global")
            return tr("modeHintGlobal");
        if (mode === "direct")
            return tr("modeHintDirect");
        return tr("modeHintRule");
    }
    function localeDate(value) {
        if (!value)
            return tr("neverUpdated");
        const date = new Date(value);
        if (isNaN(date.getTime()))
            return tr("neverUpdated");
        return tr("updatedAt", Qt.formatDateTime(date, "yyyy-MM-dd HH:mm"));
    }
    function quotaText(sub) {
        const total = sub.total ?? 0;
        if (!total)
            return tr("quotaUnknown");
        const gib = 1024 * 1024 * 1024;
        const used = (sub.upload ?? 0) + (sub.download ?? 0);
        let text = (used / gib).toFixed(1) + " / " + (total / gib).toFixed(1) + " GiB";
        const expire = sub.expire ?? 0;
        if (expire > 0)
            text += "  ·  " + tr("expires", Qt.formatDate(new Date(expire * 1000), "yyyy-MM-dd"));
        return text;
    }

    // ── backend ──────────────────────────────────────────────────────────────
    readonly property string helper: Qt.resolvedUrl("scripts/mihomo-ctl.py").toString().replace("file://", "")
    readonly property string pythonBin: SettingsData.getPluginSetting("mihomoTun", "python_bin", "python3") || "python3"
    readonly property string controller: SettingsData.getPluginSetting("mihomoTun", "controller", "http://127.0.0.1:9090")
    readonly property var env: ({
        "MIHOMO_CONTROLLER": controller,
        "MIHOMO_SECRET_FILE": SettingsData.getPluginSetting("mihomoTun", "secret_file", "/etc/mihomo/.controller-secret"),
        "MIHOMO_UNIT": SettingsData.getPluginSetting("mihomoTun", "unit", "mihomo.service"),
        "MIHOMO_CONFIG_FILE": SettingsData.getPluginSetting("mihomoTun", "config_file", "/etc/mihomo/config.yaml"),
        "MIHOMO_MAX_NODES": String(SettingsData.getPluginSetting("mihomoTun", "max_nodes", 80))
    })

    property var snap: ({})
    property var providers: []
    property var direct: ({ entries: [] })
    property var delayMap: ({})
    property string selGroup: ""
    property string ipText: ""
    property string toastText: ""
    property bool busy: false
    property int page: 0
    property string pendingDelete: ""
    property string editingName: ""
    property bool uiReady: false
    property bool uiChecked: false
    property bool pendingWebFallback: false

    readonly property bool active: (snap.service ?? "") === "active"
    readonly property var groups: snap.groups ?? []
    readonly property var nodes: snap.nodes ?? []
    readonly property var directEntries: direct.entries ?? []
    readonly property string group: selGroup.length > 0 ? selGroup : (snap.group ?? "")
    readonly property bool directConfigured: direct.configured ?? false

    readonly property var controllerHost: {
        const m = /^https?:\/\/([^/:]+)(?::(\d+))?/.exec(controller);
        return {
            "host": m && m[1] ? m[1] : "127.0.0.1",
            "port": m && m[2] ? m[2] : "9090"
        };
    }

    function run(args) {
        // NB: no stray property writes here. Assigning to a property Process does
        // not define (e.g. `args`) throws and aborts the whole call, which made
        // every action button a no-op.
        actProc.command = [pythonBin, helper].concat(args);
        actProc.environment = env;
        actProc.running = false;
        actProc.running = true;
        busy = true;
        busyGuard.restart();
    }
    function refresh() {
        statusProc.running = false;
        statusProc.running = true;
        providersProc.running = false;
        providersProc.running = true;
        directProc.running = false;
        directProc.running = true;
    }
    function parse(line, apply) {
        try {
            apply(JSON.parse(line));
        } catch (e) {}
    }
    function say(message, isError) {
        toastText = message;
        if (isError)
            ToastService.showError(message);
        else
            ToastService.showInfo(message);
    }
    function shortNode(value) {
        const parts = String(value || "").split("→");
        return parts[parts.length - 1].trim();
    }
    function copyText(value) {
        clipper.text = value;
        clipper.selectAll();
        clipper.copy();
    }
    function probeUi() {
        const xhr = new XMLHttpRequest();
        try {
            xhr.open("GET", controller.replace(/\/+$/, "") + "/ui/");
            xhr.onreadystatechange = () => {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return;
                uiChecked = true;
                uiReady = xhr.status === 200;
            };
            xhr.send();
        } catch (e) {
            uiChecked = true;
            uiReady = false;
        }
    }
    function openWebPanel() {
        if (uiReady) {
            Qt.openUrlExternally(controller.replace(/\/+$/, "") + "/ui/");
            return;
        }
        pendingWebFallback = true;
        run(["secret"]);
    }
    function askDelete(key) {
        if (pendingDelete === key) {
            pendingDelete = "";
            return true;
        }
        pendingDelete = key;
        confirmTimer.restart();
        return false;
    }

    Process {
        id: statusProc
        command: [panel.pythonBin, panel.helper, "status"]
        environment: panel.env
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => panel.parse(line, r => panel.snap = r)
        }
    }
    Process {
        id: providersProc
        command: [panel.pythonBin, panel.helper, "providers"]
        environment: panel.env
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => panel.parse(line, r => panel.providers = r.providers ?? [])
        }
    }
    Process {
        id: directProc
        command: [panel.pythonBin, panel.helper, "direct-list"]
        environment: panel.env
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => panel.parse(line, r => panel.direct = r)
        }
    }
    Process {
        id: actProc
        environment: panel.env
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => panel.parse(line, r => {
                if (r.error) {
                    panel.say(String(r.error), true);
                    return;
                }
                if (r.secret) {
                    panel.copyText(r.secret);
                    if (panel.pendingWebFallback) {
                        panel.pendingWebFallback = false;
                        Qt.openUrlExternally("https://metacubex.github.io/metacubexd/#/setup?hostname=" + panel.controllerHost.host + "&port=" + panel.controllerHost.port);
                        panel.say(panel.tr("hostedPanelOpened"), false);
                    } else {
                        panel.say(panel.tr("copied"), false);
                    }
                    return;
                }
                if (r.results) {
                    const map = {};
                    let best = null;
                    for (const item of r.results) {
                        map[item.name] = item.delay;
                        if (item.delay != null && (best === null || item.delay < best))
                            best = item.delay;
                    }
                    panel.delayMap = map;
                    panel.say(panel.tr("delayDone", r.results.length) + (best != null ? panel.tr("delayBest", best) : ""), false);
                    return;
                }
                if (r.ip) {
                    panel.ipText = r.ip;
                    panel.say(r.ip, false);
                    return;
                }
                if (r.message)
                    panel.say(String(r.message), false);
            })
        }
        onRunningChanged: {
            if (!running) {
                panel.busy = false;
                refreshTimer.restart();
            }
        }
    }
    Timer { id: refreshTimer; interval: 350; repeat: false; onTriggered: panel.refresh() }
    Timer { interval: 10000; running: panel.visible; repeat: true; onTriggered: panel.refresh() }
    Timer {
        id: confirmTimer
        interval: 4000
        repeat: false
        onTriggered: panel.pendingDelete = ""
    }
    Timer {
        id: busyGuard
        interval: 15000
        repeat: false
        onTriggered: panel.busy = false
    }
    Component.onCompleted: {
        refresh();
        probeUi();
    }

    TextEdit {
        id: clipper
        visible: false
        width: 1
        height: 1
    }

    // ── widgets ──────────────────────────────────────────────────────────────
    component Chip: Rectangle {
        id: chip

        property string label: ""
        property string icon: ""
        property bool active: false
        property bool danger: false
        signal tapped

        implicitWidth: chipRow.implicitWidth + Theme.spacingM * 2
        implicitHeight: 28
        radius: 14
        opacity: chip.enabled ? 1 : 0.5

        readonly property color accent: danger ? Theme.error : Theme.primary
        color: {
            if (chipArea.pressed)
                return active ? Theme.primaryHoverLight : Theme.surfacePressed;
            if (chipArea.containsMouse)
                return danger ? Theme.errorHover : active ? Theme.primaryHoverLight : Theme.surfaceHover;
            return active ? Theme.primaryHoverLight : Theme.surfaceLight;
        }

        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: Theme.spacingXS

            DankIcon {
                visible: chip.icon.length > 0
                name: chip.icon
                size: Theme.fontSizeSmall
                color: chip.active ? chip.accent : Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                visible: chip.label.length > 0
                text: chip.label
                font.pixelSize: Theme.fontSizeSmall
                font.weight: chip.active ? Font.Medium : Font.Normal
                color: chip.active ? chip.accent : Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        MouseArea {
            id: chipArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: chip.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: chip.tapped()
        }
    }

    component Card: Rectangle {
        id: card

        default property alias contentData: inner.data

        width: parent ? parent.width : 0
        implicitHeight: inner.implicitHeight + Theme.spacingM * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh
        border.width: Theme.layerOutlineWidth
        border.color: Theme.outlineMedium

        Column {
            id: inner
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingS
        }
    }

    component FieldLabel: StyledText {
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.Medium
        color: Theme.surfaceVariantText
    }

    // One-line explanation under a section label; keeps the panel readable for
    // people who do not know proxy vocabulary yet.
    component Hint: StyledText {
        width: parent ? parent.width : 0
        font.pixelSize: Theme.fontSizeSmall - 1
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    // ── layout ───────────────────────────────────────────────────────────────
    Column {
        id: mainColumn

        x: panel.pad
        y: panel.pad
        width: parent.width - panel.pad * 2
        spacing: Theme.spacingS

        // header
        RowLayout {
            width: parent.width
            height: 32
            spacing: Theme.spacingS

            StyledText {
                text: panel.tr("title")
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Medium
                color: Theme.surfaceText
            }
            StyledText {
                text: panel.tr("product")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                Layout.alignment: Qt.AlignVCenter
            }
            Item {
                Layout.fillWidth: true
            }
            DankIcon {
                visible: panel.busy
                name: "progress_activity"
                size: 16
                color: Theme.surfaceVariantText
                Layout.alignment: Qt.AlignVCenter

                RotationAnimation on rotation {
                    running: panel.busy
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: 900
                }
            }
            StyledText {
                text: panel.active ? panel.tr("running") : (panel.snap.service ? panel.tr("stopped") : panel.tr("unknown"))
                font.pixelSize: Theme.fontSizeSmall
                color: panel.active ? Theme.primary : Theme.surfaceVariantText
                Layout.alignment: Qt.AlignVCenter
            }
            Chip {
                label: panel.active ? panel.tr("stop") : panel.tr("start")
                icon: "power_settings_new"
                active: panel.active
                Layout.alignment: Qt.AlignVCenter
                onTapped: panel.run(["toggle"])
            }
        }

        // navigation
        DankButtonGroup {
            width: parent.width
            maximumWidth: parent.width
            size: "small"
            checkEnabled: false
            minButtonWidth: Math.floor((parent.width - Theme.spacingS - 4) / 3)
            currentIndex: panel.page
            model: [panel.tr("navMain"), panel.tr("navSubs"), panel.tr("navDirect")]
            onSelectionChanged: (index, selected) => {
                if (!selected || index < 0)
                    return;
                panel.page = index;
                if (index === 1 && panel.providers.length === 0)
                    providersProc.running = true;
                if (index === 2)
                    directProc.running = true;
            }
        }

        // ── overview ─────────────────────────────────────────────────────────
        Card {
            visible: panel.page === 0

            Column {
                width: parent.width
                spacing: Theme.spacingS

                RowLayout {
                    width: parent.width
                    spacing: Theme.spacingS

                    FieldLabel {
                        text: panel.tr("exitIp")
                    }
                    StyledText {
                        text: panel.ipText.length > 0 ? panel.ipText : "—"
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceText
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    Chip {
                        label: panel.tr("check")
                        icon: "public"
                        onTapped: panel.run(["ip"])
                    }
                }
                Hint {
                    text: panel.tr("exitIpHint")
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacingS

                FieldLabel {
                    text: panel.tr("mode")
                }
                DankFilterChips {
                    width: parent.width
                    chipHeight: 28
                    model: [
                        {
                            "value": "rule",
                            "label": panel.tr("mRule")
                        },
                        {
                            "value": "global",
                            "label": panel.tr("mGlobal")
                        },
                        {
                            "value": "direct",
                            "label": panel.tr("mDirect")
                        }
                    ]
                    currentIndex: ["rule", "global", "direct"].indexOf(panel.snap.mode ?? "")
                    onSelectionChanged: index => panel.run(["mode", ["rule", "global", "direct"][index]])
                }
                Hint {
                    text: panel.modeHint()
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacingS

                FieldLabel {
                    text: panel.tr("groups")
                }
                DankFilterChips {
                    width: parent.width
                    chipHeight: 28
                    model: panel.groups
                    currentIndex: Math.max(0, panel.groups.indexOf(panel.group))
                    onSelectionChanged: index => {
                        panel.selGroup = panel.groups[index];
                        panel.run(["group", panel.selGroup]);
                    }
                }
                Hint {
                    text: panel.tr("groupsHint")
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacingS

                RowLayout {
                    width: parent.width
                    spacing: Theme.spacingS

                    FieldLabel {
                        text: panel.tr("nodes")
                        Layout.fillWidth: true
                    }
                    StyledText {
                        visible: panel.nodes.length === 0
                        text: panel.snap.ok === undefined ? panel.tr("loading") : panel.tr("noNodes")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                    Chip {
                        visible: panel.nodes.length > 0
                        label: panel.tr("testDelay")
                        icon: "speed"
                        onTapped: panel.run(["delay", panel.group])
                    }
                }

                ListView {
                    id: nodeList

                    width: parent.width
                    height: Math.min(160, Math.max(32, panel.nodes.length * 32))
                    clip: true
                    spacing: 0
                    model: panel.nodes
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        required property var modelData

                        readonly property bool current: panel.shortNode(panel.snap.now ?? "") === panel.shortNode(modelData.name)

                        width: nodeList.width
                        height: 32
                        radius: 8
                        color: current ? Theme.primaryHoverLight : nodeMouse.containsMouse ? Theme.surfaceHover : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingS
                            anchors.rightMargin: Theme.spacingS
                            spacing: Theme.spacingS

                            StyledText {
                                text: modelData.name
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                                font.weight: parent.parent.current ? Font.Medium : Font.Normal
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                            StyledText {
                                readonly property var value: panel.delayMap[modelData.name] ?? modelData.delay
                                visible: value != null
                                text: (value ?? "") + " ms"
                                font.pixelSize: Theme.fontSizeSmall
                                color: (value ?? 9999) < 200 ? Theme.primary : Theme.surfaceVariantText
                            }
                        }
                        MouseArea {
                            id: nodeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panel.run(["select", panel.group, modelData.name])
                        }
                    }
                }

                Hint {
                    text: panel.snap.truncated === true ? panel.tr("truncated", SettingsData.getPluginSetting("mihomoTun", "max_nodes", 80)) : panel.tr("nodesHint")
                }
            }

            RowLayout {
                width: parent.width
                spacing: Theme.spacingS

                Chip {
                    label: panel.tr("updateProvider")
                    icon: "sync"
                    onTapped: panel.run(["provider-update", "all"])
                }
                Chip {
                    label: panel.tr("webPanel")
                    icon: "open_in_new"
                    onTapped: panel.openWebPanel()
                }
                Chip {
                    label: panel.tr("copySecret")
                    icon: "content_copy"
                    onTapped: panel.run(["secret"])
                }
            }

            Hint {
                visible: panel.uiChecked && !panel.uiReady
                text: panel.tr("webPanelHint")
            }
        }

        // ── subscriptions ────────────────────────────────────────────────────
        Card {
            visible: panel.page === 1

            RowLayout {
                width: parent.width
                spacing: Theme.spacingS

                FieldLabel {
                    text: panel.tr("navSubs")
                    Layout.fillWidth: true
                }
                Chip {
                    visible: panel.providers.length > 0
                    label: panel.tr("updateAll")
                    icon: "sync"
                    onTapped: panel.run(["provider-update", "all"])
                }
            }

            Hint {
                text: panel.tr("subsHint")
            }

            StyledText {
                visible: panel.providers.length === 0
                text: panel.tr("noProviders")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }

            Column {
                width: parent.width
                spacing: Theme.spacingS

                Repeater {
                    model: panel.providers

                    Rectangle {
                        id: providerRow

                        required property var modelData

                        readonly property var sub: modelData.subscription ?? ({})

                        width: parent.width
                        implicitHeight: providerColumn.implicitHeight + Theme.spacingS * 2
                        radius: 8
                        color: Theme.surfaceLight

                        Column {
                            id: providerColumn
                            anchors.fill: parent
                            anchors.margins: Theme.spacingS
                            spacing: 2

                            RowLayout {
                                width: parent.width
                                spacing: Theme.spacingS

                                StyledText {
                                    text: providerRow.modelData.name
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Medium
                                    color: Theme.surfaceText
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }
                                Chip {
                                    label: panel.tr("update")
                                    icon: "sync"
                                    onTapped: panel.run(["provider-update", providerRow.modelData.name])
                                }
                                Chip {
                                    label: panel.tr("edit")
                                    icon: "edit"
                                    onTapped: {
                                        panel.editingName = providerRow.modelData.name;
                                        subNameField.text = providerRow.modelData.name;
                                        subUrlField.text = "";
                                        subForm.visible = true;
                                        subUrlField.forceActiveFocus();
                                    }
                                }
                                Chip {
                                    label: panel.pendingDelete === ("del:" + providerRow.modelData.name) ? panel.tr("confirmDelete") : panel.tr("delete")
                                    icon: "delete"
                                    danger: true
                                    onTapped: {
                                        if (panel.askDelete("del:" + providerRow.modelData.name))
                                            panel.run(["subscription-delete", providerRow.modelData.name]);
                                    }
                                }
                            }
                            StyledText {
                                text: panel.tr("nodeCount", providerRow.modelData.node_count ?? 0) + "  ·  " + panel.quotaText(providerRow.sub)
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                elide: Text.ElideRight
                                width: parent.width
                            }
                            StyledText {
                                text: panel.localeDate(providerRow.modelData.updated_at)
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }
                    }
                }
            }

            Column {
                id: subForm
                width: parent.width
                spacing: Theme.spacingS
                visible: false

                FieldLabel {
                    text: panel.editingName.length > 0 ? panel.tr("edit") + " · " + panel.editingName : panel.tr("addSubscription")
                }
                DankTextField {
                    id: subNameField
                    width: parent.width
                    placeholderText: panel.tr("name")
                }
                DankTextField {
                    id: subUrlField
                    width: parent.width
                    placeholderText: panel.tr("url")
                }
                RowLayout {
                    spacing: Theme.spacingS

                    Chip {
                        label: panel.tr("save")
                        icon: "check"
                        active: true
                        onTapped: {
                            if (subNameField.text.length === 0 || subUrlField.text.length === 0) {
                                panel.say(panel.tr("needFields"), true);
                                return;
                            }
                            panel.run(["subscription-upsert", subNameField.text, subUrlField.text, panel.editingName]);
                            subNameField.text = "";
                            subUrlField.text = "";
                            panel.editingName = "";
                            subForm.visible = false;
                        }
                    }
                    Chip {
                        label: panel.tr("cancel")
                        icon: "close"
                        onTapped: {
                            subNameField.text = "";
                            subUrlField.text = "";
                            panel.editingName = "";
                            subForm.visible = false;
                        }
                    }
                }
            }

            Chip {
                visible: !subForm.visible
                label: panel.tr("addSubscription")
                icon: "add"
                onTapped: {
                    panel.editingName = "";
                    subNameField.text = "";
                    subUrlField.text = "";
                    subForm.visible = true;
                    subNameField.forceActiveFocus();
                }
            }
        }

        // ── direct rules ─────────────────────────────────────────────────────
        Card {
            visible: panel.page === 2

            FieldLabel {
                text: panel.tr("directRules")
            }
            Hint {
                text: panel.tr("directHelp")
            }

            RowLayout {
                width: parent.width
                spacing: Theme.spacingS

                DankIcon {
                    name: panel.directConfigured ? "check_circle" : "info"
                    size: 16
                    color: panel.directConfigured ? Theme.primary : Theme.error
                    Layout.alignment: Qt.AlignVCenter
                }
                StyledText {
                    text: panel.directConfigured ? panel.tr("configured") : panel.tr("notConfigured")
                    font.pixelSize: Theme.fontSizeSmall
                    color: panel.directConfigured ? Theme.primary : Theme.error
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
                Chip {
                    visible: !panel.directConfigured
                    label: panel.tr("copySetup")
                    icon: "content_copy"
                    onTapped: {
                        panel.copyText(panel.direct.setup_command ?? "");
                        panel.say(panel.tr("copySetupDone"), false);
                    }
                }
            }

            StyledText {
                visible: panel.directEntries.length === 0
                text: panel.tr("directEmpty")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }

            ListView {
                id: directList

                width: parent.width
                height: Math.min(160, Math.max(1, panel.directEntries.length * 32))
                visible: panel.directEntries.length > 0
                clip: true
                spacing: 0
                model: panel.directEntries
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: directRow

                    required property var modelData

                    width: directList.width
                    height: 32
                    radius: 8
                    color: directHover.hovered ? Theme.surfaceHover : "transparent"

                    HoverHandler {
                        id: directHover
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingS
                        anchors.rightMargin: Theme.spacingS
                        spacing: Theme.spacingS

                        StyledText {
                            text: modelData.value
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        StyledText {
                            text: modelData.kind
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                        Chip {
                            label: panel.pendingDelete === ("rule:" + modelData.id) ? panel.tr("confirmDelete") : panel.tr("remove")
                            icon: "delete"
                            danger: true
                            onTapped: {
                                if (panel.askDelete("rule:" + modelData.id))
                                    panel.run(["direct-remove", String(modelData.id)]);
                            }
                        }
                    }
                }
            }

            DankTextField {
                id: directField
                width: parent.width
                placeholderText: panel.tr("directPlaceholder")
            }
            RowLayout {
                width: parent.width
                spacing: Theme.spacingS

                Chip {
                    label: panel.tr("addDirect")
                    icon: "add"
                    active: true
                    onTapped: {
                        if (directField.text.length === 0)
                            return;
                        panel.run(["direct-add", directField.text]);
                        directField.text = "";
                    }
                }
                Chip {
                    label: panel.tr("reload")
                    icon: "sync"
                    onTapped: panel.run(["direct-sync"])
                }
                Chip {
                    visible: panel.directEntries.length > 0
                    label: panel.pendingDelete === "clear" ? panel.tr("confirmDelete") : panel.tr("clearAll")
                    icon: "delete_sweep"
                    danger: true
                    onTapped: {
                        if (panel.askDelete("clear"))
                            panel.run(["direct-clear"]);
                    }
                }
            }
        }

        // status line
        StyledText {
            width: parent.width
            text: panel.busy ? panel.tr("working") : panel.toastText
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            elide: Text.ElideRight
        }
    }
}
