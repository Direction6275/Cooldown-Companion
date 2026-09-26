-- Indicator identity and saved presentation. Aura state never enters this model.
local _, ST = ...
local Addon = ST.Addon
local I = {}
ST.Indicator = I

function ST.IsIndicatorGroup(group)
    return type(group) == "table" and group.displayMode == "indicator"
end

function I.Settings(group)
    return ST.IsIndicatorGroup(group) and group.indicatorSettings or nil
end

function I.IsAura(group)
    local settings = I.Settings(group)
    return settings and settings.tracking == "aura" or false
end

function I.Primary(group)
    local settings = I.Settings(group)
    return settings and group.buttons and group.buttons[settings.primaryEntry or 1]
end

local function NewReadouts(displayType)
    return {
        label = displayType == "text" and "name" or "none", timer = displayType == "text",
        count = "none", customText = "",
        labelAnchor = "TOP", labelX = 0, labelY = 0,
        timerAnchor = "CENTER", timerX = 0, timerY = 0,
        countAnchor = "BOTTOM", countX = 0, countY = 0,
        durationFormat = "clock",
    }
end

function I.Initialize(group)
    if not ST.IsIndicatorGroup(group) then return end
    local settings = group.indicatorSettings
    if type(settings) ~= "table" then settings = {}; group.indicatorSettings = settings end
    settings.version = settings.version or 1
    settings.primaryEntry = settings.primaryEntry or 1
    settings.tracking = settings.tracking or "conditions"
    settings.displayType = settings.displayType or "icon"
    settings.signal = settings.signal or {
        blendMode = "BLEND", point = "CENTER", relativePoint = "CENTER",
        relativeTo = "UIParent", x = 0, y = 0, locationType = "CENTER",
    }
    settings.icon = settings.icon or {
        maintainAspectRatio = true, buttonSize = 36, iconWidth = 36, iconHeight = 36,
        iconZoom = 0, borderSize = 1, borderColor = {0, 0, 0, 1},
        iconTintColor = {1, 1, 1, 1}, backgroundColor = {0, 0, 0, 0.5},
    }
    settings.text = settings.text or {
        value = "", textFont = "Friz Quadrata TT", textFontSize = 20,
        textFontOutline = "OUTLINE", textFontColor = {1, 1, 1, 1},
        textBgColor = {0, 0, 0, 0}, width = 180, height = 48,
    }
    settings.readouts = settings.readouts or NewReadouts()
    settings.progress = settings.progress or { enabled = false, direction = "down", dimAlpha = 0.35 }
    settings.effects = settings.effects or {}
    return settings
end

-- The primary source follows panel enablement. Preserve an old disabled source
-- as a disabled panel, so removing the redundant source toggle cannot trap it.
function I.NormalizeSourceEnablement(group)
    local source = I.Primary(group)
    if source and source.enabled == false then
        group.enabled = false
        source.enabled = true
    end
end

function I.OnSourceAdded(group, entry)
    local settings = I.Initialize(group)
    if not settings then return end
    if entry.enabled == nil then entry.enabled = true end
    if I.Primary(group) == entry then
        I.NormalizeSourceEnablement(group)
        settings.tracking = entry.addedAs == "aura" and "aura" or "conditions"
        if settings.tracking == "aura" then
            entry.textureAuraDisplayEnabled = true
        end
    end
    if not I.IsAura(group) and entry.triggerConditions == nil then
        if entry.triggerCondition then
            -- Moving a source preserves its existing rule, including an
            -- unsupported rule that must stay fail-closed until edited.
            entry.triggerConditions = {{key = entry.triggerCondition,
                expected = entry.triggerExpected, state = entry.triggerState}}
        else
            entry.triggerConditions = {{key = "cooldownActive", expected = false}}
            entry.triggerCondition, entry.triggerExpected = "cooldownActive", false
        end
    end
end

function I.IconSettings(group)
    local settings = I.Settings(group)
    if not settings then return end
    local icon = Addon.NormalizeTriggerIconSettings(CopyTable(settings.icon))
    local source = I.Primary(group)
    if not icon.manualIcon and source then
        icon.manualIcon = source.manualIcon
        if not icon.manualIcon and source.type == "spell" then
            icon.manualIcon = C_Spell.GetSpellTexture(source.id)
        elseif not icon.manualIcon and Addon.ResolveEffectiveItem then
            local item = Addon.ResolveEffectiveItem(source, false)
            icon.manualIcon = item and item.icon
        end
    end
    return icon
end

-- A render description only. Saved placement always belongs to signal.
function I.NativeSettings(group)
    local settings = I.Settings(group)
    if not settings then return end
    if settings.displayType == "texture" then
        return Addon:GetTexturePanelSettings(group, true)
    end
    local visual = { enabled = true, sourceType = "file", sourceValue = "Interface\\Buttons\\WHITE8x8",
        blendMode = "BLEND", locationType = "CENTER", color = {1, 1, 1, 1} }
    if settings.displayType == "icon" then
        local icon = I.IconSettings(group)
        visual.sourceValue = icon.manualIcon
        visual.width, visual.height = Addon.GetTriggerIconDimensions(icon)
        visual.enabled = icon.manualIcon ~= nil
    else
        visual.width, visual.height = settings.text.width or 180, settings.text.height or 48
        visual.color = {1, 1, 1, 0}
    end
    return visual
end

