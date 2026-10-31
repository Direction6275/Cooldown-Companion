--[[
    CooldownCompanion - ResourceBarPanelsHelpers
    Query helpers, autocomplete, and shared resource-bar config utilities
    for the resource bar config panel.

    Exports via ST._RBP table. Consuming files alias to locals at load time.
    Shared constants are imported from ST._RB (eliminating _CONFIG duplicates).
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState
local AceGUI = LibStub("AceGUI-3.0")

-- Shared constants from ResourceBarConstants (eliminates _CONFIG duplicates)
local RB = ST._RB
local RESOURCE_HEALTH = RB.RESOURCE_HEALTH
local CLASS_RESOURCES_CONFIG = RB.CLASS_RESOURCES_CONFIG
local SPEC_RESOURCES_CONFIG = RB.SPEC_RESOURCES_CONFIG
local IsAstralPowerAvailableForCurrentDruidSpec = RB.IsAstralPowerAvailableForCurrentDruidSpec
local DRUID_CLASS_ID = 11
local DRUID_BALANCE_SPEC_ID = 102

local ResolveSpecOverrideKey = ST._ResolveSpecOverrideKey

------------------------------------------------------------------------
-- Spell/aura autocomplete slices
------------------------------------------------------------------------
local auraBarAutocompleteCache = nil
local auraBarAutocompleteSource = nil

local function IsSharedAuraAutocompleteEntry(entry)
    return type(entry) == "table"
        and (entry.autocompleteKind == "spell" or entry.autocompleteKind == "aura")
end

local function BuildAuraBarAutocompleteCache()
    local sharedCache = CS.autocompleteCache
        or (ST._BuildAutocompleteCache and ST._BuildAutocompleteCache())
        or {}
    if auraBarAutocompleteCache and auraBarAutocompleteSource == sharedCache then
        return auraBarAutocompleteCache
    end

    local cache = {}
    for _, entry in ipairs(sharedCache) do
        if IsSharedAuraAutocompleteEntry(entry) then
            cache[#cache + 1] = entry
        end
    end
    auraBarAutocompleteCache = cache
    auraBarAutocompleteSource = sharedCache
    return cache
end

-- The AURA-only slice of the cache above, for fields that track an aura
-- rather than name a bar: a resource overlay and an icon entry's tracked-aura
-- list both want buffs and debuffs, never plain spells. Cached off the same
-- shared source and invalidated by its identity, exactly like its parent.
--
-- Rows are re-identified to trackedAuraID (the spellID the applied aura
-- carries) when it differs from the row's cast/talent spellID: these fields
-- store the picked ID verbatim into an includeSpellIDs-style candidate list,
-- and only the applied ID ever matches there. Shared rows are copied, never
-- mutated — the parent cache keeps the row identity for standalone adds.
local trackedAuraAutocompleteCache = nil
local trackedAuraAutocompleteSource = nil

local function BuildTrackedAuraAutocompleteCache()
    local sharedCache = BuildAuraBarAutocompleteCache()
    if trackedAuraAutocompleteCache and trackedAuraAutocompleteSource == sharedCache then
        return trackedAuraAutocompleteCache
    end

    local cache = {}
    for _, entry in ipairs(sharedCache) do
        if entry.autocompleteKind == "aura" then
            local trackedID = entry.trackedAuraID
            if trackedID and trackedID ~= entry.id then
                local info = C_Spell.GetSpellInfo(trackedID)
                local name = info and info.name or entry.name
                cache[#cache + 1] = {
                    id = trackedID,
                    name = name,
                    displayName = ("%s |cff999999(%d)|r"):format(name, trackedID),
                    nameLower = name:lower(),
                    icon = info and info.iconID or entry.icon,
                    category = entry.category,
                    autocompleteKind = "aura",
                    isItem = false,
                    forceAura = true,
                }
            else
                cache[#cache + 1] = entry
            end
        end
    end
    trackedAuraAutocompleteCache = cache
    trackedAuraAutocompleteSource = sharedCache
    return cache
end

local function ResolveAuraBarAutocompleteEntry(text)
    if not text then return nil end
    local cleaned = text:gsub("^%s+", ""):gsub("%s+$", "")
    if cleaned == "" then
        return nil
    end

    local numeric = tonumber(cleaned)
    local lookup = cleaned:lower()
    local cache = BuildAuraBarAutocompleteCache()
    for _, entry in ipairs(cache) do
        local entryNameLower = type(entry.name) == "string" and entry.name:lower() or nil
        if (numeric and entry.id == numeric) or entry.nameLower == lookup or entryNameLower == lookup then
            return entry
        end
    end

    return nil
end

local AddHealthResource = RB.AddHealthResource

local function GetConfigActiveResources()
    local _, _, classID = UnitClass("player")
    if not classID then return {} end

    local specID = nil
    local specIdx = C_SpecializationInfo.GetSpecialization()
    if specIdx then
        specID = C_SpecializationInfo.GetSpecializationInfo(specIdx)
    end

    -- For Druid, only expose Astral Power while currently in Balance spec.
    if classID == 11 then
        if IsAstralPowerAvailableForCurrentDruidSpec() then
            return AddHealthResource(CLASS_RESOURCES_CONFIG[11])
        end
        local resources = {}
        for _, powerType in ipairs(CLASS_RESOURCES_CONFIG[11] or {}) do
            if powerType ~= 8 then
                resources[#resources + 1] = powerType
            end
        end
        return AddHealthResource(resources)
    end

    if specID and SPEC_RESOURCES_CONFIG[specID] then
        return AddHealthResource(SPEC_RESOURCES_CONFIG[specID])
    end

    return AddHealthResource(CLASS_RESOURCES_CONFIG[classID] or {})
end

------------------------------------------------------------------------
-- Collapsed section state
------------------------------------------------------------------------
local resourceBarCollapsedSections = {}

local function GetCurrentConfigSpecID()
    local specIdx = C_SpecializationInfo.GetSpecialization()
    if specIdx then
        return C_SpecializationInfo.GetSpecializationInfo(specIdx)
    end
    return nil
end

local function AddUniqueResource(result, seen, powerType)
    if powerType == nil or powerType == RESOURCE_HEALTH or seen[powerType] then
        return
    end
    result[#result + 1] = powerType
    seen[powerType] = true
end

local function ResourceListContains(resourceList, powerType)
    if type(resourceList) ~= "table" then
        return false
    end
    for _, listedPowerType in ipairs(resourceList) do
        if listedPowerType == powerType then
            return true
        end
    end
    return false
end

local function GetPlayerClassAndSpecsConfig()
    local _, _, classID = UnitClass("player")
    local specIDs = {}
    local numSpecs = GetNumSpecializations() or 0
    for specIndex = 1, numSpecs do
        local specID = C_SpecializationInfo.GetSpecializationInfo(specIndex)
        if specID then
            specIDs[#specIDs + 1] = specID
        end
    end
    return classID, specIDs
end

local function GetConfigEditableResources(settings)
    settings = settings or CooldownCompanion:GetResourceBarSettings()
    if not (type(settings) == "table" and settings.enabled == true) then
        return {}
    end

    local classID, specIDs = GetPlayerClassAndSpecsConfig()
    if not classID then
        return {}
    end

    local result = {}
    local seen = {}
    for _, powerType in ipairs(CLASS_RESOURCES_CONFIG[classID] or {}) do
        AddUniqueResource(result, seen, powerType)
    end

    for _, specID in ipairs(specIDs) do
        for _, powerType in ipairs(SPEC_RESOURCES_CONFIG[specID] or {}) do
            AddUniqueResource(result, seen, powerType)
        end
    end

    return result
end

local function GetResourceApplicableSpecIDs(powerType)
    local classID, specIDs = GetPlayerClassAndSpecsConfig()
    if not classID or powerType == nil or powerType == RESOURCE_HEALTH then
        return {}
    end

    local applicable = {}
    for _, specID in ipairs(specIDs) do
        local belongs
        if classID == DRUID_CLASS_ID then
            if powerType == 8 then
                belongs = specID == DRUID_BALANCE_SPEC_ID
            else
                belongs = ResourceListContains(CLASS_RESOURCES_CONFIG[DRUID_CLASS_ID], powerType)
            end
        elseif SPEC_RESOURCES_CONFIG[specID] then
            belongs = ResourceListContains(SPEC_RESOURCES_CONFIG[specID], powerType)
        else
            belongs = ResourceListContains(CLASS_RESOURCES_CONFIG[classID], powerType)
        end
        if belongs then
            applicable[#applicable + 1] = specID
        end
    end
    return applicable
end

local function IsResourceEditable(powerType, settings)
    settings = settings or CooldownCompanion:GetResourceBarSettings()
    if powerType == nil or powerType == RESOURCE_HEALTH then
        return false
    end
    if not (type(settings) == "table" and settings.enabled == true) then
        return false
    end
    return #GetResourceApplicableSpecIDs(powerType) > 0
end

local function GetDefaultResourceSettingsSpecID(powerType, preferredSpecID)
    local applicable = GetResourceApplicableSpecIDs(powerType)
    if #applicable == 0 then
        return nil
    end

    if preferredSpecID then
        for _, specID in ipairs(applicable) do
            if specID == preferredSpecID then
                return specID
            end
        end
    end
    local currentSpecID = GetCurrentConfigSpecID()
    for _, specID in ipairs(applicable) do
        if specID == currentSpecID then
            return specID
        end
    end
    return applicable[1]
end

------------------------------------------------------------------------
-- Spec override helpers
------------------------------------------------------------------------

-- Returns specOverrides[specID] table, auto-vivifying intermediate tables when
-- create is true. Returns nil if any level is missing and create is false.
local function GetSpecOverrideTable(settings, powerType, specID, create)
    if not specID then return nil end
    if not settings.resources then
        if create then settings.resources = {} else return nil end
    end
    if not settings.resources[powerType] then
        if create then settings.resources[powerType] = {} else return nil end
    end
    local resource = settings.resources[powerType]
    if not resource.specOverrides then
        if create then resource.specOverrides = {} else return nil end
    end
    if not resource.specOverrides[specID] then
        if create then resource.specOverrides[specID] = {} else return nil end
    end
    return resource.specOverrides[specID]
end

-- Resolves a per-spec override key with a caller-supplied default.
-- Uses the shared resolver: specOverrides[specID][key] -> resource[key] -> default.
local function ReadSpecOverrideKey(settings, powerType, specID, key, default)
    local resource = settings.resources and settings.resources[powerType]
    if not resource then return default end
    local resolved = ResolveSpecOverrideKey(resource, specID, key)
    if resolved ~= nil then return resolved end
    return default
end

-- Writes a key into specOverrides[specID]. Passing value=nil clears the key and
-- prunes empty tables to keep SavedVariables clean.
local function WriteSpecOverrideKey(settings, powerType, specID, key, value)
    if not specID then
        geterrorhandler()("WriteSpecOverrideKey: nil specID for key " .. tostring(key))
        return
    end
    if value == nil then
        local specTable = GetSpecOverrideTable(settings, powerType, specID, false)
        if specTable then
            specTable[key] = nil
            if not next(specTable) then
                local resource = settings.resources and settings.resources[powerType]
                if resource and resource.specOverrides then
                    resource.specOverrides[specID] = nil
                    if not next(resource.specOverrides) then
                        resource.specOverrides = nil
                    end
                end
            end
        end
    else
        local specTable = GetSpecOverrideTable(settings, powerType, specID, true)
        specTable[key] = value
    end
end

-- Resources reuse the ordinary field-control contract. Only this adapter
-- knows the nested spec store; preview rollback never writes effective values.
function ST._ResourceSpecFields(container, settings, powerType, specID)
    local context = ST._GetSettingsWidgetContext(container)
    assert(context and context.kind == "resources" and context.settings == settings, "Missing resource edit context")
    local resources = rawget(settings, "resources")
    local resource = resources and rawget(resources, powerType)
    local function IsCurrent()
        return context:IsCurrent() and rawget(settings, "resources") == resources
            and (not resources or rawget(resources, powerType) == resource)
    end
    local fields = setmetatable({}, {
        __index = function(_, key)
            local spec = GetSpecOverrideTable(settings, powerType, specID, false)
            if spec and spec[key] ~= nil then return spec[key] end
            if resource then return resource[key] end
        end,
        __newindex = function(_, key, value)
            if not IsCurrent() then return end
            WriteSpecOverrideKey(settings, powerType, specID, key, value)
            resources = rawget(settings, "resources")
            resource = resources and rawget(resources, powerType)
        end,
    })
    getmetatable(fields)._settingsPreviewTarget = {
        isCurrent = IsCurrent,
        capture = function(keys)
            local oldResources, oldResource = resources, resource
            local specs = resource and rawget(resource, "specOverrides")
            local spec = specs and rawget(specs, specID)
            local restoreRoot = ST._CaptureRawSettingsFields(settings, { "resources" })
            local restoreResource = ST._CaptureRawSettingsFields(resources, { powerType })
            local restoreSpecs = ST._CaptureRawSettingsFields(resource, { "specOverrides" })
            local restoreSpec = ST._CaptureRawSettingsFields(specs, { specID })
            local restoreFields = ST._CaptureRawSettingsFields(spec, keys)
            return function()
                restoreFields()
                restoreSpec()
                restoreSpecs()
                restoreResource()
                restoreRoot()
                resources, resource = oldResources, oldResource
            end
        end,
    }
    return fields
end

function ST._MakeResourceEditRefresh(container)
    local context = ST._GetSettingsWidgetContext(container)
    assert(context and context.kind == "resources", "Missing resource edit context")
    local target = ST._CaptureConfigEditTarget(context.panelId, context)
    return function(operation, effect)
        return ST._CompleteConfigEdit(target, operation or "style", effect)
    end
end

------------------------------------------------------------------------
-- More query functions
------------------------------------------------------------------------

local function GetPlayerSpecOptionsConfig()
    local specList = {}
    local specOrder = {}
    local specInfoByID = {}

    for i = 1, (GetNumSpecializations() or 0) do
        local specID, name, _, icon = C_SpecializationInfo.GetSpecializationInfo(i)
        if specID and name then
            specList[specID] = name
            specOrder[#specOrder + 1] = specID
            specInfoByID[specID] = {
                specID = specID,
                name = name,
                icon = icon,
                order = i,
            }
        end
    end

    return specList, specOrder, specInfoByID
end

local function ResolveAuraColorSpellIDFromText(text)
    if not text then return nil, false end
    local cleaned = text:gsub("^%s+", ""):gsub("%s+$", "")
    if cleaned == "" then
        return nil, true
    end

    local numeric = tonumber(cleaned)
    if numeric and numeric > 0 then
        return numeric, false
    end

    local entry = ResolveAuraBarAutocompleteEntry(cleaned)
    if entry then
        return entry.id, false
    end

    local spellInfo = C_Spell.GetSpellInfo(cleaned)
    if spellInfo and spellInfo.spellID then
        return spellInfo.spellID, false
    end

    if CooldownCompanion.FindTalentSpellByName then
        local spellID = CooldownCompanion:FindTalentSpellByName(cleaned)
        if spellID then
            return spellID, false
        end
    end

    return nil, false
end

-- Typed names must land the same ID an autocomplete pick would: the tracked
-- slice re-identifies CDM rows to the applied-aura spellID, while a plain
-- name lookup resolves to the castable spell (Rake -> 1822, never bleed
-- 155722). Numeric input is honored verbatim. Tracked-aura LIST fields
-- resolve through here; the plain-name resolver above is this function's
-- fallback for names the tracked slice does not hold.
local function ResolveTrackedAuraSpellIDFromText(text)
    if not text then return nil, false end
    local cleaned = text:gsub("^%s+", ""):gsub("%s+$", "")
    if cleaned == "" then
        return nil, true
    end

    local numeric = tonumber(cleaned)
    if numeric and numeric > 0 then
        return numeric, false
    end

    local lookup = cleaned:lower()
    for _, entry in ipairs(BuildTrackedAuraAutocompleteCache()) do
        if entry.nameLower == lookup then
            return tonumber(entry.id), false
        end
    end

    return ResolveAuraColorSpellIDFromText(cleaned)
end

-- Simple queries
------------------------------------------------------------------------

local function IsResourceBarVerticalConfig(settings, layout)
    if layout and layout.orientation ~= nil then
        return layout.orientation == "vertical"
    end
    return settings and settings.orientation == "vertical"
end

local function GetResourceGapFieldConfig(settings, layout)
    if IsResourceBarVerticalConfig(settings, layout) then
        return "verticalXOffset", "X Offset"
    end
    return "yOffset", "Y Offset"
end

------------------------------------------------------------------------
-- Mirror-first slider wiring (owner ruling 2026-08-02)
--
-- While a slider on a resources surface is DRAGGED, the candidate value is
-- exposed only for the workspace's pinned canvas render, then restored. The
-- saved value and live display update once, on release. The canvas paints with
-- the live bars' own painters (the Independent stack on the bars workspace,
-- the panel preview in the buttons view), so it is an honest stand-in for the
-- edit - and driving the live bars from every
-- OnValueChanged tick was what made these sliders feel heavy.
--
-- CDC-SliderRow's edit box deliberately fires BOTH OnValueChanged and
-- OnMouseUp on Enter (RowWidgets.lua), so a typed value repaints the canvas
-- and applies live in the same breath with no extra handling here.
--
-- Call sites supply two closures instead of onChange/onRelease:
--   opts.set(value)  exposes the candidate value (and carries whatever guard the
--                    row had - a locked border, a disabled resource)
--   opts.apply()     the row's own live-display chain, verbatim: whatever it
--                    used to run on every drag tick, now run once on release
-- Every other field is AddSliderRow's own contract.
------------------------------------------------------------------------

-- Late-bound on purpose: Config/ResourcesWideColumn.lua publishes this and
-- self-gates on view state (Resources workspace -> the pinned canvas, the
-- buttons view -> the unified preview's mirror), so this side neither knows
-- nor decides which surface is listening.
local function RefreshResourcesCanvas(mirrorReuse)
    if ST._RefreshResourcesLayoutPreview then
        ST._RefreshResourcesLayoutPreview(mirrorReuse)
    end
end

-- The drag tick asks for mirror reuse; nothing else does. A bar value cannot
-- change the icon panel the buttons view's mirror draws, so only the bars
-- need redrawing.
local function RefreshResourcesCanvasForDrag()
    RefreshResourcesCanvas(true)
end

local function AddMirrorFirstSliderRow(container, opts)
    local set = opts.set
    local apply = opts.apply
    local captureState = opts.captureState
    local restoreState = opts.restoreState
    local stateOwner = opts.stateOwner
    local stateKeys = opts.stateKeys
    opts.set = nil
    opts.apply = nil
    opts.captureState = nil
    opts.restoreState = nil
    opts.stateOwner = nil
    opts.stateKeys = nil

    opts.onChange = function(value)
        if captureState then
            local state = captureState()
            ST._RunSettingsPreview(function() set(value) end, RefreshResourcesCanvasForDrag,
                function() restoreState(state) end)
        else
            ST._WithSettingsPreview(stateOwner, stateKeys, function() set(value) end,
                RefreshResourcesCanvasForDrag)
        end
    end
    opts.onRelease = function(value)
        local target = stateOwner and ST._GetSettingsPreviewTarget(stateOwner)
        if target and not target.isCurrent() then return end
        set(value)
        apply()
    end
    return ST._AddSliderRow(container, opts)
end

------------------------------------------------------------------------
-- Independent Anchor Settings rows
------------------------------------------------------------------------
-- The rows the Independent Resources stack and the Independent Cast Bar
-- share: anchor frame and Pick, Unlock Placement, the two points, the width
-- and the screen offsets. Each page keeps its own section, collapse key and
-- width label.
--   opts.anchor      the saved independentAnchor table, or nil before it
--                    exists
--   opts.readAnchor  optional: what a missing anchor reads as
--   opts.ensureAnchor() creates the saved anchor and returns it; only an
--                    edit calls it (rule Q1)
--   opts.owner       carries independentAnchorLocked and independentWidth
--   opts.widthLabel, opts.widthValue
--   opts.finder      Settings Finder settings: frame, unlock, point,
--                    relativePoint, width, x, y
--   opts.apply()     re-applies the bar
local function BuildIndependentAnchorRows(container, opts)
    local owner, apply = opts.owner, opts.apply
    local finder = opts.finder or {}
    -- The rows edit through this view. Clearing a key on an anchor that does
    -- not exist yet changes nothing, so it creates nothing.
    local saved = opts.anchor
    local anchor = setmetatable({}, {
        __index = function(_, key)
            local source = saved or opts.readAnchor
            return source and source[key]
        end,
        __newindex = function(_, key, value)
            if not saved then
                if value == nil then return end
                saved = opts.ensureAnchor()
            end
            saved[key] = value
        end,
    })

    -- A frame name needs the whole 140px control column to stay readable, so
    -- Pick does not share it: the editbox row takes a grid of its own and Pick
    -- sits at the head of that grid's right column, immediately across the
    -- 16px gutter.
    local targetLeft, targetRight = ST._BeginRowGrid(container)
    ST._BuildIndependentAnchorTargetRow(targetLeft, anchor, apply, {
        pickContainer = targetRight,
        setting = finder.frame,
    })

    -- LEFT column: how the bar is placed - the drag toggle and the two points
    -- that have to be read together (mine, then the target's). RIGHT column:
    -- its size and the offset applied on top of those points.
    local left, right = ST._BeginRowGrid(container)
    ST._AddCheckboxRow(left, {
        label = "Unlock Placement",
        setting = finder.unlock,
        value = not owner.independentAnchorLocked,
        onChange = function(val)
            owner.independentAnchorLocked = not val
            apply()
            if not val then
                CooldownCompanion:CheckArrangeModeAutoExit()
            end
        end,
    })
    ST._AddAnchorDropdown(left, anchor, "point", "CENTER", apply, "Anchor Point", { setting = finder.point })
    ST._AddAnchorDropdown(left, anchor, "relativePoint", "CENTER", apply, "Relative Point", { setting = finder.relativePoint })

    -- The canvas sizes the bar from this value while it drags.
    AddMirrorFirstSliderRow(right, {
        label = opts.widthLabel,
        setting = finder.width,
        min = 20, max = 600, step = 0.1,
        value = opts.widthValue,
        set = function(val) owner.independentWidth = val end,
        apply = apply,
        stateOwner = owner,
        stateKeys = "independentWidth",
    })

    -- The offsets place the bar on SCREEN, which the canvas does not draw.
    -- Store during the drag and move the live bar once on release.
    ST._AddSliderRow(right, {
        label = "X Offset",
        setting = finder.x,
        min = -2000, max = 2000, step = 0.1,
        value = anchor.x or 0,
        onRelease = function(val)
            anchor.x = val
            apply()
        end,
    })
    ST._AddSliderRow(right, {
        label = "Y Offset",
        setting = finder.y,
        min = -2000, max = 2000, step = 0.1,
        value = anchor.y or 0,
        onRelease = function(val)
            anchor.y = val
            apply()
        end,
    })
end
ST._BuildIndependentAnchorRows = BuildIndependentAnchorRows

local function OpenResourceBarConflictChooser(force)
    local classKey = CooldownCompanion._unifiedPanelConversionError
        and CooldownCompanion:GetNextResourceBarConflictClassKey()
        or CooldownCompanion:GetCurrentResourceBarClassKey()
    local showChooser = ST._ShowResourceBarConflictChooser
    if showChooser then
        return showChooser(classKey, { force = force })
    end
    CooldownCompanion:Print("Resource Bar conflict chooser is unavailable.")
    return false
end

local function BuildResourceBarConflictGate(container, editSurface, autoOpen)
    local classKey = CooldownCompanion._unifiedPanelConversionError
        and CooldownCompanion:GetNextResourceBarConflictClassKey()
        or CooldownCompanion:GetCurrentResourceBarClassKey()
    local conflict = CooldownCompanion:GetResourceBarConflict(classKey)
    if not conflict then
        return false
    end

    local label = AceGUI:Create("Label")
    ST._ConfigureWrappedHelperLabel(label)
    label:SetText("Resource Bars for " .. tostring(classKey) .. " have multiple legacy setups. Choose one setup before editing " .. (editSurface or "Resource Bars") .. ".")
    label:SetFullWidth(true)
    container:AddChild(label)

    local resolveBtn = AceGUI:Create("Button")
    resolveBtn:SetText("Resolve Resource Bars")
    resolveBtn:SetFullWidth(true)
    resolveBtn:SetCallback("OnClick", function()
        OpenResourceBarConflictChooser(true)
    end)
    container:AddChild(resolveBtn)
    CS.resourceBarConflictResolveButton = resolveBtn

    if autoOpen and not (CS.resourceBarConflictChooserDismissed and CS.resourceBarConflictChooserDismissed[classKey]) then
        local function openIfStillPending()
            if CooldownCompanion:GetResourceBarConflict(classKey) then
                OpenResourceBarConflictChooser(false)
            end
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, openIfStillPending)
        else
            openIfStillPending()
        end
    end

    return true
end

------------------------------------------------------------------------
-- Export via ST._RBP
------------------------------------------------------------------------

ST._RBP = {
    collapsedSections = resourceBarCollapsedSections,
    GetConfigActiveResources = GetConfigActiveResources,
    GetConfigEditableResources = GetConfigEditableResources,
    GetResourceApplicableSpecIDs = GetResourceApplicableSpecIDs,
    IsResourceEditable = IsResourceEditable,
    GetDefaultResourceSettingsSpecID = GetDefaultResourceSettingsSpecID,
    GetCurrentConfigSpecID = GetCurrentConfigSpecID,
    ReadSpecOverrideKey = ReadSpecOverrideKey,
    WriteSpecOverrideKey = WriteSpecOverrideKey,
    GetPlayerSpecOptionsConfig = GetPlayerSpecOptionsConfig,
    ResolveAuraColorSpellIDFromText = ResolveAuraColorSpellIDFromText,
    ResolveTrackedAuraSpellIDFromText = ResolveTrackedAuraSpellIDFromText,
    ResolveAuraBarAutocompleteEntry = ResolveAuraBarAutocompleteEntry,
    BuildAuraBarAutocompleteCache = BuildAuraBarAutocompleteCache,
    BuildTrackedAuraAutocompleteCache = BuildTrackedAuraAutocompleteCache,
    IsResourceBarVerticalConfig = IsResourceBarVerticalConfig,
    GetResourceGapFieldConfig = GetResourceGapFieldConfig,
    BuildResourceBarConflictGate = BuildResourceBarConflictGate,
}

-- Top-level rather than inside ST._RBP: CastBarPanels.lua loads BEFORE this
-- file (TOC), so it reads these at call time and never aliases _RBP at all.
ST._RefreshResourcesCanvas = RefreshResourcesCanvas
ST._RefreshResourcesCanvasForDrag = RefreshResourcesCanvasForDrag
ST._AddMirrorFirstSliderRow = AddMirrorFirstSliderRow

-- Adapt the existing per-slot order/editor contract without changing saved
-- above/below values. Vertical and independent slots do not use this adapter.
function ST._ConfigureAttachedBarPreviewSlot(slot, ensureLayout)
    local getSide, setSide = slot.getPos, slot.setPos
    slot.getPos = function()
        local saved = ensureLayout()
        return RB.ResolveBarLane(slot.anchorGroup or RB.GetBarAnchorGroup(),
            getSide(), saved.anchorRegion)
    end
    slot.getRegionRank = function()
        local saved = ensureLayout()
        return RB.GetBarRegionRank(slot.getPos(), saved.anchorRegion,
            slot.anchorGroup or RB.GetBarAnchorGroup())
    end
    slot.setPos = function(lane)
        local saved = ensureLayout()
        local oldRegion, oldSide = saved.anchorRegion, saved.position
        setSide(RB.GetBarLaneSide(lane))
        RB.SetBarLane(saved, lane)
        return oldRegion ~= saved.anchorRegion or oldSide ~= saved.position
    end
end

