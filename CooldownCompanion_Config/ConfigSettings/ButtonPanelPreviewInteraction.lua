--[[
    CooldownCompanion - ButtonPanelPreviewInteraction
    Customization copying, entry drag/reorder, tooltips, clicks, and drop ghosts.

    Part of the ButtonPanelPreview family; see its ordered block in the addon TOC.
    Private helpers are shared through ST._ButtonPanelPreview.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState
local GetConfigEntryDisplayName = ST._GetConfigEntryDisplayName
local SelectConfigButton = ST._SelectConfigButton
local ShowEntryContextMenu = ST._ShowEntryContextMenu
local PerformButtonReorder = ST._PerformButtonReorder
local StartDragTracking = ST._StartDragTracking
local CancelDrag = ST._CancelDrag

local PP = ST._ButtonPanelPreview

-- ButtonPanelPreviewShared.lua
local PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET = PP.PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET
local CopyMode = PP.CopyMode
local QueuePreviewSlotTween = PP.QueuePreviewSlotTween
local EnsureGapFrame = PP.EnsureGapFrame
local ConfigurePreviewGhost = PP.ConfigurePreviewGhost
local StartPreviewTicker = PP.StartPreviewTicker
local ClearPreviewGhost = PP.ClearPreviewGhost
local ENTRY_STATUS_BADGE_ATLAS = PP.ENTRY_STATUS_BADGE_ATLAS
local PANEL_PREVIEW_AURA_SPACE_BADGE_ATLAS = PP.PANEL_PREVIEW_AURA_SPACE_BADGE_ATLAS
local PANEL_PREVIEW_VISIBILITY_BADGE_ATLAS = PP.PANEL_PREVIEW_VISIBILITY_BADGE_ATLAS
local RefreshBarSlotWorkspacePresentation = PP.RefreshBarSlotWorkspacePresentation
local SLOT_FACTORIES = PP.SLOT_FACTORIES
local DisableReadOnlySlotInteraction = PP.DisableReadOnlySlotInteraction
local ApplyBarSlotVisualAlpha = PP.ApplyBarSlotVisualAlpha
local GetTextSlotSize = PP.GetTextSlotSize
local GetPanelGeometry = PP.GetPanelGeometry
local GetGrowthMultipliers = PP.GetGrowthMultipliers
local GetHostFitScale = PP.GetHostFitScale
local HidePreviewMessage = PP.HidePreviewMessage
local ApplyPreviewSlotGeometry = PP.ApplyPreviewSlotGeometry

-- ButtonPanelPreviewSections.lua
local SectionDrag = PP.SectionDrag

-- ButtonPanelPreviewBars.lua
local ResetBarSlotConditionalVisuals = PP.ResetBarSlotConditionalVisuals
local StyleBarEntry = PP.StyleBarEntry
local ApplyBarSlotConditionalPreview = PP.ApplyBarSlotConditionalPreview

-- ButtonPanelPreviewEffects.lua
local ClearSlotEffectPreviews = PP.ClearSlotEffectPreviews

-- ButtonPanelPreviewText.lua
local StyleTextEntry = PP.StyleTextEntry
local ApplyTextSlotConditionalPreview = PP.ApplyTextSlotConditionalPreview
local UpdateTextGroupHeader = PP.UpdateTextGroupHeader

-- ButtonPanelPreviewIcons.lua
local StyleIconEntry = PP.StyleIconEntry
local ResetSlotConditionalVisuals = PP.ResetSlotConditionalVisuals

------------------------------------------------------------------------
-- Copy Customization: armed from the entry context menu's "Copy
-- Customization To..." submenu. While armed, a banner rides the preview,
-- compatible entries ring green, and left-clicking one copies the armed
-- customization onto it. The mode survives panel switches (any compatible
-- entry anywhere is a target) and stays armed after each apply; Esc
-- (Panel.lua's key chain), right-click, or clicking the source cancels.
--
-- Copy helpers stay private to this block; their operations publish through
-- the CopyMode table owned by ButtonPanelPreviewShared.lua.
------------------------------------------------------------------------
do

local PANEL_PREVIEW_COPY_COLOR = { 0.30, 0.90, 0.45, 1 }
local PANEL_PREVIEW_COPY_BANNER_HEIGHT = 20

-- StyleLens.lua loads before this file (config toc order), so its exports are
-- real by the time this chunk runs and are captured as block upvalues. A
-- missing export would be a packaging error; nothing here fails open.
local CanUseConfigOverrideSection = ST._CanButtonUseConfigOverrideSection
local GroupSupportsPerButtonOverrides = ST._GroupSupportsPerButtonOverrides

-- Resolves the armed source from ids at call time: the mode outlives
-- arbitrary user actions, so the index may have shifted (reorder,
-- duplicate) or the entry may be gone entirely. sourceRef is the identity
-- token; a repairable shift re-stamps the index, anything else is nil.
local function ResolveCopyCustomizationSource(state)
    local groups = CooldownCompanion.db.profile.groups
    local group = groups and groups[state.sourceGroupId]
    if not (group and group.buttons) then return nil end
    local buttonData = group.buttons[state.sourceButtonIndex]
    if buttonData == state.sourceRef then
        return group, buttonData
    end
    for i, candidate in ipairs(group.buttons) do
        if candidate == state.sourceRef then
            state.sourceButtonIndex = i
            return group, candidate
        end
    end
    return nil
end

local function CancelCopyCustomization(options)
    if not CS.copyCustomization then return end
    CS.copyCustomization = nil
    if not (options and options.skipRefresh) then
        CooldownCompanion:RefreshConfigPanel()
    end
end

local function ArmCopyCustomization(groupId, buttonIndex, buttonData, scope, sectionId)
    -- Rival modes own the same columns and selection stores.
    if CS.exportMode and ST._ExitExportMode then
        ST._ExitExportMode({ skipRefresh = true })
    end
    if CS.importMode and ST._ExitImportMode then
        ST._ExitImportMode({ skipRefresh = true })
    end
    if CS.copyPanelSettings and ST._CancelCopyPanelSettings then
        ST._CancelCopyPanelSettings({ skipRefresh = true })
    end
    wipe(CS.selectedButtons)
    CS.copyCustomization = {
        sourceGroupId = groupId,
        sourceButtonIndex = buttonIndex,
        sourceRef = buttonData,
        scope = scope,
        sectionId = sectionId,
    }
    CooldownCompanion:RefreshConfigPanel()
end

ST._ArmCopyCustomization = ArmCopyCustomization
ST._CancelCopyCustomization = CancelCopyCustomization

local function GetCopyCustomizationLabel(state)
    if state.scope == "format" then return "Text Format" end
    if state.scope == "all" then return "All Customizations" end
    local sectionDef = ST.OVERRIDE_SECTIONS[state.sectionId]
    return sectionDef and sectionDef.label or tostring(state.sectionId)
end

local function CanCopySectionToEntry(targetGroup, targetButtonData, sectionId)
    local sectionDef = ST.OVERRIDE_SECTIONS[sectionId]
    if not sectionDef then return false end
    if sectionDef.modes[targetGroup.displayMode or "icons"] ~= true then return false end
    -- == true drops the reason the helper returns alongside its verdict.
    return CanUseConfigOverrideSection(targetButtonData, sectionId, targetGroup) == true
end

local function IsEligibleCopyTarget(state, targetGroup, targetButtonData)
    if not (state and targetGroup and targetButtonData) then return false end
    local sourceGroup, sourceData = ResolveCopyCustomizationSource(state)
    if not sourceData or targetButtonData == sourceData then return false end
    if not GroupSupportsPerButtonOverrides(targetGroup) then return false end
    -- The mode outlives arbitrary edits, so the armed payload can be
    -- reverted on the source while the rings are up. A vanished payload
    -- must fail here: a nil format would WIPE the target's saved format,
    -- and a cleared section would no-op while reporting success.
    if state.scope == "format" then
        return sourceData.textFormat ~= nil
            and (targetGroup.displayMode or "icons") == "text"
    end
    if state.scope == "section" then
        if not (sourceData.overrideSections
            and sourceData.overrideSections[state.sectionId]) then
            return false
        end
        return CanCopySectionToEntry(targetGroup, targetButtonData, state.sectionId)
    end
    -- "all": eligible when at least one of the source's customizations lands.
    if sourceData.textFormat ~= nil and (targetGroup.displayMode or "icons") == "text" then
        return true
    end
    for sectionId in pairs(sourceData.overrideSections or {}) do
        if CanCopySectionToEntry(targetGroup, targetButtonData, sectionId) then
            return true
        end
    end
    return false
end

-- Returns true when the click was consumed by an armed copy mode.
local function HandleCopyCustomizationClick(panelId, index, buttonData)
    local state = CS.copyCustomization
    if not state then return false end
    local targetGroup = CooldownCompanion.db.profile.groups[panelId]
    if not targetGroup then return false end
    local sourceGroup, sourceData = ResolveCopyCustomizationSource(state)
    if not sourceData then
        -- The armed source no longer exists; nothing sane to copy.
        CancelCopyCustomization()
        return true
    end
    if buttonData == sourceData then
        CancelCopyCustomization()
        return true
    end
    if not IsEligibleCopyTarget(state, targetGroup, buttonData) then
        -- Ineligible entry: stay armed; the hover tooltip explains why.
        return true
    end

    local sourceStyle = sourceGroup.style or {}
    local applied, skipped, formatCopied = 0, 0, false
    if state.scope == "section" then
        if CooldownCompanion:CopySectionOverride(sourceData, sourceStyle, buttonData, state.sectionId) then
            applied = 1
        end
    elseif state.scope == "format" then
        -- Eligibility guaranteed a non-nil source format at this click.
        buttonData.textFormat = sourceData.textFormat
        formatCopied = true
        applied = 1
    else
        local sections = sourceData.overrideSections or {}
        for _, sectionId in ipairs(ST.OVERRIDE_SECTION_ORDER or {}) do
            if sections[sectionId] then
                if CanCopySectionToEntry(targetGroup, buttonData, sectionId)
                    and CooldownCompanion:CopySectionOverride(sourceData, sourceStyle, buttonData, sectionId) then
                    applied = applied + 1
                else
                    skipped = skipped + 1
                end
            end
        end
        if sourceData.textFormat ~= nil then
            if (targetGroup.displayMode or "icons") == "text" then
                buttonData.textFormat = sourceData.textFormat
                formatCopied = true
                applied = applied + 1
            else
                skipped = skipped + 1
            end
        end
    end

    if applied == 0 then
        -- Nothing landed (the payload vanished between the eligibility check
        -- and the write). Leave the target untouched and report nothing.
        return true
    end

    CooldownCompanion:UpdateGroupStyle(panelId)
    -- The format is re-parsed on the way through PopulateGroupButtons, which
    -- only the frame refresh reaches. Paid only when a format actually copied.
    if formatCopied then
        CooldownCompanion:RefreshGroupFrame(panelId)
    end
    local name = GetConfigEntryDisplayName(buttonData) or buttonData.name or "entry"
    if skipped > 0 then
        state.lastAppliedText = ("Applied to %s (%d of %d)"):format(name, applied, applied + skipped)
    else
        state.lastAppliedText = "Applied to " .. name
    end
    CooldownCompanion:RefreshConfigPanel()
    return true
end

local function EnsureCopyCustomizationBanner(preview)
    -- The unified anchor composition builds the mirror into an inner host
    -- shrunk to the panel content, where a banner would sit on the entries
    -- themselves; it passes the outer Live Preview host so the strip reads
    -- at the top of the whole preview instead. Re-anchored on every ensure:
    -- the same preview state can build under either composition.
    local bannerHost = preview.copyBannerHost or preview.root
    local banner = preview.copyBanner
    if banner then
        banner:SetParent(bannerHost)
        banner:ClearAllPoints()
        banner:SetPoint("TOPLEFT", bannerHost, "TOPLEFT", 0, 0)
        banner:SetPoint("TOPRIGHT", bannerHost, "TOPRIGHT", 0, 0)
        return banner
    end

    -- Slim full-width strip whose dark fill and green accent line fade out
    -- toward the sides (the retired override-targeting banner's shape).
    banner = CreateFrame("Frame", nil, bannerHost)
    banner:SetPoint("TOPLEFT", bannerHost, "TOPLEFT", 0, 0)
    banner:SetPoint("TOPRIGHT", bannerHost, "TOPRIGHT", 0, 0)
    banner:SetHeight(PANEL_PREVIEW_COPY_BANNER_HEIGHT)

    local clear = CreateColor(0, 0, 0, 0)
    local fill = CreateColor(0, 0, 0, 0.7)
    local accent = CreateColor(PANEL_PREVIEW_COPY_COLOR[1],
        PANEL_PREVIEW_COPY_COLOR[2], PANEL_PREVIEW_COPY_COLOR[3], 0.8)
    banner.bgLeft = banner:CreateTexture(nil, "BACKGROUND")
    banner.bgLeft:SetPoint("TOPLEFT")
    banner.bgLeft:SetPoint("BOTTOMRIGHT", banner, "BOTTOM", 0, 0)
    banner.bgLeft:SetTexture("Interface/Buttons/WHITE8x8")
    banner.bgLeft:SetGradient("HORIZONTAL", clear, fill)
    banner.bgRight = banner:CreateTexture(nil, "BACKGROUND")
    banner.bgRight:SetPoint("TOPLEFT", banner, "TOP", 0, 0)
    banner.bgRight:SetPoint("BOTTOMRIGHT")
    banner.bgRight:SetTexture("Interface/Buttons/WHITE8x8")
    banner.bgRight:SetGradient("HORIZONTAL", fill, clear)

    banner.lineLeft = banner:CreateTexture(nil, "BORDER")
    banner.lineLeft:SetPoint("BOTTOMLEFT")
    banner.lineLeft:SetPoint("BOTTOMRIGHT", banner, "BOTTOM", 0, 0)
    banner.lineLeft:SetHeight(1)
    banner.lineLeft:SetTexture("Interface/Buttons/WHITE8x8")
    banner.lineLeft:SetGradient("HORIZONTAL", clear, accent)
    banner.lineRight = banner:CreateTexture(nil, "BORDER")
    banner.lineRight:SetPoint("BOTTOMLEFT", banner, "BOTTOM", 0, 0)
    banner.lineRight:SetPoint("BOTTOMRIGHT")
    banner.lineRight:SetHeight(1)
    banner.lineRight:SetTexture("Interface/Buttons/WHITE8x8")
    banner.lineRight:SetGradient("HORIZONTAL", accent, clear)

    banner.text = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    -- Nudged right so the crosshair + text block reads centered.
    banner.text:SetPoint("CENTER", banner, "CENTER", 9, 0)
    banner.text:SetJustifyH("LEFT")
    banner.text:SetWordWrap(false)

    banner.crosshair = banner:CreateTexture(nil, "OVERLAY")
    banner.crosshair:SetSize(12, 12)
    banner.crosshair:SetPoint("RIGHT", banner.text, "LEFT", -5, 0)
    banner.crosshair:SetAtlas("Crosshair_VehichleCursor_32")
    banner.crosshair:SetVertexColor(PANEL_PREVIEW_COPY_COLOR[1],
        PANEL_PREVIEW_COPY_COLOR[2], PANEL_PREVIEW_COPY_COLOR[3])

    banner:Hide()
    preview.copyBanner = banner
    return banner
end

-- Rebuilt with every preview build: the mode deliberately survives panel
-- switches, so whichever panel the preview shows carries the banner.
local function UpdateCopyCustomizationBanner(preview)
    local state = preview.readOnly ~= true and CS.copyCustomization or nil
    if state and not ResolveCopyCustomizationSource(state) then
        -- The armed source is gone (deleted, moved away, profile changed).
        -- Clear silently - we're already mid-rebuild.
        CS.copyCustomization = nil
        state = nil
    end

    local banner = preview.copyBanner
    if not state then
        if banner then banner:Hide() end
        return
    end

    banner = EnsureCopyCustomizationBanner(preview)
    local text = "Click an entry to apply |cffffd100"
        .. GetCopyCustomizationLabel(state) .. "|r"
    if state.lastAppliedText then
        text = text .. "  |cff99e6a3" .. state.lastAppliedText .. "|r"
    end
    banner.text:SetText(text)
    banner:SetFrameLevel((preview.copyBannerHost or preview.root):GetFrameLevel() + 40)
    banner:Show()
end

-- Green ring on the entries an armed copy click can land on. A dedicated
-- frame, NOT slot.selectedHighlight: the source entry is usually still
-- selected while the mode is armed, so the two rings coexist.
local function ApplyCopyTargetVisuals(slot, panelId, buttonData)
    local state = CS.copyCustomization
    local eligible = false
    if state and panelId and buttonData then
        local targetGroup = CooldownCompanion.db.profile.groups[panelId]
        eligible = IsEligibleCopyTarget(state, targetGroup, buttonData)
    end
    if not eligible then
        if slot.copyTargetHighlight then slot.copyTargetHighlight:Hide() end
        return
    end

    local highlight = slot.copyTargetHighlight
    if not highlight then
        highlight = CreateFrame("Frame", nil, slot)
        highlight:SetAllPoints(slot)
        highlight:EnableMouse(false)
        highlight.ringTextures = {}
        for i = 1, 4 do
            highlight.ringTextures[i] = highlight:CreateTexture(nil, "OVERLAY")
        end
        slot.copyTargetHighlight = highlight
    end
    highlight:SetFrameLevel(slot:GetFrameLevel() + PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET)
    ST.ApplyBorderTextures(highlight.ringTextures, highlight,
        PANEL_PREVIEW_COPY_COLOR, 1, ST.GetEffectiveBorderRenderMode(nil, nil, 1))
    highlight:Show()
end

CopyMode.COLOR = PANEL_PREVIEW_COPY_COLOR
CopyMode.Cancel = CancelCopyCustomization
CopyMode.GetLabel = GetCopyCustomizationLabel
CopyMode.IsEligibleTarget = IsEligibleCopyTarget
CopyMode.HandleClick = HandleCopyCustomizationClick
CopyMode.UpdateBanner = UpdateCopyCustomizationBanner
CopyMode.ApplyTargetVisuals = ApplyCopyTargetVisuals

end

-- CELL space vs entry index. The drag model numbers the cells of the grid it
-- hit-tests, and layoutDrag.slots stays keyed by group.buttons index (the
-- selection refresh reads it that way). On an ordinary panel the two numbers
-- are the same and both maps are nil. On a SECTIONED panel the grid holds only
-- the base members, so cellIndex (cell -> entry index) and cellOfIndex (entry
-- index -> cell, nil for a section member) translate between them.
local function LayoutDragCellIndex(layoutDrag, cell)
    local map = layoutDrag.cellIndex
    return map and map[cell] or cell
end

local function LayoutDragIndexCell(layoutDrag, index)
    local map = layoutDrag.cellOfIndex
    if map then return map[index] end
    return index
end

-- Slide the remaining slots into the arrangement they'd have after the
-- drop: the lifted entry's slot goes invisible, the others compact in
-- order with a gap held open at the insertion cell.
local function UpdateGridDragPreview(preview, layoutDrag, sourceCell, dropTarget, sourceIndex)
    local insertIndex = dropTarget and dropTarget.insertIndex
    local gapPos
    if insertIndex then
        gapPos = insertIndex
        -- A section member is not one of the base grid's cells, so nothing
        -- collapses behind it and the gap may sit one past the last cell.
        if sourceCell and gapPos > sourceCell then gapPos = gapPos - 1 end
        local maxGap = layoutDrag.count + (sourceCell and 0 or 1)
        if gapPos > maxGap then gapPos = maxGap end
    end
    local renderIndex = 1
    for i = 1, layoutDrag.count do
        local slot = layoutDrag.slots[LayoutDragCellIndex(layoutDrag, i)]
        if slot then
            if i == sourceCell then
                slot:SetAlpha(0)
            else
                local displayIndex = renderIndex
                if gapPos and displayIndex >= gapPos then
                    displayIndex = displayIndex + 1
                end
                local x, y = layoutDrag.cellXY(displayIndex)
                QueuePreviewSlotTween(preview, slot, layoutDrag.anchor, x, y)
                renderIndex = renderIndex + 1
            end
        end
    end
    if gapPos then
        local gap = EnsureGapFrame(preview)
        -- The base grid's insertion gap is a reorder cue, not a snap: back to
        -- the ring blue whatever colour a lane target last left on the tile.
        SectionDrag.SetGapAccent(preview, false)
        gap:SetSize(layoutDrag.slotW, layoutDrag.slotH)
        local x, y = layoutDrag.cellXY(gapPos)
        QueuePreviewSlotTween(preview, gap, layoutDrag.anchor, x, y)
        gap:Show()
    elseif preview.gapFrame then
        preview.gapFrame:Hide()
    end
    -- Past the base grid's margin the grid is already un-shuffled above (no
    -- insertion index, no gap); a lane target opens its own gap, and a
    -- create target slides the lifted entry to its landing.
    if layoutDrag.sectionDrag then
        SectionDrag.UpdateLanes(preview, layoutDrag, sourceIndex, dropTarget)
        SectionDrag.UpdateLanding(preview, layoutDrag, sourceIndex, sourceCell, dropTarget)
    end
end

local function ResetGridDragPreview(preview, layoutDrag)
    SectionDrag.HideLandingTrail(preview)
    for i = 1, layoutDrag.count do
        local slot = layoutDrag.slots[LayoutDragCellIndex(layoutDrag, i)]
        if slot then
            local x, y = layoutDrag.cellXY(i)
            QueuePreviewSlotTween(preview, slot, layoutDrag.anchor, x, y)
            slot:SetAlpha(slot._cdcBaseAlpha or 1)
        end
    end
    if preview.gapFrame then
        preview.gapFrame:Hide()
    end
    if layoutDrag.sectionDrag then
        SectionDrag.ResetLanes(preview, layoutDrag)
    end
end

local function CreatePreviewLayoutDrag(preview, panelId)
    -- Builders fill in count, slotW/H, scale, anchor, and cellXY (display
    -- cell index -> anchored x,y offset) after creating the model.
    local layoutDrag = {
        panelPreview = true,
        -- The whole-section handle is offered from a slot's OnEnter, and that
        -- handler only ever gets the drag model; these two carry the rest of
        -- the context it needs without another parameter on the wiring.
        preview = preview,
        panelId = panelId,
        slots = {},
        count = 0,
        slotW = 1,
        slotH = 1,
        scale = 1,
        anchor = "TOPLEFT",
    }

    -- Insertion anchors: midpoints between consecutive slot centers within
    -- a run (row or column), end positions extrapolated half a step beyond
    -- the run, and TWO anchors per wrap boundary (end of the previous run
    -- plus start of the next, same insertion index) — a raw midpoint there
    -- would sit diagonally between the runs in empty space and misassign
    -- drops near row/column edges. Pure geometry: covers both orientations
    -- and every growth origin.
    layoutDrag.resolveDropTarget = function(cursorX, cursorY, state)
        local count = layoutDrag.count
        local sectionDrag = layoutDrag.sectionDrag
        if count < 2 and not sectionDrag then return nil end
        local root = preview.root
        if not (root and root:IsVisible() and root.GetScaledRect) then return nil end
        -- The plain grid's insertion has no reach of its own (the nearest
        -- candidate always answers), so it is bounded by the box the
        -- preview may use plus a margin. A section model needs no such
        -- fence: every target below it is bounded already (containment, the
        -- row's skirt, a landing's one-cell reach), and a landing can sit
        -- past the box on a tightly fitted preview or a far section offset.
        if not sectionDrag
            and not SectionDrag.CursorInBox(preview, cursorX, cursorY, 40) then
            return nil
        end
        -- The whole-section handle answers to free landings and nothing
        -- else: not the base grid, not another section's lane.
        if state and state.sectionHandle then
            if not sectionDrag then return nil end
            local view = SectionDrag.View(preview.content)
            if not view then return nil end
            return SectionDrag.ResolveLanding(preview, sectionDrag, view, cursorX, cursorY)
        end

        -- Three ways to a target, in the order they win: the cluster the
        -- cursor is ON, at the position it names; the row's own region,
        -- where nothing about the base insertion changed; and, past that
        -- region, the landing the cursor is near.
        if sectionDrag then
            local view = SectionDrag.View(preview.content)
            if not view then return nil end
            local onLane = SectionDrag.ResolveLane(sectionDrag, view, cursorX, cursorY,
                SectionDrag.EntryLaneBlocker(sectionDrag, panelId, state))
            if onLane then return onLane end
            if not SectionDrag.InBaseMargin(sectionDrag, view, cursorX, cursorY) then
                return SectionDrag.ResolveLanding(preview, sectionDrag, view, cursorX, cursorY,
                    state and state.slotData and state.slotData.index)
            end
            -- An all-sectioned panel has no cells to measure an insertion
            -- against; the base grid can still be rejoined at its one position.
            if count < 1 then return { insertIndex = 1 } end
        end

        -- Base cell centers, NOT live slot rects: the slots animate while
        -- a drag is held, and resolving against moving frames would make
        -- the drop target oscillate under the cursor (the "stable slots"
        -- trick from the resources preview).
        local content = preview.content
        local cLeft, cBottom, cWidth, cHeight = content:GetScaledRect()
        if not (cLeft and cBottom and cWidth and cHeight) then return nil end
        local localW = content:GetWidth() or 1
        local localH = content:GetHeight() or 1
        local factor = (localW > 0) and (cWidth / localW) or 1
        local anchor = layoutDrag.anchor
        local slotW, slotH = layoutDrag.slotW, layoutDrag.slotH

        local centers = {}
        for i = 1, count do
            local x, y = layoutDrag.cellXY(i)
            -- Convert the anchored offset to top-left space, then to the
            -- scaled screen coordinates raw cursor values live in.
            local tlX, tlY = SectionDrag.CellCenter(anchor, x, y,
                slotW, slotH, localW, localH)
            centers[i] = {
                x = cLeft + tlX * factor,
                y = cBottom + cHeight + tlY * factor,
            }
        end

        -- Consecutive centers share a run when they stay on the same row
        -- line (small y delta) or column line (small x delta); a wrap jump
        -- always moves a full cell on both axes.
        local halfW = slotW * factor / 2
        local halfH = slotH * factor / 2
        local function sameRun(a, b)
            return math.abs(centers[b].y - centers[a].y) < halfH
                or math.abs(centers[b].x - centers[a].x) < halfW
        end
        -- Intra-run step at slot i; single-slot runs (e.g. a short last
        -- row) borrow the first measurable step so their boundary anchors
        -- still sit beside the slot instead of on top of it.
        -- A one-cell base grid has no measurable step, and a section member
        -- dropping back into it still has to land before or after that cell.
        -- The builder's own in-line pitch answers that; with two cells or more
        -- the loop below always measures a real step and overwrites it.
        local globalStepX = (layoutDrag.cellStepX or 0) * factor
        local globalStepY = (layoutDrag.cellStepY or 0) * factor
        for i = 1, count - 1 do
            if sameRun(i, i + 1) then
                globalStepX = centers[i + 1].x - centers[i].x
                globalStepY = centers[i + 1].y - centers[i].y
                break
            end
        end
        local function runStep(i)
            if i < count and sameRun(i, i + 1) then
                return centers[i + 1].x - centers[i].x, centers[i + 1].y - centers[i].y
            end
            if i > 1 and sameRun(i - 1, i) then
                return centers[i].x - centers[i - 1].x, centers[i].y - centers[i - 1].y
            end
            return globalStepX, globalStepY
        end

        local candidates = {}
        local function AddCandidate(x, y, insertIndex)
            candidates[#candidates + 1] = { x = x, y = y, insertIndex = insertIndex }
        end
        local sx, sy = runStep(1)
        AddCandidate(centers[1].x - sx / 2, centers[1].y - sy / 2, 1)
        for i = 2, count do
            if sameRun(i - 1, i) then
                AddCandidate((centers[i - 1].x + centers[i].x) / 2,
                    (centers[i - 1].y + centers[i].y) / 2, i)
            else
                local ex, ey = runStep(i - 1)
                AddCandidate(centers[i - 1].x + ex / 2, centers[i - 1].y + ey / 2, i)
                local bx, by = runStep(i)
                AddCandidate(centers[i].x - bx / 2, centers[i].y - by / 2, i)
            end
        end
        local ex, ey = runStep(count)
        AddCandidate(centers[count].x + ex / 2, centers[count].y + ey / 2, count + 1)

        local bestIndex, bestDist
        for _, cand in ipairs(candidates) do
            local dx, dy = cursorX - cand.x, cursorY - cand.y
            local dist = dx * dx + dy * dy
            if not bestDist or dist < bestDist then
                bestDist, bestIndex = dist, cand.insertIndex
            end
        end
        return { insertIndex = bestIndex }
    end

    -- A section member has no base cell (LayoutDragIndexCell returns nil for
    -- it), which is exactly the state the grid preview reads as "the lifted
    -- entry is not one of mine". Only a drag with neither a cell NOR a section
    -- model behind it has nothing to say.
    local function ResolveDragSource(state)
        local sourceIndex = state.slotData and state.slotData.index
        if not sourceIndex then return nil end
        local sourceCell = LayoutDragIndexCell(layoutDrag, sourceIndex)
        if not (sourceCell or layoutDrag.sectionDrag) then return nil end
        return sourceIndex, sourceCell
    end

    -- The handle drag reuses this whole model; the marker on the state is the
    -- only thing that separates the two gestures, and it is read first
    -- everywhere so a section move never falls into the entry paths.
    local function RunHandleDragFrame(state)
        SectionDrag.HideHandle(preview)
        if not preview.ghostActive then
            ConfigurePreviewGhost(preview, layoutDrag,
                state.slotData and state.slotData.buttonData)
        end
        SectionDrag.UpdateHandleDrag(preview, layoutDrag, state.sectionHandle,
            state.dropTarget)
        StartPreviewTicker(preview)
    end

    -- The entry drag's gesture: open for the whole drag, judged once for
    -- the entry in hand (the key names it, so a new drag re-judges), with
    -- the aura-lane blocker deciding which lanes refuse it.
    local function BeginEntryGesture(state, sourceIndex)
        local model = layoutDrag.sectionDrag
        if not model then return end
        SectionDrag.BeginGesture(preview, model, "entry:" .. tostring(sourceIndex),
            SectionDrag.EntryAnchorState,
            SectionDrag.EntryLaneBlocker(model, panelId, state))
    end

    layoutDrag.onActivate = function(state)
        GameTooltip:Hide()
        if state.sectionHandle then
            RunHandleDragFrame(state)
            return
        end
        local sourceIndex, sourceCell = ResolveDragSource(state)
        if not sourceIndex then return end
        local slot = layoutDrag.slots[sourceIndex]
        if slot and slot.hoverHighlight then
            slot.hoverHighlight:Hide()
        end
        ConfigurePreviewGhost(preview, layoutDrag, state.slotData and state.slotData.buttonData)
        BeginEntryGesture(state, sourceIndex)
        UpdateGridDragPreview(preview, layoutDrag, sourceCell, state.dropTarget, sourceIndex)
        StartPreviewTicker(preview)
    end

    layoutDrag.onUpdate = function(state, cursorX, cursorY, dropTarget)
        if state.sectionHandle then
            RunHandleDragFrame(state)
            return
        end
        local sourceIndex, sourceCell = ResolveDragSource(state)
        if not sourceIndex then return end
        BeginEntryGesture(state, sourceIndex)
        UpdateGridDragPreview(preview, layoutDrag, sourceCell, dropTarget, sourceIndex)
        if not preview.ghostActive then
            ConfigurePreviewGhost(preview, layoutDrag, state.slotData.buttonData)
        end
        StartPreviewTicker(preview)
    end

    layoutDrag.onCancel = function()
        -- One exit for both gestures, which is what makes Escape work on the
        -- handle for free: the lanes go back to rest at full alpha, the trail
        -- and the ghost go, and nothing was ever written.
        SectionDrag.HideHandle(preview)
        ResetGridDragPreview(preview, layoutDrag)
        -- The gesture is over however it ended -- drop, Escape, release into
        -- nothing -- so the record goes and the attached bar lanes come back
        -- here and only here.
        SectionDrag.EndGesture(preview)
        ClearPreviewGhost(preview)
        -- Keep ticking so the return-to-rest tween plays out
        StartPreviewTicker(preview)
    end

    -- The one writer. Membership moves first and never touches the master
    -- list's order, so every index below is still the index the drop resolved
    -- against; PerformButtonReorder then reads them as "put the entry where
    -- this index sits today", which is the same insertion-anchor grammar the
    -- base grid has always used.
    layoutDrag.applyDrop = function(state)
        local dropTarget = state and state.dropTarget
        if state and state.sectionHandle then
            -- Its own writer: a section move is per-member membership plus the
            -- section's settings, and never a reorder.
            SectionDrag.ApplyHandleDrop(panelId, layoutDrag, state.sectionHandle,
                dropTarget and dropTarget.create)
            return
        end
        local sourceIndex = state and state.slotData and state.slotData.index
        if not (PerformButtonReorder and sourceIndex and dropTarget) then return end
        local group = panelId and CooldownCompanion.db.profile.groups[panelId]
        local buttonData = state.slotData.buttonData
        local model = layoutDrag.sectionDrag
        local sourceCell = LayoutDragIndexCell(layoutDrag, sourceIndex)
        local changed, insertIndex = false, nil

        if model and dropTarget.create then
            -- A create target only ever names an anchor no section holds, so the
            -- drop is always a real move; a fresh section's order is the
            -- entry alone.
            changed = ST.SetPanelSectionForEntry(group, buttonData, dropTarget.create)
        elseif model and dropTarget.section then
            local lane = model.lanes[dropTarget.section]
            if not lane then return end
            local position = dropTarget.memberPos or 1
            local sourcePos = SectionDrag.MemberPosition(lane, sourceIndex)
            -- Same no-move test the base grid runs, in the lane's own numbering.
            if sourcePos and (position == sourcePos or position == sourcePos + 1) then
                return
            end
            -- Landing before the member that holds the target position, or just
            -- after the last one for a drop off the end of the line.
            insertIndex = lane.members[position]
                or (lane.members[#lane.members] + 1)
            changed = ST.SetPanelSectionForEntry(group, buttonData, dropTarget.section)
        else
            local insertCell = dropTarget.insertIndex
            if not insertCell then return end
            -- The drop resolved in cell space, so the no-move test belongs there
            -- too; only then are both ends translated to master-list indices.
            if sourceCell then
                if insertCell == sourceCell or insertCell == sourceCell + 1 then return end
            elseif not model then
                return
            end
            insertIndex = insertCell
            local cellIndex = layoutDrag.cellIndex
            if cellIndex then
                -- Landing before the entry that holds the target cell keeps the base
                -- order right whatever section members sit between them; a drop past
                -- the last cell lands just after the last base member.
                insertIndex = cellIndex[insertCell]
                    or ((cellIndex[layoutDrag.count] or 0) + 1)
            end
            if model then
                -- Leaving a section is the same rejoin the base grid always did,
                -- with the membership dropped first.
                changed = ST.SetPanelSectionForEntry(group, buttonData, nil)
            end
        end

        if insertIndex and insertIndex ~= sourceIndex then
            PerformButtonReorder(panelId, sourceIndex, insertIndex)
            changed = true
        end
        if not changed then return end
        CooldownCompanion:RefreshGroupFrame(panelId)
        CooldownCompanion:RefreshConfigPanel()
    end

    return layoutDrag
end

-- Shift-hover routes through the shared config Shift-tooltip controller
-- (State.lua), same as the shared entry rows: the real spell/item
-- tooltip with the resolved override spell ID, shown and hidden live as
-- the modifier changes. The controller speaks the AceGUI widget shape
-- (frame + user data), so each raw slot carries a small adapter.
local function EnsureSlotShiftTooltipAdapter(slot)
    local adapter = slot._cdcShiftTooltipAdapter
    if not adapter then
        adapter = { frame = slot, userdata = {} }
        function adapter:SetUserData(key, value)
            self.userdata[key] = value
        end
        function adapter:GetUserData(key)
            return self.userdata[key]
        end
        slot._cdcShiftTooltipAdapter = adapter
    end
    return adapter
end

local function ResolveSlotShiftTooltip(buttonData)
    if buttonData.type == "spell" and buttonData.id then
        local resolve = ST._ResolveEntryTooltipSpellId
        return "spell", resolve and resolve(buttonData) or buttonData.id
    end
    if buttonData.type == "item" and buttonData.id then
        return "item", buttonData.id
    end
    if CooldownCompanion.IsEquipmentSlotEntry
        and CooldownCompanion.IsEquipmentSlotEntry(buttonData) then
        local effectiveItem = CooldownCompanion.ResolveEffectiveItem
            and CooldownCompanion.ResolveEffectiveItem(buttonData, true) or nil
        if effectiveItem and effectiveItem.trackable and effectiveItem.itemID then
            return "item", effectiveItem.itemID
        end
    end
    return nil
end

-- Plain hover: the entry name with its kind spelled out, plus the same
-- status signals the shared row badges carry (Shift is the controller's
-- job above). Overrides and talent conditions list their actual contents
-- here so nobody has to open the entry's tabs just to see what is set.
local function ShowEntrySlotTooltip(slot, panelId, buttonData, status, visibility)
    GameTooltip:SetOwner(slot, "ANCHOR_RIGHT")
    local name = GetConfigEntryDisplayName(buttonData, { includeDecorations = true })
    GameTooltip:SetText(name or "Entry", 1, 1, 1)
    if status.disabled then
        GameTooltip:AddLine(
            ("|A:%s:14:14|a Disabled"):format(ENTRY_STATUS_BADGE_ATLAS.disabled),
            0.6, 0.6, 0.6)
    end
    if status.warn then
        GameTooltip:AddLine(
            ("|A:%s:14:14|a %s"):format(ENTRY_STATUS_BADGE_ATLAS.warn,
                status.loadBlocked and "Hidden by visibility rules" or "Spell/item unavailable"),
            1, 0.3, 0.3)
    end
    if status.override then
        local group = panelId and CooldownCompanion.db
            and CooldownCompanion.db.profile.groups[panelId] or nil
        local displayMode = group and (group.displayMode or "icons") or "icons"
        -- Same order and activity gates the styling tabs use for these
        -- sections: ST.OVERRIDE_SECTION_ORDER, then the per-entry gate.
        local canUse = ST._CanButtonUseConfigOverrideSection
        local sections = buttonData.overrideSections or {}
        local lines = {}
        if buttonData.textFormat ~= nil then
            lines[#lines + 1] = { label = "Text Format", active = displayMode == "text" }
        end
        for _, sectionId in ipairs(ST.OVERRIDE_SECTION_ORDER or {}) do
            if sections[sectionId] then
                local sectionDef = ST.OVERRIDE_SECTIONS[sectionId]
                if sectionDef then
                    lines[#lines + 1] = {
                        label = sectionDef.label,
                        active = sectionDef.modes[displayMode] == true
                            and (not canUse or (canUse(buttonData, sectionId, group))),
                    }
                end
            end
        end
        GameTooltip:AddLine(" ")
        if #lines > 0 then
            GameTooltip:AddLine(
                ("|A:%s:14:14|a Customized:"):format(ENTRY_STATUS_BADGE_ATLAS.override),
                1, 1, 1)
            for _, line in ipairs(lines) do
                if line.active then
                    GameTooltip:AddLine("    " .. line.label, 0.7, 0.7, 0.7)
                else
                    GameTooltip:AddLine("    " .. line.label .. " (inactive)", 0.45, 0.45, 0.45)
                end
            end
        else
            GameTooltip:AddLine(
                ("|A:%s:14:14|a Has customized sections"):format(ENTRY_STATUS_BADGE_ATLAS.override),
                1, 1, 1)
        end
    end
    if status.talent then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(
            ("|A:%s:14:14|a Talent conditions:"):format(ENTRY_STATUS_BADGE_ATLAS.talent),
            1, 1, 1)
        local getName = ST._GetConditionDisplayName
        for _, cond in ipairs(buttonData.talentConditions or {}) do
            local nameText = getName and getName(cond) or (cond.name or "Unknown Talent")
            local suffix = (cond.show == "not_taken")
                and " |cffff4d4d(not taken)|r" or " |cff33dd33(taken)|r"
            GameTooltip:AddLine("    " .. nameText .. suffix, 0.7, 0.7, 0.7)
        end
    end
    if status.fallback or status.sound then
        GameTooltip:AddLine(" ")
        if status.fallback then
            GameTooltip:AddLine(
                ("|A:%s:14:14|a Uses item fallbacks"):format(ENTRY_STATUS_BADGE_ATLAS.fallback),
                1, 1, 1)
        end
        if status.sound then
            GameTooltip:AddLine(
                ("|A:%s:14:14|a Sound alerts enabled"):format(ENTRY_STATUS_BADGE_ATLAS.sound),
                1, 1, 1)
        end
    end
    if status.auraHideReservesSpace then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(
            ("|A:%s:14:14|a Hidden aura still reserves layout space")
                :format(PANEL_PREVIEW_AURA_SPACE_BADGE_ATLAS),
            1, 0.82, 0.2)
        GameTooltip:AddLine(
            "Blizzard does not expose the active aura state to addon layout code, so this reserved space cannot safely collapse.",
            0.7, 0.7, 0.7, true)
    end
    if visibility and not visibility.exactPreview
        and visibility.underlyingMode == "hidden" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(
            ("|A:%s:14:14|a Hidden in simulated state")
                :format(PANEL_PREVIEW_VISIBILITY_BADGE_ATLAS),
            1, 0.82, 0.2)
        for _, reason in ipairs(visibility.reasons or {}) do
            GameTooltip:AddLine("    " .. reason.label .. " - " .. reason.rule, 0.7, 0.7, 0.7)
        end
    end
    if CooldownCompanion:HasLocalLoadConditions(buttonData) then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("This entry adds visibility rules.", 0.7, 0.7, 0.7)
    end
    GameTooltip:AddLine(" ")
    local copyState = CS.copyCustomization
    if copyState then
        -- While armed the click grammar changes entirely, so the hint
        -- lines change with it.
        local targetGroup = panelId and CooldownCompanion.db.profile.groups[panelId]
        local label = CopyMode.GetLabel(copyState)
        if CopyMode.IsEligibleTarget(copyState, targetGroup, buttonData) then
            GameTooltip:AddLine("Click to apply " .. label .. " to this entry.",
                CopyMode.COLOR[1], CopyMode.COLOR[2], CopyMode.COLOR[3])
        else
            GameTooltip:AddLine("This entry can't receive " .. label .. ".", 0.6, 0.6, 0.6)
        end
        GameTooltip:AddLine("Right-click to cancel.", 0.75, 0.82, 0.92)
    else
        if slot._cdcDraggable then
            GameTooltip:AddLine("Drag to reorder.", 0.75, 0.82, 0.92)
            if slot._cdcSectionDraggable then
                GameTooltip:AddLine("Drag past the row to place it in a section.",
                    0.75, 0.82, 0.92)
            end
        end
        -- WireEntryInteraction opens the entry context menu on every display
        -- mode, and that menu holds destructive actions, so every mode
        -- advertises it.
        GameTooltip:AddLine("Right-click for options.", 0.75, 0.82, 0.92)
        if slot._cdcReorderPausedByFilter then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Reordering is paused while entries are hidden.",
                0.7, 0.7, 0.7, true)
        end
    end
    GameTooltip:Show()
end

local function WireEntryInteraction(slot, panelId, index, buttonData, status, layoutDrag, visibility)
    slot:EnableMouse(true)
    slot._cdcDraggable = layoutDrag ~= nil
    -- Written here rather than at the call sites: icon slots are pooled across
    -- every preview shape, and a slot recycled onto a panel with no anchors
    -- must not keep advertising them.
    slot._cdcSectionDraggable = (layoutDrag and layoutDrag.sectionDrag) and true or nil
    slot._cdcEntryIndex = index
    slot._cdcEntryStatus = status
    slot:SetScript("OnMouseDown", function(self, mouseButton)
        if mouseButton ~= "LeftButton" or GetCursorInfo() then return end
        -- Armed copy mode: the press belongs to the copy click, not a drag.
        if CS.copyCustomization then return end
        if not (layoutDrag and StartDragTracking) then return end
        local cursorX, cursorY = GetCursorPosition()
        -- No `widget` field: the tracker's dim/restore would fight the
        -- alpha choreography our layoutDrag callbacks run (dragged slot
        -- goes fully invisible; disabled slots rest at reduced alpha).
        CS.dragState = {
            kind = "layout-slot",
            phase = "pending",
            previewSlot = self,
            scrollWidget = UIParent,
            startX = cursorX,
            startY = cursorY,
            layoutDrag = layoutDrag,
            slotData = { index = index, buttonData = buttonData },
        }
        StartDragTracking()
    end)
    slot:SetScript("OnMouseUp", function(self, mouseButton)
        if GetCursorInfo() then return end
        if mouseButton == "LeftButton" then
            -- Escape already cancelled this drag; the release the user is still
            -- holding belongs to that cancel, never to a selection click.
            if ST._ConsumeDragEscapeMouseUp() then return end
            local state = CS.dragState
            if state then
                -- Only fall through to selection for our own still-pending
                -- press; active drags finish through the tracker.
                if state.kind ~= "layout-slot" or state.phase ~= "pending" or state.previewSlot ~= self then
                    return
                end
                if CancelDrag then CancelDrag() else CS.dragState = nil end
            end
            if CopyMode.HandleClick(panelId, index, buttonData) then return end
            SelectConfigButton(panelId, index, { multi = IsControlKeyDown() })
            CooldownCompanion:RefreshConfigSelection()
        elseif mouseButton == "RightButton" or mouseButton == "MiddleButton" then
            if CS.dragState and CS.dragState.phase == "active" then return end
            -- Armed copy mode: right/middle-click is a cancel, never a menu.
            if CS.copyCustomization then
                CopyMode.Cancel()
                return
            end
            if ShowEntryContextMenu then
                ShowEntryContextMenu(panelId, index, buttonData)
            end
        end
    end)
    slot:SetScript("OnEnter", function(self)
        if CS.dragState and CS.dragState.phase == "active" then return end
        -- Hovering a section's own icons OFFERS the grab chip. Taking it back
        -- is not this handler's job and never was: the chip watches the cursor
        -- against its own section for as long as it is up (HandleWatch), which
        -- is the only model that survives the cursor crossing the empty pixels
        -- between an icon and the chip.
        if layoutDrag and layoutDrag.preview and self._cdcSectionAnchor
            and layoutDrag.sectionDrag then
            SectionDrag.ShowHandle(layoutDrag.preview, layoutDrag,
                self._cdcSectionAnchor)
        end
        if self._cdcBarPreviewVisibility then
            self._cdcBarPreviewHovered = true
            RefreshBarSlotWorkspacePresentation(self)
        else
            self.hoverHighlight:SetFrameLevel(self:GetFrameLevel() + PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET)
            self.hoverHighlight:Show()
        end
        -- Register with the shared Shift-tooltip controller; when Shift is
        -- already held this shows the real tooltip immediately and the
        -- decorated one is skipped. Later modifier changes are the
        -- controller's MODIFIER_STATE_CHANGED handler's job.
        local kind, id = ResolveSlotShiftTooltip(buttonData)
        local activate = ST._ActivateConfigShiftTooltip
        if kind and id and activate then
            local adapter = EnsureSlotShiftTooltipAdapter(self)
            adapter:SetUserData("cdcShiftTooltipKind", kind)
            adapter:SetUserData("cdcShiftTooltipID", id)
            adapter:SetUserData("cdcShiftTooltipOwner", self)
            adapter:SetUserData("cdcShiftTooltipAnchor", "ANCHOR_RIGHT")
            if activate(adapter) then
                return
            end
        end
        ShowEntrySlotTooltip(self, panelId, buttonData, status, visibility)
    end)
    slot:SetScript("OnLeave", function(self)
        if self._cdcBarPreviewVisibility then
            self._cdcBarPreviewHovered = false
            RefreshBarSlotWorkspacePresentation(self)
        else
            self.hoverHighlight:Hide()
        end
        if self._cdcShiftTooltipAdapter and ST._ClearConfigShiftTooltipHover then
            ST._ClearConfigShiftTooltipHover(self._cdcShiftTooltipAdapter)
        end
        GameTooltip:Hide()
    end)
end

------------------------------------------------------------------------
-- Drop ghost. ONE cell, drawn where the next entry will land, in the panel's
-- own style, carrying the prospective entry's icon: the preview's answer to
-- "what happens if I let go here" (a spell or item riding the cursor over the
-- drop overlay in ButtonsWideColumn) and "what happens if I pick this" (a
-- row of the add box's suggestion list in SpellItemAdd). Two drivers, one
-- renderer; both hand it a stub entry table, and the cursor driver adds the
-- target the preview resolved for the release.
--
-- Never static: nothing is drawn unless a payload or a suggestion is live,
-- and every hand that ends either gesture (the drop, the dropdown closing,
-- the cursor leaving the overlay, a rebuild) puts it away. The cell is the
-- preview's own slot kind, built by the same factory and styled by the same
-- styler as a real entry, but it lives outside the pools so a build never
-- counts it, releases it, or wires it for interaction.
--
-- Drop-ghost helpers stay private to this block. The one
-- survivor publishes through the DropGhost table.
------------------------------------------------------------------------
local DropGhost = {}
do

-- The cell reads as "not yet": the panel's own look, dimmed. No ring and no
-- fill of its own: the landing trail and the lane ring stay the gesture's
-- chrome.
local GHOST_ALPHA = 0.6
-- Above the real slots and below the section outline.
local GHOST_LEVEL_OFFSET = PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET + 3
-- What ApplyBarSlotConditionalPreview reads for an entry with no stored
-- preview state: the bar at rest.
local GHOST_BAR_STATE = { effectFlags = {} }

--- The mirror the Live Preview host is showing. With attached bars up it
--- is the unified composition's inner mirror (UnifiedAnchorPreview builds it
--- in _cdcUnifiedMirrorHost and releases the host's own); otherwise the
--- host's own. The drop overlay only ever knows the outer host.
function DropGhost.Mirror(host)
    local inner = host and host._cdcUnifiedMirrorHost
    local preview = inner and inner:IsShown() and inner._cdcPanelPreview or nil
    if preview and preview.root:IsVisible() then
        return preview
    end
    return host and host._cdcPanelPreview
end

--- The preview behind `host`, its slot kind and its panel, or nothing when
--- this host takes no ghost: a released or hidden mirror, a build that was
--- not an icon, bar or text mirror open to a drop (ST._BuildButtonPanelPreview
--- records the kind as dropGhostMode on exactly those builds), or a mirror
--- of some panel other than the one an add would land in.
function DropGhost.Preview(host)
    local preview = DropGhost.Mirror(host)
    local mode = preview and preview.dropGhostMode
    if not mode or preview.panelId ~= CS.selectedGroup or not preview.root:IsVisible() then
        return nil
    end
    local group = CooldownCompanion.db.profile.groups[preview.panelId]
    if not group then return nil end
    return preview, mode, group
end

function DropGhost.EnsureCell(preview, mode)
    local cells = preview.dropGhostCells
    if not cells then
        cells = {}
        preview.dropGhostCells = cells
    end
    local cell = cells[mode]
    if not cell then
        cell = SLOT_FACTORIES[mode](preview.content)
        cell:Hide()
        cells[mode] = cell
    end
    return cell
end

--- The stub a driver hands over is copied into ONE table per preview: the
--- text metrics cache keys on the entry table, so a fresh table per show
--- would grow it without bound.
function DropGhost.FillStub(preview, spec)
    local stub = preview.dropGhostStub
    if not stub then
        stub = {}
        preview.dropGhostStub = stub
    end
    wipe(stub)
    for key, value in pairs(spec) do
        stub[key] = value
    end
    return stub
end

-- Same order as the populated path for each kind, then everything a real
-- entry gets from its interaction wiring or its stored preview state is
-- stripped, and the cell is dimmed. Bars own their alpha through
-- ApplyBarSlotVisualAlpha (their root stays opaque by that helper's rule),
-- and DisableReadOnlySlotInteraction resets it, so the dim comes last.
function DropGhost.StyleCell(cell, stub, group, mode, panelId)
    if mode == "barSlots" then
        local effectiveStyle = group.style or {}
        if CooldownCompanion.GetEffectiveStyle then
            effectiveStyle = CooldownCompanion:GetEffectiveStyle(effectiveStyle, stub)
                or effectiveStyle
        end
        ResetBarSlotConditionalVisuals(cell)
        StyleBarEntry(cell, stub, group, effectiveStyle)
        ClearSlotEffectPreviews(cell)
        ApplyBarSlotConditionalPreview(cell, stub, group, panelId, nil,
            effectiveStyle, GHOST_BAR_STATE)
        cell._cdcCondAnim = nil
        DisableReadOnlySlotInteraction(cell)
        ApplyBarSlotVisualAlpha(cell, GHOST_ALPHA)
        return
    end
    if mode == "textSlots" then
        StyleTextEntry(cell, stub, group)
        -- forceBase: the panel's own format at rest, which is what the entry
        -- shows the moment it exists.
        ApplyTextSlotConditionalPreview(cell, stub, group, panelId, nil, true)
        cell._cdcCondAnim = nil
    else
        StyleIconEntry(cell, stub, group)
        ClearSlotEffectPreviews(cell)
        ResetSlotConditionalVisuals(cell)
        cell.icon:SetDesaturated(false)
        -- Base tint only, as the read-only mirror writes it: no conditional
        -- pass runs on a ghost.
        local style = group.style or {}
        if CooldownCompanion.GetEffectiveStyle then
            style = CooldownCompanion:GetEffectiveStyle(style, stub) or style
        end
        local tint = style.iconTintColor
        cell.icon:SetVertexColor(tint and tint[1] or 1, tint and tint[2] or 1,
            tint and tint[3] or 1, tint and tint[4] or 1)
    end
    DisableReadOnlySlotInteraction(cell)
    cell:SetAlpha(GHOST_ALPHA)
end

--- Where the cell goes on a POPULATED mirror: anchor, x, y, width, height in
--- the content frame's terms. `target` is the overlay's resolved release
--- ({ create = anchor }, { section = anchor }, or nil for a plain add).
function DropGhost.ResolveRect(preview, group, mode, stub, target)
    local layoutDrag = preview.layoutDrag
    local model = preview.cursorPadModel
    if target and model then
        local cell = target.create and model.free[target.create]
        if cell then
            -- The engine's own cell for that anchor's first member.
            return "TOPLEFT", cell.x, cell.y, cell.width, cell.height
        end
        local lane = target.section and model.lanes[target.section]
        if lane then
            -- The add APPENDS to the section (AddButtonToGroup's section
            -- argument), and the engine already said where that lands
            -- (SectionDrag.Build's phantom, wrap and centering included).
            local cell = lane.appendCell
            if cell then
                return "TOPLEFT", cell.x, cell.y, cell.width, cell.height
            end
            -- No engine answer (a lane the pass laid nothing out for): the
            -- step past the last member, the one place this approximates.
            local last = lane.positions and lane.positions[#lane.members]
            local x = (last and last.x or lane.originX) + (lane.stepX or 0)
            local y = (last and last.y or lane.originY) + (lane.stepY or 0)
            return "TOPLEFT", x, y, lane.width, lane.height
        end
    end
    local w, h = layoutDrag.slotW, layoutDrag.slotH
    if mode == "textSlots" then
        w, h = GetTextSlotSize(group, stub, w, h)
    end
    local count = layoutDrag.count or 0
    local perRow = layoutDrag.perRow or 1
    local x, y
    if layoutDrag.auraColumn then
        -- An Aura Bar Panel's wrap count IS its entry count (one column,
        -- GetPanelGeometry), so the grid formula would open a second column;
        -- the next cell is one pitch further down the same one.
        x, y = layoutDrag.cellXY(count)
        x, y = x + layoutDrag.cellStepX, y + layoutDrag.cellStepY
    else
        x, y = layoutDrag.cellXY(count + 1)
        if layoutDrag.centered and count % perRow == 0 then
            -- cellXY spreads a NEW line as if it were full; a line holding
            -- only the ghost centers on the edge, so the along-axis offset
            -- moves back by half a full line. (A partial line is exact: the
            -- ghost sits one pitch past the last cell, and the real add
            -- re-centers that line by half a pitch.)
            local k = (perRow - 1) / 2
            x, y = x + k * layoutDrag.cellStepX, y + k * layoutDrag.cellStepY
        end
    end
    return layoutDrag.anchor, x, y, w, h
end

--- An EMPTY panel shows a message and no content frame. The ghost stands in
--- for the first entry exactly where the populated build will draw it (one
--- cell, fit-scaled, centered on the root), and the message steps aside
--- until the ghost goes, so the box has one subject at a time.
function DropGhost.PlaceEmpty(preview, host, group, mode, cell, stub)
    local isBarMode, isTextMode = mode == "barSlots", mode == "textSlots"
    local style = group.style or {}
    local geo = GetPanelGeometry(group, isBarMode, isTextMode, nil)
    local w, h = geo.entryWidth, geo.entryHeight
    if isTextMode then
        w, h = GetTextSlotSize(group, stub, w, h)
    end
    local headerHeight = 0
    if isTextMode and style.showTextGroupHeader == true then
        headerHeight = (style.textHeaderFontSize or style.textFontSize or 12) + 4
    end
    local contentWidth, contentHeight = w, h + headerHeight
    -- Cell 1 of the populated path's grid, for the one line it needs.
    local _, yMul, growthAnchor = GetGrowthMultipliers(style.growthOrigin)
    local centeredEdge = not CooldownCompanion:IsAuraPanel(group)
        and ST.GetCenteredGrowthEdge(style.growthOrigin, geo.orientation) or nil
    local x, y = 0, yMul * headerHeight
    if centeredEdge then
        growthAnchor = centeredEdge
        if geo.orientation == "horizontal" then
            y = (centeredEdge == "TOP" and -1 or 1) * headerHeight
        else
            y = -headerHeight / 2
        end
    end

    local content = preview.content
    content:SetSize(contentWidth, contentHeight)
    content:SetScale(GetHostFitScale(host, contentWidth, contentHeight, false))
    content:ClearAllPoints()
    content:SetPoint("CENTER", preview.root, "CENTER", 0, 0)
    content:Show()
    UpdateTextGroupHeader(preview, group, style, headerHeight)
    if not preview.dropGhostHidMessage then
        local title, label, note = preview.messageTitle, preview.messageLabel, preview.messageNote
        preview.dropGhostHidMessage = {
            title = title and title:IsShown() or false,
            label = label and label:IsShown() or false,
            note = note and note:IsShown() or false,
        }
        HidePreviewMessage(preview)
    end
    cell:SetSize(w, h)
    ApplyPreviewSlotGeometry(preview, cell, growthAnchor, x, y)
end

--- The empty panel's message comes back exactly as the build left it, and
--- the content frame the ghost borrowed goes back to hidden.
function DropGhost.RestoreEmptyMessage(preview)
    local hid = preview.dropGhostHidMessage
    if not hid then return end
    preview.dropGhostHidMessage = nil
    preview.content:Hide()
    if preview.textHeader then preview.textHeader:Hide() end
    if hid.title and preview.messageTitle then preview.messageTitle:Show() end
    if hid.label and preview.messageLabel then preview.messageLabel:Show() end
    if hid.note and preview.messageNote then preview.messageNote:Show() end
end

--- Put the ghost away without touching the message or the content frame:
--- the rebuild prologue and the release own those, and both call here.
--- Every other hider goes through DropGhost.Hide.
function DropGhost.Reset(preview)
    preview.dropGhostKey = nil
    preview.dropGhostOwner = nil
    preview.dropGhostHidMessage = nil
    SectionDrag.HideLandingTrail(preview)
    local cells = preview.dropGhostCells
    if cells then
        for _, cell in pairs(cells) do
            cell:Hide()
        end
    end
end

--- `owner` names the driver ("cursor" or "autocomplete"): a driver only ever
--- hides what it showed, so the overlay's every-frame answer cannot take
--- down a suggestion's ghost, or the reverse.
function DropGhost.Hide(host, owner)
    local preview = DropGhost.Mirror(host)
    if not (preview and preview.dropGhostKey) then return end
    if owner and preview.dropGhostOwner ~= owner then return end
    DropGhost.RestoreEmptyMessage(preview)
    DropGhost.Reset(preview)
end

--- `spec` is the prospective entry as a stub ({ type, id, name, isPetSpell,
--- manualIcon }); `target` is the overlay's resolved release, nil for a plain
--- add (all the autocomplete driver ever asks for). Returns true while a
--- ghost is up. Idempotent per (kind, entry, target): the cursor driver
--- asks every frame, and a still answer costs a string compare.
function DropGhost.Show(host, spec, target, owner)
    local preview, mode, group = DropGhost.Preview(host)
    if not preview then return false end
    local targetKey = target and (target.create and ("create:" .. tostring(target.create))
        or target.section and ("lane:" .. tostring(target.section))) or "base"
    -- The name is in the key for the rows that are nothing but a name: two
    -- empty equipment slots share one placeholder icon and no id.
    local key = mode .. "|" .. tostring(spec.type) .. "|" .. tostring(spec.id)
        .. "|" .. tostring(spec.manualIcon) .. "|" .. tostring(spec.name) .. "|" .. targetKey
    if preview.dropGhostKey == key then
        preview.dropGhostOwner = owner
        return true
    end
    local cell = DropGhost.EnsureCell(preview, mode)
    local stub = DropGhost.FillStub(preview, spec)
    if preview.layoutDrag then
        local anchor, x, y, w, h = DropGhost.ResolveRect(preview, group, mode, stub, target)
        -- Sized before the styler: the mirrored icon crops its texture from
        -- the cell's current size.
        cell:SetSize(w, h)
        ApplyPreviewSlotGeometry(preview, cell, anchor, x, y)
        local free = target and target.create and preview.cursorPadModel
            and preview.cursorPadModel.free[target.create] or nil
        if free then
            SectionDrag.ShowLandingTrail(preview, free, target.create, preview.layoutDrag.scale)
        else
            SectionDrag.HideLandingTrail(preview)
        end
    else
        -- The mirror's OWN host (the unified inner frame, or `host` itself):
        -- the fit is measured against the box the mirror was built in.
        DropGhost.PlaceEmpty(preview, preview.root:GetParent(), group, mode, cell, stub)
    end
    DropGhost.StyleCell(cell, stub, group, mode, preview.panelId)
    cell:SetFrameLevel(preview.content:GetFrameLevel() + GHOST_LEVEL_OFFSET)
    cell:Show()
    preview.dropGhostKey = key
    preview.dropGhostOwner = owner
    return true
end

end

-- Private helpers consumed by later ButtonPanelPreview files.
PP.CreatePreviewLayoutDrag = CreatePreviewLayoutDrag
PP.WireEntryInteraction = WireEntryInteraction
PP.DropGhost = DropGhost
