--[[
    CooldownCompanion - Config/TalentPicker.lua: Visual talent tree picker
    rendered inside the existing config panel columns (col1 = class, col3 = spec).
    Supports multi-condition 3-way toggle (taken / not taken / clear) with Accept to commit.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local AceGUI = LibStub("AceGUI-3.0")

local ipairs = ipairs
local pairs = pairs
local tostring = tostring
local wipe = wipe
local math_min = math.min
local math_max = math.max
local math_floor = math.floor

------------------------------------------------------------------------
-- CONSTANTS
------------------------------------------------------------------------
local NODE_SIZE = 32
local NODE_PADDING = 16
local CHOICE_ICON_SIZE = 22
local CHOICE_ICON_GAP = 2
local HERO_GUTTER_WIDTH = 132
local HERO_HEADER_HEIGHT = 36
local SPEC_CONTROL_ROW_HEIGHT = 36
local SPEC_DROPDOWN_WIDTH = 150
local HERO_DROPDOWN_WIDTH = HERO_GUTTER_WIDTH - 4
local EMPTY_DROPDOWN_VALUE = 0

local DEFAULT_BORDER_SIZE = 0
local CONDITION_BORDER_SIZE = 3

local EDGE_THICKNESS = 1.4

local BTN_ROW_HEIGHT = 30
local VIEW_TRAIT_CONFIG_ID = (Constants and Constants.TraitConsts and Constants.TraitConsts.VIEW_TRAIT_CONFIG_ID) or -3

-- Colors
local COLOR_BORDER_PENDING_TAKEN   = { 0.3, 0.7, 1.0, 1 }
local COLOR_BORDER_PENDING_NOTTAKEN = { 1.0, 0.3, 0.3, 1 }
local COLOR_BORDER_DEFAULT         = { 0.55, 0.55, 0.55, 0.9 }
local COLOR_EDGE                    = { 0.7, 0.62, 0.2, 0.75 }

------------------------------------------------------------------------
-- STATE
------------------------------------------------------------------------
local classTreeFrame = nil
local heroTreeFrame = nil
local specTreeFrame = nil
local specEmptyText = nil
local backBtn = nil
local clearBtn = nil
local acceptBtn = nil
local specDropdown = nil
local heroDropdown = nil
local nodeButtons = {}
local choiceButtons = {}
local classEdgeLines = {}
local heroEdgeLines = {}
local specEdgeLines = {}
local onAcceptCallback = nil
local savedCol1Title = nil
local savedCol3Title = nil
local savedPanelTitle = nil
local isRestoring = false
local isUpdatingPickerDropdowns = false

local pickerGroup = nil
local pickerSelectedSpecID = nil
local pickerSelectedConfigID = nil
local pickerSelectedHeroSubTreeID = nil

-- Pending conditions: key = "nodeID" or "nodeID:entryID" → condition table
local pendingConditions = {}

------------------------------------------------------------------------
-- PENDING STATE HELPERS
------------------------------------------------------------------------
local function GetSpecDisplayName(specID)
    if not specID then
        return nil
    end

    local _, name = GetSpecializationInfoForSpecID(specID)
    return name or ("Spec " .. specID)
end

local function GetClassDisplayInfo()
    local className, _, classID = UnitClass("player")
    if not classID then
        return nil, nil
    end

    return classID, className or ("Class " .. classID)
end

local function GetHeroDisplayName(configID, subTreeID)
    if not subTreeID then
        return nil
    end

    local subTreeInfo = configID and C_Traits.GetSubTreeInfo(configID, subTreeID) or nil
    return (subTreeInfo and subTreeInfo.name) or ("Hero " .. subTreeID)
end

local function BuildConditionContext(scopeType, heroSubTreeID)
    if scopeType == "class" then
        local classID, className = GetClassDisplayInfo()
        if not classID then
            return nil
        end

        return {
            classID = classID,
            className = className,
        }
    end

    local specID = pickerSelectedSpecID
    if not specID then
        return nil
    end

    return {
        specID = specID,
        specName = GetSpecDisplayName(specID),
        heroSubTreeID = heroSubTreeID,
        heroName = heroSubTreeID and GetHeroDisplayName(pickerSelectedConfigID, heroSubTreeID) or nil,
    }
end

local function ClearConflictingPendingScopes(specID, heroSubTreeID)
    for key, cond in pairs(pendingConditions) do
        if cond.classID or cond.className then
            -- Class-tree conditions are valid across specs.
        elseif cond.specID and cond.specID ~= specID then
            pendingConditions[key] = nil
        elseif heroSubTreeID and cond.heroSubTreeID and cond.heroSubTreeID ~= heroSubTreeID then
            pendingConditions[key] = nil
        end
    end
end

local function GetPreferredPendingScope(source)
    local ordered = source
    if type(ordered) ~= "table" then
        ordered = pendingConditions
    end

    for _, cond in ipairs(ordered) do
        if cond.specID then
            return cond.specID, cond.heroSubTreeID
        end
    end

    if ordered == pendingConditions then
        for _, cond in pairs(pendingConditions) do
            if cond.specID then
                return cond.specID, cond.heroSubTreeID
            end
        end
    end

    return nil, nil
end

local function FillPendingConditionContext()
    local specID = pickerSelectedSpecID
    local specName = GetSpecDisplayName(specID)
    local classID, className = GetClassDisplayInfo()

    for _, cond in pairs(pendingConditions) do
        if cond.classID or cond.className then
            cond.classID = cond.classID or classID
            cond.className = cond.className or className
            cond.specID = nil
            cond.specName = nil
            cond.heroSubTreeID = nil
            cond.heroName = nil
        elseif specID and not cond.specID then
            cond.specID = specID
            cond.specName = specName
        elseif cond.specID and not cond.specName then
            cond.specName = GetSpecDisplayName(cond.specID)
        end

        if cond.className and not cond.classID then
            cond.classID = classID
        end

        if cond.heroSubTreeID and not cond.heroName then
            cond.heroName = GetHeroDisplayName(pickerSelectedConfigID, cond.heroSubTreeID)
        end
    end
end

local function PendingKey(nodeID, entryID)
    if entryID then
        return tostring(nodeID) .. ":" .. tostring(entryID)
    end
    return tostring(nodeID)
end

local function GetPendingState(nodeID, entryID)
    return pendingConditions[PendingKey(nodeID, entryID)]
end

local function ClearPendingStateForNode(nodeID)
    local directKey = tostring(nodeID)
    pendingConditions[directKey] = nil

    local prefix = directKey .. ":"
    for key in pairs(pendingConditions) do
        if key:sub(1, #prefix) == prefix then
            pendingConditions[key] = nil
        end
    end
end

local function SetPendingState(nodeID, entryID, spellID, name, show, context)
    local key = PendingKey(nodeID, entryID)
    if show then
        pendingConditions[key] = {
            nodeID  = nodeID,
            entryID = entryID,
            spellID = spellID,
            name    = name,
            show    = show,
            classID = context and context.classID or nil,
            className = context and context.className or nil,
            specID = context and context.specID or nil,
            specName = context and context.specName or nil,
            heroSubTreeID = context and context.heroSubTreeID or nil,
            heroName = context and context.heroName or nil,
        }
    else
        pendingConditions[key] = nil
    end
end

local function CyclePendingState(nodeID, entryID, spellID, name, context)
    local existing = GetPendingState(nodeID, entryID)
    local isHeroSpecProxy = entryID == nil
        and context
        and context.heroSubTreeID ~= nil
        and type(name) == "string"
        and type(context.heroName) == "string"
        and name == context.heroName

    if not existing then
        if context and context.specID then
            ClearConflictingPendingScopes(context.specID, context.heroSubTreeID)
        end
        SetPendingState(nodeID, entryID, spellID, name, "taken", context)
    elseif existing.show == "taken" then
        if context and context.specID then
            ClearConflictingPendingScopes(context.specID, context.heroSubTreeID)
        end
        SetPendingState(nodeID, entryID, spellID, name, "not_taken", context)
        if isHeroSpecProxy then
            for key, cond in pairs(pendingConditions) do
                if cond.heroSubTreeID == context.heroSubTreeID
                    and not (cond.nodeID ~= nil
                        and cond.entryID == nil
                        and type(cond.name) == "string"
                        and type(cond.heroName) == "string"
                        and cond.name == cond.heroName)
                    and cond.nodeID ~= nodeID then
                    pendingConditions[key] = nil
                end
            end
        end
    else
        -- not_taken → clear
        SetPendingState(nodeID, entryID, nil, nil, nil)
    end
end

local function CycleChoicePendingState(nodeID, entryID, spellID, name, context)
    local existing = GetPendingState(nodeID, entryID)
    local nextShow
    if not existing then
        nextShow = "taken"
    elseif existing.show == "taken" then
        nextShow = "not_taken"
    end

    ClearPendingStateForNode(nodeID)
    if nextShow then
        if context and context.specID then
            ClearConflictingPendingScopes(context.specID, context.heroSubTreeID)
        end
        SetPendingState(nodeID, entryID, spellID, name, nextShow, context)
    end
end

-- Check if any entry of a given nodeID has a pending condition (for choice node parents)
local function GetPendingStateForNode(nodeID)
    -- Check direct node key first (non-choice nodes)
    local direct = pendingConditions[tostring(nodeID)]
    if direct then return direct end

    -- Check all entry keys for this node
    local prefix = tostring(nodeID) .. ":"
    for key, cond in pairs(pendingConditions) do
        if key:sub(1, #prefix) == prefix then
            return cond
        end
    end
    return nil
end

------------------------------------------------------------------------
-- HELPERS
------------------------------------------------------------------------
local function SetBorderColor(tex, color)
    tex:SetColorTexture(color[1], color[2], color[3], color[4])
end

local function SetNodeBorderThickness(btn, thickness)
    btn.borders[1]:SetHeight(thickness)
    btn.borders[2]:SetHeight(thickness)
    btn.borders[3]:SetWidth(thickness)
    btn.borders[4]:SetWidth(thickness)
    btn.icon:ClearAllPoints()
    btn.icon:SetPoint("TOPLEFT", thickness, -thickness)
    btn.icon:SetPoint("BOTTOMRIGHT", -thickness, thickness)
end

local function SetNodeBorderColor(btn, color)
    for _, border in ipairs(btn.borders) do
        SetBorderColor(border, color)
    end
end

local function GetConditionState(nodeID, entryID)
    if entryID then
        return GetPendingState(nodeID, entryID)
    end
    return GetPendingStateForNode(nodeID)
end

local function IsHeroSpecProxyCondition(cond)
    return type(cond) == "table"
        and cond.nodeID ~= nil
        and cond.heroSubTreeID ~= nil
        and cond.entryID == nil
        and type(cond.name) == "string"
        and type(cond.heroName) == "string"
        and cond.name == cond.heroName
end

local function IsHeroSpecProxyNodeDisabled(nodeID)
    local pending = GetPendingStateForNode(nodeID)
    return pending and pending.show == "not_taken" and IsHeroSpecProxyCondition(pending)
end

local function AddPendingTooltipLine(pending, isChoiceNode)
    if not pending then return end

    local r, g, b = 0.3, 0.7, 1.0
    if pending.show == "not_taken" then
        r, g, b = 1.0, 0.3, 0.3
    end

    local line
    if isChoiceNode and pending.name then
        if pending.show == "not_taken" then
            line = "Condition: Show when " .. pending.name .. " is NOT taken"
        else
            line = "Condition: Show when " .. pending.name .. " is taken"
        end
    elseif pending.show == "not_taken" then
        line = "Condition: Show when NOT taken"
    else
        line = "Condition: Show when taken"
    end

    GameTooltip:AddLine(line, r, g, b, true)
end

-- Determine border presentation from condition state only.
local function GetNodeBorderStyle(nodeID, entryID)
    local pending = GetConditionState(nodeID, entryID)
    if not pending then
        return COLOR_BORDER_DEFAULT, DEFAULT_BORDER_SIZE
    end

    if pending.show == "taken" then
        return COLOR_BORDER_PENDING_TAKEN, CONDITION_BORDER_SIZE
    end

    return COLOR_BORDER_PENDING_NOTTAKEN, CONDITION_BORDER_SIZE
end

------------------------------------------------------------------------
-- REFRESH PICKER BORDERS
------------------------------------------------------------------------
local RefreshPickerBorders

local function CreateNodeButton(parent, index)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(NODE_SIZE, NODE_SIZE)
    btn:RegisterForClicks("AnyUp")

    -- Icon
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("TOPLEFT", DEFAULT_BORDER_SIZE, -DEFAULT_BORDER_SIZE)
    btn.icon:SetPoint("BOTTOMRIGHT", -DEFAULT_BORDER_SIZE, DEFAULT_BORDER_SIZE)
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Border (4 edge textures)
    btn.borders = {}
    local bSize = DEFAULT_BORDER_SIZE
    local b
    b = btn:CreateTexture(nil, "BORDER"); b:SetPoint("TOPLEFT", 0, 0); b:SetPoint("TOPRIGHT", 0, 0); b:SetHeight(bSize)
    btn.borders[1] = b
    b = btn:CreateTexture(nil, "BORDER"); b:SetPoint("BOTTOMLEFT", 0, 0); b:SetPoint("BOTTOMRIGHT", 0, 0); b:SetHeight(bSize)
    btn.borders[2] = b
    b = btn:CreateTexture(nil, "BORDER"); b:SetPoint("TOPLEFT", 0, 0); b:SetPoint("BOTTOMLEFT", 0, 0); b:SetWidth(bSize)
    btn.borders[3] = b
    b = btn:CreateTexture(nil, "BORDER"); b:SetPoint("TOPRIGHT", 0, 0); b:SetPoint("BOTTOMRIGHT", 0, 0); b:SetWidth(bSize)
    btn.borders[4] = b

    -- Highlight
    btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.highlight:SetAllPoints()
    btn.highlight:SetColorTexture(1, 1, 1, 0.15)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self._spellID then
            GameTooltip:SetSpellByID(self._spellID)
        elseif self._talentName then
            GameTooltip:AddLine(self._talentName, 1, 1, 1)
        end
        -- Pending state info
        local pending = self._entryID
            and GetPendingState(self._nodeID, self._entryID)
            or  GetPendingStateForNode(self._nodeID)
        AddPendingTooltipLine(pending, self._isChoiceNode)
        if self._disabledReason then
            GameTooltip:AddLine(self._disabledReason, 1, 0.82, 0.2, true)
        elseif self._isChoiceNode then
            GameTooltip:AddLine("Left-click to show or hide choices", 0.5, 0.8, 1)
        else
            GameTooltip:AddLine("Click to cycle condition", 0.5, 0.8, 1)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return btn
end

local function CreateChoiceButton(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(CHOICE_ICON_SIZE, CHOICE_ICON_SIZE)
    btn:RegisterForClicks("AnyUp")

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("TOPLEFT", DEFAULT_BORDER_SIZE, -DEFAULT_BORDER_SIZE)
    btn.icon:SetPoint("BOTTOMRIGHT", -DEFAULT_BORDER_SIZE, DEFAULT_BORDER_SIZE)
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    btn.borders = {}
    local bSize = DEFAULT_BORDER_SIZE
    local b
    b = btn:CreateTexture(nil, "BORDER"); b:SetPoint("TOPLEFT", 0, 0); b:SetPoint("TOPRIGHT", 0, 0); b:SetHeight(bSize)
    btn.borders[1] = b
    b = btn:CreateTexture(nil, "BORDER"); b:SetPoint("BOTTOMLEFT", 0, 0); b:SetPoint("BOTTOMRIGHT", 0, 0); b:SetHeight(bSize)
    btn.borders[2] = b
    b = btn:CreateTexture(nil, "BORDER"); b:SetPoint("TOPLEFT", 0, 0); b:SetPoint("BOTTOMLEFT", 0, 0); b:SetWidth(bSize)
    btn.borders[3] = b
    b = btn:CreateTexture(nil, "BORDER"); b:SetPoint("TOPRIGHT", 0, 0); b:SetPoint("BOTTOMRIGHT", 0, 0); b:SetWidth(bSize)
    btn.borders[4] = b

    btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.highlight:SetAllPoints()
    btn.highlight:SetColorTexture(1, 1, 1, 0.15)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self._spellID then
            GameTooltip:SetSpellByID(self._spellID)
        elseif self._talentName then
            GameTooltip:AddLine(self._talentName, 1, 1, 1)
        end
        -- Pending state info
        if self._nodeID then
            local pending = GetPendingState(self._nodeID, self._entryID)
            AddPendingTooltipLine(pending, true)
        end
        if self._disabledReason then
            GameTooltip:AddLine(self._disabledReason, 1, 0.82, 0.2, true)
        else
            GameTooltip:AddLine("Click to cycle a specific choice", 0.5, 0.8, 1)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return btn
end

------------------------------------------------------------------------
-- CHOICE SUBMENU (floating frame, parented to configFrame.frame)
------------------------------------------------------------------------
local choiceFrame = nil

local function HideChoiceFrame()
    if choiceFrame then
        choiceFrame._nodeID = nil
        choiceFrame._scopeType = nil
        choiceFrame._heroSubTreeID = nil
        choiceFrame:Hide()
    end
end

-- Forward declarations
local HideTalentPicker
local PopulateTree
local RefreshPickerDropdowns

local function EnsurePickerViewConfig(specID)
    if not specID then
        return nil
    end

    local playerLevel = UnitLevel("player")
    if not playerLevel or playerLevel < 1 then
        return nil
    end

    C_ClassTalents.InitializeViewLoadout(specID, playerLevel)
    if C_Traits.GetConfigInfo(VIEW_TRAIT_CONFIG_ID) then
        return VIEW_TRAIT_CONFIG_ID
    end

    return nil
end

local function BuildSpecDropdownOptions(group)
    local effectiveSpecs = group and CooldownCompanion:GetEffectiveSpecs(group) or nil
    local hasSpecFilter = effectiveSpecs and next(effectiveSpecs) ~= nil
    local values = {}
    local order = {}

    for i = 1, (GetNumSpecializations() or 0) do
        local specID, name = GetSpecializationInfo(i)
        if specID and name and (not hasSpecFilter or effectiveSpecs[specID]) then
            values[specID] = name
            order[#order + 1] = specID
        end
    end

    return values, order
end

local function BuildHeroDropdownOptions(configID, specID, group)
    if not specID then
        return {}, {}, nil
    end

    local effectiveHeroTalents = group and CooldownCompanion:GetEffectiveHeroTalents(group) or nil
    local hasHeroFilter = effectiveHeroTalents and next(effectiveHeroTalents) ~= nil
    local values = {}
    local order = {}
    local preferredSubTreeID = nil
    local subTreeIDs = configID and C_ClassTalents.GetHeroTalentSpecsForClassSpec(configID, specID) or nil

    if not subTreeIDs or #subTreeIDs == 0 then
        subTreeIDs = C_ClassTalents.GetHeroTalentSpecsForClassSpec(nil, specID)
    end

    if not subTreeIDs or #subTreeIDs == 0 then
        return values, order, preferredSubTreeID
    end

    for _, subTreeID in ipairs(subTreeIDs) do
        if not hasHeroFilter or effectiveHeroTalents[subTreeID] then
            local subTreeInfo = configID and C_Traits.GetSubTreeInfo(configID, subTreeID) or nil
            values[subTreeID] = (subTreeInfo and subTreeInfo.name) or ("Hero " .. subTreeID)
            order[#order + 1] = subTreeID

            if not preferredSubTreeID then
                preferredSubTreeID = subTreeID
            end
        end
    end

    return values, order, preferredSubTreeID
end

local function SetPickerDropdownOptions(dropdown, values, order, selectedValue, disabled, emptyText)
    if not dropdown then
        return
    end

    isUpdatingPickerDropdowns = true
    if order and #order > 0 then
        dropdown:SetList(values, order)
        dropdown:SetValue(selectedValue)
    else
        dropdown:SetList({ [EMPTY_DROPDOWN_VALUE] = emptyText }, { EMPTY_DROPDOWN_VALUE })
        dropdown:SetValue(EMPTY_DROPDOWN_VALUE)
    end
    dropdown:SetDisabled(disabled)
    isUpdatingPickerDropdowns = false
end

RefreshPickerDropdowns = function(forceSpecReset, forceHeroReset)
    local specValues, specOrder = BuildSpecDropdownOptions(pickerGroup)
    local currentSpecID = pickerSelectedSpecID

    if forceSpecReset or not currentSpecID or not specValues[currentSpecID] then
        local activeSpecID = CooldownCompanion._currentSpecId
        if activeSpecID and specValues[activeSpecID] then
            currentSpecID = activeSpecID
        else
            currentSpecID = specOrder[1]
        end
        forceHeroReset = true
    end

    pickerSelectedSpecID = currentSpecID
    pickerSelectedConfigID = EnsurePickerViewConfig(currentSpecID)

    SetPickerDropdownOptions(
        specDropdown,
        specValues,
        specOrder,
        currentSpecID,
        #specOrder <= 1,
        "No allowed specs"
    )

    if not currentSpecID then
        pickerSelectedHeroSubTreeID = nil
        if heroDropdown then
            heroDropdown.frame:Hide()
        end
        return
    end

    local heroValues, heroOrder, preferredSubTreeID = BuildHeroDropdownOptions(pickerSelectedConfigID, currentSpecID, pickerGroup)
    local currentHeroSubTreeID = pickerSelectedHeroSubTreeID

    if forceHeroReset or not currentHeroSubTreeID or not heroValues[currentHeroSubTreeID] then
        if preferredSubTreeID and heroValues[preferredSubTreeID] then
            currentHeroSubTreeID = preferredSubTreeID
        else
            currentHeroSubTreeID = heroOrder[1]
        end
    end

    pickerSelectedHeroSubTreeID = currentHeroSubTreeID
    if heroDropdown then
        heroDropdown.frame:Show()
    end
    SetPickerDropdownOptions(
        heroDropdown,
        heroValues,
        heroOrder,
        currentHeroSubTreeID,
        #heroOrder <= 1,
        "No allowed hero talents"
    )
end

local function GetChoiceFrameLevel(parentBtn)
    local level = 0
    local configFrame = CS.configFrame

    if configFrame and configFrame.frame then
        level = math_max(level, configFrame.frame:GetFrameLevel() or 0)
        if configFrame.col1 and configFrame.col1.frame then
            level = math_max(level, configFrame.col1.frame:GetFrameLevel() or 0)
        end
        if configFrame.col3 and configFrame.col3.frame then
            level = math_max(level, configFrame.col3.frame:GetFrameLevel() or 0)
        end
    end

    if classTreeFrame then
        level = math_max(level, classTreeFrame:GetFrameLevel() or 0)
    end
    if heroTreeFrame then
        level = math_max(level, heroTreeFrame:GetFrameLevel() or 0)
    end
    if specTreeFrame then
        level = math_max(level, specTreeFrame:GetFrameLevel() or 0)
    end
    if parentBtn then
        level = math_max(level, parentBtn:GetFrameLevel() or 0)
    end

    return level + 20
end

local function ShowChoiceFrame(parentBtn, entries, nodeID, scopeType, heroSubTreeID)
    local configFrame = CS.configFrame
    if not configFrame then return end

    if not choiceFrame then
        choiceFrame = CreateFrame("Frame", nil, configFrame.frame, "BackdropTemplate")
        choiceFrame:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
        })
        choiceFrame:SetBackdropColor(0.12, 0.12, 0.18, 0.98)
        choiceFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        choiceFrame:SetToplevel(true)
    end

    choiceFrame:SetParent(configFrame.frame)
    choiceFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    choiceFrame:SetFrameLevel(GetChoiceFrameLevel(parentBtn))

    -- Hide previous choice buttons
    for _, cb in ipairs(choiceButtons) do
        cb:Hide()
    end

    local count = #entries
    local totalWidth = count * CHOICE_ICON_SIZE + (count - 1) * CHOICE_ICON_GAP + 12
    choiceFrame:SetSize(totalWidth, CHOICE_ICON_SIZE + 10)
    choiceFrame:ClearAllPoints()
    choiceFrame:SetPoint("TOP", parentBtn, "BOTTOM", 0, -4)
    choiceFrame._nodeID = nodeID
    choiceFrame._scopeType = scopeType
    choiceFrame._heroSubTreeID = heroSubTreeID
    choiceFrame:Show()
    choiceFrame:Raise()

    for i, entry in ipairs(entries) do
        local cb = choiceButtons[i]
        if not cb then
            cb = CreateChoiceButton(choiceFrame)
            choiceButtons[i] = cb
        end

        cb:SetParent(choiceFrame)
        cb:SetFrameStrata(choiceFrame:GetFrameStrata())
        cb:SetFrameLevel(choiceFrame:GetFrameLevel() + 1)
        cb:ClearAllPoints()
        cb:SetPoint("LEFT", choiceFrame, "LEFT", 6 + (i - 1) * (CHOICE_ICON_SIZE + CHOICE_ICON_GAP), 0)
        cb:Show()
        cb:Raise()

        cb.icon:SetTexture(entry.icon)
        cb.icon:SetDesaturated(false)
        cb.icon:SetVertexColor(1, 1, 1)

        -- Store identity for pending state lookups
        cb._nodeID = nodeID
        cb._entryID = entry.entryID
        cb._talentName = entry.name
        cb._spellID = entry.spellID

        local borderColor, borderSize = GetNodeBorderStyle(nodeID, entry.entryID)
        SetNodeBorderThickness(cb, borderSize)
        SetNodeBorderColor(cb, borderColor)

        cb:SetScript("OnClick", function(_, mouseButton)
            if mouseButton and mouseButton ~= "LeftButton" then return end
            CycleChoicePendingState(nodeID, entry.entryID, entry.spellID, entry.name, BuildConditionContext(choiceFrame._scopeType, choiceFrame._heroSubTreeID))
            RefreshPickerBorders()
        end)
    end
end

local function ToggleChoiceFrame(parentBtn, entries, nodeID, scopeType, heroSubTreeID)
    if choiceFrame and choiceFrame:IsShown() and choiceFrame._nodeID == nodeID then
        HideChoiceFrame()
        return
    end
    ShowChoiceFrame(parentBtn, entries, nodeID, scopeType, heroSubTreeID)
end

------------------------------------------------------------------------
-- TREE FRAME CREATION (lazy, created once, reused)
------------------------------------------------------------------------
local function EnsureTreeFrames()
    local configFrame = CS.configFrame
    if not configFrame then return end
    if not classTreeFrame then
        classTreeFrame = CreateFrame("Frame", nil, configFrame.col1.content)
    end
    if not heroTreeFrame then
        heroTreeFrame = CreateFrame("Frame", nil, configFrame.col3.content)
    end
    if not specTreeFrame then
        specTreeFrame = CreateFrame("Frame", nil, configFrame.col3.content)
    end
    if not specDropdown then
        specDropdown = AceGUI:Create("Dropdown")
        specDropdown:SetWidth(SPEC_DROPDOWN_WIDTH)
        specDropdown:SetCallback("OnValueChanged", function(_, _, value)
            if isUpdatingPickerDropdowns or type(value) ~= "number" or value == EMPTY_DROPDOWN_VALUE then
                return
            end
            pickerSelectedSpecID = value
            pickerSelectedConfigID = nil
            pickerSelectedHeroSubTreeID = nil
            RefreshPickerDropdowns(false, true)
            PopulateTree()
        end)
    end
    if not heroDropdown then
        heroDropdown = AceGUI:Create("Dropdown")
        heroDropdown:SetWidth(HERO_DROPDOWN_WIDTH)
        heroDropdown:SetCallback("OnValueChanged", function(_, _, value)
            if isUpdatingPickerDropdowns or type(value) ~= "number" or value == EMPTY_DROPDOWN_VALUE then
                return
            end
            pickerSelectedHeroSubTreeID = value
            PopulateTree()
        end)
    end
end

local function LayoutSpecFrames(col3Content, showHeroFrame)
    if specDropdown then
        specDropdown.frame:SetParent(col3Content)
        specDropdown.frame:ClearAllPoints()
        specDropdown.frame:SetPoint("TOPRIGHT", col3Content, "TOPRIGHT", 0, 0)
        specDropdown.frame:Show()
    end

    if showHeroFrame and heroTreeFrame then
        heroTreeFrame:SetParent(col3Content)
        heroTreeFrame:ClearAllPoints()
        heroTreeFrame:SetPoint("TOPLEFT", col3Content, "TOPLEFT", 0, 0)
        heroTreeFrame:SetPoint("BOTTOMLEFT", col3Content, "BOTTOMLEFT", 0, 0)
        heroTreeFrame:SetWidth(HERO_GUTTER_WIDTH)
        heroTreeFrame:SetFrameStrata(specTreeFrame:GetFrameStrata())
        heroTreeFrame:SetFrameLevel((specTreeFrame:GetFrameLevel() or 0) + 10)
        heroTreeFrame:Show()
        if heroDropdown then
            heroDropdown.frame:SetParent(heroTreeFrame)
            heroDropdown.frame:ClearAllPoints()
            heroDropdown.frame:SetPoint("TOPLEFT", heroTreeFrame, "TOPLEFT", 0, 0)
            heroDropdown.frame:Show()
        end
    else
        if heroTreeFrame then
            heroTreeFrame:Hide()
        end
        if heroDropdown then
            heroDropdown.frame:Hide()
        end

    end

    specTreeFrame:ClearAllPoints()
    specTreeFrame:SetPoint("TOPLEFT", col3Content, "TOPLEFT", 0, 0)
    specTreeFrame:SetPoint("BOTTOMRIGHT", col3Content, "BOTTOMRIGHT", 0, 0)
end

------------------------------------------------------------------------
-- BACK + CLEAR + ACCEPT BUTTONS (lazy, created once)
------------------------------------------------------------------------
local function EnsureButtons()
    if not backBtn then
        backBtn = AceGUI:Create("Button")
        backBtn:SetText("Back")
        backBtn:SetWidth(80)
        backBtn:SetCallback("OnClick", function()
            HideTalentPicker()
        end)
    end

    if not clearBtn then
        clearBtn = AceGUI:Create("Button")
        clearBtn:SetText("Clear")
        clearBtn:SetWidth(80)
        clearBtn:SetCallback("OnClick", function()
            wipe(pendingConditions)
            HideChoiceFrame()
            PopulateTree()
        end)
    end

    if not acceptBtn then
        acceptBtn = AceGUI:Create("Button")
        acceptBtn:SetText("Accept")
        acceptBtn:SetWidth(160)
        acceptBtn:SetCallback("OnClick", function()
            local results = nil
            local count = 0
            for _ in pairs(pendingConditions) do count = count + 1 end
            if count > 0 then
                results = {}
                for _, cond in pairs(pendingConditions) do
                    results[#results + 1] = {
                        nodeID  = cond.nodeID,
                        entryID = cond.entryID,
                        spellID = cond.spellID,
                        name    = cond.name,
                        show    = cond.show,
                        classID = cond.classID,
                        className = cond.className,
                        specID = cond.specID,
                        specName = cond.specName,
                        heroSubTreeID = cond.heroSubTreeID,
                        heroName = cond.heroName,
                    }
                end
                local normalized, changed = CooldownCompanion:NormalizeTalentConditions(results)
                if changed then
                    results = normalized
                end
            end
            local cb = onAcceptCallback
            HideTalentPicker()
            if cb then
                cb(results)
            end
        end)
    end
end

------------------------------------------------------------------------
-- SHOW / HIDE TALENT PICKER
------------------------------------------------------------------------
local function ShowTalentPicker(configFrame, initialConditions, group)
    CS.talentPickerMode = true
    pickerGroup = group
    pickerSelectedSpecID = nil
    pickerSelectedConfigID = nil
    pickerSelectedHeroSubTreeID = nil

    local col1 = configFrame.col1
    local col2 = configFrame.col2
    local col3 = configFrame.col3
    local col4 = configFrame.col4

    -- Save titles
    savedCol1Title = col1.titletext:GetText()
    savedCol3Title = col3.titletext:GetText()
    savedPanelTitle = configFrame.titletext:GetText()

    -- Change titles
    col1:SetTitle("Class")
    col3:SetTitle("Spec")
    configFrame:SetTitle("Pick Talent Conditions")

    -- Hide col2 + col4
    col2.frame:Hide()
    col4.frame:Hide()

    -- Hide col1 normal content
    CS.col1Scroll.frame:Hide()
    CS.col1ButtonBar:Hide()
    if col1._barsPanelTabGroup then col1._barsPanelTabGroup.frame:Hide() end

    -- Hide col3 normal content (all possible states)
    if col3.bsTabGroup then col3.bsTabGroup.frame:Hide() end
    if col3.bsPlaceholder then col3.bsPlaceholder:Hide() end
    if col3._customAuraTabGroup then col3._customAuraTabGroup.frame:Hide() end
    if col3._autoAddScroll then col3._autoAddScroll.frame:Hide() end
    if col3.multiSelectScroll then col3.multiSelectScroll.frame:Hide() end

    -- Recompute column layout (2-column mode)
    configFrame.LayoutColumns()

    -- Hide panel elements
    configFrame.modeStatusRow:Hide()
    if configFrame.profileBar:IsShown() then
        configFrame.profileBar:Hide()
    end

    -- Hide column info buttons during talent picker
    if CS.columnInfoButtons[1] then CS.columnInfoButtons[1]:Hide() end
    if CS.columnInfoButtons[3] then CS.columnInfoButtons[3]:Hide() end

    -- Initialize pending conditions from initial conditions
    wipe(pendingConditions)
    local source = nil
    if initialConditions then
        source = initialConditions
        local normalized, changed = CooldownCompanion:NormalizeTalentConditions(initialConditions)
        if changed then
            source = normalized
        end
        for _, cond in ipairs(source or {}) do
            local key = PendingKey(cond.nodeID, cond.entryID)
            pendingConditions[key] = {
                nodeID  = cond.nodeID,
                entryID = cond.entryID,
                spellID = cond.spellID,
                name    = cond.name,
                show    = cond.show,
                classID = cond.classID,
                className = cond.className,
                specID = cond.specID,
                specName = cond.specName,
                heroSubTreeID = cond.heroSubTreeID,
                heroName = cond.heroName,
            }
        end
    end

    local preferredSpecID, preferredHeroSubTreeID = GetPreferredPendingScope(source)
    if preferredSpecID then
        pickerSelectedSpecID = preferredSpecID
        pickerSelectedHeroSubTreeID = preferredHeroSubTreeID
    end

    -- Create/show tree frames + buttons
    EnsureTreeFrames()
    EnsureButtons()

    -- Parent tree frames to correct content areas
    classTreeFrame:SetParent(col1.content)
    if heroTreeFrame then
        heroTreeFrame:SetParent(col3.content)
    end
    specTreeFrame:SetParent(col3.content)
    if specDropdown then
        specDropdown.frame:SetParent(col3.content)
    end
    if heroDropdown then
        heroDropdown.frame:SetParent(heroTreeFrame or col3.content)
    end

    -- Position AceGUI buttons in col1.content
    backBtn.frame:SetParent(col1.content)
    backBtn.frame:ClearAllPoints()
    backBtn.frame:SetPoint("TOPLEFT", col1.content, "TOPLEFT", 0, 0)
    backBtn.frame:Show()

    clearBtn.frame:SetParent(col1.content)
    clearBtn.frame:ClearAllPoints()
    clearBtn.frame:SetPoint("LEFT", backBtn.frame, "RIGHT", 4, 0)
    clearBtn.frame:Show()

    -- Position class tree below buttons
    classTreeFrame:ClearAllPoints()
    classTreeFrame:SetPoint("TOPLEFT", col1.content, "TOPLEFT", 0, -BTN_ROW_HEIGHT)
    classTreeFrame:SetPoint("BOTTOMRIGHT", col1.content, "BOTTOMRIGHT", 0, 0)
    classTreeFrame:Show()

    -- Position spec content; hero gutter is enabled during PopulateTree when needed
    RefreshPickerDropdowns(true, true)
    FillPendingConditionContext()
    LayoutSpecFrames(col3.content, pickerSelectedSpecID ~= nil)
    specTreeFrame:Show()

    -- Position accept button at bottom center of main panel (where modeStatusRow normally sits)
    acceptBtn.frame:SetParent(configFrame.frame)
    acceptBtn.frame:ClearAllPoints()
    acceptBtn.frame:SetPoint("BOTTOM", configFrame.frame, "BOTTOM", 0, 21)
    acceptBtn.frame:Show()

    -- Populate talent trees
    PopulateTree()
end

HideTalentPicker = function()
    if isRestoring then return end
    isRestoring = true

    local configFrame = CS.configFrame
    CS.talentPickerMode = false

    -- Hide talent content
    if classTreeFrame then classTreeFrame:Hide() end
    if heroTreeFrame then heroTreeFrame:Hide() end
    if specTreeFrame then specTreeFrame:Hide() end
    if specEmptyText then specEmptyText:Hide() end
    if specDropdown then specDropdown.frame:Hide() end
    if heroDropdown then heroDropdown.frame:Hide() end
    if backBtn then backBtn.frame:Hide() end
    if clearBtn then clearBtn.frame:Hide() end
    if acceptBtn then acceptBtn.frame:Hide() end
    HideChoiceFrame()

    -- Hide all node buttons and edges
    for _, btn in ipairs(nodeButtons) do btn:Hide() end
    for _, cb in ipairs(choiceButtons) do cb:Hide() end
    for _, line in ipairs(classEdgeLines) do line:Hide() end
    for _, line in ipairs(heroEdgeLines) do line:Hide() end
    for _, line in ipairs(specEdgeLines) do line:Hide() end

    if configFrame then
        -- Restore titles
        if savedCol1Title then configFrame.col1:SetTitle(savedCol1Title) end
        if savedCol3Title then configFrame.col3:SetTitle(savedCol3Title) end
        if savedPanelTitle then configFrame:SetTitle(savedPanelTitle) end

        -- Show col2 + col4
        configFrame.col2.frame:Show()
        configFrame.col4.frame:Show()

        -- Restore column info buttons
        if not CooldownCompanion.db.profile.hideInfoButtons then
            if CS.columnInfoButtons[1] then CS.columnInfoButtons[1]:Show() end
            if CS.columnInfoButtons[3] then CS.columnInfoButtons[3]:Show() end
        end

        -- Show col1 normal content
        CS.col1Scroll.frame:Show()
        CS.col1ButtonBar:Show()

        -- Restore modeStatusRow visibility (SyncModeToggleWithProfileBar is a closure,
        -- so replicate its visibility logic: row shows when profileBar is hidden)
        if configFrame.modeStatusRow and configFrame.profileBar then
            configFrame.modeStatusRow:SetShown(not configFrame.profileBar:IsShown())
        end

        -- Recompute layout (4-column mode) then refresh
        configFrame.LayoutColumns()
        if configFrame.UpdateModeNavigationUI then
            configFrame.UpdateModeNavigationUI()
        end
    end

    savedCol1Title = nil
    savedCol3Title = nil
    savedPanelTitle = nil
    onAcceptCallback = nil
    pickerGroup = nil
    pickerSelectedSpecID = nil
    pickerSelectedConfigID = nil
    pickerSelectedHeroSubTreeID = nil
    wipe(pendingConditions)
    isRestoring = false

    -- RefreshConfigPanel restores col3 state correctly
    if configFrame then
        CooldownCompanion:RefreshConfigPanel()
    end
end

------------------------------------------------------------------------
-- POPULATE TREE
------------------------------------------------------------------------
local function ShouldIncludeBaseTreeNode(nodeInfo)
    return nodeInfo
        and nodeInfo.isVisible
        and not nodeInfo.subTreeID
        and nodeInfo.type ~= Enum.TraitNodeType.SubTreeSelection
end

local function ShouldIncludeHeroChoiceNode(nodeInfo, activeHeroSubTreeID)
    return nodeInfo
        and activeHeroSubTreeID
        and nodeInfo.subTreeID == activeHeroSubTreeID
        and nodeInfo.type == Enum.TraitNodeType.Selection
end

local function GetEntryDisplayInfo(configID, entryID)
    local entryInfo = C_Traits.GetEntryInfo(configID, entryID)
    if not entryInfo or not entryInfo.definitionID then return nil end

    local defInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
    if not defInfo then return nil end

    local spellID = defInfo.spellID
    local name = defInfo.overrideName
    local icon = defInfo.overrideIcon

    if spellID then
        if not name then
            local spellInfo = C_Spell.GetSpellInfo(spellID)
            name = spellInfo and spellInfo.name
        end
        if not icon then
            icon = C_Spell.GetSpellTexture(spellID)
        end
    end

    return {
        entryID = entryID,
        definitionID = entryInfo.definitionID,
        spellID = spellID,
        name = name or ("Entry " .. entryID),
        icon = icon or 134400,
    }
end

local function BuildNodeRecord(configID, nodeID, nodeInfo)
    local entries = {}
    if nodeInfo.entryIDs then
        for _, eid in ipairs(nodeInfo.entryIDs) do
            local displayInfo = GetEntryDisplayInfo(configID, eid)
            if displayInfo then
                entries[#entries + 1] = displayInfo
            end
        end
    end

    if #entries == 0 then
        return nil
    end

    return {
        nodeID = nodeID,
        px = nodeInfo.posX / 10,
        py = nodeInfo.posY / 10,
        entries = entries,
        isChoice = (nodeInfo.type == Enum.TraitNodeType.Selection),
        nodeType = nodeInfo.type,
        visibleEdges = nodeInfo.visibleEdges,
        subTreeID = nodeInfo.subTreeID,
        scopeType = nil,
    }
end

local function BuildHeroSpecNodeRecord(configID, treeID, heroSubTreeID)
    if not configID or not treeID or not heroSubTreeID then
        return nil
    end

    local nodeID, nodeInfo = CooldownCompanion:GetHeroSubTreeRootNode(configID, treeID, heroSubTreeID)
    if not nodeID or not nodeInfo then
        return nil
    end

    local record = BuildNodeRecord(configID, nodeID, nodeInfo)
    if not record then
        return nil
    end

    record.scopeType = "hero"
    record.displayName = GetHeroDisplayName(configID, heroSubTreeID)
    record.isHeroSpecProxy = true
    return record
end

local function ComputeBounds(nodeSet)
    local mnX, mxX, mnY, mxY = math.huge, -math.huge, math.huge, -math.huge
    for _, n in ipairs(nodeSet) do
        if n.px < mnX then mnX = n.px end
        if n.px > mxX then mxX = n.px end
        if n.py < mnY then mnY = n.py end
        if n.py > mxY then mxY = n.py end
    end
    return mnX, mxX, mnY, mxY
end

-- Iteratively trim extremes where the gap to the next value exceeds the
-- remaining range — detects nodes far outside the main cluster.
local function TrimOutlierRange(sorted)
    local lo, hi = 1, #sorted
    while hi > lo + 1 and (sorted[hi] - sorted[hi - 1]) > (sorted[hi - 1] - sorted[lo]) do
        hi = hi - 1
    end
    while lo < hi - 1 and (sorted[lo + 1] - sorted[lo]) > (sorted[hi] - sorted[lo + 1]) do
        lo = lo + 1
    end
    return sorted[lo], sorted[hi]
end

local function ComputeTrimmedBounds(nodeSet)
    if #nodeSet < 4 then
        return ComputeBounds(nodeSet)
    end
    local xs, ys = {}, {}
    for _, n in ipairs(nodeSet) do
        xs[#xs + 1] = n.px
        ys[#ys + 1] = n.py
    end
    table.sort(xs)
    table.sort(ys)
    -- Per-axis outlier fences
    local fenceMinX, fenceMaxX = TrimOutlierRange(xs)
    local fenceMinY, fenceMaxY = TrimOutlierRange(ys)
    -- Recompute bounds excluding nodes outside either fence, so an
    -- X-outlier's Y value doesn't inflate the Y range (and vice versa).
    local mnX, mxX, mnY, mxY = math.huge, -math.huge, math.huge, -math.huge
    for _, n in ipairs(nodeSet) do
        if n.px >= fenceMinX and n.px <= fenceMaxX
            and n.py >= fenceMinY and n.py <= fenceMaxY then
            if n.px < mnX then mnX = n.px end
            if n.px > mxX then mxX = n.px end
            if n.py < mnY then mnY = n.py end
            if n.py > mxY then mxY = n.py end
        end
    end
    if mnX == math.huge then
        return ComputeBounds(nodeSet)
    end
    return mnX, mxX, mnY, mxY
end

local function FindEntryByID(entries, entryID)
    if not entries or not entryID then
        return nil
    end

    for _, entry in ipairs(entries) do
        if entry.entryID == entryID then
            return entry
        end
    end

    return nil
end

local function GetPrimaryDisplayEntry(entries, nodeID)
    local pending = GetPendingStateForNode(nodeID)
    if pending and pending.entryID then
        local pendingEntry = FindEntryByID(entries, pending.entryID)
        if pendingEntry then
            return pendingEntry
        end
    end

    return entries and entries[1] or nil
end

local function PlaceNodesInPanel(scrollChild, nodeSet, panelOffsetX, yOffset,
                                  panelMinX, panelMinY, panelMaxX, panelMaxY,
                                  panelScale, btnIndex, nodeIDToBtn)
    for _, node in ipairs(nodeSet) do
        btnIndex = btnIndex + 1
        local btn = nodeButtons[btnIndex]
        if not btn then
            btn = CreateNodeButton(scrollChild, btnIndex)
            nodeButtons[btnIndex] = btn
        end

        -- Hide nodes that fall outside the trimmed bounds (outliers).
        if node.px < panelMinX or node.px > panelMaxX
            or node.py < panelMinY or node.py > panelMaxY then
            btn:Hide()
        else
            local x = panelOffsetX + (node.px - panelMinX) * panelScale + NODE_PADDING
            local y = yOffset + (node.py - panelMinY) * panelScale + NODE_PADDING

            btn:SetParent(scrollChild)
            btn:SetFrameStrata(scrollChild:GetFrameStrata())
            btn:SetFrameLevel((scrollChild:GetFrameLevel() or 0) + 5)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", x, -y)
            btn:Show()
        end

        -- Display: choice rows prefer the conditioned option, then the first option.
        local primaryEntry = node.isChoice
            and GetPrimaryDisplayEntry(node.entries, node.nodeID)
            or node.entries[1]
        local displayName = node.displayName or (primaryEntry and primaryEntry.name) or nil
        local displaySpellID = node.isHeroSpecProxy and nil or primaryEntry.spellID

        btn.icon:SetTexture(primaryEntry.icon)
        btn.icon:SetDesaturated(false)
        btn.icon:SetVertexColor(1, 1, 1)

        -- Store identity for pending state and border refresh
        btn._nodeID = node.nodeID
        btn._entryID = nil  -- regular nodes use nil; choice entries set per-entry
        btn._isChoiceNode = node.isChoice
        btn._entries = node.entries
        btn._talentName = displayName
        btn._spellID = displaySpellID
        btn._rankText = nil
        btn._disabledReason = node.disabledReason

        local borderColor, borderSize = GetNodeBorderStyle(node.nodeID, nil)
        SetNodeBorderThickness(btn, borderSize)
        SetNodeBorderColor(btn, borderColor)
        btn.icon:SetDesaturated(node.disabledInteraction and true or false)
        if node.disabledInteraction then
            btn.icon:SetVertexColor(0.5, 0.5, 0.5)
            btn.highlight:Hide()
        else
            btn.icon:SetVertexColor(1, 1, 1)
            btn.highlight:Show()
        end

        -- Click handler
        local nodeRef = node
        btn:SetScript("OnClick", function(self, mouseButton)
            if nodeRef.disabledInteraction then
                return
            end
            if nodeRef.isChoice and #nodeRef.entries > 1 then
                if mouseButton == "LeftButton" or mouseButton == nil then
                    ToggleChoiceFrame(self, nodeRef.entries, nodeRef.nodeID, nodeRef.scopeType, nodeRef.subTreeID)
                end
            else
                HideChoiceFrame()
                CyclePendingState(nodeRef.nodeID, nil, displaySpellID, displayName, BuildConditionContext(nodeRef.scopeType, nodeRef.subTreeID))
                if nodeRef.scopeType == "hero" and nodeRef.displayName then
                    PopulateTree()
                else
                    RefreshPickerBorders()
                end
            end
        end)

        nodeIDToBtn[node.nodeID] = btn
    end

    return btnIndex
end

local function DrawEdgesInPanel(scrollChild, panelNodes, nodeIDToBtn, edgePool)
    local lineIndex = 0
    local panelNodeIDs = {}

    for _, node in ipairs(panelNodes) do
        panelNodeIDs[node.nodeID] = true
    end

    for _, node in ipairs(panelNodes) do
        if node.visibleEdges then
            local srcBtn = nodeIDToBtn[node.nodeID]
            if srcBtn then
                for _, edge in ipairs(node.visibleEdges) do
                    local dstBtn = panelNodeIDs[edge.targetNode] and nodeIDToBtn[edge.targetNode] or nil
                    if dstBtn and srcBtn:IsShown() and dstBtn:IsShown() then
                        lineIndex = lineIndex + 1
                        local line = edgePool[lineIndex]
                        if not line then
                            line = scrollChild:CreateLine(nil, "BACKGROUND")
                            edgePool[lineIndex] = line
                        end

                        line:ClearAllPoints()
                        line:SetStartPoint("CENTER", srcBtn)
                        line:SetEndPoint("CENTER", dstBtn)

                        line:SetThickness(EDGE_THICKNESS)
                        line:SetColorTexture(COLOR_EDGE[1], COLOR_EDGE[2], COLOR_EDGE[3], COLOR_EDGE[4])

                        line:Show()
                    end
                end
            end
        end
    end
end

local function RenderNodePanel(panelFrame, nodeSet, nodeIDToBtn, edgePool, btnIndex, topPadding)
    if not panelFrame or #nodeSet == 0 then
        for _, line in ipairs(edgePool) do
            line:Hide()
        end
        return btnIndex
    end

    local frameW = panelFrame:GetWidth()
    local frameH = panelFrame:GetHeight()
    local panelTopPadding = topPadding or 0
    local usableW = math_max(frameW - NODE_PADDING * 2, NODE_SIZE)
    local usableH = math_max(frameH - panelTopPadding - NODE_PADDING * 2, NODE_SIZE)
    local minX, maxX, minY, maxY = ComputeTrimmedBounds(nodeSet)
    local treeW = maxX - minX + NODE_SIZE
    local treeH = maxY - minY + NODE_SIZE
    local scaleX = treeW > 0 and usableW / treeW or 1
    local scaleY = treeH > 0 and usableH / treeH or 1
    local scale = math_min(scaleX, scaleY, 1.5)
    local spanW = (maxX - minX) * scale
    local spanH = (maxY - minY) * scale
    local contentW = spanW + NODE_SIZE + NODE_PADDING * 2
    local offsetX = math_max(0, (frameW - contentW) * 0.5)
    local contentH = spanH + NODE_SIZE + NODE_PADDING * 2
    local offsetY = math_max(0, (frameH - panelTopPadding - contentH) * 0.5)

    btnIndex = PlaceNodesInPanel(panelFrame, nodeSet, offsetX, panelTopPadding + offsetY,
        minX, minY, maxX, maxY, scale, btnIndex, nodeIDToBtn)
    DrawEdgesInPanel(panelFrame, nodeSet, nodeIDToBtn, edgePool)

    return btnIndex
end

local function RenderHeroChoiceList(panelFrame, nodeSet, nodeIDToBtn, btnIndex, leadingNode)
    for _, line in ipairs(heroEdgeLines) do
        line:Hide()
    end

    if not panelFrame or (#nodeSet == 0 and not leadingNode) then
        return btnIndex
    end

    local orderedNodes = {}
    for i, node in ipairs(nodeSet) do
        orderedNodes[i] = node
    end

    table.sort(orderedNodes, function(a, b)
        if a.py == b.py then
            return a.px < b.px
        end
        return a.py < b.py
    end)

    local centeredX = math_max(NODE_PADDING, math_floor((panelFrame:GetWidth() - NODE_SIZE) * 0.5))
    local nextY = HERO_HEADER_HEIGHT + 8
    local disableHeroSubTreeRows = leadingNode and IsHeroSpecProxyNodeDisabled(leadingNode.nodeID)

    if leadingNode then
        btnIndex = PlaceNodesInPanel(panelFrame, { leadingNode }, centeredX - NODE_PADDING, nextY - NODE_PADDING,
            leadingNode.px, leadingNode.py, leadingNode.px, leadingNode.py, 0, btnIndex, nodeIDToBtn)
        nextY = nextY + NODE_SIZE + 10
    end

    for _, node in ipairs(orderedNodes) do
        if disableHeroSubTreeRows then
            node.disabledInteraction = true
            node.disabledReason = "Clear the top hero-spec condition first to edit hero-tree talents."
        else
            node.disabledInteraction = nil
            node.disabledReason = nil
        end
        btnIndex = PlaceNodesInPanel(panelFrame, { node }, centeredX - NODE_PADDING, nextY - NODE_PADDING,
            node.px, node.py, node.px, node.py, 0, btnIndex, nodeIDToBtn)
        nextY = nextY + NODE_SIZE + 10
    end

    return btnIndex
end

-- Re-apply border colors and thickness to all visible node + choice buttons.
RefreshPickerBorders = function()
    for _, btn in ipairs(nodeButtons) do
        if btn:IsShown() and btn._nodeID then
            if btn._isChoiceNode then
                local primaryEntry = GetPrimaryDisplayEntry(btn._entries, btn._nodeID)
                if primaryEntry then
                    btn.icon:SetTexture(primaryEntry.icon)
                    btn._talentName = primaryEntry.name
                    btn._spellID = primaryEntry.spellID
                end
            end
            local borderColor, borderSize = GetNodeBorderStyle(btn._nodeID, btn._entryID)
            SetNodeBorderThickness(btn, borderSize)
            SetNodeBorderColor(btn, borderColor)
        end
    end
    for _, cb in ipairs(choiceButtons) do
        if cb:IsShown() and cb._nodeID then
            local borderColor, borderSize = GetNodeBorderStyle(cb._nodeID, cb._entryID)
            SetNodeBorderThickness(cb, borderSize)
            SetNodeBorderColor(cb, borderColor)
        end
    end
end

PopulateTree = function()
    -- Hide all existing buttons and edges
    for _, btn in ipairs(nodeButtons) do btn:Hide() end
    for _, cb in ipairs(choiceButtons) do cb:Hide() end
    for _, line in ipairs(classEdgeLines) do line:Hide() end
    for _, line in ipairs(heroEdgeLines) do line:Hide() end
    for _, line in ipairs(specEdgeLines) do line:Hide() end
    HideChoiceFrame()

    -- Hide empty-state text if it exists
    if heroTreeFrame then
        heroTreeFrame:Hide()
    end
    if heroDropdown then
        heroDropdown.frame:Hide()
    end
    if specEmptyText then
        specEmptyText:Hide()
    end

    local specID = pickerSelectedSpecID
    LayoutSpecFrames(CS.configFrame.col3.content, specID ~= nil)

    if not specEmptyText then
        specEmptyText = specTreeFrame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        specEmptyText:SetPoint("CENTER", specTreeFrame, "CENTER", 0, 0)
    end

    if not specID then
        specEmptyText:SetText("No allowed specs for this group")
        specEmptyText:Show()
        return
    end

    local configID = EnsurePickerViewConfig(specID)
    pickerSelectedConfigID = configID
    if not configID then
        specEmptyText:SetText("No talent tree available for selected spec")
        specEmptyText:Show()
        return
    end

    local configInfo = C_Traits.GetConfigInfo(configID)
    local treeID = configInfo and configInfo.treeIDs and configInfo.treeIDs[1] or nil
    if not treeID then
        treeID = C_ClassTalents.GetTraitTreeForSpec(specID)
    end
    if not treeID then
        specEmptyText:SetText("No talent tree found for selected spec")
        specEmptyText:Show()
        return
    end

    local nodeIDs = C_Traits.GetTreeNodes(treeID)
    if not nodeIDs then
        specEmptyText:SetText("No talents found for selected spec")
        specEmptyText:Show()
        return
    end

    local selectedHeroSubTreeID = pickerSelectedHeroSubTreeID
    local heroSpecNode = BuildHeroSpecNodeRecord(configID, treeID, selectedHeroSubTreeID)

    -- Get tree currencies for class/spec split
    local treeCurrencyInfo = C_Traits.GetTreeCurrencyInfo(configID, treeID, false)
    local classCurrencyID, specCurrencyID
    if treeCurrencyInfo and #treeCurrencyInfo >= 2 then
        classCurrencyID = treeCurrencyInfo[1].traitCurrencyID
        specCurrencyID = treeCurrencyInfo[2].traitCurrencyID
    end

    -- Gather visible class/spec nodes plus selected hero choice nodes.
    local classNodes = {}
    local heroNodes = {}
    local specNodes = {}
    local allNodes = {}

    for _, nodeID in ipairs(nodeIDs) do
        local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
        if ShouldIncludeBaseTreeNode(nodeInfo) then
            local record = BuildNodeRecord(configID, nodeID, nodeInfo)
            if record then
                allNodes[#allNodes + 1] = record

                -- Classify by currency
                if classCurrencyID and specCurrencyID then
                    local costs = C_Traits.GetNodeCost(configID, nodeID)
                    local isSpec = false
                    if costs and #costs > 0 then
                        for _, cost in ipairs(costs) do
                            if cost.ID == specCurrencyID then
                                isSpec = true
                                break
                            end
                        end
                        if isSpec then
                            record.scopeType = "spec"
                            specNodes[#specNodes + 1] = record
                        else
                            record.scopeType = "class"
                            classNodes[#classNodes + 1] = record
                        end
                    else
                        -- No cost (granted starting talents) -> default to class
                        record.scopeType = "class"
                        classNodes[#classNodes + 1] = record
                    end
                end
            end
        elseif ShouldIncludeHeroChoiceNode(nodeInfo, selectedHeroSubTreeID) then
            local record = BuildNodeRecord(configID, nodeID, nodeInfo)
            if record then
                record.scopeType = "hero"
                heroNodes[#heroNodes + 1] = record
            end
        end
    end

    local hasHeroChoices = heroSpecNode ~= nil or #heroNodes > 0

    local dualPanel = (#classNodes > 0 and #specNodes > 0)
    local nodeIDToBtn = {}
    local btnIndex = 0

    if dualPanel then
        btnIndex = RenderNodePanel(classTreeFrame, classNodes, nodeIDToBtn, classEdgeLines, btnIndex, 0)
        btnIndex = RenderNodePanel(specTreeFrame, specNodes, nodeIDToBtn, specEdgeLines, btnIndex, SPEC_CONTROL_ROW_HEIGHT)
    else
        -- Single-panel fallback: all nodes in left container
        btnIndex = RenderNodePanel(classTreeFrame, allNodes, nodeIDToBtn, classEdgeLines, btnIndex, 0)

        -- Right container: empty message
        specEmptyText:SetText("No spec talents found")
        specEmptyText:Show()
    end

    if hasHeroChoices then
        btnIndex = RenderHeroChoiceList(heroTreeFrame, heroNodes, nodeIDToBtn, btnIndex, heroSpecNode)
    end
end

------------------------------------------------------------------------
-- PUBLIC API
------------------------------------------------------------------------

-- Open the talent picker inside the config panel columns.
-- callback(results): called with array of conditions or nil (clear all).
-- initialConditions: array of existing conditions to pre-load as pending.
function CooldownCompanion:OpenTalentPicker(callback, initialConditions, group)
    local configFrame = CS.configFrame
    if not configFrame then return end
    onAcceptCallback = callback
    ShowTalentPicker(configFrame, initialConditions, group)
end

function CooldownCompanion:CloseTalentPicker()
    HideTalentPicker()
end

function CooldownCompanion:IsTalentPickerOpen()
    return CS.talentPickerMode
end
