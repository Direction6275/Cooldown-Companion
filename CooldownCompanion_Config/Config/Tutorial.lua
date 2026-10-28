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
local ResetConfigSelection = ST._ResetConfigSelection
local ClearConfigButtonSelection = ST._ClearConfigButtonSelection
local ClearConfigPanelMultiSelection = ST._ClearConfigPanelMultiSelection
local ClearConfigContainerMultiSelection = ST._ClearConfigContainerMultiSelection

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
    "add_one_spell",
    "entry_settings_intro",
    "panel_settings_intro",
    "finish",
}

local STEP_INDEX = {}
for index, step in ipairs(STEP_ORDER) do
    STEP_INDEX[step] = index
end

local STEP_DATA = {
    welcome = {
        title = "First Panel",
        text = "This tutorial will walk you through adding a single spell to track and explain some basics about the add-on along the way.",
        placement = "center",
    },
    groups_column_intro = {
        title = "Groups",
        text = "Groups organize related panels and are shared by characters of the same class by default. The Navigator lists each group with the panels inside it.",
        anchor = "groups_column_area",
        placement = "right",
    },
    create_group = {
        title = "Create a Group",
        text = "Click New Group.",
        anchor = "new_group_button",
        placement = "above",
        gate = "createdGroup",
    },
    panels_column_intro = {
        title = "Panels in the Navigator",
        text = "Panels live inside groups and contain the things you want to track, like spells and items. A panel's type determines how those entries are displayed.",
        anchor = "panels_column_area",
        placement = "right",
    },
    create_panel = {
        title = "Create a Panel",
        text = "Click Panel to create your first panel.",
        anchor = "empty_state_icon_button",
        placement = "above",
        gate = "createdPanel",
    },
    add_one_spell = {
        title = "Add Your First Ability",
        text = "This is an empty icon panel. Let's add something to track.\n\nType the name of a spell your character can use in the edit box.\n\nAs you type, the addon will attempt to help you narrow down what you're looking for. Add the spell by clicking on it in the dropdown or using arrow keys + Enter. Add as, at the bottom of the dropdown, chooses whether it shows as an icon or a bar.",
        anchor = "selected_panel_add_input",
        placement = "right",
        gate = "addedEntry",
    },
    entry_settings_intro = {
        title = "Entry Settings",
        text = "The Live Preview shows your panel. Click an entry in it to select it, and this column shows that entry's settings: cooldown settings, sound alerts, and more.",
        anchor = "settings_column_area",
        placement = "left",
    },
    panel_settings_intro = {
        title = "Panel Settings",
        text = "With an entry selected, the styling tabs show that entry's values. Each section reads Panel setting until Customize gives the entry its own copy, and Revert hands it back.\n\nClick a setting name or its |A:QuestLog-icon-setting:14:14|a to expand options directly below it. The checkbox turns the feature on or off.",
        anchor = "settings_column_area",
        placement = "left",
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
    titleText:SetText("First Panel")
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
    local rightButton = CreateActionButton(110)
    leftButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 10)
    rightButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 10)
    frame.leftButton = leftButton
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

    -- ST._ form: the local cancel function is declared further down this
    -- file, and its ST field is assigned at load, before any click.
    closeButton:SetScript("OnClick", function()
        ST._CancelFirstIconPanelTutorial("close_button")
    end)

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
    -- The tutorial walks the normal workspace; leave every side mode.
    if CS.exportMode and ST._ExitExportMode then
        ST._ExitExportMode({ skipRefresh = true })
    end
    if CS.importMode and ST._ExitImportMode then
        ST._ExitImportMode({ skipRefresh = true })
    end
    if CS.copyCustomization and ST._CancelCopyCustomization then
        ST._CancelCopyCustomization({ skipRefresh = true })
    end
    if CS.copyPanelSettings and ST._CancelCopyPanelSettings then
        ST._CancelCopyPanelSettings({ skipRefresh = true })
    end
    if CS.CloseSpellbookPanel then
        CS.CloseSpellbookPanel()
    end

    CloseDropDownMenus()
    if CS.HideAutocomplete then
        CS.HideAutocomplete()
    end

    ResetConfigSelection(true)
    CS.pendingEditBoxFocus = false

    if ST._SetConfigPrimaryMode then
        ST._SetConfigPrimaryMode("buttons", { skipRefresh = true })
    end

    CooldownCompanion:RefreshConfigPanel()
end

local function ConfigureButtonsForStep(frame, step)
    ResetTutorialButton(frame.leftButton)
    ResetTutorialButton(frame.rightButton)

    -- Buttons follow STEP_ORDER. A step with a gate offers Next only once its
    -- runtime flag is set; an unknown step offers Previous alone.
    local index = STEP_INDEX[step]
    if index == 1 then
        SetTutorialButton(frame.leftButton, "Skip", DismissTutorial)
    else
        SetTutorialButton(frame.leftButton, "Previous", GoToPreviousStep)
    end
    if not index then return end
    if index == #STEP_ORDER then
        SetTutorialButton(frame.rightButton, "Finish", CompleteTutorial)
        return
    end
    local gate = STEP_DATA[step].gate
    local runtime = GetRuntime()
    if not gate or (runtime and runtime[gate]) then
        local nextStep = STEP_ORDER[index + 1]
        SetTutorialButton(frame.rightButton, "Next", function()
            AdvanceStep(nextStep)
        end)
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

