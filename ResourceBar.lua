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

local CUSTOM_AURA_BAR_BASE = 201  -- 201, 202, 203 for slots 1-3
local MAX_CUSTOM_AURA_BARS = 3
local MW_SPELL_ID = 187880
local RAGING_MAELSTROM_SPELL_ID = 384143
local RESOURCE_MAELSTROM_WEAPON = 100
local DEFAULT_MW_BASE_COLOR = { 0, 0.5, 1 }
local DEFAULT_MW_OVERLAY_COLOR = { 1, 0.84, 0 }
local DEFAULT_MW_MAX_COLOR = { 0.5, 0.8, 1 }

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
local containerFrame = nil
local resourceBarFrames = {}   -- array of bar frame objects (ordered by stacking)
local activeResources = {}     -- array of power type ints currently displayed
local isPreviewActive = false
local pendingSpecChange = false
local savedContainerAlpha = nil
local alphaSyncFrame = nil

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

--- Get color for a power type, respecting per-resource overrides.
local function GetPowerColor(powerType, settings)
    if settings and settings.resources then
        local override = settings.resources[powerType]
        if override and override.color then
            return override.color
        end
    end
    return DEFAULT_POWER_COLORS[powerType] or { 1, 1, 1 }
end

--- Get combo point colors (normal, max, charged).
local function GetComboColors(settings)
    local normalColor = DEFAULT_COMBO_COLOR
    local maxColor = DEFAULT_COMBO_MAX_COLOR
    local chargedColor = DEFAULT_COMBO_CHARGED_COLOR
    if settings and settings.resources then
        local override = settings.resources[4]
        if override then
            if override.comboColor then normalColor = override.comboColor end
            if override.comboMaxColor then maxColor = override.comboMaxColor end
            if override.comboChargedColor then chargedColor = override.comboChargedColor end
        end
    end
    return normalColor, maxColor, chargedColor
end

--- Get rune-specific colors (ready, recharging, max).
local function GetRuneColors(settings)
    local readyColor = DEFAULT_RUNE_READY_COLOR
    local rechargingColor = DEFAULT_RUNE_RECHARGING_COLOR
    local maxColor = DEFAULT_RUNE_MAX_COLOR
    if settings and settings.resources then
        local override = settings.resources[5]
        if override then
            if override.runeReadyColor then readyColor = override.runeReadyColor end
            if override.runeRechargingColor then rechargingColor = override.runeRechargingColor end
            if override.runeMaxColor then maxColor = override.runeMaxColor end
        end
    end
    return readyColor, rechargingColor, maxColor
end

--- Get soul shard-specific colors (ready, recharging, max).
local function GetShardColors(settings)
    local readyColor = DEFAULT_SHARD_READY_COLOR
    local rechargingColor = DEFAULT_SHARD_RECHARGING_COLOR
    local maxColor = DEFAULT_SHARD_MAX_COLOR
    if settings and settings.resources then
        local override = settings.resources[7]
        if override then
            if override.shardReadyColor then readyColor = override.shardReadyColor end
            if override.shardRechargingColor then rechargingColor = override.shardRechargingColor end
            if override.shardMaxColor then maxColor = override.shardMaxColor end
        end
    end
    return readyColor, rechargingColor, maxColor
end

--- Get holy power colors (normal vs at max).
local function GetHolyColors(settings)
    local normalColor = DEFAULT_HOLY_COLOR
    local maxColor = DEFAULT_HOLY_MAX_COLOR
    if settings and settings.resources then
        local override = settings.resources[9]
        if override then
            if override.holyColor then normalColor = override.holyColor end
            if override.holyMaxColor then maxColor = override.holyMaxColor end
        end
    end
    return normalColor, maxColor
end

--- Get chi colors (normal vs at max).
local function GetChiColors(settings)
    local normalColor = DEFAULT_CHI_COLOR
    local maxColor = DEFAULT_CHI_MAX_COLOR
    if settings and settings.resources then
        local override = settings.resources[12]
        if override then
            if override.chiColor then normalColor = override.chiColor end
            if override.chiMaxColor then maxColor = override.chiMaxColor end
        end
    end
    return normalColor, maxColor
end

--- Get arcane charges colors (normal vs at max).
local function GetArcaneColors(settings)
    local normalColor = DEFAULT_ARCANE_COLOR
    local maxColor = DEFAULT_ARCANE_MAX_COLOR
    if settings and settings.resources then
        local override = settings.resources[16]
        if override then
            if override.arcaneColor then normalColor = override.arcaneColor end
            if override.arcaneMaxColor then maxColor = override.arcaneMaxColor end
        end
    end
    return normalColor, maxColor
