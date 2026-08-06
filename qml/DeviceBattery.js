// Pure data helpers for the Device Battery Stats plugin.
// Consumes the JSON document produced by scripts/device-battery.sh and turns
// raw collector records into view-ready device objects plus a bar summary.

.pragma library

var GLYPH_KEYBOARD = "\uE312"
var GLYPH_MOUSE = "\uE323"
var GLYPH_HEADSET = "\uE311"
var GLYPH_GAMEPAD = "\uEA28"
var GLYPH_TABLET = "\uE32F"
var GLYPH_WATCH = "\uE334"
var GLYPH_PHONE = "\uE2C4"
var GLYPH_COMPUTER = "\uE31E"
var GLYPH_SPEAKER = "\uE32D"
var GLYPH_OTHER = "\uE337"

var GLYPH_BATTERY_UNKNOWN = "\uE1A6"
var GLYPH_BATTERY_FULL = "\uE1A5"
var GLYPH_CHARGING_90 = "\uE1A9"
var GLYPH_CHARGING_50 = "\uE1A4"
var GLYPH_CHARGING_20 = "\uE1A2"
var GLYPH_BATTERY_0 = "\uEBDC"
var GLYPH_BATTERY_1 = "\uF09C"
var GLYPH_BATTERY_2 = "\uF09D"
var GLYPH_BATTERY_3 = "\uF09E"
var GLYPH_BATTERY_4 = "\uF09F"
var GLYPH_BATTERY_5 = "\uF0A0"
var GLYPH_BATTERY_6 = "\uF0A1"

var KIND_ALIASES = {
  keyboard: "keyboard",
  keypad: "keyboard",
  mouse: "mouse",
  trackball: "mouse",
  headset: "headset",
  headphone: "headset",
  headphones: "headset",
  earbud: "headset",
  earbuds: "headset",
  gamepad: "gamepad",
  controller: "gamepad",
  tablet: "tablet",
  watch: "watch",
  phone: "phone",
  smartphone: "phone",
  computer: "computer",
  laptop: "computer",
  speaker: "speaker"
}

var SOURCE_LABELS = {
  bluetooth: "Bluetooth",
  sysfs: "2.4 GHz",
  upower: "System",
  razer: "Razer"
}

function clampPercent(value) {
  var n = Number(value)
  if (!isFinite(n)) return -1
  return Math.max(0, Math.min(100, Math.round(n)))
}

function kindFor(kind, name) {
  var key = String(kind || "").toLowerCase()
  if (KIND_ALIASES[key]) return KIND_ALIASES[key]
  var haystack = String(name || "").toLowerCase()
  for (var candidate in KIND_ALIASES) {
    if (candidate.length > 2 && haystack.indexOf(candidate) !== -1)
      return KIND_ALIASES[candidate]
  }
  return "other"
}

function glyphFor(kind) {
  switch (kind) {
    case "keyboard": return GLYPH_KEYBOARD
    case "mouse": return GLYPH_MOUSE
    case "headset": return GLYPH_HEADSET
    case "gamepad": return GLYPH_GAMEPAD
    case "tablet": return GLYPH_TABLET
    case "watch": return GLYPH_WATCH
    case "phone": return GLYPH_PHONE
    case "computer": return GLYPH_COMPUTER
    case "speaker": return GLYPH_SPEAKER
    default: return GLYPH_OTHER
  }
}

function ratio(value) {
  var p = clampPercent(value)
  return p < 0 ? 0 : p / 100
}

function batteryGlyph(percent, charging) {
  if (percent >= 100) return GLYPH_BATTERY_FULL
  if (charging) {
    if (percent >= 90) return GLYPH_CHARGING_90
    if (percent >= 50) return GLYPH_CHARGING_50
    return GLYPH_CHARGING_20
  }
  if (percent < 0) return GLYPH_BATTERY_UNKNOWN
  if (percent <= 0) return GLYPH_BATTERY_0
  if (percent <= 20) return GLYPH_BATTERY_1
  if (percent <= 35) return GLYPH_BATTERY_2
  if (percent <= 50) return GLYPH_BATTERY_3
  if (percent <= 65) return GLYPH_BATTERY_4
  if (percent <= 80) return GLYPH_BATTERY_5
  if (percent <= 95) return GLYPH_BATTERY_6
  return GLYPH_BATTERY_FULL
}

