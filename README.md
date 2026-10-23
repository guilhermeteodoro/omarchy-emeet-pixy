# EMEET PIXY for Omarchy

Omarchy Quattro bar widget for the [EMEET PIXY](https://www.emeet.com) webcam,
meant as the only thing besides the daemon you need for it. It drives
[emeet-pixyd](https://github.com/LarsArtmann/emeet-pixyd) through its client
CLI, edits image controls through V4L2 (replacing cameractrls), follows camera
use (replacing a watcher service) and restores a preset when the camera
connects (replacing cameractrlsd and a privacy-on-connect udev hook).

## Requirements

- Omarchy 4 (Quattro) shell
- [emeet-pixyd](https://github.com/LarsArtmann/emeet-pixyd) installed; the
  widget calls its client (`emeet-pixy` or `emeet-pixyd <command>`).
  `~/.nix-profile/bin` and `~/.local/bin` are added to `PATH`, so a Nix profile
  install works without changes.
- `v4l2-ctl` (v4l-utils), `/usr/bin/python3` (helpers in `bin/`), `udevadm`
  (systemd)

## Following camera use

With `followUsage` on (default), every 2 seconds the widget checks whether any
process is *streaming* from the camera (`bin/streaming`: `VIDIOC_REQBUFS`
returns `EBUSY` while another process owns the stream; just holding the device
open, as browsers do, does not count) or any app records audio (PipeWire
capture streams):

- in use for ~4s: `track` plus the current preset's audio mode (`nc` without one);
- idle for `privacyDelaySec` seconds (default 10): `privacy`.

emeet-pixyd's own auto mode is switched off so the two never fight. At startup
the widget runs `sync` and the first poll adopts the camera's real state:
restarting the shell mid-call with the lens open never switches it, and a
camera left in privacy while an app streams gets opened.

**Start in Privacy mode** (`startPrivacy`, on by default): the camera powers up
at its firmware home position with the lens open, so at login and whenever it
is plugged in (`udevadm monitor`) the widget runs `sync`, restores the current
preset's image controls and closes the lens ~10s later unless an app is using
it. Off: the lens is left as the camera came up until a call has come and gone.

The follower runs inside the bar widget, so it stops if the widget is removed
from the bar.

### Keep camera awake during meetings

The camera has its own idle timer: after some seconds without an app
streaming, it closes the lens by itself. In a call where you turn your video
off, that means the lens closes mid-meeting and turning video back on shows
Privacy. **Keep camera awake during meetings** turns that timer off; with it
off, the camera closes the lens after the same delay as below. Implemented in
`bin/privacytimer` (`SET/GET_PRIVACY_TRIGGER_TIME`, `09 02 01 00` / `09 02 01 01`,
u32 LE seconds, recovered from EMEET STUDIO 2.0.4).

**Seconds to Privacy mode after a meeting ends** (`privacyDelaySec`, default
10): how long after the last app stops using the camera and microphone the
follower closes the lens.

## Install

```bash
omarchy plugin add https://github.com/guilhermeteodoro/omarchy-emeet-pixy.git --enable
~/.config/omarchy/plugins/guilhermeteodoro.emeet-pixy/install.sh   # once, asks for sudo
omarchy bar move guilhermeteodoro.emeet-pixy --section right       # optional
```

Omarchy's plugin installer never runs plugin code or sudo, so the one-time
system part lives in `install.sh`:

- installs `udev/70-emeet-pixy.rules`, which lets the logged-in user (only)
  talk to the camera's HID controls (`TAG+="uaccess"`); emeet-pixyd, live
  position and the privacy timer need it. It replaces a hand-written,
  world-writable `/etc/udev/rules.d/99-emeet-pixyd.rules` if present;
- enables `emeet-pixyd.service` for your user.

If that step was skipped, the panel shows "Setup incomplete" with the command
to copy.

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
Three tabs (Position, Image, Privacy settings), switched by click or
Left/Right (h/l), with the preset bar below them on all; the last tab is kept
for the next open. Privacy settings holds Follow camera use, Start in Privacy
mode, Keep camera awake during meetings and the delay after a meeting:

| Tab      | Section    | Controls                                  | Command                                  |
|----------|------------|-------------------------------------------|------------------------------------------|
| Position | Camera     | Track / Static / Privacy                  | `track`, `idle`, `privacy`               |
|          |            | Face / Half body / Full body              | `tracking <variant>`                     |
|          | Audio      | Noise cancel / Live / Original            | `audio nc\|live\|org`                    |
|          | Automation | Gesture control                           | `toggle-gesture`                         |
|          | PTZ        | Pan (±150), tilt (±90), zoom (100–150), Static only | `pan`, `tilt`, `zoom` (sent on release)  |
|          |            | Center, Sync, Web UI                      | `center`, `sync`                         |
| Image    | Image      | Every V4L2 control the camera exposes     | `v4l2-ctl -d <device> -c name=value`     |
|          |            | Reset image to defaults                   | one `v4l2-ctl -c` with all defaults      |

### Static position

Pan, tilt and Center are enabled only in Static: tracking and privacy drive
those motors themselves. Zoom also works while tracking. emeet-pixyd and V4L2 only know the last position
that was *set*, and UVC pan/tilt is a single control, so after tracking a pan
change would send the stale tilt along with it.

`bin/motorpos` reads the real position from the firmware over hidraw
(`CMD_GET_MOTOR_POS`, recovered from EMEET STUDIO 2.0.4; see the comment in the
script for the byte layout):

- **While tracking**, the pan/tilt sliders follow the motors (once a second
  while the panel is open).
- **Tracking → Static** hands the real position to the daemon (`pan`/`tilt`,
  rounded to whole degrees), so sliders, daemon and motors agree before the
  next move.
- **Privacy → Static** (panel, right click or CLI) returns to the last Static
  position (`staticPosition` setting), through `center` because the daemon
  would skip a move to a position it already believes in.

emeet-pixyd's own HID motor frames (`setMotorPos`, `speed`) put the payload
right after the 4-byte head; the firmware expects the HID v2 frame
`[index u8][total length u16 LE][chunk length u8][payload]`, and this app's
command table is shifted by one from the one in upstream's `tools/emhid`
(`…01 01` = GET_MOTOR_POS, `…01 02` = SET_MOTOR_SPEED, motors 1 = pan, 2 = tilt).

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
| `followUsage`        | `true`                  | Follow camera use (Privacy settings tab)  |
| `startPrivacy`       | `true`                  | Close the lens at login and on plug-in    |
| `privacyDelaySec`    | `10`                    | Seconds to Privacy mode after a meeting   |
| `preset`             | `""`                    | Current preset (preset bar)               |

## Keybindings

The widget needs no IPC: bind the CLI directly in `~/.config/hypr/bindings.lua`
and the bar picks the change up on its next poll, for example
`emeet-pixy toggle-privacy`.

## License

MIT
