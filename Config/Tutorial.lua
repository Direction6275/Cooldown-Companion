--[[
    CooldownCompanion - Config/Tutorial
    First-run icon-panel onboarding using a standalone raw frame and semantic anchors.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState
local CreateGlowContainer = ST._CreateGlowContainer
local ShowGlowStyle = ST._ShowGlowStyle
local HideGlowStyles = ST._HideGlowStyles

local pairs = pairs
local next = next
local wipe = wipe
local tonumber = tonumber
local tostring = tostring
local math_deg = math.deg
local math_floor = math.floor
local math_fmod = math.fmod
local math_pi = math.pi
local format = string.format

local TUTORIAL_ID = "firstIconPanel"
local TUTORIAL_SOLID_GLOW_COLOR = { 1, 0.9, 0.18, 1 }
local TUTORIAL_SIDE_PLACEMENT_OFFSET = 44
local TUTORIAL_FRAME_WIDTH = 316
local TUTORIAL_FRAME_MIN_HEIGHT = 90
local TUTORIAL_FRAME_MAX_HEIGHT = 320
local TUTORIAL_TEXT_WIDTH = 266
local TUTORIAL_TOP_CONTENT_PADDING = 48
local TUTORIAL_BOTTOM_CONTENT_PADDING = 42
local STEP_ORDER = {
    "welcome",
    "groups_column_intro",
    "create_group",
    "panels_column_intro",
    "create_panel",
    "panel_area_intro",
    "add_one_spell",
    "entry_settings_intro",
    "panel_settings_intro",
    "view_modes_intro",
    "finish",
}

local STEP_INDEX = {}
for index, step in ipairs(STEP_ORDER) do
    STEP_INDEX[step] = index
end

local STEP_DATA = {
    welcome = {
        title = "First Icon Panel",
        text = "This tutorial will walk you through adding a single spell to track and explain some basics about the add-on along the way.",
        placement = "center",
    },
    groups_column_intro = {
        title = "Groups",
        text = "Groups are containers for panels. By default, groups belong to the character they are created on.",
        anchor = "groups_column_area",
        placement = "right",
    },
    create_group = {
        title = "Create a Group",
        text = "Click New Group to create a group.",
        anchor = "new_group_button",
        placement = "above",
    },
    panels_column_intro = {
        title = "Panels",
        text = "Panels are containers for the things you want to track, like spells, auras, and items. The type of panel you choose determines how tracked entries are displayed.\n\nRead the descriptions of each type of panel in the column to become familiar with available panel types.",
        anchor = "panels_column_area",
        placement = "right",
    },
    create_panel = {
        title = "Create an Icon Panel",
        text = "Click Icon Panel to create a new icon panel.",
        anchor = "icon_panel_button",
        placement = "above",
    },
    panel_area_intro = {
        title = "This Is the Panel",
        text = "This is an empty icon panel. Let's add something to track.",
        anchor = "selected_panel_area",
        placement = "right",
    },
    add_one_spell = {
        title = "Add Your First Ability",
        text = "Type the name of a spell your character can use in the edit box.\n\nAs you type, the addon will attempt to help you narrow down what you're looking for. Add the spell by clicking on it in the dropdown or using arrow keys + Enter.",
        anchor = "selected_panel_add_input",
        placement = "right",
    },
    entry_settings_intro = {
        title = "Entry Settings",
        text = "This column is dedicated to editing and styling single, specific entries. Aura tracking settings, per-button visibility rules, sound alerts, and more is configured in this column.",
        anchor = "col3_area",
        placement = "right",
    },
    panel_settings_intro = {
        title = "Panel Settings",
        text = "This column is dedicated to editing and styling all entries in a panel. Panel layout, text elements, and indicators are all found here.\n\nImportant:\n\n|A:Crosshair_VehichleCursor_32:14:14|a: Whenever you see the |A:Crosshair_VehichleCursor_32:14:14|a next to a setting, that means you can override a panel-wide setting for a specific entry.\n\n|A:QuestLog-icon-setting:14:14|a: Whenever you see the |A:QuestLog-icon-setting:14:14|a next to a setting, that means you can expand advanced settings for it.",
        anchor = "col4_area",
        placement = "left",
    },
    view_modes_intro = {
        title = "Bars And Frames",
        text = "This button switches between the main Buttons view and optional extras like resource bars, cast bar anchoring and styling, and unit frame anchoring.",
        anchor = "mode_toggle_button",
        placement = "above",
    },
    finish = {
        title = "Tutorial Complete",
        text = "You can watch this tutorial again later from the gear menu in the top-right corner.",
        anchor = "gear_button",
        placement = "below",
    },
}

local function GetAddonVersion()
    if ST._GetAddonVersion then
        return tostring(ST._GetAddonVersion() or "unknown")
    end
    return "unknown"
end

local function GetStepNumber(step)
    return tonumber(STEP_INDEX[step]) or 1
end

local function GetPreviousStep(step)
    local index = STEP_INDEX[step]
    if not index or index <= 1 then
        return nil
    end
    return STEP_ORDER[index - 1]
end

local function GetTutorialState()
    if not (CooldownCompanion and CooldownCompanion.db and CooldownCompanion.db.global) then
        return nil
    end

    local global = CooldownCompanion.db.global
    if type(global.tutorials) ~= "table" then
        global.tutorials = {}
    end
    if type(global.tutorials[TUTORIAL_ID]) ~= "table" then
        global.tutorials[TUTORIAL_ID] = {}
    end

    local state = global.tutorials[TUTORIAL_ID]
    if state.completed ~= true then
        state.completed = false
    end
    if state.dismissed ~= true then
        state.dismissed = false
    end
    if state.lastVersionSeen ~= nil then
        state.lastVersionSeen = tostring(state.lastVersionSeen)
    end

    return state
end

local function ProfileHasExistingSetup()
    local profile = CooldownCompanion and CooldownCompanion.db and CooldownCompanion.db.profile
    if not profile then
        return false
    end
    return next(profile.groupContainers or {}) ~= nil or next(profile.groups or {}) ~= nil
end

local function IsConfigVisible()
    return CS.configFrame and CS.configFrame.frame and CS.configFrame.frame:IsShown()
end

local function GetRuntime()
    return CS.tutorialRuntime
end

local function IsTutorialActive()
    local runtime = GetRuntime()
    return runtime and runtime.active == true
end

local function SetStep(step)
    local runtime = GetRuntime()
    if not runtime then
        return
    end
    runtime.step = step
end

local function GetAnchor(name)
    local frame = CS.tutorialAnchors and CS.tutorialAnchors[name]
    if frame and frame.IsShown and frame:IsShown() then
        return frame
    end
    return nil
end

local function HideHighlight()
    if CS.tutorialHighlight then
        if CS.tutorialHighlight._cdcGlow and HideGlowStyles then
            HideGlowStyles(CS.tutorialHighlight._cdcGlow)
        end
        CS.tutorialHighlight:ClearAllPoints()
        CS.tutorialHighlight:Hide()
    end
end

local function RotateTexture(texture, rotation)
    if not texture then
        return
    end
    if SetClampedTextureRotation then
        local degrees = math_fmod(math_deg(rotation), 360)
        if degrees < 0 then
            degrees = degrees + 360
        end
        degrees = (math_floor((degrees / 90) + 0.5) % 4) * 90
        SetClampedTextureRotation(texture, degrees)
    else
        texture:SetRotation(rotation)
    end
end

local function EnsureTutorialFrame()
    if CS.tutorialFrame then
        return CS.tutorialFrame
    end

    local parent = (CS.configFrame and CS.configFrame.frame) or UIParent
    local frame = CreateFrame("Frame", nil, parent, "GlowBoxTemplate")
    frame:SetSize(TUTORIAL_FRAME_WIDTH, TUTORIAL_FRAME_MIN_HEIGHT)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(parent:GetFrameLevel() + 40)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(false)
    frame:Hide()

    local titleText = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    titleText:SetPoint("TOP", frame, "TOP", 0, -11)
    titleText:SetTextColor(1, 0.82, 0)
    titleText:SetText("First Icon Panel")
    frame.titleText = titleText

    local stepLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    stepLabel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -14)
    stepLabel:SetTextColor(1, 0.82, 0, 0.85)
    stepLabel:SetJustifyH("RIGHT")
    frame.stepLabel = stepLabel

    local bodyText = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightLeft")
    bodyText:SetJustifyH("LEFT")
    bodyText:SetJustifyV("TOP")
    bodyText:SetSpacing(2)
    bodyText:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -33)
    bodyText:SetWidth(TUTORIAL_TEXT_WIDTH)
    frame.bodyText = bodyText

    local arrow = CreateFrame("Frame", nil, frame, "GlowBoxArrowTemplate")
    arrow:SetSize(45, 18)
    if arrow.Arrow then
        arrow.Arrow:SetAlpha(0.9)
    end
    if arrow.Glow then
        arrow.Glow:SetAlpha(0.28)
    end
    arrow:Hide()
    frame.arrow = arrow

    local function CreateActionButton(width)
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetSize(width or 110, 22)
        button:Hide()
        return button
    end

    local leftButton = CreateActionButton(110)
    local middleButton = CreateActionButton(110)
    local rightButton = CreateActionButton(110)
    leftButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 10)
    middleButton:SetPoint("BOTTOM", frame, "BOTTOM", 0, 10)
    rightButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 10)
    frame.leftButton = leftButton
    frame.middleButton = middleButton
    frame.rightButton = rightButton

    local closeButton = CreateFrame("Button", nil, frame)
    closeButton:SetSize(18, 18)
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)
    local closeIcon = closeButton:CreateTexture(nil, "ARTWORK")
    closeIcon:SetAtlas("common-icon-redx")
    closeIcon:SetAllPoints()
    closeButton:SetHighlightAtlas("common-icon-redx")
    closeButton:GetHighlightTexture():SetAlpha(0.3)
    frame.CloseButton = closeButton

    local highlight = CreateFrame("Frame", nil, UIParent)
    highlight:SetFrameStrata("TOOLTIP")
    highlight:SetFrameLevel(2000)
    highlight:SetToplevel(true)
    highlight:EnableMouse(false)
    highlight:Hide()
    if CreateGlowContainer then
        highlight._cdcGlow = CreateGlowContainer(highlight, 48, false)
        if highlight._cdcGlow.solidFrame then
            highlight._cdcGlow.solidFrame:SetFrameStrata("TOOLTIP")
            highlight._cdcGlow.solidFrame:SetFrameLevel(highlight:GetFrameLevel() + 1)
        end
        if highlight._cdcGlow.procFrame then
            highlight._cdcGlow.procFrame:SetFrameStrata("TOOLTIP")
            highlight._cdcGlow.procFrame:SetFrameLevel(highlight:GetFrameLevel() + 2)
        end
    end
    CS.tutorialHighlight = highlight

    frame:SetScript("OnHide", function()
        HideHighlight()
        if frame.arrow then
            frame.arrow:Hide()
        end
    end)

    if closeButton then
        closeButton:SetScript("OnClick", function()
            if ST._CancelFirstIconPanelTutorial then
                ST._CancelFirstIconPanelTutorial("close_button")
            else
                frame:Hide()
            end
        end)
    end

    CS.tutorialFrame = frame
    return frame
