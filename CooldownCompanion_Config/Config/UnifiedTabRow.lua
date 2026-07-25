--[[
    CooldownCompanion - Config/UnifiedTabRow
    One visual tab row across two AceGUI TabGroups. On the left, the strip
    that scopes the workspace: panel settings in the buttons workspace,
    module settings in the Resources home. On the right, whichever detail
    strip is up: entry tabs, entry multi-select, or an attached-bar
    surface. The groups stay separate, each keeping its own content
    pipeline, scroll restore and info-button lifecycle; only their tab
    strips are made to share a row.

    Selecting an entry or a bar appends its tabs to the right, pinned to
    the right edge so the clear space between the clusters carries the
    resize; when they no longer fit, the row is split between them and both
    wrap. Exactly one tab reads as selected across the row, and only the
    scope that owns the surface shows content, so a left-hand tab can be
    opened without dropping the entry or bar selection.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

-- The detail cluster is right-aligned, so the clear space between the two
-- clusters is normally whatever the window leaves over - it grows and
-- shrinks as the window is resized. This is the floor: once the clusters
-- would be closer than this, the row is split between them instead.
-- Delineation also carries the entry icon at the cluster head (entry tabs)
-- and the accent tint, both supplied by the tab-text builders.
local MIN_CLUSTER_GAP = 40

-- AceGUI BuildTabs geometry, mirrored here so the strips can be re-laid
-- out without duplicating its row math: rows sit 20px apart, an untitled
-- strip starts 10px down, and neighbouring tabs overlap by 10px.
local TAB_ROW_PITCH = 20
local TAB_STRIP_INSET = 10
local TAB_OVERLAP = 10

-- Wrap budget that makes BuildTabs lay a strip out at natural widths on a
-- single row: too wide to wrap, and too wide to trip the rule that pads a
-- tight row out to fill its width. Both clusters are measured and drawn
-- this way whenever they fit, so every tab in the row is sized alike.
local NATURAL_STRIP_BUDGET = 100000

-- Floor for a cluster's share of a wrapped row. Below this a cluster is
-- unusable as a strip, so it is allowed to run past its share instead (the
-- accepted narrow-window edge) rather than wrapping one tab per row.
local MIN_STRIP_WIDTH = 120

------------------------------------------------------------------------
-- Strip geometry
------------------------------------------------------------------------

-- Rendered width of a strip's leading row, matching how BuildTabs chains
-- tabs (each anchored 10px into its predecessor).
local function MeasureStripWidth(tabGroup)
    if not tabGroup then return 0 end
    local total, count = 0, 0
    for _, tab in ipairs(tabGroup.tabs) do
        if tab:IsShown() then
            total = total + (tab:GetWidth() or 0)
            count = count + 1
        end
    end
    if count == 0 then return 0 end
    return total - TAB_OVERLAP * (count - 1)
end

-- Every strip registers as one of two roles. Primary strips take the left
-- of the row and stay put: the panel settings in the buttons workspace,
-- the shared resource settings in the Resources home. Detail strips take
-- the right when something is selected: entry tabs, entry multi-select,
-- and the attached-bar surfaces. A workspace hides the strips it is not
-- using before showing the ones it is, so each role has at most one strip
-- visible and the row is simply whichever two those are.
local primaryStrips = {}
local detailStrips = {}

local function GetVisibleStrip(registry)
    for _, tabGroup in ipairs(registry) do
        -- IsVisible, not IsShown: the panel strip lives inside a host frame
        -- that whole branches hide without touching the strip itself.
        if tabGroup.frame:IsVisible() then
            return tabGroup
        end
    end
    return nil
end

local function GetPrimaryStrip()
    return GetVisibleStrip(primaryStrips)
end

local function GetDetailStrip()
    return GetVisibleStrip(detailStrips)
end

local function GetStripRowCount(tabGroup)
    local offset = tabGroup.borderoffset or (TAB_STRIP_INSET + TAB_ROW_PITCH)
    local rows = math.floor(((offset - TAB_STRIP_INSET) / TAB_ROW_PITCH) + 0.5)
    if rows < 1 then rows = 1 end
    return rows
end

-- BuildTabs reads self.frame.width in preference to the frame's real
-- width. Setting the field lets a strip wrap inside a sub-range of its
-- frame while the frame itself keeps covering the whole settings rect,
-- which is what its content pane needs.
local function BuildStrip(tabGroup, budget)
    tabGroup.frame.width = budget
    tabGroup._cdcBaseBuildTabs(tabGroup)
end

-- BuildTabs anchors the first tab of every row to the group's frame and
-- chains the rest off it, so moving the row leaders moves whole rows. The
-- anchors BuildTabs just wrote are recorded as the baseline, and every
-- placement is measured from it, so placing a strip twice is a no-op.
local function CaptureStripAnchors(tabGroup)
    for _, tab in ipairs(tabGroup.tabs) do
        local point, relativeTo, relativePoint, x, y = tab:GetPoint(1)
        if tab:IsShown() and point and relativeTo == tabGroup.frame then
            tab._cdcBasePoint, tab._cdcBaseRelPoint = point, relativePoint
            tab._cdcBaseX, tab._cdcBaseY = x or 0, y or 0
        else
            tab._cdcBasePoint = nil
        end
    end
end

local function PlaceStrip(tabGroup)
    local dx = tabGroup._cdcStripOffset or 0
    local dy = tabGroup._cdcRowShift or 0
    for _, tab in ipairs(tabGroup.tabs) do
        if tab._cdcBasePoint then
            tab:SetPoint(tab._cdcBasePoint, tabGroup.frame, tab._cdcBaseRelPoint,
                tab._cdcBaseX + dx, tab._cdcBaseY - dy)
        end
    end
end

-- The accent tint lives in the label text as a colour escape, because
-- PanelTemplates rewrites tab fontstring colours on every select, deselect
-- and hover. Selection still has to read though, so the selected tab drops
-- the tint and takes the standard highlight colour while its neighbours
-- keep it. Written straight to the fontstring: tab:SetText would re-measure
-- and resize the tab outside BuildTabs' padding pass.
--
-- The tint marks a cluster as the second one in the row, so it is only
-- worn when there is a first cluster to be told apart from: a strip that
-- owns the whole row (the Resources and Cast Bar homes, Other Class
-- browsing) reads as plain tabs.
local function RefreshStripAccent(tabGroup, tinted)
    local tablist = tabGroup.tablist
    if not tablist then return end
    for index, entry in ipairs(tablist) do
        local tab = tabGroup.tabs[index]
        if tab and entry.accentText then
            tab.Text:SetText((tinted and not tab.selected) and entry.accentText or entry.text)
        end
    end
end

-- Both strips share the row, so both content panes must clear the tallest
-- one; otherwise a wrapped entry row draws over panel-scope content. The
-- shorter strip drops to the bottom row so its tabs still sit on the pane
-- edge rather than floating above a band of empty space.
local function ApplyRowCount(tabGroup, rows)
    if not tabGroup then return end
    local offset = TAB_STRIP_INSET + rows * TAB_ROW_PITCH
    tabGroup.borderoffset = offset
    tabGroup.border:SetPoint("TOPLEFT", 1, -offset)
    tabGroup._cdcRowShift = math.max(0, rows - (tabGroup._cdcRowCount or 1)) * TAB_ROW_PITCH
    PlaceStrip(tabGroup)
end

local ApplyUnifiedRow

local function FinishStrip(tabGroup)
    CaptureStripAnchors(tabGroup)
    tabGroup._cdcRowCount = GetStripRowCount(tabGroup)
end

-- Lays out the whole row at once: both clusters are measured at natural
-- widths, and only then is it known whether they fit side by side. Either
-- strip's rebuild runs this, so the two can never be laid out against
-- different assumptions.
local function LayoutUnifiedRow(trigger)
    local primary = GetPrimaryStrip()
    local detail = GetDetailStrip()

    local full = 0
    if primary then
        BuildStrip(primary, NATURAL_STRIP_BUDGET)
        primary._cdcStripOffset = 0
        full = primary.frame:GetWidth() or 0
    end
    if detail then
        BuildStrip(detail, NATURAL_STRIP_BUDGET)
        detail._cdcStripOffset = 0
        full = math.max(full, detail.frame:GetWidth() or 0)
    end

    local primaryWidth = primary and MeasureStripWidth(primary) or 0
    local detailWidth = detail and MeasureStripWidth(detail) or 0

    if full <= 0 then
        -- No usable width yet (a first pass before the rect resolves).
        -- Leave both at natural; AceGUI's deferred rebuild re-runs this.
    elseif primaryWidth > 0 and detailWidth > 0 then
        if primaryWidth + MIN_CLUSTER_GAP + detailWidth <= full then
            -- Both clusters fit side by side: the primary tabs stay put on
            -- the left and the detail cluster is pinned to the right edge,
            -- so the clear space between them carries the resize.
            detail._cdcStripOffset = full - detailWidth
        else
            -- Too tight for one row. Split the row between the clusters in
            -- proportion to their natural widths so they wrap by the same
            -- amount and the stack stays balanced, instead of one of them
            -- absorbing all of it.
            local available = math.max(MIN_STRIP_WIDTH * 2, full - MIN_CLUSTER_GAP)
            local primaryShare = math.floor(available * primaryWidth / (primaryWidth + detailWidth))
            primaryShare = math.max(MIN_STRIP_WIDTH, primaryShare)
            local detailShare = math.max(MIN_STRIP_WIDTH, available - primaryShare)
            BuildStrip(primary, primaryShare)
            BuildStrip(detail, detailShare)
            detail._cdcStripOffset = primaryShare + MIN_CLUSTER_GAP
        end
    elseif math.max(primaryWidth, detailWidth) > full then
        -- One cluster owning the whole row (nothing selected, or a
        -- workspace with no primary tabs) and wider than it: let it wrap.
        BuildStrip((detailWidth > 0) and detail or primary, full)
    end

    if primary then FinishStrip(primary) end
    if detail then FinishStrip(detail) end
    ApplyUnifiedRow()

    return trigger == primary or trigger == detail
end

-- Wraps the widget's own BuildTabs so every rebuild - SetTabs, a window
-- resize, and the deferred pass AceGUI schedules after one - re-lays the
-- whole row, and so a rebuild that changes the row count takes both
-- content panes with it.
local laying = false
local function InstallStripLayout(tabGroup, role)
    if not tabGroup or tabGroup._cdcUnifiedStrip then return end
    tabGroup._cdcUnifiedStrip = true
    local registry = (role == "detail") and detailStrips or primaryStrips
    registry[#registry + 1] = tabGroup

    -- Selecting a tab fires its group's builder synchronously, which means
    -- the row is settled by the time this returns: re-apply it here rather
    -- than asking every builder callback to remember to.
    local baseSelectTab = tabGroup.SelectTab
    tabGroup.SelectTab = function(self, value)
        baseSelectTab(self, value)
        ApplyUnifiedRow()
    end

    tabGroup._cdcBaseBuildTabs = tabGroup.BuildTabs
    tabGroup.BuildTabs = function(self)
        if laying then
            -- Nested call from the row layout, which drives the base
            -- builder itself.
            self._cdcBaseBuildTabs(self)
            return
        end
        -- Nothing else would ever clear this guard, so an error inside the
        -- layout pass would leave it set and silently disable the row for
        -- the rest of the session. Clear it either way and let the error
        -- carry on to the handler untouched.
        laying = true
        local ok, result = pcall(LayoutUnifiedRow, self)
        laying = false
        if not ok then error(result, 0) end

        if not result then
            -- This strip is not in the row right now (it or its host is
            -- hidden), so keep its own tabs current on their own terms; the
            -- row is laid out again when it comes back. No guard needed:
            -- this path drives the base builder directly.
            self._cdcStripOffset = 0
            self._cdcRowShift = 0
            BuildStrip(self, NATURAL_STRIP_BUDGET)
            FinishStrip(self)
            PlaceStrip(self)
            RefreshStripAccent(self, false)
        end
    end
end

------------------------------------------------------------------------
-- Scope: which strip owns the settings surface
------------------------------------------------------------------------

-- The remembered scope only means anything while a detail cluster (an
-- entry, an entry multi-select, an attached bar) is in the row; with only
-- the primary tabs there, they always own the surface.
local function GetScope()
    return CS.unifiedRowScope == "primary" and "primary" or "detail"
end

local function SetScope(scope)
    CS.unifiedRowScope = (scope == "primary") and "primary" or "detail"
end

-- Asked by the detail surfaces before they select a tab: primary scope
-- only means anything where there are primary tabs to have selected. A
-- stale "primary" carried into a workspace without them (the Cast Bar
-- home, Other Class browsing) must not leave it with nothing showing.
local function PrimaryOwnsSurface()
    return GetScope() == "primary" and GetPrimaryStrip() ~= nil
end

local function SetStripActive(tabGroup, active)
    if not tabGroup then return end
    if active then
        tabGroup.content:Show()
        tabGroup.border:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
        tabGroup.border:SetBackdropBorderColor(0.4, 0.4, 0.4)
        return
    end
    -- Tabs are children of the border frame, so the pane is dropped by
    -- clearing its backdrop and hiding the content frame rather than by
    -- hiding the border itself.
    tabGroup.content:Hide()
    tabGroup.border:SetBackdropColor(0, 0, 0, 0)
    tabGroup.border:SetBackdropBorderColor(0, 0, 0, 0)
    for _, tab in ipairs(tabGroup.tabs) do
        tab:SetSelected(false)
    end
end

local function ApplyRowState()
    local primary = GetPrimaryStrip()
    local detail = GetDetailStrip()

    -- The tallest strip sets the row height for both, whichever one it is.
    -- Reading only the detail cluster here would leave a primary that wraps
    -- deeper drawing its last row over its own content pane.
    local rows = math.max(
        primary and primary._cdcRowCount or 1,
        detail and detail._cdcRowCount or 1
    )
    ApplyRowCount(primary, rows)
    ApplyRowCount(detail, rows)

    -- With a detail cluster in the row the remembered scope decides; with
    -- only the primary tabs there, they own the surface by default.
    local primaryActive
    if detail then
        primaryActive = PrimaryOwnsSurface()
    else
        primaryActive = primary ~= nil
    end
    SetStripActive(primary, primaryActive)
    SetStripActive(detail, not primaryActive)

    -- Last: selection has settled across both strips, so the tint can be
    -- lifted off whichever tab now reads as selected. Only the detail
    -- cluster wears it, and only while it shares the row.
    if primary then RefreshStripAccent(primary, false) end
    if detail then RefreshStripAccent(detail, primary ~= nil) end
end

-- Run after both strips have been given their tabs and the owning scope
-- has selected its tab: harmonises the row count and enforces one selected
-- tab across the row. Re-entrant guard: the row-count pass moves a border,
-- which can cascade a layout back through a strip. Same reasoning as the
-- layout guard above - the flag is cleared even when the pass raises, so
-- one error cannot leave the row disabled for the session.
local applying = false
function ApplyUnifiedRow()
    if applying then return end

    applying = true
    local ok, err = pcall(ApplyRowState)
    applying = false
    if not ok then error(err, 0) end
end

------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
-- Every strip installs the same layout; the role decides which side of the
-- row it takes ("primary" is the default, "detail" the right-hand slot).
ST._UnifiedRowInstallStrip = InstallStripLayout
ST._UnifiedRowGetScope = GetScope
ST._UnifiedRowSetScope = SetScope
ST._UnifiedRowPrimaryOwnsSurface = PrimaryOwnsSurface
ST._UnifiedRowApply = ApplyUnifiedRow
