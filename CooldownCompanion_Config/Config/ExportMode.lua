--[[
    CooldownCompanion - Config/ExportMode
    Export mode lifecycle, selection model, setup-payload assembly, and the
    wide-column export summary. The Navigator's export checklist rendering
    lives in Config/Column1.lua so it can reuse the tree row helpers.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local AceGUI = LibStub("AceGUI-3.0")

local BuildGroupExportData = ST._BuildGroupExportData
local BuildContainerExportData = ST._BuildContainerExportData
local EncodeExportData = ST._EncodeExportData
local BuildSetupExportPayload = ST._BuildSetupExportPayload
local ShowPopupAboveConfig = ST._ShowPopupAboveConfig

------------------------------------------------------------------------
-- Mode lifecycle. CS.exportMode is nil when inactive; while active it
-- holds the mode's own selection and expansion state so the user's normal
-- navigator selection survives the round trip untouched.
------------------------------------------------------------------------

local HideAllExportPreviewTiles

local function IsExportModeActive()
    return CS.exportMode ~= nil
end

local function EnterExportMode()
    if CS.exportMode then return end
    if CooldownCompanion._unsupportedLegacyProfile then
        CooldownCompanion:Print("Export is unavailable for unsupported profiles.")
        return
    end
    if CS.talentPickerMode and CooldownCompanion.CloseTalentPicker then
        CooldownCompanion:CloseTalentPicker()
    end
    if CooldownCompanion.IsArrangeModeActive and CooldownCompanion:IsArrangeModeActive()
        and CooldownCompanion.ExitArrangeMode then
        CooldownCompanion:ExitArrangeMode()
    end
    -- The two modes are rivals for the same two columns.
    if CS.importMode and ST._ExitImportMode then
        ST._ExitImportMode()
    end
    -- A refresh already follows this entry.
    if CS.copyCustomization and ST._CancelCopyCustomization then
        ST._CancelCopyCustomization({ skipRefresh = true })
    end
    CloseDropDownMenus()

    -- Fresh selection on every entry: each export is its own curation.
    CS.exportMode = {
        selection = {
            containers = {},
            panels = {},
            resources = false,
            customBars = {},
        },
        expanded = {},
    }
    if ST._UpdateExportModeTitleButton then
        ST._UpdateExportModeTitleButton()
    end
    CooldownCompanion:RefreshConfigPanel()
end

-- options.skipRefresh: the caller already has a refresh coming (profile
-- teardown), so the mode is torn down without triggering its own.
local function ExitExportMode(options)
    if not CS.exportMode then return end
    CS.exportMode = nil
    if HideAllExportPreviewTiles then
        HideAllExportPreviewTiles()
    end
    local col3 = CS.configFrame and CS.configFrame.col3
    if col3 and col3._exportSummaryScroll then
        -- Release before hiding: a hidden scroll's pooled bands keep their
        -- resize hooks and their references into the shared tile pool.
        col3._exportSummaryScroll:ReleaseChildren()
        col3._exportSummaryScroll.frame:Hide()
    end
    if ST._UpdateExportModeTitleButton then
        ST._UpdateExportModeTitleButton()
    end
    if not (options and options.skipRefresh) then
        CooldownCompanion:RefreshConfigPanel()
    end
end

local function ToggleExportMode()
    if CS.exportMode then
        ExitExportMode()
    else
        EnterExportMode()
    end
end

------------------------------------------------------------------------
-- Selection queries shared by the Navigator renderer and the summary.
------------------------------------------------------------------------

local function GetExportSelection()
    return CS.exportMode and CS.exportMode.selection or nil
end

local function GetResourceBarClassKey()
    return CooldownCompanion.GetCurrentResourceBarClassKey
        and CooldownCompanion:GetCurrentResourceBarClassKey()
        or nil
end

local function IsResourcesExportable()
    local classKey = GetResourceBarClassKey()
    return classKey ~= nil
        and CooldownCompanion.IsResourceBarClassConfigured
        and CooldownCompanion:IsResourceBarClassConfigured(classKey)
end

local function GetExportableCustomBars()
    local rb = ST._RB
    if not (rb and rb.GetAllCustomBars) then
        return {}
    end
    local settings = CooldownCompanion:GetResourceBarSettings()
    if type(settings) ~= "table" then
        return {}
    end
    local bars = {}
    for _, entry in ipairs(rb.GetAllCustomBars(settings) or {}) do
        local customBarId = rb.EnsureCustomBarId and rb.EnsureCustomBarId(settings, entry) or entry.customBarId
        if type(customBarId) == "string" and customBarId ~= "" then
            bars[#bars + 1] = {
                customBarId = customBarId,
                entry = entry,
                label = entry.label
                    or (entry.spellID and C_Spell.GetSpellName(entry.spellID))
                    or ("Custom Bar " .. tostring(#bars + 1)),
                icon = (entry.spellID and C_Spell.GetSpellTexture(entry.spellID)) or 134400,
            }
        end
    end
    return bars
end

local function CountExportSelection()
    local selection = GetExportSelection()
    if not selection then
        return 0
    end
    local count = 0
    for _ in pairs(selection.containers) do count = count + 1 end
    if selection.resources then count = count + 1 end
    for _ in pairs(selection.customBars) do count = count + 1 end
    return count
end

------------------------------------------------------------------------
-- Payload assembly and confirm.
------------------------------------------------------------------------

local function BuildCheckedContainerEntries(selection)
    local db = CooldownCompanion.db.profile
    local ordered = {}
    for cid in pairs(selection.containers) do
        local container = db.groupContainers and db.groupContainers[cid]
        if container then
            ordered[#ordered + 1] = {
                cid = cid,
                container = container,
                order = CooldownCompanion:GetOrderForSpec(container, CooldownCompanion._currentSpecId, cid),
            }
        end
    end
    table.sort(ordered, function(a, b) return a.order < b.order end)

    local entries = {}
    for _, item in ipairs(ordered) do
        local panels = {}
        for _, panelInfo in ipairs(CooldownCompanion:GetPanels(item.cid)) do
            if selection.panels[panelInfo.groupId] then
                local panelData = BuildGroupExportData(panelInfo.group)
                panelData._originalGroupId = panelInfo.groupId
                panels[#panels + 1] = panelData
            end
        end
        entries[#entries + 1] = {
            container = BuildContainerExportData(item.container),
            panels = panels,
            _originalContainerId = item.cid,
        }
    end
    if #entries == 0 then
        return nil
    end
    return entries
end

local function BuildExportModePayload()
    local selection = GetExportSelection()
    if not selection then
        return nil
    end

    local sections = {}
    sections.containers = BuildCheckedContainerEntries(selection)

    local rb = ST._RB
    if selection.resources and rb and rb.BuildResourcesSetupSection then
        sections.resources = rb.BuildResourcesSetupSection(
            CooldownCompanion:GetResourceBarSettings(),
            GetResourceBarClassKey())
    elseif next(selection.customBars) and rb and rb.BuildCustomBarsExportPayload then
        -- The Resources section already carries every Custom Bar, so a bars
        -- section is only built when Resources is not checked.
        local settings = CooldownCompanion:GetResourceBarSettings()
        local chosen = {}
        for _, info in ipairs(GetExportableCustomBars()) do
            if selection.customBars[info.customBarId] then
                chosen[#chosen + 1] = info.entry
            end
        end
        if #chosen > 0 then
            sections.customBars = rb.BuildCustomBarsExportPayload(settings, chosen)
        end
    end

    return BuildSetupExportPayload and BuildSetupExportPayload(sections) or nil
end

local function ConfirmExportMode()
    if not CS.exportMode then return end
    local payload = BuildExportModePayload()
    if not payload then
        CooldownCompanion:Print("Nothing selected to export.")
        return
    end
    local exportString = EncodeExportData and EncodeExportData(payload)
    if not exportString then
        -- The conflict blocker already printed why.
        return
    end
    ExitExportMode()
    if ShowPopupAboveConfig then
        ShowPopupAboveConfig("CDC_EXPORT_GROUP", nil, { exportString = exportString })
    end
end

------------------------------------------------------------------------
-- Wide-column export summary: one flat surface, no preview, no divider.
------------------------------------------------------------------------

------------------------------------------------------------------------
-- Panel preview tiles for the summary: the same read-only mirrors the
-- Group overview tiles use, pooled module-locally. Tiles are raw frames
-- that ride inside pooled AceGUI bands, so the one hard rule is that
-- every tile is HIDDEN before its band can ever return to the AceGUI
-- pool - a shown orphan on a pooled frame is the Navigator badge leak
-- all over again.
------------------------------------------------------------------------

-- The Group overview's tile grammar, replicated: bordered tiles, gold name
-- label inside the border, columns by panel count, and median-clamped
-- natural-width weighting so wide panels earn wider tiles.
local EXPORT_TILE_ROW_HEIGHT = 100
local EXPORT_TILE_GAP = 8
local EXPORT_TILE_INSET = 4
local EXPORT_TILE_LABEL_HEIGHT = 18
local EXPORT_TILE_BORDER_COLOR = { 0.24, 0.34, 0.46, 0.85 }

local exportPreviewTiles = {}

local function GetExportTileColumns(count)
    if count <= 1 then return 1 end
    if count == 2 or count == 4 then return 2 end
    return 3
end

local function GetExportTileRowCount(count)
    local columns = GetExportTileColumns(count)
    return math.ceil(count / columns)
end

local function AcquireExportPreviewTile(index)
    local tile = exportPreviewTiles[index]
    if not tile then
        tile = CreateFrame("Frame", nil, UIParent)
        tile:Hide()
        tile:SetClipsChildren(true)
        if ST.CreateBorderTextureSet and ST.ApplyBorderTextures then
            tile.borderTextures = ST.CreateBorderTextureSet(tile, "OVERLAY", 7)
            ST.ApplyBorderTextures(tile.borderTextures, tile,
                EXPORT_TILE_BORDER_COLOR, 1, ST.BORDER_RENDER_MODE_CRISP)
        end
        tile.label = tile:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tile.label:SetPoint("TOPLEFT", tile, "TOPLEFT", 6, -4)
        tile.label:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -6, -4)
        tile.label:SetJustifyH("LEFT")
        tile.label:SetWordWrap(false)
        tile.previewHost = CreateFrame("Frame", nil, tile)
        tile.previewHost:SetClipsChildren(true)
        exportPreviewTiles[index] = tile
    end
    return tile
end

HideAllExportPreviewTiles = function()
    for _, tile in ipairs(exportPreviewTiles) do
        if ST._ReleaseReadOnlyPanelPreview then
            ST._ReleaseReadOnlyPanelPreview(tile.previewHost)
        end
        tile:Hide()
        tile:ClearAllPoints()
    end
end

local function LayoutExportPreviewBand(band)
    local tiles = band._cdcExportTiles
    if not tiles or #tiles == 0 then return end
    local width = band.frame:GetWidth() or 0
    if width < 80 then return end
    if band._cdcLastLayoutWidth and math.abs(band._cdcLastLayoutWidth - width) < 1 then
        return
    end
    band._cdcLastLayoutWidth = width

    local columns = GetExportTileColumns(#tiles)
    local layoutWidth = width - 8
    local index = 1
    local top = 0

    while index <= #tiles do
        local rowCount = math.min(columns, #tiles - index + 1)

        local weights = {}
        for offset = 0, rowCount - 1 do
            weights[#weights + 1] = tiles[index + offset].weight or 1
        end
        table.sort(weights)
        local mid = (#weights + 1) / 2
        local median
        if mid == math.floor(mid) then
            median = weights[mid]
        else
            median = (weights[math.floor(mid)] + weights[math.floor(mid) + 1]) / 2
        end
        median = math.max(1, median)

        local baseColumnWidth = (layoutWidth - ((columns - 1) * EXPORT_TILE_GAP)) / columns
        local rowSpan = (baseColumnWidth * rowCount) + ((rowCount - 1) * EXPORT_TILE_GAP)
        local rowStartX = 4 + ((layoutWidth - rowSpan) / 2)
        local distributable = rowSpan - ((rowCount - 1) * EXPORT_TILE_GAP)

        local weightSum = 0
        for offset = 0, rowCount - 1 do
            local info = tiles[index + offset]
            local weight = info.weight or 1
            info.layoutWeight = math.max(median * 0.75, math.min(weight, median * 1.5))
            weightSum = weightSum + info.layoutWeight
        end

        local x = rowStartX
        for offset = 0, rowCount - 1 do
            local info = tiles[index + offset]
            local tileWidth = math.max(40, math.floor(distributable * (info.layoutWeight / weightSum)))
            local tile = info.tile
            tile:SetParent(band.frame)
            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT", band.frame, "TOPLEFT", math.floor(x), -top)
            tile:SetSize(tileWidth, EXPORT_TILE_ROW_HEIGHT)
            tile.label:SetText(info.name)
            tile.previewHost:ClearAllPoints()
            tile.previewHost:SetPoint("CENTER", tile, "CENTER", 0, -(EXPORT_TILE_LABEL_HEIGHT / 2))
            tile.previewHost:SetSize(
                math.max(1, tileWidth - (EXPORT_TILE_INSET * 2)),
                math.max(1, EXPORT_TILE_ROW_HEIGHT - EXPORT_TILE_LABEL_HEIGHT - (EXPORT_TILE_INSET * 2)))
            -- Import mode's tiles are the selection gate: dimmed when the
            -- panel is excluded, clickable when a toggle is supplied. Both
            -- states are reset every layout because the pool is shared with
            -- export mode's inert tiles.
            tile:SetAlpha(info.dimmed and 0.4 or 1)
            if info.onClick then
                tile:EnableMouse(true)
                tile:SetScript("OnMouseUp", function(_, mouseButton)
                    if mouseButton == "LeftButton" then
                        info.onClick()
                    end
                end)
                tile:SetScript("OnEnter", info.onEnter)
                tile:SetScript("OnLeave", info.onLeave)
            else
                tile:EnableMouse(false)
                tile:SetScript("OnMouseUp", nil)
                tile:SetScript("OnEnter", nil)
                tile:SetScript("OnLeave", nil)
            end
            tile:Show()
            -- Import tiles carry the incoming panel's detached data; export
            -- tiles carry a saved panel's id.
            if info.groupData and ST._BuildReadOnlyPanelPreviewFromData then
                ST._BuildReadOnlyPanelPreviewFromData(tile.previewHost, info.groupData)
            elseif ST._BuildReadOnlyPanelPreview then
                ST._BuildReadOnlyPanelPreview(tile.previewHost, info.panelId)
            end
            x = x + tileWidth + EXPORT_TILE_GAP
        end

        top = top + EXPORT_TILE_ROW_HEIGHT + EXPORT_TILE_GAP
        index = index + rowCount
    end
end

local function AddExportPreviewBand(scroll, tileInfos)
    local rowCount = GetExportTileRowCount(#tileInfos)
    local band = AceGUI:Create("SimpleGroup")
    band:SetFullWidth(true)
    band:SetHeight((rowCount * EXPORT_TILE_ROW_HEIGHT)
        + ((rowCount - 1) * EXPORT_TILE_GAP) + 4)
    band.noAutoHeight = true
    band:SetLayout("Fill")
    band._cdcExportTiles = tileInfos
    band._cdcLastLayoutWidth = nil
    -- The pool must never hand the next acquirer our resize hook or state.
    band:SetCallback("OnRelease", function(widget)
        widget.frame:SetScript("OnSizeChanged", nil)
        widget._cdcExportTiles = nil
        widget._cdcLastLayoutWidth = nil
    end)
    band.frame:SetScript("OnSizeChanged", function()
        LayoutExportPreviewBand(band)
    end)
    scroll:AddChild(band)
    LayoutExportPreviewBand(band)
    return band
end

local function AddSummaryHeading(scroll, text)
    local heading = AceGUI:Create("Heading")
    heading:SetText(text)
    heading:SetFullWidth(true)
    scroll:AddChild(heading)
    return heading
end

-- Group titles wear the config's left-aligned heading grammar: class-colored
-- label with the gradient accent rule running out to the right, so each
-- group's tile band reads as its own section. classKeyOverride lets import
-- mode color a foreign class's section in that class's own color.
local function AddSummarySectionHeading(scroll, text, classKeyOverride)
    local heading = AceGUI:Create("Heading")
    heading:SetText(text)
    heading:SetFullWidth(true)
    if ST._ColorHeading then
        ST._ColorHeading(heading)
    end
    scroll:AddChild(heading)
    if not ST._ApplyLeftAlignedHeading then
        return heading
    end
    ST._ApplyLeftAlignedHeading(heading)

    local classKey = classKeyOverride or select(2, UnitClass("player"))
    local color = classKey and C_ClassColor and C_ClassColor.GetClassColor(classKey)
    local r = color and color.r or 1
    local g = color and color.g or 0.82
    local b = color and color.b or 0

    if heading.label then
        heading.label:SetTextColor(r, g, b)
        -- The AceGUI Heading pool is shared addon-wide and the left-aligned
        -- helper's release handler restores anchors but not colour; chain a
        -- restore so the class colour never leaks to the next acquirer.
        local previousOnRelease = heading.events and heading.events["OnRelease"]
        heading:SetCallback("OnRelease", function(widget, event, ...)
            if previousOnRelease then
                previousOnRelease(widget, event, ...)
            end
            if widget.label then
                widget.label:SetTextColor(1, 0.82, 0)
            end
        end)
    end
    local rule = heading.frame and heading.frame._cdcHeadingRule
    if rule then
        rule:SetGradient("HORIZONTAL",
            CreateColor(r, g, b, 0.35),
            CreateColor(r, g, b, 0))
    end
    return heading
end

local function AddSummaryLine(scroll, text, r, g, b)
    local label = AceGUI:Create("Label")
    label:SetText(text)
    label:SetFullWidth(true)
    label:SetFontObject(GameFontHighlight)
    if r then
        label:SetColor(r, g, b)
    end
    scroll:AddChild(label)
    return label
end

local function AddSummarySpacer(scroll, height)
    local spacer = AceGUI:Create("SimpleGroup")
    spacer:SetFullWidth(true)
    spacer:SetHeight(height or 8)
    spacer.noAutoHeight = true
    scroll:AddChild(spacer)
end

-- Quiet every normal workspace surface: a mode's flat surface owns the
-- column. Shared with import mode, which takes over the same column.
local function HideWorkspaceSurfacesForModes(col3)
    if col3.bsTabGroup then col3.bsTabGroup.frame:Hide() end
    if col3.bsPlaceholder then col3.bsPlaceholder:Hide() end
    if col3._multiSelectActionsScroll then col3._multiSelectActionsScroll.frame:Hide() end
    if col3._customAuraTabGroup then col3._customAuraTabGroup.frame:Hide() end
    if col3.groupSettingsHost then col3.groupSettingsHost:Hide() end
    if ST._HideButtonsPanelPreviewSurfaces then ST._HideButtonsPanelPreviewSurfaces(col3) end
    if ST._HideResourcesWideSurfaces then ST._HideResourcesWideSurfaces(col3) end
    if ST._HideWideEditingChrome then ST._HideWideEditingChrome(col3) end
    local activeHost = col3._cdcActiveWideHost
    if activeHost and activeHost.Hide then activeHost:Hide() end
end

local function RenderExportModeSummary(col3)
    if not col3 then return end

    HideWorkspaceSurfacesForModes(col3)

    if not col3._exportSummaryScroll then
        local scroll = AceGUI:Create("ScrollFrame")
        scroll:SetLayout("List")
        scroll.frame:SetParent(col3.content)
        scroll.frame:ClearAllPoints()
        scroll.frame:SetPoint("TOPLEFT", col3.content, "TOPLEFT", 0, 0)
        scroll.frame:SetPoint("BOTTOMRIGHT", col3.content, "BOTTOMRIGHT", 0, 0)
        col3._exportSummaryScroll = scroll
    end
    local scroll = col3._exportSummaryScroll
    -- Tiles first: every pooled tile must be hidden before ReleaseChildren
    -- can return band frames to the shared AceGUI pool.
    HideAllExportPreviewTiles()
    scroll:ReleaseChildren()
    scroll.frame:Show()

    local selection = GetExportSelection()
    local db = CooldownCompanion.db.profile
    local anythingChecked = selection and CountExportSelection() > 0

    if not anythingChecked then
        AddSummaryHeading(scroll, "Export")
        AddSummarySpacer(scroll, 6)
        AddSummaryLine(scroll, "Nothing selected yet.")
        AddSummarySpacer(scroll, 2)
        AddSummaryLine(scroll, "Check groups, panels, Resources, or Custom Bars in the navigator. Everything you check exports as one string.", 0.7, 0.7, 0.7)
        scroll:DoLayout()
        return
    end

    AddSummaryHeading(scroll, "This string will contain")
    AddSummarySpacer(scroll, 6)

    local orderedCids = {}
    for cid in pairs(selection.containers) do
        local container = db.groupContainers and db.groupContainers[cid]
        if container then
            orderedCids[#orderedCids + 1] = {
                cid = cid,
                container = container,
                order = CooldownCompanion:GetOrderForSpec(container, CooldownCompanion._currentSpecId, cid),
            }
        end
    end
    table.sort(orderedCids, function(a, b) return a.order < b.order end)

    if #orderedCids > 0 then
        local tileIndex = 0
        for _, item in ipairs(orderedCids) do
            local total = 0
            local checked = 0
            local tileInfos = {}
            for _, panelInfo in ipairs(CooldownCompanion:GetPanels(item.cid)) do
                total = total + 1
                if selection.panels[panelInfo.groupId] then
                    checked = checked + 1
                    tileIndex = tileIndex + 1
                    local naturalWidth
                    if ST._GetReadOnlyPanelPreviewNaturalSize then
                        naturalWidth = ST._GetReadOnlyPanelPreviewNaturalSize(panelInfo.groupId)
                    end
                    tileInfos[#tileInfos + 1] = {
                        tile = AcquireExportPreviewTile(tileIndex),
                        panelId = panelInfo.groupId,
                        name = panelInfo.group.name or ("Panel " .. tostring(panelInfo.groupId)),
                        -- Same rule as the overview: horizontal allocation
                        -- follows saved-design width, not area.
                        weight = math.max(1, tonumber(naturalWidth) or 220),
                    }
                end
            end
            local name = item.container.name or ("Group " .. tostring(item.cid))
            local countText
            if total == 0 then
                countText = "empty group"
            elseif checked == total then
                countText = checked .. (checked == 1 and " panel" or " panels")
            else
                countText = checked .. " of " .. total .. " panels"
            end
            -- The left-aligned heading helper carries 10px of air above the
            -- title; matching it below centers the title in the gap between
            -- one group's band and the next.
            AddSummarySectionHeading(scroll, name .. "  |cff777777(" .. countText .. ")|r")
            if #tileInfos > 0 then
                AddSummarySpacer(scroll, 10)
                AddExportPreviewBand(scroll, tileInfos)
            end
        end
        AddSummarySpacer(scroll, 8)
        AddSummaryLine(scroll, "Groups add alongside the importer's own groups.", 0.7, 0.7, 0.7)
    end

    -- Same centering rule as the group titles: the heading brings its own
    -- 10px above, so 10px goes below before the section's content.
    local classKey = tostring(GetResourceBarClassKey() or "?")
    if selection.resources then
        AddSummarySectionHeading(scroll, "Resources  |cff777777(" .. classKey .. ")|r")
        AddSummarySpacer(scroll, 10)
        AddSummaryLine(scroll, "Includes all resources, styling, layout order, and Custom Bars. Replaces the importer's " .. classKey .. " Resources settings.", 0.7, 0.7, 0.7)
    else
        local checkedBars = {}
        for _, info in ipairs(GetExportableCustomBars()) do
            if selection.customBars[info.customBarId] then
                checkedBars[#checkedBars + 1] = info.label
            end
        end
        if #checkedBars > 0 then
            AddSummarySectionHeading(scroll, "Custom Bars  |cff777777(" .. #checkedBars .. ", " .. classKey .. ")|r")
            AddSummarySpacer(scroll, 10)
            for _, label in ipairs(checkedBars) do
                AddSummaryLine(scroll, "    " .. label)
            end
            AddSummarySpacer(scroll, 6)
            AddSummaryLine(scroll, "Custom Bars add alongside the importer's own bars.", 0.7, 0.7, 0.7)
        end
    end

    AddSummarySpacer(scroll, 4)
    AddSummaryLine(scroll, "Export is at the bottom of the navigator.", 0.7, 0.7, 0.7)

    scroll:DoLayout()
end

------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
ST._IsExportModeActive = IsExportModeActive
ST._EnterExportMode = EnterExportMode
ST._ExitExportMode = ExitExportMode
ST._ToggleExportMode = ToggleExportMode
ST._ConfirmExportMode = ConfirmExportMode
ST._CountExportSelection = CountExportSelection
ST._IsResourcesExportable = IsResourcesExportable
ST._GetExportableCustomBars = GetExportableCustomBars
ST._RenderExportModeSummary = RenderExportModeSummary
-- Shared summary grammar, so import mode reads as the mirror image of the
-- export summary (one visual system, two directions).
ST._HideWorkspaceSurfacesForModes = HideWorkspaceSurfacesForModes
ST._AddModeSummaryHeading = AddSummaryHeading
ST._AddModeSummarySectionHeading = AddSummarySectionHeading
ST._AddModeSummaryLine = AddSummaryLine
ST._AddModeSummarySpacer = AddSummarySpacer
-- The tile pool is shared with import mode (only one mode renders at a
-- time, and both hide every tile before releasing band frames).
ST._AcquireModePreviewTile = AcquireExportPreviewTile
ST._HideAllModePreviewTiles = HideAllExportPreviewTiles
ST._AddModePreviewBand = AddExportPreviewBand
