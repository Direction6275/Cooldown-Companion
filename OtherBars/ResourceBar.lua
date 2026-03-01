--[[
    CooldownCompanion - ResourceBar
    Displays player class resources (Rage, Energy, Combo Points, Runes, etc.)
    anchored to icon groups.

    Unlike CastBar (which manipulates Blizzard's secure frame), resource bars are
    fully addon-owned frames with no taint concerns.

    SECRET VALUES (verified in-game 12.0.1):
      - UnitPower("player", primaryType) returns <secret> in combat for continuous
        resources (Mana, Rage, Energy, Focus, etc.)
      - StatusBar:SetValue(secret) works — C-level method accepts secret values
      - FontString:SetFormattedText("%d", secret) works — displays real number
      - UnitPowerMax() is NOT secret
      - Segmented/secondary resources (Combo Points, Essence, Runes, etc.) are NOT secret
      - GetRuneCooldown() returns real values in combat
      - UnitPartialPower() returns real values in combat
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local math_floor = math.floor
local math_min = math.min
local math_max = math.max
local math_abs = math.abs
local GetTime = GetTime

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------

local UPDATE_INTERVAL = 1 / 30  -- 30 Hz
local PERCENT_SCALE_CURVE = C_CurveUtil.CreateCurve()
PERCENT_SCALE_CURVE:SetType(Enum.LuaCurveType.Linear)
PERCENT_SCALE_CURVE:AddPoint(0.0, 0)
PERCENT_SCALE_CURVE:AddPoint(1.0, 100)

local CUSTOM_AURA_BAR_BASE = 201  -- 201, 202, 203 for slots 1-3
local MAX_CUSTOM_AURA_BARS = 3
local MW_SPELL_ID = 187880
local RAGING_MAELSTROM_SPELL_ID = 384143
local RESOURCE_MAELSTROM_WEAPON = 100
local DEFAULT_MW_BASE_COLOR = { 0, 0.5, 1 }
local DEFAULT_MW_OVERLAY_COLOR = { 1, 0.84, 0 }
local DEFAULT_MW_MAX_COLOR = { 0.5, 0.8, 1 }
local DEFAULT_CUSTOM_AURA_MAX_COLOR = { 1, 0.84, 0 }
local DEFAULT_RESOURCE_AURA_ACTIVE_COLOR = { 1, 0.84, 0 }
local DEFAULT_RESOURCE_TEXT_FORMAT = "current"
local DEFAULT_RESOURCE_TEXT_FONT = "Friz Quadrata TT"
local DEFAULT_RESOURCE_TEXT_SIZE = 10
local DEFAULT_RESOURCE_TEXT_OUTLINE = "OUTLINE"
local DEFAULT_RESOURCE_TEXT_COLOR = { 1, 1, 1, 1 }

local DEFAULT_POWER_COLORS = {
    [0]  = { 0, 0, 1 },              -- Mana
    [1]  = { 1, 0, 0 },              -- Rage
    [2]  = { 1, 0.5, 0.25 },         -- Focus
    [3]  = { 1, 1, 0 },              -- Energy
    [4]  = { 1, 0.96, 0.41 },        -- ComboPoints
    [5]  = { 0.5, 0.5, 0.5 },        -- Runes
    [6]  = { 0, 0.82, 1 },           -- RunicPower
    [7]  = { 0.5, 0.32, 0.55 },      -- SoulShards
    [8]  = { 0.3, 0.52, 0.9 },       -- LunarPower
    [9]  = { 0.95, 0.9, 0.6 },       -- HolyPower
    [11] = { 0, 0.5, 1 },            -- Maelstrom
    [12] = { 0.71, 1, 0.92 },        -- Chi
    [13] = { 0.4, 0, 0.8 },          -- Insanity
    [16] = { 0.1, 0.1, 0.98 },       -- ArcaneCharges
    [17] = { 0.788, 0.259, 0.992 },  -- Fury
    [18] = { 1, 0.612, 0 },          -- Pain
    [19] = { 0.286, 0.773, 0.541 },  -- Essence
}

local POWER_NAMES = {
    [0]  = "Mana",
    [1]  = "Rage",
    [2]  = "Focus",
    [3]  = "Energy",
    [4]  = "Combo Points",
    [5]  = "Runes",
    [6]  = "Runic Power",
    [7]  = "Soul Shards",
    [8]  = "Astral Power",
    [9]  = "Holy Power",
    [11] = "Maelstrom",
    [12] = "Chi",
    [13] = "Insanity",
    [16] = "Arcane Charges",
    [17] = "Fury",
    [100] = "Maelstrom Weapon",
    [18] = "Pain",
    [19] = "Essence",
}

local DEFAULT_COMBO_COLOR = { 1, 0.96, 0.41 }
local DEFAULT_COMBO_MAX_COLOR = { 1, 0.96, 0.41 }
local DEFAULT_COMBO_CHARGED_COLOR = { 0.24, 0.65, 1.0 }

local DEFAULT_RUNE_READY_COLOR = { 0.8, 0.8, 0.8 }
local DEFAULT_RUNE_RECHARGING_COLOR = { 0.490, 0.490, 0.490 }
local DEFAULT_RUNE_MAX_COLOR = { 0.8, 0.8, 0.8 }

local DEFAULT_SHARD_READY_COLOR = { 0.5, 0.32, 0.55 }
local DEFAULT_SHARD_RECHARGING_COLOR = { 0.490, 0.490, 0.490 }
local DEFAULT_SHARD_MAX_COLOR = { 0.5, 0.32, 0.55 }

local DEFAULT_HOLY_COLOR = { 0.95, 0.9, 0.6 }
local DEFAULT_HOLY_MAX_COLOR = { 0.95, 0.9, 0.6 }

local DEFAULT_CHI_COLOR = { 0.71, 1, 0.92 }
local DEFAULT_CHI_MAX_COLOR = { 0.71, 1, 0.92 }

local DEFAULT_ARCANE_COLOR = { 0.1, 0.1, 0.98 }
local DEFAULT_ARCANE_MAX_COLOR = { 0.1, 0.1, 0.98 }

local DEFAULT_ESSENCE_READY_COLOR = { 0.851, 0.482, 0.780 }
local DEFAULT_ESSENCE_RECHARGING_COLOR = { 0.490, 0.490, 0.490 }
local DEFAULT_ESSENCE_MAX_COLOR = { 0.851, 0.482, 0.780 }

local SEGMENTED_TYPES = {
    [4]  = true,  -- ComboPoints
    [5]  = true,  -- Runes
    [7]  = true,  -- SoulShards
    [9]  = true,  -- HolyPower
    [12] = true,  -- Chi
    [16] = true,  -- ArcaneCharges
    [19] = true,  -- Essence
}

-- Atlas info for class-specific bar textures (from PowerBarColorUtil.lua)
-- Only continuous power types that have a direct atlas field in Blizzard's data
local POWER_ATLAS_INFO = {
    [8]  = { atlas = "Unit_Druid_AstralPower_Fill" },
    [11] = { atlas = "Unit_Shaman_Maelstrom_Fill" },
    [13] = { atlas = "Unit_Priest_Insanity_Fill" },
    [17] = { atlas = "Unit_DemonHunter_Fury_Fill" },
    [18] = { atlas = "_DemonHunter-DemonicPainBar" },
}

-- Expose atlas-backed power types for ConfigSettings to check
ST.POWER_ATLAS_TYPES = { [8] = true, [11] = true, [13] = true, [17] = true, [18] = true }

-- Expose custom aura bar constants for ConfigSettings
ST.CUSTOM_AURA_BAR_BASE = CUSTOM_AURA_BAR_BASE
ST.MAX_CUSTOM_AURA_BARS = MAX_CUSTOM_AURA_BARS
local FormatBarTime = ST._FormatBarTime

-- Class-to-resource mapping (classID -> ordered list of power types)
-- Order = stacking order (first = closest to anchor)
local CLASS_RESOURCES = {
    [1]  = { 1 },           -- Warrior: Rage
    [2]  = { 9, 0 },        -- Paladin: HolyPower, Mana
    [3]  = { 2 },           -- Hunter: Focus
    [4]  = { 4, 3 },        -- Rogue: ComboPoints, Energy
    [5]  = { 0 },           -- Priest: Mana (Insanity added per spec)
    [6]  = { 5, 6 },        -- DK: Runes, RunicPower
    [7]  = { 0 },           -- Shaman: Mana (Maelstrom added per spec)
    [8]  = { 0 },           -- Mage: Mana (ArcaneCharges added per spec)
    [9]  = { 7, 0 },        -- Warlock: SoulShards, Mana
    [10] = { 0 },           -- Monk: Mana (Energy, Chi added per spec)
    [11] = nil,             -- Druid: form-dependent (handled separately)
    [12] = { 17 },          -- DH: Fury (Pain for Vengeance, per spec)
    [13] = { 19, 0 },       -- Evoker: Essence, Mana
}

-- Spec-specific resource overrides (specID -> resources to prepend before class defaults)
local SPEC_RESOURCES = {
    [258] = { 13, 0 },      -- Shadow Priest: Insanity, Mana
    [262] = { 11, 0 },      -- Elemental Shaman: Maelstrom, Mana
    [263] = { 100, 0 },      -- Enhancement Shaman: MW, Mana
    [62]  = { 16, 0 },      -- Arcane Mage: ArcaneCharges, Mana
    [269] = { 12, 3 },      -- Windwalker Monk: Chi, Energy
    [268] = { 3 },          -- Brewmaster Monk: Energy
    [581] = { 18 },         -- Vengeance DH: Pain
}

-- Druid form mapping (verified in-game: Bear=5, Cat=1, Moonkin=31)
local DRUID_FORM_RESOURCES = {
    [5]  = { 1 },           -- Bear: Rage
    [1]  = { 4, 3 },        -- Cat: ComboPoints, Energy
    [31] = { 8 },           -- Moonkin: LunarPower
}
local DRUID_DEFAULT_RESOURCES = { 0 }  -- No form: Mana

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------

local mwMaxStacks = 5

local isApplied = false
local hooksInstalled = false
local eventFrame = nil
local onUpdateFrame = nil
local containerFrameAbove = nil
local containerFrameBelow = nil
local lastAppliedWidth = nil
local resourceBarFrames = {}   -- array of bar frame objects (ordered by stacking)
local activeResources = {}     -- array of power type ints currently displayed
local isPreviewActive = false
local pendingSpecChange = false
local savedContainerAlpha = nil
local alphaSyncFrame = nil
local lastAppliedBarSpacing = nil
local lastAppliedBarHeight = nil
local layoutDirty = false

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local function GetResourceBarSettings()
    return CooldownCompanion.db and CooldownCompanion.db.profile
        and CooldownCompanion.db.profile.resourceBars
end

local function GetEffectiveAnchorGroupId(settings)
    if not settings then return nil end
    return settings.anchorGroupId or CooldownCompanion:GetFirstAvailableAnchorGroup()
end

local function GetAnchorGroupFrame(settings)
    local groupId = GetEffectiveAnchorGroupId(settings)
    if not groupId then return nil end
    return CooldownCompanion.groupFrames[groupId]
end

local function GetCurrentSpecID()
    local specIdx = C_SpecializationInfo.GetSpecialization()
    if specIdx then
        local specID = C_SpecializationInfo.GetSpecializationInfo(specIdx)
        return specID
    end
    return nil
end

local function GetPlayerClassID()
    local _, _, classID = UnitClass("player")
    return classID
end

local function GetSpecCustomAuraBars(settings)
    local specID = GetCurrentSpecID()
    if not specID then return {} end
    if not settings.customAuraBars then
        settings.customAuraBars = {}
    end
    if not settings.customAuraBars[specID] then
        settings.customAuraBars[specID] = {
            { enabled = false },
            { enabled = false },
            { enabled = false },
        }
    end
    return settings.customAuraBars[specID]
end

local function IsHealerSpec()
    local specIdx = C_SpecializationInfo.GetSpecialization()
    if specIdx then
        local _, _, _, _, role = C_SpecializationInfo.GetSpecializationInfo(specIdx)
        return role == "HEALER"
    end
    return false
end

local function GetDruidResources()
    local formID = GetShapeshiftFormID()
    if formID and DRUID_FORM_RESOURCES[formID] then
        return DRUID_FORM_RESOURCES[formID]
    end
    return DRUID_DEFAULT_RESOURCES
end

--- Determine which resources the current class/spec should display.
local function DetermineActiveResources()
    local classID = GetPlayerClassID()
    if not classID then return {} end

    -- Druid: form-dependent
    if classID == 11 then
        local resources = GetDruidResources()
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
            return result
        end
        return resources
    end

    -- Check spec-specific override first
    local specID = GetCurrentSpecID()
    if specID and SPEC_RESOURCES[specID] then
        return SPEC_RESOURCES[specID]
    end

    return CLASS_RESOURCES[classID] or {}
end

------------------------------------------------------------------------
-- Color resolution: data-driven lookup for all resource types
-- Each entry: { keys = { settingKey, ... }, defaults = { defaultValue, ... } }
-- GetResourceColors(powerType, settings) returns one value per key.
------------------------------------------------------------------------

local RESOURCE_COLOR_DEFS = {
    [4]   = { keys = { "comboColor", "comboMaxColor", "comboChargedColor" },
              defaults = { DEFAULT_COMBO_COLOR, DEFAULT_COMBO_MAX_COLOR, DEFAULT_COMBO_CHARGED_COLOR } },
    [5]   = { keys = { "runeReadyColor", "runeRechargingColor", "runeMaxColor" },
              defaults = { DEFAULT_RUNE_READY_COLOR, DEFAULT_RUNE_RECHARGING_COLOR, DEFAULT_RUNE_MAX_COLOR } },
    [7]   = { keys = { "shardReadyColor", "shardRechargingColor", "shardMaxColor" },
              defaults = { DEFAULT_SHARD_READY_COLOR, DEFAULT_SHARD_RECHARGING_COLOR, DEFAULT_SHARD_MAX_COLOR } },
    [9]   = { keys = { "holyColor", "holyMaxColor" },
              defaults = { DEFAULT_HOLY_COLOR, DEFAULT_HOLY_MAX_COLOR } },
    [12]  = { keys = { "chiColor", "chiMaxColor" },
              defaults = { DEFAULT_CHI_COLOR, DEFAULT_CHI_MAX_COLOR } },
    [16]  = { keys = { "arcaneColor", "arcaneMaxColor" },
              defaults = { DEFAULT_ARCANE_COLOR, DEFAULT_ARCANE_MAX_COLOR } },
    [19]  = { keys = { "essenceReadyColor", "essenceRechargingColor", "essenceMaxColor" },
              defaults = { DEFAULT_ESSENCE_READY_COLOR, DEFAULT_ESSENCE_RECHARGING_COLOR, DEFAULT_ESSENCE_MAX_COLOR } },
    [100] = { keys = { "mwBaseColor", "mwOverlayColor", "mwMaxColor" },
              defaults = { DEFAULT_MW_BASE_COLOR, DEFAULT_MW_OVERLAY_COLOR, DEFAULT_MW_MAX_COLOR } },
}

--- Generic color resolver. Returns one color per key defined in RESOURCE_COLOR_DEFS.
--- For power types without an entry (generic continuous), returns the single power color.
local function GetResourceColors(powerType, settings)
    local def = RESOURCE_COLOR_DEFS[powerType]
    if not def then
        -- Generic single-color fallback (continuous resources)
        if settings and settings.resources then
            local override = settings.resources[powerType]
            if override and override.color then
                return override.color
            end
        end
        return DEFAULT_POWER_COLORS[powerType] or { 1, 1, 1 }
    end

    local override = settings and settings.resources and settings.resources[powerType]
    local keys, defaults = def.keys, def.defaults
    local n = #keys
    if n == 2 then
        return (override and override[keys[1]]) or defaults[1],
               (override and override[keys[2]]) or defaults[2]
    elseif n == 3 then
        return (override and override[keys[1]]) or defaults[1],
               (override and override[keys[2]]) or defaults[2],
               (override and override[keys[3]]) or defaults[3]
    end
    -- Shouldn't happen, but safe fallback
    return defaults[1]
end

local function SupportsResourceAuraStackMode(powerType)
    return powerType == RESOURCE_MAELSTROM_WEAPON or SEGMENTED_TYPES[powerType] == true
end

local function GetResourceAuraTrackingMode(resource)
    if type(resource) ~= "table" then
        return "active"
    end
    if resource.auraColorTrackingMode == "stacks" or resource.auraColorTrackingMode == "active" then
        return resource.auraColorTrackingMode
    end
    local configured = tonumber(resource.auraColorMaxStacks)
    if configured and configured >= 2 then
        return "stacks"
    end
    return "active"
end

local function GetResourceAuraConfiguredMaxStacks(powerType, settings)
    if not settings or not settings.resources then return nil end
    local resource = settings.resources[powerType]
    if not resource then return nil end
    if GetResourceAuraTrackingMode(resource) ~= "stacks" then return nil end
    local configured = tonumber(resource.auraColorMaxStacks)
    if not configured then return nil end
    configured = math_floor(configured)
    if configured <= 1 then return nil end
    if configured > 99 then configured = 99 end
    return configured
end

local function IsResourceAuraOverlayEnabled(resource)
    if type(resource) ~= "table" then
        return false
    end
    if type(resource.auraOverlayEnabled) == "boolean" then
        return resource.auraOverlayEnabled
    end
    local auraSpellID = tonumber(resource.auraColorSpellID)
    return auraSpellID and auraSpellID > 0 or false
end

local function GetResourceAuraState(powerType, settings, auraActiveCache)
    if not settings or not settings.resources then return nil, nil, false end
    local resource = settings.resources[powerType]
    if not resource then return nil, nil, false end
    if not IsResourceAuraOverlayEnabled(resource) then return nil, nil, false end

    local auraSpellID = tonumber(resource.auraColorSpellID)
    if not auraSpellID or auraSpellID <= 0 then
        return nil, nil, false
    end

    local cached
    if auraActiveCache then
        cached = auraActiveCache[auraSpellID]
    end

    if not cached then
        cached = { active = false, applications = nil, hasApplications = false }

        if C_CVar.GetCVarBool("cooldownViewerEnabled") then
            local viewerFrame = CooldownCompanion.viewerAuraFrames and CooldownCompanion.viewerAuraFrames[auraSpellID]
            local instId = viewerFrame and viewerFrame.auraInstanceID
            if instId then
                local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID("player", instId)
                if auraData then
                    cached.active = true
                    if type(auraData.applications) == "number" then
                        -- applications can be secret in combat for some auras.
                        -- Keep as pass-through only (no Lua math/comparisons).
                        cached.applications = auraData.applications
                        cached.hasApplications = true
                    end
                end
            end
        end

        if not cached.active then
            -- Fallback for non-CDM spell IDs. In combat, secret aura restrictions can
            -- cause this API to return nil for some active auras.
            local auraData = C_UnitAuras.GetPlayerAuraBySpellID(auraSpellID)
            if auraData then
                cached.active = true
                if type(auraData.applications) == "number" then
                    -- applications can be secret in combat for some auras.
                    -- Keep as pass-through only (no Lua math/comparisons).
                    cached.applications = auraData.applications
                    cached.hasApplications = true
                end
            end
        end

        if auraActiveCache then
            auraActiveCache[auraSpellID] = cached
        end
    end

    if not cached.active then
        return nil, nil, false
    end

    local color = resource.auraActiveColor
    if type(color) ~= "table" or not color[1] or not color[2] or not color[3] then
        color = DEFAULT_RESOURCE_AURA_ACTIVE_COLOR
    end
    return color, cached.applications, cached.hasApplications
end

local function HideResourceAuraStackSegments(holder)
    if not holder or not holder.auraStackSegments then return end
    for _, seg in ipairs(holder.auraStackSegments) do
        seg:SetValue(0)
        seg:Hide()
    end
end

local function LayoutResourceAuraStackSegments(holder, settings)
    if not holder or not holder.auraStackSegments or not holder.segments then return end
    local barTexture = CooldownCompanion:FetchStatusBar(settings and settings.barTexture or "Solid")
    local borderStyle = settings and settings.borderStyle or "pixel"
    local borderSize = settings and settings.borderSize or 1

    for i, auraSeg in ipairs(holder.auraStackSegments) do
        local baseSeg = holder.segments[i]
        if baseSeg then
            local inset = (borderStyle == "pixel") and borderSize or 0
            if inset < 0 then inset = 0 end
            local usableHeight = baseSeg:GetHeight() - (inset * 2)
            if usableHeight < 1 then usableHeight = 1 end
            local laneHeight = math_floor((usableHeight * 0.5) + 0.5)
            laneHeight = math_max(1, math_min(usableHeight, laneHeight))

            auraSeg:ClearAllPoints()
            auraSeg:SetPoint("BOTTOMLEFT", baseSeg, "BOTTOMLEFT", inset, inset)
            auraSeg:SetPoint("BOTTOMRIGHT", baseSeg, "BOTTOMRIGHT", -inset, inset)
            auraSeg:SetHeight(laneHeight)
            auraSeg:SetStatusBarTexture(barTexture)
            auraSeg:SetFrameLevel(baseSeg:GetFrameLevel() + 4)
        else
            auraSeg:Hide()
        end
    end
end

local function EnsureResourceAuraStackSegments(holder, settings)
    if not holder or not holder.segments then return nil end
    local count = #holder.segments
    if count == 0 then return nil end

    if not holder.auraStackSegments or #holder.auraStackSegments ~= count then
        if holder.auraStackSegments then
            for _, oldSeg in ipairs(holder.auraStackSegments) do
                oldSeg:SetValue(0)
                oldSeg:ClearAllPoints()
                oldSeg:Hide()
            end
        end
        holder.auraStackSegments = {}
        for i = 1, count do
            local seg = CreateFrame("StatusBar", nil, holder)
            seg:SetMinMaxValues(0, 1)
            seg:SetValue(0)
            seg:Hide()
            holder.auraStackSegments[i] = seg
        end
    end

    LayoutResourceAuraStackSegments(holder, settings)
    return holder.auraStackSegments
end

local function ApplyResourceAuraStackSegments(holder, settings, stackValue, maxStacks, color)
    local auraSegments = EnsureResourceAuraStackSegments(holder, settings)
    if not auraSegments then return end

    local count = #auraSegments
    for i = 1, count do
        local seg = auraSegments[i]
        local segMin = ((i - 1) * maxStacks) / count
        local segMax = (i * maxStacks) / count
        seg:SetMinMaxValues(segMin, segMax)
        seg:SetValue(stackValue)
        seg:SetAlpha(1)
        seg:SetStatusBarColor(color[1], color[2], color[3], 1)
        seg:Show()
    end
end

local function ClearResourceAuraVisuals(frame)
    if not frame then return end
    HideResourceAuraStackSegments(frame)
end

local function ApplyContinuousFillColor(bar, powerType, settings, overrideColor)
    if not bar or not settings then return end

    local texName = settings.barTexture or "Solid"
    local atlasInfo = (texName == "blizzard_class") and POWER_ATLAS_INFO[powerType] or nil
    if atlasInfo then
        if overrideColor then
            bar:SetStatusBarColor(overrideColor[1], overrideColor[2], overrideColor[3], 1)
            bar.brightnessOverlay:Hide()
            return
        end

        local brightness = settings.classBarBrightness or 1.3
        bar:SetStatusBarColor(1, 1, 1, 1)
        if brightness > 1.0 then
            bar.brightnessOverlay:SetAlpha(brightness - 1.0)
            bar.brightnessOverlay:Show()
        elseif brightness < 1.0 then
            bar:SetStatusBarColor(brightness, brightness, brightness, 1)
            bar.brightnessOverlay:Hide()
        else
            bar.brightnessOverlay:Hide()
        end
        return
    end

    local color = overrideColor or GetResourceColors(powerType, settings)
    bar:SetStatusBarColor(color[1], color[2], color[3], 1)
    bar.brightnessOverlay:Hide()
end

--- Update cached MW max stacks based on Raging Maelstrom talent (OOC only — talents can't change in combat).
--- Returns true if the max changed (and bars were rebuilt), false otherwise.
local function UpdateMWMaxStacks()
    local hasRagingMaelstrom = C_SpellBook.IsSpellKnown(RAGING_MAELSTROM_SPELL_ID, Enum.SpellBookSpellBank.Player)
    local newMax = hasRagingMaelstrom and 10 or 5
    if mwMaxStacks ~= newMax then
        mwMaxStacks = newMax
        CooldownCompanion:ApplyResourceBars()  -- segment count changed, rebuild
        return true
    end
    return false
end

--- Check if a specific resource is enabled in settings.
local function IsResourceEnabled(powerType, settings)
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
-- Frame creation: Pixel borders (reused pattern)
------------------------------------------------------------------------

local function CreatePixelBorders(parent)
    local borders = {}
    local names = { "TOP", "BOTTOM", "LEFT", "RIGHT" }
    for _, side in ipairs(names) do
        local tex = parent:CreateTexture(nil, "OVERLAY", nil, 7)
        tex:SetColorTexture(0, 0, 0, 1)
        tex:Hide()
        borders[side] = tex
    end
    return borders
end

local function ApplyPixelBorders(borders, parent, color, size)
    if not borders then return end
    local r, g, b, a = color[1], color[2], color[3], color[4]
    size = size or 1

    for _, tex in pairs(borders) do
        tex:SetColorTexture(r, g, b, a)
        tex:Show()
    end

    borders.TOP:ClearAllPoints()
    borders.TOP:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    borders.TOP:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    borders.TOP:SetHeight(size)

    borders.BOTTOM:ClearAllPoints()
    borders.BOTTOM:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    borders.BOTTOM:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    borders.BOTTOM:SetHeight(size)

    borders.LEFT:ClearAllPoints()
    borders.LEFT:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -size)
    borders.LEFT:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, size)
    borders.LEFT:SetWidth(size)

    borders.RIGHT:ClearAllPoints()
    borders.RIGHT:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -size)
    borders.RIGHT:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, size)
    borders.RIGHT:SetWidth(size)