function detailLine(device) {
  var bits = []
  if (device.sourceLabel) bits.push(device.sourceLabel)
  if (device.charging) bits.push("Charging")
  else if (device.full) bits.push("Full")
  else if (device.state && device.state !== "" && device.state !== "Unknown")
    bits.push(device.state)
  else if (!device.connected) bits.push("Disconnected")
  else bits.push("Wireless")
  return bits.join(" \u00B7 ")
}

function normalize(raw) {
  if (!raw || typeof raw !== "object") return null
  var id = String(raw.id || "")
  if (id === "") return null
  var source = String(raw.source || "")
  var name = String(raw.name || "").trim() || "Unknown device"
  var percent = clampPercent(raw.percent)
  var kind = kindFor(raw.kind, name)
  return {
    id: id,
    source: source,
    sourceLabel: SOURCE_LABELS[source] || String(source).toUpperCase(),
    name: name,
    kind: kind,
    glyph: glyphFor(kind),
    address: String(raw.address || ""),
    model: String(raw.model || ""),
    connected: raw.connected === true,
    charging: raw.charging === true,
    percent: percent,
    full: percent >= 100,
    low: percent >= 0 && percent <= 20,
    state: String(raw.state || ""),
    detail: detailLine({
      sourceLabel: SOURCE_LABELS[source] || String(source).toUpperCase(),
      charging: raw.charging === true,
      full: percent >= 100,
      state: String(raw.state || ""),
      connected: raw.connected === true
    }),
    percentText: percent >= 0 ? percent + "%" : "\u2014"
  }
}

function parse(text) {
  var out = { ok: false, timestamp: "", sources: {}, devices: [] }
  var raw
  try {
    raw = JSON.parse(String(text || ""))
  } catch (e) {
    return out
  }
  if (!raw || typeof raw !== "object") return out
  out.ok = raw.ok === true
  out.timestamp = String(raw.timestamp || "")
  out.sources = raw.sources && typeof raw.sources === "object" ? raw.sources : {}
  var list = Array.isArray(raw.devices) ? raw.devices : []
  for (var i = 0; i < list.length; i++) {
    var device = normalize(list[i])
    if (device) out.devices.push(device)
  }
  out.devices.sort(function(a, b) {
    if (a.low !== b.low) return a.low ? -1 : 1
    return a.percent < b.percent ? -1 : (a.percent > b.percent ? 1 : 0)
  })
  return out
}

function summarize(devices) {
  var lowest = -1
  var worst = null
  var knownCount = 0
  var anyCharging = false
  var anyLow = false
  var anyFull = false
  var anyConnected = false
  var list = Array.isArray(devices) ? devices : []
  for (var i = 0; i < list.length; i++) {
    var d = list[i]
    if (d.charging) anyCharging = true
    if (d.low) anyLow = true
    if (d.full) anyFull = true
    if (d.connected) anyConnected = true
    if (d.percent < 0) continue
    knownCount++
    if (lowest < 0 || d.percent < lowest) {
      lowest = d.percent
      worst = d
    }
  }
  return {
    count: list.length,
    knownCount: knownCount,
    lowest: lowest,
    worst: worst,
    anyCharging: anyCharging,
    anyLow: anyLow,
    anyFull: anyFull,
    anyConnected: anyConnected
  }
}

function connectedGlyphs(devices) {
  var list = Array.isArray(devices) ? devices : []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var device = list[i]
    if (!device.connected) continue
    out.push({
      glyph: device.glyph,
      active: device.charging || device.low
    })
  }
  return out
}

function pillIcon(summary) {
  if (!summary || summary.knownCount === 0) return GLYPH_BATTERY_UNKNOWN
  return batteryGlyph(summary.lowest, summary.anyCharging)
}

function pillTooltip(summary, devices) {
  var list = Array.isArray(devices) ? devices : []
  if (list.length === 0) return "No wireless device batteries found"
  var parts = []
  for (var i = 0; i < list.length; i++) {
    var d = list[i]
    var label = d.name + " " + d.percentText
    if (d.charging) label += " \u00B7 Charging"
    else if (d.full) label += " \u00B7 Full"
    parts.push(label)
  }
  return parts.join("  |  ")
}
