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
    pixelBorders.TOP:SetHeight(1)
    pixelBorders.TOP:SetPoint("TOPLEFT", cb, "TOPLEFT", 0, 1)
    pixelBorders.TOP:SetPoint("TOPRIGHT", cb, "TOPRIGHT", 0, 1)

    pixelBorders.BOTTOM:SetHeight(1)
    pixelBorders.BOTTOM:SetPoint("BOTTOMLEFT", cb, "BOTTOMLEFT", 0, -1)
    pixelBorders.BOTTOM:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", 0, -1)

    pixelBorders.LEFT:SetWidth(1)
    pixelBorders.LEFT:SetPoint("TOPLEFT", cb, "TOPLEFT", -1, 1)
    pixelBorders.LEFT:SetPoint("BOTTOMLEFT", cb, "BOTTOMLEFT", -1, -1)

    pixelBorders.RIGHT:SetWidth(1)
    pixelBorders.RIGHT:SetPoint("TOPRIGHT", cb, "TOPRIGHT", 1, 1)
    pixelBorders.RIGHT:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", 1, -1)

    return pixelBorders
end

local function ShowPixelBorders(cb, color)
    local borders = GetPixelBorders(cb)
    local r, g, b, a = color[1], color[2], color[3], color[4]
    for _, tex in pairs(borders) do
        tex:SetColorTexture(r, g, b, a)
        tex:Show()
    end
end

local function HidePixelBorders()
    if not pixelBorders then return end
    for _, tex in pairs(pixelBorders) do
        tex:Hide()
    end
end

------------------------------------------------------------------------
-- Position helper (used by both Apply and DeferredReapply)
------------------------------------------------------------------------

local function ApplyPosition(cb, s)
    local groupFrame = GetAnchorGroupFrame(s)
    if not groupFrame then return end

    -- Remove from managed layout (OnShow re-adds on each cast via AddManagedFrame)
    UIParentBottomManagedFrameContainer:RemoveManagedFrame(cb)

    cb:ClearAllPoints()
    local yOfs = s.yOffset or -2
    if s.position == "above" then
        cb:SetPoint("BOTTOMLEFT", groupFrame, "TOPLEFT", 0, -yOfs)
        cb:SetPoint("BOTTOMRIGHT", groupFrame, "TOPRIGHT", 0, -yOfs)
    else
        cb:SetPoint("TOPLEFT", groupFrame, "BOTTOMLEFT", 0, yOfs)
        cb:SetPoint("TOPRIGHT", groupFrame, "BOTTOMRIGHT", 0, yOfs)
    end

    cb:SetHeight(s.height or 14)
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

    -- Re-position (OnShow's AddManagedFrame may have repositioned us)
    ApplyPosition(cb, s)

    -- Re-apply custom bar texture (Blizzard resets to atlas on each cast event)
    if s.barTexture and s.barTexture ~= "" then
        cb:SetStatusBarTexture(s.barTexture)
    end

    -- Re-apply custom bar color
    local bc = s.barColor
    if bc then
        cb:SetStatusBarColor(bc[1], bc[2], bc[3], bc[4])
    end

    -- Re-apply icon visibility (Blizzard's UpdateIconShown reads self.showIcon
    -- during OnEvent — we never touch showIcon, so re-set via C method on child)
    if cb.Icon then
        cb.Icon:SetShown(s.showIcon or false)
    end

    -- Re-apply cast time text visibility (we never touch showCastTimeSetting)
    if cb.CastTimeText then
        if s.showCastTimeText then
            cb.CastTimeText:SetShown(cb.casting or cb.channeling or false)
        else
            cb.CastTimeText:Hide()
        end
    end

    -- Re-hide spark if user wants it hidden
    if not s.showSpark and cb.Spark then
        cb.Spark:Hide()
    end

    -- Re-hide TextBorder
    if cb.TextBorder then
        cb.TextBorder:Hide()
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
    castEventFrame:Show()
end

local function DisableCastEventFrame()
    if not castEventFrame then return end
    castEventFrame:UnregisterAllEvents()
    castEventFrame:Hide()
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

    -- Clear our anchor and let the managed frame system take over
    cb:ClearAllPoints()
    UIParentBottomManagedFrameContainer:AddManagedFrame(cb)

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

    -- Hide pixel borders
    HidePixelBorders()

    -- Restore spark visibility
    if cb.Spark then
        cb.Spark:Show()
    end

    -- Restore icon (CLASSIC hides it)
    if cb.Icon then
        cb.Icon:Hide()
    end

    -- Restore text to CLASSIC defaults
    if cb.Text then
        cb.Text:Show()
        cb.Text:ClearAllPoints()
        cb.Text:SetWidth(185)
        cb.Text:SetHeight(16)
        cb.Text:SetPoint("TOP", 0, -10)
        cb.Text:SetFontObject("GameFontHighlightSmall")
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

    -- Position via two-point anchoring
    ApplyPosition(cb, settings)

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

    -- Icon visibility — C method on CHILD, not SetIconShown()
    -- (SetIconShown writes self.showIcon which taints OnEvent via UpdateIconShown)
    if cb.Icon then
        cb.Icon:SetShown(settings.showIcon or false)
    end

    -- Spark visibility (C method on child — safe)
    if not settings.showSpark and cb.Spark then
        cb.Spark:Hide()
    end

    -- Border style
    local borderStyle = settings.borderStyle or "blizzard"
    if borderStyle == "blizzard" then
        HidePixelBorders()
        if cb.Border then
            cb.Border:SetAtlas("ui-castingbar-frame")
            cb.Border:Show()
        end
    elseif borderStyle == "pixel" then
        if cb.Border then
            cb.Border:Hide()
        end
        ShowPixelBorders(cb, settings.borderColor or { 0, 0, 0, 1 })
    elseif borderStyle == "none" then
        HidePixelBorders()
        if cb.Border then
            cb.Border:Hide()
        end
    end

    -- Hide TextBorder (C method — safe)
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
    -- (showCastTimeSetting is read by UpdateCastTimeTextShown in OnEvent context)
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
            -- Show if currently casting
            cb.CastTimeText:SetShown(cb.casting or cb.channeling or false)
        else
            cb.CastTimeText:Hide()
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
