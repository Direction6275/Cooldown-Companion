--[[
    CooldownCompanion - Core/MigrationsLegacy.lua: legacy bridge migrations kept for the 1.15 upgrade path.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local Masque = CooldownCompanion.Masque

local pairs = pairs
local ipairs = ipairs
local type = type
local next = next
local rawget = rawget

function CooldownCompanion:MigrateGroupOwnership()
    for groupId, group in pairs(self.db.profile.groups) do
        if group.parentContainerId then
            -- Panels inherit visibility from their container — clear stale
            -- ownership fields that may have been re-stamped before this guard
            -- existed, or left over from an incomplete migration cycle.
            if group.isGlobal ~= nil then group.isGlobal = nil end
            if group.createdBy == "migrated" then group.createdBy = nil end
        elseif group.createdBy == nil and group.isGlobal == nil then
            group.isGlobal = true
            group.createdBy = "migrated"
        end
    end
end

function CooldownCompanion:MigrateFolderOwnership()
    local db = self.db.profile
    if not db.folders then return end
    for folderId, folder in pairs(db.folders) do
        if folder.section == "char" and not folder.createdBy then
            -- Infer owner from child groups
            local owner
            for _, group in pairs(db.groups) do
                if group.folderId == folderId and group.createdBy then
                    owner = group.createdBy
                    break
                end
            end
            folder.createdBy = owner or self.db.keys.char
        end
    end
end

function CooldownCompanion:MigrateOrphanedGroups()
    local currentChar = self.db.keys.char
    local currentName = currentChar:match("^(.+) %- ")
    if not currentName then return end
    for groupId, group in pairs(self.db.profile.groups) do
        if not group.isGlobal and group.createdBy
           and group.createdBy ~= currentChar
           and group.createdBy ~= "migrated" then
            local ownerName = group.createdBy:match("^(.+) %- ")
            if ownerName == currentName then
                group.createdBy = currentChar
            end
        end
    end
    -- Reclaim orphaned folders from realm renames
    if self.db.profile.folders then
        for _, folder in pairs(self.db.profile.folders) do
            if folder.section == "char" and folder.createdBy
               and folder.createdBy ~= currentChar then
                local ownerName = folder.createdBy:match("^(.+) %- ")
                if ownerName == currentName then
                    folder.createdBy = currentChar
                end
            end
        end
    end
end

function CooldownCompanion:MigrateAlphaSystem()
    for groupId, group in pairs(self.db.profile.groups) do
        -- Remove old hide fields
        group.hideWhileMounted = nil
        group.hideInCombat = nil
        group.hideOutOfCombat = nil
        group.hideNoTarget = nil

        -- Legacy mounted tri-state -> split Regular Mount + Dragonriding.
        -- Preserve behavior by copying legacy mounted settings to both buckets.
        local hadLegacyMounted = group.forceAlphaMounted ~= nil or group.forceHideMounted ~= nil
        if hadLegacyMounted then
            local legacyVisible = group.forceAlphaMounted == true
            local legacyHidden = group.forceHideMounted == true
            if rawget(group, "forceAlphaRegularMounted") == nil then
                group.forceAlphaRegularMounted = legacyVisible
            end
            if rawget(group, "forceHideRegularMounted") == nil then
                group.forceHideRegularMounted = legacyHidden
            end
            if rawget(group, "forceAlphaDragonriding") == nil then
                group.forceAlphaDragonriding = legacyVisible
            end
            if rawget(group, "forceHideDragonriding") == nil then
                group.forceHideDragonriding = legacyHidden
            end
        end
        group.forceAlphaMounted = nil
        group.forceHideMounted = nil

        -- Remove deprecated force-hide fields (replaced by force-visible-only checkboxes)
        group.forceHideTargetExists = nil
        group.forceHideMouseover = nil
        -- Ensure new defaults exist
        if group.baselineAlpha == nil then group.baselineAlpha = 1 end
        if group.fadeDelay == nil then group.fadeDelay = 1 end
        if group.fadeInDuration == nil then group.fadeInDuration = 0.2 end
        if group.fadeOutDuration == nil then group.fadeOutDuration = 0.2 end
    end

    -- Migrate legacy mounted keys in saved group setting presets.
    local presetStore = self.db.profile.groupSettingPresets
    if type(presetStore) == "table" then
        for _, mode in ipairs({"icons", "bars"}) do
            local modeStore = presetStore[mode]
            if type(modeStore) == "table" then
                for _, preset in pairs(modeStore) do
                    local groupData = type(preset) == "table" and preset.group or nil
                    if type(groupData) == "table" then
                        local hadLegacyMounted = groupData.forceAlphaMounted ~= nil or groupData.forceHideMounted ~= nil
                        if hadLegacyMounted then
                            local legacyVisible = groupData.forceAlphaMounted == true
                            local legacyHidden = groupData.forceHideMounted == true
                            if groupData.forceAlphaRegularMounted == nil then
                                groupData.forceAlphaRegularMounted = legacyVisible
                            end
                            if groupData.forceHideRegularMounted == nil then
                                groupData.forceHideRegularMounted = legacyHidden
                            end
                            if groupData.forceAlphaDragonriding == nil then
                                groupData.forceAlphaDragonriding = legacyVisible
                            end
                            if groupData.forceHideDragonriding == nil then
                                groupData.forceHideDragonriding = legacyHidden
                            end
                        end
                        groupData.forceAlphaMounted = nil
                        groupData.forceHideMounted = nil
                    end
                end
            end
        end
    end
end

function CooldownCompanion:MigrateDisplayMode()
    for groupId, group in pairs(self.db.profile.groups) do
        if group.displayMode == nil then
            group.displayMode = "icons"
        end
    end
end

function CooldownCompanion:MigrateMasqueField()
    for groupId, group in pairs(self.db.profile.groups) do
        if group.masqueEnabled == nil then
            group.masqueEnabled = false
        end
        -- If Masque addon is not available but group had it enabled, disable it
        if group.masqueEnabled and not Masque then
            group.masqueEnabled = false
        end
    end
end

function CooldownCompanion:MigrateRemoveBarChargeOldFields()
    for _, group in pairs(self.db.profile.groups) do
        if group.style then
            group.style.barChargeGap = nil
        end
        if group.buttons then
            for _, bd in ipairs(group.buttons) do
                bd.barChargeMissingColor = nil
                bd.barChargeSwipe = nil
                bd.barChargeGap = nil
                bd.barReverseCharges = nil
                bd.barCdTextOnRechargeBar = nil
            end
        end
    end
end


function CooldownCompanion:ReverseMigrateMW()
    local rb = self.db.profile.resourceBars
    if not rb then return end

    -- If MW was previously migrated to customAuraBars[1], restore it to resources[100]
    if rb.migrationVersion and rb.migrationVersion >= 1 then
        local cab1 = rb.customAuraBars and rb.customAuraBars[1]
        if cab1 and cab1.spellID == 187880 then
            if not rb.resources then rb.resources = {} end
            rb.resources[100] = {
                enabled = cab1.enabled ~= false,
                mwBaseColor = cab1.barColor,
                mwOverlayColor = cab1.overlayColor,
                mwMaxColor = cab1.maxColor,
            }
            -- Clear the custom aura bar slot
            rb.customAuraBars[1] = { enabled = false }
        end
        rb.migrationVersion = nil
    end

    -- Clean maxColor from any existing custom aura bar slots
    if rb.customAuraBars then
        for _, cab in pairs(rb.customAuraBars) do
            if cab then cab.maxColor = nil end
        end
    end
end

function CooldownCompanion:MigrateCustomAuraBarsToSpecKeyed()
    local rb = self.db.profile.resourceBars
    if not rb or not rb.customAuraBars then return end
    -- Old format has integer key [1] with an enabled field; spec IDs are 3+ digits
    local first = rb.customAuraBars[1]
    if first and type(first) == "table" and first.enabled ~= nil then
        rb.customAuraBars = {}
    end
end
