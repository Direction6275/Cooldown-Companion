-- Cast-bar visual children and presentation for caller-owned hosts.
-- No singleton, events, anchoring, gameplay state, movers or animation driver.
local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local format, math_floor = string.format, math.floor
local DEFAULT_TICK_COLOR = { 1, 1, 1, 0.8 }
local DEFAULT_HIGHLIGHT_COLOR = { 1, 0.82, 0, 1 }

local CAST_FRAME_TEMPLATE = "DisableUntrustedLayoutScriptsTemplate"

-- Blizzard designs the cast bar art for 208x11; FX regions scale off that.
local FX_BASE_WIDTH = 208
local FX_BASE_HEIGHT = 11

-- Default spark is 20px for an 11px bar.  1.66x splits the difference between
-- the full default ratio (1.82x) and a tighter fit (1.5x).
local SPARK_HEIGHT_SCALE = 1.66

local function CaptureAtlasSize(tex, atlas)
    tex:SetAtlas(atlas, false)
    local info = C_Texture.GetAtlasInfo(atlas)
    tex._ccBaseW = (info and info.width and info.width > 0) and info.width or 1
    tex._ccBaseH = (info and info.height and info.height > 0) and info.height or 1
end

local function CreateContents(frame)
    local content = CreateFrame("Frame", nil, frame, CAST_FRAME_TEMPLATE)
    content:SetAllPoints(frame)
    content:EnableMouse(false)
    frame.content = content

    local fill = CreateFrame("StatusBar", nil, content, CAST_FRAME_TEMPLATE)
    fill:SetStatusBarTexture(CooldownCompanion:FetchStatusBar("Solid"))
    fill:SetMinMaxValues(0, 1)
    ST.SetStatusBarImmediateValue(fill, 0)
    frame.fill = fill

    fill.bg = fill:CreateTexture(nil, "BACKGROUND")
    fill.bg:SetAllPoints(fill)
    fill.bg:SetColorTexture(0, 0, 0, 0.5)

    frame.spark = fill:CreateTexture(nil, "OVERLAY", nil, 3)
    frame.spark:SetAtlas("ui-castingbar-pip")
    frame.spark:Hide()

    -- Blizzard gives the spark trail an explicit 37x12 rather than the atlas
    -- size, so the design size is a constant here too.
    frame.sparkTrail = fill:CreateTexture(nil, "OVERLAY", nil, 2)
    frame.sparkTrail:SetAtlas("cast_standard_pipglow", false)
    frame.sparkTrail._ccBaseW = 37
    frame.sparkTrail._ccBaseH = 12
    frame.sparkTrail:SetBlendMode("ADD")
    -- Blizzard masks this glow so its additive edge cannot escape the bar.
    frame.sparkTrailMask = fill:CreateMaskTexture()
    frame.sparkTrailMask:SetTexture("Interface\\Buttons\\WHITE8X8",
        "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    frame.sparkTrailMask:SetAllPoints(fill)
    frame.sparkTrail:AddMaskTexture(frame.sparkTrailMask)
    frame.sparkTrail:SetPoint("RIGHT", frame.spark, "LEFT", 2, 0)
    frame.sparkTrail:Hide()

    frame.flash = fill:CreateTexture(nil, "OVERLAY", nil, 0)
    frame.flash:SetAtlas("ui-castingbar-full-glow-standard")
    frame.flash:SetBlendMode("ADD")
    frame.flash:SetPoint("TOPLEFT", fill, "TOPLEFT", -1, 1)
    frame.flash:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 1, -1)
    frame.flash:SetAlpha(0)

    frame.interruptGlow = content:CreateTexture(nil, "BACKGROUND", nil, 1)
    CaptureAtlasSize(frame.interruptGlow, "cast_interrupt_outerglow")
    frame.interruptGlow:SetBlendMode("ADD")
    frame.interruptGlow:SetPoint("CENTER", fill, "CENTER", 0, 0)
    frame.interruptGlow:SetAlpha(0)

    local textLayer = CreateFrame("Frame", nil, content, CAST_FRAME_TEMPLATE)
    textLayer:SetAllPoints(fill)
    textLayer:SetFrameLevel(fill:GetFrameLevel() + 2)
    textLayer:EnableMouse(false)
    frame.textLayer = textLayer

    -- On the text layer, not on content: `fill` is a child FRAME of content
    -- and outranks any content texture regardless of draw layer, so an
    -- offset icon dragged over the bar would render behind the fill. Here it
    -- sits above the fill and below the border overlay; the texts stay above
    -- it on OVERLAY.
    frame.icon = textLayer:CreateTexture(nil, "ARTWORK", nil, 3)
    frame.icon:Hide()

    -- Both strings must accept text even when Style initially hides them.
    local textFont = CooldownCompanion:FetchFont("Friz Quadrata TT")
    local textOutline = ST.GetEffectiveFontOutline("OUTLINE")
    frame.nameText = textLayer:CreateFontString(nil, "OVERLAY")
    frame.nameText:SetFont(textFont, 10, textOutline)
    frame.castTimeText = textLayer:CreateFontString(nil, "OVERLAY")
    frame.castTimeText:SetFont(textFont, 10, textOutline)

    -- Empower stage separators, built on demand per cast.
    frame.stagePips = {}
    -- Channel event marks use a separate pool because they have independent
    -- lifecycle, placement and colors from empower stage boundaries.
    frame.channelTickMarks = {}

    -- Borders sit on their own frame above the fill: a texture on `content`
    -- would be occluded by the StatusBar child, which outranks it by frame
    -- level regardless of draw layer.
    local overlay = CreateFrame("Frame", nil, content, CAST_FRAME_TEMPLATE)
    overlay:SetAllPoints(frame)
    overlay:SetFrameLevel(textLayer:GetFrameLevel() + 1)
    overlay:EnableMouse(false)
    frame.overlay = overlay

    -- Blizzard border atlas, for borderStyle == "blizzard".
    frame.blizzardBorder = overlay:CreateTexture(nil, "ARTWORK", nil, 4)
    frame.blizzardBorder:SetAtlas("ui-castingbar-frame")
    frame.blizzardBorder:Hide()

    frame.borders = ST.CreateBorderTextureSet(overlay, "OVERLAY", 7)
    frame.iconBorders = ST.CreateBorderTextureSet(overlay, "OVERLAY", 7)

    return frame
