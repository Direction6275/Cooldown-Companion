--[[
    CooldownCompanion - Config/ImportReview
    Universal import paste, preview, classification, and accept flow.
]]

local _, ST = ...
local CooldownCompanion = ST.Addon

local AceGUI = LibStub("AceGUI-3.0")

local PrepareSharedImportText = ST._PrepareSharedImportText
local DecodeSharedPayload = ST._DecodeSharedPayload
local ApplyProfileImportData = ST._ApplyProfileImportData
local ApplyGroupImportData = ST._ApplyGroupImportData
local ApplyCustomBarsImportData = ST._ApplyCustomBarsImportData
local ApplyFullProfileImport = ST._ApplyFullProfileImport
local BuildProfileImportPiecesReview = ST._BuildProfileImportPiecesReview
local RecountProfileImportPiecesSelection = ST._RecountProfileImportPiecesSelection
local ApplyProfileImportPieces = ST._ApplyProfileImportPieces
local CS = ST._configState

local MAX_IMPORT_LENGTH = 500000
local MAX_CUSTOM_BARS_IMPORT_LENGTH = 100000
local DIAGNOSTIC_PREFIX = "CDCdiag:"
local IMPORT_REVIEW_CONFIRM_POPUP = "CDC_IMPORT_REVIEW_CONFIRM"
local IMPORT_TEXT_LINES = 8
local IMPORT_TEXT_HEIGHT = 160
local IMPORT_REVIEW_HEIGHT = 220
local IMPORT_ACTION_HEIGHT = 30
local IMPORT_WINDOW_WIDTH = 640
local IMPORT_WINDOW_HEIGHT = 500
local IMPORT_MODE_LABELS = {
    selected = "Import selected pieces",
    restore = "Restore backup",
}
local IMPORT_MODE_ORDER = { "selected", "restore" }

local importReviewFrame = nil
local activeReview = nil
local pendingReviewImport = nil

local function CountPairs(tbl)
    local count = 0
    if type(tbl) == "table" then
        for _ in pairs(tbl) do
            count = count + 1
        end
    end
    return count
end

local function CountListOrPairs(tbl)
    if type(tbl) ~= "table" then
        return 0
    end
    local count = #tbl
    if count > 0 then
        return count
    end
    return CountPairs(tbl)
end

