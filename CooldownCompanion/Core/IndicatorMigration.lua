-- Pure conversion shared by profile activation and import. Never drops a rule.
local _, ST = ...
local I, Addon = ST.Indicator, ST.Addon
local M = {}
ST.IndicatorMigration = M

local function HasAuraClause(group)
    for _, entry in ipairs(group.buttons or {}) do
        if entry.addedAs == "aura" or entry.triggerCondition == "auraActive" then return true end
        for _, clause in ipairs(entry.triggerConditions or {}) do
            if clause.key == "auraActive" then return true end
        end
    end
end

local function Convert(group)
    local mode = group.displayMode
    if mode ~= "textures" and mode ~= "trigger" and mode ~= "text" then return end
    if mode == "text" then
        -- Token layout, per-run colors and measured text geometry have no exact
        -- standalone equivalent yet. Retain the editor instead of approximating.
        return "Text layout retained for exact appearance and behavior."
    end
    if mode == "trigger" and HasAuraClause(group) then
        return "Aura conditions retained; Blizzard controls aura displays."
    end
    local entry = group.buttons and group.buttons[1]
    if not entry then return "Empty legacy panel retained." end
    if mode == "trigger" then
        if entry.enabled == false then return "Disabled primary source retained." end
        for _, source in ipairs(group.buttons) do
            local clauses = Addon:GetTriggerConditionClauses(source)
            if source.enabled ~= false and #clauses == 0 then return "Unconfigured trigger retained." end
            for _, clause in ipairs(source.triggerConditions or clauses) do
                if not I.ConditionKeys[clause.key] then return "Unsupported condition retained." end
                if clause.key == "countTextActive" then return "Legacy count-presence behavior retained." end
            end
        end
    end
    if mode == "textures" and (#group.buttons ~= 1 or not Addon:IsTexturePanelAuraDisplayEnabled(group, entry)) then
        return "Legacy texture visibility and effects retained."
    end
    if mode == "textures" and (entry.auraTrackGroup or entry.auraTrackPet) then
        return "Legacy aura scope retained."
    end
    local legacy = CopyTable(group)
    group.displayMode = "indicator"
    group._indicatorLegacyReason = nil
    local settings = I.Initialize(group)
    settings.migratedFrom = mode
    if mode == "textures" then
        settings.tracking, settings.displayType = "aura", "texture"
        settings.signal = CopyTable(group.textureSettings or settings.signal)
        -- Texture panels ignore the old entry-enabled flag. Preserve that rule.
        entry.enabled = true
        entry.textureAuraDisplayEnabled = true
    else
        local previous = group.triggerSettings or {}
        settings.displayType = previous.displayType or "texture"
        for _, key in ipairs({"signal", "icon", "text", "effects", "soundAlerts"}) do
            if previous[key] then settings[key] = CopyTable(previous[key]) end
        end
        for _, source in ipairs(group.buttons or {}) do
            source.triggerConditions = CopyTable(Addon:GetTriggerConditionClauses(source))
        end
        if settings.displayType == "text" then
            settings.readouts.label = "custom"
            settings.readouts.customText = settings.text.value or ""
            settings.legacyTextMetrics = true
        end
    end
    group.textureSettings, group.triggerSettings = nil, nil
    I.Effects(group)
    return nil, legacy
end

function M.Apply(profile)
    if type(profile) ~= "table" then return {converted=0, retained=0, panels={}} end
    local report = {converted=0, retained=0, panels={}}
    for id, group in pairs(profile.groups or {}) do
        local mode = group.displayMode
        if mode == "indicator" then
            if not group.indicatorSettings or group.indicatorSettings.effectVersion ~= 1 then
                profile._indicatorEffectMigrationBackup = profile._indicatorEffectMigrationBackup or {}
                profile._indicatorEffectMigrationBackup[id] = profile._indicatorEffectMigrationBackup[id] or CopyTable(group)
            end
            I.Initialize(group)
            I.Effects(group)
            I.NormalizeSourceEnablement(group)
        elseif mode == "text" or mode == "textures" or mode == "trigger" then
            local reason, legacy = Convert(group)
            if legacy then
                profile._indicatorMigrationBackup = profile._indicatorMigrationBackup or {}
                profile._indicatorMigrationBackup[id] = profile._indicatorMigrationBackup[id] or legacy
                report.converted = report.converted + 1
            elseif reason then
                group._indicatorLegacyReason = reason
                report.retained = report.retained + 1
            end
            report.panels[#report.panels+1] = {id=id, name=group.name, from=mode,
                outcome=legacy and "converted" or "legacy", reason=reason}
        end
    end
    profile._indicatorMigrationVersion = 1
    return report
end

function M.ConvertImport(data)
    if type(data) ~= "table" then return data end
    local candidate = CopyTable(data)
    local function Visit(value)
        if type(value) ~= "table" then return end
        if type(value.buttons) == "table" and type(value.displayMode) == "string" then
            if value.displayMode == "indicator" then
                -- Old templates omitted source family. Do not invent one and
                -- silently select the wrong legacy store; apply reports it.
                if value.templateVersion then return end
                I.Initialize(value)
                I.Effects(value)
                I.NormalizeSourceEnablement(value)
                return
            end
            local reason = Convert(value)
            if reason then value._indicatorLegacyReason = reason end
            return
        end
        for key, child in pairs(value) do
            if key ~= "_indicatorMigrationBackup" and key ~= "_indicatorEffectMigrationBackup"
                and key ~= "_unifiedPanelBackup" then Visit(child) end
        end
    end
    Visit(candidate)
    return candidate
end

function Addon:RunIndicatorMigration()
    local profile = self.db and self.db.profile
    if not profile then return end
    local first = profile._indicatorMigrationVersion ~= 1
    local report = M.Apply(profile)
    if first and (report.converted > 0 or report.retained > 0) then
        self:Print(("Indicators: converted %d panels; preserved %d legacy panels. Legacy panels remain editable."):format(report.converted, report.retained))
    end
    return report
end
