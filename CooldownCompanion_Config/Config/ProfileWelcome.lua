-- First-profile landing surface. Uses the existing creation and module routes;
-- its disclosure state belongs to this config frame, never to SavedVariables.
local _, ST = ...
local Addon = ST.Addon
local CS = ST._configState
local AceGUI = LibStub("AceGUI-3.0")

local function IsProfileWelcomeEligible()
    local profile = Addon.db and Addon.db.profile
    if not profile or Addon._unsupportedLegacyProfile
        or next(profile.groupContainers or {}) or next(profile.groups or {}) then
        return false
    end
    if CS.importMode or CS.exportMode
        or CS.talentPickerMode or CS.otherClassLibraryActive then
        return false
    end
    -- Do not cover the existing Resources migration/recovery gate.
    if Addon:GetCurrentResourceBarConflict() then return false end
    local resources = Addon:GetResourceBarSettings()
    local cast = Addon:GetCastBarSettings()
    local frames = Addon:GetFrameAnchoringSettings()
    if not resources or not cast or not frames then return false end
    return resources.enabled ~= true and cast.enabled ~= true and frames.enabled ~= true
end

local function LayoutWelcome(pane)
    local width = math.max(120, math.min(560, pane:GetWidth() - 64))
    pane.heading:SetWidth(width)
    pane.body:SetWidth(width)
    pane.create:SetWidth(math.min(220, width))
    pane.disclosure:SetWidth(math.min(240, width))
    pane.disclosure:SetText(pane.expanded and "Optional Modules  -" or "Optional Modules  +")
    pane.disclosure:SetHeight(24)
    for _, button in ipairs(pane.modules) do
        button:SetWidth(math.min(260, width))
        button.frame:SetShown(pane.expanded == true)
    end
    local total = pane.heading:GetStringHeight() + 14 + pane.body:GetStringHeight()
        + 24 + 30 + 14 + 24 + (pane.expanded and 114 or 0)
    pane.heading:ClearAllPoints()
    pane.heading:SetPoint("TOP", pane, "TOP", 0, -math.max(12, (pane:GetHeight() - total) * 0.5))
end

local function CreateWelcome(parent)
    local shell = AceGUI:Create("InlineGroup")
    shell:SetTitle("Get Started")
    shell:SetAutoAdjustHeight(false)
    shell:SetLayout(nil)
    shell.frame:SetParent(parent)
    shell.frame:ClearAllPoints()
    shell.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)

    local pane = CreateFrame("Frame", nil, shell.content)
    pane:SetPoint("TOPLEFT", shell.content, "TOPLEFT", 0, 0)
    pane:SetPoint("BOTTOMRIGHT", shell.content, "BOTTOMRIGHT", 0, 0)
    pane.heading = pane:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    pane.heading:SetJustifyH("CENTER")
    pane.heading:SetText("Create your first group")
    pane.body = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    pane.body:SetJustifyH("CENTER")
    pane.body:SetSpacing(3)
    pane.body:SetTextColor(0.7, 0.7, 0.7)
    pane.body:SetText("Keep related cooldowns and auras together.\nStart with a group, then choose how to display them.")
    pane.body:SetPoint("TOP", pane.heading, "BOTTOM", 0, -14)

    pane.create = AceGUI:Create("Button")
    pane.create:SetText("New Group")
    pane.create:SetHeight(30)
    pane.create.frame:SetParent(pane)
    pane.create.frame:SetPoint("TOP", pane.body, "BOTTOM", 0, -24)
    pane.create:SetCallback("OnClick", ST._CreateConfigGroup)
    pane.create.frame:Show()

    pane.disclosure = AceGUI:Create("InteractiveLabel")
    pane.disclosure:SetFontObject(GameFontHighlight)
    pane.disclosure:SetJustifyH("CENTER")
    pane.disclosure:SetColor(0.7, 0.7, 0.7)
    pane.disclosure.frame:SetParent(pane)
    pane.disclosure.frame:SetPoint("TOP", pane.create.frame, "BOTTOM", 0, -14)
    pane.disclosure.frame:Show()
    pane.disclosure:SetCallback("OnClick", function(_, _, button)
        if button ~= "LeftButton" then return end
        pane.expanded = not pane.expanded
        LayoutWelcome(pane)
    end)

    pane.modules = {}
    local previous = pane.disclosure.frame
    for _, definition in ipairs({
        { "resources", "Resource Bars" },
        { "castbar", "Cast Bar" },
        { "player", "Unit Frame Anchoring" },
    }) do
        local kind = definition[1]
        local button = AceGUI:Create("Button")
        button:SetText(definition[2])
        button:SetHeight(30)
        button.frame:SetParent(pane)
        button.frame:SetPoint("TOP", previous, "BOTTOM", 0, -8)
        button:SetCallback("OnClick", function()
            ST._OpenBarWorkspace(kind)
            Addon:RefreshConfigPanel()
        end)
        pane.modules[#pane.modules + 1] = button
        previous = button.frame
    end
    pane:SetScript("OnSizeChanged", LayoutWelcome)
    shell.pane = pane
    return shell
end

local function UpdateProfileWelcome(frame)
    -- An explicitly opened disabled module must retain its enable/settings page.
    local show = not CS.barsEntrySelected and IsProfileWelcomeEligible()
    local shell = frame.profileWelcome
    if show then
        if not shell then
            shell = CreateWelcome(frame.colParent)
            frame.profileWelcome = shell
        end
        if shell.profile ~= Addon.db.profile then
            shell.profile = Addon.db.profile
            shell.pane.expanded = false
        end
        shell.frame:SetSize(frame.colParent:GetWidth(), frame.colParent:GetHeight())
        shell.frame:Show()
        LayoutWelcome(shell.pane)
    elseif shell then
        shell.frame:Hide()
        shell.pane.expanded = false
    end
    frame.col1.frame:SetShown(not show)
    frame.col3.frame:SetShown(not show)
    return show
end

ST._IsProfileWelcomeEligible = IsProfileWelcomeEligible
ST._UpdateProfileWelcome = UpdateProfileWelcome
