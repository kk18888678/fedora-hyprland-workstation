import QtQuick
import Quickshell.Services.Notifications

// Constructed only after the resident service has confirmed that the
// freedesktop notification bus name is available. This prevents a known
// competing owner from producing repeated Quickshell registration warnings.
Item {
    id: root

    property var service: null

    NotificationServer {
        id: notificationServer
        keepOnReload: false
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: false
        bodyHyperlinksSupported: false
        actionsSupported: true
        imageSupported: true

        onNotification: function(notification) {
            if (root.service) root.service.handleNotification(notification)
        }
    }
}