end

--- Get essence-specific colors (ready, recharging, max).
local function GetEssenceColors(settings)
    local readyColor = DEFAULT_ESSENCE_READY_COLOR
    local rechargingColor = DEFAULT_ESSENCE_RECHARGING_COLOR
    local maxColor = DEFAULT_ESSENCE_MAX_COLOR
    if settings and settings.resources then
        local override = settings.resources[19]
        if override then
            if override.essenceReadyColor then readyColor = override.essenceReadyColor end
            if override.essenceRechargingColor then rechargingColor = override.essenceRechargingColor end
            if override.essenceMaxColor then maxColor = override.essenceMaxColor end
        end
    end
    return readyColor, rechargingColor, maxColor
end

--- Get MW colors (base, overlay, max).
local function GetMWColors(settings)
    local baseColor = DEFAULT_MW_BASE_COLOR
    local overlayColor = DEFAULT_MW_OVERLAY_COLOR
    local maxColor = DEFAULT_MW_MAX_COLOR
    if settings and settings.resources then
        local override = settings.resources[100]
        if override then
            if override.mwBaseColor then baseColor = override.mwBaseColor end
            if override.mwOverlayColor then overlayColor = override.mwOverlayColor end
            if override.mwMaxColor then maxColor = override.mwMaxColor end
        end
    end
    return baseColor, overlayColor, maxColor
end

--- Update cached MW max stacks based on Raging Maelstrom talent (OOC only — talents can't change in combat).
local function UpdateMWMaxStacks()
    local hasRagingMaelstrom = C_SpellBook.IsSpellKnown(RAGING_MAELSTROM_SPELL_ID, Enum.SpellBookSpellBank.Player)
    local newMax = hasRagingMaelstrom and 10 or 5
    if mwMaxStacks ~= newMax then
        mwMaxStacks = newMax
        CooldownCompanion:ApplyResourceBars()  -- segment count changed, rebuild
    end
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
        if not IsHealerSpec() then
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
    borders.TOP:SetPoint("TOPLEFT", parent, "TOPLEFT", -size, size)
    borders.TOP:SetPoint("TOPRIGHT", parent, "TOPRIGHT", size, size)
    borders.TOP:SetHeight(size)

    borders.BOTTOM:ClearAllPoints()
    borders.BOTTOM:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -size, -size)
    borders.BOTTOM:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", size, -size)
    borders.BOTTOM:SetHeight(size)

    borders.LEFT:ClearAllPoints()
    borders.LEFT:SetPoint("TOPLEFT", parent, "TOPLEFT", -size, size)
    borders.LEFT:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -size, -size)
    borders.LEFT:SetWidth(size)

    borders.RIGHT:ClearAllPoints()
    borders.RIGHT:SetPoint("TOPRIGHT", parent, "TOPRIGHT", size, size)
    borders.RIGHT:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", size, -size)
    borders.RIGHT:SetWidth(size)
end

local function HidePixelBorders(borders)
    if not borders then return end
    for _, tex in pairs(borders) do
        tex:Hide()
    end
end

------------------------------------------------------------------------
-- Frame creation: Continuous bar
------------------------------------------------------------------------

local function CreateContinuousBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture("Interface\\BUTTONS\\WHITE8X8")
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(0)

    -- Background
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0, 0, 0, 0.5)

    -- Pixel borders
    bar.borders = CreatePixelBorders(bar)

    -- Text
    bar.text = bar:CreateFontString(nil, "OVERLAY")
    bar.text:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
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
        seg:SetStatusBarTexture("Interface\\BUTTONS\\WHITE8X8")
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

    local barTexture = settings and settings.barTexture or "Interface\\BUTTONS\\WHITE8X8"
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
        seg:SetStatusBarTexture("Interface\\BUTTONS\\WHITE8X8")
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
        seg:SetStatusBarTexture("Interface\\BUTTONS\\WHITE8X8")
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

    local barTexture = settings and settings.barTexture or "Interface\\BUTTONS\\WHITE8X8"
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

        -- Position overlay segment exactly on top of base
        local ov = holder.overlaySegments[i]
        ov:ClearAllPoints()
        ov:SetAllPoints(seg)
        ov:SetStatusBarTexture(barTexture)
    end
end

------------------------------------------------------------------------
-- Update logic: Continuous resources (SECRET in combat — NO Lua arithmetic)
------------------------------------------------------------------------

