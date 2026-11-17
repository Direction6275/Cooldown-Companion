local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState
local tonumber = tonumber

-- Imports from Helpers.lua
local BuildCollapsibleSection = ST._BuildCollapsibleSection
local CreateInfoButton = ST._CreateInfoButton
local AddAnchorDropdown = ST._AddAnchorDropdown
local GetCompactGrowthDirectionLabels = ST._GetCompactGrowthDirectionLabels
local NormalizeCompactGrowthDirection = ST.NormalizeCompactGrowthDirection
local BuildCompactModeControls = ST._BuildCompactModeControls

-- Imports from RowWidgets.lua (the row grammar)
local AddCheckboxRow = ST._AddCheckboxRow
local AddSliderRow = ST._AddSliderRow
local AddDropdownRow = ST._AddDropdownRow
local AnchorRowBadge = ST._AnchorRowBadge
local BeginRowGrid = ST._BeginRowGrid
local AddEditBoxRow = ST._AddEditBoxRow

-- Imports from GroupTabsShared.lua
local WireMirrorFirstSlider = ST._WireMirrorFirstSlider

-- Style lens (StyleLens.lua): only read here to know whether an entry selection
-- is active, so the panel-scope note can speak. Nothing in this tab lenses.
local ResolveStyleLens = ST._ResolveStyleLens
local AddLensPanelScopeNote = ST._AddLensPanelScopeNote

-- Imports from GroupTabsSpecial.lua
local OpenOrRebindIndicatorTexturePicker = ST._OpenOrRebindIndicatorTexturePicker

-- A dropdown sizes its menu from the 140px control it hangs under, which is
-- too narrow for user-named panels and the longer worded options below.
local WIDE_PULLOUT_WIDTH = 300

-- The per-section aura toggle's tooltip. What the section becomes, and what
-- that changes about the way it takes up room; the rest the surface teaches.
-- Lives with the row (the Panel Sections blocks below), which moved here from
-- the Appearance tab: what a cluster IS is layout grammar, and the Appearance
-- block keeps the cluster's size and spacing.
local AURA_SECTION_TOOLTIP = {
    "Aura Only Section",
    {"Only Aura entries can live here.", 1, 1, 1, true},
    " ",
    {"Active auras appear and pack together. Inactive auras take no space.", 1, 1, 1, true},
    {"Missing-aura effects are unavailable here because inactive auras have no reserved space.", 1, 1, 1, true},
    " ",
    {"Buffs on you and debuffs on your target can't share one section.", 1, 1, 1, true},
}

-- Row-grammar section headers: caret far left, label, then a class-colored
-- rule fading right.
local ROW_SECTION = { leftAligned = true }

------------------------------------------------------------------------
-- SETTINGS FINDER CATALOG
------------------------------------------------------------------------

local LAYOUT_FINDER = { sections = {}, layers = {} }
-- Layout never lenses into an entry. When an entry is selected this page
-- remains panel-owned, and Settings Finder must not offer it in entry scope.
local PRIMARY_LAYOUT_SCOPE = "panel"

-- Shared decisions take the caller's actual editing group and target memory.
-- All saved and UI-state writes stay outside.
local function ResolveLayoutAnchorState(group, preferredTargetMode)
    local isPanel = group.parentContainerId ~= nil
    local anchor = group.anchor or {}
    local panelContainerFrame, currentAnchor, currentAnchorGroupId, isCursorAnchor, targetMode
    local inferredFrame = false

    panelContainerFrame = isPanel and ("CooldownCompanionContainer" .. group.parentContainerId) or nil
    currentAnchor = anchor.relativeTo
    isCursorAnchor = isPanel
        and CooldownCompanion.IsCursorAnchor
        and CooldownCompanion:IsCursorAnchor(anchor)
        or false
    currentAnchorGroupId = type(currentAnchor) == "string"
        and currentAnchor:match("^CooldownCompanionGroup(%d+)$") or nil

    if isCursorAnchor then
        targetMode = "cursor"
    elseif currentAnchorGroupId and isPanel then
        targetMode = "panel"
    elseif isPanel and currentAnchor == "UIParent" and ST.IsIndicatorGroup(group)
        and preferredTargetMode ~= "panel" then
        -- An Indicator saved on the screen while inside a Group (owner
        -- ruling R8-fallback): a Frame target with no frame named, so
        -- "Group" stays a choice that re-attaches it. Inferred from the
        -- saved position, so it is not remembered as the player's choice.
        targetMode = "frame"
        inferredFrame = true
    elseif currentAnchor == nil or currentAnchor == "UIParent"
        or (isPanel and currentAnchor == panelContainerFrame) then
        targetMode = "group"
    else
        targetMode = "frame"
    end

    if (targetMode == "group" or targetMode == "cursor")
        and (preferredTargetMode == "frame"
            or (isPanel and preferredTargetMode == "panel")) then
        targetMode = preferredTargetMode
    end

    return {
        targetMode = targetMode,
        isPanel = isPanel,
        panelContainerFrame = panelContainerFrame,
        currentAnchor = currentAnchor,
        currentAnchorGroupId = currentAnchorGroupId,
        isCursorAnchor = isCursorAnchor,
        inferredFrame = inferredFrame,
    }
end

-- The wrap count is named for what it counts along the axis it fills first
-- (GroupFrameLayout: horizontal fills rows, vertical fills columns), the same
-- way a panel section's own wrap row reads.
local WRAP_COUNT_LABELS = {
    iconsPerRow = "Icons Per Row", iconsPerColumn = "Icons Per Column",
    barsPerRow = "Bars Per Row", barsPerColumn = "Bars Per Column",
}
local function WrapCountKey(group)
    local perRow = ST.GetPanelLayoutOrientation(group.displayMode, group.style or {}) == "horizontal"
    return (group.displayMode == "bars" and "bars" or "icons") .. (perRow and "PerRow" or "PerColumn")
end

local function ResolveLayoutArrangementState(group, layoutCount)
    local displayMode = group.displayMode or "icons"
    local isIndicator = displayMode == "indicator"
    local isAuraPanel = CooldownCompanion:IsAuraPanel(group)
    local isTotemPanel = ST.IsTotemPanelGroup(group)
    local showAll = group._settingsContext and group._settingsContext.mode ~= "entry"
    local isIconsMode = displayMode == "icons"
    local isBarMode = displayMode == "bars"
    local auraBarPanel = isBarMode and isAuraPanel

    return {
        showAll = showAll,
        isTotemPanel = isTotemPanel,
        auraBarPanel = auraBarPanel,
        allowCentered = not isAuraPanel and not isTotemPanel,
        horizontalBars = not isIndicator and isBarMode and (showAll or layoutCount > 1) and not auraBarPanel,
        orientation = not isIndicator and not isBarMode,
        growth = not isIndicator and (showAll or layoutCount > 1),
        collapse = not isIndicator and (isAuraPanel or isTotemPanel),
        -- Aura and Totem Panels take one form for every entry.
        panelForm = not isIndicator and (isAuraPanel or isTotemPanel),
        buttonsPerLine = not isIndicator and not auraBarPanel,
        compact = not isIndicator and not isAuraPanel and not isTotemPanel
            and (isIconsMode or isBarMode),
    }
end

local function HasLayoutIcons(group, groupId)
    local owner = group._attachedBarOwner or group
    return not ST.PanelSupportsAttachedBars(owner) or ST._GetPanelSettingsContents(owner, groupId).icons
end

local function HasCustomIconStrata(group, hasIcons)
    return (group.displayMode or "icons") == "icons" and not CooldownCompanion:IsAuraPanel(group)
        and not ST.IsTotemPanelGroup(group) and hasIcons
