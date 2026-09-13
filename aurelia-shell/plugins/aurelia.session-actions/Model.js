var actionDefinitions = [
    {id: "lock", label: "Lock", detail: "Lock this session", glyph: "󰍁",
        command: ["/usr/bin/loginctl", "lock-session"], confirm: true},
    {id: "logout", label: "Log out", detail: "End this session", glyph: "󰍃",
        command: ["/usr/bin/hyprctl", "dispatch", "exit"], confirm: true},
    {id: "suspend", label: "Suspend", detail: "Sleep until activity", glyph: "󰤄",
        command: ["/usr/bin/systemctl", "suspend"], confirm: true},
    {id: "reboot", label: "Restart", detail: "Reboot the workstation", glyph: "󰜉",
        command: ["/usr/bin/systemctl", "reboot"], confirm: true},
    {id: "shutdown", label: "Power off", detail: "Shut down the workstation", glyph: "󰐥",
        command: ["/usr/bin/systemctl", "poweroff"], confirm: true}
]

function cloneAction(action) {
    return {
        id: action.id,
        label: action.label,
        detail: action.detail,
        glyph: action.glyph,
        confirm: action.confirm,
        command: action.command.slice()
    }
}

function actionRows() {
    var result = []
    for (var i = 0; i < actionDefinitions.length; i++) result.push(cloneAction(actionDefinitions[i]))
    return result
}

function definitionFor(id) {
    var requested = String(id || "")
    for (var i = 0; i < actionDefinitions.length; i++) {
        if (actionDefinitions[i].id === requested) return actionDefinitions[i]
    }
    return null
}

function isKnownAction(id) {
    return definitionFor(id) !== null
}

function requiresConfirmation(id) {
    var definition = definitionFor(id)
    return !!definition && definition.confirm === true
}

function commandFor(id) {
    var definition = definitionFor(id)
    return definition ? definition.command.slice() : []
}

function confirmationTitle(id) {
    var definition = definitionFor(id)
    if (!definition || definition.confirm !== true) return "Confirm session action?"
    var titles = {
        lock: "Lock this session?",
        logout: "Log out of this session?",
        suspend: "Suspend this workstation?",
        reboot: "Restart computer?",
        shutdown: "Power off computer?"
    }
    return titles[definition.id] || "Confirm session action?"
}

function confirmationDetail(id) {
    var definition = definitionFor(id)
    if (!definition || definition.confirm !== true) return ""
    return "Choose Confirm to continue or Cancel to keep this session running."
}

function confirmationRows(id) {
    var definition = definitionFor(id)
    if (!definition || definition.confirm !== true) return []
    return [
        {id: "confirm", label: "Confirm", detail: "Continue with this action", glyph: "󰄬", confirm: false},
        {id: "cancel", label: "Cancel", detail: "Keep the session running", glyph: "󰅖", confirm: false}
    ]
}

if (typeof module !== "undefined") {
    module.exports = {
        actionRows: actionRows,
        isKnownAction: isKnownAction,
        requiresConfirmation: requiresConfirmation,
        commandFor: commandFor,
        confirmationTitle: confirmationTitle,
        confirmationDetail: confirmationDetail,
        confirmationRows: confirmationRows
    }
}
