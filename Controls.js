// Parses `v4l2-ctl --list-ctrls-menus` into image controls for the panel.

// emeet-pixyd owns the motors; touching them here would desync its state.
var DAEMON_OWNED = ["pan_absolute", "tilt_absolute", "zoom_absolute", "zoom_continuous"]

function parse(text) {
  var controls = []
  var last = null
  String(text).split("\n").forEach(function(line) {
    var head = line.match(/^\s*(\w+)\s+0x[0-9a-f]+\s+\((\w+)\)\s*:\s*(.*)$/)
    if (head) {
      last = null
      var type = head[2]
      if (type !== "int" && type !== "bool" && type !== "menu") return
      if (DAEMON_OWNED.indexOf(head[1]) !== -1) return
      var c = { name: head[1], type: type, label: label(head[1]), options: [] }
      var re = /(\w+)=(-?\d+)/g
      var m
      while ((m = re.exec(head[3])) !== null) c[m[1]] = Number(m[2])
      var flags = head[3].match(/flags=(.*)$/)
      c.inactive = !!flags && flags[1].indexOf("inactive") !== -1
      if (type === "int" && c.min === c.max) return
      controls.push(c)
      last = c
      return
    }
    var item = line.match(/^\s+(\d+): (.+)$/)
    if (item && last && last.type === "menu")
      last.options.push({ value: item[1], label: item[2].trim().replace(/ Mode$/, "") })
  })
  return controls
}

function label(name) {
  var s = name.replace(/_absolute$/, "").replace(/_/g, " ")
  return s.charAt(0).toUpperCase() + s.slice(1)
}

// `name=value,...` for every active control not at its default.
function resetArg(controls) {
  return controls
    .filter(function(c) { return !c.inactive && c.value !== c.default })
    .map(function(c) { return c.name + "=" + c.default })
    .join(",")
}

if (typeof module !== "undefined") module.exports = { parse: parse, label: label, resetArg: resetArg }
