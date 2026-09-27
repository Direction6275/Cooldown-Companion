-- One-way retirement: old records are data for conversion, never runtime modes.
local _, ST = ...
local I, Addon = ST.Indicator, ST.Addon
local M = {}
ST.IndicatorMigration = M
local RETIRED = {text=true, textures=true, trigger=true}
local function CopyValue(value)
    return type(value) == 'table' and CopyTable(value) or value
end

-- Consume the old positional selector only at data ingress. Active Indicators
-- always keep the chosen source first, followed by additional conditions.
local function NormalizeSourceOrder(group, sourceIndex)
    local settings = I.Settings(group)
    local entries = group.buttons or {}
    sourceIndex = sourceIndex or settings.primaryEntry or 1
    if entries[sourceIndex] then
        if sourceIndex ~= 1 then table.insert(entries, 1, table.remove(entries, sourceIndex)) end
    elseif #entries > 0 then
        -- A stale old index cannot identify the lost source. Preserve the rows
        -- but leave the panel disabled for the owner to choose its source.
        group.enabled = false
    end
    settings.primaryEntry = nil
end

-- The retired override registry is frozen here, outside the active style lens.
local TEXT_SECTIONS = {
    textFont = {"textFont", "textFontSize", "textFontOutline"},
    textColors = {"textFontColor"}, textBackground = {"textBgColor"},
}
local function TextStyle(group, entry, defaults)
    local style = CopyTable(group.style or defaults or {})
    local overrides = entry and entry.styleOverrides or {}
    for section, keys in pairs(TEXT_SECTIONS) do
        if entry and entry.overrideSections and entry.overrideSections[section] then
            for _, key in ipairs(keys) do
                if overrides[key] ~= nil then style[key] = CopyValue(overrides[key]) end
            end
        end
    end
    return style
end

local function ConvertText(group, source, defaults)
    local settings, entry = I.Settings(group), group.buttons[1]
    local style = TextStyle(source, entry, defaults)
    local format = (entry and entry.textFormat) or style.textFormat or '{name}  {status}'
    local tokens = {}
    for token in format:gmatch('{([%a]+)}') do tokens[token:lower()] = true end
    if entry and entry.auraTracking and (tokens.aura or tokens.aurastacks) then
        settings.tracking = 'aura'
        entry.textureAuraDisplayEnabled = true
    end
    local r = settings.readouts
    r.label = tokens.name and 'name' or 'none'
    r.timer = tokens.time or tokens.status or tokens.aura or false
    r.count = (tokens.stacks or tokens.aurastacks or tokens.charges or tokens.maxcharges
        or tokens.missingcharges or tokens.zerocharges)
        and (settings.tracking == 'aura' and 'stacks' or entry and entry.type == 'spell' and 'charges' or 'item') or 'none'
    if not next(tokens) then
        r.label, r.customText = 'custom', format:gsub('{[^}]*}', ''):gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '')
    end
    settings.displayType = tokens.icon and not (r.timer or r.count ~= 'none' or tokens.name) and 'icon' or 'text'
    for _, key in ipairs({'textFont','textFontSize','textFontOutline','textFontColor','textBgColor'}) do
        if style[key] ~= nil then settings.text[key] = CopyValue(style[key]) end
    end
    settings.text.textFontSize = style.textFontSize or 12
    r.durationFormat = style.durationFormat or 'clock'
    settings.text.width, settings.text.height = 180, math.max(24, (settings.text.textFontSize or 12) * 2 + 8)
    r.labelAnchor, r.timerAnchor, r.countAnchor = 'TOP', 'BOTTOMLEFT', 'BOTTOMRIGHT'
    settings.sourceVisibility = true
    if entry then entry.textFormat = nil end
end

