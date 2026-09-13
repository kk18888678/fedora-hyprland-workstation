function finiteNumber(value, fallback) {
  var number = Number(value)
  return isFinite(number) ? number : fallback
}

function clampIndex(index, length) {
  var count = Math.floor(finiteNumber(length, 0))
  if (count <= 0) return 0
  var value = Math.floor(finiteNumber(index, 0))
  return Math.max(0, Math.min(count - 1, value))
}

function selectProfileIndex(index, delta, profiles) {
  var values = Array.isArray(profiles) ? profiles : []
  if (values.length === 0) return 0
  return clampIndex(finiteNumber(index, 0) + finiteNumber(delta, 0), values.length)
}

function parseKeyValue(raw) {
  var next = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var idx = lines[i].indexOf("\t")
    if (idx <= 0) continue
    var key = lines[i].substring(0, idx).trim()
    if (!/^[A-Za-z][A-Za-z0-9_.-]*$/.test(key)) continue
    next[key] = lines[i].substring(idx + 1).trim()
  }
  return next
}

function validProfileName(value) {
  return /^[A-Za-z0-9][A-Za-z0-9-]*$/.test(String(value || ""))
}

function parseProfiles(raw, previousIndex) {
  var lines = String(raw || "").split("\n")
  var list = []
  var active = ""
  var seen = {}

  function add(name, isActive) {
    var profile = String(name || "").trim()
    if (!validProfileName(profile) || seen[profile]) return
    seen[profile] = true
    list.push(profile)
    if (isActive) active = profile
  }

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    var trimmed = line.trim()
    if (!trimmed) continue
    if (line.indexOf("\t") !== -1) {
      var parts = line.split("\t")
      add(parts[0], parts[1] === "1")
      continue
    }
    var human = trimmed.match(/^(\*)?\s*([A-Za-z0-9][A-Za-z0-9-]*):\s*$/)
    if (human) add(human[2], !!human[1])
  }

  return {
    profiles: list,
    activeProfile: active,
    profileIndex: clampIndex(previousIndex || 0, list.length)
  }
}

function profileIcon(name) {
  if (name === "power-saver") return "󰌪"
  if (name === "balanced") return "󰊚"
  if (name === "performance") return "󰓅"
  return "󰂄"
}

function batteryFraction(device) {
  if (!device || device.isPresent !== true) return 0
  var percentage = finiteNumber(device.percentage, 0)
  return Math.max(0, Math.min(1, percentage))
}

function chargeThresholdActive(device, onBattery, states) {
  var d = device || {}
  var s = states || {}
  if (!(d && d.isPresent === true && !onBattery)) return false

  var fraction = batteryFraction(d)
  if (d.state === s.Discharging) return false
  if (d.state === s.PendingCharge) return true
  if (d.state === s.FullyCharged && fraction < 0.99) return true
  if (d.state !== s.Charging || fraction >= 0.99) return false

  return finiteNumber(d.changeRate, 0) <= 0.2 || finiteNumber(d.timeToFull, 0) >= 8 * 60 * 60
}

function batteryIcon(device, onBattery, states) {
  var d = device || {}
  if (d.isPresent !== true) return ""

  var chargingIcons = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
  var defaultIcons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
  var index = Math.max(0, Math.min(9, Math.floor(batteryFraction(d) * 10)))
  var threshold = chargeThresholdActive(d, onBattery, states)

  if (threshold) return defaultIcons[index]
  if (d.state === states.FullyCharged) return "󰂅"
  if (!onBattery) return chargingIcons[index]
  return defaultIcons[index]
}

function modeLabel(device, onBattery, states) {
  var d = device || {}
  if (d.isPresent !== true) return ""
  if (chargeThresholdActive(d, onBattery, states)) return "Threshold"
  if (onBattery) return "On battery"
  if (batteryFraction(d) >= 1 || d.state === states.FullyCharged) return "Fully charged"
  return "Charging"
}

function formatDuration(seconds) {
  var total = Math.floor(finiteNumber(seconds, 0))
  if (total <= 0) return ""
  var hours = Math.floor(total / 3600)
  var minutes = Math.floor((total % 3600) / 60)
  if (hours > 0) return hours + "h" + (minutes > 0 ? " " + minutes + "m" : "")
  return minutes > 0 ? minutes + "m" : "<1m"
}

function percentageText(device) {
  if (!device || device.isPresent !== true) return "—"
  return Math.round(batteryFraction(device) * 100) + "%"
}

function energyText(value, suffix) {
  var number = finiteNumber(value, 0)
  if (number <= 0) return "—"
  return (Math.round(number * 10) / 10) + String(suffix || "")
}

function batterySnapshot(device, onBattery, states) {
  var d = device || {}
  if (d.isPresent !== true) return {}
  var snapshot = {
    percentage: percentageText(d),
    state: modeLabel(d, onBattery, states),
    size: energyText(d.energyCapacity || d.energyFull, "Wh"),
    rate: energyText(d.changeRate || d.energyRate, "W"),
    cycles: d.cycleCount !== undefined ? String(d.cycleCount) : "",
    threshold: d.chargeThreshold !== undefined ? String(d.chargeThreshold) : ""
  }
  var duration = onBattery ? d.timeToEmpty : d.timeToFull
  snapshot.time = formatDuration(duration)
  return snapshot
}

function parseSystemStats(raw) {
  var text = String(raw || "")
  var next = {}
  var load = text.match(/load average[s]?:\s*([0-9.]+)/i)
  if (load) next.load = load[1]
  var memory = text.match(/Mem:\s+([0-9.]+[A-Za-z]*)\s+([0-9.]+[A-Za-z]*)\s+([0-9.]+)/)
  if (memory) next.memory = memory[3] + " used / " + memory[1]
  return next
}

if (typeof module !== "undefined") {
  module.exports = {
    clampIndex: clampIndex,
    selectProfileIndex: selectProfileIndex,
    parseKeyValue: parseKeyValue,
    parseProfiles: parseProfiles,
    profileIcon: profileIcon,
    batteryFraction: batteryFraction,
    chargeThresholdActive: chargeThresholdActive,
    batteryIcon: batteryIcon,
    modeLabel: modeLabel,
    formatDuration: formatDuration,
    percentageText: percentageText,
    energyText: energyText,
    batterySnapshot: batterySnapshot,
    parseSystemStats: parseSystemStats
  }
}