end

local function ResolveLayoutSectionState(group, sectionAnchor)
    local memberCount = 0
    for _, buttonData in ipairs(group.buttons or {}) do
        if ST.GetPanelSectionForEntry(group, buttonData) == sectionAnchor then
            memberCount = memberCount + 1
        end
    end
    local axis = ST.GetPanelSectionPlacement(group, sectionAnchor)
    return {
        auraOnly = true,
        xOffset = true,
        yOffset = true,
        axis = axis,
        memberCount = memberCount,
        iconsPerRow = axis == "h" and memberCount > 1,
        iconsPerColumn = axis == "v" and memberCount > 1,
    }
end

-- Finder prepares all Layout facts once per editing context. Builders use the
-- same decisions only where needed, without scanning sections just for Strata.
-- Search keystrokes continue to read the prepared descriptor booleans.
local function GetLayoutFinderState(context)
    if context and context._ccLayoutFinderState then return context._ccLayoutFinderState end
    local group = context and context.group
    if not group then return nil end
    local groupId = context.groupId
    local owner = group._attachedBarOwner or group
    local displayMode = group.displayMode or "icons"
    local isIndicator = displayMode == "indicator"
    local anchorState = ResolveLayoutAnchorState(group,
        CS.layoutAnchorTargetMode and CS.layoutAnchorTargetMode[groupId])
    local targetMode = anchorState.targetMode
    local buttonCount = ST.IsTotemPanelGroup(group) and GetNumTotemSlots() or #(group.buttons or {})
    local state = ResolveLayoutArrangementState(group, buttonCount)
    state.sections = {}
    context._ccLayoutFinderState = state

    state.anchorTarget = true
    state.anchorPanel = anchorState.isPanel and targetMode == "panel"
    state.anchorFrame = targetMode == "frame"
    state.autoAnchor = not isIndicator
        and CooldownCompanion:IsIconLikeDisplayMode(owner.displayMode)
        and not CooldownCompanion:IsAuraPanel(group)
        and not ST.IsTotemPanelGroup(group)

    state.panelPoint = targetMode == "cursor"
    state.anchorPoint = targetMode ~= "cursor"
    state.relativePoint = targetMode ~= "cursor"
    state.xOffset = true
    state.yOffset = true

    -- Structural, not compactLayout state: the gear now builds with Compact
    -- Mode off too, opening its panel read-only behind the Turn On footer, so
    -- the rows inside stay findable. Only the centered-growth restriction
    -- still hides the Collapse Direction row itself.
    state.compactAdvanced = state.compact
    local style = group.style or {}
    state.compactGrowth = state.compactAdvanced
        and ST.GetCenteredGrowthEdge(
            style.growthOrigin,
            ST.GetPanelLayoutOrientation(group.displayMode, style)
        ) == nil

    local hasIcons = HasLayoutIcons(group, groupId)
    state.customStrata = HasCustomIconStrata(group, hasIcons)
    state.frameStrata = true

    -- Finder visits both presentations; EntryPresentation's builder dispatch
    -- only calls BuildGridArrangement for the eligible grid presentation.
    -- Keep that routing gate separate from the shared grid row decisions.
    if (displayMode == "icons" and not hasIcons)
        or (group._attachedBarOwner and ST.GetPanelLayoutKind(owner) ~= "bars") then
        for _, key in ipairs({ "horizontalBars", "orientation", "growth", "collapse", "buttonsPerLine",
            "compact", "compactAdvanced", "compactGrowth" }) do state[key] = false end
    end
    if state.buttonsPerLine then state[WrapCountKey(group)] = true end

    if not isIndicator and hasIcons and ST.PanelSupportsSections(group)
        and type(group.sections) == "table" then
        for _, sectionAnchor in ipairs(ST.PANEL_SECTION_ANCHORS or {}) do
            local section = group.sections[sectionAnchor]
            if type(section) == "table" then
                state.sections[sectionAnchor] = ResolveLayoutSectionState(group, sectionAnchor)
            end
        end
    end

    return state
end

local function LayoutFinderFlag(key)
    return function(context)
        local state = GetLayoutFinderState(context)
        return state and state[key] == true or false
    end
end

local function LayoutFinderSectionFlag(anchor, key)
    return function(context)
        local state = GetLayoutFinderState(context)
        local section = state and state.sections[anchor]
        return section and section[key] == true or false
    end
end

