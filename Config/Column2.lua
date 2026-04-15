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
local GetConfigEntryDisplayName = ST._GetConfigEntryDisplayName
local GenerateFolderName = ST._GenerateFolderName
local ShowPopupAboveConfig = ST._ShowPopupAboveConfig
local CompactUntitledInlineGroupConfig = ST._CompactUntitledInlineGroupConfig
local CancelDrag = ST._CancelDrag
local StartDragTracking = ST._StartDragTracking
local ClearCol2AnimatedPreview = ST._ClearCol2AnimatedPreview
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
local BindConfigShiftTooltip = ST._BindConfigShiftTooltip
local NotifyTutorialAction = ST._NotifyTutorialAction

local function HideAllBarWidgets(col2)
    if col2._barsStylingScroll then col2._barsStylingScroll.frame:Hide() end
    if col2._resourceStylingTabGroup then col2._resourceStylingTabGroup.frame:Hide() end
    if col2._castBarStylingTabGroup then col2._castBarStylingTabGroup.frame:Hide() end
    col2._resourceStylingSubScroll = nil
end

local tonumber = tonumber
local ipairs = ipairs

local ROW_BADGE_SIZE = 16
local OVERRIDE_BADGE_ICON_SIZE = 12
local ROW_BADGE_SPACING = 2
local ROW_BADGE_RIGHT_PAD = 4
local TEXTURE_PANEL_HEADER_BADGE_ATLAS = "UI-HUD-MicroMenu-Communities-Icon-Notification"
local PANEL_TYPE_TOOLTIPS = {
    icons = {
        title = "Icon Panel",
        description = "Classic cooldown icons for spells or items.",
    },
    bars = {
        title = "Bar Panel",
        description = "Bar timers with names and durations.",
    },
    text = {
        title = "Text Panel",
        description = "Text-only entries for compact status lists.",
    },
    textures = {
        title = "Texture Panel",
        description = "One custom texture for a single spell or item.",
    },
    trigger = {
        title = "Trigger Panel",
        description = "One texture shown when all conditions match.",
    },
}

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

local function LayoutRowBadges(frame, badge1, badge2, badge3, badge4, badge5, badge6)
    local offsetX = -ROW_BADGE_RIGHT_PAD
    offsetX = PlaceRowBadge(frame, badge1, offsetX)
    offsetX = PlaceRowBadge(frame, badge2, offsetX)
    offsetX = PlaceRowBadge(frame, badge3, offsetX)
    offsetX = PlaceRowBadge(frame, badge4, offsetX)
    offsetX = PlaceRowBadge(frame, badge5, offsetX)
    PlaceRowBadge(frame, badge6, offsetX)
end

local function IsAuraTrackingConfigReady(buttonData, cdmEnabled)
    local viewerFrame = CooldownCompanion:ResolveButtonAuraViewerFrame(buttonData)
    local auraStatus = CooldownCompanion:ResolveAuraTrackingConfigStatus(buttonData, cdmEnabled, viewerFrame)
    return auraStatus.ready == true, auraStatus
end

