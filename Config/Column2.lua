--[[
    CooldownCompanion - Config/Column2
    RefreshColumn2.
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
local CompactUntitledInlineGroupConfig = ST._CompactUntitledInlineGroupConfig
local CancelDrag = ST._CancelDrag
local StartDragTracking = ST._StartDragTracking
local GetScaledCursorPosition = ST._GetScaledCursorPosition
local TryAdd = ST._TryAdd
local TryReceiveCursorDrop = ST._TryReceiveCursorDrop
local OnAutocompleteSelect = ST._OnAutocompleteSelect
local SearchAutocomplete = ST._SearchAutocomplete
local OpenAutoAddFlow = ST._OpenAutoAddFlow
local BuildGroupExportData = ST._BuildGroupExportData
local BuildContainerExportData = ST._BuildContainerExportData
local EncodeExportData = ST._EncodeExportData
local GroupsHaveForeignSpecs = ST._GroupsHaveForeignSpecs

local tonumber = tonumber
local ipairs = ipairs

local ROW_BADGE_SIZE = 16
local OVERRIDE_BADGE_ICON_SIZE = 12
local ROW_BADGE_SPACING = 2
local ROW_BADGE_RIGHT_PAD = 4

local function EnsureRowBadge(frame, key, atlas, iconSize)
    local badge = frame[key]
    if not badge then
        badge = CreateFrame("Button", nil, frame)
        badge:SetSize(ROW_BADGE_SIZE, ROW_BADGE_SIZE)
        badge.icon = badge:CreateTexture(nil, "OVERLAY")
        badge.icon:SetAllPoints()
        badge:SetScript("OnEnter", function(self)
            if not self._cdcTooltipText then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(
                self._cdcTooltipText,
                self._cdcTooltipR or 1,
                self._cdcTooltipG or 1,
                self._cdcTooltipB or 1,
                true
            )
            GameTooltip:Show()
        end)
        badge:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        frame[key] = badge
    end

    badge:SetSize(ROW_BADGE_SIZE, ROW_BADGE_SIZE)
    badge.icon:ClearAllPoints()
    if iconSize then
        badge.icon:SetSize(iconSize, iconSize)
        badge.icon:SetPoint("CENTER", badge, "CENTER", 0, 0)
    else
        badge.icon:SetAllPoints()
    end
    badge.icon:SetAtlas(atlas, false)
    badge.icon:SetVertexColor(1, 1, 1, 1)
    badge._cdcTooltipText = nil
    badge._cdcTooltipR, badge._cdcTooltipG, badge._cdcTooltipB = nil, nil, nil
    badge:Hide()
    return badge
end

local function SetRowBadgeTooltip(badge, text, r, g, b)
    badge._cdcTooltipText = text
    badge._cdcTooltipR = r or 1
    badge._cdcTooltipG = g or 1
    badge._cdcTooltipB = b or 1
end

local function PlaceRowBadge(frame, badge, offsetX)
    if not (badge and badge:IsShown()) then
        return offsetX
    end
    badge:ClearAllPoints()
    badge:SetPoint("RIGHT", frame, "RIGHT", offsetX, 0)
    return offsetX - ROW_BADGE_SIZE - ROW_BADGE_SPACING
end

local function LayoutRowBadges(frame, badge1, badge2, badge3, badge4, badge5)
    local offsetX = -ROW_BADGE_RIGHT_PAD
    offsetX = PlaceRowBadge(frame, badge1, offsetX)
    offsetX = PlaceRowBadge(frame, badge2, offsetX)
    offsetX = PlaceRowBadge(frame, badge3, offsetX)
    offsetX = PlaceRowBadge(frame, badge4, offsetX)
    PlaceRowBadge(frame, badge5, offsetX)
end

local function IsBuffViewerChild(frame)
    if not frame then return false end
    local parent = frame:GetParent()
    local parentName = parent and parent:GetName()
    return parentName == "BuffIconCooldownViewer" or parentName == "BuffBarCooldownViewer"
end

local function ResolveButtonAuraViewerFrame(buttonData)
    if not buttonData or buttonData.type ~= "spell" then return nil end

    local viewerFrame
    if buttonData.cdmChildSlot then
        local allChildren = CooldownCompanion.viewerAuraAllChildren[buttonData.id]
        local slotChild = allChildren and allChildren[buttonData.cdmChildSlot]
        if IsBuffViewerChild(slotChild) then
            viewerFrame = slotChild
        end
    end

    if not viewerFrame and buttonData.auraSpellID then
        for id in tostring(buttonData.auraSpellID):gmatch("%d+") do
            local candidate = CooldownCompanion.viewerAuraFrames[tonumber(id)]
            if IsBuffViewerChild(candidate) then
                viewerFrame = candidate
            end
            if viewerFrame then break end
        end
    end

    if not viewerFrame then
        local resolvedAuraId = C_UnitAuras.GetCooldownAuraBySpellID(buttonData.id)
        if resolvedAuraId and resolvedAuraId ~= 0 then
            local resolvedChild = CooldownCompanion.viewerAuraFrames[resolvedAuraId]
            if IsBuffViewerChild(resolvedChild) then
                viewerFrame = resolvedChild
            end
        end
        if not viewerFrame then
            local idChild = CooldownCompanion.viewerAuraFrames[buttonData.id]
            if IsBuffViewerChild(idChild) then
                viewerFrame = idChild
            end
        end
    end

    if not viewerFrame then
        local allChildren = CooldownCompanion.viewerAuraAllChildren[buttonData.id]
        if allChildren and allChildren[1] and IsBuffViewerChild(allChildren[1]) then
            viewerFrame = allChildren[1]
        end
    end

    if not viewerFrame then
        local overrideBuffs = CooldownCompanion.ABILITY_BUFF_OVERRIDES[buttonData.id]
        if overrideBuffs then
            for id in overrideBuffs:gmatch("%d+") do
                local candidate = CooldownCompanion.viewerAuraFrames[tonumber(id)]
                if IsBuffViewerChild(candidate) then
                    viewerFrame = candidate
                end
                if viewerFrame then break end
            end
        end
    end

    if not viewerFrame then
        local fallback = CooldownCompanion:FindViewerChildForSpell(buttonData.id)
        if IsBuffViewerChild(fallback) then
            CooldownCompanion.viewerAuraFrames[buttonData.id] = fallback
            viewerFrame = fallback
        end
    end

    return viewerFrame
end

local function IsAuraTrackingReady(buttonData, cdmEnabled)
    if not (buttonData and buttonData.type == "spell" and buttonData.auraTracking) then
        return false
    end

    if cdmEnabled == nil then
        cdmEnabled = GetCVarBool("cooldownViewerEnabled")
    end
    if not cdmEnabled then
        return false
    end

    local viewerFrame = ResolveButtonAuraViewerFrame(buttonData)
    if not viewerFrame then
        return false
    end

    return true
end

------------------------------------------------------------------------
-- COLUMN 2: Panels
------------------------------------------------------------------------
local function RefreshColumn2()
    if not CS.col2Scroll then return end
    local col2 = CS.configFrame and CS.configFrame.col2

    -- Clear per-panel drop targets (rebuilt if we enter the panel render loop)
    CS._panelDropTargets = {}

    -- Release previous col2 bar widgets
    for _, widget in ipairs(CS.col2BarWidgets) do
        widget:Release()
    end
    wipe(CS.col2BarWidgets)

    -- Bars & Frames panel mode: show Styling in col2
    if CS.resourceBarPanelActive then
        CancelDrag()
        CS.HideAutocomplete()
        CS.col2Scroll.frame:Hide()
        if CS.col2ButtonBar then CS.col2ButtonBar:Hide() end
        if col2 and col2._infoBtn then col2._infoBtn:Hide() end
        if not col2 then return end

        if CS.barPanelTab == "resource_anchoring" then
            if col2._barsStylingScroll then
                col2._barsStylingScroll.frame:Hide()
            end

            if not col2._resourceStylingTabGroup then
                local tabGroup = AceGUI:Create("TabGroup")
                tabGroup:SetTabs({
                    { value = "bar_text", text = "Bar/Text Styling" },
                    { value = "colors", text = "Colors" },
                    { value = "aura_overlays", text = "Aura Overlays" },
                })
                tabGroup:SetLayout("Fill")
                tabGroup:SetCallback("OnGroupSelected", function(widget, event, tab)
                    CS.resourceStylingTab = tab
                    widget:ReleaseChildren()
                    local scroll = AceGUI:Create("ScrollFrame")
                    scroll:SetLayout("List")
                    widget:AddChild(scroll)
                    col2._resourceStylingSubScroll = scroll
                    if tab == "colors" then
                        if ST._BuildResourceBarColorsStylingPanel then
                            ST._BuildResourceBarColorsStylingPanel(scroll)
                        else
                            ST._BuildResourceBarStylingPanel(scroll, "colors")
                        end
                    elseif tab == "aura_overlays" then
                        if ST._BuildResourceBarAuraOverlaysStylingPanel then
                            ST._BuildResourceBarAuraOverlaysStylingPanel(scroll)
                        else
                            ST._BuildResourceBarStylingPanel(scroll, "aura_overlays")
                        end
                    else
                        if ST._BuildResourceBarBarTextStylingPanel then
                            ST._BuildResourceBarBarTextStylingPanel(scroll)
                        else
                            ST._BuildResourceBarStylingPanel(scroll, "bar_text")
                        end
                    end
                end)
                tabGroup.frame:SetParent(col2.content)
                tabGroup.frame:ClearAllPoints()
                tabGroup.frame:SetPoint("TOPLEFT", col2.content, "TOPLEFT", 0, 0)
                tabGroup.frame:SetPoint("BOTTOMRIGHT", col2.content, "BOTTOMRIGHT", 0, 0)
                col2._resourceStylingTabGroup = tabGroup
            end

            if CS.resourceStylingTab ~= "bar_text"
                and CS.resourceStylingTab ~= "colors"
                and CS.resourceStylingTab ~= "aura_overlays"
            then
                CS.resourceStylingTab = "bar_text"
            end
            col2._resourceStylingTabGroup.frame:Show()
            col2._resourceStylingTabGroup:SelectTab(CS.resourceStylingTab or "bar_text")
            return
        end

        if col2._resourceStylingTabGroup then
            col2._resourceStylingTabGroup.frame:Hide()
        end
        col2._resourceStylingSubScroll = nil

        -- Create/show styling scroll
        if not col2._barsStylingScroll then
            local scroll = AceGUI:Create("ScrollFrame")
            scroll:SetLayout("List")
            scroll.frame:SetParent(col2.content)
            scroll.frame:ClearAllPoints()
            scroll.frame:SetPoint("TOPLEFT", col2.content, "TOPLEFT", 0, 0)
            scroll.frame:SetPoint("BOTTOMRIGHT", col2.content, "BOTTOMRIGHT", 0, 0)
            col2._barsStylingScroll = scroll
        end

        col2._barsStylingScroll:ReleaseChildren()
        col2._barsStylingScroll.frame:Show()

        if CS.barPanelTab == "frame_anchoring" then
            local label = AceGUI:Create("Label")
            label:SetText("Unit Frame anchoring has no separate appearance settings.")
            label:SetFullWidth(true)
            col2._barsStylingScroll:AddChild(label)
        else
            ST._BuildCastBarStylingPanel(col2._barsStylingScroll)
        end
        return
    end

    -- Normal mode: hide bars styling scroll
    if col2 and col2._barsStylingScroll then
        col2._barsStylingScroll.frame:Hide()
    end
    if col2 and col2._resourceStylingTabGroup then
        col2._resourceStylingTabGroup.frame:Hide()
    end
    if col2 then
        col2._resourceStylingSubScroll = nil
    end
    if col2 and col2._infoBtn then col2._infoBtn:Show() end

    CancelDrag()
    CS.HideAutocomplete()
    CS.col2Scroll.frame:Show()
    CS.col2Scroll:ReleaseChildren()

    -- Cross-character browse mode: read-only preview
    if CS.browseMode then
        if CS.col2ButtonBar then CS.col2ButtonBar:Hide() end
        -- Extend scroll to full column height (no button bar in browse mode)
        CS.col2Scroll.frame:SetPoint("BOTTOMRIGHT", CS.col2Scroll.frame:GetParent(), "BOTTOMRIGHT", 0, 0)
        local db = CooldownCompanion.db.profile

        if not CS.browseContainerId then
            local label = AceGUI:Create("Label")
            label:SetText("|cff888888Select a group to preview its contents.|r")
            label:SetFullWidth(true)
            CS.col2Scroll:AddChild(label)
            return
        end

        -- Guard: source container may have been deleted
        if not db.groupContainers[CS.browseContainerId] then
            CS.browseContainerId = nil
            local label = AceGUI:Create("Label")
            label:SetText("|cff888888Group no longer exists.|r")
            label:SetFullWidth(true)
            CS.col2Scroll:AddChild(label)
            return
        end

        local panels = CooldownCompanion:GetPanels(CS.browseContainerId)

        -- Class color for accent bars (from browsed character)
        local browseCharInfo = CooldownCompanion.db.global.characterInfo
            and CooldownCompanion.db.global.characterInfo[CS.browseCharKey]
        local browseClassFile = browseCharInfo and browseCharInfo.classFilename
        local browseCC = browseClassFile and C_ClassColor.GetClassColor(browseClassFile)

        for panelIndex, panelInfo in ipairs(panels) do
            local panel = panelInfo.group
            local panelGroupId = panelInfo.groupId

            -- Class-colored accent separator between panels
            if panelIndex > 1 then
                local spacer = AceGUI:Create("Label")
                spacer:SetText(" ")
                spacer:SetFullWidth(true)
                spacer:SetHeight(2)
                local bar = spacer.frame._cdcAccentBar
                if not bar then
                    bar = spacer.frame:CreateTexture(nil, "ARTWORK")
                    spacer.frame._cdcAccentBar = bar
                end
                bar:SetHeight(1.5)
                bar:ClearAllPoints()
                local barInset = math.floor(spacer.frame:GetWidth() * 0.10 + 0.5)
                bar:SetPoint("LEFT", spacer.frame, "LEFT", barInset, 1)
                bar:SetPoint("RIGHT", spacer.frame, "RIGHT", -barInset, 1)
                if browseCC then
                    bar:SetColorTexture(browseCC.r, browseCC.g, browseCC.b, 0.8)
                else
                    bar:SetColorTexture(1, 1, 1, 0.3)
                end
                bar:Show()
                spacer:SetCallback("OnRelease", function() bar:Hide() end)
                CS.col2Scroll:AddChild(spacer)
            end

            -- Bordered container for this panel (matches normal Column 2)
            local panelContainer = AceGUI:Create("InlineGroup")
            panelContainer:SetTitle("")
            panelContainer:SetLayout("List")
            panelContainer:SetFullWidth(true)
            CompactUntitledInlineGroupConfig(panelContainer)
            CS.col2Scroll:AddChild(panelContainer)

            -- Panel header (same badge pattern as normal Column 2 panel headers)
            local headerText = panel.name or "Panel"
            local buttonCount = panel.buttons and #panel.buttons or 0
            headerText = headerText .. " |cff888888(" .. buttonCount .. ")|r"

            local header = AceGUI:Create("InteractiveLabel")
            CleanRecycledEntry(header)
            header:SetText(headerText)
            header:SetImage("Interface\\BUTTONS\\WHITE8X8")
            header.image:SetAlpha(0)

            local modeBadge = header._cdcModeBadge
            if not modeBadge then
                modeBadge = header.frame:CreateTexture(nil, "ARTWORK")
                header._cdcModeBadge = modeBadge
            end
            modeBadge:ClearAllPoints()
            modeBadge:SetSize(16, 16)
            if panel.displayMode == "bars" then
                modeBadge:SetAtlas("CreditsScreen-Assets-Buttons-Pause", false)
            elseif panel.displayMode == "text" then
                modeBadge:SetAtlas("poi-workorders", false)
            else
                modeBadge:SetAtlas("UI-QuestPoi-QuestNumber-SuperTracked", false)
            end
            modeBadge:Show()
            header:SetFullWidth(true)
            header:SetFontObject(GameFontHighlight)
            header:SetJustifyH("CENTER")
            local textW = header.label:GetStringWidth()
            modeBadge:SetPoint("RIGHT", header.label, "CENTER", -(textW / 2) - 2, 0)

            -- Disabled badge (shown when panel is individually disabled)
            local disabledBadge = header.frame._cdcDisabledBadge
            if not disabledBadge then
                disabledBadge = header.frame:CreateTexture(nil, "OVERLAY")
                header.frame._cdcDisabledBadge = disabledBadge
            end
            disabledBadge:SetSize(16, 16)
            disabledBadge:ClearAllPoints()
            disabledBadge:SetPoint("LEFT", header.label, "CENTER", (textW / 2) + 4, 0)
            if panel.enabled == false then
                disabledBadge:SetAtlas("GM-icon-visibleDis-pressed", false)
                disabledBadge:Show()
            else
                disabledBadge:Hide()
            end

            if panel.enabled == false then
                header:SetColor(0.5, 0.5, 0.5)
            elseif CS.selectedGroup == panelGroupId and not CS.selectedButton then
                header:SetColor(0, 1, 0)
            end
            header:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            header:SetCallback("OnClick", function()
                CS.selectedContainer = CS.browseContainerId
                CS.selectedGroup = panelGroupId
                CS.selectedButton = nil
                wipe(CS.selectedButtons)
                CooldownCompanion:RefreshConfigPanel()
            end)
            panelContainer:AddChild(header)

            -- Spacer after header
            local headerSpacer = AceGUI:Create("Label")
            headerSpacer:SetText(" ")
            headerSpacer:SetFullWidth(true)
            headerSpacer:SetHeight(4)
            panelContainer:AddChild(headerSpacer)

            -- Button list (read-only)
            if panel.buttons then
                for buttonIndex, buttonData in ipairs(panel.buttons) do
                    local entry = AceGUI:Create("InteractiveLabel")
                    CleanRecycledEntry(entry)
                    local icon = GetButtonIcon(buttonData)
                    entry:SetImage(icon)
                    entry:SetImageSize(20, 20)
                    entry:SetText(buttonData.name or ("ID: " .. (buttonData.id or "?")))
                    entry:SetFullWidth(true)
                    entry:SetFontObject(GameFontHighlightSmall)
                    entry:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                    if CS.selectedGroup == panelGroupId and CS.selectedButton == buttonIndex then
                        entry:SetColor(0, 1, 0)
                    end
                    local capturedIndex = buttonIndex
                    entry:SetCallback("OnClick", function()
                        CS.selectedContainer = CS.browseContainerId
                        CS.selectedGroup = panelGroupId
                        CS.selectedButton = capturedIndex
                        wipe(CS.selectedButtons)
                        CooldownCompanion:RefreshConfigPanel()
                    end)
                    panelContainer:AddChild(entry)
                end
            end

            -- Spacer before copy button
            local btnSpacer = AceGUI:Create("Label")
            btnSpacer:SetText(" ")
            btnSpacer:SetFullWidth(true)
            btnSpacer:SetHeight(4)
            panelContainer:AddChild(btnSpacer)

            -- "Copy Panel" button (centered at half width)
            local btnRow = AceGUI:Create("SimpleGroup")
            btnRow:SetFullWidth(true)
            btnRow:SetLayout("Flow")
            panelContainer:AddChild(btnRow)

            local leftPad = AceGUI:Create("Label")
            leftPad:SetText("")
            leftPad:SetRelativeWidth(0.25)
            btnRow:AddChild(leftPad)

            local copyPanelBtn = AceGUI:Create("Button")
            copyPanelBtn:SetText("Copy Panel")
            copyPanelBtn:SetRelativeWidth(0.5)
            copyPanelBtn:SetCallback("OnClick", function()
                -- Guard: source still exists
                if not db.groups[panelGroupId] then
                    CooldownCompanion:Print("Source panel no longer exists.")
                    return
                end
                if not CS.browseContextMenu then
                    CS.browseContextMenu = CreateFrame("Frame", "CDCBrowseContextMenu", UIParent, "UIDropDownMenuTemplate")
                end
                UIDropDownMenu_Initialize(CS.browseContextMenu, function(self, level)
                    -- "As New Group"
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = "As New Group"
                    info.notCheckable = true
                    info.func = function()
                        CloseDropDownMenus()
                        if not db.groups[panelGroupId] then return end
                        local srcContainer = db.groupContainers[CS.browseContainerId]
                        local groupName = (srcContainer and srcContainer.name) or panel.name or "Copied Group"
                        local newCid, newGid = CooldownCompanion:CopyPanelAsNewGroup(panelGroupId, groupName)
                        if newCid then
                            CS.browseMode = false
                            CS.browseCharKey = nil
                            CS.browseContainerId = nil
                            CS.selectedContainer = newCid
                            CS.selectedGroup = newGid
                            CooldownCompanion:RefreshConfigPanel()
                            CooldownCompanion:Print("Panel copied as new group.")
                        end
                    end
                    UIDropDownMenu_AddButton(info, level)

                    -- Separator
                    info = UIDropDownMenu_CreateInfo()
                    info.text = ""
                    info.isTitle = true
                    info.notCheckable = true
                    UIDropDownMenu_AddButton(info, level)

                    -- List current character's visible containers
                    local targets = {}
                    for cid, c in pairs(db.groupContainers) do
                        if CooldownCompanion:IsContainerVisibleToCurrentChar(cid) then
                            targets[#targets + 1] = { id = cid, name = c.name, order = c.order or cid }
                        end
                    end
                    table.sort(targets, function(a, b) return a.order < b.order end)

                    for _, target in ipairs(targets) do
                        info = UIDropDownMenu_CreateInfo()
                        info.text = "Into: " .. target.name
                        info.notCheckable = true
                        local targetId = target.id
                        info.func = function()
                            CloseDropDownMenus()
                            if not db.groups[panelGroupId] then return end
                            if not db.groupContainers[targetId] then return end
                            local newGid = CooldownCompanion:CopyPanelToContainer(panelGroupId, targetId)
                            if newGid then
                                CS.browseMode = false
                                CS.browseCharKey = nil
                                CS.browseContainerId = nil
                                CS.selectedContainer = targetId
                                CS.selectedGroup = newGid
                                CooldownCompanion:RefreshConfigPanel()
                                CooldownCompanion:Print("Panel copied into " .. target.name .. ".")
                            end
                        end
                        UIDropDownMenu_AddButton(info, level)
                    end
                end, "MENU")
                CS.browseContextMenu:SetFrameStrata("FULLSCREEN_DIALOG")
                ToggleDropDownMenu(1, nil, CS.browseContextMenu, "cursor", 0, 0)
            end)
            btnRow:AddChild(copyPanelBtn)
        end

        -- "Copy Entire Group" button at the bottom
        local spacer = AceGUI:Create("Label")
        spacer:SetText(" ")
        spacer:SetFullWidth(true)
        CS.col2Scroll:AddChild(spacer)

        local copyAllBtn = AceGUI:Create("Button")
        copyAllBtn:SetText("Copy Entire Group")
        copyAllBtn:SetFullWidth(true)
        copyAllBtn:SetCallback("OnClick", function()
            if not db.groupContainers[CS.browseContainerId] then
                CooldownCompanion:Print("Source group no longer exists.")
                return
            end
            local newId = CooldownCompanion:CopyContainerFromBrowse(CS.browseContainerId)
            if newId then
                CS.browseMode = false
                CS.browseCharKey = nil
                CS.browseContainerId = nil
                CS.selectedContainer = newId
                CS.selectedGroup = nil
                CooldownCompanion:RefreshConfigPanel()
                CooldownCompanion:Print("Group copied successfully.")
            end
        end)
        CS.col2Scroll:AddChild(copyAllBtn)
        return
    end

    -- Restore scroll bottom offset for button bar space (browse mode may have cleared it)
    CS.col2Scroll.frame:SetPoint("BOTTOMRIGHT", CS.col2Scroll.frame:GetParent(), "BOTTOMRIGHT", 0, 30)

    -- Multi-group selection: show inline action buttons (container IDs)
    local multiGroupCount = 0
    local multiContainerIds = {}
    for cid in pairs(CS.selectedGroups) do
        multiGroupCount = multiGroupCount + 1
        multiContainerIds[#multiContainerIds + 1] = cid
    end
    -- Sort by container order so exports and bulk operations preserve visual layout
    local containers = CooldownCompanion.db.profile.groupContainers or {}
    table.sort(multiContainerIds, function(a, b)
        return (containers[a] and containers[a].order or a) < (containers[b] and containers[b].order or b)
    end)
    if multiGroupCount >= 2 then
        if CS.col2ButtonBar then CS.col2ButtonBar:Hide() end
        local db = CooldownCompanion.db.profile
        local containers = db.groupContainers or {}

        local heading = AceGUI:Create("Heading")
        heading:SetText(multiGroupCount .. " Groups Selected")
        local cc = C_ClassColor.GetClassColor(select(2, UnitClass("player")))
        if cc then heading.label:SetTextColor(cc.r, cc.g, cc.b) end
        heading:SetFullWidth(true)
        CS.col2Scroll:AddChild(heading)

        -- Lock / Unlock All (operates on containers)
        local anyLocked = false
        for _, cid in ipairs(multiContainerIds) do
            local c = containers[cid]
            if c and c.locked then
                anyLocked = true
                break
            end
        end

        local lockBtn = AceGUI:Create("Button")
        lockBtn:SetText(anyLocked and "Unlock All" or "Lock All")
        lockBtn:SetFullWidth(true)
        lockBtn:SetCallback("OnClick", function()
            local newState = not anyLocked
            for _, cid in ipairs(multiContainerIds) do
                local c = containers[cid]
                if c then
                    c.locked = newState
                    CooldownCompanion:UpdateContainerDragHandle(cid, newState)
                    CooldownCompanion:RefreshContainerPanels(cid)
                end
            end
            CooldownCompanion:RefreshConfigPanel()
        end)
        CS.col2Scroll:AddChild(lockBtn)

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
                local info = UIDropDownMenu_CreateInfo()
                info.text = "(No Folder)"
                info.notCheckable = true
                info.func = function()
                    CloseDropDownMenus()
                    for _, cid in ipairs(multiContainerIds) do
                        CooldownCompanion:MoveGroupToFolder(cid, nil)
                    end
                    CooldownCompanion:RefreshConfigPanel()
                end
                UIDropDownMenu_AddButton(info, level)

                local charKey = CooldownCompanion.db.keys.char
                local folderList = {}
                for fid, folder in pairs(db.folders) do
                    if folder.section == "char" and folder.createdBy and folder.createdBy ~= charKey then
                        -- skip: belongs to another character
                    else
                        table.insert(folderList, {
                            id = fid,
                            name = folder.name,
                            section = folder.section,
                            order = folder.order or fid,
                        })
                    end
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
                        for _, cid in ipairs(multiContainerIds) do
                            CooldownCompanion:MoveGroupToFolder(cid, f.id)
                        end
                        CooldownCompanion:RefreshAllGroups()
                        CooldownCompanion:RefreshConfigPanel()
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

        -- Export Selected
        local exportBtn = AceGUI:Create("Button")
        exportBtn:SetText("Export Selected")
        exportBtn:SetFullWidth(true)
        exportBtn:SetCallback("OnClick", function()
            local exportContainers = {}
            for _, cid in ipairs(multiContainerIds) do
                local c = db.groupContainers[cid]
                if c then
                    local containerData = BuildContainerExportData(c)
                    local sortedPanels = CooldownCompanion:GetPanels(cid)
                    local panels = {}
                    for _, entry in ipairs(sortedPanels) do
                        panels[#panels + 1] = BuildGroupExportData(entry.group)
                    end
                    exportContainers[#exportContainers + 1] = { container = containerData, panels = panels }
                end
            end
            local payload = { type = "containers", version = 1, containers = exportContainers }
            local exportString = EncodeExportData(payload)
            ShowPopupAboveConfig("CDC_EXPORT_GROUP", nil, { exportString = exportString })
        end)
        CS.col2Scroll:AddChild(exportBtn)

        local spacer3 = AceGUI:Create("Label")
        spacer3:SetText(" ")
        spacer3:SetFullWidth(true)
        local f3, _, fl3 = spacer3.label:GetFont()
        spacer3:SetFont(f3, 3, fl3 or "")
        CS.col2Scroll:AddChild(spacer3)

        -- Delete Selected
        local delBtn = AceGUI:Create("Button")
        delBtn:SetText("Delete Selected")
        delBtn:SetFullWidth(true)
        delBtn:SetCallback("OnClick", function()
            local popup = StaticPopup_Show("CDC_DELETE_SELECTED_GROUPS", #multiContainerIds)
            if popup then
                popup.data = { groupIds = CopyTable(multiContainerIds) }
            end
        end)
        CS.col2Scroll:AddChild(delBtn)

        return
    end

    -- Unified container view: show search bar + all panels' buttons (with collapsible headers for multi-panel)
    if CS.selectedContainer then
        local profile = CooldownCompanion.db.profile
        local container = profile.groupContainers and profile.groupContainers[CS.selectedContainer]
        if not container then
            if CS.col2ButtonBar then CS.col2ButtonBar:Hide() end
            local label = AceGUI:Create("Label")
            label:SetText("Container not found")
            label:SetFullWidth(true)
            CS.col2Scroll:AddChild(label)
            return
        end

        -- Show and populate the panel-type button bar
        if CS.col2ButtonBar then
            CS.col2ButtonBar:Show()
            local barW = CS.col2ButtonBar:GetWidth() or 300
            local thirdW = (barW - 6) / 3

            local iconPanelBtn = AceGUI:Create("Button")
            iconPanelBtn:SetText("Icon Panel")
            iconPanelBtn:SetCallback("OnClick", function()
                local newPanelId = CooldownCompanion:CreatePanel(CS.selectedContainer, "icons")
                if newPanelId then
                    CS.selectedGroup = newPanelId
                    CS.addingToPanelId = newPanelId
                    CS.pendingEditBoxFocus = true
                    CooldownCompanion:RefreshConfigPanel()
                end
            end)
            iconPanelBtn.frame:SetParent(CS.col2ButtonBar)
            iconPanelBtn.frame:ClearAllPoints()
            iconPanelBtn.frame:SetPoint("TOPLEFT", CS.col2ButtonBar, "TOPLEFT", 0, -1)
            iconPanelBtn.frame:SetWidth(thirdW)
            iconPanelBtn.frame:SetHeight(28)
            iconPanelBtn.frame:Show()
            table.insert(CS.col2BarWidgets, iconPanelBtn)

            local barPanelBtn = AceGUI:Create("Button")
            barPanelBtn:SetText("Bar Panel")
            barPanelBtn:SetCallback("OnClick", function()
                local newPanelId = CooldownCompanion:CreatePanel(CS.selectedContainer, "bars")
                if newPanelId then
                    local group = CooldownCompanion.db.profile.groups[newPanelId]
                    if group then
                        group.style.orientation = "vertical"
                        if group.masqueEnabled then
                            CooldownCompanion:ToggleGroupMasque(newPanelId, false)
                        end
                        CooldownCompanion:RefreshGroupFrame(newPanelId)
                    end
                    CS.selectedGroup = newPanelId
                    CS.addingToPanelId = newPanelId
                    CS.pendingEditBoxFocus = true
                    CooldownCompanion:RefreshConfigPanel()
                end
            end)
            barPanelBtn.frame:SetParent(CS.col2ButtonBar)
            barPanelBtn.frame:ClearAllPoints()
            barPanelBtn.frame:SetPoint("LEFT", iconPanelBtn.frame, "RIGHT", 3, 0)
            barPanelBtn.frame:SetWidth(thirdW)
            barPanelBtn.frame:SetHeight(28)
            barPanelBtn.frame:Show()
            table.insert(CS.col2BarWidgets, barPanelBtn)

            local textPanelBtn = AceGUI:Create("Button")
            textPanelBtn:SetText("Text Panel")
            textPanelBtn:SetCallback("OnClick", function()
                local newPanelId = CooldownCompanion:CreatePanel(CS.selectedContainer, "text")
                if newPanelId then
                    local group = CooldownCompanion.db.profile.groups[newPanelId]
                    if group then
                        group.style.orientation = "vertical"
                        if group.masqueEnabled then
                            CooldownCompanion:ToggleGroupMasque(newPanelId, false)
                        end
                        CooldownCompanion:RefreshGroupFrame(newPanelId)
                    end
                    CS.selectedGroup = newPanelId
                    CS.addingToPanelId = newPanelId
                    CS.pendingEditBoxFocus = true
                    CooldownCompanion:RefreshConfigPanel()
                end
            end)
            textPanelBtn.frame:SetParent(CS.col2ButtonBar)
            textPanelBtn.frame:ClearAllPoints()
            textPanelBtn.frame:SetPoint("LEFT", barPanelBtn.frame, "RIGHT", 3, 0)
            textPanelBtn.frame:SetWidth(thirdW)
            textPanelBtn.frame:SetHeight(28)
            textPanelBtn.frame:Show()
            table.insert(CS.col2BarWidgets, textPanelBtn)

            -- Dynamic equal-width resize for panel buttons
            CS.col2ButtonBar._topRowBtns = {iconPanelBtn.frame, barPanelBtn.frame, textPanelBtn.frame}
            CS.col2ButtonBar:SetScript("OnSizeChanged", function(self, w)
                if self._topRowBtns then
                    local tw = (w - 6) / 3
                    for _, f in ipairs(self._topRowBtns) do
                        f:SetWidth(tw)
                    end
                end
            end)
        end

        -- Collect sorted panels
        local panels = CooldownCompanion:GetPanels(CS.selectedContainer)
        local panelCount = #panels

        -- Guard: clear stale addingToPanelId if the target panel no longer exists in this container
        if CS.addingToPanelId then
            local found = false
            for _, p in ipairs(panels) do
                if p.groupId == CS.addingToPanelId then found = true; break end
            end
            if not found then CS.addingToPanelId = nil end
        end

        if panelCount == 0 then
            local spacer = AceGUI:Create("SimpleGroup")
            spacer:SetFullWidth(true)
            spacer:SetHeight(20)
            spacer.noAutoHeight = true
            CS.col2Scroll:AddChild(spacer)

            local msg = AceGUI:Create("Label")
            msg:SetText("Click one of the buttons below to add your first panel.")
            msg:SetFullWidth(true)
            msg:SetJustifyH("CENTER")
            msg:SetFont((GameFontNormal:GetFont()), 15, "")
            CS.col2Scroll:AddChild(msg)
            CS.col2Scroll:DoLayout()
            return
        end

        local cc = C_ClassColor.GetClassColor(select(2, UnitClass("player")))

        local cdmEnabled = GetCVarBool("cooldownViewerEnabled")

        -- Metadata for cross-panel drag detection
        local col2RenderedRows = {}

        -- Reset per-panel drop targets (rebuilt in the loop below)
        CS._panelDropTargets = {}

        -- Render each panel's buttons (with headers for multi-panel containers)
        for panelIndex, panelInfo in ipairs(panels) do
            local panelId = panelInfo.groupId
            local panel = panelInfo.group
            local isCollapsed = CS.collapsedPanels[panelId]

            -- Class-colored accent separator between panels
            if panelIndex > 1 then
                local spacer = AceGUI:Create("Label")
                spacer:SetText(" ")
                spacer:SetFullWidth(true)
                spacer:SetHeight(2)
                local bar = spacer.frame._cdcAccentBar
                if not bar then
                    bar = spacer.frame:CreateTexture(nil, "ARTWORK")
                    spacer.frame._cdcAccentBar = bar
                end
                bar:SetHeight(1.5)
                bar:ClearAllPoints()
                local barInset = math.floor(spacer.frame:GetWidth() * 0.10 + 0.5)
                bar:SetPoint("LEFT", spacer.frame, "LEFT", barInset, 1)
                bar:SetPoint("RIGHT", spacer.frame, "RIGHT", -barInset, 1)
                if cc then
                    bar:SetColorTexture(cc.r, cc.g, cc.b, 0.8)
                end
                bar:Show()
                spacer:SetCallback("OnRelease", function() bar:Hide() end)
                CS.col2Scroll:AddChild(spacer)
            end

            -- Bordered container for this panel
            local panelContainer = AceGUI:Create("InlineGroup")
            panelContainer:SetTitle("")
            panelContainer:SetLayout("List")
            panelContainer:SetFullWidth(true)
            CompactUntitledInlineGroupConfig(panelContainer)
            CS.col2Scroll:AddChild(panelContainer)

            -- Per-panel drop highlight overlay (pooled on underlying frame to survive AceGUI recycling)
            do
                local pf = panelContainer.frame
                local overlay = pf._cdcDropOverlay
                if not overlay then
                    overlay = CreateFrame("Frame", nil, pf, "BackdropTemplate")
                    overlay:SetAllPoints(pf)
                    overlay:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8" })
                    overlay:SetBackdropColor(0.15, 0.55, 0.85, 0.25)
                    overlay:EnableMouse(true)

                    local border = overlay:CreateTexture(nil, "BORDER")
                    border:SetAllPoints()
                    border:SetColorTexture(0.3, 0.7, 1.0, 0.35)

                    local inner = overlay:CreateTexture(nil, "ARTWORK")
                    inner:SetPoint("TOPLEFT", 2, -2)
                    inner:SetPoint("BOTTOMRIGHT", -2, 2)
                    inner:SetColorTexture(0.05, 0.15, 0.25, 0.6)

                    overlay._cdcText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    overlay._cdcText:SetPoint("CENTER", 0, 0)

                    pf._cdcDropOverlay = overlay
                end
                overlay:SetFrameLevel(pf:GetFrameLevel() + 10)
                overlay._cdcText:SetText("|cffAADDFFDrop here|r")
                overlay:Hide()

                local dropPanelId = panelId
                overlay:SetScript("OnReceiveDrag", function()
                    local prev = CS.selectedGroup
                    CS.selectedGroup = dropPanelId
                    TryReceiveCursorDrop()
                    CS.selectedGroup = prev
                end)
                overlay:SetScript("OnMouseUp", function(self, button)
                    if button == "LeftButton" and GetCursorInfo() then
                        local prev = CS.selectedGroup
                        CS.selectedGroup = dropPanelId
                        TryReceiveCursorDrop()
                        CS.selectedGroup = prev
                    end
                end)

                table.insert(CS._panelDropTargets, { panelId = dropPanelId, frame = pf, overlay = overlay })
            end

            -- Panel header
                local btnCount = panel.buttons and #panel.buttons or 0
                local headerText = (panel.name or ("Panel " .. panelId)) .. " |cff666666(" .. btnCount .. ")|r"

                local header = AceGUI:Create("InteractiveLabel")
                CleanRecycledEntry(header)
                header:SetText(headerText)
                header:SetImage(134400) -- invisible dummy for 32px row height
                header:SetImageSize(1, 32)
                header.image:SetAlpha(0)

                -- Mode badge overlay (pooled on widget, same pattern as old Column 1)
                local modeBadge = header._cdcModeBadge
                if not modeBadge then
                    modeBadge = header.frame:CreateTexture(nil, "ARTWORK")
                    header._cdcModeBadge = modeBadge
                end
                modeBadge:ClearAllPoints()
                modeBadge:SetSize(16, 16)
                if panel.displayMode == "bars" then
                    modeBadge:SetAtlas("CreditsScreen-Assets-Buttons-Pause", false)
                elseif panel.displayMode == "text" then
                    modeBadge:SetAtlas("poi-workorders", false)
                else
                    modeBadge:SetAtlas("UI-QuestPoi-QuestNumber-SuperTracked", false)
                end
                modeBadge:Show()
                header:SetFullWidth(true)
                header:SetFontObject(GameFontHighlight)
                header:SetJustifyH("CENTER")
                -- Position badge to the left of centered text
                local textW = header.label:GetStringWidth()
                modeBadge:SetPoint("RIGHT", header.label, "CENTER", -(textW / 2) - 2, 0)
                header:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")

                -- Anchor unlock badge (shown when panel is individually unlocked)
                local anchorBadge = header.frame._cdcAnchorBadge
                if not anchorBadge then
                    anchorBadge = header.frame:CreateTexture(nil, "OVERLAY")
                    header.frame._cdcAnchorBadge = anchorBadge
                end
                anchorBadge:SetSize(16, 16)
                anchorBadge:ClearAllPoints()
                anchorBadge:SetPoint("LEFT", header.label, "CENTER", (textW / 2) + 4, 0)
                if panel.locked == false then
                    anchorBadge:SetAtlas("ShipMissionIcon-Training-Map", false)
                    anchorBadge:Show()
                else
                    anchorBadge:Hide()
                end

                -- Disabled badge (shown when panel is individually disabled)
                local disabledBadge = header.frame._cdcDisabledBadge
                if not disabledBadge then
                    disabledBadge = header.frame:CreateTexture(nil, "OVERLAY")
                    header.frame._cdcDisabledBadge = disabledBadge
                end
                disabledBadge:SetSize(16, 16)
                disabledBadge:ClearAllPoints()
                local disabledOffset = (panel.locked == false) and 22 or 0
                disabledBadge:SetPoint("LEFT", header.label, "CENTER", (textW / 2) + 4 + disabledOffset, 0)
                if panel.enabled == false then
                    disabledBadge:SetAtlas("GM-icon-visibleDis-pressed", false)
                    disabledBadge:Show()
                else
                    disabledBadge:Hide()
                end

                -- Spec / hero talent filter badges (panel-level filters not inherited from container/folder)
                local specBadges = header.frame._cdcSpecBadges
                if not specBadges then
                    specBadges = {}
                    header.frame._cdcSpecBadges = specBadges
                end
                for _, sb in ipairs(specBadges) do
                    if sb._cdcCircleMask then sb.icon:RemoveMaskTexture(sb._cdcCircleMask) end
                    sb.icon:SetTexCoord(0, 1, 0, 1)
                    sb:Hide()
                end

                local containerSpecs = container.specs
                local containerHeroTalents = container.heroTalents
                local folderSpecs, folderHeroTalents
                if container.folderId and profile.folders then
                    local folder = profile.folders[container.folderId]
                    if folder then
                        folderSpecs = folder.specs
                        folderHeroTalents = folder.heroTalents
                    end
                end

                local specBadgeIdx = 0
                local rightOffset = (textW / 2) + 4
                if panel.locked == false then rightOffset = rightOffset + 22 end
                if panel.enabled == false then rightOffset = rightOffset + 22 end

                if panel.specs then
                    for specId in pairs(panel.specs) do
                        if not (containerSpecs and containerSpecs[specId])
                           and not (folderSpecs and folderSpecs[specId]) then
                            local _, _, _, specIcon = GetSpecializationInfoForSpecID(specId)
                            if specIcon then
                                specBadgeIdx = specBadgeIdx + 1
                                local sb = specBadges[specBadgeIdx]
                                if not sb then
                                    sb = CreateFrame("Frame", nil, header.frame)
                                    sb.icon = sb:CreateTexture(nil, "OVERLAY")
                                    sb.icon:SetAllPoints()
                                    sb:EnableMouse(false)
                                    local mask = sb:CreateMaskTexture()
                                    mask:SetAllPoints(sb.icon)
                                    mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
                                    sb._cdcCircleMask = mask
                                    specBadges[specBadgeIdx] = sb
                                end
                                sb:SetSize(16, 16)
                                sb.icon:SetTexture(specIcon)
                                sb.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                                sb.icon:AddMaskTexture(sb._cdcCircleMask)
                                sb:ClearAllPoints()
                                sb:SetPoint("LEFT", header.label, "CENTER", rightOffset, 0)
                                sb:Show()
                                rightOffset = rightOffset + 18
                            end
                        end
                    end
                end

                if panel.heroTalents then
                    local configID = C_ClassTalents.GetActiveConfigID()
                    if configID then
                        for subTreeID in pairs(panel.heroTalents) do
                            if not (containerHeroTalents and containerHeroTalents[subTreeID])
                               and not (folderHeroTalents and folderHeroTalents[subTreeID]) then
                                local subTreeInfo = C_Traits.GetSubTreeInfo(configID, subTreeID)
                                if subTreeInfo and subTreeInfo.iconElementID then
                                    specBadgeIdx = specBadgeIdx + 1
                                    local sb = specBadges[specBadgeIdx]
                                    if not sb then
                                        sb = CreateFrame("Frame", nil, header.frame)
                                        sb.icon = sb:CreateTexture(nil, "OVERLAY")
                                        sb.icon:SetAllPoints()
                                        sb:EnableMouse(false)
                                        specBadges[specBadgeIdx] = sb
                                    end
                                    sb:SetSize(16, 16)
                                    sb.icon:SetAtlas(subTreeInfo.iconElementID, false)
                                    sb:ClearAllPoints()
                                    sb:SetPoint("LEFT", header.label, "CENTER", rightOffset, 0)
                                    sb:Show()
                                    rightOffset = rightOffset + 18
                                end
                            end
                        end
                    end
                end

                -- Highlight: blue if multi-selected (overrides all), gray if disabled, green if single-selected
                if CS.selectedPanels[panelId] then
                    header:SetColor(0.4, 0.7, 1.0)
                elseif panel.enabled == false then
                    header:SetColor(0.5, 0.5, 0.5)
                elseif CS.selectedGroup == panelId and not CS.selectedButton then
                    header:SetColor(0, 1, 0)
                end

                header:SetCallback("OnClick", function(widget, event, mouseButton)
                    if mouseButton == "LeftButton" then
                        local now = GetTime()
                        local lastClick = CS.panelClickTimes[panelId] or 0
                        CS.panelClickTimes[panelId] = now
                        if (now - lastClick) < 0.3 then
                            -- Double-click: toggle collapse/expand
                            CS.panelClickTimes[panelId] = 0
                            CS.collapsedPanels[panelId] = not CS.collapsedPanels[panelId] or nil
                            CooldownCompanion:RefreshConfigPanel()
                            return
                        end
                        -- Ctrl+Click: toggle panel multi-select
                        if IsControlKeyDown() then
                            if CS.selectedPanels[panelId] then
                                CS.selectedPanels[panelId] = nil
                            else
                                CS.selectedPanels[panelId] = true
                            end
                            if CS.selectedGroup and not CS.selectedPanels[CS.selectedGroup] and next(CS.selectedPanels) then
                                CS.selectedPanels[CS.selectedGroup] = true
                            end
                            CS.selectedGroup = nil
                            CS.selectedButton = nil
                            wipe(CS.selectedButtons)
                            CS.addingToPanelId = nil
                            CooldownCompanion:RefreshConfigPanel()
                            return
                        end
                        -- Single-click: select or deselect this panel, clear multi-select
                        wipe(CS.selectedPanels)
                        -- If a button is selected within this panel, just clear the button
                        -- selection (transition to panel settings) rather than deselecting.
                        if CS.selectedGroup == panelId and not CS.selectedButton then
                            CS.selectedGroup = nil
                        else
                            CS.selectedGroup = panelId
                        end
                        CS.selectedButton = nil
                        wipe(CS.selectedButtons)
                        CooldownCompanion:RefreshConfigPanel()
                    elseif mouseButton == "MiddleButton" then
                        -- Toggle panel anchor lock
                        if panel.locked == false then
                            panel.locked = nil
                            CooldownCompanion:Print(panel.name .. " locked.")
                        else
                            panel.locked = false
                            CooldownCompanion:Print(panel.name .. " unlocked. Drag to reposition.")
                        end
                        CooldownCompanion:RefreshGroupFrame(panelId)
                        CooldownCompanion:RefreshConfigPanel()
                    end
                end)

                -- Right-click context menu on mouseup (InteractiveLabel fires OnClick
                -- on mousedown which conflicts with UIDropDownMenu's mouseup behavior)
                local ctxPanelId = panelId
                local ctxPanel = panel
                header.frame:SetScript("OnMouseUp", function(self, mouseButton)
                    if mouseButton ~= "RightButton" then return end
                    if not CS.panelContextMenu then
                        CS.panelContextMenu = CreateFrame("Frame", "CDCPanelContextMenu", UIParent, "UIDropDownMenuTemplate")
                    end
                    local ctxContainerId = CS.selectedContainer
                    UIDropDownMenu_Initialize(CS.panelContextMenu, function(self, level, menuList)
                        level = level or 1
                        if level == 1 then
                            local info = UIDropDownMenu_CreateInfo()
                            info.text = "Rename"
                            info.notCheckable = true
                            info.func = function()
                                CloseDropDownMenus()
                                ShowPopupAboveConfig("CDC_RENAME_GROUP", ctxPanel.name or "Panel", { groupId = ctxPanelId })
                            end
                            UIDropDownMenu_AddButton(info, level)

                            -- Disable / Enable panel
                            info = UIDropDownMenu_CreateInfo()
                            info.text = (ctxPanel.enabled ~= false) and "Disable" or "Enable"
                            info.notCheckable = true
                            info.func = function()
                                CloseDropDownMenus()
                                ctxPanel.enabled = not (ctxPanel.enabled ~= false)
                                CooldownCompanion:RefreshGroupFrame(ctxPanelId)
                                CooldownCompanion:RefreshConfigPanel()
                            end
                            UIDropDownMenu_AddButton(info, level)

                            -- Lock / Unlock panel anchor
                            info = UIDropDownMenu_CreateInfo()
                            info.text = ctxPanel.locked == false and "Lock Anchor" or "Unlock Anchor"
                            info.notCheckable = true
                            info.func = function()
                                CloseDropDownMenus()
                                if ctxPanel.locked == false then
                                    ctxPanel.locked = nil
                                    CooldownCompanion:Print(ctxPanel.name .. " locked.")
                                else
                                    ctxPanel.locked = false
                                    CooldownCompanion:Print(ctxPanel.name .. " unlocked. Drag to reposition.")
                                end
                                CooldownCompanion:RefreshGroupFrame(ctxPanelId)
                                CooldownCompanion:RefreshConfigPanel()
                            end
                            UIDropDownMenu_AddButton(info, level)

                            local switchModes = {
                                { mode = "icons", label = "Icons" },
                                { mode = "bars", label = "Bars" },
                                { mode = "text", label = "Text" },
                            }
                            for _, m in ipairs(switchModes) do
                                if ctxPanel.displayMode ~= m.mode then
                                    info = UIDropDownMenu_CreateInfo()
                                    info.text = "Switch to " .. m.label
                                    info.notCheckable = true
                                    local targetMode = m.mode
                                    info.func = function()
                                        CloseDropDownMenus()
                                        ctxPanel.displayMode = targetMode
                                        if targetMode == "bars" or targetMode == "text" then
                                            ctxPanel.style.orientation = "vertical"
                                        end
                                        if targetMode ~= "icons" and ctxPanel.masqueEnabled then
                                            CooldownCompanion:ToggleGroupMasque(ctxPanelId, false)
                                        end
                                        CooldownCompanion:RefreshGroupFrame(ctxPanelId)
                                        CooldownCompanion:RefreshConfigPanel()
                                    end
                                    UIDropDownMenu_AddButton(info, level)
                                end
                            end

                            info = UIDropDownMenu_CreateInfo()
                            info.text = "Duplicate"
                            info.notCheckable = true
                            info.func = function()
                                CloseDropDownMenus()
                                local newPanelId = CooldownCompanion:DuplicatePanel(ctxContainerId, ctxPanelId)
                                if newPanelId then
                                    CS.selectedGroup = newPanelId
                                    CooldownCompanion:RefreshConfigPanel()
                                end
                            end
                            UIDropDownMenu_AddButton(info, level)

                            -- Export single panel
                            info = UIDropDownMenu_CreateInfo()
                            info.text = "Export"
                            info.notCheckable = true
                            info.func = function()
                                CloseDropDownMenus()
                                local db = CooldownCompanion.db.profile
                                local containerData = BuildContainerExportData(db.groupContainers[ctxContainerId])
                                containerData.name = ctxPanel.name or "Panel"
                                local payload = { type = "container", version = 1, container = containerData, panels = { BuildGroupExportData(ctxPanel) } }
                                local exportString = EncodeExportData(payload)
                                ShowPopupAboveConfig("CDC_EXPORT_GROUP", nil, { exportString = exportString })
                            end
                            UIDropDownMenu_AddButton(info, level)

                            -- "Move to Group" submenu (only when other visible containers exist)
                            local db = CooldownCompanion.db.profile
                            local hasOtherContainer = false
                            for cid, _ in pairs(db.groupContainers) do
                                if cid ~= ctxContainerId and CooldownCompanion:IsContainerVisibleToCurrentChar(cid) then
                                    hasOtherContainer = true
                                    break
                                end
                            end
                            if hasOtherContainer then
                                info = UIDropDownMenu_CreateInfo()
                                info.text = "Move to Group"
                                info.notCheckable = true
                                info.hasArrow = true
                                info.menuList = "MOVE_TO_GROUP"
                                UIDropDownMenu_AddButton(info, level)
                            end

                            info = UIDropDownMenu_CreateInfo()
                            info.text = "|cffff4444Delete|r"
                            info.notCheckable = true
                            info.func = function()
                                CloseDropDownMenus()
                                ShowPopupAboveConfig("CDC_DELETE_PANEL", ctxPanel.name or "Panel", { containerId = ctxContainerId, panelId = ctxPanelId })
                            end
                            UIDropDownMenu_AddButton(info, level)

                        elseif menuList == "MOVE_TO_GROUP" then
                            local db = CooldownCompanion.db.profile
                            local containers = db.groupContainers or {}
                            local folderContainers, looseContainers = {}, {}
                            for cid, ctr in pairs(containers) do
                                if cid ~= ctxContainerId and CooldownCompanion:IsContainerVisibleToCurrentChar(cid) then
                                    local cName = ctr.name or ("Group " .. cid)
                                    local fid = ctr.folderId
                                    if fid and db.folders[fid] then
                                        folderContainers[fid] = folderContainers[fid] or {}
                                        table.insert(folderContainers[fid], { id = cid, name = cName, order = ctr.order or cid })
                                    else
                                        table.insert(looseContainers, { id = cid, name = cName, order = ctr.order or cid })
                                    end
                                end
                            end
                            local sortedFolders = {}
                            for fid, folder in pairs(db.folders) do
                                if folderContainers[fid] then
                                    table.insert(sortedFolders, { id = fid, name = folder.name or ("Folder " .. fid), order = folder.order or fid })
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
                                for _, c in ipairs(folderContainers[folder.id]) do
                                    local info = UIDropDownMenu_CreateInfo()
                                    info.text = c.name
                                    info.notCheckable = true
                                    info.func = function()
                                        CloseDropDownMenus()
                                        local _, sourceDeleted = CooldownCompanion:MovePanel(ctxPanelId, c.id)
                                        if sourceDeleted then
                                            CS.selectedContainer = c.id
                                        end
                                        CS.selectedGroup = ctxPanelId
                                        CS.selectedButton = nil
                                        wipe(CS.selectedButtons)
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
                                for _, c in ipairs(looseContainers) do
                                    local info = UIDropDownMenu_CreateInfo()
                                    info.text = c.name
                                    info.notCheckable = true
                                    info.func = function()
                                        CloseDropDownMenus()
                                        local _, sourceDeleted = CooldownCompanion:MovePanel(ctxPanelId, c.id)
                                        if sourceDeleted then
                                            CS.selectedContainer = c.id
                                        end
                                        CS.selectedGroup = ctxPanelId
                                        CS.selectedButton = nil
                                        wipe(CS.selectedButtons)
                                        CooldownCompanion:RefreshConfigPanel()
                                    end
                                    UIDropDownMenu_AddButton(info, level)
                                end
                            end
                        end
                    end, "MENU")
                    CS.panelContextMenu:SetFrameStrata("FULLSCREEN_DIALOG")
                    ToggleDropDownMenu(1, nil, CS.panelContextMenu, "cursor", 0, 0)
                end)

                -- Add toggle button overlay (pooled on underlying frame)
                local isAdding = CS.addingToPanelId == panelId
                local addBtn = header.frame._cdcAddBtn
                if not addBtn then
                    addBtn = CreateFrame("Button", nil, header.frame)
                    addBtn:SetSize(10, 10)
                    addBtn.icon = addBtn:CreateTexture(nil, "OVERLAY")
                    addBtn.icon:SetAllPoints()
                    header.frame._cdcAddBtn = addBtn
                end
                addBtn:ClearAllPoints()
                addBtn:SetPoint("RIGHT", header.frame, "RIGHT", -4, 0)
                addBtn:SetFrameLevel(header.frame:GetFrameLevel() + 2)
                addBtn.icon:SetAtlas(isAdding and "common-icon-minus" or "common-icon-plus", false)
                addBtn.icon:SetVertexColor(0.3, 0.8, 0.3)
                local addBtnPanelId = panelId
                addBtn:SetScript("OnClick", function()
                    if CS.addingToPanelId == addBtnPanelId then
                        CS.addingToPanelId = nil
                    else
                        CS.addingToPanelId = addBtnPanelId
                        CS.selectedGroup = addBtnPanelId
                        CS.selectedButton = nil
                        wipe(CS.selectedButtons)
                        CS.collapsedPanels[addBtnPanelId] = nil
                        CS.pendingEditBoxFocus = true
                    end
                    CooldownCompanion:RefreshConfigPanel()
                end)
                addBtn:Show()

                panelContainer:AddChild(header)
                table.insert(col2RenderedRows, { kind = "header", panelId = panelId, isCollapsed = isCollapsed, widget = header })

                -- Drag-to-reorder panel headers (only for multi-panel containers)
                if panelCount > 1 then
                    local headerFrame = header.frame
                    if not headerFrame._cdcDragHooked then
                        headerFrame._cdcDragHooked = true
                        headerFrame:HookScript("OnMouseDown", function(self, mouseBtn)
                            if self._cdcOnMouseDown then self._cdcOnMouseDown(self, mouseBtn) end
                        end)
                    end
                    local dragPanelId = panelId
                    headerFrame._cdcOnMouseDown = function(self, mouseButton)
                        if GetCursorInfo() then return end
                        if mouseButton == "LeftButton" and not IsControlKeyDown() then
                            local cursorY = GetScaledCursorPosition(CS.col2Scroll)
                            CS.dragState = {
                                kind = "panel",
                                phase = "pending",
                                sourcePanelId = dragPanelId,
                                containerId = CS.selectedContainer,
                                scrollWidget = CS.col2Scroll,
                                widget = header,
                                startY = cursorY,
                                panelDropTargets = CS._panelDropTargets,
                            }
                            StartDragTracking()
                        end
                    end
                end

            -- Button list for this panel (skip if collapsed)
            if not isCollapsed then
                local panelButtons = panel.buttons or {}

                for i, buttonData in ipairs(panelButtons) do
                    local entry = AceGUI:Create("InteractiveLabel")
                    CleanRecycledEntry(entry)
                    local usable = CooldownCompanion:IsButtonUsable(buttonData)

                    local entryName = buttonData.name
                    if buttonData.type == "spell" then
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
                        if buttonData.cdmChildSlot then
                            entryName = entryName .. " #" .. buttonData.cdmChildSlot
                        end
                        local addedAs = buttonData.addedAs
                        if addedAs ~= "spell" and addedAs ~= "aura" then
                            addedAs = buttonData.isPassive and "aura" or "spell"
                        end
                        local icons = ""
                        if addedAs ~= "aura" then
                            icons = icons .. "|A:ui_adv_atk:15:15|a"
                        end
                        if addedAs == "aura" or buttonData.auraTracking then
                            icons = icons .. "|A:ui_adv_health:15:15|a"
                        end
                        if icons ~= "" then
                            entryName = entryName .. "  " .. icons
                        end
                    elseif buttonData.type == "item" then
                        if C_Item.IsEquippableItem(buttonData.id) then
                            entryName = entryName .. "  |A:Crosshair_repairnpc_32:15:15|a"
                        else
                            entryName = entryName .. "  |A:auctionhouse-icon-coin-gold:12:12|a"
                        end
                    end
                    entry:SetText(entryName or ("Unknown " .. buttonData.type))
                    entry:SetImage(GetButtonIcon(buttonData))
                    entry:SetImageSize(32, 32)
                    if entry.image and entry.image.SetDesaturated then
                        entry.image:SetDesaturated(not usable)
                    end
                    entry:SetFullWidth(true)
                    entry:SetFontObject(GameFontHighlight)
                    entry:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")

                    -- Selection highlighting: only show if this panel is the selected one
                    if CS.selectedGroup == panelId then
                        if CS.selectedButtons[i] then
                            entry:SetColor(0.4, 0.7, 1.0)
                        elseif CS.selectedButton == i then
                            entry:SetColor(0.4, 0.7, 1.0)
                        elseif not usable then
                            entry:SetColor(0.5, 0.5, 0.5)
                        end
                    elseif not usable then
                        entry:SetColor(0.5, 0.5, 0.5)
                    end

                    -- Right-side row badges
                    local rowFrame = entry.frame
                    local rowBadgeLevel = rowFrame:GetFrameLevel() + 5
                    local warnBadge, overrideBadge, soundBadge, auraBadge

                    if not usable then
                        warnBadge = EnsureRowBadge(rowFrame, "_cdcWarnBtn", "Ping_Marker_Icon_Warning")
                        warnBadge:SetFrameLevel(rowBadgeLevel)
                        SetRowBadgeTooltip(warnBadge, "Spell/item unavailable", 1, 0.3, 0.3)
                        warnBadge:Show()
                    end

                    if CooldownCompanion:HasStyleOverrides(buttonData) then
                        overrideBadge = EnsureRowBadge(
                            rowFrame,
                            "_cdcOverrideBadge",
                            "Crosshair_VehichleCursor_32",
                            OVERRIDE_BADGE_ICON_SIZE
                        )
                        overrideBadge:SetFrameLevel(rowBadgeLevel)
                        SetRowBadgeTooltip(overrideBadge, "Has appearance overrides")
                        overrideBadge:Show()
                    end

                    if buttonData.type == "spell" then
                        local enabledSoundEvents = CooldownCompanion:GetEnabledSoundAlertEventsForButton(buttonData)
                        if enabledSoundEvents then
                            soundBadge = EnsureRowBadge(rowFrame, "_cdcSoundBadge", "common-icon-sound")
                            soundBadge:SetFrameLevel(rowBadgeLevel)
                            SetRowBadgeTooltip(soundBadge, "Sound alerts enabled")
                            soundBadge:Show()
                        end

                        if buttonData.auraTracking then
                            auraBadge = EnsureRowBadge(rowFrame, "_cdcAuraBadge", "icon_trackedbuffs")
                            auraBadge:SetFrameLevel(rowBadgeLevel)
                            local auraReady = IsAuraTrackingReady(buttonData, cdmEnabled)
                            if auraReady then
                                auraBadge.icon:SetVertexColor(1, 1, 1, 1)
                                SetRowBadgeTooltip(auraBadge, "Aura tracking: Active", 0.2, 1, 0.2)
                            else
                                auraBadge.icon:SetVertexColor(1, 0.2, 0.2, 1)
                                SetRowBadgeTooltip(auraBadge, "Aura tracking: Inactive", 1, 0.2, 0.2)
                            end
                            auraBadge:Show()
                        end
                    end

                    local talentBadge = EnsureRowBadge(rowFrame, "_cdcTalentBadge", "UI-HUD-MicroMenu-SpecTalents-Mouseover")
                    talentBadge:SetFrameLevel(rowBadgeLevel)
                    if buttonData.talentConditions and #buttonData.talentConditions > 0 then
                        SetRowBadgeTooltip(talentBadge, "Has talent conditions")
                        talentBadge:Show()
                    end

                    LayoutRowBadges(rowFrame, warnBadge, overrideBadge, soundBadge, auraBadge, talentBadge)

                    entry:SetCallback("OnClick", function() end)

                    -- Handle clicks via OnMouseUp with drag guard
                    -- Capture upvalues for this button's panel context
                    local btnPanelId = panelId
                    local btnIndex = i
                    local entryFrame = entry.frame
                    entryFrame:SetScript("OnMouseUp", function(self, mouseButton)
                        if CS.dragState and CS.dragState.phase == "active" then return end
                        if mouseButton == "LeftButton" and GetCursorInfo() then
                            if TryReceiveCursorDrop() then return end
                        end
                        if mouseButton == "LeftButton" then
                            -- Auto-select this button's panel
                            local panelChanged = CS.selectedGroup ~= btnPanelId
                            if panelChanged then
                                CS.selectedGroup = btnPanelId
                                CS.selectedButton = nil
                                wipe(CS.selectedButtons)
                            end
                            wipe(CS.selectedPanels)

                            if IsControlKeyDown() then
                                if CS.selectedButtons[btnIndex] then
                                    CS.selectedButtons[btnIndex] = nil
                                else
                                    CS.selectedButtons[btnIndex] = true
                                end
                                if CS.selectedButton and not CS.selectedButtons[CS.selectedButton] and next(CS.selectedButtons) then
                                    CS.selectedButtons[CS.selectedButton] = true
                                end
                                CS.selectedButton = nil
                            else
                                wipe(CS.selectedButtons)
                                if not panelChanged and CS.selectedButton == btnIndex then
                                    CS.selectedButton = nil
                                else
                                    CS.selectedButton = btnIndex
                                end
                            end
                            CooldownCompanion:RefreshConfigPanel()
                        elseif mouseButton == "RightButton" then
                            -- Auto-select panel on right-click too
                            if CS.selectedGroup ~= btnPanelId then
                                CS.selectedGroup = btnPanelId
                                CS.selectedButton = nil
                                wipe(CS.selectedButtons)
                            end
                            wipe(CS.selectedPanels)
                            if not CS.buttonContextMenu then
                                CS.buttonContextMenu = CreateFrame("Frame", "CDCButtonContextMenu", UIParent, "UIDropDownMenuTemplate")
                            end
                            local sourceGroupId = btnPanelId
                            local sourceIndex = btnIndex
                            local entryData = buttonData
                            UIDropDownMenu_Initialize(CS.buttonContextMenu, function(self, level, menuList)
                                level = level or 1
                                if level == 1 then
                                    local dupInfo = UIDropDownMenu_CreateInfo()
                                    dupInfo.text = "Duplicate"
                                    dupInfo.notCheckable = true
                                    dupInfo.func = function()
                                        local copy = CopyTable(entryData)
                                        table.insert(CooldownCompanion.db.profile.groups[sourceGroupId].buttons, sourceIndex + 1, copy)
                                        CooldownCompanion:RefreshGroupFrame(sourceGroupId)
                                        CooldownCompanion:RefreshConfigPanel()
                                        CloseDropDownMenus()
                                    end
                                    UIDropDownMenu_AddButton(dupInfo, level)

                                    local moveInfo = UIDropDownMenu_CreateInfo()
                                    moveInfo.text = "Move to..."
                                    moveInfo.notCheckable = true
                                    moveInfo.hasArrow = true
                                    moveInfo.menuList = "MOVE_TO_GROUP"
                                    UIDropDownMenu_AddButton(moveInfo, level)

                                    local removeInfo = UIDropDownMenu_CreateInfo()
                                    removeInfo.text = "Remove"
                                    removeInfo.notCheckable = true
                                    removeInfo.func = function()
                                        CloseDropDownMenus()
                                        local name = entryData.name or "this entry"
                                        ShowPopupAboveConfig("CDC_DELETE_BUTTON", name, { groupId = sourceGroupId, buttonIndex = sourceIndex })
                                    end
                                    UIDropDownMenu_AddButton(removeInfo, level)
                                elseif menuList == "MOVE_TO_GROUP" then
                                    local db = CooldownCompanion.db.profile
                                    local containers = db.groupContainers or {}
                                    local folderGroups, looseGroups = {}, {}
                                    for id, group in pairs(db.groups) do
                                        if id ~= sourceGroupId and CooldownCompanion:IsGroupVisibleToCurrentChar(id) then
                                            local gName = group.name or ("Group " .. id)
                                            local cid = group.parentContainerId
                                            local ctr = cid and containers[cid]
                                            local fid = ctr and ctr.folderId
                                            if fid and db.folders[fid] then
                                                folderGroups[fid] = folderGroups[fid] or {}
                                                table.insert(folderGroups[fid], { id = id, name = gName })
                                            else
                                                table.insert(looseGroups, { id = id, name = gName })
                                            end
                                        end
                                    end
                                    local sortedFolders = {}
                                    for fid, folder in pairs(db.folders) do
                                        if folderGroups[fid] then
                                            table.insert(sortedFolders, { id = fid, name = folder.name or ("Folder " .. fid), order = folder.order or fid })
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
                                        for _, g in ipairs(folderGroups[folder.id]) do
                                            local info = UIDropDownMenu_CreateInfo()
                                            info.text = g.name
                                            info.notCheckable = true
                                            info.func = function()
                                                table.insert(db.groups[g.id].buttons, entryData)
                                                table.remove(db.groups[sourceGroupId].buttons, sourceIndex)
                                                CooldownCompanion:RefreshGroupFrame(g.id)
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
                                        for _, g in ipairs(looseGroups) do
                                            local info = UIDropDownMenu_CreateInfo()
                                            info.text = g.name
                                            info.notCheckable = true
                                            info.func = function()
                                                table.insert(db.groups[g.id].buttons, entryData)
                                                table.remove(db.groups[sourceGroupId].buttons, sourceIndex)
                                                CooldownCompanion:RefreshGroupFrame(g.id)
                                                CooldownCompanion:RefreshGroupFrame(sourceGroupId)
                                                CS.selectedButton = nil
                                                wipe(CS.selectedButtons)
                                                CooldownCompanion:RefreshConfigPanel()
                                                CloseDropDownMenus()
                                            end
                                            UIDropDownMenu_AddButton(info, level)
                                        end
                                    end
                                end
                            end, "MENU")
                            CS.buttonContextMenu:SetFrameStrata("FULLSCREEN_DIALOG")
                            ToggleDropDownMenu(1, nil, CS.buttonContextMenu, "cursor", 0, 0)
                        elseif mouseButton == "MiddleButton" then
                            if CS.selectedGroup ~= btnPanelId then
                                CS.selectedGroup = btnPanelId
                                CS.selectedButton = nil
                                wipe(CS.selectedButtons)
                            end
                            if not CS.moveMenuFrame then
                                CS.moveMenuFrame = CreateFrame("Frame", "CDCMoveMenu", UIParent, "UIDropDownMenuTemplate")
                            end
                            local sourceGroupId = btnPanelId
                            local sourceIndex = btnIndex
                            local entryData = buttonData
                            UIDropDownMenu_Initialize(CS.moveMenuFrame, function(self, level)
                                local db = CooldownCompanion.db.profile
                                local containers = db.groupContainers or {}
                                local folderGroups, looseGroups = {}, {}
                                for id, group in pairs(db.groups) do
                                    if id ~= sourceGroupId and CooldownCompanion:IsGroupVisibleToCurrentChar(id) then
                                        local gName = group.name or ("Group " .. id)
                                        local cid = group.parentContainerId
                                        local ctr = cid and containers[cid]
                                        local fid = ctr and ctr.folderId
                                        if fid and db.folders[fid] then
                                            folderGroups[fid] = folderGroups[fid] or {}
                                            table.insert(folderGroups[fid], { id = id, name = gName })
                                        else
                                            table.insert(looseGroups, { id = id, name = gName })
                                        end
                                    end
                                end
                                local sortedFolders = {}
                                for fid, folder in pairs(db.folders) do
                                    if folderGroups[fid] then
                                        table.insert(sortedFolders, { id = fid, name = folder.name or ("Folder " .. fid), order = folder.order or fid })
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
                                    for _, g in ipairs(folderGroups[folder.id]) do
                                        local info = UIDropDownMenu_CreateInfo()
                                        info.text = g.name
                                        info.func = function()
                                            table.insert(db.groups[g.id].buttons, entryData)
                                            table.remove(db.groups[sourceGroupId].buttons, sourceIndex)
                                            CooldownCompanion:RefreshGroupFrame(g.id)
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
                                    for _, g in ipairs(looseGroups) do
                                        local info = UIDropDownMenu_CreateInfo()
                                        info.text = g.name
                                        info.func = function()
                                            table.insert(db.groups[g.id].buttons, entryData)
                                            table.remove(db.groups[sourceGroupId].buttons, sourceIndex)
                                            CooldownCompanion:RefreshGroupFrame(g.id)
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

                    panelContainer:AddChild(entry)
                    table.insert(col2RenderedRows, { kind = "button", panelId = panelId, buttonIndex = i, widget = entry })

                    -- (Drop is now handled by per-panel overlay, not individual button rows)

                    -- Hold-click drag reorder (within this panel only)
                    if not entryFrame._cdcDragHooked then
                        entryFrame._cdcDragHooked = true
                        entryFrame:HookScript("OnMouseDown", function(self, mouseBtn)
                            if self._cdcOnMouseDown then self._cdcOnMouseDown(self, mouseBtn) end
                        end)
                    end
                    local dragPanelId = panelId
                    local dragBtnIndex = i
                    entryFrame._cdcOnMouseDown = function(self, mouseButton)
                        if GetCursorInfo() then return end
                        if mouseButton == "LeftButton" and not IsControlKeyDown() then
                            -- Auto-select this panel for drag context
                            if CS.selectedGroup ~= dragPanelId then
                                CS.selectedGroup = dragPanelId
                                CS.selectedButton = nil
                                wipe(CS.selectedButtons)
                            end
                            local cursorY = GetScaledCursorPosition(CS.col2Scroll)
                            CS.dragState = {
                                kind = "button",
                                phase = "pending",
                                sourceIndex = dragBtnIndex,
                                groupId = dragPanelId,
                                scrollWidget = CS.col2Scroll,
                                widget = entry,
                                startY = cursorY,
                                -- Multi-panel: use rendered rows for cross-panel awareness
                                col2RenderedRows = col2RenderedRows,
                            }
                            StartDragTracking()
                        end
                    end
                end -- button loop

                -- Inline add editbox (visible only when this panel is the active add target)
                if CS.addingToPanelId == panelId then
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
                        if CS.newInput ~= "" and CS.addingToPanelId then
                            CS.selectedGroup = CS.addingToPanelId
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
                    local editboxFrame = inputBox.editbox
                    if not editboxFrame._cdcAutocompHooked then
                        editboxFrame._cdcAutocompHooked = true
                        editboxFrame:HookScript("OnKeyDown", function(self, key)
                            CS.HandleAutocompleteKeyDown(key)
                        end)
                    end
                    panelContainer:AddChild(inputBox)

                    if CS.pendingEditBoxFocus then
                        CS.pendingEditBoxFocus = false
                        C_Timer.After(0, function()
                            if inputBox.editbox then
                                inputBox:SetFocus()
                            end
                        end)
                    end

                    local addSpacer = AceGUI:Create("SimpleGroup")
                    addSpacer:SetFullWidth(true)
                    addSpacer:SetHeight(2)
                    addSpacer.noAutoHeight = true
                    panelContainer:AddChild(addSpacer)

                    local addRow = AceGUI:Create("SimpleGroup")
                    addRow:SetFullWidth(true)
                    addRow:SetLayout("Flow")

                    local manualAddBtn = AceGUI:Create("Button")
                    manualAddBtn:SetText("Manual Add")
                    manualAddBtn:SetRelativeWidth(0.49)
                    manualAddBtn:SetCallback("OnClick", function()
                        if CS.newInput ~= "" and CS.addingToPanelId then
                            CS.selectedGroup = CS.addingToPanelId
                            if TryAdd(CS.newInput) then
                                CS.newInput = ""
                                CooldownCompanion:RefreshConfigPanel()
                            end
                        end
                    end)
                    addRow:AddChild(manualAddBtn)

                    local autoAddBtn = AceGUI:Create("Button")
                    autoAddBtn:SetText("Auto Add")
                    autoAddBtn:SetRelativeWidth(0.49)
                    autoAddBtn:SetCallback("OnClick", function()
                        CS.selectedGroup = CS.addingToPanelId
                        OpenAutoAddFlow()
                    end)
                    autoAddBtn:SetCallback("OnEnter", function(widget)
                        GameTooltip:SetOwner(widget.frame, "ANCHOR_TOP")
                        GameTooltip:AddLine("Auto Add")
                        GameTooltip:AddLine("Auto-add from Action Bars, Spellbook, or CDM Auras.", 1, 1, 1, true)
                        GameTooltip:Show()
                    end)
                    autoAddBtn:SetCallback("OnLeave", function()
                        GameTooltip:Hide()
                    end)
                    addRow:AddChild(autoAddBtn)

                    panelContainer:AddChild(addRow)
                end
            end -- not collapsed
        end -- panel loop

        CS.col2Scroll:DoLayout()

        return
    end

    -- No container selected
    if CS.col2ButtonBar then CS.col2ButtonBar:Hide() end
    if not CS.selectedContainer then
        local label = AceGUI:Create("Label")
        label:SetText("Select a group first")
        label:SetFullWidth(true)
        CS.col2Scroll:AddChild(label)
        return
    end

end

------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
ST._RefreshColumn2 = RefreshColumn2
