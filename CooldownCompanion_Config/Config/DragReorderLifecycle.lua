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
local SelectConfigPanel = ST._SelectConfigPanel
local ClearConfigButtonSelection = ST._ClearConfigButtonSelection

local DRAG_THRESHOLD = 8

local GetRawCursorCoordinates = DR.GetRawCursorCoordinates
local GetScaledCursorCoordinates = DR.GetScaledCursorCoordinates
local GetScaledCursorPosition = DR.GetScaledCursorPosition
local GetDropIndex = DR.GetDropIndex
local HideDragIndicator = DR.HideDragIndicator
local ShowDragIndicator = DR.ShowDragIndicator
local ResetDragIndicatorStyle = DR.ResetDragIndicatorStyle
local ClearCol1AnimatedPreview = DR.ClearCol1AnimatedPreview
local RenderCol1AnimatedPreview = DR.RenderCol1AnimatedPreview
local ShouldAnimateCol1PreviewForDrop = DR.ShouldAnimateCol1PreviewForDrop
local ShouldShowCol1StaticReorderIndicator = DR.ShouldShowCol1StaticReorderIndicator
local ResolveCol1LoadedUnloadedPlaceholderTarget = DR.ResolveCol1LoadedUnloadedPlaceholderTarget
local GetCol1DropTarget = DR.GetCol1DropTarget
local PerformGroupReorder = DR.PerformGroupReorder
local IsCol1GroupDropNoOp = DR.IsCol1GroupDropNoOp
local IsUnloadedTopLevelDrop = DR.IsUnloadedTopLevelDrop
local IsCol1MixedDragSource = DR.IsCol1MixedDragSource
local ShouldIncludeCol1TopLevelOrderRow = DR.ShouldIncludeCol1TopLevelOrderRow
local FindCol1TopLevelInsertPos = DR.FindCol1TopLevelInsertPos
local AssignCol1TopLevelOrders = DR.AssignCol1TopLevelOrders
local PartitionSelectedContainersByLoadBucket = DR.PartitionSelectedContainersByLoadBucket
local GetRailPanelDropTarget = DR.GetRailPanelDropTarget

local RAIL_PANEL_SPRING_DELAY = 0.45

local function IsCol1OwnershipMoveAllowed(sourceSection, targetSection)
    if not targetSection or sourceSection == targetSection then
        return true
    end
    if targetSection == "global" and sourceSection ~= "global" then
        return true
    end
    return sourceSection == "global" and targetSection == "char"
end

local function GetContainerSection(container)
    if not container then return nil end
    if container.isGlobal then return "global" end
    if CooldownCompanion.ResolveContainerClassScope then
        local scope = CooldownCompanion:ResolveContainerClassScope(container)
        return scope and scope.sectionKey or "invalid"
    end
    return "char"
end

local function ApplyContainerSection(containerId, container, targetSection)
    if targetSection == "global" then
        container.isGlobal = true
        return true
    end
    if targetSection == "char" then
        container.isGlobal = false
        container.createdBy = CooldownCompanion.db.keys.char
        if CooldownCompanion.NormalizeContainerEligibilityForCharacterScope then
            CooldownCompanion:NormalizeContainerEligibilityForCharacterScope(containerId)
        end
        return true
    end
    return targetSection == GetContainerSection(container)
end