local function CanTexturePanelAcceptEntry(group)
    return not (group and group.displayMode == "textures" and group.buttons and #group.buttons >= 1)
end

local function IsTriggerPanelGroup(group)
    return group and group.displayMode == "trigger"
end

local function GetTriggerRowDisplayText(buttonData)
    local targetText = GetConfigEntryDisplayName(buttonData, { includeDecorations = true })
        or buttonData.name
        or ("Unknown " .. tostring(buttonData.type))
    if CooldownCompanion.GetTriggerConditionSummary then
        local summary = CooldownCompanion:GetTriggerConditionSummary(buttonData)
        if summary and summary ~= "" then
            return targetText .. "  |cff888888" .. summary .. "|r"
        end
    end
    return targetText
end

local function ResolveColumn2TooltipSpellId(buttonData)
    if not (buttonData and buttonData.type == "spell") then
        return nil
    end

    local child
    if buttonData.cdmChildSlot then
        local allChildren = CooldownCompanion.viewerAuraAllChildren[buttonData.id]
        child = allChildren and allChildren[buttonData.cdmChildSlot]
    else
        child = CooldownCompanion.viewerAuraFrames[buttonData.id]
    end

    if child and child.cooldownInfo then
        if child.cooldownInfo.overrideTooltipSpellID then
            return child.cooldownInfo.overrideTooltipSpellID
        end
        if child.cooldownInfo.overrideSpellID then
            return child.cooldownInfo.overrideSpellID
        end
    end

    local rawOverride = C_Spell.GetOverrideSpell(buttonData.id)
    if rawOverride and rawOverride ~= 0 then
        return rawOverride
    end

    return buttonData.id
end

local function MoveEntryBetweenGroups(db, sourceGroupId, sourceIndex, targetGroupId, entryData)
    local targetGroup = db and db.groups and db.groups[targetGroupId]
    if not targetGroup then
        return false
    end
    if not CanTexturePanelAcceptEntry(targetGroup) then
        CooldownCompanion:Print("Texture Panels can only hold one entry.")
        return false
    end

    table.insert(targetGroup.buttons, entryData)
    table.remove(db.groups[sourceGroupId].buttons, sourceIndex)
    CooldownCompanion:RefreshGroupFrame(targetGroupId)
    CooldownCompanion:RefreshGroupFrame(sourceGroupId)
    CS.selectedButton = nil
    wipe(CS.selectedButtons)
    CooldownCompanion:RefreshConfigPanel()
    return true
end

local function BuildEntryMoveDestinationSections(db, sourceGroupId)
    local containers = db and db.groupContainers or {}
    local groupedByFolder = {}
    local looseGroups = {}

    for groupId, group in pairs(db.groups or {}) do
        if groupId ~= sourceGroupId
            and CooldownCompanion:IsGroupVisibleToCurrentChar(groupId)
            and CanTexturePanelAcceptEntry(group)
        then
            local containerId = group.parentContainerId
            local container = containerId and containers[containerId]
            if container then
                local folderId = container.folderId
                local bucket
                if folderId and db.folders and db.folders[folderId] then
                    groupedByFolder[folderId] = groupedByFolder[folderId] or {}
                    bucket = groupedByFolder[folderId]
                else
                    bucket = looseGroups
                end

                local entry = bucket[containerId]
                if not entry then
                    entry = {
                        containerId = containerId,
                        containerName = container.name or ("Group " .. containerId),
                        containerOrder = CooldownCompanion:GetOrderForSpec(
                            container,
                            CooldownCompanion._currentSpecId,
                            containerId
                        ),
                        panels = {},
                    }
                    bucket[containerId] = entry
                end

                entry.panels[#entry.panels + 1] = {
                    groupId = groupId,
                    name = group.name or ("Panel " .. groupId),
                    order = group.order or groupId,
                }
            end
        end
    end

    local function BuildSectionEntries(containerMap)
        local entries = {}
        for _, containerEntry in pairs(containerMap or {}) do
            table.sort(containerEntry.panels, function(a, b)
                if a.order ~= b.order then
                    return a.order < b.order
                end
                return a.groupId < b.groupId
            end)
            entries[#entries + 1] = containerEntry
        end

        table.sort(entries, function(a, b)
            if a.containerOrder ~= b.containerOrder then
                return a.containerOrder < b.containerOrder
            end
            return a.containerId < b.containerId
        end)

        return entries
    end

    local sections = {}
    local sortedFolders = {}
    for folderId, _ in pairs(groupedByFolder) do
        local folder = db.folders and db.folders[folderId]
        if folder then
            sortedFolders[#sortedFolders + 1] = {
                id = folderId,
                name = folder.name or ("Folder " .. folderId),
                order = CooldownCompanion:GetOrderForSpec(folder, CooldownCompanion._currentSpecId, folderId),
            }
        end
    end

    table.sort(sortedFolders, function(a, b)
        if a.order ~= b.order then
            return a.order < b.order
        end
        return a.id < b.id
    end)

    for _, folder in ipairs(sortedFolders) do
        sections[#sections + 1] = {
            title = folder.name,
            entries = BuildSectionEntries(groupedByFolder[folder.id]),
        }
    end

    local looseEntries = BuildSectionEntries(looseGroups)
    if #looseEntries > 0 then
        sections[#sections + 1] = {
            title = (#sortedFolders > 0) and "No Folder" or nil,
            entries = looseEntries,
        }
    end

    return sections
end

local ENTRY_MOVE_GROUP_MENU_PREFIX = "ENTRY_MOVE_GROUP:"

local function FindEntryMoveContainerEntry(sections, containerId)
    for _, section in ipairs(sections or {}) do
        for _, containerEntry in ipairs(section.entries or {}) do
            if containerEntry.containerId == containerId then
                return containerEntry
            end
        end
    end
    return nil
end

local function ParseEntryMoveContainerId(menuList)
    if type(menuList) ~= "string" then
        return nil
    end
    local idText = menuList:match("^" .. ENTRY_MOVE_GROUP_MENU_PREFIX .. "(%d+)$")
    return idText and tonumber(idText) or nil
end

local function AddEntryMoveDestinationButtons(level, sourceGroupId, sourceIndex, entryData, menuList)
    local db = CooldownCompanion.db.profile
    local sections = BuildEntryMoveDestinationSections(db, sourceGroupId)

    local targetContainerId = ParseEntryMoveContainerId(menuList)
    if targetContainerId then
        local containerEntry = FindEntryMoveContainerEntry(sections, targetContainerId)
        if not containerEntry then
            return
        end

        for _, panel in ipairs(containerEntry.panels) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = panel.name
            info.notCheckable = true
            info.func = function()
                if MoveEntryBetweenGroups(db, sourceGroupId, sourceIndex, panel.groupId, entryData) then
                    CloseDropDownMenus()
                end
            end
            UIDropDownMenu_AddButton(info, level)
        end
        return
    end

    for _, section in ipairs(sections) do
        if section.title then
            local header = UIDropDownMenu_CreateInfo()
            header.text = section.title
            header.isTitle = true
            header.notCheckable = true
            UIDropDownMenu_AddButton(header, level)
        end

        for _, containerEntry in ipairs(section.entries) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = containerEntry.containerName
            info.notCheckable = true
            info.hasArrow = true
            info.menuList = ENTRY_MOVE_GROUP_MENU_PREFIX .. tostring(containerEntry.containerId)
            info.leftPadding = section.title and 10 or 0
            UIDropDownMenu_AddButton(info, level)
        end
    end
end

------------------------------------------------------------------------
-- COLUMN 2: Panels
------------------------------------------------------------------------
local function RefreshColumn2()
    if not CS.col2Scroll then return end
    local col2 = CS.configFrame and CS.configFrame.col2
    if ClearCol2AnimatedPreview then
        ClearCol2AnimatedPreview()
    end

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

        -- Update column title based on active bar panel tab
        local col2Title = "Customization: Resources"
        if CS.barPanelTab == "castbar_anchoring" then
            col2Title = "Customization: Cast Bar"
        elseif CS.barPanelTab == "frame_anchoring" then
            col2Title = "Customization: Unit Frames"
        end
        CS.configFrame.col2:SetTitle(col2Title)

        HideAllBarWidgets(col2)

        if CS.barPanelTab == "resource_anchoring" then
            if not col2._resourceStylingTabGroup then
                local tabGroup = AceGUI:Create("TabGroup")
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
                    elseif tab == "positioning" then
                        if ST._BuildResourceBarPositioningPanel then
                            ST._BuildResourceBarPositioningPanel(scroll)
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

            -- Build dynamic "Colors: SpecName" tab text (updates on spec change)
            local colorsTabText = "Colors"
            local specIdx = C_SpecializationInfo.GetSpecialization()
            if specIdx then
                local _, specName = C_SpecializationInfo.GetSpecializationInfo(specIdx)
                if specName and specName ~= "" then
                    colorsTabText = "Colors: " .. ST._GetClassColoredText(specName)
                end
            end
            col2._resourceStylingTabGroup:SetTabs({
                { value = "bar_text", text = "Styling" },
                { value = "positioning", text = "Layout" },
                { value = "colors", text = colorsTabText },
            })

            if CS.resourceStylingTab ~= "bar_text"
                and CS.resourceStylingTab ~= "colors"
                and CS.resourceStylingTab ~= "positioning"
            then
                CS.resourceStylingTab = "bar_text"
            end
            col2._resourceStylingTabGroup.frame:Show()
            col2._resourceStylingTabGroup:SelectTab(CS.resourceStylingTab or "bar_text")
            return
        end

        -- Cast bar: always show TabGroup with Styling + Layout tabs
        if CS.barPanelTab == "castbar_anchoring" then
            local castBarSettings = CooldownCompanion:GetCastBarSettings()
            if castBarSettings then
                if not col2._castBarStylingTabGroup then
                    local tabGroup = AceGUI:Create("TabGroup")
                    tabGroup:SetLayout("Fill")
                    tabGroup:SetCallback("OnGroupSelected", function(widget, event, tab)
                        CS.castBarStylingTab = tab
                        widget:ReleaseChildren()
                        local scroll = AceGUI:Create("ScrollFrame")
                        scroll:SetLayout("List")
                        widget:AddChild(scroll)
                        if tab == "positioning" then
                            if ST._BuildCastBarPositioningPanel then
                                ST._BuildCastBarPositioningPanel(scroll)
                            end
                        else
                            ST._BuildCastBarStylingPanel(scroll)
                        end
                    end)
                    tabGroup.frame:SetParent(col2.content)
                    tabGroup.frame:ClearAllPoints()
                    tabGroup.frame:SetPoint("TOPLEFT", col2.content, "TOPLEFT", 0, 0)
                    tabGroup.frame:SetPoint("BOTTOMRIGHT", col2.content, "BOTTOMRIGHT", 0, 0)
                    col2._castBarStylingTabGroup = tabGroup
                end

                col2._castBarStylingTabGroup:SetTabs({
                    { value = "styling", text = "Styling" },
                    { value = "positioning", text = "Layout" },
                })

                if CS.castBarStylingTab ~= "styling"
                    and CS.castBarStylingTab ~= "positioning"
                then
                    CS.castBarStylingTab = "styling"
                end
                col2._castBarStylingTabGroup.frame:Show()
                col2._castBarStylingTabGroup:SelectTab(CS.castBarStylingTab or "styling")
                return
            end
        end

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

    -- Normal mode: hide bars styling scroll and tab groups
    if col2 then HideAllBarWidgets(col2) end
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
            elseif panel.displayMode == "textures" then
                modeBadge:SetAtlas(TEXTURE_PANEL_HEADER_BADGE_ATLAS, false)
            elseif panel.displayMode == "trigger" then
                modeBadge:SetAtlas(TEXTURE_PANEL_HEADER_BADGE_ATLAS, false)
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
            local disabledBadge = header.frame._cdcHeaderDisabledBadge
            if not disabledBadge then
                disabledBadge = header.frame:CreateTexture(nil, "OVERLAY")
                header.frame._cdcHeaderDisabledBadge = disabledBadge
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
                    elseif buttonData.enabled == false then
                        entry:SetColor(0.5, 0.5, 0.5)
                    end
                    if buttonData.enabled == false and entry.image and entry.image.SetDesaturated then
                        entry.image:SetDesaturated(true)
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
                            targets[#targets + 1] = { id = cid, name = c.name, order = CooldownCompanion:GetOrderForSpec(c, CooldownCompanion._currentSpecId, cid) }
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
        local ca, cb = containers[a], containers[b]
        local oa = ca and CooldownCompanion:GetOrderForSpec(ca, CooldownCompanion._currentSpecId, a) or a
        local ob = cb and CooldownCompanion:GetOrderForSpec(cb, CooldownCompanion._currentSpecId, b) or b
        return oa < ob
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
                            order = CooldownCompanion:GetOrderForSpec(folder, CooldownCompanion._currentSpecId, fid),
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
                        local panelData = BuildGroupExportData(entry.group)
                        panelData._originalGroupId = entry.groupId
                        panels[#panels + 1] = panelData
                    end
                    exportContainers[#exportContainers + 1] = { container = containerData, panels = panels, _originalContainerId = cid }
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
            local panelBtnWidth = (barW - 6) / 3

            local function CreateIconPanel()
                local newPanelId = CooldownCompanion:CreatePanel(CS.selectedContainer, "icons")
                if newPanelId then
                    CS.selectedGroup = newPanelId
                    CS.selectedButton = nil
                    wipe(CS.selectedButtons)
                    CS.addingToPanelId = newPanelId
                    CS.pendingEditBoxFocus = true
                    CooldownCompanion:RefreshConfigPanel()
                    if NotifyTutorialAction then
                        NotifyTutorialAction("panel_created", {
                            containerId = CS.selectedContainer,
                            panelId = newPanelId,
                            displayMode = "icons",
                        })
                    end
                end
            end

            local function CreateBarPanel()
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
            end

            local function CreateTextPanel()
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
            end

            local function CreateTexturePanel()
                local newPanelId = CooldownCompanion:CreatePanel(CS.selectedContainer, "textures")
                if newPanelId then
                    CS.selectedGroup = newPanelId
                    CS.selectedButton = nil
                    wipe(CS.selectedButtons)
                    CS.addingToPanelId = newPanelId
                    CS.pendingEditBoxFocus = true
                    CooldownCompanion:RefreshConfigPanel()
                end
            end

            local function CreateTriggerPanel()
                local newPanelId = CooldownCompanion:CreatePanel(CS.selectedContainer, "trigger")
                if newPanelId then
                    CS.selectedGroup = newPanelId
                    CS.selectedButton = nil
                    wipe(CS.selectedButtons)
                    CS.addingToPanelId = newPanelId
                    CS.pendingEditBoxFocus = true
                    CooldownCompanion:RefreshConfigPanel()
                end
            end

            local iconPanelBtn = AceGUI:Create("Button")
            iconPanelBtn:SetText("Icon Panel")
            iconPanelBtn:SetCallback("OnClick", CreateIconPanel)
            iconPanelBtn.frame:SetParent(CS.col2ButtonBar)
            iconPanelBtn.frame:ClearAllPoints()
            iconPanelBtn.frame:SetPoint("TOPLEFT", CS.col2ButtonBar, "TOPLEFT", 0, -1)
            iconPanelBtn.frame:SetWidth(panelBtnWidth)
            iconPanelBtn.frame:SetHeight(28)
            iconPanelBtn.frame:Show()
            if CS.tutorialAnchors then
                CS.tutorialAnchors.icon_panel_button = iconPanelBtn.frame
            end
            table.insert(CS.col2BarWidgets, iconPanelBtn)

            local barPanelBtn = AceGUI:Create("Button")
            barPanelBtn:SetText("Bar Panel")
            barPanelBtn:SetCallback("OnClick", CreateBarPanel)
            barPanelBtn.frame:SetParent(CS.col2ButtonBar)
            barPanelBtn.frame:ClearAllPoints()
            barPanelBtn.frame:SetPoint("LEFT", iconPanelBtn.frame, "RIGHT", 3, 0)
            barPanelBtn.frame:SetWidth(panelBtnWidth)
            barPanelBtn.frame:SetHeight(28)
            barPanelBtn.frame:Show()
            table.insert(CS.col2BarWidgets, barPanelBtn)

            local otherPanelBtn = AceGUI:Create("Button")
            otherPanelBtn:SetText("Extra")
            otherPanelBtn:SetCallback("OnClick", function()
                if not CS.col2PanelTypeMenu then
                    CS.col2PanelTypeMenu = CreateFrame("Frame", "CDCCol2PanelTypeMenu", UIParent, "UIDropDownMenuTemplate")
                end
                UIDropDownMenu_Initialize(CS.col2PanelTypeMenu, function(self, level)
                    level = level or 1
                    if level ~= 1 then return end

                    local info = UIDropDownMenu_CreateInfo()
                    info.text = "Text Panel"
                    info.notCheckable = true
                    info.func = function()
                        CloseDropDownMenus()
                        CreateTextPanel()
                    end
                    UIDropDownMenu_AddButton(info, level)

                    info = UIDropDownMenu_CreateInfo()
                    info.text = "Texture Panel"
                    info.notCheckable = true
                    info.func = function()
                        CloseDropDownMenus()
                        CreateTexturePanel()
                    end
                    UIDropDownMenu_AddButton(info, level)

                    info = UIDropDownMenu_CreateInfo()
                    info.text = "Trigger Panel"
                    info.notCheckable = true
                    info.func = function()
                        CloseDropDownMenus()
                        CreateTriggerPanel()
                    end
                    UIDropDownMenu_AddButton(info, level)
                end, "MENU")
                CS.col2PanelTypeMenu:SetFrameStrata("FULLSCREEN_DIALOG")
                ToggleDropDownMenu(1, nil, CS.col2PanelTypeMenu, "cursor", 0, 0)
            end)
            otherPanelBtn.frame:SetParent(CS.col2ButtonBar)
            otherPanelBtn.frame:ClearAllPoints()
            otherPanelBtn.frame:SetPoint("LEFT", barPanelBtn.frame, "RIGHT", 3, 0)
            otherPanelBtn.frame:SetWidth(panelBtnWidth)
            otherPanelBtn.frame:SetHeight(28)
            otherPanelBtn.frame:Show()
            table.insert(CS.col2BarWidgets, otherPanelBtn)

            -- Dynamic equal-width resize for panel buttons
            CS.col2ButtonBar._topRowBtns = {
                iconPanelBtn.frame,
                barPanelBtn.frame,
                otherPanelBtn.frame,
            }
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

        local cc = C_ClassColor.GetClassColor(select(2, UnitClass("player")))

        if panelCount == 0 then
            local spacer = AceGUI:Create("SimpleGroup")
            spacer:SetFullWidth(true)
            spacer:SetHeight(20)
            spacer.noAutoHeight = true
            CS.col2Scroll:AddChild(spacer)

            local header = AceGUI:Create("Label")
            header:SetText("Every entry needs a panel.")
            header:SetFullWidth(true)
            header:SetJustifyH("CENTER")
            header:SetFont((GameFontNormal:GetFont()), 15, "")
            CS.col2Scroll:AddChild(header)

            local descSpacer = AceGUI:Create("SimpleGroup")
            descSpacer:SetFullWidth(true)
            descSpacer:SetHeight(6)
            descSpacer.noAutoHeight = true
            CS.col2Scroll:AddChild(descSpacer)

            local desc = AceGUI:Create("Label")
            desc:SetText("Choose a panel type below to get started.")
            desc:SetFullWidth(true)
            desc:SetJustifyH("CENTER")
            desc:SetFont((GameFontNormal:GetFont()), 12, "")
            desc:SetColor(0.7, 0.7, 0.7)
            CS.col2Scroll:AddChild(desc)

            local helpSpacer = AceGUI:Create("SimpleGroup")
            helpSpacer:SetFullWidth(true)
            helpSpacer:SetHeight(10)
            helpSpacer.noAutoHeight = true
            CS.col2Scroll:AddChild(helpSpacer)

            local divider = AceGUI:Create("Label")
            divider:SetText(" ")
            divider:SetFullWidth(true)
            divider:SetHeight(2)
            local dividerBar = divider.frame._cdcAccentBar
            if not dividerBar then
                dividerBar = divider.frame:CreateTexture(nil, "ARTWORK")
                divider.frame._cdcAccentBar = dividerBar
            end
            dividerBar:SetHeight(1.5)
            dividerBar:ClearAllPoints()
            local dividerInset = math.floor(divider.frame:GetWidth() * 0.10 + 0.5)
            dividerBar:SetPoint("LEFT", divider.frame, "LEFT", dividerInset, 1)
            dividerBar:SetPoint("RIGHT", divider.frame, "RIGHT", -dividerInset, 1)
            if cc then
                dividerBar:SetColorTexture(cc.r, cc.g, cc.b, 0.8)
            end
            dividerBar:Show()
            divider:SetCallback("OnRelease", function() dividerBar:Hide() end)
            CS.col2Scroll:AddChild(divider)

            local postDividerSpacer = AceGUI:Create("SimpleGroup")
            postDividerSpacer:SetFullWidth(true)
            postDividerSpacer:SetHeight(10)
            postDividerSpacer.noAutoHeight = true
            CS.col2Scroll:AddChild(postDividerSpacer)

            local helpEntries = {
                PANEL_TYPE_TOOLTIPS.icons,
                PANEL_TYPE_TOOLTIPS.bars,
                PANEL_TYPE_TOOLTIPS.text,
                PANEL_TYPE_TOOLTIPS.textures,
            }

            for index, entry in ipairs(helpEntries) do
                if index > 1 then
                    local entrySpacer = AceGUI:Create("SimpleGroup")
                    entrySpacer:SetFullWidth(true)
                    entrySpacer:SetHeight(8)
                    entrySpacer.noAutoHeight = true
                    CS.col2Scroll:AddChild(entrySpacer)
                end

                local panelHelp = AceGUI:Create("Label")
                panelHelp:SetText("|cffffffff" .. entry.title .. "|r - " .. entry.description)
                panelHelp:SetFullWidth(true)
                panelHelp:SetJustifyH("CENTER")
                panelHelp:SetFont((GameFontNormal:GetFont()), 12, "")
                panelHelp:SetColor(0.75, 0.75, 0.75)
                CS.col2Scroll:AddChild(panelHelp)
            end

            CS.col2Scroll:DoLayout()
            return
        end

        local cdmEnabled = GetCVarBool("cooldownViewerEnabled")

        -- Metadata for cross-panel drag detection
        local col2RenderedRows = {}
        local col2PanelMetas = {}

        -- Reset per-panel drop targets (rebuilt in the loop below)
        CS._panelDropTargets = {}

        -- Render each panel's buttons (with headers for multi-panel containers)
        for panelIndex, panelInfo in ipairs(panels) do
            local panelId = panelInfo.groupId
            local panel = panelInfo.group
            local isCollapsed = CS.collapsedPanels[panelId]
            local panelMeta = {
                panelId = panelId,
                group = panel,
                isCollapsed = isCollapsed and true or false,
                displayMode = panel.displayMode,
                buttonRows = {},
                addRowFrame = nil,
                addInputFrame = nil,
                manualAddButtonFrame = nil,
                autoAddButtonFrame = nil,
            }

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
            panelMeta.panelWidget = panelContainer
            panelMeta.panelFrame = panelContainer.frame
            if panelContainer.frame.GetBackdropColor then
                panelMeta.backdropColor = { panelContainer.frame:GetBackdropColor() }
            end
            if panelContainer.frame.GetBackdropBorderColor then
                panelMeta.borderColor = { panelContainer.frame:GetBackdropBorderColor() }
            end

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
                overlay:SetAlpha(1)
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
                elseif panel.displayMode == "textures" then
                    modeBadge:SetAtlas(TEXTURE_PANEL_HEADER_BADGE_ATLAS, false)
                elseif panel.displayMode == "trigger" then
                    modeBadge:SetAtlas(TEXTURE_PANEL_HEADER_BADGE_ATLAS, false)
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
                local disabledBadge = header.frame._cdcHeaderDisabledBadge
                if not disabledBadge then
                    disabledBadge = header.frame:CreateTexture(nil, "OVERLAY")
                    header.frame._cdcHeaderDisabledBadge = disabledBadge
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
                    if mouseButton == "LeftButton"
                        and panelCount > 1
                        and not IsControlKeyDown()
                        and not GetCursorInfo() then
                        local cursorX, cursorY = GetScaledCursorPosition(CS.col2Scroll)
                        CS.dragState = {
                            kind = "panel",
                            phase = "pending",
                            sourcePanelId = panelId,
                            containerId = CS.selectedContainer,
                            scrollWidget = CS.col2Scroll,
                            startX = cursorX,
                            startY = cursorY,
                            panelDropTargets = CS._panelDropTargets,
                        }
                        if CS.lastCol2RenderedRows then
                            for _, row in ipairs(CS.lastCol2RenderedRows) do
                                if row.kind == "header" and row.panelId == panelId then
                                    CS.dragState.widget = row.widget
                                    break
                                end
                            end
                        end
                        StartDragTracking()
                    end
                end)

                -- Right-click context menu on mouseup (InteractiveLabel fires OnClick
                -- on mousedown which conflicts with UIDropDownMenu's mouseup behavior)
                local ctxPanelId = panelId
                local ctxPanel = panel
                header.frame:SetScript("OnMouseUp", function(self, mouseButton)
                    if CS.dragState and CS.dragState.phase == "active" then return end
                    if mouseButton == "LeftButton" then
                        local now = GetTime()
                        local lastClick = CS.panelClickTimes[panelId] or 0
                        CS.panelClickTimes[panelId] = now
                        if (now - lastClick) < 0.3 then
                            CS.panelClickTimes[panelId] = 0
                            CS.collapsedPanels[panelId] = not CS.collapsedPanels[panelId] or nil
                            CooldownCompanion:RefreshConfigPanel()
                            return
                        end

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

                        wipe(CS.selectedPanels)
                        if CS.selectedGroup == panelId and not CS.selectedButton then
                            CS.selectedGroup = nil
                        else
                            CS.selectedGroup = panelId
                        end
                        CS.selectedButton = nil
                        wipe(CS.selectedButtons)
                        CooldownCompanion:RefreshConfigPanel()
                        return
                    elseif mouseButton == "MiddleButton" then
                        if panel.locked == false then
                            panel.locked = nil
                            CooldownCompanion:Print(panel.name .. " locked.")
                        else
                            panel.locked = false
                            CooldownCompanion:Print(panel.name .. " unlocked. Drag to reposition.")
                        end
                        CooldownCompanion:RefreshGroupFrame(panelId)
                        CooldownCompanion:RefreshConfigPanel()
                        return
                    elseif mouseButton ~= "RightButton" then
                        return
                    end

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
                                { mode = "textures", label = "Textures" },
                                { mode = "trigger", label = "Trigger" },
                            }
                            for _, m in ipairs(switchModes) do
                                if ctxPanel.displayMode ~= m.mode then
                                    info = UIDropDownMenu_CreateInfo()
                                    info.text = "Switch to " .. m.label
                                    info.notCheckable = true
                                    local targetMode = m.mode
                                    info.func = function()
                                        CloseDropDownMenus()
                                        if CooldownCompanion:ChangePanelDisplayMode(ctxPanelId, targetMode) then
                                            if targetMode == "textures" then
                                                CS.pendingTexturePickerOpen = ctxPanelId
                                                CS.selectedGroup = ctxPanelId
                                                CS.selectedButton = nil
                                                wipe(CS.selectedButtons)
                                            end
                                            CooldownCompanion:RefreshConfigPanel()
                                        end
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
                                local payload = {
                                    type = "container",
                                    version = 1,
                                    container = containerData,
                                    panels = { BuildGroupExportData(ctxPanel) },
                                    _originalContainerId = ctxContainerId,
                                }
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
                                        table.insert(folderContainers[fid], { id = cid, name = cName, order = CooldownCompanion:GetOrderForSpec(ctr, CooldownCompanion._currentSpecId, cid) })
                                    else
                                        table.insert(looseContainers, { id = cid, name = cName, order = CooldownCompanion:GetOrderForSpec(ctr, CooldownCompanion._currentSpecId, cid) })
                                    end
                                end
                            end
                            local sortedFolders = {}
                            for fid, folder in pairs(db.folders) do
                                if folderContainers[fid] then
                                    table.insert(sortedFolders, { id = fid, name = folder.name or ("Folder " .. fid), order = CooldownCompanion:GetOrderForSpec(folder, CooldownCompanion._currentSpecId, fid) })
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
                local addBtnTextureFull = panel.displayMode == "textures" and btnCount >= 1
                addBtn:SetScript("OnClick", function()
                    if addBtnTextureFull then
                        CooldownCompanion:Print("Texture Panels can only hold one entry.")
                        return
                    end
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
                addBtn:SetShown(not addBtnTextureFull)

                panelContainer:AddChild(header)
                table.insert(col2RenderedRows, { kind = "header", panelId = panelId, isCollapsed = isCollapsed, widget = header })
                panelMeta.headerWidget = header
                panelMeta.headerFrame = header.frame
                panelMeta.headerText = headerText
                panelMeta.headerColor = {
                    (header.label and select(1, header.label:GetTextColor())) or 1,
                    (header.label and select(2, header.label:GetTextColor())) or 1,
                    (header.label and select(3, header.label:GetTextColor())) or 1,
                }
                panelMeta.count = btnCount

            -- Button list for this panel (skip if collapsed)
            if not isCollapsed then
                local panelButtons = panel.buttons or {}

                for i, buttonData in ipairs(panelButtons) do
                    local entry = AceGUI:Create("InteractiveLabel")
                    CleanRecycledEntry(entry)
                    local usable = CooldownCompanion:IsButtonUsable(buttonData)

                    local entryName = IsTriggerPanelGroup(panel)
                        and GetTriggerRowDisplayText(buttonData)
                        or GetConfigEntryDisplayName(buttonData, { includeDecorations = true })
                    entry:SetText(entryName or ("Unknown " .. buttonData.type))
                    entry:SetImage(GetButtonIcon(buttonData))
                    entry:SetImageSize(32, 32)
                    if entry.image and entry.image.SetDesaturated then
                        entry.image:SetDesaturated(not usable)
                    end
                    entry:SetFullWidth(true)
                    entry:SetFontObject(GameFontHighlight)
                    entry:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                    if buttonData.type == "spell" then
                        BindConfigShiftTooltip(entry, "spell", ResolveColumn2TooltipSpellId(buttonData), entry.frame, "ANCHOR_RIGHT")
                    elseif buttonData.type == "item" then
                        BindConfigShiftTooltip(entry, "item", buttonData.id, entry.frame, "ANCHOR_RIGHT")
                    end

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

                    if not usable and buttonData.enabled ~= false then
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
                            local auraReady, auraStatus = IsAuraTrackingConfigReady(buttonData, cdmEnabled)
                            if auraReady then
                                auraBadge.icon:SetVertexColor(1, 1, 1, 1)
                                SetRowBadgeTooltip(auraBadge, "Aura tracking: Active", 0.2, 1, 0.2)
                            else
                                auraBadge.icon:SetVertexColor(1, 0.2, 0.2, 1)
                                local tooltipText = "Aura tracking: Inactive"
                                if auraStatus and auraStatus.state == "cdmDisabled" then
                                    tooltipText = "Aura tracking: Inactive (Blizzard CDM disabled)"
                                elseif auraStatus and auraStatus.state == "trackedAuraUnavailable" then
                                    tooltipText = "Aura tracking: Inactive (tracked in CDM, but the Buffs/Debuffs viewer is not currently readable)"
                                elseif auraStatus and auraStatus.state == "associatedAuraNotTracked" then
                                    tooltipText = "Aura tracking: Inactive (associated aura is not currently tracked in CDM)"
                                elseif auraStatus and auraStatus.state == "noAssociatedAura" then
                                    tooltipText = "Aura tracking: Inactive (no associated aura found)"
                                end
                                SetRowBadgeTooltip(auraBadge, tooltipText, 1, 0.2, 0.2)
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

                    local disabledBadge
                    if buttonData.enabled == false then
                        disabledBadge = EnsureRowBadge(rowFrame, "_cdcDisabledBadge", "GM-icon-visibleDis-pressed")
                        disabledBadge:SetFrameLevel(rowBadgeLevel)
                        SetRowBadgeTooltip(disabledBadge, "Disabled", 0.6, 0.6, 0.6)
                        disabledBadge:Show()
                    end

                    LayoutRowBadges(rowFrame, disabledBadge, warnBadge, overrideBadge, soundBadge, auraBadge, talentBadge)

                    entry:SetCallback("OnClick", function(widget, event, mouseButton)
                        if mouseButton == "LeftButton" and not IsControlKeyDown() and not GetCursorInfo() then
                            -- Auto-select this panel for drag context
                            if CS.selectedGroup ~= panelId then
                                CS.selectedGroup = panelId
                                CS.selectedButton = nil
                                wipe(CS.selectedButtons)
                            end
                            local cursorX, cursorY = GetScaledCursorPosition(CS.col2Scroll)
                            CS.dragState = {
                                kind = "button",
                                phase = "pending",
                                sourceIndex = i,
                                groupId = panelId,
                                scrollWidget = CS.col2Scroll,
                                widget = entry,
                                startX = cursorX,
                                startY = cursorY,
                                col2RenderedRows = col2RenderedRows,
                            }
                            StartDragTracking()
                        end
                    end)

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

                            if IsControlKeyDown() and not IsTriggerPanelGroup(panel) then
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
                                    -- Disable / Enable button
                                    local toggleInfo = UIDropDownMenu_CreateInfo()
                                    toggleInfo.text = (entryData.enabled ~= false) and "Disable" or "Enable"
                                    toggleInfo.notCheckable = true
                                    toggleInfo.func = function()
                                        CloseDropDownMenus()
                                        entryData.enabled = not (entryData.enabled ~= false)
                                        CooldownCompanion:RefreshGroupFrame(sourceGroupId)
                                        CooldownCompanion:RefreshConfigPanel()
                                    end
                                    UIDropDownMenu_AddButton(toggleInfo, level)

                                    local sourceGroup = CooldownCompanion.db.profile.groups[sourceGroupId]
                                    if not (sourceGroup and sourceGroup.displayMode == "textures") then
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
                                    end

                                    local iconInfo = UIDropDownMenu_CreateInfo()
                                    iconInfo.text = "Override Icon..."
                                    iconInfo.notCheckable = true
                                    iconInfo.tooltipTitle = "|cffffd100Override Icon|r"
                                    iconInfo.tooltipText = "|cffffffffReplaces the default spell or item icon. If aura tracking with Show Aura Icon is active, the aura icon still takes priority while the aura is up.|r"
                                    iconInfo.tooltipOnButton = true
                                    iconInfo.func = function()
                                        CloseDropDownMenus()
                                        ST._OpenButtonIconPicker(sourceGroupId, sourceIndex)
                                    end
                                    UIDropDownMenu_AddButton(iconInfo, level)

                                    if ST._IsValidIconTexture(entryData.manualIcon) then
                                        local resetIconInfo = UIDropDownMenu_CreateInfo()
                                        resetIconInfo.text = "Reset Icon"
                                        resetIconInfo.notCheckable = true
                                        resetIconInfo.func = function()
                                            CloseDropDownMenus()
                                            entryData.manualIcon = nil
                                            CooldownCompanion:RefreshGroupFrame(sourceGroupId)
                                            CooldownCompanion:RefreshConfigPanel()
                                        end
                                        UIDropDownMenu_AddButton(resetIconInfo, level)
                                    end

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
                                elseif menuList == "MOVE_TO_GROUP"
                                    or ParseEntryMoveContainerId(menuList)
                                then
                                    AddEntryMoveDestinationButtons(
                                        level,
                                        sourceGroupId,
                                        sourceIndex,
                                        entryData,
                                        menuList
                                    )
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
                            UIDropDownMenu_Initialize(CS.moveMenuFrame, function(self, level, menuList)
                                level = level or 1
                                if level ~= 1 and not ParseEntryMoveContainerId(menuList) then
                                    return
                                end
                                AddEntryMoveDestinationButtons(
                                    level,
                                    sourceGroupId,
                                    sourceIndex,
                                    entryData,
                                    menuList
                                )
                            end, "MENU")
                            CS.moveMenuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
                            ToggleDropDownMenu(1, nil, CS.moveMenuFrame, "cursor", 0, 0)
                        end
                    end)

                    panelContainer:AddChild(entry)
                    table.insert(col2RenderedRows, { kind = "button", panelId = panelId, buttonIndex = i, widget = entry })
                    table.insert(panelMeta.buttonRows, {
                        buttonIndex = i,
                        widget = entry,
                        frame = entry.frame,
                        text = entryName or ("Unknown " .. buttonData.type),
                        icon = GetButtonIcon(buttonData),
                        usable = usable,
                        textColor = {
                            (entry.label and select(1, entry.label:GetTextColor())) or 1,
                            (entry.label and select(2, entry.label:GetTextColor())) or 1,
                            (entry.label and select(3, entry.label:GetTextColor())) or 1,
                        },
                        imageSize = entry.image and select(1, entry.image:GetSize()) or 32,
                    })
                end -- button loop

                -- Inline add editbox (visible only when this panel is the active add target)
                if CS.addingToPanelId == panelId and not (panel.displayMode == "textures" and btnCount >= 1) then
                    panelMeta.hasInlineAdd = true
                    local inputBox = AceGUI:Create("EditBox")
                    if inputBox.editbox.Instructions then inputBox.editbox.Instructions:Hide() end
                    inputBox:SetLabel("")
                    inputBox:SetText(CS.newInput)
                    inputBox:DisableButton(true)
                    inputBox:SetFullWidth(true)
                    panelMeta.addInputFrame = inputBox.frame

                    local function NotifyTutorialInlineAddSuccess(addTargetGroupId, rawInput)
                        if not NotifyTutorialAction then
                            return
                        end
                        local selectedButton = CS.selectedButton
                        if addTargetGroupId and selectedButton then
                            NotifyTutorialAction("inline_add_succeeded", {
                                groupId = addTargetGroupId,
                                buttonIndex = selectedButton,
                                rawInput = rawInput,
                            })
                        end
                    end

                    inputBox:SetCallback("OnEnterPressed", function(widget, event, text)
                        if CS.ConsumeAutocompleteEnter() then return end
                        CS.HideAutocomplete()
                        CS.newInput = text
                        if CS.newInput ~= "" and CS.addingToPanelId then
                            local addTargetGroupId = CS.addingToPanelId
                            CS.selectedGroup = addTargetGroupId
                            if TryAdd(CS.newInput) then
                                NotifyTutorialInlineAddSuccess(addTargetGroupId, CS.newInput)
                                CS.newInput = ""
                                local targetGroup = CooldownCompanion.db.profile.groups[addTargetGroupId]
                                if not (targetGroup and targetGroup.displayMode == "textures") then
                                    CS.pendingEditBoxFocus = true  -- re-focus for rapid successive adds
                                end
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
                    CS.SetupAutocompleteKeyHandler(inputBox)
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
                    panelMeta.addRowFrame = addRow.frame

                    local manualAddBtn = AceGUI:Create("Button")
                    manualAddBtn:SetText(IsTriggerPanelGroup(panel) and "Add Condition" or "Manual Add")
                    manualAddBtn:SetRelativeWidth(panel.displayMode == "textures" and 1 or 0.49)
                    panelMeta.manualAddButtonFrame = manualAddBtn.frame
                    manualAddBtn:SetCallback("OnClick", function()
                        if CS.newInput ~= "" and CS.addingToPanelId then
                            local addTargetGroupId = CS.addingToPanelId
                            CS.selectedGroup = addTargetGroupId
                            if TryAdd(CS.newInput) then
                                NotifyTutorialInlineAddSuccess(addTargetGroupId, CS.newInput)
                                CS.newInput = ""
                                local targetGroup = CooldownCompanion.db.profile.groups[addTargetGroupId]
                                if not (targetGroup and targetGroup.displayMode == "textures") then
                                    CS.pendingEditBoxFocus = true  -- re-focus for rapid successive adds
                                end
                                CooldownCompanion:RefreshConfigPanel()
                            end
                        end
                    end)
                    addRow:AddChild(manualAddBtn)

                    if panel.displayMode ~= "textures" then
                        local autoAddBtn = AceGUI:Create("Button")
                        autoAddBtn:SetText("Auto Add")
                        autoAddBtn:SetRelativeWidth(0.49)
                        local tutorialRuntime = CS.tutorialRuntime
                        local deemphasizeAutoAdd = tutorialRuntime
                            and tutorialRuntime.active
                            and (tutorialRuntime.step == "add_box_intro" or tutorialRuntime.step == "add_one_spell")
                        autoAddBtn:SetCallback("OnClick", function()
                            CS.selectedGroup = CS.addingToPanelId
                            OpenAutoAddFlow()
                        end)
                        autoAddBtn:SetCallback("OnEnter", function(widget)
                            GameTooltip:SetOwner(widget.frame, "ANCHOR_TOP")
                            GameTooltip:AddLine("Auto Add")
                            GameTooltip:AddLine("Auto-add from Action Bars, Spellbook, or CDM Auras.", 1, 1, 1, true)
                            if deemphasizeAutoAdd then
                                GameTooltip:AddLine("Optional during the tutorial. The guided path uses the add box above.", 0.8, 0.8, 0.8, true)
                            end
                            GameTooltip:Show()
                        end)
                        autoAddBtn:SetCallback("OnLeave", function()
                            GameTooltip:Hide()
                        end)
                        if autoAddBtn.frame then
                            autoAddBtn.frame:SetAlpha(deemphasizeAutoAdd and 0.62 or 1)
                        end
                        panelMeta.autoAddButtonFrame = autoAddBtn.frame
                        addRow:AddChild(autoAddBtn)
                    end

                    panelContainer:AddChild(addRow)
                end
            end -- not collapsed
            table.insert(col2PanelMetas, panelMeta)
        end -- panel loop

        CS.lastCol2RenderedRows = col2RenderedRows
        CS.lastCol2PanelMetas = col2PanelMetas

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
