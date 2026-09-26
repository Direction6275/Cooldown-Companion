--[[
    CooldownCompanion - CastBar
    CC draws its own player cast bar and suppresses Blizzard's while the feature
    is enabled.  The CC bar is used in both stack-attached and independent modes.

    WHY A CC-OWNED FRAME (12.1): the resource stack gained a Blizzard-side
    collapsing aura block container, and PlayerCastingBarFrame can never anchor
    to it — SetPoint fails with "Anchoring disallowed as dependent object would
    inherit forbidden aspects: UntrustedLayoutScriptExecution".  Only a frame
    created with DisableUntrustedLayoutScriptsTemplate may depend on an aspected
    anchor, and the aspect cannot be added to a Blizzard frame from addon code.

    FRAME RULES — every FRAME in the cast bar subtree, and every frame anchored
    to it, is created with DisableUntrustedLayoutScriptsTemplate.  Textures and
    font strings are regions, not frames, and need nothing.  The aspect disables
    layout scripts: no OnSizeChanged or other layout script anywhere in the
    subtree, and POSITION is never read back from the bar or its children
    (GetCenter/GetLeft/GetTop/GetPoint/GetRect).  Sizes CC sets itself may be
    read back, which is why the bar always gets an explicit width.

    TAINT RULES — PlayerCastingBarFrame still has secure OnEvent handlers that
    access CastingBarTypeInfo (keyed by secretwrap values), so suppression and
    restore touch it with C-level widget methods only.

    FORBIDDEN (causes taint):
      - Writing ANY Lua property to PlayerCastingBarFrame from addon code.
      - Calling mixin methods that write Lua properties internally: SetUnit,
        SetLook, SetIconShown, SetAndUpdateShowCastbar.

    SAFE:
      - C-level widget methods (UnregisterAllEvents, RegisterUnitEvent, Hide,
        SetPoint, SetParent, ...) — no Lua table entries written.
      - Methods on the managed-layout CONTAINER (cb.layoutParent).

    The player's own cast data is plain for addons: UnitCastingInfo,
    UnitChannelInfo, GetUnitEmpowerStageDuration, GetUnitEmpowerHoldAtMaxTime and
    the UNIT_SPELLCAST_* events are annotated SecretWhenUnitSpellCastRestricted,
    which is secret only for units other than the player and their pet.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local RB = ST._RB
local CastBarVisuals = ST._CastBarVisuals

local isApplied = false
local hooksInstalled = false
local castEventFrame = nil
local castEventFrameEnabled = false
local blizzardSuppressed = false
local blizzardSuppressionYielded = false
-- Two different things, deliberately separate (owner ruling 2026-07-26).
-- The unlock assist paints the real bar so an independent cast bar can be
-- positioned; the command-center preview is a config-canvas state and never
-- touches the world.
local isUnlockAssistActive = false
-- Blizzard's talent UI replaces the player cast bar with its ApplyingTalents
-- overlay. CC yields only to that overlay; other contextual overlays stay
-- hidden while CC owns the player cast bar.
local overlayReplacingPlayerBar = false
local nonTalentOverlayHiddenByCC = false
local independentMoverFrame = nil
local InstallHooks
local UpdateIndependentCastBarDragState
local ApplyCastBarUnlockPreview

function CooldownCompanion:GetIndependentCastBarSnapFrame()
    return independentMoverFrame
end

function CooldownCompanion:GetIndependentCastBarMoverChrome()
    local frame = independentMoverFrame
    return frame and frame._dragHandle, frame and frame._coordLabel, frame and frame._nudger,
        frame and frame._resizeGrip, frame and frame._sizeLabel
end

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local function GetCastBarSettings()
    return CooldownCompanion:GetCastBarSettings()
end

local function ShouldOwnBlizzardCastBar()
    local settings = GetCastBarSettings()
    return not CooldownCompanion._unsupportedLegacyProfile
        and type(settings) == "table"
        and settings.enabled == true
end

function CooldownCompanion:SetIndependentCastBarLocked(locked)
    local settings = GetCastBarSettings()
    if not settings then return end
    settings.independentAnchorLocked = locked == true
    self:ApplyCastBarSettings()
    if self.RefreshUnlockToolbar then
        self:RefreshUnlockToolbar()
    end
end

local function GetEffectiveAnchorGroupId(settings)
    if not settings then return nil end
    return CooldownCompanion:GetModuleAnchorPanelId("castbar")
end

local function GetAnchorGroupFrame(settings)
    local groupId = GetEffectiveAnchorGroupId(settings)
    if not groupId then return nil end
    return CooldownCompanion.groupFrames[groupId]
end

local function GetAttachedCastBarPanelYOffset(settings)
    if not settings or CooldownCompanion:IsModuleAnchorIndependent("castbar") then
        return 0
    end
    return ST.GetCastBarAttachmentOffset(settings, CooldownCompanion:GetSpecLayoutOrder())
end

------------------------------------------------------------------------
-- Independent Cast Bar Anchor (proxy mover frame to avoid Blizzard taint)
------------------------------------------------------------------------

local CAST_NUDGE_BTN_SIZE = RB.INDEPENDENT_NUDGE_BTN_SIZE
local ClampCastBarDimension = function(value, fallback) return RB.ClampIndependentDimension(value, fallback, 20) end
local RoundToTenths = RB.RoundToTenths
local GetAnchorOffset = RB.GetAnchorOffset

local function UpdateIndependentCastBarCoordLabel(frame, x, y)
    if frame and frame._coordLabel then
        frame._coordLabel.text:SetText(("x:%.1f, y:%.1f"):format(x or 0, y or 0))
    end
end

local CancelCoordinateEdit = ST.CancelCoordinateEdit
local CreateEditableCoordLabel = ST.CreateEditableCoordLabel

local function ComputeIndependentCastBarCoordinates(frame, anchor)
    local cx, cy = frame:GetCenter()
    local fw, fh = frame:GetSize()
    local relFrame = UIParent
    if anchor.relativeTo and anchor.relativeTo ~= "UIParent" then
        relFrame = CooldownCompanion:GetExternalAnchorFrame(anchor.relativeTo)
    end
    local tcx, tcy = relFrame:GetCenter()
    local tw, th = relFrame:GetSize()
    if not (cx and cy and fw and fh and tcx and tcy and tw and th) then return nil, nil end

    local fax, fay = GetAnchorOffset(anchor.point, fw, fh)
    local tax, tay = GetAnchorOffset(anchor.relativePoint, tw, th)
    return RoundToTenths((cx + fax) - (tcx + tax)), RoundToTenths((cy + fay) - (tcy + tay))
end

local function StopIndependentCastBarCoordUpdates(frame)
    frame._coordDragElapsed = nil
    frame._coordDragAnchor = nil
    frame:SetScript("OnUpdate", nil)
    if CooldownCompanion.EndDragSnapSession then
        CooldownCompanion:EndDragSnapSession(frame, false)
    end
end

local function IndependentCastBarCoordOnUpdate(self, elapsed)
    if not self._dragInProgress then
        StopIndependentCastBarCoordUpdates(self)
        return
    end

    self._coordDragElapsed = (self._coordDragElapsed or 0) + elapsed
    if self._coordDragElapsed < 0.05 then
        return
    end

    self._coordDragElapsed = 0
    local anchor = self._coordDragAnchor
    if anchor then
        local x, y = ComputeIndependentCastBarCoordinates(self, anchor)
        if x ~= nil and y ~= nil then
            UpdateIndependentCastBarCoordLabel(self, x, y)
        end
    end
    CooldownCompanion:UpdateDragSnapSession(self)
end

local function StartIndependentCastBarCoordUpdates(frame, anchor)
    frame._coordDragElapsed = 0
    frame._coordDragAnchor = anchor
    frame:SetScript("OnUpdate", IndependentCastBarCoordOnUpdate)
end

function CooldownCompanion:CancelIndependentCastBarDrag()
    local frame = independentMoverFrame
    if not frame then return end
    if frame._dragInProgress then
        frame._dragCancelPending = true
        frame:StopMovingOrSizing()
        frame._dragInProgress = nil
        StopIndependentCastBarCoordUpdates(frame)
        self:EndMoverChromeFade(frame)
    end
    UpdateIndependentCastBarDragState(GetCastBarSettings())
end

local function EnsureIndependentCastBarConfig(settings)
    if type(settings.independentAnchor) ~= "table" then
        settings.independentAnchor = {}
    end
    local anchor = settings.independentAnchor
    anchor.point = anchor.point or "CENTER"
    anchor.relativePoint = anchor.relativePoint or "CENTER"
    anchor.x = tonumber(anchor.x) or 0
    anchor.y = tonumber(anchor.y) or 0
    if anchor.relativeTo ~= nil and type(anchor.relativeTo) ~= "string" then
        anchor.relativeTo = nil
    end
    settings.independentWidth = ClampCastBarDimension(settings.independentWidth, 200)
end

local IsBarsConfigActive = RB.IsBarsConfigActive

local function SaveIndependentCastBarAnchor(refreshConfig)
    if not independentMoverFrame then return end
    local settings = GetCastBarSettings()
    if not settings then return end
    EnsureIndependentCastBarConfig(settings)

    local frame = independentMoverFrame
    local anchor = settings.independentAnchor

    local x, y = ComputeIndependentCastBarCoordinates(frame, anchor)
    if x == nil or y == nil then return end
    anchor.x = x
    anchor.y = y
    UpdateIndependentCastBarCoordLabel(frame, x, y)

    if refreshConfig and IsBarsConfigActive() and CooldownCompanion.RefreshConfigPanel then
        CooldownCompanion:RefreshConfigPanel()
    end
end

local function ApplyIndependentCastBarCoordinates(frame, x, y)
    local settings = GetCastBarSettings()
    if not settings then return end
    EnsureIndependentCastBarConfig(settings)

    local anchor = settings.independentAnchor
    anchor.x = x
    anchor.y = y
    local relFrame = UIParent
    if anchor.relativeTo and anchor.relativeTo ~= "UIParent" then
        relFrame = CooldownCompanion:GetExternalAnchorFrame(anchor.relativeTo)
    end
    frame:ClearAllPoints()
    frame:SetPoint(anchor.point, relFrame, anchor.relativePoint, x, y)
    UpdateIndependentCastBarCoordLabel(frame, x, y)
    SaveIndependentCastBarAnchor(true)
end

function ST.LockIndependentCastBarFromMover(frame)
    frame = frame or independentMoverFrame
    if not frame then return end
    local settings = GetCastBarSettings()
    if not settings then return end
    -- Locking the soloed mover would strand every other mover solo-hidden;
    -- release the solo first (mirrors SetContainerLocked).
    if CooldownCompanion._arrangeSoloContainerId == "cast"
        and CooldownCompanion.SetArrangeSoloContainer then
        CooldownCompanion:SetArrangeSoloContainer(nil)
    end
    settings.independentAnchorLocked = true
    frame._dragInProgress = nil
    StopIndependentCastBarCoordUpdates(frame)
    frame:StopMovingOrSizing()
    SaveIndependentCastBarAnchor(true)
    CooldownCompanion:EndMoverChromeFade(frame)
    UpdateIndependentCastBarDragState(settings)
    CooldownCompanion:CaptureArrangeCastBarRecord()
    if CooldownCompanion.RefreshUnlockToolbar then
        CooldownCompanion:RefreshUnlockToolbar()
    end
    CooldownCompanion:CheckArrangeModeAutoExit()
end

local function CreateCastBarMoverFrame()
    if independentMoverFrame then return end

    local frame = CreateFrame("Frame", "CooldownCompanionCastBarMover", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("HIGH")
    frame:SetSize(200, 15)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)

    independentMoverFrame = frame
end

local function EnsureCastBarMoverChrome(frame)
    if frame._dragHandle or InCombatLockdown() or CooldownCompanion._combatForcedLock then return end
    -- Drag handle (full-width, two-point anchored to mover frame)
    local dragHandle = ST.MoverChrome.CreateHeader(frame, "Cast Bar", function()
        ST.LockIndependentCastBarFromMover(frame)
    end, function() return { kind = "cast", focusId = "cast" } end)
    dragHandle:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2)
    dragHandle:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 2)
    dragHandle:EnableMouse(false)
    dragHandle:RegisterForDrag()

    -- Hovering the name bar reveals precise controls. Selection belongs to
    -- the unlock toolbar; the title bar remains a drag/menu/lock surface.
    dragHandle:SetScript("OnEnter", function()
        ST.BeginMoverChromeHoverReveal(frame, function()
            CooldownCompanion:RefreshIndependentCastBarMoverChrome()
        end)
    end)
    dragHandle:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            frame._focusClickSuppressed = nil
        end
    end)

    -- Nudger (4-direction pixel nudge, matches icon panel pattern)
    local nudger = ST.MoverChrome.CreateNudger(dragHandle, CAST_NUDGE_BTN_SIZE, function(dx, dy)
        CancelCoordinateEdit(frame._coordLabel)
        CancelCoordinateEdit(frame._sizeLabel)
        local settings = GetCastBarSettings()
        if not settings or settings.independentAnchorLocked then return end
        frame:AdjustPointsOffset(dx, dy)
        -- Write position per step and update coord label (GroupFrame pattern)
        local _, _, _, x, y = frame:GetPoint()
        if x and y then
            EnsureIndependentCastBarConfig(settings)
            settings.independentAnchor.x = RoundToTenths(x)
            settings.independentAnchor.y = RoundToTenths(y)
            UpdateIndependentCastBarCoordLabel(frame, x, y)
        end
    end, function() SaveIndependentCastBarAnchor(true) end)
    nudger:EnableMouse(false)

    -- Coordinate label (parented to mover frame, below bar content)
    local coordLabel = ST.MoverChrome.CreateLabel(frame)
    coordLabel:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -2)
    coordLabel:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -2)
    CreateEditableCoordLabel(
        coordLabel,
        function()
            local settings = GetCastBarSettings()
            local anchor = settings and settings.independentAnchor
            return anchor and anchor.x or 0, anchor and anchor.y or 0
        end,
        function(x, y)
            ApplyIndependentCastBarCoordinates(frame, x, y)
        end,
        function()
            return frame._dragInProgress == true
                or (frame._resizeGrip and frame._resizeGrip._resizeActive == true)
        end
    )

    -- Width resize chrome (grip + wheel + typed label). Width is read from
    -- and written to settings.independentWidth only; the bar frame itself is
    -- never measured (see the FRAME RULES header).
    ST.AttachMoverWidthResize(frame, {
        dragHandle = dragHandle,
        coordLabel = coordLabel,
        getWidth = function()
            local settings = GetCastBarSettings()
            return settings and settings.independentWidth or 200
        end,
        setWidth = function(width)
            local settings = GetCastBarSettings()
            if settings then
                settings.independentWidth = width
            end
        end,
        -- The shared height key: it also drives the attached form, exactly as
        -- the config Height slider does.
        getHeight = function()
            local settings = GetCastBarSettings()
            return ST.ResolveCastBarGeometry(settings).thickness
        end,
        setHeight = function(height)
            local settings = GetCastBarSettings()
            if settings then
                if settings.overrideSections and settings.overrideSections.barThickness then settings.styleOverrides.barHeight = height
                else settings.height = height end
            end
        end,
        apply = function()
            CooldownCompanion:ApplyCastBarSettings()
        end,
        isUnlocked = function()
            local settings = GetCastBarSettings()
            return settings ~= nil
                and CooldownCompanion:IsModuleAnchorIndependent("castbar")
                and not settings.independentAnchorLocked
                and not CooldownCompanion._combatForcedLock
        end,
        getAnchorPoint = function()
            local settings = GetCastBarSettings()
            local anchor = settings and settings.independentAnchor
            return anchor and anchor.point or "CENTER"
        end,
    })

    -- Drag scripts
    dragHandle:RegisterForDrag("LeftButton")
    dragHandle:SetScript("OnDragStart", function()
        CancelCoordinateEdit(coordLabel)
        CancelCoordinateEdit(frame._sizeLabel)
        local settings = GetCastBarSettings()
        if not settings or settings.independentAnchorLocked then return end
        if InCombatLockdown() then return end
        -- Dragging solos this mover, mirroring container header drags.
        if CooldownCompanion._arrangeModeActive and CooldownCompanion.SetArrangeSoloContainer then
            frame._focusClickSuppressed = true
            CooldownCompanion:SetArrangeSoloContainer("cast")
        end
        frame._dragCancelPending = nil
        frame._dragInProgress = true
        frame:StartMoving()
        CooldownCompanion:BeginMoverChromeFade(frame)
        CooldownCompanion:BeginDragSnapSession(frame, function(candidateFrame)
            return candidateFrame == frame
        end)
        StartIndependentCastBarCoordUpdates(frame, settings.independentAnchor)
    end)
    dragHandle:SetScript("OnDragStop", function()
        -- The release that ends this drag also fires OnMouseUp; it must not
        -- read as a focus-toggling click.
        frame._focusClickSuppressed = true
        local cancelSave = frame._dragCancelPending == true or CooldownCompanion._combatForcedLock
        frame._dragCancelPending = nil
        frame._dragInProgress = nil
        frame:StopMovingOrSizing()
        if not cancelSave then
            CooldownCompanion:UpdateDragSnapSession(frame)
        end
        local snapDX, snapDY = CooldownCompanion:EndDragSnapSession(frame, not cancelSave)
        if snapDX ~= nil or snapDY ~= nil then
            frame:AdjustPointsOffset(snapDX or 0, snapDY or 0)
        end
        StopIndependentCastBarCoordUpdates(frame)
        if cancelSave then
            CooldownCompanion:EndMoverChromeFade(frame)
            return
        end
        SaveIndependentCastBarAnchor(true)
        CooldownCompanion:EndMoverChromeFade(frame)
    end)

    frame._dragHandle = dragHandle
    frame._nudger = nudger
    frame._coordLabel = coordLabel
    local settings = GetCastBarSettings()
    local anchor = settings and settings.independentAnchor
    UpdateIndependentCastBarCoordLabel(frame, anchor and anchor.x, anchor and anchor.y)
    CooldownCompanion:ApplyMoverChromeFadeToFrames(dragHandle, coordLabel, nudger, frame._resizeGrip, frame._sizeLabel)
