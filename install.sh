#!/usr/bin/env bash
# One-time system setup for the EMEET PIXY plugin. Run as your user after
# `omarchy plugin add ...`; it asks for sudo only for the udev rule.
#
# Lets the logged-in user talk to the camera's HID node (udev `uaccess`).
# Replaces the old world-writable rule if present. No daemon is installed.
set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
rule=/etc/udev/rules.d/70-emeet-pixy.rules
legacy=/etc/udev/rules.d/99-emeet-pixyd.rules

sudo install -m644 "$here/udev/70-emeet-pixy.rules" "$rule"
[[ -e $legacy ]] && sudo rm -f "$legacy" && echo "removed $legacy"
sudo udevadm control --reload
sudo udevadm trigger --subsystem-match=hidraw --action=change
echo "installed $rule"

