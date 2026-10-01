-- Shared saved-design painting. Native kits are created/styled only by AuraDisplay.
-- These helpers retain no native slot references and never read aura state.
local _, ST = ...
local Addon, I = ST.Addon, ST.Indicator
local WHITE = {1, 1, 1, 1}
local READOUT_KEYS = {"label", "timer", "count"}
local STYLE_SECTIONS = {"signal", "text", "readouts", "progress"}

function I.CreateVisual(host, nativeSlot)
    if host.indicatorReadouts then return end
    Addon.EnsureTriggerIconVisual(host)
    Addon.EnsureTriggerTextVisual(host)
    local root = CreateFrame("Frame", nil, host.visualRoot)
    root:SetAllPoints(host.visualRoot)
    root:EnableMouse(false)
    local readouts = {root = root, frames = {}}
    for _, key in ipairs(READOUT_KEYS) do
        local wrapper = CreateFrame("Frame", nil, root)
        wrapper:SetAllPoints(root)
        wrapper:SetAlpha(0)
        readouts.frames[key] = wrapper
        readouts[key] = wrapper:CreateFontString(nil, "OVERLAY", "GameFontHighlightOutline")
    end
    host.indicatorReadouts = readouts

    local bar = CreateFrame("StatusBar", nil, host.visualRoot)
    bar:SetAllPoints(host.visualRoot)
    bar:EnableMouse(false)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    local fill = bar:GetStatusBarTexture() -- Creation-time only; never read after registration.
    bar:SetAlpha(0)
    local clip = CreateFrame("Frame", nil, host.visualRoot)
    clip:SetPoint("TOPLEFT", fill, "TOPLEFT", 0, 0)
    clip:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
    clip:SetClipsChildren(true)
    clip:EnableMouse(false)
    local artwork = CreateFrame("Frame", nil, clip)
    artwork:SetAllPoints(host.visualRoot)
    artwork:EnableMouse(false)
    local foreground = {visualRoot = artwork,
        primaryTexture = artwork:CreateTexture(nil, "ARTWORK"),
        secondaryTexture = artwork:CreateTexture(nil, "ARTWORK")}
    clip:SetAlpha(0)
    root:SetFrameLevel(artwork:GetFrameLevel() + 1)
    host.indicatorProgress = {bar = bar, clip = clip, foreground = foreground}
    if nativeSlot then
        nativeSlot:SetDurationText(readouts.timer)
        nativeSlot:SetApplicationCount(readouts.count)
        nativeSlot:SetDurationBar(bar, {interpolation = ST.STATUS_BAR_INTERPOLATION_SMOOTH,
            direction = ST.STATUS_BAR_TIMER_DIRECTION_REMAINING})
    end
end

-- The Pandemic effect rig: the panel pandemic glow kit, drawn above the
-- artwork and below the readouts. Native texture-panel kits build it at slot
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

-- Styles the rig from saved settings only. Off ("none") unless this is an
-- aura Indicator showing Icon or Texture artwork with the effect enabled;
-- `group` nil resets a pooled slot. The glow covers the visual's bounds,
-- stamped by StyleVisual, so no frame is ever measured.
function I.StylePandemicGlow(host, group, shown)
    local glow = host.indicatorPandemicGlow
    if not glow then return end
    local settings = I.Settings(group)
    local pandemic = settings and settings.pandemic
    local enabled = shown and I.IsAura(group) and settings.displayType ~= "text"
        and pandemic and pandemic.pandemicEffectEnabled == true or false
    ST._StyleKitPandemicGlowRegions(glow, pandemic, host.visualRoot, enabled)
end

-- Preview stand-ins: CC-owned sample seconds on the same scale the drain uses.
-- The timer text runs through the live features' manual twins, so Low Time
-- and the Pandemic marker read exactly as they will in game.
I.PREVIEW_SECONDS = 20
function I.IsPreviewPandemicWindow(seconds)
    return seconds > 0 and seconds < I.PREVIEW_SECONDS * 0.3
end

