import QtQuick
import "../../../services"

// Small child whose only job is to expose the shared AppIconResolver's
// asynchronous metadata-index readiness to an isolated fixture. A relative
// services import is only resolved for loadable children, which is why this is
// a separate file loaded through a Loader rather than an inline object in the
// root fixture. It never mutates anything.
QtObject {
    id: gate

    signal metadataReady()

    readonly property int revision: AppIconResolver.metadataIndexRevision

    onRevisionChanged: {
        if (revision > 0) gate.metadataReady()
    }

    Component.onCompleted: {
        if (revision > 0) gate.metadataReady()
    }
}