if ST._DefineSettingRoute then
    local anchor = ST._DefineSettingRoute({
        idPrefix = "panel.layout.anchor",
        scope = PRIMARY_LAYOUT_SCOPE,
        tab = "layout",
        tabLabel = "Layout",
        section = "anchor",
        sectionLabel = "Position",
        collapseKeys = { "layout_anchor" },
        rowScope = "primary",
    })
    LAYOUT_FINDER.anchor = anchor:Settings({
        target = { label = "Anchor Target", aliases = { "anchor mode" }, applies = LayoutFinderFlag("anchorTarget") },
        panel = { label = "Anchor to Panel", aliases = { "parent panel" }, applies = LayoutFinderFlag("anchorPanel") },
        frame = { label = "Anchor to Frame", aliases = { "relative frame" }, applies = LayoutFinderFlag("anchorFrame") },
        autoAnchor = { label = "Include in Auto-Anchoring", aliases = { "auto anchor" }, applies = LayoutFinderFlag("autoAnchor") },
    })

    local position = ST._DefineSettingRoute({
        idPrefix = "panel.layout.position",
        scope = PRIMARY_LAYOUT_SCOPE,
        tab = "layout",
        tabLabel = "Layout",
        section = "position",
        sectionLabel = "Position",
        -- One section with the anchor target (see the builders).
        collapseKeys = { "layout_anchor" },
        rowScope = "primary",
    })
    LAYOUT_FINDER.position = position:Settings({
        panelPoint = { label = "Panel Point", aliases = { "anchor point" }, applies = LayoutFinderFlag("panelPoint") },
        -- An Indicator's points carry the panel names (owner ruling
        -- 2026-10-27); the older words stay searchable.
        anchorPoint = {
            label = "Anchor Point",
            aliases = { "panel point", "display point", "trigger point" },
            applies = LayoutFinderFlag("anchorPoint"),
        },
        relativePoint = {
            label = "Relative Point",
            aliases = { "target point", "screen point" },
            applies = LayoutFinderFlag("relativePoint"),
        },
        xOffset = { label = "X Offset", aliases = { "horizontal position" }, applies = LayoutFinderFlag("xOffset") },
        yOffset = { label = "Y Offset", aliases = { "vertical position" }, applies = LayoutFinderFlag("yOffset") },
    })

    local arrangement = ST._DefineSettingRoute({
        idPrefix = "panel.layout.arrangement",
        scope = PRIMARY_LAYOUT_SCOPE,
        tab = "layout",
        tabLabel = "Layout",
        section = "arrangement",
        sectionLabel = "Arrangement",
        collapseKeys = { "layout_arrangement" },
        rowScope = "primary",
    })
    LAYOUT_FINDER.arrangement = arrangement:Settings({
        panelForm = { label = "Display as", aliases = { "panel type", "switch to bars", "switch to icons" },
            applies = LayoutFinderFlag("panelForm") },
        horizontalBars = { label = "Horizontal Bar Layout", aliases = { "bar direction" }, applies = LayoutFinderFlag("horizontalBars") },
        orientation = { label = "Orientation", applies = LayoutFinderFlag("orientation") },
        growth = { label = "Growth Direction", applies = LayoutFinderFlag("growth") },
        collapse = { label = "Collapse Direction", applies = LayoutFinderFlag("collapse") },
        iconsPerRow = { label = "Icons Per Row", aliases = { "wrap count", "buttons per row" }, applies = LayoutFinderFlag("iconsPerRow") },
        iconsPerColumn = { label = "Icons Per Column", aliases = { "wrap count", "buttons per column" }, applies = LayoutFinderFlag("iconsPerColumn") },
        barsPerRow = { label = "Bars Per Row", aliases = { "wrap count", "buttons per row" }, applies = LayoutFinderFlag("barsPerRow") },
        barsPerColumn = { label = "Bars Per Column", aliases = { "wrap count", "buttons per column" }, applies = LayoutFinderFlag("barsPerColumn") },
        compact = { label = "Compact Mode", aliases = { "pack visible buttons" }, applies = LayoutFinderFlag("compact") },
    })

    local compact = ST._DefineSettingRoute({
        idPrefix = "panel.layout.arrangement.compact",
        scope = PRIMARY_LAYOUT_SCOPE,
        tab = "layout",
        tabLabel = "Layout",
        section = "arrangement",
        sectionLabel = "Compact Mode",
        collapseKeys = { "layout_arrangement" },
        rowScope = "primary",
        advancedKey = "compactLayout",
    })
    LAYOUT_FINDER.compact = compact:Settings({
        growth = { label = "Collapse Direction", aliases = { "growth direction" }, applies = LayoutFinderFlag("compactGrowth") },
        maxVisible = { label = "Max Visible Entries", aliases = { "button limit", "max visible buttons" }, applies = LayoutFinderFlag("compactAdvanced") },
    })

    for _, sectionAnchor in ipairs(ST.PANEL_SECTION_ANCHORS or {}) do
        local routeAnchor = sectionAnchor
        local route = ST._DefineSettingRoute({
            idPrefix = "panel.layout.section." .. tostring(routeAnchor),
            scope = PRIMARY_LAYOUT_SCOPE,
            tab = "layout",
            tabLabel = "Layout",
            section = "section_" .. tostring(routeAnchor),
            sectionLabel = (ST.PANEL_SECTION_ANCHOR_LABELS[routeAnchor] or tostring(routeAnchor)) .. " Section",
            collapseKeys = { "layout_section_" .. tostring(routeAnchor) },
            rowScope = "primary",
            applies = LayoutFinderSectionFlag(routeAnchor, "auraOnly"),
        })
        LAYOUT_FINDER.sections[routeAnchor] = route:Settings({
            auraOnly = { label = "Aura Only Section" },
            xOffset = { label = "X Offset", applies = LayoutFinderSectionFlag(routeAnchor, "xOffset") },
            yOffset = { label = "Y Offset", applies = LayoutFinderSectionFlag(routeAnchor, "yOffset") },
            iconsPerRow = { label = "Icons Per Row", applies = LayoutFinderSectionFlag(routeAnchor, "iconsPerRow") },
            iconsPerColumn = { label = "Icons Per Column", applies = LayoutFinderSectionFlag(routeAnchor, "iconsPerColumn") },
        })
    end

    local strata = ST._DefineSettingRoute({
        idPrefix = "panel.layout.strata",
        scope = PRIMARY_LAYOUT_SCOPE,
        tab = "layout",
        tabLabel = "Layout",
        section = "strata",
        sectionLabel = "Strata",
        collapseKeys = { "layout_strata" },
        rowScope = "primary",
    })
    LAYOUT_FINDER.strata = strata:Settings({
        frame = { label = "Frame Strata", aliases = { "panel layer" }, applies = LayoutFinderFlag("frameStrata") },
        custom = { label = "Custom Icon Strata", aliases = { "layer order" }, applies = LayoutFinderFlag("customStrata") },
    })

    local layerRoute = ST._DefineSettingRoute({
        idPrefix = "panel.layout.strata.layer",
        scope = PRIMARY_LAYOUT_SCOPE,
        tab = "layout",
        tabLabel = "Layout",
        section = "strata",
        sectionLabel = "Strata",
        collapseKeys = { "layout_strata" },
        rowScope = "primary",
        applies = LayoutFinderFlag("customStrata"),
        advancedKey = "customIconStrata",
    })
    local layerCount = #(ST.DEFAULT_STRATA_ORDER or {})
    for position = 1, layerCount do
        local label = position == layerCount and ("Layer " .. position .. " (Top)")
            or (position == 1 and "Layer 1 (Bottom)" or ("Layer " .. position))
        LAYOUT_FINDER.layers[position] = layerRoute:Setting({
            key = tostring(position),
            label = label,
            aliases = { "layer order", "strata" },
        })
    end
end

local tabInfoButtons = CS.tabInfoButtons

