--[[
    CooldownCompanion - Core/StyleOverrides.lua: GetEffectiveStyle, PromoteSection, RevertSection, HasStyleOverrides
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local effectiveStyleCache = setmetatable({}, { __mode = "k" })
local DEFAULT_BAR_AURA_FILL_COLOR = { 0.2, 1.0, 0.2, 1.0 }

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

-- Active aura fills preserve an entry's visual identity unless that entry
-- explicitly owns its Active Aura Indicator color. The effective style may
-- inherit from the panel through __index, so source precedence must read the
-- saved override table and section ownership directly.
--
-- A whole Aura Panel has no resting/base fill and exposes no barColor section.
-- Entries keep that override when moved so it can return on an ordinary bar
-- panel, but it must not influence the Aura Panel while stored out of scope.
function ST.ResolveBarAuraFillColor(style, buttonData, isWholeAuraPanel)
    local sections = buttonData and buttonData.overrideSections
    local overrides = buttonData and buttonData.styleOverrides
    if sections and overrides then
        if sections.barActiveAura then
            local color = rawget(overrides, "barAuraColor")
            if color then return color end
        end
        if not isWholeAuraPanel and sections.barColor then
            local color = rawget(overrides, "barColor")
            if color then return color end
        end
    end
    return (style and style.barAuraColor) or DEFAULT_BAR_AURA_FILL_COLOR
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

--- Copy a customized section from one entry to another: the target ends up
--- with exactly the source's effective section values, overwriting anything
--- it already had for the section. Returns true only when the copy actually
--- wrote; callers must not report success on a falsy return.
function CooldownCompanion:CopySectionOverride(sourceButtonData, sourceGroupStyle, targetButtonData, sectionId)
    local section = ST.OVERRIDE_SECTIONS[sectionId]
    if not section then return false end
    if not (sourceButtonData and sourceButtonData.styleOverrides
        and sourceButtonData.overrideSections
        and sourceButtonData.overrideSections[sectionId]) then
        return false
    end
    if ST.CanButtonUseOverrideSection and not ST.CanButtonUseOverrideSection(targetButtonData, sectionId) then
        return false
    end

    if not targetButtonData.styleOverrides then targetButtonData.styleOverrides = {} end
    if not targetButtonData.overrideSections then targetButtonData.overrideSections = {} end

    local sourceOverrides = sourceButtonData.styleOverrides
    for _, key in ipairs(section.keys) do
        -- rawget: GetEffectiveStyle aliases the source's overrides to its own
        -- group style via __index, so a plain read of a key this section
        -- gained after the source's promote would leak the source PANEL's
        -- value while looking like a stored override. The explicit fallback
        -- below copies what the source actually renders with instead.
        local val = rawget(sourceOverrides, key)
        if val == nil then
            if key == "unusableVisualMode" and sourceGroupStyle then
                val = ST.GetUnusableVisualMode(sourceGroupStyle)
            else
                val = sourceGroupStyle and sourceGroupStyle[key]
                if val == nil and section.defaults then
                    val = section.defaults[key]
                end
            end
        end
        if type(val) == "table" then
            targetButtonData.styleOverrides[key] = CopyTable(val)
        else
            targetButtonData.styleOverrides[key] = val
        end
    end

    targetButtonData.overrideSections[sectionId] = true
    return true
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