end

local function HidePixelBorders(borders)
    if not borders then return end
    for _, tex in pairs(borders) do
        tex:Hide()
    end
end

local function IsCustomAuraMaxThresholdEnabled(cabConfig)
    return cabConfig and cabConfig.thresholdColorEnabled == true and cabConfig.trackingMode ~= "active"
end

local function GetCustomAuraMaxThresholdColor(cabConfig)
    if cabConfig and cabConfig.thresholdMaxColor then
        return cabConfig.thresholdMaxColor
    end
    return DEFAULT_CUSTOM_AURA_MAX_COLOR
end

local function SetCustomAuraMaxThresholdRange(bar, maxStacks)
    if not bar then return end
    local safeMax = maxStacks or 1
    if safeMax < 1 then safeMax = 1 end
    bar:SetMinMaxValues(safeMax - 1, safeMax)
end

local function EnsureCustomAuraContinuousThresholdOverlay(bar)
    if not bar or bar.thresholdOverlay then return end
    local overlay = CreateFrame("StatusBar", nil, bar)
    overlay:SetFrameLevel(bar:GetFrameLevel() + 1)
    overlay:SetMinMaxValues(0, 1)
    overlay:SetValue(0)
    overlay:Hide()
    bar.thresholdOverlay = overlay
end