local function UpdateContinuousBar(bar, powerType)
    -- SetMinMaxValues: max is NOT secret
    bar:SetMinMaxValues(0, UnitPowerMax("player", powerType))
    -- SetValue: pass UnitPower directly to C-level — accepts secrets
    bar:SetValue(UnitPower("player", powerType))

    -- Text: pass directly to C-level SetFormattedText — accepts secrets
    if bar.text and bar.text:IsShown() then
        if bar._textFormat == "current" then
            bar.text:SetFormattedText("%d", UnitPower("player", powerType))
        else
            bar.text:SetFormattedText("%d / %d", UnitPower("player", powerType), UnitPowerMax("player", powerType))
        end
    end

end

------------------------------------------------------------------------
-- Update logic: Segmented resources (NOT secret — full Lua logic)
------------------------------------------------------------------------

local function UpdateSegmentedBar(holder, powerType)
    if not holder or not holder.segments then return end

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
        local readyColor, rechargingColor, maxColor = GetRuneColors(GetResourceBarSettings())
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
            elseif r.duration and r.duration > 0 then
                seg:SetValue(math_min((now - r.start) / r.duration, 1))
                seg:SetStatusBarColor(rechargingColor[1], rechargingColor[2], rechargingColor[3], 1)
            else
                seg:SetValue(0)
                seg:SetStatusBarColor(rechargingColor[1], rechargingColor[2], rechargingColor[3], 1)
            end
        end
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
            local readyColor, rechargingColor, maxColor = GetShardColors(GetResourceBarSettings())
            local isMax = (filled == max)
            local activeReadyColor = isMax and maxColor or readyColor
            for i = 1, math_min(#holder.segments, max) do
                local seg = holder.segments[i]
                if i <= filled then
                    seg:SetValue(1)
                    seg:SetStatusBarColor(activeReadyColor[1], activeReadyColor[2], activeReadyColor[3], 1)
                elseif i == filled + 1 and partial > 0 then
                    seg:SetValue(partial)
                    seg:SetStatusBarColor(rechargingColor[1], rechargingColor[2], rechargingColor[3], 1)
                else
                    seg:SetValue(0)
                    seg:SetStatusBarColor(rechargingColor[1], rechargingColor[2], rechargingColor[3], 1)
                end
            end
        end
        return
    end

    if powerType == 19 then
        -- Essence: partial recharge with ready/recharging colors
        local filled = UnitPower("player", 19)
        local max = UnitPowerMax("player", 19)
        local partial = UnitPartialPower("player", 19) / 1000
        local readyColor, rechargingColor, maxColor = GetEssenceColors(GetResourceBarSettings())
        local isMax = (filled == max)
        local activeReadyColor = isMax and maxColor or readyColor
        for i = 1, math_min(#holder.segments, max) do
            local seg = holder.segments[i]
            if i <= filled then
                seg:SetValue(1)
                seg:SetStatusBarColor(activeReadyColor[1], activeReadyColor[2], activeReadyColor[3], 1)
            elseif i == filled + 1 and partial > 0 then
                seg:SetValue(partial)
                seg:SetStatusBarColor(rechargingColor[1], rechargingColor[2], rechargingColor[3], 1)
            else
                seg:SetValue(0)
                seg:SetStatusBarColor(rechargingColor[1], rechargingColor[2], rechargingColor[3], 1)
            end
        end
        return
    end

    -- Combo Points: color changes at max, charged coloring for Rogues
    if powerType == 4 then
        local current = UnitPower("player", 4)
        local max = UnitPowerMax("player", 4)
        local normalColor, maxColor, chargedColor = GetComboColors(GetResourceBarSettings())
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
                if chargedPoints and tContains(chargedPoints, i) then
                    seg:SetStatusBarColor(chargedColor[1], chargedColor[2], chargedColor[3], 1)
                else
                    seg:SetStatusBarColor(baseColor[1], baseColor[2], baseColor[3], 1)
                end
            else
                seg:SetValue(0)
            end
        end
        return
    end

    -- Generic segmented with max color: HolyPower, Chi, ArcaneCharges
    local current = UnitPower("player", powerType)
    local max = UnitPowerMax("player", powerType)
    local normalColor, maxColor
    if powerType == 9 then
        normalColor, maxColor = GetHolyColors(GetResourceBarSettings())
    elseif powerType == 12 then
        normalColor, maxColor = GetChiColors(GetResourceBarSettings())
    elseif powerType == 16 then
        normalColor, maxColor = GetArcaneColors(GetResourceBarSettings())
    else
        local color = GetPowerColor(powerType, GetResourceBarSettings())
        normalColor, maxColor = color, color
    end
    local isMax = (current == max and max > 0)
    local activeColor = isMax and maxColor or normalColor
    for i = 1, math_min(#holder.segments, max) do
        local seg = holder.segments[i]
        if i <= current then
            seg:SetValue(1)
            seg:SetStatusBarColor(activeColor[1], activeColor[2], activeColor[3], 1)
        else
            seg:SetValue(0)
        end
    end
end

------------------------------------------------------------------------
-- Update logic: Maelstrom Weapon (overlay bar, plain applications)
------------------------------------------------------------------------

local function UpdateMaelstromWeaponBar(holder)
    if not holder or not holder.segments then return end

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

    -- Pass stacks to all segments (StatusBar C-level clamping handles fill)
    local half = #holder.segments
    for i = 1, half do
        holder.segments[i]:SetValue(stacks)
        holder.overlaySegments[i]:SetValue(stacks)
    end

    -- Color: direct comparison is safe since MW applications are plain
    local baseColor, overlayColor, maxColor = GetMWColors(GetResourceBarSettings())
    local isMax = stacks > 0 and stacks == mwMaxStacks
    if isMax then
        for i = 1, half do
            holder.segments[i]:SetStatusBarColor(maxColor[1], maxColor[2], maxColor[3], 1)
            holder.overlaySegments[i]:SetStatusBarColor(maxColor[1], maxColor[2], maxColor[3], 1)
        end
    else
        for i = 1, half do
            holder.segments[i]:SetStatusBarColor(baseColor[1], baseColor[2], baseColor[3], 1)
            holder.overlaySegments[i]:SetStatusBarColor(overlayColor[1], overlayColor[2], overlayColor[3], 1)
        end
    end
end

------------------------------------------------------------------------
-- Update logic: Custom aura bars (aura-based, secret-safe)
------------------------------------------------------------------------

local function UpdateCustomAuraBar(barInfo)
    local cabConfig = barInfo.cabConfig
    if not cabConfig or not cabConfig.spellID then return end

    -- Read aura stacks from viewer frame (applications may be secret in combat)
    local stacks = 0
    local viewerFrame = CooldownCompanion.viewerAuraFrames and CooldownCompanion.viewerAuraFrames[cabConfig.spellID]
    local instId = viewerFrame and viewerFrame.auraInstanceID
    if instId then
        local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID("player", instId)
        if auraData then
            stacks = auraData.applications or 0
        end
    end

    local maxStacks = cabConfig.maxStacks or 1
    local barColor = cabConfig.barColor or {0.5, 0.5, 1}

    if barInfo.barType == "custom_continuous" then
        local bar = barInfo.frame
        bar:SetMinMaxValues(0, maxStacks)
        bar:SetValue(stacks)  -- SetValue accepts secrets
        if bar.text and bar.text:IsShown() then
            bar.text:SetFormattedText("%d / %d", stacks, maxStacks)  -- SetFormattedText accepts secrets
        end

    elseif barInfo.barType == "custom_segmented" then
        local holder = barInfo.frame
        if not holder.segments then return end
        -- Each segment has MinMax(i-1, i) — SetValue(stacks) with C-level clamping
        -- handles fill/empty without comparing the secret stacks value in Lua
        for i = 1, #holder.segments do
            holder.segments[i]:SetValue(stacks)
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
    end
end

------------------------------------------------------------------------
-- Styling: Custom aura bars
------------------------------------------------------------------------

local function StyleCustomAuraBar(barInfo, cabConfig, settings)
    local barColor = cabConfig.barColor or {0.5, 0.5, 1}

    if barInfo.barType == "custom_continuous" then
        local bar = barInfo.frame
        bar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], 1)
        if bar.text then
            bar.text:SetShown(cabConfig.showText == true)
        end

    elseif barInfo.barType == "custom_segmented" then
        local holder = barInfo.frame
        if holder.segments then
            for _, seg in ipairs(holder.segments) do
                seg:SetStatusBarColor(barColor[1], barColor[2], barColor[3], 1)
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
            end
        end
    end
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

    for _, barInfo in ipairs(resourceBarFrames) do
        if barInfo.frame and barInfo.frame:IsShown() then
            if barInfo.barType == "continuous" then
                UpdateContinuousBar(barInfo.frame, barInfo.powerType)
            elseif barInfo.barType == "segmented" then
                UpdateSegmentedBar(barInfo.frame, barInfo.powerType)
            elseif barInfo.barType == "mw_segmented" then
                UpdateMaelstromWeaponBar(barInfo.frame)
            elseif barInfo.barType == "custom_continuous"
                or barInfo.barType == "custom_segmented"
                or barInfo.barType == "custom_overlay" then
                UpdateCustomAuraBar(barInfo)
            end
        end
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
                        UpdateMWMaxStacks()
                        CooldownCompanion:EvaluateResourceBars()
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
    local tex = settings.barTexture or "Interface\\BUTTONS\\WHITE8X8"
    local atlasInfo = nil
    local useAtlas = false

    if tex == "blizzard_class" then
        atlasInfo = POWER_ATLAS_INFO[powerType]
        if atlasInfo then
            useAtlas = true
            bar:SetStatusBarTexture(atlasInfo.atlas)
            bar:SetStatusBarColor(1, 1, 1)  -- white so atlas colors show through

            -- Brightness overlay: additive layer over the fill for brightness > 1.0
            local brightness = settings.classBarBrightness or 1.3
            local fillTexture = bar:GetStatusBarTexture()
            bar.brightnessOverlay:SetAllPoints(fillTexture)
            bar.brightnessOverlay:SetAtlas(atlasInfo.atlas)
            if brightness > 1.0 then
                bar.brightnessOverlay:SetAlpha(brightness - 1.0)
                bar.brightnessOverlay:Show()
            elseif brightness < 1.0 then
                bar:SetStatusBarColor(brightness, brightness, brightness)
                bar.brightnessOverlay:Hide()
            else
                bar.brightnessOverlay:Hide()
            end
        else
            -- Fallback for power types without class-specific atlas
            bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
            local color = GetPowerColor(powerType, settings)
            bar:SetStatusBarColor(color[1], color[2], color[3], 1)
            bar.brightnessOverlay:Hide()
        end
    else
        bar:SetStatusBarTexture(tex)
        local color = GetPowerColor(powerType, settings)
        bar:SetStatusBarColor(color[1], color[2], color[3], 1)
        bar.brightnessOverlay:Hide()
    end


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
    local textFont = settings.textFont or "Fonts\\FRIZQT__.TTF"
    local textSize = settings.textFontSize or 10
    local textOutline = settings.textFontOutline or "OUTLINE"
    local textColor = settings.textFontColor or { 1, 1, 1, 1 }

    bar.text:SetFont(textFont, textSize, textOutline)
    bar.text:SetTextColor(textColor[1], textColor[2], textColor[3], textColor[4])

    -- Continuous bars show text by default
    local showText = true
    if settings.resources and settings.resources[powerType] then
        local ov = settings.resources[powerType]
        if ov.showText == false then showText = false end
    end
    bar.text:SetShown(showText)
    bar._textFormat = settings.textFormat or "current"
end

local function StyleSegmentedBar(holder, powerType, settings)
    if powerType == 4 then
        -- Combo Points: colored dynamically per-segment in UpdateSegmentedBar
        local normalColor = GetComboColors(settings)
        for _, seg in ipairs(holder.segments) do
            seg:SetStatusBarColor(normalColor[1], normalColor[2], normalColor[3], 1)
        end
    elseif powerType == 5 then
        -- Runes: colored dynamically per-segment in UpdateSegmentedBar
        local readyColor = GetRuneColors(settings)
        for _, seg in ipairs(holder.segments) do
            seg:SetStatusBarColor(readyColor[1], readyColor[2], readyColor[3], 1)
        end
    elseif powerType == 7 then
        -- Soul Shards: colored dynamically per-segment in UpdateSegmentedBar
        local readyColor = GetShardColors(settings)
        for _, seg in ipairs(holder.segments) do
            seg:SetStatusBarColor(readyColor[1], readyColor[2], readyColor[3], 1)
        end
    elseif powerType == 9 then
        -- Holy Power: colored dynamically per-segment in UpdateSegmentedBar
        local normalColor = GetHolyColors(settings)
        for _, seg in ipairs(holder.segments) do
            seg:SetStatusBarColor(normalColor[1], normalColor[2], normalColor[3], 1)
        end
    elseif powerType == 12 then
        -- Chi: colored dynamically per-segment in UpdateSegmentedBar
        local normalColor = GetChiColors(settings)
        for _, seg in ipairs(holder.segments) do
            seg:SetStatusBarColor(normalColor[1], normalColor[2], normalColor[3], 1)
        end
    elseif powerType == 16 then
        -- Arcane Charges: colored dynamically per-segment in UpdateSegmentedBar
        local normalColor = GetArcaneColors(settings)
        for _, seg in ipairs(holder.segments) do
            seg:SetStatusBarColor(normalColor[1], normalColor[2], normalColor[3], 1)
        end
    elseif powerType == 19 then
        -- Essence: colored dynamically per-segment in UpdateSegmentedBar
        local readyColor = GetEssenceColors(settings)
        for _, seg in ipairs(holder.segments) do
            seg:SetStatusBarColor(readyColor[1], readyColor[2], readyColor[3], 1)
        end
    else
        local color = GetPowerColor(powerType, settings)
        for _, seg in ipairs(holder.segments) do
            seg:SetStatusBarColor(color[1], color[2], color[3], 1)
        end
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

    if settings.reverseResourceOrder and #filtered > 1 then
        local n = #filtered
        for i = 1, math.floor(n / 2) do
            filtered[i], filtered[n - i + 1] = filtered[n - i + 1], filtered[i]
        end
    end

    -- Append enabled custom aura bars
    local customBars = settings.customAuraBars or {}
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

    -- Create container frame if needed
    if not containerFrame then
        containerFrame = CreateFrame("Frame", "CooldownCompanionResourceBars", UIParent)
        containerFrame:SetFrameStrata("MEDIUM")
    end
    containerFrame:Show()

    -- Create or recycle bar frames
    local barHeight = settings.barHeight or 12
    local barSpacing = settings.barSpacing or 3.6
    local segmentGap = settings.segmentGap or 4
    local totalWidth = groupFrame:GetWidth()

    -- Hide existing bars that we don't need
    for i = #filtered + 1, #resourceBarFrames do
        if resourceBarFrames[i] and resourceBarFrames[i].frame then
            resourceBarFrames[i].frame:Hide()
            if resourceBarFrames[i].frame.brightnessOverlay then
                resourceBarFrames[i].frame.brightnessOverlay:Hide()
            end
        end
    end

    for idx, powerType in ipairs(filtered) do
        local isSegmented = SEGMENTED_TYPES[powerType]
        local barInfo = resourceBarFrames[idx]

        if powerType == RESOURCE_MAELSTROM_WEAPON then
            -- Maelstrom Weapon: overlay bar with dedicated update
            local halfSegments = mwMaxStacks <= 5 and mwMaxStacks or (mwMaxStacks / 2)

            if not barInfo or barInfo.barType ~= "mw_segmented"
                or #barInfo.frame.segments ~= halfSegments then
                if barInfo and barInfo.frame then barInfo.frame:Hide() end
                local holder = CreateOverlayBar(containerFrame, halfSegments)
                barInfo = { frame = holder, barType = "mw_segmented", powerType = powerType }
                resourceBarFrames[idx] = barInfo
            else
                barInfo.powerType = powerType
            end

            barInfo.frame:SetSize(totalWidth, barHeight)
            LayoutOverlaySegments(barInfo.frame, totalWidth, barHeight, segmentGap, settings, halfSegments)

            -- Apply initial colors
            local baseColor, overlayColor = GetMWColors(settings)
            for i = 1, halfSegments do
                barInfo.frame.segments[i]:SetStatusBarColor(baseColor[1], baseColor[2], baseColor[3], 1)
                barInfo.frame.overlaySegments[i]:SetStatusBarColor(overlayColor[1], overlayColor[2], overlayColor[3], 1)
                barInfo.frame.overlaySegments[i]:Show()
            end

        elseif powerType >= CUSTOM_AURA_BAR_BASE and powerType < CUSTOM_AURA_BAR_BASE + MAX_CUSTOM_AURA_BARS then
            -- Custom aura bar
            local cabIndex = powerType - CUSTOM_AURA_BAR_BASE + 1
            local cabConfig = customBars[cabIndex]
            local mode = cabConfig.displayMode or "segmented"
            local maxStacks = cabConfig.maxStacks or 1
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
                if barInfo and barInfo.frame then barInfo.frame:Hide() end
                if mode == "continuous" then
                    local bar = CreateContinuousBar(containerFrame)
                    bar:SetMinMaxValues(0, maxStacks)
                    barInfo = { frame = bar, barType = "custom_continuous", powerType = powerType }
                elseif mode == "segmented" then
                    local holder = CreateSegmentedBar(containerFrame, maxStacks)
                    -- Set per-segment MinMax for secret-safe SetValue(stacks) clamping
                    for si = 1, maxStacks do
                        holder.segments[si]:SetMinMaxValues(si - 1, si)
                    end
                    barInfo = { frame = holder, barType = "custom_segmented", powerType = powerType }
                elseif mode == "overlay" then
                    local half = math.ceil(maxStacks / 2)
                    local holder = CreateOverlayBar(containerFrame, half)
                    barInfo = { frame = holder, barType = "custom_overlay", powerType = powerType, halfSegments = half }
                end
                resourceBarFrames[idx] = barInfo
            end

            barInfo.cabConfig = cabConfig
            barInfo.frame:SetSize(totalWidth, barHeight)
            if mode == "segmented" then
                LayoutSegments(barInfo.frame, totalWidth, barHeight, segmentGap, settings)
            elseif mode == "overlay" then
                LayoutOverlaySegments(barInfo.frame, totalWidth, barHeight, segmentGap, settings, barInfo.halfSegments)
            end
            StyleCustomAuraBar(barInfo, cabConfig, settings)

            -- Continuous bar styling (text font, background, borders)
            if mode == "continuous" then
                local tex = settings.barTexture or "Interface\\BUTTONS\\WHITE8X8"
                barInfo.frame:SetStatusBarTexture(tex)
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
                -- Text setup
                local textFont = settings.textFont or "Fonts\\FRIZQT__.TTF"
                local textSize = settings.textFontSize or 10
                local textOutline = settings.textFontOutline or "OUTLINE"
                local textColor = settings.textFontColor or { 1, 1, 1, 1 }
                barInfo.frame.text:SetFont(textFont, textSize, textOutline)
                barInfo.frame.text:SetTextColor(textColor[1], textColor[2], textColor[3], textColor[4])
                barInfo.frame.brightnessOverlay:Hide()
            end
        elseif isSegmented then
            local max = UnitPowerMax("player", powerType)
            if powerType == 5 then max = 6 end  -- Runes always 6
            if max < 1 then max = 1 end

            -- Need to recreate if segment count changed or type changed
            if not barInfo or barInfo.barType ~= "segmented"
                or barInfo.frame._numSegments ~= max then
                if barInfo and barInfo.frame then
                    barInfo.frame:Hide()
                end
                local holder = CreateSegmentedBar(containerFrame, max)
                barInfo = { frame = holder, barType = "segmented", powerType = powerType }
                resourceBarFrames[idx] = barInfo
            else
                barInfo.powerType = powerType
            end

            barInfo.frame:SetSize(totalWidth, barHeight)
            LayoutSegments(barInfo.frame, totalWidth, barHeight, segmentGap, settings)
            StyleSegmentedBar(barInfo.frame, powerType, settings)
        else
            -- Continuous bar
            if not barInfo or barInfo.barType ~= "continuous" then
                if barInfo and barInfo.frame then
                    barInfo.frame:Hide()
                end
                local bar = CreateContinuousBar(containerFrame)
                barInfo = { frame = bar, barType = "continuous", powerType = powerType }
                resourceBarFrames[idx] = barInfo
            else
                barInfo.powerType = powerType
            end

            barInfo.frame:SetSize(totalWidth, barHeight)
            StyleContinuousBar(barInfo.frame, powerType, settings)
        end

        barInfo.frame:Show()
    end

    activeResources = filtered

    -- Layout: stack bars vertically inside container
    local stackOffset = self:GetAnchorStackOffset("resourceBars")
    local yOfs = settings.yOffset or -3
    local position = settings.position or "below"

    containerFrame:ClearAllPoints()
    containerFrame:SetSize(totalWidth, 1) -- height set by content

    if position == "above" then
        containerFrame:SetPoint("BOTTOMLEFT", groupFrame, "TOPLEFT", 0, -yOfs + stackOffset)
    else
        containerFrame:SetPoint("TOPLEFT", groupFrame, "BOTTOMLEFT", 0, yOfs - stackOffset)
    end

    -- Position individual bars within container
    local currentY = 0
    for idx, barInfo in ipairs(resourceBarFrames) do
        if barInfo.frame:IsShown() then
            barInfo.frame:ClearAllPoints()
            if position == "above" then
                -- Stack upward: first bar at bottom of container, subsequent above
                barInfo.frame:SetPoint("BOTTOMLEFT", containerFrame, "BOTTOMLEFT", 0, currentY)
                barInfo.frame:SetPoint("BOTTOMRIGHT", containerFrame, "BOTTOMRIGHT", 0, currentY)
            else
                -- Stack downward: first bar at top of container, subsequent below
                barInfo.frame:SetPoint("TOPLEFT", containerFrame, "TOPLEFT", 0, -currentY)
                barInfo.frame:SetPoint("TOPRIGHT", containerFrame, "TOPRIGHT", 0, -currentY)
            end
            barInfo.frame:SetHeight(barHeight)
            currentY = currentY + barHeight + barSpacing
        end
    end

    -- Set container total height
    local totalHeight = currentY - barSpacing  -- subtract trailing spacing
    if totalHeight < 1 then totalHeight = 1 end
    containerFrame:SetHeight(totalHeight)

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
            savedContainerAlpha = containerFrame:GetAlpha()
        end

        -- Apply alpha immediately
        local groupAlpha = groupFrame:GetEffectiveAlpha()
        containerFrame:SetAlpha(groupAlpha)

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
                if containerFrame then containerFrame:SetAlpha(alpha) end
            end
        end)
    else
        -- inheritAlpha is off — stop sync and restore original if we had it
        if alphaSyncFrame then
            alphaSyncFrame:SetScript("OnUpdate", nil)
        end
        if savedContainerAlpha and containerFrame then
            containerFrame:SetAlpha(savedContainerAlpha)
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

    -- Stop alpha sync and restore alpha
    if alphaSyncFrame then
        alphaSyncFrame:SetScript("OnUpdate", nil)
    end
    if savedContainerAlpha and containerFrame then
        containerFrame:SetAlpha(savedContainerAlpha)
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
            barInfo.frame:Hide()
            if barInfo.frame.brightnessOverlay then
                barInfo.frame.brightnessOverlay:Hide()
            end
        end
    end

    -- Hide container
    if containerFrame then
        containerFrame:Hide()
    end

    isPreviewActive = false
    activeResources = {}
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

