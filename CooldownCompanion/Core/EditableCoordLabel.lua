--[[
    CooldownCompanion - Core/EditableCoordLabel
    Arrange-mode editable x/y coordinate label, shared by group frames,
    texture panels, resource bars, and the cast bar.
]]

local ADDON_NAME, ST = ...

local tonumber = tonumber

local RoundToTenths = ST.RoundToTenths

local function CancelCoordinateEdit(coordLabel)
    if not (coordLabel and coordLabel.xEdit and coordLabel.yEdit) then
        return
    end

    coordLabel._editGeneration = (coordLabel._editGeneration or 0) + 1
    coordLabel._editing = nil
    coordLabel.xEdit:ClearFocus()
    coordLabel.yEdit:ClearFocus()
    coordLabel.xLabel:Hide()
    coordLabel.yLabel:Hide()
    coordLabel.xEdit:Hide()
    coordLabel.yEdit:Hide()
    coordLabel.text:Show()
end
ST.CancelCoordinateEdit = CancelCoordinateEdit

function ST.CreateEditableCoordLabel(coordLabel, getCoordinates, applyCoordinates, isDragging)
    local xLabel = coordLabel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    xLabel:SetText("x:")
    xLabel:SetTextColor(1, 1, 1, 0.8)
    xLabel:SetPoint("LEFT", coordLabel, "LEFT", 2, 0)
    xLabel:Hide()

    local xEdit = CreateFrame("EditBox", nil, coordLabel)
    xEdit:SetAutoFocus(false)
    xEdit:SetFontObject(GameFontNormalSmall)
    xEdit:SetTextColor(1, 1, 1, 1)
    xEdit:SetJustifyH("CENTER")
    xEdit:SetPoint("LEFT", xLabel, "RIGHT", 1, 0)
    xEdit:SetPoint("RIGHT", coordLabel, "CENTER", -1, 0)
    xEdit:SetHeight(13)
    xEdit:Hide()

    local yLabel = coordLabel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    yLabel:SetText("y:")
    yLabel:SetTextColor(1, 1, 1, 0.8)
    yLabel:SetPoint("LEFT", coordLabel, "CENTER", 1, 0)
    yLabel:Hide()

    local yEdit = CreateFrame("EditBox", nil, coordLabel)
    yEdit:SetAutoFocus(false)
    yEdit:SetFontObject(GameFontNormalSmall)
    yEdit:SetTextColor(1, 1, 1, 1)
    yEdit:SetJustifyH("CENTER")
    yEdit:SetPoint("LEFT", yLabel, "RIGHT", 1, 0)
    yEdit:SetPoint("RIGHT", coordLabel, "RIGHT", -2, 0)
    yEdit:SetHeight(13)
    yEdit:Hide()

    coordLabel.xLabel = xLabel
    coordLabel.yLabel = yLabel
    coordLabel.xEdit = xEdit
    coordLabel.yEdit = yEdit
    coordLabel:EnableMouse(true)

    local function CommitEdit()
        if not coordLabel._editing then
            return
        end

        local newX = tonumber(xEdit:GetText())
        local newY = tonumber(yEdit:GetText())
        if newX == nil or newY == nil then
            CancelCoordinateEdit(coordLabel)
            return
        end

        newX = RoundToTenths(newX)
        newY = RoundToTenths(newY)
        local oldX, oldY = getCoordinates()
        oldX = RoundToTenths(oldX)
        oldY = RoundToTenths(oldY)
        CancelCoordinateEdit(coordLabel)
        if newX ~= oldX or newY ~= oldY then
            applyCoordinates(newX, newY)
        end
    end

    local function BeginEdit()
        if coordLabel._editing or (isDragging and isDragging()) then
            return
        end

        local x, y = getCoordinates()
        coordLabel._editGeneration = (coordLabel._editGeneration or 0) + 1
        coordLabel._editing = true
        coordLabel.text:Hide()
        xEdit:SetText(("%.1f"):format(tonumber(x) or 0))
        yEdit:SetText(("%.1f"):format(tonumber(y) or 0))
        xLabel:Show()
        yLabel:Show()
        xEdit:Show()
        yEdit:Show()
        xEdit:SetFocus()
        xEdit:HighlightText()
    end

    local function HandleFocusLost(self)
        self:HighlightText(0, 0)
        local generation = coordLabel._editGeneration
        C_Timer.After(0, function()
            if coordLabel._editing
                and coordLabel._editGeneration == generation
                and not xEdit:HasFocus()
                and not yEdit:HasFocus() then
                CommitEdit()
            end
        end)
    end

    xEdit:SetScript("OnEnterPressed", CommitEdit)
    yEdit:SetScript("OnEnterPressed", CommitEdit)
    xEdit:SetScript("OnEscapePressed", function() CancelCoordinateEdit(coordLabel) end)
    yEdit:SetScript("OnEscapePressed", function() CancelCoordinateEdit(coordLabel) end)
    xEdit:SetScript("OnTabPressed", function()
        yEdit:SetFocus()
        yEdit:HighlightText()
    end)
    yEdit:SetScript("OnTabPressed", function()
        xEdit:SetFocus()
        xEdit:HighlightText()
    end)
    xEdit:SetScript("OnEditFocusLost", HandleFocusLost)
    yEdit:SetScript("OnEditFocusLost", HandleFocusLost)
    xEdit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    yEdit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)

    coordLabel:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.3, 0.3, 0.3, 0.9)
    end)
    coordLabel:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    end)
    coordLabel:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            BeginEdit()
        end
    end)
    coordLabel:SetScript("OnHide", function(self)
        self:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
        CancelCoordinateEdit(self)
    end)
end
