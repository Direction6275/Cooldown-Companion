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

function I.UsesSourceSounds(group)
    local settings = I.Settings(group)
    if not settings then return false end
    local source = I.Primary(group)
    return settings.tracking == "aura" or (settings.sourceSounds == true and source and source.type == "spell") or false
end

function I.Primary(group)
    return I.Settings(group) and group.buttons and group.buttons[1]
end

-- Saved slot one owns the display; runtime lists omit unavailable entries.
-- Never substitute the first surviving condition for a missing source.
function I.RuntimeSource(frame, group)
    local source = I.Primary(group)
    if not source then return end
    for _, button in ipairs(frame and frame.buttons or {}) do
        if button.buttonData == source then return button end
    end
end

-- Generic entry actions may remove conditions or the complete source set.
-- A partial removal of the primary would silently promote another condition.
function I.GetRemovalError(group, entries)
    local source = I.Primary(group)
    if not source then return end
    local removing = {}
    for _, entry in ipairs(entries) do removing[entry] = true end
    if not removing[source] then return end
    for _, entry in ipairs(group.buttons) do
        if not removing[entry] then
            return "Change or clear this Indicator's source in Tracking before removing it."
        end
    end
end

I.EffectOrder = {"pulse", "colorShift", "shrinkExpand", "bounce"}
I.EffectFailureText = {
    indicator_effects_legacy = "This older Indicator template does not identify its active effects. Update it from the original panel before applying it.",
    indicator_effects_multiple = "Aura Indicators support one visual effect. Turn off extra effects before choosing an aura source or copying these settings.",
    indicator_effects_conditions = "Conditional visual effects require a spell or item source. Choose Always and turn off Only In Combat for each effect before choosing an aura source.",
    indicator_effects_text = "This effect cannot run with the destination's Text Only display. Choose Icon or Texture, or turn off the effect first.",
}

-- Pure reader for validation and snapshots. Before the unified store existed,
-- only the active source family owned effects; the other store was dormant.
function I.ReadEffects(group)
    local settings = I.Settings(group) or {}
    if settings.effectVersion == 1 then return settings.effects or {}, settings.effectSelection end
    if group.templateVersion and settings.tracking == nil then
        return nil, nil, "indicator_effects_legacy"
    end
    if settings.tracking ~= "aura" then return settings.effects or {} end
    local legacy = group.style and group.style.textureIndicators and group.style.textureIndicators.aura or {}
    local aura = Addon.NormalizeTextureIndicatorSection("aura", CopyTable(legacy))
    local key = aura.effectType
    local effects = {}
    for _, effectKey in ipairs(I.EffectOrder) do
        -- The old single selector shared duration/color between choices.
        effects[effectKey] = {enabled = effectKey == key and aura.enabled == true, speed = aura.speed}
        if effectKey == "colorShift" then effects[effectKey].color = CopyTable(aura.color) end
    end
    return effects, key
end

local function StoreEffects(group, effects, selection)
    local settings = I.Settings(group)
    settings.effects = CopyTable(effects)
    settings.effectSelection = selection
    settings.effectVersion = 1
    if group.style then group.style.textureIndicators = nil end
    return settings.effects
end
I.SetEffects = StoreEffects

function I.Effects(group)
    local settings = I.Settings(group)
    if not settings then return end
    if settings.effectVersion == 1 then return settings.effects end
    local effects, selection = I.ReadEffects(group)
    if effects then return StoreEffects(group, effects, selection) end
end

-- Empty panels defer capability checks until their first source is known.
-- Display switching still retains dormant effects, as the editor advertises;
-- transfers must not introduce an effect that the destination cannot render.
function I.CheckEffects(effects, tracking, displayType)
    if not tracking then return true end
    local count = 0
    for _, key in ipairs(I.EffectOrder) do
        if effects[key] and effects[key].enabled == true then
            count = count + 1
            if tracking == "aura" and ((effects[key].activation or "always") ~= "always" or effects[key].combatOnly) then
                return false, "indicator_effects_conditions"
            end
        end
    end
    if tracking == "aura" and count > 1 then return false, "indicator_effects_multiple" end
    local unavailable = tracking == "aura" and "colorShift" or "shrinkExpand"
    if displayType == "text" and effects[unavailable] and effects[unavailable].enabled == true then
        return false, "indicator_effects_text"
    end
    return true
