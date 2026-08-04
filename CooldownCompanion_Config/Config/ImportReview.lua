--[[
    CooldownCompanion - Config/ImportReview
    Universal import classification and accept flow. Rendering lives in
    Config/ImportMode.lua (the wide-column paste-and-review surface); this
    file owns what a string IS and what applying it does.
]]

local _, ST = ...
local CooldownCompanion = ST.Addon

local PrepareSharedImportText = ST._PrepareSharedImportText
local DecodeSharedPayload = ST._DecodeSharedPayload
local ApplyGroupImportData = ST._ApplyGroupImportData
local ApplyCustomBarsImportData = ST._ApplyCustomBarsImportData
local ApplySetupImportData = ST._ApplySetupImportData
local ApplyFullProfileImport = ST._ApplyFullProfileImport
local BuildProfileImportPiecesReview = ST._BuildProfileImportPiecesReview
local RecountProfileImportPiecesSelection = ST._RecountProfileImportPiecesSelection
local ApplyProfileImportPieces = ST._ApplyProfileImportPieces

-- One ceiling for every string type. Custom Bars once carried their own
-- smaller 100k limit from when they were a separate import path; a setup
-- export could wrap the same bars and bypass it, and nothing recorded what
-- the smaller number protected against, so it was retired rather than
-- duplicated across payload shapes.
local MAX_IMPORT_LENGTH = 500000
local DIAGNOSTIC_PREFIX = "CDCdiag:"

local function CountPairs(tbl)
    local count = 0
    if type(tbl) == "table" then
        for _ in pairs(tbl) do
            count = count + 1
        end
    end
    return count
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

local function BuildDiagnosticSourceCharacterInfo(meta)
    if type(meta) ~= "table" or type(meta.charKey) ~= "string" or meta.charKey == "" then
        return nil
    end

    local classFilename = meta.classFilename or meta.className
    local classID = tonumber(meta.classID)
    if not classFilename and not classID then
        return nil
    end

    return {
        [meta.charKey] = {
            classFilename = classFilename,
            classID = classID,
        },
    }
end

local function GetPayloadDataLabel(data, isDiagnostic)
    if isDiagnostic or (type(data) == "table" and data.reportKind == "bugReport") then
        return "diagnostic string"
    end
    if type(data) == "table" and data.type == "customBars" then
        return "custom bars import"
    end
    if type(data) == "table" and data.type == "setup" then
        return "setup import"
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

