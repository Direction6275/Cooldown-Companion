--[[
    CooldownCompanion - Config/Pickers
    Frame picker + CDM picker modes.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local issecretvalue = issecretvalue
local canaccessvalue = canaccessvalue
local bit_band = bit and bit.band
local math_max = math.max

-- File-local state
local pickFrameOverlay = nil
local pickFrameCallback = nil
local pickFrameSourceGroupId = nil
local pickCDMOverlay = nil
local pickCDMCallback = nil
local pickAuraTextureOverlay = nil
local pickAuraTextureCallback = nil
local AURA_TEXTURE_FILTER_SYMBOLS = "symbols"
local AURA_TEXTURE_FILTER_OTHER = "other"
local AURA_TEXTURE_FILTER_RECENT = "recent"

------------------------------------------------------------------------
-- Secret-safe value helpers
------------------------------------------------------------------------
local function IsAccessibleBoolean(value)
    if type(value) ~= "boolean" then return false end
    if issecretvalue and issecretvalue(value) then return false end
    if canaccessvalue and not canaccessvalue(value) then return false end
    return value
end

local function GetAccessibleBoolean(value)
    if type(value) ~= "boolean" then return nil end
    if issecretvalue and issecretvalue(value) then return nil end
    if canaccessvalue and not canaccessvalue(value) then return nil end
    return value
end

local function IsAccessibleNumber(value)
    if type(value) ~= "number" then return false end
    if issecretvalue and issecretvalue(value) then return false end
    if canaccessvalue and not canaccessvalue(value) then return false end
    return true
end

local function IsAccessibleString(value)
    if type(value) ~= "string" then return false end
    if issecretvalue and issecretvalue(value) then return false end
    if canaccessvalue and not canaccessvalue(value) then return false end
    return true
end

local function IsShownSafe(region)
    if not region or not region.IsShown then return false end
    if region.IsForbidden and region:IsForbidden() then return false end
    local shown = region:IsShown()
    return IsAccessibleBoolean(shown)
end

local function IsVisibleSafe(region)
    if not region or not region.IsVisible then return false end
    if region.IsForbidden and region:IsForbidden() then return false end
    local visible = region:IsVisible()
    return IsAccessibleBoolean(visible)
end

local function IsRectMeasurementSafe(region)
    if not region or not region.GetRect then
        return false
    end
    if region.IsForbidden and region:IsForbidden() then
        return false
    end
    if region.IsAnchoringRestricted then
        local isRestricted = GetAccessibleBoolean(region:IsAnchoringRestricted())
        if isRestricted == nil or isRestricted then
            return false
        end
    end
    return true
end

local function GetAccessibleRect(region)
    if not IsRectMeasurementSafe(region) then
        return nil, nil, nil, nil
    end
    local left, bottom, width, height = region:GetRect()
    if not IsAccessibleNumber(left)
       or not IsAccessibleNumber(bottom)
       or not IsAccessibleNumber(width)
       or not IsAccessibleNumber(height) then
        return nil, nil, nil, nil
    end
    return left, bottom, width, height
end

local function GetAccessibleSpellID(value)
    if not IsAccessibleNumber(value) then return nil end
    if value <= 0 then return nil end
    return value
end

local function ResolveCDMItemName(item, spellID)
    if item and item.GetNameText then
        local name = item:GetNameText()
        if IsAccessibleString(name) and name ~= "" then
            return name
        end
    end

    if spellID then
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        if spellInfo and spellInfo.name then
            return spellInfo.name
        end
        return tostring(spellID)
    end

    return ""
end

local function ResolveCDMInfoSpellID(cooldownInfo)
    if not cooldownInfo then return nil end
    local spellID = GetAccessibleSpellID(cooldownInfo.overrideTooltipSpellID)
    if spellID then return spellID end
    spellID = GetAccessibleSpellID(cooldownInfo.overrideSpellID)
    if spellID then return spellID end
    return GetAccessibleSpellID(cooldownInfo.spellID)
end

local function HasCooldownFlag(cooldownInfo, flag)
    if not cooldownInfo or not IsAccessibleNumber(flag) then
        return false
    end
    local flags = cooldownInfo.flags
    if not IsAccessibleNumber(flags) or not bit_band then
        return false
    end
    return bit_band(flags, flag) ~= 0
end

local function ShouldIncludeCDMAuraInfo(cooldownInfo)
    if not cooldownInfo then
        return false
    end

    local flagsEnum = Enum and Enum.CooldownSetSpellFlags
    if flagsEnum then
        if HasCooldownFlag(cooldownInfo, flagsEnum.HideAura) then
            return false
        end
    end

    return true
end

local function BuildCDMAuraPickerEntries()
    local entries = {}
    local showUnlearned = false
    if C_CVar and C_CVar.GetCVarBool then
        showUnlearned = GetAccessibleBoolean(C_CVar.GetCVarBool("cooldownViewerShowUnlearned")) and true or false
    end
    local categories = {
        Enum.CooldownViewerCategory.TrackedBuff,
        Enum.CooldownViewerCategory.TrackedBar,
    }
    local seenCooldownIDs = {}

    local settings = CooldownViewerSettings
    if not settings and C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_CooldownViewer")
        settings = CooldownViewerSettings
    end

    local dataProvider = settings and settings.GetDataProvider and settings:GetDataProvider()
    local function ProcessCategory(category, getCooldownIDsForCategory, getCooldownInfoForID)
        local cooldownIDs = getCooldownIDsForCategory(category)
        if not cooldownIDs then
            return
        end

        for _, cooldownID in ipairs(cooldownIDs) do
            if IsAccessibleNumber(cooldownID) and cooldownID > 0 and not seenCooldownIDs[cooldownID] then
                local cooldownInfo = getCooldownInfoForID(cooldownID)
                if ShouldIncludeCDMAuraInfo(cooldownInfo) then
                    local spellID = ResolveCDMInfoSpellID(cooldownInfo)
                    if spellID then
                        seenCooldownIDs[cooldownID] = true
                        entries[#entries + 1] = {
                            spellID = spellID,
                            cooldownID = cooldownID,
                            category = category,
                            name = ResolveCDMItemName(nil, spellID),
                            iconID = C_Spell.GetSpellTexture(spellID),
                        }
                    end
                end
            end
        end
    end

    local getCooldownIDsForCategory
    local getCooldownInfoForID
    if dataProvider and dataProvider.CheckBuildDisplayData
        and dataProvider.GetOrderedCooldownIDsForCategory
        and dataProvider.GetCooldownInfoForID then
        dataProvider:CheckBuildDisplayData()
        getCooldownIDsForCategory = function(category)
            return dataProvider:GetOrderedCooldownIDsForCategory(category, showUnlearned)
        end
        getCooldownInfoForID = function(cooldownID)
            return dataProvider:GetCooldownInfoForID(cooldownID)
        end
    else
        -- Fallback when settings data provider is unavailable.
        getCooldownIDsForCategory = function(category)
            return C_CooldownViewer.GetCooldownViewerCategorySet(category, showUnlearned)
        end
        getCooldownInfoForID = function(cooldownID)
            return C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
        end
    end

    for _, category in ipairs(categories) do
        ProcessCategory(category, getCooldownIDsForCategory, getCooldownInfoForID)
    end

    -- Keep all duplicate spell IDs and number them for clear per-entry selection.
    local totalBySpellID = {}
    for _, entry in ipairs(entries) do
        totalBySpellID[entry.spellID] = (totalBySpellID[entry.spellID] or 0) + 1
    end
    local seenBySpellID = {}
    for _, entry in ipairs(entries) do
        local total = totalBySpellID[entry.spellID] or 0
        if total > 1 then
            local index = (seenBySpellID[entry.spellID] or 0) + 1
            seenBySpellID[entry.spellID] = index
            entry.duplicateIndex = index
            entry.duplicateTotal = total
        end
    end

    return entries
end

------------------------------------------------------------------------
-- Helper: Resolve named frame from mouse focus
------------------------------------------------------------------------
local function ResolveNamedFrame(frame)
    while frame do
        if frame.IsForbidden and frame:IsForbidden() then
            return nil, nil
        end
        local name = frame:GetName()
        if name and name ~= "" then
            return frame, name
        end
        frame = frame:GetParent()
    end
    return nil, nil
end

------------------------------------------------------------------------
-- Helper: Check if frame name belongs to this addon (should be excluded)
------------------------------------------------------------------------
local function IsAddonFrame(name)
    if not name or type(name) ~= "string" then return true end
    -- Allow group frames through selectively (exclude self and circular chains)
    if name:find("^CooldownCompanionGroup%d+$") then
        local groupId = tonumber(name:match("^CooldownCompanionGroup(%d+)$"))
        if groupId and pickFrameSourceGroupId then
            if groupId == pickFrameSourceGroupId then return true end
            if CooldownCompanion:WouldCreateCircularAnchor(pickFrameSourceGroupId, groupId) then return true end
        end
        return false
    -- Allow container frames through selectively (exclude circular chains)
    elseif name:find("^CooldownCompanionContainer%d+$") then
        local containerId = tonumber(name:match("^CooldownCompanionContainer(%d+)$"))
        if containerId and pickFrameSourceGroupId then
            if CooldownCompanion:WouldCreateCircularAnchor(pickFrameSourceGroupId, containerId, "container") then return true end
        end
        return false
    elseif name:find("^CooldownCompanion") then
        return true
    end
    if name == "WorldFrame" then return true end
    -- Exclude the config panel itself (AceGUI frames)
    if CS.configFrame and CS.configFrame.frame and CS.configFrame.frame:GetName() == name then return true end
    return false
end

local function ResolveNamedMeasurableFrame(frame)
    while frame do
        if frame.IsForbidden and frame:IsForbidden() then
            return nil, nil
        end
        local name = frame:GetName()
        if name and name ~= "" and not IsAddonFrame(name) and IsRectMeasurementSafe(frame) then
            return frame, name
        end
        frame = frame:GetParent()
    end
    return nil, nil
end

------------------------------------------------------------------------
-- Helper: Check if a frame has visible content (not an empty container)
------------------------------------------------------------------------
local function HasVisibleContent(frame)
    if frame:GetObjectType() ~= "Frame" then return true end
    if frame:IsMouseEnabled() then return true end
    for _, region in pairs({ frame:GetRegions() }) do
        if IsShownSafe(region) then return true end
    end
    -- Container frames with shown children also count as having visible content
    for _, child in pairs({ frame:GetChildren() }) do
        if IsShownSafe(child) then return true end
    end
    return false
end

------------------------------------------------------------------------
-- Helper: Find deepest named child frame under cursor
------------------------------------------------------------------------
local function FindDeepestNamedChild(frame, cx, cy)
    local bestFrame, bestName, bestArea = nil, nil, math.huge
    local children = { frame:GetChildren() }
    for _, child in ipairs(children) do
        local visible = IsVisibleSafe(child)
        if visible then
            local name = child:GetName()
            if name and name ~= "" and not IsAddonFrame(name) then
                local left, bottom, width, height = GetAccessibleRect(child)
                local inside, area = false, 0
                if left and width and width > 0 and height > 0 then
                    if cx >= left and cx <= left + width and cy >= bottom and cy <= bottom + height then
                        inside, area = true, width * height
                    end
                end
                if inside and area < bestArea and HasVisibleContent(child) then
                    bestFrame, bestName, bestArea = child, name, area
                end
            end
            -- Recurse into children regardless of whether this child is named
            local deeperFrame, deeperName, deeperArea = FindDeepestNamedChild(child, cx, cy)
            if deeperFrame and deeperArea < bestArea then
                bestFrame, bestName, bestArea = deeperFrame, deeperName, deeperArea
            end
        end
    end
    return bestFrame, bestName, bestArea
end

------------------------------------------------------------------------
-- Frame picker
------------------------------------------------------------------------
local function FinishPickFrame(name)
    if not pickFrameOverlay then return end
    pickFrameOverlay:Hide()
    CooldownCompanion:ClearPickModeIndicators()
    local cb = pickFrameCallback
    pickFrameCallback = nil
    pickFrameSourceGroupId = nil
    if cb then
        cb(name)
    end
end

local function StartPickFrame(callback, sourceGroupId)
    pickFrameCallback = callback
    pickFrameSourceGroupId = sourceGroupId

    -- Create overlay lazily
    if not pickFrameOverlay then
        -- Visual-only overlay: EnableMouse(false) so GetMouseFoci sees through it
        local overlay = CreateFrame("Frame", "CooldownCompanionPickOverlay", UIParent)
        overlay:SetFrameStrata("FULLSCREEN_DIALOG")
        overlay:SetFrameLevel(100)
        overlay:SetAllPoints(UIParent)
        overlay:EnableMouse(false)
        overlay:EnableKeyboard(true)

        -- Semi-transparent dark background
        local bg = overlay:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.3)
        overlay.bg = bg

        -- Instruction text at top
        local instructions = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        instructions:SetPoint("TOP", overlay, "TOP", 0, -30)
        instructions:SetText("Click a frame to anchor  |  Right-click or Escape to cancel")
        instructions:SetTextColor(1, 1, 1, 0.9)
        overlay.instructions = instructions

        -- Cursor-following label showing frame name
        local label = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        label:SetTextColor(0.2, 1, 0.2, 1)
        overlay.label = label

        -- Highlight frame (colored border that outlines hovered frame)
        local highlight = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
        highlight:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
        })
        highlight:SetBackdropBorderColor(0, 1, 0, 0.9)
        highlight:Hide()
        overlay.highlight = highlight

        -- OnUpdate: detect frame under cursor (overlay is mouse-transparent)
        local scanElapsed = 0
        overlay:SetScript("OnUpdate", function(self, dt)
            -- Compute cursor position in UIParent coordinates (needed for all paths)
            local cx, cy = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale

            local resolvedFrame, name

            -- Try GetMouseFoci first
            local foci = GetMouseFoci()
            local focus = foci and foci[1]
            if focus and focus ~= WorldFrame then
                resolvedFrame, name = ResolveNamedMeasurableFrame(focus)
                if not name then
                    resolvedFrame, name = ResolveNamedFrame(focus)
                end
            end

            -- If GetMouseFoci didn't find a useful frame, scan from UIParent
            -- Throttle the full scan to avoid per-frame cost
            if not name or IsAddonFrame(name) then
                scanElapsed = scanElapsed + dt
                if scanElapsed >= 0.05 then
                    scanElapsed = 0
                    local scanFrame, scanName, scanArea = FindDeepestNamedChild(UIParent, cx, cy)
                    if scanFrame and scanName and not IsAddonFrame(scanName) then
                        -- Reject screen-sized containers (e.g. ElvUIParent)
                        local uiW, uiH = UIParent:GetSize()
                        if scanArea <= uiW * uiH * 0.25 then
                            resolvedFrame, name = scanFrame, scanName
                        end
                    end
                else
                    -- Between throttle ticks, reuse last result
                    resolvedFrame = self.lastResolvedFrame
                    name = self.currentName
                end
            else
                scanElapsed = 0
                -- GetMouseFoci found a named frame; try to find a deeper child
                local deepFrame, deepName = FindDeepestNamedChild(resolvedFrame, cx, cy)
                if deepFrame then
                    resolvedFrame, name = deepFrame, deepName
                end
            end

            if not name then
                self.label:SetText("")
                self.highlight:Hide()
                self.currentName = nil
                self.lastResolvedFrame = nil
                return
            end

            self.currentName = name
            self.lastResolvedFrame = resolvedFrame

            local displayName = name
            local gidStr = name:match("^CooldownCompanionGroup(%d+)$")
            if gidStr then
                local gid = tonumber(gidStr)
                local grps = CooldownCompanion.db.profile.groups
                if gid and grps and grps[gid] then
                    displayName = grps[gid].name
                end
            end

            self.label:ClearAllPoints()
            self.label:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx + 20, cy + 10)
            self.label:SetText(displayName)

            -- Position highlight around the resolved frame
            local left, bottom, width, height = GetAccessibleRect(resolvedFrame)
            if left and width and width > 0 and height > 0 then
                self.highlight:ClearAllPoints()
                self.highlight:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
                self.highlight:SetSize(width, height)
                self.highlight:Show()
            else
                self.highlight:Hide()
            end
        end)

        -- Detect clicks via GLOBAL_MOUSE_DOWN (overlay is mouse-transparent)
        overlay:RegisterEvent("GLOBAL_MOUSE_DOWN")
        overlay:SetScript("OnEvent", function(self, event, button)
            if event ~= "GLOBAL_MOUSE_DOWN" then return end
            if button == "LeftButton" then
                FinishPickFrame(self.currentName)
            elseif button == "RightButton" then
                FinishPickFrame(nil)
            end
        end)

        -- Escape to cancel
        overlay:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:SetPropagateKeyboardInput(false)
                FinishPickFrame(nil)
            else
                self:SetPropagateKeyboardInput(true)
            end
        end)

        overlay:SetScript("OnHide", function(self)
            self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        end)

        overlay:SetScript("OnShow", function(self)
            self:RegisterEvent("GLOBAL_MOUSE_DOWN")
        end)

        pickFrameOverlay = overlay
    end

    -- Hide config panel, show overlay
    if CS.configFrame and IsShownSafe(CS.configFrame.frame) then
        CS.configFrame.frame:Hide()
    end
    pickFrameOverlay.currentName = nil
    pickFrameOverlay.label:SetText("")
    pickFrameOverlay.highlight:Hide()
    pickFrameOverlay:Show()
    if pickFrameSourceGroupId then
        CooldownCompanion:ShowPickModeIndicators(pickFrameSourceGroupId)
    end