local function ConvertOne(source, entry, defaults, entryOrigins)
    local mode = source.displayMode
    local group = CopyTable(source)
    group.displayMode, group._indicatorLegacyReason, group.indicatorSettings = 'indicator', nil, nil
    if mode ~= 'trigger' then group.buttons = entry and {CopyTable(entry)} or {} end
    for index, row in ipairs(group.buttons or {}) do
        entryOrigins[row] = mode == 'trigger' and source.buttons[index] or entry
    end
    local settings = I.Initialize(group)
    settings.migratedFrom = mode
    local primary = group.buttons and group.buttons[1]
    if mode == 'trigger' then
        local previous = source.triggerSettings or {}
        settings.displayType = previous.displayType or 'texture'
        for _, key in ipairs({'signal','icon','text','effects','soundAlerts'}) do
            if previous[key] then settings[key] = CopyTable(previous[key]) end
        end
        local firstEnabled
        for index, row in ipairs(group.buttons or {}) do
            if row.enabled ~= false then firstEnabled = firstEnabled or index end
            local clauses = row.triggerConditions
            if type(clauses) ~= 'table' then
                clauses = row.triggerCondition and {{key=row.triggerCondition,
                    expected=row.triggerExpected, state=row.triggerState}} or Addon:GetTriggerConditionClauses(row)
            end
            row.triggerConditions = {}
            for _, clause in ipairs(clauses or {}) do
                local normalized = Addon:NormalizeTriggerConditionClause(row, clause)
                if not normalized or not I.ConditionKeys[normalized.key] then
                    normalized = CopyTable(clause)
                    normalized.key = clause.key or clause.conditionKey or clause.triggerCondition or 'unconfigured'
                    normalized.unavailable = true
                end
                row.triggerConditions[#row.triggerConditions + 1] = normalized
            end
            -- An explicitly empty old rule list never matched. Empty Indicator
            -- rules mean Always, so retain a nonmatching rule until it is edited.
            if #row.triggerConditions == 0 then row.triggerConditions[1] = {key='unconfigured',unavailable=true} end
        end
        NormalizeSourceOrder(group, firstEnabled or 1)
        if not firstEnabled and primary then group.enabled = false end
        if settings.displayType == 'text' then
            settings.readouts.label, settings.readouts.customText = 'custom', settings.text.value or ''
            settings.readouts.timer = false
            settings.text.textFontSize = previous.text and previous.text.textFontSize or 12
            settings.text.width, settings.text.height = 180, math.max(24, settings.text.textFontSize * 2 + 8)
        end
    else
        settings.sourceSounds = true
        settings.tracking = primary and primary.type == 'spell'
            and (primary.addedAs == 'aura' or (mode == 'textures' and primary.textureAuraDisplayEnabled == true))
            and 'aura' or 'conditions'
        if primary then
            if mode == 'textures' then
                primary.enabled = true
                -- These scopes were dormant on Texture panels. Do not revive them.
                primary.auraTrackGroup, primary.auraTrackPet = nil, nil
            end
            if settings.tracking == 'aura' then primary.textureAuraDisplayEnabled = true end
            primary.triggerConditions, primary.indicatorShowWhen = {}, 'always'
        end
        if mode == 'text' then
            ConvertText(group, source, defaults)
            settings.signal = CopyTable(source.anchor or settings.signal)
        else
            settings.displayType, settings.sourceVisibility = 'texture', true
            settings.signal = CopyTable(source.textureSettings or settings.signal)
            if settings.tracking ~= 'aura' then
                local stored = source.style and source.style.textureIndicators or {}
                local assigned = {}
                for _, section in ipairs({'proc','aura','ready','unusable'}) do
                    local effect = stored[section]
                    -- The old editor prevented duplicate enabled effects. Give
                    -- enabled settings priority over dormant copies of a type.
                    if effect and effect.effectType and effect.effectType ~= 'none'
                        and (not assigned[effect.effectType] or effect.enabled and not assigned[effect.effectType].enabled) then
                        local converted = CopyTable(effect)
                        converted.activation = section
                        settings.effects[effect.effectType] = converted
                        assigned[effect.effectType] = converted
                    end
                end
            end
        end
    end
    group.textureSettings, group.triggerSettings = nil, nil
    -- Interpret effects using the retired renderer's ownership, not the newly
    -- selected tracking family. Text never rendered textureIndicators.
    local effects, selection = {}, nil
    if mode == 'textures' and settings.tracking == 'aura' then
        effects, selection = I.ReadEffects(group)
    elseif mode ~= 'text' then
        effects = settings.effects
    end
    I.SetEffects(group, effects, selection)
    I.NormalizeSourceEnablement(group)
    return group
end

function M.ConvertPanel(source, defaults)
    if not RETIRED[source.displayMode] then
        local group = CopyTable(source)
        if ST.IsIndicatorGroup(group) then
            I.Initialize(group); NormalizeSourceOrder(group); I.Effects(group); I.NormalizeSourceEnablement(group)
            group.indicatorSettings.legacyTextMetrics = nil
        end
        return {group}
    end
    local result, entries, entryOrigins = {}, source.buttons or {}, {}
    local count = source.displayMode == 'text' and math.max(1, #entries) or 1
    local style = source.style or {}
    for index = 1, count do
        local group = ConvertOne(source, entries[index], defaults, entryOrigins)
        if count > 1 then
            group.name = (source.name or 'Indicator') .. ' - ' .. (entries[index].name or tostring(index))
            local signal = group.indicatorSettings.signal
            local vertical = (style.textOrientation or 'vertical') == 'vertical'
            local step = (vertical and group.indicatorSettings.text.height or group.indicatorSettings.text.width)
                + (style.buttonSpacing or 4)
            local key = vertical and 'y' or 'x'
            signal[key] = (signal[key] or 0) + (index - 1) * step * (vertical and -1 or 1)
            group.anchor = CopyTable(signal)
        end
        result[#result + 1] = group
    end
    return result, entryOrigins
end

function M.Apply(profile)
    local report = {converted=0, created=0, retained=0, panels={}}
    if type(profile) ~= 'table' then return report end
    local groups = profile.groups or {}
    local ids, nextId = {}, tonumber(profile.nextGroupId) or 1
    for id in pairs(groups) do
        ids[#ids + 1] = id
        nextId = math.max(nextId, (tonumber(id) or 0) + 1)
    end
    table.sort(ids, function(a,b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
    for _, id in ipairs(ids) do
        local group = groups[id]
        if RETIRED[group.displayMode] then
            local previousMode = group.displayMode
            local converted, entryOrigins = M.ConvertPanel(group, profile.globalStyle)
            profile._indicatorMigrationBackup = profile._indicatorMigrationBackup or {}
            profile._indicatorMigrationBackup[id] = profile._indicatorMigrationBackup[id] or CopyTable(group)
            -- Keep live references to saved entries stable on profile refresh.
            for _, candidate in ipairs(converted) do
                for index, row in ipairs(candidate.buttons or {}) do
                    local original = entryOrigins[row]
                    if original then
                        for key in pairs(original) do original[key] = nil end
                        for key, value in pairs(row) do original[key] = value end
                        candidate.buttons[index] = original
                    end
                end
            end
            for key in pairs(group) do group[key] = nil end
            for key, value in pairs(converted[1]) do group[key] = value end
            for index = 2, #converted do
                local child = converted[index]
                child.order = (group.order or 0) + (index - 1) / #converted
                groups[nextId], nextId = child, nextId + 1
                report.created = report.created + 1
            end
            report.converted = report.converted + 1
            report.panels[#report.panels + 1] = {id=id, name=group.name, from=previousMode, outcome='converted'}
        elseif ST.IsIndicatorGroup(group) then
            if not group.indicatorSettings or group.indicatorSettings.effectVersion ~= 1 then
                profile._indicatorEffectMigrationBackup = profile._indicatorEffectMigrationBackup or {}
                profile._indicatorEffectMigrationBackup[id] = profile._indicatorEffectMigrationBackup[id] or CopyTable(group)
            end
            I.Initialize(group)
            NormalizeSourceOrder(group)
            I.Effects(group)
            I.NormalizeSourceEnablement(group)
            group.indicatorSettings.legacyTextMetrics = nil
        end
    end
    profile.nextGroupId, profile._indicatorMigrationVersion = nextId, 2
    return report
end

-- Templates have no sources and capture presentation, never runtime tracking.
-- Preserve their existing scope coverage, including explicit nil resets.
function M.ApplyTemplates(store)
    if type(store) ~= 'table' or type(store.groups) ~= 'table' then return end
    for id, source in pairs(store.groups) do
        local version = source.templateVersion
        if RETIRED[source.displayMode] and (version == nil or version == 1 or version == 2 or version == 3 or version == 4) then
            store._indicatorMigrationBackup = store._indicatorMigrationBackup or {}
            store._indicatorMigrationBackup[id] = store._indicatorMigrationBackup[id] or CopyTable(source)
            local converted = M.ConvertPanel(source)[1]
            converted.buttons = {}
            converted.indicatorSettings = I.CapturePresentation(converted)
            local fields = CopyTable(source.capturedFields or {style={},group={},loadConditions={},section={}})
            if version == 2 then
                for _, key in ipairs(ST.PANEL_COPY_SCOPES.indicator.visibility.groupKeys) do fields.group[key] = true end
                for _, option in ipairs(ST.LOAD_CONDITION_OPTIONS) do fields.loadConditions[option.key] = true end
            end
            fields.style = fields.style.strataOrder and {strataOrder=true} or {}
            fields.section = {}
            fields.indicator = {appearance=true, effects=source.displayMode ~= 'text'}
            converted.capturedFields, converted.templateVersion = fields, 4
            store.groups[id] = converted
        end
    end
end

function M.ConvertImport(data)
    if type(data) ~= 'table' then return data end
    local candidate, nextId = CopyTable(data), 1
    local function FindIDs(value)
        if type(value) ~= 'table' then return end
        nextId = math.max(nextId, (tonumber(value._originalGroupId) or 0) + 1)
        for key, child in pairs(value) do
            if type(key) ~= 'string' or key:sub(1,1) ~= '_' then FindIDs(child) end
        end
    end
    FindIDs(candidate)
    local function Visit(value)
        if type(value) ~= 'table' then return end
        if ST.IsIndicatorGroup(value) then
            if not value.templateVersion then I.Initialize(value); NormalizeSourceOrder(value) end
            I.Effects(value)
            I.NormalizeSourceEnablement(value)
            if value.indicatorSettings then value.indicatorSettings.legacyTextMetrics = nil end
            return
        end
        if value.groups and not value.type then M.Apply(value); return end
        if type(value.panels) == 'table' then
            local panels = {}
            for _, panel in ipairs(value.panels) do
                for index, converted in ipairs(M.ConvertPanel(panel)) do
                    if index == 1 and RETIRED[panel.displayMode] then
                        converted._indicatorMigrationOriginal = CopyTable(panel)
                    end
                    if index > 1 then converted._originalGroupId, nextId = nextId, nextId + 1 end
                    converted.order = (panel.order or 0) + (index - 1) / math.max(1,#(panel.buttons or {}))
                    panels[#panels + 1] = converted
                end
            end
            value.panels = panels
        end
        for key, child in pairs(value) do
            if key ~= 'panels' and (type(key) ~= 'string' or key:sub(1,1) ~= '_') then Visit(child) end
        end
    end
    Visit(candidate)
    return candidate
end

function Addon:RunIndicatorMigration()
    local profile = self.db and self.db.profile
    if not profile then return end
    local report = M.Apply(profile)
    if report.converted > 0 then
        self:Print(('Indicators: converted %d panels; created %d additional displays. Text formatting and split layouts were simplified; originals are backed up.')
            :format(report.converted, report.created))
    end
    return report
end
