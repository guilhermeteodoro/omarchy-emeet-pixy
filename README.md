# EMEET PIXY for Omarchy

Omarchy Quattro bar widget for the [EMEET PIXY](https://www.emeet.com) webcam.
It drives [emeet-pixyd](https://github.com/LarsArtmann/emeet-pixyd) through
its client CLI, so the daemon stays the single owner of the camera.

## Requirements

- Omarchy 4 (Quattro) shell
- `emeet-pixyd` running as a user service; the widget calls its client
  (`emeet-pixy` or `emeet-pixyd <command>`). `~/.nix-profile/bin` and
  `~/.local/bin` are added to `PATH`, so a Nix profile install works without
  changes.

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
Three tabs, switched by click or Left/Right (h/l); the last one is kept for the
next open:

| Tab      | Section    | Controls                                  | Command                                  |
|----------|------------|-------------------------------------------|------------------------------------------|
| Camera   | Camera     | Track / Static / Privacy                  | `track`, `idle`, `privacy`               |
|          |            | Face / Half body / Full body              | `tracking <variant>`                     |
|          | Audio      | Noise cancel / Live / Original            | `audio nc\|live\|org`                    |
|          | Automation | Gesture control, Auto mode switches       | `toggle-gesture`, `toggle-auto`          |
| Position | PTZ        | Pan (±150), tilt (±90), zoom (100–150)    | `pan`, `tilt`, `zoom` (sent on release)  |
|          |            | Center, Sync, Web UI                      | `center`, `sync`                         |
|          | Presets    | Click to load, right click to delete      | `preset load`, `preset delete`           |
|          |            | Name field + Save                         | `preset save <name>`                     |
| Image    | Image      | Every V4L2 control the camera exposes     | `v4l2-ctl -d <device> -c name=value`     |
|          |            | Reset image to defaults                   | one `v4l2-ctl -c` with all defaults      |

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

## Keybindings

The widget needs no IPC: bind the CLI directly in `~/.config/hypr/bindings.lua`
and the bar picks the change up on its next poll, for example
`emeet-pixy toggle-privacy`.

## License

MIT
