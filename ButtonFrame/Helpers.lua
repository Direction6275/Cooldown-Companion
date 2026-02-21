--[[
    CooldownCompanion - ButtonFrame/Helpers
    Shared utilities, constants, and helper frames for button modules
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

-- Localize frequently-used globals
local ipairs = ipairs

-- Color constants
local DEFAULT_BAR_AURA_COLOR = {0.2, 1.0, 0.2, 1.0}
local DEFAULT_BAR_PANDEMIC_COLOR = {1.0, 0.5, 0.0, 1.0}
local DEFAULT_BAR_CHARGE_COLOR = {1.0, 0.82, 0.0, 1.0}

-- Scratch cooldown (legacy; kept for potential fallback use).
local scratchParent = CreateFrame("Frame")
scratchParent:Hide()
local scratchCooldown = CreateFrame("Cooldown", nil, scratchParent, "CooldownFrameTemplate")

-- Position a region in the icon area of a bar button.
-- inset=0 for backgrounds/bounds, inset=borderSize for the icon texture itself.
local function SetIconAreaPoints(region, button, isVertical, iconReverse, iconSize, inset)
    region:ClearAllPoints()
    local s = iconSize - 2 * inset
    region:SetSize(s, s)
    if isVertical then
        if iconReverse then
            region:SetPoint("BOTTOM", button, "BOTTOM", 0, inset)
        else
            region:SetPoint("TOP", button, "TOP", 0, -inset)
        end
    else
        if iconReverse then
            region:SetPoint("RIGHT", button, "RIGHT", -inset, 0)
        else
            region:SetPoint("LEFT", button, "LEFT", inset, 0)
        end
    end
end

-- Position a region in the bar area of a bar button (the non-icon portion).
-- inset=0 for backgrounds/bounds, inset=borderSize for the statusBar.
local function SetBarAreaPoints(region, button, isVertical, iconReverse, barAreaLeft, barAreaTop, inset)
    region:ClearAllPoints()
    if isVertical then
        if iconReverse then
            region:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
            region:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, barAreaTop + inset)
        else
            region:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -(barAreaTop + inset))
            region:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
        end
    else
        if iconReverse then
            region:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
            region:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -(barAreaLeft + inset), inset)
        else
            region:SetPoint("TOPLEFT", button, "TOPLEFT", barAreaLeft + inset, -inset)
            region:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
        end
    end
end

-- Anchor charge/item count text on bar buttons: relative to icon when visible, relative to bar otherwise.
local function AnchorBarCountText(button, showIcon, anchor, xOff, yOff)
    button.count:ClearAllPoints()
    if showIcon then
        button.count:SetPoint(anchor, button.icon, anchor, xOff, yOff)
    else
        button.count:SetPoint(anchor, button, anchor, xOff, yOff)
    end
end

-- Returns true if the given item ID is equippable (trinkets, weapons, armor, etc.)
-- Caches result on buttonData to avoid repeated API calls.
local function IsItemEquippable(buttonData)
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(buttonData.id)
    return equipLoc ~= nil and equipLoc ~= "" and not equipLoc:find("NON_EQUIP")
end
CooldownCompanion.IsItemEquippable = IsItemEquippable

-- Apply configurable strata (frame level) ordering to button sub-elements.
-- order: array of 4 keys {"cooldown","chargeText","procGlow","assistedHighlight"} or nil for default.
-- Index 1 = lowest layer (baseLevel+1), index 4 = highest (baseLevel+4).
-- Loss of Control is always baseLevel+5 (above all configurable elements).
local function ApplyStrataOrder(button, order)
    if not order or #order ~= 4 then
        order = ST.DEFAULT_STRATA_ORDER
    end
    local baseLevel = button:GetFrameLevel()

    -- Map element keys to their frames
    local frameMap = {
        cooldown = {button.cooldown},
        chargeText = {button.overlayFrame},
        procGlow = {
            button.procGlow and button.procGlow.solidFrame,
            button.procGlow and button.procGlow.procFrame,
            button.procGlow and button.procGlow.pixelFrame,
        },
        assistedHighlight = {
            button.assistedHighlight and button.assistedHighlight.solidFrame,
            button.assistedHighlight and button.assistedHighlight.blizzardFrame,
            button.assistedHighlight and button.assistedHighlight.procFrame,
        },
    }

    for i, key in ipairs(order) do
        local frames = frameMap[key]
        if frames then
            for _, frame in ipairs(frames) do
                if frame then
                    frame:SetFrameLevel(baseLevel + i)
                end
            end
        end
    end

    -- LoC always on top
    if button.locCooldown then
        button.locCooldown:SetFrameLevel(baseLevel + 5)
    end