end

function I.CanApplyEffects(source, destination, appearance)
    local effects, _, reason = I.ReadEffects(source)
    if not effects then return false, reason end
    local saved, target = I.Settings(source) or {}, I.Settings(destination) or {}
    return I.CheckEffects(effects, I.Primary(destination) and target.tracking,
        appearance and saved.displayType or target.displayType)
end

function I.CheckSourceEffects(group, source)
    local effects, _, reason = I.ReadEffects(group)
    if not effects then return false, reason end
    return I.CheckEffects(effects, source.addedAs == "aura" and "aura" or "conditions",
        (I.Settings(group) or {}).displayType)
end

-- The native aura renderer consumes one selected effect. This is a derived
-- description, never a second saved store. Config commits edits explicitly.
function I.NativeEffect(group)
    I.Effects(group)
    local settings = I.Settings(group)
    local effects = Addon.NormalizeTriggerPanelEffectStore(settings)
    local selected = settings.effectSelection or "pulse"
    for _, key in ipairs(I.EffectOrder) do
        if effects[key].enabled then selected = key; break end
    end
    local effect = effects[selected] or {}
    return {effectType = selected, enabled = effect.enabled == true,
        speed = effect.speed, color = effect.color and CopyTable(effect.color), combatOnly = false}
end

function I.SelectNativeEffect(group, key, enabled)
    local effects = I.Effects(group)
    for _, effect in pairs(effects) do effect.enabled = false end
    if effects[key] then effects[key].enabled = enabled == true end
    I.Settings(group).effectSelection = key
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

local function NormalizeCountReadouts(group)
    local settings, source = I.Settings(group), I.Primary(group)
    if not settings or not source then return end
    local count = I.IsAura(group) and "stacks" or source.type == "spell" and "charges" or "item"
    local function adaptReadouts(readouts)
        if readouts and readouts.count and readouts.count ~= "none" then readouts.count = count end
    end
    adaptReadouts(settings.readouts)
    for _, readouts in pairs(settings.readoutsByDisplay or {}) do adaptReadouts(readouts) end
end