end

local function ResizeTutorialFrame(frame)
    if not frame or not frame.bodyText then
        return
    end

    local bodyText = frame.bodyText
    bodyText:SetWidth(TUTORIAL_TEXT_WIDTH)

    local textHeight = math.ceil(bodyText:GetStringHeight() or 0)
    local desiredHeight = TUTORIAL_TOP_CONTENT_PADDING + textHeight + TUTORIAL_BOTTOM_CONTENT_PADDING
    local clampedHeight = math.min(TUTORIAL_FRAME_MAX_HEIGHT, math.max(TUTORIAL_FRAME_MIN_HEIGHT, desiredHeight))

    frame:SetHeight(clampedHeight)
end

local function ResetTutorialButton(button)
    button:Hide()
    button:SetEnabled(true)
    button:SetScript("OnClick", nil)
    button:SetText("")
end

local function SetTutorialButton(button, text, onClick, enabled)
    if not button then
        return
    end
    button:SetText(text or "")
    button:SetEnabled(enabled ~= false)
    button:SetScript("OnClick", onClick)
    button:Show()
end

local function DismissTutorial()
    local state = GetTutorialState()
    if state then
        state.completed = false
        state.dismissed = true
        state.lastVersionSeen = GetAddonVersion()
    end
    if ST._CancelFirstIconPanelTutorial then
        ST._CancelFirstIconPanelTutorial("dismissed")
    end
