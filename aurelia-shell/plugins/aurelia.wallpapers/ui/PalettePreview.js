// Pure decision helper for the palette editor's single-process preview
// pipeline.
//
// The editor keeps at most one `theme preview` process in flight. A newer
// request that arrives while one is running is deferred and replayed once the
// process exits; it is never promoted by terminating the running process,
// because the resulting SIGTERM exit raced the request-serial guard and
// surfaced a spurious "Color extraction failed" error.

// How an incoming preview request should be handled:
//   running  - a preview process is currently in flight
//   applying - a theme mutation is in progress
// Returns "ignore" (drop the request), "defer" (replay after the process
// exits), or "start" (launch the process now).
function requestAction(running, applying) {
    if (applying) return "ignore"
    if (running) return "defer"
    return "start"
}

// Whether a completed preview should be followed by the deferred request.
function shouldReplay(pending) {
    return pending === true
}

// Resolve the editor error text from a finished preview process. A success
// clears any previous error. A failure surfaces the command's own stderr so
// the user sees the specific cause, with a generic fallback only when the
// command emitted no diagnostic at all.
function previewError(code, stderr) {
    if (code === 0) return ""
    var detail = String(stderr || "").trim()
    return detail !== "" ? detail : "Color extraction failed."
}

if (typeof module !== "undefined") {
    module.exports = {
        requestAction: requestAction,
        shouldReplay: shouldReplay,
        previewError: previewError
    }
}