local function AddLine(lines, text)
    if text and text ~= "" then
        lines[#lines + 1] = text
    end
end

local function FormatCount(label, count)
    return label .. ": " .. tostring(count)
end

local function GetLegacyMessage(dataLabel)
    if CooldownCompanion.GetLegacySupportCutoffMessage then
        return CooldownCompanion:GetLegacySupportCutoffMessage(dataLabel)
    end
    return "This import string is no longer supported."
end

local function BuildError(code, message)
    return { ok = false, code = code or "invalid", message = message or "Import failed: invalid data." }
end

local function BuildLegacyError(dataLabel)
    return BuildError("legacy", GetLegacyMessage(dataLabel or "import string"))
end

local function BuildReview(kind, data, title, acceptText, summaryLines, extra)
    local review = {
        ok = true, kind = kind, data = data, title = title,
        acceptText = acceptText, summaryLines = summaryLines,
    }
    if extra then
        for key, value in pairs(extra) do review[key] = value end
    end
    return review
end

local function ShowPopupOverConfig(which, textArg1, data)
    local showFn = (CS and CS.ShowPopupAboveConfig) or ST._ShowPopupAboveConfig
    if showFn then
        return showFn(which, textArg1, data)
    end
    return StaticPopup_Show(which, textArg1, nil, data)
end

local function IsUnsupportedPayload(data)
    return CooldownCompanion.IsUnsupportedImportPayload
        and CooldownCompanion:IsUnsupportedImportPayload(data)
end

local function GetDiagnosticMeta(diagnostic)
    if type(diagnostic) == "table" and type(diagnostic.meta) == "table" then
        return diagnostic.meta
    end
    return nil
end

local function GetPayloadDataLabel(data, isDiagnostic)
    if isDiagnostic or (type(data) == "table" and data.reportKind == "bugReport") then
        return "diagnostic string"
    end
    if type(data) == "table" and data.type == "customBars" then
        return "custom bars import"
    end
    if type(data) == "table" and data.type then
        return "group import"
    end
    return "profile import"
end

local function CountContainerPanels(containers)
    local panelCount = 0
    if type(containers) == "table" then
        for _, entry in ipairs(containers) do
            if type(entry) == "table" and type(entry.panels) == "table" then
                panelCount = panelCount + #entry.panels
            end
        end
    end
    return panelCount
end

local function CountProfileCustomBars(profile)
    local count = 0
    local stores = type(profile) == "table" and profile.resourceBarsByChar or nil
    if type(stores) ~= "table" then
        return count
    end

    for _, settings in pairs(stores) do
        local customBars = type(settings) == "table"
            and (settings.customBars or settings.customAuraBars)
            or nil
        if type(customBars) == "table" then
            if type(customBars.entries) == "table" then
                count = count + CountListOrPairs(customBars.entries)
            elseif type(customBars.order) == "table" then
                count = count + CountListOrPairs(customBars.order)
            else
                for _, specBars in pairs(customBars) do
                    count = count + CountListOrPairs(specBars)
                end
            end
        end
    end

    return count
end

local function BuildProfileSummaryLines(profile, heading)
    local lines = {}
    AddLine(lines, heading or "Full profile")
    AddLine(lines, FormatCount("Groups", CountPairs(profile and profile.groupContainers)))
    AddLine(lines, FormatCount("Panels", CountPairs(profile and profile.groups)))
    AddLine(lines, FormatCount("Folders", CountPairs(profile and profile.folders)))

    local customBarCount = CountProfileCustomBars(profile)
    if customBarCount > 0 then
        AddLine(lines, FormatCount("Custom Bars", customBarCount))
    end

    local scoped = {}
    if type(profile) == "table" then
        if type(profile.resourceBarsByChar) == "table" then scoped[#scoped + 1] = "Resource/Custom Bars" end
        if type(profile.castBarByChar) == "table" then scoped[#scoped + 1] = "Cast Bar" end
        if type(profile.frameAnchoringByChar) == "table" then scoped[#scoped + 1] = "Frame Anchoring" end
    end
    if #scoped > 0 then
        AddLine(lines, "Character-scoped settings: " .. table.concat(scoped, ", "))
    end
    return lines
end

local function IsProfileReviewKind(review)
    return review and (review.kind == "profile" or review.kind == "diagnostic")
end

local function ReviewUsesSelectedPieces(review)
    return IsProfileReviewKind(review) and review.mode == "selected"
end

local function RecountSelectedPieces(review)
    if not (review and review.pieces) then
        return 0
    end
    if RecountProfileImportPiecesSelection then
        return RecountProfileImportPiecesSelection(review.pieces)
    end
    local selected = 0
    for _, row in ipairs(review.pieces.rows or {}) do
        if row.eligible and row.selected then
            selected = selected + 1
        end
    end
    review.pieces.selectedCount = selected
    return selected
end

local function BuildSelectedPiecesSummaryLines(review)
    local pieces = review and review.pieces or nil
    local lines = {}
    AddLine(lines, review.kind == "diagnostic" and "Diagnostic selected pieces" or "Profile selected pieces")
    AddLine(lines, "Only pieces compatible with your current class are shown.")
    AddLine(lines, FormatCount("Importable pieces", pieces and pieces.eligibleCount or 0))
    AddLine(lines, FormatCount("Selected pieces", RecountSelectedPieces(review)))
    if pieces and pieces.disabledCount and pieces.disabledCount > 0 then
        AddLine(lines, FormatCount("Hidden incompatible pieces", pieces.disabledCount))
    end
    if pieces and pieces.customBarCount and pieces.customBarCount > 0 then
        AddLine(lines, "Custom Bars: " .. tostring(pieces.customBarCount) .. " (not selectable yet)")
    end
    return lines
end

local function GetProfileImportDisclaimer(review)
    if not IsProfileReviewKind(review) then
        return nil
    end
    if ReviewUsesSelectedPieces(review) then
        return "|cffffd100Selected Pieces:|r Best for sharing setups. "
            .. "Only pieces compatible with your current class are shown."
    end
    if review.kind == "diagnostic" then
        return "|cffffd100Diagnostic Restore:|r For bug-report reproduction.\n"
            .. "|cffff6666This replaces your current profile. For sharing, import selected pieces or export groups, folders, or panels.|r"
    end
    return "|cffffd100Restore Backup:|r For your own backups.\n"
        .. "|cffff6666This replaces your current profile and may include character data from the exporter. "
        .. "For sharing, import selected pieces or export groups, folders, or panels.|r"
end

local function GetReviewAcceptText(review)
    if ReviewUsesSelectedPieces(review) then
        return "Import Selected"
    end
    return review and review.acceptText or "Import"
end

local function CanApplyReview(review)
    if not review then
        return false
    end
    if ReviewUsesSelectedPieces(review) then
        return RecountSelectedPieces(review) > 0
    end
    return true
end

local function ReviewIsDestructive(review)
    return review and review.destructive and not ReviewUsesSelectedPieces(review)
end

local function DefaultProfileImportMode(pieces)
    if type(pieces) == "table" and (tonumber(pieces.eligibleCount) or 0) > 0 then
        return "selected"
    end
    return "restore"
end

local function BuildCustomBarsSummaryLines(data)
    local lines = {
        "Custom Bars export",
        FormatCount("Bars", type(data.bars) == "table" and #data.bars or 0),
        FormatCount("Layout specs", CountPairs(data.layouts)),
    }
    AddLine(lines, data.classFilename and "Class: " .. tostring(data.classFilename))
    return lines
end

local function BuildContainerSummaryLines(data)
    return {
        "Group export",
        "Name: " .. tostring(data.container and data.container.name or "Unnamed"),
        FormatCount("Panels", type(data.panels) == "table" and #data.panels or 0),
    }
end

local function BuildContainersSummaryLines(data)
    local containers = type(data.containers) == "table" and data.containers or {}
    return {
        "Groups export",
        FormatCount("Groups", #containers),
        FormatCount("Panels", CountContainerPanels(containers)),
    }
end

local function BuildFolderSummaryLines(data)
    local containers = type(data.containers) == "table" and data.containers or {}
    return {
        "Folder export",
        "Name: " .. tostring(data.folder and data.folder.name or "Unnamed"),
        FormatCount("Groups", #containers),
        FormatCount("Panels", CountContainerPanels(containers)),
    }
end

local function ValidateProfilePayload(data)
    if not data.groups and not data.globalStyle then
        return BuildError("not_profile", "Import failed: data does not appear to be a Cooldown Companion profile.")
    end
    if (data.groups and type(data.groups) ~= "table")
        or (data.globalStyle and type(data.globalStyle) ~= "table")
    then
        return BuildError("malformed_profile", "Import failed: profile data is malformed.")
    end
end

local function ClassifyProfilePayload(data)
    local validation = ValidateProfilePayload(data)
    if validation then
        return validation
    end

    local pieces = BuildProfileImportPiecesReview and BuildProfileImportPiecesReview(data, {
        exporterCharKey = data._exporterCharKey,
    }) or nil

    return BuildReview("profile", data, "Profile Backup", "Restore Backup",
        BuildProfileSummaryLines(data, "Profile backup export"), {
        destructive = true,
        mode = DefaultProfileImportMode(pieces),
        pieces = pieces,
        warning = "This replaces your current profile.",
    })
end

local function ClassifyDiagnosticPayload(data)
    if type(data.profile) ~= "table" then
        return BuildError("diagnostic_without_profile",
            "This diagnostic string does not include an importable profile.")
    end
    if IsUnsupportedPayload(data.profile) then
        return BuildLegacyError("diagnostic profile")
    end
    local validation = ValidateProfilePayload(data.profile)
    if validation then
        return validation
    end

    local lines = BuildProfileSummaryLines(data.profile, "Diagnostic profile attachment")
    local meta = GetDiagnosticMeta(data)
    if meta and meta.charName then
        table.insert(lines, 2, "Source: " .. tostring(meta.charName))
    end

    local pieces = BuildProfileImportPiecesReview and BuildProfileImportPiecesReview(data.profile, {
        exporterCharKey = meta and meta.charKey,
    }) or nil

    return BuildReview("diagnostic", data.profile, "Diagnostic Restore",
        "Restore Diagnostic", lines, {
        diagnostic = data,
        destructive = true,
        mode = "restore",
        pieces = pieces,
        warning = "This replaces your current profile with the bug report profile.",
    })
end

local function ClassifyEntityPayload(data, compactLength)
    if data.type == "customBars" then
        if compactLength > MAX_CUSTOM_BARS_IMPORT_LENGTH then
            return BuildError("too_large", "Import string too large (" .. compactLength .. " characters).")
        end
        if type(data.bars) ~= "table" or #data.bars == 0 then
            return BuildError("empty_custom_bars", "Import failed: no Custom Bars were found.")
        end
        return BuildReview("customBars", data, "Custom Bars Import",
            "Import Custom Bars", BuildCustomBarsSummaryLines(data))
    end

    if data.type == "group" and data.group then
        return BuildLegacyError("group import")
    end
    if data.type == "groups" and data.groups then
        return BuildLegacyError("group import")
    end

    if data.type == "containers" and type(data.containers) == "table" then
        return BuildReview("groups", data, "Groups Import",
            "Import Groups", BuildContainersSummaryLines(data))
    end

    if data.type == "folder" and type(data.folder) == "table" then
        if data.groups then
            return BuildLegacyError("folder import")
        end
        return BuildReview("folder", data, "Folder Import",
            "Import Folder", BuildFolderSummaryLines(data))
    end

    if data.type == "container" and type(data.container) == "table" and type(data.panels) == "table" then
        return BuildReview("group", data, "Group Import",
            "Import Group", BuildContainerSummaryLines(data))
    end

    return BuildError("unknown_type", "Import failed: unrecognized export type.")
end

function CooldownCompanion:ClassifyImportReviewText(text)
    if not PrepareSharedImportText or not DecodeSharedPayload then
        return BuildError("unavailable", "Import failed: import helpers are unavailable.")
    end

    local preparedText, compactText, isLegacyImport = PrepareSharedImportText(text)
    if not preparedText then
        return BuildError("empty", "Paste a Cooldown Companion import string.")
    end

    local isDiagnostic = false
    if compactText:sub(1, #DIAGNOSTIC_PREFIX) == DIAGNOSTIC_PREFIX then
        isDiagnostic = true
        preparedText = compactText:sub(#DIAGNOSTIC_PREFIX + 1)
        compactText = preparedText
    end

    if isLegacyImport or compactText:sub(1, 2) == "^1" then
        return BuildLegacyError(isDiagnostic and "diagnostic string" or "import string")
    end
    if #compactText > MAX_IMPORT_LENGTH then
        return BuildError("too_large", "Import string too large (" .. #compactText .. " characters).")
    end

    local success, data = DecodeSharedPayload(preparedText)
    if not success or type(data) ~= "table" then
        return BuildError("invalid", "Import failed: invalid data.")
    end
    if IsUnsupportedPayload(data) then
        return BuildLegacyError(GetPayloadDataLabel(data, isDiagnostic))
    end

    if isDiagnostic or data.reportKind == "bugReport" then
        return ClassifyDiagnosticPayload(data)
    end
    if data.type then
        return ClassifyEntityPayload(data, #compactText)
    end
    return ClassifyProfilePayload(data)
end

function CooldownCompanion:ApplyReviewedImport(review)
    if type(review) ~= "table" or review.ok ~= true then
        return false
    end

    if review.kind == "profile" then
        if ReviewUsesSelectedPieces(review) then
            local imported = ApplyProfileImportPieces and ApplyProfileImportPieces(review.data, review.pieces)
            if imported then
                self:Print("Profile pieces imported.")
            end
            return imported == true
        end

        local imported = ApplyProfileImportData and ApplyProfileImportData(review.data)
        if imported then
            self:Print("Profile backup restored.")
        end
        return imported == true
    end

    if review.kind == "diagnostic" then
        if ReviewUsesSelectedPieces(review) then
            local imported = ApplyProfileImportPieces and ApplyProfileImportPieces(review.data, review.pieces)
            if imported then
                self:Print("Diagnostic profile pieces imported.")
            end
            return imported == true
        end

        local diagnostic = review.diagnostic
        local meta = GetDiagnosticMeta(diagnostic)
        local imported = ApplyFullProfileImport and ApplyFullProfileImport(review.data, {
            dataLabel = "diagnostic profile",
            exporterCharKey = meta and meta.charKey,
            runtimeReason = "diagnostic-profile-import",
            renameForeignCharacters = false,
        })
        if imported then
            self:Print("Diagnostic profile restored.")
        end
        return imported == true
    end

    if review.kind == "customBars" then
        return ApplyCustomBarsImportData and ApplyCustomBarsImportData(review.data) == true
    end

    if review.kind == "group" or review.kind == "groups" or review.kind == "folder" then
        return ApplyGroupImportData and ApplyGroupImportData(review.data) == true
    end

    self:Print("Import failed: unrecognized export type.")
    return false
end

local function ConfigureWrappedLabel(label)
    if ST._ConfigureWrappedHelperLabel then
        ST._ConfigureWrappedHelperLabel(label)
    end
    label:SetFullWidth(true)
end

local function AddButton(group, text, width)
    local button = AceGUI:Create("Button")
    button:SetText(text)
    button:SetWidth(width)
    group:AddChild(button)
    return button
end

local function RelayoutImportWindow(frame, reviewScroll, ...)
    for i = 1, select("#", ...) do
        local group = select(i, ...)
        if group and group.DoLayout then
            group:DoLayout()
        end
    end
    if reviewScroll and reviewScroll.DoLayout then
        reviewScroll:DoLayout()
    end
    if frame and frame.DoLayout then
        frame:DoLayout()
    end
end

local function CloseImportReviewFrame(widget)
    activeReview = nil
    if pendingReviewImport and pendingReviewImport.frame == widget then
        pendingReviewImport = nil
        if StaticPopup_Hide then
            StaticPopup_Hide(IMPORT_REVIEW_CONFIRM_POPUP)
        end
    end
    if importReviewFrame == widget then
        importReviewFrame = nil
    end
    if widget then
        AceGUI:Release(widget)
    end
end

local function ApplyReviewAndClose(review, frame)
    if CooldownCompanion:ApplyReviewedImport(review) then
        CloseImportReviewFrame(frame)
        return true
    end
    return false
end

local function GetDestructiveConfirmText(review)
    if review and review.kind == "diagnostic" then
        return "Restore this diagnostic profile? Your current profile will be overwritten."
    end
    return "Restore this profile backup? Your current profile will be overwritten."
end

local function ConfirmOrApplyReview(review, frame)
    if ReviewIsDestructive(review) then
        pendingReviewImport = {
            review = review,
            frame = frame,
        }
        ShowPopupOverConfig(IMPORT_REVIEW_CONFIRM_POPUP, GetDestructiveConfirmText(review))
        return
    end

    ApplyReviewAndClose(review, frame)
end

StaticPopupDialogs[IMPORT_REVIEW_CONFIRM_POPUP] = {
    text = "%s",
    button1 = "Restore",
    button2 = "Cancel",
    OnAccept = function()
        local pending = pendingReviewImport
        pendingReviewImport = nil
        if pending then
            ApplyReviewAndClose(pending.review, pending.frame)
        end
    end,
    OnCancel = function()
        pendingReviewImport = nil
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function FormatReviewText(review)
    local lines = {}
    local title = review.title
    local warning = review.warning
    local summaryLines = review.summaryLines
    if ReviewUsesSelectedPieces(review) then
        title = review.kind == "diagnostic" and "Diagnostic Profile Pieces" or "Profile Pieces Import"
        warning = nil
        summaryLines = BuildSelectedPiecesSummaryLines(review)
    end

    AddLine(lines, title and "|cffffd100" .. title .. "|r")
    AddLine(lines, warning and "|cffff6666" .. warning .. "|r")
    for _, line in ipairs(summaryLines or {}) do
        AddLine(lines, line)
    end
    return table.concat(lines, "\n")
end

local function ReleaseChildren(group)
    if not group then
        return
    end
    if group.ReleaseChildren then
        group:ReleaseChildren()
    else
        group.children = {}
    end
end

local function RenderModeControl(group, review, refresh)
    ReleaseChildren(group)
    if not (IsProfileReviewKind(review) and review.pieces) then
        return
    end

    local modeDrop = AceGUI:Create("Dropdown")
    modeDrop:SetLabel("Import mode:")
    modeDrop:SetList(IMPORT_MODE_LABELS, IMPORT_MODE_ORDER)
    modeDrop:SetValue(review.mode or "restore")
    modeDrop:SetWidth(260)
    modeDrop:SetCallback("OnValueChanged", function(widget, event, value)
        review.mode = value == "selected" and "selected" or "restore"
        refresh()
    end)
    group:AddChild(modeDrop)
end

local function RenderPieceRows(group, review, refresh)
    ReleaseChildren(group)
    if not ReviewUsesSelectedPieces(review) then
        return
    end

    local pieces = review.pieces
    local rows = type(pieces) == "table" and type(pieces.rows) == "table" and pieces.rows or nil
    if not rows then
        local emptyLabel = AceGUI:Create("Label")
        ConfigureWrappedLabel(emptyLabel)
        emptyLabel:SetText("|cff888888No profile pieces are available for selected import.|r")
        group:AddChild(emptyLabel)
        return
    end

    local visibleRows = 0
    for _, row in ipairs(rows) do
        if row.eligible then
            visibleRows = visibleRows + 1
            local cb = AceGUI:Create("CheckBox")
            cb:SetFullWidth(true)
            cb:SetLabel(row.label or "Profile piece")
            cb:SetValue(row.selected == true)
            cb:SetCallback("OnValueChanged", function(widget, event, value)
                row.selected = value == true
                refresh()
            end)
            group:AddChild(cb)
        end
    end

    if visibleRows == 0 then
        local emptyLabel = AceGUI:Create("Label")
        ConfigureWrappedLabel(emptyLabel)
        emptyLabel:SetText("|cff888888No pieces compatible with your current class are available.|r")
        group:AddChild(emptyLabel)
    end

    if pieces.customBarCount and pieces.customBarCount > 0 then
        local customBarsLabel = AceGUI:Create("Label")
        ConfigureWrappedLabel(customBarsLabel)
        customBarsLabel:SetText(
            "|cff888888Custom Bars found in this profile are not selectable "
            .. "until the next import/export PR.|r"
        )
        group:AddChild(customBarsLabel)
    end
end

local function ShowImportReviewWindow(context)
    if importReviewFrame then
        importReviewFrame:Show()
        return
    end

    local frame = AceGUI:Create("Window")
    frame:SetTitle("Import")
    frame:SetWidth(IMPORT_WINDOW_WIDTH)
    frame:SetHeight(IMPORT_WINDOW_HEIGHT)
    frame:SetLayout("List")
    importReviewFrame = frame
    activeReview = nil

    local pasteGroup = AceGUI:Create("SimpleGroup")
    pasteGroup:SetFullWidth(true)
    pasteGroup:SetHeight(IMPORT_TEXT_HEIGHT)
    pasteGroup.noAutoHeight = true
    pasteGroup:SetLayout("Fill")
    frame:AddChild(pasteGroup)

    local inputBox = AceGUI:Create("MultiLineEditBox")
    inputBox:SetLabel("Paste import string:")
    inputBox:SetNumLines(IMPORT_TEXT_LINES)
    inputBox:DisableButton(true)
    pasteGroup:AddChild(inputBox)

    local reviewScroll = AceGUI:Create("ScrollFrame")
    reviewScroll:SetFullWidth(true)
    reviewScroll:SetHeight(IMPORT_REVIEW_HEIGHT)
    reviewScroll:SetLayout("List")
    frame:AddChild(reviewScroll)

    local modeGroup = AceGUI:Create("SimpleGroup")
    modeGroup:SetFullWidth(true)
    modeGroup:SetLayout("Flow")
    reviewScroll:AddChild(modeGroup)

    local disclaimerLabel = AceGUI:Create("Label")
    ConfigureWrappedLabel(disclaimerLabel)
    if disclaimerLabel.SetFontObject and GameFontNormal then
        disclaimerLabel:SetFontObject(GameFontNormal)
    end
    disclaimerLabel:SetText("")
    reviewScroll:AddChild(disclaimerLabel)

    local statusLabel = AceGUI:Create("Label")
    ConfigureWrappedLabel(statusLabel)
    statusLabel:SetText("|cff888888No import string reviewed.|r")
    reviewScroll:AddChild(statusLabel)

    local pieceGroup = AceGUI:Create("SimpleGroup")
    pieceGroup:SetFullWidth(true)
    pieceGroup:SetLayout("List")
    reviewScroll:AddChild(pieceGroup)

    local buttonGroup = AceGUI:Create("SimpleGroup")
    buttonGroup:SetFullWidth(true)
    buttonGroup:SetHeight(IMPORT_ACTION_HEIGHT)
    buttonGroup.noAutoHeight = true
    buttonGroup:SetLayout("Flow")

    local acceptButton = AddButton(buttonGroup, "Import", 220)
    acceptButton:SetDisabled(true)
    local cancelButton = AddButton(buttonGroup, "Cancel", 120)

    frame:AddChild(buttonGroup)

    local function RefreshPresentation()
        RenderModeControl(modeGroup, activeReview, RefreshPresentation)
        RenderPieceRows(pieceGroup, activeReview, RefreshPresentation)
        acceptButton:SetText(GetReviewAcceptText(activeReview))
        acceptButton:SetDisabled(not CanApplyReview(activeReview))
        disclaimerLabel:SetText(GetProfileImportDisclaimer(activeReview) or "")
        if activeReview then
            statusLabel:SetText(FormatReviewText(activeReview))
        end
        RelayoutImportWindow(frame, reviewScroll, modeGroup, pieceGroup)
    end

    local function ClearReview()
        activeReview = nil
        acceptButton:SetDisabled(true)
        acceptButton:SetText("Import")
        disclaimerLabel:SetText("")
        ReleaseChildren(modeGroup)
        ReleaseChildren(pieceGroup)
        RelayoutImportWindow(frame, reviewScroll, modeGroup, pieceGroup)
    end

    local function ReviewInput()
        local review = CooldownCompanion:ClassifyImportReviewText(inputBox:GetText())
        if not review.ok then
            ClearReview()
            statusLabel:SetText("|cffff6666" .. (review.message or "Import failed.") .. "|r")
            RelayoutImportWindow(frame, reviewScroll, modeGroup, pieceGroup)
            return
        end

        activeReview = review
        if reviewScroll.SetScroll then
            reviewScroll:SetScroll(0)
        end
        RefreshPresentation()
    end

    inputBox:SetCallback("OnTextChanged", ReviewInput)
    acceptButton:SetCallback("OnClick", function()
        if not activeReview then
            ReviewInput()
        end
        if not activeReview then
            return
        end
        ConfirmOrApplyReview(activeReview, frame)
    end)
    cancelButton:SetCallback("OnClick", function()
        CloseImportReviewFrame(frame)
    end)

    frame:SetCallback("OnClose", function(widget)
        CloseImportReviewFrame(widget)
    end)

    if type(context) == "table" and type(context.initialText) == "string" then
        inputBox:SetText(context.initialText)
        ReviewInput()
    end

    inputBox:SetFocus()
end

function CooldownCompanion:OpenImportReviewWindow(context)
    ShowImportReviewWindow(context)
end

ST._ClassifyImportReviewText = function(text) return CooldownCompanion:ClassifyImportReviewText(text) end
ST._ApplyReviewedImport = function(review) return CooldownCompanion:ApplyReviewedImport(review) end
ST._OpenImportReviewWindow = function(context) return CooldownCompanion:OpenImportReviewWindow(context) end