local function EnsureCustomAuraSegmentThresholdOverlays(holder)
    if not holder or not holder.segments or holder.thresholdSegments then return end
    holder.thresholdSegments = {}
    for i = 1, #holder.segments do
        local seg = CreateFrame("StatusBar", nil, holder)
        seg:SetFrameLevel(holder:GetFrameLevel() + 3)
        seg:SetMinMaxValues(0, 1)
        seg:SetValue(0)
        seg:Hide()
        holder.thresholdSegments[i] = seg
    end
end

local function EnsureCustomAuraOverlayThresholdOverlays(holder, halfSegments)
    if not holder or holder.thresholdSegments then return end
    holder.thresholdSegments = {}
    for i = 1, halfSegments do
        local seg = CreateFrame("StatusBar", nil, holder)
        seg:SetFrameLevel(holder:GetFrameLevel() + 4)
        seg:SetMinMaxValues(0, 1)
        seg:SetValue(0)
        seg:Hide()
        holder.thresholdSegments[i] = seg
    end
end

local function LayoutCustomAuraContinuousThresholdOverlay(bar, barTexture, borderStyle, borderSize)
    if not bar or not bar.thresholdOverlay then return end
    local overlay = bar.thresholdOverlay
    overlay:SetFrameLevel(bar:GetFrameLevel() + 1)
    if bar.textLayer then
        bar.textLayer:SetFrameLevel(overlay:GetFrameLevel() + 1)
    end
    overlay:ClearAllPoints()
    if borderStyle == "pixel" then
        overlay:SetPoint("TOPLEFT", bar, "TOPLEFT", borderSize, -borderSize)
        overlay:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -borderSize, borderSize)
    else
        overlay:SetAllPoints(bar)
    end
    overlay:SetStatusBarTexture(barTexture)
end

------------------------------------------------------------------------
-- Frame creation: Continuous bar
------------------------------------------------------------------------

local function CreateContinuousBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(CooldownCompanion:FetchStatusBar("Solid"))
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(0)

    -- Background
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0, 0, 0, 0.5)

    -- Pixel borders
    bar.borders = CreatePixelBorders(bar)

    -- Text container is kept above custom aura threshold overlays.
    bar.textLayer = CreateFrame("Frame", nil, bar)
    bar.textLayer:SetAllPoints(bar)
    bar.textLayer:SetFrameLevel(bar:GetFrameLevel() + 2)

    -- Text
    bar.text = bar.textLayer:CreateFontString(nil, "OVERLAY")
    bar.text:SetFont(CooldownCompanion:FetchFont("Friz Quadrata TT"), 10, "OUTLINE")
    bar.text:SetPoint("CENTER")
    bar.text:SetTextColor(1, 1, 1, 1)

    -- Brightness overlay (additive layer for atlas textures, since SetStatusBarColor clamps to [0,1])
    bar.brightnessOverlay = bar:CreateTexture(nil, "ARTWORK", nil, 1)
    bar.brightnessOverlay:SetBlendMode("ADD")
    bar.brightnessOverlay:Hide()

    bar._barType = "continuous"
    return bar
end

------------------------------------------------------------------------
-- Frame creation: Segmented bar
------------------------------------------------------------------------

local function CreateSegmentedBar(parent, numSegments)
    local holder = CreateFrame("Frame", nil, parent)

    holder.segments = {}
    for i = 1, numSegments do
        local seg = CreateFrame("StatusBar", nil, holder)
        seg:SetStatusBarTexture(CooldownCompanion:FetchStatusBar("Solid"))
        seg:SetMinMaxValues(0, 1)
        seg:SetValue(0)

        seg.bg = seg:CreateTexture(nil, "BACKGROUND")
        seg.bg:SetAllPoints()
        seg.bg:SetColorTexture(0, 0, 0, 0.5)

        seg.borders = CreatePixelBorders(seg)

        holder.segments[i] = seg
    end

    holder._barType = "segmented"
    holder._numSegments = numSegments
    return holder
end

------------------------------------------------------------------------
-- Layout: position segments within a segmented bar
------------------------------------------------------------------------

local function LayoutSegments(holder, totalWidth, totalHeight, gap, settings)
    if not holder or not holder.segments then return end
    local n = #holder.segments
    if n == 0 then return end

    local subWidth = (totalWidth - (n - 1) * gap) / n
    if subWidth < 1 then subWidth = 1 end

    local barTexture = CooldownCompanion:FetchStatusBar(settings and settings.barTexture or "Solid")
    local bgColor = settings and settings.backgroundColor or { 0, 0, 0, 0.5 }
    local borderStyle = settings and settings.borderStyle or "pixel"
    local borderColor = settings and settings.borderColor or { 0, 0, 0, 1 }
    local borderSize = settings and settings.borderSize or 1

    for i, seg in ipairs(holder.segments) do
        seg:ClearAllPoints()
        seg:SetSize(subWidth, totalHeight)
        local xOfs = (i - 1) * (subWidth + gap)
        seg:SetPoint("TOPLEFT", holder, "TOPLEFT", xOfs, 0)

        seg:SetStatusBarTexture(barTexture)
        seg.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])

        if borderStyle == "pixel" then
            ApplyPixelBorders(seg.borders, seg, borderColor, borderSize)
        else
            HidePixelBorders(seg.borders)
        end

        if holder.thresholdSegments and holder.thresholdSegments[i] then
            local thresholdSeg = holder.thresholdSegments[i]
            thresholdSeg:ClearAllPoints()
            if borderStyle == "pixel" then
                thresholdSeg:SetPoint("TOPLEFT", seg, "TOPLEFT", borderSize, -borderSize)
                thresholdSeg:SetPoint("BOTTOMRIGHT", seg, "BOTTOMRIGHT", -borderSize, borderSize)
            else
                thresholdSeg:SetAllPoints(seg)
            end
            thresholdSeg:SetStatusBarTexture(barTexture)
        end
    end

    if holder.auraStackSegments then
        LayoutResourceAuraStackSegments(holder, settings)
    end
end

------------------------------------------------------------------------
-- Frame creation: Overlay bar (base + overlay segments)
-- Used by custom aura bars in "overlay" display mode.
-- halfSegments = number of segments per layer (e.g. 5 for 10-max).
------------------------------------------------------------------------

local function CreateOverlayBar(parent, halfSegments)
    local holder = CreateFrame("Frame", nil, parent)

    holder.segments = {}
    for i = 1, halfSegments do
        local seg = CreateFrame("StatusBar", nil, holder)
        seg:SetStatusBarTexture(CooldownCompanion:FetchStatusBar("Solid"))
        seg:SetMinMaxValues(i - 1, i)
        seg:SetValue(0)

        seg.bg = seg:CreateTexture(nil, "BACKGROUND")
        seg.bg:SetAllPoints()
        seg.bg:SetColorTexture(0, 0, 0, 0.5)

        seg.borders = CreatePixelBorders(seg)

        holder.segments[i] = seg
    end

    holder.overlaySegments = {}
    for i = 1, halfSegments do
        local seg = CreateFrame("StatusBar", nil, holder)
        seg:SetFrameLevel(holder:GetFrameLevel() + 2)
        seg:SetStatusBarTexture(CooldownCompanion:FetchStatusBar("Solid"))
        seg:SetMinMaxValues(i + halfSegments - 1, i + halfSegments)
        seg:SetValue(0)

        -- No background on overlay (transparent when empty, base bg shows through)

        holder.overlaySegments[i] = seg
    end

    return holder
end

local function LayoutOverlaySegments(holder, totalWidth, totalHeight, gap, settings, halfSegments)
    if not holder or not holder.segments then return end

    local subWidth = (totalWidth - (halfSegments - 1) * gap) / halfSegments
    if subWidth < 1 then subWidth = 1 end

    local barTexture = CooldownCompanion:FetchStatusBar(settings and settings.barTexture or "Solid")
    local bgColor = settings and settings.backgroundColor or { 0, 0, 0, 0.5 }
    local borderStyle = settings and settings.borderStyle or "pixel"
    local borderColor = settings and settings.borderColor or { 0, 0, 0, 1 }
    local borderSize = settings and settings.borderSize or 1

    for i = 1, halfSegments do
        local seg = holder.segments[i]
        seg:ClearAllPoints()
        seg:SetSize(subWidth, totalHeight)
        local xOfs = (i - 1) * (subWidth + gap)
        seg:SetPoint("TOPLEFT", holder, "TOPLEFT", xOfs, 0)

        seg:SetStatusBarTexture(barTexture)
        seg.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])

        if borderStyle == "pixel" then
            ApplyPixelBorders(seg.borders, seg, borderColor, borderSize)
        else
            HidePixelBorders(seg.borders)
        end

        -- Position overlay segment inset by border to stay inside borders
        local ov = holder.overlaySegments[i]
        ov:ClearAllPoints()
        if borderStyle == "pixel" then
            ov:SetPoint("TOPLEFT", seg, "TOPLEFT", borderSize, -borderSize)
            ov:SetPoint("BOTTOMRIGHT", seg, "BOTTOMRIGHT", -borderSize, borderSize)
        else
            ov:SetAllPoints(seg)
        end
        ov:SetStatusBarTexture(barTexture)

        if holder.thresholdSegments and holder.thresholdSegments[i] then
            local thresholdSeg = holder.thresholdSegments[i]
            thresholdSeg:ClearAllPoints()
            if borderStyle == "pixel" then
                thresholdSeg:SetPoint("TOPLEFT", seg, "TOPLEFT", borderSize, -borderSize)
                thresholdSeg:SetPoint("BOTTOMRIGHT", seg, "BOTTOMRIGHT", -borderSize, borderSize)
            else
                thresholdSeg:SetAllPoints(seg)
            end
            thresholdSeg:SetStatusBarTexture(barTexture)
        end
    end

    if holder.auraStackSegments then
        LayoutResourceAuraStackSegments(holder, settings)
    end