end

local function IsInlineIcon(s)
    return s.showIcon ~= false and not s.iconOffset
end

local function Layout(frame, s, width, height)
    if not frame then return end

    local inlineIcon = IsInlineIcon(s)
    local inlineIconSize = height
    local fillWidth = width - (inlineIcon and inlineIconSize or 0)
    if fillWidth < 1 then fillWidth = 1 end

    frame.fillWidth = fillWidth

    local fill = frame.fill
    fill:ClearAllPoints()
    if inlineIcon and not s.iconFlipSide then
        fill:SetPoint("TOPLEFT", frame.content, "TOPLEFT", inlineIconSize, 0)
    else
        fill:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, 0)
    end
    fill:SetSize(fillWidth, height)

    local icon = frame.icon
    icon:SetShown(s.showIcon ~= false)
    if s.showIcon ~= false then
        ST._ApplyIconTexCoord(icon, 1, 1, s.iconZoom)
        icon:ClearAllPoints()
        if s.iconOffset then
            local iconSize = tonumber(s.iconSize) or 16
            icon:SetSize(iconSize, iconSize)
            local ox = tonumber(s.iconOffsetX) or 0
            local oy = tonumber(s.iconOffsetY) or 0
            if s.iconFlipSide then
                icon:SetPoint("LEFT", fill, "RIGHT", 5 + ox, oy)
            else
                icon:SetPoint("RIGHT", fill, "LEFT", -5 + ox, oy)
            end
        else
            icon:SetSize(inlineIconSize, inlineIconSize)
            if s.iconFlipSide then
                icon:SetPoint("LEFT", fill, "RIGHT", 0, 0)
            else
                icon:SetPoint("RIGHT", fill, "LEFT", 0, 0)
            end
        end
    end

    local widthScale = fillWidth / FX_BASE_WIDTH
    local heightScale = height / FX_BASE_HEIGHT

    frame.spark:SetSize(8, height * SPARK_HEIGHT_SCALE)
    -- Spark-local FX keep their native width so the trail is not stretched.
    frame.sparkTrail:SetSize(frame.sparkTrail._ccBaseW, frame.sparkTrail._ccBaseH * heightScale)
    -- Blizzard draws the interrupt glow atlas at half scale.
    frame.interruptGlow:SetSize(frame.interruptGlow._ccBaseW * 0.5 * widthScale,
                                frame.interruptGlow._ccBaseH * 0.5 * heightScale)

    frame.blizzardBorder:ClearAllPoints()
    frame.blizzardBorder:SetPoint("TOPLEFT", fill, "TOPLEFT", -2, 2)
    frame.blizzardBorder:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 2, -2)

    local nameText = frame.nameText
    nameText:ClearAllPoints()
    nameText:SetPoint("LEFT", fill, "LEFT", 4, 0)
    nameText:SetPoint("RIGHT", fill, "RIGHT", -4, 0)
    nameText:SetJustifyH("LEFT")

    local castTimeText = frame.castTimeText
    castTimeText:ClearAllPoints()
    castTimeText:SetPoint("RIGHT", fill, "RIGHT",
        -4 + (tonumber(s.castTimeXOffset) or 0), tonumber(s.castTimeYOffset) or 0)
    castTimeText:SetJustifyH("RIGHT")
