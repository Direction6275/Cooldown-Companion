--[[
    CooldownCompanion - Config/Diagnostics
    Diagnostic snapshot system (bug report generation + decode panel).
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local AceGUI = LibStub("AceGUI-3.0")
local AceSerializer = LibStub("AceSerializer-3.0")
local LibDeflate = LibStub("LibDeflate")

-- File-local state
local decodedDiagnostic = nil
local diagnosticDecodeFrame = nil

local RESOURCE_NAMES = {
    [0] = "Mana", [1] = "Rage", [2] = "Focus", [3] = "Energy",
    [4] = "Combo Points", [5] = "Runes", [6] = "Runic Power",
    [7] = "Soul Shards", [8] = "Lunar Power", [9] = "Holy Power",
    [10] = "Alternate", [11] = "Maelstrom", [12] = "Chi",
    [13] = "Insanity", [16] = "Arcane Charges", [17] = "Fury",
    [18] = "Pain", [19] = "Essence", [100] = "Maelstrom Weapon",
}

local function BuildDiagnosticSnapshot()
    local db = CooldownCompanion.db
    local snapshot = { _v = 2 }

    -- Meta
    local _, classFilename, classID = UnitClass("player")
    local specIndex = C_SpecializationInfo.GetSpecialization()
    local specID, specName
    if specIndex then
        specID, specName = C_SpecializationInfo.GetSpecializationInfo(specIndex)
    end
    local buildVersion, _, _, interfaceVersion = GetBuildInfo()
    local addonVersion = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "unknown"

    local totalButtons = 0
    local groupCount = 0
    for _, group in pairs(db.profile.groups) do
        groupCount = groupCount + 1
        if group.buttons then
            totalButtons = totalButtons + #group.buttons
        end
    end

    local containerCount = 0
    for _ in pairs(db.profile.groupContainers) do
        containerCount = containerCount + 1
    end

    local charName = UnitName("player")
    local charKey = db.keys.char

    snapshot.meta = {
        addonVersion = addonVersion,
        buildVersion = buildVersion,
        interfaceVersion = interfaceVersion,
        locale = GetLocale(),
        charName = charName,
        charKey = charKey,
        className = classFilename,
        classID = classID,
        specID = specID,
        specName = specName,
        realmName = GetRealmName(),
        timestamp = date("%Y-%m-%d %H:%M:%S"),
        containerCount = containerCount,
        groupCount = groupCount,
        totalButtons = totalButtons,
        instanceType = CooldownCompanion._currentInstanceType,
    }

    -- Runtime
    local viewerAuraSpells = {}
    for spellID in pairs(CooldownCompanion.viewerAuraFrames) do
        viewerAuraSpells[#viewerAuraSpells + 1] = spellID
    end
    table.sort(viewerAuraSpells)

    local procOverlaySpells = {}
    for spellID in pairs(CooldownCompanion.procOverlaySpells) do
        procOverlaySpells[#procOverlaySpells + 1] = spellID
    end
    table.sort(procOverlaySpells)

    local rangeCheckSpells = {}
    for spellID in pairs(CooldownCompanion._rangeCheckSpells) do
        rangeCheckSpells[#rangeCheckSpells + 1] = spellID
    end
    table.sort(rangeCheckSpells)

    local groupFrameStates = {}
    for groupId, frame in pairs(CooldownCompanion.groupFrames) do
        groupFrameStates[tostring(groupId)] = {
            exists = true,
            shown = frame:IsShown(),
        }
    end

    local containerFrameStates = {}
    if CooldownCompanion.containerFrames then
        for containerId, frame in pairs(CooldownCompanion.containerFrames) do
            containerFrameStates[tostring(containerId)] = {
                exists = true,
                shown = frame:IsShown(),
            }
        end
    end

    local resourceBarRuntime = nil
    if CooldownCompanion.GetResourceBarRuntimeDebugInfo then
        resourceBarRuntime = CooldownCompanion:GetResourceBarRuntimeDebugInfo()
    end

    local loadedAddons = {}
    for i = 1, C_AddOns.GetNumAddOns() do
        local name, title, _, loadable, reason, security = C_AddOns.GetAddOnInfo(i)
        local isLoaded = C_AddOns.IsAddOnLoaded(i)
        if isLoaded then
            local version = C_AddOns.GetAddOnMetadata(i, "Version")
            loadedAddons[#loadedAddons + 1] = {
                name = name,
                title = title,
                version = version or "?",
            }
        end
    end
    table.sort(loadedAddons, function(a, b) return a.name < b.name end)

    snapshot.runtime = {
        currentInstanceType = CooldownCompanion._currentInstanceType,
        currentSpecId = CooldownCompanion._currentSpecId,
        currentHeroSpecId = CooldownCompanion._currentHeroSpecId,
        isResting = CooldownCompanion._isResting,
        cdmHidden = db.profile.cdmHidden,
        assistedSpellID = CooldownCompanion.assistedSpellID,
        viewerAuraSpells = viewerAuraSpells,
        procOverlaySpells = procOverlaySpells,
        rangeCheckSpells = rangeCheckSpells,
        groupFrameStates = groupFrameStates,
        containerFrameStates = containerFrameStates,
        resourceBarRuntime = resourceBarRuntime,
        loadedAddons = loadedAddons,
    }

    -- Build spec name cache for all referenced spec IDs
    local specNameCache = {}
    local function cacheSpecName(sid)
        if sid and not specNameCache[sid] then
            specNameCache[sid] = GetSpecializationNameForSpecID(sid)
        end
    end
    local function cacheSpecsFromTable(specTable)
        if specTable then
            for sid in pairs(specTable) do cacheSpecName(sid) end
        end
    end
    for _, group in pairs(db.profile.groups) do
        cacheSpecsFromTable(group.specs)
    end
    for _, container in pairs(db.profile.groupContainers) do
        cacheSpecsFromTable(container.specs)
    end
    for _, folder in pairs(db.profile.folders) do
        cacheSpecsFromTable(folder.specs)
    end
    local resourceStores = rawget(db.profile, "resourceBarsByChar")
    if type(resourceStores) == "table" then
        for _, resourceSettings in pairs(resourceStores) do
            if type(resourceSettings) == "table" and type(resourceSettings.customAuraBars) == "table" then
                for sid in pairs(resourceSettings.customAuraBars) do
                    if sid ~= 0 then cacheSpecName(sid) end
                end
            end
        end
    end
    snapshot.meta.specNameCache = specNameCache

    -- Profile (full copy, same as profile export)
    snapshot.profile = db.profile

    return snapshot
end

local function FormatDiagnosticAsText(diag)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end

    local function formatValue(v)
        if type(v) ~= "table" then return tostring(v) end
        local n = 0
        for _ in pairs(v) do n = n + 1 end
        if n == 0 then return "{}" end
        if n > 10 then return "{" .. n .. " entries}" end
        if #v > 0 and #v == n then
            local parts = {}
            for _, val in ipairs(v) do parts[#parts + 1] = tostring(val) end
            return "{" .. table.concat(parts, ",") .. "}"
        else
            local parts = {}
            for k, val in pairs(v) do
                parts[#parts + 1] = tostring(k) .. "=" .. tostring(val)
            end
            table.sort(parts)
            return "{" .. table.concat(parts, ", ") .. "}"
        end
    end

    local function dumpKV(t)
        local parts = {}
        for k, v in pairs(t) do
            parts[#parts + 1] = tostring(k) .. "=" .. formatValue(v)
        end
        table.sort(parts)
        return table.concat(parts, " ")
    end

    -- Explicitly include nil-valued keys that are important for debugging
    local function dumpKVWithNils(t, importantKeys)
        local parts = {}
        local seen = {}
        for k, v in pairs(t) do
            seen[k] = true
            parts[#parts + 1] = tostring(k) .. "=" .. formatValue(v)
        end
        if importantKeys then
            for _, k in ipairs(importantKeys) do
                if not seen[k] then
                    parts[#parts + 1] = k .. "=nil"
                end
            end
        end
        table.sort(parts)
        return table.concat(parts, " ")
    end

    local m = diag.meta or {}
    local r = diag.runtime or {}
    local p = diag.profile or {}
    local specNames = m.specNameCache or {}

    -- Format a spec set (handles both array-style {71,72} and map-style {[71]=true})
    local function formatSpecList(specs)
        if not specs then return "nil (no filter)" end
        local specIds = {}
        if #specs > 0 then
            for _, sid in ipairs(specs) do specIds[#specIds + 1] = sid end
        else
            for sid in pairs(specs) do specIds[#specIds + 1] = sid end
        end
        if #specIds == 0 then return "all" end
        table.sort(specIds)
        local ss = {}
        for _, s in ipairs(specIds) do
            local name = specNames[s]
            ss[#ss + 1] = name and (tostring(s) .. "(" .. name .. ")") or tostring(s)
        end
        return table.concat(ss, ", ")
    end

    -- Build viewer aura set for cross-referencing with buttons
    local viewerAuraSet = {}
    if r.viewerAuraSpells then
        for _, sid in ipairs(r.viewerAuraSpells) do
            viewerAuraSet[sid] = true
        end
    end

    -- Build group visibility map from runtime groupFrameStates
    local groupFrameVisible = {}  -- [groupId number] = true/false, nil = no frame
    if r.groupFrameStates then
        for id, state in pairs(r.groupFrameStates) do
            groupFrameVisible[tonumber(id)] = state.shown
        end
    end

    -- Build container visibility map from runtime containerFrameStates
    local containerFrameVisible = {}  -- [containerId number] = true/false, nil = no frame
    if r.containerFrameStates then
        for id, state in pairs(r.containerFrameStates) do
            containerFrameVisible[tonumber(id)] = state.shown
        end
    end

    -- Header
    add(("=== CDC BUG REPORT (v%s) ==="):format(tostring(diag._v or "?")))
    add(("Addon: %s | WoW: %s (%s) | Locale: %s"):format(
        tostring(m.addonVersion or "?"), tostring(m.buildVersion or "?"),
        tostring(m.interfaceVersion or "?"), tostring(m.locale or "?")))
    add(("Character: %s - %s | %s %s (class:%s spec:%s)"):format(
        tostring(m.charName or "?"), tostring(m.realmName or "?"),
        tostring(m.specName or "?"), tostring(m.className or "?"),
        tostring(m.classID or "?"), tostring(m.specID or "?")))
    add(("Instance: %s | Resting: %s | CDM Hidden: %s"):format(
        tostring(m.instanceType or "?"), tostring(r.isResting), tostring(r.cdmHidden)))
    add(("Timestamp: %s"):format(tostring(m.timestamp or "?")))
    add(("Containers: %s | Panels: %s | Total Buttons: %s"):format(
        tostring(m.containerCount or "?"), tostring(m.groupCount or "?"), tostring(m.totalButtons or "?")))

    -- Runtime
    add("")
    add("--- Runtime ---")
    add(("Cached Spec ID: %s | Hero Spec ID: %s"):format(
        tostring(r.currentSpecId or "nil"), tostring(r.currentHeroSpecId or "nil")))
    add(("Assisted Spell: %s"):format(tostring(r.assistedSpellID or "none")))

    local function formatIDList(t)
        if not t or #t == 0 then return "none" end
        local parts = {}
        for _, v in ipairs(t) do parts[#parts + 1] = tostring(v) end
        return table.concat(parts, ", ")
    end

    add(("Viewer Aura Spells: %s"):format(formatIDList(r.viewerAuraSpells)))
    add(("Proc Overlay Spells: %s"):format(formatIDList(r.procOverlaySpells)))
    add(("Range Check Spells: %s"):format(formatIDList(r.rangeCheckSpells)))

    if r.groupFrameStates then
        local parts = {}
        local ids = {}
        for id in pairs(r.groupFrameStates) do ids[#ids + 1] = id end
        table.sort(ids, function(a, b) return tonumber(a) < tonumber(b) end)
        for _, id in ipairs(ids) do
            local state = r.groupFrameStates[id]
            parts[#parts + 1] = ("[%s] %s"):format(id, state.shown and "shown" or "hidden")
        end
        add("Panel Frame States:")
        add("  " .. (#parts > 0 and table.concat(parts, "  ") or "none"))
    end

    if r.containerFrameStates then
        local parts = {}
        local ids = {}
        for id in pairs(r.containerFrameStates) do ids[#ids + 1] = id end
        table.sort(ids, function(a, b) return tonumber(a) < tonumber(b) end)
        for _, id in ipairs(ids) do
            local state = r.containerFrameStates[id]
            parts[#parts + 1] = ("[%s] %s"):format(id, state.shown and "shown" or "hidden")
        end
        add("Container Frame States:")
        add("  " .. (#parts > 0 and table.concat(parts, "  ") or "none"))
    end

    if r.resourceBarRuntime and #r.resourceBarRuntime > 0 then
        add("Resource Bar Runtime:")
        for _, entry in ipairs(r.resourceBarRuntime) do
            local parts = {
                ("[%s]"):format(tostring(entry.index or "?")),
                tostring(entry.barType or "unknown"),
                "powerType=" .. tostring(entry.powerType or "nil"),
                entry.shown and "shown" or "hidden",
            }
            if entry.spellID then
                parts[#parts + 1] = "spellID=" .. tostring(entry.spellID)
            end
            if entry.hideWhenInactive then
                parts[#parts + 1] = "hideWhenInactive=true"
            end
            if entry.isIndependent then
                parts[#parts + 1] = "independent=true"
            end
            add("  " .. table.concat(parts, " "))
        end
    end

    -- Loaded Addons
    add("")
    add("--- Loaded Addons (" .. tostring(r.loadedAddons and #r.loadedAddons or 0) .. ") ---")
    if r.loadedAddons and #r.loadedAddons > 0 then
        for _, addon in ipairs(r.loadedAddons) do
            add(("  %s (v%s)"):format(addon.name, addon.version or "?"))
        end
    end

    -- Helper: format buttons list with annotations
    local function addButtons(g, indent)
        if not g.buttons or #g.buttons == 0 then return end
        add(indent .. "buttons:")
        for i, btn in ipairs(g.buttons) do
            local main = ("%s  %d. %s:%s %q"):format(
                indent, i, btn.type or "?", tostring(btn.id or "?"), btn.name or "?")
            local extras = {}
            for k, v in pairs(btn) do
                if k ~= "type" and k ~= "id" and k ~= "name" then
                    extras[#extras + 1] = tostring(k) .. "=" .. formatValue(v)
                end
            end
            if btn.auraTracking and not btn.auraUnit then
                extras[#extras + 1] = "auraUnit=player(default)"
            end
            if btn.type == "spell" and btn.id and viewerAuraSet[btn.id] then
                extras[#extras + 1] = "~viewerAura=yes"
            end
            table.sort(extras)
            if #extras > 0 then
                main = main .. " " .. table.concat(extras, " ")
            end
            add(main)
        end
    end

    -- Helper: format alpha/fade keys from a table
    local function addAlphaKeys(t, indent, keys)
        local alphaParts = {}
        for _, k in ipairs(keys) do
            if t[k] ~= nil then
                alphaParts[#alphaParts + 1] = k .. "=" .. tostring(t[k])
            end
        end
        if #alphaParts > 0 then
            add(indent .. "alpha: " .. table.concat(alphaParts, " "))
        end
    end

    -- Helper: format "other" catch-all keys
    local function addOtherKeys(t, handledKeys, indent)
        local extraParts = {}
        for k, v in pairs(t) do
            if not handledKeys[k] then
                extraParts[#extraParts + 1] = tostring(k) .. "=" .. formatValue(v)
            end
        end
        table.sort(extraParts)
        if #extraParts > 0 then
            add(indent .. "other: " .. table.concat(extraParts, " "))
        end
    end

    -- Build panel-by-container index
    local panelsByContainer = {}  -- [containerId] = { {gid=N, group=table}, ... }
    local panelGroupIds = {}      -- set of groupIds that are panels
    if p.groups then
        for gid, g in pairs(p.groups) do
            if g.parentContainerId then
                panelGroupIds[gid] = true
                local cid = g.parentContainerId
                if not panelsByContainer[cid] then panelsByContainer[cid] = {} end
                panelsByContainer[cid][#panelsByContainer[cid] + 1] = { gid = gid, group = g }
            end
        end
        for _, panels in pairs(panelsByContainer) do
            table.sort(panels, function(a, b)
                local oa = a.group.order or 999
                local ob = b.group.order or 999
                if oa ~= ob then return oa < ob end
                return a.gid < b.gid
            end)
        end
    end

    -- Container alpha keys (full suite — containers own force conditions)
    local containerAlphaKeys = {
        "baselineAlpha", "forceAlphaInCombat", "forceAlphaOutOfCombat",
        "forceAlphaRegularMounted", "forceAlphaDragonriding",
        "forceAlphaTargetExists", "forceAlphaMouseover",
        "forceHideInCombat", "forceHideOutOfCombat",
        "forceHideRegularMounted", "forceHideDragonriding",
        "treatTravelFormAsMounted",
        "fadeDelay", "fadeInDuration", "fadeOutDuration",
    }

    -- Container handled keys (for "other" catch-all)
    local containerHandledKeys = {
        name=1, order=1, createdBy=1, isGlobal=1, enabled=1, locked=1,
        specs=1, heroTalents=1, anchor=1, loadConditions=1, folderId=1, frameStrata=1,
        baselineAlpha=1, forceAlphaInCombat=1, forceAlphaOutOfCombat=1,
        forceAlphaRegularMounted=1, forceAlphaDragonriding=1,
        forceAlphaTargetExists=1, forceAlphaMouseover=1,
        forceHideInCombat=1, forceHideOutOfCombat=1,
        forceHideRegularMounted=1, forceHideDragonriding=1,
        treatTravelFormAsMounted=1,
        fadeDelay=1, fadeInDuration=1, fadeOutDuration=1,
    }

    -- Panel alpha keys (panels own only their own fade, not force conditions)
    local panelAlphaKeys = {
        "baselineAlpha", "fadeDelay", "fadeInDuration", "fadeOutDuration",
    }

    -- Panel handled keys (for "other" catch-all)
    local panelHandledKeys = {
        name=1, parentContainerId=1, order=1, anchor=1, buttons=1, style=1,
        displayMode=1, masqueEnabled=1, compactLayout=1, maxVisibleButtons=1,
        compactGrowthDirection=1, specs=1, heroTalents=1,
        baselineAlpha=1, fadeDelay=1, fadeInDuration=1, fadeOutDuration=1,
        -- Legacy keys that may still exist on panels after migration
        enabled=1, locked=1, createdBy=1, isGlobal=1, loadConditions=1,
        folderId=1, frameStrata=1,
        forceAlphaInCombat=1, forceAlphaOutOfCombat=1,
        forceAlphaRegularMounted=1, forceAlphaDragonriding=1,
        forceAlphaTargetExists=1, forceAlphaMouseover=1,
        forceHideInCombat=1, forceHideOutOfCombat=1,
        forceHideRegularMounted=1, forceHideDragonriding=1,
        treatTravelFormAsMounted=1,
    }

    -- Containers & Panels (sorted by container order)
    add("")
    add("--- Containers & Panels ---")
    if p.groupContainers then
        local containerIds = {}
        for id in pairs(p.groupContainers) do containerIds[#containerIds + 1] = id end
        local specId = CooldownCompanion._currentSpecId
        table.sort(containerIds, function(a, b)
            local oa = CooldownCompanion:GetOrderForSpec(p.groupContainers[a], specId, 999)
            local ob = CooldownCompanion:GetOrderForSpec(p.groupContainers[b], specId, 999)
            if oa ~= ob then return oa < ob end
            return a < b
        end)

        for _, cid in ipairs(containerIds) do
            local c = p.groupContainers[cid]
            local panels = panelsByContainer[cid] or {}

            -- Container visibility
            local cVisStr
            if containerFrameVisible[cid] == true then
                cVisStr = "VISIBLE"
            elseif containerFrameVisible[cid] == false then
                cVisStr = "HIDDEN"
            else
                cVisStr = "NO FRAME"
            end

            -- Container header
            add(("[%d] %q | %s | %s | %s | %d panels | specs: %s | heroTalents: %s"):format(
                cid, c.name or "?",
                c.enabled ~= false and "enabled" or "DISABLED",
                cVisStr,
                c.locked ~= false and "locked" or "unlocked",
                #panels,
                formatSpecList(c.specs),
                formatSpecList(c.heroTalents)))

            -- Anchor
            local a = c.anchor
            if a then
                add(("  anchor: %s > %s > %s (%.1f, %.1f)"):format(
                    a.point or "?", a.relativeTo or "?", a.relativePoint or "?",
                    a.x or 0, a.y or 0))
            end

            -- Alpha/fade/force conditions
            addAlphaKeys(c, "  ", containerAlphaKeys)

            -- Load conditions
            if c.loadConditions then
                add("  load: " .. dumpKV(c.loadConditions))
            end

            -- Frame strata
            if c.frameStrata then
                add("  frameStrata: " .. tostring(c.frameStrata))
            end

            -- Other container-level keys
            addOtherKeys(c, containerHandledKeys, "  ")

            -- Nested panels
            for _, entry in ipairs(panels) do
                local gid = entry.gid
                local g = entry.group

                local pVisStr
                if groupFrameVisible[gid] == true then
                    pVisStr = "VISIBLE"
                elseif groupFrameVisible[gid] == false then
                    pVisStr = "HIDDEN"
                else
                    pVisStr = "NO FRAME"
                end

                local btnCount = g.buttons and #g.buttons or 0

                add(("  [%d] %q | %s | %s | %d buttons"):format(
                    gid, g.name or "?",
                    g.displayMode or "icons",
                    pVisStr,
                    btnCount))

                -- Panel anchor
                local pa = g.anchor
                if pa then
                    add(("    anchor: %s > %s > %s (%.1f, %.1f)"):format(
                        pa.point or "?", pa.relativeTo or "?", pa.relativePoint or "?",
                        pa.x or 0, pa.y or 0))
                end

                -- Panel spec filters (own, not inherited from container)
                if g.specs and next(g.specs) then
                    add("    specs: " .. formatSpecList(g.specs))
                end
                if g.heroTalents and next(g.heroTalents) then
                    add("    heroTalents: " .. formatSpecList(g.heroTalents))
                end

                -- Panel style
                if g.style then
                    add("    style: " .. dumpKV(g.style))
                end

                -- Panel alpha (own fade only)
                addAlphaKeys(g, "    ", panelAlphaKeys)

                -- Panel other
                addOtherKeys(g, panelHandledKeys, "    ")

                -- Buttons
                addButtons(g, "    ")
            end
            add("")
        end
    end

    -- Legacy/orphan groups (no parentContainerId — pre-container or broken data)
    if p.groups then
        local orphanIds = {}
        for gid, g in pairs(p.groups) do
            if not panelGroupIds[gid]
                or (g.parentContainerId and (not p.groupContainers or not p.groupContainers[g.parentContainerId])) then
                orphanIds[#orphanIds + 1] = gid
            end
        end
        if #orphanIds > 0 then
            table.sort(orphanIds)
            add("--- Legacy Groups ---")
            for _, gid in ipairs(orphanIds) do
                local g = p.groups[gid]
                local visStr
                if groupFrameVisible[gid] == true then
                    visStr = "VISIBLE"
                elseif groupFrameVisible[gid] == false then
                    visStr = "HIDDEN"
                else
                    visStr = "NO FRAME"
                end
                local btnCount = g.buttons and #g.buttons or 0
                add(("[%d] %q | %s | %s | %s | %d buttons | specs: %s"):format(
                    gid, g.name or "?",
                    g.displayMode or "icons",
                    g.enabled ~= false and "enabled" or "DISABLED",
                    visStr, btnCount,
                    formatSpecList(g.specs)))
                if g.parentContainerId then
                    add(("  parentContainerId: %d (MISSING)"):format(g.parentContainerId))
                end
                local a = g.anchor
                if a then
                    add(("  anchor: %s > %s > %s (%.1f, %.1f)"):format(
                        a.point or "?", a.relativeTo or "?", a.relativePoint or "?",
                        a.x or 0, a.y or 0))
                end
                if g.style then
                    add("  style: " .. dumpKV(g.style))
                end
                addAlphaKeys(g, "  ", containerAlphaKeys)
                if g.loadConditions then
                    add("  load: " .. dumpKV(g.loadConditions))
                end
                addOtherKeys(g, panelHandledKeys, "  ")
                addButtons(g, "  ")
                add("")
            end
        end
    end

    -- Resource Bars (with type names and explicit anchorGroupId)
    add("--- Resource Bars ---")
    local currentCharKey = diag.meta and diag.meta.charKey
    local legacyRb = rawget(p, "resourceBars")
    local legacyRbSeed = rawget(p, "legacyResourceBarsSeed")
    local rbStore = rawget(p, "resourceBarsByChar")
    local rb = type(rbStore) == "table" and currentCharKey and rbStore[currentCharKey]
    local function addResourceBarBucket(label, settings)
        if type(settings) ~= "table" then
            add(label .. "=nil")
            return
        end

        add(label .. ":")

        local rbSimple = {}
        local hasAnchorGroupId = false
        for k, v in pairs(settings) do
            if k == "anchorGroupId" then hasAnchorGroupId = true end
            if k ~= "resources" and k ~= "customAuraBars" then
                rbSimple[#rbSimple + 1] = tostring(k) .. "=" .. formatValue(v)
            end
        end
        if not hasAnchorGroupId then
            rbSimple[#rbSimple + 1] = "anchorGroupId=nil"
        end
        table.sort(rbSimple)
        add("  " .. table.concat(rbSimple, " "))

        if settings.resources then
            add("  resources:")
            local rids = {}
            for id in pairs(settings.resources) do rids[#rids + 1] = id end
            table.sort(rids)
            for _, id in ipairs(rids) do
                local typeName = RESOURCE_NAMES[id]
                local entryLabel = typeName
                    and ("[%s] (%s)"):format(tostring(id), typeName)
                    or ("[%s]"):format(tostring(id))
                local kv = dumpKV(settings.resources[id])
                add(("    %s %s"):format(entryLabel, kv ~= "" and kv or "(default)"))
            end
        end

        if settings.customAuraBars then
            local hasAny = false
            for _ in pairs(settings.customAuraBars) do hasAny = true; break end
            if hasAny then
                add("  customAuraBars:")
                local specIds = {}
                for sid in pairs(settings.customAuraBars) do specIds[#specIds + 1] = sid end
                table.sort(specIds)
                for _, sid in ipairs(specIds) do
                    local sName = sid == 0 and "Default" or specNames[sid]
                    local entryLabel = sName
                        and ("[%s] (%s)"):format(tostring(sid), sName)
                        or ("[%s]"):format(tostring(sid))
                    add(("    %s"):format(entryLabel))
                    local specBars = settings.customAuraBars[sid]
                    local slots = {}
                    for slot in pairs(specBars) do slots[#slots + 1] = slot end
                    table.sort(slots, function(a, b) return tostring(a) < tostring(b) end)
                    for _, slot in ipairs(slots) do
                        add(("      %s: %s"):format(tostring(slot), dumpKV(specBars[slot])))
                    end
                end
            end
        end
    end

    addResourceBarBucket("legacyProfile.resourceBars", legacyRb)
    addResourceBarBucket("legacyResourceBarsSeed", legacyRbSeed)
    if type(rbStore) == "table" then
        local storedChars = {}
        for charKey in pairs(rbStore) do
            storedChars[#storedChars + 1] = tostring(charKey)
        end
        table.sort(storedChars)
        add("currentChar=" .. tostring(currentCharKey))
        add("storedCharacters=" .. table.concat(storedChars, ", "))
    else
        add("resourceBarsByChar=nil")
    end
    addResourceBarBucket("resourceBarsByChar[currentChar]", rb)

    -- Cast Bar (with explicit anchorGroupId)
    add("")
    add("--- Cast Bar ---")
    local cbStore = rawget(p, "castBarByChar")
    local cb = type(cbStore) == "table" and currentCharKey and cbStore[currentCharKey]
    if type(cbStore) == "table" then
        local storedChars = {}
        for charKey in pairs(cbStore) do
            storedChars[#storedChars + 1] = tostring(charKey)
        end
        table.sort(storedChars)
        add("currentChar=" .. tostring(currentCharKey))
        add("storedCharacters=" .. table.concat(storedChars, ", "))
    end
    if cb then
        add(dumpKVWithNils(cb, {"anchorGroupId"}))
    end

    -- Frame Anchoring (with explicit anchorGroupId)
    add("")
    add("--- Frame Anchoring ---")
    local faStore = rawget(p, "frameAnchoringByChar")
    local fa = type(faStore) == "table" and currentCharKey and faStore[currentCharKey]
    if type(faStore) == "table" then
        local storedChars = {}
        for charKey in pairs(faStore) do
            storedChars[#storedChars + 1] = tostring(charKey)
        end
        table.sort(storedChars)
        add("currentChar=" .. tostring(currentCharKey))
        add("storedCharacters=" .. table.concat(storedChars, ", "))
    end
    if fa then
        local faSimple = {}
        local faComplex = {}
        local hasAnchorGroupId = false
        for k, v in pairs(fa) do
            if k == "anchorGroupId" then hasAnchorGroupId = true end
            if type(v) == "table" then
                faComplex[k] = v
            else
                faSimple[#faSimple + 1] = tostring(k) .. "=" .. tostring(v)
            end
        end
        if not hasAnchorGroupId then
            faSimple[#faSimple + 1] = "anchorGroupId=nil"
        end
        table.sort(faSimple)
        add(table.concat(faSimple, " "))
        local cKeys = {}
        for k in pairs(faComplex) do cKeys[#cKeys + 1] = k end
        table.sort(cKeys)
        for _, k in ipairs(cKeys) do
            add(("  %s: %s"):format(k, dumpKV(faComplex[k])))
        end
    end

    -- Global Style
    add("")
    add("--- Global Style ---")
    if p.globalStyle then
        add(dumpKV(p.globalStyle))
    end

    -- Folders (with member container listing)
    if p.folders then
        local hasAny = false
        for _ in pairs(p.folders) do hasAny = true; break end
        if hasAny then
            add("")
            add("--- Folders ---")
            local folderIds = {}
            for id in pairs(p.folders) do folderIds[#folderIds + 1] = id end
            table.sort(folderIds)
            for _, fid in ipairs(folderIds) do
                local f = p.folders[fid]
                -- List which containers belong to this folder
                local memberContainers = {}
                if p.groupContainers then
                    for cid, c in pairs(p.groupContainers) do
                        if c.folderId == fid then
                            memberContainers[#memberContainers + 1] = ("%d(%q)"):format(cid, c.name or "?")
                        end
                    end
                end
                table.sort(memberContainers)
                local membersStr = #memberContainers > 0 and table.concat(memberContainers, ", ") or "empty"
                add(("[%s] %q section=%s order=%s | containers: %s"):format(
                    tostring(fid), f.name or "?", f.section or "?", tostring(f.order), membersStr))
                if f.specs and next(f.specs) then
                    add(("  specs: %s"):format(formatSpecList(f.specs)))
                end
                if f.heroTalents and next(f.heroTalents) then
                    add(("  heroTalents: %s"):format(formatSpecList(f.heroTalents)))
                end
            end
        end
    end

    -- Other top-level profile keys (catch-all with recursive dump for future-proofing)
    add("")
    add("--- Other ---")
    local skipTopLevel = {
        -- Explicitly handled sections
        groups=1, groupContainers=1, folders=1, globalStyle=1,
        resourceBars=1, castBar=1, frameAnchoring=1,
        resourceBarsByChar=1, castBarByChar=1, frameAnchoringByChar=1,
        -- Structural counters
        nextGroupId=1, nextContainerId=1, nextFolderId=1,
        -- Settings shown in header or config-only
        locked=1, cdmHidden=1, minimap=1,
        hideInfoButtons=1, escClosesConfig=1, showAdvanced=1,
        autoAddPrefs=1, groupSettingPresets=1,
        -- Legacy migration data
        legacyResourceBarsSeed=1,
    }
    local function deepFormatValue(v, indent, maxDepth)
        if type(v) ~= "table" then return tostring(v) end
        maxDepth = maxDepth or 3
        local n = 0
        for _ in pairs(v) do n = n + 1 end
        if n == 0 then return "{}" end
        if maxDepth <= 0 then return "{" .. n .. " entries}" end
        -- Small simple tables: inline
        if n <= 5 then
            local allSimple = true
            for _, val in pairs(v) do
                if type(val) == "table" then allSimple = false; break end
            end
            if allSimple then return formatValue(v) end
        end
        -- Multi-line dump
        local parts = {}
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local childIndent = indent .. "  "
        for _, k in ipairs(keys) do
            local val = v[k]
            if type(val) == "table" then
                parts[#parts + 1] = childIndent .. tostring(k) .. ": " .. deepFormatValue(val, childIndent, maxDepth - 1)
            else
                parts[#parts + 1] = childIndent .. tostring(k) .. "=" .. tostring(val)
            end
        end
        return "\n" .. table.concat(parts, "\n")
    end
    local otherKeys = {}
    for k in pairs(p) do
        if not skipTopLevel[k] then
            otherKeys[#otherKeys + 1] = k
        end
    end
    table.sort(otherKeys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(otherKeys) do
        local v = p[k]
        if type(v) == "table" then
            add(tostring(k) .. ": " .. deepFormatValue(v, "  ", 3))
        else
            add(tostring(k) .. "=" .. tostring(v))
        end
    end

    return table.concat(lines, "\n")
end

StaticPopupDialogs["CDC_DIAGNOSTIC_EXPORT"] = {
    text = "Bug report string (Ctrl+C to copy, paste in Discord):",
    button1 = "Close",
    hasEditBox = true,
    OnShow = function(self)
        local snapshot = BuildDiagnosticSnapshot()
        local serialized = AceSerializer:Serialize(snapshot)
        local compressed = LibDeflate:CompressDeflate(serialized)
        local encoded = LibDeflate:EncodeForPrint(compressed)
        self.EditBox:SetText("CDCdiag:" .. encoded)
        self.EditBox:HighlightText()
        self.EditBox:SetFocus()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CDC_DIAGNOSTIC_IMPORT_CONFIRM"] = {
    text = "Import this bug report's profile into your addon? Your current profile will be overwritten.",
    button1 = "Import",
    button2 = "Cancel",
    OnAccept = function()
        if decodedDiagnostic and decodedDiagnostic.profile then
            local db = CooldownCompanion.db
            wipe(db.profile)
            for k, v in pairs(decodedDiagnostic.profile) do
                db.profile[k] = v
            end
            CS.selectedGroup = nil
            CS.selectedButton = nil
            wipe(CS.selectedButtons)
            wipe(CS.selectedGroups)
            -- Remap only the exporter's own entities to the importer's character.
            -- Other characters' entities keep their original createdBy so they
            -- appear in the browse-other-characters module instead of being
            -- flattened into the current character.
            local charKey = db.keys.char
            local exporterCharKey = decodedDiagnostic.meta and decodedDiagnostic.meta.charKey
            if db.profile.groups then
                for _, group in pairs(db.profile.groups) do
                    if not group.isGlobal and (exporterCharKey == nil or group.createdBy == exporterCharKey) then
                        group.createdBy = charKey
                    end
                end
            end
            if db.profile.groupContainers then
                for _, container in pairs(db.profile.groupContainers) do
                    if not container.isGlobal and (exporterCharKey == nil or container.createdBy == exporterCharKey) then
                        container.createdBy = charKey
                    end
                end
            end
            if db.profile.folders then
                for _, folder in pairs(db.profile.folders) do
                    if folder.section == "char" and (exporterCharKey == nil or folder.createdBy == exporterCharKey) then
                        folder.createdBy = charKey
                    end
                end
            end
            CooldownCompanion:ClearMigrationSentinels()
            CooldownCompanion:RunAllMigrations()
            CooldownCompanion:RefreshConfigPanel()
            CooldownCompanion:RefreshAllGroups()
            CooldownCompanion:Print("Diagnostic profile imported.")
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function OpenDiagnosticDecodePanel()
    if diagnosticDecodeFrame then
        diagnosticDecodeFrame:Show()
        return
    end

    local frame = AceGUI:Create("Window")
    frame:SetTitle("CDC Diagnostic Decode")
    frame:SetWidth(700)
    frame:SetHeight(600)
    frame:SetLayout("List")
    diagnosticDecodeFrame = frame

    local inputBox = AceGUI:Create("MultiLineEditBox")
    inputBox:SetLabel("Paste diagnostic string:")
    inputBox:SetFullWidth(true)
    inputBox:SetNumLines(6)
    inputBox.button:Hide()
    frame:AddChild(inputBox)

    local outputBox = AceGUI:Create("MultiLineEditBox")
    outputBox:SetLabel("Decoded report:")
    outputBox:SetFullWidth(true)
    outputBox:SetNumLines(20)
    outputBox.button:Hide()

    local btnGroup = AceGUI:Create("SimpleGroup")
    btnGroup:SetFullWidth(true)
    btnGroup:SetLayout("Flow")

    local decodeBtn = AceGUI:Create("Button")
    decodeBtn:SetText("Decode")
    decodeBtn:SetWidth(120)
    decodeBtn:SetCallback("OnClick", function()
        local text = inputBox:GetText()
        if not text or text == "" then return end
        text = text:gsub("%s+", "")
        if text:sub(1, 8) == "CDCdiag:" then
            text = text:sub(9)
        end
        local decoded = LibDeflate:DecodeForPrint(text)
        if not decoded then
            outputBox:SetText("Error: Failed to decode string.")
            return
        end
        local decompressed = LibDeflate:DecompressDeflate(decoded)
        if not decompressed then
            outputBox:SetText("Error: Failed to decompress.")
            return
        end
        local success, data = AceSerializer:Deserialize(decompressed)
        if not success or type(data) ~= "table" then
            outputBox:SetText("Error: Failed to deserialize.")
            return
        end
        decodedDiagnostic = data
        outputBox:SetText(FormatDiagnosticAsText(data))
    end)
    btnGroup:AddChild(decodeBtn)

    local copyBtn = AceGUI:Create("Button")
    copyBtn:SetText("Copy as Text")
    copyBtn:SetWidth(120)
    copyBtn:SetCallback("OnClick", function()
        if not decodedDiagnostic then return end
        outputBox.editBox:HighlightText()
        outputBox.editBox:SetFocus()
    end)
    btnGroup:AddChild(copyBtn)

    local importBtn = AceGUI:Create("Button")
    importBtn:SetText("Import Profile")
    importBtn:SetWidth(120)
    importBtn:SetCallback("OnClick", function()
        if not decodedDiagnostic or not decodedDiagnostic.profile then
            CooldownCompanion:Print("No diagnostic data to import.")
            return
        end
        StaticPopup_Show("CDC_DIAGNOSTIC_IMPORT_CONFIRM")
    end)
    btnGroup:AddChild(importBtn)

    frame:AddChild(btnGroup)
    frame:AddChild(outputBox)

    frame:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        diagnosticDecodeFrame = nil
        decodedDiagnostic = nil
    end)
end

function CooldownCompanion:OpenDiagnosticDecodePanel()
    OpenDiagnosticDecodePanel()
end
