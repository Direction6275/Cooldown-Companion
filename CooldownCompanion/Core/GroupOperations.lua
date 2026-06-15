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
local table_insert = table.insert
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

local function DurationObjectNeedsPeriodicRefresh(durationObj)
    if not durationObj then
        return false
    end
    if durationObj.HasSecretValues and durationObj:HasSecretValues() then
        return true
    end
    if durationObj.GetRemainingDuration then
        local remaining = durationObj:GetRemainingDuration()
        return remaining and remaining > 0
    end
    return true
end

local function ItemCooldownNeedsPeriodicRefresh(button)
    local startTime = button._itemCdStart
    local duration = button._itemCdDuration
    if not (startTime and duration and duration > 0) then
        return false
    end
    if type(GetTime) ~= "function" then
        return true
    end
    return GetTime() < startTime + duration
end

local function ReadyGlowWindowNeedsPeriodicRefresh(button, startField)
    local startTime = button and button[startField]
    if not startTime then
        return false
    end
    local style = button.style
    if not (style and style.readyGlowStyle and style.readyGlowStyle ~= "none") then
        return false
    end
    local duration = style.readyGlowDuration or 0
    if duration <= 0 then
        return false
    end
    if type(GetTime) ~= "function" then
        return true
    end
    return GetTime() - startTime <= duration
end

local function GetButtonPeriodicCooldownRefreshReason(button)
    if not button then
        return nil
    end
    if DurationObjectNeedsPeriodicRefresh(button._durationObj) then return "duration" end
    if DurationObjectNeedsPeriodicRefresh(button._auraDurationObj) then return "aura-duration" end
    if DurationObjectNeedsPeriodicRefresh(button._chargeDurationObj) then return "charge-duration" end
    if ItemCooldownNeedsPeriodicRefresh(button) then return "item-cooldown" end
    if button._cooldownDeferred == true then return "deferred-cooldown" end
    if button._chargeRecharging == true then return "charge-recharging" end
    if button._chargeCooldownVisualActive == true then return "charge-visual" end
    if button._secondaryCdActive == true then return "secondary-cooldown" end
    if button._desatCooldownActive == true then return "desat-cooldown" end
    if button._auraActive == true then return "aura-active" end
    if button._auraGraceStart ~= nil then return "aura-grace" end
    if button._targetSwitchAt ~= nil then return "target-switch-hold" end
    if ReadyGlowWindowNeedsPeriodicRefresh(button, "_readyGlowStartTime") then return "ready-glow-window" end
    if ReadyGlowWindowNeedsPeriodicRefresh(button, "_readyGlowMaxChargesStartTime") then return "ready-glow-max-charges-window" end
    if button._conditionalPreviewRemaining ~= nil then return "conditional-preview" end
    return nil
end

local function RebuildCooldownPeriodicRefreshIndex(addon)
    local activeButtons = addon._cooldownPeriodicRefreshButtons
    if activeButtons then
        wipe(activeButtons)
    else
        activeButtons = {}
        addon._cooldownPeriodicRefreshButtons = activeButtons
    end

    local count = 0

    for _, frame in pairs(addon.groupFrames or {}) do
        if frame and frame.IsShown and frame:IsShown() and frame.buttons then
            for _, button in ipairs(frame.buttons) do
                local reason = GetButtonPeriodicCooldownRefreshReason(button)
                if reason then
                    count = count + 1
                    activeButtons[count] = button
                end
            end
        end
    end

    addon._cooldownPeriodicRefreshButtonsDirty = nil
    addon._cooldownPeriodicRefreshActive = count > 0 or nil
    return count
end

