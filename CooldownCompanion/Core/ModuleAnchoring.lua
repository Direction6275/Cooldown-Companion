-- Panel selection belongs to each module/spec. Automatic eligibility is a
-- preference; explicit targets still obey structural and runtime constraints.
local _, ST = ...
local Addon = ST.Addon

local DEFAULT_AUTO = { mode = "auto" }
local DEFAULT_INDEPENDENT = { mode = "independent" }
local DEFAULT_PLAYER = { mode = "player" }
local MODULE_KINDS = { resources = true, castbar = true, player = true, target = true }

local function SpecEntry(entries, specId)
    return type(entries) == "table" and (entries[specId] or entries[tostring(specId)]) or nil
end

local function SettingsFor(self, kind)
    if kind == "resources" then return self:GetResourceBarSettings() end
    if kind == "castbar" then return self:GetCastBarSettings() end
    return self:GetFrameAnchoringSettings()
end

local function ValidMode(kind, mode)
    return MODULE_KINDS[kind] and (mode == "auto" or mode == "panel"
        or (mode == "independent" and (kind == "resources" or kind == "castbar"))
        or (mode == "player" and kind == "target"))
end

function Addon:GetModuleAttachment(kind, specId, settings)
    specId = tonumber(specId) or self._currentSpecId
    settings = settings or SettingsFor(self, kind)
    local owner = settings
    local record
    if kind == "resources" then
        owner = settings and SpecEntry(settings.layoutOrder, specId)
        record = owner and owner.attachment
    else
        if kind == "player" or kind == "target" then owner = settings and settings[kind] end
        record = owner and SpecEntry(owner.attachmentBySpec, specId)
    end
    if type(record) == "table" and ValidMode(kind, record.mode) then return record end
    if kind == "target" then return DEFAULT_PLAYER end
    if kind == "resources" or kind == "castbar" then
        local independent = owner and owner.independentAnchorEnabled
        if independent == nil then independent = settings and settings.independentAnchorEnabled end
        if independent == true then return DEFAULT_INDEPENDENT end
    end
    return DEFAULT_AUTO
end

function Addon:IsModuleAnchorIndependent(kind, specId, settings)
    return self:GetModuleAttachment(kind, specId, settings).mode == "independent"
end

function Addon:SetModuleAttachment(kind, mode, panelId, specId)
    if not ValidMode(kind, mode) then return false end
    specId = tonumber(specId) or self._currentSpecId
    if not specId then return false end
    local settings = SettingsFor(self, kind)
    if not settings then return false end
    local previous = self:GetModuleAttachment(kind, specId, settings)
    local record = { mode = mode, panelId = tonumber(panelId) or previous.panelId }
    if kind == "resources" then
        local layout = ST._RB.GetSpecLayoutOrder(settings, specId)
        if not layout then return false end
        layout.attachment = record
    else
        local owner = settings
        if kind == "player" or kind == "target" then
            settings[kind] = settings[kind] or {}
            owner = settings[kind]
        end
        owner.attachmentBySpec = owner.attachmentBySpec or {}
        owner.attachmentBySpec[tostring(specId)] = nil
        owner.attachmentBySpec[specId] = record
    end
    return true
end

function Addon:CanModuleAnchorToPanel(panelId)
    local group = self.db.profile.groups[panelId]
    if not group then return false, "missing" end
    if not group.parentContainerId or not self.db.profile.groupContainers[group.parentContainerId] then
        return false, "missing"
    end
    if not self:IsIconLikeDisplayMode(group.displayMode) then return false, "unsupported" end
    return self:CanGroupBeExternalAnchorTarget(panelId)
end

local function ResolvePanel(self, panelId, specId, configured)
    local result = { panelId = panelId, available = false, eligible = false }
    if not panelId then result.reason = "missing"; return result end
    local ok, reason = self:CanModuleAnchorToPanel(result.panelId)
    if not ok then result.reason = reason; return result end
    if not self:IsGroupVisibleToCurrentChar(result.panelId) then result.reason = "inaccessible"; return result end
    result.group = self.db.profile.groups[result.panelId]
    if not self:IsGroupActive(result.panelId, { group = result.group, specId = specId,
        checkCharVisibility = true, checkLoadConditions = true, configurationOnly = configured }) then
        result.reason = "inactive"; return result
    end
    result.eligible = true
    result.frame = self.groupFrames and self.groupFrames[result.panelId]
    result.available = not configured and result.frame ~= nil and result.frame:IsShown() == true
    result.reason = result.available and "ok" or "hidden"
    return result
end

