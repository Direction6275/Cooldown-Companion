--[[
    CooldownCompanion - Config/Column3
    RefreshColumn3 (button settings column).
    Thin wrapper — the actual rendering lives in ConfigSettings/ButtonSettings.lua.
]]

local ADDON_NAME, ST = ...

------------------------------------------------------------------------
-- COLUMN 3: Button Settings
------------------------------------------------------------------------
local function RefreshColumn3()
    ST._RefreshButtonSettingsColumn()
end

------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
ST._RefreshColumn3 = RefreshColumn3
