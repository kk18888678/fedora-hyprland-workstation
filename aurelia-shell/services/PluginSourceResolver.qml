import QtQuick

// Host-owned source descriptor boundary. A descriptor is plain data and is
// created only from a validated plugin identity/kind, an absolute source root,
// and a manifest-relative entry point. Loaders receive only descriptor.url at
// the final boundary; manifests and persisted state never store that URL.
QtObject {
    id: root

    function text(value) {
        return String(value === undefined || value === null ? "" : value)
    }

    function hasUnsafeCharacters(value) {
        return /[\x00-\x1f\x7f]/.test(root.text(value))
    }

    function pathFromUrl(value) {
        var source = root.text(value)
        if (source.indexOf("file://") !== 0) return source
        var encodedPath = source.substring(7)
        if (encodedPath.indexOf("/") !== 0) {
            if (encodedPath.indexOf("localhost/") !== 0) return ""
            encodedPath = "/" + encodedPath.substring(10)
        }
        if (root.hasUnsafeCharacters(encodedPath)) return ""
        try {
            return decodeURIComponent(encodedPath)
        } catch (error) {
            console.error("[PLUGIN] source_path_decode_failed")
            return ""
        }
    }

    function isAbsolutePath(value, allowRoot) {
        var path = root.pathFromUrl(value)
        return path.charAt(0) === "/" && (allowRoot === true || path !== "/") &&
            path.indexOf("\\") === -1 && !root.hasUnsafeCharacters(path)
    }

    function isSafeRelativePath(value) {
        var path = root.text(value)
        return path !== "" && path.charAt(0) !== "/" && path.indexOf("..") === -1 &&
            path.indexOf("\\") === -1 && path.indexOf(":") === -1 &&
            !root.hasUnsafeCharacters(path)
    }

    function fileUrl(value) {
        var path = root.pathFromUrl(value)
        if (!root.isAbsolutePath(path, true)) return ""
        var parts = path.split("/")
        try {
            for (var i = 0; i < parts.length; i++) parts[i] = encodeURIComponent(parts[i])
        } catch (error) {
            console.error("[PLUGIN] source_url_encode_failed")
            return ""
        }
        return "file://" + parts.join("/")
    }

    function isDescendant(path, sourceRoot) {
        var candidate = root.pathFromUrl(path)
        var parent = root.pathFromUrl(sourceRoot).replace(/\/+$/, "")
        return root.isAbsolutePath(candidate, true) && root.isAbsolutePath(parent, true) &&
            (candidate === parent || candidate.indexOf(parent + "/") === 0)
    }

    function resolvePath(sourceRoot, relativeEntryPoint) {
        var rootPath = root.pathFromUrl(sourceRoot).replace(/\/+$/, "")
        if (!root.isAbsolutePath(rootPath) || !root.isSafeRelativePath(relativeEntryPoint)) return ""
        var candidate = rootPath + "/" + root.text(relativeEntryPoint)
        return root.isDescendant(candidate, rootPath) ? candidate : ""
    }

    function invalidDescriptor(pluginId, kind, sourceRoot, relativeEntryPoint, error) {
        return {
            valid: false,
            id: String(pluginId || ""),
            kind: String(kind || ""),
            sourceRoot: String(sourceRoot || ""),
            relativeEntryPoint: String(relativeEntryPoint || ""),
            sourcePath: "",
            url: "",
            manifestPath: "",
            error: String(error || "invalid source descriptor")
        }
    }

    function descriptor(pluginId, kind, sourceRoot, relativeEntryPoint, manifestPath) {
        var id = String(pluginId || "")
        var entryKind = String(kind || "")
        var rootPath = root.pathFromUrl(sourceRoot)
        var relative = String(relativeEntryPoint || "")
        var manifest = String(manifestPath || "")
        if (id === "" || entryKind === "")
            return root.invalidDescriptor(id, entryKind, rootPath, relative, "plugin identity or kind is missing")
        if (!root.isAbsolutePath(rootPath))
            return root.invalidDescriptor(id, entryKind, rootPath, relative, "source root is not an absolute local path")
        if (!root.isSafeRelativePath(relative))
            return root.invalidDescriptor(id, entryKind, rootPath, relative, "entry point is not a safe relative path")

        var sourcePath = root.resolvePath(rootPath, relative)
        var url = sourcePath === "" ? "" : root.fileUrl(sourcePath)
        if (sourcePath === "" || url === "")
            return root.invalidDescriptor(id, entryKind, rootPath, relative, "entry point escapes source root")

        return {
            valid: true,
            id: id,
            kind: entryKind,
            sourceRoot: rootPath,
            relativeEntryPoint: relative,
            sourcePath: sourcePath,
            url: url,
            manifestPath: manifest,
            error: ""
        }
    }

    function descriptorForManifest(pluginId, kind, manifest, entryPoint) {
        var source = manifest && typeof manifest === "object" ? manifest : ({})
        var rootPath = source.__sourceDir || source.sourceRoot || ""
        return root.descriptor(pluginId, kind, rootPath, entryPoint, source.__manifestPath || source.manifestPath || "")
    }

    function resolveUrl(sourceRoot, relativeEntryPoint) {
        var path = root.resolvePath(sourceRoot, relativeEntryPoint)
        return path === "" ? "" : root.fileUrl(path)
    }
}
