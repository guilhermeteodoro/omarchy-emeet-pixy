// node Controls.test.js — fixture is real EMEET PIXY output.
const assert = require("node:assert/strict")
const { parse, resetArg, snapshot, applyArgs } = require("./Controls.js")

const fixture = `
User Controls

                     brightness 0x00980900 (int)    : min=0 max=255 step=1 default=128 value=128 flags=has-min-max
                       contrast 0x00980901 (int)    : min=0 max=255 step=1 default=128 value=74 flags=has-min-max
        white_balance_automatic 0x0098090c (bool)   : default=1 value=1
           power_line_frequency 0x00980918 (menu)   : min=0 max=2 default=2 value=2 (60 Hz)
				0: Disabled
				1: 50 Hz
				2: 60 Hz
      white_balance_temperature 0x0098091a (int)    : min=2300 max=7500 step=1 default=5000 value=5000 flags=inactive, has-min-max

Camera Controls

                  auto_exposure 0x009a0901 (menu)   : min=0 max=3 default=3 value=3 (Aperture Priority Mode)
				1: Manual Mode
				3: Aperture Priority Mode
         exposure_time_absolute 0x009a0902 (int)    : min=1 max=5000 step=1 default=300 value=312 flags=inactive, has-min-max
                   pan_absolute 0x009a0908 (int)    : min=-540000 max=540000 step=3600 default=0 value=21600 flags=has-min-max
                zoom_continuous 0x009a090f (int)    : min=0 max=0 step=0 default=0 value=0 flags=has-min-max
`

const controls = parse(fixture)
const byName = Object.fromEntries(controls.map(c => [c.name, c]))

assert.deepEqual(controls.map(c => c.name), [
  "brightness", "contrast", "white_balance_automatic", "power_line_frequency",
  "white_balance_temperature", "auto_exposure", "exposure_time_absolute",
])
assert.equal(byName.contrast.value, 74)
assert.equal(byName.contrast.max, 255)
assert.equal(byName.white_balance_temperature.inactive, true)
assert.equal(byName.brightness.inactive, false)
assert.equal(byName.exposure_time_absolute.label, "Exposure time")
// Sparse menu indexes survive; the trailing "(60 Hz)" label is not an option.
assert.deepEqual(byName.auto_exposure.options.map(o => o.value), ["1", "3"])
assert.equal(byName.power_line_frequency.options[1].label, "50 Hz")
assert.equal(byName.power_line_frequency.value, 2)
// Reset skips inactive controls (the driver rejects writes to them).
assert.equal(resetArg(controls), "contrast=128")


// Presets skip inactive controls and apply auto-mode switches before values.
const image = snapshot(controls)
assert.equal(image.exposure_time_absolute, undefined)
assert.equal(image.contrast, 74)
const args = applyArgs({ auto_exposure: 1, exposure_time_absolute: 200, brightness: 90, white_balance_automatic: 0, gone: 5 }, controls)
assert.equal(args.modes, "auto_exposure=1,white_balance_automatic=0")
assert.equal(args.values, "exposure_time_absolute=200,brightness=90")
assert.deepEqual(applyArgs(undefined, controls), { modes: "", values: "" })

console.log("ok")
