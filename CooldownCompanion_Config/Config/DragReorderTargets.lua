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
local function GetDragIndicator()
    if not CS.dragIndicator then
        CS.dragIndicator = CreateFrame("Frame", nil, UIParent)
        CS.dragIndicator:SetFrameStrata("TOOLTIP")
        CS.dragIndicator:SetSize(10, 2)
        local tex = CS.dragIndicator:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints()
        tex:SetColorTexture(0.2, 0.6, 1.0, 1.0)
        CS.dragIndicator.tex = tex
        CS.dragIndicator:Hide()
    end
    return CS.dragIndicator
end

local function HideDragIndicator()
    if CS.dragIndicator then CS.dragIndicator:Hide() end
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
    width = width or 100
    ind:SetWidth(width)
    ind:ClearAllPoints()
    if anchorAbove then
        ind:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, 1)
    else
        ind:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -1)
    end
    ind:Show()
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


local function PerformGroupReorder(sourceIndex, dropIndex, groupIds)
    if dropIndex > sourceIndex then dropIndex = dropIndex - 1 end
    if sourceIndex == dropIndex then return end
    local db = CooldownCompanion.db.profile
    local id = table.remove(groupIds, sourceIndex)
    table.insert(groupIds, dropIndex, id)
    -- Reassign .order based on new list position
    for i, gid in ipairs(groupIds) do
        if db.groups[gid] then
            db.groups[gid].order = i
        end
    end
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
    if CS.dragIndicator and CS.dragIndicator.tex then
        CS.dragIndicator:SetHeight(2)
        CS.dragIndicator.tex:SetColorTexture(0.2, 0.6, 1.0, 1.0)
    end
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

local function BuildRailPanelDropTarget(rowMeta, rowIndex, cursorY, sourcePanelIds)
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
        return {
            action = "append",
            targetContainerId = rowMeta.id,
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
        local target = BuildRailPanelDropTarget(rowMeta, rowIndex, cursorY, sourcePanelIds)
        if target then
            return target
        end
    end
    return nil
end

DR.GetDragIndicator = GetDragIndicator
DR.HideDragIndicator = HideDragIndicator
DR.GetScaledCursorCoordinates = GetScaledCursorCoordinates
DR.GetScaledCursorPosition = GetScaledCursorPosition
DR.GetRawCursorCoordinates = GetRawCursorCoordinates
DR.GetDropIndex = GetDropIndex
DR.ShowDragIndicator = ShowDragIndicator
DR.PerformGroupReorder = PerformGroupReorder
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
