-- Omarchy Cursor binding for Omarchy 4 / Hyprland's Lua configuration.
-- Add this block to ~/.config/hypr/bindings.lua after enabling the plugin.

local omarchy_cursor_id = "vegonza.omarchy-cursor"

hl.unbind("SUPER + N")
o.bind(
  "SUPER + N",
  "Cursor project picker",
  "omarchy-shell shell toggle " .. omarchy_cursor_id .. " '{}'"
)