end

local function CompleteTutorial()
    local state = GetTutorialState()
    if state then
        state.completed = true
        state.dismissed = false
        state.lastVersionSeen = GetAddonVersion()
    end
    if ST._CancelFirstIconPanelTutorial then
        ST._CancelFirstIconPanelTutorial("completed")
    end
end

local function AdvanceStep(nextStep)
    SetStep(nextStep)
    if ST._RefreshTutorialPlacement then
        ST._RefreshTutorialPlacement()
    end
end

local function GoToPreviousStep()
    local runtime = GetRuntime()
    if not runtime then
        return
    end
    local previousStep = GetPreviousStep(runtime.step)
    if previousStep then
        AdvanceStep(previousStep)
    end
end

local function NormalizeTutorialContext()
    if not IsConfigVisible() then
        return
    end

    local configFrame = CS.configFrame
    if configFrame and configFrame.HideChangelogOverlay then
        configFrame.HideChangelogOverlay()
    end
    if CS.profileBar and CS.profileBar:IsShown() then
        CS.profileBar:Hide()
    end

    if CS.talentPickerMode and CooldownCompanion.CloseTalentPicker then
        CooldownCompanion:CloseTalentPicker()
    end
    if ST._CancelAutoAddFlow then
        ST._CancelAutoAddFlow()
    end

    CloseDropDownMenus()
    if CS.HideAutocomplete then
        CS.HideAutocomplete()
    end

    CS.browseMode = false
    CS.browseCharKey = nil
    CS.browseContainerId = nil
    CS.selectedContainer = nil
    CS.selectedGroup = nil
    CS.selectedButton = nil
    wipe(CS.selectedButtons)
    wipe(CS.selectedPanels)
    wipe(CS.selectedGroups)
    CS.addingToPanelId = nil
    CS.newInput = ""
    CS.pendingEditBoxFocus = false

    if ST._SetConfigPrimaryMode then
        ST._SetConfigPrimaryMode("buttons", { skipRefresh = true })
    else
        CS.resourceBarPanelActive = false
    end

    CooldownCompanion:RefreshConfigPanel()