------------------------------------------------------------------------
-- Apply a Navigator Group drop result
------------------------------------------------------------------------
local function ApplyCol1Drop(state)
    local dropTarget = state.dropTarget
    if not dropTarget then return end

    local db = CooldownCompanion.db.profile

    if state.kind == "group" then
        -- Navigator Group rows use container IDs (sourceGroupId holds one).
        local sourceContainerId = state.sourceGroupId
        local container = db.groupContainers[sourceContainerId]
        if not container then return end

        if dropTarget.action == "reorder-before" or dropTarget.action == "reorder-after" then
            local targetRow = dropTarget.targetRow
            local targetSection = targetRow.section or state.sourceSection
            if not IsCol1OwnershipMoveAllowed(state.sourceSection, targetSection) then
                return
            end

            -- Cross-section move: toggle global/character status
            if targetSection ~= state.sourceSection then
                if not ApplyContainerSection(sourceContainerId, container, targetSection) then
                    return
                end
            end
            local renderedRows = state.col1RenderedRows
            if renderedRows then
                local includeUnloaded = IsUnloadedTopLevelDrop(state, dropTarget)
                local orderItems = {}
                for _, row in ipairs(renderedRows) do
                    if row.section == targetSection
                        and ShouldIncludeCol1TopLevelOrderRow(row, includeUnloaded)
                        and row.id ~= sourceContainerId
                    then
                        table.insert(orderItems, { kind = row.kind, id = row.id })
                    end
                end

                local insertPos = includeUnloaded and 1 or (#orderItems + 1)
                if dropTarget.targetRow.kind ~= "unloaded-divider" then
                    insertPos = FindCol1TopLevelInsertPos(
                        orderItems,
                        dropTarget.targetRow,
                        dropTarget.action,
                        #orderItems + 1
                    )
                end
                table.insert(orderItems, insertPos, { kind = "group", id = sourceContainerId })
                local specId = CooldownCompanion._currentSpecId
                for i, item in ipairs(orderItems) do
                    if db.groupContainers[item.id] then
                        CooldownCompanion:SetOrderForSpec(db.groupContainers[item.id], specId, i)
                    end
                end
            end
        end
    elseif state.kind == "multi-group" then
        local sourceContainerIds = state.sourceGroupIds
        if not sourceContainerIds then return end

        local targetRow = dropTarget.targetRow
        local targetSection = targetRow.section or state.sourceSection

        for cid in pairs(sourceContainerIds) do
            local container = db.groupContainers[cid]
            if container then
                local containerSection = GetContainerSection(container)
                if not IsCol1OwnershipMoveAllowed(containerSection, targetSection) then
                    return
                end
                if containerSection ~= targetSection then
                    if not ApplyContainerSection(cid, container, targetSection) then
                        return
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
            if IsCol1MixedDragSource(state.sourceLoadBucket) then
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
                local includeUnloaded = IsUnloadedTopLevelDrop(state, dropTarget)
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
    -- Structural-mutation contract (matches the delete and cross-panel move
    -- paths): the other index-keyed stores — multi-selection and per-button
    -- preview state — are cleared rather than remapped, or they would stay
    -- attached to whatever entries now occupy the old indexes.
    wipe(CS.selectedButtons)
    CooldownCompanion:ClearAllConfigPreviews()
end

------------------------------------------------------------------------
-- Cross-panel move helpers
------------------------------------------------------------------------
local function PerformCrossPanelMove(sourcePanelId, sourceIndex, targetPanelId, targetIndex)
    local db = CooldownCompanion.db.profile
    local sourceGroup = db.groups[sourcePanelId]
    local targetGroup = db.groups[targetPanelId]
    if not sourceGroup or not targetGroup then return nil end
    local buttonData = sourceGroup.buttons[sourceIndex]
    if not buttonData then return nil end
    local rejectMessage = CooldownCompanion.GetPanelManualEntryRejectMessage
        and CooldownCompanion:GetPanelManualEntryRejectMessage(targetGroup, buttonData)
    if rejectMessage then
        CooldownCompanion:Print(rejectMessage)
        return nil
    end
    table.remove(sourceGroup.buttons, sourceIndex)
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

local function CancelDrag(opts)
    local hadSpringOpen = CS.springOpenContainer ~= nil
    CS.springOpenContainer = nil
    if CS.dragState then
        if CS.dragState.kind == "layout-slot"
            and CS.dragState.layoutDrag
            and CS.dragState.layoutDrag.onCancel then
            CS.dragState.layoutDrag.onCancel(CS.dragState)
        end
    end
    ClearCol1AnimatedPreview()
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
    elseif hadSpringOpen and not (opts and opts.skipSpringRefresh) then
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

local function FinishButtonDrag(state)
    PerformButtonReorder(
        state.groupId,
        state.sourceIndex,
        state.dropIndex or state.sourceIndex
    )
    CooldownCompanion:RefreshGroupFrame(state.groupId)
    CooldownCompanion:ClearAllConfigPreviews()
    ClearConfigButtonSelection()
    CooldownCompanion:RefreshConfigPanel()
end

local function FinishCol1GroupDrag(state)
    local dropTarget = state.dropTarget
    local changed = true
    if dropTarget and state.kind == "group" then
        changed = not IsCol1GroupDropNoOp(state)
    end

    if dropTarget and state.kind == "group" then
        local targetSection = dropTarget.targetRow and dropTarget.targetRow.section
        if targetSection and not IsCol1OwnershipMoveAllowed(state.sourceSection, targetSection) then
            return
        end
        local sourceContainer = CooldownCompanion.db.profile.groupContainers[state.sourceGroupId]
        if targetSection and targetSection ~= state.sourceSection
           and state.sourceSection == "global"
           and targetSection == "char"
           and sourceContainer
           and GroupsHaveForeignSpecs({ sourceContainer }, false) then
            ShowPopupAboveConfig("CDC_DRAG_UNGLOBAL_GROUP", sourceContainer.name, {
                dragState = state,
            })
            return
        end
    end

    if dropTarget and state.kind == "multi-group" and state.sourceGroupIds then
        local targetSection = dropTarget.targetRow and dropTarget.targetRow.section
        if targetSection then
            local db = CooldownCompanion.db.profile
            for cid in pairs(state.sourceGroupIds) do
                local sourceContainer = db.groupContainers[cid]
                if sourceContainer and not IsCol1OwnershipMoveAllowed(GetContainerSection(sourceContainer), targetSection) then
                    return
                end
            end
        end
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

    if changed then
        ApplyCol1Drop(state)
    end
    CooldownCompanion:RefreshConfigPanel()
end

local function GetOrderedPanelIds(containerId)
    local ids = {}
    for _, panelInfo in ipairs(CooldownCompanion:GetPanels(containerId) or {}) do
        ids[#ids + 1] = panelInfo.groupId
    end
    return ids
end

local function BuildRailPanelFinalOrder(state, dropTarget)
    if not (dropTarget and dropTarget.targetContainerId) then
        return nil
    end

    local order = {}
    for _, panelId in ipairs(GetOrderedPanelIds(dropTarget.targetContainerId)) do
        if not state.sourcePanelIds[panelId] then
            order[#order + 1] = panelId
        end
    end

    local insertPos = #order + 1
    if dropTarget.targetPanelId then
        for index, panelId in ipairs(order) do
            if panelId == dropTarget.targetPanelId then
                insertPos = dropTarget.action == "after" and index + 1 or index
                break
            end
        end
    end

    for index, panelId in ipairs(state.sourcePanelOrder or {}) do
        table.insert(order, insertPos + index - 1, panelId)
    end
    return order
end

local function RailPanelDropIsNoOp(state, dropTarget, finalOrder)
    if not finalOrder then
        return true
    end

    local db = CooldownCompanion.db.profile
    for panelId in pairs(state.sourcePanelIds or {}) do
        local panel = db.groups[panelId]
        if not panel or panel.parentContainerId ~= dropTarget.targetContainerId then
            return false
        end
    end

    local currentOrder = GetOrderedPanelIds(dropTarget.targetContainerId)
    if #currentOrder ~= #finalOrder then
        return false
    end
    for index, panelId in ipairs(currentOrder) do
        if finalOrder[index] ~= panelId then
            return false
        end
    end
    return true
end

local function AssignPanelOrder(containerId, orderedPanelIds)
    local db = CooldownCompanion.db.profile
    if not db.groupContainers[containerId] then
        return
    end
    for index, panelId in ipairs(orderedPanelIds or GetOrderedPanelIds(containerId)) do
        local panel = db.groups[panelId]
        if panel and panel.parentContainerId == containerId then
            panel.order = index
        end
    end
end

local function FinishRailPanelDrag(state)
    local dropTarget = state.dropTarget
    local finalOrder = BuildRailPanelFinalOrder(state, dropTarget)
    if RailPanelDropIsNoOp(state, dropTarget, finalOrder) then
        CooldownCompanion:RefreshConfigPanel()
        return
    end

    local db = CooldownCompanion.db.profile
    local targetContainerId = dropTarget.targetContainerId
    local sourceContainers = {}
    for _, panelId in ipairs(state.sourcePanelOrder or {}) do
        local panel = db.groups[panelId]
        if panel then
            sourceContainers[panel.parentContainerId] = true
        end
    end

    for _, panelId in ipairs(state.sourcePanelOrder or {}) do
        local panel = db.groups[panelId]
        if panel and panel.parentContainerId ~= targetContainerId then
            if CooldownCompanion:MovePanel(panelId, targetContainerId) == false then
                CooldownCompanion:RefreshConfigPanel()
                return
            end
        end
    end

    AssignPanelOrder(targetContainerId, finalOrder)
    for sourceContainerId in pairs(sourceContainers) do
        if sourceContainerId ~= targetContainerId then
            AssignPanelOrder(sourceContainerId)
        end
    end

    for _, panelId in ipairs(state.sourcePanelOrder or {}) do
        if db.groups[panelId] then
            CooldownCompanion:RefreshGroupFrame(panelId)
        end
    end

    if #(state.sourcePanelOrder or {}) == 1 then
        SelectConfigPanel(state.sourcePanelOrder[1], { containerId = targetContainerId })
    else
        CS.selectedContainer = targetContainerId
        CS.selectedGroup = nil
        CS.expandedContainer = targetContainerId
        CS.resourcesEntrySelected = false
        CS.castFramesEntrySelected = false
        CS.addingToPanelId = nil
        wipe(CS.selectedPanels)
        for _, panelId in ipairs(state.sourcePanelOrder or {}) do
            if db.groups[panelId] then
                CS.selectedPanels[panelId] = true
            end
        end
        ClearConfigButtonSelection()
        CooldownCompanion:ClearAllConfigPreviews()
        if CooldownCompanion.RefreshAlphaUpdateDriver then
            CooldownCompanion:RefreshAlphaUpdateDriver()
        end
    end

    CooldownCompanion:EvaluateResourceBars()
    CooldownCompanion:UpdateAnchorStacking()
    CooldownCompanion:EvaluateCastBar()
    CooldownCompanion:RefreshConfigPanel()
end

local function RefreshRailPanelDragRows(state)
    if not ST._RefreshColumn1 then
        return
    end
    ClearCol1AnimatedPreview()
    ST._RefreshColumn1(true)
    state.railPanelRows = CS.lastCol1RenderedRows
    state.dimmedWidgets = {}
    for _, row in ipairs(state.railPanelRows or {}) do
        if row.kind == "aux-block" and row.rowType == "panel" and state.sourcePanelIds[row.id] then
            SetDraggedWidgetAlpha(row.widget, 0.4)
            state.dimmedWidgets[#state.dimmedWidgets + 1] = row.widget
        end
    end
end

local function UpdateRailPanelSpringOpen(state, dropTarget)
    local candidate = dropTarget and dropTarget.springContainerId or nil
    if not candidate or candidate == CS.springOpenContainer then
        state.springHoverContainer = nil
        state.springHoverStarted = nil
        return false
    end

    if state.springHoverContainer ~= candidate then
        state.springHoverContainer = candidate
        state.springHoverStarted = GetTime()
        return false
    end

    if GetTime() - (state.springHoverStarted or GetTime()) < RAIL_PANEL_SPRING_DELAY then
        return false
    end

    CS.springOpenContainer = candidate
    state.springHoverContainer = nil
    state.springHoverStarted = nil
    state.dropTarget = nil
    RefreshRailPanelDragRows(state)
    return true
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
    CancelDrag({ skipSpringRefresh = true })
    ResetDragIndicatorStyle()
    if state.kind == "group" and state.groupIds then
        FinishLegacyGroupDrag(state)
    elseif state.kind == "group" or state.kind == "multi-group" then
        FinishCol1GroupDrag(state)
    elseif state.kind == "rail-panel" then
        FinishRailPanelDrag(state)
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
                elseif CS.dragState.kind == "rail-panel" and CS.dragState.sourcePanelIds then
                    CS.dragState.dimmedWidgets = {}
                    for _, row in ipairs(CS.dragState.railPanelRows or {}) do
                        if row.kind == "aux-block"
                            and row.rowType == "panel"
                            and CS.dragState.sourcePanelIds[row.id] then
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
                                if savedKind == "group" and row.kind == "container" and row.id == savedSourceGroupId then
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
            if CS.dragState.kind == "layout-slot" then
                local dropTarget = CS.dragState.layoutDrag
                    and CS.dragState.layoutDrag.resolveDropTarget
                    and CS.dragState.layoutDrag.resolveDropTarget(cursorX, cursorY, CS.dragState)
                CS.dragState.dropTarget = dropTarget
                if CS.dragState.layoutDrag and CS.dragState.layoutDrag.onUpdate then
                    CS.dragState.layoutDrag.onUpdate(CS.dragState, cursorX, cursorY, dropTarget)
                elseif dropTarget and CS.dragState.layoutDrag.showIndicator then
                    CS.dragState.layoutDrag.showIndicator(dropTarget)
                else
                    HideDragIndicator()
                end
            elseif CS.dragState.railPanelRows then
                local dropTarget = GetRailPanelDropTarget(
                    cursorX,
                    cursorY,
                    CS.dragState.scrollWidget,
                    CS.dragState.railPanelRows,
                    CS.dragState.sourcePanelIds
                )
                CS.dragState.dropTarget = dropTarget
                if UpdateRailPanelSpringOpen(CS.dragState, dropTarget) then
                    HideDragIndicator()
                elseif dropTarget then
                    ResetDragIndicatorStyle()
                    HideDragIndicator()
                    if not RenderCol1AnimatedPreview({
                        kind = "rail-panel",
                        sourcePanelIds = CS.dragState.sourcePanelIds,
                        sourcePanelOrder = CS.dragState.sourcePanelOrder,
                        dropTarget = dropTarget,
                    }) then
                        ClearCol1AnimatedPreview()
                        ShowDragIndicator(
                            dropTarget.anchorFrame,
                            dropTarget.anchorAbove,
                            CS.dragState.scrollWidget
                        )
                    end
                else
                    ClearCol1AnimatedPreview()
                    HideDragIndicator()
                end
            elseif CS.dragState.col1RenderedRows then
                local dropTarget = GetCol1DropTarget(
                    cursorX,
                    cursorY,
                    CS.dragState.scrollWidget,
                    CS.dragState.col1RenderedRows,
                    CS.dragState.sourceSection,
                    CS.dragState.sourceLoadBucket
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
                        dropTarget = dropTarget,
                    }) then
                        ClearCol1AnimatedPreview()
                        local unloadedPlaceholderTarget = ResolveCol1LoadedUnloadedPlaceholderTarget(
                            CS.dragState.col1RenderedRows,
                            CS.dragState.sourceLoadBucket,
                            dropTarget
                        )
                        if unloadedPlaceholderTarget then
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
            else
                ClearCol1AnimatedPreview()
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
ST._ApplyCol1Drop = ApplyCol1Drop
ST._HideDragIndicator = HideDragIndicator
ST._GetScaledCursorPosition = GetScaledCursorPosition
ST._PerformCrossPanelMove = PerformCrossPanelMove
ST._PerformButtonReorder = PerformButtonReorder
ST._StripButtonOverrides = StripButtonOverrides
