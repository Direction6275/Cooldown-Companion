--[[
    CooldownCompanion - Config/PanelChangelogOverlay
    Bundled changelog overlay setup for the config panel.
]]

local ADDON_NAME, ST = ...

local AceGUI = LibStub("AceGUI-3.0")

local CHANGELOG_DROPDOWN_WIDTH = 140
local CHANGELOG_TEXT_BUTTON_WIDTH = 72
local CHANGELOG_CLOSE_BUTTON_WIDTH = 72
local CHANGELOG_CONTROL_ROW_INSET_Y = 12
local CHANGELOG_CONTROL_ROW_RESERVE = 38

function ST._SetupChangelogOverlay(frame, colParent, onHighlightChanged)
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
            offset = tonumber(status and status.offset) or 0,
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
        if spacer.frame._changelogDividerTex then
            spacer.frame._changelogDividerTex:Hide()
        end
        changelogScroll:AddChild(spacer)
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
        changelogScroll:AddChild(divider)
    end

    local function AddChangelogLabel(text, fontPath, fontSize, fontFlags, color)
        local label = AceGUI:Create("Label")
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
        local changelog = ST._Changelog
        local fontSize = (changelog and changelog.GetFontSize and changelog.GetFontSize()) or 13
        local minSize, maxSize = 11, 18
        if changelog and changelog.GetFontSizeBounds then
            minSize, maxSize = changelog.GetFontSizeBounds()
        end
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

        local changelog = ST._Changelog
        local orderedVersions = (changelog and changelog.GetDropdownVersions and changelog.GetDropdownVersions(selectedVersion))
            or ((changelog and changelog.GetOrderedVersions and changelog.GetOrderedVersions()) or {})
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
        local changelog = ST._Changelog
        if changelog and changelog.AdjustFontSize then
            changelog.AdjustFontSize(1)
        end
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
        local changelog = ST._Changelog
        if changelog and changelog.AdjustFontSize then
            changelog.AdjustFontSize(-1)
        end
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
        local changelog = ST._Changelog
        local activeVersion = version
        if activeVersion and changelog and not changelog.HasEntry(activeVersion) then
            activeVersion = changelog.GetNewestVersion()
        end

        local savedScroll = preserveScroll and SaveChangelogScroll() or nil
        local bodyFontPath, _, bodyFontFlags = GameFontHighlightSmall:GetFont()
        local headingFontPath, _, headingFontFlags = GameFontNormal:GetFont()
        local bodySize = (changelog and changelog.GetFontSize and changelog.GetFontSize()) or 13
        local heading2Size = bodySize + 4
        local heading3Size = bodySize + 2
        local versionFontSize = heading2Size + 2
        local estimatedVersionHeight = versionFontSize + 8
        local versionBandHeight = math.max(54, versionFontSize + 26)
        local versionTopSpacer = math.max(6, math.floor((versionBandHeight - estimatedVersionHeight) * 0.5))
        local versionBottomSpacer = math.max(6, versionBandHeight - estimatedVersionHeight - versionTopSpacer)

        frame._changelogCurrentVersion = activeVersion
        frame._changelogPreviousVersion = nil
        frame._changelogNextVersion = nil

        changelogScroll:PauseLayout()
        changelogScroll:ReleaseChildren()

        if activeVersion and changelog and changelog.HasEntry(activeVersion) then
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

            local tokens = changelog.GetRenderTokens(activeVersion) or {}
            if #tokens == 0 then
                FlushVersionDivider(10)
                AddChangelogLabel("No release notes were bundled for this version.", bodyFontPath, bodySize, bodyFontFlags, {0.92, 0.92, 0.92})
            else
                local renderedAny = false
                for _, token in ipairs(tokens) do
                    local tokenType = token.type or "paragraph"
                    local text = token.text or ""
                    if tokenType == "heading2" then
                        if FlushVersionDivider(12) then
                        elseif renderedAny then
                            AddChangelogSpacer(10)
                            AddChangelogDivider()
                            AddChangelogSpacer(12)
                        else
                            AddChangelogSpacer(10)
                        end
                        AddChangelogLabel(text, headingFontPath, heading2Size, headingFontFlags, {1, 0.82, 0})
                        AddChangelogSpacer(8)
                        renderedAny = true
                    elseif tokenType == "heading3" then
                        if FlushVersionDivider(10) then
                        elseif renderedAny then
                            AddChangelogSpacer(8)
                            AddChangelogDivider()
                            AddChangelogSpacer(10)
                        else
                            AddChangelogSpacer(10)
                        end
                        AddChangelogLabel(text, headingFontPath, heading3Size, headingFontFlags, {1, 0.92, 0.65})
                        AddChangelogSpacer(6)
                        renderedAny = true
                    elseif tokenType == "bullet" then
                        FlushVersionDivider(10)
                        local bulletColor = {0.96, 0.96, 0.96}
                        if token.important then
                            bulletColor = {1.00, 0.91, 0.67}
                        elseif (tonumber(token.depth) or 0) > 0 then
                            bulletColor = {0.70, 0.87, 0.95}
                        end
                        AddChangelogLabel(BuildChangelogListPrefix(token.depth, nil, token.important) .. text, bodyFontPath, bodySize, bodyFontFlags, bulletColor)
                        AddChangelogSpacer(5)
                        renderedAny = true
                    elseif tokenType == "ordered_bullet" then
                        FlushVersionDivider(10)
                        local orderedColor = {0.96, 0.96, 0.96}
                        if token.important then
                            orderedColor = {1.00, 0.91, 0.67}
                        elseif (tonumber(token.depth) or 0) > 0 then
                            orderedColor = {0.70, 0.87, 0.95}
                        end
                        AddChangelogLabel(BuildChangelogListPrefix(token.depth, token.index, token.important) .. text, bodyFontPath, bodySize, bodyFontFlags, orderedColor)
                        AddChangelogSpacer(5)
                        renderedAny = true
                    else
                        FlushVersionDivider(10)
                        AddChangelogLabel(text, bodyFontPath, bodySize, bodyFontFlags, {0.96, 0.96, 0.96})
                        AddChangelogSpacer(6)
                        renderedAny = true
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
        if onHighlightChanged then
            onHighlightChanged()
        end
    end
    frame.OpenChangelogOverlay = function(version, opts)
        local changelog = ST._Changelog
        local targetVersion = version

        if not (changelog and targetVersion and changelog.HasEntry(targetVersion)) then
            targetVersion = changelog and changelog.GetNewestVersion() or nil
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
        if onHighlightChanged then
            onHighlightChanged()
        end
        RenderChangelogOverlay(targetVersion)

        if opts and opts.autoOpen and targetVersion and changelog then
            changelog.MarkSeen(targetVersion)
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
