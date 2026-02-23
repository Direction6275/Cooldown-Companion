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

    -- Filtered apply: only write to non-equippable items (charge/stack toggles).
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
    if not allPassive then
    local hideCDCb = AceGUI:Create("CheckBox")
    hideCDCb:SetLabel("Hide While On Cooldown")
    SetCheckboxValue(hideCDCb, "hideWhileOnCooldown")
    hideCDCb:SetFullWidth(true)
    WrapBatchCallback(hideCDCb, function(widget, event, val)
        ApplyToSelected("hideWhileOnCooldown", val or nil)
        if val then
            ApplyToSelected("hideWhileNotOnCooldown", nil)
        end
        CooldownCompanion:RefreshConfigPanel()
    end)
    scroll:AddChild(hideCDCb)

    -- Hide While Not On Cooldown
    local hideNotCDCb = AceGUI:Create("CheckBox")
    hideNotCDCb:SetLabel("Hide While Not On Cooldown")
    SetCheckboxValue(hideNotCDCb, "hideWhileNotOnCooldown")
    hideNotCDCb:SetFullWidth(true)
    WrapBatchCallback(hideNotCDCb, function(widget, event, val)
        ApplyToSelected("hideWhileNotOnCooldown", val or nil)
        if val then
            ApplyToSelected("hideWhileOnCooldown", nil)
        end
        CooldownCompanion:RefreshConfigPanel()
    end)
    scroll:AddChild(hideNotCDCb)

    -- Hide While Unusable
    local hideUnusableCb = AceGUI:Create("CheckBox")
    hideUnusableCb:SetLabel("Hide While Unusable")
    SetCheckboxValue(hideUnusableCb, "hideWhileUnusable")
    hideUnusableCb:SetFullWidth(true)
    WrapBatchCallback(hideUnusableCb, function(widget, event, val)
        ApplyToSelected("hideWhileUnusable", val or nil)
        CooldownCompanion:RefreshConfigPanel()
    end)
    scroll:AddChild(hideUnusableCb)

    -- (?) tooltip
    CreateInfoButton(hideUnusableCb.frame, hideUnusableCb.checkbg, "LEFT", "RIGHT", hideUnusableCb.text:GetStringWidth() + 4, 0, {
        "Hide While Unusable",
        {"Uses the same logic as unusable dimming, but completely hides the button instead of dimming it.", 1, 1, 1, true},
    }, infoButtons)

    end -- not allPassive

    -- Item-specific zero charges/stacks visibility toggles
    -- Batch: show if any selected non-equippable item exists
    local showItemChargeSection
    if isBatch then showItemChargeSection = isItem and AnySelectedNonEquippable(group)
    else showItemChargeSection = isItem and not CooldownCompanion.IsItemEquippable(buttonData) end
    if showItemChargeSection then
        -- Batch: show charges section if any selected has charges
        local hasCharges
        if isBatch then hasCharges = AnySelectedHas(group, "hasCharges")
        else hasCharges = buttonData.hasCharges end
        if hasCharges then
            -- Hide While At Zero Charges
            local hideZeroChargesCb = AceGUI:Create("CheckBox")
            hideZeroChargesCb:SetLabel("Hide While At Zero Charges")
            SetCheckboxValue(hideZeroChargesCb, "hideWhileZeroCharges", FilterNonEquippable)
            hideZeroChargesCb:SetFullWidth(true)
            WrapBatchCallback(hideZeroChargesCb, function(widget, event, val)
                ApplyToNonEquippable("hideWhileZeroCharges", val or nil)
                if val then
                    ApplyToNonEquippable("desaturateWhileZeroCharges", nil)
                else
                    ApplyToNonEquippable("useBaselineAlphaFallbackZeroCharges", nil)
                end
                CooldownCompanion:RefreshConfigPanel()
            end)
            scroll:AddChild(hideZeroChargesCb)

            -- Baseline Alpha Fallback (nested under hideWhileZeroCharges)
            -- Batch: show if any selected has it on
            local showFallbackZeroCharges
            if isBatch then showFallbackZeroCharges = AnySelectedHasFiltered(group, "hideWhileZeroCharges", FilterNonEquippable)
            else showFallbackZeroCharges = buttonData.hideWhileZeroCharges end
            if showFallbackZeroCharges then
                local fallbackZeroChargesCb = AceGUI:Create("CheckBox")
                fallbackZeroChargesCb:SetLabel("Use Baseline Alpha Fallback")
                SetCheckboxValue(fallbackZeroChargesCb, "useBaselineAlphaFallbackZeroCharges", FilterNonEquippable)
                fallbackZeroChargesCb:SetFullWidth(true)
                WrapBatchCallback(fallbackZeroChargesCb, function(widget, event, val)
                    ApplyToNonEquippable("useBaselineAlphaFallbackZeroCharges", val or nil)
                end)
                scroll:AddChild(fallbackZeroChargesCb)

                -- (?) tooltip
                CreateInfoButton(fallbackZeroChargesCb.frame, fallbackZeroChargesCb.checkbg, "LEFT", "RIGHT", fallbackZeroChargesCb.text:GetStringWidth() + 4, 0, {
                    "Use Baseline Alpha Fallback",
                    {"Instead of fully hiding, show the button dimmed at the group's baseline alpha. The button keeps its layout position.", 1, 1, 1, true},
                }, infoButtons)
            end

            -- Desaturate While At Zero Charges
            local desatZeroChargesCb = AceGUI:Create("CheckBox")
            desatZeroChargesCb:SetLabel("Desaturate While At Zero Charges")
            SetCheckboxValue(desatZeroChargesCb, "desaturateWhileZeroCharges", FilterNonEquippable)
            desatZeroChargesCb:SetFullWidth(true)
            WrapBatchCallback(desatZeroChargesCb, function(widget, event, val)
                ApplyToNonEquippable("desaturateWhileZeroCharges", val or nil)
                if val then
                    ApplyToNonEquippable("hideWhileZeroCharges", nil)
                    ApplyToNonEquippable("useBaselineAlphaFallbackZeroCharges", nil)
                end
                CooldownCompanion:RefreshConfigPanel()
            end)
            scroll:AddChild(desatZeroChargesCb)
        end

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
                WrapBatchCallback(fallbackZeroStacksCb, function(widget, event, val)
                    ApplyToNonEquippable("useBaselineAlphaFallbackZeroStacks", val or nil)
                end)
                scroll:AddChild(fallbackZeroStacksCb)

                -- (?) tooltip
                CreateInfoButton(fallbackZeroStacksCb.frame, fallbackZeroStacksCb.checkbg, "LEFT", "RIGHT", fallbackZeroStacksCb.text:GetStringWidth() + 4, 0, {
                    "Use Baseline Alpha Fallback",
                    {"Instead of fully hiding, show the button dimmed at the group's baseline alpha. The button keeps its layout position.", 1, 1, 1, true},
                }, infoButtons)
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
            WrapBatchCallback(fallbackNotEquippedCb, function(widget, event, val)
                ApplyToEquippable("useBaselineAlphaFallbackNotEquipped", val or nil)
            end)
            scroll:AddChild(fallbackNotEquippedCb)

            -- (?) tooltip
            CreateInfoButton(fallbackNotEquippedCb.frame, fallbackNotEquippedCb.checkbg, "LEFT", "RIGHT", fallbackNotEquippedCb.text:GetStringWidth() + 4, 0, {
                "Use Baseline Alpha Fallback",
                {"Instead of fully hiding, show the button dimmed at the group's baseline alpha. The button keeps its layout position.", 1, 1, 1, true},
            }, infoButtons)
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
    CreateInfoButton(hideAuraCb.frame, hideAuraCb.checkbg, "LEFT", "RIGHT", hideAuraCb.text:GetStringWidth() + 4, 0, {
        "Hide While Aura Active",
        {"Requires Aura Tracking to be enabled above.", 1, 1, 1, true},
    }, infoButtons)

    -- Baseline Alpha Fallback (only shown when hideWhileAuraActive is checked)
    local showFallbackAuraActive
    if isBatch then showFallbackAuraActive = AnySelectedHasFiltered(group, "hideWhileAuraActive", FilterAuraTracking)
    else showFallbackAuraActive = buttonData.hideWhileAuraActive end
    if showFallbackAuraActive then
        local fallbackAuraCb = AceGUI:Create("CheckBox")
        fallbackAuraCb:SetLabel("Use Baseline Alpha Fallback")
        SetCheckboxValue(fallbackAuraCb, "useBaselineAlphaFallbackAuraActive", FilterAuraTracking)
        fallbackAuraCb:SetFullWidth(true)
        WrapBatchCallback(fallbackAuraCb, function(widget, event, val)
            ApplyToAuraTracking("useBaselineAlphaFallbackAuraActive", val or nil)
        end)
        scroll:AddChild(fallbackAuraCb)

        -- (?) tooltip
        CreateInfoButton(fallbackAuraCb.frame, fallbackAuraCb.checkbg, "LEFT", "RIGHT", fallbackAuraCb.text:GetStringWidth() + 4, 0, {
            "Use Baseline Alpha Fallback",
            {"Instead of fully hiding, show the button dimmed at the group's baseline alpha. The button keeps its layout position.", 1, 1, 1, true},
        }, infoButtons)
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
        end
        CooldownCompanion:RefreshConfigPanel()
    end)
    scroll:AddChild(hideNoAuraCb)

    -- (?) tooltip
    CreateInfoButton(hideNoAuraCb.frame, hideNoAuraCb.checkbg, "LEFT", "RIGHT", hideNoAuraCb.text:GetStringWidth() + 4, 0, {
        "Hide While Aura Not Active",
        {"Requires Aura Tracking to be enabled above.", 1, 1, 1, true},
    }, infoButtons)

    -- Desaturate While Aura Not Active (spell+aura only; passive buttons always desaturate)
    -- Batch: show if not all selected are passive
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
        CreateInfoButton(desatNoAuraCb.frame, desatNoAuraCb.checkbg, "LEFT", "RIGHT", desatNoAuraCb.text:GetStringWidth() + 4, 0, {
            "Desaturate While Aura Not Active",
            {"Requires Aura Tracking to be enabled above.", 1, 1, 1, true},
        }, infoButtons)
    end

    -- Baseline Alpha Fallback (only shown when hideWhileAuraNotActive is checked)
    local showFallbackAuraNotActive
    if isBatch then showFallbackAuraNotActive = AnySelectedHasFiltered(group, "hideWhileAuraNotActive", FilterAuraTracking)
    else showFallbackAuraNotActive = buttonData.hideWhileAuraNotActive end
    if showFallbackAuraNotActive then
        local fallbackCb = AceGUI:Create("CheckBox")
        fallbackCb:SetLabel("Use Baseline Alpha Fallback")
        SetCheckboxValue(fallbackCb, "useBaselineAlphaFallback", FilterAuraTracking)
        fallbackCb:SetFullWidth(true)
        WrapBatchCallback(fallbackCb, function(widget, event, val)
            ApplyToAuraTracking("useBaselineAlphaFallback", val or nil)
        end)
        scroll:AddChild(fallbackCb)

        -- (?) tooltip
        CreateInfoButton(fallbackCb.frame, fallbackCb.checkbg, "LEFT", "RIGHT", fallbackCb.text:GetStringWidth() + 4, 0, {
            "Use Baseline Alpha Fallback",
            {"Instead of fully hiding, show the button dimmed at the group's baseline alpha. The button keeps its layout position.", 1, 1, 1, true},
        }, infoButtons)
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
        }
    end
    local lc = group.loadConditions

    local function CreateLoadConditionToggle(label, key, defaultVal)
        local cb = AceGUI:Create("CheckBox")
        cb:SetLabel(label)
        local val = lc[key]
        if val == nil then val = defaultVal or false end
        cb:SetValue(val)
        cb:SetFullWidth(true)
        cb:SetCallback("OnValueChanged", function(widget, event, newVal)
            lc[key] = newVal
            CooldownCompanion:RefreshGroupFrame(groupId)
        end)
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
    }

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
            cb:SetValue(group.specs and group.specs[specId] or false)
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
            container:AddChild(cb)
            cb.checkbg:SetPoint("TOPLEFT")

            -- Hero talent sub-tree checkboxes (indented, only when spec is checked)
            BuildHeroTalentSubTreeCheckboxes(container, group, configID, specId, 20, groupId)
        end
    end

    -- Foreign specs (from global groups that may have specs from other classes)
    local playerSpecIds = {}
    for i = 1, numSpecs do
        local specId = C_SpecializationInfo.GetSpecializationInfo(i)
        if specId then playerSpecIds[specId] = true end
    end

    local foreignSpecs = {}
    if group.specs then
        for specId in pairs(group.specs) do
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
                container:AddChild(fcb)
                fcb.checkbg:SetPoint("TOPLEFT")
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
