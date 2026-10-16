#!/usr/bin/env bash
# Mihomo TUN (DMS) — install the root-owned admin helpers and the polkit action.
#
# Split out of install.sh so it can be re-run on its own: the panel's
# subscription and DIRECT-rule editors shell out to
# /usr/local/libexec/mihomo-tun/<helper> through pkexec, and when that directory
# is missing they can only answer "no admin helper" — the panel looks installed
# but cannot write the config.
#
# Idempotent. Needs root:
#   sudo ./scripts/install-helpers.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER_DIR="/usr/local/libexec/mihomo-tun"
HELPERS=(admin_common.py apply-subscription-change.py configure-direct-rules.py)
POLICY_DIR="/usr/share/polkit-1/actions"
POLICY_FILE="$POLICY_DIR/io.github.nyxdeck.mihomo-tun.policy"

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

[ "$(id -u)" -eq 0 ] || die "$(msg "需要 root 权限（sudo ./scripts/install-helpers.sh）" \
    "root is required (sudo ./scripts/install-helpers.sh)")"

for helper in "${HELPERS[@]}"; do
    [ -f "$REPO_DIR/scripts/$helper" ] || die "$(msg "缺少 $REPO_DIR/scripts/$helper" \
        "missing $REPO_DIR/scripts/$helper")"
done

step "$(msg "安装 root 助手" "Installing the root helpers")"
mkdir -p "$HELPER_DIR"
chown root:root "$HELPER_DIR"
chmod 0755 "$HELPER_DIR"
# root-owned copies: pkexec must not run a script from the user-writable plugin
# directory, which any local process could rewrite.
for helper in "${HELPERS[@]}"; do
    install -o root -g root -m 0755 "$REPO_DIR/scripts/$helper" "$HELPER_DIR/$helper"
done
ok "$(msg "助手已安装到 $HELPER_DIR（root 拥有）" "helpers installed under $HELPER_DIR (root-owned)")"

step "$(msg "注册 polkit 授权" "Registering the polkit action")"
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

step "$(msg "完成" "Done")"
ls -l "$HELPER_DIR" | sed 's/^/  /'
