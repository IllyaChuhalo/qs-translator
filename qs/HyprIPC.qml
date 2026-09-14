import QtQuick
import Quickshell
import Quickshell.Io

// Tracks the active Hyprland keyboard layout and exposes the
// translation direction that follows from it:
//   Ukrainian layout active -> uk -> en
//   anything else           -> en -> uk
Item {
    id: root

    property string activeLayout: "en" // normalized: "uk" | "en"
    readonly property string sourceLang: activeLayout === "uk" ? "uk" : "en"
    readonly property string targetLang: activeLayout === "uk" ? "en" : "uk"
    readonly property string direction: sourceLang + " → " + targetLang

    function normalize(layoutName) {
        const n = String(layoutName || "").toLowerCase()
        return (n.indexOf("ukrain") !== -1 || n === "uk") ? "uk" : "en"
    }

    // --- 1. Initial layout on startup ---
    Process {
        id: initialLayoutProc
        command: ["hyprctl", "devices", "-j"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text)
                    const kbs = data.keyboards || []
                    const main = kbs.find(k => k.main) || kbs[0]
                    if (main) root.activeLayout = root.normalize(main.active_keymap)
                } catch (e) {
                    console.warn("translator/HyprIPC: failed to parse hyprctl devices -j:", e)
                }
            }
        }
    }

    // --- 2. Live layout-change events over Hyprland's event socket ---
    Socket {
        id: hyprSocket
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/hypr/"
            + Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") + "/.socket2.sock"
        connected: true

        parser: SplitParser {
            onRead: line => {
                if (line.startsWith("activelayout>>")) {
                    // format: activelayout>>KEYBOARDNAME,LAYOUTNAME
                    const parts = line.split(">>")[1]?.split(",") || []
                    const layoutName = parts[1] || ""
                    root.activeLayout = root.normalize(layoutName)
                }
            }
        }

        onConnectedChanged: {
            if (!connected) console.warn("translator/HyprIPC: lost connection to Hyprland socket2")
        }
    }
}
