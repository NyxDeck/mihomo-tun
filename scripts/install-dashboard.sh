#!/usr/bin/env bash
# Install a local Mihomo dashboard and serve it from the controller.
#
# Mihomo only exposes /ui/ when external-ui points at a directory that holds a
# built dashboard, so this script drops metacubexd into /etc/mihomo/ui, adds
# external-ui / external-ui-name to the config, and restarts the unit.
# Idempotent: an installed dashboard is kept unless --force is given.
#
# Needs root. Run it via:
#   sudo ./install-dashboard.sh [--force] [--no-restart] [--url URL]
set -euo pipefail

CONFIG_FILE="${MIHOMO_CONFIG_FILE:-/etc/mihomo/config.yaml}"
UI_DIR="${MIHOMO_UI_DIR:-/etc/mihomo/ui}"
UI_NAME="${MIHOMO_UI_NAME:-metacubexd}"
UNIT="${MIHOMO_UNIT:-mihomo.service}"
UI_URL="${MIHOMO_UI_URL:-https://github.com/MetaCubeX/metacubexd/releases/latest/download/compressed-dist.tgz}"

FORCE=0
NO_RESTART=0
while [ $# -gt 0 ]; do
    case "$1" in
        --force)       FORCE=1 ;;
        --no-restart)  NO_RESTART=1 ;;
        --url)         UI_URL="$2"; shift ;;
        --name)        UI_NAME="$2"; shift ;;
        --config)      CONFIG_FILE="$2"; shift ;;
        --ui-dir)      UI_DIR="$2"; shift ;;
        --unit)        UNIT="$2"; shift ;;
        -h|--help)     sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

# Bilingual output; NYXDECK_LANG overrides the locale.
case "${NYXDECK_LANG:-${LC_ALL:-${LANG:-}}}" in
    zh*) LANG_CODE=zh ;;
    *)   LANG_CODE=en ;;
esac
msg() { if [ "$LANG_CODE" = zh ]; then printf '%s\n' "$1"; else printf '%s\n' "$2"; fi; }
die() { printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }
step() { printf '\n\033[1;36m::\033[0m \033[1m%s\033[0m\n' "$*"; }
ok() { printf '\033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!\033[0m %s\n' "$*"; }

[ "$(id -u)" -eq 0 ] || die "$(msg "需要 root 权限（sudo ./install-dashboard.sh）" \
    "root is required (sudo ./install-dashboard.sh)")"

fetcher=""
for c in curl wget; do
    command -v "$c" >/dev/null 2>&1 && { fetcher="$c"; break; }
done
[ -n "$fetcher" ] || die "$(msg "需要 curl 或 wget" "curl or wget is required")"

# ── 1. dashboard assets ──────────────────────────────────────────────────────
step "$(msg "安装本地控制面板 ($UI_NAME)" "Installing the local dashboard ($UI_NAME)")"
if [ -s "$UI_DIR/index.html" ] && [ "$FORCE" -ne 1 ]; then
    ok "$(msg "已安装: $UI_DIR（--force 可重新下载）" "already installed: $UI_DIR (use --force to re-download)")"
else
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    msg "$(msg "下载 $UI_URL" "Downloading $UI_URL")"
    if [ "$fetcher" = curl ]; then
        curl -fsSL --retry 2 --max-time 180 -o "$tmp/dist.tgz" "$UI_URL" \
            || die "$(msg "下载失败（离线或 GitHub 不可达？可用 MIHOMO_UI_URL 指定镜像）" \
                    "download failed (offline, or GitHub unreachable? set MIHOMO_UI_URL to a mirror)")"
    else
        wget -q -T 180 -O "$tmp/dist.tgz" "$UI_URL" \
            || die "$(msg "下载失败（离线或 GitHub 不可达？可用 MIHOMO_UI_URL 指定镜像）" \
                    "download failed (offline, or GitHub unreachable? set MIHOMO_UI_URL to a mirror)")"
    fi
    mkdir -p "$tmp/x"
    tar -xzf "$tmp/dist.tgz" -C "$tmp/x" \
        || die "$(msg "解压失败" "extraction failed")"
    [ -s "$tmp/x/index.html" ] || die "$(msg "压缩包里没有 index.html，可能是镜像给错了内容" \
        "the archive has no index.html; the mirror probably served something else")"

    rm -rf "$UI_DIR"
    mkdir -p "$UI_DIR"
    cp -a "$tmp/x/." "$UI_DIR/"
    chmod -R a+rX "$UI_DIR"
    ok "$(msg "已安装到 $UI_DIR ($(du -sh "$UI_DIR" | cut -f1))" \
            "installed into $UI_DIR ($(du -sh "$UI_DIR" | cut -f1))")"
fi

# ── 2. external-ui in config.yaml ────────────────────────────────────────────
step "$(msg "在 config.yaml 中启用 external-ui" "Enabling external-ui in config.yaml")"
[ -s "$CONFIG_FILE" ] || die "$(msg "找不到 $CONFIG_FILE，请先运行 mihomo 的 install.sh" \
    "$CONFIG_FILE not found; run the mihomo install.sh first")"

if grep -qE '^[[:space:]]*external-ui[[:space:]]*:' "$CONFIG_FILE"; then
    ok "$(msg "已存在 external-ui，保留不动" "external-ui already present; kept")"
else
    cp -a "$CONFIG_FILE" "$CONFIG_FILE.bak.dashboard.$(date +%Y%m%d_%H%M%S)"
    {
        printf '\n# Added by mihomo-tun (DMS): serve the local dashboard at /ui/\n'
        printf 'external-ui: %s\n' "$UI_DIR"
        printf 'external-ui-name: %s\n' "$UI_NAME"
    } >> "$CONFIG_FILE"
    ok "$(msg "已写入 external-ui: $UI_DIR" "wrote external-ui: $UI_DIR")"
fi

# ── 3. restart + verify ──────────────────────────────────────────────────────
step "$(msg "重启服务并验证" "Restarting the unit and verifying")"
if [ "$NO_RESTART" -eq 1 ]; then
    warn "$(msg "按要求未重启服务（--no-restart）" "unit not restarted (--no-restart)")"
else
    systemctl restart "$UNIT" || die "$(msg "$UNIT 重启失败" "failed to restart $UNIT")"
    ok "$(msg "$UNIT 已重启" "$UNIT restarted")"
    sleep 1
    code=""
    controller="$(grep -oE '^[[:space:]]*external-controller[[:space:]]*:[[:space:]]*.*' "$CONFIG_FILE" \
        | head -1 | cut -d: -f2- | tr -d ' "'"'"'' || true)"
    [ -n "$controller" ] || controller="127.0.0.1:9090"
    case "$controller" in http*) base="$controller" ;; *) base="http://$controller" ;; esac
    if command -v curl >/dev/null 2>&1; then
        code="$(curl -s -o /dev/null -m 5 -w '%{http_code}' "$base/ui/" || true)"
    fi
    if [ "$code" = 200 ]; then
        ok "$(msg "面板可用: $base/ui/" "dashboard ready: $base/ui/")"
    else
        warn "$(msg "面板尚未响应 (HTTP ${code:-?})，稍等片刻或查看 journalctl -u $UNIT" \
                "dashboard not responding yet (HTTP ${code:-?}); check journalctl -u $UNIT")"
    fi
fi

step "$(msg "完成" "Done")"
msg "$(msg "在 DMS 面板里点 Web 面板即可打开 $UI_DIR" \
        "Open it from the DMS panel's Web panel button")"
