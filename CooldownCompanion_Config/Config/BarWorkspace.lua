-- Config destinations for existing singleton bars, never saved panel records.
local _, ST = ...
local Addon = ST.Addon
local CS = ST._configState

local function GetPlacement(kind)
    local settings = kind == "resources" and Addon:GetResourceBarSettings()
        or kind == "castbar" and Addon:GetCastBarSettings()
        or Addon:GetFrameAnchoringSettings()
    if not settings or settings.enabled ~= true then return "disabled" end
    local target = Addon:ResolveModulePanel(kind)
    if target.mode == "independent" then return "independent", nil, target end
    return target.group and "attached" or "unplaced", target.group and target.panelId, target
end

local function OpenWorkspace(kind, opts)
    kind = kind or "resources"
    local _, panelId = GetPlacement(kind)
    -- Explicit module navigation restores Settings for attached bars too.
    -- A refresh may keep browsing only while a buttons workspace remains.
    if CS.spellbookPanelDocked
        and (not panelId or not (opts and opts.preserveSpellbook)) then
        CS.CloseSpellbookPanel()
    end
    if panelId then
        local panel = Addon.db.profile.groups[panelId]
        if CS.barsEntrySelected or CS.selectedGroup ~= panelId or CS.otherClassLibraryActive then
            ST._ClearConfigFinderText({ preservePrimarySelection = true })
            if ST._ResetOtherClassLibraryState then ST._ResetOtherClassLibraryState() end
            ST._SelectConfigPanel(panelId, { containerId = panel.parentContainerId })
        else
            ST._ClearConfigButtonSelection()
        end
        ST._ClearConfigBarsHomeSelection()
        CS.unifiedBarKind = kind == "resources" and "stack"
            or kind == "castbar" and "cast" or kind
        if kind ~= "resources" then CS.castFramesSelectedItem = kind end
        CS.unifiedRowScope = kind == "resources" and "primary" or "detail"
    else
        local switchingFrames = (kind == "player" or kind == "target")
            and (CS.barWorkspaceKind == "player" or CS.barWorkspaceKind == "target")
        if not CS.barsEntrySelected or (CS.barWorkspaceKind ~= kind and not switchingFrames) then
            ST._SelectConfigBarsEntry({ standalone = true, kind = kind })
            CS.standalonePanelsCollapsed = false
        else
            ST._ClearConfigBarsHomeSelection()
        end
        CS.barWorkspaceKind = kind
        if kind ~= "resources" then CS.castFramesSelectedItem = kind end
        CS.unifiedRowScope = kind == "resources" and "primary" or "detail"
    end
end

local function GetAttachmentOptions(kind)
    local list = { auto = "Automatic", panel = "Choose Panel" }
    local order = { "auto", "panel" }
    if kind == "target" then
        list.player = "Same as Player"
        table.insert(order, 1, "player")
    elseif kind ~= "player" then
        list.independent = "Independent"
        order[#order + 1] = "independent"
    end
    return list, order
end

local function GetAttachmentValue(kind)
    return Addon:GetModuleAttachment(kind).mode
end

local function SetAttachment(kind, value, panelId)
    if not Addon:SetModuleAttachment(kind, value, panelId) then return false end
    Addon:RefreshStableExternalAnchorCompactSuppression()
    Addon:EvaluateResourceBars()
    Addon:EvaluateCastBar()
    Addon:EvaluateFrameAnchoring()
    Addon:UpdateAnchorStacking()
    OpenWorkspace(kind)
    Addon:RefreshConfigPanel()
    return true
end

local function GetPanelWorkspaceChips()
    local items = {}
    local panelId = CS.selectedGroup
    if not panelId or CS.otherClassLibraryActive then return items end
    local function AddItem(label, kind, selected)
        items[#items + 1] = { label = label, selected = selected, onClick = function()
            OpenWorkspace(kind)
            Addon:RefreshConfigPanel()
        end }
    end
    local _, resourcePanel = GetPlacement("resources")
    if resourcePanel == panelId then
        AddItem("Resources", "resources", CS.unifiedBarKind == "stack")
    end
    local _, castPanel = GetPlacement("castbar")
    if castPanel == panelId then AddItem("Cast Bar", "castbar", CS.unifiedBarKind == "cast") end
    local _, playerPanel = GetPlacement("player")
    local _, targetPanel = GetPlacement("target")
    if playerPanel == panelId then AddItem("Player Frame", "player", CS.unifiedBarKind == "player") end
    if targetPanel == panelId then AddItem("Target Frame", "target", CS.unifiedBarKind == "target") end
    return items
end

ST._GetBarWorkspacePlacement = GetPlacement
ST._OpenBarWorkspace = OpenWorkspace
ST._GetBarAttachmentOptions = GetAttachmentOptions
ST._GetBarAttachmentValue = GetAttachmentValue
ST._SetBarAttachment = SetAttachment
ST._GetPanelWorkspaceChips = GetPanelWorkspaceChips

ST._NormalizeBarWorkspace = function()
    if CS.exportMode or CS.importMode or CS.talentPickerMode or CS.otherClassLibraryActive then return end
    if not CS.barsEntrySelected and not CS.selectedGroup then return end
    local kind = CS.barsEntrySelected and (CS.barWorkspaceKind or "resources")
        or CS.unifiedBarKind == "cast" and "castbar"
        or (CS.unifiedBarKind == "player" or CS.unifiedBarKind == "target") and CS.unifiedBarKind
        or CS.unifiedBarKind and "resources"
    if not kind then return end
    local _, panelId = GetPlacement(kind)
    if (CS.barsEntrySelected and panelId) or (not CS.barsEntrySelected and panelId ~= CS.selectedGroup) then
        local resource, spec = CS.selectedResourcePowerType, CS.resourceSettingsSpecID
        local custom, scope = CS.selectedCustomBarId, CS.unifiedRowScope
        local selectedKind = CS.unifiedBarKind
        local multi = {}
        for id in pairs(CS.selectedCustomBars) do multi[id] = true end
        OpenWorkspace(kind, { preserveSpellbook = true })
        if resource then
            ST._SelectConfigResource(resource, { specID = spec })
        elseif custom then
            ST._SelectConfigCustomBar(custom)
            for id in pairs(multi) do CS.selectedCustomBars[id] = true end
        end
        if not CS.barsEntrySelected and selectedKind then CS.unifiedBarKind = selectedKind end
        if resource or custom then CS.unifiedRowScope = scope end
    end
end

ST._PrepareBarWorkspaceEnable = function(kind)
    -- Keep an explicit missing selection repairable; only the legacy first-use
    -- Automatic mode chooses Independent when there is no available panel.
    if Addon:GetModuleAttachment(kind).mode ~= "auto" then return end
    if Addon:GetFirstAvailableAnchorGroup() then return end
    if kind == "resources" or kind == "castbar" then Addon:SetModuleAttachment(kind, "independent") end
end
