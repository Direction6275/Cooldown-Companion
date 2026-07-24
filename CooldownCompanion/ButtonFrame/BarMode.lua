--[[
    CooldownCompanion - ButtonFrame/BarMode
    Bar-mode button creation, styling, fill animation, and display updates
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CooldownLogic = ST.CooldownLogic
local EntryRuntime = ST.EntryRuntime
local COOLDOWN_STATE_COOLDOWN = CooldownLogic.STATE_COOLDOWN
local CHARGE_STATE_MISSING = CooldownLogic.CHARGE_STATE_MISSING
local CHARGE_STATE_ZERO = CooldownLogic.CHARGE_STATE_ZERO

-- Localize frequently-used globals
local GetTime = GetTime
local pairs = pairs
local ipairs = ipairs
local unpack = unpack

-- Imports from Helpers
local SetIconAreaPoints = ST._SetIconAreaPoints
local SetBarAreaPoints = ST._SetBarAreaPoints
local AnchorBarCountText = ST._AnchorBarCountText
local ApplyBorderEdgePositions = ST._ApplyBorderEdgePositions
local UsesChargeBehavior = CooldownCompanion.UsesChargeBehavior
local UsesChargeTextLane = CooldownCompanion.UsesChargeTextLane
local DEFAULT_BAR_CHARGE_COLOR = ST._DEFAULT_BAR_CHARGE_COLOR

-- Imports from VisualState
local ClearButtonVisualState = ST._ClearButtonVisualState
local AreButtonVisualStateSnapshotsEnabled = ST._AreButtonVisualStateSnapshotsEnabled

-- Pre-defined color constant tables to avoid per-tick allocation.
-- IMPORTANT: These tables are read-only — never write to their indices.
local DEFAULT_WHITE = {1, 1, 1, 1}
local DEFAULT_BAR_COLOR = {0.2, 0.6, 1.0, 1.0}
local DEFAULT_READY_TEXT_COLOR = {0.2, 1.0, 0.2, 1.0}

-- Imports from Glows
local ShowButtonTooltip = ST._ShowButtonTooltip

-- Imports from Visibility
local UpdateLossOfControl = ST._UpdateLossOfControl

-- Imports from Tracking
local UpdateIconTint = ST._UpdateIconTint
local EvaluateDesaturation = ST._EvaluateDesaturation

-- Shared click-through helpers from Utils.lua
local SetFrameClickThroughRecursive = ST.SetFrameClickThroughRecursive
local SetStatusBarImmediateRange = ST.SetStatusBarImmediateRange
local SetStatusBarImmediateValue = ST.SetStatusBarImmediateValue
local SetStatusBarSmoothRange = ST.SetStatusBarSmoothRange
local SetStatusBarSmoothValue = ST.SetStatusBarSmoothValue
local SetStatusBarElapsedDuration = ST.SetStatusBarElapsedDuration

local BAR_TEXT_UPDATE_INTERVAL = 0.1

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
local FormatTime = CooldownCompanion.FormatTime
local BindDurationText = CooldownCompanion.BindDurationText or function() return false end
local UnbindDurationText = CooldownCompanion.UnbindDurationText or function() end
local ApplyFontStyle = CooldownCompanion.ApplyFontStyle

-- Bar mode tooltip behavior: tooltip should come from hovering the icon area only.
local function SetBarIconTooltipScripts(button, enable)
    local iconBounds = button and button._iconBounds
    if not iconBounds then return end

    if enable then
        iconBounds:SetScript("OnEnter", function()
            local bd = button.buttonData
            if not bd then return end
            GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
            ShowButtonTooltip(button, GameTooltip)
            GameTooltip:Show()
        end)
        iconBounds:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    else
        iconBounds:SetScript("OnEnter", nil)
        iconBounds:SetScript("OnLeave", nil)
    end
end

local function ShouldStoreBarVisualState()
    return type(AreButtonVisualStateSnapshotsEnabled) == "function"
        and AreButtonVisualStateSnapshotsEnabled() == true
end

local function EnsureBarVisualTable(button, fieldName)
    local target = button[fieldName]
    if target then
        wipe(target)
    else
        target = {}
        button[fieldName] = target
    end
    return target
end

local function ClearBarVisualState(button)
    if button then
        button._barVisualIntent = nil
        button._barVisualApplied = nil
    end
end

local function StoreBarDisplayVisualState(button, details)
    local intent = EnsureBarVisualTable(button, "_barVisualIntent")
    intent.domain = details.domain
    intent.colorReason = details.colorReason
    intent.gcdSuppressed = button._barGCDSuppressed == true

    local applied = EnsureBarVisualTable(button, "_barVisualApplied")
    applied.colorReason = details.colorReason
    applied.gcdSuppressed = button._barGCDSuppressed == true
end

-- Manual text helpers unbind native duration text before writing fallback text.
local function SetBarTimeText(button, text)
    UnbindDurationText(button.timeText)
    if button._lastBarTimeText ~= text then
        button._lastBarTimeText = text
        button.timeText:SetText(text)
    end
end

local function UpdateBarFill(button)
    -- Single-bar path
    -- DurationObjects are handed to StatusBar:SetTimerDuration so drain/fill motion
    -- is engine-driven instead of re-sampled as Lua percentages.
    -- HasSecretValues gates expiry detection and time text formatting.
    -- Items use stored C_Item.GetItemCooldown values (_itemCdStart/_itemCdDuration).
    local onCooldown = false
    local itemRemaining = 0

    if button._durationObj and not button._barGCDSuppressed then
        onCooldown = true
        SetStatusBarSmoothRange(button.statusBar, 0, 1)
        if not SetStatusBarElapsedDuration(button.statusBar, button._durationObj) then
            SetStatusBarSmoothValue(button.statusBar, button._durationObj:GetElapsedPercent())     -- fill: 0->1
        end
    elseif button._cooldownDeferred then
        -- Deferred cooldown (timer hasn't started): show as "on cooldown"
        -- with a static full bar (no animation, no time text).
        onCooldown = true
        SetStatusBarImmediateRange(button.statusBar, 0, 1)
        SetStatusBarImmediateValue(button.statusBar, 0)
    elseif IsEntryItemLike(button.buttonData) then
        -- Items: use stored C_Item.GetItemCooldown values (avoids hidden-widget staleness)
        SetStatusBarSmoothRange(button.statusBar, 0, 1)
        local startMs = (button._itemCdStart or 0) * 1000
        local durationMs = (button._itemCdDuration or 0) * 1000
        local now = GetTime() * 1000
        onCooldown = durationMs > 0
        if onCooldown and button._barGCDSuppressed then onCooldown = false end
        if onCooldown then
            local elapsed = now - startMs
            itemRemaining = (durationMs - elapsed) / 1000
            local frac = elapsed / durationMs
            if frac > 1 then frac = 1 end
            SetStatusBarSmoothValue(button.statusBar, frac)
        end
    end

    if onCooldown then
        if button.style.showCooldownText then
            -- Switch font/color when mode changes
            if button._barTextMode ~= "cd" then
                button._barTextMode = "cd"
                button._barTextColorDirty = true
                local f = CooldownCompanion:FetchFont(button.style.cooldownFont or "Friz Quadrata TT")
                local s = button.style.cooldownFontSize or 12
                local o = ST.GetEffectiveFontOutline(button.style.cooldownFontOutline or "OUTLINE")
                button.timeText:SetFont(f, s, o)
                ST.ApplyFontShadowForOutline(button.timeText, o)
            end
            if button._barTextColorDirty then
                button._barTextColorDirty = nil
                local cc = button.style.cooldownFontColor or DEFAULT_WHITE
                button.timeText:SetTextColor(cc[1], cc[2], cc[3], cc[4])
            end
            -- Eligible DurationObjects use native text binding; other timer sources stay on the manual path.
            local durationStyle = button.style
            if button._durationObj then
                button._lastBarTimeText = nil
                BindDurationText(button.timeText, button._durationObj, durationStyle)
            else
                if itemRemaining > 0 then
                    SetBarTimeText(button, FormatTime(itemRemaining, durationStyle))
                else
                    SetBarTimeText(button, "")
                end
            end
        else
            SetBarTimeText(button, "")
        end
    else
        if button.buttonData.isPassive then
            SetStatusBarImmediateValue(button.statusBar, 0)
            SetBarTimeText(button, "")
        else
            SetStatusBarImmediateValue(button.statusBar, 1)
            if button.style.showBarReadyText then
                if button._barTextMode ~= "ready" then
                    button._barTextMode = "ready"
                    local f = CooldownCompanion:FetchFont(button.style.barReadyFont or "Friz Quadrata TT")
                    local s = button.style.barReadyFontSize or 12
                    local o = ST.GetEffectiveFontOutline(button.style.barReadyFontOutline or "OUTLINE")
                    button.timeText:SetFont(f, s, o)
                    ST.ApplyFontShadowForOutline(button.timeText, o)
                end
                SetBarTimeText(button, button.style.barReadyText or "Ready")
            else
                SetBarTimeText(button, "")
            end
        end
    end
end

local function ApplyBarCountTextStyle(button, style)
    if not button or not button.count then return end
    local buttonData = button.buttonData
    local showIcon = style.showBarIcon ~= false
    local defAnchor = showIcon and "BOTTOMRIGHT" or "BOTTOM"
    local defXOff = showIcon and -2 or 0
    local defYOff = 2
    local useChargeTextLane = buttonData
        and UsesChargeTextLane(buttonData)

    if useChargeTextLane then
        ApplyFontStyle(button.count, style, "charge")
        local chargeAnchor, chargeXOffset, chargeYOffset
        if showIcon then
            chargeAnchor = style.chargeAnchor or defAnchor
            chargeXOffset = style.chargeXOffset or defXOff
            chargeYOffset = style.chargeYOffset or defYOff
        else
            chargeAnchor = "CENTER"
            chargeXOffset = 0
            chargeYOffset = 0
        end
        AnchorBarCountText(button, showIcon, chargeAnchor, chargeXOffset, chargeYOffset)
    elseif buttonData and buttonData.type == "item" and not IsItemEquippable(buttonData) then
        ApplyFontStyle(button.count, buttonData, "itemCount")
        local itemAnchor = buttonData.itemCountAnchor or defAnchor
        local itemXOffset = buttonData.itemCountXOffset or defXOff
        local itemYOffset = buttonData.itemCountYOffset or defYOff
        AnchorBarCountText(button, showIcon, itemAnchor, itemXOffset, itemYOffset)
    else
        AnchorBarCountText(button, showIcon, defAnchor, defXOff, defYOff)
    end
    button._countTextLaneStyled = useChargeTextLane or false
end

-- Update bar-specific display elements (colors, desaturation, aura effects).
-- Bar fill + time text are handled by the per-button OnUpdate for smooth interpolation.
local function UpdateBarDisplay(button)
    local style = button.style
    local shouldStoreBarVisualState = ShouldStoreBarVisualState()
    if not shouldStoreBarVisualState and (button._barVisualIntent or button._barVisualApplied) then
        ClearBarVisualState(button)
    end

    -- "On cooldown" for bar color/ready text follows canonical state.
    local itemUsesResolvedCooldownState = IsEntryItemLike(button.buttonData)
        and button._resolvedItemQuantityKind == "stacks"
    local isChargeButton = UsesChargeBehavior(button.buttonData)
    local chargeState = button._chargeState
    local onCooldown
    if itemUsesResolvedCooldownState then
        onCooldown = button._cooldownState == COOLDOWN_STATE_COOLDOWN
    elseif isChargeButton then
        onCooldown = chargeState == CHARGE_STATE_MISSING
            or chargeState == CHARGE_STATE_ZERO
    else
        onCooldown = button._cooldownState == COOLDOWN_STATE_COOLDOWN
    end

    -- Time text color: switch between cooldown and ready colors
    local wantReadyTextColor = not onCooldown and style.showBarReadyText
    if button._barReadyTextColor ~= wantReadyTextColor then
        button._barReadyTextColor = wantReadyTextColor
        if wantReadyTextColor then
            local rc = style.barReadyTextColor or DEFAULT_READY_TEXT_COLOR
            button.timeText:SetTextColor(rc[1], rc[2], rc[3], rc[4])
        else
            local cc = style.cooldownFontColor or DEFAULT_WHITE
            button.timeText:SetTextColor(cc[1], cc[2], cc[3], cc[4])
        end
    end

    -- Bar color: switch between ready, cooldown, and partial charge colors.
    -- Aura-tracked buttons always use the base bar color (aura color override handles active state).
    local wantCdColor
    local cdColorReason
    if onCooldown and not button.buttonData.isPassive then
        if isChargeButton and chargeState == CHARGE_STATE_MISSING then
            wantCdColor = style.barChargeColor or DEFAULT_BAR_CHARGE_COLOR
            cdColorReason = "charge"
        else
            wantCdColor = style.barCooldownColor
            cdColorReason = "cooldown"
        end
    end
    if button._barCdColor ~= wantCdColor then
        button._barCdColor = wantCdColor
        local c = wantCdColor or style.barColor or DEFAULT_BAR_COLOR
        button.statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4])
    end

    EvaluateDesaturation(button, button.buttonData, style)

    -- Icon tinting (out-of-range red / unusable dim mode)
    UpdateIconTint(button, button.buttonData, style)

    -- Loss of control overlay on bar icon
    UpdateLossOfControl(button)

    if shouldStoreBarVisualState then
        local colorReason = cdColorReason or "ready"
        StoreBarDisplayVisualState(button, {
            domain = colorReason,
            onCooldown = onCooldown,
            chargeState = chargeState,
            colorReason = colorReason,
            color = wantCdColor or style.barColor or DEFAULT_BAR_COLOR,
        })
    end

    -- Keep the cooldown widget hidden — SetCooldown auto-shows it
    if button.cooldown:IsShown() then
        button.cooldown:Hide()
    end
end

-- Shared OnUpdate for bar-mode buttons: throttled bar fill/text refresh.
-- Reads interval from self._barTextUpdateInterval so it can be updated without re-installing.
local function BarModeOnUpdate(self, elapsed)
    self._barFillElapsed = self._barFillElapsed + elapsed
    if self._barFillElapsed >= (self._barTextUpdateInterval or BAR_TEXT_UPDATE_INTERVAL) then
        self._barFillElapsed = 0
        UpdateBarFill(self)
    end
end

-- Show-only-while-active bar entries (12.1 compositing): the aura display
-- slot renders the entire visible bar, so the CC frame stays shown as the
-- layout shell and slot host but every visual it owns goes transparent.
-- Static by design — no aura state exists to read at runtime. Mirror of
-- IconMode's ApplyAuraShellVisuals.
local function IsAuraShellEntry(buttonData)
    return buttonData
        and (buttonData.auraTracking or buttonData.addedAs == "aura")
        and buttonData.hideWhileAuraNotActive == true
end

local function ApplyBarAuraShellVisuals(button, buttonData)
    local alpha = IsAuraShellEntry(buttonData) and 0 or 1
    button.bg:SetAlpha(alpha)
    if button.iconBg then button.iconBg:SetAlpha(alpha) end
    -- The icon must be hidden by shown-state, not alpha: the per-tick tint
    -- pipeline's 4-arg SetVertexColor overwrites the texture's alpha through
    -- a non-SetAlpha C path (Phase 2 gotcha). Nothing else Shows the icon.
    button.icon:SetShown(alpha == 1)
    if button.borderTextures then
        for _, tex in ipairs(button.borderTextures) do
            tex:SetAlpha(alpha)
        end
    end
    if button.iconBorderTextures then
        for _, tex in ipairs(button.iconBorderTextures) do
            tex:SetAlpha(alpha)
        end
    end
    if button.statusBar then button.statusBar:SetAlpha(alpha) end
    if button.barTextFrame then button.barTextFrame:SetAlpha(alpha) end
    button.cooldown:SetAlpha(alpha)
    if button.locCooldown then button.locCooldown:SetAlpha(alpha) end
    if button.iconGCDCooldown then button.iconGCDCooldown:SetAlpha(alpha) end
    if button.overlayFrame then button.overlayFrame:SetAlpha(alpha) end
end

-- True-widget stack rendering (tracker C2): a standalone aura entry in
-- stack mode replaces the bar background slab with per-stack capacity
-- blocks, so the gaps between stacks are genuinely empty; the aura kit
-- overlays an identical set (same proportions as the bundled fill atlas)
-- while the aura runs. Shell entries render nothing CC-side (the kit is
-- the whole visible bar). Re-evaluation is OOC-only: the max lookup can
-- return a secret in restricted contexts, and the aura layer defers its
-- own restyle through combat anyway.
local function UpdateBarStackBlocks(button, style)
    if InCombatLockdown() then return end
    local buttonData = button.buttonData
    local max
    if buttonData and buttonData.addedAs == "aura"
        and not IsAuraShellEntry(buttonData)
        and CooldownCompanion.IsBarPanelAuraStackDisplay
        and CooldownCompanion:IsBarPanelAuraStackDisplay(buttonData) then
        max = CooldownCompanion:GetAuraStackBarMax(buttonData)
        if max and max > ST.STACK_SEGMENT_ATLAS_MAX then max = nil end
    end
    if max then
        local blocks = button._stackBgBlocks
        if not blocks then
            blocks = {}
            button._stackBgBlocks = blocks
        end
        for i = #blocks + 1, max do
            local tex = button:CreateTexture(nil, "BACKGROUND")
            tex:SetAlpha(0)
            blocks[i] = tex
        end
        ST.LayoutStackBlocks(blocks, button.statusBar or button, max,
            button._isVertical, style.barBgColor or { 0.1, 0.1, 0.1, 0.8 })
        button.bg:SetAlpha(0)
        button._stackBlocksActive = true
    elseif button._stackBlocksActive then
        button._stackBlocksActive = nil
        ST.HideStackBlocks(button._stackBgBlocks)
        -- Restore shell-aware: ApplyBarAuraShellVisuals runs before this and
        -- owns the shell alpha; a plain 1 here would resurrect a shell's bg.
        button.bg:SetAlpha(IsAuraShellEntry(buttonData) and 0 or 1)
    end
end

function CooldownCompanion:CreateBarFrame(parent, index, buttonData, style)
    local barLength = style.barLength or 180
    local barHeight = style.barHeight or 20
    local borderSize = style.borderSize or ST.DEFAULT_BORDER_SIZE
    local borderRenderMode = ST.GetBorderRenderMode(style)
    local showIcon = style.showBarIcon ~= false
    local isVertical = style.barFillVertical or false
    local iconReverse = showIcon and (style.barIconReverse or false)

    local iconSize = (style.barIconSizeOverride and style.barIconSize) or barHeight
    local iconOffset = showIcon and (style.barIconOffset or 0) or 0
    local barAreaLeft = showIcon and (iconSize + iconOffset) or 0
    local barAreaTop = showIcon and (iconSize + iconOffset) or 0

    -- Main bar frame
    local button = CreateFrame("Frame", parent:GetName() .. "Bar" .. index, parent)
    if isVertical then
        button:SetSize(barHeight, barLength)
    else
        button:SetSize(barLength, barHeight)
    end
    button._isBar = true
    button._isVertical = isVertical

    -- F6: flatten this bar's render layers into one render pass
    -- (owner-validated V1-V10: no visual difference).
    button:SetFlattensRenderLayers(true)

    -- Background — covers bar area only when icon is shown (icon has its own iconBg)
    local bgColor = style.barBgColor or {0.1, 0.1, 0.1, 0.8}
    button.bg = button:CreateTexture(nil, "BACKGROUND")
    if showIcon then
        SetBarAreaPoints(button.bg, button, isVertical, iconReverse, barAreaLeft, barAreaTop, 0)
    else
        button.bg:SetAllPoints()
    end
    button.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])

    -- Icon
    button.icon = button:CreateTexture(nil, "ARTWORK")
    if showIcon then
        SetIconAreaPoints(button.icon, button, isVertical, iconReverse, iconSize, ST.GetEffectiveBorderLayoutSize(button, borderSize, borderRenderMode))
        button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        -- Hidden 1x1 icon (still needed for UpdateButtonIcon)
        button.icon:SetPoint("TOPLEFT", 0, 0)
        button.icon:SetSize(1, 1)
        button.icon:SetAlpha(0)
    end

    -- Icon background + border (always shown when icon visible)
    button.iconBg = button:CreateTexture(nil, "BACKGROUND")
    SetIconAreaPoints(button.iconBg, button, isVertical, iconReverse, iconSize, 0)
    button.iconBg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
    if not showIcon then button.iconBg:Hide() end

    button._iconBounds = CreateFrame("Frame", nil, button)
    button._iconBounds:EnableMouse(false)
    SetIconAreaPoints(button._iconBounds, button, isVertical, iconReverse, iconSize, 0)

    button.iconBorderTextures = {}
    local borderColor = style.borderColor or {0, 0, 0, 1}
    for i = 1, 4 do
        local tex = button:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(unpack(borderColor))
        if not showIcon then tex:Hide() end
        button.iconBorderTextures[i] = tex
    end
    ApplyBorderEdgePositions(button.iconBorderTextures, button._iconBounds, borderSize, borderRenderMode)

    -- Bar area bounds (for border positioning separate from icon)
    button._barBounds = CreateFrame("Frame", nil, button)
    button._barBounds:EnableMouse(false)
    if showIcon then
        SetBarAreaPoints(button._barBounds, button, isVertical, iconReverse, barAreaLeft, barAreaTop, 0)
    else
        button._barBounds:SetAllPoints()
    end

    -- StatusBar
    button.statusBar = CreateFrame("StatusBar", nil, button)
    SetBarAreaPoints(button.statusBar, button, isVertical, iconReverse, barAreaLeft, barAreaTop, ST.GetEffectiveBorderLayoutSize(button, borderSize, borderRenderMode))
    if isVertical then
        button.statusBar:SetOrientation("VERTICAL")
    end
    SetStatusBarImmediateRange(button.statusBar, 0, 1)
    SetStatusBarImmediateValue(button.statusBar, 1)
    button.statusBar:SetReverseFill(style.barReverseFill or false)
    button.statusBar:SetStatusBarTexture(CooldownCompanion:FetchEffectiveBarTexture(style.barTexture or "Solid"))
    local barColor = style.barColor or DEFAULT_BAR_COLOR
    button.statusBar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], barColor[4])
    button.statusBar:EnableMouse(false)

    -- Dedicated text layer above custom segment holders.
    button.barTextFrame = CreateFrame("Frame", nil, button)
    SetBarAreaPoints(button.barTextFrame, button, isVertical, iconReverse, barAreaLeft, barAreaTop, ST.GetEffectiveBorderLayoutSize(button, borderSize, borderRenderMode))
    button.barTextFrame:SetFrameLevel(button.statusBar:GetFrameLevel() + 20)
    button.barTextFrame:EnableMouse(false)

    -- Name text
    button.nameText = button.barTextFrame:CreateFontString(nil, "OVERLAY")
    ApplyFontStyle(button.nameText, style, "barName", 10)
    local nameOffX = style.barNameTextOffsetX or 0
    local nameOffY = style.barNameTextOffsetY or 0
    local nameReverse = style.barNameTextReverse
    if isVertical then
        if nameReverse then
            button.nameText:SetPoint("TOP", nameOffX, -3 + nameOffY)
        else
            button.nameText:SetPoint("BOTTOM", nameOffX, 3 + nameOffY)
        end
        button.nameText:SetJustifyH("CENTER")
    else
        if nameReverse then
            button.nameText:SetPoint("RIGHT", -3 + nameOffX, nameOffY)
            button.nameText:SetJustifyH("RIGHT")
        else
            button.nameText:SetPoint("LEFT", 3 + nameOffX, nameOffY)
            button.nameText:SetJustifyH("LEFT")
        end
    end
    if style.showBarNameText ~= false or buttonData.customName then
        button.nameText:SetText(buttonData.customName or buttonData.name or "")
    else
        button.nameText:Hide()
    end

    -- Time text
    button.timeText = button.barTextFrame:CreateFontString(nil, "OVERLAY")
    ApplyFontStyle(button.timeText, style, "cooldown")
    local cdOffX = style.barCdTextOffsetX or 0
    local cdOffY = style.barCdTextOffsetY or 0
    local timeReverse = style.barTimeTextReverse
    if isVertical then
        if timeReverse then
            button.timeText:SetPoint("BOTTOM", cdOffX, 3 + cdOffY)
        else
            button.timeText:SetPoint("TOP", cdOffX, -3 + cdOffY)
        end
        button.timeText:SetJustifyH("CENTER")
    else
        if timeReverse then
            button.timeText:SetPoint("LEFT", 3 + cdOffX, cdOffY)
            button.timeText:SetJustifyH("LEFT")
        else
            button.timeText:SetPoint("RIGHT", -3 + cdOffX, cdOffY)
            button.timeText:SetJustifyH("RIGHT")
        end
    end

    -- Truncate name text so it doesn't overlap time text (horizontal only, opposite sides)
    if not isVertical and nameReverse == timeReverse then
        if nameReverse then
            button.nameText:SetPoint("LEFT", button.timeText, "RIGHT", 4, 0)
        else
            button.nameText:SetPoint("RIGHT", button.timeText, "LEFT", -4, 0)
        end
    end

    -- Border textures (around bar area, not full button)
    button.borderTextures = {}
    for i = 1, 4 do
        local tex = button:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(unpack(borderColor))
        button.borderTextures[i] = tex
    end
    ApplyBorderEdgePositions(button.borderTextures, button._barBounds, borderSize, borderRenderMode)

    -- Loss of control cooldown frame (red swipe over the bar icon)
    button.locCooldown = CreateFrame("Cooldown", button:GetName() .. "LocCooldown", button, "CooldownFrameTemplate")
    button.locCooldown:SetAllPoints(button.icon)
    button.locCooldown:SetDrawEdge(true)
    button.locCooldown:SetDrawSwipe(true)
    button.locCooldown:SetSwipeColor(0.17, 0, 0, 0.8)
    button.locCooldown:SetHideCountdownNumbers(true)
    SetFrameClickThroughRecursive(button.locCooldown, true, true)

    -- Icon-only GCD swipe frame for bar mode.
    button.iconGCDCooldown = CreateFrame("Cooldown", button:GetName() .. "IconGCDCooldown", button, "CooldownFrameTemplate")
    button.iconGCDCooldown:SetAllPoints(button.icon)
    button.iconGCDCooldown:SetDrawEdge(style.showCooldownSwipeEdge ~= false)
    button.iconGCDCooldown:SetDrawSwipe(true)
    button.iconGCDCooldown:SetReverse(style.cooldownSwipeReverse or false)
    button.iconGCDCooldown:SetHideCountdownNumbers(true)
    button.iconGCDCooldown:Hide()
    SetFrameClickThroughRecursive(button.iconGCDCooldown, true, true)

    -- Hidden cooldown frame for GetCooldownTimes() reads
    button.cooldown = CreateFrame("Cooldown", button:GetName() .. "Cooldown", button, "CooldownFrameTemplate")
    button.cooldown:SetSize(1, 1)
    button.cooldown:SetPoint("CENTER")
    button.cooldown:SetDrawSwipe(false)
    button.cooldown:SetHideCountdownNumbers(true)
    button.cooldown:Hide()
    SetFrameClickThroughRecursive(button.cooldown, true, true)
    button.cooldown:SetScript("OnCooldownDone", ST.OnButtonCooldownDone)

    -- Suppress bling (cooldown-end flash) on all bar buttons
    button.cooldown:SetDrawBling(false)
    button.locCooldown:SetDrawBling(false)
    button.iconGCDCooldown:SetDrawBling(false)

    -- Charge/item count text (overlay)
    button.overlayFrame = CreateFrame("Frame", nil, button)
    button.overlayFrame:SetAllPoints()
    button.overlayFrame:EnableMouse(false)
    button.count = button.overlayFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetText("")
    button.buttonData = buttonData

    -- Apply count text font/anchor settings
    ApplyBarCountTextStyle(button, style)

    -- Aura stack count preview stand-in: live stacks render on the slot kit
    -- (Blizzard-driven SetApplicationCount); this CC-side twin exists only
    -- for the aura stack text config preview.
    button.auraStackCount = (button.barTextFrame or button.overlayFrame):CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.auraStackCount:SetText("")
    ApplyFontStyle(button.auraStackCount, style, "auraStack")
    local asAnchor = style.auraStackAnchor or "BOTTOMLEFT"
    local asXOff = style.auraStackXOffset or 2
    local asYOff = style.auraStackYOffset or 2
    if showIcon then
        button.auraStackCount:SetPoint(asAnchor, button.icon, asAnchor, asXOff, asYOff)
    else
        button.auraStackCount:SetPoint(asAnchor, button, asAnchor, asXOff, asYOff)
    end

    -- Store button data
    button.index = index
    button.style = style

    -- Cache spell cooldown secrecy level (static per-spell: NeverSecret=0, ContextuallySecret=2)
    if buttonData.type == "spell" then
        buttonData._cooldownSecrecy = C_Secrets.GetSpellCooldownSecrecy(buttonData.id)
    end

    -- Bar text refresh / fallback fill OnUpdate. Native timers drive DurationObject fills.
    button._barFillElapsed = 0
    button._barTextUpdateInterval = BAR_TEXT_UPDATE_INTERVAL
    button:SetScript("OnUpdate", BarModeOnUpdate)

    if IsEntryItemLike(buttonData) then
        local effectiveItem = ResolveEffectiveItem(buttonData, true)
        button._resolvedItemId = effectiveItem and effectiveItem.itemID or buttonData.id
        button._resolvedItemAvailableQuantity = effectiveItem and effectiveItem.availableQuantity or 0
        button._resolvedItemQuantityKind = effectiveItem and effectiveItem.quantityKind or "stacks"
        button._equipmentSlotTrackable = CooldownCompanion.IsEquipmentSlotEntry(buttonData)
            and effectiveItem and effectiveItem.trackable == true or nil
    end

    -- Per-button visibility runtime state
    button._visibilityHidden = false
    button._prevVisibilityHidden = false
    button._visibilityAlphaOverride = nil
    button._lastVisAlpha = 1
    button._groupId = parent.groupId

    -- Set icon
    self:UpdateButtonIcon(button)

    -- Set name text from resolved spell/item name
    if style.showBarNameText ~= false or buttonData.customName then
        local displayName = buttonData.customName or buttonData.name
        if not buttonData.customName then
            if buttonData.type == "spell" then
                local spellName = C_Spell.GetSpellName(button._displaySpellId or buttonData.id)
                if spellName then displayName = spellName end
            elseif IsEntryItemLike(buttonData) then
                local itemID = button._resolvedItemId or buttonData.id
                local itemName = itemID and C_Item.GetItemNameByID(itemID)
                if itemName then displayName = itemName end
            end
        end
        button.nameText:SetText(displayName or "")
    end

    -- Methods
    button.UpdateCooldown = function(self)
        CooldownCompanion:UpdateButtonCooldown(self)
    end

    button.UpdateStyle = function(self, newStyle)
        CooldownCompanion:UpdateBarStyle(self, newStyle)
    end

    -- Click-through
    local showTooltips = style.showTooltips == true and not IsCursorAnchoredButton(button)
    local iconTooltips = showTooltips and showIcon

    -- Disable hover on the full bar; tooltip hover is icon-only via _iconBounds.
    SetFrameClickThroughRecursive(button, true, true)
    -- Prevent child frames from stealing hover.
    if button.statusBar then
        SetFrameClickThroughRecursive(button.statusBar, true, true)
    end
    if button.barTextFrame then
        SetFrameClickThroughRecursive(button.barTextFrame, true, true)
    end
    if button._barBounds then
        SetFrameClickThroughRecursive(button._barBounds, true, true)
    end
    SetFrameClickThroughRecursive(button.cooldown, true, true)
    if button.iconGCDCooldown then
        SetFrameClickThroughRecursive(button.iconGCDCooldown, true, true)
    end
    if button.locCooldown then
        SetFrameClickThroughRecursive(button.locCooldown, true, true)
    end
    if button.overlayFrame then
        SetFrameClickThroughRecursive(button.overlayFrame, true, true)
    end

    if button._iconBounds then
        SetFrameClickThroughRecursive(button._iconBounds, true, not iconTooltips)
    end
    SetBarIconTooltipScripts(button, iconTooltips)
    button:SetScript("OnEnter", nil)
    button:SetScript("OnLeave", nil)

    ApplyBarAuraShellVisuals(button, buttonData)
    UpdateBarStackBlocks(button, style)

    return button
