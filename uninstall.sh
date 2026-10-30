#!/usr/bin/env bash
# Undoes install.sh and removes the plugin. Keeps your preset extras
# (~/.config/omarchy/emeet-pixy-presets.json) and emeet-pixyd itself.
set -euo pipefail

rule=/etc/udev/rules.d/70-emeet-pixy.rules
if [[ -e $rule ]]; then
  sudo rm -f "$rule"
  sudo udevadm control --reload
  echo "removed $rule"
fi

dropin=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/emeet-pixyd.service.d/70-emeet-pixy.conf
if [[ -e $dropin ]]; then
  rm -f "$dropin"
  rmdir --ignore-fail-on-non-empty "$(dirname "$dropin")"
  systemctl --user daemon-reload
  systemctl --user try-restart emeet-pixyd.service
  echo "removed $dropin (emeet-pixyd web UI reachable again on 127.0.0.1:8090)"
fi

# Last: this deletes the directory this script lives in.
omarchy plugin remove guilhermeteodoro.emeet-pixy --yes
echo "kept ~/.config/omarchy/emeet-pixy-presets.json (delete it if you no longer need it)"
