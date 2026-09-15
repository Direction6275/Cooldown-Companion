-- Detached conversion for supported profiles and imports. No frames, current
-- aura state, or runtime panel visibility participate in destination selection.
local _, ST = ...
local Addon = ST.Addon
local Migration = {}
ST.UnifiedPanelMigration = Migration
local VERSION = 3

local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = Copy(item) end
    return result
end

local function Keys(map)
    local keys = {}
    for key in pairs(map or {}) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        if type(a) == type(b) and type(a) == "number" then return a < b end
        return type(a) .. tostring(a) < type(b) .. tostring(b)
    end)
    return keys
end

local function SpecTable(map, spec)
    return type(map) == "table" and (map[spec] or map[tostring(spec)]) or nil
end

local function Value(primary, fallback, key, default)
    if primary and primary[key] ~= nil then return primary[key] end
    if fallback and fallback[key] ~= nil then return fallback[key] end
    return default
end

local function Fingerprint(value)
    local kind = type(value)
    if kind == "table" then
        local result = { "{" }
        for _, key in ipairs(Keys(value)) do
            result[#result + 1] = Fingerprint(key) .. Fingerprint(value[key])
        end
        return table.concat(result) .. "}"
    end
    local str = kind == "number" and string.format("%.17g", value) or tostring(value)
    return kind:sub(1, 1) .. #str .. ":" .. str
end
Migration.Fingerprint = Fingerprint

local function SpecMembership(entry, fallback, settings, context, classKey)
    local specs = {}
    for key, value in pairs(type(entry.specs) == "table" and entry.specs or {}) do
        local spec = tonumber(value == true and key or value)
        if spec then specs[spec] = true end
    end
    local explicit = tonumber(entry.specID or entry.spec or entry.sourceSpecID or fallback)
    if explicit then specs[explicit] = true end
    local unassigned = not next(specs)
    if unassigned then
        for spec in pairs(context.classSpecs and context.classSpecs[classKey] or settings.layoutOrder or {}) do
            spec = tonumber(spec)
            if spec then specs[spec] = true end
        end
    end
    return specs, unassigned
end

local function Layout(settings, spec)
    return SpecTable(settings.layoutOrder, spec) or {}
end

local function Placement(slot, layout, settings)
    local vertical = Value(layout, settings, "orientation", "horizontal") == "vertical"
    local side = slot.position or "below"
    if vertical then side = slot.verticalPosition or (side == "above" and "left" or "right") end
    if side ~= "above" and side ~= "below" and side ~= "left" and side ~= "right" then side = "below" end
    local order = vertical and slot.verticalOrder or nil
    return side, slot.anchorRegion == "main" and "main" or "outer", tonumber(order or slot.order) or 1000, vertical
end

local ENTRY_KEYS = {
    "name", "isPetSpell", "isPassive", "isPassiveCooldown", "hasCharges", "maxCharges",
    "auraSpellID", "auraIDOverride", "auraUnitOverride", "auraTrackGroup", "auraTrackPet",
    "auraShellDim", "soundAlerts", "talentConditions", "loadConditions",
    "hideWhileOnCooldown", "hideWhileNotOnCooldown", "hideWhileZeroCharges", "showOnlyAtZeroCharges",
    "ignoreGCD", "neverDesaturate", "noCooldown", "customIconID", "customName",
}

-- Legacy appearance is resolved for its saved spec, then snapshotted through
-- ordinary customization sections. No current-spec getters are used here.
function Migration.ConvertLegacyBar(cab, settings, spec, slot, length)
    local id = tonumber(cab.spellID)
    if not id or id <= 0 or id ~= math.floor(id) then return nil, "Custom Bar has an invalid spell ID." end
    local layout, display = Layout(settings, spec), SpecTable(settings.displayProfiles, spec) or {}
    local spell = cab.entryType == "spell"
    local stackMode = cab.trackingMode == "stacks" or (not spell and cab.trackingMode ~= "active")
    local entry = { type = "spell", id = id, displayAs = "bars", addedAs = not spell and "aura" or "spell",
        enabled = cab.enabled == true and settings.enabled == true,
        auraTracking = not spell or cab.auraTracking == true,
        hideWhileAuraNotActive = cab.hideWhenInactive == true }
    for _, key in ipairs(ENTRY_KEYS) do entry[key] = Copy(cab[key]) end
    entry.name = entry.name or cab.spellName or ("Spell " .. id)
    entry.auraUnit = cab.auraUnit == "target" and "target" or "player"
    entry.auraBar = Copy(cab.auraBar or {})
    entry.auraBar.mode = stackMode and "stacks" or "duration"
    entry.auraBar.stackDisplayMode = cab.displayMode == "continuous" and "continuous" or "segmented"
    entry.auraBar.segmentGap = Value(layout, settings, "segmentGap", 4)
    entry.auraBar.segmentedSmoothing = Value(display, settings, "segmentedSmoothing", "on")

    local style = Copy(ST.ATTACHED_BAR_DEFAULTS)
    for _, section in pairs(ST.OVERRIDE_SECTIONS) do
        if section.modes and section.modes.bars then
            for _, key in ipairs(section.keys) do
                if cab[key] ~= nil then style[key] = Copy(cab[key]) end
            end
        end
    end
    local side, region, order, vertical = Placement(slot, layout, settings)
    local thickness = vertical and Value(layout, settings, "barWidth", Value(layout, settings, "barHeight", 12))
        or Value(layout, settings, "barHeight", 12)
    if Value(layout, settings, "customBarHeights", false) then
        thickness = vertical and (slot.barWidth or slot.barHeight or cab.barWidth or cab.barHeight or thickness)
            or (slot.barHeight or slot.barWidth or cab.barHeight or cab.barWidth or thickness)
    end
    style.barHeight, style.barLength = thickness, length or Value(layout, settings, "independentWidth", 180)
    style.barFillVertical = vertical
    style.barReverseFill = vertical and Value(layout, settings, "verticalFillDirection", "bottom_to_top") == "top_to_bottom"
    style.barTexture = Value(display, settings, "barTexture", "Solid")
    style.barBgColor = Copy(Value(display, settings, "backgroundColor", { 0, 0, 0, 0.5 }))
    style.borderColor = Copy(Value(display, settings, "borderColor", { 0, 0, 0, 1 }))
    style.borderSize = Value(display, settings, "borderStyle", "pixel") == "pixel"
        and Value(display, settings, "borderSize", 1) or 0
    style.borderRenderMode = Value(display, settings, "borderRenderMode", "custom")
    style.barColor = Copy(cab.barColor or { 0.5, 0.5, 1, 1 })
    style.barCooldownColor = Copy(cab.barCooldownColor or { 0.6, 0.13, 0.18, 1 })
    style.barChargeColor = Copy(cab.barChargeColor or { 1, 0.82, 0, 1 })
    style.barAuraColor = Copy(cab.barAuraColor or (not spell and style.barColor) or { 0.2, 1, 0.2, 1 })
    style.showBarIcon, style.showBarNameText, style.showKeybindText, style.showBarReadyText = false, false, false, false
    style.showCooldownText, style.showAuraText = cab.showDurationText == true, cab.showDurationText == true
    local showStacks = cab.showStackText
    if showStacks == nil then showStacks = not spell and stackMode and cab.showText == true end
    style.showAuraStackText, style.showChargeText = showStacks == true, spell and showStacks == true
    for _, mapping in ipairs({ { "durationText", "cooldown" }, { "durationText", "auraText" },
        { "stackText", "auraStack" }, { "stackText", "charge" } }) do
        local from, to = mapping[1], mapping[2]
        style[to .. "Font"] = cab[from .. "Font"] or "Friz Quadrata TT"
        style[to .. "FontSize"] = tonumber(cab[from .. "FontSize"]) or 10
        style[to .. "FontOutline"] = cab[from .. "FontOutline"] or "OUTLINE"
        style[to .. "FontColor"] = Copy(cab[from .. "FontColor"] or { 1, 1, 1, 1 })
    end
    local timePoint, timeX, timeY = ST.BarTextLayout.ResolveCustom(cab, "durationText", vertical, showStacks == true)
    style.barTimeTextAnchor, style.barCdTextOffsetX, style.barCdTextOffsetY = timePoint, timeX, timeY
    style.barAuraTextIndependent = false
    local stackPoint, stackX, stackY = ST.BarTextLayout.ResolveCustom(cab, "stackText", vertical, style.showAuraText)
    style.auraStackAnchor, style.auraStackXOffset, style.auraStackYOffset = stackPoint, stackX, stackY
    style.chargeAnchor, style.chargeXOffset, style.chargeYOffset = stackPoint, stackX, stackY
    style.pandemicMarkerMode = cab.pandemicMarkerEnabled == false and "off"
        or (cab.pandemicMarker ~= nil and (cab.pandemicMarker and "on" or "off")) or "auto"
    style.pandemicEffectEnabled, style.barPandemicColor = cab.pandemicEffect == true, Copy(cab.pandemicColor)
    style.durationLowTimeAuras = not spell or cab.durationLowTimeAuras == true
    if Addon.GetDurationFormat then style.durationFormat = Addon.GetDurationFormat(cab) end
    -- Legacy bars have no desaturation, GCD, range, or unusable icon effects.
    style.desaturateOnCooldown, style.showOutOfRange, style.showUnusable, style.showGCDSwipe = false, false, false, false
    style.showTooltips = false
    entry.styleOverrides, entry.overrideSections = {}, {}
    for sectionId, section in pairs(ST.OVERRIDE_SECTIONS) do
        if section.modes and section.modes.bars and ST.CanButtonUseOverrideSection(entry, sectionId) then
            entry.overrideSections[sectionId] = true
            for _, key in ipairs(section.keys) do
                entry.styleOverrides[key] = Copy(Value(style, section.defaults, key))
            end
        end
    end
    entry.barPlacement = { side = side, region = region, resources = "after" }
    return entry, style, order
end

local function IsOrdinaryBars(group)
    return type(group) == "table" and group.displayMode == "bars"
        and not ST.IsAuraPanelGroup(group) and not ST.IsTotemPanelGroup(group)
end

local function ConvertPanels(profile, report)
    for _, id in ipairs(Keys(profile.groups)) do
        local group = profile.groups[id]
        if IsOrdinaryBars(group) then
            ST._NormalizePanelOrientationKeys(group)
            ST._NormalizeBarStyleForPanelConversion(group.style)
            local style = Copy(ST._defaults.profile.globalStyle)
            for key, value in pairs(group.style or {}) do style[key] = Copy(value) end
            group.attachedBarStyle = style
            group.barOnlyLayout = { mode = "grid", compactLayout = group.compactLayout,
                compactGrowthDirection = group.compactGrowthDirection, maxVisibleButtons = group.maxVisibleButtons }
            group.displayMode = "icons"
            for _, entry in ipairs(group.buttons or {}) do entry.displayAs = "bars" end
            report.panels = report.panels + 1
        elseif ST.PanelSupportsAttachedBars(group) and (group.attachedBarStyle or group.attachedBarLayout) then
            if not group.barOnlyLayout then
                group.barOnlyLayout = { mode = "stack" }
                if group.attachedBarLayout and group.attachedBarLayout.length ~= nil then
                    group.attachedBarStyle = group.attachedBarStyle or Copy(ST.ATTACHED_BAR_DEFAULTS)
                    group.attachedBarStyle.barLength = group.attachedBarLayout.length
                end
            end
        end
        if ST.PanelSupportsAttachedBars(group) then
            ST._NormalizeBarStyleForPanelConversion(group.attachedBarStyle)
        end
    end
end

Migration.ConvertPanels = ConvertPanels

local function Allows(map, key, emptyMeansAll)
    if map == nil then return true end
    if type(map) ~= "table" then return false end
    return (emptyMeansAll and next(map) == nil) or map[key] == true or map[tostring(key)] == true
end

local function EligibleDestination(profile, group, classKey, spec, context)
    if not ST.PanelSupportsAttachedBars(group) then return false end
    local container = profile.groupContainers[group.parentContainerId]
    if not container then return false end
    -- Entity exports intentionally omit createdBy. Their incoming containers
    -- are scoped by the saved class/spec filters below; normal import landing
    -- assigns ownership later. Never relax the owner check for saved profiles.
    local ownerlessImport = context.importing and container.createdBy == nil
    if container.isGlobal ~= true and not ownerlessImport
        and context.ownerClasses[container.createdBy] ~= classKey then return false end
    local specs = group.specs or container.specs
    if not Allows(specs, spec, true) then return false end
    for _, entity in ipairs({ container, group }) do
        local conditions = entity.loadConditions or {}
        if not Allows(conditions.classAllowlist, classKey) or not Allows(conditions.specAllowlist, spec) then return false end
    end
    if not context._legacyDestinationRules then
        if group.enabled == false or container.enabled == false then return false end
        if not Allows(container.specs, spec, true) then return false end
        if group.anchor and group.anchor.relativeTo == (ST.CURSOR_ANCHOR_TARGET or "CooldownCompanionCursor") then return false end
    end
    return true
end

local function NextID(profile, mapKey, counterKey)
    local id = tonumber(profile[counterKey]) or 1
    while profile[mapKey][id] do id = id + 1 end
    profile[counterKey] = id + 1
    return id
end

local function NewDestination(profile, classKey, spec, settings, layout, context, report, identity)
    local containerId = NextID(profile, "groupContainers", "nextContainerId")
    local owner = context.classOwners[classKey]
    profile.groupContainers[containerId] = {
        name = "Bars", order = containerId, createdBy = owner, isGlobal = owner == nil,
        enabled = true, locked = true, specs = { [spec] = true },
        loadConditions = { classAllowlist = { [classKey] = true } },
        anchor = { point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", x = 0, y = 0 },
    }
    local id = NextID(profile, "groups", "nextGroupId")
    local anchor = Value(layout, settings, "independentAnchor")
    local validAnchor = type(anchor) == "table" and type(anchor.relativeTo or "UIParent") == "string"
    if validAnchor then
        local panelTarget = tonumber((anchor.relativeTo or ""):match("^CooldownCompanionGroup(%d+)$"))
        local containerTarget = tonumber((anchor.relativeTo or ""):match("^CooldownCompanionContainer(%d+)$"))
        if panelTarget and not profile.groups[panelTarget] then validAnchor = false end
        if containerTarget and not profile.groupContainers[containerTarget] then validAnchor = false end
        if anchor.relativeTo and anchor.relativeTo ~= "UIParent" and not panelTarget and not containerTarget
            and not (context.externalAnchors and context.externalAnchors[anchor.relativeTo]) then validAnchor = false end
    end
    if not validAnchor then
        if anchor then report.notices[#report.notices + 1] = "An unresolved bar-stack anchor uses the new panel's default position." end
        anchor = { point = "CENTER", relativeTo = "CooldownCompanionContainer" .. containerId,
            relativePoint = "CENTER", x = 0, y = 0 }
    end
    local style = Copy(ST.ATTACHED_BAR_DEFAULTS)
    style.barLength = Value(layout, settings, "independentWidth", 180)
    style.barFillVertical = Value(layout, settings, "orientation", "horizontal") == "vertical"
    style.barHeight = style.barFillVertical and Value(layout, settings, "barWidth", 12) or Value(layout, settings, "barHeight", 12)
    profile.groups[id] = {
        name = "Bars", displayMode = "icons", buttons = {}, enabled = true, parentContainerId = containerId,
        order = 1, style = Copy(ST._defaults.profile.globalStyle), attachedBarStyle = style,
        barOnlyLayout = { mode = "stack", stackGap = style.barFillVertical
            and Value(layout, settings, "verticalXOffset", Value(layout, settings, "yOffset", 3))
            or Value(layout, settings, "yOffset", 3) },
        attachedBarLayout = { spacing = Value(layout, settings, "barSpacing", 3.6), gap = Value(layout, settings, "yOffset", 3) },
        anchor = Copy(anchor), inheritPanelAlpha = false, baseRowAnchorVersion = 1,
        _legacyBarStack = identity,
    }
    -- An independent stack's alpha policy belongs to its replacement panel.
    for _, key in ipairs(ST.PANEL_COPY_SCOPES.icons.visibility.groupKeys) do
        profile.groups[id][key] = Copy(settings[key])
    end
    report.createdPanels = report.createdPanels + 1
    return id
end

local function Destination(profile, classKey, spec, settings, layout, context, report, destinations)
    local attachment = layout.attachment or {}
    local independent = attachment.mode == "independent"
        or (attachment.mode == nil and Value(layout, settings, "independentAnchorEnabled", false))
    local preferred
    if not independent then
        if context._legacyDestinationRules or context._legacyAttachmentModeRules then
            preferred = tonumber(attachment.panelId or settings.anchorGroupId)
        elseif attachment.mode == "panel" then
            preferred = tonumber(attachment.panelId)
        elseif attachment.mode == nil then
            preferred = tonumber(settings.anchorGroupId)
        end
    end
    if preferred and EligibleDestination(profile, profile.groups[preferred], classKey, spec, context) then return preferred end
    if not independent then
        local ids = Keys(profile.groups)
        table.sort(ids, function(a, b)
            local first, second = profile.groups[a], profile.groups[b]
            local ac, bc = profile.groupContainers[first.parentContainerId] or {}, profile.groupContainers[second.parentContainerId] or {}
            local ao, bo = ac.order or 0, bc.order or 0
            if not context._legacyDestinationRules then
                ao = (ac.specOrders and ac.specOrders[spec]) or ac.order or first.parentContainerId or 0
                bo = (bc.specOrders and bc.specOrders[spec]) or bc.order or second.parentContainerId or 0
            end
            if ao ~= bo then return ao < bo end
            if first.parentContainerId ~= second.parentContainerId then
                if not context._legacyDestinationRules then
                    local ai, bi = tonumber(first.parentContainerId), tonumber(second.parentContainerId)
                    if ai and bi then return ai < bi end
                end
                return tostring(first.parentContainerId) < tostring(second.parentContainerId)
            end
            if (first.order or 0) ~= (second.order or 0) then return (first.order or 0) < (second.order or 0) end
            if not context._legacyDestinationRules and tonumber(a) and tonumber(b) then return tonumber(a) < tonumber(b) end
            return tostring(a) < tostring(b)
        end)
        for _, id in ipairs(ids) do
            local group = profile.groups[id]
            local container = profile.groupContainers[group.parentContainerId] or {}
            -- Match automatic module anchoring's saved opt-in rules. In
            -- particular, global groups are excluded unless they opt in.
            local automatic = context._legacyDestinationRules or (container.isGlobal
                and container.anchorEligible == true or not container.isGlobal and container.anchorEligible ~= false)
            if automatic and group.anchorEligible ~= false
                and EligibleDestination(profile, group, classKey, spec, context) then return id end
        end
    end
    local identity = classKey .. ":" .. Fingerprint({ independent = independent, anchor = Value(layout, settings, "independentAnchor"),
        length = Value(layout, settings, "independentWidth", 180), orientation = Value(layout, settings, "orientation", "horizontal"),
        spacing = Value(layout, settings, "barSpacing", 3.6), height = Value(layout, settings, "barHeight", 12),
        gap = Value(layout, settings, Value(layout, settings, "orientation", "horizontal") == "vertical"
            and "verticalXOffset" or "yOffset", 3) })
    local id = destinations[identity]
    if not id then
        for _, candidateId in ipairs(Keys(profile.groups)) do
            if profile.groups[candidateId]._legacyBarStack == identity then id = candidateId; break end
        end
    end
    if not id then id = NewDestination(profile, classKey, spec, settings, layout, context, report, identity) end
    destinations[identity] = id
    profile.groupContainers[profile.groups[id].parentContainerId].specs[spec] = true
    return id
end

local function LegacyEntries(settings, classKey, context)
    local entries = {}
    local function add(cab, key, spec, slot, layoutId)
        if type(cab) ~= "table" or cab.spellID == nil then return end
        local origin = classKey .. ":" .. (layoutId and ("id:" .. tostring(layoutId))
            or cab.customBarId and ("id:" .. cab.customBarId) or key)
        local specs, unassigned = SpecMembership(cab, spec, settings, context, classKey)
        entries[#entries + 1] = { cab = cab, origin = origin, specs = specs, unassigned = unassigned,
            slot = slot, layoutId = layoutId or cab.customBarId, ordinal = #entries + 1 }
    end
    local store = settings.customBars
    if type(store) == "table" and (store.entries or store.order) then
        local seen = {}
        for _, id in ipairs(store.order or {}) do
            if not seen[id] then add((store.entries or {})[id], "shared:" .. tostring(id), nil, nil, id); seen[id] = true end
        end
        for _, id in ipairs(Keys(store.entries)) do
            if not seen[id] then add(store.entries[id], "shared:" .. tostring(id), nil, nil, id) end
        end
    elseif type(store) == "table" then
        for _, spec in ipairs(Keys(store)) do
            if tonumber(spec) and type(store[spec]) == "table" then
                for _, key in ipairs(Keys(store[spec])) do add(store[spec][key], "spec:" .. spec .. ":" .. key, spec) end
            end
        end
    end
    for _, spec in ipairs(Keys(settings.customAuraBars)) do
        if tonumber(spec) and type(settings.customAuraBars[spec]) == "table" then
            for _, key in ipairs(Keys(settings.customAuraBars[spec])) do
                add(settings.customAuraBars[spec][key], "aura:" .. spec .. ":" .. key, spec, key)
            end
        end
    end
    return entries
end

local function ResourceBlocks(settings, spec, report, classKey)
    local layout = Layout(settings, spec)
    settings.layoutOrder = settings.layoutOrder or {}
    if not SpecTable(settings.layoutOrder, spec) then settings.layoutOrder[spec] = layout end
    layout.resources = layout.resources or {}
    local rb = ST._RB or {}
    local classID = ST._GetClassIDFromResourceBarClassKey and ST._GetClassIDFromResourceBarClassKey(classKey)
    local catalog = rb.SPEC_RESOURCES_CONFIG and rb.SPEC_RESOURCES_CONFIG[tonumber(spec)]
        or (rb.CLASS_RESOURCES_CONFIG and rb.CLASS_RESOURCES_CONFIG[classID])
    local allowed
    if catalog then
        allowed = {}
        for _, powerType in ipairs(catalog) do
            local key = rb.GetCanonicalPowerType and rb.GetCanonicalPowerType(powerType) or powerType
            allowed[key] = true
        end
        if rb.RESOURCE_HEALTH then allowed[rb.RESOURCE_HEALTH] = true end
        for key in pairs(allowed) do
            local config = settings.resources and settings.resources[key]
            if (key ~= rb.RESOURCE_HEALTH or (config and config.enabled == true))
                and not layout.resources[key] and not layout.resources[tostring(key)] then
                layout.resources[key] = { position = "below", order = 900 + key }
            end
        end
    end
    local blocks = {}
    for _, key in ipairs(Keys(layout.resources)) do
        local slot = layout.resources[key]
        local config = settings.resources and (settings.resources[key] or settings.resources[tonumber(key)])
        if type(slot) == "table" and (not allowed or allowed[tonumber(key) or key])
            and ((tonumber(key) or key) ~= rb.RESOURCE_HEALTH or (config and config.enabled == true))
            and (not config or config.enabled ~= false) then
            local side, region, order = Placement(slot, layout, settings)
            local block = blocks[side]
            if not block then
                block = { first = order, last = order, region = region, slots = {} }; blocks[side] = block
            else
                if region ~= block.region then block.conflict = true end
                if order < block.first then block.first, block.region = order, region end
                block.last = math.max(block.last, order)
            end
            block.slots[#block.slots + 1] = slot
        end
    end
    layout.resourceBlocks = layout.resourceBlocks or {}
    for side, block in pairs(blocks) do
        local saved = layout.resourceBlocks[side]
        if saved then block.region = saved.anchorRegion == "main" and "main" or "outer" end
        layout.resourceBlocks[side] = { anchorRegion = block.region == "main" and "main" or "panel" }
        for _, slot in ipairs(block.slots) do slot.anchorRegion = layout.resourceBlocks[side].anchorRegion end
        if block.conflict then report.notices[#report.notices + 1] = "Resources on " .. side .. " were grouped at the first resource's attachment region." end
    end
    return blocks
end

local function StripLegacyStore(settings)
    if type(settings) ~= "table" then return end
    settings.customBars, settings.customAuraBars, settings.nextCustomBarId, settings.customAuraBarSlots = nil, nil, nil, nil
    for _, layout in pairs(settings.layoutOrder or {}) do
        if type(layout) == "table" then
            layout.customBars, layout.customAuraBarSlots, layout.auraBlockTargetFirst = nil, nil, nil
        end
    end
end

local function Validate(profile)
    if type(profile) ~= "table" or type(profile.groups) ~= "table" or type(profile.groupContainers) ~= "table" then
        return false, "Panel data is incomplete."
    end
    for _, group in pairs(profile.groups) do
        if type(group) ~= "table" or (group.buttons ~= nil and type(group.buttons) ~= "table") then
            return false, "A panel has invalid entry data."
        end
        for _, style in ipairs({ group.attachedBarStyle or {}, IsOrdinaryBars(group) and group.style or {} }) do
            for _, key in ipairs({ "barLength", "barHeight" }) do
                local value = style[key]
                if value ~= nil and (type(value) ~= "number" or value ~= value or value <= 0 or value == math.huge) then
                    return false, "A panel has invalid bar dimensions."
                end
            end
        end
        for _, entry in ipairs(group.buttons or {}) do
            if type(entry) ~= "table" then return false, "A panel contains an invalid entry." end
            if entry._legacyBarOrigin then
                if entry.type ~= "spell" or type(entry.id) ~= "number" or entry.id <= 0
                    or not profile.groupContainers[group.parentContainerId] then return false, "A converted bar has invalid ownership." end
                local style = entry.styleOverrides
                -- The origin is provenance, not permanent customization or
                -- presentation ownership. Revert can remove every override;
                -- Icon presentation legitimately clears displayAs afterward.
                if style ~= nil and type(style) ~= "table" then return false, "A converted bar has invalid customization data." end
                for _, key in ipairs({ "barLength", "barHeight" }) do
                    local value = style and style[key]
                    if value ~= nil and (type(value) ~= "number" or value <= 0 or value ~= value or value == math.huge) then
                        return false, "A converted bar has invalid dimensions."
                    end
                end
            end
        end
    end
    return true
end
Migration.Validate = Validate

-- Version 1 did not honor global-group automatic-anchor opt-in or spec order;
-- versions 1 and 2 also used dormant manual targets in Automatic mode.
-- Reconstruct both decisions from its backup, then move only surviving entries
-- still at that original destination. Never recreate deleted entries, undo a
-- manual move, or replace the user's current entry customizations.
local function RepairConvertedDestinations(profile, context, report)
    local stamp, backup = profile._unifiedPanelMigration, profile._unifiedPanelBackup
    if not stamp or (stamp.version ~= 1 and stamp.version ~= 2) or type(backup) ~= "table" then return true end
    local priorContext, correctedContext = Copy(context), Copy(context)
    priorContext._legacyDestinationRules = stamp.version == 1
    priorContext._legacyAttachmentModeRules = true
    correctedContext._legacyDestinationRules = nil
    correctedContext._legacyAttachmentModeRules = nil
    local prior, priorError = Migration.Build(backup, priorContext)
    if not prior then return false, priorError end
    local corrected, correctedError = Migration.Build(backup, correctedContext)
    if not corrected then return false, correctedError end
    local function IndexEntries(snapshot)
        local result = {}
        for id, group in pairs(snapshot.groups) do
            for _, entry in ipairs(group.buttons or {}) do
                if entry._legacyBarOrigin then
                    local specs = result[entry._legacyBarOrigin] or {}
                    result[entry._legacyBarOrigin] = specs
                    for spec, enabled in pairs(entry.loadConditions.specAllowlist or {}) do
                        if enabled then specs[tonumber(spec) or spec] = { groupId = id, entry = entry } end
                    end
                end
            end
        end
        return result
    end
    local oldEntries, newEntries = IndexEntries(prior), IndexEntries(corrected)
    local installed = {}
    local function DestinationID(id)
        if installed[id] then return installed[id] end
        if backup.groups[id] then return ST.PanelSupportsAttachedBars(profile.groups[id]) and id end
        local desired = corrected.groups[id]
        for currentId, group in pairs(profile.groups) do
            if desired._legacyBarStack and group._legacyBarStack == desired._legacyBarStack then
                installed[id] = currentId; return currentId
            end
        end
        local cid = NextID(profile, "groupContainers", "nextContainerId")
        local groupId = NextID(profile, "groups", "nextGroupId")
        local container = Copy(corrected.groupContainers[desired.parentContainerId])
        local group = Copy(desired)
        container.order, group.parentContainerId, group.buttons = cid, cid, {}
        if group.anchor and group.anchor.relativeTo == "CooldownCompanionContainer" .. desired.parentContainerId then
            group.anchor.relativeTo = "CooldownCompanionContainer" .. cid
        end
        profile.groupContainers[cid], profile.groups[groupId] = container, group
        installed[id] = groupId
        report.createdPanels = report.createdPanels + 1
        return groupId
    end
    local moves, repaired = {}, 0
    for _, id in ipairs(Keys(profile.groups)) do
        local group, retained = profile.groups[id], {}
        for _, entry in ipairs(group.buttons or {}) do
            local old, new = oldEntries[entry._legacyBarOrigin], newEntries[entry._legacyBarOrigin]
            local destinations, changed = {}, false
            for spec, enabled in pairs(entry.loadConditions and entry.loadConditions.specAllowlist or {}) do
                if enabled then
                    local key = tonumber(spec) or spec
                    local before, after = old and old[key], new and new[key]
                    local target = id
                    if before and after and before.groupId == id and after.groupId ~= id and before.entry.id == entry.id then
                        target = DestinationID(after.groupId) or id
                    end
                    changed = changed or target ~= id
                    destinations[target] = destinations[target] or {}
                    destinations[target][key] = true
                end
            end
            if changed then
                repaired = repaired + 1
                for _, target in ipairs(Keys(destinations)) do
                    local moved = Copy(entry)
                    moved.loadConditions.specAllowlist = destinations[target]
                    if target == id then retained[#retained + 1] = moved
                    else moves[#moves + 1] = { destination = target, entry = moved } end
                end
            else retained[#retained + 1] = entry end
        end
        group.buttons = retained
    end
    for _, move in ipairs(moves) do
        local group, entry = profile.groups[move.destination], move.entry
        group.buttons = group.buttons or {}
        local used = {}
        for _, existing in ipairs(group.buttons) do
            if existing._auraKey then used[tostring(existing._auraKey)] = true end
        end
        local key = tonumber(group.nextAuraKey) or 1
        while used[tostring(key)] do key = key + 1 end
        entry._auraKey, group.nextAuraKey = tostring(key), key + 1
        group.buttons[#group.buttons + 1] = entry
    end
    if repaired > 0 then
        report.repairedBars = repaired
        report.notices[#report.notices + 1] = repaired .. " migrated bar entries moved to their corrected saved attachment destinations."
    end
    return true
end

function Migration.Build(source, context)
    local valid, errorText = Validate(source)
    if not valid then return nil, errorText end
    context = context or {}
    context.ownerClasses, context.classOwners = context.ownerClasses or {}, context.classOwners or {}
    local profile = Copy(source)
    profile.resourceBarsByClass = profile.resourceBarsByClass or {}
    -- Detached legacy imports retain exporter IDs until normal import remapping.
    for _, owner in ipairs(Keys(profile.resourceBarsByChar)) do
        local settings = profile.resourceBarsByChar[owner]
        if type(settings) == "table" and (next(settings.customBars or {}) or next(settings.customAuraBars or {})) then
            local class = context.ownerClasses[owner]
            if not class then return nil, "The Resources owner has no class information: " .. tostring(owner) end
            if ST._NormalizeResourceSettingsForPanelConversion then ST._NormalizeResourceSettingsForPanelConversion(settings, class) end
            local existing = profile.resourceBarsByClass[class]
            if existing and ST._NormalizeResourceSettingsForPanelConversion then ST._NormalizeResourceSettingsForPanelConversion(existing, class) end
            if existing and Fingerprint(existing) ~= Fingerprint(settings) then
                return nil, "Resources settings conflict for " .. class .. "; source data was kept."
            end
            profile.resourceBarsByClass[class] = settings
            profile.resourceBarsByChar[owner] = nil
        end
    end
    local seed = profile.legacyResourceBarsSeed or profile.resourceBars
    if type(seed) == "table" and (next(seed.customBars or {}) or next(seed.customAuraBars or {})) then
        local class = context.defaultClass
        if not class then return nil, "The legacy Resources export has no source class information." end
        if ST._NormalizeResourceSettingsForPanelConversion then ST._NormalizeResourceSettingsForPanelConversion(seed, class) end
        local existing = profile.resourceBarsByClass[class]
        if existing and ST._NormalizeResourceSettingsForPanelConversion then ST._NormalizeResourceSettingsForPanelConversion(existing, class) end
        if existing and Fingerprint(existing) ~= Fingerprint(seed) then
            return nil, "The legacy Resources seed conflicts with " .. class .. "; source data was kept."
        end
        profile.resourceBarsByClass[class] = seed
    end
    local report = { panels = 0, bars = 0, createdPanels = 0, regrouped = 0, notices = {} }
    local repaired, repairError = RepairConvertedDestinations(profile, context, report)
    if not repaired then return nil, repairError end
    local conflicts = profile.resourceBarMigration and profile.resourceBarMigration.conflicts
    if type(conflicts) == "table" and next(conflicts) then
        return nil, "Resolve the existing Resources class conflicts before converting Custom Bars."
    end
    ConvertPanels(profile, report)
    local destinations, variants, merged = {}, {}, {}
    context.classSpecs = context.classSpecs or {}
    local completed = Copy(profile._unifiedPanelMigration and profile._unifiedPanelMigration.completed or {})
    for _, classKey in ipairs(Keys(profile.resourceBarsByClass)) do
        local settings = profile.resourceBarsByClass[classKey]
        if type(settings) == "table" then
            context.classSpecs[classKey] = context.classSpecs[classKey]
                or (ST._GetResourceBarClassSpecInfo and ST._GetResourceBarClassSpecInfo(classKey))
            if ST._NormalizeResourceSettingsForPanelConversion then ST._NormalizeResourceSettingsForPanelConversion(settings, classKey) end
            local blocksBySpec = {}
            local independentDestinations = {}
            local entries = LegacyEntries(settings, classKey, context)
            for _, legacy in ipairs(entries) do
                if not next(legacy.specs) then return nil, "A Custom Bar has no resolvable specialization: " .. legacy.origin end
                for _, spec in ipairs(Keys(legacy.specs)) do
                    local completionKey = (context.originPrefix or "saved:") .. legacy.origin .. ":" .. spec
                    if not completed[completionKey] then
                        local layout = Layout(settings, spec)
                        local slot = legacy.layoutId and layout.customBars and layout.customBars[legacy.layoutId]
                        slot = slot or (legacy.slot and layout.customAuraBarSlots and SpecTable(layout.customAuraBarSlots, legacy.slot))
                            or { order = 1000 + legacy.ordinal }
                        local entry, style, order = Migration.ConvertLegacyBar(legacy.cab, settings, spec, slot)
                        if not entry then return nil, style end
                        if legacy.unassigned then entry.enabled = false end
                        local destination = Destination(profile, classKey, spec, settings, layout, context, report, destinations)
                        local attachment = layout.attachment or {}
                        if attachment.mode == "independent" or (attachment.mode == nil
                            and Value(layout, settings, "independentAnchorEnabled", false)) then
                            independentDestinations[spec] = destination
                        end
                        local blocks = blocksBySpec[spec]
                        if not blocks then blocks = ResourceBlocks(settings, spec, report, classKey); blocksBySpec[spec] = blocks end
                        local block = blocks[entry.barPlacement.side]
                        if block then
                            entry.barPlacement.resources = order < block.first and "before" or "after"
                            if order >= block.first and order < block.last then
                                report.regrouped = report.regrouped + 1
                            end
                        end
                        local bucket = 0
                        if entry.addedAs == "aura" and entry.hideWhileAuraNotActive
                            and not entry.auraTrackGroup and not entry.auraTrackPet then
                            entry.barPlacement.resources = "after"
                            local side, region = entry.barPlacement.side, entry.barPlacement.region
                            local flagKey = side
                            if region == "main" and (side == "above" or side == "below")
                                and ST.ResolvePanelAttachmentRegion(profile.groups[destination], side, "outer") == "outer" then
                                flagKey = side .. "Main"
                            end
                            local targetFirst = layout.auraBlockTargetFirst and layout.auraBlockTargetFirst[flagKey] == true
                            bucket = (entry.auraUnit == "target") == (targetFirst == true) and 1 or 2
                        end
                        local conditions = entry.loadConditions or {}
                        local specAllowed = Allows(conditions.specAllowlist, spec)
                        local classAllowed = Allows(conditions.classAllowlist, classKey)
                        conditions.specAllowlist, conditions.classAllowlist = nil, nil
                        entry.loadConditions = conditions
                        if not specAllowed or not classAllowed then entry.enabled = false end
                        entry._legacyBarOrigin = (context.originPrefix or "saved:") .. legacy.origin
                        local signature = entry._legacyBarOrigin .. ":" .. destination .. ":" .. bucket .. ":" .. order .. ":" .. Fingerprint(entry)
                        local variant = merged[signature]
                        if not variant then
                            variant = { entry = entry, destination = destination, order = order, bucket = bucket, specs = {}, signature = signature }
                            merged[signature], variants[#variants + 1] = variant, variant
                        end
                        variant.specs[spec] = true
                        completed[completionKey] = true
                    end
                end
            end
            -- Normalize resource blocks even for specs with no Custom Bars.
            for _, spec in ipairs(Keys(settings.layoutOrder)) do
                if not blocksBySpec[tonumber(spec) or spec] then ResourceBlocks(settings, spec, report, classKey) end
            end
            for spec, destination in pairs(independentDestinations) do
                -- The replacement panel keeps the independent anchor. Its
                -- Resources block must join that same coordinator or the two
                -- stacks would overlap at the old anchor after conversion.
                local layout = Layout(settings, spec)
                layout.attachment = { mode = "panel", panelId = destination }
                report.notices[#report.notices + 1] = "Resources now attach to the replacement Bars panel at the former independent stack's position."
            end
            StripLegacyStore(settings)
        end
    end
    table.sort(variants, function(a, b)
        if a.destination ~= b.destination then return a.destination < b.destination end
        if a.bucket ~= b.bucket then return a.bucket < b.bucket end
        if a.order ~= b.order then return a.order < b.order end
        return a.signature < b.signature
    end)
    for _, variant in ipairs(variants) do
        local entry, group = variant.entry, profile.groups[variant.destination]
        entry.loadConditions.specAllowlist = variant.specs
        if context.importing then
            entry._legacyBarImportKey = entry._legacyBarOrigin .. ":" .. Fingerprint({
                destination = variant.destination, specs = variant.specs,
            })
        end
        group.buttons = group.buttons or {}
        group.buttons[#group.buttons + 1] = entry
        group.nextAuraKey = tonumber(group.nextAuraKey) or 1
        local used = {}
        for _, existing in ipairs(group.buttons) do
            if existing._auraKey then used[tostring(existing._auraKey)] = true end
        end
        while used[tostring(group.nextAuraKey)] do group.nextAuraKey = group.nextAuraKey + 1 end
        entry._auraKey, group.nextAuraKey = tostring(group.nextAuraKey), group.nextAuraKey + 1
        report.bars = report.bars + 1
    end
    -- Class normalization has already selected/merged these legacy buckets.
    -- Retain their resource settings, but prevent them from reseeding old bars.
    for _, settings in pairs(profile.resourceBarsByChar or {}) do StripLegacyStore(settings) end
    StripLegacyStore(profile.resourceBars)
    StripLegacyStore(profile.legacyResourceBarsSeed)
    if report.regrouped > 0 then
        report.notices[#report.notices + 1] = report.regrouped .. " formerly interleaved bars now follow their Resources block."
    end
    valid, errorText = Validate(profile)
    if not valid then return nil, errorText end
    profile._unifiedPanelMigration = { version = VERSION, completed = completed }
    return profile, report
end

local CONVERTED_FIELDS = { "groups", "groupContainers", "nextGroupId", "nextContainerId", "resourceBarsByClass",
    "resourceBarsByChar", "resourceBars", "legacyResourceBarsSeed" }

function Migration.Apply(profile, context)
    if profile._unifiedPanelMigration and profile._unifiedPanelMigration.version == VERSION then
        local pending = false
        for _, group in pairs(profile.groups or {}) do
            if IsOrdinaryBars(group) or (ST.PanelSupportsAttachedBars(group)
                and (group.attachedBarStyle or group.attachedBarLayout) and not group.barOnlyLayout) then pending = true; break end
        end
        if not pending then
            for classKey, settings in pairs(profile.resourceBarsByClass or {}) do
                if #LegacyEntries(settings, classKey, context or {}) > 0 then pending = true; break end
            end
        end
        if not pending then
            local function HasLegacy(settings)
                return type(settings) == "table" and (next(settings.customBars or {}) or next(settings.customAuraBars or {}))
            end
            pending = HasLegacy(profile.resourceBars) or HasLegacy(profile.legacyResourceBarsSeed)
            for _, settings in pairs(profile.resourceBarsByChar or {}) do
                if HasLegacy(settings) then pending = true; break end
            end
        end
        if not pending then return true, { panels = 0, bars = 0, createdPanels = 0, regrouped = 0, notices = {} } end
    end
    local candidate, report = Migration.Build(profile, context)
    if not candidate then return false, report end
    -- No source mutation has occurred before this point. Keep one original
    -- snapshot, outside export payloads, and stamp only after replacement.
    local backup = profile._unifiedPanelBackup
    if not backup then
        backup = {}
        for _, key in ipairs(CONVERTED_FIELDS) do backup[key] = Copy(profile[key]) end
    end
    for _, key in ipairs(CONVERTED_FIELDS) do profile[key] = candidate[key] end
    profile._unifiedPanelBackup = backup
    profile._unifiedPanelMigration = candidate._unifiedPanelMigration
    return true, report
end

function Addon:GetUnifiedPanelConversionContext()
    local context = { ownerClasses = {}, classOwners = {}, classSpecs = {}, externalAnchors = {} }
    for _, charKey in ipairs(Keys(self.db.global and self.db.global.characterInfo)) do
        local info = self.db.global.characterInfo[charKey]
        local class = info.classFilename or (ST._GetResourceBarClassKeyFromClassID and ST._GetResourceBarClassKeyFromClassID(info.classID))
        if class then
            context.ownerClasses[charKey] = class
            context.classOwners[class] = context.classOwners[class] or charKey
        end
    end
    if self._playerClassFilename and self.db.keys and self.db.keys.char then
        context.ownerClasses[self.db.keys.char] = self._playerClassFilename
        context.classOwners[self._playerClassFilename] = self.db.keys.char
    end
    for classKey, settings in pairs(self.db.profile.resourceBarsByClass or {}) do
        if ST._GetResourceBarClassSpecInfo then context.classSpecs[classKey] = ST._GetResourceBarClassSpecInfo(classKey) end
        for _, layout in pairs(settings.layoutOrder or {}) do
            local anchor = layout.independentAnchor or settings.independentAnchor
            if anchor and type(anchor.relativeTo) == "string" and _G[anchor.relativeTo] then context.externalAnchors[anchor.relativeTo] = true end
        end
    end
    context.defaultClass = self._playerClassFilename
    return context
end

function Addon:RunUnifiedPanelMigration()
    local profile = self.db and self.db.profile
    if not profile then return false end
    local ok, report = Migration.Apply(profile, self:GetUnifiedPanelConversionContext())
    if not ok then
        self:Print("Panel conversion stopped: " .. tostring(report) .. " Saved panel data was kept.")
        return false
    end
    if report.panels > 0 or report.bars > 0 or (report.repairedBars or 0) > 0 then
        self:Print(("Updated Panels: %d Bar Panels and %d Custom Bars converted; %d panels created.")
            :format(report.panels, report.bars, report.createdPanels))
        for _, notice in ipairs(report.notices) do self:Print(notice) end
    end
    return true
end

-- Supported entity payloads are projected into detached profile data, passed
-- through the same converter, and rebuilt as normal panel-containing packets.
function Migration.ConvertImport(data, context)
    context = Copy(context or {})
    context.importing = true
    context.ownerClasses, context.classOwners, context.classSpecs = context.ownerClasses or {}, context.classOwners or {}, context.classSpecs or {}
    data = Copy(data)
    for owner, info in pairs(data._characterInfo or {}) do
        local class = info.classFilename or (ST._GetResourceBarClassKeyFromClassID and ST._GetResourceBarClassKeyFromClassID(info.classID))
        if class then context.ownerClasses[owner] = class; context.classOwners[class] = owner end
    end
    if data._exporterCharKey then context.defaultClass = context.ownerClasses[data._exporterCharKey] end
    if data.profile and (data.reportKind == "bugReport" or not data.type) then
        local meta = data.meta or {}
        local class = meta.classFilename or (ST._GetResourceBarClassKeyFromClassID and ST._GetResourceBarClassKeyFromClassID(meta.classID))
        if meta.charKey and class then
            context.defaultClass = class
            context.ownerClasses[meta.charKey], context.classOwners[class] = class, meta.charKey
            context.classSpecs[class] = context.classSpecs[class] or (ST._GetResourceBarClassSpecInfo and ST._GetResourceBarClassSpecInfo(class))
        end
        local converted, report = Migration.ConvertImport(data.profile, context)
        if not converted then return nil, report end
        data.profile = converted
        return data, report
    end
    if not data.type then
        if Addon.MigrateFoldersIntoGroups then Addon:MigrateFoldersIntoGroups(data, data._characterInfo) end
        return Migration.Build(data, context)
    end
    if data.type ~= "setup" and data.type ~= "customBars" and data.type ~= "containers"
        and data.type ~= "container" and data.type ~= "folder" then return data end
    local profile = { groups = {}, groupContainers = {}, resourceBarsByClass = {}, nextGroupId = 1, nextContainerId = 1 }
    local packets = data.containers or (data.container and { data }) or {}
    -- Reserve explicit IDs before assigning IDs to older packets that lack
    -- them. Packet order cannot create an accidental collision.
    for _, packet in ipairs(packets) do
        profile.nextContainerId = math.max(profile.nextContainerId, (tonumber(packet._originalContainerId) or 0) + 1)
        for _, panel in ipairs(packet.panels or {}) do
            profile.nextGroupId = math.max(profile.nextGroupId, (tonumber(panel._originalGroupId) or 0) + 1)
        end
    end
    for _, packet in ipairs(packets) do
        if type(packet.container) ~= "table" then return nil, "A group in this import is invalid." end
        local cid = tonumber(packet._originalContainerId) or NextID(profile, "groupContainers", "nextContainerId")
        if profile.groupContainers[cid] then return nil, "The import repeats a group ID." end
        profile.groupContainers[cid] = Copy(packet.container)
        for _, panel in ipairs(packet.panels or {}) do
            local id = tonumber(panel._originalGroupId) or NextID(profile, "groups", "nextGroupId")
            if profile.groups[id] then return nil, "The import repeats a panel ID." end
            panel = Copy(panel)
            if IsOrdinaryBars(panel) then
                for index, entry in ipairs(panel.buttons or {}) do
                    entry._legacyBarImportKey = (context.originPrefix or "import:") .. "panel:" .. id .. ":" .. index
                end
            end
            panel.parentContainerId = cid
            profile.groups[id] = panel
        end
    end
    local function Class(section)
        return ST._NormalizeResourceBarClassKey and ST._NormalizeResourceBarClassKey(section.classFilename)
            or section.classFilename
            or (ST._GetResourceBarClassKeyFromClassID and ST._GetResourceBarClassKeyFromClassID(section.classID))
    end
    local resources = data.resources
    if resources and resources.settings then
        local class = Class(resources)
        if not class then return nil, "The Resources import has no class information." end
        profile.resourceBarsByClass[class] = Copy(resources.settings)
        context.classSpecs[class] = context.classSpecs[class] or (ST._GetResourceBarClassSpecInfo and ST._GetResourceBarClassSpecInfo(class))
        -- A saved attachment into this same packet establishes the source
        -- owner's class even when the old entity export omitted character info.
        for _, layout in pairs(resources.settings.layoutOrder or {}) do
            local id = layout.attachment and layout.attachment.panelId or resources.settings.anchorGroupId
            local panel = profile.groups[tonumber(id)]
            local container = panel and profile.groupContainers[panel.parentContainerId]
            if container and container.createdBy and not context.ownerClasses[container.createdBy] then
                context.ownerClasses[container.createdBy] = class
            end
        end
    end
    local custom = data.type == "customBars" and data or data.customBars
    if custom and type(custom.bars) == "table" then
        local class = Class(custom)
        if not class then return nil, "The Custom Bars import has no class information." end
        context.classSpecs[class] = context.classSpecs[class] or (ST._GetResourceBarClassSpecInfo and ST._GetResourceBarClassSpecInfo(class))
        local settings = profile.resourceBarsByClass[class]
        if not settings then
            settings = Copy(ST._defaults.profile.resourceBars or {})
            settings.enabled, settings.layoutOrder = true, {}
        elseif ST._NormalizeResourceSettingsForPanelConversion then
            ST._NormalizeResourceSettingsForPanelConversion(settings, class)
        end
        settings.customBars = settings.customBars or { entries = {}, order = {} }
        local store = settings.customBars
        if not store.entries or not store.order then return nil, "Custom Bars use incompatible legacy stores in this import." end
        local seen = {}
        for index, bar in ipairs(custom.bars) do
            local id = bar.customBarId or ("legacy_" .. index)
            if seen[id] then id = tostring(id) .. ":" .. index end
            seen[id] = true
            local existing = store.entries[id]
            local incoming = Copy(bar)
            incoming.customBarId = id
            if ST._NormalizeResourceSettingsForPanelConversion then
                local one = { customBars = { entries = { [id] = incoming }, order = { id } } }
                ST._NormalizeResourceSettingsForPanelConversion(one, class)
                incoming = one.customBars.entries[id]
                if not incoming then return nil, "A Custom Bar does not belong to the import's class." end
            end
            -- Setup exports historically included these same definitions
            -- twice. A genuinely conflicting copy must not silently win.
            if existing and Fingerprint(existing) ~= Fingerprint(incoming) then
                return nil, "Resources and Custom Bars contain conflicting definitions for " .. tostring(id) .. "."
            end
            if not existing then
                store.entries[id] = incoming
                store.order[#store.order + 1] = id
                for spec, slots in pairs(custom.layouts or {}) do
                    local layout = SpecTable(settings.layoutOrder, spec)
                    if not layout then
                        layout = { attachment = { mode = "independent" } }
                        settings.layoutOrder[spec] = layout
                    end
                    layout.customBars = layout.customBars or {}
                    layout.customBars[id] = Copy(slots[bar.customBarId])
                end
            end
        end
        profile.resourceBarsByClass[class] = settings
    end
    local converted, report = Migration.Build(profile, context)
    if not converted then return nil, report end
    local rebuilt = {}
    for _, cid in ipairs(Keys(converted.groupContainers)) do
        local packet = { container = converted.groupContainers[cid], panels = {}, _originalContainerId = cid }
        for _, id in ipairs(Keys(converted.groups)) do
            local panel = converted.groups[id]
            if panel.parentContainerId == cid then
                panel._originalGroupId = id
                packet.panels[#packet.panels + 1] = panel
            end
        end
        table.sort(packet.panels, function(a, b)
            if (a.order or 0) ~= (b.order or 0) then return (a.order or 0) < (b.order or 0) end
            return a._originalGroupId < b._originalGroupId
        end)
        rebuilt[#rebuilt + 1] = packet
    end
    table.sort(rebuilt, function(a, b)
        if (a.container.order or 0) ~= (b.container.order or 0) then return (a.container.order or 0) < (b.container.order or 0) end
        return a._originalContainerId < b._originalContainerId
    end)
    data.customBars = nil
    if resources then
        resources.settings = converted.resourceBarsByClass[Class(resources)]
        data.type, data.containers = "setup", rebuilt
    elseif data.type == "folder" then
        data.containers = rebuilt
    elseif data.type == "container" and #rebuilt == 1 then
        data.container, data.panels, data._originalContainerId = rebuilt[1].container, rebuilt[1].panels, rebuilt[1]._originalContainerId
    else
        data.type, data.containers, data.bars, data.layouts = "containers", rebuilt, nil, nil
    end
    return data, report
end