end

------------------------------------------------------------------------
-- Update logic: Continuous resources (SECRET in combat — NO Lua arithmetic)
------------------------------------------------------------------------

local function UpdateContinuousBar(bar, powerType, settings, auraActiveCache)
    if not settings then
        settings = GetResourceBarSettings()
    end

    local currentPower = UnitPower("player", powerType)
    local maxPower = UnitPowerMax("player", powerType)

    -- SetMinMaxValues: max is NOT secret
    bar:SetMinMaxValues(0, maxPower)
    -- SetValue: pass UnitPower directly to C-level — accepts secrets
    bar:SetValue(currentPower)

    local auraOverrideColor = GetResourceAuraState(powerType, settings, auraActiveCache)
    ApplyContinuousFillColor(bar, powerType, settings, auraOverrideColor)

    -- Text: pass directly to C-level SetFormattedText — accepts secrets
    if bar.text and bar.text:IsShown() then
        local textFormat = bar._textFormat
        if textFormat == "current" then
            bar.text:SetFormattedText("%d", currentPower)
        elseif textFormat == "percent" then
            -- UnitPowerPercent returns a 0..1 value by default; evaluate through a curve
            -- to get 0..100 without Lua arithmetic (secret-safe in combat).
            bar.text:SetFormattedText("%.0f", UnitPowerPercent("player", powerType, false, PERCENT_SCALE_CURVE))
        else
            bar.text:SetFormattedText("%d / %d", currentPower, maxPower)
        end
    end

end

------------------------------------------------------------------------
-- Update logic: Segmented resources (NOT secret — full Lua logic)
------------------------------------------------------------------------