end

------------------------------------------------------------------------
-- CDM picker
------------------------------------------------------------------------
local function FinishPickCDM(spellID)
    if not pickCDMOverlay then return end
    pickCDMOverlay:Hide()
    CooldownCompanion._cdmPickMode = false
    CooldownCompanion:ApplyCdmAlpha()
    local cb = pickCDMCallback
    pickCDMCallback = nil
    if cb then
        cb(spellID)
    end
end

local function StartPickCDM(callback)
    pickCDMCallback = callback

    -- Create overlay lazily
    if not pickCDMOverlay then
        local overlay = CreateFrame("Frame", "CooldownCompanionPickCDMOverlay", UIParent)
        overlay:SetFrameStrata("FULLSCREEN_DIALOG")
        overlay:SetFrameLevel(100)
        overlay:SetAllPoints(UIParent)
        overlay:EnableMouse(true)
        overlay:EnableKeyboard(true)

        -- Semi-transparent dark background
        local bg = overlay:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.3)
        overlay.bg = bg

        -- Instruction text at top
        local instructions = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        instructions:SetPoint("TOP", overlay, "TOP", 0, -30)
        overlay.defaultInstructionsText = "Click a Tracked Buff/Bar aura  |  Right-click or Escape to cancel"
        instructions:SetText(overlay.defaultInstructionsText)
        instructions:SetTextColor(1, 1, 1, 0.9)
        overlay.instructions = instructions

        local panel = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
        panel:SetPoint("CENTER", overlay, "CENTER", 0, -5)
        panel:SetSize(980, 620)

        local function ApplyPanelBackdrop()
            local source = CS.configFrame and CS.configFrame.frame
            local copied = false
            if source and source.GetBackdrop and panel.SetBackdrop then
                local backdrop = source:GetBackdrop()
                if backdrop then
                    local copy = {}
                    for k, v in pairs(backdrop) do
                        if type(v) == "table" then
                            copy[k] = {}
                            for k2, v2 in pairs(v) do
                                copy[k][k2] = v2
                            end
                        else
                            copy[k] = v
                        end
                    end
                    panel:SetBackdrop(copy)
                    copied = true
                    if source.GetBackdropColor and panel.SetBackdropColor then
                        panel:SetBackdropColor(source:GetBackdropColor())
                    end
                    if source.GetBackdropBorderColor and panel.SetBackdropBorderColor then
                        panel:SetBackdropBorderColor(source:GetBackdropBorderColor())
                    end
                end
            end

            if not copied then
                panel:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8x8",
                    edgeFile = "Interface\\Buttons\\WHITE8x8",
                    edgeSize = 1,
                })
                panel:SetBackdropColor(0.05, 0.08, 0.10, 0.95)
                panel:SetBackdropBorderColor(0.2, 0.45, 0.55, 0.9)
            end
        end
        ApplyPanelBackdrop()
        overlay.ApplyPanelBackdrop = ApplyPanelBackdrop

        local panelTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        panelTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -12)
        panelTitle:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -40, -12)
        panelTitle:SetJustifyH("CENTER")
        panelTitle:SetText("Pick Tracked Buff/Bar Aura")
        panel.title = panelTitle

        local closeBtn = CreateFrame("Button", nil, panel)
        closeBtn:SetSize(19, 19)
        closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8)
        local closeIcon = closeBtn:CreateTexture(nil, "ARTWORK")
        closeIcon:SetAtlas("common-icon-redx", false)
        closeIcon:SetAllPoints()
        closeBtn:SetHighlightAtlas("common-icon-redx")
        closeBtn:GetHighlightTexture():SetAlpha(0.3)
        closeBtn:SetScript("OnClick", function()
            FinishPickCDM(nil)
        end)
        panel.closeBtn = closeBtn

        local topSeparator = panel:CreateTexture(nil, "BORDER")
        topSeparator:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -34)
        topSeparator:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -34)
        topSeparator:SetHeight(1)
        topSeparator:SetColorTexture(0.25, 0.55, 0.65, 0.9)
        panel.topSeparator = topSeparator

        overlay.panel = panel

        local listTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        listTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -52)
        listTitle:SetJustifyH("LEFT")
        listTitle:SetText("Tracked Buff/Bar Auras")
        overlay.listTitle = listTitle

        local listScroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
        listScroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -74)
        listScroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -32, 14)
        overlay.listScroll = listScroll

        local listContent = CreateFrame("Frame", nil, listScroll)
        listContent:SetSize(1, 1)
        listScroll:SetScrollChild(listContent)
        overlay.listContent = listContent

        overlay.rows = {}
        overlay.rowHeight = 34
        overlay.rowIconSize = 24

        local function AcquireRow(index)
            local row = overlay.rows[index]
            if row then
                return row
            end

            row = CreateFrame("Button", nil, listContent, "BackdropTemplate")
            row:SetHeight((overlay.rowHeight or 34) - 2)
            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            row:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 8,
                insets = { left = 1, right = 1, top = 1, bottom = 1 },
            })
            row:SetBackdropColor(0, 0, 0, 0)
            row:SetBackdropBorderColor(0, 0, 0, 0)

            local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(overlay.rowIconSize or 24, overlay.rowIconSize or 24)
            icon:SetPoint("LEFT", row, "LEFT", 10, 0)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.icon = icon

            text:SetPoint("LEFT", icon, "RIGHT", 10, 0)
            text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            text:SetJustifyH("LEFT")
            row.text = text

            row:SetScript("OnEnter", function(self)
                self:SetBackdropColor(0.16, 0.22, 0.32, 0.6)
                self:SetBackdropBorderColor(0.4, 0.75, 1, 0.8)
            end)
            row:SetScript("OnLeave", function(self)
                self:SetBackdropColor(0, 0, 0, 0)
                self:SetBackdropBorderColor(0, 0, 0, 0)
            end)
            row:SetScript("OnClick", function(self, button)
                if button == "LeftButton" and self.spellID then
                    FinishPickCDM(self.spellID)
                elseif button == "RightButton" then
                    FinishPickCDM(nil)
                end
            end)

            overlay.rows[index] = row
            return row
        end

        local function RefreshRows()
            local entries = overlay.entries or {}
            local rowHeight = overlay.rowHeight or 34
            local listWidth = listScroll:GetWidth()
            if not listWidth or listWidth <= 0 then
                local panelWidth = panel:GetWidth()
                listWidth = (panelWidth and panelWidth > 46) and (panelWidth - 46) or 934
            end
            local contentHeight = math.max(1, #entries * rowHeight)
            listContent:SetSize(listWidth, contentHeight)

            for index, entry in ipairs(entries) do
                local row = AcquireRow(index)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", listContent, "TOPLEFT", 0, -((index - 1) * rowHeight))
                row:SetPoint("TOPRIGHT", listContent, "TOPRIGHT", 0, -((index - 1) * rowHeight))
                row.spellID = entry.spellID
                row.cooldownID = entry.cooldownID

                local categoryText = (entry.category == Enum.CooldownViewerCategory.TrackedBar) and "Tracked Bar" or "Tracked Buff"
                local duplicateSuffix = ""
                if entry.duplicateTotal and entry.duplicateTotal > 1 and entry.duplicateIndex then
                    duplicateSuffix = "  #" .. entry.duplicateIndex
                end
                local spellName = entry.name or tostring(entry.spellID)
                local iconID = entry.iconID
                if row.icon then
                    row.icon:SetTexture((IsAccessibleNumber(iconID) and iconID > 0) and iconID or 134400)
                end
                row.text:SetText(spellName .. duplicateSuffix .. "  |  " .. entry.spellID .. "  |  " .. categoryText)
                row:Show()
            end

            for index = #entries + 1, #overlay.rows do
                overlay.rows[index]:Hide()
            end
        end
        overlay.RefreshRows = RefreshRows

        overlay:SetScript("OnMouseDown", function(self, button)
            if button == "RightButton" then
                FinishPickCDM(nil)
            end
        end)

        -- Escape to cancel
        overlay:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:SetPropagateKeyboardInput(false)
                FinishPickCDM(nil)
            else
                self:SetPropagateKeyboardInput(true)
            end
        end)

        pickCDMOverlay = overlay
    end

    local isAvailable, failureReason = C_CooldownViewer.IsCooldownViewerAvailable()
    if not isAvailable then
        local reasonText = IsAccessibleString(failureReason) and failureReason or "Unknown reason"
        CooldownCompanion:Print("Cooldown Manager unavailable: " .. reasonText)
        if pickCDMCallback then
            local cb = pickCDMCallback
            pickCDMCallback = nil
            cb(nil)
        end
        return
    end

    pickCDMOverlay.entries = BuildCDMAuraPickerEntries()
    if #pickCDMOverlay.entries == 0 then
        CooldownCompanion:Print("No Tracked Buff/Bar auras found in the Cooldown Manager.")
        if pickCDMCallback then
            local cb = pickCDMCallback
            pickCDMCallback = nil
            cb(nil)
        end
        return
    end

    -- Hide config panel, show overlay
    if CS.configFrame and IsShownSafe(CS.configFrame.frame) then
        CS.configFrame.frame:Hide()
    end
    CooldownCompanion._cdmPickMode = true
    if pickCDMOverlay.ApplyPanelBackdrop then
        pickCDMOverlay.ApplyPanelBackdrop()
    end
    pickCDMOverlay.instructions:SetText(pickCDMOverlay.defaultInstructionsText)
    pickCDMOverlay.instructions:SetTextColor(1, 1, 1, 0.9)
    if pickCDMOverlay.RefreshRows then
        pickCDMOverlay:Show()
        if pickCDMOverlay.listScroll then
            pickCDMOverlay.listScroll:SetVerticalScroll(0)
        end
        pickCDMOverlay.RefreshRows()
        C_Timer.After(0, function()
            if pickCDMOverlay and pickCDMOverlay:IsShown() and pickCDMOverlay.RefreshRows then
                pickCDMOverlay.RefreshRows()
            end
        end)
    else
        pickCDMOverlay:Show()
    end
