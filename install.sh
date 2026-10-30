#!/usr/bin/env bash
# One-time system setup for the EMEET PIXY plugin. Run as your user after
# `omarchy plugin add ...`; it asks for sudo only for the udev rule.
#
# 1. Lets the logged-in user talk to the camera's HID node (udev `uaccess`),
#    which emeet-pixyd and the plugin need. Replaces a hand-written
#    world-writable 99-emeet-pixyd.rules if one exists.
# 2. Enables emeet-pixyd as a user service if its unit is installed, in its
#    own network namespace: its web UI on 127.0.0.1:8090 has no
#    authentication, so any local account could drive the camera through it.
#    The plugin uses the daemon's owner-only Unix socket instead.
set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
rule=/etc/udev/rules.d/70-emeet-pixy.rules
legacy=/etc/udev/rules.d/99-emeet-pixyd.rules

sudo install -m644 "$here/udev/70-emeet-pixy.rules" "$rule"
[[ -e $legacy ]] && sudo rm -f "$legacy" && echo "removed $legacy"
sudo udevadm control --reload
sudo udevadm trigger --subsystem-match=hidraw --action=change
echo "installed $rule"

dropin=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/emeet-pixyd.service.d/70-emeet-pixy.conf
if systemctl --user cat emeet-pixyd.service >/dev/null 2>&1; then
  mkdir -p "$(dirname "$dropin")"
  printf '[Service]\n# Isolates the unauthenticated web UI (installed by emeet-pixy install.sh)\nPrivateNetwork=yes\n' >"$dropin"
  systemctl --user daemon-reload
  systemctl --user enable emeet-pixyd.service
  systemctl --user restart emeet-pixyd.service
  echo "emeet-pixyd enabled, web UI isolated ($dropin)"
else
  echo "emeet-pixyd.service not found: install emeet-pixyd (https://github.com/LarsArtmann/emeet-pixyd)" >&2
fi
