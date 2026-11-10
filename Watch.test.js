// node Watch.test.js
const assert = require("node:assert/strict")
const W = require("./Watch.js")

function run(s, polls, camera = "tracking", startPrivacy = true) {
  const actions = []
  for (const inUse of polls) {
    const r = W.step(s, inUse, false, camera, startPrivacy)
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
assert.deepEqual(run(W.reconnected(true), [true, true]), ["track"])
assert.deepEqual(run(W.reconnected(true), Array(5).fill(false)), ["privacy"])

// Start in Privacy mode off: an idle start or reconnect leaves the lens alone...
assert.deepEqual(run(W.initial(), Array(12).fill(false), "idle", false), [])
assert.deepEqual(run(W.reconnected(false), Array(12).fill(false), "idle", false), [])
// ...but a call still tracks and its end still closes the lens.
assert.deepEqual(run(W.initial(), [false, true, true, ...Array(5).fill(false)], "idle", false), ["track", "privacy"])
// A shell restart mid-call is unaffected by the option.
assert.deepEqual(run(W.initial(), [true, true, true], "tracking", false), [])

// Audio only (a call that picked another camera): the lens state never follows it...
{
  let st = W.reconnected(true), acts = []
  for (const [v, a] of [[false, false], ...Array(6).fill([false, true])]) { const r = W.step(st, v, a, "idle", true); st = r.next; if (r.action) acts.push(r.action) }
  assert.deepEqual(acts, [], "mic alone neither tracks nor closes an open lens")
  st = W.reconnected(true)
  for (const [v, a] of Array(8).fill([false, false]).concat(Array(8).fill([false, true]))) { const r = W.step(st, v, a, "privacy", true); st = r.next; if (r.action) acts.push(r.action) }
  assert.deepEqual(acts, ["privacy"], "mic alone never opens a closed lens")
}
// ...but a call whose video goes off keeps the lens open while the mic records.
{
  let st = W.initial(), acts = []
  for (const [v, a] of [[false, false], [true, true], [true, true], ...Array(8).fill([false, true]), ...Array(5).fill([false, false])]) { const r = W.step(st, v, a, "privacy", true); st = r.next; if (r.action) acts.push(r.action) }
  assert.deepEqual(acts, ["track", "privacy"])
}
// Privacy delay: 60 s after a call = 30 idle polls.
assert.equal(W.endPolls(60), 30)
assert.equal(W.endPolls(1), 1)
{
  let st = W.initial(), acts = []
  for (const u of [false, true, true, ...Array(29).fill(false)]) { const r = W.step(st, u, false, "idle", false, W.endPolls(60)); st = r.next; if (r.action) acts.push(r.action) }
  assert.deepEqual(acts, ["track"])
  const r = W.step(st, false, false, "idle", false, W.endPolls(60))
  assert.equal(r.action, "privacy")
}

console.log("ok")
