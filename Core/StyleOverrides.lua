--[[
    CooldownCompanion - Core/StyleOverrides.lua: GetEffectiveStyle, PromoteSection, RevertSection, HasStyleOverrides
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

------------------------------------------------------------------------
-- EFFECTIVE STYLE UTILITIES
------------------------------------------------------------------------

--- Compute the effective style for a button, merging per-button overrides
--- with group defaults via metatable __index fallback.
function CooldownCompanion:GetEffectiveStyle(groupStyle, buttonData)
    if buttonData and buttonData.styleOverrides
       and buttonData.overrideSections and next(buttonData.overrideSections) then
        return setmetatable(buttonData.styleOverrides, { __index = groupStyle })
    end
    return groupStyle
end

--- Promote a section: copy current group values into buttonData.styleOverrides,
--- mark the section as active in overrideSections.
function CooldownCompanion:PromoteSection(buttonData, groupStyle, sectionId)
    local section = ST.OVERRIDE_SECTIONS[sectionId]
    if not section then return end

    if not buttonData.styleOverrides then buttonData.styleOverrides = {} end
    if not buttonData.overrideSections then buttonData.overrideSections = {} end

    -- Copy current group values into overrides
    for _, key in ipairs(section.keys) do
        local val = groupStyle[key]
        if type(val) == "table" then
            buttonData.styleOverrides[key] = CopyTable(val)
        else
            buttonData.styleOverrides[key] = val
        end
    end

    buttonData.overrideSections[sectionId] = true
end

--- Revert a section: remove section keys from styleOverrides,
--- clear the section from overrideSections.
function CooldownCompanion:RevertSection(buttonData, sectionId)
    local section = ST.OVERRIDE_SECTIONS[sectionId]
    if not section then return end

    if buttonData.styleOverrides then
        for _, key in ipairs(section.keys) do
            buttonData.styleOverrides[key] = nil
        end
        -- Clean up empty styleOverrides table
        if not next(buttonData.styleOverrides) then
            buttonData.styleOverrides = nil
        end
    end

    if buttonData.overrideSections then
        buttonData.overrideSections[sectionId] = nil
        if not next(buttonData.overrideSections) then
            buttonData.overrideSections = nil
        end
    end
end

--- Check if a button has any active style overrides.
function CooldownCompanion:HasStyleOverrides(buttonData)
    return buttonData and buttonData.overrideSections and next(buttonData.overrideSections) ~= nil
end
