--[[
    CooldownCompanion - Config/PanelChangelogOverlay
    Bundled changelog overlay setup for the config panel.
]]

local ADDON_NAME, ST = ...
local CS = ST._configState
-- Changelog.lua loads first and owns the font size, its bounds and the data.
local Changelog = ST._Changelog

local AceGUI = LibStub("AceGUI-3.0")

local CHANGELOG_DROPDOWN_WIDTH = 140
local CHANGELOG_TEXT_BUTTON_WIDTH = 72
local CHANGELOG_CLOSE_BUTTON_WIDTH = 72
local CHANGELOG_CONTROL_ROW_INSET_Y = 12
local CHANGELOG_CONTROL_ROW_RESERVE = 38

-- Heading looks: size above the body text, colour, the spacers around the
-- divider that precedes a heading, and the spacer after it.
local HEADING_STYLES = {
    heading2 = { sizeOffset = 4, color = { 1, 0.82, 0 }, beforeDivider = 10, afterDivider = 12, after = 8 },
    heading3 = { sizeOffset = 2, color = { 1, 0.92, 0.65 }, beforeDivider = 8, afterDivider = 10, after = 6 },
}
local BODY_COLOR = { 0.96, 0.96, 0.96 }
local LIST_IMPORTANT_COLOR = { 1.00, 0.91, 0.67 }
local LIST_NESTED_COLOR = { 0.70, 0.87, 0.95 }

