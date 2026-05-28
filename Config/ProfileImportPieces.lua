--[[
    CooldownCompanion - Config/ProfileImportPieces
    Non-destructive selected-pieces import helpers for full profile strings.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local BuildGroupExportData = ST._BuildGroupExportData
local BuildContainerExportData = ST._BuildContainerExportData

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
    data.folderId = nil
    data.isGlobal = nil
    data.parentContainerId = nil
    return data
end

local function CopyContainerForImport(container)
    local data = BuildContainerExportData and BuildContainerExportData(container) or CopyForExport(container)
    data.createdBy = nil
    data.order = nil
    data.specOrders = nil
    data.folderId = nil
    data.isGlobal = nil
    return data
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

local function GetCurrentCharInfo()
    local db = CooldownCompanion.db
    local charKey = db and db.keys and db.keys.char
    local info = db and db.global and db.global.characterInfo and db.global.characterInfo[charKey]
    return charKey, info
end

local function GetOwnerInfo(profile, ownerKey)
    if type(ownerKey) ~= "string" or ownerKey == "" then
        return nil
    end
    local exported = type(profile) == "table" and profile._characterInfo or nil
    local info = type(exported) == "table" and exported[ownerKey] or nil
    if info then
        return info
    end
    local globalInfo = CooldownCompanion.db
        and CooldownCompanion.db.global
        and CooldownCompanion.db.global.characterInfo
    return type(globalInfo) == "table" and globalInfo[ownerKey] or nil
end

local function ClassesMatch(currentInfo, ownerInfo)
    if type(currentInfo) ~= "table" or type(ownerInfo) ~= "table" then
        return nil
    end
    if currentInfo.classFilename and ownerInfo.classFilename then
        return currentInfo.classFilename == ownerInfo.classFilename
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
    return info.classFilename or (info.classID and ("Class " .. tostring(info.classID))) or "Unknown class"
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

local function BuildEligibility(profile, ownerKey, currentCharKey, currentInfo)
    if not ownerKey or ownerKey == currentCharKey then
        return true, true, nil
    end

    local ownerInfo = GetOwnerInfo(profile, ownerKey)
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

local function RowLabel(prefix, name, detail, reason)
    local text = prefix .. ": " .. tostring(name or "Unnamed")
    if detail and detail ~= "" then
        text = text .. " (" .. detail .. ")"
    end
    if reason and reason ~= "" then
        text = text .. " - " .. reason
    end
    return text
end

local function BuildPanelInfos(profile, defaultOwnerKey, currentCharKey, currentInfo)
    local panelsByContainer = {}
    local panelInfos = {}
    for panelId, panel in pairs(profile.groups or {}) do
        if type(panel) == "table" then
            local containerKey = NormalizeKey(panel.parentContainerId)
            local ownerKey = ResolveOwnerKey(panel, defaultOwnerKey)
            local eligible, selected, reason = BuildEligibility(profile, ownerKey, currentCharKey, currentInfo)
            local info = {
                kind = "panel",
                sourceId = panelId,
                sourceKey = NormalizeKey(panelId),
                parentContainerKey = containerKey,
                panel = panel,
                name = panel.name,
                order = panel.order,
                ownerKey = ownerKey,
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

local function BuildContainerInfos(profile, panelsByContainer, defaultOwnerKey, currentCharKey, currentInfo)
    local containerInfos = {}
    local byKey = {}
    local byFolder = {}
    for containerId, container in pairs(profile.groupContainers or {}) do
        if type(container) == "table" then
            local key = NormalizeKey(containerId)
            local ownerKey = ResolveOwnerKey(container, defaultOwnerKey)
            local eligible, selected, reason = BuildEligibility(profile, ownerKey, currentCharKey, currentInfo)
            local panels = panelsByContainer[key] or {}
            local panelCount = #panels
            local detail = tostring(panelCount) .. " panel" .. (panelCount == 1 and "" or "s")
            local info = {
                kind = "container",
                sourceId = containerId,
                sourceKey = key,
                folderKey = NormalizeKey(container.folderId),
                container = container,
                panels = panels,
                name = container.name,
                order = container.order,
                ownerKey = ownerKey,
                eligible = eligible,
                selected = eligible and selected or false,
                disabledReason = not eligible and reason or nil,
                note = eligible and reason or nil,
                detail = detail,
            }
            containerInfos[#containerInfos + 1] = info
            byKey[key] = info
            if info.folderKey then
                byFolder[info.folderKey] = byFolder[info.folderKey] or {}
                byFolder[info.folderKey][#byFolder[info.folderKey] + 1] = info
            end
        end
    end
    for _, containers in pairs(byFolder) do
        table.sort(containers, SortByOrderNameId)
    end
    table.sort(containerInfos, SortByOrderNameId)
    return containerInfos, byKey, byFolder
end

local function BuildFolderInfos(profile, containersByFolder, defaultOwnerKey, currentCharKey, currentInfo)
    local folderInfos = {}
    for folderId, folder in pairs(profile.folders or {}) do
        if type(folder) == "table" then
            local key = NormalizeKey(folderId)
            local ownerKey = ResolveOwnerKey(folder, defaultOwnerKey)
            local eligible, selected, reason = BuildEligibility(profile, ownerKey, currentCharKey, currentInfo)
            local containers = containersByFolder[key] or {}
            local panelCount = 0
            for _, containerInfo in ipairs(containers) do
                panelCount = panelCount + #containerInfo.panels
            end
            local detail = tostring(#containers) .. " group" .. (#containers == 1 and "" or "s")
                .. ", " .. tostring(panelCount) .. " panel" .. (panelCount == 1 and "" or "s")
            local info = {
                kind = "folder",
                sourceId = folderId,
                sourceKey = key,
                folder = folder,
                containers = containers,
                name = folder.name,
                order = folder.order,
                ownerKey = ownerKey,
                eligible = eligible,
                selected = eligible and selected or false,
                disabledReason = not eligible and reason or nil,
                note = eligible and reason or nil,
                detail = detail,
            }
            folderInfos[#folderInfos + 1] = info
        end
    end
    table.sort(folderInfos, SortByOrderNameId)
    return folderInfos
end

local function InheritPanelContainerEligibility(panelInfos, containersByKey)
    for _, panelInfo in ipairs(panelInfos) do
        local containerInfo = containersByKey[panelInfo.parentContainerKey]
        if containerInfo then
            panelInfo.eligible = containerInfo.eligible
            panelInfo.selected = containerInfo.eligible and containerInfo.selected or false
            panelInfo.disabledReason = containerInfo.disabledReason
            panelInfo.note = containerInfo.note
        end
    end
end

local function AddRows(model, infos, prefix)
    for _, info in ipairs(infos) do
        local reason = info.disabledReason or info.note
        info.label = RowLabel(prefix, info.name, info.detail, reason)
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
    if type(profile) ~= "table" then
        profile = {}
    end
    options = options or {}
    local currentCharKey, currentInfo = GetCurrentCharInfo()
    currentCharKey = options.currentCharKey or currentCharKey
    currentInfo = options.currentCharInfo or currentInfo
    local defaultOwnerKey = options.exporterCharKey
        or (type(profile) == "table" and profile._exporterCharKey)

    local panelInfos, panelsByContainer = BuildPanelInfos(profile, defaultOwnerKey, currentCharKey, currentInfo)
    local containerInfos, containersByKey, containersByFolder = BuildContainerInfos(
        profile, panelsByContainer, defaultOwnerKey, currentCharKey, currentInfo
    )
    InheritPanelContainerEligibility(panelInfos, containersByKey)
    local folderInfos = BuildFolderInfos(profile, containersByFolder, defaultOwnerKey, currentCharKey, currentInfo)

    local model = {
        rows = {},
        folders = folderInfos,
        containers = containerInfos,
        panels = panelInfos,
        containersByKey = containersByKey,
        panelsByContainer = panelsByContainer,
        eligibleCount = 0,
        selectedCount = 0,
        disabledCount = 0,
        customBarCount = CountProfileCustomBars(profile),
    }

    AddRows(model, folderInfos, "Folder")
    AddRows(model, containerInfos, "Group")
    AddRows(model, panelInfos, "Panel")
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
    local folders, containers, panels = {}, {}, {}
    for _, row in ipairs(model.rows or {}) do
        if row.eligible and row.selected then
            if row.kind == "folder" then
                folders[row.sourceKey] = true
            elseif row.kind == "container" then
                containers[row.sourceKey] = true
            elseif row.kind == "panel" then
                panels[row.sourceKey] = true
            end
        end
    end
    return folders, containers, panels
end

local function EligiblePanels(containerInfo, selectedPanels, includeAll)
    local panels = {}
    for _, panelInfo in ipairs(containerInfo.panels) do
        if panelInfo.eligible and (includeAll or selectedPanels[panelInfo.sourceKey]) then
            local panel = CopyGroupForImport(panelInfo.panel)
            panel._originalGroupId = NumericId(panelInfo.sourceId)
            panels[#panels + 1] = panel
        end
    end
    return panels
end

local function BuildContainerEntry(containerInfo, selectedPanels, includeAll)
    if not (containerInfo and containerInfo.eligible) then
        return nil
    end
    local panels = EligiblePanels(containerInfo, selectedPanels, includeAll)
    return {
        container = CopyContainerForImport(containerInfo.container),
        panels = panels,
        _originalContainerId = NumericId(containerInfo.sourceId),
    }
end

local function AddContainerEntry(entries, containerInfo, selectedPanels, includeAll, importedContainers)
    if not (containerInfo and containerInfo.sourceKey and not importedContainers[containerInfo.sourceKey]) then
        return
    end
    local entry = BuildContainerEntry(containerInfo, selectedPanels, includeAll)
    if entry then
        importedContainers[containerInfo.sourceKey] = true
        entries[#entries + 1] = entry
    end
end

local function ApplyPayload(payload)
    local apply = ST._ApplyGroupImportData
    return apply and apply(payload) == true
end

local function AddCheckpoint(payload, profile)
    if type(payload) == "table" and type(profile) == "table" then
        payload._cdcImportCheckpoint = profile._cdcImportCheckpoint
    end
    return payload
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

    local selectedFolders, selectedContainers, selectedPanels = SelectionSets(model)
    local importedContainers = {}
    local applied = false
    local failed = false

    for _, folderInfo in ipairs(model.folders or {}) do
        if selectedFolders[folderInfo.sourceKey] and folderInfo.eligible then
            local entries = {}
            for _, containerInfo in ipairs(folderInfo.containers or {}) do
                if selectedContainers[containerInfo.sourceKey] then
                    AddContainerEntry(entries, containerInfo, selectedPanels, false, importedContainers)
                end
            end
            local ok = ApplyPayload(AddCheckpoint({
                type = "folder",
                folder = CopyForExport(folderInfo.folder),
                containers = entries,
            }, profile))
            applied = ok or applied
            failed = failed or not ok
        end
    end

    local looseEntries = {}
    for _, containerInfo in ipairs(model.containers or {}) do
        if selectedContainers[containerInfo.sourceKey] then
            AddContainerEntry(looseEntries, containerInfo, selectedPanels, false, importedContainers)
        end
    end

    for _, panelInfo in ipairs(model.panels or {}) do
        local containerInfo = model.containersByKey and model.containersByKey[panelInfo.parentContainerKey]
        if selectedPanels[panelInfo.sourceKey] then
            AddContainerEntry(looseEntries, containerInfo, selectedPanels, false, importedContainers)
        end
    end

    if #looseEntries > 0 then
        local ok = ApplyPayload(AddCheckpoint({
            type = "containers",
            containers = looseEntries,
        }, profile))
        applied = ok or applied
        failed = failed or not ok
    end

    if applied and not failed then
        self:Print("Imported selected profile pieces.")
    elseif failed then
        self:Print("Import failed: some selected profile pieces could not be imported.")
        return false
    else
        self:Print("Import failed: selected profile pieces could not be imported.")
    end
    return applied
end

ST._BuildProfileImportPiecesReview = function(profile, options)
    return CooldownCompanion:BuildProfileImportPiecesReview(profile, options)
end

ST._RecountProfileImportPiecesSelection = RecountSelection

ST._ApplyProfileImportPieces = function(profile, model)
    return CooldownCompanion:ApplyProfileImportPieces(profile, model)
end
