--[[
    CooldownCompanion - Config/DragReorderLifecycle
    Drag lifecycle, Group drop planning and application, and public drag exports.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState
local DR = ST._DragReorder or {}
ST._DragReorder = DR

local GroupsHaveForeignSpecs = ST._GroupsHaveForeignSpecs
local ShowUnglobalGroupsPopup = ST._ShowUnglobalGroupsPopup
local SelectConfigPanel = ST._SelectConfigPanel
local ClearConfigButtonSelection = ST._ClearConfigButtonSelection

local DRAG_THRESHOLD = 8

local GetRawCursorCoordinates = DR.GetRawCursorCoordinates
local GetScaledCursorCoordinates = DR.GetScaledCursorCoordinates
local GetScaledCursorPosition = DR.GetScaledCursorPosition
local HideDragIndicator = DR.HideDragIndicator
local ShowCol1DropIndicator = DR.ShowCol1DropIndicator
local ShowRailPanelDropIndicator = DR.ShowRailPanelDropIndicator
local GetCol1DropTarget = DR.GetCol1DropTarget
local IsUnloadedTopLevelDrop = DR.IsUnloadedTopLevelDrop
local IsCol1MixedDragSource = DR.IsCol1MixedDragSource
local ShouldIncludeCol1TopLevelOrderRow = DR.ShouldIncludeCol1TopLevelOrderRow
local FindCol1TopLevelInsertPos = DR.FindCol1TopLevelInsertPos
local AssignCol1TopLevelOrders = DR.AssignCol1TopLevelOrders
local PartitionSelectedContainersByLoadBucket = DR.PartitionSelectedContainersByLoadBucket
local GetRailPanelDropTarget = DR.GetRailPanelDropTarget

local RAIL_PANEL_SPRING_DELAY = 0.45

-- Owner-tunable feel values: how deep into the column edge the cursor must sit
-- before the list starts scrolling, and how fast it scrolls at full depth.
local COL1_AUTOSCROLL_EDGE_ZONE = 48
local COL1_AUTOSCROLL_MAX_SPEED = 300

-- Without this, drop targets that are scrolled off-screen are simply
-- unreachable: the Navigator has no other way to scroll mid-drag.
--
-- No autoscroll state is stored anywhere. Each tick reads the scrollbar's
-- current value, so scrolling the wheel by hand mid-drag is preserved rather
-- than fought, and the distance is multiplied by `elapsed` so the speed is
-- frame-rate independent.
local function UpdateCol1DragAutoscroll(scrollWidget, cursorX, cursorY, elapsed)
    if not (scrollWidget and scrollWidget.content and scrollWidget.scrollframe and scrollWidget.scrollbar) then
        return
    end

    -- Scroll only where a drop could actually land. Without this the list keeps
    -- moving at full speed while the cursor sits over another column, showing no
    -- line and applying nothing on release, and leaves the Navigator scrolled
    -- somewhere the user never asked for. Same horizontal gate the drop-target
    -- resolvers already apply, so the two cannot disagree about "in the column".
    local scrollFrame = scrollWidget.scrollframe
    local left, right = scrollFrame:GetLeft(), scrollFrame:GetRight()
    if not (cursorX and left and right and cursorX >= left and cursorX <= right) then
        return
    end

    local contentHeight = scrollWidget.content:GetHeight()
    local viewportHeight = scrollWidget.scrollframe:GetHeight()
    local scrollRange = contentHeight - viewportHeight
    if scrollRange <= 0 then
        return
    end

    local viewportTop = scrollWidget.scrollframe:GetTop()
    local viewportBottom = scrollWidget.scrollframe:GetBottom()
    if not viewportTop or not viewportBottom then
        return
    end

    -- Depth is normalised 0..1 from the VIEWPORT edges, so speed scales with how
    -- far into the edge zone the cursor has pushed.
    local topDepth = (cursorY - (viewportTop - COL1_AUTOSCROLL_EDGE_ZONE))
        / COL1_AUTOSCROLL_EDGE_ZONE
    local bottomDepth = ((viewportBottom + COL1_AUTOSCROLL_EDGE_ZONE) - cursorY)
        / COL1_AUTOSCROLL_EDGE_ZONE
    local direction
    local depth
    if topDepth > 0 and topDepth >= bottomDepth then
        direction = -1
        depth = math.min(topDepth, 1)
    elseif bottomDepth > 0 then
        direction = 1
        depth = math.min(bottomDepth, 1)
    else
        return
    end

    local currentValue = scrollWidget.scrollbar:GetValue()
    local pixelDelta = direction * COL1_AUTOSCROLL_MAX_SPEED * depth * elapsed
    -- Pixels to the widget's 0..1000 units: the exact inverse of SetScroll's
    -- `offset = (height - viewheight) / 1000 * value`.
    local valueDelta = pixelDelta / scrollRange * 1000
    local targetValue = math.max(0, math.min(1000, currentValue + valueDelta))
    -- Applied via the same public path MoveScroll uses, so the thumb stays in
    -- sync, and only when the value actually changes so it does not spam at the
    -- clamps.
    if targetValue ~= currentValue then
        scrollWidget.scrollbar:SetValue(targetValue)
    end
end

local IsCol1OwnershipMoveAllowed = DR.IsCol1OwnershipMoveAllowed

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
    if targetSection == "global" or targetSection == "char" then
        return CooldownCompanion:SetContainerGlobalScope(containerId, targetSection == "global")
    end
    return targetSection == GetContainerSection(container)
end

------------------------------------------------------------------------
-- Plan a Navigator Group drop
------------------------------------------------------------------------
-- One section's Groups in one run (loaded or unloaded), in the order the
-- Navigator draws them: the list as it stands, and the same list with the
-- Groups in hand taken out, which is the list a drop inserts into.
local function CollectCol1TopLevelBucket(renderedRows, section, includeUnloaded, isSource)
    local current, remaining = {}, {}
    for _, row in ipairs(renderedRows) do
        if row.section == section and ShouldIncludeCol1TopLevelOrderRow(row, includeUnloaded) then
            current[#current + 1] = row.id
            if not isSource[row.id] then
                remaining[#remaining + 1] = row.id
            end
        end
    end
    return current, remaining
end

local function InsertCol1GroupIds(list, insertPos, ids)
    for index, id in ipairs(ids) do
        table.insert(list, insertPos + index - 1, id)
    end
end

-- One answer to "where does this Group drop land", like BuildRailPanelFinalOrder
-- for panels: per run, the order the Navigator shows now and the order the drop
-- writes. ShowCol1DropIndicator hides the line when they match, FinishCol1GroupDrag
-- skips the drop then, and ApplyCol1Drop writes the final lists.
--
-- Insert defaults: the unloaded divider means the top of the unloaded run for
-- an unloaded drop and the end otherwise; a target not found means the end; a
-- mixed selection's unloaded part goes to the top of the unloaded run unless
-- the target is in that run.
--
-- nil means nothing to drop: no target, an action that is not a reorder (the
-- line hides for those too), no rows, a vanished source, or a target on a
-- Group in hand (GetCol1DropTarget never returns one; this keeps a stray one
-- from sending the selection to the end).
local function BuildCol1GroupDropPlan(state, dropTarget)
    local targetRow = dropTarget and dropTarget.targetRow
    local renderedRows = state and state.col1RenderedRows
    if not (targetRow and renderedRows)
        or (dropTarget.action ~= "reorder-before" and dropTarget.action ~= "reorder-after")
    then
        return nil
    end

    local db = CooldownCompanion.db.profile
    local specId = CooldownCompanion._currentSpecId
    local targetSection = targetRow.section or state.sourceSection
    local isSource
    local selected, sectionChanges = {}, {}

    if state.kind == "group" then
        if not db.groupContainers[state.sourceGroupId] then
            return nil
        end
        isSource = { [state.sourceGroupId] = true }
        selected[1] = state.sourceGroupId
        if targetSection ~= state.sourceSection then
            sectionChanges[1] = state.sourceGroupId
        end
    elseif state.kind == "multi-group" and state.sourceGroupIds then
        isSource = state.sourceGroupIds
        -- The selection keeps the order the Navigator draws it in, across
        -- sections too. A selected Group with no drawn row goes after the
        -- drawn ones, by saved per-spec order and then id, as
        -- BuildOrderedContainerItems sorts.
        local drawnIndex = {}
        for index, row in ipairs(renderedRows) do
            if row.kind == "container" and drawnIndex[row.id] == nil then
                drawnIndex[row.id] = index
            end
        end
        local orderById = {}
        for cid in pairs(isSource) do
            local container = db.groupContainers[cid]
            if container then
                selected[#selected + 1] = cid
                orderById[cid] = CooldownCompanion:GetOrderForSpec(container, specId, cid)
                if GetContainerSection(container) ~= targetSection then
                    sectionChanges[#sectionChanges + 1] = cid
                end
            end
        end
        table.sort(selected, function(a, b)
            local drawnA, drawnB = drawnIndex[a] or math.huge, drawnIndex[b] or math.huge
            if drawnA ~= drawnB then
                return drawnA < drawnB
            end
            if orderById[a] == orderById[b] then
                return a < b
            end
            return orderById[a] < orderById[b]
        end)
    else
        return nil
    end

    if targetRow.kind == "container" and isSource[targetRow.id] then
        return nil
    end

    local buckets = {}
    if state.kind == "multi-group" and IsCol1MixedDragSource(state.sourceLoadBucket) then
        local selectedLoaded, selectedUnloaded = PartitionSelectedContainersByLoadBucket(selected, renderedRows)
        local loadedCurrent, loadedFinal = CollectCol1TopLevelBucket(renderedRows, targetSection, false, isSource)
        local unloadedCurrent, unloadedFinal = CollectCol1TopLevelBucket(renderedRows, targetSection, true, isSource)
        local loadedInsertPos, unloadedInsertPos
        if targetRow.kind == "unloaded-divider" or targetRow.loadBucket == "unloaded" then
            loadedInsertPos = #loadedFinal + 1
            unloadedInsertPos = FindCol1TopLevelInsertPos(unloadedFinal, targetRow, dropTarget.action, 1)
        else
            loadedInsertPos = FindCol1TopLevelInsertPos(loadedFinal, targetRow, dropTarget.action, #loadedFinal + 1)
            unloadedInsertPos = 1
        end
        InsertCol1GroupIds(loadedFinal, loadedInsertPos, selectedLoaded)
        InsertCol1GroupIds(unloadedFinal, unloadedInsertPos, selectedUnloaded)
        buckets[1] = { current = loadedCurrent, final = loadedFinal }
        buckets[2] = { current = unloadedCurrent, final = unloadedFinal }
    else
        local includeUnloaded = IsUnloadedTopLevelDrop(state, dropTarget)
        local current, final = CollectCol1TopLevelBucket(renderedRows, targetSection, includeUnloaded, isSource)
        local defaultPos = #final + 1
        if includeUnloaded and targetRow.kind == "unloaded-divider" then
            defaultPos = 1
        end
        InsertCol1GroupIds(final, FindCol1TopLevelInsertPos(final, targetRow, dropTarget.action, defaultPos), selected)
        buckets[1] = { current = current, final = final }
    end

    return {
        targetSection = targetSection,
        sectionChanges = sectionChanges,
        buckets = buckets,
    }
end

-- True when releasing changes nothing: no plan, no section change, and every
-- run's final order equals the order shown now.
local function IsCol1GroupDropPlanNoOp(plan)
    if not plan then
        return true
    end
    if plan.sectionChanges[1] then
        return false
    end
    for _, bucket in ipairs(plan.buckets) do
        if #bucket.final ~= #bucket.current then
            return false
        end
        for index, id in ipairs(bucket.current) do
            if bucket.final[index] ~= id then
                return false
            end
        end
    end
    return true
end

------------------------------------------------------------------------
-- Apply a Navigator Group drop result
------------------------------------------------------------------------
local function ApplyCol1Drop(state, plan)
    if not plan then return end

    local db = CooldownCompanion.db.profile
    local targetSection = plan.targetSection
    -- A section change can load or unload panels; the tail rebuilds for it.
    local scopeChanged = false

    if state.kind == "group" then
        -- Navigator Group rows use container IDs (sourceGroupId holds one).
        local sourceContainerId = state.sourceGroupId
        local container = db.groupContainers[sourceContainerId]
        if not container then return end

        if not IsCol1OwnershipMoveAllowed(state.sourceSection, targetSection) then
            return
        end

        -- Cross-section move: toggle global/character status
        if plan.sectionChanges[1] then
            if not ApplyContainerSection(sourceContainerId, container, targetSection) then
                return
            end
            scopeChanged = true
        end
    elseif state.kind == "multi-group" then
        local sourceContainerIds = state.sourceGroupIds
        if not sourceContainerIds then return end

        -- Every Group is checked before any moves: a confirm popup can land
        -- after the selection changed, and a refusal part-way through would
        -- leave the earlier Groups moved and nothing rebuilt.
        for cid in pairs(sourceContainerIds) do
            local container = db.groupContainers[cid]
            local containerSection = container and GetContainerSection(container)
            if container and (not IsCol1OwnershipMoveAllowed(containerSection, targetSection)
                or containerSection ~= targetSection
                    and targetSection ~= "global" and targetSection ~= "char") then
                return
            end
        end
        for _, cid in ipairs(plan.sectionChanges) do
            local container = db.groupContainers[cid]
            if container then
                ApplyContainerSection(cid, container, targetSection)
                scopeChanged = true
            end
        end
    end

    -- The plan's final lists are the order the line promised. A mixed
    -- selection's unloaded run numbers on from its loaded run.
    local specId = CooldownCompanion._currentSpecId
    local nextOrder = 1
    for _, bucket in ipairs(plan.buckets) do
        nextOrder = AssignCol1TopLevelOrders(bucket.final, db, specId, nextOrder)
    end

    -- A section change rebuilds every panel, as the menu's move does (that
    -- refresh re-evaluates the modules). Otherwise only the container order
    -- may have changed, so re-evaluate auto-anchored bars.
    if scopeChanged then
        CooldownCompanion:RefreshAllGroups()
    else
        CooldownCompanion:EvaluateBarsAndFramesRuntime("panel-attachment-choice")
    end
end

------------------------------------------------------------------------
-- Button reorder
------------------------------------------------------------------------
local function PerformButtonReorder(groupId, sourceIndex, dropIndex)
    if dropIndex > sourceIndex then dropIndex = dropIndex - 1 end
    if sourceIndex == dropIndex then return end
    local group = CooldownCompanion.db.profile.groups[groupId]
    if not group then return end
    if ST.IsIndicatorGroup(group) and (sourceIndex == 1 or dropIndex == 1) then return end
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
    -- Structural-mutation contract (matches the entry Delete and Move menu
    -- paths, PanelShared DeleteEntrySelection / MoveEntrySelection): the
    -- other index-keyed stores — multi-selection and per-button
    -- preview state — are cleared rather than remapped, or they would stay
    -- attached to whatever entries now occupy the old indexes.
    wipe(CS.selectedButtons)
    CooldownCompanion:ClearAllConfigPreviews()
end

------------------------------------------------------------------------
-- Drag lifecycle
------------------------------------------------------------------------
local DRAGGED_ALPHA = 0.4

-- A group row's widget is only its header label; the InlineGroup shell is what
-- actually spans the group AND its panel rows. Dim the shell so the whole block
-- reads as "in hand" rather than just its title.
local function ResolveDragDimTarget(row)
    if not row then return nil end
    if row.dragShellFrame and row.dragShellFrame.SetAlpha then
        return row.dragShellFrame
    end
    local widget = row.widget
    if not widget then return nil end
    return (widget.frame and widget.frame.SetAlpha and widget.frame) or widget
end

-- The pre-drag alpha is recorded rather than assumed: inactive groups already
-- sit at 0.58, so restoring to a flat 1 would silently un-dim them.
-- Keyed by frame, so re-dimming an already-dimmed target is a constant-time
-- no-op instead of a scan -- and, more importantly, so the recorded alpha is
-- always the pre-drag one and can never be overwritten with DRAGGED_ALPHA.
local function DimDragTarget(state, target)
    if not (state and target and target.SetAlpha) then return end
    state.dimmedTargets = state.dimmedTargets or {}
    if state.dimmedTargets[target] ~= nil then return end
    state.dimmedTargets[target] = (target.GetAlpha and target:GetAlpha()) or 1
    target:SetAlpha(DRAGGED_ALPHA)
end

local function DimDraggedRow(state, row)
    DimDragTarget(state, ResolveDragDimTarget(row))
end

local function DimDraggedWidget(state, widget)
    if not widget then return end
    DimDragTarget(state, (widget.frame and widget.frame.SetAlpha and widget.frame) or widget)
end

local function RestoreDragDimming(state)
    if not state then return end
    for target, alpha in pairs(state.dimmedTargets or {}) do
        if target.SetAlpha then
            target:SetAlpha(alpha)
        end
    end
    state.dimmedTargets = nil
end

------------------------------------------------------------------------
-- Escape cancels an in-flight drag
------------------------------------------------------------------------
-- Declared ahead of the catcher so its key handler reaches the real cancel
-- as an upvalue; the definition below assigns into this local.
local CancelDrag

-- The catcher is shown only while a drag is ACTIVE and hidden again by
-- CancelDrag -- the single choke point every drag end passes through (drop,
-- release-outside, and the preview-rebuild cancels). With no drag in hand the
-- frame is hidden, so it is not in the keyboard chain at all and Escape keeps
-- doing exactly what it does today (close the config window, or whatever the
-- profile's escClosesConfig option leaves it doing).
--
-- TOOLTIP strata puts it above the config window's own Escape handler, so the
-- press is consumed here instead of closing the window mid-drag. Propagation
-- follows the arrange-mode pill's discipline: armed on show and on every other
-- key so the frame behaves as if it were not there, flipped off only for the
-- Escape it actually consumes, and re-armed as soon as it can be.
--
-- SetPropagateKeyboardInput is combat-restricted, and that turns "re-arm on the
-- next show" into a trap: consuming an Escape out of combat leaves propagation
-- OFF, and a drag started in combat cannot turn it back on -- so a keyboard-
-- enabled frame would sit over the game swallowing every key, movement
-- included, for as long as the drag lasted. Hence the tracked state below: the
-- catcher re-arms on the tick after the press it consumed, and a drag that
-- still finds it disarmed IN combat goes without Escape support rather than
-- eating the keyboard.
local dragEscapeCatcher
-- True only while propagation is KNOWN to be on. Starts false: a keyboard frame
-- propagates nothing until told to, and the telling is restricted.
local dragEscapePropagating = false

--- Turn propagation back on if that is currently allowed.
--- Returns true when the catcher is safe to have in the keyboard chain.
local function ArmDragEscapeCatcher(catcher)
    -- Out of combat it always writes, exactly as the handlers here always did;
    -- in combat it can only report what the last legal write left behind.
    if InCombatLockdown() then return dragEscapePropagating end
    catcher:SetPropagateKeyboardInput(true)
    dragEscapePropagating = true
    return true
end

--- Re-arm AFTER the key event that disarmed it, never inside it.
--- The propagate flag is read when the handler returns, so an arm call in the
--- same call stack (OnKeyDown -> CancelDrag -> hide) would hand the Escape this
--- catcher just consumed straight on to the config window behind it. One tick
--- later the press is spent and the flag is free to go back to true.
--- Combat can still refuse the write; the next drag's show tries again.
local function RestoreDragEscapePropagation()
    if dragEscapePropagating or not dragEscapeCatcher then return end
    C_Timer.After(0, function()
        if dragEscapeCatcher then
            ArmDragEscapeCatcher(dragEscapeCatcher)
        end
    end)
end

local function EnsureDragEscapeCatcher()
    if dragEscapeCatcher then
        return dragEscapeCatcher
    end

    local catcher = CreateFrame("Frame", nil, UIParent)
    catcher:SetFrameStrata("TOOLTIP")
    -- Keyboard-only: no mouse, no textures, and a degenerate footprint so it
    -- can never sit between the cursor and the surface being dragged.
    catcher:SetSize(1, 1)
    catcher:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    catcher:EnableMouse(false)
    catcher:EnableKeyboard(true)
    catcher:Hide()
    catcher:SetScript("OnShow", function(self)
        ArmDragEscapeCatcher(self)
    end)
    catcher:SetScript("OnKeyDown", function(self, key)
        -- The phase test is the authority, not the frame's shown state: a
        -- stranded catcher must still pass Escape through untouched.
        if key == "ESCAPE" and CS.dragState and CS.dragState.phase == "active" then
            if not InCombatLockdown() then
                self:SetPropagateKeyboardInput(false)
                dragEscapePropagating = false
            end
            -- The mouse button is still down. Mark the release that is still in
            -- the user's hand as spent, so the drag source's mouse-up swallows
            -- it instead of falling through to its click behaviour.
            CS.dragEscapeCancelledMouseUp = true
            -- Re-arms on the way out: CancelDrag hides the catcher, and the
            -- hide schedules propagation's return for the following tick.
            CancelDrag()
        else
            ArmDragEscapeCatcher(self)
        end
    end)

    dragEscapeCatcher = catcher
    return catcher
end

local function ShowDragEscapeCatcher()
    local catcher = EnsureDragEscapeCatcher()
    -- Disarmed and in combat: it cannot be made to pass keys through, so it
    -- does not go in the chain at all. This drag loses Escape; it does not cost
    -- the player their keyboard.
    if not ArmDragEscapeCatcher(catcher) then return end
    catcher:Show()
end

local function HideDragEscapeCatcher()
    if not dragEscapeCatcher then return end
    dragEscapeCatcher:Hide()
    -- Paying back a consumed Escape here rather than on the next OnShow is what
    -- keeps a drag started IN combat from inheriting a disarmed catcher.
    RestoreDragEscapePropagation()
end

--- One-shot: true for exactly one mouse release, the one still in flight when
--- Escape cancelled an active drag. Drag sources ask this at the top of their
--- left-button mouse-up and swallow that release; every ask clears the mark, so
--- the very next click behaves normally again. Written straight onto ST rather
--- than through a file-scope local: this file is already dense with upvalues.
function ST._ConsumeDragEscapeMouseUp()
    if not CS.dragEscapeCancelledMouseUp then return false end
    CS.dragEscapeCancelledMouseUp = nil
    return true
end

function CancelDrag(opts)
    HideDragEscapeCatcher()
    local hadSpringOpen = CS.springOpenContainer ~= nil
    CS.springOpenContainer = nil
    if CS.dragState then
        if CS.dragState.kind == "layout-slot"
            and CS.dragState.layoutDrag
            and CS.dragState.layoutDrag.onCancel then
            CS.dragState.layoutDrag.onCancel(CS.dragState)
        end
    end
    RestoreDragDimming(CS.dragState)
    CS.dragState = nil
    HideDragIndicator()
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
end

local function FinishCol1GroupDrag(state)
    local dropTarget = state.dropTarget

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
            ShowUnglobalGroupsPopup(sourceContainer.name, function()
                if CooldownCompanion.db.profile.groupContainers[state.sourceGroupId] then
                    ApplyCol1Drop(state, BuildCol1GroupDropPlan(state, state.dropTarget))
                    CooldownCompanion:RefreshConfigPanel()
                end
            end)
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
                ShowUnglobalGroupsPopup(nil, function()
                    ApplyCol1Drop(state, BuildCol1GroupDropPlan(state, state.dropTarget))
                    CooldownCompanion:RefreshConfigPanel()
                end)
                return
            end
        end
    end

    -- The line asked this same plan, so a release it drew no line for changes
    -- nothing here either. The popups above only open for a section change,
    -- which is never a no-op.
    local plan = BuildCol1GroupDropPlan(state, dropTarget)
    if not IsCol1GroupDropPlanNoOp(plan) then
        ApplyCol1Drop(state, plan)
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

-- Published on DR so the drop indicators can ask exactly the question each
-- drop itself asks. DragReorderTargets loads first, so it reaches these
-- through DR at call time rather than capturing them as upvalues.
DR.BuildRailPanelFinalOrder = BuildRailPanelFinalOrder
DR.RailPanelDropIsNoOp = RailPanelDropIsNoOp
DR.BuildCol1GroupDropPlan = BuildCol1GroupDropPlan
DR.IsCol1GroupDropPlanNoOp = IsCol1GroupDropPlanNoOp

local function FinishRailPanelDrag(state)
    local dropTarget = state.dropTarget
    local finalOrder = BuildRailPanelFinalOrder(state, dropTarget)
    if RailPanelDropIsNoOp(state, dropTarget, finalOrder) then
        CooldownCompanion:RefreshConfigPanel()
        return
    end

    local attachmentOperation = CooldownCompanion:BeginPanelAttachmentRefresh()
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
                CooldownCompanion:EndPanelAttachmentRefresh(attachmentOperation)
                CooldownCompanion:RefreshConfigPanel()
                return
            end
        end
    end

    AssignPanelOrder(targetContainerId, finalOrder)
    -- Only panels that changed Group take the selection with them, as Move to
    -- Group does; a reorder inside one Group leaves the selection alone.
    local changedGroup = false
    for sourceContainerId in pairs(sourceContainers) do
        if sourceContainerId ~= targetContainerId then
            AssignPanelOrder(sourceContainerId)
            changedGroup = true
        end
    end

    for _, panelId in ipairs(state.sourcePanelOrder or {}) do
        if db.groups[panelId] then
            CooldownCompanion:RefreshGroupFrame(panelId)
        end
    end

    if changedGroup and #(state.sourcePanelOrder or {}) == 1 then
        SelectConfigPanel(state.sourcePanelOrder[1], { containerId = targetContainerId })
    elseif changedGroup then
        CS.selectedContainer = targetContainerId
        CS.selectedGroup = nil
        CS.expandedContainer = targetContainerId
        CS.barsEntrySelected = false
        CS.castFramesSelectedItem = nil
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

    CooldownCompanion:EvaluateBarsAndFramesRuntime("panel-attachment-choice")
    CooldownCompanion:EndPanelAttachmentRefresh(attachmentOperation)
    CooldownCompanion:RefreshConfigPanel()
end

local function RefreshRailPanelDragRows(state)
    if not ST._RefreshColumn1 then
        return
    end
    -- The rebuild releases every row widget, including whatever the indicator is
    -- anchored to. HideDragIndicator detaches to UIParent before fading, so the
    -- line finishes where it was rather than following a recycled row; the next
    -- tracker tick re-resolves against the fresh rows and shows it again.
    HideDragIndicator()
    ST._RefreshColumn1(true)
    state.railPanelRows = CS.lastCol1RenderedRows
    -- The rebuild replaced every row widget, so the previous dim targets are
    -- gone with them. Group shells get their alpha re-asserted by
    -- RenderContainerRow; panel rows get theirs reset by CleanRecycledEntry on
    -- re-acquire. Nothing is left stranded at DRAGGED_ALPHA either way.
    state.dimmedTargets = nil
    for _, row in ipairs(state.railPanelRows or {}) do
        if row.kind == "aux-block" and row.rowType == "panel" and state.sourcePanelIds[row.id] then
            DimDraggedRow(state, row)
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
    if state.kind == "group" or state.kind == "multi-group" then
        FinishCol1GroupDrag(state)
    elseif state.kind == "rail-panel" then
        FinishRailPanelDrag(state)
    end
end

local function StartDragTracking()
    -- Every drag source reaches here from its own mouse-DOWN, so a new press can
    -- never inherit an Escape-cancel mark left behind by an earlier drag whose
    -- release went to a frame that had no chance to claim it.
    CS.dragEscapeCancelledMouseUp = nil
    if not CS.dragTracker then
        CS.dragTracker = CreateFrame("Frame", nil, UIParent)
    end
    CS.dragTracker:SetScript("OnUpdate", function(_, elapsed)
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
                -- A drag is now in hand, so Escape belongs to it. Every exit
                -- from here runs through CancelDrag, which hides this again.
                ShowDragEscapeCatcher()
                if CS.dragState.kind == "layout-slot"
                    and CS.dragState.layoutDrag
                    and CS.dragState.layoutDrag.onActivate then
                    CS.dragState.layoutDrag.onActivate(CS.dragState)
                end
                -- Dim source widget(s)
                if CS.dragState.kind == "multi-group" and CS.dragState.sourceGroupIds then
                    for _, row in ipairs(CS.dragState.col1RenderedRows) do
                        if row.kind == "container" and CS.dragState.sourceGroupIds[row.id] then
                            DimDraggedRow(CS.dragState, row)
                        end
                    end
                elseif CS.dragState.kind == "rail-panel" and CS.dragState.sourcePanelIds then
                    for _, row in ipairs(CS.dragState.railPanelRows or {}) do
                        if row.kind == "aux-block"
                            and row.rowType == "panel"
                            and CS.dragState.sourcePanelIds[row.id] then
                            DimDraggedRow(CS.dragState, row)
                        end
                    end
                elseif CS.dragState.kind == "group" and CS.dragState.col1RenderedRows then
                    for _, row in ipairs(CS.dragState.col1RenderedRows) do
                        if row.kind == "container" and row.id == CS.dragState.sourceGroupId then
                            DimDraggedRow(CS.dragState, row)
                            break
                        end
                    end
                elseif CS.dragState.widget and CS.dragState.kind ~= "layout-slot" then
                    -- A layout drag owns its own alpha: onActivate above already
                    -- took the dragged slot to 0 (the cursor ghost stands in for
                    -- it), so dimming here would record that 0 as the pre-drag
                    -- alpha and restore it over onCancel's reset, leaving the
                    -- slot invisible. The other layout surface sidesteps this by
                    -- passing no widget at all; this one needs it for the ghost.
                    DimDraggedWidget(CS.dragState, CS.dragState.widget)
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
                            for _, row in ipairs(CS.dragState.col1RenderedRows) do
                                if row.kind == "container" and savedSourceGroupIds[row.id] then
                                    DimDraggedRow(CS.dragState, row)
                                end
                            end
                        else
                            for _, row in ipairs(CS.dragState.col1RenderedRows) do
                                if savedKind == "group" and row.kind == "container" and row.id == savedSourceGroupId then
                                    CS.dragState.widget = row.widget
                                    DimDraggedRow(CS.dragState, row)
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
        if CS.dragState.phase == "active" then
            -- Scroll BEFORE resolving a target, so the target reflects the
            -- geometry the user is actually looking at this frame.
            local dragKind = CS.dragState.kind
            if (dragKind == "group" or dragKind == "multi-group" or dragKind == "rail-panel")
                and (CS.dragState.col1RenderedRows or CS.dragState.railPanelRows)
            then
                UpdateCol1DragAutoscroll(CS.dragState.scrollWidget, cursorX, cursorY, elapsed or 0)
            end
            if CS.dragState.kind == "layout-slot" then
                local dropTarget = CS.dragState.layoutDrag
                    and CS.dragState.layoutDrag.resolveDropTarget
                    and CS.dragState.layoutDrag.resolveDropTarget(cursorX, cursorY, CS.dragState)
                CS.dragState.dropTarget = dropTarget
                if CS.dragState.layoutDrag and CS.dragState.layoutDrag.onUpdate then
                    CS.dragState.layoutDrag.onUpdate(CS.dragState, cursorX, cursorY, dropTarget)
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
                    -- Mid spring-open the destination is still expanding, so the
                    -- rows the line would anchor to are not settled yet.
                    HideDragIndicator()
                else
                    ShowRailPanelDropIndicator(CS.dragState)
                end
            elseif CS.dragState.col1RenderedRows then
                local dropTarget = GetCol1DropTarget(
                    cursorX,
                    cursorY,
                    CS.dragState.scrollWidget,
                    CS.dragState.col1RenderedRows,
                    CS.dragState.sourceSection,
                    CS.dragState.sourceLoadBucket,
                    CS.dragState.sourceGroupId,
                    CS.dragState.sourceGroupIds
                )
                CS.dragState.dropTarget = dropTarget
                ShowCol1DropIndicator(CS.dragState)
            end
        end
    end)
end

------------------------------------------------------------------------
-- ST._ exports (consumed by later Config/ files)
------------------------------------------------------------------------
ST._CancelDrag = CancelDrag
ST._StartDragTracking = StartDragTracking
ST._HideDragIndicator = HideDragIndicator
ST._GetScaledCursorPosition = GetScaledCursorPosition
ST._PerformButtonReorder = PerformButtonReorder