end

UpdateIndependentCastBarDragState = function(settings)
    if not independentMoverFrame then return end
    local frame = independentMoverFrame
    local unlocked = settings
        and CooldownCompanion:IsModuleAnchorIndependent("castbar")
        and not settings.independentAnchorLocked
        and not CooldownCompanion._combatForcedLock
        and not InCombatLockdown()
    if not unlocked and frame._dragInProgress then
        CooldownCompanion:CancelIndependentCastBarDrag()
    end

    if unlocked and not CooldownCompanion:IsContainerArrangeChromeHidden("cast") then
        EnsureCastBarMoverChrome(frame)
    end
    ST.MoverChrome.UpdateIndependent(frame, "cast", unlocked)

    -- Show a stand-in cast while unlocked so the bar is visible for
    -- positioning. Unlike a resource bar, a cast bar that is not casting has
    -- nothing of its own to show, so this one has to invent its contents —
    -- and an independent cast bar is positioned out in the world, with no
    -- config-canvas mirror to drag instead.
    if unlocked and not isUnlockAssistActive then
        CooldownCompanion:StartCastBarUnlockAssist()
        frame._cdcUnlockAssist = true
    elseif not unlocked and frame._cdcUnlockAssist then
        frame._cdcUnlockAssist = false
        CooldownCompanion:StopCastBarUnlockAssist()
    end
