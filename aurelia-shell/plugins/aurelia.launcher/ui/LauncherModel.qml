import QtQuick
import Quickshell.Io

// Application discovery and launch state are separate from LauncherPanel UI.
Item {
    id: root

    property string backendBin: ""
    property var processEnvironment: ({})
    property var applications: []
    property string query: ""
    property int selectedIndex: 0
    property bool loading: false
    property string errorMessage: ""

    readonly property var filteredApplications: {
        var needle = String(root.query || "").trim().toLowerCase()
        if (needle === "") return root.applications
        var result = []
        for (var i = 0; i < root.applications.length; i++) {
            var app = root.applications[i]
            var haystack = [app.name, app.generic_name, app.comment, app.desktop_id, app.categories]
                .map(function(value) { return String(value || "").toLowerCase() })
                .join(" ")
            if (haystack.indexOf(needle) !== -1) result.push(app)
        }
        return result
    }

    readonly property var selectedApplication: filteredApplications.length > 0 && selectedIndex >= 0 && selectedIndex < filteredApplications.length
        ? filteredApplications[selectedIndex]
        : null

    signal launchStarted(string desktopId)
    signal launchFinished(bool success, string message)

    function reload() {
        if (appsProcess.running) return
        loading = true
        errorMessage = ""
        appsProcess.command = [root.backendBin, "apps"]
        appsProcess.running = true
    }

    function moveSelection(delta) {
        if (filteredApplications.length === 0) {
            selectedIndex = 0
            return
        }
        selectedIndex = (selectedIndex + delta + filteredApplications.length) % filteredApplications.length
    }

    function launchSelected() {
        if (!selectedApplication || launchProcess.running) return false
        var desktopId = String(selectedApplication.desktop_id || "")
        if (!/^[A-Za-z0-9][A-Za-z0-9_.-]*\.desktop$/.test(desktopId)) {
            errorMessage = "Application identity is invalid."
            return false
        }
        // Launch through UWSM so the application is placed in the managed
        // graphical app scope with the imported Wayland/D-Bus session state.
        // The second `--` is gtk-launch's option separator; desktopId remains
        // a validated single argv element and is never shell-interpreted.
        launchProcess.command = ["/usr/bin/uwsm-app", "--", "/usr/bin/gtk-launch", "--", desktopId]
        console.info("[LAUNCHER] launch.begin desktop_id=" + desktopId)
        launchProcess.running = true
        launchStarted(desktopId)
        return true
    }

    onQueryChanged: selectedIndex = 0

    Process {
        id: appsProcess
        command: []
        environment: root.processEnvironment
        clearEnvironment: false
        stdout: StdioCollector { id: appsStdout }
        stderr: StdioCollector { id: appsStderr }

        onExited: function(code) {
            loading = false
            if (code !== 0) {
                applications = []
                errorMessage = appsStderr.text.trim() || "Application discovery failed."
                return
            }
            try {
                var parsed = JSON.parse(appsStdout.text || "[]")
                applications = Array.isArray(parsed) ? parsed : []
            } catch (error) {
                applications = []
                errorMessage = "Application discovery returned invalid data."
            }
        }
    }

    Process {
        id: launchProcess
        command: []
        environment: root.processEnvironment
        clearEnvironment: false
        stderr: StdioCollector { id: launchStderr }

        onExited: function(code) {
            if (code !== 0) {
                var message = launchStderr.text.trim() || "Application launch failed."
                console.warn("[LAUNCHER] launch.failed code=" + code + " error=" + message)
                root.errorMessage = message
                root.launchFinished(false, message)
            } else {
                console.info("[LAUNCHER] launch.accepted")
                root.launchFinished(true, "")
            }
        }
    }
}
