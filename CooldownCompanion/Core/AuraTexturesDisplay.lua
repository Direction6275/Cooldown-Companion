--[[
    CooldownCompanion - Core/AuraTexturesDisplay.lua
    Aura texture host creation, Indicator display rendering, and refresh flow.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AT = ST._AT

local CreateFrame = CreateFrame
local UIParent = UIParent
local ipairs = ipairs
local pairs = pairs
local type = type

local CopyColor = AT.CopyColor
local Clamp = AT.Clamp
local ResolveGroup = ST.ResolveGroup
local StopAllTextureIndicatorEffects = AT.StopAllTextureIndicatorEffects
local DoesIndicatorMatch = AT.DoesIndicatorMatch

local function GetGroupedPreviewContainerFrame(group, groupId)
    if not (group and group.parentContainerId) then
        return nil
    end
    if not (CooldownCompanion.IsContainerUnlockPreviewActive and CooldownCompanion:IsContainerUnlockPreviewActive(group.parentContainerId)) then
        return nil
    end
    if groupId
        and CooldownCompanion.IsGroupVisibleInUnlockPreview
        and not CooldownCompanion:IsGroupVisibleInUnlockPreview(groupId, {
            group = group,
            checkCharVisibility = true,
        })
    then
        return nil
    end
    return CooldownCompanion.containerFrames and CooldownCompanion.containerFrames[group.parentContainerId] or nil
end

local function EnsureAuraTextureRuntimeRoot(host)
    if host.auraRuntimeRoot then
        return host.auraRuntimeRoot
    end

    -- Plain safe parent for AuraContainer -> AuraButton -> selected-texture
    -- kit. Recursive frame sweeps stop here; AuraDisplay exclusively owns its
    -- descendants. Alpha is the preview/production switch and is safe because
    -- this frame itself is outside Blizzard's forbidden AuraButton subtree.
    local root = CreateFrame("Frame", nil, host)
    root:SetAllPoints(host)
    root:SetAlpha(0)
    root._ccNoTouch = true
    host.auraRuntimeRoot = root
    return root
end

function CooldownCompanion:EnsureAuraTextureHost(button)
    if button.auraTextureHost then
        local existing = button.auraTextureHost
        EnsureAuraTextureRuntimeRoot(existing)
        -- Acquisition for a live display: the teardown latch never survives it.
        existing._indicatorTeardownFor = nil
        return existing
    end

    -- The panel frame's child, so its fade, Group alpha, ghost look and
    -- hiding reach the display directly (the host carries only source dimming).
    -- Button pools are per panel frame, so the host never changes panels.
    -- The panel frame is the display's box: it is what gets placed, dragged
    -- and anchored to. The host sits on its centre and never takes the mouse.
    local parent = button:GetParent() or UIParent
    local host = CreateFrame("Frame", nil, parent)
    host:SetPoint("CENTER", parent, "CENTER", 0, 0)
    host:EnableMouse(false)
    host:Hide()
    host._ownerButton = button

    local visualRoot = CreateFrame("Frame", nil, host)
    visualRoot:SetPoint("CENTER", host, "CENTER", 0, 0)
    visualRoot:SetSize(1, 1)
    host.visualRoot = visualRoot

    local primary = visualRoot:CreateTexture(nil, "ARTWORK", nil, 1)
    local secondary = visualRoot:CreateTexture(nil, "ARTWORK", nil, 1)
    primary:Hide()
    secondary:Hide()
    host.primaryTexture = primary
    host.secondaryTexture = secondary

    EnsureAuraTextureRuntimeRoot(host)

    button.auraTextureHost = host
    return host
end

-- A presence display (While Missing, aura lists): a bare drawing host with
-- the same visual fields
-- the shared Indicator painters expect (visualRoot, primary/secondary
-- texture), every frame carrying `template`. AuraDisplay parents it inside the
-- presence window; alpha stays on the ordinary host, which this sits
-- centered on.
function CooldownCompanion.CreateIndicatorPresenceHost(parent, template)
    local host = CreateFrame("Frame", nil, parent, template)
    host:EnableMouse(false)
    host:SetSize(1, 1)
    host._ccFrameTemplate = template
    -- Drawn (clipped) while the aura is up too: run what effects can as
    -- AnimationGroups rather than per-frame scripts (AuraTexturesEffects).
    host._ccAnimatedEffects = true
    local visualRoot = CreateFrame("Frame", nil, host, template)
    visualRoot:SetPoint("CENTER", host, "CENTER", 0, 0)
    visualRoot:SetSize(1, 1)
    host.visualRoot = visualRoot
    host.primaryTexture = visualRoot:CreateTexture(nil, "ARTWORK", nil, 1)
    host.secondaryTexture = visualRoot:CreateTexture(nil, "ARTWORK", nil, 1)
    host.primaryTexture:Hide()
    host.secondaryTexture:Hide()
    return host
end

-- Latched: callers on the per-update path (unlocked, other modes) run this
-- every tick; the teardown happens once until the next presence render.
function CooldownCompanion.ReleaseIndicatorPresenceHost(presence)
    if presence._ccPresenceReleased then return end
    presence._ccPresenceReleased = true
    StopAllTextureIndicatorEffects(presence)
    ST.Indicator.ReleaseVisual(presence)
    CooldownCompanion.HideIndicatorDisplayVisuals(presence)
end

local function ReleasePresenceDisplay(button)
    local presences = CooldownCompanion.GetIndicatorPresenceHosts and CooldownCompanion:GetIndicatorPresenceHosts(button)
    for _, presence in ipairs(presences or {}) do
        CooldownCompanion.ReleaseIndicatorPresenceHost(presence)
    end
end

function CooldownCompanion.EnsureIndicatorIconVisual(host)
    if host.iconFrame then
        return host.iconFrame
    end

    local frame = CreateFrame("Frame", nil, host.visualRoot, host._ccFrameTemplate)
    frame:SetPoint("CENTER")
    frame:SetSize(36, 36)
    frame:Hide()

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()

    frame.icon = frame:CreateTexture(nil, "ARTWORK")

    frame.borderTextures = ST.CreateBorderTextureSet(frame, "OVERLAY")

    host.iconFrame = frame
    return frame
end

function CooldownCompanion.EnsureIndicatorTextVisual(host)
    if host.textFrame then
        return host.textFrame
    end

    local frame = CreateFrame("Frame", nil, host.visualRoot, host._ccFrameTemplate)
    frame:SetPoint("CENTER")
    frame:SetSize(200, 20)
    frame:Hide()

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()

    frame.borderTextures = ST.CreateBorderTextureSet(frame, "OVERLAY")

    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.text:SetJustifyV("MIDDLE")
    frame.text:SetJustifyH("CENTER")
    frame.text:SetWordWrap(false)
    frame.text:SetMaxLines(0)

    host.textFrame = frame
    return frame
end

function CooldownCompanion.HideIndicatorDisplayVisuals(host)
    if not host then
        return
    end
    host._indicatorStyle = nil

    if host.primaryTexture then
        host.primaryTexture:Hide()
    end
    if host.secondaryTexture then
        host.secondaryTexture:Hide()
    end
    if host.iconFrame then
        host.iconFrame:Hide()
    end
    if host.textFrame then
        host.textFrame:Hide()
    end
    host._indicatorBaseVisualsReady = nil
end

function CooldownCompanion.GetIndicatorIconDimensions(settings)
    if settings.maintainAspectRatio then
        local size = settings.buttonSize or 36
        return size, size
    end
    return settings.iconWidth or 36, settings.iconHeight or 36
end



function CooldownCompanion:HideAuraTextureVisual(button)
    local host = button and button.auraTextureHost
    if not host then
        return
    end

    local groupId = button._groupId
    -- Already-torn-down latch. Keyed by the group this host was torn down for,
    -- so a pooled host that changes hands cannot inherit it, and re-validated
    -- against the state the body itself leaves behind (hidden), so anything
    -- that shows the host reopens the teardown.
    -- Cleared explicitly on every prepare/render/finalize/release path.
    if groupId ~= nil
        and host._indicatorTeardownFor == groupId
        and not host:IsShown() then
        return
    end

    StopAllTextureIndicatorEffects(host)
    ReleasePresenceDisplay(button)
    host._ccPresenceMode = nil
    ST.Indicator.ReleaseVisual(host)
    CooldownCompanion.HideIndicatorDisplayVisuals(host)
    if host.visualRoot then
        host.visualRoot:SetAlpha(1)
    end
    if host.auraRuntimeRoot then
        host.auraRuntimeRoot:SetAlpha(0)
    end
    host._activeDisplayType = nil
    host._activeTextureSettings = nil
    host._activeTextureGeometry = nil
    host:SetAlpha(1)
    host:Hide()
    host._indicatorTeardownFor = groupId
end

function CooldownCompanion:ReleaseAuraTextureVisual(button)
    if not button or not button.auraTextureHost then
        return
    end

    self:HideAuraTextureVisual(button)
    -- A retained host outlives this release, so the next hide must run the full
    -- body rather than trust a latch set before the entry changed hands.
    button.auraTextureHost._indicatorTeardownFor = nil
    -- AuraButton has a permanent ChangeParent forbidden aspect. Once this
    -- host owns an AuraContainer, retain the whole topology across pooling;
    -- AuraDisplay parks the container and owns the pool token reconciliation.
    if not button.auraTextureHost._auraSlotOwned then
        button.auraTextureHost:SetParent(nil)
        button.auraTextureHost = nil
    end
end

function CooldownCompanion.ResolveActiveIndicatorDisplay(button)
    local group = button._groupId and ResolveGroup(button._groupId)
    local settings = ST.Indicator.Settings(group)
    if not settings then return end
    if settings.displayType == "icon" then return "icon", ST.Indicator.IconSettings(group) end
    if settings.displayType == "text" then return "text", settings.text end
    return "texture", settings.signal
end

function CooldownCompanion.ApplyIndicatorIconVisual(host, settings)
    local iconFrame = CooldownCompanion.EnsureIndicatorIconVisual(host)
    local width, height = CooldownCompanion.GetIndicatorIconDimensions(settings)
    local borderSize = settings.borderSize or 0
    local borderRenderMode = ST.GetBorderRenderMode(settings)
    local borderLayoutSize = ST.GetEffectiveBorderLayoutSize(iconFrame, borderSize, borderRenderMode)
    local iconTint = settings.iconTintColor or { 1, 1, 1, 1 }
    local backgroundColor = settings.backgroundColor or { 0, 0, 0, 0.5 }
    local borderColor = settings.borderColor or { 0, 0, 0, 1 }

    CooldownCompanion:ResetTextureIndicatorRootState(host)
    CooldownCompanion.HideIndicatorDisplayVisuals(host)

    host._activeTextureSettings = nil
    host._activeTextureGeometry = nil
    host._activeDisplayType = "icon"
    host._indicatorBaseVisualsReady = nil
    host._indicatorTextBaseColor = nil
    host._indicatorIconBaseColor = CopyColor(iconTint) or { 1, 1, 1, 1 }

    host:SetSize(width, height)
    host.visualRoot:SetSize(width, height)

    iconFrame:SetSize(width, height)
    iconFrame.bg:SetColorTexture(
        backgroundColor[1] or 0,
        backgroundColor[2] or 0,
        backgroundColor[3] or 0,
        backgroundColor[4] ~= nil and backgroundColor[4] or 0.5
    )
    iconFrame.icon:ClearAllPoints()
    iconFrame.icon:SetPoint("TOPLEFT", borderLayoutSize, -borderLayoutSize)
    iconFrame.icon:SetPoint("BOTTOMRIGHT", -borderLayoutSize, borderLayoutSize)
    iconFrame.icon:SetTexture(settings.manualIcon)
    iconFrame.icon:SetVertexColor(
        iconTint[1] or 1,
        iconTint[2] or 1,
        iconTint[3] or 1,
        iconTint[4] ~= nil and iconTint[4] or 1
    )
    ST._ApplyIconTexCoord(iconFrame.icon, width, height, settings.iconZoom)

    for _, border in ipairs(iconFrame.borderTextures) do
        border:SetColorTexture(
            borderColor[1] or 0,
            borderColor[2] or 0,
            borderColor[3] or 0,
            borderColor[4] ~= nil and borderColor[4] or 1
        )
        -- Shared border sets start hidden; the positions helper never shows.
        border:Show()
    end
    ST._ApplyBorderEdgePositions(iconFrame.borderTextures, iconFrame, borderSize, borderRenderMode)
    iconFrame:Show()

    return true
end


function CooldownCompanion:GetIndicatorDisplayVisibilityState(group, frame, driverButton, settings, isConditionsIndicator)
    local groupedPreviewFrame = GetGroupedPreviewContainerFrame(group, driverButton and driverButton._groupId)
    local combatForcedLock = self._combatForcedLock == true
    local isCursorAnchored = self.IsGroupCursorAnchored and self:IsGroupCursorAnchored(group)
    local isCursorLayoutPreview = driverButton
        and self.IsCursorAnchorLayoutPreviewGroupActive
        and self:IsCursorAnchorLayoutPreviewGroupActive(driverButton._groupId)
        or false
    local state = {
        isCursorLayoutPreview = isCursorLayoutPreview,
        isUnlocked = not isCursorAnchored and not combatForcedLock and group and (self:IsPanelUnlockPreviewActive(group) or groupedPreviewFrame ~= nil),
        triggerMatched = isConditionsIndicator and frame and frame:IsShown() and DoesIndicatorMatch(frame) or false,
        showDisplay = false,
    }

    if settings then
        if state.isCursorLayoutPreview then
            state.showDisplay = true
        elseif isConditionsIndicator then
            state.showDisplay = state.triggerMatched or state.isUnlocked
        elseif state.isUnlocked then
            state.showDisplay = true
        elseif driverButton:GetParent()
            and driverButton:GetParent():IsShown()
            and not driverButton:GetParent()._combatForcedHidden
            and not (driverButton._rawVisibilityHidden == true) then
            state.showDisplay = true
        end
    end

    state.triggerSoundVisible = settings ~= nil and state.triggerMatched and state.showDisplay
    state.bypassModuleAlpha = state.isCursorLayoutPreview
        or state.isUnlocked
    return state
end

-- The display draws this far above its hidden source, so it covers panels it
-- overlaps. The panel mover lifts an Indicator's chrome above it
-- (SyncGroupControlLevels) from the same answer.
function CooldownCompanion.GetIndicatorHostLevel(driverButton)
    return (driverButton:GetFrameLevel() or 1) + 20
end
local GetIndicatorHostLevel = CooldownCompanion.GetIndicatorHostLevel

function CooldownCompanion:RenderIndicatorDisplay(host, driverButton, group, settings, displayType, effectsActive)
    host._indicatorTeardownFor = nil
    host._ccPresenceMode = nil
    -- Written only on change: this sits on the per-update path.
    local strata, hostLevel = driverButton:GetFrameStrata(), GetIndicatorHostLevel(driverButton)
    if host:GetFrameStrata() ~= strata or host:GetFrameLevel() ~= hostLevel then
        host:SetFrameStrata(strata)
        host:SetFrameLevel(hostLevel)
    end
    return ST.Indicator.Render(host, driverButton, group, false, nil, effectsActive,
        displayType == "icon" and settings or nil)
end

-- Locked aura Indicators keep the ordinary host for anchoring,
-- load visibility, and alpha, but render their production pixels only beneath
-- Blizzard's AuraButton. This prepares the safe outer shell without touching
-- any AuraContainer descendant; AuraDisplay styles that subtree OOC.
function CooldownCompanion:PrepareManagedAuraTextureDisplay(host, driverButton, resolvedIcon, revealRuntime)
    local group = driverButton._groupId and ResolveGroup(driverButton._groupId)
    local settings = ST.Indicator.NativeSettings(group, resolvedIcon)
    if not settings then return false end
    local resolvedSourceType = self:ResolveAuraTextureAsset(
        settings.sourceType,
        settings.sourceValue,
        settings.mediaType
    )
    local geometry = self:GetIndicatorTextureRenderGeometry(settings)
    if not resolvedSourceType or not geometry then
        return false
    end

    -- Anything that repaints the host invalidates the teardown latch.
    host._indicatorTeardownFor = nil
    host._ccPresenceMode = nil
    -- Written only on change: this sits on the per-update path.
    local strata, hostLevel = driverButton:GetFrameStrata(), GetIndicatorHostLevel(driverButton)
    if host:GetFrameStrata() ~= strata or host:GetFrameLevel() ~= hostLevel then
        host:SetFrameStrata(strata)
        host:SetFrameLevel(hostLevel)
    end
    StopAllTextureIndicatorEffects(host)
    CooldownCompanion.HideIndicatorDisplayVisuals(host)
    host:SetSize(geometry.boundsWidth, geometry.boundsHeight)
    if host.visualRoot then
        host.visualRoot:SetSize(geometry.boundsWidth, geometry.boundsHeight)
        host.visualRoot:SetAlpha(0)
    end
    if host.auraRuntimeRoot then
        host.auraRuntimeRoot:SetAlpha(revealRuntime and 1 or 0)
    end
    host._activeDisplayType = nil
    host._activeTextureSettings = nil
    host._activeTextureGeometry = nil
    host._indicatorBaseVisualsReady = nil
    return true
end

-- The display's box, from the saved design alone: the size of an Indicator's
-- panel frame, which is what gets placed, dragged and anchored to.
function CooldownCompanion:GetIndicatorBoxSize(group)
    local display = ST.Indicator.Settings(group)
    if not display then
        return 1, 1
    end
    if display.displayType == "texture" then
        local geometry = self:GetIndicatorTextureRenderGeometry(self:GetIndicatorTextureSettings(group))
        if geometry then
            return geometry.boundsWidth, geometry.boundsHeight
        end
        return 36, 36
    elseif display.displayType == "icon" then
        return self.GetSavedIndicatorIconDimensions(display.icon)
    end
    local text = display.text
    return text and text.width or 180, text and text.height or 48
end

-- The panel frame is the box, and the saved design is the one answer for
-- its size. The layout pass stamps the box it sized the frame for
-- (SizeGroupFrame); the frame is sized again (the ordinary resize, with its
-- combat deferral) only when the saved box no longer matches that stamp.
-- refreshOutline: its Group's unlock outline follows; a caller that
-- refreshes every outline afterwards skips it.
local function SizeIndicatorFrame(self, frame, group, refreshOutline)
    local width, height = self:GetIndicatorBoxSize(group)
    if frame._indicatorBoxWidth == width and frame._indicatorBoxHeight == height then
        return
    end
    self:ResizeGroupFrame(frame.groupId)
    if refreshOutline and group.parentContainerId and self.RefreshContainerWrapper then
        self:RefreshContainerWrapper(group.parentContainerId)
    end
end

-- A design edit: size the frame from the saved design, whether or not the
-- display is showing.
function CooldownCompanion:SyncIndicatorFrameSize(groupId)
    local frame = self.groupFrames and self.groupFrames[groupId]
    local group = frame and ResolveGroup(groupId)
    if ST.IsIndicatorGroup(group) then
        SizeIndicatorFrame(self, frame, group, true)
    end
end

function CooldownCompanion:FinalizeIndicatorDisplay(host, frame, driverButton, group, visibilityState)
    -- This is the only path that shows the host, so it clears the teardown latch.
    host._indicatorTeardownFor = nil
    host:Show()
    -- A host drawn at a new size means the design changed: the cue, on the
    -- per-update path, to check the frame against the saved box.
    local hostWidth, hostHeight = host:GetSize()
    if frame._indicatorHostWidth ~= hostWidth or frame._indicatorHostHeight ~= hostHeight then
        frame._indicatorHostWidth, frame._indicatorHostHeight = hostWidth, hostHeight
        SizeIndicatorFrame(self, frame, group, true)
    end

    local honorSourceVisibility = ST.Indicator.Settings(group).sourceVisibility ~= false
    local visibilityAlpha = honorSourceVisibility and Clamp(driverButton._rawVisibilityAlphaOverride or 1, 0, 1) or 1
    -- The panel frame, the host's parent, carries the fade, Group alpha and
    -- the ghost look. The host adds only its own source dimming, which never
    -- reaches downstream panel anchors, and none while unlocked or previewed.
    host:SetAlpha(visibilityState.bypassModuleAlpha and 1 or visibilityAlpha)

    if driverButton:GetAlpha() ~= 0 then
        driverButton:SetAlpha(0)
        driverButton._lastVisAlpha = 0
    end
    if ST.SetFrameClickThroughRecursive then
        -- Every hidden source, including an aura Indicator's extra sources.
        if type(frame.buttons) == "table" then
            for _, backingButton in ipairs(frame.buttons) do
                ST.SetFrameClickThroughRecursive(backingButton, true, true)
            end
        else
            ST.SetFrameClickThroughRecursive(driverButton, true, true)
        end
    end
end

function CooldownCompanion:UpdateAuraTextureVisual(button)
    if not button then
        return
    end

    local group = button._groupId and ResolveGroup(button._groupId) or nil
    if not ST.IsIndicatorGroup(group) then
        self:HideAuraTextureVisual(button)
        return
    end

    local frame = button:GetParent()
    local isConditionsIndicator = self:IsConditionsIndicatorGroup(group)
    local driverButton = ST.Indicator.RuntimeSource(frame, group)
    if not driverButton then
        self:HideAuraTextureVisual(button)
        return
    end

    local displayType, settings = CooldownCompanion.ResolveActiveIndicatorDisplay(driverButton)
    local resolvedIcon = displayType == "icon" and settings or nil
    local visibilityState = self:GetIndicatorDisplayVisibilityState(group, frame, driverButton, settings, isConditionsIndicator)

    if isConditionsIndicator and self.UpdateConditionsIndicatorSoundAlerts then
        self:UpdateConditionsIndicatorSoundAlerts(frame, group, visibilityState.triggerSoundVisible)
    end

    if not settings or not visibilityState.showDisplay then
        self:HideAuraTextureVisual(driverButton)
        if driverButton:GetAlpha() ~= 0 then
            driverButton:SetAlpha(0)
            driverButton._lastVisAlpha = 0
        end
        return
    end

    local host = self:EnsureAuraTextureHost(driverButton)
    local auraControlled = not isConditionsIndicator
        and self:IsIndicatorAuraDisplayEnabled(group, driverButton.buttonData)
    -- Aura Indicators render production artwork only inside their native slot.
    -- Reveal it once the access-gated rebind has installed this source's token;
    -- a pooled host may still carry the previous source's slot. Layout/unlock
    -- previews use the ordinary saved-design render instead.
    local slotToken = driverButton._auraSlotHostToken
    local hasBoundSlot = slotToken ~= nil and slotToken == driverButton.buttonData
    local useManagedRuntime = auraControlled
        and not visibilityState.bypassModuleAlpha
    -- While Missing and aura lists: the ordinary host keeps placement and
    -- alpha but draws nothing; the display is painted into the presence
    -- copies, which Blizzard's trackers uncover only while the auras match
    -- (one copy, or one per aura for Any). Unlocked and layout previews show
    -- the saved design on the ordinary host instead.
    local presenceRuntime = ST.Indicator.UsesPresence(group)
        and not visibilityState.bypassModuleAlpha
    local presences = presenceRuntime and self:GetIndicatorPresenceHosts(driverButton)
    local presence = presences and presences[1]
    local shown
    if presence then
        -- Extra sources' rules hide the drawing and its effects; the trackers
        -- and the auras' sounds keep running underneath.
        local rulesPass = ST.Indicator.ExtraSourcesMatch(frame, group)
        -- Every copy draws the same design: once the first finds its style
        -- unchanged, the others only need their effects stepped.
        local styleBefore = presence._indicatorStyle
        presence._ccPresenceReleased = nil
        shown = ST.Indicator.Render(presence, driverButton, group, false, nil, rulesPass, resolvedIcon)
        local restyled = presence._indicatorStyle ~= styleBefore
        for index = 2, #presences do
            local copy = presences[index]
            if restyled or copy._ccPresenceReleased or not copy._indicatorStyle then
                copy._ccPresenceReleased = nil
                ST.Indicator.Render(copy, driverButton, group, false, nil, rulesPass, resolvedIcon)
            elseif shown then
                self:ApplyIndicatorEffects(copy, driverButton, group, rulesPass == true)
            end
        end
        -- Only a successful render repaints the host. A design with nothing to
        -- draw leaves the teardown latch alone, so the hide below stays cheap.
        if shown then
            host._indicatorTeardownFor = nil
            -- Written only on change: these sit on the per-update path.
            local strata, hostLevel = driverButton:GetFrameStrata(), GetIndicatorHostLevel(driverButton)
            if not host._ccPresenceMode or host:GetFrameStrata() ~= strata or host:GetFrameLevel() ~= hostLevel then
                host:SetFrameStrata(strata)
                host:SetFrameLevel(hostLevel)
            end
            if not host._ccPresenceMode then
                -- Entering presence mode: the ordinary host draws nothing from
                -- here on, so its own visuals are cleared once, not every
                -- update. Every other render path clears this latch.
                host._ccPresenceMode = true
                StopAllTextureIndicatorEffects(host)
                CooldownCompanion.HideIndicatorDisplayVisuals(host)
                if host.visualRoot then host.visualRoot:SetAlpha(0) end
                if host.auraRuntimeRoot then host.auraRuntimeRoot:SetAlpha(0) end
                host._activeDisplayType, host._activeTextureSettings, host._activeTextureGeometry = nil, nil, nil
            end
            local level = host:GetFrameLevel() + 1
            for _, copy in ipairs(presences) do
                if copy:GetFrameLevel() ~= level then copy:SetFrameLevel(level) end
            end
            -- The copies sit centred on the ordinary host: size it from the
            -- drawing (a CC-set size, never a measured one).
            local width, height = presence:GetSize()
            local hostWidth, hostHeight = host:GetSize()
            if hostWidth ~= width or hostHeight ~= height then host:SetSize(width, height) end
        end
        for _, copy in ipairs(presences) do copy:SetShown(shown and rulesPass) end
        -- Also During Pandemic: the aura's native display (gated by Blizzard
        -- to the refresh window) rides the texture layer, so the layer follows
        -- the same rules as the drawing. Written only on change.
        if host.auraRuntimeRoot then
            local twinAlpha = shown and rulesPass and ST.Indicator.AlsoDuringPandemic(group)
                and self:HasIndicatorPandemicTwin(driverButton) and 1 or 0
            if host.auraRuntimeRoot:GetAlpha() ~= twinAlpha then host.auraRuntimeRoot:SetAlpha(twinAlpha) end
        end
    elseif presenceRuntime then
        -- Not bound yet (the rebind is queued or deferred by combat): keep
        -- the host placed and sized from the saved design, drawing nothing.
        shown = self:PrepareManagedAuraTextureDisplay(host, driverButton, resolvedIcon, false)
    elseif useManagedRuntime then
        -- A While Missing tracker can stay bound until a combat-deferred
        -- rebind parks it; its drawing must not outlive the mode switch.
        ReleasePresenceDisplay(driverButton)
        -- Extra sources' rules gate only the reveal alpha. The host and the
        -- native slot stay up, so the aura's own sounds keep following it.
        shown = self:PrepareManagedAuraTextureDisplay(host, driverButton, resolvedIcon,
            hasBoundSlot and ST.Indicator.ExtraSourcesMatch(frame, group))
    else
        ReleasePresenceDisplay(driverButton)
        if host.auraRuntimeRoot then
            host.auraRuntimeRoot:SetAlpha(0)
        end
        if host.visualRoot then
            host.visualRoot:SetAlpha(1)
        end
        shown = self:RenderIndicatorDisplay(
            host,
            driverButton,
            group,
            settings,
            displayType,
            visibilityState.triggerMatched
        )
    end

    if not shown then
        self:HideAuraTextureVisual(driverButton)
        if driverButton:GetAlpha() ~= 0 then
            driverButton:SetAlpha(0)
            driverButton._lastVisAlpha = 0
        end
        return
    end

    self:FinalizeIndicatorDisplay(host, frame, driverButton, group, visibilityState)
end

function CooldownCompanion:RefreshAllAuraTextureVisuals()
    self:RebuildPanelAlphaDependencyTargets()
    for _, frame in pairs(self.groupFrames or {}) do
        local group = ResolveGroup(frame.groupId)
        local isIndicator = ST.IsIndicatorGroup(group)
        -- A hidden display never reaches the per-update size check. Every
        -- outline is refreshed below.
        if isIndicator then
            SizeIndicatorFrame(self, frame, group, false)
        end
        -- One Indicator display reads every source's fresh state: update it once.
        local driver = isIndicator and ST.Indicator.RuntimeSource(frame, group)
        if driver then
            self:UpdateAuraTextureVisual(driver)
        else
            for _, button in ipairs(frame.buttons or {}) do
                self:UpdateAuraTextureVisual(button)
            end
        end
    end
    if self.RefreshAllContainerWrappers then
        self:RefreshAllContainerWrappers()
    end
end
