import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar button + popup for the EMEET PIXY. Every action is one emeet-pixyd
// client call; the panel only renders what `status` reports back.
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

  onOpenedChanged: if (opened) { refresh(); presetsProc.running = true }
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
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: presetName.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
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

        Section {
          title: "CAMERA"
          Choice {
            value: root.camera
            options: [
              { value: "tracking", label: "Track", icon: "\u{F0C7B}" },
              { value: "idle", label: "Idle", icon: "\u{F04B2}" },
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
          Axis { name: "pan"; minimum: -150; maximum: 150 }
          Axis { name: "tilt"; minimum: -90; maximum: 90 }
          Axis { name: "zoom"; minimum: 100; maximum: 150 }
          Row {
            spacing: Style.space(6)
            Action { iconText: "\u{F01A4}"; text: "Center"; onClicked: root.run(["center"]) }
            Action { iconText: "\u{F0450}"; text: "Sync"; onClicked: root.run(["sync"]) }
            Action { iconText: "\u{F059F}"; text: "Web UI"; onClicked: { Quickshell.execDetached(["omarchy-launch-browser", root.webUrl]); root.close() } }
          }
        }

        Section {
          title: "PRESETS"
          Flow {
            width: parent.width
            spacing: Style.space(6)
            Repeater {
              model: root.presets
              Action {
                required property var modelData
                iconText: "\u{F00C0}"
                text: String(modelData)
                tooltipText: "Left click: load · Right click: delete"
                onClicked: root.run(["preset", "load", String(modelData)])
                onRightClicked: root.run(["preset", "delete", String(modelData)])
              }
            }
          }
          Row {
            width: parent.width
            spacing: Style.space(6)
            TextField {
              id: presetName
              width: parent.width - saveButton.width - parent.spacing
              placeholderText: "Save current position as…"
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
                root.run(["preset", "save", name])
                presetName.text = ""
              }
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

  // One PTZ axis: label, slider and value. Commands are sent on release only,
  // so a drag moves the motor once instead of per pixel.
  component Axis: Row {
    id: axis
    property string name: ""
    property real minimum: 0
    property real maximum: 0
    readonly property real current: Number(root.status[name] || 0)
    width: parent ? parent.width : 0
    spacing: Style.space(8)

    Text {
      width: Style.space(40)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: axis.name
      color: root.fg
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    PanelSlider {
      id: slider
      bar: root.bar
      width: parent.width - Style.space(40) - Style.space(40) - parent.spacing * 2
      minimum: axis.minimum
      maximum: axis.maximum
      step: 1
      integer: true
      value: axis.current
      onReleased: function(v) { root.run([axis.name, String(Math.round(v))]) }
    }
    Text {
      width: Style.space(40)
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