end

-- Re-present the mover chrome from current settings; the toolbar's
-- chrome-hide and solo controls call this when their session state flips.
function CooldownCompanion:RefreshIndependentCastBarMoverChrome()
    UpdateIndependentCastBarDragState(GetCastBarSettings())
end

local function HideIndependentCastBarMover()
    if not independentMoverFrame then return end
    CooldownCompanion:CancelIndependentCastBarDrag()
    independentMoverFrame._dragInProgress = nil
    StopIndependentCastBarCoordUpdates(independentMoverFrame)
    independentMoverFrame:Hide()
    if independentMoverFrame._dragHandle then
        independentMoverFrame._dragHandle:Hide()
    end
    if independentMoverFrame._nudger then
        independentMoverFrame._nudger:Hide()
    end
    if independentMoverFrame._coordLabel then
        independentMoverFrame._coordLabel:Hide()
    end
    if independentMoverFrame._sizeLabel then
        independentMoverFrame._sizeLabel:Hide()
    end
    if independentMoverFrame._cdcUnlockAssist then
        independentMoverFrame._cdcUnlockAssist = false
        CooldownCompanion:StopCastBarUnlockAssist()
    end
end

------------------------------------------------------------------------
-- CC-owned cast bar frame
--
-- Structure (every FRAME carries the forbidden-aspect template so the bar may
-- anchor to the aspected aura block container):
--
--   castBarFrame   root; CC anchors and sizes it, and it never moves itself
--     content      shake target; the root stays put so the anchor survives
--       fill       StatusBar covering the bar area (footprint minus inline icon)
--       textLayer  name / cast time above the fill
--
-- Widths are always set explicitly: a two-point anchor across the block
-- container would make the width secret, and position is never read back.
------------------------------------------------------------------------

local CAST_FRAME_TEMPLATE = "DisableUntrustedLayoutScriptsTemplate"

-- FX timings mirror Blizzard's animation groups (CastingBarFrame.xml).
local FLASH_IN, FLASH_OUT = 0.2, 0.3
local INTERRUPT_GLOW_DURATION = 1.0
local FADE_HOLD_FINISH = 0.2
local FADE_HOLD_INTERRUPT = 1.0
local FADE_DURATION = 0.3
local SHAKE_STEP = 0.05
local SHAKE_OFFSETS = {
    { -1, 1 }, { 1, -2 }, { 1, 2 }, { -1, -1 },
}

-- WoW exposes the player's channel window, but not the moments when a
-- channel actually deals damage or healing. Keep that missing cadence as a
-- small, audited registry and project it onto the real UnitChannelInfo window
-- so haste and pushback still move the marks with the cast.
--
-- END_TICKS: every event is one interval apart and the last event is at the
-- channel end. START_END: the first event is immediate and the last is at the
-- channel end (missile-style channels). Only interior events need marks.
local CHANNEL_END_TICKS = 1
local CHANNEL_START_END_TICKS = 2
local CHANNEL_TICK_DATA = {
    -- Evoker
    [356995] = { mode = CHANNEL_START_END_TICKS, count = 4, chainMode = "interval", modifiers = { { 1219723, 1 } } }, -- Disintegrate; Azure Celerity
    [370960] = { mode = CHANNEL_END_TICKS, count = 5 }, -- Emerald Communion

    -- Priest
    [15407] = { mode = CHANNEL_END_TICKS, count = 6 }, -- Mind Flay
    [391403] = { mode = CHANNEL_END_TICKS, count = 4 }, -- Mind Flay: Insanity
    [64843] = { mode = CHANNEL_END_TICKS, count = 4 }, -- Divine Hymn
    [64901] = { mode = CHANNEL_END_TICKS, count = 4 }, -- Symbol of Hope
    [263165] = { mode = CHANNEL_END_TICKS, count = 3 }, -- Void Torrent
    [47540] = { mode = CHANNEL_START_END_TICKS, count = 3, modifiers = { { 193134, 1 } } }, -- Penance; Castigation
    [47757] = { mode = CHANNEL_START_END_TICKS, count = 3, modifiers = { { 193134, 1 } } }, -- Penance (heal)
    [47758] = { mode = CHANNEL_START_END_TICKS, count = 3, modifiers = { { 193134, 1 } } }, -- Penance (damage)
    [400169] = { mode = CHANNEL_START_END_TICKS, count = 3, modifiers = { { 193134, 1 } } }, -- Dark Reprimand
    [373129] = { mode = CHANNEL_START_END_TICKS, count = 3, modifiers = { { 193134, 1 } } }, -- Dark Reprimand (heal)
    [400171] = { mode = CHANNEL_START_END_TICKS, count = 3, modifiers = { { 193134, 1 } } }, -- Dark Reprimand (damage)

    -- Mage
    [5143] = { mode = CHANNEL_START_END_TICKS, count = 5, chainMode = "missiles", modifiers = { { 236628, 2 }, { 1296581, 1 } } }, -- Arcane Missiles; Amplification / current set bonus
    [12051] = { mode = CHANNEL_END_TICKS, count = 6 }, -- Evocation
    [198100] = { mode = CHANNEL_END_TICKS, count = 8 }, -- Kleptomania
    [382440] = { mode = CHANNEL_END_TICKS, count = 4 }, -- Shifting Power

    -- Hunter
    [257044] = { mode = CHANNEL_START_END_TICKS, count = 7, modifiers = { { 459794, 3 } } }, -- Rapid Fire; Quick Draw

    -- Demon Hunter
    [198013] = { mode = CHANNEL_END_TICKS, count = 10 }, -- Eye Beam
    [473728] = { mode = CHANNEL_END_TICKS, count = 20 }, -- Void Ray
    [212084] = { mode = CHANNEL_END_TICKS, count = 10 }, -- Fel Devastation
    [452486] = { mode = CHANNEL_END_TICKS, count = 10 }, -- Fel Desolation

    -- Warlock
    [198590] = { mode = CHANNEL_END_TICKS, count = 5 }, -- Drain Soul
    [755] = { mode = CHANNEL_END_TICKS, count = 5 }, -- Health Funnel
    [217979] = { mode = CHANNEL_END_TICKS, count = 5 }, -- Health Funnel replacement
    [234153] = { mode = CHANNEL_END_TICKS, count = 5 }, -- Drain Life
    [196447] = { mode = CHANNEL_END_TICKS, count = 15 }, -- Channel Demonfire
    [417537] = { mode = CHANNEL_END_TICKS, count = 3 }, -- Oblivion

    -- Other classes / racials
    [740] = { mode = CHANNEL_END_TICKS, count = 6 }, -- Tranquility
    [206931] = { mode = CHANNEL_END_TICKS, count = 3 }, -- Blooddrinker
    [115175] = { mode = CHANNEL_END_TICKS, count = 8 }, -- Soothing Mist
    [117952] = { mode = CHANNEL_END_TICKS, count = 4 }, -- Crackling Jade Lightning
    [443028] = { mode = CHANNEL_END_TICKS, count = 4 }, -- Celestial Conduit
    [291944] = { mode = CHANNEL_END_TICKS, count = 6 }, -- Regeneratin'
}

local function ResolveChannelTickData(spellID)
    local data = CHANNEL_TICK_DATA[spellID]
    if not data then return nil end

    local count = data.count
    if data.modifiers and C_SpellBook and C_SpellBook.IsSpellKnown then
        for _, modifier in ipairs(data.modifiers) do
            if C_SpellBook.IsSpellKnown(modifier[1], Enum.SpellBookSpellBank.Player) then
                count = count + modifier[2]
            end
        end
    end
    return data.mode, count, data.chainMode
end

local castBarFrame = nil

-- Live cast + effect state.  `state` is nil whenever no cast is running; the
-- effect timers keep the driver alive through the finish/interrupt tail.
local cast = {
    state = nil,        -- "cast" | "channel" | "empower"
    startTime = 0,
    endTime = 0,
    castID = nil,
    spellID = nil,
    channelCarry = 0, -- inherited time-to-next-event on a chained channel
    channelTickInterval = nil,
    empowerHold = false, -- endTime carries GetUnitEmpowerHoldAtMaxTime
    numStages = 0,      -- kept so pips can rebuild on pushback or resize
    fadeMode = nil,     -- "finish" | "interrupt"
    fadeElapsed = 0,
    flashElapsed = nil,
    glowElapsed = nil,
    shakeElapsed = nil,
}