-- Early returns in here (a missing group) land
-- on the dispatch-level gear build pass's sweep (RunAdvancedGearBuildPass,
-- AdvancedSettingsPanel.lua).
local function BuildGridArrangement(container, group, layoutCount)
    local tabInfoButtons = CS.tabInfoButtons
    local state = ResolveLayoutArrangementState(group, layoutCount)
    local refreshStyle = ST._MakeConfigEditRefresh(group)
    local style = group.style
    -- Two settings have to be read together here whatever the mode: growth
    -- direction is relabelled by the orientation above it, so they always
    -- share a column and always sit adjacent.
    --
    -- LEFT column, in every mode: that pair. RIGHT column: how the block is
    -- packed - the wrap count and Compact Mode.
    local arrangeLeft, arrangeRight = BeginRowGrid(container)

    -- The Navigator's right-click Panel Type does the same switch.
    if state.panelForm then
        AddDropdownRow(arrangeLeft, {
            label = "Display as",
            setting = LAYOUT_FINDER.arrangement and LAYOUT_FINDER.arrangement.panelForm,
            list = { icons = "Icons", bars = "Bars" },
            order = { "icons", "bars" },
            value = group.displayMode == "bars" and "bars" or "icons",
            onChange = function(val)
                if val ~= group.displayMode then
                    CooldownCompanion:ChangePanelDisplayMode(CS.selectedGroup, val)
                end
                -- Also puts the row back when the switch was refused.
                CooldownCompanion:RefreshConfigPanel()
            end,
        })
    end

    -- An Aura BAR Panel is ONE vertical column by construction: the aura
    -- container's bars branch hard-codes the axis and takes no line ceiling, so
    -- neither the orientation question nor the wrap count has an answer to give
    -- here. Aura ICON Panels keep both - their grid follows the same style keys
    -- an ordinary icon panel's does.
    local auraBarPanel = state.auraBarPanel

    -- Orientation is remembered per display mode (bars own their key, unset =
    -- vertical), so a mode swap keeps every mode's layout. Same helper
    -- GetCompactGrowthDirectionLabels uses, because the Growth Direction
    -- labels below have to agree with it.
    local orientation = ST.GetPanelLayoutOrientation(group.displayMode, style)

    -- A centered growth edge lives on one axis, so every orientation control
    -- swaps it across with the orientation instead of silently stranding it
    -- on the old axis (where runtime folds it to a corner).
    local function SwapCenteredGrowthAxis()
        local swap = { TOP = "LEFT", LEFT = "TOP", BOTTOM = "RIGHT", RIGHT = "BOTTOM" }
        if swap[style.growthOrigin or ""] then
            style.growthOrigin = swap[style.growthOrigin]
        end
    end

    if state.horizontalBars then
        -- A bar panel's orientation is one question ("do the bars sit in a
        -- row?"), so it is a checkbox rather than the horizontal/vertical
        -- dropdown the other modes show. With a single bar there is nothing
        -- to lay out.
        --
        -- Which way a single bar's own FILL runs is a different question - it
        -- is what the bar looks like, not where the bars sit - so those two
        -- rows live with the bar's shape on the Appearance tab (Bar Settings).
        AddCheckboxRow(arrangeLeft, {
            label = "Horizontal Bar Layout",
            setting = LAYOUT_FINDER.arrangement and LAYOUT_FINDER.arrangement.horizontalBars,
            value = orientation == "horizontal",
            onChange = function(val)
                style.barOrientation = val and "horizontal" or "vertical"
                SwapCenteredGrowthAxis()
                refreshStyle("style-settings", "layout")
            end,
        })
    elseif state.orientation then
        AddDropdownRow(arrangeLeft, {
            label = "Orientation",
            setting = LAYOUT_FINDER.arrangement and LAYOUT_FINDER.arrangement.orientation,
            -- Owner ruling 2026-08-08 (supersedes 2026-07-28): the display
            -- reads the same per-mode helper the core lays out with. Each
            -- mode writes its own key so swapping modes keeps every mode's
            -- layout.
            list = { horizontal = "Horizontal", vertical = "Vertical" },
            value = orientation,
            onChange = function(val)
                style.orientation = val
                SwapCenteredGrowthAxis()
                refreshStyle("style-settings", "layout")
            end,
        })
    end

    if state.growth then
        local labels, order
        -- Aura panels delegate intra-line placement to Blizzard's flow
        -- container, so they fold centered values to TOPLEFT at runtime and
        -- this dropdown displays the same fold.
        local allowCentered = state.allowCentered
        -- Same override the Collapse Direction row below applies: an Aura BAR
        -- Panel is one vertical column by construction, so its labels must not
        -- follow the barOrientation key (hidden for this subtype, still
        -- copyable, and never read by the engine here).
        if auraBarPanel or orientation == "vertical" then
            labels = { TOPLEFT = "Down, Right", TOPRIGHT = "Down, Left", BOTTOMLEFT = "Up, Right", BOTTOMRIGHT = "Up, Left" }
            order = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
            if allowCentered then
                labels.LEFT, labels.RIGHT = "Centered, Right", "Centered, Left"
                order[5], order[6] = "LEFT", "RIGHT"
            end
        else
            labels = { TOPLEFT = "Right, Down", TOPRIGHT = "Left, Down", BOTTOMLEFT = "Right, Up", BOTTOMRIGHT = "Left, Up" }
            order = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
            if allowCentered then
                labels.TOP, labels.BOTTOM = "Centered, Down", "Centered, Up"
                order[5], order[6] = "TOP", "BOTTOM"
            end
        end

        local shownValue = style.growthOrigin or "TOPLEFT"
        if not labels[shownValue] then
            shownValue = "TOPLEFT"
        end

        AddDropdownRow(arrangeLeft, {
            label = "Growth Direction",
            setting = LAYOUT_FINDER.arrangement and LAYOUT_FINDER.arrangement.growth,
            list = labels,
            order = order,
            value = shownValue,
            onChange = function(val)
                style.growthOrigin = val
                refreshStyle("style-settings", "layout")
            end,
        })
    end

    -- An Aura Panel packs only its ACTIVE auras (Blizzard's aura container does
    -- the collapsing, so it is inherent and always on), which leaves one
    -- question Growth Direction cannot answer: which end of the panel the packed
    -- block holds as auras come and go. Same start/center/end key every other
    -- panel's compact mode writes, so it reads and writes through the compact
    -- helpers - but here it is simply how the panel arranges itself, so it sits
    -- under Growth Direction rather than behind a compact toggle this panel
    -- subtype does not have (owner ruling 2026-08-15).
    if state.collapse then
        -- PanelFlowSpec hard-codes the Vertical axis for an Aura BAR Panel, so
        -- the labels follow that rather than the (gated-away, possibly stale)
        -- barOrientation key the row above still reads.
        local collapseOrientation = auraBarPanel and "vertical" or nil
        local collapseRow = AddDropdownRow(arrangeLeft, {
            label = "Collapse Direction",
            setting = LAYOUT_FINDER.arrangement and LAYOUT_FINDER.arrangement.collapse,
            list = GetCompactGrowthDirectionLabels(group, collapseOrientation),
            order = { "start", "center", "end" },
            value = NormalizeCompactGrowthDirection(group.compactGrowthDirection),
            onChange = function(val)
                group.compactGrowthDirection = NormalizeCompactGrowthDirection(val)
                -- The mount point is read at BIND time, so the display only
                -- moves on the next aura pass. RefreshGroupFrame ends in
                -- RequestAuraRebind("aura-panel", groupId) for exactly this
                -- panel subtype, which is the request that re-runs it.
                CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            end,
        })

        -- Anchor args are a placeholder - AnchorRowBadge re-points the button
        -- onto the end of the row's label.
        AnchorRowBadge(collapseRow, CreateInfoButton(collapseRow.frame, collapseRow.frame, "LEFT", "LEFT", 0, 0, {
            "Collapse Direction",
            {state.isTotemPanel and "Occupied slots pack from the start of the panel, from its center, or from its end."
                or "Active auras pack from the start of the panel, from its center, or from its end.", 1, 1, 1, true},
            {" ", 1, 1, 1},
            {state.isTotemPanel and "Empty slots take no space. Slots retain their numeric order."
                or "Inactive auras take no space here, so the block moves as auras come and go.", 1, 1, 1, true},
        }, tabInfoButtons))
    end

    -- The wrap count is offered only once there is something to wrap.
    if state.buttonsPerLine then
        local numButtons = math.max(state.showAll and 100 or 1, layoutCount)
        local wrapKey = WrapCountKey(group)
        local wrapRow = AddSliderRow(arrangeRight, {
            label = WRAP_COUNT_LABELS[wrapKey],
            setting = LAYOUT_FINDER.arrangement and LAYOUT_FINDER.arrangement[wrapKey],
            min = 1, max = numButtons, step = 1,
            value = math.min(style.buttonsPerRow or 12, numButtons),
        })
        WireMirrorFirstSlider(wrapRow, function(val)
            style.buttonsPerRow = val
        end, function()
            return refreshStyle("style", "layout")
        end, nil, style, "buttonsPerRow")
    end

    -- Compact Mode: how the panel packs the entries that are actually visible,
    -- which is the same question the wrap count above it answers for the ones
    -- that always are - so it closes the right column rather than sitting with
    -- the look on the Appearance tab.
    --
    -- Aura panels pack themselves (the Collapse Direction row above); only
    -- Ordinary panels offer Compact Mode.
    --
    -- Panel-only data with no override section, and the Layout tab is panel
    -- scope throughout (no entry lens ever reaches it), so the row needs no
    -- lens bracket of its own here. Its gear panel closes like every other
    -- gear's: the dispatch-level gear build pass sweeps it when this
    -- section collapses, and a surface move closes it through the panel
    -- context (selecting an entry lands the surface on Appearance, changing
    -- panelSettingsTab - selectedButton itself is lens-ignored).
    --
    -- Compact Mode copies with the Arrangement scope of
    -- "Copy Panel Settings To..." (ST.PANEL_COPY_SCOPES, Defaults.lua).
    if state.compact then
        BuildCompactModeControls(arrangeRight, group, tabInfoButtons, {
            setting = LAYOUT_FINDER.arrangement and LAYOUT_FINDER.arrangement.compact,
            settings = LAYOUT_FINDER.compact,
        })
    end
end

