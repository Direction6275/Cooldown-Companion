-- Shared saved-design painting. Native kits are created/styled only by AuraDisplay.
-- These helpers retain no native slot references and never read aura state.
local _, ST = ...
local Addon, I = ST.Addon, ST.Indicator
local WHITE = {1, 1, 1, 1}
local READOUT_KEYS = {"label", "timer", "count"}
local STYLE_SECTIONS = {"signal", "text", "readouts", "progress"}

-- A host may name a frame template for every frame built under it: the While
-- Missing display sits inside a window anchored to Blizzard's aura tracker,
-- and Blizzard never passes that layout restriction down implicitly
-- (ForbiddenAspectTemplates.xml), so each frame must carry it from creation.
function I.CreateVisual(host, nativeSlot)
    if host.indicatorReadouts then return end
    Addon.EnsureIndicatorIconVisual(host)
    Addon.EnsureIndicatorTextVisual(host)
    local template = host._ccFrameTemplate
    local root = CreateFrame("Frame", nil, host.visualRoot, template)
    root:SetAllPoints(host.visualRoot)
    root:EnableMouse(false)
    local readouts = {root = root, frames = {}}
    for _, key in ipairs(READOUT_KEYS) do
        local wrapper = CreateFrame("Frame", nil, root, template)
        wrapper:SetAllPoints(root)
        wrapper:SetAlpha(0)
        readouts.frames[key] = wrapper
        readouts[key] = wrapper:CreateFontString(nil, "OVERLAY", "GameFontHighlightOutline")
    end
    host.indicatorReadouts = readouts

    local bar = CreateFrame("StatusBar", nil, host.visualRoot, template)
    bar:SetAllPoints(host.visualRoot)
    bar:EnableMouse(false)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    local fill = bar:GetStatusBarTexture() -- Creation-time only; never read after registration.
    bar:SetAlpha(0)
    local clip = CreateFrame("Frame", nil, host.visualRoot, template)
    clip:SetPoint("TOPLEFT", fill, "TOPLEFT", 0, 0)
    clip:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
    clip:SetClipsChildren(true)
    clip:EnableMouse(false)
    local artwork = CreateFrame("Frame", nil, clip, template)
    artwork:SetAllPoints(host.visualRoot)
    artwork:EnableMouse(false)
    local foreground = {visualRoot = artwork,
        primaryTexture = artwork:CreateTexture(nil, "ARTWORK"),
        secondaryTexture = artwork:CreateTexture(nil, "ARTWORK")}
    clip:SetAlpha(0)
    -- Levels above visualRoot's own artwork: +1 the artwork's Pandemic
    -- recolor, +2 the drain clip, +3 the drained copy, +4 its recolor, +5 the
    -- readouts. The recolor levels stay reserved when no recolor is built.
    local level = host.visualRoot:GetFrameLevel()
    clip:SetFrameLevel(level + 2)
    artwork:SetFrameLevel(level + 3)
    root:SetFrameLevel(level + 5)
    host.indicatorProgress = {bar = bar, clip = clip, foreground = foreground}
    if nativeSlot then
        -- Registered now, in the slot's setup window; previews build theirs
        -- when first styled on (StylePandemicTint).
        I.CreatePandemicTint(host, nativeSlot)
        nativeSlot:SetDurationText(readouts.timer)
        nativeSlot:SetApplicationCount(readouts.count)
        nativeSlot:SetDurationBar(bar, {interpolation = ST.STATUS_BAR_INTERPOLATION_SMOOTH,
            direction = ST.STATUS_BAR_TIMER_DIRECTION_REMAINING})
    end
end