end

------------------------------------------------------------------------
-- Aura texture picker
------------------------------------------------------------------------

local function FinishPickAuraTexture(selection)
    if pickAuraTextureOverlay then
        pickAuraTextureOverlay:Hide()
    end
    CooldownCompanion:ClearAllAuraTexturePickerPreviews()
    local cb = pickAuraTextureCallback
    pickAuraTextureCallback = nil
    if cb then
        cb(selection)
    end
end

local function CancelPickAuraTexture()
    if pickAuraTextureOverlay and pickAuraTextureOverlay:IsShown() then
        FinishPickAuraTexture(nil)
        return
    end
    CooldownCompanion:ClearAllAuraTexturePickerPreviews()
    pickAuraTextureCallback = nil
end

local function ApplyAuraTextureRowIcon(icon, entry)
    if not icon then
        return
    end

    icon:SetTexCoord(0, 1, 0, 1)
    icon:SetBlendMode("ADD")
    icon:SetVertexColor(1, 1, 1, 1)

    local resolvedSourceType, resolvedSourceValue = CooldownCompanion:ResolveAuraTextureAsset(
        entry.sourceType,
        entry.sourceValue
    )

    if resolvedSourceType == "atlas" and type(resolvedSourceValue) == "string" and C_Texture.GetAtlasExists(resolvedSourceValue) then
        icon:SetAtlas(resolvedSourceValue, false)
        return
    end

    if resolvedSourceType == "file" and resolvedSourceValue ~= nil then
        icon:SetTexture(resolvedSourceValue)
        local color = entry.color
        if type(color) == "table" then
            icon:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
        end
        return
    end

    icon:SetTexture(134400)
