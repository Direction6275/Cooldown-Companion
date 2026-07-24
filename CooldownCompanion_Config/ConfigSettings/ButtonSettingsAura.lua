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
    -- Two-column layout (same pattern as the panel tabs): half-width display
    -- toggles pair side by side; the heading, labels, aura list rows, and add
    -- box stay full width.
    scroll:SetLayout("Flow")

    local heading = AceGUI:Create("Heading")
    heading:SetText("Aura Tracking")
    ColorHeading(heading)
    heading:SetFullWidth(true)
    scroll:AddChild(heading)
    local auraInfoBtn = CreateInfoButton(heading.frame, heading.label, "LEFT", "RIGHT", 4, 0, {
        "Aura Tracking",
        {"Blizzard tracks the aura and drives the display directly; the addon never reads aura state in combat.", 1, 1, 1, true},
        {" ", 1, 1, 1, true},
        {"Buffs can only be tracked on yourself, and your own debuffs only on your target. This is a Blizzard restriction. The tracked unit is set automatically from the aura.", 1, 1, 1, true},
        {" ", 1, 1, 1, true},
        {"With no auras listed, the entry tracks its own aura. Added aura IDs override that; for spell entries the entry's own aura is always kept as a fallback.", 1, 1, 1, true},
    }, infoButtons)
    heading.right:ClearAllPoints()
    heading.right:SetPoint("RIGHT", heading.frame, "RIGHT", -3, 0)
    heading.right:SetPoint("LEFT", auraInfoBtn, "RIGHT", 4, 0)

    if not isStandalone then
        local enable = AceGUI:Create("CheckBox")
        enable:SetLabel("Track an Aura")
        enable:SetValue(buttonData.auraTracking == true)
        enable:SetRelativeWidth(0.5)
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

    -- Bar fill mode (tracker C2): bar hosts can fill the aura bar by stack
    -- count instead of draining with time. Max stacks is automatic (game
    -- data); the status line below shows what resolved.
    if (group.displayMode or "icons") == "bars" then
        local stacksCb = AceGUI:Create("CheckBox")
        stacksCb:SetLabel("Bar Shows Stacks")
        stacksCb:SetValue(CooldownCompanion:IsBarPanelAuraStackDisplay(buttonData))
        stacksCb:SetRelativeWidth(0.5)
        stacksCb:SetCallback("OnValueChanged", function(_, _, value)
            CooldownCompanion:SetBarPanelAuraStackDisplay(buttonData, value)
            RefreshAuraConfig()
        end)
        scroll:AddChild(stacksCb)
        CreateInfoButton(stacksCb.frame, stacksCb.checkbg, "LEFT", "RIGHT", stacksCb.text:GetStringWidth() + 4, 0, {
            "Bar Shows Stacks",
            {"The bar shows the stack count instead of draining with time. Blizzard drives the fill and the maximum comes from the game's spell data — nothing to configure.", 1, 1, 1, true},
            {" ", 1, 1, 1, true},
            {"Stack Style picks the look: Segmented renders per-stack pieces — aura entries as individual bordered bars with real gaps, spell entries as a single bar with painted dividers (adjustable gap; the cooldown bar underneath needs a solid backdrop). Continuous is one plain bar that fills as stacks build.", 1, 1, 1, true},
            {" ", 1, 1, 1, true},
            {"If the tracked aura doesn't stack, the bar keeps the normal duration fill.", 1, 1, 1, true},
        }, infoButtons)

        if CooldownCompanion:IsBarPanelAuraStackDisplay(buttonData) then
            local maxStacks = CooldownCompanion:GetAuraStackBarMax(buttonData)
            local stackStyle = CooldownCompanion:GetBarPanelAuraStackDisplayMode(buttonData)

            -- Stack style (live parity): segmented per-stack rendering or a
            -- plain continuous fill. Live's stored style was wiped by the
            -- aura-rebuild migration, so this is a fresh 12.1 choice.
            if maxStacks then
                local styleDrop = AceGUI:Create("Dropdown")
                styleDrop:SetLabel("Stack Style")
                styleDrop:SetList({ segmented = "Segmented", continuous = "Continuous" },
                    { "segmented", "continuous" })
                styleDrop:SetValue(stackStyle)
                styleDrop:SetRelativeWidth(0.5)
                styleDrop:SetCallback("OnValueChanged", function(_, _, value)
                    CooldownCompanion:SetBarPanelAuraStackDisplayMode(buttonData, value)
                    CooldownCompanion:RequestAuraRebind("config")
                    RefreshAuraConfig()
                end)
                scroll:AddChild(styleDrop)
            end

            -- Painted-divider mode only: widget-mode blocks (aura entries)
            -- have the gap proportion baked into the bundled fill atlas.
            -- Hidden too when the aura doesn't stack (duration fallback —
            -- there are no segments for a gap to sit between) and for the
            -- continuous style (no segments at all).
            if not isStandalone and maxStacks and stackStyle == "segmented" then
                local gapSlider = AceGUI:Create("Slider")
                gapSlider:SetLabel("Segment Gap")
                gapSlider:SetSliderValues(0, 20, 1)
                gapSlider:SetValue(CooldownCompanion:GetBarPanelAuraSegmentGap(buttonData))
                gapSlider:SetRelativeWidth(0.5)
                gapSlider:SetCallback("OnValueChanged", function(_, _, value)
                    CooldownCompanion:SetBarPanelAuraSegmentGap(buttonData, value)
                    -- Rebind only: the gap is pure slot-kit styling, so no group
                    -- refresh and no panel rebuild (which would break the drag).
                    CooldownCompanion:RequestAuraRebind("config")
                end)
                scroll:AddChild(gapSlider)
            end

            local statusLabel = AceGUI:Create("Label")
            if maxStacks then
                statusLabel:SetText("|cffffd100Stack bar:|r full at " .. maxStacks .. " stacks")
            else
                statusLabel:SetText("|cffff9955This aura doesn't stack — the bar will show duration.|r")
            end
            statusLabel:SetFullWidth(true)
            scroll:AddChild(statusLabel)
        end
    end

    -- Display toggles. Standalone and passive entries always show the live
    -- aura icon (it exists to display the aura), so the opt-in only appears
    -- on ordinary spell entries.
    if not (isStandalone or buttonData.isPassive) then
        local iconCb = AceGUI:Create("CheckBox")
        iconCb:SetLabel("Show Aura Icon While Active")
        iconCb:SetValue(buttonData.auraShowAuraIcon == true)
        iconCb:SetRelativeWidth(0.5)
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
        invertCb:SetRelativeWidth(0.5)
        invertCb:SetCallback("OnValueChanged", function(_, _, value)
            buttonData.invertAuraDesaturationLogic = value and true or nil
            RefreshAuraConfig()
        end)
        scroll:AddChild(invertCb)

        local neverCb = AceGUI:Create("CheckBox")
        neverCb:SetLabel("Never Desaturate")
        neverCb:SetValue(buttonData.neverDesaturate == true)
        neverCb:SetRelativeWidth(0.5)
        neverCb:SetCallback("OnValueChanged", function(_, _, value)
            buttonData.neverDesaturate = value and true or nil
            RefreshAuraConfig()
        end)
        scroll:AddChild(neverCb)
    else
        local desatCb = AceGUI:Create("CheckBox")
        desatCb:SetLabel("Desaturate Icon While Aura Missing")
        desatCb:SetValue(buttonData.desaturateWhileAuraNotActive == true)
        desatCb:SetRelativeWidth(0.5)
        desatCb:SetCallback("OnValueChanged", function(_, _, value)
            buttonData.desaturateWhileAuraNotActive = value and true or nil
            RefreshAuraConfig()
        end)
        scroll:AddChild(desatCb)
    end

    -- Pandemic marker per-entry switch. The auto default follows the tracked
    -- unit (on for target debuffs, off for player buffs); only an explicit
    -- override is stored, so unchanged entries keep tracking the default.
    local pandemicDefault = unit == "target"
    local pandemicCb = AceGUI:Create("CheckBox")
    pandemicCb:SetLabel("Pandemic Marker")
    local pandemicValue = buttonData.pandemicMarker
    if pandemicValue == nil then pandemicValue = pandemicDefault end
    pandemicCb:SetValue(pandemicValue == true)
    pandemicCb:SetRelativeWidth(0.5)
    pandemicCb:SetCallback("OnValueChanged", function(_, _, value)
        if value == pandemicDefault then
            buttonData.pandemicMarker = nil
        else
            buttonData.pandemicMarker = value and true or false
        end
        RefreshAuraConfig()
    end)
    scroll:AddChild(pandemicCb)

    CreateInfoButton(pandemicCb.frame, pandemicCb.checkbg, "LEFT", "RIGHT", pandemicCb.text:GetStringWidth() + 4, 0, {
        "Pandemic Marker",
        {"Marks the aura duration text during the last 30% of the aura's duration — the refresh window where recasting extends the remaining time instead of wasting it. Blizzard evaluates the timing; the addon never reads combat values.", 1, 1, 1, true},
        {" ", 1, 1, 1, true},
        {"On by default for debuffs on your target, off by default for your own buffs. Marker text and color are in the group's Aura Duration Text settings.", 1, 1, 1, true},
    }, infoButtons)
end

ST._BuildAuraTab = BuildAuraTab
