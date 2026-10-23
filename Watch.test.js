// node Watch.test.js
const assert = require("node:assert/strict")
const W = require("./Watch.js")

function run(s, polls, camera = "tracking") {
  const actions = []
  for (const inUse of polls) {
    const r = W.step(s, inUse, camera)
    s = r.next
    if (r.action) actions.push(r.action)
  }
  return actions
}

// Shell restart mid-call with the lens open: adopt, never switch the camera.
assert.deepEqual(run(W.initial(), [true, true, true, true], "tracking"), [])
assert.deepEqual(run(W.initial(), [true, true, true, true], "idle"), [])
// ...and the call ending afterwards still closes the lens.
assert.deepEqual(run(W.initial(), [true, true, false, false, false, false, false]), ["privacy"])

// Start in privacy while an app is streaming (the stale-icon bug): open it.
assert.deepEqual(run(W.initial(), [true, true, true], "privacy"), ["track"])
// Start in privacy, idle: nothing to do.
assert.deepEqual(run(W.initial(), Array(12).fill(false), "privacy"), [])

// Idle start with the lens open (boot): privacy after END_POLLS polls, once.
assert.deepEqual(run(W.initial(), Array(12).fill(false)), ["privacy"])

// A call: track after START_POLLS busy polls, privacy after END_POLLS idle ones.
const call = [false, ...Array(5).fill(false), true, true, true, ...Array(5).fill(false)]
assert.deepEqual(run(W.initial(), call), ["privacy", "track", "privacy"])

// A single busy blip neither tracks nor resets privacy.
assert.deepEqual(run(W.initial(), [false, false, false, false, false, false, true, false, false]), ["privacy"])

// Reconnect while busy re-tracks; while idle re-applies privacy.
assert.deepEqual(run(W.reconnected(), [true, true]), ["track"])
assert.deepEqual(run(W.reconnected(), Array(5).fill(false)), ["privacy"])

console.log("ok")
