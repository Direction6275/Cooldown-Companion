--[[
    CooldownCompanion - Config/UnifiedTabRow
    One visual tab row spanning the two AceGUI TabGroups of the buttons
    workspace: the panel-scope strip owned by GroupSettingsHost and the
    entry-scope strip created in Panel.lua. The groups stay separate -
    each keeps its own content pipeline, scroll restore and info-button
    lifecycle - and only their tab strips are made to share a row.

    Panel tabs are pinned to a single natural-width row on the left and
    never reflow. Selecting an entry appends that entry's tabs after a
    tab-width gap; they wrap inside whatever space is left. Exactly one
    tab reads as selected across both strips, and only the scope that owns
    the surface shows content, so a panel tab can be opened without
    dropping the entry selection.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

-- The entry cluster is right-aligned, so the clear space between the two
-- clusters is normally whatever the window leaves over - it grows and
-- shrinks as the window is resized. This is the floor: once the clusters
-- would be closer than this, the entry cluster stops tracking the right
-- edge and wraps instead. Delineation also carries the entry icon at the
-- cluster head and the accent tint (applied by the tab-text builders).
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

local function GetEntryStrip()
    local col3 = CS.configFrame and CS.configFrame.col3
    return col3 and col3.bsTabGroup or nil
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
            tab._cdcBase = { point, relativePoint, x or 0, y or 0 }
        else
            tab._cdcBase = nil
        end
    end
end

local function PlaceStrip(tabGroup)
    local dx = tabGroup._cdcStripOffset or 0
    local dy = tabGroup._cdcRowShift or 0
    for _, tab in ipairs(tabGroup.tabs) do
        local base = tab._cdcBase
        if base then
            tab:SetPoint(base[1], tabGroup.frame, base[2], base[3] + dx, base[4] - dy)
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
    local entry = GetEntryStrip()
    if entry and not entry.frame:IsShown() then entry = nil end

    local full = 0
    if panel then
        BuildStrip(panel, NATURAL_STRIP_BUDGET)
        panel._cdcStripOffset = 0
        full = panel.frame:GetWidth() or 0
    end
    if entry then
        BuildStrip(entry, NATURAL_STRIP_BUDGET)
        entry._cdcStripOffset = 0
        full = math.max(full, entry.frame:GetWidth() or 0)
    end

    local panelWidth = panel and MeasureStripWidth(panel) or 0
    local entryWidth = entry and MeasureStripWidth(entry) or 0

    if panelWidth > 0 and entryWidth > 0 then
        if panelWidth + MIN_CLUSTER_GAP + entryWidth <= full then
            -- Both clusters fit side by side: panel tabs stay put on the
            -- left and the entry cluster is pinned to the right edge, so
            -- the clear space between them carries the resize.
            entry._cdcStripOffset = full - entryWidth
        else
            -- Too tight for one row. Split the row between the clusters in
            -- proportion to their natural widths so they wrap by the same
            -- amount and the stack stays balanced, instead of the entry
            -- cluster absorbing all of it.
            local available = math.max(MIN_STRIP_WIDTH * 2, full - MIN_CLUSTER_GAP)
            local panelShare = math.floor(available * panelWidth / (panelWidth + entryWidth))
            panelShare = math.max(MIN_STRIP_WIDTH, panelShare)
            local entryShare = math.max(MIN_STRIP_WIDTH, available - panelShare)
            BuildStrip(panel, panelShare)
            BuildStrip(entry, entryShare)
            entry._cdcStripOffset = panelShare + MIN_CLUSTER_GAP
        end
    elseif entryWidth > full and full > 0 then
        -- Entry cluster alone (Other Class browsing hides the panel tabs)
        -- and wider than the row.
        BuildStrip(entry, full)
    elseif panelWidth > full and full > 0 then
        BuildStrip(panel, full)
    end

    if panel then FinishStrip(panel) end
    if entry then FinishStrip(entry) end
    ApplyUnifiedRow()

    return trigger == panel or trigger == entry
end

-- Wraps the widget's own BuildTabs so every rebuild - SetTabs, a window
-- resize, and the deferred pass AceGUI schedules after one - re-lays the
-- whole row, and so a rebuild that changes the row count takes both
-- content panes with it.
local laying = false
local function InstallStripLayout(tabGroup)
    if not tabGroup or tabGroup._cdcUnifiedStrip then return end
    tabGroup._cdcUnifiedStrip = true

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
        end
        laying = false
    end
end

------------------------------------------------------------------------
-- Scope: which strip owns the settings surface
------------------------------------------------------------------------

-- The remembered scope only means anything while an entry is selected;
-- with no entry cluster in the row the panel strip always owns the
-- surface.
local function GetScope()
    return CS.unifiedRowScope == "panel" and "panel" or "entry"
end

local function SetScope(scope)
    CS.unifiedRowScope = (scope == "panel") and "panel" or "entry"
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
    local entry = GetEntryStrip()
    local entryShown = entry and entry.frame:IsShown() or false

    local rows = 1
    if entryShown then
        rows = math.max(rows, entry._cdcRowCount or 1)
    end
    ApplyRowCount(panel, rows)
    ApplyRowCount(entry, rows)

    local scope = entryShown and GetScope() or "panel"
    if scope == "panel" and not panel and entryShown then
        -- No panel strip in the row (Other Class browsing hides it): the
        -- entry cluster is the only thing that can own the surface.
        scope = "entry"
    end
    SetStripActive(panel, scope == "panel")
    if entry then
        SetStripActive(entry, entryShown and scope == "entry")
    end

    applying = false
end

------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
-- Both strips install the same layout: which cluster a strip is comes from
-- where it sits in the row, not from how it was registered.
ST._UnifiedRowInstallStrip = InstallStripLayout
ST._UnifiedRowGetScope = GetScope
ST._UnifiedRowSetScope = SetScope
ST._UnifiedRowApply = ApplyUnifiedRow
