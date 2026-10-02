#!/usr/bin/env bash
# Mihomo TUN (DMS) — full install and configuration flow.
#
# Writes a TUN-capable /etc/mihomo/config.yaml and
# the controller secret, registers the plugin's DIRECT rule provider, drops a
# local dashboard into /etc/mihomo/ui, and enables the systemd unit.
# Idempotent: an existing config is never replaced unless --force is given.
#
# Needs root (writes /etc/mihomo and manages the unit). Run it via:
#   sudo ./install.sh [--yes] [--force] [--no-start] [--no-dashboard]
# or, from the plugin, it is invoked through pkexec.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="/etc/mihomo"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
SECRET_FILE="$CONFIG_DIR/.controller-secret"
RULES_DIR="$CONFIG_DIR/direct-rules"
RULES_FILE="$RULES_DIR/direct-rules.yaml"
UNIT="mihomo.service"
CONTROLLER="127.0.0.1:9090"

FORCE=0
ASSUME_YES=0
NO_START=0
NO_DASHBOARD=0
for arg in "$@"; do
    case "$arg" in
        --force)        FORCE=1 ;;
        --yes|-y)       ASSUME_YES=1 ;;
        --no-start)     NO_START=1 ;;
        --no-dashboard) NO_DASHBOARD=1 ;;
        -h|--help)
            sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

# Bilingual output; NYXDECK_LANG overrides the locale.
case "${NYXDECK_LANG:-${LC_ALL:-${LANG:-}}}" in
    zh*) LANG_CODE=zh ;;
    *)   LANG_CODE=en ;;
esac
msg() { # msg "<中文>" "<English>"
    if [ "$LANG_CODE" = zh ]; then printf '%s\n' "$1"; else printf '%s\n' "$2"; fi
}
die() { printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }
step() { printf '\n\033[1;36m::\033[0m \033[1m%s\033[0m\n' "$*"; }
ok() { printf '\033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!\033[0m %s\n' "$*"; }

[ "$(id -u)" -eq 0 ] || die "$(msg "需要 root 权限（sudo ./install.sh）" "root is required (sudo ./install.sh)")"

# ── 1. mihomo binary ─────────────────────────────────────────────────────────
step "$(msg "检查 mihomo" "Checking mihomo")"
if command -v mihomo >/dev/null 2>&1; then
    ok "$(msg "已安装: $(command -v mihomo)" "installed: $(command -v mihomo)")"
else
    # The installer never installs packages: running an AUR helper as root is
    # rejected by makepkg, and pkg managers are distro specific. Install mihomo
    # yourself, then re-run. This keeps the script distro-agnostic.
    die "$(msg "PATH 里没有 mihomo；请先用发行版的包管理器安装，再重新运行 install.sh（Arch: paru -S mihomo-bin，或上游 releases）" \
            "mihomo is not on PATH; install it with your distro's package manager first (Arch: paru -S mihomo-bin, or the upstream releases), then re-run install.sh")"
fi

# ── 2. directory + secret ────────────────────────────────────────────────────
step "$(msg "准备配置与密钥" "Preparing config and secret")"
mkdir -p "$CONFIG_DIR" "$RULES_DIR"
chmod 755 "$CONFIG_DIR"

if [ -s "$SECRET_FILE" ]; then
    ok "$(msg "沿用现有密钥" "keeping the existing secret")"
else
    umask 077
    python3 - <<'PY' > "$SECRET_FILE"
import secrets
print(secrets.token_urlsafe(24))
PY
    ok "$(msg "已生成控制器密钥" "generated the controller secret")"
fi

# The plugin reads the secret as the invoking user, and /etc/mihomo is root
# only, so the file has to be readable by that user: without this every
# controller call fails right after a fresh install. Grant it through an ACL on
# that one user rather than their primary group — on distros where the primary
# group is shared (e.g. `users`) a group readable file exposes the secret, and
# with it control of the proxy, to every other local account. Applied to an
# existing secret too, so re-running the installer repairs an old one.
secret_owner_uid="${SUDO_UID:-}${PKEXEC_UID:-}"
secret_user=""
if [ -n "$secret_owner_uid" ]; then
    secret_user="$(id -un "$secret_owner_uid" 2>/dev/null || true)"
