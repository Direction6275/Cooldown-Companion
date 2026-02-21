--[[
    CooldownCompanion - Config/Column1
    RefreshColumn1 + nested helpers (group list rendering).
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local AceGUI = LibStub("AceGUI-3.0")

-- Imports from earlier Config/ files
local CleanRecycledEntry = ST._CleanRecycledEntry
local SetupGroupRowIndicators = ST._SetupGroupRowIndicators
local GetGroupIcon = ST._GetGroupIcon
local GetFolderIcon = ST._GetFolderIcon
local GenerateFolderName = ST._GenerateFolderName
local ShowPopupAboveConfig = ST._ShowPopupAboveConfig
local CancelDrag = ST._CancelDrag
local StartDragTracking = ST._StartDragTracking
local GetScaledCursorPosition = ST._GetScaledCursorPosition

------------------------------------------------------------------------
-- COLUMN 1: Groups
------------------------------------------------------------------------
local function RefreshColumn1(preserveDrag)
    if not CS.col1Scroll then return end
    if not preserveDrag then CancelDrag() end
    CS.col1Scroll:ReleaseChildren()

    -- Hide all accent bars from previous render
    for i, bar in ipairs(CS.folderAccentBars) do
        bar:Hide()
        bar:ClearAllPoints()
    end
    local accentBarIndex = 0  -- pool cursor, incremented as bars are used

    local db = CooldownCompanion.db.profile
    local charKey = CooldownCompanion.db.keys.char

    -- Ensure folders table exists
    if not db.folders then db.folders = {} end

    -- Count current children in scroll widget
    local function CountScrollChildren()
        local children = { CS.col1Scroll.content:GetChildren() }
        return #children
    end

    -- Track all rendered rows for drag system: sequential index -> metadata
    local col1RenderedRows = {}

    -- Build top-level items for a section (folders + loose groups), sorted by order
    local function BuildSectionItems(section, sectionGroupIds)
        -- Collect folders for this section
        local sectionFolderIds = {}
        for fid, folder in pairs(db.folders) do
            if folder.section == section then
                -- Character folders: only show if owned by current character
                if section == "char" and folder.createdBy and folder.createdBy ~= charKey then
                    -- skip: belongs to another character
                else
                    table.insert(sectionFolderIds, fid)
                end
            end
        end

        -- Determine which groups are in valid folders for this section
        local validFolderIds = {}
        for _, fid in ipairs(sectionFolderIds) do
            validFolderIds[fid] = true
        end

        -- Split groups: those in a valid folder vs loose
        local looseGroupIds = {}
        local folderChildGroups = {}  -- [folderId] = { groupId, ... }
        for _, gid in ipairs(sectionGroupIds) do
            local group = db.groups[gid]
            if group.folderId and validFolderIds[group.folderId] then
                if not folderChildGroups[group.folderId] then
                    folderChildGroups[group.folderId] = {}
                end
                table.insert(folderChildGroups[group.folderId], gid)
            else
                table.insert(looseGroupIds, gid)
            end
        end

        -- Sort folder children by group order
        for fid, children in pairs(folderChildGroups) do
            table.sort(children, function(a, b)
                local orderA = db.groups[a].order or a
                local orderB = db.groups[b].order or b
                return orderA < orderB
            end)
        end

        -- Build top-level items list: folders + loose groups
        local items = {}
        for _, fid in ipairs(sectionFolderIds) do
            table.insert(items, { kind = "folder", id = fid, order = db.folders[fid].order or fid })
        end
        for _, gid in ipairs(looseGroupIds) do
            table.insert(items, { kind = "group", id = gid, order = db.groups[gid].order or gid })
        end
        table.sort(items, function(a, b) return a.order < b.order end)

        return items, folderChildGroups
    end

    -- Shift label right to make room for mode badge after UpdateImageAnchor reflows
    local MODE_BADGE_W = 18
    local function ApplyModeBadgeOffset(widget)
        local lbl = widget.label
        for i = 1, lbl:GetNumPoints() do
            local pt, rel, relPt, x, y = lbl:GetPoint(i)
            if rel == widget.image then
                lbl:SetPoint(pt, rel, relPt, (x or 0) + MODE_BADGE_W, y or 0)
                lbl:SetWidth(lbl:GetWidth() - MODE_BADGE_W)
                return
            end
        end
    end

    -- Helper: render a single group row (reused by both sections)
    local function RenderGroupRow(groupId, inFolder, sectionTag)
        local group = db.groups[groupId]
        if not group then return end

        local entry = AceGUI:Create("InteractiveLabel")
        -- Clean recycled widget sub-elements before setup
        CleanRecycledEntry(entry)
        entry:SetText(group.name)
        entry:SetImage("Interface\\BUTTONS\\WHITE8X8")
        entry:SetImageSize(inFolder and 13 or 1, 30)  -- extra width indents folder children
        entry.image:SetAlpha(0)
        entry:SetFullWidth(true)
        entry:SetFontObject(GameFontHighlight)
        entry:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")

        -- Color: blue for multi-selected, green for selected, gray for disabled, default otherwise
        if CS.selectedGroups[groupId] then
            entry:SetColor(0.4, 0.7, 1.0)
        elseif CS.selectedGroup == groupId then
            entry:SetColor(0, 1, 0)
        elseif group.enabled == false then
            entry:SetColor(0.5, 0.5, 0.5)
        end

        CS.col1Scroll:AddChild(entry)

        -- Mode badge between group icon and label text (reuse texture from recycled widget)
        local modeBadge = entry._cdcModeBadge
        if not modeBadge then
            modeBadge = entry.frame:CreateTexture(nil, "ARTWORK")
            entry._cdcModeBadge = modeBadge
        end
        modeBadge:ClearAllPoints()
        modeBadge:SetTexture(nil)
        modeBadge:SetTexCoord(0, 1, 0, 1)
        modeBadge:SetSize(14, 14)
        if group.displayMode == "bars" then
            modeBadge:SetAtlas("CreditsScreen-Assets-Buttons-Pause")
        else
            modeBadge:SetAtlas("UI-QuestPoi-QuestNumber-SuperTracked")
        end
        modeBadge:SetPoint("LEFT", entry.image, "RIGHT", 2, 0)
        modeBadge:Show()
        -- Hook OnWidthSet so badge offset survives UpdateImageAnchor reflows (once per widget)
        if not entry._cdcWidthHooked then
            entry._cdcWidthHooked = true
            hooksecurefunc(entry, "OnWidthSet", function(self)
                if self._cdcModeBadge and self._cdcModeBadge:IsShown() then
                    ApplyModeBadgeOffset(self)
                end
            end)
        end
        -- Apply offset now (first layout already ran before hook was installed)
        ApplyModeBadgeOffset(entry)

        SetupGroupRowIndicators(entry, group)

        -- Neutralize built-in OnClick so mousedown doesn't fire
        entry:SetCallback("OnClick", function() end)

        -- Handle clicks via OnMouseUp
        entry.frame:SetScript("OnMouseUp", function(self, button)
            if CS.dragState and CS.dragState.phase == "active" then return end
            if button == "LeftButton" then
                if IsShiftKeyDown() then
                    if CS.specExpandedGroupId == groupId then
                        CS.specExpandedGroupId = nil
                    else
                        CS.specExpandedGroupId = groupId
                    end
                    CooldownCompanion:RefreshConfigPanel()
                    return
                elseif IsControlKeyDown() then
                    -- Ctrl+click: toggle multi-select
                    if CS.selectedGroups[groupId] then
                        CS.selectedGroups[groupId] = nil
                    else
                        CS.selectedGroups[groupId] = true
                    end
                    -- Auto-promote current single selection into multi-select
                    if CS.selectedGroup and not CS.selectedGroups[CS.selectedGroup] and next(CS.selectedGroups) then
                        CS.selectedGroups[CS.selectedGroup] = true
                    end
                    CS.selectedGroup = nil
                    CS.selectedButton = nil
                    wipe(CS.selectedButtons)
                    CooldownCompanion:RefreshConfigPanel()
                    return
                end
                -- Normal click: toggle selection, clear multi-select
                wipe(CS.selectedGroups)
                if CS.selectedGroup == groupId then
                    CS.selectedGroup = nil
                else
                    CS.selectedGroup = groupId
                end
                CS.selectedButton = nil
                wipe(CS.selectedButtons)
                CS.castBarPanelActive = false
                CS.frameAnchoringPanelActive = false
                CooldownCompanion:StopCastBarPreview()
                CooldownCompanion:RefreshConfigPanel()
            elseif button == "RightButton" then
                if not CS.groupContextMenu then
                    CS.groupContextMenu = CreateFrame("Frame", "CDCGroupContextMenu", UIParent, "UIDropDownMenuTemplate")
                end
                UIDropDownMenu_Initialize(CS.groupContextMenu, function(self, level, menuList)
                    level = level or 1
                    if level == 1 then
                        -- Rename
                        local info = UIDropDownMenu_CreateInfo()
                        info.text = "Rename"
                        info.notCheckable = true
                        info.func = function()
                            CloseDropDownMenus()
                            ShowPopupAboveConfig("CDC_RENAME_GROUP", group.name, { groupId = groupId })
                        end
                        UIDropDownMenu_AddButton(info, level)

                        -- Toggle Global
                        info = UIDropDownMenu_CreateInfo()
                        info.text = group.isGlobal and "Make Character-Only" or "Make Global"
                        info.notCheckable = true
                        info.func = function()
                            CloseDropDownMenus()
                            if group.isGlobal and group.specs then
                                local hasForeign = false
                                local numSpecs = GetNumSpecializations()
                                local playerSpecIds = {}
                                for i = 1, numSpecs do
                                    local specId = C_SpecializationInfo.GetSpecializationInfo(i)
                                    if specId then playerSpecIds[specId] = true end
                                end
                                for specId in pairs(group.specs) do
                                    if not playerSpecIds[specId] then
                                        hasForeign = true
                                        break
                                    end
                                end
                                if hasForeign then
                                    ShowPopupAboveConfig("CDC_UNGLOBAL_GROUP", group.name, { groupId = groupId })
                                    return
                                end
                            end
                            CooldownCompanion:ToggleGroupGlobal(groupId)
                            CooldownCompanion:RefreshConfigPanel()
                        end
                        UIDropDownMenu_AddButton(info, level)

                        -- Move to Folder submenu
                        local groupSection = group.isGlobal and "global" or "char"
                        local hasFolders = false
                        for fid, folder in pairs(db.folders) do
                            if folder.section == groupSection then
                                hasFolders = true
                                break
                            end
                        end
                        if hasFolders or group.folderId then
                            info = UIDropDownMenu_CreateInfo()
                            info.text = "Move to Folder"
                            info.notCheckable = true
                            info.hasArrow = true
                            info.menuList = "MOVE_TO_FOLDER"
                            UIDropDownMenu_AddButton(info, level)
                        end

                        -- Toggle On/Off
                        info = UIDropDownMenu_CreateInfo()
                        info.text = (group.enabled ~= false) and "Disable" or "Enable"
                        info.notCheckable = true
                        info.func = function()
                            CloseDropDownMenus()
                            group.enabled = not (group.enabled ~= false)
                            CooldownCompanion:RefreshGroupFrame(groupId)
                            CooldownCompanion:RefreshConfigPanel()
                        end
                        UIDropDownMenu_AddButton(info, level)

                        -- Duplicate
                        info = UIDropDownMenu_CreateInfo()
                        info.text = "Duplicate"
                        info.notCheckable = true
                        info.func = function()
                            CloseDropDownMenus()
                            local newGroupId = CooldownCompanion:DuplicateGroup(groupId)
                            if newGroupId then
                                CS.selectedGroup = newGroupId
                                CooldownCompanion:RefreshConfigPanel()
                            end
                        end
                        UIDropDownMenu_AddButton(info, level)

                        -- Lock/Unlock
                        info = UIDropDownMenu_CreateInfo()
                        info.text = group.locked and "Unlock" or "Lock"
                        info.notCheckable = true
                        info.func = function()
                            CloseDropDownMenus()
                            group.locked = not group.locked
                            CooldownCompanion:RefreshGroupFrame(groupId)
                            CooldownCompanion:RefreshConfigPanel()
                        end
                        UIDropDownMenu_AddButton(info, level)

                        -- Spec Filter
                        info = UIDropDownMenu_CreateInfo()
                        info.text = "Spec Filter"
                        info.notCheckable = true
                        info.func = function()
                            CloseDropDownMenus()
                            if CS.specExpandedGroupId == groupId then
                                CS.specExpandedGroupId = nil
                            else
                                CS.specExpandedGroupId = groupId
                            end
                            CooldownCompanion:RefreshConfigPanel()
                        end
                        UIDropDownMenu_AddButton(info, level)

                        -- Switch display mode
                        info = UIDropDownMenu_CreateInfo()
                        info.text = group.displayMode == "bars" and "Switch to Icons" or "Switch to Bars"
                        info.notCheckable = true
                        info.func = function()
                            CloseDropDownMenus()
                            local wasBars = group.displayMode == "bars"
                            group.displayMode = wasBars and "icons" or "bars"
                            if not wasBars then
                                group.style.orientation = "vertical"
                            end
                            if group.displayMode == "bars" and group.masqueEnabled then
                                CooldownCompanion:ToggleGroupMasque(groupId, false)
                            end
                            CooldownCompanion:RefreshGroupFrame(groupId)
                            CooldownCompanion:RefreshConfigPanel()
                        end
                        UIDropDownMenu_AddButton(info, level)

                        -- Delete
                        info = UIDropDownMenu_CreateInfo()
                        info.text = "|cffff4444Delete|r"
                        info.notCheckable = true
                        info.func = function()
                            CloseDropDownMenus()
                            local name = group and group.name or "this group"
                            ShowPopupAboveConfig("CDC_DELETE_GROUP", name, { groupId = groupId })
                        end
                        UIDropDownMenu_AddButton(info, level)
                    elseif menuList == "MOVE_TO_FOLDER" then
                        -- "(No Folder)" option
                        local info = UIDropDownMenu_CreateInfo()
                        info.text = "(No Folder)"
                        info.checked = (group.folderId == nil)
                        info.func = function()
                            CloseDropDownMenus()
                            CooldownCompanion:MoveGroupToFolder(groupId, nil)
                            CooldownCompanion:RefreshConfigPanel()
                        end
                        UIDropDownMenu_AddButton(info, level)

                        -- List all folders in this group's section
                        local groupSection = group.isGlobal and "global" or "char"
                        local folderList = {}
                        for fid, folder in pairs(db.folders) do
                            if folder.section == groupSection then
                                table.insert(folderList, { id = fid, name = folder.name, order = folder.order or fid })
                            end
                        end
                        table.sort(folderList, function(a, b) return a.order < b.order end)
                        for _, f in ipairs(folderList) do
                            info = UIDropDownMenu_CreateInfo()
                            info.text = f.name
                            info.checked = (group.folderId == f.id)
                            info.func = function()
                                CloseDropDownMenus()
                                CooldownCompanion:MoveGroupToFolder(groupId, f.id)
                                CooldownCompanion:RefreshConfigPanel()
                            end
                            UIDropDownMenu_AddButton(info, level)
                        end
                    end
                end, "MENU")
                CS.groupContextMenu:SetFrameStrata("FULLSCREEN_DIALOG")
                ToggleDropDownMenu(1, nil, CS.groupContextMenu, "cursor", 0, 0)
                return
            elseif button == "MiddleButton" then
                group.locked = not group.locked
                CooldownCompanion:RefreshGroupFrame(groupId)
                CooldownCompanion:RefreshConfigPanel()
                return
            end
        end)

        -- Tag entry frame with metadata for drag system
        entry.frame._cdcItemKind = "group"
        entry.frame._cdcGroupId = groupId
        entry.frame._cdcInFolder = inFolder and group.folderId or nil
        entry.frame._cdcSection = sectionTag

        -- Track in rendered rows list
        local rowIndex = #col1RenderedRows + 1
        col1RenderedRows[rowIndex] = {
            kind = "group",
            id = groupId,
            widget = entry,
            inFolder = inFolder and group.folderId or nil,
            section = sectionTag,
        }

        -- Inline spec filter panel (expanded via Shift+Left-click)
        if CS.specExpandedGroupId == groupId then
            local numSpecs = GetNumSpecializations()
            for i = 1, numSpecs do
                local specId, name, _, icon = C_SpecializationInfo.GetSpecializationInfo(i)
                local cb = AceGUI:Create("CheckBox")
                cb:SetLabel(name)
                cb:SetImage(icon, 0.08, 0.92, 0.08, 0.92)
                cb:SetFullWidth(true)
                cb:SetValue(group.specs and group.specs[specId] or false)
                cb:SetCallback("OnValueChanged", function(widget, event, value)
                    if value then
                        if not group.specs then group.specs = {} end
                        group.specs[specId] = true
                    else
                        if group.specs then
                            group.specs[specId] = nil
                            if not next(group.specs) then
                                group.specs = nil
                            end
                        end
                    end
                    CooldownCompanion:RefreshGroupFrame(groupId)
                    CooldownCompanion:RefreshConfigPanel()
                end)
                CS.col1Scroll:AddChild(cb)
                if inFolder then
                    cb.checkbg:SetPoint("TOPLEFT", 12, 0)
                end
            end

            local playerSpecIds = {}
            for i = 1, numSpecs do
                local specId = C_SpecializationInfo.GetSpecializationInfo(i)
                if specId then playerSpecIds[specId] = true end
            end

            local foreignSpecs = {}
            if group.specs then
                for specId in pairs(group.specs) do
                    if not playerSpecIds[specId] then
                        table.insert(foreignSpecs, specId)
                    end
                end
            end

            if #foreignSpecs > 0 then
                table.sort(foreignSpecs)
                for _, specId in ipairs(foreignSpecs) do
                    local _, name, _, icon = GetSpecializationInfoForSpecID(specId)
                    if name then
                        local fcb = AceGUI:Create("CheckBox")
                        fcb:SetLabel(name)
                        if icon then fcb:SetImage(icon, 0.08, 0.92, 0.08, 0.92) end
                        fcb:SetFullWidth(true)
                        fcb:SetValue(true)
                        fcb:SetCallback("OnValueChanged", function(widget, event, value)
                            if not value then
                                if group.specs then
                                    group.specs[specId] = nil
                                    if not next(group.specs) then
                                        group.specs = nil
                                    end
                                end
                            else
                                if not group.specs then group.specs = {} end
                                group.specs[specId] = true
                            end
                            CooldownCompanion:RefreshGroupFrame(groupId)
                            CooldownCompanion:RefreshConfigPanel()
                        end)
                        CS.col1Scroll:AddChild(fcb)
                        if inFolder then
                            fcb.checkbg:SetPoint("TOPLEFT", 12, 0)
                        end
                    end
                end
            end

            local clearBtn = AceGUI:Create("Button")
            clearBtn:SetText("Clear All")
            clearBtn:SetFullWidth(true)
            clearBtn:SetCallback("OnClick", function()
                group.specs = nil
                CooldownCompanion:RefreshGroupFrame(groupId)
                CooldownCompanion:RefreshConfigPanel()
            end)
            CS.col1Scroll:AddChild(clearBtn)
        end

        -- Hold-click drag reorder via handler-table HookScript pattern
        local entryFrame = entry.frame
        if not entryFrame._cdcDragHooked then
            entryFrame._cdcDragHooked = true
            entryFrame:HookScript("OnMouseDown", function(self, mouseBtn)
                if self._cdcOnMouseDown then self._cdcOnMouseDown(self, mouseBtn) end
            end)
        end
        entryFrame._cdcOnMouseDown = function(self, button)
            if button == "LeftButton" and not IsShiftKeyDown() and not IsControlKeyDown() then
                local isMulti = next(CS.selectedGroups) and CS.selectedGroups[groupId]
                local cursorY = GetScaledCursorPosition(CS.col1Scroll)
                CS.dragState = {
                    kind = isMulti and "multi-group" or (inFolder and "folder-group" or "group"),
                    phase = "pending",
                    sourceGroupId = groupId,
                    sourceGroupIds = isMulti and CopyTable(CS.selectedGroups) or nil,
                    sourceSection = sectionTag,
                    sourceFolderId = inFolder and group.folderId or nil,
                    scrollWidget = CS.col1Scroll,
                    widget = entry,
                    startY = cursorY,
                    col1RenderedRows = col1RenderedRows,
                }
                StartDragTracking()
            end
        end

        return entry
    end

    -- Helper: render a folder header row
    local function RenderFolderRow(folderId, sectionTag)
        local folder = db.folders[folderId]
        if not folder then return end

        local isCollapsed = CS.collapsedFolders[folderId]

        -- Collapse indicator as inline texture in label
        local collapseTag = isCollapsed
            and "  |A:common-icon-plus:10:10|a"
            or "  |A:common-icon-minus:10:10|a"

        local entry = AceGUI:Create("InteractiveLabel")
        CleanRecycledEntry(entry)
        entry:SetText(folder.name .. collapseTag)
        entry:SetImage(GetFolderIcon(folderId, db))
        entry:SetImageSize(32, 32)
        entry:SetFullWidth(true)
        entry:SetFontObject(GameFontHighlight)
        entry:SetColor(1.0, 0.82, 0.0)
        entry:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        CS.col1Scroll:AddChild(entry)

        -- Tag entry frame with metadata for drag system
        entry.frame._cdcItemKind = "folder"
        entry.frame._cdcFolderId = folderId
        entry.frame._cdcSection = sectionTag

        -- Track in rendered rows list
        local rowIndex = #col1RenderedRows + 1
        col1RenderedRows[rowIndex] = {
            kind = "folder",
            id = folderId,
            widget = entry,
            section = sectionTag,
        }

        -- Neutralize built-in OnClick so mousedown doesn't fire
        entry:SetCallback("OnClick", function() end)

        -- Handle clicks via OnMouseUp
        entry.frame:SetScript("OnMouseUp", function(self, button)
            if CS.dragState and CS.dragState.phase == "active" then return end
            if button == "LeftButton" then
                CS.collapsedFolders[folderId] = not CS.collapsedFolders[folderId]
                CooldownCompanion:RefreshConfigPanel()
            elseif button == "MiddleButton" then
                local anyLocked = false
                for gid, g in pairs(db.groups) do
                    if g.folderId == folderId and g.locked then
                        anyLocked = true
                        break
                    end
                end
                local newState = not anyLocked
                for gid, g in pairs(db.groups) do
                    if g.folderId == folderId then
                        g.locked = newState
                        CooldownCompanion:RefreshGroupFrame(gid)
                    end
                end
                CooldownCompanion:RefreshConfigPanel()
                return
            elseif button == "RightButton" then
                if not CS.folderContextMenu then
                    CS.folderContextMenu = CreateFrame("Frame", "CDCFolderContextMenu", UIParent, "UIDropDownMenuTemplate")
                end
                UIDropDownMenu_Initialize(CS.folderContextMenu, function(self, level)
                    -- Rename
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = "Rename"
                    info.notCheckable = true
                    info.func = function()
                        CloseDropDownMenus()
                        ShowPopupAboveConfig("CDC_RENAME_FOLDER", folder.name, { folderId = folderId })
                    end
                    UIDropDownMenu_AddButton(info, level)

                    -- Toggle Global/Character
                    info = UIDropDownMenu_CreateInfo()
                    info.text = folder.section == "global" and "Make Character Folder" or "Make Global Folder"
                    info.notCheckable = true
                    info.func = function()
                        CloseDropDownMenus()
                        CooldownCompanion:ToggleFolderGlobal(folderId)
                        CooldownCompanion:RefreshConfigPanel()
                    end
                    UIDropDownMenu_AddButton(info, level)

                    -- Lock All / Unlock All
                    local anyLocked = false
                    for gid, g in pairs(db.groups) do
                        if g.folderId == folderId and g.locked then
                            anyLocked = true
                            break
                        end
                    end
                    info = UIDropDownMenu_CreateInfo()
                    info.text = anyLocked and "Unlock All" or "Lock All"
                    info.notCheckable = true
                    info.func = function()
                        CloseDropDownMenus()
                        local newState = not anyLocked
                        for gid, g in pairs(db.groups) do
                            if g.folderId == folderId then
                                g.locked = newState
                                CooldownCompanion:RefreshGroupFrame(gid)
                            end
                        end
                        CooldownCompanion:RefreshConfigPanel()
                    end
                    UIDropDownMenu_AddButton(info, level)

                    -- Delete
                    info = UIDropDownMenu_CreateInfo()
                    info.text = "|cffff4444Delete Folder|r"
                    info.notCheckable = true
                    info.func = function()
                        CloseDropDownMenus()
                        ShowPopupAboveConfig("CDC_DELETE_FOLDER", folder.name, { folderId = folderId })
                    end
                    UIDropDownMenu_AddButton(info, level)
                end, "MENU")
                CS.folderContextMenu:SetFrameStrata("FULLSCREEN_DIALOG")
                ToggleDropDownMenu(1, nil, CS.folderContextMenu, "cursor", 0, 0)
            end
        end)

        -- Drag support for folder header
        local entryFrame = entry.frame
        if not entryFrame._cdcDragHooked then
            entryFrame._cdcDragHooked = true
            entryFrame:HookScript("OnMouseDown", function(self, mouseBtn)
                if self._cdcOnMouseDown then self._cdcOnMouseDown(self, mouseBtn) end
            end)
        end
        entryFrame._cdcOnMouseDown = function(self, button)
            if button == "LeftButton" and not IsShiftKeyDown() then
                local cursorY = GetScaledCursorPosition(CS.col1Scroll)
                CS.dragState = {
                    kind = "folder",
                    phase = "pending",
                    sourceFolderId = folderId,
                    sourceSection = sectionTag,
                    scrollWidget = CS.col1Scroll,
                    widget = entry,
                    startY = cursorY,
                    col1RenderedRows = col1RenderedRows,
                }
                StartDragTracking()
            end
        end
    end

    -- Render a section (global or character)
    local function RenderSection(section, sectionGroupIds, headingText)
        local items, folderChildGroups = BuildSectionItems(section, sectionGroupIds)
        local isEmpty = #items == 0 and not next(folderChildGroups)
        if isEmpty and not CS.showPhantomSections then return end

        local heading = AceGUI:Create("Heading")
        heading:SetText(headingText)
        heading:SetFullWidth(true)

        if section == "char" then
            local cc = C_ClassColor.GetClassColor(select(2, UnitClass("player")))
            if cc then heading.label:SetTextColor(cc.r, cc.g, cc.b) end
        end
        CS.col1Scroll:AddChild(heading)

        if isEmpty and CS.showPhantomSections then
            local placeholder = AceGUI:Create("Label")
            placeholder:SetText("|cff888888Drop here to move|r")
            placeholder:SetFullWidth(true)
            CS.col1Scroll:AddChild(placeholder)
            local rowIndex = #col1RenderedRows + 1
            col1RenderedRows[rowIndex] = {
                kind = "phantom",
                widget = placeholder,
                section = section,
            }
            return
        end

        -- Class color for accent bars
        local classColor = C_ClassColor.GetClassColor(select(2, UnitClass("player")))

        for _, item in ipairs(items) do
            if item.kind == "folder" then
                RenderFolderRow(item.id, section)
                -- If expanded, render children with accent bar
                if not CS.collapsedFolders[item.id] then
                    local children = folderChildGroups[item.id]
                    if children and #children > 0 then
                        local firstEntry, lastEntry
                        for _, gid in ipairs(children) do
                            local entry = RenderGroupRow(gid, true, section)
                            if entry then
                                if not firstEntry then firstEntry = entry end
                                lastEntry = entry
                            end
                        end
                        -- Create accent bar spanning all child rows
                        if firstEntry and lastEntry and classColor then
                            accentBarIndex = accentBarIndex + 1
                            local bar = CS.folderAccentBars[accentBarIndex]
                            if not bar then
                                bar = CS.col1Scroll.content:CreateTexture(nil, "ARTWORK")
                                CS.folderAccentBars[accentBarIndex] = bar
                            end
                            bar:SetColorTexture(classColor.r, classColor.g, classColor.b, 0.8)
                            bar:SetWidth(3)
                            bar:ClearAllPoints()
                            bar:SetPoint("TOPLEFT", firstEntry.frame, "TOPLEFT", 0, 0)
                            bar:SetPoint("BOTTOMLEFT", lastEntry.frame, "BOTTOMLEFT", 0, 0)
                            bar:Show()
                        end
                    end
                end
            else
                RenderGroupRow(item.id, false, section)
            end
        end
    end

    -- Split groups into global and character-owned
    local globalIds = {}
    local charIds = {}
    for id, group in pairs(db.groups) do
        if group.isGlobal then
            table.insert(globalIds, id)
        elseif group.createdBy == charKey then
            table.insert(charIds, id)
        end
    end

    -- Render sections
    if #globalIds > 0 or next(db.folders) or CS.showPhantomSections then
        -- Check if there are any global folders
        local hasGlobalContent = #globalIds > 0
        if not hasGlobalContent then
            for _, folder in pairs(db.folders) do
                if folder.section == "global" then
                    hasGlobalContent = true
                    break
                end
            end
        end
        if hasGlobalContent or CS.showPhantomSections then
            RenderSection("global", globalIds, "|cff66aaff" .. "Global Groups" .. "|r")
        end
    end

    local charName = charKey:match("^(.-)%s*%-") or charKey
    -- Always show character section (even if empty, folders might exist)
    local hasCharContent = #charIds > 0
    if not hasCharContent then
        for _, folder in pairs(db.folders) do
            if folder.section == "char" and (not folder.createdBy or folder.createdBy == charKey) then
                hasCharContent = true
                break
            end
        end
    end
    if hasCharContent or CS.showPhantomSections then
        RenderSection("char", charIds, charName .. "'s Groups")
    end

    CS.lastCol1RenderedRows = col1RenderedRows

    -- Refresh the static button bar at the bottom
    if CS.col1ButtonBar then
        for _, widget in ipairs(CS.col1BarWidgets) do
            widget:Release()
        end
        wipe(CS.col1BarWidgets)

        -- Helper: generate a unique group name with the given base
        local function GenerateGroupName(base)
            local db = CooldownCompanion.db.profile
            local existing = {}
            for _, g in pairs(db.groups) do
                existing[g.name] = true
            end
            local name = base
            if existing[name] then
                local n = 1
                while existing[name .. " " .. n] do
                    n = n + 1
                end
                name = name .. " " .. n
            end
            return name
        end

        -- Top row: "New Icon Group" (left) | "New Bar Group" (right)
        local newIconBtn = AceGUI:Create("Button")
        newIconBtn:SetText("New Icon Group")
        newIconBtn:SetCallback("OnClick", function()
            local groupId = CooldownCompanion:CreateGroup(GenerateGroupName("New Group"))
            CS.selectedGroup = groupId
            CS.selectedButton = nil
            wipe(CS.selectedButtons)
            CooldownCompanion:RefreshConfigPanel()
        end)
        newIconBtn.frame:SetParent(CS.col1ButtonBar)
        newIconBtn.frame:ClearAllPoints()
        newIconBtn.frame:SetPoint("TOPLEFT", CS.col1ButtonBar, "TOPLEFT", 0, -1)
        newIconBtn.frame:SetPoint("RIGHT", CS.col1ButtonBar, "CENTER", -2, 0)
        newIconBtn.frame:SetHeight(28)
        newIconBtn.frame:Show()
        table.insert(CS.col1BarWidgets, newIconBtn)

        local newBarBtn = AceGUI:Create("Button")
        newBarBtn:SetText("New Bar Group")
        newBarBtn:SetCallback("OnClick", function()
            local groupId = CooldownCompanion:CreateGroup(GenerateGroupName("New Group"))
            local group = CooldownCompanion.db.profile.groups[groupId]
            group.displayMode = "bars"
            group.style.orientation = "vertical"
            if group.masqueEnabled then
                CooldownCompanion:ToggleGroupMasque(groupId, false)
            end
            CooldownCompanion:RefreshGroupFrame(groupId)
            CS.selectedGroup = groupId
            CS.selectedButton = nil
            wipe(CS.selectedButtons)
            CooldownCompanion:RefreshConfigPanel()
        end)
        newBarBtn.frame:SetParent(CS.col1ButtonBar)
        newBarBtn.frame:ClearAllPoints()
        newBarBtn.frame:SetPoint("TOPLEFT", CS.col1ButtonBar, "TOP", 2, -1)
        newBarBtn.frame:SetPoint("TOPRIGHT", CS.col1ButtonBar, "TOPRIGHT", 0, 0)
        newBarBtn.frame:SetHeight(28)
        newBarBtn.frame:Show()
        table.insert(CS.col1BarWidgets, newBarBtn)

        -- Bottom row: "New Folder" (full width)
        local newFolderBtn = AceGUI:Create("Button")
        newFolderBtn:SetText("New Folder")
        newFolderBtn:SetCallback("OnClick", function()
            local folderId = CooldownCompanion:CreateFolder(GenerateFolderName("New Folder"), "char")
            CooldownCompanion:RefreshConfigPanel()
        end)
        newFolderBtn.frame:SetParent(CS.col1ButtonBar)
        newFolderBtn.frame:ClearAllPoints()
        newFolderBtn.frame:SetPoint("BOTTOMLEFT", CS.col1ButtonBar, "BOTTOMLEFT", 0, 0)
        newFolderBtn.frame:SetPoint("BOTTOMRIGHT", CS.col1ButtonBar, "BOTTOMRIGHT", 0, 0)
        newFolderBtn.frame:SetHeight(28)
        newFolderBtn.frame:Show()
        table.insert(CS.col1BarWidgets, newFolderBtn)
    end
end

------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
ST._RefreshColumn1 = RefreshColumn1
