--[[
    CooldownCompanion - Core/GroupOperations.lua: LSM helpers, group visibility/load conditions,
    state toggles, group frame operations, spell/item info utilities
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

-- Localize frequently-used globals for faster access
local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local select = select
local next = next
local type = type
local UnitExists = UnitExists
local UnitCanAttack = UnitCanAttack
local InCombatLockdown = InCombatLockdown
local C_CVar_GetCVarBool = C_CVar.GetCVarBool

local function ClearButtonVisualState(button)
    local clear = ST._ClearButtonVisualState
    if clear then
        clear(button)
    end
end

local function UnregisterKeyPressHighlightFrame(frame)
    local unregisterButton = ST._UnregisterKeyPressHighlightButton
    if not (unregisterButton and frame and frame.buttons) then return end
    for _, button in ipairs(frame.buttons) do
        unregisterButton(button)
    end
end

local function RefreshKeyPressHighlightFrame(frame)
    local cacheButtonBindingKeys = ST._CacheButtonBindingKeys
    local refreshButton = ST._RefreshKeyPressHighlightEnrollment
    if not (frame and frame.buttons) then return end
    if not (cacheButtonBindingKeys or refreshButton) then return end

    for _, button in ipairs(frame.buttons) do
        if cacheButtonBindingKeys then
            cacheButtonBindingKeys(button, button.buttonData)
        else
            refreshButton(button)
        end
    end
end

local LOAD_CONDITION_DEFAULTS = {
    raid = false,
    dungeon = false,
    delve = false,
    battleground = false,
    arena = false,
    openWorld = false,
    rested = false,
    petBattle = true,
    vehicleUI = true,
}

local LOCAL_LOAD_CONDITION_DEFAULTS = {
    raid = false,
    dungeon = false,
    delve = false,
    battleground = false,
    arena = false,
    openWorld = false,
    rested = false,
    petBattle = false,
    vehicleUI = false,
}

local LOAD_CONDITION_ALLOWLIST_KEYS = {
    classAllowlist = true,
    specAllowlist = true,
    characterAllowlist = true,
}

local CLASS_SCAN_LIMIT = 30

local function GetFrameName(frame)
    if not frame then
        return nil
    end
    if frame.GetName then
        return frame:GetName()
    end
    if frame.groupId then
        return "CooldownCompanionGroup" .. frame.groupId
    end
    return frame.name
end

local function NormalizeClassKey(key)
    if type(key) ~= "string" or key == "" then return nil end
    return string.upper(key)
end

local function NormalizeSpecKey(key)
    local specId = tonumber(key)
    if not specId then return nil end
    return specId
end

local function NormalizeCharacterKey(key)
    if type(key) ~= "string" or key == "" then return nil end
    return key
end

local function NormalizeTruthyMap(map, normalizer, failClosed)
    if map == nil then return nil, false, false end
    if type(map) ~= "table" then return nil, true, true end

    local normalized = {}
    local sawEntry = false
    local invalidEnabledEntry = false
    for key, enabled in pairs(map) do
        sawEntry = true
        if enabled == true then
            local normalizedKey = normalizer(key)
            if normalizedKey ~= nil then
                normalized[normalizedKey] = true
            else
                invalidEnabledEntry = true
            end
        end
    end

    if next(normalized) then
        return normalized, false, true
    end
    if invalidEnabledEntry and failClosed then
        return {}, true, true
    end
    if sawEntry and failClosed then
        return {}, false, true
    end
    return nil, false, false
end

local function CopyTruthyMap(map)
    if not map then return nil end
    local copy = {}
    for key in pairs(map) do
        copy[key] = true
    end
    return copy
end

local function IntersectTruthyMaps(left, right)
    local intersection = {}
    for key in pairs(left or {}) do
        if right and right[key] then
            intersection[key] = true
        end
    end
    return intersection
end

local function AddEffectiveSource(sources, map, inherited, normalizer)
    local normalized, malformed, hasRestriction = NormalizeTruthyMap(map, normalizer, true)
    if hasRestriction then
        sources[#sources + 1] = {
            values = normalized or {},
            inherited = inherited and true or false,
            malformed = malformed and true or false,
        }
    end
end

local function AddCombinedEffectiveSource(sources, inherited, normalizer, ...)
    local values
    local hasRestriction = false
    local malformed = false

    for index = 1, select("#", ...) do
        local normalized, sourceMalformed, sourceHasRestriction = NormalizeTruthyMap(select(index, ...), normalizer, true)
        if sourceMalformed then
            malformed = true
        end
        if sourceHasRestriction then
            hasRestriction = true
            values = values or {}
            for key in pairs(normalized or {}) do
                values[key] = true
            end
        end
    end

    if hasRestriction then
        sources[#sources + 1] = {
            values = values,
            inherited = inherited and true or false,
            malformed = malformed,
        }
    end
end

local function ResolveEffectiveSources(sources)
    local effective
    local inherited = false
    local hasRestriction = false

    for _, source in ipairs(sources or {}) do
        hasRestriction = true
        if source.inherited then inherited = true end
        if source.malformed then
            effective = {}
        elseif effective == nil then
            effective = CopyTruthyMap(source.values) or {}
        else
            effective = IntersectTruthyMaps(effective, source.values)
        end
    end

    return effective, inherited, hasRestriction
end

local function AddEntityEffectiveSpecSource(sources, entity, inherited)
    AddCombinedEffectiveSource(
        sources,
        inherited,
        NormalizeSpecKey,
        entity and entity.specs,
        entity and entity.loadConditions and entity.loadConditions.specAllowlist
    )
end

local function AddFolderEffectiveSpecSource(sources, profile, folderId)
    local folders = profile and profile.folders
    local folder = folderId and folders and folders[folderId]
    AddEntityEffectiveSpecSource(sources, folder, true)
end

local function MergeEligibilityAllowlist(state, key, map, normalizer)
    local normalized, malformed, hasRestriction = NormalizeTruthyMap(map, normalizer, true)
    if malformed then
        state[key .. "Restricted"] = true
        state[key .. "NoMatch"] = true
        state[key] = {}
        return false
    end
    if not hasRestriction then return true end

    local restrictedKey = key .. "Restricted"
    state[restrictedKey] = true
    if state[key] == nil then
        state[key] = CopyTruthyMap(normalized) or {}
    else
        state[key] = IntersectTruthyMaps(state[key], normalized)
    end
    return true
end

local function AllowlistMatches(state, key, currentValue)
    if not state[key .. "Restricted"] then return true end
    if state[key .. "NoMatch"] then return false end
    if currentValue == nil then return false end
    return state[key] and state[key][currentValue] == true
end

local function GetCurrentAnchorTargetName(frame)
    if not frame then
        return nil
    end
    if frame.anchoredToParent then
        return GetFrameName(frame.anchoredToParent)
    end
    if frame.GetPoint then
        local _, relativeFrame = frame:GetPoint(1)
        return GetFrameName(relativeFrame)
    end
    return frame.relativeTo
end

local function IsFrameAnchoredToSavedTarget(frame, anchor)
    local relativeTo = type(anchor) == "table" and anchor.relativeTo or nil
    if not relativeTo or relativeTo == "UIParent" then
        return true
    end
    return GetCurrentAnchorTargetName(frame) == relativeTo
end

local function GetPanelAnchorDepth(groups, groupId, visiting)
    visiting = visiting or {}
    if visiting[groupId] then
        return 0
    end
    visiting[groupId] = true

    local group = groups and groups[groupId]
    local anchor = group and group.anchor
    local relativeTo = type(anchor) == "table" and anchor.relativeTo or nil
    local kind, targetGroupId = CooldownCompanion:ParseAddonAnchorFrameName(relativeTo)
    if kind ~= "group" then
        visiting[groupId] = nil
        return 0
    end

    local target = groups[targetGroupId]
    if not (target and target.parentContainerId) then
        visiting[groupId] = nil
        return 0
    end

    local depth = GetPanelAnchorDepth(groups, targetGroupId, visiting) + 1
    visiting[groupId] = nil
    return depth
end

ST.LOAD_CONDITION_OPTIONS = ST.LOAD_CONDITION_OPTIONS or {
    { key = "raid",          label = "Raid" },
    { key = "dungeon",       label = "Dungeon" },
    { key = "delve",         label = "Delve" },
    { key = "battleground",  label = "Battleground" },
    { key = "arena",         label = "Arena" },
    { key = "openWorld",     label = "Open World" },
    { key = "rested",        label = "Rested Area" },
    { key = "petBattle",     label = "Pet Battle", default = true },
    { key = "vehicleUI",     label = "Vehicle / Override UI", default = true },
}

-- LibSharedMedia for font/texture selection
local LSM = LibStub("LibSharedMedia-3.0")

--- Return the per-spec order for a container or folder, falling back to the
--- global .order field and then to the supplied default (typically the ID).
--- @param obj table  groupContainer or folder table with optional specOrders
--- @param specId number|nil  current specialization ID
--- @param default number|nil  fallback when no order exists
function CooldownCompanion:GetOrderForSpec(obj, specId, default)
    if obj.specOrders and specId then
        local so = obj.specOrders[specId]
        if so then return so end
    end
    return obj.order or default
end

--- Write a per-spec order value to a container or folder.
--- Creates the specOrders table if it doesn't exist.
function CooldownCompanion:SetOrderForSpec(obj, specId, value)
    if not specId then
        obj.order = value
        return
    end
    if not obj.specOrders then obj.specOrders = {} end
    obj.specOrders[specId] = value
end

function CooldownCompanion:FetchFont(name)
    local effectiveName = ST.GetEffectiveFontName and ST.GetEffectiveFontName(name) or name
    if effectiveName and (not LSM.IsValid or LSM:IsValid("font", effectiveName)) then
        local font = LSM:Fetch("font", effectiveName)
        if font then
            return font
        end
    end
    return LSM:Fetch("font", ST.DEFAULT_FONT_NAME or "Friz Quadrata TT") or STANDARD_TEXT_FONT
end

function CooldownCompanion:FetchStatusBar(name)
    return LSM:Fetch("statusbar", name) or LSM:Fetch("statusbar", "Solid") or [[Interface\BUTTONS\WHITE8X8]]
end

function CooldownCompanion:FetchEffectiveBarTexture(name)
    local effectiveName = ST.GetEffectiveBarTextureName and ST.GetEffectiveBarTextureName(name) or name
    return self:FetchStatusBar(effectiveName)
end

-- Re-apply all media after a SharedMedia pack registers new fonts/textures
function CooldownCompanion:RefreshAllMedia()
    -- SharedMedia registrations from other addons can fire during startup before
    -- the aura texture runtime has finished attaching its visual methods.
    if type(self.UpdateAuraTextureVisual) ~= "function"
        or type(self.HideAuraTextureVisual) ~= "function" then
        return
    end

    self:RefreshAllGroups()
    self:EvaluateBarsAndFramesRuntime("shared-media")
end

local function RefreshProfileWideVisuals(addon, reason, opts, refreshAuraTextures)
    if addon.RefreshAllGroups then
        addon:RefreshAllGroups()
    end
    if addon.EvaluateBarsAndFramesRuntime then
        addon:EvaluateBarsAndFramesRuntime(reason)
    end
    if refreshAuraTextures ~= false and addon.RefreshAllAuraTextureVisuals then
        addon:RefreshAllAuraTextureVisuals()
    end
    if not opts or opts.refreshConfig ~= false then
        if addon.RefreshConfigPanel then
            addon:RefreshConfigPanel()
        end
    end
end

function CooldownCompanion:ApplyProfileOnePixelBorderMode(opts)
    RefreshProfileWideVisuals(self, "profile-border-mode", opts)
end

function CooldownCompanion:SetProfileOnePixelBordersEnabled(enabled, opts)
    local profile = self.db and self.db.profile
    if not profile then return false end
    profile.profileOnePixelBorders = enabled == true
    self:ApplyProfileOnePixelBorderMode(opts)
    return true
end

function CooldownCompanion:ApplyProfileWideFontMode(opts)
    RefreshProfileWideVisuals(self, "profile-font-mode", opts)
end

local function InitializeProfileWideFontDefaults(profile)
    local initialized = false
    if type(profile.profileWideFontName) ~= "string" or profile.profileWideFontName == "" then
        profile.profileWideFontName = ST.DEFAULT_FONT_NAME or "Friz Quadrata TT"
        initialized = true
    end
    if type(profile.profileWideFontOutline) ~= "string" then
        profile.profileWideFontOutline = ST.DEFAULT_FONT_OUTLINE or "OUTLINE"
        initialized = true
    end
    return initialized
end

function CooldownCompanion:SetProfileWideFontEnabled(enabled, opts)
    local profile = self.db and self.db.profile
    if not profile then return false end

    local target = enabled == true
    local changed = profile.profileWideFontEnabled ~= target
    profile.profileWideFontEnabled = target

    local initialized = target and InitializeProfileWideFontDefaults(profile)

    if changed or initialized then
        self:ApplyProfileWideFontMode(opts)
    end
    return true
end

function CooldownCompanion:SetProfileWideFontName(fontName, opts)
    local profile = self.db and self.db.profile
    if not profile or type(fontName) ~= "string" or fontName == "" then
        return false
    end

    local changed = profile.profileWideFontName ~= fontName
    if changed then
        profile.profileWideFontName = fontName
    end

    local enableChanged = false
    if opts and opts.enable == true and profile.profileWideFontEnabled ~= true then
        profile.profileWideFontEnabled = true
        enableChanged = true
        InitializeProfileWideFontDefaults(profile)
    end

    if changed or enableChanged then
        self:ApplyProfileWideFontMode(opts)
    end
    return true
end

function CooldownCompanion:SetProfileWideFontOutline(outline, opts)
    local profile = self.db and self.db.profile
    if not profile or type(outline) ~= "string" then
        return false
    end
    outline = ST.NormalizeFontOutline(outline)

    local changed = profile.profileWideFontOutline ~= outline
    if changed then
        profile.profileWideFontOutline = outline
    end

    local enableChanged = false
    if opts and opts.enable == true and profile.profileWideFontEnabled ~= true then
        profile.profileWideFontEnabled = true
        enableChanged = true
        InitializeProfileWideFontDefaults(profile)
    end

    if changed or enableChanged then
        self:ApplyProfileWideFontMode(opts)
    end
    return true
end

function CooldownCompanion:ApplyProfileWideBarTextureMode(opts)
    RefreshProfileWideVisuals(self, "profile-bar-texture-mode", opts, false)
end

local function InitializeProfileWideBarTextureDefaults(profile)
    if type(profile.profileWideBarTextureName) ~= "string" or profile.profileWideBarTextureName == "" then
        profile.profileWideBarTextureName = "Solid"
        return true
    end
    return false
end

function CooldownCompanion:SetProfileWideBarTextureEnabled(enabled, opts)
    local profile = self.db and self.db.profile
    if not profile then return false end

    local target = enabled == true
    local changed = profile.profileWideBarTextureEnabled ~= target
    profile.profileWideBarTextureEnabled = target

    local initialized = target and InitializeProfileWideBarTextureDefaults(profile)

    if changed or initialized then
        self:ApplyProfileWideBarTextureMode(opts)
    end
    return true
end

function CooldownCompanion:SetProfileWideBarTextureName(textureName, opts)
    local profile = self.db and self.db.profile
    if not profile or type(textureName) ~= "string" or textureName == "" then
        return false
    end

    local changed = profile.profileWideBarTextureName ~= textureName
    if changed then
        profile.profileWideBarTextureName = textureName
    end

    local enableChanged = false
    if opts and opts.enable == true and profile.profileWideBarTextureEnabled ~= true then
        profile.profileWideBarTextureEnabled = true
        enableChanged = true
        InitializeProfileWideBarTextureDefaults(profile)
    end

    if changed or enableChanged then
        self:ApplyProfileWideBarTextureMode(opts)
    end
    return true
end

function CooldownCompanion:ClearUnsupportedProfileRuntime()
    if InCombatLockdown() then
        self._pendingUnsupportedLegacyHide = true
        return
    end

    self._pendingUnsupportedLegacyHide = nil

    local activeGroupIds = {}
    for groupId in pairs(self.groupFrames or {}) do
        activeGroupIds[#activeGroupIds + 1] = groupId
    end
    for _, groupId in ipairs(activeGroupIds) do
        self:UnloadGroup(groupId)
    end

    for containerId, frame in pairs(self.containerFrames or {}) do
        frame:Hide()
        self.containerFrames[containerId] = nil
    end

    for _, frame in pairs(self._dormantFrames or {}) do
        frame:Hide()
    end

    if self.RevertResourceBars then
        self:RevertResourceBars()
    end
    if self.RevertCastBar then
        self:RevertCastBar()
    end
end

function CooldownCompanion:IsGroupVisibleToCurrentChar(groupId)
    local group = self.db.profile.groups[groupId]
    if not group then return false end

    -- For panels, delegate visibility to the parent container
    if group.parentContainerId then
        return self:IsContainerVisibleToCurrentChar(group.parentContainerId)
    end

    -- Legacy path (no container)
    local scope = self:ResolveProfileEntityClassScope(group, {
        isGlobal = group.isGlobal == true,
    })
    return scope.runtimeVisible == true
end

-- Resolve the container for a panel group, or nil if the group has no container.
function CooldownCompanion:GetParentContainer(groupOrGroupId)
    local group = groupOrGroupId
    if type(groupOrGroupId) == "number" then
        group = self.db.profile.groups[groupOrGroupId]
    end
    if not group or not group.parentContainerId then return nil end
    local containers = self.db.profile.groupContainers
    return containers and containers[group.parentContainerId]
end

function CooldownCompanion:IsContainerUnlockPreviewActive(containerOrContainerId)
    local container = containerOrContainerId
    local containerId = nil

    if self._combatForcedLock then
        return false
    end

    if type(containerOrContainerId) == "number" then
        containerId = containerOrContainerId
        container = self.db.profile.groupContainers and self.db.profile.groupContainers[containerId]
    elseif type(containerOrContainerId) == "table" then
        for id, candidate in pairs(self.db.profile.groupContainers or {}) do
            if candidate == containerOrContainerId then
                containerId = id
                break
            end
        end
    end

    if not container then
        return false
    end
    if container.locked ~= false then
        return false
    end
    if containerId and not self:IsContainerVisibleToCurrentChar(containerId) then
        return false
    end

    return true
end

local function ForceCombatMouseLock(frame)
    if not frame then
        return
    end

    local canChangeProtectedState = not frame.CanChangeProtectedState or frame:CanChangeProtectedState()
    if frame.EnableMouse and canChangeProtectedState then
        frame:EnableMouse(false)
    end
    if frame.SetMouseClickEnabled and canChangeProtectedState then
        frame:SetMouseClickEnabled(false)
    end
    if frame.SetMouseMotionEnabled and canChangeProtectedState then
        frame:SetMouseMotionEnabled(false)
    end
end

local function CanSafelyChangeFrameVisibility(frame)
    if not frame then
        return false
    end
    if not InCombatLockdown() then
        return true
    end
    if frame.CanChangeProtectedState then
        return frame:CanChangeProtectedState()
    end
    return not (frame.IsProtected and frame:IsProtected())
end

local function SuppressFrameVisibilityForCombat(frame)
    if not frame then
        return
    end

    if CanSafelyChangeFrameVisibility(frame) then
        frame:Hide()
        return
    end

    if frame.GetAlpha and frame._combatForcedAlpha == nil then
        frame._combatForcedAlpha = frame:GetAlpha()
    end
    if frame.SetAlpha then
        frame:SetAlpha(0)
    end
end

local function RestoreFrameVisibilityAfterCombat(frame)
    if not frame then
        return
    end

    if frame._combatForcedAlpha ~= nil and frame.SetAlpha then
        frame:SetAlpha(frame._combatForcedAlpha)
    end
    frame._combatForcedAlpha = nil
end

function CooldownCompanion:BeginCombatForcedLock()
    if self._combatForcedLock then
        return false
    end

    local snapshot = {
        containers = {},
        groups = {},
        hadUnlocked = false,
    }

    for containerId, container in pairs(self.db.profile.groupContainers or {}) do
        if container
            and container.locked == false
            and self:IsContainerVisibleToCurrentChar(containerId)
        then
            snapshot.containers[containerId] = true
            snapshot.hadUnlocked = true
        end
    end

    for groupId, group in pairs(self.db.profile.groups or {}) do
        if group
            and group.locked == false
            and not (self.IsGroupCursorAnchored and self:IsGroupCursorAnchored(group))
            and self:IsGroupVisibleToCurrentChar(groupId)
        then
            snapshot.groups[groupId] = true
            snapshot.hadUnlocked = true
        end
    end

    self._combatForcedLock = true
    self._combatForcedLockSnapshot = snapshot

    for groupId, frame in pairs(self.groupFrames or {}) do
        local group = self.db and self.db.profile and self.db.profile.groups and self.db.profile.groups[groupId]
        local active = group and self:IsGroupActive(groupId, {
            group = group,
            checkCharVisibility = true,
            checkLoadConditions = true,
            requireButtons = true,
        }) or false

        if frame._dragInProgress then
            frame._dragCancelPending = true
            if not frame:IsProtected() then
                frame:StopMovingOrSizing()
            end
            frame._dragInProgress = nil
        end
        frame._combatForcedHidden = not active or nil
        SuppressFrameVisibilityForCombat(frame.dragHandle)
        SuppressFrameVisibilityForCombat(frame.coordLabel)
        SuppressFrameVisibilityForCombat(frame.dragHelpButton)
        SuppressFrameVisibilityForCombat(frame.nudger)
        ForceCombatMouseLock(frame)
        ForceCombatMouseLock(frame.dragHandle)
        ForceCombatMouseLock(frame.dragHelpButton)
        ForceCombatMouseLock(frame.nudger)
        for _, button in ipairs(frame.buttons or {}) do
            local host = button and button.auraTextureHost or nil
            if host then
                if host._isDragging then
                    host._dragCancelPending = true
                    if not host:IsProtected() then
                        host:StopMovingOrSizing()
                    end
                    host._isDragging = nil
                end
                host._dragEnabled = false
                ForceCombatMouseLock(host)
                SuppressFrameVisibilityForCombat(host.dragHandle)
                SuppressFrameVisibilityForCombat(host.coordLabel)
                SuppressFrameVisibilityForCombat(host.dragHelpButton)
                SuppressFrameVisibilityForCombat(host.nudger)
                ForceCombatMouseLock(host.dragHelpButton)
                if host.auraTextureOutlineFill then
                    host.auraTextureOutlineFill:Hide()
                end
                for _, edge in ipairs(host.auraTextureOutlineEdges or {}) do
                    edge:Hide()
                end
            end
            if not active and self.HideAuraTextureVisual then
                self:HideAuraTextureVisual(button)
            end
        end

        if active then
            local frameAlpha = (group and group.baselineAlpha) or 1
            frameAlpha = self:GetPanelCurrentAlphaValue(groupId, group)
            frame:SetAlpha(frameAlpha)
        elseif frame:IsProtected() then
            frame:SetAlpha(0)
        else
            frame:Hide()
        end
    end

    if self.containerFrames then
        for containerId, frame in pairs(self.containerFrames) do
            if frame._dragInProgress then
                frame._dragCancelPending = true
                if not frame:IsProtected() then
                    frame:StopMovingOrSizing()
                end
                frame._dragInProgress = nil
            end
            self:UpdateContainerDragHandle(containerId, true)
        end
    end

    return snapshot.hadUnlocked
end

function CooldownCompanion:EndCombatForcedLock()
    if not self._combatForcedLock then
        return nil
    end

    local snapshot = self._combatForcedLockSnapshot
    self._combatForcedLock = nil
    self._combatForcedLockSnapshot = nil

    for _, frame in pairs(self.groupFrames or {}) do
        frame._combatForcedHidden = nil
        RestoreFrameVisibilityAfterCombat(frame.dragHandle)
        RestoreFrameVisibilityAfterCombat(frame.coordLabel)
        RestoreFrameVisibilityAfterCombat(frame.dragHelpButton)
        RestoreFrameVisibilityAfterCombat(frame.nudger)
        for _, button in ipairs(frame.buttons or {}) do
            local host = button and button.auraTextureHost or nil
            RestoreFrameVisibilityAfterCombat(host and host.dragHandle or nil)
            RestoreFrameVisibilityAfterCombat(host and host.coordLabel or nil)
            RestoreFrameVisibilityAfterCombat(host and host.dragHelpButton or nil)
            RestoreFrameVisibilityAfterCombat(host and host.nudger or nil)
        end
    end

    for _, frame in pairs(self.containerFrames or {}) do
        RestoreFrameVisibilityAfterCombat(frame.dragHandle)
        RestoreFrameVisibilityAfterCombat(frame.dragHandle and frame.dragHandle.header or nil)
        RestoreFrameVisibilityAfterCombat(frame.coordLabel)
        RestoreFrameVisibilityAfterCombat(frame.nudger)
        for _, label in pairs(frame._containerPanelLabels or {}) do
            RestoreFrameVisibilityAfterCombat(label)
        end
    end

    return snapshot
end

function CooldownCompanion:IsGroupVisibleInUnlockPreview(groupId, opts)
    opts = opts or {}

    local group = opts.group or self.db.profile.groups[groupId]
    if not (group and group.parentContainerId) then
        return false
    end

    local container = opts.container or self:GetParentContainer(group)
    if not self:IsContainerUnlockPreviewActive(container) then
        return false
    end

    local isRotationAssistant = self:IsRotationAssistantGroup(group)
    if not isRotationAssistant and not (group.buttons and #group.buttons > 0) then
        return false
    end

    local groupFrame = opts.groupFrame
    if groupFrame == nil and groupId then
        groupFrame = self.groupFrames and self.groupFrames[groupId] or nil
    end
    if groupFrame and not isRotationAssistant and (not groupFrame.buttons or #groupFrame.buttons == 0) then
        return false
    end

    local checkCharVisibility = opts.checkCharVisibility
    if checkCharVisibility == nil then
        checkCharVisibility = true
    end
    if checkCharVisibility and groupId and not self:IsGroupVisibleToCurrentChar(groupId) then
        return false
    end

    if self.IsGroupEligibilityMet and not self:IsGroupEligibilityMet(group) then
        return false
    end

    local effectiveSpecs, _, hasSpecFilter = self:GetEffectiveSpecs(group)
    if hasSpecFilter then
        if not (self._currentSpecId and effectiveSpecs[self._currentSpecId]) then
            return false
        end
    end

    return true
end

function CooldownCompanion:GetContainerUnlockPreviewPanels(containerId, panels)
    local previewPanels = {}
    local panelList = panels or self:GetPanels(containerId)
    for _, panelInfo in ipairs(panelList) do
        if not self:IsGroupSuppressedForOtherClassBrowse(panelInfo.groupId, panelInfo.group)
            and self:IsGroupVisibleInUnlockPreview(panelInfo.groupId, {
                group = panelInfo.group,
                checkCharVisibility = true,
            }) then
            previewPanels[#previewPanels + 1] = panelInfo
        end
    end
    return previewPanels
end

function CooldownCompanion:GetEffectiveSpecs(group)
    if not group then return nil, false end

    local sources = {}
    local profile = self.db and self.db.profile

    local container = self:GetParentContainer(group)
    if container then
        AddFolderEffectiveSpecSource(sources, profile, container.folderId)
        AddEntityEffectiveSpecSource(sources, container, true)
        AddEntityEffectiveSpecSource(sources, group, false)
    else
        AddFolderEffectiveSpecSource(sources, profile, group.folderId)
        AddEntityEffectiveSpecSource(sources, group, false)
    end

    return ResolveEffectiveSources(sources)
end

function CooldownCompanion:GetInheritedEffectiveSpecs(group)
    if not group then return nil, false end

    local sources = {}
    local profile = self.db and self.db.profile

    local container = self:GetParentContainer(group)
    if container then
        AddFolderEffectiveSpecSource(sources, profile, container.folderId)
        AddEntityEffectiveSpecSource(sources, container, true)
    else
        AddFolderEffectiveSpecSource(sources, profile, group.folderId)
    end

    return ResolveEffectiveSources(sources)
end

function CooldownCompanion:GetEffectiveHeroTalents(group)
    if not group then return nil, false end

    local sources = {}

    local container = self:GetParentContainer(group)
    if container then
        local folderId = container.folderId
        if folderId then
            local folders = self.db and self.db.profile and self.db.profile.folders
            local folder = folders and folders[folderId]
            AddEffectiveSource(sources, folder and folder.heroTalents, true, NormalizeSpecKey)
        end
        AddEffectiveSource(sources, container.heroTalents, true, NormalizeSpecKey)
        AddEffectiveSource(sources, group.heroTalents, false, NormalizeSpecKey)
    else
        local folderId = group.folderId
        if folderId then
            local folders = self.db and self.db.profile and self.db.profile.folders
            local folder = folders and folders[folderId]
            AddEffectiveSource(sources, folder and folder.heroTalents, true, NormalizeSpecKey)
        end
        AddEffectiveSource(sources, group.heroTalents, false, NormalizeSpecKey)
    end

    return ResolveEffectiveSources(sources)
end

local function CopyTalentCondition(cond)
    return {
        nodeID = cond.nodeID,
        entryID = cond.entryID,
        spellID = cond.spellID,
        name = cond.name,
        show = cond.show or "taken",
        classID = cond.classID,
        className = cond.className,
        specID = cond.specID,
        specName = cond.specName,
        heroSubTreeID = cond.heroSubTreeID,
        heroName = cond.heroName,
    }
end

local function IsLegacyChoiceRowCondition(cond)
    return type(cond) == "table"
        and cond.entryID == nil
        and cond.spellID == nil
        and type(cond.name) == "string"
        and cond.name:sub(1, 12) == "Choice row: "
end

function CooldownCompanion:NormalizeTalentConditions(conditions)
    if type(conditions) ~= "table" then return nil, false end

    local grouped = {}
    local orderedGroupKeys = {}
    local passthrough = {}
    local hasDuplicateNode = false
    local hasLegacyChoiceRow = false
    local hasUnscopedNodeCondition = false
    local scopedSpecIDs = {}
    local scopedHeroIDs = {}
    local scopedSpecCount = 0
    local scopedHeroCount = 0

    for _, cond in ipairs(conditions) do
        if type(cond) == "table" and cond.nodeID then
            if IsLegacyChoiceRowCondition(cond) then
                hasLegacyChoiceRow = true
            end
            if not cond.specID and not cond.classID and not cond.className then
                hasUnscopedNodeCondition = true
            end
            if cond.specID and not scopedSpecIDs[cond.specID] then
                scopedSpecIDs[cond.specID] = true
                scopedSpecCount = scopedSpecCount + 1
            end
            if cond.heroSubTreeID and not scopedHeroIDs[cond.heroSubTreeID] then
                scopedHeroIDs[cond.heroSubTreeID] = true
                scopedHeroCount = scopedHeroCount + 1
            end

            local groupKey = tostring(cond.nodeID)
                .. "|" .. tostring(cond.classID or 0)
                .. "|" .. tostring(cond.specID or 0)
                .. "|" .. tostring(cond.heroSubTreeID or 0)
            local group = grouped[groupKey]
            if not group then
                group = {}
                grouped[groupKey] = group
                orderedGroupKeys[#orderedGroupKeys + 1] = groupKey
            else
                hasDuplicateNode = true
            end
            group[#group + 1] = cond
        else
            passthrough[#passthrough + 1] = cond
        end
    end

    if not hasDuplicateNode
        and not hasLegacyChoiceRow
        and scopedSpecCount <= 1
        and scopedHeroCount <= 1
        and not (scopedSpecCount > 0 and hasUnscopedNodeCondition)
    then
        return conditions, false
    end

    local normalized = {}
    for _, cond in ipairs(passthrough) do
        normalized[#normalized + 1] = cond
    end

    for _, groupKey in ipairs(orderedGroupKeys) do
        local group = grouped[groupKey]
        if group and #group > 0 then
            local firstCondition = nil
            local firstSpecific = nil
            local takenCount = 0
            local seenEntries = {}
            local takenCondition = nil
            local uniqueEntryCount = 0
            local specificCount = 0

            for _, cond in ipairs(group) do
                if not firstCondition and not IsLegacyChoiceRowCondition(cond) then
                    firstCondition = cond
                end

                if cond.entryID ~= nil then
                    if not firstSpecific then
                        firstSpecific = cond
                    end
                    specificCount = specificCount + 1
                    if not seenEntries[cond.entryID] then
                        seenEntries[cond.entryID] = true
                        uniqueEntryCount = uniqueEntryCount + 1
                    end

                    if (cond.show or "taken") == "not_taken" then
                        -- no-op
                    else
                        takenCount = takenCount + 1
                        takenCondition = cond
                    end
                end
            end

            local resolved
            if specificCount > 1 and specificCount == uniqueEntryCount and uniqueEntryCount > 1 then
                if takenCount == 1 then
                    resolved = CopyTalentCondition(takenCondition)
                else
                    resolved = CopyTalentCondition(firstSpecific)
                end
            end

            if not resolved then
                local fallback = firstSpecific or firstCondition
                if fallback then
                    resolved = CopyTalentCondition(fallback)
                end
            end

            if resolved then
                normalized[#normalized + 1] = resolved
            end
        end
    end

    local chosenSpecID = nil
    for _, cond in ipairs(normalized) do
        if type(cond) == "table" and cond.nodeID and cond.specID then
            chosenSpecID = cond.specID
            break
        end
    end
    if chosenSpecID then
        local filtered = {}
        for _, cond in ipairs(normalized) do
            if type(cond) == "table" and cond.nodeID then
                if cond.classID or cond.className or cond.specID == chosenSpecID then
                    filtered[#filtered + 1] = cond
                end
            else
                filtered[#filtered + 1] = cond
            end
        end
        normalized = filtered
    end

    local chosenHeroSubTreeID = nil
    for _, cond in ipairs(normalized) do
        if type(cond) == "table" and cond.nodeID and cond.heroSubTreeID then
            chosenHeroSubTreeID = cond.heroSubTreeID
            break
        end
    end
    if chosenHeroSubTreeID then
        local filtered = {}
        for _, cond in ipairs(normalized) do
            if type(cond) == "table" and cond.nodeID then
                if not cond.heroSubTreeID or cond.heroSubTreeID == chosenHeroSubTreeID then
                    filtered[#filtered + 1] = cond
                end
            else
                filtered[#filtered + 1] = cond
            end
        end
        normalized = filtered
    end

    if #normalized == 0 then
        return nil, true
    end
    return normalized, true
end

-- Folder spec filters are stamped onto child containers so that runtime checks
-- (which read container.specs) pick up folder-level restrictions. Stamping occurs
-- both here (when folder specs change) and in MoveGroupToFolder (when a container
-- joins a folder). Hero talents are NOT stamped — they cascade at read time via
-- GetEffectiveHeroTalents.
function CooldownCompanion:ApplyFolderSpecFilterToChildren(folderId)
    local db = self.db and self.db.profile
    local folder = db and db.folders and db.folders[folderId]
    if not (db and folder) then return end

    local folderSpecs = folder.specs
    local hasFolderSpecs = folderSpecs and next(folderSpecs)

    -- Post-migration: folderId lives on containers, not groups
    local containers = db.groupContainers or {}
    for _, container in pairs(containers) do
        if container.folderId == folderId then
            if hasFolderSpecs then
                container.specs = CopyTable(folderSpecs)
            else
                container.specs = nil
            end
        end
    end
end

function CooldownCompanion:IsHeroTalentAllowed(group)
    local effectiveHeroTalents, _, hasHeroTalentFilter = self:GetEffectiveHeroTalents(group)
    if not hasHeroTalentFilter then return true end
    local heroSpecId = self._currentHeroSpecId
    if not heroSpecId then return true end  -- low level, no hero talent selected
    return effectiveHeroTalents[heroSpecId] == true
end

function CooldownCompanion:GroupHasUsableButtons(group, opts)
    opts = opts or {}
    if self:IsRotationAssistantGroup(group) then
        if opts.checkLoadConditions == false then
            return true
        end
        local entrySettings = self:GetRotationAssistantEntrySettings(group, false)
        return self:IsButtonLoadConditionMet(entrySettings or {}, group)
    end
    if not (group and group.buttons and #group.buttons > 0) then
        return false
    end
    for _, buttonData in ipairs(group.buttons) do
        if self:IsButtonUsable(buttonData, group, opts) then
            return true
        end
    end
    return false
end

function CooldownCompanion:GetGroupLayoutButtonCount(groupId, group, opts)
    opts = opts or {}
    if self:IsRotationAssistantGroup(group) then
        return 1
    end

    if not (group and group.buttons and #group.buttons > 0) then
        return 0
    end

    local buttonUsabilityOptions = opts.buttonUsabilityOptions
    if not buttonUsabilityOptions
        and opts.allowConfigPreviewButtonUsability
        and self.GetGroupLayoutButtonUsabilityOptions then
        buttonUsabilityOptions = self:GetGroupLayoutButtonUsabilityOptions(groupId, group)
    end

    local count = 0
    for sourceIndex, buttonData in ipairs(group.buttons) do
        if self:IsButtonInConfigPreviewScope(groupId, sourceIndex, buttonUsabilityOptions)
            and self:IsButtonUsable(buttonData, group, buttonUsabilityOptions) then
            count = count + 1
        end
    end
    return count
end

local CONFIG_PREVIEW_BUTTON_USABILITY_OPTIONS = {
    checkLoadConditions = false,
    ignoreSpellAvailability = true,
    ignoreItemAvailability = true,
    ignoreTalentConditions = true,
    configPreview = true,
    selectionDrivenConfigPreview = true,
}

local function IsGroupEnabledForConfigPreview(addon, group)
    if not group then return false end

    local container = addon:GetParentContainer(group)
    if container then
        if container.enabled == false or group.enabled == false then return false end
    elseif group.enabled == false then
        return false
    end

    if group.parentContainerId then
        if not addon.ResolveContainerClassScope then
            return false
        end
        local scope = addon:ResolveContainerClassScope(group.parentContainerId)
        if not scope or scope.isInvalid == true then
            return false
        end
    end

    return true
end

local function IsConfigSelectionPreviewShown()
    local CS = ST and ST._configState
    local configFrame = CS and CS.configFrame
    local frame = configFrame and configFrame.frame
    if not (frame and frame.IsShown and frame:IsShown()) then
        return nil
    end
    return CS
end

local function IsSelectionDrivenConfigPreviewScope(addon, groupId, sourceIndex)
    local CS = IsConfigSelectionPreviewShown()
    if not CS then
        return false
    end

    if CS.selectedGroup == groupId then
        if not sourceIndex then
            return true
        end
        if CS.selectedButton then
            return CS.selectedButton == sourceIndex
        end
        if CS.selectedButtons and next(CS.selectedButtons) then
            return CS.selectedButtons[sourceIndex] or false
        end
        return true
    end

    if CS.selectedPanels and CS.selectedPanels[groupId] then
        return true
    end

    if CS.selectedContainer and not CS.selectedGroup
        and not (CS.selectedPanels and next(CS.selectedPanels)) then
        local db = addon.db
        local group = db and db.profile and db.profile.groups and db.profile.groups[groupId]
        if group and group.parentContainerId == CS.selectedContainer then
            return true
        end
    end

    return false
end

function CooldownCompanion:IsButtonInConfigPreviewScope(groupId, sourceIndex, opts)
    if not (opts and opts.configPreview) then
        return true
    end
    if opts.selectionDrivenConfigPreview then
        return IsSelectionDrivenConfigPreviewScope(self, groupId, sourceIndex) == true
    end
    if not ST.IsConfigButtonForceVisible then
        return true
    end

    local previewButton = {
        _groupId = groupId,
        index = sourceIndex,
    }
    return ST.IsConfigButtonForceVisible(previewButton) == true
end

local function GroupHasConfigPreviewButtons(addon, groupId, group)
    return addon:GetGroupLayoutButtonCount(groupId, group, {
        buttonUsabilityOptions = CONFIG_PREVIEW_BUTTON_USABILITY_OPTIONS,
    }) > 0
end

function CooldownCompanion:GetGroupButtonUsabilityOptions(groupId, group)
    if not (groupId and IsSelectionDrivenConfigPreviewScope(self, groupId)) then
        return nil
    end

    local db = self.db and self.db.profile
    group = group or (db and db.groups and db.groups[groupId])
    if not IsGroupEnabledForConfigPreview(self, group) then
        return nil
    end

    if not GroupHasConfigPreviewButtons(self, groupId, group) then
        return nil
    end

    return CONFIG_PREVIEW_BUTTON_USABILITY_OPTIONS
end

function CooldownCompanion:GetGroupLayoutButtonUsabilityOptions(groupId, group)
    return self:GetGroupButtonUsabilityOptions(groupId, group)
end

function CooldownCompanion:IsGroupActive(groupId, opts)
    opts = opts or {}
    local db = self.db and self.db.profile
    local group = opts.group or (db and db.groups and db.groups[groupId])
    if not group then return false end

    -- If this panel has a parent container, check container-level state first
    local container = self:GetParentContainer(group)
    if container and self:IsContainerUnlockPreviewActive(container) then
        return self:IsGroupVisibleInUnlockPreview(groupId, {
            group = group,
            container = container,
            checkCharVisibility = opts.checkCharVisibility,
        })
    end
    if container then
        if container.enabled == false then return false end
        if group.enabled == false then return false end

    else
        -- Legacy path: enabled lives on the group
        if group.enabled == false then return false end
    end

    -- Spec and hero talent filtering (GetEffectiveSpecs already delegates to container)
    local effectiveSpecs, _, hasSpecFilter = self:GetEffectiveSpecs(group)
    if hasSpecFilter then
        if not (self._currentSpecId and effectiveSpecs[self._currentSpecId]) then
            return false
        end
    end

    if not self:IsHeroTalentAllowed(group) then return false end

    local checkCharVisibility = opts.checkCharVisibility
    if checkCharVisibility == nil then checkCharVisibility = true end
    if checkCharVisibility and groupId and not self:IsGroupVisibleToCurrentChar(groupId) then
        return false
    end

    if opts.checkLoadConditions ~= false then
        if not self:IsGroupLoadConditionMet(group) then
            return false
        end
    end

    local buttonUsabilityOptions = opts.buttonUsabilityOptions
    if not buttonUsabilityOptions
        and opts.allowConfigPreviewButtonUsability
        and self.GetGroupButtonUsabilityOptions then
        buttonUsabilityOptions = self:GetGroupButtonUsabilityOptions(groupId, group)
    end

    if opts.requireButtons and not self:GroupHasUsableButtons(group, {
        checkLoadConditions = opts.checkLoadConditions,
        ignoreSpellAvailability = buttonUsabilityOptions and buttonUsabilityOptions.ignoreSpellAvailability,
        ignoreItemAvailability = buttonUsabilityOptions and buttonUsabilityOptions.ignoreItemAvailability,
        ignoreTalentConditions = buttonUsabilityOptions and buttonUsabilityOptions.ignoreTalentConditions,
    }) then
        return false
    end

    return true
end

function CooldownCompanion:IsGroupEligibleForConfigPreview(groupId, opts)
    opts = opts or {}
    if not (groupId and IsSelectionDrivenConfigPreviewScope(self, groupId)) then
        return false
    end

    local db = self.db and self.db.profile
    local group = opts.group or (db and db.groups and db.groups[groupId])
    if not IsGroupEnabledForConfigPreview(self, group) then
        return false
    end

    return GroupHasConfigPreviewButtons(self, groupId, group)
end

local function BuildConfigPreviewEligibility(addon)
    local groups = addon.db and addon.db.profile and addon.db.profile.groups
    if not groups then
        return nil, nil
    end

    local containerIds
    local groupIds
    for groupId, group in pairs(groups) do
        local containerId = group and group.parentContainerId
        if containerId and addon:IsGroupEligibleForConfigPreview(groupId, {
            group = group,
        }) then
            containerIds = containerIds or {}
            containerIds[containerId] = true
            groupIds = groupIds or {}
            groupIds[groupId] = true
        end
    end
    return containerIds, groupIds
end

local function EnsureConfigPreviewContainerFrame(addon, group, previewEligible)
    if not (previewEligible and group and group.parentContainerId and addon.containerFrames) then
        return
    end
    if InCombatLockdown() then
        addon._pendingVisibilityRefresh = true
        return
    end

    local containerFrame = addon.containerFrames[group.parentContainerId]
    if containerFrame then
        containerFrame:Show()
    elseif addon.CreateContainerFrame then
        addon:CreateContainerFrame(group.parentContainerId)
    end
end

local function CleanupInactiveConfigPreviewContainerFrames(addon)
    if not addon.containerFrames then
        return false
    end

    local previewContainerIds = BuildConfigPreviewEligibility(addon)
    local cleaned = false
    for containerId, frame in pairs(addon.containerFrames) do
        if frame
            and not addon:IsContainerVisibleToCurrentChar(containerId)
            and not (previewContainerIds and previewContainerIds[containerId]) then
            if InCombatLockdown() and frame.IsProtected and frame:IsProtected() then
                addon._pendingVisibilityRefresh = true
            else
                if addon.ClearContainerUnlockState then
                    addon:ClearContainerUnlockState(containerId)
                end
                local wasShown = not frame.IsShown or frame:IsShown()
                frame:Hide()
                cleaned = cleaned or wasShown
            end
        end
    end
    return cleaned
end

local function IsConfigFrameShown()
    local configState = ST and ST._configState
    local frame = configState and configState.configFrame and configState.configFrame.frame
    return frame and frame.IsShown and frame:IsShown()
end

function CooldownCompanion:IsGroupSuppressedForOtherClassBrowse(groupId, group)
    local configState = ST and ST._configState
    if not (configState
        and configState.otherClassLibraryActive == true
        and configState.hideActiveCurrentClassPanels == true
        and IsConfigFrameShown()) then
        return false
    end

    local db = self.db and self.db.profile
    group = group or (db and db.groups and db.groups[groupId])
    if not group then
        return false
    end

    local visibleToCurrentChar = self:IsGroupVisibleToCurrentChar(groupId)
    if not visibleToCurrentChar then
        return false
    end

    local frame = self.groupFrames and self.groupFrames[groupId]
    if frame and frame.IsShown and frame:IsShown() then
        return true
    end

    return self:IsGroupActive(groupId, {
        group = group,
        checkCharVisibility = false,
        checkLoadConditions = true,
        requireButtons = true,
    }) == true
end

function CooldownCompanion:IsContainerSuppressedForOtherClassBrowse(containerId, panels)
    if not containerId then
        return false
    end

    local panelList = panels or (self.GetPanels and self:GetPanels(containerId)) or nil
    local hasSuppressedPanel = false
    for _, panelInfo in ipairs(panelList or {}) do
        local groupId = panelInfo.groupId
        local group = panelInfo.group
        if self:IsGroupSuppressedForOtherClassBrowse(groupId, group) then
            hasSuppressedPanel = true
        elseif self:IsGroupVisibleInUnlockPreview(groupId, {
            group = group,
            checkCharVisibility = true,
        }) then
            return false
        end
    end

    return hasSuppressedPanel
end

function CooldownCompanion:CleanHeroTalentsForSpec(group, specId)
    if not group.heroTalents or not next(group.heroTalents) then return end
    local subTreeIDs = C_ClassTalents.GetHeroTalentSpecsForClassSpec(nil, specId)
    if not subTreeIDs then return end
    for _, subTreeID in ipairs(subTreeIDs) do
        group.heroTalents[subTreeID] = nil
    end
    if not next(group.heroTalents) then
        group.heroTalents = nil
    end
end

local function ClearEmptyCoreLoadConditions(entity)
    if type(entity) ~= "table" or type(entity.loadConditions) ~= "table" then return end
    if not next(entity.loadConditions) then
        entity.loadConditions = nil
    end
end

local function GetClassInfoByID(classID)
    classID = tonumber(classID)
    if not classID then return nil, nil, nil end
    if C_CreatureInfo and C_CreatureInfo.GetClassInfo then
        local classInfo = C_CreatureInfo.GetClassInfo(classID)
        if type(classInfo) == "table" then
            return classInfo.className, classInfo.classFile, classInfo.classID
        end
    end
    if GetClassInfo then
        return GetClassInfo(classID)
    end
    return nil, nil, nil
end

local function GetClassKeyFromClassID(classID)
    local _, classFilename = GetClassInfoByID(classID)
    return NormalizeClassKey(classFilename)
end

local function GetClassIDFromClassKey(classKey)
    classKey = NormalizeClassKey(classKey)
    if not classKey then return nil end
    for classID = 1, CLASS_SCAN_LIMIT do
        if GetClassKeyFromClassID(classID) == classKey then
            return classID
        end
    end
    return nil
end

local function GetCurrentScopeClassKey(addon)
    local classFilename = addon and addon._playerClassFilename
    if not classFilename and UnitClass then
        classFilename = select(2, UnitClass("player"))
    end
    return NormalizeClassKey(classFilename)
end

local function GetSpecClassKey(specId)
    if not (C_SpecializationInfo and C_SpecializationInfo.GetClassIDFromSpecID) then
        return nil
    end
    return GetClassKeyFromClassID(C_SpecializationInfo.GetClassIDFromSpecID(tonumber(specId)))
end

local function SpecBelongsToClass(specId, classKey)
    if not classKey then return true end
    local specClassKey = GetSpecClassKey(specId)
    return specClassKey == classKey
end

local function HeroTalentBelongsToClass(subTreeID, classKey)
    subTreeID = tonumber(subTreeID)
    if not classKey then return true end
    if not (subTreeID
        and C_ClassTalents
        and C_ClassTalents.GetHeroTalentSpecsForClassSpec
        and C_SpecializationInfo
        and C_SpecializationInfo.GetNumSpecializationsForClassID
        and C_SpecializationInfo.GetSpecializationInfo)
    then
        return false
    end

    local classID = GetClassIDFromClassKey(classKey)
    if not classID then return false end

    local numSpecs = C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0
    for specIndex = 1, numSpecs do
        local specId = C_SpecializationInfo.GetSpecializationInfo(
            specIndex,
            false,
            false,
            nil,
            nil,
            nil,
            classID
        )
        local subTreeIDs = specId and C_ClassTalents.GetHeroTalentSpecsForClassSpec(nil, specId)
        for _, availableSubTreeID in ipairs(subTreeIDs or {}) do
            if tonumber(availableSubTreeID) == subTreeID then
                return true
            end
        end
    end
    return false
end

local function GetCharacterClassKey(addon, charKey)
    local info = charKey
        and addon
        and addon.db
        and addon.db.global
        and addon.db.global.characterInfo
        and addon.db.global.characterInfo[charKey]
    if type(info) ~= "table" then
        return nil
    end
    return NormalizeClassKey(info.classFilename)
        or GetClassKeyFromClassID(info.classID)
end

local function BuildClassScopeResult(scope, opts)
    opts = opts or {}
    return {
        scope = scope,
        sectionKey = opts.sectionKey,
        ownerCharKey = opts.ownerCharKey,
        ownerClassKey = opts.ownerClassKey,
        currentClassKey = opts.currentClassKey,
        currentCharKey = opts.currentCharKey,
        isGlobal = scope == "global",
        isCurrentClass = scope == "current-class",
        isOtherClass = scope == "other-class",
        isInvalid = scope == "invalid",
        runtimeVisible = scope == "global" or scope == "current-class",
        invalidReason = opts.invalidReason,
    }
end

local function ResolveProfileEntityClassScope(addon, entity, opts)
    opts = opts or {}
    local currentCharKey = opts.currentCharKey
        or addon and addon.db and addon.db.keys and addon.db.keys.char
        or nil
    local currentClassKey = NormalizeClassKey(opts.currentClassKey)
        or GetCurrentScopeClassKey(addon)

    if type(entity) ~= "table" then
        return BuildClassScopeResult("invalid", {
            currentCharKey = currentCharKey,
            currentClassKey = currentClassKey,
            sectionKey = "invalid",
            invalidReason = "missing-entity",
        })
    end

    if opts.isGlobal == true then
        return BuildClassScopeResult("global", {
            currentCharKey = currentCharKey,
            currentClassKey = currentClassKey,
            sectionKey = "global",
        })
    end

    local ownerCharKey = opts.ownerCharKey or entity.createdBy
    if type(ownerCharKey) ~= "string" or ownerCharKey == "" then
        return BuildClassScopeResult("invalid", {
            currentCharKey = currentCharKey,
            currentClassKey = currentClassKey,
            sectionKey = "invalid",
            invalidReason = "missing-owner",
        })
    end

    local ownerClassKey = GetCharacterClassKey(addon, ownerCharKey)
    if not ownerClassKey then
        return BuildClassScopeResult("invalid", {
            ownerCharKey = ownerCharKey,
            currentCharKey = currentCharKey,
            currentClassKey = currentClassKey,
            sectionKey = "invalid",
            invalidReason = "missing-owner-class",
        })
    end

    if ownerClassKey == currentClassKey then
        return BuildClassScopeResult("current-class", {
            ownerCharKey = ownerCharKey,
            ownerClassKey = ownerClassKey,
            currentCharKey = currentCharKey,
            currentClassKey = currentClassKey,
            sectionKey = "char",
        })
    end

    return BuildClassScopeResult("other-class", {
        ownerCharKey = ownerCharKey,
        ownerClassKey = ownerClassKey,
        currentCharKey = currentCharKey,
        currentClassKey = currentClassKey,
        sectionKey = "class:" .. ownerClassKey,
    })
end

function CooldownCompanion:ResolveProfileEntityClassScope(entity, opts)
    return ResolveProfileEntityClassScope(self, entity, opts)
end

function CooldownCompanion:ResolveContainerClassScope(containerOrContainerId, opts)
    local container = containerOrContainerId
    if type(containerOrContainerId) == "number" then
        local db = self.db and self.db.profile
        container = db and db.groupContainers and db.groupContainers[containerOrContainerId] or nil
    end
    opts = opts and CopyTable(opts) or {}
    opts.isGlobal = type(container) == "table" and container.isGlobal == true
    return ResolveProfileEntityClassScope(self, container, opts)
end

function CooldownCompanion:ResolveFolderClassScope(folderOrFolderId, opts)
    local folder = folderOrFolderId
    if type(folderOrFolderId) == "number" then
        local db = self.db and self.db.profile
        folder = db and db.folders and db.folders[folderOrFolderId] or nil
    end
    opts = opts and CopyTable(opts) or {}
    opts.isGlobal = type(folder) == "table" and folder.section == "global"
    return ResolveProfileEntityClassScope(self, folder, opts)
end

function CooldownCompanion:CanMoveContainerToFolder(containerOrContainerId, folderOrFolderId, opts)
    opts = opts or {}
    if folderOrFolderId == nil then
        return true
    end

    local containerScope = self:ResolveContainerClassScope(containerOrContainerId)
    local folderScope = self:ResolveFolderClassScope(folderOrFolderId)
    if containerScope.isInvalid or folderScope.isInvalid then
        return false, "invalid-class-scope"
    end

    if containerScope.scope == folderScope.scope then
        if containerScope.scope == "global" then
            return true
        end
        return containerScope.ownerClassKey == folderScope.ownerClassKey, "mixed-class-folder"
    end

    if opts.allowScopeChange == true then
        if containerScope.scope == "global" and folderScope.scope == "current-class" then
            return true
        end
        if folderScope.scope == "global"
            and (containerScope.scope == "current-class" or containerScope.scope == "other-class")
        then
            return true
        end
    end

    return false, "scope-mismatch"
end

function CooldownCompanion:CanMovePanelToContainer(groupOrGroupId, targetContainerOrContainerId)
    local db = self.db and self.db.profile
    if not (db and db.groups and db.groupContainers) then
        return false, "missing-profile"
    end

    local group = groupOrGroupId
    if type(groupOrGroupId) ~= "table" then
        group = db.groups[groupOrGroupId]
    end
    if type(group) ~= "table" or not group.parentContainerId then
        return false, "missing-source-panel"
    end

    local targetContainer = targetContainerOrContainerId
    local targetContainerId
    if type(targetContainerOrContainerId) ~= "table" then
        targetContainerId = targetContainerOrContainerId
        targetContainer = db.groupContainers[targetContainerOrContainerId]
    else
        for containerId, container in pairs(db.groupContainers) do
            if container == targetContainer then
                targetContainerId = containerId
                break
            end
        end
    end
    if type(targetContainer) ~= "table" then
        return false, "missing-target-container"
    end
    if targetContainerId and group.parentContainerId == targetContainerId then
        return false, "same-container"
    end

    local sourceScope = self:ResolveContainerClassScope(group.parentContainerId)
    local targetScope = self:ResolveContainerClassScope(targetContainer)
    if sourceScope.isInvalid or targetScope.isInvalid then
        return false, "invalid-class-scope"
    end
    if sourceScope.scope ~= targetScope.scope then
        return false, "scope-mismatch"
    end
    if sourceScope.scope == "global" then
        return true
    end
    if sourceScope.ownerClassKey == targetScope.ownerClassKey then
        return true
    end
    return false, "mixed-class-panel"
end

function CooldownCompanion:CanMoveEntryToGroup(sourceGroupId, targetGroupId)
    local db = self.db and self.db.profile
    if not (db and db.groups) then
        return false
    end
    if sourceGroupId == targetGroupId then
        return false
    end

    local sourceGroup = db.groups[sourceGroupId]
    local targetGroup = db.groups[targetGroupId]
    if not (sourceGroup and targetGroup and sourceGroup.parentContainerId and targetGroup.parentContainerId) then
        return false
    end

    if not self.ResolveContainerClassScope then
        return self:IsGroupVisibleToCurrentChar(targetGroupId)
    end

    local sourceScope = self:ResolveContainerClassScope(sourceGroup.parentContainerId)
    if not sourceScope or sourceScope.isInvalid then
        return false
    end

    if sourceScope.isOtherClass then
        local targetScope = self:ResolveContainerClassScope(targetGroup.parentContainerId)
        return targetScope
            and targetScope.isInvalid ~= true
            and targetScope.isOtherClass == true
            and targetScope.ownerClassKey == sourceScope.ownerClassKey
    end

    return self:IsGroupVisibleToCurrentChar(targetGroupId)
end

local function PruneSpecMapToClass(addon, entity, map, classKey)
    if type(map) ~= "table" or not classKey then return false end
    local changed = false
    for key in pairs(map) do
        local specId = NormalizeSpecKey(key)
        if specId and SpecBelongsToClass(specId, classKey) then
            if key ~= specId then
                map[specId] = true
                map[key] = nil
                changed = true
            end
        else
            map[key] = nil
            if specId then
                map[specId] = nil
                if addon and addon.CleanHeroTalentsForSpec then
                    addon:CleanHeroTalentsForSpec(entity, specId)
                end
            end
            changed = true
        end
    end
    return changed
end

local function CharacterKeyMatchesClass(addon, charKey, classKey, ownerCharKey)
    if not classKey then return true end
    if charKey and ownerCharKey and charKey == ownerCharKey then
        return true
    end
    local currentCharKey = addon and addon.db and addon.db.keys and addon.db.keys.char
    if charKey and currentCharKey and charKey == currentCharKey then
        return true
    end
    return GetCharacterClassKey(addon, charKey) == classKey
end

local function PruneCharacterMapToClass(addon, map, classKey, ownerCharKey)
    if type(map) ~= "table" or not classKey then return false end
    local changed = false
    for key in pairs(map) do
        local charKey = NormalizeCharacterKey(key)
        if not (charKey and CharacterKeyMatchesClass(addon, charKey, classKey, ownerCharKey)) then
            map[key] = nil
            if charKey then
                map[charKey] = nil
            end
            changed = true
        end
    end
    return changed
end

local function PruneHeroTalentMapToClass(entity, classKey)
    if type(entity) ~= "table" or type(entity.heroTalents) ~= "table" or not classKey then return false end
    local changed = false
    for subTreeID in pairs(entity.heroTalents) do
        local normalizedSubTreeID = tonumber(subTreeID)
        if normalizedSubTreeID and HeroTalentBelongsToClass(normalizedSubTreeID, classKey) then
            if subTreeID ~= normalizedSubTreeID then
                entity.heroTalents[normalizedSubTreeID] = true
                entity.heroTalents[subTreeID] = nil
                changed = true
            end
        else
            entity.heroTalents[subTreeID] = nil
            if normalizedSubTreeID then
                entity.heroTalents[normalizedSubTreeID] = nil
            end
            changed = true
        end
    end
    if not next(entity.heroTalents) then
        entity.heroTalents = nil
    end
    return changed
end

local function WithOwnerCharKey(opts, ownerCharKey)
    if opts and opts.ownerCharKey then return opts end
    local scopedOpts = opts and CopyTable(opts) or {}
    scopedOpts.ownerCharKey = ownerCharKey
    return scopedOpts
end

function CooldownCompanion:NormalizeEligibilityForCharacterScope(entity, opts)
    if type(entity) ~= "table" then return false end
    opts = opts or {}
    local ownerCharKey = opts.ownerCharKey
        or entity.createdBy
        or (self.db and self.db.keys and self.db.keys.char)
    local classKey = NormalizeClassKey(opts.scopeClassKey)
        or GetCharacterClassKey(self, ownerCharKey)
        or GetCurrentScopeClassKey(self)
    local changed = false

    if PruneSpecMapToClass(self, entity, entity.specs, classKey) then
        changed = true
        if type(entity.specs) == "table" and not next(entity.specs) then
            entity.specs = nil
        end
    end
    changed = PruneHeroTalentMapToClass(entity, classKey) or changed

    local loadConditions = entity.loadConditions
    if type(loadConditions) == "table" then
        if loadConditions.classAllowlist ~= nil then
            loadConditions.classAllowlist = nil
            changed = true
        end
        if PruneSpecMapToClass(self, entity, loadConditions.specAllowlist, classKey) then
            changed = true
            if type(loadConditions.specAllowlist) == "table" and not next(loadConditions.specAllowlist) then
                loadConditions.specAllowlist = nil
            end
        end
        if PruneCharacterMapToClass(self, loadConditions.characterAllowlist, classKey, ownerCharKey) then
            changed = true
            if type(loadConditions.characterAllowlist) == "table"
                and not next(loadConditions.characterAllowlist)
            then
                loadConditions.characterAllowlist = nil
            end
        end
        ClearEmptyCoreLoadConditions(entity)
    end

    return changed
end

function CooldownCompanion:NormalizeContainerEligibilityForCharacterScope(containerId, opts)
    local db = self.db and self.db.profile
    if not (db and db.groupContainers) then return false end
    local container = db.groupContainers[containerId]
    if not container then return false end
    opts = WithOwnerCharKey(opts, container.createdBy or (self.db and self.db.keys and self.db.keys.char))

    local changed = self:NormalizeEligibilityForCharacterScope(container, opts)
    for _, group in pairs(db.groups or {}) do
        if type(group) == "table" and group.parentContainerId == containerId then
            changed = self:NormalizeEligibilityForCharacterScope(group, opts) or changed
        end
    end
    return changed
end

function CooldownCompanion:NormalizeFolderEligibilityForCharacterScope(folderId, opts)
    local db = self.db and self.db.profile
    if not (db and db.folders) then return false end
    local folder = db.folders[folderId]
    if not folder then return false end
    opts = WithOwnerCharKey(opts, folder.createdBy or (self.db and self.db.keys and self.db.keys.char))

    local changed = self:NormalizeEligibilityForCharacterScope(folder, opts)
    local childContainerIds = {}
    for containerId, container in pairs(db.groupContainers or {}) do
        if type(container) == "table" and container.folderId == folderId then
            childContainerIds[containerId] = true
            changed = self:NormalizeEligibilityForCharacterScope(container, opts) or changed
        end
    end
    for _, group in pairs(db.groups or {}) do
        if type(group) == "table" and childContainerIds[group.parentContainerId] then
            changed = self:NormalizeEligibilityForCharacterScope(group, opts) or changed
        end
    end
    return changed
end

function CooldownCompanion:IsGroupAvailableForAnchoring(groupId)
    local group = self.db.profile.groups[groupId]
    if not group then return false end
    if not group.parentContainerId then return false end
    if self.CanGroupBeExternalAnchorTarget then
        if not self:CanGroupBeExternalAnchorTarget(groupId) then return false end
    elseif self.IsGroupCursorAnchored and self:IsGroupCursorAnchored(group) then
        return false
    end
    if self.IsIconLikeDisplayMode and not self:IsIconLikeDisplayMode(group.displayMode) then return false end
    local container = self:GetParentContainer(group)
    if container and container.isGlobal and not container.anchorEligible then return false end
    if container and not container.isGlobal and container.anchorEligible == false then return false end
    if not self:IsGroupActive(groupId, {
        group = group,
        checkCharVisibility = true,
        checkLoadConditions = true,
    }) then
        return false
    end

    return true
end

function CooldownCompanion:IsGroupAvailableForPanelAnchorTarget(groupId)
    local group = self.db.profile.groups[groupId]
    if not group then return false end
    if self.CanGroupBePanelAnchorTarget then
        if not self:CanGroupBePanelAnchorTarget(groupId) then return false end
    else
        if not group.parentContainerId then return false end
        if self.IsGroupCursorAnchored and self:IsGroupCursorAnchored(group) then return false end
        if CooldownCompanion:IsStandaloneTexturePanelGroup(group) then return false end
    end

    local container = self:GetParentContainer(group)
    if container and container.isGlobal and not container.anchorEligible then return false end
    if container and not container.isGlobal and container.anchorEligible == false then return false end

    if not self:IsGroupActive(groupId, {
        group = group,
        checkCharVisibility = true,
        checkLoadConditions = true,
    }) then
        return false
    end

    return true
end

function CooldownCompanion:GetFirstAvailableAnchorGroup()
    local db = self.db.profile
    local groups = db.groups
    if not groups then return nil end
    local containers = db.groupContainers
    if not containers then return nil end
    local folders = db.folders or {}
    local specId = self._currentSpecId

    -- Build container-to-folder mapping
    local folderContainers = {}  -- [folderId] = { {id, order}, ... }
    local looseContainers = {}   -- { {id, order}, ... }

    for cid, container in pairs(containers) do
        local fid = container.folderId
        if fid and folders[fid] then
            if not folderContainers[fid] then
                folderContainers[fid] = {}
            end
            folderContainers[fid][#folderContainers[fid] + 1] = { id = cid, order = self:GetOrderForSpec(container, specId, cid) }
        else
            looseContainers[#looseContainers + 1] = { id = cid, order = self:GetOrderForSpec(container, specId, cid) }
        end
    end

    -- Sort containers within each folder by per-spec order
    for _, children in pairs(folderContainers) do
        table.sort(children, function(a, b) return a.order < b.order end)
    end
    table.sort(looseContainers, function(a, b) return a.order < b.order end)

    -- Build top-level items: folders + loose containers, sorted by order
    -- (mirrors Column1.lua BuildSectionItems)
    local topItems = {}
    for fid in pairs(folderContainers) do
        topItems[#topItems + 1] = { kind = "folder", id = fid, order = self:GetOrderForSpec(folders[fid], specId, fid) }
    end
    for _, lc in ipairs(looseContainers) do
        topItems[#topItems + 1] = { kind = "container", id = lc.id, order = lc.order }
    end
    table.sort(topItems, function(a, b) return a.order < b.order end)

    -- Iterate in visual order, return first available panel
    for _, item in ipairs(topItems) do
        local containerList
        if item.kind == "folder" then
            containerList = folderContainers[item.id]
        else
            containerList = { item }
        end
        for _, cInfo in ipairs(containerList) do
            local panels = self:GetPanels(cInfo.id)
            for _, panelInfo in ipairs(panels) do
                if self:IsGroupAvailableForAnchoring(panelInfo.groupId) then
                    return panelInfo.groupId
                end
            end
        end
    end
    return nil
end

local function IsResourceBarIndependentAnchor(settings, specId)
    local independent = settings and settings.independentAnchorEnabled == true
    local layouts = settings and settings.layoutOrder
    local layoutKey = specId and (tonumber(specId) or specId)
    local layout = nil
    if layoutKey and type(layouts) == "table" then
        layout = layouts[layoutKey] or layouts[tostring(layoutKey)]
    end
    if type(layout) == "table" and layout.independentAnchorEnabled ~= nil then
        independent = layout.independentAnchorEnabled == true
    end
    return independent
end

function CooldownCompanion:IsGroupStableExternalAnchor(groupId)
    groupId = tonumber(groupId)
    if not groupId then
        return false
    end

    local anchorGroupId = self.GetFirstAvailableAnchorGroup and tonumber(self:GetFirstAvailableAnchorGroup()) or nil
    if anchorGroupId ~= groupId then
        return false
    end

    local frameSettings = self.GetFrameAnchoringSettings and self:GetFrameAnchoringSettings() or nil
    if frameSettings and frameSettings.enabled == true then
        return true
    end

    local castSettings = self.GetCastBarSettings and self:GetCastBarSettings() or nil
    if castSettings and castSettings.enabled == true and castSettings.independentAnchorEnabled ~= true then
        return true
    end

    local resourceSettings = self.GetResourceBarSettings and self:GetResourceBarSettings() or nil
    if resourceSettings
        and resourceSettings.enabled == true
        and not IsResourceBarIndependentAnchor(resourceSettings, self._currentSpecId) then
        return true
    end

    return false
end

function CooldownCompanion:NormalizeStableExternalAnchorCompactLayout(groupId, group)
    local isStableAnchor = self:IsGroupStableExternalAnchor(groupId)
    if not isStableAnchor then
        return false, false
    end

    group = group or (self.db and self.db.profile and self.db.profile.groups and self.db.profile.groups[groupId])
    if group and group.compactLayout then
        group.compactLayout = false
        local frame = self.groupFrames and self.groupFrames[groupId]
        if frame then
            frame._layoutDirty = true
            if InCombatLockdown and InCombatLockdown() and frame:IsProtected() then
                self._pendingFullRefresh = true
            elseif self.PopulateGroupButtons then
                self:PopulateGroupButtons(groupId)
            end
        end
        return true, true
    end

    return true, false
end

function CooldownCompanion:NormalizeCurrentStableExternalAnchorCompactLayout()
    local groupId = self.GetFirstAvailableAnchorGroup and self:GetFirstAvailableAnchorGroup() or nil
    if not groupId then
        return false, false
    end
    return self:NormalizeStableExternalAnchorCompactLayout(groupId)
end

function CooldownCompanion:PopulatePanelAnchorTargetDropdown(dropdown, sourceGroupId)
    local db = self.db.profile
    local containers = db.groupContainers or {}
    local folders = db.folders or {}
    local folderContainers = {}
    local looseContainers = {}
    local eligibleCount = 0

    dropdown:SetList({}, {})

    for groupId, group in pairs(db.groups) do
        local targetFrameName = "CooldownCompanionGroup" .. groupId
        if groupId ~= sourceGroupId
            and _G[targetFrameName]
            and not self:WouldCreateCircularAnchor(sourceGroupId, groupId)
            and self:IsGroupAvailableForPanelAnchorTarget(groupId) then
            eligibleCount = eligibleCount + 1
            local cid = group.parentContainerId
            local ctr = containers[cid]
            local fid = ctr and ctr.folderId
            local contName = ctr and ctr.name or "Group"
            local panelName = group.name or ("Panel " .. groupId)
            local panelEntry = {
                id = groupId,
                key = tostring(groupId),
                name = panelName,
                contName = contName,
                order = group.order or groupId,
            }
            local containerBucket
            local entry = {
                id = cid,
                name = contName,
                order = self:GetOrderForSpec(ctr or {}, self._currentSpecId, cid),
                panels = {},
            }
            if fid and folders[fid] then
                folderContainers[fid] = folderContainers[fid] or {}
                containerBucket = folderContainers[fid][cid]
                if not containerBucket then
                    containerBucket = entry
                    folderContainers[fid][cid] = containerBucket
                end
            else
                containerBucket = looseContainers[cid]
                if not containerBucket then
                    containerBucket = entry
                    looseContainers[cid] = containerBucket
                end
            end
            table.insert(containerBucket.panels, panelEntry)
        end
    end

    local sortedFolders = {}
    for fid, folder in pairs(folders) do
        if folderContainers[fid] then
            table.insert(sortedFolders, {
                id = fid,
                name = folder.name or ("Folder " .. fid),
                order = self:GetOrderForSpec(folder, self._currentSpecId, fid),
            })
        end
    end
    table.sort(sortedFolders, function(a, b) return a.order < b.order end)

    local hasHeaders = #sortedFolders > 0

    for _, folder in ipairs(sortedFolders) do
        local hdrKey = "_panel_hdr_" .. folder.id
        dropdown:AddItem(hdrKey, "|cffffd100" .. folder.name .. "|r")
        dropdown:SetItemDisabled(hdrKey, true)

        local sortedContainers = {}
        for _, container in pairs(folderContainers[folder.id]) do
            table.insert(sortedContainers, container)
        end
        table.sort(sortedContainers, function(a, b)
            if a.order ~= b.order then return a.order < b.order end
            return a.name < b.name
        end)

        for _, container in ipairs(sortedContainers) do
            local containerHdrKey = "_panel_ctr_" .. folder.id .. "_" .. tostring(container.id)
            dropdown:AddItem(containerHdrKey, "   |cffffd100" .. container.name .. "|r")
            dropdown:SetItemDisabled(containerHdrKey, true)

            table.sort(container.panels, function(a, b)
                if a.order ~= b.order then return a.order < b.order end
                return a.name < b.name
            end)
            for _, panel in ipairs(container.panels) do
                dropdown:AddItem(panel.key, "      " .. panel.name)
                dropdown.list[panel.key] = panel.contName .. ": " .. panel.name
            end
        end
    end

    local sortedLooseContainers = {}
    for _, container in pairs(looseContainers) do
        table.insert(sortedLooseContainers, container)
    end

    if #sortedLooseContainers > 0 then
        if hasHeaders then
            dropdown:AddItem("_panel_hdr_none", "|cffffd100No Folder|r")
            dropdown:SetItemDisabled("_panel_hdr_none", true)
        end
        table.sort(sortedLooseContainers, function(a, b)
            if a.order ~= b.order then return a.order < b.order end
            return a.name < b.name
        end)
        for _, container in ipairs(sortedLooseContainers) do
            local containerHdrKey = "_panel_ctr_none_" .. tostring(container.id)
            local containerPrefix = hasHeaders and "   " or ""
            dropdown:AddItem(containerHdrKey, containerPrefix .. "|cffffd100" .. container.name .. "|r")
            dropdown:SetItemDisabled(containerHdrKey, true)

            table.sort(container.panels, function(a, b)
                if a.order ~= b.order then return a.order < b.order end
                return a.name < b.name
            end)
            for _, panel in ipairs(container.panels) do
                local panelPrefix = hasHeaders and "      " or "   "
                dropdown:AddItem(panel.key, panelPrefix .. panel.name)
                dropdown.list[panel.key] = panel.contName .. ": " .. panel.name
            end
        end
    end

    return eligibleCount
end

function CooldownCompanion:GetDefaultLoadConditions()
    return CopyTable(LOAD_CONDITION_DEFAULTS)
end

function CooldownCompanion:GetLocalLoadConditionDefaults()
    return CopyTable(LOCAL_LOAD_CONDITION_DEFAULTS)
end

function CooldownCompanion:HasLocalLoadConditions(entity)
    if not (type(entity) == "table" and type(entity.loadConditions) == "table") then
        return false
    end
    for key, value in pairs(entity.loadConditions) do
        if value == true then
            return true
        end
        if LOAD_CONDITION_ALLOWLIST_KEYS[key] and type(value) == "table" and next(value) then
            return true
        end
    end
    return false
end

function CooldownCompanion:EvaluateLoadConditions(loadConditions, defaults)
    local lc = loadConditions
    if not lc then return true end
    defaults = defaults or LOAD_CONDITION_DEFAULTS

    local instanceType = self._currentInstanceType

    -- Map instance type to load condition key
    local conditionKey
    if instanceType == "raid" then
        conditionKey = "raid"
    elseif instanceType == "party" then
        conditionKey = "dungeon"
    elseif instanceType == "pvp" then
        conditionKey = "battleground"
    elseif instanceType == "arena" then
        conditionKey = "arena"
    elseif instanceType == "delve" then
        conditionKey = "delve"
    else
        conditionKey = "openWorld"  -- "none" or "scenario"
    end

    -- If the matching instance condition is enabled, unload
    if lc[conditionKey] then return false end

    -- If rested condition is enabled and player is resting, unload
    if lc.rested and self._isResting then return false end

    -- If pet battle condition is enabled and player is in a pet battle, unload.
    -- Group/panel scopes default this on; folder/entry scopes default it off.
    local petBattle = lc.petBattle
    if petBattle == nil then petBattle = defaults.petBattle or false end
    if petBattle and self._inPetBattle then return false end

    -- If vehicle/override UI condition is enabled and player is in a vehicle or
    -- override bar, unload. Defaults follow the same scope rules as pet battles.
    local vehicleUI = lc.vehicleUI
    if vehicleUI == nil then vehicleUI = defaults.vehicleUI or false end
    if vehicleUI and self._inVehicleUI then return false end

    return true
end

function CooldownCompanion:GetCurrentEligibilityIdentity()
    local classFilename = self._playerClassFilename
    if not classFilename and UnitClass then
        classFilename = select(2, UnitClass("player"))
    end
    return {
        classFilename = NormalizeClassKey(classFilename),
        specId = self._currentSpecId,
        charKey = self.db and self.db.keys and self.db.keys.char or nil,
    }
end

local function AddLoadConditionSource(sources, label, entity, defaults, allowClassEligibility)
    if type(entity) == "table" and type(entity.loadConditions) == "table" then
        sources[#sources + 1] = {
            label = label,
            loadConditions = entity.loadConditions,
            defaults = defaults,
            allowClassEligibility = allowClassEligibility == true,
        }
    end
end

local function HasEligibilityAllowlist(loadConditions, allowClassEligibility)
    if type(loadConditions) ~= "table" then return false end
    if allowClassEligibility and loadConditions.classAllowlist ~= nil then
        return true
    end
    return loadConditions.specAllowlist ~= nil
        or loadConditions.characterAllowlist ~= nil
end

local function IsFolderGlobalScope(folder)
    return type(folder) == "table" and folder.section == "global"
end

local function IsContainerGlobalScope(container)
    return type(container) == "table" and container.isGlobal == true
end

function CooldownCompanion:GetInheritedLoadConditionSources(group)
    local sources = {}
    local db = self.db and self.db.profile
    if not (db and group) then return sources end

    local container = self:GetParentContainer(group)
    if container then
        local folder = container.folderId and db.folders and db.folders[container.folderId]
        AddLoadConditionSource(sources, "Folder", folder, LOCAL_LOAD_CONDITION_DEFAULTS, IsFolderGlobalScope(folder))
        AddLoadConditionSource(sources, "Group", container, LOAD_CONDITION_DEFAULTS, IsContainerGlobalScope(container))
        return sources
    end

    local folder = group.folderId and db.folders and db.folders[group.folderId]
    AddLoadConditionSource(sources, "Folder", folder, LOCAL_LOAD_CONDITION_DEFAULTS, IsFolderGlobalScope(folder))
    return sources
end

function CooldownCompanion:GetLoadConditionSourcesForGroup(group)
    local sources = self:GetInheritedLoadConditionSources(group)
    if group then
        local container = self:GetParentContainer(group)
        local allowClassEligibility
        if container then
            allowClassEligibility = IsContainerGlobalScope(container)
        else
            allowClassEligibility = group.isGlobal == true
        end
        AddLoadConditionSource(sources, group.parentContainerId and "Panel" or "Group", group, LOAD_CONDITION_DEFAULTS, allowClassEligibility)
    end
    return sources
end

function CooldownCompanion:GetLoadConditionSourcesForEntry(buttonData, group)
    local sources = self:GetLoadConditionSourcesForGroup(group)
    AddLoadConditionSource(sources, "Entry", buttonData, LOCAL_LOAD_CONDITION_DEFAULTS, false)
    return sources
end

function CooldownCompanion:EvaluateLoadConditionSources(sources, opts)
    opts = opts or {}
    local eligibility
    local identity

    for _, source in ipairs(sources or {}) do
        if opts.eligibilityOnly ~= true
            and not self:EvaluateLoadConditions(source.loadConditions, source.defaults)
        then
            return false, source.label
        end
        local loadConditions = source.loadConditions
        if HasEligibilityAllowlist(loadConditions, source.allowClassEligibility) then
            if not eligibility then
                eligibility = {}
                identity = self:GetCurrentEligibilityIdentity()
            end
            if source.allowClassEligibility then
                MergeEligibilityAllowlist(eligibility, "class", loadConditions.classAllowlist, NormalizeClassKey)
            end
            MergeEligibilityAllowlist(eligibility, "spec", loadConditions.specAllowlist, NormalizeSpecKey)
            MergeEligibilityAllowlist(eligibility, "character", loadConditions.characterAllowlist, NormalizeCharacterKey)
            if not AllowlistMatches(eligibility, "class", identity.classFilename)
                or not AllowlistMatches(eligibility, "spec", identity.specId)
                or not AllowlistMatches(eligibility, "character", identity.charKey)
            then
                return false, source.label
            end
        end
    end
    return true, nil
end

function CooldownCompanion:IsGroupLoadConditionMet(group)
    return self:EvaluateLoadConditionSources(self:GetLoadConditionSourcesForGroup(group))
end

function CooldownCompanion:IsGroupEligibilityMet(group)
    return self:EvaluateLoadConditionSources(self:GetLoadConditionSourcesForGroup(group), {
        eligibilityOnly = true,
    })
end

function CooldownCompanion:IsButtonLoadConditionMet(buttonData, group)
    return self:EvaluateLoadConditionSources(self:GetLoadConditionSourcesForEntry(buttonData, group))
end

function CooldownCompanion:IsCustomBarLoadConditionMet(customBar)
    local sources = {}
    AddLoadConditionSource(sources, "Custom Bar", customBar, LOCAL_LOAD_CONDITION_DEFAULTS, true)
    return self:EvaluateLoadConditionSources(sources)
end

function CooldownCompanion:IsCustomBarRuntimeEligible(customBar)
    if type(customBar) ~= "table" then return false end
    if customBar.enabled ~= true or not customBar.spellID then return false end
    if not self:IsTalentConditionMet(customBar) then return false end
    return self:IsCustomBarLoadConditionMet(customBar)
end


-- ToggleGroupGlobal is defined in GroupManagement.lua (container-aware version)

function CooldownCompanion:GroupHasPetSpells(groupId)
    local group = self.db.profile.groups[groupId]
    if not group then return false end
    for _, buttonData in ipairs(group.buttons) do
        if buttonData.isPetSpell then return true end
    end
    return false
end

local function SpellIDsMatchCanonicalForm(storedSpellID, resolvedSpellID)
    if not storedSpellID or not resolvedSpellID then
        return false
    end
    if storedSpellID == resolvedSpellID then
        return true
    end

    local storedBaseSpellID = C_Spell.GetBaseSpell(storedSpellID)
    local resolvedBaseSpellID = C_Spell.GetBaseSpell(resolvedSpellID)

    return storedBaseSpellID ~= nil
        and resolvedBaseSpellID ~= nil
        and storedBaseSpellID == resolvedBaseSpellID
end

function CooldownCompanion:IsButtonUsable(buttonData, group, opts)
    opts = opts or {}
    if buttonData.enabled == false then return false end

    if opts.checkLoadConditions ~= false and not self:IsButtonLoadConditionMet(buttonData, group) then return false end

    -- Per-button talent condition: gate visibility on a specific talent node.
    if not opts.ignoreTalentConditions and not self:IsTalentConditionMet(buttonData) then return false end

    if opts.ignoreSpellAvailability and buttonData.type == "spell" then
        return true
    end
    if opts.ignoreItemAvailability
        and (
            buttonData.type == "item"
            or (CooldownCompanion.IsEquipmentSlotEntry and CooldownCompanion.IsEquipmentSlotEntry(buttonData))
        ) then
        return true
    end

    -- Passive/proc spells are tracked via aura, not spellbook presence.
    -- Multi-CDM-child buttons: verify their specific slot still exists in the CDM
    -- (spell may not be available on the current spec/talent loadout).
    if buttonData.isPassive then
        if buttonData.cdmChildSlot then
            local allChildren = self.viewerAuraAllChildren[buttonData.id]
            if not allChildren or not allChildren[buttonData.cdmChildSlot] then
                return false
            end
        end
        return true
    end

    if buttonData.type == "spell" then
        local bank = buttonData.isPetSpell
            and Enum.SpellBookSpellBank.Pet
            or Enum.SpellBookSpellBank.Player

        -- Pet spells: retain direct known/spellbook check.
        if buttonData.isPetSpell then
            return C_SpellBook.IsSpellKnownOrInSpellBook(buttonData.id, bank, false)
        end

        -- Player spells: require exact active-spec spellbook presence for this
        -- tracked spell ID (not an override/sibling form). This keeps loadability
        -- aligned with current-spec spellbook addability semantics.
        local slot, slotBank = C_SpellBook.FindSpellBookSlotForSpell(
            buttonData.id, false, true, false, false
        )
        if slot and slotBank == Enum.SpellBookSpellBank.Player then
            local itemType, _, spellID = C_SpellBook.GetSpellBookItemType(slot, slotBank)
            if spellID
                and not C_SpellBook.IsSpellBookItemOffSpec(slot, slotBank)
                and itemType ~= Enum.SpellBookItemType.FutureSpell
                and SpellIDsMatchCanonicalForm(buttonData.id, spellID)
            then
                return true
            end
        end

        -- Flyout child spells can be valid even when they don't resolve to a
        -- direct spell slot via FindSpellBookSlotForSpell.
        local flyoutSlot = C_SpellBook.FindFlyoutSlotBySpellID(buttonData.id)
        if not flyoutSlot then
            return false
        end

        local flyoutBank = Enum.SpellBookSpellBank.Player
        local flyoutType = C_SpellBook.GetSpellBookItemType(flyoutSlot, flyoutBank)
        if flyoutType ~= Enum.SpellBookItemType.Flyout then
            return false
        end
        if C_SpellBook.IsSpellBookItemOffSpec(flyoutSlot, flyoutBank) then
            return false
        end

        return true
    elseif CooldownCompanion.IsEquipmentSlotEntry and CooldownCompanion.IsEquipmentSlotEntry(buttonData) then
        local effectiveItem = CooldownCompanion.ResolveEffectiveItem
            and CooldownCompanion.ResolveEffectiveItem(buttonData, true) or nil
        return effectiveItem and effectiveItem.trackable == true
    elseif buttonData.type == "item" then
        if buttonData.hasCharges then return true end
        if not CooldownCompanion.IsItemEquippable(buttonData) then return true end
        return C_Item.GetItemCount(buttonData.id) > 0
    end
    return true
end

local function GetFrameForButtonSetComparison(addon, groupId)
    local frame = addon.groupFrames and addon.groupFrames[groupId]
    if frame then return frame end
    return addon._dormantFrames and addon._dormantFrames[groupId] or nil
end

function CooldownCompanion:GroupButtonSetNeedsRebuild(groupId, group, opts)
    opts = opts or {}
    local frame = GetFrameForButtonSetComparison(self, groupId)
    if not frame or not frame.buttons then
        return false
    end
    if self:IsRotationAssistantGroup(group) then
        local buttonData = frame._rotationAssistantButtonData
        return #frame.buttons ~= 1
            or not frame.buttons[1]
            or frame.buttons[1].buttonData ~= buttonData
    end
    if not group.buttons then
        return #frame.buttons > 0
    end

    local usableButtons = {}
    local usableCount = 0
    local buttonUsabilityOptions = opts.buttonUsabilityOptions
    if not buttonUsabilityOptions
        and opts.allowConfigPreviewButtonUsability
        and self.GetGroupButtonUsabilityOptions then
        buttonUsabilityOptions = self:GetGroupButtonUsabilityOptions(groupId, group)
    end
    for sourceIndex, buttonData in ipairs(group.buttons) do
        if self:IsButtonInConfigPreviewScope(groupId, sourceIndex, buttonUsabilityOptions)
            and self:IsButtonUsable(buttonData, group, buttonUsabilityOptions) then
            usableCount = usableCount + 1
            usableButtons[usableCount] = buttonData
        end
    end

    if #frame.buttons ~= usableCount then
        return true
    end

    for i = 1, usableCount do
        local button = frame.buttons[i]
        if not button or button.buttonData ~= usableButtons[i] then
            return true
        end
    end

    return false
end

function CooldownCompanion:AnyGroupButtonSetNeedsRebuild()
    if not self.db or not self.db.profile or not self.db.profile.groups then
        return false
    end

    for groupId, group in pairs(self.db.profile.groups) do
        if self:IsGroupVisibleToCurrentChar(groupId)
            and self:IsGroupActive(groupId, {
                group = group,
                checkCharVisibility = false,
                checkLoadConditions = true,
                requireButtons = false,
            })
            and self:GroupButtonSetNeedsRebuild(groupId, group)
        then
            return true
        end
    end

    return false
end

function CooldownCompanion:ResetSpellAvailabilityButtonRuntime()
    local function resetFrameButtons(frame)
        if not frame or not frame.buttons then return end
        for _, button in ipairs(frame.buttons) do
            local buttonData = button.buttonData
            if buttonData and buttonData.type == "spell" then
                button._noCooldown = nil
                button._noCooldownSpellId = nil
                button._baseNoCooldown = nil
                button._baseNoCooldownSpellId = nil
                button._resourceGateCost = nil
                button._resourceGateCostSpellId = nil
                button._baseResourceGateCost = nil
                button._baseResourceGateCostSpellId = nil
                button._displaySpellId = nil
                button._liveOverrideSpellId = nil
                button._lastSpellTexture = nil
                button._lastTextureCheckAt = nil
                button._iconDirty = true
                button._cooldownDeferred = nil
                button._durationObj = nil
                button._auraDurationObj = nil
                button._auraCooldownStart = nil
                button._auraCooldownDuration = nil
                button._auraPrimarySwipeActive = nil
                button._chargeDurationObj = nil
                button._chargeRecharging = nil
                button._chargeState = nil
                button._currentReadableCharges = nil
                button._chargeCountReadable = nil
                button._zeroChargesConfirmed = nil
                button._displayCountZeroUsabilityFallback = nil
                ClearButtonVisualState(button)
            end
        end
    end

    if self.groupFrames then
        for _, frame in pairs(self.groupFrames) do
            resetFrameButtons(frame)
        end
    end
    if self._dormantFrames then
        for _, frame in pairs(self._dormantFrames) do
            resetFrameButtons(frame)
        end
    end

    self:MarkCooldownsDirty("availability-rebuild")
end

function CooldownCompanion:RefreshAllGroupsForSpellAvailability()
    local needsFullRefresh = self:AnyGroupButtonSetNeedsRebuild()
    self:ResetSpellAvailabilityButtonRuntime()

    if needsFullRefresh then
        self:RefreshAllGroups()
    else
        self:RefreshAllGroupsVisibilityOnly()
    end

    ST.TagRefreshPass("availability-rebuild")
    self:UpdateAllCooldowns()

    -- D3: spec/talent/spell-availability churn can change override identity
    -- without repopulating buttons — refresh the identity index (coalesced).
    self:RequestSpellButtonIndexRebuild("availability")
end

function CooldownCompanion:CreateAllGroupFrames()
    local previousCreatingAllGroupFrames = self._creatingAllGroupFrames
    self._creatingAllGroupFrames = true
    for groupId, _ in pairs(self.db.profile.groups) do
        if self:IsGroupVisibleToCurrentChar(groupId) then
            self:CreateGroupFrame(groupId)
        end
    end
    self._creatingAllGroupFrames = previousCreatingAllGroupFrames
    self:FinalizePanelAnchors()
    self:FinalizeNonPanelGroupAnchors()
    if self.RefreshAlphaUpdateDriver then
        self:RefreshAlphaUpdateDriver()
    end
end

function CooldownCompanion:RefreshConfigSelectedGroupFrames()
    if self._refreshingConfigSelectedGroupFrames then
        return
    end
    if InCombatLockdown() then
        self._pendingFullRefresh = true
        if self.RefreshAlphaUpdateDriver then
            self:RefreshAlphaUpdateDriver()
        end
        return
    end
    if not (self.db and self.db.profile and self.db.profile.groups) then
        return
    end

    self._refreshingConfigSelectedGroupFrames = true
    local groups = self.db.profile.groups
    local previousPreviewed = self._configPreviewedGroupFrames
    local currentPreviewed = nil
    local candidates = {}

    for groupId in pairs(groups) do
        if IsSelectionDrivenConfigPreviewScope(self, groupId) then
            currentPreviewed = currentPreviewed or {}
            currentPreviewed[groupId] = true
            candidates[groupId] = true
        end
    end
    if previousPreviewed then
        for groupId in pairs(previousPreviewed) do
            candidates[groupId] = true
        end
    end
    self._configPreviewedGroupFrames = currentPreviewed

    local refreshed = false
    for groupId in pairs(candidates) do
        local group = groups[groupId]
        if group then
            local frame = self.groupFrames and self.groupFrames[groupId]
            local wasPreviewed = previousPreviewed and previousPreviewed[groupId]
            local isPreviewed = currentPreviewed and currentPreviewed[groupId]
            local previewEligible = self:IsGroupEligibleForConfigPreview(groupId, {
                group = group,
            })
            local active = self:IsGroupActive(groupId, {
                group = group,
                checkCharVisibility = true,
                checkLoadConditions = true,
                requireButtons = true,
            }) or previewEligible
            if (active or (wasPreviewed and frame))
                and (not frame
                    or (wasPreviewed and not isPreviewed)
                    or self:GroupButtonSetNeedsRebuild(groupId, group, {
                        allowConfigPreviewButtonUsability = isPreviewed,
                    })) then
                EnsureConfigPreviewContainerFrame(self, group, previewEligible)
                self:RefreshGroupFrame(groupId)
                refreshed = true
            end
        end
    end
    self._refreshingConfigSelectedGroupFrames = nil
    local containersCleaned = CleanupInactiveConfigPreviewContainerFrames(self)

    if refreshed or containersCleaned then
        self:FinalizePanelAnchors()
        if self.RefreshAllContainerWrappers then
            self:RefreshAllContainerWrappers()
        end
    end
end

function CooldownCompanion:FinalizePanelAnchors()
    local groups = self.db and self.db.profile and self.db.profile.groups
    if not (groups and self.groupFrames) then
        return
    end

    -- This is the post-create/post-refresh owner for panel lifecycle order:
    -- size every panel first, then re-apply saved anchors from roots outward.
    local panels = {}
    for groupId, group in pairs(groups) do
        local frame = self.groupFrames[groupId]
        if group and group.parentContainerId and group.anchor and frame then
            if self.NormalizeStableExternalAnchorCompactLayout then
                self:NormalizeStableExternalAnchorCompactLayout(groupId, group)
            end
            if not group.compactLayout then
                frame.layoutButtonCount = self:GetGroupLayoutButtonCount(groupId, group, {
                    allowConfigPreviewButtonUsability = self:IsGroupEligibleForConfigPreview(groupId, {
                        group = group,
                    }),
                })
            else
                frame.layoutButtonCount = nil
            end
            self:ResizeGroupFrame(groupId)
            panels[#panels + 1] = {
                groupId = groupId,
                group = group,
                frame = frame,
                depth = GetPanelAnchorDepth(groups, groupId),
            }
        end
    end

    table.sort(panels, function(a, b)
        if a.depth ~= b.depth then
            return a.depth < b.depth
        end
        return tostring(a.groupId) < tostring(b.groupId)
    end)

    for _, panel in ipairs(panels) do
        if not (panel.group.compactLayout and IsFrameAnchoredToSavedTarget(panel.frame, panel.group.anchor)) then
            self:AnchorGroupFrame(panel.frame, panel.group.anchor)
        end
    end

    self:RebuildPanelAlphaDependencyTargets(groups)
end

function CooldownCompanion:FinalizeNonPanelGroupAnchors()
    local groups = self.db and self.db.profile and self.db.profile.groups
    if not (groups and self.groupFrames) then
        return
    end

    for groupId, group in pairs(groups) do
        local anchor = group and group.anchor
        local relativeTo = type(anchor) == "table" and anchor.relativeTo or nil
        local targetKind = self:ParseAddonAnchorFrameName(relativeTo)
        local frame = self.groupFrames[groupId]
        if frame
            and group
            and not group.parentContainerId
            and (targetKind == "group" or targetKind == "container") then
            self:AnchorGroupFrame(frame, anchor)
        end
    end
end

function CooldownCompanion:RefreshAllGroups()
    if self._unsupportedLegacyProfile then
        self:ClearUnsupportedProfileRuntime()
        return
    end

    -- Defer entire refresh during combat — protected frame operations
    -- (Show/Hide/SetSize/SetPoint/SetFrameStrata/RegisterForDrag/EnableMouse)
    -- are all blocked. Per-tick cooldown updates continue independently.
    if InCombatLockdown() then
        self._pendingFullRefresh = true
        if self.RefreshAlphaUpdateDriver then
            self:RefreshAlphaUpdateDriver()
        end
        return
    end
    -- Clean up stale container frames (e.g. after profile switch)
    local previewContainerIds, previewGroupIds = BuildConfigPreviewEligibility(self)
    if self.containerFrames then
        local containers = self.db.profile.groupContainers or {}
        for containerId, frame in pairs(self.containerFrames) do
            if not containers[containerId] then
                frame:Hide()
                self.containerFrames[containerId] = nil
            end
        end
        -- Ensure all current-profile containers have frames
        for containerId, _ in pairs(containers) do
            if self:IsContainerVisibleToCurrentChar(containerId)
                or (previewContainerIds and previewContainerIds[containerId]) then
                if not self.containerFrames[containerId] then
                    self:CreateContainerFrame(containerId)
                else
                    self.containerFrames[containerId]:Show()
                end
            else
                if self.containerFrames[containerId] then
                    self.containerFrames[containerId]:Hide()
                end
            end
        end
    end

    -- Fully unload frames for groups not in the current profile
    -- (e.g. after a profile switch).
    for groupId, _ in pairs(self.groupFrames) do
        if not self.db.profile.groups[groupId] then
            self:UnloadGroup(groupId)
            self:DiscardDormantFrame(groupId)
        end
    end
    -- Also discard dormant frames for deleted groups
    if self._dormantFrames then
        for groupId, _ in pairs(self._dormantFrames) do
            if not self.db.profile.groups[groupId] then
                self:DiscardDormantFrame(groupId)
            end
        end
    end

    -- Refresh current profile's groups: load active ones, unload inactive ones
    for groupId, group in pairs(self.db.profile.groups) do
        local visible = self:IsGroupVisibleToCurrentChar(groupId)
        local previewEligible = previewGroupIds and previewGroupIds[groupId] == true
        if not visible and not previewEligible then
            self:UnloadGroup(groupId)
        elseif self:IsGroupSuppressedForOtherClassBrowse(groupId, group) then
            self:UnloadGroup(groupId)
        elseif self:IsGroupActive(groupId, {
            group = group,
            checkCharVisibility = false,
            checkLoadConditions = true,
            requireButtons = false,
        }) or previewEligible then
            self:RefreshGroupFrame(groupId)
        else
            self:UnloadGroup(groupId)
        end
    end

    self:FinalizeContainerAnchorsToScreenOffsets()
    self:FinalizePanelAnchors()
    if self.RefreshAllContainerWrappers then
        self:RefreshAllContainerWrappers()
    end
    if self.RefreshCursorAnchorTicker then
        self:RefreshCursorAnchorTicker()
    end
    if self.RefreshAlphaUpdateDriver then
        self:RefreshAlphaUpdateDriver()
    end
end

-- Refresh only frame-level visibility/load-state without rebuilding buttons.
-- Used by zone/resting/pet-battle transitions to avoid compact-layout flash
-- caused by full button repopulation.
function CooldownCompanion:RefreshAllGroupsVisibilityOnly()
    if self._unsupportedLegacyProfile then
        self:ClearUnsupportedProfileRuntime()
        return
    end

    -- Fully unload frames for groups not in the current profile
    for groupId, _ in pairs(self.groupFrames) do
        if not self.db.profile.groups[groupId] then
            self:UnloadGroup(groupId)
            self:DiscardDormantFrame(groupId)
        end
    end
    -- Also discard dormant frames for deleted groups
    if self._dormantFrames then
        for groupId, _ in pairs(self._dormantFrames) do
            if not self.db.profile.groups[groupId] then
                self:DiscardDormantFrame(groupId)
            end
        end
    end

    for groupId, group in pairs(self.db.profile.groups) do
        local visible = self:IsGroupVisibleToCurrentChar(groupId)
        local previewEligible = self:IsGroupEligibleForConfigPreview(groupId, {
            group = group,
        })
        EnsureConfigPreviewContainerFrame(self, group, previewEligible)
        if not visible and not previewEligible then
            self:UnloadGroup(groupId)
        elseif self:IsGroupSuppressedForOtherClassBrowse(groupId, group) then
            self:UnloadGroup(groupId)
        else
            local active = self:IsGroupActive(groupId, {
                group = group,
                checkCharVisibility = true,
                checkLoadConditions = true,
                requireButtons = true,
            }) or previewEligible

            if not active then
                self:UnloadGroup(groupId)
            else
                local frame = self.groupFrames[groupId]
                if frame and self:GroupButtonSetNeedsRebuild(groupId, group, {
                    allowConfigPreviewButtonUsability = previewEligible,
                }) then
                    self:RefreshGroupFrame(groupId)
                    frame = self.groupFrames[groupId]
                elseif not frame then
                    if self:GroupButtonSetNeedsRebuild(groupId, group, {
                        allowConfigPreviewButtonUsability = previewEligible,
                    }) then
                        self:DiscardDormantFrame(groupId)
                    end
                    -- Recover dormant frame with buttons intact (no repopulation needed)
                    frame = self:RecoverDormantFrame(groupId)
                end
                if not frame then
                    if InCombatLockdown() then
                        self._pendingVisibilityRefresh = true
                    else
                        frame = self:CreateGroupFrame(groupId)
                    end
                end

                if frame then
                    local wasShown = frame:IsShown()
                    if InCombatLockdown() and frame:IsProtected() then
                        if not wasShown then
                            self._pendingVisibilityRefresh = true
                        end
                    else
                        frame:Show()
                    end
                    -- Resolve locked from container (panels defer to container lock)
                    local container = self:GetParentContainer(group)
                    local isLocked
                    if self.IsGroupCursorAnchored and self:IsGroupCursorAnchored(group) then
                        isLocked = true
                    elseif container then
                        isLocked = container.locked ~= false
                    else
                        isLocked = group.locked
                    end
                    -- Force 100% alpha while unlocked for easier positioning
                    if not isLocked then
                        frame:SetAlpha(1)
                    -- Apply current alpha from the alpha fade system so frame
                    -- doesn't flash at 1.0 when baseline alpha is configured.
                    else
                        local frameAlpha, _, hasRuntimeAlpha = self:GetPanelCurrentAlphaValue(groupId, group)
                        if hasRuntimeAlpha then
                            frame:SetAlpha(frameAlpha)
                        end
                    end

                    -- When transitioning hidden -> shown, refresh button state
                    -- immediately so compact groups never show stale slots.
                    if not wasShown then
                        if frame.UpdateCooldowns then
                            frame:UpdateCooldowns()
                        end
                        if group.compactLayout then
                            frame._layoutDirty = true
                            self:UpdateGroupLayout(groupId)
                        end
                    end
                end
            end
        end
    end

    self:FinalizeContainerAnchorsToScreenOffsets()
    self:FinalizePanelAnchors()
    if self.RefreshAllContainerWrappers then
        self:RefreshAllContainerWrappers()
    end
    if self.RefreshCursorAnchorTicker then
        self:RefreshCursorAnchorTicker()
    end
    if self.RefreshAlphaUpdateDriver then
        self:RefreshAlphaUpdateDriver()
    end
end

-- Fully unload a group: save/clear button OnUpdate scripts, remove from
-- Masque, clear runtime state, hide the frame, and move it to a dormant
-- cache for reuse. Config data (db.profile.groups) is preserved so the
-- group can reload when load conditions change. Buttons remain attached
-- to the frame so visibility-only transitions can reuse them without
-- creating new C-side frame objects.
function CooldownCompanion:UnloadGroup(groupId)
    local frame = self.groupFrames[groupId]
    if not frame then return end
    UnregisterKeyPressHighlightFrame(frame)

    -- Save and clear button OnUpdate scripts, remove from Masque.
    -- Buttons stay attached to the frame for potential reuse.
    if frame.buttons then
        for _, button in ipairs(frame.buttons) do
            if self.HideAuraTextureVisual then
                self:HideAuraTextureVisual(button)
            end
            self:RemoveButtonFromMasque(groupId, button)
            local onUpdate = button:GetScript("OnUpdate")
            if onUpdate then
                button._savedOnUpdate = onUpdate
                button:SetScript("OnUpdate", nil)
            end
            -- Dormant buttons stop being evaluated; release their scratches so
            -- they don't pin aura data or secret names while parked.
            ST.EntryRuntime.ReleaseTrackedAuraScratch(button)
        end
    end

    -- Delete Masque group
    self:DeleteMasqueGroup(groupId)

    -- Clear alpha fade state
    if self.alphaState then
        self.alphaState[groupId] = nil
    end

    -- Stop alphaSyncFrame OnUpdate
    if frame.alphaSyncFrame then
        frame.alphaSyncFrame:SetScript("OnUpdate", nil)
    end

    -- Hide and move to dormant cache for reuse
    if InCombatLockdown() and frame:IsProtected() then
        if frame:IsShown() then
            self._pendingVisibilityRefresh = true
        end
    else
        frame:Hide()
    end
    frame._triggerSoundInitialized = nil
    frame._triggerSoundWasVisible = nil
    self._dormantFrames = self._dormantFrames or {}
    self._dormantFrames[groupId] = frame
    self.groupFrames[groupId] = nil
    -- D3: frame left the live set — refresh the identity index (coalesced).
    self:RequestSpellButtonIndexRebuild("unload")
    if self.RefreshCursorAnchorTicker then
        self:RefreshCursorAnchorTicker()
    end
    if self.RefreshAlphaUpdateDriver then
        self:RefreshAlphaUpdateDriver()
    end
end

-- Recover a dormant frame: restore it to groupFrames, re-enable button
-- OnUpdate scripts, and recreate Masque group. Used by visibility-only
-- transitions to avoid recreating buttons.
function CooldownCompanion:RecoverDormantFrame(groupId)
    if not self._dormantFrames then return nil end
    local frame = self._dormantFrames[groupId]
    if not frame then return nil end

    self._dormantFrames[groupId] = nil
    self.groupFrames[groupId] = frame

    -- Restore button OnUpdate scripts
    if frame.buttons then
        for _, button in ipairs(frame.buttons) do
            if button._savedOnUpdate then
                button:SetScript("OnUpdate", button._savedOnUpdate)
                button._savedOnUpdate = nil
            end
        end
    end
    RefreshKeyPressHighlightFrame(frame)

    -- Recreate Masque group and re-add buttons
    local group = self.db.profile.groups[groupId]
    if group and group.masqueEnabled and self.Masque then
        self:CreateMasqueGroup(groupId)
        for _, button in ipairs(frame.buttons) do
            self:AddButtonToMasque(groupId, button)
        end
    end

    -- Restore alpha sync if this frame inherits alpha from a parent frame.
    -- Skip if anchor is pending re-evaluation — anchoredToParent may be stale
    -- and will be corrected when AnchorGroupFrame runs from the layout ticker.
    if frame.anchoredToParent and not frame._anchorDirty then
        self:SetupAlphaSync(frame, frame.anchoredToParent)
    end

    -- D3: frame re-entered the live set without repopulation — refresh the
    -- identity index (coalesced).
    self:RequestSpellButtonIndexRebuild("recover")

    return frame
end

-- Discard a dormant frame permanently (used by delete operations).
function CooldownCompanion:DiscardDormantFrame(groupId)
    if self._dormantFrames then
        local frame = self._dormantFrames[groupId]
        UnregisterKeyPressHighlightFrame(frame)
        if frame and frame.buttons and self.ReleaseAuraTextureVisual then
            for _, button in ipairs(frame.buttons) do
                self:ReleaseAuraTextureVisual(button)
            end
        end
        if frame and self.ReleaseGroupButtonPools then
            self:ReleaseGroupButtonPools(frame)
        end
        self._dormantFrames[groupId] = nil
    end
end

-- A1 shared per-pass input snapshot: the GCD state (spell 61304), the
-- assisted-highlight hostile-target gate, and the CDM viewer CVar -- the three
-- reads every button in a pass must see identically (D4 inventory A1). Extracted
-- so routed mini-passes (F1 3b) take the same once-per-batch snapshot the broad
-- walk uses. Deliberately does NOT touch _cooldownUpdatePassActive or
-- _passTimeStateSeen: a mini-pass must not set either (3b constraints 4-5), so
-- those stay in UpdateAllCooldowns below.
function CooldownCompanion:SnapshotCooldownPassContext()
    self._gcdInfo = C_Spell.GetSpellCooldown(61304)
    -- GCD activity: isActive is NeverSecret (12.0.1 hotfix)
    self._gcdActive = self._gcdInfo and self._gcdInfo.isActive or false
    -- Cache for GCD overlay display in CooldownUpdate (only when GCD is active)
    self._gcdDurationObj = self._gcdActive and C_Spell.GetSpellCooldownDuration(61304) or nil

    -- Assisted highlight target gate:
    -- hard target has priority; if none exists, allow soft enemy fallback.
    local hasHostileTarget = false
    if UnitExists("target") then
        hasHostileTarget = UnitCanAttack("player", "target") and true or false
    elseif UnitExists("softenemy") then
        hasHostileTarget = UnitCanAttack("player", "softenemy") and true or false
    end
    self._assistedHighlightHasHostileTarget = hasHostileTarget

    -- Cache CDM viewer CVar once per tick (avoids per-button GetCVarBool in ResolveBuffViewerFrameForSpell)
    self._cdmViewerEnabled = C_CVar_GetCVarBool("cooldownViewerEnabled") == true
end

function CooldownCompanion:UpdateAllCooldowns()
    local T = ST.RefreshTelemetry
    local telemetryOn = T and T.enabled
    local t0, frames, buttons
    if telemetryOn then
        t0 = debugprofilestop()
        frames, buttons = 0, 0
    end

    self:SnapshotCooldownPassContext()
    self._cooldownUpdatePassActive = true
    -- F2 idle skip: reset the per-pass time-animation flag. Any button that renders
    -- time-driven state this walk sets it true (NoteButtonTimeState); a walk that
    -- ends with it still false latches idle-eligible below. Fail open.
    self._passTimeStateSeen = false

    for groupId, frame in pairs(self.groupFrames) do
        if frame and frame.UpdateCooldowns and frame:IsShown() then
            frame:UpdateCooldowns()
            if telemetryOn then
                frames = frames + 1
                buttons = buttons + (frame.buttons and #frame.buttons or 0)
            end
        end
    end

    self._cooldownUpdatePassActive = nil
    -- F2 idle-skip eligibility: a completed full walk that saw no time-animated
    -- button latches idle-eligible. Only this line may latch it true; every
    -- other writer (NoteButtonTimeState) may only clear it to false. It is thus
    -- never older than the last completed walk. Maintained unconditionally (not
    -- gated on telemetry) so the live-skip predicate (CanSkipIdleTickerRefresh)
    -- can read it. Fail open.
    self._tickerIdleEligible = not self._passTimeStateSeen
    -- F2: any completed walk restarts the idle-skip safety clock (see
    -- TICKER_MAX_CONSECUTIVE_SKIPS). Covers every walk path, not just the ticker.
    self._tickerSkipStreak = 0
    if telemetryOn then
        local elapsed = debugprofilestop() - t0
        T:RecordPass(frames, buttons, elapsed)
    end
end

function CooldownCompanion:UpdateAllGroupLayouts()
    for groupId, frame in pairs(self.groupFrames) do
        if frame and frame:IsShown() then
            local protected = InCombatLockdown() and frame:IsProtected()
            if frame._strataDirty and not protected then
                self:RefreshGroupFrame(groupId)
            end
            if frame._sizeDirty then
                self:ResizeGroupFrame(groupId)
            end
            if frame._layoutDirty then
                self:UpdateGroupLayout(groupId)
            end
            if frame._anchorDirty and not protected then
                local group = self.db.profile.groups[groupId]
                if group then
                    self:AnchorGroupFrame(frame, group.anchor)
                end
            end
        end
    end
    -- Recover deferred container anchors
    if self.containerFrames then
        for containerId, frame in pairs(self.containerFrames) do
            if frame and frame:IsShown() and frame._anchorDirty then
                if not (InCombatLockdown() and frame:IsProtected()) then
                    local container = self.db.profile.groupContainers[containerId]
                    if container then
                        self:AnchorContainerFrame(frame, container.anchor)
                    end
                end
            end
        end
    end
end

-- Refresh all panel frames belonging to a container.
function CooldownCompanion:RefreshContainerPanels(containerId)
    for gid, group in pairs(self.db.profile.groups) do
        if group.parentContainerId == containerId then
            self:RefreshGroupFrame(gid)
        end
    end
end

-- Show or hide the drag handle on a container frame to match its lock state.
function CooldownCompanion:UpdateContainerDragHandle(containerId, locked)
    local cFrame = self.containerFrames and self.containerFrames[containerId]
    if cFrame and cFrame.dragHandle then
        local effectiveLocked = locked or self._combatForcedLock
        if effectiveLocked then
            if self.ClearContainerUnlockState then
                self:ClearContainerUnlockState(containerId)
            end
            SuppressFrameVisibilityForCombat(cFrame.dragHandle)
            SuppressFrameVisibilityForCombat(cFrame.dragHandle and cFrame.dragHandle.header or nil)
            SuppressFrameVisibilityForCombat(cFrame.coordLabel)
            SuppressFrameVisibilityForCombat(cFrame.nudger)
            if cFrame._containerPanelLabels then
                for _, label in pairs(cFrame._containerPanelLabels) do
                    SuppressFrameVisibilityForCombat(label)
                end
            end
        elseif self.RefreshContainerWrapper then
            self:RefreshContainerWrapper(containerId)
        else
            cFrame.dragHandle:Show()
        end
    end
end

function CooldownCompanion:LockAllFrames()
    -- Also lock any individually-unlocked panels
    for groupId, group in pairs(self.db.profile.groups) do
        if group.locked == false then
            group.locked = nil
        end
    end
    for groupId, frame in pairs(self.groupFrames) do
        if frame then
            self:UpdateGroupClickthrough(groupId)
            if self.SetGroupDragControlsShown then
                self:SetGroupDragControlsShown(frame, false)
            elseif frame.dragHandle then
                frame.dragHandle:Hide()
            end
        end
    end
    -- Lock container frames
    if self.containerFrames then
        for containerId in pairs(self.containerFrames) do
            self:UpdateContainerDragHandle(containerId, true)
        end
    end
    self:RefreshAllGroups()
end

function CooldownCompanion:UnlockAllFrames()
    -- Unlock containers only; individual panels retain their own lock state
    for groupId, frame in pairs(self.groupFrames) do
        if frame then
            self:UpdateGroupClickthrough(groupId)
            local group = self.db.profile.groups[groupId]
            local panelUnlocked = group
                and group.locked == false
                and not self._combatForcedLock
                and not (self.IsGroupCursorAnchored and self:IsGroupCursorAnchored(group))
            if panelUnlocked and self.SetGroupDragControlsShown then
                self:SetGroupDragControlsShown(frame, true)
            elseif panelUnlocked and frame.dragHandle then
                frame.dragHandle:Show()
            end
            if panelUnlocked then
                frame:SetAlpha(1)
            end
        end
    end
    -- Unlock container frames
    if self.containerFrames then
        for containerId in pairs(self.containerFrames) do
            local container = self.db.profile.groupContainers[containerId]
            self:UpdateContainerDragHandle(containerId, not container or container.locked)
        end
    end
    self:RefreshAllGroups()
end

-- TALENT NODE CACHE (for per-button talent conditions)
------------------------------------------------------------------------

function CooldownCompanion:GetHeroSubTreeRootNode(configID, treeID, heroSubTreeID)
    if not configID or not treeID or not heroSubTreeID then
        return nil, nil
    end

    local nodeIDs = C_Traits.GetTreeNodes(treeID)
    if not nodeIDs then
        return nil, nil
    end

    local bestNodeID, bestNodeInfo = nil, nil
    for _, nodeID in ipairs(nodeIDs) do
        local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
        if nodeInfo
            and nodeInfo.subTreeID == heroSubTreeID
            and nodeInfo.type ~= Enum.TraitNodeType.SubTreeSelection then
            if not bestNodeInfo
                or nodeInfo.posY < bestNodeInfo.posY
                or (nodeInfo.posY == bestNodeInfo.posY and nodeInfo.posX < bestNodeInfo.posX) then
                bestNodeID = nodeID
                bestNodeInfo = nodeInfo
            end
        end
    end

    return bestNodeID, bestNodeInfo
end

-- Rebuild the runtime talent node cache from the active talent config.
-- Called on TRAIT_CONFIG_UPDATED, PLAYER_ENTERING_WORLD, spec changes.
function CooldownCompanion:RebuildTalentNodeCache()
    if not self._talentNodeCache then
        self._talentNodeCache = {}
    else
        wipe(self._talentNodeCache)
    end

    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID then return end

    local specID = self._currentSpecId
    if not specID then return end

    local treeID = C_ClassTalents.GetTraitTreeForSpec(specID)
    if not treeID then return end

    local activeHeroSubTreeID = self._currentHeroSpecId or C_ClassTalents.GetActiveHeroTalentSpec()
    local heroRootNodeID = nil
    if activeHeroSubTreeID then
        heroRootNodeID = self:GetHeroSubTreeRootNode(configID, treeID, activeHeroSubTreeID)
    end

    local nodeIDs = C_Traits.GetTreeNodes(treeID)
    if not nodeIDs then return end

    for _, nodeID in ipairs(nodeIDs) do
        local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
        local includeNode = nodeInfo
            and nodeInfo.isVisible
            and nodeInfo.type ~= Enum.TraitNodeType.SubTreeSelection
            and (
                not nodeInfo.subTreeID
                or (
                    activeHeroSubTreeID
                    and nodeInfo.subTreeID == activeHeroSubTreeID
                    and (
                        nodeInfo.type == Enum.TraitNodeType.Selection
                        or nodeID == heroRootNodeID
                    )
                )
            )
        if includeNode then
            self._talentNodeCache[nodeID] = {
                activeRank = nodeInfo.activeRank or 0,
                activeEntryID = nodeInfo.activeEntry and nodeInfo.activeEntry.entryID or nil,
            }
        end
    end
end

-- Check whether per-button talent conditions are satisfied.
-- Returns true if no conditions set. All conditions use AND logic.
-- Missing nodes are treated as not taken.
function CooldownCompanion:IsTalentConditionMet(buttonData)
    local conditions = buttonData.talentConditions
    if not conditions or #conditions == 0 then return true end

    local needsNormalization = #conditions > 1 or IsLegacyChoiceRowCondition(conditions[1])
    if needsNormalization then
        local normalized, changed = self:NormalizeTalentConditions(conditions)
        if changed then
            buttonData.talentConditions = normalized
            conditions = normalized
            if not conditions or #conditions == 0 then return true end
        end
    end

    local cache = self._talentNodeCache
    if not cache then
        self:RebuildTalentNodeCache()
        cache = self._talentNodeCache
    end

    local function IsHeroSpecProxyCondition(cond)
        return type(cond) == "table"
            and cond.nodeID ~= nil
            and cond.heroSubTreeID ~= nil
            and cond.entryID == nil
            and type(cond.name) == "string"
            and type(cond.heroName) == "string"
            and cond.name == cond.heroName
    end

    for _, cond in ipairs(conditions) do
        if cond.classID and self._playerClassID and cond.classID ~= self._playerClassID then
            return false
        end

        if cond.specID and cond.specID ~= self._currentSpecId then
            return false
        end

        local activeHeroSubTreeID = nil
        if cond.heroSubTreeID then
            activeHeroSubTreeID = self._currentHeroSpecId or C_ClassTalents.GetActiveHeroTalentSpec()
        end

        if IsHeroSpecProxyCondition(cond) then
            local show = cond.show or "taken"
            local heroIsActive = activeHeroSubTreeID ~= nil and cond.heroSubTreeID == activeHeroSubTreeID
            if show == "not_taken" then
                if heroIsActive then
                    return false
                end
            else
                if not heroIsActive then
                    return false
                end
            end
        elseif cond.heroSubTreeID then
            if cond.heroSubTreeID ~= activeHeroSubTreeID then
                return false
            end
        end

        if not IsHeroSpecProxyCondition(cond) then
            local entry = cache and cache[cond.nodeID] or nil
            local isTaken = entry and entry.activeRank > 0 or false

            -- For choice nodes: if a specific entryID is required, verify it matches
            if isTaken and cond.entryID then
                isTaken = (entry.activeEntryID == cond.entryID)
            end

            local show = cond.show or "taken"
            if show == "not_taken" then
                if isTaken then return false end
            else
                if not isTaken then return false end
            end
        end
    end

    return true
end

-- Utility functions
function CooldownCompanion:GetSpellInfo(spellId)
    local spellInfo = C_Spell.GetSpellInfo(spellId)
    if spellInfo then
        return spellInfo.name, spellInfo.iconID, spellInfo.castTime
    end
    return nil
end

function CooldownCompanion:GetItemInfo(itemId)
    local itemName, _, _, _, _, _, _, _, _, itemIcon = C_Item.GetItemInfo(itemId)
    if not itemName then
        local _, _, _, _, icon = C_Item.GetItemInfoInstant(itemId)
        return nil, icon
    end
    return itemName, itemIcon
end