-- The whole panel's draw layer, in the Strata section; onChanged applies the
-- new layer.
local function AddFrameStrataRow(parent, group, infoButtons, onChanged)
    local frameStrataRow = AddDropdownRow(parent, {
        label = "Frame Strata",
        setting = LAYOUT_FINDER.strata and LAYOUT_FINDER.strata.frame,
        list = {
            BACKGROUND = "Background",
            LOW = "Low",
            MEDIUM = "Default",
            HIGH = "High",
            DIALOG = "Highest",
        },
        order = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG" },
        value = group.frameStrata or "MEDIUM",
        onChange = function(val)
            group.frameStrata = (val ~= "MEDIUM") and val or nil
            onChanged()
        end,
    })

    local subject = ST.IsIndicatorGroup(group) and "Indicator" or "panel"
    AnchorRowBadge(frameStrataRow, CreateInfoButton(frameStrataRow.frame, frameStrataRow.frame, "LEFT", "LEFT", 0, 0, {
        "Frame Strata",
        {"Sets the rendering layer for this " .. subject .. ".", 1, 1, 1, true},
        " ",
        {"Panels and Indicators on a higher strata fully overlap lower ones.", 1, 1, 1, true},
    }, infoButtons))
end

local function BuildLayoutTab(container)
    if not CS.selectedGroup then return end
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then return end
    if ST.PanelSupportsAttachedBars(group) then
        -- Entry placement is edited by dragging in the preview.
        if ST._GetPanelSettingsSelection(group) then return end
        ST._AddLensPanelScopeNote(container, ST._ResolveStyleLens(group))
        local context = ST._CreatePanelSettingsContext(group, "shared")
        container = ST._NewPanelSettingsSectionHost(container, context)
        group = context.group
    end
    local style = group.style
    local layoutCount = ST.IsTotemPanelGroup(group) and GetNumTotemSlots() or #group.buttons

    local isIndicator = ST.IsIndicatorGroup(group)

    -- Layout is the one panel tab the entry lens never touches: every edit
    -- here lands on the whole panel while any selected entry stays selected
    -- above, and this line is the only thing on the surface that says so.
    -- Not on an Indicator: its sibling tabs never lens either, so there the
    -- strip is uniform and the note would be the odd one out instead of
    -- Layout.
    if not isIndicator then
        AddLensPanelScopeNote(container, ResolveStyleLens(group), true)
    end

    CS.layoutAnchorTargetMode = CS.layoutAnchorTargetMode or {}
    local anchorState = ResolveLayoutAnchorState(group,
        CS.layoutAnchorTargetMode[CS.selectedGroup])
    local isPanel, panelContainerFrame = anchorState.isPanel, anchorState.panelContainerFrame
    local currentAnchor, currentAnchorGroupId = anchorState.currentAnchor, anchorState.currentAnchorGroupId
    local isCursorAnchor, targetMode = anchorState.isCursorAnchor, anchorState.targetMode
    CS.layoutAnchorTargetMode[CS.selectedGroup] = not anchorState.inferredFrame and targetMode or nil
    local cursorAnchorTarget = CooldownCompanion.GetCursorAnchorTargetName
        and CooldownCompanion:GetCursorAnchorTargetName()
        or ST.CURSOR_ANCHOR_TARGET
        or "CooldownCompanionCursor"
    local defaultFrame = isPanel and panelContainerFrame or "UIParent"
    -- ================================================================
    -- The row grammar (RowWidgets.lua). The rules every row-grammar section
    -- follows are stated once, in the recipe comment at the top of
    -- BuildAppearanceTab's icons path (GroupTabsAppearance.lua); this tab
    -- conforms to them rather than restating them.
    --
    -- Every mode that reaches here shares this one layout: anchoring,
    -- position and frame strata are panel facts, not display-mode
    -- facts. (Alpha is a panel fact too, but it reads as visibility
    -- behavior, so it lives on the Visibility tab.)
    -- Only the Arrangement section and the icons-only strata block
    -- below vary, and each of those names its own mode gate. (An Indicator
    -- is a single display rather than a panel of entries, so it has
    -- neither.)
    -- ================================================================
    local iconAnchorTargetList = isPanel
        and {
            group = "Group",
            panel = "Panel",
            frame = "Frame",
            cursor = "Cursor",
        }
        or {
            group = "Screen",
            frame = "Frame",
        }
    local iconAnchorTargetOrder = isPanel
        and { "group", "panel", "frame", "cursor" }
        or { "group", "frame" }

    -- ============================================================
    -- Position (what this panel hangs off, and where it sits there)
    -- ============================================================
    -- One section: the target and the points/offsets answer the same
    -- question. It keeps the "layout_anchor" key the mover menu opens.
    local _, anchorCollapsed = BuildCollapsibleSection(container, "Position", "layout_anchor", nil, nil, ROW_SECTION)

    if not anchorCollapsed then
    -- LEFT column: the target itself. RIGHT column: whether other features may
    -- anchor THEMSELVES to this panel - the one remaining setting that belongs
    -- to anchoring rather than to the entries inside. (Where the panel's alpha
    -- comes from used to share this column; it now leads the Visibility tab's
    -- Alpha section, beside the rows it gates, so on bar panels this column
    -- runs empty.)
    local anchorLeft, anchorRight = BeginRowGrid(container)

    AddDropdownRow(anchorLeft, {
        label = "Anchor Target",
        setting = LAYOUT_FINDER.anchor and LAYOUT_FINDER.anchor.target,
        list = iconAnchorTargetList,
        order = iconAnchorTargetOrder,
        value = targetMode,
        onChange = function(val, widget)
            if val == targetMode then return end
            if val == "group" then
                CS.layoutAnchorTargetMode[CS.selectedGroup] = nil
                local wasAnchored = group.anchor.relativeTo and group.anchor.relativeTo ~= defaultFrame
                CooldownCompanion:SetGroupAnchor(CS.selectedGroup, defaultFrame, wasAnchored)
                CooldownCompanion:RefreshConfigPanel()
            elseif val == "cursor" then
                CS.layoutAnchorTargetMode[CS.selectedGroup] = nil
                if CooldownCompanion:SetGroupAnchor(CS.selectedGroup, cursorAnchorTarget) then
                    CooldownCompanion:RefreshConfigPanel()
                else
                    widget:SetValue(targetMode)
                end
            elseif val == "frame" or val == "panel" then
                CS.layoutAnchorTargetMode[CS.selectedGroup] = val
                CooldownCompanion:RefreshConfigPanel()
            end
        end,
    })

    if isPanel and targetMode == "panel" then
        local panelAnchorRow = AddDropdownRow(anchorLeft, {
            label = "Anchor to Panel",
            setting = LAYOUT_FINDER.anchor and LAYOUT_FINDER.anchor.panel,
            pulloutWidth = WIDE_PULLOUT_WIDTH,
            onChange = function(val, widget)
                if not val or val == "" then return end
                local targetGroupId = tonumber(val)
                if not targetGroupId then return end
                local targetFrameName = "CooldownCompanionGroup" .. targetGroupId
                if CooldownCompanion:SetGroupAnchor(CS.selectedGroup, targetFrameName) then
                    CooldownCompanion:RefreshConfigPanel()
                else
                    widget:SetValue(nil)
                end
            end,
        })
        -- The populator writes the stock Dropdown's own `list` table
        -- directly (container headers plus indented panel entries), so it
        -- takes the embedded child rather than the row wrapper.
        CooldownCompanion:PopulatePanelAnchorTargetDropdown(panelAnchorRow.dropdown, CS.selectedGroup)
        if currentAnchorGroupId then
            panelAnchorRow:SetValue(tostring(currentAnchorGroupId))
        else
            panelAnchorRow:SetValue(nil)
        end
    end

    -- Auto-Anchoring eligibility (icon-like modes only - others are never
    -- eligible). Aura and Totem Panels are structurally excluded in
    -- IsGroupAvailableForAnchoring, so the checkbox has nothing to opt into.
    --
    -- It reads as anchoring rather than arrangement: it decides whether the
    -- Resource Bars, the Cast Bar and the Unit Frames may hang off this panel,
    -- in Automatic mode; explicit module selections ignore this preference.
    if CooldownCompanion:IsIconLikeDisplayMode(group.displayMode)
        and not CooldownCompanion:IsAuraPanel(group)
        and not ST.IsTotemPanelGroup(group) then
        -- Shows what Automatic actually does: a Group that opted out takes
        -- its panels with it, and only the Group's own row brings them back.
        local containerIncluded = CooldownCompanion:IsContainerAutoAnchorEligible(
            CooldownCompanion:GetParentContainer(group))
        local anchorEligibleRow = AddCheckboxRow(anchorRight, {
            label = "Include in Auto-Anchoring",
            setting = LAYOUT_FINDER.anchor and LAYOUT_FINDER.anchor.autoAnchor,
            value = containerIncluded and group.anchorEligible ~= false,
            disabled = not containerIncluded,
            onChange = function(val)
                if val then
                    group.anchorEligible = nil
                else
                    group.anchorEligible = false
                end
                CooldownCompanion:EvaluateBarsAndFramesRuntime("panel-attachment-choice")
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        -- Badge chained off the end of the label; the anchor args below
        -- are a placeholder - AnchorRowBadge re-points the button.
        AnchorRowBadge(anchorEligibleRow, CreateInfoButton(anchorEligibleRow.frame, anchorEligibleRow.frame, "LEFT", "LEFT", 0, 0, {
            "Include in Auto-Anchoring",
            {"Resource Bars, the Cast Bar, and Unit Frames can attach themselves to a panel automatically.", 1, 1, 1, true},
            {" ", 1, 1, 1},
            {"They scan your groups in list order, then the panels inside each group, and attach to the first eligible icon panel that is currently shown.", 1, 1, 1, true},
            {" ", 1, 1, 1},
            {"Uncheck this to skip this panel in Automatic mode. Modules using Choose Panel can still attach here.", 1, 1, 1, true},
            {" ", 1, 1, 1},
            {"A group can exclude all of its panels in its own settings. Global groups start excluded.", 1, 1, 1, true},
        }, tabInfoButtons))
    end

    if targetMode == "frame" then
        -- A frame name needs the whole 140px control column to stay
        -- readable, so Pick does not share it: the editbox row takes a
        -- grid of its own and Pick sits at the head of that grid's right
        -- column. The gutter between columns is 16px, so the button lands
        -- immediately right of the editbox, and both are on line one of
        -- their own grid, so nothing above them can knock them apart.
        local frameLeft, frameRight = BeginRowGrid(container)

        local frameAnchorText = currentAnchor
        if frameAnchorText == "UIParent" or isCursorAnchor or currentAnchorGroupId then frameAnchorText = "" end
        if isPanel and frameAnchorText == panelContainerFrame then frameAnchorText = "" end

        local anchorRow = AddEditBoxRow(frameLeft, {
            label = "Anchor to Frame",
            setting = LAYOUT_FINDER.anchor and LAYOUT_FINDER.anchor.frame,
            value = frameAnchorText,
            onEnterPressed = function(text, widget)
                local wasAnchored = group.anchor.relativeTo and group.anchor.relativeTo ~= defaultFrame
                if text == "" then
                    CooldownCompanion:SetGroupAnchor(CS.selectedGroup, defaultFrame, wasAnchored)
                else
                    local target = _G[text]
                    if not target or type(target) ~= "table" or not target.GetObjectType then
                        CooldownCompanion:Print("Frame not found: " .. text)
                        widget:SetText(frameAnchorText)
                        return
                    end
                    CooldownCompanion:SetGroupAnchor(CS.selectedGroup, text)
                end
                CooldownCompanion:RefreshConfigPanel()
            end,
        })
        if anchorRow.editbox.Instructions then anchorRow.editbox.Instructions:Hide() end

        -- Exactly one grammar row tall so the button's centre lands on the
        -- editbox's: Flow insets its single row by 3px and the button is
        -- 24 tall, so 3 + 24 + 3 fills the 30px band. noAutoHeight keeps
        -- Flow's own 27px report from shrinking it back.
        local pickRow = AceGUI:Create("SimpleGroup")
        pickRow:SetFullWidth(true)
        pickRow:SetLayout("Flow")
        pickRow:SetHeight(ST._RowGrammar and ST._RowGrammar.ROW_HEIGHT or 30)
        pickRow.noAutoHeight = true

        local pickBtn = AceGUI:Create("Button")
        pickBtn:SetText("Pick")
        pickBtn:SetAutoWidth(true)
        pickBtn:SetCallback("OnClick", function()
            local grp = CS.selectedGroup
            CS.StartPickFrame(function(name)
                if CS.configFrame then
                    CS.configFrame.frame:Show()
                end
                if name then
                    CooldownCompanion:SetGroupAnchor(grp, name)
                end
                CooldownCompanion:RefreshConfigPanel()
            end, grp)
        end)
        pickRow:AddChild(pickBtn)

        -- (?) tooltip for anchor picking
        CreateInfoButton(pickBtn.frame, pickBtn.frame, "LEFT", "RIGHT", 2, 0, {
            "Pick Frame",
            {"Hides the config panel and highlights frames under your cursor. Left-click a frame to anchor this panel to it, or right-click to cancel.", 1, 1, 1, true},
            " ",
            {"You can also type a frame name directly into the editbox.", 1, 1, 1, true},
        }, tabInfoButtons)

        -- Added last so the List-layout column measures a populated row.
        frameRight:AddChild(pickRow)
    end
    end -- not anchorCollapsed

    -- Points and offsets, under the same heading as the target above.
    -- Cursor anchoring pins the relative point: SetGroupAnchor and the
    -- cursor mover write it, so there is no row for it and nothing to write
    -- here.

    local function refreshGroupAnchor()
        CooldownCompanion:ReanchorGroupFrame(CS.selectedGroup)
    end

    local positionCollapsed = anchorCollapsed

    if not positionCollapsed then
    -- LEFT column: the two points that have to be read together (mine,
    -- then the target's). RIGHT column: the offset pair applied on top of
    -- them. Cursor mode has no relative point.
    local positionLeft, positionRight = BeginRowGrid(container)

    AddAnchorDropdown(positionLeft, group.anchor, "point",
        targetMode == "cursor" and "BOTTOMLEFT" or "CENTER",
        refreshGroupAnchor,
        targetMode == "cursor" and "Panel Point" or "Anchor Point",
        {
            setting = LAYOUT_FINDER.position and (
                targetMode == "cursor" and LAYOUT_FINDER.position.panelPoint
                or LAYOUT_FINDER.position.anchorPoint),
        })

    if targetMode ~= "cursor" then
        AddAnchorDropdown(positionLeft, group.anchor, "relativePoint", "CENTER",
            refreshGroupAnchor, "Relative Point", {
                setting = LAYOUT_FINDER.position and LAYOUT_FINDER.position.relativePoint,
            })
    end

    -- Screen position is not represented inside the pinned mirror. Store the
    -- drag value and re-anchor the live panel once on release.
    local xOffsetRow = AddSliderRow(positionRight, {
        label = "X Offset",
        setting = LAYOUT_FINDER.position and LAYOUT_FINDER.position.xOffset,
        min = -2000, max = 2000, step = 0.1,
        value = group.anchor.x or 0,
    })
    local function PreviewCursorOffset()
        if targetMode == "cursor" and CooldownCompanion.SetCursorAnchorLayoutPreviewOffset then
            CooldownCompanion:SetCursorAnchorLayoutPreviewOffset(
                CS.selectedGroup,
                group.anchor.x or 0,
                group.anchor.y or 0
            )
        end
    end
    local function CommitGroupOffset()
        if CooldownCompanion.ClearCursorAnchorLayoutPreviewOffset then
            CooldownCompanion:ClearCursorAnchorLayoutPreviewOffset(CS.selectedGroup)
        end
        refreshGroupAnchor()
    end

    WireMirrorFirstSlider(xOffsetRow, function(val)
        group.anchor.x = val
    end, CommitGroupOffset, targetMode == "cursor" and PreviewCursorOffset or false,
        group.anchor, "x")

    local yOffsetRow = AddSliderRow(positionRight, {
        label = "Y Offset",
        setting = LAYOUT_FINDER.position and LAYOUT_FINDER.position.yOffset,
        min = -2000, max = 2000, step = 0.1,
        value = group.anchor.y or 0,
    })
    WireMirrorFirstSlider(yOffsetRow, function(val)
        group.anchor.y = val
    end, CommitGroupOffset, targetMode == "cursor" and PreviewCursorOffset or false,
        group.anchor, "y")

    -- An Indicator keeps the Reset button its Layout tab has always had; it
    -- is the mover menu's own reset, which every panel has there.
    if isIndicator then
        local resetBtn = AceGUI:Create("Button")
        resetBtn:SetText(targetMode == "cursor" and "Reset Cursor Offset" or "Reset Position")
        resetBtn:SetAutoWidth(true)
        resetBtn:SetCallback("OnClick", function()
            if CooldownCompanion.ClearCursorAnchorLayoutPreviewOffset then
                CooldownCompanion:ClearCursorAnchorLayoutPreviewOffset(CS.selectedGroup)
            end
            CooldownCompanion:ResetMoverQuickPosition({ kind = "panel", id = CS.selectedGroup })
        end)
        positionRight:AddChild(resetBtn)
    end
    end -- not positionCollapsed

    -- ============================================================
    -- Arrangement (how the entries sit relative to each other)
    -- ============================================================
    if isIndicator then
        -- One display: nothing to arrange.
    elseif not ST._BuildUnifiedPanelArrangement(container, group, BuildGridArrangement) then
        local _, arrangementCollapsed = BuildCollapsibleSection(container, "Arrangement", "layout_arrangement", nil, nil, ROW_SECTION)
        if not arrangementCollapsed then
            BuildGridArrangement(container, group, layoutCount)
        end
    end

    -- ============================================================
    -- Panel Sections (one quiet block per placed cluster)
    -- ============================================================
    -- Nothing here exists on an ordinary panel: a panel with no sections shows
    -- no heading, no rows, no gap. A section whose members are all hidden still
    -- gets its block - the section lives in the profile either way, and the
    -- owner has to be able to nudge it before it comes back.
    --
    -- What the cluster IS, then where it sits: a section's icon size and
    -- spacing stay with the panel's own copies of those in the Appearance tab
    -- (owner ruling 2026-08-22 -- size and spacing are Appearance's vocabulary;
    -- placement, direction, and wrap are Layout's), and the aura toggle heads
    -- the block here because "only auras live here, and they pack" is a
    -- statement about the cluster's layout rather than its look.
    local hasIcons = HasLayoutIcons(group, CS.selectedGroup)
    local panelSections = hasIcons and ST.PanelSupportsSections(group) and group.sections or nil
    if type(panelSections) == "table" and next(panelSections) then
        -- Reading order, so the blocks sit in the order the anchors read on the
        -- panel rather than whatever order the profile happens to store them in.
        for _, anchor in ipairs(ST.PANEL_SECTION_ANCHORS) do
            local section = panelSections[anchor]
            if type(section) == "table" then
                local _, sectionCollapsed = BuildCollapsibleSection(container,
                    ST.PANEL_SECTION_ANCHOR_LABELS[anchor] .. " Section",
                    "layout_section_" .. anchor, nil, nil, ROW_SECTION)

                if not sectionCollapsed then
                -- WHAT this cluster is comes before where it sits: the aura
                -- toggle and the wrap count share the first grid, and the
                -- offsets pair sits below them.
                --
                -- A section holding anything the aura container cannot draw is
                -- told so on a DISABLED checkbox rather than being allowed to
                -- click and fail: the engine's refusal is asked for here, before
                -- the write, and the blocking entry's own sentence is what the
                -- row explains itself with. The blocker only ever gates turning
                -- the flag ON. A section already flagged can still develop one
                -- (polarity is spec-dependent, so a member admitted on one spec
                -- can mismatch on another), and the setter deliberately lets OFF
                -- through unconditionally - so the checkbox must stay clickable
                -- there, or the section is trapped aura-only.
                local sectionAuraOnly = ST.IsAuraOnlyPanelSection(group, anchor)
                local sectionBlocker = not sectionAuraOnly
                    and ST.GetAuraSectionToggleBlocker(group, anchor) or nil
                local sectionToggleTooltip = AURA_SECTION_TOOLTIP
                if sectionBlocker then
                    sectionToggleTooltip = {
                        AURA_SECTION_TOOLTIP[1],
                        {sectionBlocker, 1, 0.4, 0.4, true},
                        " ",
                    }
                    for line = 2, #AURA_SECTION_TOOLTIP do
                        sectionToggleTooltip[#sectionToggleTooltip + 1] = AURA_SECTION_TOOLTIP[line]
                    end
                end

                local sectionTopLeft, sectionTopRight = BeginRowGrid(container)
                AddCheckboxRow(sectionTopLeft, {
                    label = "Aura Only Section",
                    setting = LAYOUT_FINDER.sections[anchor]
                        and LAYOUT_FINDER.sections[anchor].auraOnly,
                    value = sectionAuraOnly,
                    tooltip = sectionToggleTooltip,
                    disabled = sectionBlocker ~= nil,
                    onChange = function(value, widget)
                        -- A structural commit, not a styling one: the flag
                        -- changes which entries materialize a button at all, so
                        -- it takes the same pair a section drop takes rather
                        -- than the sliders' UpdateGroupStyle. Safe here for the
                        -- same reason it is safe there - a click is over.
                        if not ST.SetPanelSectionAuraOnly(group, anchor, value) then
                            widget:SetValue(ST.IsAuraOnlyPanelSection(group, anchor))
                            return
                        end
                        CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
                        CooldownCompanion:RefreshConfigPanel()
                    end,
                })

                -- The section's one layout-grammar control: a wrap count.
                -- Direction is ALWAYS the anchor's own (owner ruling
                -- 2026-08-28: a Growth Direction override was built, seen,
                -- and removed -- do not revive it). Wrap only once there is
                -- something to wrap, the same gate the base row's own wrap
                -- slider keeps. Top of the range stores nil: "everything on
                -- one line" must stay open-ended so a member added later
                -- joins the line instead of wrapping under a count that
                -- silently became a cap.
                local sectionState = ResolveLayoutSectionState(group, anchor)
                local axis, memberCount = sectionState.axis, sectionState.memberCount
                if sectionState.iconsPerRow or sectionState.iconsPerColumn then
                    local wrapLabel = (axis == "h") and "Icons Per Row" or "Icons Per Column"
                    local sectionWrapRow = AddSliderRow(sectionTopRight, {
                        label = wrapLabel,
                        setting = LAYOUT_FINDER.sections[anchor] and (
                            axis == "h" and LAYOUT_FINDER.sections[anchor].iconsPerRow
                            or LAYOUT_FINDER.sections[anchor].iconsPerColumn),
                        min = 1, max = memberCount, step = 1,
                        value = math.min(section.maxPerLine or memberCount, memberCount),
                    })
                    WireMirrorFirstSlider(sectionWrapRow, function(val)
                        section.maxPerLine = (val < memberCount) and val or nil
                    end, function()
                        CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
                    end, nil, section, "maxPerLine")
                end

                local sectionLeft, sectionRight = BeginRowGrid(container)

                local sectionXRow = AddSliderRow(sectionLeft, {
                    label = "X Offset",
                    setting = LAYOUT_FINDER.sections[anchor]
                        and LAYOUT_FINDER.sections[anchor].xOffset,
                    min = -100, max = 100, step = 0.1,
                    value = section.offsetX or 0,
                })
                WireMirrorFirstSlider(sectionXRow, function(val)
                    section.offsetX = val
                end, nil, nil, section, "offsetX")

                local sectionYRow = AddSliderRow(sectionRight, {
                    label = "Y Offset",
                    setting = LAYOUT_FINDER.sections[anchor]
                        and LAYOUT_FINDER.sections[anchor].yOffset,
                    min = -100, max = 100, step = 0.1,
                    value = section.offsetY or 0,
                })
                WireMirrorFirstSlider(sectionYRow, function(val)
                    section.offsetY = val
                end, nil, nil, section, "offsetY")
                end -- not sectionCollapsed
            end
        end
    end

    -- ============================================================
    -- Strata
    -- ============================================================
    local _, strataCollapsed = BuildCollapsibleSection(container, "Strata", "layout_strata", nil, nil, ROW_SECTION)

    if not strataCollapsed then
    -- Per-icon layer ordering exists on icon panels only; the other modes
    -- have no stack of icon layers to reorder.
    --
    -- Nor does an Aura Panel: it materializes no CC buttons at all (GroupFrame's
    -- aura-panel branch), so seven of the eight layers this orders - the fill
    -- timer, cooldown swipe, ready glow, key press highlight, text overlay,
    -- assisted highlight and proc glow - do not exist here, and the eighth (Aura
    -- Display) IS the panel. There is no stack left to reorder.
    local showCustomStrata = HasCustomIconStrata(group, hasIcons)
    local customStrataEnabled = showCustomStrata and type(style.strataOrder) == "table"

    -- LEFT column: the whole panel's draw layer, the row most players want.
    -- RIGHT column: the per-icon layer switch, whose layers open in its gear.
    local strataLeft, strataRight = BeginRowGrid(container)

    local strataToggleRow
    if showCustomStrata then
    strataToggleRow = AddCheckboxRow(strataRight, {
        label = "Custom Icon Strata",
        setting = LAYOUT_FINDER.strata and LAYOUT_FINDER.strata.custom,
        value = customStrataEnabled,
        onChange = function(val)
            if not val then
                style.strataOrder = nil
                CS.pendingStrataOrder = nil
                CS.pendingStrataGroup = nil
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            else
                style.strataOrder = style.strataOrder or {}
                CS.pendingStrataOrder = nil
                CS.InitPendingStrataOrder(CS.selectedGroup)
            end
            local host = CS.groupSettingsActiveHost
            if host and host.tabGroup then
                host.tabGroup:SelectTab(CS.selectedTab)
            end
        end,
    })

    AnchorRowBadge(strataToggleRow, CreateInfoButton(strataToggleRow.frame, strataToggleRow.frame, "LEFT", "LEFT", 0, 0, {
        "Custom Icon Strata",
        {"Sets the draw order of each icon's visual layers.", 1, 1, 1, true},
        " ",
        {"Layer 8 draws on top, Layer 1 on the bottom.", 1, 1, 1, true},
        " ",
        {"Aura Display moves the aura glow, pandemic glow, aura swipe and aura text together.", 1, 1, 1, true},
        " ",
        {"Put Cooldown Swipe above Aura Display to keep a spell's own cooldown visible while its aura runs.", 1, 1, 1, true},
        " ",
        {"Loss of Control and keybind text always draw on top.", 1, 1, 1, true},
    }, tabInfoButtons))
    end -- showCustomStrata (custom strata toggle)

    AddFrameStrataRow(strataLeft, group, tabInfoButtons, function()
        CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
    end)

    if strataToggleRow then
        ST._AddAdvancedToggle(strataToggleRow, "customIconStrata", {}, true, {
            unlock = not customStrataEnabled and { enable = {
                label = "Enable Custom Icon Strata", run = function()
                    style.strataOrder = {}
                    CS.pendingStrataOrder = nil
                    CS.InitPendingStrataOrder(CS.selectedGroup)
                    CooldownCompanion:RefreshConfigPanel()
                end,
            } } or nil,
            build = function(panel)
                CS.InitPendingStrataOrder(CS.selectedGroup)

                local ELEMENT_COUNT = #ST.DEFAULT_STRATA_ORDER

                -- Build dropdown list with unassigned entries highlighted in green
                local function BuildStrataList()
                    local assigned = {}
                    for i = 1, ELEMENT_COUNT do
                        if CS.pendingStrataOrder[i] then
                            assigned[CS.pendingStrataOrder[i]] = true
                        end
                    end
                    local list = {}
                    for _, key in ipairs(CS.strataElementKeys) do
                        if not assigned[key] then
                            list[key] = "|cff40ff40" .. CS.strataElementLabels[key] .. "|r"
                        else
                            list[key] = CS.strataElementLabels[key]
                        end
                    end
                    return list
                end

                local strataDropdowns = {}

                -- Refresh all dropdown lists and values
                local function RefreshAllDropdowns()
                    local list = BuildStrataList()
                    for i = 1, ELEMENT_COUNT do
                        if strataDropdowns[i] then
                            strataDropdowns[i]:SetList(list)
                            strataDropdowns[i]:SetValue(CS.pendingStrataOrder[i])
                        end
                    end
                end

                -- One ordered stack, top to bottom inside its owning editor.

                for displayIdx = 1, ELEMENT_COUNT do
                    local pos = ELEMENT_COUNT + 1 - displayIdx
                    local label
                    if pos == ELEMENT_COUNT then
                        label = "Layer " .. pos .. " (Top)"
                    elseif pos == 1 then
                        label = "Layer " .. pos .. " (Bottom)"
                    else
                        label = "Layer " .. pos
                    end

                    local drop = AddDropdownRow(panel, {
                        label = label,
                        setting = LAYOUT_FINDER.layers[pos],
                        indent = false,
                        list = BuildStrataList(),
                        value = CS.pendingStrataOrder[pos],
                        onChange = function(val)
                            for i = 1, ELEMENT_COUNT do
                                if i ~= pos and CS.pendingStrataOrder[i] == val then
                                    CS.pendingStrataOrder[i] = nil
                                end
                            end
                            CS.pendingStrataOrder[pos] = val

                            if CS.IsStrataOrderComplete(CS.pendingStrataOrder) then
                                style.strataOrder = {}
                                for i = 1, ELEMENT_COUNT do
                                    style.strataOrder[i] = CS.pendingStrataOrder[i]
                                end
                            else
                                style.strataOrder = {}
                            end
                            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)

                            RefreshAllDropdowns()
                        end,
                    })
                    strataDropdowns[pos] = drop
                end
            end,
        })
    end
    end -- not strataCollapsed

    -- An open texture picker follows the Indicator across tabs.
    if isIndicator and CS.IsAuraTexturePickerOpen and CS.IsAuraTexturePickerOpen() then
        OpenOrRebindIndicatorTexturePicker(group, CooldownCompanion:GetIndicatorTextureSettings(group), false)
    end
end

ST._BuildLayoutTab = BuildLayoutTab
