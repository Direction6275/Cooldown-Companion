--[[
    CooldownCompanion - Config/DragReorderTargets
    Drop-target resolution, indicator helpers, and reorder primitives.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState
local DR = ST._DragReorder or {}
ST._DragReorder = DR

local COL1_HIT_X_PAD = 6
local FindCol1SectionDividerTarget
local activeCol1DropSourceSection

local function IsCol1OwnershipMoveAllowed(sourceSection, targetSection)
    if not targetSection or sourceSection == targetSection then
        return true
    end
    if targetSection == "global" and sourceSection ~= "global" then
        return true
    end
    return sourceSection == "global" and targetSection == "char"
end

------------------------------------------------------------------------
-- Drag indicator helpers
------------------------------------------------------------------------
-- The drag chrome is deliberately one thing: this line. The dragged group's own
-- AceGUI shell dimming carries "what am I holding", so nothing follows the
-- cursor and nothing else moves during a Navigator drag.
local DRAG_INDICATOR_HEIGHT = 2
-- Soft ends, so the line reads as a seam opening in the list rather than a bar
-- laid across it, and echoes the fading rule the section headings use.
local DRAG_INDICATOR_FADE_WIDTH = 28
-- Below this the two end gradients would overlap and the solid core between them
-- would be anchored inside out.
local DRAG_INDICATOR_MIN_WIDTH = DRAG_INDICATOR_FADE_WIDTH * 2
local DRAG_INDICATOR_FADE_TIME = 0.12
local DRAG_INDICATOR_DEFAULT_COLOR = { 0.2, 0.6, 1.0 }
-- Retargeting dips the line instead of restarting it from nothing, so moving
-- between drop targets reads as a pulse rather than a flicker.
local DRAG_INDICATOR_MOVE_ALPHA = 0.4

-- White source texture + SetGradient, the same way the row-grammar section rule
-- is built: the gradient supplies both the colour and the alpha ramp.
--
-- API verified against blizzard-ui-ptr, lane ptr, Interface 120100, build
-- 12.1.0 (68914), source commit d3915c78:
--   Texture:SetGradient(orientation, minColor, maxColor) with ColorMixin args --
--     Blizzard_NamePlates/Blizzard_NamePlates.lua:642 uses exactly this shape.
--     (Pre-10.0 it took r,g,b tables; that form is gone.)
--   CreateColor(r, g, b, a) -- Blizzard_SharedXMLBase/Color.lua:3.
--   Texture:SetColorTexture(r, g, b, a) -- widely used, e.g.
--     Blizzard_ColorPickerFrame/Mainline/ColorPickerFrame.lua:5.
--
-- Reapplying this is not free (two SetGradient calls plus four CreateColor
-- allocations), and every caller sits in a per-frame drag path, so it early-outs
-- unless the colour actually changed.
local function ApplyDragIndicatorColor(ind, r, g, b)
    if ind._cdcColorR == r and ind._cdcColorG == g and ind._cdcColorB == b then
        return
    end
    ind._cdcColorR, ind._cdcColorG, ind._cdcColorB = r, g, b

    ind.core:SetColorTexture(r, g, b, 1)
    ind.fadeLeft:SetTexture("Interface/Buttons/WHITE8x8")
    ind.fadeLeft:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, 1))
    ind.fadeRight:SetTexture("Interface/Buttons/WHITE8x8")
    ind.fadeRight:SetGradient("HORIZONTAL", CreateColor(r, g, b, 1), CreateColor(r, g, b, 0))
end

local function GetDragIndicator()
    if not CS.dragIndicator then
        local ind = CreateFrame("Frame", nil, UIParent)
        ind:SetFrameStrata("TOOLTIP")
        ind:SetSize(10, DRAG_INDICATOR_HEIGHT)
        ind:Hide()

        ind.fadeLeft = ind:CreateTexture(nil, "OVERLAY")
        ind.fadeLeft:SetPoint("TOPLEFT")
        ind.fadeLeft:SetPoint("BOTTOMLEFT")
        ind.fadeLeft:SetWidth(DRAG_INDICATOR_FADE_WIDTH)

        ind.fadeRight = ind:CreateTexture(nil, "OVERLAY")
        ind.fadeRight:SetPoint("TOPRIGHT")
        ind.fadeRight:SetPoint("BOTTOMRIGHT")
        ind.fadeRight:SetWidth(DRAG_INDICATOR_FADE_WIDTH)

        ind.core = ind:CreateTexture(nil, "OVERLAY")
        ind.core:SetPoint("TOPLEFT", ind.fadeLeft, "TOPRIGHT")
        ind.core:SetPoint("BOTTOMRIGHT", ind.fadeRight, "BOTTOMLEFT")

        ind.currentAlpha = 0
        ind.targetAlpha = 0
        CS.dragIndicator = ind
        ApplyDragIndicatorColor(ind, unpack(DRAG_INDICATOR_DEFAULT_COLOR))
    end
    return CS.dragIndicator
end

-- One alpha on one frame. This is the only thing that animates in a Navigator
-- drag, which is precisely why it cannot drift out of agreement with the drop
-- target the way the old proxy preview could.
--
-- Defined once at file scope rather than per call: its installers run on every
-- drag-tracker tick, and building a closure there would allocate every frame.
local function TickDragIndicatorFade(self, elapsed)
    local target = self.targetAlpha or 0
    local current = self.currentAlpha or 0
    local step = elapsed / DRAG_INDICATOR_FADE_TIME

    if current < target then
        current = math.min(target, current + step)
    elseif current > target then
        current = math.max(target, current - step)
    end

    self.currentAlpha = current
    self:SetAlpha(current)

    if current == target then
        self:SetScript("OnUpdate", nil)
        if target <= 0 then
            self:Hide()
            -- Drop the anchor as well: it is an AceGUI row frame that can be
            -- recycled out from under us on the next Column 1 rebuild.
            self:ClearAllPoints()
            self._cdcAnchor = nil
        end
    end
end

