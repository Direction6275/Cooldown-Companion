--[[
    CooldownCompanion_Config - bridge config module files onto the main addon's private table
]]

local CONFIG_ADDON_NAME, ConfigST = ...
local CooldownCompanion = _G.CooldownCompanion
local MainST = CooldownCompanion and CooldownCompanion.ST

if not (CooldownCompanion and MainST) then
    error(CONFIG_ADDON_NAME .. " requires CooldownCompanion to be loaded first.")
end

setmetatable(ConfigST, {
    __index = MainST,
    __newindex = MainST,
})

MainST.ConfigAddonName = CONFIG_ADDON_NAME
