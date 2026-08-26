--[[
    CooldownCompanion - Core/EditableCoordLabel
    Arrange-mode editable numeric label, shared by panel movers, plus the
    width-resize kit the independent bar movers build their resize chrome from.
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

------------------------------------------------------------------------
-- Resize kit for the independent bar movers (cast bar, resource stack): a
-- corner grip, mouse-wheel steps on the name bar, and a typed size label,
-- driving the saved width and (where one exists) height. Sizes always come
-- from the stored settings plus the cursor delta, never from bar geometry --
-- the cast bar subtree forbids position reads (see CastBar.lua header).
------------------------------------------------------------------------

-- 0 = re-apply every frame during a grip drag (owner ruling: smooth resize
-- everywhere in arrange mode; movers can pass applyInterval to throttle).
local MOVER_WIDTH_RESIZE_INTERVAL = 0

local function GetMoverResizeCursorPosition()
    local cursorX, cursorY = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    if not (cursorX and cursorY and scale and scale > 0) then
        return nil
    end
    return cursorX / scale, cursorY / scale
end

local function RefreshConfigPanelIfShown()
    local configState = ST._configState
    local configFrame = configState and configState.configFrame
    local frame = configFrame and configFrame.frame
    if frame and frame:IsShown() then
        ST.Addon:RefreshConfigPanel()
    end
end

local function IsMoverChromeRegionOver(region)
    -- 4px of grace bridges the small gaps between chrome pieces, matching
    -- the container reveal.
    return region ~= nil and region:IsShown() and region:IsMouseOver(4, -4, -4, 4)
end

function ST.IsMoverChromePointerOver(frame)
    return IsMoverChromeRegionOver(frame._dragHandle)
        or IsMoverChromeRegionOver(frame._nudger)
        or IsMoverChromeRegionOver(frame._coordLabel)
        or IsMoverChromeRegionOver(frame._sizeLabel)
        or IsMoverChromeRegionOver(frame._resizeGrip)
end

-- Arrange chrome reveal for the independent bar movers, mirroring the
-- container model: at rest only the name bar shows; hovering it reveals the
-- nudger, labels, and grip until the pointer leaves the chrome. Outside
-- arrange mode the movers keep their full chrome, so this never starts.
function ST.BeginMoverChromeHoverReveal(frame, refresh)
    local addon = ST.Addon
    if not addon._arrangeModeActive or frame._arrangeChromeHover then
        return
    end
    frame._arrangeChromeHover = true
    frame._arrangeHoverGen = (frame._arrangeHoverGen or 0) + 1
    local generation = frame._arrangeHoverGen
    refresh()
    local function Watch()
        if frame._arrangeHoverGen ~= generation or frame._arrangeChromeHover ~= true then
            return
        end
        if addon._arrangeModeActive and ST.IsMoverChromePointerOver(frame) then
            C_Timer.After(0.2, Watch)
            return
        end
        frame._arrangeChromeHover = nil
        refresh()
    end
    C_Timer.After(0.2, Watch)
end

-- opts:
--   dragHandle       name-bar frame; kit parent and mouse-wheel target
--   coordLabel       existing coordinate label; the size label anchors below it
--   gripAnchor       frame whose BOTTOMRIGHT hosts the grip (defaults to the mover)
--   getWidth()       saved width (the bar's primary length)
--   setWidth(w)      write the saved width (the kit clamps first)
--   getHeight()      saved height/thickness; omit for a width-only mover
--   setHeight(h)     write the saved height (the kit clamps first)
--   isHeightEnabled() optional gate; false hides the height half at runtime
--   isVertical()     optional; true when the bar's LENGTH runs vertically, so
--                    the grip's axes swap to keep dragging natural
--   apply()          re-apply settings so the live bar tracks the new size
--   isUnlocked()     true while this mover is editable
--   getAnchorPoint() saved anchor point, for the center/edge travel factors
--   minWidth/maxWidth   width clamps (default 20/600, the config slider range)
--   minHeight/maxHeight height clamps (default 4/40, the config slider range)
--   applyInterval    seconds between live re-applies during a grip drag;
--                    0 applies every frame (the default)
function ST.AttachMoverWidthResize(frame, opts)
    local addon = ST.Addon
    local dragHandle = opts.dragHandle
    local coordLabel = opts.coordLabel
    local minWidth = opts.minWidth or 20
    local maxWidth = opts.maxWidth or 600
    local minHeight = opts.minHeight or 4
    local maxHeight = opts.maxHeight or 40
    local applyInterval = opts.applyInterval or MOVER_WIDTH_RESIZE_INTERVAL

    local function Clamp(value, minValue, maxValue)
        value = RoundToTenths(tonumber(value) or minValue)
        if value < minValue then
            return minValue
        elseif value > maxValue then
            return maxValue
        end
        return value
    end

    local function ClampWidth(value)
        return Clamp(value, minWidth, maxWidth)
    end

    local function ClampHeight(value)
        return Clamp(value, minHeight, maxHeight)
    end

    local function HeightEnabled()
        if not opts.getHeight then
            return false
        end
        if opts.isHeightEnabled then
            return opts.isHeightEnabled() == true
        end
        return true
    end

    local function IsVertical()
        return opts.isVertical ~= nil and opts.isVertical() == true
    end

    local sizeLabel = CreateFrame("Frame", nil, dragHandle, "BackdropTemplate")
    sizeLabel:SetHeight(15)
    sizeLabel:SetPoint("TOPLEFT", coordLabel, "BOTTOMLEFT", 0, -2)
    sizeLabel:SetPoint("TOPRIGHT", coordLabel, "BOTTOMRIGHT", 0, -2)
    sizeLabel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    sizeLabel:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    ST.CreatePixelBorders(sizeLabel)
    sizeLabel.text = sizeLabel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sizeLabel.text:SetPoint("CENTER")
    sizeLabel.text:SetTextColor(1, 1, 1, 1)

    local RepositionGrip

    -- The height half can come and go at runtime (resource bars disable the
    -- shared thickness under per-resource custom heights), so the label
    -- reconfigures on every refresh, mirroring UpdateGroupSizeLabel's
    -- kind-stamp: a mode flip mid-edit cancels the edit instead of committing
    -- a value into the wrong field.
    local function UpdateSizeLabelText()
        if RepositionGrip then
            RepositionGrip()
        end
        local withHeight = HeightEnabled()
        if sizeLabel._editing and sizeLabel._withHeight ~= withHeight then
            CancelCoordinateEdit(sizeLabel)
        end
        sizeLabel._withHeight = withHeight
        if withHeight then
            ST.ConfigureEditableCoordLabel(sizeLabel, "w:", "h:", false)
            sizeLabel.text:SetText(("w:%.1f, h:%.1f"):format(
                tonumber(opts.getWidth()) or 0,
                tonumber(opts.getHeight()) or 0
            ))
        else
            ST.ConfigureEditableCoordLabel(sizeLabel, "w:", nil, true)
            sizeLabel.text:SetText(("w:%.1f"):format(tonumber(opts.getWidth()) or 0))
        end
    end
    sizeLabel.UpdateText = UpdateSizeLabelText

    local grip = CreateFrame("Button", nil, dragHandle)
    grip:SetSize(12, 12)
    grip:SetFrameStrata(dragHandle:GetFrameStrata())
    grip:SetFrameLevel(dragHandle:GetFrameLevel() + 4)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    -- The grip lives on the MOVABLE corner: an anchored edge is fixed, so a
    -- RIGHT-anchored bar grows leftward and its left edge is the one that
    -- tracks the cursor. Centered axes keep the RIGHT/BOTTOM default.
    local function GetGripCorners()
        local point = opts.getAnchorPoint and opts.getAnchorPoint() or "CENTER"
        if type(point) ~= "string" then
            point = "CENTER"
        end
        local xSide = point:find("RIGHT", 1, true) and "LEFT" or "RIGHT"
        local ySide = point:find("BOTTOM", 1, true) and "TOP" or "BOTTOM"
        return xSide, ySide
    end

    RepositionGrip = function()
        local xSide, ySide = GetGripCorners()
        if grip._cornerX == xSide and grip._cornerY == ySide then
            return
        end
        grip._cornerX = xSide
        grip._cornerY = ySide
        local corner = ySide .. xSide
        grip:ClearAllPoints()
        grip:SetPoint(corner, opts.gripAnchor or frame, corner,
            xSide == "LEFT" and 1 or -1,
            ySide == "TOP" and -1 or 1)
    end
    RepositionGrip()

    ST.CreateEditableCoordLabel(
        sizeLabel,
        function()
            return tonumber(opts.getWidth()) or 0, opts.getHeight and tonumber(opts.getHeight()) or 0
        end,
        function(width, height)
            local withHeight = HeightEnabled()
            if withHeight ~= (height ~= nil) then
                return
            end
            opts.setWidth(ClampWidth(width))
            if withHeight then
                opts.setHeight(ClampHeight(height))
            end
            opts.apply()
            UpdateSizeLabelText()
            RefreshConfigPanelIfShown()
        end,
        function()
            return frame._dragInProgress == true or grip._resizeActive == true
        end,
        { labelA = "w:", labelB = "h:" }
    )
    coordLabel._exclusiveEditLabel = sizeLabel
    sizeLabel._exclusiveEditLabel = coordLabel
    UpdateSizeLabelText()

    -- The anchor point decides how far the dragged edge travels per unit of
    -- size on each axis: a centered bar grows both ways, so its edge moves
    -- half as fast.
    local function GetAxisFactors()
        local point = opts.getAnchorPoint and opts.getAnchorPoint() or "CENTER"
        if type(point) ~= "string" then
            point = "CENTER"
        end
        local fx = 0.5
        if point:find("LEFT", 1, true) or point:find("RIGHT", 1, true) then
            fx = 1
        end
        local fy = 0.5
        if point:find("TOP", 1, true) or point:find("BOTTOM", 1, true) then
            fy = 1
        end
        return fx, fy
    end

    local function ApplySizeFromCursor()
        local cursorX, cursorY = GetMoverResizeCursorPosition()
        if not cursorX then
            return false
        end
        -- Dragging the grip's corner outward extends the bar: the signs flip
        -- when the grip sits on the left or top (the anchored edge is on the
        -- other side). A vertical bar's LENGTH runs along Y, so the axes swap
        -- there to keep the gesture natural.
        local alongX = grip._resizeSignX * (cursorX - grip._resizeStartX) / grip._resizeFactorX
        local alongY = grip._resizeSignY * -(cursorY - grip._resizeStartY) / grip._resizeFactorY
        local widthDelta = grip._resizeVertical and alongY or alongX
        local heightDelta = grip._resizeVertical and alongX or alongY
        local changed = false

        local newWidth = ClampWidth(grip._resizeStartWidth + widthDelta)
        if newWidth ~= grip._resizeLastWidth then
            grip._resizeLastWidth = newWidth
            opts.setWidth(newWidth)
            changed = true
        end
        if grip._resizeStartHeight then
            local newHeight = ClampHeight(grip._resizeStartHeight + heightDelta)
            if newHeight ~= grip._resizeLastHeight then
                grip._resizeLastHeight = newHeight
                opts.setHeight(newHeight)
                changed = true
            end
        end
        if changed then
            UpdateSizeLabelText()
        end
        return changed
    end

    local function EndWidthResizeGesture(applyFinal)
        if not grip._resizeActive then
            grip:SetScript("OnUpdate", nil)
            return
        end
        grip._resizeActive = nil
        grip:SetScript("OnUpdate", nil)
        local pending = grip._resizePending
        if applyFinal then
            ApplySizeFromCursor()
            opts.apply()
            RefreshConfigPanelIfShown()
        elseif pending then
            addon._pendingFullRefresh = true
        end
        grip._resizeStartX = nil
        grip._resizeStartY = nil
        grip._resizeStartWidth = nil
        grip._resizeStartHeight = nil
        grip._resizeLastWidth = nil
        grip._resizeLastHeight = nil
        grip._resizeFactorX = nil
        grip._resizeFactorY = nil
        grip._resizeSignX = nil
        grip._resizeSignY = nil
        grip._resizeVertical = nil
        grip._resizeElapsed = nil
        grip._resizePending = nil
        UpdateSizeLabelText()
        addon:EndMoverChromeFade(grip)
    end

    local function UpdateWidthResizeGesture(_, elapsed)
        if not grip._resizeActive then
            return
        end
        -- Combat entry cancels the gesture explicitly; chrome teardown is
        -- not guaranteed to hide the grip on the same frame.
        if InCombatLockdown() or addon._combatForcedLock then
            EndWidthResizeGesture(false)
            return
        end
        grip._resizeElapsed = grip._resizeElapsed + elapsed
        if ApplySizeFromCursor() then
            grip._resizePending = true
        end
        if grip._resizeElapsed >= applyInterval then
            grip._resizeElapsed = 0
            if grip._resizePending then
                grip._resizePending = nil
                opts.apply()
            end
        end
    end

    local function BeginWidthResizeGesture()
        if grip._resizeActive then
            return
        end
        if InCombatLockdown() or not (opts.isUnlocked and opts.isUnlocked()) then
            return
        end
        local cursorX, cursorY = GetMoverResizeCursorPosition()
        if not cursorX then
            return
        end
        CancelCoordinateEdit(coordLabel)
        CancelCoordinateEdit(sizeLabel)
        grip._resizeStartX = cursorX
        grip._resizeStartY = cursorY
        grip._resizeStartWidth = ClampWidth(opts.getWidth())
        grip._resizeStartHeight = HeightEnabled() and ClampHeight(opts.getHeight()) or nil
        grip._resizeLastWidth = grip._resizeStartWidth
        grip._resizeLastHeight = grip._resizeStartHeight
        grip._resizeFactorX, grip._resizeFactorY = GetAxisFactors()
        local xSide, ySide = GetGripCorners()
        grip._resizeSignX = xSide == "LEFT" and -1 or 1
        grip._resizeSignY = ySide == "TOP" and -1 or 1
        grip._resizeVertical = IsVertical() or nil
        grip._resizeElapsed = 0
        grip._resizePending = nil
        grip._resizeActive = true
        addon:BeginMoverChromeFade(grip)
        grip:SetScript("OnUpdate", UpdateWidthResizeGesture)
    end

    grip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            BeginWidthResizeGesture()
        end
    end)
    grip:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            EndWidthResizeGesture(not addon._combatForcedLock and not InCombatLockdown())
        end
    end)
    grip:SetScript("OnHide", function()
        GameTooltip:Hide()
        EndWidthResizeGesture(not addon._combatForcedLock and not InCombatLockdown())
    end)
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Resize")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Mouse wheel over the name bar also resizes.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    dragHandle:EnableMouseWheel(true)
    dragHandle:SetScript("OnMouseWheel", function(_, delta)
        if not delta or delta == 0 or grip._resizeActive then
            return
        end
        if InCombatLockdown() or not (opts.isUnlocked and opts.isUnlocked()) then
            return
        end
        CancelCoordinateEdit(coordLabel)
        CancelCoordinateEdit(sizeLabel)
        addon:BeginMoverChromeWheelFade(frame)
        -- One notch steps both dimensions together, matching icon panels.
        local step = delta > 0 and 1 or -1
        local changed = false
        local currentWidth = ClampWidth(opts.getWidth())
        local newWidth = ClampWidth(currentWidth + step)
        if newWidth ~= currentWidth then
            opts.setWidth(newWidth)
            changed = true
        end
        if HeightEnabled() then
            local currentHeight = ClampHeight(opts.getHeight())
            local newHeight = ClampHeight(currentHeight + step)
            if newHeight ~= currentHeight then
                opts.setHeight(newHeight)
                changed = true
            end
        end
        if changed then
            opts.apply()
            UpdateSizeLabelText()
        end
    end)

    frame._resizeGrip = grip
    frame._sizeLabel = sizeLabel
    return grip, sizeLabel
end