end

local function StartPickAuraTexture(opts)
    opts = type(opts) == "table" and opts or {}
    pickAuraTextureCallback = opts.callback
    local initialSelection = type(opts.initialSelection) == "table" and opts.initialSelection or nil

    if not pickAuraTextureOverlay then
        local overlay = CreateFrame("Frame", "CooldownCompanionPickAuraTextureOverlay", UIParent)
        overlay:SetFrameStrata("FULLSCREEN_DIALOG")
        overlay:SetFrameLevel(105)
        overlay:SetAllPoints(UIParent)
        overlay:EnableMouse(true)
        overlay:EnableKeyboard(true)

        local bg = overlay:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.18)
        overlay.bg = bg

        local panel = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
        panel:SetPoint("CENTER", overlay, "CENTER", 260, -5)
        panel:SetSize(980, 640)
        overlay.panel = panel

        local function ApplyPanelBackdrop()
            local source = CS.configFrame and CS.configFrame.frame
            local copied = false
            if source and source.GetBackdrop and panel.SetBackdrop then
                local backdrop = source:GetBackdrop()
                if backdrop then
                    local copy = {}
                    for key, value in pairs(backdrop) do
                        if type(value) == "table" then
                            copy[key] = {}
                            for subKey, subValue in pairs(value) do
                                copy[key][subKey] = subValue
                            end
                        else
                            copy[key] = value
                        end
                    end
                    panel:SetBackdrop(copy)
                    copied = true
                    if source.GetBackdropColor and panel.SetBackdropColor then
                        panel:SetBackdropColor(source:GetBackdropColor())
                    end
                    if source.GetBackdropBorderColor and panel.SetBackdropBorderColor then
                        panel:SetBackdropBorderColor(source:GetBackdropBorderColor())
                    end
                end
            end

            if not copied then
                panel:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8x8",
                    edgeFile = "Interface\\Buttons\\WHITE8x8",
                    edgeSize = 1,
                })
                panel:SetBackdropColor(0.05, 0.08, 0.10, 0.96)
                panel:SetBackdropBorderColor(0.2, 0.45, 0.55, 0.9)
            end
        end
        ApplyPanelBackdrop()
        overlay.ApplyPanelBackdrop = ApplyPanelBackdrop

        local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -12)
        title:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -40, -12)
        title:SetJustifyH("CENTER")
        title:SetText("Browse Aura Textures")
        overlay.title = title

        local closeBtn = CreateFrame("Button", nil, panel)
        closeBtn:SetSize(19, 19)
        closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8)
        local closeIcon = closeBtn:CreateTexture(nil, "ARTWORK")
        closeIcon:SetAtlas("common-icon-redx", false)
        closeIcon:SetAllPoints()
        closeBtn:SetHighlightAtlas("common-icon-redx")
        closeBtn:GetHighlightTexture():SetAlpha(0.3)
        closeBtn:SetScript("OnClick", function()
            FinishPickAuraTexture(nil)
        end)
        panel.closeBtn = closeBtn

        local topSeparator = panel:CreateTexture(nil, "BORDER")
        topSeparator:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -34)
        topSeparator:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -34)
        topSeparator:SetHeight(1)
        topSeparator:SetColorTexture(0.25, 0.55, 0.65, 0.9)

        local searchLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        searchLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -52)
        searchLabel:SetText("Search")

        local searchBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
        searchBox:SetAutoFocus(false)
        searchBox:SetSize(360, 26)
        searchBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -72)
        searchBox:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
        end)
        overlay.searchBox = searchBox

        local filterLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        filterLabel:SetPoint("TOPLEFT", searchBox, "TOPRIGHT", 24, 12)
        filterLabel:SetText("Category")

        local filterDrop = CreateFrame("Frame", nil, panel, "UIDropDownMenuTemplate")
        filterDrop:SetPoint("TOPLEFT", searchBox, "TOPRIGHT", 8, 10)
        UIDropDownMenu_SetWidth(filterDrop, 180)
        overlay.filterDrop = filterDrop

        local statusLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        statusLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -106)
        statusLabel:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -18, -106)
        statusLabel:SetJustifyH("LEFT")
        statusLabel:SetText("")
        overlay.statusLabel = statusLabel

        local listScroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
        listScroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -126)
        listScroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -32, 62)
        overlay.listScroll = listScroll

        local listContent = CreateFrame("Frame", nil, listScroll)
        listContent:SetSize(1, 1)
        listScroll:SetScrollChild(listContent)
        overlay.listContent = listContent
        overlay.rows = {}
        overlay.rowHeight = 44
        overlay.rowIconSize = 28
        overlay.filterValue = AURA_TEXTURE_FILTER_SYMBOLS
        overlay.searchText = ""
        overlay.selectedKey = nil
        overlay.selectedEntry = nil

        local selectionLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        selectionLabel:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 18, 20)
        selectionLabel:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -250, 20)
        selectionLabel:SetJustifyH("LEFT")
        selectionLabel:SetText("Select a texture to preview it on the chosen aura button.")
        overlay.selectionLabel = selectionLabel

        local confirmBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        confirmBtn:SetSize(120, 24)
        confirmBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -18, 18)
        confirmBtn:SetText("Use Texture")
        confirmBtn:SetEnabled(false)
        panel.confirmBtn = confirmBtn
        overlay.confirmBtn = confirmBtn

        local cancelBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        cancelBtn:SetSize(90, 24)
        cancelBtn:SetPoint("RIGHT", confirmBtn, "LEFT", -8, 0)
        cancelBtn:SetText("Cancel")
        cancelBtn:SetScript("OnClick", function()
            FinishPickAuraTexture(nil)
        end)

        local function SetSelectedEntry(entry)
            overlay.selectedEntry = entry
            overlay.selectedKey = entry and entry.key or nil
            confirmBtn:SetEnabled(entry ~= nil)

            if entry then
                overlay.selectionLabel:SetText((entry.label or "Texture") .. "  |  " .. (entry.subtitle or entry.category or ""))
                if CS.selectedGroup and CS.selectedButton then
                    CooldownCompanion:SetAuraTexturePickerPreview(
                        CS.selectedGroup,
                        CS.selectedButton,
                        CooldownCompanion:CreateAuraTextureSelection(entry)
                    )
                end
            else
                overlay.selectionLabel:SetText("Select a texture to preview it on the chosen aura button.")
                CooldownCompanion:ClearAllAuraTexturePickerPreviews()
            end

            if overlay.RefreshRows then
                overlay.RefreshRows()
            end
        end

        confirmBtn:SetScript("OnClick", function()
            if overlay.selectedEntry then
                FinishPickAuraTexture(CooldownCompanion:CreateAuraTextureSelection(overlay.selectedEntry))
            end
        end)

        local function AcquireRow(index)
            local row = overlay.rows[index]
            if row then
                return row
            end

            row = CreateFrame("Button", nil, listContent, "BackdropTemplate")
            row:SetHeight((overlay.rowHeight or 44) - 2)
            row:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 8,
                insets = { left = 1, right = 1, top = 1, bottom = 1 },
            })
            row:SetBackdropColor(0, 0, 0, 0)
            row:SetBackdropBorderColor(0, 0, 0, 0)

            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetPoint("LEFT", row, "LEFT", 10, 0)
            icon:SetSize(overlay.rowIconSize or 28, overlay.rowIconSize or 28)
            row.icon = icon

            local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            text:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
            text:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -2)
            text:SetJustifyH("LEFT")
            row.text = text

            local subText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            subText:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -3)
            subText:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -18)
            subText:SetJustifyH("LEFT")
            subText:SetTextColor(0.72, 0.82, 0.92)
            row.subText = subText

            row:SetScript("OnEnter", function(self)
                if overlay.selectedKey == self.entryKey then
                    return
                end
                self:SetBackdropColor(0.12, 0.18, 0.28, 0.45)
                self:SetBackdropBorderColor(0.35, 0.60, 0.85, 0.65)
            end)
            row:SetScript("OnLeave", function(self)
                if overlay.selectedKey == self.entryKey then
                    return
                end
                self:SetBackdropColor(0, 0, 0, 0)
                self:SetBackdropBorderColor(0, 0, 0, 0)
            end)
            row:SetScript("OnClick", function(self)
                SetSelectedEntry(self.entry)
            end)

            overlay.rows[index] = row
            return row
        end

        local function RefreshRows()
            local entries = overlay.entries or {}
            local rowHeight = overlay.rowHeight or 44
            local listWidth = listScroll:GetWidth()
            if not listWidth or listWidth <= 0 then
                listWidth = 930
            end
            listContent:SetSize(listWidth, math_max(1, #entries * rowHeight))

            for index, entry in ipairs(entries) do
                local row = AcquireRow(index)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", listContent, "TOPLEFT", 0, -((index - 1) * rowHeight))
                row:SetPoint("TOPRIGHT", listContent, "TOPRIGHT", 0, -((index - 1) * rowHeight))
                row.entry = entry
                row.entryKey = entry.key
                row.text:SetText(entry.label or "Texture")
                row.subText:SetText(entry.subtitle or entry.category or "")
                ApplyAuraTextureRowIcon(row.icon, entry)

                if overlay.selectedKey == entry.key then
                    row:SetBackdropColor(0.18, 0.26, 0.38, 0.65)
                    row:SetBackdropBorderColor(0.45, 0.78, 1, 0.85)
                else
                    row:SetBackdropColor(0, 0, 0, 0)
                    row:SetBackdropBorderColor(0, 0, 0, 0)
                end

                row:Show()
            end

            for index = #entries + 1, #overlay.rows do
                overlay.rows[index]:Hide()
            end
        end
        overlay.RefreshRows = RefreshRows

        local function RefreshEntries()
            overlay.searchText = searchBox:GetText() or ""
            overlay.entries = CooldownCompanion:GetAuraTexturePickerEntries(overlay.searchText, overlay.filterValue)

            if #overlay.entries == 0 then
                overlay.statusLabel:SetText("No textures matched the current search.")
            else
                overlay.statusLabel:SetText("Showing " .. tostring(#overlay.entries) .. " textures.")
            end

            local keepSelected = false
            if overlay.selectedKey then
                for _, entry in ipairs(overlay.entries) do
                    if entry.key == overlay.selectedKey then
                        keepSelected = true
                        break
                    end
                end
            end
            if not keepSelected then
                SetSelectedEntry(nil)
            end

            RefreshRows()
        end
        overlay.RefreshEntries = RefreshEntries

        searchBox:SetScript("OnTextChanged", function()
            RefreshEntries()
        end)

        local filterList, filterOrder = CooldownCompanion:GetAuraTexturePickerFilters()
        overlay.filterList = filterList
        overlay.filterOrder = filterOrder
        UIDropDownMenu_Initialize(filterDrop, function(_, level)
            if level ~= 1 then
                return
            end
            for _, value in ipairs(filterOrder) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = filterList[value]
                info.checked = overlay.filterValue == value
                info.func = function()
                    overlay.filterValue = value
                    UIDropDownMenu_SetText(filterDrop, filterList[value])
                    RefreshEntries()
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
        UIDropDownMenu_SetText(filterDrop, filterList[AURA_TEXTURE_FILTER_SYMBOLS])

        overlay:SetScript("OnMouseDown", function(self, button)
            if button == "RightButton" then
                FinishPickAuraTexture(nil)
            end
        end)
        overlay:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:SetPropagateKeyboardInput(false)
                FinishPickAuraTexture(nil)
            else
                self:SetPropagateKeyboardInput(true)
            end
        end)

        pickAuraTextureOverlay = overlay
    end

    pickAuraTextureOverlay.selectedKey = nil
    pickAuraTextureOverlay.selectedEntry = nil
    pickAuraTextureOverlay.filterValue = AURA_TEXTURE_FILTER_SYMBOLS
    pickAuraTextureOverlay.entries = {}
    pickAuraTextureOverlay.selectionLabel:SetText("Select a texture to preview it on the chosen aura button.")
    UIDropDownMenu_SetText(pickAuraTextureOverlay.filterDrop, pickAuraTextureOverlay.filterList[AURA_TEXTURE_FILTER_SYMBOLS])
    pickAuraTextureOverlay.confirmBtn:SetEnabled(false)
    pickAuraTextureOverlay.searchBox:SetText("")
    if pickAuraTextureOverlay.ApplyPanelBackdrop then
        pickAuraTextureOverlay.ApplyPanelBackdrop()
    end
    pickAuraTextureOverlay:Show()
    if pickAuraTextureOverlay.listScroll then
        pickAuraTextureOverlay.listScroll:SetVerticalScroll(0)
    end
    if pickAuraTextureOverlay.RefreshEntries then
        pickAuraTextureOverlay.RefreshEntries()
    end

    if initialSelection and initialSelection.sourceType then
        pickAuraTextureOverlay.filterValue = CooldownCompanion:GetAuraTexturePickerFilterForSelection(initialSelection)
        UIDropDownMenu_SetText(pickAuraTextureOverlay.filterDrop, pickAuraTextureOverlay.filterList[pickAuraTextureOverlay.filterValue])
        if initialSelection.label and initialSelection.label ~= "" then
            pickAuraTextureOverlay.searchBox:SetText(initialSelection.label)
        elseif type(initialSelection.sourceValue) == "string" and initialSelection.sourceValue ~= "" then
            pickAuraTextureOverlay.searchBox:SetText(initialSelection.sourceValue)
        end
    end

    if initialSelection and initialSelection.sourceType and initialSelection.sourceValue ~= nil then
        local entry = CooldownCompanion.FindAuraTexturePickerEntry
            and CooldownCompanion:FindAuraTexturePickerEntry(pickAuraTextureOverlay.entries, initialSelection)
            or nil
        if entry then
            pickAuraTextureOverlay.selectedKey = entry.key
            pickAuraTextureOverlay.selectedEntry = entry
            pickAuraTextureOverlay.confirmBtn:SetEnabled(true)
            pickAuraTextureOverlay.selectionLabel:SetText((entry.label or "Texture") .. "  |  " .. (entry.subtitle or entry.category or ""))
            if CS.selectedGroup and CS.selectedButton then
                CooldownCompanion:SetAuraTexturePickerPreview(
                    CS.selectedGroup,
                    CS.selectedButton,
                    CooldownCompanion:CreateAuraTextureSelection(entry)
                )
            end
            if pickAuraTextureOverlay.RefreshRows then
                pickAuraTextureOverlay.RefreshRows()
            end
        end
    end
end

CS.StartPickFrame = StartPickFrame
CS.StartPickCDM = StartPickCDM

------------------------------------------------------------------------
-- Helper: Check if a spell is in CDM TrackedBuff or TrackedBar categories
------------------------------------------------------------------------
local function IsSpellInCDMBuffBar(spellId)
    for _, cat in ipairs({Enum.CooldownViewerCategory.TrackedBuff, Enum.CooldownViewerCategory.TrackedBar}) do
        local ids = C_CooldownViewer.GetCooldownViewerCategorySet(cat, true)
        if ids then
            for _, cdID in ipairs(ids) do
                local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                if info then
                    if info.spellID == spellId or info.overrideSpellID == spellId
                       or info.overrideTooltipSpellID == spellId then
                        return true
                    end
                end
            end
        end
    end
    return false
end

------------------------------------------------------------------------
-- Helper: Check if a spell is in CDM Essential or Utility categories
------------------------------------------------------------------------
local IsSpellInCDMCooldown = ST.IsSpellInCDMCooldown

------------------------------------------------------------------------
-- Helper: Detect passive or proc spells (zero-cooldown CDM-tracked spells)
------------------------------------------------------------------------
local IsActiveSpellBookSpell = ST.IsActiveSpellBookSpell

local function IsPassiveOrProc(spellId)
    if C_Spell.IsSpellPassive(spellId) then return true end
    -- Active spellbook spells (e.g. Death Strike) can have base cooldown 0 and
    -- still be normal spell entries; don't auto-classify them as aura-only.
    if IsActiveSpellBookSpell(spellId) then return false end
    if C_Spell.GetSpellCharges(spellId) then return false end
    local baseCooldown = GetSpellBaseCooldown(spellId)
    if (not baseCooldown or baseCooldown == 0) and IsSpellInCDMBuffBar(spellId) then
        return true
    end
    return false
end

local NEVER_TRACKABLE_SPELL_IDS = {
    -- Add explicit spellIDs here when confirmed (for example, Mobile Banking).
}

local NEVER_TRACKABLE_SPELL_SET = {}
for _, spellID in ipairs(NEVER_TRACKABLE_SPELL_IDS) do
    NEVER_TRACKABLE_SPELL_SET[spellID] = true
end

local function IsNeverTrackableSpell(spellId)
    local id = tonumber(spellId)
    if not id or id <= 0 then return false end
    if NEVER_TRACKABLE_SPELL_SET[id] then return true end
    if C_Spell.IsAutoAttackSpell(id) then return true end
    if C_Spell.IsRangedAutoAttackSpell(id) then return true end
    return false
end

local function ShouldSuppressSpellbookEntry(spellId, skillLineIndex, isAura)
    if IsNeverTrackableSpell(spellId) then
        return true
    end
    if isAura and skillLineIndex == Enum.SpellBookSkillLineIndex.General then
        return true
    end
    return false
end

------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
ST._IsSpellInCDMBuffBar = IsSpellInCDMBuffBar
ST._IsSpellInCDMCooldown = IsSpellInCDMCooldown
ST._IsPassiveOrProc = IsPassiveOrProc
ST._IsNeverTrackableSpell = IsNeverTrackableSpell
ST._ShouldSuppressSpellbookEntry = ShouldSuppressSpellbookEntry
