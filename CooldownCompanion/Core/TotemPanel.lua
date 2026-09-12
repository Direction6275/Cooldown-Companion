-- Automatic presentation of Blizzard's occupied totem slots. Slot numbers are
-- addresses, never spell identities. These widgets deliberately stay outside
-- frame.buttons, the spell index, and every aura/cooldown tracking pipeline.
local ADDON_NAME, ST = ...
local Addon = ST.Addon
local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max
local PREVIEW_SLOT_COUNT, PREVIEW_DURATION, PREVIEW_INITIAL_ELAPSED = 3, 20, 8
ST.TOTEM_PANEL_PREVIEW_SLOT_COUNT = PREVIEW_SLOT_COUNT
local playback, playbackSurface

local function PreviewElapsed(groupId)
    if not playback or playback.groupId ~= groupId then return PREVIEW_INITIAL_ELAPSED end
    return playback.elapsed + (playback.startedAt and (GetTime() - playback.startedAt) or 0)
end

function Addon:IsTotemPanelPreviewPlaying(groupId)
    return groupId ~= nil and playback ~= nil and playback.groupId == groupId and playback.startedAt ~= nil
end

-- One geometry contract for the live display, Arrange mode, and config mirror.
-- Live footprints reserve every slot; editing footprints reserve three samples.
function ST.GetTotemPanelGeometry(group, capacity)
    local style = group.style or {}
    local width, height
    if group.displayMode == "bars" then
        width, height = style.barLength or 180, style.barHeight or 20
        if style.barFillVertical then width, height = height, width end
    elseif style.maintainAspectRatio then
        width = style.buttonSize or ST.BUTTON_SIZE
        height = width
    else
        width = style.iconWidth or style.buttonSize or ST.BUTTON_SIZE
        height = style.iconHeight or style.buttonSize or ST.BUTTON_SIZE
    end
    capacity = max(1, capacity or GetNumTotemSlots())
    local perLine = max(1, min(capacity, style.buttonsPerRow or 12))
    local horizontal = ST.GetPanelLayoutOrientation(group.displayMode, style) == "horizontal"
    local cols = horizontal and perLine or ceil(capacity / perLine)
    local rows = horizontal and ceil(capacity / perLine) or perLine
    local spacing = style.buttonSpacing or ST.BUTTON_SPACING
    return {
        width = width, height = height, spacing = spacing, perLine = perLine,
        horizontal = horizontal, capacity = capacity, cols = cols, rows = rows,
        panelWidth = cols * width + (cols - 1) * spacing,
        panelHeight = rows * height + (rows - 1) * spacing,
    }
end

-- Returns a TOPLEFT position in the reserved rectangle, using only public
-- layout inputs. Fixed slot order survives replacements and collapse.
function ST.GetTotemPanelCellPosition(group, geo, index, count)
    local style = group.style or {}
    local origin = style.growthOrigin or "TOPLEFT"
    local right = origin == "TOPRIGHT" or origin == "BOTTOMRIGHT"
    local bottom = origin == "BOTTOMLEFT" or origin == "BOTTOMRIGHT"
    local line = floor((index - 1) / geo.perLine)
    local item = (index - 1) % geo.perLine
    local inLine = min(geo.perLine, count - line * geo.perLine)
    local direction = group.compactGrowthDirection or "center"
    local primaryCapacity = geo.horizontal and geo.cols or geo.rows
    local offset = direction == "end" and (primaryCapacity - inLine)
        or direction == "center" and (primaryCapacity - inLine) / 2 or 0
    local reversed = (geo.horizontal and right) or (not geo.horizontal and bottom)
    if reversed then offset = primaryCapacity - inLine - offset end
    local primary = reversed and (inLine - 1 - item) or item
    primary = primary + offset
    local col = geo.horizontal and primary or (right and geo.cols - 1 - line or line)
    local row = geo.horizontal and (bottom and geo.rows - 1 - line or line) or primary
    return col * (geo.width + geo.spacing), -row * (geo.height + geo.spacing)
end

-- Only fields consumed by shared chrome are translated. No aura-state flags
-- are used to obtain duration styling, and no spell-specific controls run.
local function DisplayStyle(group)
    local style = CopyTable(group.style or {})
    style.showKeybindText = false
    style.showChargeText = false
    style.showAuraText = false
    style.showAuraStackText = false
    style.showTooltips = false
    style.allowPings = false
    style.iconFillEnabled = false
    style.showAssistedHighlight = false
    style.showLossOfControl = false
    style.procGlowStyle = "none"
    style.readyGlowStyle = "none"
    style.keyPressHighlightStyle = "none"
    style.separateTextPositions = false
    return style
