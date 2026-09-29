-- Shared bar appearance. Module adapters translate appearance only; tracking,
-- text visibility, placement and independent saved settings keep their owners.
local _, ST = ...
local Addon = ST.Addon
local defaults = ST._defaults.profile.globalStyle
local sections = {
    barTexture = { label = "Bar Texture", keys = { "barTexture", "barClassTextureBrightness" } },
    barDirection = { label = "Fill Direction", keys = { "barReverseFill" } },
    barSmoothing = { label = "Segmented Smoothing", keys = { "barSegmentedSmoothing" } },
    barNameTypography = { label = "Name Text Font", keys = { "barNameFont", "barNameFontSize", "barNameFontOutline", "barNameFontColor" } },
    barDurationTypography = { label = "Duration Text Font", keys = { "barDurationFont", "barDurationFontSize", "barDurationFontOutline", "barDurationFontColor" } },
    barValueTypography = { label = "Value Text Font", keys = { "barValueFont", "barValueFontSize", "barValueFontOutline", "barValueFontColor" } },
    barIconAppearance = { label = "Icon Appearance", keys = { "barIconReverse", "barIconOffset", "barIconSizeOverride", "barIconSize" } },
}
defaults.barSegmentedSmoothing = "on"
defaults.barClassTextureBrightness = 1.3
defaults.barBorderStyle = "pixel"
ST.ATTACHED_BAR_DEFAULTS.barBorderStyle = "pixel"
table.insert(ST.OVERRIDE_SECTIONS.borderSettings.keys, "barBorderStyle")
for _, suffix in ipairs({ "Font", "FontSize", "FontOutline", "FontColor" }) do
    defaults["barDuration" .. suffix] = defaults["cooldown" .. suffix]
    defaults["barValue" .. suffix] = defaults["charge" .. suffix]
end
local TEXT_SUFFIXES = { "Font", "FontSize", "FontOutline", "FontColor" }
local keySections = {}
for id, section in pairs(sections) do
    section.modes, section.defaults = { bars = true }, {}
    for _, key in ipairs(section.keys) do
        section.defaults[key] = defaults[key]
        keySections[key] = id
        ST.ATTACHED_BAR_DEFAULTS[key] = type(defaults[key]) == "table" and CopyTable(defaults[key]) or defaults[key]
    end
    ST.OVERRIDE_SECTIONS[id] = section
end
-- Give every value one override owner. The migration below transfers old
-- section ownership before any subsequent promote/revert operation.
for _, id in ipairs({ "barShape", "barNameText", "barIcon" }) do
    local keys = ST.OVERRIDE_SECTIONS[id].keys
    for i = #keys, 1, -1 do
        if keySections[keys[i]] then table.remove(keys, i) end
    end
end
ST.SHARED_BAR_STYLE_SECTIONS = { "barTexture", "barBgColor", "borderSettings", "barDirection",
    "barSmoothing", "barNameTypography", "barDurationTypography", "barValueTypography", "barIconAppearance", "iconZoom" }