local function ResetCastState()
    cast.state = nil
    cast.startTime = 0
    cast.endTime = 0
    cast.castID = nil
    cast.spellID = nil
    cast.channelCarry = 0
    cast.channelTickInterval = nil
    cast.empowerHold = false
    cast.numStages = 0
    cast.fadeMode = nil
    cast.fadeElapsed = 0
    cast.flashElapsed = nil
    cast.glowElapsed = nil
    cast.shakeElapsed = nil
end

--- Disintegrate and Arcane Missiles can be recast before their outgoing
--- channel ends. The replacement fires immediately, then inherits the old
--- event grid; this returns the time to that inherited event plus the new
--- interval. Other channels always return a fresh cadence.
local function ResolveChannelCadenceForStart(spellID, startTime, endTime, castID)
    local mode, eventCount, chainMode = ResolveChannelTickData(spellID)
    if mode ~= CHANNEL_START_END_TICKS or eventCount <= 1 then
        return 0, nil
    end

    local duration = endTime - startTime
    if duration <= 0 then return 0, nil end

    local sameSpellWasRunning = cast.state == "channel" and cast.spellID == spellID
    local sameCast = false
    if sameSpellWasRunning then
        if castID and cast.castID then
            sameCast = castID == cast.castID
        else
            sameCast = (startTime - cast.startTime) < 0.5
        end
    end

    local carry = sameCast and (cast.channelCarry or 0) or 0
    if not sameCast and chainMode and sameSpellWasRunning
        and cast.channelTickInterval and cast.channelTickInterval > 0
        and startTime < cast.endTime - 0.01 then
        carry = math.fmod(cast.endTime - startTime, cast.channelTickInterval)
        if carry < 0.01 then
            carry = 0
        elseif chainMode == "missiles" and carry > cast.channelTickInterval - 0.05 then
            -- Arcane Missiles cast immediately after an outgoing missile has
            -- been observed to lose the bonus missile and uses a fresh grid.
            carry = 0
        end
    end

    if carry >= duration then carry = 0 end

    return carry, (duration - carry) / (eventCount - 1)
end

local function RefreshChannelCadenceInterval()
    local mode, eventCount = ResolveChannelTickData(cast.spellID)
    local duration = cast.endTime - cast.startTime
    if cast.state == "channel" and mode == CHANNEL_START_END_TICKS
        and eventCount > 1 and duration > cast.channelCarry then
        cast.channelTickInterval = (duration - cast.channelCarry) / (eventCount - 1)
    else
        cast.channelTickInterval = nil
    end
end

--- Cache an atlas's design size once so later layout passes can scale from it.
--- Read from the atlas record rather than the region: nothing in the cast bar
--- subtree is measured back out of the frame.
local function EnsureCastBarFrame()
    if castBarFrame then return castBarFrame end

    local frame = CreateFrame("Frame", "CooldownCompanionCastBar", UIParent, CAST_FRAME_TEMPLATE)
    frame:SetFixedFrameStrata(true)
    frame:SetFrameStrata("HIGH")
    frame:SetSize(200, 15)
    frame:EnableMouse(false)
    frame:Hide()

    CastBarVisuals.CreateContents(frame)
    castBarFrame = frame
    return frame
end

------------------------------------------------------------------------
-- Blizzard cast bar suppression
--
-- The event set below is exactly what CastingBarMixin:SetUnit registers, so
-- re-registering it restores the frame without calling SetUnit (which writes
-- Lua properties and would taint the secure OnEvent).
------------------------------------------------------------------------

local BLIZZARD_CAST_UNIT_EVENTS = {
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_EMPOWER_UPDATE",
    "UNIT_SPELLCAST_EMPOWER_STOP",
    "UNIT_SPELLCAST_INTERRUPTIBLE",
    "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_FAILED",
}

local function SuppressBlizzardCastBar()
    -- Blizzard owns the full transition while its ApplyingTalents overlay is
    -- active. Re-evaluations may still run as spec-specific panels settle, but
    -- they must not take player-bar ownership back until the overlay ends.
    if overlayReplacingPlayerBar then return end

    local cb = PlayerCastingBarFrame
    if not cb then return end
    blizzardSuppressed = true
    blizzardSuppressionYielded = false

    -- Re-apply every part of suppression even when CC already owns the bar:
    -- Edit Mode and overlay teardown can show/re-manage it later. This method
    -- is on the CONTAINER, not on the cast bar (we do NOT write
    -- cb.ignoreFramePositionManager — that taints OnEvent).
    if cb.layoutParent then
        cb.layoutParent:RemoveManagedFrame(cb)
    end
    cb:UnregisterAllEvents()
    -- Edit Mode replaces Hide/SetPoint/ClearAllPoints on this frame with Lua
    -- overrides (EditModeSystemMixin:OnSystemLoad) that run edit-mode logic;
    -- calling those from addon code executes Blizzard Lua under addon taint.
    -- The *Base aliases are the preserved C methods.
    local hide = cb.HideBase or cb.Hide
    hide(cb)
end

local function YieldBlizzardCastBarSuppression()
    if not blizzardSuppressed or blizzardSuppressionYielded then return end

    local cb = PlayerCastingBarFrame
    if not cb then return end

    -- StartReplacingPlayerBarAt has already disabled the regular player bar.
    -- Restore only its event registrations here: the Blizzard overlay remains
    -- the visible owner, and CC does not reposition or show the regular bar.
    for _, event in ipairs(BLIZZARD_CAST_UNIT_EVENTS) do
        cb:RegisterUnitEvent(event, "player")
    end
    cb:RegisterEvent("PLAYER_ENTERING_WORLD")
    blizzardSuppressionYielded = true
end

local function RestoreBlizzardCastBar()
    if not blizzardSuppressed then return end
    blizzardSuppressed = false
    blizzardSuppressionYielded = false

    local cb = PlayerCastingBarFrame
    if not cb then return end

    for _, event in ipairs(BLIZZARD_CAST_UNIT_EVENTS) do
        cb:RegisterUnitEvent(event, "player")
    end
    cb:RegisterEvent("PLAYER_ENTERING_WORLD")

    -- The Edit Mode overrides again (see SuppressBlizzardCastBar): every
    -- point/visibility write below goes through the preserved C aliases, and
    -- isInDefaultPosition is a plain field read, never the mixin call.
    local clearAllPoints = cb.ClearAllPointsBase or cb.ClearAllPoints
    local setPoint = cb.SetPointBase or cb.SetPoint
    local hide = cb.HideBase or cb.Hide

    cb:SetAlpha(1)

    -- "Lock To Player Frame": PlayerFrame owns the bar's parent, strata and
    -- anchors (PlayerFrame_AttachCastBar) and ignoreFramePositionManager is
    -- set, so the writes below would detach it from its owner for the rest
    -- of the session. Leave the whole arrangement alone.
    if not cb.attachedToPlayerFrame then
        cb:SetParent(UIParent)
        cb:SetFixedFrameStrata(true)
        cb:SetFrameStrata("HIGH")

        -- Restore the EditMode position for a custom placement. The managed
        -- default position is NOT re-added here: AddManagedFrame early-exits
        -- on a hidden frame, and ManagedFrameMixin.OnShow re-adds the bar on
        -- its next cast anyway.
        clearAllPoints(cb)
        if cb.systemInfo and cb.systemInfo.anchorInfo
            and cb.systemInfo.isInDefaultPosition == false then
            local scale = cb:GetScale()
            local ai = cb.systemInfo.anchorInfo
            setPoint(cb, ai.point, ai.relativeTo, ai.relativePoint,
                     ai.offsetX / scale, ai.offsetY / scale)
            if cb.systemInfo.anchorInfo2 then
                local ai2 = cb.systemInfo.anchorInfo2
                setPoint(cb, ai2.point, ai2.relativeTo, ai2.relativePoint,
                         ai2.offsetX / scale, ai2.offsetY / scale)
            end
        end
    end

    -- Blizzard's frame shows itself again on the next cast START; its cached
    -- casting state is refreshed by that event and by PLAYER_ENTERING_WORLD.
    hide(cb)
end

local function RestoreBlizzardOverlayCastBar()
    if not nonTalentOverlayHiddenByCC then return end
    nonTalentOverlayHiddenByCC = false

    local overlayBar = OverlayPlayerCastingBarFrame
    if not overlayBar or overlayBar:IsShown() then return end

    -- CC only hides this frame after Blizzard shows it for an active cast.
    -- If that cast is still running when the feature is disabled, reveal the
    -- existing overlay with the preserved C method. Future casts need no
    -- intervention: the persistent OnShow hook stops hiding them once CC no
    -- longer owns the player cast bar.
    local castName = UnitCastingInfo("player")
    local channelName = UnitChannelInfo("player")
    if not castName and not channelName then return end

    local show = overlayBar.ShowBase or overlayBar.Show
    show(overlayBar)
end

------------------------------------------------------------------------
-- Geometry
------------------------------------------------------------------------

local function GetCastBarHeight(s)
    return ST.ResolveCastBarGeometry(s, ST.GetModuleGeometryHost("castbar")).thickness
end

