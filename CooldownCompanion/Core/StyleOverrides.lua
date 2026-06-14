--[[
    CooldownCompanion - Core/StyleOverrides.lua: GetEffectiveStyle, PromoteSection, RevertSection, HasStyleOverrides
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local effectiveStyleCache = setmetatable({}, { __mode = "k" })

local function PruneDisallowedOverrideSections(buttonData)
    if not (buttonData and buttonData.overrideSections) then
        return
    end
    if not ST.CanButtonUseOverrideSection then
        return
    end

    local changed = false
    for sectionId in pairs(buttonData.overrideSections) do
        if not ST.CanButtonUseOverrideSection(buttonData, sectionId) then
            local section = ST.OVERRIDE_SECTIONS[sectionId]
            if section and buttonData.styleOverrides then
                for _, key in ipairs(section.keys) do
                    buttonData.styleOverrides[key] = nil
                end
            end
            buttonData.overrideSections[sectionId] = nil
            changed = true
        end
    end

    if changed then
        if buttonData.styleOverrides and not next(buttonData.styleOverrides) then
            buttonData.styleOverrides = nil
        end
        if buttonData.overrideSections and not next(buttonData.overrideSections) then
            buttonData.overrideSections = nil
        end
    end
end

------------------------------------------------------------------------
-- EFFECTIVE STYLE UTILITIES
------------------------------------------------------------------------

--- Compute the effective style for a button, merging per-button overrides
--- with group defaults via metatable __index fallback.
function CooldownCompanion:GetEffectiveStyle(groupStyle, buttonData)
    PruneDisallowedOverrideSections(buttonData)

    if buttonData and buttonData.styleOverrides
       and buttonData.overrideSections and next(buttonData.overrideSections) then
        local cache = effectiveStyleCache[buttonData]
        if not cache then
            cache = {}
            effectiveStyleCache[buttonData] = cache
        end
        if cache.groupStyle ~= groupStyle or cache.overrides ~= buttonData.styleOverrides then
            setmetatable(buttonData.styleOverrides, { __index = groupStyle })
            cache.groupStyle = groupStyle
            cache.overrides = buttonData.styleOverrides
        end
        return buttonData.styleOverrides
    end
    if buttonData then
        effectiveStyleCache[buttonData] = nil
    end
    return groupStyle
end

--- Promote a section: copy current group values into buttonData.styleOverrides,
--- mark the section as active in overrideSections.
function CooldownCompanion:PromoteSection(buttonData, groupStyle, sectionId)
    local section = ST.OVERRIDE_SECTIONS[sectionId]
    if not section then return end
    if ST.CanButtonUseOverrideSection and not ST.CanButtonUseOverrideSection(buttonData, sectionId) then
        return
    end

    if not buttonData.styleOverrides then buttonData.styleOverrides = {} end
    if not buttonData.overrideSections then buttonData.overrideSections = {} end

    -- Copy current group values into overrides
    for _, key in ipairs(section.keys) do
        local val = groupStyle[key]
        if val == nil and section.defaults then
            val = section.defaults[key]
        end
        if key == "unusableVisualMode" then
            val = ST.GetUnusableVisualMode(groupStyle)
        end
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
    PruneDisallowedOverrideSections(buttonData)
    return buttonData and buttonData.overrideSections and next(buttonData.overrideSections) ~= nil
end
