# EMEET PIXY for Omarchy

Omarchy Quattro bar widget for the [EMEET PIXY](https://www.emeet.com) webcam,
with direct camera control through the bundled `bin/pixy` helper. It edits
image controls through V4L2, follows camera use and restores image presets
when the camera connects. No daemon, HTTP server or user service is required.

## Requirements

- Omarchy 4 (Quattro) shell
- `v4l2-ctl` (v4l-utils), `/usr/bin/python3` (helpers in `bin/`), `udevadm`
  (systemd), `ffmpeg` (live preview)

## Following camera use

With `followUsage` on (default), every 2 seconds the widget checks whether any
process is *streaming* from the camera (`bin/streaming`: `VIDIOC_REQBUFS`
returns `EBUSY` while another process owns the stream; just holding the device
open, as browsers do, does not count) or any app records audio (PipeWire
capture streams):

- in use for ~4s: the **Meeting starts in** mode (`meetingMode`: `track`, the
  default, or `idle` = Static, which returns to the last Static position) plus
  the current preset's audio mode (`nc` without one);
- idle for `privacyDelaySec` seconds (default 10): `privacy`.

Every status poll reads the hardware directly; the first poll adopts its state:
restarting the shell mid-call with the lens open never switches it, and a
camera left in privacy while an app streams gets opened.

**Start in Privacy mode** (`startPrivacy`, on by default): the camera powers up
at its firmware home position with the lens open, so at login and whenever it
is plugged in (`udevadm monitor`) the widget reads hardware, restores the current
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
  talk to the camera's HID controls (`TAG+="uaccess"`), including native
  control, live position and the privacy timer. It replaces a hand-written,
  world-writable `/etc/udev/rules.d/99-emeet-pixyd.rules` if present.

When upgrading from 0.4, stop and disable the old daemon yourself:
`systemctl --user disable --now emeet-pixyd.service`. Do this only outside a
call, when switching to this version. The installer neither starts nor changes
services. Remove an old `70-emeet-pixy.conf` service drop-in only after retiring
the daemon; uninstalling this plugin does not re-expose its web server.

If that step was skipped, the panel shows "Setup incomplete" with the command
to copy.

Update with `omarchy plugin update guilhermeteodoro.emeet-pixy`.

## Remove

```bash
~/.config/omarchy/plugins/guilhermeteodoro.emeet-pixy/uninstall.sh   # asks for sudo if install.sh ran
```

It removes the udev rule and runs `omarchy plugin remove`. Your presets in
`~/.config/omarchy/emeet-pixy-presets.json` are kept. Any separately installed
emeet-pixyd and its state are untouched.

## Bar button

Left click always opens the panel. Middle and right click are configurable in
the panel (Privacy settings → Bar button) or as `middleClick` / `rightClick`:

| Action           | Effect                                                  |
|------------------|---------------------------------------------------------|
| `static-track`   | Switch Static ↔ Track                                   |
| `toggle-privacy` | Privacy ↔ the mode before it (Static or Track)          |
| `none`           | Nothing                                                 |

Defaults: middle `static-track`, right `toggle-privacy`. The tooltip lists the current
choices.

The icon shows the webcam glyph, crossed out in privacy mode, green in Static
and blue while tracking (like the camera's LED), and dimmed when the camera is
unavailable. The tooltip shows camera and audio modes.

## Panel
Three tabs (Position, Image, Privacy settings), switched by click or
Left/Right (h/l), with the preset bar below them on all; the last tab is kept
for the next open. Privacy settings holds Follow camera use, Meeting starts in,
Start in Privacy mode, Keep camera awake during meetings and the delay after a
meeting:

| Tab      | Section    | Controls                                  | Command                                  |
|----------|------------|-------------------------------------------|------------------------------------------|
| Position | Camera     | Track / Static / Privacy                  | `track`, `idle`, `privacy`               |
|          | Audio      | Noise cancel / Live / Original            | `audio nc\|live\|org`                    |
|          | Automation | Gesture control                           | `toggle-gesture`                         |
|          | PTZ        | Pan (±150), tilt (±90), zoom (100–150), Static only | `pan`, `tilt`, `zoom` (sent on release) |
| Image    | Image      | Every V4L2 control the camera exposes     | `v4l2-ctl -d <device> -c name=value`     |
|          |            | Reset image to defaults                   | one `v4l2-ctl -c` with all defaults      |

The camera icon at the top right of the panel toggles a live 16:9 view for checking
PTZ and image changes. It defaults off and remembers your choice, but streams
only while the panel is open. Close the panel (or hide the preview) before
joining a call: UVC streaming is exclusive. For Follow camera use the preview
counts like a meeting: turning it on in Privacy opens the lens in the Meeting
starts in mode (Track, or Static at the last Static position), and hiding it or
closing the panel goes to Privacy after `privacyDelaySec`, like a meeting
ending. An unavailable or busy camera shows an error instead of blank video.

### Static position

Pan and tilt are enabled only in Static: tracking and privacy drive those
motors themselves. Zoom also works while tracking.

`bin/pixy status` and `bin/motorpos` read real motor positions via
`09 63 01 01` with HID v2 framing
`[index u8][total length u16 LE][chunk length u8][payload]`.
The reply contains motor, target and current position; motors 1 and 2 are pan
and tilt. No motor-speed command is sent.

Native moves use V4L2 extended controls. Pan and tilt are submitted together,
using live HID coordinates for the untouched axis, because UVC shares their
control and otherwise reuses stale tilt after tracking. While tracking, the
sliders follow the motors once a second with the panel open.
Privacy → Static in the panel restores `staticPosition` without a preliminary
center move. A direct CLI `idle` does not read the panel's settings.
Static moves hold the helper lock until the motors reach their target (up to
15 seconds), preventing a status/preset read from saving an in-between position.

### Presets

A preset contains PTZ plus image controls, audio and gesture settings.
Loading does not change camera mode.

- **Current preset**: the one last picked in the preset bar, stored as the
  `preset` setting, so it survives restarts. Picking another loads it and makes
  it current.
- **Auto-save**: every change made in the panel (image controls, reset, audio,
  gestures, pan/tilt/zoom) is saved into the current preset ~2.5s
  later, after the values are read back from the camera. Position is saved only
  when the panel moved the motors, since tracking moves them on its own.
  Changes made outside the panel (CLI) are not saved.
- **New** saves the current setup under a new name and makes it current;
  the trash button deletes the current preset.
- Storage: all fields live in `~/.config/omarchy/emeet-pixy-presets.json`.
  `bin/pixy` is the sole writer, preserving extras while saving PTZ atomically.
  No automatic migration is performed. Existing extras remain, but re-save
  each old preset's position before loading it. Daemon state was found at
  `/run/emeet-pixyd/state.json`, not `~/.local/state/emeet-pixyd/`; it is not
  a durable migration source and is never modified by the helper.
- Loading runs `preset load`, `audio`, `gesture-on|off`, then two `v4l2-ctl -c`
  writes: auto-mode switches first (auto exposure, autofocus, auto white
  balance), then values, because the driver rejects e.g. exposure time while
  auto exposure is on.
- Presets created elsewhere (CLI) start with position only and gain the
  rest on their first auto-save.

The Image tab places standalone controls first, then groups exposure time and
gain under auto exposure, temperature under auto white balance, and focus under
continuous autofocus. Dependent sliders are indented beneath their switch.

The Image section works like [cameractrls](https://github.com/soyersoyer/cameractrls):
it lists the controls the driver reports (`v4l2-ctl --list-ctrls-menus`)
and shows them as sliders, switches or choices. On the PIXY these are brightness,
contrast, saturation, hue, gamma, gain, sharpness, backlight compensation,
power-line frequency, white balance (auto/temperature), auto exposure
(manual/aperture priority), exposure time and focus (auto/absolute). Pan, tilt
and zoom have their own native controls in the Position tab. A control that an
auto mode governs (exposure time under aperture priority, focus under
continuous autofocus) is dimmed until you switch that auto mode off. Every slider has < > buttons that move it one step. Right click
a slider to reset that control. The parser test runs with `node Controls.test.js`.

Editing the plugin: keep the checkout anywhere and symlink it to
`~/.config/omarchy/plugins/guilhermeteodoro.emeet-pixy`. The shell logs
"reloading" on save but keeps the cached `Panel.qml`; run
`omarchy restart shell` to load changes.

Every action triggers a status refresh. The bar polls `status` every
`refreshIntervalSec` seconds, and every 2 seconds while the panel is open.

## Settings

Edit the entry in `~/.config/omarchy/shell.json` or use the bar settings UI:

| Key                  | Default                 | Meaning                                   |
|----------------------|-------------------------|-------------------------------------------|
| `refreshIntervalSec` | `5`                     | Poll interval while the panel is closed   |
| `preview`            | `false`                 | Live preview while the panel is open      |
| `followUsage`        | `true`                  | Follow camera use (Privacy settings tab)  |
| `meetingMode`        | `track`                 | Meeting opens the lens in `track`/`idle`  |
| `startPrivacy`       | `true`                  | Close the lens at login and on plug-in    |
| `privacyDelaySec`    | `10`                    | Seconds to Privacy mode after a meeting   |
| `middleClick`        | `static-track`          | Bar button middle-click action            |
| `rightClick`         | `toggle-privacy`        | Bar button right-click action             |
| `preset`             | `""`                    | Current preset (preset bar)               |

## Keybindings

The widget needs no IPC: bind the bundled helper directly in
`~/.config/hypr/bindings.lua`, for example
`~/.config/omarchy/plugins/guilhermeteodoro.emeet-pixy/bin/pixy privacy`.
The bar picks the change up on its next poll. Available commands:
`status`, `device`, `track`, `idle`, `privacy`, `audio nc|live|org`,
`toggle-gesture`, `gesture-on`, `gesture-off`, `pan N`, `tilt N`, `zoom N`,
`ptz PAN TILT ZOOM` (one combined move), `center`, and
`preset save|load|delete NAME` / `preset list`.

Camera status is hardware state, not the last requested mode. Firmware 2.0.4
reports open-lens standby (raw mode 3) without a stream; this is displayed as
Static. Tracking readback becomes `tracking` with a running video stream.
Pan/tilt status and saved positions use whole degrees; the live motor helper
retains sub-degree precision.

The audio and gesture setters use the EMEET STUDIO 2.0.4 frames: audio
`09 05 00 03` with payload `1/2/3`, gesture `09 04 02 00` with payload
`[2, enabled]`. Hardware tests found that the daemon's legacy setters did not
change these settings. Gesture GET reads payload byte 9, not the padded last
byte, so native status can correctly differ from the daemon's cached status.

## Credits

Protocol knowledge from [emeet-pixyd](https://github.com/LarsArtmann/emeet-pixyd)
(MIT) and EMEET STUDIO reverse engineering. The helper uses Python's standard
library and Linux HID/V4L2 interfaces, not the daemon.

## License

MIT
