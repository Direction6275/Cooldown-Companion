--[[
    CooldownCompanion - Config/ImportMode
    Import mode lifecycle and the wide-column paste-and-review surface.
    Classification and apply stay in Config/ImportReview.lua; this file
    renders the same reviews in the config's own columns, wearing the
    export summary's visual grammar so the two modes read as one system.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local AceGUI = LibStub("AceGUI-3.0")

local ShowPopupAboveConfig = ST._ShowPopupAboveConfig

local IMPORT_MODE_CONFIRM_POPUP = "CDC_IMPORT_MODE_CONFIRM"
local IMPORT_PASTE_LINES = 7

local IMPORT_MODE_LABELS = {
    selected = "Import selected pieces",
    restore = "Restore backup",
}
local IMPORT_MODE_ORDER = { "selected", "restore" }
local IMPORT_MODE_OPTION_WIDTHS = {
    selected = 190,
    restore = 150,
}

local RenderImportModeReview

------------------------------------------------------------------------
-- Mode lifecycle. CS.importMode is nil when inactive; while active it
-- holds the current review and the one resources decision. Unlike export
-- mode, entry is allowed on unsupported legacy profiles: restoring a
-- backup is the recovery path out of one.
------------------------------------------------------------------------

local function IsImportModeActive()
    return CS.importMode ~= nil
end

local pendingConfirm = nil

local function EnterImportMode()
    if CS.importMode then return end
    if CS.exportMode and ST._ExitExportMode then
        ST._ExitExportMode()
    end
    if CS.talentPickerMode and CooldownCompanion.CloseTalentPicker then
        CooldownCompanion:CloseTalentPicker()
    end
    if CooldownCompanion.IsArrangeModeActive and CooldownCompanion:IsArrangeModeActive()
        and CooldownCompanion.ExitArrangeMode then
        CooldownCompanion:ExitArrangeMode()
    end
    CloseDropDownMenus()

    -- Fresh on every entry: no review, no pasted text, everything kept.
    CS.importMode = {
        review = nil,
        statusText = nil,
        skipResources = false,
        excludedPanels = {},
    }
    if ST._UpdateImportModeTitleButton then
        ST._UpdateImportModeTitleButton()
    end
    CooldownCompanion:RefreshConfigPanel()
end

-- options.skipRefresh: the caller already has a refresh coming (profile
-- teardown), so the mode is torn down without triggering its own.
local function ExitImportMode(options)
    if not CS.importMode then return end
    CS.importMode = nil
    if pendingConfirm then
        pendingConfirm = nil
        StaticPopup_Hide(IMPORT_MODE_CONFIRM_POPUP)
    end
    if ST._HideAllModePreviewTiles then
        ST._HideAllModePreviewTiles()
    end
    local col3 = CS.configFrame and CS.configFrame.col3
    if col3 then
        local paste = col3._importPasteBox
        if paste then
            if paste.ClearFocus then
                paste:ClearFocus()
            elseif paste.editBox then
                paste.editBox:ClearFocus()
            end
            paste.frame:Hide()
        end
        if col3._importReviewScroll then
            -- Release before hiding: a hidden scroll's pooled bands keep
            -- their resize hooks and their tile-pool references.
            col3._importReviewScroll:ReleaseChildren()
            col3._importReviewScroll.frame:Hide()
        end
    end
    if ST._UpdateImportModeTitleButton then
        ST._UpdateImportModeTitleButton()
    end
    if not (options and options.skipRefresh) then
        CooldownCompanion:RefreshConfigPanel()
    end
end

local function ToggleImportMode()
    if CS.importMode then
        ExitImportMode()
    else
        EnterImportMode()
    end
end

------------------------------------------------------------------------
-- Confirm-side queries. The navigator's Import pill reads these.
------------------------------------------------------------------------

local function GetImportModeReview()
    return CS.importMode and CS.importMode.review or nil
end

local function GetReviewSelectedCount(review)
    if ST._ImportReviewUsesSelectedPieces and ST._ImportReviewUsesSelectedPieces(review) then
        return ST._RecountImportReviewSelectedPieces
            and ST._RecountImportReviewSelectedPieces(review)
            or 0
    end
    return nil
end

------------------------------------------------------------------------
-- The panel gate: every incoming panel arrives selected, and clicking
-- its preview tile toggles it out of the import. Exclusions are keyed by
-- the payload's own panel tables, which are stable for the life of the
-- paste; reclassifying resets them. A group whose every panel is
-- excluded is skipped entirely; a genuinely empty group still imports.
------------------------------------------------------------------------

local function IsPanelExcluded(mode, panelData)
    return mode.excludedPanels and mode.excludedPanels[panelData] == true
end

local function FilterContainerEntries(mode, entries)
    local filtered = {}
    for _, entry in ipairs(entries) do
        if type(entry) == "table" then
            local panels = type(entry.panels) == "table" and entry.panels or {}
            local kept = {}
            for _, panelData in ipairs(panels) do
                if not IsPanelExcluded(mode, panelData) then
                    kept[#kept + 1] = panelData
                end
            end
            if #kept > 0 or #panels == 0 then
                local newEntry = {}
                for key, value in pairs(entry) do
                    newEntry[key] = value
                end
                newEntry.panels = kept
                filtered[#filtered + 1] = newEntry
            end
        end
    end
    return filtered
end

-- The data the confirm actually applies: the payload with excluded panels
-- (and a toggled-off resources piece) filtered out. nil means nothing is
-- left to import.
local function GetEffectiveImportData(mode, review)
    local data = review.data

    if review.kind == "group" then
        local panels = type(data.panels) == "table" and data.panels or {}
        local kept = {}
        for _, panelData in ipairs(panels) do
            if not IsPanelExcluded(mode, panelData) then
                kept[#kept + 1] = panelData
            end
        end
        if #kept == 0 and #panels > 0 then
            return nil
        end
        local copy = {}
        for key, value in pairs(data) do
            copy[key] = value
        end
        copy.panels = kept
        return copy
    end

    if review.kind == "groups" then
        local entries = type(data.containers) == "table" and data.containers or {}
        local filtered = FilterContainerEntries(mode, entries)
        if #filtered == 0 then
            return nil
        end
        local copy = {}
        for key, value in pairs(data) do
            copy[key] = value
        end
        copy.containers = filtered
        return copy
    end

    if review.kind == "setup" then
        local copy = {}
        for key, value in pairs(data) do
            copy[key] = value
        end
        if type(copy.containers) == "table" then
            local filtered = FilterContainerEntries(mode, copy.containers)
            if #filtered > 0 then
                copy.containers = filtered
            else
                copy.containers = nil
            end
        end
        if mode.skipResources then
            copy.resources = nil
        end
        local hasContainers = type(copy.containers) == "table" and #copy.containers > 0
        if not hasContainers and type(copy.resources) ~= "table"
            and type(copy.customBars) ~= "table" then
            return nil
        end
        return copy
    end

    return data
end

local function CanConfirmImportMode()
    local mode = CS.importMode
    local review = mode and mode.review
    if not review then
        return false
    end
    local selectedCount = GetReviewSelectedCount(review)
    if ST._CanApplyImportReview and not ST._CanApplyImportReview(review, selectedCount) then
        return false
    end
    -- Excluding every panel (or toggling off a resources-only string's one
    -- piece) can leave nothing behind the gate.
    if review.kind == "setup" or review.kind == "group" or review.kind == "groups" then
        if GetEffectiveImportData(mode, review) == nil then
            return false
        end
    end
    return true
end

local function GetImportModeAcceptText()
    local review = GetImportModeReview()
    if review and ST._GetImportReviewAcceptText then
        return ST._GetImportReviewAcceptText(review)
    end
    return "Import"
end

------------------------------------------------------------------------
-- Apply and confirm.
------------------------------------------------------------------------

local function ApplyImportModeReview(review)
    local mode = CS.importMode
    local applyReview = review
    if review.kind == "setup" or review.kind == "group" or review.kind == "groups" then
        -- Apply what survived the gate, not the raw payload. Written as an
        -- explicit branch: an `and/or` chain here would turn "the gate left
        -- nothing" into the UNFILTERED payload, importing the very panels
        -- the user excluded.
        local data
        if mode then
            data = GetEffectiveImportData(mode, review)
        else
            data = review.data
        end
        if not data then
            return false
        end
        applyReview = { ok = true, kind = review.kind, data = data }
    end
    if CooldownCompanion:ApplyReviewedImport(applyReview) then
        ExitImportMode()
        return true
    end
    return false
end

local function ConfirmImportMode()
    if not CS.importMode then return end
    local review = GetImportModeReview()
    if not review or not CanConfirmImportMode() then
        return
    end
    if ST._ImportReviewIsDestructive and ST._ImportReviewIsDestructive(review) then
        pendingConfirm = review
        local confirmText = ST._GetImportReviewConfirmText
            and ST._GetImportReviewConfirmText(review)
            or "Restore this profile backup? Your current profile will be overwritten."
        if ShowPopupAboveConfig then
            ShowPopupAboveConfig(IMPORT_MODE_CONFIRM_POPUP, confirmText)
        else
            StaticPopup_Show(IMPORT_MODE_CONFIRM_POPUP, confirmText)
        end
        return
    end
    ApplyImportModeReview(review)
end

StaticPopupDialogs[IMPORT_MODE_CONFIRM_POPUP] = {
    text = "%s",
    button1 = "Restore",
    button2 = "Cancel",
    OnAccept = function()
        local review = pendingConfirm
        pendingConfirm = nil
        if review then
            ApplyImportModeReview(review)
        end
    end,
    OnCancel = function()
        pendingConfirm = nil
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

------------------------------------------------------------------------
-- Classification: re-renders only the review area below the paste box,
-- so the box keeps focus and its text across every reclassify.
------------------------------------------------------------------------

local function UpdateImportModePill()
    local mode = CS.importMode
    if mode and mode._updatePill then
        mode._updatePill()
    end
end

local function ReviewImportModeText(text)
    local mode = CS.importMode
    if not mode then return end
    -- A reclassify invalidates any confirm popup still open from the previous
    -- paste: its captured review no longer matches what the screen describes,
    -- and Restore must never apply a backup the user is no longer looking at.
    if pendingConfirm then
        pendingConfirm = nil
        StaticPopup_Hide(IMPORT_MODE_CONFIRM_POPUP)
    end
    mode.review = nil
    mode.statusText = nil
    mode.skipResources = false
    mode.excludedPanels = {}

    local review = CooldownCompanion.ClassifyImportReviewText
        and CooldownCompanion:ClassifyImportReviewText(text or "")
        or nil
    if review and review.ok then
        mode.review = review
    elseif review and review.code ~= "empty" then
        mode.statusText = review.message or "Import failed."
    end

    local col3 = CS.configFrame and CS.configFrame.col3
    local scroll = col3 and col3._importReviewScroll
    if scroll and scroll.SetScroll then
        scroll:SetScroll(0)
    end
    RenderImportModeReview()
    UpdateImportModePill()
end

------------------------------------------------------------------------
-- The review renderers. Setup and group strings get the export summary's
-- mirror: one section per incoming group with a tile band of real panel
-- previews (rendered from the payload's own data), then Resources and
-- Custom Bars sections in the section class's own color. Every other
-- string type renders its classified summary under one section heading.
------------------------------------------------------------------------

local function AddHeading(scroll, text)
    if ST._AddModeSummaryHeading then
        ST._AddModeSummaryHeading(scroll, text)
    end
end

local function AddSectionHeading(scroll, text, classKey)
    if ST._AddModeSummarySectionHeading then
        ST._AddModeSummarySectionHeading(scroll, text, classKey)
    end
end

local function AddLine(scroll, text, r, g, b)
    if ST._AddModeSummaryLine then
        ST._AddModeSummaryLine(scroll, text, r, g, b)
    end
end

local function AddSpacer(scroll, height)
    if ST._AddModeSummarySpacer then
        ST._AddModeSummarySpacer(scroll, height)
    end
end

local function GetPlayerClassKey()
    local classFilename = select(2, UnitClass("player"))
    if ST._NormalizeResourceBarClassKey then
        return ST._NormalizeResourceBarClassKey(classFilename) or classFilename
    end
    return classFilename
end

local function AddCharacterEligibilityLine(scroll, data)
    local stripped = type(data) == "table" and tonumber(data._cdcCharacterEligibilityStripped) or 0
    if stripped and stripped > 0 then
        AddSpacer(scroll, 6)
        AddLine(scroll, "Character eligibility is local and will not be imported.", 0.7, 0.7, 0.7)
    end
end

local function TogglePanelExcluded(mode, panelData)
    if not mode.excludedPanels then
        mode.excludedPanels = {}
    end
    if mode.excludedPanels[panelData] then
        mode.excludedPanels[panelData] = nil
    else
        mode.excludedPanels[panelData] = true
    end
    RenderImportModeReview()
    UpdateImportModePill()
end

-- Incoming groups render exactly like the export summary: a class-colored
-- accent-rule heading per group with a bordered tile band of real panel
-- previews under it, built from the payload's own (rehydrated) panel data.
-- The tiles double as the gate: click toggles a panel out of the import
-- (dimmed, tagged, and counted out of the heading). The heading helper
-- carries 10px above the title; 10px goes below it so titles center
-- between bands, same as the export summary.
local function AddContainerSections(scroll, mode, entries)
    local tileIndex = 0
    local anyExcluded = false
    for _, entry in ipairs(entries) do
        if type(entry) == "table" then
            local panels = type(entry.panels) == "table" and entry.panels or {}
            local name = type(entry.container) == "table" and entry.container.name or nil
            local included = 0
            for _, panelData in ipairs(panels) do
                if not IsPanelExcluded(mode, panelData) then
                    included = included + 1
                end
            end
            local countText
            if #panels == 0 then
                countText = "empty group"
            elseif included == #panels then
                countText = included .. (included == 1 and " panel" or " panels")
            else
                anyExcluded = true
                countText = included .. " of " .. #panels .. " panels"
            end
            AddSectionHeading(scroll, (name or "Group") .. "  |cff777777(" .. countText .. ")|r")

            local tileInfos = {}
            if ST._AcquireModePreviewTile then
                for _, panelData in ipairs(panels) do
                    if type(panelData) == "table" then
                        tileIndex = tileIndex + 1
                        local naturalWidth
                        if ST._GetReadOnlyPanelPreviewNaturalSizeFromData then
                            naturalWidth = ST._GetReadOnlyPanelPreviewNaturalSizeFromData(panelData)
                        end
                        local panelName = panelData.name or "Panel"
                        local excluded = IsPanelExcluded(mode, panelData)
                        tileInfos[#tileInfos + 1] = {
                            tile = ST._AcquireModePreviewTile(tileIndex),
                            groupData = panelData,
                            name = excluded
                                and (panelName .. "  |cff777777(excluded)|r")
                                or panelName,
                            weight = math.max(1, tonumber(naturalWidth) or 220),
                            dimmed = excluded,
                            onClick = function()
                                TogglePanelExcluded(mode, panelData)
                            end,
                            onEnter = function(tileFrame)
                                GameTooltip:SetOwner(tileFrame, "ANCHOR_RIGHT")
                                GameTooltip:AddLine(panelName)
                                if IsPanelExcluded(mode, panelData) then
                                    GameTooltip:AddLine("Excluded. Click to include it in the import.", 1, 1, 1, true)
                                else
                                    GameTooltip:AddLine("Click to exclude it from the import.", 1, 1, 1, true)
                                end
                                GameTooltip:Show()
                            end,
                            onLeave = function()
                                GameTooltip:Hide()
                            end,
                        }
                    end
                end
            end
            if #tileInfos > 0 and ST._AddModePreviewBand then
                AddSpacer(scroll, 10)
                ST._AddModePreviewBand(scroll, tileInfos)
            end
        end
    end
    AddSpacer(scroll, 8)
    AddLine(scroll, "Groups add alongside your own groups.", 0.7, 0.7, 0.7)
    if anyExcluded then
        AddLine(scroll, "Excluded panels stay out of this import. A group with all panels excluded is skipped.", 0.7, 0.7, 0.7)
    end
end

local function RenderSetupReview(scroll, mode, review)
    local data = review.data
    local hasContainers, customBars, resources = ST._GetSetupImportSections(data)

    AddHeading(scroll, "This string contains")
    AddSpacer(scroll, 6)

    if hasContainers then
        AddContainerSections(scroll, mode, data.containers)
    end

    local playerClassKey = GetPlayerClassKey()

    if resources then
        local classKey = ST._GetSetupImportSectionClassKey(resources)
        local keyText = tostring(classKey or "Unknown class")
        AddSectionHeading(scroll, "Resources  |cff777777(" .. keyText .. ")|r", classKey)
        AddSpacer(scroll, 10)
        AddLine(scroll, "Includes all resources, styling, layout order, and Custom Bars.", 0.7, 0.7, 0.7)

        -- The one decision on the surface, shown only when there are
        -- settings to lose. Untouched-module users import silently.
        local configured = classKey
            and CooldownCompanion.IsResourceBarClassConfigured
            and CooldownCompanion:IsResourceBarClassConfigured(classKey)
        if configured then
            AddSpacer(scroll, 6)
            local toggle = AceGUI:Create("CheckBox")
            toggle:SetFullWidth(true)
            toggle:SetLabel("Replace my " .. keyText .. " Resources settings")
            toggle:SetValue(not mode.skipResources)
            toggle:SetCallback("OnValueChanged", function(_, _, value)
                mode.skipResources = value ~= true
                RenderImportModeReview()
                UpdateImportModePill()
            end)
            scroll:AddChild(toggle)
            if mode.skipResources then
                AddLine(scroll, "The Resources setup will be skipped. Everything else still imports.", 0.7, 0.7, 0.7)
            end
        end

        if classKey and playerClassKey and classKey ~= playerClassKey then
            AddSpacer(scroll, 6)
            AddLine(scroll, "This setup is for " .. keyText .. ". You are playing a " .. tostring(playerClassKey) .. ".")
            -- Browse Other Classes shows groups and panels only; Resources
            -- always resolves the current character's class, so the setup is
            -- genuinely there but not visible until you play that class.
            AddLine(scroll, "It imports for " .. keyText .. " and is waiting the next time you play a " .. keyText .. " character.", 0.7, 0.7, 0.7)
            if hasContainers then
                AddLine(scroll, "The anchor to a group in this string does not carry across classes; re-pick it on that character.", 0.7, 0.7, 0.7)
            end
        end
    end

    if customBars then
        local classKey = ST._GetSetupImportSectionClassKey(customBars)
        local keyText = classKey and tostring(classKey) or nil
        local countText = tostring(#customBars.bars) .. (keyText and (", " .. keyText) or "")
        AddSectionHeading(scroll, "Custom Bars  |cff777777(" .. countText .. ")|r", classKey)
        AddSpacer(scroll, 10)
        for index, bar in ipairs(customBars.bars) do
            local label = type(bar) == "table" and bar.label or nil
            if not label and type(bar) == "table" and bar.spellID then
                label = C_Spell.GetSpellName(bar.spellID)
            end
            AddLine(scroll, "    " .. tostring(label or ("Custom Bar " .. index)))
        end
        AddSpacer(scroll, 6)
        AddLine(scroll, "Custom Bars add alongside your own bars.", 0.7, 0.7, 0.7)
        if classKey and playerClassKey and classKey ~= playerClassKey then
            AddLine(scroll, "They import for " .. keyText .. " and are waiting the next time you play a " .. keyText .. " character.", 0.7, 0.7, 0.7)
        end
    end

    AddCharacterEligibilityLine(scroll, data)
end

local function RenderModeRadioRow(scroll, review)
    if not (ST._IsProfileImportReviewKind and ST._IsProfileImportReviewKind(review)
        and review.pieces) then
        return
    end
    local row = AceGUI:Create("SimpleGroup")
    row:SetFullWidth(true)
    row:SetLayout("Flow")
    local currentMode = review.mode == "selected" and "selected" or "restore"
    for _, optionMode in ipairs(IMPORT_MODE_ORDER) do
        local option = AceGUI:Create("CheckBox")
        option:SetType("radio")
        option:SetLabel(IMPORT_MODE_LABELS[optionMode])
        option:SetValue(optionMode == currentMode)
        option:SetWidth(IMPORT_MODE_OPTION_WIDTHS[optionMode] or 160)
        option:SetCallback("OnValueChanged", function(widget, event, value)
            if value ~= true then
                widget:SetValue(true)
                return
            end
            review.mode = optionMode
            RenderImportModeReview()
            UpdateImportModePill()
        end)
        row:AddChild(option)
    end
    scroll:AddChild(row)
    AddSpacer(scroll, 6)
end

local function RenderPieceRows(scroll, review)
    if not (ST._ImportReviewUsesSelectedPieces and ST._ImportReviewUsesSelectedPieces(review)) then
        return
    end
    AddSpacer(scroll, 6)

    local pieces = review.pieces
    local rows = type(pieces) == "table" and type(pieces.rows) == "table" and pieces.rows or nil
    local visibleRows = 0
    for _, row in ipairs(rows or {}) do
        if row.eligible then
            visibleRows = visibleRows + 1
            local cb = AceGUI:Create("CheckBox")
            cb:SetFullWidth(true)
            cb:SetLabel(row.label or "Profile piece")
            cb:SetValue(row.selected == true)
            cb:SetCallback("OnValueChanged", function(widget, event, value)
                if ST._SetProfileImportPieceSelected then
                    ST._SetProfileImportPieceSelected(pieces, row, value == true)
                else
                    row.selected = value == true
                    row.userChanged = true
                end
                RenderImportModeReview()
                UpdateImportModePill()
            end)
            scroll:AddChild(cb)
        end
    end

    if visibleRows == 0 then
        AddLine(scroll, "No pieces compatible with your current class are available.", 0.55, 0.55, 0.55)
    end
end

local function RenderClassifiedReview(scroll, mode, review)
    if review.kind == "setup" then
        RenderSetupReview(scroll, mode, review)
        return
    end

    -- Plain group strings (single, multi, and folder-legacy bundles) carry
    -- the same container/panel shapes a setup section does, so they get the
    -- same visual mirror.
    if review.kind == "group" or review.kind == "groups" then
        local entries
        if review.kind == "group" then
            entries = { { container = review.data.container, panels = review.data.panels } }
        else
            entries = type(review.data.containers) == "table" and review.data.containers or {}
        end
        AddHeading(scroll, "This string contains")
        AddSpacer(scroll, 6)
        AddContainerSections(scroll, mode, entries)
        AddCharacterEligibilityLine(scroll, review.data)
        return
    end

    local selectedCount = GetReviewSelectedCount(review)
    local title, warning, lines = ST._GetImportReviewPresentation(review, selectedCount)

    AddSectionHeading(scroll, title or "Import")
    AddSpacer(scroll, 10)

    RenderModeRadioRow(scroll, review)

    local disclaimer = ST._GetImportReviewDisclaimer and ST._GetImportReviewDisclaimer(review)
    if disclaimer then
        AddLine(scroll, disclaimer)
        AddSpacer(scroll, 6)
    end
    if warning then
        AddLine(scroll, "|cffff6666" .. warning .. "|r")
    end
    -- Every classifier's first summary line restates the string's kind,
    -- which the section heading above already carries.
    for index = 2, #(lines or {}) do
        AddLine(scroll, lines[index])
    end

    RenderPieceRows(scroll, review)
end

-- Once a string classifies, the paste box has done its job: it collapses
-- and the review takes the whole column. Empty and error states keep it.
local function LayoutImportSurface(col3, showPaste)
    local paste = col3._importPasteBox
    local scroll = col3._importReviewScroll
    if not (paste and scroll) then return end
    paste.frame:SetShown(showPaste)
    scroll.frame:ClearAllPoints()
    if showPaste then
        scroll.frame:SetPoint("TOPLEFT", paste.frame, "BOTTOMLEFT", 0, -8)
    else
        scroll.frame:SetPoint("TOPLEFT", col3.content, "TOPLEFT", 0, 0)
    end
    scroll.frame:SetPoint("BOTTOMRIGHT", col3.content, "BOTTOMRIGHT", 0, 0)
end

local function ResetImportModePaste()
    local mode = CS.importMode
    local col3 = CS.configFrame and CS.configFrame.col3
    if not (mode and col3) then return end
    mode.review = nil
    mode.statusText = nil
    mode.skipResources = false
    mode.excludedPanels = {}
    if col3._importPasteBox then
        col3._importPasteBox:SetText("")
    end
    RenderImportModeReview()
    UpdateImportModePill()
    if col3._importPasteBox then
        col3._importPasteBox:SetFocus()
    end
end

RenderImportModeReview = function()
    local mode = CS.importMode
    local col3 = CS.configFrame and CS.configFrame.col3
    local scroll = col3 and col3._importReviewScroll
    if not (mode and scroll) then return end

    LayoutImportSurface(col3, not mode.review)

    -- Tiles first: every pooled tile must be hidden before ReleaseChildren
    -- can return band frames to the shared AceGUI pool.
    if ST._HideAllModePreviewTiles then
        ST._HideAllModePreviewTiles()
    end
    scroll:ReleaseChildren()

    if mode.statusText then
        AddHeading(scroll, "Import")
        AddSpacer(scroll, 6)
        AddLine(scroll, "|cffff6666" .. mode.statusText .. "|r")
    elseif not mode.review then
        AddHeading(scroll, "Import")
        AddSpacer(scroll, 6)
        AddLine(scroll, "Nothing pasted yet.")
        AddSpacer(scroll, 2)
        AddLine(scroll, "Paste any Cooldown Companion export string above. The summary shows what it contains before anything imports.", 0.7, 0.7, 0.7)
    else
        RenderClassifiedReview(scroll, mode, mode.review)
        AddSpacer(scroll, 8)
        AddLine(scroll, "Import is at the bottom of the navigator.", 0.7, 0.7, 0.7)
        AddSpacer(scroll, 6)
        local repaste = AceGUI:Create("Button")
        repaste:SetText("Paste a different string")
        repaste:SetAutoWidth(true)
        repaste:SetCallback("OnClick", ResetImportModePaste)
        scroll:AddChild(repaste)
    end

    scroll:DoLayout()
end

------------------------------------------------------------------------
-- The wide-column surface: paste box pinned on top, review scroll below.
-- Both are created once and live on col3 across mode round trips, like
-- the export summary scroll.
------------------------------------------------------------------------

local function EnsureImportSurface(col3)
    if col3._importPasteBox then return end

    local paste = AceGUI:Create("MultiLineEditBox")
    paste:SetLabel("Paste import string")
    paste:SetNumLines(IMPORT_PASTE_LINES)
    paste:DisableButton(true)
    paste.frame:SetParent(col3.content)
    paste.frame:ClearAllPoints()
    paste.frame:SetPoint("TOPLEFT", col3.content, "TOPLEFT", 0, 0)
    paste.frame:SetPoint("TOPRIGHT", col3.content, "TOPRIGHT", 0, 0)
    paste:SetCallback("OnTextChanged", function(widget)
        ReviewImportModeText(widget:GetText())
    end)
    col3._importPasteBox = paste

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll.frame:SetParent(col3.content)
    scroll.frame:ClearAllPoints()
    scroll.frame:SetPoint("TOPLEFT", paste.frame, "BOTTOMLEFT", 0, -8)
    scroll.frame:SetPoint("BOTTOMRIGHT", col3.content, "BOTTOMRIGHT", 0, 0)
    col3._importReviewScroll = scroll
end

local function RenderImportModeSurface(col3)
    if not col3 then return end
    local mode = CS.importMode
    if not mode then return end

    if ST._HideWorkspaceSurfacesForModes then
        ST._HideWorkspaceSurfacesForModes(col3)
    end
    EnsureImportSurface(col3)
    col3._importReviewScroll.frame:Show()

    if not mode._entered then
        mode._entered = true
        col3._importPasteBox:SetText("")
        RenderImportModeReview()
        col3._importPasteBox:SetFocus()
    else
        -- Paste-box visibility is layout state owned by the review render.
        RenderImportModeReview()
    end
end

------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
ST._IsImportModeActive = IsImportModeActive
ST._EnterImportMode = EnterImportMode
ST._ExitImportMode = ExitImportMode
ST._ToggleImportMode = ToggleImportMode
ST._ConfirmImportMode = ConfirmImportMode
ST._CanConfirmImportMode = CanConfirmImportMode
ST._GetImportModeAcceptText = GetImportModeAcceptText
ST._RenderImportModeSurface = RenderImportModeSurface
