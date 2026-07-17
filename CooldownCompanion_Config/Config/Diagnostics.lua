--[[
    CooldownCompanion - Config/Diagnostics
    Diagnostic snapshot system (bug report generation + decode panel).
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local AceGUI = LibStub("AceGUI-3.0")
local EncodeSharedPayload = ST._EncodeSharedPayload
local DecodeSharedPayload = ST._DecodeSharedPayload
local PrepareSharedImportText = ST._PrepareSharedImportText

-- File-local state
local diagnosticDecodeFrame = nil
local DIAGNOSTIC_REPORT_BUG_REPORT = "bugReport"

local function RejectUnsupportedImportPayload(data, dataLabel)
    if CooldownCompanion.IsUnsupportedImportPayload and CooldownCompanion:IsUnsupportedImportPayload(data) then
        CooldownCompanion:NotifyLegacySupportCutoff(dataLabel)
        return true
    end
    return false
end

local function CountTableEntries(t)
    if type(t) ~= "table" then return 0 end
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

local function SortedSelectionString(selection)
    if type(selection) ~= "table" then
        return ""
    end

    local keys = {}
    for key, selected in pairs(selection) do
        if selected then
            keys[#keys + 1] = tostring(key)
        end
    end
    table.sort(keys)
    return table.concat(keys, ",")
end

local function SummarizeButton(button)
    if type(button) ~= "table" then return nil end

    return {
        type = button.type,
        id = button.id,
        name = button.name,
        auraTracking = button.auraTracking == true,
        auraUnit = button.auraUnit,
        hideWhenInactive = button.hideWhenInactive == true,
        loadConditionCount = CountTableEntries(button.loadConditions),
        overrideCount = CountTableEntries(button.styleOverrides),
    }
end

local function SummarizePanel(panelId, panel)
    if type(panel) ~= "table" then return nil end

    return {
        id = panelId,
        name = panel.name,
        displayMode = panel.displayMode or "icons",
        parentContainerId = panel.parentContainerId,
        buttonCount = type(panel.buttons) == "table" and #panel.buttons or 0,
        specCount = CountTableEntries(panel.specs),
        heroTalentCount = CountTableEntries(panel.heroTalents),
        loadConditionCount = CountTableEntries(panel.loadConditions),
        masqueEnabled = panel.masqueEnabled == true,
        compactLayout = panel.compactLayout == true,
        maxVisibleButtons = panel.maxVisibleButtons,
    }
end

local function SummarizeContainer(containerId, container)
    if type(container) ~= "table" then return nil end

    return {
        id = containerId,
        name = container.name,
        enabled = container.enabled ~= false,
        locked = container.locked ~= false,
        folderId = container.folderId,
        specCount = CountTableEntries(container.specs),
        heroTalentCount = CountTableEntries(container.heroTalents),
        loadConditionCount = CountTableEntries(container.loadConditions),
    }
end

local function GetFrameShown(frameStates, id)
    if type(frameStates) ~= "table" or id == nil then
        return nil
    end

    local state = frameStates[tostring(id)]
    if type(state) ~= "table" then
        return nil
    end

    return state.shown == true
end

local function IncrementCount(counts, key)
    key = tostring(key or "unknown")
    counts[key] = (counts[key] or 0) + 1
end

local function BuildProfileShapeSummary(profile)
    local shape = {
        panelModes = {},
        buttonTypes = {},
    }

    local groups = type(profile) == "table" and profile.groups or nil
    if type(groups) ~= "table" then
        return shape
    end

    for _, group in pairs(groups) do
        if type(group) == "table" then
            IncrementCount(shape.panelModes, group.displayMode or "icons")

            if type(group.buttons) == "table" then
                for _, button in ipairs(group.buttons) do
                    if type(button) == "table" then
                        IncrementCount(shape.buttonTypes, button.type)
                    end
                end
            end
        end
    end

    return shape
end

local function BuildConfigDiagnosticSummary(profile, groupFrameStates, containerFrameStates)
    local groups = type(profile) == "table" and profile.groups or nil
    local containers = type(profile) == "table" and profile.groupContainers or nil
    local selectedContainerId = CS and CS.selectedContainer or nil
    local selectedPanelId = CS and CS.selectedGroup or nil
    local selectedButtonIndex = CS and CS.selectedButton or nil
    local selectedPanel = groups and selectedPanelId and groups[selectedPanelId] or nil
    local selectedButton = selectedPanel and selectedPanel.buttons and selectedButtonIndex and selectedPanel.buttons[selectedButtonIndex] or nil

    local visiblePanels = {}
    local visiblePanelCount = 0
    if groups and type(groupFrameStates) == "table" then
        local ids = {}
        for id, state in pairs(groupFrameStates) do
            if type(state) == "table" and state.shown then
                ids[#ids + 1] = tonumber(id) or id
            end
        end
        table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
        visiblePanelCount = #ids
        for _, panelId in ipairs(ids) do
            if #visiblePanels >= 12 then
                break
            end
            local panelSummary = SummarizePanel(panelId, groups[panelId])
            if panelSummary then
                visiblePanels[#visiblePanels + 1] = panelSummary
            end
        end
    end

    return {
        selectedFolder = CS and CS.selectedFolder or nil,
        selectedContainer = selectedContainerId,
        selectedGroup = selectedPanelId,
        selectedButton = selectedButtonIndex,
        selectedTab = CS and CS.selectedTab or nil,
        selectedContainerTab = CS and CS.selectedContainerTab or nil,
        buttonSettingsTab = CS and CS.buttonSettingsTab or nil,
        panelSettingsTab = CS and CS.panelSettingsTab or nil,
        resourcesEntrySelected = CS and CS.resourcesEntrySelected == true,
        castFramesEntrySelected = CS and CS.castFramesEntrySelected == true,
        resourcesSettingsTab = CS and CS.resourcesSettingsTab or nil,
        castBarHomeTab = CS and CS.castBarHomeTab or nil,
        customBarSettingsTab = CS and CS.customBarSettingsTab or nil,
        selectedCustomBarId = CS and CS.selectedCustomBarId or nil,
        selectedButtons = CS and SortedSelectionString(CS.selectedButtons) or "",
        selectedPanels = CS and SortedSelectionString(CS.selectedPanels) or "",
        selectedGroups = CS and SortedSelectionString(CS.selectedGroups) or "",
        selectedCustomBars = CS and SortedSelectionString(CS.selectedCustomBars) or "",
        selectedContainerSummary = SummarizeContainer(selectedContainerId, containers and selectedContainerId and containers[selectedContainerId] or nil),
        selectedPanelSummary = SummarizePanel(selectedPanelId, selectedPanel),
        selectedButtonSummary = SummarizeButton(selectedButton),
        selectedContainerFrameShown = GetFrameShown(containerFrameStates, selectedContainerId),
        selectedPanelFrameShown = GetFrameShown(groupFrameStates, selectedPanelId),
        visiblePanels = visiblePanels,
        visiblePanelCount = visiblePanelCount,
        visiblePanelsTruncated = visiblePanelCount > #visiblePanels,
        profileShape = BuildProfileShapeSummary(profile),
    }
end

local function BuildDiagnosticSnapshot()
    local db = CooldownCompanion.db
    local snapshot = {
        _v = 2,
        reportKind = DIAGNOSTIC_REPORT_BUG_REPORT,
    }

    -- Meta
    local _, classFilename, classID = UnitClass("player")
    local specIndex = C_SpecializationInfo.GetSpecialization()
    local specID, specName
    if specIndex then
        specID, specName = C_SpecializationInfo.GetSpecializationInfo(specIndex)
    end
    local buildVersion, _, _, interfaceVersion = GetBuildInfo()
    local addonVersion = (ST._GetAddonVersion and ST._GetAddonVersion()) or "unknown"

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

    local barsAndFramesRuntime = nil
    if CooldownCompanion.GetBarsAndFramesRuntimeDebugInfo then
        barsAndFramesRuntime = CooldownCompanion:GetBarsAndFramesRuntimeDebugInfo()
    end

    local visualStateDiagnostics = nil
    if CooldownCompanion.CaptureButtonVisualStateDiagnostics then
        visualStateDiagnostics = CooldownCompanion:CaptureButtonVisualStateDiagnostics({
            maxRows = 16,
        })
    end

    local loadedAddons = {}
    for i = 1, C_AddOns.GetNumAddOns() do
        local name, title = C_AddOns.GetAddOnInfo(i)
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
        barsAndFramesRuntime = barsAndFramesRuntime,
        resourceBarRuntime = resourceBarRuntime,
        visualStateDiagnostics = visualStateDiagnostics,
        loadedAddons = loadedAddons,
    }

    snapshot.config = BuildConfigDiagnosticSummary(db.profile, groupFrameStates, containerFrameStates)

    -- Build spec name cache for all referenced spec IDs
    local specNameCache = {}
    local function cacheSpecName(sid)
        sid = tonumber(sid)
        if sid and sid ~= 0 and not specNameCache[sid] then
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
    local function cacheSpecsFromResourceStores(resourceStores)
        if type(resourceStores) ~= "table" then
            return
        end
        for _, resourceSettings in pairs(resourceStores) do
            local customBars = type(resourceSettings) == "table"
                and (type(resourceSettings.customBars) == "table" and resourceSettings.customBars or resourceSettings.customAuraBars)
            if type(customBars) == "table" then
                if type(customBars.entries) == "table" or type(customBars.order) == "table" then
                    local entries = type(customBars.entries) == "table" and customBars.entries or {}
                    for _, entry in pairs(entries) do
                        if type(entry) == "table" then
                            cacheSpecsFromTable(entry.specs)
                            cacheSpecName(entry.specID or entry.spec or entry.sourceSpecID)
                        end
                    end
                    local layoutOrder = type(resourceSettings.layoutOrder) == "table" and resourceSettings.layoutOrder or {}
                    for sid, layout in pairs(layoutOrder) do
                        if type(layout) == "table" and type(layout.customBars) == "table" and next(layout.customBars) then
                            cacheSpecName(sid)
                        end
                    end
                else
                    for sid in pairs(customBars) do
                        cacheSpecName(sid)
                    end
                end
            end
        end
    end
    cacheSpecsFromResourceStores(rawget(db.profile, "resourceBarsByClass"))
    cacheSpecsFromResourceStores(rawget(db.profile, "resourceBarsByChar"))
    snapshot.meta.specNameCache = specNameCache

    -- Keep the decoded report compact while attaching an importable profile.
    snapshot.profile = db.profile

    return snapshot
end

local function FormatIDList(t)
    if not t or #t == 0 then return "none" end
    local parts = {}
    for _, v in ipairs(t) do parts[#parts + 1] = tostring(v) end
    return table.concat(parts, ", ")
end

local function AddVisualStateDiagnosticsLines(add, visualStateDiagnostics)
    if not visualStateDiagnostics then
        return
    end

    local vsd = visualStateDiagnostics
    add("Visual State Diagnostics:")
    add(("  rows=%s mismatched=%s missing=%s refreshedFrames=%s cap=%s restored=%s"):format(
        tostring(vsd.rowCount or 0),
        tostring(vsd.mismatchCount or 0),
        tostring(vsd.missingSnapshots or 0),
        tostring(vsd.refreshedFrames or 0),
        tostring(vsd.maxRows or "?"),
        tostring(vsd.captureRestored)
    ))
    if vsd.reason then
        add("  reason=" .. tostring(vsd.reason))
    end
    if vsd.truncated then
        add("  truncated=true")
    end
    if type(vsd.rows) == "table" and #vsd.rows > 0 then
        for _, row in ipairs(vsd.rows) do
            local parts = {
                ("[%s:%s]"):format(tostring(row.groupId or "?"), tostring(row.buttonIndex or "?")),
                tostring(row.displayMode or "?"),
                tostring(row.buttonType or "?") .. ":" .. tostring(row.buttonId or "?"),
                "phase=" .. tostring(row.phase or "nil"),
            }
            if row.cooldown then
                parts[#parts + 1] = "cd=" .. tostring(row.cooldown.state or "nil")
                parts[#parts + 1] = "visual=" .. tostring(row.cooldown.visualActive)
            end
            if row.visibility then
                parts[#parts + 1] = "visibility=" .. tostring(row.visibility.mode or (row.visibility.hidden and "hidden" or "visible"))
                parts[#parts + 1] = "hidden=" .. tostring(row.visibility.hidden)
                if row.visibility.alphaOverride ~= nil then
                    parts[#parts + 1] = "alpha=" .. tostring(row.visibility.alphaOverride)
                end
                if row.visibility.rawMode and row.visibility.rawMode ~= row.visibility.mode then
                    parts[#parts + 1] = "rawVisibility=" .. tostring(row.visibility.rawMode)
                end
                if row.visibility.overrideSource then
                    parts[#parts + 1] = "override=" .. tostring(row.visibility.overrideSource)
                end
                if type(row.visibility.reasonNames) == "table" and #row.visibility.reasonNames > 0 then
                    parts[#parts + 1] = "visibilityReason=" .. table.concat(row.visibility.reasonNames, "+")
                end
                if row.visibility.triggerSuppressed then
                    parts[#parts + 1] = "triggerSuppressed=true"
                end
            end
            if row.visuals then
                parts[#parts + 1] = "desat=" .. tostring(row.visuals.desaturationApplied)
                parts[#parts + 1] = "tint=" .. tostring(row.visuals.tintActive)
                if row.visuals.tintIntentReason and row.visuals.tintIntentReason ~= "base" then
                    parts[#parts + 1] = "tintReason=" .. tostring(row.visuals.tintIntentReason)
                end
                parts[#parts + 1] = "fill=" .. tostring(row.visuals.iconFillActive)
                if row.visuals.iconFillIntentMode then
                    parts[#parts + 1] = "fillMode=" .. tostring(row.visuals.iconFillIntentMode)
                end
                if row.visuals.iconFillIntentReason and row.visuals.iconFillIntentReason ~= "inactive" then
                    parts[#parts + 1] = "fillReason=" .. tostring(row.visuals.iconFillIntentReason)
                end
                local showGlowDiagnostics = row.displayMode == "icons" and row.phase == "post-dispatch"
                if showGlowDiagnostics then
                    local procGlowReason = row.visuals.procGlowReason
                    if row.visuals.procGlowActive
                        or row.visuals.procGlowPreview
                        or row.visuals.procGlowCombatSuppressed then
                        parts[#parts + 1] = "procGlow=" .. tostring(row.visuals.procGlowActive)
                        if procGlowReason then
                            parts[#parts + 1] = "procGlowReason=" .. tostring(procGlowReason)
                        end
                    end
                    local auraGlowReason = row.visuals.auraGlowReason
                    if row.visuals.auraGlowActive
                        or row.visuals.auraGlowPandemicIntent
                        or row.visuals.auraGlowPreview
                        or row.visuals.auraGlowCombatSuppressed then
                        parts[#parts + 1] = "auraGlow=" .. tostring(row.visuals.auraGlowActive)
                        if row.visuals.auraGlowPandemicIntent or row.visuals.auraGlowPandemicApplied then
                            parts[#parts + 1] = "pandemicGlow=true"
                        end
                        if auraGlowReason then
                            parts[#parts + 1] = "auraGlowReason=" .. tostring(auraGlowReason)
                        end
                    end
                    local readyGlowReason = row.visuals.readyGlowReason
                    if row.visuals.readyGlowActive
                        or row.visuals.readyGlowPreview
                        or row.visuals.readyGlowCombatSuppressed
                        or row.visuals.readyGlowSuppressedByProc
                        or row.visuals.readyGlowAuraSuppressed
                        or row.visuals.readyGlowMaxCharges
                        or readyGlowReason == "duration-window" then
                        parts[#parts + 1] = "readyGlow=" .. tostring(row.visuals.readyGlowActive)
                        if readyGlowReason then
                            parts[#parts + 1] = "readyGlowReason=" .. tostring(readyGlowReason)
                        end
                        if row.visuals.readyGlowSuppressedByProc then
                            parts[#parts + 1] = "readySuppressed=proc"
                        elseif row.visuals.readyGlowAuraSuppressed then
                            parts[#parts + 1] = "readySuppressed=aura"
                        elseif row.visuals.readyGlowCombatSuppressed then
                            parts[#parts + 1] = "readySuppressed=combat"
                        end
                        if row.visuals.readyGlowMaxCharges then
                            parts[#parts + 1] = "readyMaxCharges=true"
                        end
                    end
                end
            end
            local hasBarSignals = row.bar and (row.bar.intentAvailable == true
                or row.bar.stackDisplay == true
                or row.bar.gcdSuppressed == true
                or (row.displayMode == "bars" and row.phase == "post-dispatch"))
            if hasBarSignals then
                parts[#parts + 1] = "bar=" .. tostring(row.bar.domain or "missing")
                if row.bar.colorReason then
                    parts[#parts + 1] = "barColor=" .. tostring(row.bar.colorReason)
                end
                if row.bar.auraEffectActive then
                    parts[#parts + 1] = "barEffect=" .. tostring(row.bar.auraEffectReason or "aura")
                end
                if row.bar.pulseActive then
                    parts[#parts + 1] = "barPulse=" .. tostring(row.bar.pulseMode or true)
                end
                if row.bar.colorShiftActive then
                    parts[#parts + 1] = "barShift=" .. tostring(row.bar.colorShiftMode or true)
                end
                if row.bar.stackDisplay then
                    parts[#parts + 1] = "barStack=" .. tostring(row.bar.stackMode or "default")
                end
                if row.bar.gcdSuppressed then
                    parts[#parts + 1] = "barGCDSuppressed=true"
                end
            end
            if row.text and (row.displayMode == "text" or row.text.intentAvailable == true) then
                local textDomain = row.text.domain
                if not textDomain and row.text.preservedSecretTextRender == true then
                    textDomain = "preserved-secret"
                end
                parts[#parts + 1] = "text=" .. tostring(textDomain or "missing")
                if row.text.appliedWritePath then
                    parts[#parts + 1] = "textWrite=" .. tostring(row.text.appliedWritePath)
                end
                if row.text.stackSource then
                    parts[#parts + 1] = "stack=" .. tostring(row.text.stackSource)
                end
                if row.text.secretDuration or row.text.secretStack or row.text.secretName then
                    local secretParts = {}
                    if row.text.secretDuration then
                        secretParts[#secretParts + 1] = tostring(row.text.secretDurationToken or "duration")
                    end
                    if row.text.secretStack then
                        secretParts[#secretParts + 1] = "stack"
                    end
                    if row.text.secretName then
                        secretParts[#secretParts + 1] = "name"
                    end
                    parts[#parts + 1] = "textSecret=" .. table.concat(secretParts, "+")
                end
                if row.text.pulseActive then
                    parts[#parts + 1] = "pulse=true"
                end
            end
            if type(row.mismatches) == "table" and #row.mismatches > 0 then
                parts[#parts + 1] = "mismatch=" .. table.concat(row.mismatches, ",")
            elseif row.missingSnapshot then
                parts[#parts + 1] = "snapshot=missing"
            else
                parts[#parts + 1] = "match=ok"
            end
            add("  " .. table.concat(parts, " "))
        end
    end
end

local function FormatCountMap(counts)
    if type(counts) ~= "table" then
        return "none"
    end

    local keys = {}
    for key in pairs(counts) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

    if #keys == 0 then
        return "none"
    end

    local parts = {}
    for _, key in ipairs(keys) do
        parts[#parts + 1] = tostring(key) .. "=" .. tostring(counts[key])
    end
    return table.concat(parts, " ")
end

local function FormatBool(value)
    return tostring(value == true)
end

local function AddBarsAndFramesRuntimeLines(add, barsAndFramesRuntime)
    local baf = barsAndFramesRuntime
    if not baf then
        return
    end

    add(("Bars & Frames Runtime: enabled=%s generation=%s reason=%s"):format(
        FormatBool(baf.enabled),
        tostring(baf.generation or 0),
        tostring(baf.lastReason or "nil")
    ))
    add(("  Flags: resourceBars=%s castBar=%s frameAnchoring=%s"):format(
        FormatBool(baf.flags and baf.flags.resourceBars),
        FormatBool(baf.flags and baf.flags.castBar),
        FormatBool(baf.flags and baf.flags.frameAnchoring)
    ))
    local counters = baf.counters or {}
    add(("  Counters: refresh=%s evaluate=%s skipped=%s activate=%s deactivate=%s work=%s"):format(
        tostring(counters.refresh or 0),
        tostring(counters.evaluate or 0),
        tostring(counters.skippedEvaluate or 0),
        tostring(counters.activate or 0),
        tostring(counters.deactivate or 0),
        FormatCountMap(counters.work)
    ))
    local rb = baf.resourceBars or {}
    add(("  Resource Bars: applied=%s onUpdate=%s lifecycleEvents=%s updateEvents=%s hooks=%s activeBars=%s"):format(
        FormatBool(rb.applied),
        FormatBool(rb.onUpdateActive),
        FormatBool(rb.lifecycleEventsActive),
        FormatBool(rb.updateEventsActive),
        FormatBool(rb.hooksInstalled),
        tostring(rb.activeBarCount or 0)
    ))
    local cb = baf.castBar or {}
    add(("  Cast Bar: applied=%s castEvents=%s hooks=%s"):format(
        FormatBool(cb.applied),
        FormatBool(cb.castEventsActive),
        FormatBool(cb.hooksInstalled)
    ))
    local fa = baf.frameAnchoring or {}
    add(("  Frame Anchoring: applied=%s alphaSync=%s pendingCombat=%s hooks=%s"):format(
        FormatBool(fa.applied),
        FormatBool(fa.alphaSyncActive),
        FormatBool(fa.pendingCombatReevaluate),
        FormatBool(fa.hooksInstalled)
    ))
end

local function FormatRelevantAddonList(loadedAddons)
    if type(loadedAddons) ~= "table" then
        return "none"
    end

    local relevantNames = {
        ["!BugGrabber"] = true,
        AddonProfiler = true,
        Bartender4 = true,
        BugSack = true,
        CC_DevBridge = true,
        Clicked = true,
        Dominos = true,
        ElvUI = true,
        Masque = true,
        OmniCC = true,
        Plater = true,
        Platynator = true,
        WeakAuras = true,
    }
    local found = {}
    for _, addon in ipairs(loadedAddons) do
        local name = addon and addon.name
        if relevantNames[name] then
            found[#found + 1] = name .. " v" .. tostring(addon.version or "?")
        end
    end
    table.sort(found)

    if #found == 0 then
        return "none"
    end
    return table.concat(found, ", ")
end

local function AddAgentDebugSignals(add, diag)
    local r = diag.runtime or {}
    local c = diag.config or {}
    local shape = c.profileShape or {}
    local vsd = r.visualStateDiagnostics

    add("--- Agent Debug Signals ---")
    add("Profile Shape: panelModes=" .. FormatCountMap(shape.panelModes)
        .. " | buttonTypes=" .. FormatCountMap(shape.buttonTypes))

    if not c.selectedFolder
        and not c.selectedContainer
        and not c.selectedGroup
        and not c.selectedButton
        and not c.selectedCustomBarId then
        add("Selection Signal: no active config selection captured; select the broken group, panel, entry, or Custom Bar first if possible.")
    else
        add("Selection Signal: active selection captured.")
    end

    if vsd then
        add(("Visual-State Signal: mismatched=%s missing=%s restored=%s truncated=%s"):format(
            tostring(vsd.mismatchCount or 0),
            tostring(vsd.missingSnapshots or 0),
            tostring(vsd.captureRestored),
            tostring(vsd.truncated == true)
        ))
    else
        add("Visual-State Signal: unavailable")
    end
    if r.barsAndFramesRuntime then
        add(("Bars & Frames Runtime: enabled=%s flags=%s"):format(
            FormatBool(r.barsAndFramesRuntime.enabled),
            FormatCountMap(r.barsAndFramesRuntime.flags)
        ))
    end
    add("Relevant Addons: " .. FormatRelevantAddonList(r.loadedAddons))
    add("Profile Attachment: compact profile included in this bug report string.")
end

local function FormatDiagnosticBugReportAsText(diag)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    local m = diag.meta or {}
    local r = diag.runtime or {}
    local c = diag.config or {}

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

    add("")
    AddAgentDebugSignals(add, diag)

    add("")
    add("--- Current Config Context ---")
    add(("Selection: folder=%s group=%s panel=%s button=%s customBar=%s"):format(
        tostring(c.selectedFolder or "nil"),
        tostring(c.selectedContainer or "nil"),
        tostring(c.selectedGroup or "nil"),
        tostring(c.selectedButton or "nil"),
        tostring(c.selectedCustomBarId or "nil")))
    add(("Tabs: selected=%s container=%s panel=%s button=%s resources=%s castBar=%s customBar=%s"):format(
        tostring(c.selectedTab or "nil"),
        tostring(c.selectedContainerTab or "nil"),
        tostring(c.panelSettingsTab or "nil"),
        tostring(c.buttonSettingsTab or "nil"),
        tostring(c.resourcesSettingsTab or "nil"),
        tostring(c.castBarHomeTab or "nil"),
        tostring(c.customBarSettingsTab or "nil")))
    if c.selectedButtons ~= "" or c.selectedPanels ~= "" or c.selectedGroups ~= "" or c.selectedCustomBars ~= "" then
        add(("Multi-select: buttons=%s panels=%s groups=%s customBars=%s"):format(
            c.selectedButtons ~= "" and c.selectedButtons or "none",
            c.selectedPanels ~= "" and c.selectedPanels or "none",
            c.selectedGroups ~= "" and c.selectedGroups or "none",
            c.selectedCustomBars ~= "" and c.selectedCustomBars or "none"))
    end
    if c.selectedContainerSummary then
        local container = c.selectedContainerSummary
        add(("Selected Group: [%s] %q enabled=%s locked=%s specs=%s heroTalents=%s loadConditions=%s shown=%s"):format(
            tostring(container.id or "?"),
            tostring(container.name or "?"),
            tostring(container.enabled),
            tostring(container.locked),
            tostring(container.specCount or 0),
            tostring(container.heroTalentCount or 0),
            tostring(container.loadConditionCount or 0),
            tostring(c.selectedContainerFrameShown)))
    end
    if c.selectedPanelSummary then
        local panel = c.selectedPanelSummary
        add(("Selected Panel: [%s] %q mode=%s buttons=%s parent=%s specs=%s heroTalents=%s loadConditions=%s shown=%s"):format(
            tostring(panel.id or "?"),
            tostring(panel.name or "?"),
            tostring(panel.displayMode or "?"),
            tostring(panel.buttonCount or 0),
            tostring(panel.parentContainerId or "nil"),
            tostring(panel.specCount or 0),
            tostring(panel.heroTalentCount or 0),
            tostring(panel.loadConditionCount or 0),
            tostring(c.selectedPanelFrameShown)))
    end
    if c.selectedButtonSummary then
        local button = c.selectedButtonSummary
        add(("Selected Entry: %s:%s %q auraTracking=%s auraUnit=%s hideWhenInactive=%s loadConditions=%s overrides=%s"):format(
            tostring(button.type or "?"),
            tostring(button.id or "?"),
            tostring(button.name or "?"),
            tostring(button.auraTracking),
            tostring(button.auraUnit or "nil"),
            tostring(button.hideWhenInactive),
            tostring(button.loadConditionCount or 0),
            tostring(button.overrideCount or 0)))
    end
    if type(c.visiblePanels) == "table" then
        add(("Visible Panels: %s%s"):format(
            tostring(c.visiblePanelCount or #c.visiblePanels),
            c.visiblePanelsTruncated and " (truncated)" or ""))
        for _, panel in ipairs(c.visiblePanels) do
            add(("  [%s] %q mode=%s buttons=%s parent=%s"):format(
                tostring(panel.id or "?"),
                tostring(panel.name or "?"),
                tostring(panel.displayMode or "?"),
                tostring(panel.buttonCount or 0),
                tostring(panel.parentContainerId or "nil")))
        end
    end

    add("")
    add("--- Runtime ---")
    add(("Cached Spec ID: %s | Hero Spec ID: %s"):format(
        tostring(r.currentSpecId or "nil"), tostring(r.currentHeroSpecId or "nil")))
    add(("Assisted Spell: %s"):format(tostring(r.assistedSpellID or "none")))
    add(("Viewer Aura Spells: %s"):format(FormatIDList(r.viewerAuraSpells)))
    add(("Proc Overlay Spells: %s"):format(FormatIDList(r.procOverlaySpells)))
    add(("Range Check Spells: %s"):format(FormatIDList(r.rangeCheckSpells)))

    AddBarsAndFramesRuntimeLines(add, r.barsAndFramesRuntime)

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
            add("  " .. table.concat(parts, " "))
        end
    end

    AddVisualStateDiagnosticsLines(add, r.visualStateDiagnostics)

    add("")
    add("--- Loaded Addons (" .. tostring(r.loadedAddons and #r.loadedAddons or 0) .. ") ---")
    if r.loadedAddons and #r.loadedAddons > 0 then
        for _, addon in ipairs(r.loadedAddons) do
            add(("  %s (v%s)"):format(addon.name, addon.version or "?"))
        end
    end

    return table.concat(lines, "\n")
end

local function FormatDiagnosticAsText(diag)
    return FormatDiagnosticBugReportAsText(diag)
end

local function SetDiagnosticExportText(popup)
    local snapshot = BuildDiagnosticSnapshot()
    popup.EditBox:SetText("CDCdiag:" .. EncodeSharedPayload(snapshot, "diagnostic"))
    popup.EditBox:HighlightText()
    popup.EditBox:SetFocus()
end

StaticPopupDialogs["CDC_DIAGNOSTIC_BUG_REPORT"] = {
    text = "Bug report string with compact profile export (Ctrl+C to copy, paste in Discord):",
    button1 = "Close",
    hasEditBox = true,
    OnShow = function(self)
        SetDiagnosticExportText(self)
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
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
        local preparedText, compactText = PrepareSharedImportText(text)
        if not preparedText then return end
        outputBox.canCopyDiagnosticText = nil
        if compactText:sub(1, 8) == "CDCdiag:" then
            preparedText = compactText:sub(9)
            compactText = preparedText
        end
        if compactText:sub(1, 2) == "^1" then
            outputBox:SetText("")
            CooldownCompanion:NotifyLegacySupportCutoff("diagnostic string")
            return
        end
        local success, data = DecodeSharedPayload(preparedText)
        if not success or type(data) ~= "table" then
            outputBox:SetText("Error: Failed to deserialize.")
            return
        end
        if RejectUnsupportedImportPayload(data, "diagnostic string") then
            outputBox:SetText("")
            return
        end
        outputBox.canCopyDiagnosticText = true
        outputBox:SetText(FormatDiagnosticAsText(data))
    end)
    btnGroup:AddChild(decodeBtn)

    local copyBtn = AceGUI:Create("Button")
    copyBtn:SetText("Copy as Text")
    copyBtn:SetWidth(120)
    copyBtn:SetCallback("OnClick", function()
        if not outputBox.canCopyDiagnosticText then return end
        outputBox.editBox:HighlightText()
        outputBox.editBox:SetFocus()
    end)
    btnGroup:AddChild(copyBtn)

    frame:AddChild(btnGroup)
    frame:AddChild(outputBox)

    frame:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        diagnosticDecodeFrame = nil
    end)
end

function CooldownCompanion:_configOpenDiagnosticDecodePanelImpl()
    OpenDiagnosticDecodePanel()
end
