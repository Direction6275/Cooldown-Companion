--[[
    CooldownCompanion - ButtonFrame/BarMode
    Bar-mode button creation, styling, fill animation, and display updates
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

-- Localize frequently-used globals
local GetTime = GetTime
local pairs = pairs
local ipairs = ipairs
local unpack = unpack
local math_floor = math.floor
local math_sin = math.sin
local math_pi = math.pi
local string_format = string.format
local InCombatLockdown = InCombatLockdown

-- Imports from Helpers
local SetIconAreaPoints = ST._SetIconAreaPoints
local SetBarAreaPoints = ST._SetBarAreaPoints
local AnchorBarCountText = ST._AnchorBarCountText
local ApplyEdgePositions = ST._ApplyEdgePositions
local ApplyIconTexCoord = ST._ApplyIconTexCoord
local UsesChargeBehavior = CooldownCompanion.UsesChargeBehavior
local UsesChargeTextLane = CooldownCompanion.UsesChargeTextLane
local DEFAULT_BAR_AURA_COLOR = ST._DEFAULT_BAR_AURA_COLOR
local DEFAULT_BAR_PANDEMIC_COLOR = ST._DEFAULT_BAR_PANDEMIC_COLOR
local DEFAULT_BAR_CHARGE_COLOR = ST._DEFAULT_BAR_CHARGE_COLOR

-- Pre-defined color constant tables to avoid per-tick allocation.
-- IMPORTANT: These tables are read-only — never write to their indices.
local DEFAULT_WHITE = {1, 1, 1, 1}
local DEFAULT_AURA_TEXT_COLOR = {0, 0.925, 1, 1}
local DEFAULT_BAR_COLOR = {0.2, 0.6, 1.0, 1.0}
local DEFAULT_READY_TEXT_COLOR = {0.2, 1.0, 0.2, 1.0}

-- Imports from Glows
local CreateGlowContainer = ST._CreateGlowContainer
local SetBarAuraEffect = ST._SetBarAuraEffect

-- Imports from Visibility
local UpdateLossOfControl = ST._UpdateLossOfControl

-- Imports from Tracking
local UpdateIconTint = ST._UpdateIconTint
local EvaluateDesaturation = ST._EvaluateDesaturation

-- Shared click-through helpers from Utils.lua
local SetFrameClickThroughRecursive = ST.SetFrameClickThroughRecursive

-- Shared helpers from ButtonFrame/Helpers.lua
local IsItemEquippable = CooldownCompanion.IsItemEquippable
local FormatTime = CooldownCompanion.FormatTime
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
            if bd.type == "spell" then
                GameTooltip:SetSpellByID(button._displaySpellId or bd.id)
            elseif bd.type == "item" then
                GameTooltip:SetItemByID(bd.id)
            end
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

-- Lightweight OnUpdate: interpolates bar fill + time text between ticker updates.
local function UpdateBarFill(button)
    -- Single-bar path
    -- DurationObject percent methods return secret values during combat in 12.0.1,
    -- but SetValue() accepts secrets (C-side widget method).  HasSecretValues gates
    -- expiry detection and time text formatting.
    -- Items use stored C_Item.GetItemCooldown values (_itemCdStart/_itemCdDuration).
    local onCooldown = false
    local itemRemaining = 0

    if button._durationObj and not button._barGCDSuppressed then
        onCooldown = true
        -- SetValue accepts secret values; fraction animates natively in the engine
        if button._auraActive then
            button.statusBar:SetValue(button._durationObj:GetRemainingPercent())   -- drain: 1→0
        else
            button.statusBar:SetValue(button._durationObj:GetElapsedPercent())     -- fill: 0→1
        end
    elseif button._viewerBar and button._auraActive and not button._barGCDSuppressed then
        -- Totem/guardian: mirror viewer's BuffBar StatusBar (secret pass-through).
        -- Blizzard fills viewerFrame.Bar with SetMinMaxValues(0, duration) and
        -- SetValue(remaining) each frame.  Both GetValue and GetMinMaxValues
        -- return secret values when set with secrets — no arithmetic needed.
        local viewerBar = button._viewerBar
        if viewerBar:IsVisible() then
            onCooldown = true
            local _, maxVal = viewerBar:GetMinMaxValues()
            button.statusBar:SetMinMaxValues(0, maxVal)
            button.statusBar:SetValue(viewerBar:GetValue())
        end
    elseif button._cooldownDeferred then
        -- Deferred cooldown (timer hasn't started): show as "on cooldown"
        -- with a static full bar (no animation, no time text).
        onCooldown = true
        button.statusBar:SetValue(0)
    elseif button.buttonData.type == "item" then
        -- Items: use stored C_Item.GetItemCooldown values (avoids hidden-widget staleness)
        local startMs = (button._itemCdStart or 0) * 1000
        local durationMs = (button._itemCdDuration or 0) * 1000
        local now = GetTime() * 1000
        onCooldown = durationMs > 0
        if onCooldown and button._barGCDSuppressed then onCooldown = false end
        if onCooldown then
            local elapsed = now - startMs
            itemRemaining = (durationMs - elapsed) / 1000
            if button._auraActive then
                local frac = 1 - (elapsed / durationMs)
                if frac < 0 then frac = 0 end
                button.statusBar:SetValue(frac)
            else
                local frac = elapsed / durationMs
                if frac > 1 then frac = 1 end
                button.statusBar:SetValue(frac)
            end
        end
    end

    if onCooldown then
        local showTimeText = button._auraActive
            and (button.style.showAuraText ~= false)
            or (not button._auraActive and button.style.showCooldownText)
        if showTimeText then
            -- Switch font/color when mode changes
            local mode = button._auraActive and "aura" or "cd"
            if button._barTextMode ~= mode then
                button._barTextMode = mode
                button._barTextColorDirty = true
                if button._auraActive then
                    local f = CooldownCompanion:FetchFont(button.style.auraTextFont or "Friz Quadrata TT")
                    local s = button.style.auraTextFontSize or 12
                    local o = button.style.auraTextFontOutline or "OUTLINE"
                    button.timeText:SetFont(f, s, o)
                else
                    local f = CooldownCompanion:FetchFont(button.style.cooldownFont or "Friz Quadrata TT")
                    local s = button.style.cooldownFontSize or 12
                    local o = button.style.cooldownFontOutline or "OUTLINE"
                    button.timeText:SetFont(f, s, o)
                end
            end
            if button._barTextColorDirty then
                button._barTextColorDirty = nil
                local cc = button._auraActive
                    and (button.style.auraTextFontColor or DEFAULT_AURA_TEXT_COLOR)
                    or (button.style.cooldownFontColor or DEFAULT_WHITE)
                button.timeText:SetTextColor(cc[1], cc[2], cc[3], cc[4])
            end
            -- Time text: HasSecretValues() returns a non-secret boolean.
            -- Non-secret: full FormatTime formatting ("1:30:00", "1:30", "45", etc.)
            -- Secret: pass secret number to C++ SetFormattedText ("%.1f" / "%.0f" format)
            local decimal = button.style.decimalTimers
            if button._durationObj then
                local remaining = button._durationObj:GetRemainingDuration()
                if not button._durationObj:HasSecretValues() then
                    if remaining > 0 then
                        button.timeText:SetText(FormatTime(remaining, decimal))
                    else
                        button.timeText:SetText("")
                    end
                else
                    button.timeText:SetFormattedText(decimal and "%.1f" or "%.0f", remaining)
                end
            elseif button._viewerBar then
                -- Totem: viewer bar values may be secret (set by Blizzard's internal totem tracking).
                -- HasSecretValues() on the viewer StatusBar is unreliable (Blizzard's
                -- secure code sets it, so the widget reports plain — but the actual
                -- number returned by GetValue() is a secret wrapper).
                -- Always use SetFormattedText for secret-safe pass-through.
                button.timeText:SetFormattedText(decimal and "%.1f" or "%.0f", button._viewerBar:GetValue())
            else
                if itemRemaining > 0 then
                    button.timeText:SetText(FormatTime(itemRemaining, decimal))
                else
                    button.timeText:SetText("")
                end
            end
        end
    else
        -- Restore 0-1 range if exiting viewer bar pass-through
        if button._viewerBar then
            button.statusBar:SetMinMaxValues(0, 1)
            button._viewerBar = nil
        end
        if button._barAuraActivePreview then
            button.statusBar:SetValue(1)
            button.timeText:SetText("")
        elseif button.buttonData.isPassive then
            button.statusBar:SetValue(0)
            button.timeText:SetText("")
        else
        button.statusBar:SetValue(1)
        if button.style.showBarReadyText then
            if button._barTextMode ~= "ready" then
                button._barTextMode = "ready"
                local f = CooldownCompanion:FetchFont(button.style.barReadyFont or "Friz Quadrata TT")
                local s = button.style.barReadyFontSize or 12
                local o = button.style.barReadyFontOutline or "OUTLINE"
                button.timeText:SetFont(f, s, o)
            end
            button.timeText:SetText(button.style.barReadyText or "Ready")
        else
            button.timeText:SetText("")
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

    if buttonData and UsesChargeTextLane(buttonData) then
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
    button._countTextLaneStyled = buttonData and UsesChargeTextLane(buttonData) or false
end

-- Update bar-specific display elements (colors, desaturation, aura effects).
-- Bar fill + time text are handled by the per-button OnUpdate for smooth interpolation.
local function UpdateBarDisplay(button)
    local style = button.style

    -- Determine onCooldown via nil-checks (secret-safe).
    -- _durationObj is non-nil only when UpdateButtonCooldown found an active CD/aura.
    -- _viewerBar is non-nil when a totem/guardian viewer bar is active.
    local onCooldown
    if button._cooldownDeferred then
        onCooldown = true
    elseif button._durationObj then
        onCooldown = not button._barGCDSuppressed
    elseif button._viewerBar and button._auraActive then
        onCooldown = not button._barGCDSuppressed
    elseif button.buttonData.type == "item" then
        onCooldown = button._itemCdDuration and button._itemCdDuration > 0
        if onCooldown and button._barGCDSuppressed then
            onCooldown = false
        end
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
    if onCooldown and not button.buttonData.isPassive then
        if UsesChargeBehavior(button.buttonData) and not button._zeroChargesConfirmed then
            wantCdColor = style.barChargeColor or DEFAULT_BAR_CHARGE_COLOR
        else
            wantCdColor = style.barCooldownColor
        end
    end
    if button._barCdColor ~= wantCdColor then
        button._barCdColor = wantCdColor
        local c = wantCdColor or style.barColor or DEFAULT_BAR_COLOR
        button.statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4])
    end

    EvaluateDesaturation(button, button.buttonData, style)

    -- Icon tinting (out-of-range red / unusable dimming)
    UpdateIconTint(button, button.buttonData, style)

    -- Loss of control overlay on bar icon
    UpdateLossOfControl(button)

    -- Bar aura visuals in bar mode are driven by barAuraEffect, not icon-mode aura flags.
    local barAuraVisualsEnabled = style.barAuraEffect ~= "none"
    local inCombat = InCombatLockdown()

    -- Bar aura color: override bar fill when aura is active (pandemic overrides aura color)
    local wantAuraColor
    if button._pandemicPreview then
        wantAuraColor = (button.style and button.style.barPandemicColor) or DEFAULT_BAR_PANDEMIC_COLOR
    elseif button._barAuraActivePreview then
        wantAuraColor = (button.style and button.style.barAuraColor) or DEFAULT_BAR_AURA_COLOR
    elseif button._auraActive then
        if button._inPandemic and style.showPandemicGlow ~= false
           and (not style.pandemicGlowCombatOnly or inCombat) then
            wantAuraColor = (button.style and button.style.barPandemicColor) or DEFAULT_BAR_PANDEMIC_COLOR
        elseif barAuraVisualsEnabled
               and (not style.auraGlowCombatOnly or inCombat) then
            wantAuraColor = (button.style and button.style.barAuraColor) or DEFAULT_BAR_AURA_COLOR
        end
    end
    if button._barAuraColor ~= wantAuraColor then
        button._barAuraColor = wantAuraColor
        if not wantAuraColor then
            -- Reset to normal color immediately (don't wait for next tick)
            button._barCdColor = nil
            local resetColor
            if onCooldown then
                if UsesChargeBehavior(button.buttonData) and not button._zeroChargesConfirmed then
                    resetColor = style.barChargeColor or DEFAULT_BAR_CHARGE_COLOR
                else
                    resetColor = style.barCooldownColor
                end
            end
            local c = resetColor or style.barColor or DEFAULT_BAR_COLOR
            button.statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4])
        end
    end
    if wantAuraColor and not button._barColorShiftActive then
        button.statusBar:SetStatusBarColor(wantAuraColor[1], wantAuraColor[2], wantAuraColor[3], wantAuraColor[4])
    end

    -- Bar aura effect (pandemic overrides effect color)
    local barAuraEffectPandemic = button._pandemicPreview
        or (button._auraActive and button._inPandemic and style.showPandemicGlow ~= false
            and (not style.pandemicGlowCombatOnly or inCombat))
    local barAuraEffectShow = button._barAuraEffectPreview or button._barAuraActivePreview
        or button._pandemicPreview
        or (button._auraActive and (barAuraEffectPandemic
            or (barAuraVisualsEnabled and (not style.auraGlowCombatOnly or inCombat))))
    SetBarAuraEffect(button, barAuraEffectShow, barAuraEffectPandemic or false)

    -- Bar indicator effects: alpha pulse, color shift
    -- Gated behind the same master toggles as existing bar aura effects:
    -- barAuraVisualsEnabled for aura-active, showPandemicGlow for pandemic (via barAuraEffectPandemic).
    local auraActiveForPulse = button._barAuraActivePreview
        or (barAuraVisualsEnabled and button._auraActive
            and (not style.auraGlowCombatOnly or inCombat))

    -- Alpha Pulse — cache state for per-frame animation in BarModeOnUpdate
    -- _pandemicPreview respects the enable flag so the pandemic preview only
    -- shows pulse if the user actually enabled it (matching bar aura effect behavior).
    local wantPulse
    if button._barPulsePreview then
        wantPulse = button._barPulsePreview
    elseif (barAuraEffectPandemic or button._pandemicPreview) and style.pandemicBarPulseEnabled then
        wantPulse = "pandemic"
    elseif auraActiveForPulse and style.barAuraPulseEnabled then
        wantPulse = "aura"
    end
    if wantPulse then
        button._barPulseActive = true
        button._barPulseSpeed = (wantPulse == "pandemic")
            and (style.pandemicBarPulseSpeed or 0.5)
            or (style.barAuraPulseSpeed or 0.5)
    elseif button._barPulseActive then
        button._barPulseActive = nil
        button.statusBar:SetAlpha(1.0)
    end

    -- Color Shift — cache state for per-frame animation in BarModeOnUpdate
    local wantColorShift
    if button._barColorShiftPreview then
        wantColorShift = button._barColorShiftPreview
    elseif (barAuraEffectPandemic or button._pandemicPreview) and style.pandemicBarColorShiftEnabled then
        wantColorShift = "pandemic"
    elseif auraActiveForPulse and style.barAuraColorShiftEnabled then
        wantColorShift = "aura"
    end
    if wantColorShift then
        button._barColorShiftActive = true
        button._barCSBaseColor = wantAuraColor or wantCdColor or style.barColor or DEFAULT_BAR_COLOR
        if wantColorShift == "pandemic" then
            button._barCSShiftColor = style.pandemicBarColorShiftColor or DEFAULT_WHITE
            button._barCSSpeed = style.pandemicBarColorShiftSpeed or 0.5
        else
            button._barCSShiftColor = style.barAuraColorShiftColor or DEFAULT_WHITE
            button._barCSSpeed = style.barAuraColorShiftSpeed or 0.5
        end
    elseif button._barColorShiftActive then
        button._barColorShiftActive = nil
        local c = wantAuraColor or wantCdColor or style.barColor or DEFAULT_BAR_COLOR
        button.statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4])
    end

    -- Keep the cooldown widget hidden — SetCooldown auto-shows it
    if button.cooldown:IsShown() then
        button.cooldown:Hide()
    end
