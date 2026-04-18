local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

local ColorHeading = ST._ColorHeading
local BuildGroupExportData = ST._BuildGroupExportData
local BuildContainerExportData = ST._BuildContainerExportData
local EncodeExportData = ST._EncodeExportData

local function GroupUsesTriggerPanelEntries(group)
    return group and group.displayMode == "trigger"
end

function ST._RefreshButtonSettingsMultiSelect(scroll, multiCount, multiIndices, uniformType)
    for _, btn in ipairs(CS.buttonSettingsInfoButtons) do
        btn:ClearAllPoints()
        btn:Hide()
        btn:SetParent(nil)
    end
    wipe(CS.buttonSettingsInfoButtons)

    local heading = AceGUI:Create("Heading")
    heading:SetText(multiCount .. " Selected")
    ColorHeading(heading)
    heading:SetFullWidth(true)
    scroll:AddChild(heading)

    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    local isTriggerPanel = GroupUsesTriggerPanelEntries(group)

    local dupBtn = AceGUI:Create("Button")
    dupBtn:SetText("Duplicate Selected")
    dupBtn:SetFullWidth(true)
    dupBtn:SetCallback("OnClick", function()
        local sourceGroupId = CS.selectedGroup
        local sourceGroup = CooldownCompanion.db.profile.groups[sourceGroupId]
        if not sourceGroup then return end
        local sorted = {}
        for _, idx in ipairs(multiIndices) do
            table.insert(sorted, idx)
        end
        table.sort(sorted, function(a, b) return a > b end)
        for _, idx in ipairs(sorted) do
            local copy = CopyTable(sourceGroup.buttons[idx])
            table.insert(sourceGroup.buttons, idx + 1, copy)
        end
        CooldownCompanion:RefreshGroupFrame(sourceGroupId)
        CS.selectedButton = nil
        wipe(CS.selectedButtons)
        CooldownCompanion:RefreshConfigPanel()
    end)
    scroll:AddChild(dupBtn)

    local spacer1 = AceGUI:Create("Label")
    spacer1:SetText(" ")
    spacer1:SetFullWidth(true)
    local font, _, flags = spacer1.label:GetFont()
    spacer1:SetFont(font, 3, flags or "")
    scroll:AddChild(spacer1)

    local moveBtn = AceGUI:Create("Button")
    moveBtn:SetText("Move Selected")
    moveBtn:SetFullWidth(true)
    moveBtn:SetCallback("OnClick", function()
        local moveMenuFrame = _G["CDCMoveMenu"]
        if not moveMenuFrame then
            moveMenuFrame = CreateFrame("Frame", "CDCMoveMenu", UIParent, "UIDropDownMenuTemplate")
        end
        local sourceGroupId = CS.selectedGroup
        local indices = multiIndices
        local db = CooldownCompanion.db.profile
        UIDropDownMenu_Initialize(moveMenuFrame, function(self, level)
            local containers = db.groupContainers or {}
            local folderGroups, looseGroups = {}, {}
            for id, groupInfo in pairs(db.groups) do
                if id ~= sourceGroupId and CooldownCompanion:IsGroupVisibleToCurrentChar(id) then
                    local groupName = groupInfo.name or ("Group " .. id)
                    local cid = groupInfo.parentContainerId
                    local container = cid and containers[cid]
                    local fid = container and container.folderId
                    if fid and db.folders[fid] then
                        folderGroups[fid] = folderGroups[fid] or {}
                        table.insert(folderGroups[fid], { id = id, name = groupName })
                    else
                        table.insert(looseGroups, { id = id, name = groupName })
                    end
                end
            end
            local sortedFolders = {}
            for fid, folder in pairs(db.folders) do
                if folderGroups[fid] then
                    table.insert(sortedFolders, {
                        id = fid,
                        name = folder.name or ("Folder " .. fid),
                        order = CooldownCompanion:GetOrderForSpec(folder, CooldownCompanion._currentSpecId, fid),
                    })
                end
            end
            table.sort(sortedFolders, function(a, b) return a.order < b.order end)
            local hasFolders = #sortedFolders > 0
            for _, folder in ipairs(sortedFolders) do
                local hdr = UIDropDownMenu_CreateInfo()
                hdr.text = folder.name
                hdr.isTitle = true
                hdr.notCheckable = true
                UIDropDownMenu_AddButton(hdr, level)
                table.sort(folderGroups[folder.id], function(a, b) return a.name < b.name end)
                for _, groupEntry in ipairs(folderGroups[folder.id]) do
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = groupEntry.name
                    info.func = function()
                        for _, idx in ipairs(indices) do
                            table.insert(db.groups[groupEntry.id].buttons, db.groups[sourceGroupId].buttons[idx])
                        end
                        table.sort(indices, function(a, b) return a > b end)
                        for _, idx in ipairs(indices) do
                            table.remove(db.groups[sourceGroupId].buttons, idx)
                        end
                        CooldownCompanion:RefreshGroupFrame(groupEntry.id)
                        CooldownCompanion:RefreshGroupFrame(sourceGroupId)
                        CS.selectedButton = nil
                        wipe(CS.selectedButtons)
                        CooldownCompanion:RefreshConfigPanel()
                        CloseDropDownMenus()
                    end
                    UIDropDownMenu_AddButton(info, level)
                end
            end
            if #looseGroups > 0 then
                if hasFolders then
                    local hdr = UIDropDownMenu_CreateInfo()
                    hdr.text = "No Folder"
                    hdr.isTitle = true
                    hdr.notCheckable = true
                    UIDropDownMenu_AddButton(hdr, level)
                end
                table.sort(looseGroups, function(a, b) return a.name < b.name end)
                for _, groupEntry in ipairs(looseGroups) do
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = groupEntry.name
                    info.func = function()
                        for _, idx in ipairs(indices) do
                            table.insert(db.groups[groupEntry.id].buttons, db.groups[sourceGroupId].buttons[idx])
                        end
                        table.sort(indices, function(a, b) return a > b end)
                        for _, idx in ipairs(indices) do
                            table.remove(db.groups[sourceGroupId].buttons, idx)
                        end
                        CooldownCompanion:RefreshGroupFrame(groupEntry.id)
                        CooldownCompanion:RefreshGroupFrame(sourceGroupId)
                        CS.selectedButton = nil
                        wipe(CS.selectedButtons)
                        CooldownCompanion:RefreshConfigPanel()
                        CloseDropDownMenus()
                    end
                    UIDropDownMenu_AddButton(info, level)
                end
            end
        end, "MENU")
        moveMenuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        ToggleDropDownMenu(1, nil, moveMenuFrame, "cursor", 0, 0)
    end)
    scroll:AddChild(moveBtn)

    local spacer2 = AceGUI:Create("Label")
    spacer2:SetText(" ")
    spacer2:SetFullWidth(true)
    local font2, _, flags2 = spacer2.label:GetFont()
    spacer2:SetFont(font2, 3, flags2 or "")
    scroll:AddChild(spacer2)

    local delBtn = AceGUI:Create("Button")
    delBtn:SetText("Delete Selected")
    delBtn:SetFullWidth(true)
    delBtn:SetCallback("OnClick", function()
        CS.ShowPopupAboveConfig("CDC_DELETE_SELECTED_BUTTONS", multiCount, {
            groupId = CS.selectedGroup,
            indices = multiIndices,
        })
    end)
    scroll:AddChild(delBtn)

    if uniformType and group and not isTriggerPanel then
        local visSpacer = AceGUI:Create("Label")
        visSpacer:SetText(" ")
        visSpacer:SetFullWidth(true)
        scroll:AddChild(visSpacer)

        local repData = group.buttons[multiIndices[1]]
        if repData then
            ST._BuildVisibilitySettings(scroll, repData, CS.buttonSettingsInfoButtons, {
                group = group,
                uniformType = uniformType,
            })
            if CooldownCompanion.db.profile.hideInfoButtons then
                for _, btn in ipairs(CS.buttonSettingsInfoButtons) do
                    btn:Hide()
                end
            end
        end
    end