function I.Label(group)
    local settings = I.Settings(group)
    local readouts = settings and settings.readouts
    if not readouts then return "" end
    if readouts.label == "custom" then return readouts.customText or settings.text.value or "" end
    if readouts.label == "name" then
        local source = I.Primary(group)
        return source and source.name or ""
    end
    return ""
end

function I.SetDisplayType(group, displayType)
    local settings = I.Initialize(group)
    if not settings or (displayType ~= "texture" and displayType ~= "icon" and displayType ~= "text") then return end
    if settings.displayType == displayType then return end
    settings.readoutsByDisplay = settings.readoutsByDisplay or {}
    settings.readoutsByDisplay[settings.displayType] = CopyTable(settings.readouts)
    settings.readouts = CopyTable(settings.readoutsByDisplay[displayType] or NewReadouts(displayType))
    settings.displayType = displayType
end

function I.AddRestriction(group, entry)
    if not ST.IsIndicatorGroup(group) then return end
    if I.Primary(group) and I.IsAura(group) then return "This Indicator already tracks an aura. Replace its source in Tracking." end
    local entries = entry and (entry[1] and entry or {entry}) or {}
    for _, source in ipairs(entries) do
        if source.addedAs == "aura" and (source.auraTrackGroup or source.auraTrackPet) then
            return "Indicators support Player or Target aura sources. Change this aura's scope before moving it."
        end
        if source.addedAs == "aura" and (I.Primary(group) or #entries > 1) then
            return "Aura displays cannot be combined with conditions. Create an aura Indicator instead."
        end
    end
end

I.ConditionKeys = {cooldownActive=true, procActive=true, rangeActive=true, usable=true,
    chargesRecharging=true, chargeState=true, countTextActive=true, countState=true}

function I.Match(frame, group)
    local settings = I.Settings(group)
    if not settings or I.IsAura(group) then return false end
    local primary = I.Primary(group)
    if not primary then return false end
    local runtime = {}
    for _, button in ipairs(frame.buttons or {}) do runtime[button.index] = button end
    if not runtime[settings.primaryEntry or 1] then return false end
    for index, entry in ipairs(group.buttons or {}) do
        if entry.enabled ~= false then
            if not runtime[index] then return false end
            for _, clause in ipairs(entry.triggerConditions or {}) do
                if not I.ConditionKeys[clause.key] then return false end
                local actual = ST._AT.EvaluateTriggerRowCondition(runtime[index], clause.key, true)
                if issecretvalue(actual) or actual == nil then return false end
                local expected = clause.state
                if expected == nil then expected = clause.expected ~= false end
                if actual ~= expected then return false end
            end
        end
    end
    -- Empty rules deliberately mean Always, provided the source is available.
    return primary.enabled ~= false
end

function I.ClearSource(group)
    group.buttons = {}
    local settings = I.Initialize(group)
    settings.primaryEntry, settings.tracking = 1, "conditions"
end

-- Build a replacement off to the side. Failed validation must leave the
-- current source and its conditions intact until the add actually succeeds.
function I.StageSourceReplacement(group, expectedSource)
    if not ST.IsIndicatorGroup(group) or I.Primary(group) ~= expectedSource then return end
    local candidate = {}
    for key, value in pairs(group) do candidate[key] = value end
    candidate.buttons = {}
    candidate.indicatorSettings = CopyTable(I.Settings(group))
    candidate.indicatorSettings.primaryEntry = 1
    candidate.indicatorSettings.tracking = "conditions"
    return candidate
end

function I.CommitSourceReplacement(group, candidate)
    group.buttons = candidate.buttons
    local settings = I.Settings(group)
    settings.primaryEntry = 1
    settings.tracking = I.Settings(candidate).tracking
    local source = I.Primary(group)
    local count = I.IsAura(group) and "stacks" or source.type == "spell" and "charges" or "item"
    local function adaptReadouts(readouts)
        if readouts and readouts.count and readouts.count ~= "none" then readouts.count = count end
    end
    adaptReadouts(settings.readouts)
    for _, readouts in pairs(settings.readoutsByDisplay or {}) do adaptReadouts(readouts) end
end

local SIGNAL_APPEARANCE = {"sourceType","sourceValue","mediaType","label","scale","alpha","blendMode",
    "rotation","stretchX","stretchY","color","locationType","pairSpacing","width","height"}
local PRESENTATION_FIELDS = {"displayType","icon","text","readouts","readoutsByDisplay","progress","legacyTextMetrics"}

function I.CapturePresentation(group)
    local settings = I.Settings(group)
    if not settings then return end
    local copy = {signal={}}
    for _, key in ipairs(PRESENTATION_FIELDS) do copy[key] = type(settings[key]) == "table" and CopyTable(settings[key]) or settings[key] end
    for _, key in ipairs(SIGNAL_APPEARANCE) do
        local value = settings.signal[key]
        copy.signal[key] = type(value) == "table" and CopyTable(value) or value
    end
    copy.effects = CopyTable(settings.effects or {})
    return copy
end

function I.ApplyPresentation(source, destination, appearance, effects)
    local saved, target = I.Settings(source), I.Initialize(destination)
    if not saved or not target then return end
    if appearance then
        for _, key in ipairs(PRESENTATION_FIELDS) do
            target[key] = type(saved[key]) == "table" and CopyTable(saved[key]) or saved[key]
        end
        for _, key in ipairs(SIGNAL_APPEARANCE) do
            local value = (saved.signal or {})[key]
            target.signal[key] = type(value) == "table" and CopyTable(value) or value
        end
    end
    if effects then target.effects = CopyTable(saved.effects or {}) end
    I.Initialize(destination)
end
