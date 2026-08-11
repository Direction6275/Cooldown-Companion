--[[
    CooldownCompanion_Config - bridge config module files onto the main addon's private table
]]

local CONFIG_ADDON_NAME, ConfigST = ...
local CooldownCompanion = _G.CooldownCompanion
local MainST = CooldownCompanion and CooldownCompanion.ST

if not (CooldownCompanion and MainST) then
    error(CONFIG_ADDON_NAME .. " requires CooldownCompanion to be loaded first.")
end

if type(_G.SetDesaturation) ~= "function" then
    _G.SetDesaturation = function(texture, desaturated)
        if not texture then
            return
        end

        if texture.SetDesaturated then
            texture:SetDesaturated(desaturated == true)
        elseif texture.SetDesaturation then
            texture:SetDesaturation(desaturated and 1 or 0)
        end
    end
end

setmetatable(ConfigST, {
    __index = MainST,
    __newindex = MainST,
})

MainST.ConfigAddonName = CONFIG_ADDON_NAME