end

local function ConfigureButtonsForStep(frame, step)
    ResetTutorialButton(frame.leftButton)
    ResetTutorialButton(frame.middleButton)
    ResetTutorialButton(frame.rightButton)

    if step == "welcome" then
        SetTutorialButton(frame.leftButton, "Skip", DismissTutorial)
        SetTutorialButton(frame.rightButton, "Next", function()
            AdvanceStep("groups_column_intro")
        end)
    elseif step == "groups_column_intro" then
        SetTutorialButton(frame.leftButton, "Previous", GoToPreviousStep)
        SetTutorialButton(frame.rightButton, "Next", function()
            AdvanceStep("create_group")
        end)
    elseif step == "create_group" then
        SetTutorialButton(frame.leftButton, "Previous", GoToPreviousStep)
        if GetRuntime() and GetRuntime().createdGroup then
            SetTutorialButton(frame.rightButton, "Next", function()
                AdvanceStep("panels_column_intro")
            end)
        end
    elseif step == "panels_column_intro" then
        SetTutorialButton(frame.leftButton, "Previous", GoToPreviousStep)
        SetTutorialButton(frame.rightButton, "Next", function()
            AdvanceStep("create_panel")
        end)
    elseif step == "create_panel" then
        SetTutorialButton(frame.leftButton, "Previous", GoToPreviousStep)
        if GetRuntime() and GetRuntime().createdPanel then
            SetTutorialButton(frame.rightButton, "Next", function()
                AdvanceStep("panel_area_intro")
            end)
        end
    elseif step == "panel_area_intro" then
        SetTutorialButton(frame.leftButton, "Previous", GoToPreviousStep)
        SetTutorialButton(frame.rightButton, "Next", function()
            AdvanceStep("add_one_spell")
        end)
    elseif step == "add_one_spell" then
        SetTutorialButton(frame.leftButton, "Previous", GoToPreviousStep)
        if GetRuntime() and GetRuntime().addedEntry then
            SetTutorialButton(frame.rightButton, "Next", function()
                AdvanceStep("entry_settings_intro")
            end)
        end
    elseif step == "entry_settings_intro" then
        SetTutorialButton(frame.leftButton, "Previous", GoToPreviousStep)
        SetTutorialButton(frame.rightButton, "Next", function()
            AdvanceStep("panel_settings_intro")
        end)
    elseif step == "panel_settings_intro" then
        SetTutorialButton(frame.leftButton, "Previous", GoToPreviousStep)
        SetTutorialButton(frame.rightButton, "Next", function()
            AdvanceStep("view_modes_intro")
        end)
    elseif step == "view_modes_intro" then
        SetTutorialButton(frame.leftButton, "Previous", GoToPreviousStep)
        SetTutorialButton(frame.rightButton, "Next", function()
            AdvanceStep("finish")
        end)
    elseif step == "finish" then
        SetTutorialButton(frame.leftButton, "Previous", GoToPreviousStep)
        SetTutorialButton(frame.rightButton, "Finish", CompleteTutorial)
    else
        SetTutorialButton(frame.leftButton, "Previous", GoToPreviousStep)
    end
