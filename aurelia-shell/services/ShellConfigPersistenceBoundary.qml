import QtQuick
import Quickshell
import Quickshell.Io

// Owns the two external operations attached to ShellConfig persistence:
// recoverable migration backup and post-save permission hardening. Keeping
// them outside the state model prevents the config owner from accumulating
// unrelated Process lifecycle code.
Item {
    id: boundary

    property var owner: null

    function startMigrationBackup() {
        if (!migrationBackupProcess.running) migrationBackupProcess.running = true
    }

    function securePermissions() {
        if (!securePermissionProcess.running) securePermissionProcess.running = true
    }

    Process {
        id: migrationBackupProcess
        command: boundary.owner ? [
            "/usr/bin/bash",
            "-c",
            "set -Eeuo pipefail; source_path=\"$1\"; backup_path=\"$2\"; " +
            "[[ -f \"$source_path\" && ! -L \"$source_path\" ]] || exit 2; " +
            "if [[ -e \"$backup_path\" || -L \"$backup_path\" ]]; then " +
            "  [[ -f \"$backup_path\" && ! -L \"$backup_path\" ]] || exit 3; " +
            "  exit 0; " +
            "fi; cp -- \"$source_path\" \"$backup_path\"",
            "aurelia-shell-config-migration-backup",
            boundary.owner.configPath,
            boundary.owner.migrationBackupPath
        ] : []

        onExited: function(code) {
            if (!boundary.owner) return
            if (code !== 0) {
                boundary.owner.migrationInProgress = false
                boundary.owner.migrationResult = "backup-failed"
                boundary.owner.lastError = "Could not create the recoverable Aurelia shell config migration backup."
                return
            }
            boundary.owner.configFile.setText(boundary.owner.migrationText)
        }
    }

    Process {
        id: securePermissionProcess
        command: boundary.owner ? [
            "/usr/bin/bash",
            "-c",
            "set -Eeuo pipefail; target=\"$1\"; " +
            "[[ -f \"$target\" && ! -L \"$target\" ]] || exit 2; " +
            "chmod 600 -- \"$target\"",
            "aurelia-shell-config-secure-permissions",
            boundary.owner.configPath
        ] : []

        onExited: function(code) {
            if (!boundary.owner) return
            if (code !== 0) {
                boundary.owner.lastSaveOk = false
                boundary.owner.lastError = "Could not secure Aurelia shell config permissions."
            }
            if (boundary.owner.migrationInProgress)
                boundary.owner.finishMigrationSave(code === 0)
        }
    }
}
