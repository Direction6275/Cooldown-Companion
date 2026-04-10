local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

local BASE_THUMB_SIZE = 64
local THUMB_GAP = 8
local DEFAULT_THUMBS_PER_ROW = 5
local GRID_HEIGHT = 452
local FILTER_SHAREDMEDIA = "sharedMedia"
local FILTER_FAVORITES = "favorites"

local pickerWindow = nil
local pickerParkingFrame = CreateFrame("Frame", nil, UIParent)
pickerParkingFrame:Hide()
local pickerThumbnailPool = {}
local pickerScrollFrame = nil
local pickerScrollChild = nil

local function IsSharedMediaFilter(filterValue)
    return filterValue == FILTER_SHAREDMEDIA
end

local function IsFavoritesFilter(filterValue)
    return filterValue == FILTER_FAVORITES
end

local function GetEntryActionMode(entry)
    if type(entry) ~= "table" then
        return nil
    end

    if entry.canRemoveFavorite then
        return "removeFavorite"
    end

    if entry.canFavorite then
        return "addFavorite"
    end

    return nil
end

local function BuildPreviewSelection(groupId, buttonIndex, entry)
    local profile = CooldownCompanion.db and CooldownCompanion.db.profile
    local group = profile and profile.groups and profile.groups[groupId]
    local baseSettings = group and CooldownCompanion:GetTexturePanelSettings(group)
    return CooldownCompanion:CreateTexturePanelSelection(entry, baseSettings)
end

local function ApplyEntryTexture(texture, entry)
    local resolvedSourceType, resolvedSourceValue = CooldownCompanion:ResolveAuraTextureAsset(
        entry.sourceType,
        entry.sourceValue,
        entry.mediaType
    )

    if resolvedSourceType == "atlas" then
        texture:SetAtlas(resolvedSourceValue, false)
        texture:Show()
        return
    end

    if resolvedSourceType == "file" then
        texture:SetTexture(resolvedSourceValue)
        texture:Show()
        return
    end

    texture:Hide()
end