function CooldownCompanion:InvalidateCooldownRefreshIndexes()
    self._cooldownPeriodicRefreshButtonsDirty = true
    self._itemCooldownEventButtonsDirty = true
    if self.InvalidatePowerSensitiveButtonIndex then
        self:InvalidatePowerSensitiveButtonIndex()
    end
    if self.InvalidateCastButtonIndex then
        self:InvalidateCastButtonIndex()
    end
    if self.InvalidateCastCountEventIndex then
        self:InvalidateCastCountEventIndex()
    end
    if self.InvalidateRangeCheckButtonIndex then
        self:InvalidateRangeCheckButtonIndex()
    end
    if self.InvalidateAuraButtonIndex then
        self:InvalidateAuraButtonIndex()
    end
end

local function RebuildItemCooldownEventButtonIndex(addon)
    local buttons = addon._itemCooldownEventButtons
    if buttons then
        wipe(buttons)
    else
        buttons = {}
        addon._itemCooldownEventButtons = buttons
    end

    local isEntryItemLike = addon.IsEntryItemLike
    if type(isEntryItemLike) ~= "function" then
        addon._itemCooldownEventButtonsDirty = nil
        return buttons
    end

    for _, frame in pairs(addon.groupFrames or {}) do
        if frame and frame.buttons then
            for _, button in ipairs(frame.buttons) do
                local buttonData = button and button.buttonData
                if buttonData and isEntryItemLike(buttonData) and button.UpdateCooldown then
                    table_insert(buttons, button)
                end
            end
        end
    end

    addon._itemCooldownEventButtonsDirty = nil
    return buttons
end

local function PrepareCooldownUpdatePass(addon)
    addon._gcdInfo = C_Spell.GetSpellCooldown(61304)
    -- GCD activity: isActive is NeverSecret (12.0.1 hotfix)
    addon._gcdActive = addon._gcdInfo and addon._gcdInfo.isActive or false
    -- Cache for GCD overlay display in CooldownUpdate (only when GCD is active)
    addon._gcdDurationObj = addon._gcdActive and C_Spell.GetSpellCooldownDuration(61304) or nil

    -- Assisted highlight target gate:
    -- hard target has priority; if none exists, allow soft enemy fallback.
    local hasHostileTarget = false
    if UnitExists("target") then
        hasHostileTarget = UnitCanAttack("player", "target") and true or false
    elseif UnitExists("softenemy") then
        hasHostileTarget = UnitCanAttack("player", "softenemy") and true or false
    end
    addon._assistedHighlightHasHostileTarget = hasHostileTarget

    -- Cache CDM viewer CVar once per pass.
    addon._cdmViewerEnabled = C_CVar_GetCVarBool("cooldownViewerEnabled") == true
    addon._cooldownUpdatePassActive = true
end

local function FinishCooldownUpdatePass(addon)
    addon._cooldownUpdatePassActive = nil
    if type(GetTime) == "function" then
        addon._lastCooldownMaintenanceRefreshAt = GetTime()
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