end

local function ClearSlot(button)
    button._totemSlotActive = false
    -- Clearing is not an expiry notification. A genuine completion during
    -- a refresh still queues another snapshot so an edge cannot be lost.
    button.cooldown._totemClearing = true
    button.cooldown:Clear()
    button.cooldown._totemClearing = nil
    Addon:UpdateButtonIcon(button, nil)
    if button.timeText then Addon.UnbindDurationText(button.timeText, true) end
    if button.nameText then button.nameText:SetText("") end
    if button.statusBar then
        ST.SetStatusBarImmediateRange(button.statusBar, 0, 1)
        ST.SetStatusBarImmediateValue(button.statusBar, 0)
    end
    button:Hide()
end

local RefreshSurface
local function Expired(cooldown)
    local surface = cooldown._totemPanelSurface
    if not surface or cooldown._totemClearing then return end
    if surface.preview then
        if not Addon:IsTotemPanelPreviewPlaying(surface.groupId) then return end
    elseif surface.arrangePreview and not InCombatLockdown() then return end
    -- Coalesce native completion callbacks into the next event-loop turn.
    -- This is notification delivery, not a cast/totem timing correlation.
    if surface._refreshQueued then return end
    surface._refreshQueued = true
    C_Timer.After(0, function()
        surface._refreshQueued = nil
        if surface:IsVisible() then RefreshSurface(surface) end
    end)
end

local function StyleSlot(button, style)
    button:UpdateStyle(style)
    -- The shared bar restyler reinstalls its cooldown updater. Totem slots
    -- own their native timers, including after every restyle and pool reuse.
    button:SetScript("OnUpdate", nil)
    button.icon:SetDesaturated(false)
    local tint = style.iconTintColor or { 1, 1, 1, 1 }
    button.icon:SetVertexColor(tint[1], tint[2], tint[3], tint[4] or 1)
    button.count:SetText("")
    button.count:Hide()
    button.locCooldown:Hide()
    if button.keybindText then button.keybindText:Hide() end
    button.cooldown:SetUseAuraDisplayTime(false)
    button.cooldown:SetDrawBling(false)
    button.cooldown:SetDrawSwipe(not button._isBar and style.showCooldownSwipe ~= false
        and style.showCooldownSwipeFill ~= false)
    button.cooldown:SetDrawEdge(not button._isBar and style.showCooldownSwipe ~= false
        and style.cooldownSwipeEdgeEnabled == true)
    button.cooldown:SetReverse(style.cooldownSwipeReverse ~= false)
    button.cooldown:SetHideCountdownNumbers(button._isBar or style.showCooldownText == false)
    Addon.ApplyDurationFormatToCooldown(button.cooldown, style)
    if button._isBar then
        button.timeText:SetShown(style.showCooldownText ~= false)
        button.nameText:SetShown(style.showBarNameText ~= false)
    end
    if (style.auraGlowStyle or "pulse") ~= "none" and not button._totemGlow then
        button._totemGlow = ST._BuildKitGlowRegions(button, false, false)
    end
    if button._totemGlow then
        button._totemGlow.host:SetFrameLevel(button:GetFrameLevel() + 30)
        ST._StyleKitGlowRegions(button._totemGlow, style, button._barBounds or button,
            (style.auraGlowStyle or "pulse") ~= "none")
    end
    ST.SetFrameClickThroughRecursive(button, true, true)
end

local function EnsureSlots(surface, group)
    local capacity = surface.preview and PREVIEW_SLOT_COUNT or GetNumTotemSlots()
    surface.capacity = capacity
    local mode = group.displayMode == "bars" and "bars" or "icons"
    local style = DisplayStyle(group)
    surface.style = style
    -- Separate bounded pools also cover switching profiles onto an existing
    -- frame id whose saved subtype/display mode differs.
    for _, pool in pairs(surface.pools) do
        for _, button in ipairs(pool) do ClearSlot(button) end
    end
    local pool = surface.pools[mode]
    surface.slots = pool
    for slot = 1, capacity do
        local button = pool[slot]
        if not button then
            local data = { type = "totem", totemSlot = slot, name = "Totem" }
            button = mode == "bars" and Addon:CreateBarFrame(surface, slot, data, style)
                or Addon:CreateButtonFrame(surface, slot, data, style)
            -- Shared factories provide chrome only. These widgets never run
            -- ordinary spell/item updates or enroll in aura ownership.
            button.UpdateCooldown = nil
            button:SetScript("OnUpdate", nil)
            button:SetScript("OnEnter", nil)
            button:SetScript("OnLeave", nil)
            button.cooldown._totemPanelSurface = surface
            button.cooldown:SetScript("OnCooldownDone", Expired)
            pool[slot] = button
        end
        StyleSlot(button, style)
    end
