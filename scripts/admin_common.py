#!/usr/bin/env python3
"""Shared helpers for the root-privileged Mihomo helpers.

apply-subscription-change.py and configure-direct-rules.py are installed under
/usr/local/libexec/mihomo-tun (root-owned) and launched through pkexec or sudo.
Because the caller is unprivileged, they must not trust a path handed to them:
mihomo is resolved to a root-owned, non-writable executable.
"""

import os
import shutil
import stat

# Usual locations: a distro package manager uses /usr/bin, an upstream release
# tarball /usr/local/bin.
TRUSTED_CANDIDATES = ("/usr/bin/mihomo", "/usr/local/bin/mihomo", "/bin/mihomo")


def trusted_executable(path):
    """True when path is a regular file root owns and others cannot write."""
    if not path:
        return False
    try:
        info = os.stat(path)
    except OSError:
        return False
    if not stat.S_ISREG(info.st_mode):
        return False
    if info.st_uid != 0:
        return False
    if info.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
        return False
    return bool(info.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH))


def resolve_mihomo_bin(explicit=None):
    """Path to a root-owned mihomo, or SystemExit.

    A caller-supplied --mihomo-bin / MIHOMO_BIN / PATH hit is accepted only if
    it passes trusted_executable, so an unprivileged caller cannot make root
    run an arbitrary binary; otherwise the standard root locations are tried.
    """
    for candidate in (explicit, os.environ.get("MIHOMO_BIN"), shutil.which("mihomo")):
        if trusted_executable(candidate):
            return candidate
    for candidate in TRUSTED_CANDIDATES:
        if trusted_executable(candidate):
            return candidate
    raise SystemExit(
        "找不到可信的 mihomo（需 root 拥有且组/其他不可写）：%s" % (explicit or "mihomo")
    )
