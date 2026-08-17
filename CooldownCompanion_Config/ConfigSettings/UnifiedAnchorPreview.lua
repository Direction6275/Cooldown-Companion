--[[
    CooldownCompanion - UnifiedAnchorPreview
    The buttons view's unified anchor-panel preview: when the selected
    panel is the panel attached bars anchor to, the pinned preview renders
    the real button-panel mirror with the Layout & Order bar lanes wrapped
    around it (resource bars, Custom Bars, cast bar). Clicking a bar opens
    its settings below the divider; dragging re-arranges it, exactly like
    the Resources home preview. Every other panel keeps the plain mirror.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

-- Oversized measuring rect: the mirror builds against it at scale 1, then
-- the inner host shrinks to the mirror content's natural size so the lanes
-- wrap it exactly. The whole composition is scaled to fit by the Layout &
-- Order preview afterwards.
local UNIFIED_MEASURE_SIZE = 4000

-- The attached-bars badge: the same pin the group overview stamps on the
-- anchor panel's tile, worn here as a quick toggle in the preview's
-- top-right corner (the inside corner opposite the command center).
local BADGE_ATLAS = "Waypoint-MapPin-Tracked"
-- The pin atlas carries transparent margins of its own, so the frame hugs
-- the corner tighter than the spellbook badge's numbers to LOOK the same
-- distance in.
local BADGE_SIZE = 20
local BADGE_INSET = 1

local function IsUnifiedAnchorPreviewEligible(groupId)
    if not groupId then
        return false
    end
    if CS.otherClassLibraryActive then
        return false
    end
    if CooldownCompanion.GetCurrentResourceBarConflict
        and CooldownCompanion:GetCurrentResourceBarConflict() then
        return false
    end
    if not (CooldownCompanion.GetFirstAvailableAnchorGroup
        and groupId == CooldownCompanion:GetFirstAvailableAnchorGroup()) then
        return false
    end
    -- The composition needs a renderable mirror to wrap: an empty panel's
    -- mirror is a guidance message, which should keep the plain preview
    -- rather than the bar lanes around a placeholder rect.
    local group = CooldownCompanion.db
        and CooldownCompanion.db.profile
        and CooldownCompanion.db.profile.groups
        and CooldownCompanion.db.profile.groups[groupId]
    if not group then
        return false
    end
    if group.displayMode ~= ST.DISPLAY_MODE_ROTATION_ASSISTANT
        and #(group.buttons or {}) == 0 then
        return false
    end
    return ST._HasAttachedBarLanesToRender
        and ST._HasAttachedBarLanesToRender() == true
end

-- The unified composition renders only while the quick toggle has not
-- hidden it. Exported under this name, so the toggle also clears a
-- lane-selected bar's settings through the shipped validation
-- (GetValidatedUnifiedBarKind): with the lanes off screen there is no
-- lane to have clicked.
local function ShouldUseUnifiedAnchorPreview(groupId)
    return IsUnifiedAnchorPreviewEligible(groupId)
        and not CS.unifiedAnchorBarsHidden
end

------------------------------------------------------------------------
-- The quick toggle: hide the attached bar lanes from this preview
------------------------------------------------------------------------

-- Shared badge chrome. Each toggle supplies its own state, text, refresh
-- behavior and positioning; this owns only the identical frame interaction.
local function ApplyPreviewBadgeHover(badge)
    badge.icon:SetDesaturated(false)
    badge.icon:SetVertexColor(1, 1, 1, 1)
end

local function ApplyPreviewBadgeTint(badge)
    if badge._cdcIsHidden() then
        badge.icon:SetDesaturated(true)
        badge.icon:SetVertexColor(0.72, 0.72, 0.72, 0.85)
    else
        ApplyPreviewBadgeHover(badge)
    end
end

local function ShowPreviewBadgeTooltip(badge)
    GameTooltip:SetOwner(badge, "ANCHOR_LEFT")
    if badge._cdcIsHidden() then
        GameTooltip:SetText(badge._cdcShowText)
    else
        GameTooltip:SetText(badge._cdcHideText)
    end
    GameTooltip:Show()
end

local function CreatePreviewToggleBadge(host, atlas, isHidden, showText, hideText, onClick)
    local badge = CreateFrame("Button", nil, host)
    badge:SetSize(BADGE_SIZE, BADGE_SIZE)
    badge.icon = badge:CreateTexture(nil, "ARTWORK")
    badge.icon:SetAllPoints()
    badge.icon:SetAtlas(atlas, false)
    badge._cdcIsHidden = isHidden
    badge._cdcShowText = showText
    badge._cdcHideText = hideText
    badge._cdcOnClick = onClick
    badge:SetScript("OnEnter", function(self)
        ApplyPreviewBadgeHover(self)
        ShowPreviewBadgeTooltip(self)
    end)
    badge:SetScript("OnLeave", function(self)
        ApplyPreviewBadgeTint(self)
        GameTooltip:Hide()
    end)
    badge:SetScript("OnClick", function(self)
        self._cdcOnClick()
        -- A refresh may retint the badge under the cursor; keep the hover
        -- look and current tooltip until the mouse leaves.
        if GameTooltip:GetOwner() == self then
            ApplyPreviewBadgeHover(self)
            ShowPreviewBadgeTooltip(self)
        end
    end)
    return badge
end

local function AreAttachedBarsHidden()
    return CS.unifiedAnchorBarsHidden
end

local function ToggleAttachedBars()
    CS.unifiedAnchorBarsHidden = not CS.unifiedAnchorBarsHidden or nil
    -- Hiding the lanes takes a lane-selected bar's settings with them; only
    -- the full refresh revalidates that selection.
    if CS.unifiedBarKind then
        CooldownCompanion:RefreshConfigPanel()
    elseif ST._RefreshButtonsPreviewMirror then
        ST._RefreshButtonsPreviewMirror(CS.selectedGroup)
    end
end

-- Session state, view only: the flag lives in CS and the live bars never
-- move. Shown whenever the panel would wear the lanes, hidden or not, so
-- the way back is always on screen.
local function UpdateAttachedBarsBadge(host, eligible)
    local badge = host._cdcAttachedBarsBadge
    if not eligible then
        if badge then badge:Hide() end
        return
    end
    if not badge then
        badge = CreatePreviewToggleBadge(
            host,
            BADGE_ATLAS,
            AreAttachedBarsHidden,
            "Show attached bars",
            "Hide attached bars",
            ToggleAttachedBars
        )
        badge:SetPoint("TOPRIGHT", host, "TOPRIGHT", -BADGE_INSET, -BADGE_INSET)
        host._cdcAttachedBarsBadge = badge
    end
    -- Above the mirror's slots for the same reason the command center
    -- band is: overhanging slot art must not draw over a hit target.
    badge:SetFrameLevel(host:GetFrameLevel() + 20)
    ApplyPreviewBadgeTint(badge)
    badge:Show()
end

------------------------------------------------------------------------
-- The second quick toggle: hide currently-unavailable entries from the
-- focused mirror
------------------------------------------------------------------------

-- Wears the mirror's own "Spell/item unavailable" warn mark, so the badge
-- names exactly what it hides. Sits one badge width inside the attached-bars
-- pin when the pin is up, and takes the pin's corner spot when it is not.
local UNAVAILABLE_BADGE_ATLAS = "Ping_Marker_Icon_Warning"
local BADGE_GAP = 2

local function AreUnavailableEntriesHidden()
    return CS.panelPreviewUnavailableHidden
end

local function ToggleUnavailableEntries()
    CS.panelPreviewUnavailableHidden = not CS.panelPreviewUnavailableHidden or nil
    if ST._RefreshButtonsPreviewMirror then
        ST._RefreshButtonsPreviewMirror(CS.selectedGroup)
    end
end

-- Session state, view only, exactly like the pin: the flag lives in CS and
-- saved config never moves. Shown while the panel has an entry to hide, and
-- always while the filter is on, so the way back stays on screen.
local function UpdateUnavailableEntriesBadge(host, groupId, pinShown)
    local state
    if not CS.otherClassLibraryActive and ST._PanelPreviewUnavailableEntryState then
        local group = groupId
            and CooldownCompanion.db
            and CooldownCompanion.db.profile
            and CooldownCompanion.db.profile.groups
            and CooldownCompanion.db.profile.groups[groupId]
        state = ST._PanelPreviewUnavailableEntryState(group)
    end
    local shown = state == true
        or (state ~= nil and CS.panelPreviewUnavailableHidden == true)
    local badge = host._cdcUnavailableEntriesBadge
    if not shown then
        if badge then badge:Hide() end
        return
    end
    if not badge then
        badge = CreatePreviewToggleBadge(
            host,
            UNAVAILABLE_BADGE_ATLAS,
            AreUnavailableEntriesHidden,
            "Show unavailable entries",
            "Hide unavailable entries",
            ToggleUnavailableEntries
        )
        host._cdcUnavailableEntriesBadge = badge
    end
    -- Re-anchored every build: whether the pin is up can change hands
    -- between builds, and this badge always claims the slot beside it or
    -- the pin's own corner spot.
    badge:ClearAllPoints()
    local insetX = BADGE_INSET + (pinShown and (BADGE_SIZE + BADGE_GAP) or 0)
    badge:SetPoint("TOPRIGHT", host, "TOPRIGHT", -insetX, -BADGE_INSET)
    badge:SetFrameLevel(host:GetFrameLevel() + 20)
    ApplyPreviewBadgeTint(badge)
    badge:Show()
end

-- The mirror content carries the natural (unscaled) panel size; shrink the
-- measuring host to it so the lanes wrap the mirror exactly. Message states
-- (empty panel) keep a readable minimum instead.
local function ShrinkMirrorHostToContent(inner)
    local mirror = inner._cdcPanelPreview
    local mirrorContent = mirror and mirror.content
    local width, height = 220, 90
    if mirrorContent and mirrorContent:IsShown() then
        width = math.max(40, mirrorContent:GetWidth() or 0)
        height = math.max(20, mirrorContent:GetHeight() or 0)
    end
    inner:SetSize(width, height)
end

-- Second copy of the panel, for the vertical layout's separate cast-bar
-- section: one frame cannot sit in two places, and before this the canvas
-- fell back to its drawn facsimile down there, so the cast lane previewed
-- against a capped stand-in while the primary lane wrapped the real mirror.
--
-- Read-only, and wearing the canvas's "icons stay in place" refusal: it is a
-- duplicate of entries the mirror above already owns, so a second set of
-- click targets for the same entries would only be ambiguous - which is
-- exactly the stance the facsimile it replaces took.
local function BuildUnifiedCastMirror(host, groupId)
    local inner = host._cdcUnifiedCastMirrorHost
    if not inner then
        inner = CreateFrame("Frame", nil, host)
        inner:SetClipsChildren(false)
        -- Wired once; the frame is reused by every later build.
        if ST._ApplyLayoutPreviewIconPanelClickShield then
            ST._ApplyLayoutPreviewIconPanelClickShield(inner)
        end
        host._cdcUnifiedCastMirrorHost = inner
    end
    inner:SetSize(UNIFIED_MEASURE_SIZE, UNIFIED_MEASURE_SIZE)
    inner:Show()
    -- applySessionFilter: this duplicate is a visible copy of the filtered
    -- interactive mirror above, not a saved-design tile, so the unavailable
    -- filter must reflow both copies identically.
    ST._BuildButtonPanelPreview(inner, groupId,
        { readOnly = true, applySessionFilter = true })
    ShrinkMirrorHostToContent(inner)
    return inner
end

-- The cast copy is dropped whenever the composition it belongs to is: a
-- horizontal layout that no longer asks for it, a view switch, config close.
-- The canvas hides the frame it borrowed on its own, but only the owner can
-- put the mirror inside it away.
local function ReleaseUnifiedCastMirror(host)
    local castHost = host._cdcUnifiedCastMirrorHost
    if not castHost then
        return
    end
    if ST._ReleaseReadOnlyPanelPreview then
        ST._ReleaseReadOnlyPanelPreview(castHost)
    end
    castHost:Hide()
end

local function BuildUnifiedAnchorPreview(host, groupId)
    local inner = host._cdcUnifiedMirrorHost
    if not inner then
        inner = CreateFrame("Frame", nil, host)
        inner:SetClipsChildren(false)
        host._cdcUnifiedMirrorHost = inner
    end
    inner:SetSize(UNIFIED_MEASURE_SIZE, UNIFIED_MEASURE_SIZE)
    inner:Show()
    -- The mirror's measured layout stays inside `inner`, which the caller
    -- shrinks to its content; `host` keeps the Live Preview's own chrome.
    -- The copy-customization banner pins to the outer host so it reads at
    -- the top of the whole Live Preview instead of over the entries.
    ST._BuildButtonPanelPreview(inner, groupId, { bannerHost = host })
    ShrinkMirrorHostToContent(inner)

    -- Instance 1 is this interactive mirror. Instance 2 is built only when
    -- the canvas asks for it - a horizontal layout never does, and building
    -- it up front would double the mirror cost of the common case. A build
    -- that stops asking (vertical to horizontal) puts it away again.
    local castMirrorUsed = false
    ST._BuildLayoutOrderPanel(host, {
        externalPanel = inner,
        panelFrameProvider = function(index)
            if index ~= 2 then
                return nil
            end
            castMirrorUsed = true
            return BuildUnifiedCastMirror(host, groupId)
        end,
    })
    if not castMirrorUsed then
        ReleaseUnifiedCastMirror(host)
    end
end

-- Single build entry for the wide buttons preview: unified when the panel
-- is the live anchor target with bars to show, the plain mirror otherwise.
-- Transitions release whichever surface is being vacated (the release
-- stops the conditional ticker, so it only runs when the surface actually
-- changes hands).
local function BuildAnchorAwarePanelPreview(host, groupId)
    -- Resolved once: the eligibility chain ends in a full lane-slot collect,
    -- so the badge and the render branch share one answer per build.
    local eligible = IsUnifiedAnchorPreviewEligible(groupId)
    UpdateAttachedBarsBadge(host, eligible)
    UpdateUnavailableEntriesBadge(host, groupId, eligible)
    if eligible and not CS.unifiedAnchorBarsHidden then
        local plain = host._cdcPanelPreview
        if plain and plain.root and plain.root:IsShown() then
            ST._ReleaseButtonPanelPreview(host)
        end
        BuildUnifiedAnchorPreview(host, groupId)
        return
    end

    local inner = host._cdcUnifiedMirrorHost
    if inner and inner:IsShown() then
        if ST._ReleaseButtonPanelPreview then
            ST._ReleaseButtonPanelPreview(inner)
        end
        inner:Hide()
    end
    ReleaseUnifiedCastMirror(host)
    local lanes = host._cdcLayoutPreview
    if lanes and lanes.root and lanes.root:IsShown() then
        lanes.root:Hide()
    end
    ST._BuildButtonPanelPreview(host, groupId)
end

-- Full release for view switches and config close: both the plain mirror
-- and the unified composition (inner mirror + lanes) go quiet.
local function ReleaseAnchorAwarePanelPreview(host)
    if host._cdcAttachedBarsBadge then
        host._cdcAttachedBarsBadge:Hide()
    end
    if host._cdcUnavailableEntriesBadge then
        host._cdcUnavailableEntriesBadge:Hide()
    end
    if ST._ReleaseButtonPanelPreview then
        ST._ReleaseButtonPanelPreview(host)
        if host._cdcUnifiedMirrorHost then
            ST._ReleaseButtonPanelPreview(host._cdcUnifiedMirrorHost)
        end
    end
    if host._cdcUnifiedMirrorHost then
        host._cdcUnifiedMirrorHost:Hide()
    end
    ReleaseUnifiedCastMirror(host)
    local lanes = host._cdcLayoutPreview
    if lanes and lanes.root then
        lanes.root:Hide()
    end
end

------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
ST._ShouldUseUnifiedAnchorPreview = ShouldUseUnifiedAnchorPreview
ST._BuildAnchorAwarePanelPreview = BuildAnchorAwarePanelPreview
ST._ReleaseAnchorAwarePanelPreview = ReleaseAnchorAwarePanelPreview