end

-- Shared edge anchor spec from Utils.lua
local EDGE_ANCHOR_SPEC = ST.EDGE_ANCHOR_SPEC

-- Apply edge positions to 4 border/highlight textures using the shared spec
local function ApplyEdgePositions(textures, button, size)
    for i, spec in ipairs(EDGE_ANCHOR_SPEC) do
        local tex = textures[i]
        tex:ClearAllPoints()
        tex:SetPoint(spec[1], button, spec[2], spec[5] * size, spec[6] * size)
        tex:SetPoint(spec[3], button, spec[4], spec[7] * size, spec[8] * size)
    end
end

-- Apply aspect-ratio-aware texture cropping to an icon.
-- Crops the narrower dimension so the icon image stays undistorted.
local function ApplyIconTexCoord(icon, width, height)
    if width ~= height then
        local texMin, texMax = 0.08, 0.92
        local texRange = texMax - texMin
        local aspectRatio = width / height
        if aspectRatio > 1.0 then
            local crop = (texRange - texRange / aspectRatio) / 2
            icon:SetTexCoord(texMin, texMax, texMin + crop, texMax - crop)
        else
            local crop = (texRange - texRange * aspectRatio) / 2
            icon:SetTexCoord(texMin + crop, texMax - crop, texMin, texMax)
        end
    else
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

-- Shared click-through helpers from Utils.lua
local SetFrameClickThrough = ST.SetFrameClickThrough
local SetFrameClickThroughRecursive = ST.SetFrameClickThroughRecursive

-- Fit a Blizzard highlight template frame to a button.
-- The flipbook texture must overhang the button edges to create the border effect.
-- Original template: 45x45 frame, 66x66 texture => ~23% overhang per side.
-- Per-axis overhang keeps the border flush with non-square icons.
local function FitHighlightFrame(frame, button, overhangPct)
    local w, h = button:GetSize()
    local pct = (overhangPct or 32) / 100
    local overhangW = w * pct
    local overhangH = h * pct

    frame:ClearAllPoints()
    frame:SetPoint("CENTER", button, "CENTER")
    frame:SetSize(w, h)

    -- Resize child regions (flipbook textures) to overhang the frame edges
    for _, region in ipairs({frame:GetRegions()}) do
        if region.ClearAllPoints then
            region:ClearAllPoints()
            region:SetPoint("CENTER", frame, "CENTER")
            region:SetSize(w + overhangW * 2, h + overhangH * 2)
        end
    end
    -- Also handle textures nested inside child frames
    for _, child in ipairs({frame:GetChildren()}) do
        child:ClearAllPoints()
        child:SetPoint("CENTER", frame, "CENTER")
        child:SetSize(w + overhangW * 2, h + overhangH * 2)
        for _, region in ipairs({child:GetRegions()}) do
            if region.ClearAllPoints then
                region:ClearAllPoints()
                region:SetAllPoints(child)
            end
        end
    end
end

-- Exports
ST._scratchParent = scratchParent
ST._scratchCooldown = scratchCooldown
ST._DEFAULT_BAR_AURA_COLOR = DEFAULT_BAR_AURA_COLOR
ST._DEFAULT_BAR_PANDEMIC_COLOR = DEFAULT_BAR_PANDEMIC_COLOR
ST._DEFAULT_BAR_CHARGE_COLOR = DEFAULT_BAR_CHARGE_COLOR
ST._SetIconAreaPoints = SetIconAreaPoints
ST._SetBarAreaPoints = SetBarAreaPoints
ST._AnchorBarCountText = AnchorBarCountText
ST._ApplyStrataOrder = ApplyStrataOrder
ST._ApplyEdgePositions = ApplyEdgePositions
ST._ApplyIconTexCoord = ApplyIconTexCoord
ST._FitHighlightFrame = FitHighlightFrame
