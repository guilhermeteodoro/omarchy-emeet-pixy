// Camera-use follower (replaces the old emeet-watch service): open the lens
// and track while an app uses the camera or microphone, privacy once idle.
// emeet-pixyd's own auto mode is turned off so the two never fight.

var START_POLLS = 2 // x 2s: lens opens ~4s after an app starts using the camera
var END_POLLS = 5   // x 2s: privacy ~10s after camera and audio capture stop

function initial() {
  return { primed: false, state: "", busy: 0, idle: 0 }
}

// After a (re)connect the camera is back at its firmware home position, so
// forget what was applied and let the next polls command it again.
function reconnected() {
  return { primed: true, state: "", busy: 0, idle: 0 }
}

// One poll. Returns { next, action } with action "", "track" or "privacy".
// The first poll adopts the camera's synced state instead of commanding it: a
// shell restart mid-call with the lens open never switches the camera, while
// an idle start still gets privacy and a privacy start with an app streaming
// still opens the lens.
function step(s, inUse, camera) {
  if (!s.primed) {
    var state = camera === "privacy" ? "privacy" : (inUse ? "tracking" : "")
    return { next: { primed: true, state: state, busy: 0, idle: 0 }, action: "" }
  }
  var busy = inUse ? s.busy + 1 : 0
  var idle = inUse ? 0 : s.idle + 1
  if (s.state !== "tracking" && busy >= START_POLLS)
    return { next: { primed: true, state: "tracking", busy: busy, idle: idle }, action: "track" }
  if (s.state !== "privacy" && idle >= END_POLLS)
    return { next: { primed: true, state: "privacy", busy: busy, idle: idle }, action: "privacy" }
  return { next: { primed: true, state: s.state, busy: busy, idle: idle }, action: "" }
}

if (typeof module !== "undefined")
  module.exports = { START_POLLS: START_POLLS, END_POLLS: END_POLLS, initial: initial, reconnected: reconnected, step: step }
