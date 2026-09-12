import QtQuick
import Quickshell
import Quickshell.Io

// T11 metadata fixture. It exercises the real BarWidgetRegistry and
// ShellConfig normalization with a test-local registry.
ShellRoot {
    id: root

    readonly property string barRegistrySource: Quickshell.env("AURELIA_BAR_METADATA_REGISTRY_SOURCE") || ""
    readonly property string configSource: Quickshell.env("AURELIA_BAR_METADATA_CONFIG_SOURCE") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_BAR_METADATA_RESULT") || ""
    property var barRegistry: null
    property var stateConfig: null
    property bool evaluated: false

    QtObject {
        id: fakeRegistry
        property int revision: 1
        property var pluginIds: ["fixture.defaulted", "fixture.multi"]
        property var installedPlugins: ({
            "fixture.defaulted": {
                name: "Defaulted widget",
                version: "1.0.0",
                description: "Fixture",
                kinds: ["bar-widget"],
                entryPoints: { barWidget: "Defaulted.qml" },
                barWidget: {
                    displayName: "Defaulted",
                    description: "Defaulted fixture",
                    category: "Testing",
                    allowMultiple: false,
                    defaultSection: "right",
                    defaults: { format: "default", defaultOnly: 1 },
                    settingsForm: "fixtureSettings",
                    schema: [{ key: "format", type: "string", label: "Format" }]
                }
            },
            "fixture.multi": {
                name: "Multi widget",
                version: "1.0.0",
                description: "Fixture",
                kinds: ["bar-widget"],
                entryPoints: { barWidget: "Multi.qml" },
                barWidget: {
                    displayName: "Multi",
                    description: "Multi fixture",
                    category: "Testing",
                    allowMultiple: true,
                    defaultSection: "center"
                }
            }
        })
        signal pluginsChanged()

        function entryPointUrl(id, kind) {
            if (!installedPlugins[id]) return ""
            var key = kind === "bar-widget" ? "barWidget" : kind
            return Qt.resolvedUrl(installedPlugins[id].entryPoints[key])
        }

        function isEnabled(id) {
            return installedPlugins[id] !== undefined
        }

        function hasActiveRuntimeFailure(id, kind) {
            return false
        }
    }

    Loader {
        id: barRegistryLoader
        source: root.barRegistrySource
        onLoaded: {
            item.pluginRegistry = fakeRegistry
            item.sync()
            root.barRegistry = item
            root.tryEvaluate()
        }
    }

    Loader {
        id: configLoader
        source: root.configSource
        onLoaded: {
            item.barWidgetRegistry = root.barRegistry
            root.stateConfig = item
            root.tryEvaluate()
        }
    }

    FileView {
        id: resultFile
        path: root.resultPath
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: false
        printErrors: false
        onSaved: Qt.quit()
        onSaveFailed: Qt.quit()
    }

    function writeResult(value) {
        if (root.evaluated || root.resultPath === "") return
        root.evaluated = true
        resultFile.setText(JSON.stringify(value) + "\n")
    }

    function tryEvaluate() {
        if (root.evaluated || !root.barRegistry || !root.stateConfig) return
        root.stateConfig.barWidgetRegistry = root.barRegistry
        var explicit = {
            id: "fixture.defaulted",
            format: "custom",
            settings: { format: "nested", userOnly: 7 },
            unknownUser: "keep"
        }
        var normalized = root.stateConfig.normalize({
            version: 1,
            bar: {
                id: "aurelia.bar",
                layout: {
                    left: [],
                    center: [],
                    right: [
                        { id: "fixture.defaulted" },
                        explicit,
                        { id: "fixture.multi", instanceId: "multi-a" },
                        { id: "fixture.multi", instanceId: "multi-b" }
                    ]
                }
            }
        })
        var settings = root.barRegistry.settingsFor("fixture.defaulted", explicit)
        var entries = normalized.bar.layout.right
        root.writeResult({
            defaultFormat: root.barRegistry.settingsFor("fixture.defaulted", {id: "fixture.defaulted"}).format,
            explicitFormat: settings.format,
            nestedUserValue: settings.userOnly,
            unknownUserValue: settings.unknownUser,
            defaultOnly: settings.defaultOnly,
            displayName: root.barRegistry.displayNameFor("fixture.defaulted"),
            description: root.barRegistry.descriptionFor("fixture.defaulted"),
            category: root.barRegistry.categoryFor("fixture.defaulted"),
            settingsForm: root.barRegistry.settingsFormFor("fixture.defaulted"),
            defaultSection: root.barRegistry.defaultSectionFor("fixture.defaulted"),
            singleAllowMultiple: root.barRegistry.allowMultipleFor("fixture.defaulted"),
            multiAllowMultiple: root.barRegistry.allowMultipleFor("fixture.multi"),
            schemaLength: root.barRegistry.schemaFor("fixture.defaulted").length,
            normalizedEntryCount: entries.length,
            firstEntryId: entries[0].id,
            multiInstanceIds: [entries[1].instanceId, entries[2].instanceId],
            widgetCount: root.barRegistry.widgetIds.length
        })
    }

    Timer {
        interval: 7000
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
