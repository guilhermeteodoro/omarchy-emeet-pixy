import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Controls.js" as Controls

// Bar button + popup for the EMEET PIXY. Camera actions are emeet-pixyd client
// calls; image controls (brightness, exposure, …) go straight to V4L2 with
// v4l2-ctl, like cameractrls does. The panel only renders what they report.
Panel {
  id: root
  moduleName: "guilhermeteodoro.emeet-pixy"

  readonly property string command: String(setting("command", "emeet-pixy"))
  readonly property int refreshIntervalSec: Math.max(1, Number(setting("refreshIntervalSec", 5)))
  readonly property string webUrl: String(setting("webUrl", "http://127.0.0.1:8090"))

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Parsed `status`: camera, audio, gesture, pan, tilt, zoom, in_call, auto, device.
  property var status: ({})
  property var presets: []
  // Everything a preset holds beyond the daemon's pan/tilt/zoom, keyed by
  // preset name: { image: {control: value}, audio, gesture }.
  property var presetExtras: ({})
  readonly property string presetsPath: Quickshell.env("HOME") + "/.config/omarchy/emeet-pixy-presets.json"
  // Panel tab; kept while the shell runs so reopening lands where you left.
  property string tab: "camera"
  readonly property var tabs: ["camera", "position", "image", "presets"]
  // Parsed `v4l2-ctl --list-ctrls-menus`, see Controls.js.
  property var controls: []
  readonly property string device: status.device || ""
  readonly property bool online: status.camera !== undefined
  readonly property string camera: status.camera || ""
  readonly property bool inCall: status.in_call === "yes"

  function cameraIcon() {
    return camera === "privacy" || !online ? "\u{F1737}" : "\u{F05A0}"
  }

  function summary() {
    if (!online) return "emeet-pixyd unreachable"
    return camera + " · audio " + status.audio + (inCall ? " · in call" : "")
  }

  // Runs `<command> args...`. The shell's PATH usually lacks the Nix profile
  // where emeet-pixyd is installed, so it is appended here.
  function argv(args) {
    return ["sh", "-c", 'PATH="$PATH:$HOME/.nix-profile/bin:$HOME/.local/bin"; exec "$0" "$@"', command].concat(args)
  }

  function savePresetExtras(next) {
    presetExtras = next
    presetsFile.setText(JSON.stringify({ version: 1, presets: next }, null, 2) + "\n")
  }

  function savePreset(name) {
    run(["preset", "save", name])
    var next = Object.assign({}, presetExtras)
    next[name] = { image: Controls.snapshot(controls), audio: status.audio || "", gesture: status.gesture === "true" }
    savePresetExtras(next)
  }

  function deletePreset(name) {
    run(["preset", "delete", name])
    var next = Object.assign({}, presetExtras)
    delete next[name]
    savePresetExtras(next)
  }

  // One sequential script so the image writes land after the daemon has
  // settled; values travel as positional args, never interpolated.
  function loadPreset(name) {
    var extra = presetExtras[name] || {}
    var image = Controls.applyArgs(extra.image, controls)
    var gesture = extra.gesture === undefined ? "" : (extra.gesture ? "gesture-on" : "gesture-off")
    Quickshell.execDetached(["sh", "-c",
      'PATH="$PATH:$HOME/.nix-profile/bin:$HOME/.local/bin"\n' +
      '"$0" preset load "$1"\n' +
      '[ -n "$2" ] && "$0" audio "$2"\n' +
      '[ -n "$3" ] && "$0" "$3"\n' +
      '[ -n "$5" ] && v4l2-ctl -d "$4" -c "$5"\n' +
      '[ -n "$6" ] && v4l2-ctl -d "$4" -c "$6"\n' +
      'exit 0',
      command, name, extra.audio || "", gesture, device, image.modes, image.values])
    refreshSoon.restart()
    controlsSoon.restart()
  }

  function presetSummary(name) {
    var extra = presetExtras[name]
    if (!extra) return "Position only (saved outside this panel)"
    return "Position · " + Object.keys(extra.image || {}).length + " image controls · audio " + (extra.audio || "?") + " · gestures " + (extra.gesture ? "on" : "off")
  }

  function run(args) {
    Quickshell.execDetached(argv(args))
    refreshSoon.restart()
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function parseStatus(text) {
    var next = {}
    String(text).trim().split(/\s+/).forEach(function(pair) {
      var eq = pair.indexOf("=")
      if (eq > 0) next[pair.slice(0, eq)] = pair.slice(eq + 1)
    })
    status = next
  }

  function parsePresets(text) {
    var names = []
    String(text).split("\n").forEach(function(line) {
      var m = line.match(/^\s+(\S+):/)
      if (m) names.push(m[1])
    })
    presets = names
  }

  function refreshControls() {
    if (device !== "" && !controlsProc.running) controlsProc.running = true
  }

  // Optimistic: the row shows the new value at once; the re-read 400ms later
  // picks up driver clamping and controls that became (in)active.
  function setControl(name, value) {
    controls = controls.map(function(c) {
      return c.name === name ? Object.assign({}, c, { value: value }) : c
    })
    writeControls(name + "=" + value)
  }

  function writeControls(arg) {
    if (device === "" || arg === "") return
    Quickshell.execDetached(["v4l2-ctl", "-d", device, "-c", arg])
    controlsSoon.restart()
  }

  onOpenedChanged: if (opened) { refresh(); presetsProc.running = true; refreshControls() }
  onDeviceChanged: if (opened) refreshControls()
  onCommandChanged: refresh()
  Component.onCompleted: refresh()

  Process {
    id: statusProc
    command: root.argv(["status"])
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.parseStatus(text) }
  }

  Process {
    id: presetsProc
    command: root.argv(["preset", "list"])
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.parsePresets(text) }
  }

  Process {
    id: controlsProc
    command: ["v4l2-ctl", "-d", root.device, "--list-ctrls-menus"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.controls = Controls.parse(text) }
  }

  // The panel already shows writes optimistically; this re-read only catches
  // clamping and (in)active flips, so it can wait for a preset script to finish.
  Timer { id: controlsSoon; interval: 1500; onTriggered: root.refreshControls() }

  FileView {
    id: presetsFile
    path: root.presetsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try { root.presetExtras = JSON.parse(text()).presets || {} } catch (e) { root.presetExtras = {} }
    }
    onFileChanged: reload()
  }

  Timer { interval: root.opened ? 2000 : root.refreshIntervalSec * 1000; running: true; repeat: true; onTriggered: root.refresh() }
  Timer { id: refreshSoon; interval: 700; onTriggered: { root.refresh(); if (root.opened) presetsProc.running = true } }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.cameraIcon()
    active: root.camera === "tracking"
    dimmed: !root.online
    tooltipText: "EMEET PIXY: " + root.summary()
    onPressed: function(b) {
      if (b === Qt.RightButton) root.run(["toggle-privacy"])
      else if (b === Qt.MiddleButton) Quickshell.execDetached(["omarchy-launch-browser", root.webUrl])
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: presetName.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dx === 0 || presetName.activeFocus) return
        var i = (root.tabs.indexOf(root.tab) + dx + root.tabs.length) % root.tabs.length
        root.tab = root.tabs[i]
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: column
        width: flick.width
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: "EMEET PIXY"
          meta: root.summary()
          detail: root.status.device || ""
          foreground: root.fg
          fontFamily: root.fontFamily
          iconOpacity: root.online ? 1.0 : 0.5
          iconComponent: Component {
            Text {
              textFormat: Text.PlainText
              text: root.cameraIcon()
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        Choice {
          width: parent.width
          value: root.tab
          options: [
            { value: "camera", label: "Camera", icon: "\u{F0100}" },
            { value: "position", label: "Position", icon: "\u{F01A4}" },
            { value: "image", label: "Image", icon: "\u{F02F1}" },
            { value: "presets", label: "Presets", icon: "\u{F00C0}" }
          ]
          onChanged: function(v) { root.tab = v }
        }

        Section {
          title: "CAMERA"
          visible: root.tab === "camera"
          Choice {
            value: root.camera
            options: [
              { value: "tracking", label: "Track", icon: "\u{F0C7B}" },
              // emeet-pixyd calls this `idle`: lens open, motors hold position.
              { value: "idle", label: "Static", icon: "\u{F0403}" },
              { value: "privacy", label: "Privacy", icon: "\u{F0209}" }
            ]
            // The CLI verb for tracking mode is `track`.
            onChanged: function(v) { root.run([v === "tracking" ? "track" : v]) }
          }
          Choice {
            value: ""
            options: [
              { value: "face", label: "Face" },
              { value: "halfbody", label: "Half body" },
              { value: "fullbody", label: "Full body" }
            ]
            onChanged: function(v) { root.run(["tracking", v]) }
          }
        }

        Section {
          title: "AUDIO"
          visible: root.tab === "camera"
          Choice {
            value: root.status.audio || ""
            options: [
              { value: "nc", label: "Noise cancel" },
              { value: "live", label: "Live" },
              { value: "org", label: "Original" }
            ]
            onChanged: function(v) { root.run(["audio", v]) }
          }
        }

        Section {
          title: "AUTOMATION"
          visible: root.tab === "camera"
          Toggle {
            width: parent.width
            label: "Gesture control"
            checked: root.status.gesture === "true"
            foreground: root.fg
            fontFamily: root.fontFamily
            onClicked: root.run(["toggle-gesture"])
          }
          Toggle {
            width: parent.width
            label: "Auto mode"
            description: "Track on call start, privacy on call end (" + (root.status.auto || "?") + ")"
            checked: root.online && root.status.auto !== "off"
            foreground: root.fg
            fontFamily: root.fontFamily
            onClicked: root.run(["toggle-auto"])
          }
        }

        Section {
          title: "PAN · TILT · ZOOM"
          visible: root.tab === "position"
          SliderRow { text: "pan"; minimum: -150; maximum: 150; current: Number(root.status.pan || 0); onCommitted: function(v) { root.run(["pan", String(v)]) } }
          SliderRow { text: "tilt"; minimum: -90; maximum: 90; current: Number(root.status.tilt || 0); onCommitted: function(v) { root.run(["tilt", String(v)]) } }
          SliderRow { text: "zoom"; minimum: 100; maximum: 150; current: Number(root.status.zoom || 0); onCommitted: function(v) { root.run(["zoom", String(v)]) } }
          Row {
            spacing: Style.space(6)
            Action { iconText: "\u{F01A4}"; text: "Center"; onClicked: root.run(["center"]) }
            Action { iconText: "\u{F0450}"; text: "Sync"; onClicked: root.run(["sync"]) }
            Action { iconText: "\u{F059F}"; text: "Web UI"; onClicked: { Quickshell.execDetached(["omarchy-launch-browser", root.webUrl]); root.close() } }
          }
        }

        Section {
          title: "PRESETS"
          visible: root.tab === "presets"
          Flow {
            width: parent.width
            spacing: Style.space(6)
            Repeater {
              model: root.presets
              Action {
                required property var modelData
                iconText: "\u{F00C0}"
                text: String(modelData)
                tooltipText: root.presetSummary(String(modelData)) + "\nLeft click: load · Right click: delete"
                onClicked: root.loadPreset(String(modelData))
                onRightClicked: root.deletePreset(String(modelData))
              }
            }
          }
          Row {
            width: parent.width
            spacing: Style.space(6)
            TextField {
              id: presetName
              width: parent.width - saveButton.width - parent.spacing
              placeholderText: "Save current setup as…"
              foreground: root.fg
              onAccepted: saveButton.clicked()
            }
            Action {
              id: saveButton
              iconText: "\u{F0193}"
              text: "Save"
              onClicked: {
                var name = presetName.text.trim()
                if (name === "") return
                root.savePreset(name)
                presetName.text = ""
              }
            }
          }
          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: "A preset saves position, image controls, audio mode and gestures. Camera and auto mode are left as they are."
            color: root.fg
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Section {
          title: "IMAGE"
          visible: root.tab === "image"
          Text {
            visible: root.controls.length === 0
            textFormat: Text.PlainText
            text: root.device === "" ? "No camera device reported by emeet-pixyd" : "Reading controls…"
            color: root.fg
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Repeater {
            model: root.controls
            Column {
              id: ctl
              required property var modelData
              readonly property var c: modelData
              width: parent ? parent.width : 0
              spacing: Style.space(4)
              // Inactive = governed by an automatic mode (e.g. exposure time
              // while auto exposure is on); the driver rejects writes.
              enabled: !c.inactive
              opacity: c.inactive ? 0.4 : 1.0

              SliderRow {
                visible: ctl.c.type === "int"
                text: ctl.c.label
                labelWidth: Style.space(150)
                minimum: ctl.c.min || 0
                maximum: ctl.c.max || 0
                step: ctl.c.step || 1
                current: ctl.c.value
                onCommitted: function(v) { root.setControl(ctl.c.name, v) }
                onReset: root.setControl(ctl.c.name, ctl.c.default)
              }
              Toggle {
                visible: ctl.c.type === "bool"
                width: parent.width
                label: ctl.c.label
                checked: ctl.c.value === 1
                foreground: root.fg
                fontFamily: root.fontFamily
                onClicked: root.setControl(ctl.c.name, ctl.c.value === 1 ? 0 : 1)
              }
              Text {
                visible: ctl.c.type === "menu"
                textFormat: Text.PlainText
                text: ctl.c.label
                color: root.fg
                opacity: 0.6
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              Choice {
                visible: ctl.c.type === "menu"
                value: String(ctl.c.value)
                options: ctl.c.options
                onChanged: function(v) { root.setControl(ctl.c.name, Number(v)) }
              }
            }
          }
          Action {
            iconText: "\u{F0450}"
            text: "Reset image to defaults"
            tooltipText: "Right click a slider to reset just that control"
            onClicked: root.writeControls(Controls.resetArg(root.controls))
          }
        }
      }
      }
    }
  }

  component Section: Column {
    property string title: ""
    default property alias content: body.data
    width: parent ? parent.width : 0
    spacing: Style.space(8)

    PanelSeparator { foreground: root.fg }
    PanelSectionHeader { text: parent.title; foreground: root.fg; fontFamily: root.fontFamily }
    Column { id: body; width: parent.width; spacing: Style.space(8) }
  }

  component Choice: ButtonGroup {
    foreground: root.fg
    fontFamily: root.fontFamily
    fontSize: Style.font.bodySmall
    focusable: false
  }

  component Action: Button {
    foreground: root.fg
    fontFamily: root.fontFamily
    fontSize: Style.font.bodySmall
    bordered: true
  }

  // Label, slider and value. Commits on release only, so a drag sends one
  // command (one motor move) instead of one per pixel. Right click = reset.
  component SliderRow: Row {
    id: srow
    property string text: ""
    property real labelWidth: Style.space(40)
    property real minimum: 0
    property real maximum: 0
    property real step: 1
    property real current: 0
    signal committed(int value)
    signal reset()
    width: parent ? parent.width : 0
    spacing: Style.space(8)

    Text {
      width: srow.labelWidth
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: srow.text
      elide: Text.ElideRight
      color: root.fg
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    PanelSlider {
      id: slider
      bar: root.bar
      width: parent.width - srow.labelWidth - Style.space(44) - parent.spacing * 2
      minimum: srow.minimum
      maximum: srow.maximum
      step: srow.step
      integer: true
      value: srow.current
      onReleased: function(v) { srow.committed(Math.round(v)) }
      onRightClicked: srow.reset()
    }
    Text {
      width: Style.space(44)
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
      text: String(Math.round(slider.liveValue))
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