local IGNORE_SPELL_AVAILABILITY_OPTIONS = {
    ignoreSpellAvailability = true,
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
    if group.isGlobal then return true end
    return group.createdBy == self.db.keys.char
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

    if not (group.buttons and #group.buttons > 0) then
        return false
    end

    local groupFrame = opts.groupFrame
    if groupFrame == nil and groupId then
        groupFrame = self.groupFrames and self.groupFrames[groupId] or nil
    end
    if groupFrame and (not groupFrame.buttons or #groupFrame.buttons == 0) then
        return false
    end

    local checkCharVisibility = opts.checkCharVisibility
    if checkCharVisibility == nil then
        checkCharVisibility = true
    end
    if checkCharVisibility and groupId and not self:IsGroupVisibleToCurrentChar(groupId) then
        return false
    end

    local effectiveSpecs = self:GetEffectiveSpecs(group)
    if effectiveSpecs and next(effectiveSpecs) then
        if not (self._currentSpecId and effectiveSpecs[self._currentSpecId]) then
            return false
        end
    end

    return true
end

function CooldownCompanion:GetContainerUnlockPreviewPanels(containerId)
    local previewPanels = {}
    local panels = self:GetPanels(containerId)
    for _, panelInfo in ipairs(panels) do
        if self:IsGroupVisibleInUnlockPreview(panelInfo.groupId, {
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

    -- Panel: container specs (includes stamped folder specs) → panel's own
    local container = self:GetParentContainer(group)
    if container then
        if container.specs and next(container.specs) then
            return container.specs, true
        end
        -- Fall through to panel's own
        return group.specs, false
    end

    -- Non-panel group: check folder cascade
    local folderId = group.folderId
    if folderId then
        local folders = self.db and self.db.profile and self.db.profile.folders
        local folder = folders and folders[folderId]
        if folder and folder.specs and next(folder.specs) then
            return folder.specs, true
        end
    end
    return group.specs, false
end

function CooldownCompanion:GetEffectiveHeroTalents(group)
    if not group then return nil, false end

    -- Panel cascade: folder → container → panel's own heroTalents
    local container = self:GetParentContainer(group)
    if container then
        -- Check folder first
        local folderId = container.folderId
        if folderId then
            local folders = self.db and self.db.profile and self.db.profile.folders
            local folder = folders and folders[folderId]
            if folder and folder.heroTalents and next(folder.heroTalents) then
                return folder.heroTalents, true
            end
        end
        -- Then container's own heroTalents
        if container.heroTalents and next(container.heroTalents) then
            return container.heroTalents, true
        end
        -- Fall through to panel's own
        return group.heroTalents, false
    end

    -- Non-panel container: check folder cascade
    local folderId = group.folderId
    if folderId then
        local folders = self.db and self.db.profile and self.db.profile.folders
        local folder = folders and folders[folderId]
        if folder and folder.heroTalents and next(folder.heroTalents) then
            return folder.heroTalents, true
        end
    end
    return group.heroTalents, false
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

function CooldownCompanion:SetFolderSpecs(folderId, specs)
    local db = self.db and self.db.profile
    local folder = db and db.folders and db.folders[folderId]
    if not folder then return false end
    local oldSpecs = folder.specs and CopyTable(folder.specs) or nil

    if specs and next(specs) then
        local normalizedSpecs = {}
        for specId, enabled in pairs(specs) do
            local numSpecId = tonumber(specId)
            if enabled and numSpecId then
                normalizedSpecs[numSpecId] = true
            end
        end
        folder.specs = next(normalizedSpecs) and normalizedSpecs or nil
    else
        folder.specs = nil
    end

    -- Hero filters must remain scoped to selected specs.
    if folder.heroTalents and next(folder.heroTalents) then
        if not (folder.specs and next(folder.specs)) then
            folder.heroTalents = nil
        elseif oldSpecs then
            for specId in pairs(oldSpecs) do
                if not folder.specs[specId] then
                    -- Works for folders too; CleanHeroTalentsForSpec only mutates .heroTalents
                    self:CleanHeroTalentsForSpec(folder, specId)
                end
            end
        end
    end

    self:ApplyFolderSpecFilterToChildren(folderId)
    self:RefreshAllGroups()
    self:RefreshConfigPanel()
    return true
end

function CooldownCompanion:SetFolderHeroTalent(folderId, subTreeID, enabled)
    local db = self.db and self.db.profile
    local folder = db and db.folders and db.folders[folderId]
    if not folder then return false end
    if not (folder.specs and next(folder.specs)) then return false end

    if enabled then
        if not folder.heroTalents then folder.heroTalents = {} end
        folder.heroTalents[subTreeID] = true
    else
        if folder.heroTalents then
            folder.heroTalents[subTreeID] = nil
            if not next(folder.heroTalents) then
                folder.heroTalents = nil
            end
        end
    end

    self:ApplyFolderSpecFilterToChildren(folderId)
    self:RefreshAllGroups()
    self:RefreshConfigPanel()
    return true
end

function CooldownCompanion:IsHeroTalentAllowed(group)
    local effectiveHeroTalents = self:GetEffectiveHeroTalents(group)
    if not (effectiveHeroTalents and next(effectiveHeroTalents)) then return true end
    local heroSpecId = self._currentHeroSpecId
    if not heroSpecId then return true end  -- low level, no hero talent selected
    return effectiveHeroTalents[heroSpecId] == true
end

function CooldownCompanion:GroupHasUsableButtons(group, opts)
    opts = opts or {}
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

function CooldownCompanion:GetGroupButtonUsabilityOptions(groupId, group)
    if group
        and group.parentContainerId
        and ST.IsGroupConfigSelected
        and ST.IsGroupConfigSelected(groupId) then
        return IGNORE_SPELL_AVAILABILITY_OPTIONS
    end
    return nil
end

function CooldownCompanion:GetGroupLayoutButtonUsabilityOptions(groupId, group)
    if group and group.parentContainerId and not group.compactLayout then
        return IGNORE_SPELL_AVAILABILITY_OPTIONS
    end
    return nil
end

function CooldownCompanion:GetGroupLayoutButtonCount(groupId, group)
    if not (group and group.buttons and #group.buttons > 0) then
        return 0
    end

    local opts = self.GetGroupLayoutButtonUsabilityOptions
        and self:GetGroupLayoutButtonUsabilityOptions(groupId, group)
        or nil

    local count = 0
    for _, buttonData in ipairs(group.buttons) do
        if self:IsButtonUsable(buttonData, group, opts) then
            count = count + 1
        end
    end
    return count
end

function CooldownCompanion:IsGroupActive(groupId, opts)
    opts = opts or {}
    local group = opts.group or self.db.profile.groups[groupId]
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

    local buttonUsabilityOptions = opts.buttonUsabilityOptions
        or (self.GetGroupButtonUsabilityOptions and self:GetGroupButtonUsabilityOptions(groupId, group))

    if opts.requireButtons and not self:GroupHasUsableButtons(group, {
        checkLoadConditions = opts.checkLoadConditions,
        ignoreSpellAvailability = buttonUsabilityOptions and buttonUsabilityOptions.ignoreSpellAvailability,
    }) then
        return false
    end

    -- Spec and hero talent filtering (GetEffectiveSpecs already delegates to container)
    local effectiveSpecs = self:GetEffectiveSpecs(group)
    if effectiveSpecs and next(effectiveSpecs) then
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

function CooldownCompanion:IsGroupAvailableForAnchoring(groupId)
    local group = self.db.profile.groups[groupId]
    if not group then return false end
    if not group.parentContainerId then return false end
    if self.CanGroupBeExternalAnchorTarget then
        if not self:CanGroupBeExternalAnchorTarget(groupId) then return false end
    elseif self.IsGroupCursorAnchored and self:IsGroupCursorAnchored(group) then
        return false
    end
    if group.displayMode ~= "icons" then return false end
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
        if group.displayMode == "textures" or group.displayMode == "trigger" then return false end
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

function CooldownCompanion:PopulateAnchorDropdown(dropdown)
    local db = self.db.profile
    local containers = db.groupContainers or {}
    local folders = db.folders or {}
    local folderPanels = {}
    local loosePanels = {}
    local eligibleCount = 0

    for groupId, group in pairs(db.groups) do
        if self:IsGroupAvailableForAnchoring(groupId) then
            eligibleCount = eligibleCount + 1
            local cid = group.parentContainerId
            local ctr = cid and containers[cid]
            local fid = ctr and ctr.folderId
            local contName = ctr and ctr.name or "Group"
            local panelName = group.name or ("Panel " .. groupId)
            local entry = { id = groupId, name = panelName, contName = contName }
            if fid and folders[fid] then
                folderPanels[fid] = folderPanels[fid] or {}
                table.insert(folderPanels[fid], entry)
            else
                table.insert(loosePanels, entry)
            end
        end
    end

    dropdown:SetList({ [""] = "Auto (first available)" }, { "" })

    local sortedFolders = {}
    for fid, folder in pairs(folders) do
        if folderPanels[fid] then
            table.insert(sortedFolders, { id = fid, name = folder.name or ("Folder " .. fid), order = self:GetOrderForSpec(folder, self._currentSpecId, fid) })
        end
    end
    table.sort(sortedFolders, function(a, b) return a.order < b.order end)

    local hasHeaders = #sortedFolders > 0

    for _, folder in ipairs(sortedFolders) do
        local hdrKey = "_hdr_" .. folder.id
        dropdown:AddItem(hdrKey, "|cffffd100" .. folder.name .. "|r")
        dropdown:SetItemDisabled(hdrKey, true)

        table.sort(folderPanels[folder.id], function(a, b)
            if a.contName ~= b.contName then return a.contName < b.contName end
            return a.name < b.name
        end)
        for _, panel in ipairs(folderPanels[folder.id]) do
            local key = tostring(panel.id)
            dropdown:AddItem(key, "   " .. panel.name)
            dropdown.list[key] = panel.contName .. " > " .. panel.name
        end
    end

    if #loosePanels > 0 then
        if hasHeaders then
            dropdown:AddItem("_hdr_none", "|cffffd100No Folder|r")
            dropdown:SetItemDisabled("_hdr_none", true)
        end
        table.sort(loosePanels, function(a, b)
            if a.contName ~= b.contName then return a.contName < b.contName end
            return a.name < b.name
        end)
        for _, panel in ipairs(loosePanels) do
            local key = tostring(panel.id)
            local prefix = hasHeaders and "   " or ""
            dropdown:AddItem(key, prefix .. panel.name)
            dropdown.list[key] = panel.contName .. " > " .. panel.name
        end
    end

    return eligibleCount
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
    for _, value in pairs(entity.loadConditions) do
        if value == true then
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

function CooldownCompanion:CheckLoadConditions(group)
    return self:EvaluateLoadConditions(group and group.loadConditions)
end

local function AddLoadConditionSource(sources, label, entity, defaults)
    if type(entity) == "table" and type(entity.loadConditions) == "table" then
        sources[#sources + 1] = {
            label = label,
            loadConditions = entity.loadConditions,
            defaults = defaults,
        }
    end
end

function CooldownCompanion:GetInheritedLoadConditionSources(group)
    local sources = {}
    local db = self.db and self.db.profile
    if not (db and group) then return sources end

    local container = self:GetParentContainer(group)
    if container then
        local folder = container.folderId and db.folders and db.folders[container.folderId]
        AddLoadConditionSource(sources, "Folder", folder, LOCAL_LOAD_CONDITION_DEFAULTS)
        AddLoadConditionSource(sources, "Group", container, LOAD_CONDITION_DEFAULTS)
        return sources
    end

    local folder = group.folderId and db.folders and db.folders[group.folderId]
    AddLoadConditionSource(sources, "Folder", folder, LOCAL_LOAD_CONDITION_DEFAULTS)
    return sources
end

function CooldownCompanion:GetLoadConditionSourcesForGroup(group)
    local sources = self:GetInheritedLoadConditionSources(group)
    if group then
        AddLoadConditionSource(sources, group.parentContainerId and "Panel" or "Group", group, LOAD_CONDITION_DEFAULTS)
    end
    return sources
end

function CooldownCompanion:GetLoadConditionSourcesForEntry(buttonData, group)
    local sources = self:GetLoadConditionSourcesForGroup(group)
    AddLoadConditionSource(sources, "Entry", buttonData, LOCAL_LOAD_CONDITION_DEFAULTS)
    return sources
end

function CooldownCompanion:EvaluateLoadConditionSources(sources)
    for _, source in ipairs(sources or {}) do
        if not self:EvaluateLoadConditions(source.loadConditions, source.defaults) then
            return false, source.label
        end
    end
    return true, nil
end

function CooldownCompanion:IsGroupLoadConditionMet(group)
    return self:EvaluateLoadConditionSources(self:GetLoadConditionSourcesForGroup(group))
end

function CooldownCompanion:IsButtonLoadConditionMet(buttonData, group)
    return self:EvaluateLoadConditionSources(self:GetLoadConditionSourcesForEntry(buttonData, group))
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
    if not self:IsTalentConditionMet(buttonData) then return false end

    if opts.ignoreSpellAvailability and buttonData.type == "spell" then
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
            and CooldownCompanion.ResolveEffectiveItem(buttonData, { requestLoad = true }) or nil
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

function CooldownCompanion:GroupButtonSetNeedsRebuild(groupId, group)
    local frame = GetFrameForButtonSetComparison(self, groupId)
    if not frame or not frame.buttons then
        return false
    end
    if not group.buttons then
        return #frame.buttons > 0
    end

    local usableButtons = {}
    local usableCount = 0
    local buttonUsabilityOptions = self.GetGroupButtonUsabilityOptions
        and self:GetGroupButtonUsabilityOptions(groupId, group)
        or nil
    for _, buttonData in ipairs(group.buttons) do
        if self:IsButtonUsable(buttonData, group, buttonUsabilityOptions) then
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

    self:MarkCooldownsDirty()
end

function CooldownCompanion:RefreshAllGroupsForSpellAvailability()
    local needsFullRefresh = self:AnyGroupButtonSetNeedsRebuild()
    self:ResetSpellAvailabilityButtonRuntime()

    if needsFullRefresh then
        self:RefreshAllGroups()
    else
        self:RefreshAllGroupsVisibilityOnly()
    end

    self:UpdateAllCooldowns()
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
    if not (ST.IsGroupConfigSelected and self.db and self.db.profile and self.db.profile.groups) then
        return
    end

    self._refreshingConfigSelectedGroupFrames = true
    local groups = self.db.profile.groups
    local previousPreviewed = self._configPreviewedGroupFrames
    local currentPreviewed = nil
    local candidates = {}

    for groupId in pairs(groups) do
        if ST.IsGroupConfigSelected(groupId) then
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
            local active = self:IsGroupActive(groupId, {
                group = group,
                checkCharVisibility = true,
                checkLoadConditions = true,
                requireButtons = true,
            })
            if (active or (wasPreviewed and frame))
                and (not frame
                    or (wasPreviewed and not isPreviewed)
                    or self:GroupButtonSetNeedsRebuild(groupId, group)) then
                self:RefreshGroupFrame(groupId)
                refreshed = true
            end
        end
    end
    self._refreshingConfigSelectedGroupFrames = nil

    if refreshed then
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
        if not self:IsGroupVisibleToCurrentChar(groupId) then
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
        if not self:IsGroupVisibleToCurrentChar(groupId) then
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
    if self.InvalidateCooldownRefreshIndexes then
        self:InvalidateCooldownRefreshIndexes()
    end
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
    if self.InvalidateCooldownRefreshIndexes then
        self:InvalidateCooldownRefreshIndexes()
    end

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
        if self.InvalidateCooldownRefreshIndexes then
            self:InvalidateCooldownRefreshIndexes()
        end
    end
end

function CooldownCompanion:UpdateCooldownButtonsForSpellEvent(spellID, baseSpellID)
    if not self.CollectCooldownEventButtonsForSpell then
        return false
    end

    local buttons = self:CollectCooldownEventButtonsForSpell(spellID, baseSpellID)
    if not buttons then
        return false
    end

    PrepareCooldownUpdatePass(self)

    local updated = false
    for _, button in ipairs(buttons) do
        local groupId = button and button._groupId
        local frame = groupId and self.groupFrames and self.groupFrames[groupId] or nil
        if frame and frame.IsShown and frame:IsShown()
                and button.UpdateCooldown
                and button._pooled ~= true then
            button:UpdateCooldown()
            updated = true
        end
    end

    RebuildCooldownPeriodicRefreshIndex(self)
    FinishCooldownUpdatePass(self)

    return updated
end

function CooldownCompanion:UpdateItemCooldownButtonsForEvent()
    local isEntryItemLike = self.IsEntryItemLike
    if type(isEntryItemLike) ~= "function" then
        return false
    end

    local indexedButtons = self._itemCooldownEventButtons
    if self._itemCooldownEventButtonsDirty or type(indexedButtons) ~= "table" then
        indexedButtons = RebuildItemCooldownEventButtonIndex(self)
    end
    if #indexedButtons == 0 then
        return false
    end

    local foundStaleEntry = false
    local visibleButtons = self._itemCooldownEventVisibleButtons
    if visibleButtons then
        wipe(visibleButtons)
    else
        visibleButtons = {}
        self._itemCooldownEventVisibleButtons = visibleButtons
    end
    for _, button in ipairs(indexedButtons) do
        local groupId = button and button._groupId
        local frame = groupId and self.groupFrames and self.groupFrames[groupId] or nil
        local buttonData = button and button.buttonData
        if frame and button.UpdateCooldown
                and button._pooled ~= true
                and isEntryItemLike(buttonData) then
            if frame.IsShown and frame:IsShown() then
                table_insert(visibleButtons, button)
            end
        else
            foundStaleEntry = true
        end
    end

    if foundStaleEntry then
        self._itemCooldownEventButtonsDirty = true
    end

    if #visibleButtons == 0 then
        return false
    end

    PrepareCooldownUpdatePass(self)

    local updated = false
    for _, button in ipairs(visibleButtons) do
        local groupId = button and button._groupId
        local frame = groupId and self.groupFrames and self.groupFrames[groupId] or nil
        if frame then
            button:UpdateCooldown()
            updated = true
        end
    end

    RebuildCooldownPeriodicRefreshIndex(self)
    FinishCooldownUpdatePass(self)

    return updated
end

function CooldownCompanion:UpdateAllCooldowns()
    PrepareCooldownUpdatePass(self)

    for groupId, frame in pairs(self.groupFrames) do
        if frame and frame.UpdateCooldowns and frame:IsShown() then
            frame:UpdateCooldowns()
        end
    end

    RebuildCooldownPeriodicRefreshIndex(self)
    FinishCooldownUpdatePass(self)
end

function CooldownCompanion:UpdateActiveCooldownButtons()
    local periodicRefreshActive = false

    PrepareCooldownUpdatePass(self)

    if self._cooldownPeriodicRefreshButtonsDirty
            or type(self._cooldownPeriodicRefreshButtons) ~= "table" then
        RebuildCooldownPeriodicRefreshIndex(self)
    end

    local activeButtons = self._cooldownPeriodicRefreshButtons
    local nextActiveButtons = self._cooldownPeriodicRefreshButtonsNext
    if nextActiveButtons then
        wipe(nextActiveButtons)
    else
        nextActiveButtons = {}
    end
    for _, button in ipairs(activeButtons or {}) do
        local groupId = button and button._groupId
        local frame = groupId and self.groupFrames and self.groupFrames[groupId] or nil
        if frame and frame.IsShown and frame:IsShown()
                and button.UpdateCooldown
                and button._pooled ~= true then
            local reason = GetButtonPeriodicCooldownRefreshReason(button)
            if reason then
                button:UpdateCooldown()

                reason = GetButtonPeriodicCooldownRefreshReason(button)
                if reason then
                    table_insert(nextActiveButtons, button)
                    if not periodicRefreshActive then
                        periodicRefreshActive = true
                    end
                end
            end
        end
    end

    FinishCooldownUpdatePass(self)
    self._cooldownPeriodicRefreshButtonsNext = activeButtons
    self._cooldownPeriodicRefreshButtons = nextActiveButtons
    self._cooldownPeriodicRefreshActive = periodicRefreshActive or nil
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
