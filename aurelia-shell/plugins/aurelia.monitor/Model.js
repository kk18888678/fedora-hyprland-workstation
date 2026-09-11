function clampBrightness(value) {
  var number = Number(value)
  if (!isFinite(number)) return 1
  return Math.max(1, Math.min(100, Math.round(number)))
}

function normalizeScale(scale) {
  var number = parseFloat(String(scale || ""))
  if (!isFinite(number)) return ""
  return String(Math.round(number * 100) / 100)
}

function gcd(a, b) {
  while (b) {
    var remainder = a % b
    a = b
    b = remainder
  }
  return a
}

// Hyprland accepts fractional scales only when the resulting logical mode is
// integral. Keep the reference's 1/120 rule local to the display model so the
// UI and the backend can use the same requested presets without guessing.
function cleanScale(scale, width, height) {
  var requested = Number(scale)
  var modeWidth = Number(width)
  var modeHeight = Number(height)
  if (!isFinite(requested) || !isFinite(modeWidth) || !isFinite(modeHeight) ||
      requested <= 0 || modeWidth <= 0 || modeHeight <= 0) return ""

  var divisor = gcd(Math.round(modeWidth * 120), Math.round(modeHeight * 120))
  if (divisor <= 0) return ""

  var scaleUnits = Math.max(1, Math.round(requested * 120))
  if (scaleUnits > divisor) scaleUnits = divisor
  while (divisor % scaleUnits !== 0) scaleUnits++
  return normalizeScale(scaleUnits / 120)
}

function matchingScaleIndex(scales, currentScale, width, height) {
  var current = Number(currentScale)
  if (!Array.isArray(scales) || !isFinite(current)) return -1

  var bestIndex = -1
  var bestDistance = Infinity
  var normalizedCurrent = normalizeScale(current)
  for (var i = 0; i < scales.length; i++) {
    if (cleanScale(scales[i], width, height) !== normalizedCurrent) continue

    var distance = Math.abs(Number(scales[i]) - current)
    if (distance < bestDistance) {
      bestIndex = i
      bestDistance = distance
    }
  }
  return bestIndex
}

function availableScales(scales, width, height) {
  if (!Array.isArray(scales)) return []
  if (Number(width) <= 0 || Number(height) <= 0) return scales.slice()

  var byEffectiveScale = {}
  for (var i = 0; i < scales.length; i++) {
    var requested = Number(scales[i])
    var effectiveText = cleanScale(requested, width, height)
    var effective = Number(effectiveText)
    if (!isFinite(requested) || !isFinite(effective) || effectiveText === "") continue

    var key = normalizeScale(effective)
    var existing = byEffectiveScale[key]
    var distance = Math.abs(requested - effective)
    if (!existing || distance < existing.distance) {
      byEffectiveScale[key] = {
        value: String(scales[i]),
        index: i,
        distance: distance
      }
    }
  }

  return Object.keys(byEffectiveScale)
    .map(function(key) { return byEffectiveScale[key] })
    .sort(function(left, right) { return left.index - right.index })
    .map(function(candidate) { return candidate.value })
}

function brightnessName(percent) {
  var value = Math.round(percent)
  if (value >= 95) return "Sun blast"
  if (value >= 80) return "Solar flare"
  if (value >= 65) return "Golden hour"
  if (value >= 45) return "Even day"
  if (value >= 30) return "Soft glow"
  if (value >= 20) return "Lamp light"
  if (value >= 10) return "Candlelit"
  return "Night owl"
}

function parseDisplays(raw) {
  var displays = []
  try {
    displays = raw ? JSON.parse(String(raw)) : []
  } catch (error) {
    displays = []
  }
  if (!Array.isArray(displays)) displays = []

  var enabledDisplayCount = 0
  for (var i = 0; i < displays.length; i++) {
    if (displays[i] && displays[i].enabled === true) enabledDisplayCount++
  }

  return {
    displays: displays,
    enabledDisplayCount: enabledDisplayCount
  }
}

function normalizedMode(value) {
  var text = String(value || "").trim()
  if (text.slice(-2).toLowerCase() === "hz") text = text.slice(0, -2)
  var match = text.match(/^([0-9]+)x([0-9]+)@([0-9]+(?:\.[0-9]+)?)$/)
  if (!match) return ""
  return match[1] + "x" + match[2] + "@" + normalizeScale(Number(match[3]))
}

function resolutionModes(display) {
  if (!display) return []
  var values = Array.isArray(display.availableModes) ? display.availableModes : []
  var result = []
  var seen = {}

  for (var i = 0; i < values.length; i++) {
    var mode = normalizedMode(values[i])
    if (mode === "" || seen[mode]) continue
    var match = mode.match(/^([0-9]+)x([0-9]+)@([0-9]+(?:\.[0-9]+)?)$/)
    seen[mode] = true
    result.push({
      mode: mode,
      width: Number(match[1]),
      height: Number(match[2]),
      refresh: Number(match[3]),
      label: match[1] + "×" + match[2] + " @ " + match[3] + " Hz"
    })
  }

  var current = currentMode(display)
  if (current !== "" && !seen[current]) {
    var currentMatch = current.match(/^([0-9]+)x([0-9]+)@([0-9]+(?:\.[0-9]+)?)$/)
    if (currentMatch) {
      result.unshift({
        mode: current,
        width: Number(currentMatch[1]),
        height: Number(currentMatch[2]),
        refresh: Number(currentMatch[3]),
        label: currentMatch[1] + "×" + currentMatch[2] + " @ " + currentMatch[3] + " Hz"
      })
    }
  }
  return result
}

function currentMode(display) {
  if (!display) return ""
  var width = Number(display.width)
  var height = Number(display.height)
  var refresh = Number(display.refreshRate)
  if (!isFinite(width) || !isFinite(height) || !isFinite(refresh) ||
      width <= 0 || height <= 0 || refresh <= 0) return ""
  return width + "x" + height + "@" + normalizeScale(refresh)
}

if (typeof module !== "undefined") {
  module.exports = {
    clampBrightness: clampBrightness,
    normalizeScale: normalizeScale,
    cleanScale: cleanScale,
    matchingScaleIndex: matchingScaleIndex,
    availableScales: availableScales,
    brightnessName: brightnessName,
    parseDisplays: parseDisplays,
    normalizedMode: normalizedMode,
    resolutionModes: resolutionModes,
    currentMode: currentMode
  }
}
