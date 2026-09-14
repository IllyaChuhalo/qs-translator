import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

ShellRoot {
    id: root

    property bool active: false
    property string inputText: ""
    property string previewText: ""
    property bool translating: false
    property string sttState: "notStarted" // notStarted | idle | listening | processing
    property real micLevel: 0.0
    property string translationBackend: "checking" // checking | google | libre

    Colors { id: colors }
    HyprIPC { id: hypr }

    function show() {
        inputText = ""
        previewText = ""
        inputField.text = ""
        active = true
        win.visible = true
        checkTranslationBackend()
        sttKeepAliveTimer.stop() // reopened in time — cancel any pending unload
        startSttDaemon()
    }

    function hideOnly() {
        active = false
        win.visible = false
        sttKeepAliveTimer.restart()
    }

    // Hide first, wait for Hyprland to give focus back to the previous
    // window, THEN copy + simulate paste, THEN quit — in that order,
    // with delays, to dodge the Wayland focus-handoff race condition.
    function hideAndCommit(text) {
        active = false
        win.visible = false
        sttKeepAliveTimer.restart()
        if (text && text.trim().length > 0) {
            commitTimer.textToCommit = text
            commitTimer.start()
        }
    }

    function checkTranslationBackend() {
        translationBackend = "checking"
        const probe = new XMLHttpRequest()
        probe.onreadystatechange = function () {
            if (probe.readyState === XMLHttpRequest.DONE) {
                translationBackend = (probe.status === 200) ? "google" : "libre"
                console.log("translator: backend check ->", translationBackend, "(status", probe.status + ")")
                if (inputText.trim().length > 0) requestTranslation() // refresh preview with the right backend
            }
        }
        probe.onerror = function () {
            translationBackend = "libre"
            console.log("translator: backend check -> libre (network error reaching google)")
        }
        probe.open("GET", "https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=uk&dt=t&q=test")
        probe.send()
    }

    Timer {
        id: debounce
        interval: 550 // wait for an actual pause in typing, not just between keystrokes
        onTriggered: root.requestTranslation()
    }
    onInputTextChanged: debounce.restart()

    function requestTranslation() {
        if (inputText.trim().length === 0) {
            previewText = ""
            return
        }
        if (translationBackend === "checking") return // debounce will fire again once check resolves
        translating = true
        if (translationBackend === "google") {
            requestTranslationGoogle()
        } else {
            requestTranslationLibre()
        }
    }

    function requestTranslationGoogle() {
        const url = "https://translate.googleapis.com/translate_a/single"
            + "?client=gtx&sl=" + hypr.sourceLang + "&tl=" + hypr.targetLang
            + "&dt=t&q=" + encodeURIComponent(inputText)

        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                console.log("translator: google request done, status =", xhr.status)
                if (xhr.status === 200) {
                    translating = false
                    try {
                        const parsed = JSON.parse(xhr.responseText)
                        previewText = parsed[0].map(seg => seg[0]).join("")
                    } catch (e) {
                        console.warn("translator: could not parse google response:", e)
                    }
                } else {
                    // Google started rate-limiting mid-session — fall back for the rest of it
                    console.warn("translator: google failed (status", xhr.status + "), switching to libre")
                    translationBackend = "libre"
                    requestTranslationLibre()
                }
            }
        }
        xhr.onerror = function () {
            translationBackend = "libre"
            requestTranslationLibre()
        }
        xhr.open("GET", url)
        xhr.send()
    }

    function requestTranslationLibre() {
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                translating = false
                console.log("translator: libre request done, status =", xhr.status)
                if (xhr.status === 200) {
                    try {
                        const parsed = JSON.parse(xhr.responseText)
                        previewText = parsed.translatedText ?? ""
                    } catch (e) {
                        console.warn("translator: could not parse libre response:", e,
                            "raw:", xhr.responseText.slice(0, 200))
                    }
                } else {
                    console.warn("translator: libre translation failed, status", xhr.status,
                        "body:", xhr.responseText.slice(0, 200))
                }
            }
        }
        xhr.onerror = function () {
            translating = false
            console.warn("translator: network-level error contacting local LibreTranslate — is the Docker container running?")
        }
        xhr.open("POST", "http://localhost:5000/translate")
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.send(JSON.stringify({
            q: inputText,
            source: hypr.sourceLang,
            target: hypr.targetLang,
            format: "text"
        }))
    }

    function shellQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }

    Timer {
        id: commitTimer
        interval: 100 // give Hyprland time to hand focus back
        property string textToCommit: ""
        onTriggered: commitProc.run(textToCommit)
    }

    Process {
        id: commitProc
        function run(text) {
            command = ["sh", "-c", "wl-copy -- " + root.shellQuote(text) + " && wtype -M ctrl v -m ctrl"]
            running = true
        }
    }

    // STT daemon lifecycle: pre-warmed on popup open (not on mic tap — by
    // the time you actually reach for the mic, the model's usually
    // already loaded, hidden behind normal human reaction time), kept
    // alive for a while after close so reopening the popup repeatedly
    // doesn't pay reload cost every single time, and only unloaded after
    // sitting idle for a while.
    Timer {
        id: sttKeepAliveTimer
        interval: 45000 // unload model after 45s of the popup being closed
        onTriggered: stopSttDaemon()
    }

    function startSttDaemon() {
        if (!sttProc.running) {
            console.log("translator/STT: pre-warming daemon")
            sttProc.running = true
        }
    }

    function stopSttDaemon() {
        if (sttProc.running) {
            console.log("translator/STT: idle timeout, unloading")
            sttProc.running = false // sends SIGTERM
        }
        sttState = "notStarted"
        micLevel = 0.0
    }

    Process {
        id: sttProc
        command: [
            Quickshell.env("HOME") + "/.local/share/translator-stt-venv/bin/python",
            Quickshell.env("HOME") + "/.config/quickshell/translator/stt_daemon.py",
            "medium"
        ]
        running: false
        stdinEnabled: true

        stdout: SplitParser {
            onRead: line => {
                console.log("translator/STT:", line)
                if (line === "LOADING" || line === "MODEL_READY") {
                    // informational only — doesn't gate recording either way
                } else if (line === "LISTENING") {
                    root.sttState = "listening"
                } else if (line === "PROCESSING" || line === "WAITING_MODEL") {
                    root.sttState = "processing"
                } else if (line.startsWith("LEVEL:")) {
                    root.micLevel = parseFloat(line.slice("LEVEL:".length)) || 0.0
                } else if (line.startsWith("RESULT:")) {
                    root.sttState = "idle"
                    root.micLevel = 0.0
                    const text = line.slice("RESULT:".length)
                    if (text.length > 0) {
                        inputField.text = text
                        inputField.cursorPosition = text.length
                    }
                } else if (line.startsWith("ERROR:")) {
                    root.sttState = "idle"
                    root.micLevel = 0.0
                    console.warn("translator/STT:", line)
                }
            }
        }

        stderr: SplitParser {
            onRead: line => console.warn("translator/STT stderr:", line)
        }
    }

    function sttToggle() {
        if (!sttProc.running) {
            // Shouldn't normally happen (show() pre-warms it), but cover
            // the case anyway — start it and record immediately.
            console.log("translator/STT: daemon wasn't running, starting + recording immediately")
            sttProc.running = true
            sttProc.write("START:" + hypr.sourceLang + "\n")
            return
        }
        if (sttState === "idle" || sttState === "notStarted") {
            sttProc.write("START:" + hypr.sourceLang + "\n")
        } else if (sttState === "listening") {
            sttProc.write("STOP\n") // manual fallback stop
        }
        // "processing" -> ignore taps, nothing sensible to do
    }

    PanelWindow {
        id: win
        visible: false
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "translator-popup"
        // -1 = pure overlay: don't reserve screen space, don't push
        // other (tiled) windows around. Without this, an anchored
        // layer-shell surface can act like a bar and shrink the workarea.
        WlrLayershell.exclusiveZone: -1

        anchors { bottom: true }
        margins { bottom: 96 } // clear the dock — raise/lower to match its height
        implicitWidth: 480
        implicitHeight: card.height

        onVisibleChanged: if (visible) inputField.forceActiveFocus()

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
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        radius: 16
                        color: colors.scheme.surfaceContainerHighest
                        border.width: inputField.activeFocus ? 2 : 0
                        border.color: colors.scheme.primary

                        TextInput {
                            id: inputField
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            verticalAlignment: TextInput.AlignVCenter
                            color: colors.scheme.onSurface
                            font.pixelSize: 16
                            clip: true
                            onTextChanged: root.inputText = text

                            Keys.onEscapePressed: root.hideOnly()
                            Keys.onReturnPressed: root.hideAndCommit(
                                root.previewText.length > 0 ? root.previewText : root.inputText)
                        }
                    }

                    Rectangle {
                        id: micButton
                        Layout.preferredWidth: root.sttState === "listening" ? 120 : 48
                        Layout.preferredHeight: 48
                        radius: 24
                        color: {
                            if (root.sttState === "listening") return colors.scheme.errorContainer ?? colors.scheme.error
                            if (root.sttState === "processing")
                                return colors.scheme.surfaceContainerHighest
                            return micArea.pressed ? colors.scheme.primary : colors.scheme.secondaryContainer
                        }
                        Behavior on Layout.preferredWidth {
                            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                        }

                        // Idle/loading/processing: single icon glyph
                        Text {
                            anchors.centerIn: parent
                            visible: root.sttState !== "listening"
                            text: "mic"
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 22
                            opacity: root.sttState === "processing" ? 0.5 : 1.0
                            color: micArea.pressed ? colors.scheme.onPrimary : colors.scheme.onSecondaryContainer
                        }

                        // Listening: small voice-level bar visualizer + stop glyph
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
                                        height: Math.max(5, Math.min(24,
                                            5 + root.micLevel * 19 * (0.4 + Math.random() * 0.6)))
                                        color: colors.scheme.onErrorContainer ?? colors.scheme.onError

                                        Behavior on height {
                                            NumberAnimation { duration: 90; easing.type: Easing.OutQuad }
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

                    Item { Layout.fillWidth: true }

                    Text {
                        visible: root.translationBackend !== "checking"
                        text: root.translationBackend === "google" ? "Google" : "Local (LibreTranslate)"
                        color: colors.scheme.outline
                        font.pixelSize: 11
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "translator"
        function toggle(): void {
            if (root.active) root.hideOnly()
            else root.show()
        }
    }
}
