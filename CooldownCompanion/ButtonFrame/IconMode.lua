--[[
    CooldownCompanion - ButtonFrame/IconMode
    Icon-mode button creation, styling, visuals, and glow updates
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CooldownLogic = ST.CooldownLogic
local EntryRuntime = ST.EntryRuntime
-- F2 canary sink (loaded before this file; dev-gated, observe-only).
local RefreshTelemetry = ST.RefreshTelemetry
local COOLDOWN_STATE_COOLDOWN = CooldownLogic.STATE_COOLDOWN
local CHARGE_STATE_ZERO = CooldownLogic.CHARGE_STATE_ZERO

-- Localize frequently-used globals
local pairs = pairs
local ipairs = ipairs
local unpack = unpack
local InCombatLockdown = InCombatLockdown
local GetTime = GetTime
local issecretvalue = issecretvalue

-- Imports from Helpers
local ApplyStrataOrder = ST._ApplyStrataOrder
local ApplyEdgePositions = ST._ApplyEdgePositions
local ApplyBorderEdgePositions = ST._ApplyBorderEdgePositions
local ApplyIconTexCoord = ST._ApplyIconTexCoord
local FitHighlightFrame = ST._FitHighlightFrame
local UsesChargeBehavior = CooldownCompanion.UsesChargeBehavior
local UsesChargeTextLane = CooldownCompanion.UsesChargeTextLane
local HasItemFallbacks = CooldownCompanion.HasItemFallbacks
local ResolveViewerChildForSpellDisplay = ST.ResolveViewerChildForSpellDisplay

-- Imports from VisualState
local ClearButtonVisualState = ST._ClearButtonVisualState
local ResolveIconDesaturationIntent = ST._ResolveIconDesaturationIntent
local ResolveIconFillIntent = ST._ResolveIconFillIntent
local ResolveIconGlowIntent = ST._ResolveIconGlowIntent

-- Imports from Glows
local CreateGlowContainer = ST._CreateGlowContainer
local CreateAssistedHighlight = ST._CreateAssistedHighlight
local SetupTooltipScripts = ST._SetupTooltipScripts
local SetAssistedHighlight = ST._SetAssistedHighlight
local SetProcGlow = ST._SetProcGlow
local SetAuraGlow = ST._SetAuraGlow
local SetReadyGlow = ST._SetReadyGlow
local SetKeyPressHighlight = ST._SetKeyPressHighlight
local IsBindingKeyPressed = ST._IsBindingKeyPressed
local CacheButtonBindingKeys = ST._CacheButtonBindingKeys

-- Imports from Visibility
local UpdateLossOfControl = ST._UpdateLossOfControl

-- Imports from Tracking
local UpdateIconTint = ST._UpdateIconTint
local EvaluateDesaturation = ST._EvaluateDesaturation

-- Shared click-through helpers from Utils.lua
local SetFrameClickThroughRecursive = ST.SetFrameClickThroughRecursive

local function IsCursorAnchoredButton(button)
    return button
        and CooldownCompanion.IsGroupCursorAnchored
        and CooldownCompanion:IsGroupCursorAnchored(button._groupId)
        or false
end

-- Shared helpers from ButtonFrame/Helpers.lua
local IsItemEquippable = CooldownCompanion.IsItemEquippable
local IsEntryItemLike = CooldownCompanion.IsEntryItemLike
local ResolveEffectiveItem = CooldownCompanion.ResolveEffectiveItem
local ApplyFontStyle = CooldownCompanion.ApplyFontStyle
local ApplyDurationFormatToCooldown = CooldownCompanion.ApplyDurationFormatToCooldown

-- Pre-defined color constant tables to avoid per-tick allocation.
-- IMPORTANT: These tables are read-only — never write to their indices.
local DEFAULT_WHITE = {1, 1, 1, 1}
local ICON_FILL_TEXTURE = "Interface\\Buttons\\WHITE8x8"
local QUESTION_MARK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local KPH_INTERVAL = 0.05
local kphAccumulator = 0
local kphButtons = {}
local kphButtonIndexes = {}
local kphUpdateFrame = CreateFrame("Frame")

local RefreshKeyPressHighlightEnrollment
local UnregisterKeyPressHighlightButton

local function IsKeyPressHighlightGroupEligible(button)
    local groupId = button and button._groupId
    local groups = CooldownCompanion.db and CooldownCompanion.db.profile
        and CooldownCompanion.db.profile.groups
    local group = groupId and groups and groups[groupId]
    return group and group.displayMode ~= "bars" and group.displayMode ~= "text" or false
end

local function HasCachedBindingKeys(button)
    local keyInfos = button and button._bindingKeyInfos
    return keyInfos and #keyInfos > 0 or false
end

local function ShouldEnrollKeyPressHighlightButton(button)
    if not (button and button.keyPressHighlight and IsKeyPressHighlightGroupEligible(button)) then
        return false
    end

    if button._keyPressHighlightPreview then
        return true
    end

    local style = button.style
    if not (style and style.keyPressHighlightStyle and style.keyPressHighlightStyle ~= "none") then
        return false
    end

    local buttonData = button.buttonData
    if not buttonData
        or buttonData._rotationAssistantVirtual == true
        or buttonData.type == "header"
        or buttonData.isPassive then
        return false
    end

    return HasCachedBindingKeys(button)
end

local function ShouldShowKeyPressHighlight(button, inCombat)
    if button._keyPressHighlightPreview then
        return true, inCombat
    end

    local style = button.style
    if style and style.keyPressHighlightCombatOnly then
        if inCombat == nil then
            inCombat = InCombatLockdown()
        end
        if not inCombat then
            return false, inCombat
        end
    end

    local keyInfos = button._bindingKeyInfos
    if keyInfos then
        for _, info in ipairs(keyInfos) do
            if IsBindingKeyPressed(info) then
                return true, inCombat
            end
        end
    end

    return false, inCombat
end

local function StopKeyPressHighlightDriver()
    kphAccumulator = 0
    kphUpdateFrame:SetScript("OnUpdate", nil)
end

local function KeyPressHighlightOnUpdate(_, elapsed)
    kphAccumulator = kphAccumulator + elapsed
    if kphAccumulator < KPH_INTERVAL then return end
    kphAccumulator = 0

    local inCombat
    local index = 1
    while index <= #kphButtons do
        local button = kphButtons[index]
        if ShouldEnrollKeyPressHighlightButton(button) then
            local showKPH
            showKPH, inCombat = ShouldShowKeyPressHighlight(button, inCombat)
            SetKeyPressHighlight(button, showKPH)
            index = index + 1
        else
            UnregisterKeyPressHighlightButton(button)
        end
    end
end

local function StartKeyPressHighlightDriver()
    if #kphButtons > 0 and not kphUpdateFrame:GetScript("OnUpdate") then
        kphUpdateFrame:SetScript("OnUpdate", KeyPressHighlightOnUpdate)
    end
end

UnregisterKeyPressHighlightButton = function(button)
    if not button then return end

    local index = kphButtonIndexes[button]
    if index then
        local lastIndex = #kphButtons
        local lastButton = kphButtons[lastIndex]
        kphButtons[index] = lastButton
        kphButtons[lastIndex] = nil
        kphButtonIndexes[button] = nil
        if lastButton and lastButton ~= button then
            kphButtonIndexes[lastButton] = index
        end
    end

    if button.keyPressHighlight then
        SetKeyPressHighlight(button, false)
    end
    button._keyPressHighlightActive = nil

    if #kphButtons == 0 then
        StopKeyPressHighlightDriver()
    end
end

RefreshKeyPressHighlightEnrollment = function(button)
    if ShouldEnrollKeyPressHighlightButton(button) then
        if not kphButtonIndexes[button] then
            kphButtons[#kphButtons + 1] = button
            kphButtonIndexes[button] = #kphButtons
        end
        StartKeyPressHighlightDriver()
    else
        UnregisterKeyPressHighlightButton(button)
    end
end

local function SelectTextureValue(value, knownAvailable)
    if knownAvailable == true then
        return value, true
    end
    if issecretvalue(value) then
        return value, true
    end
    if value ~= nil then
        return value, true
    end
    return nil, false
end

local function ApplyIconFillLayer(button)
    if button and button.iconFill then
        local fillLevel = button:GetFrameLevel() + 1
        if button.cooldown and button.cooldown.GetFrameLevel then
            local cooldownLevel = button.cooldown:GetFrameLevel()
            if cooldownLevel and cooldownLevel > fillLevel then
                fillLevel = cooldownLevel - 1
            end
        end
        button.iconFill:SetFrameLevel(fillLevel)
    end
end

local function AnchorIconFill(button)
    if not (button and button.iconFill and button.icon) then
        return
    end

    button.iconFill:ClearAllPoints()
    button.iconFill:SetPoint("TOPLEFT", button.icon, "TOPLEFT", 0, 0)
    button.iconFill:SetPoint("BOTTOMRIGHT", button.icon, "BOTTOMRIGHT", 0, 0)
end

local function ApplyIconFillGeometry(button, style)
    if not (button and button.iconFill) then
        return
    end

    local orientation = style and style.iconFillOrientation == "horizontal" and "HORIZONTAL" or "VERTICAL"
    local reverseFill = style and style.iconFillReverse == true or false
    if button._iconFillOrientation == orientation and button._iconFillReverseFill == reverseFill then
        return
    end

    button._iconFillOrientation = orientation
    button._iconFillReverseFill = reverseFill
    button.iconFill:SetOrientation(orientation)
    button.iconFill:SetReverseFill(reverseFill)
end

local function ResolveIconFillTimerValue(button, elapsedPercent)
    if button and button.style and button.style.iconFillTimerBehavior == "fill" then
        return elapsedPercent
    end
    return 1 - elapsedPercent
end

local function ResolveIconFillDurationObjectValue(button, durationObj)
    if not durationObj then
        return nil
    end
    if button and button.style and button.style.iconFillTimerBehavior == "fill" then
        return durationObj:GetElapsedPercent()
    end
    return durationObj:GetRemainingPercent()
end

local function ApplyDefaultCooldownSwipeStyle(button, style)
    if not (button and button.cooldown and style) then
        return
    end

    local swipeEnabled = style.showCooldownSwipe ~= false
    local fillEnabled = style.showCooldownSwipeFill ~= false
    local edgeEnabled = style.showCooldownSwipeEdge ~= false
    local reverse = style.cooldownSwipeReverse or false
    local alpha = style.cooldownSwipeAlpha or 0.8
    local edgeColor = style.cooldownSwipeEdgeColor or DEFAULT_WHITE
    button.cooldown:SetUseAuraDisplayTime(false)
    button.cooldown:SetDrawSwipe(swipeEnabled and fillEnabled and button._hideCooldownChargesActive ~= true)
    button.cooldown:SetDrawEdge(swipeEnabled and edgeEnabled)
    button.cooldown:SetReverse(swipeEnabled and reverse)
    button.cooldown:SetSwipeColor(0, 0, 0, alpha)
    button.cooldown:SetEdgeColor(edgeColor[1], edgeColor[2], edgeColor[3], edgeColor[4])
end

local function ResolveIconFillPreviewRemaining(button)
    local duration = button and button._conditionalPreviewDuration
    local startTime = button and button._conditionalPreviewStartTime
    if not (duration and startTime and duration > 0) then
        return nil, nil
    end

    -- F2 canary: past the guard, an icon-fill conditional-preview remaining is
    -- computed this walk (covered by the conditionalPreview classifier term).
    RefreshTelemetry:NoteTimeRender()
    local remaining
    if button._conditionalPreviewLoop
        and button._conditionalPreviewLoopStartTime
        and button._conditionalPreviewLoopDuration
        and button._conditionalPreviewLoopDuration > 0 then
        local elapsed = GetTime() - button._conditionalPreviewLoopStartTime
        if elapsed < 0 then elapsed = 0 end
        local cycleElapsed = elapsed % button._conditionalPreviewLoopDuration
        remaining = button._conditionalPreviewLoopDuration - cycleElapsed
        if remaining > duration then remaining = duration end
    else
        remaining = duration - (GetTime() - startTime)
        if remaining < 0 then remaining = 0 end
    end

    return remaining, duration
end

local function SetIconFillFromCooldownWidget(button)
    if not (button and button.iconFill and button.cooldown) then
        return false
    end

    if button._cooldownState ~= COOLDOWN_STATE_COOLDOWN and button._auraActive ~= true then
        return false
    end

    local startMs, durMs = button.cooldown:GetCooldownTimes()
    if not (startMs and durMs)
        or issecretvalue(startMs)
        or issecretvalue(durMs)
        or durMs <= 0 then
        return false
    end

    local elapsed = (GetTime() * 1000) - startMs
    if elapsed < 0 then elapsed = 0 end
    if elapsed > durMs then elapsed = durMs end

    local value = ResolveIconFillTimerValue(button, elapsed / durMs)

    -- F2 canary: cooldown-widget icon fill draws remaining this walk (covered by
    -- the _cooldownState == COOLDOWN / _auraActive classifier terms, guarded above).
    -- Under the combat ticker floor this fill self-animates (its own OnUpdate,
    -- usesOnUpdate), so the walk-time render is redundant -- do not count it, or it
    -- would falsely trip falseIdleTotal against the now-skippable icon.
    button.iconFill:SetValue(value)
    return true
end

local function SetIconFillValue(button)
    if not (button and button.iconFill and button._iconFillMode) then
        return
    end

    local remaining, duration = ResolveIconFillPreviewRemaining(button)
    if remaining and duration and duration > 0 then
        button.iconFill:SetValue(ResolveIconFillTimerValue(button, 1 - (remaining / duration)))
        return
    end

    if button._durationObj then
        button.iconFill:SetValue(ResolveIconFillDurationObjectValue(button, button._durationObj))
        return
    end

    if SetIconFillFromCooldownWidget(button) then
        return
    end

    if button._iconFillMode == "cooldown" and IsEntryItemLike(button.buttonData) then
        local durationSeconds = button._itemCdDuration or 0
        if durationSeconds > 0 then
            -- F2 canary: item cooldown icon fill draws remaining this walk
            -- (covered by the _cooldownState == COOLDOWN classifier term). Skipped
            -- under the combat ticker floor -- this fill self-animates (own
            -- OnUpdate), so counting it would falsely trip falseIdleTotal.
            local elapsed = GetTime() - (button._itemCdStart or 0)
            if elapsed < 0 then elapsed = 0 end
            local value = elapsed / durationSeconds
            if value > 1 then value = 1 end
            button.iconFill:SetValue(ResolveIconFillTimerValue(button, value))
            return
        end
    end

    button.iconFill:SetValue(0)
end

local function IconFillOnUpdate(self)
    SetIconFillValue(self._owner)
end

local function ClearIconFillVisualState(button, style, preserveIntent, forceClearScript)
    if not button then
        return
    end

    local wasActive = button._iconFillActive == true
    if button.iconFill then
        button.iconFill:Hide()
        if forceClearScript == true or button._iconFillOnUpdateInstalled then
            button.iconFill:SetScript("OnUpdate", nil)
        end
    end

    button._iconFillOnUpdateInstalled = nil
    button._iconFillActive = nil
    button._iconFillMode = nil
    button._iconFillColorR = nil
    button._iconFillColorG = nil
    button._iconFillColorB = nil
    button._iconFillColorA = nil
    if not preserveIntent then
        button._iconFillIntent = nil
    end

    if wasActive then
        ApplyDefaultCooldownSwipeStyle(button, style)
    end
end

local function HideIconFill(button, style, preserveIntent)
    ClearIconFillVisualState(button, style, preserveIntent)
end

local function UpdateIconFill(button, buttonData, style)
    if type(ResolveIconFillIntent) ~= "function" then
        HideIconFill(button, style)
        return
    end

    local intent = button._iconFillIntent
    if type(intent) ~= "table" then
        intent = {}
        button._iconFillIntent = intent
    end

    ResolveIconFillIntent(button, buttonData, style, intent)
    if intent.active ~= true or not intent.mode then
        HideIconFill(button, style, true)
        return
    end

    local mode = intent.mode
    button._iconFillActive = true
    button._iconFillMode = mode
    ApplyIconFillGeometry(button, style)
    local r = intent.r or 1
    local g = intent.g or 1
    local b = intent.b or 1
    local colorA = intent.a or 1
    if button._iconFillColorR ~= r
        or button._iconFillColorG ~= g
        or button._iconFillColorB ~= b
        or button._iconFillColorA ~= colorA then
        button._iconFillColorR = r
        button._iconFillColorG = g
        button._iconFillColorB = b
        button._iconFillColorA = colorA
        button.iconFill:SetStatusBarColor(r, g, b, colorA)
    end
    SetIconFillValue(button)
    button.iconFill:Show()
    if intent.usesOnUpdate ~= true then
        if button._iconFillOnUpdateInstalled then
            button.iconFill:SetScript("OnUpdate", nil)
            button._iconFillOnUpdateInstalled = nil
        end
    elseif not button._iconFillOnUpdateInstalled then
        button.iconFill:SetScript("OnUpdate", IconFillOnUpdate)
        button._iconFillOnUpdateInstalled = true
    end

    if intent.suppressCooldownSwipe == true and button.cooldown then
        button.cooldown:SetDrawSwipe(false)
        button.cooldown:SetDrawEdge(false)
    end
end

local function ApplyCountTextStyle(button, style)
    if not button or not button.count then return end
    local buttonData = button.buttonData
    button.count:ClearAllPoints()
    if buttonData and UsesChargeTextLane(buttonData) then
        ApplyFontStyle(button.count, style, "charge")

        local chargeAnchor = style.chargeAnchor or "BOTTOMRIGHT"
        local chargeXOffset = style.chargeXOffset or -2
        local chargeYOffset = style.chargeYOffset or 2
        button.count:SetPoint(chargeAnchor, chargeXOffset, chargeYOffset)
    elseif buttonData and buttonData.type == "item"
       and not IsItemEquippable(buttonData) then
        ApplyFontStyle(button.count, buttonData, "itemCount")

        local itemAnchor = buttonData.itemCountAnchor or "BOTTOMRIGHT"
        local itemXOffset = buttonData.itemCountXOffset or -2
        local itemYOffset = buttonData.itemCountYOffset or 2
        button.count:SetPoint(itemAnchor, itemXOffset, itemYOffset)
    else
        button.count:SetPoint("BOTTOMRIGHT", -2, 2)
    end
    button._countTextLaneStyled = buttonData and UsesChargeTextLane(buttonData) or false
end

-- Show-only-while-active entries (12.1 compositing): the aura display slot
-- renders the entire visible button, so the CC frame stays shown as the
-- layout shell and slot host but every visual it owns goes transparent.
-- Static by design — no aura state exists to read at runtime.
local function IsAuraShellEntry(buttonData)
    return buttonData
        and (buttonData.auraTracking or buttonData.addedAs == "aura")
        and buttonData.hideWhileAuraNotActive == true
end

local function SetGlowContainerShellAlpha(container, alpha)
    if not container then return end
    -- Stamp the shell alpha so glow state changes can't resurrect the
    -- container: StopSolidBorderPulse restores this instead of a flat 1.
    container._ccShellAlpha = alpha
    if container.solidFrame then container.solidFrame:SetAlpha(alpha) end
    if container.procFrame then container.procFrame:SetAlpha(alpha) end
    if container.blizzardFrame then container.blizzardFrame:SetAlpha(alpha) end
end

-- Aura config previews render on CC-side regions — the exact ones a
-- show-only-while-active shell hides (the text preview FontString lives on
-- overlayFrame) — so the shell exposes while one runs. Restored by the
-- preview clear path (Preview.lua) and every restyle. Mirrors BarMode's
-- IsAuraPreviewExposingShell.
local function IsAuraPreviewExposingShell(button)
    if button._auraGlowPreview == true then
        -- The aura-glow preview renders through the CC-side glow container,
        -- whose shell alpha this helper stamps — expose it too.
        return true
    end
    local preview = button._conditionalVisualPreview
    local kind = preview and preview.kind
    return kind == "aura_duration_text"
        or kind == "aura_stack_text"
        or kind == "aura_duration_swipe"
end

local function ApplyAuraShellVisuals(button, buttonData)
    local alpha = (IsAuraShellEntry(buttonData) and not IsAuraPreviewExposingShell(button)) and 0 or 1
    button.bg:SetAlpha(alpha)
    -- The icon must be hidden by shown-state, not alpha: the per-tick tint
    -- pipeline writes icon:SetVertexColor(r,g,b,a) on every intent change,
    -- and the 4-arg form overwrites the texture's alpha through a different
    -- C entry point than SetAlpha — it silently undid an alpha-0 shell on
    -- the next tick. Nothing else Shows the icon.
    button.icon:SetShown(alpha == 1)
    if button.borderTextures then
        for _, tex in ipairs(button.borderTextures) do
            tex:SetAlpha(alpha)
        end
    end
    button.cooldown:SetAlpha(alpha)
    if button.locCooldown then button.locCooldown:SetAlpha(alpha) end
    if button.iconFill then button.iconFill:SetAlpha(alpha) end
    if button.overlayFrame then button.overlayFrame:SetAlpha(alpha) end
    SetGlowContainerShellAlpha(button.procGlow, alpha)
    SetGlowContainerShellAlpha(button.auraGlow, alpha)
    SetGlowContainerShellAlpha(button.readyGlow, alpha)
    SetGlowContainerShellAlpha(button.keyPressHighlight, alpha)
    SetGlowContainerShellAlpha(button.assistedHighlight, alpha)
end

-- Countdown text hosting (12.1 compositing): by default the countdown region
-- stays inside the Cooldown frame, which sits BELOW the aura display — so an
-- active aura's display naturally occludes it. separateTextPositions hoists
-- it into the overlay frame ABOVE the aura display, so the cooldown and the
-- aura duration (drawn by the slot kit) show simultaneously.
local function ApplyCooldownTextHost(button, buttonData, style)
    local region = button._cdTextRegion
    if not region then return end
    local wantOverlay = style.separateTextPositions == true
        and (buttonData.auraTracking or buttonData.addedAs == "aura")
        and not buttonData.isPassive
    local host = wantOverlay and button.overlayFrame or button.cooldown
    if host and region:GetParent() ~= host then
        region:SetParent(host)
    end
    region:ClearAllPoints()
    local cdAnchor = style.cooldownTextAnchor or "CENTER"
    region:SetPoint(cdAnchor, host, cdAnchor,
        style.cooldownTextXOffset or 0, style.cooldownTextYOffset or 0)
end

function CooldownCompanion:CreateButtonFrame(parent, index, buttonData, style)
    local width, height

    if style.maintainAspectRatio then
        -- Square mode: use buttonSize for both dimensions
        local size = style.buttonSize or ST.BUTTON_SIZE
        width = size
        height = size
    else
        -- Non-square mode: use separate width/height
        width = style.iconWidth or style.buttonSize or ST.BUTTON_SIZE
        height = style.iconHeight or style.buttonSize or ST.BUTTON_SIZE
    end

    -- Create main button frame
    local button = CreateFrame("Frame", parent:GetName() .. "Button" .. index, parent)
    button:SetSize(width, height)

    -- F6: flatten this button's render layers into one render pass
    -- (owner-validated V1-V10: no visual difference).
    button:SetFlattensRenderLayers(true)

    -- Background
    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetAllPoints()
    local bgColor = style.backgroundColor or {0, 0, 0, 0.5}
    button.bg:SetColorTexture(unpack(bgColor))

    -- Icon
    button.icon = button:CreateTexture(nil, "ARTWORK")
    local borderSize = style.borderSize or ST.DEFAULT_BORDER_SIZE
    local borderRenderMode = ST.GetBorderRenderMode(style)
    local borderLayoutSize = ST.GetEffectiveBorderLayoutSize(button, borderSize, borderRenderMode)
    button.icon:SetPoint("TOPLEFT", borderLayoutSize, -borderLayoutSize)
    button.icon:SetPoint("BOTTOMRIGHT", -borderLayoutSize, borderLayoutSize)

    ApplyIconTexCoord(button.icon, width, height)

    button.iconFill = CreateFrame("StatusBar", button:GetName() .. "IconFill", button)
    button.iconFill._owner = button
    AnchorIconFill(button)
    button.iconFill:SetMinMaxValues(0, 1)
    button.iconFill:SetValue(0)
    ApplyIconFillGeometry(button, style)
    button.iconFill:SetStatusBarTexture(ICON_FILL_TEXTURE)
    button.iconFill:Hide()
    SetFrameClickThroughRecursive(button.iconFill, true, true)

    -- Border using textures (not BackdropTemplate which captures mouse)
    local borderColor = style.borderColor or {0, 0, 0, 1}
    button.borderTextures = {}

    -- Create 4 edge textures for border using shared anchor spec
    for i = 1, 4 do
        local tex = button:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(unpack(borderColor))
        button.borderTextures[i] = tex
    end
    ApplyBorderEdgePositions(button.borderTextures, button, borderSize, borderRenderMode)

    -- Assisted highlight overlays (multiple styles, all hidden by default)
    button.assistedHighlight = CreateAssistedHighlight(button, style)

    -- Cooldown frame (standard radial swipe)
    button.cooldown = CreateFrame("Cooldown", button:GetName() .. "Cooldown", button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints(button.icon)
    ApplyDefaultCooldownSwipeStyle(button, style)
    button.cooldown:SetHideCountdownNumbers(false) -- Always allow; visibility controlled via text alpha
    ApplyDurationFormatToCooldown(button.cooldown, style)
    -- Recursively disable mouse on cooldown and all its children (CooldownFrameTemplate has children)
    -- Always fully non-interactive: disable both clicks and motion
    SetFrameClickThroughRecursive(button.cooldown, true, true)
    button.cooldown:SetScript("OnCooldownDone", ST.OnButtonCooldownDone)

    -- Loss of control cooldown frame (red swipe showing lockout duration)
    button.locCooldown = CreateFrame("Cooldown", button:GetName() .. "LocCooldown", button, "CooldownFrameTemplate")
    button.locCooldown:SetAllPoints(button.icon)
    button.locCooldown:SetDrawEdge(true)
    button.locCooldown:SetDrawSwipe(true)
    button.locCooldown:SetSwipeColor(0.17, 0, 0, 0.8)
    button.locCooldown:SetHideCountdownNumbers(true)
    SetFrameClickThroughRecursive(button.locCooldown, true, true)

    -- Suppress bling (cooldown-end flash) on all icon buttons
    button.cooldown:SetDrawBling(false)
    button.locCooldown:SetDrawBling(false)

    -- Proc glow elements (solid border + animated glow + lazy dash/spark pools)
    button.procGlow = CreateGlowContainer(button, style.procGlowSize or 32)

    -- Aura active glow elements (solid border + animated glow + lazy dash pool)
    button.auraGlow = CreateGlowContainer(button, 32)

    -- Ready glow elements (glow while off cooldown)
    button.readyGlow = CreateGlowContainer(button, 32)

    -- Key press highlight elements (glow while keybind is held)
    button.keyPressHighlight = CreateGlowContainer(button, 32, true)

    -- Aura/ready glow frame levels are now managed by ApplyStrataOrder (called below)

    -- Apply custom cooldown text font settings
    local region = button.cooldown:GetRegions()
    if region and region.SetFont then
        ApplyFontStyle(region, style, "cooldown")
        region:ClearAllPoints()
        local cdAnchor = style.cooldownTextAnchor or "CENTER"
        local cdXOff = style.cooldownTextXOffset or 0
        local cdYOff = style.cooldownTextYOffset or 0
        region:SetPoint(cdAnchor, cdXOff, cdYOff)
        button._cdTextRegion = region
    end

    -- Stack count text (for items) — on overlay frame so it renders above cooldown swipe
    button.overlayFrame = CreateFrame("Frame", nil, button)
    button.overlayFrame:SetAllPoints()
    button.overlayFrame:EnableMouse(false)

    ApplyCooldownTextHost(button, buttonData, style)

    button.count = button.overlayFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetText("")
    button.buttonData = buttonData

    if IsEntryItemLike(buttonData) then
        local effectiveItem = ResolveEffectiveItem(buttonData, true)
        button._resolvedItemId = effectiveItem and effectiveItem.itemID or buttonData.id
        button._resolvedItemAvailableQuantity = effectiveItem and effectiveItem.availableQuantity or 0
        button._resolvedItemQuantityKind = effectiveItem and effectiveItem.quantityKind or "stacks"
        button._equipmentSlotTrackable = CooldownCompanion.IsEquipmentSlotEntry(buttonData)
            and effectiveItem and effectiveItem.trackable == true or nil
    end

    ApplyCountTextStyle(button, style)

    -- Aura stack count text: separate FontString for aura stacks and config previews.
    button.auraStackCount = button.overlayFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.auraStackCount:SetText("")
    ApplyFontStyle(button.auraStackCount, style, "auraStack")
    local asAnchor = style.auraStackAnchor or "BOTTOMLEFT"
    local asXOff = style.auraStackXOffset or 2
    local asYOff = style.auraStackYOffset or 2
    button.auraStackCount:SetPoint(asAnchor, asXOff, asYOff)

    -- Keybind text overlay
    button.keybindText = button.overlayFrame:CreateFontString(nil, "OVERLAY")
    do
        ApplyFontStyle(button.keybindText, style, "keybind", 10)
        local anchor = style.keybindAnchor or "TOPRIGHT"
        local xOff = style.keybindXOffset or -2
        local yOff = style.keybindYOffset or -2
        button.keybindText:SetPoint(anchor, xOff, yOff)
        local text = CooldownCompanion:GetDisplayedKeybindText(buttonData, button._resolvedItemId, button)
        button.keybindText:SetText(text or "")
        button.keybindText:SetShown(style.showKeybindText and text ~= nil)
    end

    -- Apply configurable strata ordering (LoC always on top)
    ApplyStrataOrder(button, style.strataOrder)
    ApplyIconFillLayer(button)

    -- Store button data
    button.index = index
    button.style = style
    button._groupId = parent.groupId

    -- Cache spell cooldown secrecy level (static per-spell: NeverSecret=0, ContextuallySecret=2)
    if buttonData.type == "spell" then
        buttonData._cooldownSecrecy = C_Secrets.GetSpellCooldownSecrecy(buttonData.id)
    end

    -- Spell display texture-monitor cache
    button._lastSpellTexture = nil
    button._lastTextureCheckAt = nil

    -- Key press highlight runtime state
    button._keyPressHighlightActive = nil
    CacheButtonBindingKeys(button, buttonData)

    -- Per-button visibility runtime state
    button._visibilityHidden = false
    button._prevVisibilityHidden = false
    button._visibilityAlphaOverride = nil
    button._lastVisAlpha = 1

    -- Set icon
    self:UpdateButtonIcon(button)

    -- Methods
    button.UpdateCooldown = function(self)
        CooldownCompanion:UpdateButtonCooldown(self)
    end

    button.UpdateStyle = function(self, newStyle)
        CooldownCompanion:UpdateButtonStyle(self, newStyle)
    end

    -- Click-through is always enabled (clicks always pass through for camera movement)
    -- Motion (hover) is only enabled when tooltips are on
    local showTooltips = style.showTooltips == true and not IsCursorAnchoredButton(button)
    local disableClicks = true
    local disableMotion = not showTooltips

    -- Apply to the button frame and all children recursively
    SetFrameClickThroughRecursive(button, disableClicks, disableMotion)
    -- Re-apply full click-through on overlay frames (the recursive call above
    -- re-enables motion on them when tooltips are on, causing them to steal hover events)
    SetFrameClickThroughRecursive(button.cooldown, true, true)
    if button.iconFill then
        SetFrameClickThroughRecursive(button.iconFill, true, true)
    end
    SetFrameClickThroughRecursive(button.locCooldown, true, true)
    if button.procGlow then
        SetFrameClickThroughRecursive(button.procGlow.solidFrame, true, true)
        SetFrameClickThroughRecursive(button.procGlow.procFrame, true, true)
    end
    if button.overlayFrame then
        SetFrameClickThroughRecursive(button.overlayFrame, true, true)
    end
    if button.assistedHighlight then
        if button.assistedHighlight.solidFrame then
            SetFrameClickThroughRecursive(button.assistedHighlight.solidFrame, true, true)
        end
        if button.assistedHighlight.blizzardFrame then
            SetFrameClickThroughRecursive(button.assistedHighlight.blizzardFrame, true, true)
        end
        if button.assistedHighlight.procFrame then
            SetFrameClickThroughRecursive(button.assistedHighlight.procFrame, true, true)
        end
    end
    if button.auraGlow then
        if button.auraGlow.solidFrame then
            SetFrameClickThroughRecursive(button.auraGlow.solidFrame, true, true)
        end
        if button.auraGlow.procFrame then
            SetFrameClickThroughRecursive(button.auraGlow.procFrame, true, true)
        end
    end
    if button.readyGlow then
        if button.readyGlow.solidFrame then
            SetFrameClickThroughRecursive(button.readyGlow.solidFrame, true, true)
        end
        if button.readyGlow.procFrame then
            SetFrameClickThroughRecursive(button.readyGlow.procFrame, true, true)
        end
    end
    if button.keyPressHighlight then
        if button.keyPressHighlight.solidFrame then
            SetFrameClickThroughRecursive(button.keyPressHighlight.solidFrame, true, true)
        end
        if button.keyPressHighlight.procFrame then
            SetFrameClickThroughRecursive(button.keyPressHighlight.procFrame, true, true)
        end
    end
    -- Set tooltip scripts when tooltips are enabled (regardless of click-through)
    if showTooltips then
        SetupTooltipScripts(button)
    end

    ApplyAuraShellVisuals(button, buttonData)

    return button
end

function CooldownCompanion:UpdateButtonIcon(button)
    local buttonData = button.buttonData
    local icon
    local hasIcon = false
    local displayId = buttonData.id
    local overrideId = nil
    local forceBaseDisplay = button._forceBaseDisplaySpellId == true
    local function UseIcon(value, knownAvailable)
        local selectedIcon, selectedAvailable = SelectTextureValue(value, knownAvailable)
        if selectedAvailable then
            icon = selectedIcon
            hasIcon = true
        end
        return selectedAvailable
    end

    if buttonData._rotationAssistantVirtual == true and buttonData._rotationAssistantMissing == true then
        UseIcon(self:GetRotationAssistantFallbackIcon(), true)
        button._displaySpellId = nil
        if hasIcon then
            button.icon:SetTexture(icon)
        else
            button.icon:SetTexture(QUESTION_MARK_ICON)
        end
        return
    end

    if buttonData.type == "spell" then
        overrideId = C_Spell.GetOverrideSpell(buttonData.id)
        if overrideId == buttonData.id or overrideId == 0 then
            overrideId = nil
        end
        if forceBaseDisplay then
            overrideId = nil
        end
        -- Look up viewer child for current override info (icon, display name).
        -- For override spells (ability→buff mapping), viewerAuraFrames may point
        -- to a BuffIcon/BuffBar child whose spellID is the buff, not the ability.
        -- Scan for an Essential/Utility child that tracks the transforming spell.
        local child = ResolveViewerChildForSpellDisplay(CooldownCompanion, buttonData)
        if child and child.cooldownInfo and not forceBaseDisplay then
            -- Track the current override for display name and aura lookups
            if child.cooldownInfo.overrideSpellID then
                displayId = child.cooldownInfo.overrideSpellID
            end
            if overrideId then
                displayId = overrideId
            end
            -- For multi-slot buttons, read the CDM's already-rendered icon texture
            -- directly from the viewer child's Icon widget. This avoids secret
            -- values (child.auraSpellID is secret in combat) and guarantees the
            -- icon matches what the CDM viewer displays.
            -- BuffIcon children: child.Icon is a Texture.
            -- BuffBar children: child.Icon is a Frame containing child.Icon.Icon.
            -- For single-child buttons, use the base spellID — GetSpellTexture on
            -- a base spell dynamically returns the current override's icon.
            if buttonData.cdmChildSlot then
                local iconTexture = child.Icon
                if iconTexture and not iconTexture.GetTextureFileID then
                    iconTexture = iconTexture.Icon
                end
                if iconTexture and iconTexture.GetTextureFileID then
                    -- GetTextureFileID may return a secret value in combat;
                    -- pass it straight through — do not test or branch on it.
                    UseIcon(iconTexture:GetTextureFileID())
                else
                    -- No icon widget found — use spell API fallback.
                    -- Always use buttonData.id: GetSpellTexture dynamically
                    -- resolves the current visual (including talent transforms).
                    UseIcon(C_Spell.GetSpellTexture(buttonData.id))
                end
            else
                -- Non-cdmChildSlot buttons: GetSpellTexture on the base spell
                -- dynamically resolves the current visual (including talent
                -- transforms).
                UseIcon(C_Spell.GetSpellTexture(buttonData.id))
            end
        end
        -- Always validate displayId against the Spell API — the viewer child may
        -- have a stale override that hasn't caught up to the current transform yet.
        if overrideId then
            displayId = overrideId
        end
        if not hasIcon then
            -- Always use buttonData.id: GetSpellTexture dynamically
            -- resolves the current visual (including talent transforms).
            UseIcon(C_Spell.GetSpellTexture(buttonData.id))
        end
    elseif IsEntryItemLike(buttonData) then
        local itemID = button._resolvedItemId or buttonData.id
        if itemID then
            UseIcon(C_Item.GetItemIconByID(itemID))
        end
    end

    -- Manual icon override: replaces base icon. (The 12.1 aura icon swap is
    -- Blizzard-driven on the aura display layer — see Core/AuraDisplay.lua.)
    local manualIcon = buttonData.manualIcon
    if type(manualIcon) == "number" or type(manualIcon) == "string" then
        icon = manualIcon
        hasIcon = true
    end

    local prevDisplayId = button._displaySpellId
    button._displaySpellId = displayId

    if hasIcon then
        button.icon:SetTexture(icon)
    else
        button.icon:SetTexture(QUESTION_MARK_ICON)
    end

    -- Update cooldown secrecy when override spell changes (e.g. Command Demon → pet ability)
    if displayId ~= prevDisplayId and buttonData.type == "spell" then
        buttonData._cooldownSecrecy = C_Secrets.GetSpellCooldownSecrecy(displayId)
        -- The router's index keys on _displaySpellId, and silent transforms
        -- mutate it here with no structural rebuild -- without one, a cooldown
        -- fire for the new identity index-misses and is dropped. Change-edge
        -- only, so steady-state walks request nothing. Virtual buttons are
        -- index-excluded and churn permanently; never rebuild for them.
        if buttonData._rotationAssistantVirtual ~= true then
            self:RequestSpellButtonIndexRebuild("display-id")
        end
    end

    -- Update bar name text when the display spell changes (e.g. transform)
    if button.nameText and not buttonData.customName and buttonData.type == "spell" and displayId ~= prevDisplayId then
        local spellName = C_Spell.GetSpellName(displayId)
        if spellName then
            button.nameText:SetText(spellName)
        end
    end
end

local function ApplyIconDesaturationIntent(button, buttonData, style)
    if type(ResolveIconDesaturationIntent) ~= "function" then
        EvaluateDesaturation(button, buttonData, style)
        return
    end

    local intent = button._iconDesaturationIntent
    if type(intent) ~= "table" then
        intent = {}
        button._iconDesaturationIntent = intent
    end

    ResolveIconDesaturationIntent(button, buttonData, style, intent)

    if button._desaturated ~= intent.active then
        button._desaturated = intent.active
        button.icon:SetDesaturated(intent.active)
    end
end

-- Update icon-mode visuals: GCD suppression, cooldown text, desaturation, and vertex color.
local function UpdateIconModeVisuals(button, buttonData, style, fetchOk, isOnGCD, isGCDOnly)
    -- GCD suppression (isOnGCD is NeverSecret, always readable)
    -- Passives never suppress — always show cooldown widget for aura swipe
    if fetchOk and not buttonData.isPassive then
        -- Suppress only true GCD-only state. The extra presentation-state guard
        -- keeps any explicit real-cooldown presentation from being hidden here.
        local suppressGCD = not style.showGCDSwipe
            and isGCDOnly
            and button._chargeCooldownVisualActive ~= true
            and button._cooldownState ~= COOLDOWN_STATE_COOLDOWN

        local realCooldownSwipeActive = button._cooldownState == COOLDOWN_STATE_COOLDOWN
            and button._cooldownDeferred ~= true
        local cooldownVisualActive = realCooldownSwipeActive
            or button._conditionalPreviewDomain == "cooldown"
            or button._chargeCooldownVisualActive == true
            or (isGCDOnly and style.showGCDSwipe == true)

        if suppressGCD or not cooldownVisualActive then
            button.cooldown:Hide()
        else
            button.cooldown:Show()
        end
    end

    -- Charge-visual suppression: when toggle is active and charges remain,
    -- hide the swipe fill (dark overlay) but keep the edge visible.
    if UsesChargeBehavior(buttonData) and buttonData.hideCooldownWithCharges
            and not HasItemFallbacks(buttonData) then
        local hasChargesRemaining = (button._chargeState ~= CHARGE_STATE_ZERO)
        if hasChargesRemaining ~= button._hideCooldownChargesActive then
            button._hideCooldownChargesActive = hasChargesRemaining
            if hasChargesRemaining then
                button.cooldown:SetDrawSwipe(false)
            else
                ApplyDefaultCooldownSwipeStyle(button, style)
            end
        end
    elseif button._hideCooldownChargesActive ~= nil then
        button._hideCooldownChargesActive = nil
        ApplyDefaultCooldownSwipeStyle(button, style)
    end

    UpdateIconFill(button, buttonData, style)

    -- Independent GCD swipe. Runs AFTER UpdateIconFill because it also writes
    -- button.cooldown's swipe flags -- being the final owner for the pass is
    -- what keeps the latch honest. Bar mode draws its GCD radial from a
    -- dedicated frame, so Show GCD Swipe works there even with the main swipe
    -- off; icon mode shares button.cooldown, whose flags
    -- ApplyDefaultCooldownSwipeStyle gates on showCooldownSwipe, so a GCD-only
    -- radial drew nothing when the main swipe was off. Only in that case, draw
    -- it ourselves, mirroring bar mode (sweep on, edge per
    -- showCooldownSwipeEdge). Latched to avoid per-tick writes; the falling
    -- edge restores default styling and runs unconditionally, so a fetchOk
    -- false tick can't strand the latch. Defers to real cooldown (isGCDOnly
    -- excludes it), icon-fill owner, charge-visual, hideCooldownWithCharges,
    -- and previews.
    local gcdOnlyRadialActive = fetchOk
        and not buttonData.isPassive
        and isGCDOnly
        and style.showGCDSwipe == true
        and style.showCooldownSwipe == false
        and button._iconFillActive ~= true
        and button._chargeCooldownVisualActive ~= true
        and button._hideCooldownChargesActive ~= true
        and button._conditionalPreviewDomain ~= "cooldown"

    if gcdOnlyRadialActive then
        if button._gcdSwipeDrawActive ~= true then
            button._gcdSwipeDrawActive = true
            button.cooldown:SetDrawSwipe(true)
            button.cooldown:SetDrawEdge(style.showCooldownSwipeEdge ~= false)
            button.cooldown:SetReverse(style.cooldownSwipeReverse or false)
        end
    elseif button._gcdSwipeDrawActive == true then
        button._gcdSwipeDrawActive = nil
        ApplyDefaultCooldownSwipeStyle(button, style)
    end

    -- Cooldown text: visibility + color. (Aura duration text is drawn by the
    -- aura display layer — see Core/AuraDisplay.lua.)
    -- Color is reapplied each tick because WoW's CooldownFrame may reset it.
    if button._cdTextRegion then
        local showText, fontColor
        if buttonData.isPassive then
            -- Passive aura entry: no cooldown text (cooldown frame hidden)
            button._cdTextRegion:SetTextColor(0, 0, 0, 0)
        else
            showText = style.showCooldownText
            if showText and button._hideCooldownChargesActive then
                showText = false
            end
            fontColor = style.cooldownFontColor or DEFAULT_WHITE
        end
        if showText then
            local cc = fontColor
            button._cdTextRegion:SetTextColor(cc[1], cc[2], cc[3], cc[4])
        else
            button._cdTextRegion:SetTextColor(0, 0, 0, 0)
        end
        -- Properly hide/show countdown numbers via API (alpha=0 alone is unreliable
        -- because WoW's CooldownFrame animation resets text color each tick)
        local wantHide = not showText
        if button._cdTextHidden ~= wantHide then
            button._cdTextHidden = wantHide
            button.cooldown:SetHideCountdownNumbers(wantHide)
        end
    end

    ApplyIconDesaturationIntent(button, buttonData, style)

    UpdateIconTint(button, buttonData, style)
end

-- Update icon-mode glow effects: loss of control, assisted highlight, proc glow, aura glow.
local function UpdateIconModeGlows(button, buttonData, style, procOverlayActive)
    local inCombat = InCombatLockdown()

    -- Loss of control overlay
    UpdateLossOfControl(button)

    if buttonData._rotationAssistantVirtual == true then
        SetAssistedHighlight(button, false)
        SetProcGlow(button, false)
        SetAuraGlow(button, false, false)
        SetReadyGlow(button, false)
        SetKeyPressHighlight(button, false)
        return
    end

    -- Assisted highlight glow
    if button.assistedHighlight then
        local assistedSpellID = CooldownCompanion.assistedSpellID
        local displayId = button._displaySpellId or buttonData.id
        local hostileOnly = style.assistedHighlightHostileTargetOnly ~= false
        local showHighlight = style.showAssistedHighlight
            and (not style.assistedHighlightCombatOnly or inCombat)
            and buttonData.type == "spell"
            and (not hostileOnly or CooldownCompanion._assistedHighlightHasHostileTarget)
            and assistedSpellID
            and (displayId == assistedSpellID
                 or buttonData.id == assistedSpellID
                 or C_Spell.GetOverrideSpell(buttonData.id) == assistedSpellID)

        SetAssistedHighlight(button, showHighlight)
    end

    local glowIntent
    if type(ResolveIconGlowIntent) == "function" then
        glowIntent = button._iconGlowIntent
        if type(glowIntent) ~= "table" then
            glowIntent = {}
            button._iconGlowIntent = glowIntent
        end
        ResolveIconGlowIntent(button, buttonData, style, procOverlayActive, glowIntent, {
            inCombat = inCombat,
        })
    end

    -- Proc glow (spell activation overlay)
    if button.procGlow then
        local showProc = glowIntent and glowIntent.proc and glowIntent.proc.active == true
        SetProcGlow(button, showProc)
    end

    -- Aura active glow indicator
    if button.auraGlow then
        local auraIntent = glowIntent and glowIntent.aura
        local showAuraGlow = auraIntent and auraIntent.active == true
        local pandemicOverride = auraIntent and auraIntent.pandemic == true or false
        SetAuraGlow(button, showAuraGlow, pandemicOverride)
    end

    -- Ready glow (glow while off cooldown)
    if button.readyGlow then
        local readyIntent = glowIntent and glowIntent.ready
        local showReady = readyIntent and readyIntent.active == true
        -- F2 canary: a finite ready-glow duration window is lit this walk; its
        -- OFF edge is walk-evaluated (covered by the ready-glow window
        -- classifier term). durationWindow is reset on every resolve, so this
        -- cannot read a stale flag.
        if showReady and readyIntent.durationWindow == true then
            RefreshTelemetry:NoteTimeRender()
        end
        SetReadyGlow(button, showReady)
    end
end

function CooldownCompanion:UpdateButtonStyle(button, style)
    local width, height

    if style.maintainAspectRatio then
        -- Square mode: use buttonSize for both dimensions
        local size = style.buttonSize or ST.BUTTON_SIZE
        width = size
        height = size
    else
        -- Non-square mode: use separate width/height
        width = style.iconWidth or style.buttonSize or ST.BUTTON_SIZE
        height = style.iconHeight or style.buttonSize or ST.BUTTON_SIZE
    end

    local borderSize = style.borderSize or ST.DEFAULT_BORDER_SIZE
    local borderRenderMode = ST.GetBorderRenderMode(style)
    local borderLayoutSize = ST.GetEffectiveBorderLayoutSize(button, borderSize, borderRenderMode)

    -- Store updated style reference
    button.style = style
    if ClearButtonVisualState then
        ClearButtonVisualState(button)
    end

    -- Invalidate cached widget state so next tick reapplies everything
    button._desaturated = nil
    button._iconDesaturationIntent = nil
    button._iconTintIntent = nil
    button._iconFillIntent = nil
    button._iconGlowIntent = nil
    button._desatCooldownActive = nil
    button._readyGlowStartTime = nil
    button._readyGlowMaxChargesStartTime = nil
    button._readyGlowMaxChargesActive = nil
    button._readyGlowMaxChargesSpellID = nil
    button._noCooldown = nil
    button._noCooldownSpellId = nil
    button._baseNoCooldown = nil
    button._baseNoCooldownSpellId = nil
    button._resourceGateCost = nil
    button._resourceGateCostSpellId = nil
    button._baseResourceGateCost = nil
    button._baseResourceGateCostSpellId = nil
    button._vertexR = nil
    button._vertexG = nil
    button._vertexB = nil
    button._vertexA = nil
    button._chargeText = nil
    button._chargeCountReadable = nil
    button._zeroChargesConfirmed = nil
    button._hideCooldownChargesActive = nil
    button._gcdSwipeDrawActive = nil
    button._nilConfirmPending = nil
    button._procGlowActive = nil
    button._auraGlowActive = nil
    button._readyGlowActive = nil
    button._keyPressHighlightActive = nil
    button._displaySpellId = nil
    button._liveOverrideSpellId = nil
    button._spellOutOfRange = nil
    button._itemCount = nil
    button._lastSpellTexture = nil
    button._lastTextureCheckAt = nil

    button._iconFillActive = nil
    button._iconFillMode = nil
    button._iconFillColorR = nil
    button._iconFillColorG = nil
    button._iconFillColorB = nil
    button._iconFillColorA = nil
    if button.auraStackCount then button.auraStackCount:SetText("") end
    if button._auraTextPreviewFS then button._auraTextPreviewFS:Hide() end
    if button._auraSwipePreviewCooldown then
        button._auraSwipePreviewCooldown:SetCooldown(0, 0)
        button._auraSwipePreviewCooldown:Hide()
    end
    button._visibilityHidden = false
    button._prevVisibilityHidden = false
    button._visibilityAlphaOverride = nil
    button._lastVisAlpha = 1

    button:SetSize(width, height)

    -- Update icon position
    button.icon:ClearAllPoints()
    button.icon:SetPoint("TOPLEFT", borderLayoutSize, -borderLayoutSize)
    button.icon:SetPoint("BOTTOMRIGHT", -borderLayoutSize, borderLayoutSize)

    ApplyIconTexCoord(button.icon, width, height)

    if button.iconFill then
        AnchorIconFill(button)
        button.iconFill:SetMinMaxValues(0, 1)
        button.iconFill:SetValue(0)
        ApplyIconFillGeometry(button, style)
        button.iconFill:SetStatusBarTexture(ICON_FILL_TEXTURE)
        button.iconFill:SetScript("OnUpdate", nil)
        button._iconFillOnUpdateInstalled = nil
        button.iconFill:Hide()
    end

    -- Update border textures
    local borderColor = style.borderColor or {0, 0, 0, 1}
    if button.borderTextures then
        ApplyBorderEdgePositions(button.borderTextures, button, borderSize, borderRenderMode)
        for _, tex in ipairs(button.borderTextures) do
            tex:SetColorTexture(unpack(borderColor))
        end
    end

    local bgColor = style.backgroundColor or {0, 0, 0, 0.5}
    button.bg:SetColorTexture(unpack(bgColor))

    -- Countdown number visibility is controlled per-tick via SetHideCountdownNumbers
    button.cooldown:SetHideCountdownNumbers(false)
    ApplyDurationFormatToCooldown(button.cooldown, style)
    ApplyDefaultCooldownSwipeStyle(button, style)

    -- Update cooldown font settings. The countdown region may be hosted in
    -- the overlay frame (separateTextPositions on aura entries), so use the
    -- stored reference — the Cooldown frame's region list can't be re-fetched.
    local region = button._cdTextRegion
    if region and region.SetFont then
        ApplyFontStyle(region, style, "cooldown")
    end
    ApplyCooldownTextHost(button, button.buttonData, style)
    button._cdTextHidden = nil

    -- Update count text font/anchor settings from effective style
    ApplyCountTextStyle(button, style)

    -- Update aura stack count font/anchor settings
    if button.auraStackCount then
        button.auraStackCount:ClearAllPoints()
        ApplyFontStyle(button.auraStackCount, style, "auraStack")
        local asAnchor = style.auraStackAnchor or "BOTTOMLEFT"
        local asXOff = style.auraStackXOffset or 2
        local asYOff = style.auraStackYOffset or 2
        button.auraStackCount:SetPoint(asAnchor, asXOff, asYOff)
    end

    -- Update keybind text overlay
    if button.keybindText then
        ApplyFontStyle(button.keybindText, style, "keybind", 10)
        button.keybindText:ClearAllPoints()
        local anchor = style.keybindAnchor or "TOPRIGHT"
        local xOff = style.keybindXOffset or -2
        local yOff = style.keybindYOffset or -2
        button.keybindText:SetPoint(anchor, xOff, yOff)
        local text = CooldownCompanion:GetDisplayedKeybindText(button.buttonData, button._resolvedItemId, button)
        button.keybindText:SetText(text or "")
        button.keybindText:SetShown(style.showKeybindText and text ~= nil)
    end

    -- Update highlight overlay positions and hide all
    if button.assistedHighlight then
        local highlightSize = style.assistedHighlightBorderSize or 2
        ApplyEdgePositions(button.assistedHighlight.solidTextures, button, highlightSize)
        if button.assistedHighlight.blizzardFrame then
            FitHighlightFrame(button.assistedHighlight.blizzardFrame, button, style.assistedHighlightBlizzardOverhang)
        end
        if button.assistedHighlight.procFrame then
            FitHighlightFrame(button.assistedHighlight.procFrame, button, style.assistedHighlightProcOverhang)
        end
        button.assistedHighlight.currentState = nil -- reset so next tick re-applies
        SetAssistedHighlight(button, false)
    end

    -- Update loss of control cooldown frame
    if button.locCooldown then
        button.locCooldown:SetSwipeColor(0.17, 0, 0, 0.8)
        button.locCooldown:Clear()
    end

    -- Update proc glow frames
    if button.procGlow then
        button.procGlow.solidFrame:SetAllPoints()
        ApplyEdgePositions(button.procGlow.solidTextures, button, style.procGlowSize or 2)
        FitHighlightFrame(button.procGlow.procFrame, button, style.procGlowSize or 32)
        SetProcGlow(button, false)
    end

    -- Update aura glow frames
    if button.auraGlow then
        button.auraGlow.solidFrame:SetAllPoints()
        ApplyEdgePositions(button.auraGlow.solidTextures, button, button.style.auraGlowSize or 2)
        FitHighlightFrame(button.auraGlow.procFrame, button, button.style.auraGlowSize or 32)
        SetAuraGlow(button, false)
    end

    -- Update ready glow frames
    if button.readyGlow then
        button.readyGlow.solidFrame:SetAllPoints()
        ApplyEdgePositions(button.readyGlow.solidTextures, button, button.style.readyGlowSize or 2)
        FitHighlightFrame(button.readyGlow.procFrame, button, button.style.readyGlowSize or 32)
        SetReadyGlow(button, false)
    end

    -- Update key press highlight frames
    if button.keyPressHighlight then
        button.keyPressHighlight.solidFrame:SetAllPoints()
        ApplyEdgePositions(button.keyPressHighlight.solidTextures, button, button.style.keyPressHighlightSize or 5)
        -- Only reset the glow if not in preview mode; force cache re-evaluation on next frame
        if not button._keyPressHighlightPreview then
            SetKeyPressHighlight(button, false)
        end
        button._keyPressHighlightActive = nil
        RefreshKeyPressHighlightEnrollment(button)
    end

    -- Apply configurable strata ordering (LoC always on top)
    ApplyStrataOrder(button, style.strataOrder)
    ApplyIconFillLayer(button)
    CooldownCompanion:UpdateAuraTextureVisual(button)

    -- Click-through is always enabled (clicks always pass through for camera movement)
    -- Motion (hover) is only enabled when tooltips are on
    local showTooltips = style.showTooltips == true and not IsCursorAnchoredButton(button)
    local disableClicks = true
    local disableMotion = not showTooltips

    -- Apply to the button frame and all children recursively
    SetFrameClickThroughRecursive(button, disableClicks, disableMotion)
    -- Re-apply full click-through on overlay frames (the recursive call above
    -- re-enables motion on them when tooltips are on, causing them to steal hover events)
    SetFrameClickThroughRecursive(button.cooldown, true, true)
    if button.iconFill then
        SetFrameClickThroughRecursive(button.iconFill, true, true)
    end
    SetFrameClickThroughRecursive(button.locCooldown, true, true)
    if button.procGlow then
        SetFrameClickThroughRecursive(button.procGlow.solidFrame, true, true)
        SetFrameClickThroughRecursive(button.procGlow.procFrame, true, true)
    end
    if button.overlayFrame then
        SetFrameClickThroughRecursive(button.overlayFrame, true, true)
    end
    if button.assistedHighlight then
        if button.assistedHighlight.solidFrame then
            SetFrameClickThroughRecursive(button.assistedHighlight.solidFrame, true, true)
        end
        if button.assistedHighlight.blizzardFrame then
            SetFrameClickThroughRecursive(button.assistedHighlight.blizzardFrame, true, true)
        end
        if button.assistedHighlight.procFrame then
            SetFrameClickThroughRecursive(button.assistedHighlight.procFrame, true, true)
        end
    end
    if button.auraGlow then
        if button.auraGlow.solidFrame then
            SetFrameClickThroughRecursive(button.auraGlow.solidFrame, true, true)
        end
        if button.auraGlow.procFrame then
            SetFrameClickThroughRecursive(button.auraGlow.procFrame, true, true)
        end
    end
    if button.readyGlow then
        if button.readyGlow.solidFrame then
            SetFrameClickThroughRecursive(button.readyGlow.solidFrame, true, true)
        end
        if button.readyGlow.procFrame then
            SetFrameClickThroughRecursive(button.readyGlow.procFrame, true, true)
        end
    end
    if button.keyPressHighlight then
        if button.keyPressHighlight.solidFrame then
            SetFrameClickThroughRecursive(button.keyPressHighlight.solidFrame, true, true)
        end
        if button.keyPressHighlight.procFrame then
            SetFrameClickThroughRecursive(button.keyPressHighlight.procFrame, true, true)
        end
    end

    -- Re-set aura/ready glow frame levels after strata order
    if button.auraGlow then
        local auraGlowLevel = button.cooldown:GetFrameLevel() + 1
        button.auraGlow.solidFrame:SetFrameLevel(auraGlowLevel)
        button.auraGlow.procFrame:SetFrameLevel(auraGlowLevel)
    end
    if button.readyGlow then
        local readyGlowLevel = button.cooldown:GetFrameLevel() + 1
        button.readyGlow.solidFrame:SetFrameLevel(readyGlowLevel)
        button.readyGlow.procFrame:SetFrameLevel(readyGlowLevel)
    end
    if button.keyPressHighlight then
        local kphLevel = button.cooldown:GetFrameLevel() + 1
        button.keyPressHighlight.solidFrame:SetFrameLevel(kphLevel)
        button.keyPressHighlight.procFrame:SetFrameLevel(kphLevel)
    end

    -- Set tooltip scripts when tooltips are enabled (regardless of click-through)
    if showTooltips then
        SetupTooltipScripts(button)
    end

    ApplyAuraShellVisuals(button, button.buttonData)
end

-- Exports
ST._RefreshKeyPressHighlightEnrollment = RefreshKeyPressHighlightEnrollment
ST._UnregisterKeyPressHighlightButton = UnregisterKeyPressHighlightButton
ST._UpdateIconModeVisuals = UpdateIconModeVisuals
ST._UpdateIconModeGlows = UpdateIconModeGlows
ST._ApplyIconCountTextStyle = ApplyCountTextStyle
ST._ApplyAuraShellVisuals = ApplyAuraShellVisuals
ST._ClearIconFillVisualState = ClearIconFillVisualState
