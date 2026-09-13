// Pure Bluetooth capability-probe contract. The command targets the
// org.freedesktop.DBus.ObjectManager interface explicitly; busctl's normal
// human-readable output lists its members, not the full interface name.

function hasObjectManagerMember(output) {
    return String(output || "").indexOf(".GetManagedObjects") !== -1
}

function succeeded(exitCode, output) {
    return Number(exitCode) === 0 && hasObjectManagerMember(output)
}

function bounded(value, limit) {
    var text = String(value || "").replace(/[\r\n\t]+/g, " ").trim()
    var max = Number(limit)
    if (!isFinite(max) || max < 1) max = 512
    return text.length > max ? text.substring(0, max) + "..." : text
}

function failureDetail(exitCode, stdout, stderr) {
    var error = bounded(stderr, 384)
    var output = bounded(stdout, 384)
    var detail = error !== "" ? error : (output !== "" ? output : "no diagnostic output")
    return "exit_code=" + String(Number(exitCode)) + " detail=" + detail
}

var AureliaBluetoothProbe = {
    hasObjectManagerMember: hasObjectManagerMember,
    succeeded: succeeded,
    failureDetail: failureDetail
}

if (typeof module !== "undefined" && module.exports) module.exports = AureliaBluetoothProbe
