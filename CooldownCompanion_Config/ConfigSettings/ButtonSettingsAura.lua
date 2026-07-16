--[[
    CooldownCompanion_Config - ConfigSettings/ButtonSettingsAura.lua
    Per-entry Aura tab (12.1 rebuild, fresh design — no CDM concepts).
    Phase 1 scope: enable toggle, tracked-aura list + add box, derived unit
    line. Display toggles and style sections arrive in later phases.
    The tracked unit is auto-derived from spell polarity and never user-set:
    Blizzard's anti-cheat gate allows only buffs-on-player and own-debuffs-
    on-target, so illegal configurations are unrepresentable here.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

local ColorHeading = ST._ColorHeading
local CreateInfoButton = ST._CreateInfoButton

-- Full group refresh, not just a rebind: aura config changes can flip the
-- CC-side static composition too (shell alpha, countdown text hosting),
-- which only UpdateButtonStyle applies.
local function RefreshAuraConfig()
    CooldownCompanion:RefreshAllGroups()
    CooldownCompanion:RequestAuraRebind("config")
    CooldownCompanion:RefreshConfigPanel()
end

local function ClassifyAuraSpellUnit(spellID)
    if not (spellID and C_Spell.DoesSpellExist(spellID)) then return nil end
    return C_Spell.IsSpellHarmful(spellID) and "target" or "player"
end

local function GetEntryAuraUnit(buttonData)
    local resolved = CooldownCompanion:ResolveAuraSpellID(buttonData)
    return ClassifyAuraSpellUnit(resolved) or buttonData.auraUnit or "player"
end

-- Store the derived unit whenever tracking config changes, so the runtime's
-- fallback (uncached spells at login) starts from the right value.
local function SyncDerivedAuraUnit(buttonData)
    local unit = ClassifyAuraSpellUnit(CooldownCompanion:ResolveAuraSpellID(buttonData))
    if unit then
        buttonData.auraUnit = unit
    end
end

local function GetCandidateList(buttonData)
    local list = {}
    local raw = buttonData.auraSpellID and tostring(buttonData.auraSpellID) or nil
    if raw then
        for id in raw:gmatch("%d+") do
            list[#list + 1] = tonumber(id)
        end
    end
    return list
end

local function SetCandidateList(buttonData, list)
    if #list > 0 then
        local parts = {}
        for i, id in ipairs(list) do parts[i] = tostring(id) end
        buttonData.auraSpellID = table.concat(parts, ",")
    else
        buttonData.auraSpellID = nil
    end
    -- Keep the stored (derived) unit in sync with the list's polarity.
    SyncDerivedAuraUnit(buttonData)
    if buttonData.addedAs == "aura" and CooldownCompanion.NormalizeStandaloneAuraButtonData then
        CooldownCompanion:NormalizeStandaloneAuraButtonData(buttonData)
    end
end

local function TryAddCandidate(buttonData, input)
    input = input and input:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if input == "" then return false end
    local spellID = tonumber(input)
    if not spellID then
        local info = C_Spell.GetSpellInfo(input)
        spellID = info and info.spellID
    end
    if not (spellID and C_Spell.DoesSpellExist(spellID)) then
        CooldownCompanion:Print("Aura not found: " .. input .. ". Try the spell ID.")
        return false
    end
    local list = GetCandidateList(buttonData)
    for _, existing in ipairs(list) do
        if existing == spellID then
            return false
        end
    end
    local newUnit = ClassifyAuraSpellUnit(spellID)
    local currentUnit = GetEntryAuraUnit(buttonData)
    if newUnit and newUnit ~= currentUnit then
        CooldownCompanion:Print("Buffs and debuffs can't be tracked by the same entry. Debuffs are tracked on your target, buffs on you.")
        return false
    end
    list[#list + 1] = spellID
    SetCandidateList(buttonData, list)
    return true
end

-- Removing the last listed aura is always allowed: the entry's own aura is
-- implicit (standalone entries rebuild it from the entry itself), so an empty
-- list just returns to the default.
local function RemoveCandidate(buttonData, spellID)
    local list = GetCandidateList(buttonData)
    for i, existing in ipairs(list) do
        if existing == spellID then
            table.remove(list, i)
            SetCandidateList(buttonData, list)
            return true
        end
    end
    return false
end

local function AddCandidateRow(scroll, buttonData, spellID)
    local row = AceGUI:Create("SimpleGroup")
    row:SetLayout("Flow")
    row:SetFullWidth(true)

    local info = C_Spell.GetSpellInfo(spellID)
    local name = info and info.name or ("Spell " .. spellID)

    local label = AceGUI:Create("Label")
    label:SetImage(C_Spell.GetSpellTexture(spellID) or 134400)
    label:SetImageSize(16, 16)
    label:SetText(("%s |cff999999(%d)|r"):format(name, spellID))
    label:SetRelativeWidth(0.8)
    row:AddChild(label)

    local remove = AceGUI:Create("InteractiveLabel")
    remove:SetText("|cffff5555Remove|r")
    remove:SetRelativeWidth(0.2)
    remove:SetCallback("OnClick", function()
        if RemoveCandidate(buttonData, spellID) then
            RefreshAuraConfig()
        end
    end)
    row:AddChild(remove)

    scroll:AddChild(row)
end

local function BuildAuraTab(scroll, group, buttonData, infoButtons)
    local isStandalone = buttonData.addedAs == "aura"

    local heading = AceGUI:Create("Heading")
    heading:SetText("Aura Tracking")
    ColorHeading(heading)
    heading:SetFullWidth(true)
    scroll:AddChild(heading)
    CreateInfoButton(heading.frame, heading.label, "LEFT", "RIGHT", 4, 0, {
        "Aura Tracking",
        {"Blizzard tracks the aura and drives the display directly; the addon never reads aura state in combat.", 1, 1, 1, true},
        {" ", 1, 1, 1, true},
        {"Buffs can only be tracked on yourself, and your own debuffs only on your target. This is a Blizzard restriction. The tracked unit is set automatically from the aura.", 1, 1, 1, true},
        {" ", 1, 1, 1, true},
        {"With no auras listed, the entry tracks its own aura. Added aura IDs override that; for spell entries the entry's own aura is always kept as a fallback.", 1, 1, 1, true},
    }, infoButtons)

    if not isStandalone then
        local enable = AceGUI:Create("CheckBox")
        enable:SetLabel("Track an Aura")
        enable:SetValue(buttonData.auraTracking == true)
        enable:SetFullWidth(true)
        enable:SetCallback("OnValueChanged", function(_, _, value)
            buttonData.auraTracking = value and true or nil
            if value then
                if not buttonData.auraSpellID then
                    local inferred = CooldownCompanion:InferConfirmedAuraSpellIDString(buttonData)
                    if inferred then
                        buttonData.auraSpellID = inferred
                    end
                end
                SyncDerivedAuraUnit(buttonData)
            end
            RefreshAuraConfig()
        end)
        scroll:AddChild(enable)
    end

    if not (isStandalone or buttonData.auraTracking) then
        return
    end

    -- Derived unit line (read-only by design; the "?" button explains why).
    local unit = GetEntryAuraUnit(buttonData)
    local unitLabel = AceGUI:Create("Label")
    unitLabel:SetText("|cffffd100Tracked on:|r " .. (unit == "target" and "Target" or "You"))
    unitLabel:SetFullWidth(true)
    scroll:AddChild(unitLabel)

    -- Tracked aura list (empty = tracking the entry's own aura; the "?"
    -- button explains the default and override behavior).
    for _, spellID in ipairs(GetCandidateList(buttonData)) do
        AddCandidateRow(scroll, buttonData, spellID)
    end

    local addBox = AceGUI:Create("EditBox")
    addBox:SetLabel("Add aura by name or ID")
    addBox:SetText("")
    addBox:SetFullWidth(true)
    addBox:SetCallback("OnEnterPressed", function(widget, _, text)
        if TryAddCandidate(buttonData, text) then
            widget:SetText("")
            RefreshAuraConfig()
        end
    end)
    scroll:AddChild(addBox)

    -- Display toggles. Standalone and passive entries always show the live
    -- aura icon (it exists to display the aura), so the opt-in only appears
    -- on ordinary spell entries.
    if not (isStandalone or buttonData.isPassive) then
        local iconCb = AceGUI:Create("CheckBox")
        iconCb:SetLabel("Show Aura Icon While Active")
        iconCb:SetValue(buttonData.auraShowAuraIcon == true)
        iconCb:SetFullWidth(true)
        iconCb:SetCallback("OnValueChanged", function(_, _, value)
            buttonData.auraShowAuraIcon = value and true or nil
            RefreshAuraConfig()
        end)
        scroll:AddChild(iconCb)
    end

    if buttonData.isPassive then
        -- Passives desaturate while the aura is missing by default.
        local invertCb = AceGUI:Create("CheckBox")
        invertCb:SetLabel("Desaturate While Active Instead")
        invertCb:SetValue(buttonData.invertAuraDesaturationLogic == true)
        invertCb:SetFullWidth(true)
        invertCb:SetCallback("OnValueChanged", function(_, _, value)
            buttonData.invertAuraDesaturationLogic = value and true or nil
            RefreshAuraConfig()
        end)
        scroll:AddChild(invertCb)

        local neverCb = AceGUI:Create("CheckBox")
        neverCb:SetLabel("Never Desaturate")
        neverCb:SetValue(buttonData.neverDesaturate == true)
        neverCb:SetFullWidth(true)
        neverCb:SetCallback("OnValueChanged", function(_, _, value)
            buttonData.neverDesaturate = value and true or nil
            RefreshAuraConfig()
        end)
        scroll:AddChild(neverCb)
    else
        local desatCb = AceGUI:Create("CheckBox")
        desatCb:SetLabel("Desaturate Icon While Aura Missing")
        desatCb:SetValue(buttonData.desaturateWhileAuraNotActive == true)
        desatCb:SetFullWidth(true)
        desatCb:SetCallback("OnValueChanged", function(_, _, value)
            buttonData.desaturateWhileAuraNotActive = value and true or nil
            RefreshAuraConfig()
        end)
        scroll:AddChild(desatCb)
    end
end

ST._BuildAuraTab = BuildAuraTab
