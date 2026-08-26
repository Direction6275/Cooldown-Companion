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

local function GetUnlockedPanelAlpha(frame)
    return frame and frame._unlockGhost and 0.4 or 1
end

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

--- Return the per-spec order for a container, falling back to the
--- global .order field and then to the supplied default (typically the ID).
--- @param obj table  groupContainer with optional specOrders
--- @param specId number|nil  current specialization ID
--- @param default number|nil  fallback when no order exists
function CooldownCompanion:GetOrderForSpec(obj, specId, default)
    if obj.specOrders and specId then
        local so = obj.specOrders[specId]
        if so then return so end
    end
    return obj.order or default
end

--- Write a per-spec order value to a container.
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

function CooldownCompanion:IsPanelUnlockPreviewActive(groupOrGroupId)
    local group = groupOrGroupId
    if type(groupOrGroupId) == "number" then
        group = self.db.profile.groups[groupOrGroupId]
    end
    return group
        and group.locked == false
        and not self._combatForcedLock
        and not (self.IsGroupCursorAnchored and self:IsGroupCursorAnchored(group))
        or false
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

local ARRANGE_PANEL_SIZE_KEYS = {
    "buttonSize",
    "iconWidth",
    "iconHeight",
    "barLength",
    "barHeight",
}
local ARRANGE_TEXTURE_POSITION_KEYS = {
    "point",
    "relativePoint",
    "relativeTo",
    "x",
    "y",
    "buttonSize",
}

local function CopyArrangeTable(source)
    if type(source) ~= "table" then
        return nil
    end

    local copy = {}
    for key, value in pairs(source) do
        copy[key] = value
    end
    return copy
end

local function CaptureArrangeFields(source, keys)
    if type(source) ~= "table" then
        return nil
    end

    local record = { values = {}, present = {} }
    for _, key in ipairs(keys) do
        if rawget(source, key) ~= nil then
            record.values[key] = source[key]
            record.present[key] = true
        end
    end
    return record
end

local function RestoreArrangeTable(owner, key, record)
    if record == nil then
        owner[key] = nil
        return
    end

    local target = owner[key]
    if type(target) ~= "table" then
        target = {}
        owner[key] = target
    end
    for existingKey in pairs(target) do
        target[existingKey] = nil
    end
    for recordKey, value in pairs(record) do
        target[recordKey] = value
    end
end

local function RestoreArrangeFields(target, record, keys)
    for _, key in ipairs(keys) do
        if record.present[key] then
            target[key] = record.values[key]
        else
            target[key] = nil
        end
    end
end

function CooldownCompanion:CaptureArrangePanelRecord(groupId)
    local snapshot = self._arrangeSnapshot
    if not snapshot then
        return
    end

    local group = self.db.profile.groups[groupId]
    if not group then
        return
    end

    snapshot.panels[groupId] = {
        anchor = CopyArrangeTable(group.anchor),
        size = CaptureArrangeFields(group.style, ARRANGE_PANEL_SIZE_KEYS),
        texture = CaptureArrangeFields(group.textureSettings, ARRANGE_TEXTURE_POSITION_KEYS),
        signal = CaptureArrangeFields(
            group.triggerSettings and group.triggerSettings.signal,
            ARRANGE_TEXTURE_POSITION_KEYS
        ),
        locked = group.locked,
    }
end

function CooldownCompanion:CaptureArrangeContainerRecord(containerId)
    local snapshot = self._arrangeSnapshot
    if not snapshot then
        return
    end

    local container = self.db.profile.groupContainers[containerId]
    if not container then
        return
    end

    snapshot.containers[containerId] = {
        anchor = CopyArrangeTable(container.anchor),
        locked = container.locked,
    }
    for groupId, group in pairs(self.db.profile.groups) do
        if group.parentContainerId == containerId then
            self:CaptureArrangePanelRecord(groupId)
        end
    end
end

function CooldownCompanion:CaptureArrangeCastBarRecord()
    local snapshot = self._arrangeSnapshot
    if not snapshot then
        return
    end

    local settings = self.GetCastBarSettings and self:GetCastBarSettings()
    if not settings then
        snapshot.castBar = nil
        return
    end

    snapshot.castBar = {
        settings = settings,
        anchor = CopyArrangeTable(settings.independentAnchor),
        locked = settings.independentAnchorLocked,
        width = settings.independentWidth,
        height = settings.height,
    }
end

function CooldownCompanion:CaptureArrangeResourceRecord()
    local snapshot = self._arrangeSnapshot
    if not snapshot then
        return
    end

    local resourceBar = ST._RB
    local settings = resourceBar
        and resourceBar.GetResourceBarSettings
        and resourceBar.GetResourceBarSettings()
    local placementSettings = settings
        and resourceBar.GetSpecLayoutOrder
        and resourceBar.GetSpecLayoutOrder(settings)
    if not placementSettings then
        snapshot.resource = nil
        return
    end

    snapshot.resource = {
        settings = placementSettings,
        anchor = CopyArrangeTable(placementSettings.independentAnchor),
        locked = placementSettings.independentAnchorLocked,
        width = placementSettings.independentWidth,
        -- Thickness keys: which one is live flips with orientation, so both
        -- are captured and restored verbatim.
        barWidth = placementSettings.barWidth,
        barHeight = placementSettings.barHeight,
    }
end

function CooldownCompanion:CaptureArrangeSnapshot()
    self._arrangeSnapshot = {
        panels = {},
        containers = {},
    }

    for groupId in pairs(self.db.profile.groups) do
        self:CaptureArrangePanelRecord(groupId)
    end
    for containerId in pairs(self.db.profile.groupContainers or {}) do
        self:CaptureArrangeContainerRecord(containerId)
    end
    self:CaptureArrangeCastBarRecord()
    self:CaptureArrangeResourceRecord()
end

local function RestoreArrangeSnapshot(addon, snapshot)
    if not snapshot then
        return
    end

    for groupId, record in pairs(snapshot.panels or {}) do
        local group = addon.db.profile.groups[groupId]
        if group then
            RestoreArrangeTable(group, "anchor", record.anchor)
            if record.size then
                group.style = type(group.style) == "table" and group.style or {}
                RestoreArrangeFields(group.style, record.size, ARRANGE_PANEL_SIZE_KEYS)
            end
            if record.texture then
                group.textureSettings = type(group.textureSettings) == "table" and group.textureSettings or {}
                RestoreArrangeFields(group.textureSettings, record.texture, ARRANGE_TEXTURE_POSITION_KEYS)
            end
            if record.signal then
                group.triggerSettings = type(group.triggerSettings) == "table" and group.triggerSettings or {}
                group.triggerSettings.signal = type(group.triggerSettings.signal) == "table"
                    and group.triggerSettings.signal
                    or {}
                RestoreArrangeFields(group.triggerSettings.signal, record.signal, ARRANGE_TEXTURE_POSITION_KEYS)
            end
            group.locked = record.locked
        end
    end

    for containerId, record in pairs(snapshot.containers or {}) do
        local container = addon.db.profile.groupContainers[containerId]
        if container then
            RestoreArrangeTable(container, "anchor", record.anchor)
            container.locked = record.locked
            -- Push the restored anchor back onto the frame directly. The refresh
            -- pass below only re-anchors a container when normalization changes
            -- its anchor, and a restored anchor is already normalized, so nothing
            -- else moves the frame off the position the drag left it at. Panels
            -- anchor relative to their container, so they follow from here.
            local frame = addon.containerFrames and addon.containerFrames[containerId]
            if frame and type(container.anchor) == "table" then
                addon:AnchorContainerFrame(frame, container.anchor)
            end
        end
    end

    if snapshot.castBar and snapshot.castBar.settings then
        local record = snapshot.castBar
        RestoreArrangeTable(record.settings, "independentAnchor", record.anchor)
        record.settings.independentAnchorLocked = record.locked
        record.settings.independentWidth = record.width
        record.settings.height = record.height
    end
    if snapshot.resource and snapshot.resource.settings then
        local record = snapshot.resource
        RestoreArrangeTable(record.settings, "independentAnchor", record.anchor)
        record.settings.independentAnchorLocked = record.locked
        record.settings.independentWidth = record.width
        record.settings.barWidth = record.barWidth
        record.settings.barHeight = record.barHeight
    end

    addon:UnlockAllFrames()
    addon:ApplyCastBarSettings()
    addon:ApplyResourceBars()
    addon:RefreshAllAuraTextureVisuals()
    if addon.RefreshConfigPanel then
        addon:RefreshConfigPanel()
    end
    addon:CheckConfigReExpandAfterLock()
