local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

local ColorHeading = ST._ColorHeading
local ClearConfigButtonSelection = ST._ClearConfigButtonSelection
local ClearConfigPanelMultiSelection = ST._ClearConfigPanelMultiSelection
local ClearConfigContainerMultiSelection = ST._ClearConfigContainerMultiSelection

local function IsContainerVisibleInConfig(containerOrContainerId)
    if CooldownCompanion.ResolveContainerClassScope then
        local scope = CooldownCompanion:ResolveContainerClassScope(containerOrContainerId)
        return scope.isInvalid ~= true
    end
    return CooldownCompanion:IsContainerVisibleToCurrentChar(containerOrContainerId)
end

local function CanAllPanelsMoveToContainer(panelIds, containerId)
    if not IsContainerVisibleInConfig(containerId) then
        return false
    end
    if not CooldownCompanion.CanMovePanelToContainer then
        return true
    end
    for _, panelId in ipairs(panelIds or {}) do
        local ok = CooldownCompanion:CanMovePanelToContainer(panelId, containerId)
        if not ok then
            return false
        end
    end
    return true
end

local function CanMoveEntryToGroup(sourceGroupId, targetGroupId)
    if CooldownCompanion.CanMoveEntryToGroup then
        return CooldownCompanion:CanMoveEntryToGroup(sourceGroupId, targetGroupId) == true
    end
    return CooldownCompanion:IsGroupVisibleToCurrentChar(targetGroupId)
end

local function GroupUsesTriggerPanelEntries(group)
    return group and group.displayMode == "trigger"
end

local function GetManualMoveRejectMessage(group, count, entries)
    if CooldownCompanion.GetPanelManualEntryRejectMessage then
        local message = CooldownCompanion:GetPanelManualEntryRejectMessage(group, entries)
        if message then
            return message
        end
    end
    if group and group.displayMode == "textures" and (count or 0) > 1 then
        return "Texture Panels can only hold one entry. Move one entry at a time."
    end
    return nil
end

