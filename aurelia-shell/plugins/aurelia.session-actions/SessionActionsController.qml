import QtQuick
import "Model.js" as Model

// Non-visual state machine for the session-actions panel. Keeping request,
// confirmation, and execution policy outside the window makes the safety
// boundary testable even when a headless environment cannot create a
// PanelWindow.
QtObject {
    id: controller

    property var owner: null

    function resetSelection() {
        if (!controller.owner) return
        controller.owner.actionIndex = 0
        controller.owner.cursorActive = false
    }

    function open(payloadJson) {
        if (!controller.owner) return "not-ready"
        controller.owner.confirmAction = ""
        controller.owner.actionError = ""
        controller.resetSelection()
        controller.owner.shown = true
        return "ok"
    }

    function close() {
        if (!controller.owner) return "not-ready"
        controller.owner.confirmAction = ""
        controller.resetSelection()
        controller.owner.shown = false
        return "ok"
    }

    function requestAction(action) {
        if (!controller.owner) return "not-ready"
        var requested = String(action || "")
        if (!Model.isKnownAction(requested)) return "invalid"
        if (!Model.requiresConfirmation(requested)) {
            console.error("[SESSION-ACTIONS] action_blocked reason=confirmation_policy kind=" + requested)
            return "confirmation-required"
        }
        controller.owner.confirmAction = requested
        controller.resetSelection()
        return "confirm"
    }

    function runAction(action) {
        // Compatibility entry point: callers may request an action, but no
        // caller may use this method to bypass the confirmation state.
        return controller.requestAction(action)
    }

    function executeConfirmedAction(action) {
        if (!controller.owner) return "not-ready"
        var requested = String(action || "")
        var command = Model.commandFor(requested)
        if (command.length === 0) return "invalid"
        if (controller.owner.confirmAction !== requested ||
            !Model.requiresConfirmation(requested)) {
            console.error("[SESSION-ACTIONS] action_blocked reason=confirmation_required kind=" + requested)
            return "confirmation-required"
        }
        if (!controller.owner.runtime || typeof controller.owner.runtime.runCommand !== "function")
            return "not-ready"
        var result = controller.owner.runtime.runCommand(command, requested)
        if (result === "ok" || result === "pending") controller.close()
        return result
    }

    function confirmPendingAction() {
        if (!controller.owner || !Model.requiresConfirmation(controller.owner.confirmAction)) return "invalid"
        return controller.executeConfirmedAction(controller.owner.confirmAction)
    }

    function cancelPendingAction() {
        if (!controller.owner) return "not-ready"
        controller.owner.confirmAction = ""
        controller.resetSelection()
        return "ok"
    }

    function moveSelection(delta) {
        if (!controller.owner) return
        var rows = controller.owner.visibleActionRows
        if (!Array.isArray(rows) || rows.length === 0) return
        controller.owner.actionIndex = Math.max(0, Math.min(
            rows.length - 1, controller.owner.actionIndex + delta))
        controller.owner.cursorActive = true
    }

    function activateSelection() {
        if (!controller.owner) return "not-ready"
        var rows = controller.owner.visibleActionRows
        if (!Array.isArray(rows) || controller.owner.actionIndex < 0 ||
            controller.owner.actionIndex >= rows.length) return "invalid"
        var selected = rows[controller.owner.actionIndex]
        if (controller.owner.confirmAction !== "")
            return selected.id === "confirm"
                ? controller.confirmPendingAction()
                : controller.cancelPendingAction()
        return controller.requestAction(selected.id)
    }
}
