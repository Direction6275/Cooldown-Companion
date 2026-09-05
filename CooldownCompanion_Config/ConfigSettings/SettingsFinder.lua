--[[
    CooldownCompanion - ConfigSettings/SettingsFinder.lua

    Static settings catalog, matching, and navigation for the Editing action
    row's Settings Finder. Settings modules register lightweight descriptors
    while they load; searching never constructs an inactive settings page.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local DEFAULT_RESULT_LIMIT = 8
local MAX_RESULT_LIMIT = 8

local registry = {}
local descriptorsById = {}
local contextPreparers = {}

local TAB_LABELS = {
    general = "General",
    settings = "Settings",
    format = "Format",
    appearance = "Appearance",
    layout = "Layout",
    effects = "Indicators",
    loadconditions = "Visibility",
    health = "Health",
}

local VALID_SCOPES = {
    group = true,
    panel = true,
    entry = true,
    resources = true,
    resource = true,
    customBar = true,
    castBar = true,
    playerFrame = true,
    targetFrame = true,
}

local VALID_ROW_SCOPES = {
    primary = true,
    detail = true,
}

local ROUTE_FIELDS = {
    "scope", "tab", "tabLabel", "section", "sectionId", "sectionLabel",
    "collapseKeys", "collapseStore", "rowScope", "tabStateKey",
    "advancedKey", "navigate",
}

local function Trim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function NormalizeSearchText(value)
    if type(value) ~= "string" then
        return ""
    end
    -- Labels occasionally contain WoW color markup. It is presentation,
    -- never a search term.
    value = value:gsub("|c%x%x%x%x%x%x%x%x", " "):gsub("|r", " ")
    value = value:lower():gsub("[^%w]+", " ")
    return Trim(value:gsub("%s+", " "))
end

local function CopyTable(values)
    if type(values) ~= "table" then
        return values
    end
    local copy = {}
    for key, value in pairs(values) do
        copy[key] = value
    end
    return copy
end

local function AppendAlias(target, alias)
    local normalized = NormalizeSearchText(alias)
    if normalized ~= "" then
        target[#target + 1] = normalized
    end
end

local function NormalizeAliases(aliases)
    local normalized = {}
    if type(aliases) == "string" then
        AppendAlias(normalized, aliases)
    elseif type(aliases) == "table" then
        for _, alias in ipairs(aliases) do
            AppendAlias(normalized, alias)
        end
    end
    return normalized
end

local function BuildBreadcrumb(descriptor)
    local tabLabel = descriptor.tabLabel or TAB_LABELS[descriptor.tab] or descriptor.tab
    local sectionLabel = descriptor.sectionLabel or descriptor.section
    if tabLabel and sectionLabel and sectionLabel ~= tabLabel then
        return tabLabel .. " \226\128\186 " .. sectionLabel
    end
    return tabLabel or sectionLabel or "Settings"
end

local function ScopeDefinitionIsValid(scope)
    if type(scope) == "string" then
        return VALID_SCOPES[scope] == true
    end
    if type(scope) == "function" then
        return true
    end
    if type(scope) ~= "table" then
        return false
    end

    local found = false
    for key, value in pairs(scope) do
        if type(key) == "number" then
            if type(value) ~= "string" or not VALID_SCOPES[value] then
                return false
            end
        else
            if not VALID_SCOPES[key] or type(value) ~= "boolean" then
                return false
            end
        end
        found = true
    end
    return found
end

local function CopyRouteField(descriptor, routeDefaults, settingOptions, field)
    local value = settingOptions[field]
    if value == nil then
        value = routeDefaults[field]
    end
    descriptor[field] = CopyTable(value)
end

local function ValidateDescriptorShape(descriptor)
    if type(descriptor.id) ~= "string" or descriptor.id == "" then
        error("Cooldown Companion Settings Finder: setting descriptor requires a stable id")
    end
    if type(descriptor.label) ~= "string" or Trim(descriptor.label) == "" then
        error("Cooldown Companion Settings Finder: " .. descriptor.id .. " requires a label")
    end
    if not ScopeDefinitionIsValid(descriptor.scope) then
        error("Cooldown Companion Settings Finder: " .. descriptor.id .. " has an invalid scope")
    end
    if descriptor.tab == nil and type(descriptor.navigate) ~= "function" then
        error("Cooldown Companion Settings Finder: " .. descriptor.id .. " requires a tab or navigate callback")
    end
    if descriptor.tab ~= nil and not TAB_LABELS[descriptor.tab] then
        error("Cooldown Companion Settings Finder: " .. descriptor.id .. " has an invalid tab")
    end
    if descriptor.rowScope ~= nil and not VALID_ROW_SCOPES[descriptor.rowScope] then
        error("Cooldown Companion Settings Finder: " .. descriptor.id .. " has an invalid row scope")
    end
    local sectionIdentity = descriptor.sectionId or descriptor.section
    if type(sectionIdentity) ~= "string" or Trim(sectionIdentity) == "" then
        error("Cooldown Companion Settings Finder: " .. descriptor.id .. " requires a section identity")
    end
    if type(descriptor.sectionLabel) ~= "string" or Trim(descriptor.sectionLabel) == "" then
        error("Cooldown Companion Settings Finder: " .. descriptor.id .. " requires a section label")
    end
    if descriptor.tabStateKey ~= nil and type(descriptor.tabStateKey) ~= "string" then
        error("Cooldown Companion Settings Finder: " .. descriptor.id .. " has an invalid tab state key")
    end
    if descriptor.collapseKeys ~= nil
        and type(descriptor.collapseKeys) ~= "string"
        and type(descriptor.collapseKeys) ~= "table"
        and type(descriptor.collapseKeys) ~= "function"
    then
        error("Cooldown Companion Settings Finder: " .. descriptor.id .. " has invalid collapse keys")
    end
    if descriptor.collapseStore ~= nil
        and descriptor.collapseStore ~= "resource"
        and type(descriptor.collapseStore) ~= "table"
        and type(descriptor.collapseStore) ~= "function"
    then
        error("Cooldown Companion Settings Finder: " .. descriptor.id .. " has an invalid collapse store")
    end
    if descriptor.advancedKey ~= nil
        and type(descriptor.advancedKey) ~= "string"
        and type(descriptor.advancedKey) ~= "function"
    then
        error("Cooldown Companion Settings Finder: " .. descriptor.id .. " has an invalid advanced destination")
    end
    if descriptor.navigate ~= nil and type(descriptor.navigate) ~= "function" then
        error("Cooldown Companion Settings Finder: " .. descriptor.id .. " has an invalid navigator")
    end
    if descriptor._routeApplies ~= nil and type(descriptor._routeApplies) ~= "function" then
        error("Cooldown Companion Settings Finder: " .. descriptor.id .. " has an invalid route predicate")
    end
    if descriptor._settingApplies ~= nil and type(descriptor._settingApplies) ~= "function" then
        error("Cooldown Companion Settings Finder: " .. descriptor.id .. " has an invalid setting predicate")
    end
end

local function RegisterDescriptor(routeDefaults, settingOptions)
    settingOptions = settingOptions or {}
    local key = settingOptions.key
    if type(key) ~= "string" or key == "" then
        error("Cooldown Companion Settings Finder: route setting requires a stable key")
    end

    local prefix = routeDefaults.idPrefix
    if type(prefix) ~= "string" or prefix == "" then
        error("Cooldown Companion Settings Finder: route requires idPrefix")
    end

    local descriptor = {
        id = prefix .. "." .. key,
        key = key,
        label = settingOptions.label,
        aliases = CopyTable(settingOptions.aliases),
        _routeApplies = routeDefaults.applies,
        _settingApplies = settingOptions.applies,
    }
    for _, field in ipairs(ROUTE_FIELDS) do
        CopyRouteField(descriptor, routeDefaults, settingOptions, field)
    end

    if descriptorsById[descriptor.id] then
        error("Cooldown Companion Settings Finder: duplicate descriptor id " .. descriptor.id)
    end
    ValidateDescriptorShape(descriptor)

    descriptor.tabLabel = descriptor.tabLabel or TAB_LABELS[descriptor.tab] or descriptor.tab
    descriptor.breadcrumb = BuildBreadcrumb(descriptor)
    descriptor._normalizedLabel = NormalizeSearchText(descriptor.label)
    descriptor._normalizedAliases = NormalizeAliases(descriptor.aliases)
    descriptor._normalizedBreadcrumb = NormalizeSearchText(descriptor.breadcrumb)

    descriptorsById[descriptor.id] = descriptor
    registry[#registry + 1] = descriptor

    return descriptor
end

local function DefineSettingRoute(defaults)
    defaults = defaults or {}
    if type(defaults.idPrefix) ~= "string" or defaults.idPrefix == "" then
        error("Cooldown Companion Settings Finder: DefineSettingRoute requires idPrefix")
    end

    local route = { defaults = defaults }

    function route:Setting(options)
        return RegisterDescriptor(self.defaults, options)
    end

    -- Compact catalog shorthand. A keyed map returns the same keyed shape;
    -- an array returns an array. Map keys become stable setting keys unless
    -- an entry deliberately supplies its own.
    function route:Settings(specs)
        local result = {}
        if type(specs) ~= "table" then
            return result
        end
        if #specs > 0 then
            for index, options in ipairs(specs) do
                result[index] = self:Setting(options)
            end
        else
            for key, options in pairs(specs) do
                options = CopyTable(options or {})
                options.key = options.key or key
                result[key] = self:Setting(options)
            end
        end
        return result
    end

    return route
end

local function GetSelectedCustomBar(settings)
    if settings and ST._RB and ST._RB.FindCustomBarById then
        return ST._RB.FindCustomBarById(settings, CS.selectedCustomBarId)
    end
    if ST._FindSelectedConfigCustomBar then
        return ST._FindSelectedConfigCustomBar()
    end
    return nil
end

-- Captured once when the editing action row is rebuilt. Typing compares this
-- lightweight state instead of reconstructing a full context (which can
-- resolve class-scoped Resources settings).
local CONTEXT_STATE_FIELDS = {
    "selectedContainer", "selectedGroup", "selectedButton",
    "selectedRotationAssistantEntry", "selectedResourcePowerType",
    "resourceSettingsSpecID", "selectedCustomBarId", "castFramesSelectedItem",
    "barsEntrySelected", "barWorkspaceKind", "unifiedBarKind",
}

local function CaptureContextState()
    local state = {}
    for _, field in ipairs(CONTEXT_STATE_FIELDS) do
        state[field] = CS[field]
    end
    return state
end

local function BuildContextIdentity(context)
    if not context then
        return nil
    end
    local parts = {
        context.scope or "",
        tostring(context.containerId or ""),
        tostring(context.container or ""),
        tostring(context.groupId or ""),
        tostring(context.group or ""),
        tostring(context.displayMode or ""),
        tostring(context.buttonIndex or ""),
        tostring(context.buttonData or ""),
        tostring(context.rotationAssistant == true),
        tostring(context.resourcePowerType or ""),
        tostring(context.resourceSpecID or ""),
        tostring(context.customBarId or ""),
        tostring(context.customBar or ""),
        tostring(context.castFramesItem or ""),
    }
    return table.concat(parts, "|")
end

local function GetSettingsFinderContext()
    local db = CooldownCompanion.db and CooldownCompanion.db.profile
    if not db then
        return nil
    end

    local context = {
        containerId = CS.selectedContainer,
        groupId = CS.selectedGroup,
        buttonIndex = CS.selectedButton,
        resourcePowerType = CS.selectedResourcePowerType,
        resourceSpecID = CS.resourceSettingsSpecID,
        customBarId = CS.selectedCustomBarId,
        castFramesItem = CS.castFramesSelectedItem,
        rowScope = CS.unifiedRowScope,
    }
    context.container = context.containerId and db.groupContainers
        and db.groupContainers[context.containerId] or nil
    context.group = context.groupId and db.groups and db.groups[context.groupId] or nil
    context.displayMode = context.group and (context.group.displayMode or "icons") or nil
    context.buttonData = context.group and context.buttonIndex and context.group.buttons
        and context.group.buttons[context.buttonIndex] or nil
    context.button = context.buttonData
    if CS.barsEntrySelected then
        -- The selected detail object remains the Finder scope while Primary
        -- and Detail merely choose which row of tabs is visible. A result is
        -- therefore free to navigate between both rows for that same object.
        if context.castFramesItem == "castbar" then
            context.scope = "castBar"
        elseif context.castFramesItem == "player" then
            context.scope = "playerFrame"
        elseif context.castFramesItem == "target" then
            context.scope = "targetFrame"
        elseif context.customBarId then
            context.scope = "customBar"
        elseif context.resourcePowerType ~= nil then
            context.scope = "resource"
        else
            context.scope = "resources"
        end
    elseif context.group then
        -- An entry or attached bar remains the edited object while either
        -- unified tab row owns the surface. rowScope is a navigation target,
        -- not part of the object's searchable identity.
        if CS.unifiedBarKind == "stack" then
            context.scope = "resources"
        elseif CS.unifiedBarKind == "player" then
            context.scope = "playerFrame"
        elseif CS.unifiedBarKind == "target" then
            context.scope = "targetFrame"
        elseif CS.unifiedBarKind == "resource" and context.resourcePowerType ~= nil then
            context.scope = "resource"
        elseif CS.unifiedBarKind == "custom" and context.customBarId then
            context.scope = "customBar"
        elseif CS.unifiedBarKind == "cast" then
            context.scope = "castBar"
        elseif context.buttonData then
            -- Finder scope follows the object being edited, not the style
            -- lens that owns its visual overrides. Texture panels keep their
            -- style panel-owned, but their selected spell still renders
            -- entry-specific Settings and Visibility rows.
            context.scope = "entry"
        elseif CS.selectedRotationAssistantEntry == true then
            context.scope = "entry"
            context.rotationAssistant = true
        else
            context.scope = "panel"
            context.rowScope = "primary"
        end
    elseif context.container then
        context.scope = "group"
        context.rowScope = "primary"
    else
        return nil
    end

    -- Resource settings are class-scoped and their accessor may normalize or
    -- initialize a bucket. Ordinary Group/Panel/Entry Finder contexts have no
    -- reason to touch them. Bar and frame surfaces already own that settings
    -- domain, so resolve it exactly once after their scope is known.
    if context.scope == "resources" or context.scope == "resource"
        or context.scope == "customBar" or context.scope == "castBar"
        or context.scope == "playerFrame" or context.scope == "targetFrame"
    then
        context.resourceSettings = CooldownCompanion.GetResourceBarSettings
            and CooldownCompanion:GetResourceBarSettings() or nil
    end
    if context.scope == "customBar" then
        context.customBar = GetSelectedCustomBar(context.resourceSettings)
        if not context.customBar then
            return nil
        end
    end

    context._selectionState = CaptureContextState()
    context.identity = BuildContextIdentity(context)
    return context
end

local function GetSettingsFinderContextIdentity(context)
    return context and (context.identity or BuildContextIdentity(context)) or nil
end

local function SettingsFinderContextIsCurrent(context)
    local state = context and context._selectionState
    local db = CooldownCompanion.db and CooldownCompanion.db.profile
    if not (state and db) then
        return false
    end
    for _, field in ipairs(CONTEXT_STATE_FIELDS) do
        if state[field] ~= CS[field] then
            return false
        end
    end

    local container = context.containerId and db.groupContainers
        and db.groupContainers[context.containerId] or nil
    local group = context.groupId and db.groups and db.groups[context.groupId] or nil
    local buttonData = group and context.buttonIndex and group.buttons
        and group.buttons[context.buttonIndex] or nil
    return container == context.container
        and group == context.group
        and buttonData == context.buttonData
        and (group and (group.displayMode or "icons") or nil) == context.displayMode
end

local function ScopeMatches(scope, contextScope)
    if type(scope) == "string" then
        return scope == contextScope
    end
    if type(scope) == "function" then
        return scope(contextScope) and true or false
    end
    if type(scope) ~= "table" then
        return false
    end
    if scope[contextScope] ~= nil then
        return scope[contextScope] == true
    end
    for _, value in ipairs(scope) do
        if value == contextScope then
            return true
        end
    end
    return false
end

local function RegisterSettingsFinderContextPreparer(scope, prepare)
    if not ScopeDefinitionIsValid(scope) then
        error("Cooldown Companion Settings Finder: context preparer has an invalid scope")
    end
    if type(prepare) ~= "function" then
        error("Cooldown Companion Settings Finder: context preparer requires a function")
    end
    contextPreparers[#contextPreparers + 1] = { scope = scope, prepare = prepare }
end

local function IsDescriptorApplicable(descriptor, context)
    if type(descriptor) == "string" then
        descriptor = descriptorsById[descriptor]
    end
    if not (descriptor and context and ScopeMatches(descriptor.scope, context.scope)) then
        return false
    end
    if descriptor._routeApplies and not descriptor._routeApplies(context, descriptor) then
        return false
    end
    if descriptor._settingApplies and not descriptor._settingApplies(context, descriptor) then
        return false
    end
    return true
end

local function FindIndistinguishableResult(applicableDescriptors)
    local displaySignatures = {}
    for _, descriptor in ipairs(applicableDescriptors or {}) do
        local signature = descriptor._normalizedLabel .. "\0"
            .. descriptor._normalizedBreadcrumb
        local prior = displaySignatures[signature]
        if prior then
            return "indistinguishable result: " .. prior.id .. " and "
                .. descriptor.id .. " (" .. descriptor.label .. " / "
                .. descriptor.breadcrumb .. ")"
        end
        displaySignatures[signature] = descriptor
    end
    return nil
end

local function PrepareSettingsFinderContext(context, validationErrors)
    if not context then
        return nil
    end
    local cached = context._settingsFinderApplicability
    if cached and context._settingsFinderRegistrySize == #registry
        and context._settingsFinderPreparerCount == #contextPreparers
    then
        return context
    end

    -- Some structurally relevant facts (for example an inactive Cast Bar
    -- tab's border mode) used to be published only by the visible page
    -- builder. Resolve those facts once for this edited object before taking
    -- the applicability snapshot. Search keystrokes never run preparers or
    -- predicates; they read the snapshot below.
    for _, entry in ipairs(contextPreparers) do
        if ScopeMatches(entry.scope, context.scope) then
            entry.prepare(context)
        end
    end

    cached = {}
    local applicableDescriptors = {}
    -- Applicability may consult spell-derived facts. Resolve every descriptor
    -- once while the settings surface is rebuilt, then keep the keystroke path
    -- to table reads and normalized string matching only.
    for _, descriptor in ipairs(registry) do
        local applies = IsDescriptorApplicable(descriptor, context) == true
        cached[descriptor.id] = applies
        if applies then
            applicableDescriptors[#applicableDescriptors + 1] = descriptor
        end
    end
    local displayError = FindIndistinguishableResult(applicableDescriptors)
    if displayError then
        if validationErrors then
            validationErrors[#validationErrors + 1] = displayError
            return context
        end
        error("Cooldown Companion Settings Finder: " .. displayError)
    end
    context._settingsFinderApplicability = cached
    context._settingsFinderApplicableDescriptors = applicableDescriptors
    context._settingsFinderRegistrySize = #registry
    context._settingsFinderPreparerCount = #contextPreparers
    return context
end

local function RevalidateSettingsFinderDescriptor(descriptor, context)
    if type(descriptor) == "string" then
        descriptor = descriptorsById[descriptor]
    end
    if not (descriptor and context) then
        return false
    end
    PrepareSettingsFinderContext(context)
    return context._settingsFinderApplicability[descriptor.id] == true
end

local function HasSettingsFinderEntries(context)
    context = context or GetSettingsFinderContext()
    if not context then
        return false
    end
    PrepareSettingsFinderContext(context)
    return #context._settingsFinderApplicableDescriptors > 0
end

local function SplitTokens(normalized)
    local tokens = {}
    for token in normalized:gmatch("%S+") do
        tokens[#tokens + 1] = token
    end
    return tokens
end

local function StartsAtWord(text, token)
    return text:find(token, 1, true) == 1
        or text:find(" " .. token, 1, true) ~= nil
end

local function ScoreToken(descriptor, token)
    local label = descriptor._normalizedLabel
    if label == token then return 0 end
    if label:find(token, 1, true) == 1 then return 10 end
    if StartsAtWord(label, token) then return 20 end
    if label:find(token, 1, true) then return 30 end

    for _, alias in ipairs(descriptor._normalizedAliases) do
        if alias == token then return 40 end
        if alias:find(token, 1, true) == 1 then return 50 end
        if StartsAtWord(alias, token) then return 60 end
        if alias:find(token, 1, true) then return 70 end
    end

    local breadcrumb = descriptor._normalizedBreadcrumb
    if StartsAtWord(breadcrumb, token) then return 80 end
    if breadcrumb:find(token, 1, true) then return 90 end
    return nil
end

local function ScoreDescriptor(descriptor, normalizedQuery, tokens)
    local score = 0
    for _, token in ipairs(tokens) do
        local tokenScore = ScoreToken(descriptor, token)
        if tokenScore == nil then
            return nil
        end
        score = score + tokenScore
    end
    if descriptor._normalizedLabel == normalizedQuery then
        score = score - 1000
    elseif descriptor._normalizedLabel:find(normalizedQuery, 1, true) == 1 then
        score = score - 500
    end
    return score
end

local function SearchSettingsFinder(query, context, requestedLimit)
    local normalized = NormalizeSearchText(query)
    if #normalized < 2 then
        return {}, false
    end
    context = context or GetSettingsFinderContext()
    local applicableDescriptors = context and context._settingsFinderApplicableDescriptors
    if not applicableDescriptors or context._settingsFinderRegistrySize ~= #registry then
        return {}, false
    end

    local tokens = SplitTokens(normalized)
    local matches = {}
    for _, descriptor in ipairs(applicableDescriptors) do
        local score = ScoreDescriptor(descriptor, normalized, tokens)
        if score ~= nil then
            matches[#matches + 1] = { descriptor = descriptor, score = score }
        end
    end
    table.sort(matches, function(left, right)
        if left.score ~= right.score then
            return left.score < right.score
        end
        if left.descriptor._normalizedLabel ~= right.descriptor._normalizedLabel then
            return left.descriptor._normalizedLabel < right.descriptor._normalizedLabel
        end
        return left.descriptor.id < right.descriptor.id
    end)

    local limit = tonumber(requestedLimit) or DEFAULT_RESULT_LIMIT
    limit = math.max(1, math.min(MAX_RESULT_LIMIT, math.floor(limit)))
    local truncated = #matches > limit
    local results = {}
    for index = 1, math.min(limit, #matches) do
        results[index] = matches[index].descriptor
    end
    return results, truncated
end

local function BindSettingWidget(widget, descriptor, renderedLabel)
    if type(descriptor) == "string" then
        descriptor = descriptorsById[descriptor]
    end
    if not (widget and descriptor) then
        return nil
    end
    if renderedLabel ~= nil and renderedLabel ~= descriptor.label then
        error("Cooldown Companion Settings Finder: widget label mismatch for "
            .. descriptor.id .. " (expected '" .. descriptor.label
            .. "', got '" .. tostring(renderedLabel) .. "')")
    end
    widget._cdcSettingDescriptor = descriptor
    if ST._RecordSettingHighlightWidget then
        ST._RecordSettingHighlightWidget(widget, descriptor.id)
    end
    return descriptor
end

local function ResolveCollapseKeys(descriptor, context)
    local keys = descriptor.collapseKeys
    if type(keys) == "function" then
        keys = keys(context, descriptor)
    end
    if type(keys) == "string" then
        return { keys }
    end
    if type(keys) ~= "table" then
        return {}
    end
    local result = {}
    if #keys > 0 then
        for _, key in ipairs(keys) do
            result[#result + 1] = key
        end
    else
        for key, enabled in pairs(keys) do
            if enabled then
                result[#result + 1] = key
            end
        end
        table.sort(result)
    end
    return result
end

local function ResolveCollapseStore(descriptor, context)
    local store = descriptor.collapseStore
    if type(store) == "function" then
        return store(context, descriptor)
    end
    if store == "resource" then
        return ST._RBP and ST._RBP.collapsedSections or nil
    end
    if type(store) == "table" then
        return store
    end
    return CS.collapsedSections
end

local function SetUnifiedRowScope(scope)
    if not scope then
        return
    end
    -- Always through the strip's own writer - no fallback copy of its
    -- normalization, so the two can never drift.
    ST._UnifiedRowSetScope(scope)
end

local function ApplyDefaultTabRoute(descriptor, context)
    local tab = descriptor.tab
    if descriptor.tabStateKey then
        CS[descriptor.tabStateKey] = tab
        return
    end
    if context.scope == "group" then
        CS.selectedContainerTab = tab
    elseif context.scope == "panel" then
        CS.selectedTab = tab
        CS.panelSettingsTab = tab
        CS.panelSettingsTabExplicit = true
    elseif context.scope == "entry" then
        if descriptor.rowScope == "detail" then
            CS.buttonSettingsTab = tab
        else
            CS.selectedTab = tab
            CS.panelSettingsTab = tab
            CS.panelSettingsTabExplicit = true
        end
    elseif context.scope == "resources" then
        CS.resourcesSettingsTab = tab
    elseif descriptor.rowScope == "primary" then
        CS.resourcesSettingsTab = tab
    end
end

local function OpenFinderCollapseTargets(descriptor, context, pending)
    local keys = ResolveCollapseKeys(descriptor, context)
    local store = ResolveCollapseStore(descriptor, context)
    local lens
    if context.group and ST._ResolveStyleLens then
        lens = ST._ResolveStyleLens(context.group)
    end
    for _, key in ipairs(keys) do
        if store then
            store[key] = nil
        end
        pending.collapseKeys[key] = true
        if context.group and store == CS.collapsedSections and ST._ResolveLensCollapseKey then
            local lensKey = ST._ResolveLensCollapseKey(lens, context.group, nil, key)
            if lensKey and lensKey ~= key then
                store[lensKey] = false
                pending.collapseKeys[lensKey] = true
            end
        end
    end
end

local function ResolveAdvancedKey(descriptor, context)
    if type(descriptor.advancedKey) == "function" then
        return descriptor.advancedKey(context, descriptor)
    end
    return descriptor.advancedKey
end

local function NavigateToFinderSetting(descriptor, expectedContext)
    if type(descriptor) == "string" then
        descriptor = descriptorsById[descriptor]
    end
    if not descriptor then
        return false
    end

    local context = GetSettingsFinderContext()
    if not context then
        return false
    end
    local expectedIdentity = type(expectedContext) == "string"
        and expectedContext or GetSettingsFinderContextIdentity(expectedContext)
    if expectedIdentity
        and expectedIdentity ~= GetSettingsFinderContextIdentity(context)
    then
        return false
    end
    if not RevalidateSettingsFinderDescriptor(descriptor, context) then
        return false
    end

    if CS.CancelPickAuraTexture then
        CS.CancelPickAuraTexture()
    end

    SetUnifiedRowScope(descriptor.rowScope)
    if descriptor.navigate then
        -- A custom navigator owns only destination-state writes. It must not
        -- refresh; the engine performs the one rebuild below.
        if descriptor.navigate(context, descriptor) == false then
            return false
        end
    else
        ApplyDefaultTabRoute(descriptor, context)
    end

    local advancedKey = ResolveAdvancedKey(descriptor, context)
    local pending = {
        source = "settingsFinder",
        settingKey = descriptor.id,
        rowKey = advancedKey,
        sectionId = descriptor.sectionId or descriptor.section,
        collapseKeys = {},
    }
    CS.pendingSettingHighlight = pending
    OpenFinderCollapseTargets(descriptor, context, pending)

    -- Queued last: the queue snapshots tab/scope context and consumes when
    -- the rebuilt matching gear provides its actual advanced-panel builder.
    if advancedKey
        and CS.QueueAdvancedSettingsPanelOpen
        and not (CS.IsAdvancedSettingsPanelOpen and CS.IsAdvancedSettingsPanelOpen(advancedKey))
    then
        CS.QueueAdvancedSettingsPanelOpen(advancedKey)
    end

    -- The wide-column refresh begins by tearing down the previous surface,
    -- which normally clears stale finder state. Keep this one pending target
    -- alive through that synchronous teardown so the rebuilt exact row can
    -- bind and consume it.
    CS._settingsFinderNavigationRefresh = true
    CooldownCompanion:RefreshConfigPanel()
    CS._settingsFinderNavigationRefresh = nil
    if ST._ScheduleNavSettingHighlight then
        ST._ScheduleNavSettingHighlight()
    end
    return true
end

local function ClearSettingsFinderNavigation()
    if CS._settingsFinderNavigationRefresh then
        return
    end
    if CS.pendingSettingHighlight
        and CS.pendingSettingHighlight.source == "settingsFinder"
    then
        CS.pendingSettingHighlight = nil
    end
end

local function ValidateRegistry(context)
    local errors = {}
    local seen = {}
    for _, descriptor in ipairs(registry) do
        if seen[descriptor.id] then
            errors[#errors + 1] = "duplicate id: " .. descriptor.id
        end
        seen[descriptor.id] = true
        if descriptor._normalizedLabel == "" then
            errors[#errors + 1] = "missing searchable label: " .. descriptor.id
        end
        if not descriptor.tabLabel and not descriptor.navigate then
            errors[#errors + 1] = "missing tab route: " .. descriptor.id
        end
    end

    if context then
        -- Preparation is the real-catalog development assertion path. Passing
        -- the error sink lets this diagnostic API report instead of throw.
        PrepareSettingsFinderContext(context, errors)
    end
    return #errors == 0, errors
end

ST._DefineSettingRoute = DefineSettingRoute
ST._RegisterSettingsFinderContextPreparer = RegisterSettingsFinderContextPreparer
ST._BindSettingWidget = BindSettingWidget
ST._GetSettingsFinderContext = GetSettingsFinderContext
ST._GetSettingsFinderContextIdentity = GetSettingsFinderContextIdentity
ST._IsSettingsFinderContextCurrent = SettingsFinderContextIsCurrent
ST._IsSettingsFinderDescriptorApplicable = RevalidateSettingsFinderDescriptor
ST._PrepareSettingsFinderContext = PrepareSettingsFinderContext
ST._HasSettingsFinderEntries = HasSettingsFinderEntries
ST._SearchSettingsFinder = SearchSettingsFinder
ST._NavigateToFinderSetting = NavigateToFinderSetting
ST._ClearSettingsFinderNavigation = ClearSettingsFinderNavigation
ST._GetSettingsFinderRegistry = function() return registry end
ST._GetSettingsFinderDescriptor = function(id) return descriptorsById[id] end
ST._ValidateSettingsFinderRegistry = ValidateRegistry
ST._NormalizeSettingsFinderText = NormalizeSearchText
