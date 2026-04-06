local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

local C_Texture_GetAtlasExists = C_Texture.GetAtlasExists

local BASE_THUMB_SIZE = 64
local THUMB_GAP = 8
local DEFAULT_THUMBS_PER_ROW = 5
local GRID_HEIGHT = 452

local pickerWindow = nil

local function GetTargetButtonData(groupId, buttonIndex)
    local profile = CooldownCompanion.db and CooldownCompanion.db.profile
    local group = profile and profile.groups and profile.groups[groupId]
    return group and group.buttons and group.buttons[buttonIndex] or nil
end

local function BuildPreviewSelection(groupId, buttonIndex, entry)
    local profile = CooldownCompanion.db and CooldownCompanion.db.profile
    local group = profile and profile.groups and profile.groups[groupId]
    local baseSettings = group and CooldownCompanion:GetTexturePanelSettings(group)
    return CooldownCompanion:CreateTexturePanelSelection(entry, baseSettings)
end

local function ApplyEntryTexture(texture, entry)
    if entry.sourceType == "atlas" then
        if type(entry.sourceValue) ~= "string" or not C_Texture_GetAtlasExists(entry.sourceValue) then
            texture:Hide()
            return
        end
        texture:SetAtlas(entry.sourceValue, false)
        texture:Show()
        return
    end

    if entry.sourceType == "file" then
        texture:SetTexture(entry.sourceValue)
        texture:Show()
        return
    end

    texture:Hide()
end

local function FindEntryForSelection(entries, selection)
    if CooldownCompanion.FindAuraTexturePickerEntry then
        return CooldownCompanion:FindAuraTexturePickerEntry(entries, selection)
    end

    if type(selection) ~= "table" then
        return nil
    end

    return nil
end

local function CloseAuraTexturePicker()
    if pickerWindow then
        pickerWindow:Fire("OnClose")
    end
end

