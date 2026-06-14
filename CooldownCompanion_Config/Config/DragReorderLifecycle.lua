--[[
    CooldownCompanion - Config/DragReorderLifecycle
    Drag lifecycle, drop application, and public drag exports.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState
local DR = ST._DragReorder or {}
ST._DragReorder = DR

local ShowPopupAboveConfig = ST._ShowPopupAboveConfig
local GroupsHaveForeignSpecs = ST._GroupsHaveForeignSpecs
local FolderHasForeignSpecs = ST._FolderHasForeignSpecs
local SelectConfigPanel = ST._SelectConfigPanel
local ClearConfigButtonSelection = ST._ClearConfigButtonSelection

local DRAG_THRESHOLD = 8
local PREVIEW_MODE_PANEL_COMPACT = DR.PREVIEW_MODE_PANEL_COMPACT

local GetRawCursorCoordinates = DR.GetRawCursorCoordinates
local GetScaledCursorCoordinates = DR.GetScaledCursorCoordinates
local GetScaledCursorPosition = DR.GetScaledCursorPosition
local GetDragIndicator = DR.GetDragIndicator
local GetDropIndex = DR.GetDropIndex
local HideDragIndicator = DR.HideDragIndicator
local ShowDragIndicator = DR.ShowDragIndicator
local ShowFolderDropOverlay = DR.ShowFolderDropOverlay
local ResetDragIndicatorStyle = DR.ResetDragIndicatorStyle
local ClearCol1AnimatedPreview = DR.ClearCol1AnimatedPreview
local ClearCol2AnimatedPreview = DR.ClearCol2AnimatedPreview
local RenderCol1AnimatedPreview = DR.RenderCol1AnimatedPreview
local RenderCol2AnimatedPreview = DR.RenderCol2AnimatedPreview
local UpdateCol2CursorPreview = DR.UpdateCol2CursorPreview
local SetDraggedFolderAccentBarHidden = DR.SetDraggedFolderAccentBarHidden
local ShouldAnimateCol1PreviewForDrop = DR.ShouldAnimateCol1PreviewForDrop
local ShouldShowCol1StaticReorderIndicator = DR.ShouldShowCol1StaticReorderIndicator
local ResolveCol1LoadedUnloadedPlaceholderTarget = DR.ResolveCol1LoadedUnloadedPlaceholderTarget
local GetCol1DropTarget = DR.GetCol1DropTarget
local GetCol2DropTarget = DR.GetCol2DropTarget
local GetCol2CompactPanelDropTarget = DR.GetCol2CompactPanelDropTarget
local GetCol2PanelDropTarget = DR.GetCol2PanelDropTarget
local PerformPanelReorder = DR.PerformPanelReorder
local IsPanelReorderNoOp = DR.IsPanelReorderNoOp
local PerformGroupReorder = DR.PerformGroupReorder
local ResolveCol1GroupDropTargetFolderId = DR.ResolveCol1GroupDropTargetFolderId
local IsCol1GroupDropNoOp = DR.IsCol1GroupDropNoOp
local IsCol1FolderDropNoOp = DR.IsCol1FolderDropNoOp
local IsUnloadedTopLevelDrop = DR.IsUnloadedTopLevelDrop
local IsCol1MixedDragSource = DR.IsCol1MixedDragSource
local ShouldIncludeCol1TopLevelOrderRow = DR.ShouldIncludeCol1TopLevelOrderRow
local FindCol1TopLevelInsertPos = DR.FindCol1TopLevelInsertPos
local AssignCol1TopLevelOrders = DR.AssignCol1TopLevelOrders
local PartitionSelectedContainersByLoadBucket = DR.PartitionSelectedContainersByLoadBucket

------------------------------------------------------------------------
-- Apply a column-1 folder-aware drop result
------------------------------------------------------------------------
local function ApplyCol1Drop(state)
    local dropTarget = state.dropTarget
    if not dropTarget then return end

    local db = CooldownCompanion.db.profile

    if state.kind == "group" or state.kind == "folder-group" then
        -- Column 1 rows are containers now (sourceGroupId holds a containerId)
        local sourceContainerId = state.sourceGroupId
        local container = db.groupContainers[sourceContainerId]
        if not container then return end

        if dropTarget.action == "into-folder" or dropTarget.action == "reorder-before" or dropTarget.action == "reorder-after" then
            local targetRow = dropTarget.targetRow
            local targetFolderId = ResolveCol1GroupDropTargetFolderId(state, dropTarget)
            CooldownCompanion:MoveGroupToFolder(sourceContainerId, targetFolderId)

            -- Cross-section move: toggle global/character status
            local targetSection = targetRow.section or state.sourceSection
            if targetSection ~= state.sourceSection then
                if targetSection == "global" then
                    container.isGlobal = true
                else
                    container.isGlobal = false
                    container.createdBy = CooldownCompanion.db.keys.char
                end
            end

            -- Reassign order values for all items in the target section
            -- to place the dragged container at the right position
            local section = targetSection
            local renderedRows = state.col1RenderedRows
            if renderedRows then
                -- Build ordered list of items in the same parent (folder or top-level)
                -- and reassign order values
                targetFolderId = container.folderId
                local includeUnloaded = IsUnloadedTopLevelDrop(state, dropTarget, targetFolderId)
                local orderItems = {}
                for _, row in ipairs(renderedRows) do
                    if row.section == section then
                        if targetFolderId then
                            -- Ordering within a folder: collect containers in same folder
                            if row.kind == "container" and row.inFolder == targetFolderId and row.id ~= sourceContainerId then
                                table.insert(orderItems, row.id)
                            end
                        else
                            -- Top-level ordering: collect top-level items (folders + loose containers)
                            if ShouldIncludeCol1TopLevelOrderRow(row, includeUnloaded) then
                                if row.id ~= sourceContainerId then
                                    table.insert(orderItems, { kind = row.kind, id = row.id })
                                end
                            end
                        end
                    end
                end

                -- Find insertion position
                local insertPos
                if targetFolderId then
                    -- Within folder: find target container position
                    insertPos = #orderItems + 1
                    for idx, cid in ipairs(orderItems) do
                        if cid == dropTarget.targetRow.id then
                            insertPos = dropTarget.action == "reorder-after" and idx + 1 or idx
                            break
                        end
                    end
                    table.insert(orderItems, insertPos, sourceContainerId)
                    local specId = CooldownCompanion._currentSpecId
                    for i, cid in ipairs(orderItems) do
                        if db.groupContainers[cid] then
                            CooldownCompanion:SetOrderForSpec(db.groupContainers[cid], specId, i)
                        end
                    end
                else
                    -- Top-level: find target position among mixed items
                    insertPos = includeUnloaded and 1 or (#orderItems + 1)
                    if dropTarget.targetRow.kind ~= "unloaded-divider" then
                        insertPos = #orderItems + 1
                        for idx, item in ipairs(orderItems) do
                            if item.kind == dropTarget.targetRow.kind and item.id == dropTarget.targetRow.id then
                                insertPos = dropTarget.action == "reorder-after" and idx + 1 or idx
                                break
                            end
                        end
                    end
                    table.insert(orderItems, insertPos, { kind = "group", id = sourceContainerId })
                    local specId = CooldownCompanion._currentSpecId
                    for i, item in ipairs(orderItems) do
                        if item.kind == "folder" and db.folders[item.id] then
                            CooldownCompanion:SetOrderForSpec(db.folders[item.id], specId, i)
                        elseif db.groupContainers[item.id] then
                            CooldownCompanion:SetOrderForSpec(db.groupContainers[item.id], specId, i)
                        end
                    end
                end
            end
        end
    elseif state.kind == "multi-group" then
        -- Multi-select: sourceGroupIds holds container IDs (Column 1 rows are containers)
        local sourceContainerIds = state.sourceGroupIds
        if not sourceContainerIds then return end

        local targetRow = dropTarget.targetRow
        -- Determine target folder and section
        local targetFolderId = ResolveCol1GroupDropTargetFolderId(state, dropTarget)

        local targetSection = targetRow.section or state.sourceSection

        -- Set folder and cross-section toggle for each selected container
        for cid in pairs(sourceContainerIds) do
            local c = db.groupContainers[cid]
            if c then
                CooldownCompanion:MoveGroupToFolder(cid, targetFolderId)
                local containerSection = c.isGlobal and "global" or "char"
                if containerSection ~= targetSection then
                    if targetSection == "global" then
                        c.isGlobal = true
                    else
                        c.isGlobal = false
                        c.createdBy = CooldownCompanion.db.keys.char
                    end
                end
            end
        end

        -- Sort selected containers by current per-spec order to preserve relative ordering
        local specId = CooldownCompanion._currentSpecId
        local sortedSelected = {}
        for cid in pairs(sourceContainerIds) do
            local c = db.groupContainers[cid]
            if c then
                table.insert(sortedSelected, { id = cid, order = CooldownCompanion:GetOrderForSpec(c, specId, cid) })
            end
        end
        table.sort(sortedSelected, function(a, b) return a.order < b.order end)

        -- Rebuild order for target section
        local renderedRows = state.col1RenderedRows
        if renderedRows then
            if targetFolderId then
                -- Ordering within a folder
                local orderItems = {}
                for _, row in ipairs(renderedRows) do
                    if row.kind == "container" and row.inFolder == targetFolderId and not sourceContainerIds[row.id] then
                        table.insert(orderItems, row.id)
                    end
                end

                -- Find insertion position
                local insertPos = #orderItems + 1
                for idx, cid in ipairs(orderItems) do
                    if cid == targetRow.id then
                        insertPos = dropTarget.action == "reorder-after" and idx + 1 or idx
                        break
                    end
                end
                -- Insert all selected containers at the position, preserving relative order
                for i, item in ipairs(sortedSelected) do
                    table.insert(orderItems, insertPos + i - 1, item.id)
                end
                for i, cid in ipairs(orderItems) do
                    if db.groupContainers[cid] then
                        CooldownCompanion:SetOrderForSpec(db.groupContainers[cid], specId, i)
                    end
                end
            elseif IsCol1MixedDragSource(state.sourceLoadBucket) then
                local selectedLoaded, selectedUnloaded = PartitionSelectedContainersByLoadBucket(sourceContainerIds, renderedRows, specId, db)
                local loadedOrderItems = {}
                local unloadedOrderItems = {}
                for _, row in ipairs(renderedRows) do
                    if row.section == targetSection and not sourceContainerIds[row.id] then
                        if ShouldIncludeCol1TopLevelOrderRow(row, false) then
                            table.insert(loadedOrderItems, { kind = row.kind, id = row.id })
                        elseif ShouldIncludeCol1TopLevelOrderRow(row, true) then
                            table.insert(unloadedOrderItems, { kind = row.kind, id = row.id })
                        end
                    end
                end

                local targetIsUnloaded = targetRow.kind == "unloaded-divider" or targetRow.loadBucket == "unloaded"
                local loadedInsertPos
                local unloadedInsertPos
                if targetIsUnloaded then
                    loadedInsertPos = #loadedOrderItems + 1
                    unloadedInsertPos = FindCol1TopLevelInsertPos(unloadedOrderItems, targetRow, dropTarget.action, 1)
                else
                    loadedInsertPos = FindCol1TopLevelInsertPos(loadedOrderItems, targetRow, dropTarget.action, #loadedOrderItems + 1)
                    unloadedInsertPos = 1
                end

                for i, item in ipairs(selectedLoaded) do
                    table.insert(loadedOrderItems, loadedInsertPos + i - 1, { kind = item.kind, id = item.id })
                end
                for i, item in ipairs(selectedUnloaded) do
                    table.insert(unloadedOrderItems, unloadedInsertPos + i - 1, { kind = item.kind, id = item.id })
                end

                local nextOrder = AssignCol1TopLevelOrders(loadedOrderItems, db, specId, 1)
                AssignCol1TopLevelOrders(unloadedOrderItems, db, specId, nextOrder)
            else
                -- Top-level ordering
                local includeUnloaded = IsUnloadedTopLevelDrop(state, dropTarget, targetFolderId)
                local orderItems = {}
                for _, row in ipairs(renderedRows) do
                    if row.section == targetSection then
                        if ShouldIncludeCol1TopLevelOrderRow(row, includeUnloaded) then
                            if not sourceContainerIds[row.id] then
                                table.insert(orderItems, { kind = row.kind, id = row.id })
                            end
                        end
                    end
                end

                local insertPos = includeUnloaded and 1 or (#orderItems + 1)
                if targetRow.kind ~= "unloaded-divider" then
                    insertPos = #orderItems + 1
                    for idx, item in ipairs(orderItems) do
                        if item.kind == targetRow.kind and item.id == targetRow.id then
                            insertPos = dropTarget.action == "reorder-after" and idx + 1 or idx
                            break
                        end
                    end
                end
                -- Insert all selected containers at the position
                for i, item in ipairs(sortedSelected) do
                    table.insert(orderItems, insertPos + i - 1, { kind = "group", id = item.id })
                end
                for i, item in ipairs(orderItems) do
                    if item.kind == "folder" and db.folders[item.id] then
                        CooldownCompanion:SetOrderForSpec(db.folders[item.id], specId, i)
                    elseif db.groupContainers[item.id] then
                        CooldownCompanion:SetOrderForSpec(db.groupContainers[item.id], specId, i)
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

        -- Cross-section move: toggle folder section and update all child containers
        if section ~= state.sourceSection then
            folder.section = section
            if section == "char" then
                folder.createdBy = CooldownCompanion.db.keys.char
            end
            for containerId, container in pairs(db.groupContainers) do
                if container.folderId == sourceFolderId then
                    if section == "global" then
                        container.isGlobal = true
                    else
                        container.isGlobal = false
                        container.createdBy = CooldownCompanion.db.keys.char
                    end
                end
            end
        end

        -- Build top-level items for the section (excluding the source folder)
        local renderedRows = state.col1RenderedRows
        if renderedRows then
            local includeUnloaded = IsUnloadedTopLevelDrop(state, dropTarget, nil)
            local orderItems = {}
            for _, row in ipairs(renderedRows) do
                if row.section == section then
                    if ShouldIncludeCol1TopLevelOrderRow(row, includeUnloaded)
                        and row.id ~= sourceFolderId then
                        table.insert(orderItems, { kind = row.kind, id = row.id })
                    end
                end
            end

            local insertPos = includeUnloaded and 1 or (#orderItems + 1)
            if targetRow.kind ~= "unloaded-divider" then
                insertPos = #orderItems + 1
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
            end
            table.insert(orderItems, insertPos, { kind = "folder", id = sourceFolderId })
            local specId = CooldownCompanion._currentSpecId
            for i, item in ipairs(orderItems) do
                if item.kind == "folder" then
                    if db.folders[item.id] then
                        CooldownCompanion:SetOrderForSpec(db.folders[item.id], specId, i)
                    end
                else
                    if db.groupContainers[item.id] then
                        CooldownCompanion:SetOrderForSpec(db.groupContainers[item.id], specId, i)
                    end
                end
            end
        end
    end

    -- Container order may have changed — re-evaluate auto-anchored bars
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
-- Cross-panel move helpers
------------------------------------------------------------------------
local function PerformCrossPanelMove(sourcePanelId, sourceIndex, targetPanelId, targetIndex)
    local db = CooldownCompanion.db.profile
    local sourceGroup = db.groups[sourcePanelId]
    local targetGroup = db.groups[targetPanelId]
    if not sourceGroup or not targetGroup then return nil end
    local rejectMessage = CooldownCompanion.GetPanelManualEntryRejectMessage
        and CooldownCompanion:GetPanelManualEntryRejectMessage(targetGroup)
    if rejectMessage then
        CooldownCompanion:Print(rejectMessage)
        return nil
    end
    local buttonData = table.remove(sourceGroup.buttons, sourceIndex)
    if not buttonData then return nil end
    -- Resolve "append" targets (nil targetIndex = after last button)
    if not targetIndex then
        targetIndex = #targetGroup.buttons + 1
    end
    local maxTarget = #targetGroup.buttons + 1
    if targetIndex > maxTarget then targetIndex = maxTarget end
    table.insert(targetGroup.buttons, targetIndex, buttonData)
    return buttonData
end

local function StripButtonOverrides(buttonData)
    buttonData.styleOverrides = nil
    buttonData.overrideSections = nil
    buttonData.textFormat = nil
end

local function ButtonHasOverrides(buttonData)
    return (buttonData.styleOverrides and next(buttonData.styleOverrides))
        or (buttonData.overrideSections and next(buttonData.overrideSections))
        or buttonData.textFormat ~= nil
end

------------------------------------------------------------------------
-- Drag lifecycle
------------------------------------------------------------------------
local function SetDraggedWidgetAlpha(widget, alpha)
    if not widget then return end
    if widget.frame and widget.frame.SetAlpha then
        widget.frame:SetAlpha(alpha)
    elseif widget.SetAlpha then
        widget:SetAlpha(alpha)
    end
end

local function CancelDrag()
    if CS.dragState then
        if CS.dragState.kind == "layout-slot"
            and CS.dragState.layoutDrag
            and CS.dragState.layoutDrag.onCancel then
            CS.dragState.layoutDrag.onCancel(CS.dragState)
        end
    end
    ClearCol1AnimatedPreview()
    ClearCol2AnimatedPreview()
    if CS.dragState then
        if CS.dragState.dimmedWidgets then
            for _, w in ipairs(CS.dragState.dimmedWidgets) do
                SetDraggedWidgetAlpha(w, 1)
            end
        elseif CS.dragState.widget then
            SetDraggedWidgetAlpha(CS.dragState.widget, 1)
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

local function FinishLayoutSlotDrag(state)
    local cursorX, cursorY = GetRawCursorCoordinates()
    if state.layoutDrag and state.layoutDrag.resolveDropTarget then
        state.dropTarget = state.layoutDrag.resolveDropTarget(cursorX, cursorY, state)
    end
    if state.layoutDrag and state.layoutDrag.applyDrop then
        state.layoutDrag.applyDrop(state)
    end
    CancelDrag()
    ResetDragIndicatorStyle()
end

local function FinishLegacyGroupDrag(state)
    PerformGroupReorder(state.sourceIndex, state.dropIndex or state.sourceIndex, state.groupIds)
    CooldownCompanion:EvaluateResourceBars()
    CooldownCompanion:UpdateAnchorStacking()
    CooldownCompanion:EvaluateCastBar()
    CooldownCompanion:RefreshConfigPanel()
end

local function FinishCol1FolderAwareDrag(state)
    local dropTarget = state.dropTarget
    local changed = true
    if dropTarget then
        if state.kind == "group" or state.kind == "folder-group" then
            changed = not IsCol1GroupDropNoOp(state)
        elseif state.kind == "folder" then
            changed = not IsCol1FolderDropNoOp(state)
        end
    end

    if dropTarget and (state.kind == "group" or state.kind == "folder-group") then
        local targetSection = dropTarget.targetRow and dropTarget.targetRow.section
        local sourceContainer = CooldownCompanion.db.profile.groupContainers[state.sourceGroupId]
        if targetSection and targetSection ~= state.sourceSection
           and state.sourceSection == "global"
           and sourceContainer and sourceContainer.specs
           and GroupsHaveForeignSpecs({ sourceContainer }, false) then
            ShowPopupAboveConfig("CDC_DRAG_UNGLOBAL_GROUP", sourceContainer.name, {
                dragState = state,
            })
            return
        end
    end

    if dropTarget and state.kind == "multi-group" and state.sourceGroupIds then
        local targetSection = dropTarget.targetRow and dropTarget.targetRow.section
        if targetSection == "char" then
            local db = CooldownCompanion.db.profile
            local groupList = {}
            for cid in pairs(state.sourceGroupIds) do
                if db.groupContainers[cid] then
                    groupList[#groupList + 1] = db.groupContainers[cid]
                end
            end
            if GroupsHaveForeignSpecs(groupList, true) then
                local ids = {}
                for gid in pairs(state.sourceGroupIds) do
                    ids[#ids + 1] = gid
                end
                ShowPopupAboveConfig("CDC_UNGLOBAL_SELECTED_GROUPS", nil, {
                    groupIds = ids,
                    callback = function()
                        ApplyCol1Drop(state)
                        CooldownCompanion:RefreshConfigPanel()
                    end,
                })
                return
            end
        end
    end

    if dropTarget and state.kind == "folder" then
        local targetSection = dropTarget.targetRow and dropTarget.targetRow.section
        if targetSection and targetSection ~= state.sourceSection
           and state.sourceSection == "global"
           and FolderHasForeignSpecs
           and FolderHasForeignSpecs(state.sourceFolderId) then
            ShowPopupAboveConfig("CDC_DRAG_UNGLOBAL_FOLDER", nil, {
                dragState = state,
            })
            return
        end
    end

    if changed then
        ApplyCol1Drop(state)
    end
    CooldownCompanion:RefreshConfigPanel()
end

local function FinishPanelDrag(state)
    local dropTarget = state.dropTarget
    local changed = dropTarget and not IsPanelReorderNoOp(state.sourcePanelId, dropTarget.targetIndex, state.panelDropTargets)
    if changed then
        SelectConfigPanel(state.sourcePanelId)
        PerformPanelReorder(state.sourcePanelId, dropTarget.targetIndex, state.panelDropTargets)
        for _, entry in ipairs(state.panelDropTargets) do
            CooldownCompanion:RefreshGroupFrame(entry.panelId)
        end
    end
    CooldownCompanion:RefreshConfigPanel()
end

local function FinishButtonDrag(state)
    if state.dropTarget then
        local dt = state.dropTarget
        local resolvedIndex = dt.targetIndex
        if not resolvedIndex then
            local tg = CooldownCompanion.db.profile.groups[dt.targetPanelId]
            resolvedIndex = tg and (#tg.buttons + 1) or 1
        end
        if dt.targetPanelId == state.groupId then
            PerformButtonReorder(state.groupId, state.sourceIndex, resolvedIndex)
            CooldownCompanion:RefreshGroupFrame(state.groupId)
        else
            local sourceGroup = CooldownCompanion.db.profile.groups[state.groupId]
            local targetGroup = CooldownCompanion.db.profile.groups[dt.targetPanelId]
            local rejectMessage = CooldownCompanion.GetPanelManualEntryRejectMessage
                and CooldownCompanion:GetPanelManualEntryRejectMessage(targetGroup)
            if rejectMessage then
                CooldownCompanion:Print(rejectMessage)
            else
                local buttonData = sourceGroup and sourceGroup.buttons[state.sourceIndex]
                if buttonData and ButtonHasOverrides(buttonData) then
                    ShowPopupAboveConfig("CDC_CROSS_PANEL_STRIP_OVERRIDES", buttonData.name or "this button", {
                        sourcePanelId = state.groupId,
                        sourceIndex = state.sourceIndex,
                        targetPanelId = dt.targetPanelId,
                        targetIndex = resolvedIndex,
                    })
                    return
                end
                PerformCrossPanelMove(state.groupId, state.sourceIndex, dt.targetPanelId, resolvedIndex)
                CooldownCompanion:RefreshGroupFrame(state.groupId)
                CooldownCompanion:RefreshGroupFrame(dt.targetPanelId)
            end
        end
    else
        PerformButtonReorder(state.groupId, state.sourceIndex, state.dropIndex or state.sourceIndex)
        CooldownCompanion:RefreshGroupFrame(state.groupId)
    end
    CooldownCompanion:ClearAllConfigPreviews()
    ClearConfigButtonSelection()
    CooldownCompanion:RefreshConfigPanel()
end

local function FinishDrag()
    if not CS.dragState or CS.dragState.phase ~= "active" then
        CancelDrag()
        return
    end
    local state = CS.dragState
    if state.kind == "layout-slot" then
        FinishLayoutSlotDrag(state)
        return
    end
    CS.showPhantomSections = false  -- clear before CancelDrag to avoid redundant deferred refresh
    CancelDrag()
    ResetDragIndicatorStyle()
    if state.kind == "group" and state.groupIds then
        FinishLegacyGroupDrag(state)
    elseif state.kind == "group" or state.kind == "folder" or state.kind == "folder-group" or state.kind == "multi-group" then
        FinishCol1FolderAwareDrag(state)
    elseif state.kind == "panel" then
        FinishPanelDrag(state)
    elseif state.kind == "button" then
        FinishButtonDrag(state)
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
        local cursorX, cursorY
        if CS.dragState.kind == "layout-slot" then
            cursorX, cursorY = GetRawCursorCoordinates()
        else
            cursorX, cursorY = GetScaledCursorCoordinates(CS.dragState.scrollWidget)
        end
        if CS.dragState.phase == "pending" then
            local deltaY = math.abs(cursorY - (CS.dragState.startY or cursorY))
            local deltaX = math.abs(cursorX - (CS.dragState.startX or cursorX))
            if deltaY > DRAG_THRESHOLD or deltaX > DRAG_THRESHOLD then
                CS.dragState.phase = "active"
                if CS.dragState.kind == "layout-slot"
                    and CS.dragState.layoutDrag
                    and CS.dragState.layoutDrag.onActivate then
                    CS.dragState.layoutDrag.onActivate(CS.dragState)
                end
                -- Dim source widget(s)
                if CS.dragState.kind == "multi-group" and CS.dragState.sourceGroupIds then
                    CS.dragState.dimmedWidgets = {}
                    for _, row in ipairs(CS.dragState.col1RenderedRows) do
                        if row.kind == "container" and CS.dragState.sourceGroupIds[row.id] then
                            SetDraggedWidgetAlpha(row.widget, 0.4)
                            table.insert(CS.dragState.dimmedWidgets, row.widget)
                        end
                    end
                elseif CS.dragState.widget then
                    SetDraggedWidgetAlpha(CS.dragState.widget, 0.4)
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
                        local savedSourceLoadBucket = CS.dragState.sourceLoadBucket
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
                            sourceLoadBucket = savedSourceLoadBucket,
                            scrollWidget = savedScrollWidget,
                            startY = savedStartY,
                            col1RenderedRows = CS.lastCol1RenderedRows,
                        }
                        -- Dim the source widget(s) in the new rows
                        if savedKind == "multi-group" and savedSourceGroupIds then
                            CS.dragState.dimmedWidgets = {}
                            for _, row in ipairs(CS.dragState.col1RenderedRows) do
                                if row.kind == "container" and savedSourceGroupIds[row.id] then
                                    SetDraggedWidgetAlpha(row.widget, 0.4)
                                    table.insert(CS.dragState.dimmedWidgets, row.widget)
                                end
                            end
                        else
                            for _, row in ipairs(CS.dragState.col1RenderedRows) do
                                if savedKind == "folder" and row.kind == "folder" and row.id == savedSourceFolderId then
                                    CS.dragState.widget = row.widget
                                    SetDraggedWidgetAlpha(row.widget, 0.4)
                                    break
                                elseif (savedKind == "group" or savedKind == "folder-group") and row.kind == "container" and row.id == savedSourceGroupId then
                                    CS.dragState.widget = row.widget
                                    SetDraggedWidgetAlpha(row.widget, 0.4)
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
        if CS.dragState.phase == "active" then
            SetDraggedFolderAccentBarHidden(CS.dragState, true)
            if CS.dragState.kind == "layout-slot" then
                local dropTarget = CS.dragState.layoutDrag
                    and CS.dragState.layoutDrag.resolveDropTarget
                    and CS.dragState.layoutDrag.resolveDropTarget(cursorX, cursorY, CS.dragState)
                CS.dragState.dropTarget = dropTarget
                ClearCol2AnimatedPreview()
                if CS.dragState.layoutDrag and CS.dragState.layoutDrag.onUpdate then
                    CS.dragState.layoutDrag.onUpdate(CS.dragState, cursorX, cursorY, dropTarget)
                elseif dropTarget and CS.dragState.layoutDrag.showIndicator then
                    CS.dragState.layoutDrag.showIndicator(dropTarget)
                else
                    HideDragIndicator()
                end
            elseif CS.dragState.col1RenderedRows then
                ClearCol2AnimatedPreview()
                -- Column 1 folder-aware drop detection
                local effectiveKind = CS.dragState.kind == "multi-group" and "group" or CS.dragState.kind
                local dropTarget = GetCol1DropTarget(
                    cursorX,
                    cursorY,
                    CS.dragState.scrollWidget,
                    CS.dragState.col1RenderedRows,
                    effectiveKind,
                    CS.dragState.sourceSection,
                    CS.dragState.sourceFolderId,
                    CS.dragState.sourceLoadBucket,
                    CS.dragState.dropTarget
                )
                CS.dragState.dropTarget = dropTarget
                if dropTarget then
                    ResetDragIndicatorStyle()
                    HideDragIndicator()
                    local shouldAnimatePreview = ShouldAnimateCol1PreviewForDrop(
                        CS.dragState.sourceLoadBucket,
                        dropTarget,
                        CS.dragState.col1RenderedRows
                    )
                    if not shouldAnimatePreview or not RenderCol1AnimatedPreview({
                        kind = CS.dragState.kind,
                        sourceGroupId = CS.dragState.sourceGroupId,
                        sourceGroupIds = CS.dragState.sourceGroupIds,
                        sourceFolderId = CS.dragState.sourceFolderId,
                        dropTarget = dropTarget,
                    }) then
                        ClearCol1AnimatedPreview()
                        local unloadedPlaceholderTarget = ResolveCol1LoadedUnloadedPlaceholderTarget(
                            CS.dragState.col1RenderedRows,
                            CS.dragState.sourceLoadBucket,
                            dropTarget
                        )
                        if dropTarget.action == "into-folder" then
                            HideDragIndicator()
                        elseif unloadedPlaceholderTarget then
                            HideDragIndicator()
                        elseif ShouldShowCol1StaticReorderIndicator(
                            CS.dragState.sourceLoadBucket,
                            dropTarget
                        )
                            and dropTarget.action == "reorder-before"
                        then
                            ShowDragIndicator(dropTarget.anchorFrame, true, CS.dragState.scrollWidget)
                        elseif ShouldShowCol1StaticReorderIndicator(
                            CS.dragState.sourceLoadBucket,
                            dropTarget
                        ) then
                            ShowDragIndicator(dropTarget.anchorFrame, false, CS.dragState.scrollWidget)
                        else
                            HideDragIndicator()
                        end
                    end
                else
                    ClearCol1AnimatedPreview()
                    HideDragIndicator()
                end
            elseif CS.dragState.panelDropTargets then
                ClearCol1AnimatedPreview()
                -- Panel reorder detection
                local preview = CS.col2Preview
                local dropTarget
                if preview and preview.mode == PREVIEW_MODE_PANEL_COMPACT then
                    dropTarget = GetCol2CompactPanelDropTarget(cursorY)
                else
                    dropTarget = GetCol2PanelDropTarget(cursorY, CS.dragState.panelDropTargets)
                end
                CS.dragState.dropTarget = dropTarget
                if dropTarget then
                    HideDragIndicator()
                    RenderCol2AnimatedPreview({
                        kind = "panel",
                        sourcePanelId = CS.dragState.sourcePanelId,
                        dropTarget = dropTarget,
                    })
                else
                    HideDragIndicator()
                    ClearCol2AnimatedPreview()
                end
            elseif CS.dragState.col2RenderedRows then
                ClearCol1AnimatedPreview()
                -- Column 2 cross-panel drop detection
                local dropTarget = GetCol2DropTarget(cursorY, CS.dragState.col2RenderedRows)
                CS.dragState.dropTarget = dropTarget
                if dropTarget then
                    HideDragIndicator()
                    RenderCol2AnimatedPreview({
                        kind = "button",
                        groupId = CS.dragState.groupId,
                        sourceIndex = CS.dragState.sourceIndex,
                        dropTarget = dropTarget,
                    })
                else
                    HideDragIndicator()
                    ClearCol2AnimatedPreview()
                end
            else
                ClearCol1AnimatedPreview()
                ClearCol2AnimatedPreview()
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
ST._PerformCrossPanelMove = PerformCrossPanelMove
ST._StripButtonOverrides = StripButtonOverrides
ST._UpdateCol2CursorPreview = UpdateCol2CursorPreview
ST._ClearCol2AnimatedPreview = ClearCol2AnimatedPreview