local function FindEntryForSelection(entries, selection)
    if CooldownCompanion.FindAuraTexturePickerEntry then
        local matchedEntry = CooldownCompanion:FindAuraTexturePickerEntry(entries, selection)
        if matchedEntry then
            return matchedEntry
        end
    end

    if CooldownCompanion.FindAuraTexturePickerEntryByAsset then
        local matchedEntry = CooldownCompanion:FindAuraTexturePickerEntryByAsset(entries, selection)
        if matchedEntry then
            return matchedEntry
        end
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
    local stagedClear = false
    local activeThumbs = {}
    local currentThumbSize = BASE_THUMB_SIZE
    local suppressPathTextChanged = false

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

    local scrollFrame = pickerScrollFrame
    local scrollChild = pickerScrollChild
    if not scrollFrame or not scrollChild then
        scrollFrame = CreateFrame("ScrollFrame", nil, scrollGroup.frame)
        scrollChild = CreateFrame("Frame", nil, scrollFrame)
        pickerScrollFrame = scrollFrame
        pickerScrollChild = scrollChild
    else
        scrollFrame:SetParent(scrollGroup.frame)
        scrollChild:SetParent(scrollFrame)
    end
    scrollFrame:ClearAllPoints()
    scrollFrame:SetPoint("TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -4, 4)
    scrollFrame:Show()
    scrollFrame:EnableMouseWheel(true)

    scrollChild:SetSize(1, 1)
    scrollChild:Show()
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
            thumb:SetScript("OnMouseWheel", nil)
            if thumb._deleteBtn then
                thumb._deleteBtn:Hide()
                thumb._deleteBtn:SetScript("OnClick", nil)
                thumb._deleteBtn:SetScript("OnEnter", nil)
                thumb._deleteBtn:SetScript("OnLeave", nil)
            end
            thumb._entry = nil
            if thumb._hover then thumb._hover:Hide() end
            if thumb._selected then thumb._selected:Hide() end
            pickerThumbnailPool[#pickerThumbnailPool + 1] = thumb
        end
        wipe(activeThumbs)
    end

    local function CleanupRawGrid()
        ReleaseActiveThumbs()

        for _, thumb in ipairs(pickerThumbnailPool) do
            thumb:Hide()
            thumb:ClearAllPoints()
            thumb:SetScript("OnEnter", nil)
            thumb:SetScript("OnLeave", nil)
            thumb:SetScript("OnClick", nil)
            thumb:SetScript("OnMouseWheel", nil)
            if thumb._deleteBtn then
                thumb._deleteBtn:Hide()
                thumb._deleteBtn:SetScript("OnClick", nil)
                thumb._deleteBtn:SetScript("OnEnter", nil)
                thumb._deleteBtn:SetScript("OnLeave", nil)
            end
            thumb:SetParent(pickerParkingFrame)
            thumb._entry = nil
            if thumb._hover then thumb._hover:Hide() end
            if thumb._selected then thumb._selected:Hide() end
        end

        -- AceGUI recycles SimpleGroup frames, so these raw child frames must be
        -- detached before release or they can bleed into unrelated config UIs.
        -- Keep them parked in module-level pools so repeated open/close cycles
        -- reuse the same frames instead of quietly accumulating hidden ones.
        scrollFrame:SetScript("OnMouseWheel", nil)
        scrollFrame:SetScript("OnSizeChanged", nil)
        scrollFrame:EnableMouseWheel(false)
        scrollFrame:SetVerticalScroll(0)
        scrollFrame:SetScrollChild(scrollChild)
        scrollFrame:ClearAllPoints()
        scrollFrame:SetParent(pickerParkingFrame)
        scrollFrame:Hide()

        scrollChild:SetScript("OnMouseWheel", nil)
        scrollChild:EnableMouseWheel(false)
        scrollChild:SetParent(scrollFrame)
        scrollChild:SetSize(1, 1)
        scrollChild:Hide()
    end

    scrollGroup:SetCallback("OnRelease", function()
        CleanupRawGrid()
    end)

    local function UpdateSelectionLabel()
        if selectedEntry then
            selectionLabel:SetText((selectedEntry.label or "Texture") .. (selectedEntry.subtitle and ("  |  " .. selectedEntry.subtitle) or ""))
        elseif stagedClear then
            selectionLabel:SetText("Clear staged. Apply removes the current texture.")
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
        stagedClear = false
        applyBtn:SetDisabled(entry == nil)
        UpdateSelectionLabel()
        StageEntryPreview(entry)
        for _, thumb in ipairs(activeThumbs) do
            thumb._selected:SetShown(thumb._entry == entry)
        end
    end

    local function AcquireThumb()
        local thumb = table.remove(pickerThumbnailPool)
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

        local deleteBtn = CreateFrame("Button", nil, thumb)
        deleteBtn:SetSize(22, 22)
        deleteBtn:SetPoint("TOPRIGHT", thumb, "TOPRIGHT", -1, -1)
        deleteBtn:Hide()
        thumb._deleteBtn = deleteBtn

        local deleteTex = deleteBtn:CreateTexture(nil, "ARTWORK")
        deleteTex:SetPoint("TOPLEFT", 2, -2)
        deleteTex:SetPoint("BOTTOMRIGHT", -2, 2)
        deleteTex:SetAtlas("common-icon-redx", false)
        deleteBtn._icon = deleteTex

        local deleteText = deleteBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        deleteText:SetPoint("CENTER")
        deleteText:SetJustifyH("CENTER")
        deleteText:SetJustifyV("MIDDLE")
        deleteText:SetScale(1.75)
        deleteText:Hide()
        deleteBtn._text = deleteText

        return thumb
    end

    local function SetPathInputText(text)
        suppressPathTextChanged = true
        currentSearch = text or ""
        searchBox:SetText(currentSearch)
        suppressPathTextChanged = false
    end

    local function GetVisibleEntries()
        return CooldownCompanion:GetAuraTexturePickerEntries(currentSearch, currentFilter)
    end

    local function ConfigureThumbActionButton(thumb, entry)
        local actionMode = GetEntryActionMode(entry)
        local button = thumb._deleteBtn
        if not button then
            return
        end

        button._actionMode = actionMode
        if not actionMode then
            button:Hide()
            return
        end

        if actionMode == "addFavorite" then
            if button._icon then
                button._icon:Hide()
            end
            if button._text then
                button._text:SetText("+")
                button._text:SetTextColor(0.55, 1, 0.55, 1)
                button._text:Show()
            end
            return
        end

        if button._icon then
            button._icon:SetAtlas("common-icon-redx", false)
            button._icon:Show()
        end
        if button._text then
            button._text:SetText("")
            button._text:Hide()
        end
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

    local function UpdateInputMode()
        searchBox:SetLabel("Search")
    end

    searchBox:SetCallback("OnLeave", function()
        GameTooltip:Hide()
    end)

    local function RebuildGrid()
        ReleaseActiveThumbs()
        local entries = GetVisibleEntries()

        if #entries == 0 then
            if IsFavoritesFilter(currentFilter) and currentSearch == "" then
                statusLabel:SetText("No favorite textures yet. Browse any category and click + to save one here.")
            elseif IsFavoritesFilter(currentFilter) then
                statusLabel:SetText("No favorite textures matched the current search.")
            elseif IsSharedMediaFilter(currentFilter) then
                statusLabel:SetText("No SharedMedia textures matched the current search.")
            else
                statusLabel:SetText("No textures matched the current search.")
            end
        elseif IsFavoritesFilter(currentFilter) then
            statusLabel:SetText(("Showing %d favorite textures. Click the red X to remove one."):format(#entries))
        elseif IsSharedMediaFilter(currentFilter) then
            statusLabel:SetText(("Showing %d SharedMedia textures. Click + to favorite one, or the red X to remove it from Favorites."):format(#entries))
        else
            statusLabel:SetText(("Showing %d textures. Click + to favorite one, or the red X to remove it from Favorites."):format(#entries))
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
            ConfigureThumbActionButton(thumb, entry)
            ApplyEntryTexture(thumb._previewTex, entry)

            thumb:SetScript("OnEnter", function(self)
                self._hover:Show()
                if self._deleteBtn and GetEntryActionMode(entry) then
                    self._deleteBtn:Show()
                end
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
                if self._deleteBtn and self._deleteBtn:IsMouseOver() then
                    return
                end
                self._hover:Hide()
                if self._deleteBtn then
                    self._deleteBtn:Hide()
                end
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
            if thumb._deleteBtn then
                thumb._deleteBtn:SetScript("OnEnter", function()
                    thumb._deleteBtn:Show()
                    if thumb._hover then
                        thumb._hover:Show()
                    end
                    GameTooltip:SetOwner(thumb._deleteBtn, "ANCHOR_LEFT")
                    if thumb._deleteBtn._actionMode == "addFavorite" then
                        GameTooltip:AddLine("Add To Favorites")
                        GameTooltip:AddLine("Save this texture in the Favorites category.", 1, 1, 1, true)
                    elseif thumb._deleteBtn._actionMode == "removeFavorite" then
                        GameTooltip:AddLine("Remove From Favorites")
                        GameTooltip:AddLine("Keep the texture in its normal category, but remove it from Favorites.", 1, 1, 1, true)
                    end
                    GameTooltip:Show()
                end)
                thumb._deleteBtn:SetScript("OnLeave", function()
                    if thumb:IsMouseOver() then
                        thumb._deleteBtn:Show()
                        return
                    end
                    thumb._deleteBtn:Hide()
                    if thumb._hover then
                        thumb._hover:Hide()
                    end
                    GameTooltip:Hide()
                    if selectedEntry then
                        StageEntryPreview(selectedEntry)
                    else
                        ClearStagedPreview()
                    end
                end)
                thumb._deleteBtn:SetScript("OnClick", function()
                    if thumb._deleteBtn._actionMode == "addFavorite" then
                        local savedEntry = CooldownCompanion:SaveFavoriteAuraTexture(entry)
                        if savedEntry then
                            statusLabel:SetText((savedEntry.label or "Texture") .. " added to Favorites.")
                        else
                            statusLabel:SetText("That texture could not be added to Favorites.")
                        end
                    elseif thumb._deleteBtn._actionMode == "removeFavorite" then
                        CooldownCompanion:RemoveFavoriteAuraTexture(entry)
                        if selectedEntry == entry and IsFavoritesFilter(currentFilter) then
                            selectedEntry = nil
                        end
                        statusLabel:SetText((entry.label or "Texture") .. " removed from Favorites.")
                    end
                    GameTooltip:Hide()
                    RebuildGrid()
                end)
            end
            thumb:SetScript("OnMouseWheel", function(_, delta)
                ScrollGridByWheel(delta)
            end)

            thumb:Show()
            activeThumbs[#activeThumbs + 1] = thumb
        end

        scrollChild:SetWidth(math.max(1, contentWidth))
        scrollChild:SetHeight(math.max(1, contentHeight))
        SetGridScroll(0)
        applyBtn:SetDisabled(selectedEntry == nil and not stagedClear)
        UpdateSelectionLabel()
        -- Keep the live staged preview in sync after list rebuilds so list
        -- updates cannot leave an older hovered texture showing.
        if selectedEntry then
            StageEntryPreview(selectedEntry)
        elseif stagedClear then
            ClearStagedPreview()
        else
            ClearStagedPreview()
        end
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
    UpdateInputMode()

    sourceDrop:SetCallback("OnValueChanged", function(_, _, value)
        currentFilter = value or "symbols"
        UpdateInputMode()
        RebuildGrid()
    end)

    searchBox:SetCallback("OnTextChanged", function(_, _, text)
        if suppressPathTextChanged then
            return
        end
        currentSearch = text or ""
        RebuildGrid()
    end)

    applyBtn:SetCallback("OnClick", function()
        if (not selectedEntry and not stagedClear) or not currentOnCommit then
            return
        end
        local selection = selectedEntry and BuildPreviewSelection(currentGroupId, currentButtonIndex, selectedEntry) or nil
        currentSelection = selection
        currentOnCommit(selection)
        stagedClear = false
        if selectedEntry then
            StageEntryPreview(selectedEntry)
        else
            ClearStagedPreview()
        end
        UpdateSelectionLabel()
        CloseAuraTexturePicker()
    end)

    clearBtn:SetCallback("OnClick", function()
        selectedEntry = nil
        stagedClear = currentSelection ~= nil
        ClearStagedPreview()
        applyBtn:SetDisabled(not stagedClear)
        UpdateSelectionLabel()
        RebuildGrid()
    end)

    window:SetCallback("OnClose", function(widget)
        ClearStagedPreview()
        GameTooltip:Hide()
        CleanupRawGrid()
        widget._rebind = nil
        widget._refreshEntries = nil
        widget._targetGroupId = nil
        widget._targetButtonIndex = nil
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
        stagedClear = false
        window._targetGroupId = currentGroupId
        window._targetButtonIndex = currentButtonIndex
        window:SetTitle(newOpts.title or "Browse Texture Panel Visuals")

        currentFilter = CooldownCompanion:GetAuraTexturePickerFilterForSelection(currentSelection)
        currentSearch = (currentSelection and (currentSelection.label or currentSelection.sourceValue)) or ""

        UpdateInputMode()
        SetPathInputText(currentSearch or "")
        sourceDrop:SetValue(currentFilter)
        RebuildGrid()
    end

    currentFilter = CooldownCompanion:GetAuraTexturePickerFilterForSelection(currentSelection)
    currentSearch = (currentSelection and (currentSelection.label or currentSelection.sourceValue)) or ""

    UpdateInputMode()
    SetPathInputText(currentSearch)
    sourceDrop:SetValue(currentFilter)
    window._targetGroupId = currentGroupId
    window._targetButtonIndex = currentButtonIndex
    window._refreshEntries = RebuildGrid
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

local function RefreshAuraTexturePicker()
    if pickerWindow and pickerWindow._refreshEntries then
        pickerWindow._refreshEntries()
    end
end

CS.StartPickAuraTexture = StartPickAuraTexture
CS.CancelPickAuraTexture = CloseAuraTexturePicker
CS.RebindPickAuraTexture = RebindPickAuraTexture
CS.IsAuraTexturePickerOpen = IsAuraTexturePickerOpen
CS.RefreshAuraTexturePicker = RefreshAuraTexturePicker
