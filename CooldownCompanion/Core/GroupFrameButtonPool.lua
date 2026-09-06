--[[
    CooldownCompanion - GroupFrameButtonPool
    Button pool keys, reuse cleanup, acquisition, and release.

    Part of the GroupFrame family; see its ordered block in the addon TOC.
    Private helpers are shared through ST._GroupFrame.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local pairs = pairs
local ipairs = ipairs
local InCombatLockdown = InCombatLockdown
local wipe = wipe
local HideGlowStyles = ST._HideGlowStyles
local UnbindDurationText = CooldownCompanion.UnbindDurationText

local GF = ST._GroupFrame

local function UnregisterKeyPressHighlightButton(button)
    local unregister = ST._UnregisterKeyPressHighlightButton
    if unregister then
        unregister(button)
    end
end

local function RefreshButtonKeybindState(button, buttonData)
    if CooldownCompanion.RefreshResolvedItemKeybindState then
        CooldownCompanion:RefreshResolvedItemKeybindState(button, buttonData)
        return
    end

    local cache = ST._CacheButtonBindingKeys
    if cache then
        cache(button, buttonData)
    end
end

local function ClearButtonVisualState(button)
    local clear = ST._ClearButtonVisualState
    if clear then
        clear(button)
    end
end

-- Reset per-button glow state when compact layout toggles visibility.
-- Hidden buttons skip visual updates, so caches must be invalidated on transitions.
local function ResetButtonGlowTransitionState(button)
    if not button then return end

    if HideGlowStyles then
        if button.procGlow then
            HideGlowStyles(button.procGlow)
        end
        if button.readyGlow then
            HideGlowStyles(button.readyGlow)
        end
        if button.assistedHighlight then
            HideGlowStyles(button.assistedHighlight)
        end
    end
    if ST._StopCooldownPressFlash then
        ST._StopCooldownPressFlash(button)
    end

    button._procGlowActive = nil
    button._auraGlowActive = nil
    button._readyGlowActive = nil
    button._readyGlowMaxChargesStartTime = nil
    button._readyGlowMaxChargesActive = false
    button._barAuraEffectActive = nil
    -- No statusBar alpha reset here: the deleted aura pulse animation was the
    -- only writer it undid, and it would unhide a show-only-while-active
    -- shell's bar on compact re-show. Shell state owns statusBar alpha now.
    if button.assistedHighlight then
        button.assistedHighlight.currentState = nil
    end
end

local function ClearButtonCompactSlotCache(button)
    if not button then return end
    button._compactSlotAnchor = nil
    button._compactSlotX = nil
    button._compactSlotY = nil
end

local function GetButtonPoolKey(group, buttonData, style)
    local displayMode = group and group.displayMode
    if displayMode == "text" then
        return "text"
    elseif displayMode == "bars" then
        return "bars"
    elseif displayMode == "textures" then
        return "textures"
    elseif displayMode == "trigger" then
        return "trigger"
    end
    return "icons"
end

local function GetRuntimeGroupButtonList(self, frame, group)
    if self:IsRotationAssistantGroup(group) then
        local buttonData = self:GetRotationAssistantButtonData(frame)
        local list = frame._rotationAssistantButtonList
        if not list then
            list = {}
            frame._rotationAssistantButtonList = list
        end
        list[1] = buttonData
        for index = 2, #list do
            list[index] = nil
        end
        return list
    end
    return group and group.buttons or {}
end

local function IsRuntimeButtonUsable(self, buttonData, group, opts)
    if buttonData and buttonData._rotationAssistantVirtual == true then
        return (opts and opts.checkLoadConditions == false) or self:IsButtonLoadConditionMet(buttonData, group)
    end
    return self:IsButtonUsable(buttonData, group, opts)
end

local function GetExistingButtonPoolKey(button)
    if button and button._buttonPoolKey then
        return button._buttonPoolKey
    end
    if button and button._isText then
        return "text"
    end
    if button and button._isBar then
        return "bars"
    end
    return "icons"
end

local function GetButtonPool(frame, poolKey)
    frame._buttonFramePools = frame._buttonFramePools or {}
    local pool = frame._buttonFramePools[poolKey]
    if not pool then
        pool = {}
        frame._buttonFramePools[poolKey] = pool
    end
    return pool
end

local function ClearCooldownWidget(widget)
    if not widget then return end
    widget:SetScript("OnUpdate", nil)
    if widget.Clear then
        widget:Clear()
    end
    widget:Hide()
end

local function HideButtonGlowContainer(container)
    if container and HideGlowStyles then
        HideGlowStyles(container)
    elseif container and container.Hide then
        container:Hide()
    end
end

local function ClearButtonPreviewState(button)
    button._procGlowPreview = nil
    button._auraGlowPreview = nil
    button._pandemicPreview = nil
    button._barAuraEffectPreview = nil
    button._readyGlowPreview = nil
    button._keyPressHighlightPreview = nil
    button._textureProcPreview = nil
    button._textureAuraPreview = nil
    button._textureReadyPreview = nil
    button._textureUnusablePreview = nil
    button._forceVisibleByConfig = nil
    button._prevForceVisibleByConfig = nil
end

local function ClearReusableButtonRuntime(button)
    button._resolvedItemId = nil
    button._resolvedItemAvailableQuantity = nil
    button._resolvedItemQuantityKind = nil
    button._resolvedItemMaxCharges = nil
    button._equipmentSlotTrackable = nil
    button._displaySpellId = nil
    button._liveOverrideSpellId = nil
    button._spellOutOfRange = nil
    button._lastSpellTexture = nil
    button._lastTextureCheckAt = nil
    button._noCooldown = nil
    button._noCooldownSpellId = nil
    button._baseNoCooldown = nil
    button._baseNoCooldownSpellId = nil
    button._resourceGateCost = nil
    button._resourceGateCostSpellId = nil
    button._baseResourceGateCost = nil
    button._baseResourceGateCostSpellId = nil
    button._cooldownDeferred = nil
    button._durationObj = nil
    button._chargeDurationObj = nil
    -- _totemSwipeStyleActive is deliberately NOT cleared here: it is the latch
    -- that owes the swipe-style restore, and the next pass sees the phase gone
    -- and runs the falling edge. (_totemGlowStyleActive is different: its kit
    -- is hidden outright by the caller, so its latch is cleared there.)
    button._totemActive = nil
    button._chargeRecharging = nil
    button._chargeState = nil
    button._currentReadableCharges = nil
    button._chargeCountReadable = nil
    button._chargeText = nil
    button._chargesSpent = nil
    button._sndInitialized = nil
    button._sndPrevCooldownActive = nil
    button._sndPrevAuraActive = nil
    button._sndPrevCharges = nil
    button._sndPrevChargeRecharging = nil
    button._sndPrevChargeCooldownStart = nil
    button._sndTransitionOptions = nil
    button._zeroChargesConfirmed = nil
    button._nilConfirmPending = nil
    button._hideCooldownChargesActive = nil
    button._gcdSwipeDrawActive = nil
    button._displayCountZeroUsabilityFallback = nil
    button._itemCount = nil
    button._auraSpellID = nil
    button._auraUnit = nil
    button._auraActive = false
    button._auraTrackingReady = nil
    button._auraHasTimer = nil
    button._textSecretNameActive = nil
    button._bindingKeyInfos = nil
    button._keyPressHighlightActive = nil
    button._visibilityHidden = false
    button._prevVisibilityHidden = false
    button._visibilityAlphaOverride = nil
    button._visibilityFinalMode = nil
    button._rawVisibilityReasonMode = nil
    button._rawVisibilityHidden = nil
    button._rawVisibilityAlphaOverride = nil
    button._visibilityOverrideSource = nil
    button._visibilityTriggerSuppressed = nil
    button._visibilityReasonBits = nil
    button._rawVisibilityReasonBits = nil
    button._lastVisAlpha = 1
    button._desaturated = nil
    button._iconDesaturationIntent = nil
    button._iconTintIntent = nil
    button._iconFillIntent = nil
    button._iconGlowIntent = nil
    button._barVisualIntent = nil
    button._barVisualApplied = nil
    button._desatCooldownActive = nil
    button._rawDesatCooldownActive = nil
    button._unusableTintActive = nil
    button._iconFillActive = nil
    button._iconFillMode = nil
    button._iconFillColorR = nil
    button._iconFillColorG = nil
    button._iconFillColorB = nil
    button._iconFillColorA = nil
    button._procGlowActive = nil
    button._auraGlowActive = nil
    button._auraGlowPandemic = nil
    button._readyGlowActive = nil
    button._readyGlowStartTime = nil
    button._readyGlowTotemDeferred = nil
    button._readyGlowMaxChargesStartTime = nil
    button._readyGlowMaxChargesActive = nil
    button._readyGlowMaxChargesSpellID = nil
    button._barAuraEffectActive = nil
    button._barGCDSuppressed = nil
    button._barCdColor = nil
    button._barReadyTextColor = nil
    button._barTextMode = nil
    button._barFillSuppressed = nil
    button._cdTextFontMode = nil
    button._barTextColorDirty = true
    button._lastBarTimeText = nil
    button._textVisualIntent = nil
    button._textVisualApplied = nil
    button._textModeSecretArgs = nil
    button._textModeSecretParts = nil
    button._savedOnUpdate = nil
    ClearButtonPreviewState(button)
    ClearButtonVisualState(button)
    if button.count then button.count:SetText("") end
    if button.textString then
        button.textString:SetText("")
        button.textString:SetAlpha(1)
    end
    -- Composite text entries render through pooled run strings beside
    -- textString; put them away with it so the next entry starts blank.
    if button._isText and ST._ResetTextRunStrings then
        ST._ResetTextRunStrings(button)
    end
    if button.nameText then button.nameText:SetText("") end
    if button.timeText then
        UnbindDurationText(button.timeText)
        button.timeText:SetText("")
    end
    if button.statusBar then button.statusBar:SetAlpha(1.0) end
end

local function ResolveReusableButtonEntryState(button, buttonData)
    if CooldownCompanion.IsEntryItemLike and CooldownCompanion.IsEntryItemLike(buttonData) then
        local effectiveItem = CooldownCompanion.ResolveEffectiveItem
            and CooldownCompanion.ResolveEffectiveItem(buttonData, true)
            or nil
        button._resolvedItemId = effectiveItem and effectiveItem.itemID or buttonData.id
        button._resolvedItemAvailableQuantity = effectiveItem and effectiveItem.availableQuantity or 0
        button._resolvedItemQuantityKind = effectiveItem and effectiveItem.quantityKind or "stacks"
        button._equipmentSlotTrackable = CooldownCompanion.IsEquipmentSlotEntry
            and CooldownCompanion.IsEquipmentSlotEntry(buttonData)
            and effectiveItem and effectiveItem.trackable == true or nil
    end

    if buttonData and buttonData.type == "spell" then
        if buttonData._cooldownSecrecySpellID ~= buttonData.id then
            buttonData._cooldownSecrecy = C_Secrets.GetSpellCooldownSecrecy(buttonData.id)
            buttonData._cooldownSecrecySpellID = buttonData.id
        end
    end

    button._auraSpellID = CooldownCompanion.ResolveAuraSpellID
        and CooldownCompanion:ResolveAuraSpellID(buttonData)
        or nil
    button._auraUnit = buttonData and buttonData.auraUnit or "player"
    button._auraTrackingReady = nil
end

local function DeactivatePooledButton(self, groupId, button)
    if not button then return end
    UnregisterKeyPressHighlightButton(button)
    if self.ReleaseAuraTextureVisual then
        self:ReleaseAuraTextureVisual(button)
    end
    if self.RemoveButtonFromMasque then
        self:RemoveButtonFromMasque(groupId, button)
    end
    button:SetScript("OnUpdate", nil)
    button:SetScript("OnEnter", nil)
    button:SetScript("OnLeave", nil)
    if button._iconBounds then
        button._iconBounds:SetScript("OnEnter", nil)
        button._iconBounds:SetScript("OnLeave", nil)
    end
    if button.iconFill then
        button.iconFill:SetScript("OnUpdate", nil)
        button.iconFill:Hide()
    end
    button._iconFillOnUpdateInstalled = nil
    ClearCooldownWidget(button.cooldown)
    ClearCooldownWidget(button.locCooldown)
    ClearCooldownWidget(button.iconGCDCooldown)
    HideButtonGlowContainer(button.assistedHighlight)
    HideButtonGlowContainer(button.procGlow)
    HideButtonGlowContainer(button.readyGlow)
    HideButtonGlowContainer(button.keyPressHighlight)
    if ST._StopCooldownPressFlash then
        ST._StopCooldownPressFlash(button)
    end
    HideButtonGlowContainer(button.barAuraEffect)
    -- Totem active phase aura indicator: CC-owned kit regions on the button
    -- itself, so the glow-container hides above do not reach them. Hidden here
    -- (rather than left to the next pass's falling edge) because a released
    -- button may be reused by a different entry before it ticks again, and it
    -- must never inherit a lit indicator. enabled=false ignores the style
    -- table, so nil is the honest argument on both resolvers.
    if button._totemGlowKit then
        button._totemGlowStyleActive = nil
        if button._isBar then
            ST._StyleKitBarGlowRegions(button._totemGlowKit, nil, button, false)
        else
            ST._StyleKitGlowRegions(button._totemGlowKit, nil, button, false)
        end
    end
    ClearReusableButtonRuntime(button)
    button._buttonPoolKey = GetExistingButtonPoolKey(button)
    button:Hide()
    button:ClearAllPoints()
end

-- Rule-1 exact-match HINTS for AcquireButtonFromPool: one map pair per pool key
-- (pools are per display mode), because the two acquisition contexts key on
-- different fields -- combat on _auraSlotHostToken, out of combat on buttonData.
-- Strictly hints: every reader re-tests the rule on the hinted frame and must
-- still find it in the pool, so a stale or missing hint only costs the verbatim
-- scan below and can never change which frame rule 1 picks. Weak keys so a hint
-- left behind by a field that changed while the frame sat pooled cannot keep a
-- deleted entry's table reachable for the session.
local function ReleaseButtonToPool(self, frame, groupId, button)
    DeactivatePooledButton(self, groupId, button)
    local poolKey = button._buttonPoolKey
    local pool = GetButtonPool(frame, poolKey)
    pool[#pool + 1] = button
    local index = frame._buttonPoolIndex
    if not index then
        index = {}
        frame._buttonPoolIndex = index
    end
    local indexEntry = index[poolKey]
    if not indexEntry then
        indexEntry = {
            byData = setmetatable({}, { __mode = "k" }),
            byToken = setmetatable({}, { __mode = "k" }),
        }
        index[poolKey] = indexEntry
    end
    -- Last release wins, which is the frame the descending scan would reach
    -- first if two pooled frames ever carry the same key.
    if button.buttonData ~= nil then
        indexEntry.byData[button.buttonData] = button
    end
    if button._auraSlotHostToken ~= nil then
        indexEntry.byToken[button._auraSlotHostToken] = button
    end
end

local function AcquireButtonFromPool(frame, poolKey, buttonData)
    local pools = frame._buttonFramePools
    local pool = pools and pools[poolKey]
    if not pool or #pool == 0 then return nil end
    local pick
    local inCombat = InCombatLockdown()
    local indexEntry = frame._buttonPoolIndex and frame._buttonPoolIndex[poolKey] or nil
    if indexEntry and buttonData ~= nil then
        local hinted
        if inCombat then
            hinted = indexEntry.byToken[buttonData]
            if hinted and hinted._auraSlotHostToken ~= buttonData then
                hinted = nil
            end
        else
            hinted = indexEntry.byData[buttonData]
            if hinted and hinted.buttonData ~= buttonData then
                hinted = nil
            end
        end
        if hinted then
            for i = 1, #pool do
                if pool[i] == hinted then
                    pick = i
                    break
                end
            end
        end
    end
    if pick ~= nil then
        -- Rule-1 hint hit: the ladders below would reach the same frame first.
    elseif inCombat then
        -- Aura-slot hosts are combat-locked to their entry: the slot subtree
        -- riding a host is forbidden (untouchable) until the OOC rebind pass,
        -- so a mismatched host would show another entry's aura on this button.
        -- Prefer the host already bound to this entry; else any slot-free one;
        -- else force a fresh CC-owned frame (returning nil).
        local free
        for i = #pool, 1, -1 do
            local token = pool[i]._auraSlotHostToken
            if token == buttonData then
                pick = i
                break
            elseif token == nil and not free then
                free = i
            end
        end
        pick = pick or free
        -- Refusing here sends the caller to the deterministic constructors,
        -- which name the new frame from the entry index -- the same name the
        -- refused pooled frame still carries. That is harmless and is not a
        -- duplicate-name error: CreateFrame reassigns the global and no CC
        -- surface resolves button frames by name (anchor parsing is $-anchored
        -- to panel/container names, keybinds resolve action-bar globals, and
        -- Masque keys by frame object). Showing another entry's aura on this
        -- button would be the worse trade. Reviewers have flagged this four
        -- times; the pool re-converges on the next out-of-combat rebind.
        if not pick then return nil end
    else
        -- No aura-slot lock needed out of combat: the rebind pass parks every
        -- record unconditionally before it binds, so no pooled frame can still be
        -- carrying a live slot by the time one is handed out. (An earlier ally-gate
        -- design did leave blocked records bound through a pass, which required a
        -- lock here; that gate was measured unnecessary and removed.)
        --
        -- Prefer the frame that already hosts this entry: repeated repopulates
        -- (config refreshes) then converge on a stable entry<->frame mapping
        -- instead of reversing it each pass, which flip-flopped the statically
        -- composed aura-shell visuals and churned the aura slot rebinds.
        -- Same preference ladder as the combat branch: this entry's own host
        -- first, then a slot-free one, and only then any host. The queued
        -- rebind parks stale records on the NEXT frame, so handing out a host
        -- still bound to another entry would show that entry's aura for a
        -- frame (and through the fight if combat starts in that window).
        local free
        for i = #pool, 1, -1 do
            if pool[i].buttonData == buttonData then
                pick = i
                break
            elseif not free and pool[i]._auraSlotHostToken == nil then
                free = i
            end
        end
        pick = pick or free or #pool
    end
    local button = table.remove(pool, pick)
    -- Whichever rule handed this frame out, it has left the pool: drop every
    -- hint that still points at it, including a displaced fallback pick.
    if indexEntry then
        if button.buttonData ~= nil and indexEntry.byData[button.buttonData] == button then
            indexEntry.byData[button.buttonData] = nil
        end
        if button._auraSlotHostToken ~= nil and indexEntry.byToken[button._auraSlotHostToken] == button then
            indexEntry.byToken[button._auraSlotHostToken] = nil
        end
    end
    button:SetParent(frame)
    return button
end

local function PreparePooledButtonForUse(self, frame, group, button, index, buttonData, style)
    button.buttonData = buttonData
    button.index = index
    button.style = style
    button._groupId = frame.groupId
    if buttonData._rotationAssistantVirtual == true and self.RefreshRotationAssistantButton then
        self:RefreshRotationAssistantButton(button)
    end
    ResolveReusableButtonEntryState(button, buttonData)
    RefreshButtonKeybindState(button, buttonData)
    if button.UpdateStyle then
        button:UpdateStyle(style)
    end
    if self.UpdateButtonIcon then
        self:UpdateButtonIcon(button)
    end
    -- A text entry is auto-sized from a worst-case render of its format, and
    -- {name} resolves through the display identity UpdateButtonIcon just
    -- assigned (ClearReusableButtonRuntime wiped it on release). UpdateStyle
    -- above therefore measured against the SAVED id, so re-measure here; the
    -- ApplyActiveButtonLayout call that follows this loop re-pitches the grid.
    if button._isText and ST._ApplyTextEntryLayout then
        ST._ApplyTextEntryLayout(button)
    end
    if CooldownCompanion:IsStandaloneTexturePanelGroup(group) then
        button:SetAlpha(0)
        button._lastVisAlpha = 0
    else
        button:SetAlpha(1)
        button._lastVisAlpha = 1
    end
end

local function ForEachGroupButtonFrame(frame, callback)
    if not (frame and callback) then return end
    if frame.buttons then
        for _, button in ipairs(frame.buttons) do
            callback(button, false, button and button._buttonPoolKey)
        end
    end
    if frame._buttonFramePools then
        for poolKey, pool in pairs(frame._buttonFramePools) do
            for _, button in ipairs(pool) do
                callback(button, true, poolKey)
            end
        end
    end
end

function CooldownCompanion:ReleaseGroupButtonPools(frame)
    if not (frame and frame._buttonFramePools) then return end
    local groupId = frame.groupId
    for poolKey, pool in pairs(frame._buttonFramePools) do
        for _, button in ipairs(pool) do
            button._buttonPoolKey = poolKey
            DeactivatePooledButton(self, groupId, button)
        end
        wipe(pool)
    end
    frame._buttonFramePools = nil
    frame._buttonPoolIndex = nil
end

-- Private helpers consumed by later GroupFrame files.
GF.IsRuntimeButtonUsable = IsRuntimeButtonUsable
GF.ClearButtonCompactSlotCache = ClearButtonCompactSlotCache
GF.GetRuntimeGroupButtonList = GetRuntimeGroupButtonList
GF.GetButtonPoolKey = GetButtonPoolKey
GF.GetExistingButtonPoolKey = GetExistingButtonPoolKey
GF.ReleaseButtonToPool = ReleaseButtonToPool
GF.AcquireButtonFromPool = AcquireButtonFromPool
GF.PreparePooledButtonForUse = PreparePooledButtonForUse
GF.ResetButtonGlowTransitionState = ResetButtonGlowTransitionState
GF.ForEachGroupButtonFrame = ForEachGroupButtonFrame
