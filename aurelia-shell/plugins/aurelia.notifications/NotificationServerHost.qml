import QtQuick
import Quickshell.Services.Notifications

// Constructed only after the resident service has confirmed that the
// freedesktop notification bus name is available. This prevents a known
// competing owner from producing repeated Quickshell registration warnings.
Item {
    id: root

    property var service: null
    property var pendingNotifications: []

    function deliver(notification) {
        if (!notification) return
        if (root.service) {
            root.service.handleNotification(notification)
            return
        }
        // Loader injection and the first D-Bus signal can occur in adjacent
        // event-loop turns. Track the object now so it cannot disappear while
        // the resident Service reference is being connected.
        try { notification.tracked = true } catch (error) {}
        root.pendingNotifications = root.pendingNotifications.concat([notification])
    }

    onServiceChanged: {
        if (!root.service || root.pendingNotifications.length === 0) return
        var pending = root.pendingNotifications
        root.pendingNotifications = []
        for (var i = 0; i < pending.length; i++) root.service.handleNotification(pending[i])
    }

    NotificationServer {
        id: notificationServer
        // Ask Quickshell to re-emit tracked notifications across a hot reload;
        // the Aurelia state files remain the cross-process recovery layer.
        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        actionsSupported: true
        imageSupported: true

        onNotification: function(notification) {
            root.deliver(notification)
        }
    }
}
