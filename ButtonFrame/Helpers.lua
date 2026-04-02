--[[
    CooldownCompanion - ButtonFrame/Helpers
    Shared utilities, constants, and helper frames for button modules
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

-- Localize frequently-used globals
local ipairs = ipairs
local math_floor = math.floor
local pairs = pairs
local string_format = string.format

-- Color constants
local DEFAULT_BAR_AURA_COLOR = {0.2, 1.0, 0.2, 1.0}
local DEFAULT_BAR_PANDEMIC_COLOR = {1.0, 0.5, 0.0, 1.0}
local DEFAULT_BAR_CHARGE_COLOR = {1.0, 0.82, 0.0, 1.0}

-- Format remaining seconds for time display (shared across bar, text, and preview modes).
local function FormatTime(seconds, decimal)
    if seconds >= 3600 then
        return string_format("%d:%02d:%02d", math_floor(seconds / 3600), math_floor(seconds / 60) % 60, math_floor(seconds % 60))
    elseif seconds >= 60 then
        return string_format("%d:%02d", math_floor(seconds / 60), math_floor(seconds % 60))
    elseif seconds > 0 then
        return string_format(decimal and "%.1f" or "%d", decimal and seconds or math_floor(seconds))
    end
    return ""
end
CooldownCompanion.FormatTime = FormatTime

-- Apply font, size, outline, and text color to a FontString from a style table.
-- Keys are derived from prefix: e.g. prefix="charge" reads chargeFont, chargeFontSize,
-- chargeFontOutline, chargeFontColor. defaultSize overrides the 12pt fallback.
local function ApplyFontStyle(region, source, prefix, defaultSize)
    local font = CooldownCompanion:FetchFont(source[prefix .. "Font"] or "Friz Quadrata TT")
    local size = source[prefix .. "FontSize"] or defaultSize or 12
    local outline = source[prefix .. "FontOutline"] or "OUTLINE"
    region:SetFont(font, size, outline)
    local color = source[prefix .. "FontColor"] or {1, 1, 1, 1}
    region:SetTextColor(color[1], color[2], color[3], color[4])
end
CooldownCompanion.ApplyFontStyle = ApplyFontStyle

-- Cast-count text is intentionally explicit rather than auto-discovered.
-- Blizzard's cast-count/use APIs also fire for proc/override families
-- like Execute/Thunder Clap, which makes generic detection unreliable.
local CAST_COUNT_SPELL_FAMILIES = {
    [115294] = {
        buttons = {
            [115294] = true, -- Mana Tea
        },
        spells = {
            [115294] = true,
        },
    },
    [116670] = {
        buttons = {
            [116670] = true, -- Vivify button that displays Sheilun's Gift count
        },
        spells = {
            [116670] = true,
            [399491] = true, -- Sheilun's Gift cast-count spell
        },
    },
}

local function GetCastCountFamily(buttonData)
    if not buttonData then return nil end
    for _, family in pairs(CAST_COUNT_SPELL_FAMILIES) do
        if family.buttons[buttonData.id] then
            return family
        end
    end
    return nil
end

local function HasCastCountText(buttonData)
    return GetCastCountFamily(buttonData) ~= nil
end
CooldownCompanion.HasCastCountText = HasCastCountText

local function GetCastCountSpellID(buttonData, currentSpellID)
    local family = GetCastCountFamily(buttonData)
    if not family then return nil end

    if currentSpellID and family.spells[currentSpellID] then
        return currentSpellID
    end

    if family.spells[buttonData.id] then
        return buttonData.id
    end

    return nil
end
CooldownCompanion.GetCastCountSpellID = GetCastCountSpellID

local function UsesChargeBehavior(buttonData)
    return buttonData
        and (buttonData.hasCharges == true or buttonData._hasDisplayCount == true)
        or false
end
CooldownCompanion.UsesChargeBehavior = UsesChargeBehavior

-- Count text intentionally shares the charge font lane for real charges,
-- Blizzard display/use counts, and spell cast-count stacks.
local function UsesChargeTextLane(buttonData)
    if not buttonData then return false end
    return UsesChargeBehavior(buttonData)
        or HasCastCountText(buttonData)
        or buttonData.isPassive == true
end
CooldownCompanion.UsesChargeTextLane = UsesChargeTextLane

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
-- order: array of 6 keys or nil for default.
-- Index 1 = lowest layer (baseLevel+1), index 6 = highest (baseLevel+6).
-- Loss of Control is always baseLevel+7 (above all configurable elements).
local function ApplyStrataOrder(button, order)
    if not order or #order ~= #ST.DEFAULT_STRATA_ORDER then
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
        },
        auraGlow = {
            button.auraGlow and button.auraGlow.solidFrame,
            button.auraGlow and button.auraGlow.procFrame,
        },
        readyGlow = {
            button.readyGlow and button.readyGlow.solidFrame,
            button.readyGlow and button.readyGlow.procFrame,
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
        button.locCooldown:SetFrameLevel(baseLevel + #ST.DEFAULT_STRATA_ORDER + 1)
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
