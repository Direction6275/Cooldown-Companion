--[[
    CooldownCompanion - CastBar
    Repositions and reskins PlayerCastingBarFrame to anchor beneath/above an icon group.

    TAINT RULES — PlayerCastingBarFrame has secure OnEvent handlers that access
    CastingBarTypeInfo (keyed by secretwrap values).  Any taint in the execution
    context causes "forbidden table" errors.

    FORBIDDEN (causes taint):
      - Writing ANY Lua property to PlayerCastingBarFrame from addon code
        (e.g. cb.showIcon, cb.showCastTimeSetting, cb.ignoreFramePositionManager).
        These values are read by Blizzard's OnEvent; insecure writes taint the
        entire execution, which cascades: even self.casting, self.barType etc.
        written DURING the tainted event become tainted for subsequent events.
      - Calling SetIconShown() from addon code (writes self.showIcon internally).
      - Calling SetLook() from addon code (writes self.look, self.playCastFX).
      - hooksecurefunc on methods called FROM OnEvent (SetStatusBarTexture, ShowSpark).

    SAFE:
      - C-level widget methods (SetPoint, SetHeight, SetStatusBarTexture,
        SetStatusBarColor, Show, Hide, etc.) — no Lua table entries written.
      - Calling C methods on CHILD objects (cb.Icon:Hide(), cb.Text:SetFont()).
      - hooksecurefunc — does not taint the caller's execution context.
      - hooksecurefunc on methods NOT called from OnEvent (SetLook).

    Strategy: all customisation uses C widget methods only.  A helper frame listens
    for cast events independently and defers re-application via C_Timer.After(0),
    ensuring our code never runs inside Blizzard's secure handler.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local isApplied = false
local pixelBorders = nil
local hooksInstalled = false
local castEventFrame = nil
local fillMaskLeft, fillMaskRight = nil, nil
local isPreviewActive = false
local originalFXSizes = nil

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local function GetCastBarSettings()
    return CooldownCompanion.db and CooldownCompanion.db.profile and CooldownCompanion.db.profile.castBar
end

local function GetAnchorGroupFrame(settings)
    if not settings or not settings.anchorGroupId then return nil end
    return CooldownCompanion.groupFrames[settings.anchorGroupId]
end

--- Create or return the pixel border textures for the cast bar
local function GetPixelBorders(cb)
    if pixelBorders then return pixelBorders end
    pixelBorders = {}
    local names = { "TOP", "BOTTOM", "LEFT", "RIGHT" }
    for _, side in ipairs(names) do
        local tex = cb:CreateTexture(nil, "OVERLAY", nil, 7)
        tex:SetColorTexture(0, 0, 0, 1)
        tex:Hide()
        pixelBorders[side] = tex
    end
    return pixelBorders
end

--- Optional iconFrame + iconOnRight: extends the border to wrap both bar+icon.
local function ShowPixelBorders(cb, color, size, iconFrame, iconOnRight)
    local borders = GetPixelBorders(cb)
    local r, g, b, a = color[1], color[2], color[3], color[4]
    size = size or 1

    for _, tex in pairs(borders) do
        tex:SetColorTexture(r, g, b, a)
        tex:Show()
    end

    local leftFrame = (iconFrame and not iconOnRight) and iconFrame or cb
    local rightFrame = (iconFrame and iconOnRight) and iconFrame or cb

    borders.TOP:SetHeight(size)
    borders.TOP:ClearAllPoints()
    borders.TOP:SetPoint("TOPLEFT", leftFrame, "TOPLEFT", 0, size)
    borders.TOP:SetPoint("TOPRIGHT", rightFrame, "TOPRIGHT", 0, size)

    borders.BOTTOM:SetHeight(size)
    borders.BOTTOM:ClearAllPoints()
    borders.BOTTOM:SetPoint("BOTTOMLEFT", leftFrame, "BOTTOMLEFT", 0, -size)
    borders.BOTTOM:SetPoint("BOTTOMRIGHT", rightFrame, "BOTTOMRIGHT", 0, -size)

    borders.LEFT:SetWidth(size)
    borders.LEFT:ClearAllPoints()
    borders.LEFT:SetPoint("TOPLEFT", leftFrame, "TOPLEFT", -size, size)
    borders.LEFT:SetPoint("BOTTOMLEFT", leftFrame, "BOTTOMLEFT", -size, -size)

    borders.RIGHT:SetWidth(size)
    borders.RIGHT:ClearAllPoints()
    borders.RIGHT:SetPoint("TOPRIGHT", rightFrame, "TOPRIGHT", size, size)
    borders.RIGHT:SetPoint("BOTTOMRIGHT", rightFrame, "BOTTOMRIGHT", size, -size)
end

local function HidePixelBorders()
    if not pixelBorders then return end
    for _, tex in pairs(pixelBorders) do
        tex:Hide()
    end
end

--- Icon pixel borders (inline mode — matches bar border style)
local iconPixelBorders = nil

local function GetIconPixelBorders(cb)
    if iconPixelBorders then return iconPixelBorders end
    iconPixelBorders = {}
    local names = { "TOP", "BOTTOM", "LEFT", "RIGHT" }
    for _, side in ipairs(names) do
        local tex = cb:CreateTexture(nil, "OVERLAY", nil, 7)
        tex:SetColorTexture(0, 0, 0, 1)
        tex:Hide()
        iconPixelBorders[side] = tex
    end
    return iconPixelBorders
end

local function ShowIconPixelBorders(cb, color, size)
    local borders = GetIconPixelBorders(cb)
    local r, g, b, a = color[1], color[2], color[3], color[4]
    size = size or 1

    for _, tex in pairs(borders) do
        tex:SetColorTexture(r, g, b, a)
        tex:Show()
    end

    borders.TOP:SetHeight(size)
    borders.TOP:ClearAllPoints()
    borders.TOP:SetPoint("TOPLEFT", cb.Icon, "TOPLEFT", 0, size)
    borders.TOP:SetPoint("TOPRIGHT", cb.Icon, "TOPRIGHT", 0, size)

    borders.BOTTOM:SetHeight(size)
    borders.BOTTOM:ClearAllPoints()
    borders.BOTTOM:SetPoint("BOTTOMLEFT", cb.Icon, "BOTTOMLEFT", 0, -size)
    borders.BOTTOM:SetPoint("BOTTOMRIGHT", cb.Icon, "BOTTOMRIGHT", 0, -size)

    borders.LEFT:SetWidth(size)
    borders.LEFT:ClearAllPoints()
    borders.LEFT:SetPoint("TOPLEFT", cb.Icon, "TOPLEFT", -size, size)
    borders.LEFT:SetPoint("BOTTOMLEFT", cb.Icon, "BOTTOMLEFT", -size, -size)

    borders.RIGHT:SetWidth(size)
    borders.RIGHT:ClearAllPoints()
    borders.RIGHT:SetPoint("TOPRIGHT", cb.Icon, "TOPRIGHT", size, size)
    borders.RIGHT:SetPoint("BOTTOMRIGHT", cb.Icon, "BOTTOMRIGHT", size, -size)
end

local function HideIconPixelBorders()
    if not iconPixelBorders then return end
    for _, tex in pairs(iconPixelBorders) do
        tex:Hide()
    end
end

--- Fill edge masks: thin opaque strips at the left/right edges of the StatusBar
--- that prevent the bar fill texture from visually poking past the Blizzard border
--- atlas when the bar is wider/taller than the designed 208x11 default.
--- Layer: ARTWORK sublevel 1 (above fill at BORDER, below border at ARTWORK sublevel 4).
local function EnsureFillMasks(cb)
    if fillMaskLeft then return end
    fillMaskLeft = cb:CreateTexture(nil, "ARTWORK", nil, 1)
    fillMaskRight = cb:CreateTexture(nil, "ARTWORK", nil, 1)

    fillMaskLeft:SetColorTexture(0, 0, 0, 1)
    fillMaskLeft:SetWidth(2)
    fillMaskLeft:SetPoint("TOPLEFT", cb, "TOPLEFT", 0, 0)
    fillMaskLeft:SetPoint("BOTTOMLEFT", cb, "BOTTOMLEFT", 0, 0)

    fillMaskRight:SetColorTexture(0, 0, 0, 1)
    fillMaskRight:SetWidth(2)
    fillMaskRight:SetPoint("TOPRIGHT", cb, "TOPRIGHT", 0, 0)
    fillMaskRight:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", 0, 0)
end

local function ShowFillMasks(cb)
    EnsureFillMasks(cb)
    fillMaskLeft:Show()
    fillMaskRight:Show()
end

local function HideFillMasks()
    if fillMaskLeft then fillMaskLeft:Hide() end
    if fillMaskRight then fillMaskRight:Hide() end
end

------------------------------------------------------------------------
-- Spark sizing helper — height matches bar exactly, width stays default
------------------------------------------------------------------------

-- Default spark is 20px for an 11px bar.  1.66x splits the difference between
-- the full default ratio (1.82x) and a tighter fit (1.5x).
local SPARK_HEIGHT_SCALE = 1.66

local function ApplySparkSize(cb, barHeight)
    if not cb.Spark then return end
    local atlas = cb.Spark:GetAtlas()
    if atlas then
        cb.Spark:SetAtlas(atlas, false)
    end
    cb.Spark:SetSize(8, barHeight * SPARK_HEIGHT_SCALE)
end

------------------------------------------------------------------------
-- FX scaling helpers — scale cast bar effect textures proportionally
-- Default bar is 208x11; FX regions are designed for that size.
-- When the bar is wider/taller, scale all FX regions proportionally.
------------------------------------------------------------------------

-- Bar-wide FX: scale both width and height proportionally
local FX_REGIONS_BAR_WIDE = {
    "BorderMask",       -- MaskTexture that clips all FX (256x13)
    "InterruptGlow",    -- interrupt outer glow
    "ChargeGlow",       -- empowered outer glow
    "EnergyGlow",       -- standard finish upward glow
    "EnergyMask",       -- standard finish mask
    "Flakes01",         -- standard finish particles
    "Flakes02",
    "Flakes03",
    "Shine",            -- crafting finish wipe
    "CraftingMask",     -- crafting finish mask
    "BaseGlow",         -- channel finish FX
    "WispGlow",
    "WispMask",
    "Sparkles01",
    "Sparkles02",
}

-- Spark-local FX: small textures anchored to the spark pip — scale height only
local FX_REGIONS_SPARK_LOCAL = {
    "StandardGlow",     -- spark trail glow (37x12)
    "CraftGlow",        -- craft spark trail glow (37x12)
    "ChannelShadow",    -- channel spark shadow (11x11)
}

local function CaptureOriginalFXSizes(cb)
    if originalFXSizes then return end
    originalFXSizes = {}
    for _, name in ipairs(FX_REGIONS_BAR_WIDE) do
        local region = cb[name]
        if region then
            local w, h = region:GetSize()
            if w and h and w > 0 and h > 0 then
                originalFXSizes[name] = { w = w, h = h }
            end
        end
    end
    for _, name in ipairs(FX_REGIONS_SPARK_LOCAL) do
        local region = cb[name]
        if region then
            local w, h = region:GetSize()
            if w and h and w > 0 and h > 0 then
                originalFXSizes[name] = { w = w, h = h }
            end
        end
    end
end

local function ApplyFXScaling(cb, barWidth, barHeight)
    CaptureOriginalFXSizes(cb)
    if not originalFXSizes then return end

    local widthScale = barWidth / 208
    local heightScale = barHeight / 11

    for _, name in ipairs(FX_REGIONS_BAR_WIDE) do
        local orig = originalFXSizes[name]
        if orig then
            local region = cb[name]
            if region then
                region:SetSize(orig.w * widthScale, orig.h * heightScale)
            end
        end
    end
    -- Spark-local: height only — width stays original to avoid distortion
    for _, name in ipairs(FX_REGIONS_SPARK_LOCAL) do
        local orig = originalFXSizes[name]
        if orig then
            local region = cb[name]
            if region then
                region:SetSize(orig.w, orig.h * heightScale)
            end
        end
    end
end

local function RevertFXScaling(cb)
    if not originalFXSizes then return end
    for _, name in ipairs(FX_REGIONS_BAR_WIDE) do
        local orig = originalFXSizes[name]
        if orig then
            local region = cb[name]
            if region then
                region:SetSize(orig.w, orig.h)
            end
        end
    end
    for _, name in ipairs(FX_REGIONS_SPARK_LOCAL) do
        local orig = originalFXSizes[name]
        if orig then
            local region = cb[name]
            if region then
                region:SetSize(orig.w, orig.h)
            end
        end
    end
end

------------------------------------------------------------------------
-- FX suppression — hides/stops individual FX categories.
-- Called from DeferredReapply and ApplyCastBarSettings (both branches).
-- Uses ~= false so missing keys default to enabled.
------------------------------------------------------------------------

local function SuppressFX(cb, s)
    -- Always hide ChannelShadow when styling is on (artifacts)
    if s.stylingEnabled then
        if cb.ChannelShadow then cb.ChannelShadow:Hide() end
    end
    if s.showSparkTrail == false then
        if cb.StandardGlow then cb.StandardGlow:Hide() end
        if cb.CraftGlow then cb.CraftGlow:Hide() end
        if cb.ChannelShadow then cb.ChannelShadow:Hide() end
    end
    if s.showInterruptShake == false then
        if cb.InterruptShakeAnim then cb.InterruptShakeAnim:Stop() end
    end
    if s.showInterruptGlow == false then
        if cb.InterruptGlowAnim then cb.InterruptGlowAnim:Stop() end
        if cb.InterruptGlow then cb.InterruptGlow:SetAlpha(0) end
    end
    if s.showCastFinishFX == false then
        if cb.StandardFinish then cb.StandardFinish:Stop() end
        if cb.FlashAnim then cb.FlashAnim:Stop() end
        if cb.Flash then cb.Flash:SetAlpha(0) end
    end
    if s.showChannelFinishFX == false then
        if cb.ChannelFinish then cb.ChannelFinish:Stop() end
        if cb.FlashAnim then cb.FlashAnim:Stop() end
        if cb.Flash then cb.Flash:SetAlpha(0) end
    end
    if s.showCraftFinishFX == false then
        if cb.CraftingFinish then cb.CraftingFinish:Stop() end
        if cb.FlashAnim then cb.FlashAnim:Stop() end
        if cb.Flash then cb.Flash:SetAlpha(0) end
    end
end

------------------------------------------------------------------------
-- FX hooks — synchronous suppression via hooksecurefunc on Play().
-- hooksecurefunc runs immediately after the original call (same frame),
-- so Stop() prevents even a single rendered frame of the animation.
-- IMPORTANT: `self` in hook callbacks is a SECRET VALUE when Play() is
-- called from Blizzard's secure OnEvent — cannot be indexed.  We capture
-- a local reference to each AnimationGroup at install time instead.
-- All hooks are on CHILD objects (AnimationGroup) — taint-safe.
------------------------------------------------------------------------

local fxHooksInstalled = false

local function InstallFXHooks(cb)
    if fxHooksInstalled then return end
    fxHooksInstalled = true

    -- Each type-specific hook also suppresses FlashAnim + Flash (the shared border
    -- glow).  PlayFadeAnim (FlashAnim) fires BEFORE PlayFinishAnim in the same frame,
    -- so stopping FlashAnim from the type hook is still same-frame — no visible flash.
    if cb.StandardFinish then
        local anim = cb.StandardFinish
        hooksecurefunc(anim, "Play", function()
            local s = GetCastBarSettings()
            if s and s.showCastFinishFX == false then
                anim:Stop()
                if cb.FlashAnim then cb.FlashAnim:Stop() end
                if cb.Flash then cb.Flash:SetAlpha(0) end
            end
        end)
    end
    if cb.ChannelFinish then
        local anim = cb.ChannelFinish
        hooksecurefunc(anim, "Play", function()
            local s = GetCastBarSettings()
            if s and s.showChannelFinishFX == false then
                anim:Stop()
                if cb.FlashAnim then cb.FlashAnim:Stop() end
                if cb.Flash then cb.Flash:SetAlpha(0) end
            end
        end)
    end
    if cb.CraftingFinish then
        local anim = cb.CraftingFinish
        hooksecurefunc(anim, "Play", function()
            local s = GetCastBarSettings()
            if s and s.showCraftFinishFX == false then
                anim:Stop()
                if cb.FlashAnim then cb.FlashAnim:Stop() end
                if cb.Flash then cb.Flash:SetAlpha(0) end
            end
        end)
    end
    if cb.InterruptGlowAnim then
        local anim = cb.InterruptGlowAnim
        hooksecurefunc(anim, "Play", function()
            local s = GetCastBarSettings()
            if s and s.showInterruptGlow == false then
                anim:Stop()
                if cb.InterruptGlow then cb.InterruptGlow:SetAlpha(0) end
            end
        end)
    end
    if cb.ChannelShadow then
        local shadow = cb.ChannelShadow
        hooksecurefunc(shadow, "Show", function()
            if not isApplied then return end
            local s = GetCastBarSettings()
            if s and s.stylingEnabled then
                shadow:Hide()
            end
        end)
    end
end

------------------------------------------------------------------------
-- Spark size hook — replaces per-frame OnUpdate with a same-frame hook
-- on Spark:SetAtlas (fired by Blizzard's ShowSpark during cast events).
------------------------------------------------------------------------
local sparkHookInstalled = false

local function InstallSparkHook(cb)
    if sparkHookInstalled then return end
    if not cb or not cb.Spark then return end
    sparkHookInstalled = true

    local spark = cb.Spark
    hooksecurefunc(spark, "SetAtlas", function()
        if not isApplied then return end
        local s = GetCastBarSettings()
        if not s or not s.enabled then return end
        local barH = s.stylingEnabled and (s.height or 14) or 11
        spark:SetSize(8, barH * SPARK_HEIGHT_SCALE)
    end)
end

------------------------------------------------------------------------
-- Position helper (used by both Apply and DeferredReapply)
------------------------------------------------------------------------

local function ApplyPosition(cb, s, height)
    local groupFrame = GetAnchorGroupFrame(s)
    if not groupFrame then return end

    -- Remove from managed layout (OnShow re-adds on each cast via AddManagedFrame)
    UIParentBottomManagedFrameContainer:RemoveManagedFrame(cb)

    cb:ClearAllPoints()
    local yOfs = s.yOffset or -2
    local stackOffset = CooldownCompanion:GetAnchorStackOffset("castBar")

    -- Inline icon: inset bar on the icon side so fill/spark stay within bar area
    local iconInsetLeft, iconInsetRight = 0, 0
    if s.stylingEnabled and s.showIcon and not s.iconOffset then
        local iconSize = height
        if s.iconFlipSide then
            iconInsetRight = iconSize
        else
            iconInsetLeft = iconSize
        end
    end

    if s.position == "above" then
        cb:SetPoint("BOTTOMLEFT", groupFrame, "TOPLEFT", iconInsetLeft, -yOfs + stackOffset)
        cb:SetPoint("BOTTOMRIGHT", groupFrame, "TOPRIGHT", -iconInsetRight, -yOfs + stackOffset)
    else
        cb:SetPoint("TOPLEFT", groupFrame, "BOTTOMLEFT", iconInsetLeft, yOfs - stackOffset)
        cb:SetPoint("TOPRIGHT", groupFrame, "BOTTOMRIGHT", -iconInsetRight, yOfs - stackOffset)
    end

    cb:SetHeight(height or 14)
end

------------------------------------------------------------------------
-- Deferred re-apply: runs NEXT FRAME after Blizzard's secure OnEvent
------------------------------------------------------------------------
local pendingReapply = false

local function DeferredReapply()
    pendingReapply = false
    if not isApplied then return end
    local cb = PlayerCastingBarFrame
    if not cb then return end
    local s = GetCastBarSettings()
    if not s or not s.enabled then return end

    -- Effective height: custom when styling on, Blizzard default when off
    local effectiveHeight = s.stylingEnabled and (s.height or 14) or 11

    -- Re-position (OnShow's AddManagedFrame may have repositioned us)
    ApplyPosition(cb, s, effectiveHeight)

    -- Spark sizing (technical — always applies regardless of styling)
    ApplySparkSize(cb, effectiveHeight)

    -- FX scaling (always applies when anchored — spark trails, interrupt glow, etc.)
    ApplyFXScaling(cb, cb:GetWidth(), effectiveHeight)

    -- FX suppression (always applies — user toggles for individual FX categories)
    SuppressFX(cb, s)

    if s.stylingEnabled then
        -- Re-apply custom bar texture (Blizzard resets to atlas on each cast event)
        if s.barTexture and s.barTexture ~= "" then
            cb:SetStatusBarTexture(s.barTexture)
        end

        -- Re-apply custom bar color
        local bc = s.barColor
        if bc then
            cb:SetStatusBarColor(bc[1], bc[2], bc[3], bc[4])
        end

        -- Re-apply icon visibility, size, and position
        if cb.Icon then
            cb.Icon:SetShown(s.showIcon or false)
            if s.showIcon then
                cb.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                if s.iconOffset then
                    local iSize = s.iconSize or 16
                    cb.Icon:SetSize(iSize, iSize)
                    cb.Icon:ClearAllPoints()
                    local ox = s.iconOffsetX or 0
                    local oy = s.iconOffsetY or 0
                    if s.iconFlipSide then
                        cb.Icon:SetPoint("LEFT", cb, "RIGHT", 5 + ox, oy)
                    else
                        cb.Icon:SetPoint("RIGHT", cb, "LEFT", -5 + ox, oy)
                    end
                else
                    local iconSize = effectiveHeight
                    cb.Icon:SetSize(iconSize, iconSize)
                    cb.Icon:ClearAllPoints()
                    if s.iconFlipSide then
                        cb.Icon:SetPoint("LEFT", cb, "RIGHT", 0, 0)
                    else
                        cb.Icon:SetPoint("RIGHT", cb, "LEFT", 0, 0)
                    end
                end
            end
        end

        -- Re-apply pixel borders
        local bStyle = s.borderStyle or "blizzard"
        if bStyle == "pixel" then
            local bColor = s.borderColor or {0,0,0,1}
            local bSize = s.borderSize or 1
            if s.showIcon and not s.iconOffset then
                ShowPixelBorders(cb, bColor, bSize, cb.Icon, s.iconFlipSide)
            else
                ShowPixelBorders(cb, bColor, bSize)
            end
            if s.showIcon and s.iconOffset then
                ShowIconPixelBorders(cb, bColor, s.iconBorderSize or 1)
            else
                HideIconPixelBorders()
            end
        else
            HideIconPixelBorders()
        end

        -- Re-apply cast time text visibility
        if cb.CastTimeText then
            if s.showCastTimeText then
                cb.CastTimeText:SetShown(cb.casting or cb.channeling or false)
            else
                cb.CastTimeText:Hide()
            end
        end

        -- Re-apply spark visibility
        if not s.showSpark and cb.Spark then
            cb.Spark:Hide()
        end

        -- Re-hide TextBorder
        if cb.TextBorder then
            cb.TextBorder:Hide()
        end

        -- Re-show fill masks based on border style
        if (s.borderStyle or "blizzard") == "blizzard" then
            ShowFillMasks(cb)
        end
    else
        -- Anchoring-only: just show fill masks (Blizzard border at non-standard width)
        ShowFillMasks(cb)
    end
end

local function ScheduleReapply()
    if pendingReapply then return end
    if not isApplied then return end
    pendingReapply = true
    C_Timer.After(0, DeferredReapply)
end

--- Create the helper frame that listens for cast events on a SEPARATE frame
--- (not on PlayerCastingBarFrame) and schedules deferred re-apply.
local function EnsureCastEventFrame()
    if castEventFrame then return end
    castEventFrame = CreateFrame("Frame")
    castEventFrame:SetScript("OnEvent", function(self, event, unit)
        if unit and unit ~= "player" then return end
        -- Real cast started — end preview if active
        if isPreviewActive then
            isPreviewActive = false
        end
        ScheduleReapply()
    end)
    castEventFrame:Hide()
end

local function EnableCastEventFrame()
    EnsureCastEventFrame()
    castEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    castEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    castEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    castEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    castEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "player")
    castEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player")
    castEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    castEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", "player")
    castEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "player")
    castEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_UPDATE", "player")
end

local function DisableCastEventFrame()
    if not castEventFrame then return end
    castEventFrame:UnregisterAllEvents()
    pendingReapply = false
end

------------------------------------------------------------------------
-- Revert: restore Blizzard defaults
-- NOTE: We must NOT call cb:SetLook("CLASSIC") — calling it from addon
-- code writes self.look, self.playCastFX etc. which taints OnEvent.
-- Instead we manually restore the CLASSIC visual state using C methods.
------------------------------------------------------------------------
function CooldownCompanion:RevertCastBar()
    if not isApplied then return end
    isApplied = false

    DisableCastEventFrame()

    local cb = PlayerCastingBarFrame
    if not cb then return end

    -- Restore size (CLASSIC defaults)
    cb:SetWidth(208)
    cb:SetHeight(11)

    -- Restore parent / strata
    cb:SetParent(UIParent)
    cb:SetFixedFrameStrata(true)
    cb:SetFrameStrata("HIGH")

    -- Restore EditMode position.
    -- AddManagedFrame early-exits when IsInDefaultPosition() is false (custom EditMode
    -- position), leaving the bar with no anchors.  Read the saved anchorInfo directly
    -- and apply it ourselves (all reads + C SetPoint — taint-safe).
    cb:ClearAllPoints()
    if cb.systemInfo and cb.systemInfo.anchorInfo and not cb:IsInDefaultPosition() then
        local scale = cb:GetScale()
        local ai = cb.systemInfo.anchorInfo
        cb:SetPoint(ai.point, ai.relativeTo, ai.relativePoint,
                    ai.offsetX / scale, ai.offsetY / scale)
        if cb.systemInfo.anchorInfo2 then
            local ai2 = cb.systemInfo.anchorInfo2
            cb:SetPoint(ai2.point, ai2.relativeTo, ai2.relativePoint,
                        ai2.offsetX / scale, ai2.offsetY / scale)
        end
    else
        UIParentBottomManagedFrameContainer:AddManagedFrame(cb)
    end

    -- Restore bar fill to default atlas and reset color tint
    cb:SetStatusBarTexture("ui-castingbar-filling-standard")
    cb:SetStatusBarColor(1, 1, 1, 1)

    -- Restore background atlas and anchoring
    if cb.Background then
        cb.Background:SetAtlas("ui-castingbar-background")
        cb.Background:SetVertexColor(1, 1, 1, 1)
        cb.Background:ClearAllPoints()
        cb.Background:SetPoint("TOPLEFT", -1, 1)
        cb.Background:SetPoint("BOTTOMRIGHT", 1, -1)
    end

    -- Restore Blizzard border atlas
    if cb.Border then
        cb.Border:SetAtlas("ui-castingbar-frame")
        cb.Border:Show()
    end

    -- Show TextBorder again (CLASSIC shows it)
    if cb.TextBorder then
        cb.TextBorder:Show()
    end

    -- Hide pixel borders, icon borders, and fill masks
    HidePixelBorders()
    HideIconPixelBorders()
    HideFillMasks()

    -- Restore FX regions to original sizes
    RevertFXScaling(cb)

    -- End preview if active
    isPreviewActive = false

    -- Restore spark visibility and size (CLASSIC: 8x20)
    if cb.Spark then
        cb.Spark:SetSize(8, 20)
        cb.Spark:Show()
    end

    -- Restore icon (CLASSIC: hidden, 16x16, left side)
    if cb.Icon then
        cb.Icon:Hide()
        cb.Icon:SetSize(16, 16)
        cb.Icon:SetDrawLayer("ARTWORK", 0)
        cb.Icon:SetTexCoord(0, 1, 0, 1)
        cb.Icon:ClearAllPoints()
        cb.Icon:SetPoint("RIGHT", cb, "LEFT", -5, 0)
    end

    -- Restore text to CLASSIC defaults
    if cb.Text then
        cb.Text:Show()
        cb.Text:ClearAllPoints()
        cb.Text:SetWidth(185)
        cb.Text:SetHeight(16)
        cb.Text:SetPoint("TOP", 0, -10)
        cb.Text:SetFontObject("GameFontHighlightSmall")
        cb.Text:SetJustifyH("CENTER")
        cb.Text:SetVertexColor(1, 1, 1, 1)
    end

    -- Restore cast time text
    if cb.CastTimeText then
        cb.CastTimeText:SetFontObject("GameFontHighlightLarge")
        cb.CastTimeText:ClearAllPoints()
        cb.CastTimeText:SetPoint("LEFT", cb, "RIGHT", 10, 0)
        cb.CastTimeText:SetVertexColor(1, 1, 1, 1)
    end

    -- Restore BorderShield to CLASSIC defaults
    if cb.BorderShield then
        cb.BorderShield:ClearAllPoints()
        cb.BorderShield:SetWidth(256)
        cb.BorderShield:SetHeight(64)
        cb.BorderShield:SetPoint("TOP", 0, 28)
    end

    -- Hide DropShadow (CLASSIC hides it)
    if cb.DropShadow then
        cb.DropShadow:Hide()
    end
end

------------------------------------------------------------------------
-- Apply: reposition and restyle the cast bar
-- CRITICAL: only C-level widget methods — NO Lua property writes to cb
------------------------------------------------------------------------
function CooldownCompanion:ApplyCastBarSettings()
    local settings = GetCastBarSettings()
    if not settings or not settings.enabled then
        self:RevertCastBar()
        return
    end

    -- Validate anchor group
    local groupId = settings.anchorGroupId
    if not groupId then
        self:RevertCastBar()
        return
    end

    local group = self.db.profile.groups[groupId]
    if not group then
        self:RevertCastBar()
        return
    end

    local groupFrame = GetAnchorGroupFrame(settings)
    if not groupFrame or not groupFrame:IsShown() then
        self:RevertCastBar()
        return
    end

    -- Only anchor to icon-mode groups
    if group.displayMode ~= "icons" then
        self:RevertCastBar()
        return
    end

    local cb = PlayerCastingBarFrame
    if not cb then return end

    -- Remove from managed layout — C method on CONTAINER, not on cast bar
    -- (we do NOT set cb.ignoreFramePositionManager — that taints OnEvent)
    UIParentBottomManagedFrameContainer:RemoveManagedFrame(cb)
    cb:SetParent(UIParent)
    cb:SetFixedFrameStrata(true)
    cb:SetFrameStrata("HIGH")

    -- ---- ANCHORING (always applied when enabled) ----
    -- Height: use custom setting when styling is on, Blizzard default (11) when off
    local effectiveHeight = settings.stylingEnabled and (settings.height or 14) or 11
    ApplyPosition(cb, settings, effectiveHeight)
    ApplySparkSize(cb, effectiveHeight)
    local barWidth = groupFrame:GetWidth()
    if settings.showIcon and not settings.iconOffset and settings.stylingEnabled then
        barWidth = barWidth - effectiveHeight
    end
    ApplyFXScaling(cb, barWidth, effectiveHeight)

    -- FX hooks (once) + suppression (always applies — user toggles for FX categories)
    InstallFXHooks(cb)
    InstallSparkHook(cb)
    SuppressFX(cb, settings)

    if settings.stylingEnabled then
        -- ---- STYLING (optional layer) ----

        -- Bar fill color (C widget method — safe)
        local bc = settings.barColor
        if bc then
            cb:SetStatusBarColor(bc[1], bc[2], bc[3], bc[4])
        end

        -- Bar fill texture (C widget method — safe)
        local tex = settings.barTexture
        if tex and tex ~= "" then
            cb:SetStatusBarTexture(tex)
        end

        -- Background color (C methods on child — safe)
        if cb.Background then
            local bgc = settings.backgroundColor
            if bgc then
                cb.Background:SetAtlas(nil)
                cb.Background:SetColorTexture(bgc[1], bgc[2], bgc[3], bgc[4])
                cb.Background:ClearAllPoints()
                cb.Background:SetPoint("TOPLEFT", 0, 0)
                cb.Background:SetPoint("BOTTOMRIGHT", 0, 0)
            end
        end

        -- Icon visibility, size, and position — C methods on CHILD
        if cb.Icon then
            cb.Icon:SetShown(settings.showIcon or false)
            if settings.showIcon then
                cb.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                if settings.iconOffset then
                    -- Offset mode: custom size, positioned outside bar with X/Y offsets
                    local iSize = settings.iconSize or 16
                    cb.Icon:SetSize(iSize, iSize)
                    cb.Icon:ClearAllPoints()
                    local ox = settings.iconOffsetX or 0
                    local oy = settings.iconOffsetY or 0
                    if settings.iconFlipSide then
                        cb.Icon:SetPoint("LEFT", cb, "RIGHT", 5 + ox, oy)
                    else
                        cb.Icon:SetPoint("RIGHT", cb, "LEFT", -5 + ox, oy)
                    end
                else
                    -- Inline mode: icon outside bar, same height as bar
                    local iconSize = effectiveHeight
                    cb.Icon:SetSize(iconSize, iconSize)
                    cb.Icon:ClearAllPoints()
                    if settings.iconFlipSide then
                        cb.Icon:SetPoint("LEFT", cb, "RIGHT", 0, 0)
                    else
                        cb.Icon:SetPoint("RIGHT", cb, "LEFT", 0, 0)
                    end
                end
            end
        end

        -- Spark visibility
        if not settings.showSpark and cb.Spark then
            cb.Spark:Hide()
        end

        -- Border style
        local borderStyle = settings.borderStyle or "blizzard"
        if borderStyle == "blizzard" then
            HidePixelBorders()
            HideIconPixelBorders()
            if cb.Border then
                cb.Border:SetAtlas("ui-castingbar-frame")
                cb.Border:Show()
            end
            ShowFillMasks(cb)
        elseif borderStyle == "pixel" then
            HideFillMasks()
            if cb.Border then
                cb.Border:Hide()
            end
            local bColor = settings.borderColor or { 0, 0, 0, 1 }
            local bSize = settings.borderSize or 1
            if settings.showIcon and not settings.iconOffset then
                ShowPixelBorders(cb, bColor, bSize, cb.Icon, settings.iconFlipSide)
            else
                ShowPixelBorders(cb, bColor, bSize)
            end
            -- Icon border (offset mode only)
            if settings.showIcon and settings.iconOffset then
                ShowIconPixelBorders(cb, bColor, settings.iconBorderSize or 1)
            else
                HideIconPixelBorders()
            end
        elseif borderStyle == "none" then
            HidePixelBorders()
            HideIconPixelBorders()
            HideFillMasks()
            if cb.Border then
                cb.Border:Hide()
            end
        end

        -- Hide TextBorder
        if cb.TextBorder then
            cb.TextBorder:Hide()
        end

        -- Spell name text (C methods on child — safe)
        if cb.Text then
            if settings.showNameText then
                cb.Text:Show()
                local nf = settings.nameFont or "Fonts\\FRIZQT__.TTF"
                local ns = settings.nameFontSize or 10
                local no = settings.nameFontOutline or "OUTLINE"
                cb.Text:SetFont(nf, ns, no)
                cb.Text:ClearAllPoints()
                cb.Text:SetPoint("LEFT", cb, "LEFT", 4, 0)
                cb.Text:SetPoint("RIGHT", cb, "RIGHT", -4, 0)
                cb.Text:SetWidth(0)
                cb.Text:SetHeight(0)
                cb.Text:SetJustifyH("LEFT")
                local nc = settings.nameFontColor
                if nc then
                    cb.Text:SetVertexColor(nc[1], nc[2], nc[3], nc[4])
                end
            else
                cb.Text:Hide()
            end
        end

        -- Cast time text — C methods only, NOT showCastTimeSetting
        if cb.CastTimeText then
            if settings.showCastTimeText then
                local ctf = settings.castTimeFont or "Fonts\\FRIZQT__.TTF"
                local cts = settings.castTimeFontSize or 10
                local cto = settings.castTimeFontOutline or "OUTLINE"
                cb.CastTimeText:SetFont(ctf, cts, cto)
                cb.CastTimeText:ClearAllPoints()
                local xOfs = settings.castTimeXOffset or 0
                local ctYOfs = settings.castTimeYOffset or 0
                cb.CastTimeText:SetPoint("RIGHT", cb, "RIGHT", -4 + xOfs, ctYOfs)
                cb.CastTimeText:SetJustifyH("RIGHT")
                local ctc = settings.castTimeFontColor
                if ctc then
                    cb.CastTimeText:SetVertexColor(ctc[1], ctc[2], ctc[3], ctc[4])
                end
                cb.CastTimeText:SetShown(cb.casting or cb.channeling or false)
            else
                cb.CastTimeText:Hide()
            end
        end
    else
        -- ---- ANCHORING ONLY — restore Blizzard default visuals ----
        -- (needed to undo styling if it was previously enabled)
        cb:SetStatusBarTexture("ui-castingbar-filling-standard")
        cb:SetStatusBarColor(1, 1, 1, 1)

        if cb.Background then
            cb.Background:SetAtlas("ui-castingbar-background")
            cb.Background:SetVertexColor(1, 1, 1, 1)
            cb.Background:ClearAllPoints()
            cb.Background:SetPoint("TOPLEFT", -1, 1)
            cb.Background:SetPoint("BOTTOMRIGHT", 1, -1)
        end

        if cb.Icon then
            cb.Icon:Hide()
            cb.Icon:SetSize(16, 16)
            cb.Icon:SetDrawLayer("ARTWORK", 0)
            cb.Icon:SetTexCoord(0, 1, 0, 1)
            cb.Icon:ClearAllPoints()
            cb.Icon:SetPoint("RIGHT", cb, "LEFT", -5, 0)
        end
        if cb.Spark then cb.Spark:Show() end

        HidePixelBorders()
        HideIconPixelBorders()
        if cb.Border then
            cb.Border:SetAtlas("ui-castingbar-frame")
            cb.Border:Show()
        end
        ShowFillMasks(cb)

        if cb.TextBorder then cb.TextBorder:Show() end

        -- Restore text to CLASSIC defaults
        if cb.Text then
            cb.Text:Show()
            cb.Text:ClearAllPoints()
            cb.Text:SetWidth(185)
            cb.Text:SetHeight(16)
            cb.Text:SetPoint("TOP", 0, -10)
            cb.Text:SetFontObject("GameFontHighlightSmall")
            cb.Text:SetJustifyH("CENTER")
            cb.Text:SetVertexColor(1, 1, 1, 1)
        end

        if cb.CastTimeText then
            cb.CastTimeText:SetFontObject("GameFontHighlightLarge")
            cb.CastTimeText:ClearAllPoints()
            cb.CastTimeText:SetPoint("LEFT", cb, "RIGHT", 10, 0)
            cb.CastTimeText:SetVertexColor(1, 1, 1, 1)
        end
    end

    isApplied = true

    -- Enable the helper frame that re-applies visuals on each cast event
    EnableCastEventFrame()
end

------------------------------------------------------------------------
-- Evaluate: central decision point
------------------------------------------------------------------------
function CooldownCompanion:EvaluateCastBar()
    local settings = GetCastBarSettings()
    if not settings or not settings.enabled then
        self:RevertCastBar()
        return
    end
    self:ApplyCastBarSettings()
end

------------------------------------------------------------------------
-- Preview: show the cast bar with fake cast data for settings preview.
-- State is ephemeral (local flag, not saved to DB).  Preview ends when:
--   • a real cast event fires
--   • the user unchecks Preview
--   • the cast bar panel is deactivated / config panel closed
--   • the feature is disabled / anchor reverts
------------------------------------------------------------------------

local function ApplyPreview()
    if not isApplied then return end
    local cb = PlayerCastingBarFrame
    if not cb then return end
    local s = GetCastBarSettings()
    if not s or not s.enabled then return end

    -- Ensure the managed frame system doesn't fight us
    UIParentBottomManagedFrameContainer:RemoveManagedFrame(cb)

    cb:SetAlpha(1)
    cb:Show()
    cb:SetMinMaxValues(0, 100)
    cb:SetValue(65)

    -- Spell name text
    if cb.Text then
        cb.Text:SetText("Preview Cast")
        cb.Text:Show()
    end

    -- Cast time text (always show in preview so the user can see layout)
    if cb.CastTimeText then
        cb.CastTimeText:SetText("1.5 s")
        if s.stylingEnabled then
            cb.CastTimeText:SetShown(s.showCastTimeText ~= false)
        else
            cb.CastTimeText:Show()
        end
    end

    -- Spark at the fill edge (65% of bar width)
    if cb.Spark then
        local showSpark = (not s.stylingEnabled) or (s.showSpark ~= false)
        if showSpark then
            local sparkPos = 0.65 * cb:GetWidth()
            cb.Spark:Show()
            cb.Spark:ClearAllPoints()
            cb.Spark:SetPoint("CENTER", cb, "LEFT", sparkPos, cb.Spark.offsetY or 0)
        else
            cb.Spark:Hide()
        end
    end

    -- TextBorder: hide only when styling is active
    if s.stylingEnabled and cb.TextBorder then
        cb.TextBorder:Hide()
    end

    -- Fill masks
    local borderStyle = s.stylingEnabled and (s.borderStyle or "blizzard") or "blizzard"
    if borderStyle == "blizzard" then
        ShowFillMasks(cb)
    end
end

function CooldownCompanion:StartCastBarPreview()
    isPreviewActive = true
    self:ApplyCastBarSettings()
    ApplyPreview()
end

function CooldownCompanion:StopCastBarPreview()
    if not isPreviewActive then return end
    isPreviewActive = false

    local cb = PlayerCastingBarFrame
    if not cb then return end

    -- If not actually casting, hide the bar
    if not (cb.casting or cb.channeling) then
        cb:Hide()
    end
end

function CooldownCompanion:IsCastBarPreviewActive()
    return isPreviewActive
end

------------------------------------------------------------------------
-- Hooks
-- hooksecurefunc on SetLook is safe: SetLook is never called from OnEvent,
-- and the deferred ApplyCastBarSettings uses only C methods (no Lua writes).
-- Hooks on our own addon methods (RefreshGroupFrame, RefreshAllGroups) are
-- always safe since they are not Blizzard secure handlers.
------------------------------------------------------------------------

local function InstallHooks()
    if not hooksInstalled then
        hooksInstalled = true

        -- When SetLook is called by Blizzard (EditMode, PlayerFrame attach/detach),
        -- re-apply our settings after it finishes.
        hooksecurefunc(PlayerCastingBarFrame, "SetLook", function()
            if isApplied then
                C_Timer.After(0, function()
                    local s = GetCastBarSettings()
                    if s and s.enabled then
                        CooldownCompanion:ApplyCastBarSettings()
                    end
                end)
            end
        end)

        -- When anchor group refreshes (visibility changes) — re-evaluate
        hooksecurefunc(CooldownCompanion, "RefreshGroupFrame", function(self, groupId)
            local s = GetCastBarSettings()
            if s and s.enabled and s.anchorGroupId == groupId then
                C_Timer.After(0, function()
                    CooldownCompanion:EvaluateCastBar()
                end)
            end
        end)

        -- When all groups refresh (profile switch, zone change) — re-evaluate
        hooksecurefunc(CooldownCompanion, "RefreshAllGroups", function()
            C_Timer.After(0.1, function()
                CooldownCompanion:EvaluateCastBar()
            end)
        end)
    end
end

------------------------------------------------------------------------
-- Initialization
------------------------------------------------------------------------

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function(self, event)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")

    -- Delay to ensure group frames are created first
    C_Timer.After(0.5, function()
        InstallHooks()
        CooldownCompanion:EvaluateCastBar()
    end)
end)
