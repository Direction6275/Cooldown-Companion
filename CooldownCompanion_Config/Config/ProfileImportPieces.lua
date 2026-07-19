--[[
    CooldownCompanion - Config/ProfileImportPieces
    Non-destructive selected-pieces import helpers for full profile strings.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local BuildGroupExportData = ST._BuildGroupExportData
local BuildContainerExportData = ST._BuildContainerExportData
local ApplyCustomBarsImportData = ST._ApplyCustomBarsImportData
local BlockCustomBarsImportForResourceBarConflict = ST._BlockCustomBarsImportForResourceBarConflict

local EMPTY_TABLE = {}
local CUSTOM_BAR_CONTENT_FIELDS = {
    "name",
    "spellID",
    "auraSpellID",
    "resourceKey",
    "width",
    "height",
    "texture",
    "barColor",
    "backgroundColor",
    "borderColor",
    "textColor",
    "durationFormat",
    "trackingMode",
    "auraTracking",
    "enabled",
}

local function TableOrEmpty(value)
    return type(value) == "table" and value or EMPTY_TABLE
end

local function CountPairs(tbl)
    local count = 0
    if type(tbl) == "table" then
        for _ in pairs(tbl) do
            count = count + 1
        end
    end
    return count
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

local function NumericSpecId(value)
    local specID = tonumber(value)
    if specID and specID > 0 then
        return specID
    end
    return nil
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
    data.isGlobal = nil
    return data
end

local function IsSharedCustomBarsStore(customBars)
    return type(customBars) == "table"
        and (type(customBars.entries) == "table" or type(customBars.order) == "table")
end

local function IsConfiguredCustomBar(entry)
    local rb = ST._RB
    if rb and rb.IsConfiguredCustomBar then
        return rb.IsConfiguredCustomBar(entry) == true
    end
    if type(entry) ~= "table" then
        return false
    end
    if entry.entryType ~= nil or entry.independentAnchorEnabled ~= nil then
        return true
    end
    for _, field in ipairs(CUSTOM_BAR_CONTENT_FIELDS) do
        if entry[field] ~= nil then
            return true
        end
    end
    return false
end

local function AddSpec(specs, specID)
    specID = NumericSpecId(specID)
    if specID then
        specs[specID] = true
    end
end

local function CopySpecSet(specs)
    local copy = {}
    if type(specs) == "table" then
        for specID, enabled in pairs(specs) do
            if enabled == true then
                copy[specID] = true
            end
        end
    end
    return copy
end

local function CountSpecSet(...)
    local seen = {}
    for i = 1, select("#", ...) do
        local specs = select(i, ...)
        if type(specs) == "table" then
            for specID, enabled in pairs(specs) do
                if enabled == true then
                    seen[specID] = true
                end
            end
        end
    end
    return CountPairs(seen)
end

local function MergeSpecSet(target, source)
    if type(target) ~= "table" or type(source) ~= "table" then
        return
    end
    for specID, enabled in pairs(source) do
        if enabled == true then
            target[specID] = true
        end
    end
end

local function SortedKeys(tbl)
    local keys = {}
    if type(tbl) == "table" then
        for key in pairs(tbl) do
            keys[#keys + 1] = key
        end
    end
    table.sort(keys, function(a, b)
        local numA = tonumber(a)
        local numB = tonumber(b)
        if numA and numB and numA ~= numB then
            return numA < numB
        end
        if numA and not numB then
            return true
        end
        if numB and not numA then
            return false
        end
        local strA = tostring(a)
        local strB = tostring(b)
        if strA ~= strB then
            return strA < strB
        end
        return type(a) < type(b)
    end)
    return keys
end

local function CollectEntrySpecs(entry, fallbackSpecID)
    local specs = {}
    if type(entry) == "table" then
        if type(entry.specs) == "table" then
            for key, value in pairs(entry.specs) do
                if value == true then
                    AddSpec(specs, key)
                elseif type(value) == "number" or type(value) == "string" then
                    AddSpec(specs, value)
                end
            end
        end
        AddSpec(specs, entry.specID or entry.spec or entry.sourceSpecID)
    end
    AddSpec(specs, fallbackSpecID)
    return specs
end

local function CollectCustomBarLayouts(settings, customBarId)
    local layouts = {}
    local layoutOrder = type(settings) == "table" and settings.layoutOrder or nil
    if type(layoutOrder) ~= "table" or customBarId == nil then
        return layouts
    end
    for specID, layout in pairs(layoutOrder) do
        local normalizedSpecID = NumericSpecId(specID)
        local customBars = type(layout) == "table" and layout.customBars or nil
        local customBarLayout = type(customBars) == "table"
            and (customBars[customBarId] or customBars[tostring(customBarId)])
            or nil
        if normalizedSpecID and type(customBarLayout) == "table" then
            layouts[normalizedSpecID] = CopyForExport(customBarLayout)
        end
    end
    return layouts
end

local function CollectLegacyCustomAuraBarSlotLayouts(settings, specID, slotKey)
    local layouts = {}
    specID = NumericSpecId(specID)
    if not specID or slotKey == nil then
        return layouts
    end

    local layoutOrder = type(settings) == "table" and settings.layoutOrder or nil
    local layout = type(layoutOrder) == "table"
        and (layoutOrder[specID] or layoutOrder[tostring(specID)])
        or nil
    local slots = type(layout) == "table" and layout.customAuraBarSlots or nil
    local slotLayout = type(slots) == "table"
        and (slots[slotKey] or slots[tonumber(slotKey)] or slots[tostring(slotKey)])
        or nil
    if type(slotLayout) == "table" then
        layouts[specID] = CopyForExport(slotLayout)
    end
    return layouts
end

local function MergeLayouts(targetLayouts, targetSpecs, sourceLayouts)
    if type(targetLayouts) ~= "table" or type(sourceLayouts) ~= "table" then
        return
    end
    for specID, layout in pairs(sourceLayouts) do
        if type(layout) == "table" then
            if type(targetLayouts[specID]) ~= "table" then
                targetLayouts[specID] = CopyForExport(layout)
            end
            if type(targetSpecs) == "table" then
                targetSpecs[specID] = true
            end
        end
    end
end

local function ShortOwnerLabel(ownerKey)
    if type(ownerKey) ~= "string" or ownerKey == "" then
        return nil
    end
    return ownerKey:match("^([^%-]+)") or ownerKey
end

local function MakeCustomBarPayloadId(index)
    return "profileCustomBar" .. tostring(index)
end

local function CustomBarName(entry)
    if type(entry) ~= "table" then
        return "Custom Bar"
    end
    return entry.name or entry.label or entry.spellName or entry.auraName or "Custom Bar"
end

local function CustomBarDetail(info, includeSource)
    local specCount = CountSpecSet(info.specs, info.layoutSpecs)
    local parts = {}
    if specCount == 0 then
        parts[#parts + 1] = "All specs"
    else
        parts[#parts + 1] = tostring(specCount) .. " spec" .. (specCount == 1 and "" or "s")
    end
    if includeSource then
        local source = ShortOwnerLabel(info.sourceStoreKey)
        if source then
            parts[#parts + 1] = source
        end
    end
    return table.concat(parts, ", ")
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

local function ClassKeyFromInfo(info)
    if type(info) ~= "table" then return nil end
    local classKey = NormalizeClassKey(info.classFilename or info.classFile or info.className)
    if classKey then return classKey end
    local classID = tonumber(info.classID)
    if classID and C_CreatureInfo and C_CreatureInfo.GetClassInfo then
        local classInfo = C_CreatureInfo.GetClassInfo(classID)
        if type(classInfo) == "table" then
            return NormalizeClassKey(classInfo.classFile)
        end
    end
    if classID and GetClassInfo then
        local _, classFilename = GetClassInfo(classID)
        return NormalizeClassKey(classFilename)
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

local function BuildClassStoreEligibility(sourceClassKey, currentInfo)
    sourceClassKey = NormalizeClassKey(sourceClassKey)
    local currentClassKey = ClassKeyFromInfo(currentInfo)
    if not sourceClassKey or not currentClassKey then
        return false, false, "Source class unknown"
    end
    if sourceClassKey ~= currentClassKey then
        return false, false, sourceClassKey .. " content"
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
            local panelCount = #panels
            local detail = tostring(panelCount) .. " panel" .. (panelCount == 1 and "" or "s")
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
                detail = detail,
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

local function AddCustomBarInfo(infos, profile, settings, sourceStoreKey, entryKey, entry, options)
    if type(entry) ~= "table" or not IsConfiguredCustomBar(entry) then
        return
    end
    options = options or {}
    local ownerKey = sourceStoreKey
    local eligible, selected, reason
    if options.sourceClassKey then
        eligible, selected, reason = BuildClassStoreEligibility(options.sourceClassKey, options.currentInfo)
    else
        eligible, selected, reason = BuildEligibility(
            profile,
            ownerKey,
            options.currentCharKey,
            options.currentInfo,
            options.sourceCharacterInfo
        )
    end
    local rawId = type(entry.customBarId) == "string" and entry.customBarId ~= "" and entry.customBarId
        or (type(entryKey) == "string" and entryKey or nil)
    if rawId and options.skipRawIds and options.skipRawIds[rawId] then
        return
    end
    local specs = CollectEntrySpecs(entry, options.fallbackSpecID)
    local layouts = CollectCustomBarLayouts(settings, rawId)
    if options.legacyAuraSlots then
        MergeLayouts(layouts, nil, CollectLegacyCustomAuraBarSlotLayouts(
            settings,
            options.fallbackSpecID,
            entryKey
        ))
    end
    local existing = rawId and options.infoByRawId and options.infoByRawId[rawId]
    if existing then
        MergeSpecSet(existing.specs, specs)
        MergeLayouts(existing.layouts, existing.layoutSpecs, layouts)
        return existing
    end
    local layoutSpecs = {}
    for specID in pairs(layouts) do
        layoutSpecs[specID] = true
    end
    local info = {
        kind = "customBar",
        sourceId = MakeCustomBarPayloadId(#infos + 1),
        sourceStoreKey = sourceStoreKey,
        sourceEntryKey = entryKey,
        rawCustomBarId = rawId,
        customBar = entry,
        name = CustomBarName(entry),
        order = options.order,
        ownerKey = ownerKey,
        eligible = eligible,
        selected = eligible and selected or false,
        disabledReason = not eligible and reason or nil,
        note = eligible and reason or nil,
        specs = specs,
        layoutSpecs = layoutSpecs,
        layouts = layouts,
    }
    info.sourceKey = "customBar:" .. info.sourceId
    infos[#infos + 1] = info
    if rawId and options.infoByRawId then
        options.infoByRawId[rawId] = info
    end
    return info
end

local function AddSharedCustomBarInfos(infos, profile, settings, sourceStoreKey, customBars, options)
    local entries = type(customBars.entries) == "table" and customBars.entries or EMPTY_TABLE
    local seen = {}
    local order = 0
    if type(customBars.order) == "table" then
        for _, customBarId in ipairs(customBars.order) do
            local entry = entries[customBarId]
            if type(entry) == "table" then
                seen[customBarId] = true
                order = order + 1
                AddCustomBarInfo(infos, profile, settings, sourceStoreKey, customBarId, entry, {
                    currentCharKey = options.currentCharKey,
                    currentInfo = options.currentInfo,
                    sourceCharacterInfo = options.sourceCharacterInfo,
                    sourceClassKey = options.sourceClassKey,
                    infoByRawId = options.infoByRawId,
                    skipRawIds = options.skipRawIds,
                    order = order,
                })
            end
        end
    end
    for entryKey, entry in pairs(entries) do
        if not seen[entryKey] then
            order = order + 1
            AddCustomBarInfo(infos, profile, settings, sourceStoreKey, entryKey, entry, {
                currentCharKey = options.currentCharKey,
                currentInfo = options.currentInfo,
                sourceCharacterInfo = options.sourceCharacterInfo,
                sourceClassKey = options.sourceClassKey,
                infoByRawId = options.infoByRawId,
                skipRawIds = options.skipRawIds,
                order = order,
            })
        end
    end
end

local function AddSpecKeyedCustomBarInfos(infos, profile, settings, sourceStoreKey, customBars, options)
    local order = 0
    for _, specKey in ipairs(SortedKeys(customBars)) do
        local specBars = customBars[specKey]
        local specID = NumericSpecId(specKey)
        if specID and type(specBars) == "table" then
            for _, entryKey in ipairs(SortedKeys(specBars)) do
                local entry = specBars[entryKey]
                if type(entry) == "table" then
                    order = order + 1
                    AddCustomBarInfo(infos, profile, settings, sourceStoreKey, entryKey, entry, {
                        currentCharKey = options.currentCharKey,
                        currentInfo = options.currentInfo,
                        sourceCharacterInfo = options.sourceCharacterInfo,
                        sourceClassKey = options.sourceClassKey,
                        fallbackSpecID = specID,
                        infoByRawId = options.infoByRawId,
                        legacyAuraSlots = options.legacyAuraSlots,
                        skipRawIds = options.skipRawIds,
                        order = order,
                    })
                end
            end
        end
    end
end

local function BuildCustomBarInfos(profile, currentCharKey, currentInfo, sourceCharacterInfo)
    local infos = {}
    local classStores = type(profile) == "table" and profile.resourceBarsByClass or nil
    local legacyStores = type(profile) == "table" and profile.resourceBarsByChar or nil
    local classStoreRawIds = {}

    local function addFromSettings(sourceStoreKey, settings, options)
        local initialCount = #infos
        if type(settings) == "table" then
            local infoByRawId = {}
            local customBars = settings.customBars
            if IsSharedCustomBarsStore(customBars) then
                AddSharedCustomBarInfos(infos, profile, settings, sourceStoreKey, customBars, {
                    currentCharKey = options.currentCharKey,
                    currentInfo = options.currentInfo,
                    sourceCharacterInfo = options.sourceCharacterInfo,
                    sourceClassKey = options.sourceClassKey,
                    infoByRawId = infoByRawId,
                    skipRawIds = options.skipRawIds,
                })
            elseif type(customBars) == "table" then
                AddSpecKeyedCustomBarInfos(infos, profile, settings, sourceStoreKey, customBars, {
                    currentCharKey = options.currentCharKey,
                    currentInfo = options.currentInfo,
                    sourceCharacterInfo = options.sourceCharacterInfo,
                    sourceClassKey = options.sourceClassKey,
                    infoByRawId = infoByRawId,
                    skipRawIds = options.skipRawIds,
                })
            end
            if type(settings.customAuraBars) == "table" then
                AddSpecKeyedCustomBarInfos(infos, profile, settings, sourceStoreKey, settings.customAuraBars, {
                    currentCharKey = options.currentCharKey,
                    currentInfo = options.currentInfo,
                    sourceCharacterInfo = options.sourceCharacterInfo,
                    sourceClassKey = options.sourceClassKey,
                    infoByRawId = infoByRawId,
                    legacyAuraSlots = true,
                    skipRawIds = options.skipRawIds,
                })
            end
            if options.recordRawIds then
                for rawId in pairs(infoByRawId) do
                    options.recordRawIds[rawId] = true
                end
            end
        end
        return #infos > initialCount
    end

    if type(classStores) == "table" then
        for sourceClassKey, settings in pairs(classStores) do
            local normalizedClassKey = NormalizeClassKey(sourceClassKey)
            if normalizedClassKey and type(settings) == "table" then
                local rawIds = {}
                local added = addFromSettings(normalizedClassKey, settings, {
                    currentCharKey = currentCharKey,
                    currentInfo = currentInfo,
                    sourceCharacterInfo = sourceCharacterInfo,
                    sourceClassKey = normalizedClassKey,
                    recordRawIds = rawIds,
                })
                if added then
                    classStoreRawIds[normalizedClassKey] = rawIds
                end
            end
        end
    end

    if type(legacyStores) == "table" then
        for sourceStoreKey, settings in pairs(legacyStores) do
            local ownerInfo = GetOwnerInfo(profile, sourceStoreKey, sourceCharacterInfo)
            local ownerClassKey = ClassKeyFromInfo(ownerInfo)
            addFromSettings(sourceStoreKey, settings, {
                currentCharKey = currentCharKey,
                currentInfo = currentInfo,
                sourceCharacterInfo = sourceCharacterInfo,
                skipRawIds = ownerClassKey and classStoreRawIds[ownerClassKey] or nil,
            })
        end
    end

    local sourceStores = {}
    for _, info in ipairs(infos) do
        sourceStores[info.sourceStoreKey] = true
    end
    local includeSource = CountPairs(sourceStores) > 1
    for _, info in ipairs(infos) do
        info.detail = CustomBarDetail(info, includeSource)
        info.label = RowLabel("Custom Bar", info.name, info.detail, info.disabledReason or info.note)
    end
    table.sort(infos, SortByOrderNameId)
    return infos
end

function CooldownCompanion:BuildProfileImportPiecesReview(profile, options)
    if type(profile) ~= "table" then
        profile = {}
    else
        profile = CopyTable(profile)
        if self.MigrateFoldersIntoGroups then
            -- Present old backups in the supported hierarchy and carry every
            -- inherited restriction onto the Group rows before selection.
            self:MigrateFoldersIntoGroups(profile)
        end
    end
    options = options or {}
    local currentCharKey, currentInfo = GetCurrentCharInfo()
    currentCharKey = options.currentCharKey or currentCharKey
    currentInfo = options.currentCharInfo or currentInfo
    local sourceCharacterInfo = options.sourceCharacterInfo
    local defaultOwnerKey = options.exporterCharKey
        or (type(profile) == "table" and profile._exporterCharKey)

    local panelInfos, panelsByContainer = BuildPanelInfos(
        profile, defaultOwnerKey, currentCharKey, currentInfo, sourceCharacterInfo
    )
    local containerInfos, containersByKey = BuildContainerInfos(
        profile, panelsByContainer, defaultOwnerKey, currentCharKey, currentInfo, sourceCharacterInfo
    )
    InheritPanelContainerEligibility(panelInfos, containersByKey)
    local customBarInfos = BuildCustomBarInfos(profile, currentCharKey, currentInfo, sourceCharacterInfo)

    local model = {
        rows = {},
        containers = containerInfos,
        panels = panelInfos,
        customBars = customBarInfos,
        containersByKey = containersByKey,
        panelsByContainer = panelsByContainer,
        currentClassID = currentInfo and currentInfo.classID,
        currentClassFilename = currentInfo and currentInfo.classFilename,
        eligibleCount = 0,
        selectedCount = 0,
        disabledCount = 0,
        customBarCount = #customBarInfos,
    }

    AddRows(model, containerInfos, "Group")
    AddRows(model, panelInfos, "Panel")
    AddRows(model, customBarInfos, "Custom Bar")
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
    local containers, panels, customBars = {}, {}, {}
    local deselectedContainers, deselectedPanels = {}, {}
    for _, row in ipairs(model.rows or {}) do
        if row.eligible then
            if row.selected then
                if row.kind == "container" then
                    containers[row.sourceKey] = true
                elseif row.kind == "panel" then
                    panels[row.sourceKey] = true
                elseif row.kind == "customBar" then
                    customBars[row.sourceKey] = true
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
    return containers, panels, customBars, deselectedContainers, deselectedPanels
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

local function BuildSelectedCustomBarsPayload(model, selectedCustomBars)
    if type(model) ~= "table" or type(selectedCustomBars) ~= "table" then
        return nil
    end
    local payload = {
        type = "customBars",
        version = 1,
        classID = model.currentClassID,
        classFilename = model.currentClassFilename,
        bars = {},
        layouts = {},
    }
    for _, info in ipairs(model.customBars or {}) do
        if info.eligible and selectedCustomBars[info.sourceKey] then
            local payloadId = info.sourceId
            local entry = CopyForExport(info.customBar)
            entry.customBarId = payloadId
            entry.specs = CopySpecSet(info.specs)
            entry.specID = nil
            entry.spec = nil
            entry.sourceSpecID = nil
            payload.bars[#payload.bars + 1] = entry
            for specID, layout in pairs(info.layouts or {}) do
                if type(layout) == "table" then
                    payload.layouts[specID] = payload.layouts[specID] or {}
                    payload.layouts[specID][payloadId] = CopyForExport(layout)
                end
            end
        end
    end
    if #payload.bars == 0 then
        return nil
    end
    return payload
end

local function ApplyCustomBarsPayload(profile, payload)
    if not (ApplyCustomBarsImportData and payload) then
        return false
    end
    return ApplyCustomBarsImportData(AddCheckpoint(payload, profile), {
        silentSuccess = true,
    }) == true
end

local function ShouldBlockSelectedCustomBarsImport()
    local block = BlockCustomBarsImportForResourceBarConflict
        or ST._BlockCustomBarsImportForResourceBarConflict
    return block and block() == true
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

    local selectedContainers, selectedPanels, selectedCustomBars, deselectedContainers, deselectedPanels = SelectionSets(model)
    local selectedCustomBarsPayload = BuildSelectedCustomBarsPayload(model, selectedCustomBars)

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

    if selectedCustomBarsPayload and ShouldBlockSelectedCustomBarsImport() then
        failed = true
    elseif selectedCustomBarsPayload then
        local ok = ApplyCustomBarsPayload(profile, selectedCustomBarsPayload)
        applied = ok or applied
        failed = failed or not ok
    elseif CountPairs(selectedCustomBars) > 0 then
        failed = true
    end

    FinishImportBatch(batchToken, applied)
    if applied then
        if self.RefreshAllGroups then
            self:RefreshAllGroups()
        end
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
ST._SetProfileImportPieceSelected = SetProfileImportPieceSelected

ST._ApplyProfileImportPieces = function(profile, model)
    return CooldownCompanion:ApplyProfileImportPieces(profile, model)
end