end

function ST.LayoutTotemPanelSurface(surface, group)
    local active = surface.active
    for index, button in ipairs(active) do
        local x, y = ST.GetTotemPanelCellPosition(group, surface.geo, index, #active)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", surface, "TOPLEFT", x, y)
        button:Show()
    end
end

-- Static examples are only used in explicitly labelled editing surfaces.
-- No sample has a spell id and none is saved as a tracked entry.
local PREVIEW_ICONS = { 136098, 136102, 136114 }
local function RenderSample(surface, button, slot, playing)
    Addon:UpdateButtonIcon(button, PREVIEW_ICONS[slot])
    button.cooldown._totemClearing = true
    button.cooldown:Clear()
    button.cooldown._totemClearing = nil
    if button._isBar then button.nameText:SetText("Totem " .. slot) end
    if not playing then
        -- Match ordinary panel mirrors: idle samples show only their saved
        -- appearance, with no glow, duration text, swipe, or timed bar fill.
        button.cooldown:Hide()
        if button._isBar then
            Addon.UnbindDurationText(button.timeText, true)
            ST.SetStatusBarImmediateRange(button.statusBar, 0, 1)
            ST.SetStatusBarImmediateValue(button.statusBar, 1)
        end
        return
    end
    local elapsed = (PreviewElapsed(surface.groupId) + (slot - 1) * 4) % PREVIEW_DURATION
    local start = GetTime() - elapsed
    button.cooldown:Resume()
    button.cooldown:SetCooldown(start, PREVIEW_DURATION)
    button.cooldown:Show()
    if button._isBar then
        local duration = button._totemPreviewDuration
        if not duration then
            duration = C_DurationUtil.CreateDuration()
            button._totemPreviewDuration = duration
        end
        duration:SetTimeFromStart(start, PREVIEW_DURATION, 1)
        ST.SetStatusBarTimerDuration(button.statusBar, duration, ST.STATUS_BAR_TIMER_DIRECTION_REMAINING)
        if surface.style.showCooldownText ~= false then
            Addon.BindDurationText(button.timeText, duration, surface.style, true)
        else
            Addon.UnbindDurationText(button.timeText, true)
        end
    end
end

RefreshSurface = function(surface)
    if surface._refreshing then return end
    local group = surface.previewGroup or (Addon.db.profile.groups[surface.groupId])
    if not ST.IsTotemPanelGroup(group) then return end
    surface._refreshing = true
    wipe(surface.active)
    local preview = surface.preview or (surface.arrangePreview and not InCombatLockdown())
    local playing = surface.preview and Addon:IsTotemPanelPreviewPlaying(surface.groupId)
    local previousCapacity = surface.geo and surface.geo.capacity
    surface.geo = ST.GetTotemPanelGeometry(group, preview and PREVIEW_SLOT_COUNT or surface.capacity)
    local frame = not surface.preview and Addon.groupFrames[surface.groupId]
    if frame then
        -- The mover, resize grip, and display must measure the same cells.
        frame.visibleButtonCount = surface.geo.capacity
    end
    for slot = 1, surface.capacity do
        local button = surface.slots[slot]
        local duration = not preview and GetTotemDuration(slot) or nil
        local active = preview or ST.EntryRuntime.DurationObjectShowsCooldown(duration)
        -- Never derive layout from a secret boolean. If a client changes this
        -- native-widget contract, fail closed instead of showing an old slot.
        if issecretvalue(active) then active = false end
        if preview and slot > PREVIEW_SLOT_COUNT then active = false end
        if active then
            if button._totemGlow then button._totemGlow.host:SetShown(not preview or playing) end
            button._totemSlotActive = true
            if preview then
                RenderSample(surface, button, slot, playing)
            else
                local _, name, _, _, texture = GetTotemInfo(slot)
                Addon:UpdateButtonIcon(button, texture)
                button.cooldown:Resume()
                button.cooldown:SetCooldownFromDurationObject(duration)
                button.cooldown:Show()
                if button._isBar then
                    -- Name and texture stay paired with this exact slot's
                    -- duration; both are secret-safe display pass-throughs.
                    if issecretvalue(name) then button.nameText:SetText(name)
                    else button.nameText:SetText(name or "") end
                    ST.SetStatusBarTimerDuration(button.statusBar, duration,
                        ST.STATUS_BAR_TIMER_DIRECTION_REMAINING)
                    if surface.style.showCooldownText ~= false then
                        Addon.BindDurationText(button.timeText, duration, surface.style, true)
                    else
                        Addon.UnbindDurationText(button.timeText, true)
                    end
                end
            end
            surface.active[#surface.active + 1] = button
        else
            ClearSlot(button)
        end
    end
    ST.LayoutTotemPanelSurface(surface, group)
    surface._refreshing = nil
    if frame and previousCapacity and previousCapacity ~= surface.geo.capacity then
        Addon:ResizeGroupFrame(surface.groupId)
        ST._GroupFrame.UpdateResizedPanelContainerWrapper(surface.groupId)
    end
end

local EVENTS = { "PLAYER_TOTEM_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }
local serial = 0
function ST.CreateTotemPanelSurface(parent, groupId, preview)
    serial = serial + 1
    local surface = CreateFrame("Frame", "CooldownCompanionTotems" .. serial, parent)
    surface.groupId, surface.preview = groupId, preview
    surface.pools = { icons = {}, bars = {} }
    surface.active = {}
    surface:EnableMouse(false)
    if not preview then
        surface:SetScript("OnEvent", function() RefreshSurface(surface) end)
        surface:SetScript("OnShow", function()
            for _, event in ipairs(EVENTS) do surface:RegisterEvent(event) end
            if surface.slots then RefreshSurface(surface) end
        end)
    end
    surface:SetScript("OnHide", function()
        surface:UnregisterAllEvents()
        surface._refreshing = true
        for _, button in ipairs(surface.slots or {}) do ClearSlot(button) end
        surface._refreshing = nil
    end)
    return surface
end

function ST.UpdateTotemPanelSurface(surface, group)
    surface._refreshing = true
    EnsureSlots(surface, group)
    surface._refreshing = nil
    if surface.preview then
        surface.previewGroup = group
        if surface.groupId then playbackSurface = surface end
    end
    if not surface.preview and surface:IsVisible() then
        for _, event in ipairs(EVENTS) do surface:RegisterEvent(event) end
    end
    RefreshSurface(surface)
end

function Addon:PopulateTotemPanel(groupId)
    local frame, group = self.groupFrames[groupId], self.db.profile.groups[groupId]
    if not (frame and ST.IsTotemPanelGroup(group)) then return end
    self:EnforceTotemPanelInvariants(group)
    local surface = frame._totemPanelSurface
    if not surface then
        surface = ST.CreateTotemPanelSurface(frame, groupId, false)
        surface:SetAllPoints(frame)
        frame._totemPanelSurface = surface
    end
    ST.UpdateTotemPanelSurface(surface, group)
    surface:Show()
    frame.layoutButtonCount = nil
    frame._layoutDirty = false
end

function Addon:SetTotemPanelPreviewShown(frame, shown)
    local surface = frame and frame._totemPanelSurface
    if not surface or surface.arrangePreview == (shown == true) then return end
    surface.arrangePreview = shown == true
    RefreshSurface(surface)
end

-- Playback belongs exclusively to the focused config mirror. No live slot,
-- Arrange sample, or read-only overview consumes this editing clock.
function Addon:SetTotemPanelPreviewPlaying(groupId, shown)
    if not ST.IsTotemPanelGroup(self.db.profile.groups[groupId]) then return end
    if not playback or playback.groupId ~= groupId then
        playback = {groupId = groupId, elapsed = PREVIEW_INITIAL_ELAPSED}
    end
    local elapsed = PreviewElapsed(groupId)
    playback.elapsed = elapsed % PREVIEW_DURATION
    playback.startedAt = shown and GetTime() or nil
    if playbackSurface and playbackSurface.groupId == groupId and playbackSurface:IsVisible() then
        RefreshSurface(playbackSurface)
    end
end

function Addon:ClearAllTotemPanelPreviews()
    if playback and playback.startedAt then
        local elapsed = PreviewElapsed(playback.groupId)
        playback.elapsed, playback.startedAt = elapsed % PREVIEW_DURATION, nil
        if playbackSurface and playbackSurface:IsVisible() then RefreshSurface(playbackSurface) end
    end
end
