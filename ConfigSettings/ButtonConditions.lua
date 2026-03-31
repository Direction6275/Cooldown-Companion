--[[
    CooldownCompanion - ConfigSettings/ButtonConditions.lua: Per-button visibility settings and
    group-level load conditions
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

-- Imports from Helpers.lua and State.lua
local BuildHeroTalentSubTreeCheckboxes = ST._BuildHeroTalentSubTreeCheckboxes
local ColorHeading = ST._ColorHeading
local AttachCollapseButton = ST._AttachCollapseButton
local CreateInfoButton = ST._CreateInfoButton
local AttachCheckboxTooltip = ST._AttachCheckboxTooltip
local ApplyCheckboxIndent = ST._ApplyCheckboxIndent

local HasTooltipCooldown = ST.HasTooltipCooldown
local HasUsageRequirement = ST.HasUsageRequirement

local tabInfoButtons = CS.tabInfoButtons
local appearanceTabElements = CS.appearanceTabElements

------------------------------------------------------------------------
-- BATCH HELPERS (multi-select visibility)
------------------------------------------------------------------------

-- Returns true if all selected have field truthy, false if all falsy, nil if mixed
local function GetBatchFieldValue(group, field)
    local anyTrue, anyFalse = false, false
    for idx in pairs(CS.selectedButtons) do
        local bd = group.buttons[idx]
        if bd then
            if bd[field] then anyTrue = true else anyFalse = true end
        end
    end
    if anyTrue and anyFalse then return nil end  -- mixed
    return anyTrue  -- true if all true, false if all false
end

-- Scoped version: only reads from buttons matching filterFn(bd) → true.
-- Ensures read scope matches write scope for filtered apply functions.
local function GetBatchFieldValueFiltered(group, field, filterFn)
    local anyTrue, anyFalse = false, false
    local anyMatched = false
    for idx in pairs(CS.selectedButtons) do
        local bd = group.buttons[idx]
        if bd and filterFn(bd) then
            anyMatched = true
            if bd[field] then anyTrue = true else anyFalse = true end
        end
    end
    if not anyMatched then return false end
    if anyTrue and anyFalse then return nil end
    return anyTrue
end

-- Filter predicates (matching the write scopes of ApplyTo* functions)
local function FilterNonEquippable(bd)
    return bd.type == "item" and not CooldownCompanion.IsItemEquippable(bd)
end
local function FilterEquippable(bd)
    return bd.type == "item" and CooldownCompanion.IsItemEquippable(bd)
end
local function FilterAuraTracking(bd)
    return bd.auraTracking == true
end
local function FilterTargetAuraTracking(bd)
    return bd.auraTracking == true and bd.auraUnit == "target"
end
local function FilterChargeCapable(bd)
    if not bd.hasCharges then return false end
    if bd.type == "spell" then return true end
    if bd.type == "item" and not CooldownCompanion.IsItemEquippable(bd) then return true end
    return false
end

-- Returns true if any selected button has field truthy
local function AnySelectedHas(group, field)
    for idx in pairs(CS.selectedButtons) do
        local bd = group.buttons[idx]
        if bd and bd[field] then return true end
    end
    return false
end

-- Scoped version: only checks buttons matching filterFn(bd) → true
local function AnySelectedHasFiltered(group, field, filterFn)
    for idx in pairs(CS.selectedButtons) do
        local bd = group.buttons[idx]
        if bd and filterFn(bd) and bd[field] then return true end
    end
    return false
end

-- Returns true if all selected buttons have field truthy
local function AllSelectedAre(group, field)
    for idx in pairs(CS.selectedButtons) do
        local bd = group.buttons[idx]
        if bd and not bd[field] then return false end
    end
    return true
end

-- Returns true if a button has no real cooldown (GCD-only spell)
local function IsNoCooldownSpell(bd)
    if not bd or bd.type ~= "spell" or bd.isPassive or bd.hasCharges then return false end
    local baseCd = GetSpellBaseCooldown(bd.id)
    return (not baseCd or baseCd == 0) and not HasTooltipCooldown(bd.id)
end

-- Returns true if all selected buttons are no-cooldown spells
local function AllSelectedNoCooldown(group)
    for idx in pairs(CS.selectedButtons) do
        local bd = group.buttons[idx]
        if bd and not IsNoCooldownSpell(bd) then return false end
    end
    return true
end

-- Returns true if a button would never be affected by unusable dimming.
-- Items can always be unusable (level, class, etc.), so only spells are checked.
-- A spell is "never unusable" only if it has no resource cost AND no usage
-- requirements (form/stance/etc). Spells like Mangle (zero cost, requires
-- Bear Form) correctly return false here — their toggle remains visible.
local WHIRLING_DRAGON_PUNCH_SPELL_ID = 152175

local function IsNeverUnusableButton(bd)
    if not bd or bd.type ~= "spell" then return false end
    if bd.id == WHIRLING_DRAGON_PUNCH_SPELL_ID then return false end
    if bd._castCountCandidate then return false end
    local costs = C_Spell.GetSpellPowerCost(bd.id)
    if costs and #costs > 0 then return false end
    return not HasUsageRequirement(bd.id)
end

-- Returns true if all selected buttons would never be affected by unusable dimming
local function AllSelectedNeverUnusable(group)
    for idx in pairs(CS.selectedButtons) do
        local bd = group.buttons[idx]
        if bd and not IsNeverUnusableButton(bd) then return false end
    end
    return true
end

-- Returns true if any selected item button is equippable
local function AnySelectedEquippable(group)
    for idx in pairs(CS.selectedButtons) do
        local bd = group.buttons[idx]
        if bd and bd.type == "item" and CooldownCompanion.IsItemEquippable(bd) then return true end
    end
    return false
end

-- Returns true if any selected item button is non-equippable
local function AnySelectedNonEquippable(group)
    for idx in pairs(CS.selectedButtons) do
        local bd = group.buttons[idx]
        if bd and bd.type == "item" and not CooldownCompanion.IsItemEquippable(bd) then return true end
    end
    return false
end

-- Returns true if any selected button is charge-capable (spells or non-equippable items with charges)
local function AnySelectedChargeCapable(group)
    for idx in pairs(CS.selectedButtons) do
        local bd = group.buttons[idx]
        if bd and FilterChargeCapable(bd) then return true end
    end
    return false
end

------------------------------------------------------------------------
-- Batch checkbox helper: set up tri-state display and click semantics
------------------------------------------------------------------------
local function SetupBatchCheckbox(cb, batchValue)
    cb:SetTriState(true)
    cb:SetValue(batchValue)
    -- Store pre-click value so callback can distinguish mixed→click from true→click
    cb._batchPrev = batchValue
end

-- Remap AceGUI tri-state cycling for batch UX:
--   mixed(nil) click → all ON, ON(true) click → all OFF, OFF(false) click → all ON
local function RemapBatchValue(widget, val)
    -- AceGUI tri-state cycles: true→nil, nil→false, false→true
    if widget._batchPrev == nil and val == false then
        -- Was mixed, AceGUI cycled nil→false. We want → ON.
        return true
    elseif val == nil then
        -- Was true, AceGUI cycled true→nil. We want → OFF.
        return false
    end
    -- Was false, AceGUI cycled false→true. Keep → ON.
    return val and true or false
end

------------------------------------------------------------------------
-- Talent condition display helpers (shared with ResourceBarPanels)
------------------------------------------------------------------------

local function ResolveConditionClassName(cond)
    if not cond then
        return nil
    end

    if cond.className and cond.className ~= "" then
        return cond.className
    end

    if cond.classID then
        local name = GetClassInfo(cond.classID)
        return name or ("Class " .. cond.classID)
    end

    return nil
end

local function ResolveConditionSpecName(cond)
    if not cond then
        return nil
    end

    if cond.specName and cond.specName ~= "" then
        return cond.specName
    end

    if cond.specID then
        local _, name = GetSpecializationInfoForSpecID(cond.specID)
        return name or ("Spec " .. cond.specID)
    end

    return nil
end

local function ResolveConditionHeroName(cond)
    if not cond then
        return nil
    end

    if cond.heroName and cond.heroName ~= "" then
        return cond.heroName
    end

    if cond.heroSubTreeID then
        return "Hero " .. cond.heroSubTreeID
    end

    return nil
end

local function GetConditionContextSuffix(cond)
    local parts = {}
    local className = ResolveConditionClassName(cond)
    local specName = ResolveConditionSpecName(cond)
    local heroName = ResolveConditionHeroName(cond)

    if className then
        parts[#parts + 1] = className
    end
    if specName then
        parts[#parts + 1] = specName
    end
    if heroName then
        parts[#parts + 1] = heroName
    end

    if #parts == 0 then
        return ""
    end

    return " [" .. table.concat(parts, ", ") .. "]"
end

local function GetConditionListContextSuffix(list)
    local scope = {}

    for _, cond in ipairs(list or {}) do
        if not scope.className then
            scope.className = ResolveConditionClassName(cond)
        end
        if not scope.specName then
            scope.specName = ResolveConditionSpecName(cond)
        end
        if not scope.heroName then
            scope.heroName = ResolveConditionHeroName(cond)
        end
    end

    if not scope.className and not scope.specName and not scope.heroName then
        return ""
    end

    local parts = {}
    if scope.className then
        parts[#parts + 1] = scope.className
    end
    if scope.specName then
        parts[#parts + 1] = scope.specName
    end
    if scope.heroName then
        parts[#parts + 1] = scope.heroName
    end
    return " [" .. table.concat(parts, ", ") .. "]"
end

local function GetConditionDisplayName(cond)
    return (cond.name or "Unknown Talent") .. GetConditionContextSuffix(cond)
end

------------------------------------------------------------------------
-- PER-BUTTON VISIBILITY SETTINGS
------------------------------------------------------------------------
local function BuildVisibilitySettings(scroll, buttonData, infoButtons, batchContext)
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then return end

    local isBatch = batchContext ~= nil
    local isItem
    if isBatch then
        isItem = batchContext.uniformType == "item"
    else
        isItem = buttonData.type == "item"
    end

    -- Helper: apply a value to all selected buttons if multi-select, else just this one
    local function ApplyToSelected(field, value)
        if CS.selectedButtons then
            local count = 0
            for _ in pairs(CS.selectedButtons) do count = count + 1 end
            if count >= 2 then
                for idx in pairs(CS.selectedButtons) do
                    local bd = group.buttons[idx]
                    if bd then bd[field] = value end
                end
                return
            end
        end
        buttonData[field] = value
    end

    -- Filtered apply: only write to non-equippable items (stack toggles).
    -- When clearing (value is falsy), write to ALL selected to clean stale data.
    local function ApplyToNonEquippable(field, value)
        if isBatch then
            for idx in pairs(CS.selectedButtons) do
                local bd = group.buttons[idx]
                if bd then
                    if not value or FilterNonEquippable(bd) then
                        bd[field] = value
                    end
                end
            end
        else
            buttonData[field] = value
        end
    end

    -- Filtered apply: only write to charge-capable buttons (charge toggles).
    -- When clearing (value is falsy), write to ALL selected to clean stale data.
    local function ApplyToChargeCapable(field, value)
        if isBatch then
            for idx in pairs(CS.selectedButtons) do
                local bd = group.buttons[idx]
                if bd then
                    if not value or FilterChargeCapable(bd) then
                        bd[field] = value
                    end
                end
            end
        else
            buttonData[field] = value
        end
    end

    -- Filtered apply: only write to equippable items (equip toggles).
    -- When clearing, write to ALL selected to clean stale data.
    local function ApplyToEquippable(field, value)
        if isBatch then
            for idx in pairs(CS.selectedButtons) do
                local bd = group.buttons[idx]
                if bd then
                    if not value or FilterEquippable(bd) then
                        bd[field] = value
                    end
                end
            end
        else
            buttonData[field] = value
        end
    end

    -- Filtered apply: only write to buttons with aura tracking enabled.
    -- When clearing, write to ALL selected to clean stale data.
    local function ApplyToAuraTracking(field, value)
        if isBatch then
            for idx in pairs(CS.selectedButtons) do
                local bd = group.buttons[idx]
                if bd then
                    if not value or FilterAuraTracking(bd) then
                        bd[field] = value
                    end
                end
            end
        else
            buttonData[field] = value
        end
    end

    -- Filtered apply: only write to buttons with target aura tracking.
    -- When clearing, write to ALL selected to clean stale data.
    local function ApplyToTargetAuraTracking(field, value)
        if isBatch then
            for idx in pairs(CS.selectedButtons) do
                local bd = group.buttons[idx]
                if bd then
                    if not value or FilterTargetAuraTracking(bd) then
                        bd[field] = value
                    end
                end
            end
        else
            buttonData[field] = value
        end
    end

    -- Helper: set checkbox value (batch-aware tri-state or normal).
    -- Optional filterFn scopes the batch read to match the write filter.
    local function SetCheckboxValue(cb, field, filterFn)
        if isBatch then
            local batchVal
            if filterFn then
                batchVal = GetBatchFieldValueFiltered(group, field, filterFn)
            else
                batchVal = GetBatchFieldValue(group, field)
            end
            SetupBatchCheckbox(cb, batchVal)
        else
            cb:SetValue(buttonData[field] or false)
        end
    end

    -- Helper: wrap OnValueChanged callback with batch remapping
    local function WrapBatchCallback(cb, callback)
        cb:SetCallback("OnValueChanged", function(widget, event, val)
            if isBatch then
                val = RemapBatchValue(widget, val)
            end
            callback(widget, event, val)
            if isBatch then
                widget._batchPrev = val
                widget:SetValue(val)  -- sync visual state for non-refreshing callbacks
            end
        end)
    end

    local heading = AceGUI:Create("Heading")
    heading:SetText("Visibility Rules")
    ColorHeading(heading)
    heading:SetFullWidth(true)
    scroll:AddChild(heading)

    local visKey = isBatch
        and (CS.selectedGroup .. "_batch_visibility")
        or  (CS.selectedGroup .. "_" .. CS.selectedButton .. "_visibility")
    local visCollapsed = CS.collapsedSections[visKey]
    local visCollapseBtn = AttachCollapseButton(heading, visCollapsed, function()
        CS.collapsedSections[visKey] = not CS.collapsedSections[visKey]
        CooldownCompanion:RefreshConfigPanel()
    end)


    if not visCollapsed then
    -- Hide While On Cooldown (skip for passives — no cooldown)
    -- Batch: show if not ALL selected are passive
    local allPassive
    if isBatch then allPassive = AllSelectedAre(group, "isPassive")
    else allPassive = buttonData.isPassive end
    local allNoCooldown
    if isBatch then allNoCooldown = AllSelectedNoCooldown(group)
    else allNoCooldown = IsNoCooldownSpell(buttonData) end
    local allNeverUnusable
    if isBatch then allNeverUnusable = AllSelectedNeverUnusable(group)
    else allNeverUnusable = IsNeverUnusableButton(buttonData) end
    if not allPassive and not allNoCooldown then
    local hideCDCb = AceGUI:Create("CheckBox")
    hideCDCb:SetLabel("Hide While On Cooldown")
    SetCheckboxValue(hideCDCb, "hideWhileOnCooldown")
    hideCDCb:SetFullWidth(true)
    WrapBatchCallback(hideCDCb, function(widget, event, val)
        ApplyToSelected("hideWhileOnCooldown", val or nil)
        if val then
            ApplyToSelected("hideWhileNotOnCooldown", nil)
            ApplyToSelected("useBaselineAlphaFallbackNotOnCooldown", nil)
        else
            ApplyToSelected("useBaselineAlphaFallbackOnCooldown", nil)
        end
        CooldownCompanion:RefreshConfigPanel()
    end)
    scroll:AddChild(hideCDCb)

    -- Baseline Alpha Fallback (nested under hideWhileOnCooldown)
    local showFallbackOnCooldown
    if isBatch then showFallbackOnCooldown = AnySelectedHas(group, "hideWhileOnCooldown")
    else showFallbackOnCooldown = buttonData.hideWhileOnCooldown end
    if showFallbackOnCooldown then
        local fallbackOnCDCb = AceGUI:Create("CheckBox")
        fallbackOnCDCb:SetLabel("Use Baseline Alpha Fallback")
        SetCheckboxValue(fallbackOnCDCb, "useBaselineAlphaFallbackOnCooldown")
        fallbackOnCDCb:SetFullWidth(true)
        ApplyCheckboxIndent(fallbackOnCDCb, 20)
        WrapBatchCallback(fallbackOnCDCb, function(widget, event, val)
            ApplyToSelected("useBaselineAlphaFallbackOnCooldown", val or nil)
        end)
        scroll:AddChild(fallbackOnCDCb)

        AttachCheckboxTooltip(fallbackOnCDCb, {
            "Use Baseline Alpha Fallback",
            {"Instead of fully hiding, show the button dimmed at the group's baseline alpha. The button keeps its layout position.", 1, 1, 1, true},
        })
    end

    -- Hide While Not On Cooldown
    local hideNotCDCb = AceGUI:Create("CheckBox")
    hideNotCDCb:SetLabel("Hide While Not On Cooldown")
    SetCheckboxValue(hideNotCDCb, "hideWhileNotOnCooldown")
    hideNotCDCb:SetFullWidth(true)
    WrapBatchCallback(hideNotCDCb, function(widget, event, val)
        ApplyToSelected("hideWhileNotOnCooldown", val or nil)
        if val then
            ApplyToSelected("hideWhileOnCooldown", nil)
            ApplyToSelected("useBaselineAlphaFallbackOnCooldown", nil)
        else
            ApplyToSelected("useBaselineAlphaFallbackNotOnCooldown", nil)
        end
        CooldownCompanion:RefreshConfigPanel()
    end)
    scroll:AddChild(hideNotCDCb)

    -- Baseline Alpha Fallback (nested under hideWhileNotOnCooldown)
    local showFallbackNotOnCooldown
    if isBatch then showFallbackNotOnCooldown = AnySelectedHas(group, "hideWhileNotOnCooldown")
    else showFallbackNotOnCooldown = buttonData.hideWhileNotOnCooldown end
    if showFallbackNotOnCooldown then
        local fallbackNotOnCDCb = AceGUI:Create("CheckBox")
        fallbackNotOnCDCb:SetLabel("Use Baseline Alpha Fallback")
        SetCheckboxValue(fallbackNotOnCDCb, "useBaselineAlphaFallbackNotOnCooldown")
        fallbackNotOnCDCb:SetFullWidth(true)
        ApplyCheckboxIndent(fallbackNotOnCDCb, 20)
        WrapBatchCallback(fallbackNotOnCDCb, function(widget, event, val)
            ApplyToSelected("useBaselineAlphaFallbackNotOnCooldown", val or nil)
        end)
        scroll:AddChild(fallbackNotOnCDCb)

        AttachCheckboxTooltip(fallbackNotOnCDCb, {
            "Use Baseline Alpha Fallback",
            {"Instead of fully hiding, show the button dimmed at the group's baseline alpha. The button keeps its layout position.", 1, 1, 1, true},
        })
    end

    end -- not allPassive and not allNoCooldown

    if not allPassive then
    if not allNeverUnusable then
    -- Hide While Unusable
    local hideUnusableCb = AceGUI:Create("CheckBox")
    hideUnusableCb:SetLabel("Hide While Unusable")
    SetCheckboxValue(hideUnusableCb, "hideWhileUnusable")
    hideUnusableCb:SetFullWidth(true)
    WrapBatchCallback(hideUnusableCb, function(widget, event, val)
        ApplyToSelected("hideWhileUnusable", val or nil)
        if not val then
            ApplyToSelected("useBaselineAlphaFallbackUnusable", nil)
        end
        CooldownCompanion:RefreshConfigPanel()
    end)
    scroll:AddChild(hideUnusableCb)

    -- (?) tooltip
    AttachCheckboxTooltip(hideUnusableCb, {
        "Hide While Unusable",
        {"Uses the same logic as unusable dimming, but completely hides the button instead of dimming it.", 1, 1, 1, true},
    })

    -- Baseline Alpha Fallback (nested under hideWhileUnusable)
    local showFallbackUnusable
    if isBatch then showFallbackUnusable = AnySelectedHas(group, "hideWhileUnusable")
    else showFallbackUnusable = buttonData.hideWhileUnusable end
    if showFallbackUnusable then
        local fallbackUnusableCb = AceGUI:Create("CheckBox")
        fallbackUnusableCb:SetLabel("Use Baseline Alpha Fallback")
        SetCheckboxValue(fallbackUnusableCb, "useBaselineAlphaFallbackUnusable")
        fallbackUnusableCb:SetFullWidth(true)
        ApplyCheckboxIndent(fallbackUnusableCb, 20)
        WrapBatchCallback(fallbackUnusableCb, function(widget, event, val)
            ApplyToSelected("useBaselineAlphaFallbackUnusable", val or nil)
        end)
        scroll:AddChild(fallbackUnusableCb)

        AttachCheckboxTooltip(fallbackUnusableCb, {
            "Use Baseline Alpha Fallback",
            {"Instead of fully hiding, show the button dimmed at the group's baseline alpha. The button keeps its layout position.", 1, 1, 1, true},
        })
    end
    end -- not allNeverUnusable

    -- Hide While No Proc (spell entries only, not aura entries)
    local showNoProcToggle
    if isBatch then
        showNoProcToggle = batchContext and batchContext.uniformType == "spell"
    else
        showNoProcToggle = buttonData.type == "spell" and buttonData.addedAs ~= "aura"
    end
    if showNoProcToggle then
        local hideNoProcCb = AceGUI:Create("CheckBox")
        hideNoProcCb:SetLabel("Hide While No Proc")
        SetCheckboxValue(hideNoProcCb, "hideWhileNoProc")
        hideNoProcCb:SetFullWidth(true)
        WrapBatchCallback(hideNoProcCb, function(widget, event, val)
            ApplyToSelected("hideWhileNoProc", val or nil)
            if not val then
                ApplyToSelected("useBaselineAlphaFallbackNoProc", nil)
            end
            CooldownCompanion:RefreshConfigPanel()
        end)
        scroll:AddChild(hideNoProcCb)

        -- Baseline Alpha Fallback (nested under hideWhileNoProc)
        local showFallbackNoProc
        if isBatch then showFallbackNoProc = AnySelectedHas(group, "hideWhileNoProc")
        else showFallbackNoProc = buttonData.hideWhileNoProc end
        if showFallbackNoProc then
            local fallbackNoProcCb = AceGUI:Create("CheckBox")
            fallbackNoProcCb:SetLabel("Use Baseline Alpha Fallback")
            SetCheckboxValue(fallbackNoProcCb, "useBaselineAlphaFallbackNoProc")
            fallbackNoProcCb:SetFullWidth(true)
            ApplyCheckboxIndent(fallbackNoProcCb, 20)
            WrapBatchCallback(fallbackNoProcCb, function(widget, event, val)
                ApplyToSelected("useBaselineAlphaFallbackNoProc", val or nil)
            end)
            scroll:AddChild(fallbackNoProcCb)

            AttachCheckboxTooltip(fallbackNoProcCb, {
                "Use Baseline Alpha Fallback",
                {"Instead of fully hiding, show the button dimmed at the group's baseline alpha. The button keeps its layout position.", 1, 1, 1, true},
            })
        end
    end

    end -- not allPassive (unusable + no proc)

    -- Charge-based visibility toggles (spells + non-equippable items with charges)
    -- Batch: show if any selected button is charge-capable
    local showChargeSection
    if isBatch then showChargeSection = AnySelectedChargeCapable(group)
    else showChargeSection = buttonData.hasCharges and (buttonData.type == "spell" or (isItem and not CooldownCompanion.IsItemEquippable(buttonData))) end
    if showChargeSection then
        -- Hide While At Zero Charges
        local hideZeroChargesCb = AceGUI:Create("CheckBox")
        hideZeroChargesCb:SetLabel("Hide While At Zero Charges")
        SetCheckboxValue(hideZeroChargesCb, "hideWhileZeroCharges", FilterChargeCapable)
        hideZeroChargesCb:SetFullWidth(true)
        WrapBatchCallback(hideZeroChargesCb, function(widget, event, val)
            ApplyToChargeCapable("hideWhileZeroCharges", val or nil)
            if val then
                ApplyToChargeCapable("desaturateWhileZeroCharges", nil)
            else
                ApplyToChargeCapable("useBaselineAlphaFallbackZeroCharges", nil)
            end
            CooldownCompanion:RefreshConfigPanel()
        end)
        scroll:AddChild(hideZeroChargesCb)

        -- Baseline Alpha Fallback (nested under hideWhileZeroCharges)
        -- Batch: show if any selected has it on
        local showFallbackZeroCharges
        if isBatch then showFallbackZeroCharges = AnySelectedHasFiltered(group, "hideWhileZeroCharges", FilterChargeCapable)
        else showFallbackZeroCharges = buttonData.hideWhileZeroCharges end
        if showFallbackZeroCharges then
            local fallbackZeroChargesCb = AceGUI:Create("CheckBox")
            fallbackZeroChargesCb:SetLabel("Use Baseline Alpha Fallback")
            SetCheckboxValue(fallbackZeroChargesCb, "useBaselineAlphaFallbackZeroCharges", FilterChargeCapable)
            fallbackZeroChargesCb:SetFullWidth(true)
            ApplyCheckboxIndent(fallbackZeroChargesCb, 20)
            WrapBatchCallback(fallbackZeroChargesCb, function(widget, event, val)
                ApplyToChargeCapable("useBaselineAlphaFallbackZeroCharges", val or nil)
            end)
            scroll:AddChild(fallbackZeroChargesCb)

            -- (?) tooltip
            AttachCheckboxTooltip(fallbackZeroChargesCb, {
                "Use Baseline Alpha Fallback",
                {"Instead of fully hiding, show the button dimmed at the group's baseline alpha. The button keeps its layout position.", 1, 1, 1, true},
            })
        end

        -- Desaturate While At Zero Charges
        local desatZeroChargesCb = AceGUI:Create("CheckBox")
        desatZeroChargesCb:SetLabel("Desaturate While At Zero Charges")
        SetCheckboxValue(desatZeroChargesCb, "desaturateWhileZeroCharges", FilterChargeCapable)
        desatZeroChargesCb:SetFullWidth(true)
        WrapBatchCallback(desatZeroChargesCb, function(widget, event, val)
            ApplyToChargeCapable("desaturateWhileZeroCharges", val or nil)
            if val then
                ApplyToChargeCapable("hideWhileZeroCharges", nil)
                ApplyToChargeCapable("useBaselineAlphaFallbackZeroCharges", nil)
            end
            CooldownCompanion:RefreshConfigPanel()
        end)
        scroll:AddChild(desatZeroChargesCb)

        -- Hide Cooldown While Charges Remain
        local hideCdChargesCb = AceGUI:Create("CheckBox")
        hideCdChargesCb:SetLabel("Hide Cooldown While Charges Remain")
        SetCheckboxValue(hideCdChargesCb, "hideCooldownWithCharges", FilterChargeCapable)
        hideCdChargesCb:SetFullWidth(true)
        WrapBatchCallback(hideCdChargesCb, function(widget, event, val)
            ApplyToChargeCapable("hideCooldownWithCharges", val or nil)
        end)
        scroll:AddChild(hideCdChargesCb)
    end

    -- Stack-based visibility toggles (non-equippable items without charges)
    -- Batch: show if any selected non-equippable item exists
    local showStackSection
    if isBatch then showStackSection = isItem and AnySelectedNonEquippable(group)
    else showStackSection = isItem and not CooldownCompanion.IsItemEquippable(buttonData) end
    if showStackSection then
        -- Batch: show stacks section if any selected lacks charges (stack-based items)
        local hasStacks
        if isBatch then hasStacks = not AllSelectedAre(group, "hasCharges")
        else hasStacks = not buttonData.hasCharges end
        if hasStacks then
            -- Hide While At Zero Stacks
            local hideZeroStacksCb = AceGUI:Create("CheckBox")
            hideZeroStacksCb:SetLabel("Hide While At Zero Stacks")
            SetCheckboxValue(hideZeroStacksCb, "hideWhileZeroStacks", FilterNonEquippable)
            hideZeroStacksCb:SetFullWidth(true)
            WrapBatchCallback(hideZeroStacksCb, function(widget, event, val)
                ApplyToNonEquippable("hideWhileZeroStacks", val or nil)
                if val then
                    ApplyToNonEquippable("desaturateWhileZeroStacks", nil)
                else
                    ApplyToNonEquippable("useBaselineAlphaFallbackZeroStacks", nil)
                end
                CooldownCompanion:RefreshConfigPanel()
            end)
            scroll:AddChild(hideZeroStacksCb)

            -- Baseline Alpha Fallback (nested under hideWhileZeroStacks)
            local showFallbackZeroStacks
            if isBatch then showFallbackZeroStacks = AnySelectedHasFiltered(group, "hideWhileZeroStacks", FilterNonEquippable)
            else showFallbackZeroStacks = buttonData.hideWhileZeroStacks end
            if showFallbackZeroStacks then
                local fallbackZeroStacksCb = AceGUI:Create("CheckBox")
                fallbackZeroStacksCb:SetLabel("Use Baseline Alpha Fallback")
                SetCheckboxValue(fallbackZeroStacksCb, "useBaselineAlphaFallbackZeroStacks", FilterNonEquippable)
                fallbackZeroStacksCb:SetFullWidth(true)
                ApplyCheckboxIndent(fallbackZeroStacksCb, 20)
                WrapBatchCallback(fallbackZeroStacksCb, function(widget, event, val)
                    ApplyToNonEquippable("useBaselineAlphaFallbackZeroStacks", val or nil)
                end)
                scroll:AddChild(fallbackZeroStacksCb)

                -- (?) tooltip
                AttachCheckboxTooltip(fallbackZeroStacksCb, {
                    "Use Baseline Alpha Fallback",
                    {"Instead of fully hiding, show the button dimmed at the group's baseline alpha. The button keeps its layout position.", 1, 1, 1, true},
                })
            end

            -- Desaturate While At Zero Stacks
            local desatZeroStacksCb = AceGUI:Create("CheckBox")
            desatZeroStacksCb:SetLabel("Desaturate While At Zero Stacks")
            SetCheckboxValue(desatZeroStacksCb, "desaturateWhileZeroStacks", FilterNonEquippable)
            desatZeroStacksCb:SetFullWidth(true)
            WrapBatchCallback(desatZeroStacksCb, function(widget, event, val)
                ApplyToNonEquippable("desaturateWhileZeroStacks", val or nil)
                if val then
                    ApplyToNonEquippable("hideWhileZeroStacks", nil)
                    ApplyToNonEquippable("useBaselineAlphaFallbackZeroStacks", nil)
                end
                CooldownCompanion:RefreshConfigPanel()
            end)
            scroll:AddChild(desatZeroStacksCb)
        end
    end

    -- Hide While Not Equipped (equippable items only)
    -- Batch: show if any selected item is equippable
    local showEquipSection
    if isBatch then showEquipSection = isItem and AnySelectedEquippable(group)
    else showEquipSection = isItem and CooldownCompanion.IsItemEquippable(buttonData) end
    if showEquipSection then
        local hideNotEquippedCb = AceGUI:Create("CheckBox")
        hideNotEquippedCb:SetLabel("Hide While Not Equipped")
        SetCheckboxValue(hideNotEquippedCb, "hideWhileNotEquipped", FilterEquippable)
        hideNotEquippedCb:SetFullWidth(true)
        WrapBatchCallback(hideNotEquippedCb, function(widget, event, val)
            ApplyToEquippable("hideWhileNotEquipped", val or nil)
            if not val then
                ApplyToEquippable("useBaselineAlphaFallbackNotEquipped", nil)
            end
            CooldownCompanion:RefreshConfigPanel()
        end)
        scroll:AddChild(hideNotEquippedCb)

        -- Baseline Alpha Fallback (nested under hideWhileNotEquipped)
        local showFallbackEquip
        if isBatch then showFallbackEquip = AnySelectedHasFiltered(group, "hideWhileNotEquipped", FilterEquippable)
        else showFallbackEquip = buttonData.hideWhileNotEquipped end
        if showFallbackEquip then
            local fallbackNotEquippedCb = AceGUI:Create("CheckBox")
            fallbackNotEquippedCb:SetLabel("Use Baseline Alpha Fallback")
            SetCheckboxValue(fallbackNotEquippedCb, "useBaselineAlphaFallbackNotEquipped", FilterEquippable)
            fallbackNotEquippedCb:SetFullWidth(true)
            ApplyCheckboxIndent(fallbackNotEquippedCb, 20)
            WrapBatchCallback(fallbackNotEquippedCb, function(widget, event, val)
                ApplyToEquippable("useBaselineAlphaFallbackNotEquipped", val or nil)
            end)
            scroll:AddChild(fallbackNotEquippedCb)

            -- (?) tooltip
            AttachCheckboxTooltip(fallbackNotEquippedCb, {
                "Use Baseline Alpha Fallback",
                {"Instead of fully hiding, show the button dimmed at the group's baseline alpha. The button keeps its layout position.", 1, 1, 1, true},
            })
        end
    end

    -- Hide While Aura Active (not applicable for items)
    if not isItem then
    -- Batch: disable aura toggles if no selected button has auraTracking
    local auraDisabled
    if isBatch then auraDisabled = not AnySelectedHas(group, "auraTracking")
    else auraDisabled = not buttonData.auraTracking end
    local hideAuraVal
    if isBatch then hideAuraVal = GetBatchFieldValue(group, "hideWhileAuraActive")
    else hideAuraVal = buttonData.hideWhileAuraActive end
    local hideAuraCb = AceGUI:Create("CheckBox")
    hideAuraCb:SetLabel("Hide While Aura Active")
    -- When auraDisabled in batch: use unfiltered reads so stale data is visible
    if isBatch and auraDisabled then
        SetCheckboxValue(hideAuraCb, "hideWhileAuraActive")
    else
        SetCheckboxValue(hideAuraCb, "hideWhileAuraActive", FilterAuraTracking)
    end
    hideAuraCb:SetFullWidth(true)
    if auraDisabled then
        if isBatch then
            if hideAuraVal == false then hideAuraCb:SetDisabled(true) end
        else
            if not hideAuraVal then hideAuraCb:SetDisabled(true) end
        end
    end
    WrapBatchCallback(hideAuraCb, function(widget, event, val)
        if isBatch and auraDisabled then
            -- Stale cleanup: clear this field + dependents on ALL selected buttons
            ApplyToSelected("hideWhileAuraActive", nil)
            ApplyToSelected("useBaselineAlphaFallbackAuraActive", nil)
            ApplyToSelected("hideAuraActiveExceptPandemic", nil)
            CooldownCompanion:RefreshConfigPanel()
            return
        end
        ApplyToAuraTracking("hideWhileAuraActive", val or nil)
        if val then
            ApplyToAuraTracking("hideWhileAuraNotActive", nil)
            ApplyToAuraTracking("useBaselineAlphaFallback", nil)
        end
        CooldownCompanion:RefreshConfigPanel()
    end)
    scroll:AddChild(hideAuraCb)

    -- (?) tooltip
    AttachCheckboxTooltip(hideAuraCb, {
        "Hide While Aura Active",
        {"Requires Aura Tracking to be enabled above.", 1, 1, 1, true},
    })

    -- Shared: is hideWhileAuraActive enabled? (used by pandemic + fallback sub-options)
    local showFallbackAuraActive
    if isBatch then showFallbackAuraActive = AnySelectedHasFiltered(group, "hideWhileAuraActive", FilterAuraTracking)
    else showFallbackAuraActive = buttonData.hideWhileAuraActive end

    -- Except in Pandemic (only for target aura tracking)
    local isTargetAura
    if isBatch then
        isTargetAura = false
        for idx in pairs(CS.selectedButtons) do
            local bd = group.buttons[idx]
            if bd and bd.auraTracking and bd.auraUnit == "target" then
                isTargetAura = true
                break
            end
        end
    else
        isTargetAura = buttonData.auraUnit == "target"
    end
    if isTargetAura then
        local pandemicCb = AceGUI:Create("CheckBox")
        pandemicCb:SetLabel("Except in Pandemic")
        SetCheckboxValue(pandemicCb, "hideAuraActiveExceptPandemic", FilterTargetAuraTracking)
        pandemicCb:SetFullWidth(true)
        ApplyCheckboxIndent(pandemicCb, 20)
        if not showFallbackAuraActive then
            pandemicCb:SetDisabled(true)
        end
        WrapBatchCallback(pandemicCb, function(widget, event, val)
            ApplyToTargetAuraTracking("hideAuraActiveExceptPandemic", val or nil)
        end)
        scroll:AddChild(pandemicCb)

        -- (?) tooltip
        AttachCheckboxTooltip(pandemicCb, {
            "Except in Pandemic",
            {"Shows the button during the pandemic window (last ~30% of the debuff duration) so you know when to reapply.", 1, 1, 1, true},
        })
    end

    -- Baseline Alpha Fallback (only shown when hideWhileAuraActive is checked)
    if showFallbackAuraActive then
        local fallbackAuraCb = AceGUI:Create("CheckBox")
        fallbackAuraCb:SetLabel("Use Baseline Alpha Fallback")
        SetCheckboxValue(fallbackAuraCb, "useBaselineAlphaFallbackAuraActive", FilterAuraTracking)
        fallbackAuraCb:SetFullWidth(true)
        ApplyCheckboxIndent(fallbackAuraCb, 20)
        WrapBatchCallback(fallbackAuraCb, function(widget, event, val)
            ApplyToAuraTracking("useBaselineAlphaFallbackAuraActive", val or nil)
        end)
        scroll:AddChild(fallbackAuraCb)

        -- (?) tooltip
        AttachCheckboxTooltip(fallbackAuraCb, {
            "Use Baseline Alpha Fallback",
            {"Instead of fully hiding, show the button dimmed at the group's baseline alpha. The button keeps its layout position.", 1, 1, 1, true},
        })
    end

    -- Hide While Aura Not Active
    local hideNoAuraVal
    if isBatch then hideNoAuraVal = GetBatchFieldValue(group, "hideWhileAuraNotActive")
    else hideNoAuraVal = buttonData.hideWhileAuraNotActive end
    local hideNoAuraCb = AceGUI:Create("CheckBox")
    hideNoAuraCb:SetLabel("Hide While Aura Not Active")
    if isBatch and auraDisabled then
        SetCheckboxValue(hideNoAuraCb, "hideWhileAuraNotActive")
    else
        SetCheckboxValue(hideNoAuraCb, "hideWhileAuraNotActive", FilterAuraTracking)
    end
    hideNoAuraCb:SetFullWidth(true)
    if auraDisabled then
        if isBatch then
            if hideNoAuraVal == false then hideNoAuraCb:SetDisabled(true) end
        else
            if not hideNoAuraVal then hideNoAuraCb:SetDisabled(true) end
        end
    end
    WrapBatchCallback(hideNoAuraCb, function(widget, event, val)
        if isBatch and auraDisabled then
            ApplyToSelected("hideWhileAuraNotActive", nil)
            ApplyToSelected("useBaselineAlphaFallback", nil)
            CooldownCompanion:RefreshConfigPanel()
            return
        end
        ApplyToAuraTracking("hideWhileAuraNotActive", val or nil)
        if val then
            ApplyToAuraTracking("hideWhileAuraActive", nil)
            ApplyToAuraTracking("useBaselineAlphaFallbackAuraActive", nil)
            ApplyToAuraTracking("hideAuraActiveExceptPandemic", nil)
        end
        CooldownCompanion:RefreshConfigPanel()
    end)
    scroll:AddChild(hideNoAuraCb)

    -- (?) tooltip
    AttachCheckboxTooltip(hideNoAuraCb, {
        "Hide While Aura Not Active",
        {"Requires Aura Tracking to be enabled above.", 1, 1, 1, true},
    })

    -- Baseline Alpha Fallback (only shown when hideWhileAuraNotActive is checked)
    local showFallbackAuraNotActive
    if isBatch then showFallbackAuraNotActive = AnySelectedHasFiltered(group, "hideWhileAuraNotActive", FilterAuraTracking)
    else showFallbackAuraNotActive = buttonData.hideWhileAuraNotActive end
    if showFallbackAuraNotActive then
        local fallbackCb = AceGUI:Create("CheckBox")
        fallbackCb:SetLabel("Use Baseline Alpha Fallback")
        SetCheckboxValue(fallbackCb, "useBaselineAlphaFallback", FilterAuraTracking)
        fallbackCb:SetFullWidth(true)
        ApplyCheckboxIndent(fallbackCb, 20)
        WrapBatchCallback(fallbackCb, function(widget, event, val)
            ApplyToAuraTracking("useBaselineAlphaFallback", val or nil)
        end)
        scroll:AddChild(fallbackCb)

        -- (?) tooltip
        AttachCheckboxTooltip(fallbackCb, {
            "Use Baseline Alpha Fallback",
            {"Instead of fully hiding, show the button dimmed at the group's baseline alpha. The button keeps its layout position.", 1, 1, 1, true},
        })
    end

    -- Saturate While Aura Not Active (passive aura entries only — inverted toggle)
    local anyPassiveAura
    if isBatch then anyPassiveAura = AnySelectedHas(group, "isPassive")
    else anyPassiveAura = buttonData.isPassive end
    if anyPassiveAura then
        local satNoAuraCb = AceGUI:Create("CheckBox")
        satNoAuraCb:SetLabel("Saturate While Aura Not Active")
        SetCheckboxValue(satNoAuraCb, "saturateWhileAuraNotActive", FilterAuraTracking)
        satNoAuraCb:SetFullWidth(true)
        WrapBatchCallback(satNoAuraCb, function(widget, event, val)
            ApplyToAuraTracking("saturateWhileAuraNotActive", val or nil)
        end)
        scroll:AddChild(satNoAuraCb)

        -- (?) tooltip
        AttachCheckboxTooltip(satNoAuraCb, {
            "Saturate While Aura Not Active",
            {"Keep the icon at full color even when the tracked aura is missing.", 1, 1, 1, true},
        })
    end

    -- Desaturate While Aura Not Active (non-passive aura entries)
    local allPassiveAura
    if isBatch then allPassiveAura = AllSelectedAre(group, "isPassive")
    else allPassiveAura = buttonData.isPassive end
    if not allPassiveAura then
        local desatNoAuraVal
        if isBatch then desatNoAuraVal = GetBatchFieldValue(group, "desaturateWhileAuraNotActive")
        else desatNoAuraVal = buttonData.desaturateWhileAuraNotActive end
        local desatNoAuraCb = AceGUI:Create("CheckBox")
        desatNoAuraCb:SetLabel("Desaturate While Aura Not Active")
        if isBatch and auraDisabled then
            SetCheckboxValue(desatNoAuraCb, "desaturateWhileAuraNotActive")
        else
            SetCheckboxValue(desatNoAuraCb, "desaturateWhileAuraNotActive", FilterAuraTracking)
        end
        desatNoAuraCb:SetFullWidth(true)
        if auraDisabled then
            if isBatch then
                if desatNoAuraVal == false then desatNoAuraCb:SetDisabled(true) end
            else
                if not desatNoAuraVal then desatNoAuraCb:SetDisabled(true) end
            end
        end
        WrapBatchCallback(desatNoAuraCb, function(widget, event, val)
            if isBatch and auraDisabled then
                ApplyToSelected("desaturateWhileAuraNotActive", nil)
                CooldownCompanion:RefreshConfigPanel()
                return
            end
            ApplyToAuraTracking("desaturateWhileAuraNotActive", val or nil)
        end)
        scroll:AddChild(desatNoAuraCb)

        -- (?) tooltip
        AttachCheckboxTooltip(desatNoAuraCb, {
            "Desaturate While Aura Not Active",
            {"Requires Aura Tracking to be enabled above.", 1, 1, 1, true},
        })
    end

    -- Warning: aura-based toggles enabled but auraTracking is off
    local hasAuraToggle, hasAuraTracking
    if isBatch then
        hasAuraToggle = AnySelectedHas(group, "hideWhileAuraNotActive") or AnySelectedHas(group, "hideWhileAuraActive")
        hasAuraTracking = AnySelectedHas(group, "auraTracking")
    else
        hasAuraToggle = buttonData.hideWhileAuraNotActive or buttonData.hideWhileAuraActive
        hasAuraTracking = buttonData.auraTracking
    end
    if not isItem and hasAuraToggle and not hasAuraTracking then
        local warnSpacer = AceGUI:Create("Label")
        warnSpacer:SetText(" ")
        warnSpacer:SetFullWidth(true)
        scroll:AddChild(warnSpacer)

        local warnLabel = AceGUI:Create("Label")
        warnLabel:SetText("|cffff8800Warning: Aura Tracking is not enabled. Enable it above for aura-based visibility to take effect.|r")
        warnLabel:SetFullWidth(true)
        scroll:AddChild(warnLabel)
    end
    end -- not isItem

    end -- not visCollapsed

    ------------------------------------------------------------------------
    -- TALENT CONDITIONS (independent section, not nested under Visibility Rules)
    ------------------------------------------------------------------------

    local talentHeading = AceGUI:Create("Heading")
    talentHeading:SetText("Talent Conditions")
    ColorHeading(talentHeading)
    talentHeading:SetFullWidth(true)
    scroll:AddChild(talentHeading)

    local talentKey = isBatch
        and (CS.selectedGroup .. "_batch_talentcondition")
        or  (CS.selectedGroup .. "_" .. CS.selectedButton .. "_talentcondition")
    local talentCollapsed = CS.collapsedSections[talentKey]
    local talentCollapseBtn = AttachCollapseButton(talentHeading, talentCollapsed, function()
        CS.collapsedSections[talentKey] = not CS.collapsedSections[talentKey]
        CooldownCompanion:RefreshConfigPanel()
    end)

    local talentInfoBtn = CreateInfoButton(talentHeading.frame, talentCollapseBtn, "LEFT", "RIGHT", 2, 0, {
        "Talent Conditions",
        {"Show or hide this button based on which talents you have selected. If you add multiple conditions, all of them must pass.", 1, 1, 1, true},
    }, infoButtons)
    talentHeading.right:ClearAllPoints()
    talentHeading.right:SetPoint("RIGHT", talentHeading.frame, "RIGHT", -3, 0)
    talentHeading.right:SetPoint("LEFT", talentInfoBtn, "RIGHT", 4, 0)

    -- Determine current talent condition state
    local conditions = buttonData.talentConditions
    local condCount = conditions and #conditions or 0
    local hasTalent
    if isBatch then
        hasTalent = GetBatchFieldValue(group, "talentConditions")
    else
        hasTalent = condCount > 0
    end

    if talentCollapsed then
        local summaryLabel = AceGUI:Create("Label")
        if isBatch and hasTalent == nil then
            summaryLabel:SetText("|cff888888Multiple conditions|r")
        elseif hasTalent and condCount > 0 then
            local firstCond = conditions[1]
            local displayIcon = firstCond.spellID and C_Spell.GetSpellTexture(firstCond.spellID)
            if displayIcon then
                summaryLabel:SetImage(displayIcon, 0.08, 0.92, 0.08, 0.92)
                summaryLabel:SetImageSize(16, 16)
            end
            if condCount == 1 then
                local showText = (firstCond.show == "not_taken") and " (not taken)" or " (taken)"
                summaryLabel:SetText(GetConditionDisplayName(firstCond) .. showText)
            else
                summaryLabel:SetText(condCount .. " conditions" .. GetConditionListContextSuffix(conditions))
            end
        else
            summaryLabel:SetText("|cff888888None|r")
        end
        summaryLabel:SetFullWidth(true)
        scroll:AddChild(summaryLabel)
    end

    if not talentCollapsed then

    -- Condition list display
    if isBatch and hasTalent == nil then
        local mixedLabel = AceGUI:Create("Label")
        mixedLabel:SetText("|cff888888Multiple conditions — pick or clear to unify.|r")
        mixedLabel:SetFullWidth(true)
        scroll:AddChild(mixedLabel)
    elseif condCount > 0 then
        local cache = CooldownCompanion._talentNodeCache
        local currentSpecID = CooldownCompanion._currentSpecId
        local currentHeroSubTreeID = CooldownCompanion._currentHeroSpecId
        for _, cond in ipairs(conditions) do
            local condLabel = AceGUI:Create("Label")
            local displayIcon = cond.spellID and C_Spell.GetSpellTexture(cond.spellID)
            if displayIcon then
                condLabel:SetImage(displayIcon, 0.08, 0.92, 0.08, 0.92)
                condLabel:SetImageSize(16, 16)
            end
            local nameText = GetConditionDisplayName(cond)
            local showText, showColor
            if cond.show == "not_taken" then
                showText = " |cffff4d4d(not taken)|r"
            else
                showText = " |cff33dd33(taken)|r"
            end
            condLabel:SetText("|cffFFFFFF" .. nameText .. "|r" .. showText)
            condLabel:SetFullWidth(true)
            scroll:AddChild(condLabel)

            -- Per-condition stale node warning
            local matchesCurrentScope = (not cond.specID or cond.specID == currentSpecID)
                and (not cond.heroSubTreeID or cond.heroSubTreeID == currentHeroSubTreeID)
            if not isBatch and matchesCurrentScope and cache and not cache[cond.nodeID] then
                local warnLabel = AceGUI:Create("Label")
                warnLabel:SetText("|cffff8800  This talent is not in your current active tree, so it behaves as not taken right now.|r")
                warnLabel:SetFullWidth(true)
                scroll:AddChild(warnLabel)
            end
        end
    else
        local emptyLabel = AceGUI:Create("Label")
        emptyLabel:SetText("|cff888888No talent conditions set.|r")
        emptyLabel:SetFullWidth(true)
        scroll:AddChild(emptyLabel)
    end

    -- Button row: side-by-side Pick + Clear using Flow layout
    local talentBtnRow = AceGUI:Create("SimpleGroup")
    talentBtnRow:SetFullWidth(true)
    talentBtnRow:SetLayout("Flow")

    local pickBtn = AceGUI:Create("Button")
    pickBtn:SetText(condCount > 0 and "Edit" or "Pick Talents")
    pickBtn:SetRelativeWidth(hasTalent and 0.5 or 1)
    pickBtn:SetCallback("OnClick", function()
        local initialConditions = not isBatch and buttonData.talentConditions or nil
        CooldownCompanion:OpenTalentPicker(function(results)
            if results then
                local normalized, changed = CooldownCompanion:NormalizeTalentConditions(results)
                if changed then
                    results = normalized
                end
            end
            if results then
                -- Deep-copy each condition for batch mode safety
                if CS.selectedButtons then
                    local count = 0
                    for _ in pairs(CS.selectedButtons) do count = count + 1 end
                    if count >= 2 then
                        for idx in pairs(CS.selectedButtons) do
                            local bd = group.buttons[idx]
                            if bd then
                                local copy = {}
                                for i, cond in ipairs(results) do
                                    copy[i] = {
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
                                bd.talentConditions = copy
                                -- Clean old fields for migration safety
                                bd.talentNodeID  = nil
                                bd.talentEntryID = nil
                                bd.talentSpellID = nil
                                bd.talentName    = nil
                                bd.talentShow    = nil
                            end
                        end
                    else
                        buttonData.talentConditions = results
                        buttonData.talentNodeID  = nil
                        buttonData.talentEntryID = nil
                        buttonData.talentSpellID = nil
                        buttonData.talentName    = nil
                        buttonData.talentShow    = nil
                    end
                else
                    buttonData.talentConditions = results
                    buttonData.talentNodeID  = nil
                    buttonData.talentEntryID = nil
                    buttonData.talentSpellID = nil
                    buttonData.talentName    = nil
                    buttonData.talentShow    = nil
                end
            else
                -- Clear all
                ApplyToSelected("talentConditions", nil)
                ApplyToSelected("talentNodeID", nil)
                ApplyToSelected("talentEntryID", nil)
                ApplyToSelected("talentSpellID", nil)
                ApplyToSelected("talentName", nil)
                ApplyToSelected("talentShow", nil)
            end
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end, initialConditions, group)
    end)
    talentBtnRow:AddChild(pickBtn)

    -- Clear All button (only when conditions exist)
    if hasTalent then
        local clearBtn = AceGUI:Create("Button")
        clearBtn:SetText("Clear")
        clearBtn:SetRelativeWidth(0.5)
        clearBtn:SetCallback("OnClick", function()
            ApplyToSelected("talentConditions", nil)
            ApplyToSelected("talentNodeID", nil)
            ApplyToSelected("talentEntryID", nil)
            ApplyToSelected("talentSpellID", nil)
            ApplyToSelected("talentName", nil)
            ApplyToSelected("talentShow", nil)
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        talentBtnRow:AddChild(clearBtn)
    end

    scroll:AddChild(talentBtnRow)

    end -- not talentCollapsed

end

------------------------------------------------------------------------
-- LOAD CONDITIONS TAB
------------------------------------------------------------------------

local function BuildLoadConditionsTab(container)
    for _, btn in ipairs(tabInfoButtons) do
        btn:ClearAllPoints()
        btn:Hide()
        btn:SetParent(nil)
    end
    wipe(tabInfoButtons)
    for _, elem in ipairs(appearanceTabElements) do
        elem:ClearAllPoints()
        elem:Hide()
        elem:SetParent(nil)
    end
    wipe(appearanceTabElements)

    if not CS.selectedGroup then return end
    local groupId = CS.selectedGroup
    local group = CooldownCompanion.db.profile.groups[groupId]
    if not group then return end

    -- Ensure loadConditions table exists
    if not group.loadConditions then
        group.loadConditions = {
            raid = false, dungeon = false, delve = false, battleground = false,
            arena = false, openWorld = false, rested = false, petBattle = true,
            vehicleUI = true,
        }
    end
    local lc = group.loadConditions
    local effectiveSpecs, inheritedSpecFilter = CooldownCompanion:GetEffectiveSpecs(group)
    local effectiveHeroTalents, inheritedHeroFilter = CooldownCompanion:GetEffectiveHeroTalents(group)

    -- Look up parent container's load conditions for inheritance
    local containerLc = nil
    if group.parentContainerId then
        local containers = CooldownCompanion.db.profile.groupContainers
        local parentContainer = containers and containers[group.parentContainerId]
        if parentContainer then
            containerLc = parentContainer.loadConditions
        end
    end

    local function isContainerConditionActive(key, defaultVal)
        if not containerLc then return false end
        local val = containerLc[key]
        if val == nil then val = defaultVal or false end
        return val
    end

    local function CreateLoadConditionToggle(label, key, defaultVal)
        local cb = AceGUI:Create("CheckBox")
        cb:SetLabel(label)
        cb:SetFullWidth(true)
        if isContainerConditionActive(key, defaultVal) then
            cb:SetValue(true)
            cb:SetDisabled(true)
        else
            local val = lc[key]
            if val == nil then val = defaultVal or false end
            cb:SetValue(val)
            cb:SetCallback("OnValueChanged", function(widget, event, newVal)
                lc[key] = newVal
                CooldownCompanion:RefreshGroupFrame(groupId)
            end)
        end
        return cb
    end

    local heading = AceGUI:Create("Heading")
    heading:SetText("Do Not Load When In")
    ColorHeading(heading)
    heading:SetFullWidth(true)
    container:AddChild(heading)

    local instanceCollapsed = CS.collapsedSections["loadconditions_instance"]
    AttachCollapseButton(heading, instanceCollapsed, function()
        CS.collapsedSections["loadconditions_instance"] = not CS.collapsedSections["loadconditions_instance"]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not instanceCollapsed then
    local conditions = {
        { key = "raid",          label = "Raid" },
        { key = "dungeon",       label = "Dungeon" },
        { key = "delve",         label = "Delve" },
        { key = "battleground",  label = "Battleground" },
        { key = "arena",         label = "Arena" },
        { key = "openWorld",     label = "Open World" },
        { key = "rested",        label = "Rested Area" },
        { key = "petBattle",     label = "Pet Battle", default = true },
        { key = "vehicleUI",    label = "Vehicle / Override UI", default = true },
    }

    if containerLc then
        local anyInherited = false
        for _, cond in ipairs(conditions) do
            if isContainerConditionActive(cond.key, cond.default) then
                anyInherited = true
                break
            end
        end
        if anyInherited then
            local inheritedLabel = AceGUI:Create("Label")
            inheritedLabel:SetText("|cff888888Some conditions inherited from group settings.|r")
            inheritedLabel:SetFullWidth(true)
            container:AddChild(inheritedLabel)
        end
    end

    for _, cond in ipairs(conditions) do
        container:AddChild(CreateLoadConditionToggle(cond.label, cond.key, cond.default))
    end
    end -- not instanceCollapsed

    -- Specialization heading
    local specHeading = AceGUI:Create("Heading")
    specHeading:SetText("Specialization Filter")
    ColorHeading(specHeading)
    specHeading:SetFullWidth(true)
    container:AddChild(specHeading)

    local specCollapsed = CS.collapsedSections["loadconditions_spec"]
    AttachCollapseButton(specHeading, specCollapsed, function()
        CS.collapsedSections["loadconditions_spec"] = not CS.collapsedSections["loadconditions_spec"]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not specCollapsed then
    if inheritedSpecFilter or inheritedHeroFilter then
        local inheritedLabel = AceGUI:Create("Label")
        inheritedLabel:SetText("|cff888888Some filters inherited from group settings.|r")
        inheritedLabel:SetFullWidth(true)
        container:AddChild(inheritedLabel)
    end

    -- Current class spec checkboxes
    local numSpecs = GetNumSpecializations()
    local configID = C_ClassTalents.GetActiveConfigID()
    for i = 1, numSpecs do
        local specId, name, _, icon = C_SpecializationInfo.GetSpecializationInfo(i)
        if specId then
            local cb = AceGUI:Create("CheckBox")
            cb:SetLabel(name)
            if icon then cb:SetImage(icon, 0.08, 0.92, 0.08, 0.92) end
            cb:SetFullWidth(true)
            if inheritedSpecFilter then
                cb:SetValue(effectiveSpecs and effectiveSpecs[specId] or false)
            else
                cb:SetValue(group.specs and group.specs[specId] or false)
            end
            if inheritedSpecFilter then
                cb:SetDisabled(true)
            else
                cb:SetCallback("OnValueChanged", function(widget, event, value)
                    if value then
                        if not group.specs then group.specs = {} end
                        group.specs[specId] = true
                    else
                        if group.specs then
                            group.specs[specId] = nil
                            if not next(group.specs) then
                                group.specs = nil
                            end
                        end
                        CooldownCompanion:CleanHeroTalentsForSpec(group, specId)
                    end
                    CooldownCompanion:RefreshGroupFrame(groupId)
                    CooldownCompanion:RefreshConfigPanel()
                end)
            end
            container:AddChild(cb)
            ApplyCheckboxIndent(cb, 0)

            -- Hero talent sub-tree checkboxes (indented, only when spec is checked)
            BuildHeroTalentSubTreeCheckboxes(container, group, configID, specId, 20, groupId, {
                specsSource = effectiveSpecs,
                heroTalentsSource = effectiveHeroTalents,
                useHeroTalentsSource = inheritedHeroFilter,
                disableToggles = inheritedHeroFilter,
            })
        end
    end

    -- Foreign specs (from global groups that may have specs from other classes)
    local playerSpecIds = {}
    for i = 1, numSpecs do
        local specId = C_SpecializationInfo.GetSpecializationInfo(i)
        if specId then playerSpecIds[specId] = true end
    end

    local foreignSpecs = {}
    if effectiveSpecs then
        for specId in pairs(effectiveSpecs) do
            if not playerSpecIds[specId] then
                table.insert(foreignSpecs, specId)
            end
        end
    end

    if #foreignSpecs > 0 then
        table.sort(foreignSpecs)
        for _, specId in ipairs(foreignSpecs) do
            local _, name, _, icon = GetSpecializationInfoForSpecID(specId)
            if name then
                local fcb = AceGUI:Create("CheckBox")
                fcb:SetLabel(name)
                if icon then fcb:SetImage(icon, 0.08, 0.92, 0.08, 0.92) end
                fcb:SetFullWidth(true)
                fcb:SetValue(true)
                if inheritedSpecFilter then
                    fcb:SetDisabled(true)
                else
                    fcb:SetCallback("OnValueChanged", function(widget, event, value)
                        if not value then
                            if group.specs then
                                group.specs[specId] = nil
                                if not next(group.specs) then
                                    group.specs = nil
                                end
                            end
                        else
                            if not group.specs then group.specs = {} end
                            group.specs[specId] = true
                        end
                        CooldownCompanion:RefreshGroupFrame(groupId)
                        CooldownCompanion:RefreshConfigPanel()
                    end)
                end
                container:AddChild(fcb)
                ApplyCheckboxIndent(fcb, 0)
            end
        end
    end
    end -- not specCollapsed
end


------------------------------------------------------------------------
-- EXPORTS
------------------------------------------------------------------------
ST._BuildVisibilitySettings = BuildVisibilitySettings
ST._BuildLoadConditionsTab = BuildLoadConditionsTab
ST._GetConditionDisplayName = GetConditionDisplayName
ST._GetConditionListContextSuffix = GetConditionListContextSuffix
