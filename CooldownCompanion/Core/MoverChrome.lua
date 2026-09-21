-- Shared mover controls. Owners supply actions and place the returned widgets;
-- geometry, saved settings, selection, and native display frames stay with them.
local _, ST = ...
local Chrome = {}
ST.MoverChrome = Chrome

function Chrome.CreateLabel(parent)
    local label = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    label:SetHeight(15)
    label:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    label:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    ST.CreatePixelBorders(label)
    label.text = label:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label.text:SetPoint("CENTER")
    label.text:SetTextColor(1, 1, 1, 1)
    return label
end

function Chrome.CreateHeader(parent, title, onLock, getDescriptor)
    local header = Chrome.CreateLabel(parent)
    header.text:SetText(title)
    header.lockButton = ST.CreateMoverLockBadge(header, 12, onLock)
    header.lockButton:SetPoint("RIGHT", header, "RIGHT", -2, 0)
    header.menuButton = ST.CreateMoverQuickMenuButton(header, 12, getDescriptor, header)
    header.menuButton:SetPoint("RIGHT", header.lockButton, "LEFT", -2, 0)
    local inset = header.lockButton:GetWidth() + header.menuButton:GetWidth() + 8
    header.text:ClearAllPoints()
    header.text:SetPoint("LEFT", header, "LEFT", inset, 0)
    header.text:SetPoint("RIGHT", header, "RIGHT", -inset, 0)
    header.text:SetJustifyH("CENTER")
    return header
end

local directions = {
    { atlas = "common-dropdown-icon-back", rotation = -math.pi / 2, anchor = "BOTTOM", dx = 0, dy = 1, ox = 0, oy = 2 },
    { atlas = "common-dropdown-icon-next", rotation = -math.pi / 2, anchor = "TOP", dx = 0, dy = -1, ox = 0, oy = -2 },
    { atlas = "common-dropdown-icon-back", rotation = 0, anchor = "RIGHT", dx = -1, dy = 0, ox = -2, oy = 0 },
    { atlas = "common-dropdown-icon-next", rotation = 0, anchor = "LEFT", dx = 1, dy = 0, ox = 2, oy = 0 },
}

function Chrome.CreateNudger(parent, buttonSize, nudge, commit)
    local addon = ST.Addon
    local nudger = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    nudger.buttons = {}
    nudger:SetSize(buttonSize * 2 + 2, buttonSize * 2 + 2)
    nudger:SetPoint("BOTTOM", parent, "TOP", 0, 2)
    nudger:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    nudger:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    ST.CreatePixelBorders(nudger)
    nudger:SetScript("OnEnter", function(self)
        addon:BeginMoverChromeHoverFade(self)
    end)
    nudger:SetScript("OnLeave", function(self)
        if not self:IsMouseOver() then addon:EndMoverChromeFade(self) end
    end)
    nudger:SetScript("OnHide", function(self)
        addon:EndMoverChromeFade(self)
    end)
    for _, dir in ipairs(directions) do
        local button = CreateFrame("Button", nil, nudger)
        nudger.buttons[#nudger.buttons + 1] = button
        button:SetSize(buttonSize, buttonSize)
        button:SetPoint(dir.anchor, nudger, "CENTER", dir.ox, dir.oy)
        button:EnableMouse(true)
        local arrow = button:CreateTexture(nil, "OVERLAY")
        arrow:SetAtlas(dir.atlas, false)
        arrow:SetAllPoints()
        arrow:SetRotation(dir.rotation)
        arrow:SetVertexColor(0.8, 0.8, 0.8, 0.8)
        button.arrow = arrow
        button:SetScript("OnEnter", function()
            arrow:SetVertexColor(1, 1, 1, 1)
            addon:BeginMoverChromeHoverFade(nudger)
        end)
        button:SetScript("OnLeave", function()
            if nudger.RefreshSectionTint then
                nudger.RefreshSectionTint()
            else
                arrow:SetVertexColor(0.8, 0.8, 0.8, 0.8)
            end
            commit()
            if not nudger:IsMouseOver() then addon:EndMoverChromeFade(nudger) end
        end)
        button:SetScript("OnMouseDown", function()
            nudge(dir.dx, dir.dy)
            addon:VerifyMoverChromeHoverFade(nudger)
        end)
        button:SetScript("OnMouseUp", commit)
    end
    return nudger
end

-- Only the independent bars share this complete presentation policy. Panel
-- selection and container wrappers keep their own reveal and input rules.
function Chrome.UpdateIndependent(frame, focusId, unlocked)
    local addon = ST.Addon
    local chromeShown = unlocked and not addon:IsContainerArrangeChromeHidden(focusId) or false
    local revealed = not addon._arrangeModeActive
        or addon._arrangeFocusContainerId == focusId
        or frame._arrangeChromeHover == true
    local toolsShown = chromeShown and revealed or false
    frame:SetMovable(unlocked or false)
    local header = frame._dragHandle
    if header then
        header:SetShown(chromeShown)
        header:EnableMouse(chromeShown)
        if chromeShown then header:RegisterForDrag("LeftButton") else header:RegisterForDrag() end
    end
    local nudger = frame._nudger
    if nudger then
        nudger:SetShown(toolsShown)
        nudger:EnableMouse(toolsShown)
        for _, button in ipairs(nudger.buttons) do button:EnableMouse(toolsShown) end
    end
    if frame._coordLabel then frame._coordLabel:SetShown(toolsShown) end
    if frame._sizeLabel then
        frame._sizeLabel:SetShown(toolsShown)
        if toolsShown then frame._sizeLabel.UpdateText() end
    end
    if frame._resizeGrip then frame._resizeGrip:SetShown(toolsShown) end
    addon:ApplyMoverChromeFadeToFrames(header, frame._coordLabel, nudger, frame._resizeGrip, frame._sizeLabel)
end