end

function ST._RefreshPanelMultiSelect(scroll, multiCount, multiPanelIds)
    local db = CooldownCompanion.db.profile
    local containerId = CS.selectedContainer

    local heading = AceGUI:Create("Heading")
    heading:SetText(multiCount .. " Panels Selected")
    ColorHeading(heading)
    heading:SetFullWidth(true)
    scroll:AddChild(heading)

    local function AddSpacer()
        local sp = AceGUI:Create("Label")
        sp:SetText(" ")
        sp:SetFullWidth(true)
        local f, _, fl = sp.label:GetFont()
        sp:SetFont(f, 3, fl or "")
        scroll:AddChild(sp)
    end

    local anyDisabled = false
    for _, pid in ipairs(multiPanelIds) do
        local panel = db.groups[pid]
        if panel and panel.enabled == false then
            anyDisabled = true
            break
        end
    end
    local enableBtn = AceGUI:Create("Button")
    enableBtn:SetText(anyDisabled and "Enable All" or "Disable All")
    enableBtn:SetFullWidth(true)
    enableBtn:SetCallback("OnClick", function()
        for _, pid in ipairs(multiPanelIds) do
            local panel = db.groups[pid]
            if panel then
                panel.enabled = anyDisabled and nil or false
                CooldownCompanion:RefreshGroupFrame(pid)
            end
        end
        CooldownCompanion:RefreshConfigPanel()
    end)
    scroll:AddChild(enableBtn)

    AddSpacer()

    local anyUnlocked = false
    for _, pid in ipairs(multiPanelIds) do
        local panel = db.groups[pid]
        if panel and panel.locked == false then
            anyUnlocked = true
            break
        end
    end
    local lockBtn = AceGUI:Create("Button")
    lockBtn:SetText(anyUnlocked and "Lock All" or "Unlock All")
    lockBtn:SetFullWidth(true)
    lockBtn:SetCallback("OnClick", function()
        for _, pid in ipairs(multiPanelIds) do
            local panel = db.groups[pid]
            if panel then
                panel.locked = anyUnlocked and nil or false
                CooldownCompanion:RefreshGroupFrame(pid)
            end
        end
        CooldownCompanion:RefreshConfigPanel()
    end)
    scroll:AddChild(lockBtn)

    AddSpacer()

    local dupBtn = AceGUI:Create("Button")
    dupBtn:SetText("Duplicate Selected")
    dupBtn:SetFullWidth(true)
    dupBtn:SetCallback("OnClick", function()
        for _, pid in ipairs(multiPanelIds) do
            CooldownCompanion:DuplicatePanel(containerId, pid)
        end
        wipe(CS.selectedPanels)
        CooldownCompanion:RefreshConfigPanel()
    end)
    scroll:AddChild(dupBtn)

    AddSpacer()

    local hasOtherContainer = false
    for cid in pairs(db.groupContainers) do
        if cid ~= containerId and CooldownCompanion:IsContainerVisibleToCurrentChar(cid) then
            hasOtherContainer = true
            break
        end
    end
    if hasOtherContainer then
        local moveBtn = AceGUI:Create("Button")
        moveBtn:SetText("Move to Group")
        moveBtn:SetFullWidth(true)
        moveBtn:SetCallback("OnClick", function()
            local moveMenuFrame = _G["CDCPanelMultiMoveMenu"]
            if not moveMenuFrame then
                moveMenuFrame = CreateFrame("Frame", "CDCPanelMultiMoveMenu", UIParent, "UIDropDownMenuTemplate")
            end
            UIDropDownMenu_Initialize(moveMenuFrame, function(self, level)
                local containers = db.groupContainers or {}
                local folderContainers, looseContainers = {}, {}
                for cid, ctr in pairs(containers) do
                    if cid ~= containerId and CooldownCompanion:IsContainerVisibleToCurrentChar(cid) then
                        local name = ctr.name or ("Group " .. cid)
                        local fid = ctr.folderId
                        if fid and db.folders[fid] then
                            folderContainers[fid] = folderContainers[fid] or {}
                            table.insert(folderContainers[fid], {
                                id = cid,
                                name = name,
                                order = CooldownCompanion:GetOrderForSpec(ctr, CooldownCompanion._currentSpecId, cid),
                            })
                        else
                            table.insert(looseContainers, {
                                id = cid,
                                name = name,
                                order = CooldownCompanion:GetOrderForSpec(ctr, CooldownCompanion._currentSpecId, cid),
                            })
                        end
                    end
                end
                local sortedFolders = {}
                for fid, folder in pairs(db.folders) do
                    if folderContainers[fid] then
                        table.insert(sortedFolders, {
                            id = fid,
                            name = folder.name or ("Folder " .. fid),
                            order = CooldownCompanion:GetOrderForSpec(folder, CooldownCompanion._currentSpecId, fid),
                        })
                    end
                end
                table.sort(sortedFolders, function(a, b) return a.order < b.order end)
                local hasFolders = #sortedFolders > 0
                for _, folder in ipairs(sortedFolders) do
                    local hdr = UIDropDownMenu_CreateInfo()
                    hdr.text = folder.name
                    hdr.isTitle = true
                    hdr.notCheckable = true
                    UIDropDownMenu_AddButton(hdr, level)
                    table.sort(folderContainers[folder.id], function(a, b) return a.order < b.order end)
                    for _, container in ipairs(folderContainers[folder.id]) do
                        local info = UIDropDownMenu_CreateInfo()
                        info.text = container.name
                        info.notCheckable = true
                        info.func = function()
                            CloseDropDownMenus()
                            for _, pid in ipairs(multiPanelIds) do
                                CooldownCompanion:MovePanel(pid, container.id)
                            end
                            wipe(CS.selectedPanels)
                            CS.selectedContainer = container.id
                            CooldownCompanion:RefreshConfigPanel()
                        end
                        UIDropDownMenu_AddButton(info, level)
                    end
                end
                if #looseContainers > 0 then
                    if hasFolders then
                        local hdr = UIDropDownMenu_CreateInfo()
                        hdr.text = "No Folder"
                        hdr.isTitle = true
                        hdr.notCheckable = true
                        UIDropDownMenu_AddButton(hdr, level)
                    end
                    table.sort(looseContainers, function(a, b) return a.order < b.order end)
                    for _, container in ipairs(looseContainers) do
                        local info = UIDropDownMenu_CreateInfo()
                        info.text = container.name
                        info.notCheckable = true
                        info.func = function()
                            CloseDropDownMenus()
                            for _, pid in ipairs(multiPanelIds) do
                                CooldownCompanion:MovePanel(pid, container.id)
                            end
                            wipe(CS.selectedPanels)
                            CS.selectedContainer = container.id
                            CooldownCompanion:RefreshConfigPanel()
                        end
                        UIDropDownMenu_AddButton(info, level)
                    end
                end
            end, "MENU")
            moveMenuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
            ToggleDropDownMenu(1, nil, moveMenuFrame, "cursor", 0, 0)
        end)
        scroll:AddChild(moveBtn)

        AddSpacer()
    end

    local exportBtn = AceGUI:Create("Button")
    exportBtn:SetText("Export Selected")
    exportBtn:SetFullWidth(true)
    exportBtn:SetCallback("OnClick", function()
        local containerData = BuildContainerExportData(db.groupContainers[containerId])
        local exportPanels = {}
        for _, pid in ipairs(multiPanelIds) do
            local panel = db.groups[pid]
            if panel then
                local panelData = BuildGroupExportData(panel)
                panelData._originalGroupId = pid
                exportPanels[#exportPanels + 1] = panelData
            end
        end
        local payload = {
            type = "container",
            version = 1,
            container = containerData,
            panels = exportPanels,
            _originalContainerId = containerId,
        }
        local exportString = EncodeExportData(payload)
        CS.ShowPopupAboveConfig("CDC_EXPORT_GROUP", nil, { exportString = exportString })
    end)
    scroll:AddChild(exportBtn)

    AddSpacer()

    local delBtn = AceGUI:Create("Button")
    delBtn:SetText("Delete Selected")
    delBtn:SetFullWidth(true)
    delBtn:SetCallback("OnClick", function()
        local ids = {}
        for _, pid in ipairs(multiPanelIds) do
            ids[#ids + 1] = pid
        end
        CS.ShowPopupAboveConfig("CDC_DELETE_SELECTED_PANELS", multiCount, {
            containerId = containerId,
            panelIds = ids,
        })
    end)
    scroll:AddChild(delBtn)
end
