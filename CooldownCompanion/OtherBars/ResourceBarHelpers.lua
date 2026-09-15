--[[
    CooldownCompanion - ResourceBarHelpers
    Pure query/helper functions with no mutable state writes (aside from
    auto-vivification of config tables and a power-type secrecy memoization
    cache). Used by both ResourceBar.lua and ResourceBarVisuals.lua at runtime.

    All functions are added to ST._RB so consuming files can alias them to
    locals at load time.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local math_floor = math.floor
local string_format = string.format
local table_sort = table.sort
local SecretsAPI = C_Secrets

-- Import constants from ResourceBarConstants
local RB = ST._RB
local SEGMENTED_TYPES = RB.SEGMENTED_TYPES
local DEFAULT_POWER_COLORS = RB.DEFAULT_POWER_COLORS
local RESOURCE_COLOR_DEFS = RB.RESOURCE_COLOR_DEFS
local RESOURCE_MAELSTROM_WEAPON = RB.RESOURCE_MAELSTROM_WEAPON
local DEFAULT_SEG_THRESHOLD_COLOR = RB.DEFAULT_SEG_THRESHOLD_COLOR
local DEFAULT_CONTINUOUS_TICK_MODE = RB.DEFAULT_CONTINUOUS_TICK_MODE
local DEFAULT_CONTINUOUS_TICK_PERCENT = RB.DEFAULT_CONTINUOUS_TICK_PERCENT
local DEFAULT_CONTINUOUS_TICK_ABSOLUTE = RB.DEFAULT_CONTINUOUS_TICK_ABSOLUTE
local DEFAULT_CONTINUOUS_TICK_WIDTH = RB.DEFAULT_CONTINUOUS_TICK_WIDTH
local DEFAULT_CONTINUOUS_TICK_COLOR = RB.DEFAULT_CONTINUOUS_TICK_COLOR
local RESOURCE_HEALTH = RB.RESOURCE_HEALTH
local CLASS_RESOURCES = RB.CLASS_RESOURCES
local SPEC_RESOURCES = RB.SPEC_RESOURCES
local DRUID_PERSISTENT_RESOURCES_BY_SPEC = RB.DRUID_PERSISTENT_RESOURCES_BY_SPEC
local DRUID_FORM_RESOURCES = RB.DRUID_FORM_RESOURCES
local DRUID_DEFAULT_RESOURCES = RB.DRUID_DEFAULT_RESOURCES
local DRUID_BALANCE_SPEC_ID = 102
local MAX_RESOURCE_THRESHOLD_TICK_ENTRIES = 3

local ResolveSpecOverrideKey = ST._ResolveSpecOverrideKey

local RESOURCE_DISPLAY_PROFILE_KEYS = {
    "barTexture",
    "classBarBrightness",
    "backgroundColor",
    "borderStyle",
    "borderColor",
    "borderSize",
    "borderRenderMode",
    "segmentedSmoothing",
}

local RESOURCE_TEXT_DISPLAY_KEYS = {
    "showText",
    "textFormat",
    "textFont",
    "textFontSize",
    "textFontOutline",
    "textFontColor",
    "textAnchor",
    "textXOffset",
    "textYOffset",
    "hideTextAtZero",
    "showRechargeText",
    "rechargeTextMode",
    "rechargeTextFont",
    "rechargeTextFontSize",
    "rechargeTextFontOutline",
    "rechargeTextFontColor",
    "rechargeTextAnchor",
    "rechargeTextXOffset",
    "rechargeTextYOffset",
}

local RESOURCE_HEALTH_DISPLAY_KEYS = {
    "healthBarColor",
    "healthBarOpacity",
    "healthBarGradient",
    "healthBarFullColor",
    "healthBarHalfColor",
    "healthBarLowColor",
    "healthBackgroundColor",
    "healthBackgroundGradient",
    "healthBackgroundFullColor",
    "healthBackgroundHalfColor",
    "healthBackgroundLowColor",
    "healthBackgroundOpacity",
    "showAbsorbs",
    "showHealAbsorbs",
    "showIncomingHeals",
    "showLowHealthAlert",
    "healthAbsorbColor",
    "healthAbsorbTexture",
    "healthHealAbsorbColor",
    "healthHealAbsorbTexture",
    "healthIncomingHealColor",
    "healthIncomingHealTexture",
    "healthLowHealthAlertColor",
    "healthLowHealthAlertTexture",
    "healthLowHealthAlertMissingHealthOnly",
}

------------------------------------------------------------------------
-- Layout Helpers
------------------------------------------------------------------------

local GetSpecLayoutOrder

local function GetResourceBarSettings()
    return CooldownCompanion:GetResourceBarSettings()
end

local function GetResourceLayout(settings)
    if type(settings) ~= "table" then return nil end
    return GetSpecLayoutOrder and GetSpecLayoutOrder(settings) or nil
end

local function GetResourceLayoutValue(settings, key, fallback)
    local layout = GetResourceLayout(settings)
    if layout and layout[key] ~= nil then
        return layout[key]
    end
    if settings and settings[key] ~= nil then
        return settings[key]
    end
    return fallback
end

local function IsVerticalResourceLayout(settings)
    return GetResourceLayoutValue(settings, "orientation", "horizontal") == "vertical"
end

local function GetResourceLayoutOrientation(settings)
    return IsVerticalResourceLayout(settings) and "vertical" or "horizontal"
end

local function IsVerticalFillReversed(settings)
    if not IsVerticalResourceLayout(settings) then
        return false
    end
    return GetResourceLayoutValue(settings, "verticalFillDirection", "bottom_to_top") == "top_to_bottom"
end

local function GetResourcePrimaryLength(groupFrame, settings, region)
    if not groupFrame then return 0 end
    local group = groupFrame.groupId and CooldownCompanion.db.profile.groups[groupFrame.groupId]
    if group and ST.GetPanelAttachmentDimensions then
        local width, height = ST.GetPanelAttachmentDimensions(groupFrame, group, region or "outer")
        return IsVerticalResourceLayout(settings) and height or width
    end
    if IsVerticalResourceLayout(settings) then
        return groupFrame:GetHeight()
    end
    return groupFrame:GetWidth()
end

local function GetResourceGlobalThickness(settings)
    if IsVerticalResourceLayout(settings) then
        return GetResourceLayoutValue(settings, "barWidth")
            or GetResourceLayoutValue(settings, "barHeight")
            or 12
    end
    return GetResourceLayoutValue(settings, "barHeight")
        or GetResourceLayoutValue(settings, "barWidth")
        or 12
end

local function GetResourceAnchorGap(settings, layout, orientation)
    layout = layout or GetResourceLayout(settings)
    -- Attached cast bars and horizontal preview lanes keep their Y gap even
    -- when the resource stack uses the vertical orientation.
    if orientation == "vertical" or (orientation == nil and IsVerticalResourceLayout(settings)) then
        return (layout and (layout.verticalXOffset or layout.yOffset))
            or settings.verticalXOffset
            or settings.yOffset
            or 3
    end
    return (layout and (layout.yOffset or layout.verticalXOffset))
        or settings.yOffset
        or settings.verticalXOffset
        or 3
end

local function GetVerticalSideFallback(horizontalSide)
    return horizontalSide == "above" and "left" or "right"
end

local function GetEffectiveAnchorGroupId(settings)
    if not settings then return nil end
    return CooldownCompanion:GetModuleAnchorPanelId("resources")
end

-- Attached horizontal stacks have two possible bodies on each side. Keep
-- their identity separate from direction: aura containers, cast predecessors
-- and the preview must all partition the same way. Old side keys remain the
-- outer stacks (and retain their saved aura-bucket order).
RB.ATTACHED_BAR_LANES = { "above", "below", "aboveMain", "belowMain" }

function RB.GetBarLaneSide(lane)
    if lane == "aboveMain" then return "above" end
    if lane == "belowMain" then return "below" end
    return lane
end

function RB.GetBarAnchorGroup()
    local resolved = CooldownCompanion:ResolveModulePanel("resources")
    local id = resolved.group and resolved.panelId
    return id and CooldownCompanion.db.profile.groups[id], id
end

function RB.HasBarSectionOnSide(group, side)
    if not ST.GetSectionsForLayout(group) then return false end
    for _, entry in ipairs(group.buttons or {}) do
        local anchor = ST.GetPanelSectionForEntry(group, entry)
        if anchor then
            local _, sectionSide = ST.GetPanelSectionPlacement(group, anchor)
            if sectionSide == side then return true end
        end
    end
    return false
end

function RB.ResolveBarLane(group, side, region, independent)
    if independent or (side ~= "above" and side ~= "below") then return side end
    if ST.PanelSupportsAttachedBars(group) then
        region = ST.ResolvePanelAttachmentRegion(group, side, region)
        return region == "main" and side .. "Main" or side
    end
    if region == "main" or not RB.HasBarSectionOnSide(group, side) then
        return side .. "Main"
    end
    return side
end

-- A resource side has one region, chosen by its first saved resource until
-- the block is explicitly moved. Individual resource order stays internal.
function RB.GetResourceBlockRegion(layout, side, vertical)
    local block = layout.resourceBlocks and layout.resourceBlocks[side]
    if block then return block.anchorRegion end
    local firstOrder, firstKey, region
    for key, slot in pairs(layout.resources or {}) do
        local position = vertical and (slot.verticalPosition or GetVerticalSideFallback(slot.position))
            or slot.position or "below"
        if position == side then
            local order = vertical and slot.verticalOrder or slot.order
            order = tonumber(order) or 900 + (tonumber(key) or 0)
            if not firstOrder or order < firstOrder or (order == firstOrder and tostring(key) < firstKey) then
                firstOrder, firstKey, region = order, tostring(key), slot.anchorRegion
            end
        end
    end
    return region or "main"
end

function RB.GetBarLaneBody(frame, lane)
    if lane == "aboveMain" or lane == "belowMain" then
        return ST.GetPanelAnchorBodyFrame(frame)
    end
    return frame
end

function RB.SetBarLane(slot, lane)
    slot.position = RB.GetBarLaneSide(lane)
    slot.anchorRegion = (lane == "aboveMain" or lane == "belowMain") and "main" or "panel"
end

function RB.GetBarPlacementOptions(group)
    local list, order = {}, {}
    for _, side in ipairs({ "above", "below" }) do
        local label = side == "above" and "Above" or "Below"
        list[side .. "Main"] = label .. " Main Icons"
        order[#order + 1] = side .. "Main"
        if RB.HasBarSectionOnSide(group, side) then
            list[side] = label .. " Entire Panel"
            order[#order + 1] = side
        end
    end
    return list, order
end

-- Only the collapsed destination needs this tie-break. It follows the fixed /
-- player aura / target aura rank and precedes the saved order within that rank.
function RB.GetBarRegionRank(lane, region, group)
    local side = RB.GetBarLaneSide(lane)
    if (lane == "aboveMain" or lane == "belowMain")
        and not RB.HasBarSectionOnSide(group, side) and region ~= "main" then
        return 1
    end
    return 0
end

-- Both rectangles can change independently under compact layout. Identity is
-- part of the snapshot because a sectioned-state flip replaces the body.
function RB.GetBarAnchorGeometry(frame, group)
    local body = ST.GetPanelAnchorBodyFrame(frame)
    if not body then return nil end
    return table.concat({ tostring(frame), tostring(body), frame:GetWidth(), frame:GetHeight(),
        body:GetWidth(), body:GetHeight(),
        tostring(RB.HasBarSectionOnSide(group, "above")),
        tostring(RB.HasBarSectionOnSide(group, "below")) }, ":")
end

function RB.GetAuraBlockFlagKey(lane, group)
    local side = RB.GetBarLaneSide(lane)
    if side ~= lane and not RB.HasBarSectionOnSide(group or RB.GetBarAnchorGroup(), side) then
        return side
    end
    return lane
end

-- The addon already keeps this id and refreshes it on the exact spec-change
-- events (CacheCurrentSpec, Core/EventHandlers.lua), and it is written during
-- OnEnable before any bar exists — so the resource poll reads the cache
-- instead of two C calls per resolution. The live calls remain the answer
-- while the cache is still empty, so a caller can never be handed a spec id
-- this addon has not seen yet.
local function GetCurrentSpecID()
    local cachedSpecID = CooldownCompanion._currentSpecId
    if cachedSpecID then
        return cachedSpecID
    end
    local specIdx = C_SpecializationInfo.GetSpecialization()
    if specIdx then
        local specID = C_SpecializationInfo.GetSpecializationInfo(specIdx)
        return specID
    end
    return nil
end

-- Class cannot change within a session, so the lookup happens once.
local cachedPlayerClassID = nil
local function GetPlayerClassID()
    if cachedPlayerClassID == nil then
        local _, _, classID = UnitClass("player")
        cachedPlayerClassID = classID
    end
    return cachedPlayerClassID
end

local customBarContentFields = {
    "spellID",
    "trackingMode",
    "displayMode",
    "maxStacks",
    "label",
    "barColor",
    "barCooldownColor",
    "barChargeColor",
    "overlayColor",
    "barHeight",
    "barWidth",
    "soundAlerts",
    "loadConditions",
    "talentConditions",
    "hideWhenInactive",
    "auraShellDim",
    "hideWhileOnCooldown",
    "hideWhileNotOnCooldown",
    "showOnlyAtZeroCharges",
    "hideWhileZeroCharges",
    "hideWhileAuraActive",
    "hideAuraActiveExceptPandemic",
    "auraTracking",
    "auraTrackGroup",
    "auraTrackPet",
    "auraSpellID",
    "auraUnitOverride",
    "auraIDOverride",
    "barAuraIndicatorEnabled",
    "barAuraColor",
    "barAuraEffect",
    "barAuraEffectColor",
    "barAuraEffectSize",
    "barAuraEffectThickness",
    "barAuraEffectSpeed",
    "barAuraEffectLines",
    "auraGlowCombatOnly",
    "barAuraPulseEnabled",
    "barAuraPulseSpeed",
    "barAuraColorShiftEnabled",
    "barAuraColorShiftSpeed",
    "barAuraColorShiftColor",
    "pandemicEffect",
    "pandemicColor",
    "pandemicMarker",
    "pandemicMarkerText",
    "pandemicMarkerColorMode",
    "pandemicMarkerColor",
    -- Retired pandemic families, kept ONLY so not-yet-migrated legacy
    -- entries still count as configured content (the import/migration
    -- passes strip the keys themselves; nothing renders them).
    "showPandemicGlow",
    "barPandemicColor",
    "pandemicBarEffect",
    "pandemicBarEffectColor",
    "pandemicBarEffectSize",
    "pandemicBarEffectThickness",
    "pandemicBarEffectSpeed",
    "pandemicBarEffectLines",
    "pandemicGlowCombatOnly",
    "pandemicBarPulseEnabled",
    "pandemicBarPulseSpeed",
    "pandemicBarColorShiftEnabled",
    "pandemicBarColorShiftSpeed",
    "pandemicBarColorShiftColor",
    "thresholdColorEnabled",
    "thresholdMaxColor",
    "maxStacksGlowEnabled",
    "maxStacksGlowStyle",
    "maxStacksGlowColor",
    "maxStacksGlowSize",
    "maxStacksGlowSpeed",
    "maxStacksGlowThickness",
    "maxStacksGlowLines",
    "maxStacksBarPulseEnabled",
    "maxStacksBarPulseSpeed",
    "maxStacksBarColorShiftEnabled",
    "maxStacksBarColorShiftSpeed",
    "maxStacksBarColorShiftColor",
    "showDurationText",
    "durationTextFont",
    "durationTextFontSize",
    "durationTextFontOutline",
    "durationTextFontColor",
    "durationFormat",
    "decimalTimers",
    "durationLowTimeThreshold",
    "durationLowTimeDecimals",
    "durationLowTimeColor",
    "durationLowTimeThreshold2",
    "durationLowTimeColor2",
    "durationLowTimeAuras",
    "cooldownTextVisibilityThreshold",
    "auraTextVisibilityThreshold",
    "showStackText",
    "showText",
    "stackTextFormat",
    "stackTextFont",
    "stackTextFontSize",
    "stackTextFontOutline",
    "stackTextFontColor",
    "auraUnit",
    "hasCharges",
    "maxCharges",
    -- Stack text formatter options: the shared config rows keep these in an
    -- auraBar subtable (panel key names), not flat on the entry.
    "auraBar",
}

local function HasCustomBarContent(cab)
    if type(cab) ~= "table" then
        return false
    end
    if cab.enabled == true then
        return true
    end
    for _, field in ipairs(customBarContentFields) do
        local value = cab[field]
        -- Table fields (auraBar) count only while they hold something: the
        -- setters leave an empty {} behind when the last key clears, and an
        -- empty shell must not make a stripped bar count as configured.
        if value ~= nil and (type(value) ~= "table" or next(value) ~= nil) then
            return true
        end
    end
    return false
end

local function IsConfiguredCustomBar(cab)
    return type(cab) == "table"
        and (
            HasCustomBarContent(cab)
            or cab.entryType ~= nil
            or cab.independentAnchorEnabled ~= nil
        )
end

local function GetCustomBarEntryType(cab)
    if type(cab) == "table" and cab.entryType == "spell" then
        return "spell"
    end
    return "aura"
end

local function IsSpellCustomBarConfig(cab)
    return GetCustomBarEntryType(cab) == "spell"
end

local function NormalizePayloadClassKey(value)
    if type(value) ~= "string" or value == "" then
        return nil
    end
    return string.upper(value)
end

-- The "Resources" piece of a setup export: the whole class bucket, tagged with
-- the class it belongs to. Replaces the target class's bucket on import.
local function BuildResourcesSetupSection(settings, classKey)
    if type(settings) ~= "table" then
        return nil
    end
    classKey = NormalizePayloadClassKey(classKey)
    if not classKey then
        local _, playerClassFilename = UnitClass("player")
        classKey = NormalizePayloadClassKey(playerClassFilename)
    end
    if not classKey then
        return nil
    end
    local classID = ST._GetClassIDFromResourceBarClassKey
        and ST._GetClassIDFromResourceBarClassKey(classKey)
        or nil
    return {
        classID = classID,
        classFilename = classKey,
        settings = CopyTable(settings),
    }
end

local function IsValidCustomAuraUnit(unit)
    return unit == "player" or unit == "target"
end

local function GetDefaultCustomAuraUnit(spellID)
    return ST.ClassifyAuraSpellUnit(spellID) or "player"
end

local function GetDefaultSpellCustomBarAuraUnit(cabConfig, spellID)
    local resolvedSpellID = spellID
    if resolvedSpellID == nil and type(cabConfig) == "table" then
        resolvedSpellID = cabConfig.spellID
    end
    resolvedSpellID = tonumber(resolvedSpellID)

    if CooldownCompanion and CooldownCompanion.ResolveStandaloneAuraDefaultUnit then
        -- The synthetic must classify the same way the live slot adapter
        -- does (ResourceBarAuraHost's BuildEntryAdapter): the resolver
        -- branches on addedAs, and an aura bar left unmarked takes the
        -- plain-spell branch, resolving a unit the bound candidate list
        -- disagrees with.
        local isAuraEntry = type(cabConfig) == "table"
            and not IsSpellCustomBarConfig(cabConfig)
        return CooldownCompanion:ResolveStandaloneAuraDefaultUnit({
            type = "spell",
            id = resolvedSpellID,
            addedAs = isAuraEntry and "aura" or nil,
            auraTracking = true,
            auraSpellID = type(cabConfig) == "table" and cabConfig.auraSpellID or nil,
            -- User overrides (panel parity): every cab synthetic carries
            -- both keys, or block and slot paths could watch different
            -- units for the same bar.
            auraUnitOverride = type(cabConfig) == "table" and cabConfig.auraUnitOverride or nil,
            auraIDOverride = type(cabConfig) == "table" and cabConfig.auraIDOverride or nil,
        })
    end

    return GetDefaultCustomAuraUnit(resolvedSpellID)
end

local function GetResolvedCustomAuraBarAuraUnit(cabConfig, spellID)
    local resolvedSpellID = spellID
    if resolvedSpellID == nil and type(cabConfig) == "table" then
        resolvedSpellID = cabConfig.spellID
    end

    -- Both entry types resolve candidate-aware (the tracked aura list can
    -- carry a different polarity than the base spell); the helper falls
    -- back to base-spell polarity when no candidate resolves. The migration
    -- and config derive the stored auraUnit from this same identity, and
    -- the slot display path classifies through the same standalone resolver.
    -- The USER unit override (auraUnitOverride, panel parity 2026-08-28)
    -- rides inside that shared resolver via the synthetic's keys — every
    -- cab probe carries it, so block and slot paths still agree. What stays
    -- banned is a path-local stored-unit branch like the retired
    -- auraUnitExplicit, which only ONE path read.
    return GetDefaultSpellCustomBarAuraUnit(cabConfig, resolvedSpellID)
end

local function EnsureCustomAuraBarAuraUnit(cabConfig, spellID, unit)
    local resolvedSpellID = spellID
    if resolvedSpellID == nil and type(cabConfig) == "table" then
        resolvedSpellID = cabConfig.spellID
    end

    if type(cabConfig) == "table" then
        local resolvedUnit = IsValidCustomAuraUnit(unit) and unit
            or GetResolvedCustomAuraBarAuraUnit(cabConfig, resolvedSpellID)

        cabConfig.auraUnit = resolvedUnit
        -- Custom-bar units are always polarity-derived: the explicit-unit
        -- flag is retired, and stripping residue here keeps an imported
        -- pre-retirement config from ever resurrecting it.
        cabConfig.auraUnitExplicit = nil

        if IsValidCustomAuraUnit(cabConfig.auraUnit) then
            return cabConfig.auraUnit
        end
    end

    return GetDefaultSpellCustomBarAuraUnit(cabConfig, resolvedSpellID)
end

local function CopyIndependentAnchor(anchor)
    if type(anchor) ~= "table" then
        return nil
    end
    return CopyTable(anchor)
end

local function SeedResourceLayoutFromGlobal(layout, settings, cbSettings, specID)
    if type(layout) ~= "table" or type(settings) ~= "table" then
        return layout
    end

    if type(layout.resources) ~= "table" then layout.resources = {} end
    if type(layout.castBar) ~= "table" then layout.castBar = {} end

    if layout.independentAnchorEnabled == nil then
        layout.independentAnchorEnabled = settings.independentAnchorEnabled == true
    end
    if layout.orientation == nil then layout.orientation = settings.orientation or "horizontal" end
    if layout.verticalFillDirection == nil then layout.verticalFillDirection = settings.verticalFillDirection or "bottom_to_top" end
    if layout.barSpacing == nil then layout.barSpacing = settings.barSpacing or 3.6 end
    if layout.segmentGap == nil then layout.segmentGap = settings.segmentGap or 4 end
    if layout.barHeight == nil then layout.barHeight = settings.barHeight or 12 end
    if layout.barWidth == nil then layout.barWidth = settings.barWidth or layout.barHeight or 12 end
    if layout.customBarHeights == nil then layout.customBarHeights = settings.customBarHeights == true end
    if layout.inheritAlpha == nil then layout.inheritAlpha = settings.inheritAlpha == true end
    if layout.yOffset == nil then layout.yOffset = settings.yOffset or 3 end
    if layout.verticalXOffset == nil then layout.verticalXOffset = settings.verticalXOffset or layout.yOffset or 3 end
    if layout.independentWidth == nil then layout.independentWidth = settings.independentWidth end
    if layout.independentAnchorLocked == nil then layout.independentAnchorLocked = settings.independentAnchorLocked end
    if type(layout.independentAnchor) ~= "table" then
        layout.independentAnchor = CopyIndependentAnchor(settings.independentAnchor)
    end

    if type(settings.resources) == "table" then
        for pt, res in pairs(settings.resources) do
            if type(res) == "table" and (res.barHeight ~= nil or res.barWidth ~= nil) then
                if type(layout.resources[pt]) ~= "table" then layout.resources[pt] = {} end
                local target = layout.resources[pt]
                if target.barHeight == nil then target.barHeight = res.barHeight end
                if target.barWidth == nil then target.barWidth = res.barWidth end
            end
        end
    end


    return layout
end

local function CreateDefaultLayoutOrder(settings, cbSettings, specID)
    return SeedResourceLayoutFromGlobal({
        resources = {},
        castBar = { position = "below", order = 2000 },
    }, settings, cbSettings, specID)
end

GetSpecLayoutOrder = function(settings, specID)
    if type(settings) ~= "table" then return nil end
    specID = specID or GetCurrentSpecID()
    if not specID then return nil end
    specID = tonumber(specID) or specID
    if not settings.layoutOrder then settings.layoutOrder = {} end
    if type(settings.layoutOrder[specID]) ~= "table" then
        settings.layoutOrder[specID] = CreateDefaultLayoutOrder(settings, nil, specID)
    else
        SeedResourceLayoutFromGlobal(settings.layoutOrder[specID], settings, nil, specID)
    end
    return settings.layoutOrder[specID]
end

-- Seeding only fills nils and normalizes one key, and every key it touches is
-- non-nil once it has run, so a second pass over the same profile table can
-- never change the result. It is therefore first-touch: the write-back below
-- lands in SavedVariables, and GetSpecResourceDisplayProfile is read at the
-- poll cadence. Weak keys so a profile table dropped by a profile switch,
-- import or spec copy is not pinned here — and a replaced table is a new
-- table, which seeds again.
local seededResourceDisplayProfiles = setmetatable({}, { __mode = "k" })

local function SeedResourceDisplayProfileFromGlobal(profile, settings)
    if type(profile) ~= "table" or type(settings) ~= "table" then
        return profile
    end
    if seededResourceDisplayProfiles[profile] then
        return profile
    end
    seededResourceDisplayProfiles[profile] = true
    for _, key in ipairs(RESOURCE_DISPLAY_PROFILE_KEYS) do
        if profile[key] == nil then
            local value = settings[key]
            profile[key] = type(value) == "table" and CopyTable(value) or value
        end
    end
    if profile.barTexture == nil then profile.barTexture = "Solid" end
    if profile.backgroundColor == nil then profile.backgroundColor = { 0, 0, 0, 0.5 } end
    if profile.borderStyle == nil then profile.borderStyle = "pixel" end
    if profile.borderColor == nil then profile.borderColor = { 0, 0, 0, 1 } end
    if profile.borderSize == nil then profile.borderSize = 1 end
    if profile.borderRenderMode == nil then profile.borderRenderMode = ST.BORDER_RENDER_MODE_CUSTOM end
    if profile.classBarBrightness == nil then profile.classBarBrightness = 1.3 end
    profile.segmentedSmoothing = ST.NormalizeSegmentedSmoothing(profile.segmentedSmoothing)
    return profile
end

local function GetSpecResourceDisplayProfile(settings, specID)
    if type(settings) ~= "table" then return nil end
    specID = specID or GetCurrentSpecID()
    if not specID then return nil end
    specID = tonumber(specID) or specID
    if type(settings.displayProfiles) ~= "table" then
        settings.displayProfiles = {}
    end
    if type(settings.displayProfiles[specID]) ~= "table" then
        settings.displayProfiles[specID] = {}
    end
    return SeedResourceDisplayProfileFromGlobal(settings.displayProfiles[specID], settings)
end

local function GetResourceDisplayValue(settings, key, fallback)
    local profile = GetSpecResourceDisplayProfile(settings)
    if profile and profile[key] ~= nil then
        return profile[key]
    end
    if settings and settings[key] ~= nil then
        return settings[key]
    end
    return fallback
end

local function GetResourceSegmentedSmoothing(settings, specID)
    local profile = GetSpecResourceDisplayProfile(settings, specID)
    return ST.NormalizeSegmentedSmoothing(profile and profile.segmentedSmoothing or nil)
end

-- Maelstrom Weapon stack display shape. The stack count is identical in
-- every style; only the widget that renders it differs:
--   overlay    five segments with a second colour layer for stacks past
--              five (the default, and the only pre-12.1 look)
--   segments   one segment per stack, no overlay layer
--   continuous a single bar filling from empty to the stack maximum
-- The maximum is talent-driven (mwMaxStacks), so "segments" is five or ten
-- segments depending on Raging Maelstrom, exactly like the overlay style's
-- own capacity.
local MW_DISPLAY_STYLES = { overlay = true, segments = true, continuous = true }

local function GetMWDisplayStyle(settings, specID)
    if type(settings) ~= "table" or type(settings.resources) ~= "table" then
        return "overlay"
    end
    local resource = settings.resources[RESOURCE_MAELSTROM_WEAPON]
    if type(resource) ~= "table" then
        return "overlay"
    end
    local style = ResolveSpecOverrideKey(resource, specID or GetCurrentSpecID(), "mwDisplayStyle")
    return MW_DISPLAY_STYLES[style] and style or "overlay"
end

-- Stack display shape for an aura-stack family member. Two shapes only: the
-- overlay layer exists for Maelstrom Weapon alone, whose stacks can run past
-- its segment count. Resolved through the same spec-override path as
-- mwDisplayStyle, under the family's own generic key. The untouched default
-- is the member's own: one segment per stack suits the small fixed caps
-- (Icicles, Tip of the Spear), but a member whose maximum is large enough
-- to read as noise segment-by-segment ships Continuous instead.
-- A mutually exclusive pair is one slot, so the shape is one setting on one
-- bucket: resolve to the canonical half first, so both halves answer the same
-- and the slot cannot change shape mid-fight when the swap happens. Reached
-- through RB because the resolver is defined below this chunk; every other
-- resource resolves to itself.
local function GetAuraStackDisplayStyle(settings, powerType, specID)
    powerType = RB.GetCanonicalPowerType(powerType)
    local info = RB.AURA_STACK_RESOURCES[powerType]
    local default = (info and info.defaultStyle) or "segments"
    if type(settings) ~= "table" or type(settings.resources) ~= "table" then
        return default
    end
    local resource = settings.resources[powerType]
    if type(resource) ~= "table" then
        return default
    end
    local style = ResolveSpecOverrideKey(resource, specID or GetCurrentSpecID(), "stackDisplayStyle")
    if style == "continuous" or style == "segments" then
        return style
    end
    return default
end

-- Resolved stack maximum for an aura-stack family member. Most members state
-- a constant; the Devourer pair asks the same calls Blizzard's own Devourer
-- bar asks, because those caps move with talents and with what Collapsing
-- Star currently costs. Either call can come back with nothing before the
-- client has a value, and GetSpellMaxCumulativeAuraApplications is flagged
-- SecretWhenUnitAuraRestricted, so a secret is a legal answer too — in every
-- one of those cases the member's fallbackMax stands in rather than a zero
-- maximum reaching the range and percent maths downstream. Called on every
-- tick per materialized bar, so it stays two table reads and one C call.
local function GetAuraStackResourceMax(powerType)
    local info = RB.AURA_STACK_RESOURCES[powerType]
    if not info then return 0 end
    if info.maxStacks then return info.maxStacks, true end

    local resolved
    if info.dynamicMax == "cumulativeAura"
        and type(C_Spell.GetSpellMaxCumulativeAuraApplications) == "function" then
        resolved = C_Spell.GetSpellMaxCumulativeAuraApplications(info.auraSpellID)
    elseif info.dynamicMax == "collapsingStarCost"
        and type(GetCollapsingStarCost) == "function" then
        resolved = GetCollapsingStarCost()
    end
    -- The secret test is the FIRST thing that touches the answer: even the
    -- nil test below is a comparison, and comparing a secret is a hard error
    -- rather than a wrong number.
    if issecretvalue and issecretvalue(resolved) then
        resolved = nil
    end
    local confirmed = type(resolved) == "number" and resolved > 0
        and resolved < math.huge and resolved == math.floor(resolved)
    if resolved == nil or resolved == 0 then
        resolved = info.fallbackMax
    end
    resolved = tonumber(resolved) or 1
    -- Rendering keeps its fallback; sounds require a confirmed cap.
    return resolved >= 1 and resolved or 1, confirmed
end

-- Whether an aura-stack family member is currently the hidden half of a
-- mutually exclusive pair. Only members that declare metaVisibility can be:
-- every other member (and every other spec's bars) returns false without
-- reading an aura at all, so nobody pays for the Devourer swap. The aura
-- read itself is presence-only, the same plain never-secret call Blizzard's
-- Devourer bar makes.
local function IsAuraStackResourceSuppressed(powerType)
    local info = RB.AURA_STACK_RESOURCES[powerType]
    local visibility = info and info.metaVisibility
    if not visibility then return false end
    local inMeta = C_UnitAuras.GetPlayerAuraBySpellID(RB.VOID_METAMORPHOSIS_SPELL_ID) ~= nil
    if visibility == "inMeta" then
        return not inMeta
    end
    return inMeta
end

-- The pair's shared state, for the runtime watcher that spots the flip.
local function IsInVoidMetamorphosis()
    return C_UnitAuras.GetPlayerAuraBySpellID(RB.VOID_METAMORPHOSIS_SPELL_ID) ~= nil
end

-- Which member's entries hold a resource's SLOT-SHAPED settings — its
-- placement in layout.resources (side, order, per-bar thickness) and, in
-- settings.resources, the stack display shape and the max-stack border. A
-- mutually exclusive pair is one bar in the world occupying one slot, so the
-- half that declares canonicalHalf stores none of those of its own and every
-- such read resolves to the canonical half. Without this the pair had two
-- independent placements and the world order depended on which half happened
-- to be up, so the layout canvas could never match the game; the same is
-- true of the shape and the border, which describe that one slot. Per-HALF
-- styling is deliberately NOT routed here: colors and stack thresholds stay
-- in each half's own bucket. Every other resource answers with itself, so no
-- other spec pays for the Devourer swap.
local function GetCanonicalPowerType(powerType)
    local info = RB.AURA_STACK_RESOURCES[powerType]
    local canonical = info and info.canonicalHalf
    return canonical or powerType
end

-- Which half of a proxied pair a config surface should DRAW in that one
-- slot: whichever half is live in the world right now, so the canvas shows
-- the bar the player is actually looking at. Placement identity is
-- untouched — the slot still reads and writes the canonical half's entry.
-- Resources that are nobody's proxy target answer with themselves.
local function GetPlacementRenderPowerType(powerType)
    if not IsAuraStackResourceSuppressed(powerType) then
        return powerType
    end
    for pt, info in pairs(RB.AURA_STACK_RESOURCES) do
        if info.canonicalHalf == powerType and not IsAuraStackResourceSuppressed(pt) then
            return pt
        end
    end
    return powerType
end

local function GetResourceDisplayConfig(settings, powerType)
    local resource = settings and settings.resources and settings.resources[powerType]
    if type(resource) ~= "table" then return nil end
    local specID = GetCurrentSpecID()
    if not specID then return resource end
    local resolved = CopyTable(resource)
    local specOverrides = resource.specOverrides
    local specData = type(specOverrides) == "table" and (specOverrides[specID] or specOverrides[tostring(specID)]) or nil
    if type(specData) == "table" then
        for key, value in pairs(specData) do
            resolved[key] = value
        end
    end
    return resolved
end

local function GetResourceSpecOverrideTable(settings, powerType, specID, create)
    if type(settings) ~= "table" or not specID then return nil end
    specID = tonumber(specID) or specID
    if type(settings.resources) ~= "table" then
        if not create then return nil end
        settings.resources = {}
    end
    if type(settings.resources[powerType]) ~= "table" then
        if not create then return nil end
        settings.resources[powerType] = {}
    end
    local resource = settings.resources[powerType]
    if type(resource.specOverrides) ~= "table" then
        if not create then return nil end
        resource.specOverrides = {}
    end
    if type(resource.specOverrides[specID]) ~= "table" then
        if not create then return nil end
        resource.specOverrides[specID] = {}
    end
    return resource.specOverrides[specID]
end

local function GetAnchorOffset(point, width, height)
    if point == "TOPLEFT" then
        return -width / 2, height / 2
    elseif point == "TOP" then
        return 0, height / 2
    elseif point == "TOPRIGHT" then
        return width / 2, height / 2
    elseif point == "LEFT" then
        return -width / 2, 0
    elseif point == "CENTER" then
        return 0, 0
    elseif point == "RIGHT" then
        return width / 2, 0
    elseif point == "BOTTOMLEFT" then
        return -width / 2, -height / 2
    elseif point == "BOTTOM" then
        return 0, -height / 2
    elseif point == "BOTTOMRIGHT" then
        return width / 2, -height / 2
    end
    return 0, 0
end

------------------------------------------------------------------------
-- Independent Anchor Validation Helpers
------------------------------------------------------------------------

local RoundToTenths = ST.RoundToTenths

local function ClampIndependentDimension(value, fallback, minVal)
    local dim = tonumber(value) or tonumber(fallback) or 120
    minVal = minVal or 4
    if dim < minVal then
        dim = minVal
    elseif dim > 1200 then
        dim = 1200
    end
    return dim
end

local function IsTruthyConfigFlag(value)
    return value == true or value == 1 or value == "1" or value == "true"
end

------------------------------------------------------------------------
-- Resource Detection
------------------------------------------------------------------------

local function IsHealerSpec()
    local specIdx = C_SpecializationInfo.GetSpecialization()
    if specIdx then
        local _, _, _, _, role = C_SpecializationInfo.GetSpecializationInfo(specIdx)
        return role == "HEALER"
    end
    return false
end

local function IsAstralPowerAvailableForCurrentDruidSpec()
    return GetCurrentSpecID() == DRUID_BALANCE_SPEC_ID
end

local function GetDruidResources()
    local formID = GetShapeshiftFormID()
    if formID and DRUID_FORM_RESOURCES[formID] then
        local resources = DRUID_FORM_RESOURCES[formID]
        if formID == 31 and not IsAstralPowerAvailableForCurrentDruidSpec() then
            return DRUID_DEFAULT_RESOURCES
        end
        return resources
    end
    return DRUID_DEFAULT_RESOURCES
end

local function AddHealthResource(resources)
    local result = { RESOURCE_HEALTH }
    if type(resources) ~= "table" then
        return result
    end

    for _, powerType in ipairs(resources) do
        if powerType ~= RESOURCE_HEALTH then
            result[#result + 1] = powerType
        end
    end

    return result
end

--- Determine which resources the current class/spec should display.
local function DetermineActiveResources(settings)
    local classID = GetPlayerClassID()
    if not classID then return {} end

    -- Druid: current-form resources, optionally unioned with persistent spec resources.
    if classID == 11 then
        local resources = GetDruidResources()
        if settings and settings.keepSpecResourcesInAllForms == true then
            local persistentResources = DRUID_PERSISTENT_RESOURCES_BY_SPEC[GetCurrentSpecID()]
            local orderedResources = {}
            local seen = {}

            for _, pt in ipairs(persistentResources or {}) do
                if not seen[pt] then
                    seen[pt] = true
                    orderedResources[#orderedResources + 1] = pt
                end
            end
            for _, pt in ipairs(resources) do
                if not seen[pt] then
                    seen[pt] = true
                    orderedResources[#orderedResources + 1] = pt
                end
            end

            resources = orderedResources
        end
        -- Always add Mana if not already present and not hidden
        local hasMana = false
        for _, pt in ipairs(resources) do
            if pt == 0 then hasMana = true; break end
        end
        if not hasMana then
            local result = {}
            for _, pt in ipairs(resources) do
                table.insert(result, pt)
            end
            table.insert(result, 0)
            return AddHealthResource(result)
        end
        return AddHealthResource(resources)
    end

    -- Check spec-specific override first
    local specID = GetCurrentSpecID()
    if specID and SPEC_RESOURCES[specID] then
        return AddHealthResource(SPEC_RESOURCES[specID])
    end

    return AddHealthResource(CLASS_RESOURCES[classID] or {})
end

------------------------------------------------------------------------
-- Color & Secret Functions
------------------------------------------------------------------------

--- Generic color resolver. Resolves per-spec overrides first, falling back to
--- resource-level values and then hardcoded defaults. Returns one color per key
--- defined in RESOURCE_COLOR_DEFS. For power types without an entry (generic
--- continuous), returns the single power color.
local function GetResourceColors(powerType, settings)
    local def = RESOURCE_COLOR_DEFS[powerType]
    local specID = GetCurrentSpecID()
    if not def then
        -- Generic single-color fallback (continuous resources)
        if settings and settings.resources then
            local override = settings.resources[powerType]
            if override then
                local resolved = ResolveSpecOverrideKey(override, specID, "color")
                if resolved then return resolved end
            end
        end
        return DEFAULT_POWER_COLORS[powerType] or { 1, 1, 1 }
    end

    local override = settings and settings.resources and settings.resources[powerType]
    local keys, defaults = def.keys, def.defaults
    local n = #keys
    if n == 2 then
        return ResolveSpecOverrideKey(override, specID, keys[1]) or defaults[1],
               ResolveSpecOverrideKey(override, specID, keys[2]) or defaults[2]
    elseif n == 3 then
        return ResolveSpecOverrideKey(override, specID, keys[1]) or defaults[1],
               ResolveSpecOverrideKey(override, specID, keys[2]) or defaults[2],
               ResolveSpecOverrideKey(override, specID, keys[3]) or defaults[3]
    end
    -- Shouldn't happen, but safe fallback
    return defaults[1]
end

local POWER_SECRECY_CACHE = {}
local SECRET_LEVEL_NEVER = Enum and Enum.SecrecyLevel and Enum.SecrecyLevel.NeverSecret or 0

local function IsPowerTypePotentiallySecret(powerType)
    local cached = POWER_SECRECY_CACHE[powerType]
    if cached ~= nil then
        return cached
    end

    local potentiallySecret = true
    if SecretsAPI and SecretsAPI.GetPowerTypeSecrecy then
        potentiallySecret = SecretsAPI.GetPowerTypeSecrecy(powerType) ~= SECRET_LEVEL_NEVER
    end

    POWER_SECRECY_CACHE[powerType] = potentiallySecret
    return potentiallySecret
end

local function IsUnitPowerSecret(unit, powerType)
    if not IsPowerTypePotentiallySecret(powerType) then
        return false
    end
    if SecretsAPI and SecretsAPI.ShouldUnitPowerBeSecret then
        return SecretsAPI.ShouldUnitPowerBeSecret(unit, powerType) == true
    end
    return false
end

local function IsUnitPowerMaxSecret(unit, powerType)
    if not IsPowerTypePotentiallySecret(powerType) then
        return false
    end
    if SecretsAPI and SecretsAPI.ShouldUnitPowerMaxBeSecret then
        return SecretsAPI.ShouldUnitPowerMaxBeSecret(unit, powerType) == true
    end
    return false
end

------------------------------------------------------------------------
-- Color/Config Helpers
------------------------------------------------------------------------

local function GetSafeRGBColor(color, fallback)
    if type(color) == "table" and color[1] ~= nil and color[2] ~= nil and color[3] ~= nil then
        return color
    end
    return fallback
end

-- Identical to GetSafeRGBColor; alias kept for call-site clarity (RGB vs RGBA intent)
local GetSafeRGBAColor = GetSafeRGBColor

local function ClampSegmentedThresholdValue(value, fallback)
    value = tonumber(value)
    if not value then
        return fallback
    end
    value = math_floor(value)
    if value < 1 then
        value = 1
    elseif value > 99 then
        value = 99
    end
    return value
end

local function ClampContinuousTickPercentValue(value, fallback)
    value = tonumber(value)
    if not value then
        return fallback
    end
    if value < 0 then
        value = 0
    elseif value > 100 then
        value = 100
    end
    return value
end

local function ClampContinuousTickAbsoluteValue(value, fallback)
    value = tonumber(value)
    if not value then
        return fallback
    end
    if value < 0 then
        value = 0
    end
    return value
end

local function CollectNumericKeys(tbl)
    local keys = {}
    if type(tbl) ~= "table" then
        return keys
    end
    for key in pairs(tbl) do
        if type(key) == "number" then
            keys[#keys + 1] = key
        end
    end
    table_sort(keys)
    return keys
end

-- One shared list stands in for every disabled path below. Those paths are the
-- default and they are reached at the poll cadence, so a fresh empty table per
-- read was pure garbage. Read-only by convention: no caller mutates a returned
-- entry list, they only walk it.
local EMPTY_THRESHOLD_TICK_ENTRIES = {}

local function NormalizeEntryList(entries, clampValue, colorFallback, colorResolver)
    local normalized = {}
    local seen = {}
    if type(entries) ~= "table" then
        return normalized
    end

    local keys = CollectNumericKeys(entries)
    for _, key in ipairs(keys) do
        local entry = entries[key]
        local value = type(entry) == "table" and clampValue(entry.value, nil) or nil
        if value ~= nil then
            local valueKey = tostring(value)
            if not seen[valueKey] then
                seen[valueKey] = true
                normalized[#normalized + 1] = {
                    value = value,
                    color = colorResolver(type(entry) == "table" and entry.color or nil, colorFallback),
                }
                if #normalized >= MAX_RESOURCE_THRESHOLD_TICK_ENTRIES then
                    break
                end
            end
        end
    end

    table_sort(normalized, function(a, b)
        return a.value < b.value
    end)
    return normalized
end

local function GetNormalizedSegmentedThresholdEntriesFromConfig(entries)
    return NormalizeEntryList(entries, ClampSegmentedThresholdValue, DEFAULT_SEG_THRESHOLD_COLOR, GetSafeRGBColor)
end

local function GetNormalizedContinuousTickEntriesFromConfig(entries, mode)
    local clamp = mode == "absolute" and ClampContinuousTickAbsoluteValue or ClampContinuousTickPercentValue
    return NormalizeEntryList(entries, clamp, DEFAULT_CONTINUOUS_TICK_COLOR, GetSafeRGBAColor)
end

local function BuildLegacySegmentedThresholdEntry(resource, specID)
    return {
        value = ClampSegmentedThresholdValue(ResolveSpecOverrideKey(resource, specID, "segThresholdValue"), 1),
        color = GetSafeRGBColor(ResolveSpecOverrideKey(resource, specID, "segThresholdColor"), DEFAULT_SEG_THRESHOLD_COLOR),
    }
end

local function BuildLegacyContinuousTickEntry(resource, specID, mode)
    local value
    if mode == "absolute" then
        value = ClampContinuousTickAbsoluteValue(ResolveSpecOverrideKey(resource, specID, "continuousTickAbsolute"), DEFAULT_CONTINUOUS_TICK_ABSOLUTE)
    else
        value = ClampContinuousTickPercentValue(ResolveSpecOverrideKey(resource, specID, "continuousTickPercent"), DEFAULT_CONTINUOUS_TICK_PERCENT)
    end
    return {
        value = value,
        color = GetSafeRGBAColor(ResolveSpecOverrideKey(resource, specID, "continuousTickColor"), DEFAULT_CONTINUOUS_TICK_COLOR),
    }
end

local function ResolveSpecEntryList(resource, specID, entriesKey, clearedKey)
    if specID and type(resource) == "table" then
        local specOverrides = resource.specOverrides
        local specData = type(specOverrides) == "table" and specOverrides[specID] or nil
        if type(specData) == "table" then
            if specData[entriesKey] ~= nil then
                return specData[entriesKey], specData[clearedKey] == true
            end
            if specData[clearedKey] == true then
                return nil, true
            end
        end
    end
    return resource and resource[entriesKey], resource and resource[clearedKey] == true
end

local function GetSegmentedThresholdEntriesConfig(powerType, settings)
    -- Stack-counted resources get threshold colours alongside the real
    -- segmented power types: Maelstrom Weapon and every aura-stack family
    -- member (reached through RB, which adds no local to this chunk).
    if powerType ~= RESOURCE_MAELSTROM_WEAPON and SEGMENTED_TYPES[powerType] ~= true
        and RB.AURA_STACK_RESOURCES[powerType] == nil then
        return false, EMPTY_THRESHOLD_TICK_ENTRIES
    end
    if not settings or not settings.resources then
        return false, EMPTY_THRESHOLD_TICK_ENTRIES
    end

    local resource = settings.resources[powerType]
    if type(resource) ~= "table" then
        return false, EMPTY_THRESHOLD_TICK_ENTRIES
    end

    local specID = GetCurrentSpecID()
    local enabled = ResolveSpecOverrideKey(resource, specID, "segThresholdEnabled")
    if enabled ~= true then
        return false, EMPTY_THRESHOLD_TICK_ENTRIES
    end

    local rawEntries, cleared = ResolveSpecEntryList(resource, specID, "segThresholdEntries", "segThresholdEntriesCleared")
    local entries = GetNormalizedSegmentedThresholdEntriesFromConfig(rawEntries)
    if #entries == 0 and not cleared then
        entries[1] = BuildLegacySegmentedThresholdEntry(resource, specID)
    end
    return true, entries
end

-- `holder` is optional and is the applied bar frame when the caller has one.
-- The list it carries was compiled by ApplyResourceBars for exactly this power
-- type (RB.CompileResourceBarConfig); the power-type stamp is what makes a
-- recycled frame fall back to a live resolution instead of answering with the
-- previous occupant's thresholds. A holder with no stamp resolves live, so
-- preview frames and any caller without a holder behave exactly as before.
local function GetSegmentedThresholdColorForValue(powerType, settings, currentValue, holder)
    currentValue = tonumber(currentValue)
    if not currentValue then
        return false, nil
    end

    local enabled, entries
    if holder ~= nil and holder._ccSegThresholdPowerType == powerType then
        enabled = holder._ccSegThresholdEnabled
        entries = holder._ccSegThresholdEntries
    else
        enabled, entries = GetSegmentedThresholdEntriesConfig(powerType, settings)
    end
    if not enabled then
        return false, nil
    end

    local activeColor
    for _, entry in ipairs(entries) do
        if currentValue >= entry.value then
            activeColor = entry.color
        else
            break
        end
    end

    return activeColor ~= nil, activeColor
end

local function GetContinuousTickEntriesConfig(powerType, settings)
    if SEGMENTED_TYPES[powerType] or powerType == RESOURCE_MAELSTROM_WEAPON
        or RB.AURA_STACK_RESOURCES[powerType] then
        return false, nil, EMPTY_THRESHOLD_TICK_ENTRIES, nil, nil
    end
    if not settings or not settings.resources then
        return false, nil, EMPTY_THRESHOLD_TICK_ENTRIES, nil, nil
    end

    local resource = settings.resources[powerType]
    if type(resource) ~= "table" then
        return false, nil, EMPTY_THRESHOLD_TICK_ENTRIES, nil, nil
    end

    local specID = GetCurrentSpecID()
    local enabled = ResolveSpecOverrideKey(resource, specID, "continuousTickEnabled")
    if enabled ~= true then
        return false, nil, EMPTY_THRESHOLD_TICK_ENTRIES, nil, nil
    end

    local mode = ResolveSpecOverrideKey(resource, specID, "continuousTickMode")
    if mode ~= "percent" and mode ~= "absolute" then
        mode = DEFAULT_CONTINUOUS_TICK_MODE
    end

    local entriesKey = mode == "absolute" and "continuousTickAbsoluteEntries" or "continuousTickPercentEntries"
    local clearedKey = mode == "absolute" and "continuousTickAbsoluteEntriesCleared" or "continuousTickPercentEntriesCleared"
    local rawEntries, cleared = ResolveSpecEntryList(resource, specID, entriesKey, clearedKey)
    local entries = GetNormalizedContinuousTickEntriesFromConfig(rawEntries, mode)
    if #entries == 0 and not cleared then
        entries[1] = BuildLegacyContinuousTickEntry(resource, specID, mode)
    end

    local tickWidth = tonumber(ResolveSpecOverrideKey(resource, specID, "continuousTickWidth")) or DEFAULT_CONTINUOUS_TICK_WIDTH
    if tickWidth < 1 then tickWidth = 1 elseif tickWidth > 10 then tickWidth = 10 end
    local combatOnly = ResolveSpecOverrideKey(resource, specID, "continuousTickCombatOnly") or false
    return true, mode, entries, tickWidth, combatOnly
end

-- Derived config the poll body would otherwise rebuild 30 times a second,
-- compiled once at the apply boundary and hung off the applied bar. Both lists
-- are pure functions of the resource's settings bucket, its spec overrides and
-- the current spec — and every writer of those commits through
-- ApplyResourceBars (config commits, profile switch, import, migration) or
-- through the lifecycle events that re-evaluate on a spec, talent or form
-- change. The power-type stamp is the reuse guard: a recycled frame that now
-- renders a different resource, and any frame this never ran for, resolves
-- live instead.
function RB.ClearCompiledResourceBarConfig(holder)
    if not holder then return end
    holder._ccSegThresholdPowerType = nil
    holder._ccSegThresholdEnabled = nil
    holder._ccSegThresholdEntries = nil
    holder._ccTickPowerType = nil
    holder._ccTickEnabled = nil
    holder._ccTickMode = nil
    holder._ccTickEntries = nil
    holder._ccTickWidth = nil
    holder._ccTickCombatOnly = nil
end

function RB.CompileResourceBarConfig(holder, powerType, settings)
    if not holder or powerType == nil then return end

    local thresholdEnabled, thresholdEntries = GetSegmentedThresholdEntriesConfig(powerType, settings)
    holder._ccSegThresholdEnabled = thresholdEnabled
    holder._ccSegThresholdEntries = thresholdEntries
    holder._ccSegThresholdPowerType = powerType

    local tickEnabled, tickMode, tickEntries, tickWidth, tickCombatOnly =
        GetContinuousTickEntriesConfig(powerType, settings)
    holder._ccTickEnabled = tickEnabled
    holder._ccTickMode = tickMode
    holder._ccTickEntries = tickEntries
    holder._ccTickWidth = tickWidth
    holder._ccTickCombatOnly = tickCombatOnly
    holder._ccTickPowerType = powerType
end

local function SupportsResourceAuraStackMode(powerType)
    return powerType == RESOURCE_MAELSTROM_WEAPON or SEGMENTED_TYPES[powerType] == true
        or RB.AURA_STACK_RESOURCES[powerType] ~= nil
end

-- Whether this resource renders as ONE continuous StatusBar under the
-- current settings. Mirrors the ApplyResourceBars shape dispatch, so the
-- config panel and the preview stand-in can answer "can the aura fill
-- recolor ride this bar" without a live frame (the recolor needs a single
-- fill texture; segment clusters and health have none it can ride).
-- specID is optional and matters to the config panel: an inactive-spec
-- page must resolve THAT spec's display style, not the active one the
-- style getters default to.
local function IsContinuousResourceShape(settings, powerType, specID)
    if powerType == nil or powerType == RESOURCE_HEALTH then
        return false
    end
    if powerType == 101 then -- Stagger
        return true
    end
    if powerType == RESOURCE_MAELSTROM_WEAPON then
        return GetMWDisplayStyle(settings, specID) == "continuous"
    end
    if RB.AURA_STACK_RESOURCES[powerType] then
        return GetAuraStackDisplayStyle(settings, powerType, specID) == "continuous"
    end
    return SEGMENTED_TYPES[powerType] ~= true
end

------------------------------------------------------------------------
-- IsResourceEnabled
------------------------------------------------------------------------

--- Check if a specific resource is enabled in settings.
local function IsResourceEnabled(powerType, settings)
    if powerType == RESOURCE_HEALTH then
        local health = settings and settings.resources and settings.resources[RESOURCE_HEALTH]
        return type(health) == "table" and health.enabled == true
    end

    if settings and settings.resources then
        local override = settings.resources[powerType]
        if override and override.enabled == false then
            return false
        end
    end
    -- Hide mana for non-healer toggle
    if powerType == 0 and settings and settings.hideManaForNonHealer then
        if not IsHealerSpec() and GetCurrentSpecID() ~= 62 then
            return false
        end
    end
    return true
end

------------------------------------------------------------------------
-- Segmented Text Helpers
------------------------------------------------------------------------

local function IsSegmentedTextResource(powerType)
    return powerType == RESOURCE_MAELSTROM_WEAPON or SEGMENTED_TYPES[powerType] == true
        or RB.AURA_STACK_RESOURCES[powerType] ~= nil
end

local function FormatSegmentedTextNumber(value)
    local n = tonumber(value) or 0
    local rounded = math_floor((n * 10) + 0.5) / 10
    local formatted = string_format("%.1f", rounded)
    return (formatted:gsub("%.0$", ""))
end

local function ClearSegmentedText(holder)
    if holder and holder.text then
        holder.text:SetText("")
    end
end

local function SetSegmentedText(holder, currentValue, maxValue)
    if not holder or not holder.text or not holder.text:IsShown() then return end
    if type(currentValue) ~= "number" then
        holder.text:SetText("")
        return
    end

    if holder._hideTextAtZero and currentValue == 0 then
        holder.text:SetText("")
        return
    end

    local textFormat = holder._textFormat
    if textFormat == "current_max" then
        if type(maxValue) ~= "number" then
            holder.text:SetText("")
            return
        end
        holder.text:SetText(FormatSegmentedTextNumber(currentValue) .. " / " .. FormatSegmentedTextNumber(maxValue))
    else
        holder.text:SetText(FormatSegmentedTextNumber(currentValue))
    end
end

------------------------------------------------------------------------
-- Shared Independent Mover Utilities
------------------------------------------------------------------------

local function IsBarsConfigActive()
    local cs = ST and ST._configState
    if not cs or not cs.barsEntrySelected then
        return false
    end
    if not CooldownCompanion.GetConfigFrame then
        return false
    end
    local configFrame = CooldownCompanion:GetConfigFrame()
    return configFrame and configFrame.frame and configFrame.frame:IsShown() == true
end

------------------------------------------------------------------------
-- Add all helpers to ST._RB
------------------------------------------------------------------------

RB.GetResourceBarSettings = GetResourceBarSettings
RB.IsVerticalResourceLayout = IsVerticalResourceLayout
RB.GetResourceLayoutOrientation = GetResourceLayoutOrientation
RB.IsVerticalFillReversed = IsVerticalFillReversed
RB.GetResourcePrimaryLength = GetResourcePrimaryLength
RB.GetResourceGlobalThickness = GetResourceGlobalThickness
RB.GetResourceAnchorGap = GetResourceAnchorGap
RB.GetVerticalSideFallback = GetVerticalSideFallback
RB.GetEffectiveAnchorGroupId = GetEffectiveAnchorGroupId
RB.GetCurrentSpecID = GetCurrentSpecID
RB.GetPlayerClassID = GetPlayerClassID
RB.BuildResourcesSetupSection = BuildResourcesSetupSection
RB.IsConfiguredCustomBar = IsConfiguredCustomBar
RB.GetCustomBarEntryType = GetCustomBarEntryType
RB.IsSpellCustomBarConfig = IsSpellCustomBarConfig
RB.GetResolvedCustomAuraBarAuraUnit = GetResolvedCustomAuraBarAuraUnit
RB.EnsureCustomAuraBarAuraUnit = EnsureCustomAuraBarAuraUnit
RB.GetSpecLayoutOrder = GetSpecLayoutOrder
RB.GetSpecResourceDisplayProfile = GetSpecResourceDisplayProfile
RB.GetResourceDisplayValue = GetResourceDisplayValue
RB.GetResourceSegmentedSmoothing = GetResourceSegmentedSmoothing
RB.GetMWDisplayStyle = GetMWDisplayStyle
RB.GetAuraStackDisplayStyle = GetAuraStackDisplayStyle
RB.GetAuraStackResourceMax = GetAuraStackResourceMax
RB.IsAuraStackResourceSuppressed = IsAuraStackResourceSuppressed
RB.IsInVoidMetamorphosis = IsInVoidMetamorphosis
RB.GetCanonicalPowerType = GetCanonicalPowerType
RB.GetPlacementRenderPowerType = GetPlacementRenderPowerType
RB.GetResourceDisplayConfig = GetResourceDisplayConfig
RB.GetResourceSpecOverrideTable = GetResourceSpecOverrideTable
RB.RESOURCE_TEXT_DISPLAY_KEYS = RESOURCE_TEXT_DISPLAY_KEYS
RB.RESOURCE_HEALTH_DISPLAY_KEYS = RESOURCE_HEALTH_DISPLAY_KEYS
RB.GetAnchorOffset = GetAnchorOffset
RB.RoundToTenths = RoundToTenths
RB.ClampIndependentDimension = ClampIndependentDimension
RB.IsBarsConfigActive = IsBarsConfigActive
RB.IsTruthyConfigFlag = IsTruthyConfigFlag
RB.IsAstralPowerAvailableForCurrentDruidSpec = IsAstralPowerAvailableForCurrentDruidSpec
RB.DetermineActiveResources = DetermineActiveResources
RB.GetResourceColors = GetResourceColors
RB.IsUnitPowerSecret = IsUnitPowerSecret
RB.IsUnitPowerMaxSecret = IsUnitPowerMaxSecret
RB.GetSafeRGBColor = GetSafeRGBColor
RB.MAX_RESOURCE_THRESHOLD_TICK_ENTRIES = MAX_RESOURCE_THRESHOLD_TICK_ENTRIES
RB.ClampSegmentedThresholdValue = ClampSegmentedThresholdValue
RB.ClampContinuousTickPercentValue = ClampContinuousTickPercentValue
RB.ClampContinuousTickAbsoluteValue = ClampContinuousTickAbsoluteValue
RB.GetNormalizedSegmentedThresholdEntriesFromConfig = GetNormalizedSegmentedThresholdEntriesFromConfig
RB.GetNormalizedContinuousTickEntriesFromConfig = GetNormalizedContinuousTickEntriesFromConfig
RB.ResolveSpecEntryList = ResolveSpecEntryList
RB.GetSegmentedThresholdColorForValue = GetSegmentedThresholdColorForValue
RB.GetContinuousTickEntriesConfig = GetContinuousTickEntriesConfig
RB.SupportsResourceAuraStackMode = SupportsResourceAuraStackMode
RB.IsContinuousResourceShape = IsContinuousResourceShape
RB.IsResourceEnabled = IsResourceEnabled
RB.IsSegmentedTextResource = IsSegmentedTextResource
RB.ClearSegmentedText = ClearSegmentedText
RB.SetSegmentedText = SetSegmentedText
