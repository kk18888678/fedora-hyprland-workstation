// Pure workspace activation decision used by the bar widget. Live Hyprland
// objects are preferred; only empty baseline workspaces use a structured
// dispatch string.

function validWorkspaceId(value) {
    var id = Number(value)
    return isFinite(id) && Math.floor(id) === id && id >= 1 && id <= 10
}

function actionFor(workspace, id, usingLua) {
    if (!validWorkspaceId(id)) return {ok: false, reason: "invalid-workspace"}
    var workspaceId = String(Number(id))
    if (workspace && typeof workspace.activate === "function")
        return {ok: true, mode: "object", id: workspaceId}
    return {
        ok: true,
        mode: "dispatch",
        id: workspaceId,
        command: usingLua === true
            ? "hl.dsp.focus({ workspace = \"" + workspaceId + "\" })"
            : "workspace " + workspaceId
    }
}

var AureliaWorkspaceActionModel = {
    validWorkspaceId: validWorkspaceId,
    actionFor: actionFor
}

if (typeof module !== "undefined" && module.exports) module.exports = AureliaWorkspaceActionModel