-- Only installs the ticker when there is actually distance to cover, so the
-- steady state of a held drag is no script at all rather than one that installs
-- and immediately uninstalls itself every frame.
local function StartDragIndicatorFade(ind)
    if (ind.currentAlpha or 0) ~= (ind.targetAlpha or 0) then
        ind:SetScript("OnUpdate", TickDragIndicatorFade)
        return
    end

    -- Already at the target: apply the settled state here rather than installing
    -- a ticker only to have its first frame do it. Skipping this would strand a
    -- hide request that arrives on the same frame as the show -- the frame would
    -- stay shown at alpha 0, still anchored to a row that can be released.
    ind:SetScript("OnUpdate", nil)
    if (ind.targetAlpha or 0) <= 0 then
        ind:Hide()
        ind:ClearAllPoints()
        ind._cdcAnchor = nil
    end
end

-- Detach from the row BEFORE fading, re-pinning to UIParent at the rect the
-- line currently occupies so only alpha animates.
--
-- Callers hide the indicator and then immediately rebuild Column 1 -- the
-- spring-open refresh does, and so does every completed drop via CancelDrag ->
-- RefreshConfigPanel. That rebuild runs ReleaseChildren, and AceGUI's Release
-- does `frame:ClearAllPoints(); frame:Hide(); frame:SetParent(UIParent)` on the
-- very frame the line is anchored to, then hands it back out for a different
-- row. Holding the anchor across the fade therefore leaves the last ~0.12s of
-- every drag painted against an unpositioned or entirely unrelated row.
local function HideDragIndicator()
    local ind = CS.dragIndicator
    if not ind then return end
    ind.targetAlpha = 0

    if not ind:IsShown() then
        ind.currentAlpha = 0
        ind:SetScript("OnUpdate", nil)
        ind:ClearAllPoints()
        ind._cdcAnchor = nil
        return
    end

    if ind._cdcAnchor then
        local left, bottom = ind:GetLeft(), ind:GetBottom()
        ind:ClearAllPoints()
        ind._cdcAnchor = nil
        if left and bottom then
            ind:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
        else
            -- No resolvable rect: the anchor row was already released. There is
            -- nowhere honest to fade from, so drop it now.
            ind.currentAlpha = 0
            ind:SetScript("OnUpdate", nil)
            ind:Hide()
            return
        end
    end

    StartDragIndicatorFade(ind)
end

-- A nil colour means "no opinion" -- keep whatever is applied rather than
-- clearing the textures.
local function SetDragIndicatorColor(r, g, b)
    if not (r and g and b) then
        return
    end
    ApplyDragIndicatorColor(GetDragIndicator(), r, g, b)
end

local function GetDragScaleFrame(scrollWidget)
    if not scrollWidget then
        return UIParent
    end
    return scrollWidget.frame or scrollWidget
end

local function GetScaledCursorCoordinates(scrollWidget)
    local cursorX, cursorY = GetCursorPosition()
    local scaleFrame = GetDragScaleFrame(scrollWidget)
    local scale = (scaleFrame and scaleFrame.GetEffectiveScale and scaleFrame:GetEffectiveScale()) or 1
    return cursorX / scale, cursorY / scale
end

local function GetScaledCursorPosition(scrollWidget)
    return GetScaledCursorCoordinates(scrollWidget)
end

local function GetRawCursorCoordinates()
    return GetCursorPosition()
end

local function GetDropIndex(scrollWidget, cursorY, childOffset, totalDraggable)
    -- childOffset: number of non-draggable children at the start of the scroll (e.g. input box, buttons, separator)
    -- Iterate draggable children and compare cursor Y to midpoints
    local children = { scrollWidget.content:GetChildren() }
    local dropIndex = totalDraggable + 1  -- default: after last
    local anchorFrame = nil
    local anchorAbove = true

    for ci = 1, totalDraggable do
        local child = children[ci + childOffset]
        if child and child:IsShown() then
            local top = child:GetTop()
            local bottom = child:GetBottom()
            if top and bottom then
                local mid = (top + bottom) / 2
                if cursorY > mid then
                    dropIndex = ci
                    anchorFrame = child
                    anchorAbove = true
                    break
                end
                -- Track the last child we passed as potential "below" anchor
                anchorFrame = child
                anchorAbove = false
                dropIndex = ci + 1
            end
        end
    end

    return dropIndex, anchorFrame, anchorAbove
end

local function ShowDragIndicator(anchorFrame, anchorAbove, parentScrollWidget)
    if not anchorFrame then
        HideDragIndicator()
        return
    end
    local ind = GetDragIndicator()
    local width
    if parentScrollWidget and parentScrollWidget.content then
        width = parentScrollWidget.content:GetWidth()
    else
        local scaleFrame = GetDragScaleFrame(parentScrollWidget)
        width = scaleFrame and scaleFrame:GetWidth()
    end
    -- `or` does not guard this: GetWidth() returns 0, not nil, for a frame that
    -- has not been laid out yet, and 0 is truthy in Lua. Below twice the fade
    -- width the two end gradients overlap and the core spans negative width, so
    -- clamp rather than let the line draw itself inside out.
    width = math.max(width or 0, DRAG_INDICATOR_MIN_WIDTH)
    ind:SetWidth(width)

    local moved = ind._cdcAnchor ~= anchorFrame or ind._cdcAbove ~= anchorAbove
    ind._cdcAnchor = anchorFrame
    ind._cdcAbove = anchorAbove

    ind:ClearAllPoints()
    if anchorAbove then
        ind:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, 1)
    else
        ind:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -1)
    end

    if not ind:IsShown() then
        ind.currentAlpha = 0
    elseif moved then
        ind.currentAlpha = math.min(ind.currentAlpha or 1, DRAG_INDICATOR_MOVE_ALPHA)
    end
    ind.targetAlpha = 1
    ind:SetAlpha(ind.currentAlpha or 0)
    ind:Show()
    StartDragIndicatorFade(ind)
end

------------------------------------------------------------------------
-- Navigator drop no-op helpers
------------------------------------------------------------------------

local IsUnloadedTopLevelDrop
local ShouldIncludeCol1TopLevelOrderRow

local function FindCol1GroupSourcePosition(renderedRows, section, sourceContainerId, includeUnloaded)
    local pos = 0
    for _, row in ipairs(renderedRows or {}) do
        if row.section == section and ShouldIncludeCol1TopLevelOrderRow(row, includeUnloaded) then
            pos = pos + 1
            if row.id == sourceContainerId then
                return pos
            end
        end
    end
    return nil
