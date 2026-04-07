local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

local BASE_THUMB_SIZE = 64
local THUMB_GAP = 8
local DEFAULT_THUMBS_PER_ROW = 5
local GRID_HEIGHT = 452
local FILTER_CUSTOM = "custom"

local pickerWindow = nil
local pickerParkingFrame = CreateFrame("Frame", nil, UIParent)
pickerParkingFrame:Hide()
local pickerThumbnailPool = {}
local pickerScrollFrame = nil
local pickerScrollChild = nil
local customTextureValidationFrame = CreateFrame("Frame", nil, UIParent)
customTextureValidationFrame:Hide()
local customTextureValidationTexture = customTextureValidationFrame:CreateTexture(nil, "ARTWORK")
-- Request blocking loads here so valid custom textures can report their native
-- size immediately when the user adds them to the saved custom shelf.
customTextureValidationTexture:SetBlockingLoadsRequested(true)

local function IsCustomFilter(filterValue)
    return filterValue == FILTER_CUSTOM
end

local function ValidateCustomTexturePath(path)
    local normalizedPath = CooldownCompanion:NormalizeCustomAuraTexturePath(path)
    if not normalizedPath then
        return nil, nil, nil, "Enter a WoW texture path like Interface\\AddOns\\MyPack\\Texture.tga."
    end

    customTextureValidationTexture:SetTexture(nil)
    local success = customTextureValidationTexture:SetTexture(normalizedPath)
    if not success or customTextureValidationTexture:GetTexture() == nil then
        customTextureValidationTexture:SetTexture(nil)
        return nil, nil, nil, "Texture could not be loaded. Check the path, format, and dimensions."
    end

    if not customTextureValidationTexture:IsObjectLoaded() then
        customTextureValidationTexture:SetTexture(nil)
        return nil, nil, nil, "Texture has not finished loading yet. Check the path and try again."
    end

    local width, height = customTextureValidationTexture:GetSize()
    if type(width) ~= "number" or width <= 0 or type(height) ~= "number" or height <= 0 then
        customTextureValidationTexture:SetTexture(nil)
        return nil, nil, nil, "Texture size could not be read. Check the file and try again."
    end

    customTextureValidationTexture:SetTexture(nil)
    return normalizedPath, width, height, nil
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
        entry.sourceValue
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
        return CooldownCompanion:FindAuraTexturePickerEntry(entries, selection)
    end

    if type(selection) ~= "table" then
        return nil
    end

    return nil
end

local function GetCustomEntryLabel(path)
    if type(path) ~= "string" or path == "" then
        return "Custom Texture"
    end

    local fileName = path:match("([^\\]+)$")
    return fileName or path
end

