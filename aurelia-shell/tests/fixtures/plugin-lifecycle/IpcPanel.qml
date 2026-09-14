import QtQuick
import Quickshell.Io

// A real dynamic plugin IPC owner used to prove reload destruction ordering.
Item {
    IpcHandler {
        target: "fixture.reload-ipc"
        function ping(): string { return "ok" }
    }
}
