// Low-level local path/URL primitives used only by PluginSourceResolver and
// approved local-resource consumers. Plugin identity, root ownership, and
// entry-point policy belong to PluginSourceResolver/PluginRegistry.

function text(value) {
    return String(value === undefined || value === null ? "" : value)
}

function hasUnsafeCharacters(value) {
    return /[\x00-\x1f\x7f]/.test(text(value))
}

function pathFromUrl(value) {
    var source = text(value)
    if (source.indexOf("file://") !== 0) return source

    var encodedPath = source.substring(7)
    if (encodedPath.indexOf("/") !== 0) {
        if (encodedPath.indexOf("localhost/") !== 0) return ""
        encodedPath = "/" + encodedPath.substring(10)
    }
    if (hasUnsafeCharacters(encodedPath)) return ""
    try {
        return decodeURIComponent(encodedPath)
    } catch (error) {
        if (typeof console !== "undefined" && console.error)
            console.error("[SOURCE] path_decode_failed")
        return ""
    }
}

function isAbsolutePath(value, allowRoot) {
    var path = pathFromUrl(value)
    return path.charAt(0) === "/" && (allowRoot === true || path !== "/") &&
        path.indexOf("\\") === -1 && !hasUnsafeCharacters(path)
}

function isSafeRelativePath(value) {
    var path = text(value)
    return path !== "" && path.charAt(0) !== "/" && path.indexOf("..") === -1 &&
        path.indexOf("\\") === -1 && path.indexOf(":") === -1 &&
        !hasUnsafeCharacters(path)
}

function fileUrl(value) {
    var path = pathFromUrl(value)
    if (!isAbsolutePath(path, true)) return ""

    var parts = path.split("/")
    try {
        for (var i = 0; i < parts.length; i++) parts[i] = encodeURIComponent(parts[i])
    } catch (error) {
        if (typeof console !== "undefined" && console.error)
            console.error("[SOURCE] path_encode_failed")
        return ""
    }
    return "file://" + parts.join("/")
}

function isDescendant(path, root) {
    var candidate = pathFromUrl(path)
    var parent = pathFromUrl(root).replace(/\/+$/, "")
    return isAbsolutePath(candidate, true) && isAbsolutePath(parent, true) &&
        (candidate === parent || candidate.indexOf(parent + "/") === 0)
}

function resolvePath(root, relativePath) {
    var rootPath = pathFromUrl(root).replace(/\/+$/, "")
    if (!isAbsolutePath(rootPath) || !isSafeRelativePath(relativePath)) return ""
    var candidate = rootPath + "/" + text(relativePath)
    return isDescendant(candidate, rootPath) ? candidate : ""
}

function resolveUrl(root, relativePath) {
    var path = resolvePath(root, relativePath)
    return path === "" ? "" : fileUrl(path)
}

var AureliaSourceUrl = {
    pathFromUrl: pathFromUrl,
    isAbsolutePath: isAbsolutePath,
    isSafeRelativePath: isSafeRelativePath,
    fileUrl: fileUrl,
    isDescendant: isDescendant,
    resolvePath: resolvePath,
    resolveUrl: resolveUrl
}

if (typeof module !== "undefined" && module.exports) module.exports = AureliaSourceUrl
