#!/usr/bin/env python3
"""Install the Mihomo TUN Control direct-rule provider into a Mihomo config.

Run this once with root privileges. The plugin can then update the provider
file and refresh it through the controller API without further privilege.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path


PROVIDER_NAME = "nyxdeck-direct"
# Names earlier releases shipped. A RULE-SET line carries none of the BEGIN/END
# markers the provider block has, so on a config whose block has already been
# rewritten the name is the only thing left to recognise the line by.
LEGACY_PROVIDER_NAMES = ("noctalia-direct",)
START = "# BEGIN Mihomo TUN Control direct exclusions"
END = "# END Mihomo TUN Control direct exclusions"
# Written directly above the managed rule line, which is itself unmarked.
MANAGED_RULE_COMMENT = (
    "# Managed by Mihomo TUN Control; keep this rule before broad CN rules."
)
RULE_PATTERN = re.compile(r"^-\s*RULE-SET,([^,]+),DIRECT$")


def section_end(lines, start):
    index = start + 1
    while index < len(lines):
        line = lines[index]
        if line and not line.startswith((" ", "#")):
            break
        index += 1
    return index


def find_section(lines, name):
    for index, line in enumerate(lines):
        if line == name + ":":
            return index, section_end(lines, index)
    return None


def provider_entry(indent):
    prefix = " " * indent
    return [
        prefix + PROVIDER_NAME + ":",
        prefix + "  type: file",
        prefix + "  behavior: classical",
        prefix + "  format: yaml",
        prefix + "  path: " + repr(args.rules_path),
    ]


def remove_managed_provider(lines):
    first = next((index for index, line in enumerate(lines) if line == START), None)
    if first is None:
        return lines
    last = next((index for index in range(first, len(lines)) if lines[index] == END), None)
    if last is None:
        raise SystemExit("发现不完整的受管配置块：" + START)
    # 块尾那个空行也一起删：install_provider() 每次都会把自己的空行写回来，不删的
    # 话每跑一次配置就多一个空行，render_config() 永远不收敛，main() 里那句
    # 「已配置，无需修改」也就永远走不到 —— 每次都要写文件、备份、重启 mihomo。
    end = last + 1
    if end < len(lines) and lines[end] == "":
        end += 1
    return lines[:first] + lines[end:]


def install_provider(text):
    lines = remove_managed_provider(text.splitlines())
    section = find_section(lines, "rule-providers")
    if section is None:
        proxy_groups = find_section(lines, "proxy-groups")
        if proxy_groups is None:
            raise SystemExit("找不到顶层 proxy-groups，无法确定 rule-providers 插入位置")
        block = [START, "rule-providers:"] + provider_entry(2) + [END, ""]
        lines[proxy_groups[0]:proxy_groups[0]] = block
    else:
        start, end = section
        for index in range(start + 1, end):
            if lines[index].strip() == PROVIDER_NAME + ":":
                raise SystemExit(
                    "配置里已有未受管的 %s，请先手动移除或改名后再运行" % PROVIDER_NAME
                )
        block = [START] + provider_entry(2) + [END, ""]
        lines[end:end] = block
    return "\n".join(lines) + "\n"


def rules_indent(lines, start):
    """缩进样式以现有的 rules 列表项为准。

    工具生成的配置（如 yaml.safe_dump）序列号在行首（0 缩进），手写的配置
    通常是 2 空格。受管的 RULE-SET 行必须用相同缩进，否则整份 YAML 解析失败。
    """
    for line in lines[start + 1:]:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped.startswith("-"):
            return line[:len(line) - len(line.lstrip())]
        break
    return "  "


def managed_provider_names(lines):
    """本插件可能写进这份配置的每一个 provider 名字。

    只认当前名字是不够的：那条 RULE-SET 规则行自己没有标记，认它只能靠它带的
    名字，而改名之前写下的配置带的是旧名字 —— 旧名字既可能还留在受管块里，
    也可能随块一起被换掉、只剩规则行还在。
    """
    names = {PROVIDER_NAME, *LEGACY_PROVIDER_NAMES}
    first = next((index for index, line in enumerate(lines) if line == START), None)
    if first is None:
        return names
    last = next((index for index in range(first, len(lines)) if lines[index] == END), None)
    if last is None:
        return names
    for line in lines[first + 1:last]:
        # 块里只有 provider 名字是「有缩进、无值」的行；type/behavior/path 都带值。
        match = re.match(r"^\s+([^\s:#]+):\s*$", line)
        if match:
            names.add(match.group(1))
    return names


def install_rule(text, names):
    lines = text.splitlines()
    rules = find_section(lines, "rules")
    if rules is None:
        raise SystemExit("找不到顶层 rules")
    start, end = rules
    indent = rules_indent(lines, start)
    rule_line = indent + "- RULE-SET,%s,DIRECT" % PROVIDER_NAME

    # 按「名字属于本插件」来找，而不是只比对当前名字：旧名字认不出来的话，那条
    # 规则会被当成别人的行留在原地，而它引用的 rule-set 已经随受管块一起被删了，
    # mihomo 于是拒绝整份配置（rule set ... not found），用户看到的却是回滚。
    keep, duplicates = None, []
    for index in range(start + 1, end):
        match = RULE_PATTERN.match(lines[index].strip())
        if match is None:
            continue
        marked = index - 1 > start and lines[index - 1].strip() == MANAGED_RULE_COMMENT
        if match.group(1) not in names and not marked:
            continue
        if keep is None:
            keep = index
        else:
            duplicates.append(index)

    if keep is None:
        lines[start + 1:start + 1] = [
            indent + MANAGED_RULE_COMMENT,
            rule_line,
        ]
        return "\n".join(lines) + "\n"

    # 已经有一条就待在它该在的位置上（这条规则必须排在宽泛的 CN 规则之前），
    # 就地改名即可；再插一条会和它并存，而多出来的那条正是校验失败的原因。
    drop = set()
    for index in reversed(duplicates):
        drop.add(index)
        if index - 1 > keep and lines[index - 1].strip() == MANAGED_RULE_COMMENT:
            drop.add(index - 1)
    if drop:
        lines = [line for position, line in enumerate(lines) if position not in drop]
    lines[keep] = rule_line
    if keep > 0 and lines[keep - 1].strip() != MANAGED_RULE_COMMENT:
        lines.insert(keep, indent + MANAGED_RULE_COMMENT)
    return "\n".join(lines) + "\n"


def render_config(text):
    # 名字要在块被重写之前读出来：install_provider() 会把块整段换掉。
    names = managed_provider_names(text.splitlines())
    return install_rule(install_provider(text), names)


def validate(config_path, mihomo_bin):
    completed = subprocess.run(
        [mihomo_bin, "-t", "-d", str(config_path.parent)],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout or "").strip()
        raise RuntimeError(detail[-4000:] or "mihomo config validation failed")


def prepare_rules_path(config_path):
    rules_path = Path(args.rules_path).expanduser().resolve()
    try:
        rules_path.relative_to(config_path.parent.resolve())
    except ValueError as exc:
        raise SystemExit(
            "规则文件必须位于 %s 目录下，满足 Mihomo SAFE_PATHS" % config_path.parent
        ) from exc

    rules_path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    if not rules_path.exists():
        rules_path.write_text(
            "# Generated by Mihomo TUN Control. Do not edit by hand.\npayload: []\n",
            encoding="utf-8",
        )

    uid = int(os.environ.get("SUDO_UID") or os.geteuid())
    gid = int(os.environ.get("SUDO_GID") or os.getegid())
    os.chown(rules_path.parent, uid, gid)
    os.chmod(rules_path.parent, 0o700)
    os.chown(rules_path, uid, gid)
    os.chmod(rules_path, 0o600)
    args.rules_path = str(rules_path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="/etc/mihomo/config.yaml")
    parser.add_argument("--rules-path", required=True)
    parser.add_argument("--mihomo-bin", default="/usr/bin/mihomo")
    parser.add_argument("--service")
    parser.add_argument("--no-restart", action="store_true")
    global args
    args = parser.parse_args()

    config_path = Path(args.config)
    if os.geteuid() != 0:
        raise SystemExit("请用 root 运行，例如 sudo python3 configure-direct-rules.py ...")
    if not config_path.is_file():
        raise SystemExit("找不到配置文件：%s" % config_path)
    if not Path(args.mihomo_bin).is_file():
        raise SystemExit("找不到 mihomo：%s" % args.mihomo_bin)
    prepare_rules_path(config_path)

    original = config_path.read_text(encoding="utf-8")
    updated = render_config(original)
    if updated == original:
        print("direct-rule provider 已配置，无需修改")
        return

    backup = config_path.with_name(
        config_path.name + ".bak.nyxdeck-direct." + time.strftime("%Y%m%d_%H%M%S")
    )
    shutil.copy2(config_path, backup)
    mode = config_path.stat().st_mode & 0o777

    try:
        config_path.write_text(updated, encoding="utf-8")
        os.chmod(config_path, mode)
        validate(config_path, args.mihomo_bin)
    except Exception:
        shutil.copy2(backup, config_path)
        os.chmod(config_path, mode)
        raise

    if args.service and not args.no_restart:
        subprocess.run(["systemctl", "restart", args.service], check=True)

    print("已配置 %s" % PROVIDER_NAME)
    print("规则文件：%s" % args.rules_path)
    print("配置备份：%s" % backup)


if __name__ == "__main__":
    main()