function ST._SetupChangelogOverlay(frame, colParent)
    local changelogOverlay
    local changelogContainer
    local changelogScroll
    local changelogVersionDrop
    local changelogFontDownBtn
    local changelogFontUpBtn
    local changelogCloseBtn
    local changelogDropdownUpdating = false
    local changelogScrollStatus = {}
    local changelogContentParent
    local changelogContentTopY = -10
    local changelogHiddenFrames = {}

    local function SaveChangelogScroll()
        local status = changelogScroll and (changelogScroll.status or changelogScroll.localstatus)
        return {
            scrollvalue = tonumber(status and status.scrollvalue) or 0,
        }
    end

    local function RestoreChangelogScroll(saved)
        if not changelogScroll then
            return
        end
        changelogScroll:SetScroll(tonumber(saved and saved.scrollvalue) or 0)
        changelogScroll:FixScroll()
    end

    local function AddChangelogSpacer(height)
        local spacer = AceGUI:Create("SimpleGroup")
        spacer:SetFullWidth(true)
        spacer:SetHeight(height)
        spacer.noAutoHeight = true
        changelogScroll:AddChild(spacer)
    end

    -- The divider texture rides a pooled SimpleGroup frame, so it hides when
    -- the widget goes back to the pool and can never show on another one.
    -- AceGUI clears callbacks on release, so this is set on every acquire.
    local function HideDividerOnRelease(widget)
        widget.frame._changelogDividerTex:Hide()
    end

    local function AddChangelogDivider()
        local divider = AceGUI:Create("SimpleGroup")
        divider:SetFullWidth(true)
        divider:SetHeight(1)
        divider.noAutoHeight = true
        if not divider.frame._changelogDividerTex then
            local tex = divider.frame:CreateTexture(nil, "ARTWORK")
            tex:SetPoint("TOPLEFT", divider.frame, "TOPLEFT", 0, 0)
            tex:SetPoint("TOPRIGHT", divider.frame, "TOPRIGHT", 0, 0)
            tex:SetHeight(1)
            divider.frame._changelogDividerTex = tex
        end
        divider.frame._changelogDividerTex:SetColorTexture(0.35, 0.35, 0.35, 0.4)
        divider.frame._changelogDividerTex:Show()
        divider:SetCallback("OnRelease", HideDividerOnRelease)
        changelogScroll:AddChild(divider)
    end

    local function AddChangelogLabel(text, fontPath, fontSize, fontFlags, color)
        local label = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(label)
        label:SetText(text)
        label:SetFullWidth(true)
        label:SetJustifyH("LEFT")
        label:SetJustifyV("TOP")
        label:SetFont(fontPath, fontSize, fontFlags or "")
        if color then
            label:SetColor(color[1], color[2], color[3])
        end
        changelogScroll:AddChild(label)
    end

    local function BuildChangelogListPrefix(depth, orderedIndex, isImportant)
        local indent = string.rep("    ", math.max(0, tonumber(depth) or 0))
        if isImportant then
            return indent .. "|cffFFB347!|r  "
        end
        if orderedIndex then
            return indent .. "|cff4EC9B0" .. tostring(orderedIndex) .. ".|r  "
        end
        return indent .. "|cff4EC9B0\226\128\162|r  "
    end

    local function UpdateChangelogFontButtons()
        local fontSize = Changelog.GetFontSize()
        local minSize, maxSize = Changelog.GetFontSizeBounds()
        if changelogFontDownBtn then
            changelogFontDownBtn:SetDisabled(fontSize <= minSize)
        end
        if changelogFontUpBtn then
            changelogFontUpBtn:SetDisabled(fontSize >= maxSize)
        end
    end

    local function UpdateChangelogVersionDropdown(selectedVersion)
        if not changelogVersionDrop then
            return
        end

        local orderedVersions = Changelog.GetDropdownVersions(selectedVersion)
        local versionList = {}
        for _, version in ipairs(orderedVersions) do
            versionList[version] = version
        end

        changelogDropdownUpdating = true
        changelogVersionDrop:SetList(versionList, orderedVersions)
        changelogVersionDrop:SetDisabled(#orderedVersions == 0)
        if #orderedVersions > 0 then
            local value = selectedVersion
            if not value or not versionList[value] then
                value = orderedVersions[1]
            end
            changelogVersionDrop:SetValue(value)
        else
            changelogVersionDrop:SetText("No entries")
        end
        changelogDropdownUpdating = false
    end

    changelogContainer = AceGUI:Create("InlineGroup")
    changelogContainer:SetTitle("Changelog")
    changelogContainer:SetLayout("Fill")
    changelogContainer.frame:SetParent(colParent)
    changelogContainer.frame:ClearAllPoints()
    changelogContainer.frame:SetPoint("TOPLEFT", colParent, "TOPLEFT", 0, 0)
    changelogContainer.frame:SetPoint("BOTTOMRIGHT", colParent, "BOTTOMRIGHT", 0, 0)
    changelogContainer.frame:SetFrameLevel(colParent:GetFrameLevel() + 20)
    changelogContainer.frame:Hide()
    changelogOverlay = changelogContainer.frame

    changelogScroll = AceGUI:Create("ScrollFrame")
    changelogScroll:SetLayout("List")
    changelogScroll:SetStatusTable(changelogScrollStatus)
    changelogContainer:AddChild(changelogScroll)

    if changelogContainer.content then
        changelogContentParent = changelogContainer.content:GetParent()
        local _, _, _, _, origY = changelogContainer.content:GetPoint(1)
        changelogContentTopY = origY or -10
        changelogContainer.content:ClearAllPoints()
        changelogContainer.content:SetPoint("TOPLEFT", changelogContentParent, "TOPLEFT", 10, changelogContentTopY)
        changelogContainer.content:SetPoint("BOTTOMRIGHT", changelogContentParent, "BOTTOMRIGHT", -10, CHANGELOG_CONTROL_ROW_RESERVE)
    end

    changelogCloseBtn = AceGUI:Create("Button")
    changelogCloseBtn:SetText(CLOSE)
    changelogCloseBtn:SetWidth(CHANGELOG_CLOSE_BUTTON_WIDTH)
    changelogCloseBtn:SetHeight(22)
    changelogCloseBtn:SetCallback("OnClick", function()
        if frame.HideChangelogOverlay then
            frame.HideChangelogOverlay()
        end
    end)
    changelogCloseBtn.frame:SetParent(changelogOverlay)
    changelogCloseBtn.frame:ClearAllPoints()
    changelogCloseBtn.frame:SetPoint("BOTTOMRIGHT", changelogContentParent or changelogOverlay, "BOTTOMRIGHT", -10, CHANGELOG_CONTROL_ROW_INSET_Y)
    changelogCloseBtn.frame:Show()

    changelogFontUpBtn = AceGUI:Create("Button")
    changelogFontUpBtn:SetText("Text +")
    changelogFontUpBtn:SetWidth(CHANGELOG_TEXT_BUTTON_WIDTH)
    changelogFontUpBtn:SetHeight(22)
    changelogFontUpBtn:SetCallback("OnClick", function()
        Changelog.AdjustFontSize(1)
        if frame.RenderChangelogOverlay then
            frame.RenderChangelogOverlay(frame._changelogCurrentVersion, true)
        end
    end)
    changelogFontUpBtn:SetCallback("OnEnter", function(widget)
        GameTooltip:SetOwner(widget.frame, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Increase Text Size")
        GameTooltip:AddLine("Increase changelog text size.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    changelogFontUpBtn:SetCallback("OnLeave", function()
        GameTooltip:Hide()
    end)
    changelogFontUpBtn.frame:SetParent(changelogOverlay)
    changelogFontUpBtn.frame:ClearAllPoints()
    changelogFontUpBtn.frame:SetPoint("RIGHT", changelogCloseBtn.frame, "LEFT", -2, 0)
    changelogFontUpBtn.frame:Show()

    changelogFontDownBtn = AceGUI:Create("Button")
    changelogFontDownBtn:SetText("Text -")
    changelogFontDownBtn:SetWidth(CHANGELOG_TEXT_BUTTON_WIDTH)
    changelogFontDownBtn:SetHeight(22)
    changelogFontDownBtn:SetCallback("OnClick", function()
        Changelog.AdjustFontSize(-1)
        if frame.RenderChangelogOverlay then
            frame.RenderChangelogOverlay(frame._changelogCurrentVersion, true)
        end
    end)
    changelogFontDownBtn:SetCallback("OnEnter", function(widget)
        GameTooltip:SetOwner(widget.frame, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Decrease Text Size")
        GameTooltip:AddLine("Decrease changelog text size.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    changelogFontDownBtn:SetCallback("OnLeave", function()
        GameTooltip:Hide()
    end)
    changelogFontDownBtn.frame:SetParent(changelogOverlay)
    changelogFontDownBtn.frame:ClearAllPoints()
    changelogFontDownBtn.frame:SetPoint("RIGHT", changelogFontUpBtn.frame, "LEFT", -2, 0)
    changelogFontDownBtn.frame:Show()

    changelogVersionDrop = AceGUI:Create("Dropdown")
    changelogVersionDrop:SetLabel("")
    changelogVersionDrop:SetWidth(CHANGELOG_DROPDOWN_WIDTH)
    changelogVersionDrop:SetPulloutWidth(CHANGELOG_DROPDOWN_WIDTH)
    changelogVersionDrop:SetCallback("OnValueChanged", function(_, _, value)
        if changelogDropdownUpdating or type(value) ~= "string" or value == "" then
            return
        end
        if frame.RenderChangelogOverlay then
            frame.RenderChangelogOverlay(value)
        end
    end)
    changelogVersionDrop.frame:SetParent(changelogOverlay)
    changelogVersionDrop.frame:ClearAllPoints()
    changelogVersionDrop.frame:SetPoint("RIGHT", changelogFontDownBtn.frame, "LEFT", -6, 0)
    changelogVersionDrop.frame:Show()

    local function RenderChangelogOverlay(version, preserveScroll)
        local activeVersion = version
        if activeVersion and not Changelog.HasEntry(activeVersion) then
            activeVersion = Changelog.GetNewestVersion()
        end

        local savedScroll = preserveScroll and SaveChangelogScroll() or nil
        local bodyFontPath, _, bodyFontFlags = GameFontHighlightSmall:GetFont()
        local headingFontPath, _, headingFontFlags = GameFontNormal:GetFont()
        local bodySize = Changelog.GetFontSize()
        -- The version title sits two points above a top-level heading.
        local versionFontSize = bodySize + HEADING_STYLES.heading2.sizeOffset + 2
        local estimatedVersionHeight = versionFontSize + 8
        local versionBandHeight = math.max(54, versionFontSize + 26)
        local versionTopSpacer = math.max(6, math.floor((versionBandHeight - estimatedVersionHeight) * 0.5))
        local versionBottomSpacer = math.max(6, versionBandHeight - estimatedVersionHeight - versionTopSpacer)

        frame._changelogCurrentVersion = activeVersion

        changelogScroll:PauseLayout()
        changelogScroll:ReleaseChildren()

        if activeVersion and Changelog.HasEntry(activeVersion) then
            AddChangelogSpacer(versionTopSpacer)
            AddChangelogLabel("v" .. activeVersion, headingFontPath, versionFontSize, headingFontFlags, {1, 0.82, 0})
            AddChangelogSpacer(versionBottomSpacer)

            local pendingVersionDivider = true
            local function FlushVersionDivider(spacerAfter)
                if not pendingVersionDivider then
                    return false
                end
                AddChangelogDivider()
                if spacerAfter and spacerAfter > 0 then
                    AddChangelogSpacer(spacerAfter)
                end
                pendingVersionDivider = false
                return true
            end

            local tokens = Changelog.GetRenderTokens(activeVersion) or {}
            if #tokens == 0 then
                FlushVersionDivider(10)
                AddChangelogLabel("No release notes were bundled for this version.", bodyFontPath, bodySize, bodyFontFlags, {0.92, 0.92, 0.92})
            else
                for _, token in ipairs(tokens) do
                    local tokenType = token.type or "paragraph"
                    local text = token.text or ""
                    local style = HEADING_STYLES[tokenType]
                    if style then
                        -- The first token takes the version divider; every
                        -- later heading draws its own.
                        if not FlushVersionDivider(style.afterDivider) then
                            AddChangelogSpacer(style.beforeDivider)
                            AddChangelogDivider()
                            AddChangelogSpacer(style.afterDivider)
                        end
                        AddChangelogLabel(text, headingFontPath, bodySize + style.sizeOffset, headingFontFlags, style.color)
                        AddChangelogSpacer(style.after)
                    elseif tokenType == "bullet" or tokenType == "ordered_bullet" then
                        FlushVersionDivider(10)
                        local listColor = BODY_COLOR
                        if token.important then
                            listColor = LIST_IMPORTANT_COLOR
                        elseif (tonumber(token.depth) or 0) > 0 then
                            listColor = LIST_NESTED_COLOR
                        end
                        -- Plain bullets carry no index, so they keep the bullet glyph.
                        AddChangelogLabel(BuildChangelogListPrefix(token.depth, token.index, token.important) .. text, bodyFontPath, bodySize, bodyFontFlags, listColor)
                        AddChangelogSpacer(5)
                    else
                        FlushVersionDivider(10)
                        AddChangelogLabel(text, bodyFontPath, bodySize, bodyFontFlags, BODY_COLOR)
                        AddChangelogSpacer(6)
                    end
                end
            end
        else
            AddChangelogSpacer(10)
            AddChangelogLabel("No bundled changelog entries are available for this build yet.", bodyFontPath, bodySize, bodyFontFlags, {0.92, 0.92, 0.92})
        end

        AddChangelogSpacer(4)
        changelogScroll:ResumeLayout()
        changelogScroll:DoLayout()

        UpdateChangelogVersionDropdown(activeVersion)
        UpdateChangelogFontButtons()

        if savedScroll then
            RestoreChangelogScroll(savedScroll)
        else
            changelogScroll:SetScroll(0)
            changelogScroll:FixScroll()
        end
    end

    frame.RenderChangelogOverlay = RenderChangelogOverlay
    frame.HideChangelogOverlay = function()
        if changelogVersionDrop and changelogVersionDrop.open and changelogVersionDrop.pullout then
            changelogVersionDrop.pullout:Close()
        end
        changelogOverlay:Hide()
        for child in pairs(changelogHiddenFrames) do
            child:Show()
        end
        wipe(changelogHiddenFrames)
    end
    frame.OpenChangelogOverlay = function(version, opts)
        if CS.spellbookPanelWindow then CS.CloseSpellbookPanel() end
        local targetVersion = version

        if not (targetVersion and Changelog.HasEntry(targetVersion)) then
            targetVersion = Changelog.GetNewestVersion()
        end

        wipe(changelogHiddenFrames)
        for _, child in ipairs({colParent:GetChildren()}) do
            if child ~= changelogOverlay and child:IsShown() then
                changelogHiddenFrames[child] = true
                child:Hide()
            end
        end
        changelogOverlay:Show()
        changelogOverlay:Raise()
        RenderChangelogOverlay(targetVersion)

        if opts and opts.autoOpen and targetVersion then
            Changelog.MarkSeen(targetVersion)
        end
    end
    frame.ToggleChangelogOverlay = function()
        if changelogOverlay:IsShown() then
            frame.HideChangelogOverlay()
        else
            frame.OpenChangelogOverlay()
        end
    end

    return changelogOverlay
end