end

local function UpdateHighlight(anchor)
    if not anchor then
        HideHighlight()
        return
    end

    local highlight = CS.tutorialHighlight
    if not highlight then
        return
    end
    highlight:ClearAllPoints()
    highlight:SetParent(UIParent)
    highlight:SetPoint("TOPLEFT", anchor, "TOPLEFT", -1, 1)
    highlight:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 1, -1)
    highlight:Show()
    if highlight._cdcGlow and ShowGlowStyle then
        ShowGlowStyle(highlight._cdcGlow, "solid", highlight, TUTORIAL_SOLID_GLOW_COLOR, {
            size = 3,
            defaultAlpha = 1,
        })
    end
end

local function PositionArrow(frame, placement)
    local arrow = frame and frame.arrow
    if not arrow then
        return
    end

    arrow:ClearAllPoints()
    RotateTexture(arrow.Arrow, 0)
    RotateTexture(arrow.Glow, 0)

    if placement == "above" then
        arrow:SetPoint("TOP", frame, "BOTTOM", 0, 3)
    elseif placement == "below" then
        arrow:SetPoint("BOTTOM", frame, "TOP", 0, -3)
        RotateTexture(arrow.Arrow, math_pi)
        RotateTexture(arrow.Glow, math_pi)
    elseif placement == "left" then
        arrow:SetPoint("LEFT", frame, "RIGHT", -3, 0)
        RotateTexture(arrow.Arrow, -math_pi / 2)
        RotateTexture(arrow.Glow, -math_pi / 2)
    elseif placement == "right" then
        arrow:SetPoint("RIGHT", frame, "LEFT", 3, 0)
        RotateTexture(arrow.Arrow, math_pi / 2)
        RotateTexture(arrow.Glow, math_pi / 2)
    else
        arrow:Hide()
        return
    end

    arrow:Show()
end