end

-- Shared OnUpdate for bar-mode buttons: aura expiry detection, pulse/color-shift animation, + throttled bar fill.
-- Reads interval from self._barUpdateInterval so it can be updated without re-installing.
local function BarModeOnUpdate(self, elapsed)
    -- Detect aura expiry via HasSecretValues + GetRemainingDuration.
    -- Non-secret (out of combat): instant expiry detection.
    -- Secret (in combat): skip; UpdateButtonCooldown handles expiry next tick.
    -- Skip when cooldowns are dirty (target switch / UNIT_AURA just fired,
    -- ticker hasn't processed yet — old DurationObject may be invalidated)
    -- or grace period active (holdover DurationObject from previous target).
    if self._auraActive and self._durationObj
       and not self._auraGraceStart and not self._targetSwitchAt and not CooldownCompanion._cooldownsDirty then
        if not self._durationObj:HasSecretValues() then
            if self._durationObj:GetRemainingDuration() <= 0 then
                self._durationObj = nil
                self._auraActive = false
                self._inPandemic = false
                self._barAuraColor = nil
                local c = self.style.barColor or DEFAULT_BAR_COLOR
                self.statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4])
                SetBarAuraEffect(self, false)
                self._barPulseActive = nil
                self._barColorShiftActive = nil
                self.statusBar:SetAlpha(1.0)
            end
        end
    end
    -- Viewer bar expiry (totem/guardian): bar hidden = totem despawned
    if self._auraActive and self._viewerBar
       and not self._auraGraceStart and not self._targetSwitchAt and not CooldownCompanion._cooldownsDirty then
        if not self._viewerBar:IsVisible() then
            self._viewerBar = nil
            self._auraActive = false
            self._inPandemic = false
            self._barAuraColor = nil
            local c = self.style.barColor or DEFAULT_BAR_COLOR
            self.statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4])
            self.statusBar:SetMinMaxValues(0, 1)
            SetBarAuraEffect(self, false)
            self._barPulseActive = nil
            self._barColorShiftActive = nil
            self.statusBar:SetAlpha(1.0)
        end
    end
    -- Per-frame pulse/color-shift animations (must run at frame rate for smoothness)
    if self._barPulseActive or self._barColorShiftActive then
        local now = GetTime()
        if self._barPulseActive then
            local speed = self._barPulseSpeed or 0.5
            self.statusBar:SetAlpha(0.6 + 0.4 * math_sin(now * 2 * math_pi / speed))
        end
        if self._barColorShiftActive then
            local base = self._barCSBaseColor
            local shift = self._barCSShiftColor
            if base and shift then
                local speed = self._barCSSpeed or 0.5
                local t = 0.5 + 0.5 * math_sin(now * 2 * math_pi / speed)
                local ba = base[4] or 1
                self.statusBar:SetStatusBarColor(
                    base[1] + (shift[1] - base[1]) * t,
                    base[2] + (shift[2] - base[2]) * t,
                    base[3] + (shift[3] - base[3]) * t,
                    ba + ((shift[4] or 1) - ba) * t
                )
            else
                self._barColorShiftActive = nil
            end
        end
    end

    self._barFillElapsed = self._barFillElapsed + elapsed
    if self._barFillElapsed >= self._barUpdateInterval then
        self._barFillElapsed = 0
        UpdateBarFill(self)
    end
