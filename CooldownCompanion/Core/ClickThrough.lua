--[[
    CooldownCompanion - ClickThrough
    Frame click-through and mouse interaction helpers
]]

local ADDON_NAME, ST = ...

local InCombatLockdown = InCombatLockdown
local select = select

-- Helper function to make a frame click-through
-- disableClicks: prevent LMB/RMB clicks (allows camera movement pass-through)
-- disableMotion: prevent OnEnter/OnLeave hover events (disables tooltips)
function ST.SetFrameClickThrough(frame, disableClicks, disableMotion)
    if not frame then return end
    local inCombat = InCombatLockdown()
    local clickState = disableClicks == true
    local motionState = disableMotion == true

    if frame._cdcClickThroughClicks == clickState
        and frame._cdcClickThroughMotion == motionState
        and (inCombat or frame._cdcClickThroughProtectedApplied == true) then
        return
    end

    if clickState then
        -- Disable mouse click interaction for camera pass-through
        -- SetMouseClickEnabled and SetPropagateMouseClicks are protected in combat
        if not inCombat then
            if frame.SetMouseClickEnabled then
                frame:SetMouseClickEnabled(false)
            end
            if frame.SetPropagateMouseClicks then
                frame:SetPropagateMouseClicks(true)
            end
            if frame.RegisterForClicks then
                frame:RegisterForClicks()
            end
            if frame.RegisterForDrag then
                frame:RegisterForDrag()
            end
        end
        frame:SetScript("OnMouseDown", nil)
        frame:SetScript("OnMouseUp", nil)
    else
        if not inCombat then
            if frame.SetMouseClickEnabled then
                frame:SetMouseClickEnabled(true)
            end
            if frame.SetPropagateMouseClicks then
                frame:SetPropagateMouseClicks(false)
            end
        end
    end

    if motionState then
        -- Disable mouse motion (hover) events
        if not inCombat then
            if frame.SetMouseMotionEnabled then
                frame:SetMouseMotionEnabled(false)
            end
            if frame.SetPropagateMouseMotion then
                frame:SetPropagateMouseMotion(true)
            end
        end
        frame:SetScript("OnEnter", nil)
        frame:SetScript("OnLeave", nil)
    else
        if not inCombat then
            if frame.SetMouseMotionEnabled then
                frame:SetMouseMotionEnabled(true)
            end
            if frame.SetPropagateMouseMotion then
                frame:SetPropagateMouseMotion(false)
            end
        end
    end

    -- EnableMouse must be true if we want motion events (tooltips)
    -- Only fully disable if both clicks and motion are disabled
    if not inCombat then
        if clickState and motionState then
            frame:EnableMouse(false)
            if frame.SetHitRectInsets then
                frame:SetHitRectInsets(10000, 10000, 10000, 10000)
            end
            frame:EnableKeyboard(false)
        else
            frame:EnableMouse(true)
            if frame.SetHitRectInsets then
                frame:SetHitRectInsets(0, 0, 0, 0)
            end
        end
    end

    frame._cdcClickThroughClicks = clickState
    frame._cdcClickThroughMotion = motionState
    frame._cdcClickThroughProtectedApplied = not inCombat
end

local function SetChildFramesClickThrough(disableClicks, disableMotion, ...)
    for i = 1, select("#", ...) do
        ST.SetFrameClickThroughRecursive(select(i, ...), disableClicks, disableMotion)
    end
end

-- Recursively apply click-through to frame and all children
function ST.SetFrameClickThroughRecursive(frame, disableClicks, disableMotion)
    if not frame then return end
    ST.SetFrameClickThrough(frame, disableClicks, disableMotion)
    SetChildFramesClickThrough(disableClicks, disableMotion, frame:GetChildren())
end