-- The selected entries' buttonData list, for the centralized move
-- compatibility check (primary aura entries can't leave icon/bar panels).
local function CollectSelectedEntryData(db, sourceGroupId, indices)
    local sourceGroup = db and db.groups and db.groups[sourceGroupId]
    if not (sourceGroup and sourceGroup.buttons) then return nil end
    local entries = {}
    for _, idx in ipairs(indices or {}) do
        entries[#entries + 1] = sourceGroup.buttons[idx]
    end
    return entries[1] and entries or nil
end

-- Row-grammar action strips: compact buttons on grammar-height lines (the
-- preset-trio shape in Helpers.lua). Flow insets its single row by 3px top
-- and bottom, so 3 + 24 + 3 centres inside the 30px band, and noAutoHeight
-- keeps Flow's own 27px report from shrinking it back.
local ACTION_STRIP_HEIGHT = (ST._RowGrammar and ST._RowGrammar.ROW_HEIGHT) or 30
local ACTION_STRIP_BUTTON_HEIGHT = 24
local ACTION_STRIP_GUTTER = 4
-- AceGUI Button's own SetAutoWidth rule is "text width + 30px padding"; the
-- shared-width measure below reuses it so the widest button lands exactly
-- where auto width would have put it.
local ACTION_STRIP_TEXT_PAD = 30

-- rows: an ordered list of strips, each an ordered list of { text = ,
-- onClick = }. Every button in the block gets the width of the widest label,
-- so consecutive strips read as aligned columns instead of ragged left-packed
-- lines that look like accidental wrapping. Flow anchors its children from the
-- left, so the block reads as a group instead of a stack of page-wide
-- banners. Flow packs siblings at 0px, so the gutter between buttons is a
-- fixed-size spacer group - the same idiom the preset trio uses. It matches
-- the buttons' height on purpose: Flow offsets each child by (its height / 2)
-- relative to the previous one, so a shorter spacer would make the line step.
local function AddActionStrips(scroll, rows)
    -- Every button is created and labelled up front so the shared width is
    -- known before any strip is assembled; each one is parented below.
    local buttons = {}
    local maxTextWidth = 0
    for _, actions in ipairs(rows) do
        for _, action in ipairs(actions) do
            local btn = AceGUI:Create("Button")
            btn:SetText(action.text)
            btn:SetCallback("OnClick", action.onClick)
            buttons[action] = btn
            local textWidth = btn.text:GetStringWidth()
            if textWidth > maxTextWidth then
                maxTextWidth = textWidth
            end
        end
    end
    local buttonWidth = math.ceil(maxTextWidth) + ACTION_STRIP_TEXT_PAD

    for _, actions in ipairs(rows) do
        local strip = AceGUI:Create("SimpleGroup")
        strip:SetFullWidth(true)
        strip:SetLayout("Flow")
        strip:SetHeight(ACTION_STRIP_HEIGHT)
        strip.noAutoHeight = true

        for index, action in ipairs(actions) do
            if index > 1 then
                local gutter = AceGUI:Create("SimpleGroup")
                gutter:SetWidth(ACTION_STRIP_GUTTER)
                gutter:SetHeight(ACTION_STRIP_BUTTON_HEIGHT)
                gutter.noAutoHeight = true
                strip:AddChild(gutter)
            end

            local btn = buttons[action]
            btn:SetWidth(buttonWidth)
            strip:AddChild(btn)
        end

        -- Added once populated so the List-layout parent computes scroll
        -- height correctly on first render.
        scroll:AddChild(strip)
    end
end

function ST._RefreshButtonSettingsMultiSelect(scroll, multiCount, multiIndices, uniformType)
    for _, btn in ipairs(CS.buttonSettingsInfoButtons) do
        btn:ClearAllPoints()
        btn:Hide()
        btn:SetParent(nil)
    end
    wipe(CS.buttonSettingsInfoButtons)

    -- Informational, not a collapsible section: it names the selection rather
    -- than opening one, so it keeps the centered heading shape.
    local heading = AceGUI:Create("Heading")
    heading:SetText(multiCount .. " Selected")
    ColorHeading(heading)
    heading:SetFullWidth(true)
    scroll:AddChild(heading)

    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    local isTriggerPanel = GroupUsesTriggerPanelEntries(group)

    local function DuplicateSelected()
        local sourceGroupId = CS.selectedGroup
        local sourceGroup = CooldownCompanion.db.profile.groups[sourceGroupId]
        if not sourceGroup then return end
        local sorted = {}
        for _, idx in ipairs(multiIndices) do
            table.insert(sorted, idx)
        end
        table.sort(sorted, function(a, b) return a > b end)
        local previousCount = #sourceGroup.buttons
        for _, idx in ipairs(sorted) do
            local copy = CopyTable(sourceGroup.buttons[idx])
            -- Each copy inherits its original's aura key, which would put two
            -- entries in the same panel on one aura group. A copy also inherits
            -- its original's SECTION, so on a mixed panel it is handed a key of
            -- its own rather than merely stripped.
            CooldownCompanion:AdoptAuraEntryKey(sourceGroup, copy)
            table.insert(sourceGroup.buttons, idx + 1, copy)
        end
        CooldownCompanion:KeepPanelSingleLineOnGrowth(sourceGroup, previousCount)
        CooldownCompanion:RefreshGroupFrame(sourceGroupId)
        ClearConfigButtonSelection()
        CooldownCompanion:RefreshConfigPanel()
    end

    local function ShowMoveMenu()
        local moveMenuFrame = _G["CDCMoveMenu"]
        if not moveMenuFrame then
            moveMenuFrame = CreateFrame("Frame", "CDCMoveMenu", UIParent, "UIDropDownMenuTemplate")
        end
        local sourceGroupId = CS.selectedGroup
        local indices = multiIndices
        local db = CooldownCompanion.db.profile
        local selectedEntries = CollectSelectedEntryData(db, sourceGroupId, indices)
        UIDropDownMenu_Initialize(moveMenuFrame, function(self, level)
            local destinationGroups = {}
            for id, groupInfo in pairs(db.groups) do
                if id ~= sourceGroupId
                    and CanMoveEntryToGroup(sourceGroupId, id)
                    and not GetManualMoveRejectMessage(groupInfo, multiCount, selectedEntries) then
                    table.insert(destinationGroups, {
                        id = id,
                        name = groupInfo.name or ("Group " .. id),
                    })
                end
            end
            table.sort(destinationGroups, function(a, b) return a.name < b.name end)
            for _, groupEntry in ipairs(destinationGroups) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = groupEntry.name
                info.func = function()
                    if not CanMoveEntryToGroup(sourceGroupId, groupEntry.id) then
                        return
                    end
                    local targetGroup = db.groups[groupEntry.id]
                    local rejectMessage = GetManualMoveRejectMessage(targetGroup, multiCount, selectedEntries)
                    if rejectMessage then
                        CooldownCompanion:Print(rejectMessage)
                        return
                    end
                    local previousCount = #targetGroup.buttons
                    for _, idx in ipairs(indices) do
                        local moved = db.groups[sourceGroupId].buttons[idx]
                        -- A section placement belongs to the panel it was made
                        -- on; an entry landing here starts in the base row, and
                        -- the source's cluster dissolves behind the last member
                        -- to leave it.
                        ST.DetachEntryFromPanelSection(db.groups[sourceGroupId], moved)
                        -- After the detach, so the key rule reads the membership
                        -- the entry actually lands with. An Aura Panel mints the
                        -- arrival its own key; anywhere else the key it wore
                        -- where it came from comes off rather than waiting to
                        -- collide inside an aura section.
                        CooldownCompanion:AdoptAuraEntryKey(targetGroup, moved)
                        table.insert(targetGroup.buttons, moved)
                    end
                    table.sort(indices, function(a, b) return a > b end)
                    for _, idx in ipairs(indices) do
                        table.remove(db.groups[sourceGroupId].buttons, idx)
                    end
                    CooldownCompanion:KeepPanelSingleLineOnGrowth(targetGroup, previousCount)
                    CooldownCompanion:RefreshGroupFrame(groupEntry.id)
                    CooldownCompanion:RefreshGroupFrame(sourceGroupId)
                    ClearConfigButtonSelection()
                    CooldownCompanion:RefreshConfigPanel()
                    CloseDropDownMenus()
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end, "MENU")
        moveMenuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        ToggleDropDownMenu(1, nil, moveMenuFrame, "cursor", 0, 0)
    end

    -- Duplicate and Move share a line because both copy or relocate the
    -- selection. Delete is destructive, so it gets its own line rather than
    -- sitting a gutter away from the two harmless actions.
    AddActionStrips(scroll, {
        {
            { text = "Duplicate Selected", onClick = DuplicateSelected },
            { text = "Move Selected", onClick = ShowMoveMenu },
        },
        {
            {
                text = "Delete Selected",
                onClick = function()
                    CS.ShowPopupAboveConfig("CDC_DELETE_SELECTED_BUTTONS", multiCount, {
                        groupId = CS.selectedGroup,
                        indices = multiIndices,
                    })
                end,
            },
        },
    })

    if uniformType and group and not isTriggerPanel then
        local repData = group.buttons[multiIndices[1]]
        if repData then
            -- The same row-grammar Show & Hide Rules / Talent Conditions
            -- sections the Visibility tab draws for one entry, in batch mode:
            -- both stay here so a selection is edited in one place. The
            -- representative entry seeds the tri-state reads and the builders'
            -- ApplyTo* helpers fan every write out across the selection. Its ROW_SECTION
            -- header owns the air above it, so nothing spaces it here.
            ST._BuildVisibilitySettings(scroll, repData, CS.buttonSettingsInfoButtons, {
                group = group,
                uniformType = uniformType,
            })
        end
    end
end

function ST._RefreshGroupMultiSelect(scroll, multiCount, multiGroupIds)
    local db = CooldownCompanion.db.profile

    local heading = AceGUI:Create("Heading")
    heading:SetText(multiCount .. " Groups Selected")
    ColorHeading(heading)
    heading:SetFullWidth(true)
    scroll:AddChild(heading)

    local anyDisabled = false
    local anyUnlocked = false
    for _, containerId in ipairs(multiGroupIds) do
        local container = db.groupContainers[containerId]
        if container then
            if container.enabled == false then
                anyDisabled = true
            end
            if container.locked == false then
                anyUnlocked = true
            end
        end
    end

    local stateActions = {
        {
            text = anyDisabled and "Enable All" or "Disable All",
            onClick = function()
                for _, containerId in ipairs(multiGroupIds) do
                    CooldownCompanion:SetContainerEnabled(containerId, anyDisabled)
                end
                CooldownCompanion:RefreshConfigPanel()
            end,
        },
        {
            text = anyUnlocked and "Lock All" or "Unlock All",
            onClick = function()
                for _, containerId in ipairs(multiGroupIds) do
                    CooldownCompanion:SetContainerLocked(containerId, anyUnlocked)
                end
                CooldownCompanion:RefreshConfigPanel()
                if not anyUnlocked and ST.CollapseConfigForUnlock then
                    ST.CollapseConfigForUnlock()
                elseif anyUnlocked then
                    CooldownCompanion:CheckArrangeModeAutoExit()
                end
            end,
        },
    }

    AddActionStrips(scroll, {
        stateActions,
        {
            {
                text = "Duplicate Selected",
                onClick = function()
                    -- Duplicate in display order (multiGroupIds carries hash
                    -- order); the existence check also keeps a stale id from
                    -- falling through to a panel-id interpretation.
                    local ordered = {}
                    for _, containerId in ipairs(multiGroupIds) do
                        local container = db.groupContainers[containerId]
                        if container then
                            ordered[#ordered + 1] = {
                                cid = containerId,
                                order = CooldownCompanion:GetOrderForSpec(container, CooldownCompanion._currentSpecId, containerId),
                            }
                        end
                    end
                    table.sort(ordered, function(a, b) return a.order < b.order end)
                    local orderedIds = {}
                    for i, item in ipairs(ordered) do
                        orderedIds[i] = item.cid
                    end
                    CooldownCompanion:DuplicateContainers(orderedIds)
                    ClearConfigContainerMultiSelection()
                    CooldownCompanion:RefreshConfigPanel()
                end,
            },
        },
        {
            {
                text = "Delete Selected",
                onClick = function()
                    local ids = {}
                    for _, containerId in ipairs(multiGroupIds) do
                        ids[#ids + 1] = containerId
                    end
                    CS.ShowPopupAboveConfig("CDC_DELETE_SELECTED_GROUPS", multiCount, {
                        groupIds = ids,
                    })
                end,
            },
        },
    })
end

function ST._RefreshPanelMultiSelect(scroll, multiCount, multiPanelIds)
    local db = CooldownCompanion.db.profile
    local containerId = CS.selectedContainer

    -- Informational, not a collapsible section.
    local heading = AceGUI:Create("Heading")
    heading:SetText(multiCount .. " Panels Selected")
    ColorHeading(heading)
    heading:SetFullWidth(true)
    scroll:AddChild(heading)

    local anyDisabled = false
    for _, pid in ipairs(multiPanelIds) do
        local panel = db.groups[pid]
        if panel and panel.enabled == false then
            anyDisabled = true
            break
        end
    end

    local anyUnlocked = false
    for _, pid in ipairs(multiPanelIds) do
        local panel = db.groups[pid]
        if panel
            and panel.locked == false
            and not (CooldownCompanion.IsGroupCursorAnchored and CooldownCompanion:IsGroupCursorAnchored(panel)) then
            anyUnlocked = true
            break
        end
    end

    -- Panel state: the two toggles that flip a flag on every selected panel.
    -- Assembled with the other strips at the bottom of this function so the
    -- whole block shares one button width.
    local stateActions = {
        {
            text = anyDisabled and "Enable All" or "Disable All",
            onClick = function()
                for _, pid in ipairs(multiPanelIds) do
                    local panel = db.groups[pid]
                    if panel then
                        panel.enabled = anyDisabled and true or false
                        CooldownCompanion:RefreshGroupFrame(pid)
                    end
                end
                CooldownCompanion:RefreshConfigPanel()
            end,
        },
        {
            text = anyUnlocked and "Lock All" or "Unlock All",
            onClick = function()
                for _, pid in ipairs(multiPanelIds) do
                    local panel = db.groups[pid]
                    if panel
                        and not (CooldownCompanion.IsGroupCursorAnchored and CooldownCompanion:IsGroupCursorAnchored(panel)) then
                        CooldownCompanion:SetPanelLocked(pid, anyUnlocked)
                    end
                end
                CooldownCompanion:RefreshConfigPanel()
                if not anyUnlocked and ST.CollapseConfigForUnlock then
                    ST.CollapseConfigForUnlock()
                end
            end,
        },
    }

    local hasOtherContainer = false
    for cid in pairs(db.groupContainers) do
        if cid ~= containerId and CanAllPanelsMoveToContainer(multiPanelIds, cid) then
            hasOtherContainer = true
            break
        end
    end

    local function ShowPanelMoveMenu()
        local moveMenuFrame = _G["CDCPanelMultiMoveMenu"]
        if not moveMenuFrame then
            moveMenuFrame = CreateFrame("Frame", "CDCPanelMultiMoveMenu", UIParent, "UIDropDownMenuTemplate")
        end
        UIDropDownMenu_Initialize(moveMenuFrame, function(self, level)
            local containers = db.groupContainers or {}
            local destinations = {}
            for cid, ctr in pairs(containers) do
                if cid ~= containerId and CanAllPanelsMoveToContainer(multiPanelIds, cid) then
                    table.insert(destinations, {
                        id = cid,
                        name = ctr.name or ("Group " .. cid),
                        order = CooldownCompanion:GetOrderForSpec(ctr, CooldownCompanion._currentSpecId, cid),
                    })
                end
            end
            table.sort(destinations, function(a, b) return a.order < b.order end)
            for _, container in ipairs(destinations) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = container.name
                info.notCheckable = true
                info.func = function()
                    CloseDropDownMenus()
                    for _, pid in ipairs(multiPanelIds) do
                        CooldownCompanion:MovePanel(pid, container.id)
                    end
                    ClearConfigPanelMultiSelection({ selectContainerId = container.id })
                    CooldownCompanion:RefreshConfigPanel()
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end, "MENU")
        moveMenuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        ToggleDropDownMenu(1, nil, moveMenuFrame, "cursor", 0, 0)
    end

    -- Everything that produces a copy or relocates the selection, on one line.
    -- Move only appears when there is somewhere to move to, so this strip is
    -- one or two wide.
    local copyActions = {
        { text = "Duplicate Selected", onClick = function()
            for _, pid in ipairs(multiPanelIds) do
                CooldownCompanion:DuplicatePanel(containerId, pid)
            end
            ClearConfigPanelMultiSelection()
            CooldownCompanion:RefreshConfigPanel()
        end },
    }
    if hasOtherContainer then
        copyActions[#copyActions + 1] = { text = "Move to Group", onClick = ShowPanelMoveMenu }
    end

    -- One aligned block: state toggles, then the copy/relocate line, then
    -- Delete - destructive, so it keeps its own line.
    AddActionStrips(scroll, {
        stateActions,
        copyActions,
        {
            {
                text = "Delete Selected",
                onClick = function()
                    local ids = {}
                    for _, pid in ipairs(multiPanelIds) do
                        ids[#ids + 1] = pid
                    end
                    CS.ShowPopupAboveConfig("CDC_DELETE_SELECTED_PANELS", multiCount, {
                        containerId = containerId,
                        panelIds = ids,
                    })
                end,
            },
        },
    })
end
