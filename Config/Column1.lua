--[[
    CooldownCompanion - Config/Column1
    RefreshColumn1 + nested helpers (group list rendering).
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local AceGUI = LibStub("AceGUI-3.0")

-- Imports from earlier Config/ files
local BuildHeroTalentSubTreeCheckboxes = ST._BuildHeroTalentSubTreeCheckboxes
local CleanRecycledEntry = ST._CleanRecycledEntry
local SetupGroupRowIndicators = ST._SetupGroupRowIndicators
local SetupFolderRowIndicators = ST._SetupFolderRowIndicators
local GetGroupIcon = ST._GetGroupIcon
local GetContainerIcon = ST._GetContainerIcon
local GetFolderIcon = ST._GetFolderIcon
local OpenFolderIconPicker = ST._OpenFolderIconPicker
local OpenContainerIconPicker = ST._OpenContainerIconPicker
local IsValidIconTexture = ST._IsValidIconTexture
local GenerateFolderName = ST._GenerateFolderName
local ShowPopupAboveConfig = ST._ShowPopupAboveConfig
local CancelDrag = ST._CancelDrag
local StartDragTracking = ST._StartDragTracking
local GetScaledCursorPosition = ST._GetScaledCursorPosition
local BuildGroupExportData = ST._BuildGroupExportData
local BuildContainerExportData = ST._BuildContainerExportData
local EncodeExportData = ST._EncodeExportData
local ContainersHaveForeignSpecs = ST._ContainersHaveForeignSpecs
local FolderHasForeignSpecs = ST._FolderHasForeignSpecs
local ApplyCheckboxIndent = ST._ApplyCheckboxIndent

------------------------------------------------------------------------
-- Clear all selection state (container, panel, button, multi-select)
------------------------------------------------------------------------
local function ClearSelection()
    CS.selectedContainer = nil
    CS.selectedGroup = nil
    CS.selectedButton = nil
    wipe(CS.selectedButtons)
    wipe(CS.selectedPanels)
end

------------------------------------------------------------------------
-- Browse mode: class-colored name helper
------------------------------------------------------------------------
local function GetClassColoredCharName(charKey, classFilename)
    local name = charKey:match("^(.-)%s*%-") or charKey
    if classFilename then
        local cc = C_ClassColor.GetClassColor(classFilename)
        if cc then
            return cc:WrapTextInColorCode(name), cc
        end
    end
    return name, nil
end

------------------------------------------------------------------------
-- Browse mode: render cross-character browsing UI in Column 1
------------------------------------------------------------------------
local function RenderBrowseMode()
    if not CS.col1Scroll then return end
    CS.col1Scroll:ReleaseChildren()

    -- Hide button bar in browse mode
    if CS.col1ButtonBar then CS.col1ButtonBar:Hide() end

    local db = CooldownCompanion.db.profile

    if not CS.browseCharKey then
        -- Phase A: Character list
        local backBtn = AceGUI:Create("InteractiveLabel")
        CleanRecycledEntry(backBtn)
        backBtn:SetText("|A:common-icon-backarrow:14:14|a  Back to My Groups")
        backBtn:SetImage(134400)
        backBtn:SetImageSize(1, 32)
        backBtn.image:SetAlpha(0)
        backBtn:SetFullWidth(true)
        backBtn:SetFontObject(GameFontHighlight)
        backBtn:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        backBtn:SetCallback("OnClick", function()
            CS.browseMode = false
            CS.browseCharKey = nil
            CS.browseContainerId = nil
            ClearSelection()
            CooldownCompanion:RefreshConfigPanel()
        end)
        CS.col1Scroll:AddChild(backBtn)

        local heading = AceGUI:Create("Heading")
        heading:SetText("Other Characters")
        heading:SetFullWidth(true)
        CS.col1Scroll:AddChild(heading)

        local chars = CooldownCompanion:EnumerateBrowseCharacters()
        if #chars == 0 then
            local emptyLabel = AceGUI:Create("Label")
            emptyLabel:SetText("|cff888888No other characters have groups on this profile.|r")
            emptyLabel:SetFullWidth(true)
            CS.col1Scroll:AddChild(emptyLabel)
            return
        end

        for _, charInfo in ipairs(chars) do
            local entry = AceGUI:Create("InteractiveLabel")
            CleanRecycledEntry(entry)
            local displayName, cc = GetClassColoredCharName(charInfo.charKey, charInfo.classFilename)

            -- Class icon (use individual atlas to avoid tiled-sheet border)
            if charInfo.classFilename then
                entry:SetImage(134400) -- placeholder to initialise image widget
                entry.image:SetAtlas("classicon-" .. strlower(charInfo.classFilename), false)
                entry:SetImageSize(32, 32)
            else
                entry:SetImage(134400)
                entry:SetImageSize(32, 32)
            end

            entry:SetText(displayName)
            entry:SetFullWidth(true)
            entry:SetFontObject(GameFontHighlight)
            entry:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            entry:SetCallback("OnClick", function()
                CS.browseCharKey = charInfo.charKey
                CS.browseContainerId = nil
                ClearSelection()
                CooldownCompanion:RefreshConfigPanel()
            end)
            CS.col1Scroll:AddChild(entry)
        end
    else
        -- Phase B: Selected character's groups
        local backBtn = AceGUI:Create("InteractiveLabel")
        CleanRecycledEntry(backBtn)
        backBtn:SetText("|A:common-icon-backarrow:14:14|a  Back to Characters")
        backBtn:SetImage(134400)
        backBtn:SetImageSize(1, 32)
        backBtn.image:SetAlpha(0)
        backBtn:SetFullWidth(true)
        backBtn:SetFontObject(GameFontHighlight)
        backBtn:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        backBtn:SetCallback("OnClick", function()
            CS.browseCharKey = nil
            CS.browseContainerId = nil
            ClearSelection()
            CooldownCompanion:RefreshConfigPanel()
        end)
        CS.col1Scroll:AddChild(backBtn)

        -- Character heading with class color
        local charInfo = CooldownCompanion.db.global.characterInfo and CooldownCompanion.db.global.characterInfo[CS.browseCharKey]
        local classFilename = charInfo and charInfo.classFilename
        local charName = CS.browseCharKey:match("^(.-)%s*%-") or CS.browseCharKey
        local displayHeading = charName .. "'s Groups"

        local heading = AceGUI:Create("Heading")
        heading:SetText(displayHeading)
        heading:SetFullWidth(true)
        if classFilename then
            local cc = C_ClassColor.GetClassColor(classFilename)
            if cc then heading.label:SetTextColor(cc.r, cc.g, cc.b) end
        end
        CS.col1Scroll:AddChild(heading)

        local containers = CooldownCompanion:GetCharacterContainers(CS.browseCharKey)
        if #containers == 0 then
            local emptyLabel = AceGUI:Create("Label")
            emptyLabel:SetText("|cff888888This character has no groups.|r")
            emptyLabel:SetFullWidth(true)
            CS.col1Scroll:AddChild(emptyLabel)
            return
        end

        for _, item in ipairs(containers) do
            local containerId = item.containerId
            local container = item.container

            local entry = AceGUI:Create("InteractiveLabel")
            CleanRecycledEntry(entry)

            local panelCount = CooldownCompanion:GetPanelCount(containerId)
            local displayName = container.name
            if panelCount > 1 then
                displayName = displayName .. "  |cff888888(" .. panelCount .. " panels)|r"
            end

            entry:SetText(displayName)
            entry:SetImage(GetContainerIcon(containerId, db))
            entry:SetImageSize(32, 32)
            entry:SetFullWidth(true)
            entry:SetFontObject(GameFontHighlight)
            entry:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")

            -- Green highlight for selected browse container
            if CS.browseContainerId == containerId then
                entry:SetColor(0, 1, 0)
            end

            -- Neutralize built-in OnClick
            entry:SetCallback("OnClick", function() end)

            -- Left-click: select for preview; Right-click: copy context menu
            entry.frame:SetScript("OnMouseUp", function(self, button)
                if button == "LeftButton" then
                    if CS.browseContainerId == containerId then
                        CS.browseContainerId = nil
                        CS.selectedContainer = nil
                    else
                        CS.browseContainerId = containerId
                        CS.selectedContainer = containerId
                    end
                    CS.selectedGroup = nil
                    CS.selectedButton = nil
                    wipe(CS.selectedButtons)
                    wipe(CS.selectedPanels)
                    CooldownCompanion:RefreshConfigPanel()
                elseif button == "RightButton" then
                    -- Verify source still exists
                    if not db.groupContainers[containerId] then return end
                    if not CS.browseContextMenu then
                        CS.browseContextMenu = CreateFrame("Frame", "CDCBrowseContextMenu", UIParent, "UIDropDownMenuTemplate")
                    end
                    UIDropDownMenu_Initialize(CS.browseContextMenu, function(self, level)
                        local info = UIDropDownMenu_CreateInfo()
                        info.text = "Copy Entire Group"
                        info.notCheckable = true
                        info.func = function()
                            CloseDropDownMenus()
                            if not db.groupContainers[containerId] then return end
                            local newId = CooldownCompanion:CopyContainerFromBrowse(containerId)
                            if newId then
                                CS.browseMode = false
                                CS.browseCharKey = nil
                                CS.browseContainerId = nil
                                CS.selectedContainer = newId
                                CS.selectedGroup = nil
                                CooldownCompanion:RefreshConfigPanel()
                                CooldownCompanion:Print("Group copied successfully.")
                            end
                        end
                        UIDropDownMenu_AddButton(info, level)
                    end, "MENU")
                    CS.browseContextMenu:SetFrameStrata("FULLSCREEN_DIALOG")
                    ToggleDropDownMenu(1, nil, CS.browseContextMenu, "cursor", 0, 0)
                end
            end)

            CS.col1Scroll:AddChild(entry)
            SetupGroupRowIndicators(entry, container)
        end
    end
end

------------------------------------------------------------------------
-- COLUMN 1: Groups
------------------------------------------------------------------------
local function RefreshColumn1(preserveDrag)
    if not CS.col1Scroll then return end

    -- Bars & Frames panel mode: take over col1 with the bar/frame tab group
    if CS.resourceBarPanelActive then
        CancelDrag()
        CS.HideAutocomplete()
        CS.col1Scroll.frame:Hide()
        if CS.col1ButtonBar then CS.col1ButtonBar:Hide() end

        local col1 = CS.configFrame and CS.configFrame.col1
        if col1 then
            if not col1._barsPanelTabGroup then
                local tabGroup = AceGUI:Create("TabGroup")
                tabGroup:SetTabs({
                    { value = "resource_anchoring", text = "Resources" },
                    { value = "castbar_anchoring",  text = "Cast Bar" },
                    { value = "frame_anchoring",    text = "Unit Frames" },
                })
                tabGroup:SetLayout("Fill")
                tabGroup:SetCallback("OnGroupSelected", function(widget, event, tab)
                    CS.barPanelTab = tab
                    -- Clean up info buttons from previous tab before recycling widgets
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
                    if tab == "resource_anchoring" then
                        ST._BuildResourceBarAnchoringPanel(scroll)
                    elseif tab == "castbar_anchoring" then
                        ST._BuildCastBarAnchoringPanel(scroll)
                    elseif tab == "frame_anchoring" then
                        ST._BuildFrameAnchoringPlayerPanel(scroll)
                        ST._BuildFrameAnchoringTargetPanel(scroll)
                    end
                    ST._RefreshColumn2()
                    ST._RefreshColumn3()
                end)
                tabGroup.frame:SetParent(col1.content)
                tabGroup.frame:ClearAllPoints()
                tabGroup.frame:SetPoint("TOPLEFT", col1.content, "TOPLEFT", 0, 0)
                tabGroup.frame:SetPoint("BOTTOMRIGHT", col1.content, "BOTTOMRIGHT", 0, 0)
                col1._barsPanelTabGroup = tabGroup
            end
            col1._barsPanelTabGroup.frame:Show()
            col1._barsPanelTabGroup:SelectTab(CS.barPanelTab)
        end
        return
    end

    -- Normal mode: hide bars tab group, show groups content
    local col1NormalMode = CS.configFrame and CS.configFrame.col1
    if col1NormalMode and col1NormalMode._barsPanelTabGroup then
        col1NormalMode._barsPanelTabGroup.frame:Hide()
    end
    CS.col1Scroll.frame:Show()

    -- Cross-character browse mode: render browse UI instead of normal groups
    if CS.browseMode then
        if CS.browseBadge then CS.browseBadge:Hide() end
        CancelDrag()
        RenderBrowseMode()
        return
    end

    if CS.col1ButtonBar then CS.col1ButtonBar:Show() end

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

    -- Build top-level items for a section (folders + loose containers), sorted by order
    local function BuildSectionItems(section, sectionContainerIds)
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

        -- Determine which containers are in valid folders for this section
        local validFolderIds = {}
        for _, fid in ipairs(sectionFolderIds) do
            validFolderIds[fid] = true
        end

        -- Split containers: those in a valid folder vs loose
        local looseContainerIds = {}
        local folderChildContainers = {}  -- [folderId] = { containerId, ... }
        for _, cid in ipairs(sectionContainerIds) do
            local container = db.groupContainers[cid]
            if container.folderId and validFolderIds[container.folderId] then
                if not folderChildContainers[container.folderId] then
                    folderChildContainers[container.folderId] = {}
                end
                table.insert(folderChildContainers[container.folderId], cid)
            else
                table.insert(looseContainerIds, cid)
            end
        end

        -- Sort folder children by container order
        for fid, children in pairs(folderChildContainers) do
            table.sort(children, function(a, b)
                local orderA = db.groupContainers[a].order or a
                local orderB = db.groupContainers[b].order or b
                return orderA < orderB
            end)
        end

        -- Build top-level items list: folders + loose containers
        local items = {}
        for _, fid in ipairs(sectionFolderIds) do
            table.insert(items, { kind = "folder", id = fid, order = db.folders[fid].order or fid })
        end
        for _, cid in ipairs(looseContainerIds) do
            table.insert(items, { kind = "container", id = cid, order = db.groupContainers[cid].order or cid })
        end
        table.sort(items, function(a, b) return a.order < b.order end)

        return items, folderChildContainers
    end

    local function IsContainerInactive(containerId, container)
        if not container then return true end
        if container.enabled == false then return true end
        -- Check if container has any panels with buttons
        local hasButtons = false
        for _, group in pairs(db.groups) do
            if group.parentContainerId == containerId and group.buttons and #group.buttons > 0 then
                hasButtons = true
                break
            end
        end
        if not hasButtons then return true end
        -- Check load conditions via any panel (they inherit from container)
        for gid, group in pairs(db.groups) do
            if group.parentContainerId == containerId then
                local active = CooldownCompanion:IsGroupActive(nil, {
                    group = group,
                    requireButtons = true,
                    checkCharVisibility = false,
                    checkLoadConditions = true,
                })
                if active then return false end
            end
        end
        return true
    end

    local function IsFolderFullyInactive(folderId, childContainerIds)
        if not childContainerIds or #childContainerIds == 0 then return true end
        for _, cid in ipairs(childContainerIds) do
            if not IsContainerInactive(cid, db.groupContainers[cid]) then
                return false
            end
        end
        return true
    end

    -- Helper: render a single container row (reused by both sections)
    local function RenderContainerRow(containerId, inFolder, sectionTag)
        local container = db.groupContainers[containerId]
        if not container then return end

        local entry = AceGUI:Create("InteractiveLabel")
        CleanRecycledEntry(entry)
        local isInactive = IsContainerInactive(containerId, container)

        -- Show panel count in name when >1 panel
        local panelCount = CooldownCompanion:GetPanelCount(containerId)
        local displayName = container.name
        if panelCount > 1 then
            displayName = displayName .. "  |cff888888(" .. panelCount .. " panels)|r"
        end

        entry:SetText(displayName)
        if not inFolder and IsValidIconTexture(container.manualIcon) then
            entry:SetImage(container.manualIcon)
            entry:SetImageSize(32, 32)
        else
            entry:SetImage("Interface\\BUTTONS\\WHITE8X8")
            entry:SetImageSize(inFolder and 13 or 1, 30)
            entry.image:SetAlpha(0)
        end
        entry:SetFullWidth(true)
        entry:SetFontObject(GameFontHighlight)
        entry:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")

        -- Color: blue for multi-selected, green for selected, gray for inactive
        if CS.selectedGroups[containerId] then
            entry:SetColor(0.4, 0.7, 1.0)
        elseif CS.selectedContainer == containerId then
            entry:SetColor(0, 1, 0)
        elseif isInactive then
            entry:SetColor(0.5, 0.5, 0.5)
        end

        CS.col1Scroll:AddChild(entry)

        -- No mode badge for containers (panels have individual modes)
        if entry._cdcModeBadge then entry._cdcModeBadge:Hide() end

        SetupGroupRowIndicators(entry, container)

        -- Neutralize built-in OnClick so mousedown doesn't fire
        entry:SetCallback("OnClick", function() end)

        -- Handle clicks via OnMouseUp
        entry.frame:SetScript("OnMouseUp", function(self, button)
            if CS.dragState and CS.dragState.phase == "active" then return end
            if button == "LeftButton" then
                if IsShiftKeyDown() then
                    if CS.specExpandedGroupId == containerId then
                        CS.specExpandedGroupId = nil
                    else
                        CS.specExpandedGroupId = containerId
                        CS.specExpandedFolderId = nil
                    end
                    CooldownCompanion:RefreshConfigPanel()
                    return
                elseif IsControlKeyDown() then
                    -- Ctrl+click: toggle multi-select (container IDs)
                    if CS.selectedGroups[containerId] then
                        CS.selectedGroups[containerId] = nil
                    else
                        CS.selectedGroups[containerId] = true
                    end
                    if CS.selectedContainer and not CS.selectedGroups[CS.selectedContainer] and next(CS.selectedGroups) then
                        CS.selectedGroups[CS.selectedContainer] = true
                    end
                    ClearSelection()
                    CooldownCompanion:RefreshConfigPanel()
                    return
                end
                -- Normal click: toggle-through selection, clear multi-select
                wipe(CS.selectedGroups)
                if CS.selectedContainer == containerId then
                    if CS.selectedGroup then
                        -- First re-click: clear panel selection (return to container settings)
                        CS.selectedGroup = nil
                    else
                        -- Second re-click: deselect container entirely
                        CS.selectedContainer = nil
                    end
                else
                    CS.selectedContainer = containerId
                    CS.selectedGroup = nil
                end
                CS.selectedButton = nil
                wipe(CS.selectedButtons)
                wipe(CS.selectedPanels)
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
                            ShowPopupAboveConfig("CDC_RENAME_GROUP", container.name, { containerId = containerId })
                        end
                        UIDropDownMenu_AddButton(info, level)

                        -- Toggle Global
                        info = UIDropDownMenu_CreateInfo()
                        info.text = container.isGlobal and "Make Character-Only" or "Make Global"
                        info.notCheckable = true
                        info.func = function()
                            CloseDropDownMenus()
                            if container.isGlobal and container.specs
                               and ContainersHaveForeignSpecs({container}, false) then
                                ShowPopupAboveConfig("CDC_UNGLOBAL_GROUP", container.name, { containerId = containerId })
                                return
                            end
                            CooldownCompanion:ToggleGroupGlobal(containerId)
                            CooldownCompanion:RefreshConfigPanel()
                        end
                        UIDropDownMenu_AddButton(info, level)

                        -- Move to Folder submenu
                        local containerSection = container.isGlobal and "global" or "char"
                        local hasFolders = false
                        for fid, folder in pairs(db.folders) do
                            if folder.section == containerSection then
                                if containerSection == "char" and folder.createdBy and folder.createdBy ~= charKey then
                                    -- skip: belongs to another character
                                else
                                    hasFolders = true
                                    break
                                end
                            end
                        end
                        if hasFolders or container.folderId then
                            info = UIDropDownMenu_CreateInfo()
                            info.text = "Move to Folder"
                            info.notCheckable = true
                            info.hasArrow = true
                            info.menuList = "MOVE_TO_FOLDER"
                            UIDropDownMenu_AddButton(info, level)
                        end

                        -- Toggle On/Off
                        info = UIDropDownMenu_CreateInfo()
                        info.text = (container.enabled ~= false) and "Disable" or "Enable"
                        info.notCheckable = true
                        info.func = function()
                            CloseDropDownMenus()
                            container.enabled = not (container.enabled ~= false)
                            CooldownCompanion:RefreshContainerPanels(containerId)
                            CooldownCompanion:RefreshConfigPanel()
                        end
                        UIDropDownMenu_AddButton(info, level)

                        -- Duplicate
                        info = UIDropDownMenu_CreateInfo()
                        info.text = "Duplicate"
                        info.notCheckable = true
                        info.func = function()
                            CloseDropDownMenus()
                            local newContainerId = CooldownCompanion:DuplicateGroup(containerId)
                            if newContainerId then
                                CS.selectedContainer = newContainerId
                                CS.selectedGroup = nil
                                CooldownCompanion:RefreshConfigPanel()
                            end
                        end
                        UIDropDownMenu_AddButton(info, level)

                        -- Export
                        info = UIDropDownMenu_CreateInfo()
                        if next(CS.selectedGroups) then
                            info.text = "Export Selected"
                            info.notCheckable = true
                            info.func = function()
                                CloseDropDownMenus()
                                -- Sort selected containers by order to preserve visual layout
                                local orderedCids = {}
                                for cid in pairs(CS.selectedGroups) do
                                    local c = db.groupContainers[cid]
                                    if c then
                                        orderedCids[#orderedCids + 1] = { cid = cid, order = c.order or cid }
                                    end
                                end
                                table.sort(orderedCids, function(a, b) return a.order < b.order end)
                                local exportContainers = {}
                                for _, item in ipairs(orderedCids) do
                                    local c = db.groupContainers[item.cid]
                                    local containerData = BuildContainerExportData(c)
                                    local sortedPanels = CooldownCompanion:GetPanels(item.cid)
                                    local panels = {}
                                    for _, entry in ipairs(sortedPanels) do
                                        local panelData = BuildGroupExportData(entry.group)
                                        panelData._originalGroupId = entry.groupId
                                        panels[#panels + 1] = panelData
                                    end
                                    exportContainers[#exportContainers + 1] = { container = containerData, panels = panels, _originalContainerId = item.cid }
                                end
                                local payload = { type = "containers", version = 1, containers = exportContainers }
                                local exportString = EncodeExportData(payload)
                                ShowPopupAboveConfig("CDC_EXPORT_GROUP", nil, { exportString = exportString })
                            end
                        else
                            info.text = "Export"
                            info.notCheckable = true
                            info.func = function()
                                CloseDropDownMenus()
                                -- Export container + all panels (sorted by panel order)
                                local sortedPanels = CooldownCompanion:GetPanels(containerId)
                                local panels = {}
                                for _, entry in ipairs(sortedPanels) do
                                    local panelData = BuildGroupExportData(entry.group)
                                    panelData._originalGroupId = entry.groupId
                                    panels[#panels + 1] = panelData
                                end
                                local containerData = BuildContainerExportData(container)
                                local payload = { type = "container", version = 1, container = containerData, panels = panels }
                                local exportString = EncodeExportData(payload)
                                ShowPopupAboveConfig("CDC_EXPORT_GROUP", nil, { exportString = exportString })
                            end
                        end
                        UIDropDownMenu_AddButton(info, level)

                        -- Lock/Unlock
                        info = UIDropDownMenu_CreateInfo()
                        info.text = container.locked and "Unlock" or "Lock"
                        info.notCheckable = true
                        info.func = function()
                            CloseDropDownMenus()
                            container.locked = not container.locked
                            CooldownCompanion:UpdateContainerDragHandle(containerId, container.locked)
                            CooldownCompanion:RefreshContainerPanels(containerId)
                            CooldownCompanion:RefreshConfigPanel()
                        end
                        UIDropDownMenu_AddButton(info, level)

                        -- Auto-Anchoring eligibility toggle
                        do
                            local isCurrentlyEligible
                            if container.isGlobal then
                                isCurrentlyEligible = container.anchorEligible == true
                            else
                                isCurrentlyEligible = container.anchorEligible ~= false
                            end
                            info = UIDropDownMenu_CreateInfo()
                            info.text = isCurrentlyEligible
                                and "Exclude from Auto-Anchoring"
                                or "Include in Auto-Anchoring"
                            info.notCheckable = true
                            info.func = function()
                                CloseDropDownMenus()
                                local fresh = db.groupContainers[containerId]
                                if not fresh then return end
                                if fresh.isGlobal then
                                    fresh.anchorEligible = not fresh.anchorEligible or nil
                                else
                                    if fresh.anchorEligible ~= false then
                                        fresh.anchorEligible = false
                                    else
                                        fresh.anchorEligible = nil
                                    end
                                end
                                CooldownCompanion:EvaluateResourceBars()
                                CooldownCompanion:UpdateAnchorStacking()
                                CooldownCompanion:EvaluateCastBar()
                                CooldownCompanion:EvaluateFrameAnchoring()
                                CooldownCompanion:RefreshConfigPanel()
                            end
                            UIDropDownMenu_AddButton(info, level)
                        end

                        -- Spec Filter
                        info = UIDropDownMenu_CreateInfo()
                        info.text = "Spec Filter"
                        info.notCheckable = true
                        info.func = function()
                            CloseDropDownMenus()
                            if CS.specExpandedGroupId == containerId then
                                CS.specExpandedGroupId = nil
                            else
                                CS.specExpandedGroupId = containerId
                                CS.specExpandedFolderId = nil
                            end
                            CooldownCompanion:RefreshConfigPanel()
                        end
                        UIDropDownMenu_AddButton(info, level)

                        -- Set Group Icon (only for non-foldered containers)
                        if not container.folderId then
                            info = UIDropDownMenu_CreateInfo()
                            info.text = "Set Group Icon..."
                            info.notCheckable = true
                            info.func = function()
                                CloseDropDownMenus()
                                OpenContainerIconPicker(containerId)
                            end
                            UIDropDownMenu_AddButton(info, level)

                            if IsValidIconTexture(container.manualIcon) then
                                info = UIDropDownMenu_CreateInfo()
                                info.text = "Clear Custom Icon"
                                info.notCheckable = true
                                info.func = function()
                                    CloseDropDownMenus()
                                    local fresh = db.groupContainers[containerId]
                                    if fresh then
                                        fresh.manualIcon = nil
                                        CooldownCompanion:RefreshConfigPanel()
                                    end
                                end
                                UIDropDownMenu_AddButton(info, level)
                            end
                        end

                        -- Add Panel submenu
                        info = UIDropDownMenu_CreateInfo()
                        info.text = "Add Panel"
                        info.notCheckable = true
                        info.hasArrow = true
                        info.menuList = "ADD_PANEL"
                        UIDropDownMenu_AddButton(info, level)

                        -- Delete
                        info = UIDropDownMenu_CreateInfo()
                        info.text = "|cffff4444Delete|r"
                        info.notCheckable = true
                        info.func = function()
                            CloseDropDownMenus()
                            ShowPopupAboveConfig("CDC_DELETE_GROUP", container.name, { containerId = containerId })
                        end
                        UIDropDownMenu_AddButton(info, level)
                    elseif menuList == "MOVE_TO_FOLDER" then
                        local info = UIDropDownMenu_CreateInfo()
                        info.text = "(No Folder)"
                        info.checked = (container.folderId == nil)
                        info.func = function()
                            CloseDropDownMenus()
                            CooldownCompanion:MoveGroupToFolder(containerId, nil)
                            CooldownCompanion:RefreshConfigPanel()
                        end
                        UIDropDownMenu_AddButton(info, level)

                        local containerSection = container.isGlobal and "global" or "char"
                        local folderList = {}
                        for fid, folder in pairs(db.folders) do
                            if folder.section == containerSection then
                                if containerSection == "char" and folder.createdBy and folder.createdBy ~= charKey then
                                    -- skip: belongs to another character
                                else
                                    table.insert(folderList, { id = fid, name = folder.name, order = folder.order or fid })
                                end
                            end
                        end
                        table.sort(folderList, function(a, b) return a.order < b.order end)
                        for _, f in ipairs(folderList) do
                            info = UIDropDownMenu_CreateInfo()
                            info.text = f.name
                            info.checked = (container.folderId == f.id)
                            info.func = function()
                                CloseDropDownMenus()
                                CooldownCompanion:MoveGroupToFolder(containerId, f.id)
                                CooldownCompanion:RefreshConfigPanel()
                            end
                            UIDropDownMenu_AddButton(info, level)
                        end
                    elseif menuList == "ADD_PANEL" then
                        local modes = {
                            { mode = "icons", label = "Icon Panel" },
                            { mode = "bars", label = "Bar Panel" },
                            { mode = "text", label = "Text Panel" },
                        }
                        for _, m in ipairs(modes) do
                            local info = UIDropDownMenu_CreateInfo()
                            info.text = m.label
                            info.notCheckable = true
                            local targetMode = m.mode
                            info.func = function()
                                CloseDropDownMenus()
                                local newPanelId = CooldownCompanion:CreatePanel(containerId, targetMode)
                                if newPanelId then
                                    CS.selectedContainer = containerId
                                    CS.selectedGroup = newPanelId
                                    CS.addingToPanelId = newPanelId
                                    CS.pendingEditBoxFocus = true
                                    CooldownCompanion:RefreshConfigPanel()
                                end
                            end
                            UIDropDownMenu_AddButton(info, level)
                        end
                    end
                end, "MENU")
                CS.groupContextMenu:SetFrameStrata("FULLSCREEN_DIALOG")
                ToggleDropDownMenu(1, nil, CS.groupContextMenu, "cursor", 0, 0)
                return
            elseif button == "MiddleButton" then
                container.locked = not container.locked
                CooldownCompanion:UpdateContainerDragHandle(containerId, container.locked)
                CooldownCompanion:RefreshContainerPanels(containerId)
                CooldownCompanion:RefreshConfigPanel()
                return
            end
        end)

        -- Tag entry frame with metadata for drag system
        entry.frame._cdcItemKind = "container"
        entry.frame._cdcGroupId = containerId
        entry.frame._cdcInFolder = inFolder and container.folderId or nil
        entry.frame._cdcSection = sectionTag

        -- Track in rendered rows list
        local rowIndex = #col1RenderedRows + 1
        col1RenderedRows[rowIndex] = {
            kind = "container",
            id = containerId,
            widget = entry,
            inFolder = inFolder and container.folderId or nil,
            section = sectionTag,
        }

        -- Inline spec filter panel (expanded via Shift+Left-click)
        if CS.specExpandedGroupId == containerId then
            local numSpecs = GetNumSpecializations()
            local configID = C_ClassTalents.GetActiveConfigID()
            local htIndent = inFolder and 32 or 20
            local folder = container.folderId and db.folders and db.folders[container.folderId]
            local folderSpecs = folder and folder.specs
            local folderHeroTalents = folder and folder.heroTalents
            local effectiveSpecs
            if folderSpecs or container.specs then
                effectiveSpecs = {}
                if folderSpecs then for k in pairs(folderSpecs) do effectiveSpecs[k] = true end end
                if container.specs then for k in pairs(container.specs) do effectiveSpecs[k] = true end end
                if not next(effectiveSpecs) then effectiveSpecs = nil end
            end
            for i = 1, numSpecs do
                local specId, name, _, icon = C_SpecializationInfo.GetSpecializationInfo(i)
                local lockedByFolder = folderSpecs and folderSpecs[specId]
                local cb = AceGUI:Create("CheckBox")
                cb:SetLabel(name)
                cb:SetImage(icon, 0.08, 0.92, 0.08, 0.92)
                cb:SetFullWidth(true)
                cb:SetValue(lockedByFolder or (container.specs and container.specs[specId]) or false)
                if folderSpecs then
                    cb:SetDisabled(true)
                else
                    cb:SetCallback("OnValueChanged", function(widget, event, value)
                        if value then
                            if not container.specs then container.specs = {} end
                            container.specs[specId] = true
                        else
                            if container.specs then
                                container.specs[specId] = nil
                                if not next(container.specs) then
                                    container.specs = nil
                                end
                            end
                            CooldownCompanion:CleanHeroTalentsForSpec(container, specId)
                        end
                        CooldownCompanion:RefreshContainerPanels(containerId)
                        CooldownCompanion:RefreshConfigPanel()
                    end)
                end
                CS.col1Scroll:AddChild(cb)
                ApplyCheckboxIndent(cb, inFolder and 12 or 0)

                local htOpts = nil
                if folderHeroTalents and next(folderHeroTalents) then
                    htOpts = {
                        heroTalentsSource = folderHeroTalents,
                        useHeroTalentsSource = true,
                        disableToggles = true,
                    }
                end
                htOpts = htOpts or {}
                if effectiveSpecs then
                    htOpts.specsSource = effectiveSpecs
                end
                htOpts.onChanged = function()
                    CooldownCompanion:RefreshContainerPanels(containerId)
                    CooldownCompanion:RefreshConfigPanel()
                end
                BuildHeroTalentSubTreeCheckboxes(CS.col1Scroll, container, configID, specId, htIndent, containerId, htOpts)
            end

            local playerSpecIds = {}
            for i = 1, numSpecs do
                local specId = C_SpecializationInfo.GetSpecializationInfo(i)
                if specId then playerSpecIds[specId] = true end
            end

            local foreignSpecs = {}
            if container.specs then
                for specId in pairs(container.specs) do
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
                                if container.specs then
                                    container.specs[specId] = nil
                                    if not next(container.specs) then
                                        container.specs = nil
                                    end
                                end
                            else
                                if not container.specs then container.specs = {} end
                                container.specs[specId] = true
                            end
                            CooldownCompanion:RefreshContainerPanels(containerId)
                            CooldownCompanion:RefreshConfigPanel()
                        end)
                        CS.col1Scroll:AddChild(fcb)
                        ApplyCheckboxIndent(fcb, inFolder and 12 or 0)
                    end
                end
            end

            local hasOwnSpecs = false
            if container.specs then
                for specId in pairs(container.specs) do
                    if not (folderSpecs and folderSpecs[specId]) then
                        hasOwnSpecs = true
                        break
                    end
                end
            end
            if not hasOwnSpecs and container.heroTalents and next(container.heroTalents) then
                hasOwnSpecs = true
            end
            if hasOwnSpecs then
                local clearBtn = AceGUI:Create("Button")
                clearBtn:SetText("Clear All")
                clearBtn:SetFullWidth(true)
                clearBtn:SetCallback("OnClick", function()
                    if folderSpecs then
                        container.specs = CopyTable(folderSpecs)
                    else
                        container.specs = nil
                    end
                    container.heroTalents = nil
                    CooldownCompanion:RefreshContainerPanels(containerId)
                    CooldownCompanion:RefreshConfigPanel()
                end)
                CS.col1Scroll:AddChild(clearBtn)
            end
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
                local isMulti = next(CS.selectedGroups) and CS.selectedGroups[containerId]
                local cursorY = GetScaledCursorPosition(CS.col1Scroll)
                CS.dragState = {
                    kind = isMulti and "multi-group" or (inFolder and "folder-group" or "group"),
                    phase = "pending",
                    sourceGroupId = containerId,
                    sourceGroupIds = isMulti and CopyTable(CS.selectedGroups) or nil,
                    sourceSection = sectionTag,
                    sourceFolderId = inFolder and container.folderId or nil,
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

    -- Helper: generate a unique group name with the given base
    local function GenerateGroupName(base)
        local profile = CooldownCompanion.db.profile
        local existing = {}
        -- Check container names (groups are now "panels" under containers)
        for _, c in pairs(profile.groupContainers or {}) do
            existing[c.name] = true
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

    -- Helper: render a folder header row
    local function RenderFolderRow(folderId, sectionTag, childContainerIds)
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
        local allChildrenInactive = IsFolderFullyInactive(folderId, childContainerIds)
        if allChildrenInactive then
            entry:SetColor(0.5, 0.5, 0.5)
        else
            entry:SetColor(1.0, 0.82, 0.0)
        end
        entry:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        CS.col1Scroll:AddChild(entry)
        SetupFolderRowIndicators(entry, folder)

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
                if IsShiftKeyDown() then
                    if CS.specExpandedFolderId == folderId then
                        CS.specExpandedFolderId = nil
                    else
                        CS.specExpandedFolderId = folderId
                        CS.specExpandedGroupId = nil
                    end
                    CooldownCompanion:RefreshConfigPanel()
                    return
                end
                CS.collapsedFolders[folderId] = not CS.collapsedFolders[folderId]
                CooldownCompanion:RefreshConfigPanel()
            elseif button == "MiddleButton" then
                -- Lock/unlock all containers in this folder
                local containers = db.groupContainers or {}
                local anyLocked = false
                for _, c in pairs(containers) do
                    if c.folderId == folderId and c.locked then
                        anyLocked = true
                        break
                    end
                end
                local newState = not anyLocked
                for cid, c in pairs(containers) do
                    if c.folderId == folderId then
                        c.locked = newState
                        CooldownCompanion:UpdateContainerDragHandle(cid, newState)
                        CooldownCompanion:RefreshContainerPanels(cid)
                    end
                end
                CooldownCompanion:RefreshConfigPanel()
                CooldownCompanion:Print("Folder " .. (folder.name or "Unknown") .. (newState and " locked." or " unlocked."))
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

                    -- Add Group to folder
                    info = UIDropDownMenu_CreateInfo()
                    info.text = "Add Group"
                    info.notCheckable = true
                    info.func = function()
                        CloseDropDownMenus()
                        local containerId = CooldownCompanion:CreateGroup(GenerateGroupName("New Group"))
                        CooldownCompanion:MoveGroupToFolder(containerId, folderId)
                        CS.selectedContainer = containerId
                        CS.selectedGroup = nil
                        CS.selectedButton = nil
                        wipe(CS.selectedButtons)
                        CooldownCompanion:RefreshConfigPanel()
                    end
                    UIDropDownMenu_AddButton(info, level)

                    -- Manual icon override
                    info = UIDropDownMenu_CreateInfo()
                    info.text = "Set Folder Icon..."
                    info.notCheckable = true
                    info.func = function()
                        CloseDropDownMenus()
                        OpenFolderIconPicker(folderId)
                    end
                    UIDropDownMenu_AddButton(info, level)

                    if type(folder.manualIcon) == "number" or type(folder.manualIcon) == "string" then
                        info = UIDropDownMenu_CreateInfo()
                        info.text = "Clear Custom Icon"
                        info.notCheckable = true
                        info.func = function()
                            CloseDropDownMenus()
                            local currentFolder = db.folders[folderId]
                            if currentFolder then
                                currentFolder.manualIcon = nil
                                CooldownCompanion:RefreshConfigPanel()
                            end
                        end
                        UIDropDownMenu_AddButton(info, level)
                    end

                    -- Toggle Global/Character
                    info = UIDropDownMenu_CreateInfo()
                    info.text = folder.section == "global" and "Make Character Folder" or "Make Global Folder"
                    info.notCheckable = true
                    info.func = function()
                        CloseDropDownMenus()
                        if folder.section == "global"
                           and FolderHasForeignSpecs
                           and FolderHasForeignSpecs(folderId) then
                            ShowPopupAboveConfig("CDC_UNGLOBAL_FOLDER", folder.name, { folderId = folderId })
                            return
                        end
                        CooldownCompanion:ToggleFolderGlobal(folderId)
                        CooldownCompanion:RefreshConfigPanel()
                    end
                    UIDropDownMenu_AddButton(info, level)

                    -- Lock All / Unlock All (operates on containers in folder)
                    local containers = db.groupContainers or {}
                    local anyLocked = false
                    for _, c in pairs(containers) do
                        if c.folderId == folderId and c.locked then
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
                        for cid, c in pairs(containers) do
                            if c.folderId == folderId then
                                c.locked = newState
                                CooldownCompanion:UpdateContainerDragHandle(cid, newState)
                                CooldownCompanion:RefreshContainerPanels(cid)
                            end
                        end
                        CooldownCompanion:RefreshConfigPanel()
                    end
                    UIDropDownMenu_AddButton(info, level)

                    -- Spec Filter
                    info = UIDropDownMenu_CreateInfo()
                    info.text = "Spec / Hero Filter"
                    info.notCheckable = true
                    info.func = function()
                        CloseDropDownMenus()
                        if CS.specExpandedFolderId == folderId then
                            CS.specExpandedFolderId = nil
                        else
                            CS.specExpandedFolderId = folderId
                            CS.specExpandedGroupId = nil
                        end
                        CooldownCompanion:RefreshConfigPanel()
                    end
                    UIDropDownMenu_AddButton(info, level)

                    -- Export Folder
                    info = UIDropDownMenu_CreateInfo()
                    info.text = "Export Folder"
                    info.notCheckable = true
                    info.func = function()
                        CloseDropDownMenus()
                        local folderData = { name = folder.name }
                        if type(folder.manualIcon) == "number" or type(folder.manualIcon) == "string" then
                            folderData.manualIcon = folder.manualIcon
                        end
                        if folder.specs and next(folder.specs) then
                            folderData.specs = CopyTable(folder.specs)
                        end
                        if folder.heroTalents and next(folder.heroTalents) then
                            folderData.heroTalents = CopyTable(folder.heroTalents)
                        end
                        -- Collect containers in order, then build export data
                        local orderedCids = {}
                        for cid, c in pairs(db.groupContainers) do
                            if c.folderId == folderId then
                                orderedCids[#orderedCids + 1] = { cid = cid, order = c.order or cid }
                            end
                        end
                        table.sort(orderedCids, function(a, b) return a.order < b.order end)
                        local exportContainers = {}
                        for _, item in ipairs(orderedCids) do
                            local c = db.groupContainers[item.cid]
                            local containerData = BuildContainerExportData(c)
                            local sortedPanels = CooldownCompanion:GetPanels(item.cid)
                            local panels = {}
                            for _, entry in ipairs(sortedPanels) do
                                local panelData = BuildGroupExportData(entry.group)
                                panelData._originalGroupId = entry.groupId
                                panels[#panels + 1] = panelData
                            end
                            exportContainers[#exportContainers + 1] = { container = containerData, panels = panels, _originalContainerId = item.cid }
                        end
                        local payload = { type = "folder", version = 2, folder = folderData, containers = exportContainers }
                        local exportString = EncodeExportData(payload)
                        ShowPopupAboveConfig("CDC_EXPORT_GROUP", nil, { exportString = exportString })
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

    local function RenderFolderSpecPanel(folderId)
        local folder = db.folders[folderId]
        if not folder then return end

        local function BuildFolderSpecs(nextSpecId, enabled)
            local nextSpecs = folder.specs and CopyTable(folder.specs) or {}
            if enabled then
                nextSpecs[nextSpecId] = true
            else
                nextSpecs[nextSpecId] = nil
            end
            if not next(nextSpecs) then
                nextSpecs = nil
            end
            return nextSpecs
        end

        local numSpecs = GetNumSpecializations()
        local configID = C_ClassTalents.GetActiveConfigID()
        local htIndent = 32
        for i = 1, numSpecs do
            local specId, name, _, icon = C_SpecializationInfo.GetSpecializationInfo(i)
            local cb = AceGUI:Create("CheckBox")
            cb:SetLabel(name)
            cb:SetImage(icon, 0.08, 0.92, 0.08, 0.92)
            cb:SetFullWidth(true)
            cb:SetValue(folder.specs and folder.specs[specId] or false)
            cb:SetCallback("OnValueChanged", function(widget, event, value)
                CooldownCompanion:SetFolderSpecs(folderId, BuildFolderSpecs(specId, value))
            end)
            CS.col1Scroll:AddChild(cb)
            ApplyCheckboxIndent(cb, 12)

            if configID and folder.specs and folder.specs[specId] then
                local subTreeIDs = C_ClassTalents.GetHeroTalentSpecsForClassSpec(nil, specId)
                if subTreeIDs then
                    for _, subTreeID in ipairs(subTreeIDs) do
                        local subTreeInfo = C_Traits.GetSubTreeInfo(configID, subTreeID)
                        if subTreeInfo then
                            local htCb = AceGUI:Create("CheckBox")
                            htCb:SetLabel(subTreeInfo.name or ("Hero " .. subTreeID))
                            htCb:SetFullWidth(true)
                            htCb:SetValue(folder.heroTalents and folder.heroTalents[subTreeID] or false)
                            htCb:SetCallback("OnValueChanged", function(widget, event, value)
                                CooldownCompanion:SetFolderHeroTalent(folderId, subTreeID, value)
                            end)
                            CS.col1Scroll:AddChild(htCb)
                            ApplyCheckboxIndent(htCb, htIndent)
                            if subTreeInfo.iconElementID then
                                htCb:SetImage(136235)
                                htCb.image:SetAtlas(subTreeInfo.iconElementID, false)
                                htCb.image:SetTexCoord(0, 1, 0, 1)
                            end
                        end
                    end
                end
            end
        end

        local playerSpecIds = {}
        for i = 1, numSpecs do
            local specId = C_SpecializationInfo.GetSpecializationInfo(i)
            if specId then playerSpecIds[specId] = true end
        end

        local foreignSpecs = {}
        if folder.specs then
            for specId in pairs(folder.specs) do
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
                        CooldownCompanion:SetFolderSpecs(folderId, BuildFolderSpecs(specId, value))
                    end)
                    CS.col1Scroll:AddChild(fcb)
                    ApplyCheckboxIndent(fcb, 12)
                end
            end
        end

        local clearBtn = AceGUI:Create("Button")
        clearBtn:SetText("Clear All")
        clearBtn:SetFullWidth(true)
        clearBtn:SetCallback("OnClick", function()
            CooldownCompanion:SetFolderSpecs(folderId, nil)
        end)
        CS.col1Scroll:AddChild(clearBtn)
    end

    -- Render a section (global or character)
    local function RenderSection(section, sectionGroupIds, headingText)
        local items, folderChildContainers = BuildSectionItems(section, sectionGroupIds)

        -- Partition into loaded (active) and unloaded (inactive)
        local loadedItems = {}
        local unloadedItems = {}
        for _, item in ipairs(items) do
            local isInactive
            if item.kind == "folder" then
                isInactive = IsFolderFullyInactive(item.id, folderChildContainers[item.id])
            else
                isInactive = IsContainerInactive(item.id, db.groupContainers[item.id])
            end
            if isInactive then
                table.insert(unloadedItems, item)
            else
                table.insert(loadedItems, item)
            end
        end

        local isEmpty = #loadedItems == 0 and #unloadedItems == 0
        if isEmpty and not CS.showPhantomSections then return end

        local heading = AceGUI:Create("Heading")
        heading:SetText(headingText)
        heading:SetFullWidth(true)

        if section == "char" then
            local cc = C_ClassColor.GetClassColor(select(2, UnitClass("player")))
            if cc then heading.label:SetTextColor(cc.r, cc.g, cc.b) end

            -- Browse badge: inline atlas in heading text so the line breaks around it
            local browseChars = CooldownCompanion:EnumerateBrowseCharacters()
            if #browseChars > 0 then
                heading:SetText(headingText .. "  |A:BattleBar-SwapPetIcon:14:14|a")

                -- Invisible clickable overlay for tooltip + click
                if not CS.browseBadge then
                    local badge = CreateFrame("Button", nil, UIParent)
                    badge:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText("Browse Other Characters")
                        GameTooltip:AddLine("View and copy groups from other characters on this profile.", 1, 1, 1, true)
                        GameTooltip:Show()
                    end)
                    badge:SetScript("OnLeave", function() GameTooltip:Hide() end)
                    badge:SetScript("OnClick", function()
                        CS.browseMode = true
                        CS.browseCharKey = nil
                        CS.browseContainerId = nil
                        ClearSelection()
                        wipe(CS.selectedGroups)
                        CooldownCompanion:RefreshConfigPanel()
                    end)
                    CS.browseBadge = badge
                end
                CS.browseBadge:SetParent(heading.frame)
                CS.browseBadge:ClearAllPoints()
                CS.browseBadge:SetPoint("RIGHT", heading.label, "RIGHT", 0, 0)
                CS.browseBadge:SetSize(16, heading.label:GetHeight() or 16)
                CS.browseBadge:Show()
            else
                if CS.browseBadge then CS.browseBadge:Hide() end
            end
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

        local function RenderItems(itemList)
            for _, item in ipairs(itemList) do
                if item.kind == "folder" then
                    RenderFolderRow(item.id, section, folderChildContainers[item.id])
                    if CS.specExpandedFolderId == item.id then
                        RenderFolderSpecPanel(item.id)
                    end
                    -- If expanded, render children with accent bar
                    if not CS.collapsedFolders[item.id] then
                        local children = folderChildContainers[item.id]
                        if children and #children > 0 then
                            local firstEntry, lastEntry
                            for _, cid in ipairs(children) do
                                local entry = RenderContainerRow(cid, true, section)
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
                elseif item.kind == "container" then
                    RenderContainerRow(item.id, false, section)
                end
            end
        end

        RenderItems(loadedItems)

        if #loadedItems > 0 and #unloadedItems > 0 then
            local sep = AceGUI:Create("Heading")
            sep:SetText("")
            sep:SetFullWidth(true)
            CS.col1Scroll:AddChild(sep)
        end

        RenderItems(unloadedItems)
    end

    -- Split containers into global and character-owned
    local containers = db.groupContainers or {}
    local globalIds = {}
    local charIds = {}
    for id, container in pairs(containers) do
        if container.isGlobal then
            table.insert(globalIds, id)
        elseif container.createdBy == charKey then
            table.insert(charIds, id)
        end
    end

    -- Render sections
    if #globalIds > 0 or next(db.folders) or CS.showPhantomSections then
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

        -- Single row: "New Group" | "New Folder" | "Import Group" (thirds)
        local barW = CS.col1ButtonBar:GetWidth() or 300
        local thirdW = (barW - 6) / 3

        local newGroupBtn = AceGUI:Create("Button")
        newGroupBtn:SetText("New Group")
        newGroupBtn:SetCallback("OnClick", function()
            local containerId, groupId = CooldownCompanion:CreateGroup(GenerateGroupName("New Group"))
            CS.selectedContainer = containerId
            CS.selectedGroup = nil
            CS.selectedButton = nil
            wipe(CS.selectedButtons)
            CooldownCompanion:RefreshConfigPanel()
        end)
        newGroupBtn.frame:SetParent(CS.col1ButtonBar)
        newGroupBtn.frame:ClearAllPoints()
        newGroupBtn.frame:SetPoint("TOPLEFT", CS.col1ButtonBar, "TOPLEFT", 0, -1)
        newGroupBtn.frame:SetWidth(thirdW)
        newGroupBtn.frame:SetHeight(28)
        newGroupBtn.frame:Show()
        table.insert(CS.col1BarWidgets, newGroupBtn)

        local newFolderBtn = AceGUI:Create("Button")
        newFolderBtn:SetText("New Folder")
        newFolderBtn:SetCallback("OnClick", function()
            local folderId = CooldownCompanion:CreateFolder(GenerateFolderName("New Folder"), "char")
            CooldownCompanion:RefreshConfigPanel()
        end)
        newFolderBtn.frame:SetParent(CS.col1ButtonBar)
        newFolderBtn.frame:ClearAllPoints()
        newFolderBtn.frame:SetPoint("LEFT", newGroupBtn.frame, "RIGHT", 3, 0)
        newFolderBtn.frame:SetWidth(thirdW)
        newFolderBtn.frame:SetHeight(28)
        newFolderBtn.frame:Show()
        table.insert(CS.col1BarWidgets, newFolderBtn)

        local importBtn = AceGUI:Create("Button")
        importBtn:SetText("Import")
        importBtn:SetCallback("OnClick", function()
            ShowPopupAboveConfig("CDC_IMPORT_GROUP")
        end)
        importBtn.frame:SetParent(CS.col1ButtonBar)
        importBtn.frame:ClearAllPoints()
        importBtn.frame:SetPoint("LEFT", newFolderBtn.frame, "RIGHT", 3, 0)
        importBtn.frame:SetWidth(thirdW)
        importBtn.frame:SetHeight(28)
        importBtn.frame:Show()
        table.insert(CS.col1BarWidgets, importBtn)

        -- Dynamic equal-width resize
        CS.col1ButtonBar._topRowBtns = {newGroupBtn.frame, newFolderBtn.frame, importBtn.frame}
        CS.col1ButtonBar:SetScript("OnSizeChanged", function(self, w)
            if self._topRowBtns then
                local tw = (w - 6) / 3
                for _, f in ipairs(self._topRowBtns) do
                    f:SetWidth(tw)
                end
            end
        end)
    end
end

------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
ST._RefreshColumn1 = RefreshColumn1
