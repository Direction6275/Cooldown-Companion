--[[
    CooldownCompanion - ResourceBarPanelsLayoutOrder
    Registers the dedicated visual preview renderer as the Layout & Order panel.
]]

local ADDON_NAME, ST = ...

local function BuildLayoutOrderPanel(container)
    ST._BuildLayoutOrderPreviewPanel(container)
end

ST._BuildLayoutOrderPanel = BuildLayoutOrderPanel