local function BuildProfileSummaryLines(profile, heading, customBarCount)
    local lines = {}
    AddLine(lines, heading or "Full profile")
    AddLine(lines, FormatCount("Groups", CountPairs(profile and profile.groupContainers)))
    AddLine(lines, FormatCount("Panels", CountPairs(profile and profile.groups)))

    customBarCount = customBarCount or 0
    if customBarCount > 0 then
        AddLine(lines, FormatCount("Custom Bars", customBarCount))
    end

    local classScoped = {}
    local characterScoped = {}
    local legacyScoped = {}
    if type(profile) == "table" then
        if CountPairs(profile.resourceBarsByClass) > 0 then classScoped[#classScoped + 1] = "Resource/Custom Bars" end
        if type(profile.resourceBarsByChar) == "table" then legacyScoped[#legacyScoped + 1] = "legacy Resource/Custom Bars" end
        if type(profile.castBarByChar) == "table" then characterScoped[#characterScoped + 1] = "Cast Bar" end
        if type(profile.frameAnchoringByChar) == "table" then characterScoped[#characterScoped + 1] = "Frame Anchoring" end
    end
    if #classScoped > 0 then
        AddLine(lines, "Class-scoped settings: " .. table.concat(classScoped, ", "))
    end
    if #characterScoped > 0 then
        AddLine(lines, "Character-scoped settings: " .. table.concat(characterScoped, ", "))
    end
    if #legacyScoped > 0 then
        AddLine(lines, "Unresolved legacy settings: " .. table.concat(legacyScoped, ", "))
    end
    local migration = type(profile) == "table" and profile.resourceBarMigration or nil
    local conflicts = type(migration) == "table" and migration.conflicts or nil
    local unsafe = type(migration) == "table" and migration.unsafeCharKeys or nil
    if CountPairs(conflicts) > 0 then
        AddLine(lines, FormatCount("Pending Resource Bar conflicts", CountPairs(conflicts)))
    end
    if CountPairs(unsafe) > 0 then
        AddLine(lines, FormatCount("Resource Bar buckets missing class metadata", CountPairs(unsafe)))
    end
    return lines
end

local function IsProfileReviewKind(review)
    return review and (review.kind == "profile" or review.kind == "diagnostic")
end

local function ReviewUsesSelectedPieces(review)
    return IsProfileReviewKind(review) and review.mode == "selected"
end

local function AddCharacterEligibilityNotice(lines, data)
    local stripped = type(data) == "table" and tonumber(data._cdcCharacterEligibilityStripped) or 0
    if stripped and stripped > 0 then
        AddLine(lines, "Character eligibility is local and will not be imported.")
    end
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

local function BuildSelectedPiecesSummaryLines(review, selectedCount)
    local pieces = review and review.pieces or nil
    local lines = {}
    AddLine(lines, review.kind == "diagnostic" and "Diagnostic selected pieces" or "Profile selected pieces")
    AddLine(lines, "Only pieces compatible with your current class are shown.")
    AddLine(lines, FormatCount("Importable pieces", pieces and pieces.eligibleCount or 0))
    AddLine(lines, FormatCount("Selected pieces", selectedCount or RecountSelectedPieces(review)))
    if pieces and pieces.disabledCount and pieces.disabledCount > 0 then
        AddLine(lines, FormatCount("Hidden incompatible pieces", pieces.disabledCount))
    end
    if pieces and pieces.customBarCount and pieces.customBarCount > 0 then
        AddLine(lines, FormatCount("Custom Bars", pieces.customBarCount))
    end
    AddCharacterEligibilityNotice(lines, review and (review.diagnostic or review.data))
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
            .. "|cffff6666This replaces your current profile. For sharing, import selected pieces or export groups or panels.|r"
    end
    return "|cffffd100Restore Backup:|r For your own backups.\n"
        .. "|cffff6666This replaces your current profile and may include character data from the exporter. "
        .. "For sharing, import selected pieces or export groups or panels.|r"
end

local function GetReviewAcceptText(review)
    if ReviewUsesSelectedPieces(review) then
        return "Import Selected"
    end
    return review and review.acceptText or "Import"
end

local function CanApplyReview(review, selectedCount)
    if not review then
        return false
    end
    if ReviewUsesSelectedPieces(review) then
        return (selectedCount or RecountSelectedPieces(review)) > 0
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

-- Class identity of any class-tagged payload or setup section. Shared by
-- the standalone Custom Bars payload (which is tagged the same way) and by
-- the setup sections.
local function GetSetupSectionClassKey(section)
    if type(section) ~= "table" then
        return nil
    end
    local normalize = ST._NormalizeResourceBarClassKey
    local classKey = normalize and normalize(section.classFilename) or nil
    if classKey then
        return classKey
    end
    if section.classID and ST._GetResourceBarClassKeyFromClassID then
        return ST._GetResourceBarClassKeyFromClassID(section.classID)
    end
    return nil
end

local function GetPlayerClassKey()
    local normalize = ST._NormalizeResourceBarClassKey
    local classFilename = select(2, UnitClass("player"))
    return normalize and normalize(classFilename) or classFilename
end

-- The class a payload imports INTO: nil means the importing character's own
-- class (the legacy same-class contract), a class key means a cross-class
-- import that lands in that class's bucket.
local function GetForeignImportClassKey(data)
    local classKey = GetSetupSectionClassKey(data)
    local playerClassKey = GetPlayerClassKey()
    if classKey and playerClassKey and classKey ~= playerClassKey then
        return classKey, playerClassKey
    end
    return nil, playerClassKey
end

local function AddForeignClassNotice(lines, foreignClassKey, playerClassKey, what)
    if not foreignClassKey then
        return
    end
    AddLine(lines, "This " .. what .. " is for " .. tostring(foreignClassKey)
        .. ". You are playing a " .. tostring(playerClassKey) .. ".")
    AddLine(lines, "It imports for " .. tostring(foreignClassKey)
        .. " and is waiting the next time you play a " .. tostring(foreignClassKey) .. " character.")
end

local function BuildCustomBarsSummaryLines(data)
    local lines = {
        "Custom Bars export",
        FormatCount("Bars", type(data.bars) == "table" and #data.bars or 0),
        FormatCount("Layout specs", CountPairs(data.layouts)),
    }
    AddLine(lines, data.classFilename and "Class: " .. tostring(data.classFilename))
    local foreignClassKey, playerClassKey = GetForeignImportClassKey(data)
    AddForeignClassNotice(lines, foreignClassKey, playerClassKey, "Custom Bars export")
    AddCharacterEligibilityNotice(lines, data)
    return lines
end

local function GetSetupSections(data)
    local hasContainers = type(data.containers) == "table" and #data.containers > 0
    local customBars = type(data.customBars) == "table"
        and type(data.customBars.bars) == "table"
        and #data.customBars.bars > 0
        and data.customBars
        or nil
    local resources = type(data.resources) == "table"
        and type(data.resources.settings) == "table"
        and data.resources
        or nil
    return hasContainers, customBars, resources
end

local function BuildSetupSummaryLines(data, hasContainers, customBars, resources)
    local lines = {}
    AddLine(lines, "Setup export")

    if hasContainers then
        AddLine(lines, FormatCount("Groups", #data.containers))
        AddLine(lines, FormatCount("Panels", CountContainerPanels(data.containers)))
    end

    local playerClassKey = GetPlayerClassKey()
    local foreignClassKey = nil

    if resources then
        local classKey = GetSetupSectionClassKey(resources)
        AddLine(lines, "Resources setup: " .. tostring(classKey or "Unknown class"))
        if classKey and CooldownCompanion.IsResourceBarClassConfigured
            and CooldownCompanion:IsResourceBarClassConfigured(classKey) then
            AddLine(lines, "This replaces your current " .. tostring(classKey) .. " Resources settings.")
        end
        if classKey and playerClassKey and classKey ~= playerClassKey then
            foreignClassKey = classKey
        end
    end

    if customBars then
        local classKey = GetSetupSectionClassKey(customBars)
        AddLine(lines, FormatCount("Custom Bars", #customBars.bars)
            .. (classKey and (" (" .. tostring(classKey) .. ")") or ""))
        if classKey and playerClassKey and classKey ~= playerClassKey then
            foreignClassKey = foreignClassKey or classKey
        end
    end

    if foreignClassKey then
        AddForeignClassNotice(lines, foreignClassKey, playerClassKey, "setup")
        if hasContainers and resources then
            AddLine(lines, "The Resources anchor does not carry across classes; re-pick it on that character.")
        end
    end

    AddCharacterEligibilityNotice(lines, data)
    return lines
end

local function BuildContainerSummaryLines(data)
    local lines = {
        "Group export",
        "Name: " .. tostring(data.container and data.container.name or "Unnamed"),
        FormatCount("Panels", type(data.panels) == "table" and #data.panels or 0),
    }
    AddCharacterEligibilityNotice(lines, data)
    return lines
end

local function BuildContainersSummaryLines(data)
    local containers = type(data.containers) == "table" and data.containers or {}
    local lines = {
        "Groups export",
        FormatCount("Groups", #containers),
        FormatCount("Panels", CountContainerPanels(containers)),
    }
    AddCharacterEligibilityNotice(lines, data)
    return lines
end

local function BuildLegacyGroupBundleSummaryLines(data)
    local containers = type(data.containers) == "table" and data.containers or {}
    local lines = {
        "Legacy group bundle",
        FormatCount("Groups", #containers),
        FormatCount("Panels", CountContainerPanels(containers)),
    }
    AddCharacterEligibilityNotice(lines, data)
    return lines
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

    local lines = BuildProfileSummaryLines(data, "Profile backup export", pieces and pieces.customBarCount)
    AddCharacterEligibilityNotice(lines, data)

    return BuildReview("profile", data, "Profile Backup", "Restore Backup",
        lines, {
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

    local meta = GetDiagnosticMeta(data)
    local pieces = BuildProfileImportPiecesReview and BuildProfileImportPiecesReview(data.profile, {
        exporterCharKey = meta and meta.charKey,
        sourceCharacterInfo = BuildDiagnosticSourceCharacterInfo(meta),
    }) or nil
    local lines = BuildProfileSummaryLines(data.profile, "Diagnostic profile attachment",
        pieces and pieces.customBarCount)
    if meta and meta.charName then
        table.insert(lines, 2, "Source: " .. tostring(meta.charName))
    end
    AddCharacterEligibilityNotice(lines, data)

    return BuildReview("diagnostic", data.profile, "Diagnostic Restore",
        "Restore Diagnostic", lines, {
        diagnostic = data,
        destructive = true,
        mode = "restore",
        pieces = pieces,
        warning = "This replaces your current profile with the bug report profile.",
    })
end

local function ClassifyEntityPayload(data)
    if data.type == "customBars" then
        if type(data.bars) ~= "table" or #data.bars == 0 then
            return BuildError("empty_custom_bars", "Import failed: no Custom Bars were found.")
        end
        return BuildReview("customBars", data, "Custom Bars Import",
            "Import Custom Bars", BuildCustomBarsSummaryLines(data))
    end

    if data.type == "setup" then
        local hasContainers, customBars, resources = GetSetupSections(data)
        if not hasContainers and not customBars and not resources then
            return BuildError("empty_setup", "Import failed: this setup export is empty.")
        end
        return BuildReview("setup", data, "Setup Import", "Import Setup",
            BuildSetupSummaryLines(data, hasContainers, customBars, resources))
    end

    if data.type == "group" and data.group then
        return BuildLegacyError("group import")
    end
    if data.type == "groups" and data.groups then
        return BuildLegacyError("group import")
    end

    -- A group payload carrying no groups is reported as the empty string it
    -- is, the same way setup and Custom Bars payloads are. Accepting it
    -- would render a review whose Import button can never enable.
    if data.type == "containers" and type(data.containers) == "table" then
        if #data.containers == 0 then
            return BuildError("empty_groups", "Import failed: this export contains no groups.")
        end
        return BuildReview("groups", data, "Groups Import",
            "Import Groups", BuildContainersSummaryLines(data))
    end

    if data.type == "folder" and type(data.folder) == "table" then
        if data.groups then
            return BuildLegacyError("folder import")
        end
        if type(data.containers) ~= "table" or #data.containers == 0 then
            return BuildError("empty_groups", "Import failed: this export contains no groups.")
        end
        return BuildReview("groups", data, "Group Import",
            "Import Groups", BuildLegacyGroupBundleSummaryLines(data))
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
        return ClassifyEntityPayload(data)
    end
    return ClassifyProfilePayload(data)
end

function CooldownCompanion:ApplyReviewedImport(review)
    if type(review) ~= "table" or review.ok ~= true then
        return false
    end

    if review.kind == "profile" or review.kind == "diagnostic" then
        if ReviewUsesSelectedPieces(review) then
            return ApplyProfileImportPieces and ApplyProfileImportPieces(review.data, review.pieces) == true
        end

        local options = {
            dataLabel = "profile import",
            runtimeReason = "profile-import",
            renameForeignCharacters = true,
        }
        local successMessage = "Profile backup restored."
        if review.kind == "diagnostic" then
            local meta = GetDiagnosticMeta(review.diagnostic)
            options.dataLabel = "diagnostic profile"
            options.exporterCharKey = meta and meta.charKey
            options.exportedCharInfo = BuildDiagnosticSourceCharacterInfo(meta)
            options.runtimeReason = "diagnostic-profile-import"
            options.renameForeignCharacters = false
            successMessage = "Diagnostic profile restored."
        end
        local imported = ApplyFullProfileImport and ApplyFullProfileImport(review.data, options)
        if imported then
            self:Print(successMessage)
        end
        return imported == true
    end

    if review.kind == "customBars" then
        if not ApplyCustomBarsImportData then
            return false
        end
        -- Cross-class bars land in the payload class's bucket instead of
        -- being rejected, the same contract a setup export's bars get.
        local foreignClassKey = GetForeignImportClassKey(review.data)
        return ApplyCustomBarsImportData(review.data, foreignClassKey and {
            targetClassKey = foreignClassKey,
        } or nil) == true
    end

    if review.kind == "setup" then
        return ApplySetupImportData and ApplySetupImportData(review.data) == true
    end

    if review.kind == "group" or review.kind == "groups" then
        return ApplyGroupImportData and ApplyGroupImportData(review.data) == true
    end

    self:Print("Import failed: unrecognized export type.")
    return false
end

local function GetDestructiveConfirmText(review)
    if review and review.kind == "diagnostic" then
        return "Restore this diagnostic profile? Your current profile will be overwritten."
    end
    return "Restore this profile backup? Your current profile will be overwritten."
end

-- The one presentation truth: import mode renders these as its sectioned
-- column surface.
local function GetReviewPresentation(review, selectedCount)
    local title = review.title
    local warning = review.warning
    local summaryLines = review.summaryLines
    if ReviewUsesSelectedPieces(review) then
        title = review.kind == "diagnostic" and "Diagnostic Profile Pieces" or "Profile Pieces Import"
        warning = nil
        summaryLines = BuildSelectedPiecesSummaryLines(review, selectedCount)
    end
    return title, warning, summaryLines
end

------------------------------------------------------------------------
-- Review helpers shared with import mode (Config/ImportMode.lua), which
-- owns all rendering of these classifications.
------------------------------------------------------------------------
ST._IsProfileImportReviewKind = IsProfileReviewKind
ST._ImportReviewUsesSelectedPieces = ReviewUsesSelectedPieces
ST._RecountImportReviewSelectedPieces = RecountSelectedPieces
ST._CanApplyImportReview = CanApplyReview
ST._ImportReviewIsDestructive = ReviewIsDestructive
ST._GetImportReviewAcceptText = GetReviewAcceptText
ST._GetImportReviewDisclaimer = GetProfileImportDisclaimer
ST._GetImportReviewConfirmText = GetDestructiveConfirmText
ST._GetImportReviewPresentation = GetReviewPresentation
ST._GetSetupImportSections = GetSetupSections
ST._GetSetupImportSectionClassKey = GetSetupSectionClassKey
