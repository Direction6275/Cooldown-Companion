--[[
    CooldownCompanion - ButtonPanelPreview
    Live Preview composition, selection refresh, read-only builds, and release.
    Renders saved settings and config-owned preview state, never live button
    geometry, which can be secret-sensitive in config context.

    Part of the ButtonPanelPreview family; see its ordered block in the addon TOC.
    Private helpers are shared through ST._ButtonPanelPreview.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState
local math_floor = math.floor
local math_min = math.min
local math_max = math.max
local math_ceil = math.ceil
local GetLayoutPreviewIcon = ST._GetLayoutPreviewIcon
local CancelDrag = ST._CancelDrag

local PP = ST._ButtonPanelPreview

-- ButtonPanelPreviewShared.lua
local EnsurePreviewState = PP.EnsurePreviewState
local ClearPreviewGhost = PP.ClearPreviewGhost
local ResetPreviewState = PP.ResetPreviewState
local HidePreviewMessage = PP.HidePreviewMessage
local SetPreviewMessage = PP.SetPreviewMessage
local FinalizePreviewState = PP.FinalizePreviewState
local IsIconModePanel = PP.IsIconModePanel
local IsEntrySelected = PP.IsEntrySelected
local GetPanelGeometry = PP.GetPanelGeometry
local GetGrowthMultipliers = PP.GetGrowthMultipliers
local GetHostFitScale = PP.GetHostFitScale
local GetConfigOnlyBarPreviewIcon = PP.GetConfigOnlyBarPreviewIcon
local AcquireSlot = PP.AcquireSlot
local GetTextSlotSize = PP.GetTextSlotSize
local ApplyPreviewSlotGeometry = PP.ApplyPreviewSlotGeometry
local GetStoredBarPreviewState = PP.GetStoredBarPreviewState
local CollectBarEntryStatus = PP.CollectBarEntryStatus
local CollectEntryStatus = ST._CollectEntryStatus
local ResolveBarPreviewVisibility = PP.ResolveBarPreviewVisibility
local PANEL_PREVIEW_DISABLED_ALPHA = PP.PANEL_PREVIEW_DISABLED_ALPHA
local ApplyBarSlotPreviewVisibility = PP.ApplyBarSlotPreviewVisibility
local ApplySlotBadges = PP.ApplySlotBadges
local DisableReadOnlySlotInteraction = PP.DisableReadOnlySlotInteraction
local ApplySelectionVisuals = PP.ApplySelectionVisuals
local IsGlowPreviewActiveOnEntry = PP.IsGlowPreviewActiveOnEntry
local CopyMode = PP.CopyMode
local PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET = PP.PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET
local PANEL_PREVIEW_RING_COLOR = PP.PANEL_PREVIEW_RING_COLOR
local RefreshBarSlotWorkspacePresentation = PP.RefreshBarSlotWorkspacePresentation
local GetPanelPreviewNaturalSize = PP.GetPanelPreviewNaturalSize
local ResetBarSlotWorkspaceState = PP.ResetBarSlotWorkspaceState

-- ButtonPanelPreviewSections.lua
local SectionDrag = PP.SectionDrag

-- ButtonPanelPreviewTriggers.lua
local StopTextureMirrorEffects = PP.StopTextureMirrorEffects
local BuildTextureMirror = PP.BuildTextureMirror
local BuildTriggerPanelPreview = PP.BuildTriggerPanelPreview
local BuildSelectionStrip = PP.BuildSelectionStrip

-- ButtonPanelPreviewInteraction.lua
local DropGhost = PP.DropGhost
local CreatePreviewLayoutDrag = PP.CreatePreviewLayoutDrag
local WireEntryInteraction = PP.WireEntryInteraction

-- ButtonPanelPreviewEffects.lua
local StopConditionalTicker = PP.StopConditionalTicker
local ApplySlotEffectPreviews = PP.ApplySlotEffectPreviews
local ClearSlotEffectPreviews = PP.ClearSlotEffectPreviews
local EnsureConditionalTicker = PP.EnsureConditionalTicker

-- ButtonPanelPreviewText.lua
local UpdateTextGroupHeader = PP.UpdateTextGroupHeader
local StyleTextEntry = PP.StyleTextEntry
local ApplyTextSlotConditionalPreview = PP.ApplyTextSlotConditionalPreview

-- ButtonPanelPreviewBars.lua
local StyleBarEntry = PP.StyleBarEntry
local ResetBarSlotConditionalVisuals = PP.ResetBarSlotConditionalVisuals
local ApplyBarSlotConditionalPreview = PP.ApplyBarSlotConditionalPreview

-- ButtonPanelPreviewIcons.lua
local StyleIconEntry = PP.StyleIconEntry
local ResetSlotConditionalVisuals = PP.ResetSlotConditionalVisuals
local ApplySlotConditionalPreview = PP.ApplySlotConditionalPreview

function ST._BuildButtonPanelPreview(host, panelId, options)
    options = type(options) == "table" and options or nil
    local readOnly = options and options.readOnly == true
    -- Rebuilding pulls the slot frames out from under an in-flight drag
    if not readOnly
        and CS.dragState and CS.dragState.kind == "layout-slot" and CancelDrag then
        CancelDrag()
    end

    local preview = EnsurePreviewState(host)
    preview.panelId = panelId
    preview.readOnly = readOnly
    -- Copy-customization banner surface; nil means the preview's own root.
    preview.copyBannerHost = options and options.bannerHost or nil
    -- The Live Preview host whose attached bar lanes wrap this mirror; nil for
    -- every mirror that is not inside the unified anchor composition.
    preview.laneChromeHost = options and options.laneHost or nil
    if not readOnly and panelId == CS.selectedGroup then
        -- A full build reconciles the cleared stores by construction; do not
        -- make the next selection-only pass repeat that work.
        CS.panelPreviewVisualsNeedReconcile = nil
    end
    preview.layoutDrag = nil
    -- The cursor-drop model is rebuilt with the mirror it describes (or its
    -- build inputs are, when the model waits for first use); every other
    -- build path leaves both nil, which is how the drop overlay knows this
    -- preview offers no landings. The open gesture, whichever it was, read
    -- a model this build replaces, so its record goes with them (and hands
    -- the attached bar lanes back).
    preview.cursorPadModel = nil
    preview.cursorPadInputs = nil
    SectionDrag.EndGesture(preview)
    StopTextureMirrorEffects(preview.textureMirror)
    -- Fresh static layout: discard any tweens or ghost the canceled drag
    -- queued so they can't fight the rebuilt slot positions
    preview.tweens = preview.tweens or {}
    wipe(preview.tweens)
    ClearPreviewGhost(preview)
    -- And the drop ghost: it stood on the grid this build replaces. Only the
    -- builds that end on a droppable mirror license it again.
    DropGhost.Reset(preview)
    preview.dropGhostMode = nil
    preview.root:SetScript("OnUpdate", nil)
    if preview.gapFrame then
        preview.gapFrame:Hide()
    end
    -- The section outline, whichever gesture drew it: a cursor drop's gold
    -- ring outlives the rebuild its own add triggers unless it is put away
    -- here, and HideHandle below only reaches it when a handle exists.
    SectionDrag.HideSectionOutline(preview)
    -- Same reasoning for the section handle: it points at a lane in the model
    -- this build is about to replace.
    SectionDrag.HideHandle(preview)
    -- Belt and braces on the bar lanes: the CancelDrag above already restored
    -- them through onCancel, and a rebuild with no drag in flight never faded
    -- them, but a mirror must never hand its host back a faded set of lanes.
    SectionDrag.SetLaneChromeFaded(preview, false)
    if preview.textHeader then
        preview.textHeader:Hide()
    end
    -- Hide the texture mirror up front so switching from a texture panel to any
    -- other type never leaves a stale texture drawn over the new mirror; only
    -- BuildTextureMirror re-shows it.
    if preview.textureMirror then
        preview.textureMirror.root:Hide()
    end
    ResetPreviewState(preview)
    HidePreviewMessage(preview)
    preview.content:Hide()
    -- Stop the animation ticker up front: the early exits below (no group,
    -- empty panel) render no animated slots, and the main path re-arms it
    -- only when a slot actually animates. The stored preview state the
    -- ticker reads lives outside the ticker, so a stop/re-arm is seamless.
    StopConditionalTicker(preview)

    -- options.groupData renders a detached panel table (an import payload's
    -- incoming panel) instead of a saved panel. Read-only paths never touch
    -- panelId after this resolution, so a nil id is safe with data supplied.
    local group = options and type(options.groupData) == "table" and options.groupData or nil
    if not group then
        group = panelId and CooldownCompanion.db.profile.groups[panelId]
    end
    if not group then
        SetPreviewMessage(preview, "Select a panel to preview it here.")
        FinalizePreviewState(preview)
        return
    end

    local isBarMode = group.displayMode == "bars"
    local isTextMode = group.displayMode == "text"
    if not isBarMode and not isTextMode and not IsIconModePanel(group) then
        -- Texture panels render their real texture; trigger panels stack
        -- their display visual above the strip; rotation-assistant panels
        -- keep the entry-icon selection strip alone.
        if CooldownCompanion:IsTexturePanelGroup(group) then
            return BuildTextureMirror(preview, host, panelId, group, readOnly)
        end
        if CooldownCompanion:IsTriggerPanelGroup(group) then
            return BuildTriggerPanelPreview(preview, host, panelId, group, readOnly)
        end
        return BuildSelectionStrip(preview, host, panelId, group, readOnly)
    end

    local buttons = group.buttons or {}
    local count = #buttons
    if count == 0 then
        if readOnly then
            SetPreviewMessage(preview, "Empty Panel")
        elseif ST.IsAuraPanelGroup(group) then
            SetPreviewMessage(preview,
                "Search for a spell in the field below, enter its ID, or drag it into this preview.",
                "Add your first aura",
                "Your first aura sets whether this panel tracks your buffs or your target's debuffs.")
        else
            SetPreviewMessage(preview,
                "Search for a spell or item in the field below, enter an ID, or drag one into this preview.",
                "Add your first entry")
        end
        -- The drop ghost may stand in for the first entry here (DropGhost).
        -- The unified composition included: it holds the message's box at a
        -- readable minimum (UnifiedAnchorPreview's ShrinkMirrorHostToContent),
        -- and the ghost hides the message rather than sharing that box.
        if not readOnly then
            preview.dropGhostMode = isBarMode and "barSlots"
                or (isTextMode and "textSlots" or "iconSlots")
        end
        FinalizePreviewState(preview)
        return
    end

    -- Session view filter (the preview host's quick toggle): drop unavailable
    -- or disabled entries and reflow the rest, except for any selected entries
    -- the player is still editing. Dense ordinals place the cells; every
    -- per-entry surface keeps its group.buttons index.
    -- Never on Bar panels: their mirror is a saved-design projection that
    -- deliberately keeps live usability and enabled state out
    -- (CollectBarEntryStatus), so there is no unavailable/disabled state there
    -- for the toggle to hide. Read-only mirrors stay unfiltered except the
    -- unified cast duplicate, which opts in so both copies of the anchor panel
    -- show the same filtered set.
    local visibleIndices
    if (not readOnly or (options and options.applySessionFilter == true))
        and not isBarMode
        and CS.panelPreviewUnavailableHidden
        and not CS.otherClassLibraryActive then
        local kept = {}
        for index, buttonData in ipairs(buttons) do
            if CooldownCompanion:IsButtonUsable(buttonData, group)
                or IsEntrySelected(index) then
                kept[#kept + 1] = index
            end
        end
        if #kept < count then
            visibleIndices = kept
            count = #kept
        end
    end
    if count == 0 then
        SetPreviewMessage(preview,
            "All entries here are unavailable or disabled, so the preview toggle has hidden them.")
        FinalizePreviewState(preview)
        return
    end

    local geo = GetPanelGeometry(group, isBarMode, isTextMode, visibleIndices)
    local w, h = geo.entryWidth, geo.entryHeight
    local spacing = geo.spacing
    local perRow = math_max(1, geo.buttonsPerRow)
    local style = group.style or {}
    local xMul, yMul, growthAnchor = GetGrowthMultipliers(style.growthOrigin)
    -- Same gate the live layout applies: aura panels (Blizzard's flow
    -- container) fold centered growth to TOPLEFT.
    local centeredEdge = not CooldownCompanion:IsAuraPanel(group)
        and ST.GetCenteredGrowthEdge(style.growthOrigin, geo.orientation) or nil
    if centeredEdge then
        growthAnchor = centeredEdge
    end

    -- Text-mode group header claims a row of space above (or below, for
    -- bottom growth) the entries, exactly like the live layout.
    local headerHeight = 0
    if isTextMode and style.showTextGroupHeader == true then
        headerHeight = (style.textHeaderFontSize or style.textFontSize or 12) + 4
    end

    -- Panel Sections. Every number a section contributes below -- footprint,
    -- position, icon size -- is read straight off the engine's own layout
    -- table, the same one Core/GroupFrameLayout.lua lays the live panel out from.
    -- The mirror must never re-derive a section's geometry: that is the one
    -- way this preview and the world can disagree.
    local sections = ST.GetSectionsForLayout(group)
    -- The drag grammar needs the same partition even before a panel has its
    -- first section: the landings a drag offers are how one gets created.
    --
    -- CREATING the first section takes two entries -- a panel whose only entry
    -- is already the whole base row has nothing to gain by placing it. But once
    -- a section EXISTS the count stops mattering: a lone entry sitting in one
    -- has to be able to come back, and with the temporary menu gone the drag is
    -- the only way out. So an existing section is its own licence to drag.
    local wantSectionDrag = not readOnly and not visibleIndices
        and (count >= 2 or sections ~= nil)
        and ST.PanelSupportsSections(group)
    -- The same model for a spell or item on the CURSOR (the drop-to-add
    -- overlay in ButtonsWideColumn asks for it). One entry is enough here:
    -- there is nothing to move, only something to add, so a lone entry's
    -- free anchors are as much a destination as a crowd's. The unified
    -- composition included: its landings can sit on the strip the attached
    -- bar lanes occupy, and the gesture quiets them (SetLaneChromeFaded),
    -- exactly as the entry drag does. Not under the session filter, for the
    -- entry drag's own reason: a section whose members are filtered out
    -- reads as a free anchor and would offer a section where one already
    -- sits.
    local wantCursorModel = not readOnly and not visibleIndices
        and ST.PanelSupportsSections(group)
    local sectionLayout, sectionPlacement, cellIndex, cellOfIndex
    local sectionLists
    local cellCount = count
    if sections or wantSectionDrag or wantCursorModel then
        -- The engine partitions objects carrying .buttonData, which the slots
        -- do not exist yet to be; a throwaway list of the entries this build is
        -- actually rendering (the session filter may have narrowed it) carries
        -- the master index along for the reorder mapping.
        local entries = {}
        for ordinal = 1, count do
            local index = visibleIndices and visibleIndices[ordinal] or ordinal
            entries[ordinal] = { buttonData = buttons[index], index = index }
        end
        sectionLists = ST.PartitionPanelSectionMembers(group, entries)
    end
    if sections then
        local lists = sectionLists
        sectionLayout = ST.BuildPanelSectionLayout(group, sections, lists,
            w, h, spacing, headerHeight)

        cellCount = #lists.base
        cellIndex, cellOfIndex = {}, {}
        for cell, entry in ipairs(lists.base) do
            cellIndex[cell] = entry.index
            cellOfIndex[entry.index] = cell
        end

        sectionPlacement = {}
        for anchor, info in pairs(sectionLayout.sections) do
            for k, entry in ipairs(lists.members[anchor]) do
                -- Same per-cell positions Core/PanelSections.lua places a live
                -- button with; the fields are the whole of the arithmetic.
                local position = info.positions[k]
                sectionPlacement[entry.index] = {
                    x = position and position.x or info.originX,
                    y = position and position.y or info.originY,
                    width = info.width,
                    height = info.height,
                }
            end
        end
    end

    local contentWidth, contentHeight
    if sectionLayout then
        -- The union footprint, matching ResizeGroupFrame's own clamp, so the
        -- preview scales a sectioned panel by the rect the panel really spans.
        contentWidth = math_max(sectionLayout.totalWidth, 1)
        contentHeight = math_max(sectionLayout.totalHeight, 1)
    else
        local cols, rows
        if geo.orientation == "horizontal" then
            cols = math_min(count, perRow)
            rows = math_ceil(count / perRow)
        else
            rows = math_min(count, perRow)
            cols = math_ceil(count / perRow)
        end
        contentWidth = (cols - 1) * (w + spacing) + w
        contentHeight = (rows - 1) * (h + spacing) + h + headerHeight
    end

    -- The base grid's cells are laid out against the BASE CLUSTER's rect, not
    -- the union -- the live panel does this with an interior anchor frame
    -- (PanelSections' _sectionBaseAnchor). The mirror hands the same result to
    -- one shared content frame by offsetting every cell by the distance between
    -- the two rects' growth-anchor points. Without sections the rects are the
    -- same rect and this is exactly zero, so the grid keeps its old numbers.
    local baseDX, baseDY = 0, 0
    if sectionLayout then
        local unionX, unionY = ST._GetPanelAnchorOffset(growthAnchor, contentWidth, contentHeight)
        local clusterX, clusterY = ST._GetPanelAnchorOffset(growthAnchor,
            sectionLayout.baseWidth, sectionLayout.baseHeight)
        baseDX = sectionLayout.baseOffsetX + sectionLayout.baseWidth / 2 + clusterX
            - contentWidth / 2 - unionX
        baseDY = -sectionLayout.baseOffsetY - sectionLayout.baseHeight / 2 + clusterY
            + contentHeight / 2 - unionY
    end

    -- Scale is needed while styling (badges counter-scale against it), so
    -- compute it up front from the grid extents.
    local scale = GetHostFitScale(host, contentWidth, contentHeight, readOnly)

    local content = preview.content
    content:SetSize(contentWidth, contentHeight)
    content:Show()
    UpdateTextGroupHeader(preview, group, style, headerHeight)

    local poolName = isBarMode and "barSlots" or (isTextMode and "textSlots" or "iconSlots")
    local styleFn = isBarMode and StyleBarEntry or (isTextMode and StyleTextEntry or StyleIconEntry)
    -- The drop ghost (DropGhost) draws on this build's grid; read-only
    -- mirrors take no drop. The unified composition is in: the ghost claims
    -- no strip the bar lanes sit on, only the base row's next cell.
    preview.dropGhostMode = (not readOnly) and poolName or nil

    local layoutDrag = readOnly and { slots = {} } or CreatePreviewLayoutDrag(preview, panelId)
    layoutDrag.iconResolver = isBarMode and GetConfigOnlyBarPreviewIcon or GetLayoutPreviewIcon
    -- The grid holds the BASE members only once sections are in play; the
    -- section members are placed from the layout table instead.
    layoutDrag.count = cellCount
    layoutDrag.cellIndex = cellIndex
    layoutDrag.cellOfIndex = cellOfIndex
    layoutDrag.slotW, layoutDrag.slotH = w, h
    layoutDrag.scale = scale
    layoutDrag.anchor = growthAnchor
    -- For the drop ghost's next-cell arithmetic (DropGhost): the wrap count,
    -- whether the line spreads from its middle, and the Aura Bar Panel's
    -- one-column rule, none of which cellXY can be asked for after the fact.
    layoutDrag.perRow = perRow
    layoutDrag.centered = centeredEdge and true or nil
    layoutDrag.auraColumn = (isBarMode and ST.IsAuraPanelGroup(group)) or nil
    if centeredEdge then
        -- Mirror of the live centered branch in ApplyActiveButtonLayout:
        -- offsets hang off the frame's edge midpoint, so the trailing
        -- partial line centers itself. cellXY doubles as the drag-reorder
        -- hit model, so centering must live here, not after.
        local lineCount = math_ceil(cellCount / perRow)
        layoutDrag.cellXY = function(d)
            local line = math_floor((d - 1) / perRow)
            local indexInLine = (d - 1) % perRow
            local itemsInLine = (line == lineCount - 1) and (cellCount - line * perRow) or perRow
            if geo.orientation == "horizontal" then
                local edgeYMul = centeredEdge == "TOP" and -1 or 1
                return baseDX + (indexInLine - (itemsInLine - 1) / 2) * (w + spacing),
                    baseDY + edgeYMul * (line * (h + spacing) + headerHeight)
            end
            local edgeXMul = centeredEdge == "LEFT" and 1 or -1
            return baseDX + edgeXMul * line * (w + spacing),
                baseDY + ((itemsInLine - 1) / 2 - indexInLine) * (h + spacing) - headerHeight / 2
        end
    else
        layoutDrag.cellXY = function(d)
            local row, col
            if geo.orientation == "horizontal" then
                row = math_floor((d - 1) / perRow)
                col = (d - 1) % perRow
            else
                col = math_floor((d - 1) / perRow)
                row = (d - 1) % perRow
            end
            return baseDX + xMul * col * (w + spacing),
                baseDY + yMul * (row * (h + spacing) + headerHeight)
        end
    end
    -- The pitch between two cells on the same line, which cellXY can only be
    -- asked for once there ARE two cells. The insertion-anchor model borrows it
    -- when a base grid is down to a single cell.
    if geo.orientation == "horizontal" then
        layoutDrag.cellStepX = (centeredEdge and 1 or xMul) * (w + spacing)
        layoutDrag.cellStepY = 0
    else
        layoutDrag.cellStepX = 0
        layoutDrag.cellStepY = (centeredEdge and -1 or yMul) * (h + spacing)
    end
    preview.layoutDrag = layoutDrag
    -- Reorder maps dense cells to group.buttons indices, so it stays off
    -- while the session filter has punched holes in that mapping. A
    -- sectioned panel counts ENTRIES, not base cells: an entry sitting in a
    -- section still has the base row and the other anchors to be dragged to.
    -- A one-entry panel has nowhere to go and stays off -- UNLESS that one entry
    -- is in a section, where the drag is the only way back to the base row.
    local dragModel = (not readOnly and not visibleIndices
        and (count >= 2 or wantSectionDrag)) and layoutDrag or nil
    if dragModel and wantSectionDrag then
        layoutDrag.sectionDrag = SectionDrag.Build(group, sections, sectionLists,
            sectionLayout, w, h, spacing, headerHeight, contentWidth, contentHeight)
        SectionDrag.FloorEmptyBase(layoutDrag.sectionDrag, layoutDrag,
            contentWidth, contentHeight)
        if wantCursorModel then
            -- One model for both gestures: they cannot overlap (an entry drag
            -- refuses to start with a payload on the cursor), and the cursor
            -- drop reads the row through the flagless InRow, so it never
            -- touches InBaseMargin's flag.
            preview.cursorPadModel = layoutDrag.sectionDrag
        end
    elseif wantCursorModel then
        -- A lone entry with no sections has no entry drag to pay for a model,
        -- and most such builds never meet a cursor payload, so the inputs are
        -- stashed and CursorPadModel builds on first use.
        preview.cursorPadInputs = { group, sections, sectionLists, sectionLayout,
            w, h, spacing, headerHeight, contentWidth, contentHeight, layoutDrag }
    end

    for ordinal = 1, count do
        local index = visibleIndices and visibleIndices[ordinal] or ordinal
        local buttonData = buttons[index]
        -- A section member's own icon size, and its position, come from the
        -- engine's layout table; nil means the entry is a base-grid cell.
        local placement = sectionPlacement and sectionPlacement[index]
        local slot = AcquireSlot(preview, content, poolName)
        if isTextMode then
            -- Cell placement stays on the uniform pitch below; only the slot's
            -- own footprint is per-entry, like the live text button.
            slot:SetSize(GetTextSlotSize(group, buttonData, w, h))
        elseif placement then
            -- Sized before styleFn: the mirrored icon crops its texture from
            -- the slot's current size (ST._ApplyIconTexCoord).
            slot:SetSize(placement.width, placement.height)
        else
            slot:SetSize(w, h)
        end

        if placement then
            ApplyPreviewSlotGeometry(preview, slot, "TOPLEFT", placement.x, placement.y)
        else
            local cx, cy = layoutDrag.cellXY(cellOfIndex and cellOfIndex[index] or ordinal)
            ApplyPreviewSlotGeometry(preview, slot, growthAnchor, cx, cy)
        end

        local effectiveStyle
        local barPreviewState
        if isBarMode then
            effectiveStyle = group.style or {}
            if CooldownCompanion.GetEffectiveStyle then
                effectiveStyle = CooldownCompanion:GetEffectiveStyle(effectiveStyle, buttonData)
                    or effectiveStyle
            end
            if not readOnly then
                barPreviewState = GetStoredBarPreviewState(panelId, index)
            end
            ResetBarSlotConditionalVisuals(slot)
        end
        styleFn(slot, buttonData, group, effectiveStyle)
        if not readOnly and not isTextMode then
            ApplySlotEffectPreviews(slot, buttonData, group, panelId, index, isBarMode,
                effectiveStyle, barPreviewState)
        elseif not isTextMode then
            ClearSlotEffectPreviews(slot)
        end
        local status = not readOnly and (isBarMode and CollectBarEntryStatus(buttonData, group)
            or CollectEntryStatus(buttonData, group)) or nil
        local barVisibility
        if isBarMode and not readOnly then
            barVisibility = ResolveBarPreviewVisibility(buttonData, group, barPreviewState)
        end
        if slot.icon and not readOnly then
            slot.icon:SetDesaturated(not status.usable)
        elseif slot.icon then
            slot.icon:SetDesaturated(false)
            -- No conditional pass runs on a read-only mirror, so nothing else
            -- would write the configured icon tint (same resolution the
            -- focused mirror uses, base tint only - saved settings, no state).
            local tintStyle = effectiveStyle or group.style or {}
            if not effectiveStyle and CooldownCompanion.GetEffectiveStyle then
                tintStyle = CooldownCompanion:GetEffectiveStyle(tintStyle, buttonData) or tintStyle
            end
            local baseTint = tintStyle.iconTintColor
            slot.icon:SetVertexColor(baseTint and baseTint[1] or 1,
                baseTint and baseTint[2] or 1,
                baseTint and baseTint[3] or 1,
                baseTint and baseTint[4] or 1)
        end
        if readOnly and isTextMode then
            ApplyTextSlotConditionalPreview(slot, buttonData, group, panelId, index, true)
            slot._cdcCondAnim = nil
        elseif readOnly then
            ResetSlotConditionalVisuals(slot)
        elseif isBarMode then
            ApplyBarSlotConditionalPreview(slot, buttonData, group, panelId, index,
                effectiveStyle, barPreviewState)
        elseif isTextMode then
            ApplyTextSlotConditionalPreview(slot, buttonData, group, panelId, index)
        else
            ApplySlotConditionalPreview(slot, buttonData, group, panelId, index)
        end
        if not readOnly and not isBarMode and status.disabled then
            slot:SetAlpha(PANEL_PREVIEW_DISABLED_ALPHA)
        end
        slot._cdcBaseAlpha = readOnly and 1 or (isBarMode and 1
            or (status.disabled and PANEL_PREVIEW_DISABLED_ALPHA or 1))
        if not readOnly and isBarMode then
            ApplyBarSlotPreviewVisibility(slot, barVisibility, scale, IsEntrySelected(index))
        end
        if readOnly then
            ApplySlotBadges(slot, {}, scale, true)
            DisableReadOnlySlotInteraction(slot)
        else
            ApplySlotBadges(slot, status, scale,
                isBarMode and barVisibility.exactPreview == true)
            ApplySelectionVisuals(slot, index,
                (isBarMode and barVisibility.exactPreview == true)
                    or IsGlowPreviewActiveOnEntry(panelId, index))
            CopyMode.ApplyTargetVisuals(slot, panelId, buttonData)
            -- Pooled slots: written every build so a slot leaving a filtered
            -- build does not keep advertising the pause.
            slot._cdcReorderPausedByFilter = visibleIndices and true or nil
            -- Which section's cluster this icon belongs to, for the hover
            -- handle. Pooled like every flag above: a slot recycled onto a base
            -- cell, a read-only mirror, or a filtered build must not keep
            -- offering another panel's handle.
            slot._cdcSectionAnchor = (dragModel and layoutDrag.sectionDrag and sections)
                and ST.GetPanelSectionForEntry(group, buttonData) or nil
            -- Section members drag like every other entry now: one model, and
            -- the drop target decides what the gesture meant.
            WireEntryInteraction(slot, panelId, index, buttonData, status,
                dragModel, barVisibility)
        end
        layoutDrag.slots[index] = slot
    end

    -- Tick only while at least one slot is animating a conditional preview
    -- (pairs, not 1..count: the session filter keys slots sparsely).
    local anyAnimated = false
    for _, s in pairs(layoutDrag.slots) do
        if s._cdcCondAnim then
            anyAnimated = true
            break
        end
    end
    if not readOnly and anyAnimated then
        EnsureConditionalTicker(preview)
    else
        StopConditionalTicker(preview)
    end

    content:SetScale(scale)
    content:ClearAllPoints()
    content:SetPoint("CENTER", preview.root, "CENTER", 0, 0)

    FinalizePreviewState(preview)
end

-- Entry selection normally does not change saved panel geometry or mirrored
-- visuals. The session filter is the exception: selection determines whether
-- a filtered entry remains in the visible subset, so that path
-- falls back to a full mirror rebuild. Otherwise update the existing selection
-- rings (and bar ghost exposure) in place.
function ST._RefreshButtonPanelPreviewSelection(host, panelId)
    local preview = host and host._cdcPanelPreview
    if not (preview and preview.panelId == panelId and preview.readOnly ~= true) then
        return false
    end

    local reconcileVisuals = CS.panelPreviewVisualsNeedReconcile == true
    CS.panelPreviewVisualsNeedReconcile = nil

    local group = panelId and CooldownCompanion.db.profile.groups[panelId]
    if not group then
        return false
    end

    if CS.panelPreviewUnavailableHidden
        and not CS.otherClassLibraryActive
        and ST._PanelPreviewUnavailableEntryState
        and ST._PanelPreviewUnavailableEntryState(group) == true then
        return false
    end

    local slots = preview.layoutDrag and preview.layoutDrag.slots
    if CooldownCompanion:IsTexturePanelGroup(group) then
        return true
    end
    if not slots then
        return false
    end

    if CooldownCompanion:IsRotationAssistantGroup(group) then
        local slot = slots[1]
        if not slot then
            return false
        end
        local buttonData = slot._cdcPreviewButtonData
        if buttonData and reconcileVisuals then
            local status = CollectEntryStatus(buttonData, group)
            if slot.icon then
                slot.icon:SetDesaturated(not status.usable)
            end
            ApplySlotEffectPreviews(slot, buttonData, group, panelId, 1, false)
            ApplySlotConditionalPreview(slot, buttonData, group, panelId, 1)
            if slot._cdcCondAnim then
                EnsureConditionalTicker(preview)
            end
        end
        if CS.selectedRotationAssistantEntry == true
            and not IsGlowPreviewActiveOnEntry(panelId, 1) then
            slot.selectedHighlight:SetFrameLevel(slot:GetFrameLevel() + PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET)
            ST.ApplyBorderTextures(slot.selectedHighlight.ringTextures, slot.selectedHighlight,
                PANEL_PREVIEW_RING_COLOR, 1, ST.GetEffectiveBorderRenderMode(nil, nil, 1))
            slot.selectedHighlight:Show()
        else
            slot.selectedHighlight:Hide()
        end
        return true
    end

    local isBarMode = group.displayMode == "bars"
    local isTextMode = group.displayMode == "text"
    local isGridPanel = isBarMode or isTextMode or IsIconModePanel(group)
    if reconcileVisuals then
        StopConditionalTicker(preview)
    end
    local anyAnimated = false
    for index, slot in pairs(slots) do
        local buttonData = group.buttons and group.buttons[index]
        if reconcileVisuals and isGridPanel and buttonData then
            local status = isBarMode and CollectBarEntryStatus(buttonData, group)
                or CollectEntryStatus(buttonData, group)
            if slot.icon then
                slot.icon:SetDesaturated(not status.usable)
            end
            if isBarMode then
                local effectiveStyle = group.style or {}
                if CooldownCompanion.GetEffectiveStyle then
                    effectiveStyle = CooldownCompanion:GetEffectiveStyle(effectiveStyle, buttonData)
                        or effectiveStyle
                end
                local barPreviewState = GetStoredBarPreviewState(panelId, index)
                ApplySlotEffectPreviews(slot, buttonData, group, panelId, index, true,
                    effectiveStyle, barPreviewState)
                ApplyBarSlotConditionalPreview(slot, buttonData, group, panelId, index,
                    effectiveStyle, barPreviewState)
            elseif isTextMode then
                ApplyTextSlotConditionalPreview(slot, buttonData, group, panelId, index)
            else
                ApplySlotEffectPreviews(slot, buttonData, group, panelId, index, false)
                ApplySlotConditionalPreview(slot, buttonData, group, panelId, index)
            end
        end
        anyAnimated = anyAnimated or slot._cdcCondAnim ~= nil
        if slot._cdcBarPreviewVisibility then
            RefreshBarSlotWorkspacePresentation(slot)
        end
        local exactBarPreview = slot._cdcBarPreviewVisibility
            and slot._cdcBarPreviewVisibility.exactPreview == true
        ApplySelectionVisuals(slot, index,
            exactBarPreview or IsGlowPreviewActiveOnEntry(panelId, index))
        CopyMode.ApplyTargetVisuals(slot, panelId, buttonData)
    end
    if reconcileVisuals and anyAnimated then
        EnsureConditionalTicker(preview)
    end
    return true
end

-- Saved-design mirror used by Group Panel Overview tiles. The overview owns
-- the only mouse surface; this renderer supplies visuals and natural geometry.
function ST._GetReadOnlyPanelPreviewNaturalSize(panelId)
    local group = panelId and CooldownCompanion.db.profile.groups[panelId]
    return GetPanelPreviewNaturalSize(group)
end

function ST._BuildReadOnlyPanelPreview(host, panelId)
    if not host then return nil, 220, 90 end
    local naturalWidth, naturalHeight =
        ST._GetReadOnlyPanelPreviewNaturalSize(panelId)
    ST._BuildButtonPanelPreview(host, panelId, { readOnly = true })
    local preview = host._cdcPanelPreview
    return preview and preview.root or nil, naturalWidth, naturalHeight
end

-- Detached-data variants for import mode's incoming-panel tiles: the panel
-- exists only inside a decoded (rehydrated) payload, not in the profile.
function ST._GetReadOnlyPanelPreviewNaturalSizeFromData(groupData)
    return GetPanelPreviewNaturalSize(groupData)
end

function ST._BuildReadOnlyPanelPreviewFromData(host, groupData)
    if not host then return nil, 220, 90 end
    local naturalWidth, naturalHeight = GetPanelPreviewNaturalSize(groupData)
    ST._BuildButtonPanelPreview(host, nil, { readOnly = true, groupData = groupData })
    local preview = host._cdcPanelPreview
    return preview and preview.root or nil, naturalWidth, naturalHeight
end

function ST._ReleaseReadOnlyPanelPreview(host)
    local preview = host and host._cdcPanelPreview
    if not preview then return end
    StopConditionalTicker(preview)
    StopTextureMirrorEffects(preview.textureMirror)
    for poolName, pool in pairs(preview.pools) do
        local used = preview.used[poolName] or 0
        for index = 1, used do
            local slot = pool[index]
            if slot then
                DisableReadOnlySlotInteraction(slot)
                slot:Hide()
                slot:ClearAllPoints()
            end
        end
        preview.used[poolName] = 0
    end
    if preview.textureMirror then
        preview.textureMirror.root:EnableMouse(false)
        preview.textureMirror.root:Hide()
    end
    if preview.textHeader then preview.textHeader:Hide() end
    preview.content:Hide()
    preview.root:Hide()
end

-- The Live Preview's drop-to-add overlay (ButtonsWideColumn) tracks a spell
-- or item on the cursor against the panel's section landings through these.
ST._TrackPreviewCursorDrop = SectionDrag.TrackCursorDrop
ST._EndPreviewCursorDrop = SectionDrag.EndCursorDrop
ST._ResolvePreviewCursorDrop = SectionDrag.ResolveCursorDrop
-- The same overlay, and the add box's suggestion list (SpellItemAdd), drive
-- the drop ghost through these.
ST._ShowPreviewDropGhost = DropGhost.Show
ST._HidePreviewDropGhost = DropGhost.Hide

-- Quick-toggle support for the buttons-view preview host: nil when this
-- panel type renders no entry grid the filter touches; otherwise whether it
-- contains any unavailable or disabled entry the filter can act on. Filtering
-- reuses IsButtonUsable; selected entries are preserved by the build pass.
-- Bar panels are nil on purpose: their mirror is a saved-design projection
-- the filter never applies to, so the badge must not offer it there.
function ST._PanelPreviewUnavailableEntryState(group)
    if not group then return nil end
    if group.displayMode ~= "text" and not IsIconModePanel(group) then
        return nil
    end
    for _, buttonData in ipairs(group.buttons or {}) do
        if not CooldownCompanion:IsButtonUsable(buttonData, group) then
            return true
        end
    end
    return false
end

function ST._ReleaseButtonPanelPreview(host)
    local preview = host and host._cdcPanelPreview
    if preview then
        StopConditionalTicker(preview)
        StopTextureMirrorEffects(preview.textureMirror)
        DropGhost.Reset(preview)
        local barPool = preview.pools.barSlots or {}
        for index = 1, (preview.used.barSlots or 0) do
            local slot = barPool[index]
            if slot then ResetBarSlotWorkspaceState(slot) end
        end
        -- The banner can live on an external host (unified composition), so
        -- hiding the root does not necessarily take it along.
        if preview.copyBanner then
            preview.copyBanner:Hide()
        end
        preview.root:Hide()
    end
end
