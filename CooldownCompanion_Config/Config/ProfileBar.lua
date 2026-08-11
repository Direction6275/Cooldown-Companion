--[[
    CooldownCompanion - Config/ProfileBar
    RefreshProfileBar (the profile dropdown + action buttons above the
    surfaces). Every view now uses the unified workspace.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local AceGUI = LibStub("AceGUI-3.0")

-- Imports from earlier Config/ files
local ShowPopupAboveConfig = ST._ShowPopupAboveConfig
local ResetConfigSelection = ST._ResetConfigSelection

local function RefreshProfileBar(bar)
    -- Release tracked AceGUI widgets
    for _, widget in ipairs(CS.profileBarAceWidgets) do
        widget:Release()
    end
    wipe(CS.profileBarAceWidgets)

    local db = CooldownCompanion.db
    local profiles = db:GetProfiles()
    local currentProfile = db:GetCurrentProfile()

    -- Build ordered profile list for AceGUI Dropdown
    local profileList = {}
    for _, name in ipairs(profiles) do
        profileList[name] = name
    end

    -- Profile dropdown (no label, compact)
    local profileDrop = AceGUI:Create("Dropdown")
    profileDrop:SetLabel("")
    profileDrop:SetList(profileList, profiles)
    profileDrop:SetValue(currentProfile)
    profileDrop:SetWidth(150)
    profileDrop:SetCallback("OnValueChanged", function(widget, event, val)
        db:SetProfile(val)
        ResetConfigSelection(true)
        CooldownCompanion:RefreshConfigPanel()
        CooldownCompanion:RefreshAllGroups()
    end)
    profileDrop.frame:SetParent(bar)
    profileDrop.frame:ClearAllPoints()
    profileDrop.frame:SetPoint("LEFT", bar, "LEFT", 0, 0)
    profileDrop.frame:Show()
    table.insert(CS.profileBarAceWidgets, profileDrop)

    -- Helper to create horizontally chained buttons
    local lastAnchor = profileDrop.frame
    local createdButtons = {}
    local PROFILE_BAR_BUTTON_MIN_WIDTH = 55
    local PROFILE_BAR_BUTTON_EXTRA_PADDING = 8
    local PROFILE_BAR_BUTTON_TRUNCATION_STEP = 4
    local PROFILE_BAR_BUTTON_TRUNCATION_MAX_WIDTH = 220
    local function AddBarButton(text, onClick)
        local btn = AceGUI:Create("Button")
        btn:SetText(text)
        btn:SetAutoWidth(true)
        btn:SetCallback("OnClick", onClick)
        btn.frame:SetParent(bar)
        btn.frame:ClearAllPoints()
        btn.frame:SetPoint("LEFT", lastAnchor, "RIGHT", 4, 0)
        btn:SetHeight(22)
        local measuredWidth = btn.frame:GetWidth() or 0
        local desiredWidth = math.max(PROFILE_BAR_BUTTON_MIN_WIDTH, measuredWidth + PROFILE_BAR_BUTTON_EXTRA_PADDING)
        btn:SetWidth(desiredWidth)
        btn.frame:Show()
        table.insert(CS.profileBarAceWidgets, btn)
        table.insert(createdButtons, btn)
        lastAnchor = btn.frame
        return btn
    end

    AddBarButton("New", function()
        ShowPopupAboveConfig("CDC_NEW_PROFILE")
    end)

    AddBarButton("Rename", function()
        ShowPopupAboveConfig("CDC_RENAME_PROFILE", currentProfile, { oldName = currentProfile })
    end)

    AddBarButton("Duplicate", function()
        ShowPopupAboveConfig("CDC_DUPLICATE_PROFILE", nil, { source = currentProfile })
    end)

    AddBarButton("Delete", function()
        local allProfiles = db:GetProfiles()
        local isOnly = #allProfiles <= 1
        if isOnly then
            ShowPopupAboveConfig("CDC_RESET_PROFILE", currentProfile, { profileName = currentProfile, isOnly = true })
        else
            ShowPopupAboveConfig("CDC_DELETE_PROFILE", currentProfile, { profileName = currentProfile })
        end
    end)

    AddBarButton("Export Backup", function()
        ShowPopupAboveConfig("CDC_EXPORT_PROFILE")
    end)

    -- Keep widening while text truncates so skin/font variations don't clip labels.
    for _, btn in ipairs(createdButtons) do
        local fontString = btn.frame.GetFontString and btn.frame:GetFontString() or nil
        if fontString and fontString.IsTruncated and fontString:IsTruncated() then
            local width = btn.frame:GetWidth() or PROFILE_BAR_BUTTON_MIN_WIDTH
            while width < PROFILE_BAR_BUTTON_TRUNCATION_MAX_WIDTH and fontString:IsTruncated() do
                width = math.min(PROFILE_BAR_BUTTON_TRUNCATION_MAX_WIDTH, width + PROFILE_BAR_BUTTON_TRUNCATION_STEP)
                btn:SetWidth(width)
            end
        end
    end
end

------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
ST._RefreshProfileBar = RefreshProfileBar
