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
    // Lock surfaces whose screen is built: keys reach a field from then on.
    property int readySurfaces: 0
    readonly property string userName: Quickshell.env("USER") || ""
    readonly property url background: theme.generated.source ? "file://" + theme.generated.source : ""
    // The monitor with workspace 1 (named by the compositor), else the first: only it shows the card.
    readonly property var primaryScreen: Quickshell.screens.find(s => s.name === Quickshell.env("MYWM_PRIMARY_OUTPUT"))
        || Quickshell.screens[0] || null

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
                primary: surface.screen === root.primaryScreen
                onPasswordEdited: text => root.password = text
                onSubmitted: root.submit()
                Component.onCompleted: {
                    login.focusField();
                    root.readySurfaces += 1;
                }
                Component.onDestruction: root.readySurfaces -= 1
            }
        }
    }

    IpcHandler {
        target: "lock"
        function locked(): bool { return lock.locked && lock.secure; }
        // Locked and drawn on every monitor: typing reaches the password.
        function ready(): bool { return lock.secure && root.readySurfaces >= Quickshell.screens.length; }
        function message(): string { return root.message; }
    }
}