local function PositionFrame(frame, anchor, placement)
    frame:ClearAllPoints()

    if not anchor then
        local parent = (CS.configFrame and CS.configFrame.frame) or UIParent
        frame:SetPoint("CENTER", parent, "CENTER", 0, 0)
        if frame.arrow then
            frame.arrow:Hide()
        end
        HideHighlight()
        return
    end

    if placement == "center" then
        local parent = (CS.configFrame and CS.configFrame.frame) or UIParent
        frame:SetPoint("CENTER", parent, "CENTER", 0, 0)
    elseif placement == "above" then
        frame:SetPoint("BOTTOM", anchor, "TOP", 0, 18)
    elseif placement == "below" then
        frame:SetPoint("TOP", anchor, "BOTTOM", 0, -18)
    elseif placement == "left" then
        frame:SetPoint("RIGHT", anchor, "LEFT", -TUTORIAL_SIDE_PLACEMENT_OFFSET, 0)
    elseif placement == "right" then
        frame:SetPoint("LEFT", anchor, "RIGHT", TUTORIAL_SIDE_PLACEMENT_OFFSET, 0)
    else
        frame:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    end

    PositionArrow(frame, placement)
    UpdateHighlight(anchor)
end

local function ValidateRuntimeState()
    local runtime = GetRuntime()
    if not runtime then
        return
    end
end