end

local function Style(frame, s)
    if not frame then return end

    frame.sparkEnabled = s.showSpark ~= false
    frame.sparkTrailEnabled = s.showSparkTrail ~= false

    frame.fill:SetStatusBarTexture(CooldownCompanion:FetchEffectiveBarTexture(s.barTexture or "Solid"))

    local barColor = s.barColor or { 1, 0.7, 0, 1 }
    frame.fill:SetStatusBarColor(barColor[1] or 0, barColor[2] or 0, barColor[3] or 0,
        barColor[4] ~= nil and barColor[4] or 1)

    local bg = s.backgroundColor or { 0, 0, 0, 0.5 }
    frame.fill.bg:SetColorTexture(bg[1] or 0, bg[2] or 0, bg[3] or 0,
        bg[4] ~= nil and bg[4] or 0.5)

    local borderStyle = s.borderStyle or "pixel"
    if borderStyle == "pixel" then
        frame.blizzardBorder:Hide()
        local color = s.borderColor or { 0, 0, 0, 1 }
        local size = s.borderSize or 1
        local mode = ST.GetEffectiveBorderRenderMode(ST.GetBorderRenderMode(s), nil, size)
        if IsInlineIcon(s) then
            -- One ring around bar + inline icon.
            local leftEdge = s.iconFlipSide and frame.fill or frame.icon
            local rightEdge = s.iconFlipSide and frame.icon or frame.fill
            ST.ApplyBorderTexturesBetween(frame.borders, leftEdge, rightEdge, color, size, mode)
        else
            ST.ApplyBorderTextures(frame.borders, frame.fill, color, size, mode)
        end
        if s.showIcon ~= false and s.iconOffset then
            local iconBorderSize = s.iconBorderSize or 1
            local iconMode = ST.GetEffectiveBorderRenderMode(
                ST.GetBorderRenderMode(s, "iconBorderRenderMode"), nil, iconBorderSize)
            ST.ApplyBorderTextures(frame.iconBorders, frame.icon, color, iconBorderSize, iconMode)
        else
            ST.HideBorderTextures(frame.iconBorders)
        end
    else
        ST.HideBorderTextures(frame.borders)
        ST.HideBorderTextures(frame.iconBorders)
        frame.blizzardBorder:SetShown(borderStyle == "blizzard")
    end

    local nameText = frame.nameText
    if s.showNameText ~= false then
        local font = CooldownCompanion:FetchFont(s.nameFont or "Friz Quadrata TT")
        local outline = ST.GetEffectiveFontOutline(s.nameFontOutline or "OUTLINE")
        nameText:SetFont(font, s.nameFontSize or 10, outline)
        ST.ApplyFontShadowForOutline(nameText, outline)
        local color = s.nameFontColor
        if color then
            nameText:SetVertexColor(color[1], color[2], color[3], color[4])
        end
        nameText:Show()
    else
        nameText:Hide()
    end

    local castTimeText = frame.castTimeText
    if s.showCastTimeText ~= false then
        local font = CooldownCompanion:FetchFont(s.castTimeFont or "Friz Quadrata TT")
        local outline = ST.GetEffectiveFontOutline(s.castTimeFontOutline or "OUTLINE")
        castTimeText:SetFont(font, s.castTimeFontSize or 10, outline)
        ST.ApplyFontShadowForOutline(castTimeText, outline)
        local color = s.castTimeFontColor
        if color then
            castTimeText:SetVertexColor(color[1], color[2], color[3], color[4])
        end
        castTimeText:Show()
    else
        castTimeText:Hide()
    end
