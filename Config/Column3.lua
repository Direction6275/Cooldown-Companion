--[[
    CooldownCompanion - Config/Column3
    RefreshColumn3 (button settings / custom aura bars column).
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState
local AceGUI = LibStub("AceGUI-3.0")

------------------------------------------------------------------------
-- COLUMN 3: Button Settings (normal) / Custom Aura Bars (bars mode)
------------------------------------------------------------------------
local function RefreshColumn3()
    -- Bars & Frames panel mode: show Custom Aura Bars
    if CS.resourceBarPanelActive then
        local col3 = CS.configFrame and CS.configFrame.col3
        if not col3 then ST._RefreshButtonSettingsColumn() return end

        -- Hide button settings content that lives on the same col3 content area
        if col3.bsTabGroup then col3.bsTabGroup.frame:Hide() end
        if col3.bsPlaceholder then col3.bsPlaceholder:Hide() end
        if col3.multiSelectScroll then col3.multiSelectScroll.frame:Hide() end

        -- Create/show custom aura scroll
        if not col3._customAuraScroll then
            local scroll = AceGUI:Create("ScrollFrame")
            scroll:SetLayout("List")
            scroll.frame:SetParent(col3.content)
            scroll.frame:ClearAllPoints()
            scroll.frame:SetPoint("TOPLEFT", col3.content, "TOPLEFT", 0, 0)
            scroll.frame:SetPoint("BOTTOMRIGHT", col3.content, "BOTTOMRIGHT", 0, 0)
            col3._customAuraScroll = scroll
        end

        col3._customAuraScroll:ReleaseChildren()
        col3._customAuraScroll.frame:Show()
        ST._BuildCustomAuraBarPanel(col3._customAuraScroll)
        return
    end

    -- Normal mode: hide custom aura scroll
    local col3Normal = CS.configFrame and CS.configFrame.col3
    if col3Normal and col3Normal._customAuraScroll then
        col3Normal._customAuraScroll.frame:Hide()
    end

    ST._RefreshButtonSettingsColumn()
end

------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
ST._RefreshColumn3 = RefreshColumn3