local function ResolveCastBarWidth(s)
    if CooldownCompanion:IsModuleAnchorIndependent("castbar") then
        return ClampCastBarDimension(s.independentWidth, 200)
    end
    local groupFrame = GetAnchorGroupFrame(s)
    if not groupFrame then return nil end
    local layout = CooldownCompanion:GetSpecLayoutOrder()
    local slot = layout and layout.castBar or {}
    local lane = RB.ResolveBarLane(CooldownCompanion:ResolveModulePanel("castbar").group, slot.position or "below", slot.anchorRegion)
    local region = (lane == "aboveMain" or lane == "belowMain") and "main" or "outer"
    local group = CooldownCompanion:ResolveModulePanel("castbar").group
    local width = ST.GetPanelAttachmentDimensions(groupFrame, group, region)
    if not width or width <= 0 then return nil end
    return width
end

--- One point per side, taken from the corner the stack pins that side by, and
--- growing the way the stack grows.  Two-point anchoring is never an option:
--- it would make this bar's width secret.  The corner matters as much as the
--- count — the aura block container's extent is secret, so only its mount
--- corner is a deterministic edge to line up with.
local SIDE_ANCHORS = {
    above = { point = "BOTTOMLEFT", relativePoint = "TOPLEFT", dx = 0, dy = 1 },
    below = { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", dx = 0, dy = -1 },
    left = { point = "TOPRIGHT", relativePoint = "TOPLEFT", dx = -1, dy = 0 },
    right = { point = "TOPLEFT", relativePoint = "TOPRIGHT", dx = 1, dy = 0 },
}

local function AnchorBySide(frame, side, relative, spacing, yOffset)
    local anchor = SIDE_ANCHORS[side] or SIDE_ANCHORS.below
    frame:SetPoint(anchor.point, relative, anchor.relativePoint,
        anchor.dx * spacing, anchor.dy * spacing + yOffset)
end

--- Position + size the bar.  Returns false when the anchor is unavailable.
local function ApplyCastBarPosition(s, width, height)
    local frame = castBarFrame
    if not frame then return false end

    frame:ClearAllPoints()
    frame:SetSize(width, height)

    if CooldownCompanion:IsModuleAnchorIndependent("castbar") then
        if not independentMoverFrame then return false end
        frame:SetPoint("TOPLEFT", independentMoverFrame, "TOPLEFT", 0, 0)
        return true
    end

    local groupFrame = GetAnchorGroupFrame(s)
    if not groupFrame then return false end

    local specLayout = CooldownCompanion:GetSpecLayoutOrder()
    local cbLayout = specLayout and specLayout.castBar
    local cbPosition = (cbLayout and cbLayout.position) or "below"
    local rbSettings = CooldownCompanion:GetResourceBarSettings()
    local stackDetached = specLayout and CooldownCompanion:IsResourceBarAnchorIndependent()
    -- The cast bar has no vertical-side concept: its stored position is
    -- always above/below, and the layout preview draws it there in every
    -- orientation. Under a vertical stack the left/right-keyed predecessor
    -- and block lookups simply miss, and the bar anchors to the panel.
    local side = cbPosition
    local lane = RB.ResolveBarLane(CooldownCompanion:ResolveModulePanel("castbar").group, side, cbLayout and cbLayout.anchorRegion)

    local gap = RB.GetResourceAnchorGap(rbSettings or {}, specLayout, "horizontal")
    local barSpacing = specLayout and specLayout.barSpacing
        or (rbSettings and rbSettings.barSpacing)
        or 3.6
    local panelYOffset = GetAttachedCastBarPanelYOffset(s)
    local geometryPanel = ST.GetModuleGeometryPanel("castbar")
    if geometryPanel then
        local geometry = ST.ResolveBarGeometry(geometryPanel)
        gap, barSpacing = geometry.distance, geometry.spacing
    end

    local region = (lane == "aboveMain" or lane == "belowMain") and "main" or "outer"
    local panelTail = ST.GetPanelAttachmentTail and ST.GetPanelAttachmentTail(groupFrame, side, region)
    if panelTail then
        local anchor = side == "above" and "BOTTOM" or "TOP"
        local far = side == "above" and "TOP" or "BOTTOM"
        frame:SetPoint(anchor, panelTail, far, 0,
            (side == "above" and 1 or -1) * barSpacing + panelYOffset)
        return true
    end

    if not stackDetached and CooldownCompanion:ModulesShareAnchorPanel("resources", "castbar") then
        -- The cast bar is ALWAYS the last element of its side (owner ruling
        -- 2026-08-09): the stack reserves no space for an interleaved cast
        -- bar, so a stored order between two bars double-books the next
        -- bar's slot. The stored order is ignored for anchoring.
        local predecessor = CooldownCompanion:GetResourceBarPredecessor(lane, math.huge)
        if predecessor then
            AnchorBySide(frame, side, predecessor, barSpacing, panelYOffset)
            return true
        end
    end

    AnchorBySide(frame, side, RB.GetBarLaneBody(groupFrame, lane), gap, panelYOffset)
    return true
end

--- Position the bar's contents inside the applied footprint.
local function ApplyCastBarLayout(s, width, height)
    CastBarVisuals.Layout(castBarFrame, s, width, height)
end

local function ApplyCastBarStyle(s)
    CastBarVisuals.Style(castBarFrame, s)
end

------------------------------------------------------------------------
-- Rendering
------------------------------------------------------------------------

local function HideStagePips()
    local frame = castBarFrame
    if not frame then return end
    for _, pip in ipairs(frame.stagePips) do
        pip:Hide()
    end
end

--- Empowered casts get one separator per stage boundary.  Stage durations are
--- plain for the player (SecretWhenUnitSpellCastRestricted), and the offsets
--- come from the width CC set itself — the bar's position is never read.
local function BuildStagePips(numStages)
    HideStagePips()
    local frame = castBarFrame
    if not frame or numStages <= 0 then return end

    local total = cast.endTime - cast.startTime
    if total <= 0 then return end
    local stageMaxValue = total * 1000
    local sumDuration = 0
    local shown = 0

    for index = 1, numStages do
        local duration = GetUnitEmpowerStageDuration("player", index - 1)
        if type(duration) == "number" and duration > 0 then
            sumDuration = sumDuration + duration
            local portion = sumDuration / stageMaxValue
            if portion > 0 and portion < 1 then
                shown = shown + 1
                local pip = frame.stagePips[shown]
                if not pip then
                    pip = frame.fill:CreateTexture(nil, "OVERLAY", nil, 1)
                    frame.stagePips[shown] = pip
                end
                local offset = frame.fillWidth * portion
                pip:SetColorTexture(0, 0, 0, 0.85)
                pip:ClearAllPoints()
                pip:SetPoint("TOP", frame.fill, "TOPLEFT", offset, 0)
                pip:SetPoint("BOTTOM", frame.fill, "BOTTOMLEFT", offset, 0)
                pip:SetWidth(1)
                pip:Show()
            end
        end
    end
end

local function HideChannelTickMarks()
    CastBarVisuals.HideChannelTickMarks(castBarFrame)
end

local function BuildChannelTickMarks()
    HideChannelTickMarks()
    local frame = castBarFrame
    local settings = GetCastBarSettings()
    if not frame or cast.state ~= "channel" or not settings
        or settings.showChannelTickMarks ~= true then
        return
    end

    local mode, eventCount = ResolveChannelTickData(cast.spellID)
    if not mode or type(eventCount) ~= "number" then return end

    -- The registry is static data, but cap its output defensively so a bad
    -- future entry cannot manufacture an unbounded region pool.
    eventCount = math.min(math.floor(eventCount), 64)
    local divisor
    local markCount
    local chainedInterval
    if mode == CHANNEL_END_TICKS then
        divisor = eventCount
        markCount = eventCount - 1
    elseif mode == CHANNEL_START_END_TICKS then
        divisor = eventCount - 1
        markCount = eventCount - 2
    end
    if not divisor or divisor <= 0 or not markCount or markCount <= 0 then return end

    local total = cast.endTime - cast.startTime
    if total <= 0 then return end

    -- A chained Disintegrate or Arcane Missiles has one immediate event plus
    -- the inherited outgoing event before settling into the new channel's
    -- remaining grid. That creates exactly one additional interior mark.
    if mode == CHANNEL_START_END_TICKS and cast.channelCarry > 0
        and cast.channelCarry < total then
        chainedInterval = (total - cast.channelCarry) / divisor
        markCount = eventCount - 1
    end

    for index = 1, markCount do
        local elapsedPortion
        if chainedInterval then
            elapsedPortion = (cast.channelCarry + (index - 1) * chainedInterval) / total
        else
            elapsedPortion = index / divisor
        end
        CastBarVisuals.SetChannelTickMark(frame, settings, index, elapsedPortion, index == markCount)
    end
end

local function SetCastFill(pct, showSpark)
    CastBarVisuals.SetFill(castBarFrame, pct, showSpark)
end

local function SetCastTimeText(remaining)
    CastBarVisuals.SetTimeText(castBarFrame, remaining)
end

local function ClearCastBarEffects()
    local frame = castBarFrame
    if not frame then return end
    cast.flashElapsed = nil
    cast.glowElapsed = nil
    cast.shakeElapsed = nil
    frame.flash:SetAlpha(0)
    frame.interruptGlow:SetAlpha(0)
    frame.content:ClearAllPoints()
    frame.content:SetAllPoints(frame)
end

local StartCastBarDriverUpdates
local StopCastBarDriverUpdates

local function HideCastBar()
    ResetCastState()
    HideStagePips()
    HideChannelTickMarks()
    local frame = castBarFrame
    if frame then
        ClearCastBarEffects()
        frame:SetAlpha(1)
        frame:Hide()
    end
    StopCastBarDriverUpdates()
end

local function FinishCast()
    local frame = castBarFrame
    if not frame or not cast.state then return end
    local s = GetCastBarSettings()

    if cast.state ~= "channel" then
        SetCastFill(1, false)
    else
        SetCastFill(0, false)
    end
    SetCastTimeText(0)
    cast.state = nil
    HideStagePips()
    HideChannelTickMarks()

    if s and s.showCastFinishFX ~= false then
        cast.flashElapsed = 0
    end
    cast.fadeMode = "finish"
    cast.fadeElapsed = 0
    StartCastBarDriverUpdates()
end

local function InterruptCast(text)
    local frame = castBarFrame
    if not frame or not frame:IsShown() then return end
    local s = GetCastBarSettings()

    SetCastFill(1, false)
    SetCastTimeText(0)
    cast.state = nil
    HideStagePips()
    HideChannelTickMarks()
    if text and s and s.showNameText ~= false then
        frame.nameText:SetText(text)
    end

    if s and s.showInterruptGlow ~= false then
        cast.glowElapsed = 0
    end
    if s and s.showInterruptShake ~= false then
        cast.shakeElapsed = 0
    end
    cast.fadeMode = "interrupt"
    cast.fadeElapsed = 0
    StartCastBarDriverUpdates()
end

local function CastBarOnUpdate(self, elapsed)
    local frame = castBarFrame
    if not frame then
        StopCastBarDriverUpdates()
        return
    end

    local busy = false

    if cast.state then
        busy = true
        local now = GetTime()
        local total = cast.endTime - cast.startTime
        if total <= 0 then total = 0.001 end
        local remaining = cast.endTime - now
        local pct
        if cast.state == "channel" then
            pct = remaining / total
        else
            pct = (now - cast.startTime) / total
        end
        SetCastFill(pct, true)
        SetCastTimeText(remaining)
        -- Safety only: the STOP event owns the finish, but a cast that
        -- outlives its own end time by a full second is over.
        if remaining < -1 then
            FinishCast()
        end
    end

    if cast.flashElapsed then
        busy = true
        cast.flashElapsed = cast.flashElapsed + elapsed
        local t = cast.flashElapsed
        if t < FLASH_IN then
            frame.flash:SetAlpha(t / FLASH_IN)
        elseif t < FLASH_IN + FLASH_OUT then
            frame.flash:SetAlpha(1 - (t - FLASH_IN) / FLASH_OUT)
        else
            cast.flashElapsed = nil
            frame.flash:SetAlpha(0)
        end
    end

    if cast.glowElapsed then
        busy = true
        cast.glowElapsed = cast.glowElapsed + elapsed
        if cast.glowElapsed < INTERRUPT_GLOW_DURATION then
            frame.interruptGlow:SetAlpha(1 - cast.glowElapsed / INTERRUPT_GLOW_DURATION)
        else
            cast.glowElapsed = nil
            frame.interruptGlow:SetAlpha(0)
        end
    end

    if cast.shakeElapsed then
        busy = true
        cast.shakeElapsed = cast.shakeElapsed + elapsed
        local step = math.floor(cast.shakeElapsed / SHAKE_STEP) + 1
        local offset = SHAKE_OFFSETS[step]
        frame.content:ClearAllPoints()
        if offset then
            frame.content:SetPoint("TOPLEFT", frame, "TOPLEFT", offset[1], offset[2])
            frame.content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", offset[1], offset[2])
        else
            cast.shakeElapsed = nil
            frame.content:SetAllPoints(frame)
        end
    end

    if cast.fadeMode then
        busy = true
        cast.fadeElapsed = cast.fadeElapsed + elapsed
        local hold = cast.fadeMode == "interrupt" and FADE_HOLD_INTERRUPT or FADE_HOLD_FINISH
        if cast.fadeElapsed <= hold then
            frame:SetAlpha(1)
        elseif cast.fadeElapsed < hold + FADE_DURATION then
            frame:SetAlpha(1 - (cast.fadeElapsed - hold) / FADE_DURATION)
        else
            cast.fadeMode = nil
            HideCastBar()
            return
        end
    end

    if not busy then
        StopCastBarDriverUpdates()
    end
end

StartCastBarDriverUpdates = function()
    if not castEventFrame then return end
    castEventFrame:Show()
    castEventFrame:SetScript("OnUpdate", CastBarOnUpdate)
end

StopCastBarDriverUpdates = function()
    if not castEventFrame then return end
    castEventFrame:SetScript("OnUpdate", nil)
    castEventFrame:Hide()
end

------------------------------------------------------------------------
-- Cast events (value math mirrors CastingBarMixin)
------------------------------------------------------------------------

local function ReadCastInfo(kind)
    if kind == "cast" then
        local name, text, texture, startTime, endTime, isTradeSkill, castID, _notInterruptible, spellID =
            UnitCastingInfo("player")
        return name, text, texture, startTime, endTime, isTradeSkill, castID, 0, spellID
    end
    local name, text, texture, startTime, endTime, isTradeSkill, _notInterruptible, spellID, _isEmpowered, numStages, castBarID =
        UnitChannelInfo("player")
    return name, text, texture, startTime, endTime, isTradeSkill, castBarID, tonumber(numStages) or 0, spellID
end

local function BeginCast(kind)
    local s = GetCastBarSettings()
    if not s or not s.enabled or not isApplied then return end
    local frame = castBarFrame
    if not frame then return end

    -- A Blizzard overlay cast bar (crafting, talent commit) owns the player
    -- cast for now; showing it here too would double it.
    if overlayReplacingPlayerBar then
        HideCastBar()
        return
    end

    -- Some game modes disable the player cast bar outright
    -- (Enum.GameRule.PlayerCastBarDisabled); Blizzard's own bar hides under
    -- the same rule, so CC must not draw a replacement there. Checked per
    -- cast so a mid-session mode change is honored without a callback.
    local shouldShowPlayerCastBar = GameRulesUtil and GameRulesUtil.ShouldShowPlayerCastBar
    if shouldShowPlayerCastBar and not shouldShowPlayerCastBar() then
        HideCastBar()
        return
    end

    local name, text, texture, startTime, endTime, _isTradeSkill, castID, numStages, spellID = ReadCastInfo(kind)
    if not name or not startTime or not endTime then
        HideCastBar()
        return
    end

    local isEmpower = kind == "empower" and numStages > 0
    if isEmpower then
        endTime = endTime + GetUnitEmpowerHoldAtMaxTime("player")
    end

    local startTimeSeconds = startTime / 1000
    local endTimeSeconds = endTime / 1000
    local channelCarry, channelTickInterval = 0, nil
    if kind == "channel" then
        channelCarry, channelTickInterval = ResolveChannelCadenceForStart(
            spellID, startTimeSeconds, endTimeSeconds, castID)
    end

    ClearCastBarEffects()
    cast.state = kind
    cast.startTime = startTimeSeconds
    cast.endTime = endTimeSeconds
    cast.castID = castID
    cast.spellID = spellID
    cast.channelCarry = channelCarry
    cast.channelTickInterval = channelTickInterval
    cast.empowerHold = isEmpower
    cast.numStages = isEmpower and numStages or 0
    cast.fadeMode = nil
    cast.fadeElapsed = 0

    if frame.nameText:IsShown() then
        frame.nameText:SetText(text or name or "")
    end
    frame.icon:SetTexture(texture)
    frame:SetAlpha(1)
    frame:Show()

    BuildStagePips(cast.numStages)
    BuildChannelTickMarks()
    CastBarOnUpdate(castEventFrame, 0)
    StartCastBarDriverUpdates()
end

--- UNIT_SPELLCAST_DELAYED / CHANNEL_UPDATE / EMPOWER_UPDATE: pushback and
--- haste changes move the window, so re-read it and keep the same state.
local function UpdateCastTiming(kind)
    if not cast.state then return end
    local name, _text, _texture, startTime, endTime, _isTradeSkill, castID, _numStages, spellID = ReadCastInfo(kind)
    if not name or not startTime or not endTime then
        HideCastBar()
        return
    end
    -- Blizzard's HandleChannelUpdateDelayed drops the hold window here; CC
    -- keeps it so an empower delay does not jump the fill.
    if cast.empowerHold then
        endTime = endTime + GetUnitEmpowerHoldAtMaxTime("player")
    end
    cast.startTime = startTime / 1000
    cast.endTime = endTime / 1000
    if castID ~= nil then cast.castID = castID end
    cast.spellID = spellID
    RefreshChannelCadenceInterval()
    -- Pushback moved the window the pip offsets were computed from.
    if cast.state == "empower" and cast.numStages > 0 then
        BuildStagePips(cast.numStages)
    elseif cast.state == "channel" then
        BuildChannelTickMarks()
    end
end

local function HandleCastEvent(self, event, unit, arg2, _arg3, arg4, arg5)
    -- PLAYER_ENTERING_WORLD carries login flags, not a unit token, so it is
    -- resolved before the unit guard.
    if event == "PLAYER_ENTERING_WORLD" then
        if isUnlockAssistActive then return end
        -- isEmpowered decides the resync kind: an empower resumed as a plain
        -- channel would fill backwards, drop the hold window and lose its
        -- stage pips.
        local channelName, _, _, _, _, _, _, _, channelIsEmpowered = UnitChannelInfo("player")
        if channelName then
            BeginCast(channelIsEmpowered and "empower" or "channel")
        elseif UnitCastingInfo("player") then
            BeginCast("cast")
        else
            HideCastBar()
        end
        return
    end

    if unit ~= "player" then return end

    -- A real cast event supersedes the unlock stand-in — including one that
    -- starts nothing (a FAILED with no cast running), which must also wipe
    -- the fabricated fill instead of stranding it.
    if isUnlockAssistActive then
        CooldownCompanion:StopCastBarUnlockAssist()
    end

    if event == "UNIT_SPELLCAST_START" then
        BeginCast("cast")
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        BeginCast("channel")
    elseif event == "UNIT_SPELLCAST_EMPOWER_START" then
        BeginCast("empower")
    elseif event == "UNIT_SPELLCAST_DELAYED" then
        UpdateCastTiming("cast")
    elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" or event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
        UpdateCastTiming("channel")
    elseif event == "UNIT_SPELLCAST_STOP" then
        if cast.state == "cast" and (cast.castID == nil or arg2 == cast.castID) then
            FinishCast()
        end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if cast.state == "channel" then
            -- A rapidly restarted channel can receive the outgoing channel's
            -- STOP after the replacement START. Preserve the replacement bar
            -- while the live API still reports a player channel.
            if UnitChannelInfo("player") then return end
            if arg4 == nil then
                FinishCast()
            else
                InterruptCast(INTERRUPTED)
            end
        end
    elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        if cast.state == "empower" then
            if arg4 == false then
                -- Never FAILED here: Blizzard reserves that text for the
                -- FAILED event, and releasing an empower before stage one is
                -- normal play, shown as an interrupt-style stop
                -- (HandleInterruptOrSpellFailed keys the text on the event).
                InterruptCast(INTERRUPTED)
            else
                FinishCast()
            end
        end
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        -- Blizzard's guard: an empower interrupts without an id match, an
        -- ordinary cast only when the payload's GUID is the one on the bar
        -- (a failed OTHER attempt must not tear down a running cast).
        -- Channels keep their interruption in CHANNEL_STOP.
        if cast.state == "empower"
            or (cast.state == "cast" and (cast.castID == nil or arg2 == cast.castID)) then
            InterruptCast(INTERRUPTED)
        end
    elseif event == "UNIT_SPELLCAST_FAILED" then
        if cast.state == "cast" and (cast.castID == nil or arg2 == cast.castID) then
            InterruptCast(FAILED)
        end
    end
end

--- Driver frame: owns both the cast events and the casting OnUpdate.
--- Parented to UIParent so OnUpdate can run when it is shown.
local function EnsureCastEventFrame()
    if castEventFrame then return end
    castEventFrame = CreateFrame("Frame", nil, UIParent)
    castEventFrame:SetSize(1, 1)
    castEventFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    castEventFrame:EnableMouse(false)
    castEventFrame:SetScript("OnEvent", HandleCastEvent)
    castEventFrame:Hide()
end

local CC_CAST_UNIT_EVENTS = {
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_EMPOWER_UPDATE",
    "UNIT_SPELLCAST_EMPOWER_STOP",
}

local function EnableCastEventFrame()
    EnsureCastEventFrame()
    if castEventFrameEnabled then return end
    for _, event in ipairs(CC_CAST_UNIT_EVENTS) do
        castEventFrame:RegisterUnitEvent(event, "player")
    end
    castEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    castEventFrameEnabled = true
end

local function DisableCastEventFrame()
    if not castEventFrame then return end
    castEventFrame:UnregisterAllEvents()
    StopCastBarDriverUpdates()
    castEventFrameEnabled = false
end

------------------------------------------------------------------------
-- Teardown: suspend CC's drawable bar separately from releasing ownership
------------------------------------------------------------------------
local function TearDownCastBarDisplay()
    isApplied = false

    HideIndependentCastBarMover()
    DisableCastEventFrame()
    HideCastBar()

    -- End the unlock stand-in if active: it paints THIS bar, so it goes when
    -- the bar does.
    --
    -- The config-canvas preview deliberately does NOT go with live teardown.
    -- It keeps rendering from saved settings through transient frame
    -- availability, the same reason RevertResourceBars leaves canvas state
    -- alone. Ownership sits with
    -- ClearAllConfigPreviews and the command center's enablement check,
    -- which ask whether the cast bar is configured at all rather than whether
    -- it happens to be drawable this instant.
    isUnlockAssistActive = false
end

local function SuspendCastBar()
    TearDownCastBarDisplay()
    SuppressBlizzardCastBar()
end

function CooldownCompanion:RevertCastBar()
    -- A configured module owns Blizzard suppression even when CC's attached
    -- bar is temporarily undrawable. Only a true feature/profile teardown
    -- releases Blizzard's player bar.
    if ShouldOwnBlizzardCastBar() then
        SuspendCastBar()
        return
    end
    if not isApplied and not blizzardSuppressed and not nonTalentOverlayHiddenByCC then return end

    TearDownCastBarDisplay()

    RestoreBlizzardCastBar()
    RestoreBlizzardOverlayCastBar()
end

------------------------------------------------------------------------
-- Apply: build, position and style CC's cast bar
------------------------------------------------------------------------
function CooldownCompanion:ApplyCastBarSettings(opts)
    opts = opts or {}
    if not opts.skipRuntimeGate then
        return self:RefreshBarsAndFramesRuntimeFeature("castBar", "castbar-apply", true)
    end
    if self.RecordBarsAndFramesRuntimeWork then
        self:RecordBarsAndFramesRuntimeWork("castApply")
    end

    local settings = GetCastBarSettings()
    if not settings or not settings.enabled then
        self:RevertCastBar()
        return
    end
    InstallHooks()
    SuppressBlizzardCastBar()

    local isIndependent = CooldownCompanion:IsModuleAnchorIndependent("castbar")

    if isIndependent then
        -- Independent mode: no group needed, set up mover frame
        EnsureIndependentCastBarConfig(settings)
        CreateCastBarMoverFrame()
        local anchor = settings.independentAnchor
        local relFrame = UIParent
        if anchor.relativeTo and anchor.relativeTo ~= "UIParent" then
            relFrame = CooldownCompanion:GetExternalAnchorFrame(anchor.relativeTo)
        end
        independentMoverFrame:ClearAllPoints()
        independentMoverFrame:SetPoint(anchor.point, relFrame, anchor.relativePoint, anchor.x, anchor.y)
        independentMoverFrame:SetSize(settings.independentWidth, GetCastBarHeight(settings))
        independentMoverFrame:Show()
        UpdateIndependentCastBarDragState(settings)
        UpdateIndependentCastBarCoordLabel(independentMoverFrame, anchor.x, anchor.y)
    else
        local groupId = GetEffectiveAnchorGroupId(settings)
        if not groupId then
            SuspendCastBar()
            return
        end

        local group = self.db.profile.groups[groupId]
        if not group then
            SuspendCastBar()
            return
        end

        local groupFrame = CooldownCompanion.groupFrames[groupId]
        if not groupFrame or not groupFrame:IsShown() then
            SuspendCastBar()
            return
        end

        -- Only anchor to icon-like groups
        if not CooldownCompanion:IsIconLikeDisplayMode(group.displayMode) then
            SuspendCastBar()
            return
        end

        HideIndependentCastBarMover()
    end

    local width = ResolveCastBarWidth(settings)
    if not width then
        SuspendCastBar()
        return
    end
    local height = GetCastBarHeight(settings)

    EnsureCastBarFrame()
    if not ApplyCastBarPosition(settings, width, height) then
        SuspendCastBar()
        return
    end
    ApplyCastBarLayout(settings, width, height)
    ApplyCastBarStyle(settings)
    -- The pip offsets are absolute against the fill width that just changed.
    if cast.state == "empower" and cast.numStages > 0 then
        BuildStagePips(cast.numStages)
    elseif cast.state == "channel" then
        BuildChannelTickMarks()
    end

    SuppressBlizzardCastBar()
    isApplied = true
    EnableCastEventFrame()

    -- Pick up a cast already in flight (feature enabled mid-cast, /reload),
    -- the same resync Blizzard's bar does on PLAYER_ENTERING_WORLD.
    if isUnlockAssistActive then
        ApplyCastBarUnlockPreview()
    elseif not cast.state and not cast.fadeMode then
        HandleCastEvent(castEventFrame, "PLAYER_ENTERING_WORLD")
    end
end

------------------------------------------------------------------------
-- Reposition: anchor/width recalculation for stack and group changes
------------------------------------------------------------------------

function CooldownCompanion:RepositionCastBar()
    if not isApplied then return end
    local settings = GetCastBarSettings()
    if not settings or not settings.enabled then return end
    if not castBarFrame then return end

    local width = ResolveCastBarWidth(settings)
    if not width then return end
    local height = GetCastBarHeight(settings)

    if not ApplyCastBarPosition(settings, width, height) then return end
    ApplyCastBarLayout(settings, width, height)
    -- The pip offsets are absolute against the fill width that just changed.
    if cast.state == "empower" and cast.numStages > 0 then
        BuildStagePips(cast.numStages)
    elseif cast.state == "channel" then
        BuildChannelTickMarks()
    end
    return true
end

-- Resource-only edits and native aura tails change attachment geometry, not
-- cast styling. Retain full lifecycle convergence for suspended bars and
-- independent movers, whose setup belongs to ApplyCastBarSettings.
function CooldownCompanion:RefreshCastBarAttachment()
    local settings = GetCastBarSettings()
    local groupId = settings and GetEffectiveAnchorGroupId(settings)
    local group = groupId and self.db.profile.groups[groupId]
    local frame = groupId and self.groupFrames[groupId]
    if isApplied and settings and settings.enabled
        and not self:IsModuleAnchorIndependent("castbar")
        and not (independentMoverFrame and independentMoverFrame:IsShown())
        and group and self:IsIconLikeDisplayMode(group.displayMode)
        and frame and frame:IsShown() and self:RepositionCastBar() then
        if isUnlockAssistActive then
            ApplyCastBarUnlockPreview()
        elseif not cast.state and not cast.fadeMode then
            HandleCastEvent(castEventFrame, "PLAYER_ENTERING_WORLD")
        end
        self:RefreshUnlockToolbar()
        return
    end
    self:EvaluateCastBar({ skipRuntimeGate = true })
end

------------------------------------------------------------------------
-- Evaluate: central decision point
------------------------------------------------------------------------
function CooldownCompanion:EvaluateCastBar(opts)
    opts = opts or {}
    if not opts.skipRuntimeGate then
        return self:RefreshBarsAndFramesRuntimeFeature("castBar", opts.reason or "castbar-evaluate")
    end
    if self.RecordBarsAndFramesRuntimeWork then
        self:RecordBarsAndFramesRuntimeWork("castEvaluate")
    end

    if self._unsupportedLegacyProfile then
        self:RevertCastBar()
        self:RefreshUnlockToolbar()
        return
    end

    local settings = GetCastBarSettings()
    if not settings or not settings.enabled then
        self:RevertCastBar()
        self:RefreshUnlockToolbar()
        return
    end
    InstallHooks()
    self:ApplyCastBarSettings({ skipRuntimeGate = true })
    self:RefreshUnlockToolbar()
end

function CooldownCompanion:GetCastBarRuntimeDebugInfo()
    return {
        applied = isApplied == true,
        hooksInstalled = hooksInstalled == true,
        castEventsActive = castEventFrameEnabled == true,
        blizzardSuppressed = blizzardSuppressed == true,
        blizzardSuppressionYielded = blizzardSuppressionYielded == true,
    }
end

------------------------------------------------------------------------
-- Unlock assist: show CC's cast bar with a stand-in cast so it can be
-- dragged. State is ephemeral (local flag, not saved to DB) and ends when:
--   • a real cast event fires
--   • the bar is locked again
--   • the cast bar panel is deactivated / config panel closed
--   • the feature is disabled / anchor reverts
--
-- This is the one place CC still paints a fabricated value onto a live
-- display, and only because an idle cast bar has nothing to position by.
------------------------------------------------------------------------

ApplyCastBarUnlockPreview = function()
    if not isApplied then return end
    local frame = castBarFrame
    if not frame then return end
    local s = GetCastBarSettings()
    if not s or not s.enabled then return end

    ResetCastState()
    HideStagePips()
    HideChannelTickMarks()
    ClearCastBarEffects()
    StopCastBarDriverUpdates()

    frame:SetAlpha(1)
    frame:Show()
    SetCastFill(0.65, true)
    if frame.nameText:IsShown() then
        frame.nameText:SetText("Preview Cast")
    end
    -- Through the shared setter so its last-text dedupe cache stays coherent.
    SetCastTimeText(1.5)
end

function CooldownCompanion:StartCastBarUnlockAssist()
    isUnlockAssistActive = true
    self:ApplyCastBarSettings()
    ApplyCastBarUnlockPreview()
end

function CooldownCompanion:StopCastBarUnlockAssist()
    -- Unconditional on the flag: a cast event can clear it while the
    -- stand-in is still painted (a FAILED that starts nothing), and the
    -- mover's lock path must still wipe the fabricated fill.
    isUnlockAssistActive = false
    if not cast.state and not cast.fadeMode then
        HideCastBar()
    end
end

-- The command-center cast preview: state only. The cast it stands for is
-- animated on the config canvas's cast facsimile, never on the real bar.
function CooldownCompanion:IsCastBarPreviewActive()
    return ST._ConfigPreview.GetSample("cast") ~= nil
end

------------------------------------------------------------------------
-- Hooks
-- Hooks on our own addon methods (RefreshGroupFrame, RefreshAllGroups) are
-- always safe since they are not Blizzard secure handlers.  Nothing here
-- hooks PlayerCastingBarFrame any more: CC no longer restyles it, so the
-- SetLook / PlayerFrame_AdjustAttachments re-apply chase is gone with it.
------------------------------------------------------------------------

InstallHooks = function()
    if not hooksInstalled then
        hooksInstalled = true

        -- Yield only to Blizzard's ApplyingTalents overlay. Other contextual
        -- overlays use the same frame, but CC remains the cast-bar owner and
        -- hides them. OverlayPlayerCastingBarMixin also re-enables the regular
        -- player bar after OnHide, so hook the end of that handoff and
        -- reassert suppression after Blizzard's write.
        -- The registry reports transitions only, so seed the current state:
        -- hooks install the first time the feature applies, which can happen
        -- while an overlay cast is already on screen. IsShown is a C-level
        -- read and overrideBarType is read-only from CC's side.
        local function IsTalentOverlayShown()
            local overlayBar = OverlayPlayerCastingBarFrame
            local applyingTalentsType = CastingBarType and CastingBarType.ApplyingTalents
            return overlayBar ~= nil
                and overlayBar:IsShown()
                and applyingTalentsType ~= nil
                and overlayBar.overrideBarType == applyingTalentsType
        end

        local function HideNonTalentOverlay()
            local overlayBar = OverlayPlayerCastingBarFrame
            if not overlayBar or not overlayBar:IsShown() then return end
            nonTalentOverlayHiddenByCC = true
            local hide = overlayBar.HideBase or overlayBar.Hide
            hide(overlayBar)
        end

        local overlayHandoffHooksInstalled = false
        local function InstallOverlayHandoffHooks()
            if overlayHandoffHooksInstalled then return end
            local overlayBar = OverlayPlayerCastingBarFrame
            if not overlayBar
                or type(overlayBar.StartReplacingPlayerBarAt) ~= "function"
                or type(overlayBar.EndReplacingPlayerBar) ~= "function" then
                return
            end
            hooksecurefunc(overlayBar, "StartReplacingPlayerBarAt", function(_, _, overrideInfo)
                local applyingTalentsType = CastingBarType and CastingBarType.ApplyingTalents
                if not applyingTalentsType
                    or not overrideInfo
                    or overrideInfo.overrideBarType ~= applyingTalentsType then
                    return
                end
                overlayReplacingPlayerBar = true
                if isApplied then
                    HideCastBar()
                end
                YieldBlizzardCastBarSuppression()
            end)
            hooksecurefunc(overlayBar, "EndReplacingPlayerBar", function()
                nonTalentOverlayHiddenByCC = false
                overlayReplacingPlayerBar = false
                if ShouldOwnBlizzardCastBar() then
                    SuppressBlizzardCastBar()
                    C_Timer.After(0, function()
                        if ShouldOwnBlizzardCastBar() then
                            CooldownCompanion:EvaluateCastBar({ reason = "castbar-talent-handoff" })
                        end
                    end)
                end
            end)
            overlayHandoffHooksInstalled = true
        end

        local overlayBar = OverlayPlayerCastingBarFrame
        overlayReplacingPlayerBar = IsTalentOverlayShown()
        if overlayBar and overlayBar:IsShown() and not overlayReplacingPlayerBar then
            HideNonTalentOverlay()
        end
        InstallOverlayHandoffHooks()

        EventRegistry:RegisterCallback("OverlayPlayerCastBar.OnShow", function()
            InstallOverlayHandoffHooks()
            overlayReplacingPlayerBar = IsTalentOverlayShown()
            if overlayReplacingPlayerBar then
                if isApplied then
                    HideCastBar()
                end
                YieldBlizzardCastBarSuppression()
            elseif not overlayReplacingPlayerBar and ShouldOwnBlizzardCastBar() then
                HideNonTalentOverlay()
                SuppressBlizzardCastBar()
            end
        end, CooldownCompanion)
        EventRegistry:RegisterCallback("OverlayPlayerCastBar.OnHide", function()
            local shouldResume = overlayReplacingPlayerBar
            -- OnHide can run inside EndReplacingPlayerBar before Blizzard has
            -- restored its regular player bar. Keep yielding until the end
            -- hook completes the handoff, then pick up any in-flight cast.
            if shouldResume then
                C_Timer.After(0, function()
                    if isApplied and not isUnlockAssistActive then
                        HandleCastEvent(castEventFrame, "PLAYER_ENTERING_WORLD")
                    end
                end)
            end
        end, CooldownCompanion)

        -- Edit Mode explicitly shows PlayerCastingBarFrame regardless of its
        -- current cast state. Its registry events fire after Blizzard's own
        -- enter/exit updates, making them the narrow point to reassert CC's
        -- existing C-level suppression.
        local function ReassertBlizzardCastBarSuppression()
            if ShouldOwnBlizzardCastBar() then
                SuppressBlizzardCastBar()
            end
        end
        EventRegistry:RegisterCallback("EditMode.Enter", ReassertBlizzardCastBarSuppression, CooldownCompanion)
        EventRegistry:RegisterCallback("EditMode.Exit", ReassertBlizzardCastBarSuppression, CooldownCompanion)
    end
end
