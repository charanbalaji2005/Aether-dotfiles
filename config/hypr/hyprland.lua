-- AetherOS — Hyprland entry point (Hyprland 0.57+, Lua configuration)
--
-- Hyprland 0.57 loads this file instead of hyprland.conf. The AetherOS
-- configuration still lives in hyprland.conf and the fragments it sources
-- (the `aether` tools keep regenerating those), so this file only hands
-- them to the compatibility layer in lua/aether_compat.lua.
--
-- Problems found while loading: ~/.local/state/aether/hypr-lua.log
-- Your own Lua settings: add them at the end of this file.

local dir = os.getenv("HOME") .. "/.config/hypr"
local compat = dofile(dir .. "/lua/aether_compat.lua")

compat.load(dir .. "/hyprland.conf")
compat.finish()