fi
chmod 600 "$SECRET_FILE"
if [ -n "$secret_user" ] && command -v setfacl >/dev/null 2>&1 \
        && setfacl -m "u:$secret_user:r" "$SECRET_FILE" 2>/dev/null; then
    ok "$(msg "密钥仅 root 与 $secret_user 可读（ACL）" \
            "secret readable by root and $secret_user only (ACL)")"
elif [ -n "$secret_user" ]; then
    # No ACL support: fall back to the primary group, and say why that is worse.
    secret_group="$(id -gn "$secret_user" 2>/dev/null || true)"
    if [ -n "$secret_group" ] && chown "root:$secret_group" "$SECRET_FILE" 2>/dev/null; then
        chmod 640 "$SECRET_FILE"
        warn "$(msg "没有 setfacl，改用组 $secret_group；若该组不止你一人，控制器密钥会对其余成员可见，请改用专用组" \
                "setfacl unavailable; using group $secret_group — if that group has other members they can read the controller secret; use a dedicated group")"
    else
        warn "$(msg "无法授权给用户，控制器调用会失败；请执行：sudo setfacl -m u:$secret_user:r $SECRET_FILE" \
                "could not grant access; run: sudo setfacl -m u:$secret_user:r $SECRET_FILE")"
    fi
else
    warn "$(msg "无法判断你的用户，请自行授权：sudo setfacl -m u:<user>:r $SECRET_FILE" \
            "could not determine your user; run: sudo setfacl -m u:<user>:r $SECRET_FILE")"
fi
SECRET="$(cat "$SECRET_FILE")"

# ── 3. root helpers + polkit action ──────────────────────────────────────────
step "$(msg "安装 root 助手" "Installing the root helpers")"
HELPER_DIR="/usr/local/libexec/mihomo-tun"
mkdir -p "$HELPER_DIR"
chown root:root "$HELPER_DIR"
chmod 0755 "$HELPER_DIR"
# root-owned copies: pkexec must not run a script from the user-writable plugin
# directory, which any local process could rewrite.
for helper in admin_common.py apply-subscription-change.py configure-direct-rules.py; do
    install -o root -g root -m 0755 "$REPO_DIR/scripts/$helper" "$HELPER_DIR/$helper"
done
ok "$(msg "助手已安装到 $HELPER_DIR（root 拥有）" "helpers installed under $HELPER_DIR (root-owned)")"

POLICY_DIR="/usr/share/polkit-1/actions"
POLICY_FILE="$POLICY_DIR/io.github.nyxdeck.mihomo-tun.policy"
if [ -d "$POLICY_DIR" ]; then
    cat > "$POLICY_FILE" <<POLICY
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE policyconfig PUBLIC "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
<policyconfig>
  <vendor>NyxDeck</vendor>
  <action id="io.github.nyxdeck.mihomo-tun.apply-subscription">
    <description>Edit the Mihomo configuration</description>
    <message>Authentication is required to change Mihomo subscriptions</message>
    <defaults>
      <allow_any>no</allow_any>
      <allow_inactive>no</allow_inactive>
      <allow_active>auth_admin_keep</allow_active>
    </defaults>
    <annotate key="org.freedesktop.policykit.exec.path">$HELPER_DIR/apply-subscription-change.py</annotate>
  </action>
</policyconfig>
POLICY
    chmod 0644 "$POLICY_FILE"
    ok "$(msg "polkit 授权已安装" "polkit action installed")"
else
    warn "$(msg "未找到 $POLICY_DIR，跳过 polkit 授权（pkexec 仍会提示，文案为默认）" \
            "$POLICY_DIR not found; skipping the polkit action (pkexec still prompts, with the default text)")"
fi

# ── 4. config.yaml ───────────────────────────────────────────────────────────
step "$(msg "写入 config.yaml" "Writing config.yaml")"
if [ -s "$CONFIG_FILE" ] && [ "$FORCE" -ne 1 ]; then
    warn "$(msg "已存在 $CONFIG_FILE，保留不动（--force 可覆盖）" \
            "$CONFIG_FILE exists; kept (use --force to replace)")"
