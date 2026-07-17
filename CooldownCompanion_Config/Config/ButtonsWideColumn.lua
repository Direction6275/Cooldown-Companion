--[[
    CooldownCompanion - Config/ButtonsWideColumn
    Wide column 3 for the plain buttons view: hosts the entry settings
    surfaces (bsTabGroup, entry multi-select), the panel batch actions, and
    the group-side settings surfaces (via GroupSettingsHost) in one column
    spanning the col3+col4 region. Column 4 is hidden while this is active.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState
local AceGUI = LibStub("AceGUI-3.0")

local PREVIEW_GAP = 4

local function HideEntrySurfaces(col3)
    if col3.bsTabGroup then col3.bsTabGroup.frame:Hide() end
    if col3.bsPlaceholder then col3.bsPlaceholder:Hide() end
    if col3.multiSelectScroll then col3.multiSelectScroll.frame:Hide() end
end

-- Settings surfaces anchor beneath the pinned preview when it is shown,
-- and fill the whole column otherwise (same pattern as the Resources home).
local function AnchorButtonsContentFrame(col3, frame)
    frame:ClearAllPoints()
    local previewHost = col3.buttonsPreviewHost
    if previewHost and previewHost:IsShown() then
        frame:SetPoint("TOPLEFT", previewHost, "BOTTOMLEFT", 0, -PREVIEW_GAP)
        frame:SetPoint("BOTTOMRIGHT", col3.content, "BOTTOMRIGHT", 0, 0)
    else
        frame:SetPoint("TOPLEFT", col3.content, "TOPLEFT", 0, 0)
        frame:SetPoint("BOTTOMRIGHT", col3.content, "BOTTOMRIGHT", 0, 0)
    end
end

local function HidePanelPreview(col3)
    local host = col3.buttonsPreviewHost
    if host then
        host:Hide()
        if ST._ReleaseButtonPanelPreview then
            ST._ReleaseButtonPanelPreview(host)
        end
    end
end

-- Pinned preview of the selected panel at the top of the wide column.
local function UpdatePanelPreview(col3)
    if not CS.selectedGroup then
        HidePanelPreview(col3)
        return
    end

    local host = col3.buttonsPreviewHost
    if not host then
        host = CreateFrame("Frame", nil, col3.content)
        host:SetClipsChildren(false)
        col3.buttonsPreviewHost = host
    end
    host:ClearAllPoints()
    host:SetPoint("TOPLEFT", col3.content, "TOPLEFT", 0, 0)
    host:SetPoint("TOPRIGHT", col3.content, "TOPRIGHT", 0, 0)
    local columnHeight = col3.content:GetHeight() or 0
    host:SetHeight(math.max(150, math.floor(columnHeight * 0.35)))
    host:Show()
    ST._BuildButtonPanelPreview(host, CS.selectedGroup)
end

-- True when the column should show entry settings instead of the
-- group-side surfaces: a valid single entry (including the rotation
-- assistant's virtual entry) or an entry multi-select.
local function IsEntrySelectionActive()
    local group = CS.selectedGroup and CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then
        return false
    end
    local multiCount = 0
    for _ in pairs(CS.selectedButtons) do multiCount = multiCount + 1 end
    if multiCount >= 2 then
        return true
    end
    if CS.selectedRotationAssistantEntry == true
        and CooldownCompanion:IsRotationAssistantGroup(group) then
        return true
    end
    return CS.selectedButton ~= nil and group.buttons[CS.selectedButton] ~= nil
end

local function RefreshButtonsWideColumn()
    local col3 = CS.configFrame and CS.configFrame.col3
    if not col3 then return end

    -- Hide surfaces owned by the resources/cast homes that share col3
    if col3._customAuraTabGroup then col3._customAuraTabGroup.frame:Hide() end
    col3._customAuraSubScroll = nil
    if col3._customAuraScroll then col3._customAuraScroll.frame:Hide() end
    if col3._customBarsScroll then col3._customBarsScroll.frame:Hide() end
    if col3._resourcesIntroPane then col3._resourcesIntroPane:Hide() end
    if col3._unitFramesScroll then col3._unitFramesScroll.frame:Hide() end
    if col3._unitFramesIntroPane then col3._unitFramesIntroPane:Hide() end

    -- Panel multi-select: batch operations replace everything else
    local panelMultiCount = 0
    local multiPanelIds = {}
    for pid in pairs(CS.selectedPanels) do
        panelMultiCount = panelMultiCount + 1
        multiPanelIds[#multiPanelIds + 1] = pid
    end
    if panelMultiCount >= 2 and CS.selectedContainer then
        HideEntrySurfaces(col3)
        HidePanelPreview(col3)
        if col3.groupSettingsHost then col3.groupSettingsHost:Hide() end

        if not col3._panelMultiSelectScroll then
            local scroll = AceGUI:Create("ScrollFrame")
            scroll:SetLayout("List")
            scroll.frame:SetParent(col3.content)
            scroll.frame:ClearAllPoints()
            scroll.frame:SetPoint("TOPLEFT", col3.content, "TOPLEFT", 0, 0)
            scroll.frame:SetPoint("BOTTOMRIGHT", col3.content, "BOTTOMRIGHT", 0, 0)
            col3._panelMultiSelectScroll = scroll
        end
        col3._panelMultiSelectScroll:ReleaseChildren()
        col3._panelMultiSelectScroll.frame:Show()
        ST._RefreshPanelMultiSelect(col3._panelMultiSelectScroll, panelMultiCount, multiPanelIds)
        return
    end
    if col3._panelMultiSelectScroll then
        col3._panelMultiSelectScroll.frame:Hide()
    end

    -- Entry selected: the entry settings surfaces own the settings area
    if IsEntrySelectionActive() then
        if col3.groupSettingsHost then col3.groupSettingsHost:Hide() end
        UpdatePanelPreview(col3)
        if col3.bsTabGroup then
            AnchorButtonsContentFrame(col3, col3.bsTabGroup.frame)
        end
        if col3.multiSelectScroll then
            AnchorButtonsContentFrame(col3, col3.multiSelectScroll.frame)
        end
        ST._RefreshButtonSettingsColumn()
        -- The multi-select scroll may have been created just now with fill
        -- anchors; re-anchor it below the preview.
        if col3.multiSelectScroll then
            AnchorButtonsContentFrame(col3, col3.multiSelectScroll.frame)
        end
        return
    end

    -- Otherwise the group-side surfaces (panel, container, folder settings,
    -- placeholders) own the settings area
    HideEntrySurfaces(col3)
    UpdatePanelPreview(col3)

    local host = col3.groupSettingsHost
    if not host then
        host = CreateFrame("Frame", nil, col3.content)
        col3.groupSettingsHost = host
    end
    AnchorButtonsContentFrame(col3, host)
    host:Show()
    ST._RefreshGroupSettingsHost(host)
end

ST._RefreshButtonsWideColumn = RefreshButtonsWideColumn
ST._AnchorButtonsContentFrame = AnchorButtonsContentFrame
