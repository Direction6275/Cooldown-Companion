--[[
    CooldownCompanion - ResourceBarPanelsCustomBars
    Config panel builders for the Custom Bars list, editor, tabs,
    badges, row actions, and preview toggles.
    Query helpers and shared builders live in ResourceBarPanelsHelpers.lua.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local LSM = LibStub("LibSharedMedia-3.0")
local CS = ST._configState
local IsPassiveOrProc = ST._IsPassiveOrProc
local ShowPopupAboveConfig = CS.ShowPopupAboveConfig
local OpenImportReviewWindow = ST._OpenImportReviewWindow
local ClearCustomBarPreviewState = ST._ClearConfigCustomBarPreviewState
local SelectConfigCustomBar = ST._SelectConfigCustomBar
local ClearConfigCustomBarSelection = ST._ClearConfigCustomBarSelection
local ToggleConfigCustomBarMultiSelect = ST._ToggleConfigCustomBarMultiSelect
local PruneConfigCustomBarSelection = ST._PruneConfigCustomBarSelection

-- Imports from Helpers.lua
local ColorHeading = ST._ColorHeading
local AttachCollapseButton = ST._AttachCollapseButton
local AddAdvancedToggle = ST._AddAdvancedToggle
local CreateCharacterCopyButton = ST._CreateCharacterCopyButton
local CreateInfoButton = ST._CreateInfoButton
local ApplyCheckboxIndent = ST._ApplyCheckboxIndent
local AddColorPicker = ST._AddColorPicker
local AddAnchorDropdown = ST._AddAnchorDropdown
local HookSliderEditBox = ST._HookSliderEditBox
local BuildAlphaControls = ST._BuildAlphaControls
local BuildIndependentAnchorTargetRow = ST._BuildIndependentAnchorTargetRow
local BuildPandemicBarControls = ST._BuildPandemicBarControls
local BuildBarActiveAuraControls = ST._BuildBarActiveAuraControls
local BuildBarAuraPulseControls = ST._BuildBarAuraPulseControls
local BuildPandemicBarPulseControls = ST._BuildPandemicBarPulseControls
local AddPreviewToggleButton = ST._AddPreviewToggleButton
local AddPreviewBadge = ST._AddPreviewBadge
local RefreshConfigPanelForPreviewToggle = ST._RefreshConfigPanelForPreviewToggle
local CleanRecycledEntry = ST._CleanRecycledEntry
local ApplyConfigRowIcon = ST._ApplyConfigRowIcon
local BindConfigShiftTooltip = ST._BindConfigShiftTooltip
local AddDurationFormatDropdown = ST._AddDurationFormatDropdown
local tabInfoButtons = CS.tabInfoButtons

local function RefreshLayoutOrderPreview()
    if not (CS.resourceBarPanelActive and CS.col4Container and ST._RefreshColumn4) then
        return
    end
    ST._RefreshColumn4(CS.col4Container)
end

-- Shared constants from ResourceBarConstants
local RB = ST._RB
local POWER_NAMES = RB.POWER_NAMES
local SEGMENTED_TYPES = RB.SEGMENTED_TYPES
local HIDE_AT_ZERO_ELIGIBLE = RB.HIDE_AT_ZERO_ELIGIBLE
local DEFAULT_POWER_COLORS = RB.DEFAULT_POWER_COLORS
local DEFAULT_MW_BASE_COLOR = RB.DEFAULT_MW_BASE_COLOR
local DEFAULT_MW_OVERLAY_COLOR = RB.DEFAULT_MW_OVERLAY_COLOR
local DEFAULT_MW_MAX_COLOR = RB.DEFAULT_MW_MAX_COLOR
local DEFAULT_CUSTOM_AURA_MAX_COLOR = RB.DEFAULT_CUSTOM_AURA_MAX_COLOR
local DEFAULT_RESOURCE_TEXT_FORMAT = RB.DEFAULT_RESOURCE_TEXT_FORMAT
local DEFAULT_CUSTOM_AURA_STACK_TEXT_FORMAT = RB.DEFAULT_CUSTOM_AURA_STACK_TEXT_FORMAT
local DEFAULT_RESOURCE_TEXT_FONT = RB.DEFAULT_RESOURCE_TEXT_FONT
local DEFAULT_RESOURCE_TEXT_SIZE = RB.DEFAULT_RESOURCE_TEXT_SIZE
local DEFAULT_RESOURCE_TEXT_OUTLINE = RB.DEFAULT_RESOURCE_TEXT_OUTLINE
local DEFAULT_RESOURCE_TEXT_COLOR = RB.DEFAULT_RESOURCE_TEXT_COLOR
local DEFAULT_RESOURCE_TEXT_ANCHOR = RB.DEFAULT_RESOURCE_TEXT_ANCHOR
local DEFAULT_RESOURCE_TEXT_X_OFFSET = RB.DEFAULT_RESOURCE_TEXT_X_OFFSET
local DEFAULT_RESOURCE_TEXT_Y_OFFSET = RB.DEFAULT_RESOURCE_TEXT_Y_OFFSET
local DEFAULT_SEG_THRESHOLD_COLOR = RB.DEFAULT_SEG_THRESHOLD_COLOR
local DEFAULT_CONTINUOUS_TICK_COLOR = RB.DEFAULT_CONTINUOUS_TICK_COLOR
local DEFAULT_CONTINUOUS_TICK_MODE = RB.DEFAULT_CONTINUOUS_TICK_MODE
local DEFAULT_CONTINUOUS_TICK_WIDTH = RB.DEFAULT_CONTINUOUS_TICK_WIDTH
local DEFAULT_HEALTH_BAR_COLOR = RB.DEFAULT_HEALTH_BAR_COLOR
local DEFAULT_HEALTH_BAR_OPACITY = RB.DEFAULT_HEALTH_BAR_OPACITY
local DEFAULT_HEALTH_BAR_FULL_COLOR = RB.DEFAULT_HEALTH_BAR_FULL_COLOR
local DEFAULT_HEALTH_BAR_HALF_COLOR = RB.DEFAULT_HEALTH_BAR_HALF_COLOR
local DEFAULT_HEALTH_BAR_LOW_COLOR = RB.DEFAULT_HEALTH_BAR_LOW_COLOR
local DEFAULT_HEALTH_BAR_GRADIENT = RB.DEFAULT_HEALTH_BAR_GRADIENT
local DEFAULT_HEALTH_BACKGROUND_COLOR = RB.DEFAULT_HEALTH_BACKGROUND_COLOR
local DEFAULT_HEALTH_BACKGROUND_FULL_COLOR = RB.DEFAULT_HEALTH_BACKGROUND_FULL_COLOR
local DEFAULT_HEALTH_BACKGROUND_HALF_COLOR = RB.DEFAULT_HEALTH_BACKGROUND_HALF_COLOR
local DEFAULT_HEALTH_BACKGROUND_LOW_COLOR = RB.DEFAULT_HEALTH_BACKGROUND_LOW_COLOR
local DEFAULT_HEALTH_BACKGROUND_OPACITY = RB.DEFAULT_HEALTH_BACKGROUND_OPACITY
local DEFAULT_HEALTH_BACKGROUND_GRADIENT = RB.DEFAULT_HEALTH_BACKGROUND_GRADIENT
local DEFAULT_HEALTH_ABSORB_COLOR = RB.DEFAULT_HEALTH_ABSORB_COLOR
local DEFAULT_HEALTH_HEAL_ABSORB_COLOR = RB.DEFAULT_HEALTH_HEAL_ABSORB_COLOR
local DEFAULT_HEALTH_INCOMING_HEAL_COLOR = RB.DEFAULT_HEALTH_INCOMING_HEAL_COLOR
local DEFAULT_HEALTH_LOW_HEALTH_ALERT_COLOR = RB.DEFAULT_HEALTH_LOW_HEALTH_ALERT_COLOR
local DEFAULT_HEALTH_EFFECT_TEXTURE = RB.DEFAULT_HEALTH_EFFECT_TEXTURE
local DEFAULT_COMBO_COLOR = RB.DEFAULT_COMBO_COLOR
local DEFAULT_COMBO_MAX_COLOR = RB.DEFAULT_COMBO_MAX_COLOR
local DEFAULT_COMBO_CHARGED_COLOR = RB.DEFAULT_COMBO_CHARGED_COLOR
local DEFAULT_RUNE_READY_COLOR = RB.DEFAULT_RUNE_READY_COLOR
local DEFAULT_RUNE_RECHARGING_COLOR = RB.DEFAULT_RUNE_RECHARGING_COLOR
local DEFAULT_RUNE_MAX_COLOR = RB.DEFAULT_RUNE_MAX_COLOR
local DEFAULT_SHARD_READY_COLOR = RB.DEFAULT_SHARD_READY_COLOR
local DEFAULT_SHARD_RECHARGING_COLOR = RB.DEFAULT_SHARD_RECHARGING_COLOR
local DEFAULT_SHARD_MAX_COLOR = RB.DEFAULT_SHARD_MAX_COLOR
local DEFAULT_HOLY_COLOR = RB.DEFAULT_HOLY_COLOR
local DEFAULT_HOLY_MAX_COLOR = RB.DEFAULT_HOLY_MAX_COLOR
local DEFAULT_CHI_COLOR = RB.DEFAULT_CHI_COLOR
local DEFAULT_CHI_MAX_COLOR = RB.DEFAULT_CHI_MAX_COLOR
local DEFAULT_ARCANE_COLOR = RB.DEFAULT_ARCANE_COLOR
local DEFAULT_ARCANE_MAX_COLOR = RB.DEFAULT_ARCANE_MAX_COLOR
local DEFAULT_ESSENCE_READY_COLOR = RB.DEFAULT_ESSENCE_READY_COLOR
local DEFAULT_ESSENCE_RECHARGING_COLOR = RB.DEFAULT_ESSENCE_RECHARGING_COLOR
local DEFAULT_ESSENCE_MAX_COLOR = RB.DEFAULT_ESSENCE_MAX_COLOR
local GetResolvedCustomAuraBarAuraUnit = RB.GetResolvedCustomAuraBarAuraUnit
local EnsureCustomAuraBarAuraUnit = RB.EnsureCustomAuraBarAuraUnit
local GetCustomBarEntryType = RB.GetCustomBarEntryType
local EnsureCustomBarId = RB.EnsureCustomBarId
local EnsureCustomBarLayout = RB.EnsureCustomBarLayout
local GetCustomBarLayout = RB.GetCustomBarLayout
local GetResourceSpecOverrideTable = RB.GetResourceSpecOverrideTable
local RESOURCE_HEALTH_DISPLAY_KEYS = RB.RESOURCE_HEALTH_DISPLAY_KEYS
local resourceSpecCopyButton
local resourceSpecCopyMenu

local function IsHeroSpecProxyCondition(cond)
    return type(cond) == "table"
        and cond.nodeID ~= nil
        and cond.heroSubTreeID ~= nil
        and cond.entryID == nil
        and type(cond.name) == "string"
        and type(cond.heroName) == "string"
        and cond.name == cond.heroName
end
local function IsSpellCustomBarConfig(cab)
    if RB.IsSpellCustomBarConfig then
        return RB.IsSpellCustomBarConfig(cab)
    end
    return GetCustomBarEntryType and GetCustomBarEntryType(cab) == "spell"
end

local function IsCustomBarAuraDisplayConfig(cab, isSpellCustomBar)
    if isSpellCustomBar == nil then
        isSpellCustomBar = IsSpellCustomBarConfig(cab)
    end

    return (not isSpellCustomBar) or (cab and cab.auraTracking == true)
end

local function GetCustomBarTrackingModeConfig(cab, isSpellCustomBar)
    if RB.GetCustomBarTrackingMode then
        return RB.GetCustomBarTrackingMode(cab, isSpellCustomBar)
    end

    local mode = cab and cab.trackingMode
    if mode == "active" or mode == "stacks" then
        return mode
    end
    return isSpellCustomBar and "active" or "stacks"
end

local RefreshCustomAuraBarAuraUnitForSpell = RB.RefreshCustomAuraBarAuraUnitForSpell

-- Imports from ResourceBarPanelsHelpers
local RBP = ST._RBP
local resourceBarCollapsedSections = RBP.collapsedSections
local BuildResourceAuraOverlaySection = RBP.BuildResourceAuraOverlaySection
local GetConfigActiveResources = RBP.GetConfigActiveResources
local GetCurrentConfigSpecID = RBP.GetCurrentConfigSpecID
local ReadSpecOverrideKey = RBP.ReadSpecOverrideKey
local WriteSpecOverrideKey = RBP.WriteSpecOverrideKey
local GetSafeRGBConfig = RBP.GetSafeRGBConfig
local GetSafeRGBAConfig = RBP.GetSafeRGBAConfig
local GetSegmentedThresholdValueConfig = RBP.GetSegmentedThresholdValueConfig
local GetContinuousTickModeConfig = RBP.GetContinuousTickModeConfig
local GetContinuousTickPercentConfig = RBP.GetContinuousTickPercentConfig
local GetContinuousTickAbsoluteConfig = RBP.GetContinuousTickAbsoluteConfig
local ResolveAuraColorSpellIDFromText = RBP.ResolveAuraColorSpellIDFromText
local GetAuraBarAutocompleteDisplayName = RBP.GetAuraBarAutocompleteDisplayName
local GetAuraBarAutocompleteDisplayIcon = RBP.GetAuraBarAutocompleteDisplayIcon
local GetAuraBarAutocompleteEntryName = RBP.GetAuraBarAutocompleteEntryName
local ResolveAuraBarAutocompleteEntry = RBP.ResolveAuraBarAutocompleteEntry
local ShowAuraBarAutocompleteResults = RBP.ShowAuraBarAutocompleteResults
local BuildAuraBarAutocompleteCache = RBP.BuildAuraBarAutocompleteCache
local IsResourceBarVerticalConfig = RBP.IsResourceBarVerticalConfig
local GetResourceThicknessFieldConfig = RBP.GetResourceThicknessFieldConfig
local GetResourceGapFieldConfig = RBP.GetResourceGapFieldConfig

local function CopyTableValue(value)
    return type(value) == "table" and CopyTable(value) or value
end

------------------------------------------------------------------------
-- Custom Bars detail panel
------------------------------------------------------------------------

local function ApplyCustomAuraBarPanelChanges(opts)
    CooldownCompanion:ApplyResourceBars()
    if opts and opts.updateAnchors then
        CooldownCompanion:UpdateAnchorStacking()
    end
    if opts and opts.refreshConfig then
        CooldownCompanion:RefreshConfigPanel()
    end
    if opts and opts.refreshLayoutPreview then
        RefreshLayoutOrderPreview()
    end
end

local function FindCustomBarIndexById(customBars, customBarId)
    if type(customBars) ~= "table" or type(customBarId) ~= "string" then
        return nil
    end
    for index, entry in ipairs(customBars) do
        if type(entry) == "table" and entry.customBarId == customBarId then
            return index
        end
    end
    return nil
end

local function EnsureCustomBarRowTextBadge(frame, key)
    local badge = frame[key]
    if not badge then
        badge = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        frame[key] = badge
    end
    badge:ClearAllPoints()
    badge:SetJustifyH("RIGHT")
    badge:SetJustifyV("MIDDLE")
    badge:Show()
    return badge
end

local function EnsureCustomBarRowIconBadge(frame, key, atlas)
    local badge = frame[key]
    if not badge then
        badge = CreateFrame("Button", nil, frame)
        badge:SetSize(16, 16)
        badge.icon = badge:CreateTexture(nil, "OVERLAY")
        badge.icon:SetAllPoints()
        badge:SetScript("OnEnter", function(self)
            if not self._cdcTooltipText then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(
                self._cdcTooltipText,
                self._cdcTooltipR or 1,
                self._cdcTooltipG or 1,
                self._cdcTooltipB or 1,
                true
            )
            GameTooltip:Show()
        end)
        badge:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        frame[key] = badge
    end

    badge:ClearAllPoints()
    badge:SetSize(16, 16)
    badge.icon:SetAtlas(atlas, false)
    badge.icon:SetVertexColor(1, 1, 1, 1)
    badge._cdcTooltipText = nil
    badge._cdcTooltipR, badge._cdcTooltipG, badge._cdcTooltipB = nil, nil, nil
    badge:SetFrameLevel(frame:GetFrameLevel() + 5)
    badge:Show()
    return badge
end

local function SetCustomBarRowBadgeTooltip(badge, text, r, g, b)
    badge._cdcTooltipText = text
    badge._cdcTooltipR = r or 1
    badge._cdcTooltipG = g or 1
    badge._cdcTooltipB = b or 1
end

local function GetCustomBarSpecOptions()
    local specs = {}
    local _, _, classID = UnitClass("player")
    local numSpecs = classID
        and C_SpecializationInfo.GetNumSpecializationsForClassID(classID)
        or 0
    for specIndex = 1, numSpecs do
        local specID, specName, _, specIcon = C_SpecializationInfo.GetSpecializationInfo(
            specIndex,
            false,
            false,
            nil,
            nil,
            nil,
            classID
        )
        if specID then
            specs[#specs + 1] = {
                id = specID,
                name = specName or ("Spec " .. tostring(specID)),
                icon = specIcon,
            }
        end
    end
    return specs
end

local function EnsureCustomBarSpecBadge(frame, index)
    if not frame._cdcCustomBarSpecBadges then
        frame._cdcCustomBarSpecBadges = {}
    end
    local badge = frame._cdcCustomBarSpecBadges[index]
    if not badge then
        badge = CreateFrame("Frame", nil, frame)
        badge.icon = badge:CreateTexture(nil, "OVERLAY")
        badge.icon:SetAllPoints()
        badge:EnableMouse(false)
        local mask = badge:CreateMaskTexture()
        mask:SetAllPoints(badge.icon)
        mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        badge._cdcCircleMask = mask
        frame._cdcCustomBarSpecBadges[index] = badge
    end
    badge:ClearAllPoints()
    badge:SetSize(16, 16)
    badge.icon:SetTexture(nil)
    badge.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    badge.icon:SetVertexColor(1, 1, 1, 1)
    if badge._cdcCircleMask then
        badge.icon:RemoveMaskTexture(badge._cdcCircleMask)
        badge.icon:AddMaskTexture(badge._cdcCircleMask)
    end
    badge:SetFrameLevel(frame:GetFrameLevel() + 6)
    badge:Show()
    return badge
end

local function PlaceCustomBarSpecBadges(rowFrame, settings, entry, currentSpecID, anchor, point, offset)
    local specs = GetCustomBarSpecOptions()
    local badgeIndex = 0
    if RB.CustomBarHasSpecFilters and RB.CustomBarHasSpecFilters(entry) then
        for _, spec in ipairs(specs) do
            local active = RB.CustomBarHasExplicitSpec and RB.CustomBarHasExplicitSpec(entry, spec.id)
            if active and spec.icon then
                badgeIndex = badgeIndex + 1
                local badge = EnsureCustomBarSpecBadge(rowFrame, badgeIndex)
                badge.icon:SetTexture(spec.icon)
                badge:SetPoint("RIGHT", anchor, point, offset, 0)
                anchor = badge
                point = "LEFT"
                offset = -3
            end
        end
    end

    if rowFrame._cdcCustomBarSpecBadges then
        for index = badgeIndex + 1, #rowFrame._cdcCustomBarSpecBadges do
            rowFrame._cdcCustomBarSpecBadges[index]:Hide()
        end
    end
    return anchor, point, offset
end

local function AddCustomBarSpecFilterControls(container, settings, entry, currentSpecID)
    local specs = GetCustomBarSpecOptions()
    for _, spec in ipairs(specs) do
        local cb = AceGUI:Create("CheckBox")
        cb:SetLabel(spec.name)
        if spec.icon then
            cb:SetImage(spec.icon, 0.08, 0.92, 0.08, 0.92)
        end
        cb:SetFullWidth(true)
        cb:SetValue(RB.CustomBarHasExplicitSpec and RB.CustomBarHasExplicitSpec(entry, spec.id) or false)
        cb:SetCallback("OnValueChanged", function(widget, event, value)
            if value then
                if RB.AddCustomBarToSpec then
                    RB.AddCustomBarToSpec(settings, entry, spec.id, currentSpecID)
                end
            else
                if RB.RemoveCustomBarFromSpec then
                    RB.RemoveCustomBarFromSpec(settings, entry, spec.id)
                end
                if spec.id == currentSpecID then
                    ClearCustomBarPreviewState()
                end
            end
            ApplyCustomAuraBarPanelChanges({
                updateAnchors = true,
                refreshConfig = true,
                refreshLayoutPreview = true,
            })
        end)
        ApplyCheckboxIndent(cb, 12)
        container:AddChild(cb)
    end
end

local function StripCustomBarEntryTypeWords(text)
    if type(text) ~= "string" then
        return text
    end

    return text
        :gsub("%s*%(([%w%s]+)%)%s*$", function(kind)
            local normalized = kind and kind:lower():gsub("^%s+", ""):gsub("%s+$", "")
            if normalized == "buff" or normalized == "cooldown" or normalized == "aura" then
                return ""
            end
            return " (" .. kind .. ")"
        end)
        :gsub("%s+$", "")
end

local function GetCustomBarEntryTypeIcons(entry)
    if entry and entry.entryType == "spell" then
        local icons = "|A:ui_adv_atk:15:15|a"
        if entry.auraTracking == true then
            icons = icons .. " |A:ui_adv_health:15:15|a"
        end
        return icons
    end

    return "|A:ui_adv_health:15:15|a"
end

local function ResolveCustomBarAuraTrackingStatus(entry, resolvedAuraUnit)
    local spellID = tonumber(entry and entry.spellID)
    local cdmEnabled = C_CVar.GetCVarBool("cooldownViewerEnabled") == true
    local isSpellEntry = entry and entry.entryType == "spell"
    local auraTrackingEnabled = true
    if isSpellEntry then
        auraTrackingEnabled = entry.auraTracking == true
    end
    local auraSpellID = entry and entry.auraSpellID or nil
    local buttonData = spellID and {
        type = "spell",
        id = spellID,
        auraSpellID = auraSpellID,
        auraTracking = auraTrackingEnabled,
        auraUnit = resolvedAuraUnit,
        addedAs = isSpellEntry and nil or "aura",
    } or nil
    local viewerFrame = buttonData and CooldownCompanion:ResolveButtonAuraViewerFrame(buttonData) or nil

    return buttonData and CooldownCompanion:ResolveAuraTrackingConfigStatus(buttonData, cdmEnabled, viewerFrame)
        or { state = "noAssociatedAura", ready = false, cdmEnabled = cdmEnabled }
end

local function ConfigureCustomBarAddInstructions(addBox, placeholderText)
    local editFrame = addBox and addBox.editbox
    if not editFrame then
        return function() end
    end

    local instructions = editFrame._cdcCustomBarAddInstructions
    if not instructions then
        instructions = editFrame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        instructions:SetPoint("LEFT", editFrame, "LEFT", 6, 0)
        instructions:SetPoint("RIGHT", editFrame, "RIGHT", -6, 0)
        instructions:SetJustifyH("LEFT")
        instructions:SetTextColor(0.5, 0.5, 0.5)
        editFrame._cdcCustomBarAddInstructions = instructions
    end
    instructions:SetText(placeholderText)

    local function Update(text)
        instructions:SetShown((text or "") == "")
    end

    local prevOnRelease = addBox.events and addBox.events["OnRelease"]
    addBox:SetCallback("OnRelease", function(widget)
        if prevOnRelease then
            prevOnRelease(widget, "OnRelease")
        end
        instructions:Hide()
        instructions:SetText("")
    end)

    Update(editFrame:GetText())
    return Update
end

local function DeleteCustomBarById(settings, specID, customBars, customBarId)
    if RB.DeleteCustomBar then
        return RB.DeleteCustomBar(settings, customBarId)
    end

    return false
end

local function DuplicateCustomBarById(settings, specID, customBars, customBarId)
    local sourceIndex = FindCustomBarIndexById(customBars, customBarId)
    local sourceEntry = sourceIndex and customBars[sourceIndex]
    if type(settings) ~= "table" or type(sourceEntry) ~= "table" then
        return nil
    end

    local fallbackOrder = 1000 + sourceIndex + 1
    local newId
    if RB.DuplicateCustomBar then
        newId = RB.DuplicateCustomBar(settings, sourceEntry, specID, fallbackOrder)
    elseif RB.AddCustomBar then
        local sourceLayout = GetCustomBarLayout(settings, specID, sourceEntry, false)
        local copy = CopyTable(sourceEntry)
        copy.customBarId = nil
        newId = RB.AddCustomBar(settings, copy, specID, fallbackOrder)
        if newId then
            local targetLayout = EnsureCustomBarLayout(settings, specID, newId, fallbackOrder)
            if type(sourceLayout) == "table" and type(targetLayout) == "table" then
                for key, value in pairs(sourceLayout) do
                    targetLayout[key] = CopyTableValue(value)
                end
                if sourceLayout.order ~= nil then
                    targetLayout.order = (tonumber(sourceLayout.order) or 1000) + 1
                end
                if sourceLayout.verticalOrder ~= nil then
                    targetLayout.verticalOrder = (tonumber(sourceLayout.verticalOrder) or 1000) + 1
                end
            end
        end
    else
        local copy = CopyTable(sourceEntry)
        copy.customBarId = nil
        newId = EnsureCustomBarId(settings, copy)
        table.insert(customBars, sourceIndex + 1, copy)
    end
    if not newId then
        return nil
    end

    return newId
end

local function HideCustomBarRowDecorations(frame)
    if not frame then return end
    if frame._cdcCustomBarTypeBadge then frame._cdcCustomBarTypeBadge:Hide() end
    if frame._cdcCustomBarAuraStatusBadge then frame._cdcCustomBarAuraStatusBadge:Hide() end
    if frame._cdcCustomBarDisabledBadge then frame._cdcCustomBarDisabledBadge:Hide() end
    if frame._cdcModeBadgeHitRect then frame._cdcModeBadgeHitRect:Hide() end
    if frame._cdcGenericRenameBadge then frame._cdcGenericRenameBadge:Hide() end
    if frame._cdcAddBtn then frame._cdcAddBtn:Hide() end
    if frame._cdcAnchorBadge then frame._cdcAnchorBadge:Hide() end
    if frame._cdcHeaderDisabledBadge then frame._cdcHeaderDisabledBadge:Hide() end
    if frame._cdcBadges then
        for _, badge in ipairs(frame._cdcBadges) do
            badge:Hide()
        end
    end
    if frame._cdcCustomBarSpecBadges then
        for _, badge in ipairs(frame._cdcCustomBarSpecBadges) do
            badge:Hide()
        end
    end
end

local function OpenCustomBarRowMenu(customBars, specID, customBarId, entry)
    if not CS.customBarContextMenu then
        CS.customBarContextMenu = CreateFrame("Frame", "CDCCustomBarContextMenu", UIParent, "UIDropDownMenuTemplate")
    end

    UIDropDownMenu_Initialize(CS.customBarContextMenu, function(_, level)
        if level ~= 1 then return end

        local toggleInfo = UIDropDownMenu_CreateInfo()
        toggleInfo.text = (entry.enabled == true) and "Disable" or "Enable"
        toggleInfo.notCheckable = true
        toggleInfo.func = function()
            CloseDropDownMenus()
            entry.enabled = entry.enabled ~= true
            if entry.enabled and not entry.trackingMode then
                entry.trackingMode = "active"
            end
            ApplyCustomAuraBarPanelChanges({
                updateAnchors = true,
                refreshConfig = true,
            })
        end
        UIDropDownMenu_AddButton(toggleInfo, level)

        local duplicateInfo = UIDropDownMenu_CreateInfo()
        duplicateInfo.text = "Duplicate"
        duplicateInfo.notCheckable = true
        duplicateInfo.func = function()
            CloseDropDownMenus()
            local newId = DuplicateCustomBarById(CooldownCompanion:GetResourceBarSettings(), specID, customBars, customBarId)
            if newId then
                SelectConfigCustomBar(newId, {
                    clearPreview = true,
                    resetTab = true,
                })
            end
            ApplyCustomAuraBarPanelChanges({
                updateAnchors = true,
                refreshConfig = true,
            })
        end
        UIDropDownMenu_AddButton(duplicateInfo, level)

        local exportInfo = UIDropDownMenu_CreateInfo()
        exportInfo.text = "Export"
        exportInfo.notCheckable = true
        exportInfo.func = function()
            CloseDropDownMenus()
            local exportSettings = CooldownCompanion:GetResourceBarSettings()
            local payload = RB.BuildCustomBarsExportPayload and RB.BuildCustomBarsExportPayload(exportSettings, { entry })
            local exportString = payload and ST._EncodeExportData and ST._EncodeExportData(payload)
            if exportString then
                ShowPopupAboveConfig("CDC_EXPORT_CUSTOM_BARS", nil, { exportString = exportString })
            else
                CooldownCompanion:Print("Export failed: Custom Bar data was unavailable.")
            end
        end
        UIDropDownMenu_AddButton(exportInfo, level)

        local removeInfo = UIDropDownMenu_CreateInfo()
        removeInfo.text = "Remove"
        removeInfo.notCheckable = true
        removeInfo.func = function()
            CloseDropDownMenus()
            local settings = CooldownCompanion:GetResourceBarSettings()
            if DeleteCustomBarById(settings, specID, customBars, customBarId) then
                if CS.selectedCustomBarId == customBarId then
                    ClearConfigCustomBarSelection(true)
                end
                if CS.customBarSpecExpandedId == customBarId then
                    CS.customBarSpecExpandedId = nil
                end
            end
            ApplyCustomAuraBarPanelChanges({
                updateAnchors = true,
                refreshConfig = true,
            })
        end
        UIDropDownMenu_AddButton(removeInfo, level)
    end, "MENU")

    CS.customBarContextMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    ToggleDropDownMenu(1, nil, CS.customBarContextMenu, "cursor", 0, 0)
end

local function BuildSortedCustomBarSoundOptionOrder(soundOptions)
    local order = {}
    for optionKey in pairs(soundOptions or {}) do
        order[#order + 1] = optionKey
    end
    table.sort(order, function(a, b)
        if a == "None" then return true end
        if b == "None" then return false end
        local aLabel = soundOptions[a] or tostring(a)
        local bLabel = soundOptions[b] or tostring(b)
        if aLabel == bLabel then
            return tostring(a) < tostring(b)
        end
        return aLabel < bLabel
    end)
    return order
end

local function BuildCustomBarSoundAlertsTab(container, cab, infoButtons)
    local soundHeading = AceGUI:Create("Heading")
    soundHeading:SetText("Sound Alerts")
    ColorHeading(soundHeading)
    soundHeading:SetHeight(22)
    soundHeading:SetFullWidth(true)
    soundHeading.label:ClearAllPoints()
    soundHeading.label:SetPoint("CENTER", soundHeading.frame, "CENTER", 0, 2)
    soundHeading.left:ClearAllPoints()
    soundHeading.left:SetPoint("LEFT", soundHeading.frame, "LEFT", 3, 0)
    soundHeading.left:SetPoint("RIGHT", soundHeading.label, "LEFT", -5, 0)
    soundHeading.right:ClearAllPoints()
    soundHeading.right:SetPoint("RIGHT", soundHeading.frame, "RIGHT", -3, 0)
    soundHeading.right:SetPoint("LEFT", soundHeading.label, "RIGHT", 5, 0)
    container:AddChild(soundHeading)

    local soundInfoBtn = CreateInfoButton(soundHeading.frame, soundHeading.label, "LEFT", "RIGHT", 4, 0, {
        "Sound Alerts",
        {"Sound alerts are played through the Master channel and follow your game's Master volume setting.", 1, 1, 1, true},
    }, infoButtons)
    soundHeading.right:ClearAllPoints()
    soundHeading.right:SetPoint("RIGHT", soundHeading.frame, "RIGHT", -3, 0)
    soundHeading.right:SetPoint("LEFT", soundInfoBtn, "RIGHT", 4, 0)

    local validEvents = CooldownCompanion:GetScopedValidSoundAlertEventsForCustomBar(cab)
    if not validEvents then
        local noEvents = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(noEvents)
        noEvents:SetText("|cff888888No alertable sound events are available for this Custom Bar entry.|r")
        noEvents:SetFullWidth(true)
        container:AddChild(noEvents)
        return
    end

    local soundOptions = CooldownCompanion:GetSoundAlertOptions()
    local soundOptionOrder = BuildSortedCustomBarSoundOptionOrder(soundOptions)
    local eventOrder = CooldownCompanion:GetSoundAlertEventOrder()

    for _, eventKey in ipairs(eventOrder) do
        if validEvents[eventKey] then
            local soundDrop = AceGUI:Create("Dropdown")
            soundDrop:SetLabel(CooldownCompanion:GetCustomBarSoundAlertEventLabel(cab, eventKey))
            soundDrop:SetList(soundOptions, soundOptionOrder)
            soundDrop:SetValue(CooldownCompanion:GetCustomBarSoundAlertSelection(cab, eventKey))
            soundDrop:SetFullWidth(true)
            soundDrop:SetCallback("OnValueChanged", function(widget, event, val)
                CooldownCompanion:SetCustomBarSoundAlertEvent(cab, eventKey, val)
                CooldownCompanion:RefreshConfigPanel()
            end)
            container:AddChild(soundDrop)
        end
    end
end

local function BuildCustomBarLoadConditionsTab(container, cab, infoButtons)
    local addScopedLoadConditionToggles = ST._AddScopedLoadConditionToggles
    if type(addScopedLoadConditionToggles) ~= "function" then
        local unavailable = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(unavailable)
        unavailable:SetText("|cff888888Load condition controls are not available yet.|r")
        unavailable:SetFullWidth(true)
        container:AddChild(unavailable)
        return
    end

    addScopedLoadConditionToggles(container, {
        target = cab,
        defaults = CooldownCompanion:GetLocalLoadConditionDefaults(),
        inheritedSources = {},
        headingText = "Hide This Entry In",
        headingTextWhenInherited = "Also Hide This Entry In",
        inheritedCollapsedKey = "loadconditions_custombar_inherited",
        localCollapsedKey = "loadconditions_custombar_local",
        preserveMissing = true,
        onChanged = function()
            if cab.loadConditions and not next(cab.loadConditions) then
                cab.loadConditions = nil
            end
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:UpdateAnchorStacking()
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    if CooldownCompanion:HasLocalLoadConditions(cab) then
        local clearBtn = AceGUI:Create("Button")
        clearBtn:SetText("Clear Entry Load Conditions")
        clearBtn:SetFullWidth(true)
        clearBtn:SetCallback("OnClick", function()
            cab.loadConditions = nil
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:UpdateAnchorStacking()
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(clearBtn)
    end
end

local function AddCustomBarAuraTrackingGap(container)
    local spacer = AceGUI:Create("Label")
    spacer:SetText(" ")
    spacer:SetFullWidth(true)
    container:AddChild(spacer)
end

local function TrimCustomBarTrackedAuraText(text)
    return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function BuildCustomBarTrackedAuraError(token, reason)
    if reason == "ambiguous" then
        return "Multiple CDM auras match " .. token .. ". Pick the specific aura from the dropdown, or enter its aura spell ID."
    end
    return token .. " is not a CDM Tracked Buff/Bar aura."
end

local function ResolveCustomBarTrackedAuraText(rawText, shouldSkipToken)
    local text = TrimCustomBarTrackedAuraText(rawText)
    if text == "" then
        return nil
    end
    if not CS.ResolveCDMAuraAutocompleteEntry then
        return nil, "CDM aura autocomplete is not ready. Try again in a moment."
    end

    local resolvedIDs = {}
    for token in text:gmatch("[^,]+") do
        local cleaned = TrimCustomBarTrackedAuraText(token)
        if cleaned ~= "" then
            local skipToken = shouldSkipToken and shouldSkipToken(cleaned)
            if not skipToken then
                local entry, reason = CS.ResolveCDMAuraAutocompleteEntry(cleaned)
                local auraID = entry and tonumber(entry.id)
                if not auraID or auraID <= 0 then
                    return nil, BuildCustomBarTrackedAuraError(cleaned, reason)
                end
                resolvedIDs[#resolvedIDs + 1] = auraID
            end
        end
    end

    return #resolvedIDs > 0 and resolvedIDs or nil
end

local function BuildCustomBarStandaloneAuraButtonData(cab, spellID, rawAuraSpellID)
    spellID = tonumber(spellID)
    if not spellID or IsSpellCustomBarConfig(cab) then
        return nil
    end

    return {
        type = "spell",
        id = spellID,
        auraSpellID = rawAuraSpellID,
        auraTracking = true,
        addedAs = "aura",
    }
end

local function GetCustomBarStandaloneAuraFallbackSpellIDText(cab, spellID, rawAuraSpellID)
    local buttonData = BuildCustomBarStandaloneAuraButtonData(cab, spellID, rawAuraSpellID)
    if not buttonData or not CooldownCompanion.GetStandaloneAuraFallbackSpellIDText then
        return rawAuraSpellID
    end
    return CooldownCompanion:GetStandaloneAuraFallbackSpellIDText(buttonData, rawAuraSpellID)
end

local function IsCustomBarOriginalStandaloneAuraID(cab, spellID, auraID)
    auraID = tonumber(auraID)
    local buttonData = auraID and BuildCustomBarStandaloneAuraButtonData(cab, spellID)
    if not buttonData or not CooldownCompanion.GetStandaloneAuraCandidateGroups then
        return false
    end

    local originalAuraIDs = CooldownCompanion:GetStandaloneAuraCandidateGroups(buttonData)
    for _, originalAuraID in ipairs(originalAuraIDs or {}) do
        if auraID == tonumber(originalAuraID) then
            return true
        end
    end
    return false
end

local function GetCustomBarTrackedAuraIDList(cab, spellID)
    local ids = {}
    local seen = {}
    local rawIDs = cab and cab.auraSpellID
    rawIDs = IsSpellCustomBarConfig(cab)
        and rawIDs
        or GetCustomBarStandaloneAuraFallbackSpellIDText(cab, spellID, rawIDs)
    if rawIDs then
        for id in tostring(rawIDs):gmatch("%d+") do
            local auraID = tonumber(id)
            if auraID and auraID > 0 and not seen[auraID] then
                seen[auraID] = true
                ids[#ids + 1] = auraID
            end
        end
    end
    return ids
end

local function SetCustomBarTrackedAuraIDList(cab, spellID, ids)
    local normalizedIDs = {}
    local seen = {}
    for _, id in ipairs(ids or {}) do
        local auraID = tonumber(id)
        if auraID and auraID > 0 and not seen[auraID] then
            seen[auraID] = true
            normalizedIDs[#normalizedIDs + 1] = tostring(auraID)
        end
    end

    local rawText = #normalizedIDs > 0 and table.concat(normalizedIDs, ",") or nil
    cab.auraSpellID = IsSpellCustomBarConfig(cab)
        and rawText
        or GetCustomBarStandaloneAuraFallbackSpellIDText(cab, spellID, rawText)
    EnsureCustomAuraBarAuraUnit(cab, spellID)
end

local function AddCustomBarTrackedAuraID(cab, spellID, auraID)
    auraID = tonumber(auraID)
    if not auraID or auraID <= 0 then
        return false
    end
    if IsCustomBarOriginalStandaloneAuraID(cab, spellID, auraID) then
        return false
    end

    local ids = GetCustomBarTrackedAuraIDList(cab, spellID)
    for _, existingID in ipairs(ids) do
        if existingID == auraID then
            return false
        end
    end

    ids[#ids + 1] = auraID
    SetCustomBarTrackedAuraIDList(cab, spellID, ids)
    return true
end

local function AddCustomBarTrackedAuraIDText(cab, spellID, rawText)
    local resolvedIDs, errorText = ResolveCustomBarTrackedAuraText(rawText, function(cleaned)
        local auraID = cleaned:match("^%d+$") and tonumber(cleaned) or nil
        return IsCustomBarOriginalStandaloneAuraID(cab, spellID, auraID)
    end)
    if not resolvedIDs then
        if errorText then
            CooldownCompanion:Print(errorText)
        end
        return false
    end

    local ids = GetCustomBarTrackedAuraIDList(cab, spellID)
    local seen = {}
    for _, auraID in ipairs(ids) do
        seen[auraID] = true
    end

    local added = false
    for _, auraID in ipairs(resolvedIDs) do
        if auraID and auraID > 0 and not seen[auraID] and not IsCustomBarOriginalStandaloneAuraID(cab, spellID, auraID) then
            seen[auraID] = true
            ids[#ids + 1] = auraID
            added = true
        end
    end

    if added then
        SetCustomBarTrackedAuraIDList(cab, spellID, ids)
    end
    return added
end

local function MoveCustomBarTrackedAuraID(cab, spellID, sourceIndex, targetIndex)
    local ids = GetCustomBarTrackedAuraIDList(cab, spellID)
    sourceIndex = tonumber(sourceIndex)
    targetIndex = tonumber(targetIndex)
    if not sourceIndex or not targetIndex or sourceIndex < 1 or sourceIndex > #ids then
        return false
    end
    if targetIndex < 1 then targetIndex = 1 end
    if targetIndex > #ids then targetIndex = #ids end
    if targetIndex == sourceIndex then
        return false
    end

    local movedID = table.remove(ids, sourceIndex)
    if not movedID then
        return false
    end
    table.insert(ids, targetIndex, movedID)
    SetCustomBarTrackedAuraIDList(cab, spellID, ids)
    return true
end

local function RemoveCustomBarTrackedAuraID(cab, spellID, rowIndex)
    local ids = GetCustomBarTrackedAuraIDList(cab, spellID)
    rowIndex = tonumber(rowIndex)
    if not rowIndex or rowIndex < 1 or rowIndex > #ids then
        return false
    end

    table.remove(ids, rowIndex)
    SetCustomBarTrackedAuraIDList(cab, spellID, ids)
    return true
end

local function RefreshCustomBarTrackedAuraEntry(cab, spellID)
    if CS.HideAutocomplete then
        CS.HideAutocomplete()
    end
    EnsureCustomAuraBarAuraUnit(cab, spellID)
    ApplyCustomAuraBarPanelChanges({
        updateAnchors = true,
        refreshConfig = true,
    })
end

local function GetCustomBarTrackedAuraDisplayName(auraID)
    return C_Spell.GetSpellName(auraID) or ("Spell " .. tostring(auraID))
end

local function BuildCustomBarTrackedAuraRowText(auraID, rowIndex)
    return ("%d. %s |cff888888%s|r"):format(
        rowIndex,
        GetCustomBarTrackedAuraDisplayName(auraID),
        tostring(auraID)
    )
end

local function ConfigureCustomBarTrackedAuraMoveButton(button, rotation, tooltipTitle, tooltipBody, disabled, onClick)
    local isDisabled = disabled or CS.browseMode
    button:SetSize(18, 18)
    if button.text then
        button.text:Hide()
    end
    if not button.icon then
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetPoint("TOPLEFT", 2, -2)
        button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    end
    if button.highlight then
        button.highlight:Hide()
        button.highlight:SetAlpha(0)
    end
    button.icon:SetAtlas("arrow-short", false)
    button.icon:SetRotation(rotation)
    if button.icon.SetDesaturated then
        button.icon:SetDesaturated(isDisabled == true)
    end
    button.icon:SetVertexColor(1, 0.82, 0, isDisabled and 0.45 or 1)
    button.icon:Show()
    button:SetAlpha(isDisabled and 0.35 or 1)
    button:EnableMouse(true)
    button:SetScript("OnClick", isDisabled and nil or onClick)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(tooltipTitle)
        GameTooltip:AddLine(tooltipBody, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    button:Show()
end

local function EnsureCustomBarTrackedAuraMoveButtons(entry, cab, spellID, rowIndex, rowCount)
    local frame = entry.frame
    local upBtn = frame._cdcCustomBarAuraUpBtn
    if not upBtn then
        upBtn = CreateFrame("Button", nil, frame)
        frame._cdcCustomBarAuraUpBtn = upBtn
    end
    local downBtn = frame._cdcCustomBarAuraDownBtn
    if not downBtn then
        downBtn = CreateFrame("Button", nil, frame)
        frame._cdcCustomBarAuraDownBtn = downBtn
    end

    upBtn:ClearAllPoints()
    upBtn:SetPoint("RIGHT", frame, "RIGHT", -24, 0)
    upBtn:SetFrameLevel(frame:GetFrameLevel() + 6)
    ConfigureCustomBarTrackedAuraMoveButton(
        upBtn,
        math.pi / 2,
        "Move Up",
        "Move this aura one priority slot higher.",
        rowIndex <= 1,
        function()
            if MoveCustomBarTrackedAuraID(cab, spellID, rowIndex, rowIndex - 1) then
                RefreshCustomBarTrackedAuraEntry(cab, spellID)
            end
        end
    )

    downBtn:ClearAllPoints()
    downBtn:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
    downBtn:SetFrameLevel(frame:GetFrameLevel() + 6)
    ConfigureCustomBarTrackedAuraMoveButton(
        downBtn,
        -math.pi / 2,
        "Move Down",
        "Move this aura one priority slot lower.",
        rowIndex >= rowCount,
        function()
            if MoveCustomBarTrackedAuraID(cab, spellID, rowIndex, rowIndex + 1) then
                RefreshCustomBarTrackedAuraEntry(cab, spellID)
            end
        end
    )
end

local function ShowCustomBarTrackedAuraRowMenu(cab, spellID, rowIndex)
    if CS.browseMode then
        return
    end

    if not CS.customBarTrackedAuraContextMenu then
        CS.customBarTrackedAuraContextMenu = CreateFrame("Frame", "CDCCustomBarTrackedAuraContextMenu", UIParent, "UIDropDownMenuTemplate")
    end

    UIDropDownMenu_Initialize(CS.customBarTrackedAuraContextMenu, function(_, level)
        if level ~= 1 then return end
        local info = UIDropDownMenu_CreateInfo()
        info.text = "|cffff4444Delete|r"
        info.notCheckable = true
        info.registerForAnyClick = true
        info.func = function()
            CloseDropDownMenus()
            if RemoveCustomBarTrackedAuraID(cab, spellID, rowIndex) then
                RefreshCustomBarTrackedAuraEntry(cab, spellID)
            end
        end
        UIDropDownMenu_AddButton(info, level)
    end, "MENU")
    CS.customBarTrackedAuraContextMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    ToggleDropDownMenu(1, nil, CS.customBarTrackedAuraContextMenu, "cursor", 0, 0)
end

local function InstallCustomBarTrackedAuraRowMenu(entry, cab, spellID, rowIndex)
    entry.frame:SetScript("OnMouseUp", function(_, button)
        if CS.browseMode then
            return
        end
        if button == "RightButton" then
            ShowCustomBarTrackedAuraRowMenu(cab, spellID, rowIndex)
        end
    end)
end

local function CreateCustomBarTrackedAuraRow(container, cab, spellID, auraID, rowIndex, rowCount)
    local row = AceGUI:Create("InteractiveLabel")
    local icon = C_Spell.GetSpellTexture(auraID) or 134400
    CleanRecycledEntry(row)
    row:SetText(BuildCustomBarTrackedAuraRowText(auraID, rowIndex))
    row:SetFullWidth(true)
    row:SetFontObject(GameFontHighlightSmall)
    row:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    ApplyConfigRowIcon(row, icon, { rightPad = 48 })
    if BindConfigShiftTooltip then
        BindConfigShiftTooltip(row, "spell", auraID, row.frame, "ANCHOR_RIGHT")
    end
    row._cdcAfterConfigRowLayout = function(self)
        local frame = self.frame
        local label = self.label
        local image = self.image
        self:SetHeight(22)
        frame:SetHeight(22)
        frame.height = 22
        if image then
            image:ClearAllPoints()
            image:SetTexture(icon)
            image:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            image:SetSize(18, 18)
            image:SetPoint("LEFT", frame, "LEFT", 2, 0)
            image:Show()
        end
        if label then
            label:ClearAllPoints()
            label:SetPoint("LEFT", frame, "LEFT", 24, 0)
            label:SetPoint("RIGHT", frame, "RIGHT", -48, 0)
            label:SetJustifyH("LEFT")
            label:SetJustifyV("MIDDLE")
            if label.SetWordWrap then
                label:SetWordWrap(false)
            end
            if label.SetNonSpaceWrap then
                label:SetNonSpaceWrap(false)
            end
            if label.SetMaxLines then
                label:SetMaxLines(1)
            end
        end
    end
    row:_cdcAfterConfigRowLayout()
    EnsureCustomBarTrackedAuraMoveButtons(row, cab, spellID, rowIndex, rowCount)
    InstallCustomBarTrackedAuraRowMenu(row, cab, spellID, rowIndex)
    container:AddChild(row)
    return row
end

local function AddCustomBarSettingsHeading(container, text, infoButtons, tooltip)
    local heading = AceGUI:Create("Heading")
    heading:SetText(text)
    ColorHeading(heading)
    heading:SetFullWidth(true)
    container:AddChild(heading)

    if tooltip then
        local tooltipLines = { text }
        if type(tooltip) == "table" then
            for _, line in ipairs(tooltip) do
                tooltipLines[#tooltipLines + 1] = { line, 1, 1, 1, true }
            end
        else
            tooltipLines[#tooltipLines + 1] = { tooltip, 1, 1, 1, true }
        end
        local infoBtn = CreateInfoButton(heading.frame, heading.label, "LEFT", "RIGHT", 4, 0, {
            unpack(tooltipLines)
        }, infoButtons)
        heading.right:ClearAllPoints()
        heading.right:SetPoint("RIGHT", heading.frame, "RIGHT", -3, 0)
        heading.right:SetPoint("LEFT", infoBtn, "RIGHT", 4, 0)
    end
end

local function BuildCustomBarAuraTrackingSection(container, cab, resolvedAuraUnit, infoButtons)
    local isSpellCustomBar = IsSpellCustomBarConfig(cab)
    local spellID = tonumber(cab and cab.spellID)
    if isSpellCustomBar and spellID and not (resolvedAuraUnit == "player" or resolvedAuraUnit == "target") then
        resolvedAuraUnit = EnsureCustomAuraBarAuraUnit(cab, spellID)
    end

    local heading = AceGUI:Create("Heading")
    heading:SetText("Aura Tracking")
    ColorHeading(heading)
    heading:SetFullWidth(true)
    container:AddChild(heading)

    local infoBtn = CreateInfoButton(heading.frame, heading.label, "LEFT", "RIGHT", 4, 0, {
        "Aura Tracking",
        {isSpellCustomBar and "Shows a tracked buff or debuff on top of this spell Custom Bar." or "Shows the tracked aura's remaining duration or stack state on this Custom Bar.", 1, 1, 1, true},
        " ",
        {isSpellCustomBar and "This follows the same Tracked Auras model used by spell entries in bar panels." or "Custom Bars keep their tracked aura identity in the entry row. This section shows whether that aura is ready to drive the bar.", 1, 1, 1, true},
        " ",
        "Requires:",
        {"- Blizzard Cooldown Manager (CDM) must be enabled.", 1, 1, 1, true},
        {"- In Edit Mode, the CDM Buffs/Debuffs visibility setting must be set to Always Visible.", 1, 1, 1, true},
        {"- The aura must be tracked in CDM as a Tracked Buff or Tracked Bar.", 1, 1, 1, true},
    }, infoButtons)
    heading.right:ClearAllPoints()
    heading.right:SetPoint("RIGHT", heading.frame, "RIGHT", -3, 0)
    heading.right:SetPoint("LEFT", infoBtn, "RIGHT", 4, 0)

    local cdmEnabled = C_CVar.GetCVarBool("cooldownViewerEnabled") == true
    local auraTrackingEnabled = true
    if isSpellCustomBar then
        auraTrackingEnabled = cab.auraTracking == true
    end
    local auraSpellID = cab.auraSpellID
    local buttonData = spellID and {
            type = "spell",
            id = spellID,
            auraSpellID = auraSpellID,
            auraTracking = auraTrackingEnabled,
            auraUnit = resolvedAuraUnit,
            addedAs = isSpellCustomBar and nil or "aura",
        } or nil
    local viewerFrame = buttonData and CooldownCompanion:ResolveButtonAuraViewerFrame(buttonData) or nil
    local auraStatus = buttonData and CooldownCompanion:ResolveAuraTrackingConfigStatus(buttonData, cdmEnabled, viewerFrame)
        or { state = "noAssociatedAura", ready = false, cdmEnabled = cdmEnabled }
    local auraConfigReady = auraStatus.ready == true
    local inactiveColor = auraStatus.state == "associatedAuraNotTracked" and "|cffffff00" or "|cffff0000"

    local auraLabel = "Aura Tracking"
    auraLabel = auraLabel .. (auraConfigReady and ": |cff00ff00Active|r" or ": " .. inactiveColor .. "Inactive|r")

    if isSpellCustomBar then
        local auraCb = AceGUI:Create("CheckBox")
        auraCb:SetLabel(auraLabel)
        auraCb:SetValue(cab.auraTracking == true)
        auraCb:SetFullWidth(true)
        auraCb:SetCallback("OnValueChanged", function(_, _, value)
            cab.auraTracking = value and true or false
            if value then
                EnsureCustomAuraBarAuraUnit(cab, spellID)
            else
                CooldownCompanion:SetCustomAuraBarActivePreview(cab, false)
                CooldownCompanion:SetCustomAuraBarPandemicPreview(cab, false)
            end
            ApplyCustomAuraBarPanelChanges({
                updateAnchors = true,
                refreshConfig = true,
            })
        end)
        container:AddChild(auraCb)

        if cab.auraTracking ~= true then
            AddCustomBarAuraTrackingGap(container)
            return
        end
    end

    local trackedAuraFieldLabel = isSpellCustomBar and "Tracked Auras" or "Additional Auras"
    local trackedAuraFieldTooltip = isSpellCustomBar
        and "Most spells are tracked automatically, but some abilities apply a buff or debuff with a different aura ID than the spell itself. Search for CDM tracked auras by name, or enter CDM aura spell IDs, to choose which auras should count for this Custom Bar.\n\nUse arrows to set tracked aura priority. Right-click a row to delete it. Use \"Pick CDM\" below to visually select an aura from the Cooldown Manager."
        or "The original aura is checked first. Add CDM tracked auras here when another aura should also count for this Custom Bar.\n\nUse arrows to set additional aura priority. Right-click a row to delete it. Use \"Pick CDM\" below to visually select an aura from the Cooldown Manager."
    local auraIDList = GetCustomBarTrackedAuraIDList(cab, spellID)
    local auraEditBox = AceGUI:Create("EditBox")
    if auraEditBox.editbox.Instructions then
        auraEditBox.editbox.Instructions:Hide()
    end
    auraEditBox:SetLabel(trackedAuraFieldLabel)
    auraEditBox:SetText("")
    auraEditBox:DisableButton(true)
    auraEditBox:SetFullWidth(true)
    local function CommitCustomBarTrackedAuraEntry(widget, entry)
        CS.HideAutocomplete()
        if not (entry and AddCustomBarTrackedAuraIDText(cab, spellID, tostring(entry.id))) then
            return
        end
        widget:SetText("")
        RefreshCustomBarTrackedAuraEntry(cab, spellID)
    end
    auraEditBox:SetCallback("OnTextChanged", function(widget, _, text)
        if CS.browseMode then
            CS.HideAutocomplete()
            return
        end
        if text and #text >= 1 and CS.SearchCDMAuraAutocomplete then
            CS.ShowAutocompleteResults(CS.SearchCDMAuraAutocomplete(text), widget, function(entry)
                CommitCustomBarTrackedAuraEntry(widget, entry)
            end, { requireExactNumericEnter = true })
        else
            CS.HideAutocomplete()
        end
    end)
    auraEditBox:SetCallback("OnEnterPressed", function(widget, _, text)
        if CS.browseMode then
            CS.HideAutocomplete()
            return
        end
        if CS.ConsumeAutocompleteEnter and CS.ConsumeAutocompleteEnter() then
            return
        end
        CS.HideAutocomplete()
        if not AddCustomBarTrackedAuraIDText(cab, spellID, text) then
            return
        end
        widget:SetText("")
        RefreshCustomBarTrackedAuraEntry(cab, spellID)
    end)
    if CS.SetupAutocompleteKeyHandler then
        CS.SetupAutocompleteKeyHandler(auraEditBox)
    end
    container:AddChild(auraEditBox)

    CreateInfoButton(auraEditBox.frame, auraEditBox.frame, "TOPLEFT", "TOPLEFT", auraEditBox.label:GetStringWidth() + 4, -2, {
        trackedAuraFieldLabel,
        {trackedAuraFieldTooltip, 1, 1, 1, true},
    }, infoButtons)

    for index, auraID in ipairs(auraIDList) do
        CreateCustomBarTrackedAuraRow(container, cab, spellID, auraID, index, #auraIDList)
    end

    AddCustomBarAuraTrackingGap(container)

    if isSpellCustomBar or spellID then
        if not (cab.auraUnit == "player" or cab.auraUnit == "target") then
            resolvedAuraUnit = EnsureCustomAuraBarAuraUnit(cab, spellID)
        end

        local auraUnitDrop = AceGUI:Create("Dropdown")
        auraUnitDrop:SetLabel("Aura Unit")
        auraUnitDrop:SetList({
            player = "Player",
            target = "Target",
        }, { "player", "target" })
        auraUnitDrop:SetValue((cab.auraUnitExplicit == true and cab.auraUnit) or resolvedAuraUnit or "player")
        auraUnitDrop:SetFullWidth(true)
        auraUnitDrop:SetCallback("OnValueChanged", function(_, _, value)
            if value ~= "player" and value ~= "target" then
                return
            end
            EnsureCustomAuraBarAuraUnit(cab, spellID, value)
            ApplyCustomAuraBarPanelChanges({
                updateAnchors = true,
                refreshConfig = true,
            })
        end)
        container:AddChild(auraUnitDrop)
        CreateInfoButton(auraUnitDrop.frame, auraUnitDrop.label, "LEFT", "RIGHT", 4, 0, {
            "Aura Unit",
            {"This is an entry-wide setting. It controls where every Tracked Aura or Additional Aura on this Custom Bar is expected to exist. Use Target for debuffs on your target, or Player for buffs/procs on yourself, even if the Custom Bar's spell is something else.", 1, 1, 1, true},
        }, infoButtons)

        AddCustomBarAuraTrackingGap(container)
    end

    local cdmToggleBtn = AceGUI:Create("Button")
    cdmToggleBtn:SetText(cdmEnabled and "Blizzard CDM: |cff00ff00Active|r" or "Blizzard CDM: |cffff0000Inactive|r")
    cdmToggleBtn:SetFullWidth(true)
    cdmToggleBtn:SetCallback("OnClick", function()
        local current = C_CVar.GetCVarBool("cooldownViewerEnabled") == true
        C_CVar.SetCVar("cooldownViewerEnabled", current and "0" or "1")
        CooldownCompanion:RefreshConfigPanel()
        if not current then
            C_Timer.After(0.2, function()
                CooldownCompanion:BuildViewerAuraMap()
                CooldownCompanion:RefreshConfigPanel()
            end)
        end
    end)
    container:AddChild(cdmToggleBtn)

    local cdmRow = AceGUI:Create("SimpleGroup")
    cdmRow:SetFullWidth(true)
    cdmRow:SetLayout("Flow")

    local openCdmBtn = AceGUI:Create("Button")
    openCdmBtn:SetText("CDM Settings")
    openCdmBtn:SetRelativeWidth(0.5)
    openCdmBtn:SetCallback("OnClick", function()
        if CooldownViewerSettings then
            CooldownViewerSettings:TogglePanel()
        end
    end)
    cdmRow:AddChild(openCdmBtn)

    local pickCDMBtn = AceGUI:Create("Button")
    pickCDMBtn:SetText("Pick CDM")
    pickCDMBtn:SetRelativeWidth(0.5)
    pickCDMBtn:SetCallback("OnClick", function()
        CS.StartPickCDM(function(pickedSpellID)
            if CS.configFrame then
                CS.configFrame.frame:Show()
            end
            if pickedSpellID then
                AddCustomBarTrackedAuraID(cab, spellID, pickedSpellID)
            end
            ApplyCustomAuraBarPanelChanges({
                updateAnchors = true,
                refreshConfig = true,
            })
        end)
    end)
    pickCDMBtn:SetCallback("OnEnter", function(widget)
        GameTooltip:SetOwner(widget.frame, "ANCHOR_TOP")
        GameTooltip:AddLine("Pick from Cooldown Manager")
        GameTooltip:AddLine("Shows a list of Tracked Buff/Tracked Bar auras currently tracked in the Cooldown Manager. Click one to add it to " .. trackedAuraFieldLabel .. ".", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    pickCDMBtn:SetCallback("OnLeave", function()
        GameTooltip:Hide()
    end)
    cdmRow:AddChild(pickCDMBtn)
    container:AddChild(cdmRow)

    AddCustomBarAuraTrackingGap(container)

    local statusLabel = AceGUI:Create("Label")
    ST._ConfigureWrappedHelperLabel(statusLabel)
    statusLabel:SetText(auraConfigReady and "|cff00ff00Aura tracking is active and ready.|r" or (inactiveColor .. "Aura tracking is not ready.|r"))
    statusLabel:SetFullWidth(true)
    statusLabel:SetJustifyH("CENTER")
    container:AddChild(statusLabel)
    AddCustomBarAuraTrackingGap(container)

    local explainText
    if auraStatus.state == "cdmDisabled" then
        explainText = "|cff888888Blizzard Cooldown Manager is disabled. Enable it above to allow aura tracking.|r"
    elseif auraStatus.state == "noAssociatedAura" then
        explainText = "|cff888888This aura was not found in Blizzard CDM's tracked buff or tracked bar data.|r"
    elseif auraStatus.state == "trackedAuraUnavailable" then
        explainText = "|cff888888This aura is tracked in Blizzard CDM, but its Buffs/Debuffs viewer is not currently readable. Set the CDM Buffs/Debuffs visibility to Always Visible.|r"
    elseif auraStatus.state == "associatedAuraNotTracked" then
        explainText = "|cff888888This aura was found, but it is not currently tracked in CDM as a Tracked Buff or Tracked Bar.|r"
    end

    if explainText then
        local explainLabel = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(explainLabel)
        explainLabel:SetText(explainText)
        explainLabel:SetFullWidth(true)
        container:AddChild(explainLabel)
        AddCustomBarAuraTrackingGap(container)
    end

end

local function BuildCustomBarVisibilityRulesSection(container, customBars, capturedIdx, cab, resolvedAuraUnit, capturedKey, infoButtons)
    if cab.hideWhenInactive == true and cab.hideWhileAuraActive == true then
        cab.hideWhileAuraActive = nil
        cab.hideAuraActiveExceptPandemic = nil
    end

    local heading = AceGUI:Create("Heading")
    heading:SetText("Visibility Rules")
    ColorHeading(heading)
    heading:SetFullWidth(true)
    container:AddChild(heading)

    local visibilityKey = "cab_visibility_" .. tostring(capturedKey)
    local visibilityCollapsed = resourceBarCollapsedSections[visibilityKey]
    local collapseBtn = AttachCollapseButton(heading, visibilityCollapsed, function()
        resourceBarCollapsedSections[visibilityKey] = not resourceBarCollapsedSections[visibilityKey]
        CooldownCompanion:RefreshConfigPanel()
    end)

    local infoBtn = CreateInfoButton(heading.frame, collapseBtn, "LEFT", "RIGHT", 2, 0, {
        "Visibility Rules",
        {"Show or hide this Custom Bar based on whether its tracked aura is active.", 1, 1, 1, true},
    }, infoButtons)
    heading.right:ClearAllPoints()
    heading.right:SetPoint("RIGHT", heading.frame, "RIGHT", -3, 0)
    heading.right:SetPoint("LEFT", infoBtn, "RIGHT", 4, 0)

    if visibilityCollapsed then
        return
    end

    local hideAuraCb = AceGUI:Create("CheckBox")
    hideAuraCb:SetLabel("Hide While Aura Active")
    hideAuraCb:SetValue(cab.hideWhileAuraActive == true)
    hideAuraCb:SetFullWidth(true)
    hideAuraCb:SetCallback("OnValueChanged", function(widget, event, val)
        customBars[capturedIdx].hideWhileAuraActive = val or nil
        if val then
            customBars[capturedIdx].hideWhenInactive = nil
        else
            customBars[capturedIdx].hideAuraActiveExceptPandemic = nil
        end
        ApplyCustomAuraBarPanelChanges({
            updateAnchors = true,
            refreshConfig = true,
        })
    end)
    container:AddChild(hideAuraCb)
    CreateInfoButton(hideAuraCb.frame, hideAuraCb.checkbg, "LEFT", "RIGHT", hideAuraCb.text:GetStringWidth() + 4, 0, {
        "Hide While Aura Active",
        {"Hides this Custom Bar while the tracked aura is currently active.", 1, 1, 1, true},
    }, infoButtons)

    if resolvedAuraUnit == "target" then
        local pandemicCb = AceGUI:Create("CheckBox")
        pandemicCb:SetLabel("Except in Pandemic")
        pandemicCb:SetValue(cab.hideAuraActiveExceptPandemic == true)
        pandemicCb:SetFullWidth(true)
        if cab.hideWhileAuraActive ~= true then
            pandemicCb:SetDisabled(true)
        end
        pandemicCb:SetCallback("OnValueChanged", function(widget, event, val)
            customBars[capturedIdx].hideAuraActiveExceptPandemic = val or nil
            ApplyCustomAuraBarPanelChanges({
                updateAnchors = true,
                refreshConfig = true,
            })
        end)
        container:AddChild(pandemicCb)
        ApplyCheckboxIndent(pandemicCb, 20)
        CreateInfoButton(pandemicCb.frame, pandemicCb.checkbg, "LEFT", "RIGHT", pandemicCb.text:GetStringWidth() + 4, 0, {
            "Except in Pandemic",
            {"Shows the bar during the pandemic window so you know when to reapply the target aura.", 1, 1, 1, true},
        }, infoButtons)
    end

    local hideNoAuraCb = AceGUI:Create("CheckBox")
    hideNoAuraCb:SetLabel("Hide While Aura Not Active")
    hideNoAuraCb:SetValue(cab.hideWhenInactive == true)
    hideNoAuraCb:SetFullWidth(true)
    hideNoAuraCb:SetCallback("OnValueChanged", function(widget, event, val)
        customBars[capturedIdx].hideWhenInactive = val or nil
        if val then
            customBars[capturedIdx].hideWhileAuraActive = nil
            customBars[capturedIdx].hideAuraActiveExceptPandemic = nil
        end
        ApplyCustomAuraBarPanelChanges({
            updateAnchors = true,
            refreshConfig = true,
        })
    end)
    container:AddChild(hideNoAuraCb)
    CreateInfoButton(hideNoAuraCb.frame, hideNoAuraCb.checkbg, "LEFT", "RIGHT", hideNoAuraCb.text:GetStringWidth() + 4, 0, {
        "Hide While Aura Not Active",
        {"Hides this Custom Bar until the tracked aura is active.", 1, 1, 1, true},
    }, infoButtons)
end

local function AddResourceBarsDisabledLabel(container, text)
    local label = AceGUI:Create("Label")
    ST._ConfigureWrappedHelperLabel(label)
    label:SetText(text)
    label:SetFullWidth(true)
    container:AddChild(label)
end

local function BuildCustomBarsListPanel(container)
    local settings = CooldownCompanion:GetResourceBarSettings()
    if not (settings and settings.enabled) then
        AddResourceBarsDisabledLabel(container, "Enable Resource Bars to configure Custom Bars.")
        return
    end

    local customBarsSpecID = GetCurrentConfigSpecID()
    local customBars = RB.GetAllCustomBars and RB.GetAllCustomBars(settings) or CooldownCompanion:GetSpecCustomAuraBars()
    PruneConfigCustomBarSelection(function(customBarId)
        return FindCustomBarIndexById(customBars, customBarId) ~= nil
    end)
    local selectedId = CS.selectedCustomBarId

    local addBox = AceGUI:Create("EditBox")
    if addBox.editbox.Instructions then addBox.editbox.Instructions:Hide() end
    addBox:SetLabel("")
    addBox:SetFullWidth(true)
    addBox:DisableButton(true)
    local updatePlaceholder = ConfigureCustomBarAddInstructions(addBox, "Add spell or aura by name or ID")

    local function GetCustomBarEntryTypeForAutocomplete(entry)
        if type(entry) ~= "table" then
            return "spell"
        end
        if entry.forceAura == true or entry.isPassive == true then
            return "aura"
        end
        if entry.forceAura == false then
            return "spell"
        end
        if IsPassiveOrProc and entry.id and IsPassiveOrProc(entry.id) then
            return "aura"
        end
        return "spell"
    end

    local function StripExplicitCustomBarEntryTypeSuffix(text)
        local cleaned = text and text:gsub("^%s+", ""):gsub("%s+$", ""):lower() or ""
        if cleaned:match("%s%((buff)%)$") or cleaned:match("%s%((aura)%)$") then
            return (text or ""):gsub("%s+%([Bb][Uu][Ff][Ff]%)%s*$", ""):gsub("%s+%([Aa][Uu][Rr][Aa]%)%s*$", ""), "aura"
        end
        if cleaned:match("%s%((cooldown)%)$") then
            return (text or ""):gsub("%s+%([Cc][Oo][Oo][Ll][Dd][Oo][Ww][Nn]%)%s*$", ""), "spell"
        end
        return text, nil
    end

    local function GetCustomBarEntryTypeForSpellID(spellId, explicitType)
        if explicitType then
            return explicitType
        end
        if not spellId or not C_Spell.GetSpellInfo(spellId) then
            return "aura"
        end
        local sawAuraEntry = false
        local sawSpellEntry = false
        local cache = BuildAuraBarAutocompleteCache and BuildAuraBarAutocompleteCache() or nil
        for _, entry in ipairs(cache or {}) do
            if entry.id == spellId then
                if GetCustomBarEntryTypeForAutocomplete(entry) == "aura" then
                    sawAuraEntry = true
                else
                    sawSpellEntry = true
                end
            end
        end
        if sawAuraEntry and not sawSpellEntry then
            return "aura"
        elseif sawSpellEntry and not sawAuraEntry then
            return "spell"
        end
        if IsPassiveOrProc and IsPassiveOrProc(spellId) then
            return "aura"
        end
        return "spell"
    end

    local function AddCustomBarFromSpell(spellId, labelOverride, entryType)
        if not spellId then return false end
        entryType = entryType == "aura" and "aura" or "spell"
        local entry = {
            entryType = entryType,
            enabled = true,
            spellID = spellId,
            label = labelOverride or GetAuraBarAutocompleteDisplayName(spellId) or C_Spell.GetSpellName(spellId) or "",
        }
        if entryType == "aura" then
            entry.trackingMode = "active"
            RefreshCustomAuraBarAuraUnitForSpell(entry, spellId)
        else
            local charges = C_Spell.GetSpellCharges(spellId)
            local maxCharges = charges and tonumber(charges.maxCharges)
            if maxCharges and maxCharges > 1 then
                entry.hasCharges = true
                entry.maxCharges = maxCharges
            end
        end
        local id = RB.AddCustomBar
            and RB.AddCustomBar(settings, entry, customBarsSpecID, 1000 + #CooldownCompanion:GetSpecCustomAuraBars() + 1)
            or EnsureCustomBarId(settings, entry)
        if not RB.AddCustomBar then
            customBars[#customBars + 1] = entry
            EnsureCustomBarLayout(settings, nil, id, 1000 + #customBars)
        end
        SelectConfigCustomBar(id)
        ApplyCustomAuraBarPanelChanges({
            updateAnchors = true,
            refreshConfig = true,
        })
        return true
    end

    local function CommitCustomBarText(widget, text)
        local lookupText, explicitType = StripExplicitCustomBarEntryTypeSuffix(text)
        local autocompleteEntry = ResolveAuraBarAutocompleteEntry and (
            ResolveAuraBarAutocompleteEntry(text)
            or (lookupText ~= text and ResolveAuraBarAutocompleteEntry(lookupText))
        )
        if autocompleteEntry and AddCustomBarFromSpell(
            autocompleteEntry.id,
            GetAuraBarAutocompleteEntryName(autocompleteEntry),
            explicitType or GetCustomBarEntryTypeForAutocomplete(autocompleteEntry)
        ) then
            widget:SetText("")
            return true
        end

        local id, explicitClear = ResolveAuraColorSpellIDFromText(lookupText)
        if explicitClear then
            widget:SetText("")
            return true
        end
        if AddCustomBarFromSpell(id, nil, GetCustomBarEntryTypeForSpellID(id, explicitType)) then
            widget:SetText("")
            return true
        end

        local cleaned = text and text:gsub("^%s+", ""):gsub("%s+$", "") or ""
        if cleaned ~= "" then
            CooldownCompanion:Print("Custom Bar spell or aura not found: " .. cleaned)
        end
        return false
    end

    local function onAuraBarSelect(entry)
        CS.HideAutocomplete()
        if entry and AddCustomBarFromSpell(
            entry.id,
            GetAuraBarAutocompleteEntryName(entry),
            GetCustomBarEntryTypeForAutocomplete(entry)
        ) then
            addBox._cdcCustomBarAutocompleteCommitted = true
            addBox:SetText("")
        end
    end

    addBox:SetCallback("OnTextChanged", function(widget, event, text)
        updatePlaceholder(text)
        ShowAuraBarAutocompleteResults(text, widget, onAuraBarSelect)
    end)
    addBox:SetCallback("OnEnterPressed", function(widget, event, text)
        if CS.ConsumeAutocompleteEnter then
            CS.ConsumeAutocompleteEnter()
        end
        if widget._cdcCustomBarAutocompleteCommitted then
            widget._cdcCustomBarAutocompleteCommitted = nil
            return
        end
        CS.HideAutocomplete()
        CommitCustomBarText(widget, text)
    end)
    CS.SetupAutocompleteKeyHandler(addBox)
    addBox.editbox:SetPoint("BOTTOMRIGHT", 1, 0)

    local actionControls = AceGUI:Create("SimpleGroup")
    actionControls:SetFullWidth(true)
    actionControls:SetHeight(59)
    actionControls.noAutoHeight = true
    actionControls:SetLayout("CDC_MANUAL")
    actionControls:AddChild(addBox)

    local importBtn = AceGUI:Create("Button")
    importBtn:SetText("Import")
    importBtn:SetCallback("OnClick", function()
        OpenImportReviewWindow()
    end)
    actionControls:AddChild(importBtn)

    local exportAllBtn = AceGUI:Create("Button")
    exportAllBtn:SetText("Export All")
    exportAllBtn:SetCallback("OnClick", function()
        local payload = RB.BuildCustomBarsExportPayload and RB.BuildCustomBarsExportPayload(settings, customBars)
        local exportString = payload and ST._EncodeExportData and ST._EncodeExportData(payload)
        if exportString then
            ShowPopupAboveConfig("CDC_EXPORT_CUSTOM_BARS", nil, { exportString = exportString })
        else
            CooldownCompanion:Print("Export failed: Custom Bar data was unavailable.")
        end
    end)
    actionControls:AddChild(exportAllBtn)
    local function PositionCustomBarActionControls(width)
        local host = actionControls.content or actionControls.frame
        width = width or host:GetWidth() or actionControls.frame:GetWidth() or 0
        if width <= 0 then return end
        addBox.frame:ClearAllPoints()
        addBox.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        addBox.frame:SetWidth(width)
        addBox.frame:SetHeight(28)
        local gap = 3
        local importWidth = math.floor((width - gap) / 2)
        local exportWidth = width - gap - importWidth
        importBtn.frame:ClearAllPoints()
        importBtn.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -31)
        importBtn.frame:SetWidth(importWidth)
        importBtn.frame:SetHeight(28)
        exportAllBtn.frame:ClearAllPoints()
        exportAllBtn.frame:SetPoint("LEFT", importBtn.frame, "RIGHT", gap, 0)
        exportAllBtn.frame:SetWidth(exportWidth)
        exportAllBtn.frame:SetHeight(28)
    end
    local originalActionControlsOnWidthSet = actionControls.OnWidthSet
    actionControls.OnWidthSet = function(self, width)
        if originalActionControlsOnWidthSet then
            originalActionControlsOnWidthSet(self, width)
        end
        PositionCustomBarActionControls(width)
    end
    container:AddChild(actionControls)
    PositionCustomBarActionControls()

    if #customBars == 0 then
        local empty = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(empty)
        empty:SetText("|cff888888No Custom Bars yet.|r")
        empty:SetFullWidth(true)
        container:AddChild(empty)
        return
    end

    local loadedBars = {}
    local inactiveBars = {}
    for index, entry in ipairs(customBars) do
        local target = (RB.CustomBarHasSpec and RB.CustomBarHasSpec(entry, customBarsSpecID)) and loadedBars or inactiveBars
        target[#target + 1] = { entry = entry, index = index }
    end

    local customBarRows = {
        { heading = "Loaded" },
    }
    if #loadedBars == 0 then
        customBarRows[#customBarRows + 1] = { empty = "No Custom Bars loaded for this spec." }
    else
        for _, row in ipairs(loadedBars) do
            customBarRows[#customBarRows + 1] = row
        end
    end
    customBarRows[#customBarRows + 1] = { heading = "Inactive Specs" }
    if #inactiveBars == 0 then
        customBarRows[#customBarRows + 1] = { empty = "No inactive-spec Custom Bars." }
    else
        for _, row in ipairs(inactiveBars) do
            row.inactive = true
            customBarRows[#customBarRows + 1] = row
        end
    end

    for index, item in ipairs(customBarRows) do
        if item.heading then
            local listHeading = AceGUI:Create("Heading")
            listHeading:SetText(item.heading)
            ColorHeading(listHeading)
            listHeading:SetFullWidth(true)
            container:AddChild(listHeading)
        elseif item.empty then
            local empty = AceGUI:Create("Label")
            ST._ConfigureWrappedHelperLabel(empty)
            empty:SetText("|cff888888" .. item.empty .. "|r")
            empty:SetFullWidth(true)
            container:AddChild(empty)
        else
        local entry = item.entry
        index = item.index or index
        local customBarId = EnsureCustomBarId(settings, entry)
        local spellName = entry.label
            or (entry.spellID and GetAuraBarAutocompleteDisplayName(entry.spellID))
            or (entry.spellID and C_Spell.GetSpellName(entry.spellID))
            or ("Custom Bar " .. tostring(index))
        local rowText = StripCustomBarEntryTypeWords(spellName)
        local typeIcons = GetCustomBarEntryTypeIcons(entry)
        if typeIcons and typeIcons ~= "" then
            rowText = (rowText or ("Custom Bar " .. tostring(index))) .. "  " .. typeIcons
        end
        local selected = customBarId == selectedId
        local icon = entry.spellID and (GetAuraBarAutocompleteDisplayIcon(entry.spellID) or C_Spell.GetSpellTexture(entry.spellID)) or 134400
        local isSpellCustomBar = IsSpellCustomBarConfig(entry)
        local resolvedRowAuraUnit = GetResolvedCustomAuraBarAuraUnit(entry, entry.spellID)
        local showAuraStatusBadge = (not item.inactive) and ((not isSpellCustomBar) or entry.auraTracking == true)
        local auraStatus = showAuraStatusBadge and ResolveCustomBarAuraTrackingStatus(entry, resolvedRowAuraUnit) or nil
        local rowRightPad = 4
        if entry.enabled == false then
            rowRightPad = rowRightPad + 20
        end
        if showAuraStatusBadge then
            rowRightPad = rowRightPad + 20
        end
        if RB.CustomBarHasSpecFilters and RB.CustomBarHasSpecFilters(entry) then
            for _, spec in ipairs(GetCustomBarSpecOptions()) do
                if spec.icon and RB.CustomBarHasExplicitSpec and RB.CustomBarHasExplicitSpec(entry, spec.id) then
                    rowRightPad = rowRightPad + 19
                end
            end
        end

        local row = AceGUI:Create("InteractiveLabel")
        if CleanRecycledEntry then CleanRecycledEntry(row) end
        HideCustomBarRowDecorations(row.frame)
        row:SetText(rowText)
        row:SetFullWidth(true)
        row:SetFontObject(GameFontHighlight)
        row:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        if row.frame and row.frame.RegisterForClicks then
            row.frame:RegisterForClicks("AnyUp")
        end
        if ApplyConfigRowIcon then
            ApplyConfigRowIcon(row, icon, { rightPad = rowRightPad })
        elseif icon then
            row:SetImage(icon, 0.08, 0.92, 0.08, 0.92)
            row:SetImageSize(18, 18)
        end
        if CS.selectedCustomBars[customBarId] then
            row:SetColor(0.4, 0.7, 1.0)
        elseif selected then
            row:SetColor(0.4, 0.7, 1.0)
        elseif item.inactive then
            row:SetColor(0.62, 0.62, 0.62)
        elseif entry.enabled ~= true then
            row:SetColor(0.55, 0.55, 0.55)
        end

        local rowFrame = row.frame
        local rightBadgeAnchor = rowFrame
        local rightBadgePoint = "RIGHT"
        local rightBadgeOffset = -4

        if entry.enabled == false then
            local disabledBadge = EnsureCustomBarRowIconBadge(rowFrame, "_cdcCustomBarDisabledBadge", "GM-icon-visibleDis-pressed")
            disabledBadge:SetPoint("RIGHT", rowFrame, "RIGHT", rightBadgeOffset, 0)
            SetCustomBarRowBadgeTooltip(disabledBadge, "Disabled", 0.6, 0.6, 0.6)
            rightBadgeAnchor = disabledBadge
            rightBadgePoint = "LEFT"
            rightBadgeOffset = -4
        end

        if showAuraStatusBadge then
            local auraStatusBadge = EnsureCustomBarRowIconBadge(rowFrame, "_cdcCustomBarAuraStatusBadge", "icon_trackedbuffs")
            auraStatusBadge:SetPoint("RIGHT", rightBadgeAnchor, rightBadgePoint, rightBadgeOffset, 0)
            if auraStatus.ready == true then
                auraStatusBadge.icon:SetVertexColor(1, 1, 1, 1)
                SetCustomBarRowBadgeTooltip(auraStatusBadge, "Aura tracking: Active", 0.2, 1, 0.2)
            else
                auraStatusBadge.icon:SetVertexColor(1, 0.2, 0.2, 1)
                local tooltipText = "Aura tracking: Inactive"
                if auraStatus.state == "cdmDisabled" then
                    tooltipText = "Aura tracking: Inactive (Blizzard CDM disabled)"
                elseif auraStatus.state == "trackedAuraUnavailable" then
                    tooltipText = "Aura tracking: Inactive (tracked in CDM, but the Buffs/Debuffs viewer is not currently readable)"
                elseif auraStatus.state == "associatedAuraNotTracked" then
                    tooltipText = "Aura tracking: Inactive (associated aura is not currently tracked in CDM)"
                elseif auraStatus.state == "noAssociatedAura" then
                    tooltipText = "Aura tracking: Inactive (no associated aura found)"
                end
                SetCustomBarRowBadgeTooltip(auraStatusBadge, tooltipText, 1, 0.2, 0.2)
            end
            rightBadgeAnchor = auraStatusBadge
            rightBadgePoint = "LEFT"
            rightBadgeOffset = -4
        end

        PlaceCustomBarSpecBadges(rowFrame, settings, entry, customBarsSpecID, rightBadgeAnchor, rightBadgePoint, rightBadgeOffset)

        row:SetCallback("OnClick", function() end)
        row.frame:SetScript("OnMouseUp", function(self, mouseButton)
            if mouseButton == "LeftButton" and IsShiftKeyDown and IsShiftKeyDown() then
                if CS.customBarSpecExpandedId == customBarId then
                    CS.customBarSpecExpandedId = nil
                else
                    CS.customBarSpecExpandedId = customBarId
                end
                CooldownCompanion:RefreshConfigPanel()
                return
            end
            if mouseButton == "RightButton" then
                local selectionChanged = SelectConfigCustomBar(customBarId, {
                    clearPreview = true,
                    clearButtonMulti = true,
                })
                if selectionChanged then
                    CooldownCompanion:RefreshConfigPanel()
                end
                OpenCustomBarRowMenu(customBars, customBarsSpecID, customBarId, entry)
            elseif mouseButton == "LeftButton" then
                if IsControlKeyDown and IsControlKeyDown() then
                    ToggleConfigCustomBarMultiSelect(customBarId)
                    CooldownCompanion:RefreshConfigPanel()
                    return
                end

                SelectConfigCustomBar(customBarId, {
                    clearPreview = true,
                    toggle = true,
                })
                CooldownCompanion:RefreshConfigPanel()
            end
        end)
        container:AddChild(row)
        if CS.customBarSpecExpandedId == customBarId then
            AddCustomBarSpecFilterControls(container, settings, entry, customBarsSpecID)
        end
        end
    end
end

local function BuildCustomBarIndicatorsTab(container, customBars, capturedIdx, cab, isSpellCustomBar, resolvedAuraUnit, capturedKey, infoButtons, previewsEnabled)
    local cabIdx = capturedIdx
    local cabApplyBars = function() CooldownCompanion:ApplyResourceBars() end
    local renderedControls = false
    previewsEnabled = previewsEnabled == true

    if not cab.spellID then
        local emptyLabel = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(emptyLabel)
        emptyLabel:SetText("|cff888888This Custom Bar has no indicator settings yet.|r")
        emptyLabel:SetFullWidth(true)
        container:AddChild(emptyLabel)
        return
    end

    local hasAuraDisplayControls = IsCustomBarAuraDisplayConfig(cab, isSpellCustomBar)
    local trackingMode = GetCustomBarTrackingModeConfig(cab, isSpellCustomBar)
    local isActiveTracking = hasAuraDisplayControls and trackingMode == "active"
    local hasActiveAuraIndicatorControls = isActiveTracking

    if hasActiveAuraIndicatorControls then
        renderedControls = true

        local indicatorsHeading = AceGUI:Create("Heading")
        indicatorsHeading:SetText("Active Aura")
        ColorHeading(indicatorsHeading)
        indicatorsHeading:SetFullWidth(true)
        container:AddChild(indicatorsHeading)

        local activeAuraEnabled = (cab.barAuraEffect or "none") ~= "none"

        local activeAuraCb = AceGUI:Create("CheckBox")
        activeAuraCb:SetLabel("Show Active Aura Indicator")
        activeAuraCb:SetValue(activeAuraEnabled)
        activeAuraCb:SetFullWidth(true)
        activeAuraCb:SetCallback("OnValueChanged", function(widget, event, val)
            if val then
                local effect = customBars[cabIdx].barAuraEffect
                if effect == nil or effect == "none" then
                    effect = "pixel"
                end
                customBars[cabIdx].barAuraEffect = effect
            else
                customBars[cabIdx].barAuraEffect = "none"
            end
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(activeAuraCb)

        local function BuildCustomBarActiveAuraAdvanced(panel)
            local activeAuraCombatCb = AceGUI:Create("CheckBox")
            activeAuraCombatCb:SetLabel("Show Only In Combat")
            activeAuraCombatCb:SetValue(cab.auraGlowCombatOnly or false)
            activeAuraCombatCb:SetFullWidth(true)
            activeAuraCombatCb:SetCallback("OnValueChanged", function(widget, event, val)
                customBars[cabIdx].auraGlowCombatOnly = val
                CooldownCompanion:ApplyResourceBars()
            end)
            panel:AddChild(activeAuraCombatCb)

            BuildBarActiveAuraControls(panel, customBars[cabIdx], cabApplyBars, {
                hidePrimaryColorPicker = not isSpellCustomBar,
            })
            BuildBarAuraPulseControls(panel, customBars[cabIdx], cabApplyBars)
        end

        local _, activeAuraAdvBtn = AddAdvancedToggle(activeAuraCb, "rbCabActiveAura_" .. capturedKey, infoButtons, activeAuraEnabled, {
            title = "Active Aura Indicator Advanced",
            build = BuildCustomBarActiveAuraAdvanced,
        })
        if previewsEnabled then
            AddPreviewBadge(activeAuraCb, activeAuraAdvBtn, "Preview Active Aura Effects", function()
                return CooldownCompanion:IsCustomAuraBarActivePreviewActive(customBars[cabIdx])
            end, function(show)
                CooldownCompanion:SetCustomAuraBarActivePreview(customBars[cabIdx], show)
            end, activeAuraEnabled)
        end
        if not activeAuraEnabled or not previewsEnabled then
            CooldownCompanion:SetCustomAuraBarActivePreview(customBars[cabIdx], false)
        end

        if resolvedAuraUnit == "target" then
            local pandemicEnabled = cab.showPandemicGlow == true

            local pandemicCb = AceGUI:Create("CheckBox")
            pandemicCb:SetLabel("Show Pandemic Indicator")
            pandemicCb:SetValue(pandemicEnabled)
            pandemicCb:SetFullWidth(true)
            pandemicCb:SetCallback("OnValueChanged", function(widget, event, val)
                customBars[cabIdx].showPandemicGlow = val and true or false
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:RefreshConfigPanel()
            end)
            container:AddChild(pandemicCb)

            local function BuildCustomBarPandemicAdvanced(panel)
                local pandemicCombatCb = AceGUI:Create("CheckBox")
                pandemicCombatCb:SetLabel("Show Only In Combat")
                pandemicCombatCb:SetValue(cab.pandemicGlowCombatOnly or false)
                pandemicCombatCb:SetFullWidth(true)
                pandemicCombatCb:SetCallback("OnValueChanged", function(widget, event, val)
                    customBars[cabIdx].pandemicGlowCombatOnly = val
                    CooldownCompanion:ApplyResourceBars()
                end)
                panel:AddChild(pandemicCombatCb)

                BuildPandemicBarControls(panel, customBars[cabIdx], cabApplyBars)
                BuildPandemicBarPulseControls(panel, customBars[cabIdx], cabApplyBars)
            end

            local _, pandemicAdvBtn = AddAdvancedToggle(pandemicCb, "rbCabPandemic_" .. capturedKey, infoButtons, pandemicEnabled, {
                title = "Pandemic Indicator Advanced",
                build = BuildCustomBarPandemicAdvanced,
            })
            if previewsEnabled then
                AddPreviewBadge(pandemicCb, pandemicAdvBtn, "Preview Pandemic Effects", function()
                    return CooldownCompanion:IsCustomAuraBarPandemicPreviewActive(customBars[cabIdx])
                end, function(show)
                    CooldownCompanion:SetCustomAuraBarPandemicPreview(customBars[cabIdx], show)
                end, pandemicEnabled)
            end
            if not pandemicEnabled or not previewsEnabled then
                CooldownCompanion:SetCustomAuraBarPandemicPreview(customBars[cabIdx], false)
            end
        else
            CooldownCompanion:SetCustomAuraBarPandemicPreview(customBars[cabIdx], false)
        end
    elseif not isSpellCustomBar and hasAuraDisplayControls then
        renderedControls = true

        local thresholdHeading = AceGUI:Create("Heading")
        thresholdHeading:SetText("Stack Threshold")
        ColorHeading(thresholdHeading)
        thresholdHeading:SetFullWidth(true)
        container:AddChild(thresholdHeading)

        local thresholdCb = AceGUI:Create("CheckBox")
        thresholdCb:SetLabel("Enable Max Stack Color")
        thresholdCb:SetValue(cab.thresholdColorEnabled == true)
        thresholdCb:SetFullWidth(true)
        thresholdCb:SetCallback("OnValueChanged", function(widget, event, val)
            customBars[cabIdx].thresholdColorEnabled = val or nil
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(thresholdCb)

        if cab.thresholdColorEnabled == true then
            AddColorPicker(container, customBars[cabIdx], "thresholdMaxColor", "Max Stack Color", DEFAULT_CUSTOM_AURA_MAX_COLOR, false,
                cabApplyBars, function() CooldownCompanion:RecolorCustomAuraBar(customBars[cabIdx]) end)
        end
    end

    if not isSpellCustomBar and hasAuraDisplayControls and not isActiveTracking then
        renderedControls = true

        local indicatorsHeading = AceGUI:Create("Heading")
        indicatorsHeading:SetText("Max Stack Indicator")
        ColorHeading(indicatorsHeading)
        indicatorsHeading:SetFullWidth(true)
        container:AddChild(indicatorsHeading)

        local glowCb = AceGUI:Create("CheckBox")
        glowCb:SetLabel("Max Stack Indicator")
        glowCb:SetValue(cab.maxStacksGlowEnabled == true)
        glowCb:SetFullWidth(true)
        glowCb:SetCallback("OnValueChanged", function(widget, event, val)
            customBars[cabIdx].maxStacksGlowEnabled = val or nil
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(glowCb)

        local function BuildMaxStackIndicatorAdvanced(panel)
            local isContinuousDisplay = (cab.trackingMode == "active") or (cab.displayMode == "continuous")
            local currentStyle = cab.maxStacksGlowStyle or "solidBorder"
            if currentStyle == "pulsingOverlay" and not isContinuousDisplay then
                currentStyle = "solidBorder"
                customBars[cabIdx].maxStacksGlowStyle = "solidBorder"
            end

            local styleList, styleOrder
            if isContinuousDisplay then
                styleList = {
                    solidBorder = "Solid Border",
                    pulsingBorder = "Pulsing Border",
                    pulsingOverlay = "Pulsing Overlay",
                }
                styleOrder = { "solidBorder", "pulsingBorder", "pulsingOverlay" }
            else
                styleList = {
                    solidBorder = "Solid Border",
                    pulsingBorder = "Pulsing Border",
                }
                styleOrder = { "solidBorder", "pulsingBorder" }
            end
            local styleDrop = AceGUI:Create("Dropdown")
            styleDrop:SetLabel("Indicator Style")
            styleDrop:SetList(styleList, styleOrder)
            styleDrop:SetValue(currentStyle)
            styleDrop:SetFullWidth(true)
            styleDrop:SetCallback("OnValueChanged", function(widget, event, val)
                customBars[cabIdx].maxStacksGlowStyle = val
                CooldownCompanion:ApplyResourceBars()
                if CS.RefreshAdvancedSettingsPanel then
                    CS.RefreshAdvancedSettingsPanel()
                end
            end)
            panel:AddChild(styleDrop)

            AddColorPicker(panel, customBars[cabIdx], "maxStacksGlowColor", "Indicator Color", {1, 0.84, 0, 0.9}, true,
                cabApplyBars, cabApplyBars)

            if currentStyle ~= "pulsingOverlay" then
                local sizeSlider = AceGUI:Create("Slider")
                sizeSlider:SetLabel("Border Size")
                sizeSlider:SetSliderValues(1, 8, 1)
                sizeSlider:SetValue(cab.maxStacksGlowSize or 2)
                sizeSlider:SetFullWidth(true)
                sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                    customBars[cabIdx].maxStacksGlowSize = val
                    CooldownCompanion:ApplyResourceBars()
                end)
                panel:AddChild(sizeSlider)
            end

            if currentStyle == "pulsingBorder" or currentStyle == "pulsingOverlay" then
                local speedSlider = AceGUI:Create("Slider")
                speedSlider:SetLabel("Pulse Duration")
                speedSlider:SetSliderValues(0.1, 2.0, 0.1)
                speedSlider:SetValue(cab.maxStacksGlowSpeed or 0.5)
                speedSlider:SetFullWidth(true)
                speedSlider:SetCallback("OnValueChanged", function(widget, event, val)
                    customBars[cabIdx].maxStacksGlowSpeed = val
                    CooldownCompanion:ApplyResourceBars()
                end)
                panel:AddChild(speedSlider)
            end
        end

        local _, glowAdvBtn = AddAdvancedToggle(glowCb, "rbCabMaxStacksIndicator_" .. capturedKey, infoButtons, cab.maxStacksGlowEnabled == true, {
            title = "Max Stack Indicator Advanced",
            build = BuildMaxStackIndicatorAdvanced,
        })
        local glowPreviewBtn
        if previewsEnabled then
            glowPreviewBtn = AddPreviewBadge(glowCb, glowAdvBtn, "Preview Indicator", function()
                return CS.customBarIndicatorPreviewActive == true and CooldownCompanion:IsResourceBarPreviewActive()
            end, function(show)
                CS.customBarIndicatorPreviewActive = show and true or nil
                if show then
                    CooldownCompanion:StartResourceBarPreview()
                else
                    CooldownCompanion:StopResourceBarPreview()
                end
            end, cab.maxStacksGlowEnabled == true)
        end
        if (not previewsEnabled or cab.maxStacksGlowEnabled ~= true) and CS.customBarIndicatorPreviewActive and CooldownCompanion:IsResourceBarPreviewActive() then
            CooldownCompanion:StopResourceBarPreview()
            CS.customBarIndicatorPreviewActive = nil
        end
        if not previewsEnabled then
            CS.customBarIndicatorPreviewActive = nil
        end

        CreateInfoButton(glowCb.frame, glowPreviewBtn or glowAdvBtn, "LEFT", "RIGHT", 4, 0, {
            "Max Stack Indicator",
            {"Due to combat restrictions, individual bar segments cannot be highlighted independently.", 1, 1, 1, true},
            " ",
            {"The indicator covers the entire resource bar and appears automatically when your buff reaches its maximum stack count.", 1, 1, 1, true},
            " ",
            {"The Pulsing Overlay style is only available for continuous display mode.", 1, 1, 1, true},
        }, glowCb)

    end

    if not renderedControls then
        local emptyLabel = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(emptyLabel)
        emptyLabel:SetText("|cff888888This Custom Bar has no indicator settings yet.|r")
        emptyLabel:SetFullWidth(true)
        container:AddChild(emptyLabel)
    end
end

local function BuildCustomAuraBarPanel(container, customBarId, activeTab)
    local settings = CooldownCompanion:GetResourceBarSettings()
    if not (settings and settings.enabled) then
        AddResourceBarsDisabledLabel(container, "Enable Resource Bars to configure Custom Bar settings.")
        return
    end

    local customBars = RB.GetAllCustomBars and RB.GetAllCustomBars(settings) or CooldownCompanion:GetSpecCustomAuraBars()
    local rbCabTextAdvBtns = {}
    local selectedIndex = FindCustomBarIndexById(customBars, customBarId)
    local infoButtons = CS.customBarInfoButtons
    if not infoButtons then
        infoButtons = {}
        CS.customBarInfoButtons = infoButtons
    end

    if not selectedIndex then
        local label = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(label)
        label:SetText("Select a Custom Bar to configure it.")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end
    local cab = customBars[selectedIndex]
    local capturedIdx = selectedIndex
    local capturedId = EnsureCustomBarId(settings, cab)
    local capturedKey = capturedId or tostring(capturedIdx)
    local currentConfigSpecID = GetCurrentConfigSpecID()
    local customBarLoadedForCurrentSpec = not RB.CustomBarHasSpec or RB.CustomBarHasSpec(cab, currentConfigSpecID)
    local function resolveLayoutSpecID(entry, fallbackSpecID)
        fallbackSpecID = tonumber(fallbackSpecID) or fallbackSpecID
        if RB.CustomBarHasSpec and fallbackSpecID and RB.CustomBarHasSpec(entry, fallbackSpecID) then
            return fallbackSpecID
        end
        if RB.CustomBarHasExplicitSpec then
            for _, spec in ipairs(GetCustomBarSpecOptions()) do
                if RB.CustomBarHasExplicitSpec(entry, spec.id) then
                    return spec.id
                end
            end
        end

        local entryCustomBarId = type(entry) == "table" and entry.customBarId or nil
        local layoutOrder = type(settings) == "table" and settings.layoutOrder or nil
        if type(entryCustomBarId) == "string" and type(layoutOrder) == "table" then
            local layoutSpecIDs = {}
            for specID, specLayout in pairs(layoutOrder) do
                if type(specLayout) == "table"
                    and type(specLayout.customBars) == "table"
                    and type(specLayout.customBars[entryCustomBarId]) == "table" then
                    layoutSpecIDs[#layoutSpecIDs + 1] = tonumber(specID) or specID
                end
            end
            table.sort(layoutSpecIDs, function(a, b) return tostring(a) < tostring(b) end)
            if layoutSpecIDs[1] then
                return layoutSpecIDs[1]
            end
        end

        return fallbackSpecID
    end

    local layoutSpecID = resolveLayoutSpecID(cab, currentConfigSpecID)
    local layout = RB.GetSpecLayoutOrder and RB.GetSpecLayoutOrder(settings, layoutSpecID) or CooldownCompanion:GetSpecLayoutOrder()
    local thicknessField, thicknessLabel = GetResourceThicknessFieldConfig(settings, layout)
    local isSpellCustomBar = IsSpellCustomBarConfig(cab)
    local hasAuraDisplayControls = IsCustomBarAuraDisplayConfig(cab, isSpellCustomBar)
    local trackingMode = GetCustomBarTrackingModeConfig(cab, isSpellCustomBar)
    local isStackDisplay = hasAuraDisplayControls and trackingMode ~= "active"
    local resolvedAuraUnit = GetResolvedCustomAuraBarAuraUnit(cab, cab.spellID)
    activeTab = activeTab or "appearance"

    if activeTab == "settings" or activeTab == "layout" or activeTab == "anchor" or activeTab == "alpha" then
        activeTab = "appearance"
    end

    if activeTab == "soundalerts" then
        ST._BuildCustomBarSoundAlertsTab(container, cab, infoButtons)
        return
    end

    if activeTab == "loadconditions" then
        ST._BuildCustomBarLoadConditionsTab(container, cab, infoButtons)
        return
    end

    if activeTab == "indicators" then
        BuildCustomBarIndicatorsTab(container, customBars, capturedIdx, cab, isSpellCustomBar, resolvedAuraUnit, capturedKey, infoButtons, customBarLoadedForCurrentSpec)
        return
    end

    BuildCustomBarAuraTrackingSection(container, cab, resolvedAuraUnit, infoButtons)

    if hasAuraDisplayControls then
        AddCustomBarSettingsHeading(container, "Aura Display Mode", infoButtons, {
            "Determines how the tracked aura is displayed on this Custom Bar.",
            " ",
            "Active: shows the aura's remaining duration while it is active.",
            " ",
            "Stack Count: ignores duration and shows only the aura's current stack count.",
        })
    end

            -- Aura Display Mode dropdown
            if hasAuraDisplayControls then
            local trackDrop = AceGUI:Create("Dropdown")
            trackDrop:SetList({
                active = "Active",
                stacks = "Stack Count",
            }, { "active", "stacks" })
            trackDrop:SetValue(trackingMode)
            trackDrop:SetFullWidth(true)
            trackDrop:SetCallback("OnValueChanged", function(widget, event, val)
                customBars[capturedIdx].trackingMode = val
                if val ~= "active" then
                    CooldownCompanion:SetCustomAuraBarActivePreview(customBars[capturedIdx], false)
                    CooldownCompanion:SetCustomAuraBarPandemicPreview(customBars[capturedIdx], false)
                end
                ApplyCustomAuraBarPanelChanges({
                    updateAnchors = true,
                    refreshConfig = true,
                })
            end)
            container:AddChild(trackDrop)
            end

            -- Max Stacks slider (hidden in "active" tracking mode)
            if isStackDisplay then
            local maxSlider = AceGUI:Create("Slider")
            maxSlider:SetLabel("Max Stacks")
            maxSlider:SetSliderValues(1, 99, 1)
            maxSlider:SetValue(cab.maxStacks or 1)
            maxSlider:SetFullWidth(true)
            local pendingMaxStacks = cab.maxStacks or 1
            maxSlider:SetCallback("OnValueChanged", function(widget, event, val)
                pendingMaxStacks = math.max(1, math.min(99, math.floor((tonumber(val) or 1) + 0.5)))
            end)
            maxSlider:SetCallback("OnMouseUp", function(widget, event, val)
                local committedValue = math.max(1, math.min(99, math.floor((tonumber(val) or pendingMaxStacks or 1) + 0.5)))
                if customBars[capturedIdx].maxStacks == committedValue then
                    return
                end
                customBars[capturedIdx].maxStacks = committedValue
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:UpdateAnchorStacking()
            end)
            container:AddChild(maxSlider)
            end

            -- Display Mode dropdown (hidden in "active" tracking mode)
            if isStackDisplay then
            local modeDrop = AceGUI:Create("Dropdown")
            modeDrop:SetLabel("Display Mode")
            modeDrop:SetList({
                continuous = "Continuous",
                segmented = "Segmented",
                overlay = "Overlay",
            }, { "continuous", "segmented", "overlay" })
            modeDrop:SetValue(cab.displayMode or "segmented")
            modeDrop:SetFullWidth(true)
            modeDrop:SetCallback("OnValueChanged", function(widget, event, val)
                customBars[capturedIdx].displayMode = val
                ApplyCustomAuraBarPanelChanges({
                    updateAnchors = true,
                    refreshConfig = true,
                })
            end)
            container:AddChild(modeDrop)
            end

            -- Per-slot bar thickness override
            if layout and layout.customBarHeights then
                AddCustomBarSettingsHeading(container, "Size")

                local slotLayout = EnsureCustomBarLayout(settings, layoutSpecID, capturedId, 1000 + capturedIdx) or {}
                local cabHeightSlider = AceGUI:Create("Slider")
                cabHeightSlider:SetLabel(thicknessLabel)
                cabHeightSlider:SetSliderValues(4, 40, 0.1)
                if thicknessField == "barWidth" then
                    cabHeightSlider:SetValue(slotLayout.barWidth or slotLayout.barHeight or layout.barWidth or layout.barHeight or settings.barWidth or settings.barHeight or 12)
                else
                    cabHeightSlider:SetValue(slotLayout.barHeight or slotLayout.barWidth or layout.barHeight or layout.barWidth or settings.barHeight or settings.barWidth or 12)
                end
                cabHeightSlider:SetFullWidth(true)
                local cabIdx = capturedIdx
                cabHeightSlider:SetCallback("OnValueChanged", function(widget, event, val)
                    local customBar = customBars[cabIdx]
                    local customLayout = EnsureCustomBarLayout(settings, layoutSpecID, customBar and customBar.customBarId, 1000 + cabIdx)
                    if customLayout then
                        customLayout[thicknessField] = val
                    end
                    CooldownCompanion:ApplyResourceBars()
                    CooldownCompanion:RepositionCastBar()
                    CooldownCompanion:UpdateAnchorStacking()
                end)
                container:AddChild(cabHeightSlider)
            end

            -- ---- Colors section (only when has spell ID) ----
            if cab.spellID then
                local colorHeading = AceGUI:Create("Heading")
                colorHeading:SetText("Colors")
                ColorHeading(colorHeading)
                colorHeading:SetFullWidth(true)
                container:AddChild(colorHeading)

                -- Bar Color (all modes)
                local cabIdx = capturedIdx
                local cabApplyBars = function() CooldownCompanion:ApplyResourceBars() end
                AddColorPicker(container, customBars[cabIdx], "barColor", "Bar Color", {0.5, 0.5, 1}, false,
                    cabApplyBars, function() CooldownCompanion:RecolorCustomAuraBar(customBars[cabIdx]) end)

                if isSpellCustomBar and not isStackDisplay then
                    AddColorPicker(container, customBars[cabIdx], "barCooldownColor", "Bar Cooldown Color", {0.6, 0.13, 0.18, 1}, true,
                        cabApplyBars, cabApplyBars)
                    AddColorPicker(container, customBars[cabIdx], "barChargeColor", "Bar Recharging Color", {1.0, 0.82, 0.0, 1}, true,
                        cabApplyBars, cabApplyBars)
                end

                -- Overlay Color (overlay mode only)
                if cab.displayMode == "overlay" and isStackDisplay then
                    local cpOverlay = AddColorPicker(container, customBars[cabIdx], "overlayColor", "Overlay Color", {1, 0.84, 0}, false,
                        cabApplyBars, function() CooldownCompanion:RecolorCustomAuraBar(customBars[cabIdx]) end)

                    cpOverlay:SetCallback("OnEnter", function(widget)
                        GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
                        GameTooltip:AddLine("Overlay Color")
                        GameTooltip:AddLine("Number of bar segments equals half the max stacks. Overlay color activates once base segments are full.", 1, 1, 1, true)
                        GameTooltip:Show()
                    end)
                    cpOverlay:SetCallback("OnLeave", function()
                        GameTooltip:Hide()
                    end)
                end

                -- ---- Text / Duration controls ----
                local isActive = not isStackDisplay
                local isContinuous = isActive or (cab.displayMode == "continuous")

                if isContinuous then
                    local textsHeading = AceGUI:Create("Heading")
                    textsHeading:SetText("Texts")
                    ColorHeading(textsHeading)
                    textsHeading:SetFullWidth(true)
                    container:AddChild(textsHeading)

                    local showDurationControls = not (isSpellCustomBar and isStackDisplay)
                    local durationTextCb
                    if showDurationControls then
                        durationTextCb = AceGUI:Create("CheckBox")
                        durationTextCb:SetLabel("Show Duration Text")
                        durationTextCb:SetValue(cab.showDurationText == true)
                        durationTextCb:SetFullWidth(true)
                        durationTextCb:SetCallback("OnValueChanged", function(widget, event, val)
                            customBars[cabIdx].showDurationText = val or nil
                            CooldownCompanion:ApplyResourceBars()
                            CooldownCompanion:RefreshConfigPanel()
                        end)
                        container:AddChild(durationTextCb)
                    end

                    -- Show Stack Text
                    local stackVal = cab.showStackText
                    if stackVal == nil and not isActive then
                        stackVal = cab.showText  -- backwards compat
                    end

                    local stackTextCb = AceGUI:Create("CheckBox")
                    local stackTextLabel = "Show Stack Text"
                    if isSpellCustomBar then
                        stackTextLabel = isStackDisplay and "Show Aura Stack Text" or "Show Count Text (Charges/Uses)"
                    end
                    stackTextCb:SetLabel(stackTextLabel)
                    stackTextCb:SetValue(stackVal == true)
                    stackTextCb:SetFullWidth(true)
                    stackTextCb:SetCallback("OnValueChanged", function(widget, event, val)
                        customBars[cabIdx].showStackText = val or nil
                        CooldownCompanion:ApplyResourceBars()
                        CooldownCompanion:RefreshConfigPanel()
                    end)
                    container:AddChild(stackTextCb)

                    local showDuration = showDurationControls and cab.showDurationText == true
                    local showStack = (stackVal == true)
                    local function BuildDurationTextAdvanced(panel)
                        local fontDrop = AceGUI:Create("Dropdown")
                        fontDrop:SetLabel("Duration Font")
                        CS.SetupFontDropdown(fontDrop)
                        fontDrop:SetValue(cab.durationTextFont or DEFAULT_RESOURCE_TEXT_FONT)
                        fontDrop:SetFullWidth(true)
                        fontDrop:SetCallback("OnValueChanged", function(widget, event, val)
                            customBars[cabIdx].durationTextFont = val
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        panel:AddChild(fontDrop)

                        local sizeDrop = AceGUI:Create("Slider")
                        sizeDrop:SetLabel("Duration Font Size")
                        sizeDrop:SetSliderValues(6, 24, 1)
                        sizeDrop:SetValue(cab.durationTextFontSize or DEFAULT_RESOURCE_TEXT_SIZE)
                        sizeDrop:SetFullWidth(true)
                        sizeDrop:SetCallback("OnValueChanged", function(widget, event, val)
                            customBars[cabIdx].durationTextFontSize = val
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        panel:AddChild(sizeDrop)

                        local outlineDrop = AceGUI:Create("Dropdown")
                        outlineDrop:SetLabel("Duration Outline")
                        outlineDrop:SetList(CS.outlineOptions)
                        outlineDrop:SetValue(cab.durationTextFontOutline or DEFAULT_RESOURCE_TEXT_OUTLINE)
                        outlineDrop:SetFullWidth(true)
                        outlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
                            customBars[cabIdx].durationTextFontOutline = val
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        panel:AddChild(outlineDrop)

                        AddColorPicker(panel, customBars[cabIdx], "durationTextFontColor", "Duration Text Color", DEFAULT_RESOURCE_TEXT_COLOR, true, cabApplyBars)

                        AddDurationFormatDropdown(panel, customBars[cabIdx], cabApplyBars)
                    end

                    local durationAdvExpanded = showDurationControls
                        and AddAdvancedToggle(durationTextCb, "rbCabDurationText_" .. capturedKey, rbCabTextAdvBtns, showDuration, {
                            title = "Duration Text Advanced",
                            build = BuildDurationTextAdvanced,
                        })

                    local function BuildStackTextAdvanced(panel)
                        if not isActive then
                            local stackTextFormatDrop = AceGUI:Create("Dropdown")
                            stackTextFormatDrop:SetLabel("Text Format")
                            local stackTextFormatOptions = {
                                current = "Current Value",
                                current_max = "Current / Max",
                            }
                            local stackTextFormatOrder = { "current", "current_max" }
                            stackTextFormatDrop:SetList(stackTextFormatOptions, stackTextFormatOrder)
                            local stackTextFormatValue = cab.stackTextFormat or DEFAULT_CUSTOM_AURA_STACK_TEXT_FORMAT
                            if stackTextFormatValue ~= "current" and stackTextFormatValue ~= "current_max" then
                                stackTextFormatValue = DEFAULT_CUSTOM_AURA_STACK_TEXT_FORMAT
                            end
                            stackTextFormatDrop:SetValue(stackTextFormatValue)
                            stackTextFormatDrop:SetFullWidth(true)
                            stackTextFormatDrop:SetCallback("OnValueChanged", function(widget, event, val)
                                if val == "current" or val == "current_max" then
                                    customBars[cabIdx].stackTextFormat = val
                                else
                                    customBars[cabIdx].stackTextFormat = DEFAULT_CUSTOM_AURA_STACK_TEXT_FORMAT
                                end
                                CooldownCompanion:ApplyResourceBars()
                            end)
                            panel:AddChild(stackTextFormatDrop)
                        end

                        local fontDrop = AceGUI:Create("Dropdown")
                        local stackFontLabel = isSpellCustomBar and (isStackDisplay and "Aura Stack Font" or "Charge Font") or "Stack Font"
                        fontDrop:SetLabel(stackFontLabel)
                        CS.SetupFontDropdown(fontDrop)
                        fontDrop:SetValue(cab.stackTextFont or DEFAULT_RESOURCE_TEXT_FONT)
                        fontDrop:SetFullWidth(true)
                        fontDrop:SetCallback("OnValueChanged", function(widget, event, val)
                            customBars[cabIdx].stackTextFont = val
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        panel:AddChild(fontDrop)

                        local sizeDrop = AceGUI:Create("Slider")
                        local stackSizeLabel = isSpellCustomBar and (isStackDisplay and "Aura Stack Font Size" or "Charge Font Size") or "Stack Font Size"
                        sizeDrop:SetLabel(stackSizeLabel)
                        sizeDrop:SetSliderValues(6, 24, 1)
                        sizeDrop:SetValue(cab.stackTextFontSize or DEFAULT_RESOURCE_TEXT_SIZE)
                        sizeDrop:SetFullWidth(true)
                        sizeDrop:SetCallback("OnValueChanged", function(widget, event, val)
                            customBars[cabIdx].stackTextFontSize = val
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        panel:AddChild(sizeDrop)

                        local outlineDrop = AceGUI:Create("Dropdown")
                        local stackOutlineLabel = isSpellCustomBar and (isStackDisplay and "Aura Stack Outline" or "Charge Outline") or "Stack Outline"
                        outlineDrop:SetLabel(stackOutlineLabel)
                        outlineDrop:SetList(CS.outlineOptions)
                        outlineDrop:SetValue(cab.stackTextFontOutline or DEFAULT_RESOURCE_TEXT_OUTLINE)
                        outlineDrop:SetFullWidth(true)
                        outlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
                            customBars[cabIdx].stackTextFontOutline = val
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        panel:AddChild(outlineDrop)

                        AddColorPicker(panel, customBars[cabIdx], "stackTextFontColor", "Stack Text Color", DEFAULT_RESOURCE_TEXT_COLOR, true, cabApplyBars)
                    end

                    local stackAdvExpanded = AddAdvancedToggle(stackTextCb, "rbCabStackText_" .. capturedKey, rbCabTextAdvBtns, showStack, {
                        title = stackTextLabel .. " Advanced",
                        build = BuildStackTextAdvanced,
                    })
                end

                if not isSpellCustomBar or cab.auraTracking == true then
                    BuildCustomBarVisibilityRulesSection(container, customBars, capturedIdx, cab, resolvedAuraUnit, capturedKey, infoButtons)
                end

                -- ---- Talent Conditions section ----
                local talentHeading = AceGUI:Create("Heading")
                talentHeading:SetText("Talent Conditions")
                ColorHeading(talentHeading)
                talentHeading:SetFullWidth(true)
                container:AddChild(talentHeading)

                local talentKey = "cab_talent_" .. capturedKey
                local talentCollapsed = resourceBarCollapsedSections[talentKey]

                local talentCollapseBtn = AttachCollapseButton(talentHeading, talentCollapsed, function()
                    resourceBarCollapsedSections[talentKey] = not resourceBarCollapsedSections[talentKey]
                    CooldownCompanion:RefreshConfigPanel()
                end)

                local talentInfoBtn = CreateInfoButton(talentHeading.frame, talentCollapseBtn, "LEFT", "RIGHT", 2, 0, {
                    "Talent Conditions",
                    {"Show or hide this Custom Bar based on which talents you have selected. If you add multiple conditions, all of them must pass.", 1, 1, 1, true},
                }, infoButtons)
                talentHeading.right:ClearAllPoints()
                talentHeading.right:SetPoint("RIGHT", talentHeading.frame, "RIGHT", -3, 0)
                talentHeading.right:SetPoint("LEFT", talentInfoBtn, "RIGHT", 4, 0)

                local conditions = cab.talentConditions
                local condCount = conditions and #conditions or 0

                if talentCollapsed then
                    local summaryLabel = AceGUI:Create("Label")
                    ST._ConfigureWrappedHelperLabel(summaryLabel)
                    if condCount > 0 then
                        local firstCond = conditions[1]
                        local displayIcon = not IsHeroSpecProxyCondition(firstCond)
                            and firstCond.spellID
                            and C_Spell.GetSpellTexture(firstCond.spellID)
                        if displayIcon then
                            summaryLabel:SetImage(displayIcon, 0.08, 0.92, 0.08, 0.92)
                            summaryLabel:SetImageSize(16, 16)
                        end
                        if condCount == 1 then
                            local showText = (firstCond.show == "not_taken") and " (not taken)" or " (taken)"
                            summaryLabel:SetText(ST._GetConditionDisplayName(firstCond) .. showText)
                        else
                            summaryLabel:SetText(condCount .. " conditions" .. ST._GetConditionListContextSuffix(conditions))
                        end
                    else
                        summaryLabel:SetText("|cff888888None|r")
                    end
                    summaryLabel:SetFullWidth(true)
                    container:AddChild(summaryLabel)
                end

                if not talentCollapsed then

                -- Condition list display
                if condCount > 0 then
                    local cache = CooldownCompanion._talentNodeCache
                    local currentSpecID = layoutSpecID or CooldownCompanion._currentSpecId
                    local currentHeroSubTreeID = CooldownCompanion._currentHeroSpecId
                    for _, cond in ipairs(conditions) do
                        local condLabel = AceGUI:Create("Label")
                        ST._ConfigureWrappedHelperLabel(condLabel)
                        local displayIcon = not IsHeroSpecProxyCondition(cond)
                            and cond.spellID
                            and C_Spell.GetSpellTexture(cond.spellID)
                        if displayIcon then
                            condLabel:SetImage(displayIcon, 0.08, 0.92, 0.08, 0.92)
                            condLabel:SetImageSize(16, 16)
                        end
                        local nameText = ST._GetConditionDisplayName(cond)
                        local showText
                        if cond.show == "not_taken" then
                            showText = " |cffff4d4d(not taken)|r"
                        else
                            showText = " |cff33dd33(taken)|r"
                        end
                        condLabel:SetText("|cffFFFFFF" .. nameText .. "|r" .. showText)
                        condLabel:SetFullWidth(true)
                        container:AddChild(condLabel)

                        -- Per-condition stale node warning
                        local matchesCurrentScope = (not cond.specID or cond.specID == currentSpecID)
                            and (not cond.heroSubTreeID or cond.heroSubTreeID == currentHeroSubTreeID)
                        if matchesCurrentScope and cache and not cache[cond.nodeID] then
                            local warnLabel = AceGUI:Create("Label")
                            ST._ConfigureWrappedHelperLabel(warnLabel)
                            warnLabel:SetText("|cffff8800  This talent is not in your current active tree, so it behaves as not taken right now.|r")
                            warnLabel:SetFullWidth(true)
                            container:AddChild(warnLabel)
                        end
                    end
                else
                    local emptyLabel = AceGUI:Create("Label")
                    ST._ConfigureWrappedHelperLabel(emptyLabel)
                    emptyLabel:SetText("|cff888888No talent conditions set.|r")
                    emptyLabel:SetFullWidth(true)
                    container:AddChild(emptyLabel)
                end

                -- Button row: side-by-side Pick + Clear using Flow layout
                local talentBtnRow = AceGUI:Create("SimpleGroup")
                talentBtnRow:SetFullWidth(true)
                talentBtnRow:SetLayout("Flow")

                local pickBtn = AceGUI:Create("Button")
                pickBtn:SetText(condCount > 0 and "Edit" or "Pick Talents")
                pickBtn:SetRelativeWidth(condCount > 0 and 0.5 or 1)
                pickBtn:SetCallback("OnClick", function()
                    local initialConditions = cab.talentConditions
                    local specID = layoutSpecID or CooldownCompanion._currentSpecId
                    local specHint = specID and { specs = { [specID] = true } } or nil
                    CooldownCompanion:OpenTalentPicker(function(results)
                        if results then
                            local normalized, changed = CooldownCompanion:NormalizeTalentConditions(results)
                            if changed then
                                results = normalized
                            end
                            customBars[cabIdx].talentConditions = results
                        else
                            customBars[cabIdx].talentConditions = nil
                        end
                        CooldownCompanion:ApplyResourceBars()
                        CooldownCompanion:UpdateAnchorStacking()
                        CooldownCompanion:RefreshConfigPanel()
                    end, initialConditions, specHint)
                end)
                talentBtnRow:AddChild(pickBtn)

                -- Clear button (only when conditions exist)
                if condCount > 0 then
                    local clearBtn = AceGUI:Create("Button")
                    clearBtn:SetText("Clear")
                    clearBtn:SetRelativeWidth(0.5)
                    clearBtn:SetCallback("OnClick", function()
                        customBars[cabIdx].talentConditions = nil
                        CooldownCompanion:ApplyResourceBars()
                        CooldownCompanion:UpdateAnchorStacking()
                        CooldownCompanion:RefreshConfigPanel()
                    end)
                    talentBtnRow:AddChild(clearBtn)
                end

                container:AddChild(talentBtnRow)

                end -- not talentCollapsed
            end

end

-- Expose for ButtonSettings.lua and Config.lua
ST._BuildCustomBarsListPanel = BuildCustomBarsListPanel
ST._BuildCustomAuraBarPanel = BuildCustomAuraBarPanel
ST._BuildCustomBarSoundAlertsTab = BuildCustomBarSoundAlertsTab
ST._BuildCustomBarLoadConditionsTab = BuildCustomBarLoadConditionsTab