else
    [ -s "$CONFIG_FILE" ] && cp -a "$CONFIG_FILE" "$CONFIG_FILE.bak.$(date +%Y%m%d_%H%M%S)"
    cat > "$CONFIG_FILE" <<YAML
# Mihomo TUN (DMS) — base configuration
# Add subscriptions from the panel; it edits proxy-providers and proxy-groups.
mixed-port: 7890
allow-lan: false
bind-address: 127.0.0.1
mode: rule
log-level: info
ipv6: true
external-controller: $CONTROLLER
secret: "$SECRET"

tun:
  enable: true
  stack: mixed
  auto-route: true
  auto-redirect: true
  auto-detect-interface: true
  dns-hijack:
    - any:53

dns:
  enable: true
  ipv6: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  nameserver:
    - https://223.5.5.5/dns-query
    - https://1.1.1.1/dns-query

proxy-providers: {}

proxies: []

proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - DIRECT

rules:
  - MATCH,PROXY
YAML
    chmod 600 "$CONFIG_FILE"
    ok "$(msg "已写入基础配置（TUN + 控制器 + fake-ip DNS）" \
            "wrote the base config (TUN + controller + fake-ip DNS)")"
fi

# ── 5. DIRECT rule provider ──────────────────────────────────────────────────
step "$(msg "注册 DIRECT 规则 provider" "Registering the DIRECT rule provider")"
set +e
python3 "$HELPER_DIR/configure-direct-rules.py" \
    --config "$CONFIG_FILE" \
    --rules-path "$RULES_FILE" \
    --service "$UNIT" 2>&1 | sed 's/^/  /'
rc=${PIPESTATUS[0]}
set -e
if [ "$rc" -eq 0 ]; then
    chown -R "${SUDO_USER:-$USER}" "$RULES_DIR" 2>/dev/null || true
    ok "$(msg "DIRECT provider 就绪" "DIRECT provider ready")"
else
    warn "$(msg "provider 设置失败（可稍后在面板里重试）" \
            "provider setup failed (retry later from the panel)")"
fi

# ── 6. local dashboard ───────────────────────────────────────────────────────
if [ "$NO_DASHBOARD" -eq 1 ]; then
    warn "$(msg "按要求跳过本地控制面板（--no-dashboard）" \
            "skipping the local dashboard (--no-dashboard)")"
else
    step "$(msg "安装本地控制面板" "Installing the local dashboard")"
    set +e
    MIHOMO_CONFIG_FILE="$CONFIG_FILE" MIHOMO_UNIT="$UNIT" \
        bash "$REPO_DIR/scripts/install-dashboard.sh" --no-restart 2>&1 | sed 's/^/  /'
    rc=${PIPESTATUS[0]}
    set -e
    if [ "$rc" -eq 0 ]; then
        ok "$(msg "面板就绪，服务启动后可访问 /ui/" \
                "dashboard ready; /ui/ comes up with the service")"
    else
        warn "$(msg "面板安装失败（稍后可单独重试 install-dashboard.sh）" \
                "dashboard install failed (retry scripts/install-dashboard.sh later)")"
    fi
fi

# ── 7. service ───────────────────────────────────────────────────────────────
step "$(msg "启用 systemd 服务" "Enabling the systemd unit")"
systemctl enable "$UNIT" >/dev/null 2>&1 || true
if [ "$NO_START" -eq 1 ]; then
    warn "$(msg "按要求未启动服务" "service not started (--no-start)")"
else
    systemctl restart "$UNIT" || die "$(msg "$UNIT 启动失败" "failed to start $UNIT")"
    ok "$(msg "$UNIT 已启动" "$UNIT started")"
fi

step "$(msg "完成" "Done")"
ok "$(msg "配置: $CONFIG_FILE" "config: $CONFIG_FILE")"
ok "$(msg "密钥: $SECRET_FILE" "secret: $SECRET_FILE")"
msg "$(msg "下一步：在面板里添加订阅，然后选择节点。" \
        "Next: add a subscription in the panel, then pick a node.")"
