-- Config destinations for existing singleton bars, never saved panel records.
local _, ST = ...
local Addon = ST.Addon
local CS = ST._configState

local function GetPlacement(kind)
    local settings = kind == "resources" and Addon:GetResourceBarSettings()
        or kind == "castbar" and Addon:GetCastBarSettings()
        or Addon:GetFrameAnchoringSettings()
    if not settings or settings.enabled ~= true then return "disabled" end
    local independent = kind == "resources" and Addon:IsResourceBarAnchorIndependent()
        or kind == "castbar" and settings.independentAnchorEnabled == true
    if independent then return "independent" end
    local panelId = Addon:GetFirstAvailableAnchorGroup()
    return panelId and "attached" or "unplaced", panelId
end

local function OpenWorkspace(kind)
    kind = kind or "resources"
    local _, panelId = GetPlacement(kind)
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

local function GetAttachmentOptions()
    return { attached = "Attached to Panel", independent = "Independent" },
        { "attached", "independent" }
end

local function GetAttachmentValue(kind)
    local independent = kind == "resources" and Addon:IsResourceBarAnchorIndependent()
        or kind == "castbar" and Addon:GetCastBarSettings().independentAnchorEnabled == true
    return independent and "independent" or "attached"
end

local function SetAttachment(kind, value)
    local independent = value == "independent"
    if not independent and value ~= "attached" then return false end
    local resources = Addon:GetResourceBarSettings()
    if kind == "resources" then
        local layout = Addon:GetSpecLayoutOrder()
        if not (resources and layout) then return false end
        layout.independentAnchorEnabled = independent
    elseif kind == "castbar" then
        Addon:GetCastBarSettings().independentAnchorEnabled = independent
    else
        return false
    end
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
    local anchorId = Addon:GetFirstAvailableAnchorGroup()
    local function AddItem(label, kind, selected)
        items[#items + 1] = { label = label, selected = selected, onClick = function()
            OpenWorkspace(kind)
            Addon:RefreshConfigPanel()
        end }
    end
    local _, resourcePanel = GetPlacement("resources")
    if resourcePanel == panelId then
        AddItem("Resources", "resources", CS.unifiedBarKind == "stack")
    elseif resourcePanel then
        local current = Addon.db.profile.groups[resourcePanel]
        AddItem("Resources (" .. (current.name or "Panel") .. ")", "resources", false)
    elseif anchorId and Addon:IsGroupAvailableForAnchoring(panelId) then
        AddItem("Resources", "resources", false)
    end
    local _, castPanel = GetPlacement("castbar")
    if castPanel == panelId then AddItem("Cast Bar", "castbar", CS.unifiedBarKind == "cast") end
    if anchorId == panelId then
        AddItem("Player Frame", "player", CS.unifiedBarKind == "player")
        AddItem("Target Frame", "target", CS.unifiedBarKind == "target")
    end
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
        OpenWorkspace(kind)
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
    if Addon:GetFirstAvailableAnchorGroup() then return end
    if kind == "resources" then
        local layout = Addon:GetSpecLayoutOrder()
        if layout then layout.independentAnchorEnabled = true end
    elseif kind == "castbar" then
        Addon:GetCastBarSettings().independentAnchorEnabled = true
    end
end
