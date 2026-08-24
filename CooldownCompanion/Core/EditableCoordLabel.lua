--[[
    CooldownCompanion - Core/EditableCoordLabel
    Arrange-mode editable numeric label, shared by panel movers.
]]

local ADDON_NAME, ST = ...

local tonumber = tonumber

local RoundToTenths = ST.RoundToTenths

local function CancelCoordinateEdit(coordLabel)
    if not (coordLabel and coordLabel.xEdit) then
        return
    end

    coordLabel._editGeneration = (coordLabel._editGeneration or 0) + 1
    coordLabel._editing = nil
    coordLabel.xEdit:ClearFocus()
    coordLabel.xLabel:Hide()
    coordLabel.xEdit:Hide()
    if coordLabel.yEdit then
        coordLabel.yEdit:ClearFocus()
        coordLabel.yLabel:Hide()
        coordLabel.yEdit:Hide()
    end
    coordLabel.text:Show()
end
ST.CancelCoordinateEdit = CancelCoordinateEdit

function ST.ConfigureEditableCoordLabel(coordLabel, labelA, labelB, singleField)
    if not (coordLabel and coordLabel.xLabel and coordLabel.xEdit) then
        return
    end

    labelA = labelA or "x:"
    labelB = labelB or "y:"
    singleField = singleField == true
    if coordLabel._singleField == singleField
        and coordLabel._labelA == labelA
        and (singleField or coordLabel._labelB == labelB) then
        return
    end

    coordLabel._singleField = singleField
    coordLabel._labelA = labelA
    coordLabel._labelB = labelB
    coordLabel.xLabel:SetText(labelA)
    coordLabel.xEdit:ClearAllPoints()
    coordLabel.xEdit:SetPoint("LEFT", coordLabel.xLabel, "RIGHT", 1, 0)
    if coordLabel._singleField then
        coordLabel.xEdit:SetPoint("RIGHT", coordLabel, "RIGHT", -2, 0)
    else
        coordLabel.xEdit:SetPoint("RIGHT", coordLabel, "CENTER", -1, 0)
        if coordLabel.yLabel then
            coordLabel.yLabel:SetText(labelB)
        end
    end
end

function ST.CreateEditableCoordLabel(coordLabel, getCoordinates, applyCoordinates, isDragging, options)
    options = options or {}
    local singleField = options.singleField == true
    local xLabel = coordLabel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    xLabel:SetText(options.labelA or "x:")
    xLabel:SetTextColor(1, 1, 1, 0.8)
    xLabel:SetPoint("LEFT", coordLabel, "LEFT", 2, 0)
    xLabel:Hide()

    local xEdit = CreateFrame("EditBox", nil, coordLabel)
    xEdit:SetAutoFocus(false)
    xEdit:SetFontObject(GameFontNormalSmall)
    xEdit:SetTextColor(1, 1, 1, 1)
    xEdit:SetJustifyH("CENTER")
    xEdit:SetPoint("LEFT", xLabel, "RIGHT", 1, 0)
    if singleField then
        xEdit:SetPoint("RIGHT", coordLabel, "RIGHT", -2, 0)
    else
        xEdit:SetPoint("RIGHT", coordLabel, "CENTER", -1, 0)
    end
    xEdit:SetHeight(13)
    xEdit:Hide()

    local yLabel
    local yEdit
    if not singleField then
        yLabel = coordLabel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        yLabel:SetText(options.labelB or "y:")
        yLabel:SetTextColor(1, 1, 1, 0.8)
        yLabel:SetPoint("LEFT", coordLabel, "CENTER", 1, 0)
        yLabel:Hide()

        yEdit = CreateFrame("EditBox", nil, coordLabel)
        yEdit:SetAutoFocus(false)
        yEdit:SetFontObject(GameFontNormalSmall)
        yEdit:SetTextColor(1, 1, 1, 1)
        yEdit:SetJustifyH("CENTER")
        yEdit:SetPoint("LEFT", yLabel, "RIGHT", 1, 0)
        yEdit:SetPoint("RIGHT", coordLabel, "RIGHT", -2, 0)
        yEdit:SetHeight(13)
        yEdit:Hide()
    end

    coordLabel.xLabel = xLabel
    coordLabel.yLabel = yLabel
    coordLabel.xEdit = xEdit
    coordLabel.yEdit = yEdit
    coordLabel._singleField = singleField
    coordLabel._labelA = options.labelA or "x:"
    coordLabel._labelB = options.labelB or "y:"
    coordLabel:EnableMouse(true)

    local function CommitEdit()
        if not coordLabel._editing then
            return
        end

        local newX = tonumber(xEdit:GetText())
        local newY = not coordLabel._singleField and yEdit and tonumber(yEdit:GetText()) or nil
        if newX == nil or (not coordLabel._singleField and newY == nil) then
            CancelCoordinateEdit(coordLabel)
            return
        end

        newX = RoundToTenths(newX)
        local oldX, oldY = getCoordinates()
        oldX = RoundToTenths(oldX)
        if not coordLabel._singleField then
            newY = RoundToTenths(newY)
            oldY = RoundToTenths(oldY)
        end
        CancelCoordinateEdit(coordLabel)
        if coordLabel._singleField then
            if newX ~= oldX then
                applyCoordinates(newX)
            end
        elseif newX ~= oldX or newY ~= oldY then
            applyCoordinates(newX, newY)
        end
    end
    coordLabel._CommitPendingEdit = CommitEdit

    local function BeginEdit()
        if coordLabel._editing or (isDragging and isDragging()) then
            return
        end

        if coordLabel._exclusiveEditLabel and coordLabel._exclusiveEditLabel._editing then
            coordLabel._exclusiveEditLabel._CommitPendingEdit()
        end
        local x, y = getCoordinates()
        coordLabel._editGeneration = (coordLabel._editGeneration or 0) + 1
        coordLabel._editing = true
        coordLabel.text:Hide()
        xEdit:SetText(("%.1f"):format(tonumber(x) or 0))
        xLabel:Show()
        xEdit:Show()
        if not coordLabel._singleField then
            yEdit:SetText(("%.1f"):format(tonumber(y) or 0))
            yLabel:Show()
            yEdit:Show()
        end
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
                and (coordLabel._singleField or not yEdit:HasFocus()) then
                CommitEdit()
            end
        end)
    end

    xEdit:SetScript("OnEnterPressed", CommitEdit)
    xEdit:SetScript("OnEscapePressed", function() CancelCoordinateEdit(coordLabel) end)
    if yEdit then
        yEdit:SetScript("OnEnterPressed", CommitEdit)
        yEdit:SetScript("OnEscapePressed", function() CancelCoordinateEdit(coordLabel) end)
        xEdit:SetScript("OnTabPressed", function()
            if not coordLabel._singleField then
                yEdit:SetFocus()
                yEdit:HighlightText()
            end
        end)
        yEdit:SetScript("OnTabPressed", function()
            if not coordLabel._singleField then
                xEdit:SetFocus()
                xEdit:HighlightText()
            end
        end)
        yEdit:SetScript("OnEditFocusLost", HandleFocusLost)
        yEdit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    else
        xEdit:SetScript("OnTabPressed", function() end)
    end
    xEdit:SetScript("OnEditFocusLost", HandleFocusLost)
    xEdit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)

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
