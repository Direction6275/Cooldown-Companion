--[[
    CooldownCompanion - Core/ConfigLoader.lua: load-on-demand config addon bridge
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local pairs = pairs
local tostring = tostring
local type = type
local next = next

local CONFIG_ADDON_NAME = ADDON_NAME .. "_Config"
local SETTINGS_CATEGORY_NAME = "Cooldown Companion"
local SETTINGS_LAUNCHER_TEXT = "Open Cooldown Companion"

local function SetConfigPrimaryModeWrapper(mode, opts)
    if ST._SetConfigPrimaryModeImpl then
        return ST._SetConfigPrimaryModeImpl(mode, opts)
    end

    local CS = ST._configState
    if CS then
        CS.resourceBarPanelActive = (mode == "bars")
    end
end

-- Keep the wrapper stable so early hooksecurefunc callers continue to observe
-- mode switches after the lazy config addon installs the real implementation.
ST._SetConfigPrimaryMode = ST._SetConfigPrimaryMode or SetConfigPrimaryModeWrapper

function CooldownCompanion:IsConfigLoaded()
    if self._configAddonLoaded then
        return true
    end

    if C_AddOns and C_AddOns.IsAddOnLoaded then
        local _, loaded = C_AddOns.IsAddOnLoaded(CONFIG_ADDON_NAME)
        if loaded then
            self._configAddonLoaded = true
            return true
        end
    end

    return false
end

local function FormatConfigLoadFailure(entryPoint, reason)
    local source = entryPoint and tostring(entryPoint) or "config"
    local detail = reason and tostring(reason) or "unknown error"
    return "Cannot open Cooldown Companion config from " .. source
        .. ": " .. detail .. ". Make sure " .. CONFIG_ADDON_NAME .. " is installed and enabled."
end

StaticPopupDialogs["CDC_RESET_PROFILE"] = {
    text = "Reset profile '%s' to default settings?",
    button1 = "Reset",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if data and data.profileName and CooldownCompanion.db then
            CooldownCompanion.db:ResetProfile()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function CloseBlizzardSettings()
    if SettingsPanel and SettingsPanel.Close then
        SettingsPanel:Close(true)
    elseif Settings and Settings.CloseUI then
        Settings.CloseUI()
    elseif InterfaceOptionsFrame then
        InterfaceOptionsFrame:Hide()
    end
end

function CooldownCompanion:LoadConfigAddon(entryPoint)
    if not self:IsConfigLoaded() then
        if not (C_AddOns and C_AddOns.LoadAddOn) then
            self:Print(FormatConfigLoadFailure(entryPoint, "LoadAddOn unavailable"))
            return false
        end

        local loaded, reason = C_AddOns.LoadAddOn(CONFIG_ADDON_NAME)
        if not loaded then
            self:Print(FormatConfigLoadFailure(entryPoint, reason))
            return false
        end
        self._configAddonLoaded = true
    end

    if not self._configToggleImpl then
        self:Print(FormatConfigLoadFailure(entryPoint, "config addon did not initialize"))
        return false
    end
    return true
end

local function QueueConfigIntent(addon, intent)
    addon._pendingConfigIntent = intent
    addon:Print("Config will open after combat ends.")
end

local function GetConfigFrameIfLoaded(addon)
    if addon._configGetFrameImpl then
        return addon:_configGetFrameImpl()
    end
    return nil
end

local function EnsureConfigOpen(addon)
    local configFrame = GetConfigFrameIfLoaded(addon)
    if configFrame and configFrame._miniFrame and configFrame._miniFrame:IsShown() then
        configFrame._miniFrame:Hide()
    end
    if not configFrame or not configFrame.frame:IsShown() then
        if not addon._configToggleImpl then
            return false
        end
        addon:_configToggleImpl()
    end
    return true
end

function CooldownCompanion:RunConfigIntent(intent)
    intent = intent or {}
    local entryPoint = intent.entryPoint or "config"

    if InCombatLockdown and InCombatLockdown() then
        QueueConfigIntent(self, intent)
        return false
    end

    if intent.action == "reset" then
        local profileName = self.db:GetCurrentProfile()
        if self:IsConfigLoaded() and ST._ShowPopupAboveConfig then
            ST._ShowPopupAboveConfig("CDC_RESET_PROFILE", profileName, { profileName = profileName })
        else
            StaticPopup_Show("CDC_RESET_PROFILE", profileName, nil, { profileName = profileName })
        end
        return true
    end

    if not self:LoadConfigAddon(entryPoint) then
        return false
    end

    if intent.closeSettings then
        CloseBlizzardSettings()
    end

    if intent.action == "open" then
        if not EnsureConfigOpen(self) then
            self:Print(FormatConfigLoadFailure(entryPoint, "config panel unavailable"))
            return false
        end
        return true
    elseif intent.action == "debugimport" then
        if self._configOpenDiagnosticDecodePanelImpl then
            self:_configOpenDiagnosticDecodePanelImpl()
            return true
        end
        self:Print(FormatConfigLoadFailure(entryPoint, "diagnostic panel unavailable"))
        return false
    end

    if not self._configToggleImpl then
        self:Print(FormatConfigLoadFailure(entryPoint, "config panel unavailable"))
        return false
    end
    self:_configToggleImpl()
    return true
end

function CooldownCompanion:ToggleConfig(intent)
    if type(intent) ~= "table" then
        intent = {
            action = "toggle",
            entryPoint = "config",
        }
    else
        intent.action = intent.action or "toggle"
        intent.entryPoint = intent.entryPoint or "config"
    end

    return self:RunConfigIntent(intent)
end

function CooldownCompanion:RefreshConfigPanel()
    if self._configRefreshPanelImpl then
        return self:_configRefreshPanelImpl()
    end
end

function CooldownCompanion:GetConfigFrame()
    return GetConfigFrameIfLoaded(self)
end

function CooldownCompanion:OpenDiagnosticDecodePanel()
    return self:RunConfigIntent({
        action = "debugimport",
        entryPoint = "/cdc debugimport",
    })
end

function CooldownCompanion:ShowResetProfilePopup()
    return self:RunConfigIntent({
        action = "reset",
        entryPoint = "/cdc reset",
    })
end

local function ResetLoadedConfigForProfileChange(addon)
    if addon._configResetForProfileChangeImpl then
        addon:_configResetForProfileChangeImpl()
    end
end

local function RestampCharacterScopedProfileOwnership(addon)
    local db = addon.db
    local profile = db and db.profile
    local charKey = db and db.keys and db.keys.char
    if not (profile and charKey) then return end

    if profile.groups then
        for _, group in pairs(profile.groups) do
            if not group.isGlobal then
                group.createdBy = charKey
            end
        end
    end
    if profile.groupContainers then
        for _, container in pairs(profile.groupContainers) do
            if not container.isGlobal then
                container.createdBy = charKey
            end
        end
    end
end

local function RunProfileMigrationAndRefresh(addon, reason)
    if not addon:RunAllMigrations() then
        addon:ClearUnsupportedProfileRuntime()
        addon:RefreshConfigPanel()
        return
    end

    addon:RefreshConfigPanel()
    addon:RefreshAllGroups()
    if addon.EvaluateBarsAndFramesRuntime then
        addon:EvaluateBarsAndFramesRuntime(reason)
    end
end

local function CreateSettingsLauncherFrame(addon)
    local frame = CreateFrame("Frame")
    frame.name = SETTINGS_CATEGORY_NAME

    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(SETTINGS_CATEGORY_NAME)

    local description = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    description:SetJustifyH("LEFT")
    description:SetText("Open the Cooldown Companion configuration panel.")
    description:SetWidth(520)

    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -16)
    if button.SetTextToFit then
        button:SetTextToFit(SETTINGS_LAUNCHER_TEXT)
    else
        button:SetText(SETTINGS_LAUNCHER_TEXT)
        button:SetWidth(190)
    end
    button:SetHeight(24)
    button:SetScript("OnClick", function()
        addon:ToggleConfig({
            action = "open",
            entryPoint = "Blizzard Settings",
            closeSettings = true,
        })
    end)

    return frame
end

local function RegisterSettingsLauncher(addon)
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
        return
    end

    local frame = CreateSettingsLauncherFrame(addon)
    local category = Settings.RegisterCanvasLayoutCategory(frame, SETTINGS_CATEGORY_NAME)
    if category then
        Settings.RegisterAddOnCategory(category)
        if category.GetID then
            addon._settingsCategoryID = category:GetID()
        else
            addon._settingsCategoryID = category.ID
        end
    end
end

function CooldownCompanion:SetupConfig()
    if self._configSetupDone then
        return
    end
    self._configSetupDone = true

    RegisterSettingsLauncher(self)

    self.db.RegisterCallback(self, "OnProfileChanged", function(db, profileName)
        ResetLoadedConfigForProfileChange(CooldownCompanion)
        local rawProfile = db and db.sv and type(db.sv.profiles) == "table" and db.sv.profiles[profileName]
        if type(rawProfile) ~= "table" or next(rawProfile) == nil then
            CooldownCompanion._allowMissingMigrationCheckpointOnce = true
        end
        RunProfileMigrationAndRefresh(CooldownCompanion, "profile-changed")
    end)
    self.db.RegisterCallback(self, "OnProfileCopied", function()
        ResetLoadedConfigForProfileChange(CooldownCompanion)

        if CooldownCompanion.MigrateFoldersIntoGroups then
            -- Flatten compatibility Folders before copied character-scoped
            -- entities are restamped to the current character.
            CooldownCompanion:MigrateFoldersIntoGroups(CooldownCompanion.db and CooldownCompanion.db.profile)
        end

        local suppress = CooldownCompanion._suppressOwnershipRestamp
        CooldownCompanion._suppressOwnershipRestamp = nil
        if not suppress then
            RestampCharacterScopedProfileOwnership(CooldownCompanion)
        end

        RunProfileMigrationAndRefresh(CooldownCompanion, "profile-copied")
    end)
    self.db.RegisterCallback(self, "OnProfileReset", function()
        ResetLoadedConfigForProfileChange(CooldownCompanion)
        CooldownCompanion._allowMissingMigrationCheckpointOnce = true
        RunProfileMigrationAndRefresh(CooldownCompanion, "profile-reset")
    end)
    self.db.RegisterCallback(self, "OnProfileDeleted", function()
        CooldownCompanion:RefreshConfigPanel()
    end)
end

function CooldownCompanion:OpenPendingConfigIntent()
    local intent = self._pendingConfigIntent
    self._pendingConfigIntent = nil
    return self:ToggleConfig(intent or {
        action = "toggle",
        entryPoint = "combat deferred",
    })
end