end

local function SetFill(frame, pct, showSpark)
    if not frame then return end
    if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end
    -- No interpolation: both callers supply the exact displayed progress.
    frame.fill:SetValue(pct)

    if showSpark and frame.sparkEnabled then
        frame.spark:ClearAllPoints()
        frame.spark:SetPoint("CENTER", frame.fill, "LEFT", pct * frame.fillWidth, 0)
        frame.spark:Show()
        frame.sparkTrail:SetShown(frame.sparkTrailEnabled)
    else
        frame.spark:Hide()
        frame.sparkTrail:Hide()
    end
end

local function SetTimeText(frame, remaining)
    if not frame then return end
    -- Hidden = the cast-time text setting is off (the style pass hides the
    -- string once); skip the per-frame format entirely.
    local castTimeText = frame.castTimeText
    if not castTimeText:IsShown() then return end
    if remaining < 0 then remaining = 0 end
    -- Same dedupe as BarMode's SetBarTimeText: the rendered tenth changes
    -- ~10x/sec while this runs every frame, so skip unchanged strings. The
    -- integer gate must round the way CAST_BAR_CAST_TIME does (every locale
    -- ships a single decimal); truncating instead would hold the previous
    -- tenth on screen for up to 0.05s.
    local tenth = math_floor(remaining * 10 + 0.5)
    if tenth == frame._lastCastTimeTenth then return end
    frame._lastCastTimeTenth = tenth

    local text = format(CAST_BAR_CAST_TIME or "%.1f", remaining)
    if text ~= frame._lastCastTimeText then
        frame._lastCastTimeText = text
        castTimeText:SetText(text)
    end
end

local function HideChannelTickMarks(frame)
    if not frame then return end
    for _, mark in ipairs(frame.channelTickMarks) do
        mark:Hide()
    end
end

-- Callers own mark count and cadence. Fractions are elapsed portions measured
-- inward from the right edge of the depleting channel; no spell queries here.
local function SetChannelTickMark(frame, settings, index, elapsedPortion, isLast)
    local mark = frame.channelTickMarks[index]
    if not mark then
        mark = frame.fill:CreateTexture(nil, "OVERLAY", nil, 1)
        frame.channelTickMarks[index] = mark
    end
    local highlight = settings.highlightPenultimateChannelTick == true and isLast
    local color = highlight and (settings.penultimateChannelTickColor or DEFAULT_HIGHLIGHT_COLOR)
        or (settings.channelTickColor or DEFAULT_TICK_COLOR)
    local width = math.min(math.max(tonumber(settings.channelTickWidth) or 1, 1), 5)
    mark:SetColorTexture(color[1], color[2], color[3], color[4] ~= nil and color[4] or 1)
    mark:ClearAllPoints()
    local offset = frame.fillWidth * elapsedPortion
    mark:SetPoint("TOP", frame.fill, "TOPRIGHT", -offset, 0)
    mark:SetPoint("BOTTOM", frame.fill, "BOTTOMRIGHT", -offset, 0)
    mark:SetWidth(width)
    mark:Show()
end

ST._CastBarVisuals = {
    CreateContents = CreateContents,
    Layout = Layout,
    Style = Style,
    SetFill = SetFill,
    SetTimeText = SetTimeText,
    HideChannelTickMarks = HideChannelTickMarks,
    SetChannelTickMark = SetChannelTickMark,
}
