// Pure tray icon policy for the bar. Symbolic artwork is recoloured to the bar
// foreground; multi-colour brand/application art is the single documented
// exception and keeps its original palette. Keeping the decision in one pure
// module lets the bar widget and its isolated tests share the exact rule.

function isSymbolicIcon(icon) {
    var name = String(icon || "").split("?")[0]
    return name.slice(-9) === "-symbolic"
}

function preserveColors(icon) {
    return !isSymbolicIcon(icon)
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        isSymbolicIcon: isSymbolicIcon,
        preserveColors: preserveColors
    }
}
