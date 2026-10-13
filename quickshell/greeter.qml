pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd
import Quickshell.Wayland

// The login screen for greetd, run by `mywm-compositor --greeter`: it looks like the lock screen (LoginScreen.qml),
// with the wallpaper and colors mywm mirrors into the greeter directory. Once greetd starts the session this
// process ends, and the compositor with it.
//
// Environment: MYWM_THEME_STATE (colors), MYWM_GREETER_BACKGROUND (picture), MYWM_GREETER_USER (preset user name),
// MYWM_GREETER_SESSIONS (directory of wayland-sessions/*.desktop).
ShellRoot {
    id: root
    property Theme theme: Theme {}
    property string user: Quickshell.env("MYWM_GREETER_USER") || ""
    property string password: ""
    property string message: ""
    property bool failed: false
    property bool busy: false
    property var sessions: []
    property int session: 0
    readonly property string background: Quickshell.env("MYWM_GREETER_BACKGROUND") || ""
    // The monitor with workspace 1 (named by the compositor), else the first: only it shows the card.
    readonly property var primaryScreen: Quickshell.screens.find(s => s.name === Quickshell.env("MYWM_PRIMARY_OUTPUT"))
        || Quickshell.screens[0] || null

    function submit(): void {
        if (busy || user === "" || sessions.length === 0) return;
        busy = true;
        failed = false;
        message = "";
        Greetd.createSession(user);
    }

    function fail(text: string): void {
        busy = false;
        failed = true;
        password = "";
        message = text;
        if (Greetd.state !== GreetdState.Inactive) Greetd.cancelSession();
    }

    // "<file>:Name=…" and "<file>:Exec=…" lines, one pair per session; Name before Exec in every file.
    function parseSessions(text: string): void {
        const byFile = {};
        for (const line of text.split("\n")) {
            const match = line.match(/^(.*\.desktop):(Name|Exec)=(.*)$/);
            if (!match) continue;
            const entry = byFile[match[1]] || (byFile[match[1]] = {});
            if (!(match[2] in entry)) entry[match[2]] = match[3].trim();
        }
        sessions = Object.keys(byFile).sort().map(file => byFile[file])
            .filter(entry => entry.Name && entry.Exec)
            .map(entry => ({ name: entry.Name, command: entry.Exec.split(/\s+/).filter(part => !part.startsWith("%")) }));
    }

    Process {
        command: ["sh", "-c", "grep -H -E '^(Name|Exec)=' \"$0\"/*.desktop", Quickshell.env("MYWM_GREETER_SESSIONS") || "/run/current-system/sw/share/wayland-sessions"]
        running: true
        stdout: StdioCollector { onStreamFinished: root.parseSessions(text) }
    }
    Process { id: power }

    Connections {
        target: Greetd
        function onAuthMessage(message: string, error: bool, responseRequired: bool, echoResponse: bool): void {
            if (responseRequired) Greetd.respond(root.password);
            else if (error) root.message = message;
        }
        function onAuthFailure(message: string): void { root.fail("Falsches Passwort"); }
        // greetd also answers Quickshell's cancel after a failed attempt with an error; only one during an
        // attempt counts.
        function onError(error: string): void { if (root.busy) root.fail("Anmeldung nicht möglich: " + error); }
        function onReadyToLaunch(): void {
            root.message = "Sitzung startet …";
            Greetd.launch(root.sessions[root.session].command);
        }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: window
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: root.theme.backgroundColor
            WlrLayershell.layer: WlrLayer.Overlay
            readonly property bool primary: modelData === root.primaryScreen
            WlrLayershell.keyboardFocus: primary ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            WlrLayershell.namespace: "mywm-greeter"
            LoginScreen {
                id: login
                anchors.fill: parent
                theme: root.theme
                background: root.background ? "file://" + root.background : ""
                askUser: true
                userName: root.user
                password: root.password
                busy: root.busy
                message: root.message
                messageIsError: root.failed
                sessions: root.sessions
                session: root.session
                showPower: true
                primary: window.primary
                onUserEdited: text => root.user = text
                onPasswordEdited: text => root.password = text
                onSubmitted: root.submit()
                onSessionPicked: index => root.session = index
                onPowerRequested: action => {
                    power.command = ["systemctl", action];
                    power.running = true;
                }
                Component.onCompleted: login.focusField()
            }
        }
    }

    IpcHandler {
        target: "greeter"
        function sessions(): string { return JSON.stringify(root.sessions); }
        function message(): string { return root.message; }
        function pickSession(index: int): void { if (index >= 0 && index < root.sessions.length) root.session = index; }
    }
}
