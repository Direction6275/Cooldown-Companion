--[[
    CooldownCompanion - UnifiedAnchorPreview
    The buttons view's panel preview build: the real button-panel mirror
    (attached resource and cast bars render inside it) plus its two quick
    toggle badges, the attached-bars pin and the unavailable-entries eye.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

-- The attached-bars badge: the same pin the group overview stamps on the
-- anchor panel's tile, worn here as a quick toggle in the preview's
-- top-right corner (the inside corner opposite the command center).
local BADGE_ATLAS = "Waypoint-MapPin-Tracked"
-- Its untracked twin (same atlas page and size) while the lanes are hidden.
local BADGE_HIDDEN_ATLAS = "Waypoint-MapPin-Untracked"
-- The pin atlas carries transparent margins of its own, so the frame hugs
-- the corner tighter than the spellbook badge's numbers to LOOK the same
-- distance in.
local BADGE_SIZE = 20
local BADGE_INSET = 1

-- The command center gates on the same test the attached bars render with.
-- Hidden bars remain editable through the workspace's selection links.
local function ShouldUseUnifiedAnchorPreview(groupId)
    local group = groupId and CooldownCompanion.db.profile.groups[groupId]
    return ST.PanelSupportsAttachedBars(group)
        and not CS.unifiedAnchorBarsHidden
        and ST._HasAttachedBarLanesToRender(groupId) == true
end

------------------------------------------------------------------------
-- The quick toggle: hide the attached bar lanes from this preview
------------------------------------------------------------------------

-- Shared badge chrome. Each toggle supplies its own state, text, refresh
-- behavior and positioning; this owns only the identical frame interaction.
-- A toggle with a hidden-state atlas swaps its art with its state.
local function ApplyPreviewBadgeArt(badge)
    if badge._cdcHiddenAtlas then
        badge.icon:SetAtlas(badge._cdcIsHidden() and badge._cdcHiddenAtlas or badge._cdcAtlas, false)
    end
end

local function ApplyPreviewBadgeHover(badge)
    ApplyPreviewBadgeArt(badge)
    badge.icon:SetDesaturated(false)
    badge.icon:SetVertexColor(1, 1, 1, 1)
end

local function ApplyPreviewBadgeTint(badge)
    if badge._cdcIsHidden() then
        ApplyPreviewBadgeArt(badge)
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

local function CreatePreviewToggleBadge(host, atlas, isHidden, showText, hideText, onClick, hiddenAtlas, artSize)
    local badge = CreateFrame("Button", nil, host)
    badge:SetSize(BADGE_SIZE, BADGE_SIZE)
    badge.icon = badge:CreateTexture(nil, "ARTWORK")
    -- Heavily padded art draws larger around the same hit frame and slot.
    if artSize then
        badge.icon:SetSize(artSize, artSize)
        badge.icon:SetPoint("CENTER")
    else
        badge.icon:SetAllPoints()
    end
    badge.icon:SetAtlas(atlas, false)
    badge._cdcAtlas = atlas
    badge._cdcHiddenAtlas = hiddenAtlas
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
    -- Rebuild the fallback selection links as well as the canvas, including
    -- when no bar was selected before hiding the lanes.
    CooldownCompanion:RefreshConfigPanel()
end

-- Session state, view only: the flag lives in CS and the live bars never
-- move. Shown whenever the panel draws attached bars, hidden or not, so
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
            ToggleAttachedBars,
            BADGE_HIDDEN_ATLAS
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
-- The second quick toggle: hide unavailable or disabled entries from the
-- focused mirror
------------------------------------------------------------------------

-- An eye that shows the state: open while every entry that cannot show
-- (greyed, disabled, or naming a spell or item that no longer exists) is
-- visible, crossed (the preview's "not shown right now" art, as on the
-- Disabled badge and a bar's hidden mark) while they are hidden. Not the red
-- warning triangle: that marks only the missing ones. Sits one badge width
-- inside the attached-bars pin when the pin is up, and takes the pin's
-- corner spot when it is not.
local UNAVAILABLE_BADGE_ATLAS = "GM-icon-visible-pressed"
local UNAVAILABLE_HIDDEN_BADGE_ATLAS = "GM-icon-visibleDis-pressed"
-- The eye atlases pad their glyph heavily; drawn at the badge frame's size
-- the eye reads smaller than the pin beside it.
local UNAVAILABLE_BADGE_ART_SIZE = 26
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
            "Show unavailable and disabled entries",
            "Hide unavailable and disabled entries",
            ToggleUnavailableEntries,
            UNAVAILABLE_HIDDEN_BADGE_ATLAS,
            UNAVAILABLE_BADGE_ART_SIZE
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

-- Single build entry for the wide buttons preview: the mirror (attached
-- bars render inside it) plus its quick-toggle badges. The bars test is
-- resolved once, so both badges share one answer per build.
local function BuildAnchorAwarePanelPreview(host, groupId, outcome)
    local group = groupId and CooldownCompanion.db.profile.groups[groupId]
    local hasModules = ST.PanelSupportsAttachedBars(group) and ST._HasAttachedBarLanesToRender(groupId) == true
    UpdateAttachedBarsBadge(host, hasModules)
    UpdateUnavailableEntriesBadge(host, groupId, hasModules)
    if not (outcome and ST._UpdateButtonPanelPreview(host, groupId, outcome)) then
        ST._BuildButtonPanelPreview(host, groupId)
    end
end

-- Full release for view switches and config close: the mirror and its
-- badges go quiet.
local function ReleaseAnchorAwarePanelPreview(host)
    if host._cdcAttachedBarsBadge then
        host._cdcAttachedBarsBadge:Hide()
    end
    if host._cdcUnavailableEntriesBadge then
        host._cdcUnavailableEntriesBadge:Hide()
    end
    if ST._ReleaseButtonPanelPreview then
        ST._ReleaseButtonPanelPreview(host)
    end
end

------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
ST._ShouldUseUnifiedAnchorPreview = ShouldUseUnifiedAnchorPreview
ST._BuildAnchorAwarePanelPreview = BuildAnchorAwarePanelPreview
ST._ReleaseAnchorAwarePanelPreview = ReleaseAnchorAwarePanelPreview
