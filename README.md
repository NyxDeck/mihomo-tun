# Mihomo TUN (DMS)

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) plugin
that controls a local, systemd-managed **mihomo** TUN service: start / stop,
proxy mode, proxy groups and nodes, subscriptions, DIRECT rules, and the exit
IP. It also carries the full install and configuration flow.

Ported from the Noctalia plugin
[mihomo-tun](https://github.com/matsuzaka-yuki/mihomo-tun) (MIT). The Python
helper is reused unchanged; the UI is native to DMS.

## What it does

- Install mihomo and write a TUN-capable `/etc/mihomo/config.yaml`, the
  controller secret, and the plugin's DIRECT rule provider — `install.sh`.
- Start / stop `mihomo.service` from a bar pill (left click opens the panel).
- Switch rule / global / direct mode.
- Browse proxy groups and pick a node.
- Check the effective exit IP.
- Manage subscriptions and DIRECT rules (the helper edits the config through a
  single `pkexec` authorization).

## Requirements

- Linux with systemd, and a running mihomo external controller.
- `python3` and `systemctl` on `PATH`.
- Permission to `systemctl start/stop` the unit (a narrow polkit rule; the
  plugin never runs `sudo`).

## Install

Full install / configuration (writes `/etc/mihomo`, enables the unit):

```sh
sudo ./install.sh
```

Plugin only (until it is in the registry):

```sh
git clone https://github.com/NyxDeck/mihomo-tun.git \
    ~/.config/DankMaterialShell/plugins/mihomo-tun
dms restart
```

Then add the widget to the bar and open its panel. Settings hold the controller
URL, secret file, unit name, and polling interval.

## Layout

```
plugin.json            DMS plugin manifest
MihomoService.qml      daemon: polls status, exposes `dms ipc call mihomoTun ...`
MihomoWidget.qml       bar pill + popout
MihomoPanel.qml        popout panel (mode, groups, nodes, exit IP)
MihomoSettings.qml     settings page
install.sh             full mihomo install / configuration flow
scripts/mihomo-ctl.py  controller backend (one JSON object per call)
scripts/configure-direct-rules.py    root DIRECT rule-provider setup
scripts/apply-subscription-change.py subscription edits
```

The backend is usable on its own:

```sh
python3 scripts/mihomo-ctl.py status
python3 scripts/mihomo-ctl.py toggle
python3 scripts/mihomo-ctl.py group PROXY
python3 scripts/mihomo-ctl.py select PROXY 'node name'
python3 scripts/mihomo-ctl.py mode global
python3 scripts/mihomo-ctl.py ip
```

## Security model

- The controller secret is read from a local file and never stored in the
  plugin settings.
- Starting and stopping the service is a privileged operation; scope
  systemd/polkit narrowly instead of granting broad passwordless access.
- Subscription edits change the root-owned mihomo config; the panel asks
  `pkexec` for a one-time authorization, validates the candidate config, and
  restarts mihomo.

## Credits & license

Ported from [matsuzaka-yuki/mihomo-tun](https://github.com/matsuzaka-yuki/mihomo-tun)
(MIT). MIT licensed; see [LICENSE](LICENSE).
