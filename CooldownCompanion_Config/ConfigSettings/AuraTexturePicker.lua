local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

-- Inline texture browser. The catalog used to live in a floating AceGUI Window
-- ("Browse Texture Panel Visuals"); it now renders as a takeover of the wide
-- column's settings area (ButtonsWideColumn owns the host + the takeover
-- branch; this file renders the grid + chrome into it via
-- ST._RenderInlineTextureBrowser). Hover = live preview, click = commit
-- immediately (no Apply button), Remove Texture empties the panel, Back returns to
-- the settings. Serves both texture panels and trigger panels.

local BASE_THUMB_SIZE = 64
local THUMB_GAP = 8
local MIN_COLUMNS = 1
local CONTENT_INSET = 6
local TAB_ROW_HEIGHT = 22
local TAB_GAP = 4
local TAB_TEXT_PAD = 12
local SEARCH_HEIGHT = 26
local ROW_GAP = 8
local BOTTOM_ROW_HEIGHT = 24
local FOOTER_TEXT_HEIGHT = 36
local STAR_SIZE = 16
local FILTER_SHAREDMEDIA = "sharedMedia"
local FILTER_FAVORITES = "favorites"

-- Browser state is module-scope (not a window closure) because the surface is
-- rebuilt from ButtonsWideColumn's refresh, and the chrome is created once and
-- reused across opens. The host is a persistent raw frame (never an
-- AceGUI-recycled one), so pooled thumbnails parked on its scroll child cannot
-- bleed onto sibling surfaces.
local chrome = nil
local thumbnailPool = {}
local activeThumbs = {}
local currentGroupId = nil
local currentButtonIndex = nil
local currentOnCommit = nil
local currentSelection = nil
local currentFilter = "symbols"
local currentSearch = ""
local currentThumbSize = BASE_THUMB_SIZE
local suppressSearchChanged = false

-- Selection wash/accent uses the player's class color, matching the quiet row
-- and the navigator (standing ruling: class wash + solid accent, no gold/glow).
local function GetSelectionColor()
    local classColor = C_ClassColor and C_ClassColor.GetClassColor(select(2, UnitClass("player")))
    if classColor then
        return classColor.r, classColor.g, classColor.b
    end
    return 1, 0.82, 0
end

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
    local baseSettings
    if group and group.displayMode == "trigger" then
        baseSettings = CooldownCompanion:GetTriggerPanelSignalSettings(group)
    else
        baseSettings = group and CooldownCompanion:GetTexturePanelSettings(group)
    end
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
        return CooldownCompanion:FindAuraTexturePickerEntry(entries, selection)
    end
    return nil
end

-- Keep authored names intact; make raw atlas identifiers readable only in
-- the browser. Saved selections and texture lookup still use the original ID.
local function GetEntryDisplayName(entry)
    local name = entry.label or tostring(entry.sourceValue or "Texture")
    if entry.sourceType ~= "atlas" or strtrim(name) ~= strtrim(tostring(entry.sourceValue)) then
        return name
    end
    name = strtrim(name):gsub("Questturnin", "Quest Turn In")
        :gsub("(%l)(%u)", "%1 %2"):gsub("[_%-]+", " "):gsub("%s+", " ")
    return (name:gsub("%S+", function(word)
        return word:sub(1, 1):upper() .. word:sub(2)
    end))
end