function I.PreviewTimerText(group, seconds)
    local settings = I.Settings(group)
    local options = settings and settings.readouts
    if not (options and options.timer and seconds > 0) then return "" end
    if I.IsAura(group) then
        local marker = I.IsPreviewPandemicWindow(seconds) and I.PandemicMarkerOn(group)
            and Addon:IsPandemicMarkerPreviewWanted(I.Primary(group), options)
        return Addon:FormatAuraDurationPreviewText(seconds, options, marker, true)
    end
    return Addon.FormatDurationText(seconds, options, true, "cooldown")
end

local function ReadoutAnchor(options, key)
    return options[key .. "Anchor"] or (key == "label" and "TOP" or key == "count" and "BOTTOM" or "CENTER")
end

-- `font`/`outline` are the shared text font StyleVisual already resolved; only
-- a readout with its own font or outline needs another lookup.
local function StyleReadouts(host, group, font, outline)
    local settings = I.Settings(group)
    local text, options = settings.text, settings.readouts
    local readouts = host.indicatorReadouts
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
        local enabled = key == "label" and options.label ~= "none"
            or key == "timer" and options.timer == true
            or key == "count" and (I.IsAura(group) and options.count == "stacks"
                or not I.IsAura(group) and (options.count == "charges" or options.count == "item"))
        -- The native duration binding owns FontString alpha. A separate,
        -- unregistered wrapper owns the saved choice to show this readout.
        readouts.frames[key]:SetAlpha(enabled and 1 or 0)
    end
    readouts.label:SetText(I.Label(group))
end

function I.StyleVisual(host, group, icon, font, outline)
    local settings = I.Settings(group)
    if not settings then return false end
    if settings.displayType == "icon" then icon = icon or I.IconSettings(group) end
    local visual = I.NativeSettings(group, icon)
    if not visual or visual.enabled == false then return false end
    local geometry, alpha = Addon:GetTexturePanelRenderGeometry(visual)
    if not geometry then return false end
    host.visualRoot:SetSize(geometry.boundsWidth, geometry.boundsHeight)
    -- CC-owned bounds for the pandemic glow; a native slot's rect is never read.
    host.visualRoot._ccKitRectW, host.visualRoot._ccKitRectH = geometry.boundsWidth, geometry.boundsHeight
    Addon:ResetTextureIndicatorRootState(host)
    Addon.HideStandaloneDisplayVisuals(host)
    host.indicatorProgress.clip:SetAlpha(0)
    host._indicatorDimAlpha = nil
    host._activeDisplayType = settings.displayType
    font = font or Addon:FetchFont(settings.text.textFont or "Friz Quadrata TT")
    outline = outline or ST.GetEffectiveFontOutline(settings.text.textFontOutline)
    local shown = true
    if settings.displayType == "icon" then
        if not icon.manualIcon then return false end
        Addon.ApplyTriggerIconVisual(host, icon)
    elseif settings.displayType == "texture" then
        local draining = settings.progress.enabled == true
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
        host._triggerTextBaseColor = CopyTable(settings.text.textFontColor or WHITE)
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
    local same = previous and previous.source == I.Primary(group)
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
    local snapshot = {source=I.Primary(group), displayType=settings.displayType, tracking=settings.tracking,
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
    if not preview and not I.IsAura(group) then
        if not RefreshRuntimeStyle(host, group, icon) then return false end
    else
        local shown, width, height = I.StyleVisual(host, group, icon)
        if not shown then return false end
        host:SetSize(width, height)
    end
    I.UpdateReadouts(host, driver, group, (preview or I.IsAura(group)) and (fraction or 0.5) or nil)
    if not I.IsAura(group) and not preview then
        Addon:ApplyTriggerPanelEffects(host, driver, group, effectsActive == true)
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
    local host = slot.kit and slot.kit.texturePanelHost
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
    local host = slot.kit.texturePanelHost
    slot.slotButton:ClearIcon()
    local shown, width, height = I.StyleVisual(host, group)
    local settings = I.Settings(group)
    local source = I.Primary(group)
    if settings.displayType == "icon" and not settings.icon.manualIcon and not (source and source.manualIcon) then
        slot.slotButton:SetIcon(host.iconFrame.icon)
    end
    slot.slotButton:SetDurationText(host.indicatorReadouts.timer, durationOptions)
    slot.slotButton:SetApplicationCount(host.indicatorReadouts.count)
    I.StylePandemicGlow(host, group, shown)
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
