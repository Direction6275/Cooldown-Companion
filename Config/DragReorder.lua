--[[
    CooldownCompanion - Config/DragReorder
    Full drag-and-drop reordering system for groups and buttons.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local ShowPopupAboveConfig = ST._ShowPopupAboveConfig

-- File-local constants
local DRAG_THRESHOLD = 8

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

local function GetScaledCursorPosition(scrollWidget)
    local _, cursorY = GetCursorPosition()
    local scale = scrollWidget.frame:GetEffectiveScale()
    cursorY = cursorY / scale
    return cursorY
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
    local width = parentScrollWidget.content:GetWidth() or 100
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
        db.groups[gid].order = i
    end
end

------------------------------------------------------------------------
-- Drop target detection for column 1 with folder support
------------------------------------------------------------------------
local function GetCol1DropTarget(cursorY, renderedRows, sourceKind, sourceSection)
    if not renderedRows or #renderedRows == 0 then return nil end

    for i, rowMeta in ipairs(renderedRows) do
        local frame = rowMeta.widget and rowMeta.widget.frame
        if frame and frame:IsShown() then
            local top = frame:GetTop()
            local bottom = frame:GetBottom()
            if top and bottom and cursorY <= top and cursorY >= bottom then
                local height = top - bottom
                -- If hovering over a folder header and dragging a group, use 3-zone detection
                if rowMeta.kind == "folder" and (sourceKind == "group" or sourceKind == "folder-group") then
                    local topZone = top - height * 0.25
                    local bottomZone = bottom + height * 0.25
                    if cursorY > topZone then
                        return { action = "reorder-before", rowIndex = i, targetRow = rowMeta, anchorFrame = frame }
                    elseif cursorY < bottomZone then
                        return { action = "reorder-after", rowIndex = i, targetRow = rowMeta, anchorFrame = frame }
                    else
                        return { action = "into-folder", rowIndex = i, targetRow = rowMeta, anchorFrame = frame, targetFolderId = rowMeta.id }
                    end
                else
                    -- Standard 2-zone (above/below midpoint)
                    local mid = (top + bottom) / 2
                    if cursorY > mid then
                        return { action = "reorder-before", rowIndex = i, targetRow = rowMeta, anchorFrame = frame }
                    else
                        return { action = "reorder-after", rowIndex = i, targetRow = rowMeta, anchorFrame = frame }
                    end
                end
            end
        end
    end

    -- Cursor is in a gap between rows (e.g. between sections): find the first
    -- row whose top edge is below the cursor and target it with reorder-before.
    for i, rowMeta in ipairs(renderedRows) do
        local frame = rowMeta.widget and rowMeta.widget.frame
        if frame and frame:IsShown() then
            local top = frame:GetTop()
            if top and cursorY > top then
                return { action = "reorder-before", rowIndex = i, targetRow = rowMeta, anchorFrame = frame }
            end
        end
    end

    -- Below all rows: drop after the last row overall.
    local lastRow = renderedRows[#renderedRows]
    local lastRowIndex = #renderedRows
    local lastFrame = lastRow and lastRow.widget and lastRow.widget.frame
    if lastFrame and lastFrame:IsShown() then
        return { action = "reorder-after", rowIndex = lastRowIndex, targetRow = lastRow, anchorFrame = lastFrame, isBelowAll = true }
    end
    return nil
end

-- Show drag indicator for "into-folder" drops (highlight overlay on folder row)
local function ShowFolderDropOverlay(anchorFrame, parentScrollWidget)
    local ind = GetDragIndicator()
    local width = parentScrollWidget.content:GetWidth() or 100
    ind:SetWidth(width)
    ind:SetHeight(anchorFrame:GetHeight() or 24)
    ind:ClearAllPoints()
    ind:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", 0, 0)
    ind.tex:SetColorTexture(0.4, 0.7, 0.2, 0.3)
    ind:Show()
end

-- Reset drag indicator to default line style
local function ResetDragIndicatorStyle()
    if CS.dragIndicator and CS.dragIndicator.tex then
        CS.dragIndicator:SetHeight(2)
        CS.dragIndicator.tex:SetColorTexture(0.2, 0.6, 1.0, 1.0)
    end
end

------------------------------------------------------------------------
-- Apply a column-1 folder-aware drop result
------------------------------------------------------------------------
local function ApplyCol1Drop(state)
    local dropTarget = state.dropTarget
    if not dropTarget then return end

    local db = CooldownCompanion.db.profile

    if state.kind == "group" or state.kind == "folder-group" then
        local sourceGroupId = state.sourceGroupId
        local group = db.groups[sourceGroupId]
        if not group then return end

        if dropTarget.action == "into-folder" then
            -- Move group into the target folder
            group.folderId = dropTarget.targetFolderId
        elseif dropTarget.action == "reorder-before" or dropTarget.action == "reorder-after" then
            local targetRow = dropTarget.targetRow
            if dropTarget.isBelowAll then
                -- Dropped below all rows: always become top-level
                group.folderId = nil
            elseif targetRow.kind == "group" and targetRow.inFolder then
                -- If dropping on a row that's in a folder, join that folder
                group.folderId = targetRow.inFolder
            elseif targetRow.kind == "folder" then
                -- Dropping before/after a folder header = top-level
                group.folderId = nil
            elseif targetRow.kind == "phantom" then
                -- Dropping on phantom section placeholder = top-level in that section
                group.folderId = nil
            else
                -- Dropping on a loose group = stay/become loose
                group.folderId = nil
            end

            -- Cross-section move: toggle global/character status
            local targetSection = targetRow.section or state.sourceSection
            if targetSection ~= state.sourceSection then
                if targetSection == "global" then
                    group.isGlobal = true
                else
                    group.isGlobal = false
                    group.createdBy = CooldownCompanion.db.keys.char
                end
            end

            -- Reassign order values for all items in the target section
            -- to place the dragged group at the right position
            local section = targetSection
            local renderedRows = state.col1RenderedRows
            if renderedRows then
                -- Build ordered list of items in the same container (folder or top-level)
                -- and reassign order values
                local targetFolderId = group.folderId
                local orderItems = {}
                for _, row in ipairs(renderedRows) do
                    if row.section == section then
                        if targetFolderId then
                            -- Ordering within a folder: collect groups in same folder
                            if row.kind == "group" and row.inFolder == targetFolderId and row.id ~= sourceGroupId then
                                table.insert(orderItems, row.id)
                            end
                        else
                            -- Top-level ordering: collect top-level items (folders + loose groups)
                            if (row.kind == "folder") or (row.kind == "group" and not row.inFolder) then
                                if row.id ~= sourceGroupId then
                                    table.insert(orderItems, { kind = row.kind, id = row.id })
                                end
                            end
                        end
                    end
                end

                -- Find insertion position
                local insertPos
                if targetFolderId then
                    -- Within folder: find target group position
                    insertPos = #orderItems + 1
                    for idx, gid in ipairs(orderItems) do
                        if gid == dropTarget.targetRow.id then
                            insertPos = dropTarget.action == "reorder-after" and idx + 1 or idx
                            break
                        end
                    end
                    table.insert(orderItems, insertPos, sourceGroupId)
                    for i, gid in ipairs(orderItems) do
                        db.groups[gid].order = i
                    end
                else
                    -- Top-level: find target position among mixed items
                    insertPos = #orderItems + 1
                    for idx, item in ipairs(orderItems) do
                        if item.kind == dropTarget.targetRow.kind and item.id == dropTarget.targetRow.id then
                            insertPos = dropTarget.action == "reorder-after" and idx + 1 or idx
                            break
                        end
                    end
                    table.insert(orderItems, insertPos, { kind = "group", id = sourceGroupId })
                    for i, item in ipairs(orderItems) do
                        if item.kind == "folder" then
                            db.folders[item.id].order = i
                        else
                            db.groups[item.id].order = i
                        end
                    end
                end
            end
        end
    elseif state.kind == "multi-group" then
        local sourceGroupIds = state.sourceGroupIds
        if not sourceGroupIds then return end

        local targetRow = dropTarget.targetRow
        -- Determine target folder and section
        local targetFolderId = nil
        if dropTarget.action == "into-folder" then
            targetFolderId = dropTarget.targetFolderId
        elseif dropTarget.action == "reorder-before" or dropTarget.action == "reorder-after" then
            if dropTarget.isBelowAll then
                targetFolderId = nil
            elseif targetRow.kind == "group" and targetRow.inFolder then
                targetFolderId = targetRow.inFolder
            else
                targetFolderId = nil
            end
        end

        local targetSection = targetRow.section or state.sourceSection

        -- Set folder and cross-section toggle for each selected group
        for gid in pairs(sourceGroupIds) do
            local g = db.groups[gid]
            if g then
                g.folderId = targetFolderId
                local groupSection = g.isGlobal and "global" or "char"
                if groupSection ~= targetSection then
                    if targetSection == "global" then
                        g.isGlobal = true
                    else
                        g.isGlobal = false
                        g.createdBy = CooldownCompanion.db.keys.char
                    end
                end
            end
        end

        -- Sort selected groups by current order to preserve relative ordering
        local sortedSelected = {}
        for gid in pairs(sourceGroupIds) do
            local g = db.groups[gid]
            if g then
                table.insert(sortedSelected, { id = gid, order = g.order or gid })
            end
        end
        table.sort(sortedSelected, function(a, b) return a.order < b.order end)

        -- Rebuild order for target container
        local renderedRows = state.col1RenderedRows
        if renderedRows then
            if targetFolderId then
                -- Ordering within a folder
                local orderItems = {}
                for _, row in ipairs(renderedRows) do
                    if row.kind == "group" and row.inFolder == targetFolderId and not sourceGroupIds[row.id] then
                        table.insert(orderItems, row.id)
                    end
                end

                -- Find insertion position
                local insertPos = #orderItems + 1
                for idx, gid in ipairs(orderItems) do
                    if gid == targetRow.id then
                        insertPos = dropTarget.action == "reorder-after" and idx + 1 or idx
                        break
                    end
                end
                -- Insert all selected groups at the position, preserving relative order
                for i, item in ipairs(sortedSelected) do
                    table.insert(orderItems, insertPos + i - 1, item.id)
                end
                for i, gid in ipairs(orderItems) do
                    db.groups[gid].order = i
                end
            else
                -- Top-level ordering
                local orderItems = {}
                for _, row in ipairs(renderedRows) do
                    if row.section == targetSection then
                        if (row.kind == "folder") or (row.kind == "group" and not row.inFolder) then
                            if not sourceGroupIds[row.id] then
                                table.insert(orderItems, { kind = row.kind, id = row.id })
                            end
                        end
                    end
                end

                local insertPos = #orderItems + 1
                for idx, item in ipairs(orderItems) do
                    if item.kind == targetRow.kind and item.id == targetRow.id then
                        insertPos = dropTarget.action == "reorder-after" and idx + 1 or idx
                        break
                    end
                end
                -- Insert all selected groups at the position
                for i, item in ipairs(sortedSelected) do
                    table.insert(orderItems, insertPos + i - 1, { kind = "group", id = item.id })
                end
                for i, item in ipairs(orderItems) do
                    if item.kind == "folder" then
                        db.folders[item.id].order = i
                    else
                        db.groups[item.id].order = i
                    end
                end
            end
        end
    elseif state.kind == "folder" then
        local sourceFolderId = state.sourceFolderId
        local folder = db.folders[sourceFolderId]
        if not folder then return end

        local dropTarget = state.dropTarget
        local targetRow = dropTarget.targetRow
        local section = targetRow.section or state.sourceSection

        -- Cross-section move: toggle folder section and update all child groups
        if section ~= state.sourceSection then
            folder.section = section
            if section == "char" then
                folder.createdBy = CooldownCompanion.db.keys.char
            end
            for groupId, group in pairs(db.groups) do
                if group.folderId == sourceFolderId then
                    if section == "global" then
                        group.isGlobal = true
                    else
                        group.isGlobal = false
                        group.createdBy = CooldownCompanion.db.keys.char
                    end
                end
            end
        end

        -- Build top-level items for the section (excluding the source folder)
        local renderedRows = state.col1RenderedRows
        if renderedRows then
            local orderItems = {}
            for _, row in ipairs(renderedRows) do
                if row.section == section then
                    if (row.kind == "folder" or (row.kind == "group" and not row.inFolder)) and row.id ~= sourceFolderId then
                        table.insert(orderItems, { kind = row.kind, id = row.id })
                    end
                end
            end

            local insertPos = #orderItems + 1
            for idx, item in ipairs(orderItems) do
                local targetKind = targetRow.kind
                local targetId = targetRow.id
                -- If target is a group inside a folder, use the folder as anchor
                if targetRow.inFolder then
                    targetKind = "folder"
                    targetId = targetRow.inFolder
                end
                if item.kind == targetKind and item.id == targetId then
                    insertPos = dropTarget.action == "reorder-after" and idx + 1 or idx
                    break
                end
            end
            table.insert(orderItems, insertPos, { kind = "folder", id = sourceFolderId })
            for i, item in ipairs(orderItems) do
                if item.kind == "folder" then
                    db.folders[item.id].order = i
                else
                    db.groups[item.id].order = i
                end
            end
        end
    end

    -- Group order may have changed — re-evaluate auto-anchored bars
    CooldownCompanion:EvaluateResourceBars()
    CooldownCompanion:UpdateAnchorStacking()
    CooldownCompanion:EvaluateCastBar()
end

------------------------------------------------------------------------
-- Button reorder
------------------------------------------------------------------------
local function PerformButtonReorder(groupId, sourceIndex, dropIndex)
    if dropIndex > sourceIndex then dropIndex = dropIndex - 1 end
    if sourceIndex == dropIndex then return end
    local group = CooldownCompanion.db.profile.groups[groupId]
    if not group then return end
    local entry = table.remove(group.buttons, sourceIndex)
    table.insert(group.buttons, dropIndex, entry)
    -- Track selectedButton
    if CS.selectedButton == sourceIndex then
        CS.selectedButton = dropIndex
    elseif CS.selectedButton then
        -- Adjust if the move shifted the selected index
        if sourceIndex < CS.selectedButton and dropIndex >= CS.selectedButton then
            CS.selectedButton = CS.selectedButton - 1
        elseif sourceIndex > CS.selectedButton and dropIndex <= CS.selectedButton then
            CS.selectedButton = CS.selectedButton + 1
        end
    end
end

------------------------------------------------------------------------
-- Drag lifecycle
------------------------------------------------------------------------
local function CancelDrag()
    if CS.dragState then
        if CS.dragState.dimmedWidgets then
            for _, w in ipairs(CS.dragState.dimmedWidgets) do
                w.frame:SetAlpha(1)
            end
        elseif CS.dragState.widget then
            CS.dragState.widget.frame:SetAlpha(1)
        end
    end
    CS.dragState = nil
    HideDragIndicator()
    ResetDragIndicatorStyle()
    if CS.dragTracker then
        CS.dragTracker:SetScript("OnUpdate", nil)
    end
    if CS.showPhantomSections then
        CS.showPhantomSections = false
        C_Timer.After(0, function()
            CooldownCompanion:RefreshConfigPanel()
        end)
    end
end

local function FinishDrag()
    if not CS.dragState or CS.dragState.phase ~= "active" then
        CancelDrag()
        return
    end
    local state = CS.dragState
    CS.showPhantomSections = false  -- clear before CancelDrag to avoid redundant deferred refresh
    CancelDrag()
    ResetDragIndicatorStyle()
    if state.kind == "group" and state.groupIds then
        -- Legacy flat reorder (column 2 button drags still use this path)
        PerformGroupReorder(state.sourceIndex, state.dropIndex or state.sourceIndex, state.groupIds)
        CooldownCompanion:EvaluateResourceBars()
        CooldownCompanion:UpdateAnchorStacking()
        CooldownCompanion:EvaluateCastBar()
        CooldownCompanion:RefreshConfigPanel()
    elseif state.kind == "group" or state.kind == "folder" or state.kind == "folder-group" or state.kind == "multi-group" then
        -- Column 1 folder-aware drop
        -- Check for cross-section global→char with foreign specs
        local dropTarget = state.dropTarget
        if dropTarget and (state.kind == "group" or state.kind == "folder-group") then
            local targetSection = dropTarget.targetRow and dropTarget.targetRow.section
            local sourceGroup = CooldownCompanion.db.profile.groups[state.sourceGroupId]
            if targetSection and targetSection ~= state.sourceSection
               and state.sourceSection == "global"
               and sourceGroup and sourceGroup.specs then
                local hasForeign = false
                local numSpecs = GetNumSpecializations()
                local playerSpecIds = {}
                for i = 1, numSpecs do
                    local specId = C_SpecializationInfo.GetSpecializationInfo(i)
                    if specId then playerSpecIds[specId] = true end
                end
                for specId in pairs(sourceGroup.specs) do
                    if not playerSpecIds[specId] then
                        hasForeign = true
                        break
                    end
                end
                if hasForeign then
                    ShowPopupAboveConfig("CDC_DRAG_UNGLOBAL_GROUP", sourceGroup.name, {
                        dragState = state,
                    })
                    return
                end
            end
        end
        -- Check for cross-section global→char with foreign specs (multi-group)
        if dropTarget and state.kind == "multi-group" and state.sourceGroupIds then
            local targetSection = dropTarget.targetRow and dropTarget.targetRow.section
            if targetSection then
                local hasForeign = false
                local numSpecs = GetNumSpecializations()
                local playerSpecIds = {}
                for i = 1, numSpecs do
                    local specId = C_SpecializationInfo.GetSpecializationInfo(i)
                    if specId then playerSpecIds[specId] = true end
                end
                local db = CooldownCompanion.db.profile
                for gid in pairs(state.sourceGroupIds) do
                    local g = db.groups[gid]
                    if g and g.isGlobal and targetSection == "char" and g.specs then
                        for specId in pairs(g.specs) do
                            if not playerSpecIds[specId] then
                                hasForeign = true
                                break
                            end
                        end
                        if hasForeign then break end
                    end
                end
                if hasForeign then
                    ShowPopupAboveConfig("CDC_UNGLOBAL_SELECTED_GROUPS", nil, {
                        groupIds = (function()
                            local ids = {}
                            for gid in pairs(state.sourceGroupIds) do table.insert(ids, gid) end
                            return ids
                        end)(),
                        callback = function()
                            ApplyCol1Drop(state)
                            CooldownCompanion:RefreshConfigPanel()
                        end,
                    })
                    return
                end
            end
        end
        -- Check for cross-section global→char with foreign specs in folder children
        if dropTarget and state.kind == "folder" then
            local targetSection = dropTarget.targetRow and dropTarget.targetRow.section
            if targetSection and targetSection ~= state.sourceSection
               and state.sourceSection == "global" then
                local hasForeign = false
                local numSpecs = GetNumSpecializations()
                local playerSpecIds = {}
                for i = 1, numSpecs do
                    local specId = C_SpecializationInfo.GetSpecializationInfo(i)
                    if specId then playerSpecIds[specId] = true end
                end
                for groupId, group in pairs(CooldownCompanion.db.profile.groups) do
                    if group.folderId == state.sourceFolderId and group.specs then
                        for specId in pairs(group.specs) do
                            if not playerSpecIds[specId] then
                                hasForeign = true
                                break
                            end
                        end
                        if hasForeign then break end
                    end
                end
                if hasForeign then
                    ShowPopupAboveConfig("CDC_DRAG_UNGLOBAL_FOLDER", nil, {
                        dragState = state,
                    })
                    return
                end
            end
        end
        ApplyCol1Drop(state)
        CooldownCompanion:RefreshConfigPanel()
    elseif state.kind == "button" then
        PerformButtonReorder(state.groupId, state.sourceIndex, state.dropIndex or state.sourceIndex)
        CooldownCompanion:RefreshGroupFrame(state.groupId)
        CooldownCompanion:RefreshConfigPanel()
    end
end

local function StartDragTracking()
    if not CS.dragTracker then
        CS.dragTracker = CreateFrame("Frame", nil, UIParent)
    end
    CS.dragTracker:SetScript("OnUpdate", function()
        if not CS.dragState then
            CS.dragTracker:SetScript("OnUpdate", nil)
            return
        end
        if not IsMouseButtonDown("LeftButton") then
            -- Mouse released
            if CS.dragState.phase == "active" then
                FinishDrag()
            else
                -- Was just a click, not a drag — clear state
                CancelDrag()
            end
            return
        end
        local cursorY = GetScaledCursorPosition(CS.dragState.scrollWidget)
        if CS.dragState.phase == "pending" then
            if math.abs(cursorY - CS.dragState.startY) > DRAG_THRESHOLD then
                CS.dragState.phase = "active"
                -- Dim source widget(s)
                if CS.dragState.kind == "multi-group" and CS.dragState.sourceGroupIds then
                    CS.dragState.dimmedWidgets = {}
                    for _, row in ipairs(CS.dragState.col1RenderedRows) do
                        if row.kind == "group" and CS.dragState.sourceGroupIds[row.id] then
                            row.widget.frame:SetAlpha(0.4)
                            table.insert(CS.dragState.dimmedWidgets, row.widget)
                        end
                    end
                elseif CS.dragState.widget then
                    CS.dragState.widget.frame:SetAlpha(0.4)
                end
                -- Check if we need phantom sections for cross-section drops
                if CS.dragState.col1RenderedRows and not CS.showPhantomSections then
                    local hasGlobal, hasChar = false, false
                    for _, row in ipairs(CS.dragState.col1RenderedRows) do
                        if row.section == "global" then hasGlobal = true end
                        if row.section == "char" then hasChar = true end
                    end
                    if not hasGlobal or not hasChar then
                        -- Save drag metadata before rebuild
                        local savedKind = CS.dragState.kind
                        local savedSourceGroupId = CS.dragState.sourceGroupId
                        local savedSourceGroupIds = CS.dragState.sourceGroupIds
                        local savedSourceFolderId = CS.dragState.sourceFolderId
                        local savedSourceSection = CS.dragState.sourceSection
                        local savedScrollWidget = CS.dragState.scrollWidget
                        local savedStartY = CS.dragState.startY
                        CS.showPhantomSections = true
                        ST._RefreshColumn1(true)
                        -- Reconstruct drag state with new rendered rows
                        CS.dragState = {
                            kind = savedKind,
                            phase = "active",
                            sourceGroupId = savedSourceGroupId,
                            sourceGroupIds = savedSourceGroupIds,
                            sourceFolderId = savedSourceFolderId,
                            sourceSection = savedSourceSection,
                            scrollWidget = savedScrollWidget,
                            startY = savedStartY,
                            col1RenderedRows = CS.lastCol1RenderedRows,
                        }
                        -- Dim the source widget(s) in the new rows
                        if savedKind == "multi-group" and savedSourceGroupIds then
                            CS.dragState.dimmedWidgets = {}
                            for _, row in ipairs(CS.dragState.col1RenderedRows) do
                                if row.kind == "group" and savedSourceGroupIds[row.id] then
                                    row.widget.frame:SetAlpha(0.4)
                                    table.insert(CS.dragState.dimmedWidgets, row.widget)
                                end
                            end
                        else
                            for _, row in ipairs(CS.dragState.col1RenderedRows) do
                                if savedKind == "folder" and row.kind == "folder" and row.id == savedSourceFolderId then
                                    CS.dragState.widget = row.widget
                                    row.widget.frame:SetAlpha(0.4)
                                    break
                                elseif (savedKind == "group" or savedKind == "folder-group") and row.kind == "group" and row.id == savedSourceGroupId then
                                    CS.dragState.widget = row.widget
                                    row.widget.frame:SetAlpha(0.4)
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
        if CS.dragState.phase == "active" then
            if CS.dragState.col1RenderedRows then
                -- Column 1 folder-aware drop detection
                local effectiveKind = CS.dragState.kind == "multi-group" and "group" or CS.dragState.kind
                local dropTarget = GetCol1DropTarget(cursorY, CS.dragState.col1RenderedRows, effectiveKind, CS.dragState.sourceSection)
                CS.dragState.dropTarget = dropTarget
                if dropTarget then
                    ResetDragIndicatorStyle()
                    if dropTarget.action == "into-folder" then
                        ShowFolderDropOverlay(dropTarget.anchorFrame, CS.dragState.scrollWidget)
                    elseif dropTarget.action == "reorder-before" then
                        ShowDragIndicator(dropTarget.anchorFrame, true, CS.dragState.scrollWidget)
                    else
                        ShowDragIndicator(dropTarget.anchorFrame, false, CS.dragState.scrollWidget)
                    end
                else
                    HideDragIndicator()
                end
            else
                local dropIndex, anchorFrame, anchorAbove = GetDropIndex(
                    CS.dragState.scrollWidget, cursorY,
                    CS.dragState.childOffset or 0,
                    CS.dragState.totalDraggable
                )
                CS.dragState.dropIndex = dropIndex
                ShowDragIndicator(anchorFrame, anchorAbove, CS.dragState.scrollWidget)
            end
        end
    end)
end

------------------------------------------------------------------------
-- ST._ exports (consumed by later Config/ files)
------------------------------------------------------------------------
ST._CancelDrag = CancelDrag
ST._StartDragTracking = StartDragTracking
ST._FinishDrag = FinishDrag
ST._ApplyCol1Drop = ApplyCol1Drop
ST._PerformButtonReorder = PerformButtonReorder
ST._PerformGroupReorder = PerformGroupReorder
ST._GetDragIndicator = GetDragIndicator
ST._HideDragIndicator = HideDragIndicator
ST._GetScaledCursorPosition = GetScaledCursorPosition
ST._GetDropIndex = GetDropIndex
ST._ShowDragIndicator = ShowDragIndicator
ST._GetCol1DropTarget = GetCol1DropTarget
ST._ShowFolderDropOverlay = ShowFolderDropOverlay
ST._ResetDragIndicatorStyle = ResetDragIndicatorStyle