end

function CooldownCompanion:UpdateBarStyle(button, newStyle)
    local barLength = newStyle.barLength or 180
    local barHeight = newStyle.barHeight or 20
    local borderSize = newStyle.borderSize or ST.DEFAULT_BORDER_SIZE
    local borderRenderMode = ST.GetBorderRenderMode(newStyle)
    local borderLayoutSize = ST.GetEffectiveBorderLayoutSize(button, borderSize, borderRenderMode)
    local showIcon = newStyle.showBarIcon ~= false
    local isVertical = newStyle.barFillVertical or false
    local iconReverse = showIcon and (newStyle.barIconReverse or false)
    local iconSize = (newStyle.barIconSizeOverride and newStyle.barIconSize) or barHeight
    local iconOffset = showIcon and (newStyle.barIconOffset or 0) or 0
    local barAreaLeft = showIcon and (iconSize + iconOffset) or 0
    local barAreaTop = showIcon and (iconSize + iconOffset) or 0

    button.style = newStyle
    if ClearButtonVisualState then
        ClearButtonVisualState(button)
    end
    button._isVertical = isVertical

    -- Update bar text/fallback fill OnUpdate interval
    button._barFillElapsed = 0
    button._barTextUpdateInterval = BAR_TEXT_UPDATE_INTERVAL
    button:SetScript("OnUpdate", BarModeOnUpdate)

    -- Invalidate cached state
    button._desaturated = nil
    button._iconTintIntent = nil
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
    button._nilConfirmPending = nil
    button._displaySpellId = nil
    button._liveOverrideSpellId = nil
    button._itemCount = nil
    EntryRuntime.ClearAuraPandemicRuntimeState(button)
    if button.auraStackCount then button.auraStackCount:SetText("") end
    button._visibilityHidden = false
    button._prevVisibilityHidden = false
    button._visibilityAlphaOverride = nil
    button._lastVisAlpha = 1
    button._barCdColor = nil
    button._chargeRecharging = nil
    button._chargesSpent = nil
    button._barReadyTextColor = nil
    button.statusBar:SetAlpha(1.0)

    if isVertical then
        button:SetSize(barHeight, barLength)
    else
        button:SetSize(barLength, barHeight)
    end

    -- Update icon
    button.icon:ClearAllPoints()
    if showIcon then
        SetIconAreaPoints(button.icon, button, isVertical, iconReverse, iconSize, borderLayoutSize)
        button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button.icon:SetAlpha(1)
    else
        button.icon:SetPoint("TOPLEFT", 0, 0)
        button.icon:SetSize(1, 1)
        button.icon:SetAlpha(0)
    end
    if button.iconGCDCooldown then
        button.iconGCDCooldown:SetAllPoints(button.icon)
        button.iconGCDCooldown:SetDrawEdge(newStyle.showCooldownSwipeEdge ~= false)
        button.iconGCDCooldown:SetReverse(newStyle.cooldownSwipeReverse or false)
        if not showIcon or newStyle.showGCDSwipe ~= true then
            button.iconGCDCooldown:Hide()
        end
    end

    button.bg:ClearAllPoints()
    if showIcon then
        SetBarAreaPoints(button.bg, button, isVertical, iconReverse, barAreaLeft, barAreaTop, 0)
    else
        button.bg:SetAllPoints()
    end
    button.bg:Show()

    -- Icon bg + border: always shown when icon visible
    if button.iconBg then
        SetIconAreaPoints(button.iconBg, button, isVertical, iconReverse, iconSize, 0)
        if showIcon then button.iconBg:Show() else button.iconBg:Hide() end
    end
    if button._iconBounds then
        SetIconAreaPoints(button._iconBounds, button, isVertical, iconReverse, iconSize, 0)
    end
    if button.iconBorderTextures then
        ApplyBorderEdgePositions(button.iconBorderTextures, button._iconBounds, borderSize, borderRenderMode)
        for _, tex in ipairs(button.iconBorderTextures) do
            if showIcon then tex:Show() else tex:Hide() end
        end
    end

    -- Bar area bounds
    if button._barBounds then
        button._barBounds:ClearAllPoints()
        if showIcon then
            SetBarAreaPoints(button._barBounds, button, isVertical, iconReverse, barAreaLeft, barAreaTop, 0)
        else
            button._barBounds:SetAllPoints()
        end
    end

    -- Update status bar
    SetBarAreaPoints(button.statusBar, button, isVertical, iconReverse, barAreaLeft, barAreaTop, borderLayoutSize)
    if isVertical then
        button.statusBar:SetOrientation("VERTICAL")
    else
        button.statusBar:SetOrientation("HORIZONTAL")
    end
    button.statusBar:SetReverseFill(newStyle.barReverseFill or false)
    button.statusBar:SetStatusBarTexture(CooldownCompanion:FetchEffectiveBarTexture(newStyle.barTexture or "Solid"))
    local barColor = newStyle.barColor or {0.2, 0.6, 1.0, 1.0}
    button.statusBar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], barColor[4])

    if button.barTextFrame then
        button.barTextFrame:ClearAllPoints()
        SetBarAreaPoints(button.barTextFrame, button, isVertical, iconReverse, barAreaLeft, barAreaTop, borderLayoutSize)
        button.barTextFrame:SetFrameLevel(button.statusBar:GetFrameLevel() + 20)
    end

    -- Update background
    local bgColor = newStyle.barBgColor or {0.1, 0.1, 0.1, 0.8}
    button.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
    if button.iconBg then
        button.iconBg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
    end

    -- Update border
    local borderColor = newStyle.borderColor or {0, 0, 0, 1}
    if button.borderTextures then
        ApplyBorderEdgePositions(button.borderTextures, button._barBounds or button, borderSize, borderRenderMode)
        for _, tex in ipairs(button.borderTextures) do
            tex:SetColorTexture(unpack(borderColor))
            tex:Show()
        end
    end
    if button.iconBorderTextures then
        for _, tex in ipairs(button.iconBorderTextures) do
            tex:SetColorTexture(unpack(borderColor))
        end
    end

    -- Update name text font and position
    local hasCustomName = button.buttonData and button.buttonData.customName
    if newStyle.showBarNameText ~= false or hasCustomName then
        ApplyFontStyle(button.nameText, newStyle, "barName", 10)
        button.nameText:Show()
    else
        button.nameText:Hide()
    end

    -- Update time text font (default state; per-tick logic handles aura mode)
    ApplyFontStyle(button.timeText, newStyle, "cooldown")
    -- Clear cached text mode so per-tick logic re-applies the correct font and color
    button._barTextMode = nil
    button._barTextColorDirty = true

    -- Re-anchor name and time text for orientation
    local nameOffX = newStyle.barNameTextOffsetX or 0
    local nameOffY = newStyle.barNameTextOffsetY or 0
    local cdOffX = newStyle.barCdTextOffsetX or 0
    local cdOffY = newStyle.barCdTextOffsetY or 0
    local nameReverse = newStyle.barNameTextReverse
    local timeReverse = newStyle.barTimeTextReverse
    button.nameText:ClearAllPoints()
    button.timeText:ClearAllPoints()
    if isVertical then
        if nameReverse then
            button.nameText:SetPoint("TOP", nameOffX, -3 + nameOffY)
        else
            button.nameText:SetPoint("BOTTOM", nameOffX, 3 + nameOffY)
        end
        button.nameText:SetJustifyH("CENTER")
        if timeReverse then
            button.timeText:SetPoint("BOTTOM", cdOffX, 3 + cdOffY)
        else
            button.timeText:SetPoint("TOP", cdOffX, -3 + cdOffY)
        end
        button.timeText:SetJustifyH("CENTER")
    else
        if nameReverse then
            button.nameText:SetPoint("RIGHT", -3 + nameOffX, nameOffY)
            button.nameText:SetJustifyH("RIGHT")
        else
            button.nameText:SetPoint("LEFT", 3 + nameOffX, nameOffY)
            button.nameText:SetJustifyH("LEFT")
        end
        if timeReverse then
            button.timeText:SetPoint("LEFT", 3 + cdOffX, cdOffY)
            button.timeText:SetJustifyH("LEFT")
        else
            button.timeText:SetPoint("RIGHT", -3 + cdOffX, cdOffY)
            button.timeText:SetJustifyH("RIGHT")
        end
        -- Truncate name text so it doesn't overlap time text (opposite sides only)
        if nameReverse == timeReverse then
            if nameReverse then
                button.nameText:SetPoint("LEFT", button.timeText, "RIGHT", 4, 0)
            else
                button.nameText:SetPoint("RIGHT", button.timeText, "LEFT", -4, 0)
            end
        end
    end

    -- Update charge/item count font and anchor to icon or bar center
    ApplyBarCountTextStyle(button, newStyle)

    -- Update aura stack count font/anchor settings
    if button.auraStackCount then
        button.auraStackCount:ClearAllPoints()
        ApplyFontStyle(button.auraStackCount, newStyle, "auraStack")
        local asAnchor = newStyle.auraStackAnchor or "BOTTOMLEFT"
        local asXOff = newStyle.auraStackXOffset or 2
        local asYOff = newStyle.auraStackYOffset or 2
        if showIcon then
            button.auraStackCount:SetPoint(asAnchor, button.icon, asAnchor, asXOff, asYOff)
        else
            button.auraStackCount:SetPoint(asAnchor, button, asAnchor, asXOff, asYOff)
        end
    end

    -- Update spell name text
    self:UpdateButtonIcon(button)
    if newStyle.showBarNameText ~= false or (button.buttonData and button.buttonData.customName) then
        local displayName = button.buttonData.customName or button.buttonData.name
        if not button.buttonData.customName then
            if button.buttonData.type == "spell" then
                local spellName = C_Spell.GetSpellName(button._displaySpellId or button.buttonData.id)
                if spellName then displayName = spellName end
            elseif IsEntryItemLike(button.buttonData) then
                local itemID = button._resolvedItemId or button.buttonData.id
                local itemName = itemID and C_Item.GetItemNameByID(itemID)
                if itemName then displayName = itemName end
            end
        end
        button.nameText:SetText(displayName or "")
    end

    -- Update click-through
    local showTooltips = newStyle.showTooltips == true and not IsCursorAnchoredButton(button)
    local iconTooltips = showTooltips and showIcon

    -- Disable hover on the full bar; tooltip hover is icon-only via _iconBounds.
    SetFrameClickThroughRecursive(button, true, true)
    -- Prevent child frames from stealing hover.
    if button.statusBar then
        SetFrameClickThroughRecursive(button.statusBar, true, true)
    end
    if button.barTextFrame then
        SetFrameClickThroughRecursive(button.barTextFrame, true, true)
    end
    if button._barBounds then
        SetFrameClickThroughRecursive(button._barBounds, true, true)
    end
    SetFrameClickThroughRecursive(button.cooldown, true, true)
    if button.iconGCDCooldown then
        SetFrameClickThroughRecursive(button.iconGCDCooldown, true, true)
    end
    if button.locCooldown then
        SetFrameClickThroughRecursive(button.locCooldown, true, true)
    end
    if button.overlayFrame then
        SetFrameClickThroughRecursive(button.overlayFrame, true, true)
    end

    if button._iconBounds then
        SetFrameClickThroughRecursive(button._iconBounds, true, not iconTooltips)
    end
    SetBarIconTooltipScripts(button, iconTooltips)
    button:SetScript("OnEnter", nil)
    button:SetScript("OnLeave", nil)

    ApplyBarAuraShellVisuals(button, button.buttonData)
    UpdateBarStackBlocks(button, newStyle)

    CooldownCompanion:UpdateAuraTextureVisual(button)
end

-- Exports
ST._UpdateBarDisplay = UpdateBarDisplay
ST._ApplyBarCountTextStyle = ApplyBarCountTextStyle
ST._ApplyBarAuraShellVisuals = ApplyBarAuraShellVisuals
ST._UpdateBarStackBlocks = UpdateBarStackBlocks
