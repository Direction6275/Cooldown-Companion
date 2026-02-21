--[[
    CooldownCompanion - Config/Column2
    RefreshColumn2, RefreshColumn3, RefreshProfileBar.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local AceGUI = LibStub("AceGUI-3.0")

-- Imports from earlier Config/ files
local CleanRecycledEntry = ST._CleanRecycledEntry
local GetButtonIcon = ST._GetButtonIcon
local GenerateFolderName = ST._GenerateFolderName
local ShowPopupAboveConfig = ST._ShowPopupAboveConfig
local CancelDrag = ST._CancelDrag
local StartDragTracking = ST._StartDragTracking
local GetScaledCursorPosition = ST._GetScaledCursorPosition
local TryAdd = ST._TryAdd
local TryReceiveCursorDrop = ST._TryReceiveCursorDrop
local OnAutocompleteSelect = ST._OnAutocompleteSelect
local SearchAutocomplete = ST._SearchAutocomplete

------------------------------------------------------------------------
-- COLUMN 2: Spells / Items
------------------------------------------------------------------------
local function RefreshColumn2()
    if not CS.col2Scroll then return end
    local col2 = CS.configFrame and CS.configFrame.col2

    -- Resource bar panel mode: take over col2 with resource anchoring panel
    if CS.resourceBarPanelActive then
        CancelDrag()
        CS.HideAutocomplete()
        CS.col2Scroll.frame:Hide()
        if col2 and col2._infoBtn then col2._infoBtn:Hide() end

        if not col2._resourceAnchoringScroll then
            local scroll = AceGUI:Create("ScrollFrame")
            scroll:SetLayout("List")
            scroll.frame:SetParent(col2.content)
            scroll.frame:ClearAllPoints()
            scroll.frame:SetPoint("TOPLEFT", col2.content, "TOPLEFT", 0, 0)
            scroll.frame:SetPoint("BOTTOMRIGHT", col2.content, "BOTTOMRIGHT", 0, 0)
            col2._resourceAnchoringScroll = scroll
        end
        col2._resourceAnchoringScroll:ReleaseChildren()
        col2._resourceAnchoringScroll.frame:Show()
        ST._BuildResourceBarAnchoringPanel(col2._resourceAnchoringScroll)
        return
    end

    -- Hide resource anchoring scroll when not in resource bar mode
    if col2 and col2._resourceAnchoringScroll then
        col2._resourceAnchoringScroll.frame:Hide()
    end
    if col2 and col2._infoBtn then col2._infoBtn:Show() end

    CancelDrag()
    CS.HideAutocomplete()
    CS.col2Scroll.frame:Show()
    CS.col2Scroll:ReleaseChildren()

    -- Multi-group selection: show inline action buttons instead of spell list
    local multiGroupCount = 0
    local multiGroupIds = {}
    for gid in pairs(CS.selectedGroups) do
        multiGroupCount = multiGroupCount + 1
        table.insert(multiGroupIds, gid)
    end
    if multiGroupCount >= 2 then
        local db = CooldownCompanion.db.profile

        local heading = AceGUI:Create("Heading")
        heading:SetText(multiGroupCount .. " Groups Selected")
        local cc = C_ClassColor.GetClassColor(select(2, UnitClass("player")))
        if cc then heading.label:SetTextColor(cc.r, cc.g, cc.b) end
        heading:SetFullWidth(true)
        CS.col2Scroll:AddChild(heading)

        -- Delete Selected
        local delBtn = AceGUI:Create("Button")
        delBtn:SetText("Delete Selected")
        delBtn:SetFullWidth(true)
        delBtn:SetCallback("OnClick", function()
            ShowPopupAboveConfig("CDC_DELETE_SELECTED_GROUPS", multiGroupCount, { groupIds = multiGroupIds })
        end)
        CS.col2Scroll:AddChild(delBtn)

        local spacer1 = AceGUI:Create("Label")
        spacer1:SetText(" ")
        spacer1:SetFullWidth(true)
        local f1, _, fl1 = spacer1.label:GetFont()
        spacer1:SetFont(f1, 3, fl1 or "")
        CS.col2Scroll:AddChild(spacer1)

        -- Move to Folder
        local moveBtn = AceGUI:Create("Button")
        moveBtn:SetText("Move to Folder")
        moveBtn:SetFullWidth(true)
        moveBtn:SetCallback("OnClick", function()
            if not CS.moveMenuFrame then
                CS.moveMenuFrame = CreateFrame("Frame", "CDCMoveMenu", UIParent, "UIDropDownMenuTemplate")
            end
            UIDropDownMenu_Initialize(CS.moveMenuFrame, function(self, level)
                -- "(No Folder)" option
                local info = UIDropDownMenu_CreateInfo()
                info.text = "(No Folder)"
                info.notCheckable = true
                info.func = function()
                    CloseDropDownMenus()
                    for _, gid in ipairs(multiGroupIds) do
                        local g = db.groups[gid]
                        if g then g.folderId = nil end
                    end
                    CooldownCompanion:RefreshConfigPanel()
                end
                UIDropDownMenu_AddButton(info, level)

                -- Collect all folders from both sections
                local folderList = {}
                for fid, folder in pairs(db.folders) do
                    table.insert(folderList, {
                        id = fid,
                        name = folder.name,
                        section = folder.section,
                        order = folder.order or fid,
                    })
                end
                table.sort(folderList, function(a, b)
                    if a.section ~= b.section then
                        return a.section == "global"
                    end
                    return a.order < b.order
                end)

                for _, f in ipairs(folderList) do
                    info = UIDropDownMenu_CreateInfo()
                    local sectionLabel = f.section == "global" and " (Global)" or " (Char)"
                    info.text = f.name .. sectionLabel
                    info.notCheckable = true
                    info.func = function()
                        CloseDropDownMenus()
                        local targetSection = f.section

                        -- Check for foreign specs when moving global→char
                        local hasForeignSpecs = false
                        if targetSection == "char" then
                            local numSpecs = GetNumSpecializations()
                            local playerSpecIds = {}
                            for i = 1, numSpecs do
                                local specId = C_SpecializationInfo.GetSpecializationInfo(i)
                                if specId then playerSpecIds[specId] = true end
                            end
                            for _, gid in ipairs(multiGroupIds) do
                                local g = db.groups[gid]
                                if g and g.isGlobal and g.specs then
                                    for specId in pairs(g.specs) do
                                        if not playerSpecIds[specId] then
                                            hasForeignSpecs = true
                                            break
                                        end
                                    end
                                    if hasForeignSpecs then break end
                                end
                            end
                        end

                        local doMove = function()
                            for _, gid in ipairs(multiGroupIds) do
                                local g = db.groups[gid]
                                if g then
                                    g.folderId = f.id
                                    -- Cross-section: toggle global/char
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
                            CooldownCompanion:RefreshAllGroups()
                            CooldownCompanion:RefreshConfigPanel()
                        end

                        if hasForeignSpecs then
                            ShowPopupAboveConfig("CDC_UNGLOBAL_SELECTED_GROUPS", nil, {
                                groupIds = multiGroupIds,
                                callback = doMove,
                            })
                        else
                            doMove()
                        end
                    end
                    UIDropDownMenu_AddButton(info, level)
                end
            end, "MENU")
            CS.moveMenuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
            ToggleDropDownMenu(1, nil, CS.moveMenuFrame, "cursor", 0, 0)
        end)
        CS.col2Scroll:AddChild(moveBtn)

        local spacer2 = AceGUI:Create("Label")
        spacer2:SetText(" ")
        spacer2:SetFullWidth(true)
        local f2, _, fl2 = spacer2.label:GetFont()
        spacer2:SetFont(f2, 3, fl2 or "")
        CS.col2Scroll:AddChild(spacer2)

        -- Group into New Folder
        local newFolderBtn = AceGUI:Create("Button")
        newFolderBtn:SetText("Group into New Folder")
        newFolderBtn:SetFullWidth(true)
        newFolderBtn:SetCallback("OnClick", function()
            if not CS.moveMenuFrame then
                CS.moveMenuFrame = CreateFrame("Frame", "CDCMoveMenu", UIParent, "UIDropDownMenuTemplate")
            end
            UIDropDownMenu_Initialize(CS.moveMenuFrame, function(self, level)
                for _, entry in ipairs({
                    { text = "New Global Folder", section = "global" },
                    { text = "New Character Folder", section = "char" },
                }) do
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = entry.text
                    info.notCheckable = true
                    info.func = function()
                        CloseDropDownMenus()
                        local targetSection = entry.section

                        -- Check for foreign specs when targeting char section
                        local hasForeignSpecs = false
                        if targetSection == "char" then
                            local numSpecs = GetNumSpecializations()
                            local playerSpecIds = {}
                            for i = 1, numSpecs do
                                local specId = C_SpecializationInfo.GetSpecializationInfo(i)
                                if specId then playerSpecIds[specId] = true end
                            end
                            for _, gid in ipairs(multiGroupIds) do
                                local g = db.groups[gid]
                                if g and g.isGlobal and g.specs then
                                    for specId in pairs(g.specs) do
                                        if not playerSpecIds[specId] then
                                            hasForeignSpecs = true
                                            break
                                        end
                                    end
                                    if hasForeignSpecs then break end
                                end
                            end
                        end

                        local doGroupIntoFolder = function()
                            local folderName = GenerateFolderName("New Folder")
                            local folderId = CooldownCompanion:CreateFolder(folderName, targetSection)
                            for _, gid in ipairs(multiGroupIds) do
                                local g = db.groups[gid]
                                if g then
                                    g.folderId = folderId
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
                            CooldownCompanion:RefreshAllGroups()
                            CooldownCompanion:RefreshConfigPanel()
                        end

                        if hasForeignSpecs then
                            ShowPopupAboveConfig("CDC_UNGLOBAL_SELECTED_GROUPS", nil, {
                                groupIds = multiGroupIds,
                                callback = doGroupIntoFolder,
                            })
                        else
                            doGroupIntoFolder()
                        end
                    end
                    UIDropDownMenu_AddButton(info, level)
                end
            end, "MENU")
            CS.moveMenuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
            ToggleDropDownMenu(1, nil, CS.moveMenuFrame, "cursor", 0, 0)
        end)
        CS.col2Scroll:AddChild(newFolderBtn)

        local spacer3 = AceGUI:Create("Label")
        spacer3:SetText(" ")
        spacer3:SetFullWidth(true)
        local f3, _, fl3 = spacer3.label:GetFont()
        spacer3:SetFont(f3, 3, fl3 or "")
        CS.col2Scroll:AddChild(spacer3)

        -- Make Global / Make Character
        local anyChar = false
        local allGlobal = true
        for _, gid in ipairs(multiGroupIds) do
            local g = db.groups[gid]
            if g then
                if not g.isGlobal then
                    anyChar = true
                    allGlobal = false
                end
            end
        end

        local toggleBtn = AceGUI:Create("Button")
        toggleBtn:SetText(anyChar and "Make All Global" or "Make All Character")
        toggleBtn:SetFullWidth(true)
        toggleBtn:SetCallback("OnClick", function()
            if anyChar then
                -- Make all global
                for _, gid in ipairs(multiGroupIds) do
                    local g = db.groups[gid]
                    if g and not g.isGlobal then
                        g.isGlobal = true
                        g.folderId = nil
                    end
                end
                CooldownCompanion:RefreshAllGroups()
                CooldownCompanion:RefreshConfigPanel()
            else
                -- Make all character — check for foreign specs
                local hasForeignSpecs = false
                local numSpecs = GetNumSpecializations()
                local playerSpecIds = {}
                for i = 1, numSpecs do
                    local specId = C_SpecializationInfo.GetSpecializationInfo(i)
                    if specId then playerSpecIds[specId] = true end
                end
                for _, gid in ipairs(multiGroupIds) do
                    local g = db.groups[gid]
                    if g and g.specs then
                        for specId in pairs(g.specs) do
                            if not playerSpecIds[specId] then
                                hasForeignSpecs = true
                                break
                            end
                        end
                        if hasForeignSpecs then break end
                    end
                end

                local doToggle = function()
                    for _, gid in ipairs(multiGroupIds) do
                        local g = db.groups[gid]
                        if g and g.isGlobal then
                            g.isGlobal = false
                            g.createdBy = CooldownCompanion.db.keys.char
                            g.folderId = nil
                        end
                    end
                    CooldownCompanion:RefreshAllGroups()
                    CooldownCompanion:RefreshConfigPanel()
                end

                if hasForeignSpecs then
                    ShowPopupAboveConfig("CDC_UNGLOBAL_SELECTED_GROUPS", nil, {
                        groupIds = multiGroupIds,
                        callback = doToggle,
                    })
                else
                    doToggle()
                end
            end
        end)
        CS.col2Scroll:AddChild(toggleBtn)

        local spacer4 = AceGUI:Create("Label")
        spacer4:SetText(" ")
        spacer4:SetFullWidth(true)
        local f4, _, fl4 = spacer4.label:GetFont()
        spacer4:SetFont(f4, 3, fl4 or "")
        CS.col2Scroll:AddChild(spacer4)

        -- Lock / Unlock All
        local anyLocked = false
        for _, gid in ipairs(multiGroupIds) do
            local g = db.groups[gid]
            if g and g.locked then
                anyLocked = true
                break
            end
        end

        local lockBtn = AceGUI:Create("Button")
        lockBtn:SetText(anyLocked and "Unlock All" or "Lock All")
        lockBtn:SetFullWidth(true)
        lockBtn:SetCallback("OnClick", function()
            local newState = not anyLocked
            for _, gid in ipairs(multiGroupIds) do
                local g = db.groups[gid]
                if g then
                    g.locked = newState
                    CooldownCompanion:RefreshGroupFrame(gid)
                end
            end
            CooldownCompanion:RefreshConfigPanel()
        end)
        CS.col2Scroll:AddChild(lockBtn)

        return
    end

    if not CS.selectedGroup then
        local label = AceGUI:Create("Label")
        label:SetText("Select a group first")
        label:SetFullWidth(true)
        CS.col2Scroll:AddChild(label)
        return
    end

    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then return end

    -- Input editbox
    local inputBox = AceGUI:Create("EditBox")
    if inputBox.editbox.Instructions then inputBox.editbox.Instructions:Hide() end
    inputBox:SetLabel("")
    inputBox:SetText(CS.newInput)
    inputBox:DisableButton(true)
    inputBox:SetFullWidth(true)
    inputBox:SetCallback("OnEnterPressed", function(widget, event, text)
        if CS.ConsumeAutocompleteEnter() then return end
        CS.HideAutocomplete()
        CS.newInput = text
        if CS.newInput ~= "" and CS.selectedGroup then
            if TryAdd(CS.newInput) then
                CS.newInput = ""
                CooldownCompanion:RefreshConfigPanel()
            end
        end
    end)
    inputBox:SetCallback("OnTextChanged", function(widget, event, text)
        CS.newInput = text
        if text and #text >= 1 then
            local results = SearchAutocomplete(text)
            CS.ShowAutocompleteResults(results, widget, OnAutocompleteSelect)
        else
            CS.HideAutocomplete()
        end
    end)
    inputBox.editbox:SetPoint("BOTTOMRIGHT", 1, 0)
    -- Arrow key / Enter navigation for autocomplete dropdown.
    -- HookScript is necessary because AceGUI has no OnKeyDown callback.
    -- Guarded: only acts when the autocomplete dropdown is visible; no-op otherwise.
    local editboxFrame = inputBox.editbox
    if not editboxFrame._cdcAutocompHooked then
        editboxFrame._cdcAutocompHooked = true
        editboxFrame:HookScript("OnKeyDown", function(self, key)
            CS.HandleAutocompleteKeyDown(key)
        end)
    end
    CS.col2Scroll:AddChild(inputBox)

    if CS.pendingEditBoxFocus then
        CS.pendingEditBoxFocus = false
        C_Timer.After(0, function()
            if inputBox.editbox then
                inputBox:SetFocus()
            end
        end)
    end

    local spacer = AceGUI:Create("SimpleGroup")
    spacer:SetFullWidth(true)
    spacer:SetHeight(2)
    spacer.noAutoHeight = true
    CS.col2Scroll:AddChild(spacer)

    local addBtn = AceGUI:Create("Button")
    addBtn:SetText("Add Spell/Item to Track")
    addBtn:SetFullWidth(true)
    addBtn.frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    addBtn:SetCallback("OnClick", function(_, _, button)
        if button == "RightButton" then
            if InCombatLockdown() then
                CooldownCompanion:Print("Cannot open spellbook during combat.")
                return
            end
            PlayerSpellsUtil.ToggleSpellBookFrame()
            return
        end
        if CS.newInput ~= "" and CS.selectedGroup then
            if TryAdd(CS.newInput) then
                CS.newInput = ""
                CooldownCompanion:RefreshConfigPanel()
            end
        end
    end)
    CS.col2Scroll:AddChild(addBtn)

    -- Separator
    local sep = AceGUI:Create("Heading")
    sep:SetText("")
    local cc = C_ClassColor.GetClassColor(select(2, UnitClass("player")))
    if cc then sep.label:SetTextColor(cc.r, cc.g, cc.b) end
    sep:SetFullWidth(true)
    CS.col2Scroll:AddChild(sep)

    -- Spell/Item list
    -- childOffset = 4 (inputBox, spacer, addBtn, sep are the first 4 children before draggable entries)
    local numButtons = #group.buttons
    for i, buttonData in ipairs(group.buttons) do
        local entry = AceGUI:Create("InteractiveLabel")
        CleanRecycledEntry(entry)
        local usable = CooldownCompanion:IsButtonUsable(buttonData)
        -- Show current spell name via viewer child's overrideSpellID (tracks current form)
        local entryName = buttonData.name
        if buttonData.type == "spell" then
            -- For multi-slot buttons, use the slot-specific CDM child
            local child
            if buttonData.cdmChildSlot then
                local allChildren = CooldownCompanion.viewerAuraAllChildren[buttonData.id]
                child = allChildren and allChildren[buttonData.cdmChildSlot]
            else
                child = CooldownCompanion.viewerAuraFrames[buttonData.id]
            end
            if child and child.cooldownInfo and child.cooldownInfo.overrideSpellID then
                local spellName = C_Spell.GetSpellName(child.cooldownInfo.overrideSpellID)
                if spellName then entryName = spellName end
            else
                local spellName = C_Spell.GetSpellName(buttonData.id)
                if spellName then entryName = spellName end
            end
            -- Append slot number for multi-entry spells
            if buttonData.cdmChildSlot then
                entryName = entryName .. " #" .. buttonData.cdmChildSlot
            end
            -- Append tracking type label (based on how entry was originally added)
            if not buttonData.addedAs then
                -- Backfill for entries created before addedAs was introduced
                buttonData.addedAs = buttonData.auraTracking and "aura" or "spell"
            end
            local addedAs = buttonData.addedAs
            if addedAs == "aura" then
                entryName = entryName .. " (Aura)"
            else
                entryName = entryName .. " (Spell)"
            end
        elseif buttonData.type == "item" then
            if C_Item.IsEquippableItem(buttonData.id) then
                entryName = entryName .. " (Equipment)"
            elseif C_Item.IsConsumableItem(buttonData.id) then
                entryName = entryName .. " (Consumable)"
            else
                entryName = entryName .. " (Item)"
            end
        end
        entry:SetText(entryName or ("Unknown " .. buttonData.type))
        entry:SetImage(GetButtonIcon(buttonData))
        entry:SetImageSize(32, 32)
        entry:SetFullWidth(true)
        entry:SetFontObject(GameFontHighlight)
        entry:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        if CS.selectedButtons[i] then
            entry:SetColor(0.4, 0.7, 1.0)
        elseif CS.selectedButton == i then
            entry:SetColor(0.4, 0.7, 1.0)
        elseif not usable then
            entry:SetColor(0.5, 0.5, 0.5)
        end

        -- Clean up any recycled warning icon, then create if needed
        if entry.frame._cdcWarnBtn then
            entry.frame._cdcWarnBtn:Hide()
        end
        if not usable then
            local warnBtn = entry.frame._cdcWarnBtn
            if not warnBtn then
                warnBtn = CreateFrame("Button", nil, entry.frame)
                warnBtn:SetSize(16, 16)
                warnBtn:SetPoint("RIGHT", entry.frame, "RIGHT", -4, 0)
                local warnIcon = warnBtn:CreateTexture(nil, "OVERLAY")
                warnIcon:SetAtlas("Ping_Marker_Icon_Warning")
                warnIcon:SetAllPoints()
                warnBtn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine("Spell/item unavailable", 1, 0.3, 0.3)
                    GameTooltip:Show()
                end)
                warnBtn:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
                entry.frame._cdcWarnBtn = warnBtn
            end
            warnBtn:SetFrameLevel(entry.frame:GetFrameLevel() + 5)
            warnBtn:Show()
        end

        -- Override badge: show a small icon if button has style overrides
        if entry.frame._cdcOverrideBadge then
            entry.frame._cdcOverrideBadge:Hide()
        end
        if CooldownCompanion:HasStyleOverrides(buttonData) then
            local badge = entry.frame._cdcOverrideBadge
            if not badge then
                badge = CreateFrame("Frame", nil, entry.frame)
                badge:SetSize(16, 16)
                local badgeIcon = badge:CreateTexture(nil, "OVERLAY")
                badgeIcon:SetSize(12, 12)
                badgeIcon:SetPoint("CENTER")
                badgeIcon:SetAtlas("Professions-Icon-Export")
                badge:EnableMouse(true)
                badge:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine("Has appearance overrides")
                    GameTooltip:Show()
                end)
                badge:SetScript("OnLeave", function() GameTooltip:Hide() end)
                entry.frame._cdcOverrideBadge = badge
            end
            -- Position to the left of the warning icon (or right side if no warning)
            badge:ClearAllPoints()
            if not usable and entry.frame._cdcWarnBtn then
                badge:SetPoint("RIGHT", entry.frame._cdcWarnBtn, "LEFT", -2, 0)
            else
                badge:SetPoint("RIGHT", entry.frame, "RIGHT", -4, 0)
            end
            badge:SetFrameLevel(entry.frame:GetFrameLevel() + 5)
            badge:Show()
        end

        -- Neutralize InteractiveLabel's built-in OnClick (Label_OnClick Fire)
        -- so that mousedown doesn't trigger selection; we handle clicks on mouseup instead
        entry:SetCallback("OnClick", function() end)

        -- Handle clicks via OnMouseUp with drag guard
        local entryFrame = entry.frame
        entryFrame:SetScript("OnMouseUp", function(self, button)
            -- If a drag was active, suppress this click
            if CS.dragState and CS.dragState.phase == "active" then return end
            -- If cursor holds a spell/item from spellbook/bags, receive the drop
            if button == "LeftButton" and GetCursorInfo() then
                if TryReceiveCursorDrop() then return end
            end
            if button == "LeftButton" then
                if IsControlKeyDown() then
                    -- Ctrl+click: toggle multi-select
                    if CS.selectedButtons[i] then
                        CS.selectedButtons[i] = nil
                    else
                        CS.selectedButtons[i] = true
                    end
                    -- Include current selectedButton in multi-select if starting fresh
                    if CS.selectedButton and not CS.selectedButtons[CS.selectedButton] and next(CS.selectedButtons) then
                        CS.selectedButtons[CS.selectedButton] = true
                    end
                    CS.selectedButton = nil
                else
                    -- Normal click: toggle single select, clear multi-select
                    wipe(CS.selectedButtons)
                    if CS.selectedButton == i then
                        CS.selectedButton = nil
                    else
                        CS.selectedButton = i
                    end
                end
                CooldownCompanion:RefreshConfigPanel()
            elseif button == "RightButton" then
                if not CS.buttonContextMenu then
                    CS.buttonContextMenu = CreateFrame("Frame", "CDCButtonContextMenu", UIParent, "UIDropDownMenuTemplate")
                end
                local sourceGroupId = CS.selectedGroup
                local sourceIndex = i
                local entryData = buttonData
                UIDropDownMenu_Initialize(CS.buttonContextMenu, function(self, level)
                    -- Duplicate option
                    local dupInfo = UIDropDownMenu_CreateInfo()
                    dupInfo.text = "Duplicate"
                    dupInfo.notCheckable = true
                    dupInfo.func = function()
                        -- Deep copy the button data
                        local copy = {}
                        for k, v in pairs(entryData) do
                            if type(v) == "table" then
                                copy[k] = {}
                                for k2, v2 in pairs(v) do
                                    copy[k][k2] = v2
                                end
                            else
                                copy[k] = v
                            end
                        end
                        -- Insert after current position
                        table.insert(CooldownCompanion.db.profile.groups[sourceGroupId].buttons, sourceIndex + 1, copy)
                        CooldownCompanion:RefreshGroupFrame(sourceGroupId)
                        CooldownCompanion:RefreshConfigPanel()
                        CloseDropDownMenus()
                    end
                    UIDropDownMenu_AddButton(dupInfo, level)
                    -- Remove option
                    local removeInfo = UIDropDownMenu_CreateInfo()
                    removeInfo.text = "Remove"
                    removeInfo.notCheckable = true
                    removeInfo.func = function()
                        CloseDropDownMenus()
                        local name = entryData.name or "this entry"
                        ShowPopupAboveConfig("CDC_DELETE_BUTTON", name, { groupId = sourceGroupId, buttonIndex = sourceIndex })
                    end
                    UIDropDownMenu_AddButton(removeInfo, level)
                end, "MENU")
                CS.buttonContextMenu:SetFrameStrata("FULLSCREEN_DIALOG")
                ToggleDropDownMenu(1, nil, CS.buttonContextMenu, "cursor", 0, 0)
            elseif button == "MiddleButton" then
                if not CS.moveMenuFrame then
                    CS.moveMenuFrame = CreateFrame("Frame", "CDCMoveMenu", UIParent, "UIDropDownMenuTemplate")
                end
                local sourceGroupId = CS.selectedGroup
                local sourceIndex = i
                local entryData = buttonData
                UIDropDownMenu_Initialize(CS.moveMenuFrame, function(self, level)
                    local db = CooldownCompanion.db.profile
                    local groupIds = {}
                    for id in pairs(db.groups) do
                        if CooldownCompanion:IsGroupVisibleToCurrentChar(id) then
                            table.insert(groupIds, id)
                        end
                    end
                    table.sort(groupIds)
                    for _, gid in ipairs(groupIds) do
                        if gid ~= sourceGroupId then
                            local info = UIDropDownMenu_CreateInfo()
                            info.text = db.groups[gid].name
                            info.func = function()
                                table.insert(db.groups[gid].buttons, entryData)
                                table.remove(db.groups[sourceGroupId].buttons, sourceIndex)
                                CooldownCompanion:RefreshGroupFrame(gid)
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
                CS.moveMenuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
                ToggleDropDownMenu(1, nil, CS.moveMenuFrame, "cursor", 0, 0)
            end
        end)

        CS.col2Scroll:AddChild(entry)

        -- Accept spell/item drops on each entry frame
        entryFrame:SetScript("OnReceiveDrag", TryReceiveCursorDrop)

        -- Hold-click drag reorder via handler-table HookScript pattern
        if not entryFrame._cdcDragHooked then
            entryFrame._cdcDragHooked = true
            entryFrame:HookScript("OnMouseDown", function(self, mouseBtn)
                if self._cdcOnMouseDown then self._cdcOnMouseDown(self, mouseBtn) end
            end)
        end
        entryFrame._cdcOnMouseDown = function(self, button)
            -- Don't start internal drag-reorder when cursor holds a spell/item
            if GetCursorInfo() then return end
            if button == "LeftButton" and not IsControlKeyDown() then
                local cursorY = GetScaledCursorPosition(CS.col2Scroll)
                CS.dragState = {
                    kind = "button",
                    phase = "pending",
                    sourceIndex = i,
                    groupId = CS.selectedGroup,
                    scrollWidget = CS.col2Scroll,
                    widget = entry,
                    startY = cursorY,
                    childOffset = 4,
                    totalDraggable = numButtons,
                }
                StartDragTracking()
            end
        end
    end

end


------------------------------------------------------------------------
-- COLUMN 3: Group Settings / Tab Column
------------------------------------------------------------------------
local function RefreshColumn3(container)
    -- Cast Bar panel mode: show cast bar settings instead of group settings
    if CS.castBarPanelActive then
        if container.placeholderLabel then
            container.placeholderLabel:Hide()
        end
        if container.tabGroup then
            container.tabGroup.frame:Hide()
        end
        if container.customAuraScroll then
            container.customAuraScroll.frame:Hide()
        end
        if container.frameAnchoringScroll then
            container.frameAnchoringScroll.frame:Hide()
        end
        -- Create or reuse the cast bar scroll frame
        if not container.castBarScroll then
            local scroll = AceGUI:Create("ScrollFrame")
            scroll:SetLayout("List")
            scroll.frame:SetParent(container)
            scroll.frame:ClearAllPoints()
            scroll.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
            scroll.frame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
            container.castBarScroll = scroll
        end
        container.castBarScroll:ReleaseChildren()
        container.castBarScroll.frame:Show()
        ST._BuildCastBarStylingPanel(container.castBarScroll)
        return
    end
    -- Hide cast bar scroll if it exists
    if container.castBarScroll then
        container.castBarScroll.frame:Hide()
    end

    -- Resource Bar panel mode: show custom aura bar panel instead of group settings
    if CS.resourceBarPanelActive then
        if container.placeholderLabel then
            container.placeholderLabel:Hide()
        end
        if container.tabGroup then
            container.tabGroup.frame:Hide()
        end
        if container.frameAnchoringScroll then
            container.frameAnchoringScroll.frame:Hide()
        end
        if not container.customAuraScroll then
            local scroll = AceGUI:Create("ScrollFrame")
            scroll:SetLayout("List")
            scroll.frame:SetParent(container)
            scroll.frame:ClearAllPoints()
            scroll.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
            scroll.frame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
            container.customAuraScroll = scroll
        end
        container.customAuraScroll:ReleaseChildren()
        container.customAuraScroll.frame:Show()
        ST._BuildCustomAuraBarPanel(container.customAuraScroll)
        return
    end
    -- Hide custom aura scroll if it exists
    if container.customAuraScroll then
        container.customAuraScroll.frame:Hide()
    end

    -- Frame Anchoring panel mode: show target frame settings
    if CS.frameAnchoringPanelActive then
        if container.placeholderLabel then
            container.placeholderLabel:Hide()
        end
        if container.tabGroup then
            container.tabGroup.frame:Hide()
        end
        if not container.frameAnchoringScroll then
            local scroll = AceGUI:Create("ScrollFrame")
            scroll:SetLayout("List")
            scroll.frame:SetParent(container)
            scroll.frame:ClearAllPoints()
            scroll.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
            scroll.frame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
            container.frameAnchoringScroll = scroll
        end
        container.frameAnchoringScroll:ReleaseChildren()
        container.frameAnchoringScroll.frame:Show()
        ST._BuildFrameAnchoringTargetPanel(container.frameAnchoringScroll)
        return
    end
    -- Hide frame anchoring scroll if it exists
    if container.frameAnchoringScroll then
        container.frameAnchoringScroll.frame:Hide()
    end

    -- Multi-group selection: show placeholder
    local multiGroupCount = 0
    for _ in pairs(CS.selectedGroups) do multiGroupCount = multiGroupCount + 1 end
    if multiGroupCount >= 2 then
        if not container.placeholderLabel then
            container.placeholderLabel = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            container.placeholderLabel:SetPoint("TOPLEFT", -1, 0)
        end
        container.placeholderLabel:SetText("Select a single group to configure")
        container.placeholderLabel:Show()
        if container.tabGroup then
            container.tabGroup.frame:Hide()
        end
        return
    end

    if not CS.selectedGroup then
        -- Show placeholder, hide tab group
        if not container.placeholderLabel then
            container.placeholderLabel = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            container.placeholderLabel:SetPoint("TOPLEFT", -1, 0)
        end
        container.placeholderLabel:SetText("Select a group to configure")
        container.placeholderLabel:Show()
        if container.tabGroup then
            container.tabGroup.frame:Hide()
        end
        return
    end

    if container.placeholderLabel then
        container.placeholderLabel:Hide()
    end

    -- Create the TabGroup once, reuse on subsequent refreshes
    if not container.tabGroup then
        local tabGroup = AceGUI:Create("TabGroup")
        tabGroup:SetLayout("Fill")

        tabGroup:SetCallback("OnGroupSelected", function(widget, event, tab)
            CS.selectedTab = tab
            -- Clean up raw (?) info buttons BEFORE releasing children, so they
            -- don't leak onto recycled AceGUI frames when switching tabs
            for _, btn in ipairs(CS.tabInfoButtons) do
                btn:ClearAllPoints()
                btn:Hide()
                btn:SetParent(nil)
            end
            wipe(CS.tabInfoButtons)
            widget:ReleaseChildren()

            local scroll = AceGUI:Create("ScrollFrame")
            scroll:SetLayout("List")
            widget:AddChild(scroll)
            CS.col3Scroll = scroll

            if tab == "appearance" then
                ST._BuildAppearanceTab(scroll)
            elseif tab == "layout" then
                ST._BuildLayoutTab(scroll)
            elseif tab == "effects" then
                ST._BuildEffectsTab(scroll)
            elseif tab == "loadconditions" then
                ST._BuildLoadConditionsTab(scroll)
            end
        end)

        -- Parent the AceGUI widget frame to our raw column frame
        tabGroup.frame:SetParent(container)
        tabGroup.frame:ClearAllPoints()
        tabGroup.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
        tabGroup.frame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)

        container.tabGroup = tabGroup
    end

    -- Update tabs every refresh so the effects tab label reflects current group mode
    local effectsLabel = "Indicators"
    container.tabGroup:SetTabs({
        { value = "appearance",      text = "Appearance" },
        { value = "effects",         text = effectsLabel },
        { value = "layout",          text = "Layout" },
        { value = "loadconditions",  text = "Load Conditions" },
    })

    -- Save AceGUI scroll state before tab re-select (old col3Scroll will be released)
    local savedOffset, savedScrollvalue
    if CS.col3Scroll then
        local s = CS.col3Scroll.status or CS.col3Scroll.localstatus
        if s and s.offset and s.offset > 0 then
            savedOffset = s.offset
            savedScrollvalue = s.scrollvalue
        end
    end

    -- Migrate stale tab keys from previous layout
    if CS.selectedTab == "extras" then CS.selectedTab = "effects" end
    if CS.selectedTab == "positioning" then CS.selectedTab = "layout" end

    -- Show and refresh the tab content (SelectTab fires callback synchronously,
    -- which releases old col3Scroll and creates a new one)
    container.tabGroup.frame:Show()
    container.tabGroup:SelectTab(CS.selectedTab)

    -- Restore scroll state on the new col3Scroll widget.  LayoutFinished has already
    -- scheduled FixScrollOnUpdate for next frame — it will read these values.
    if savedOffset and CS.col3Scroll then
        local s = CS.col3Scroll.status or CS.col3Scroll.localstatus
        if s then
            s.offset = savedOffset
            s.scrollvalue = savedScrollvalue
        end
    end
