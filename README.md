# EMEET PIXY for Omarchy

Omarchy Quattro bar widget for the [EMEET PIXY](https://www.emeet.com) webcam,
meant as the only thing besides the daemon you need for it. It drives
[emeet-pixyd](https://github.com/LarsArtmann/emeet-pixyd) through its client
CLI, edits image controls through V4L2 (replacing cameractrls), follows camera
use (replacing a watcher service) and restores a preset when the camera
connects (replacing cameractrlsd and a privacy-on-connect udev hook).

## Requirements

- Omarchy 4 (Quattro) shell
- `emeet-pixyd` enabled as a user service (`systemctl --user enable --now
  emeet-pixyd`); the widget calls its client (`emeet-pixy` or
  `emeet-pixyd <command>`). `~/.nix-profile/bin` and `~/.local/bin` are added
  to `PATH`, so a Nix profile install works without changes.
- `v4l2-ctl` (v4l-utils), `/usr/bin/python3` (streaming probe), `udevadm` (systemd)

## Following camera use

With `followUsage` on (default), every 2 seconds the widget checks whether any
process is *streaming* from the camera (`bin/streaming`: `VIDIOC_REQBUFS`
returns `EBUSY` while another process owns the stream; just holding the device
open, as browsers do, does not count) or any app records audio (PipeWire
capture streams):

- in use for ~4s: `track` plus the current preset's audio mode (`nc` without one);
- idle for ~10s: `privacy`.

emeet-pixyd's own auto mode is switched off so the two never fight. At startup
the widget runs `sync` and the first poll adopts the camera's real state:
restarting the shell mid-call with the lens open never switches it, an idle
start still closes the lens, and a camera left in privacy while an app streams
gets opened.

When the camera connects (`udevadm monitor`, plus once at startup when it is
idle), the widget runs `sync`, restores the image controls of the current
preset, and lets the follower re-apply track or privacy, since the camera comes
back at its firmware home position with the lens open.

The follower runs inside the bar widget, so it stops if the widget is removed
from the bar.

## Install

```bash
omarchy plugin add https://github.com/guilhermeteodoro/omarchy-emeet-pixy.git --enable
omarchy bar move guilhermeteodoro.emeet-pixy --section right   # optional
```

Update with `omarchy plugin update guilhermeteodoro.emeet-pixy`.

## Bar button

| Input        | Action                                |
|--------------|---------------------------------------|
| Left click   | Open the panel                        |
| Right click  | `toggle-privacy`                      |
| Middle click | Open the daemon web UI                |

The icon shows the webcam glyph, crossed out in privacy mode, in the urgent
color while tracking, and dimmed when the daemon is unreachable. The tooltip
shows the mode, audio mode and call state.

## Panel
Two tabs (Position, Image), switched by click or Left/Right (h/l), with the
preset bar below them on both; the last tab is kept for the next open:

| Tab      | Section    | Controls                                  | Command                                  |
|----------|------------|-------------------------------------------|------------------------------------------|
| Position | Camera     | Track / Static / Privacy                  | `track`, `idle`, `privacy`               |
|          |            | Face / Half body / Full body              | `tracking <variant>`                     |
|          | Audio      | Noise cancel / Live / Original            | `audio nc\|live\|org`                    |
|          | Automation | Gesture control, Follow camera use        | `toggle-gesture`, `followUsage` setting  |
|          | PTZ        | Pan (±150), tilt (±90), zoom (100–150), Static only | `pan`, `tilt`, `zoom` (sent on release)  |
|          |            | Center, Sync, Web UI                      | `center`, `sync`                         |
| Image    | Image      | Every V4L2 control the camera exposes     | `v4l2-ctl -d <device> -c name=value`     |
|          |            | Reset image to defaults                   | one `v4l2-ctl -c` with all defaults      |

### Static position

Pan, tilt, zoom and Center are enabled only in Static: tracking and privacy
drive the motors themselves, and nothing can read where they leave them.
emeet-pixyd and V4L2 keep reporting the last position that was *set*; on the
PIXY (4K, `328f:00c0`) the firmware's `CMD_GET_MOTOR_POS` (`09 63 01 02`) and
`CMD_SET_MOTOR_PRESET_POS` answer with the same fixed reply
(`… 00 02 00 02 00 40`) whatever the position, so live polling is not possible.

- **Tracking → Static** stops where tracking left the camera. The panel shows
  each axis as "—" until it is set again (slider, Center, preset load).
- **Privacy → Static** (panel, right click or CLI) returns to the last fully
  known Static position (`staticPosition` setting), through `center` because
  the daemon would skip a move to a position it already believes in.

### Presets

A preset is the daemon's PTZ preset extended with the rest of the setup: every
active image control, the audio mode and gesture control. Camera mode and auto
mode are left alone, so loading a preset never opens the privacy shutter.

- **Current preset**: the one last picked in the preset bar, stored as the
  `preset` setting, so it survives restarts. Picking another loads it and makes
  it current.
- **Auto-save**: every change made in the panel (image controls, reset, audio,
  gestures, pan/tilt/zoom, Center) is saved into the current preset ~2.5s
  later, after the values are read back from the camera. Position is saved only
  when the panel moved the motors, since tracking moves them on its own.
  Changes made outside the panel (CLI, web UI) are not saved.
- **New** saves the current setup under a new name and makes it current;
  the trash button deletes the current preset.
- Storage: `preset save/load/delete` in emeet-pixyd for position, the rest in
  `~/.config/omarchy/emeet-pixy-presets.json`.
- Loading runs `preset load`, `audio`, `gesture-on|off`, then two `v4l2-ctl -c`
  writes: auto-mode switches first (auto exposure, autofocus, auto white
  balance), then values, because the driver rejects e.g. exposure time while
  auto exposure is on.
- Presets created elsewhere (web UI, CLI) start with position only and gain the
  rest on their first auto-save.

The Image section works like [cameractrls](https://github.com/soyersoyer/cameractrls):
it lists the controls the driver reports (`v4l2-ctl --list-ctrls-menus`)
and shows them as sliders, switches or choices. On the PIXY these are brightness,
contrast, saturation, hue, gamma, gain, sharpness, backlight compensation,
power-line frequency, white balance (auto/temperature), auto exposure
(manual/aperture priority), exposure time and focus (auto/absolute). Pan, tilt
and zoom are left out because emeet-pixyd owns the motors. A control that an
auto mode governs (exposure time under aperture priority, focus under
continuous autofocus) is dimmed until you switch that auto mode off. Right click
a slider to reset that control. The parser test runs with `node Controls.test.js`.

Editing the plugin: keep the checkout anywhere and symlink it to
`~/.config/omarchy/plugins/guilhermeteodoro.emeet-pixy`. The shell logs
"reloading" on save but keeps the cached `Panel.qml`; run
`omarchy restart shell` to load changes.

The daemon does not report the tracking variant, so those buttons never show
as selected. Every action triggers a status refresh. The bar polls `status`
every `refreshIntervalSec` seconds, and every 2 seconds while the panel is open.

## Settings

Edit the entry in `~/.config/omarchy/shell.json` or use the bar settings UI:

| Key                  | Default                 | Meaning                                   |
|----------------------|-------------------------|-------------------------------------------|
| `command`            | `emeet-pixy`            | Client binary name or absolute path       |
| `refreshIntervalSec` | `5`                     | Poll interval while the panel is closed   |
| `webUrl`             | `http://127.0.0.1:8090` | Daemon web UI (`EMEET_PIXYD_WEB_ADDR`)    |
| `followUsage`        | `true`                  | Follow camera use (panel: Position tab)   |
| `preset`             | `""`                    | Current preset (preset bar)               |

## Keybindings

The widget needs no IPC: bind the CLI directly in `~/.config/hypr/bindings.lua`
and the bar picks the change up on its next poll, for example
`emeet-pixy toggle-privacy`.

## License

MIT