function I.OnSourceAdded(group, entry)
    if ST.IsIndicatorGroup(group) and (not I.Primary(group) or I.Primary(group) == entry) then
        local allowed, reason = I.CheckSourceEffects(group, entry)
        if not allowed then return false, reason end
    end
    local settings = I.Initialize(group)
    if not settings then return true end
    I.Effects(group) -- Capture the previous family before tracking changes.
    if entry.enabled == nil then entry.enabled = true end
    if I.Primary(group) == entry then
        I.NormalizeSourceEnablement(group)
        settings.tracking = entry.addedAs == "aura" and "aura" or "conditions"
        if settings.tracking == "aura" then
            entry.textureAuraDisplayEnabled = true
        end
        NormalizeCountReadouts(group)
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
    return true
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
function I.NativeSettings(group, resolvedIcon)
    local settings = I.Settings(group)
    if not settings then return end
    if settings.displayType == "texture" then
        return Addon:GetTexturePanelSettings(group, true)
    end
    local visual = { enabled = true, sourceType = "file", sourceValue = "Interface\\Buttons\\WHITE8x8",
        blendMode = "BLEND", locationType = "CENTER", color = {1, 1, 1, 1} }
    if settings.displayType == "icon" then
        local icon = resolvedIcon or I.IconSettings(group)
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
        if source.addedAs == "aura" and (I.Primary(group) or #entries > 1) then
            return "Aura displays cannot be combined with conditions. Create an aura Indicator instead."
        end
        if not I.Primary(group) then
            local allowed, reason = I.CheckSourceEffects(group, source)
            if not allowed then return I.EffectFailureText[reason] end
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
    for _, button in ipairs(frame.buttons or {}) do runtime[button.buttonData] = button end
    if not runtime[primary] then return false end
    if settings.sourceVisibility and runtime[primary]._rawVisibilityHidden then return false end
    for _, entry in ipairs(group.buttons or {}) do
        if entry.enabled ~= false then
            if not runtime[entry] then return false end
            for _, clause in ipairs(entry.triggerConditions or {}) do
                if clause.unavailable or not I.ConditionKeys[clause.key] then return false end
                local actual = ST._AT.EvaluateTriggerRowCondition(runtime[entry], clause.key, true)
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
    local settings = I.Initialize(group)
    I.Effects(group)
    group.buttons = {}
    settings.tracking = "conditions"
end

-- Build a replacement off to the side. Failed validation must leave the
-- current source and its conditions intact until the add actually succeeds.
function I.StageSourceReplacement(group, expectedSource)
    if not ST.IsIndicatorGroup(group) or I.Primary(group) ~= expectedSource then return end
    local candidate = {}
    for key, value in pairs(group) do candidate[key] = value end
    candidate.buttons = {}
    candidate.indicatorSettings = CopyTable(I.Settings(group))
    candidate.style = group.style and CopyTable(group.style)
    local effects, selection = I.ReadEffects(group)
    StoreEffects(candidate, effects, selection)
    candidate.indicatorSettings.tracking = "conditions"
    return candidate
end

function I.CommitSourceReplacement(group, candidate)
    local allowed, reason = I.CheckSourceEffects(candidate, I.Primary(candidate))
    if not allowed then return false, reason end
    group.buttons = candidate.buttons
    local settings = I.Settings(group)
    settings.tracking = I.Settings(candidate).tracking
    StoreEffects(group, I.Effects(candidate), I.Settings(candidate).effectSelection)
    NormalizeCountReadouts(group)
    return true
end

local SIGNAL_APPEARANCE = {"sourceType","sourceValue","mediaType","label","scale","alpha","blendMode",
    "rotation","stretchX","stretchY","color","locationType","pairSpacing","width","height"}
local PRESENTATION_FIELDS = {"displayType","icon","text","readouts","readoutsByDisplay","progress"}

function I.CapturePresentation(group)
    local settings = I.Settings(group)
    if not settings then return end
    local copy = {signal={}}
    for _, key in ipairs(PRESENTATION_FIELDS) do copy[key] = type(settings[key]) == "table" and CopyTable(settings[key]) or settings[key] end
    for _, key in ipairs(SIGNAL_APPEARANCE) do
        local value = settings.signal[key]
        copy.signal[key] = type(value) == "table" and CopyTable(value) or value
    end
    local effects, selection = I.ReadEffects(group)
    copy.effects = CopyTable(effects)
    copy.effectSelection, copy.effectVersion = selection, 1
    return copy
end

function I.ApplyPresentation(source, destination, appearance, effects)
    if effects then
        local allowed, reason = I.CanApplyEffects(source, destination, appearance)
        if not allowed then return false, reason end
    end
    local saved, target = I.Settings(source), I.Initialize(destination)
    if not saved or not target then return false end
    if appearance then
        for _, key in ipairs(PRESENTATION_FIELDS) do
            target[key] = type(saved[key]) == "table" and CopyTable(saved[key]) or saved[key]
        end
        for _, key in ipairs(SIGNAL_APPEARANCE) do
            local value = (saved.signal or {})[key]
            target.signal[key] = type(value) == "table" and CopyTable(value) or value
        end
    end
    if effects then
        local store, selection = I.ReadEffects(source)
        StoreEffects(destination, store, selection)
    end
    I.Initialize(destination)
    if appearance then NormalizeCountReadouts(destination) end
    return true
end
