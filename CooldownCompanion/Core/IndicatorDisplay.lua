-- Shared saved-design painting. Native kits are created/styled only by AuraDisplay.
-- These helpers retain no native slot references and never read aura state.
local _, ST = ...
local Addon, I = ST.Addon, ST.Indicator
local WHITE = {1, 1, 1, 1}

function I.CreateVisual(host, nativeSlot)
    if host.indicatorReadouts then return end
    Addon.EnsureTriggerIconVisual(host)
    Addon.EnsureTriggerTextVisual(host)
    local root = CreateFrame("Frame", nil, host.visualRoot)
    root:SetAllPoints(host.visualRoot)
    root:EnableMouse(false)
    local readouts = {root = root, frames = {}}
    for _, key in ipairs({"label", "timer", "count"}) do
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

local function StyleReadouts(host, group)
    local settings = I.Settings(group)
    local text, options = settings.text, settings.readouts
    local color = text.textFontColor or WHITE
    local font = Addon:FetchFont(text.textFont or "Friz Quadrata TT")
    local readouts = host.indicatorReadouts
    readouts.root:Show()
    for _, key in ipairs({"label", "timer", "count"}) do
        local fs = readouts[key]
        fs:SetFont(font, text.textFontSize or 20, text.textFontOutline or "OUTLINE")
        fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
        fs:ClearAllPoints()
        local anchor = options[key .. "Anchor"] or (key == "label" and "TOP" or key == "count" and "BOTTOM" or "CENTER")
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

function I.StyleVisual(host, group)
    local settings = I.Settings(group)
    if not settings then return false end
    local visual = I.NativeSettings(group)
    if not visual or visual.enabled == false then return false end
    local geometry, alpha = Addon:GetTexturePanelRenderGeometry(visual)
    if not geometry then return false end
    host.visualRoot:SetSize(geometry.boundsWidth, geometry.boundsHeight)
    Addon:ResetTextureIndicatorRootState(host)
    Addon.HideStandaloneDisplayVisuals(host)
    host.indicatorProgress.clip:SetAlpha(0)
    host._indicatorDimAlpha = nil
    host._activeDisplayType = settings.displayType
    local shown = true
    if settings.displayType == "icon" then
        local icon = I.IconSettings(group)
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
    elseif settings.legacyTextMetrics then
        -- Migrated trigger messages keep their existing metrics/background.
        Addon.ApplyTriggerTextVisual(host, settings.text)
        geometry.boundsWidth, geometry.boundsHeight = Addon.GetTriggerTextDisplayMetrics(host.textFrame.text, settings.text)
    else
        host._triggerTextBaseColor = CopyTable(settings.text.textFontColor or WHITE)
        host.textFrame.bg:SetColorTexture(unpack(settings.text.textBgColor or {0, 0, 0, 0}))
        host.textFrame:SetSize(geometry.boundsWidth, geometry.boundsHeight)
        host.textFrame.text:SetFont(Addon:FetchFont(settings.text.textFont or "Friz Quadrata TT"),
            settings.text.textFontSize or 20, settings.text.textFontOutline or "OUTLINE")
        host.textFrame.text:SetText("")
        host.textFrame:Show()
    end
    StyleReadouts(host, group)
    if settings.legacyTextMetrics then host.indicatorReadouts.frames.label:SetAlpha(0) end
    return shown, geometry.boundsWidth, geometry.boundsHeight
end

function I.UpdateReadouts(host, driver, group, previewFraction)
    local settings, readouts = I.Settings(group), host.indicatorReadouts
    local options = settings.readouts
    local preview = previewFraction ~= nil
    if preview then
        Addon.UnbindDurationText(readouts.timer, true)
        readouts.timer:SetText(options.timer and previewFraction > 0 and Addon.FormatTime(previewFraction * 20, options) or "")
        readouts.count:SetText(options.count ~= "none" and "3" or "")
    elseif not I.IsAura(group) then
        local duration = driver and (driver._chargeRecharging and driver._chargeDurationObj or driver._durationObj)
        local itemDuration = driver and driver._itemCdDuration or 0
        local itemRemaining = itemDuration > 0 and math.max(0, itemDuration - (GetTime() - (driver._itemCdStart or 0))) or 0
        if options.timer and duration then
            Addon.BindDurationText(readouts.timer, duration, options, false, "cooldown")
        else
            Addon.UnbindDurationText(readouts.timer, true)
            if options.timer and itemRemaining > 0 then readouts.timer:SetText(Addon.FormatTime(itemRemaining, options)) end
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
            if duration then
                host.indicatorProgress.bar:SetTimerDuration(duration, ST.STATUS_BAR_INTERPOLATION_SMOOTH,
                    ST.STATUS_BAR_TIMER_DIRECTION_REMAINING)
            elseif itemDuration > 0 then
                host.indicatorProgress.bar:SetMinMaxValues(0, itemDuration)
                host.indicatorProgress.bar:SetValue(itemRemaining)
            else
                host.indicatorProgress.clip:SetAlpha(0)
                host._indicatorDimAlpha = nil
                local visual = I.NativeSettings(group)
                local geometry, alpha = Addon:GetTexturePanelRenderGeometry(visual)
                ST._AT.LayoutTexturePieces(host, visual, geometry, alpha)
            end
        end
    end
    if preview then
        host.indicatorProgress.bar:SetMinMaxValues(0, 1)
        host.indicatorProgress.bar:SetValue(previewFraction)
    end
end

function I.Render(host, driver, group, preview, fraction, effectsActive)
    I.CreateVisual(host)
    local shown, width, height = I.StyleVisual(host, group)
    if not shown then return false end
    host:SetSize(width, height)
    I.UpdateReadouts(host, driver, group, (preview or I.IsAura(group)) and (fraction or 0.5) or nil)
    if not I.IsAura(group) and not preview then
        Addon:ApplyTriggerPanelEffects(host, driver, group, effectsActive == true)
    end
    return true
end

-- Called only by the native aura owner's gated bind. No live updates use this.
function I.StyleAura(slot, group, driver)
    local host = slot.kit.texturePanelHost
    slot.slotButton:ClearIcon()
    local shown = I.StyleVisual(host, group)
    local settings = I.Settings(group)
    local source = I.Primary(group)
    if settings.displayType == "icon" and not settings.icon.manualIcon and not (source and source.manualIcon) then
        slot.slotButton:SetIcon(host.iconFrame.icon)
    end
    local formatter = Addon.GetDurationTextFormatter(settings.readouts, false, "aura")
    slot.slotButton:SetDurationText(host.indicatorReadouts.timer, {textFormatter = formatter})
    slot.slotButton:SetApplicationCount(host.indicatorReadouts.count)
    host.visualRoot:SetAlpha(shown and 1 or 0)
    return shown
end

function I.ReleaseVisual(host)
    if not host or not host.indicatorReadouts then return end
    ST._AT.StopAllTextureIndicatorEffects(host)
    Addon.UnbindDurationText(host.indicatorReadouts.timer, true)
    host.indicatorReadouts.root:Hide()
    host.indicatorProgress.clip:SetAlpha(0)
end