end

------------------------------------------------------------------------
-- Profile Bar
------------------------------------------------------------------------
local function RefreshProfileBar(bar)
    -- Release tracked AceGUI widgets
    for _, widget in ipairs(CS.profileBarAceWidgets) do
        widget:Release()
    end
    wipe(CS.profileBarAceWidgets)

    local db = CooldownCompanion.db
    local profiles = db:GetProfiles()
    local currentProfile = db:GetCurrentProfile()

    -- Build ordered profile list for AceGUI Dropdown
    local profileList = {}
    for _, name in ipairs(profiles) do
        profileList[name] = name
    end

    -- Profile dropdown (no label, compact)
    local profileDrop = AceGUI:Create("Dropdown")
    profileDrop:SetLabel("")
    profileDrop:SetList(profileList, profiles)
    profileDrop:SetValue(currentProfile)
    profileDrop:SetWidth(150)
    profileDrop:SetCallback("OnValueChanged", function(widget, event, val)
        db:SetProfile(val)
        CS.selectedGroup = nil
        CS.selectedButton = nil
        wipe(CS.selectedButtons)
        wipe(CS.selectedGroups)
        CooldownCompanion:RefreshConfigPanel()
        CooldownCompanion:RefreshAllGroups()
    end)
    profileDrop.frame:SetParent(bar)
    profileDrop.frame:ClearAllPoints()
    profileDrop.frame:SetPoint("LEFT", bar, "LEFT", 0, 0)
    profileDrop.frame:Show()
    table.insert(CS.profileBarAceWidgets, profileDrop)

    -- Helper to create horizontally chained buttons
    local lastAnchor = profileDrop.frame
    local function AddBarButton(text, width, onClick)
        local btn = AceGUI:Create("Button")
        btn:SetText(text)
        btn:SetWidth(width)
        btn:SetCallback("OnClick", onClick)
        btn.frame:SetParent(bar)
        btn.frame:ClearAllPoints()
        btn.frame:SetPoint("LEFT", lastAnchor, "RIGHT", 4, 0)
        btn:SetHeight(22)
        btn.frame:Show()
        table.insert(CS.profileBarAceWidgets, btn)
        lastAnchor = btn.frame
        return btn
    end

    AddBarButton("New", 55, function()
        ShowPopupAboveConfig("CDC_NEW_PROFILE")
    end)

    AddBarButton("Rename", 80, function()
        ShowPopupAboveConfig("CDC_RENAME_PROFILE", currentProfile, { oldName = currentProfile })
    end)

    AddBarButton("Duplicate", 90, function()
        ShowPopupAboveConfig("CDC_DUPLICATE_PROFILE", nil, { source = currentProfile })
    end)

    AddBarButton("Delete", 70, function()
        local allProfiles = db:GetProfiles()
        local isOnly = #allProfiles <= 1
        if isOnly then
            ShowPopupAboveConfig("CDC_RESET_PROFILE", currentProfile, { profileName = currentProfile, isOnly = true })
        else
            ShowPopupAboveConfig("CDC_DELETE_PROFILE", currentProfile, { profileName = currentProfile })
        end
    end)

    AddBarButton("Export", 75, function()
        ShowPopupAboveConfig("CDC_EXPORT_PROFILE")
    end)

    AddBarButton("Import", 75, function()
        ShowPopupAboveConfig("CDC_IMPORT_PROFILE")
    end)
end

------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
ST._RefreshColumn2 = RefreshColumn2
ST._RefreshColumn3 = RefreshColumn3
ST._RefreshProfileBar = RefreshProfileBar