for _, id in ipairs(ST.SHARED_BAR_STYLE_SECTIONS) do
    local found
    for _, existing in ipairs(ST.OVERRIDE_SECTION_ORDER) do if existing == id then found = true; break end end
    if not found then ST.OVERRIDE_SECTION_ORDER[#ST.OVERRIDE_SECTION_ORDER + 1] = id end
end
-- Fill direction is panel shape (PANEL_TEMPLATE_SHAPE_KEYS), never quick-copied.
for id in pairs(sections) do
    if id ~= "barDirection" then table.insert(ST.PANEL_COPY_SCOPES.bars.appearance.sections, id) end
end

local common = { barTexture = "barTexture", backgroundColor = "barBgColor", borderStyle = "barBorderStyle",
    borderColor = "borderColor", borderSize = "borderSize", borderRenderMode = "borderRenderMode" }
ST.MODULE_BAR_STYLE_MAPS = {
    resources = { segmentedSmoothing = "barSegmentedSmoothing", classBarBrightness = "barClassTextureBrightness" },
    castbar = { iconFlipSide = "barIconReverse", iconZoom = "iconZoom", iconSize = "barIconSize",
        iconSizeOverride = "barIconSizeOverride", iconGap = "barIconOffset" },
}
for _, map in pairs(ST.MODULE_BAR_STYLE_MAPS) do
    for key, value in pairs(common) do map[key] = value end
end
for _, suffix in ipairs({ "Font", "FontSize", "FontOutline", "FontColor" }) do
    ST.MODULE_BAR_STYLE_MAPS.resources["text" .. suffix] = "barValue" .. suffix
    ST.MODULE_BAR_STYLE_MAPS.resources["rechargeText" .. suffix] = "barDuration" .. suffix
    ST.MODULE_BAR_STYLE_MAPS.castbar["name" .. suffix] = "barName" .. suffix
    ST.MODULE_BAR_STYLE_MAPS.castbar["castTime" .. suffix] = "barDuration" .. suffix
end
for _, id in ipairs({ "barBgColor", "borderSettings", "iconZoom" }) do
    for _, key in ipairs(ST.OVERRIDE_SECTIONS[id].keys) do keySections[key] = id end
end
ST.BAR_STYLE_KEY_SECTIONS = keySections

function ST.CanModuleUseBarStyleSection(kind, id)
    if id == "barThickness" then return true end
    if kind == "resources" then
        return id == "barCharges" or id == "barTexture" or id == "barBgColor" or id == "borderSettings"
            or id == "barDirection" or id == "barSmoothing" or id == "barDurationTypography" or id == "barValueTypography"
    end
    return id == "barTexture" or id == "barBgColor" or id == "borderSettings"
        or id == "barNameTypography" or id == "barDurationTypography" or id == "barIconAppearance" or id == "iconZoom"
end

-- Read configuration only. The optional host is also used by the config canvas
-- to resolve the panel it is depicting, including off-spec previews.
function ST.ResolveModuleBarStyle(kind, settings, powerType, spec, host)
    settings = settings or {}
    -- Same fallback as the resource helpers: the cached spec, else the live one.
    spec = spec or (ST._RB and ST._RB.GetCurrentSpecID and ST._RB.GetCurrentSpecID()) or Addon._currentSpecId
    local layout = kind == "resources" and settings.layoutOrder
        and (settings.layoutOrder[spec] or settings.layoutOrder[tostring(spec)]) or nil
    local canonical = ST._RB and ST._RB.GetCanonicalPowerType and powerType
        and ST._RB.GetCanonicalPowerType(powerType) or powerType
    local object = kind == "resources" and layout and layout.resources and layout.resources[canonical] or nil
    if kind == "castbar" then object = settings end
    local panel = host
    if panel == nil then panel = ST.GetModuleGeometryPanel(kind, spec) end
    if panel == false then panel = nil end
    local base = panel and ST.GetAttachedBarStyle(panel) or nil
    local profile = kind == "resources" and settings.displayProfiles
        and (settings.displayProfiles[spec] or settings.displayProfiles[tostring(spec)]) or settings
    local style = {}
    for key, panelKey in pairs(ST.MODULE_BAR_STYLE_MAPS[kind]) do
        local value = base and base[panelKey]
        -- Resource text has no group baseline; the renderer reads only the
        -- resource's customization or its defaults (below).
        local resourceTextKey = kind == "resources" and (keySections[panelKey] == "barValueTypography"
            or keySections[panelKey] == "barDurationTypography")
        if value == nil and not resourceTextKey then value = profile and profile[key] end
        if value == nil and not resourceTextKey then value = settings[key] end
        if value ~= nil then style[panelKey] = value end
    end
    if kind == "resources" then
        style.barReverseFill = base and base.barReverseFill
        if style.barReverseFill == nil then
            style.barReverseFill = ((layout and layout.orientation) or settings.orientation) == "vertical"
                and ((layout and layout.verticalFillDirection) or settings.verticalFillDirection) == "top_to_bottom"
        end
    end
    -- An independent resource draws untouched text with the resource text
    -- defaults, and its recharge text falls back to the value text. Mirror
    -- that here so editors show, and Customize seeds, what is drawn.
    local resourceText = kind == "resources" and not base and ST._RB
    if resourceText then
        for suffix, default in pairs(resourceText.DEFAULT_RESOURCE_TEXT_STYLE or {}) do
            if style["barValue" .. suffix] == nil then style["barValue" .. suffix] = default end
        end
    end
    for key, id in pairs(keySections) do
        if style[key] == nil and not (resourceText and id == "barDurationTypography") then
            style[key] = (base or ST.ATTACHED_BAR_DEFAULTS)[key]
        end
        if (panel or kind == "resources") and object and object.overrideSections and object.overrideSections[id] and object.styleOverrides then
            local value = rawget(object.styleOverrides, key)
            if value ~= nil then style[key] = value end
        end
    end
    if resourceText then
        for _, suffix in ipairs(TEXT_SUFFIXES) do
            if style["barDuration" .. suffix] == nil then style["barDuration" .. suffix] = style["barValue" .. suffix] end
        end
    end
    -- None is represented by zero in the common border controls. Special
    -- resource/cast artwork remains an explicit local choice.
    style.borderStyle = style.barBorderStyle or "pixel"
    return style, panel, object
end

function ST.ApplyModuleBarStyle(kind, target, settings, powerType, spec, host, appearance)
    local style, panel, object
    if appearance then
        -- Canvas builds carry the depicted panel's resolved appearance through
        -- all painters instead of consulting the live attachment again.
        style, panel, object = appearance.style, appearance.panel, appearance.object
    else
        style, panel, object = ST.ResolveModuleBarStyle(kind, settings, powerType, spec, host)
    end
    local owns = (panel or kind == "resources") and object and object.overrideSections or {}
    for key, panelKey in pairs(ST.MODULE_BAR_STYLE_MAPS[kind]) do
        -- Independent values remain local unless this individual bar is customized.
        if panel or owns[keySections[panelKey]] then target[key] = style[panelKey] end
    end
    if panel or owns.borderSettings then target.borderStyle = style.borderStyle end
    return target
end

function ST.ResolveCastBarStyle(settings, host)
    local resolved = {}
    for key, value in pairs(settings or {}) do resolved[key] = value end
    return ST.ApplyModuleBarStyle("castbar", resolved, settings, nil, nil, host)
end

-- Typography is shared by purpose; visibility, positions and conditional
-- colors retain their independent settings and override sections. The aura
-- timer color is one of those conditional colors: it keeps auraTextFontColor
-- (and its cyan fallback) so aura timers stay distinct from cooldown timers.
local SHARED_TYPOGRAPHY_ROLES = {
    { "barDuration", "cooldown", true },
    { "barDuration", "auraText", false },
    { "barValue", "charge", true },
    { "barValue", "auraStack", true },
}
function ST.ApplySharedBarTypography(style)
    for _, role in ipairs(SHARED_TYPOGRAPHY_ROLES) do
        for _, suffix in ipairs({ "Font", "FontSize", "FontOutline", "FontColor" }) do
            if role[3] or suffix ~= "FontColor" then
                local key = role[2] .. suffix
                if style[role[1] .. suffix] ~= nil then style[key] = style[role[1] .. suffix] end
            end
        end
    end
    if style.barBorderStyle == "none" then
        style.borderSize, style.borderRenderMode = 0, ST.BORDER_RENDER_MODE_CUSTOM or "custom"
    end
    return style
end
ST.ApplySharedBarTypography(ST.ATTACHED_BAR_DEFAULTS)

-- Enqueue on the panel's existing synchronous attachment transaction. Module
-- apply owns the style snapshots read by live updates and config previews.
function ST.RefreshPanelBarAppearance(groupId, scope)
    if scope and (scope.entry or scope.presentation ~= "bars") then return end
    local group = Addon.db.profile.groups[groupId]
    for kind, feature in pairs({ resources = "resourceBars", castbar = "castBar" }) do
        if group and ST.GetModuleGeometryPanel(kind) == group then
            Addon:RefreshBarsAndFramesRuntimeFeature(feature, "panel-bar-style", true)
        end
    end
end

-- Per-resource text typography has one owner: the resource's slot
-- customization in each spec. Saved per-resource values (class-wide, with
-- per-spec overrides) move there once, so they survive attaching to a panel
-- and Revert returns to the inherited style.
local RESOURCE_TEXT_ROLES = { { "text", "barValue", "barValueTypography" },
    { "rechargeText", "barDuration", "barDurationTypography" } }

-- Spec layouts belong to RB.GetSpecLayoutOrder, so a spec first created by a
-- migration matches one created by a visit (including its cast bar slot).
local function MigrationSpecLayout(settings, spec)
    local layout = settings.layoutOrder and (settings.layoutOrder[spec] or settings.layoutOrder[tostring(spec)])
    if layout then return layout end
    if ST._RB and ST._RB.GetSpecLayoutOrder then return ST._RB.GetSpecLayoutOrder(settings, spec) end
    settings.layoutOrder = settings.layoutOrder or {}
    settings.layoutOrder[spec] = {}
    return settings.layoutOrder[spec]
end

-- Returns false, changing nothing, when the class's specs are unknown: the
-- saved values are deleted only after they reach every spec.
local function MoveResourceTextToCustomizations(settings, class)
    local specs = {}
    if ST._GetResourceBarClassSpecInfo then
        local classSpecs = ST._GetResourceBarClassSpecInfo(class)
        if not classSpecs then return false end
        for spec in pairs(classSpecs) do specs[tonumber(spec) or spec] = true end
    end
    for spec in pairs(settings.layoutOrder or {}) do specs[tonumber(spec) or spec] = true end
    for spec in pairs(settings.displayProfiles or {}) do specs[tonumber(spec) or spec] = true end
    local buckets = {}
    for powerType, resource in pairs(settings.resources or {}) do
        if type(resource) == "table" then
            powerType = tonumber(powerType) or powerType
            local canonical = ST._RB and ST._RB.GetCanonicalPowerType and ST._RB.GetCanonicalPowerType(powerType) or powerType
            buckets[#buckets + 1] = { powerType = powerType, canonical = canonical, resource = resource }
            for spec in pairs(resource.specOverrides or {}) do specs[tonumber(spec) or spec] = true end
        end
    end
    -- A proxied pair shares its canonical half's slot, which holds one style;
    -- the canonical half's own values win it deterministically.
    table.sort(buckets, function(a, b)
        local aOwns, bOwns = a.powerType == a.canonical, b.powerType == b.canonical
        if aOwns ~= bOwns then return aOwns end
        return tostring(a.powerType) < tostring(b.powerType)
    end)
    for _, bucket in ipairs(buckets) do
        local resource = bucket.resource
        for spec in pairs(specs) do
            local specResource = resource.specOverrides
                and (resource.specOverrides[spec] or resource.specOverrides[tostring(spec)])
            for _, role in ipairs(RESOURCE_TEXT_ROLES) do
                local values
                for _, suffix in ipairs(TEXT_SUFFIXES) do
                    local value = specResource and specResource[role[1] .. suffix]
                    if value == nil then value = resource[role[1] .. suffix] end
                    if value ~= nil then
                        values = values or {}
                        values[role[2] .. suffix] = type(value) == "table" and CopyTable(value) or value
                    end
                end
                if values then
                    local layout = MigrationSpecLayout(settings, spec)
                    layout.resources = layout.resources or {}
                    local canonical = bucket.canonical
                    local slot = layout.resources[canonical] or layout.resources[tostring(canonical)] or {}
                    layout.resources[canonical], layout.resources[tostring(canonical)] = slot, nil
                    -- An existing customization is newer than the saved value.
                    if not (slot.overrideSections and slot.overrideSections[role[3]]) then
                        slot.overrideSections, slot.styleOverrides = slot.overrideSections or {}, slot.styleOverrides or {}
                        slot.overrideSections[role[3]] = true
                        for key, value in pairs(values) do slot.styleOverrides[key] = value end
                    end
                end
            end
        end
    end
    for _, bucket in ipairs(buckets) do
        local resource = bucket.resource
        for _, role in ipairs(RESOURCE_TEXT_ROLES) do
            for _, suffix in ipairs(TEXT_SUFFIXES) do
                resource[role[1] .. suffix] = nil
                for _, specResource in pairs(resource.specOverrides or {}) do
                    if type(specResource) == "table" then specResource[role[1] .. suffix] = nil end
                end
            end
        end
        -- Prune emptied spec tables, as the per-spec writer does.
        for spec, specResource in pairs(resource.specOverrides or {}) do
            if type(specResource) == "table" and not next(specResource) then resource.specOverrides[spec] = nil end
        end
    end
    return true
end

function ST.MigrateSharedBarStyle(profile)
    if not profile then return end
    for _, group in pairs(profile.groups or {}) do
        if group._sharedBarStyleVersion ~= 1 then
            local style = group.attachedBarStyle or ((group.displayMode == "bars") and group.style)
            if style then
                local duration = ST.IsAuraPanelGroup(group) and "auraText" or "cooldown"
                local value = ST.IsAuraPanelGroup(group) and "auraStack" or "charge"
                for _, suffix in ipairs({ "Font", "FontSize", "FontOutline", "FontColor" }) do
                    if style["barDuration" .. suffix] == nil then style["barDuration" .. suffix] = style[duration .. suffix] end
                    if style["barValue" .. suffix] == nil then style["barValue" .. suffix] = style[value .. suffix] end
                end
            end
            for _, entry in ipairs(group.buttons or {}) do
                local owned, overrides = entry.overrideSections, entry.styleOverrides
                if owned and overrides then
                    for oldId, targets in pairs({ barShape = {"barTexture", "barDirection"},
                        barNameText = {"barNameTypography"}, barIcon = {"barIconAppearance"} }) do
                        if owned[oldId] then
                            for _, id in ipairs(targets) do
                                for _, key in ipairs(sections[id].keys) do
                                    if rawget(overrides, key) ~= nil then owned[id] = true; break end
                                end
                            end
                        end
                    end
                    if ST.GetEntryPresentation(group, entry) == "bars" then
                        local auraOnly = entry.addedAs == "aura" or ST.IsAuraPanelGroup(group)
                        for _, role in ipairs({
                            { auraOnly and "auraText" or "cooldownText", auraOnly and "auraText" or "cooldown", "barDurationTypography", "barDuration" },
                            { auraOnly and "auraStackText" or "chargeText", auraOnly and "auraStack" or "charge", "barValueTypography", "barValue" },
                        }) do
                            if owned[role[1]] and not owned[role[3]] then
                                for _, suffix in ipairs({"Font", "FontSize", "FontOutline", "FontColor"}) do
                                    local value = rawget(overrides, role[2] .. suffix)
                                    if value ~= nil then
                                        overrides[role[4] .. suffix] = type(value) == "table" and CopyTable(value) or value
                                        owned[role[3]] = true
                                    end
                                end
                            end
                        end
                    end
                end
                -- A saved value becomes a customization only when it differs
                -- from what the entry inherits. Conversions write the default
                -- explicitly, and that must keep following the panel.
                local smoothing = entry.auraBar and entry.auraBar.segmentedSmoothing
                if smoothing ~= nil then
                    smoothing = ST.NormalizeSegmentedSmoothing(smoothing)
                    local base = ST.GetEntryBaseStyle(group, entry)
                    if smoothing ~= ST.NormalizeSegmentedSmoothing(base and base.barSegmentedSmoothing) then
                        entry.overrideSections, entry.styleOverrides = owned or {}, overrides or {}
                        entry.overrideSections.barSmoothing = true
                        entry.styleOverrides.barSegmentedSmoothing = smoothing
                    end
                    entry.auraBar.segmentedSmoothing = nil
                end
            end
            group._sharedBarStyleVersion = 1
        end
    end
    -- Preserve explicitly selected module artwork as a visible customization.
    for _, settings in pairs(profile.castBarByChar or {}) do
        local version = tonumber(settings._sharedBarStyleVersion) or 0
        if version < 1 then
            if rawget(settings, "iconSizeOverride") == nil then settings.iconSizeOverride = settings.iconOffset == true end
            if settings.borderStyle == "blizzard" and not (settings.overrideSections and settings.overrideSections.borderSettings) then
                settings.overrideSections, settings.styleOverrides = settings.overrideSections or {}, settings.styleOverrides or {}
                settings.overrideSections.borderSettings = true
                for localKey, key in pairs(common) do
                    if keySections[key] == "borderSettings" then
                        local value = settings[localKey]
                        settings.styleOverrides[key] = type(value) == "table" and CopyTable(value) or value
                    end
                end
            end
        end
        if version < 2 then
            -- A detached icon's saved size stays with it while attached. The
            -- customization is parked while the cast bar is independent.
            if settings.iconOffset == true and not (settings.overrideSections and settings.overrideSections.barIconAppearance) then
                settings.overrideSections, settings.styleOverrides = settings.overrideSections or {}, settings.styleOverrides or {}
                settings.overrideSections.barIconAppearance = true
                settings.styleOverrides.barIconSizeOverride = true
                settings.styleOverrides.barIconSize = tonumber(settings.iconSize) or 16
            end
            settings._sharedBarStyleVersion = 2
        end
    end
    for class, settings in pairs(profile.resourceBarsByClass or {}) do
        local version = tonumber(settings._sharedBarStyleVersion) or 0
        if version < 1 then
            -- Saved resource and placement tables contain customizations only.
            -- Include the class catalog and unvisited specs before stamping the
            -- migration, so default bars preserve their selected class artwork.
            local specs = {}
            local classSpecs = ST._GetResourceBarClassSpecInfo and ST._GetResourceBarClassSpecInfo(class)
            for spec in pairs(classSpecs or {}) do specs[tonumber(spec) or spec] = true end
            for spec in pairs(settings.layoutOrder or {}) do specs[tonumber(spec) or spec] = true end
            for spec in pairs(settings.displayProfiles or {}) do specs[tonumber(spec) or spec] = true end
            local classID = ST._GetClassIDFromResourceBarClassKey and ST._GetClassIDFromResourceBarClassKey(class)
            for spec in pairs(specs) do
                local display = settings.displayProfiles and (settings.displayProfiles[spec] or settings.displayProfiles[tostring(spec)]) or settings
                if (display.barTexture or settings.barTexture) == "blizzard_class" then
                    local layout = settings.layoutOrder and (settings.layoutOrder[spec] or settings.layoutOrder[tostring(spec)])
                    local catalog = ST._RB and ((ST._RB.SPEC_RESOURCES_CONFIG or {})[spec]
                        or (ST._RB.CLASS_RESOURCES_CONFIG or {})[classID]) or {}
                    local powerTypes = {}
                    for _, powerType in ipairs(catalog) do powerTypes[powerType] = true end
                    for powerType in pairs(settings.resources or {}) do
                        powerTypes[tonumber(powerType) or powerType] = true
                    end
                    for powerType in pairs(layout and layout.resources or {}) do
                        powerTypes[tonumber(powerType) or powerType] = true
                    end
                    for powerType in pairs(powerTypes) do
                        if ST.POWER_ATLAS_TYPES and ST.POWER_ATLAS_TYPES[powerType] then
                            layout = layout or MigrationSpecLayout(settings, spec)
                            layout.resources = layout.resources or {}
                            local slot = layout.resources[powerType] or layout.resources[tostring(powerType)] or {}
                            layout.resources[powerType] = slot
                            layout.resources[tostring(powerType)] = nil
                            if not (slot.overrideSections and slot.overrideSections.barTexture) then
                                slot.overrideSections, slot.styleOverrides = slot.overrideSections or {}, slot.styleOverrides or {}
                                slot.overrideSections.barTexture = true
                                slot.styleOverrides.barTexture = "blizzard_class"
                                slot.styleOverrides.barClassTextureBrightness = display.classBarBrightness or settings.classBarBrightness or 1.3
                            end
                        end
                    end
                end
            end
            settings._sharedBarStyleVersion = 1
        end
        -- Left at 1 when incomplete, so the next login retries only the move.
        if version < 2 and MoveResourceTextToCustomizations(settings, class) then
            settings._sharedBarStyleVersion = 2
        end
    end
end

function ST.MigrateSharedBarStyleTemplates(store)
    for _, template in pairs(store and store.groups or {}) do
        local scope = template.attachedBarStyle and "attachedBarStyle" or template.displayMode == "bars" and "style"
        local fields = scope and template.capturedFields and template.capturedFields[scope]
        local style = scope and template[scope]
        if (template.templateVersion == 3 or template.templateVersion == 4) and fields and style then
            if fields.borderSize and not fields.barBorderStyle then
                fields.barBorderStyle, style.barBorderStyle = true, "pixel"
            end
            local auraOnly = ST.IsAuraPanelGroup(template)
            for _, role in ipairs({{auraOnly and "auraText" or "cooldown", "barDuration"}, {auraOnly and "auraStack" or "charge", "barValue"}}) do
                for _, suffix in ipairs({"Font", "FontSize", "FontOutline", "FontColor"}) do
                    local oldKey, key = role[1] .. suffix, role[2] .. suffix
                    if fields[oldKey] and not fields[key] then
                        local value = style[oldKey]
                        if value == nil then value = defaults[oldKey] end
                        style[key] = type(value) == "table" and CopyTable(value) or value
                        fields[key] = true
                    end
                end
            end
        end
    end
end
