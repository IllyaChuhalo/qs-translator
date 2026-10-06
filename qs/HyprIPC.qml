import QtQuick
import Quickshell
import Quickshell.Io

// Synchronizes translation direction with the active Hyprland keyboard layout (uk -> en or en -> uk).
Item {
    id: root

    property string activeLayout: "en"
    readonly property string sourceLang: activeLayout === "uk" ? "uk" : "en"
    readonly property string targetLang: activeLayout === "uk" ? "en" : "uk"
    readonly property string direction: sourceLang + " → " + targetLang

    function normalize(layoutName) {
        const n = String(layoutName || "").toLowerCase();
        return (n.indexOf("ukrain") !== -1 || n === "uk") ? "uk" : "en";
    }

    Process {
        id: initialLayoutProc

        command: ["hyprctl", "devices", "-j"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    const kbs = data.keyboards || [];
                    const main = kbs.find((k) => {
                        return k.main;
                    }) || kbs[0];
                    if (main)
                        root.activeLayout = root.normalize(main.active_keymap);

                } catch (e) {
                    console.warn("translator/HyprIPC: failed to parse hyprctl devices -j:", e);
                }
            }
        }

    }

    Socket {
        id: hyprSocket

        path: Quickshell.env("XDG_RUNTIME_DIR") + "/hypr/" + Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") + "/.socket2.sock"
        connected: true
        onConnectedChanged: {
            if (!connected)
                console.warn("translator/HyprIPC: lost connection to Hyprland socket2");

        }

        parser: SplitParser {
            onRead: (line) => {
                if (line.startsWith("activelayout>>")) {
                    const raw = line.split(">>")[1];
                    const parts = raw ? raw.split(",") : [];
                    const layoutName = parts[1] || "";
                    root.activeLayout = root.normalize(layoutName);
                }
            }
        }

    }

}