local function UpdateSegmentedBar(holder, powerType, settings, auraActiveCache)
    if not holder or not holder.segments then return end
    if not settings then
        settings = GetResourceBarSettings()
    end

    local auraOverrideColor, auraApplications, auraHasApplications = GetResourceAuraState(powerType, settings, auraActiveCache)
    local auraMaxStacks = GetResourceAuraConfiguredMaxStacks(powerType, settings)
    local useAuraStackMode = auraOverrideColor
        and auraMaxStacks
        and auraHasApplications
        and SupportsResourceAuraStackMode(powerType)
    local fullSegments = {}

    local function FinalizeAuraVisuals()
        if auraOverrideColor and not useAuraStackMode then
            for i, seg in ipairs(holder.segments) do
                if fullSegments[i] then
                    seg:SetStatusBarColor(auraOverrideColor[1], auraOverrideColor[2], auraOverrideColor[3], 1)
                end
            end
        end

        if useAuraStackMode then
            ApplyResourceAuraStackSegments(holder, settings, auraApplications, auraMaxStacks, auraOverrideColor)
        else
            HideResourceAuraStackSegments(holder)
        end
    end

    if powerType == 5 then
        -- DK Runes: sorted by readiness (ready left, longest CD right)
        local now = GetTime()
        local numSegs = math_min(#holder.segments, 6)
        local runeData = {}
        for i = 1, 6 do
            local start, duration, ready = GetRuneCooldown(i)
            local remaining = 0
            if not ready and duration and duration > 0 then
                remaining = math_max((start + duration) - now, 0)
            end
            runeData[i] = { start = start, duration = duration, ready = ready, remaining = remaining }
        end
        -- Sort: ready first, then by ascending remaining time
        table.sort(runeData, function(a, b)
            if a.ready ~= b.ready then return a.ready end
            return a.remaining < b.remaining
        end)
        local readyColor, rechargingColor, maxColor = GetResourceColors(5, settings)
        local allReady = true
        for i = 1, numSegs do
            if not runeData[i].ready then allReady = false; break end
        end
        local activeReadyColor = allReady and maxColor or readyColor
        for i = 1, numSegs do
            local r = runeData[i]
            local seg = holder.segments[i]
            if r.ready then
                seg:SetValue(1)
                seg:SetStatusBarColor(activeReadyColor[1], activeReadyColor[2], activeReadyColor[3], 1)
                fullSegments[i] = true
            elseif r.duration and r.duration > 0 then
                seg:SetValue(math_min((now - r.start) / r.duration, 1))
                seg:SetStatusBarColor(rechargingColor[1], rechargingColor[2], rechargingColor[3], 1)
            else
                seg:SetValue(0)
                seg:SetStatusBarColor(rechargingColor[1], rechargingColor[2], rechargingColor[3], 1)
            end
        end
        FinalizeAuraVisuals()
        return
    end

    if powerType == 7 then
        -- Soul Shards: fractional fill with ready/recharging colors
        local raw = UnitPower("player", 7, true)
        local rawMax = UnitPowerMax("player", 7, true)
        local max = UnitPowerMax("player", 7)
        if max > 0 and rawMax > 0 then
            local perShard = rawMax / max
            local filled = math_floor(raw / perShard)
            local partial = (raw % perShard) / perShard
            local readyColor, rechargingColor, maxColor = GetResourceColors(7, settings)
            local isMax = (filled == max)
            local activeReadyColor = isMax and maxColor or readyColor
            for i = 1, math_min(#holder.segments, max) do
                local seg = holder.segments[i]
                if i <= filled then
                    seg:SetValue(1)
                    seg:SetStatusBarColor(activeReadyColor[1], activeReadyColor[2], activeReadyColor[3], 1)
                    fullSegments[i] = true
                elseif i == filled + 1 and partial > 0 then
                    seg:SetValue(partial)
                    seg:SetStatusBarColor(rechargingColor[1], rechargingColor[2], rechargingColor[3], 1)
                else
                    seg:SetValue(0)
                    seg:SetStatusBarColor(rechargingColor[1], rechargingColor[2], rechargingColor[3], 1)
                end
            end
        end
        FinalizeAuraVisuals()
        return
    end

    if powerType == 19 then
        -- Essence: partial recharge with ready/recharging colors
        local filled = UnitPower("player", 19)
        local max = UnitPowerMax("player", 19)
        local partial = UnitPartialPower("player", 19) / 1000
        local readyColor, rechargingColor, maxColor = GetResourceColors(19, settings)
        local isMax = (filled == max)
        local activeReadyColor = isMax and maxColor or readyColor
        for i = 1, math_min(#holder.segments, max) do
            local seg = holder.segments[i]
            if i <= filled then
                seg:SetValue(1)
                seg:SetStatusBarColor(activeReadyColor[1], activeReadyColor[2], activeReadyColor[3], 1)
                fullSegments[i] = true
            elseif i == filled + 1 and partial > 0 then
                seg:SetValue(partial)
                seg:SetStatusBarColor(rechargingColor[1], rechargingColor[2], rechargingColor[3], 1)
            else
                seg:SetValue(0)
                seg:SetStatusBarColor(rechargingColor[1], rechargingColor[2], rechargingColor[3], 1)
            end
        end
        FinalizeAuraVisuals()
        return
    end

    -- Combo Points: color changes at max, charged coloring for Rogues
    if powerType == 4 then
        local current = UnitPower("player", 4)
        local max = UnitPowerMax("player", 4)
        local normalColor, maxColor, chargedColor = GetResourceColors(4, settings)
        local isMax = (current == max and max > 0)
        local baseColor = isMax and maxColor or normalColor

        -- Charged combo points (Rogue only)
        local chargedPoints
        if GetPlayerClassID() == 4 then
            chargedPoints = GetUnitChargedPowerPoints("player")
        end

        for i = 1, math_min(#holder.segments, max) do
            local seg = holder.segments[i]
            if i <= current then
                seg:SetValue(1)
                fullSegments[i] = true
                if chargedPoints and tContains(chargedPoints, i) then
                    seg:SetStatusBarColor(chargedColor[1], chargedColor[2], chargedColor[3], 1)
                else
                    seg:SetStatusBarColor(baseColor[1], baseColor[2], baseColor[3], 1)
                end
            else
                seg:SetValue(0)
            end
        end
        FinalizeAuraVisuals()
        return
    end

    -- Generic segmented with max color: HolyPower, Chi, ArcaneCharges
    local current = UnitPower("player", powerType)
    local max = UnitPowerMax("player", powerType)
    local normalColor, maxColor
    if RESOURCE_COLOR_DEFS[powerType] then
        normalColor, maxColor = GetResourceColors(powerType, settings)
    else
        local color = GetResourceColors(powerType, settings)
        normalColor, maxColor = color, color
    end
    local isMax = (current == max and max > 0)
    local activeColor = isMax and maxColor or normalColor
    for i = 1, math_min(#holder.segments, max) do
        local seg = holder.segments[i]
        if i <= current then
            seg:SetValue(1)
            seg:SetStatusBarColor(activeColor[1], activeColor[2], activeColor[3], 1)
            fullSegments[i] = true
        else
            seg:SetValue(0)
        end
    end
    FinalizeAuraVisuals()
end

------------------------------------------------------------------------
-- Update logic: Maelstrom Weapon (overlay bar, plain applications)
------------------------------------------------------------------------

local function UpdateMaelstromWeaponBar(holder, settings, auraActiveCache)
    if not holder or not holder.segments then return end
    if not settings then
        settings = GetResourceBarSettings()
    end

    -- Read stacks from viewer frame (applications is plain for MW)
    local stacks = 0
    local viewerFrame = CooldownCompanion.viewerAuraFrames and CooldownCompanion.viewerAuraFrames[MW_SPELL_ID]
    local instId = viewerFrame and viewerFrame.auraInstanceID
    if instId then
        local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID("player", instId)
        if auraData then
            stacks = auraData.applications or 0
        end
    end

    local half = #holder.segments
    local baseColor, overlayColor, maxColor = GetResourceColors(100, settings)
    local isMax = stacks > 0 and stacks == mwMaxStacks

    for i = 1, half do
        local baseSeg = holder.segments[i]
        local overlaySeg = holder.overlaySegments[i]

        baseSeg:SetValue(stacks)
        overlaySeg:SetValue(stacks)
        -- Hide right-half overlay segments when value is at/below their segment minimum.
        -- This prevents tiny leading-edge ticks on empty overlay segments.
        if stacks > (half + i - 1) then
            overlaySeg:SetAlpha(1)
        else
            overlaySeg:SetAlpha(0)
        end

        if isMax then
            baseSeg:SetStatusBarColor(maxColor[1], maxColor[2], maxColor[3], 1)
            overlaySeg:SetStatusBarColor(maxColor[1], maxColor[2], maxColor[3], 1)
        else
            baseSeg:SetStatusBarColor(baseColor[1], baseColor[2], baseColor[3], 1)
            overlaySeg:SetStatusBarColor(overlayColor[1], overlayColor[2], overlayColor[3], 1)
        end
    end

    local auraOverrideColor, auraApplications, auraHasApplications = GetResourceAuraState(100, settings, auraActiveCache)
    local auraMaxStacks = GetResourceAuraConfiguredMaxStacks(100, settings)
    local useAuraStackMode = auraOverrideColor and auraMaxStacks and auraHasApplications and SupportsResourceAuraStackMode(100)

    if auraOverrideColor and not useAuraStackMode then
        for i = 1, half do
            if stacks >= i then
                holder.segments[i]:SetStatusBarColor(auraOverrideColor[1], auraOverrideColor[2], auraOverrideColor[3], 1)
            end
            if stacks >= (half + i) then
                holder.overlaySegments[i]:SetStatusBarColor(auraOverrideColor[1], auraOverrideColor[2], auraOverrideColor[3], 1)
            end
        end
    end

    if useAuraStackMode then
        ApplyResourceAuraStackSegments(holder, settings, auraApplications, auraMaxStacks, auraOverrideColor)
    else
        HideResourceAuraStackSegments(holder)
    end
end

------------------------------------------------------------------------
-- Update logic: Custom aura bars (aura-based, secret-safe)
------------------------------------------------------------------------

local function UpdateCustomAuraBar(barInfo)
    local cabConfig = barInfo.cabConfig
    if not cabConfig or not cabConfig.spellID then return end

    -- Read aura data from viewer frame (applications may be secret in combat)
    local stacks = 0
    local applications = 0
    local auraPresent = false
    local durationObj
    local isActive = cabConfig.trackingMode == "active"
    local useDrain = isActive
    local needsDuration = useDrain or cabConfig.showDurationText
    local viewerFrame = CooldownCompanion.viewerAuraFrames and CooldownCompanion.viewerAuraFrames[cabConfig.spellID]
    local instId = viewerFrame and viewerFrame.auraInstanceID
    if instId then
        local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID("player", instId)
        if auraData then
            auraPresent = true
            applications = auraData.applications or 0
            if isActive then
                stacks = 1
            else
                stacks = applications
            end
            if needsDuration then
                durationObj = C_UnitAuras.GetAuraDuration("player", instId)
            end
        end
    end

    -- Hide When Inactive: hide the bar frame when aura is absent
    if cabConfig.hideWhenInactive then
        local wasShown = barInfo.frame:IsShown()
        barInfo.frame:SetShown(auraPresent)
        if wasShown ~= auraPresent then
            layoutDirty = true
        end
        if not auraPresent then return end
    end

    local maxStacks = cabConfig.maxStacks or 1
    local thresholdEnabled = IsCustomAuraMaxThresholdEnabled(cabConfig)

    if barInfo.barType == "custom_continuous" then
        local bar = barInfo.frame
        if useDrain then
            bar:SetMinMaxValues(0, 1)
            if durationObj then
                bar:SetValue(durationObj:GetRemainingPercent())  -- secret-safe, 1->0 drain
            else
                -- No DurationObject (indefinite aura or aura absent)
                bar:SetValue(stacks)  -- 1 if active (full), 0 if absent (empty)
            end
        else
            bar:SetMinMaxValues(0, maxStacks)
            bar:SetValue(stacks)  -- SetValue accepts secrets
        end

        if bar.thresholdOverlay then
            if thresholdEnabled then
                SetCustomAuraMaxThresholdRange(bar.thresholdOverlay, maxStacks)
                bar.thresholdOverlay:SetValue(stacks)
                bar.thresholdOverlay:Show()
            else
                bar.thresholdOverlay:SetValue(0)
                bar.thresholdOverlay:Hide()
            end
        end

        -- Duration text (bar.text): driven by showDurationText, independent of drain
        if bar.text and bar.text:IsShown() then
            if durationObj then
                local remaining = durationObj:GetRemainingDuration()
                if not durationObj:HasSecretValues() then
                    if remaining > 0 then
                        bar.text:SetText(FormatBarTime(remaining))
                    else
                        bar.text:SetText("")
                    end
                else
                    bar.text:SetFormattedText("%.1f", remaining)
                end
            else
                bar.text:SetText("")
            end
        end

        -- Stack text (bar.stackText): driven by showStackText
        if bar.stackText and bar.stackText:IsShown() then
            if auraPresent then
                if isActive then
                    bar.stackText:SetFormattedText("%d", applications)
                else
                    bar.stackText:SetFormattedText("%d / %d", stacks, maxStacks)
                end
            else
                bar.stackText:SetText("")
            end
        end

    elseif barInfo.barType == "custom_segmented" then
        local holder = barInfo.frame
        if not holder.segments then return end
        -- Each segment has MinMax(i-1, i) — SetValue(stacks) with C-level clamping
        -- handles fill/empty without comparing the secret stacks value in Lua
        for i = 1, #holder.segments do
            holder.segments[i]:SetValue(stacks)
        end

        if holder.thresholdSegments then
            for i = 1, #holder.thresholdSegments do
                local thresholdSeg = holder.thresholdSegments[i]
                if thresholdEnabled then
                    SetCustomAuraMaxThresholdRange(thresholdSeg, maxStacks)
                    thresholdSeg:SetValue(stacks)
                    thresholdSeg:Show()
                else
                    thresholdSeg:SetValue(0)
                    thresholdSeg:Hide()
                end
            end
        end

    elseif barInfo.barType == "custom_overlay" then
        local holder = barInfo.frame
        if not holder.segments then return end
        local half = barInfo.halfSegments or 1

        -- Pass stacks to ALL segments (StatusBar C-level clamping handles per-segment fill)
        for i = 1, half do
            holder.segments[i]:SetValue(stacks)
            holder.overlaySegments[i]:SetValue(stacks)
        end

        if holder.thresholdSegments then
            for i = 1, half do
                local thresholdSeg = holder.thresholdSegments[i]
                if thresholdEnabled then
                    SetCustomAuraMaxThresholdRange(thresholdSeg, maxStacks)
                    thresholdSeg:SetValue(stacks)
                    thresholdSeg:Show()
                else
                    thresholdSeg:SetValue(0)
                    thresholdSeg:Hide()
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- Styling: Custom aura bars
------------------------------------------------------------------------

local function StyleCustomAuraBar(barInfo, cabConfig)
    local barColor = cabConfig.barColor or {0.5, 0.5, 1}
    local thresholdEnabled = IsCustomAuraMaxThresholdEnabled(cabConfig)
    local thresholdColor = GetCustomAuraMaxThresholdColor(cabConfig)

    if barInfo.barType == "custom_continuous" then
        local bar = barInfo.frame
        bar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], 1)
        if bar.thresholdOverlay then
            bar.thresholdOverlay:SetStatusBarColor(thresholdColor[1], thresholdColor[2], thresholdColor[3], 1)
            bar.thresholdOverlay:SetShown(thresholdEnabled)
        end

        -- Determine visibility for both text elements
        local isActive = cabConfig.trackingMode == "active"
        local showDuration = cabConfig.showDurationText == true
        local showStack = cabConfig.showStackText
        if showStack == nil then
            -- Backwards compat: fall back to showText for stacks mode
            if not isActive then
                showStack = cabConfig.showText == true
            else
                showStack = false
            end
        end

        -- Duration text (bar.text)
        if bar.text then
            bar.text:SetShown(showDuration)
            if showDuration then
                bar.text:ClearAllPoints()
                if showStack then
                    bar.text:SetPoint("LEFT", bar, "LEFT", 4, 0)
                else
                    bar.text:SetPoint("CENTER")
                end
            end
        end

        -- Stack text (bar.stackText)
        if bar.stackText then
            bar.stackText:SetShown(showStack)
            if showStack then
                bar.stackText:ClearAllPoints()
                if showDuration then
                    bar.stackText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
                else
                    bar.stackText:SetPoint("CENTER")
                end
            end
        end

    elseif barInfo.barType == "custom_segmented" then
        local holder = barInfo.frame
        if holder.segments then
            for _, seg in ipairs(holder.segments) do
                seg:SetStatusBarColor(barColor[1], barColor[2], barColor[3], 1)
            end
        end
        if holder.thresholdSegments then
            for _, seg in ipairs(holder.thresholdSegments) do
                seg:SetStatusBarColor(thresholdColor[1], thresholdColor[2], thresholdColor[3], 1)
                seg:SetShown(thresholdEnabled)
            end
        end

    elseif barInfo.barType == "custom_overlay" then
        local holder = barInfo.frame
        local overlayColor = cabConfig.overlayColor or {1, 0.84, 0}
        local half = barInfo.halfSegments or 1
        if holder.segments then
            for i = 1, half do
                holder.segments[i]:SetStatusBarColor(barColor[1], barColor[2], barColor[3], 1)
                holder.overlaySegments[i]:SetStatusBarColor(overlayColor[1], overlayColor[2], overlayColor[3], 1)
                holder.overlaySegments[i]:Show()
                if holder.thresholdSegments and holder.thresholdSegments[i] then
                    holder.thresholdSegments[i]:SetStatusBarColor(thresholdColor[1], thresholdColor[2], thresholdColor[3], 1)
                    holder.thresholdSegments[i]:SetShown(thresholdEnabled)
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- Live recolor for custom aura bars (called from config color picker)
------------------------------------------------------------------------

function CooldownCompanion:RecolorCustomAuraBar(cabConfig)
    for _, barInfo in ipairs(resourceBarFrames) do
        if barInfo.cabConfig == cabConfig then
            StyleCustomAuraBar(barInfo, cabConfig)
            break
        end
    end
end

------------------------------------------------------------------------
-- Relayout: reposition bars within their containers by visibility/order
-- Called from ApplyResourceBars() and from OnUpdate when layoutDirty.
------------------------------------------------------------------------

local function CompareBarOrder(a, b)
    if a._order ~= b._order then return a._order < b._order end
    return (a.powerType or 0) < (b.powerType or 0)
end

local function RelayoutBars()
    if not containerFrameAbove or not containerFrameBelow then return end
    local barSpacing = lastAppliedBarSpacing or 3.6
    local globalBarHeight = lastAppliedBarHeight or 12

    local aboveBars = {}
    local belowBars = {}
    for _, barInfo in ipairs(resourceBarFrames) do
        if barInfo and barInfo.frame and barInfo.frame:IsShown() then
            if barInfo._side == "above" then
                table.insert(aboveBars, barInfo)
            else
                table.insert(belowBars, barInfo)
            end
        end
    end
    table.sort(aboveBars, CompareBarOrder)
    table.sort(belowBars, CompareBarOrder)

    -- Stack above bars (order ascending = bottom to top; order=1 closest to group)
    local currentY = 0
    for _, barInfo in ipairs(aboveBars) do
        barInfo.frame:ClearAllPoints()
        barInfo.frame:SetPoint("BOTTOMLEFT", containerFrameAbove, "BOTTOMLEFT", 0, currentY)
        barInfo.frame:SetPoint("BOTTOMRIGHT", containerFrameAbove, "BOTTOMRIGHT", 0, currentY)
        local h = barInfo._effectiveHeight or globalBarHeight
        barInfo.frame:SetHeight(h)
        currentY = currentY + h + barSpacing
    end
    local aboveHeight = currentY > 0 and (currentY - barSpacing) or 1
    containerFrameAbove:SetHeight(aboveHeight)
    if #aboveBars > 0 then containerFrameAbove:Show() else containerFrameAbove:Hide() end

    -- Stack below bars (order ascending = top to bottom; order=1 closest to group)
    currentY = 0
    for _, barInfo in ipairs(belowBars) do
        barInfo.frame:ClearAllPoints()
        barInfo.frame:SetPoint("TOPLEFT", containerFrameBelow, "TOPLEFT", 0, -currentY)
        barInfo.frame:SetPoint("TOPRIGHT", containerFrameBelow, "TOPRIGHT", 0, -currentY)
        local h = barInfo._effectiveHeight or globalBarHeight
        barInfo.frame:SetHeight(h)
        currentY = currentY + h + barSpacing
    end
    local belowHeight = currentY > 0 and (currentY - barSpacing) or 1
    containerFrameBelow:SetHeight(belowHeight)
    if #belowBars > 0 then containerFrameBelow:Show() else containerFrameBelow:Hide() end
end

------------------------------------------------------------------------
-- OnUpdate handler (30 Hz)
------------------------------------------------------------------------

local elapsed_acc = 0

local function OnUpdate(self, elapsed)
    elapsed_acc = elapsed_acc + elapsed
    if elapsed_acc < UPDATE_INTERVAL then return end
    elapsed_acc = 0

    if isPreviewActive then return end

    local settings = GetResourceBarSettings()
    local auraActiveCache = {}

    for _, barInfo in ipairs(resourceBarFrames) do
        if barInfo.frame and barInfo.frame:IsShown() then
            if barInfo.barType == "continuous" then
                UpdateContinuousBar(barInfo.frame, barInfo.powerType, settings, auraActiveCache)
            elseif barInfo.barType == "segmented" then
                UpdateSegmentedBar(barInfo.frame, barInfo.powerType, settings, auraActiveCache)
            elseif barInfo.barType == "mw_segmented" then
                UpdateMaelstromWeaponBar(barInfo.frame, settings, auraActiveCache)
            elseif barInfo.barType == "custom_continuous"
                or barInfo.barType == "custom_segmented"
                or barInfo.barType == "custom_overlay" then
                UpdateCustomAuraBar(barInfo)
            end
        elseif barInfo.frame and barInfo.cabConfig and barInfo.cabConfig.hideWhenInactive then
            -- Frame hidden by hideWhenInactive; still update so it can re-show when aura returns
            UpdateCustomAuraBar(barInfo)
        end
    end

    if layoutDirty then
        layoutDirty = false
        RelayoutBars()
        CooldownCompanion:RepositionCastBar()
    end
end

------------------------------------------------------------------------
-- Event handling (must be defined before Apply/Revert which call these)
------------------------------------------------------------------------

-- Lifecycle events: always registered while the feature is enabled.
-- These trigger full re-evaluation (not just re-apply) so the bars
-- come back after a form change that temporarily hides them.
local lifecycleFrame = nil

local function EnableLifecycleEvents()
    if not lifecycleFrame then
        lifecycleFrame = CreateFrame("Frame")
        lifecycleFrame:SetScript("OnEvent", function(self, event, ...)
            if event == "UPDATE_SHAPESHIFT_FORM" then
                CooldownCompanion:EvaluateResourceBars()
                CooldownCompanion:UpdateAnchorStacking()
            elseif event == "ACTIVE_TALENT_GROUP_CHANGED"
                or event == "PLAYER_SPECIALIZATION_CHANGED" then
                if not pendingSpecChange then
                    pendingSpecChange = true
                    C_Timer.After(0.5, function()
                        pendingSpecChange = false
                        local rebuilt = UpdateMWMaxStacks()
                        if not rebuilt then
                            CooldownCompanion:EvaluateResourceBars()
                        end
                        CooldownCompanion:UpdateAnchorStacking()
                    end)
                end
            elseif event == "PLAYER_TALENT_UPDATE"
                or event == "TRAIT_CONFIG_UPDATED" then
                UpdateMWMaxStacks()
            end
        end)
    end
    lifecycleFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    lifecycleFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
    lifecycleFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    lifecycleFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
    lifecycleFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
end

local function DisableLifecycleEvents()
    if not lifecycleFrame then return end
    lifecycleFrame:UnregisterAllEvents()
    pendingSpecChange = false
end

-- Update events: only registered while bars are applied.
local function EnableEventFrame()
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", function(self, event, ...)
            if event == "UNIT_MAXPOWER" then
                local unit = ...
                if unit == "player" then
                    CooldownCompanion:ApplyResourceBars()
                end
            end
        end)
    end
    eventFrame:RegisterUnitEvent("UNIT_MAXPOWER", "player")
end

local function DisableEventFrame()
    if not eventFrame then return end
    eventFrame:UnregisterAllEvents()
end

------------------------------------------------------------------------
-- Apply: Create/show/position resource bars
------------------------------------------------------------------------

local function StyleContinuousBar(bar, powerType, settings)
    local texName = settings.barTexture or "Solid"

    if texName == "blizzard_class" then
        local atlasInfo = POWER_ATLAS_INFO[powerType]
        if atlasInfo then
            bar:SetStatusBarTexture(atlasInfo.atlas)
            local fillTexture = bar:GetStatusBarTexture()
            bar.brightnessOverlay:SetAllPoints(fillTexture)
            bar.brightnessOverlay:SetAtlas(atlasInfo.atlas)
        else
            -- Fallback for power types without class-specific atlas
            bar:SetStatusBarTexture(CooldownCompanion:FetchStatusBar("Blizzard"))
        end
    else
        bar:SetStatusBarTexture(CooldownCompanion:FetchStatusBar(texName))
    end

    ApplyContinuousFillColor(bar, powerType, settings, nil)

    local bgc = settings.backgroundColor or { 0, 0, 0, 0.5 }
    bar.bg:SetColorTexture(bgc[1], bgc[2], bgc[3], bgc[4])

    local borderStyle = settings.borderStyle or "pixel"
    local borderColor = settings.borderColor or { 0, 0, 0, 1 }
    local borderSize = settings.borderSize or 1

    if borderStyle == "pixel" then
        ApplyPixelBorders(bar.borders, bar, borderColor, borderSize)
    else
        HidePixelBorders(bar.borders)
    end

    -- Text setup
    local resourceConfig = settings.resources and settings.resources[powerType]
    local textFormat = resourceConfig and resourceConfig.textFormat or DEFAULT_RESOURCE_TEXT_FORMAT
    if textFormat ~= "current" and textFormat ~= "current_max" and textFormat ~= "percent" then
        textFormat = DEFAULT_RESOURCE_TEXT_FORMAT
    end
    local textFontName = resourceConfig and resourceConfig.textFont or DEFAULT_RESOURCE_TEXT_FONT
    local textSize = tonumber(resourceConfig and resourceConfig.textFontSize) or DEFAULT_RESOURCE_TEXT_SIZE
    local textOutline = resourceConfig and resourceConfig.textFontOutline or DEFAULT_RESOURCE_TEXT_OUTLINE
    local textColor = resourceConfig and resourceConfig.textFontColor or DEFAULT_RESOURCE_TEXT_COLOR
    if type(textColor) ~= "table" or textColor[1] == nil or textColor[2] == nil or textColor[3] == nil then
        textColor = DEFAULT_RESOURCE_TEXT_COLOR
    end

    local textFont = CooldownCompanion:FetchFont(textFontName)
    bar.text:SetFont(textFont, textSize, textOutline)
    bar.text:SetTextColor(textColor[1], textColor[2], textColor[3], textColor[4] ~= nil and textColor[4] or 1)

    -- Continuous bars show text by default
    local showText = true
    if resourceConfig and resourceConfig.showText == false then
        showText = false
    end
    bar.text:SetShown(showText)
    bar._textFormat = textFormat
end

local function StyleSegmentedBar(holder, powerType, settings)
    -- All segmented types use their first color return as the initial segment color.
    -- UpdateSegmentedBar dynamically recolors per-segment each tick.
    local color = GetResourceColors(powerType, settings)
    for _, seg in ipairs(holder.segments) do
        seg:SetStatusBarColor(color[1], color[2], color[3], 1)
    end
    -- Segmented bars hide text by default (no text FontString on segmented)
end

function CooldownCompanion:ApplyResourceBars()
    local settings = GetResourceBarSettings()
    if not settings or not settings.enabled then
        self:RevertResourceBars()
        return
    end

    local groupId = GetEffectiveAnchorGroupId(settings)
    if not groupId then
        self:RevertResourceBars()
        return
    end

    local group = self.db.profile.groups[groupId]
    if not group or group.displayMode ~= "icons" then
        self:RevertResourceBars()
        return
    end

    local groupFrame = CooldownCompanion.groupFrames[groupId]
    if not groupFrame or not groupFrame:IsShown() then
        self:RevertResourceBars()
        return
    end

    -- Determine which resources to show
    local resources = DetermineActiveResources()
    local filtered = {}
    for _, pt in ipairs(resources) do
        if IsResourceEnabled(pt, settings) then
            table.insert(filtered, pt)
        end
    end

    -- Append enabled custom aura bars
    local customBars = GetSpecCustomAuraBars(settings)
    for i = 1, MAX_CUSTOM_AURA_BARS do
        local cab = customBars[i]
        if cab and cab.enabled and cab.spellID then
            table.insert(filtered, CUSTOM_AURA_BAR_BASE + i - 1)
        end
    end

    if #filtered == 0 then
        self:RevertResourceBars()
        return
    end

    -- Create containers if needed
    if not containerFrameAbove then
        containerFrameAbove = CreateFrame("Frame", "CooldownCompanionResourceBarsAbove", UIParent)
        containerFrameAbove:SetFrameStrata("MEDIUM")
    end
    if not containerFrameBelow then
        containerFrameBelow = CreateFrame("Frame", "CooldownCompanionResourceBarsBelow", UIParent)
        containerFrameBelow:SetFrameStrata("MEDIUM")
    end

    -- Create or recycle bar frames
    local globalBarHeight = settings.barHeight or 12
    local barSpacing = settings.barSpacing or 3.6
    lastAppliedBarSpacing = barSpacing
    lastAppliedBarHeight = globalBarHeight
    local segmentGap = settings.segmentGap or 4
    local totalWidth = groupFrame:GetWidth()

    -- Determine side/order for each bar (for per-element positioning)
    local sideList = {}
    local orderList = {}
    local fallbackOrder = 900
    for idx, powerType in ipairs(filtered) do
        local side, order
        if powerType >= CUSTOM_AURA_BAR_BASE then
            local slotIdx = powerType - CUSTOM_AURA_BAR_BASE + 1
            local slotCfg = settings.customAuraBarSlots and settings.customAuraBarSlots[slotIdx]
            side = (slotCfg and slotCfg.position) or "below"
            order = (slotCfg and slotCfg.order) or (fallbackOrder + idx)
        else
            local res = settings.resources and settings.resources[powerType]
            side = (res and res.position) or "below"
            order = (res and res.order) or (fallbackOrder + idx)
        end
        sideList[idx] = side
        orderList[idx] = order
    end

    -- Hide existing bars that we don't need
    for i = #filtered + 1, #resourceBarFrames do
        if resourceBarFrames[i] and resourceBarFrames[i].frame then
            ClearResourceAuraVisuals(resourceBarFrames[i].frame)
            resourceBarFrames[i].frame:Hide()
            if resourceBarFrames[i].frame.brightnessOverlay then
                resourceBarFrames[i].frame.brightnessOverlay:Hide()
            end
        end
    end

    for idx, powerType in ipairs(filtered) do
        local isSegmented = SEGMENTED_TYPES[powerType]
        local barInfo = resourceBarFrames[idx]
        local targetContainer = sideList[idx] == "above" and containerFrameAbove or containerFrameBelow

        -- Resolve per-bar height override
        local effectiveHeight = globalBarHeight
        if settings.customBarHeights then
            if powerType >= CUSTOM_AURA_BAR_BASE and powerType < CUSTOM_AURA_BAR_BASE + MAX_CUSTOM_AURA_BARS then
                local cabIdx = powerType - CUSTOM_AURA_BAR_BASE + 1
                local cab = customBars[cabIdx]
                effectiveHeight = cab and cab.barHeight or globalBarHeight
            else
                local res = settings.resources[powerType]
                effectiveHeight = res and res.barHeight or globalBarHeight
            end
        end

        if powerType == RESOURCE_MAELSTROM_WEAPON then
            -- Maelstrom Weapon: overlay bar with dedicated update
            local halfSegments = mwMaxStacks <= 5 and mwMaxStacks or (mwMaxStacks / 2)

            if not barInfo or barInfo.barType ~= "mw_segmented"
                or #barInfo.frame.segments ~= halfSegments then
                if barInfo and barInfo.frame then
                    ClearResourceAuraVisuals(barInfo.frame)
                    barInfo.frame:Hide()
                end
                local holder = CreateOverlayBar(targetContainer, halfSegments)
                barInfo = { frame = holder, barType = "mw_segmented", powerType = powerType }
                resourceBarFrames[idx] = barInfo
            else
                barInfo.powerType = powerType
            end

            barInfo.frame:SetSize(totalWidth, effectiveHeight)
            LayoutOverlaySegments(barInfo.frame, totalWidth, effectiveHeight, segmentGap, settings, halfSegments)

            -- Apply initial colors
            local baseColor, overlayColor = GetResourceColors(100, settings)
            for i = 1, halfSegments do
                barInfo.frame.segments[i]:SetStatusBarColor(baseColor[1], baseColor[2], baseColor[3], 1)
                barInfo.frame.overlaySegments[i]:SetStatusBarColor(overlayColor[1], overlayColor[2], overlayColor[3], 1)
                barInfo.frame.overlaySegments[i]:Show()
            end

        elseif powerType >= CUSTOM_AURA_BAR_BASE and powerType < CUSTOM_AURA_BAR_BASE + MAX_CUSTOM_AURA_BARS then
            -- Custom aura bar
            local cabIndex = powerType - CUSTOM_AURA_BAR_BASE + 1
            local cabConfig = customBars[cabIndex]
            local isActive = cabConfig.trackingMode == "active"
            local mode = isActive and "continuous" or (cabConfig.displayMode or "segmented")
            local maxStacks = isActive and 1 or (cabConfig.maxStacks or 1)
            local targetBarType = "custom_" .. mode

            -- Determine if bar needs recreation
            local needsRecreate = not barInfo or barInfo.barType ~= targetBarType
            if not needsRecreate and mode == "segmented" then
                needsRecreate = barInfo.frame._numSegments ~= maxStacks
            end
            if not needsRecreate and mode == "overlay" then
                needsRecreate = barInfo.halfSegments ~= math.ceil(maxStacks / 2)
            end

            if needsRecreate then
                if barInfo and barInfo.frame then
                    ClearResourceAuraVisuals(barInfo.frame)
                    barInfo.frame:Hide()
                end
                if mode == "continuous" then
                    local bar = CreateContinuousBar(targetContainer)
                    bar:SetMinMaxValues(0, maxStacks)
                    barInfo = { frame = bar, barType = "custom_continuous", powerType = powerType }
                elseif mode == "segmented" then
                    local holder = CreateSegmentedBar(targetContainer, maxStacks)
                    -- Set per-segment MinMax for secret-safe SetValue(stacks) clamping
                    for si = 1, maxStacks do
                        holder.segments[si]:SetMinMaxValues(si - 1, si)
                    end
                    barInfo = { frame = holder, barType = "custom_segmented", powerType = powerType }
                elseif mode == "overlay" then
                    local half = math.ceil(maxStacks / 2)
                    local holder = CreateOverlayBar(targetContainer, half)
                    barInfo = { frame = holder, barType = "custom_overlay", powerType = powerType, halfSegments = half }
                end
                resourceBarFrames[idx] = barInfo
            end

            if mode == "continuous" then
                EnsureCustomAuraContinuousThresholdOverlay(barInfo.frame)
            elseif mode == "segmented" then
                EnsureCustomAuraSegmentThresholdOverlays(barInfo.frame)
            elseif mode == "overlay" then
                EnsureCustomAuraOverlayThresholdOverlays(barInfo.frame, barInfo.halfSegments or math.ceil(maxStacks / 2))
            end

            barInfo.cabConfig = cabConfig
            barInfo.frame:Show()  -- ensure reused frames visible for layout; OnUpdate re-hides if hideWhenInactive
            barInfo.frame:SetSize(totalWidth, effectiveHeight)
            if mode == "segmented" then
                LayoutSegments(barInfo.frame, totalWidth, effectiveHeight, segmentGap, settings)
            elseif mode == "overlay" then
                LayoutOverlaySegments(barInfo.frame, totalWidth, effectiveHeight, segmentGap, settings, barInfo.halfSegments)
            end
            -- Continuous bar styling (text font, background, borders)
            if mode == "continuous" then
                local barTexture = CooldownCompanion:FetchStatusBar(settings.barTexture or "Solid")
                barInfo.frame:SetStatusBarTexture(barTexture)
                local bgc = settings.backgroundColor or { 0, 0, 0, 0.5 }
                barInfo.frame.bg:SetColorTexture(bgc[1], bgc[2], bgc[3], bgc[4])
                local borderStyle = settings.borderStyle or "pixel"
                local borderColor = settings.borderColor or { 0, 0, 0, 1 }
                local borderSize = settings.borderSize or 1
                if borderStyle == "pixel" then
                    ApplyPixelBorders(barInfo.frame.borders, barInfo.frame, borderColor, borderSize)
                else
                    HidePixelBorders(barInfo.frame.borders)
                end
                LayoutCustomAuraContinuousThresholdOverlay(barInfo.frame, barTexture, borderStyle, borderSize)
                -- Duration text style (bar.text)
                local durationTextFontName = cabConfig.durationTextFont or DEFAULT_RESOURCE_TEXT_FONT
                local durationTextSize = tonumber(cabConfig.durationTextFontSize) or DEFAULT_RESOURCE_TEXT_SIZE
                local durationTextOutline = cabConfig.durationTextFontOutline or DEFAULT_RESOURCE_TEXT_OUTLINE
                local durationTextColor = cabConfig.durationTextFontColor or DEFAULT_RESOURCE_TEXT_COLOR
                if type(durationTextColor) ~= "table" or durationTextColor[1] == nil or durationTextColor[2] == nil or durationTextColor[3] == nil then
                    durationTextColor = DEFAULT_RESOURCE_TEXT_COLOR
                end
                local durationTextFont = CooldownCompanion:FetchFont(durationTextFontName)
                barInfo.frame.text:SetFont(durationTextFont, durationTextSize, durationTextOutline)
                barInfo.frame.text:SetTextColor(durationTextColor[1], durationTextColor[2], durationTextColor[3], durationTextColor[4] ~= nil and durationTextColor[4] or 1)
                -- Lazily create stackText FontString for custom aura bars
                if not barInfo.frame.stackText then
                    barInfo.frame.stackText = (barInfo.frame.textLayer or barInfo.frame):CreateFontString(nil, "OVERLAY")
                    barInfo.frame.stackText:SetTextColor(1, 1, 1, 1)
                end
                -- Stack text style (bar.stackText)
                local stackTextFontName = cabConfig.stackTextFont or DEFAULT_RESOURCE_TEXT_FONT
                local stackTextSize = tonumber(cabConfig.stackTextFontSize) or DEFAULT_RESOURCE_TEXT_SIZE
                local stackTextOutline = cabConfig.stackTextFontOutline or DEFAULT_RESOURCE_TEXT_OUTLINE
                local stackTextColor = cabConfig.stackTextFontColor or DEFAULT_RESOURCE_TEXT_COLOR
                if type(stackTextColor) ~= "table" or stackTextColor[1] == nil or stackTextColor[2] == nil or stackTextColor[3] == nil then
                    stackTextColor = DEFAULT_RESOURCE_TEXT_COLOR
                end
                local stackTextFont = CooldownCompanion:FetchFont(stackTextFontName)
                barInfo.frame.stackText:SetFont(stackTextFont, stackTextSize, stackTextOutline)
                barInfo.frame.stackText:SetTextColor(stackTextColor[1], stackTextColor[2], stackTextColor[3], stackTextColor[4] ~= nil and stackTextColor[4] or 1)
                barInfo.frame.brightnessOverlay:Hide()
            end
            -- Apply bar color AFTER texture setup (SetStatusBarTexture resets vertex color)
            StyleCustomAuraBar(barInfo, cabConfig)
        elseif isSegmented then
            local max = UnitPowerMax("player", powerType)
            if powerType == 5 then max = 6 end  -- Runes always 6
            if max < 1 then max = 1 end

            -- Need to recreate if segment count changed or type changed
            if not barInfo or barInfo.barType ~= "segmented"
                or barInfo.frame._numSegments ~= max then
                if barInfo and barInfo.frame then
                    ClearResourceAuraVisuals(barInfo.frame)
                    barInfo.frame:Hide()
                end
                local holder = CreateSegmentedBar(targetContainer, max)
                barInfo = { frame = holder, barType = "segmented", powerType = powerType }
                resourceBarFrames[idx] = barInfo
            else
                barInfo.powerType = powerType
            end

            barInfo.frame:SetSize(totalWidth, effectiveHeight)
            LayoutSegments(barInfo.frame, totalWidth, effectiveHeight, segmentGap, settings)
            StyleSegmentedBar(barInfo.frame, powerType, settings)
        else
            -- Continuous bar
            if not barInfo or barInfo.barType ~= "continuous" then
                if barInfo and barInfo.frame then
                    ClearResourceAuraVisuals(barInfo.frame)
                    barInfo.frame:Hide()
                end
                local bar = CreateContinuousBar(targetContainer)
                barInfo = { frame = bar, barType = "continuous", powerType = powerType }
                resourceBarFrames[idx] = barInfo
            else
                barInfo.powerType = powerType
            end

            barInfo.frame:SetSize(totalWidth, effectiveHeight)
            StyleContinuousBar(barInfo.frame, powerType, settings)
        end

        if barInfo.frame:GetParent() ~= targetContainer then
            barInfo.frame:SetParent(targetContainer)
        end
        barInfo._side = sideList[idx]
        barInfo._order = orderList[idx]
        barInfo._effectiveHeight = effectiveHeight
        barInfo.frame:Show()
    end

    activeResources = filtered

    -- Layout: per-element positioning using above/below containers
    local gap = settings.yOffset or 3
    lastAppliedWidth = totalWidth

    -- Anchor containers to group frame (static — only changes on full Apply)
    containerFrameAbove:ClearAllPoints()
    containerFrameBelow:ClearAllPoints()
    containerFrameAbove:SetWidth(totalWidth)
    containerFrameBelow:SetWidth(totalWidth)
    containerFrameAbove:SetPoint("BOTTOMLEFT", groupFrame, "TOPLEFT", 0, gap)
    containerFrameBelow:SetPoint("TOPLEFT", groupFrame, "BOTTOMLEFT", 0, -gap)

    -- Position bars within containers (reusable for relayout on visibility change)
    RelayoutBars()

    -- Enable OnUpdate
    if not onUpdateFrame then
        onUpdateFrame = CreateFrame("Frame")
    end
    onUpdateFrame:SetScript("OnUpdate", OnUpdate)

    -- Enable events
    EnableEventFrame()

    isApplied = true

    -- Alpha inheritance
    if settings.inheritAlpha then
        -- Save original alpha (only if not already saved)
        if not savedContainerAlpha then
            savedContainerAlpha = containerFrameAbove:GetAlpha()
        end

        -- Apply alpha immediately
        local groupAlpha = groupFrame:GetEffectiveAlpha()
        containerFrameAbove:SetAlpha(groupAlpha)
        containerFrameBelow:SetAlpha(groupAlpha)

        -- Start alpha sync OnUpdate (~30Hz polling)
        if not alphaSyncFrame then
            alphaSyncFrame = CreateFrame("Frame")
        end
        local lastAlpha = groupAlpha
        local accumulator = 0
        local SYNC_INTERVAL = 1 / 30
        alphaSyncFrame:SetScript("OnUpdate", function(self, dt)
            accumulator = accumulator + dt
            if accumulator < SYNC_INTERVAL then return end
            accumulator = 0
            if not groupFrame then return end
            local alpha = groupFrame:GetEffectiveAlpha()
            if alpha ~= lastAlpha then
                lastAlpha = alpha
                if containerFrameAbove then containerFrameAbove:SetAlpha(alpha) end
                if containerFrameBelow then containerFrameBelow:SetAlpha(alpha) end
            end
        end)
    else
        -- inheritAlpha is off — stop sync and restore original if we had it
        if alphaSyncFrame then
            alphaSyncFrame:SetScript("OnUpdate", nil)
        end
        if savedContainerAlpha then
            if containerFrameAbove then containerFrameAbove:SetAlpha(savedContainerAlpha) end
            if containerFrameBelow then containerFrameBelow:SetAlpha(savedContainerAlpha) end
            savedContainerAlpha = nil
        end
    end
end

------------------------------------------------------------------------
-- Revert: hide all resource bars
------------------------------------------------------------------------

function CooldownCompanion:RevertResourceBars()
    if not isApplied then return end
    isApplied = false
    lastAppliedWidth = nil
    lastAppliedBarSpacing = nil
    lastAppliedBarHeight = nil
    layoutDirty = false

    -- Stop alpha sync and restore alpha
    if alphaSyncFrame then
        alphaSyncFrame:SetScript("OnUpdate", nil)
    end
    if savedContainerAlpha then
        if containerFrameAbove then containerFrameAbove:SetAlpha(savedContainerAlpha) end
        if containerFrameBelow then containerFrameBelow:SetAlpha(savedContainerAlpha) end
    end
    savedContainerAlpha = nil

    -- Stop OnUpdate
    if onUpdateFrame then
        onUpdateFrame:SetScript("OnUpdate", nil)
    end

    -- Stop events
    DisableEventFrame()

    -- Hide all bars
    for _, barInfo in ipairs(resourceBarFrames) do
        if barInfo.frame then
            ClearResourceAuraVisuals(barInfo.frame)
            barInfo.frame:Hide()
            if barInfo.frame.brightnessOverlay then
                barInfo.frame.brightnessOverlay:Hide()
            end
        end
    end

    -- Hide containers
    if containerFrameAbove then containerFrameAbove:Hide() end
    if containerFrameBelow then containerFrameBelow:Hide() end

    isPreviewActive = false
    activeResources = {}
end

function CooldownCompanion:GetSpecCustomAuraBars()
    local settings = GetResourceBarSettings()
    if not settings then return {} end
    return GetSpecCustomAuraBars(settings)
end

------------------------------------------------------------------------
-- Evaluate: central decision point
------------------------------------------------------------------------

function CooldownCompanion:EvaluateResourceBars()
    local settings = GetResourceBarSettings()
    if not settings or not settings.enabled then
        DisableLifecycleEvents()
        self:RevertResourceBars()
        return
    end
    EnableLifecycleEvents()
    self:ApplyResourceBars()
end

-- Returns the last visible resource/custom aura bar on `side` with order < upToOrder.
-- Used by CastBar to anchor as the next stacked element.
function CooldownCompanion:GetResourceBarPredecessor(side, upToOrder)
    if not isApplied then return nil end

    local best = nil
    for _, barInfo in ipairs(resourceBarFrames) do
        if barInfo.frame and barInfo.frame:IsShown()
            and barInfo._side == side
            and barInfo._order < upToOrder then
            if not best then
                best = barInfo
            elseif barInfo._order > best._order then
                best = barInfo
            elseif barInfo._order == best._order
                and (barInfo.powerType or 0) > (best.powerType or 0) then
                best = barInfo
            end
        end
    end

    return best and best.frame or nil
end

------------------------------------------------------------------------
-- Preview mode
------------------------------------------------------------------------

local function ApplyPreviewData()
    local settings = GetResourceBarSettings()

    local function ApplyResourceAuraLanePreview(barInfo, previewRatio)
        local powerType = barInfo.powerType
        if not powerType then return end

        local resource = settings and settings.resources and settings.resources[powerType]
        if not IsResourceAuraOverlayEnabled(resource) then
            HideResourceAuraStackSegments(barInfo.frame)
            return
        end
        local auraSpellID = resource and tonumber(resource.auraColorSpellID) or nil
        local auraMaxStacks = GetResourceAuraConfiguredMaxStacks(powerType, settings)
        if not auraSpellID or auraSpellID <= 0 or not auraMaxStacks then
            HideResourceAuraStackSegments(barInfo.frame)
            return
        end

        local auraColor = resource and resource.auraActiveColor
        if type(auraColor) ~= "table" or not auraColor[1] or not auraColor[2] or not auraColor[3] then
            auraColor = DEFAULT_RESOURCE_AURA_ACTIVE_COLOR
        end

        local previewStacks = math_max(1, math_floor((auraMaxStacks * previewRatio) + 0.5))
        ApplyResourceAuraStackSegments(barInfo.frame, settings, previewStacks, auraMaxStacks, auraColor)
    end

    for _, barInfo in ipairs(resourceBarFrames) do
        if barInfo.frame and barInfo.frame:IsShown() then
            ClearResourceAuraVisuals(barInfo.frame)
            if barInfo.barType == "continuous" then
                barInfo.frame:SetMinMaxValues(0, 100)
                barInfo.frame:SetValue(65)
                if barInfo.frame.text and barInfo.frame.text:IsShown() then
                    local textFormat = barInfo.frame._textFormat
                    if textFormat == "current" then
                        barInfo.frame.text:SetText("65")
                    elseif textFormat == "percent" then
                        barInfo.frame.text:SetText("65")
                    else
                        barInfo.frame.text:SetText("65 / 100")
                    end
                end
            elseif barInfo.barType == "segmented" then
                local n = #barInfo.frame.segments
                for i, seg in ipairs(barInfo.frame.segments) do
                    if i <= math_floor(n * 0.6) then
                        seg:SetValue(1)
                    elseif i == math_floor(n * 0.6) + 1 then
                        seg:SetValue(0.5)
                    else
                        seg:SetValue(0)
                    end
                end
                ApplyResourceAuraLanePreview(barInfo, 0.5)
            elseif barInfo.barType == "mw_segmented" then
                -- Preview at 7 stacks (all 5 base full, 2 overlay full)
                local half = #barInfo.frame.segments
                local previewStacks = 7
                for i = 1, half do
                    barInfo.frame.segments[i]:SetValue(previewStacks)
                    barInfo.frame.overlaySegments[i]:SetValue(previewStacks)
                    if previewStacks > (half + i - 1) then
                        barInfo.frame.overlaySegments[i]:SetAlpha(1)
                    else
                        barInfo.frame.overlaySegments[i]:SetAlpha(0)
                    end
                end
                ApplyResourceAuraLanePreview(barInfo, 0.5)
            elseif barInfo.barType == "custom_continuous" then
                local cabConfig = barInfo.cabConfig
                local isActive = cabConfig and cabConfig.trackingMode == "active"
                local maxStacks = (cabConfig and cabConfig.maxStacks) or 1
                local thresholdEnabled = IsCustomAuraMaxThresholdEnabled(cabConfig)
                local previewValue
                if isActive then
                    barInfo.frame:SetMinMaxValues(0, 1)
                    previewValue = 0.65
                    barInfo.frame:SetValue(previewValue)
                else
                    barInfo.frame:SetMinMaxValues(0, maxStacks)
                    previewValue = math.ceil(maxStacks * 0.65)
                    barInfo.frame:SetValue(previewValue)
                end
                if barInfo.frame.thresholdOverlay then
                    if thresholdEnabled then
                        SetCustomAuraMaxThresholdRange(barInfo.frame.thresholdOverlay, maxStacks)
                        barInfo.frame.thresholdOverlay:SetValue(previewValue or 0)
                        barInfo.frame.thresholdOverlay:Show()
                    else
                        barInfo.frame.thresholdOverlay:SetValue(0)
                        barInfo.frame.thresholdOverlay:Hide()
                    end
                end
                if barInfo.frame.text and barInfo.frame.text:IsShown() then
                    barInfo.frame.text:SetText(FormatBarTime(12.3))
                end
                if barInfo.frame.stackText and barInfo.frame.stackText:IsShown() then
                    if isActive then
                        barInfo.frame.stackText:SetFormattedText("%d", 3)
                    else
                        barInfo.frame.stackText:SetFormattedText("%d / %d", previewValue, maxStacks)
                    end
                end
            elseif barInfo.barType == "custom_segmented" then
                local cabConfig = barInfo.cabConfig
                local maxStacks = (cabConfig and cabConfig.maxStacks) or 1
                local thresholdEnabled = IsCustomAuraMaxThresholdEnabled(cabConfig)
                local n = #barInfo.frame.segments
                local fill = math.ceil(n * 0.6)
                -- Segments have MinMax(i-1, i); C-level clamping handles fill/empty
                for _, seg in ipairs(barInfo.frame.segments) do
                    seg:SetValue(fill)
                end
                if barInfo.frame.thresholdSegments then
                    for _, seg in ipairs(barInfo.frame.thresholdSegments) do
                        if thresholdEnabled then
                            SetCustomAuraMaxThresholdRange(seg, maxStacks)
                            seg:SetValue(fill)
                            seg:Show()
                        else
                            seg:SetValue(0)
                            seg:Hide()
                        end
                    end
                end
            elseif barInfo.barType == "custom_overlay" then
                local cabConfig = barInfo.cabConfig
                local maxStacks = (cabConfig and cabConfig.maxStacks) or 1
                local previewStacks = math.ceil(maxStacks * 0.7)
                local thresholdEnabled = IsCustomAuraMaxThresholdEnabled(cabConfig)
                local half = barInfo.halfSegments or 1
                for i = 1, half do
                    barInfo.frame.segments[i]:SetValue(previewStacks)
                    barInfo.frame.overlaySegments[i]:SetValue(previewStacks)
                    if barInfo.frame.thresholdSegments and barInfo.frame.thresholdSegments[i] then
                        local seg = barInfo.frame.thresholdSegments[i]
                        if thresholdEnabled then
                            SetCustomAuraMaxThresholdRange(seg, maxStacks)
                            seg:SetValue(previewStacks)
                            seg:Show()
                        else
                            seg:SetValue(0)
                            seg:Hide()
                        end
                    end
                end
            end
        end
    end
end

function CooldownCompanion:StartResourceBarPreview()
    isPreviewActive = true
    self:ApplyResourceBars()
    ApplyPreviewData()
end

function CooldownCompanion:StopResourceBarPreview()
    if not isPreviewActive then return end
    isPreviewActive = false
    -- Resume live updates on next OnUpdate tick
end

function CooldownCompanion:IsResourceBarPreviewActive()
    return isPreviewActive
end

------------------------------------------------------------------------
-- Hook installation (same pattern as CastBar)
------------------------------------------------------------------------

local function InstallHooks()
    if hooksInstalled then return end
    hooksInstalled = true

    -- When anchor group refreshes — re-evaluate
    hooksecurefunc(CooldownCompanion, "RefreshGroupFrame", function(self, groupId)
        local s = GetResourceBarSettings()
        if s and s.enabled and (not s.anchorGroupId or s.anchorGroupId == groupId) then
            C_Timer.After(0, function()
                CooldownCompanion:EvaluateResourceBars()
            end)
        end
    end)

    local function QueueResourceBarReevaluate()
        C_Timer.After(0.1, function()
            CooldownCompanion:EvaluateResourceBars()
        end)
    end

    -- When all groups refresh — re-evaluate
    hooksecurefunc(CooldownCompanion, "RefreshAllGroups", function()
        QueueResourceBarReevaluate()
    end)

    -- Visibility-only refresh path (zone/resting/pet-battle transitions)
    -- still needs resource bar anchoring re-evaluation.
    hooksecurefunc(CooldownCompanion, "RefreshAllGroupsVisibilityOnly", function()
        QueueResourceBarReevaluate()
    end)

    -- When compact layout changes visible buttons — re-apply if width changed
    hooksecurefunc(CooldownCompanion, "UpdateGroupLayout", function(self, groupId)
        local s = GetResourceBarSettings()
        if not s or not s.enabled then return end
        local anchorGroupId = GetEffectiveAnchorGroupId(s)
        if anchorGroupId ~= groupId then return end
        local groupFrame = CooldownCompanion.groupFrames[groupId]
        if not groupFrame or not lastAppliedWidth then return end
        local newWidth = groupFrame:GetWidth()
        if math_abs(newWidth - lastAppliedWidth) < 0.1 then
            return
        end
        CooldownCompanion:ApplyResourceBars()
    end)

    -- When icon size / spacing / buttons-per-row changes — re-apply if width changed
    hooksecurefunc(CooldownCompanion, "ResizeGroupFrame", function(self, groupId)
        local s = GetResourceBarSettings()
        if not s or not s.enabled then return end
        local anchorGroupId = GetEffectiveAnchorGroupId(s)
        if anchorGroupId ~= groupId then return end
        local groupFrame = CooldownCompanion.groupFrames[groupId]
        if not groupFrame or not lastAppliedWidth then return end
        local newWidth = groupFrame:GetWidth()
        if math_abs(newWidth - lastAppliedWidth) < 0.1 then
            return
        end
        CooldownCompanion:ApplyResourceBars()
    end)
end

------------------------------------------------------------------------
-- Initialization
------------------------------------------------------------------------

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function(self, event)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")

    C_Timer.After(0.5, function()
        UpdateMWMaxStacks()
        InstallHooks()
        CooldownCompanion:EvaluateResourceBars()
    end)
end)
