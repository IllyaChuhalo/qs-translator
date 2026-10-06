import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    property bool active: false
    property string inputText: ""
    property string previewText: ""
    property bool translating: false
    property string sttState: "notStarted" // notStarted | idle | listening | processing
    property real micLevel: 0
    property string translationBackend: "" // "" | "google" | "libre"
    property bool googleFailedInSession: false
    property bool aiPolishEnabled: true
    property bool isPolishing: false

    function show() {
        colors.refresh();
        inputText = "";
        previewText = "";
        inputField.text = "";
        translationBackend = "";
        googleFailedInSession = false;
        isPolishing = false;
        active = true;
        win.visible = true;
        sttKeepAliveTimer.stop();
        startSttDaemon();
    }

    function hideOnly() {
        active = false;
        win.visible = false;
        sttKeepAliveTimer.restart();
    }

    // Closes the popup and commits text to the active window via clipboard and simulated paste.
    function hideAndCommit(text) {
        active = false;
        win.visible = false;
        sttKeepAliveTimer.restart();
        if (text && text.trim().length > 0) {
            commitTimer.textToCommit = text;
            commitTimer.start();
        }
    }

    // Requests translation using Google Translate with automatic fallback to LibreTranslate.
    function requestTranslation() {
        if (inputText.trim().length === 0) {
            previewText = "";
            translationBackend = "";
            return ;
        }
        translating = true;
        if (googleFailedInSession)
            requestTranslationLibre();
        else
            requestTranslationGoogle();
    }

    function requestTranslationGoogle() {
        const url = "https://translate.googleapis.com/translate_a/single" + "?client=gtx&sl=" + hypr.sourceLang + "&tl=" + hypr.targetLang + "&dt=t&q=" + encodeURIComponent(inputText);
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                console.log("translator: google request done, status =", xhr.status);
                if (xhr.status === 200) {
                    translating = false;
                    translationBackend = "google";
                    try {
                        const parsed = JSON.parse(xhr.responseText);
                        previewText = parsed[0].map((seg) => {
                            return seg[0];
                        }).join("");
                    } catch (e) {
                        console.warn("translator: could not parse google response:", e);
                    }
                } else {
                    console.warn("translator: google failed (status", xhr.status + "), switching to libre for this session");
                    googleFailedInSession = true;
                    translationBackend = "libre";
                    requestTranslationLibre();
                }
            }
        };
        xhr.onerror = function() {
            console.warn("translator: google network error, switching to libre for this session");
            googleFailedInSession = true;
            translationBackend = "libre";
            requestTranslationLibre();
        };
        xhr.open("GET", url);
        xhr.send();
    }

    function requestTranslationLibre() {
        translationBackend = "libre";
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                translating = false;
                console.log("translator: libre request done, status =", xhr.status);
                if (xhr.status === 200) {
                    try {
                        const parsed = JSON.parse(xhr.responseText);
                        previewText = parsed.translatedText ?? "";
                    } catch (e) {
                        console.warn("translator: could not parse libre response:", e, "raw:", xhr.responseText.slice(0, 200));
                    }
                } else {
                    console.warn("translator: libre translation failed, status", xhr.status, "body:", xhr.responseText.slice(0, 200));
                }
            }
        };
        xhr.onerror = function() {
            translating = false;
            console.warn("translator: network-level error contacting local LibreTranslate — is the Docker container running?");
        };
        xhr.open("POST", "http://localhost:5000/translate");
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.send(JSON.stringify({
            "q": inputText,
            "source": hypr.sourceLang,
            "target": hypr.targetLang,
            "format": "text"
        }));
    }

    // Submits transcribed speech to local SLM for grammar polish before translation.
    function handleVoiceFinalResult(text) {
        if (!text || text.trim().length === 0)
            return ;

        if (aiPolishEnabled) {
            isPolishing = true;
            polishTimer.pendingText = text;
            if (sttProc.running)
                sttProc.write("POLISH:" + text + "\n");

            polishTimer.restart();
        } else {
            requestTranslation();
        }
    }

    function shellQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    function startSttDaemon() {
        if (!sttProc.running) {
            console.log("translator/STT: pre-warming daemon");
            sttProc.running = true;
        }
    }

    function stopSttDaemon() {
        if (sttProc.running) {
            console.log("translator/STT: idle timeout, unloading");
            sttProc.running = false; // sends SIGTERM
        }
        sttState = "notStarted";
        isPolishing = false;
        micLevel = 0;
    }

    function sttToggle() {
        if (!sttProc.running) {
            console.log("translator/STT: starting daemon and recording");
            sttProc.running = true;
            sttProc.write("START:" + hypr.sourceLang + "\n");
            return ;
        }
        if (sttState === "idle" || sttState === "notStarted")
            sttProc.write("START:" + hypr.sourceLang + "\n");
        else if (sttState === "listening")
            sttProc.write("STOP\n");
    }

    onInputTextChanged: {
        if (sttState !== "listening" && !isPolishing)
            debounce.restart();

    }

    Colors {
        id: colors
    }

    HyprIPC {
        id: hypr
    }

    Timer {
        id: debounce

        interval: 550
        onTriggered: root.requestTranslation()
    }

    Timer {
        id: polishTimer

        property string pendingText: ""

        interval: 3500
        onTriggered: {
            if (root.isPolishing) {
                console.warn("translator: AI polish timeout fallback, translating raw text");
                root.isPolishing = false;
                root.requestTranslation();
            }
        }
    }

    Timer {
        id: commitTimer

        property string textToCommit: ""

        interval: 100
        onTriggered: commitProc.run(textToCommit)
    }

    Process {
        id: commitProc

        function run(text) {
            command = ["sh", "-c", "wl-copy -- " + root.shellQuote(text) + " && wtype -M ctrl v -m ctrl"];
            running = true;
        }

    }

    // Manages STT daemon lifecycle, pre-warming on open and unloading after idle timeout.
    Timer {
        id: sttKeepAliveTimer

        interval: 45000
        onTriggered: stopSttDaemon()
    }

    Process {
        id: sttProc

        command: [Quickshell.env("HOME") + "/.local/share/translator-stt-venv/bin/python", Quickshell.env("HOME") + "/.config/quickshell/translator/stt_daemon.py", "medium"]
        running: false
        stdinEnabled: true

        stdout: SplitParser {
            onRead: (line) => {
                console.log("translator/STT:", line);
                if (line === "LOADING" || line === "MODEL_READY") {
                } else if (line === "LISTENING") {
                    root.sttState = "listening";
                } else if (line === "PROCESSING" || line === "WAITING_MODEL") {
                    root.sttState = "processing";
                } else if (line.startsWith("LEVEL:")) {
                    root.micLevel = parseFloat(line.slice("LEVEL:".length)) || 0;
                } else if (line.startsWith("PARTIAL:")) {
                    const partialText = line.slice("PARTIAL:".length);
                    if (partialText.length > 0) {
                        inputField.text = partialText;
                        inputField.cursorPosition = partialText.length;
                    }
                } else if (line.startsWith("RESULT:")) {
                    root.sttState = "idle";
                    root.micLevel = 0;
                    const text = line.slice("RESULT:".length);
                    if (text.length > 0) {
                        inputField.text = text;
                        inputField.cursorPosition = text.length;
                    }
                    root.handleVoiceFinalResult(text);
                } else if (line.startsWith("POLISHED:")) {
                    polishTimer.stop();
                    root.isPolishing = false;
                    const polished = line.slice("POLISHED:".length).trim();
                    if (polished.length > 0) {
                        inputField.text = polished;
                        inputField.cursorPosition = polished.length;
                    }
                    root.requestTranslation();
                } else if (line.startsWith("ERROR:")) {
                    root.sttState = "idle";
                    root.isPolishing = false;
                    root.micLevel = 0;
                    console.warn("translator/STT:", line);
                }
            }
        }

        stderr: SplitParser {
            onRead: (line) => {
                return console.warn("translator/STT stderr:", line);
            }
        }

    }

    PanelWindow {
        id: win

        visible: false
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "translator-popup"
        WlrLayershell.exclusiveZone: -1
        implicitWidth: 480
        implicitHeight: card.height
        onVisibleChanged: {
            if (visible)
                inputField.forceActiveFocus();

        }

        anchors {
            bottom: true
        }

        margins {
            bottom: 96
        }

        Rectangle {
            id: card

            anchors.horizontalCenter: parent.horizontalCenter
            width: 460
            height: content.implicitHeight + 32
            radius: 24
            color: colors.scheme.surfaceContainerHigh
            border.width: 1
            border.color: colors.scheme.outlineVariant

            ColumnLayout {
                id: content

                anchors.fill: parent
                anchors.margins: 16
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        id: inputContainer

                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        radius: 16
                        color: colors.scheme.surfaceContainerHighest
                        border.width: root.isPolishing ? 2 : (inputField.activeFocus ? 2 : 0)
                        border.color: colors.scheme.primary
                        clip: true

                        Rectangle {
                            id: shimmerWave

                            visible: root.isPolishing
                            width: 150
                            height: parent.height
                            anchors.verticalCenter: parent.verticalCenter

                            gradient: Gradient {
                                orientation: Gradient.Horizontal

                                GradientStop {
                                    position: 0
                                    color: "transparent"
                                }

                                GradientStop {
                                    position: 0.5
                                    color: Qt.alpha(colors.scheme.primary, 0.35)
                                }

                                GradientStop {
                                    position: 1
                                    color: "transparent"
                                }

                            }

                            NumberAnimation on x {
                                from: -150
                                to: inputContainer.width + 150
                                duration: 1100
                                loops: Animation.Infinite
                                running: root.isPolishing
                            }

                        }

                        TextInput {
                            id: inputField

                            anchors.left: parent.left
                            anchors.right: polishBtn.left
                            anchors.leftMargin: 16
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            color: colors.scheme.onSurface
                            font.pixelSize: 16
                            clip: true
                            onTextChanged: root.inputText = text
                            Keys.onEscapePressed: root.hideOnly()
                            Keys.onReturnPressed: root.hideAndCommit(root.previewText.length > 0 ? root.previewText : root.inputText)
                        }

                        Rectangle {
                            id: polishBtn

                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28
                            height: 28
                            radius: 14
                            color: "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "auto_awesome"
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: 20
                                color: root.aiPolishEnabled ? colors.scheme.primary : colors.scheme.outline
                                opacity: root.aiPolishEnabled ? 1 : 0.45

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 150
                                    }

                                }

                                Behavior on color {
                                    ColorAnimation {
                                        duration: 150
                                    }

                                }

                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.aiPolishEnabled = !root.aiPolishEnabled
                            }

                        }

                    }

                    Rectangle {
                        id: micButton

                        Layout.preferredWidth: root.sttState === "listening" ? 120 : 48
                        Layout.preferredHeight: 48
                        radius: 24
                        color: {
                            if (root.sttState === "listening")
                                return colors.scheme.errorContainer ?? colors.scheme.error;

                            if (root.sttState === "processing" || root.isPolishing)
                                return colors.scheme.surfaceContainerHighest;

                            return micArea.pressed ? colors.scheme.primary : colors.scheme.secondaryContainer;
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: root.sttState !== "listening"
                            text: "mic"
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 22
                            opacity: (root.sttState === "processing" || root.isPolishing) ? 0.7 : 1
                            color: micArea.pressed ? colors.scheme.onPrimary : colors.scheme.onSecondaryContainer
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 6
                            visible: root.sttState === "listening"

                            Row {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 3
                                height: 24

                                Repeater {
                                    model: 5

                                    delegate: Rectangle {
                                        width: 4
                                        radius: 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        height: Math.max(5, Math.min(24, 5 + root.micLevel * 19 * (0.4 + Math.random() * 0.6)))
                                        color: colors.scheme.onErrorContainer ?? colors.scheme.onError

                                        Behavior on height {
                                            NumberAnimation {
                                                duration: 90
                                                easing.type: Easing.OutQuad
                                            }

                                        }

                                    }

                                }

                            }

                            Text {
                                text: "stop"
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: 18
                                color: colors.scheme.onErrorContainer ?? colors.scheme.onError
                            }

                        }

                        MouseArea {
                            id: micArea

                            anchors.fill: parent
                            enabled: root.sttState === "notStarted" || root.sttState === "idle" || root.sttState === "listening"
                            onClicked: root.sttToggle()
                        }

                        Behavior on Layout.preferredWidth {
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutCubic
                            }

                        }

                    }

                }

                Text {
                    Layout.fillWidth: true
                    visible: root.translating || root.previewText.length > 0
                    text: root.translating ? "…" : root.previewText
                    color: colors.scheme.onSurfaceVariant
                    font.pixelSize: 14
                    wrapMode: Text.Wrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: hypr.direction
                        color: colors.scheme.outline
                        font.pixelSize: 11
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Text {
                        visible: root.translationBackend.length > 0 && root.previewText.length > 0
                        text: root.translationBackend === "google" ? "Google" : "LibreTranslate"
                        color: colors.scheme.outline
                        font.pixelSize: 11
                    }

                }

            }

        }

    }

    IpcHandler {
        function toggle() {
            if (root.active)
                root.hideOnly();
            else
                root.show();
        }

        target: "translator"
    }

}
