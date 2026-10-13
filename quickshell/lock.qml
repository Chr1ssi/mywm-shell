pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland

// The screen lock (ext-session-lock), started by the compositor. The password goes through PAM (service
// `mywm-lock`); only a successful check unlocks, and if this process dies the session stays locked.
ShellRoot {
    id: root
    property Theme theme: Theme {}
    property string password: ""
    property string message: ""
    property bool failed: false
    readonly property string userName: Quickshell.env("USER") || ""
    readonly property url background: theme.generated.source ? "file://" + theme.generated.source : ""

    function submit(): void {
        if (pam.active || root.password === "") return;
        root.message = "";
        root.failed = false;
        pam.start();
    }

    PamContext {
        id: pam
        config: "mywm-lock"
        // The tests bring their own PAM services.
        configDirectory: Quickshell.env("MYWM_PAM_DIR") || "/etc/pam.d"
        onResponseRequiredChanged: if (responseRequired) respond(root.password)
        onCompleted: result => {
            if (result === PamResult.Success) {
                lock.locked = false;
                return;
            }
            root.password = "";
            root.failed = true;
            root.message = result === PamResult.MaxTries ? "Zu viele Versuche" : "Falsches Passwort";
        }
        onError: error => {
            root.password = "";
            root.failed = true;
            root.message = "Anmeldung nicht möglich (" + PamError.toString(error) + ")";
        }
    }

    WlSessionLock {
        id: lock
        locked: true
        onLockedChanged: if (!locked) Qt.quit()
        WlSessionLockSurface {
            id: surface
            color: root.theme.backgroundColor
            LoginScreen {
                id: login
                anchors.fill: parent
                theme: root.theme
                background: root.background
                userName: root.userName
                password: root.password
                busy: pam.active
                message: root.message
                messageIsError: root.failed
                onPasswordEdited: text => root.password = text
                onSubmitted: root.submit()
                Component.onCompleted: login.focusField()
            }
        }
    }

    IpcHandler {
        target: "lock"
        function locked(): bool { return lock.locked && lock.secure; }
        function message(): string { return root.message; }
    }
}