function Addon:ResolveModulePanel(kind, specId, options)
    -- Editors inspect configured eligibility without consulting frame visibility.
    -- Runtime callers omit options and retain the shown-panel fallback policy.
    local configured = options and options.configured == true
    specId = tonumber(specId) or self._currentSpecId
    local attachment = self:GetModuleAttachment(kind, specId, options and options.settings)
    local selection = attachment.mode == "player" and self:GetModuleAttachment("player", specId) or attachment
    if not specId or selection.mode == "independent" then
        return { mode = attachment.mode, available = false, eligible = false,
            reason = not specId and "spec-loading" or "independent" }
    end
    local selectedPanelId = selection.mode == "panel" and tonumber(selection.panelId) or nil
    local result = ResolvePanel(self, selectedPanelId
        or (selection.mode == "auto" and self:GetFirstAvailableAnchorGroup(specId, options) or nil), specId, configured)
    if selection.mode == "panel" then
        local selectedReason, selectedEligible = result.reason, result.eligible
        if (configured and not result.eligible) or (not configured and not result.available) then
            -- Keep the preference untouched. All consumers use panelId as the
            -- effective destination, so stacking, navigation and previews agree.
            local fallbackId = self:GetFirstAvailableAnchorGroup(specId, { requireShown = not configured, configured = configured })
            result = ResolvePanel(self, fallbackId, specId, configured)
            result.fallback = true
        end
        result.selectedPanelId = selectedPanelId
        result.selectedReason = selectedReason
        result.selectedEligible = selectedEligible
    end
    if not result.panelId then result.reason = "no-automatic-panel" end
    result.mode = attachment.mode
    return result
end

function Addon:GetModuleAnchorPanelId(kind)
    local resolved = self:ResolveModulePanel(kind)
    return resolved.available and resolved.panelId or nil
end

function Addon:ModulesShareAnchorPanel(first, second)
    local a, b = self:ResolveModulePanel(first), self:ResolveModulePanel(second)
    return a.available and b.available and a.panelId == b.panelId
end

function Addon:GetModuleAnchorStatusText(result, kind)
    local reason = result.reason
    if reason == "ok" and (kind == "player" or kind == "target") and self.GetFrameAnchoringRuntimeDebugInfo then
        local runtime = self:GetFrameAnchoringRuntimeDebugInfo()
        if runtime.pendingCombatReevaluate then return "Position updates when combat ends." end
        if runtime.specId == self._currentSpecId and runtime[kind .. "PanelId"] == result.panelId then
            local failure = runtime[kind .. "Reason"]
            if failure == "provider-unavailable" then return "Unit frame is currently unavailable. Attachment resumes when it returns." end
            if failure == "anchor-dependency" then return "This attachment has an unsupported anchor dependency. Choose another panel." end
        end
    end
    if result.fallback then
        local unavailable = result.selectedReason == "missing" and "Selected panel is missing."
            or "Selected panel is unavailable."
        if result.available then
            return unavailable .. " Using Automatic: " .. (result.group.name or ("Panel " .. result.panelId)) .. "."
        end
        return unavailable .. " No available panel for Automatic anchoring."
    end
    if reason == "ok" or reason == "independent" then return nil end
    if reason == "spec-loading" then return "Specialization data loading..." end
    if reason == "no-automatic-panel" then return "No eligible panel for Automatic anchoring." end
    if reason == "missing" then
        return result.panelId and "Anchor panel is missing. Choose another panel." or "Choose an anchor panel."
    end
    if reason == "inaccessible" then return "Selected panel is not available to this character." end
    if reason == "inactive" or reason == "hidden" then return "Selected panel is currently unavailable. Attachment resumes when it returns." end
    return "Selected panel cannot host this attachment. Choose a supported icon panel."
end

-- Normalize only the record's shape. Temporary eligibility must never erase
-- a user's binding, and old anchorGroupId values are deliberately not read.
function Addon:VisitModuleAttachments(settings, kind, visit)
    if type(settings) ~= "table" then return end
    if kind == "resources" then
        for _, layout in pairs(type(settings.layoutOrder) == "table" and settings.layoutOrder or {}) do
            if type(layout) == "table" and type(layout.attachment) == "table" then visit(layout.attachment) end
        end
    else
        local owner = (kind == "player" or kind == "target") and settings[kind] or settings
        for _, record in pairs(type(owner) == "table" and type(owner.attachmentBySpec) == "table" and owner.attachmentBySpec or {}) do
            if type(record) == "table" then visit(record) end
        end
    end
end

function Addon:RemapModuleAttachmentPanels(settings, kind, panelMap)
    self:VisitModuleAttachments(settings, kind, function(record)
        local oldId = tonumber(record.panelId)
        record.panelId = oldId and panelMap and panelMap[oldId] or nil
    end)
end

function Addon:NormalizeModuleAttachments(settings, kind)
    self:VisitModuleAttachments(settings, kind, function(record)
        if not ValidMode(kind, record.mode) then record.mode = kind == "target" and "player" or "auto" end
        local id = tonumber(record.panelId)
        record.panelId = id and id > 0 and id == math.floor(id) and id or nil
    end)
end

function Addon:GetModuleAnchoringDebugInfo()
    local result = {}
    local runtime = self.GetFrameAnchoringRuntimeDebugInfo and self:GetFrameAnchoringRuntimeDebugInfo()
    for _, kind in ipairs({ "resources", "castbar", "player", "target" }) do
        local target = self:ResolveModulePanel(kind)
        local settings = SettingsFor(self, kind)
        result[kind] = { mode = target.mode, panelId = target.panelId,
            selectedPanelId = target.selectedPanelId, selectedReason = target.selectedReason,
            fallback = target.fallback == true, available = target.available, reason = target.reason,
            enabled = settings and settings.enabled == true }
        if runtime and (kind == "player" or kind == "target") then
            result[kind].applied = runtime[kind .. "Applied"]
            result[kind].bindingReason = runtime.pendingCombatReevaluate and "pending-combat" or runtime[kind .. "Reason"]
        end
    end
    return result
end
