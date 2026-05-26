--[[
    CooldownCompanion - ButtonFrame/CooldownUpdate
    Main per-tick cooldown orchestrator (UpdateButtonCooldown)
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CooldownLogic = ST.CooldownLogic
local EntryRuntime = ST.EntryRuntime

-- Localize frequently-used globals
local GetTime = GetTime
local tonumber = tonumber
local tostring = tostring
local ipairs = ipairs
local type = type
local issecretvalue = issecretvalue
local math_max = math.max

-- Imports from Glows
local GetViewerAuraStackText = ST._GetViewerAuraStackText

-- Imports from Visibility
local EvaluateButtonVisibility = ST._EvaluateButtonVisibility

-- Pre-defined color constant tables to avoid per-tick allocation.
-- IMPORTANT: These tables are read-only — never write to their indices.
local DEFAULT_WHITE = {1, 1, 1, 1}

-- APIs for text-mode conditional tokens
local C_Spell_IsSpellUsable = C_Spell.IsSpellUsable
local IsUsableItem = C_Item.IsUsableItem
local IsItemInRange = C_Item.IsItemInRange
local InCombatLockdown = InCombatLockdown
local UnitCanAttack = UnitCanAttack

-- Imports from Utils
local HasTooltipCooldown = ST.HasTooltipCooldown

-- Imports from Preview
local GetConditionalVisualPreview = ST._GetConditionalVisualPreview

-- Imports from Tracking
local UpdateChargeTracking = ST._UpdateChargeTracking
local UpdateDisplayCountTracking = ST._UpdateDisplayCountTracking
local UpdateItemChargeTracking = ST._UpdateItemChargeTracking

-- Imports from IconMode
local ApplyIconCountTextStyle = ST._ApplyIconCountTextStyle
local UpdateIconModeVisuals = ST._UpdateIconModeVisuals
local UpdateIconModeGlows = ST._UpdateIconModeGlows
local CacheButtonBindingKeys = ST._CacheButtonBindingKeys
local ClearIconFillVisualState = ST._ClearIconFillVisualState

-- Imports from BarMode
local ApplyBarCountTextStyle = ST._ApplyBarCountTextStyle
local UpdateBarDisplay = ST._UpdateBarDisplay
local IsConfigButtonForceVisible = ST.IsConfigButtonForceVisible

-- Imports from TextMode
local UpdateTextDisplay = ST._UpdateTextDisplay

-- IsItemEquippable from Helpers (exported on CooldownCompanion)
local IsItemEquippable = CooldownCompanion.IsItemEquippable
local UsesChargeBehavior = CooldownCompanion.UsesChargeBehavior
local UsesChargeTextLane = CooldownCompanion.UsesChargeTextLane
local ResolveItemFallback = CooldownCompanion.ResolveItemFallback
local HasCastCountText = CooldownCompanion.HasCastCountText
local GetCastCountSpellID = CooldownCompanion.GetCastCountSpellID
local GetConditionalCastCountSpellID = CooldownCompanion.GetConditionalCastCountSpellID
local COOLDOWN_STATE_READY = CooldownLogic.STATE_READY
local COOLDOWN_STATE_GCD = CooldownLogic.STATE_GCD
local COOLDOWN_STATE_COOLDOWN = CooldownLogic.STATE_COOLDOWN
local CHARGE_STATE_FULL = CooldownLogic.CHARGE_STATE_FULL
local CHARGE_STATE_MISSING = CooldownLogic.CHARGE_STATE_MISSING
local CHARGE_STATE_ZERO = CooldownLogic.CHARGE_STATE_ZERO

function CooldownCompanion:ShouldRefreshButtonVisualStateSnapshot()
    local isEnabled = ST._AreButtonVisualStateSnapshotsEnabled
    return isEnabled and isEnabled() == true
end

function CooldownCompanion:RefreshButtonVisualStateSnapshot(button, context, phase)
    if not CooldownCompanion:ShouldRefreshButtonVisualStateSnapshot() then
        return nil
    end

    local refresh = ST._RefreshButtonVisualState
    if refresh and context then
        context.phase = phase
        return refresh(button, context)
    end
    return nil
end

local function ClearConditionalVisualPreviewFields(button)
    if button._conditionalAuraPreview then
        local buttonData = button.buttonData
        if not (buttonData and (buttonData.auraTracking or buttonData.isPassive)) then
            button._auraActive = false
            button._auraHasTimer = false
            button._auraStackText = ""
        end
    end
    if button._conditionalAuraStackTextPreview then
        button._auraStackText = ""
        if button.auraStackCount then
            button.auraStackCount:SetText("")
        end
    end
    if button._conditionalPandemicPreview then
        local buttonData = button.buttonData
        if not (buttonData and buttonData.auraTracking) then
            button._inPandemic = false
            button._pandemicGraceStart = nil
        end
    end
    button._conditionalPreviewKind = nil
    button._conditionalPreviewStartTime = nil
    button._conditionalPreviewDuration = nil
    button._conditionalPreviewRemaining = nil
    button._conditionalPreviewLoop = nil
    button._conditionalPreviewLoopStartTime = nil
    button._conditionalPreviewLoopDuration = nil
    button._conditionalPreviewDomain = nil
    button._conditionalAuraPreview = nil
    button._conditionalAuraDurationTextPreview = nil
    button._conditionalAuraStackTextPreview = nil
    button._conditionalPandemicPreview = nil
    button._conditionalUnusablePreview = nil
    button._conditionalOutOfRangePreview = nil
    button._conditionalReadyPreview = nil
    button._conditionalBarAuraActivePreview = nil
end

local function HideIconFillForHiddenButton(button)
    if type(ClearIconFillVisualState) == "function" then
        ClearIconFillVisualState(button, button and button.style, nil, true)
        return
    end
    if not (button and button.iconFill) then return end
    button.iconFill:Hide()
    button.iconFill:SetScript("OnUpdate", nil)
    button._iconFillOnUpdateInstalled = nil
    button._iconFillActive = nil
    button._iconFillMode = nil
    button._iconFillAuraActive = nil
    button._iconFillIntent = nil
end

local function ApplyChargeTextColor(button, buttonData, style, usesChargeBehavior)
    if not (button and button.count and (style.chargeFontColor or style.chargeFontColorMissing or style.chargeFontColorZero)) then
        return
    end

    local cc
    if usesChargeBehavior and button._chargeState == CHARGE_STATE_ZERO then
        cc = style.chargeFontColorZero or DEFAULT_WHITE
    elseif usesChargeBehavior and button._chargeState == CHARGE_STATE_MISSING then
        cc = style.chargeFontColorMissing or DEFAULT_WHITE
    elseif usesChargeBehavior and button._chargeState == CHARGE_STATE_FULL then
        cc = style.chargeFontColor or DEFAULT_WHITE
    elseif usesChargeBehavior then
        cc = style.chargeFontColor or DEFAULT_WHITE
    elseif UsesChargeTextLane(buttonData) and not (button and button._barAuraStackDisplay) then
        cc = style.chargeFontColor or DEFAULT_WHITE
    end

    if cc then
        button.count:SetTextColor(cc[1], cc[2], cc[3], cc[4])
    end
end

local function GetConditionalPreviewTiming(preview, now)
    local duration = tonumber(preview and preview.duration)
    local startTime = tonumber(preview and preview.startTime)
    if not duration or duration <= 0 then
        return nil, nil, nil
    end
    if not startTime then
        startTime = now
    end

    local loopDuration = tonumber(preview and preview.loopDuration)
    local loopStartTime = tonumber(preview and preview.loopStartTime)
    if preview and preview.loop == true and loopDuration and loopDuration > 0 then
        if loopDuration > duration then
            loopDuration = duration
        end
        if not loopStartTime then
            loopStartTime = startTime + (duration - loopDuration)
        end
        local elapsed = now - loopStartTime
        if elapsed < 0 then
            elapsed = 0
        end
        local cycleElapsed = elapsed % loopDuration
        local remaining = loopDuration - cycleElapsed
        if remaining > duration then
            remaining = duration
        end
        startTime = now - (duration - remaining)
        return startTime, duration, remaining, loopStartTime, loopDuration
    end

    local remaining = duration - (now - startTime)
    if remaining < 0 then
        remaining = 0
    end
    return startTime, duration, remaining
end

local function SetConditionalPreviewTimingFields(button, startTime, duration, remaining, loopStartTime, loopDuration)
    button._conditionalPreviewStartTime = startTime
    button._conditionalPreviewDuration = duration
    button._conditionalPreviewRemaining = remaining
    button._conditionalPreviewLoop = (loopStartTime and loopDuration) and true or nil
    button._conditionalPreviewLoopStartTime = loopStartTime
    button._conditionalPreviewLoopDuration = loopDuration
end

local function ApplyConditionalVisualPreview(button, buttonData, style, preview, now, usesChargeBehavior)
    if not preview then
        return
    end

    local kind = preview.kind
    button._conditionalPreviewKind = kind

    if kind == "cooldown" then
        local startTime, duration, remaining, loopStartTime, loopDuration = GetConditionalPreviewTiming(preview, now)
        if not startTime then return end
        button._cooldownState = COOLDOWN_STATE_COOLDOWN
        button._desatCooldownActive = true
        button._cooldownDeferred = nil
        button._conditionalPreviewDomain = "cooldown"
        SetConditionalPreviewTimingFields(button, startTime, duration, remaining, loopStartTime, loopDuration)
        if button.cooldown then
            button.cooldown:SetCooldown(startTime, duration)
        end
        return
    end

    if kind == "aura" or kind == "pandemic" then
        local startTime, duration, remaining, loopStartTime, loopDuration = GetConditionalPreviewTiming(preview, now)
        if not startTime then return end
        button._auraActive = true
        button._auraHasTimer = true
        button._auraStackText = preview.stackText or "3"
        button._inPandemic = kind == "pandemic"
        button._conditionalAuraPreview = true
        button._conditionalPandemicPreview = kind == "pandemic" or nil
        button._conditionalBarAuraActivePreview = true
        button._conditionalPreviewDomain = "aura"
        SetConditionalPreviewTimingFields(button, startTime, duration, remaining, loopStartTime, loopDuration)
        if button.cooldown then
            button.cooldown:SetCooldown(startTime, duration)
        end
        if button.auraStackCount and style.showAuraStackText ~= false then
            button.auraStackCount:SetText(button._auraStackText or "")
        end
        return
    end

    if kind == "aura_duration_text" then
        local startTime, duration, remaining, loopStartTime, loopDuration = GetConditionalPreviewTiming(preview, now)
        if not startTime then return end
        button._conditionalAuraDurationTextPreview = true
        button._conditionalPreviewDomain = "aura_text"
        SetConditionalPreviewTimingFields(button, startTime, duration, remaining, loopStartTime, loopDuration)
        if button.cooldown then
            button.cooldown:SetCooldown(startTime, duration)
        end
        return
    end

    if kind == "aura_stack_text" then
        button._auraStackText = preview.stackText or "3"
        button._conditionalAuraStackTextPreview = true
        if button.auraStackCount and style.showAuraStackText ~= false then
            button.auraStackCount:SetText(button._auraStackText or "")
        end
        return
    end

    if kind == "charge_full" or kind == "charge_missing" or kind == "charge_zero" then
        if not usesChargeBehavior then
            return
        end
        local maxCharges = buttonData.maxCharges or 2
        if maxCharges < 2 then
            maxCharges = 2
        end

        local currentCharges = maxCharges
        if kind == "charge_missing" then
            currentCharges = math_max(1, maxCharges - 1)
            button._chargeState = CHARGE_STATE_MISSING
            button._zeroChargesConfirmed = false
        elseif kind == "charge_zero" then
            currentCharges = 0
            button._chargeState = CHARGE_STATE_ZERO
            button._zeroChargesConfirmed = true
            button._desatCooldownActive = true
        else
            button._chargeState = CHARGE_STATE_FULL
            button._zeroChargesConfirmed = false
            button._desatCooldownActive = false
        end

        button._chargeCountReadable = true
        button._currentReadableCharges = currentCharges
        button._chargeText = currentCharges
        if button.count and style.showChargeText ~= false then
            button.count:SetText(currentCharges)
        end
        return
    end

    if kind == "unusable" then
        button._isUnusable = true
        button._conditionalUnusablePreview = true
        return
    end

    if kind == "out_of_range" then
        button._isOutOfRange = true
        button._conditionalOutOfRangePreview = true
    end
end

local function AuraDataHasTimer(auraData)
    if not auraData then return false end
    local duration = auraData.duration
    if duration == nil then return false end
    if issecretvalue(duration) then return nil end
    return duration > 0
end

local function MergeAuraTimerState(currentHasTimer, auraData)
    local hasTimer = AuraDataHasTimer(auraData)
    if hasTimer ~= nil then
        return hasTimer
    end
    return currentHasTimer
end

local function GetViewerNameFontString(viewerFrame)
    -- BuffBar viewer items render name text on Bar.Name. BuffIcon entries have no name text.
    local bar = viewerFrame and viewerFrame.Bar
    return bar and bar.Name or nil
end

local function CreateAuraDisplayNameState(button)
    return {
        priorReadableName = button and button._auraDisplayName or nil,
        priorSecretTextActive = button and button._isText and button._textSecretNameActive == true or false,
    }
end

local function RecordAuraDisplayName(state, auraData)
    if not (state and auraData) then return end
    local auraName = auraData.name
    if issecretvalue(auraName) then
        state.secretName = auraName
        state.hasSecretName = true
        state.nameApplied = true
        return true
    elseif auraName and auraName ~= "" then
        state.readableName = auraName
        state.nameApplied = true
        return true
    end
end

local function PreserveSecretAuraTextRender(state)
    if not (state and state.priorSecretTextActive) then return end
    state.preserveSecretTextRender = true
    state.nameApplied = true
end

local function PreserveAuraDisplayNameDuringGrace(state)
    if not state then return end
    if state.priorReadableName then
        state.readableName = state.priorReadableName
        state.nameApplied = true
    elseif state.priorSecretTextActive then
        PreserveSecretAuraTextRender(state)
    end
end

local function RestoreBaseDisplayName(button, buttonData)
    if not (button and button.nameText and buttonData) or buttonData.customName then
        return
    end

    local restoreSpellID = button._displaySpellId or buttonData.id
    local baseName = buttonData.name
    if buttonData.type == "spell" then
        baseName = C_Spell.GetSpellName(restoreSpellID) or baseName
    elseif buttonData.type == "item" then
        baseName = C_Item.GetItemNameByID(button._resolvedItemId or buttonData.id) or baseName
    end

    if baseName then
        button.nameText:SetText(baseName)
    end
end

local function CommitAuraDisplayName(button, buttonData, viewerFrame, auraOverrideActive, state)
    if auraOverrideActive then
        if state and state.readableName then
            button._auraDisplayName = state.readableName
            if button.nameText and not buttonData.customName then
                button.nameText:SetText(state.readableName)
                button._auraNameOverrideActive = true
            end
        elseif state and state.hasSecretName then
            if button.nameText and not buttonData.customName then
                button.nameText:SetText(state.secretName)
                button._auraNameOverrideActive = true
            end
        elseif state and state.preserveSecretTextRender then
            button._auraNameOverrideActive = true
        end

        if viewerFrame then
            local viewerName = GetViewerNameFontString(viewerFrame)
            if not (state and state.nameApplied) and button.nameText and not buttonData.customName and viewerName and viewerName.GetText then
                -- Pass through the CDM-rendered text directly; avoid calling viewer mixin methods
                -- from tainted code (they can execute secret-value logic internally).
                button.nameText:SetText(viewerName:GetText())
            end
            -- Multi-slot buttons read their icon from the viewer's Icon widget.
            -- Event-driven UpdateButtonIcon calls can race with the CDM viewer's
            -- internal icon update on transforms (e.g. Diabolic Ritual), so re-sync
            -- the icon every tick to ensure it reflects the viewer's current state.
            if buttonData.cdmChildSlot then
                CooldownCompanion:UpdateButtonIcon(button)
            end
            button._viewerAuraVisualsActive = true
        end
    elseif button._viewerAuraVisualsActive or button._auraNameOverrideActive then
        button._viewerAuraVisualsActive = nil
        button._auraNameOverrideActive = nil
        RestoreBaseDisplayName(button, buttonData)
        -- Multi-slot buttons got their icon from per-tick viewer reads while
        -- the aura was active. Now that the aura has dropped, re-sync the icon
        -- to the viewer's current (base) state.
        if buttonData.cdmChildSlot then
            CooldownCompanion:UpdateButtonIcon(button)
        end
    end
end

local function DispatchStandaloneTextureVisual(button)
    if not button then
        return
    end
    if type(CooldownCompanion.UpdateAuraTextureVisual) ~= "function" then
        return
    end

    local group = button._groupId and CooldownCompanion.db and CooldownCompanion.db.profile
        and CooldownCompanion.db.profile.groups and CooldownCompanion.db.profile.groups[button._groupId] or nil
    if group and group.displayMode == "trigger" then
        local frame = button:GetParent()
        local runtimeButtons = frame and frame.buttons
        if type(runtimeButtons) == "table" and runtimeButtons[#runtimeButtons] == button then
            CooldownCompanion:UpdateAuraTextureVisual(runtimeButtons[1] or button)
        end
        return
    end

    CooldownCompanion:UpdateAuraTextureVisual(button)
end

local function IsReadyGlowMaxChargeEligible(buttonData)
    return buttonData
        and buttonData.type == "spell"
        and buttonData.hasCharges == true
        and not buttonData._hasDisplayCount
end

local function IsReadyGlowAtMaxCharges(button, buttonData)
    if not (button and IsReadyGlowMaxChargeEligible(buttonData)) then
        return false
    end

    return button._chargeState == CHARGE_STATE_FULL
end

function CooldownCompanion:RefreshResolvedItemKeybindState(button, buttonData)
    if button.keybindText then
        local text = self:GetDisplayedKeybindText(buttonData, button._resolvedItemId)
        button.keybindText:SetText(text or "")
        button.keybindText:SetShown(button.style and button.style.showKeybindText and text ~= nil)
    end
    if CacheButtonBindingKeys then
        CacheButtonBindingKeys(button, buttonData)
    end
end

local function GetLiveOverrideSpellID(buttonData)
    if not (buttonData and buttonData.type == "spell" and not buttonData.isPassive) then
        return nil
    end

    local overrideID = C_Spell.GetOverrideSpell(buttonData.id)
    if overrideID and overrideID ~= 0 and overrideID ~= buttonData.id then
        return overrideID
    end

    return nil
end

local function ResolveChargeState(button, buttonData)
    if not UsesChargeBehavior(buttonData) then
        return nil
    end

    local currentCharges = button._currentReadableCharges
    local maxCharges = buttonData.maxCharges
    if buttonData.type == "item"
            and button._resolvedItemId
            and tonumber(button._resolvedItemId) ~= tonumber(buttonData.id) then
        maxCharges = button._resolvedItemMaxCharges
    end
    if button._chargeCountReadable == true and currentCharges ~= nil then
        if currentCharges <= 0 then
            return CHARGE_STATE_ZERO
        end
        if buttonData.type == "item" and button._resolvedItemQuantityKind == "stacks" then
            return CHARGE_STATE_FULL
        end
        if maxCharges and maxCharges > 0 then
            if currentCharges >= maxCharges then
                return CHARGE_STATE_FULL
            end
            return CHARGE_STATE_MISSING
        end
        return CHARGE_STATE_FULL
    end

    if button._zeroChargesConfirmed == true then
        return CHARGE_STATE_ZERO
    end
    if button._chargeRecharging == true then
        return CHARGE_STATE_MISSING
    end
    if button._chargeRecharging == false then
        return CHARGE_STATE_FULL
    end

    return nil
end

local function EvaluateItemCooldown(button, buttonData, style, renderCooldown)
    button._isEquippableNotEquipped = false
    button._itemGCDOnly = false
    local isEquippable = IsItemEquippable(buttonData)
    local itemID = button._resolvedItemId or buttonData.id
    if isEquippable and not C_Item.IsEquippedItem(itemID) then
        button._isEquippableNotEquipped = true
        if renderCooldown then
            button.cooldown:SetCooldown(0, 0)
        end
        button._itemCdStart = 0
        button._itemCdDuration = 0
        button._cooldownState = COOLDOWN_STATE_READY
        return false
    end

    local cdStart, cdDuration, enableCooldownTimer = C_Item.GetItemCooldown(itemID)
    if not enableCooldownTimer and cdStart > 0 then
        if renderCooldown then
            button.cooldown:SetCooldown(0, 0)
        end
        button._itemCdStart = 0
        button._itemCdDuration = 0
        button._cooldownDeferred = true
        button._cooldownState = COOLDOWN_STATE_COOLDOWN
        return false
    end

    local itemGCDOnly = CooldownLogic.IsItemGCDOnly(cdStart, cdDuration, CooldownCompanion._gcdInfo)
    button._itemGCDOnly = itemGCDOnly == true
    if cdDuration and cdDuration > 0 then
        if itemGCDOnly then
            button._itemCdStart = 0
            button._itemCdDuration = 0
            button._cooldownState = COOLDOWN_STATE_READY
        else
            button._itemCdStart = cdStart
            button._itemCdDuration = cdDuration
            button._cooldownState = COOLDOWN_STATE_COOLDOWN
        end
    else
        button._itemCdStart = 0
        button._itemCdDuration = 0
        button._cooldownState = COOLDOWN_STATE_READY
    end

    if renderCooldown then
        if itemGCDOnly and style.showGCDSwipe ~= true then
            button.cooldown:SetCooldown(0, 0)
            button.cooldown:Hide()
        else
            button.cooldown:SetCooldown(cdStart, cdDuration)
        end
    end

    return itemGCDOnly == true
end

local function UpdateResolvedItemState(button, buttonData)
    if not (buttonData and buttonData.type == "item") then
        button._resolvedItemId = nil
        button._resolvedItemAvailableQuantity = nil
        button._resolvedItemQuantityKind = nil
        button._resolvedItemMaxCharges = nil
        return false
    end

    local resolvedItemID, availableQuantity, quantityKind = ResolveItemFallback(buttonData)
    local changed = resolvedItemID ~= button._resolvedItemId
        or quantityKind ~= button._resolvedItemQuantityKind

    if changed then
        button._resolvedItemMaxCharges = nil
    end
    button._resolvedItemId = resolvedItemID or buttonData.id
    button._resolvedItemAvailableQuantity = availableQuantity or 0
    button._resolvedItemQuantityKind = quantityKind or "stacks"
    return changed
end

function CooldownCompanion:UpdateButtonCooldown(button)
    local buttonData = button.buttonData
    local style = button.style
    local barAuraStackConfigured = button._isBar and CooldownCompanion:IsBarPanelAuraStackDisplay(buttonData)
    local barAuraStackDisplay = false
    local previousBarAuraStackValue = button._barAuraStackValue
    local previousBarAuraStackValueAvailable = button._barAuraStackValueAvailable == true
    local previousBarAuraStackValueSecret = button._barAuraStackValueSecret == true
    local usesChargeBehavior = UsesChargeBehavior(buttonData)
    local useChargeTextLane = UsesChargeTextLane(buttonData)
    local now = GetTime()
    local isGCDOnly = false
    local desatWasActive = button._desatCooldownActive == true
    local conditionalPreview = GetConditionalVisualPreview and GetConditionalVisualPreview(button)
    local buttonGroup = button._groupId and CooldownCompanion.db and CooldownCompanion.db.profile
        and CooldownCompanion.db.profile.groups and CooldownCompanion.db.profile.groups[button._groupId] or nil
    local buttonDisplayMode = buttonGroup and (buttonGroup.displayMode or "icons") or "icons"
    ClearConditionalVisualPreviewFields(button)

    if UpdateResolvedItemState(button, buttonData) then
        CooldownCompanion:UpdateButtonIcon(button)
        RestoreBaseDisplayName(button, buttonData)
        CooldownCompanion:RefreshResolvedItemKeybindState(button, buttonData)
    end

    if button.count and button._countTextLaneStyled ~= useChargeTextLane then
        if button._isBar then
            ApplyBarCountTextStyle(button, style)
        elseif not button._isText then
            ApplyIconCountTextStyle(button, style)
        else
            button._countTextLaneStyled = useChargeTextLane
        end
    end

    -- For transforming spells (e.g. Void Eruption -> Void Volley), keep the
    -- displayed spell fresh even when the game does not fire SPELL_UPDATE_ICON.
    local cooldownSpellId = button._displaySpellId or buttonData.id
    local liveOverrideId
    local forceBaseDisplayId = false
    if buttonData.type == "spell" and not buttonData.cdmChildSlot then
        local refreshIcon = false
        local previousLiveOverrideId = button._liveOverrideSpellId
        liveOverrideId = GetLiveOverrideSpellID(buttonData)
        button._liveOverrideSpellId = liveOverrideId
        if liveOverrideId then
            if liveOverrideId ~= cooldownSpellId then
                refreshIcon = true
            end
            cooldownSpellId = liveOverrideId
        elseif previousLiveOverrideId then
            cooldownSpellId = buttonData.id
            forceBaseDisplayId = true
            refreshIcon = true
        end

        if button._displaySpellId ~= cooldownSpellId then
            refreshIcon = true
        end

        -- Per-tick icon staleness detection for silent transforms (e.g. Tiger's
        -- Fury changing Rake/Rip icons). GetSpellTexture dynamically resolves
        -- the current visual, but no event fires for these transforms.
        local freshIcon = C_Spell.GetSpellTexture(buttonData.id)
        if freshIcon and freshIcon ~= button._lastSpellTexture then
            button._lastSpellTexture = freshIcon
            refreshIcon = true
        end

        if refreshIcon then
            if forceBaseDisplayId then
                button._forceBaseDisplaySpellId = true
            end
            CooldownCompanion:UpdateButtonIcon(button)
            button._forceBaseDisplaySpellId = nil
            cooldownSpellId = forceBaseDisplayId and buttonData.id
                or liveOverrideId
                or button._displaySpellId
                or buttonData.id
        end
    end

    -- Deferred icon refresh for cdmChildSlot buttons (set by OnSpellUpdateIcon).
    -- One-tick delay ensures the CDM viewer's RefreshSpellTexture has already
    -- run, so child.Icon:GetTextureFileID() returns the current texture.
    if button._iconDirty then
        button._iconDirty = nil
        CooldownCompanion:UpdateButtonIcon(button)
        cooldownSpellId = liveOverrideId or button._displaySpellId or buttonData.id
    end

    -- Lazy-cache no-cooldown detection for spells (GCD-only, no real CD).
    -- Tie the cache to the displayed spell so replacements do not inherit the
    -- base spell's cooldown classification.
    if buttonData.type == "spell" and not buttonData.isPassive and not usesChargeBehavior then
        if button._noCooldown == nil or button._noCooldownSpellId ~= cooldownSpellId then
            button._noCooldownSpellId = cooldownSpellId
            local baseCd = GetSpellBaseCooldown(cooldownSpellId)
            button._noCooldown = (not baseCd or baseCd == 0) and not HasTooltipCooldown(cooldownSpellId)
        end
    else
        button._noCooldown = false
        button._noCooldownSpellId = nil
    end

    -- Proc state: event-driven table lookup (base spell + current displayed override).
    -- Keeps visibility and glow checks aligned without polling overlay APIs.
    local procOverlayActive = false
    if buttonData.type == "spell" and not buttonData.isPassive then
        local displaySpellId = button._displaySpellId
        procOverlayActive = CooldownCompanion.procOverlaySpells[buttonData.id] ~= nil
        if not procOverlayActive and displaySpellId and displaySpellId ~= buttonData.id then
            procOverlayActive = CooldownCompanion.procOverlaySpells[displaySpellId] ~= nil
        end
    end

    -- Clear per-tick DurationObject; set below if cooldown/aura active.
    -- Used by bar fill, desaturation, visibility checks instead of
    -- GetCooldownTimes() which returns secret values after
    -- SetCooldownFromDurationObject() in 12.0.1.
    -- Save previous aura DurationObject for one-tick grace period on target switch.
    local wasAuraActive = button._auraActive == true
    local prevAuraDurationObj = wasAuraActive and button._auraDurationObj or nil
    button._durationObj = nil
    button._auraDurationObj = nil
    button._auraCooldownStart = nil
    button._auraCooldownDuration = nil
    button._auraPrimarySwipeActive = nil
    button._cooldownDeferred = nil
    button._cooldownState = COOLDOWN_STATE_READY
    button._chargeState = nil
    button._chargeCooldownVisualActive = nil
    button._barAuraStackDisplay = nil
    button._barAuraStackValue = nil
    button._barAuraStackValueAvailable = nil
    button._barAuraStackMax = nil
    button._barAuraStackMode = nil
    button._barAuraStackValueSecret = nil
    button._barAuraStackValueDirty = nil
    -- Fetch cooldown data and update the cooldown widget.
    -- isOnGCD is NeverSecret (always readable even during restricted combat).
    local fetchOk, isOnGCD
    local spellCooldownInfo
    local spellCooldownDuration
    local spellRealCooldownShown = false
    local spellCooldownResult
    -- Aura-override probe: cached for reuse by secondary CD and sound alerts.
    local auraProbeInfo, auraProbeIsGCDOnly
    local auraProbeDuration
    local auraProbeNormalCooldownShown = false
    local auraProbeRealCooldownShown = false
    local auraDisplayNameState
    local previousActiveAuraSpellID = button._activeAuraSpellID
    local previousActiveAuraSpellIDFromFallback = button._activeAuraSpellIDFromFallback == true
    local auraApplications
    local auraGraceHeld = false
    local barAuraSecretStackValue
    local preserveBarAuraStackText

    -- Aura tracking: check for active buff/debuff and decide whether it owns the primary swipe.
    local auraOverrideActive = false
    local keepSpellCooldownSwipe = buttonData.auraKeepSpellCooldownSwipe == true
        and buttonData.addedAs ~= "aura"
        and buttonData.isPassive ~= true
        and not button._isBar
        and not button._isText
        and buttonDisplayMode == "icons"
    local auraPrimarySwipeAllowed = not keepSpellCooldownSwipe
    local auraHasTimer = button._auraHasTimer == true
    local auraTrackingReady = buttonData.isPassive == true
    if buttonData.auraTracking and button._auraSpellID then
        auraDisplayNameState = CreateAuraDisplayNameState(button)
        button._auraDisplayName = nil
        local auraState = EntryRuntime.EvaluateTrackedAuraState(
            button,
            buttonData,
            button._auraSpellID,
            {
                now = now,
                allowDurationlessAuraInstance = barAuraStackConfigured,
                previousAuraDurationObj = prevAuraDurationObj,
                wasAuraActive = wasAuraActive,
            }
        )
        local viewerFrame = auraState.viewerFrame
        auraTrackingReady = auraState.auraTrackingReady == true
        auraOverrideActive = auraState.auraPresent == true
        auraApplications = auraState.auraApplications
        auraGraceHeld = auraState.auraGraceHeld == true
        auraHasTimer = auraState.auraHasTimer == true
        button._viewerBar = auraState.viewerBar

        if auraState.auraData then
            RecordAuraDisplayName(auraDisplayNameState, auraState.auraData)
        elseif auraGraceHeld then
            PreserveAuraDisplayNameDuringGrace(auraDisplayNameState)
        end

        if auraOverrideActive then
            if auraState.durationObj then
                button._auraDurationObj = auraState.durationObj
                if auraPrimarySwipeAllowed then
                    button._durationObj = auraState.durationObj
                    button.cooldown:SetCooldownFromDurationObject(auraState.durationObj)
                end
            elseif auraState.auraCooldownStart and auraState.auraCooldownDuration and auraPrimarySwipeAllowed then
                button.cooldown:SetCooldown(auraState.auraCooldownStart, auraState.auraCooldownDuration)
            end
            fetchOk = true
        end

        -- Viewer icon change detection: for passive aura-tracked buttons, the
        -- viewer frame's Icon widget updates per-stage (e.g. Heating Up → Hot Streak)
        -- but UpdateButtonIcon is not called per-tick. Detect texture changes here
        -- and trigger an icon update only when the viewer icon actually changes.
        if buttonData.isPassive and viewerFrame then
            local iconObj = viewerFrame.Icon
            if iconObj and not iconObj.GetTextureFileID then
                iconObj = iconObj.Icon
            end
            if iconObj and iconObj.GetTextureFileID then
                local vfTexId = iconObj:GetTextureFileID()
                if issecretvalue(vfTexId) then
                    -- Secret in combat: can't compare, always refresh
                    -- (SetTexture accepts secret values as pass-through)
                    button._auraViewerFrame = viewerFrame
                    CooldownCompanion:UpdateButtonIcon(button)
                elseif vfTexId ~= button._lastViewerTexId then
                    button._lastViewerTexId = vfTexId
                    button._auraViewerFrame = viewerFrame
                    CooldownCompanion:UpdateButtonIcon(button)
                end
            end
        elseif buttonData.isPassive and button._lastViewerTexId then
            button._lastViewerTexId = nil
            button._auraViewerFrame = nil
            CooldownCompanion:UpdateButtonIcon(button)
        end

        -- Aura icon swap: trigger icon update on _auraActive transition
        if buttonData.auraShowAuraIcon and button._auraSpellID then
            local shouldShow = auraOverrideActive
            button._auraViewerFrame = shouldShow and viewerFrame or nil
            local activeAuraSpellChanged = shouldShow
                and (button._activeAuraSpellID ~= previousActiveAuraSpellID
                    or (button._activeAuraSpellIDFromFallback == true) ~= previousActiveAuraSpellIDFromFallback)
            if shouldShow ~= (button._showingAuraIcon or false) or activeAuraSpellChanged then
                button._showingAuraIcon = shouldShow
                CooldownCompanion:UpdateButtonIcon(button)
            elseif shouldShow and viewerFrame then
                -- Detect viewer Icon texture changes for stage transitions
                -- within an already-active aura (e.g. Heating Up → Hot Streak).
                local iconObj = viewerFrame.Icon
                if iconObj and not iconObj.GetTextureFileID then
                    iconObj = iconObj.Icon
                end
                if iconObj and iconObj.GetTextureFileID then
                    local vfTexId = iconObj:GetTextureFileID()
                    if issecretvalue(vfTexId) then
                        -- Secret in combat: can't compare, always refresh
                        CooldownCompanion:UpdateButtonIcon(button)
                    elseif vfTexId ~= button._lastViewerTexId then
                        button._lastViewerTexId = vfTexId
                        CooldownCompanion:UpdateButtonIcon(button)
                    end
                end
            end
        else
            button._showingAuraIcon = nil
            -- Don't clear _auraViewerFrame for passive buttons — managed above
            if not buttonData.isPassive then
                button._auraViewerFrame = nil
            end
        end

        -- Read aura stack text from viewer frame (combat-safe, secret pass-through)
        if button._auraTrackingReady or buttonData.isPassive then
            if auraOverrideActive and viewerFrame then
                button._auraStackText = GetViewerAuraStackText(viewerFrame)
            else
                button._auraStackText = ""
            end
        end

        button._inPandemic = EntryRuntime.ResolveAuraPandemicState(button, viewerFrame, {
            now = now,
            enabled = auraOverrideActive and (style.showPandemicGlow ~= false or buttonData.hideAuraActiveExceptPandemic),
            previewActive = button._pandemicPreview == true,
        })

        -- Pass through aura display names while keeping icon writes owned by UpdateButtonIcon.
        CommitAuraDisplayName(button, buttonData, viewerFrame, auraOverrideActive, auraDisplayNameState)
    end
    button._auraTrackingReady = auraTrackingReady
    local auraOwnsPrimarySwipe = auraOverrideActive and auraPrimarySwipeAllowed
    button._auraPrimarySwipeActive = auraOwnsPrimarySwipe or nil

    -- Stack-count aura bars own the bar surface even while the aura is inactive.
    -- Inactive auras render as zero stacks so segmented/overlay placeholders stay visible.
    barAuraStackDisplay = barAuraStackConfigured or false
    if barAuraStackDisplay then
        button._barAuraStackDisplay = true
        button._barAuraStackValue = 0
        button._barAuraStackValueAvailable = true
        button._barAuraStackMax = CooldownCompanion:GetBarPanelAuraMaxStacks(buttonData)
        button._barAuraStackMode = CooldownCompanion:GetBarPanelAuraStackDisplayMode(buttonData)
    end
    usesChargeBehavior = UsesChargeBehavior(buttonData) and not barAuraStackDisplay
    useChargeTextLane = UsesChargeTextLane(buttonData) and not barAuraStackDisplay
    if button.count and button._countTextLaneStyled ~= useChargeTextLane then
        if button._isBar then
            ApplyBarCountTextStyle(button, style)
        elseif not button._isText then
            ApplyIconCountTextStyle(button, style)
        else
            button._countTextLaneStyled = useChargeTextLane
        end
    end

    if barAuraStackDisplay then
        button._viewerBar = nil
        button.cooldown:SetCooldown(0, 0)
        button.cooldown:Hide()

        barAuraSecretStackValue, preserveBarAuraStackText = EntryRuntime.ApplyBarAuraStackState(
            button,
            auraOverrideActive,
            auraApplications,
            auraGraceHeld,
            previousBarAuraStackValue,
            previousBarAuraStackValueAvailable,
            previousBarAuraStackValueSecret
        )
    end

    if buttonData.isPassive and not auraOverrideActive then
        button.cooldown:Hide()
    end

    -- Probe spell CD during aura override (shared by secondary CD and sound alerts).
    if auraOwnsPrimarySwipe and not barAuraStackDisplay and buttonData.type == "spell" and not buttonData.isPassive then
        auraProbeInfo = C_Spell.GetSpellCooldown(cooldownSpellId)
        if auraProbeInfo and auraProbeInfo.isActive then
            local auraProbeNormalDuration = C_Spell.GetSpellCooldownDuration(cooldownSpellId)
            auraProbeNormalCooldownShown = EntryRuntime.DurationObjectShowsCooldown(auraProbeNormalDuration)
            auraProbeDuration = C_Spell.GetSpellCooldownDuration(cooldownSpellId, true)
            auraProbeRealCooldownShown = EntryRuntime.DurationObjectShowsCooldown(auraProbeDuration)
        end
        auraProbeIsGCDOnly = auraProbeInfo and CooldownLogic.IsSpellGCDOnly(auraProbeInfo, {
            normalCooldownShown = auraProbeNormalCooldownShown,
            realCooldownShown = auraProbeRealCooldownShown,
        }) or false
    end

    -- Secondary cooldown text display during aura override
    if auraOwnsPrimarySwipe and not barAuraStackDisplay and button.secondaryCooldown then
        if buttonData.type == "spell" and not buttonData.isPassive then
            if auraProbeInfo then
                if not auraProbeIsGCDOnly then
                    if auraProbeDuration and auraProbeRealCooldownShown then
                        button.secondaryCooldown:SetCooldownFromDurationObject(auraProbeDuration)
                        button._secondaryCdActive = true
                    else
                        button.secondaryCooldown:SetCooldown(0, 0)
                        button._secondaryCdActive = false
                    end
                else
                    button.secondaryCooldown:SetCooldown(0, 0)
                    button._secondaryCdActive = false
                end
            else
                button.secondaryCooldown:SetCooldown(0, 0)
                button._secondaryCdActive = false
            end
        elseif buttonData.type == "item" then
            local itemID = button._resolvedItemId or buttonData.id
            local cdStart, cdDuration = C_Item.GetItemCooldown(itemID)
            local probeIsGCDOnly = CooldownLogic.IsItemGCDOnly(cdStart, cdDuration, CooldownCompanion._gcdInfo)
            if cdDuration and cdDuration > 0 and not probeIsGCDOnly then
                button.secondaryCooldown:SetCooldown(cdStart, cdDuration)
                button._secondaryCdActive = true
            else
                button.secondaryCooldown:SetCooldown(0, 0)
                button._secondaryCdActive = false
            end
        end
    elseif button.secondaryCooldown and button._secondaryCdActive then
        button._secondaryCdActive = false
        button.secondaryCooldown:SetCooldown(0, 0)
    end

    if not auraOwnsPrimarySwipe and not barAuraStackDisplay then
        if buttonData.type == "spell" and not buttonData.isPassive then
            spellCooldownResult = EntryRuntime.EvaluateButtonSpellCooldown(buttonData, cooldownSpellId, button._noCooldown)
            if spellCooldownResult and spellCooldownResult.fetchOk then
                spellCooldownInfo = spellCooldownResult.info
                spellCooldownDuration = spellCooldownResult.durationObj
                spellRealCooldownShown = spellCooldownResult.realCooldownShown == true
                isOnGCD = spellCooldownResult.isOnGCD or false
                button._cooldownState = spellCooldownResult.state or COOLDOWN_STATE_READY
                local renderDurationObj = spellCooldownResult.renderDurationObj
                button._cooldownDeferred = spellCooldownResult.deferred or nil
                local cooldownPresentationState = spellCooldownResult.presentationState or button._cooldownState
                isGCDOnly = button._cooldownState ~= COOLDOWN_STATE_COOLDOWN
                    and cooldownPresentationState == COOLDOWN_STATE_GCD

                if button._cooldownState == COOLDOWN_STATE_COOLDOWN then
                    if renderDurationObj then
                        button._durationObj = renderDurationObj
                        button.cooldown:SetCooldownFromDurationObject(renderDurationObj)
                    else
                        button.cooldown:SetCooldown(0, 0)
                    end
                elseif cooldownPresentationState == COOLDOWN_STATE_GCD then
                    if style.showGCDSwipe == true and renderDurationObj then
                        button.cooldown:SetCooldownFromDurationObject(renderDurationObj)
                    else
                        button.cooldown:SetCooldown(0, 0)
                        button.cooldown:Hide()
                    end
                else
                    button.cooldown:SetCooldown(0, 0)
                end
                fetchOk = true
            elseif not fetchOk or auraOverrideActive then
                button.cooldown:SetCooldown(0, 0)
            end
        elseif buttonData.type == "item" then
            isGCDOnly = EvaluateItemCooldown(button, buttonData, style, true)
            fetchOk = true
        end
    elseif not barAuraStackDisplay and buttonData.type == "item" then
        -- Items keep underlying cooldown state during aura override for visibility/desaturation.
        -- Spell aura overrides intentionally do not: the aura owns the spell visual state.
        isGCDOnly = EvaluateItemCooldown(button, buttonData, style, false)
        fetchOk = true
    end

    -- Update spell charge data before zero-charge state classification.
    -- When readable, charge count is authoritative for "zero charges" (unusable),
    -- even if the spell also has a per-cast cooldown lockout.
    local charges
    if usesChargeBehavior and buttonData.hasCharges and buttonData.type == "spell" then
        button._displayCountZeroUsabilityFallback = nil
        charges = UpdateChargeTracking(button, buttonData, cooldownSpellId)
        button._chargeCooldownVisualActive = EntryRuntime.DurationObjectShowsCooldown(button._chargeDurationObj)
        button._chargeRecharging = button._chargeCooldownVisualActive
    elseif usesChargeBehavior
        and (buttonData._hasDisplayCount or buttonData._displayCountFamily)
        and buttonData.type == "spell"
    then
        UpdateDisplayCountTracking(button, buttonData, cooldownSpellId)
    elseif usesChargeBehavior and buttonData.type == "item" then
        UpdateItemChargeTracking(button, buttonData)
        button._chargeRecharging = button._cooldownState == COOLDOWN_STATE_COOLDOWN
    elseif not usesChargeBehavior then
        -- hasCharges cleared: wipe stale charge state.
        button._currentReadableCharges = nil
        button._chargeCountReadable = nil
        button._zeroChargesConfirmed = nil
        button._chargeRecharging = nil
        button._chargeDurationObj = nil
        button._chargesSpent = nil
        button._chargeText = nil
        button._displayCountZeroUsabilityFallback = nil
        if buttonData.type == "spell" then
            button.count:SetText("")
        end
        -- Shared count-text lane for non-charge spells:
        --   1) Blizzard display/use counts (e.g. pooled/shared uses)
        --   2) Cast-count stacks (e.g. Mana Tea)
        -- Both intentionally reuse the charge-text font/toggle without driving
        -- charge-specific cooldown logic.
        if buttonData.type == "spell"
                and not barAuraStackDisplay
                and not (button._auraTrackingReady and button.style and button.style.showAuraStackText ~= false)
                and button.style and button.style.showChargeText then
            local displayCountShown = false
            local hasCastCountText = HasCastCountText(buttonData)
            local conditionalCastCountSpellID
            if buttonData._hasDisplayCount or buttonData._displayCountFamily then
                local displayCount = button.count:GetText()
                if issecretvalue(displayCount) then
                    displayCountShown = true
                elseif displayCount and displayCount ~= "" then
                    displayCountShown = true
                end
            end
            if not hasCastCountText and buttonData._castCountCandidate then
                conditionalCastCountSpellID = GetConditionalCastCountSpellID(buttonData, cooldownSpellId)
            end

            if not displayCountShown and hasCastCountText then
                -- Cast-count text is only shown for explicitly supported
                -- spell families. Use the current live spell/override path
                -- when it belongs to that family.
                button._chargeText = nil
                local castCountSpellID = GetCastCountSpellID(buttonData, cooldownSpellId)
                local castCount = castCountSpellID and C_Spell.GetSpellCastCount(castCountSpellID)
                if castCountSpellID and issecretvalue(castCount) then
                    button.count:SetText(castCount)
                elseif castCountSpellID and not issecretvalue(castCount) and castCount and castCount > 0 then
                    button.count:SetText(castCount)
                else
                    button.count:SetText("")
                end
            elseif not displayCountShown and conditionalCastCountSpellID then
                -- Conditional cast-count text is tied to the live override spell
                -- identified by SPELL_UPDATE_USES. This keeps transformed spells
                -- like Thunderblast showing text without making the base spell
                -- render a stale or always-on count.
                button._chargeText = nil
                local castCount = C_Spell.GetSpellCastCount(conditionalCastCountSpellID)
                if issecretvalue(castCount) then
                    button.count:SetText(castCount)
                elseif castCount and castCount > 0 then
                    button.count:SetText(castCount)
                else
                    button.count:SetText("")
                end
            elseif not displayCountShown then
                button.count:SetText("")
            end
        elseif not barAuraStackDisplay
                and (buttonData._hasDisplayCount or buttonData._displayCountFamily or HasCastCountText(buttonData) or buttonData._castCountCandidate) and buttonData.type == "spell"
                and not (button._auraTrackingReady and button.style and button.style.showAuraStackText ~= false) then
            -- Count text disabled: ensure display/use-count and cast-count text is cleared.
            button.count:SetText("")
        elseif button._chargeText ~= nil then
            button._chargeText = nil
            button.count:SetText("")
        end
    end

    button._isOnGCD = isOnGCD or false
    -- Bar mode: suppress GCD-only display in bars (checked by UpdateBarFill OnUpdate).
    -- Skip for charge spells: their _durationObj is the recharge cycle, never the GCD.
    if button._isBar then
        button._barGCDSuppressed = fetchOk and isGCDOnly
            and not usesChargeBehavior and not buttonData.isPassive and not barAuraStackDisplay
    end

    -- Bar mode icon-only GCD swipe.
    if button._isBar and button.iconGCDCooldown then
        local showBarGCDSwipe = (style.showBarIcon ~= false)
            and style.showGCDSwipe == true
            and buttonData.type == "spell"
            and isOnGCD == true
        if showBarGCDSwipe then
            local gcdDurationObj = CooldownCompanion._gcdDurationObj
            if not gcdDurationObj and spellCooldownDuration then
                gcdDurationObj = spellCooldownDuration
            end
            if gcdDurationObj then
                local iconGCDCooldown = button.iconGCDCooldown
                iconGCDCooldown:SetDrawEdge(style.showCooldownSwipeEdge ~= false)
                iconGCDCooldown:SetReverse(style.cooldownSwipeReverse or false)
                iconGCDCooldown:Hide()
                iconGCDCooldown:SetCooldownFromDurationObject(gcdDurationObj)
            else
                button.iconGCDCooldown:Hide()
            end
        else
            button.iconGCDCooldown:Hide()
        end
    end

    -- Charge count tracking: detect whether the main cooldown (0 charges)
    -- is active.  Filter GCD so only real cooldown reads as true.
    -- Item and readable-spell paths are always safe. Restricted-spell fallbacks
    -- that depend on button.cooldown or isGCDOnly are gated on aura primary-swipe ownership.
    if usesChargeBehavior then
        -- Default to non-zero each tick; set true only when a current probe confirms zero.
        button._mainCDShown = false
        if buttonData.type == "item" then
            -- Items: 0 charges = on cooldown. No GCD to filter.
            local itemID = button._resolvedItemId or buttonData.id
            local chargeCount = C_Item.GetItemCount(itemID, false, true)
            button._mainCDShown = (chargeCount == 0)
        elseif buttonData.type == "spell"
           and button._chargeCountReadable == true
           and button._currentReadableCharges ~= nil then
            -- Readable charge count is the source of truth for zero-charge state.
            -- Prevents short lockout cooldowns (e.g., dragonriding flyout abilities)
            -- from being misclassified as "zero charges".
            button._mainCDShown = (button._currentReadableCharges == 0)
        elseif buttonData.type == "spell" and (buttonData._hasDisplayCount or buttonData._displayCountFamily) then
            -- Secret display counts do not expose a readable number in combat for
            -- some use-count spells. Do not guess zero-state from unrelated
            -- usability signals; leave the zero-state unknown instead.
            button._mainCDShown = false
        elseif buttonData.type == "spell" and usesChargeBehavior and buttonData.hasCharges then
            -- Restricted mode: charges unreadable (secret values).
            -- Action bar probe reflects the regular-cooldown DurationObject
            -- which is NOT charge-aware (isActive = isEnabled and startTime > 0
            -- and duration > 0).  It can report true during per-cast lockouts
            -- and recharge, so the _chargesSpent heuristic below guards both
            -- this path and the isActive fallback.
            local slotProbe = spellCooldownResult and spellCooldownResult.slotProbe
                or EntryRuntime.ProbeActionSlotCooldownForSpell(buttonData.id, cooldownSpellId)
            if slotProbe.shown ~= nil then
                button._mainCDShown = slotProbe.realShown == true
            elseif not auraOwnsPrimarySwipe then
                -- No action bar slot found; use the ignoreGCD-backed real cooldown state.
                if spellCooldownResult and spellCooldownResult.fetchOk then
                    button._mainCDShown = spellCooldownResult.state == COOLDOWN_STATE_COOLDOWN
                elseif spellCooldownInfo then
                    button._mainCDShown = spellRealCooldownShown
                else
                    button._mainCDShown = false
                end
            end
        end
    end

    -- Canonical zero-charge state for downstream visuals/visibility.
    -- _mainCDShown is the raw "main cooldown sweep shown" signal; suppress zero
    -- while we have explicit cast-history evidence that not all charges are spent.
    if usesChargeBehavior then
        -- Seed _chargesSpent when recharging without cast history (e.g. after
        -- /reload mid-recharge).  Defaults to maxCharges ("all spent") so the
        -- heuristic below does not suppress genuine zero-charge signals.
        -- OnSpellCast takes over on the next cast; full recharge resets the cycle.
        if button._chargeRecharging and not button._chargesSpent then
            button._chargesSpent = buttonData.maxCharges or 0
        end

        local zeroConfirmed = (button._mainCDShown == true)
        if zeroConfirmed
           and buttonData.type == "spell"
           and usesChargeBehavior
           and buttonData.hasCharges
           and button._chargeCountReadable ~= true then
            -- Heuristic: suppress zero-charge when cast history says charges remain.
            -- Applies to both the action bar probe and isActive fallback paths.
            -- The probe reflects the regular-cooldown DurationObject which is
            -- not charge-aware and can report true during lockouts/recharge;
            -- _chargesSpent provides authoritative cast-history evidence.
            local maxCharges = buttonData.maxCharges
            local spent = button._chargesSpent
            if maxCharges and maxCharges > 1 and spent and spent < maxCharges then
                zeroConfirmed = false
            end
        end
        button._zeroChargesConfirmed = zeroConfirmed
    else
        button._zeroChargesConfirmed = false
    end
    button._chargeState = ResolveChargeState(button, buttonData)

    -- Cooldown desaturation follows the canonical cooldown state, never the GCD.
    if buttonData.type == "item" then
        button._desatCooldownActive = button._cooldownState == COOLDOWN_STATE_COOLDOWN
    elseif usesChargeBehavior then
        button._desatCooldownActive = button._chargeState == CHARGE_STATE_ZERO
    elseif auraOwnsPrimarySwipe and auraProbeInfo then
        button._desatCooldownActive = (auraProbeRealCooldownShown and not auraProbeIsGCDOnly) or false
    else
        button._desatCooldownActive = button._cooldownState == COOLDOWN_STATE_COOLDOWN
    end
    -- Track on-CD → off-CD transition for ready glow duration timer.
    -- desatWasActive is true only when the previous tick had an active cooldown,
    -- so nil → false (initial load) does NOT set a start time.
    if desatWasActive and button._desatCooldownActive == false then
        button._readyGlowStartTime = now
    elseif button._desatCooldownActive == true then
        button._readyGlowStartTime = nil
    end

    if usesChargeBehavior then
      if buttonData.type == "spell" and buttonData.hasCharges then
        -- Bar/text mode: charge bars are driven by the recharge DurationObject, not
        -- the main spell CD or GCD. Save and clear the main CD so recharge
        -- timing fully controls bar fill for charge spells.
        if (button._isBar or button._isText) and not auraOwnsPrimarySwipe and button._chargeDurationObj then
            button._durationObj = nil
        end

        local normalCooldownDisplayActive = button._cooldownState == COOLDOWN_STATE_COOLDOWN
            or (isGCDOnly and style.showGCDSwipe == true)
        if not auraOwnsPrimarySwipe and button._chargeDurationObj then
            if not button._isBar and not button._isText then
                if button._chargeCooldownVisualActive then
                    -- Icon mode: active recharge owns the shared cooldown frame.
                    button._durationObj = button._chargeDurationObj
                    button.cooldown:SetCooldownFromDurationObject(button._chargeDurationObj)
                elseif not normalCooldownDisplayActive then
                    button.cooldown:SetCooldown(0, 0)
                end
            elseif button._chargeRecharging then
                -- Bar/text mode: only set _durationObj if actually recharging
                button._durationObj = button._chargeDurationObj
            end
        elseif not button._isBar and not button._isText and not auraOwnsPrimarySwipe then
            -- Icon mode fallback: no chargeDurationObj, try fetching one.
            -- Only an active charge DurationObject may replace an existing GCD display.
            local chargeSpellID = cooldownSpellId or buttonData.id
            local fallbackDuration = C_Spell.GetSpellChargeDuration(chargeSpellID)
            local fallbackActive = EntryRuntime.DurationObjectShowsCooldown(fallbackDuration)
            button._chargeCooldownVisualActive = fallbackActive or nil
            if fallbackActive then
                button._chargeRecharging = true
                button._durationObj = fallbackDuration
                button.cooldown:SetCooldownFromDurationObject(fallbackDuration)
            elseif not normalCooldownDisplayActive then
                button.cooldown:SetCooldown(0, 0)
            end
        end

      end
    end

    if IsReadyGlowMaxChargeEligible(buttonData) then
        local readyGlowSpellID = cooldownSpellId or buttonData.id
        if button._readyGlowMaxChargesSpellID ~= readyGlowSpellID then
            button._readyGlowMaxChargesSpellID = readyGlowSpellID
            button._readyGlowMaxChargesStartTime = nil
            button._readyGlowMaxChargesActive = nil
        end

        local isCapped = IsReadyGlowAtMaxCharges(button, buttonData)
        if button._readyGlowMaxChargesActive ~= true and isCapped then
            button._readyGlowMaxChargesStartTime = now
        elseif not isCapped then
            button._readyGlowMaxChargesStartTime = nil
        end
        button._readyGlowMaxChargesActive = isCapped
    else
        button._readyGlowMaxChargesSpellID = nil
        button._readyGlowMaxChargesActive = nil
        button._readyGlowMaxChargesStartTime = nil
    end

    -- Item count display (inventory quantity for non-equipment tracked items)
    if buttonData.type == "item" and not buttonData.hasCharges and not IsItemEquippable(buttonData) then
        local count = button._resolvedItemAvailableQuantity
            or C_Item.GetItemCount(button._resolvedItemId or buttonData.id)
        if button._itemCount ~= count then
            button._itemCount = count
            if count and count >= 1 then
                button.count:SetText(count)
            else
                button.count:SetText("")
            end
        end
    end

    -- Aura stack count display (aura-tracking spells with stackable auras)
    -- Text is a secret value in combat — pass through directly to SetText.
    -- Blizzard sets it to "" when stacks <= 1 and the count string when > 1.
    if button.auraStackCount and button._barAuraStackDisplay then
        if style.showAuraStackText ~= false and button._auraActive then
            if not preserveBarAuraStackText then
                local stackTextFormat = CooldownCompanion:GetBarPanelAuraStackTextFormat(buttonData)

                if barAuraSecretStackValue ~= nil then
                    EntryRuntime.SetAuraStackCountText(button.auraStackCount, barAuraSecretStackValue, button._barAuraStackMax, stackTextFormat)
                elseif button._barAuraStackValueAvailable and not issecretvalue(button._barAuraStackValue) then
                    EntryRuntime.SetAuraStackCountText(button.auraStackCount, button._barAuraStackValue, button._barAuraStackMax, stackTextFormat)
                elseif button._auraStackText ~= nil then
                    EntryRuntime.SetAuraStackCountText(button.auraStackCount, button._auraStackText, button._barAuraStackMax, stackTextFormat)
                else
                    button.auraStackCount:SetText("")
                end
            end
        else
            button.auraStackCount:SetText("")
        end
    elseif button.auraStackCount and (button._auraTrackingReady or buttonData.isPassive or button._conditionalAuraStackTextPreview)
       and (style.showAuraStackText ~= false) then
        if button._auraActive or button._conditionalAuraStackTextPreview then
            button.auraStackCount:SetText(button._auraStackText or "")
        else
            button.auraStackCount:SetText("")
        end
    end

    -- Charge text color: three-state (zero / partial / max).
    -- Uses the canonical charge state resolved above.
    ApplyChargeTextColor(button, buttonData, style, usesChargeBehavior)

    -- Per-button sound alerts (Blizzard-scoped events, CDM-valid only).
    if buttonData.type == "spell" then
        local soundCfg = buttonData.soundAlerts
        local hasSoundConfig = soundCfg and type(soundCfg.events) == "table" and next(soundCfg.events) ~= nil
        if hasSoundConfig then
            local currentCharges
            local maxCharges
            local chargeRecharging = false
            local chargeCooldownStartTime
            if usesChargeBehavior then
                if button._currentReadableCharges ~= nil then
                    currentCharges = button._currentReadableCharges
                elseif charges and charges.currentCharges ~= nil
                   and not issecretvalue(charges.currentCharges) then
                    currentCharges = charges.currentCharges
                end

                if charges then
                    maxCharges = charges.maxCharges
                elseif buttonData.maxCharges and buttonData.maxCharges > 0 then
                    maxCharges = buttonData.maxCharges
                end

                chargeRecharging = button._chargeRecharging
                if charges and charges.cooldownStartTime ~= nil
                   and not issecretvalue(charges.cooldownStartTime) then
                    chargeCooldownStartTime = charges.cooldownStartTime
                end
            end

            local cooldownActive
            if usesChargeBehavior then
                -- Charge spells: cooldown-active means zero available charges.
                cooldownActive = button._chargeState == CHARGE_STATE_ZERO
            elseif auraOwnsPrimarySwipe then
                -- Aura visuals replace button.cooldown; reuse the shared
                -- probe computed above (same spell, same tick).
                if auraProbeInfo then
                    cooldownActive = auraProbeRealCooldownShown and not auraProbeIsGCDOnly
                else
                    cooldownActive = false
                end
            else
                -- Normal path: real cooldown ignores GCD-only presentation.
                cooldownActive = button._cooldownState == COOLDOWN_STATE_COOLDOWN
            end

            self:UpdateButtonSoundAlerts(
                button,
                cooldownSpellId,
                isOnGCD or false,
                cooldownActive,
                auraOverrideActive,
                currentCharges,
                maxCharges,
                chargeRecharging,
                chargeCooldownStartTime
            )
        else
            button._sndInitialized = nil
        end
    end

    -- Per-button visibility evaluation (after charge tracking)
    button._procOverlayActive = procOverlayActive
    EvaluateButtonVisibility(button, buttonData, auraOverrideActive, procOverlayActive, auraOwnsPrimarySwipe)
    button._rawVisibilityHidden = button._visibilityHidden
    button._rawVisibilityAlphaOverride = button._visibilityAlphaOverride
    button._rawVisibilityReasonBits = button._visibilityReasonBits
    button._rawVisibilityReasonMode = button._visibilityReasonMode

    local group = button._groupId and CooldownCompanion.db.profile.groups[button._groupId]
    local isTriggerPanel = group and group.displayMode == "trigger"
    local forceVisibleByUnlockPreview = group
        and group.parentContainerId
        and CooldownCompanion.IsContainerUnlockPreviewActive
        and CooldownCompanion:IsContainerUnlockPreviewActive(group.parentContainerId)
        and not isTriggerPanel
    local visibilityOverrideSource
    if isTriggerPanel then
        button._visibilityHidden = true
        button._visibilityAlphaOverride = 0
        visibilityOverrideSource = "trigger"
    end

    -- Config panel QOL: selected buttons in column 2 are always fully visible.
    local forceVisibleByConfig = IsConfigButtonForceVisible(button)
    local forceVisibleByPreview = conditionalPreview ~= nil and not isTriggerPanel
    if forceVisibleByUnlockPreview or forceVisibleByPreview then
        button._visibilityHidden = false
        button._visibilityAlphaOverride = 1
        visibilityOverrideSource = forceVisibleByUnlockPreview and "unlock-preview" or "conditional-preview"
    elseif forceVisibleByConfig and not isTriggerPanel then
        button._visibilityHidden = false
        button._visibilityAlphaOverride = 1
        visibilityOverrideSource = "config"
    end
    button._forceVisibleByConfig = ((forceVisibleByConfig or forceVisibleByUnlockPreview or forceVisibleByPreview) and not isTriggerPanel) or nil
    if button._visibilityHidden == true then
        button._visibilityFinalMode = "hidden"
    elseif button._visibilityAlphaOverride ~= nil and button._visibilityAlphaOverride ~= 1 then
        button._visibilityFinalMode = "dimmed"
    else
        button._visibilityFinalMode = "visible"
    end
    button._visibilityOverrideSource = visibilityOverrideSource
    button._visibilityTriggerSuppressed = visibilityOverrideSource == "trigger" or nil
    button._visibilityCompactLayout = group and group.compactLayout == true or nil

    local visualStateContext
    local shouldCaptureVisualState = CooldownCompanion:ShouldRefreshButtonVisualStateSnapshot()
    if shouldCaptureVisualState then
        visualStateContext = button._visualStateContext
        if type(visualStateContext) ~= "table" then
            visualStateContext = {}
            button._visualStateContext = visualStateContext
        end
        visualStateContext.displayMode = buttonDisplayMode
        visualStateContext.preserveSecretTextRender = auraDisplayNameState and auraDisplayNameState.preserveSecretTextRender == true
    end
    -- Track visibility/force-visible state changes for compact layout reflow.
    local visibilityChanged = button._visibilityHidden ~= button._prevVisibilityHidden
    if visibilityChanged then
        button._prevVisibilityHidden = button._visibilityHidden
    end
    local forceVisibleChanged = button._forceVisibleByConfig ~= button._prevForceVisibleByConfig
    if forceVisibleChanged then
        button._prevForceVisibleByConfig = button._forceVisibleByConfig
    end
    if visibilityChanged or forceVisibleChanged then
        local groupFrame = button:GetParent()
        if groupFrame then groupFrame._layoutDirty = true end
    end

    -- Apply visibility alpha or early-return for hidden buttons
    if not group or not group.compactLayout then
        -- Non-compact mode: alpha=0 for hidden, restore for visible
        if button._visibilityHidden then
            button.cooldown:Hide()  -- prevent stale IsShown() across ticks
            HideIconFillForHiddenButton(button)
            if button._lastVisAlpha ~= 0 then
                button:SetAlpha(0)
                button._lastVisAlpha = 0
            end
            DispatchStandaloneTextureVisual(button)
            if shouldCaptureVisualState then
                CooldownCompanion:RefreshButtonVisualStateSnapshot(button, visualStateContext, "hidden")
            end
            return  -- Skip all visual updates
        else
            local targetAlpha = button._visibilityAlphaOverride or 1
            if button._lastVisAlpha ~= targetAlpha then
                button:SetAlpha(targetAlpha)
                button._lastVisAlpha = targetAlpha
            end
        end
    else
        -- Compact mode: Show/Hide handled by UpdateGroupLayout
        if button._visibilityHidden then
            -- Prevent stale IsShown() across ticks. SetCooldown(0,0) does not
            -- auto-hide the CooldownFrame; without this, bar mode _mainCDShown
            -- and icon mode force-show both read stale true on next tick.
            button.cooldown:Hide()
            HideIconFillForHiddenButton(button)
            DispatchStandaloneTextureVisual(button)
            if shouldCaptureVisualState then
                CooldownCompanion:RefreshButtonVisualStateSnapshot(button, visualStateContext, "hidden")
            end
            return  -- Skip visual updates for hidden buttons
        else
            local targetAlpha = button._visibilityAlphaOverride or 1
            if button._lastVisAlpha ~= targetAlpha then
                button:SetAlpha(targetAlpha)
                button._lastVisAlpha = targetAlpha
            end
        end
    end

    -- Unusable/out-of-range state for text mode {unusable}/{oor} conditionals
    if button._isText then
        if buttonData.isPassive then
            button._isUnusable = false
        elseif buttonData.type == "spell" then
            local spellID = button._displaySpellId or buttonData.id
            button._isUnusable = not C_Spell_IsSpellUsable(spellID)
        elseif buttonData.type == "item" or buttonData.type == "equipitem" then
            local usable = IsUsableItem(button._resolvedItemId or buttonData.id)
            button._isUnusable = not usable
        else
            button._isUnusable = false
        end

        if buttonData.type == "spell" then
            button._isOutOfRange = button._spellOutOfRange or false
        elseif buttonData.type == "item" or buttonData.type == "equipitem" then
            -- C_Item.IsItemInRange is protected in combat for non-enemy targets (10.2.0)
            if not InCombatLockdown() or UnitCanAttack("player", "target") then
                local inRange = IsItemInRange(button._resolvedItemId or buttonData.id, "target")
                button._isOutOfRange = (inRange == false)
            else
                button._isOutOfRange = false
            end
        else
            button._isOutOfRange = false
        end
    else
        button._isUnusable = false
        button._isOutOfRange = false
    end

    ApplyConditionalVisualPreview(
        button,
        buttonData,
        style,
        conditionalPreview,
        now,
        usesChargeBehavior
    )
    ApplyChargeTextColor(button, buttonData, style, usesChargeBehavior)

    -- Mode-specific visual dispatch
    if button._isText then
        if not (auraDisplayNameState and auraDisplayNameState.preserveSecretTextRender) then
            UpdateTextDisplay(button, auraDisplayNameState and auraDisplayNameState.secretName, auraDisplayNameState and auraDisplayNameState.hasSecretName == true)
        end
    elseif button._isBar then
        UpdateBarDisplay(button)
        DispatchStandaloneTextureVisual(button)
    else
        UpdateIconModeVisuals(button, buttonData, style, fetchOk, isOnGCD, isGCDOnly)
        UpdateIconModeGlows(button, buttonData, style, procOverlayActive)
        DispatchStandaloneTextureVisual(button)
    end
    if shouldCaptureVisualState then
        CooldownCompanion:RefreshButtonVisualStateSnapshot(button, visualStateContext, "post-dispatch")
    end
end