local function OpenAuraTexturePicker(opts)
    opts = opts or {}

    if pickerWindow then
        pickerWindow:Show()
        pickerWindow.frame:Raise()
        if pickerWindow._rebind then
            pickerWindow._rebind(opts)
        end
        return
    end

    local window = AceGUI:Create("Window")
    window:SetTitle(opts.title or "Browse Texture Panel Visuals")
    window:SetWidth(470)
    window:SetHeight(610)
    window:SetLayout("Flow")
    window:EnableResize(false)
    pickerWindow = window
    CS.auraTexturePickerWindow = window

    local configFrame = CS.configFrame
    if configFrame and configFrame.frame and configFrame.frame:IsShown() then
        window.frame:ClearAllPoints()
        window.frame:SetPoint("TOPLEFT", configFrame.frame, "TOPRIGHT", 4, 0)
    end

    local currentGroupId = opts.groupId
    local currentButtonIndex = opts.buttonIndex
    local currentOnCommit = opts.callback
    local currentSelection = opts.initialSelection
    local currentFilter = "symbols"
    local currentSearch = ""
    local selectedEntry = nil
    local thumbnailPool = {}
    local activeThumbs = {}
    local currentThumbSize = BASE_THUMB_SIZE

    local sourceDrop = AceGUI:Create("Dropdown")
    sourceDrop:SetLabel("Category")
    sourceDrop:SetRelativeWidth(0.45)
    window:AddChild(sourceDrop)

    local searchBox = AceGUI:Create("EditBox")
    searchBox:SetLabel("Search")
    searchBox:SetRelativeWidth(0.55)
    searchBox:DisableButton(true)
    window:AddChild(searchBox)

    local statusLabel = AceGUI:Create("Label")
    statusLabel:SetFullWidth(true)
    statusLabel:SetFontObject(GameFontHighlightSmall)
    statusLabel:SetText("")
    window:AddChild(statusLabel)

    local scrollGroup = AceGUI:Create("SimpleGroup")
    scrollGroup:SetFullWidth(true)
    scrollGroup:SetHeight(GRID_HEIGHT)
    scrollGroup:SetLayout("Fill")
    window:AddChild(scrollGroup)

    local scrollFrame = CreateFrame("ScrollFrame", nil, scrollGroup.frame)
    scrollFrame:SetPoint("TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -4, 4)
    scrollFrame:EnableMouseWheel(true)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(1, 1)
    scrollFrame:SetScrollChild(scrollChild)
    scrollChild:EnableMouseWheel(true)
    local lastViewportWidth = 0

    local selectionLabel = AceGUI:Create("Label")
    selectionLabel:SetFullWidth(true)
    selectionLabel:SetText("Hover a texture to preview it. Click to stage it. Apply saves it.")
    window:AddChild(selectionLabel)

    local applyBtn = AceGUI:Create("Button")
    applyBtn:SetText("Apply")
    applyBtn:SetRelativeWidth(0.5)
    applyBtn:SetDisabled(true)
    window:AddChild(applyBtn)

    local clearBtn = AceGUI:Create("Button")
    clearBtn:SetText("Clear")
    clearBtn:SetRelativeWidth(0.5)
    window:AddChild(clearBtn)

    local function ReleaseActiveThumbs()
        for _, thumb in ipairs(activeThumbs) do
            thumb:Hide()
            thumb:ClearAllPoints()
            thumb:SetScript("OnEnter", nil)
            thumb:SetScript("OnLeave", nil)
            thumb:SetScript("OnClick", nil)
            thumbnailPool[#thumbnailPool + 1] = thumb
        end
        wipe(activeThumbs)
    end

    local function UpdateSelectionLabel()
        if selectedEntry then
            selectionLabel:SetText((selectedEntry.label or "Texture") .. (selectedEntry.subtitle and ("  |  " .. selectedEntry.subtitle) or ""))
        elseif currentSelection and currentSelection.label then
            selectionLabel:SetText("Current: " .. currentSelection.label)
        else
            selectionLabel:SetText("Hover a texture to preview it. Click to stage it. Apply saves it.")
        end
    end

    local function ClearStagedPreview()
        if currentGroupId and currentButtonIndex then
            CooldownCompanion:SetAuraTexturePickerPreview(currentGroupId, currentButtonIndex, nil)
        end
    end

    local function StageEntryPreview(entry)
        if not (currentGroupId and currentButtonIndex) then
            return
        end
        if not entry then
            ClearStagedPreview()
            return
        end
        CooldownCompanion:SetAuraTexturePickerPreview(
            currentGroupId,
            currentButtonIndex,
            BuildPreviewSelection(currentGroupId, currentButtonIndex, entry)
        )
    end

    local function SetSelectedEntry(entry)
        selectedEntry = entry
        applyBtn:SetDisabled(entry == nil)
        UpdateSelectionLabel()
        StageEntryPreview(entry)
        for _, thumb in ipairs(activeThumbs) do
            thumb._selected:SetShown(thumb._entry == entry)
        end
    end

    local function AcquireThumb()
        local thumb = table.remove(thumbnailPool)
        if thumb then
            thumb:SetParent(scrollChild)
            return thumb
        end

        thumb = CreateFrame("Button", nil, scrollChild, "BackdropTemplate")
        thumb:SetSize(currentThumbSize, currentThumbSize)
        thumb:EnableMouseWheel(true)

        local previewBg = thumb:CreateTexture(nil, "BACKGROUND")
        previewBg:SetAllPoints()
        previewBg:SetColorTexture(0, 0, 0, 0.45)

        local previewTex = thumb:CreateTexture(nil, "ARTWORK")
        previewTex:SetAllPoints(previewBg)
        thumb._previewTex = previewTex

        local hover = thumb:CreateTexture(nil, "OVERLAY")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.08)
        hover:Hide()
        thumb._hover = hover

        local selected = thumb:CreateTexture(nil, "OVERLAY")
        selected:SetAllPoints()
        selected:SetColorTexture(0.2, 0.85, 1, 0.18)
        selected:Hide()
        thumb._selected = selected

        return thumb
    end

    local function GetVisibleEntries()
        return CooldownCompanion:GetAuraTexturePickerEntries(currentSearch, currentFilter)
    end

    local function GetGridMetrics(entryCount)
        local viewportWidth = scrollFrame:GetWidth()
        if not viewportWidth or viewportWidth <= 0 then
            viewportWidth = (BASE_THUMB_SIZE + THUMB_GAP) * DEFAULT_THUMBS_PER_ROW
        end

        local columns = DEFAULT_THUMBS_PER_ROW
        local thumbSize = math.max(BASE_THUMB_SIZE, math.floor((viewportWidth - ((columns - 1) * THUMB_GAP)) / columns))
        local contentWidth = math.max(1, (columns * thumbSize) + ((columns - 1) * THUMB_GAP))
        local rows = math.max(1, math.ceil((entryCount or 0) / columns))
        local contentHeight = (rows * thumbSize) + ((rows - 1) * THUMB_GAP)
        return columns, thumbSize, contentWidth, contentHeight
    end

    local function ClampScrollOffset(offset)
        local maxScroll = math.max(0, (scrollChild:GetHeight() or 0) - (scrollFrame:GetHeight() or 0))
        return math.min(math.max(offset or 0, 0), maxScroll)
    end

    local function SetGridScroll(offset)
        scrollFrame:SetVerticalScroll(ClampScrollOffset(offset))
    end

    local function ScrollGridByWheel(delta)
        if not delta or delta == 0 then
            return
        end
        SetGridScroll((scrollFrame:GetVerticalScroll() or 0) - (delta * (currentThumbSize + THUMB_GAP)))
    end

    scrollFrame:SetScript("OnMouseWheel", function(_, delta)
        ScrollGridByWheel(delta)
    end)
    scrollChild:SetScript("OnMouseWheel", function(_, delta)
        ScrollGridByWheel(delta)
    end)

    local function RebuildGrid()
        ReleaseActiveThumbs()
        local entries = GetVisibleEntries()

        if #entries == 0 then
            statusLabel:SetText("No textures matched the current search.")
        else
            statusLabel:SetText(("Showing %d textures."):format(#entries))
        end

        local matchedSelected = FindEntryForSelection(entries, currentSelection)
        local visibleSelected = selectedEntry and FindEntryForSelection(entries, selectedEntry) or nil
        if visibleSelected then
            selectedEntry = visibleSelected
        else
            selectedEntry = matchedSelected
        end

        local columns, thumbSize, contentWidth, contentHeight = GetGridMetrics(#entries)
        currentThumbSize = thumbSize
        local strideX = currentThumbSize + THUMB_GAP
        local strideY = currentThumbSize + THUMB_GAP
        for index, entry in ipairs(entries) do
            local thumb = AcquireThumb()
            local row = math.floor((index - 1) / columns)
            local col = (index - 1) % columns

            thumb:ClearAllPoints()
            thumb:SetSize(currentThumbSize, currentThumbSize)
            thumb:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", col * strideX, -(row * strideY))
            thumb._entry = entry
            thumb._selected:SetShown(selectedEntry == entry)
            ApplyEntryTexture(thumb._previewTex, entry)

            thumb:SetScript("OnEnter", function(self)
                self._hover:Show()
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(entry.label or "Texture")
                if entry.subtitle and entry.subtitle ~= "" then
                    GameTooltip:AddLine(entry.subtitle, 1, 1, 1, true)
                elseif entry.category and entry.category ~= "" then
                    GameTooltip:AddLine(entry.category, 1, 1, 1, true)
                end
                GameTooltip:Show()
                StageEntryPreview(entry)
            end)
            thumb:SetScript("OnLeave", function(self)
                self._hover:Hide()
                GameTooltip:Hide()
                if selectedEntry then
                    StageEntryPreview(selectedEntry)
                else
                    ClearStagedPreview()
                end
            end)
            thumb:SetScript("OnClick", function()
                SetSelectedEntry(entry)
            end)
            thumb:SetScript("OnMouseWheel", function(_, delta)
                ScrollGridByWheel(delta)
            end)

            thumb:Show()
            activeThumbs[#activeThumbs + 1] = thumb
        end

        scrollChild:SetWidth(math.max(1, contentWidth))
        scrollChild:SetHeight(math.max(1, contentHeight))
        SetGridScroll(0)
        applyBtn:SetDisabled(selectedEntry == nil)
        UpdateSelectionLabel()
    end

    scrollFrame:SetScript("OnSizeChanged", function(_, width)
        if type(width) ~= "number" or width <= 0 then
            return
        end
        if math.abs(width - lastViewportWidth) <= 1 then
            return
        end
        lastViewportWidth = width
        RebuildGrid()
    end)

    local filterList, filterOrder = CooldownCompanion:GetAuraTexturePickerFilters()
    sourceDrop:SetList(filterList, filterOrder)
    sourceDrop:SetValue(currentFilter)

    sourceDrop:SetCallback("OnValueChanged", function(_, _, value)
        currentFilter = value or "symbols"
        currentSearch = ""
        searchBox:SetText("")
        RebuildGrid()
    end)

    searchBox:SetCallback("OnTextChanged", function(_, _, text)
        currentSearch = text or ""
        RebuildGrid()
    end)

    applyBtn:SetCallback("OnClick", function()
        if not selectedEntry or not currentOnCommit then
            return
        end
        local selection = BuildPreviewSelection(currentGroupId, currentButtonIndex, selectedEntry)
        currentSelection = selection
        currentOnCommit(selection)
        StageEntryPreview(selectedEntry)
        UpdateSelectionLabel()
        CloseAuraTexturePicker()
    end)

    clearBtn:SetCallback("OnClick", function()
        selectedEntry = nil
        currentSelection = nil
        ClearStagedPreview()
        if currentOnCommit then
            currentOnCommit(nil)
        end
        UpdateSelectionLabel()
        RebuildGrid()
    end)

    window:SetCallback("OnClose", function(widget)
        ClearStagedPreview()
        GameTooltip:Hide()
        ReleaseActiveThumbs()
        pickerWindow = nil
        CS.auraTexturePickerWindow = nil
        AceGUI:Release(widget)
    end)

    window._rebind = function(newOpts)
        ClearStagedPreview()
        currentGroupId = newOpts.groupId
        currentButtonIndex = newOpts.buttonIndex
        currentOnCommit = newOpts.callback
        currentSelection = newOpts.initialSelection
        window._targetGroupId = currentGroupId
        window._targetButtonIndex = currentButtonIndex
        window:SetTitle(newOpts.title or "Browse Texture Panel Visuals")

        currentFilter = CooldownCompanion:GetAuraTexturePickerFilterForSelection(currentSelection)
        currentSearch = (currentSelection and (currentSelection.label or currentSelection.sourceValue)) or ""

        searchBox:SetText(currentSearch or "")
        sourceDrop:SetValue(currentFilter)
        RebuildGrid()
    end

    currentFilter = CooldownCompanion:GetAuraTexturePickerFilterForSelection(currentSelection)
    currentSearch = (currentSelection and (currentSelection.label or currentSelection.sourceValue)) or ""

    searchBox:SetText(currentSearch)
    sourceDrop:SetValue(currentFilter)
    window._targetGroupId = currentGroupId
    window._targetButtonIndex = currentButtonIndex
    RebuildGrid()
end

local function StartPickAuraTexture(opts)
    OpenAuraTexturePicker({
        title = "Browse Texture Panel Visuals",
        groupId = opts and opts.groupId or CS.selectedGroup,
        buttonIndex = opts and opts.buttonIndex or CS.selectedButton,
        callback = opts and opts.callback,
        initialSelection = opts and opts.initialSelection,
    })

    if pickerWindow then
        pickerWindow._targetGroupId = opts and opts.groupId or CS.selectedGroup
        pickerWindow._targetButtonIndex = opts and opts.buttonIndex or CS.selectedButton
    end
end

local function RebindPickAuraTexture(opts)
    if not pickerWindow or not pickerWindow._rebind then
        return
    end

    pickerWindow._targetGroupId = opts and opts.groupId or CS.selectedGroup
    pickerWindow._targetButtonIndex = opts and opts.buttonIndex or CS.selectedButton
    pickerWindow._rebind({
        title = "Browse Texture Panel Visuals",
        groupId = opts and opts.groupId or CS.selectedGroup,
        buttonIndex = opts and opts.buttonIndex or CS.selectedButton,
        callback = opts and opts.callback,
        initialSelection = opts and opts.initialSelection,
    })
end

local function IsAuraTexturePickerOpen()
    return pickerWindow ~= nil
end

CS.StartPickAuraTexture = StartPickAuraTexture
CS.CancelPickAuraTexture = CloseAuraTexturePicker
CS.RebindPickAuraTexture = RebindPickAuraTexture
CS.IsAuraTexturePickerOpen = IsAuraTexturePickerOpen