end

function CooldownCompanion:IsArrangeModeActive()
    return self._arrangeModeActive == true
end

function CooldownCompanion:IsAnyFrameUnlocked()
    for _, container in pairs(self.db.profile.groupContainers or {}) do
        if container.locked == false then
            return true
        end
    end

    for _, group in pairs(self.db.profile.groups or {}) do
        if group.locked == false then
            return true
        end
    end

    local castSettings = self.GetCastBarSettings and self:GetCastBarSettings()
    if castSettings
        and castSettings.enabled == true
        and castSettings.independentAnchorEnabled == true
        and not castSettings.independentAnchorLocked then
        return true
    end

    local resourceSettings = self.GetResourceBarSettings and self:GetResourceBarSettings()
    local resourceLayout = resourceSettings and self.GetSpecLayoutOrder and self:GetSpecLayoutOrder()
    if resourceSettings
        and resourceSettings.enabled == true
        and resourceLayout
        and resourceLayout.independentAnchorEnabled == true
        and not resourceLayout.independentAnchorLocked then
        return true
    end

    return false
end

function CooldownCompanion:CheckConfigReExpandAfterLock()
    if InCombatLockdown() or self._combatForcedLock then
        return
    end
    if self:IsAnyFrameUnlocked() then
        return
    end
    if ST.ExpandConfigAfterLock then
        ST.ExpandConfigAfterLock()
    end
end

function CooldownCompanion:CheckArrangeModeAutoExit()
    self:CheckConfigReExpandAfterLock()

    if not self:IsArrangeModeActive() then
        return
    end

    for containerId, container in pairs(self.db.profile.groupContainers or {}) do
        if self:IsContainerVisibleToCurrentChar(containerId)
            and container.locked == false then
            return
        end
    end

    local castSettings = self.GetCastBarSettings and self:GetCastBarSettings()
    if castSettings
        and castSettings.enabled == true
        and castSettings.independentAnchorEnabled == true
        and not castSettings.independentAnchorLocked then
        return
    end

    local resourceSettings = self.GetResourceBarSettings and self:GetResourceBarSettings()
    local resourceLayout = resourceSettings and self.GetSpecLayoutOrder and self:GetSpecLayoutOrder()
    if resourceSettings
        and resourceSettings.enabled == true
        and resourceLayout
        and resourceLayout.independentAnchorEnabled == true
        and not resourceLayout.independentAnchorLocked then
        return
    end

    self:ExitArrangeMode()
end

local function GetArrangeModePill(addon)
    if addon._arrangeModePill then
        return addon._arrangeModePill
    end

    local pill = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    pill:SetPoint("TOP", UIParent, "TOP", 0, -80)
    pill:SetFrameStrata("FULLSCREEN_DIALOG")
    pill:SetClampedToScreen(true)
    pill:SetMovable(true)
    pill:EnableMouse(true)
    pill:RegisterForDrag("LeftButton")
    pill:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    pill:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    -- Gold accents tie the pill to the snap guides shown while arranging.
    ST.CreatePixelBorders(pill, 1, 0.82, 0, 0.45)

    -- The top row lives in a fixed 30px band so the pill can grow downward
    -- when the group list expands.
    local title = pill:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", pill, "TOPLEFT", 10, -15)
    title:SetText("Panels unlocked")
    title:SetTextColor(1, 0.82, 0, 1)

    local helpButton = ST.CreateRuntimeInfoButton(pill, title, "LEFT", "RIGHT", 4, 0, function(tooltip)
        tooltip:AddLine("Panels unlocked")
        tooltip:AddLine(" ")
        tooltip:AddLine("Esc or Cancel reverts unsaved changes.", 1, 1, 1, false)
        tooltip:AddLine(" ")
        tooltip:AddLine("Done, a padlock, or /cdc lock saves.", 1, 1, 1, false)
        tooltip:AddLine(" ")
        tooltip:AddLine("Click a name to work on it alone.", 1, 1, 1, false)
        tooltip:AddLine(" ")
        tooltip:AddLine("Click it again to bring the others back.", 1, 1, 1, false)
        tooltip:AddLine(" ")
        tooltip:AddLine("Uncheck a row to hide its handles.", 1, 1, 1, false)
    end)
    ST.SetRuntimeInfoButtonShown(helpButton, true)

    local expander = CreateFrame("Button", nil, pill)
    expander:SetSize(16, 16)
    expander:SetPoint("LEFT", helpButton, "RIGHT", 2, 0)
    local expanderArrow = expander:CreateTexture(nil, "OVERLAY")
    expanderArrow:SetAllPoints()
    expanderArrow:SetAtlas("common-dropdown-icon-next")
    expanderArrow:SetVertexColor(1, 0.82, 0, 0.9)
    pill._expanderArrow = expanderArrow
    expander:SetScript("OnClick", function()
        pill._listExpanded = not pill._listExpanded or nil
        CooldownCompanion:RefreshArrangePillList()
    end)
    expander:SetScript("OnEnter", function()
        expanderArrow:SetVertexColor(1, 1, 1, 1)
    end)
    expander:SetScript("OnLeave", function()
        expanderArrow:SetVertexColor(1, 0.82, 0, 0.9)
    end)

    local doneButton = CreateFrame("Button", nil, pill, "BackdropTemplate")
    doneButton:SetSize(52, 20)
    doneButton:SetPoint("RIGHT", pill, "TOPRIGHT", -10, -15)
    doneButton:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    doneButton:SetBackdropColor(0.16, 0.16, 0.16, 1)
    ST.CreatePixelBorders(doneButton, 0.3, 0.85, 0.3, 0.7)
    local doneText = doneButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    doneText:SetPoint("CENTER")
    doneText:SetText("Done")
    doneText:SetTextColor(1, 1, 1, 1)

    local cancelButton = CreateFrame("Button", nil, pill, "BackdropTemplate")
    cancelButton:SetPoint("RIGHT", doneButton, "LEFT", -6, 0)
    cancelButton:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    cancelButton:SetBackdropColor(0.16, 0.16, 0.16, 1)
    ST.CreatePixelBorders(cancelButton, 0.9, 0.3, 0.3, 0.7)
    local cancelText = cancelButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cancelText:SetPoint("CENTER")
    cancelText:SetText("Cancel")
    cancelText:SetTextColor(1, 1, 1, 1)
    local cancelButtonWidth = math.ceil(cancelText:GetStringWidth() + 16)
    cancelButton:SetSize(cancelButtonWidth, 20)

    -- Top band: title [?] [>] ... [Cancel] [Done]. The list rows stack below.
    pill._baseWidth = math.ceil(10 + title:GetStringWidth() + 4 + 16 + 2 + 16 + 14 + cancelButtonWidth + 6 + 52 + 10)
    pill:SetSize(pill._baseWidth, 30)

    cancelButton:SetScript("OnClick", function()
        CooldownCompanion:CancelArrangeMode()
    end)
    cancelButton:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.3, 0.13, 0.13, 1)
    end)
    cancelButton:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.16, 0.16, 0.16, 1)
    end)

    doneButton:SetScript("OnClick", function()
        CooldownCompanion:ExitArrangeMode()
    end)
    doneButton:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.12, 0.26, 0.12, 1)
    end)
    doneButton:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.16, 0.16, 0.16, 1)
    end)

    pill:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        self._dragInProgress = true
        self:StartMoving()
    end)
    pill:SetScript("OnDragStop", function(self)
        self._dragInProgress = nil
        self:StopMovingOrSizing()
    end)
    pill:EnableMouseWheel(true)
    pill:SetScript("OnMouseWheel", function(self, delta)
        if not self._listExpanded or (self._listMaxScrollOffset or 0) == 0 then
            return
        end
        self._listScrollOffset = (self._listScrollOffset or 0) - delta
        CooldownCompanion:RefreshArrangePillList()
    end)
    pill:EnableKeyboard(true)
    pill:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            if not InCombatLockdown() then
                self:SetPropagateKeyboardInput(false)
            end
            CooldownCompanion:CancelArrangeMode()
        elseif not InCombatLockdown() then
            self:SetPropagateKeyboardInput(true)
        end
    end)
    pill:SetScript("OnShow", function(self)
        if not InCombatLockdown() then
            self:SetPropagateKeyboardInput(true)
        end
        CooldownCompanion:RefreshArrangePillList()
    end)
    pill:SetScript("OnHide", function(self)
        if self._dragInProgress then
            self._dragInProgress = nil
            self:StopMovingOrSizing()
        end
        GameTooltip:Hide()
    end)
    pill:Hide()

    addon._arrangeModePill = pill
    return pill