------------------------------------------------------------------------
-- Total height for stacking coordination
------------------------------------------------------------------------

function CooldownCompanion:GetResourceBarsTotalHeight()
    if not isApplied then return 0 end
    local settings = GetResourceBarSettings()
    if not settings then return 0 end

    local count = 0
    for _, barInfo in ipairs(resourceBarFrames) do
        if barInfo.frame and barInfo.frame:IsShown() then
            count = count + 1
        end
    end
    if count == 0 then return 0 end

    local barHeight = settings.barHeight or 12
    local barSpacing = settings.barSpacing or 3.6
    return count * barHeight + (count - 1) * barSpacing + math_abs(settings.yOffset or -3)
end

------------------------------------------------------------------------
-- Preview mode
------------------------------------------------------------------------

local function ApplyPreviewData()
    for _, barInfo in ipairs(resourceBarFrames) do
        if barInfo.frame and barInfo.frame:IsShown() then
            if barInfo.barType == "continuous" then
                barInfo.frame:SetMinMaxValues(0, 100)
                barInfo.frame:SetValue(65)
                if barInfo.frame.text and barInfo.frame.text:IsShown() then
                    barInfo.frame.text:SetText("65 / 100")
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
            elseif barInfo.barType == "mw_segmented" then
                -- Preview at 7 stacks (all 5 base full, 2 overlay full)
                local half = #barInfo.frame.segments
                for i = 1, half do
                    barInfo.frame.segments[i]:SetValue(7)
                    barInfo.frame.overlaySegments[i]:SetValue(7)
                end
            elseif barInfo.barType == "custom_continuous" then
                local cabConfig = barInfo.cabConfig
                local maxStacks = (cabConfig and cabConfig.maxStacks) or 1
                barInfo.frame:SetMinMaxValues(0, maxStacks)
                local val = math.ceil(maxStacks * 0.65)
                barInfo.frame:SetValue(val)
                if barInfo.frame.text and barInfo.frame.text:IsShown() then
                    barInfo.frame.text:SetFormattedText("%d / %d", val, maxStacks)
                end
            elseif barInfo.barType == "custom_segmented" then
                local n = #barInfo.frame.segments
                local fill = math.ceil(n * 0.6)
                -- Segments have MinMax(i-1, i); C-level clamping handles fill/empty
                for _, seg in ipairs(barInfo.frame.segments) do
                    seg:SetValue(fill)
                end
            elseif barInfo.barType == "custom_overlay" then
                local cabConfig = barInfo.cabConfig
                local maxStacks = (cabConfig and cabConfig.maxStacks) or 1
                local previewStacks = math.ceil(maxStacks * 0.7)
                local half = barInfo.halfSegments or 1
                for i = 1, half do
                    barInfo.frame.segments[i]:SetValue(previewStacks)
                    barInfo.frame.overlaySegments[i]:SetValue(previewStacks)
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

    -- When all groups refresh — re-evaluate
    hooksecurefunc(CooldownCompanion, "RefreshAllGroups", function()
        C_Timer.After(0.1, function()
            CooldownCompanion:EvaluateResourceBars()
        end)
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
