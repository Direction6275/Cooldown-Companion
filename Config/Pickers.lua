--[[
    CooldownCompanion - Config/Pickers
    Frame picker + CDM picker modes.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local CDM_VIEWER_NAMES = ST._CDM_VIEWER_NAMES

-- File-local state
local pickFrameOverlay = nil
local pickFrameCallback = nil
local pickFrameSourceGroupId = nil
local pickCDMOverlay = nil
local pickCDMCallback = nil

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
    elseif name:find("^CooldownCompanion") then
        return true
    end
    if name == "WorldFrame" then return true end
    -- Exclude the config panel itself (AceGUI frames)
    if CS.configFrame and CS.configFrame.frame and CS.configFrame.frame:GetName() == name then return true end
    return false
end

------------------------------------------------------------------------
-- Helper: Check if a frame has visible content (not an empty container)
------------------------------------------------------------------------
local function HasVisibleContent(frame)
    if frame:GetObjectType() ~= "Frame" then return true end
    if frame:IsMouseEnabled() then return true end
    for _, region in pairs({ frame:GetRegions() }) do
        if region:IsShown() then return true end
    end
    -- Container frames with shown children also count as having visible content
    for _, child in pairs({ frame:GetChildren() }) do
        if child:IsShown() then return true end
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
        local visible = not (child.IsForbidden and child:IsForbidden()) and child:IsVisible()
        if visible then
            local name = child:GetName()
            if name and name ~= "" and not IsAddonFrame(name) then
                local left, bottom, width, height = child:GetRect()
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
                resolvedFrame, name = ResolveNamedFrame(focus)
            end

            -- If resolved to a blocked addon child, walk up for an allowed group frame
            if name and IsAddonFrame(name) then
                local parent = resolvedFrame:GetParent()
                while parent do
                    local pname = parent:GetName()
                    if pname and pname ~= "" and not IsAddonFrame(pname) then
                        resolvedFrame, name = parent, pname
                        break
                    end
                    parent = parent:GetParent()
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
            local left, bottom, width, height = resolvedFrame:GetRect()
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
    if CS.configFrame and CS.configFrame.frame:IsShown() then
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
        instructions:SetText("Click a buff/debuff in the Cooldown Manager  |  Right-click or Escape to cancel")
        instructions:SetTextColor(1, 1, 1, 0.9)
        overlay.instructions = instructions

        -- Cursor-following label showing spell name/ID
        local label = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        label:SetTextColor(0.2, 1, 0.2, 1)
        overlay.label = label

        -- Highlight frame (colored border that outlines hovered CDM child)
        local highlight = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
        highlight:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
        })
        highlight:SetBackdropBorderColor(0, 1, 0, 0.9)
        highlight:Hide()
        overlay.highlight = highlight

        -- OnUpdate: detect CDM child under cursor
        overlay:SetScript("OnUpdate", function(self, dt)
            local cx, cy = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale

            local bestChild, bestArea, bestSpellID, bestName, bestIsAuraViewer

            for _, viewerName in ipairs(CDM_VIEWER_NAMES) do
                local viewer = _G[viewerName]
                if viewer then
                    local isAuraViewer = viewerName == "BuffIconCooldownViewer" or viewerName == "BuffBarCooldownViewer"
                    for _, child in pairs({viewer:GetChildren()}) do
                        if child.cooldownInfo and child:IsVisible() then
                            local left, bottom, width, height = child:GetRect()
                            if left and width and width > 0 and height > 0 then
                                if cx >= left and cx <= left + width and cy >= bottom and cy <= bottom + height then
                                    local area = width * height
                                    if not bestArea or area < bestArea then
                                        local info = child.cooldownInfo
                                        local sid = info.overrideSpellID or info.spellID
                                        if sid then
                                            bestChild = child
                                            bestArea = area
                                            bestSpellID = sid
                                            bestIsAuraViewer = isAuraViewer
                                            local spellInfo = C_Spell.GetSpellInfo(sid)
                                            bestName = spellInfo and spellInfo.name or tostring(sid)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end

            -- Also scan the CDM Settings panel (CooldownViewerSettings) if open
            local settingsPanel = CooldownViewerSettings
            if settingsPanel and settingsPanel:IsVisible() and settingsPanel.categoryPool then
                for categoryDisplay in settingsPanel.categoryPool:EnumerateActive() do
                    if categoryDisplay.itemPool then
                        local catObj = categoryDisplay:GetCategoryObject()
                        local isAuraCat = catObj and (catObj:GetCategory() == Enum.CooldownViewerCategory.TrackedBuff or catObj:GetCategory() == Enum.CooldownViewerCategory.TrackedBar)
                        for item in categoryDisplay.itemPool:EnumerateActive() do
                            if item:IsVisible() and not item:IsEmptyCategory() then
                                local left, bottom, width, height = item:GetRect()
                                if left and width and width > 0 and height > 0 then
                                    if cx >= left and cx <= left + width and cy >= bottom and cy <= bottom + height then
                                        local area = width * height
                                        if not bestArea or area < bestArea then
                                            local info = item:GetCooldownInfo()
                                            local sid = info and (info.overrideSpellID or info.spellID)
                                            if sid then
                                                bestChild = item
                                                bestArea = area
                                                bestSpellID = sid
                                                bestIsAuraViewer = isAuraCat
                                                local spellInfo = C_Spell.GetSpellInfo(sid)
                                                bestName = spellInfo and spellInfo.name or tostring(sid)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end

            self.currentSpellID = bestSpellID

            if not bestChild then
                self.label:SetText("")
                self.highlight:Hide()
                return
            end

            -- Color: green for BuffIcon/BuffBar (aura-capable), red for Essential/Utility (not a buff/debuff)
            if bestIsAuraViewer then
                self.label:SetTextColor(0.2, 1, 0.2, 1)
            else
                self.label:SetTextColor(1, 0.3, 0.3, 1)
            end

            self.label:ClearAllPoints()
            self.label:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx + 20, cy + 10)
            local suffix = bestIsAuraViewer and "TRACKABLE AURA" or "NOT AN AURA"
            self.label:SetText(bestName .. "  |  " .. bestSpellID .. "  |  " .. suffix)

            local left, bottom, width, height = bestChild:GetRect()
            if left and width and width > 0 and height > 0 then
                self.highlight:ClearAllPoints()
                self.highlight:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
                self.highlight:SetSize(width, height)
                if bestIsAuraViewer then
                    self.highlight:SetBackdropBorderColor(0, 1, 0, 0.9)
                else
                    self.highlight:SetBackdropBorderColor(1, 0.3, 0.3, 0.9)
                end
                self.highlight:Show()
            else
                self.highlight:Hide()
            end
        end)

        -- Detect clicks via GLOBAL_MOUSE_DOWN
        overlay:RegisterEvent("GLOBAL_MOUSE_DOWN")
        overlay:SetScript("OnEvent", function(self, event, button)
            if event ~= "GLOBAL_MOUSE_DOWN" then return end
            if button == "LeftButton" then
                FinishPickCDM(self.currentSpellID)
            elseif button == "RightButton" then
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

        overlay:SetScript("OnHide", function(self)
            self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        end)

        overlay:SetScript("OnShow", function(self)
            self:RegisterEvent("GLOBAL_MOUSE_DOWN")
        end)

        pickCDMOverlay = overlay
    end

    -- Hide config panel, show overlay
    if CS.configFrame and CS.configFrame.frame:IsShown() then
        CS.configFrame.frame:Hide()
    end
    -- Temporarily show CDM if hidden
    if CooldownCompanion.db.profile.cdmHidden then
        CooldownCompanion._cdmPickMode = true
        CooldownCompanion:ApplyCdmAlpha()
    end
    pickCDMOverlay.currentSpellID = nil
    pickCDMOverlay.label:SetText("")
    pickCDMOverlay.highlight:Hide()
    pickCDMOverlay:Show()
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
local function IsSpellInCDMCooldown(spellId)
    for _, cat in ipairs({Enum.CooldownViewerCategory.Essential, Enum.CooldownViewerCategory.Utility}) do
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
-- Helper: Detect passive or proc spells (zero-cooldown CDM-tracked spells)
------------------------------------------------------------------------
local function IsPassiveOrProc(spellId)
    if C_Spell.IsSpellPassive(spellId) then return true end
    if C_Spell.GetSpellCharges(spellId) then return false end
    local baseCooldown = GetSpellBaseCooldown(spellId)
    if (not baseCooldown or baseCooldown == 0) and IsSpellInCDMBuffBar(spellId) then
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