local function RefreshTutorialPlacement()
    local runtime = GetRuntime()
    if not (runtime and runtime.active and IsConfigVisible()) then
        if CS.tutorialFrame then
            CS.tutorialFrame:Hide()
        end
        HideHighlight()
        return
    end

    local frame = EnsureTutorialFrame()
    if frame:GetParent() ~= CS.configFrame.frame then
        frame:SetParent(CS.configFrame.frame)
    end
    frame:SetFrameLevel(CS.configFrame.frame:GetFrameLevel() + 40)

    local step = runtime.step or "welcome"
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

    -- Both empty-picker views dim non-icon choices during the tutorial.
    -- Templates have no tutorial anchor, but still need their appearance reset.
    if ST._IsEmptyGroupPickerVisible and ST._IsEmptyGroupPickerVisible() then
        CooldownCompanion:RefreshConfigPanel()
    end
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

    -- The Get Started card stands in for the Navigator on an empty profile,
    -- which is exactly when the tutorial starts on its own.
    local welcome = CS.configFrame and CS.configFrame.profileWelcome
    local col1Frame = CS.configFrame and CS.configFrame.col1 and CS.configFrame.col1.frame
    if welcome and welcome.frame:IsShown() then
        anchors.groups_column_area = welcome.pane
    elseif col1Frame then
        anchors.groups_column_area = col1Frame
    end
    if col1Frame then
        anchors.panels_column_area = col1Frame
    end

    -- Named handle, not a bar position: Browse Other Classes swaps the New
    -- Group button out for its own toggle, and only the named field goes nil
    -- there.
    local createButton = welcome and welcome.frame:IsShown() and welcome.pane.create
        or CS.col1CreateButton
    if createButton and createButton.frame then
        anchors.new_group_button = createButton.frame
    end
    -- The empty state's Icon Panel card exists only while the Group overview is
    -- on screen for an empty Group that can take a new Panel. Anywhere else the
    -- anchor stays unset, which centers the tutorial box with no highlight
    -- instead of pointing at the wrong control.
    local emptyStateIconCard = ST._GetEmptyPickerCardFrame
        and ST._GetEmptyPickerCardFrame("icons")
    if emptyStateIconCard then
        anchors.empty_state_icon_button = emptyStateIconCard
    end

    local selectedPanelId = CS.selectedGroup
    local selectedPanelRow
    for _, row in ipairs(CS.lastCol1RenderedRows or {}) do
        if row.rowType == "panel" and row.id == selectedPanelId then
            selectedPanelRow = row
            break
        end
    end

    if selectedPanelRow then
        local col3 = CS.configFrame and CS.configFrame.col3
        local addBox = col3 and col3.buttonsAddBox
        if addBox and addBox.frame and addBox.frame:IsShown() then
            anchors.selected_panel_add_input = addBox.frame
        end
    end

    local settingsColumn = CS.configFrame and CS.configFrame.col3 and CS.configFrame.col3._cdcSettingsColumn
    if settingsColumn and settingsColumn.frame then
        anchors.settings_column_area = settingsColumn.frame
    end
end

local function StartFirstIconPanelTutorial()
    if not IsConfigVisible() then
        return false
    end

    NormalizeTutorialContext()

    CS.tutorialRuntime = {
        active = true,
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
    return StartFirstIconPanelTutorial()
end

local function NotifyTutorialAction(action, payload)
    local runtime = GetRuntime()
    if not (runtime and runtime.active) then
        return
    end

    if action == "group_created" and (runtime.step == "welcome" or runtime.step == "groups_column_intro" or runtime.step == "create_group") then
        runtime.createdGroup = true
        ClearConfigButtonSelection()
        ClearConfigPanelMultiSelection()
        ClearConfigContainerMultiSelection()
        AdvanceStep("panels_column_intro")
    elseif action == "panel_created" and (runtime.step == "panels_column_intro" or runtime.step == "create_panel") then
        if payload and payload.displayMode == "icons" then
            runtime.createdPanel = true
            ClearConfigButtonSelection()
            ClearConfigPanelMultiSelection()
            ClearConfigContainerMultiSelection()
            AdvanceStep("add_one_spell")
        end
    elseif action == "inline_add_succeeded" and runtime.step == "add_one_spell" then
        -- The add already selected the new entry: CompleteAdd notifies only then.
        if payload and payload.groupId and payload.buttonIndex then
            runtime.addedEntry = true
            AdvanceStep("entry_settings_intro")
        end
    end
end

-- The empty picker's non-icon create cards stand down while this is true, so
-- the guided first-panel path cannot dead-end: creating any other panel type
-- removes the picker (the create_panel step's anchor) without advancing the
-- tutorial.
local function IsTutorialAwaitingIconPanel()
    local runtime = GetRuntime()
    return (runtime and runtime.active
        and (runtime.step == "panels_column_intro" or runtime.step == "create_panel")) == true
end

ST._IsTutorialAwaitingIconPanel = IsTutorialAwaitingIconPanel
ST._MaybeAutoStartFirstIconPanelTutorial = MaybeAutoStartFirstIconPanelTutorial
ST._StartFirstIconPanelTutorial = StartFirstIconPanelTutorial
ST._CancelFirstIconPanelTutorial = CancelFirstIconPanelTutorial
ST._NotifyTutorialAction = NotifyTutorialAction
ST._RebuildTutorialAnchors = RebuildTutorialAnchors
ST._RefreshTutorialPlacement = RefreshTutorialPlacement
