// Data-only command builders for the notification file queue. The service
// owns when commands run; this module keeps shell argument construction and
// durable file semantics separate from notification lifecycle orchestration.

// Image copies are atomic and verified. A copy that cannot be proven to have
// produced a non-empty file within the bound (missing source, unreadable,
// over-bound, or a short read) fails the whole persist job before the JSON is
// written, so a dangling file:// path can never be recorded. The caller falls
// back to an honest retained theme name/default on failure.
var COPY_IMAGES_SCRIPT =
    "failed=0\n" +
    "while (( $# >= 2 )); do\n" +
    "  source=\"$1\" target=\"$2\" tmp=\"$2.tmp.$$\"\n" +
    "  copied=0\n" +
    "  if [[ -f \"$source\" ]] && /usr/bin/timeout --foreground --kill-after=1s 5s /usr/bin/head -c 5242881 -- \"$source\" > \"$tmp\"; then\n" +
    "    if ! size=$(/usr/bin/stat -c%s -- \"$tmp\"); then /usr/bin/printf '%s\\n' '[NOTIFICATIONS] image_copy_size_failed' >&2; size=0; fi\n" +
    "    if [[ \"$size\" =~ ^[0-9]+$ ]] && (( size > 0 && size <= 5242880 )); then /usr/bin/mv -f -- \"$tmp\" \"$target\"; copied=1; fi\n" +
    "  fi\n" +
    "  if (( copied == 0 )); then /usr/bin/rm -f -- \"$tmp\"; failed=1; fi\n" +
    "  shift 2\n" +
    "done\n" +
    "(( failed == 0 ))\n"

function withFileTimeout(script, args) {
    return ["/usr/bin/timeout", "--foreground", "--kill-after=1s", "5s", "/usr/bin/bash", "-c", script].concat(args)
}

function appendCopies(command, copies) {
    for (var i = 0; i < (copies || []).length; i++) {
        command.push(copies[i].from, copies[i].to)
    }
    return command
}

function persistPopup(persistable, popupStateDir, imagesDir, fileName) {
    var script =
        "set -Eeuo pipefail\n" +
        "dir=\"$1\" images=\"$2\" json=\"$3\" name=\"$4\"\n" +
        "/usr/bin/mkdir -p -- \"$dir\" \"$images\"\n" +
        "shift 4\n" +
        COPY_IMAGES_SCRIPT +
        "tmp=\"$dir/.$name.tmp.$$\"\n" +
        "trap '/usr/bin/rm -f -- \"$tmp\"' EXIT\n" +
        "/usr/bin/printf '%s\\n' \"$json\" > \"$tmp\"\n" +
        "/usr/bin/mv -f -- \"$tmp\" \"$dir/$name\"\n" +
        "trap - EXIT\n"
    var command = withFileTimeout(script, [
        "--",
        popupStateDir,
        imagesDir,
        persistable.json,
        fileName
    ])
    return appendCopies(command, persistable.copies)
}

function sweepImages(popupStateDir, imagesDir) {
    var script =
        "set -Eeuo pipefail\n" +
        "live=\"$1\" imgs=\"$2\"\n" +
        "shopt -s nullglob\n" +
        "for tmp in \"$live\"/.*.tmp.*; do [[ -e \"$tmp\" ]] || continue; /usr/bin/rm -f -- \"$tmp\"; done\n" +
        "for image in \"$imgs\"/*; do\n" +
        "  [[ -e \"$image\" ]] || continue\n" +
        "  name=\"${image##*/}\"\n" +
        // Image files share the notification stem ("<timestamp>-<id>-<role>").
        // The resolved icon is written as "<stem>-appIcon", so stripping the
        // final -role segment recovers the stem and keeps the icon while its
        // popup JSON lives.
        "  stem=\"${name%-*}\"\n" +
        "  [[ -e \"$live/$stem.json\" ]] || /usr/bin/rm -f -- \"$image\"\n" +
        "done\n"
    return withFileTimeout(script, ["--", popupStateDir, imagesDir])
}

function deletePopup(popupStateDir, imagesDir, fileName) {
    var script =
        "set -Eeuo pipefail\n" +
        "/usr/bin/rm -f -- \"$1/$2\" \"$3/${2%.json}\"-*\n"
    return withFileTimeout(script, ["--", popupStateDir, fileName, imagesDir])
}

function readDirectory(directory) {
    var script =
        "set -Eeuo pipefail\n" +
        "directory=\"$1\"\n" +
        "shopt -s nullglob\n" +
        "files=(\"$directory\"/*.json)\n" +
        "(( ${#files[@]} == 0 )) && exit 0\n" +
        "/usr/bin/awk '1' \"${files[@]}\"\n"
    return withFileTimeout(script, ["--", directory])
}

if (typeof module !== "undefined") {
    module.exports = {
        persistPopup: persistPopup,
        sweepImages: sweepImages,
        deletePopup: deletePopup,
        readDirectory: readDirectory
    }
}
