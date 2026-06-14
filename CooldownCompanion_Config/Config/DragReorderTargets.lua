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

local function FindCol1FolderBlockRange(rows, folderId)
    local headerIndex
    for i, row in ipairs(rows) do
        if row.kind == "folder" and row.id == folderId then
            headerIndex = i
            break
        end
    end
    if not headerIndex then
        return nil
    end

    local lastIndex = headerIndex
    for i = headerIndex + 1, #rows do
        local row = rows[i]
        if row.kind == "container" and row.inFolder == folderId then
            lastIndex = i
        elseif row.kind == "aux-block" and row.ownerFolderId == folderId then
            lastIndex = i
        else
            break
        end
    end
    return headerIndex, lastIndex
end

local function IsExternalFolderChildTarget(rowMeta, sourceKind, sourceFolderId)
    if not (rowMeta and rowMeta.kind == "container" and rowMeta.inFolder) then
        return false
    end
    if sourceKind ~= "group" and sourceKind ~= "folder-group" then
        return false
    end
    return sourceFolderId ~= rowMeta.inFolder
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

------------------------------------------------------------------------
-- Column 2 cross-panel drop target detection
------------------------------------------------------------------------
local function FindPreviousPanelId(renderedRows, currentIndex)
    for i = currentIndex - 1, 1, -1 do
        if renderedRows[i].kind == "header" then
            return renderedRows[i].panelId
        end
    end
    return nil
end

local function PanelAcceptsEntryDrop(panelId)
    local db = CooldownCompanion.db and CooldownCompanion.db.profile
    local group = panelId and db and db.groups and db.groups[panelId]
    if not group then return false end
    return not CooldownCompanion.GetPanelManualEntryRejectMessage
        or CooldownCompanion:GetPanelManualEntryRejectMessage(group) == nil
end

local function BuildCol2EntryDropTarget(action, targetPanelId, targetIndex, anchorFrame, anchorAbove)
    if not PanelAcceptsEntryDrop(targetPanelId) then
        return nil
    end
    return {
        action = action,
        targetPanelId = targetPanelId,
        targetIndex = targetIndex,
        anchorFrame = anchorFrame,
        anchorAbove = anchorAbove,
    }
end

