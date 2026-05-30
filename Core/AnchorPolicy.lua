--[[
    CooldownCompanion - AnchorPolicy
    Shared rules for addon-frame anchor eligibility.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local CURSOR_ANCHOR_TARGET = "CooldownCompanionCursor"
local DEFAULT_CURSOR_ANCHOR = {
    point = "BOTTOMLEFT",
    relativeTo = CURSOR_ANCHOR_TARGET,
    relativePoint = "CENTER",
    x = 16,
    y = 16,
}

ST.CURSOR_ANCHOR_TARGET = CURSOR_ANCHOR_TARGET
local PANEL_ANCHOR_DOMAINS = {
    panel = true,
    ["panel-target"] = true,
    ["panel-import"] = true,
}

local EXTERNAL_ANCHOR_STORES = {
    castBar = {
        rootKey = "castBar",
        rootName = "Cast Bar",
        legacyKey = "legacyCastBarSeed",
        legacyName = "Cast Bar Seed",
        scopedKey = "castBarByChar",
        scopedNamePrefix = "Cast Bar ",
    },
    resourceBars = {
        rootKey = "resourceBars",
        rootName = "Resource Bars",
        legacyKey = "legacyResourceBarsSeed",
        legacyName = "Resource Bars Seed",
        scopedKey = "resourceBarsByChar",
        scopedNamePrefix = "Resource Bars ",
    },
    frameAnchoring = {
        rootKey = "frameAnchoring",
        rootName = "Unit Frames",
        legacyKey = "legacyFrameAnchoringSeed",
        legacyName = "Unit Frames Seed",
        scopedKey = "frameAnchoringByChar",
        scopedNamePrefix = "Unit Frames ",
    },
}

local function CopyAnchor(anchor)
    return {
        point = anchor.point,
        relativeTo = anchor.relativeTo,
        relativePoint = anchor.relativePoint,
        x = anchor.x,
        y = anchor.y,
    }
end

local function NormalizeCursorAnchor(anchor)
    local changed = false
    if type(anchor) ~= "table" then
        return CopyAnchor(DEFAULT_CURSOR_ANCHOR), true
    end

    if anchor.point == nil or anchor.point == "" then
        anchor.point = DEFAULT_CURSOR_ANCHOR.point
        changed = true
    end
    if anchor.relativeTo ~= CURSOR_ANCHOR_TARGET then
        anchor.relativeTo = CURSOR_ANCHOR_TARGET
        changed = true
    end
    if anchor.relativePoint ~= DEFAULT_CURSOR_ANCHOR.relativePoint then
        anchor.relativePoint = DEFAULT_CURSOR_ANCHOR.relativePoint
        changed = true
    end

    local x = tonumber(anchor.x)
    if x == nil then
        anchor.x = DEFAULT_CURSOR_ANCHOR.x
        changed = true
    elseif anchor.x ~= x then
        anchor.x = x
        changed = true
    end

    local y = tonumber(anchor.y)
    if y == nil then
        anchor.y = DEFAULT_CURSOR_ANCHOR.y
        changed = true
    elseif anchor.y ~= y then
        anchor.y = y
        changed = true
    end

    return anchor, changed
end

local function GetProfile(self)
    return self and self.db and self.db.profile or nil
end

local function GetGroup(self, groupOrId)
    if type(groupOrId) == "table" then
        return groupOrId
    end
    local profile = GetProfile(self)
    return profile and profile.groups and profile.groups[groupOrId] or nil
end

local function ParseAddonAnchorFrameName(frameName)
    if type(frameName) ~= "string" then return nil end

    local groupId = frameName:match("^CooldownCompanionGroup(%d+)$")
    if groupId then
        return "group", tonumber(groupId)
    end

    local containerId = frameName:match("^CooldownCompanionContainer(%d+)$")
    if containerId then
        return "container", tonumber(containerId)
    end

    if frameName == CURSOR_ANCHOR_TARGET then
        return "cursor", nil
    end
end

local function AddonAnchorFrameReachesCursorRoot(profile, kind, id, visited)
    local node
    if kind == "group" then
        node = profile and profile.groups and profile.groups[id]
    elseif kind == "container" then
        node = profile and profile.groupContainers and profile.groupContainers[id]
    end
    if not node then
        return false
    end
    local anchor = node.anchor
    local relativeTo
    if type(anchor) == "table" then
        relativeTo = anchor.relativeTo
    elseif type(anchor) == "string" then
        relativeTo = anchor
    else
        return false
    end

    visited = visited or {}
    local visitKey = tostring(kind) .. ":" .. tostring(id)
    if visited[visitKey] then
        return false
    end
    visited[visitKey] = true

    if relativeTo == CURSOR_ANCHOR_TARGET then
        return true
    end

    local targetKind, targetId = ParseAddonAnchorFrameName(relativeTo)
    if targetKind == "group" or targetKind == "container" then
        return AddonAnchorFrameReachesCursorRoot(profile, targetKind, targetId, visited)
    end
    return false
end

local function BuildRootAnchor(relativeTo)
    return {
        point = "CENTER",
        relativeTo = relativeTo or "UIParent",
        relativePoint = "CENTER",
        x = 0,
        y = 0,
    }
end

local function AnchorTargetsCursorRoot(profile, relativeTo)
    if relativeTo == CURSOR_ANCHOR_TARGET then
        return true
    end
    local kind, targetId = ParseAddonAnchorFrameName(relativeTo)
    if kind == "group" or kind == "container" then
        return AddonAnchorFrameReachesCursorRoot(profile, kind, targetId)
    end
    return false
end

local function BuildCursorRootAddonFrameMaps(profile)
    local cursorRootGroups = {}
    local cursorRootContainers = {}
    for groupId in pairs(profile and profile.groups or {}) do
        if AddonAnchorFrameReachesCursorRoot(profile, "group", groupId) then
            cursorRootGroups[groupId] = true
        end
    end
    for containerId in pairs(profile and profile.groupContainers or {}) do
        if AddonAnchorFrameReachesCursorRoot(profile, "container", containerId) then
            cursorRootContainers[containerId] = true
        end
    end
    return cursorRootGroups, cursorRootContainers
end

local function BuildCursorRootTargetPredicate(profile)
    local cursorRootGroups, cursorRootContainers = BuildCursorRootAddonFrameMaps(profile)
    return function(relativeTo)
        if relativeTo == CURSOR_ANCHOR_TARGET then
            return true
        end
        local kind, targetId = ParseAddonAnchorFrameName(relativeTo)
        if kind == "group" then
            return cursorRootGroups[targetId] == true
        end
        if kind == "container" then
            return cursorRootContainers[targetId] == true
        end
        return false
    end
end

local function ResetExternalAnchor(anchor)
    anchor.point = "CENTER"
    anchor.relativeTo = nil
    anchor.relativePoint = "CENTER"
    anchor.x = 0
    anchor.y = 0
end

local function SanitizeExternalAnchor(anchor, targetIsCursorRoot)
    if type(anchor) ~= "table" then
        return
    end
    if targetIsCursorRoot(anchor.relativeTo) then
        ResetExternalAnchor(anchor)
    end
end

local function SanitizeExternalFrameName(settings, key, targetIsCursorRoot)
    if type(settings) ~= "table" then
        return
    end
    if targetIsCursorRoot(settings[key]) then
        settings[key] = ""
    end
end

local function SanitizeFrameAnchoringSettings(settings, targetIsCursorRoot)
    SanitizeExternalFrameName(settings, "customPlayerFrame", targetIsCursorRoot)
    SanitizeExternalFrameName(settings, "customTargetFrame", targetIsCursorRoot)
end

local function SanitizeResourceBarSettings(settings, targetIsCursorRoot)
    if type(settings) ~= "table" then
        return
    end
    SanitizeExternalAnchor(settings.independentAnchor, targetIsCursorRoot)
    local layoutOrder = settings.layoutOrder
    if type(layoutOrder) == "table" then
        for _, layout in pairs(layoutOrder) do
            if type(layout) == "table" then
                SanitizeExternalAnchor(layout.independentAnchor, targetIsCursorRoot)
            end
        end
    end
end

local function SanitizeCastBarSettings(settings, targetIsCursorRoot)
    if type(settings) ~= "table" then
        return
    end
    SanitizeExternalAnchor(settings.independentAnchor, targetIsCursorRoot)
end

local function ForEachExternalAnchorSettings(profile, store, apply)
    apply(profile[store.rootKey], store.rootName)
    apply(profile[store.legacyKey], store.legacyName)

    local stores = profile[store.scopedKey]
    if type(stores) == "table" then
        for charKey, settings in pairs(stores) do
            apply(settings, store.scopedNamePrefix .. tostring(charKey))
        end
    end
end

local function SanitizeScopedExternalAnchors(profile, targetIsCursorRoot)
    ForEachExternalAnchorSettings(profile, EXTERNAL_ANCHOR_STORES.castBar, function(settings)
        SanitizeCastBarSettings(settings, targetIsCursorRoot)
    end)
    ForEachExternalAnchorSettings(profile, EXTERNAL_ANCHOR_STORES.resourceBars, function(settings)
        SanitizeResourceBarSettings(settings, targetIsCursorRoot)
    end)
    ForEachExternalAnchorSettings(profile, EXTERNAL_ANCHOR_STORES.frameAnchoring, function(settings)
        SanitizeFrameAnchoringSettings(settings, targetIsCursorRoot)
    end)
end

local function AddDependent(dependents, name)
    dependents[#dependents + 1] = {
        name = name,
    }
end

local function AddAnchorDependent(dependents, anchor, targetFrameName, name)
    if type(anchor) == "table" and anchor.relativeTo == targetFrameName then
        AddDependent(dependents, name)
    end
end

local function AddFrameNameDependent(dependents, frameName, targetFrameName, name)
    if frameName == targetFrameName then
        AddDependent(dependents, name)
    end
end

local function AddResourceBarDependents(dependents, settings, targetFrameName, name)
    if type(settings) ~= "table" then
        return
    end
    AddAnchorDependent(dependents, settings.independentAnchor, targetFrameName, name)
    local layoutOrder = settings.layoutOrder
    if type(layoutOrder) == "table" then
        for layoutId, layout in pairs(layoutOrder) do
            AddAnchorDependent(
                dependents,
                type(layout) == "table" and layout.independentAnchor or nil,
                targetFrameName,
                name .. " Layout " .. tostring(layoutId)
            )
        end
    end
end

local function AddCastBarDependents(dependents, settings, targetFrameName, name)
    if type(settings) ~= "table" then
        return
    end
    AddAnchorDependent(dependents, settings.independentAnchor, targetFrameName, name)
end

local function AddFrameAnchoringDependents(dependents, settings, targetFrameName, name)
    if type(settings) ~= "table" then
        return
    end
    AddFrameNameDependent(dependents, settings.customPlayerFrame, targetFrameName, name .. " Player")
    AddFrameNameDependent(dependents, settings.customTargetFrame, targetFrameName, name .. " Target")
end

function CooldownCompanion:GetCursorAnchorTargetName()
    return CURSOR_ANCHOR_TARGET
end

function CooldownCompanion:GetDefaultCursorPanelAnchor()
    return CopyAnchor(DEFAULT_CURSOR_ANCHOR)
end

function CooldownCompanion:NormalizeCursorAnchor(anchor)
    return NormalizeCursorAnchor(anchor)
end

function CooldownCompanion:IsCursorAnchor(anchor)
    if anchor == CURSOR_ANCHOR_TARGET then
        return true
    end
    return type(anchor) == "table" and anchor.relativeTo == CURSOR_ANCHOR_TARGET
end

function CooldownCompanion:IsGroupCursorAnchored(groupOrId)
    local group = GetGroup(self, groupOrId)
    return self:IsCursorAnchor(group and group.anchor)
end

function CooldownCompanion:DoesAnchorTargetReachCursorRoot(relativeTo, profile)
    return AnchorTargetsCursorRoot(profile or GetProfile(self), relativeTo)
end

function CooldownCompanion:ParseAddonAnchorFrameName(frameName)
    return ParseAddonAnchorFrameName(frameName)
end

function CooldownCompanion:GetAddonAnchorTargetInfo(frameName)
    local kind, id = ParseAddonAnchorFrameName(frameName)
    if kind then
        return {
            kind = kind,
            id = id,
            frameName = frameName,
        }
    end
    return nil
end

function CooldownCompanion:CanGroupUseCursorAnchor(groupOrId)
    local group = GetGroup(self, groupOrId)
    return group and group.parentContainerId ~= nil or false
end

function CooldownCompanion:GetGroupAnchorValidationDomain(groupOrId)
    local group = GetGroup(self, groupOrId)
    return group and group.parentContainerId and "panel" or "external"
end

function CooldownCompanion:GetGroupAnchorValidationOptions(groupId)
    return {
        domain = self:GetGroupAnchorValidationDomain(groupId),
        sourceGroupId = groupId,
        sourceKind = "group",
    }
end

function CooldownCompanion:CanGroupBePanelAnchorTarget(targetGroupId, sourceGroupId)
    local profile = GetProfile(self)
    local group = GetGroup(self, targetGroupId)
    if not group then return false, "missing" end
    if not group.parentContainerId then return false, "not-panel" end
    if AnchorTargetsCursorRoot(profile, "CooldownCompanionGroup" .. tostring(targetGroupId)) then
        return false, "cursor-root-target"
    end
    if group.displayMode == "textures" or group.displayMode == "trigger" then
        return false, "unsupported-display-mode"
    end
    if sourceGroupId and self.WouldCreateCircularAnchor and self:WouldCreateCircularAnchor(sourceGroupId, targetGroupId) then
        return false, "circular"
    end
    return true
end

function CooldownCompanion:CanGroupBeExternalAnchorTarget(targetGroupId)
    local profile = GetProfile(self)
    local group = GetGroup(self, targetGroupId)
    if not group then return false, "missing" end
    if AnchorTargetsCursorRoot(profile, "CooldownCompanionGroup" .. tostring(targetGroupId)) then
        return false, "cursor-root-target"
    end
    return true
end

function CooldownCompanion:GetExternalAnchorDependents(groupId, profile)
    profile = profile or GetProfile(self)
    if type(profile) ~= "table" then
        return {}
    end

    local targetFrameName = "CooldownCompanionGroup" .. tostring(groupId)
    local dependents = {}

    ForEachExternalAnchorSettings(profile, EXTERNAL_ANCHOR_STORES.castBar, function(settings, name)
        AddCastBarDependents(dependents, settings, targetFrameName, name)
    end)
    ForEachExternalAnchorSettings(profile, EXTERNAL_ANCHOR_STORES.resourceBars, function(settings, name)
        AddResourceBarDependents(dependents, settings, targetFrameName, name)
    end)
    ForEachExternalAnchorSettings(profile, EXTERNAL_ANCHOR_STORES.frameAnchoring, function(settings, name)
        AddFrameAnchoringDependents(dependents, settings, targetFrameName, name)
    end)

    return dependents
end

function CooldownCompanion:ValidateAddonFrameAnchorTarget(relativeTo, options)
    options = options or {}
    local sourceId = options.sourceId or options.sourceGroupId
    local sourceKind = options.sourceKind or "group"
    if relativeTo == nil or relativeTo == "" or relativeTo == "UIParent" then
        return true, "ui-parent"
    end

    local kind, id = ParseAddonAnchorFrameName(relativeTo)
    if kind == "cursor" then
        if options.allowCursor then
            return true, "cursor"
        end
        return false, "cursor-not-allowed", kind, id
    end

    if kind == "group" then
        if PANEL_ANCHOR_DOMAINS[options.domain] then
            local ok, reason = self:CanGroupBePanelAnchorTarget(id, sourceId)
            if not ok then return false, reason, kind, id end
            return true, "ok", kind, id
        end

        local ok, reason = self:CanGroupBeExternalAnchorTarget(id)
        if not ok then return false, reason, kind, id end
        if sourceId
            and self.WouldCreateCircularAnchor
            and self:WouldCreateCircularAnchor(sourceId, id, "group", sourceKind) then
            return false, "circular", kind, id
        end
        return true, "ok", kind, id
    end

    if kind == "container" then
        if AnchorTargetsCursorRoot(GetProfile(self), relativeTo) then
            return false, "cursor-root-target", kind, id
        end
        if sourceId
            and self.WouldCreateCircularAnchor
            and self:WouldCreateCircularAnchor(sourceId, id, "container", sourceKind) then
            return false, "circular", kind, id
        end
        return true, "ok", kind, id
    end

    if type(relativeTo) == "string" and relativeTo:find("^CooldownCompanion") then
        return false, "addon-frame-unavailable"
    end

    return true, "external"
end

function CooldownCompanion:GetInvalidAnchorTargetReason(relativeTo, options)
    local ok, reason = self:ValidateAddonFrameAnchorTarget(relativeTo, options)
    if ok then return nil end

    if reason == "cursor-root-target" then
        return "Panels anchored to the cursor cannot be anchor targets. Choose Cursor directly instead."
    end
    if reason == "cursor-not-allowed" then
        return "Cursor is not available for this anchor target."
    end
    if reason == "circular" then
        return "Cannot anchor: would create a circular reference."
    end
    if reason == "unsupported-display-mode" then
        return "That panel type cannot be used as this anchor target."
    end
    return "That frame cannot be used as this anchor target."
end

function CooldownCompanion:PrintInvalidAnchorTargetReason(relativeTo, options)
    local message = self:GetInvalidAnchorTargetReason(relativeTo, options)
        or "That frame cannot be used as this anchor target."
    self:Print(message)
end

function CooldownCompanion:GetExternalAnchorFrame(relativeTo)
    if not relativeTo or relativeTo == "" or relativeTo == "UIParent" then
        return UIParent, "ui-parent"
    end

    local ok, reason = self:ValidateAddonFrameAnchorTarget(relativeTo, {
        domain = "external",
    })
    if not ok then
        return UIParent, reason
    end

    return _G[relativeTo] or UIParent, "ok"
end

function CooldownCompanion:SanitizeCursorAnchorPolicy(profile)
    profile = profile or GetProfile(self)
    if type(profile) ~= "table" then
        return
    end

    local targetIsCursorRoot = BuildCursorRootTargetPredicate(profile)

    for groupId, group in pairs(profile.groups or {}) do
        if type(group) == "table" then
            local anchor = group.anchor
            local relativeTo = type(anchor) == "table" and anchor.relativeTo or anchor
            if relativeTo == CURSOR_ANCHOR_TARGET then
                if not group.parentContainerId then
                    group.anchor = BuildRootAnchor("UIParent")
                else
                    group.anchor = NormalizeCursorAnchor(anchor)
                end
            elseif targetIsCursorRoot(relativeTo) then
                if group.parentContainerId then
                    group.anchor = BuildRootAnchor("CooldownCompanionContainer" .. tostring(group.parentContainerId))
                else
                    group.anchor = BuildRootAnchor("UIParent")
                end
            end
        end
    end

    for _, container in pairs(profile.groupContainers or {}) do
        if type(container) == "table" then
            local anchor = container.anchor
            local relativeTo = type(anchor) == "table" and anchor.relativeTo or anchor
            if targetIsCursorRoot(relativeTo) then
                container.anchor = BuildRootAnchor("UIParent")
            end
        end
    end

    SanitizeScopedExternalAnchors(profile, targetIsCursorRoot)
end
