// Camera-use follower (replaces the old emeet-watch service): open the lens
// and track while an app uses the camera or microphone, privacy once idle.

var START_POLLS = 2 // x 2s: lens opens ~4s after an app starts using the camera
var POLL_SEC = 2
var END_POLLS = 5   // default x 2s: privacy ~10s after camera and audio capture stop

// Privacy delay in seconds -> idle polls (at least one).
function endPolls(delaySec) {
  return Math.max(1, Math.ceil(Number(delaySec) / POLL_SEC))
}

function initial() {
  return { primed: false, state: "", busy: 0, idle: 0 }
}

// After a (re)connect the camera is back at its firmware home position with
// the lens open. With startPrivacy the next idle polls close it; without, the
// lens is left alone until a call has come and gone.
function reconnected(startPrivacy) {
  return { primed: true, state: startPrivacy ? "" : "privacy", busy: 0, idle: 0 }
}

// One poll. Returns { next, action } with action "", "track" or "privacy".
// The first poll adopts the camera's hardware state instead of commanding it: a
// shell restart mid-call with the lens open never switches the camera, a
// privacy start with an app streaming still opens the lens, and an idle start
// with the lens open gets privacy only with startPrivacy (login / boot).
function step(s, inUse, camera, startPrivacy, idlePolls) {
  var end = idlePolls || END_POLLS
  if (!s.primed) {
    var state = camera === "privacy" || !startPrivacy ? "privacy" : (inUse ? "tracking" : "")
    if (camera !== "privacy" && inUse) state = "tracking"
    return { next: { primed: true, state: state, busy: 0, idle: 0 }, action: "" }
  }
  var busy = inUse ? s.busy + 1 : 0
  var idle = inUse ? 0 : s.idle + 1
  if (s.state !== "tracking" && busy >= START_POLLS)
    return { next: { primed: true, state: "tracking", busy: busy, idle: idle }, action: "track" }
  if (s.state !== "privacy" && idle >= end)
    return { next: { primed: true, state: "privacy", busy: busy, idle: idle }, action: "privacy" }
  return { next: { primed: true, state: s.state, busy: busy, idle: idle }, action: "" }
}

if (typeof module !== "undefined")
  module.exports = { START_POLLS: START_POLLS, END_POLLS: END_POLLS, endPolls: endPolls, initial: initial, reconnected: reconnected, step: step }
