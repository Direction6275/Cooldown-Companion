--[[
    CooldownCompanion - Utils
    Shared utilities, constants, and helpers used across multiple files
]]

local ADDON_NAME, ST = ...

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

ST.DEFAULT_OVERHANG_PCT = 32
ST.DEFAULT_GLOW_COLOR = {1, 1, 1, 1}
ST.DEFAULT_BG_COLOR = {0.2, 0.2, 0.2, 0.8}
ST.PARTICLE_COUNT = 12
ST.NUM_GLOW_STYLES = 3

-- Shared edge anchor spec: {point1, relPoint1, point2, relPoint2, x1sign, y1sign, x2sign, y2sign}
-- Signs: 0 = zero offset, 1 = +size, -1 = -size
ST.EDGE_ANCHOR_SPEC = {
    {"TOPLEFT", "TOPLEFT",     "BOTTOMRIGHT", "TOPRIGHT",     0, 0,  0, -1}, -- Top    (full width)
    {"TOPLEFT", "BOTTOMLEFT",  "BOTTOMRIGHT", "BOTTOMRIGHT",  0, 1,  0,  0}, -- Bottom (full width)
    {"TOPLEFT", "TOPLEFT",     "BOTTOMRIGHT", "BOTTOMLEFT",   0, -1,  1,  1}, -- Left   (inset to avoid corner overlap)
    {"TOPLEFT", "TOPRIGHT",    "BOTTOMRIGHT", "BOTTOMRIGHT", -1, -1,  0,  1}, -- Right  (inset to avoid corner overlap)
}

--------------------------------------------------------------------------------
-- Click-Through Helpers
--------------------------------------------------------------------------------

-- Helper function to make a frame click-through
-- disableClicks: prevent LMB/RMB clicks (allows camera movement pass-through)
-- disableMotion: prevent OnEnter/OnLeave hover events (disables tooltips)
function ST.SetFrameClickThrough(frame, disableClicks, disableMotion)
    if not frame then return end
    local inCombat = InCombatLockdown()

    if disableClicks then
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

    if disableMotion then
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
        if disableClicks and disableMotion then
            frame:EnableMouse(false)
            if frame.SetHitRectInsets then
                frame:SetHitRectInsets(10000, 10000, 10000, 10000)
            end
            frame:EnableKeyboard(false)
        elseif not disableClicks and not disableMotion then
            frame:EnableMouse(true)
            if frame.SetHitRectInsets then
                frame:SetHitRectInsets(0, 0, 0, 0)
            end
        else
            frame:EnableMouse(true)
            if frame.SetHitRectInsets then
                frame:SetHitRectInsets(0, 0, 0, 0)
            end
        end
    end
end

-- Recursively apply click-through to frame and all children
function ST.SetFrameClickThroughRecursive(frame, disableClicks, disableMotion)
    ST.SetFrameClickThrough(frame, disableClicks, disableMotion)
    -- Apply to all child frames
    for _, child in ipairs({frame:GetChildren()}) do
        ST.SetFrameClickThroughRecursive(child, disableClicks, disableMotion)
    end
end

--------------------------------------------------------------------------------
-- Border Helpers
--------------------------------------------------------------------------------

-- Create 4 pixel-perfect border textures using PixelUtil (replaces backdrop edgeFile)
function ST.CreatePixelBorders(frame, r, g, b, a)
    r, g, b, a = r or 0, g or 0, b or 0, a or 1

    local top = frame:CreateTexture(nil, "BORDER")
    top:SetColorTexture(r, g, b, a)
    PixelUtil.SetPoint(top, "TOPLEFT", frame, "TOPLEFT", 0, 0)
    PixelUtil.SetPoint(top, "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    PixelUtil.SetHeight(top, 1, 1)

    local bottom = frame:CreateTexture(nil, "BORDER")
    bottom:SetColorTexture(r, g, b, a)
    PixelUtil.SetPoint(bottom, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    PixelUtil.SetPoint(bottom, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    PixelUtil.SetHeight(bottom, 1, 1)

    local left = frame:CreateTexture(nil, "BORDER")
    left:SetColorTexture(r, g, b, a)
    PixelUtil.SetPoint(left, "TOPLEFT", frame, "TOPLEFT", 0, 0)
    PixelUtil.SetPoint(left, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    PixelUtil.SetWidth(left, 1, 1)

    local right = frame:CreateTexture(nil, "BORDER")
    right:SetColorTexture(r, g, b, a)
    PixelUtil.SetPoint(right, "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    PixelUtil.SetPoint(right, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    PixelUtil.SetWidth(right, 1, 1)

    frame.borderTextures = { top, bottom, left, right }
end

--------------------------------------------------------------------------------
-- Color Utilities
--------------------------------------------------------------------------------

-- Format a color table {r, g, b, a} into a cache key string.
-- Replaces repeated string.format("%.2f%.2f%.2f%.2f", c[1], c[2], c[3], c[4]) calls.
function ST.FormatColorKey(c)
    return string.format("%.2f%.2f%.2f%.2f", c[1], c[2], c[3], c[4] or 1)
end
