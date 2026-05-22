--[[
    CooldownCompanion - Core/MigrationsResourceBars.lua: resource, cast, layout, and Custom Bars migrations.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local Masque = CooldownCompanion.Masque

local pairs = pairs
local ipairs = ipairs
local type = type
local next = next
local rawget = rawget

function CooldownCompanion:MigrateBarOrdering()
    local profile = self.db.profile
    local rb = profile.resourceBars
    local cb = profile.castBar
    if not rb then return end

    -- Skip if already migrated (old fields are gone) or never configured
    if rb.position == nil and rb.stackOrder == nil then return end

    local oldPosition = rb.position or "below"
    local oldStackOrder = rb.stackOrder or "resource_first"

    -- Assign unique sequential orders to class resources per power type.
    -- Order matches the CLASS_RESOURCES/SPEC_RESOURCES tables in ResourceBar.lua.
    -- We use a fixed broad list covering all classes; non-enabled resources are ignored.
    -- Each power type gets a unique value so the sort is deterministic.
    local defaultResourceOrder = {
        [0]  = 1,    -- Mana
        [1]  = 2,    -- Rage
        [2]  = 3,    -- Focus
        [3]  = 4,    -- Energy
        [4]  = 5,    -- ComboPoints
        [5]  = 6,    -- Runes
        [6]  = 7,    -- RunicPower
        [7]  = 8,    -- SoulShards
        [8]  = 9,    -- LunarPower
        [9]  = 10,   -- HolyPower
        [11] = 11,   -- Maelstrom
        [12] = 12,   -- Chi
        [13] = 13,   -- Insanity
        [16] = 14,   -- ArcaneCharges
        [17] = 15,   -- Fury
        [18] = 16,   -- Pain
        [19] = 17,   -- Essence
        [100] = 18,  -- Maelstrom Weapon
    }

    -- Set position/order on any resources already in the db
    if rb.resources then
        for pt, res in pairs(rb.resources) do
            res.position = oldPosition
            res.order = defaultResourceOrder[pt] or 1
        end
    end

    -- Set position/order on custom aura bar slots
    if not rb.customAuraBarSlots then
        rb.customAuraBarSlots = {}
    end
    for i = 1, 5 do
        if not rb.customAuraBarSlots[i] then
            rb.customAuraBarSlots[i] = {}
        end
        rb.customAuraBarSlots[i].position = oldPosition
        rb.customAuraBarSlots[i].order = 1000 + i
    end

    -- Migrate cast bar order based on old stackOrder
    if cb then
        if oldStackOrder == "cast_first" then
            cb.order = 0
        else
            cb.order = 2000
        end
        -- Migrate cast bar position to match old resource bar position
        if cb.position == nil then
            cb.position = oldPosition
        end
    end

    -- Remove old fields
    rb.position = nil
    rb.stackOrder = nil
    rb.reverseResourceOrder = nil

    -- castBar.yOffset is no longer used for gap (shared gap comes from resourceBars.yOffset).
    -- Clear any non-default value so it doesn't mislead future code.
    if cb and (cb.yOffset or 0) ~= 0 then
        cb.yOffset = 0
    end
end

-- Remove vestigial auraDurationCache from profile (no longer in defaults).
-- It was never written to at runtime; this just cleans up stale SavedVariables.
function CooldownCompanion:MigrateRemoveAuraDurationCache()
    self.db.profile.auraDurationCache = nil
end

-- Normalize only legacy shared resource-bar settings that predate the
-- character-scoped buckets. Modern character-scoped values may be negative on
-- purpose now, so leave those untouched.
function CooldownCompanion:MigrateResourceBarYOffset()
    local function normalizeLegacyYOffset(settings)
        if type(settings) == "table" and settings.yOffset and settings.yOffset < 0 then
            settings.yOffset = math.abs(settings.yOffset)
        end
    end

    normalizeLegacyYOffset(rawget(self.db.profile, "resourceBars"))
    normalizeLegacyYOffset(rawget(self.db.profile, "legacyResourceBarsSeed"))
end

-- Remove the old castBar.yOffset field from all storage buckets.
-- Attached-mode cast bar gap now comes from resourceBars.yOffset plus the
-- new opt-in castBar.panelAnchorYOffset delta.
function CooldownCompanion:MigrateLegacyCastBarYOffsetField()
    local profile = self.db.profile
    if profile._migratedLegacyCastBarYOffsetField then return end

    local function clearLegacyYOffset(settings)
        if type(settings) == "table" and settings.yOffset ~= nil then
            settings.yOffset = nil
        end
    end

    clearLegacyYOffset(rawget(profile, "castBar"))
    clearLegacyYOffset(rawget(profile, "legacyCastBarSeed"))

    local store = rawget(profile, "castBarByChar")
    if type(store) == "table" then
        for _, settings in pairs(store) do
            clearLegacyYOffset(settings)
        end
    end

    profile._migratedLegacyCastBarYOffsetField = true
end

local function HasResourceAuraOverlayEntries(resource)
    if type(resource) ~= "table" or type(resource.auraOverlayEntries) ~= "table" then
        return false
    end
    return next(resource.auraOverlayEntries) ~= nil
end

local function HasLegacyResourceAuraOverlayData(resource)
    if type(resource) ~= "table" then
        return false
    end
    return resource.auraColorSpellID ~= nil
        or resource.auraActiveColor ~= nil
        or resource.auraColorTrackingMode ~= nil
        or resource.auraColorMaxStacks ~= nil
end

local function GetEffectiveResourceAuraOverlayEnabled(resource)
    if type(resource) ~= "table" then
        return false
    end
    if type(resource.auraOverlayEnabled) == "boolean" then
        return resource.auraOverlayEnabled
    end
    if HasResourceAuraOverlayEntries(resource) then
        return true
    end
    local auraSpellID = tonumber(resource.auraColorSpellID)
    return auraSpellID and auraSpellID > 0 or false
end

local function CopyResourceAuraOverlayColor(color)
    if type(color) ~= "table" or color[1] == nil or color[2] == nil or color[3] == nil then
        return nil
    end
    return { color[1], color[2], color[3] }
end

local function ClearLegacyResourceAuraOverlayFields(resource)
    if type(resource) ~= "table" then
        return
    end
    resource.auraColorSpellID = nil
    resource.auraActiveColor = nil
    resource.auraColorTrackingMode = nil
    resource.auraColorMaxStacks = nil
    resource.auraUnit = nil
    resource.auraUnitExplicit = nil
end

function CooldownCompanion:MigrateResourceAuraOverlayEntries()
    -- Resource aura overlay legacy conversion now happens when the current
    -- character's resource bar settings bucket is materialized from the shared
    -- seed, so the data can be filtered by character/class before becoming
    -- persistent per-character state.
end

function CooldownCompanion:MigrateCharacterScopedBarSettings()
    self:CaptureLegacyScopedBarSettingsSeeds()
    self:EnsureLegacyScopedBarSeenCharacters()
    self:EnsureCurrentCharacterScopedBarSettings()
end

local function BackfillCustomAuraBarSlots5(rb)
    if type(rb) ~= "table" then return end

    if not rb.customAuraBarSlots then
        rb.customAuraBarSlots = {}
    end
    for i = 4, 5 do
        if not rb.customAuraBarSlots[i] then
            rb.customAuraBarSlots[i] = { position = "below", order = 1000 + i }
        end
    end

    if rb.customAuraBars then
        for _, specBars in pairs(rb.customAuraBars) do
            if type(specBars) == "table" then
                for i = 4, 5 do
                    if not specBars[i] then
                        specBars[i] = { enabled = false }
                    end
                end
            end
        end
    end
end

function CooldownCompanion:MigrateCustomAuraBarSlots5()
    local profile = self.db.profile
    if profile._migratedCustomAuraSlots5v2 then return end

    -- Clean up stale v1 sentinel
    profile._migratedCustomAuraSlots5 = nil

    -- Legacy / seed resource bar settings
    BackfillCustomAuraBarSlots5(rawget(profile, "resourceBars"))
    BackfillCustomAuraBarSlots5(rawget(profile, "legacyResourceBarsSeed"))

    -- Character-scoped buckets
    local store = rawget(profile, "resourceBarsByChar")
    if type(store) == "table" then
        for _, charSettings in pairs(store) do
            BackfillCustomAuraBarSlots5(charSettings)
        end
    end

    profile._migratedCustomAuraSlots5v2 = true
end

-- Migrate flat per-character layout position/order fields into the new
-- per-spec layoutOrder table.  Copies existing arrangement to ALL specs of
-- the current character's class so every spec starts with the previous layout.
function CooldownCompanion:MigrateLayoutOrderToSpecKeyed()
    local profile = self.db.profile
    if profile._migratedLayoutOrder then return end

    local _, _, classID = UnitClass("player")
    if not classID then return end

    local numSpecs = C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0
    if numSpecs == 0 then return end

    local specIDs = {}
    for i = 1, numSpecs do
        local specID = GetSpecializationInfoForClassID(classID, i)
        if specID then
            specIDs[#specIDs + 1] = specID
        end
    end
    if #specIDs == 0 then return end

    -- Extract layout fields from a resource bar settings table + optional cast bar table
    local function ExtractLayout(rbSettings, cbSettings)
        local layout = {
            resources = {},
            customAuraBarSlots = {},
            castBar = { position = "below", order = 2000 },
        }

        if type(rbSettings) == "table" and type(rbSettings.resources) == "table" then
            for pt, res in pairs(rbSettings.resources) do
                if type(res) == "table" and (res.position or res.order or res.verticalPosition or res.verticalOrder) then
                    layout.resources[pt] = {
                        position = res.position,
                        order = res.order,
                        verticalPosition = res.verticalPosition,
                        verticalOrder = res.verticalOrder,
                    }
                end
            end
        end

        if type(rbSettings) == "table" and type(rbSettings.customAuraBarSlots) == "table" then
            for slotIdx, slot in pairs(rbSettings.customAuraBarSlots) do
                if type(slot) == "table" and (slot.position or slot.order or slot.verticalPosition or slot.verticalOrder) then
                    layout.customAuraBarSlots[slotIdx] = {
                        position = slot.position,
                        order = slot.order,
                        verticalPosition = slot.verticalPosition,
                        verticalOrder = slot.verticalOrder,
                    }
                end
            end
        end

        if type(cbSettings) == "table" then
            if cbSettings.position or cbSettings.order then
                layout.castBar = {
                    position = cbSettings.position or "below",
                    order = cbSettings.order or 2000,
                }
            end
        end

        return layout
    end

    -- Copy layout to all specs (only for specs not already present)
    local function ApplyLayoutToAllSpecs(rbSettings, layout)
        if not rbSettings.layoutOrder then rbSettings.layoutOrder = {} end
        local allPresent = true
        for _, specID in ipairs(specIDs) do
            if not rbSettings.layoutOrder[specID] then allPresent = false; break end
        end
        if allPresent then return end

        for _, specID in ipairs(specIDs) do
            if not rbSettings.layoutOrder[specID] then
                rbSettings.layoutOrder[specID] = CopyTable(layout)
            end
        end
    end

    -- Migrate character-scoped buckets
    local rbStore = rawget(profile, "resourceBarsByChar")
    local cbStore = rawget(profile, "castBarByChar")
    if type(rbStore) == "table" then
        for charKey, rbSettings in pairs(rbStore) do
            if type(rbSettings) == "table" then
                local cbSettings = type(cbStore) == "table" and cbStore[charKey] or nil
                local layout = ExtractLayout(rbSettings, cbSettings)
                ApplyLayoutToAllSpecs(rbSettings, layout)
            end
        end
    end

    -- Migrate legacy seed
    local seed = rawget(profile, "legacyResourceBarsSeed")
    if type(seed) == "table" then
        local cbSeed = rawget(profile, "legacyCastBarSeed")
        local layout = ExtractLayout(seed, cbSeed)
        ApplyLayoutToAllSpecs(seed, layout)
    end

    profile._migratedLayoutOrder = true
end

-- Expand the per-spec resource-bar layout table from ordering-only data into
-- the single layout profile used by the Layout tab.  Existing global fields are
-- copied into every same-class spec so a reload preserves the visible layout.
function CooldownCompanion:MigrateResourceBarExpandedSpecLayouts()
    local profile = self.db.profile
    if profile._migratedResourceBarExpandedSpecLayouts then return end

    local _, _, classID = UnitClass("player")
    if not classID then return end

    local specIDs = {}
    for i = 1, (C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0) do
        local specID = GetSpecializationInfoForClassID(classID, i)
        if specID then
            specIDs[#specIDs + 1] = specID
        end
    end
    if #specIDs == 0 then return end

    local function SetMissing(tbl, key, value)
        if tbl[key] == nil then
            tbl[key] = value
        end
    end

    local function EnsureExpandedLayout(rbSettings, cbSettings, specID)
        if type(rbSettings) ~= "table" then return end
        rbSettings.specPlacementOverrides = nil
        if type(rbSettings.layoutOrder) ~= "table" then rbSettings.layoutOrder = {} end
        if type(rbSettings.layoutOrder[specID]) ~= "table" then
            rbSettings.layoutOrder[specID] = {
                resources = {},
                customAuraBarSlots = {},
                castBar = { position = "below", order = 2000 },
            }
        end

        local layout = rbSettings.layoutOrder[specID]
        if type(layout.resources) ~= "table" then layout.resources = {} end
        if type(layout.customAuraBarSlots) ~= "table" then layout.customAuraBarSlots = {} end
        if type(layout.castBar) ~= "table" then layout.castBar = {} end

        SetMissing(layout, "independentAnchorEnabled", rbSettings.independentAnchorEnabled == true)
        SetMissing(layout, "orientation", rbSettings.orientation or "horizontal")
        SetMissing(layout, "verticalFillDirection", rbSettings.verticalFillDirection or "bottom_to_top")
        SetMissing(layout, "barSpacing", rbSettings.barSpacing or 3.6)
        SetMissing(layout, "segmentGap", rbSettings.segmentGap or 4)
        SetMissing(layout, "barHeight", rbSettings.barHeight or 12)
        SetMissing(layout, "barWidth", rbSettings.barWidth or layout.barHeight or 12)
        SetMissing(layout, "customBarHeights", rbSettings.customBarHeights == true)
        SetMissing(layout, "inheritAlpha", rbSettings.inheritAlpha == true)
        SetMissing(layout, "yOffset", rbSettings.yOffset or 3)
        SetMissing(layout, "verticalXOffset", rbSettings.verticalXOffset or layout.yOffset or 3)
        SetMissing(layout, "independentWidth", rbSettings.independentWidth)
        SetMissing(layout, "independentAnchorLocked", rbSettings.independentAnchorLocked)
        if layout.independentAnchor == nil and type(rbSettings.independentAnchor) == "table" then
            layout.independentAnchor = CopyTable(rbSettings.independentAnchor)
        end

        if type(rbSettings.resources) == "table" then
            for pt, res in pairs(rbSettings.resources) do
                if type(res) == "table" then
                    if type(layout.resources[pt]) ~= "table" then layout.resources[pt] = {} end
                    local target = layout.resources[pt]
                    SetMissing(target, "position", res.position)
                    SetMissing(target, "order", res.order)
                    SetMissing(target, "verticalPosition", res.verticalPosition)
                    SetMissing(target, "verticalOrder", res.verticalOrder)
                    SetMissing(target, "barHeight", res.barHeight)
                    SetMissing(target, "barWidth", res.barWidth)
                end
            end
        end

        if type(rbSettings.customAuraBarSlots) == "table" then
            for slotIdx, slot in pairs(rbSettings.customAuraBarSlots) do
                if type(slot) == "table" then
                    if type(layout.customAuraBarSlots[slotIdx]) ~= "table" then layout.customAuraBarSlots[slotIdx] = {} end
                    local target = layout.customAuraBarSlots[slotIdx]
                    SetMissing(target, "position", slot.position)
                    SetMissing(target, "order", slot.order)
                    SetMissing(target, "verticalPosition", slot.verticalPosition)
                    SetMissing(target, "verticalOrder", slot.verticalOrder)
                end
            end
        end

        local specCustomBars = type(rbSettings.customAuraBars) == "table" and rbSettings.customAuraBars[specID] or nil
        if type(specCustomBars) == "table" then
            for slotIdx, cab in pairs(specCustomBars) do
                if type(cab) == "table" and (cab.barHeight ~= nil or cab.barWidth ~= nil) then
                    if type(layout.customAuraBarSlots[slotIdx]) ~= "table" then layout.customAuraBarSlots[slotIdx] = {} end
                    local target = layout.customAuraBarSlots[slotIdx]
                    SetMissing(target, "barHeight", cab.barHeight)
                    SetMissing(target, "barWidth", cab.barWidth)
                end
            end
        end

        if type(cbSettings) == "table" then
            SetMissing(layout.castBar, "position", cbSettings.position or "below")
            SetMissing(layout.castBar, "order", cbSettings.order or 2000)
            SetMissing(layout.castBar, "panelAnchorYOffsetEnabled", cbSettings.panelAnchorYOffsetEnabled == true)
            SetMissing(layout.castBar, "panelAnchorYOffset", cbSettings.panelAnchorYOffset or 0)
        else
            SetMissing(layout.castBar, "position", "below")
            SetMissing(layout.castBar, "order", 2000)
            SetMissing(layout.castBar, "panelAnchorYOffsetEnabled", false)
            SetMissing(layout.castBar, "panelAnchorYOffset", 0)
        end
    end

    local rbStore = rawget(profile, "resourceBarsByChar")
    local cbStore = rawget(profile, "castBarByChar")
    if type(rbStore) == "table" then
        for charKey, rbSettings in pairs(rbStore) do
            local cbSettings = type(cbStore) == "table" and cbStore[charKey] or nil
            for _, specID in ipairs(specIDs) do
                EnsureExpandedLayout(rbSettings, cbSettings, specID)
            end
        end
    end

    local seed = rawget(profile, "legacyResourceBarsSeed")
    if type(seed) == "table" then
        local cbSeed = rawget(profile, "legacyCastBarSeed")
        for _, specID in ipairs(specIDs) do
            EnsureExpandedLayout(seed, cbSeed, specID)
        end
    end

    profile._migratedResourceBarExpandedSpecLayouts = true
end

-- Resolve stored spell IDs to their base form so the override chain can
-- freely transform to any variant at runtime.  Skip items (implicit via
-- type check), pet spells (may not resolve through GetBaseSpell), and CDM
-- child slots (viewer-frame mapping uses specific IDs).

function CooldownCompanion:MigrateSpecColorsToSpecOverrides()
    local profile = self.db and self.db.profile
    if not profile then return end
    if profile._migratedSpecOverrides then return end

    local function migrateSettings(settings)
        if type(settings) ~= "table" or type(settings.resources) ~= "table" then return end
        for _, resource in pairs(settings.resources) do
            if type(resource) == "table" and type(resource.specColors) == "table" then
                resource.specOverrides = resource.specColors
                resource.specColors = nil
            elseif type(resource) == "table" and resource.specColors ~= nil then
                resource.specColors = nil
            end
        end
    end

    -- Legacy / seed resource bar settings
    migrateSettings(rawget(profile, "resourceBars"))
    migrateSettings(rawget(profile, "legacyResourceBarsSeed"))

    -- Character-scoped buckets
    local store = rawget(profile, "resourceBarsByChar")
    if type(store) == "table" then
        for _, charSettings in pairs(store) do
            migrateSettings(charSettings)
        end
    end

    profile._migratedSpecOverrides = true
end

-- Copy existing global Resource Bar display choices into the active class's
-- per-spec display profiles so old profiles preserve their visible styling.
function CooldownCompanion:MigrateResourceBarDisplayProfiles()
    local profile = self.db and self.db.profile
    if not profile then return end
    if profile._migratedResourceBarDisplayProfilesV2 then return end

    local _, _, classID = UnitClass("player")
    if not classID then return end

    local specIDs = {}
    for i = 1, (C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0) do
        local specID = GetSpecializationInfoForClassID(classID, i)
        if specID then
            specIDs[#specIDs + 1] = specID
        end
    end
    if #specIDs == 0 then return end

    local profileKeys = {
        "barTexture",
        "classBarBrightness",
        "backgroundColor",
        "borderStyle",
        "borderColor",
        "borderSize",
    }
    local resourceDisplayKeys = {
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
        "color",
        "comboColor",
        "comboMaxColor",
        "comboChargedColor",
        "runeReadyColor",
        "runeRechargingColor",
        "runeMaxColor",
        "shardReadyColor",
        "shardRechargingColor",
        "shardMaxColor",
        "holyColor",
        "holyMaxColor",
        "chiColor",
        "chiMaxColor",
        "arcaneColor",
        "arcaneMaxColor",
        "essenceReadyColor",
        "essenceRechargingColor",
        "essenceMaxColor",
        "mwBaseColor",
        "mwOverlayColor",
        "mwMaxColor",
        "staggerGreenColor",
        "staggerYellowColor",
        "staggerRedColor",
        "segThresholdEnabled",
        "segThresholdValue",
        "segThresholdColor",
        "continuousTickEnabled",
        "continuousTickMode",
        "continuousTickPercent",
        "continuousTickAbsolute",
        "continuousTickColor",
        "continuousTickCombatOnly",
        "continuousTickWidth",
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

    local function CopyMissingKey(source, target, key)
        if target[key] == nil and source[key] ~= nil then
            target[key] = type(source[key]) == "table" and CopyTable(source[key]) or source[key]
        end
    end

    local function GetAuraEntryForSpec(resource, specID)
        if type(resource) ~= "table" or type(resource.auraOverlayEntries) ~= "table" then
            return nil
        end
        return resource.auraOverlayEntries[specID] or resource.auraOverlayEntries[tostring(specID)]
    end

    local function MigrateSettings(rbSettings)
        if type(rbSettings) ~= "table" then return end
        if type(rbSettings.displayProfiles) ~= "table" then
            rbSettings.displayProfiles = {}
        end

        for _, specID in ipairs(specIDs) do
            if type(rbSettings.displayProfiles[specID]) ~= "table" then
                rbSettings.displayProfiles[specID] = {}
            end
            local targetProfile = rbSettings.displayProfiles[specID]
            for _, key in ipairs(profileKeys) do
                CopyMissingKey(rbSettings, targetProfile, key)
            end

            local layout = type(rbSettings.layoutOrder) == "table"
                and (rbSettings.layoutOrder[specID] or rbSettings.layoutOrder[tostring(specID)])
                or nil
            if type(layout) == "table" and layout.inheritAlpha == nil then
                layout.inheritAlpha = rbSettings.inheritAlpha == true
            end

            if type(rbSettings.resources) == "table" then
                for _, resource in pairs(rbSettings.resources) do
                    if type(resource) == "table" then
                        if type(resource.specOverrides) ~= "table" then
                            resource.specOverrides = {}
                        end
                        if type(resource.specOverrides[specID]) ~= "table" then
                            resource.specOverrides[specID] = {}
                        end
                        local targetResource = resource.specOverrides[specID]
                        for _, key in ipairs(resourceDisplayKeys) do
                            CopyMissingKey(resource, targetResource, key)
                        end
                        if targetResource.auraOverlayEnabled == nil then
                            local hasAuraEntry = type(GetAuraEntryForSpec(resource, specID)) == "table"
                            if type(resource.auraOverlayEnabled) == "boolean" then
                                if resource.auraOverlayEnabled == false then
                                    targetResource.auraOverlayEnabled = false
                                elseif hasAuraEntry then
                                    targetResource.auraOverlayEnabled = true
                                end
                            elseif hasAuraEntry then
                                targetResource.auraOverlayEnabled = true
                            end
                        end
                    end
                end
            end
        end
    end

    MigrateSettings(rawget(profile, "resourceBars"))
    MigrateSettings(rawget(profile, "legacyResourceBarsSeed"))

    local store = rawget(profile, "resourceBarsByChar")
    if type(store) == "table" then
        for _, charSettings in pairs(store) do
            MigrateSettings(charSettings)
        end
    end

    profile._migratedResourceBarDisplayProfiles = true
    profile._migratedResourceBarDisplayProfilesV2 = true
end

function CooldownCompanion:MigrateCustomAuraBarsToCustomBars()
    local profile = self.db and self.db.profile
    if not profile or profile._migratedCustomBarsDynamicV2 then return end

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
        "hideWhileAuraActive",
        "hideAuraActiveExceptPandemic",
        "auraTracking",
        "auraSpellID",
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
        "showDurationText",
        "durationTextFont",
        "durationTextFontSize",
        "durationTextFontOutline",
        "durationTextFontColor",
        "durationFormat",
        "decimalTimers",
        "showStackText",
        "showText",
        "stackTextFormat",
        "stackTextFont",
        "stackTextFontSize",
        "stackTextFontOutline",
        "stackTextFontColor",
        "auraUnit",
        "auraUnitExplicit",
        "hasCharges",
        "maxCharges",
    }

    local function HasCustomBarContent(cab)
        if type(cab) ~= "table" then
            return false
        end
        if cab.enabled == true then
            return true
        end
        for _, field in ipairs(customBarContentFields) do
            if cab[field] ~= nil then
                return true
            end
        end
        return false
    end

    local function IsConfiguredCustomBar(cab)
        return type(cab) == "table"
            and (
                HasCustomBarContent(cab)
                or cab.independentAnchorEnabled ~= nil
            )
    end

    local function NormalizeCustomBarSpecID(specID)
        local numericSpecID = tonumber(specID)
        if numericSpecID and numericSpecID > 0 then
            return numericSpecID
        end
        return nil
    end

    local function IsSharedCustomBarsStore(customBars)
        return type(customBars) == "table"
            and (type(customBars.entries) == "table" or type(customBars.order) == "table")
    end

    local function NormalizeCustomBarSpecMembership(entry)
        if type(entry) ~= "table" then
            return {}
        end

        local normalized = {}
        if type(entry.specs) == "table" then
            for key, value in pairs(entry.specs) do
                if value == true then
                    local specID = NormalizeCustomBarSpecID(key)
                    if specID then normalized[specID] = true end
                elseif type(value) == "number" or type(value) == "string" then
                    local specID = NormalizeCustomBarSpecID(value)
                    if specID then normalized[specID] = true end
                end
            end
        end

        local legacySpecID = NormalizeCustomBarSpecID(entry.specID or entry.spec or entry.sourceSpecID)
        if legacySpecID then
            normalized[legacySpecID] = true
        end

        entry.specs = normalized
        entry.specID = nil
        entry.spec = nil
        entry.sourceSpecID = nil
        return normalized
    end

    local function SetCustomBarSpecMembership(entry, specID)
        specID = NormalizeCustomBarSpecID(specID)
        if type(entry) == "table" and specID then
            NormalizeCustomBarSpecMembership(entry)[specID] = true
        end
    end

    local function NormalizeCustomBarAttachedPlacement(entry)
        if type(entry) ~= "table" then
            return
        end
        entry.independentAnchorEnabled = nil
        entry.independentLocked = nil
        entry.independentAnchorTargetMode = nil
        entry.independentAnchorFrameName = nil
        entry.independentAnchorGroupId = nil
        entry.independentAnchor = nil
        entry.independentSize = nil
        entry.independentOrientation = nil
        entry.independentVerticalFillDirection = nil
    end

    local function BuildCustomBarIdOwners(customBars)
        local owners = {}
        if type(customBars) ~= "table" then
            return owners
        end

        if IsSharedCustomBarsStore(customBars) then
            local entries = type(customBars.entries) == "table" and customBars.entries or {}
            for _, candidate in pairs(entries) do
                local customBarId = type(candidate) == "table" and candidate.customBarId or nil
                if type(customBarId) == "string" and customBarId ~= "" and owners[customBarId] == nil then
                    owners[customBarId] = candidate
                end
            end
        else
            for _, specBars in pairs(customBars) do
                if type(specBars) == "table" then
                    for _, candidate in pairs(specBars) do
                        local customBarId = type(candidate) == "table" and candidate.customBarId or nil
                        if type(customBarId) == "string" and customBarId ~= "" and owners[customBarId] == nil then
                            owners[customBarId] = candidate
                        end
                    end
                end
            end
        end
        return owners
    end

    local function EnsureNextId(settings, entry, customBarIdOwners)
        local entryId = entry.customBarId
        if type(entryId) == "string"
            and entryId ~= ""
            and (customBarIdOwners[entryId] == nil or customBarIdOwners[entryId] == entry) then
            customBarIdOwners[entryId] = entry
            return entry.customBarId
        end
        settings.nextCustomBarId = tonumber(settings.nextCustomBarId) or 1
        local id
        repeat
            id = "custom_bar_" .. tostring(settings.nextCustomBarId)
            settings.nextCustomBarId = settings.nextCustomBarId + 1
        until customBarIdOwners[id] == nil
        entry.customBarId = id
        customBarIdOwners[id] = entry
        return id
    end

    local function AddCustomBarOrder(store, customBarId)
        if type(store) ~= "table" or type(customBarId) ~= "string" or customBarId == "" then
            return
        end
        if type(store.order) ~= "table" then
            store.order = {}
        end
        for _, existingId in ipairs(store.order) do
            if existingId == customBarId then
                return
            end
        end
        store.order[#store.order + 1] = customBarId
    end

    local function CopyLegacyCustomBarLayout(settings, specID, customBarId, slotIdx, fallbackOrder)
        local layout = type(settings.layoutOrder) == "table"
            and (settings.layoutOrder[specID] or settings.layoutOrder[tostring(specID)])
            or nil
        if type(layout) ~= "table" or type(customBarId) ~= "string" then
            return
        end
        if type(layout.customBars) ~= "table" then
            layout.customBars = {}
        end
        if type(layout.customBars[customBarId]) == "table" then
            return
        end

        local legacySlot = type(layout.customAuraBarSlots) == "table"
            and layout.customAuraBarSlots[slotIdx]
            or nil
        layout.customBars[customBarId] = type(legacySlot) == "table"
            and CopyTable(legacySlot)
            or { position = "below", order = fallbackOrder or 1000 }
    end

    local function MigrateSettings(settings)
        if type(settings) ~= "table" then return end

        local sourceCustomBars = type(settings.customBars) == "table" and settings.customBars or {}
        local sourceCustomAuraBars = type(settings.customAuraBars) == "table" and settings.customAuraBars or nil
        local store = { entries = {}, order = {} }
        settings.customBars = store
        local customBarIdOwners = BuildCustomBarIdOwners(sourceCustomBars)

        local function addEntry(entry, specID, fallbackOrder)
            specID = NormalizeCustomBarSpecID(specID)
            if not (specID and IsConfiguredCustomBar(entry)) then
                return nil
            end
            NormalizeCustomBarAttachedPlacement(entry)
            if not HasCustomBarContent(entry) then
                return nil
            end
            entry.entryType = entry.entryType or "aura"
            SetCustomBarSpecMembership(entry, specID)
            local id = EnsureNextId(settings, entry, customBarIdOwners)
            if not id then
                return nil
            end
            store.entries[id] = entry
            AddCustomBarOrder(store, id)
            CopyLegacyCustomBarLayout(settings, specID, id, nil, fallbackOrder)
            return id
        end

        local function addSpecBars(specID, specBars)
            specID = NormalizeCustomBarSpecID(specID)
            if not (specID and type(specBars) == "table") then
                return
            end

            local numericKeys = {}
            for key in pairs(specBars) do
                if type(key) == "number" then
                    numericKeys[#numericKeys + 1] = key
                end
            end
            table.sort(numericKeys)

            local seen = {}
            for index, key in ipairs(numericKeys) do
                addEntry(specBars[key], specID, 1000 + index)
                seen[key] = true
            end
            for key, entry in pairs(specBars) do
                if not seen[key] then
                    addEntry(entry, specID, 1000 + #store.order + 1)
                end
            end
        end

        if IsSharedCustomBarsStore(sourceCustomBars) then
            local entries = type(sourceCustomBars.entries) == "table" and sourceCustomBars.entries or {}
            local order = type(sourceCustomBars.order) == "table" and sourceCustomBars.order or {}
            local seen = {}
            local function addSharedEntry(entry)
                if not IsConfiguredCustomBar(entry) then
                    return
                end
                NormalizeCustomBarAttachedPlacement(entry)
                if not HasCustomBarContent(entry) then
                    return
                end
                entry.entryType = entry.entryType or "aura"
                NormalizeCustomBarSpecMembership(entry)
                local id = EnsureNextId(settings, entry, customBarIdOwners)
                if id and not seen[id] then
                    store.entries[id] = entry
                    AddCustomBarOrder(store, id)
                    seen[id] = true
                end
            end
            for _, customBarId in ipairs(order) do
                addSharedEntry(entries[customBarId])
            end
            for _, entry in pairs(entries) do
                addSharedEntry(entry)
            end
        else
            local specIDs = {}
            for specID in pairs(sourceCustomBars) do
                specIDs[#specIDs + 1] = specID
            end
            table.sort(specIDs, function(a, b) return tostring(a) < tostring(b) end)
            for _, specID in ipairs(specIDs) do
                addSpecBars(specID, sourceCustomBars[specID])
            end
        end

        if sourceCustomAuraBars then
            local specIDs = {}
            for specID in pairs(sourceCustomAuraBars) do
                specIDs[#specIDs + 1] = specID
            end
            table.sort(specIDs, function(a, b) return tostring(a) < tostring(b) end)

            for _, specID in ipairs(specIDs) do
                local normalizedSpecID = NormalizeCustomBarSpecID(specID)
                local legacyBars = sourceCustomAuraBars[specID]
                local numericSlots = {}
                if normalizedSpecID and type(legacyBars) == "table" then
                    for slotIdx in pairs(legacyBars) do
                        if tonumber(slotIdx) then
                            numericSlots[#numericSlots + 1] = tonumber(slotIdx)
                        end
                    end
                end
                table.sort(numericSlots)

                for index, slotIdx in ipairs(numericSlots) do
                    local cab = legacyBars[slotIdx] or legacyBars[tostring(slotIdx)]
                    if IsConfiguredCustomBar(cab) then
                        local existingID = type(cab.customBarId) == "string" and cab.customBarId or nil
                        local entry = existingID and store.entries[existingID] or nil
                        local id
                        if type(entry) == "table" then
                            SetCustomBarSpecMembership(entry, normalizedSpecID)
                            id = existingID
                        else
                            entry = CopyTable(cab)
                            id = addEntry(entry, normalizedSpecID, 1000 + index)
                        end
                        CopyLegacyCustomBarLayout(settings, normalizedSpecID, id, slotIdx, 1000 + index)
                    end
                end
            end
            settings.customAuraBars = nil
        end
    end

    MigrateSettings(rawget(profile, "resourceBars"))
    MigrateSettings(rawget(profile, "legacyResourceBarsSeed"))

    local store = rawget(profile, "resourceBarsByChar")
    if type(store) == "table" then
        for _, charSettings in pairs(store) do
            MigrateSettings(charSettings)
        end
    end

    profile._migratedCustomBarsDynamic = true
    profile._migratedCustomBarsDynamicV2 = true
end