local function GetBrowserEntries()
    local entries = CooldownCompanion:GetAuraTexturePickerEntries("", currentFilter)
    local query = strtrim(currentSearch):lower()
    if query == "" then return entries end
    local matches = {}
    for _, entry in ipairs(entries) do
        local searchText = (entry.searchText or entry.label or ""):lower()
        if searchText:find(query, 1, true) or GetEntryDisplayName(entry):lower():find(query, 1, true) then
            matches[#matches + 1] = entry
        end
    end
    return matches
end

local function UpdateSelectionLabel(entry)
    if not chrome then return end
    local selection = entry or currentSelection
    if selection then
        local name = GetEntryDisplayName(selection)
        chrome.selectionLabel:SetText((entry and "Preview: " or "Current: ") .. name)
    else
        chrome.selectionLabel:SetText("No texture selected")
    end
end

local function ClearSearchFocus()
    if chrome then chrome.searchBox:ClearFocus() end
end

--------------------------------------------------------------------------------
-- Staging (hover live preview)
--------------------------------------------------------------------------------

-- Drop the staged texture from the active preview surface and repaint the
-- pinned mirror back to the saved texture. Guarded so no-op rebuilds do not
-- trigger redundant mirror rebuilds.
local function ClearStagedPreview()
    UpdateSelectionLabel()
    if CS.textureMirrorStage then
        CS.textureMirrorStage = nil
        if currentGroupId and ST._RefreshButtonsPreviewMirror then
            ST._RefreshButtonsPreviewMirror(currentGroupId)
        end
    end
end

-- Stage a hovered entry. Texture and trigger panels use the pinned mirror as
-- their only continuous preview.
local function StageEntryPreview(entry)
    if not currentGroupId then
        return
    end
    if not entry then
        ClearStagedPreview()
        return
    end
    local selection = BuildPreviewSelection(currentGroupId, currentButtonIndex, entry)
    UpdateSelectionLabel(entry)
    CS.textureMirrorStage = { groupId = currentGroupId, selection = selection }
    if ST._RefreshButtonsPreviewMirror then
        ST._RefreshButtonsPreviewMirror(currentGroupId)
    end
end

--------------------------------------------------------------------------------
-- Commit / close
--------------------------------------------------------------------------------

-- Click commits immediately, then returns to the settings. The flag is dropped
-- BEFORE the commit so the commit's RefreshConfigPanel rebuilds col3 into the
-- settings view (the takeover branch is gated on the flag). The saved texture
-- is updated by the commit callback, so the mirror repaints to it on rebuild.
local function CommitSelection(selection)
    ClearSearchFocus()
    GameTooltip:Hide()
    CS.inlineTextureBrowserOpen = nil
    CS.textureMirrorStage = nil
    currentSelection = selection
    if currentOnCommit then
        currentOnCommit(selection)
    end
end

-- Clear empties the panel but keeps the browser open so a replacement can be
-- picked immediately. The flag stays set, so the commit's RefreshConfigPanel
-- re-renders the grid (now with no selected tile and an empty big preview).
local function ClearPanelTexture()
    ClearSearchFocus()
    GameTooltip:Hide()
    CS.textureMirrorStage = nil
    currentSelection = nil
    if currentOnCommit then
        currentOnCommit(nil)
    end
end

-- Public close: drop the flag + staged previews and restore the settings area
-- (only when the config is up, so config-close cleanup doesn't rebuild col3).
-- Also the mutual-exclusion hook other side-windows call when they open.
local function CancelPickAuraTexture()
    if not CS.inlineTextureBrowserOpen then
        return
    end
    ClearSearchFocus()
    GameTooltip:Hide()
    CS.inlineTextureBrowserOpen = nil
    CS.textureMirrorStage = nil
    local configFrame = CS.configFrame
    if configFrame and configFrame.frame and configFrame.frame:IsShown()
        and ST._RefreshButtonsWideColumn then
        ST._RefreshButtonsWideColumn()
    end
end

--------------------------------------------------------------------------------
-- Grid
--------------------------------------------------------------------------------

-- Columns adapt to the wide workspace: as many BASE_THUMB_SIZE columns as the
-- viewport fits (min MIN_COLUMNS), then the thumbs grow slightly to fill the
-- leftover width so the grid isn't ragged.
local function GetGridMetrics(entryCount)
    local viewportWidth = chrome and chrome.scrollFrame:GetWidth() or 0
    if not viewportWidth or viewportWidth <= 0 then
        viewportWidth = (BASE_THUMB_SIZE + THUMB_GAP) * MIN_COLUMNS
    end

    local columns = math.max(MIN_COLUMNS,
        math.floor((viewportWidth + THUMB_GAP) / (BASE_THUMB_SIZE + THUMB_GAP)))
    local usable = viewportWidth - ((columns - 1) * THUMB_GAP)
    local thumbSize = math.max(1, math.floor(usable / columns))
    local contentWidth = math.max(1, (columns * thumbSize) + ((columns - 1) * THUMB_GAP))
    local rows = math.max(1, math.ceil((entryCount or 0) / columns))
    local contentHeight = (rows * thumbSize) + ((rows - 1) * THUMB_GAP)
    return columns, thumbSize, contentWidth, contentHeight
end

local function ClampScrollOffset(offset)
    local scrollFrame = chrome.scrollFrame
    local scrollChild = chrome.scrollChild
    local maxScroll = math.max(0, (scrollChild:GetHeight() or 0) - (scrollFrame:GetHeight() or 0))
    return math.min(math.max(offset or 0, 0), maxScroll)
end

local function SetGridScroll(offset)
    chrome.scrollFrame:SetVerticalScroll(ClampScrollOffset(offset))
end

local function ScrollGridByWheel(delta)
    if not delta or delta == 0 then
        return
    end
    SetGridScroll((chrome.scrollFrame:GetVerticalScroll() or 0) - (delta * (currentThumbSize + THUMB_GAP)))
end

-- Persistent favorite marks: a filled gold star shows on every favorited tile;
-- the "add" outline star only appears on hover so unfavorited tiles stay quiet.
local function UpdateThumbStar(thumb, hovered)
    local star = thumb._star
    if not star then
        return
    end
    local mode = star._mode
    if mode == "removeFavorite" then
        star:Show()
        star._icon:SetAlpha(hovered and 1 or 0.85)
    elseif mode == "addFavorite" then
        star:SetShown(hovered)
        star._icon:SetAlpha(hovered and 0.9 or 0)
    else
        star:Hide()
    end
end

local function ConfigureThumbStar(thumb, entry)
    local star = thumb._star
    if not star then
        return
    end
    local mode = GetEntryActionMode(entry)
    star._mode = mode
    if mode == "removeFavorite" then
        star._icon:SetAtlas("auctionhouse-icon-favorite", false)
    elseif mode == "addFavorite" then
        star._icon:SetAtlas("auctionhouse-icon-favorite-off", false)
    end
    UpdateThumbStar(thumb, false)
end

local function ReleaseActiveThumbs()
    for _, thumb in ipairs(activeThumbs) do
        thumb:Hide()
        thumb:ClearAllPoints()
        thumb._entry = nil
        if thumb._hover then thumb._hover:Hide() end
        if thumb._selected then thumb._selected:Hide() end
        if thumb._accent then thumb._accent:Hide() end
        if thumb._star then thumb._star:Hide() end
        thumbnailPool[#thumbnailPool + 1] = thumb
    end
    wipe(activeThumbs)
end

local function AcquireThumb()
    local thumb = table.remove(thumbnailPool)
    if thumb then
        thumb:SetParent(chrome.scrollChild)
        return thumb
    end

    thumb = CreateFrame("Button", nil, chrome.scrollChild)
    thumb:EnableMouseWheel(true)
    thumb:RegisterForClicks("LeftButtonUp")

    local previewBg = thumb:CreateTexture(nil, "BACKGROUND")
    previewBg:SetAllPoints()
    previewBg:SetColorTexture(0, 0, 0, 0.45)

    local previewTex = thumb:CreateTexture(nil, "ARTWORK")
    previewTex:SetAllPoints(previewBg)
    thumb._previewTex = previewTex

    -- Selected (matches the saved texture): class wash + solid left accent.
    local selected = thumb:CreateTexture(nil, "OVERLAY")
    selected:SetAllPoints()
    selected:Hide()
    thumb._selected = selected

    local accent = thumb:CreateTexture(nil, "OVERLAY")
    accent:SetPoint("TOPLEFT", thumb, "TOPLEFT", 0, 0)
    accent:SetPoint("BOTTOMLEFT", thumb, "BOTTOMLEFT", 0, 0)
    accent:SetWidth(3)
    accent:Hide()
    thumb._accent = accent

    -- HIGHLIGHT layer on a Button is mouse-gated automatically.
    local hover = thumb:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.08)
    thumb._hover = hover

    local star = CreateFrame("Button", nil, thumb)
    star:SetSize(STAR_SIZE, STAR_SIZE)
    star:SetPoint("TOPRIGHT", thumb, "TOPRIGHT", -2, -2)
    star:RegisterForClicks("LeftButtonUp")
    star:Hide()
    local starIcon = star:CreateTexture(nil, "OVERLAY")
    starIcon:SetAllPoints()
    star._icon = starIcon
    thumb._star = star

    return thumb
end

local function RebuildGrid()
    if not chrome then
        return
    end
    -- A rebuild can remove the hovered thumbnail without delivering OnLeave
    -- (for example when its favorite star removes the last filtered result).
    -- Reset the staged selection before recycling the thumbnail frames.
    ClearStagedPreview()
    GameTooltip:Hide()
    ReleaseActiveThumbs()

    local entries = GetBrowserEntries()

    local emptyText
    if #entries == 0 then
        if IsFavoritesFilter(currentFilter) and currentSearch == "" then
            emptyText = "No favorites yet."
        elseif IsFavoritesFilter(currentFilter) then
            emptyText = "No favorite textures match."
        elseif IsSharedMediaFilter(currentFilter) and currentSearch == "" then
            emptyText = "No SharedMedia textures available."
        else
            emptyText = "No textures match."
        end
    end
    chrome.emptyLabel:SetText(emptyText or "")
    chrome.emptyLabel:SetShown(emptyText ~= nil)
    chrome.statusLabel:SetText((#entries == 1 and "%d texture" or "%d textures"):format(#entries))
    chrome.clearBtn:SetDisabled(currentSelection == nil)

    local savedMatch = FindEntryForSelection(entries, currentSelection)

    local columns, thumbSize, contentWidth, contentHeight = GetGridMetrics(#entries)
    currentThumbSize = thumbSize
    local strideX = thumbSize + THUMB_GAP
    local strideY = thumbSize + THUMB_GAP

    local r, g, b = GetSelectionColor()

    for index, entry in ipairs(entries) do
        local thumb = AcquireThumb()
        local row = math.floor((index - 1) / columns)
        local col = (index - 1) % columns

        thumb:ClearAllPoints()
        thumb:SetSize(thumbSize, thumbSize)
        thumb:SetPoint("TOPLEFT", chrome.scrollChild, "TOPLEFT", col * strideX, -(row * strideY))
        thumb._entry = entry

        ApplyEntryTexture(thumb._previewTex, entry)

        local isSaved = (savedMatch ~= nil and entry == savedMatch)
        thumb._selected:SetColorTexture(r, g, b, 0.18)
        thumb._selected:SetShown(isSaved)
        thumb._accent:SetColorTexture(r, g, b, 0.9)
        thumb._accent:SetShown(isSaved)

        ConfigureThumbStar(thumb, entry)

        thumb:SetScript("OnEnter", function(self)
            self._hover:Show()
            UpdateThumbStar(self, true)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local name = GetEntryDisplayName(entry)
            GameTooltip:AddLine(name)
            if entry.sourceType == "atlas" and name ~= entry.sourceValue then
                GameTooltip:AddLine(entry.sourceValue, 0.7, 0.7, 0.7, true)
            end
            if entry.subtitle and entry.subtitle ~= "" then
                GameTooltip:AddLine(entry.subtitle, 1, 1, 1, true)
            elseif entry.category and entry.category ~= "" then
                GameTooltip:AddLine(entry.category, 1, 1, 1, true)
            end
            GameTooltip:Show()
            StageEntryPreview(entry)
        end)
        thumb:SetScript("OnLeave", function(self)
            if self._star and self._star:IsMouseOver() then
                return
            end
            self._hover:Hide()
            UpdateThumbStar(self, false)
            GameTooltip:Hide()
            ClearStagedPreview()
        end)
        thumb:SetScript("OnClick", function()
            CommitSelection(BuildPreviewSelection(currentGroupId, currentButtonIndex, entry))
        end)
        thumb:SetScript("OnMouseWheel", function(_, delta)
            ScrollGridByWheel(delta)
        end)

        local star = thumb._star
        star:SetScript("OnEnter", function(self)
            thumb._hover:Show()
            UpdateThumbStar(thumb, true)
            StageEntryPreview(thumb._entry)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            if self._mode == "addFavorite" then
                GameTooltip:AddLine("Add To Favorites")
                GameTooltip:AddLine("Save this texture in the Favorites category.", 1, 1, 1, true)
            else
                GameTooltip:AddLine("Remove From Favorites")
                GameTooltip:AddLine("Keep the texture in its category but drop it from Favorites.", 1, 1, 1, true)
            end
            GameTooltip:Show()
        end)
        star:SetScript("OnLeave", function()
            GameTooltip:Hide()
            if thumb:IsMouseOver() then
                UpdateThumbStar(thumb, true)
                return
            end
            thumb._hover:Hide()
            UpdateThumbStar(thumb, false)
            ClearStagedPreview()
        end)
        star:SetScript("OnClick", function(self)
            if self._mode == "addFavorite" then
                local saved = CooldownCompanion:SaveFavoriteAuraTexture(thumb._entry)
                if saved then
                    chrome.statusLabel:SetText(GetEntryDisplayName(saved) .. " added to Favorites.")
                end
            elseif self._mode == "removeFavorite" then
                CooldownCompanion:RemoveFavoriteAuraTexture(thumb._entry)
            end
            GameTooltip:Hide()
            RebuildGrid()
        end)

        thumb:Show()
        activeThumbs[#activeThumbs + 1] = thumb
    end

    chrome.scrollChild:SetWidth(math.max(1, contentWidth))
    chrome.scrollChild:SetHeight(math.max(1, contentHeight))
    SetGridScroll(0)
end

--------------------------------------------------------------------------------
-- Chrome (category tabs, search, grid scroll, status, buttons)
--------------------------------------------------------------------------------

local function UpdateTabSelection()
    if not chrome then
        return
    end
    local r, g, b = GetSelectionColor()
    for _, tab in ipairs(chrome.tabs) do
        local selected = tab._filter == currentFilter
        tab._wash:SetColorTexture(r, g, b, 0.14)
        tab._wash:SetShown(selected)
        tab._accent:SetColorTexture(r, g, b, 0.9)
        tab._accent:SetShown(selected)
        if selected then
            tab._label:SetTextColor(r, g, b, 1)
        else
            tab._label:SetTextColor(0.6, 0.6, 0.6, 1)
        end
    end
end

local function SelectFilter(filterKey)
    if currentFilter == filterKey then
        return
    end
    currentFilter = filterKey
    UpdateTabSelection()
    RebuildGrid()
end

local function BuildTabRow(host)
    local filterList, filterOrder = CooldownCompanion:GetAuraTexturePickerFilters()
    chrome.tabs = {}
    -- Iterate the ORDER array (not the options map) so the dormant "Custom"
    -- filter, which is deliberately excluded from the order, never gets a tab.
    for _, key in ipairs(filterOrder) do
        local tab = CreateFrame("Button", nil, host)
        tab:SetHeight(TAB_ROW_HEIGHT)
        tab._filter = key
        tab:RegisterForClicks("LeftButtonUp")

        local wash = tab:CreateTexture(nil, "BACKGROUND")
        wash:SetAllPoints()
        wash:Hide()
        tab._wash = wash

        local accent = tab:CreateTexture(nil, "ARTWORK")
        accent:SetHeight(2)
        accent:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
        accent:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
        accent:Hide()
        tab._accent = accent

        local hover = tab:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.06)

        local label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("CENTER")
        label:SetText(filterList[key] or key)
        tab._label = label
        tab._naturalWidth = label:GetStringWidth() + (TAB_TEXT_PAD * 2)
        label:ClearAllPoints()
        label:SetPoint("LEFT", tab, "LEFT", TAB_TEXT_PAD, 0)
        label:SetPoint("RIGHT", tab, "RIGHT", -TAB_TEXT_PAD, 0)
        label:SetJustifyH("CENTER")
        label:SetWordWrap(false)

        tab:SetScript("OnClick", function()
            SelectFilter(key)
        end)

        chrome.tabs[#chrome.tabs + 1] = tab
    end
end

-- Persistent chrome owns its AceGUI children for its entire lifetime, just
-- like the spellbook. It is never released into a recycled settings container.
local function LayoutChrome()
    local host = chrome.host
    local width = math.max(1, host:GetWidth() - CONTENT_INSET * 2)
    local tabX, tabY = 0, CONTENT_INSET + SEARCH_HEIGHT + ROW_GAP
    for _, tab in ipairs(chrome.tabs) do
        local tabWidth = math.min(width, tab._naturalWidth)
        if tabX > 0 and tabX + tabWidth > width then
            tabX = 0
            tabY = tabY + TAB_ROW_HEIGHT + TAB_GAP
        end
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", host, "TOPLEFT", CONTENT_INSET + tabX, -tabY)
        tab:SetWidth(tabWidth)
        tabX = tabX + tabWidth + TAB_GAP
    end

    local clearFrame, backFrame = chrome.clearBtn.frame, chrome.cancelBtn.frame
    local actionWidth = clearFrame:GetWidth() + ROW_GAP + backFrame:GetWidth()
    local stacked = width < actionWidth + 240
    local footerHeight = stacked and (FOOTER_TEXT_HEIGHT + ROW_GAP + BOTTOM_ROW_HEIGHT) or FOOTER_TEXT_HEIGHT
    backFrame:ClearAllPoints()
    backFrame:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -CONTENT_INSET, CONTENT_INSET)
    clearFrame:ClearAllPoints()
    clearFrame:SetPoint("RIGHT", backFrame, "LEFT", -ROW_GAP, 0)

    local textRightInset = CONTENT_INSET + (stacked and 0 or actionWidth + ROW_GAP)
    local textTop = CONTENT_INSET + footerHeight
    chrome.selectionLabel:ClearAllPoints()
    chrome.selectionLabel:SetPoint("TOPLEFT", host, "BOTTOMLEFT", CONTENT_INSET, textTop)
    chrome.selectionLabel:SetPoint("TOPRIGHT", host, "BOTTOMRIGHT", -textRightInset, textTop)
    chrome.statusLabel:ClearAllPoints()
    chrome.statusLabel:SetPoint("TOPLEFT", chrome.selectionLabel, "BOTTOMLEFT", 0, -4)
    chrome.statusLabel:SetPoint("TOPRIGHT", chrome.selectionLabel, "BOTTOMRIGHT", 0, -4)

    local gridTop = tabY + TAB_ROW_HEIGHT + ROW_GAP
    chrome.scrollFrame:ClearAllPoints()
    chrome.scrollFrame:SetPoint("TOPLEFT", host, "TOPLEFT", CONTENT_INSET, -gridTop)
    chrome.scrollFrame:SetPoint("TOPRIGHT", host, "TOPRIGHT", -CONTENT_INSET, -gridTop)
    chrome.scrollFrame:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", CONTENT_INSET, CONTENT_INSET + footerHeight + ROW_GAP)
    chrome.scrollFrame:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -CONTENT_INSET, CONTENT_INSET + footerHeight + ROW_GAP)
end

local function BuildChrome(host)
    chrome = { host = host }
    BuildTabRow(host)

    local searchBox = AceGUI:Create("EditBox")
    searchBox:SetLabel("")
    searchBox:DisableButton(true)
    searchBox:SetText("")
    searchBox.frame:SetParent(host)
    searchBox.frame:ClearAllPoints()
    searchBox.frame:SetPoint("TOPLEFT", host, "TOPLEFT", CONTENT_INSET, -CONTENT_INSET)
    searchBox.frame:SetPoint("TOPRIGHT", host, "TOPRIGHT", -CONTENT_INSET - 22, -CONTENT_INSET)
    searchBox.frame:Show()
    chrome.searchBox = searchBox

    chrome.help = ST._CreateInfoButton(host, searchBox.frame, "LEFT", "RIGHT", 4, 0, {
        "Texture Browser",
        { "Hover a texture to preview it. Click to use it and return to settings. Back to Settings keeps your current texture.", 1, 1, 1, true },
        { "Click a texture's star to add or remove it from Favorites.", 1, 1, 1, true },
        { "Search by name or texture identifier. If no textures match, try another search or category.", 1, 1, 1, true },
        { "SharedMedia textures come from installed SharedMedia texture collections.", 1, 1, 1, true },
    })

    if searchBox.editbox.Instructions then searchBox.editbox.Instructions:Hide() end
    -- Keep the placeholder above skins' editbox backdrops without attaching
    -- persistent regions to an AceGUI widget that another owner might recycle.
    local searchHintHost = CreateFrame("Frame", nil, host)
    searchHintHost:SetAllPoints(searchBox.editbox)
    searchHintHost:SetFrameLevel(searchBox.editbox:GetFrameLevel() + 1)
    local searchHint = searchHintHost:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchHint:SetPoint("LEFT", searchBox.editbox, "LEFT", 6, 0)
    searchHint:SetPoint("RIGHT", searchBox.editbox, "RIGHT", -6, 0)
    searchHint:SetJustifyH("LEFT")
    searchHint:SetWordWrap(false)
    searchHint:SetText("Search textures...")
    chrome.searchHint = searchHint
    searchBox:SetCallback("OnTextChanged", function(_, _, text)
        searchHint:SetShown((text or "") == "")
        if suppressSearchChanged then return end
        currentSearch = text or ""
        RebuildGrid()
    end)

    local cancelBtn = AceGUI:Create("Button")
    cancelBtn:SetAutoWidth(true)
    cancelBtn:SetText("Back to Settings")
    cancelBtn.frame:SetParent(host)
    cancelBtn.frame:Show()
    cancelBtn:SetCallback("OnClick", CancelPickAuraTexture)
    chrome.cancelBtn = cancelBtn

    local clearBtn = AceGUI:Create("Button")
    clearBtn:SetAutoWidth(true)
    clearBtn:SetText("Remove Texture")
    clearBtn.frame:SetParent(host)
    clearBtn.frame:Show()
    clearBtn:SetCallback("OnClick", ClearPanelTexture)
    chrome.clearBtn = clearBtn

    local selectionLabel = host:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    selectionLabel:SetJustifyH("LEFT")
    selectionLabel:SetWordWrap(false)
    chrome.selectionLabel = selectionLabel

    local statusLabel = host:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    statusLabel:SetJustifyH("LEFT")
    statusLabel:SetWordWrap(false)
    chrome.statusLabel = statusLabel

    local scrollFrame = CreateFrame("ScrollFrame", nil, host)
    scrollFrame:EnableMouseWheel(true)
    chrome.scrollFrame = scrollFrame

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(1, 1)
    scrollFrame:SetScrollChild(scrollChild)
    chrome.scrollChild = scrollChild

    local emptyLabel = scrollFrame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyLabel:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 12, -24)
    emptyLabel:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", -12, -24)
    emptyLabel:SetJustifyH("CENTER")
    emptyLabel:SetWordWrap(true)
    emptyLabel:Hide()
    chrome.emptyLabel = emptyLabel

    -- This host is addon-owned; unlike the AceGUI children it is not pooled.
    host:HookScript("OnHide", function()
        ClearSearchFocus()
        CS.textureMirrorStage = nil
        GameTooltip:Hide()
        UpdateSelectionLabel()
    end)
    host:HookScript("OnSizeChanged", LayoutChrome)

    scrollFrame:SetScript("OnMouseWheel", function(_, delta)
        ScrollGridByWheel(delta)
    end)

    -- Re-lay the grid once the viewport width settles (the host has no width on
    -- the first render pass); ignore sub-pixel jitter.
    local lastWidth = 0
    scrollFrame:SetScript("OnSizeChanged", function(_, width)
        if type(width) ~= "number" or width <= 0 then
            return
        end
        if math.abs(width - lastWidth) <= 1 then
            return
        end
        lastWidth = width
        RebuildGrid()
    end)
end

--------------------------------------------------------------------------------
-- Render entry point (called by ButtonsWideColumn's takeover branch)
--------------------------------------------------------------------------------

local function RenderInlineTextureBrowser(host)
    if not chrome then
        BuildChrome(host)
    end
    LayoutChrome()
    UpdateTabSelection()
    -- Sync the search box to the current filter reset without re-triggering the
    -- filter handler.
    suppressSearchChanged = true
    chrome.searchBox:SetText(currentSearch)
    chrome.searchHint:SetShown(currentSearch == "")
    suppressSearchChanged = false
    RebuildGrid()
end

--------------------------------------------------------------------------------
-- Public contract (preserved for the GroupTabs call sites)
--------------------------------------------------------------------------------

-- Open (or re-point) the inline browser for a panel, then refresh col3 so the
-- takeover branch renders it. Callers always invoke this outside a config
-- refresh (a Browse click, a big-preview click, or a deferred pending-open
-- timer), so RefreshConfigPanel here is never re-entrant.
local function OpenBrowser(opts)
    ClearSearchFocus()
    ClearStagedPreview()
    opts = opts or {}

    -- Match the retired picker window's mutual-exclusion contract before the
    -- inline browser takes over the settings area.
    if CS.CloseAdvancedSettingsPanel then
        CS.CloseAdvancedSettingsPanel({ skipRefresh = true })
    end
    if CS.CloseProfileWideFontWindow then
        CS.CloseProfileWideFontWindow()
    end
    if CS.CloseProfileWideBarTextureWindow then
        CS.CloseProfileWideBarTextureWindow()
    end
    if CS.CloseSpellbookPanel then
        CS.CloseSpellbookPanel()
    end

    currentGroupId = opts.groupId or CS.selectedGroup
    currentButtonIndex = opts.buttonIndex
    currentOnCommit = opts.callback
    currentSelection = (opts.initialSelection and opts.initialSelection.sourceType and opts.initialSelection) or nil
    currentFilter = CooldownCompanion:GetAuraTexturePickerFilterForSelection(currentSelection)
    currentSearch = ""
    CS.inlineTextureBrowserOpen = currentGroupId
    CooldownCompanion:RefreshConfigPanel()
end

local function StartPickAuraTexture(opts)
    OpenBrowser(opts)
end

local function RebindPickAuraTexture(opts)
    OpenBrowser(opts)
end

local function IsAuraTexturePickerOpen()
    return CS.inlineTextureBrowserOpen ~= nil
end

local function RefreshAuraTexturePicker()
    if CS.inlineTextureBrowserOpen and chrome then
        RebuildGrid()
    end
end

CS.StartPickAuraTexture = StartPickAuraTexture
CS.CancelPickAuraTexture = CancelPickAuraTexture
CS.RebindPickAuraTexture = RebindPickAuraTexture
CS.IsAuraTexturePickerOpen = IsAuraTexturePickerOpen
CS.RefreshAuraTexturePicker = RefreshAuraTexturePicker
ST._RenderInlineTextureBrowser = RenderInlineTextureBrowser
