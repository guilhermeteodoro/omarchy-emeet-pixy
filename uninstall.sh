#!/usr/bin/env bash
# Undoes install.sh and removes the plugin. Keeps your presets.
set -euo pipefail

rule=/etc/udev/rules.d/70-emeet-pixy.rules
if [[ -e $rule ]]; then
  sudo rm -f "$rule"
  sudo udevadm control --reload
  echo "removed $rule"
fi

# Last: this deletes the directory this script lives in.
omarchy plugin remove guilhermeteodoro.emeet-pixy --yes
echo "kept ~/.config/omarchy/emeet-pixy-presets.json (delete it if you no longer need it)"
