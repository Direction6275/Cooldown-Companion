--[[
    CooldownCompanion - Core/AuraTexturesDisplay.lua
    Aura texture host creation, standalone display rendering, and refresh flow.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AT = ST._AT

local CreateFrame = CreateFrame
local UIParent = UIParent
local ipairs = ipairs
local math_floor = math.floor
local math_max = math.max
local math_pi = math.pi
local pairs = pairs
local string_find = string.find
local string_trim = strtrim
local tostring = tostring
local tonumber = tonumber
local type = type

local DEFAULT_TEXTURE_SIZE = AT.DEFAULT_TEXTURE_SIZE
local UI_PARENT_NAME = AT.UI_PARENT_NAME
local CopyColor = AT.CopyColor
local Clamp = AT.Clamp
local NormalizeAnchorPoint = AT.NormalizeAnchorPoint
local NormalizeAuraTextureSettings = AT.NormalizeAuraTextureSettings
local ResolveGroup = AT.ResolveGroup
local LayoutTexturePieces = AT.LayoutTexturePieces
local SetTextureIndicatorBaseVisuals = AT.SetTextureIndicatorBaseVisuals
local StopAllTextureIndicatorEffects = AT.StopAllTextureIndicatorEffects
local ApplyTextureIndicatorEffects = AT.ApplyTextureIndicatorEffects
local DoesTriggerPanelMatch = AT.DoesTriggerPanelMatch

local NUDGE_BTN_SIZE = 12
local NUDGE_GAP = 2
local NUDGE_REPEAT_DELAY = 0.5
local NUDGE_REPEAT_INTERVAL = 0.05

local function CreateAuraTextureOutline(host)
    local fill = host:CreateTexture(nil, "OVERLAY")
    fill:SetPoint("TOPLEFT", host, "TOPLEFT", -4, 4)
    fill:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 4, -4)
    fill:SetColorTexture(0.05, 0.35, 0.5, 0.12)
    fill:Hide()

    local edges = {}
    local edgeSpecs = {
        { point1 = "TOPLEFT", point2 = "TOPRIGHT", x1 = -4, y1 = 4, x2 = 4, y2 = 4, width = 1, height = nil },
        { point1 = "BOTTOMLEFT", point2 = "BOTTOMRIGHT", x1 = -4, y1 = -4, x2 = 4, y2 = -4, width = 1, height = nil },
        { point1 = "TOPLEFT", point2 = "BOTTOMLEFT", x1 = -4, y1 = 4, x2 = -4, y2 = -4, width = nil, height = 1 },
        { point1 = "TOPRIGHT", point2 = "BOTTOMRIGHT", x1 = 4, y1 = 4, x2 = 4, y2 = -4, width = nil, height = 1 },
    }

    for index, spec in ipairs(edgeSpecs) do
        local edge = host:CreateTexture(nil, "OVERLAY")
        edge:SetColorTexture(0.2, 0.8, 1, 0.95)
        edge:SetPoint(spec.point1, host, spec.point1, spec.x1, spec.y1)
        edge:SetPoint(spec.point2, host, spec.point2, spec.x2, spec.y2)
        if spec.width then
            edge:SetHeight(spec.width)
        end
        if spec.height then
            edge:SetWidth(spec.height)
        end
        edge:Hide()
        edges[index] = edge
    end

    host.auraTextureOutlineFill = fill
    host.auraTextureOutlineEdges = edges
end

local function SetAuraTextureOutlineShown(host, shown)
    if not host.auraTextureOutlineFill then
        CreateAuraTextureOutline(host)
    end

    host.auraTextureOutlineFill:SetShown(shown)
    for _, edge in ipairs(host.auraTextureOutlineEdges or {}) do
        edge:SetShown(shown)
    end
end

local function UpdateTextureHostCoordLabel(host, x, y)
    if host and host.coordLabel and host.coordLabel.text then
        host.coordLabel.text:SetText(("x:%.1f, y:%.1f"):format(x or 0, y or 0))
    end
end

local function GetAnchorOffset(point, width, height)
    if point == "TOPLEFT" then return -(width or 0) / 2, (height or 0) / 2 end
    if point == "TOP" then return 0, (height or 0) / 2 end
    if point == "TOPRIGHT" then return (width or 0) / 2, (height or 0) / 2 end
    if point == "LEFT" then return -(width or 0) / 2, 0 end
    if point == "CENTER" then return 0, 0 end
    if point == "RIGHT" then return (width or 0) / 2, 0 end
    if point == "BOTTOMLEFT" then return -(width or 0) / 2, -(height or 0) / 2 end
    if point == "BOTTOM" then return 0, -(height or 0) / 2 end
    if point == "BOTTOMRIGHT" then return (width or 0) / 2, -(height or 0) / 2 end
    return 0, 0
end

local function GetGroupedPreviewContainerFrame(group)
    if not (group and group.parentContainerId) then
        return nil
    end
    if not (CooldownCompanion.IsContainerUnlockPreviewActive and CooldownCompanion:IsContainerUnlockPreviewActive(group.parentContainerId)) then
        return nil
    end
    return CooldownCompanion.containerFrames and CooldownCompanion.containerFrames[group.parentContainerId] or nil
end

local function GetStandaloneScreenAnchorPoint(settings)
    local point = settings and settings.point or "CENTER"
    local relativePoint = settings and settings.relativePoint or "CENTER"
    local x = tonumber(settings and settings.x) or 0
    local y = tonumber(settings and settings.y) or 0
    local uiCenterX, uiCenterY = UIParent:GetCenter()
    local uiWidth, uiHeight = UIParent:GetSize()
    if not (uiCenterX and uiCenterY and uiWidth and uiHeight) then
        return nil, nil, point, relativePoint
    end

    local relOffsetX, relOffsetY = GetAnchorOffset(relativePoint, uiWidth, uiHeight)
    return uiCenterX + relOffsetX + x, uiCenterY + relOffsetY + y, point, relativePoint
end

local function SaveGroupedStandalonePreviewSettings(host, group, settings)
    local containerFrame = GetGroupedPreviewContainerFrame(group)
    if not (host and containerFrame and settings and host.GetPoint) then
        return false
    end

    local containerX, containerY = containerFrame:GetCenter()
    local uiCenterX, uiCenterY = UIParent:GetCenter()
    local uiWidth, uiHeight = UIParent:GetSize()
    local point, relativeFrame, _, x, y = host:GetPoint(1)
    if not (containerX and containerY and uiCenterX and uiCenterY and uiWidth and uiHeight) then
        return false
    end

    if relativeFrame ~= containerFrame and not host._wrapperManaged then
        return false
    end

    local relativePoint = settings.relativePoint or "CENTER"
    local refOffsetX, refOffsetY = GetAnchorOffset(relativePoint, uiWidth, uiHeight)
    local screenAnchorX = containerX + (x or 0)
    local screenAnchorY = containerY + (y or 0)

    settings.point = NormalizeAnchorPoint(point or settings.point or "CENTER")
    settings.relativePoint = NormalizeAnchorPoint(relativePoint)
    settings.relativeTo = UI_PARENT_NAME
    settings.x = math_floor(((screenAnchorX - (uiCenterX + refOffsetX)) * 10) + 0.5) / 10
    settings.y = math_floor(((screenAnchorY - (uiCenterY + refOffsetY)) * 10) + 0.5) / 10
    return true
end

local function SaveTextureHostPosition(host)
    if not host then
        return
    end

    local owner = host._ownerButton
    local group = owner and owner._groupId and ResolveGroup(owner._groupId) or nil
    local settings
    local requiresConfiguredTexture = false
    if group and CooldownCompanion:IsTriggerPanelGroup(group) then
        settings = CooldownCompanion:GetTriggerPanelSignalSettings(group)
    else
        settings = group and CooldownCompanion:GetTexturePanelSettings(group)
        requiresConfiguredTexture = true
    end
    if not settings then
        return
    end
    if requiresConfiguredTexture and not settings.sourceType then
        return
    end

    if SaveGroupedStandalonePreviewSettings(host, group, settings) then
        UpdateTextureHostCoordLabel(host, settings.x, settings.y)
        CooldownCompanion:UpdateAuraTextureVisual(owner)
        if ST._configState and ST._configState.configFrame and ST._configState.configFrame.frame and ST._configState.configFrame.frame:IsShown() then
            CooldownCompanion:RefreshConfigPanel()
        end
        return
    end

    local point, _, relPoint, x, y = host:GetPoint(1)
    settings.point = NormalizeAnchorPoint(point)
    settings.relativePoint = NormalizeAnchorPoint(relPoint)
    settings.relativeTo = UI_PARENT_NAME
    settings.x = math_floor(((x or 0) * 10) + 0.5) / 10
    settings.y = math_floor(((y or 0) * 10) + 0.5) / 10

    UpdateTextureHostCoordLabel(host, settings.x, settings.y)
    CooldownCompanion:UpdateAuraTextureVisual(owner)
    if ST._configState and ST._configState.configFrame and ST._configState.configFrame.frame and ST._configState.configFrame.frame:IsShown() then
        CooldownCompanion:RefreshConfigPanel()
    end
end

local function EnsureAuraTextureNudger(host)
    if host.nudger then
        return
    end

    local nudger = CreateFrame("Frame", nil, host.dragHandle, "BackdropTemplate")
    nudger:SetSize(NUDGE_BTN_SIZE * 2 + NUDGE_GAP, NUDGE_BTN_SIZE * 2 + NUDGE_GAP)
    nudger:SetPoint("BOTTOM", host.dragHandle, "TOP", 0, 2)
    nudger:SetFrameStrata(host.dragHandle:GetFrameStrata())
    nudger:SetFrameLevel(host.dragHandle:GetFrameLevel() + 5)
    nudger:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    nudger:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    ST.CreatePixelBorders(nudger)
    nudger.buttons = {}

    local directions = {
        { atlas = "common-dropdown-icon-back", rotation = -math_pi / 2, anchor = "BOTTOM", dx =  0, dy =  1, ox = 0,         oy = NUDGE_GAP },
        { atlas = "common-dropdown-icon-next", rotation = -math_pi / 2, anchor = "TOP",    dx =  0, dy = -1, ox = 0,         oy = -NUDGE_GAP },
        { atlas = "common-dropdown-icon-back", rotation = 0,            anchor = "RIGHT",  dx = -1, dy =  0, ox = -NUDGE_GAP, oy = 0 },
        { atlas = "common-dropdown-icon-next", rotation = 0,            anchor = "LEFT",   dx =  1, dy =  0, ox = NUDGE_GAP,  oy = 0 },
    }

    local function DoNudge(dx, dy)
        host:AdjustPointsOffset(dx, dy)
        local _, _, _, x, y = host:GetPoint()
        local owner = host._ownerButton
        local group = owner and owner._groupId and ResolveGroup(owner._groupId) or nil
        local settings
        if group and CooldownCompanion:IsTriggerPanelGroup(group) then
            settings = CooldownCompanion:GetTriggerPanelSignalSettings(group)
        else
            settings = group and CooldownCompanion:GetTexturePanelSettings(group)
        end
        if settings then
            settings.x = math_floor((x or 0) * 10 + 0.5) / 10
            settings.y = math_floor((y or 0) * 10 + 0.5) / 10
        end
        UpdateTextureHostCoordLabel(host, x, y)
    end

    for _, dir in ipairs(directions) do
        local btn = CreateFrame("Button", nil, nudger)
        btn:SetSize(NUDGE_BTN_SIZE, NUDGE_BTN_SIZE)
        btn:SetPoint(dir.anchor, nudger, "CENTER", dir.ox, dir.oy)
        btn:EnableMouse(true)
        nudger.buttons[#nudger.buttons + 1] = btn

        local arrow = btn:CreateTexture(nil, "OVERLAY")
        arrow:SetAtlas(dir.atlas)
        arrow:SetAllPoints()
        arrow:SetRotation(dir.rotation)
        arrow:SetVertexColor(0.8, 0.8, 0.8, 0.8)
        btn.arrow = arrow

        btn:SetScript("OnEnter", function(self)
            self.arrow:SetVertexColor(1, 1, 1, 1)
        end)
        btn:SetScript("OnLeave", function(self)
            self.arrow:SetVertexColor(0.8, 0.8, 0.8, 0.8)
            if self.nudgeDelayTimer then
                self.nudgeDelayTimer:Cancel()
                self.nudgeDelayTimer = nil
            end
            if self.nudgeTicker then
                self.nudgeTicker:Cancel()
                self.nudgeTicker = nil
            end
            SaveTextureHostPosition(host)
        end)

        btn:SetScript("OnMouseDown", function(self)
            DoNudge(dir.dx, dir.dy)
            self.nudgeDelayTimer = C_Timer.NewTimer(NUDGE_REPEAT_DELAY, function()
                self.nudgeTicker = C_Timer.NewTicker(NUDGE_REPEAT_INTERVAL, function()
                    DoNudge(dir.dx, dir.dy)
                end)
            end)
        end)

        btn:SetScript("OnMouseUp", function(self)
            if self.nudgeDelayTimer then
                self.nudgeDelayTimer:Cancel()
                self.nudgeDelayTimer = nil
            end
            if self.nudgeTicker then
                self.nudgeTicker:Cancel()
                self.nudgeTicker = nil
            end
            SaveTextureHostPosition(host)
        end)
    end

    host.nudger = nudger
end

local function EnsureAuraTextureDragHandle(host)
    if host.dragHandle then
        return
    end

    local dragHandle = CreateFrame("Frame", nil, host, "BackdropTemplate")
    dragHandle:SetPoint("BOTTOMLEFT", host, "TOPLEFT", 0, 2)
    dragHandle:SetPoint("BOTTOMRIGHT", host, "TOPRIGHT", 0, 2)
    dragHandle:SetHeight(15)
    dragHandle:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    dragHandle:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    ST.CreatePixelBorders(dragHandle)
    dragHandle:RegisterForDrag("LeftButton")
    dragHandle:EnableMouse(true)

    local text = dragHandle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER")
    text:SetTextColor(1, 1, 1, 1)
    dragHandle.text = text

    local coordLabel = CreateFrame("Frame", nil, dragHandle, "BackdropTemplate")
    coordLabel:SetHeight(15)
    coordLabel:SetPoint("TOPLEFT", host, "BOTTOMLEFT", 0, -2)
    coordLabel:SetPoint("TOPRIGHT", host, "BOTTOMRIGHT", 0, -2)
    coordLabel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    coordLabel:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    ST.CreatePixelBorders(coordLabel)
    coordLabel.text = coordLabel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    coordLabel.text:SetPoint("CENTER")
    coordLabel.text:SetTextColor(1, 1, 1, 1)

    dragHandle:SetScript("OnDragStart", function()
        if host._dragEnabled then
            host._isDragging = true
            host:StartMoving()
        end
    end)
    dragHandle:SetScript("OnDragStop", function()
        host._isDragging = nil
        host:StopMovingOrSizing()
        SaveTextureHostPosition(host)
    end)
    dragHandle:SetScript("OnMouseUp", function(_, button)
        if button ~= "MiddleButton" then
            return
        end

        local owner = host._ownerButton
        local group = owner and owner._groupId and ResolveGroup(owner._groupId) or nil
        if not group then
            return
        end

        group.locked = nil
        CooldownCompanion:RefreshGroupFrame(owner._groupId)
        CooldownCompanion:RefreshAllAuraTextureVisuals()
        if ST._configState and ST._configState.configFrame and ST._configState.configFrame.frame and ST._configState.configFrame.frame:IsShown() then
            CooldownCompanion:RefreshConfigPanel()
        end
        CooldownCompanion:Print((group.name or "Texture Panel") .. " locked.")
    end)

    host.dragHandle = dragHandle
    host.coordLabel = coordLabel
    EnsureAuraTextureNudger(host)
end

local function SyncAuraTextureControlLevels(host)
    if not host then
        return
    end

    local strata = host:GetFrameStrata()
    local baseLevel = host:GetFrameLevel() or 1

    if host.dragHandle then
        host.dragHandle:SetFrameStrata(strata)
        host.dragHandle:SetFrameLevel(baseLevel + 5)
    end
    if host.coordLabel then
        host.coordLabel:SetFrameStrata(strata)
        host.coordLabel:SetFrameLevel(baseLevel + 6)
    end
    if host.nudger then
        host.nudger:SetFrameStrata(strata)
        host.nudger:SetFrameLevel(baseLevel + 10)
        for index, btn in ipairs(host.nudger.buttons or {}) do
            btn:SetFrameStrata(strata)
            btn:SetFrameLevel(baseLevel + 11 + index)
        end
    end
end

local function EnsureAuraTextureHost(button)
    if button.auraTextureHost then
        return button.auraTextureHost
    end

    local host = CreateFrame("Frame", nil, UIParent)
    host:SetMovable(true)
    host:SetClampedToScreen(true)
    host:EnableMouse(false)
    host:Hide()
    host._ownerButton = button

    local visualRoot = CreateFrame("Frame", nil, host)
    visualRoot:SetPoint("CENTER", host, "CENTER", 0, 0)
    visualRoot:SetSize(1, 1)
    host.visualRoot = visualRoot

    local primary = visualRoot:CreateTexture(nil, "ARTWORK", nil, 1)
    local secondary = visualRoot:CreateTexture(nil, "ARTWORK", nil, 1)
    primary:Hide()
    secondary:Hide()
    host.primaryTexture = primary
    host.secondaryTexture = secondary

    host:SetScript("OnDragStart", function(self)
        if not self._dragEnabled then
            return
        end
        self._isDragging = true
        self:StartMoving()
    end)

    host:SetScript("OnDragStop", function(self)
        self._isDragging = nil
        self:StopMovingOrSizing()
        SaveTextureHostPosition(self)
    end)

    CreateAuraTextureOutline(host)
    EnsureAuraTextureDragHandle(host)
    button.auraTextureHost = host
    return host
end

function CooldownCompanion.EnsureTriggerIconVisual(host)
    if host.iconFrame then
        return host.iconFrame
    end

    local frame = CreateFrame("Frame", nil, host.visualRoot)
    frame:SetPoint("CENTER")
    frame:SetSize(36, 36)
    frame:Hide()

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()

    frame.icon = frame:CreateTexture(nil, "ARTWORK")

    frame.borderTextures = {}
    for index = 1, 4 do
        frame.borderTextures[index] = frame:CreateTexture(nil, "OVERLAY")
    end

    host.iconFrame = frame
    return frame
end

function CooldownCompanion.EnsureTriggerTextVisual(host)
    if host.textFrame then
        return host.textFrame
    end

    local frame = CreateFrame("Frame", nil, host.visualRoot)
    frame:SetPoint("CENTER")
    frame:SetSize(200, 20)
    frame:Hide()

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()

    frame.borderTextures = {}
    for index = 1, 4 do
        frame.borderTextures[index] = frame:CreateTexture(nil, "OVERLAY")
    end

    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.text:SetJustifyV("MIDDLE")
    frame.text:SetJustifyH("CENTER")
    frame.text:SetWordWrap(false)
    frame.text:SetMaxLines(0)

    host.textFrame = frame
    return frame
end

function CooldownCompanion.HideStandaloneDisplayVisuals(host)
    if not host then
        return
    end

    if host.primaryTexture then
        host.primaryTexture:Hide()
    end
    if host.secondaryTexture then
        host.secondaryTexture:Hide()
    end
    if host.iconFrame then
        host.iconFrame:Hide()
    end
    if host.textFrame then
        host.textFrame:Hide()
    end
end

function CooldownCompanion.GetTriggerIconDimensions(settings)
    if settings.maintainAspectRatio then
        local size = settings.buttonSize or 36
        return size, size
    end
    return settings.iconWidth or 36, settings.iconHeight or 36
end

function CooldownCompanion.HasTriggerTextValue(settings)
    return type(settings) == "table" and type(settings.value) == "string" and string_trim(settings.value) ~= ""
end

function CooldownCompanion.GetTriggerTextDisplayMetrics(fontString, settings)
    if not fontString or type(settings) ~= "table" then
        return 1, 1, CooldownCompanion.TRIGGER_PANEL_TEXT_INSET_X or 4, CooldownCompanion.TRIGGER_PANEL_TEXT_INSET_Y or 2, 1, 1, 1
    end

    local insetX = CooldownCompanion.TRIGGER_PANEL_TEXT_INSET_X or 4
    local insetY = CooldownCompanion.TRIGGER_PANEL_TEXT_INSET_Y or 2
    local overflowX = CooldownCompanion.TRIGGER_PANEL_TEXT_OVERFLOW_X or 6
    local overflowY = CooldownCompanion.TRIGGER_PANEL_TEXT_OVERFLOW_Y or 4
    local font = CooldownCompanion:FetchFont(settings.textFont or "Friz Quadrata TT")
    local textValue = CooldownCompanion.NormalizeTriggerPanelTextLineEndings(settings.value)

    fontString:ClearAllPoints()
    fontString:SetWordWrap(false)
    fontString:SetMaxLines(0)
    fontString:SetJustifyV("MIDDLE")
    fontString:SetJustifyH(settings.textAlignment or "CENTER")
    fontString:SetWidth(0)
    fontString:SetFont(font, settings.textFontSize or 12, settings.textFontOutline or "OUTLINE")
    fontString:SetText(textValue)

    local textWidth = 1
    local lineCount = 1
    local lineStart = 1
    while true do
        local lineBreak = string_find(textValue, "\n", lineStart, true)
        local lineText
        if lineBreak then
            lineText = textValue:sub(lineStart, lineBreak - 1)
        else
            lineText = textValue:sub(lineStart)
        end

        if lineText ~= "" then
            fontString:SetText(lineText)
            local measuredWidth = fontString.GetUnboundedStringWidth and fontString:GetUnboundedStringWidth() or fontString:GetStringWidth()
            textWidth = math_max(textWidth, math_floor((measuredWidth or 0) + 0.999))
        end

        if not lineBreak then
            break
        end
        lineCount = lineCount + 1
        lineStart = lineBreak + 1
    end

    fontString:SetText("Ag")
    local singleLineHeight = math_max(1, math_floor((fontString:GetStringHeight() or 0) + 0.999))
    fontString:SetText(textValue)
    local measuredHeight = math_max(1, math_floor((fontString:GetStringHeight() or 0) + 0.999))
    local textHeight = math_max(measuredHeight, singleLineHeight * lineCount)
    textWidth = textWidth + (overflowX * 2)
    textHeight = textHeight + (overflowY * 2)
    return textWidth + (insetX * 2), textHeight + (insetY * 2), insetX, insetY, textWidth, textHeight, lineCount
end

local function GetTexturePanelAlphaModuleId(groupId)
    if not groupId then
        return nil
    end
    return "texture_panel_" .. tostring(groupId)
end

local function GetTexturePanelLayoutPreviewAlpha(button)
    local CS = ST._configState
    if not button or not CS or CS.panelSettingsTab ~= "layout" or CS.selectedGroup ~= button._groupId then
        return nil
    end

    local preview = CS.texturePanelAlphaPreview
    if type(preview) ~= "table" then
        return nil
    end

    return preview[button._groupId]
end

function CooldownCompanion:HideAuraTextureVisual(button)
    local alphaModuleId = button and GetTexturePanelAlphaModuleId(button._groupId) or nil
    if alphaModuleId then
        self:UnregisterModuleAlpha(alphaModuleId, true)
    end

    local host = button and button.auraTextureHost
    if not host then
        return
    end

    StopAllTextureIndicatorEffects(host)
    if host._isDragging then
        host._isDragging = nil
        host:StopMovingOrSizing()
    end
    CooldownCompanion.HideStandaloneDisplayVisuals(host)
    host._activeDisplayType = nil
    host._activeTextureSettings = nil
    host._activeTextureGeometry = nil
    host._dragEnabled = nil
    host._wrapperManaged = nil
    host:EnableMouse(false)
    host:SetAlpha(1)
    SetAuraTextureOutlineShown(host, false)
    if host.dragHandle then
        host.dragHandle:Hide()
    end
    if host.coordLabel then
        host.coordLabel:Hide()
    end
    if host.nudger then
        for _, btn in ipairs(host.nudger.buttons or {}) do
            if btn.nudgeDelayTimer then
                btn.nudgeDelayTimer:Cancel()
                btn.nudgeDelayTimer = nil
            end
            if btn.nudgeTicker then
                btn.nudgeTicker:Cancel()
                btn.nudgeTicker = nil
            end
        end
        host.nudger:Hide()
    end
    host:Hide()

    local group = button and button._groupId and ResolveGroup(button._groupId) or nil
    if group and group.parentContainerId and self.RefreshContainerWrapper then
        self:RefreshContainerWrapper(group.parentContainerId)
    end
end

function CooldownCompanion:ReleaseAuraTextureVisual(button)
    if not button or not button.auraTextureHost then
        return
    end

    local alphaModuleId = GetTexturePanelAlphaModuleId(button._groupId)
    self:HideAuraTextureVisual(button)
    if alphaModuleId then
        self:UnregisterModuleAlpha(alphaModuleId)
    end
    button.auraTextureHost:SetParent(nil)
    button.auraTextureHost = nil
end

local function IsStandaloneTextureEditingButton(button)
    local CS = ST._configState
    if not CS or not CS.configFrame or not CS.configFrame.frame or not CS.configFrame.frame:IsShown() then
        return false
    end
    if CS.selectedGroup ~= button._groupId then
        return false
    end

    local group = button._groupId and ResolveGroup(button._groupId) or nil
    if not CooldownCompanion:IsStandaloneTexturePanelGroup(group) then
        return false
    end

    if CS.panelSettingsTab == "appearance" or CS.panelSettingsTab == "effects" or CS.panelSettingsTab == "layout" then
        if CooldownCompanion:IsTriggerPanelGroup(group) then
            return true
        end
        if CS.selectedButton == nil then
            return true
        end
    end

    local pickerWindow = CS.auraTexturePickerWindow
    return pickerWindow and pickerWindow._targetGroupId == button._groupId
end

local function IsTexturePanelConfigForceVisible(button)
    if not button then
        return false
    end

    local group = button._groupId and ResolveGroup(button._groupId) or nil
    if not CooldownCompanion:IsTexturePanelGroup(group) then
        return false
    end

    return ST.IsConfigButtonForceVisible(button)
end

local function GetStandaloneTextureSettings(group)
    if CooldownCompanion:IsTriggerPanelGroup(group) then
        return CooldownCompanion:GetTriggerPanelSignalSettings(group)
    end

    if CooldownCompanion:IsTexturePanelGroup(group) then
        return CooldownCompanion:GetTexturePanelSettings(group)
    end

    return nil
end

function CooldownCompanion.GetStandaloneDisplayType(group)
    if CooldownCompanion:IsTriggerPanelGroup(group) then
        return CooldownCompanion:GetTriggerPanelDisplayType(group, true)
    end
    if CooldownCompanion:IsTexturePanelGroup(group) then
        return "texture"
    end
    return nil
end

function CooldownCompanion.ResolveActiveStandaloneDisplay(button)
    local group = button._groupId and ResolveGroup(button._groupId) or nil
    if not CooldownCompanion:IsStandaloneTexturePanelGroup(group) then
        return nil, nil
    end

    local displayType = CooldownCompanion.GetStandaloneDisplayType(group)
    local preview = button._auraTexturePreviewSelection
    if displayType == "texture" and type(preview) == "table" then
        return "texture", NormalizeAuraTextureSettings(preview)
    end

    if displayType == "icon" then
        local settings = CooldownCompanion:GetTriggerPanelIconSettings(group, false)
        if not settings or settings.manualIcon == nil then
            return "icon", nil
        end
        return "icon", settings
    end

    if displayType == "text" then
        local settings = CooldownCompanion:GetTriggerPanelTextSettings(group, false)
        if not settings or not CooldownCompanion.HasTriggerTextValue(settings) then
            return "text", nil
        end
        return "text", settings
    end

    local settings = GetStandaloneTextureSettings(group)
    if not settings or not settings.sourceType or settings.sourceValue == nil then
        return "texture", nil
    end
    if not settings.enabled and not IsStandaloneTextureEditingButton(button) then
        return "texture", nil
    end

    return "texture", settings
end

function CooldownCompanion.ApplyTriggerIconVisual(host, settings)
    local iconFrame = CooldownCompanion.EnsureTriggerIconVisual(host)
    local width, height = CooldownCompanion.GetTriggerIconDimensions(settings)
    local borderSize = settings.borderSize or 0
    local iconTint = settings.iconTintColor or { 1, 1, 1, 1 }
    local backgroundColor = settings.backgroundColor or { 0, 0, 0, 0.5 }
    local borderColor = settings.borderColor or { 0, 0, 0, 1 }

    CooldownCompanion:ResetTextureIndicatorRootState(host)
    CooldownCompanion.HideStandaloneDisplayVisuals(host)

    host._activeTextureSettings = nil
    host._activeTextureGeometry = nil
    host._activeDisplayType = "icon"
    host._triggerTextBaseColor = nil
    host._triggerIconBaseColor = CopyColor(iconTint) or { 1, 1, 1, 1 }

    host:SetSize(width, height)
    host.visualRoot:SetSize(width, height)

    iconFrame:SetSize(width, height)
    iconFrame.bg:SetColorTexture(
        backgroundColor[1] or 0,
        backgroundColor[2] or 0,
        backgroundColor[3] or 0,
        backgroundColor[4] ~= nil and backgroundColor[4] or 0.5
    )
    iconFrame.icon:ClearAllPoints()
    iconFrame.icon:SetPoint("TOPLEFT", borderSize, -borderSize)
    iconFrame.icon:SetPoint("BOTTOMRIGHT", -borderSize, borderSize)
    iconFrame.icon:SetTexture(settings.manualIcon)
    iconFrame.icon:SetVertexColor(
        iconTint[1] or 1,
        iconTint[2] or 1,
        iconTint[3] or 1,
        iconTint[4] ~= nil and iconTint[4] or 1
    )
    ST._ApplyIconTexCoord(iconFrame.icon, width, height)

    for _, border in ipairs(iconFrame.borderTextures) do
        border:SetColorTexture(
            borderColor[1] or 0,
            borderColor[2] or 0,
            borderColor[3] or 0,
            borderColor[4] ~= nil and borderColor[4] or 1
        )
    end
    ST._ApplyEdgePositions(iconFrame.borderTextures, iconFrame, borderSize)
    iconFrame:Show()

    return true
end

function CooldownCompanion.ApplyTriggerTextVisual(host, settings)
    local textFrame = CooldownCompanion.EnsureTriggerTextVisual(host)
    local textColor = settings.textFontColor or { 1, 1, 1, 1 }
    local backgroundColor = settings.textBgColor or { 0, 0, 0, 0 }
    local frameWidth, frameHeight, insetX, insetY, textWidth, textHeight, lineCount = CooldownCompanion.GetTriggerTextDisplayMetrics(textFrame.text, settings)

    CooldownCompanion:ResetTextureIndicatorRootState(host)
    CooldownCompanion.HideStandaloneDisplayVisuals(host)

    host._activeTextureSettings = nil
    host._activeTextureGeometry = nil
    host._activeDisplayType = "text"
    host._triggerIconBaseColor = nil
    host._triggerTextBaseColor = CopyColor(textColor) or { 1, 1, 1, 1 }

    host:SetSize(frameWidth, frameHeight)
    host.visualRoot:SetSize(frameWidth, frameHeight)

    textFrame:SetSize(frameWidth, frameHeight)
    textFrame.bg:SetColorTexture(
        backgroundColor[1] or 0,
        backgroundColor[2] or 0,
        backgroundColor[3] or 0,
        backgroundColor[4] ~= nil and backgroundColor[4] or 0
    )
    for _, border in ipairs(textFrame.borderTextures) do
        border:Hide()
    end

    textFrame.text:SetTextColor(
        textColor[1] or 1,
        textColor[2] or 1,
        textColor[3] or 1,
        textColor[4] ~= nil and textColor[4] or 1
    )
    textFrame.text:ClearAllPoints()
    textFrame.text:SetPoint("TOPLEFT", textFrame, "TOPLEFT", insetX, -insetY)
    textFrame.text:SetPoint("BOTTOMRIGHT", textFrame, "BOTTOMRIGHT", -insetX, insetY)
    textFrame.text:SetSize(textWidth or math_max(1, frameWidth - (insetX * 2)), textHeight or math_max(1, frameHeight - (insetY * 2)))
    textFrame.text:SetJustifyH(settings.textAlignment or "CENTER")
    textFrame.text:SetWordWrap((lineCount or 1) > 1)
    textFrame.text:SetJustifyV((lineCount or 1) > 1 and "TOP" or "MIDDLE")
    textFrame:Show()

    return true
end

function CooldownCompanion:GetStandaloneDisplayVisibilityState(group, frame, driverButton, displayType, settings, isTriggerPanel)
    local groupedPreviewFrame = GetGroupedPreviewContainerFrame(group)
    local state = {
        isEditing = IsStandaloneTextureEditingButton(driverButton),
        isConfigForceVisible = (not isTriggerPanel) and IsTexturePanelConfigForceVisible(driverButton),
        isGroupedPreview = groupedPreviewFrame ~= nil,
        groupedPreviewFrame = groupedPreviewFrame,
        isUnlocked = group and (group.locked == false or groupedPreviewFrame ~= nil),
        hasPreviewSelection = displayType == "texture" and type(driverButton._auraTexturePreviewSelection) == "table",
        hasTriggerEffectPreview = isTriggerPanel and driverButton._triggerEffectsPreview == true,
        triggerMatched = isTriggerPanel and frame and frame:IsShown() and DoesTriggerPanelMatch(frame) or false,
        showDisplay = false,
    }

    if settings then
        if state.hasPreviewSelection then
            state.showDisplay = true
        elseif isTriggerPanel then
            state.showDisplay = state.triggerMatched or state.hasTriggerEffectPreview or state.isEditing or state.isUnlocked
        elseif state.isEditing then
            state.showDisplay = true
        elseif state.isConfigForceVisible then
            state.showDisplay = true
        elseif state.isUnlocked then
            state.showDisplay = true
        elseif driverButton:GetParent()
            and driverButton:GetParent():IsShown()
            and not (driverButton._rawVisibilityHidden == true) then
            state.showDisplay = true
        end
    end

    state.triggerSoundVisible = settings ~= nil and state.triggerMatched and state.showDisplay
    state.bypassModuleAlpha = state.hasPreviewSelection or state.isEditing or state.isConfigForceVisible or state.isUnlocked
    return state
end

function CooldownCompanion:RenderStandaloneDisplay(host, driverButton, group, settings, displayType, isTriggerPanel, effectsActive)
    local hostWidth, hostHeight
    local shown = false

    host:SetFrameStrata(driverButton:GetFrameStrata())
    host:SetFrameLevel((driverButton:GetFrameLevel() or 1) + 20)
    SyncAuraTextureControlLevels(host)

    if displayType == "texture" then
        local baseAlpha = Clamp((settings.color and settings.color[4] or 1) * settings.alpha, 0.05, 1)
        local alpha = Clamp(baseAlpha, 0, 1)
        local sourceWidth = settings.width and settings.width > 0 and settings.width or DEFAULT_TEXTURE_SIZE
        local sourceHeight = settings.height and settings.height > 0 and settings.height or DEFAULT_TEXTURE_SIZE
        local geometry = self:BuildTexturePanelGeometry(settings, sourceWidth * settings.scale, sourceHeight * settings.scale)
        CooldownCompanion.HideStandaloneDisplayVisuals(host)
        hostWidth = geometry.boundsWidth
        hostHeight = geometry.boundsHeight
        host:SetSize(hostWidth, hostHeight)
        if host.visualRoot then
            host.visualRoot:SetSize(hostWidth, hostHeight)
        end
        shown = LayoutTexturePieces(host, settings, geometry, alpha)
        if shown then
            host._activeTextureSettings = settings
            host._activeTextureGeometry = geometry
            host._activeDisplayType = "texture"
            SetTextureIndicatorBaseVisuals(host)
            if isTriggerPanel then
                self:ApplyTriggerPanelEffects(host, driverButton, group, effectsActive)
            else
                ApplyTextureIndicatorEffects(host, driverButton, group)
            end
        end
    elseif displayType == "icon" then
        hostWidth, hostHeight = CooldownCompanion.GetTriggerIconDimensions(settings)
        host:SetSize(hostWidth, hostHeight)
        if host.visualRoot then
            host.visualRoot:SetSize(hostWidth, hostHeight)
        end
        shown = CooldownCompanion.ApplyTriggerIconVisual(host, settings)
        if shown and isTriggerPanel then
            self:ApplyTriggerPanelEffects(host, driverButton, group, effectsActive)
        else
            StopAllTextureIndicatorEffects(host)
        end
    elseif displayType == "text" then
        shown = CooldownCompanion.ApplyTriggerTextVisual(host, settings)
        if shown and isTriggerPanel then
            self:ApplyTriggerPanelEffects(host, driverButton, group, effectsActive)
        else
            StopAllTextureIndicatorEffects(host)
        end
    end

    return shown
end

function CooldownCompanion:FinalizeStandaloneDisplay(host, frame, driverButton, group, settings, displayType, isTriggerPanel, visibilityState)
    local sharedSettings = GetStandaloneTextureSettings(group) or {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = 0,
    }

    if not host._isDragging then
        local currentPoint, currentRelativeFrame, _, currentX, currentY = host:GetPoint(1)
        host:ClearAllPoints()
        local groupedPreviewFrame = visibilityState and visibilityState.groupedPreviewFrame or nil
        if groupedPreviewFrame then
            local preserveRelativeOffset = host._wrapperManaged
                and currentRelativeFrame == groupedPreviewFrame
                and currentX ~= nil
                and currentY ~= nil
            if preserveRelativeOffset then
                host:SetPoint(currentPoint or sharedSettings.point or "CENTER", groupedPreviewFrame, "CENTER", currentX, currentY)
            else
                local screenAnchorX, screenAnchorY, point = GetStandaloneScreenAnchorPoint(sharedSettings)
                local containerX, containerY = groupedPreviewFrame:GetCenter()
                if screenAnchorX and screenAnchorY and containerX and containerY then
                    host:SetPoint(point or sharedSettings.point or "CENTER", groupedPreviewFrame, "CENTER", screenAnchorX - containerX, screenAnchorY - containerY)
                else
                    host:SetPoint(sharedSettings.point, UIParent, sharedSettings.relativePoint, sharedSettings.x, sharedSettings.y)
                end
            end
        else
            host:SetPoint(sharedSettings.point, UIParent, sharedSettings.relativePoint, sharedSettings.x, sharedSettings.y)
        end
    end
    host:Show()

    local alphaModuleId = GetTexturePanelAlphaModuleId(driverButton._groupId)
    local layoutPreviewAlpha = GetTexturePanelLayoutPreviewAlpha(driverButton)
    local visibilityAlpha = Clamp(driverButton._rawVisibilityAlphaOverride or 1, 0, 1)
    if alphaModuleId then
        if visibilityState.bypassModuleAlpha then
            self:UnregisterModuleAlpha(alphaModuleId, true)
            host:SetAlpha(layoutPreviewAlpha ~= nil and layoutPreviewAlpha or 1)
        else
            self:RegisterModuleAlpha(alphaModuleId, group, { host })
            local alphaState = self.alphaState and self.alphaState[alphaModuleId]
            if alphaState and alphaState.currentAlpha ~= nil then
                host:SetAlpha(Clamp(alphaState.currentAlpha * visibilityAlpha, 0, 1))
            else
                host:SetAlpha(visibilityAlpha)
            end
        end
    else
        host:SetAlpha(visibilityState.bypassModuleAlpha and (layoutPreviewAlpha ~= nil and layoutPreviewAlpha or 1) or visibilityAlpha)
    end

    local savedSettings = isTriggerPanel and group and group.triggerSettings and group.triggerSettings.signal or group and group.textureSettings or nil
    local hasSavedDisplay = false
    if displayType == "texture" then
        hasSavedDisplay = type(savedSettings) == "table" and savedSettings.sourceType ~= nil
    elseif displayType == "icon" then
        hasSavedDisplay = settings.manualIcon ~= nil
    elseif displayType == "text" then
        hasSavedDisplay = CooldownCompanion.HasTriggerTextValue(settings)
    end
    host._dragEnabled = visibilityState.isUnlocked and hasSavedDisplay and not visibilityState.isGroupedPreview
    host._wrapperManaged = visibilityState.isGroupedPreview or nil
    host:EnableMouse(false)
    SetAuraTextureOutlineShown(host, false)
    if host.dragHandle and host.coordLabel then
        host.dragHandle.text:SetText(group and group.name or "Texture Panel")
        if host._isDragging then
            local _, _, _, currentX, currentY = host:GetPoint()
            UpdateTextureHostCoordLabel(host, currentX, currentY)
        else
            UpdateTextureHostCoordLabel(host, sharedSettings.x, sharedSettings.y)
        end
        local showHeader = host._dragEnabled == true and not visibilityState.isGroupedPreview
        host.dragHandle:SetShown(showHeader)
        host.coordLabel:SetShown(showHeader)
        if host.nudger then
            host.nudger:SetShown(showHeader)
        end
    end
    if driverButton:GetAlpha() ~= 0 then
        driverButton:SetAlpha(0)
        driverButton._lastVisAlpha = 0
    end
    if ST.SetFrameClickThroughRecursive then
        if isTriggerPanel and frame and type(frame.buttons) == "table" then
            for _, backingButton in ipairs(frame.buttons) do
                ST.SetFrameClickThroughRecursive(backingButton, true, true)
            end
        else
            ST.SetFrameClickThroughRecursive(driverButton, true, true)
        end
    end

    if visibilityState.isGroupedPreview and group and group.parentContainerId and self.RefreshContainerWrapper then
        self:RefreshContainerWrapper(group.parentContainerId)
    end
end

function CooldownCompanion:SyncGroupedStandalonePreviewSettings(containerId)
    if not (containerId and self.GetContainerUnlockPreviewPanels) then
        return
    end

    local previewPanels = self:GetContainerUnlockPreviewPanels(containerId)
    for _, panelInfo in ipairs(previewPanels) do
        local group = panelInfo.group
        if group and (group.displayMode == "textures" or group.displayMode == "trigger") then
            local groupFrame = self.groupFrames and self.groupFrames[panelInfo.groupId] or nil
            local driverButton = groupFrame and groupFrame.buttons and groupFrame.buttons[1] or nil
            local host = driverButton and driverButton.auraTextureHost or nil
            local settings = nil
            if group.displayMode == "trigger" then
                settings = self:GetTriggerPanelSignalSettings(group)
            else
                settings = self:GetTexturePanelSettings(group)
            end

            if host and settings and SaveGroupedStandalonePreviewSettings(host, group, settings) then
                UpdateTextureHostCoordLabel(host, settings.x, settings.y)
            end
        end
    end
end

function CooldownCompanion:UpdateAuraTextureVisual(button)
    if not button or button._isText then
        return
    end

    local group = button._groupId and ResolveGroup(button._groupId) or nil
    if not self:IsStandaloneTexturePanelGroup(group) then
        self:HideAuraTextureVisual(button)
        return
    end

    local frame = button:GetParent()
    local isTriggerPanel = self:IsTriggerPanelGroup(group)
    local driverButton = button
    if isTriggerPanel then
        driverButton = frame and frame.buttons and frame.buttons[1] or nil
        if not driverButton then
            self:HideAuraTextureVisual(button)
            return
        end
    end

    local displayType, settings = CooldownCompanion.ResolveActiveStandaloneDisplay(driverButton)
    local visibilityState = self:GetStandaloneDisplayVisibilityState(group, frame, driverButton, displayType, settings, isTriggerPanel)

    if isTriggerPanel and self.UpdateTriggerPanelSoundAlerts then
        self:UpdateTriggerPanelSoundAlerts(frame, group, visibilityState.triggerSoundVisible)
    end

    if not settings or not visibilityState.showDisplay then
        self:HideAuraTextureVisual(driverButton)
        if driverButton:GetAlpha() ~= 0 then
            driverButton:SetAlpha(0)
            driverButton._lastVisAlpha = 0
        end
        return
    end

    local host = EnsureAuraTextureHost(driverButton)
    local shown = self:RenderStandaloneDisplay(
        host,
        driverButton,
        group,
        settings,
        displayType,
        isTriggerPanel,
        visibilityState.triggerMatched or visibilityState.hasTriggerEffectPreview
    )

    if not shown then
        self:HideAuraTextureVisual(driverButton)
        if driverButton:GetAlpha() ~= 0 then
            driverButton:SetAlpha(0)
            driverButton._lastVisAlpha = 0
        end
        return
    end

    self:FinalizeStandaloneDisplay(host, frame, driverButton, group, settings, displayType, isTriggerPanel, visibilityState)
end

function CooldownCompanion:RefreshAllAuraTextureVisuals()
    for _, frame in pairs(self.groupFrames or {}) do
        for _, button in ipairs(frame.buttons or {}) do
            self:UpdateAuraTextureVisual(button)
        end
    end
end