end

-- Rebuild the pill's group list: one row per arrange-managed group, sorted by
-- name. Row name click pins the group's controls (WS2 focus); the checkbox is
-- the session-only chrome filter. Collapsed, the pill is just the top band.
-- The unlock toolbar lists the independent bar movers next to the group
-- containers. They share the containers' session-only chrome-hidden map and
-- solo slot, keyed by the string ids "cast" and "resource" -- collision-free
-- beside numeric container ids.
function CooldownCompanion:IsArrangeSpecialMoverId(id)
    return id == "cast" or id == "resource"
end

function CooldownCompanion:RefreshArrangeSpecialMoverChrome(id)
    if id == "cast" then
        if self.RefreshIndependentCastBarMoverChrome then
            self:RefreshIndependentCastBarMoverChrome()
        end
    elseif id == "resource" then
        if self.RefreshIndependentResourceStackMoverChrome then
            self:RefreshIndependentResourceStackMoverChrome()
        end
    end
end

function CooldownCompanion:RefreshArrangePillList()
    local pill = self._arrangeModePill
    if not (pill and pill:IsShown()) then
        return
    end

    local ROW_HEIGHT = 18
    local rows = pill._rows
    if not rows then
        rows = {}
        pill._rows = rows
    end

    local entries = {}
    if self._arrangeModeActive then
        for containerId, container in pairs(self.db.profile.groupContainers or {}) do
            if container.locked == false
                and self:IsContainerVisibleToCurrentChar(containerId)
                and self:ContainerHasArrangeEligiblePanel(containerId) then
                entries[#entries + 1] = { id = containerId, name = container.name or ("Group " .. containerId) }
            end
        end
        local castSettings = self.GetCastBarSettings and self:GetCastBarSettings()
        if castSettings
            and castSettings.enabled == true
            and castSettings.independentAnchorEnabled == true
            and not castSettings.independentAnchorLocked then
            entries[#entries + 1] = { id = "cast", name = "Cast Bar" }
        end
        local rbSettings = self.GetResourceBarSettings and self:GetResourceBarSettings()
        local rbPlacement = rbSettings and self.GetSpecLayoutOrder and self:GetSpecLayoutOrder()
        if rbSettings
            and rbSettings.enabled == true
            and rbPlacement
            and rbPlacement.independentAnchorEnabled == true
            and not rbPlacement.independentAnchorLocked then
            entries[#entries + 1] = { id = "resource", name = "Resource Bars" }
        end
        table.sort(entries, function(a, b)
            if a.name == b.name then
                -- Mixed id types: special movers use string ids.
                return tostring(a.id) < tostring(b.id)
            end
            return a.name < b.name
        end)
    end

    local expanded = pill._listExpanded == true and #entries > 0
    if pill._expanderArrow then
        pill._expanderArrow:SetRotation(expanded and -math.pi / 2 or 0)
    end

    -- Cap the viewport so a large roster cannot push rows off screen; the
    -- overflow scrolls with the mouse wheel.
    local MAX_VISIBLE_ROWS = 12
    local maxOffset = math.max(0, #entries - MAX_VISIBLE_ROWS)
    local scrollOffset = pill._listScrollOffset or 0
    if scrollOffset > maxOffset then
        scrollOffset = maxOffset
    end
    if scrollOffset < 0 then
        scrollOffset = 0
    end
    pill._listScrollOffset = scrollOffset
    pill._listMaxScrollOffset = maxOffset
    local visibleCount = math.min(#entries, MAX_VISIBLE_ROWS)

    local function EnsureRow(index)
        local row = rows[index]
        if row then
            return row
        end

        row = CreateFrame("Button", nil, pill)
        row:SetHeight(ROW_HEIGHT)

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(1, 0.82, 0, 0.12)
        row.bg:Hide()

        row.check = CreateFrame("Button", nil, row, "BackdropTemplate")
        row.check:SetSize(12, 12)
        row.check:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.check:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
        row.check:SetBackdropColor(0.16, 0.16, 0.16, 1)
        ST.CreatePixelBorders(row.check)
        row.check.fill = row.check:CreateTexture(nil, "OVERLAY")
        row.check.fill:SetSize(6, 6)
        row.check.fill:SetPoint("CENTER")
        row.check.fill:SetColorTexture(1, 0.82, 0, 0.9)
        row.check:SetScript("OnClick", function()
            if row.containerId then
                -- Toggle the MANUAL flag the checkbox renders; the effective
                -- state also folds in solo and would misread during one.
                local hiddenSet = CooldownCompanion._arrangeChromeHidden
                local manuallyHidden = hiddenSet ~= nil and hiddenSet[row.containerId] == true
                CooldownCompanion:SetContainerArrangeChromeHidden(row.containerId, not manuallyHidden)
                CooldownCompanion:RefreshArrangePillList()
            end
        end)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.name:SetPoint("LEFT", row.check, "RIGHT", 6, 0)
        row.name:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)

        row:SetScript("OnClick", function()
            local id = row.containerId
            if not id then
                return
            end
            local hiddenSet = CooldownCompanion._arrangeChromeHidden
            if hiddenSet and hiddenSet[id] == true then
                return
            end
            if CooldownCompanion._arrangeSoloContainerId == id then
                CooldownCompanion:SetArrangeSoloContainer(nil)
            else
                CooldownCompanion:SetArrangeSoloContainer(id)
            end
        end)
        row:SetScript("OnEnter", function(self)
            if not self._selected then
                self.bg:SetColorTexture(1, 1, 1, 0.06)
                self.bg:Show()
            end
        end)
        row:SetScript("OnLeave", function(self)
            if not self._selected then
                self.bg:Hide()
            end
        end)

        rows[index] = row
        return row
    end

    local maxNameWidth = 0
    for index = 1, visibleCount do
        local entry = entries[scrollOffset + index]
        local row = EnsureRow(index)
        row.containerId = entry.id
        row.name:SetText(entry.name)

        -- The checkbox mirrors the MANUAL flag; the gray name mirrors the
        -- effective state, so a solo grays the others without unticking them.
        local hiddenSet = self._arrangeChromeHidden
        local manuallyHidden = hiddenSet ~= nil and hiddenSet[entry.id] == true
        local hidden = self:IsContainerArrangeChromeHidden(entry.id)
        row.check.fill:SetShown(not manuallyHidden)
        row.name:SetTextColor(hidden and 0.55 or 1, hidden and 0.55 or 1, hidden and 0.55 or 1, 1)

        row._selected = self._arrangeFocusContainerId == entry.id and not hidden or nil
        if row._selected then
            row.bg:SetColorTexture(1, 0.82, 0, 0.12)
            row.bg:Show()
        elseif row:IsMouseOver() then
            row.bg:SetColorTexture(1, 1, 1, 0.06)
            row.bg:Show()
        else
            row.bg:Hide()
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", pill, "TOPLEFT", 8, -(30 + (index - 1) * ROW_HEIGHT))
        row:SetPoint("TOPRIGHT", pill, "TOPRIGHT", -8, -(30 + (index - 1) * ROW_HEIGHT))
        row:SetShown(expanded)

        local nameWidth = row.name:GetStringWidth() or 0
        if nameWidth > maxNameWidth then
            maxNameWidth = nameWidth
        end
    end

    for index = visibleCount + 1, #rows do
        rows[index].containerId = nil
        rows[index]:Hide()
    end

    if expanded then
        pill:SetSize(
            math.max(pill._baseWidth or 200, math.ceil(8 + 2 + 12 + 6 + maxNameWidth + 2 + 8 + 12)),
            30 + visibleCount * ROW_HEIGHT + 6
        )
    else
        pill:SetSize(pill._baseWidth or 200, 30)
    end
end

local function CancelActiveMoverDrag(addon, frame, activeField)
    if not (frame and frame[activeField]) then
        return
    end

    frame._dragCancelPending = true
    if not (InCombatLockdown() and frame:IsProtected()) then
        frame:StopMovingOrSizing()
    end
    if addon.EndDragSnapSession then
        addon:EndDragSnapSession(frame, false)
    end
    frame[activeField] = nil
end

local function CancelActiveMoverGestures(addon)
    if addon.ResetMoverChromeFade then
        addon:ResetMoverChromeFade()
    end
    if addon.CancelIndependentCastBarDrag then
        addon:CancelIndependentCastBarDrag()
    end
    if addon.CancelIndependentResourceStackDrag then
        addon:CancelIndependentResourceStackDrag()
    end

    for _, frame in pairs(addon.groupFrames or {}) do
        CancelActiveMoverDrag(addon, frame, "_dragInProgress")
        for _, button in ipairs(frame.buttons or {}) do
            CancelActiveMoverDrag(addon, button and button.auraTextureHost, "_isDragging")
        end
    end

    for _, frame in pairs(addon.containerFrames or {}) do
        CancelActiveMoverDrag(addon, frame, "_dragInProgress")
    end
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

    if self._arrangeModePill then
        self._arrangeModePill:Hide()
    end
    CancelActiveMoverGestures(self)
    -- Combat hands cursor panels back to the real cursor: the arrange pin
    -- (and any config selection preview) suspends for the fight. The
    -- forced-lock flag above makes this a full clear, not a demote.
    if self.ClearCursorAnchorLayoutPreview then
        self:ClearCursorAnchorLayoutPreview()
    end

    for groupId, frame in pairs(self.groupFrames or {}) do
        local group = self.db and self.db.profile and self.db.profile.groups and self.db.profile.groups[groupId]
        frame._containerUnlockPreviewActive = nil
        frame._panelUnlockPreviewActive = nil
        frame._unlockGhost = nil
        local active = group and self:IsGroupActive(groupId, {
            group = group,
            checkCharVisibility = true,
            checkLoadConditions = true,
            requireButtons = true,
        }) or false

        frame._combatForcedHidden = not active or nil
        SuppressFrameVisibilityForCombat(frame.dragHandle)
        SuppressFrameVisibilityForCombat(frame.coordLabel)
        SuppressFrameVisibilityForCombat(frame.dragHelpButton)
        SuppressFrameVisibilityForCombat(frame.nudger)
        -- The chrome just came down without going through
        -- SetGroupDragControlsShown, so explicitly remove the Aura Panel's
        -- frame-owned placeholder preview too. The live aura display stays
        -- bound and resumes for the fight; no rebind is possible in combat.
        self:SetAuraPanelPlaceholderPreviewShown(frame, false)
        ForceCombatMouseLock(frame)
        ForceCombatMouseLock(frame.dragHandle)
        ForceCombatMouseLock(frame.dragHelpButton)
        ForceCombatMouseLock(frame.nudger)
        for _, button in ipairs(frame.buttons or {}) do
            local buttonData = button and button.buttonData
            if CooldownCompanion:IsAuraShellEntry(buttonData) then
                ST._ApplyShellVisualsForButton(button, buttonData)
            end
            local host = button and button.auraTextureHost or nil
            if host then
                host._unlockGhost = nil
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
        -- Restore the placeholder preview immediately. Container Arrange Mode
        -- previews every member even though only the selected member has drag
        -- controls; RefreshAllGroups below re-asserts the same state.
        local group = frame.groupId and self.db.profile.groups[frame.groupId]
        local containerPreviewActive = group and group.parentContainerId
            and self:IsContainerUnlockPreviewActive(group.parentContainerId)
            or false
        local handleShown = (frame.dragHandle and frame.dragHandle:IsShown()) == true
        self:SetAuraPanelPlaceholderPreviewShown(frame, handleShown or containerPreviewActive)
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

    local arrangeModeActive = self._arrangeModeActive == true
    local castSettings = self.GetCastBarSettings and self:GetCastBarSettings()
    local restoreCastMover = arrangeModeActive
        or (castSettings
            and castSettings.enabled == true
            and castSettings.independentAnchorEnabled == true
            and not castSettings.independentAnchorLocked)
    if restoreCastMover and self.ApplyCastBarSettings then
        self:ApplyCastBarSettings()
    end

    local resourceSettings = self.GetResourceBarSettings and self:GetResourceBarSettings()
    local resourceLayout = resourceSettings
        and self.GetSpecLayoutOrder
        and self:GetSpecLayoutOrder()
    local restoreResourceMover = arrangeModeActive
        or (resourceSettings
            and resourceSettings.enabled == true
            and resourceLayout
            and resourceLayout.independentAnchorEnabled == true
            and not resourceLayout.independentAnchorLocked)
    if restoreResourceMover and self.ApplyResourceBars then
        self:ApplyResourceBars()
    end

    if self._arrangeModeActive and self._arrangeModePill then
        self._arrangeModePill:Show()
    end
    -- Re-park cursor panels on the dummy cursor for the rest of the
    -- arrange session (the pin suspended on combat entry).
    if self._arrangeModeActive and self.ShowCursorAnchorLayoutPreview then
        self:ShowCursorAnchorLayoutPreview(nil)
    end

    return snapshot
end

function CooldownCompanion:IsGroupVisibleInUnlockPreview(groupId, opts)
    opts = opts or {}

    local group = opts.group or self.db.profile.groups[groupId]
    if not group then
        return false
    end

    if opts.panelUnlockPreview then
        if not self:IsPanelUnlockPreviewActive(group) then
            return false
        end
    else
        if not group.parentContainerId then
            return false
        end

        local container = opts.container or self:GetParentContainer(group)
        if not opts.assumeContainerUnlocked and not self:IsContainerUnlockPreviewActive(container) then
            return false
        end
    end

    -- An Aura Panel joins the Rotation Assistant in skipping the entry checks:
    -- both are placed and sized before they have entries (the Aura Panel keeps a
    -- reserved one-cell footprint for exactly this), so "no saved entry" must
    -- not mean "not on screen to arrange".
    local skipEntryChecks = self:IsRotationAssistantGroup(group) or ST.IsAuraPanelGroup(group)
    if not skipEntryChecks and not (group.buttons and #group.buttons > 0) then
        return false
    end
    if not skipEntryChecks and not self:GroupHasUsableButtons(group, {
        checkLoadConditions = false,
    }) then
        return false
    end

    local groupFrame = opts.groupFrame
    if groupFrame == nil and groupId then
        groupFrame = self.groupFrames and self.groupFrames[groupId] or nil
    end
    -- Same exemption on the runtime side. An Aura Panel renders its entries
    -- through its own aura container and materializes no CC buttons at all, so
    -- an empty button list is its normal state rather than the "nothing
    -- rendered yet" signal this check reads it as everywhere else.
    -- The same emptiness, one cluster at a time. A MIXED panel whose entries all
    -- sit in aura sections materializes no CC button either, so its frame reads
    -- empty while those sections still own a rectangle to arrange. Only the
    -- FRAME check is exempted: the data checks above stay in force, because
    -- those entries are saved entries and answer them honestly.
    if groupFrame
        and not skipEntryChecks
        and not ST.PanelHasAuraSection(group)
        and (not groupFrame.buttons or #groupFrame.buttons == 0) then
        return false
    end

    local checkCharVisibility = opts.checkCharVisibility
    if checkCharVisibility == nil then
        checkCharVisibility = true
    end
    if checkCharVisibility and groupId and not self:IsGroupVisibleToCurrentChar(groupId) then
        return false
    end

    if not opts.panelUnlockPreview then
        if self.IsGroupEligibilityMet and not self:IsGroupEligibilityMet(group) then
            return false
        end

        local effectiveSpecs, _, hasSpecFilter = self:GetEffectiveSpecs(group)
        if hasSpecFilter then
            if not (self._currentSpecId and effectiveSpecs[self._currentSpecId]) then
                return false
            end
        end
    end

    return true
end

-- Cursor-anchored panels have no stable position (they ride the live cursor,
-- or park on the dummy cursor while pinned), so they never join the container
-- mover's footprint: no wrapper stretch, no member overlay, no arrange
-- selection. Their offset is edited through the dummy-cursor preview instead.
function CooldownCompanion:GetContainerUnlockPreviewPanels(containerId, panels)
    local previewPanels = {}
    local panelList = panels or self:GetPanels(containerId)
    for _, panelInfo in ipairs(panelList) do
        if not self:IsGroupCursorAnchored(panelInfo.group)
            and self:IsGroupVisibleInUnlockPreview(panelInfo.groupId, {
                group = panelInfo.group,
                checkCharVisibility = true,
            }) then
            previewPanels[#previewPanels + 1] = panelInfo
        end
    end
    return previewPanels
end

function CooldownCompanion:ContainerHasArrangeEligiblePanel(containerId)
    for _, panelInfo in ipairs(self:GetPanels(containerId)) do
        if not self:IsGroupCursorAnchored(panelInfo.group)
            and self:IsGroupVisibleInUnlockPreview(panelInfo.groupId, {
                group = panelInfo.group,
                checkCharVisibility = true,
                assumeContainerUnlocked = true,
            }) then
            return true
        end
    end
    return false
end

function CooldownCompanion:GetEffectiveSpecs(group)
    if not group then return nil, false end

    local sources = {}
    local container = self:GetParentContainer(group)
    if container then
        AddEntityEffectiveSpecSource(sources, container, true)
        AddEntityEffectiveSpecSource(sources, group, false)
    else
        AddEntityEffectiveSpecSource(sources, group, false)
    end

    return ResolveEffectiveSources(sources)
end

function CooldownCompanion:GetInheritedEffectiveSpecs(group)
    if not group then return nil, false end

    local sources = {}
    local container = self:GetParentContainer(group)
    if container then
        AddEntityEffectiveSpecSource(sources, container, true)
    end

    return ResolveEffectiveSources(sources)
end

function CooldownCompanion:GetEffectiveHeroTalents(group)
    if not group then return nil, false end

    local sources = {}

    local container = self:GetParentContainer(group)
    if container then
        AddEffectiveSource(sources, container.heroTalents, true, NormalizeSpecKey)
        AddEffectiveSource(sources, group.heroTalents, false, NormalizeSpecKey)
    else
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

local function IsHeroSpecProxyCondition(cond)
    return type(cond) == "table"
        and cond.nodeID ~= nil
        and cond.heroSubTreeID ~= nil
        and cond.entryID == nil
        and type(cond.name) == "string"
        and type(cond.heroName) == "string"
        and cond.name == cond.heroName
end

ST._IsHeroSpecProxyCondition = IsHeroSpecProxyCondition

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

    local count = 0
    for _, buttonData in ipairs(group.buttons) do
        if self:IsButtonUsable(buttonData, group, buttonUsabilityOptions) then
            count = count + 1
        end
    end
    return count
end

-- Ordered identity of the entries an Aura Panel currently reserves cells for.
--
-- An Aura Panel materializes no CC buttons, so the entry-identity comparison
-- every other group makes against frame.buttons has nothing to read. This string
-- stands in for that list: PopulateGroupButtons stamps it on the frame, and
-- GroupButtonSetNeedsRebuild diffs against it on the next availability sweep so
-- the panel keeps a refresh trigger of its own.
--
-- Walked over group.buttons with the SAME predicate and the SAME options
-- GetGroupLayoutButtonCount uses -- which is how GetAuraPanelGridMetrics counts
-- cells -- so the signature and the cell count can never disagree about which
-- entries are in.
--
-- ORDER carries the identity and the count does not: two mutually exclusive
-- talent auras can swap with the entry count unchanged, and the panel still has
-- to repopulate and rebind.
--
-- Identity per entry is _auraKey, which is the same string the aura engine keys
-- the panel's aura groups by -- so two entries this signature calls the same are
-- two entries the bind pass would also collapse into one. Entries with no key
-- (pre-subtype or hand-edited data, which the bind pass parks) still occupy a
-- cell, so they are carried under a distinct prefix by type and id rather than
-- dropped: a keyless entry coming or going still moves the footprint.
local function AppendAuraEntryToken(signature, buttonData)
    local auraKey = buttonData._auraKey
    if auraKey then
        return signature .. "\031k" .. tostring(auraKey)
    end
    return signature .. "\031?"
        .. tostring(buttonData.type) .. ":" .. tostring(buttonData.id)
end

function CooldownCompanion:GetAuraPanelEntrySignature(group, buttonUsabilityOptions)
    if not (group and group.buttons) then
        return ""
    end

    local signature = ""
    for _, buttonData in ipairs(group.buttons) do
        if self:IsButtonUsable(buttonData, group, buttonUsabilityOptions) then
            signature = AppendAuraEntryToken(signature, buttonData)
        end
    end
    return signature
end

-- The same string for a MIXED panel, scoped to the entries that render through
-- an aura SECTION. Those entries materialize no CC button either, so the
-- frame.buttons comparison GroupButtonSetNeedsRebuild makes for every ordinary
-- panel cannot see them -- and it must not try, or a panel with one aura section
-- would report "needs rebuild" on every availability sweep forever. Filtering
-- them out of that comparison deletes their refresh trigger, exactly the way a
-- flat false once deleted the Aura Panel's; this restores it.
--
-- Empty for a panel with no aura section, so an ordinary panel stores and
-- compares nothing.
function CooldownCompanion:GetAuraSectionEntrySignature(group, buttonUsabilityOptions)
    if not (group and group.buttons and ST.PanelHasAuraSection(group)) then
        return ""
    end

    local signature = ""
    for _, buttonData in ipairs(group.buttons) do
        if ST.IsAuraSectionEntry(group, buttonData)
            and self:IsButtonUsable(buttonData, group, buttonUsabilityOptions) then
            signature = AppendAuraEntryToken(signature, buttonData)
        end
    end
    return signature
end

local UNLOCK_PREVIEW_BUTTON_USABILITY_OPTIONS = {
    checkLoadConditions = false,
}

function CooldownCompanion:GetGroupButtonUsabilityOptions(groupId, group)
    local frame = groupId and self.groupFrames and self.groupFrames[groupId]
    if frame
        and (frame._containerUnlockPreviewActive == true
            or frame._panelUnlockPreviewActive == true) then
        return UNLOCK_PREVIEW_BUTTON_USABILITY_OPTIONS
    end

    return nil
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
    if container and not opts.ignoreUnlockPreview and self:IsContainerUnlockPreviewActive(container) then
        return self:IsGroupVisibleInUnlockPreview(groupId, {
            group = group,
            container = container,
            checkCharVisibility = opts.checkCharVisibility,
        })
    end
    if not opts.ignoreUnlockPreview and self:IsPanelUnlockPreviewActive(group) then
        return self:IsGroupVisibleInUnlockPreview(groupId, {
            group = group,
            panelUnlockPreview = true,
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

local GetClassKeyFromClassID = ST._GetResourceBarClassKeyFromClassID
local GetClassIDFromClassKey = ST._GetClassIDFromResourceBarClassKey

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
    -- An Aura Panel is never an anchor target (owner ruling 2026-08-15). Its
    -- height is whatever the active auras happen to need right now, so anything
    -- stacked off its edge would chase the aura churn. Structural, not a stored
    -- anchorEligible = false: an imported or hand-edited profile can undo a data
    -- write, and this predicate is what every consumer asks.
    --
    -- The rule now also lives on CanGroupBeExternalAnchorTarget (AnchorPolicy),
    -- which the branch above prefers and which covers MANUAL targets too. Kept
    -- here as well because the `elseif` fallback runs when that predicate is
    -- missing, and this list may not lose the rule with it.
    if ST.IsAuraPanelGroup(group) then return false end
    if group.anchorEligible == false then return false end
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
    local specId = self._currentSpecId

    local orderedContainers = {}
    for cid, container in pairs(containers) do
        orderedContainers[#orderedContainers + 1] = {
            id = cid,
            order = self:GetOrderForSpec(container, specId, cid),
        }
    end
    table.sort(orderedContainers, function(a, b)
        if a.order ~= b.order then
            return a.order < b.order
        end

        local aId = tonumber(a.id)
        local bId = tonumber(b.id)
        if aId and bId and aId ~= bId then
            return aId < bId
        end
        return tostring(a.id) < tostring(b.id)
    end)

    for _, containerInfo in ipairs(orderedContainers) do
        for _, panelInfo in ipairs(self:GetPanels(containerInfo.id)) do
            if self:IsGroupAvailableForAnchoring(panelInfo.groupId) then
                return panelInfo.groupId
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

function CooldownCompanion:IsResourceBarAnchorIndependent()
    local settings = self.GetResourceBarSettings and self:GetResourceBarSettings() or nil
    return IsResourceBarIndependentAnchor(settings, self._currentSpecId)
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
    local groupedPanels = {}
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
            local contName = ctr and ctr.name or "Group"
            local containerBucket = groupedPanels[cid]
            if not containerBucket then
                containerBucket = {
                    id = cid,
                    name = contName,
                    order = self:GetOrderForSpec(ctr or {}, self._currentSpecId, cid),
                    panels = {},
                }
                groupedPanels[cid] = containerBucket
            end
            table.insert(containerBucket.panels, {
                id = groupId,
                key = tostring(groupId),
                name = group.name or ("Panel " .. groupId),
                contName = contName,
                order = group.order or groupId,
            })
        end
    end

    local sortedContainers = {}
    for _, container in pairs(groupedPanels) do
        table.insert(sortedContainers, container)
    end
    table.sort(sortedContainers, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.name < b.name
    end)
    for _, container in ipairs(sortedContainers) do
        local containerHdrKey = "_panel_ctr_" .. tostring(container.id)
        dropdown:AddItem(containerHdrKey, "|cffffd100" .. container.name .. "|r")
        dropdown:SetItemDisabled(containerHdrKey, true)

        table.sort(container.panels, function(a, b)
            if a.order ~= b.order then return a.order < b.order end
            return a.name < b.name
        end)
        for _, panel in ipairs(container.panels) do
            dropdown:AddItem(panel.key, "   " .. panel.name)
            dropdown.list[panel.key] = panel.contName .. ": " .. panel.name
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
    -- Group/panel scopes default this on; entry scopes default it off.
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

local function IsContainerGlobalScope(container)
    return type(container) == "table" and container.isGlobal == true
end

function CooldownCompanion:GetInheritedLoadConditionSources(group)
    local sources = {}
    local db = self.db and self.db.profile
    if not (db and group) then return sources end

    local container = self:GetParentContainer(group)
    if container then
        AddLoadConditionSource(sources, "Group", container, LOAD_CONDITION_DEFAULTS, IsContainerGlobalScope(container))
        return sources
    end
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
    -- An Aura Panel's button list is empty by design, so the entry-count
    -- comparison below would report "needs rebuild" forever: one such panel
    -- would force a full refresh of EVERY group on every availability pass.
    -- Answering a flat false instead deleted the panel's OWN refresh trigger --
    -- nothing re-ran population when a talent or load-condition change altered
    -- WHICH entries are usable, so the footprint, the unlock placeholders and
    -- the aura rebind all went stale. Compare the ordered entry signature
    -- PopulateGroupButtons stamped on the frame instead. It holds still for a
    -- panel whose entries did not change -- so the every-sweep refresh storm the
    -- flat false was guarding against stays prevented -- and differs the moment
    -- they do, including a same-count swap between two mutually exclusive talent
    -- auras, which no count comparison could see.
    if ST.IsAuraPanelGroup(group) then
        -- Resolved exactly the way PopulateGroupButtons resolves it, so an
        -- unlock preview (which relaxes load conditions for the stored
        -- signature) cannot make stored and current disagree on every sweep.
        local buttonUsabilityOptions = opts.buttonUsabilityOptions
            or self:GetGroupButtonUsabilityOptions(groupId, group)
        -- A frame that has never been populated carries no signature. Reading
        -- that as the empty signature mirrors the non-aura path below exactly:
        -- an empty button list needs a rebuild when there are usable entries,
        -- and does not when there are none.
        return (frame._auraPanelEntrySig or "")
            ~= self:GetAuraPanelEntrySignature(group, buttonUsabilityOptions)
    end
    if not group.buttons then
        return #frame.buttons > 0
    end

    local usableButtons = {}
    local usableCount = 0
    local buttonUsabilityOptions = opts.buttonUsabilityOptions
    -- Aura-section members leave both sides of the comparison below: they never
    -- materialize a button, so counting them would report "needs rebuild" every
    -- sweep. Their identity rides the signature instead, diffed here first so a
    -- talent swap inside a section still triggers the rebuild the button
    -- comparison can no longer see.
    local auraSectionPanel = ST.PanelHasAuraSection(group)
    if auraSectionPanel then
        local options = buttonUsabilityOptions
            or self:GetGroupButtonUsabilityOptions(groupId, group)
        if (frame._auraSectionEntrySig or "")
            ~= self:GetAuraSectionEntrySignature(group, options) then
            return true
        end
    end
    for _, buttonData in ipairs(group.buttons) do
        if self:IsButtonUsable(buttonData, group, buttonUsabilityOptions)
            and not (auraSectionPanel and ST.IsAuraSectionEntry(group, buttonData)) then
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
                button._chargeDurationObj = nil
                -- _totemSwipeStyleActive stays: it owes the swipe-style restore
                -- and the next pass runs the falling edge (see GroupFrame).
                button._totemActive = nil
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
                frame.layoutButtonCount = self:GetGroupLayoutButtonCount(groupId, group)
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
            if self:IsContainerVisibleToCurrentChar(containerId) then
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
        if not visible then
            self:UnloadGroup(groupId)
        elseif self:IsGroupActive(groupId, {
            group = group,
            checkCharVisibility = false,
            checkLoadConditions = true,
            requireButtons = false,
        }) then
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
        if not visible then
            self:UnloadGroup(groupId)
        else
            local active = self:IsGroupActive(groupId, {
                group = group,
                checkCharVisibility = true,
                checkLoadConditions = true,
                requireButtons = true,
            })

            if not active then
                self:UnloadGroup(groupId)
            else
                local frame = self.groupFrames[groupId]
                if frame and self:GroupButtonSetNeedsRebuild(groupId, group) then
                    self:RefreshGroupFrame(groupId)
                    frame = self.groupFrames[groupId]
                elseif not frame then
                    if self:GroupButtonSetNeedsRebuild(groupId, group) then
                        -- Recover the shell and repopulate it rather than
                        -- discarding it: frames cannot be destroyed, so a
                        -- discard leaks the whole tree (buttons, cooldowns and
                        -- their irremovable aura slot containers) and leaves a
                        -- second frame answering to the same global name, which
                        -- the by-name anchor checks then match against.
                        -- RefreshGroupFrame recovers the dormant shell into
                        -- groupFrames and repopulates its children.
                        self:RefreshGroupFrame(groupId)
                        frame = self.groupFrames[groupId]
                    else
                        -- Recover dormant frame with buttons intact (no repopulation needed)
                        frame = self:RecoverDormantFrame(groupId)
                    end
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
                    local isLocked = not (
                        frame._containerUnlockPreviewActive == true
                        or frame._panelUnlockPreviewActive == true
                    )
                    if self.IsGroupCursorAnchored and self:IsGroupCursorAnchored(group) then
                        isLocked = true
                    end
                    -- Keep unlocked panels fully visible, except unlock ghosts.
                    if not isLocked then
                        frame:SetAlpha(GetUnlockedPanelAlpha(frame))
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

-- Fully unload a group: save/clear button OnUpdate scripts, clear runtime
-- state, hide the frame, and move it to a dormant cache for reuse. Config
-- data (db.profile.groups) is preserved so the group can reload when load
-- conditions change. Buttons remain attached to the frame so visibility-only
-- transitions can reuse them without creating new C-side frame objects, and
-- Masque registration is left intact for the same reason -- it is torn down
-- in DiscardDormantFrame, the true-teardown path.
function CooldownCompanion:UnloadGroup(groupId)
    local frame = self.groupFrames[groupId]
    if not frame then return end
    UnregisterKeyPressHighlightFrame(frame)

    -- Save and clear button OnUpdate scripts.
    -- Buttons stay attached to the frame for potential reuse.
    if frame.buttons then
        for _, button in ipairs(frame.buttons) do
            if self.HideAuraTextureVisual then
                self:HideAuraTextureVisual(button)
            end
            local onUpdate = button:GetScript("OnUpdate")
            if onUpdate then
                button._savedOnUpdate = onUpdate
                button:SetScript("OnUpdate", nil)
            end
        end
    end

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
    -- Native aura sounds are Blizzard-side registrations keyed on unit+spell,
    -- not on this frame, so parking the panel does not stop them: a hidden
    -- panel keeps alerting until a pass parks its records. Same reason the
    -- delete paths rebind.
    self:RequestAuraRebind("unload")
    if self.RefreshCursorAnchorTicker then
        self:RefreshCursorAnchorTicker()
    end
    if self.RefreshAlphaUpdateDriver then
        self:RefreshAlphaUpdateDriver()
    end
end

-- Recover a dormant frame: restore it to groupFrames and re-enable button
-- OnUpdate scripts. Used by visibility-only transitions to avoid recreating
-- buttons.
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

    -- Masque registration survives dormancy, so reconcile it in both directions:
    -- rebuild it when the group should be skinned but isn't, and release it when
    -- the group stopped being skinned while the frame was parked. The second case
    -- matters because writers that bypass ToggleGroupMasque (preset/style copies,
    -- combat-deferred edits) can clear masqueEnabled on a dormant group, and only
    -- RemoveButtonFromMasque restores CC's native borders.
    local group = self.db.profile.groups[groupId]
    if group and group.masqueEnabled and self.Masque and not self.MasqueGroups[groupId] then
        self:CreateMasqueGroup(groupId)
        for _, button in ipairs(frame.buttons) do
            self:AddButtonToMasque(groupId, button)
        end
    elseif self.Masque and self.MasqueGroups[groupId] and not (group and group.masqueEnabled) then
        for _, button in ipairs(frame.buttons) do
            self:RemoveButtonFromMasque(groupId, button)
        end
        self:DeleteMasqueGroup(groupId)
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
    -- The counterpart to the unload rebind: recovery skips PopulateGroupButtons
    -- (that is the point of the dormant path), so nothing else re-binds these
    -- buttons. Any pass that ran while the panel was parked left its records
    -- parked — container hidden, sounds released — and they stay that way.
    self:RequestAuraRebind("recover")

    return frame
end

-- Discard a dormant frame permanently (used by delete operations). This is the
-- true-teardown path, so the Masque group is released here rather than when the
-- frame is merely parked.
function CooldownCompanion:DiscardDormantFrame(groupId)
    local frame = self._dormantFrames and self._dormantFrames[groupId] or nil
    UnregisterKeyPressHighlightFrame(frame)
    if frame and frame.buttons then
        for _, button in ipairs(frame.buttons) do
            self:RemoveButtonFromMasque(groupId, button)
            if self.ReleaseAuraTextureVisual then
                self:ReleaseAuraTextureVisual(button)
            end
        end
    end
    self:DeleteMasqueGroup(groupId)
    if frame and self.ReleaseGroupButtonPools then
        self:ReleaseGroupButtonPools(frame)
    end
    if self._dormantFrames then
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
    -- Combat state cannot change part-way through a synchronous pass, so the
    -- lockdown read is per pass, not per frame.
    local inCombat = InCombatLockdown()
    for groupId, frame in pairs(self.groupFrames) do
        if frame and frame:IsShown() then
            local protected = inCombat and frame:IsProtected()
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
                if not (inCombat and frame:IsProtected()) then
                    local container = self.db.profile.groupContainers[containerId]
                    if container then
                        self:AnchorContainerFrame(frame, container.anchor)
                    end
                end
            end
        end
    end
end

-- Shared by the group context menu and the group multi-select surface;
-- callers own the config-panel refresh.
function CooldownCompanion:SetContainerEnabled(containerId, enabled)
    local container = self.db.profile.groupContainers[containerId]
    if not container then return end
    container.enabled = enabled
    self:RefreshContainerPanels(containerId)
end

function CooldownCompanion:SetContainerLocked(containerId, locked)
    local container = self.db.profile.groupContainers[containerId]
    if not container then return end
    -- Locking the soloed group would strand every other group solo-hidden
    -- with no chrome anywhere; release the solo first.
    if locked and self._arrangeSoloContainerId == containerId and self.SetArrangeSoloContainer then
        self:SetArrangeSoloContainer(nil)
    end
    container.locked = locked
    self:UpdateContainerDragHandle(containerId, locked)
    self:RefreshContainerPanels(containerId)
    if self._arrangeModeActive and self.RefreshArrangePillList then
        self:RefreshArrangePillList()
    end
end

function CooldownCompanion:SetPanelLocked(panelId, locked)
    local group = self.db.profile.groups[panelId]
    if not group then return end
    if self.IsGroupCursorAnchored and self:IsGroupCursorAnchored(group) then return end
    if locked then
        group.locked = nil
    else
        group.locked = false
    end
    self:RefreshGroupFrame(panelId)
    -- Panels are not part of the arrange-managed set (arrange unlocks containers,
    -- and panel padlocks hide while their container is unlocked), so this must not
    -- be the broader CheckArrangeModeAutoExit: a bulk multi-select lock would then
    -- evaluate an arrange exit once per panel and could exit partway through.
    if locked then
        self:CheckConfigReExpandAfterLock()
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
    -- Lock every container, including containers hidden for this character.
    -- Write the bulk state directly: SetContainerLocked refreshes that
    -- container's panels, while the single RefreshAllGroups below reconciles
    -- the complete runtime once after every lock value is settled.
    for _, container in pairs(self.db.profile.groupContainers or {}) do
        container.locked = true
    end
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
                frame:SetAlpha(GetUnlockedPanelAlpha(frame))
            end
        end
    end
    -- Unlock container frames
    if self.containerFrames then
        for containerId in pairs(self.containerFrames) do
            local container = self.db.profile.groupContainers[containerId]
            -- nil means locked; only an explicit false unlocks a container.
            self:UpdateContainerDragHandle(containerId, not container or container.locked ~= false)
        end
    end
    self:RefreshAllGroups()
end

function CooldownCompanion:EnterArrangeMode()
    if InCombatLockdown() or self._combatForcedLock then
        self:Print("Cannot unlock during combat.")
        return
    end
    if self._arrangeModeActive then
        return
    end

    self:CaptureArrangeSnapshot()
    self._arrangeModeActive = true
    self._arrangeFocusContainerId = nil
    self._arrangeChromeHidden = nil
    self._arrangeSoloContainerId = nil
    for containerId in pairs(self.db.profile.groupContainers or {}) do
        if self:IsContainerVisibleToCurrentChar(containerId)
            and self:ContainerHasArrangeEligiblePanel(containerId) then
            self:SetContainerLocked(containerId, false)
        end
    end
    if self.SetIndependentCastBarLocked then
        self:SetIndependentCastBarLocked(false)
    end
    if self.SetIndependentResourceStackLocked then
        self:SetIndependentResourceStackLocked(false)
    end
    if ST.CollapseConfigForUnlock then
        ST.CollapseConfigForUnlock()
    end
    -- Cursor-anchored panels chase the live cursor, which would sweep their
    -- mover chrome across every other outline mid-arrange. Park them on the
    -- dummy cursor for the whole unlock instead.
    if self.ShowCursorAnchorLayoutPreview then
        self:ShowCursorAnchorLayoutPreview(nil)
    end
    local pill = GetArrangeModePill(self)
    -- The group list is where solo focus and chrome hiding live; start every
    -- unlock with it open so those controls are discoverable.
    pill._listExpanded = true
    pill._listScrollOffset = 0
    pill:Show()
    self:Print("All frames unlocked. Drag to move.")
end

function CooldownCompanion:ExitArrangeMode(opts)
    self._arrangeSnapshot = nil
    self._arrangeModeActive = nil
    self._arrangeFocusContainerId = nil
    self._arrangeChromeHidden = nil
    self._arrangeSoloContainerId = nil
    CancelActiveMoverGestures(self)
    -- The arrange flag is already down, so this is a full teardown; config
    -- re-expand below restores its own selection preview if one applies.
    if self.ClearCursorAnchorLayoutPreview then
        self:ClearCursorAnchorLayoutPreview()
    end
    self:LockAllFrames()
    if self.SetIndependentCastBarLocked then
        self:SetIndependentCastBarLocked(true)
    end
    if self.SetIndependentResourceStackLocked then
        self:SetIndependentResourceStackLocked(true)
    end
    if self._arrangeModePill then
        self._arrangeModePill:Hide()
    end
    if self.RefreshConfigPanel then
        self:RefreshConfigPanel()
    end
    if not (opts and opts.silent) then
        self:Print("All frames locked.")
    end
    if not (opts and opts.skipConfigReExpand) then
        self:CheckConfigReExpandAfterLock()
    end
end

function CooldownCompanion:CancelArrangeMode()
    if not self._arrangeModeActive then
        return
    end
    if InCombatLockdown() or self._combatForcedLock then
        self:Print("Cannot cancel unlocking during combat.")
        return
    end

    local snapshot = self._arrangeSnapshot
    self._arrangeSnapshot = nil
    self:ExitArrangeMode({ silent = true, skipConfigReExpand = true })
    if snapshot then
        RestoreArrangeSnapshot(self, snapshot)
    end
    self:Print("Unlock cancelled. Unsaved changes reverted.")
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