end

function CooldownCompanion:CreateBarFrame(parent, index, buttonData, style)
    local barLength = style.barLength or 180
    local barHeight = style.barHeight or 20
    local borderSize = style.borderSize or ST.DEFAULT_BORDER_SIZE
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
        SetIconAreaPoints(button.icon, button, isVertical, iconReverse, iconSize, borderSize)
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
    ApplyEdgePositions(button.iconBorderTextures, button._iconBounds, borderSize)

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
    SetBarAreaPoints(button.statusBar, button, isVertical, iconReverse, barAreaLeft, barAreaTop, borderSize)
    if isVertical then
        button.statusBar:SetOrientation("VERTICAL")
    end
    button.statusBar:SetMinMaxValues(0, 1)
    button.statusBar:SetValue(1)
    button.statusBar:SetReverseFill(style.barReverseFill or false)
    button.statusBar:SetStatusBarTexture(CooldownCompanion:FetchStatusBar(style.barTexture or "Solid"))
    local barColor = style.barColor or DEFAULT_BAR_COLOR
    button.statusBar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], barColor[4])
    button.statusBar:EnableMouse(false)

    -- Name text
    button.nameText = button.statusBar:CreateFontString(nil, "OVERLAY")
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
    button.timeText = button.statusBar:CreateFontString(nil, "OVERLAY")
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
    ApplyEdgePositions(button.borderTextures, button._barBounds, borderSize)

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

    -- Aura stack count text — separate FontString for aura stacks, independent of charge text
    if buttonData.auraTracking or buttonData.isPassive then
        button.auraStackCount = button.overlayFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
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
    end

    -- Store button data
    button.index = index
    button.style = style

    -- Cache spell cooldown secrecy level (static per-spell: NeverSecret=0, ContextuallySecret=2)
    if buttonData.type == "spell" then
        buttonData._cooldownSecrecy = C_Secrets.GetSpellCooldownSecrecy(buttonData.id)
    end

    -- Bar fill interpolation OnUpdate
    button._barFillElapsed = 0
    button._barUpdateInterval = style.barUpdateInterval or 0.025
    button:SetScript("OnUpdate", BarModeOnUpdate)

    -- Aura tracking runtime state
    button._auraSpellID = CooldownCompanion:ResolveAuraSpellID(buttonData)
    button._auraUnit = buttonData.auraUnit or "player"
    button._auraActive = false
    button._auraTrackingReady = buttonData.isPassive == true
    button._showingAuraIcon = false
    button._auraViewerFrame = nil
    button._lastViewerTexId = nil

    button._auraInstanceID = nil
    button._viewerBar = nil
    button._viewerAuraVisualsActive = nil

    -- Per-button visibility runtime state
    button._visibilityHidden = false
    button._prevVisibilityHidden = false
    button._visibilityAlphaOverride = nil
    button._lastVisAlpha = 1
    button._groupId = parent.groupId

    -- Aura effect frames (solid border, pixel glow, proc glow)
    button.barAuraEffect = CreateGlowContainer(button, 32)

    -- Set icon
    self:UpdateButtonIcon(button)

    -- Set name text from resolved spell/item name
    if style.showBarNameText ~= false or buttonData.customName then
        local displayName = buttonData.customName or buttonData.name
        if not buttonData.customName then
            if buttonData.type == "spell" then
                local spellName = C_Spell.GetSpellName(button._displaySpellId or buttonData.id)
                if spellName then displayName = spellName end
            elseif buttonData.type == "item" then
                local itemName = C_Item.GetItemNameByID(buttonData.id)
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
    local showTooltips = style.showTooltips == true
    local iconTooltips = showTooltips and showIcon

    -- Disable hover on the full bar; tooltip hover is icon-only via _iconBounds.
    SetFrameClickThroughRecursive(button, true, true)
    -- Prevent child frames from stealing hover.
    if button.statusBar then
        SetFrameClickThroughRecursive(button.statusBar, true, true)
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

    return button