-- Pandemic recolor (Texture and Text displays; Icons glow instead,
-- CreatePandemicGlow): tinted copies of the artwork, the drained artwork and
-- the label, each in a frame a native slot registers as a pandemic region, so
-- Blizzard reveals them only inside the refresh window. Born hidden; a
-- preview shows them itself. Only native slots and previews build one.
function I.CreatePandemicTint(host, nativeSlot)
    if host.indicatorPandemicTint then return host.indicatorPandemicTint end
    local template = host._ccFrameTemplate
    local level = host.visualRoot:GetFrameLevel()
    local readouts, clip = host.indicatorReadouts, host.indicatorProgress.clip
    local labelTint = CreateFrame("Frame", nil, readouts.frames.label, template)
    labelTint:SetAllPoints(readouts.root)
    labelTint:EnableMouse(false)
    labelTint:Hide()
    -- Above the artwork, below the drained copy.
    local tintBase = CreateFrame("Frame", nil, host.visualRoot, template)
    tintBase:SetAllPoints(host.visualRoot)
    tintBase:EnableMouse(false)
    tintBase:Hide()
    tintBase:SetFrameLevel(level + 1)
    -- The drained copy's recolor rides the same clip, above it.
    local tintFore = CreateFrame("Frame", nil, clip, template)
    tintFore:SetAllPoints(host.visualRoot)
    tintFore:EnableMouse(false)
    tintFore:Hide()
    tintFore:SetFrameLevel(level + 4)
    local tint = {labelFrame = labelTint, baseFrame = tintBase, foreFrame = tintFore,
        label = labelTint:CreateFontString(nil, "OVERLAY", "GameFontHighlightOutline"),
        base = {visualRoot = tintBase,
            primaryTexture = tintBase:CreateTexture(nil, "ARTWORK"),
            secondaryTexture = tintBase:CreateTexture(nil, "ARTWORK")},
        fore = {visualRoot = tintFore,
            primaryTexture = tintFore:CreateTexture(nil, "ARTWORK"),
            secondaryTexture = tintFore:CreateTexture(nil, "ARTWORK")},
        -- The artwork fields LayoutTexturePieces reads, refilled per style.
        settings = {color = {1, 1, 1, 1}}}
    -- A recolor, not a multiply: the copies go gray before the tint, so any
    -- artwork turns the effect color instead of its own color times it.
    tint.base.primaryTexture:SetDesaturated(true)
    tint.base.secondaryTexture:SetDesaturated(true)
    tint.fore.primaryTexture:SetDesaturated(true)
    tint.fore.secondaryTexture:SetDesaturated(true)
    if nativeSlot and nativeSlot.AddPandemicRegion then
        nativeSlot:AddPandemicRegion(tintBase)
        nativeSlot:AddPandemicRegion(tintFore)
        nativeSlot:AddPandemicRegion(labelTint)
    end
    host.indicatorPandemicTint = tint
    return tint
end

-- The Pandemic effect rig: the panel pandemic glow kit, drawn above the
-- artwork and below the readouts. Native aura Indicator kits build it at slot
-- creation and register it with the slot (Blizzard then owns its Shown state);
-- the config preview builds its own and shows it itself. It is a child of
-- visualRoot so Pulse, Shrink / Expand and Bounce carry it with the artwork.
function I.CreatePandemicGlow(host, auraOwned)
    local glow = ST._BuildKitGlowRegions(host.visualRoot, true, auraOwned)
    local root = host.indicatorReadouts.root
    local level = root:GetFrameLevel()
    glow.host:SetFrameLevel(level)
    glow.cdm.frame:SetFrameLevel(level)
    root:SetFrameLevel(level + 1)
    host.indicatorPandemicGlow = glow
    return glow
end

-- Nameplate reminders show refresh soon on an Icon as a plain border in the
-- Pandemic Color instead of the glow rig (owner ruling 2026-10-04): a kit
-- exists per watcher, up to twenty per DoT. Built inside the pandemic twin's
-- gated base, so Blizzard already reveals it only in the window; styled from
-- saved settings, sized from the bounds StyleVisual stamps.
local PANDEMIC_BORDER_SIZE = 2
function I.CreatePandemicBorder(host)
    local frame = CreateFrame("Frame", nil, host.visualRoot, host._ccFrameTemplate)
    frame:SetAllPoints(host.visualRoot)
    frame:EnableMouse(false)
    frame:SetFrameLevel(host.indicatorReadouts.root:GetFrameLevel())
    host.indicatorReadouts.root:SetFrameLevel(frame:GetFrameLevel() + 1)
    frame:Hide()
    host.indicatorPandemicBorder = {frame = frame, edges = ST.CreateBorderTextureSet(frame)}
    return host.indicatorPandemicBorder
end

