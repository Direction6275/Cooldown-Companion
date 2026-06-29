--[[
    CooldownCompanion - Config/CooldownManagerPanels
    Read-only Cooldown Manager starter panel helpers.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local ipairs = ipairs
local math_floor = math.floor
local math_max = math.max
local tonumber = tonumber

local IsConcreteSpellID = ST.IsConcreteSpellID
local ResolveCDMDisplaySpellID = ST.ResolveCDMDisplaySpellID
local ResolveCDMAuraSpellID = ST.ResolveCDMAuraSpellID
local bit_band = bit and bit.band

local CDM_PANEL_SOURCES = {
    {
        key = "trackedBuffs",
        categoryKey = "TrackedBuff",
        panelName = "CDM | Tracked Buffs",
        displayMode = "icons",
        entryKind = "aura",
        layoutKind = "trackedBuffs",
    },
    {
        key = "essential",
        categoryKey = "Essential",
        panelName = "CDM | Essential Cooldowns",
        displayMode = "icons",
        entryKind = "spell",
        layoutKind = "essential",
    },
    {
        key = "utility",
        categoryKey = "Utility",
        panelName = "CDM | Utility Cooldowns",
        displayMode = "icons",
        entryKind = "spell",
        layoutKind = "utility",
    },
    {
        key = "trackedBars",
        categoryKey = "TrackedBar",
        panelName = "CDM | Tracked Bars",
        displayMode = "bars",
        entryKind = "aura",
        layoutKind = "trackedBars",
    },
}

local CDM_PANEL_SOURCE_BY_KEY = {}
for _, source in ipairs(CDM_PANEL_SOURCES) do
    CDM_PANEL_SOURCE_BY_KEY[source.key] = source
end

local function IsKnownSourceKey(sourceKey)
    return CDM_PANEL_SOURCE_BY_KEY[sourceKey] ~= nil
end

local function GetSourceDisplayMode(sourceKey)
    local source = CDM_PANEL_SOURCE_BY_KEY[sourceKey]
    return source and source.displayMode or nil
end

local function CheckCooldownViewerAvailable()
    if not (C_CooldownViewer
        and C_CooldownViewer.GetCooldownViewerCategorySet
        and C_CooldownViewer.GetCooldownViewerCooldownInfo
        and Enum
        and Enum.CooldownViewerCategory) then
        return false, "Cooldown Manager API is unavailable."
    end

    if C_CooldownViewer.IsCooldownViewerAvailable then
        local available, failureReason = C_CooldownViewer.IsCooldownViewerAvailable()
        if available ~= true then
            if type(failureReason) == "string" and failureReason ~= "" then
                return false, failureReason
            end
            return false, "Unknown reason"
        end
    end

    return true, nil
end

local function GetCooldownViewerSettingsDataProvider()
    local settings = CooldownViewerSettings
    if not settings and C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_CooldownViewer")
        settings = CooldownViewerSettings
    end

    local dataProvider = settings
        and settings.GetDataProvider
        and settings:GetDataProvider()
        or nil
    if not (dataProvider
        and dataProvider.CheckBuildDisplayData
        and dataProvider.GetOrderedCooldownIDsForCategory
        and dataProvider.GetCooldownInfoForID) then
        return nil
    end

    -- Raw category sets include entries Blizzard shows under Not Displayed.
    dataProvider:CheckBuildDisplayData()
    return dataProvider
end

local function GetCooldownCategory(source)
    local categories = Enum and Enum.CooldownViewerCategory
    return categories and categories[source.categoryKey] or nil
end

local function HasCooldownFlag(cooldownInfo, flag)
    if not (cooldownInfo and type(flag) == "number" and bit_band) then
        return false
    end
    local flags = cooldownInfo.flags
    if type(flags) ~= "number" then
        return false
    end
    return bit_band(flags, flag) ~= 0
end

local function ShouldIncludeAuraCooldownInfo(cooldownInfo)
    if type(cooldownInfo) ~= "table" then
        return false
    end

    local flagsEnum = Enum and Enum.CooldownSetSpellFlags
    if flagsEnum and HasCooldownFlag(cooldownInfo, flagsEnum.HideAura) then
        return false
    end

    return true
end

local function ResolveSpellName(spellID)
    if not (C_Spell and IsConcreteSpellID and IsConcreteSpellID(spellID)) then
        return nil
    end

    if C_Spell.GetSpellInfo then
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        if spellInfo and spellInfo.name then
            return spellInfo.name
        end
    end

    if C_Spell.GetSpellName then
        return C_Spell.GetSpellName(spellID)
    end

    return nil
end

local function ResolveEntrySpellID(source, cooldownInfo)
    if source.entryKind == "aura" then
        return ResolveCDMAuraSpellID and ResolveCDMAuraSpellID(cooldownInfo) or nil
    end

    return ResolveCDMDisplaySpellID and ResolveCDMDisplaySpellID(cooldownInfo)
        or cooldownInfo and cooldownInfo.spellID
        or nil
end

local function BuildSourceEntries(source, dataProvider)
    local entries = {}
    local category = GetCooldownCategory(source)
    if category == nil then
        return entries
    end

    local cooldownIDs = dataProvider:GetOrderedCooldownIDsForCategory(category, false)
    if type(cooldownIDs) ~= "table" then
        return entries
    end

    local seen = {}
    for _, cooldownID in ipairs(cooldownIDs) do
        if type(cooldownID) == "number" then
            local cooldownInfo = dataProvider:GetCooldownInfoForID(cooldownID)
            if type(cooldownInfo) == "table"
                and cooldownInfo.isKnown ~= false
                and (source.entryKind ~= "aura" or ShouldIncludeAuraCooldownInfo(cooldownInfo)) then
                local spellID = ResolveEntrySpellID(source, cooldownInfo)
                if IsConcreteSpellID and IsConcreteSpellID(spellID) and not seen[spellID] then
                    local name = ResolveSpellName(spellID)
                    if type(name) == "string" and name ~= "" then
                        seen[spellID] = true
                        entries[#entries + 1] = {
                            id = spellID,
                            name = name,
                            sourceKey = source.key,
                            cooldownID = cooldownID,
                            forceAura = source.entryKind == "aura" and true or false,
                            isPassive = source.entryKind == "aura" and true or nil,
                        }
                    end
                end
            end
        end
    end

    return entries
end

local function CopySourceSpec(source)
    return {
        key = source.key,
        categoryKey = source.categoryKey,
        panelName = source.panelName,
        displayMode = source.displayMode,
        entryKind = source.entryKind,
        layoutKind = source.layoutKind,
    }
end

local function BuildCDMPanelSourceData()
    local available, failureReason = CheckCooldownViewerAvailable()
    local result = {
        available = available == true,
        failureReason = failureReason,
        sources = {},
        sourcesByKey = {},
        totalEntries = 0,
    }

    if not result.available then
        return result
    end

    local dataProvider = GetCooldownViewerSettingsDataProvider()
    if not dataProvider then
        result.available = false
        result.failureReason = "Cooldown Manager display data is unavailable."
        return result
    end

    for _, sourceSpec in ipairs(CDM_PANEL_SOURCES) do
        local source = CopySourceSpec(sourceSpec)
        source.entries = BuildSourceEntries(sourceSpec, dataProvider)
        result.totalEntries = result.totalEntries + #source.entries
        result.sources[#result.sources + 1] = source
        result.sourcesByKey[source.key] = source
    end

    return result
end

local function GetSourceData(sourceData, sourceKey)
    if not (sourceData and sourceKey) then
        return nil
    end
    return sourceData.sourcesByKey and sourceData.sourcesByKey[sourceKey] or nil
end

local function PopulateCDMPanelFromSource(panelId, sourceData)
    local group = CooldownCompanion
        and CooldownCompanion.db
        and CooldownCompanion.db.profile
        and CooldownCompanion.db.profile.groups
        and CooldownCompanion.db.profile.groups[panelId]
        or nil
    if not group then
        return 0
    end

    group.buttons = {}

    local added = 0
    for _, entry in ipairs(sourceData and sourceData.entries or {}) do
        local index = CooldownCompanion:AddButtonToGroup(
            panelId,
            "spell",
            entry.id,
            entry.name,
            nil,
            entry.isPassive,
            entry.forceAura,
            nil,
            sourceData.entryKind == "spell"
        )
        if index then
            if sourceData.entryKind == "spell" and group.buttons and group.buttons[index] then
                group.buttons[index].name = entry.name
            end
            added = added + 1
        end
    end

    if added == 0 and CooldownCompanion.RefreshGroupFrame then
        CooldownCompanion:RefreshGroupFrame(panelId)
    end

    return added
end

local function SetPanelAnchor(group, containerId, x, y)
    if not group then
        return
    end
    group.anchor = {
        point = "CENTER",
        relativeTo = "CooldownCompanionContainer" .. tostring(containerId),
        relativePoint = "CENTER",
        x = x,
        y = y,
    }
end

local function GetStarterButtonLimit(entryCount, fallback)
    local count = tonumber(entryCount)
    if count and count > 0 then
        return math_max(1, math_floor(count))
    end

    return math_max(1, tonumber(fallback) or 12)
end

local function ScaleIconPanel(style, scale, floorSize, entryCount)
    local baseSize = tonumber(style.buttonSize) or ST.BUTTON_SIZE or 36
    style.buttonSize = math_max(floorSize, math_floor((baseSize * scale) + 0.5))
    style.maintainAspectRatio = true
    style.iconWidth = nil
    style.iconHeight = nil
    style.orientation = "horizontal"
    style.growthOrigin = "TOPLEFT"
    style.buttonsPerRow = GetStarterButtonLimit(entryCount, style.buttonsPerRow)
end

local function ApplyCDMStarterPanelLayout(group, sourceKey, containerId, entryCount)
    local source = CDM_PANEL_SOURCE_BY_KEY[sourceKey]
    if not (group and source) then
        return
    end

    group.style = group.style or {}
    local style = group.style

    if source.layoutKind == "essential" then
        ScaleIconPanel(style, 1.3, 46, entryCount)
        SetPanelAnchor(group, containerId, 0, 215)
    elseif source.layoutKind == "trackedBuffs" then
        ScaleIconPanel(style, 0.95, 34, entryCount)
        SetPanelAnchor(group, containerId, 0, 85)
    elseif source.layoutKind == "utility" then
        ScaleIconPanel(style, 0.95, 34, entryCount)
        SetPanelAnchor(group, containerId, 0, 150)
    elseif source.layoutKind == "trackedBars" then
        style.orientation = "vertical"
        style.growthOrigin = "TOPLEFT"
        style.buttonsPerRow = GetStarterButtonLimit(entryCount, style.buttonsPerRow)
        style.barLength = math_max(180, tonumber(style.barLength) or 180)
        style.barHeight = math_max(20, tonumber(style.barHeight) or 20)
        style.barIconSize = math_max(20, tonumber(style.barIconSize) or style.barHeight or 20)
        SetPanelAnchor(group, containerId, 150, 0)
    end
end

ST._BuildCDMPanelSourceData = BuildCDMPanelSourceData
ST._GetCDMPanelSourceData = GetSourceData
ST._PopulateCDMPanelFromSource = PopulateCDMPanelFromSource
ST._ApplyCDMStarterPanelLayout = ApplyCDMStarterPanelLayout
ST._IsCDMPanelSourceKey = IsKnownSourceKey
ST._GetCDMPanelSourceDisplayMode = GetSourceDisplayMode
ST._CDMPanelSources = CDM_PANEL_SOURCES
