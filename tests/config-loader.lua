local function AssertEqual(actual, expected, message)
    assert(actual == expected, ("%s (expected %s, got %s)"):format(message, tostring(expected), tostring(actual)))
end

local function AssertContains(text, needle, message)
    assert(type(text) == "string" and text:find(needle, 1, true), message .. " (missing " .. needle .. ")")
end

local function ReadFile(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local function FileExists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

local function ParseTocEntries(text)
    local entries = {}
    for line in text:gmatch("[^\r\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= "" and not trimmed:match("^#") then
            entries[#entries + 1] = trimmed
        end
    end
    return entries
end

local function AssertListEqual(actual, expected, message)
    AssertEqual(#actual, #expected, message .. " count")
    for index, expectedValue in ipairs(expected) do
        AssertEqual(actual[index], expectedValue, message .. " entry " .. index)
    end
end

local function NewHarness()
    local records = {
        prints = {},
        loadCalls = {},
        toggleCount = 0,
        refreshCount = 0,
        diagnosticCount = 0,
        resetConfigCount = 0,
        resetProfileCount = 0,
        popupCount = 0,
        popupHelperCount = 0,
        modeCalls = {},
        settingsClosed = false,
        settingsPanelClosed = false,
        settingsPanelCloseSkipTransition = nil,
        options = nil,
        minimap = nil,
    }

    local inCombat = false
    local failLoad = false
    local failReason = "MISSING"
    local loadWithoutImpl = false
    local loadingAddon = false
    local migrationsOk = true
    local frameShown = false
    local miniShown = false

    _G.CooldownCompanion = nil
    _G.CooldownCompanionDB = nil
    _G.StaticPopupDialogs = {}

    function wipe(tbl)
        if not tbl then return end
        for key in pairs(tbl) do
            tbl[key] = nil
        end
    end

    function InCombatLockdown()
        return inCombat
    end

    Settings = {}
    SettingsPanel = {
        Close = function(_, skipTransitionBackToOpeningPanel)
            records.settingsPanelClosed = true
            records.settingsPanelCloseSkipTransition = skipTransitionBackToOpeningPanel
        end,
    }
    InterfaceOptionsFrame = {
        Hide = function()
            records.interfaceOptionsHidden = true
        end,
    }

    C_Timer = {
        After = function(_, callback)
            callback()
        end,
    }

    function CreateFrame()
        local frame = {
            scripts = {},
        }
        function frame:SetScript(scriptName, callback)
            self.scripts[scriptName] = callback
        end
        function frame:GetScript(scriptName)
            return self.scripts[scriptName]
        end
        function frame:RegisterEvent() end
        function frame:UnregisterEvent() end
        function frame:UnregisterAllEvents() end
        return frame
    end

    function StaticPopup_Show(name, text, unused, data)
        records.popupCount = records.popupCount + 1
        records.popupName = name
        records.popupText = text
        records.popupData = data
    end

    local libs = {}
    function LibStub(name, silent)
        local lib = libs[name]
        if not lib and not silent then
            error("missing lib " .. tostring(name))
        end
        return lib
    end

    libs["AceAddon-3.0"] = {
        NewAddon = function(_, addonName)
            local addon = {
                _addonName = addonName,
                _rangeCheckSpells = {},
            }
            function addon:RegisterChatCommand(command, method)
                self._chatCommands = self._chatCommands or {}
                self._chatCommands[command] = method
            end
            function addon:RegisterEvent() end
            function addon:UnregisterEvent() end
            function addon:Print(message)
                records.prints[#records.prints + 1] = message
            end
            return addon
        end,
    }

    libs["LibDataBroker-1.1"] = {
        NewDataObject = function(_, name, data)
            records.minimap = data
            return data
        end,
    }

    libs["LibDBIcon-1.0"] = {
        Register = function() end,
        Hide = function() records.minimapHidden = true end,
        Show = function() records.minimapShown = true end,
    }

    libs["LibSharedMedia-3.0"] = {
        RegisterCallback = function() end,
    }

    libs["AceDB-3.0"] = {
        New = function()
            local db = {
                profile = {
                    showAdvanced = {},
                    minimap = {},
                    groups = {},
                    groupContainers = {},
                    folders = {},
                },
                global = {
                    characterInfo = {},
                },
                keys = {
                    char = "Test-Realm",
                },
                sv = {
                    profiles = {
                        Default = {},
                    },
                },
                callbacks = {},
            }
            function db.RegisterCallback(_, eventName, callback)
                db.callbacks[eventName] = callback
            end
            function db:GetCurrentProfile()
                return "Default"
            end
            function db:ResetProfile()
                records.resetProfileCount = records.resetProfileCount + 1
                if db.callbacks.OnProfileReset then
                    db.callbacks.OnProfileReset(db)
                end
            end
            return db
        end,
    }

    libs["AceConfig-3.0"] = {
        RegisterOptionsTable = function(_, name, options)
            records.optionsName = name
            records.options = options
        end,
    }

    libs["AceConfigDialog-3.0"] = {
        AddToBlizOptions = function(_, name, title)
            records.blizOptionsName = name
            records.blizOptionsTitle = title
        end,
    }

    C_AddOns = {
        IsAddOnLoaded = function(name)
            if name == "CooldownCompanion_Config" then
                if records.loaded then
                    return true, true
                end
                if loadingAddon then
                    return true, false
                end
            end
            return false, false
        end,
        LoadAddOn = function(name)
            records.loadCalls[#records.loadCalls + 1] = name
            if name ~= "CooldownCompanion_Config" then
                return false, "MISSING"
            end
            if failLoad then
                return false, failReason
            end
            records.loaded = true
            if loadWithoutImpl then
                return true
            end
            local addon = _G.CooldownCompanion
            local ST = addon.ST
            ST._configState = ST._configState or {}
            ST._SetConfigPrimaryModeImpl = function(mode)
                records.modeCalls[#records.modeCalls + 1] = mode
                ST._configState.resourceBarPanelActive = (mode == "bars")
            end
            ST._ShowPopupAboveConfig = function(name, text, data)
                records.popupHelperCount = records.popupHelperCount + 1
                StaticPopup_Show(name, text, nil, data)
            end
            addon._configGetFrameImpl = function()
                return {
                    frame = {
                        IsShown = function()
                            return frameShown
                        end,
                        Show = function()
                            frameShown = true
                        end,
                        Hide = function()
                            frameShown = false
                        end,
                    },
                    _miniFrame = {
                        IsShown = function()
                            return miniShown
                        end,
                        Hide = function()
                            miniShown = false
                        end,
                    },
                }
            end
            addon._configToggleImpl = function()
                records.toggleCount = records.toggleCount + 1
                frameShown = not frameShown
            end
            addon._configRefreshPanelImpl = function()
                records.refreshCount = records.refreshCount + 1
            end
            addon._configOpenDiagnosticDecodePanelImpl = function()
                records.diagnosticCount = records.diagnosticCount + 1
            end
            addon._configResetForProfileChangeImpl = function()
                records.resetConfigCount = records.resetConfigCount + 1
            end
            StaticPopupDialogs["CDC_RESET_PROFILE"] = {}
            return true
        end,
    }

    local ST = {
        _defaults = {},
    }

    assert(loadfile("CooldownCompanion/Core/Init.lua"))("CooldownCompanion", ST)
    local addon = _G.CooldownCompanion
    addon.ST = ST
    addon.RunAllMigrations = function() return migrationsOk end
    addon.ClearUnsupportedProfileRuntime = function() records.clearUnsupported = (records.clearUnsupported or 0) + 1 end
    addon.RefreshAllGroups = function() records.refreshAllGroups = (records.refreshAllGroups or 0) + 1 end
    addon.EvaluateBarsAndFramesRuntime = function(_, reason) records.evaluateReason = reason end
    addon.BeginCombatForcedLock = function() end
    addon.EndCombatForcedLock = function() return {} end
    addon.QueueCooldownRefresh = function() end
    addon.ApplyCdmAlpha = function() end
    addon.IsContainerVisibleToCurrentChar = function() return false end

    assert(loadfile("CooldownCompanion/Core/ConfigLoader.lua"))("CooldownCompanion", ST)
    assert(loadfile("CooldownCompanion/Core/Lifecycle.lua"))("CooldownCompanion", ST)
    addon:OnInitialize()

    local originalSetConfigPrimaryMode = ST._SetConfigPrimaryMode
    records.modeWrapperCalls = 0
    ST._SetConfigPrimaryMode = function(...)
        records.modeWrapperCalls = records.modeWrapperCalls + 1
        return originalSetConfigPrimaryMode(...)
    end

    return {
        addon = addon,
        ST = ST,
        records = records,
        setCombat = function(value) inCombat = value and true or false end,
        setLoadFailure = function(value, reason)
            failLoad = value and true or false
            failReason = reason or failReason
        end,
        setLoadWithoutImpl = function(value)
            loadWithoutImpl = value and true or false
        end,
        setLoadingAddon = function(value)
            loadingAddon = value and true or false
        end,
        setMigrationsOk = function(value)
            migrationsOk = value and true or false
        end,
    }
end

do
    local h = NewHarness()
    h.addon:RefreshConfigPanel()
    AssertEqual(#h.records.loadCalls, 0, "passive config refresh should not load config")
    AssertEqual(h.addon:GetConfigFrame(), nil, "config frame should be nil before config loads")
end

do
    local h = NewHarness()
    h.setLoadFailure(true, "DISABLED")
    h.addon:SlashCommand("")
    AssertEqual(#h.records.loadCalls, 1, "/cdc should attempt config load")
    AssertEqual(h.records.toggleCount, 0, "failed /cdc load should not toggle config")
    AssertContains(h.records.prints[#h.records.prints], "/cdc", "failed /cdc load should name entry point")
    AssertContains(h.records.prints[#h.records.prints], "DISABLED", "failed /cdc load should include reason")
end

do
    local h = NewHarness()
    h.addon:SlashCommand("")
    AssertEqual(#h.records.loadCalls, 1, "/cdc should load config")
    AssertEqual(h.records.toggleCount, 1, "/cdc should toggle config after load")
end

do
    local h = NewHarness()
    h.setLoadWithoutImpl(true)
    h.addon:SlashCommand("")
    AssertEqual(#h.records.loadCalls, 1, "successful config load without hooks should be attempted once")
    AssertEqual(h.records.toggleCount, 0, "successful config load without hooks should not toggle config")
    AssertContains(h.records.prints[#h.records.prints], "did not initialize", "missing hook load should print init failure")
end

do
    local h = NewHarness()
    h.setLoadingAddon(true)
    h.addon:SlashCommand("")
    AssertEqual(#h.records.loadCalls, 1, "loaded-or-loading config state should still attempt explicit load")
    AssertEqual(h.records.toggleCount, 1, "loaded-or-loading config state should toggle after explicit load")
end

do
    local h = NewHarness()
    h.addon:SlashCommand("buttons")
    AssertEqual(h.records.modeCalls[#h.records.modeCalls], "buttons", "/cdc buttons should select Buttons mode")
    AssertEqual(h.records.modeWrapperCalls, 1, "/cdc buttons should pass through stable mode wrapper")
end

do
    local h = NewHarness()
    h.addon:SlashCommand("bars")
    AssertEqual(h.records.modeCalls[#h.records.modeCalls], "bars", "/cdc bars should select Bars mode")
    AssertEqual(h.records.modeWrapperCalls, 1, "/cdc bars should pass through stable mode wrapper")
end

do
    local h = NewHarness()
    h.addon:SlashCommand("frames")
    AssertEqual(h.records.modeCalls[#h.records.modeCalls], "bars", "/cdc frames should alias Bars mode")
    AssertEqual(h.records.modeWrapperCalls, 1, "/cdc frames should pass through stable mode wrapper")
end

do
    local h = NewHarness()
    h.addon:SlashCommand("debugimport")
    AssertEqual(h.records.diagnosticCount, 1, "/cdc debugimport should open diagnostics after load")
end

do
    local h = NewHarness()
    h.setLoadFailure(true, "DISABLED")
    h.addon:SlashCommand("reset")
    AssertEqual(#h.records.loadCalls, 0, "/cdc reset should not require config addon load")
    AssertEqual(h.records.popupName, "CDC_RESET_PROFILE", "/cdc reset should show reset popup without config load")
    AssertEqual(h.records.popupHelperCount, 0, "/cdc reset should use core popup before config load")
    AssertEqual(h.records.popupData.profileName, "Default", "/cdc reset should pass current profile")
    StaticPopupDialogs["CDC_RESET_PROFILE"].OnAccept(nil, h.records.popupData)
    AssertEqual(h.records.resetProfileCount, 1, "/cdc reset popup should reset current profile")
    AssertEqual(h.records.refreshAllGroups, 1, "/cdc reset popup should refresh runtime groups through profile callback")
end

do
    local h = NewHarness()
    h.addon:SlashCommand("")
    h.addon:SlashCommand("reset")
    AssertEqual(#h.records.loadCalls, 1, "loaded /cdc reset should reuse already loaded config")
    AssertEqual(h.records.popupHelperCount, 1, "loaded /cdc reset should use config popup helper")
end

do
    local h = NewHarness()
    h.records.minimap.OnClick(nil, "LeftButton")
    AssertEqual(h.records.toggleCount, 1, "minimap click should toggle config after load")
end

do
    local h = NewHarness()
    h.records.options.args.openConfig.func()
    AssertEqual(h.records.settingsPanelClosed, true, "Blizzard Settings should close after successful config load")
    AssertEqual(h.records.settingsPanelCloseSkipTransition, true, "Blizzard Settings close should skip transition back")
    AssertEqual(h.records.toggleCount, 1, "Blizzard Settings button should open config")
    AssertEqual(h.records.optionsName, "CooldownCompanion", "settings registration should stay on main addon")
end

do
    local h = NewHarness()
    h.setLoadFailure(true, "MISSING")
    h.records.options.args.openConfig.func()
    AssertEqual(h.records.settingsPanelClosed, false, "failed Blizzard Settings load should leave Settings open")
    AssertContains(h.records.prints[#h.records.prints], "Blizzard Settings", "failed Settings load should name entry point")
end

do
    local h = NewHarness()
    h.setCombat(true)
    h.records.options.args.openConfig.func()
    AssertEqual(#h.records.loadCalls, 0, "combat-deferred Blizzard Settings should not load config in combat")
    AssertEqual(h.records.settingsPanelClosed, false, "combat-deferred Blizzard Settings should not close Settings before load")
    AssertEqual(h.addon._pendingConfigIntent.closeSettings, true, "combat-deferred Blizzard Settings should remember close handoff")
    h.setCombat(false)
    h.addon:OnCombatEnd()
    AssertEqual(h.records.settingsPanelClosed, true, "combat-deferred Blizzard Settings should close Settings after combat")
    AssertEqual(h.records.settingsPanelCloseSkipTransition, true, "combat-deferred Settings close should skip transition back")
    AssertEqual(h.records.toggleCount, 1, "combat-deferred Blizzard Settings should open config after combat")
end

do
    local h = NewHarness()
    h.setCombat(true)
    h.addon:SlashCommand("bars")
    AssertEqual(#h.records.loadCalls, 0, "combat-deferred /cdc bars should not load config in combat")
    h.setCombat(false)
    h.addon:OnCombatEnd()
    AssertEqual(h.records.modeCalls[#h.records.modeCalls], "bars", "combat-deferred /cdc bars should preserve mode")
end

do
    local h = NewHarness()
    h.addon:SlashCommand("")
    h.setCombat(true)
    h.addon:OnCombatStart()
    AssertEqual(h.addon:GetConfigFrame().frame:IsShown(), false, "combat start should hide open config")
    AssertEqual(h.addon._pendingConfigIntent.action, "toggle", "combat start should queue reopen intent")
    AssertEqual(h.addon._pendingConfigIntent.entryPoint, "combat reopen", "combat start should name reopen intent")
    h.setCombat(false)
    h.addon:OnCombatEnd()
    AssertEqual(h.addon:GetConfigFrame().frame:IsShown(), true, "combat end should reopen previously open config")
end

do
    local h = NewHarness()
    h.addon.db.callbacks.OnProfileChanged(h.addon.db, "Default")
    AssertEqual(h.records.refreshAllGroups, 1, "profile change should refresh runtime groups before config load")
    AssertEqual(h.records.resetConfigCount, 0, "profile change before config load should not touch config state")
    h.addon:SlashCommand("")
    h.addon.db.callbacks.OnProfileReset()
    AssertEqual(h.records.resetConfigCount, 1, "profile reset after config load should reset config state")
end

do
    local h = NewHarness()
    local profile = h.addon.db.profile
    profile.groups = {
        charGroup = { isGlobal = false, createdBy = "Old-Realm" },
        globalGroup = { isGlobal = true, createdBy = "Other-Realm" },
    }
    profile.groupContainers = {
        charContainer = { isGlobal = false, createdBy = "Old-Realm" },
        globalContainer = { isGlobal = true, createdBy = "Other-Realm" },
    }
    profile.folders = {
        charFolder = { section = "char", createdBy = "Old-Realm" },
        globalFolder = { section = "global", createdBy = "Other-Realm" },
    }
    h.addon.db.callbacks.OnProfileCopied()
    AssertEqual(profile.groups.charGroup.createdBy, "Test-Realm", "profile copy should restamp char group ownership")
    AssertEqual(profile.groups.globalGroup.createdBy, "Other-Realm", "profile copy should not restamp global group ownership")
    AssertEqual(profile.groupContainers.charContainer.createdBy, "Test-Realm", "profile copy should restamp char container ownership")
    AssertEqual(profile.groupContainers.globalContainer.createdBy, "Other-Realm", "profile copy should not restamp global container ownership")
    AssertEqual(profile.folders.charFolder.createdBy, "Test-Realm", "profile copy should restamp char folder ownership")
    AssertEqual(profile.folders.globalFolder.createdBy, "Other-Realm", "profile copy should not restamp global folder ownership")
end

do
    local h = NewHarness()
    h.addon.db.profile.groups.charGroup = { isGlobal = false, createdBy = "Old-Realm" }
    h.addon._suppressOwnershipRestamp = true
    h.addon.db.callbacks.OnProfileCopied()
    AssertEqual(h.addon.db.profile.groups.charGroup.createdBy, "Old-Realm", "suppressed profile copy should preserve ownership")
    AssertEqual(h.addon._suppressOwnershipRestamp, nil, "suppressed profile copy should consume suppression flag")
end

for _, scenario in ipairs({
    {
        name = "profile changed",
        run = function(h)
            h.addon.db.callbacks.OnProfileChanged(h.addon.db, "Default")
        end,
    },
    {
        name = "profile copied",
        run = function(h)
            h.addon.db.callbacks.OnProfileCopied()
        end,
    },
    {
        name = "profile reset",
        run = function(h)
            h.addon.db.callbacks.OnProfileReset()
        end,
    },
}) do
    local h = NewHarness()
    h.setMigrationsOk(false)
    scenario.run(h)
    AssertEqual(h.records.clearUnsupported, 1, scenario.name .. " migration failure should clear unsupported runtime")
    AssertEqual(h.records.refreshAllGroups, nil, scenario.name .. " migration failure should not refresh all groups")
    AssertEqual(h.records.evaluateReason, nil, scenario.name .. " migration failure should not evaluate bars runtime")
end

do
    assert(not FileExists("CooldownCompanion.toc"), "main TOC should not remain at repo root")
    assert(not FileExists("Core/Init.lua"), "Core files should not remain at repo root")
    assert(not FileExists("ButtonFrame/IconMode.lua"), "ButtonFrame files should not remain at repo root")
    assert(not FileExists("OtherBars/ResourceBar.lua"), "OtherBars files should not remain at repo root")
    assert(not FileExists("Media/cdcminimap.tga"), "Media files should not remain at repo root")
    assert(FileExists("CooldownCompanion/CooldownCompanion.toc"), "main TOC should live in addon folder")
    assert(FileExists("CooldownCompanion/Core/Init.lua"), "main Core files should live in addon folder")
    assert(FileExists("CooldownCompanion/Media/cdcminimap.tga"), "main Media files should live in addon folder")

    local mainToc = ReadFile("CooldownCompanion/CooldownCompanion.toc")
    assert(not mainToc:find("\nConfig\\", 1, true), "main TOC should not load Config files")
    assert(not mainToc:find("\nConfigSettings\\", 1, true), "main TOC should not load ConfigSettings files")
    AssertContains(mainToc, "Core\\ConfigLoader.lua", "main TOC should load config loader")

    local configToc = ReadFile("CooldownCompanion_Config/CooldownCompanion_Config.toc")
    AssertContains(configToc, "## RequiredDeps: CooldownCompanion", "config TOC should depend on main addon")
    AssertContains(configToc, "## LoadOnDemand: 1", "config TOC should be load-on-demand")
    AssertListEqual(ParseTocEntries(configToc), {
        "Bootstrap.lua",
        "Config\\State.lua",
        "Config\\Tutorial.lua",
        "Config\\ExportCodec.lua",
        "Config\\ProfileImport.lua",
        "Config\\Popups.lua",
        "Config\\ProfileImportPieces.lua",
        "Config\\ImportReview.lua",
        "Config\\Diagnostics.lua",
        "Config\\Pickers.lua",
        "Config\\TalentPicker.lua",
        "Config\\SpellItemAdd.lua",
        "Config\\AutoImport.lua",
        "Config\\DragReorderTargets.lua",
        "Config\\DragReorderPreview.lua",
        "Config\\DragReorderLifecycle.lua",
        "Config\\DragReorder.lua",
        "Config\\Column1.lua",
        "Config\\Column2.lua",
        "Config\\Column3.lua",
        "Config\\Column4.lua",
        "Config\\PanelChangelogOverlay.lua",
        "Config\\Panel.lua",
        "ConfigSettings\\Helpers.lua",
        "ConfigSettings\\AdvancedSettingsPanel.lua",
        "ConfigSettings\\SectionBuilders.lua",
        "ConfigSettings\\CastBarPanels.lua",
        "ConfigSettings\\ResourceBarPanelsHelpers.lua",
        "ConfigSettings\\ResourceBarLayoutOrderPreview.lua",
        "ConfigSettings\\ResourceBarPanelsResource.lua",
        "ConfigSettings\\ResourceBarPanelsCustomBars.lua",
        "ConfigSettings\\ResourceBarPanelsLayoutOrder.lua",
        "ConfigSettings\\ResourceBarPanels.lua",
        "ConfigSettings\\FrameAnchoringPanels.lua",
        "ConfigSettings\\AuraTexturePicker.lua",
        "ConfigSettings\\ButtonSettingsMultiSelect.lua",
        "ConfigSettings\\ButtonSettingsOverrides.lua",
        "ConfigSettings\\ButtonSettings.lua",
        "ConfigSettings\\ButtonConditions.lua",
        "ConfigSettings\\BarModeTabs.lua",
        "ConfigSettings\\FormatEditor.lua",
        "ConfigSettings\\TextModeTabs.lua",
        "ConfigSettings\\GroupTabs.lua",
    }, "config TOC load order")

    local packageMeta = ReadFile(".pkgmeta")
    AssertContains(packageMeta, "CooldownCompanion/CooldownCompanion: CooldownCompanion",
        "package metadata should flatten main addon folder")
    AssertContains(packageMeta, "CooldownCompanion/CooldownCompanion_Config: CooldownCompanion_Config",
        "package metadata should move companion addon to sibling folder")
    AssertContains(packageMeta, "- CooldownCompanion/Libs", "package metadata should ignore local nested libs")
    AssertContains(packageMeta, "- tests", "package metadata should not ship local tests")
end

do
    local h = NewHarness()
    local configST = {}
    assert(loadfile("CooldownCompanion_Config/Bootstrap.lua"))("CooldownCompanion_Config", configST)
    configST._bootstrapForwardedValue = true
    AssertEqual(h.ST._bootstrapForwardedValue, true, "bootstrap writes should forward to main ST")
    AssertEqual(configST.Addon, h.addon, "bootstrap reads should resolve from main ST")
end

print("config-loader ok")