local function RefreshTutorialPlacement()
    local runtime = GetRuntime()
    if not (runtime and runtime.active and IsConfigVisible()) then
        if CS.tutorialFrame then
            CS.tutorialFrame:Hide()
        end
        HideHighlight()
        return
    end

    ValidateRuntimeState()
    runtime = GetRuntime()
    if not runtime then
        return
    end

    local frame = EnsureTutorialFrame()
    if frame:GetParent() ~= CS.configFrame.frame then
        frame:SetParent(CS.configFrame.frame)
    end
    frame:SetFrameLevel(CS.configFrame.frame:GetFrameLevel() + 40)

    local step = runtime.step or "welcome"
    if step == "view_modes_intro" and CS.profileBar and CS.profileBar:IsShown() then
        CS.profileBar:Hide()
        if ST._RebuildTutorialAnchors then
            ST._RebuildTutorialAnchors()
        end
    end
    local data = STEP_DATA[step] or STEP_DATA.welcome
    local titleText = frame.titleText
    if titleText then
        titleText:SetText(data.title or "Tutorial")
    end
    frame.stepLabel:SetText(format("%d of %d", GetStepNumber(step), #STEP_ORDER))
    frame.bodyText:SetText(data.text or "")
    ConfigureButtonsForStep(frame, step)
    ResizeTutorialFrame(frame)

    local anchor = data.anchor and GetAnchor(data.anchor) or nil
    PositionFrame(frame, anchor, data.placement)
    frame:Show()
end

local function CancelFirstIconPanelTutorial(reason)
    local runtime = GetRuntime()
    if not runtime then
        return
    end

    CS.tutorialRuntime = nil
    if CS.tutorialFrame then
        CS.tutorialFrame:Hide()
    end
    HideHighlight()
end

local function RebuildTutorialAnchors()
    local anchors = CS.tutorialAnchors
    if not anchors then
        anchors = {}
        CS.tutorialAnchors = anchors
    end
    wipe(anchors)

    if CS.gearButton and CS.gearButton:IsShown() then
        anchors.gear_button = CS.gearButton
    end
    if CS.modeToggleButton and CS.modeToggleButton:IsShown() then
        anchors.mode_toggle_button = CS.modeToggleButton
    end

    if CS.configFrame and CS.configFrame.col1 and CS.configFrame.col1.frame then
        anchors.groups_column_area = CS.configFrame.col1.frame
    end
    if CS.configFrame and CS.configFrame.col2 and CS.configFrame.col2.frame then
        anchors.panels_column_area = CS.configFrame.col2.frame
    end

    local col1Widgets = CS.col1BarWidgets or {}
    local firstCol1Button = col1Widgets[1]
    if firstCol1Button and firstCol1Button.frame then
        anchors.new_group_button = firstCol1Button.frame
    end

    local col2Widgets = CS.col2BarWidgets or {}
    local firstCol2Button = col2Widgets[1]
    if firstCol2Button and firstCol2Button.frame and CS.col2ButtonBar and CS.col2ButtonBar:IsShown() then
        anchors.icon_panel_button = firstCol2Button.frame
    end

    local selectedPanelId = CS.selectedGroup
    local selectedPanelMeta
    for _, panelMeta in ipairs(CS.lastCol2PanelMetas or {}) do
        if panelMeta.panelId == selectedPanelId then
            selectedPanelMeta = panelMeta
            break
        end
    end

    if selectedPanelMeta then
        anchors.selected_panel_area = selectedPanelMeta.panelFrame or selectedPanelMeta.headerFrame
        anchors.selected_panel_add_row = selectedPanelMeta.addRowFrame
        anchors.selected_panel_add_input = selectedPanelMeta.addInputFrame
        anchors.selected_panel_manual_add_button = selectedPanelMeta.manualAddButtonFrame
    end

    if CS.configFrame and CS.configFrame.col3 and CS.configFrame.col3.frame then
        anchors.col3_area = CS.configFrame.col3.frame
    end
    if CS.configFrame and CS.configFrame.col4 and CS.configFrame.col4.frame then
        anchors.col4_area = CS.configFrame.col4.frame
    end
end

local function StartFirstIconPanelTutorial(isReplay)
    if not IsConfigVisible() then
        return false
    end

    NormalizeTutorialContext()

    CS.tutorialRuntime = {
        active = true,
        isReplay = isReplay == true,
        step = "welcome",
        createdGroup = false,
        createdPanel = false,
        addedEntry = false,
    }

    RebuildTutorialAnchors()
    RefreshTutorialPlacement()
    return true
end

local function MaybeAutoStartFirstIconPanelTutorial()
    if not IsConfigVisible() or IsTutorialActive() then
        return false
    end

    local state = GetTutorialState()
    if not state then
        return false
    end
    if state.completed or state.dismissed or state.lastVersionSeen ~= nil then
        return false
    end
    if ProfileHasExistingSetup() then
        return false
    end

    state.lastVersionSeen = GetAddonVersion()
    return StartFirstIconPanelTutorial(false)
end

local function NotifyTutorialAction(action, payload)
    local runtime = GetRuntime()
    if not (runtime and runtime.active) then
        return
    end

    if action == "group_created" and (runtime.step == "welcome" or runtime.step == "groups_column_intro" or runtime.step == "create_group") then
        runtime.createdGroup = true
        CS.selectedButton = nil
        wipe(CS.selectedButtons)
        wipe(CS.selectedPanels)
        wipe(CS.selectedGroups)
        AdvanceStep("panels_column_intro")
    elseif action == "panel_created" and (runtime.step == "panels_column_intro" or runtime.step == "create_panel") then
        if payload and payload.displayMode == "icons" then
            runtime.createdPanel = true
            CS.selectedButton = nil
            wipe(CS.selectedButtons)
            wipe(CS.selectedPanels)
            wipe(CS.selectedGroups)
            AdvanceStep("panel_area_intro")
        end
    elseif action == "inline_add_succeeded" and (runtime.step == "panel_area_intro" or runtime.step == "add_one_spell") then
        if payload and payload.groupId and payload.buttonIndex then
            runtime.addedEntry = true
            CS.selectedGroup = payload.groupId
            CS.selectedButton = payload.buttonIndex
            wipe(CS.selectedButtons)
            wipe(CS.selectedPanels)
            wipe(CS.selectedGroups)
            AdvanceStep("entry_settings_intro")
        end
    end
end

ST._MaybeAutoStartFirstIconPanelTutorial = MaybeAutoStartFirstIconPanelTutorial
ST._StartFirstIconPanelTutorial = StartFirstIconPanelTutorial
ST._CancelFirstIconPanelTutorial = CancelFirstIconPanelTutorial
ST._NotifyTutorialAction = NotifyTutorialAction
ST._RebuildTutorialAnchors = RebuildTutorialAnchors
ST._RefreshTutorialPlacement = RefreshTutorialPlacement