local function GetCol2DropTarget(cursorY, renderedRows)
    if not renderedRows or #renderedRows == 0 then return nil end

    for i, rowMeta in ipairs(renderedRows) do
        local frame = rowMeta.widget and rowMeta.widget.frame
        if frame and frame:IsShown() then
            local top = frame:GetTop()
            local bottom = frame:GetBottom()
            if top and bottom and cursorY <= top and cursorY >= bottom then
                local mid = (top + bottom) / 2

                if rowMeta.kind == "button" then
                    if cursorY > mid then
                        return BuildCol2EntryDropTarget("insert", rowMeta.panelId, rowMeta.buttonIndex, frame, true)
                    else
                        return BuildCol2EntryDropTarget("insert", rowMeta.panelId, rowMeta.buttonIndex + 1, frame, false)
                    end
                elseif rowMeta.kind == "header" then
                    if rowMeta.isCollapsed then
                        -- Drop onto collapsed header = append to that panel
                        return BuildCol2EntryDropTarget("append-to-collapsed", rowMeta.panelId, nil, frame, false)
                    else
                        return BuildCol2EntryDropTarget("insert", rowMeta.panelId, 1, frame, true)
                    end
                end
            end
        end
    end

    -- Cursor is in a vertical gap between visible rows/panels.
    for i = 1, #renderedRows - 1 do
        local prevMeta = renderedRows[i]
        local nextMeta = renderedRows[i + 1]
        local prevFrame = prevMeta.widget and prevMeta.widget.frame
        local nextFrame = nextMeta.widget and nextMeta.widget.frame
        if prevFrame and nextFrame and prevFrame:IsShown() and nextFrame:IsShown() then
            local prevBottom = prevFrame:GetBottom()
            local nextTop = nextFrame:GetTop()
            if prevBottom and nextTop and cursorY <= prevBottom and cursorY >= nextTop then
                local gapMid = (prevBottom + nextTop) / 2
                if nextMeta.kind == "header" and prevMeta.panelId ~= nextMeta.panelId then
                    if cursorY > gapMid then
                        return BuildCol2EntryDropTarget("append", prevMeta.panelId, nil, prevFrame, false)
                    end

                    if nextMeta.isCollapsed then
                        return BuildCol2EntryDropTarget("append-to-collapsed", nextMeta.panelId, nil, nextFrame, true)
                    end

                    return BuildCol2EntryDropTarget("insert", nextMeta.panelId, 1, nextFrame, true)
                end

                if nextMeta.kind == "button" then
                    return BuildCol2EntryDropTarget("insert", nextMeta.panelId, nextMeta.buttonIndex, nextFrame, true)
                elseif nextMeta.kind == "header" then
                    return BuildCol2EntryDropTarget(
                        nextMeta.isCollapsed and "append-to-collapsed" or "insert",
                        nextMeta.panelId,
                        nextMeta.isCollapsed and nil or 1,
                        nextFrame,
                        true
                    )
                end
            end
        end
    end

    -- Below all rows: append to last panel
    local lastRow = renderedRows[#renderedRows]
    if lastRow then
        local panelId = lastRow.panelId
        local lastFrame = lastRow.widget and lastRow.widget.frame
        if lastFrame and lastFrame:IsShown() then
            return BuildCol2EntryDropTarget("append", panelId, nil, lastFrame, false)
        end
    end
    return nil
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
-- Column 1 drop no-op helpers
------------------------------------------------------------------------

local IsUnloadedTopLevelDrop
local ShouldIncludeCol1TopLevelOrderRow

local function ResolveCol1GroupDropTargetFolderId(state, dropTarget)
    if not dropTarget then
        return nil
    end

    if dropTarget.folderBlockId then
        if dropTarget.action == "into-folder" then
            return dropTarget.folderBlockId
        end
        return nil
    end

    if dropTarget.action == "into-folder" then
        return dropTarget.targetFolderId
    end

    if dropTarget.action ~= "reorder-before" and dropTarget.action ~= "reorder-after" then
        return nil
    end

    local targetRow = dropTarget.targetRow
    if not targetRow or dropTarget.isBelowAll then
        return nil
    end

    if targetRow.kind == "container" and targetRow.inFolder then
        return targetRow.inFolder
    end

    return nil
end

local function FindCol1GroupSourcePosition(renderedRows, section, folderId, sourceContainerId, includeUnloaded)
    local pos = 0
    for _, row in ipairs(renderedRows or {}) do
        if row.section == section then
            if folderId then
                if row.kind == "container" and row.inFolder == folderId then
                    pos = pos + 1
                    if row.id == sourceContainerId then
                        return pos
                    end
                end
            elseif ShouldIncludeCol1TopLevelOrderRow(row, includeUnloaded) then
                pos = pos + 1
                if row.kind == "container" and row.id == sourceContainerId then
                    return pos
                end
            end
        end
    end
    return nil
end

local function BuildCol1GroupOrderItems(renderedRows, section, folderId, sourceContainerId, includeUnloaded)
    local orderItems = {}
    for _, row in ipairs(renderedRows or {}) do
        if row.section == section then
            if folderId then
                if row.kind == "container" and row.inFolder == folderId and row.id ~= sourceContainerId then
                    table.insert(orderItems, row.id)
                end
            elseif ShouldIncludeCol1TopLevelOrderRow(row, includeUnloaded) then
                if row.id ~= sourceContainerId then
                    table.insert(orderItems, { kind = row.kind, id = row.id })
                end
            end
        end
    end
    return orderItems
end

local function ResolveCol1GroupInsertPos(orderItems, dropTarget, folderId, includeUnloaded)
    local targetRow = dropTarget and dropTarget.targetRow
    if folderId then
        local insertPos = #orderItems + 1
        if targetRow and targetRow.kind == "container" then
            for idx, cid in ipairs(orderItems) do
                if cid == targetRow.id then
                    insertPos = dropTarget.action == "reorder-after" and idx + 1 or idx
                    break
                end
            end
        end
        return insertPos
    end

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
    local targetFolderId = ResolveCol1GroupDropTargetFolderId(state, dropTarget)

    if targetSection ~= state.sourceSection or targetFolderId ~= state.sourceFolderId then
        return false
    end

    if dropTarget.action ~= "into-folder"
        and dropTarget.action ~= "reorder-before"
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

    local includeUnloaded = IsUnloadedTopLevelDrop(state, dropTarget, targetFolderId)
    local sourcePos = FindCol1GroupSourcePosition(
        renderedRows,
        targetSection,
        targetFolderId,
        state.sourceGroupId,
        includeUnloaded
    )
    if not sourcePos then
        return false
    end

    local orderItems = BuildCol1GroupOrderItems(
        renderedRows,
        targetSection,
        targetFolderId,
        state.sourceGroupId,
        includeUnloaded
    )
    local insertPos = ResolveCol1GroupInsertPos(orderItems, dropTarget, targetFolderId, includeUnloaded)
    return insertPos == sourcePos
end

local function FindCol1FolderSourcePosition(renderedRows, section, sourceFolderId, includeUnloaded)
    local pos = 0
    for _, row in ipairs(renderedRows or {}) do
        if row.section == section and ShouldIncludeCol1TopLevelOrderRow(row, includeUnloaded) then
            pos = pos + 1
            if row.kind == "folder" and row.id == sourceFolderId then
                return pos
            end
        end
    end
    return nil
end

local function BuildCol1FolderOrderItems(renderedRows, section, sourceFolderId, includeUnloaded)
    local orderItems = {}
    for _, row in ipairs(renderedRows or {}) do
        if row.section == section and ShouldIncludeCol1TopLevelOrderRow(row, includeUnloaded) then
            if row.id ~= sourceFolderId then
                table.insert(orderItems, { kind = row.kind, id = row.id })
            end
        end
    end
    return orderItems
end

local function ResolveCol1FolderInsertPos(orderItems, dropTarget, targetRow, includeUnloaded)
    local insertPos = includeUnloaded and 1 or (#orderItems + 1)
    if targetRow and targetRow.kind ~= "unloaded-divider" then
        insertPos = #orderItems + 1
        for idx, item in ipairs(orderItems) do
            local targetKind = targetRow.kind
            local targetId = targetRow.id
            if targetRow.inFolder then
                targetKind = "folder"
                targetId = targetRow.inFolder
            end
            if item.kind == targetKind and item.id == targetId then
                insertPos = dropTarget.action == "reorder-after" and idx + 1 or idx
                break
            end
        end
    end
    return insertPos
end

local function IsCol1FolderDropNoOp(state)
    local dropTarget = state and state.dropTarget
    if not dropTarget then
        return true
    end

    if dropTarget.action ~= "reorder-before" and dropTarget.action ~= "reorder-after" then
        return false
    end

    local targetRow = dropTarget.targetRow
    local targetSection = (targetRow and targetRow.section) or state.sourceSection
    if targetSection ~= state.sourceSection then
        return false
    end

    if targetRow and targetRow.kind == "folder" and targetRow.id == state.sourceFolderId then
        return true
    end

    local renderedRows = state.col1RenderedRows
    if not renderedRows then
        return false
    end

    local includeUnloaded = IsUnloadedTopLevelDrop(state, dropTarget, nil)
    local sourcePos = FindCol1FolderSourcePosition(renderedRows, targetSection, state.sourceFolderId, includeUnloaded)
    if not sourcePos then
        return false
    end

    local orderItems = BuildCol1FolderOrderItems(renderedRows, targetSection, state.sourceFolderId, includeUnloaded)
    local insertPos = ResolveCol1FolderInsertPos(orderItems, dropTarget, targetRow, includeUnloaded)
    return insertPos == sourcePos
end


local function GetCol2CompactPanelDropTarget(cursorY)
    local preview = CS.col2Preview
    local entries = preview and preview.compactEntries
    if not entries or #entries == 0 then return nil end

    for i, entry in ipairs(entries) do
        local frame = entry.frame
        if frame and frame:IsShown() then
            local top = frame:GetTop()
            local bottom = frame:GetBottom()
            if top and bottom then
                local mid = (top + bottom) / 2
                if cursorY > mid then
                    return {
                        targetIndex = entry.originalIndex,
                        targetPanelId = entry.panelId,
                        anchorFrame = frame,
                        anchorAbove = true,
                    }
                elseif i == #entries then
                    return {
                        targetIndex = (entry.originalIndex or i) + 1,
                        targetPanelId = entry.panelId,
                        anchorFrame = frame,
                        anchorAbove = false,
                    }
                end
            end
        end
    end

    local first = entries[1]
    if first and first.frame and first.frame:IsShown() then
        return {
            targetIndex = first.originalIndex or 1,
            targetPanelId = first.panelId,
            anchorFrame = first.frame,
            anchorAbove = true,
        }
    end
    return nil
end

------------------------------------------------------------------------
-- Column 2 panel-header drop target detection
------------------------------------------------------------------------
local function GetCol2PanelDropTarget(cursorY, panelDropTargets)
    if not panelDropTargets or #panelDropTargets == 0 then return nil end

    for i, entry in ipairs(panelDropTargets) do
        local frame = entry.frame
        if frame and frame:IsShown() then
            local top = frame:GetTop()
            local bottom = frame:GetBottom()
            if top and bottom then
                local mid = (top + bottom) / 2
                if cursorY > mid then
                    -- Cursor is in the upper half → drop above this panel (index i)
                    return {
                        targetIndex = i,
                        targetPanelId = entry.panelId,
                        anchorFrame = frame,
                        anchorAbove = true,
                    }
                elseif i == #panelDropTargets then
                    -- Below midpoint of last panel → drop after last
                    return {
                        targetIndex = i + 1,
                        targetPanelId = entry.panelId,
                        anchorFrame = frame,
                        anchorAbove = false,
                    }
                end
            end
        end
    end

    -- Cursor above all panels → index 1
    local first = panelDropTargets[1]
    if first and first.frame and first.frame:IsShown() then
        return {
            targetIndex = 1,
            targetPanelId = first.panelId,
            anchorFrame = first.frame,
            anchorAbove = true,
        }
    end
    return nil
end

------------------------------------------------------------------------
-- Panel reorder
------------------------------------------------------------------------
local function PerformPanelReorder(sourcePanelId, dropIndex, panelDropTargets)
    local db = CooldownCompanion.db.profile
    -- Build ordered panelIds list from drop targets
    local panelIds = {}
    for _, entry in ipairs(panelDropTargets) do
        table.insert(panelIds, entry.panelId)
    end
    -- Find source index
    local sourceIndex
    for i, pid in ipairs(panelIds) do
        if pid == sourcePanelId then
            sourceIndex = i
            break
        end
    end
    if not sourceIndex then return end
    if dropIndex > sourceIndex then dropIndex = dropIndex - 1 end
    if sourceIndex == dropIndex then return end
    table.remove(panelIds, sourceIndex)
    table.insert(panelIds, dropIndex, sourcePanelId)
    -- Reassign .order based on new list position
    for i, pid in ipairs(panelIds) do
        if db.groups[pid] then
            db.groups[pid].order = i
        end
    end
end

local function IsPanelReorderNoOp(sourcePanelId, dropIndex, panelDropTargets)
    if not (sourcePanelId and dropIndex and panelDropTargets) then
        return true
    end

    local sourceIndex
    for i, entry in ipairs(panelDropTargets) do
        if entry.panelId == sourcePanelId then
            sourceIndex = i
            break
        end
    end
    if not sourceIndex then
        return true
    end

    if dropIndex > sourceIndex then
        dropIndex = dropIndex - 1
    end

    return sourceIndex == dropIndex
end

------------------------------------------------------------------------
-- Group reorder
------------------------------------------------------------------------
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
-- Drop target detection for column 1 with folder support
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

local function GetCol1FolderBlockIdForRow(rowMeta, sourceKind)
    if sourceKind ~= "group" and sourceKind ~= "folder-group" then
        return nil
    end
    if not rowMeta then
        return nil
    end

    if rowMeta.kind == "folder" then
        return rowMeta.id
    end
    if rowMeta.kind == "container" and rowMeta.inFolder then
        return rowMeta.inFolder
    end
    if rowMeta.kind == "aux-block" and rowMeta.ownerFolderId then
        return rowMeta.ownerFolderId
    end

    return nil
end

local function GetCol1FolderBlockInfo(renderedRows, folderId)
    if not folderId then
        return nil
    end

    local firstIndex, lastIndex = FindCol1FolderBlockRange(renderedRows or {}, folderId)
    if not firstIndex or not lastIndex then
        return nil
    end

    local firstRow = renderedRows[firstIndex]
    local lastRow = renderedRows[lastIndex]
    local firstFrame = GetCol1DropFrame(firstRow)
    local lastFrame = GetCol1DropFrame(lastRow)
    if not (firstRow and lastRow and firstFrame and lastFrame and firstFrame:IsShown() and lastFrame:IsShown()) then
        return nil
    end

    local top = firstFrame:GetTop()
    local bottom = lastFrame:GetBottom()
    if not (top and bottom) then
        return nil
    end

    return {
        folderId = folderId,
        headerIndex = firstIndex,
        firstIndex = firstIndex,
        lastIndex = lastIndex,
        headerRow = firstRow,
        firstRow = firstRow,
        lastRow = lastRow,
        firstFrame = firstFrame,
        lastFrame = lastFrame,
        top = top,
        bottom = bottom,
    }
end

local function GetCol1FolderBlockEdgeInset(frame)
    local height = frame and frame:GetHeight()
    if not height or height <= 0 then
        return 8
    end
    return math.min(14, math.max(8, height * 0.35))
end

local function BuildCol1FolderBlockDropResult(renderedRows, folderId, action, extra)
    local blockInfo = GetCol1FolderBlockInfo(renderedRows, folderId)
    if not blockInfo then
        return nil
    end

    local result = BuildCol1DropResult(action, blockInfo.headerIndex, blockInfo.headerRow, {
        targetFolderId = folderId,
        folderBlockId = folderId,
        folderBlockFirstRow = blockInfo.firstRow,
        folderBlockLastRow = blockInfo.lastRow,
        folderBlockFirstIndex = blockInfo.firstIndex,
        folderBlockLastIndex = blockInfo.lastIndex,
        folderBlockPosition = action == "into-folder" and "inside"
            or (action == "reorder-before" and "before" or "after"),
    })
    if not result then
        return nil
    end

    result.anchorFrame = action == "reorder-after" and blockInfo.lastFrame or blockInfo.firstFrame
    if extra then
        for key, value in pairs(extra) do
            result[key] = value
        end
    end
    return result
end

local function BuildCol1FolderReorderBlockTarget(renderedRows, folderId, action, extra)
    local blockInfo = GetCol1FolderBlockInfo(renderedRows, folderId)
    if not blockInfo then
        return nil
    end

    local result = BuildCol1DropResult(action, blockInfo.headerIndex, blockInfo.headerRow, {
        folderBlockId = folderId,
        folderBlockFirstRow = blockInfo.firstRow,
        folderBlockLastRow = blockInfo.lastRow,
        folderBlockFirstIndex = blockInfo.firstIndex,
        folderBlockLastIndex = blockInfo.lastIndex,
        folderBlockPosition = action == "reorder-before" and "before" or "after",
    })
    if not result then
        return nil
    end

    result.anchorFrame = action == "reorder-after" and blockInfo.lastFrame or blockInfo.firstFrame
    if extra then
        for key, value in pairs(extra) do
            result[key] = value
        end
    end
    return result
end

local function FindCol1FolderDropTarget(renderedRows, section, folderId)
    if not folderId then
        return nil
    end

    for _, candidate in ipairs(renderedRows or {}) do
        if candidate.section == section and candidate.kind == "folder" and candidate.id == folderId then
            return BuildCol1FolderBlockDropResult(renderedRows, folderId, "into-folder")
        end
    end

    return nil
end

local function ResolveCol1FolderBlockDropTarget(renderedRows, rowMeta, sourceKind, action, extra)
    local folderId = GetCol1FolderBlockIdForRow(rowMeta, sourceKind)
    if not folderId then
        return nil
    end

    return BuildCol1FolderBlockDropResult(renderedRows, folderId, action or "into-folder", extra)
end

local ResolveCol1FolderBlockBoundaryTarget

local function ResolveCol1FolderBlockHoverTarget(
    renderedRows,
    folderId,
    cursorY,
    sourceKind,
    sourceSection,
    sourceFolderId,
    sourceLoadBucket
)
    local blockInfo = GetCol1FolderBlockInfo(renderedRows, folderId)
    if not blockInfo or not cursorY or cursorY > blockInfo.top or cursorY < blockInfo.bottom then
        return nil
    end

    local topInset = GetCol1FolderBlockEdgeInset(blockInfo.firstFrame)
    if cursorY >= (blockInfo.top - topInset) then
        return ResolveCol1FolderBlockBoundaryTarget(
            renderedRows,
            blockInfo.headerRow,
            sourceKind,
            sourceSection,
            sourceLoadBucket,
            "reorder-before"
        )
    end

    local bottomInset = GetCol1FolderBlockEdgeInset(blockInfo.lastFrame)
    if cursorY <= (blockInfo.bottom + bottomInset) then
        return ResolveCol1FolderBlockBoundaryTarget(
            renderedRows,
            blockInfo.headerRow,
            sourceKind,
            sourceSection,
            sourceLoadBucket,
            "reorder-after"
        )
    end

    if sourceFolderId and sourceFolderId == folderId then
        return nil
    end

    return BuildCol1FolderBlockDropResult(renderedRows, folderId, "into-folder")
end

local function ResolveCol1FolderDragBlockHoverTarget(renderedRows, folderId, cursorY, previousDropTarget)
    local blockInfo = GetCol1FolderBlockInfo(renderedRows, folderId)
    if not blockInfo or not cursorY or cursorY > blockInfo.top or cursorY < blockInfo.bottom then
        return nil
    end

    local mid = (blockInfo.top + blockInfo.bottom) / 2
    local action = cursorY > mid and "reorder-before" or "reorder-after"
    local hysteresis = math.min(18, math.max(8, (blockInfo.top - blockInfo.bottom) * 0.12))
    if previousDropTarget
        and previousDropTarget.folderBlockId == folderId
        and (previousDropTarget.action == "reorder-before" or previousDropTarget.action == "reorder-after")
        and math.abs(cursorY - mid) <= hysteresis
    then
        action = previousDropTarget.action
    end
    return BuildCol1FolderReorderBlockTarget(renderedRows, folderId, action)
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
        elseif rowMeta.loadBucket == "unloaded" and (rowMeta.kind == "folder" or rowMeta.kind == "container") then
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
        elseif rowMeta.loadBucket == "unloaded" and (rowMeta.kind == "folder" or rowMeta.kind == "container") then
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

local function ResolveCol1AuxBlockTarget(renderedRows, rowIndex, rowMeta, sourceKind, sourceSection, sourceFolderId, sourceLoadBucket)
    if not rowMeta then
        return nil
    end
    if sourceLoadBucket == "unloaded" then
        return ResolveCol1UnloadedSectionTarget(renderedRows, rowMeta.section, rowIndex + 1)
    end
    if rowMeta.ownerFolderId
        and (sourceKind == "group" or sourceKind == "folder-group")
    then
        return BuildCol1FolderBlockDropResult(renderedRows, rowMeta.ownerFolderId, "into-folder")
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
            or rowMeta.kind == "folder"
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

ResolveCol1FolderBlockBoundaryTarget = function(renderedRows, rowMeta, sourceKind, sourceSection, sourceLoadBucket, action, extra)
    local folderBlockTarget = ResolveCol1FolderBlockDropTarget(renderedRows, rowMeta, sourceKind, action, extra)
    if not folderBlockTarget then
        return nil
    end

    local targetRow = folderBlockTarget.targetRow
    if not targetRow then
        return folderBlockTarget
    end

    if IsCol1MixedDragSource(sourceLoadBucket) then
        return ResolveCol1MixedSectionTarget(
            renderedRows,
            targetRow,
            folderBlockTarget.rowIndex,
            sourceSection,
            action
        )
    end

    if IsCol1UnloadedDragSource(sourceLoadBucket) then
        if targetRow.loadBucket ~= "unloaded" then
            local startIndex = action == "reorder-after"
                and (folderBlockTarget.folderBlockLastIndex or folderBlockTarget.rowIndex)
                or folderBlockTarget.rowIndex
            return ResolveCol1UnloadedSectionTarget(
                renderedRows,
                targetRow.section,
                startIndex,
                action == "reorder-after"
            )
        end
        return folderBlockTarget
    end

    if targetRow.loadBucket == "unloaded" then
        return FindCol1SectionDividerTarget(renderedRows, targetRow.section)
    end

    return folderBlockTarget
end

local function ResolvePreviousFolderBlockBoundaryTarget(renderedRows, rowIndex, sourceKind, sourceSection, sourceLoadBucket, action, extra)
    local previousRow = rowIndex and renderedRows and renderedRows[rowIndex - 1]
    if not previousRow then
        return nil
    end

    local previousFolderId = GetCol1FolderBlockIdForRow(previousRow, sourceKind)
    if not previousFolderId then
        return nil
    end

    local currentFolderId = GetCol1FolderBlockIdForRow(renderedRows[rowIndex], sourceKind)
    if currentFolderId and currentFolderId == previousFolderId then
        return nil
    end

    return ResolveCol1FolderBlockBoundaryTarget(
        renderedRows,
        previousRow,
        sourceKind,
        sourceSection,
        sourceLoadBucket,
        action,
        extra
    )
end

local function GetCol1DropTarget(cursorX, cursorY, scrollWidget, renderedRows, sourceKind, sourceSection, sourceFolderId, sourceLoadBucket, previousDropTarget)
    if not renderedRows or #renderedRows == 0 then return nil end
    local sourceIsMixed = IsCol1MixedDragSource(sourceLoadBucket)
    local sourceIsUnloaded = IsCol1UnloadedDragSource(sourceLoadBucket)
    local contentLeft, contentRight = GetCol1HorizontalBounds(scrollWidget, renderedRows)
    if not IsCursorWithinHorizontalBounds(cursorX, contentLeft, contentRight, COL1_HIT_X_PAD) then
        return nil
    end

    if sourceKind == "group" or sourceKind == "folder-group" then
        local seenFolderBlocks = {}
        for _, rowMeta in ipairs(renderedRows) do
            local folderId = GetCol1FolderBlockIdForRow(rowMeta, sourceKind)
            if folderId and not seenFolderBlocks[folderId] then
                seenFolderBlocks[folderId] = true
                local folderBlockTarget = ResolveCol1FolderBlockHoverTarget(
                    renderedRows,
                    folderId,
                    cursorY,
                    sourceKind,
                    sourceSection,
                    sourceFolderId,
                    sourceLoadBucket
                )
                if folderBlockTarget then
                    return folderBlockTarget
                end
            end
        end
    elseif sourceKind == "folder" then
        local seenFolderBlocks = {}
        for _, rowMeta in ipairs(renderedRows) do
            if rowMeta.kind == "folder" and rowMeta.id and not seenFolderBlocks[rowMeta.id] then
                seenFolderBlocks[rowMeta.id] = true
                local folderBlockTarget = ResolveCol1FolderDragBlockHoverTarget(
                    renderedRows,
                    rowMeta.id,
                    cursorY,
                    previousDropTarget
                )
                if folderBlockTarget then
                    return folderBlockTarget
                end
            end
        end
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
                if rowMeta.kind == "folder" and (sourceKind == "group" or sourceKind == "folder-group") then
                    return BuildCol1FolderBlockDropResult(renderedRows, rowMeta.id, "into-folder")
                elseif IsExternalFolderChildTarget(rowMeta, sourceKind, sourceFolderId) then
                    return ResolveCol1FolderBlockDropTarget(renderedRows, rowMeta, sourceKind, "into-folder")
                elseif rowMeta.kind == "aux-block" then
                    return ResolveCol1AuxBlockTarget(renderedRows, i, rowMeta, sourceKind, sourceSection, sourceFolderId, sourceLoadBucket)
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
                    local previousFolderTarget = ResolvePreviousFolderBlockBoundaryTarget(
                        renderedRows,
                        i,
                        sourceKind,
                        sourceSection,
                        sourceLoadBucket,
                        "reorder-after"
                    )
                    if previousFolderTarget then
                        return previousFolderTarget
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
                    local previousFolderTarget = ResolvePreviousFolderBlockBoundaryTarget(
                        renderedRows,
                        i,
                        sourceKind,
                        sourceSection,
                        sourceLoadBucket,
                        "reorder-after"
                    )
                    if previousFolderTarget then
                        return previousFolderTarget
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
                local folderBoundaryTarget = ResolveCol1FolderBlockBoundaryTarget(
                    renderedRows,
                    rowMeta,
                    sourceKind,
                    sourceSection,
                    sourceLoadBucket,
                    "reorder-before"
                )
                if folderBoundaryTarget then
                    return folderBoundaryTarget
                elseif rowMeta.kind == "section-header" then
                    if sourceIsMixed then
                        return ResolveCol1MixedSectionTarget(renderedRows, rowMeta, i + 1, sourceSection, "reorder-before")
                    end
                    if sourceIsUnloaded then
                        return ResolveCol1UnloadedSectionTarget(renderedRows, rowMeta.section, i + 1)
                    end
                    return FindFirstCol1DropTargetInSection(renderedRows, rowMeta.section, i + 1)
                elseif IsExternalFolderChildTarget(rowMeta, sourceKind, sourceFolderId) then
                    return ResolveCol1FolderBlockBoundaryTarget(
                        renderedRows,
                        rowMeta,
                        sourceKind,
                        sourceSection,
                        sourceLoadBucket,
                        "reorder-before"
                    )
                elseif rowMeta.kind == "aux-block" then
                    return ResolveCol1AuxBlockTarget(renderedRows, i, rowMeta, sourceKind, sourceSection, sourceFolderId, sourceLoadBucket)
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
            local folderBoundaryTarget = ResolveCol1FolderBlockBoundaryTarget(
                renderedRows,
                rowMeta,
                sourceKind,
                sourceSection,
                sourceLoadBucket,
                "reorder-after",
                { isBelowAll = true }
            )
            if folderBoundaryTarget then
                return folderBoundaryTarget
            elseif rowMeta.kind == "unloaded-divider" or rowMeta.loadBucket == "unloaded" then
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

IsUnloadedTopLevelDrop = function(state, dropTarget, targetFolderId)
    if targetFolderId then
        return false
    end
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
    if row.kind ~= "folder" and not (row.kind == "container" and not row.inFolder) then
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
        if item.kind == "folder" and db.folders[item.id] then
            CooldownCompanion:SetOrderForSpec(db.folders[item.id], specId, nextOrder)
            nextOrder = nextOrder + 1
        elseif db.groupContainers[item.id] then
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

-- Show drag indicator for "into-folder" drops (highlight overlay on folder row)
local function ShowFolderDropOverlay(dropTarget, parentScrollWidget)
    HideDragIndicator()
end

-- Reset drag indicator to default line style
local function ResetDragIndicatorStyle()
    if CS.dragIndicator and CS.dragIndicator.tex then
        CS.dragIndicator:SetHeight(2)
        CS.dragIndicator.tex:SetColorTexture(0.2, 0.6, 1.0, 1.0)
    end
end

DR.GetDragIndicator = GetDragIndicator
DR.HideDragIndicator = HideDragIndicator
DR.GetScaledCursorCoordinates = GetScaledCursorCoordinates
DR.GetScaledCursorPosition = GetScaledCursorPosition
DR.GetRawCursorCoordinates = GetRawCursorCoordinates
DR.GetDropIndex = GetDropIndex
DR.GetCol2DropTarget = GetCol2DropTarget
DR.ShowDragIndicator = ShowDragIndicator
DR.GetCol2CompactPanelDropTarget = GetCol2CompactPanelDropTarget
DR.GetCol2PanelDropTarget = GetCol2PanelDropTarget
DR.PerformPanelReorder = PerformPanelReorder
DR.IsPanelReorderNoOp = IsPanelReorderNoOp
DR.PerformGroupReorder = PerformGroupReorder
DR.GetCol1DropTarget = GetCol1DropTarget
DR.ShowFolderDropOverlay = ShowFolderDropOverlay
DR.ResetDragIndicatorStyle = ResetDragIndicatorStyle
DR.ResolveCol1GroupDropTargetFolderId = ResolveCol1GroupDropTargetFolderId
DR.IsCol1GroupDropNoOp = IsCol1GroupDropNoOp
DR.IsCol1FolderDropNoOp = IsCol1FolderDropNoOp
DR.IsUnloadedTopLevelDrop = IsUnloadedTopLevelDrop
DR.ShouldIncludeCol1TopLevelOrderRow = ShouldIncludeCol1TopLevelOrderRow
DR.FindCol1SectionDividerTarget = FindCol1SectionDividerTarget
DR.FindCol1FolderBlockRange = FindCol1FolderBlockRange
DR.IsExternalFolderChildTarget = IsExternalFolderChildTarget
DR.IsCol1MixedDragSource = IsCol1MixedDragSource
DR.FindCol1TopLevelInsertPos = FindCol1TopLevelInsertPos
DR.AssignCol1TopLevelOrders = AssignCol1TopLevelOrders
DR.PartitionSelectedContainersByLoadBucket = PartitionSelectedContainersByLoadBucket
DR.ResolveCol1FolderBlockBoundaryTarget = ResolveCol1FolderBlockBoundaryTarget
