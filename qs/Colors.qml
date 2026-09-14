import QtQuick
import Quickshell
import Quickshell.Io

// Reads the Material 3 palette that matugen/ii generates on every
// wallpaper/theme change. We deliberately do NOT import ii's own
// Appearance.qml (it drags in a chain of relative imports from inside
// ii/modules/ that can shift on update) — instead we read the same
// raw JSON artifact ii itself is driven by. If the theme changes,
// watchChanges picks it up live and the popup re-colors itself.
Item {
    id: root

    readonly property string colorsPath:
        Quickshell.env("HOME") + "/.local/state/quickshell/user/generated/colors.json"

    // Safe dark fallback (mirrors your current palette) used until the
    // file has loaded once, or if it's ever briefly unreadable.
    property var scheme: ({
        background: "#141314",
        surface: "#141314",
        surfaceDim: "#141314",
        surfaceBright: "#3a3939",
        surfaceContainerLowest: "#0e0e0e",
        surfaceContainerLow: "#1c1b1c",
        surfaceContainer: "#201f20",
        surfaceContainerHigh: "#2b2a2a",
        surfaceContainerHighest: "#353435",
        onSurface: "#e5e1e2",
        onSurfaceVariant: "#c8c5cb",
        primary: "#c8c5cd",
        onPrimary: "#303036",
        primaryContainer: "#0b0b10",
        onPrimaryContainer: "#9c9aa1",
        secondary: "#c9c5c9",
        onSecondary: "#313032",
        secondaryContainer: "#474649",
        onSecondaryContainer: "#e3dfe2",
        error: "#ffb4ab",
        onError: "#690005",
        outline: "#929095",
        outlineVariant: "#47464b",
        scrim: "#000000"
    })

    function applyRaw(raw) {
        root.scheme = {
            background: raw.background,
            surface: raw.surface,
            surfaceDim: raw.surface_dim,
            surfaceBright: raw.surface_bright,
            surfaceContainerLowest: raw.surface_container_lowest,
            surfaceContainerLow: raw.surface_container_low,
            surfaceContainer: raw.surface_container,
            surfaceContainerHigh: raw.surface_container_high,
            surfaceContainerHighest: raw.surface_container_highest,
            onSurface: raw.on_surface,
            onSurfaceVariant: raw.on_surface_variant,
            primary: raw.primary,
            onPrimary: raw.on_primary,
            primaryContainer: raw.primary_container,
            onPrimaryContainer: raw.on_primary_container,
            secondary: raw.secondary,
            onSecondary: raw.on_secondary,
            secondaryContainer: raw.secondary_container,
            onSecondaryContainer: raw.on_secondary_container,
            error: raw.error,
            onError: raw.on_error,
            outline: raw.outline,
            outlineVariant: raw.outline_variant,
            scrim: raw.scrim
        }
    }

    // FileView.loaded is a plain bool property and text() a plain function
    // (per Quickshell.Io.FileView docs) — so we just react to loaded
    // flipping true, rather than guessing at a custom signal signature.
    FileView {
        id: file
        path: root.colorsPath
        watchChanges: true
        onFileChanged: reload()

        onLoadedChanged: {
            if (loaded) {
                try {
                    root.applyRaw(JSON.parse(file.text()))
                } catch (e) {
                    console.warn("translator/Colors: failed to parse colors.json:", e)
                }
            }
        }
    }
}
