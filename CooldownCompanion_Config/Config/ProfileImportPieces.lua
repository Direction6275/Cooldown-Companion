--[[
    CooldownCompanion - Config/ProfileImportPieces
    Non-destructive selected-pieces import helpers for full profile strings.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local BuildGroupExportData = ST._BuildGroupExportData
local BuildContainerExportData = ST._BuildContainerExportData

local EMPTY_TABLE = {}

local function TableOrEmpty(value)
    return type(value) == "table" and value or EMPTY_TABLE
end

local function NormalizeKey(value)
    if value == nil then
        return nil
    end
    return tostring(value)
end

local function NumericId(value)
    return tonumber(value) or value
end

local function DeepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, child in pairs(value) do
        copy[DeepCopy(key)] = DeepCopy(child)
    end
    return copy
end

local function CopyForExport(data)
    return CopyTable and CopyTable(data) or DeepCopy(data)
end

local function CopyGroupForImport(group)
    local data = BuildGroupExportData and BuildGroupExportData(group) or CopyForExport(group)
    data.createdBy = nil
    data.order = nil
    data.isGlobal = nil
    data.parentContainerId = nil
    return data
end

local function CopyContainerForImport(container)
    local data = BuildContainerExportData and BuildContainerExportData(container) or CopyForExport(container)
    data.createdBy = nil
    data.order = nil
    data.specOrders = nil
    -- isGlobal rides so the landing decision keeps a global piece global
    -- (same rule as BuildContainerExportData).
    return data
end

local function GetCurrentCharInfo()
    local db = CooldownCompanion.db
    local charKey = db and db.keys and db.keys.char
    local info = db and db.global and db.global.characterInfo and db.global.characterInfo[charKey]
    return charKey, info
end

local function GetOwnerInfo(profile, ownerKey, sourceCharacterInfo)
    if type(ownerKey) ~= "string" or ownerKey == "" then
        return nil
    end
    local info = type(sourceCharacterInfo) == "table" and sourceCharacterInfo[ownerKey] or nil
    if info then
        return info
    end
    local exported = type(profile) == "table" and profile._characterInfo or nil
    info = type(exported) == "table" and exported[ownerKey] or nil
    if info then
        return info
    end
    local globalInfo = CooldownCompanion.db
        and CooldownCompanion.db.global
        and CooldownCompanion.db.global.characterInfo
    return type(globalInfo) == "table" and globalInfo[ownerKey] or nil
end

local function NormalizeClassKey(classKey)
    if type(classKey) ~= "string" or classKey == "" then return nil end
    return string.upper(classKey)
end

local function ClassesMatch(currentInfo, ownerInfo)
    if type(currentInfo) ~= "table" or type(ownerInfo) ~= "table" then
        return nil
    end
    local currentClassKey = NormalizeClassKey(currentInfo.classFilename or currentInfo.classFile or currentInfo.className)
    local ownerClassKey = NormalizeClassKey(ownerInfo.classFilename or ownerInfo.classFile or ownerInfo.className)
    if currentClassKey and ownerClassKey then
        return currentClassKey == ownerClassKey
    end
    if currentInfo.classID and ownerInfo.classID then
        return currentInfo.classID == ownerInfo.classID
    end
    return nil
end

local function ClassLabel(info)
    if type(info) ~= "table" then
        return "Unknown class"
    end
    return info.classFilename or info.classFile or (info.classID and ("Class " .. tostring(info.classID))) or "Unknown class"
end

local function ResolveOwnerKey(entity, defaultOwnerKey)
    if type(entity) ~= "table" or entity.isGlobal or entity.section == "global" then
        return nil
    end
    if type(entity.createdBy) == "string" and entity.createdBy ~= "" then
        return entity.createdBy
    end
    return defaultOwnerKey
end

local function BuildEligibility(profile, ownerKey, currentCharKey, currentInfo, sourceCharacterInfo)
    if not ownerKey or ownerKey == currentCharKey then
        return true, true, nil
    end

    local ownerInfo = GetOwnerInfo(profile, ownerKey, sourceCharacterInfo)
    local matches = ClassesMatch(currentInfo, ownerInfo)
    if matches == false then
        return false, false, ClassLabel(ownerInfo) .. " content"
    end
    if matches == nil then
        return false, false, "Source class unknown"
    end
    return true, true, nil
end

local function SortByOrderNameId(a, b)
    local orderA = tonumber(a.order) or math.huge
    local orderB = tonumber(b.order) or math.huge
    if orderA ~= orderB then
        return orderA < orderB
    end
    local nameA = tostring(a.name or "")
    local nameB = tostring(b.name or "")
    if nameA ~= nameB then
        return nameA < nameB
    end
    return tostring(a.sourceId) < tostring(b.sourceId)
end

local function BuildPanelInfos(profile, defaultOwnerKey, currentCharKey, currentInfo, sourceCharacterInfo)
    local panelsByContainer = {}
    local panelInfos = {}
    for panelId, panel in pairs(TableOrEmpty(profile.groups)) do
        if type(panel) == "table" then
            local containerKey = NormalizeKey(panel.parentContainerId)
            local ownerExplicit = type(panel.createdBy) == "string" and panel.createdBy ~= ""
            local ownerKey = ResolveOwnerKey(panel, defaultOwnerKey)
            local eligible, selected, reason = BuildEligibility(
                profile,
                ownerKey,
                currentCharKey,
                currentInfo,
                sourceCharacterInfo
            )
            local info = {
                kind = "panel",
                sourceId = panelId,
                sourceKey = NormalizeKey(panelId),
                parentContainerKey = containerKey,
                panel = panel,
                name = panel.name,
                order = panel.order,
                ownerKey = ownerKey,
                ownerExplicit = ownerExplicit,
                eligible = eligible and containerKey ~= nil,
                selected = (eligible and selected and containerKey ~= nil) or false,
                disabledReason = (not containerKey and "Missing parent group") or (not eligible and reason or nil),
                note = eligible and reason or nil,
            }
            panelInfos[#panelInfos + 1] = info
            if containerKey then
                panelsByContainer[containerKey] = panelsByContainer[containerKey] or {}
                panelsByContainer[containerKey][#panelsByContainer[containerKey] + 1] = info
            end
        end
    end
    for _, panels in pairs(panelsByContainer) do
        table.sort(panels, SortByOrderNameId)
    end
    table.sort(panelInfos, SortByOrderNameId)
    return panelInfos, panelsByContainer
end

local function BuildContainerInfos(profile, panelsByContainer, defaultOwnerKey, currentCharKey, currentInfo, sourceCharacterInfo)
    local containerInfos = {}
    local byKey = {}
    for containerId, container in pairs(TableOrEmpty(profile.groupContainers)) do
        if type(container) == "table" then
            local key = NormalizeKey(containerId)
            local ownerKey = ResolveOwnerKey(container, defaultOwnerKey)
            local eligible, selected, reason = BuildEligibility(
                profile,
                ownerKey,
                currentCharKey,
                currentInfo,
                sourceCharacterInfo
            )
            local panels = panelsByContainer[key] or {}
            local info = {
                kind = "container",
                sourceId = containerId,
                sourceKey = key,
                container = container,
                panels = panels,
                name = container.name,
                order = container.order,
                ownerKey = ownerKey,
                eligible = eligible,
                selected = eligible and selected or false,
                disabledReason = not eligible and reason or nil,
                note = eligible and reason or nil,
            }
            containerInfos[#containerInfos + 1] = info
            byKey[key] = info
        end
    end
    table.sort(containerInfos, SortByOrderNameId)
    return containerInfos, byKey
end

local function InheritPanelContainerEligibility(panelInfos, containersByKey)
    for _, panelInfo in ipairs(panelInfos) do
        local containerInfo = containersByKey[panelInfo.parentContainerKey]
        if containerInfo then
            if not panelInfo.ownerExplicit then
                panelInfo.eligible = containerInfo.eligible
                panelInfo.selected = containerInfo.eligible and containerInfo.selected or false
                panelInfo.disabledReason = containerInfo.disabledReason
                panelInfo.note = containerInfo.note
            else
                local panelEligible = panelInfo.eligible == true
                panelInfo.eligible = panelEligible and containerInfo.eligible == true
                panelInfo.selected = panelInfo.eligible and panelInfo.selected and containerInfo.selected or false
                if panelEligible and not containerInfo.eligible then
                    panelInfo.disabledReason = containerInfo.disabledReason
                    panelInfo.note = containerInfo.note
                end
            end
        else
            -- No heading to sit under, and nothing lands at apply either.
            panelInfo.eligible = false
            panelInfo.selected = false
            panelInfo.disabledReason = "Missing parent group"
            panelInfo.note = nil
        end
    end
end

-- Counts each row. Groups, panels and templates render from their data.
local function AddRows(model, infos)
    for _, info in ipairs(infos) do
        model.rows[#model.rows + 1] = info
        if info.eligible then
            model.eligibleCount = model.eligibleCount + 1
            if info.selected then
                model.selectedCount = model.selectedCount + 1
            end
        else
            model.disabledCount = model.disabledCount + 1
        end
    end
end

function CooldownCompanion:BuildProfileImportPiecesReview(profile, options)
    options = options or {}
    local sourceCharacterInfo = options.sourceCharacterInfo
        or (type(profile) == "table" and profile._characterInfo)
    if type(profile) ~= "table" then
        profile = {}
    else
        profile = CopyTable(profile)
        if self.MigrateFoldersIntoGroups then
            -- Present old backups in the supported hierarchy and carry every
            -- inherited restriction onto the Group rows before selection.
            self:MigrateFoldersIntoGroups(profile, sourceCharacterInfo)
        end
    end
    local currentCharKey, currentInfo = GetCurrentCharInfo()
    currentCharKey = options.currentCharKey or currentCharKey
    currentInfo = options.currentCharInfo or currentInfo
    local defaultOwnerKey = options.exporterCharKey
        or (type(profile) == "table" and profile._exporterCharKey)

    local panelInfos, panelsByContainer = BuildPanelInfos(
        profile, defaultOwnerKey, currentCharKey, currentInfo, sourceCharacterInfo
    )
    local containerInfos, containersByKey = BuildContainerInfos(
        profile, panelsByContainer, defaultOwnerKey, currentCharKey, currentInfo, sourceCharacterInfo
    )
    InheritPanelContainerEligibility(panelInfos, containersByKey)
    -- Panel Templates are account-wide, so any class can take them. Backups
    -- only (options.includeTemplates).
    local templateInfos = {}
    local templates = options.includeTemplates and type(profile) == "table"
        and type(profile._panelTemplates) == "table" and profile._panelTemplates or {}
    for index, template in ipairs(templates) do
        if type(template) == "table" then
            templateInfos[#templateInfos + 1] = {
                kind = "template",
                sourceKey = index,
                template = template,
                name = template.name,
                eligible = true,
                selected = true,
            }
        end
    end

    local model = {
        rows = {},
        containers = containerInfos,
        panels = panelInfos,
        templates = templateInfos,
        containersByKey = containersByKey,
        panelsByContainer = panelsByContainer,
        eligibleCount = 0,
        selectedCount = 0,
        disabledCount = 0,
    }

    AddRows(model, containerInfos)
    AddRows(model, panelInfos)
    AddRows(model, templateInfos)
    return model
end

local function RecountSelection(model)
    if type(model) ~= "table" then
        return 0
    end
    local selected = 0
    if type(model.rows) == "table" then
        for _, row in ipairs(model.rows) do
            if row.eligible and row.selected then
                selected = selected + 1
            end
        end
    end
    model.selectedCount = selected
    return selected
end

local function SelectionSets(model)
    local containers, panels = {}, {}
    local deselectedContainers, deselectedPanels = {}, {}
    for _, row in ipairs(model.rows or {}) do
        if row.eligible then
            if row.selected then
                if row.kind == "container" then
                    containers[row.sourceKey] = true
                elseif row.kind == "panel" then
                    panels[row.sourceKey] = true
                end
            elseif row.userChanged then
                if row.kind == "container" then
                    deselectedContainers[row.sourceKey] = true
                elseif row.kind == "panel" then
                    deselectedPanels[row.sourceKey] = true
                end
            end
        end
    end
    return containers, panels, deselectedContainers, deselectedPanels
end

local function EligiblePanels(containerInfo, selectedPanels, deselectedPanels, includeAll)
    local panels = {}
    for _, panelInfo in ipairs(containerInfo.panels) do
        if panelInfo.eligible and (
            selectedPanels[panelInfo.sourceKey]
                or (includeAll and not deselectedPanels[panelInfo.sourceKey])
        ) then
            local panel = CopyGroupForImport(panelInfo.panel)
            panel._originalGroupId = NumericId(panelInfo.sourceId)
            panels[#panels + 1] = panel
        end
    end
    return panels
end

local function BuildContainerEntry(containerInfo, selectedPanels, deselectedPanels, includeAll)
    if not (containerInfo and containerInfo.eligible) then
        return nil
    end
    local panels = EligiblePanels(containerInfo, selectedPanels, deselectedPanels, includeAll)
    return {
        container = CopyContainerForImport(containerInfo.container),
        panels = panels,
        _originalContainerId = NumericId(containerInfo.sourceId),
    }
end

local function AddContainerEntry(entries, containerInfo, selectedPanels, deselectedPanels, includeAll, importedContainers)
    if not (containerInfo and containerInfo.sourceKey and not importedContainers[containerInfo.sourceKey]) then
        return
    end
    local entry = BuildContainerEntry(containerInfo, selectedPanels, deselectedPanels, includeAll)
    if entry then
        importedContainers[containerInfo.sourceKey] = true
        entries[#entries + 1] = entry
    end
end

-- Both sections defer their migration run to the single one this door takes
-- after finishing its batch, the same contract the setup door uses. Without
-- it each section walked the whole profile again on one click.
local DEFER_TO_PIECES_RUN = { deferMigrations = true }

local function ApplyPayload(payload)
    local apply = ST._ApplyGroupImportData
    return apply and apply(payload, DEFER_TO_PIECES_RUN) == true
end

local function AddCheckpoint(payload, profile)
    if type(payload) == "table" and type(profile) == "table" then
        payload._cdcImportCheckpoint = profile._cdcImportCheckpoint
    end
    return payload
end

local function BeginImportBatch()
    local begin = ST._BeginGroupImportBatch
    return begin and begin() or nil
end

local function ApplyProfilePiecePayload(profile, payload, batchToken)
    local attach = ST._AttachGroupImportBatch
    if attach and batchToken then
        attach(payload, batchToken)
    end
    return ApplyPayload(AddCheckpoint(payload, profile))
end

local function FinishImportBatch(batchToken, remapAnchors)
    local finish = ST._FinishGroupImportBatch
    if finish and batchToken then
        finish(batchToken, remapAnchors == true)
    end
end

local function SetChildSelection(row, selected)
    if not (row and row.eligible) then
        return
    end
    row.selected = selected == true
    row.userChanged = nil
end

local function SetProfileImportPieceSelected(model, row, selected)
    if type(row) ~= "table" then
        return
    end
    local enabled = selected == true
    row.selected = enabled
    row.userChanged = true
    if row.kind == "container" then
        for _, panelInfo in ipairs(row.panels or {}) do
            SetChildSelection(panelInfo, enabled)
        end
    elseif row.kind == "panel" and not enabled then
        -- Unticking a Group's last panel unticks the Group too, the rule the
        -- setup tiles follow: a Group never arrives emptied of its panels.
        local containerRow = model.containersByKey and model.containersByKey[row.parentContainerKey]
        if containerRow and containerRow.selected then
            local anySelected = false
            for _, panelInfo in ipairs(containerRow.panels or {}) do
                if panelInfo.eligible and panelInfo.selected then
                    anySelected = true
                    break
                end
            end
            if not anySelected then
                containerRow.selected = false
                containerRow.userChanged = true
            end
        end
    end
    RecountSelection(model)
end

function CooldownCompanion:ApplyProfileImportPieces(profile, model)
    if type(profile) ~= "table" or type(model) ~= "table" then
        return false
    end

    RecountSelection(model)
    if model.selectedCount == 0 then
        self:Print("Import failed: no profile pieces selected.")
        return false
    end

    local selectedContainers, selectedPanels, deselectedContainers, deselectedPanels = SelectionSets(model)
    local selectedTemplates = {}
    for _, info in ipairs(model.templates or {}) do
        if info.eligible and info.selected then
            selectedTemplates[#selectedTemplates + 1] = info.template
        end
    end

    local importedContainers = {}
    local batchToken = BeginImportBatch()
    local applied = false
    local failed = false

    local looseEntries = {}
    for _, containerInfo in ipairs(model.containers or {}) do
        if selectedContainers[containerInfo.sourceKey] then
            AddContainerEntry(looseEntries, containerInfo, selectedPanels, deselectedPanels, true, importedContainers)
        end
    end

    for _, panelInfo in ipairs(model.panels or {}) do
        local containerInfo = model.containersByKey and model.containersByKey[panelInfo.parentContainerKey]
        if selectedPanels[panelInfo.sourceKey] then
            AddContainerEntry(looseEntries, containerInfo, selectedPanels, deselectedPanels, false, importedContainers)
        end
    end

    if #looseEntries > 0 then
        local ok = ApplyProfilePiecePayload(profile, {
            type = "containers",
            containers = looseEntries,
        }, batchToken)
        applied = ok or applied
        failed = failed or not ok
    end

    FinishImportBatch(batchToken, applied)

    -- The single migration run for every section this click inserted, taken
    -- once the batch has remapped anchors and before the refresh below, so
    -- the frames that refresh builds come from migrated entries.
    if applied then
        local runMigrations = ST._RunPostImportMigrations
        if runMigrations and not runMigrations() then
            failed = true
        end
    end

    if applied then
        local attachmentOperation = self:BeginPanelAttachmentRefresh()
        if self.RefreshAllGroups then
            self:RefreshAllGroups()
        end
        self:EndPanelAttachmentRefresh(attachmentOperation)
    end

    -- Account-wide: no profile migration run and no frame refresh.
    if #selectedTemplates > 0 then
        self:ImportPanelTemplates(selectedTemplates)
    end

    if applied and not failed then
        self:Print("Imported selected profile pieces.")
    elseif failed then
        self:Print("Import failed: some selected profile pieces could not be imported.")
        return false
    elseif #selectedTemplates > 0 then
        -- Templates only: ImportPanelTemplates already said what landed.
        return true
    else
        self:Print("Import failed: selected profile pieces could not be imported.")
    end
    return applied
end

ST._BuildProfileImportPiecesReview = function(profile, options)
    return CooldownCompanion:BuildProfileImportPiecesReview(profile, options)
end

ST._RecountProfileImportPiecesSelection = RecountSelection
ST._SetProfileImportPieceSelected = SetProfileImportPieceSelected

ST._ApplyProfileImportPieces = function(profile, model)
    return CooldownCompanion:ApplyProfileImportPieces(profile, model)
end
