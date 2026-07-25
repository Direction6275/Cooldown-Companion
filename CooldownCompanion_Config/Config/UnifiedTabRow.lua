--[[
    CooldownCompanion - Config/UnifiedTabRow
    One visual tab row across two AceGUI TabGroups: the panel-scope strip
    owned by GroupSettingsHost on the left, and whichever detail strip is
    up on the right - the entry tabs from Panel.lua, or one of the
    attached-bar surfaces in ResourcesWideColumn. The groups stay separate,
    each keeping its own content pipeline, scroll restore and info-button
    lifecycle; only their tab strips are made to share a row.

    Selecting an entry or a bar appends its tabs to the right of the panel
    tabs, pinned to the right edge so the clear space between the clusters
    carries the resize; when they no longer fit, the row is split between
    them and both wrap. Exactly one tab reads as selected across the row,
    and only the scope that owns the surface shows content, so a panel tab
    can be opened without dropping the entry or bar selection.
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

local function GetPanelStrip()
    local col3 = CS.configFrame and CS.configFrame.col3
    local host = col3 and col3.groupSettingsHost
    if not (host and host:IsShown()) then return nil end
    local tabGroup = host.tabGroup
    if not (tabGroup and tabGroup.frame:IsShown()) then return nil end
    return tabGroup
end

-- Every strip that can take the right-hand slot registers here: the entry
-- tabs and the attached-bar surfaces (resource, cast, custom). Only one is
-- ever shown at a time - the workspace hides the others before showing the
-- one it wants - so the detail cluster is simply whichever is up.
local detailStrips = {}

local function GetDetailStrip()
    local panel = GetPanelStrip()
    for _, tabGroup in ipairs(detailStrips) do
        if tabGroup ~= panel and tabGroup.frame:IsShown() then
            return tabGroup
        end
    end
    return nil
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
    local panel = GetPanelStrip()
    local detail = GetDetailStrip()

    local full = 0
    if panel then
        BuildStrip(panel, NATURAL_STRIP_BUDGET)
        panel._cdcStripOffset = 0
        full = panel.frame:GetWidth() or 0
    end
    if detail then
        BuildStrip(detail, NATURAL_STRIP_BUDGET)
        detail._cdcStripOffset = 0
        full = math.max(full, detail.frame:GetWidth() or 0)
    end

    local panelWidth = panel and MeasureStripWidth(panel) or 0
    local detailWidth = detail and MeasureStripWidth(detail) or 0

    if panelWidth > 0 and detailWidth > 0 then
        if panelWidth + MIN_CLUSTER_GAP + detailWidth <= full then
            -- Both clusters fit side by side: panel tabs stay put on the
            -- left and the detail cluster is pinned to the right edge, so
            -- the clear space between them carries the resize.
            detail._cdcStripOffset = full - detailWidth
        else
            -- Too tight for one row. Split the row between the clusters in
            -- proportion to their natural widths so they wrap by the same
            -- amount and the stack stays balanced, instead of one of them
            -- absorbing all of it.
            local available = math.max(MIN_STRIP_WIDTH * 2, full - MIN_CLUSTER_GAP)
            local panelShare = math.floor(available * panelWidth / (panelWidth + detailWidth))
            panelShare = math.max(MIN_STRIP_WIDTH, panelShare)
            local detailShare = math.max(MIN_STRIP_WIDTH, available - panelShare)
            BuildStrip(panel, panelShare)
            BuildStrip(detail, detailShare)
            detail._cdcStripOffset = panelShare + MIN_CLUSTER_GAP
        end
    elseif detailWidth > full and full > 0 then
        -- Detail cluster alone (the Resources and Cast Bar homes, Other
        -- Class browsing) and wider than the row.
        BuildStrip(detail, full)
    elseif panelWidth > full and full > 0 then
        BuildStrip(panel, full)
    end

    if panel then FinishStrip(panel) end
    if detail then FinishStrip(detail) end
    ApplyUnifiedRow()

    return trigger == panel or trigger == detail
end

-- Wraps the widget's own BuildTabs so every rebuild - SetTabs, a window
-- resize, and the deferred pass AceGUI schedules after one - re-lays the
-- whole row, and so a rebuild that changes the row count takes both
-- content panes with it.
local laying = false
local function InstallStripLayout(tabGroup, isDetailStrip)
    if not tabGroup or tabGroup._cdcUnifiedStrip then return end
    tabGroup._cdcUnifiedStrip = true
    if isDetailStrip then
        detailStrips[#detailStrips + 1] = tabGroup
    end

    tabGroup._cdcBaseBuildTabs = tabGroup.BuildTabs
    tabGroup.BuildTabs = function(self)
        if laying then
            -- Nested call from the row layout, which drives the base
            -- builder itself.
            self._cdcBaseBuildTabs(self)
            return
        end
        laying = true
        if not LayoutUnifiedRow(self) then
            -- This strip is not in the row right now (it or its host is
            -- hidden), so keep its own tabs current on their own terms; the
            -- row is laid out again when it comes back.
            self._cdcStripOffset = 0
            self._cdcRowShift = 0
            BuildStrip(self, NATURAL_STRIP_BUDGET)
            FinishStrip(self)
            PlaceStrip(self)
            RefreshStripAccent(self, false)
        end
        laying = false
    end
end

------------------------------------------------------------------------
-- Scope: which strip owns the settings surface
------------------------------------------------------------------------

-- The remembered scope only means anything while a detail cluster (an
-- entry, an entry multi-select, or an attached bar) is in the row; with
-- only panel tabs there, the panel strip always owns the surface.
local function GetScope()
    return CS.unifiedRowScope == "panel" and "panel" or "detail"
end

local function SetScope(scope)
    CS.unifiedRowScope = (scope == "panel") and "panel" or "detail"
end

-- Asked by the detail surfaces before they select a tab: panel scope only
-- means anything where there are panel tabs to have selected. A stale
-- "panel" carried into the Resources home or Other Class browsing must not
-- leave that workspace with nothing showing.
local function PanelOwnsSurface()
    return GetScope() == "panel" and GetPanelStrip() ~= nil
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

-- Run after both strips have been given their tabs and the owning scope
-- has selected its tab: harmonises the row count and enforces one
-- selected tab across the row. Re-entrant guard: the row-count pass moves
-- a border, which can cascade a layout back through a strip.
local applying = false
function ApplyUnifiedRow()
    if applying then return end
    applying = true

    local panel = GetPanelStrip()
    local detail = GetDetailStrip()

    local rows = 1
    if detail then
        rows = math.max(rows, detail._cdcRowCount or 1)
    end
    ApplyRowCount(panel, rows)
    ApplyRowCount(detail, rows)

    -- With a detail cluster in the row the remembered scope decides; with
    -- only panel tabs there, they own the surface by default.
    local panelActive
    if detail then
        panelActive = PanelOwnsSurface()
    else
        panelActive = panel ~= nil
    end
    SetStripActive(panel, panelActive)
    SetStripActive(detail, not panelActive)

    -- Last: selection has settled across both strips, so the tint can be
    -- lifted off whichever tab now reads as selected. Only the detail
    -- cluster wears it, and only while it shares the row.
    if panel then RefreshStripAccent(panel, false) end
    if detail then RefreshStripAccent(detail, panel ~= nil) end

    applying = false
end

------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
-- Every strip installs the same layout; pass true for the ones that can
-- take the right-hand slot (entry tabs, attached-bar surfaces).
ST._UnifiedRowInstallStrip = InstallStripLayout
ST._UnifiedRowGetScope = GetScope
ST._UnifiedRowSetScope = SetScope
ST._UnifiedRowPanelOwnsSurface = PanelOwnsSurface
ST._UnifiedRowApply = ApplyUnifiedRow
