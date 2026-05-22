--[[
    CooldownCompanion - Core/MigrationsGroups.lua: group, folder, container, and panel migrations.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local Masque = CooldownCompanion.Masque

local pairs = pairs
local ipairs = ipairs
local type = type
local next = next
local rawget = rawget

function CooldownCompanion:MigrateFolders()
    if self.db.profile.folders == nil then
        self.db.profile.folders = {}
    end
    if self.db.profile.nextFolderId == nil then
        self.db.profile.nextFolderId = 1
    end
end

function CooldownCompanion:MigrateFolderSpecFilters()
    local db = self.db.profile
    if not db.folders then return end

    for folderId, folder in pairs(db.folders) do
        if folder.specs ~= nil and type(folder.specs) ~= "table" then
            folder.specs = nil
        end

        if folder.specs then
            local normalizedSpecs = {}
            for specId, enabled in pairs(folder.specs) do
                local numSpecId = tonumber(specId)
                if enabled and numSpecId then
                    normalizedSpecs[numSpecId] = true
                end
            end
            if next(normalizedSpecs) then
                folder.specs = normalizedSpecs
            else
                folder.specs = nil
            end
        end

        if folder.heroTalents ~= nil and type(folder.heroTalents) ~= "table" then
            folder.heroTalents = nil
        end
        if folder.heroTalents then
            local normalizedHero = {}
            for subTreeID, enabled in pairs(folder.heroTalents) do
                local numSubTreeID = tonumber(subTreeID)
                if enabled and numSubTreeID then
                    normalizedHero[numSubTreeID] = true
                end
            end
            if next(normalizedHero) then
                folder.heroTalents = normalizedHero
            else
                folder.heroTalents = nil
            end
        end
        if not (folder.specs and next(folder.specs)) then
            folder.heroTalents = nil
        end

        if folder.specs and next(folder.specs) then
            self:ApplyFolderSpecFilterToChildren(folderId)
        end
    end
end


function CooldownCompanion:MigratePanelAnchorCenter()
    local profile = self.db and self.db.profile
    if not profile or profile._migratedPanelAnchorCenter then return end

    local containers = profile.groupContainers or {}
    for _, group in pairs(profile.groups or {}) do
        local pcid = group.parentContainerId
        if pcid and containers[pcid] then
            local a = group.anchor
            if a and a.point == "TOPLEFT"
               and a.relativeTo == "CooldownCompanionContainer" .. pcid
               and a.relativePoint == "TOPLEFT"
               and (a.x or 0) == 0 and (a.y or 0) == 0 then
                a.point = "CENTER"
                a.relativePoint = "CENTER"
            end
        end
    end

    profile._migratedPanelAnchorCenter = true
end

function CooldownCompanion:MigrateContainerAnchorsToScreenOffsets()
    local profile = self.db.profile
    if profile._migratedContainerAnchorsToScreenOffsets then return end

    for containerId, container in pairs(profile.groupContainers or {}) do
        if self:IsContainerVisibleToCurrentChar(containerId) then
            container.anchor = self:NormalizeContainerAnchor(container.anchor)
        end
    end

    profile._migratedContainerAnchorsToScreenOffsets = true
end

-------------------------------------------------------------------------
-- MigrateContainerAlphaToPanel: Copies container-level alpha settings
-- down to each child panel so panels own their own alpha independently.
-------------------------------------------------------------------------
local ALPHA_FIELDS = {
    "baselineAlpha",
    "forceAlphaInCombat", "forceAlphaOutOfCombat",
    "forceAlphaRegularMounted", "forceAlphaDragonriding",
    "forceAlphaTargetExists", "forceAlphaFocusExists", "forceAlphaMouseover",
    "forceHideInCombat", "forceHideOutOfCombat",
    "forceHideRegularMounted", "forceHideDragonriding",
    "fadeInDuration", "fadeOutDuration", "fadeDelay",
    "customFade", "treatTravelFormAsMounted",
}

function CooldownCompanion:MigrateContainerAlphaToPanel()
    local profile = self.db.profile
    if profile._migratedContainerAlphaToPanel then return end

    local containers = profile.groupContainers
    if not containers then
        profile._migratedContainerAlphaToPanel = true
        return
    end

    for containerId, container in pairs(containers) do
        -- Check if container has non-default alpha settings
        local hasCustomAlpha = (container.baselineAlpha ~= nil and container.baselineAlpha ~= 1)
        if not hasCustomAlpha then
            for _, key in ipairs(ALPHA_FIELDS) do
                if key ~= "baselineAlpha" and container[key] then
                    hasCustomAlpha = true
                    break
                end
            end
        end

        -- Copy alpha fields to each child panel that has default alpha
        for groupId, group in pairs(profile.groups) do
            if group.parentContainerId == containerId then
                if hasCustomAlpha then
                    -- Only copy to panels with default alpha (no custom settings)
                    local panelHasCustomAlpha = (group.baselineAlpha ~= nil and group.baselineAlpha ~= 1)
                    if not panelHasCustomAlpha then
                        for _, key in ipairs(ALPHA_FIELDS) do
                            if key ~= "baselineAlpha" and group[key] then
                                panelHasCustomAlpha = true
                                break
                            end
                        end
                    end

                    if not panelHasCustomAlpha then
                        for _, key in ipairs(ALPHA_FIELDS) do
                            local val = container[key]
                            if val ~= nil then
                                if type(val) == "table" then
                                    group[key] = CopyTable(val)
                                else
                                    group[key] = val
                                end
                            end
                        end
                    end
                end

                -- Ensure every panel has baselineAlpha set for nil-safety
                if group.baselineAlpha == nil then
                    group.baselineAlpha = 1
                end
            end
        end
    end

    profile._migratedContainerAlphaToPanel = true
end

-- Clear hero talents that were stamped onto containers by the old authoritative
-- ApplyFolderSpecFilterToChildren.  Those values were folder copies, not
-- user-set.  With the new cascading model, GetEffectiveHeroTalents reads the
-- folder at runtime so the stamped copies are stale duplicates.
function CooldownCompanion:MigrateContainerHeroTalentStamps()
    local profile = self.db.profile
    if profile._migratedContainerHeroTalentStamps then return end

    local containers = profile.groupContainers
    local folders = profile.folders
    if not containers or not folders then
        profile._migratedContainerHeroTalentStamps = true
        return
    end

    for _, container in pairs(containers) do
        local folderId = container.folderId
        if folderId then
            local folder = folders[folderId]
            if folder and folder.heroTalents and next(folder.heroTalents) then
                container.heroTalents = nil
            end
        end
    end

    profile._migratedContainerHeroTalentStamps = true
end

-- Expand 4-element strataOrder arrays to 6-element by inserting auraGlow and readyGlow.
-- These were previously hardcoded at cooldown:GetFrameLevel() + 1 (just above cooldown),
-- so we insert them immediately after the "cooldown" entry to preserve that visual position.
