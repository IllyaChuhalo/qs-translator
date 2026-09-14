-- Add into ~/.config/hypr/custom/keybinds.lua (survives ii updates).
--
-- SUPER+T is already taken by the terminal in the base keybinds.lua,
-- so this uses SUPER+ALT+T instead (confirmed free against your base
-- config). Pick something else if you'd rather — just grep your
-- hyprland/keybinds.lua and custom/keybinds.lua for the combo first.
--
-- The fallback handles first-ever invocation: if the resident
-- `translator` process isn't running yet, ipc call fails, so we
-- launch it, give it a moment to come up, then toggle it visible.
hl.bind("SUPER + ALT + T",
    hl.dsp.exec_cmd(
        "qs -c translator ipc call translator toggle || " ..
        "(qs -c translator & sleep 0.3; qs -c translator ipc call translator toggle)"
    ),
    { description = "Shell: Toggle translator popup" }
)
