import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui
import "Controls.js" as Controls
import "Watch.js" as Watch

// Bar button + popup for the EMEET PIXY, and the one place that manages it:
// camera actions are emeet-pixyd client calls, image controls go straight to
// V4L2 with v4l2-ctl (like cameractrls), and the widget follows camera use
// (Watch.js) and restores a preset whenever the camera connects.
Panel {
  id: root
  moduleName: "guilhermeteodoro.emeet-pixy"

  readonly property string command: String(setting("command", "emeet-pixy"))
  readonly property int refreshIntervalSec: Math.max(1, Number(setting("refreshIntervalSec", 5)))
  readonly property bool followUsage: setting("followUsage", true) === true
  readonly property bool preview: setting("preview", false) === true
  // Close the lens at login and when the camera is plugged in (it powers up
  // at its firmware home position with the lens open).
  readonly property bool startPrivacy: setting("startPrivacy", true) === true
  // Mode the follower opens the lens in when a meeting starts: `track`, or
  // `idle` (Static), which returns to the last Static position.
  readonly property string meetingMode: setting("meetingMode", "track") === "idle" ? "idle" : "track"
  // Bar button: left always opens the panel; middle and right are configurable.
  readonly property string middleClick: String(setting("middleClick", "static-track"))
  readonly property string rightClick: String(setting("rightClick", "toggle-privacy"))
  readonly property var clickActions: [
    { value: "static-track", label: "Switch Static \u2194 Track" },
    { value: "toggle-privacy", label: "Privacy \u2194 previous mode" },
    { value: "none", label: "Nothing" }
  ]
  // Last non-privacy mode, for "Privacy <-> previous mode".
  property string lastMode: "idle"

  function clickLabel(action) {
    for (var i = 0; i < clickActions.length; i++) if (clickActions[i].value === action) return clickActions[i].label
    return action
  }

  function runClick(action) {
    if (action === "static-track") run([camera === "tracking" ? "idle" : "track"])
    else if (action === "toggle-privacy") run([camera === "privacy" ? (lastMode === "tracking" ? "track" : "idle") : "privacy"])
  }
  // Current preset: the last one picked. Panel changes save into it.
  readonly property string currentPreset: String(setting("preset", ""))

  readonly property color fg: bar ? bar.foreground : Color.foreground
  // Bar icon colors, matching the camera's own LED.
  readonly property color staticColor: "#4ade80"
  readonly property color trackColor: "#3b82f6"
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Parsed `status`: camera, audio, gesture, pan, tilt, zoom, in_call, auto, device.
  property var status: ({})
  property var presets: []
  // Everything a preset holds beyond the daemon's pan/tilt/zoom, keyed by
  // preset name: { image: {control: value}, audio, gesture }.
  property var presetExtras: ({})
  readonly property string presetsPath: Quickshell.env("HOME") + "/.config/omarchy/emeet-pixy-presets.json"
  // Panel tab; kept while the shell runs so reopening lands where you left.
  property string tab: "position"
  readonly property var tabs: ["position", "image", "privacy"]
  property bool naming: false
  // Parsed `v4l2-ctl --list-ctrls-menus`, see Controls.js.
  property var controls: []
  readonly property string device: status.device || ""
  readonly property bool online: status.camera !== undefined
  readonly property string camera: status.camera || ""
  readonly property bool inCall: status.in_call === "yes"

  // Live preview: ffmpeg in its own process copies MJPEG frames to one file
  // that an Image reloads. Not QtMultimedia: it keeps the device streaming
  // inside the shell process until the shell exits, which blocks meeting apps
  // and looks like a never-ending meeting to the follower. Killing ffmpeg
  // releases the camera.
  readonly property string previewFrame: Quickshell.env("XDG_RUNTIME_DIR") + "/emeet-pixy-preview.jpg"
  readonly property bool previewWanted: opened && preview && device !== ""
  property string previewError: ""
  property int previewTick: 0
  onPreviewWantedChanged: { if (previewWanted) previewError = ""; previewProc.running = previewWanted }

  Process {
    id: previewProc
    command: ["sh", "-c", 'rm -f "$1"; exec ffmpeg -hide_banner -loglevel error -f v4l2 -input_format mjpeg -video_size 640x360 -framerate 15 -i "$0" -c:v copy -f image2 -update 1 -atomic_writing 1 -y "$1"',
      root.device, root.previewFrame]
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (root.previewWanted) root.previewError = /busy/i.test(text) ? "Camera in use by another app" : (String(text).trim().split("\n").pop() || "Preview stopped")
    }
  }
  Timer { interval: 66; repeat: true; running: previewProc.running; onTriggered: root.previewTick++ }

  property var watch: Watch.initial()
  property bool connectPending: false
  // Any app recording audio counts as use, so an audio-only call keeps the
  // lens state too (same rule as the old emeet-watch service).
  readonly property bool capturing: {
    var nodes = Pipewire.nodes ? Pipewire.nodes.values : []
    for (var i = 0; i < nodes.length; i++)
      if (nodes[i] && nodes[i].isStream && nodes[i].isSink === false) return true
    return false
  }

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

  // Writes the live setup into the current preset. PTZ goes to the daemon's
  // preset only when the panel moved the motors: during tracking the position
  // drifts on its own and is not a setting.
  function saveCurrent(withPosition) {
    if (currentPreset === "") return
    if (withPosition) run(["preset", "save", currentPreset])
    var next = Object.assign({}, presetExtras)
    var image = controls.length > 0 ? Controls.snapshot(controls) : (presetExtras[currentPreset] || {}).image
    next[currentPreset] = { image: image || {}, audio: status.audio || "", gesture: status.gesture === "true" }
    savePresetExtras(next)
  }

  // Every setting change made in the panel lands here. The save waits for the
  // status and control re-reads so it stores what the camera actually took.
  property bool positionDirty: false
  function noteChange(position) {
    if (position) positionDirty = true
    autosave.restart()
  }

  function createPreset(name) {
    setSetting("preset", name)
    saveCurrent(true)
    presetsSoon.restart()
  }

  function deleteCurrent() {
    if (currentPreset === "") return
    run(["preset", "delete", currentPreset])
    var next = Object.assign({}, presetExtras)
    delete next[currentPreset]
    savePresetExtras(next)
    setSetting("preset", "")
    presetsSoon.restart()
  }

  // Loading makes it the current preset. One sequential script so the image
  // writes land after the daemon has settled; values travel as positional
  // args, never interpolated.
  function loadPreset(name) {
    autosave.stop()
    positionDirty = false
    setSetting("preset", name)
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
    var previous = status.camera
    status = next
    if (next.camera === "tracking" || next.camera === "idle") lastMode = next.camera
    if (next.camera !== "idle" || ptzProc.running || motorProc.running) return
    if (previous === "privacy") restoreStatic(next)
    else if (previous === "tracking") readMotors(true)
    else rememberStatic(next)
  }

  // Tracking moves the motors without telling the daemon or V4L2, which keep
  // the last position that was *set*. Worse, UVC pan and tilt are one control,
  // so a stale tilt rides along with the next pan. bin/motorpos reads the real
  // position from the firmware (GET_MOTOR_POS over hidraw):
  // - while tracking, the sliders follow it (panel open, once a second);
  // - Tracking -> Static hands it to the daemon, so sliders, daemon and motors
  //   agree again before anyone moves a slider.
  // Privacy -> Static returns to the last Static position, kept across restarts.
  property string hidraw: ""
  // install.sh grants the HID node to the logged-in user; live position, the
  // privacy timer and emeet-pixyd's HID controls need it. Missing access means
  // setup was skipped, so the panel says so instead of offering an option.
  property bool hidrawAccess: true
  readonly property string setupCommand: "'" + Qt.resolvedUrl("install.sh").toString().replace(/^file:\/\//, "") + "'"

  function checkAccess() {
    if (!accessProc.running) accessProc.running = true
  }

  // The camera's own idle timer (bin/privacytimer, seconds without streaming,
  // 0 = never) closes the lens while video is turned off mid-meeting. "Keep camera
  // awake during meetings" turns it off; otherwise it uses the same delay
  // as the follower. -1 = not read yet.
  property int privacyTimer: -1
  readonly property bool keepLensOpen: privacyTimer === 0
  // Seconds from the end of a meeting to Privacy mode (follower and timer).
  readonly property int privacyDelay: Math.max(2, Number(setting("privacyDelaySec", 10)))

  function privacyTimerCall(seconds) {
    if (hidraw === "" || !hidrawAccess || timerProc.running) return
    var args = [Qt.resolvedUrl("bin/privacytimer").toString().replace(/^file:\/\//, ""), hidraw]
    timerProc.command = seconds === undefined ? args : args.concat([String(seconds)])
    timerProc.running = true
  }

  Process {
    id: timerProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { var n = parseInt(String(text).trim(), 10); if (!isNaN(n)) root.privacyTimer = n }
    }
  }

  property var livePosition: null
  property bool adoptPending: false
  readonly property var staticPosition: setting("staticPosition", null)

  function readMotors(adopt) {
    if (hidraw === "" || motorProc.running) return
    adoptPending = adopt
    motorProc.running = true
  }

  function onMotorsRead(text) {
    var v = String(text).trim().split(/\s+/).map(Number)
    if (v.length !== 2 || isNaN(v[0]) || isNaN(v[1])) return
    livePosition = { pan: v[0], tilt: v[1] }
    if (!adoptPending) return
    adoptPending = false
    // Whole degrees: the motors move at most half a degree.
    ptzProc.command = ["sh", "-c",
      'PATH="$PATH:$HOME/.nix-profile/bin:$HOME/.local/bin"\n' +
      '"$0" pan "$1" && "$0" tilt "$2"',
      command, String(Math.round(v[0])), String(Math.round(v[1]))]
    ptzProc.running = true
  }

  function rememberStatic(s) {
    var p = { pan: Number(s.pan), tilt: Number(s.tilt), zoom: Number(s.zoom) }
    if (isNaN(p.pan) || isNaN(p.tilt) || isNaN(p.zoom)) return
    var q = staticPosition
    if (q && q.pan === p.pan && q.tilt === p.tilt && q.zoom === p.zoom) return
    setSetting("staticPosition", p)
  }

  // `center` first: the daemon would skip a move to the position it already
  // believes in, but privacy moved the motors elsewhere.
  function restoreStatic(s) {
    var p = staticPosition || { pan: Number(s.pan) || 0, tilt: Number(s.tilt) || 0, zoom: Number(s.zoom) || 100 }
    ptzProc.command = ["sh", "-c",
      'PATH="$PATH:$HOME/.nix-profile/bin:$HOME/.local/bin"\n' +
      '"$0" center && "$0" pan "$1" && "$0" tilt "$2" && "$0" zoom "$3"',
      command, String(p.pan), String(p.tilt), String(p.zoom)]
    ptzProc.running = true
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
    noteChange(false)
  }

  // Persists one key of this widget's shell.json entry.
  function setSetting(key, value) {
    var next = Object.assign({}, settings)
    next[key] = value
    settings = next
    if (bar && bar.shell && bar.shell.updateEntryInline) bar.shell.updateEntryInline(moduleName, next)
  }

  function pollUse(videoBusy) {
    var wasPrimed = watch.primed
    // The preview counts as camera use, so hiding it (or closing the panel)
    // ends it like a meeting: Privacy after privacyDelay. Its lens mode is
    // set by the Preview button, so mark the lens open: no `track` action.
    if (previewProc.running && watch.primed && watch.state !== "tracking")
      watch = Object.assign({}, watch, { state: "tracking" })
    var inUse = videoBusy || capturing
    var r = Watch.step(watch, inUse, camera, startPrivacy, Watch.endPolls(privacyDelay))
    watch = r.next
    if (!wasPrimed && !inUse) applyCurrentImage()
    if (r.action === "track") {
      var extra = presetExtras[currentPreset]
      run([meetingMode])
      run(["audio", extra && extra.audio ? extra.audio : "nc"])
    } else if (r.action === "privacy") {
      run(["privacy"])
    }
  }

  // Re-read the controls first: applyArgs needs their types to order writes.
  function applyCurrentImage() {
    if (!presetExtras[currentPreset]) return
    connectPending = true
    if (!controlsProc.running) controlsProc.running = true
  }

  function onControlsRead(text) {
    controls = Controls.parse(text)
    if (!connectPending) return
    connectPending = false
    var extra = presetExtras[currentPreset]
    if (!extra) return
    var image = Controls.applyArgs(extra.image, controls)
    Quickshell.execDetached(["sh", "-c",
      '[ -n "$1" ] && v4l2-ctl -d "$0" -c "$1"\n[ -n "$2" ] && v4l2-ctl -d "$0" -c "$2"\nexit 0',
      device, image.modes, image.values])
    controlsSoon.restart()
  }

  function reconnect() {
    run(["sync"])
    watch = Watch.reconnected(startPrivacy)
    applyCurrentImage()
  }

  onFollowUsageChanged: if (followUsage) run(["auto-off"])

  onOpenedChanged: if (opened) { refresh(); presetsProc.running = true; refreshControls(); privacyTimerCall() }
  onDeviceChanged: { if (opened) refreshControls(); deviceProc.running = true }
  onCommandChanged: refresh()
  // sync first: the watcher's first poll adopts the camera state, so it must
  // be the hardware's, not whatever the daemon last believed.
  Component.onCompleted: { if (followUsage) { run(["auto-off"]); run(["sync"]) } refresh() }

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
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.onControlsRead(text) }
  }

  Process {
    id: useProc
    command: [Qt.resolvedUrl("bin/streaming").toString().replace(/^file:\/\//, ""), root.device]
    onExited: function(exitCode) { root.pollUse(exitCode === 0) }
  }

  Timer {
    interval: 2000
    running: root.followUsage && root.device !== ""
    repeat: true
    onTriggered: if (!useProc.running) useProc.running = true
  }

  // Camera (re)connects: the daemon re-probes on its own; give it a moment,
  // then reconcile. The PIXY adds several video nodes, hence the debounce.
  Process {
    running: true
    command: ["udevadm", "monitor", "--udev", "--subsystem-match=video4linux"]
    stdout: SplitParser {
      onRead: function(line) { if (/\sadd\s/.test(line)) reconnectSoon.restart() }
    }
  }
  Timer { id: reconnectSoon; interval: 3000; onTriggered: root.reconnect() }

  // The panel already shows writes optimistically; this re-read only catches
  // clamping and (in)active flips, so it can wait for a preset script to finish.
  Timer { id: controlsSoon; interval: 1500; onTriggered: root.refreshControls() }

  // Restore/adopt of the Static position; parseStatus skips memorising while
  // it runs so the in-between position is never stored.
  Process {
    id: ptzProc
    // No autosave: these positions come from the camera, not from the user.
    onExited: root.refresh()
  }

  // emeet-pixy device -> "/dev/videoN /dev/hidrawM MODEL"
  Process {
    id: deviceProc
    command: root.argv(["device"])
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var m = String(text).match(/\/dev\/hidraw\d+/)
        root.hidraw = m ? m[0] : ""
        if (root.hidraw !== "") root.checkAccess()
      }
    }
  }

  Process {
    id: accessProc
    command: ["test", "-w", root.hidraw]
    onExited: function(code) {
      root.hidrawAccess = code === 0
      if (root.hidrawAccess) root.privacyTimerCall()
    }
  }

  Process {
    id: motorProc
    command: [Qt.resolvedUrl("bin/motorpos").toString().replace(/^file:\/\//, ""), root.hidraw]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.onMotorsRead(text) }
  }

  Timer {
    interval: 1000
    running: root.opened && root.camera === "tracking" && root.hidraw !== ""
    repeat: true
    triggeredOnStart: true
    onTriggered: root.readMotors(false)
  }

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
  // Fires after refreshSoon and controlsSoon, so it saves re-read values.
  Timer { id: autosave; interval: 2500; onTriggered: { root.saveCurrent(root.positionDirty); root.positionDirty = false } }
  Timer { id: presetsSoon; interval: 1200; onTriggered: presetsProc.running = true }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.cameraIcon()
    active: root.camera === "tracking" || root.camera === "idle"
    activeColor: root.camera === "tracking" ? root.trackColor : root.staticColor
    dimmed: !root.online
    tooltipText: "EMEET PIXY: " + root.summary() + (root.currentPreset !== "" ? "\nPreset: " + root.currentPreset : "")
      + "\nMiddle click: " + root.clickLabel(root.middleClick) + " \u00B7 Right click: " + root.clickLabel(root.rightClick)
    onPressed: function(b) {
      if (b === Qt.RightButton) root.runClick(root.rightClick)
      else if (b === Qt.MiddleButton) root.runClick(root.middleClick)
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
          // Top-right holds the preview toggle; the device path is in its tooltip.
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
          trailingControl: Component {
            Action {
              bordered: false
              // Padding is the hit area; the glyph stays small.
              horizontalPadding: Style.space(10)
              verticalPadding: Style.space(8)
              iconText: "\u{F05A0}"
              opacity: root.preview ? 1.0 : 0.45
              tooltipText: (root.preview ? "Hide preview" : "Live preview") + (root.status.device ? " (" + root.status.device + ")" : "")
              // Turning it on opens the lens in the meeting mode; Static returns
              // to the last Static position (Privacy -> Static restore).
              onClicked: {
                if (!root.preview && root.camera === "privacy") root.run([root.meetingMode])
                root.setSetting("preview", !root.preview)
              }
            }
          }
        }


        Choice {
          width: parent.width
          value: root.tab
          options: [
            { value: "position", label: "Position", icon: "\u{F0100}" },
            { value: "image", label: "Image", icon: "\u{F02F1}" },
            { value: "privacy", label: "Privacy settings", icon: "\u{F099D}" }
          ]
          onChanged: function(v) { root.tab = v }
        }

        Section {
          title: "SETUP INCOMPLETE"
          visible: root.hidraw !== "" && !root.hidrawAccess
          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: "This plugin can't reach the camera's controls, so live position and the privacy timer are off. Run the plugin's setup once in a terminal (it asks for your password), then replug the camera."
            color: root.fg
            opacity: 0.8
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Action {
            iconText: "\u{F018F}"
            text: "Copy setup command"
            tooltipText: root.setupCommand
            onClicked: Quickshell.execDetached(["wl-copy", root.setupCommand])
          }
        }

        Item {
            width: parent.width
            height: width * 9 / 16
            visible: root.preview
            Image {
              anchors.fill: parent
              fillMode: Image.PreserveAspectFit
              cache: false
              retainWhileLoading: true
              source: previewProc.running ? "file://" + root.previewFrame + "?" + root.previewTick : ""
              visible: previewMessage.text === ""
            }
            Text {
              id: previewMessage
              anchors.centerIn: parent
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: root.device === "" ? "No EMEET PIXY camera found"
                : root.previewError !== "" ? root.previewError
                : root.camera === "privacy" ? "Lens closed — choose Static or Track to preview"
                : ""
              color: root.fg
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
        }

        Section {
          title: "CAMERA"
          visible: root.tab === "position"
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
        }

        Section {
          title: "AUDIO"
          visible: root.tab === "position"
          Choice {
            value: root.status.audio || ""
            options: [
              { value: "nc", label: "Noise cancel" },
              { value: "live", label: "Live" },
              { value: "org", label: "Original" }
            ]
            onChanged: function(v) { root.run(["audio", v]); root.noteChange(false) }
          }
        }

        Section {
          title: "AUTOMATION"
          visible: root.tab === "position"
          Toggle {
            width: parent.width
            label: "Gesture control"
            checked: root.status.gesture === "true"
            foreground: root.fg
            fontFamily: root.fontFamily
            onClicked: { root.run(["toggle-gesture"]); root.noteChange(false) }
          }
        }

        Section {
          title: "PAN · TILT · ZOOM"
          visible: root.tab === "position"
          Text {
            visible: root.camera !== "idle"
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: "Pan and tilt work in Static; while tracking they show where the motors are. Zoom works in Static and Track."
            color: root.fg
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Column {
            width: parent.width
            spacing: Style.space(8)
            // Tracking and privacy drive pan/tilt themselves.
            enabled: root.camera === "idle"
            opacity: enabled ? 1.0 : 0.4
            SliderRow { text: "\u{F0BB8} pan"; labelWidth: Style.space(70); minimum: -150; maximum: 150; current: root.camera === "tracking" && root.livePosition ? root.livePosition.pan : Number(root.status.pan || 0); onCommitted: function(v) { root.run(["pan", String(v)]); root.noteChange(true) } }
            SliderRow { text: "\u{F0BBE} tilt"; labelWidth: Style.space(70); minimum: -90; maximum: 90; current: root.camera === "tracking" && root.livePosition ? root.livePosition.tilt : Number(root.status.tilt || 0); onCommitted: function(v) { root.run(["tilt", String(v)]); root.noteChange(true) } }
          }
          // Zoom is not moved by tracking, so it stays usable there.
          SliderRow { text: "\u{F06ED} zoom"; labelWidth: Style.space(70); enabled: root.camera === "idle" || root.camera === "tracking"; opacity: enabled ? 1.0 : 0.4; minimum: 100; maximum: 150; current: Number(root.status.zoom || 0); onCommitted: function(v) { root.run(["zoom", String(v)]); root.noteChange(true) } }
          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.StyledText
            text: 'Camera control by <a href="https://github.com/LarsArtmann/emeet-pixyd">emeet-pixyd</a>'
            linkColor: root.fg
            color: root.fg
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            onLinkActivated: function(link) { Quickshell.execDetached(["omarchy-launch-browser", link]); root.close() }
            HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
          }
        }

        Section {
          title: "PRIVACY"
          visible: root.tab === "privacy"
          Toggle {
            width: parent.width
            label: "Follow camera use"
            description: "Track ~4s after an app uses the camera or mic; Privacy mode once the meeting is over"
            checked: root.followUsage
            foreground: root.fg
            fontFamily: root.fontFamily
            onClicked: root.setSetting("followUsage", !root.followUsage)
          }
          PickRow {
            text: "Meeting starts in"
            value: root.meetingMode
            options: [
              { value: "track", label: "Track" },
              { value: "idle", label: "Static (last position)" }
            ]
            enabled: root.followUsage
            opacity: enabled ? 1.0 : 0.4
            onPicked: function(v) { root.setSetting("meetingMode", v) }
          }
          Toggle {
            width: parent.width
            label: "Start in Privacy mode"
            description: "Go into Privacy mode at login and whenever the camera is plugged in"
            checked: root.startPrivacy
            enabled: root.followUsage
            opacity: enabled ? 1.0 : 0.4
            foreground: root.fg
            fontFamily: root.fontFamily
            onClicked: root.setSetting("startPrivacy", !root.startPrivacy)
          }
          Toggle {
            width: parent.width
            visible: root.privacyTimer >= 0
            label: "Keep camera awake during meetings"
            description: "Stops the camera's default of going into Privacy mode when you turn your video off in a call"
            checked: root.keepLensOpen
            foreground: root.fg
            fontFamily: root.fontFamily
            onClicked: root.privacyTimerCall(root.keepLensOpen ? root.privacyDelay : 0)
          }
          NumberField {
            label: "Seconds to Privacy mode after a meeting ends"
            from: 2
            to: 3600
            value: root.privacyDelay
            foreground: root.fg
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            onModified: function(v) {
              root.setSetting("privacyDelaySec", v)
              if (root.privacyTimer > 0) root.privacyTimerCall(v)
            }
          }
        }

        Section {
          title: "BAR BUTTON"
          visible: root.tab === "privacy"
          Text {
            textFormat: Text.PlainText
            text: "Left click: open this panel"
            color: root.fg
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          PickRow { text: "Middle click"; value: root.middleClick; onPicked: function(v) { root.setSetting("middleClick", v) } }
          PickRow { text: "Right click"; value: root.rightClick; onPicked: function(v) { root.setSetting("rightClick", v) } }
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

        // Preset bar: last, on every tab, since every tab edits the current preset.
        Section {
          title: "PRESET"
          Row {
            width: parent.width
            spacing: Style.space(6)
            Dropdown {
              width: parent.width - newButton.width - deleteButton.width - parent.spacing * 2
              showLabel: false
              // Match the New / delete buttons next to it.
              rowHeight: newButton.height
              value: root.currentPreset
              options: root.presets
              fontFamily: root.fontFamily
              onChanged: function(v) { root.loadPreset(v) }
            }
            Action {
              id: newButton
              iconText: "\u{F0415}"
              text: "New"
              tooltipText: "Save the current setup as a new preset"
              onClicked: root.naming = !root.naming
            }
            Action {
              id: deleteButton
              iconText: "\u{F01B4}"
              tooltipText: "Delete " + root.currentPreset
              enabled: root.currentPreset !== ""
              opacity: enabled ? 1.0 : 0.4
              onClicked: root.deleteCurrent()
            }
          }
          Row {
            visible: root.naming
            width: parent.width
            spacing: Style.space(6)
            TextField {
              id: presetName
              width: parent.width - createButton.width - parent.spacing
              placeholderText: "New preset name"
              foreground: root.fg
              onAccepted: createButton.clicked()
            }
            Action {
              id: createButton
              iconText: "\u{F0193}"
              text: "Create"
              onClicked: {
                var name = presetName.text.trim()
                if (name === "") return
                root.createPreset(name)
                presetName.text = ""
                root.naming = false
              }
            }
          }
          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: root.currentPreset !== ""
              ? "Changes save to \u201C" + root.currentPreset + "\u201D automatically: position, image, audio, gestures."
              : "No preset selected: changes are not saved."
            color: root.fg
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
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

  // A labelled setting picker (defaults to the bar-button click actions).
  component PickRow: Row {
    id: crow
    property string text: ""
    property string value: ""
    property var options: root.clickActions
    signal picked(string value)
    width: parent ? parent.width : 0
    spacing: Style.space(8)

    Text {
      width: Style.space(110)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: crow.text
      color: root.fg
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Dropdown {
      width: parent.width - Style.space(110) - parent.spacing
      showLabel: false
      value: crow.value
      options: crow.options
      fontFamily: root.fontFamily
      onChanged: function(v) { crow.picked(v) }
    }
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
    // < > buttons move by one step.
    property real arrowStep: step
    signal committed(int value)
    signal reset()
    function nudge(dir) {
      var v = Math.max(minimum, Math.min(maximum, Math.round(slider.liveValue) + dir * arrowStep))
      slider.liveValue = v
      committed(v)
    }
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
    Action { id: less; visible: srow.arrowStep > 0; bordered: false; horizontalPadding: 0; verticalPadding: 0; iconSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter; iconText: "\u{F0141}"; onClicked: srow.nudge(-1) }
    PanelSlider {
      id: slider
      bar: root.bar
      width: parent.width - srow.labelWidth - Style.space(44) - parent.spacing * 2
        - (srow.arrowStep > 0 ? less.width + more.width + parent.spacing * 2 : 0)
      minimum: srow.minimum
      maximum: srow.maximum
      step: srow.step
      integer: true
      value: srow.current
      onReleased: function(v) { srow.committed(Math.round(v)) }
      onRightClicked: srow.reset()
    }
    Action { id: more; visible: srow.arrowStep > 0; bordered: false; horizontalPadding: 0; verticalPadding: 0; iconSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter; iconText: "\u{F0142}"; onClicked: srow.nudge(1) }
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
