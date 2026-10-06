import QtQuick
import Quickshell
import Quickshell.Io

// Manages dynamic theme palettes with priority-based path resolution and change detection.
Item {
    id: root

    readonly property string envColorsPath: Quickshell.env("TRANSLATOR_COLORS_PATH") || ""
    readonly property string customColorsPath: Quickshell.env("HOME") + "/.config/translator/colors.json"
    readonly property string systemColorsPath: Quickshell.env("HOME") + "/.local/state/quickshell/user/generated/colors.json"
    property string lastLoadedSignature: ""
    readonly property var defaultScheme: ({
        "background": "#141314",
        "surface": "#141314",
        "surfaceDim": "#141314",
        "surfaceBright": "#3a3939",
        "surfaceContainerLowest": "#0e0e0e",
        "surfaceContainerLow": "#1c1b1c",
        "surfaceContainer": "#201f20",
        "surfaceContainerHigh": "#2b2a2a",
        "surfaceContainerHighest": "#353435",
        "onSurface": "#e5e1e2",
        "onSurfaceVariant": "#c8c5cb",
        "primary": "#c8c5cd",
        "onPrimary": "#303036",
        "primaryContainer": "#0b0b10",
        "onPrimaryContainer": "#9c9aa1",
        "secondary": "#c9c5c9",
        "onSecondary": "#313032",
        "secondaryContainer": "#474649",
        "onSecondaryContainer": "#e3dfe2",
        "error": "#ffb4ab",
        "onError": "#690005",
        "outline": "#929095",
        "outlineVariant": "#47464b",
        "scrim": "#000000"
    })
    property var scheme: root.defaultScheme

    // Computes a deterministic checksum of file contents to skip redundant JSON parsing.
    function computeSignature(str) {
        if (!str)
            return "0";

        let hash = 0;
        for (let i = 0; i < str.length; i++) {
            hash = ((hash << 5) - hash + str.charCodeAt(i)) | 0;
        }
        return str.length + ":" + hash;
    }

    // Applies parsed JSON color tokens supporting both snake_case and camelCase with default fallbacks.
    function applyRaw(raw) {
        root.scheme = {
            "background": raw.background ?? root.defaultScheme.background,
            "surface": raw.surface ?? root.defaultScheme.surface,
            "surfaceDim": raw.surface_dim ?? raw.surfaceDim ?? root.defaultScheme.surfaceDim,
            "surfaceBright": raw.surface_bright ?? raw.surfaceBright ?? root.defaultScheme.surfaceBright,
            "surfaceContainerLowest": raw.surface_container_lowest ?? raw.surfaceContainerLowest ?? root.defaultScheme.surfaceContainerLowest,
            "surfaceContainerLow": raw.surface_container_low ?? raw.surfaceContainerLow ?? root.defaultScheme.surfaceContainerLow,
            "surfaceContainer": raw.surface_container ?? raw.surfaceContainer ?? root.defaultScheme.surfaceContainer,
            "surfaceContainerHigh": raw.surface_container_high ?? raw.surfaceContainerHigh ?? root.defaultScheme.surfaceContainerHigh,
            "surfaceContainerHighest": raw.surface_container_highest ?? raw.surfaceContainerHighest ?? root.defaultScheme.surfaceContainerHighest,
            "onSurface": raw.on_surface ?? raw.onSurface ?? root.defaultScheme.onSurface,
            "onSurfaceVariant": raw.on_surface_variant ?? raw.onSurfaceVariant ?? root.defaultScheme.onSurfaceVariant,
            "primary": raw.primary ?? root.defaultScheme.primary,
            "onPrimary": raw.on_primary ?? raw.onPrimary ?? root.defaultScheme.onPrimary,
            "primaryContainer": raw.primary_container ?? raw.primaryContainer ?? root.defaultScheme.primaryContainer,
            "onPrimaryContainer": raw.on_primary_container ?? raw.onPrimaryContainer ?? root.defaultScheme.onPrimaryContainer,
            "secondary": raw.secondary ?? root.defaultScheme.secondary,
            "onSecondary": raw.on_secondary ?? raw.onSecondary ?? root.defaultScheme.onSecondary,
            "secondaryContainer": raw.secondary_container ?? raw.secondaryContainer ?? root.defaultScheme.secondaryContainer,
            "onSecondaryContainer": raw.on_secondary_container ?? raw.onSecondaryContainer ?? root.defaultScheme.onSecondaryContainer,
            "error": raw.error ?? root.defaultScheme.error,
            "onError": raw.on_error ?? raw.onError ?? root.defaultScheme.onError,
            "outline": raw.outline ?? root.defaultScheme.outline,
            "outlineVariant": raw.outline_variant ?? raw.outlineVariant ?? root.defaultScheme.outlineVariant,
            "scrim": raw.scrim ?? root.defaultScheme.scrim
        };
    }

    // Selects the highest-priority loaded palette source and updates theme if content changed.
    function updatePalette() {
        let text = "";
        if (root.envColorsPath.length > 0 && envFile.loaded && envFile.text().length > 0)
            text = envFile.text();
        else if (customFile.loaded && customFile.text().length > 0)
            text = customFile.text();
        else if (systemFile.loaded && systemFile.text().length > 0)
            text = systemFile.text();
        if (text.length === 0) {
            if (root.lastLoadedSignature !== "") {
                root.scheme = root.defaultScheme;
                root.lastLoadedSignature = "";
            }
            return ;
        }
        const sig = root.computeSignature(text);
        if (sig === root.lastLoadedSignature)
            return ;

        try {
            root.applyRaw(JSON.parse(text));
            root.lastLoadedSignature = sig;
        } catch (e) {
            console.warn("translator/Colors: failed to parse colors palette:", e);
        }
    }

    // Forces a disk reload of all candidate color sources and reapplies the active theme.
    function refresh() {
        if (root.envColorsPath.length > 0)
            envFile.reload();

        customFile.reload();
        systemFile.reload();
        root.updatePalette();
    }

    FileView {
        id: envFile

        path: root.envColorsPath
        watchChanges: true
        onFileChanged: reload()
        onLoadedChanged: root.updatePalette()
    }

    FileView {
        id: customFile

        path: root.customColorsPath
        watchChanges: true
        onFileChanged: reload()
        onLoadedChanged: root.updatePalette()
    }

    FileView {
        id: systemFile

        path: root.systemColorsPath
        watchChanges: true
        onFileChanged: reload()
        onLoadedChanged: root.updatePalette()
    }

}
