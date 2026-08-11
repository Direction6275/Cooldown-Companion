--[[
    CooldownCompanion - ResourceBarPanelsLayoutOrder
    Registers the dedicated visual preview renderer as the Layout & Order panel.
]]

local ADDON_NAME, ST = ...

local function BuildLayoutOrderPanel(container, opts)
    ST._BuildLayoutOrderPreviewPanel(container, opts)
end

ST._BuildLayoutOrderPanel = BuildLayoutOrderPanel