-- The host draws the aura's live display: a native aura Indicator, or the
-- Also During Pandemic twin of a While Missing one (AuraDisplay
-- "pandemicIndicatorAura", the preview's Pandemic Window state).
local function DrawsLiveAura(host, group)
    return I.IsNativeAura(group) or host._ccPandemicTwin == true and I.AlsoDuringPandemic(group)
end

-- The host draws a presence picture (While Missing, several auras): no
-- timer, count or drain. The pandemic twin is the live display instead.
local function DrawsPresence(host, group)
    return I.UsesPresence(group) and not host._ccPandemicTwin
end

-- Styles the rig from saved settings only. Off ("none") unless this is an
-- aura Indicator showing Icon artwork with the effect enabled (Texture and
-- Text recolor instead, StylePandemicTint);
-- `group` nil resets a pooled slot. The glow covers the visual's bounds,
-- stamped by StyleVisual, so no frame is ever measured.
function I.StylePandemicGlow(host, group, shown)
    local glow = host.indicatorPandemicGlow
    if not glow then return end
    local settings = I.Settings(group)
    local enabled = shown and DrawsLiveAura(host, group) and settings.displayType == "icon"
        and I.PandemicEffectOn(group) or false
    ST._StyleKitPandemicGlowRegions(glow, settings and settings.pandemic, host.visualRoot, enabled)
end

-- The nameplate border: an Icon display with the Pandemic effect on.
function I.StylePandemicBorder(host, group, shown)
    local border = host.indicatorPandemicBorder
    if not border then return end
    local settings = I.Settings(group)
    local on = shown and settings and DrawsLiveAura(host, group) and settings.displayType == "icon"
        and I.PandemicEffectOn(group) or false
    if not on then border.frame:Hide(); return end
    -- A fixed thickness in the kit's own units: nothing is measured.
    ST.ApplyBorderTextures(border.edges, border.frame,
        settings.pandemic.pandemicGlowColor or ST.DEFAULT_PANDEMIC_COLOR, PANDEMIC_BORDER_SIZE)
    border.frame:Show()
end

-- The Pandemic effect on Texture and Text displays: the artwork (and its
-- drained copy) or the label in the effect color, laid over the original.
-- Same saved-settings-only rule as the glow; `group` nil resets a pooled
-- slot. Reads only the CC-styled artwork state StyleVisual just stamped.
function I.StylePandemicTint(host, group, shown)
    local settings = I.Settings(group)
    local pandemic = settings and settings.pandemic
    local on = shown and settings and DrawsLiveAura(host, group) and I.PandemicEffectOn(group) or false
    local displayType = settings and settings.displayType
    -- A native slot's rig exists from creation; a preview's is built on first use.
    local tint = host.indicatorPandemicTint
        or on and displayType ~= "icon" and I.CreatePandemicTint(host)
    if not tint then return end
    local color = pandemic and pandemic.pandemicGlowColor or ST.DEFAULT_PANDEMIC_COLOR
    local visual, geometry = host._activeTextureSettings, host._activeTextureGeometry
    if on and displayType == "texture" and visual and geometry then
        -- The artwork fields LayoutTexturePieces reads, in the effect color;
        -- one table per rig, refilled on each style.
        local tinted = tint.settings
        tinted.sourceType, tinted.sourceValue, tinted.mediaType = visual.sourceType, visual.sourceValue, visual.mediaType
        tinted.blendMode = visual.blendMode
        local tintColor = tinted.color
        tintColor[1], tintColor[2], tintColor[3] = color[1] or 1, color[2] or 1, color[3] or 1
        tintColor[4] = visual.color and visual.color[4] or 1
        local alpha = host._indicatorTextureAlpha or 1
        ST._AT.LayoutTexturePieces(tint.base, tinted, geometry, alpha * (host._indicatorDimAlpha or 1))
        ST._AT.LayoutTexturePieces(tint.fore, tinted, geometry, alpha)
        -- Kept gray whatever a texture swap does (see CreateVisual).
        tint.base.primaryTexture:SetDesaturated(true)
        tint.base.secondaryTexture:SetDesaturated(true)
        tint.fore.primaryTexture:SetDesaturated(true)
        tint.fore.secondaryTexture:SetDesaturated(true)
    else
        tint.base.primaryTexture:Hide()
        tint.base.secondaryTexture:Hide()
        tint.fore.primaryTexture:Hide()
        tint.fore.secondaryTexture:Hide()
    end
    local label = host.indicatorReadouts and host.indicatorReadouts.label
    if on and displayType == "text" and label then
        local font, size, flags = label:GetFont()
        if font then
            tint.label:SetFont(font, size, flags)
            ST.ApplyFontShadowForOutline(tint.label, flags)
        end
        tint.label:ClearAllPoints()
        tint.label:SetPoint("CENTER", label, "CENTER", 0, 0)
        tint.label:SetJustifyH("CENTER")
        tint.label:SetWordWrap(false)
        tint.label:SetText(label:GetText() or "")
        -- Hue only, like the Texture recolor: the copy keeps the label's own
        -- opacity (StyleReadouts' color), so it covers the original exactly.
        local base = host._indicatorReadoutColors and host._indicatorReadoutColors.label
        tint.label:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, base and base[4] or 1)
    else
        tint.label:SetText("")
    end
end

-- A Text display recolors its whole text in the window: the label through
-- StylePandemicTint, the timer through the duration formatter's whole-text
-- Pandemic coloring. The marker keeps its text only when `markerWanted`
-- (the caller's own marker decision, Auto's unit rule included). The
-- readouts as the formatter should read them, or nil when this doesn't
-- apply. `into` (optional) is reused, so a per-frame caller allocates nothing.
function I.PandemicTimerStyle(group, markerWanted, into)
    if not I.PandemicRecolorsText(group) then return end
    local settings = I.Settings(group)
    local pandemic = settings.pandemic
    local style = into or {}
    if into then wipe(into) end
    for key, value in pairs(settings.readouts) do style[key] = value end
    style.pandemicMarkerColorMode = "whole"
    style.pandemicMarkerColor = pandemic.pandemicGlowColor or ST.DEFAULT_PANDEMIC_COLOR
    if not markerWanted then style.pandemicMarkerText = "" end
    return style
end
local previewTimerStyle = {}

-- Preview stand-ins: CC-owned sample seconds on the same scale the drain uses.
-- The timer text runs through the live features' manual twins, so Low Time
-- and the Pandemic marker read exactly as they will in game.
I.PREVIEW_SECONDS = 20
function I.IsPreviewPandemicWindow(seconds)
    return seconds > 0 and seconds < I.PREVIEW_SECONDS * 0.3
end
-- A sample inside that window (5 of 20 seconds), for the Pandemic Window state.
I.PREVIEW_PANDEMIC_FRACTION = 0.25

function I.PreviewTimerText(group, seconds)
    local settings = I.Settings(group)
    local options = settings and settings.readouts
    if not (options and options.timer and seconds > 0) then return "" end
    if I.IsAura(group) then
        local window = I.IsPreviewPandemicWindow(seconds)
        local markerWanted = I.PandemicMarkerOn(group)
            and Addon:IsPandemicMarkerPreviewWanted(I.Primary(group), options)
        local recolor = I.PandemicTimerStyle(group, markerWanted, previewTimerStyle)
        if recolor then
            return Addon:FormatAuraDurationPreviewText(seconds, recolor, window, true)
        end
        return Addon:FormatAuraDurationPreviewText(seconds, options, window and markerWanted, true)
    end
    return Addon.FormatDurationText(seconds, options, true, "cooldown")
end

local function ReadoutAnchor(options, key)
    return options[key .. "Anchor"] or (key == "label" and "TOP" or key == "count" and "BOTTOM" or "CENTER")
end

-- The saved choice to show a readout; `missing` (a presence picture) has no
-- timer or count.
local function ReadoutShown(group, options, key, missing)
    return key == "label" and options.label ~= "none"
        or key == "timer" and options.timer == true and not missing
        or key == "count" and not missing and (I.IsAura(group) and options.count == "stacks"
            or not I.IsAura(group) and (options.count == "charges" or options.count == "item"))
end

-- A Text display with no visible background is just its text: how far that
-- text sits inside the box's top and bottom edges, from saved settings alone
-- (nothing is measured). Unlock mode hangs its header and coordinates on the
-- text instead of the box. The label decides when it has text: a timer or
-- count is usually blank while unlocked (and may be secret), so they count
-- only without one. Nil when the box itself is what shows (other displays,
-- a background).
function I.TextContentInsets(group)
    local settings = I.Settings(group)
    if not (settings and settings.displayType == "text") then return end
    local background = settings.text.textBgColor
    if background and (background[4] or 1) > 0 then return end
    local options, boxHeight = settings.readouts, settings.text.height or 48
    local missing = I.UsesPresence(group)
    local labeled = ReadoutShown(group, options, "label", missing) and (I.Label(group) or "") ~= ""
    local top, bottom
    for _, key in ipairs(READOUT_KEYS) do
        if (key == "label") == labeled and ReadoutShown(group, options, key, missing) then
            local _, size = I.ReadoutFont(settings, key)
            -- A rendered line runs a little past its font size (outline,
            -- descenders); pad so the chrome clears the glyphs.
            local line = size * 1.1 + 2
            local anchor = ReadoutAnchor(options, key)
            -- Downward from the box's top edge.
            local anchorY = (anchor:find("TOP") and 0 or anchor:find("BOTTOM") and boxHeight or boxHeight / 2)
                - (options[key .. "Y"] or 0)
            local lineTop = anchorY - (anchor:find("TOP") and 0 or anchor:find("BOTTOM") and line or line / 2)
            top = math.min(top or lineTop, lineTop)
            bottom = math.max(bottom or lineTop + line, lineTop + line)
        end
    end
    if not top then return end
    return math.max(0, top), math.max(0, boxHeight - bottom)
end

-- `font`/`outline` are the shared text font StyleVisual already resolved; only
-- a readout with its own font or outline needs another lookup.
local function StyleReadouts(host, group, font, outline)
    local settings = I.Settings(group)
    local text, options = settings.text, settings.readouts
    local readouts = host.indicatorReadouts
    local missing = DrawsPresence(host, group)
    readouts.root:Show()
    -- Text effects restore and shift each readout from its own color.
    local baseColors = host._indicatorReadoutColors or {}
    host._indicatorReadoutColors = baseColors
    for _, key in ipairs(READOUT_KEYS) do
        local fs = readouts[key]
        local fontName, size, outlineName, color = I.ReadoutFont(settings, key)
        baseColors[key] = color
        local fontPath = text[key .. "Font"] and Addon:FetchFont(fontName) or font
        local fontOutline = text[key .. "FontOutline"] and ST.GetEffectiveFontOutline(outlineName) or outline
        fs:SetFont(fontPath, size, fontOutline)
        ST.ApplyFontShadowForOutline(fs, fontOutline)
        fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
        fs:ClearAllPoints()
        local anchor = ReadoutAnchor(options, key)
        fs:SetPoint(anchor, host.visualRoot, anchor, options[key .. "X"] or 0, options[key .. "Y"] or 0)
        fs:SetJustifyH("CENTER")
        fs:SetWordWrap(false)
        -- The native duration binding owns FontString alpha. A separate,
        -- unregistered wrapper owns the saved choice to show this readout.
        readouts.frames[key]:SetAlpha(ReadoutShown(group, options, key, missing) and 1 or 0)
    end
    readouts.label:SetText(I.Label(group))
    if missing then
        -- Once per restyle, not per update: nothing here ever changes.
        Addon.UnbindDurationText(readouts.timer, true)
        readouts.timer:SetText("")
        readouts.count:SetText("")
    end
end

function I.StyleVisual(host, group, icon, font, outline)
    local settings = I.Settings(group)
    if not settings then return false end
    if settings.displayType == "icon" then icon = icon or I.IconSettings(group) end
    local visual = I.NativeSettings(group, icon)
    if not visual or visual.enabled == false then return false end
    local geometry, alpha = Addon:GetIndicatorTextureRenderGeometry(visual)
    if not geometry then return false end
    host.visualRoot:SetSize(geometry.boundsWidth, geometry.boundsHeight)
    -- CC-owned bounds for the pandemic glow; a native slot's rect is never read.
    host.visualRoot._ccKitRectW, host.visualRoot._ccKitRectH = geometry.boundsWidth, geometry.boundsHeight
    Addon:ResetTextureIndicatorRootState(host)
    Addon.HideIndicatorDisplayVisuals(host)
    host.indicatorProgress.clip:SetAlpha(0)
    host._indicatorDimAlpha = nil
    host._activeDisplayType = settings.displayType
    font = font or Addon:FetchFont(settings.text.textFont or "Friz Quadrata TT")
    outline = outline or ST.GetEffectiveFontOutline(settings.text.textFontOutline)
    local shown = true
    if settings.displayType == "icon" then
        if not icon.manualIcon then return false end
        Addon.ApplyIndicatorIconVisual(host, icon)
    elseif settings.displayType == "texture" then
        local draining = settings.progress.enabled == true and not DrawsPresence(host, group)
        local dim = draining and (settings.progress.dimAlpha or 0.35) or 1
        host._indicatorDimAlpha = dim
        shown = ST._AT.LayoutTexturePieces(host, visual, geometry, alpha * dim)
        if draining then
            local progress = host.indicatorProgress
            ST._AT.LayoutTexturePieces(progress.foreground, visual, geometry, alpha)
            local direction = settings.progress.direction or "down"
            progress.bar:SetOrientation((direction == "left" or direction == "right") and "HORIZONTAL" or "VERTICAL")
            progress.bar:SetReverseFill(direction == "right" or direction == "up")
            progress.clip:SetAlpha(1)
        end
        host._activeTextureSettings, host._activeTextureGeometry = visual, geometry
        host._indicatorTextureAlpha = alpha
    else
        host._indicatorTextBaseColor = CopyTable(settings.text.textFontColor or WHITE)
        host.textFrame.bg:SetColorTexture(unpack(settings.text.textBgColor or {0, 0, 0, 0}))
        host.textFrame:SetSize(geometry.boundsWidth, geometry.boundsHeight)
        host.textFrame.text:SetFont(font, settings.text.textFontSize or 20, outline)
        host.textFrame.text:SetText("")
        host.textFrame:Show()
    end
    StyleReadouts(host, group, font, outline)
    return shown, geometry.boundsWidth, geometry.boundsHeight
end

-- Text effects paint readouts through here: with no shift each readout gets
-- its own styled color back, otherwise it moves from that color toward the
-- shift color. `fallback` covers a host whose readouts were never styled.
function I.PaintReadoutColors(host, fallback, shift, t, shiftAlpha)
    local readouts = host.indicatorReadouts
    if not readouts then return end
    local colors = host._indicatorReadoutColors or {}
    for _, key in ipairs(READOUT_KEYS) do
        local base = colors[key] or fallback
        local r, g, b, a = base[1] or 1, base[2] or 1, base[3] or 1, base[4] or 1
        if shift then
            r = r + (((shift[1] or 1) - r) * t)
            g = g + (((shift[2] or 1) - g) * t)
            b = b + (((shift[3] or 1) - b) * t)
            a = math.min(1, math.max(0, a))
            a = a + ((shiftAlpha - a) * t)
        end
        readouts[key]:SetTextColor(r, g, b, a)
    end
end

-- Compare saved values, not table identity: sliders/colors, imports and preview
-- rollback can edit a table in place. No timer/count/aura observations enter this
-- snapshot. Native aura kits still use the unconditional, access-gated styler.
local function SameStyleValues(current, previous)
    if type(current) ~= "table" then return current == previous end
    if type(previous) ~= "table" then return false end
    for key, value in pairs(current) do
        if not SameStyleValues(value, previous[key]) then return false end
    end
    for key in pairs(previous) do
        if current[key] == nil then return false end
    end
    return true
end

local function RefreshRuntimeStyle(host, group, icon)
    local settings = I.Settings(group)
    local font = Addon:FetchFont(settings.text.textFont or "Friz Quadrata TT")
    local outline = ST.GetEffectiveFontOutline(settings.text.textFontOutline)
    local label = I.Label(group)
    local borderMode, borderInset, assetType, assetValue
    if icon then
        borderMode = ST.GetEffectiveBorderRenderMode(icon, nil, icon.borderSize)
        -- StyleVisual resets visualRoot's animated scale before laying out the
        -- icon. The outer host matches that scale without sampling Shrink/Expand.
        borderInset = ST.GetEffectiveBorderLayoutSize(host, icon.borderSize, borderMode)
    elseif settings.displayType == "texture" then
        local signal = settings.signal
        assetType, assetValue = Addon:ResolveAuraTextureAsset(signal.sourceType, signal.sourceValue, signal.mediaType)
    end
    local previous = host._indicatorStyle
    -- A SharedMedia font registering late changes what a saved font name
    -- resolves to without changing any saved value.
    local fontGeneration = ST.FontMediaGeneration
    local missing = I.UsesPresence(group)
    local same = previous and previous.source == I.Primary(group) and previous.missing == missing
        and previous.fontGeneration == fontGeneration
        and previous.displayType == settings.displayType and previous.tracking == settings.tracking
        and previous.font == font and previous.outline == outline and previous.label == label
        and previous.borderMode == borderMode and previous.borderInset == borderInset
        and previous.assetType == assetType and previous.assetValue == assetValue
        and SameStyleValues(icon, previous.icon)
    if same then
        for _, key in ipairs(STYLE_SECTIONS) do
            if not SameStyleValues(settings[key], previous[key]) then same = false; break end
        end
    end
    if same then return true end

    local shown, width, height = I.StyleVisual(host, group, icon, font, outline)
    if not shown then host._indicatorStyle = nil; return false end
    host:SetSize(width, height)
    local snapshot = {source=I.Primary(group), missing=missing, displayType=settings.displayType, tracking=settings.tracking,
        font=font, outline=outline, label=label, borderMode=borderMode, borderInset=borderInset,
        fontGeneration=fontGeneration,
        assetType=assetType, assetValue=assetValue, icon=icon}
    for _, key in ipairs(STYLE_SECTIONS) do snapshot[key] = CopyTable(settings[key]) end
    host._indicatorStyle = snapshot
    return true
end

local function SetProgressDim(host, dim)
    if host._indicatorDimAlpha == dim then return end
    host._indicatorDimAlpha = dim
    host._indicatorBaseVisualsReady = nil
    ST._AT.LayoutTexturePieces(host, host._activeTextureSettings, host._activeTextureGeometry,
        host._indicatorTextureAlpha * (dim or 1))
end

function I.UpdateReadouts(host, driver, group, previewFraction)
    local settings, readouts = I.Settings(group), host.indicatorReadouts
    local options = settings.readouts
    local preview = previewFraction ~= nil
    if preview then
        Addon.UnbindDurationText(readouts.timer, true)
        readouts.timer:SetText(I.PreviewTimerText(group, previewFraction * I.PREVIEW_SECONDS))
        -- A stack rule's preview sets its sample count; like Blizzard's count
        -- text, one stack or none shows nothing.
        local stacks = host._previewStacks
        readouts.count:SetText(options.count ~= "none" and (not stacks and "3" or stacks > 1 and tostring(stacks)) or "")
    elseif I.UsesPresence(group) then
        -- Presence-drawn: no timer, count or drain.
        -- StyleReadouts cleared them once; nothing to do per update.
    elseif not I.IsAura(group) then
        local duration = driver and (driver._chargeRecharging and driver._chargeDurationObj or driver._durationObj)
        local itemDuration = driver and driver._itemCdDuration or 0
        local itemRemaining = itemDuration > 0 and math.max(0, itemDuration - (GetTime() - (driver._itemCdStart or 0))) or 0
        -- Manual readouts need the normal walk cadence while they advance.
        -- Register here: the source button is hidden even when this display is
        -- visible, so its ordinary time-state classifier is never reached.
        -- Native duration bindings and previews animate without this walk.
        if not duration and itemRemaining > 0 and (options.timer
            or (settings.displayType == "texture" and settings.progress.enabled)) then
            Addon:PinCooldownTicker("indicator-item")
        end
        -- Low Time applies to every Indicator timer (nil threshold = off).
        if options.timer and duration then
            Addon.BindDurationText(readouts.timer, duration, options, true, "cooldown")
        else
            Addon.UnbindDurationText(readouts.timer, true)
            if options.timer and itemRemaining > 0 then
                readouts.timer:SetText(Addon.FormatDurationText(itemRemaining, options, true, "cooldown"))
            end
        end
        if options.count ~= "none" and driver then
            -- Existing non-aura count text may be secret: pass it straight to a
            -- FontString. Never compare or concatenate the returned text.
            if options.count == "charges" and driver.count then
                readouts.count:SetText(driver.count:GetText())
            elseif options.count == "item" and driver._resolvedItemAvailableQuantity then
                readouts.count:SetText(driver._resolvedItemAvailableQuantity)
            else readouts.count:SetText("") end
        else readouts.count:SetText("") end
        if settings.progress.enabled and settings.displayType == "texture" then
            -- Style no longer runs on every tick. Restore the drain when a new
            -- cooldown starts, and restore its unshifted foreground before the
            -- live effects writer applies this tick's activation state.
            if duration or itemDuration > 0 then
                SetProgressDim(host, settings.progress.dimAlpha or 0.35)
                host.indicatorProgress.clip:SetAlpha(1)
            end
            local color = host._activeTextureSettings.color or WHITE
            local foreground = host.indicatorProgress.foreground
            foreground.primaryTexture:SetVertexColor(color[1], color[2], color[3], host._indicatorTextureAlpha)
            foreground.secondaryTexture:SetVertexColor(color[1], color[2], color[3], host._indicatorTextureAlpha)
            if duration then
                host.indicatorProgress.bar:SetTimerDuration(duration, ST.STATUS_BAR_INTERPOLATION_SMOOTH,
                    ST.STATUS_BAR_TIMER_DIRECTION_REMAINING)
            elseif itemDuration > 0 then
                host.indicatorProgress.bar:SetMinMaxValues(0, itemDuration)
                host.indicatorProgress.bar:SetValue(itemRemaining)
            else
                host.indicatorProgress.clip:SetAlpha(0)
                SetProgressDim(host, nil)
            end
        end
    end
    if preview then
        host.indicatorProgress.bar:SetMinMaxValues(0, 1)
        host.indicatorProgress.bar:SetValue(previewFraction)
    end
end

function I.Render(host, driver, group, preview, fraction, effectsActive, resolvedIcon)
    I.CreateVisual(host)
    local settings = I.Settings(group)
    if not settings then return false end
    local icon = settings.displayType == "icon" and (resolvedIcon or I.IconSettings(group)) or nil
    -- Spell, item and While Missing Indicators are drawn here at runtime;
    -- native auras draw in their slot and reach this only for previews.
    local ccDrawn = not I.IsNativeAura(group)
    if not preview and ccDrawn then
        if not RefreshRuntimeStyle(host, group, icon) then return false end
    else
        local shown, width, height = I.StyleVisual(host, group, icon)
        if not shown then return false end
        host:SetSize(width, height)
    end
    I.UpdateReadouts(host, driver, group, (preview or not ccDrawn) and (fraction or 0.5) or nil)
    if ccDrawn and not preview then
        Addon:ApplyIndicatorEffects(host, driver, group, effectsActive == true)
    end
    return true
end

-- The stack gate's cell: a box around the slot center wide enough for all the
-- display draws (artwork, pandemic glow, Bounce, readouts at their offsets),
-- estimated from saved settings so nothing in the slot is ever measured.
local function StackGateCell(group, width, height)
    local settings = I.Settings(group)
    local options = settings.readouts
    local glow = tonumber(settings.pandemic and settings.pandemic.pandemicGlowSize) or 0
    local pad = math.max(width, height) / 2 + glow + 24
    local reachX, reachY = width / 2 + pad, height / 2 + pad
    local label = I.Label(group) or ""
    for _, key in ipairs(READOUT_KEYS) do
        local _, size = I.ReadoutFont(settings, key)
        local anchor = ReadoutAnchor(options, key)
        local x = (anchor:find("LEFT") and -width / 2 or anchor:find("RIGHT") and width / 2 or 0) + (options[key .. "X"] or 0)
        local y = (anchor:find("TOP") and height / 2 or anchor:find("BOTTOM") and -height / 2 or 0) + (options[key .. "Y"] or 0)
        -- About one font size per character, generous for any font.
        local chars = key == "label" and math.max(#label, 4) or key == "timer" and 6 or 3
        reachX = math.max(reachX, math.abs(x) + size * chars)
        reachY = math.max(reachY, math.abs(y) + size * 2)
    end
    return math.ceil(reachX * 2), math.ceil(reachY * 2)
end

-- A presence tracker's cell (one per aura): the same generous box around the display,
-- from saved settings only. Bounce travel is already inside its padding.
function I.PresenceCell(group)
    local visual = I.NativeSettings(group)
    local geometry = visual and Addon:GetIndicatorTextureRenderGeometry(visual)
    if not geometry then return end
    return StackGateCell(group, geometry.boundsWidth, geometry.boundsHeight)
end

-- The stack rule on a native slot. Each stack moves the hidden bar's fill by
-- one cell, so whole stacks decide whether the cell is covered:
--   At Least N    gate = the filled part of an N-cell bar ending at the cell's
--                 right edge, so the cell is covered from N stacks up. At Max
--                 is At Least the aura's max.
--   Fewer Than N  gate = the unfilled part of that bar: covered below N.
--   Exactly N     gate = the cell itself; the host rides the fill's right edge
--                 on an (N+1)-cell bar whose Nth step ends on the cell, so it
--                 sits inside only at exactly N (the bar clamps above its max).
-- Anchored to the slot center and the creation-time fill texture; no rect or
-- bar value is read. OOC bind only. `group` nil or no rule: unclipped.
function I.StyleStackGate(slot, group, width, height)
    local host = slot.kit and slot.kit.indicatorHost
    local stack = host and host.stackGate
    if not stack then return end
    local slotButton, gate, bar, fill = slot.slotButton, stack.gate, stack.bar, stack.fill
    local compare, count, auraMax = I.StackRule(group)
    gate:ClearAllPoints()
    host:ClearAllPoints()
    host:SetAllPoints(slotButton)
    -- A rule the aura's max settles needs no bar: one that cannot pass (or be
    -- checked) fails closed with the gate hidden until a bind changes it, and
    -- one that always passes is the unclipped gate. This also keeps the bar
    -- from being built wider than the max ever needs.
    local outcome = I.StackRuleOutcome(compare, count, auraMax)
    gate:SetShown(outcome ~= "never")
    if not compare or outcome then
        gate:SetAllPoints(slotButton)
        gate:SetClipsChildren(false)
        return
    end
    local cell, barHeight = StackGateCell(group, width, height)
    local max = compare == "exactly" and count + 1 or count
    if stack.max ~= max then
        slotButton:SetApplicationBar(bar, {maxApplications = max})
        stack.max = max
    end
    bar:ClearAllPoints()
    bar:SetSize(cell * max, barHeight)
    if compare == "exactly" then
        bar:SetPoint("LEFT", slotButton, "CENTER", cell / 2 - cell * count, 0)
        gate:SetPoint("CENTER", slotButton, "CENTER", 0, 0)
        gate:SetSize(cell, barHeight)
        host:ClearAllPoints()
        host:SetPoint("CENTER", fill, "RIGHT", -cell / 2, 0)
        host:SetSize(width, height)
    else
        bar:SetPoint("RIGHT", slotButton, "CENTER", cell / 2, 0)
        if compare == "atLeast" or compare == "max" then
            gate:SetPoint("TOPLEFT", fill, "TOPLEFT", 0, 0)
            gate:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
        else
            gate:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
            gate:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
        end
    end
    gate:SetClipsChildren(true)
end

-- Called only by the native aura owner's gated bind. No live updates use this.
-- `durationOptions` is the owner's composed timer formatter (Duration Format,
-- Low Time and the Pandemic marker, built from `readouts`); this model never
-- reads aura data to build it.
function I.StyleAura(slot, group, durationOptions)
    local host = slot.kit.indicatorHost
    slot.slotButton:ClearIcon()
    -- A nameplate watcher draws one DoT of the row, with that DoT's icon.
    local dot = slot.nameplateAura
    local shown, width, height = I.StyleVisual(host, group, dot and I.NameplateIconSettings(group, dot) or nil)
    local settings = I.Settings(group)
    local source = dot or I.Primary(group)
    local chosen = settings.icon.manualIcon and not (dot and I.IsMultiAura(group))
    if settings.displayType == "icon" and not chosen and not (source and source.manualIcon) then
        slot.slotButton:SetIcon(host.iconFrame.icon)
    end
    slot.slotButton:SetDurationText(host.indicatorReadouts.timer, durationOptions)
    slot.slotButton:SetApplicationCount(host.indicatorReadouts.count)
    I.StylePandemicGlow(host, group, shown)
    I.StylePandemicBorder(host, group, shown)
    I.StylePandemicTint(host, group, shown)
    I.StyleStackGate(slot, shown and group or nil, width, height)
    host.visualRoot:SetAlpha(shown and 1 or 0)
    return shown
end

function I.ReleaseVisual(host)
    if not host or not host.indicatorReadouts then return end
    host._indicatorStyle = nil
    ST._AT.StopAllTextureIndicatorEffects(host)
    Addon.UnbindDurationText(host.indicatorReadouts.timer, true)
    host.indicatorReadouts.root:Hide()
    host.indicatorProgress.clip:SetAlpha(0)
end