local function BuildTransientCurrentCustomEntry(selection)
    if not CooldownCompanion:IsCustomAuraTextureSelection(selection) then
        return nil
    end

    local normalizedPath = CooldownCompanion:NormalizeCustomAuraTexturePath(selection.sourceValue)
    if not normalizedPath then
        return nil
    end

    local label = selection.label or GetCustomEntryLabel(normalizedPath)
    return {
        key = selection.libraryKey or ("custom:" .. string.lower(normalizedPath)),
        libraryKey = selection.libraryKey or ("custom:" .. string.lower(normalizedPath)),
        label = label,
        categoryKey = FILTER_CUSTOM,
        category = "Custom",
        sourceType = "file",
        sourceValue = normalizedPath,
        width = selection.width,
        height = selection.height,
        color = selection.color,
        blendMode = selection.blendMode,
        scale = selection.scale,
        layoutAgnostic = true,
        subtitle = normalizedPath .. "  |  Current selection (not saved)",
        searchText = string.lower(label .. " " .. normalizedPath .. " current selection custom texture"),
        isTransientCustomTexture = true,
    }
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
        deleteBtn:SetSize(16, 16)
        deleteBtn:SetPoint("TOPRIGHT", thumb, "TOPRIGHT", -2, -2)
        deleteBtn:Hide()
        thumb._deleteBtn = deleteBtn

        local deleteTex = deleteBtn:CreateTexture(nil, "ARTWORK")
        deleteTex:SetAllPoints()
        deleteTex:SetAtlas("common-icon-redx", false)
        deleteBtn._icon = deleteTex

        return thumb
    end

    local function SetPathInputText(text)
        suppressPathTextChanged = true
        currentSearch = text or ""
        searchBox:SetText(currentSearch)
        suppressPathTextChanged = false
    end

    local function GetUnsavedCurrentCustomPath()
        if not IsCustomFilter(currentFilter) or not CooldownCompanion:IsCustomAuraTextureSelection(currentSelection) then
            return nil
        end

        local savedEntries = CooldownCompanion:GetAuraTexturePickerEntries("", FILTER_CUSTOM)
        if FindEntryForSelection(savedEntries, currentSelection) then
            return nil
        end

        return CooldownCompanion:NormalizeCustomAuraTexturePath(currentSelection.sourceValue)
    end

    local function GetVisibleEntries()
        if IsCustomFilter(currentFilter) then
            local entries = CooldownCompanion:GetAuraTexturePickerEntries("", currentFilter)
            if not FindEntryForSelection(entries, currentSelection) then
                local transientEntry = BuildTransientCurrentCustomEntry(currentSelection)
                if transientEntry then
                    table.insert(entries, 1, transientEntry)
                end
            end
            return entries
        end
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

    local function UpdateInputMode()
        if IsCustomFilter(currentFilter) then
            searchBox:SetLabel("Texture Path")
        else
            searchBox:SetLabel("Search")
        end
    end

    searchBox:SetCallback("OnEnter", function(widget)
        if not IsCustomFilter(currentFilter) then
            return
        end

        GameTooltip:SetOwner(widget.frame, "ANCHOR_TOP")
        GameTooltip:AddLine("Custom Texture Path")
        GameTooltip:AddLine("Enter a WoW texture path.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Rules:", 1, 0.82, 0, true)
        GameTooltip:AddLine("- Must start with Interface\\", 1, 1, 1, true)
        GameTooltip:AddLine("- Do not use C:\\ or other OS paths", 1, 1, 1, true)
        GameTooltip:AddLine("- PNG paths must include the .png file extension", 1, 1, 1, true)
        GameTooltip:AddLine("- BLP, JPG, JPEG, and TGA paths can include the file extension or omit it", 1, 1, 1, true)
        GameTooltip:AddLine("- If more than one file shares the same name, include the file extension", 1, 1, 1, true)
        GameTooltip:AddLine("- Image dimensions must be power-of-two, like 64x64 or 256x128", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Example:", 1, 0.82, 0, true)
        GameTooltip:AddLine("Interface\\AddOns\\Pack\\Glow.tga", 1, 1, 1, true)
        GameTooltip:Show()
    end)

    searchBox:SetCallback("OnLeave", function()
        GameTooltip:Hide()
    end)

    local function RebuildGrid()
        ReleaseActiveThumbs()
        local entries = GetVisibleEntries()

        if #entries == 0 then
            if IsCustomFilter(currentFilter) then
                statusLabel:SetText("Enter a WoW texture path and press Enter to add it to Custom.")
            else
                statusLabel:SetText("No textures matched the current search.")
            end
        elseif IsCustomFilter(currentFilter) then
            statusLabel:SetText(("Showing %d custom textures. Press Enter to add another."):format(#entries))
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
            if thumb._deleteBtn then
                thumb._deleteBtn:Hide()
            end
            ApplyEntryTexture(thumb._previewTex, entry)

            thumb:SetScript("OnEnter", function(self)
                self._hover:Show()
                if self._deleteBtn and entry.isCustomTexture then
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
                    CooldownCompanion:RemoveCustomAuraTexture(entry.libraryKey or entry.key or entry.sourceValue)
                    if selectedEntry == entry then
                        selectedEntry = nil
                    end
                    if IsCustomFilter(currentFilter) then
                        SetPathInputText(GetUnsavedCurrentCustomPath() or "")
                    end
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
        -- Keep the live staged preview in sync after list rebuilds so adding or
        -- removing a custom tile cannot leave an older hovered texture showing.
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
        if IsCustomFilter(currentFilter) then
            SetPathInputText(GetUnsavedCurrentCustomPath() or "")
        else
            SetPathInputText("")
        end
        RebuildGrid()
    end)

    searchBox:SetCallback("OnTextChanged", function(_, _, text)
        if suppressPathTextChanged then
            return
        end
        currentSearch = text or ""
        if IsCustomFilter(currentFilter) then
            if currentSearch == "" then
                RebuildGrid()
            else
                statusLabel:SetText("Press Enter to add this path to Custom.")
            end
            return
        end
        RebuildGrid()
    end)

    searchBox:SetCallback("OnEnterPressed", function(_, _, value)
        if not IsCustomFilter(currentFilter) then
            return
        end

        local normalizedPath, width, height, err = ValidateCustomTexturePath(value)
        if not normalizedPath then
            statusLabel:SetText(err or "Texture could not be added.")
            return
        end

        local existingEntry, pathToSave, resolveErr = CooldownCompanion:ResolveCustomAuraTextureSubmission(normalizedPath)
        if resolveErr then
            statusLabel:SetText(resolveErr)
            return
        end

        -- Custom submissions reuse an existing shelf tile when the typed path
        -- clearly points at the same saved texture, and otherwise require the
        -- user to disambiguate with a file extension before adding a new one.
        local entry = existingEntry
        if not entry then
            entry = CooldownCompanion:SaveCustomAuraTexture(pathToSave or normalizedPath, width, height)
        end
        if not entry then
            statusLabel:SetText("Texture could not be added.")
            return
        end

        currentSearch = ""
        SetPathInputText("")
        selectedEntry = entry
        stagedClear = false
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
        currentSearch = IsCustomFilter(currentFilter)
            and (GetUnsavedCurrentCustomPath() or "")
            or ((currentSelection and (currentSelection.label or currentSelection.sourceValue)) or "")

        UpdateInputMode()
        SetPathInputText(currentSearch or "")
        sourceDrop:SetValue(currentFilter)
        RebuildGrid()
    end

    currentFilter = CooldownCompanion:GetAuraTexturePickerFilterForSelection(currentSelection)
    currentSearch = IsCustomFilter(currentFilter)
        and (GetUnsavedCurrentCustomPath() or "")
        or ((currentSelection and (currentSelection.label or currentSelection.sourceValue)) or "")

    UpdateInputMode()
    SetPathInputText(currentSearch)
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
