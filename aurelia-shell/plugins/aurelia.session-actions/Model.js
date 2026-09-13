var actionDefinitions = [
    {id: "lock", label: "Lock", detail: "Lock this session", glyph: "󰍁",
        command: ["/usr/bin/loginctl", "lock-session"], confirm: false},
    {id: "logout", label: "Log out", detail: "End this session", glyph: "󰍃",
        command: ["/usr/bin/hyprctl", "dispatch", "exit"], confirm: false},
    {id: "suspend", label: "Suspend", detail: "Sleep until activity", glyph: "󰤄",
        command: ["/usr/bin/systemctl", "suspend"], confirm: false},
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
        confirmationRows: confirmationRows
    }
}