end

local function BuildCol1GroupOrderItems(renderedRows, section, sourceContainerId, includeUnloaded)
    local orderItems = {}
    for _, row in ipairs(renderedRows or {}) do
        if row.section == section and ShouldIncludeCol1TopLevelOrderRow(row, includeUnloaded) then
            if row.id ~= sourceContainerId then
                table.insert(orderItems, { kind = row.kind, id = row.id })
            end
        end
    end
    return orderItems
end

local function ResolveCol1GroupInsertPos(orderItems, dropTarget, includeUnloaded)
    local targetRow = dropTarget and dropTarget.targetRow
    local insertPos = includeUnloaded and 1 or (#orderItems + 1)
    if targetRow and targetRow.kind ~= "unloaded-divider" then
        insertPos = #orderItems + 1
        for idx, item in ipairs(orderItems) do
            if item.kind == targetRow.kind and item.id == targetRow.id then
                insertPos = dropTarget.action == "reorder-after" and idx + 1 or idx
                break
            end
        end
    end
    return insertPos
end

local function IsCol1GroupDropNoOp(state)
    local dropTarget = state and state.dropTarget
    if not dropTarget then
        return true
    end

    local targetRow = dropTarget.targetRow
    local targetSection = (targetRow and targetRow.section) or state.sourceSection
    if targetSection ~= state.sourceSection then
        return false
    end

    if dropTarget.action ~= "reorder-before"
        and dropTarget.action ~= "reorder-after"
    then
        return false
    end

    if targetRow and targetRow.kind == "container" and targetRow.id == state.sourceGroupId then
        return true
    end

    local renderedRows = state.col1RenderedRows
    if not renderedRows then
        return false
    end

    local includeUnloaded = IsUnloadedTopLevelDrop(state, dropTarget)
    local sourcePos = FindCol1GroupSourcePosition(
        renderedRows,
        targetSection,
        state.sourceGroupId,
        includeUnloaded
    )
    if not sourcePos then
        return false
    end

    local orderItems = BuildCol1GroupOrderItems(
        renderedRows,
        targetSection,
        state.sourceGroupId,
        includeUnloaded
    )
    local insertPos = ResolveCol1GroupInsertPos(orderItems, dropTarget, includeUnloaded)
    return insertPos == sourcePos
end


------------------------------------------------------------------------
-- Navigator Group drop targeting
------------------------------------------------------------------------
local function GetCol1DropFrame(rowMeta)
    return rowMeta and rowMeta.widget and rowMeta.widget.frame
end

local function GetCol1HorizontalBounds(scrollWidget, renderedRows)
    local content = scrollWidget and scrollWidget.content
    if content and content.IsShown and content:IsShown() then
        local left, right = content:GetLeft(), content:GetRight()
        if left and right then
            return left, right
        end
    end

    for _, rowMeta in ipairs(renderedRows or {}) do
        local frame = GetCol1DropFrame(rowMeta)
        if frame and frame:IsShown() then
            local left, right = frame:GetLeft(), frame:GetRight()
            if left and right then
                return left, right
            end
        end
    end

    return nil, nil
end

local function IsCursorWithinHorizontalBounds(cursorX, left, right, pad)
    if not (cursorX and left and right) then
        return false
    end
    pad = pad or 0
    return cursorX >= (left + pad) and cursorX <= (right - pad)
end

local function BuildCol1DropResult(action, rowIndex, rowMeta, extra)
    local frame = GetCol1DropFrame(rowMeta)
    if not (rowMeta and frame and frame:IsShown()) then
        return nil
    end
    if activeCol1DropSourceSection
        and not IsCol1OwnershipMoveAllowed(activeCol1DropSourceSection, rowMeta.section)
    then
        return nil
    end

    local result = {
        action = action,
        rowIndex = rowIndex,
        targetRow = rowMeta,
        anchorFrame = frame,
    }
    if extra then
        for key, value in pairs(extra) do
            result[key] = value
        end
    end
    return result
end

FindCol1SectionDividerTarget = function(renderedRows, section)
    for i, rowMeta in ipairs(renderedRows or {}) do
        if rowMeta.section == section and rowMeta.kind == "unloaded-divider" then
            return BuildCol1DropResult("reorder-before", i, rowMeta)
        end
    end
    return nil
end

local function FindFirstCol1UnloadedTargetInSection(renderedRows, section, startIndex)
    for i = startIndex or 1, #(renderedRows or {}) do
        local rowMeta = renderedRows[i]
        if rowMeta.section ~= section then
            if rowMeta.section then
                break
            end
        elseif rowMeta.loadBucket == "unloaded" and rowMeta.kind == "container" then
            return BuildCol1DropResult("reorder-before", i, rowMeta)
        end
    end
    return nil
end

local function FindLastCol1UnloadedTargetInSection(renderedRows, section, startIndex)
    for i = startIndex or #(renderedRows or {}), 1, -1 do
        local rowMeta = renderedRows[i]
        if rowMeta.section ~= section then
            if rowMeta.section then
                break
            end
        elseif rowMeta.loadBucket == "unloaded" and rowMeta.kind == "container" then
            return BuildCol1DropResult("reorder-after", i, rowMeta)
        end
    end
    return nil
end

local function ResolveCol1UnloadedSectionTarget(renderedRows, section, startIndex, preferLast)
    if preferLast then
        return FindLastCol1UnloadedTargetInSection(renderedRows, section, startIndex)
            or FindCol1SectionDividerTarget(renderedRows, section)
    end
    return FindFirstCol1UnloadedTargetInSection(renderedRows, section, startIndex)
        or FindCol1SectionDividerTarget(renderedRows, section)
end

local function FindFirstCol1DropTargetInSection(renderedRows, section, startIndex)
    for i = startIndex or 1, #(renderedRows or {}) do
        local rowMeta = renderedRows[i]
        if rowMeta.section ~= section then
            if rowMeta.section then
                break
            end
        elseif rowMeta.kind == "unloaded-divider" then
            return BuildCol1DropResult("reorder-before", i, rowMeta)
        elseif rowMeta.kind == "phantom" or rowMeta.acceptsDrop then
            return BuildCol1DropResult("reorder-before", i, rowMeta)
        end
    end
    return nil
end

local function FindLastCol1DropTargetInSection(renderedRows, section, startIndex)
    for i = startIndex or #(renderedRows or {}), 1, -1 do
        local rowMeta = renderedRows[i]
        if rowMeta.section ~= section then
            if rowMeta.section then
                break
            end
        elseif rowMeta.kind == "phantom" or rowMeta.acceptsDrop then
            return BuildCol1DropResult("reorder-after", i, rowMeta)
        end
    end
    return nil
end

local function ResolveCol1AuxBlockTarget(renderedRows, rowIndex, rowMeta, sourceLoadBucket)
    if not rowMeta then
        return nil
    end
    if sourceLoadBucket == "unloaded" then
        return ResolveCol1UnloadedSectionTarget(renderedRows, rowMeta.section, rowIndex + 1)
    end
    local nextTarget = FindFirstCol1DropTargetInSection(renderedRows, rowMeta.section, rowIndex + 1)
    if nextTarget then
        return nextTarget
    end
    return FindLastCol1DropTargetInSection(renderedRows, rowMeta.section, rowIndex - 1)
end

local function IsCol1UnloadedDragSource(sourceLoadBucket)
    return sourceLoadBucket == "unloaded"
end

local function IsCol1MixedDragSource(sourceLoadBucket)
    return sourceLoadBucket == "mixed"
end

local function ResolveCol1MixedSectionTarget(renderedRows, rowMeta, rowIndex, sourceSection, action)
    if not rowMeta then
        return nil
    end

    local targetSection = rowMeta.section
    if not targetSection then
        return nil
    end

    if targetSection == sourceSection then
        if rowMeta.kind == "section-header" then
            return FindFirstCol1DropTargetInSection(renderedRows, targetSection, rowIndex)
        end
        if rowMeta.kind == "unloaded-divider" then
            return FindCol1SectionDividerTarget(renderedRows, targetSection)
        end
        if rowMeta.kind == "phantom"
            or rowMeta.loadBucket == "unloaded"
            or rowMeta.acceptsDrop
        then
            return BuildCol1DropResult(action or "reorder-before", rowIndex, rowMeta)
        end
        return nil
    end

    if rowMeta.kind == "phantom" then
        return BuildCol1DropResult("reorder-before", rowIndex, rowMeta)
    end

    if rowMeta.kind == "unloaded-divider" then
        return FindCol1SectionDividerTarget(renderedRows, targetSection)
    end

    return FindFirstCol1DropTargetInSection(renderedRows, targetSection, rowIndex)
        or FindCol1SectionDividerTarget(renderedRows, targetSection)
end

local function GetCol1DropTarget(cursorX, cursorY, scrollWidget, renderedRows, sourceSection, sourceLoadBucket)
    if not renderedRows or #renderedRows == 0 then return nil end
    activeCol1DropSourceSection = sourceSection
    local sourceIsMixed = IsCol1MixedDragSource(sourceLoadBucket)
    local sourceIsUnloaded = IsCol1UnloadedDragSource(sourceLoadBucket)
    local contentLeft, contentRight = GetCol1HorizontalBounds(scrollWidget, renderedRows)
    if not IsCursorWithinHorizontalBounds(cursorX, contentLeft, contentRight, COL1_HIT_X_PAD) then
        return nil
    end

    for i, rowMeta in ipairs(renderedRows) do
        local frame = GetCol1DropFrame(rowMeta)
        if frame and frame:IsShown() then
            local left, right = frame:GetLeft(), frame:GetRight()
            local top = frame:GetTop()
            local bottom = frame:GetBottom()
            if top and bottom
                and IsCursorWithinHorizontalBounds(cursorX, left, right, COL1_HIT_X_PAD)
                and cursorY <= top
                and cursorY >= bottom
            then
                if rowMeta.kind == "aux-block" then
                    return ResolveCol1AuxBlockTarget(renderedRows, i, rowMeta, sourceLoadBucket)
                elseif rowMeta.kind == "section-header" then
                    if sourceIsMixed then
                        return ResolveCol1MixedSectionTarget(renderedRows, rowMeta, i + 1, sourceSection, "reorder-before")
                    end
                    if sourceIsUnloaded then
                        return ResolveCol1UnloadedSectionTarget(renderedRows, rowMeta.section, i + 1)
                    end
                    return FindFirstCol1DropTargetInSection(renderedRows, rowMeta.section, i + 1)
                elseif rowMeta.kind == "unloaded-divider" then
                    if sourceIsMixed then
                        return ResolveCol1MixedSectionTarget(renderedRows, rowMeta, i, sourceSection, "reorder-before")
                    end
                    if sourceIsUnloaded then
                        return ResolveCol1UnloadedSectionTarget(renderedRows, rowMeta.section, i + 1)
                    end
                    return FindCol1SectionDividerTarget(renderedRows, rowMeta.section)
                elseif rowMeta.loadBucket == "unloaded" then
                    if sourceIsMixed then
                        local mid = (top + bottom) / 2
                        if cursorY > mid then
                            return ResolveCol1MixedSectionTarget(renderedRows, rowMeta, i, sourceSection, "reorder-before")
                        end
                        return ResolveCol1MixedSectionTarget(renderedRows, rowMeta, i, sourceSection, "reorder-after")
                    end
                    if sourceIsUnloaded then
                        local mid = (top + bottom) / 2
                        if cursorY > mid then
                            return BuildCol1DropResult("reorder-before", i, rowMeta)
                        else
                            return BuildCol1DropResult("reorder-after", i, rowMeta)
                        end
                    end
                    return FindCol1SectionDividerTarget(renderedRows, rowMeta.section)
                elseif rowMeta.kind == "phantom" or rowMeta.acceptsDrop then
                    if sourceIsMixed then
                        local mid = (top + bottom) / 2
                        if cursorY > mid then
                            return ResolveCol1MixedSectionTarget(renderedRows, rowMeta, i, sourceSection, "reorder-before")
                        end
                        return ResolveCol1MixedSectionTarget(renderedRows, rowMeta, i, sourceSection, "reorder-after")
                    end
                    if sourceIsUnloaded then
                        return ResolveCol1UnloadedSectionTarget(renderedRows, rowMeta.section, i + 1)
                    end
                    local mid = (top + bottom) / 2
                    if cursorY > mid then
                        return BuildCol1DropResult("reorder-before", i, rowMeta)
                    else
                        return BuildCol1DropResult("reorder-after", i, rowMeta)
                    end
                else
                    return nil
                end
            end
        end
    end

    -- Cursor is in a gap between rows (e.g. between sections): find the first
    -- row whose top edge is below the cursor and target it with reorder-before.
    for i, rowMeta in ipairs(renderedRows) do
        local frame = GetCol1DropFrame(rowMeta)
        if frame and frame:IsShown() then
            local top = frame:GetTop()
            if top and cursorY > top then
                if rowMeta.kind == "section-header" then
                    if sourceIsMixed then
                        return ResolveCol1MixedSectionTarget(renderedRows, rowMeta, i + 1, sourceSection, "reorder-before")
                    end
                    if sourceIsUnloaded then
                        return ResolveCol1UnloadedSectionTarget(renderedRows, rowMeta.section, i + 1)
                    end
                    return FindFirstCol1DropTargetInSection(renderedRows, rowMeta.section, i + 1)
                elseif rowMeta.kind == "aux-block" then
                    return ResolveCol1AuxBlockTarget(renderedRows, i, rowMeta, sourceLoadBucket)
                elseif rowMeta.kind == "unloaded-divider" then
                    if sourceIsMixed then
                        return ResolveCol1MixedSectionTarget(renderedRows, rowMeta, i, sourceSection, "reorder-before")
                    end
                    if sourceIsUnloaded then
                        return ResolveCol1UnloadedSectionTarget(renderedRows, rowMeta.section, i + 1)
                    end
                    return FindCol1SectionDividerTarget(renderedRows, rowMeta.section)
                elseif rowMeta.loadBucket == "unloaded" then
                    if sourceIsMixed then
                        return ResolveCol1MixedSectionTarget(renderedRows, rowMeta, i, sourceSection, "reorder-before")
                    end
                    if sourceIsUnloaded then
                        return BuildCol1DropResult("reorder-before", i, rowMeta)
                    end
                    return FindCol1SectionDividerTarget(renderedRows, rowMeta.section)
                elseif rowMeta.kind == "phantom" or rowMeta.acceptsDrop then
                    if sourceIsMixed then
                        return ResolveCol1MixedSectionTarget(renderedRows, rowMeta, i, sourceSection, "reorder-before")
                    end
                    if sourceIsUnloaded then
                        return ResolveCol1UnloadedSectionTarget(renderedRows, rowMeta.section, i)
                    end
                    return BuildCol1DropResult("reorder-before", i, rowMeta)
                end
            end
        end
    end

    -- Below all rows: drop after the last row overall.
    for i = #renderedRows, 1, -1 do
        local rowMeta = renderedRows[i]
        local frame = GetCol1DropFrame(rowMeta)
        if frame and frame:IsShown() then
            if rowMeta.kind == "unloaded-divider" or rowMeta.loadBucket == "unloaded" then
                if sourceIsMixed then
                    return ResolveCol1MixedSectionTarget(renderedRows, rowMeta, i, sourceSection, "reorder-after")
                end
                if sourceIsUnloaded then
                    return ResolveCol1UnloadedSectionTarget(renderedRows, rowMeta.section, i, true)
                end
                local dividerTarget = FindCol1SectionDividerTarget(renderedRows, rowMeta.section)
                if dividerTarget then
                    return dividerTarget
                end
            elseif rowMeta.kind == "phantom" or rowMeta.acceptsDrop then
                if sourceIsMixed then
                    return ResolveCol1MixedSectionTarget(renderedRows, rowMeta, i, sourceSection, "reorder-after")
                end
                if sourceIsUnloaded then
                    return ResolveCol1UnloadedSectionTarget(renderedRows, rowMeta.section, i, true)
                end
                return BuildCol1DropResult("reorder-after", i, rowMeta, { isBelowAll = true })
            end
        end
    end
    return nil
end

IsUnloadedTopLevelDrop = function(state, dropTarget)
    if not IsCol1UnloadedDragSource(state and state.sourceLoadBucket) then
        return false
    end
    local targetRow = dropTarget and dropTarget.targetRow
    return targetRow and (targetRow.kind == "unloaded-divider" or targetRow.loadBucket == "unloaded")
end

ShouldIncludeCol1TopLevelOrderRow = function(row, includeUnloaded)
    if not row then
        return false
    end
    if row.kind ~= "container" then
        return false
    end
    if includeUnloaded then
        return row.loadBucket == "unloaded"
    end
    return row.loadBucket ~= "unloaded"
end

local function FindCol1TopLevelInsertPos(orderItems, targetRow, action, defaultPos)
    local insertPos = defaultPos or (#orderItems + 1)
    if not targetRow or targetRow.kind == "unloaded-divider" then
        return insertPos
    end
    for idx, item in ipairs(orderItems) do
        if item.kind == targetRow.kind and item.id == targetRow.id then
            insertPos = action == "reorder-after" and idx + 1 or idx
            break
        end
    end
    return insertPos
end

local function AssignCol1TopLevelOrders(orderItems, db, specId, startOrder)
    local nextOrder = startOrder or 1
    for _, item in ipairs(orderItems) do
        if db.groupContainers[item.id] then
            CooldownCompanion:SetOrderForSpec(db.groupContainers[item.id], specId, nextOrder)
            nextOrder = nextOrder + 1
        end
    end
    return nextOrder
end

local function PartitionSelectedContainersByLoadBucket(sourceContainerIds, renderedRows, specId, db)
    local loadBucketById = {}
    for _, row in ipairs(renderedRows or {}) do
        if row.kind == "container" and sourceContainerIds[row.id] then
            loadBucketById[row.id] = row.loadBucket
        end
    end

    local loaded, unloaded = {}, {}
    for cid in pairs(sourceContainerIds or {}) do
        local container = db.groupContainers[cid]
        if container then
            local item = {
                kind = "group",
                id = cid,
                order = CooldownCompanion:GetOrderForSpec(container, specId, cid),
            }
            if loadBucketById[cid] == "unloaded" then
                table.insert(unloaded, item)
            else
                table.insert(loaded, item)
            end
        end
    end

    table.sort(loaded, function(a, b) return a.order < b.order end)
    table.sort(unloaded, function(a, b) return a.order < b.order end)
    return loaded, unloaded
end

-- Reset drag indicator to default line style
local function ResetDragIndicatorStyle()
    local ind = CS.dragIndicator
    if not ind then return end
    ind:SetHeight(DRAG_INDICATOR_HEIGHT)
    ApplyDragIndicatorColor(ind, unpack(DRAG_INDICATOR_DEFAULT_COLOR))
end

-- The line says WHERE the group is going: the Global section's identity colour
-- for "global", the player's class colour for their own "char" section.
--
-- Those are the only two sections a Navigator drag can reach -- every
-- other-class section is rendered with disableDrag, so no drag starts in one.
-- Deliberately no fallback guess for those keys: if dragging is ever enabled
-- there, this returns nil and the caller keeps the current colour rather than
-- silently painting the line in the wrong class's colour.
--
-- C_ClassColor.GetClassColor is documented MayReturnNothing=true
-- (blizzard-ui-ptr, ptr lane, Interface 120100, build 12.1.0), hence the guard.
local function GetCol1SectionColor(section)
    if section == "global" then
        local c = ST._COL1_GLOBAL_SECTION_COLOR
        return c[1], c[2], c[3]
    end
    if section ~= "char" then
        return nil
    end
    local cc = C_ClassColor.GetClassColor(select(2, UnitClass("player")))
    if cc then
        return cc.r, cc.g, cc.b
    end
    return unpack(DRAG_INDICATOR_DEFAULT_COLOR)
end

-- A Navigator group row's widget frame is its header InteractiveLabel, which
-- AceGUI seats INSIDE the group's InlineGroup shell with the shell's own border
-- and padding around it. An insertion line anchored there draws inside the very
-- group it is meant to sit beside, so prefer the shell rect that
-- RenderContainerRow records on the row as dragShellFrame.
--
-- Note this is deliberately only an ANCHOR choice. Hit testing still runs
-- against widget.frame via GetCol1DropFrame, so where a drop resolves is
-- unchanged -- only where the line is painted.
local function GetCol1IndicatorAnchor(targetRow)
    if not targetRow then
        return nil
    end
    if targetRow.kind == "container" and targetRow.dragShellFrame then
        return targetRow.dragShellFrame
    end
    return targetRow.widget and targetRow.widget.frame
end

-- The whole visual for a Navigator group drag: one insertion line at the
-- resolved drop position.
--
-- Invariant: a drop target that would CHANGE something always paints a line,
-- and the only permitted silent branch is one where releasing does nothing.
-- Feedback and outcome are driven from the same predicate, so the line can
-- never go missing for a drop that would actually move a group -- that silent
-- case is what made dragging a loaded group over the unloaded region look like
-- nothing was happening even though the drop still applied on release.
--
-- If you are here because a line is missing, confirm the drop is genuinely a
-- no-op before treating the suppression below as the bug.
-- One gap between two groups has TWO valid spellings: "after the group above"
-- and "before the group below". They drop identically, but they anchor to
-- different frames, so the line lands a few pixels apart depending on which row
-- the cursor happened to be over when it resolved.
--
-- Collapse them to one canonical spelling -- always the row BELOW the gap -- so
-- a given destination always draws the line in exactly one place.
--
-- The equivalence is true BY CONSTRUCTION, not by assumption: the row this
-- returns is the next row that ShouldIncludeCol1TopLevelOrderRow admits, i.e.
-- the next entry in the very ordering the drop is computed against. "After item
-- N" and "before item N+1" are the same index.
--
-- Running off the end of the ordering does NOT mean there is only one spelling.
-- For a loaded source, "after the last loaded group" and "before the unloaded
-- divider" are the same boundary, and the divider is the form the gap pass and
-- the below-all pass both already produce -- so it is the canonical one, and
-- pass 1 has to be brought into line with it. Without this, dropping past the
-- last loaded group draws the line under that group's shell while merely moving
-- a few pixels further draws it above the "Unloaded Groups" heading instead.
--
-- Gated on a loaded source: an unloaded-source drag orders within the unloaded
-- run, which the divider sits ABOVE, not below.
--
-- Gated on a SINGLE-BUCKET source too. A mixed selection is applied through
-- PartitionSelectedContainersByLoadBucket and its targets come from
-- ResolveCol1MixedSectionTarget, neither of which shares the "after item N ==
-- before item N+1" identity the rewrite depends on -- so for a mixed drag the
-- rewritten line could point somewhere the drop will not land, which is exactly
-- the failure this whole function exists to prevent. Mixed drags keep the raw
-- target: one spelling drawn honestly beats two spellings unified by a rule
-- that does not hold.
local function CanonicalizeCol1IndicatorTarget(state, dropTarget)
    if dropTarget.action ~= "reorder-after" then
        return dropTarget
    end

    if IsCol1MixedDragSource(state.sourceLoadBucket) then
        return dropTarget
    end

    local renderedRows = state.col1RenderedRows
    local rowIndex = dropTarget.rowIndex
    local section = dropTarget.targetRow and dropTarget.targetRow.section
    if not (renderedRows and rowIndex and section) then
        return dropTarget
    end

    local includeUnloaded = IsUnloadedTopLevelDrop(state, dropTarget)
    for i = rowIndex + 1, #renderedRows do
        local row = renderedRows[i]
        if row.section ~= section then
            break
        end
        if ShouldIncludeCol1TopLevelOrderRow(row, includeUnloaded) then
            return BuildCol1DropResult("reorder-before", i, row) or dropTarget
        end
    end

    if not includeUnloaded then
        local dividerTarget = FindCol1SectionDividerTarget(renderedRows, section)
        if dividerTarget then
            return dividerTarget
        end
    end

    return dropTarget
end

local function ShowCol1DropIndicator(state)
    local dropTarget = state and state.dropTarget
    if not dropTarget
        or (dropTarget.action ~= "reorder-before" and dropTarget.action ~= "reorder-after")
    then
        HideDragIndicator()
        return
    end

    -- The slots directly above and below a group resolve to a valid target that
    -- would land it exactly where it already sits. Releasing there does nothing,
    -- so the line must not advertise it. This is the SAME predicate
    -- FinishCol1GroupDrag uses to decide whether to do any work, so the line and
    -- the outcome cannot disagree.
    --
    -- Single-group only: IsCol1GroupDropNoOp reasons about one sourceGroupId,
    -- and a multi-group drag carries only the row you grabbed there, so it
    -- cannot answer for the whole selection.
    --
    -- Memoised: this runs on every tracker tick and the predicate rebuilds the
    -- whole top-level order list and rescans for the source position each time.
    --
    -- Keyed on action/targetRow/rowIndex rather than on the dropTarget table,
    -- which GetCol1DropTarget rebuilds every tick and would therefore never
    -- match. targetRow IS stable -- it is the rowMeta out of col1RenderedRows --
    -- and a Column 1 rebuild replaces those tables, so the key invalidates
    -- itself exactly when the geometry it was computed against goes away.
    if state.kind == "group" then
        if state._cdcNoOpAction ~= dropTarget.action
            or state._cdcNoOpRow ~= dropTarget.targetRow
            or state._cdcNoOpIndex ~= dropTarget.rowIndex
        then
            state._cdcNoOpAction = dropTarget.action
            state._cdcNoOpRow = dropTarget.targetRow
            state._cdcNoOpIndex = dropTarget.rowIndex
            state._cdcNoOpResult = IsCol1GroupDropNoOp(state)
        end
        if state._cdcNoOpResult then
            HideDragIndicator()
            return
        end
    end

    -- Display only. The drop still applies from state.dropTarget, which is
    -- untouched -- this picks which of two identical spellings gets drawn.
    local shown = CanonicalizeCol1IndicatorTarget(state, dropTarget)

    SetDragIndicatorColor(GetCol1SectionColor(shown.targetRow and shown.targetRow.section))
    ShowDragIndicator(
        GetCol1IndicatorAnchor(shown.targetRow) or shown.anchorFrame,
        shown.action == "reorder-before",
        state.scrollWidget
    )
end

------------------------------------------------------------------------
-- Navigator rail Panel drop targets
------------------------------------------------------------------------
local function CanRailPanelsMoveToContainer(sourcePanelIds, targetContainerId)
    local db = CooldownCompanion.db and CooldownCompanion.db.profile
    if not (db and db.groups and db.groupContainers and db.groupContainers[targetContainerId]) then
        return false
    end

    for panelId in pairs(sourcePanelIds or {}) do
        local panel = db.groups[panelId]
        if not panel then
            return false
        end
        if panel.parentContainerId ~= targetContainerId then
            if not CooldownCompanion.CanMovePanelToContainer
                or CooldownCompanion:CanMovePanelToContainer(panelId, targetContainerId) ~= true then
                return false
            end
        end
    end
    return true
end

-- Walk forward from fromIndex for the first panel row belonging to containerId
-- that is not itself being dragged. Every aux row inside a group block carries
-- ownerId == the container, so a row without it means we have walked out of the
-- block and there is nothing further to find. Entry rows sit between panel rows
-- and are simply skipped.
local function FindRailPanelRowInContainer(renderedRows, containerId, fromIndex, sourcePanelIds)
    for i = fromIndex, #(renderedRows or {}) do
        local rowMeta = renderedRows[i]
        if rowMeta.ownerId ~= containerId then
            return nil
        end
        if rowMeta.kind == "aux-block"
            and rowMeta.rowType == "panel"
            and not (sourcePanelIds and sourcePanelIds[rowMeta.id])
        then
            return i, rowMeta
        end
    end
    return nil
end

local function BuildRailPanelDropTarget(rowMeta, rowIndex, cursorY, sourcePanelIds, renderedRows)
    local frame = GetCol1DropFrame(rowMeta)
    if not (frame and frame:IsShown()) then
        return nil
    end

    local top, bottom = frame:GetTop(), frame:GetBottom()
    if not (top and bottom and cursorY <= top and cursorY >= bottom) then
        return nil
    end

    if rowMeta.kind == "container" then
        if not CanRailPanelsMoveToContainer(sourcePanelIds, rowMeta.id) then
            return nil
        end

        -- The group header sits ABOVE its panel rows, so dropping on it means
        -- "put this at the TOP of the group". Returning append here meant
        -- dragging the first panel up onto its own header moved it to the
        -- BOTTOM -- drag up, land last.
        if rowMeta.isExpanded then
            local firstIndex, firstRow =
                FindRailPanelRowInContainer(renderedRows, rowMeta.id, rowIndex + 1, sourcePanelIds)
            local firstFrame = firstRow and GetCol1DropFrame(firstRow)
            if firstFrame and firstFrame:IsShown() then
                return {
                    action = "before",
                    targetContainerId = rowMeta.id,
                    targetPanelId = firstRow.id,
                    targetRow = firstRow,
                    rowIndex = firstIndex,
                    anchorFrame = firstFrame,
                    anchorAbove = true,
                }
            end
        end

        -- A collapsed group renders no panel rows to aim at, but the header must
        -- still mean "top" -- otherwise releasing before the spring-open timer
        -- fires appends to the BOTTOM while waiting for it inserts at the top,
        -- i.e. the same gesture lands differently depending on timing.
        --
        -- BuildRailPanelFinalOrder resolves targetPanelId against the container's
        -- MODEL order, not against rendered rows, so a panel id taken straight
        -- from GetPanels is a valid target even with nothing rendered. The line
        -- still anchors under the header, and spring-open still runs.
        local firstPanelId
        for _, panelInfo in ipairs(CooldownCompanion:GetPanels(rowMeta.id) or {}) do
            if not (sourcePanelIds and sourcePanelIds[panelInfo.groupId]) then
                firstPanelId = panelInfo.groupId
                break
            end
        end

        return {
            action = firstPanelId and "before" or "append",
            targetContainerId = rowMeta.id,
            targetPanelId = firstPanelId,
            targetRow = rowMeta,
            rowIndex = rowIndex,
            anchorFrame = frame,
            anchorAbove = false,
            springContainerId = rowMeta.isExpanded and nil or rowMeta.id,
        }
    end

    if rowMeta.kind == "aux-block" and rowMeta.rowType == "panel" then
        if sourcePanelIds and sourcePanelIds[rowMeta.id] then
            return nil
        end
        if not CanRailPanelsMoveToContainer(sourcePanelIds, rowMeta.ownerId) then
            return nil
        end
        local above = cursorY > ((top + bottom) * 0.5)
        return {
            action = above and "before" or "after",
            targetContainerId = rowMeta.ownerId,
            targetPanelId = rowMeta.id,
            targetRow = rowMeta,
            rowIndex = rowIndex,
            anchorFrame = frame,
            anchorAbove = above,
        }
    end

    return nil
end

local function GetRailPanelDropTarget(cursorX, cursorY, scrollWidget, renderedRows, sourcePanelIds)
    if not (renderedRows and next(sourcePanelIds or {})) then
        return nil
    end

    local left, right = GetCol1HorizontalBounds(scrollWidget, renderedRows)
    if not IsCursorWithinHorizontalBounds(cursorX, left, right, COL1_HIT_X_PAD) then
        return nil
    end

    for rowIndex, rowMeta in ipairs(renderedRows) do
        local target = BuildRailPanelDropTarget(rowMeta, rowIndex, cursorY, sourcePanelIds, renderedRows)
        if target then
            return target
        end
    end
    return nil
end

-- The panel-side counterpart of CanonicalizeCol1IndicatorTarget: "after panel N"
-- and "before panel N+1" are the same gap but anchor to different rows, so the
-- line would sit a few pixels apart depending on which half of which row the
-- cursor was in. Always draw the row BELOW the gap.
--
-- Equivalent by construction: BuildRailPanelFinalOrder computes insertPos from
-- the target's position in the ordering with the dragged panels removed, and
-- skipping source rows here mirrors exactly that exclusion.
local function CanonicalizeRailPanelIndicatorTarget(state, dropTarget)
    if dropTarget.action ~= "after" then
        return dropTarget
    end

    local nextIndex, nextRow = FindRailPanelRowInContainer(
        state.railPanelRows,
        dropTarget.targetContainerId,
        (dropTarget.rowIndex or 0) + 1,
        state.sourcePanelIds
    )
    local nextFrame = nextRow and GetCol1DropFrame(nextRow)
    if not (nextFrame and nextFrame:IsShown()) then
        return dropTarget
    end

    return {
        action = "before",
        targetContainerId = dropTarget.targetContainerId,
        targetPanelId = nextRow.id,
        targetRow = nextRow,
        rowIndex = nextIndex,
        anchorFrame = nextFrame,
        anchorAbove = true,
    }
end

-- Same three guarantees the group line has: one canonical position per
-- destination, nothing drawn for a drop that would change nothing, and a colour
-- that names the destination section.
--
-- BuildRailPanelFinalOrder and RailPanelDropIsNoOp live in DragReorderLifecycle,
-- which loads AFTER this file, so they are reached through DR at call time
-- rather than captured as upvalues. They are the SAME pair FinishRailPanelDrag
-- consults, so the line and the outcome cannot disagree.
local function ShowRailPanelDropIndicator(state)
    local dropTarget = state and state.dropTarget
    if not dropTarget then
        HideDragIndicator()
        return
    end

    -- Memoised on the parts that identify the destination; the dropTarget table
    -- itself is rebuilt every tracker tick and would never compare equal.
    if state._cdcRailNoOpAction ~= dropTarget.action
        or state._cdcRailNoOpPanel ~= dropTarget.targetPanelId
        or state._cdcRailNoOpContainer ~= dropTarget.targetContainerId
    then
        state._cdcRailNoOpAction = dropTarget.action
        state._cdcRailNoOpPanel = dropTarget.targetPanelId
        state._cdcRailNoOpContainer = dropTarget.targetContainerId

        local isNoOp = false
        if DR.BuildRailPanelFinalOrder and DR.RailPanelDropIsNoOp then
            local finalOrder = DR.BuildRailPanelFinalOrder(state, dropTarget)
            isNoOp = DR.RailPanelDropIsNoOp(state, dropTarget, finalOrder)
        end
        state._cdcRailNoOpResult = isNoOp
    end
    if state._cdcRailNoOpResult then
        HideDragIndicator()
        return
    end

    local shown = CanonicalizeRailPanelIndicatorTarget(state, dropTarget)

    -- anchorFrame is already the right rect for both shapes: a panel row's own
    -- frame, or the group header for an append. Deliberately NOT routed through
    -- GetCol1IndicatorAnchor -- that promotes a container row to its whole
    -- InlineGroup shell, which is correct when a GROUP is being reordered around
    -- and wrong when a panel is going inside one.
    SetDragIndicatorColor(GetCol1SectionColor(shown.targetRow and shown.targetRow.section))
    ShowDragIndicator(shown.anchorFrame, shown.anchorAbove, state.scrollWidget)
end

DR.GetDragIndicator = GetDragIndicator
DR.HideDragIndicator = HideDragIndicator
DR.GetScaledCursorCoordinates = GetScaledCursorCoordinates
DR.GetScaledCursorPosition = GetScaledCursorPosition
DR.GetRawCursorCoordinates = GetRawCursorCoordinates
DR.GetDropIndex = GetDropIndex
DR.ShowDragIndicator = ShowDragIndicator
DR.ShowCol1DropIndicator = ShowCol1DropIndicator
DR.ShowRailPanelDropIndicator = ShowRailPanelDropIndicator
DR.SetDragIndicatorColor = SetDragIndicatorColor
DR.GetCol1SectionColor = GetCol1SectionColor
DR.GetCol1DropTarget = GetCol1DropTarget
DR.ResetDragIndicatorStyle = ResetDragIndicatorStyle
DR.IsCol1GroupDropNoOp = IsCol1GroupDropNoOp
DR.IsUnloadedTopLevelDrop = IsUnloadedTopLevelDrop
DR.ShouldIncludeCol1TopLevelOrderRow = ShouldIncludeCol1TopLevelOrderRow
DR.FindCol1SectionDividerTarget = FindCol1SectionDividerTarget
DR.IsCol1MixedDragSource = IsCol1MixedDragSource
DR.FindCol1TopLevelInsertPos = FindCol1TopLevelInsertPos
DR.AssignCol1TopLevelOrders = AssignCol1TopLevelOrders
DR.PartitionSelectedContainersByLoadBucket = PartitionSelectedContainersByLoadBucket
DR.GetRailPanelDropTarget = GetRailPanelDropTarget
