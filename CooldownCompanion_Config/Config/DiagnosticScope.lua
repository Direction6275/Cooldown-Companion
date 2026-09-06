--[[
    CooldownCompanion - Config/DiagnosticScope
    Conservative, saved-data-only diagnostic slicing. Never edits the profile
    or evaluates transient visibility, spec, talent, or load-condition state.
]]
local _, ST = ...

local CHARACTER_STORES = {
    resourceBarsByChar = true, castBarByChar = true, frameAnchoringByChar = true,
    healthBarByChar = true, cdmAuraSetupByChar = true,
}
local function Count(t)
    local count = 0
    for _ in pairs(type(t) == "table" and t or {}) do count = count + 1 end
    return count
end
local function Key(t, id)
    if type(t) ~= "table" or id == nil then return nil end
    if t[id] ~= nil then return id end
    if t[tostring(id)] ~= nil then return tostring(id) end
    local number = tonumber(id)
    if number and t[number] ~= nil then return number end
end

local function BuildScopedDiagnosticProfile(profile, meta, config, runtime, characterInfo)
    meta, config, runtime = meta or {}, config or {}, runtime or {}
    characterInfo = type(characterInfo) == "table" and characterInfo or {}
    local knownClasses = {}
    for _, info in pairs(characterInfo) do
        if type(info) == "table" and type(info.classFilename) == "string" and info.classFilename ~= "" then
            knownClasses[info.classFilename:upper()] = true
        end
    end
    local scoped = CopyTable(profile)
    local groups, containers = profile.groups or {}, profile.groupContainers or {}
    local keptGroups, keptContainers = {}, {}
    local pending = {}
    local scope = {
        kind = "character", className = meta.className, charKey = meta.charKey,
        allClassSpecs = true, omittedPanelIds = {}, omittedContainerIds = {},
        omittedClassStores = {}, omittedCharacterStores = {}, unknownOwnerCount = 0,
        dependencyPanelCount = 0,
    }
    local function IsOtherClass(entity)
        if type(entity) ~= "table" or entity.isGlobal == true then return false end
        local owner = entity.createdBy
        if owner and owner == meta.charKey then return false end
        local info = owner and characterInfo[owner]
        if type(info) == "table" then
            if type(info.classFilename) == "string" and info.classFilename ~= ""
                and type(meta.className) == "string" and meta.className ~= "" then
                return info.classFilename:upper() ~= meta.className:upper()
            end
            if type(info.classID) == "number" and info.classID > 0
                and type(meta.classID) == "number" and meta.classID > 0 then
                return info.classID ~= meta.classID
            end
        end
        scope.unknownOwnerCount = scope.unknownOwnerCount + 1
        return false
    end
    local keepPanel, keepContainer
    keepContainer = function(id)
        id = Key(containers, id)
        if not id or keptContainers[id] then return end
        keptContainers[id] = true
        pending[#pending + 1] = containers[id]
        -- A group is a layout unit. Keep siblings even when only one panel
        -- was selected or referenced by a retained anchor.
        for panelId, panel in pairs(groups) do
            if type(panel) == "table" and Key(containers, panel.parentContainerId) == id then
                keepPanel(panelId)
            end
        end
    end
    keepPanel = function(id)
        id = Key(groups, id)
        if not id or keptGroups[id] then return end
        keptGroups[id] = true
        pending[#pending + 1] = groups[id]
        local panel = groups[id]
        if type(panel) == "table" then keepContainer(panel.parentContainerId) end
    end
    for id, container in pairs(containers) do
        if not IsOtherClass(container) then keepContainer(id) end
    end
    for id, panel in pairs(groups) do
        if not keptGroups[id] and type(panel) ~= "table" then
            keepPanel(id)
        elseif not keptGroups[id] then
            local parent = Key(containers, panel.parentContainerId)
            -- A missing parent is diagnostic evidence, not an exclusion.
            if (panel.parentContainerId and not parent) or (not parent and not IsOtherClass(panel)) then
                keepPanel(id)
            end
        end
    end
    local initialPanels = Count(keptGroups)
    keepContainer(config.selectedContainer)
    keepPanel(config.selectedGroup)
    for id in tostring(config.selectedGroups or ""):gmatch("[^,]+") do keepContainer(id) end
    for id in tostring(config.selectedPanels or ""):gmatch("[^,]+") do keepPanel(id) end
    for id, state in pairs(runtime.groupFrameStates or {}) do
        if type(state) == "table" and state.shown then keepPanel(id) end
    end
    for id, state in pairs(runtime.containerFrameStates or {}) do
        if type(state) == "table" and state.shown then keepContainer(id) end
    end

    -- Keep only the current character's known character-local stores. Retain
    -- malformed store keys, which cannot be confidently attributed elsewhere.
    for name in pairs(CHARACTER_STORES) do
        local store = scoped[name]
        if type(store) == "table" and type(meta.charKey) == "string" and meta.charKey ~= "" then
            local removed = 0
            for owner in pairs(store) do
                if type(owner) == "string" and owner ~= meta.charKey and characterInfo[owner] ~= nil then
                    store[owner] = nil
                    removed = removed + 1
                end
            end
            if removed > 0 then scope.omittedCharacterStores[name] = removed end
        end
    end
    if type(scoped.resourceBarsByClass) == "table" and type(meta.className) == "string" and meta.className ~= "" then
        for className in pairs(scoped.resourceBarsByClass) do
            if type(className) == "string" and knownClasses[className:upper()]
                and className:upper() ~= meta.className:upper()
                and className ~= config.otherClassLibraryClassKey then
                scope.omittedClassStores[#scope.omittedClassStores + 1] = className
                scoped.resourceBarsByClass[className] = nil
            end
        end
        table.sort(scope.omittedClassStores)
    end
    -- Presets are copied into settings when applied; no runtime reader uses
    -- them as inherited defaults. Full reports retain the preset library.
    scope.omittedPresetStores = Count(scoped.groupSettingPresets)
    scoped.groupSettingPresets = nil

    local function References(value)
        if type(value) ~= "table" then return end
        for key, child in pairs(value) do
            if type(child) == "table" then
                References(child)
            elseif key == "relativeTo" and type(child) == "string" then
                keepPanel(child:match("^CooldownCompanionGroup(%d+)$"))
                keepContainer(child:match("^CooldownCompanionContainer(%d+)$"))
            elseif key == "anchorGroupId" or key == "independentAnchorGroupId" or key == "groupId" or key == "panelId" then
                keepPanel(child)
            end
        end
    end
    -- Current bar settings and the captured runtime can refer to panels even
    -- when those panels have failed their own load conditions.
    for name, value in pairs(scoped) do
        if name ~= "groups" and name ~= "groupContainers" then References(value) end
    end
    References(runtime)
    -- This store is keyed by spec ID, so References cannot discover its panel
    -- IDs. Preserve every mark (including unresolved targets) and include all
    -- existing targets before closing dependencies. Saved ownership alone
    -- cannot establish which spec's mark is irrelevant to the reported bug.
    if type(scoped.externalAnchorPanels) == "table" then
        for _, panelId in pairs(scoped.externalAnchorPanels) do
            keepPanel(panelId)
        end
    end
    local index = 1
    while index <= #pending do
        References(pending[index])
        index = index + 1
    end
    scoped.groups, scoped.groupContainers = {}, {}
    for id, panel in pairs(groups) do
        if keptGroups[id] then scoped.groups[id] = CopyTable(panel)
        else scope.omittedPanelIds[#scope.omittedPanelIds + 1] = id end
    end
    for id, container in pairs(containers) do
        if keptContainers[id] then scoped.groupContainers[id] = CopyTable(container)
        else scope.omittedContainerIds[#scope.omittedContainerIds + 1] = id end
    end
    local function SortIds(ids)
        table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
    end
    SortIds(scope.omittedPanelIds)
    SortIds(scope.omittedContainerIds)
    scoped._characterInfo = {}
    for _, entities in ipairs({ scoped.groups, scoped.groupContainers }) do
        for _, entity in pairs(entities) do
            local owner = type(entity) == "table" and entity.createdBy
            if owner and characterInfo[owner] then
                scoped._characterInfo[owner] = CopyTable(characterInfo[owner])
            end
        end
    end
    scoped._cdcDiagnosticScope = "character"
    scope.includedPanels = Count(scoped.groups)
    scope.includedContainers = Count(scoped.groupContainers)
    scope.includedButtons = 0
    for _, panel in pairs(scoped.groups) do
        if type(panel) == "table" and type(panel.buttons) == "table" then
            scope.includedButtons = scope.includedButtons + #panel.buttons
        end
    end
    scope.dependencyPanelCount = scope.includedPanels - initialPanels
    return scoped, scope
end

ST._BuildScopedDiagnosticProfile = BuildScopedDiagnosticProfile