end

function CooldownCompanion:UpdateBarStyle(button, newStyle)
    local barLength = newStyle.barLength or 180
    local barHeight = newStyle.barHeight or 20
    local borderSize = newStyle.borderSize or ST.DEFAULT_BORDER_SIZE
    local showIcon = newStyle.showBarIcon ~= false
    local isVertical = newStyle.barFillVertical or false
    local iconReverse = showIcon and (newStyle.barIconReverse or false)
    local iconSize = (newStyle.barIconSizeOverride and newStyle.barIconSize) or barHeight
    local iconOffset = showIcon and (newStyle.barIconOffset or 0) or 0
    local barAreaLeft = showIcon and (iconSize + iconOffset) or 0
    local barAreaTop = showIcon and (iconSize + iconOffset) or 0

    button.style = newStyle
    button._isVertical = isVertical

    -- Update bar fill OnUpdate interval
    button._barFillElapsed = 0
    button._barUpdateInterval = newStyle.barUpdateInterval or 0.025
    button:SetScript("OnUpdate", BarModeOnUpdate)

    -- Invalidate cached state
    button._desaturated = nil
    button._desatCooldownActive = nil
    button._readyGlowStartTime = nil
    button._readyGlowMaxChargesStartTime = nil
    button._readyGlowMaxChargesActive = nil
    button._readyGlowMaxChargesSpellID = nil
    button._noCooldown = nil
    button._vertexR = nil
    button._vertexG = nil
    button._vertexB = nil
    button._vertexA = nil
    button._chargeText = nil
    button._chargeCountReadable = nil
    button._zeroChargesConfirmed = nil
    button._nilConfirmPending = nil
    button._displaySpellId = nil
    button._itemCount = nil
    button._auraActive = nil
    button._showingAuraIcon = nil
    button._auraViewerFrame = nil
    button._lastViewerTexId = nil

    button._auraInstanceID = nil
    button._viewerBar = nil
    button._inPandemic = nil
    button._pandemicGraceStart = nil
    button._pandemicGraceSuppressed = nil
    button._viewerAuraVisualsActive = nil
    button._auraSpellID = CooldownCompanion:ResolveAuraSpellID(button.buttonData)
    button._auraUnit = button.buttonData.auraUnit or "player"
    button._auraStackText = nil
    button._postCastGCDHold = nil
    button._postCastGCDHoldUntil = nil
    if button.auraStackCount then button.auraStackCount:SetText("") end
    button._visibilityHidden = false
    button._prevVisibilityHidden = false
    button._visibilityAlphaOverride = nil
    button._lastVisAlpha = 1
    button._barCdColor = nil
    button._chargeRecharging = nil
    button._chargesSpent = nil
    button._barReadyTextColor = nil
    button._barAuraColor = nil
    button._barAuraEffectActive = nil
    button._barPulseActive = nil
    button._barColorShiftActive = nil
    button.statusBar:SetAlpha(1.0)

    if isVertical then
        button:SetSize(barHeight, barLength)
    else
        button:SetSize(barLength, barHeight)
    end

    -- Update icon
    button.icon:ClearAllPoints()
    if showIcon then
        SetIconAreaPoints(button.icon, button, isVertical, iconReverse, iconSize, borderSize)
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
        ApplyEdgePositions(button.iconBorderTextures, button._iconBounds, borderSize)
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
    SetBarAreaPoints(button.statusBar, button, isVertical, iconReverse, barAreaLeft, barAreaTop, borderSize)
    if isVertical then
        button.statusBar:SetOrientation("VERTICAL")
    else
        button.statusBar:SetOrientation("HORIZONTAL")
    end
    button.statusBar:SetReverseFill(newStyle.barReverseFill or false)
    button.statusBar:SetStatusBarTexture(CooldownCompanion:FetchStatusBar(newStyle.barTexture or "Solid"))
    local barColor = newStyle.barColor or {0.2, 0.6, 1.0, 1.0}
    button.statusBar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], barColor[4])

    -- Update background
    local bgColor = newStyle.barBgColor or {0.1, 0.1, 0.1, 0.8}
    button.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
    if button.iconBg then
        button.iconBg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
    end

    -- Update border
    local borderColor = newStyle.borderColor or {0, 0, 0, 1}
    if button.borderTextures then
        ApplyEdgePositions(button.borderTextures, button._barBounds or button, borderSize)
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
            elseif button.buttonData.type == "item" then
                local itemName = C_Item.GetItemNameByID(button.buttonData.id)
                if itemName then displayName = itemName end
            end
        end
        button.nameText:SetText(displayName or "")
    end

    -- Update click-through
    local showTooltips = newStyle.showTooltips == true
    local iconTooltips = showTooltips and showIcon

    -- Disable hover on the full bar; tooltip hover is icon-only via _iconBounds.
    SetFrameClickThroughRecursive(button, true, true)
    -- Prevent child frames from stealing hover.
    if button.statusBar then
        SetFrameClickThroughRecursive(button.statusBar, true, true)
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
    CooldownCompanion:UpdateAuraTextureVisual(button)
end

-- Exports
ST._UpdateBarDisplay = UpdateBarDisplay
ST._ApplyBarCountTextStyle = ApplyBarCountTextStyle
